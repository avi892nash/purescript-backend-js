-- | Ports the `mkFn` / `runFn` family of inliners from
-- | `Language.PureScript.CoreImp.Optimizer.Inliner` (purescript@c4a35b3,
-- | src/Language/PureScript/CoreImp/Optimizer/Inliner.hs:189-234).
-- |
-- | These rewrite:
-- |
-- |   mkFnN(\a1 -> \a2 -> ... -> \aN -> body)
-- |     → function (a1, a2, ..., aN) { return body; }
-- |
-- |   runFnN(f)(a1)(a2)...(aN)
-- |     → f(a1, a2, ..., aN)
-- |
-- | For the Eff/Effect/ST variants the result is wrapped in an extra
-- | `function () { return ...; }` thunk so the effect is delayed.
-- |
-- | Mapping (PursJS <-> Inliner.hs line):
-- |   mkFnInliner               Inliner.hs:189-191 + 197-213 (mkFn / mkFn')
-- |   mkEffFnInliner            Inliner.hs:193-195 (mkEffFn)
-- |   runFnInliner              Inliner.hs:218-219 (runFn) + 225-234 (runFn')
-- |   runEffFnInliner           Inliner.hs:221-223 (runEffFn)
module PursJS.CoreImp.Optimizer.Uncurried
  ( mkUncurriedInliners
  ) where

import Prelude

import Data.Array as Array
import Data.Foldable (foldr)
import Data.Maybe (Maybe(..))
import Data.Tuple (Tuple(..))
import PursJS.CoreImp.AST (AST(..))
import PursJS.CoreImp.Optimizer.Constants (Ref, p_mkEffFn, p_mkEffectFn, p_mkFn, p_mkSTFn, p_runEffFn, p_runEffectFn, p_runFn, p_runSTFn)
import PursJS.PSString (mkString, runPSString)

-- | Match a ModuleAccessor against a prefix-Ref plus arity:
-- |   `isNFn (M, "mkEffectFn") 2 (App ModuleAccessor M "mkEffectFn2")` → true.
isNFn :: Ref -> Int -> AST -> Boolean
isNFn (Tuple m prefix) n (ModuleAccessor _ m' name') =
  m == m' && runPSString name' == runPSString prefix <> show n
isNFn _ _ _ = false

-- | Collect args from a chain of single-arg `Function`s:
-- |   `function (a) { return function (b) { return ...; } }`
-- |   → Just ([a, b], [returnBody])
-- | Walks `n` levels deep. Returns Nothing if the shape doesn't match.
collectArgs :: Int -> Int -> Array String -> AST -> Maybe { args :: Array String, stmts :: Array AST }
collectArgs total m acc fn
  | m == 1 = case fn of
      Function _ Nothing [oneArg] (Block _ js) | Array.length acc == total - 1 ->
        Just { args: Array.reverse (Array.cons oneArg acc), stmts: js }
      _ -> Nothing
  | otherwise = case fn of
      Function _ Nothing [oneArg] (Block _ [Return _ ret]) ->
        collectArgs total (m - 1) (Array.cons oneArg acc) ret
      _ -> Nothing

-- | `mkFn'` from Inliner.hs:197-213, parametrised by the result-building
-- | `res` function (which differs between mkFn / mkEffFn).
mkFnHelper
  :: Ref
  -> ({ ss1 :: _, ss2 :: _, ss3 :: _, args :: Array String, body :: AST } -> AST)
  -> Int
  -> AST
  -> AST
mkFnHelper mkFn_ res 0 = convert
  where
  convert (App _ ref [Function s1 Nothing [_] (Block s2 [Return s3 js])])
    | isNFn mkFn_ 0 ref =
        res { ss1: s1, ss2: s2, ss3: s3, args: [], body: js }
  convert other = other
mkFnHelper mkFn_ res n = convert
  where
  convert orig@(App ss ref [fn])
    | isNFn mkFn_ n ref = case collectArgs n n [] fn of
        Just r -> case r.stmts of
          [Return ss' ret] -> res { ss1: ss, ss2: ss, ss3: ss', args: r.args, body: ret }
          _ -> orig
        Nothing -> orig
  convert other = other

-- | Inline `mkFnN(\a1 -> ... -> body)` → `function (a1, ..., aN) { return body; }`.
mkFnInliner :: Int -> AST -> AST
mkFnInliner = mkFnHelper p_mkFn $ \r ->
  Function r.ss1 Nothing r.args (Block r.ss2 [Return r.ss3 r.body])

-- | Inline `mkEffectFnN(\a1 -> ... -> effect)` → `function (a1, ..., aN) { return effect(); }`.
mkEffFnInliner :: Ref -> Int -> AST -> AST
mkEffFnInliner mkFn_ = mkFnHelper mkFn_ $ \r ->
  Function r.ss1 Nothing r.args (Block r.ss2 [Return r.ss3 (App r.ss3 r.body [])])

-- | `runFn'` from Inliner.hs:225-234.
runFnHelper
  :: Ref
  -> (_ -> AST -> Array AST -> AST)
  -> Int
  -> AST
  -> AST
runFnHelper runFn_ res n ast = case go n [] ast of
  Just r -> r
  Nothing -> ast
  where
  go :: Int -> Array AST -> AST -> Maybe AST
  go 0 acc (App ss ref [fn]) | isNFn runFn_ n ref && Array.length acc == n =
    Just (res ss fn acc)
  go m acc (App _ lhs [arg]) = go (m - 1) (Array.cons arg acc) lhs
  go _ _ _ = Nothing

-- | Inline `runFnN(f)(a1)(a2)...(aN)` → `f(a1, a2, ..., aN)`.
runFnInliner :: Int -> AST -> AST
runFnInliner = runFnHelper p_runFn App

-- | Inline `runEffectFnN(f)(a1)(a2)...(aN)` → `function () { return f(a1, ..., aN); }`.
runEffFnInliner :: Ref -> Int -> AST -> AST
runEffFnInliner runFn_ = runFnHelper runFn_ $ \ss fn acc ->
  Function ss Nothing [] (Block ss [Return ss (App ss fn acc)])

-- | The full list of uncurried inliners — mirrors Inliner.hs:163-166.
-- | Arities 0..10 for `mkFn` + `runFn` + each of `mkEff*` / `mkEffect*` /
-- | `mkST*` and their `runX` counterparts.
mkUncurriedInliners :: Array (AST -> AST)
mkUncurriedInliners =
  Array.concat
    [ map mkFnInliner aritiesPlain
    , map runFnInliner aritiesPlain
    , map (mkEffFnInliner p_mkEffFn) aritiesPlain
    , map (runEffFnInliner p_runEffFn) aritiesPlain
    , map (mkEffFnInliner p_mkEffectFn) aritiesPlain
    , map (runEffFnInliner p_runEffectFn) aritiesPlain
    , map (mkEffFnInliner p_mkSTFn) aritiesPlain
    , map (runEffFnInliner p_runSTFn) aritiesPlain
    ]
  where
  aritiesPlain :: Array Int
  aritiesPlain = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
