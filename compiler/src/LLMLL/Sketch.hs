-- |
-- Module      : LLMLL.Sketch
-- Description : Output contract for llmll typecheck --sketch (Phase 2c D5).
--
-- This module owns the JSON encoding of sketch results.
-- TypeCheck.hs owns the inference; this module owns the wire format.
--
-- Output schema (schemaVersion 0.2.0):
-- {
--   "schemaVersion": "0.2.0",
--   "holes": [ { "name", "inferredType", "pointer" } ],
--   "errors": [ { "kind", "message", "pointer", "holeSensitive",
--                 "expected"?, "got"?, "hole"? } ]
-- }
module LLMLL.Sketch
  ( -- Re-export TypeCheck types so consumers only need LLMLL.Sketch
    SketchResult(..)
  , SketchHole(..)
  , HoleStatus(..)
  , runSketch
    -- Encoding
  , encodeSketchResult
  ) where

import Data.Aeson (encode, object, (.=))
import qualified Data.Aeson as A
import qualified Data.ByteString.Lazy as BL
import Data.List (sortBy)
import Data.Ord (comparing)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE

import LLMLL.TypeCheck
  ( SketchResult(..), SketchHole(..), HoleStatus(..), runSketch )
import LLMLL.Diagnostic (Diagnostic(..), Severity(..))
import LLMLL.Syntax (typeLabel)

-- ---------------------------------------------------------------------------
-- Schema version
-- ---------------------------------------------------------------------------

schemaVersion :: T.Text
schemaVersion = "0.2.0"

-- ---------------------------------------------------------------------------
-- Error sorting: holeSensitive:false before holeSensitive:true (spec requirement)
-- ---------------------------------------------------------------------------

sortErrors :: [Diagnostic] -> [Diagnostic]
sortErrors = sortBy (comparing diagHoleSensitive)
-- Bool: False < True, so False-first is the natural ordering

-- ---------------------------------------------------------------------------
-- JSON encoders
-- ---------------------------------------------------------------------------

holeToJson :: SketchHole -> A.Value
holeToJson sh = object
  [ "name"         .= shName sh
  , "inferredType" .= inferredTypeJson (shStatus sh)
  , "pointer"      .= shPointer sh
  ]

inferredTypeJson :: HoleStatus -> A.Value
inferredTypeJson (HoleTyped t)       = A.String (typeLabel t)
inferredTypeJson (HoleAmbiguous _ _) = A.Null
inferredTypeJson HoleUnknown         = A.Null

errToJson :: Diagnostic -> A.Value
errToJson d = object $
  [ "kind"          .= diagKind d
  , "message"       .= diagMessage d
  , "holeSensitive" .= diagHoleSensitive d
  ] ++
  maybe [] (\p -> ["pointer"  .= p]) (diagPointer d)  ++
  maybe [] (\e -> ["expected" .= e]) (diagExpected d) ++
  maybe [] (\g -> ["got"      .= g]) (diagGot d)      ++
  maybe [] (\h -> ["hole"     .= h]) (diagHole d)

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

-- | Encode a SketchResult as a lazy ByteString JSON blob.
-- Errors are sorted: holeSensitive:false first (spec requirement).
encodeSketchResult :: SketchResult -> BL.ByteString
encodeSketchResult result = encode $ object
  [ "schemaVersion" .= schemaVersion
  , "holes"         .= map holeToJson (sketchHoles result)
  , "errors"        .= map errToJson  (sortErrors (sketchErrors result))
  ]
