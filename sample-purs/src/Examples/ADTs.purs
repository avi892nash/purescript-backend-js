-- | Algebraic data types — sum types, product constructors, and newtype.
-- |
-- | Exercises CodeGen.JS `Constructor` handling (JS.hs:336-354 for nullary,
-- | JS.hs:345-354 for n-ary, IsNewtype short-cut at JS.hs:336-340).
module Examples.ADTs where

-- Nullary sum (each constructor emits an IIFE with a `.value` singleton).
data Color = Red | Green | Blue

red :: Color
red = Red

-- Product constructor (emits `function (a) { return function (b) { return new C(a, b); } }`).
data Pair a b = Pair a b

mkPair :: Pair Int String
mkPair = Pair 1 "one"

-- Recursive sum type — the codegen handles the recursion fine because the
-- generated `new C(...)` calls don't materialise the type at runtime.
data Tree a
  = Leaf
  | Branch (Tree a) a (Tree a)

singleton :: forall a. a -> Tree a
singleton x = Branch Leaf x Leaf

-- Newtype — short-cut: `var Wrap = { create: function (value) { return value; } }`.
-- The constructor application disappears entirely at runtime; only the
-- underlying value remains.
newtype Wrap = Wrap Int

unwrap :: Wrap -> Int
unwrap (Wrap n) = n

wrapped :: Wrap
wrapped = Wrap 7
