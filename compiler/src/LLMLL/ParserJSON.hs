{-# LANGUAGE OverloadedStrings #-}
-- |
-- Module      : LLMLL.ParserJSON
-- Description : Parse a JSON-AST (.ast.json) file into the same [Statement] AST
--               that Parser.hs produces from S-expression source.
--
-- The two parsers MUST agree on every construct. Any divergence is a bug.
--
-- JSON schema: docs/llmll-ast.schema.json (v0.1.2)
-- Versioning policy: docs/json-ast-versioning.md
module LLMLL.ParserJSON
  ( parseJSONAST
  , expectedSchemaVersion
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.ByteString.Lazy as BL
import Data.Aeson
  ( Value(..), Object
  , eitherDecode
  , withObject )
import Data.Aeson.Types
  ( Parser, parseEither
  , (.:), (.:?), (.!=) )

import LLMLL.Syntax
import LLMLL.Diagnostic (Diagnostic(..), mkError)

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

-- | The schema version this parser accepts. Compiler rejects any other value.
expectedSchemaVersion :: Text
expectedSchemaVersion = "0.1.2"

-- | Parse a JSON-AST byte string into a list of top-level statements.
-- Returns @Left Diagnostic@ on any structural or version error.
parseJSONAST :: FilePath -> BL.ByteString -> Either Diagnostic [Statement]
parseJSONAST fp bs =
  case eitherDecode bs of
    Left err ->
      Left $ (mkError Nothing (T.pack err))
        { diagKind    = Just "json-parse-error"
        , diagPointer = Just "/"
        , diagCode    = Just "E010"
        }
    Right val ->
      case parseEither (parseProgram fp) val of
        Left msg -> Left $ (mkError Nothing (T.pack msg))
          { diagKind = Just (extractKind (T.pack msg))
          , diagCode = Just "E011"
          }
        Right stmts -> Right stmts
  where
    extractKind msg
      | "schema-version-mismatch" `T.isInfixOf` msg = "schema-version-mismatch"
      | otherwise = "json-decode-error"

-- ---------------------------------------------------------------------------
-- Program-level decoder
-- ---------------------------------------------------------------------------

parseProgram :: FilePath -> Value -> Parser [Statement]
parseProgram _fp = withObject "Program" $ \o -> do
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
      mapM parseStatement stmtVals

-- ---------------------------------------------------------------------------
-- Statement decoder
-- ---------------------------------------------------------------------------

parseStatement :: Value -> Parser Statement
parseStatement = withObject "Statement" $ \o -> do
  kind <- o .: "kind" :: Parser Text
  case kind of
    "def-logic"    -> parseDefLogic o
    "def-interface"-> parseDefInterface o
    "def-invariant"-> parseDefInvariant o
    "type-decl"    -> parseTypeDecl o
    "gen-decl"     -> parseGenDecl o
    "check"        -> parseCheckDecl o
    "import"       -> parseImportDecl o
    "module"       -> parseModuleDecl o
    "def-main"     -> parseDefMain o
    _              -> fail $ "unknown Statement kind: " ++ T.unpack kind

parseDefLogic :: Object -> Parser Statement
parseDefLogic o = do
  name   <- o .: "name"
  params <- o .: "params" >>= mapM parseTypedParam
  mPre   <- o .:? "pre"   >>= mapM parseExpr
  mPost  <- o .:? "post"  >>= mapM parseExpr
  body   <- o .: "body"   >>= parseExpr
  pure $ SDefLogic name params Nothing (Contract mPre mPost) body

parseDefInterface :: Object -> Parser Statement
parseDefInterface o = do
  name    <- o .: "name"
  methods <- o .: "methods" >>= mapM parseIfaceMethod
  pure $ SDefInterface name methods

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
  pure $ SDefLogic name [param] Nothing (Contract Nothing Nothing) body

parseTypeDecl :: Object -> Parser Statement
parseTypeDecl o = do
  name <- o .: "name"
  body <- o .: "body" >>= parseTypeBody
  pure $ STypeDef name body

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
      -- Encode variant payloads as "CtorName:TypeName | CtorName2" for emitTypeDef.
      let encodeVar (ctor, Nothing)  = ctor
          encodeVar (ctor, Just pt)  = ctor <> ":" <> typeLabel pt
          label = T.intercalate " | " (map encodeVar variants)
      pure $ TCustom label
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
  label  <- o .: "label"
  forAll <- o .: "for_all" >>= parseForAll label
  pure $ SCheck forAll

parseForAll :: Text -> Value -> Parser Property
parseForAll label = withObject "ForAll" $ \o -> do
  bindings <- o .: "bindings" >>= mapM parseTypedParam
  body     <- o .: "body"     >>= parseExpr
  pure $ Property label bindings body

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
  -- We represent flattened modules as a single SExpr sentinel,
  -- since parseStatement returns one Statement. The caller (parseProgram)
  -- could collect imports+stmts; for now we return a no-op SExpr.
  _imports <- o .: "imports"    :: Parser [Value]
  _stmts   <- o .: "statements" :: Parser [Value]
  pure $ SExpr (ELit LitUnit)

parseDefMain :: Object -> Parser Statement
parseDefMain o = do
  mode    <- o .: "mode" :: Parser Text
  step    <- o .: "step"    >>= parseExpr
  mInit   <- o .:? "init"    >>= mapM parseExpr
  mRead   <- o .:? "read"    >>= mapM parseExpr
  mDone   <- o .:? "done"    >>= mapM parseExpr
  mOnDone <- o .:? "on_done" >>= mapM parseExpr
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
    "pair-type" -> do
      fst_ <- o .: "fst" >>= parseType
      snd_ <- o .: "snd" >>= parseType
      pure $ TCustom ("(" <> typeLabel fst_ <> ", " <> typeLabel snd_ <> ")")
    "command"   -> pure $ TCustom "Command"
    "named"     -> TCustom <$> o .: "name"
    _           -> fail $ "unknown Type kind: " ++ T.unpack kind

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
    "hole-delegate-async" -> EHole . HDelegateAsync <$> parseDelegateSpec o

    _ -> fail $ "unknown Expr kind: " ++ T.unpack kind

parseLet1Binding :: Value -> Parser (Name, Maybe Type, Expr)
parseLet1Binding = withObject "LetBinding" $ \o -> do
  name <- o .: "name"
  expr <- o .: "expr" >>= parseExpr
  pure (name, Nothing, expr)

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

parseDoStep :: Value -> Parser DoStep
parseDoStep = withObject "DoStep" $ \o -> do
  kind <- o .: "kind" :: Parser Text
  case kind of
    "bind-step" -> DoBind <$> o .: "name" <*> (o .: "expr" >>= parseExpr)
    "expr-step" -> DoExpr <$> (o .: "expr" >>= parseExpr)
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
