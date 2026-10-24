-- |
-- Module      : LLMLL.FloatLit
-- Description : FLOAT-LIT-1. The value and range rule for a float literal,
--               shared by the S-expression parser and the JSON-AST reader.
--
-- LLMLL.md §12 (decimal-numbers-proposal Rev 1, R1-3): a FLOAT denotes the
-- exact decimal value its digits and exponent spell, rounded to the nearest
-- double with ties to even. The literal is refused, with diagnostic kind
-- @float-literal-range@, when the rounded magnitude is infinite or when a
-- non-zero decimal value rounds to zero. Subnormal results are accepted.
-- R1-1: a zero-valued literal denotes +0.0 whatever its sign or spelling.
--
-- The two front ends spell literals differently (RFC 8259 for JSON, the §12
-- FLOAT production for S-expressions) but both reach this function with the
-- literal as an exact (sign, coefficient, base-10 exponent) triple, so they
-- accept the same set of values. The exponent is an 'Integer' read from the
-- digit text: a machine-integer exponent wraps (D7, @1e18446744073709551617@
-- read as @10.0@), and this module never sees one.
--
-- Leaf module: no LLMLL imports.
module LLMLL.FloatLit
  ( classifyFloatLit
  , floatLitRangeTag
  , floatLitRangeMessage
  ) where

import Data.Ratio ((%))
import Data.Text (Text)

-- | The diagnostic kind, and the prefix every range message starts with. The
-- S-expression channel recognises a parse failure by this prefix
-- ('LLMLL.Diagnostic.megaparsecToDiagnostic'), and the JSON reader's
-- @extractKind@ by the same text.
floatLitRangeTag :: Text
floatLitRangeTag = "float-literal-range"

-- | The message for a refused literal, given its source spelling and why.
floatLitRangeMessage :: Text -> Text -> Text
floatLitRangeMessage spelling why =
  floatLitRangeTag <> ": the float literal " <> spelling <> " " <> why
  <> " (LLMLL.md §12: a float literal must round to a finite double, and a"
  <> " non-zero literal must not round to 0.0)"

-- | @classifyFloatLit negative coefficient ex@ for the literal whose
-- value is @(-1)^negative * coefficient * 10^ex@, @coefficient >= 0@.
-- 'Right' is the double it denotes; 'Left' is the reason it is refused.
--
-- The two bounds decide a literal without building an enormous rational: a
-- value whose leading digit sits at 10^309 or above exceeds the largest double
-- (about 1.798e308), and one whose leading digit sits below 10^-324 is under
-- half the smallest subnormal (about 2.47e-324), so it rounds to zero. Between
-- the bounds the exact rational is converted with 'fromRational', which GHC
-- rounds to nearest, ties to even.
classifyFloatLit :: Bool -> Integer -> Integer -> Either Text Double
classifyFloatLit negative coefficient ex
  | coefficient == 0 = Right 0.0                       -- R1-1: one zero, +0.0
  | leading > 308    = Left tooLarge
  | leading < (-324) = Left tooSmall
  | isInfinite d     = Left tooLarge
  | d == 0           = Left tooSmall
  | otherwise        = Right (if negative then negate d else d)
  where
    leading  = ex + toInteger (length (show coefficient)) - 1
    exact    = if ex >= 0
                 then fromInteger (coefficient * 10 ^ ex)
                 else coefficient % (10 ^ negate ex)
    d        = fromRational exact :: Double
    tooLarge = "is too large for a 64-bit float"
    tooSmall = "is not zero but rounds to 0.0 in a 64-bit float"
