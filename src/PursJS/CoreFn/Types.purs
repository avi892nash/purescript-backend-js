module PursJS.CoreFn.Types where

import Prelude

import Data.Either (Either)
import Data.Map (Map)
import Data.Maybe (Maybe)
import Data.Tuple (Tuple)
import PursJS.Comments (Comment)
import PursJS.Names (Ident, ModuleName, ProperName, Qualified, SourceSpan)
import PursJS.PSString (PSString)

-- | Data constructor metadata
data ConstructorType = ProductType | SumType

derive instance Eq ConstructorType
derive instance Ord ConstructorType

-- | Metadata annotations
data Meta
  = IsConstructor ConstructorType (Array Ident)
  | IsNewtype
  | IsTypeClassConstructor
  | IsForeign
  | IsWhere
  | IsSyntheticApp

derive instance Eq Meta
derive instance Ord Meta

-- | Annotation: source span + comments + optional meta
type Ann = { ss :: SourceSpan, comments :: Array Comment, meta :: Maybe Meta }

-- | Literal values (used both in expressions and binders)
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

-- | Core functional expressions
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

-- | A let or module binding
data Bind a
  = NonRec a Ident (Expr a)
  | Rec (Array { ann :: a, ident :: Ident, expr :: Expr a })

-- | Guard = boolean expression
type Guard a = Expr a

-- | A case alternative
data CaseAlternative a = CaseAlternative
  { binders :: Array (Binder a)
  , result :: Either (Array (Tuple (Guard a) (Expr a))) (Expr a)
  }

-- | Pattern binders
data Binder a
  = NullBinder a
  | LiteralBinder a (Literal (Binder a))
  | VarBinder a Ident
  | ConstructorBinder a (Qualified ProperName) (Qualified ProperName) (Array (Binder a))
  | NamedBinder a Ident (Binder a)

-- | The CoreFn module
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

-- Annotation accessors
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

extractBinderAnn :: forall a. Binder a -> a
extractBinderAnn = case _ of
  NullBinder a -> a
  LiteralBinder a _ -> a
  VarBinder a _ -> a
  ConstructorBinder a _ _ _ -> a
  NamedBinder a _ _ -> a
