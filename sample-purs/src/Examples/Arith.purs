-- | Arithmetic — exercises the type-class inliners.
-- |
-- | Without the inliner: `x + y` becomes `Data_Semiring.add(semiringInt)(x)(y)`.
-- | With Inliner2.inlineCommonValues at Inliner.hs:98-101 the Int variant
-- | collapses to `(x + y) | 0`. The Number variant goes through
-- | inlineCommonOperators (Inliner.hs:107) and becomes plain `x + y`.
module Examples.Arith where

import Prelude

intAdd :: Int -> Int -> Int
intAdd x y = x + y          -- → return x + y | 0

intMul :: Int -> Int -> Int
intMul x y = x * y          -- → return x * y | 0

intSub :: Int -> Int -> Int
intSub x y = x - y          -- → return x - y | 0

intNeg :: Int -> Int
intNeg x = (-x)             -- → return -x | 0   (Inliner.hs:96-97)

numAdd :: Number -> Number -> Number
numAdd x y = x + y          -- → return x + y    (no `| 0` for Number)

numDiv :: Number -> Number -> Number
numDiv x y = x / y          -- → return x / y    (euclideanRingNumber)

-- String concat goes via semigroupString → emits `+` as a binary op
-- (Inliner.hs:147 — `binary P_semigroupString P_append Add`).
strConcat :: String -> String -> String
strConcat a b = a <> b

-- Comparison ops on Int — Ord.lessThan etc. inline to `<` via Inliner.hs:134-137.
isLess :: Int -> Int -> Boolean
isLess a b = a < b

isEq :: Int -> Int -> Boolean
isEq a b = a == b           -- eqInt → `===`

isNotEq :: String -> String -> Boolean
isNotEq a b = a /= b        -- eqString → `!==`

-- Booleans: HeytingAlgebra inlines to &&, ||, !.
boolAnd :: Boolean -> Boolean -> Boolean
boolAnd a b = a && b

boolOr :: Boolean -> Boolean -> Boolean
boolOr a b = a || b

boolNot :: Boolean -> Boolean
boolNot a = not a
