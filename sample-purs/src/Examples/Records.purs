-- | Records: literals, projection, and record-update.
-- |
-- | Exercises:
-- |   - ObjectLiteral codegen (Literal ObjectLiteral) in JS.hs:359-366
-- |   - Accessor (JS.hs:294-295) — `r.field` becomes `r["field"]` then the
-- |     printer prints it as `r.field` when "field" is a valid JS identifier
-- |   - ObjectUpdate (JS.hs:296-302) — { r with x = 1 } either becomes a
-- |     known-copy ObjectLiteral or an extendObj IIFE
module Examples.Records where

import Prelude

type Point = { x :: Int, y :: Int }

origin :: Point
origin = { x: 0, y: 0 }

-- Projection compiles to `r.x` or `r["x"]`.
xCoord :: Point -> Int
xCoord r = r.x

-- Record update with a known copy-list: emits a new ObjectLiteral with both
-- copied and updated fields.
moveX :: Point -> Int -> Point
moveX p dx = p { x = p.x + dx }

-- Multi-field record update.
shift :: Point -> Int -> Int -> Point
shift p dx dy = p { x = p.x + dx, y = p.y + dy }

-- Quoted field with non-identifier characters — the codegen will keep this
-- as a bracket-index `r["odd-key"]` because the printer's accessor rewrite
-- in Printer.hs:184-191 only takes effect for valid JS identifiers.
type Tagged = { "odd-key" :: Int }

tagged :: Tagged
tagged = { "odd-key": 42 }
