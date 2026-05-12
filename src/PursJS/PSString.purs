-- | Ports `Language.PureScript.PSString` (purescript@c4a35b3,
-- | src/Language/PureScript/PSString.hs).
-- |
-- | The Haskell representation is `[Word16]` (a list of UTF-16 code units).
-- | Here we use `String`, which is already UTF-16 internally in JavaScript,
-- | so `toCharCode` on each Char gives us the code unit.
-- |
-- | Mapping (PursJS <-> PSString.hs line):
-- |   PSString                  PSString.hs:51        (`newtype PSString { toUTF16CodeUnits :: [Word16] }`)
-- |   mkString                  PSString.hs:239-240
-- |   decodeString              PSString.hs:99-100
-- |   prettyPrintStringJS       PSString.hs:200-219
-- |   encodeCodeUnit            PSString.hs:203-214 (the `encodeChar` helper)
-- |   showHexPad / showHex      PSString.hs:216-219 (`showHex'`)
module PursJS.PSString where

import Prelude

import Data.Array as Array
import Data.Char as Char
import Data.Foldable (foldMap)
import Data.Maybe (Maybe(..), fromMaybe)
import Data.String as Str
import Data.String.CodeUnits as CU

newtype PSString = PSString String

derive newtype instance Eq PSString
derive newtype instance Ord PSString

mkString :: String -> PSString
mkString = PSString

decodeString :: PSString -> Maybe String
decodeString (PSString s) = Just s

runPSString :: PSString -> String
runPSString (PSString s) = s

-- | Pretty-print a PSString as a JS string literal, matching
-- | Haskell's `prettyPrintStringJS`.
prettyPrintStringJS :: PSString -> String
prettyPrintStringJS (PSString s) =
  "\"" <> foldMap encodeCodeUnit (toCodeUnits s) <> "\""

toCodeUnits :: String -> Array Int
toCodeUnits s = map Char.toCharCode (CU.toCharArray s)

encodeCodeUnit :: Int -> String
encodeCodeUnit c
  | c > 0xFF = "\\u" <> showHexPad 4 c
  | c > 0x7E || c < 0x20 = "\\x" <> showHexPad 2 c
  | c == 0x08 = "\\b"
  | c == 0x09 = "\\t"
  | c == 0x0A = "\\n"
  | c == 0x0B = "\\v"
  | c == 0x0C = "\\f"
  | c == 0x0D = "\\r"
  | c == 0x22 = "\\\""
  | c == 0x5C = "\\\\"
  | otherwise = fromMaybe "?" (CU.singleton <$> Char.fromCharCode c)

showHexPad :: Int -> Int -> String
showHexPad width n =
  let hs = showHex n
      padLen = width - Str.length hs
  in (Str.joinWith "" (Array.replicate padLen "0")) <> hs

showHex :: Int -> String
showHex 0 = "0"
showHex n = go n ""
  where
  go :: Int -> String -> String
  go 0 acc = acc
  go x acc =
    let d = x `mod` 16
        ch = if d < 10
                then fromMaybe '0' (Char.fromCharCode (d + 48))
                else fromMaybe 'a' (Char.fromCharCode (d - 10 + 97))
    in go (x / 16) (CU.singleton ch <> acc)
