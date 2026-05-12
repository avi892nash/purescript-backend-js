-- | Tail-call elimination. Rewrites a tail-recursive top-level binding
-- |
-- |   var spin = function (v) { return spin(v); };
-- |
-- | into a `$tco_loop` while loop:
-- |
-- |   var spin = function ($copy_v) {
-- |       var $tco_var_v = $copy_v;
-- |       var $tco_done = false;
-- |       var $tco_result;
-- |       function $tco_loop(v) {
-- |           $tco_var_v = v;
-- |           return;
-- |       };
-- |       while (!$tco_done) {
-- |           $tco_result = $tco_loop($tco_var_v);
-- |       };
-- |       return $tco_result;
-- |   };
-- |
-- | Mirrors `Language.PureScript.CoreImp.Optimizer.TCO.tco` for the
-- | single-function recursion case (no mutual-recursion yet).
module PursJS.CoreImp.Optimizer.TCO
  ( tco
  ) where

import Prelude

import Control.Monad.State (State, evalState, get, put)
import Data.Array as Array
import Data.Foldable (sum)
import Data.Maybe (Maybe(..))
import Data.Set (Set)
import Data.Set as Set
import Data.Traversable (traverse)
import Data.Tuple (Tuple(..))
import PursJS.CoreImp.AST (AST(..), InitializerEffects(..), UnaryOperator(..))
import PursJS.CoreImp.Traversals (everything, everywhereTopDownM)

type S a = State Int a

tcoVar :: String -> String
tcoVar arg = "$tco_var_" <> arg

copyVar :: String -> String
copyVar arg = "$copy_" <> arg

tcoLoopName :: String
tcoLoopName = "$tco_loop"

tcoResultName :: String
tcoResultName = "$tco_result"

tcoDoneM :: S String
tcoDoneM = do
  n <- get
  pure ("$tco_done" <> if n == 0 then "" else show n)

bumpDone :: S Unit
bumpDone = get >>= \n -> put (n + 1)

tco :: AST -> AST
tco ast = evalState (everywhereTopDownM convert ast) 0
  where
  convert :: AST -> S AST
  convert (VariableIntroduction ss name (Just (Tuple p fn@(Function _ _ _ _)))) =
    let { argss, body, replace } = topCollectAllFunctionArgs [] identity fn
        innerArgs = case Array.head argss of
          Just args -> args
          Nothing -> []
        outerArgs = Array.concat (Array.reverse (Array.drop 1 argss))
        arity = Array.length argss
    in case findTailRecursiveFns name arity body of
      Nothing -> pure (VariableIntroduction ss name (Just (Tuple p fn)))
      Just trFns -> do
        loopified <- toLoop trFns name arity outerArgs innerArgs body
        pure (VariableIntroduction ss name (Just (Tuple p (replace loopified))))
  convert other = pure other

-- | Walk the chain of nested `function (a) { return function (b) { ... } }`,
-- | collecting all arg lists. Returns the args, the deepest body, and a
-- | reconstructor function to put the body back into the function shape.
rewriteFunctionsWith
  :: (Array String -> Array String)
  -> Array (Array String)
  -> (AST -> AST)
  -> AST
  -> { argss :: Array (Array String), body :: AST, replace :: AST -> AST }
rewriteFunctionsWith argMapper = collectAllFunctionArgs
  where
  -- function ident (args) { return ...body... }
  collectAllFunctionArgs allArgs f (Function s1 ident args (Block s2 stmts))
    | Just { head: ret@(Return _ _) } <- Array.uncons stmts =
        collectAllFunctionArgs (Array.cons args allArgs)
          (\b -> f (Function s1 ident (argMapper args) (Block s2 [b])))
          ret
  -- function ident (args) <some non-trivial body>
  collectAllFunctionArgs allArgs f (Function ss ident args body@(Block _ _)) =
    { argss: Array.cons args allArgs
    , body
    , replace: f <<< Function ss ident (argMapper args)
    }
  -- return function ident (args) { <single stmt> }
  collectAllFunctionArgs allArgs f (Return s1 (Function s2 ident args (Block s3 [single]))) =
    collectAllFunctionArgs (Array.cons args allArgs)
      (\b -> f (Return s1 (Function s2 ident (argMapper args) (Block s3 [b]))))
      single
  -- return function ident (args) <non-trivial body>
  collectAllFunctionArgs allArgs f (Return s1 (Function s2 ident args body@(Block _ _))) =
    { argss: Array.cons args allArgs
    , body
    , replace: f <<< Return s1 <<< Function s2 ident (argMapper args)
    }
  collectAllFunctionArgs allArgs f body =
    { argss: allArgs, body, replace: f }

topCollectAllFunctionArgs :: Array (Array String) -> (AST -> AST) -> AST -> { argss :: Array (Array String), body :: AST, replace :: AST -> AST }
topCollectAllFunctionArgs = rewriteFunctionsWith (map copyVar)

innerCollectAllFunctionArgs :: Array (Array String) -> (AST -> AST) -> AST -> { argss :: Array (Array String), body :: AST, replace :: AST -> AST }
innerCollectAllFunctionArgs = rewriteFunctionsWith identity

countReferences :: String -> AST -> Int
countReferences ident = everything (+) match
  where
  match (Var _ id') | id' == ident = 1
  match _ = 0

-- | If `ident` is a tail-recursive function with `arity` arg lists, return the
-- | set of identifiers (including itself) that all behave tail-recursively.
-- | Returns Nothing if `ident` is not tail-recursive.
findTailRecursiveFns :: String -> Int -> AST -> Maybe (Set String)
findTailRecursiveFns ident arity js =
  if countReferences ident js > 0
    then go Set.empty (Set.singleton (Tuple ident arity))
    else Nothing
  where
  go :: Set String -> Set (Tuple String Int) -> Maybe (Set String)
  go known required = case Set.findMin required of
    Just r@(Tuple iden _) -> do
      required'' <- findTailPositionDeps r js
      let required' = Set.delete r required
          known' = Set.insert iden known
          required2 = Set.union required' (Set.filter (\(Tuple iden2 _) -> not (Set.member iden2 known')) required'')
      go known' required2
    Nothing -> Just known

findTailPositionDeps :: Tuple String Int -> AST -> Maybe (Set (Tuple String Int))
findTailPositionDeps (Tuple ident arity) = allInTailPosition
  where
  selfRefCount = countReferences ident

  allInTailPosition (Return _ expr)
    | isSelfCall ident arity expr =
        if selfRefCount expr == 1 then Just Set.empty else Nothing
    | otherwise =
        if selfRefCount expr == 0 then Just Set.empty else Nothing
  allInTailPosition (While _ cond body)
    | selfRefCount cond == 0 = allInTailPosition body
    | otherwise = Nothing
  allInTailPosition (For _ _ lo hi body)
    | selfRefCount lo == 0 && selfRefCount hi == 0 = allInTailPosition body
    | otherwise = Nothing
  allInTailPosition (ForIn _ _ obj body)
    | selfRefCount obj == 0 = allInTailPosition body
    | otherwise = Nothing
  allInTailPosition (IfElse _ cond t f)
    | selfRefCount cond == 0 = do
        a <- allInTailPosition t
        b <- case f of
          Just fb -> allInTailPosition fb
          Nothing -> Just Set.empty
        Just (Set.union a b)
    | otherwise = Nothing
  allInTailPosition (Block _ body) =
    foldMapA allInTailPosition body
  allInTailPosition (Throw _ js')
    | selfRefCount js' == 0 = Just Set.empty
    | otherwise = Nothing
  allInTailPosition (ReturnNoResult _) = Just Set.empty
  allInTailPosition (VariableIntroduction _ _ Nothing) = Just Set.empty
  allInTailPosition (VariableIntroduction _ ident' (Just (Tuple _ js')))
    | selfRefCount js' == 0 = Just Set.empty
    | otherwise = case js' of
        Function _ Nothing _ _ ->
          let r = innerCollectAllFunctionArgs [] identity js'
          in Set.insert (Tuple ident' (Array.length r.argss)) <$> allInTailPosition r.body
        _ -> Nothing
  allInTailPosition (Assignment _ _ js')
    | selfRefCount js' == 0 = Just Set.empty
    | otherwise = Nothing
  allInTailPosition (Comment _ js') = allInTailPosition js'
  allInTailPosition _ = Nothing

foldMapA :: forall a. (a -> Maybe (Set (Tuple String Int))) -> Array a -> Maybe (Set (Tuple String Int))
foldMapA f arr = Array.foldM (\acc x -> Set.union acc <$> f x) Set.empty arr

isSelfCall :: String -> Int -> AST -> Boolean
isSelfCall ident 1 (App _ (Var _ ident') _) = ident == ident'
isSelfCall ident n (App _ fn _) | n > 0 = isSelfCall ident (n - 1) fn
isSelfCall _ _ _ = false

toLoop :: Set String -> String -> Int -> Array String -> Array String -> AST -> S AST
toLoop trFns ident arity outerArgs innerArgs js = do
  tcoDone <- tcoDoneM
  bumpDone

  let
    rootSS = Nothing

    markDone ss = Assignment ss (Var ss tcoDone) (BooleanLiteral ss true)

    loopify :: AST -> AST
    loopify (Return ss ret)
      | isSelfCall ident arity ret =
          let allArgs = Array.concat (collectArgs [] ret)
              tcoVarAssigns = Array.zipWith
                (\val arg -> Assignment ss (Var ss (tcoVar arg)) val)
                allArgs outerArgs
              copyAssigns = Array.zipWith
                (\val arg -> Assignment ss (Var ss (copyVar arg)) val)
                (Array.drop (Array.length outerArgs) allArgs) innerArgs
          in Block ss (tcoVarAssigns <> copyAssigns <> [ReturnNoResult ss])
      | isIndirectSelfCall ret = Return ss ret
      | otherwise = Block ss [markDone ss, Return ss ret]
    loopify (ReturnNoResult ss) = Block ss [markDone ss, ReturnNoResult ss]
    loopify (While ss cond body) = While ss cond (loopify body)
    loopify (For ss i lo hi body) = For ss i lo hi (loopify body)
    loopify (ForIn ss i obj body) = ForIn ss i obj (loopify body)
    loopify (IfElse ss cond t f) = IfElse ss cond (loopify t) (map loopify f)
    loopify (Block ss body) = Block ss (map loopify body)
    loopify (VariableIntroduction ss f (Just (Tuple p fn@(Function _ Nothing _ _))))
      | Set.member f trFns =
          let r = innerCollectAllFunctionArgs [] identity fn
          in VariableIntroduction ss f (Just (Tuple p (r.replace (loopify r.body))))
    loopify other = other

    collectArgs :: Array (Array AST) -> AST -> Array (Array AST)
    collectArgs acc (App _ fn args) = collectArgs (Array.cons args acc) fn
    collectArgs acc _ = acc

    isIndirectSelfCall :: AST -> Boolean
    isIndirectSelfCall (App _ (Var _ id') _) = Set.member id' trFns
    isIndirectSelfCall (App _ fn _) = isIndirectSelfCall fn
    isIndirectSelfCall _ = false

  pure $ Block rootSS $
    map (\arg -> VariableIntroduction rootSS (tcoVar arg)
                   (Just (Tuple UnknownEffects (Var rootSS (copyVar arg))))) outerArgs <>
    [ VariableIntroduction rootSS tcoDone (Just (Tuple UnknownEffects (BooleanLiteral rootSS false)))
    , VariableIntroduction rootSS tcoResultName Nothing
    , Function rootSS (Just tcoLoopName) (outerArgs <> innerArgs) (Block rootSS [loopify js])
    , While rootSS (Unary rootSS Not (Var rootSS tcoDone))
        (Block rootSS
          [ Assignment rootSS (Var rootSS tcoResultName)
              (App rootSS (Var rootSS tcoLoopName)
                (map (Var rootSS <<< tcoVar) outerArgs <> map (Var rootSS <<< copyVar) innerArgs))
          ])
    , Return rootSS (Var rootSS tcoResultName)
    ]

-- Avoid unused warnings
_unused :: Int
_unused = sum [0]
