-- | Minimal port of `Language.PureScript.CoreFn.Laziness.applyLazinessTransform`
-- | (purescript@c4a35b3, src/Language/PureScript/CoreFn/Laziness.hs:1-568).
-- |
-- | The full Haskell version is a sophisticated dependency analysis that picks
-- | the minimum set of bindings to lazy-wrap. We implement a simpler rule that
-- | preserves correctness:
-- |
-- |   "If any binding in a Rec group has an *eager* reference to one of its
-- |    siblings (i.e. a `Var sibling` not inside a `Function`), lazy-wrap ALL
-- |    bindings in the group."
-- |
-- | This catches the cases that matter — mutually-recursive instance
-- | dictionaries where one initializer eagerly evaluates a type-class method
-- | on another sibling dictionary — and leaves singleton self-recursive
-- | functions (like `gcd`) untouched.
-- |
-- | Outputs:
-- |
-- |   var $lazy_b1 = $runtime_lazy("b1", "Module", function () { return E1; });
-- |   var $lazy_b2 = $runtime_lazy("b2", "Module", function () { return E2; });
-- |   ...
-- |   var b1 = $lazy_b1(0);
-- |   var b2 = $lazy_b2(0);
-- |
-- | with sibling references inside each Ei rewritten as `$lazy_bj(0)` calls.
-- |
-- | The `$runtime_lazy` runtime helper itself is defined inline by
-- | `PursJS.CodeGen.JS` whenever this module reports `needsRuntimeLazy = true`,
-- | mirroring JS.hs:209-229.
module PursJS.CodeGen.Laziness
  ( hasEagerSiblingRef
  , rewriteSiblingRefs
  , lazyName
  , runtimeLazyAST
  ) where

import Prelude

import Data.Array as Array
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Data.Set (Set)
import Data.Set as Set
import Data.Tuple (Tuple(..))
import PursJS.CoreImp.AST (AST(..), BinaryOperator(..), InitializerEffects(..), UnaryOperator(..))
import PursJS.PSString (mkString)

-- | Compute whether `ast` contains a `Var name` (where `name ∈ siblings`)
-- | that is NOT inside any nested `Function` literal — UNLESS that Function
-- | is immediately applied as an IIFE (in which case it IS eager).
-- |
-- | This catches both the obvious case (a bare `Var sibling` at the top of
-- | an initializer) and the IIFE case
-- |
-- |   (function () { return sibling; })()
-- |
-- | which the codegen produces for ObjectUpdate, Let, etc.
hasEagerSiblingRef :: Set String -> AST -> Boolean
hasEagerSiblingRef siblings = go
  where
  go :: AST -> Boolean
  go (Var _ n) = Set.member n siblings
  -- A bare Function literal (not being applied) is not eager.
  go (Function _ _ _ _) = false
  go (NumericLiteral _ _) = false
  go (StringLiteral _ _) = false
  go (BooleanLiteral _ _) = false
  go (Unary _ _ a) = go a
  go (Binary _ _ a b) = go a || go b
  go (ArrayLiteral _ xs) = Array.any go xs
  go (Indexer _ a b) = go a || go b
  go (ObjectLiteral _ ps) = Array.any (\(Tuple _ v) -> go v) ps
  -- An IIFE — `(function (args) { body })(args')` — eagerly executes its
  -- body. Walk into the function body too (treating each parameter as a
  -- regular binder; references that match a sibling are still eager).
  go (App _ (Function _ _ _ body) xs) = goBlock body || Array.any go xs
  go (App _ f xs) = go f || Array.any go xs
  go (ModuleAccessor _ _ _) = false
  go (Block _ xs) = Array.any go xs
  go (VariableIntroduction _ _ Nothing) = false
  go (VariableIntroduction _ _ (Just (Tuple _ a))) = go a
  go (Assignment _ a b) = go a || go b
  go (While _ a b) = go a || go b
  go (For _ _ a b c) = go a || go b || go c
  go (ForIn _ _ a b) = go a || go b
  go (IfElse _ a b c) = go a || go b || maybe false go c
  go (Return _ a) = go a
  go (ReturnNoResult _) = false
  go (Throw _ a) = go a
  go (InstanceOf _ a b) = go a || go b
  go (Comment _ a) = go a

  -- Walk into a Block (the body of an IIFE) at the same eager level.
  goBlock :: AST -> Boolean
  goBlock (Block _ xs) = Array.any go xs
  goBlock other = go other

  maybe :: Boolean -> (AST -> Boolean) -> Maybe AST -> Boolean
  maybe d f = case _ of
    Just a -> f a
    Nothing -> d

-- | Rewrite every `Var n` (where n is in `siblings`) inside `ast` to
-- | `$lazy_n(0)`. Walks into Functions too — the lazy refs need to be there
-- | so that when the deferred initializer runs, it uses the lazy version.
rewriteSiblingRefs :: Set String -> AST -> AST
rewriteSiblingRefs siblings = go
  where
  go :: AST -> AST
  go (Var ss n)
    | Set.member n siblings =
        App ss (Var ss (lazyName n)) [NumericLiteral ss (Left 0)]
  go (Unary ss op a) = Unary ss op (go a)
  go (Binary ss op a b) = Binary ss op (go a) (go b)
  go (ArrayLiteral ss xs) = ArrayLiteral ss (map go xs)
  go (Indexer ss a b) = Indexer ss (go a) (go b)
  go (ObjectLiteral ss ps) = ObjectLiteral ss (map (\(Tuple k v) -> Tuple k (go v)) ps)
  go (Function ss n args body) = Function ss n args (go body)
  go (App ss f xs) = App ss (go f) (map go xs)
  go (Block ss xs) = Block ss (map go xs)
  go (VariableIntroduction ss n Nothing) = VariableIntroduction ss n Nothing
  go (VariableIntroduction ss n (Just (Tuple eff a))) =
    VariableIntroduction ss n (Just (Tuple eff (go a)))
  go (Assignment ss a b) = Assignment ss (go a) (go b)
  go (While ss a b) = While ss (go a) (go b)
  go (For ss n a b c) = For ss n (go a) (go b) (go c)
  go (ForIn ss n a b) = ForIn ss n (go a) (go b)
  go (IfElse ss a b c) = IfElse ss (go a) (go b) (map go c)
  go (Return ss a) = Return ss (go a)
  go (Throw ss a) = Throw ss (go a)
  go (InstanceOf ss a b) = InstanceOf ss (go a) (go b)
  go (Comment c a) = Comment c (go a)
  go other = other

lazyName :: String -> String
lazyName n = "$lazy_" <> n

-- | The literal `$runtime_lazy` runtime helper. Matches JS.hs:209-229.
-- | Emitted at the top of any module that uses lazy wrapping.
runtimeLazyAST :: AST
runtimeLazyAST = VariableIntroduction Nothing "$runtime_lazy" (Just (Tuple UnknownEffects body))
  where
  body = Function Nothing Nothing ["name", "moduleName", "init"] outerBlock
  outerBlock = Block Nothing
    [ VariableIntroduction Nothing "state"
        (Just (Tuple UnknownEffects (intLit 0)))
    , VariableIntroduction Nothing "val" Nothing
    , Return Nothing returnFn
    ]
  returnFn = Function Nothing Nothing ["lineNumber"] returnBody
  returnBody = Block Nothing
    [ IfElse Nothing (stateEq 2) (Return Nothing (Var Nothing "val")) Nothing
    , IfElse Nothing (stateEq 1) throwRef Nothing
    , Assignment Nothing (Var Nothing "state") (intLit 1)
    , Assignment Nothing (Var Nothing "val") (App Nothing (Var Nothing "init") [])
    , Assignment Nothing (Var Nothing "state") (intLit 2)
    , Return Nothing (Var Nothing "val")
    ]
  stateEq n = Binary Nothing EqualTo (Var Nothing "state") (intLit n)
  intLit n = NumericLiteral Nothing (Left n)
  throwRef = Throw Nothing (Unary Nothing New (App Nothing (Var Nothing "ReferenceError") refArgs))
  refArgs =
    [ foldAdd
        [ Var Nothing "name"
        , StringLiteral Nothing (mkString " was needed before it finished initializing (module ")
        , Var Nothing "moduleName"
        , StringLiteral Nothing (mkString ", line ")
        , Var Nothing "lineNumber"
        , StringLiteral Nothing (mkString ")")
        ]
    , Var Nothing "moduleName"
    , Var Nothing "lineNumber"
    ]

foldAdd :: Array AST -> AST
foldAdd arr = case Array.uncons arr of
  Just { head, tail } -> Array.foldl (\acc x -> Binary Nothing Add acc x) head tail
  Nothing -> Var Nothing "<<empty foldAdd>>"
