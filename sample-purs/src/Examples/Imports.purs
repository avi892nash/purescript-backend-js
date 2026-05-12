-- | Imports — exercises:
-- |   - renameImports (JS.hs:140-157): if a module name collides with a
-- |     declared local name, the import is renamed to e.g. `Foo_Bar_1`
-- |   - importToJs (JS.hs:161-164): emits `import * as Foo_Bar from "../Foo.Bar/index.js"`
-- |   - replaceModuleAccessors (JS.hs:182-187): rewrites `ModuleAccessor`
-- |     nodes into `<alias>.<name>` references
-- |   - The "only imports actually used" filtering at JS.hs:71-74 — imports
-- |     whose references all get inlined away vanish entirely
module Examples.Imports where

import Prelude

import Examples.ADTs (Color(..), Tree(..))
import Examples.Arith (intAdd)

-- Cross-module reference. After codegen this is
-- `Examples_ADTs.Red.value` (nullary constructor → `.value` field).
defaultColor :: Color
defaultColor = Red

-- Cross-module function call. Compiles to `Examples_Arith.intAdd(2)(3)`
-- but then inlineCommonValues replaces the intAdd reference if it can see
-- through; otherwise we keep the cross-module call.
two :: Int
two = intAdd 1 1

-- Reference to a constructor of another module — `Examples_ADTs.Branch.create`.
emptyTree :: forall a. Tree a
emptyTree = Leaf
