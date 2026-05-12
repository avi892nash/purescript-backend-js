-- | Ports `Control.Monad.Supply` + `Control.Monad.Supply.Class` (purescript@c4a35b3,
-- | src/Control/Monad/Supply.hs and src/Control/Monad/Supply/Class.hs).
-- |
-- | The Haskell compiler uses `SupplyT m a` (a wrapper around StateT Integer m a)
-- | and exposes `fresh :: m Integer` and `freshName :: m Text`.
-- |
-- | Mapping (PursJS <-> Class.hs line):
-- |   Supply (= State Int)      Supply.hs (`newtype SupplyT m a = SupplyT (StateT Integer m a)`)
-- |   fresh                     Supply/Class.hs:26-29
-- |   freshName                 Supply/Class.hs:36-37 (`freshName = ("$" <> ) . pack . show <$> fresh`)
module PursJS.CodeGen.Supply where

import Prelude

import Control.Monad.State (State, get, put)

-- | The supply monad. The Haskell compiler shares one SupplyT across all
-- | desugaring/CSE/codegen/optimizer phases; here we only thread it through
-- | codegen + the monadic optimizer passes (`inlineFnComposition`, `tco`'s
-- | inner `$tco_doneN` counter).
type Supply a = State Int a

-- | Supply/Class.hs:26-29 — yield the current counter, advance by one.
fresh :: Supply Int
fresh = do
  n <- get
  put (n + 1)
  pure n

-- | Supply/Class.hs:36-37 — `freshName = ("$" <>) . pack . show <$> fresh`.
-- | Gives `$0`, `$1`, ... for use as case scrutinee binders, compose IIFE
-- | bound variables, etc.
freshName :: Supply String
freshName = (\n -> "$" <> show n) <$> fresh
