-- | Ports `magicDoEffect`, `magicDoEff`, and `magicDoST` from
-- | `Language.PureScript.CoreImp.Optimizer.MagicDo` (purescript@c4a35b3,
-- | src/Language/PureScript/CoreImp/Optimizer/MagicDo.hs).
-- |
-- | Inlines monomorphic `bind`/`discard`/`pure` for the `Effect`, `Eff`,
-- | and `ST` monads into a single `function __do() { ... }` block, so that
-- | a chain of `>>=` calls compiles into a flat sequence of effectful
-- | statements.
-- |
-- | Mapping (PursJS <-> MagicDo.hs line):
-- |   magicDoEffect             MagicDo.hs:33-34 (specialised at C.M_Effect)
-- |   magicDoEff                MagicDo.hs:30-31 (specialised at C.M_Control_Monad_Eff)
-- |   magicDoST                 MagicDo.hs:36-37 (specialised at C.M_Control_Monad_ST_Internal)
-- |   magicDo (the worker)      MagicDo.hs:39-90 (one helper here)
-- |
-- | NOT yet ported: `inlineST` (MagicDo.hs:93-136 — turns `STRef new/read/
-- | write/modify` calls into local-variable accesses).
module PursJS.CoreImp.Optimizer.MagicDo
  ( magicDoEffect
  , magicDoEff
  , magicDoST
  ) where

import Prelude

import Data.Array as Array
import Data.Maybe (Maybe(..))
import Data.Tuple (Tuple(..))
import PursJS.CoreImp.AST (AST(..), InitializerEffects(..))
import PursJS.CoreImp.Optimizer.Constants (Ref, p_applicativeEff, p_applicativeEffect, p_applicativeST, p_bind, p_bindEff, p_bindEffect, p_bindST, p_discard, p_discardUnit, p_pure)
import PursJS.CoreImp.Traversals (everywhereTopDown)

isRef :: Ref -> AST -> Boolean
isRef (Tuple mn name) (ModuleAccessor _ mn' name') = mn == mn' && name == name'
isRef _ _ = false

-- | The trio of dictionary references for a given do-notation monad.
type EffDicts =
  { bindDict :: Ref
  , applicativeDict :: Ref
  }

effectDicts :: EffDicts
effectDicts = { bindDict: p_bindEffect, applicativeDict: p_applicativeEffect }

stDicts :: EffDicts
stDicts = { bindDict: p_bindST, applicativeDict: p_applicativeST }

effDicts :: EffDicts
effDicts = { bindDict: p_bindEff, applicativeDict: p_applicativeEff }

magicDoEffect :: (AST -> AST) -> AST -> AST
magicDoEffect = magicDo effectDicts

magicDoST :: (AST -> AST) -> AST -> AST
magicDoST = magicDo stDicts

magicDoEff :: (AST -> AST) -> AST -> AST
magicDoEff = magicDo effDicts

magicDo :: EffDicts -> (AST -> AST) -> AST -> AST
magicDo dicts expander = everywhereTopDown convert
  where
  fnName :: String
  fnName = "__do"

  convert :: AST -> AST
  -- pure(applicative)(val)()  ->  val
  convert (App _ (App _ pureFn [val]) []) | isPure pureFn = val

  -- discard(bind)(m)(function () { ...js })
  --   →  function __do() { m(); applyReturns js }
  convert (App _ (App _ b [m]) [Function s1 Nothing [] (Block s2 js)])
    | isDiscard b =
        Function s1 (Just fnName) []
          (Block s2 (Array.cons (App s2 m []) (map applyReturns js)))

  -- bind(bind)(m)(function () { ...js }) — wildcard binder
  convert (App _ (App _ b [m]) [Function s1 Nothing [] (Block s2 js)])
    | isBind b =
        Function s1 (Just fnName) []
          (Block s2 (Array.cons (App s2 m []) (map applyReturns js)))

  -- bind(bind)(m)(function (arg) { ...js })
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
    App _ fn [dict] -> isRef p_bind fn && isRef dicts.bindDict dict
    _ -> false

  isDiscard ast = case expander ast of
    App _ inner [dict] -> case expander inner of
      App _ fn [dict'] -> isRef p_discard fn && isRef p_discardUnit dict' && isRef dicts.bindDict dict
      _ -> false
    _ -> false

  isPure ast = case expander ast of
    App _ fn [dict] -> isRef p_pure fn && isRef dicts.applicativeDict dict
    _ -> false

  -- After we collapse `bind` into a do-block, the continuations stop being
  -- effectful. Any final `return <ast>` becomes `return <ast>()`.
  applyReturns :: AST -> AST
  applyReturns (Return ss ret) = Return ss (App ss ret [])
  applyReturns (Block ss js) = Block ss (map applyReturns js)
  applyReturns (While ss cond body) = While ss cond (applyReturns body)
  applyReturns (For ss v lo hi body) = For ss v lo hi (applyReturns body)
  applyReturns (ForIn ss v xs body) = ForIn ss v xs (applyReturns body)
  applyReturns (IfElse ss cond t f) = IfElse ss cond (applyReturns t) (map applyReturns f)
  applyReturns other = other
