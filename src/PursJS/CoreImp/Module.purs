-- | Ports `Language.PureScript.CoreImp.Module` (purescript@c4a35b3,
-- | src/Language/PureScript/CoreImp/Module.hs).
-- |
-- | The wrapper that adds ES-module imports, exports, and header comments
-- | around the body ASTs.
-- |
-- | Mapping (PursJS <-> CoreImp/Module.hs line):
-- |   Module (record)           Module.hs:10-15   (Haskell: data Module = Module { modHeader, modImports, modBody, modExports })
-- |   Import                    Module.hs:17      (`data Import = Import Text PSString`)
-- |   Export                    Module.hs:19      (`data Export = Export (NonEmpty Text) (Maybe PSString)`)
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
