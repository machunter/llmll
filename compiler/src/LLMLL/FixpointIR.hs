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
    -- * STRLIT literal interning (shared by FixpointEmit + GuardClassifier)
  , strlitConst
  , strlitLen
    -- * Constructor symbols (shared by FixpointEmit; FQ-CTOR-COLLIDE-1)
  , fqCtorSym
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import Data.Char (isAlphaNum, isUpper, ord)
import Numeric (showHex)

-- | STRLIT (Stage 1): the interned nullary Str-constant NAME of a string literal.
-- Each code point is fixed-width 6-hex (@ord c@ ≤ U+10FFFF fits in 6 hex digits),
-- so 'strlitConst' is INJECTIVE and its output lives entirely in the sanitize-
-- stable alphabet @[0-9a-f_]@ — 'sanitizeFQId' (non-injective) is the identity on
-- it, so two distinct literals never collide post-sanitize. A collision would
-- identify distinct literals → a FALSE VERIFY; hence NEVER a hash. The empty
-- string interns to bare @strlit_@. Lives here (not FixpointEmit) so the guard
-- channel (GuardClassifier) can intern literals without an import cycle.
strlitConst :: Text -> Text
strlitConst s = "strlit_" <> T.concat [ pad6 (ord c) | c <- T.unpack s ]
  where pad6 n = T.justifyRight 6 '0' (T.pack (showHex n ""))

-- | STRLIT (Stage 2): the CODE-POINT length encoded in a 'strlitConst' name — the
-- inverse of its fixed-width 6-hex-per-code-point encoding. Equals @T.length s@ =
-- the runtime @string_length@ (code points; an astral char = 1), so length facts
-- agree with the program under evaluation. @strlit_@ (the empty literal) recovers 0.
strlitLen :: Text -> Integer
strlitLen n = fromIntegral ((T.length n - T.length "strlit_") `div` 6)

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
  | FQArr FQSort FQSort      -- ^ LEVER-A1: SMT array sort (index, element), rendered to
                             --   liquid-fixpoint's native map theory sort @(Map_t k v)@
                             --   with interpreted @Map_select@/@Map_store@/@Map_default@
                             --   (probe-proven on the pinned solver stack; see
                             --   docs/design/data-scope-lever-a-feasibility.md §2)
  | FQMapArr                 -- ^ LEVER-A2.1: the map-component array sort. Renders
                             --   IDENTICALLY to @FQArr FQInt FQInt@ (both are
                             --   @(Map_t int int)@ in .fq), but is a DISTINCT
                             --   Haskell value so the emitter can tell a map
                             --   return/component apart from a @bytes[n]@ return
                             --   (which share the concrete array sort). Byte-inert:
                             --   no .fq text changes.
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
-- LEVER-A1: the array sort prints as fixpoint's native map-theory sort. Only
-- int/Str element instantiations are emittable on the pinned solver — its SMT
-- bridge declares the map ops monomorphically (bool elements crash; the map
-- presence encoding is int-0/1 for exactly this reason, proposal §5 Rev 1.1).
emitSort (FQArr k v)        = "(Map_t " <> emitSort k <> " " <> emitSort v <> ")"
emitSort FQMapArr           = "(Map_t int int)"  -- identical text, distinct value

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

-- | The emitted @.fq@ symbol for a datatype constructor (FQ-CTOR-COLLIDE-1).
--
-- Constructor symbols and ordinary binders share one flat namespace in the
-- emitted constraint file. Constructors were previously emitted as the bare
-- lowercasing of their source name, so a parameter or @let@ binder spelled like
-- any in-scope constructor took the same symbol: an @XferState@ with a @Denied@
-- state and a @denied : bool@ flag made liquid-fixpoint fail with a sort error
-- naming a type the function need not even mention. Merely DECLARING the type
-- was enough, since the datatype declaration lands in the same file.
--
-- User constructors are uppercase-initial and therefore get a reserved prefix;
-- the built-in lowercase constructor symbols (@ok@, @err@, @pair2@) are emitted
-- verbatim, because their declaration and use sites both spell them that way.
-- Constructor names are globally unique per module (the typechecker rejects a
-- duplicate within or across type definitions), so the prefix alone separates
-- the namespaces and no type qualification is needed.
--
-- Residual, deliberately accepted: 'sanitizeFQId' maps every illegal character
-- to @_@, so a binder literally named @ctor_denied@ (or @ctor-denied@) would
-- still collide. That is reachable only by naming a binder after the internal
-- convention, and it fails closed as before.
--
-- This is the single definition of the convention. Declaration and every use
-- site route through it, which is what was missing before.
fqCtorSym :: Text -> Text
fqCtorSym nm
  | not (T.null nm), isUpper (T.head nm) = "ctor_" <> sanitizeFQId (T.toLower nm)
  | otherwise                            = sanitizeFQId nm

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
      let cn     = fqCtorSym nm
          fields = T.intercalate ", "
            [ cn <> "_" <> T.pack (show i) <> " : " <> emitSort s | (i, s) <- zip [0 :: Int ..] flds ]
      in if null flds then " | " <> cn <> " { }"
                      else " | " <> cn <> " { " <> fields <> " }"
