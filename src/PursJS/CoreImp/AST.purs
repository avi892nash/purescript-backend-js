-- | Ports `Language.PureScript.CoreImp.AST` (purescript@c4a35b3,
-- | src/Language/PureScript/CoreImp/AST.hs).
-- |
-- | The "simplified imperative" JS AST that sits between CoreFn and the
-- | pretty printer. Every JavaScript construct the codegen needs to emit has
-- | a constructor here.
-- |
-- | Mapping (PursJS <-> CoreImp/AST.hs line):
-- |   UnaryOperator             AST.hs:17-23
-- |   BinaryOperator            AST.hs:26-46
-- |   CIComments                AST.hs:50-53
-- |   InitializerEffects        AST.hs:59
-- |   AST                       AST.hs:62-111
-- |
-- | The `everywhere` / `everything` / `everywhereTopDown` / `everywhereTopDownM`
-- | traversals from AST.hs:172-243 are in `PursJS.CoreImp.Traversals`.
module PursJS.CoreImp.AST where

import Prelude

import Data.Either (Either)
import Data.List.NonEmpty (NonEmptyList)
import Data.Maybe (Maybe)
import Data.Tuple (Tuple)
import PursJS.Comments (Comment)
import PursJS.Names (ModuleName, SourceSpan)
import PursJS.PSString (PSString)

data UnaryOperator
  = Negate
  | Not
  | BitwiseNot
  | Positive
  | New

derive instance Eq UnaryOperator
derive instance Ord UnaryOperator

data BinaryOperator
  = Add
  | Subtract
  | Multiply
  | Divide
  | Modulus
  | EqualTo
  | NotEqualTo
  | LessThan
  | LessThanOrEqualTo
  | GreaterThan
  | GreaterThanOrEqualTo
  | And
  | Or
  | BitwiseAnd
  | BitwiseOr
  | BitwiseXor
  | ShiftLeft
  | ShiftRight
  | ZeroFillShiftRight

derive instance Eq BinaryOperator
derive instance Ord BinaryOperator

data CIComments
  = SourceComments (Array Comment)
  | PureAnnotation

derive instance Eq CIComments

data InitializerEffects = NoEffects | UnknownEffects

derive instance Eq InitializerEffects

-- | Simplified imperative JS expressions.
-- | Either-encoded numeric: Left = Int, Right = Number (matching the Haskell
-- | encoding `Either Integer Double`).
data AST
  = NumericLiteral (Maybe SourceSpan) (Either Int Number)
  | StringLiteral (Maybe SourceSpan) PSString
  | BooleanLiteral (Maybe SourceSpan) Boolean
  | Unary (Maybe SourceSpan) UnaryOperator AST
  | Binary (Maybe SourceSpan) BinaryOperator AST AST
  | ArrayLiteral (Maybe SourceSpan) (Array AST)
  | Indexer (Maybe SourceSpan) AST AST
  | ObjectLiteral (Maybe SourceSpan) (Array (Tuple PSString AST))
  | Function (Maybe SourceSpan) (Maybe String) (Array String) AST
  | App (Maybe SourceSpan) AST (Array AST)
  | Var (Maybe SourceSpan) String
  | ModuleAccessor (Maybe SourceSpan) ModuleName PSString
  | Block (Maybe SourceSpan) (Array AST)
  | VariableIntroduction (Maybe SourceSpan) String (Maybe (Tuple InitializerEffects AST))
  | Assignment (Maybe SourceSpan) AST AST
  | While (Maybe SourceSpan) AST AST
  | For (Maybe SourceSpan) String AST AST AST
  | ForIn (Maybe SourceSpan) String AST AST
  | IfElse (Maybe SourceSpan) AST AST (Maybe AST)
  | Return (Maybe SourceSpan) AST
  | ReturnNoResult (Maybe SourceSpan)
  | Throw (Maybe SourceSpan) AST
  | InstanceOf (Maybe SourceSpan) AST AST
  | Comment CIComments AST

-- Re-export NonEmptyList so Module exports can use it
_unused :: forall a. NonEmptyList a -> NonEmptyList a
_unused = identity
