-- | Ports `Language.PureScript.Comments` (purescript@c4a35b3,
-- | src/Language/PureScript/Comments.hs).
-- |
-- | `LineComment` = `-- ...`, `BlockComment` = `{- ... -}`.
module PursJS.Comments where

import Prelude

-- | Comments.hs — `data Comment = LineComment Text | BlockComment Text`.
data Comment
  = LineComment String
  | BlockComment String

derive instance Eq Comment
derive instance Ord Comment
