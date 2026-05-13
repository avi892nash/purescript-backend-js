-- | Effect.Uncurried — exercises the `mkEffectFn0..10` / `runEffectFn0..10`
-- | inliners from Inliner.hs:165, 193-195, 218-234.
-- |
-- | After the inliner runs:
-- |   mkEffectFn2(\a b -> eff)        becomes  function (a, b) { return eff(); }
-- |   runEffectFn2(f)(a)(b)           becomes  function () { return f(a, b); }
module Examples.Uncurried where

import Prelude
import Effect (Effect)
import Effect.Uncurried (EffectFn2, mkEffectFn2, runEffectFn2)
import Effect.Console (log)

-- mkEffectFn2 wraps a curried Effect-producing function as a 2-arg Effect Fn.
logTwo :: EffectFn2 String String Unit
logTwo = mkEffectFn2 (\a b -> do
  log a
  log b)

-- runEffectFn2 takes the wrapped form and unwraps to a call site.
runIt :: Effect Unit
runIt = runEffectFn2 logTwo "hello" "world"
