-- |
-- Module      : LLMLL.InvariantRegistry
-- Description : Data-driven invariant pattern registry for --sketch mode.
--
-- Loads invariant suggestion patterns from an external JSON file and matches
-- them against function signatures. No recompilation needed to add patterns.
--
-- v0.4: Initial implementation for Sprint 2 Task 7.
module LLMLL.InvariantRegistry
  ( -- * Types
    InvariantPattern(..)
  , TypeMatcher(..)
  , InvariantSuggestion(..)
    -- * Loading
  , loadPatterns
  , defaultPatterns
    -- * Matching
  , matchPatterns
  ) where

import Data.Aeson (FromJSON(..), (.:), (.:?), withObject)
import qualified Data.Aeson as A
import qualified Data.ByteString.Lazy as BL
import qualified Data.Text as T
import Data.Text (Text)

import LLMLL.Syntax (Type(..), Name)

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------

-- | A type signature matcher from the registry.
-- Simplified for v0.4: matches "list[a] -> list[a]" pattern specifically.
data TypeMatcher = TypeMatcher
  { tmParams  :: [TypePattern]
  , tmReturns :: TypePattern
  } deriving (Show, Eq)

-- | A single type pattern element.
data TypePattern
  = TPAny                  -- ^ matches any type
  | TPList Text            -- ^ list[a] — a is a variable name
  deriving (Show, Eq)

-- | An invariant pattern loaded from the registry.
data InvariantPattern = InvariantPattern
  { ipId          :: Text           -- ^ unique pattern identifier
  , ipDescription :: Text           -- ^ human-readable description
  , ipTypeSig     :: Maybe TypeMatcher  -- ^ type signature to match (Nothing = any)
  , ipNamePattern :: Text           -- ^ name substring/prefix to match
  , ipSuggestion  :: Text           -- ^ LLMLL postcondition expression text
  , ipValidFor    :: Text           -- ^ version compatibility field
  } deriving (Show, Eq)

-- | A matched invariant suggestion.
data InvariantSuggestion = InvariantSuggestion
  { isPatternId   :: Text    -- ^ which pattern matched
  , isSuggestion  :: Text    -- ^ the suggested postcondition
  , isDescription :: Text    -- ^ human-readable explanation
  } deriving (Show, Eq)

-- ---------------------------------------------------------------------------
-- JSON parsing
-- ---------------------------------------------------------------------------

instance FromJSON TypePattern where
  parseJSON = withObject "TypePattern" $ \o -> do
    kind <- o .: "kind"
    case (kind :: Text) of
      "list" -> TPList <$> o .: "elem"
      _      -> pure TPAny

instance FromJSON TypeMatcher where
  parseJSON = withObject "TypeMatcher" $ \o ->
    TypeMatcher <$> o .: "params" <*> o .: "returns"

instance FromJSON InvariantPattern where
  parseJSON = withObject "InvariantPattern" $ \o ->
    InvariantPattern
      <$> o .:  "id"
      <*> o .:  "description"
      <*> o .:? "type_signature"
      <*> o .:  "name_pattern"
      <*> o .:  "suggestion"
      <*> o .:  "valid_for"

-- ---------------------------------------------------------------------------
-- Loading
-- ---------------------------------------------------------------------------

-- | Load patterns from a JSON file. Returns empty list on any error.
loadPatterns :: FilePath -> IO [InvariantPattern]
loadPatterns path = do
  raw <- BL.readFile path
  case A.eitherDecode raw of
    Left _    -> pure []
    Right pats -> pure pats

-- | Built-in default patterns (used when no external file is available).
-- These match the 5 patterns from the registry JSON file.
defaultPatterns :: [InvariantPattern]
defaultPatterns =
  [ InvariantPattern
      { ipId = "list-preserving"
      , ipDescription = "Functions that transform a list but preserve its length"
      , ipTypeSig = Just (TypeMatcher [TPList "a"] (TPList "a"))
      , ipNamePattern = ".*"
      , ipSuggestion = "(= (list-length result) (list-length input))"
      , ipValidFor = ">=0.4"
      }
  , InvariantPattern
      { ipId = "sorted"
      , ipDescription = "Sorting functions should produce sorted output"
      , ipTypeSig = Just (TypeMatcher [TPList "a"] (TPList "a"))
      , ipNamePattern = "sort"
      , ipSuggestion = "(sorted result)"
      , ipValidFor = ">=0.4"
      }
  , InvariantPattern
      { ipId = "round-trip"
      , ipDescription = "Encode/decode pairs should round-trip"
      , ipTypeSig = Nothing
      , ipNamePattern = "encode|serialize|compress|marshal|pack"
      , ipSuggestion = "(= (decode (encode x)) x)"
      , ipValidFor = ">=0.4"
      }
  , InvariantPattern
      { ipId = "subset"
      , ipDescription = "Filtering/slicing functions produce a subset"
      , ipTypeSig = Just (TypeMatcher [TPList "a"] (TPList "a"))
      , ipNamePattern = "filter|take|drop|slice|remove"
      , ipSuggestion = "(<= (list-length result) (list-length input))"
      , ipValidFor = ">=0.4"
      }
  , InvariantPattern
      { ipId = "idempotent"
      , ipDescription = "Normalization/deduplication should be idempotent"
      , ipTypeSig = Nothing
      , ipNamePattern = "normalize|canonicalize|dedupe|dedup|unique|trim|clean"
      , ipSuggestion = "(= (f (f x)) (f x))"
      , ipValidFor = ">=0.4"
      }
  ]

-- ---------------------------------------------------------------------------
-- Matching
-- ---------------------------------------------------------------------------

-- | Match a function's name and type signature against all patterns.
-- Returns all matching suggestions.
matchPatterns :: Name -> Type -> [InvariantPattern] -> [InvariantSuggestion]
matchPatterns name ty patterns =
  [ InvariantSuggestion
      { isPatternId   = ipId pat
      , isSuggestion  = ipSuggestion pat
      , isDescription = ipDescription pat
      }
  | pat <- patterns
  , matchesName name (ipNamePattern pat)
  , matchesType ty (ipTypeSig pat)
  ]

-- | Check if a function name matches a name pattern.
-- Pattern format: ".*" matches everything, "foo|bar|baz" matches if name contains any.
matchesName :: Name -> Text -> Bool
matchesName _name ".*" = True
matchesName name pat =
  let parts = T.splitOn "|" pat
  in any (\p -> T.isInfixOf p name) parts

-- | Check if a function's type matches a type signature matcher.
matchesType :: Type -> Maybe TypeMatcher -> Bool
matchesType _ Nothing = True   -- no type constraint = matches any
matchesType (TFn paramTypes retType) (Just tm) =
  matchParamTypes paramTypes (tmParams tm) && matchRetType retType (tmReturns tm)
matchesType _ (Just _) = False  -- non-function types don't match

-- | Check if parameter types match the pattern's param types.
matchParamTypes :: [Type] -> [TypePattern] -> Bool
matchParamTypes [] [] = True
matchParamTypes (t:ts) (p:ps) = matchTypePattern t p && matchParamTypes ts ps
matchParamTypes _ _ = False  -- arity mismatch

-- | Check if a single type matches a type pattern.
matchTypePattern :: Type -> TypePattern -> Bool
matchTypePattern _ TPAny = True
matchTypePattern (TList _) (TPList _) = True
matchTypePattern _ _ = False

-- | Check if the return type matches.
matchRetType :: Type -> TypePattern -> Bool
matchRetType = matchTypePattern
