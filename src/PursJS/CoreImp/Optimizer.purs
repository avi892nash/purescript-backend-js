-- | Top-level optimizer pipeline. Mirrors `Language.PureScript.CoreImp.Optimizer.optimize`.
module PursJS.CoreImp.Optimizer
  ( optimize
  ) where

import Prelude

import Data.Array as Array
import Data.Traversable (traverse)
import PursJS.CodeGen.Supply (Supply)
import PursJS.CoreImp.AST (AST)
import PursJS.CoreImp.Optimizer.Blocks (collapseNestedBlocks, collapseNestedIfs)
import PursJS.CoreImp.Optimizer.Common (applyAll)
import PursJS.CoreImp.Optimizer.FnComposition (inlineFnComposition)
import PursJS.CoreImp.Optimizer.Inliner (etaConvert, evaluateIifes, inlineVariables, unThunk)
import PursJS.CoreImp.Optimizer.Inliner2 (buildExpander, inlineCommonOperators, inlineCommonValues, inlineFnIdentity, inlineUnsafeCoerce)
import PursJS.CoreImp.Optimizer.MagicDo (magicDoEffect)
import PursJS.CoreImp.Optimizer.TCO (tco)
import PursJS.CoreImp.Optimizer.Unused (removeCodeAfterReturnStatements, removeUndefinedApp, removeUnusedEffectFreeVars)

optimize :: Array String -> Array (Array AST) -> Supply (Array (Array AST))
optimize exps jsDecls = do
  let allTopLevel = Array.concat jsDecls
      expander = buildExpander allTopLevel
      pureRound ast = untilFixed (inlineUnsafeCoerce <<< inlineFnIdentity expander <<< tidyUp <<< applyAll
        [ inlineCommonValues expander
        , inlineCommonOperators expander
        ]) ast
      monadicRound ast = inlineFnComposition expander (pureRound ast)
  inlined <- traverse (traverse (\ast -> untilFixedM 16 monadicRound ast)) jsDecls
  let withMagicDo = map (map (untilFixed (magicDoEffect expander))) inlined
  -- Apply TCO after magicDo so that the de-monadised loop body can be analysed.
  let withTco = map (map (tco <<< untilFixed tidyUp)) withMagicDo
  let cleaned = map (map (untilFixed tidyUp)) withTco
  pure (removeUnusedEffectFreeVars exps cleaned)

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
