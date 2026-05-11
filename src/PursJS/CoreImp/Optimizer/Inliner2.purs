-- | Type-class-dictionary-aware inliners. After these passes run, calls
-- | like `Data_Semiring.add(semiringInt)(x)(y)` are rewritten as
-- | `(x + y) | 0`, `Data_Eq.eq(eqString)(x)(y)` as `x === y`, etc.
module PursJS.CoreImp.Optimizer.Inliner2
  ( buildExpander
  , inlineCommonValues
  , inlineCommonOperators
  , inlineFnIdentity
  , inlineUnsafeCoerce
  ) where

import Prelude

import Data.Array as Array
import Data.Either (Either(..))
import Data.Foldable (foldr)
import Data.Maybe (Maybe(..))
import Data.Tuple (Tuple(..))
import PursJS.CoreImp.AST (AST(..), BinaryOperator(..), InitializerEffects(..), UnaryOperator(..))
import PursJS.CoreImp.Optimizer.Common (applyAll, replaceIdents)
import PursJS.CoreImp.Optimizer.Constants (Ref, p_add, p_append, p_boundedBoolean, p_bottom, p_categoryFn, p_conj, p_div, p_disj, p_eq, p_eqBoolean, p_eqChar, p_eqInt, p_eqNumber, p_eqString, p_euclideanRingNumber, p_greaterThan, p_greaterThanOrEq, p_heytingAlgebraBoolean, p_identity, p_lessThan, p_lessThanOrEq, p_mul, p_negate, p_not, p_notEq, p_one, p_ordBoolean, p_ordChar, p_ordInt, p_ordNumber, p_ordString, p_ringInt, p_ringNumber, p_semigroupString, p_semiringInt, p_semiringNumber, p_sub, p_top, p_unsafeCoerce, p_zero)
import PursJS.CoreImp.Traversals (everywhere, everywhereTopDown)
import PursJS.Names (ModuleName)
import PursJS.PSString (PSString)

-- | Match a ModuleAccessor against a (ModuleName, PSString) pair.
isRef :: Ref -> AST -> Boolean
isRef (Tuple mn name) (ModuleAccessor _ mn' name') = mn == mn' && name == name'
isRef _ _ = false

-- | Build an expander that inlines top-level effect-free `var x = e;`
-- | bindings inline at use sites. This is what lets the inliner see
-- | through helper bindings like `var add = Data_Semiring.add(semiringInt);`.
buildExpander :: Array AST -> AST -> AST
buildExpander asts =
  let pairs = foldr go [] asts
  in replaceIdents pairs
  where
  go :: AST -> Array (Tuple String AST) -> Array (Tuple String AST)
  go (VariableIntroduction _ name (Just (Tuple NoEffects e))) acc = Array.cons (Tuple name e) acc
  go _ acc = acc

-- | Common values that simplify to numeric/boolean literals.
inlineCommonValues :: (AST -> AST) -> AST -> AST
inlineCommonValues expander = everywhere convert
  where
  convert ast@(App ss _ _) = case expander ast of
    App ss' fn [dict]
      | isRef p_zero fn && (isRef p_semiringInt dict || isRef p_semiringNumber dict) ->
          NumericLiteral ss' (Left 0)
      | isRef p_one fn && (isRef p_semiringInt dict || isRef p_semiringNumber dict) ->
          NumericLiteral ss' (Left 1)
      | isRef p_bottom fn && isRef p_boundedBoolean dict -> BooleanLiteral ss' false
      | isRef p_top fn && isRef p_boundedBoolean dict -> BooleanLiteral ss' true
    _ -> convertNeg ast
  convert other = other

  -- negate ringInt x
  convertNeg (App ss inner [x]) = case expander inner of
    App _ fn [dict]
      | isRef p_negate fn && isRef p_ringInt dict ->
          Binary ss BitwiseOr (Unary ss Negate x) (NumericLiteral ss (Left 0))
    _ -> convertOp (App ss inner [x])
  convertNeg other = other

  -- semiringInt add/mul; ringInt sub
  convertOp (App ss (App _ inner [x]) [y]) = case expander inner of
    App _ fn [dict]
      | isRef p_semiringInt dict && isRef p_add fn -> intOp ss Add x y
      | isRef p_semiringInt dict && isRef p_mul fn -> intOp ss Multiply x y
      | isRef p_ringInt dict && isRef p_sub fn -> intOp ss Subtract x y
    _ -> App ss (App ss inner [x]) [y]
  convertOp other = other

  intOp ss op x y =
    Binary ss BitwiseOr (Binary ss op x y) (NumericLiteral ss (Left 0))

-- | Common type-class methods that lower to JS binary/unary operators.
inlineCommonOperators :: (AST -> AST) -> AST -> AST
inlineCommonOperators expander =
  everywhereTopDown (applyAll passes)
  where
  passes :: Array (AST -> AST)
  passes =
    [ binary p_semiringNumber p_add Add
    , binary p_semiringNumber p_mul Multiply
    , binary p_ringNumber p_sub Subtract
    , unary p_ringNumber p_negate Negate
    , binary p_euclideanRingNumber p_div Divide

    , binary p_eqNumber p_eq EqualTo
    , binary p_eqNumber p_notEq NotEqualTo
    , binary p_eqInt p_eq EqualTo
    , binary p_eqInt p_notEq NotEqualTo
    , binary p_eqString p_eq EqualTo
    , binary p_eqString p_notEq NotEqualTo
    , binary p_eqChar p_eq EqualTo
    , binary p_eqChar p_notEq NotEqualTo
    , binary p_eqBoolean p_eq EqualTo
    , binary p_eqBoolean p_notEq NotEqualTo

    , binary p_ordBoolean p_lessThan LessThan
    , binary p_ordBoolean p_lessThanOrEq LessThanOrEqualTo
    , binary p_ordBoolean p_greaterThan GreaterThan
    , binary p_ordBoolean p_greaterThanOrEq GreaterThanOrEqualTo
    , binary p_ordChar p_lessThan LessThan
    , binary p_ordChar p_lessThanOrEq LessThanOrEqualTo
    , binary p_ordChar p_greaterThan GreaterThan
    , binary p_ordChar p_greaterThanOrEq GreaterThanOrEqualTo
    , binary p_ordInt p_lessThan LessThan
    , binary p_ordInt p_lessThanOrEq LessThanOrEqualTo
    , binary p_ordInt p_greaterThan GreaterThan
    , binary p_ordInt p_greaterThanOrEq GreaterThanOrEqualTo
    , binary p_ordNumber p_lessThan LessThan
    , binary p_ordNumber p_lessThanOrEq LessThanOrEqualTo
    , binary p_ordNumber p_greaterThan GreaterThan
    , binary p_ordNumber p_greaterThanOrEq GreaterThanOrEqualTo
    , binary p_ordString p_lessThan LessThan
    , binary p_ordString p_lessThanOrEq LessThanOrEqualTo
    , binary p_ordString p_greaterThan GreaterThan
    , binary p_ordString p_greaterThanOrEq GreaterThanOrEqualTo

    , binary p_semigroupString p_append Add

    , binary p_heytingAlgebraBoolean p_conj And
    , binary p_heytingAlgebraBoolean p_disj Or
    , unary p_heytingAlgebraBoolean p_not Not
    ]

  binary :: Ref -> Ref -> BinaryOperator -> AST -> AST
  binary dict fn op = convert
    where
    convert (App ss (App _ inner [x]) [y]) = case expander inner of
      App _ fn' [dict']
        | isRef fn fn' && isRef dict dict' -> Binary ss op x y
      _ -> App ss (App ss inner [x]) [y]
    convert other = other

  unary :: Ref -> Ref -> UnaryOperator -> AST -> AST
  unary dict fn op = convert
    where
    convert (App ss inner [x]) = case expander inner of
      App _ fn' [dict']
        | isRef fn fn' && isRef dict dict' -> Unary ss op x
      _ -> App ss inner [x]
    convert other = other

inlineFnIdentity :: (AST -> AST) -> AST -> AST
inlineFnIdentity expander = everywhereTopDown convert
  where
  convert (App _ inner [x]) = case expander inner of
    App _ fn [dict]
      | isRef p_identity fn && isRef p_categoryFn dict -> x
    _ -> App Nothing inner [x]
  convert other = other

inlineUnsafeCoerce :: AST -> AST
inlineUnsafeCoerce = everywhereTopDown convert
  where
  convert (App _ fn [x]) | isRef p_unsafeCoerce fn = x
  convert other = other

-- Avoid "unused" import lint warnings; these names are referenced via constants
_unused :: { mn :: ModuleName -> ModuleName, str :: PSString -> PSString }
_unused = { mn: identity, str: identity }
