-- | Parse a corefn.json file into the CoreFn AST.
-- |
-- | The JSON shape produced by `purs --codegen corefn` is documented by example
-- | in the Haskell module Language.PureScript.CoreFn.ToJSON; here we read it
-- | directly using argonaut-core's Json type.
module PursJS.CoreFn.FromJSON where

import Prelude

import Data.Argonaut.Core (Json, isNull, toArray, toBoolean, toNumber, toObject, toString)
import Data.Argonaut.Parser (jsonParser)
import Data.Array as Array
import Data.Either (Either(..), note)
import Data.Int as Int
import Data.Map (Map)
import Data.Map as Map
import Data.Maybe (Maybe(..))
import Data.String as Str
import Data.String.CodeUnits as CU
import Data.Traversable (traverse)
import Data.Tuple (Tuple(..))
import Foreign.Object (Object)
import Foreign.Object as Obj
import PursJS.Comments (Comment(..))
import PursJS.CoreFn.Types (Ann, Bind(..), Binder(..), CaseAlternative(..), ConstructorType(..), Expr(..), Literal(..), Meta(..), Module)
import PursJS.Names (Ident(..), ModuleName(..), ProperName(..), Qualified(..), QualifiedBy(..), SourcePos(..), SourceSpan(..), unusedIdent)
import PursJS.PSString (PSString, mkString)

type Parser a = Either String a

parseModule :: String -> Either String (Module Ann)
parseModule s = jsonParser s >>= moduleFromJson

-- ---------- helpers ----------

asObject :: Json -> Parser (Object Json)
asObject j = note "expected object" (toObject j)

asArray :: Json -> Parser (Array Json)
asArray j = note "expected array" (toArray j)

asString :: Json -> Parser String
asString j = note "expected string" (toString j)

asInt :: Json -> Parser Int
asInt j = note "expected int" (toNumber j >>= Int.fromNumber)

asNumber :: Json -> Parser Number
asNumber j = note "expected number" (toNumber j)

asBool :: Json -> Parser Boolean
asBool j = note "expected boolean" (toBoolean j)

field :: String -> Object Json -> Parser Json
field k o = note ("missing field: " <> k) (Obj.lookup k o)

fieldStr :: String -> Object Json -> Parser String
fieldStr k o = field k o >>= asString

-- ---------- module ----------

moduleFromJson :: Json -> Parser (Module Ann)
moduleFromJson j = do
  o <- asObject j
  modulePath <- fieldStr "modulePath" o
  name <- field "moduleName" o >>= moduleNameFromJson
  ss <- field "sourceSpan" o >>= sourceSpanFromJson modulePath
  imports <- field "imports" o >>= asArray >>= traverse (importFromJson modulePath)
  exports <- field "exports" o >>= asArray >>= traverse identFromJson
  reExports <- field "reExports" o >>= reExportsFromJson
  decls <- field "decls" o >>= asArray >>= traverse (bindFromJson modulePath)
  foreigns <- field "foreign" o >>= asArray >>= traverse identFromJson
  comments <- field "comments" o >>= asArray >>= traverse commentFromJson
  pure
    { sourceSpan: ss
    , comments
    , name
    , path: modulePath
    , imports
    , exports
    , reExports
    , foreign_: foreigns
    , decls
    }

importFromJson :: String -> Json -> Parser (Tuple Ann ModuleName)
importFromJson modulePath j = do
  o <- asObject j
  ann <- field "annotation" o >>= annFromJson modulePath
  mn <- field "moduleName" o >>= moduleNameFromJson
  pure (Tuple ann mn)

reExportsFromJson :: Json -> Parser (Map ModuleName (Array Ident))
reExportsFromJson j = do
  o <- asObject j
  pairs <- traverse asValues (Obj.toUnfoldable o :: Array (Tuple String Json))
  pure (Map.fromFoldable pairs)
  where
  asValues :: Tuple String Json -> Parser (Tuple ModuleName (Array Ident))
  asValues (Tuple k v) = do
    arr <- asArray v
    idents <- traverse (\jj -> Ident <$> asString jj) arr
    pure (Tuple (ModuleName k) idents)

-- ---------- comments ----------

commentFromJson :: Json -> Parser Comment
commentFromJson j = do
  o <- asObject j
  case Obj.lookup "LineComment" o of
    Just v -> LineComment <$> asString v
    Nothing -> case Obj.lookup "BlockComment" o of
      Just v -> BlockComment <$> asString v
      Nothing -> Left "unknown comment shape"

-- ---------- ann ----------

annFromJson :: String -> Json -> Parser Ann
annFromJson modulePath j = do
  o <- asObject j
  ss <- field "sourceSpan" o >>= sourceSpanFromJson modulePath
  meta <- field "meta" o >>= metaFromJson
  pure { ss, comments: [], meta }

sourceSpanFromJson :: String -> Json -> Parser SourceSpan
sourceSpanFromJson modulePath j = do
  o <- asObject j
  start <- field "start" o >>= asArray >>= twoInts
  end <- field "end" o >>= asArray >>= twoInts
  pure (SourceSpan { name: modulePath, start, end })

twoInts :: Array Json -> Parser SourcePos
twoInts arr = case arr of
  [a, b] -> SourcePos <$> asInt a <*> asInt b
  _ -> Left "expected [line, col]"

metaFromJson :: Json -> Parser (Maybe Meta)
metaFromJson j
  | isNull j = pure Nothing
  | otherwise = do
      o <- asObject j
      ty <- fieldStr "metaType" o
      case ty of
        "IsConstructor" -> do
          ct <- field "constructorType" o >>= constructorTypeFromJson
          is <- field "identifiers" o >>= asArray >>= traverse identFromJson
          pure (Just (IsConstructor ct is))
        "IsNewtype" -> pure (Just IsNewtype)
        "IsTypeClassConstructor" -> pure (Just IsTypeClassConstructor)
        "IsForeign" -> pure (Just IsForeign)
        "IsWhere" -> pure (Just IsWhere)
        "IsSyntheticApp" -> pure (Just IsSyntheticApp)
        other -> Left ("unknown Meta: " <> other)

constructorTypeFromJson :: Json -> Parser ConstructorType
constructorTypeFromJson j = do
  t <- asString j
  case t of
    "ProductType" -> pure ProductType
    "SumType" -> pure SumType
    other -> Left ("unknown ConstructorType: " <> other)

-- ---------- names ----------

identFromJson :: Json -> Parser Ident
identFromJson j = do
  s <- asString j
  pure $ if s == unusedIdent then UnusedIdent else Ident s

properNameFromJson :: Json -> Parser ProperName
properNameFromJson j = ProperName <$> asString j

moduleNameFromJson :: Json -> Parser ModuleName
moduleNameFromJson j = do
  arr <- asArray j
  parts <- traverse asString arr
  pure (ModuleName (Str.joinWith "." parts))

qualifiedFromJson :: forall a. (String -> a) -> Json -> Parser (Qualified a)
qualifiedFromJson f j = do
  o <- asObject j
  case Obj.lookup "moduleName" o of
    Just mnJ -> do
      mn <- moduleNameFromJson mnJ
      id <- field "identifier" o >>= asString
      pure (Qualified (ByModuleName mn) (f id))
    Nothing -> case Obj.lookup "sourcePos" o of
      Just spJ -> do
        arr <- asArray spJ
        sp <- case arr of
          [l, c] -> SourcePos <$> asInt l <*> asInt c
          _ -> Left "sourcePos must be [line,col]"
        id <- field "identifier" o >>= asString
        pure (Qualified (BySourcePos sp) (f id))
      Nothing -> Left "qualified: needs moduleName or sourcePos"

-- ---------- literal ----------

literalFromJson :: forall a. (Json -> Parser a) -> Json -> Parser (Literal a)
literalFromJson t j = do
  o <- asObject j
  ty <- fieldStr "literalType" o
  case ty of
    "IntLiteral" -> NumericLiteralInt <$> (field "value" o >>= asInt)
    "NumberLiteral" -> NumericLiteralNumber <$> (field "value" o >>= asNumber)
    "StringLiteral" -> StringLiteral <<< mkString <$> (field "value" o >>= asString)
    "CharLiteral" -> do
      v <- field "value" o >>= asString
      case CU.charAt 0 v of
        Just c -> pure (CharLiteral c)
        Nothing -> Left "empty char literal"
    "BooleanLiteral" -> BooleanLiteral <$> (field "value" o >>= asBool)
    "ArrayLiteral" -> do
      arr <- field "value" o >>= asArray
      ArrayLiteral <$> traverse t arr
    "ObjectLiteral" -> do
      arr <- field "value" o >>= asArray
      ObjectLiteral <$> traverse (pairFromJson t) arr
    other -> Left ("unknown literal: " <> other)

pairFromJson :: forall a. (Json -> Parser a) -> Json -> Parser (Tuple PSString a)
pairFromJson t j = do
  arr <- asArray j
  case arr of
    [k, v] -> do
      ks <- asString k
      a <- t v
      pure (Tuple (mkString ks) a)
    _ -> Left "expected [k, v] pair"

-- ---------- expr ----------

exprFromJson :: String -> Json -> Parser (Expr Ann)
exprFromJson modulePath j = do
  o <- asObject j
  ty <- fieldStr "type" o
  case ty of
    "Var" -> do
      ann <- field "annotation" o >>= annFromJson modulePath
      qi <- field "value" o >>= qualifiedFromJson Ident
      pure (Var ann qi)
    "Literal" -> do
      ann <- field "annotation" o >>= annFromJson modulePath
      lit <- field "value" o >>= literalFromJson (exprFromJson modulePath)
      pure (Literal ann lit)
    "Constructor" -> do
      ann <- field "annotation" o >>= annFromJson modulePath
      tyn <- field "typeName" o >>= properNameFromJson
      con <- field "constructorName" o >>= properNameFromJson
      fs <- field "fieldNames" o >>= asArray >>= traverse identFromJson
      pure (Constructor ann tyn con fs)
    "Accessor" -> do
      ann <- field "annotation" o >>= annFromJson modulePath
      fn <- field "fieldName" o >>= asString
      e <- field "expression" o >>= exprFromJson modulePath
      pure (Accessor ann (mkString fn) e)
    "ObjectUpdate" -> do
      ann <- field "annotation" o >>= annFromJson modulePath
      e <- field "expression" o >>= exprFromJson modulePath
      copyJ <- field "copy" o
      copy <-
        if isNull copyJ
          then pure Nothing
          else Just <$> (asArray copyJ >>= traverse (\jj -> mkString <$> asString jj))
      us <- field "updates" o >>= asArray >>= traverse (pairFromJson (exprFromJson modulePath))
      pure (ObjectUpdate ann e copy us)
    "Abs" -> do
      ann <- field "annotation" o >>= annFromJson modulePath
      arg <- field "argument" o >>= identFromJson
      body <- field "body" o >>= exprFromJson modulePath
      pure (Abs ann arg body)
    "App" -> do
      ann <- field "annotation" o >>= annFromJson modulePath
      f <- field "abstraction" o >>= exprFromJson modulePath
      a <- field "argument" o >>= exprFromJson modulePath
      pure (App ann f a)
    "Case" -> do
      ann <- field "annotation" o >>= annFromJson modulePath
      cs <- field "caseExpressions" o >>= asArray >>= traverse (exprFromJson modulePath)
      cas <- field "caseAlternatives" o >>= asArray >>= traverse (caseAltFromJson modulePath)
      pure (Case ann cs cas)
    "Let" -> do
      ann <- field "annotation" o >>= annFromJson modulePath
      bs <- field "binds" o >>= asArray >>= traverse (bindFromJson modulePath)
      e <- field "expression" o >>= exprFromJson modulePath
      pure (Let ann bs e)
    other -> Left ("unknown expression: " <> other)

-- ---------- bind ----------

bindFromJson :: String -> Json -> Parser (Bind Ann)
bindFromJson modulePath j = do
  o <- asObject j
  ty <- fieldStr "bindType" o
  case ty of
    "NonRec" -> do
      ann <- field "annotation" o >>= annFromJson modulePath
      id <- field "identifier" o >>= identFromJson
      e <- field "expression" o >>= exprFromJson modulePath
      pure (NonRec ann id e)
    "Rec" -> do
      bs <- field "binds" o >>= asArray >>= traverse (recEntry modulePath)
      pure (Rec bs)
    other -> Left ("unknown bind: " <> other)

recEntry :: String -> Json -> Parser { ann :: Ann, ident :: Ident, expr :: Expr Ann }
recEntry mp j = do
  o <- asObject j
  ann <- field "annotation" o >>= annFromJson mp
  id <- field "identifier" o >>= identFromJson
  e <- field "expression" o >>= exprFromJson mp
  pure { ann, ident: id, expr: e }

-- ---------- case alternative ----------

caseAltFromJson :: String -> Json -> Parser (CaseAlternative Ann)
caseAltFromJson modulePath j = do
  o <- asObject j
  bs <- field "binders" o >>= asArray >>= traverse (binderFromJson modulePath)
  isG <- field "isGuarded" o >>= asBool
  if isG
    then do
      es <- field "expressions" o >>= asArray >>= traverse (guardPairFromJson modulePath)
      pure (CaseAlternative { binders: bs, result: Left es })
    else do
      e <- field "expression" o >>= exprFromJson modulePath
      pure (CaseAlternative { binders: bs, result: Right e })

guardPairFromJson :: String -> Json -> Parser (Tuple (Expr Ann) (Expr Ann))
guardPairFromJson modulePath j = do
  o <- asObject j
  g <- field "guard" o >>= exprFromJson modulePath
  e <- field "expression" o >>= exprFromJson modulePath
  pure (Tuple g e)

-- ---------- binder ----------

binderFromJson :: String -> Json -> Parser (Binder Ann)
binderFromJson modulePath j = do
  o <- asObject j
  ty <- fieldStr "binderType" o
  case ty of
    "NullBinder" -> do
      ann <- field "annotation" o >>= annFromJson modulePath
      pure (NullBinder ann)
    "VarBinder" -> do
      ann <- field "annotation" o >>= annFromJson modulePath
      id <- field "identifier" o >>= identFromJson
      pure (VarBinder ann id)
    "LiteralBinder" -> do
      ann <- field "annotation" o >>= annFromJson modulePath
      lit <- field "literal" o >>= literalFromJson (binderFromJson modulePath)
      pure (LiteralBinder ann lit)
    "ConstructorBinder" -> do
      ann <- field "annotation" o >>= annFromJson modulePath
      tyn <- field "typeName" o >>= qualifiedFromJson ProperName
      con <- field "constructorName" o >>= qualifiedFromJson ProperName
      bs <- field "binders" o >>= asArray >>= traverse (binderFromJson modulePath)
      pure (ConstructorBinder ann tyn con bs)
    "NamedBinder" -> do
      ann <- field "annotation" o >>= annFromJson modulePath
      id <- field "identifier" o >>= identFromJson
      bb <- field "binder" o >>= binderFromJson modulePath
      pure (NamedBinder ann id bb)
    other -> Left ("unknown binder: " <> other)

