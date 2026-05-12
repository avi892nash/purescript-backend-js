-- | Ports `Language.PureScript.CoreImp.Optimizer.Blocks` (purescript@c4a35b3,
-- | src/Language/PureScript/CoreImp/Optimizer/Blocks.hs).
-- |
-- | Mapping (PursJS <-> Blocks.hs line):
-- |   collapseNestedBlocks         Blocks.hs:12-20
-- |   collapseNestedIfs            Blocks.hs:22-28
module PursJS.CoreImp.Optimizer.Blocks
  ( collapseNestedBlocks
  , collapseNestedIfs
  ) where

import Prelude

import Data.Array as Array
import Data.Maybe (Maybe(..))
import PursJS.CoreImp.AST (AST(..), BinaryOperator(..))
import PursJS.CoreImp.Traversals (everywhere)

-- | Hoist immediate child blocks up: `Block [Block [a, b], c] -> Block [a, b, c]`.
collapseNestedBlocks :: AST -> AST
collapseNestedBlocks = everywhere collapse
  where
  collapse (Block ss sts) = Block ss (Array.concatMap flatten sts)
  collapse js = js

  flatten (Block _ sts) = sts
  flatten s = [s]

-- | `if (true) { x } -> x`. Also coalesces `if (c1) { if (c2) { x } }` into
-- | `if (c1 && c2) { x }`.
collapseNestedIfs :: AST -> AST
collapseNestedIfs = everywhere collapse
  where
  collapse (IfElse _ (BooleanLiteral _ true) (Block _ [js]) _) = js
  collapse (IfElse s1 cond1 (Block _ [IfElse s2 cond2 body Nothing]) Nothing) =
    IfElse s1 (Binary s2 And cond1 cond2) body Nothing
  collapse js = js
