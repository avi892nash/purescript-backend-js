-- | Ports the CoreFn AST (purescript@c4a35b3). The Haskell source is split
-- | across several modules; we collect them here:
-- |
-- |   Meta, ConstructorType        src/Language/PureScript/CoreFn/Meta.hs:13-51
-- |   Ann                          src/Language/PureScript/CoreFn/Ann.hs (type Ann = (SourceSpan, [Comment], Maybe Meta))
-- |   Literal                      src/Language/PureScript/AST/Literals.hs
-- |   Expr, Bind, CaseAlternative, Guard
-- |                                src/Language/PureScript/CoreFn/Expr.hs:18-93
-- |   Binder                       src/Language/PureScript/CoreFn/Binders.hs:14-34
-- |   Module                       src/Language/PureScript/CoreFn/Module.hs:15-25
-- |   extractAnn                   CoreFn/Expr.hs:98-107
-- |   extractBinderAnn             CoreFn/Binders.hs:37-42
module PursJS.CoreFn.Types where

import Prelude

import Data.Either (Either)
import Data.Map (Map)
import Data.Maybe (Maybe)
import Data.Tuple (Tuple)
import PursJS.Comments (Comment)
import PursJS.Names (Ident, ModuleName, ProperName, Qualified, SourceSpan)
import PursJS.PSString (PSString)

-- | CoreFn/Meta.hs:43-51 — `data ConstructorType = ProductType | SumType`.
data ConstructorType = ProductType | SumType

derive instance Eq ConstructorType
derive instance Ord ConstructorType

-- | CoreFn/Meta.hs:13-38 — `data Meta`.
data Meta
  = IsConstructor ConstructorType (Array Ident)
  | IsNewtype
  | IsTypeClassConstructor
  | IsForeign
  | IsWhere
  | IsSyntheticApp

derive instance Eq Meta
derive instance Ord Meta

-- | CoreFn/Ann.hs — `type Ann = (SourceSpan, [Comment], Maybe Meta)`.
-- | Switched from a 3-tuple to a record because PureScript doesn't have nice
-- | tuple-record syntax and `.ss`/`.meta` reads more clearly than `fst`/`snd`/`thd`.
type Ann = { ss :: SourceSpan, comments :: Array Comment, meta :: Maybe Meta }

-- | AST/Literals.hs — `data Literal a`.
-- | The Haskell `NumericLiteral (Either Integer Double)` is split into two
-- | constructors here to avoid wrapping every literal in `Either`.
data Literal a
  = NumericLiteralInt Int
  | NumericLiteralNumber Number
  | StringLiteral PSString
  | CharLiteral Char
  | BooleanLiteral Boolean
  | ArrayLiteral (Array a)
  | ObjectLiteral (Array (Tuple PSString a))

derive instance Eq a => Eq (Literal a)
derive instance Ord a => Ord (Literal a)

-- | CoreFn/Expr.hs:18-55 — `data Expr a`.
data Expr a
  = Literal a (Literal (Expr a))
  | Constructor a ProperName ProperName (Array Ident)
  | Accessor a PSString (Expr a)
  | ObjectUpdate a (Expr a) (Maybe (Array PSString)) (Array (Tuple PSString (Expr a)))
  | Abs a Ident (Expr a)
  | App a (Expr a) (Expr a)
  | Var a (Qualified Ident)
  | Case a (Array (Expr a)) (Array (CaseAlternative a))
  | Let a (Array (Bind a)) (Expr a)

-- | CoreFn/Expr.hs:60-68 — `data Bind a = NonRec a Ident (Expr a) | Rec [((a, Ident), Expr a)]`.
-- | The `Rec` shape uses a record array for cleaner field access (Haskell uses
-- | nested tuples `((Ann, Ident), Expr Ann)`).
data Bind a
  = NonRec a Ident (Expr a)
  | Rec (Array { ann :: a, ident :: Ident, expr :: Expr a })

-- | CoreFn/Expr.hs:73 — `type Guard a = Expr a`.
type Guard a = Expr a

-- | CoreFn/Expr.hs:78-87 — `data CaseAlternative a`.
data CaseAlternative a = CaseAlternative
  { binders :: Array (Binder a)
  , result :: Either (Array (Tuple (Guard a) (Expr a))) (Expr a)
  }

-- | CoreFn/Binders.hs:14-34 — `data Binder a`.
data Binder a
  = NullBinder a
  | LiteralBinder a (Literal (Binder a))
  | VarBinder a Ident
  | ConstructorBinder a (Qualified ProperName) (Qualified ProperName) (Array (Binder a))
  | NamedBinder a Ident (Binder a)

-- | CoreFn/Module.hs:15-25 — `data Module a = Module { ... }`.
-- | `moduleForeign` is renamed to `foreign_` (PureScript can't use `foreign` as
-- | a record label because it's a reserved word).
type Module a =
  { sourceSpan :: SourceSpan
  , comments :: Array Comment
  , name :: ModuleName
  , path :: String
  , imports :: Array (Tuple a ModuleName)
  , exports :: Array Ident
  , reExports :: Map ModuleName (Array Ident)
  , foreign_ :: Array Ident
  , decls :: Array (Bind a)
  }

-- | CoreFn/Expr.hs:98-107 — `extractAnn`.
extractAnn :: forall a. Expr a -> a
extractAnn = case _ of
  Literal a _ -> a
  Constructor a _ _ _ -> a
  Accessor a _ _ -> a
  ObjectUpdate a _ _ _ -> a
  Abs a _ _ -> a
  App a _ _ -> a
  Var a _ -> a
  Case a _ _ -> a
  Let a _ _ -> a

-- | CoreFn/Binders.hs:37-42 — `extractBinderAnn`.
extractBinderAnn :: forall a. Binder a -> a
extractBinderAnn = case _ of
  NullBinder a -> a
  LiteralBinder a _ -> a
  VarBinder a _ -> a
  ConstructorBinder a _ _ _ -> a
  NamedBinder a _ _ -> a
