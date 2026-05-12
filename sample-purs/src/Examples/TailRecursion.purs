-- | Tail-recursive functions — exercises the TCO pass
-- | (CoreImp.Optimizer.TCO / TCO.hs).
-- |
-- | Each `var f = function (a) { return f(a'); }` is rewritten as a
-- | `$tco_loop` while-loop. Multi-arg tail recursion stacks the args as
-- | `$copy_a, $copy_b, ...` and `$tco_var_a, $tco_var_b, ...`.
module Examples.TailRecursion where

import Prelude

-- Single-arg tail recursion (the canonical Data.Void.absurd shape).
-- Rewrites to:
--   var spin = function ($copy_v) {
--       var $tco_var_v = $copy_v;
--       var $tco_done = false;
--       var $tco_result;
--       function $tco_loop(v) { $tco_var_v = v; return; }
--       while (!$tco_done) { $tco_result = $tco_loop($tco_var_v); }
--       return $tco_result;
--   };
spin :: forall a. a -> a
spin x = spin x

-- Two-arg tail recursion (cf. Data.Function.applyN). Both args get
-- $copy_/$tco_var_ prefixes.
sumDown :: Int -> Int -> Int
sumDown n acc
  | n <= 0 = acc
  | otherwise = sumDown (n - 1) (acc + n)

-- A non-tail-recursive function should NOT be TCO'd — the addition happens
-- *after* the recursive call, so the rec call isn't in tail position.
-- TCO's findTailPositionDeps at TCO.hs:97-99 will return Nothing here and
-- this stays as a normal recursive function in the JS.
sumUp :: Int -> Int
sumUp 0 = 0
sumUp n = n + sumUp (n - 1)
