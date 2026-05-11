module PursJS.Names where

import Prelude

import Data.Maybe (Maybe(..))

data Ident
  = Ident String
  | GenIdent (Maybe String) Int
  | UnusedIdent
  | InternalIdent InternalIdentData

derive instance Eq Ident
derive instance Ord Ident

data InternalIdentData
  = RuntimeLazyFactory
  | Lazy String

derive instance Eq InternalIdentData
derive instance Ord InternalIdentData

unusedIdent :: String
unusedIdent = "$__unused"

runIdent :: Ident -> String
runIdent (Ident i) = i
runIdent (GenIdent Nothing n) = "$" <> show n
runIdent (GenIdent (Just name) n) = "$" <> name <> show n
runIdent UnusedIdent = unusedIdent
runIdent (InternalIdent _) = "<<internal ident>>"

newtype ProperName = ProperName String

derive instance Eq ProperName
derive instance Ord ProperName

runProperName :: ProperName -> String
runProperName (ProperName n) = n

newtype ModuleName = ModuleName String

derive instance Eq ModuleName
derive instance Ord ModuleName

runModuleName :: ModuleName -> String
runModuleName (ModuleName n) = n

-- | Source position: line, column (1-based)
data SourcePos = SourcePos Int Int

derive instance Eq SourcePos
derive instance Ord SourcePos

data QualifiedBy
  = BySourcePos SourcePos
  | ByModuleName ModuleName

derive instance Eq QualifiedBy
derive instance Ord QualifiedBy

data Qualified a = Qualified QualifiedBy a

derive instance Eq a => Eq (Qualified a)
derive instance Ord a => Ord (Qualified a)

disqualify :: forall a. Qualified a -> a
disqualify (Qualified _ a) = a

getQual :: forall a. Qualified a -> Maybe ModuleName
getQual (Qualified (ByModuleName mn) _) = Just mn
getQual _ = Nothing

showQualified :: forall a. (a -> String) -> Qualified a -> String
showQualified f (Qualified (BySourcePos _) a) = f a
showQualified f (Qualified (ByModuleName mn) a) = runModuleName mn <> "." <> f a

-- | A source span (file, start, end)
data SourceSpan = SourceSpan
  { name :: String
  , start :: SourcePos
  , end :: SourcePos
  }

derive instance Eq SourceSpan
derive instance Ord SourceSpan
