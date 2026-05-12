-- | Ports `Language.PureScript.CodeGen.JS.Printer` (purescript@c4a35b3,
-- | src/Language/PureScript/CodeGen/JS/Printer.hs).
-- |
-- | The Haskell version uses the `pattern-arrows` library to express the
-- | operator-precedence table declaratively (see `operators` in Printer.hs:276-310).
-- | Here we implement the equivalent recursive printer with explicit precedence
-- | levels (`pLowest`..`pAtom`) and `wrapParens` checks. The numeric levels are
-- | chosen so the *order* of the levels in pattern-arrows' `OperatorTable` is
-- | preserved (lowest precedence first).
-- |
-- | Mapping (PursJS <-> Printer.hs line):
-- |   prettyPrintModule / prettyModule  Printer.hs:252-258
-- |   prettyPrintJS                     Printer.hs:266-267
-- |   renderStatements / prettyStatements
-- |                                     Printer.hs:246-250
-- |   renderImport / prettyImport       Printer.hs:158-161
-- |   renderExport / prettyExport       Printer.hs:163-182
-- |   renderComment / comment           Printer.hs:130-156
-- |   render (Block/Function/...)       Printer.hs:31-128 (`match` / `match'`)
-- |   accessor pattern                  Printer.hs:184-191
-- |   indexer pattern                   Printer.hs:193-197
-- |   precedence table                  Printer.hs:276-310 (`operators`)
-- |
-- | The operator precedence levels in pattern-arrows are layered as
-- |   1. indexer        2. accessor      3. app            4. new
-- |   5. lambda         6. unary (!,~,+,-)   7. * / %
-- |   8. + -            9. << >> >>>     10. < <= > >= instanceof
-- |   11. === !==       12. &            13. ^
-- |   14. |             15. &&           16. ||
-- | (atoms above 1, lowest below 16). We invert: higher number = tighter bind.
module PursJS.CodeGen.Printer
  ( prettyPrintJS
  , prettyPrintModule
  ) where

import Prelude

import Data.Array as Array
import Data.Either (Either(..))
import Data.Foldable (foldMap)
import Data.List.NonEmpty as NEL
import Data.Maybe (Maybe(..), fromMaybe, maybe)
import Data.Number.Format as Num
import Data.String as Str
import Data.String.CodeUnits as SC
import Data.Tuple (Tuple(..))
import PursJS.CodeGen.Common (anyNameToJs, identCharToText, isValidJsIdentifier, nameIsJsBuiltIn, nameIsJsReserved)
import PursJS.Comments (Comment(..))
import PursJS.CoreImp.AST (AST(..), BinaryOperator(..), CIComments(..), UnaryOperator(..))
import PursJS.CoreImp.Module (Export(..), Import(..), Module)
import PursJS.PSString (PSString, decodeString, prettyPrintStringJS)

-- | Precedence: higher means binds tighter. Mirrors the Haskell pattern-arrows
-- | operator table from `Language.PureScript.CodeGen.JS.Printer`.
type Prec = Int

-- Precedence levels, from tightest to loosest. The Haskell table is layered:
--   [indexer], [accessor], [app], [new], [lambda],
--   [unary !, ~, +, -], [* / %], [+ -], [<< >> >>>],
--   [< <= > >= instanceof], [=== !==], [&], [^], [|], [&&], [||]
-- The "Wrap" operators are unary postfixes (effectively, given pattern-arrows).
pLowest :: Prec
pLowest = 0

pOr :: Prec
pOr = 1

pAnd :: Prec
pAnd = 2

pBitOr :: Prec
pBitOr = 3

pBitXor :: Prec
pBitXor = 4

pBitAnd :: Prec
pBitAnd = 5

pEq :: Prec
pEq = 6

pComp :: Prec
pComp = 7

pShift :: Prec
pShift = 8

pAddSub :: Prec
pAddSub = 9

pMulDiv :: Prec
pMulDiv = 10

pUnary :: Prec
pUnary = 11

pLam :: Prec
pLam = 12

pNew :: Prec
pNew = 13

pApp :: Prec
pApp = 14

pAccessor :: Prec
pAccessor = 15

pIndexer :: Prec
pIndexer = 16

pAtom :: Prec
pAtom = 17

-- Indent state, tracking current depth in spaces (4 per level).
type Indent = Int

indentStep :: Int
indentStep = 4

indentStr :: Indent -> String
indentStr n = Str.joinWith "" (Array.replicate n " ")

inc :: Indent -> Indent
inc n = n + indentStep

-- | Top-level entry: render a Module to JS text. No trailing newline.
prettyPrintModule :: Module -> String
prettyPrintModule m =
  let headerStr = foldMap (renderComment 0) m.header
      importsStrs = map (renderImport 0) m.imports
      bodyStr = renderStatements 0 m.body
      exportsStrs = map (renderExport 0) m.exports
      pieces = importsStrs <> [bodyStr] <> exportsStrs
      glued = Str.joinWith "\n" pieces
  in headerStr <> glued

prettyPrintJS :: Module -> String
prettyPrintJS = prettyPrintModule

renderImport :: Indent -> Import -> String
renderImport _ (Import ident from) =
  "import * as " <> ident <> " from " <> prettyPrintStringJS from <> ";"

renderExport :: Indent -> Export -> String
renderExport ind (Export idents mFrom) =
  let lines = map (toLine mFrom) (NEL.toUnfoldable idents :: Array String)
      innerInd = indentStr (inc ind)
      indented = map (\s -> innerInd <> s) lines
      body = Str.joinWith ",\n" indented
      fromPart = case mFrom of
        Nothing -> ""
        Just f -> " from " <> prettyPrintStringJS f
  in "export {\n" <> body <> "\n" <> indentStr ind <> "}" <> fromPart <> ";"
  where
  toLine :: Maybe PSString -> String -> String
  toLine Nothing ident
    | nameIsJsReserved ident || nameIsJsBuiltIn ident =
        "$$" <> ident <> " as " <> ident
  toLine _ "$main" = escapeIdent "$main" <> " as $main"
  toLine _ ident = escapeIdent ident

  escapeIdent :: String -> String
  escapeIdent s = foldMap identCharToText (SC.toCharArray s)

-- ===== comments =====

renderComment :: Indent -> Comment -> String
renderComment ind (LineComment t) = indentStr ind <> "//" <> t <> "\n"
renderComment ind (BlockComment t) =
  let lines = Str.split (Str.Pattern "\n") t
      body = foldMap (\l -> indentStr ind <> " * " <> removeComments l <> "\n") lines
  in indentStr ind <> "/**\n" <> body <> indentStr ind <> " */\n" <> indentStr ind

removeComments :: String -> String
removeComments s =
  case Str.stripPrefix (Str.Pattern "*/") s of
    Just rest -> removeComments rest
    Nothing -> case Str.uncons s of
      Just { head, tail } -> Str.singleton head <> removeComments tail
      Nothing -> ""

-- ===== statements =====

-- | Render a sequence of statements at the given indent level.
-- | Each line is prefixed with `indentStr ind`. The caller is responsible
-- | for bumping the indent for nested blocks via `inc`.
renderStatements :: Indent -> Array AST -> String
renderStatements ind sts =
  let indStr = indentStr ind
      lines = map (\s -> indStr <> renderExpr pLowest ind s <> ";") sts
  in Str.joinWith "\n" lines

-- ===== expressions =====

renderExpr :: Prec -> Indent -> AST -> String
renderExpr ctx ind ast = wrapParens ctx (precOf ast) (render ind ast)

wrapParens :: Prec -> Prec -> String -> String
wrapParens ctx p s = if ctx > p then "(" <> s <> ")" else s

precOf :: AST -> Prec
precOf = case _ of
  NumericLiteral _ _ -> pAtom
  StringLiteral _ _ -> pAtom
  BooleanLiteral _ _ -> pAtom
  ArrayLiteral _ _ -> pAtom
  ObjectLiteral _ _ -> pAtom
  Block _ _ -> pAtom
  Var _ _ -> pAtom
  ModuleAccessor _ _ _ -> pAtom
  VariableIntroduction _ _ _ -> pAtom
  Assignment _ _ _ -> pAtom
  While _ _ _ -> pAtom
  For _ _ _ _ _ -> pAtom
  ForIn _ _ _ _ -> pAtom
  IfElse _ _ _ _ -> pAtom
  Return _ _ -> pAtom
  ReturnNoResult _ -> pAtom
  Throw _ _ -> pAtom
  Comment _ _ -> pAtom
  Indexer _ s _ -> case s of
    -- An Indexer with a string literal property that's a valid JS ident is
    -- rendered as `.prop` (accessor precedence). Otherwise `[s]` (indexer).
    StringLiteral _ ps -> case decodeString ps of
      Just str | isValidJsIdentifier str -> pAccessor
      _ -> pIndexer
    _ -> pIndexer
  App _ _ _ -> pApp
  Unary _ New _ -> pNew
  Function _ _ _ _ -> pLam
  Unary _ Not _ -> pUnary
  Unary _ BitwiseNot _ -> pUnary
  Unary _ Positive _ -> pUnary
  Unary _ Negate _ -> pUnary
  Binary _ Multiply _ _ -> pMulDiv
  Binary _ Divide _ _ -> pMulDiv
  Binary _ Modulus _ _ -> pMulDiv
  Binary _ Add _ _ -> pAddSub
  Binary _ Subtract _ _ -> pAddSub
  Binary _ ShiftLeft _ _ -> pShift
  Binary _ ShiftRight _ _ -> pShift
  Binary _ ZeroFillShiftRight _ _ -> pShift
  Binary _ LessThan _ _ -> pComp
  Binary _ LessThanOrEqualTo _ _ -> pComp
  Binary _ GreaterThan _ _ -> pComp
  Binary _ GreaterThanOrEqualTo _ _ -> pComp
  InstanceOf _ _ _ -> pComp
  Binary _ EqualTo _ _ -> pEq
  Binary _ NotEqualTo _ _ -> pEq
  Binary _ BitwiseAnd _ _ -> pBitAnd
  Binary _ BitwiseXor _ _ -> pBitXor
  Binary _ BitwiseOr _ _ -> pBitOr
  Binary _ And _ _ -> pAnd
  Binary _ Or _ _ -> pOr

render :: Indent -> AST -> String
render _ (NumericLiteral _ (Left i)) = show i
render _ (NumericLiteral _ (Right n)) = showNumber n
render _ (StringLiteral _ s) = prettyPrintStringJS s
render _ (BooleanLiteral _ true) = "true"
render _ (BooleanLiteral _ false) = "false"
render _ (Var _ ident) = ident
render ind (ArrayLiteral _ xs) =
  "[ " <> Str.joinWith ", " (map (renderExpr pLowest ind) xs) <> " ]"
render _ (ObjectLiteral _ []) = "{}"
render ind (ObjectLiteral _ ps) =
  let innerInd = indentStr (inc ind)
      lines = map (\(Tuple key val) ->
                    innerInd <> objectPropertyKey key <> ": " <> renderExpr pLowest (inc ind) val)
                  ps
  in "{\n" <> Str.joinWith ",\n" lines <> "\n" <> indentStr ind <> "}"
render ind (Block _ sts) =
  "{\n" <> renderStatements (inc ind) sts <> "\n" <> indentStr ind <> "}"
render ind (VariableIntroduction _ ident mInit) =
  case mInit of
    Nothing -> "var " <> ident
    Just (Tuple _ j) -> "var " <> ident <> " = " <> renderExpr pLowest ind j
render ind (Assignment _ target val) =
  renderExpr pLowest ind target <> " = " <> renderExpr pLowest ind val
render ind (While _ cond body) =
  "while (" <> renderExpr pLowest ind cond <> ") " <> renderExpr pLowest ind body
render ind (For _ ident start end body) =
  "for (var " <> ident <> " = " <> renderExpr pLowest ind start
  <> "; " <> ident <> " < " <> renderExpr pLowest ind end
  <> "; " <> ident <> "++) " <> renderExpr pLowest ind body
render ind (ForIn _ ident obj body) =
  "for (var " <> ident <> " in " <> renderExpr pLowest ind obj <> ") " <> renderExpr pLowest ind body
render ind (IfElse _ cond thens elses) =
  let elseStr = case elses of
        Nothing -> ""
        Just e -> " else " <> renderExpr pLowest ind e
  in "if (" <> renderExpr pLowest ind cond <> ") " <> renderExpr pLowest ind thens <> elseStr
render ind (Return _ val) =
  "return " <> renderExpr pLowest ind val
render _ (ReturnNoResult _) = "return"
render ind (Throw _ val) =
  "throw " <> renderExpr pLowest ind val
render ind (Indexer _ (StringLiteral _ ps) obj) =
  case decodeString ps of
    Just str | isValidJsIdentifier str ->
      renderExpr pAccessor ind obj <> "." <> str
    _ -> renderExpr pIndexer ind obj <> "[" <> prettyPrintStringJS ps <> "]"
render ind (Indexer _ idx obj) =
  renderExpr pIndexer ind obj <> "[" <> renderExpr pLowest ind idx <> "]"
render ind (App _ fn args) =
  renderExpr pApp ind fn <> "(" <> Str.joinWith ", " (map (renderExpr pLowest ind) args) <> ")"
render ind (Unary _ New e) =
  "new " <> renderExpr pNew ind e
render ind (Function _ name args body) =
  let nm = fromMaybe "" name
      argsStr = Str.joinWith ", " args
  in "function " <> nm <> "(" <> argsStr <> ") " <> renderExpr pLowest ind body
render ind (Unary _ Not e) = "!" <> renderExpr pUnary ind e
render ind (Unary _ BitwiseNot e) = "~" <> renderExpr pUnary ind e
render ind (Unary _ Positive e) = "+" <> renderExpr pUnary ind e
render ind (Unary _ Negate e) =
  let prefix = case e of
        Unary _ Negate _ -> "- "
        _ -> "-"
  in prefix <> renderExpr pUnary ind e
render ind (Binary _ Multiply a b) = renderBinaryL ind pMulDiv "*" a b
render ind (Binary _ Divide a b) = renderBinaryL ind pMulDiv "/" a b
render ind (Binary _ Modulus a b) = renderBinaryL ind pMulDiv "%" a b
render ind (Binary _ Add a b) = renderBinaryL ind pAddSub "+" a b
render ind (Binary _ Subtract a b) = renderBinaryL ind pAddSub "-" a b
render ind (Binary _ ShiftLeft a b) = renderBinaryL ind pShift "<<" a b
render ind (Binary _ ShiftRight a b) = renderBinaryL ind pShift ">>" a b
render ind (Binary _ ZeroFillShiftRight a b) = renderBinaryL ind pShift ">>>" a b
render ind (Binary _ LessThan a b) = renderBinaryL ind pComp "<" a b
render ind (Binary _ LessThanOrEqualTo a b) = renderBinaryL ind pComp "<=" a b
render ind (Binary _ GreaterThan a b) = renderBinaryL ind pComp ">" a b
render ind (Binary _ GreaterThanOrEqualTo a b) = renderBinaryL ind pComp ">=" a b
render ind (Binary _ EqualTo a b) = renderBinaryL ind pEq "===" a b
render ind (Binary _ NotEqualTo a b) = renderBinaryL ind pEq "!==" a b
render ind (Binary _ BitwiseAnd a b) = renderBinaryL ind pBitAnd "&" a b
render ind (Binary _ BitwiseXor a b) = renderBinaryL ind pBitXor "^" a b
render ind (Binary _ BitwiseOr a b) = renderBinaryL ind pBitOr "|" a b
render ind (Binary _ And a b) = renderBinaryL ind pAnd "&&" a b
render ind (Binary _ Or a b) = renderBinaryL ind pOr "||" a b
render ind (InstanceOf _ a b) =
  -- AssocR in Haskell. Lhs at higher prec, rhs at same or higher.
  renderExpr (pComp + 1) ind a <> " instanceof " <> renderExpr pComp ind b
render ind (ModuleAccessor _ _ name) =
  -- Should normally be eliminated by replaceModuleAccessors; fallback:
  case decodeString name of
    Just s -> s
    Nothing -> "<<module accessor>>"
render ind (Comment (SourceComments coms) j) =
  "\n" <> foldMap (renderComment ind) coms <> renderExpr pLowest ind j
render ind (Comment PureAnnotation j) =
  "/* #__PURE__ */ " <> renderExpr pLowest ind j

-- AssocL binary operator rendering: left-arg at same prec, right-arg at prec+1.
renderBinaryL :: Indent -> Prec -> String -> AST -> AST -> String
renderBinaryL ind p op a b =
  renderExpr p ind a <> " " <> op <> " " <> renderExpr (p + 1) ind b

-- | Show a Number matching Haskell's `Show Double` instance, which the
-- | Haskell printer uses (Printer.hs:38 — `T.pack $ either show show n`).
-- |
-- | Haskell's `show :: Double -> String` uses `Numeric.showFloat` with the
-- | "generic" format:
-- |
-- |   if 0.1 <= |n| < 1e7   → fixed format with at least one digit after `.`
-- |   otherwise              → exponential `mantissa<e|E>exp`
-- |
-- | JS's `Number.prototype.toString()` follows a different threshold
-- | (1e-7..1e21), so we replicate the Haskell rule explicitly here.
showNumber :: Number -> String
showNumber n =
  let absN = if n < 0.0 then -n else n
  in
    if n /= n then "NaN"
    else if n == 0.0 then "0.0"
    else if absN >= 0.1 && absN < 1.0e7 then ensureDecimal (Num.toString n)
    else formatExponential n

ensureDecimal :: String -> String
ensureDecimal s =
  if Str.contains (Str.Pattern ".") s || Str.contains (Str.Pattern "e") s
    then s
    else s <> ".0"

-- | Format `n` as `<mantissa>e<exp>`, where mantissa has at least one digit
-- | after the decimal point and exp has no leading `+` (matches Haskell's
-- | `showEFloat`).
foreign import _toExponential :: Number -> String

formatExponential :: Number -> String
formatExponential n =
  let raw = _toExponential n          -- e.g. "1e+10" or "1.5e-7"
      -- Split mantissa and exponent
      parts = Str.split (Str.Pattern "e") raw
  in case parts of
       [mant, exp_] ->
         let mant' = if Str.contains (Str.Pattern ".") mant then mant else mant <> ".0"
             exp' = case Str.stripPrefix (Str.Pattern "+") exp_ of
               Just rest -> rest
               Nothing -> exp_
         in mant' <> "e" <> exp'
       _ -> raw  -- shouldn't happen

-- ===== object property keys =====

objectPropertyKey :: PSString -> String
objectPropertyKey s = case decodeString s of
  Just str | isValidJsIdentifier str -> str
  _ -> prettyPrintStringJS s
