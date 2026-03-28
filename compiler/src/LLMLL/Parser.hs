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
pTopLevelItem = pModuleFlattened <|> (pure <$> pStatement)

-- | Parse @(module Name [imports...] [open/export...] [statements...])@ and return
-- its contents as a flat list of statements.  The module name is
-- ignored (single-file model).  Imports become 'SImport' nodes.
-- v0.2: open/export declarations are also accepted before body statements.
pModuleFlattened :: Parser [Statement]
pModuleFlattened = do
  _ <- try (symbol "(" *> symbol "module")
  _ <- pIdent          -- module name: recorded but not used in single-file model
  imports <- many (try pImportStmt)
  opens   <- many (try pOpenDecl <|> try pExportDecl)
  body    <- many pStatement
  _ <- symbol ")"
  pure (imports ++ opens ++ body)

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
  [ pDefLogic
  , pLetrec
  , pDefMain
  , pDefInterface
  , pTypeDef
  , pCheckBlock
  , pGenDecl
  , pImportStmt
  , pOpenDecl
  , pExportDecl
  , SExpr <$> pExpr
  ]

-- | Parse (def-logic name [params] (pre ...) ... (post ...) body)
-- Multiple (pre ...) clauses are accepted and desugared to (pre (and ...)).
pDefLogic :: Parser Statement
pDefLogic = do
  _ <- try (symbol "(" *> symbol "def-logic")
  name <- pIdent
  params <- brackets (many pDefParam)
  preClauses <- many (try pPreClause)
  mPost <- optional (try pPostClause)
  body <- pExpr
  _ <- symbol ")"
  let mPre = case preClauses of
               []  -> Nothing
               [p] -> Just p
               ps  -> Just (foldl1 (\a b -> EApp "and" [a, b]) ps)
  pure $ SDefLogic name params Nothing (Contract mPre mPost) body

-- | Parse (letrec name [params] :decreases measure body)
-- Introduces an explicitly recursive function with a termination measure.
-- The :decreases expression must be integer-valued and must strictly decrease
-- in each recursive call (QF linear arithmetic, for LH verification in D4).
pLetrec :: Parser Statement
pLetrec = do
  _ <- try (symbol "(" *> symbol "letrec")
  name    <- pIdent
  params  <- brackets (many pDefParam)
  preClauses <- many (try pPreClause)
  mPost   <- optional (try pPostClause)
  dec     <- symbol ":decreases" *> pExpr
  body    <- pExpr
  _       <- symbol ")"
  let mPre = case preClauses of
               []  -> Nothing
               [p] -> Just p
               ps  -> Just (foldl1 (\a b -> EApp "and" [a, b]) ps)
  pure $ SLetrec name params Nothing (Contract mPre mPost) dec body

-- | A def-logic param is either a typed binding (name: type) or a bare name.
-- Bare names are given a wildcard type to unblock parsing; type inference is v0.2.
pDefParam :: Parser (Name, Type)
pDefParam = do
  n <- pIdent
  (do _ <- symbol ":"
      ty <- pType
      pure (n, ty)) <|> pure (n, TCustom "_")

-- | Parse (def-interface Name [fn-sig ...])
pDefInterface :: Parser Statement
pDefInterface = do
  _ <- try (symbol "(" *> symbol "def-interface")
  name <- pIdent
  fns <- many (try pInterfaceFn)
  _ <- symbol ")"
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
    pFnParam = try (do
      _ <- pIdent
      _ <- symbol ":"
      pType) <|> pType

-- | Parse (type Name definition)
pTypeDef :: Parser Statement
pTypeDef = do
  _ <- try (symbol "(" *> symbol "type")
  name <- pIdent
  body <- pTypeBody
  _ <- symbol ")"
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
  (bindName, baseTy) <- brackets pTypedParam
  constraint <- pExpr
  pure $ TDependent bindName baseTy constraint

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
  pure $ TSumType arms

-- | Parse (check "description" (for-all [...] body))
pCheckBlock :: Parser Statement
pCheckBlock = do
  _ <- try (symbol "(" *> symbol "check")
  desc <- pStringLiteral
  prop <- pForAll
  _ <- symbol ")"
  pure $ SCheck (Property desc (propBindings prop) (propBody prop))

-- | Parse (gen TypeName generator-expr)
-- Introduces a custom PBT generator for a named type (LLMLL v0.1.1 §5.2).
-- Represented as a top-level SExpr since Statement doesn't have a GenDecl arm yet.
pGenDecl :: Parser Statement
pGenDecl = do
  _ <- try (symbol "(" *> symbol "gen")
  _typeName <- pIdent
  genExpr <- pExpr
  _ <- symbol ")"
  pure $ SExpr genExpr  -- store the generator expression; type index deferred to v0.2

-- | Parse (for-all [bindings] body) or (∀ [bindings] body)
pForAll :: Parser Property
pForAll = parens $ do
  _ <- try (symbol "for-all") <|> (T.singleton <$> char '\x2200' <* sc)  -- for-all or ∀
  bindings <- brackets (many pTypedParam)
  body <- pExpr
  pure $ Property "" bindings body

-- | Parse an import statement.
-- (import foo.bar.baz)
-- (import foo.bar.baz (interface [...]))
-- (import foo.bar.baz (capability ...))
pImportStmt :: Parser Statement
pImportStmt = do
  _ <- try (symbol "(" *> symbol "import")
  path <- pDottedIdent
  iface <- optional (try pInterfaceSpec)
  cap <- optional (try pCapabilitySpec)
  _ <- symbol ")"
  pure $ SImport (Import path iface cap)

-- | Parse (open foo.bar) or (open foo.bar (f g h)) — v0.2.
-- Pulls all or named exports of a module into the current bare scope.
pOpenDecl :: Parser Statement
pOpenDecl = do
  _ <- try (symbol "(" *> symbol "open")
  path <- splitDotted <$> pDottedIdent
  names <- optional (parens (many pIdent))
  _ <- symbol ")"
  pure $ SOpen path names

-- | Parse (export f g h) — v0.2.
-- Restricts which top-level names are visible to importers.
pExportDecl :: Parser Statement
pExportDecl = do
  _ <- try (symbol "(" *> symbol "export")
  names <- many pIdent
  _ <- symbol ")"
  pure $ SExport names

-- | Split a dotted Text identifier into a module path.
splitDotted :: Text -> [Text]
splitDotted = T.splitOn "."

-- | Parse (def-main :mode console|cli|http [:port n] :init expr :step expr ...)
pDefMain :: Parser Statement
pDefMain = do
  _ <- try (symbol "(" *> symbol "def-main")
  mode    <- pModeKeyword *> pEntryMode
  initE   <- optional (symbol ":init"    *> pExpr)
  stepE   <- symbol ":step"              *> pExpr
  readE   <- optional (symbol ":read"    *> pExpr)
  doneE   <- optional (symbol ":done?"   *> pExpr)
  onDoneE <- optional (symbol ":on-done" *> pExpr)
  _       <- symbol ")"
  pure $ SDefMain mode initE stepE readE doneE onDoneE
  where
    pModeKeyword = symbol ":mode"

-- | Parse the mode keyword after `:mode`.
pEntryMode :: Parser EntryMode
pEntryMode = choice
  [ ModeConsole <$ symbol "console"
  , ModeCli     <$ symbol "cli"
  , symbol "http" *> (ModeHttp . fromIntegral <$> option (8080 :: Integer) pIntLit)
  ]

pInterfaceSpec :: Parser [(Name, Type)]
pInterfaceSpec = parens $ do
  _ <- symbol "interface"
  brackets (many pInterfaceFn)

pCapabilitySpec :: Parser Capability
pCapabilitySpec = parens $ do
  _ <- symbol "capability"
  kind <- pCapKind
  target <- option "" (pStringLiteral <|> (T.pack . show <$> pIntLit) <|> pIdent)
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
  [ try pPairType   -- Phase 2c: (T1, T2) pair-type in parameter positions
  , TInt      <$ symbol "int"
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

-- | Phase 2c: parse pair-type (T1, T2) in type position into TResult T1 T2.
-- This matches the runtime model: EPair evaluates to TResult.
-- Accepted in def-logic params, lambda params, and for-all bindings.
pPairType :: Parser Type
pPairType = do
  _ <- try (lookAhead (symbol "("))
  parens $ do
    t1 <- pType
    _  <- symbol ","
    t2 <- pType
    pure (TResult t1 t2)

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
  , try pCondExpr      -- (cond [c1 e1] [c2 e2] [_ fallback]) sugar
  , try pIfExpr
  , try pMatchExpr
  , try pFnExpr        -- (fn [params] body) lambda in expression position
  , try pPairExpr
  , try pAwaitExpr
  , try pDoExpr
  , try pHoleExpr
  , try pListLitExpr   -- [expr ...] list literal in expression position
  , try pSExprApp     -- (func args...)
  , pAtom
  ]

-- | Parse a list literal in expression position: [expr expr ...]
-- Desugars to foldr list-prepend (list-empty) — same as lit-list in JSON-AST.
-- Empty [] desugars to (list-empty).
pListLitExpr :: Parser Expr
pListLitExpr = do
  items <- brackets (many (try pExpr))
  pure $ foldr (\item acc -> EApp "list-prepend" [item, acc])
               (EApp "list-empty" [])
               items

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
pLetBinding =
  -- v0.1.2 canonical: (name expr)
  (parens $ do
    name <- pIdent
    val  <- pExpr
    pure (name, Nothing, val))
  -- v0.1.1 legacy: [name expr]  (kept for backward compatibility)
  <|> (brackets $ do
    name <- pIdent
    val  <- pExpr
    pure (name, Nothing, val))
  -- Note: type annotations on let bindings could be added later

-- | Parse (if cond then else)
pIfExpr :: Parser Expr
pIfExpr = parens $ do
  _ <- symbol "if"
  cond  <- pExpr
  thenE <- pExpr
  elseE <- pExpr <?> "else branch (if requires exactly 3 sub-expressions: condition, then, else)"
  pure $ EIf cond thenE elseE

-- | Parse (cond [cond1 expr1] [cond2 expr2] ... [_ fallback])
-- Desugars to nested (if cond1 expr1 (if cond2 expr2 ... fallback)).
-- The final arm can use _ as a wildcard (always matched as true fallback).
pCondExpr :: Parser Expr
pCondExpr = parens $ do
  _ <- symbol "cond"
  arms <- some (brackets $ (,) <$> pExpr <*> pExpr)
  pure $ foldr desugarArm (ELit (LitBool False)) arms
  where
    desugarArm (cond, body) rest =
      case cond of
        EVar "_"  -> body            -- wildcard arm: always taken, ignore rest
        _         -> EIf cond body rest

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
  [ try $ do     -- standalone _ wildcard (not followed by ident chars)
      _ <- char '_'
      notFollowedBy (alphaNumChar <|> char '-' <|> char '_')
      sc
      pure PWildcard
  , try $ parens $ do   -- (Ctor arg1 arg2 ...) constructor pattern
      name <- pIdent
      args <- many pPattern
      pure $ PConstructor name args
  , PLiteral <$> pLiteral
  , PVar <$> pIdent     -- also matches _foo as a single named binder
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
  , try pProofRequiredHole  -- D3: must come before pNamedHole
  , pNamedHole
  ]

-- | Parse ?proof-required (D3 manual proof obligation marker).
pProofRequiredHole :: Parser Expr
pProofRequiredHole = do
  _ <- string "?proof-required"
  sc
  pure $ EHole (HProofRequired "manual")

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
  , try $ LitInt   <$> pSignedDecimal   -- P3: negative literals e.g. -1, -42
  , LitInt <$> lexeme' L.decimal
  , LitString <$> pStringLiteral
  , LitBool True  <$ symbol "true"
  , LitBool False <$ symbol "false"
  , LitUnit       <$ symbol "()"
  ]

-- | Signed decimal: matches '-' immediately followed by digits (no space).
-- 'try' in pLiteral ensures we backtrack if '-' appears as the subtraction OP.
pSignedDecimal :: Parser Integer
pSignedDecimal = lexeme' $ do
  _ <- char '-'
  n <- L.decimal
  pure (negate n)

-- ---------------------------------------------------------------------------
-- Primitive Parsers
-- ---------------------------------------------------------------------------

pStringLiteral :: Parser Text
pStringLiteral = lexeme' $ do
  _ <- char '"'
  content <- T.pack <$> manyTill pStringChar (char '"')
  pure content
  where
    -- P2: handle \uXXXX before Megaparsec's L.charLiteral (which doesn't recognise \u).
    pStringChar :: Parser Char
    pStringChar = (char '\\' *> pEscape) <|> anySingleBut '"'

    pEscape :: Parser Char
    pEscape =
          (char 'u' *> pUnicodeEscape)   -- \uXXXX
      <|> (char 'n' *> pure '\n')        -- standard Haskell-style escapes
      <|> (char 't' *> pure '\t')
      <|> (char 'r' *> pure '\r')
      <|> (char '\\' *> pure '\\')
      <|> (char '"' *> pure '"')
      <|> (char '0' *> pure '\0')
      <|> anySingle  -- pass through anything else (best-effort)

    pUnicodeEscape :: Parser Char
    pUnicodeEscape = do
      h1 <- hexDigitChar; h2 <- hexDigitChar
      h3 <- hexDigitChar; h4 <- hexDigitChar
      let code = foldl (\acc c -> acc * 16 + fromEnum (hexVal c)) 0 [h1,h2,h3,h4]
      pure (toEnum code)

    hexVal :: Char -> Int
    hexVal c
      | c >= '0' && c <= '9' = fromEnum c - fromEnum '0'
      | c >= 'a' && c <= 'f' = fromEnum c - fromEnum 'a' + 10
      | c >= 'A' && c <= 'F' = fromEnum c - fromEnum 'A' + 10
      | otherwise             = 0

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
  , "capability", "letrec"
  -- v0.2 module system
  , "open", "export"
  ]
