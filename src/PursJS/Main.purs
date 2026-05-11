-- | CLI: read a corefn.json file, transform it, and print the generated JS to
-- | stdout. Usage:
-- |   pursjs <path-to-corefn.json> [--no-comments]
module PursJS.Main where

import Prelude

import Data.Array as Array
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Effect (Effect)
import Effect.Class.Console as Console
import Effect.Exception (throw)
import Node.Buffer as Buffer
import Node.Encoding (Encoding(..))
import Node.FS.Sync as FS
import Node.Process as Process
import PursJS.CodeGen.JS (runModuleToJs)
import PursJS.CodeGen.Printer (prettyPrintModule)
import PursJS.CoreFn.FromJSON (parseModule)

main :: Effect Unit
main = do
  args <- Process.argv
  -- argv[0] = node, argv[1] = script. The rest is user args.
  let userArgs = Array.drop 2 args
  case Array.uncons userArgs of
    Nothing -> do
      Console.error "Usage: pursjs <path-to-corefn.json> [--no-comments]"
      Process.exit' 1
    Just { head: path, tail } -> do
      let noComments = Array.elem "--no-comments" tail
      buf <- FS.readFile path
      contents <- Buffer.toString UTF8 buf
      case parseModule contents of
        Left e -> do
          Console.error ("parse error: " <> e)
          Process.exit' 1
        Right m -> do
          let mod = runModuleToJs { noComments } m Nothing
          let out = prettyPrintModule mod
          Console.log out
