{-# LANGUAGE StrictData #-}
-- |
-- Module      : LLMLL.Lexer
-- Description : Megaparsec-based tokenizer for LLMLL S-expressions.
--
-- Tokenizes LLMLL source code into a stream of tokens with source spans.
-- Handles all keywords, hole syntax, type names, literals, capability flags,
-- comments, and Unicode symbol aliases.
--
-- == Unicode Alias Policy
-- Source identifiers must be ASCII.  However, a curated set of mathematical
-- Unicode symbols are accepted as aliases for their ASCII equivalents.  Both
-- forms produce the *same* 'TokenKind'; the canonical output of the compiler
-- always uses ASCII.
--
-- @
-- ASCII   Unicode   Meaning
-- -----   -------   -------
-- ->      →         function / return arrow
-- >=      ≥         greater-or-equal
-- <=      ≤         less-or-equal
-- !=      ≠         not-equal
-- and     ∧         logical conjunction
-- or      ∨         logical disjunction
-- not     ¬         logical negation
-- for-all ∀         universal quantifier
-- fn      λ         lambda / anonymous function
-- @
module LLMLL.Lexer
  ( -- * Token Types
    Token(..)
  , TokenKind(..)
  , tokenize
  , lexLLMLL
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import Data.Void (Void)
import Text.Megaparsec hiding (Token)
import Text.Megaparsec.Char
import qualified Text.Megaparsec.Char.Lexer as L

import LLMLL.Syntax (Span(..))

-- ---------------------------------------------------------------------------
-- Token Types
-- ---------------------------------------------------------------------------

-- | A token with source location.
data Token = Token
  { tokKind :: TokenKind
  , tokSpan :: Span
  , tokText :: Text    -- ^ Original source text of this token
  } deriving (Show, Eq)

-- | The different kinds of tokens.
data TokenKind
  -- Delimiters
  = TokLParen            -- ^ (
  | TokRParen            -- ^ )
  | TokLBracket          -- ^ [
  | TokRBracket          -- ^ ]

  -- Literals
  | TokIntLit Integer    -- ^ Integer literal
  | TokFloatLit Double   -- ^ Float literal
  | TokStringLit Text    -- ^ "string"
  | TokBoolLit Bool      -- ^ true / false
  | TokHashBytes Text    -- ^ #x4f2a... (hex bytes)

  -- Keywords
  | TokModule
  | TokImport
  | TokDefLogic
  | TokDefInterface
  | TokDefInvariant
  | TokLet
  | TokIf
  | TokMatch
  | TokCheck
  | TokPre
  | TokPost
  | TokForAll
  | TokType
  | TokWhere
  | TokPair
  | TokAwait
  | TokDo
  | TokOnFailure
  | TokFn

  -- Arrows
  | TokArrow             -- ^ ->

  -- Operators
  | TokPlus              -- ^ +
  | TokMinus             -- ^ -
  | TokStar              -- ^ *
  | TokSlash             -- ^ /
  | TokEqual             -- ^ =
  | TokNotEqual          -- ^ !=
  | TokLT                -- ^ <
  | TokGT                -- ^ >
  | TokLTE               -- ^ <=
  | TokGTE               -- ^ >=
  | TokAnd               -- ^ and
  | TokOr                -- ^ or
  | TokNot               -- ^ not
  | TokPipe              -- ^ |   (for sum types)

  -- Type Keywords
  | TokTInt
  | TokTFloat
  | TokTString
  | TokTBool
  | TokTUnit
  | TokTBytes
  | TokTList
  | TokTMap
  | TokTResult
  | TokTPromise

  -- Hole Syntax
  | TokHoleNamed Text          -- ^ ?name
  | TokHoleChoose              -- ^ ?choose
  | TokHoleRequestCap          -- ^ ?request-cap
  | TokHoleScaffold            -- ^ ?scaffold
  | TokHoleDelegate            -- ^ ?delegate
  | TokHoleDelegateAsync       -- ^ ?delegate-async

  -- Capability Flags
  | TokCapability              -- ^ capability
  | TokKwDeterministic         -- ^ :deterministic
  | TokKwLanguage              -- ^ :language
  | TokKwModules               -- ^ :modules
  | TokKwStyle                 -- ^ :style
  | TokKwVersion               -- ^ :version

  -- Identifiers
  | TokIdent Text              -- ^ General identifier
  | TokAgentRef Text           -- ^ @agent-name
  | TokKeywordArg Text         -- ^ :keyword-name (generic keyword arg)

  deriving (Show, Eq)

-- ---------------------------------------------------------------------------
-- Lexer
-- ---------------------------------------------------------------------------

type Parser = Parsec Void Text

-- | Tokenize LLMLL source. Returns either an error or a list of tokens.
tokenize :: FilePath -> Text -> Either (ParseErrorBundle Text Void) [Token]
tokenize = parse (space' *> many pToken <* eof)

-- | Synonym for tokenize.
lexLLMLL :: FilePath -> Text -> Either (ParseErrorBundle Text Void) [Token]
lexLLMLL = tokenize

-- | Skip whitespace and comments.
space' :: Parser ()
space' = L.space space1 (L.skipLineComment ";;") empty

-- | Lexeme wrapper: parse something and skip trailing whitespace.
lexeme :: Parser a -> Parser a
lexeme = L.lexeme space'

-- | Parse a single token.
pToken :: Parser Token
pToken = do
  startPos <- getSourcePos
  (kind, _) <- choice
    [ pDelimiter
    , pHole
    , pArrow           -- must come before pOperator (shares '-')
    , pUnicodeOperator -- single-char Unicode symbols (∧ ∨ ¬ ∀ λ)
    , pOperator        -- ASCII multi-char operators (>=  <=  != then single)
    , pStringLit
    , pHashBytes
    , pNumberLit
    , pKeywordOrIdent
    ]
  endPos <- getSourcePos
  let sp = Span
        { spanFile    = sourceName startPos
        , spanLine    = unPos (sourceLine startPos)
        , spanCol     = unPos (sourceColumn startPos)
        , spanEndLine = unPos (sourceLine endPos)
        , spanEndCol  = unPos (sourceColumn endPos)
        }
  let txt = kindToText kind
  space'
  pure $ Token kind sp txt

-- | Parse delimiters.
pDelimiter :: Parser (TokenKind, ())
pDelimiter = choice
  [ (TokLParen,)   <$> (() <$ char '(')
  , (TokRParen,)   <$> (() <$ char ')')
  , (TokLBracket,) <$> (() <$ char '[')
  , (TokRBracket,) <$> (() <$ char ']')
  ]

-- | Parse arrow token: ASCII @->@ or Unicode @→@ (U+2192).
-- Must be tried before 'pOperator' so that @-@ is not consumed first.
pArrow :: Parser (TokenKind, ())
pArrow = try $ (TokArrow,) <$> (() <$ choice
  [ string "->"   -- ASCII form (maximal munch: always preferred over - alone)
  , string "\x2192"  -- Unicode → (U+2192 RIGHTWARDS ARROW)
  ])

-- | Parse Unicode single-codepoint symbol aliases (∧ ∨ ¬ ∀ λ).
-- These map to the same 'TokenKind' as their ASCII keyword equivalents.
-- Called before 'pOperator' and 'pKeywordOrIdent' in 'pToken'.
pUnicodeOperator :: Parser (TokenKind, ())
pUnicodeOperator = choice
  [ (TokAnd,)    <$> (() <$ char '\x2227')  -- ∧  U+2227  LOGICAL AND
  , (TokOr,)     <$> (() <$ char '\x2228')  -- ∨  U+2228  LOGICAL OR
  , (TokNot,)    <$> (() <$ char '\xAC')    -- ¬  U+00AC  NOT SIGN
  , (TokForAll,) <$> (() <$ char '\x2200')  -- ∀  U+2200  FOR ALL
  , (TokFn,)     <$> (() <$ char '\x03BB')  -- λ  U+03BB  GREEK SMALL LETTER LAMBDA
  ]

-- | Parse ASCII operators (multi-char attempted first; Unicode ≥ ≤ ≠ also accepted).
pOperator :: Parser (TokenKind, ())
pOperator = choice
  [ try $ (TokGTE,)      <$> (() <$ (string ">="  <|> string "\x2265"))  -- ≥ U+2265
  , try $ (TokLTE,)      <$> (() <$ (string "<="  <|> string "\x2264"))  -- ≤ U+2264
  , try $ (TokNotEqual,) <$> (() <$ (string "!="  <|> string "\x2260"))  -- ≠ U+2260
  , (TokPipe,)            <$> (() <$ char '|')
  , (TokPlus,)            <$> (() <$ char '+')
  , (TokStar,)            <$> (() <$ char '*')
  , (TokSlash,)           <$> (() <$ char '/')
  , (TokEqual,)           <$> (() <$ char '=')
  , (TokLT,)              <$> (() <$ char '<')
  , (TokGT,)              <$> (() <$ char '>')
  ]

-- | Parse a string literal.
pStringLit :: Parser (TokenKind, ())
pStringLit = do
  _ <- char '"'
  content <- T.pack <$> manyTill L.charLiteral (char '"')
  pure (TokStringLit content, ())

-- | Parse hex bytes literal: #x4f2a...
pHashBytes :: Parser (TokenKind, ())
pHashBytes = try $ do
  _ <- string "#x"
  hex <- T.pack <$> some hexDigitChar
  pure (TokHashBytes hex, ())

-- | Parse number literals (integers and floats).
pNumberLit :: Parser (TokenKind, ())
pNumberLit = try $ do
  neg <- option False (True <$ char '-')
  digits <- some digitChar
  mDot <- optional (char '.' *> some digitChar)
  let prefix = if neg then "-" else ""
  case mDot of
    Nothing -> pure (TokIntLit (read (prefix ++ digits)), ())
    Just frac ->
      pure (TokFloatLit (read (prefix ++ digits ++ "." ++ frac)), ())

-- | Parse holes: ?name, ?choose, ?request-cap, ?scaffold, ?delegate, ?delegate-async
pHole :: Parser (TokenKind, ())
pHole = try $ do
  _ <- char '?'
  name <- T.pack <$> some (alphaNumChar <|> char '-' <|> char '_')
  pure (classifyHole name, ())
  where
    classifyHole n
      | n == "choose"         = TokHoleChoose
      | n == "request-cap"    = TokHoleRequestCap
      | n == "scaffold"       = TokHoleScaffold
      | n == "delegate-async" = TokHoleDelegateAsync
      | n == "delegate"       = TokHoleDelegate
      | otherwise             = TokHoleNamed n

-- | Parse keywords, type keywords, boolean literals, agent refs, keyword args, identifiers.
pKeywordOrIdent :: Parser (TokenKind, ())
pKeywordOrIdent = choice
  [ pAgentRef
  , pKeywordArg
  , pWord
  ]

-- | Parse @agent-name
pAgentRef :: Parser (TokenKind, ())
pAgentRef = try $ do
  _ <- char '@'
  name <- T.pack <$> some (alphaNumChar <|> char '-' <|> char '_')
  pure (TokAgentRef name, ())

-- | Parse :keyword-arg
pKeywordArg :: Parser (TokenKind, ())
pKeywordArg = try $ do
  _ <- char ':'
  name <- T.pack <$> some (alphaNumChar <|> char '-' <|> char '_')
  pure (classifyKeywordArg name, ())
  where
    classifyKeywordArg n
      | n == "deterministic" = TokKwDeterministic
      | n == "language"      = TokKwLanguage
      | n == "modules"       = TokKwModules
      | n == "style"         = TokKwStyle
      | n == "version"       = TokKwVersion
      | otherwise            = TokKeywordArg n

-- | Parse a word (identifier or keyword).
pWord :: Parser (TokenKind, ())
pWord = do
  first <- letterChar <|> char '_' <|> char '-'
  rest <- T.pack <$> many (alphaNumChar <|> char '-' <|> char '_' <|> char '.' <|> char '?')
  let word = T.cons first rest
  pure (classifyWord word, ())

classifyWord :: Text -> TokenKind
classifyWord w = case w of
  -- Keywords
  "module"        -> TokModule
  "import"        -> TokImport
  "def-logic"     -> TokDefLogic
  "def-interface" -> TokDefInterface
  "def-invariant" -> TokDefInvariant
  "let"           -> TokLet
  "if"            -> TokIf
  "match"         -> TokMatch
  "check"         -> TokCheck
  "pre"           -> TokPre
  "post"          -> TokPost
  "for-all"       -> TokForAll
  "type"          -> TokType
  "where"         -> TokWhere
  "pair"          -> TokPair
  "await"         -> TokAwait
  "do"            -> TokDo
  "on-failure"    -> TokOnFailure
  "fn"            -> TokFn
  "capability"    -> TokCapability

  -- Boolean literals
  "true"          -> TokBoolLit True
  "false"         -> TokBoolLit False

  -- Logical operators
  "and"           -> TokAnd
  "or"            -> TokOr
  "not"           -> TokNot

  -- Type keywords
  "int"           -> TokTInt
  "float"         -> TokTFloat
  "string"        -> TokTString
  "bool"          -> TokTBool
  "unit"          -> TokTUnit
  "bytes"         -> TokTBytes
  "list"          -> TokTList
  "map"           -> TokTMap
  "Result"        -> TokTResult
  "Promise"       -> TokTPromise

  -- General identifier
  _               -> TokIdent w

-- | Convert a TokenKind back to approximate text (for Token construction).
kindToText :: TokenKind -> Text
kindToText = \case
  TokLParen          -> "("
  TokRParen          -> ")"
  TokLBracket        -> "["
  TokRBracket        -> "]"
  TokIntLit n        -> T.pack (show n)
  TokFloatLit n      -> T.pack (show n)
  TokStringLit s     -> "\"" <> s <> "\""
  TokBoolLit True    -> "true"
  TokBoolLit False   -> "false"
  TokHashBytes h     -> "#x" <> h
  TokModule          -> "module"
  TokImport          -> "import"
  TokDefLogic        -> "def-logic"
  TokDefInterface    -> "def-interface"
  TokDefInvariant    -> "def-invariant"
  TokLet             -> "let"
  TokIf              -> "if"
  TokMatch           -> "match"
  TokCheck           -> "check"
  TokPre             -> "pre"
  TokPost            -> "post"
  TokForAll          -> "for-all"
  TokType            -> "type"
  TokWhere           -> "where"
  TokPair            -> "pair"
  TokAwait           -> "await"
  TokDo              -> "do"
  TokOnFailure       -> "on-failure"
  TokFn              -> "fn"
  TokArrow           -> "->"
  TokPlus            -> "+"
  TokMinus           -> "-"
  TokStar            -> "*"
  TokSlash           -> "/"
  TokEqual           -> "="
  TokNotEqual        -> "!="
  TokLT              -> "<"
  TokGT              -> ">"
  TokLTE             -> "<="
  TokGTE             -> ">="
  TokAnd             -> "and"
  TokOr              -> "or"
  TokNot             -> "not"
  TokPipe            -> "|"
  TokTInt            -> "int"
  TokTFloat          -> "float"
  TokTString         -> "string"
  TokTBool           -> "bool"
  TokTUnit           -> "unit"
  TokTBytes          -> "bytes"
  TokTList           -> "list"
  TokTMap            -> "map"
  TokTResult         -> "Result"
  TokTPromise        -> "Promise"
  TokHoleNamed n     -> "?" <> n
  TokHoleChoose      -> "?choose"
  TokHoleRequestCap  -> "?request-cap"
  TokHoleScaffold    -> "?scaffold"
  TokHoleDelegate    -> "?delegate"
  TokHoleDelegateAsync -> "?delegate-async"
  TokCapability      -> "capability"
  TokKwDeterministic -> ":deterministic"
  TokKwLanguage      -> ":language"
  TokKwModules       -> ":modules"
  TokKwStyle         -> ":style"
  TokKwVersion       -> ":version"
  TokIdent t         -> t
  TokAgentRef t      -> "@" <> t
  TokKeywordArg t    -> ":" <> t
