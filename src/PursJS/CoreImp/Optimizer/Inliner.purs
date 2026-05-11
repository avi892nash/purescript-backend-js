-- | Basic AST-level inlining passes that don't require knowledge of specific
-- | type class dictionaries. Mirrors `Language.PureScript.CoreImp.Optimizer.Inliner`
-- | for the subset we currently need.
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
