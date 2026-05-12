-- | Ports `Language.PureScript.CoreImp.Optimizer.Common` (purescript@c4a35b3,
-- | src/Language/PureScript/CoreImp/Optimizer/Common.hs).
-- |
-- | Variable-rewriting and structural helpers shared across optimizer passes.
-- |
-- | Mapping (PursJS <-> Common.hs line):
-- |   applyAll                  Common.hs:15-16
-- |   replaceIdent              Common.hs:18-22
-- |   replaceIdents             Common.hs:24-28
-- |   isReassigned              Common.hs:30-39
-- |   isRebound                 Common.hs:41-45
-- |   targetVariable            Common.hs:47-50
-- |   isUpdated                 Common.hs:52-57
-- |   removeFromBlock           Common.hs:59-61
-- |
-- | The `Ref` pattern synonym at Common.hs:63-72 is realised here as the
-- | `isRef` helper in each optimizer pass that needs it (e.g. Inliner2,
-- | FnComposition, MagicDo).
module PursJS.CoreImp.Optimizer.Common where

import Prelude

import Data.Array as Array
import Data.Foldable (foldl)
import Data.Maybe (Maybe(..), fromMaybe)
import Data.Tuple (Tuple(..))
import PursJS.CoreImp.AST (AST(..))
import PursJS.CoreImp.Traversals (everything, everywhere)

-- | Compose a list of endomorphisms. Matches Haskell's `foldl' (.) id`,
-- | which means `applyAll [f, g, h] x = f (g (h x))` — the LAST function in
-- | the list is applied FIRST.
applyAll :: forall a. Array (a -> a) -> a -> a
applyAll fs x = foldl (<<<) identity fs x

-- | Replace every `Var _ var1` with the given AST.
replaceIdent :: String -> AST -> AST -> AST
replaceIdent var1 js = everywhere replace
  where
  replace (Var _ var2) | var1 == var2 = js
  replace other = other

-- | Replace identifiers according to the assoc list.
replaceIdents :: Array (Tuple String AST) -> AST -> AST
replaceIdents vars = everywhere replace
  where
  replace v@(Var _ var) = case lookup var vars of
    Just j -> j
    Nothing -> v
  replace other = other

lookup :: forall a. String -> Array (Tuple String a) -> Maybe a
lookup key arr = case Array.uncons arr of
  Nothing -> Nothing
  Just { head: Tuple k v, tail }
    | k == key -> Just v
    | otherwise -> lookup key tail

-- | True if `var1` is reassigned (rebound) anywhere in the AST.
isReassigned :: String -> AST -> Boolean
isReassigned var1 = everything (||) check
  where
  check :: AST -> Boolean
  check (Function _ _ args _) | Array.elem var1 args = true
  check (VariableIntroduction _ arg _) | var1 == arg = true
  check (Assignment _ (Var _ arg) _) | var1 == arg = true
  check (For _ arg _ _ _) | var1 == arg = true
  check (ForIn _ arg _ _) | var1 == arg = true
  check _ = false

-- | True if any variable referenced inside `js` is reassigned or updated in `d`.
isRebound :: AST -> AST -> Boolean
isRebound js d =
  Array.any (\v -> isReassigned v d || isUpdated v d)
    (everything (<>) variablesOf js)
  where
  variablesOf :: AST -> Array String
  variablesOf (Var _ var) = [var]
  variablesOf _ = []

targetVariable :: AST -> String
targetVariable (Var _ var) = var
targetVariable (Indexer _ _ tgt) = targetVariable tgt
targetVariable _ = "<<bad targetVariable>>"

isUpdated :: String -> AST -> Boolean
isUpdated var1 = everything (||) check
  where
  check :: AST -> Boolean
  check (Assignment _ target _) | var1 == targetVariable target = true
  check _ = false

removeFromBlock :: (Array AST -> Array AST) -> AST -> AST
removeFromBlock f (Block ss sts) = Block ss (f sts)
removeFromBlock _ js = js
