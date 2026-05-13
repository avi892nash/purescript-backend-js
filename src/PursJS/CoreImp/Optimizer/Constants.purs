-- | The `(ModuleName, PSString)` pairs the inliner pattern-matches against.
-- |
-- | In the Haskell compiler these constants are TH-generated via the EDSL in
-- | `Language.PureScript.Constants.Libs` (purescript@c4a35b3,
-- | src/Language/PureScript/Constants/Libs.hs). The TH expands something like
-- | `TH.mod "Data.Semiring" (TH.vars ["add","mul","one","zero"])` into top-level
-- | `P_add :: (ModuleName, PSString)`, `P_mul :: ...`, etc.
-- |
-- | Mapping (PursJS <-> Libs.hs section):
-- |   p_add/p_mul/p_one/p_zero/p_semiringInt/p_semiringNumber
-- |                              Libs.hs:160-165 (Data.Semiring block)
-- |   p_sub/p_negate/p_ringInt/p_ringNumber
-- |                              Libs.hs (Data.Ring block; mod "Data.Ring")
-- |   p_div/p_euclideanRingNumber
-- |                              Libs.hs (Data.EuclideanRing block)
-- |   p_eq/p_notEq/p_eq*         Libs.hs (Data.Eq block)
-- |   p_lessThan/...             Libs.hs (Data.Ord block)
-- |   p_append/p_semigroupString Libs.hs:152-158 (Data.Semigroup block)
-- |   p_conj/p_disj/p_not/p_heytingAlgebraBoolean
-- |                              Libs.hs (Data.HeytingAlgebra block)
-- |   p_top/p_bottom/p_boundedBoolean
-- |                              Libs.hs (Data.Bounded block)
-- |   p_compose/p_composeFlipped/p_semigroupoidFn
-- |                              Libs.hs (Control.Semigroupoid block)
-- |   p_identity/p_categoryFn    Libs.hs (Control.Category block)
-- |   p_unsafeCoerce/p_unsafePartial
-- |                              Libs.hs (Unsafe.Coerce / Partial.Unsafe blocks)
-- |   p_bind/p_discard/p_discardUnit
-- |                              Libs.hs (Control.Bind block)
-- |   p_pure                     Libs.hs (Control.Applicative block)
-- |   p_bindEffect/p_applicativeEffect
-- |                              Libs.hs (Effect block) — for magicDoEffect
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

-- Data.Array — `unsafeIndex(dict)(arr)(i)` rewritten as `arr[i]`
-- (Inliner.hs:161 — `inlineNonClassFunction (isModFnWithDict P_unsafeIndex)`)
p_unsafeIndex :: Ref
p_unsafeIndex = mkRef "Data.Array" "unsafeIndex"

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

-- Control.Monad.ST.Internal — magicDoST target dictionaries.
p_bindST :: Ref
p_bindST = mkRef "Control.Monad.ST.Internal" "bindST"
p_applicativeST :: Ref
p_applicativeST = mkRef "Control.Monad.ST.Internal" "applicativeST"

p_m_ST_Internal :: ModuleName
p_m_ST_Internal = ModuleName "Control.Monad.ST.Internal"

-- Legacy Eff — magicDoEff target dictionaries.
p_bindEff :: Ref
p_bindEff = mkRef "Control.Monad.Eff" "bindEff"
p_applicativeEff :: Ref
p_applicativeEff = mkRef "Control.Monad.Eff" "applicativeEff"

p_m_Eff :: ModuleName
p_m_Eff = ModuleName "Control.Monad.Eff"

-- Data.Function.Uncurried / Effect.Uncurried — `mkFn0..10` / `runFn0..10` etc.
-- These are used as PREFIX strings; the inliner appends the arity (0..10) and
-- compares against the actual ModuleAccessor.
p_mkFn :: Ref
p_mkFn = mkRef "Data.Function.Uncurried" "mkFn"
p_runFn :: Ref
p_runFn = mkRef "Data.Function.Uncurried" "runFn"
p_mkEffFn :: Ref
p_mkEffFn = mkRef "Control.Monad.Eff.Uncurried" "mkEffFn"
p_runEffFn :: Ref
p_runEffFn = mkRef "Control.Monad.Eff.Uncurried" "runEffFn"
p_mkEffectFn :: Ref
p_mkEffectFn = mkRef "Effect.Uncurried" "mkEffectFn"
p_runEffectFn :: Ref
p_runEffectFn = mkRef "Effect.Uncurried" "runEffectFn"
p_mkSTFn :: Ref
p_mkSTFn = mkRef "Control.Monad.ST.Uncurried" "mkSTFn"
p_runSTFn :: Ref
p_runSTFn = mkRef "Control.Monad.ST.Uncurried" "runSTFn"
