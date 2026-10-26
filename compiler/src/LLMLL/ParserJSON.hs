{-# LANGUAGE OverloadedStrings #-}
-- |
-- Module      : LLMLL.ParserJSON
-- Description : Parse a JSON-AST (.ast.json) file into the same [Statement] AST
--               that Parser.hs produces from S-expression source.
--
-- The two parsers MUST agree on every construct. Any divergence is a bug.
--
-- JSON schema: docs/llmll-ast.schema.json
-- Versioning policy: the "description" field of that same schema file, which
-- enumerates the accepted schemaVersions and what each one added. There is no
-- separate versioning document by design -- a second file would be a second
-- source of truth to drift against. The per-bump rationale lives in the
-- 'expectedSchemaVersion' comment block below.
module LLMLL.ParserJSON
  ( parseJSONAST
  , parseJSONASTValue
  , expectedSchemaVersion
    -- | Exported so the test suite can assert that what the emitter STAMPS is
    -- something the reader ACCEPTS. Bumping one without the other compiles
    -- fine and makes the compiler refuse to read its own output.
  , acceptedSchemaVersions
  ) where

import Control.Monad (when)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.ByteString.Lazy as BL
import Data.Aeson
  ( Value(..), Object
  , eitherDecode
  , withObject, withText )
import Data.Aeson.Types
  ( Parser, parseEither
  , (.:), (.:?), (.!=) )
import qualified Data.Aeson.KeyMap as KM
import qualified Data.Aeson.Key    as Key

import LLMLL.Syntax
import LLMLL.Diagnostic (Diagnostic(..), mkError)
import LLMLL.FloatLit (classifyFloatLit, floatLitRangeMessage, floatLitRangeTag)
import Data.Scientific (Scientific)
import qualified Data.Scientific as Sci
import qualified Data.ByteString.Lazy.Char8 as BL8
import Data.Char (isDigit)
import Data.Int (Int64)

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

-- | The schema version this parser accepts. Compiler rejects any other value.
-- v0.10.2: bumped from 0.3.0 to 0.4.0 to signal identifier-shape regex
-- constraints on ExprApp.fn and ExprQualApp.qual_fn.
-- v0.11 LT-INV: bumped from 0.5.0 to 0.6.0; gate confirmed EL-5 2026-05-30.
-- DEF-RET (v0.13.x): bumped 0.6.0 → 0.7.0 for the optional return_type field on def/def-shell.
-- REC-DESCENT (v0.14.24): bumped 0.7.0 → 0.8.0 for the optional decreases array on def-shell.
-- SRC-CONJ-1: bumped 0.8.0 → 0.9.0 for the optional pre_clauses/post_clauses
-- per-conjunct provenance arrays on def/def-shell/letrec.
-- DISCARD-1 (v0.14.80): bumped 0.9.0 → 0.10.0. TWO changes, one additive and
-- one breaking, shipped together so the corpus pays one bump instead of two:
-- the optional `discard` flag on do-step (additive), and the REMOVAL of `read`
-- from def-main (breaking). Minor rather than major follows the precedent
-- above, where every additive-optional field took a minor; the removal is
-- carried at the same level because its measured in-tree population was zero.
-- Both nodes carry "additionalProperties": false, so neither field can ride in
-- unversioned: a document with `discard` fails against 0.9.0, and a document
-- with `read` now fails against 0.10.0.
-- PROC-BOUNDARY-1: bumped 0.10.0 → 0.11.0 for the optional `status` field on
-- def-main. PURELY ADDITIVE, unlike DISCARD-1's mixed bump above: nothing is
-- removed and no existing field changes meaning, so every 0.10.0 document is a
-- valid 0.11.0 one. The bump is still owed rather than optional, because
-- DefMain carries "additionalProperties": false, so a document with `status`
-- fails validation against 0.10.0 and the field cannot ride in unversioned.
-- MODE-CLI-1 + MODE-HTTP-1: bumped 0.11.0 → 0.12.0. DefMain.mode becomes the
-- plain string enum ["console", "cli"] and the {"kind": "http", "port": N}
-- object is removed. A cli step now takes (State, Response). No tracked
-- document used http, so every older version stays accepted for reading.
-- AST-TYPE-ALIAS-1 + FFI-CONV-1: bumped 0.12.0 → 0.13.0, once for both. A
-- type-decl body may be any Type (a plain alias), and Type gains the boundary
-- kinds hs-text, hs-int and hs-maybe. Both are additive: every 0.12.0 document
-- is a valid 0.13.0 one, so the older versions stay accepted for reading.
-- FLOAT-LIT-1 (decimal-numbers-proposal Rev 1, R1-2): bumped 0.13.0 → 0.14.0
-- for the optional `literal_kind` key on a literal pattern. Additive: every
-- 0.13.0 document is a valid 0.14.0 one, so the older versions stay accepted.
-- GENERICS-1: bumped 0.14.0 → 0.15.0 for the optional `type_params` key on a
-- def-shell and the `type-var` Type kind. Additive, so 0.14.0 stays accepted.
expectedSchemaVersion :: Text
expectedSchemaVersion = "0.15.0"

-- | Versions the reader accepts. REC-DESCENT's decreases and DEF-RET's return_type are
-- additive-optional, so a 0.7.0 / 0.6.0 document (those fields absent) is a valid 0.8.0
-- one — accept all for backward-compatible reads. Emission stamps 'expectedSchemaVersion'.
-- Grammar discipline (e.g. def-logic rejection) is enforced separately by GrammarMode.
--
-- DISCARD-1: this list must gain each new version alongside the
-- 'expectedSchemaVersion' bump above, or the compiler emits a document it then
-- refuses to read. Bumping only the stamp is a silent emit/read asymmetry that
-- no type catches: it was caught here by round-tripping the emitter's own
-- output, which is why the test suite pins that round trip rather than the
-- constant.
--
-- Older versions stay accepted because 'read' was optional on def-main and the
-- reader now ignores it: a pre-0.10.0 document that carried it still parses,
-- losing a field nothing consumed. Schema validation of such a document against
-- 0.10.0 fails, which is the intended split — the schema is the authority on
-- what may be WRITTEN, this list on what can still be READ.
acceptedSchemaVersions :: [Text]
acceptedSchemaVersions = ["0.15.0", "0.14.0", "0.13.0", "0.12.0", "0.11.0", "0.10.0", "0.9.0", "0.8.0", "0.7.0", "0.6.0"]

-- | Parse a JSON-AST byte string into a list of top-level statements.
-- Returns @Left Diagnostic@ on any structural or version error.
parseJSONAST :: GrammarMode -> FilePath -> BL.ByteString -> Either Diagnostic [Statement]
parseJSONAST mode fp bs
  -- FLOAT-LIT-1 (D7): aeson reads a number's exponent as a bounded Int, so
  -- 1e18446744073709551617 is already the number 10 in the decoded Value and
  -- no check on the Value can see it. The raw bytes are the last place the
  -- exponent is still text.
  | Just tok <- oversizedExponent bs =
      Left (mkError Nothing (floatLitRangeMessage tok "has an exponent too large to represent"))
             { diagKind       = Just floatLitRangeTag
             , diagCode       = Just "E011"
             , diagSuggestion = Just "write the number with an exponent of at most 18 digits; a float literal must round to a finite double"
             }
  | otherwise =
  case eitherDecode bs of
    Left err ->
      -- B1: aeson surfaces \x1b and other invalid JSON escapes as a UTF-8 decode
      -- error pointing at an unrelated location. Detect the pattern and add a
      -- targeted hint so agents know immediately what to fix.
      let isEscapeError = any (`T.isInfixOf` T.pack err)
                            ["Invalid UTF-8", "Cannot decode", "Failed reading"]
          hint = if isEscapeError
                   then Just "JSON strings must use \\uXXXX for control/non-ASCII chars (e.g. \\u001b not \\x1b)"
                   else Nothing
          diag = (mkError Nothing (T.pack err))
                   { diagKind       = Just "json-parse-error"
                   , diagPointer    = Just "/"
                   , diagCode       = Just "E010"
                   , diagSuggestion = hint
                   }
      in Left diag
    Right val ->
      case parseEither (parseProgram mode fp) val of
        Left msg ->
          let k = extractKind (T.pack msg)
              diag = (mkError Nothing (T.pack msg))
                       { diagKind       = Just k
                       , diagCode       = Just "E011"
                       , diagSuggestion =
                           if k == "core-grammar-violation"
                             then Just "Replace {\"kind\":\"def-logic\",...} with {\"kind\":\"def\",...} (strict-core) or {\"kind\":\"def-shell\",...} (permissive); replace {\"kind\":\"letrec\",...} with {\"kind\":\"def-shell\",...}"
                           else if k == "legacy-grammar-violation"
                             then Just "Drop --grammar=legacy to parse v0.11 programs ({\"kind\":\"def\",...} / {\"kind\":\"def-shell\",...} are the current forms); def-logic was removed in v0.12.1, so under --grammar=legacy only {\"kind\":\"letrec\",...} remains available"
                           else if k == "unexpected-key"
                             then Just (unexpectedKeyHint (T.pack msg))
                           else if k == "type-params-not-supported"
                             then Just typeParamsHint
                           else if k == "removed-construct"
                             then Just "def-logic was removed in v0.12.1; replace {\"kind\":\"def-logic\",...} with {\"kind\":\"def\",...} (strict-core) or {\"kind\":\"def-shell\",...} (permissive)"
                           else Nothing
                       }
          in Left diag
        Right stmts -> Right stmts
  where
    extractKind msg
      | "schema-version-mismatch"  `T.isInfixOf` msg = "schema-version-mismatch"
      | "core-grammar-violation"   `T.isInfixOf` msg = "core-grammar-violation"
      | "legacy-grammar-violation" `T.isInfixOf` msg = "legacy-grammar-violation"
      | "removed-construct"        `T.isInfixOf` msg = "removed-construct"
      | "unexpected-key:"          `T.isInfixOf` msg = "unexpected-key"
      -- FLOAT-LIT-1
      | "float-literal-range:"     `T.isInfixOf` msg = "float-literal-range"
      -- BYTES-LEN-RANGE-1
      | "bytes-length-range:"      `T.isInfixOf` msg = "bytes-length-range"
      | "literal-kind-mismatch:"   `T.isInfixOf` msg = "literal-kind-mismatch"
      -- GENERICS-1
      | "type-params-not-supported:" `T.isInfixOf` msg = "type-params-not-supported"
      | "unknown-type-var:"        `T.isInfixOf` msg = "unknown-type-var"
      | otherwise = "json-decode-error"

-- | AST-RETURNS-KEY-1: the fix for a definition-head key the reader does not
-- know. "returns" is the measured confusion (the DEMO-COMP brief spells it so).
unexpectedKeyHint :: Text -> Text
unexpectedKeyHint msg
  | "\"returns\"" `T.isInfixOf` msg =
      "The return-type key is \"return_type\"; a \"returns\" key is not read"
  | "def '" `T.isInfixOf` msg && "\"decreases\"" `T.isInfixOf` msg =
      "A \"decreases\" measure belongs on a def-shell; a def may not self-recurse"
  | otherwise =
      "Remove the key or correct its spelling; docs/llmll-ast.schema.json lists the declared keys"

-- | GENERICS-1: the fix for a @type_params@ key on a form other than
-- def-shell, modelled on the @decreases@ hint above.
typeParamsHint :: Text
typeParamsHint =
  "A \"type_params\" list belongs on a def-shell; on def, letrec, def-interface"
  <> " and type-decl it is deferred (GENERICS-2, GENERIC-TYPES-1)"

-- | Parse a JSON Value (already decoded) into statements.
-- Returns multi-error diagnostics for agent round-trip efficiency.
-- GrammarMode is threaded from the caller so patch-apply uses the host file's mode.
parseJSONASTValue :: GrammarMode -> Value -> Either [Diagnostic] [Statement]
parseJSONASTValue mode val =
  case parseEither (parseProgram mode "<patch>") val of
    Left msg -> Left [(mkError Nothing (T.pack msg))
      { diagKind = Just "json-decode-error"
      , diagCode = Just "E011"
      }]
    Right stmts -> Right stmts

-- ---------------------------------------------------------------------------
-- Program-level decoder
-- ---------------------------------------------------------------------------

parseProgram :: GrammarMode -> FilePath -> Value -> Parser [Statement]
parseProgram mode _fp = withObject "Program" $ \o -> do
  sv <- o .: "schemaVersion" :: Parser Text
  if sv `notElem` acceptedSchemaVersions
    then fail $
      "schema-version-mismatch: expected one of "
      ++ show acceptedSchemaVersions
      ++ ", got '"
      ++ T.unpack sv
      -- No inner quotes around `description`: the message is rendered inside a
      -- quoted string in both the s-expression and the JSON diagnostic
      -- channels, where they come back to the user as \" escape noise.
      ++ "' (see the description field of docs/llmll-ast.schema.json for what "
      ++ "each accepted version added)"
    else do
      stmtVals <- o .: "statements" :: Parser [Value]
      concat <$> mapM (flattenStatement mode) stmtVals

-- ---------------------------------------------------------------------------
-- Statement decoder
-- ---------------------------------------------------------------------------

-- | Flatten a top-level JSON-AST value into a list of statements. A @module@
-- form is spliced into its @imports@ ++ @statements@ (single-file model,
-- matching the S-expression parser's 'LLMLL.Parser.pModuleFlattened'); nested
-- modules flatten recursively. Every other kind yields exactly one statement.
-- Replaces the prior 'parseModuleDecl' stub, which discarded the module body
-- entirely (a JSON-AST / S-expression parser drift that let module-wrapped
-- submissions verify vacuously with an empty effect summary).
flattenStatement :: GrammarMode -> Value -> Parser [Statement]
flattenStatement mode = withObject "Statement" $ \o -> do
  kind <- o .: "kind" :: Parser Text
  if kind == "module"
    then do
      impVals  <- o .:? "imports"    .!= ([] :: [Value])
      stmtVals <- o .:? "statements" .!= ([] :: [Value])
      imps <- concat <$> mapM (flattenStatement mode) impVals
      body <- concat <$> mapM (flattenStatement mode) stmtVals
      pure (imps ++ body)
    else (: []) <$> parseStatement mode (Object o)

parseStatement :: GrammarMode -> Value -> Parser Statement
parseStatement mode v = do
  st <- parseStatement' mode v
  -- GENERICS-1: a type-var is scoped only by a def-shell's type_params
  -- (checked in 'parseDefShellJSON'); anywhere else it names nothing.
  case (st, typeVarNames v) of
    (SDefShell{}, _) -> pure st
    (_, n : _)       -> fail (T.unpack (unknownTypeVarMessage n))
    (_, [])          -> pure st

-- | GENERICS-1: every @{"kind":"type-var","name":n}@ under a statement, read
-- off the raw JSON, where the spelling is still visible ('parseType' reads a
-- type-var as a plain name for 'bindTypeParams').
typeVarNames :: Value -> [Text]
typeVarNames val = case val of
  Object o -> (case (KM.lookup "kind" o, KM.lookup "name" o) of
                 (Just (String "type-var"), Just (String n)) -> [n]
                 _                                           -> [])
              ++ concatMap typeVarNames (KM.elems o)
  Array a  -> concatMap typeVarNames a
  _        -> []

-- | GENERICS-1: refuse a @type_params@ key on a form other than def-shell.
refuseTypeParams :: Text -> Object -> Parser ()
refuseTypeParams form o = when (KM.member "type_params" o) $ do
  name <- o .:? "name" .!= ("(unknown)" :: Text)
  fail (T.unpack (typeParamsNotSupportedMessage form name))

parseStatement' :: GrammarMode -> Value -> Parser Statement
parseStatement' mode = withObject "Statement" $ \o -> do
  kind <- o .: "kind" :: Parser Text
  case kind of
    "def-logic" -> do
      -- v0.12.1: 'def-logic' removed under all grammar modes (no auto-rewrite,
      -- no escape valve). The GrammarLegacy arm that previously called
      -- 'parseDefLogic' is gone; both modes now reject.
      name <- o .:? "name" .!= ("(unknown)" :: Text)
      fail $ "removed-construct: 'def-logic' (function '"
             ++ T.unpack name
             ++ "') was removed in v0.12.1 and is rejected under all grammar "
             ++ "modes; use 'def' for strict-core or 'def-shell' for permissive"
    -- LT-INV (v0.11): strict-core and permissive-shell variants
    "def" ->
      case mode of
        GrammarCoreInversion -> parseDefCore o
        GrammarLegacy -> do
          name <- o .:? "name" .!= ("(unknown)" :: Text)
          fail $ "legacy-grammar-violation: 'def' (function '"
                 ++ T.unpack name
                 ++ "') is not admitted under --grammar=legacy; "
                 ++ "drop --grammar=legacy to parse v0.11 programs "
                 ++ "(def-logic, the v0.10 strict-core form, was removed in v0.12.1)"
    "def-shell" ->
      case mode of
        GrammarCoreInversion -> parseDefShellJSON o
        GrammarLegacy -> do
          name <- o .:? "name" .!= ("(unknown)" :: Text)
          fail $ "legacy-grammar-violation: 'def-shell' (function '"
                 ++ T.unpack name
                 ++ "') is not admitted under --grammar=legacy; "
                 ++ "drop --grammar=legacy to parse v0.11 programs, "
                 ++ "or use 'letrec' for the v0.10 permissive-recursive equivalent"
    "letrec"       ->
      case mode of
        GrammarCoreInversion -> do
          name <- o .:? "name" .!= ("(unknown)" :: Text)
          fail $ "core-grammar-violation: 'letrec' (function '"
                 ++ T.unpack name
                 ++ "') is not admitted under --grammar=core-inversion; "
                 ++ "use 'def-shell' for permissive recursive definitions"
        GrammarLegacy -> parseLetrec o
    "def-interface"-> parseDefInterface o
    "def-invariant"-> parseDefInvariant o
    "type-decl"    -> parseTypeDecl o
    "gen-decl"     -> parseGenDecl o
    "check"        -> parseCheckDecl o
    "import"       -> parseImportDecl o
    "module"       -> fail
      "'module' is flattened at program scope by flattenStatement and must \
      \not reach parseStatement (nested modules flatten recursively)"
    "def-main"     -> parseDefMain o
    -- v0.2 module system
    "open"         -> parseOpenDecl o
    "export"       -> parseExportDecl o
    -- v0.3 stratified verification
    "trust"        -> parseTrustDecl o
    -- v0.6 suppression governance
    "weakness-ok"  -> parseWeaknessOkDecl o
    _              -> fail $ "unknown Statement kind: " ++ T.unpack kind

-- | SRC-CONJ-1: decode one clause of a pre_clauses/post_clauses array:
-- {"expr": <Expr>, "source": <string, optional>}.
parseProvClause :: Value -> Parser ProvClause
parseProvClause = withObject "ContractClause" $ \c -> do
  e <- c .: "expr" >>= parseExpr
  s <- c .:? "source"
  pure (ProvClause e s)

-- | SRC-CONJ-1: resolve one contract side from its two admissible shapes. The
-- legacy scalar shape ("pre" + optional "pre_source") and the per-conjunct
-- array shape ("pre_clauses": [{"expr","source"?}, ...]) are mutually
-- exclusive; both present on the same side is a parse error naming the side,
-- and an empty array is a parse error (author intent is ambiguous). The array
-- derives the scalar by left and-fold in author order, matching the S-expr
-- parser's 'foldClauses'; a one-element array normalizes to the scalar shape
-- (empty ProvClause list), preserving the "list non-empty implies >= 2
-- clauses" invariant on 'Contract'.
resolveClauseSide :: String -> Maybe Expr -> Maybe Text -> Maybe [Value]
                  -> Parser (Maybe Expr, Maybe Text, [ProvClause])
resolveClauseSide _ mScalar mSrc Nothing = pure (mScalar, mSrc, [])
resolveClauseSide side mScalar mSrc (Just vs) = do
  when (mScalar /= Nothing || mSrc /= Nothing) $
    fail $ "contract-clause-shape: '" ++ side ++ "_clauses' cannot be combined with scalar '"
        ++ side ++ "'/'" ++ side ++ "_source' on the same side (use one shape)"
  cls <- mapM parseProvClause vs
  case cls of
    []                 -> fail $ "contract-clause-shape: '" ++ side
                              ++ "_clauses' must contain at least one clause"
    [ProvClause e s]   -> pure (Just e, s, [])
    _                  -> pure ( Just (foldl1 (\a b -> EApp "and" [a, b]) (map pcExpr cls))
                               , Nothing
                               , cls )

-- | SRC-CONJ-1: fetch the three fields of one contract side and resolve them.
contractSide :: Object -> Key.Key -> Key.Key -> Key.Key -> String
             -> Parser (Maybe Expr, Maybe Text, [ProvClause])
contractSide o exprK srcK clausesK side = do
  mScalar <- o .:? exprK >>= mapM parseExpr
  mSrc    <- o .:? srcK
  mArr    <- o .:? clausesK
  resolveClauseSide side mScalar mSrc mArr

-- | AST-RETURNS-KEY-1: the keys DefCore and DefShell declare in
-- docs/llmll-ast.schema.json. Both are additionalProperties: false, and a key
-- outside these lists was dropped without a message: a misspelled "post"
-- verified as SAFE with nothing proved, and "returns" left the return type
-- unchecked.
defCoreKeys, defShellKeys :: [Text]
defCoreKeys =
  [ "kind", "name", "params", "return_type"
  , "pre", "pre_source", "pre_clauses"
  , "post", "post_source", "post_clauses"
  , "spec_entropy", "body" ]
defShellKeys = defCoreKeys ++ ["decreases", "type_params"]

-- | Fail on any key outside @allowed@. For nodes the schema declares
-- additionalProperties: false (N3, AST-RETURNS-KEY-1).
rejectUnknownKeys :: String -> [Text] -> Object -> Parser ()
rejectUnknownKeys what allowed o =
  case filter (`notElem` allowed) (map Key.toText (KM.keys o)) of
    [] -> pure ()
    ks -> fail $ what ++ " has unexpected keys: "
                 ++ show (map T.unpack ks)
                 ++ " (allowed: "
                 ++ T.unpack (T.intercalate ", " (map (T.pack . show) allowed))
                 ++ ")"

-- | LT-INV (v0.11): parse {"kind":"def",...} into SDef (strict-core).
parseDefCore :: Object -> Parser Statement
parseDefCore o = do
  name     <- o .: "name"
  refuseTypeParams "def" o
  rejectUnknownKeys ("unexpected-key: def '" ++ T.unpack name ++ "'") defCoreKeys o
  params   <- o .: "params" >>= mapM parseTypedParam
  (mPre, mPreSrc, preCls)    <- contractSide o "pre" "pre_source" "pre_clauses" "pre"
  (mPost, mPostSrc, postCls) <- contractSide o "post" "post_source" "post_clauses" "post"
  mEntropy <- o .:? "spec_entropy" >>= mapM parseSpecEntropyField
  mRet     <- o .:? "return_type" >>= mapM parseType
  body     <- o .: "body"         >>= parseExpr
  pure $ SDef name params mRet (Contract mPre mPreSrc mPost mPostSrc mEntropy preCls postCls) body

-- | LT-INV (v0.11): parse {"kind":"def-shell",...} into SDefShell (permissive).
parseDefShellJSON :: Object -> Parser Statement
parseDefShellJSON o = do
  name     <- o .: "name"
  rejectUnknownKeys ("unexpected-key: def-shell '" ++ T.unpack name ++ "'") defShellKeys o
  params   <- o .: "params" >>= mapM parseTypedParam
  (mPre, mPreSrc, preCls)    <- contractSide o "pre" "pre_source" "pre_clauses" "pre"
  (mPost, mPostSrc, postCls) <- contractSide o "post" "post_source" "post_clauses" "post"
  mEntropy <- o .:? "spec_entropy" >>= mapM parseSpecEntropyField
  mRet     <- o .:? "return_type" >>= mapM parseType
  body     <- o .: "body"         >>= parseExpr
  -- REC-DESCENT (v0.14.24): optional termination-measure list (schema 0.8.0).
  -- Absent → []; Phase 1 parses + round-trips only, no obligation.
  decreases <- o .:? "decreases" >>= maybe (pure []) (mapM parseExpr)
  -- GENERICS-1 (schema 0.15.0): optional type parameters, in declared order.
  tps <- o .:? "type_params" >>= maybe (pure []) (mapM parseTypeParam)
  case filter (`notElem` map fst tps) (typeVarNames (Object o)) of
    (n : _) -> fail (T.unpack (unknownTypeVarMessage n))
    []      -> pure ()
  pure $ bindTypeParams $
    SDefShell name params mRet (Contract mPre mPreSrc mPost mPostSrc mEntropy preCls postCls) body decreases tps

-- | GENERICS-1: one @type_params@ entry, @{"name":"a"}@ or
-- @{"name":"k","constraint":"ord"}@.
parseTypeParam :: Value -> Parser (Name, Maybe TyConstraint)
parseTypeParam = withObject "TypeParam" $ \o -> do
  n  <- o .: "name"
  mc <- o .:? "constraint"
  case mc of
    Nothing -> pure (n, Nothing)
    Just c  -> case parseTyConstraint c of
      Just k  -> pure (n, Just k)
      Nothing -> fail $ "type parameter '" ++ T.unpack n ++ "': unknown constraint '"
                     ++ T.unpack c ++ "' (expected \"eq\", \"ord\" or \"key\")"

-- | LT-CDP (v0.11): decode the optional `spec_entropy` field on a JSON-AST
-- contract object. Strict — unknown labels are a parse error rather than a
-- silent default per the proposal §3 surface contract.
parseSpecEntropyField :: Value -> Parser SpecEntropy
parseSpecEntropyField = withText "SpecEntropy" $ \txt -> case parseSpecEntropy txt of
  Just se -> pure se
  Nothing -> fail $ "invalid spec_entropy: " ++ T.unpack txt
                 ++ " (expected \"strict\", \"intentional\", or \"unknown\")"

parseDefInterface :: Object -> Parser Statement
parseDefInterface o = do
  name    <- o .: "name"
  refuseTypeParams "def-interface" o
  methods <- o .: "methods" >>= mapM parseIfaceMethod
  laws    <- o .:? "laws" .!= [] >>= mapM parseLawProperty
  pure $ SDefInterface name methods laws

-- | Parse a law from JSON-AST:
-- { "kind": "for-all", "bindings": [...], "body": {...} }
-- Optional "description" field for named laws (v0.7 extension).
parseLawProperty :: Value -> Parser Property
parseLawProperty = withObject "LawProperty" $ \o -> do
  bindings <- o .: "bindings" >>= mapM parseTypedParam
  body     <- o .: "body"     >>= parseExpr
  desc     <- o .:? "description" .!= ""
  pure $ Property desc bindings body []

parseIfaceMethod :: Value -> Parser (Name, Type)
parseIfaceMethod = withObject "IfaceMethod" $ \o -> do
  name   <- o .: "name"
  fnType <- o .: "fn_type" >>= parseType
  pure (name, fnType)

parseDefInvariant :: Object -> Parser Statement
parseDefInvariant o = do
  name  <- o .: "name"
  param <- o .: "param" >>= parseTypedParam
  body  <- o .: "body"  >>= parseExpr
  -- v0.12.1: def-invariant now has its own node (SDefInvariant), so AstEmit
  -- can round-trip it faithfully instead of re-emitting it as 'def-logic'.
  pure $ SDefInvariant name [param] Nothing (Contract Nothing Nothing Nothing Nothing Nothing [] []) body

parseTypeDecl :: Object -> Parser Statement
parseTypeDecl o = do
  name <- o .: "name"
  refuseTypeParams "type" o
  body <- o .: "body" >>= parseTypeBody
  pure $ STypeDef name body

parseLetrec :: Object -> Parser Statement
parseLetrec o = do
  name     <- o .: "name"
  refuseTypeParams "letrec" o
  params   <- o .: "params" >>= mapM parseTypedParam
  (mPre, mPreSrc, preCls)    <- contractSide o "pre" "pre_source" "pre_clauses" "pre"
  (mPost, mPostSrc, postCls) <- contractSide o "post" "post_source" "post_clauses" "post"
  mEntropy <- o .:? "spec_entropy" >>= mapM parseSpecEntropyField
  dec      <- o .: "decreases" >>= parseExpr
  body     <- o .: "body"      >>= parseExpr
  pure $ SLetrec name params Nothing (Contract mPre mPreSrc mPost mPostSrc mEntropy preCls postCls) dec body

parseTypeBody :: Value -> Parser Type
parseTypeBody = withObject "TypeBody" $ \o -> do
  kind <- o .: "kind" :: Parser Text
  case kind of
    "where" -> do
      binding   <- o .: "binding" :: Parser Name
      baseType  <- o .: "base_type" >>= parseType
      predicate <- o .: "predicate" >>= parseExpr
      pure $ TDependent binding baseType predicate
    "sum" -> do
      variants <- o .: "variants" >>= mapM parseVariant
      pure $ TSumType variants
    -- AST-TYPE-ALIAS-1: any other body is a plain alias, as the S-expression
    -- pTypeBody's fallback to pType reads it and as AstEmit writes it.
    _ -> parseType (Object o)

parseVariant :: Value -> Parser (Name, Maybe Type)
parseVariant = withObject "Variant" $ \o -> do
  ctor    <- o .: "constructor"
  payload <- o .:? "payload" >>= mapM parseType
  pure (ctor, payload)

parseGenDecl :: Object -> Parser Statement
parseGenDecl o = do
  body <- o .: "body" >>= parseExpr
  pure $ SExpr body   -- mirrors how Parser.hs handles gen-decl

parseCheckDecl :: Object -> Parser Statement
parseCheckDecl o = do
  label    <- o .: "label"
  forAll   <- o .: "for_all" >>= parseForAll label
  -- OBLIG-PBT-4: optional 'subjects' field on CheckDecl. Empty or absent =
  -- no annotation; non-empty = explicit-subject opt-in (proposal §11.1).
  -- Reject empty-list-with-key per S6; dedupe per S7.
  subs0    <- o .:? "subjects" .!= ([] :: [Name])
  subjects <- case subs0 of
    [] -> case KM.lookup (Key.fromText "subjects") o of
            Just _  -> fail "(check) 'subjects' must declare ≥1 subject"
            Nothing -> pure []
    xs -> pure (dedupeNames xs)
  pure $ SCheck (forAll { propSubjects = subjects })
  where
    dedupeNames = foldr (\n acc -> if n `elem` acc then acc else n : acc) []

parseForAll :: Text -> Value -> Parser Property
parseForAll label = withObject "ForAll" $ \o -> do
  bindings <- o .: "bindings" >>= mapM parseTypedParam
  body     <- o .: "body"     >>= parseExpr
  pure $ Property label bindings body []

parseImportDecl :: Object -> Parser Statement
parseImportDecl o = do
  path   <- o .: "path"
  mIface <- o .:? "interface" >>= mapM (mapM parseIfaceMethod)
  mCap   <- o .:? "capability" >>= mapM parseCapabilitySpec
  pure $ SImport (Import path mIface mCap)

parseCapabilitySpec :: Value -> Parser Capability
parseCapabilitySpec = withObject "CapabilitySpec" $ \o -> do
  name   <- o .: "name" :: Parser Text
  target <- o .:? "path_or_port" .!= ""
  det    <- o .:? "deterministic" .!= False
  let kind = parseCapKind name
  pure $ Capability kind target det

parseCapKind :: Text -> CapabilityKind
parseCapKind "read-write"     = CapReadWrite
parseCapKind "read"           = CapRead
parseCapKind "write"          = CapWrite
parseCapKind "connect"        = CapNetConnect
parseCapKind "serve"          = CapNetServe
parseCapKind "post"           = CapHttpPost
parseCapKind "get"            = CapHttpGet
parseCapKind "monotonic-read" = CapClockMonotonic
parseCapKind "get-bytes"      = CapRandomGet
parseCapKind other            = CapCustom other

-- | Parse {"kind":"open","path":"foo.bar","names":["f","g"]}  -- v0.2
parseopenDecl :: Object -> Parser Statement
parseopenDecl o = do
  pathStr <- o .:  "path"  :: Parser Text
  mNames  <- o .:? "names" :: Parser (Maybe [Name])
  let path = T.splitOn "." pathStr
  pure $ SOpen path mNames

parseOpenDecl :: Object -> Parser Statement
parseOpenDecl = parseopenDecl

-- | Parse {"kind":"export","names":["f","g"]}  -- v0.2
parseExportDecl :: Object -> Parser Statement
parseExportDecl o = do
  names <- o .: "names" :: Parser [Name]
  pure $ SExport names

-- | Parse a trust declaration from JSON-AST.
-- { "kind": "trust", "target": "crypto.hash.pbkdf2", "level": "asserted" }
parseTrustDecl :: Object -> Parser Statement
parseTrustDecl o = do
  target <- o .: "target" :: Parser Name
  lvl    <- o .: "level"  :: Parser Text
  vl <- case lvl of
    -- TRUST-CC-1: retired. Named explicitly so the error says what happened.
    "contract-checked" ->
      fail "trust level 'contract-checked' was retired (TRUST-CC-1); \
           \a body that leaves the fragment reports 'asserted' plus a \
           \body_fallback marker on the trust report"
    -- TRUST-LEVEL-FLOOR-1: rejected, with the S-expression parser's text.
    "verified" -> fail trustVerifiedRejected
    "tested"   -> pure $ DLTested 0
    "asserted" -> pure DLAsserted
    _          -> fail $ "unknown trust level: " ++ T.unpack lvl
  pure $ STrust target vl

-- | Parse {"kind":"weakness-ok","name":"fn","reason":"..."} — v0.6.
parseWeaknessOkDecl :: Object -> Parser Statement
parseWeaknessOkDecl o = do
  name   <- o .: "name"   :: Parser Name
  reason <- o .: "reason" :: Parser Text
  when (T.null reason) $ fail "weakness-ok requires a non-empty reason string"
  pure $ SWeaknessOk name reason

parseDefMain :: Object -> Parser Statement
parseDefMain o = do
  mode    <- o .: "mode" :: Parser Text
  step    <- o .: "step"    >>= parseExpr
  mInit   <- o .:? "init"    >>= mapM parseExpr
  -- DISCARD-1 (schema 0.10.0): `read` is RETIRED. It was parsed, round-tripped,
  -- never type-checked and read by no emitter: a response-input channel that was
  -- designed and never wired. EFFECT-RESP builds the working one, and shipping a
  -- second live input channel beside a dead one is how agents learn a surface
  -- that does nothing. Measured in-tree population at retirement: zero .llmll
  -- sources and zero def-main JSON-AST documents carried it. The schema's
  -- `additionalProperties: false` now rejects the property outright.
  mDone   <- o .:? "done?"   >>= mapM parseExpr
  mOnDone <- o .:? "on-done" >>= mapM parseExpr
  -- PROC-BOUNDARY-1 (schema 0.11.0): additive-optional. Absent is exit 0 on the
  -- :done? path, which is what every pre-0.11.0 document meant, so a 0.10.0
  -- def-main reads unchanged.
  mStatus <- o .:? "status"  >>= mapM parseExpr
  -- MODE-HTTP-1 defect (i): the catch-all here was `_ -> ModeHttp 8080`, so a
  -- misspelt mode ("consoel") decoded as an http server on port 8080. An
  -- unknown mode is now a decode error that names the accepted values. A mode
  -- that is an object (the old http form) already fails at the `Parser Text`
  -- read above.
  entryMode <- case mode of
        "console" -> pure ModeConsole
        "cli"     -> pure ModeCli
        other     -> fail $ T.unpack $
          "def-main: unknown mode " <> T.pack (show other)
          <> "; the accepted values are \"console\" and \"cli\""
          <> (if "http" `T.isPrefixOf` other
                then ". No HTTP server harness exists; the server design is \
                     \tracked as HTTP-SERVE-1"
                else "")
  pure $ SDefMain entryMode mInit step mDone mOnDone mStatus

-- ---------------------------------------------------------------------------
-- Type decoder
-- ---------------------------------------------------------------------------

parseType :: Value -> Parser Type
parseType = withObject "Type" $ \o -> do
  kind <- o .: "kind" :: Parser Text
  case kind of
    "primitive" -> do
      name <- o .: "name" :: Parser Text
      case name of
        "int"    -> pure TInt
        "float"  -> pure TFloat
        "string" -> pure TString
        "bool"   -> pure TBool
        "unit"   -> pure TUnit
        _        -> fail $ "unknown primitive: " ++ T.unpack name
    "list"      -> TList <$> (o .: "elem_type" >>= parseType)
    "map"       -> TMap  <$> (o .: "key_type"  >>= parseType)
                         <*> (o .: "val_type"   >>= parseType)
    "result"    -> TResult  <$> (o .: "ok_type"  >>= parseType)
                            <*> (o .: "err_type"  >>= parseType)
    "promise"   -> TPromise <$> (o .: "inner_type" >>= parseType)
    -- BYTES-LEN-RANGE-1: read the exact number. aeson's Int decoder accepted
    -- -1 and refused 2^63 with a generic decode error; the length must be an
    -- integer in [0, 2^63 - 1], refused with kind bytes-length-range.
    "bytes"     -> do
      -- toBoundedInteger, not floatingOrInteger: it refuses a huge exponent
      -- without materialising the Integer.
      n <- o .: "length" :: Parser Scientific
      -- Integral once past the first guard; spell it in full unless the
      -- exponent is large, where the Scientific form is shorter and building
      -- the digits would be the cost toBoundedInteger avoided.
      let spelled
            | Sci.base10Exponent n <= 40 = show (truncate n :: Integer)
            | otherwise                  = show n
      if not (Sci.isInteger n)
        then fail ("bytes-length-range: bytes length " ++ show n ++ " is not an integer")
        else case Sci.toBoundedInteger n :: Maybe Int of
          Just i | bytesLengthInRange (toInteger i) -> pure (TBytes i)
          _ -> fail (T.unpack (bytesLengthRangeMessage (T.pack spelled)))
    "fn-type"   -> do
      params <- o .: "params" >>= mapM (fmap snd . parseTypedParam)
      ret    <- o .: "return_type" >>= parseType
      pure $ TFn params ret
    "where"     -> do
      binding   <- o .: "binding" :: Parser Name
      baseType  <- o .: "base_type" >>= parseType
      predicate <- o .: "predicate" >>= parseExpr
      pure $ TDependent binding baseType predicate
    -- PR 2 fix: pair-type now correctly produces TPair (was TResult — unsound)
    "pair-type" -> do
      fst_ <- o .: "fst" >>= parseType
      snd_ <- o .: "snd" >>= parseType
      pure $ TPair fst_ snd_
    "command"   -> pure $ TCustom "Command"
    -- FFI-CONV-1 (D10): boundary types; the checker refuses them outside a
    -- haskell.* interface entry (E20).
    "hs-text"   -> pure $ TCustom "hs-text"
    "hs-int"    -> pure $ TCustom "hs-int"
    "hs-maybe"  -> (\t -> TResult t (TCustom "hs-maybe")) <$> (o .: "inner" >>= parseType)
    "named"     -> do
      n <- o .: "name" :: Parser Text
      pure $ resolveNamedType n
    -- GENERICS-1 (schema 0.15.0): a type parameter, read as a plain name so
    -- 'bindTypeParams' binds it exactly as the S-expression front end's
    -- lowercase name; an undeclared one is refused by 'typeVarNames'.
    "type-var"  -> TCustom <$> (o .: "name" :: Parser Text)
    _           -> fail $ "unknown Type kind: " ++ T.unpack kind

-- | Resolve well-known type names to their built-in constructors.
-- Anything not in this list stays as TCustom.
-- If a new built-in type constructor is added to the Type ADT with a
-- typeLabel that could collide with TCustom, extend this function.
resolveNamedType :: Text -> Type
resolveNamedType "DelegationError" = TDelegationError
resolveNamedType n                 = TCustom n

-- ---------------------------------------------------------------------------
-- TypedParam decoder
-- ---------------------------------------------------------------------------

parseTypedParam :: Value -> Parser (Name, Type)
parseTypedParam = withObject "TypedParam" $ \o -> do
  name    <- o .: "name"
  untyped <- o .:? "untyped" .!= False
  if untyped
    then pure (name, TCustom "_")
    else do
      mType <- o .:? "param_type"
      case mType of
        Nothing -> pure (name, TCustom "_")
        Just tv -> do
          ty <- parseType tv
          pure (name, ty)

-- ---------------------------------------------------------------------------
-- Expression decoder
-- ---------------------------------------------------------------------------

parseExpr :: Value -> Parser Expr
parseExpr = withObject "Expr" $ \o -> do
  kind <- o .: "kind" :: Parser Text
  case kind of
    "lit-int"    -> do
      n <- o .: "value" :: Parser Int
      pure $ ELit (LitInt (fromIntegral n))
    -- FLOAT-LIT-1: read the exact number and apply the shared range rule.
    -- R1-3: the node kind, not the spelling, makes a float, so 2 is 2.0.
    "lit-float"  -> ELit <$> (o .: "value" >>= jsonFloatLit)
    "lit-string" -> ELit . LitString <$> o .: "value"
    "lit-bool"   -> ELit . LitBool   <$> o .: "value"
    "lit-unit"   -> pure (ELit LitUnit)

    -- List literal: desugar [a, b, c] -> (list-prepend a (list-prepend b (list-prepend c (list-empty))))
    "lit-list" -> do
      items <- (o .: "items" :: Parser [Value]) >>= mapM parseExpr
      pure $ foldr (\item acc -> EApp "list-prepend" [item, acc])
                   (EApp "list-empty" [])
                   items

    "var"        -> EVar             <$> o .: "name"

    "let" -> do
      bindings <- o .: "bindings" >>= mapM parseLet1Binding
      body     <- o .: "body"     >>= parseExpr
      pure $ ELet bindings body

    "if" -> EIf
      <$> (o .: "cond"        >>= parseExpr)
      <*> (o .: "then_branch" >>= parseExpr)
      <*> (o .: "else_branch" >>= parseExpr)

    "match" -> do
      scrut <- o .: "scrutinee" >>= parseExpr
      arms  <- o .: "arms"      >>= mapM parseMatchArm
      pure $ EMatch scrut arms

    "app" -> do
      fn   <- o .: "fn"
      args <- o .: "args" >>= mapM parseExpr
      pure $ EApp fn args

    "qual-app" -> do
      fn   <- o .: "qual_fn"
      args <- o .: "args" >>= mapM parseExpr
      pure $ EApp fn args  -- qualified apps stored as EApp with dotted name

    "op" -> do
      op   <- o .: "op"
      args <- o .: "args" >>= mapM parseExpr
      pure $ EOp op args

    "pair" -> EPair
      <$> (o .: "fst" >>= parseExpr)
      <*> (o .: "snd" >>= parseExpr)

    "lambda" -> do
      params <- o .: "params" >>= mapM parseTypedParam
      body   <- o .: "body"   >>= parseExpr
      pure $ ELambda params body

    "await" -> EAwait <$> (o .: "expr" >>= parseExpr)

    "do" -> do
      steps <- o .: "steps" >>= mapM parseDoStep
      pure $ EDo steps

    "hole-named"          -> EHole . HNamed        <$> o .: "name"
    "hole-choose"         -> EHole . HChoose        <$> o .: "options"
    "hole-request-cap"    -> EHole . HRequestCap    <$> o .: "cap_path"
    "hole-scaffold"       -> EHole . HScaffold      <$> parseScaffoldSpec o
    "hole-delegate"       -> EHole . HDelegate      <$> parseDelegateSpec o
    "hole-delegate-async" -> do
      raw <- parseDelegateSpec o
      case delegateOnFailure raw of
        Just _ -> fail "on_failure is not supported on hole-delegate-async; use a sync ?delegate with on-failure, or handle errors after (await ...)"
        Nothing -> pure ()
      case normalizeAsyncDelegateSpec raw of
        Left err -> fail (T.unpack err)
        Right spec -> pure $ EHole (HDelegateAsync spec)
    -- D3: ?proof-required hole; LT-PPR (v0.11): optional predicate field
    "hole-proof-required" -> do
      reason <- o .:? "reason" .!= "manual"
      mPred  <- o .:? "predicate" >>= mapM parseExpr
      pure $ EHole (HProofRequired reason mPred)

    _ -> fail $ "unknown Expr kind: " ++ T.unpack kind

parseLet1Binding :: Value -> Parser (Pattern, Maybe Type, Expr)
parseLet1Binding = withObject "LetBinding" $ \o -> do
  -- N3: reject unexpected keys — schema declares additionalProperties: false
  rejectUnknownKeys "let binding" ["name", "pattern", "expr"] o
  -- PR 4: "name" → PVar (ergonomic shorthand); "pattern" → full pattern
  pat <- do
    mName <- o .:? "name" :: Parser (Maybe Name)
    case mName of
      Just n  -> pure (PVar n)
      Nothing -> o .: "pattern" >>= parsePattern
  expr <- o .: "expr" >>= parseExpr
  pure (pat, Nothing, expr)

parseMatchArm :: Value -> Parser (Pattern, Expr)
parseMatchArm = withObject "MatchArm" $ \o -> do
  pat  <- o .: "pattern" >>= parsePattern
  body <- o .: "body"    >>= parseExpr
  pure (pat, body)

parsePattern :: Value -> Parser Pattern
parsePattern = withObject "Pattern" $ \o -> do
  kind <- o .: "kind" :: Parser Text
  case kind of
    "wildcard"    -> pure PWildcard
    "bind"        -> PVar <$> o .: "name"
    "literal"     -> PLiteral <$> parseLiteralValue o
    "constructor" -> do
      ctor <- o .: "constructor"
      subs <- o .:? "sub_patterns" .!= []
      PConstructor ctor <$> mapM parsePattern subs
    _ -> fail $ "unknown Pattern kind: " ++ T.unpack kind

-- | A literal pattern's value. FLOAT-LIT-1 (Rev 1, R1-2): aeson cannot tell
-- 2 from 2.0, so a float pattern carries @"literal_kind": "float"@.
--
--   * key absent: an integral number is an int, any other number a float;
--   * @"float"@: the number is a float (2 reads as 2.0);
--   * @"int"@: the number must be integral, otherwise a parse error;
--   * the key next to a string or boolean value is a parse error.
parseLiteralValue :: Object -> Parser Literal
parseLiteralValue o = do
  v  <- o .: "value"
  lk <- o .:? "literal_kind" :: Parser (Maybe Text)
  case (v, lk) of
    (Number n, Nothing)
      | Sci.isInteger n -> pure (jsonIntPattern n)
      | otherwise       -> jsonFloatLit n
    (Number n, Just "float") -> jsonFloatLit n
    (Number n, Just "int")
      | Sci.isInteger n -> pure (jsonIntPattern n)
      | otherwise       -> fail $ "literal-kind-mismatch: \"literal_kind\": \"int\" on the non-integral number "
                                  ++ show n
    (Number _, Just other) -> fail $ "literal-kind-mismatch: \"literal_kind\" must be \"int\" or \"float\", got "
                                     ++ show other
    (String _, Just _) -> fail "literal-kind-mismatch: \"literal_kind\" applies to a number; this pattern's value is a string"
    (Bool _,   Just _) -> fail "literal-kind-mismatch: \"literal_kind\" applies to a number; this pattern's value is a boolean"
    (String s, Nothing) -> pure (LitString s)
    (Bool b,   Nothing) -> pure (LitBool b)
    _          -> fail "literal value must be number, string, or bool"

-- | An integral pattern number. Exact through Int64 (read from the Scientific,
-- not through Double); beyond that the earlier Double reading is kept, because
-- the unbounded-int reading is JSON-INT-UNBOUNDED-1, a separate row.
jsonIntPattern :: Scientific -> Literal
jsonIntPattern n = case Sci.toBoundedInteger n :: Maybe Int64 of
  Just i  -> LitInt (toInteger i)
  Nothing -> LitInt (round (Sci.toRealFloat n :: Double))

-- | FLOAT-LIT-1: a JSON number as a float literal, under the range rule both
-- front ends share ('LLMLL.FloatLit.classifyFloatLit'). The spelling in the
-- message is the number as aeson read it.
jsonFloatLit :: Scientific -> Parser Literal
jsonFloatLit n =
  let c = Sci.coefficient n
  in case classifyFloatLit (c < 0) (abs c) (toInteger (Sci.base10Exponent n)) of
       Right d  -> pure (LitFloat d)
       Left why -> fail (T.unpack (floatLitRangeMessage (T.pack (show n)) why))

-- | FLOAT-LIT-1 (D7): the first number token in the raw JSON text whose
-- exponent has more than 18 digits, if any. Such an exponent does not fit a
-- 64-bit Int, and aeson wraps it silently. String contents (with their
-- escapes) are skipped, so a string that merely looks like a number is not a
-- number token. Linear in the input.
oversizedExponent :: BL.ByteString -> Maybe Text
oversizedExponent = go . BL8.unpack
  where
    go [] = Nothing
    go ('"' : rest) = go (skipString rest)
    go s@(c : rest)
      | c == '-' || isDigit c =
          let (tok, after) = span numChar s
          in if tooLong tok then Just (T.pack tok) else go after
      | otherwise = go rest
    skipString ('\\' : _ : rest) = skipString rest
    skipString ('"' : rest)        = rest
    skipString (_ : rest)          = skipString rest
    skipString []                  = []
    numChar ch = isDigit ch || ch `elem` ("+-.eE" :: String)
    tooLong tok = case break (`elem` ("eE" :: String)) tok of
      (_, _ : ex) -> length (dropWhile (`elem` ("+-" :: String)) ex) > 18
      _           -> False

-- PR 2: unified DoStep. Only "do-step" is accepted.
-- "bind-step"/"expr-step" are rejected: do-notation never shipped in a stable
-- release, so there is nothing to be backward-compatible with.
parseDoStep :: Value -> Parser DoStep
parseDoStep = withObject "DoStep" $ \o -> do
  kind <- o .: "kind" :: Parser Text
  case kind of
    "do-step"   -> do
      expr  <- o .: "expr" >>= parseExpr
      mName <- o .:? "name" :: Parser (Maybe Name)
      -- DISCARD-1 (schema 0.10.0): optional, defaulting to False. Absent and
      -- false must stay indistinguishable on the way in, because AstEmit omits
      -- the field when False on the way out.
      dsc   <- o .:? "discard" .!= False
      pure $ DoStep mName expr dsc
    "bind-step" -> fail "use {\"kind\":\"do-step\",\"name\":\"x\",\"expr\":...} instead of \"bind-step\" (schema v0.3)"
    "expr-step" -> fail "use {\"kind\":\"do-step\",\"expr\":...} instead of \"expr-step\" (schema v0.3)"
    _ -> fail $ "unknown DoStep kind: " ++ T.unpack kind

parseScaffoldSpec :: Object -> Parser ScaffoldSpec
parseScaffoldSpec o = do
  template <- o .: "template"
  pure $ ScaffoldSpec template Nothing [] Nothing Nothing

parseDelegateSpec :: Object -> Parser DelegateSpec
parseDelegateSpec o = do
  agent  <- o .: "agent"
  desc   <- o .: "description"
  retTy  <- o .: "return_type" >>= parseType
  onFail <- o .:? "on_failure" >>= mapM parseExpr
  pure $ DelegateSpec agent desc retTy onFail
