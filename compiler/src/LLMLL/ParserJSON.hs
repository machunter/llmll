{-# LANGUAGE OverloadedStrings #-}
-- |
-- Module      : LLMLL.ParserJSON
-- Description : Parse a JSON-AST (.ast.json) file into the same [Statement] AST
--               that Parser.hs produces from S-expression source.
--
-- The two parsers MUST agree on every construct. Any divergence is a bug.
--
-- JSON schema: docs/llmll-ast.schema.json
-- Versioning policy: docs/json-ast-versioning.md
module LLMLL.ParserJSON
  ( parseJSONAST
  , parseJSONASTValue
  , expectedSchemaVersion
  ) where

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

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

-- | The schema version this parser accepts. Compiler rejects any other value.
-- v0.10.2: bumped from 0.3.0 to 0.4.0 to signal identifier-shape regex
-- constraints on ExprApp.fn and ExprQualApp.qual_fn.
expectedSchemaVersion :: Text
expectedSchemaVersion = "0.6.0"

-- | Parse a JSON-AST byte string into a list of top-level statements.
-- Returns @Left Diagnostic@ on any structural or version error.
parseJSONAST :: GrammarMode -> FilePath -> BL.ByteString -> Either Diagnostic [Statement]
parseJSONAST mode fp bs =
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
                       , diagSuggestion = if k == "core-grammar-violation"
                                            then Just "Replace {\"kind\":\"def-logic\",...} with {\"kind\":\"def\",...} (strict-core) or {\"kind\":\"def-shell\",...} (permissive); replace {\"kind\":\"letrec\",...} with {\"kind\":\"def-shell\",...}"
                                            else Nothing
                       }
          in Left diag
        Right stmts -> Right stmts
  where
    extractKind msg
      | "schema-version-mismatch" `T.isInfixOf` msg = "schema-version-mismatch"
      | "core-grammar-violation"  `T.isInfixOf` msg = "core-grammar-violation"
      | otherwise = "json-decode-error"

-- | Parse a JSON Value (already decoded) into statements.
-- Returns multi-error diagnostics for agent round-trip efficiency.
-- Always uses GrammarLegacy: patch-apply callers have no grammar-mode context.
-- TODO: thread GrammarMode through llmll-patch once a per-file mode is tracked.
parseJSONASTValue :: Value -> Either [Diagnostic] [Statement]
parseJSONASTValue val =
  case parseEither (parseProgram GrammarLegacy "<patch>") val of
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
  if sv /= expectedSchemaVersion
    then fail $
      "schema-version-mismatch: expected '"
      ++ T.unpack expectedSchemaVersion
      ++ "', got '"
      ++ T.unpack sv
      ++ "' (see docs/json-ast-versioning.md)"
    else do
      stmtVals <- o .: "statements" :: Parser [Value]
      mapM (parseStatement mode) stmtVals

-- ---------------------------------------------------------------------------
-- Statement decoder
-- ---------------------------------------------------------------------------

parseStatement :: GrammarMode -> Value -> Parser Statement
parseStatement mode = withObject "Statement" $ \o -> do
  kind <- o .: "kind" :: Parser Text
  case kind of
    "def-logic" ->
      case mode of
        GrammarCoreInversion -> do
          name <- o .:? "name" .!= ("(unknown)" :: Text)
          fail $ "core-grammar-violation: 'def-logic' (function '"
                 ++ T.unpack name
                 ++ "') is not admitted under --grammar=core-inversion; "
                 ++ "use 'def' for strict-core or 'def-shell' for permissive"
        GrammarLegacy -> parseDefLogic o
    -- LT-INV (v0.11): strict-core and permissive-shell variants
    "def"          -> parseDefCore o
    "def-shell"    -> parseDefShellJSON o
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
    "module"       -> parseModuleDecl o
    "def-main"     -> parseDefMain o
    -- v0.2 module system
    "open"         -> parseOpenDecl o
    "export"       -> parseExportDecl o
    -- v0.3 stratified verification
    "trust"        -> parseTrustDecl o
    -- v0.6 suppression governance
    "weakness-ok"  -> parseWeaknessOkDecl o
    _              -> fail $ "unknown Statement kind: " ++ T.unpack kind

parseDefLogic :: Object -> Parser Statement
parseDefLogic o = do
  name   <- o .: "name"
  params <- o .: "params" >>= mapM parseTypedParam
  mPre   <- o .:? "pre"   >>= mapM parseExpr
  mPreSrc <- o .:? "pre_source"
  mPost  <- o .:? "post"  >>= mapM parseExpr
  mPostSrc <- o .:? "post_source"
  mEntropy <- o .:? "spec_entropy" >>= mapM parseSpecEntropyField
  body   <- o .: "body"   >>= parseExpr
  pure $ SDefLogic name params Nothing (Contract mPre mPreSrc mPost mPostSrc mEntropy) body

-- | LT-INV (v0.11): parse {"kind":"def",...} into SDef (strict-core).
parseDefCore :: Object -> Parser Statement
parseDefCore o = do
  name     <- o .: "name"
  params   <- o .: "params" >>= mapM parseTypedParam
  mPre     <- o .:? "pre"         >>= mapM parseExpr
  mPreSrc  <- o .:? "pre_source"
  mPost    <- o .:? "post"        >>= mapM parseExpr
  mPostSrc <- o .:? "post_source"
  mEntropy <- o .:? "spec_entropy" >>= mapM parseSpecEntropyField
  body     <- o .: "body"         >>= parseExpr
  pure $ SDef name params Nothing (Contract mPre mPreSrc mPost mPostSrc mEntropy) body

-- | LT-INV (v0.11): parse {"kind":"def-shell",...} into SDefShell (permissive).
parseDefShellJSON :: Object -> Parser Statement
parseDefShellJSON o = do
  name     <- o .: "name"
  params   <- o .: "params" >>= mapM parseTypedParam
  mPre     <- o .:? "pre"         >>= mapM parseExpr
  mPreSrc  <- o .:? "pre_source"
  mPost    <- o .:? "post"        >>= mapM parseExpr
  mPostSrc <- o .:? "post_source"
  mEntropy <- o .:? "spec_entropy" >>= mapM parseSpecEntropyField
  body     <- o .: "body"         >>= parseExpr
  pure $ SDefShell name params Nothing (Contract mPre mPreSrc mPost mPostSrc mEntropy) body

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
  -- def-invariant stored as SDefLogic (full node deferred to v0.2)
  pure $ SDefLogic name [param] Nothing (Contract Nothing Nothing Nothing Nothing Nothing) body

parseTypeDecl :: Object -> Parser Statement
parseTypeDecl o = do
  name <- o .: "name"
  body <- o .: "body" >>= parseTypeBody
  pure $ STypeDef name body

parseLetrec :: Object -> Parser Statement
parseLetrec o = do
  name     <- o .: "name"
  params   <- o .: "params" >>= mapM parseTypedParam
  mPre     <- o .:? "pre"      >>= mapM parseExpr
  mPreSrc  <- o .:? "pre_source"
  mPost    <- o .:? "post"     >>= mapM parseExpr
  mPostSrc <- o .:? "post_source"
  mEntropy <- o .:? "spec_entropy" >>= mapM parseSpecEntropyField
  dec      <- o .: "decreases" >>= parseExpr
  body     <- o .: "body"      >>= parseExpr
  pure $ SLetrec name params Nothing (Contract mPre mPreSrc mPost mPostSrc mEntropy) dec body

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
    _ -> fail $ "unknown TypeBody kind: " ++ T.unpack kind

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

parseModuleDecl :: Object -> Parser Statement
parseModuleDecl o = do
  -- v0.1.2 single-file model: flatten module into its body.
  _imports <- o .: "imports"    :: Parser [Value]
  _stmts   <- o .: "statements" :: Parser [Value]
  pure $ SExpr (ELit LitUnit)

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
    "contract-checked" -> pure $ DLContractChecked ""
    "verified"  -> pure $ DLVerified ""
    "tested"   -> pure $ DLTested 0
    "asserted" -> pure DLAsserted
    _          -> fail $ "unknown trust level: " ++ T.unpack lvl
  pure $ STrust target vl

-- | Parse {"kind":"weakness-ok","name":"fn","reason":"..."} — v0.6.
parseWeaknessOkDecl :: Object -> Parser Statement
parseWeaknessOkDecl o = do
  name   <- o .: "name"   :: Parser Name
  reason <- o .: "reason" :: Parser Text
  pure $ SWeaknessOk name reason

parseDefMain :: Object -> Parser Statement
parseDefMain o = do
  mode    <- o .: "mode" :: Parser Text
  step    <- o .: "step"    >>= parseExpr
  mInit   <- o .:? "init"    >>= mapM parseExpr
  mRead   <- o .:? "read"    >>= mapM parseExpr
  mDone   <- o .:? "done?"   >>= mapM parseExpr
  mOnDone <- o .:? "on-done" >>= mapM parseExpr
  let entryMode = case mode of
        "console" -> ModeConsole
        "cli"     -> ModeCli
        _         -> ModeHttp 8080
  pure $ SDefMain entryMode mInit step mRead mDone mOnDone

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
    "bytes"     -> TBytes   <$> o .: "length"
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
    "named"     -> do
      n <- o .: "name" :: Parser Text
      pure $ resolveNamedType n
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
    "lit-float"  -> ELit . LitFloat  <$> (o .: "value" :: Parser Double)
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
  let allowedKeys = ["name", "pattern", "expr"]
      allKeys     = map (Key.toText . fst) (KM.toList o)
      extraKeys   = filter (`notElem` allowedKeys) allKeys
  case extraKeys of
    [] -> pure ()
    ks -> fail $ "let binding has unexpected keys: "
                 ++ show (map T.unpack ks)
                 ++ " (allowed: \"name\", \"pattern\", \"expr\")"
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

parseLiteralValue :: Object -> Parser Literal
parseLiteralValue o = do
  v <- o .: "value"
  case v of
    Number n   ->
      let d = realToFrac n :: Double
          i = round d :: Integer
      in if fromIntegral i == d
           then pure (LitInt i)
           else pure (LitFloat d)
    String s   -> pure (LitString s)
    Bool b     -> pure (LitBool b)
    _          -> fail "literal value must be number, string, or bool"

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
      pure $ DoStep mName expr
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
