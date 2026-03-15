{-# LANGUAGE StrictData #-}
-- |
-- Module      : LLMLL.Parser
-- Description : Parse LLMLL S-expressions into the AST.
--
-- Takes raw source text (not pre-tokenized) and parses directly into
-- the AST types defined in "LLMLL.Syntax". Uses Megaparsec for
-- error reporting with source spans.
module LLMLL.Parser
  ( parseModule
  , parseStatements
  , parseTopLevel
  , parseExpr
  , ParseError
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import Data.Void (Void)
import Text.Megaparsec hiding (ParseError)
import Text.Megaparsec.Char
import qualified Text.Megaparsec.Char.Lexer as L

import LLMLL.Syntax

type Parser = Parsec Void Text
type ParseError = ParseErrorBundle Text Void

-- ---------------------------------------------------------------------------
-- Whitespace & Helpers
-- ---------------------------------------------------------------------------

-- | Skip whitespace and ;; comments.
sc :: Parser ()
sc = L.space space1 (L.skipLineComment ";;") empty

-- | Lexeme: parse then skip trailing whitespace.
lexeme' :: Parser a -> Parser a
lexeme' = L.lexeme sc

-- | Symbol: parse a specific string then skip whitespace.
symbol :: Text -> Parser Text
symbol = L.symbol sc

-- | Parse the ARROW token: ASCII @->@ or Unicode @\x2192@ (U+2192).
-- Both map to the same AST position; canonical output uses @->@.
pArrowSym :: Parser ()
pArrowSym = sc *> (() <$ choice [string "->", string "\x2192"]) <* sc

-- | Parse something wrapped in parentheses.
parens :: Parser a -> Parser a
parens = between (symbol "(") (symbol ")")

-- | Parse something wrapped in brackets.
brackets :: Parser a -> Parser a
brackets = between (symbol "[") (symbol "]")

-- ---------------------------------------------------------------------------
-- Top-Level Entry Points
-- ---------------------------------------------------------------------------

-- | Parse a complete LLMLL module.
parseModule :: FilePath -> Text -> Either ParseError Module
parseModule fp = parse (sc *> pModule <* eof) fp

-- | Parse a list of top-level statements (for files without a module wrapper).
parseStatements :: FilePath -> Text -> Either ParseError [Statement]
parseStatements fp = parse (sc *> many pStatement <* eof) fp

-- | Unified top-level parser: accepts both bare statements and files that
-- begin with an optional @(module Name imports body)@ wrapper (single-file
-- model, v0.1.1 limitation — see LLMLL.md §8).
--
-- When a @(module ...)@ form is detected the module name is discarded and
-- its body statements are returned as flat top-level statements.  Multiple
-- @(module ...)@ forms in one file are also allowed (rare but harmless) —
-- all their bodies are concatenated.
--
-- @(import ...)@ at top level (inside or outside a module block) is parsed
-- as an 'SImport' node; capability enforcement is deferred to v0.2.
parseTopLevel :: FilePath -> Text -> Either ParseError [Statement]
parseTopLevel fp = parse (sc *> (concat <$> many pTopLevelItem) <* eof) fp

-- | Parse a single expression (for testing/REPL).
parseExpr :: FilePath -> Text -> Either ParseError Expr
parseExpr fp = parse (sc *> pExpr <* eof) fp

-- ---------------------------------------------------------------------------
-- Top-Level Items (unified: statements + optional module wrappers)
-- ---------------------------------------------------------------------------

-- | One top-level item expands to zero or more statements.
-- A @(module Name imports body)@ form is flattened into its imports + body.
-- Any other form is a single statement.
pTopLevelItem :: Parser [Statement]
pTopLevelItem = try pModuleFlattened <|> (pure <$> pStatement)

-- | Parse @(module Name [imports...] [statements...])@ and return
-- its contents as a flat list of statements.  The module name is
-- ignored (single-file model).  Imports become 'SImport' nodes.
pModuleFlattened :: Parser [Statement]
pModuleFlattened = parens $ do
  _ <- symbol "module"
  _ <- pIdent          -- module name: recorded but not used in single-file model
  imports <- many (try pImportStmt)
  body    <- many pStatement
  pure (imports ++ body)

-- ---------------------------------------------------------------------------
-- Module (full module form, used by parseModule)
-- ---------------------------------------------------------------------------

pModule :: Parser Module
pModule = parens $ do
  _ <- symbol "module"
  name <- pIdent
  imports <- many (try pImportStmt)
  body <- many pStatement
  pure $ Module name (map extractImport imports) body
  where
    extractImport (SImport i) = i
    extractImport _           = error "impossible: non-import in import position"

-- ---------------------------------------------------------------------------
-- Statements
-- ---------------------------------------------------------------------------

pStatement :: Parser Statement
pStatement = choice
  [ try pDefLogic
  , try pDefInterface
  , try pTypeDef
  , try pCheckBlock
  , try pGenDecl
  , try pImportStmt
  , SExpr <$> pExpr
  ]

-- | Parse (def-logic name [params] (pre ...) (post ...) body)
pDefLogic :: Parser Statement
pDefLogic = parens $ do
  _ <- symbol "def-logic"
  name <- pIdent
  params <- brackets (many pDefParam)
  mPre  <- optional (try pPreClause)
  mPost <- optional (try pPostClause)
  body <- pExpr
  pure $ SDefLogic name params Nothing (Contract mPre mPost) body

-- | A def-logic param is either a typed binding (name: type) or a bare name.
-- Bare names are given a wildcard type to unblock parsing; type inference is v0.2.
pDefParam :: Parser (Name, Type)
pDefParam = try pTypedParam <|> do
  n <- pIdent
  pure (n, TCustom "_")

-- | Parse (def-interface Name [fn-sig ...])
pDefInterface :: Parser Statement
pDefInterface = parens $ do
  _ <- symbol "def-interface"
  name <- pIdent
  fns <- many (try pInterfaceFn)
  pure $ SDefInterface name fns

-- | Parse a function signature in a def-interface:
--   [name (fn [arg-types] -> ret-type)]
pInterfaceFn :: Parser (Name, Type)
pInterfaceFn = brackets $ do
  name <- pIdent
  ty <- pFnType
  pure (name, ty)

-- | Parse (fn [arg-types] -> ret-type)  or  (fn [arg-types] → ret-type)
-- Accepts both bare types [string int] and named params [name: string x: int]
pFnType :: Parser Type
pFnType = parens $ do
  _ <- try (symbol "fn") <|> (T.singleton <$> char '\x03BB' <* sc)  -- fn or λ
  args <- brackets (many pFnParam)
  pArrowSym
  ret <- pType
  pure $ TFn args ret
  where
    -- Try named param first (name: type), fall back to bare type
    pFnParam = try (snd <$> pTypedParam) <|> pType

-- | Parse (type Name definition)
pTypeDef :: Parser Statement
pTypeDef = parens $ do
  _ <- symbol "type"
  name <- pIdent
  body <- pTypeBody
  pure $ STypeDef name body

-- | Parse the body of a type definition.
pTypeBody :: Parser Type
pTypeBody = choice
  [ try pWhereType   -- (where [x: base] constraint)
  , try pSumTypeMultiArm     -- (| Ctor1 Payload) (| Ctor2 Payload) ...
  , pType
  ]

-- | Parse dependent/where type: (where [x: base] constraint)
pWhereType :: Parser Type
pWhereType = parens $ do
  _ <- symbol "where"
  (_, baseTy) <- brackets pTypedParam
  constraint <- pExpr
  pure $ TDependent baseTy constraint

-- | Parse one ADT arm: (| ConstructorName [PayloadType])
--   e.g.  (| StartGame Word)   or   (| Guess Letter)
pSumArm :: Parser (Name, Maybe Type)
pSumArm = parens $ do
  _ <- symbol "|"
  ctor <- pIdent
  payload <- optional pType
  pure (ctor, payload)

-- | Parse a sum type with one or more (| Ctor Payload) arms.
-- The arms are direct children of the enclosing (type ...) parens,
-- so we do NOT wrap this in another parens call.
pSumTypeMultiArm :: Parser Type
pSumTypeMultiArm = do
  arms <- some (try pSumArm)
  let label = T.intercalate " | " (map fst arms)
  pure $ TCustom label

-- | Parse (check "description" (for-all [...] body))
pCheckBlock :: Parser Statement
pCheckBlock = parens $ do
  _ <- symbol "check"
  desc <- pStringLiteral
  prop <- pForAll
  pure $ SCheck (Property desc (propBindings prop) (propBody prop))

-- | Parse (gen TypeName generator-expr)
-- Introduces a custom PBT generator for a named type (LLMLL v0.1.1 §5.2).
-- Represented as a top-level SExpr since Statement doesn't have a GenDecl arm yet.
pGenDecl :: Parser Statement
pGenDecl = parens $ do
  _ <- symbol "gen"
  _typeName <- pIdent
  genExpr <- pExpr
  pure $ SExpr genExpr  -- store the generator expression; type index deferred to v0.2

-- | Parse (for-all [bindings] body) or (∀ [bindings] body)
pForAll :: Parser Property
pForAll = parens $ do
  _ <- try (symbol "for-all") <|> (T.singleton <$> char '\x2200' <* sc)  -- for-all or ∀
  bindings <- brackets (many pTypedParam)
  body <- pExpr
  pure $ Property "" bindings body

-- | Parse (import path (interface [...]) (capability ...))
pImportStmt :: Parser Statement
pImportStmt = parens $ do
  _ <- symbol "import"
  path <- pDottedIdent
  iface <- optional (try pInterfaceSpec)
  cap <- optional (try pCapabilitySpec)
  pure $ SImport (Import path iface cap)

pInterfaceSpec :: Parser [(Name, Type)]
pInterfaceSpec = parens $ do
  _ <- symbol "interface"
  brackets (many pInterfaceFn)

pCapabilitySpec :: Parser Capability
pCapabilitySpec = parens $ do
  _ <- symbol "capability"
  kind <- pCapKind
  target <- pStringLiteral <|> (T.pack . show <$> pIntLit) <|> pIdent
  det <- option False pDeterministicFlag
  pure $ Capability kind target det

pCapKind :: Parser CapabilityKind
pCapKind = choice
  [ CapReadWrite     <$ try (symbol "read-write")
  , CapRead          <$ try (symbol "read")
  , CapWrite         <$ try (symbol "write")
  , CapNetConnect    <$ try (symbol "connect")
  , CapNetServe      <$ try (symbol "serve")
  , CapHttpPost      <$ try (symbol "post")
  , CapHttpGet       <$ try (symbol "get")
  , CapClockMonotonic <$ try (symbol "monotonic-read")
  , CapRandomGet     <$ try (symbol "get-bytes")
  , CapCustom <$> pIdent
  ]

pDeterministicFlag :: Parser Bool
pDeterministicFlag = do
  _ <- symbol ":deterministic"
  (True <$ symbol "true") <|> (False <$ symbol "false")

-- ---------------------------------------------------------------------------
-- Contracts
-- ---------------------------------------------------------------------------

pPreClause :: Parser Expr
pPreClause = parens $ symbol "pre" *> pExpr

pPostClause :: Parser Expr
pPostClause = parens $ symbol "post" *> pExpr

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------

pType :: Parser Type
pType = choice
  [ TInt      <$ symbol "int"
  , TFloat    <$ symbol "float"
  , TString   <$ symbol "string"
  , TBool     <$ symbol "bool"
  , TUnit     <$ symbol "unit"
  , try pBytesType
  , try pListType
  , try pMapType
  , try pResultType
  , try pPromiseType
  , try pFnType
  , try pWhereType
  , TCustom <$> pIdent
  ]

pBytesType :: Parser Type
pBytesType = do
  _ <- symbol "bytes"
  n <- brackets pIntLit
  pure $ TBytes (fromIntegral n)

pListType :: Parser Type
pListType = do
  _ <- symbol "list"
  TList <$> brackets pType

pMapType :: Parser Type
pMapType = do
  _ <- symbol "map"
  brackets $ do
    k <- pType
    _ <- optional (symbol ",")
    TMap k <$> pType

pResultType :: Parser Type
pResultType = do
  _ <- symbol "Result"
  brackets $ do
    t <- pType
    _ <- optional (symbol ",")
    TResult t <$> pType

pPromiseType :: Parser Type
pPromiseType = do
  _ <- symbol "Promise"
  TPromise <$> brackets pType

-- ---------------------------------------------------------------------------
-- Expressions
-- ---------------------------------------------------------------------------

pExpr :: Parser Expr
pExpr = choice
  [ try pLetExpr
  , try pIfExpr
  , try pMatchExpr
  , try pFnExpr        -- (fn [params] body) lambda in expression position
  , try pPairExpr
  , try pAwaitExpr
  , try pDoExpr
  , try pHoleExpr
  , try pSExprApp     -- (func args...)
  , pAtom
  ]

-- | Parse (fn [typed-params] body) or (fn [typed-params] -> ret-type body)
-- Anonymous function / lambda expression.
-- The -> ret-type annotation is optional; we only parse it if '->' is present.
pFnExpr :: Parser Expr
pFnExpr = parens $ do
  _ <- try (symbol "fn") <|> (T.singleton <$> char '\x03BB' <* sc)  -- fn or λ
  params <- brackets (many pDefParam)
  _ <- optional (try (pArrowSym *> pType))  -- only consume type when -> present
  body <- pExpr
  pure $ ELambda params body

-- | Parse (let [bindings] body)
pLetExpr :: Parser Expr
pLetExpr = parens $ do
  _ <- symbol "let"
  bindings <- brackets (many pLetBinding)
  body <- pExpr
  pure $ ELet bindings body

pLetBinding :: Parser (Name, Maybe Type, Expr)
pLetBinding = brackets $ do
  name <- pIdent
  val <- pExpr
  pure (name, Nothing, val)
  -- Note: type annotations on let bindings could be added later

-- | Parse (if cond then else)
pIfExpr :: Parser Expr
pIfExpr = parens $ do
  _ <- symbol "if"
  cond <- pExpr
  thenE <- pExpr
  elseE <- pExpr
  pure $ EIf cond thenE elseE

-- | Parse (match expr [patterns])
pMatchExpr :: Parser Expr
pMatchExpr = parens $ do
  _ <- symbol "match"
  expr <- pExpr
  cases <- some pMatchCase
  pure $ EMatch expr cases

pMatchCase :: Parser (Pattern, Expr)
pMatchCase = parens $ do
  pat <- pPattern
  body <- pExpr
  pure (pat, body)

-- | Parse pattern in match arm.
-- Handles:
--   (Ctor var1 var2)  — constructor pattern with arguments, wrapped in parens
--   _                 — wildcard
--   literal           — literal
--   ident             — variable binding
pPattern :: Parser Pattern
pPattern = choice
  [ PWildcard <$ symbol "_"
  , try $ parens $ do   -- (Ctor arg1 arg2 ...) constructor pattern
      name <- pIdent
      args <- many pPattern
      pure $ PConstructor name args
  , PLiteral <$> pLiteral
  , PVar <$> pIdent
  ]

-- | Parse (pair a b)
pPairExpr :: Parser Expr
pPairExpr = parens $ do
  _ <- symbol "pair"
  a <- pExpr
  EPair a <$> pExpr

-- | Parse (await expr)
pAwaitExpr :: Parser Expr
pAwaitExpr = parens $ do
  _ <- symbol "await"
  EAwait <$> pExpr

-- | Parse (do [name <- expr] ... final-expr)
pDoExpr :: Parser Expr
pDoExpr = parens $ do
  _ <- symbol "do"
  steps <- some pDoStep
  pure $ EDo steps

pDoStep :: Parser DoStep
pDoStep = try pDoBind <|> (DoExpr <$> pExpr)
  where
    pDoBind = brackets $ do
      name <- pIdent
      _ <- symbol "<-"
      DoBind name <$> pExpr

-- | Parse hole expressions.
pHoleExpr :: Parser Expr
pHoleExpr = choice
  [ try pDelegateHole
  , try pDelegateAsyncHole
  , try pScaffoldHole
  , try pChooseHole
  , try pRequestCapHole
  , pNamedHole
  ]

pNamedHole :: Parser Expr
pNamedHole = do
  _ <- char '?'
  name <- T.pack <$> some (alphaNumChar <|> char '-' <|> char '_')
  sc
  pure $ EHole (HNamed name)

pChooseHole :: Parser Expr
pChooseHole = parens $ do
  _ <- symbol "?choose"
  opts <- many pIdent
  pure $ EHole (HChoose opts)

pRequestCapHole :: Parser Expr
pRequestCapHole = parens $ do
  _ <- symbol "?request-cap"
  cap <- pDottedIdent
  pure $ EHole (HRequestCap cap)

pScaffoldHole :: Parser Expr
pScaffoldHole = parens $ do
  _ <- symbol "?scaffold"
  template <- pIdent
  lang    <- optional (symbol ":language" *> pIdent)
  mods    <- option [] (symbol ":modules" *> brackets (many pIdent))
  style   <- optional (symbol ":style" *> pIdent)
  version <- optional (symbol ":version" *> pStringLiteral)
  pure $ EHole (HScaffold (ScaffoldSpec template lang mods style version))

pDelegateHole :: Parser Expr
pDelegateHole = parens $ do
  _ <- symbol "?delegate"
  agent <- pAgentRef
  desc <- pStringLiteral
  pArrowSym
  retTy <- pType
  onFail <- optional (try pOnFailure)
  pure $ EHole (HDelegate (DelegateSpec agent desc retTy onFail))

pDelegateAsyncHole :: Parser Expr
pDelegateAsyncHole = parens $ do
  _ <- symbol "?delegate-async"
  agent <- pAgentRef
  desc <- pStringLiteral
  pArrowSym
  retTy <- pType
  pure $ EHole (HDelegateAsync (DelegateSpec agent desc retTy Nothing))

pOnFailure :: Parser Expr
pOnFailure = parens $ symbol "on-failure" *> pExpr

-- | Parse a general S-expression application: (func arg1 arg2 ...)
-- The head can be an identifier OR an operator symbol like >, >=, +, -, etc.
pSExprApp :: Parser Expr
pSExprApp = parens $ do
  func <- pFuncName
  args <- many pExpr
  if isOperator func
    then pure $ EOp func args
    else pure $ EApp func args

-- | Parse a function/operator name: either an identifier or an operator symbol.
-- Recognises both ASCII operators and their Unicode aliases (see LLMLL.md §2.4).
pFuncName :: Parser Name
pFuncName = lexeme' $ choice
  [ try (string ">=") , try (string "<=") , try (string "!=") , try (string "->")
  -- Unicode comparison aliases
  , try (string "\x2265") -- ≥
  , try (string "\x2264") -- ≤
  , try (string "\x2260") -- ≠
  , try (string "\x2192") -- →
  -- Unicode single-char operator aliases
  , T.singleton <$> oneOf ("><=+-*/\x2227\x2228\x00AC" :: String)  -- ∧ ∨ ¬
  , do
      first <- letterChar <|> char '_'
      rest <- T.pack <$> many (alphaNumChar <|> char '-' <|> char '_' <|> char '?' <|> char '.')
      let ident = T.cons first rest
      if ident `elem` reservedWords
        then fail $ "reserved word " ++ T.unpack ident ++ " used as identifier"
        else pure ident
  ]

isOperator :: Name -> Bool
isOperator n = n `elem`
  ["+", "-", "*", "/", "=", "!=", "<", ">", "<=", ">=",
   "and", "or", "not", "regex-match", "is-valid?",
   -- Unicode aliases map to the same operator semantics:
   "\x2265", "\x2264", "\x2260",  -- ≥ ≤ ≠
   "\x2227", "\x2228", "\x00AC"   -- ∧ ∨ ¬
  ]

-- ---------------------------------------------------------------------------
-- Atoms
-- ---------------------------------------------------------------------------

pAtom :: Parser Expr
pAtom = choice
  [ ELit <$> pLiteral
  , EVar <$> pIdent
  ]

pLiteral :: Parser Literal
pLiteral = choice
  [ try $ LitFloat <$> lexeme' L.float
  , LitInt <$> lexeme' L.decimal
  , LitString <$> pStringLiteral
  , LitBool True  <$ symbol "true"
  , LitBool False <$ symbol "false"
  , LitUnit       <$ symbol "()"
  ]

-- ---------------------------------------------------------------------------
-- Primitive Parsers
-- ---------------------------------------------------------------------------

pStringLiteral :: Parser Text
pStringLiteral = lexeme' $ do
  _ <- char '"'
  content <- T.pack <$> manyTill L.charLiteral (char '"')
  pure content

pIntLit :: Parser Integer
pIntLit = lexeme' L.decimal

pIdent :: Parser Name
pIdent = lexeme' $ do
  first <- letterChar <|> char '_'
  rest <- T.pack <$> many (alphaNumChar <|> char '-' <|> char '_' <|> char '?' <|> char '.')
  let ident = T.cons first rest
  -- Reject keywords as identifiers
  if ident `elem` reservedWords
    then fail $ "reserved word " ++ T.unpack ident ++ " used as identifier"
    else pure ident

pDottedIdent :: Parser Name
pDottedIdent = lexeme' $ do
  first <- letterChar <|> char '_'
  rest <- T.pack <$> many (alphaNumChar <|> char '-' <|> char '_' <|> char '.')
  pure $ T.cons first rest

pAgentRef :: Parser Name
pAgentRef = lexeme' $ do
  _ <- char '@'
  T.pack <$> some (alphaNumChar <|> char '-' <|> char '_')

-- | Parse a typed parameter: name: type
pTypedParam :: Parser (Name, Type)
pTypedParam = do
  name <- pIdent
  _ <- symbol ":"
  ty <- pType
  pure (name, ty)

reservedWords :: [Text]
reservedWords =
  [ "module", "import", "def-logic", "def-interface", "let", "if"
  , "match", "check", "pre", "post", "for-all", "type", "where"
  , "pair", "await", "do", "on-failure", "fn", "true", "false"
  , "capability"
  ]
