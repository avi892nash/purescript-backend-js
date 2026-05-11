-- | Fresh-name supply: a State Int monad with a single combinator.
module PursJS.CodeGen.Supply where

import Prelude

import Control.Monad.State (State, get, put)

type Supply a = State Int a

fresh :: Supply Int
fresh = do
  n <- get
  put (n + 1)
  pure n

-- | Matches the Haskell compiler: `freshName = "$" <> show n`.
freshName :: Supply String
freshName = (\n -> "$" <> show n) <$> fresh
