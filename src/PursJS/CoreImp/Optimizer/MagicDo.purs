-- | The "Magic Do" optimization. Inlines `bind`, `pure`, and `discard` for the
-- | `Effect` monad into a single `function __do() { ... }` body, mirroring
-- | `magicDoEffect` in `Language.PureScript.CoreImp.Optimizer.MagicDo`.
-- |
-- | Currently implements `magicDoEffect` only (not `magicDoEff` for the legacy
-- | `Eff` monad, and not `magicDoST` for `ST`).
module PursJS.CoreImp.Optimizer.MagicDo
  ( magicDoEffect
  ) where

import Prelude

import Data.Array as Array
import Data.Maybe (Maybe(..))
import Data.Tuple (Tuple(..))
import PursJS.CoreImp.AST (AST(..), InitializerEffects(..))
import PursJS.CoreImp.Optimizer.Constants (Ref, p_applicativeEffect, p_bind, p_bindEffect, p_discard, p_discardUnit, p_pure)
import PursJS.CoreImp.Traversals (everywhereTopDown)

isRef :: Ref -> AST -> Boolean
isRef (Tuple mn name) (ModuleAccessor _ mn' name') = mn == mn' && name == name'
isRef _ _ = false

magicDoEffect :: (AST -> AST) -> AST -> AST
magicDoEffect expander = everywhereTopDown convert
  where
  fnName :: String
  fnName = "__do"

  convert :: AST -> AST
  -- pure(applicativeEffect)(val)()  ->  val
  convert (App _ (App _ pureFn [val]) []) | isPure pureFn = val

  -- discard(bindEffect)(m)(function () { ...js })
  --   →  function __do() { m(); applyReturns js }
  convert (App _ (App _ b [m]) [Function s1 Nothing [] (Block s2 js)])
    | isDiscard b =
        Function s1 (Just fnName) []
          (Block s2 (Array.cons (App s2 m []) (map applyReturns js)))

  -- bind(bindEffect)(m)(function () { ...js }) — wildcard binder
  convert (App _ (App _ b [m]) [Function s1 Nothing [] (Block s2 js)])
    | isBind b =
        Function s1 (Just fnName) []
          (Block s2 (Array.cons (App s2 m []) (map applyReturns js)))

  -- bind(bindEffect)(m)(function (arg) { ...js })
  convert (App _ (App _ b [m]) [Function s1 Nothing [arg] (Block s2 js)])
    | isBind b =
        Function s1 (Just fnName) []
          (Block s2 (Array.cons (VariableIntroduction s2 arg (Just (Tuple UnknownEffects (App s2 m [])))) (map applyReturns js)))

  -- Inline __do returns:  return (function __do() { ... })()  →  body
  convert (Return _ (App _ (Function _ (Just ident) [] body) []))
    | ident == fnName = body

  -- Inline double applications
  convert (App _ (App s1 (Function s2 Nothing [] (Block ss body)) []) []) =
    App s1 (Function s2 Nothing [] (Block ss (map applyReturns body))) []

  convert other = other

  isBind ast = case expander ast of
    App _ fn [dict] -> isRef p_bind fn && isRef p_bindEffect dict
    _ -> false

  isDiscard ast = case expander ast of
    App _ inner [dict] -> case expander inner of
      App _ fn [dict'] -> isRef p_discard fn && isRef p_discardUnit dict' && isRef p_bindEffect dict
      _ -> false
    _ -> false

  isPure ast = case expander ast of
    App _ fn [dict] -> isRef p_pure fn && isRef p_applicativeEffect dict
    _ -> false

  -- After we collapse `bind` into a do-block, the continuations stop being
  -- effectful (Effect a => Effect b becomes a → b). To stitch the block back
  -- into JS, any final `return <ast>` needs to become `return <ast>()`.
  applyReturns :: AST -> AST
  applyReturns (Return ss ret) = Return ss (App ss ret [])
  applyReturns (Block ss js) = Block ss (map applyReturns js)
  applyReturns (While ss cond body) = While ss cond (applyReturns body)
  applyReturns (For ss v lo hi body) = For ss v lo hi (applyReturns body)
  applyReturns (ForIn ss v xs body) = ForIn ss v xs (applyReturns body)
  applyReturns (IfElse ss cond t f) = IfElse ss cond (applyReturns t) (map applyReturns f)
  applyReturns other = other
