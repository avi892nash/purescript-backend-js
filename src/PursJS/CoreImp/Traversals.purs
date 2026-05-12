-- | Generic AST traversals: `everywhere`, `everything`, `everywhereTopDown`.
-- | Mirrors `Language.PureScript.CoreImp.AST.everywhere` etc. in the Haskell
-- | compiler.
module PursJS.CoreImp.Traversals where

import Prelude

import Data.Foldable (foldl)
import Data.Maybe (Maybe(..))
import Data.Traversable (traverse)
import Data.Tuple (Tuple(..))
import PursJS.CoreImp.AST (AST(..))

-- | Bottom-up: rewrite children first, then apply f to the node.
everywhere :: (AST -> AST) -> AST -> AST
everywhere f = go
  where
  go (Unary ss op j) = f (Unary ss op (go j))
  go (Binary ss op j1 j2) = f (Binary ss op (go j1) (go j2))
  go (ArrayLiteral ss js) = f (ArrayLiteral ss (map go js))
  go (Indexer ss j1 j2) = f (Indexer ss (go j1) (go j2))
  go (ObjectLiteral ss js) = f (ObjectLiteral ss (map (\(Tuple k v) -> Tuple k (go v)) js))
  go (Function ss name args j) = f (Function ss name args (go j))
  go (App ss j js) = f (App ss (go j) (map go js))
  go (Block ss js) = f (Block ss (map go js))
  go (VariableIntroduction ss name Nothing) = f (VariableIntroduction ss name Nothing)
  go (VariableIntroduction ss name (Just (Tuple eff j))) =
    f (VariableIntroduction ss name (Just (Tuple eff (go j))))
  go (Assignment ss j1 j2) = f (Assignment ss (go j1) (go j2))
  go (While ss j1 j2) = f (While ss (go j1) (go j2))
  go (For ss name j1 j2 j3) = f (For ss name (go j1) (go j2) (go j3))
  go (ForIn ss name j1 j2) = f (ForIn ss name (go j1) (go j2))
  go (IfElse ss j1 j2 j3) = f (IfElse ss (go j1) (go j2) (map go j3))
  go (Return ss js) = f (Return ss (go js))
  go (Throw ss js) = f (Throw ss (go js))
  go (InstanceOf ss j1 j2) = f (InstanceOf ss (go j1) (go j2))
  go (Comment com j) = f (Comment com (go j))
  go other = f other

-- | Top-down: apply f first, then rewrite children.
everywhereTopDown :: (AST -> AST) -> AST -> AST
everywhereTopDown f = go <<< f
  where
  go (Unary ss op j) = Unary ss op (go (f j))
  go (Binary ss op j1 j2) = Binary ss op (go (f j1)) (go (f j2))
  go (ArrayLiteral ss js) = ArrayLiteral ss (map (go <<< f) js)
  go (Indexer ss j1 j2) = Indexer ss (go (f j1)) (go (f j2))
  go (ObjectLiteral ss js) =
    ObjectLiteral ss (map (\(Tuple k v) -> Tuple k (go (f v))) js)
  go (Function ss name args j) = Function ss name args (go (f j))
  go (App ss j js) = App ss (go (f j)) (map (go <<< f) js)
  go (Block ss js) = Block ss (map (go <<< f) js)
  go (VariableIntroduction ss name Nothing) =
    VariableIntroduction ss name Nothing
  go (VariableIntroduction ss name (Just (Tuple eff j))) =
    VariableIntroduction ss name (Just (Tuple eff (go (f j))))
  go (Assignment ss j1 j2) = Assignment ss (go (f j1)) (go (f j2))
  go (While ss j1 j2) = While ss (go (f j1)) (go (f j2))
  go (For ss name j1 j2 j3) =
    For ss name (go (f j1)) (go (f j2)) (go (f j3))
  go (ForIn ss name j1 j2) = ForIn ss name (go (f j1)) (go (f j2))
  go (IfElse ss j1 j2 j3) =
    IfElse ss (go (f j1)) (go (f j2)) (map (go <<< f) j3)
  go (Return ss j) = Return ss (go (f j))
  go (Throw ss j) = Throw ss (go (f j))
  go (InstanceOf ss j1 j2) = InstanceOf ss (go (f j1)) (go (f j2))
  go (Comment com j) = Comment com (go (f j))
  go other = other

-- | Monadic top-down traversal: apply f, then recurse into children.
everywhereTopDownM :: forall m. Monad m => (AST -> m AST) -> AST -> m AST
everywhereTopDownM f x = f x >>= go
  where
  fp :: AST -> m AST
  fp y = f y >>= go

  go :: AST -> m AST
  go (Unary ss op j) = Unary ss op <$> fp j
  go (Binary ss op j1 j2) = Binary ss op <$> fp j1 <*> fp j2
  go (ArrayLiteral ss js) = ArrayLiteral ss <$> traverse fp js
  go (Indexer ss j1 j2) = Indexer ss <$> fp j1 <*> fp j2
  go (ObjectLiteral ss js) =
    ObjectLiteral ss <$> traverse (\(Tuple k v) -> Tuple k <$> fp v) js
  go (Function ss name args j) = Function ss name args <$> fp j
  go (App ss j js) = App ss <$> fp j <*> traverse fp js
  go (Block ss js) = Block ss <$> traverse fp js
  go (VariableIntroduction ss name Nothing) =
    pure (VariableIntroduction ss name Nothing)
  go (VariableIntroduction ss name (Just (Tuple eff j))) =
    (\j' -> VariableIntroduction ss name (Just (Tuple eff j'))) <$> fp j
  go (Assignment ss j1 j2) = Assignment ss <$> fp j1 <*> fp j2
  go (While ss j1 j2) = While ss <$> fp j1 <*> fp j2
  go (For ss name j1 j2 j3) = For ss name <$> fp j1 <*> fp j2 <*> fp j3
  go (ForIn ss name j1 j2) = ForIn ss name <$> fp j1 <*> fp j2
  go (IfElse ss j1 j2 j3) =
    IfElse ss <$> fp j1 <*> fp j2 <*> traverse fp j3
  go (Return ss j) = Return ss <$> fp j
  go (Throw ss j) = Throw ss <$> fp j
  go (InstanceOf ss j1 j2) = InstanceOf ss <$> fp j1 <*> fp j2
  go (Comment com j) = Comment com <$> fp j
  go other = pure other

-- | Fold over all nodes (including the root). Combine with the supplied
-- | semigroup-like combinator and accumulator function.
everything :: forall r. (r -> r -> r) -> (AST -> r) -> AST -> r
everything combine f = go
  where
  go ast = case ast of
    Unary _ _ j1 -> f ast `combine` go j1
    Binary _ _ j1 j2 -> f ast `combine` go j1 `combine` go j2
    ArrayLiteral _ js -> foldl combine (f ast) (map go js)
    Indexer _ j1 j2 -> f ast `combine` go j1 `combine` go j2
    ObjectLiteral _ js ->
      foldl combine (f ast) (map (\(Tuple _ v) -> go v) js)
    Function _ _ _ j1 -> f ast `combine` go j1
    App _ j1 js ->
      foldl combine (f ast `combine` go j1) (map go js)
    Block _ js -> foldl combine (f ast) (map go js)
    VariableIntroduction _ _ (Just (Tuple _ j1)) -> f ast `combine` go j1
    Assignment _ j1 j2 -> f ast `combine` go j1 `combine` go j2
    While _ j1 j2 -> f ast `combine` go j1 `combine` go j2
    For _ _ j1 j2 j3 -> f ast `combine` go j1 `combine` go j2 `combine` go j3
    ForIn _ _ j1 j2 -> f ast `combine` go j1 `combine` go j2
    IfElse _ j1 j2 Nothing -> f ast `combine` go j1 `combine` go j2
    IfElse _ j1 j2 (Just j3) -> f ast `combine` go j1 `combine` go j2 `combine` go j3
    Return _ j1 -> f ast `combine` go j1
    Throw _ j1 -> f ast `combine` go j1
    InstanceOf _ j1 j2 -> f ast `combine` go j1 `combine` go j2
    Comment _ j1 -> f ast `combine` go j1
    _ -> f ast
