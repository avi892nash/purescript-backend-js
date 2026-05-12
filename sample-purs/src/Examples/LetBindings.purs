-- | Let bindings — exercises CodeGen.JS `Let` (JS.hs:332-335).
-- |
-- | A `let` expression becomes an IIFE with the bindings as `var` declarations
-- | followed by a `return`. After unThunk + inlineVariables this often
-- | collapses entirely when the bindings are trivially substitutable.
module Examples.LetBindings where

import Prelude

simple :: Int
simple =
  let x = 1
      y = 2
  in x + y

-- Let with a function (becomes `var f = function (n) { return ... }`).
withFn :: Int -> Int
withFn n =
  let double v = v + v
  in double n + 1

-- Shadowing — inner `x` shadows outer parameter `x` inside the let.
-- The codegen relies on the surrounding lexical scope (a new IIFE) to
-- get the shadowing right; no renaming pass needed.
shadow :: Int -> Int
shadow x =
  let x = 100
  in x

-- Mutually recursive let (becomes a `Rec` bind). Without
-- applyLazinessTransform (not yet ported) this won't necessarily produce
-- correct JS in cases where the bindings forward-reference each other
-- — but for simple cases like this where the names are only used inside
-- function bodies, plain `var f = ...; var g = ...;` works fine.
mutual :: Int -> Boolean
mutual n =
  let even 0 = true
      even k = odd (k - 1)
      odd 0 = false
      odd k = even (k - 1)
  in even n
