{-# LANGUAGE OverloadedStrings #-}
-- |
-- Module      : LLMLL.RegexPattern
-- Description : The pattern rules `check` applies to a literal regex pattern.
--
-- REGEX-CAPTURE-1 / REGEX-CASE-1 (docs/design/regex-capture-case-proposal.md,
-- Rev 0, plus amendment A1 from the implementation plan).
--
-- The four regex builtins (regex-match, regex-find, regex-find-all,
-- regex-spans) compile their pattern at run time with regex-tdfa, inside the
-- generated program's preamble ('llmll_rxCompile' in CodegenHs). A pattern
-- that does not compile makes the call answer False or [] there, with no
-- message. This module lets `check` say so first, for a pattern it can see:
-- a string literal, or a nullary local definition whose whole body is one.
--
-- THE RULES HERE AND THE PREAMBLE'S MUST AGREE. Both use the same regex-tdfa:
-- compiler/stack.yaml and the stack.yaml that `llmll build` writes pin the
-- same LTS resolver, and Spec.hs RX-12 fails if they ever differ.
module LLMLL.RegexPattern
  ( RegexProblem(..)
  , splitCaseFlag
  , validatePattern
  , rxMeaningfulEscapes
  ) where

import Data.Char (isAsciiLower, isAsciiUpper)
import Text.Regex.TDFA.Pattern (Pattern(..))
import Text.Regex.TDFA.ReadRegex (parseRegex)

-- | Why a pattern is rejected.
data RegexProblem
  = RxParse String
    -- ^ regex-tdfa cannot parse it; the library's message, on one line.
  | RxEscape Char
    -- ^ Amendment A1: a backslash before an ASCII letter that regex-tdfa
    -- reads as the letter itself. @\\d@ matches the letter d, not a digit.
  deriving (Eq, Show)

-- | A leading @(?i)@ asks for a match without regard to case. Only the first
-- four characters are read; @(?i)@ anywhere else stays in the pattern, where
-- regex-tdfa rejects it. Answers (case sensitive?, the rest of the pattern).
splitCaseFlag :: String -> (Bool, String)
splitCaseFlag ('(':'?':'i':')':rest) = (False, rest)
splitCaseFlag p                      = (True, p)

-- | The escapes outside a bracket expression to which regex-tdfa gives a
-- meaning: the word-boundary and buffer anchors. Every other backslash before
-- an ASCII letter is read as the letter itself. Spec.hs RX-7 measures this
-- set against the library over a-z and A-Z, so a library change fails a test.
rxMeaningfulEscapes :: [Char]
rxMeaningfulEscapes = "bB<>`'"

-- | Apply the rules to a pattern as the builtin would receive it, @(?i)@
-- prefix included.
validatePattern :: String -> Either RegexProblem ()
validatePattern raw =
  case parseRegex (snd (splitCaseFlag raw)) of
    Left err       -> Left (RxParse (oneLine (show err)))
    Right (pat, _) -> maybe (Right ()) (Left . RxEscape) (letterEscape pat)
  where
    oneLine = unwords . lines

-- | The first escape of an ASCII letter that regex-tdfa reads literally.
-- Escapes inside a bracket expression are not 'PEscape' nodes, so they are
-- not visited: inside brackets a backslash is an ordinary POSIX character.
letterEscape :: Pattern -> Maybe Char
letterEscape p = case p of
  PEscape _ c
    | (isAsciiLower c || isAsciiUpper c) && c `notElem` rxMeaningfulEscapes -> Just c
    | otherwise -> Nothing
  PGroup _ q    -> letterEscape q
  POr qs        -> firstJust qs
  PConcat qs    -> firstJust qs
  PQuest q      -> letterEscape q
  PPlus q       -> letterEscape q
  PStar _ q     -> letterEscape q
  PBound _ _ q  -> letterEscape q
  PNonCapture q -> letterEscape q
  PNonEmpty q   -> letterEscape q
  _             -> Nothing
  where
    firstJust = foldr (\q acc -> maybe acc Just (letterEscape q)) Nothing
