-- | Literals — Int, Number, String, Char, Boolean, Array, record.
-- |
-- | Exercises CodeGen.JS `literalToValueJS` (JS.hs:359-366) and Printer's
-- | numeric/string/array/object literal rendering.
module Examples.Literals where

import Prelude

answer :: Int
answer = 42

negativeAnswer :: Int
negativeAnswer = -42

pi :: Number
pi = 3.14159

bigNumber :: Number
bigNumber = 1.0e10

greeting :: String
greeting = "Hello, world!"

withEscape :: String
withEscape = "tab:\there\nnewline"

letter :: Char
letter = 'a'

flag :: Boolean
flag = true

nums :: Array Int
nums = [1, 2, 3, 4, 5]

person :: { name :: String, age :: Int }
person = { name: "Ada", age: 36 }

nested :: { coords :: { x :: Int, y :: Int }, label :: String }
nested = { coords: { x: 10, y: 20 }, label: "origin" }
