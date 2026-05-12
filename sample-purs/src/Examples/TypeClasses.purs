-- | Type classes & instances — exercises:
-- |   - Constructor codegen for the class dictionary (an ObjectLiteral with
-- |     one entry per class method)
-- |   - Var with IsConstructor (JS.hs:290-293) — `.value` or `.create`
-- |   - The `IsTypeClassConstructor` meta short-cut (JS.hs:242-245) which
-- |     elides the class-constructor wrapper because it's only ever applied
module Examples.TypeClasses where

import Prelude

-- A simple class with one method.
class Describable a where
  describe :: a -> String

-- Instance — compiles to `var describableInt = { describe: ... };`.
instance describableInt :: Describable Int where
  describe n = "an int: " <> show n

instance describableBoolean :: Describable Boolean where
  describe true = "yes"
  describe false = "no"

-- Use of a class method — generates `describe(describableInt)(42)` after
-- typechecking elaboration.
descIntList :: Array String
descIntList = [ describe 1, describe 2, describe 3 ]

-- Class with a superclass constraint — the dict for the subclass references
-- the dict for the superclass.
class Describable a <= Verbose a where
  verbose :: a -> String

instance verboseInt :: Verbose Int where
  verbose n = describe n <> " (verbose)"

-- A polymorphic function with a constraint. After elaboration this becomes
-- `var d = function (dictDescribable) { return function (x) { return describe(dictDescribable)(x); } }`.
useDescribe :: forall a. Describable a => a -> String
useDescribe x = describe x
