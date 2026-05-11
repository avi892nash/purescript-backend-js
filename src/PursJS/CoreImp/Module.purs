module PursJS.CoreImp.Module where

import Data.List.NonEmpty (NonEmptyList)
import Data.Maybe (Maybe)
import PursJS.Comments (Comment)
import PursJS.CoreImp.AST (AST)
import PursJS.PSString (PSString)

type Module =
  { header :: Array Comment
  , imports :: Array Import
  , body :: Array AST
  , exports :: Array Export
  }

-- | An ES module import: `import * as <name> from <from>;`
data Import = Import String PSString

-- | An ES module export: `export { ... } [from <from>];`
data Export = Export (NonEmptyList String) (Maybe PSString)
