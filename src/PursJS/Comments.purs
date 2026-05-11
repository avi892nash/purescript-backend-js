module PursJS.Comments where

import Prelude

data Comment
  = LineComment String
  | BlockComment String

derive instance Eq Comment
derive instance Ord Comment
