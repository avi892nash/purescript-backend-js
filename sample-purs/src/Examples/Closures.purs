-- | Lambdas, partial application, function composition.
-- |
-- | Exercises:
-- |   - Abs codegen (JS.hs:303-308)
-- |   - inlineFnComposition (FnComposition.purs / Inliner.hs:248-274) — turns
-- |     `(f <<< g) x` into `f (g x)` (saturated form) or eta-expands the
-- |     point-free version into a lambda IIFE
-- |   - inlineFnIdentity (Inliner.hs:276-281) — `identity x` becomes `x`
module Examples.Closures where

import Prelude

-- Plain lambda — `function (x) { return x + 1 | 0; }`.
inc :: Int -> Int
inc = \x -> x + 1

-- Closure over a free variable — generates a nested function.
addN :: Int -> Int -> Int
addN n = \x -> x + n

-- Curried multi-arg — emits a function-returning-function chain.
add :: Int -> Int -> Int
add x y = x + y

-- Point-free with `<<<` (compose). After inlineFnComposition this should
-- compile to `function ($N) { return inc(inc($N)); }`.
addTwo :: Int -> Int
addTwo = inc <<< inc

-- Composing three. The compose chain is flattened by goApps and rebuilt as
-- a single IIFE (Inliner.hs:269-274).
inc4 :: Int -> Int
inc4 = inc <<< inc <<< inc <<< inc

-- identity is inlined away by inlineFnIdentity — the resulting JS is just `5`.
idApp :: Int
idApp = identity 5
