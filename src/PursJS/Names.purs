-- | Ports types from `Language.PureScript.Names` (purescript@c4a35b3,
-- | src/Language/PureScript/Names.hs) and the `SourcePos`/`SourceSpan` part of
-- | `Language.PureScript.AST.SourcePos` (src/Language/PureScript/AST/SourcePos.hs).
-- |
-- | Mapping (PursJS <-> Names.hs line):
-- |   Ident                   Names.hs:81-98
-- |   InternalIdentData       Names.hs:70-73
-- |   unusedIdent             Names.hs:103-104
-- |   runIdent                Names.hs:106-111
-- |   ProperName              Names.hs:158-159 (kind param `a` erased: we only use it as a tag for runProperName)
-- |   ModuleName              Names.hs:190-191
-- |   QualifiedBy             Names.hs:205-208
-- |   Qualified               Names.hs:231-232
-- |   showQualified           Names.hs:237-239
-- |   getQual                 Names.hs:241-242
-- |   disqualify              Names.hs:257-259
-- |   SourcePos               SourcePos.hs (data SourcePos)
-- |   SourceSpan              SourcePos.hs (data SourceSpan)
module PursJS.Names where

import Prelude

import Data.Maybe (Maybe(..))

-- | Names.hs:81-98 — `data Ident`.
-- | The Haskell type has the same four variants. We don't carry NFData / Serialise
-- | instances because we don't externs-serialize from PureScript.
data Ident
  = Ident String
  | GenIdent (Maybe String) Int
  | UnusedIdent
  | InternalIdent InternalIdentData

derive instance Eq Ident
derive instance Ord Ident

-- | Names.hs:70-73 — `data InternalIdentData`. Used by CoreFn.Laziness.
data InternalIdentData
  = RuntimeLazyFactory
  | Lazy String

derive instance Eq InternalIdentData
derive instance Ord InternalIdentData

-- | Names.hs:103-104 — `unusedIdent = "$__unused"`.
unusedIdent :: String
unusedIdent = "$__unused"

-- | Names.hs:106-111 — `runIdent`.
runIdent :: Ident -> String
runIdent (Ident i) = i
runIdent (GenIdent Nothing n) = "$" <> show n
runIdent (GenIdent (Just name) n) = "$" <> name <> show n
runIdent UnusedIdent = unusedIdent
runIdent (InternalIdent _) = "<<internal ident>>"

-- | Names.hs:158-159 — `newtype ProperName (a :: ProperNameType)`.
-- | The kind parameter `a` (TypeName/ConstructorName/ClassName/Namespace) is
-- | erased here — PureScript can't express the phantom kind directly, but the
-- | functions consuming `ProperName` don't distinguish them in codegen anyway.
newtype ProperName = ProperName String

derive instance Eq ProperName
derive instance Ord ProperName

runProperName :: ProperName -> String
runProperName (ProperName n) = n

-- | Names.hs:190-191 — `newtype ModuleName = ModuleName Text`.
newtype ModuleName = ModuleName String

derive instance Eq ModuleName
derive instance Ord ModuleName

runModuleName :: ModuleName -> String
runModuleName (ModuleName n) = n

-- | SourcePos.hs — `data SourcePos`. Line and column, both 1-based.
data SourcePos = SourcePos Int Int

derive instance Eq SourcePos
derive instance Ord SourcePos

-- | Names.hs:205-208 — `data QualifiedBy`.
data QualifiedBy
  = BySourcePos SourcePos
  | ByModuleName ModuleName

derive instance Eq QualifiedBy
derive instance Ord QualifiedBy

-- | Names.hs:231-232 — `data Qualified a = Qualified QualifiedBy a`.
data Qualified a = Qualified QualifiedBy a

derive instance Eq a => Eq (Qualified a)
derive instance Ord a => Ord (Qualified a)

-- | Names.hs:257-259 — `disqualify (Qualified _ a) = a`.
disqualify :: forall a. Qualified a -> a
disqualify (Qualified _ a) = a

-- | Names.hs:241-242 — `getQual = toMaybeModuleName . (\(Qualified qb _) -> qb)`.
getQual :: forall a. Qualified a -> Maybe ModuleName
getQual (Qualified (ByModuleName mn) _) = Just mn
getQual _ = Nothing

-- | Names.hs:237-239 — `showQualified f (Qualified by a)`.
showQualified :: forall a. (a -> String) -> Qualified a -> String
showQualified f (Qualified (BySourcePos _) a) = f a
showQualified f (Qualified (ByModuleName mn) a) = runModuleName mn <> "." <> f a

-- | SourcePos.hs — `data SourceSpan = SourceSpan { spanName, spanStart, spanEnd }`.
data SourceSpan = SourceSpan
  { name :: String
  , start :: SourcePos
  , end :: SourcePos
  }

derive instance Eq SourceSpan
derive instance Ord SourceSpan
