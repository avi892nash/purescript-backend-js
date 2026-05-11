-- | Top-level optimizer pipeline. Mirrors `Language.PureScript.CoreImp.Optimizer.optimize`.
-- |
-- | This is a subset of the full optimizer — it covers the AST-level cleanup
-- | (block flattening, IIFE collapse, variable inlining, dead-code removal,
-- | unused-var removal) but does *not* yet handle: magic-do, TCO, or the
-- | type-class-aware inliners (Semiring add, Ring sub, Eq eq, etc.).
module PursJS.CoreImp.Optimizer
  ( optimize
  ) where

import Prelude

import Data.Array as Array
import PursJS.CoreImp.AST (AST)
import PursJS.CoreImp.Optimizer.Blocks (collapseNestedBlocks, collapseNestedIfs)
import PursJS.CoreImp.Optimizer.Common (applyAll)
import PursJS.CoreImp.Optimizer.Inliner (etaConvert, evaluateIifes, inlineVariables, unThunk)
import PursJS.CoreImp.Optimizer.Inliner2 (buildExpander, inlineCommonOperators, inlineCommonValues, inlineFnIdentity, inlineUnsafeCoerce)
import PursJS.CoreImp.Optimizer.Unused (removeCodeAfterReturnStatements, removeUndefinedApp, removeUnusedEffectFreeVars)

optimize :: Array String -> Array (Array AST) -> Array (Array AST)
optimize exps jsDecls =
  let allTopLevel = Array.concat jsDecls
      expander = buildExpander allTopLevel
      go ast = untilFixed (inlineUnsafeCoerce <<< inlineFnIdentity expander <<< tidyUp <<< applyAll
        [ inlineCommonValues expander
        , inlineCommonOperators expander
        ]) ast
      optimized = map (map (untilFixed tidyUp <<< go)) jsDecls
  in removeUnusedEffectFreeVars exps optimized

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

-- | Apply f until fixed point. Requires Eq, which we have via Array structural
-- | equality through `Array.length` + element compare; since `AST` doesn't
-- | derive Eq we use a cycle bound instead (32 iterations should converge for
-- | well-behaved tidyUp passes).
untilFixed :: (AST -> AST) -> AST -> AST
untilFixed f = go 32
  where
  go 0 x = x
  go n x =
    let x' = f x
    in go (n - 1) x'
