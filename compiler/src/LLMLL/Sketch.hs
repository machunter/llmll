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
  , ScopeSource(..)
  , ScopeBinding(..)
  , InvariantSuggestion(..)
  , runSketch
    -- Encoding
  , encodeSketchResult
  ) where

import Data.Aeson (encode, object, (.=))
import qualified Data.Aeson as A
import qualified Data.ByteString.Lazy as BL
import Data.List (sortBy)
import qualified Data.Map.Strict as Map
import Data.Ord (comparing)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE

import LLMLL.TypeCheck
  ( SketchResult(..), SketchHole(..), HoleStatus(..)
  , ScopeSource(..), ScopeBinding(..)
  , InvariantSuggestion(..)
  , runSketch )
import LLMLL.Diagnostic (Diagnostic(..), Severity(..))
import LLMLL.Syntax (typeLabel)

-- ---------------------------------------------------------------------------
-- Schema version
-- ---------------------------------------------------------------------------

schemaVersion :: T.Text
schemaVersion = "0.3.0"  -- v0.3.5: added scope env to holes

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
  , "scope"        .= scopeToJson (shEnv sh)
  ]

-- | v0.3.5: Serialize the scope delta as a JSON array of {name, type, source} objects.
scopeToJson :: Map.Map T.Text ScopeBinding -> A.Value
scopeToJson env = A.toJSON
  [ object
      [ "name"   .= name
      , "type"   .= typeLabel (sbType binding)
      , "source" .= scopeSourceLabel (sbSource binding)
      ]
  | (name, binding) <- Map.toAscList env
  ]

scopeSourceLabel :: ScopeSource -> T.Text
scopeSourceLabel SrcParam      = "param"
scopeSourceLabel SrcLetBinding = "let-binding"
scopeSourceLabel SrcMatchArm   = "match-arm"
scopeSourceLabel SrcOpenImport = "open-import"

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

-- | Encode an InvariantSuggestion as JSON.
invariantToJson :: InvariantSuggestion -> A.Value
invariantToJson inv = object
  [ "pattern_id"  .= isPatternId inv
  , "suggestion"  .= isSuggestion inv
  , "description" .= isDescription inv
  ]

-- | Encode a SketchResult as a lazy ByteString JSON blob.
-- Errors are sorted: holeSensitive:false first (spec requirement).
-- v0.4: Includes invariant_suggestions field.
encodeSketchResult :: SketchResult -> BL.ByteString
encodeSketchResult result = encode $ object
  [ "schemaVersion"         .= schemaVersion
  , "holes"                 .= map holeToJson (sketchHoles result)
  , "errors"                .= map errToJson  (sortErrors (sketchErrors result))
  , "invariant_suggestions" .= map invariantToJson (sketchInvariants result)
  ]
