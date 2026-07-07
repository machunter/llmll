-- |
-- Module      : LLMLL.FixpointIR
-- Description : Intermediate representation for liquid-fixpoint .fq constraint files.
--
-- D4: Decoupled verification backend.
-- Rather than integrating LiquidHaskell as a GHC plugin (fragile, version-locked),
-- we emit .fq constraints directly from the LLMLL typed AST and run liquid-fixpoint
-- as a standalone binary.
--
-- Coverage: QF linear integer arithmetic only.
-- Non-linear sites are flagged as HProofRequired and skipped (D3).

module LLMLL.FixpointIR
  ( -- * Sorts
    FQSort(..)
    -- * Predicates
  , FQPred(..)
  , FQBinOp(..)
    -- * Refinement type
  , FQReft(..)
    -- * Binders (environment entries)
  , FQBind(..)
  , FQBindId
    -- * Constraints
  , FQConstraint(..)
  , FQConstraintId
    -- * Uninterpreted-function constants (NIW)
  , FQConstant(..)
    -- * Qualifiers
  , FQQualifier(..)
    -- * Data declarations (ADT sorts)
  , FQDataDecl(..)
    -- * Top-level .fq file
  , FQFile(..)
  , emptyFQFile
    -- * Emission to text
  , emitFQFile
    -- * Predicate emission
  , emitPred
  , emitPredParens
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import Data.Char (isAlphaNum)

-- ---------------------------------------------------------------------------
-- Sorts
-- ---------------------------------------------------------------------------

-- | Supported liquid-fixpoint base sorts (linear arithmetic fragment).
-- NIW (v0.12): FQStr/FQList are opaque carrier sorts for the measure class
-- (REF-META-3 §4.2) — values are uninterpreted; only their integer images
-- under strLen/listLen participate in constraints.
data FQSort
  = FQInt            -- ^ int
  | FQBool           -- ^ bool
  | FQUnit           -- ^ unit (for functions returning ())
  | FQStr            -- ^ opaque string carrier (built-in Str sort)
  | FQList           -- ^ opaque list carrier (uninterpreted Lst sort)
  | FQData Text      -- ^ named ADT sort, e.g. Color
  | FQDataApp Text [FQSort]  -- ^ PAIR-RET: applied (parametric) datatype sort, e.g. (Pair2 int int)
  | FQTyVar Int      -- ^ PAIR-RET: polymorphic field tyvar @(n) inside a parametric data decl
  deriving (Show, Eq)

-- ---------------------------------------------------------------------------
-- Predicates
-- ---------------------------------------------------------------------------

data FQBinOp
  = FQGe   -- ^ >=
  | FQGt   -- ^ >
  | FQLe   -- ^ <=
  | FQLt   -- ^ <
  | FQEq   -- ^ =
  | FQNeq  -- ^ /=
  | FQAdd  -- ^ +
  | FQSub  -- ^ -
  deriving (Show, Eq)

data FQPred
  = FQTrue
  | FQFalse
  | FQVar Text                        -- ^ variable reference, e.g. "v", "n"
  | FQLit Integer                     -- ^ integer literal
  | FQBinPred FQBinOp FQPred FQPred  -- ^ comparison: p1 >= p2
  | FQBinArith FQBinOp FQPred FQPred -- ^ arithmetic: p1 + p2
  | FQAnd [FQPred]
  | FQOr  [FQPred]
  | FQNot FQPred
  | FQKVar Text [FQPred]              -- ^ $k0(v) — wf constraint variable
  | FQApp Text [FQPred]               -- ^ NIW: uninterpreted function application, e.g. (strLen s)
  deriving (Show, Eq)

-- ---------------------------------------------------------------------------
-- Refinement type
-- ---------------------------------------------------------------------------

-- | A liquid-fixpoint refinement type: { v : sort | pred }
data FQReft = FQReft
  { reftVar  :: Text    -- ^ refinement variable name (usually "v")
  , reftSort :: FQSort
  , reftPred :: FQPred
  } deriving (Show, Eq)

-- ---------------------------------------------------------------------------
-- Binders
-- ---------------------------------------------------------------------------

type FQBindId = Int

-- | Environment binder: bind N name : { v : sort | pred }
data FQBind = FQBind
  { bindId   :: FQBindId
  , bindName :: Text
  , bindReft :: FQReft
  } deriving (Show, Eq)

-- ---------------------------------------------------------------------------
-- Constraints
-- ---------------------------------------------------------------------------

type FQConstraintId = Int

-- | A subtyping constraint: env ⊢ lhs <: rhs
data FQConstraint = FQConstraint
  { conId  :: FQConstraintId
  , conEnv :: [FQBindId]     -- ^ binder IDs in scope
  , conLhs :: FQReft
  , conRhs :: FQReft
  , conTag :: [Text]         -- ^ diagnostic metadata (function name, clause)
  } deriving (Show, Eq)

-- ---------------------------------------------------------------------------
-- Qualifiers
-- ---------------------------------------------------------------------------

-- | A qualifier template: qualif Name(params): body
data FQQualifier = FQQualifier
  { qualName   :: Text
  , qualParams :: [(Text, FQSort)]  -- ^ (param name, sort)
  , qualBody   :: FQPred
  } deriving (Show, Eq)

-- ---------------------------------------------------------------------------
-- Data type declarations (ADT sorts)
-- ---------------------------------------------------------------------------

-- | data Name arity = [ Ctor arity | ... ]
data FQDataDecl = FQDataDecl
  { ddName  :: Text
  , ddArity :: Int
  , ddCtors :: [(Text, [FQSort])]  -- ^ (ctor name, field sorts) — COMP-4 (a): real arities
  } deriving (Show, Eq)

-- ---------------------------------------------------------------------------
-- Top-level .fq file
-- ---------------------------------------------------------------------------

-- | NIW: an uninterpreted-function constant declaration.
-- Rendered as: constant name : (func(0 , [argSort; retSort]))
data FQConstant = FQConstant
  { fqcName :: Text
  , fqcArgs :: [FQSort]
  , fqcRet  :: FQSort
  } deriving (Show, Eq)

data FQFile = FQFile
  { fqConstants   :: [FQConstant]
  , fqDataDecls   :: [FQDataDecl]
  , fqQualifiers  :: [FQQualifier]
  , fqBinds       :: [FQBind]
  , fqConstraints :: [FQConstraint]
  } deriving (Show, Eq)

emptyFQFile :: FQFile
emptyFQFile = FQFile [] [] [] [] []

-- ---------------------------------------------------------------------------
-- Emission to .fq text
-- ---------------------------------------------------------------------------

emitFQFile :: FQFile -> Text
emitFQFile f = T.unlines $
    map emitConstant  (fqConstants f)
 ++ map emitDataDecl  (fqDataDecls f)
 ++ map emitQualifier (fqQualifiers f)
 ++ map emitBind      (fqBinds f)
 ++ map emitConstraint (fqConstraints f)

emitSort :: FQSort -> Text
emitSort FQInt      = "int"
emitSort FQBool     = "bool"
emitSort FQUnit     = "unit"
emitSort FQStr      = "Str"   -- liquid-fixpoint built-in string sort (opaque under path (a))
emitSort FQList     = "Lst"   -- uninterpreted carrier sort (probe-verified accepted bare)
emitSort (FQData n) = n
-- PAIR-RET: an applied parametric sort prints as `(TyCon arg ...)`; a field tyvar
-- prints as liquid-fixpoint's `@(n)` De-Bruijn sort variable. Both spike-confirmed
-- accepted by the pinned fixpoint (polymorphic `data Pair2 2`, applied `(Pair2 int int)`).
emitSort (FQDataApp n args) = "(" <> n <> " " <> T.unwords (map emitSort args) <> ")"
emitSort (FQTyVar i)        = "@(" <> T.pack (show i) <> ")"

-- | NIW: constant strLen : (func(0 , [Str; int]))
emitConstant :: FQConstant -> Text
emitConstant c =
  "constant " <> sanitizeFQId (fqcName c) <> " : (func(0 , ["
  <> T.intercalate "; " (map emitSort (fqcArgs c ++ [fqcRet c]))
  <> "]))"

-- | F-NIW-3: map an LLMLL identifier to a liquid-fixpoint-legal one. The LLMLL
-- lexer admits '-', '.', '?' in names (Lexer.hs:314-315), but liquid-fixpoint's
-- identifier lexer accepts only [A-Za-z0-9_] — a hyphenated function/param/var
-- name otherwise crashes the solver at parse ("unexpected '-'"). Any non-legal
-- char maps to '_'. Identity on already-legal names (the whole existing corpus
-- plus internal _bv_/call_ names), so .fq output is byte-identical except where a
-- name would otherwise be rejected. Applied at this single emission chokepoint so
-- binders and references mangle identically and still resolve.
sanitizeFQId :: Text -> Text
sanitizeFQId = T.map (\c -> if isAlphaNum c || c == '_' then c else '_')

emitPred :: FQPred -> Text
emitPred FQTrue               = "true"
emitPred FQFalse              = "false"
emitPred (FQVar v)            = sanitizeFQId v
emitPred (FQLit n)            = T.pack (show n)
-- BOOL-FRAG (v0.14.15): fixpoint accepts `not` only in predicate position, not as an
-- operand of (=)/(!=) — `result = (not b)` crashes ("free vars [not]") while &&/|| are
-- tolerated there. For bools, X = ¬Y ⟺ X ≠ Y, so push the negation through the
-- (dis)equality; this recurses, so nested `not`s collapse. `not` on an int is ill-typed
-- (TypeCheck rejects), so a FQNot operand of (=)/(!=) is always bool → the flip is sound.
emitPred (FQBinPred FQEq  l (FQNot r)) = emitPred (FQBinPred FQNeq l r)
emitPred (FQBinPred FQEq  (FQNot l) r) = emitPred (FQBinPred FQNeq l r)
emitPred (FQBinPred FQNeq l (FQNot r)) = emitPred (FQBinPred FQEq  l r)
emitPred (FQBinPred FQNeq (FQNot l) r) = emitPred (FQBinPred FQEq  l r)
emitPred (FQBinPred op l r)   = "(" <> emitPredParens l <> " " <> emitOp op <> " " <> emitPredParens r <> ")"
emitPred (FQBinArith op l r)  = "(" <> emitPredParens l <> " " <> emitOp op <> " " <> emitPredParens r <> ")"
emitPred (FQAnd [])           = "true"
emitPred (FQAnd ps)           = T.intercalate " && " (map emitPredParens ps)
emitPred (FQOr  [])           = "false"
emitPred (FQOr  ps)           = T.intercalate " || " (map emitPredParens ps)
emitPred (FQNot p)            = "(not " <> emitPredParens p <> ")"
emitPred (FQKVar k args)      = "$" <> sanitizeFQId k <> "(" <> T.intercalate "," (map emitPred args) <> ")"
emitPred (FQApp f args)       = "(" <> sanitizeFQId f <> " " <> T.unwords (map emitPredParens args) <> ")"

-- | Wrap compound predicates in parentheses to prevent precedence ambiguity.
-- FQAnd/FQOr/FQNot sub-expressions must be parenthesized when used as operands.
emitPredParens :: FQPred -> Text
emitPredParens p@(FQAnd _) = "(" <> emitPred p <> ")"
emitPredParens p@(FQOr  _) = "(" <> emitPred p <> ")"
emitPredParens p@(FQNot _) = "(" <> emitPred p <> ")"
emitPredParens p            = emitPred p

emitOp :: FQBinOp -> Text
emitOp FQGe  = ">="
emitOp FQGt  = ">"
emitOp FQLe  = "<="
emitOp FQLt  = "<"
emitOp FQEq  = "="
emitOp FQNeq = "/="
emitOp FQAdd = "+"
emitOp FQSub = "-"

emitReft :: FQReft -> Text
emitReft r =
  "{ " <> sanitizeFQId (reftVar r) <> " : " <> emitSort (reftSort r)
  <> " | " <> emitPred (reftPred r) <> " }"

emitBind :: FQBind -> Text
emitBind b =
  "bind " <> T.pack (show (bindId b))
  <> " " <> sanitizeFQId (bindName b)
  <> " : " <> emitReft (bindReft b)

emitConstraint :: FQConstraint -> Text
emitConstraint c = T.unlines
  [ "constraint:"
  , "  env [" <> T.intercalate "; " (map (T.pack . show) (conEnv c)) <> "]"
  , "  lhs " <> emitReft (conLhs c)
  , "  rhs " <> emitReft (conRhs c)
  , "  id " <> T.pack (show (conId c))
  -- liquid-fixpoint tagP expects [Int], not [Text]. Emit constraint ID as tag
  -- for traceability. Human-readable tags live in ConstraintTable (DiagnosticFQ).
  , "  tag [" <> T.pack (show (conId c)) <> "]"
  ]

emitQualifier :: FQQualifier -> Text
emitQualifier q =
  "qualif " <> sanitizeFQId (qualName q)
  <> "(" <> T.intercalate ", " (map emitParam (qualParams q)) <> ")"
  <> ": (" <> emitPred (qualBody q) <> ")"
  where
    emitParam (nm, srt) = sanitizeFQId nm <> " : " <> emitSort srt

emitDataDecl :: FQDataDecl -> Text
emitDataDecl d =
  "data " <> sanitizeFQId (ddName d) <> " " <> T.pack (show (ddArity d))
  <> " = [" <> T.concat (map emitCtor (ddCtors d)) <> "]"
  where
    -- liquid-fixpoint's .fq grammar parses the data *type* name with an
    -- uppercase identifier parser (fTyConP), so lowercasing it (the prior
    -- "bug B1" fix) made the declaration line unparseable for every user sum
    -- type AND desynced it from the sort reference site, which preserves case
    -- (emitSort (FQData n) = n, this module). The type name now preserves
    -- source case so declaration and reference agree.
    --
    -- Each constructor is emitted in fixpoint's ADT syntax `| ctor { fields }`.
    -- COMP-4 (a): an admissible sum carries REAL fields (`ctor_i : sort`) so
    -- constructor/selector terms discharge (the field name IS the selector);
    -- inadmissible (recursive) and nullary ctors emit `{ }`. Constructor symbols
    -- and field names stay sanitized lowercase, agreeing with the translation site.
    emitCtor (nm, flds) =
      let cn     = sanitizeFQId (T.toLower nm)
          fields = T.intercalate ", "
            [ cn <> "_" <> T.pack (show i) <> " : " <> emitSort s | (i, s) <- zip [0 :: Int ..] flds ]
      in if null flds then " | " <> cn <> " { }"
                      else " | " <> cn <> " { " <> fields <> " }"
