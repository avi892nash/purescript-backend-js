-- | Name mangling, JS reserved words, JS built-ins. Mirrors
-- | Language.PureScript.CodeGen.JS.Common in the Haskell compiler.
module PursJS.CodeGen.Common where

import Prelude

import Data.Array as Array
import Data.Char (toCharCode)
import Data.Foldable (foldMap)
import Data.Maybe (Maybe(..))
import Data.String as Str
import Data.String.CodeUnits as SC
import PursJS.Names (Ident(..), InternalIdentData(..), ModuleName(..), ProperName, runProperName, unusedIdent)

-- | Convert a module name (`Foo.Bar.Baz`) into its JS identifier (`Foo_Bar_Baz`).
-- | Prefix with `$$` if the result is a JS built-in.
moduleNameToJs :: ModuleName -> String
moduleNameToJs (ModuleName mn) =
  let name = Str.replaceAll (Str.Pattern ".") (Str.Replacement "_") mn
  in if nameIsJsBuiltIn name then "$$" <> name else name

identToJs :: Ident -> String
identToJs (Ident name)
  | not (Str.null name) && headIsDigit name = "$$" <> escapeIdent name
  | otherwise = anyNameToJs name
identToJs (GenIdent _ _) = "<<internal error: GenIdent in identToJs>>"
identToJs UnusedIdent = unusedIdent
identToJs (InternalIdent RuntimeLazyFactory) = "$runtime_lazy"
identToJs (InternalIdent (Lazy name)) = "$lazy_" <> anyNameToJs name

properToJs :: ProperName -> String
properToJs = anyNameToJs <<< runProperName

-- | Convert any name to a valid JS identifier. Assumes input is a valid
-- | PureScript identifier already.
anyNameToJs :: String -> String
anyNameToJs name
  | nameIsJsReserved name || nameIsJsBuiltIn name = "$$" <> name
  | otherwise = escapeIdent name

escapeIdent :: String -> String
escapeIdent = foldMap identCharToText <<< SC.toCharArray

-- | True if the string is a valid JS identifier as-is. Conservative: a false
-- | return doesn't mean it's invalid.
isValidJsIdentifier :: String -> Boolean
isValidJsIdentifier s =
  not (Str.null s) &&
  isAlpha (firstChar s) &&
  s == anyNameToJs s

firstChar :: String -> Char
firstChar s = case SC.charAt 0 s of
  Just c -> c
  Nothing -> ' '

isAlpha :: Char -> Boolean
isAlpha c =
  let n = toCharCode c
  in (n >= 65 && n <= 90) || (n >= 97 && n <= 122)

isDigit :: Char -> Boolean
isDigit c =
  let n = toCharCode c
  in n >= 48 && n <= 57

isAlphaNum :: Char -> Boolean
isAlphaNum c = isAlpha c || isDigit c

headIsDigit :: String -> Boolean
headIsDigit s = case SC.charAt 0 s of
  Just c -> isDigit c
  Nothing -> false

identCharToText :: Char -> String
identCharToText c
  | isAlphaNum c = SC.singleton c
  | otherwise = case c of
      '_' -> "_"
      '.' -> "$dot"
      '$' -> "$dollar"
      '~' -> "$tilde"
      '=' -> "$eq"
      '<' -> "$less"
      '>' -> "$greater"
      '!' -> "$bang"
      '#' -> "$hash"
      '%' -> "$percent"
      '^' -> "$up"
      '&' -> "$amp"
      '|' -> "$bar"
      '*' -> "$times"
      '/' -> "$div"
      '+' -> "$plus"
      '-' -> "$minus"
      ':' -> "$colon"
      '\\' -> "$bslash"
      '?' -> "$qmark"
      '@' -> "$at"
      '\'' -> "$prime"
      _ -> "$" <> show (toCharCode c)

nameIsJsReserved :: String -> Boolean
nameIsJsReserved name = Array.elem name jsAnyReserved

nameIsJsBuiltIn :: String -> Boolean
nameIsJsBuiltIn name = Array.elem name jsBuiltIns

jsBuiltIns :: Array String
jsBuiltIns =
  [ "arguments"
  , "Array"
  , "ArrayBuffer"
  , "Boolean"
  , "DataView"
  , "Date"
  , "decodeURI"
  , "decodeURIComponent"
  , "encodeURI"
  , "encodeURIComponent"
  , "Error"
  , "escape"
  , "eval"
  , "EvalError"
  , "Float32Array"
  , "Float64Array"
  , "Function"
  , "Infinity"
  , "Int16Array"
  , "Int32Array"
  , "Int8Array"
  , "Intl"
  , "isFinite"
  , "isNaN"
  , "JSON"
  , "Map"
  , "Math"
  , "NaN"
  , "Number"
  , "Object"
  , "parseFloat"
  , "parseInt"
  , "Promise"
  , "Proxy"
  , "RangeError"
  , "ReferenceError"
  , "Reflect"
  , "RegExp"
  , "Set"
  , "SIMD"
  , "String"
  , "Symbol"
  , "SyntaxError"
  , "TypeError"
  , "Uint16Array"
  , "Uint32Array"
  , "Uint8Array"
  , "Uint8ClampedArray"
  , "undefined"
  , "unescape"
  , "URIError"
  , "WeakMap"
  , "WeakSet"
  ]

jsAnyReserved :: Array String
jsAnyReserved =
  jsKeywords <> jsSometimesReserved <> jsFutureReserved <>
  jsFutureReservedStrict <> jsOldReserved <> jsLiterals

jsKeywords :: Array String
jsKeywords =
  [ "break", "case", "catch", "class", "const", "continue", "debugger"
  , "default", "delete", "do", "else", "export", "extends", "finally"
  , "for", "function", "if", "import", "in", "instanceof", "new"
  , "return", "super", "switch", "this", "throw", "try", "typeof"
  , "var", "void", "while", "with"
  ]

jsSometimesReserved :: Array String
jsSometimesReserved = ["await", "let", "static", "yield"]

jsFutureReserved :: Array String
jsFutureReserved = ["enum"]

jsFutureReservedStrict :: Array String
jsFutureReservedStrict =
  ["implements", "interface", "package", "private", "protected", "public"]

jsOldReserved :: Array String
jsOldReserved =
  [ "abstract", "boolean", "byte", "char", "double", "final", "float"
  , "goto", "int", "long", "native", "short", "synchronized", "throws"
  , "transient", "volatile"
  ]

jsLiterals :: Array String
jsLiterals = ["null", "true", "false"]
