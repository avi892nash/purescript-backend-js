-- | First half of `Language.PureScript.CoreImp.Optimizer.Inliner`
-- | (purescript@c4a35b3, src/Language/PureScript/CoreImp/Optimizer/Inliner.hs).
-- |
-- | These passes are AST-shape-only (don't look at module/dict identifiers);
-- | the type-class-aware ones live in `PursJS.CoreImp.Optimizer.Inliner2`,
-- | and `inlineFnComposition` (the only monadic pass) is in
-- | `PursJS.CoreImp.Optimizer.FnComposition`.
-- |
-- | Mapping (PursJS <-> Inliner.hs line):
-- |   shouldInline              Inliner.hs:36-43
-- |   etaConvert                Inliner.hs:45-55
-- |   unThunk                   Inliner.hs:57-66
-- |   evaluateIifes             Inliner.hs:68-75
-- |   inlineVariables           Inliner.hs:77-85
module PursJS.CoreImp.Optimizer.Inliner
  ( shouldInline
  , etaConvert
  , unThunk
  , evaluateIifes
  , inlineVariables
  ) where

import Prelude

import Data.Array as Array
import Data.Foldable (any)
import Data.Maybe (Maybe(..))
import Data.Tuple (Tuple(..))
import PursJS.CoreImp.AST (AST(..))
import PursJS.CoreImp.Optimizer.Common (isReassigned, isRebound, isUpdated, removeFromBlock, replaceIdent, replaceIdents)
import PursJS.CoreImp.Traversals (everywhere)

shouldInline :: AST -> Boolean
shouldInline (Var _ _) = true
shouldInline (ModuleAccessor _ _ _) = true
shouldInline (NumericLiteral _ _) = true
shouldInline (StringLiteral _ _) = true
shouldInline (BooleanLiteral _ _) = true
shouldInline (Indexer _ index val) = shouldInline index && shouldInline val
shouldInline _ = false

etaConvert :: AST -> AST
etaConvert = everywhere convert
  where
  convert (Block ss [Return _ (App _ (Function _ Nothing idents block@(Block _ body)) args)])
    | Array.length idents == Array.length args
    , Array.all shouldInline args
    , not (Array.any (\i -> isRebound (Var Nothing i) block) idents)
    , not (any (\a -> isRebound a block) args)
    = Block ss (map (replaceIdents (Array.zip idents args)) body)
  convert (Function _ Nothing [] (Block _ [Return _ (App _ fn [])])) = fn
  convert js = js

unThunk :: AST -> AST
unThunk = everywhere convert
  where
  convert (Block ss []) = Block ss []
  convert (Block ss jss) = case Array.unsnoc jss of
    Just { init: ini, last: Return _ (App _ (Function _ Nothing [] (Block _ body)) []) } ->
      Block ss (ini <> body)
    _ -> Block ss jss
  convert js = js

evaluateIifes :: AST -> AST
evaluateIifes = everywhere convert
  where
  convert (App _ (Function _ Nothing [] (Block _ [Return _ ret])) []) = ret
  convert (App _ (Function _ Nothing idents (Block _ [Return ss ret])) [])
    | not (any (\i -> isReassigned i ret) idents) =
        replaceIdents (map (\i -> Tuple i (Var ss "undefined")) idents) ret
  convert js = js

inlineVariables :: AST -> AST
inlineVariables = everywhere (removeFromBlock go)
  where
  go :: Array AST -> Array AST
  go arr = case Array.uncons arr of
    Nothing -> []
    Just { head: VariableIntroduction _ var (Just (Tuple _ js)) , tail: sts }
      | shouldInline js
      , not (any (\s -> isReassigned var s) sts)
      , not (any (\s -> isRebound js s) sts)
      , not (any (\s -> isUpdated var s) sts) ->
        go (map (replaceIdent var js) sts)
    Just { head: s, tail: sts } -> Array.cons s (go sts)
