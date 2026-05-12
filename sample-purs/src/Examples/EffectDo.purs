-- | Effectful do-notation — exercises magicDoEffect.
-- |
-- | Without magicDoEffect, a do-block compiles to a chain of
-- |   bind(bindEffect)(eff1)(function (x) { return bind(...)(eff2)(...) ... })
-- |
-- | After magicDoEffect (MagicDo.hs:33-34, ported in
-- | PursJS.CoreImp.Optimizer.MagicDo), the chain collapses to:
-- |   function __do() {
-- |       var x = eff1();
-- |       ...
-- |       return result;
-- |   }
module Examples.EffectDo where

import Prelude
import Effect (Effect)
import Effect.Console (log, logShow)

-- Discards two effects in sequence (purely-discard chain).
hello :: Effect Unit
hello = do
  log "Hello"
  log "World"

-- Three-step discard chain.
greet :: String -> Effect Unit
greet name = do
  log "Hi,"
  log name
  log "(welcome)"

-- pure + log mix.
ping :: Effect Int
ping = do
  log "pinging"
  pure 42

-- More complex — multiple sequenced discards followed by a final return.
sequenced :: Effect Unit
sequenced = do
  logShow 1
  logShow 2
  logShow 3
