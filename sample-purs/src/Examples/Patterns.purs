-- | Pattern matching: case expressions with literal, var, constructor,
-- | and named binders. Demonstrates the IIFE-with-conditionals shape that
-- | `bindersToJs` emits and how the optimizer collapses it.
-- |
-- | Exercises:
-- |   - bindersToJs (JS.hs:406-444): the outer IIFE wrapping a case
-- |   - binderToJs / binderToJs' (JS.hs:446-481): each binder variant
-- |   - literalToBinderJS (JS.hs:483-513): literal binders compile to `===`
-- |     comparisons; array binders also check `.length`
-- |   - unThunk / evaluateIifes / inlineVariables collapse the IIFE when the
-- |     pattern is trivially refutable
module Examples.Patterns where

import Prelude
import Examples.ADTs (Color(..), Tree(..))

-- Simplest pattern match — single VarBinder. After optimization this becomes
-- `var describe = function (c) { return ... };` with the IIFE collapsed.
describe :: Color -> String
describe c = case c of
  Red -> "red"
  Green -> "green"
  Blue -> "blue"

-- Nested constructor binders. The codegen emits nested
-- `if (v instanceof Branch) { ... }` checks via SumType handling at
-- JS.hs:466-468.
treeSize :: forall a. Tree a -> Int
treeSize t = case t of
  Leaf -> 0
  Branch l _ r -> 1 + treeSize l + treeSize r

-- Multi-scrutinee case. `bindersToJs` allocates one fresh `$N` name per
-- scrutinee at JS.hs:408 (`valNames <- replicateM ...`), then chains the
-- binders together.
zip2 :: forall a b. Array a -> Array b -> Array { fst :: a, snd :: b }
zip2 xs ys = case xs, ys of
  [x], [y] -> [{ fst: x, snd: y }]
  _, _ -> []

-- Guards: a Left list of (guard, body) pairs in CaseAlternative. The
-- codegen at JS.hs:436-442 emits each as an `if (g) { return body }`.
classify :: Int -> String
classify n
  | n < 0 = "negative"
  | n == 0 = "zero"
  | otherwise = "positive"
