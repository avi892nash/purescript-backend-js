-- | String literals — exercises PSString's `prettyPrintStringJS` (PSString.hs:200-219).
-- |
-- | The encoder iterates over UTF-16 code units, emitting `\x..`, `\u....`,
-- | or one-of the named escapes (`\n`, `\t`, etc.).
module Examples.Strings where

-- Plain ASCII.
plain :: String
plain = "Hello"

-- All the named escape sequences.
named :: String
named = "a\tb\nc\rd\\e\"f"

-- High-bit ASCII (0x80-0xFF) — printed as `\xNN`.
highBit :: String
highBit = "café"

-- Non-BMP would be a surrogate pair in UTF-16; emoji emits `😀`.
emoji :: String
emoji = "😀"

-- Mix of plain and escapes.
mixed :: String
mixed = "line one\n  line two\t(tabbed)"
