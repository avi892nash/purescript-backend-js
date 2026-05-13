-- | Top-level optimizer pipeline. Ports `Language.PureScript.CoreImp.Optimizer.optimize`
-- | (purescript@c4a35b3, src/Language/PureScript/CoreImp/Optimizer.hs:36-62).
-- |
-- | Order of passes (matches Optimizer.hs `optimize` exactly):
-- |
-- |   1. for each AST in each decl, run to fixed point:
-- |        inlineFnComposition (monadic)
-- |       ∘ inlineFnIdentity
-- |       ∘ inlineUnsafeCoerce
-- |       ∘ tidyUp
-- |       ∘ applyAll [inlineCommonValues, inlineCommonOperators]
-- |
-- |   2. for each AST, run to fixed point: magicDoEffect
-- |      (We don't yet port magicDoEff or magicDoST / inlineST.)
-- |
-- |   3. for each AST: tco then a final tidyUp pass.
-- |
-- |   4. removeUnusedEffectFreeVars on the whole module.
-- |
-- | Mapping (PursJS <-> Optimizer.hs line):
-- |   optimize                  Optimizer.hs:36-48
-- |   tidyUp                    Optimizer.hs:50-60
-- |   buildExpander             Optimizer.hs:80-85  (in PursJS.CoreImp.Optimizer.Inliner2)
-- |   untilFixedPoint           Optimizer.hs:64-69  (we use a 32-iteration cap because AST has no Eq)
module PursJS.CoreImp.Optimizer
  ( optimize
  ) where

import Prelude

import Data.Array as Array
import Data.Traversable (traverse)
import PursJS.CodeGen.Supply (Supply)
import PursJS.CoreImp.AST (AST(..), UnaryOperator(..))
import PursJS.CoreImp.Optimizer.Blocks (collapseNestedBlocks, collapseNestedIfs)
import PursJS.CoreImp.Optimizer.Common (applyAll)
import PursJS.CoreImp.Optimizer.FnComposition (inlineFnComposition)
import PursJS.CoreImp.Optimizer.Inliner (etaConvert, evaluateIifes, inlineVariables, unThunk)
import PursJS.CoreImp.Optimizer.Inliner2 (buildExpander, inlineCommonOperators, inlineCommonValues, inlineFnIdentity, inlineUnsafeCoerce, inlineUnsafeIndex, inlineUnsafePartial)
import PursJS.CoreImp.Optimizer.MagicDo (magicDoEff, magicDoEffect, magicDoST)
import PursJS.CoreImp.Optimizer.TCO (tco)
import PursJS.CoreImp.Optimizer.Uncurried (mkUncurriedInliners)
import PursJS.CoreImp.Optimizer.Unused (removeCodeAfterReturnStatements, removeUndefinedApp, removeUnusedEffectFreeVars)
import PursJS.CoreImp.Traversals (everywhereTopDown)
import Data.Either (Either(..))

optimize :: Array String -> Array (Array AST) -> Supply (Array (Array AST))
optimize exps jsDecls = do
  let allTopLevel = Array.concat jsDecls
      expander = buildExpander allTopLevel
      uncurriedPass = everywhereTopDown (applyAll mkUncurriedInliners)
      pureRound ast = untilFixed (inlineUnsafeCoerce <<< inlineUnsafePartial <<< inlineFnIdentity expander <<< tidyUp <<< uncurriedPass <<< inlineUnsafeIndex <<< applyAll
        [ inlineCommonValues expander
        , inlineCommonOperators expander
        ]) ast
      monadicRound ast = inlineFnComposition expander (pureRound ast)
  inlined <- traverse (traverse (\ast -> untilFixedM 16 monadicRound ast)) jsDecls
  -- Run all three magicDo passes (Effect, ST, Eff) — each only matches its
  -- specific dictionary refs so they're independent.
  let magicDoAll = magicDoEffect expander <<< magicDoST expander <<< magicDoEff expander
      withMagicDo = map (map (untilFixed magicDoAll)) inlined
  -- Apply TCO after magicDo so that the de-monadised loop body can be analysed.
  let withTco = map (map (tco <<< untilFixed tidyUp)) withMagicDo
  -- checkIntegers (JS.hs:190-207) — fold `Unary Negate (NumericLiteral i)`
  -- into `NumericLiteral (-i)` so we never emit `--N` for `n = -2147483648`.
  let withChecked = map (map (everywhereTopDown checkIntegers)) withTco
  let cleaned = map (map (untilFixed tidyUp)) withChecked
  pure (removeUnusedEffectFreeVars exps cleaned)

-- | JS.hs:191-207 — `checkIntegers`. Top-down rewrite that absorbs a leading
-- | `Unary Negate` into a `NumericLiteral` so we don't end up emitting
-- | `--2147483648` for `n = -2147483648` (where the corefn contains
-- | `Unary Negate (NumericLiteral 2147483648)` and our parser wraps
-- | 2147483648 to -2147483648 via the JS `| 0` trick).
-- |
-- | Note: in PureScript, `negate Int.bottom` wraps back to `Int.bottom`
-- | (because `2147483648 :: Int` overflows). That happens to be what JS
-- | semantics want here too — `-(-2147483648) | 0 === -2147483648` — so
-- | the rewrite is sound even with that quirk.
checkIntegers :: AST -> AST
checkIntegers (Unary _ Negate (NumericLiteral ss (Left i))) =
  NumericLiteral ss (Left (negate i))
checkIntegers other = other

tidyUp :: AST -> AST
tidyUp = applyAll
  [ collapseNestedBlocks
  , collapseNestedIfs
  , removeCodeAfterReturnStatements
  , removeUndefinedApp
  , unThunk
  , etaConvert
  , evaluateIifes
  , inlineVariables
  ]

-- | Apply f until fixed point (capped at 32 iterations).
untilFixed :: (AST -> AST) -> AST -> AST
untilFixed f = go 32
  where
  go 0 x = x
  go n x =
    let x' = f x
    in go (n - 1) x'

-- | Monadic variant.
untilFixedM :: Int -> (AST -> Supply AST) -> AST -> Supply AST
untilFixedM cap f = go cap
  where
  go 0 x = pure x
  go n x = f x >>= go (n - 1)
