-- | The (ModuleName, PSString) pairs the inliner pattern-matches against.
-- | Mirrors the TH-generated `P_*` constants in
-- | `Language.PureScript.Constants.Libs`.
module PursJS.CoreImp.Optimizer.Constants where

import Data.Tuple (Tuple(..))
import PursJS.Names (ModuleName(..))
import PursJS.PSString (PSString, mkString)

type Ref = Tuple ModuleName PSString

mkRef :: String -> String -> Ref
mkRef m n = Tuple (ModuleName m) (mkString n)

-- Data.Semiring
p_add :: Ref
p_add = mkRef "Data.Semiring" "add"
p_mul :: Ref
p_mul = mkRef "Data.Semiring" "mul"
p_zero :: Ref
p_zero = mkRef "Data.Semiring" "zero"
p_one :: Ref
p_one = mkRef "Data.Semiring" "one"
p_semiringInt :: Ref
p_semiringInt = mkRef "Data.Semiring" "semiringInt"
p_semiringNumber :: Ref
p_semiringNumber = mkRef "Data.Semiring" "semiringNumber"

-- Data.Ring
p_sub :: Ref
p_sub = mkRef "Data.Ring" "sub"
p_negate :: Ref
p_negate = mkRef "Data.Ring" "negate"
p_ringInt :: Ref
p_ringInt = mkRef "Data.Ring" "ringInt"
p_ringNumber :: Ref
p_ringNumber = mkRef "Data.Ring" "ringNumber"

-- Data.EuclideanRing
p_div :: Ref
p_div = mkRef "Data.EuclideanRing" "div"
p_euclideanRingNumber :: Ref
p_euclideanRingNumber = mkRef "Data.EuclideanRing" "euclideanRingNumber"

-- Data.Eq
p_eq :: Ref
p_eq = mkRef "Data.Eq" "eq"
p_notEq :: Ref
p_notEq = mkRef "Data.Eq" "notEq"
p_eqInt :: Ref
p_eqInt = mkRef "Data.Eq" "eqInt"
p_eqNumber :: Ref
p_eqNumber = mkRef "Data.Eq" "eqNumber"
p_eqString :: Ref
p_eqString = mkRef "Data.Eq" "eqString"
p_eqChar :: Ref
p_eqChar = mkRef "Data.Eq" "eqChar"
p_eqBoolean :: Ref
p_eqBoolean = mkRef "Data.Eq" "eqBoolean"

-- Data.Ord
p_lessThan :: Ref
p_lessThan = mkRef "Data.Ord" "lessThan"
p_lessThanOrEq :: Ref
p_lessThanOrEq = mkRef "Data.Ord" "lessThanOrEq"
p_greaterThan :: Ref
p_greaterThan = mkRef "Data.Ord" "greaterThan"
p_greaterThanOrEq :: Ref
p_greaterThanOrEq = mkRef "Data.Ord" "greaterThanOrEq"
p_ordInt :: Ref
p_ordInt = mkRef "Data.Ord" "ordInt"
p_ordNumber :: Ref
p_ordNumber = mkRef "Data.Ord" "ordNumber"
p_ordString :: Ref
p_ordString = mkRef "Data.Ord" "ordString"
p_ordChar :: Ref
p_ordChar = mkRef "Data.Ord" "ordChar"
p_ordBoolean :: Ref
p_ordBoolean = mkRef "Data.Ord" "ordBoolean"

-- Data.Semigroup
p_append :: Ref
p_append = mkRef "Data.Semigroup" "append"
p_semigroupString :: Ref
p_semigroupString = mkRef "Data.Semigroup" "semigroupString"

-- Data.HeytingAlgebra
p_conj :: Ref
p_conj = mkRef "Data.HeytingAlgebra" "conj"
p_disj :: Ref
p_disj = mkRef "Data.HeytingAlgebra" "disj"
p_not :: Ref
p_not = mkRef "Data.HeytingAlgebra" "not"
p_heytingAlgebraBoolean :: Ref
p_heytingAlgebraBoolean = mkRef "Data.HeytingAlgebra" "heytingAlgebraBoolean"

-- Data.Bounded
p_top :: Ref
p_top = mkRef "Data.Bounded" "top"
p_bottom :: Ref
p_bottom = mkRef "Data.Bounded" "bottom"
p_boundedBoolean :: Ref
p_boundedBoolean = mkRef "Data.Bounded" "boundedBoolean"

-- Control.Semigroupoid / Control.Category
p_compose :: Ref
p_compose = mkRef "Control.Semigroupoid" "compose"
p_composeFlipped :: Ref
p_composeFlipped = mkRef "Control.Semigroupoid" "composeFlipped"
p_semigroupoidFn :: Ref
p_semigroupoidFn = mkRef "Control.Semigroupoid" "semigroupoidFn"
p_identity :: Ref
p_identity = mkRef "Control.Category" "identity"
p_categoryFn :: Ref
p_categoryFn = mkRef "Control.Category" "categoryFn"

-- Unsafe.Coerce / Partial.Unsafe
p_unsafeCoerce :: Ref
p_unsafeCoerce = mkRef "Unsafe.Coerce" "unsafeCoerce"
p_unsafePartial :: Ref
p_unsafePartial = mkRef "Partial.Unsafe" "unsafePartial"

-- Control.Bind / Control.Applicative — used by magicDo
p_bind :: Ref
p_bind = mkRef "Control.Bind" "bind"
p_discard :: Ref
p_discard = mkRef "Control.Bind" "discard"
p_discardUnit :: Ref
p_discardUnit = mkRef "Control.Bind" "discardUnit"
p_pure :: Ref
p_pure = mkRef "Control.Applicative" "pure"

-- Effect — magicDoEffect target dictionaries
p_bindEffect :: Ref
p_bindEffect = mkRef "Effect" "bindEffect"
p_applicativeEffect :: Ref
p_applicativeEffect = mkRef "Effect" "applicativeEffect"

p_m_Effect :: ModuleName
p_m_Effect = ModuleName "Effect"
