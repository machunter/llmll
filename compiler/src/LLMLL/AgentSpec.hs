-- |
-- Module      : LLMLL.AgentSpec
-- Description : Compiler-emitted agent specification for LLM system prompts.
--
-- Reads 'builtinEnv' from TypeCheck and serializes it as a structured spec
-- for inclusion in agent system prompts.  Single source of truth: adding a
-- new builtin to 'builtinEnv' automatically appears in the agent spec.
--
-- v0.3.4: Phase B from agent-prompt-semantics-gap.md
module LLMLL.AgentSpec
  ( -- * Core
    agentSpec
  , agentSpecJSON
  , agentSpecText
    -- * Types
  , AgentSpec(..)
  , BuiltinEntry(..)
  , OperatorEntry(..)
  ) where

import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import Data.Set (Set)
import qualified Data.Set as Set

import LLMLL.Syntax (Type(..), Name)
import LLMLL.TypeCheck (builtinEnv)

-- ---------------------------------------------------------------------------
-- Data Types
-- ---------------------------------------------------------------------------

-- | Complete agent specification.
data AgentSpec = AgentSpec
  { asVersion    :: Text
  , asBuiltins   :: [BuiltinEntry]
  , asOperators  :: [OperatorEntry]
  } deriving (Show, Eq)

-- | A builtin function entry.
data BuiltinEntry = BuiltinEntry
  { beName     :: Name
  , beParams   :: [(Name, Text)]   -- ^ param name + type label
  , beReturns  :: Text             -- ^ return type label
  } deriving (Show, Eq)

-- | An operator entry.
data OperatorEntry = OperatorEntry
  { aoOp      :: Name
  , aoParams  :: [Text]           -- ^ type labels for each operand
  , aoReturns :: Text             -- ^ return type label
  } deriving (Show, Eq)

-- ---------------------------------------------------------------------------
-- Operator Set
-- ---------------------------------------------------------------------------

-- | All names routed through EOp / emitOp in codegen.
-- Must match the pattern matches in CodegenHs.emitOp exactly.
operatorNames :: Set Name
operatorNames = Set.fromList
  [ "+", "-", "*", "/", "mod"          -- arithmetic
  , "=", "!=", "<", ">", "<=", ">="    -- comparison
  , "and", "or", "not"                  -- logic
  ]

-- ---------------------------------------------------------------------------
-- Exclusion
-- ---------------------------------------------------------------------------

-- | Capability-gated names excluded from the agent spec.
-- Uses prefix match so new wasi.* functions are automatically excluded.
isExcluded :: Name -> Bool
isExcluded n = "wasi." `T.isPrefixOf` n

-- ---------------------------------------------------------------------------
-- Core Generation
-- ---------------------------------------------------------------------------

-- | Generate the agent spec from builtinEnv.
-- Deterministic: all output is sorted alphabetically.
agentSpec :: AgentSpec
agentSpec = AgentSpec
  { asVersion   = "0.3.4"
  , asBuiltins  = sort' beName  builtinEntries
  , asOperators = sort' aoOp    operatorEntries
  }
  where
    -- Partition builtinEnv into operators and functions
    allEntries = Map.toAscList builtinEnv
    (operatorEntries, builtinEntries) = foldr partition ([], []) allEntries

    partition (name, ty) (ops, fns)
      | isExcluded name = (ops, fns)     -- skip wasi.*
      | name `Set.member` operatorNames = (mkOp name ty : ops, fns)
      | otherwise                       = (ops, mkFn name ty : fns)

    mkFn name (TFn params ret) = BuiltinEntry
      { beName    = name
      , beParams  = zipWith (\i t -> (paramName i t, renderType t)) [0 :: Int ..] params
      , beReturns = renderType ret
      }
    mkFn name ty = BuiltinEntry name [] (renderType ty)

    mkOp name (TFn params ret) = OperatorEntry
      { aoOp      = name
      , aoParams  = map renderType params
      , aoReturns = renderType ret
      }
    mkOp name ty = OperatorEntry name [] (renderType ty)

    sort' f = sortBy' (\a b -> compare (f a) (f b))

-- | Stable sort by a comparator (not importing Data.List.sortBy to keep deps minimal)
sortBy' :: (a -> a -> Ordering) -> [a] -> [a]
sortBy' _ [] = []
sortBy' cmp (x:xs) = sortBy' cmp lesser ++ [x] ++ sortBy' cmp greater
  where
    lesser  = [y | y <- xs, cmp y x /= GT]
    greater = [y | y <- xs, cmp y x == GT]

-- ---------------------------------------------------------------------------
-- Type Rendering
-- ---------------------------------------------------------------------------

-- | Render a type in polymorphic Haskell-style notation for agent prompts.
renderType :: Type -> Text
renderType TInt            = "int"
renderType TFloat          = "float"
renderType TString         = "string"
renderType TBool           = "bool"
renderType TUnit           = "unit"
renderType (TBytes n)      = "bytes[" <> T.pack (show n) <> "]"
renderType (TList t)       = "list[" <> renderType t <> "]"
renderType (TMap k v)      = "map[" <> renderType k <> ", " <> renderType v <> "]"
renderType (TResult t e)   = "Result[" <> renderType t <> ", " <> renderType e <> "]"
renderType (TPair a b)     = "(" <> renderType a <> ", " <> renderType b <> ")"
renderType (TFn args ret)  = "(" <> T.intercalate ", " (map renderType args) <> ") → " <> renderType ret
renderType (TPromise t)    = "Promise[" <> renderType t <> "]"
renderType (TDependent _ b _) = renderType b
renderType TDelegationError = "DelegationError"
renderType (TVar n)        = n
renderType (TCustom n)     = n
renderType (TSumType ctors) = T.intercalate " | " (map fst ctors)

-- | Generate a parameter name from index and type.
paramName :: Int -> Type -> Name
paramName _ TString = "s"
paramName _ TInt    = "n"
paramName _ TBool   = "b"
paramName _ (TList _) = "xs"
paramName _ (TResult _ _) = "r"
paramName _ (TVar n) = n
paramName i _ = "x" <> T.pack (show i)

-- ---------------------------------------------------------------------------
-- JSON Output
-- ---------------------------------------------------------------------------

-- | Emit the agent spec as a JSON string.
agentSpecJSON :: Text
agentSpecJSON = T.unlines
  [ "{"
  , "  \"version\": " <> jsonStr (asVersion spec) <> ","
  , "  \"builtins\": ["
  , T.intercalate ",\n" (map emitBuiltinJSON (asBuiltins spec))
  , "  ],"
  , "  \"operators\": ["
  , T.intercalate ",\n" (map emitOpJSON (asOperators spec))
  , "  ],"
  , "  \"constructors\": {"
  , "    \"Result\": {\"variants\": [\"Success\", \"Error\"], \"note\": \"ok(v) → Success, err(e) → Error\"},"
  , "    \"Pair\": {\"variants\": [\"pair\"], \"note\": \"pair(a, b) → (a, b); first(p)/second(p) to project\"}"
  , "  },"
  , "  \"evaluation_model\": \"strict, left-to-right\","
  , "  \"pattern_kinds\": [\"constructor\", \"bind\", \"literal\", \"wildcard\"],"
  , "  \"type_nodes\": ["
  , "    {\"kind\": \"primitive\", \"values\": [\"int\", \"float\", \"string\", \"bool\", \"unit\"]},"
  , "    {\"kind\": \"result\", \"syntax\": \"Result[ok_type, err_type]\"},"
  , "    {\"kind\": \"list\", \"syntax\": \"list[elem_type]\"},"
  , "    {\"kind\": \"pair\", \"syntax\": \"(A, B)\"},"
  , "    {\"kind\": \"fn\", \"syntax\": \"fn [params] → return_type\"}"
  , "  ]"
  , "}"
  ]
  where
    spec = agentSpec

emitBuiltinJSON :: BuiltinEntry -> Text
emitBuiltinJSON e =
  "    {\"name\": " <> jsonStr (beName e)
  <> ", \"params\": [" <> T.intercalate ", " (map fmtParam (beParams e)) <> "]"
  <> ", \"returns\": " <> jsonStr (beReturns e) <> "}"
  where
    fmtParam (n, t) = "[" <> jsonStr n <> ", " <> jsonStr t <> "]"

emitOpJSON :: OperatorEntry -> Text
emitOpJSON e =
  "    {\"op\": " <> jsonStr (aoOp e)
  <> ", \"params\": [" <> T.intercalate ", " (map jsonStr (aoParams e)) <> "]"
  <> ", \"returns\": " <> jsonStr (aoReturns e) <> "}"

jsonStr :: Text -> Text
jsonStr t = "\"" <> T.concatMap escape t <> "\""
  where
    escape '"'  = "\\\""
    escape '\\' = "\\\\"
    escape '\n' = "\\n"
    escape c    = T.singleton c

-- ---------------------------------------------------------------------------
-- Text Output (for direct LLM system prompt inclusion)
-- ---------------------------------------------------------------------------

-- | Emit the agent spec as a token-dense text reference.
agentSpecText :: Text
agentSpecText = T.unlines $
  [ "## LLMLL Built-in Functions"
  , ""
  ] ++ map emitBuiltinText (asBuiltins spec) ++
  [ ""
  , "## Operators"
  , ""
  ] ++ map emitOpText (asOperators spec) ++
  [ ""
  , "## Constructors"
  , ""
  , "- Result: Success(value) / Error(err) — use ok(v)/err(e) to construct"
  , "- Pair: pair(a, b) — use first(p)/second(p) to project"
  , ""
  , "## Evaluation Model"
  , ""
  , "Strict, left-to-right. let bindings are sequential."
  , ""
  , "## Pattern Kinds (for match arms)"
  , ""
  , "- constructor: {\"kind\": \"constructor\", \"constructor\": \"Success\", \"sub_patterns\": [{\"kind\": \"bind\", \"name\": \"x\"}]}"
  , "- bind: {\"kind\": \"bind\", \"name\": \"x\"}"
  , "- literal: {\"kind\": \"literal\", \"value\": {\"kind\": \"lit-int\", \"value\": 0}}"
  , "- wildcard: {\"kind\": \"wildcard\"}"
  , ""
  , "## Type Nodes (for JSON-AST)"
  , ""
  , "- Primitive: {\"kind\": \"primitive\", \"name\": \"int\"} (also: float, string, bool, unit)"
  , "- Result: {\"kind\": \"result\", \"ok_type\": ..., \"err_type\": ...}"
  , "- List: {\"kind\": \"list\", \"element_type\": ...}"
  , "- Pair: {\"kind\": \"pair-type\", \"first_type\": ..., \"second_type\": ...}"
  , "- Function: {\"kind\": \"fn-type\", \"param_types\": [...], \"return_type\": ...}"
  ]
  where
    spec = agentSpec

emitBuiltinText :: BuiltinEntry -> Text
emitBuiltinText e =
  let name = beName e
      sig  = T.intercalate " → " (map snd (beParams e) ++ [beReturns e])
      pad  = T.replicate (max 1 (22 - T.length name)) " "
  in name <> pad <> ": " <> sig

emitOpText :: OperatorEntry -> Text
emitOpText e =
  let name = aoOp e
      sig  = T.intercalate " → " (aoParams e ++ [aoReturns e])
      pad  = T.replicate (max 1 (22 - T.length name)) " "
  in name <> pad <> ": " <> sig
