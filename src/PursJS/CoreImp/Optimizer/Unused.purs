-- | Ports `Language.PureScript.CoreImp.Optimizer.Unused` (purescript@c4a35b3,
-- | src/Language/PureScript/CoreImp/Optimizer/Unused.hs).
-- |
-- | Three independent dead-code passes:
-- |
-- |   - removeCodeAfterReturnStatements: drop everything after a `return ...`
-- |     inside a block (it's unreachable). Used to clean up the case-IIFE
-- |     bodies where the codegen emits a trailing `throw "Failed pattern match"`
-- |     after a `return`.
-- |
-- |   - removeUndefinedApp: `f(undefined)`  →  `f()`. Used for the
-- |     unsafePartial-inlining path (we pass undefined as the proof and rely on
-- |     this to clean it up).
-- |
-- |   - removeUnusedEffectFreeVars: drop top-level `var x = ...` whose value is
-- |     marked NoEffects and whose name nothing references. Runs to fixed point.
-- |     This is what removes the dictionary helper bindings the inliner has
-- |     replaced everywhere.
-- |
-- | Mapping (PursJS <-> Unused.hs line):
-- |   removeCodeAfterReturnStatements   Unused.hs:19-30
-- |   removeUndefinedApp                Unused.hs:32-36
-- |   removeUnusedEffectFreeVars        Unused.hs:38-52
module PursJS.CoreImp.Optimizer.Unused
  ( removeCodeAfterReturnStatements
  , removeUndefinedApp
  , removeUnusedEffectFreeVars
  ) where

import Prelude

import Data.Array as Array
import Data.Foldable (foldMap)
import Data.Maybe (Maybe(..))
import Data.Set (Set)
import Data.Set as Set
import Data.Tuple (Tuple(..))
import PursJS.CoreImp.AST (AST(..), InitializerEffects(..))
import PursJS.CoreImp.Optimizer.Common (removeFromBlock)
import PursJS.CoreImp.Traversals (everything, everywhere)

removeCodeAfterReturnStatements :: AST -> AST
removeCodeAfterReturnStatements = everywhere (removeFromBlock go)
  where
  go :: Array AST -> Array AST
  go jss =
    let { init: pref, rest } = break isReturn jss
    in case Array.head rest of
         Nothing -> jss
         Just r -> Array.snoc pref r

  isReturn :: AST -> Boolean
  isReturn (Return _ _) = true
  isReturn (ReturnNoResult _) = true
  isReturn _ = false

  break :: (AST -> Boolean) -> Array AST -> { init :: Array AST, rest :: Array AST }
  break p arr = go' [] arr
    where
    go' acc xs = case Array.uncons xs of
      Nothing -> { init: Array.reverse acc, rest: [] }
      Just { head, tail }
        | p head -> { init: Array.reverse acc, rest: xs }
        | otherwise -> go' (Array.cons head acc) tail

removeUndefinedApp :: AST -> AST
removeUndefinedApp = everywhere convert
  where
  convert (App ss fn [Var _ "undefined"]) = App ss fn []
  convert js = js

-- | Drop top-level `var x = ...` declarations whose initializer has no
-- | effects and that nothing references. Runs to fixed point.
removeUnusedEffectFreeVars :: Array String -> Array (Array AST) -> Array (Array AST)
removeUnusedEffectFreeVars exps decls = loop decls
  where
  expsSet = Set.fromFoldable exps

  loop :: Array (Array AST) -> Array (Array AST)
  loop asts =
    let used = Set.union expsSet (collectUsed asts)
        { changed, result } = stepAll used asts
    in if changed
       then loop (Array.filter (not <<< Array.null) result)
       else asts

  collectUsed :: Array (Array AST) -> Set String
  collectUsed asts = foldMap (foldMap collectFromAST) asts

  collectFromAST :: AST -> Set String
  collectFromAST = everything Set.union step
    where
    step (Var _ x) = Set.singleton x
    step _ = Set.empty

  stepAll :: Set String -> Array (Array AST) -> { changed :: Boolean, result :: Array (Array AST) }
  stepAll used asts =
    let results = map (stepOne used) asts
        changed = Array.any _.changed results
        result = map _.result results
    in { changed, result }

  stepOne :: Set String -> Array AST -> { changed :: Boolean, result :: Array AST }
  stepOne used arr =
    Array.foldl step' { changed: false, result: [] } arr
    where
    step' acc s = case isKept used s of
      true -> { changed: acc.changed, result: Array.snoc acc.result s }
      false -> { changed: true, result: acc.result }

  isKept :: Set String -> AST -> Boolean
  isKept used = case _ of
    VariableIntroduction _ var (Just (Tuple NoEffects _)) -> Set.member var used
    _ -> true
