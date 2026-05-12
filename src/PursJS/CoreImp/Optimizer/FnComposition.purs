-- | Ports `inlineFnComposition` from
-- | `Language.PureScript.CoreImp.Optimizer.Inliner` (purescript@c4a35b3,
-- | src/Language/PureScript/CoreImp/Optimizer/Inliner.hs:248-274).
-- |
-- | The only monadic optimizer pass — it uses `freshName` to coin a binder
-- | for the lambda parameter when partially-applied compose is eta-expanded.
-- |
-- |   (f <<< g) x  →  f (g x)                              (saturated form)
-- |   (f <<< g)    →  function ($N) { return f(g($N)); }   (eta form)
-- |
-- | In a multi-level compose like `(f <<< g <<< h) x`, the algorithm walks down
-- | left-associated compose calls in `goApps` and reconstructs the nested
-- | application chain in `mkApps`. The Haskell uses view-pattern matching with
-- | the `expander` arrow; here we lift that into explicit `case ... of` steps
-- | via the `isComposeAppliedToFnDict` helper.
-- |
-- | Mapping (PursJS <-> Inliner.hs line):
-- |   inlineFnComposition       Inliner.hs:248-257
-- |   mkApps                    Inliner.hs:259-264
-- |   mkApp                     Inliner.hs:266-267
-- |   goApps                    Inliner.hs:269-274
module PursJS.CoreImp.Optimizer.FnComposition
  ( inlineFnComposition
  ) where

import Prelude

import Data.Array as Array
import Data.Either (Either(..), either)
import Data.Foldable (foldr)
import Data.Maybe (Maybe(..))
import Data.Tuple (Tuple(..))
import PursJS.CodeGen.Supply (Supply, freshName)
import PursJS.CoreImp.AST (AST(..), InitializerEffects(..))
import PursJS.CoreImp.Optimizer.Constants (Ref, p_compose, p_composeFlipped, p_semigroupoidFn)
import PursJS.CoreImp.Traversals (everywhereTopDownM)
import PursJS.Names (ModuleName)
import PursJS.PSString (PSString)

isRef :: Ref -> AST -> Boolean
isRef (Tuple mn name) (ModuleAccessor _ mn' name') = mn == mn' && name == name'
isRef _ _ = false

-- | Match `App _ (Ref compose-or-composeFlipped) [Ref semigroupoidFn]` after expansion.
-- | Returns Just (whether-it's-flipped) on a hit.
isComposeAppliedToFnDict :: (AST -> AST) -> AST -> Maybe Boolean
isComposeAppliedToFnDict expander ast = case expander ast of
  App _ fn [dict]
    | isRef p_semigroupoidFn dict ->
        if isRef p_compose fn then Just false
        else if isRef p_composeFlipped fn then Just true
        else Nothing
  _ -> Nothing

inlineFnComposition :: (AST -> AST) -> AST -> Supply AST
inlineFnComposition expander = everywhereTopDownM convert
  where
  convert :: AST -> Supply AST
  convert ast = case trySaturated ast of
    Just r -> r
    Nothing -> case tryEta ast of
      Just r -> r
      Nothing -> pure ast

  -- Saturated form: compose(dict)(x)(y)(z) -> x (y z)
  --   Tree: App s1 (App s2 (App _ inner [x]) [y]) [z]   where expander(inner) = App _ (Ref compose) [Ref semigroupoidFn]
  trySaturated :: AST -> Maybe (Supply AST)
  trySaturated (App s1 (App s2 (App _ inner [x]) [y]) [z]) =
    case isComposeAppliedToFnDict expander inner of
      Just false -> Just (pure (App s1 x [App s2 y [z]]))
      Just true -> Just (pure (App s2 y [App s1 x [z]]))
      Nothing -> Nothing
  trySaturated _ = Nothing

  -- Eta form: compose(dict)(x)(y)  -> function ($N) { vars; return x (y $N) }
  --   Tree: App ss (App _ inner _) _   where expander(inner) is the compose-dict ref pair
  tryEta :: AST -> Maybe (Supply AST)
  tryEta app@(App ss (App _ inner _) _) =
    case isComposeAppliedToFnDict expander inner of
      Just _ -> Just $ do
        fns <- goApps app
        a <- freshName
        pure (mkApps ss fns a)
      Nothing -> Nothing
  tryEta _ = Nothing

  mkApps :: Maybe _ -> Array (Either AST (Tuple String AST)) -> String -> AST
  mkApps ss fns a =
    let vars = Array.mapMaybe rightsOnly fns
        varDecls = map (\(Tuple name e) -> VariableIntroduction ss name (Just (Tuple UnknownEffects e))) vars
        comp = Function ss Nothing [a]
                 (Block ss [Return Nothing (foldr step (Var ss a) fns)])
    in App ss
         (Function ss Nothing []
           (Block ss (varDecls <> [Return Nothing comp])))
         []
    where
    rightsOnly :: Either AST (Tuple String AST) -> Maybe (Tuple String AST)
    rightsOnly (Right t) = Just t
    rightsOnly (Left _) = Nothing

    step :: Either AST (Tuple String AST) -> AST -> AST
    step fn acc = App ss (mkApp fn) [acc]

    mkApp :: Either AST (Tuple String AST) -> AST
    mkApp = either identity (\(Tuple name _) -> Var Nothing name)

  goApps :: AST -> Supply (Array (Either AST (Tuple String AST)))
  goApps (App _ (App _ inner [x]) [y]) =
    case isComposeAppliedToFnDict expander inner of
      Just false -> (<>) <$> goApps x <*> goApps y
      Just true -> (<>) <$> goApps y <*> goApps x
      Nothing -> singleton (App Nothing (App Nothing inner [x]) [y])
  goApps app@(App _ _ _) = singleton app
  goApps other = pure [Left other]

  singleton :: AST -> Supply (Array (Either AST (Tuple String AST)))
  singleton ast = do
    n <- freshName
    pure [Right (Tuple n ast)]

-- Avoid unused-import lint
_unused :: { mn :: ModuleName -> ModuleName, str :: PSString -> PSString }
_unused = { mn: identity, str: identity }
