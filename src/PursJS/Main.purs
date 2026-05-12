-- | CLI driver. Reads a corefn.json file, runs the codegen pipeline, and
-- | prints the resulting JavaScript to stdout.
-- |
-- | This is the analogue of `Language.PureScript.Make.Actions.ssCodegen`
-- | (src/Language/PureScript/Make/Actions.hs:230-280) — the part that takes
-- | the CoreFn `Module Ann`, calls `J.moduleToJs`, runs `prettyPrintJS`, and
-- | writes the result.
-- |
-- | Usage:
-- |   pursjs <path-to-corefn.json> [--with-comments]
-- |
-- | The default is `--no-comments` to match `purs compile`'s default
-- | (Actions.hs:269-273: comments only emitted when `--comments` is passed).
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
import PursJS.PSString (mkString)

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
      -- purs's default is no comments. Use --with-comments to opt in.
      let noComments = not (Array.elem "--with-comments" tail)
      buf <- FS.readFile path
      contents <- Buffer.toString UTF8 buf
      case parseModule contents of
        Left e -> do
          Console.error ("parse error: " <> e)
          Process.exit' 1
        Right m -> do
          let foreignInclude =
                if Array.null m.foreign_ then Nothing
                else Just (mkString "./foreign.js")
          let mod = runModuleToJs { noComments } m foreignInclude
          let out = prettyPrintModule mod
          Console.log out
