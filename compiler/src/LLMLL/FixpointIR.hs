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
  , qualifiersToBraces    -- FIXPOINT-UPGRADE-1
    -- * Predicate emission
  , emitPred
  , emitSort              -- JSON-1: sort-rendering test
  , emitPredParens
    -- * STRLIT literal interning (shared by FixpointEmit + GuardClassifier)
  , strlitConst
  , strlitLen
    -- * Constructor symbols (shared by FixpointEmit; FQ-CTOR-COLLIDE-1)
  , fqCtorSym
    -- * Emission-boundary scope check (FQ-FREEVAR-GUARD-1)
  , predSymbols
  , fqFreeSymbols
    -- * Emission-boundary name check (FQ-NAME-COLLIDE-1)
  , predRawSymbols
  , fqNameCollisions
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
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
  -- JSON-1: the sealed JSON carrier. Same shape as FQList and for the same
  -- reason: no json-* builtin is reflected, so nothing ever constructs a term
  -- at this sort. It exists so a Json binder is declared at an OPAQUE sort
  -- rather than falling through typeToSort's `_ -> FQInt` default, which
  -- declared it as an integer.
  | FQJson           -- ^ opaque JSON carrier (uninterpreted Jsn sort)
  -- FLOAT-LIT-1 (D3): the float carrier, on the JSON-1 pattern. float is
  -- outside Sigma_auto (LLMLL.md §5.3.3) and nothing reflects a float term:
  -- 'buildSortEnv' declares no float binder and a used float payload falls
  -- back (match-payload-sort). The sort exists so a float payload field or
  -- binder is declared at an OPAQUE sort, not at int as typeToSort's default
  -- declared it. Probe: a .fq with a Flt field and binder is accepted bare.
  | FQFloat          -- ^ opaque float carrier (uninterpreted Flt sort)
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
  -- SIGMA-CONST-ARITH-1: only ever built with a constant operand (a numeral
  -- coefficient, or a numeral divisor > 0), so every term stays linear. On the
  -- `int` sort fixpoint's `/` and `mod` are SMT-LIB `div` and `mod`, which equal
  -- Haskell `div` and `mod` for a positive divisor.
  | FQMul  -- ^ * (one operand a numeral)
  | FQDiv  -- ^ / (integer division by a numeral > 0)
  | FQMod  -- ^ mod (by a numeral > 0)
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
  | FQIte FQPred FQPred FQPred        -- ^ MINMAX-FRAG-1: int-valued (if c then a else b)
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
emitSort FQFloat    = "Flt"   -- FLOAT-LIT-1: uninterpreted carrier, probe-verified accepted bare
emitSort FQJson     = "Jsn"   -- JSON-1: uninterpreted carrier, same bare-acceptance path as Lst
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
--
-- FQ-NAME-COLLIDE-1: the map is NOT injective. @a-b@, @a?b@, @a.b@ and @a_b@ all
-- print as @a_b@, and the solver then reads two program values as one. The
-- encoding is kept, so a file with no clash prints unchanged; 'fqNameCollisions'
-- finds each constraint where two names meet in one symbol, and the emitter
-- withdraws the owning function's VC.
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
-- Residual: a binder literally named @ctor_denied@ (or @ctor-denied@) still
-- prints as the constructor symbol. This does not always fail closed. At another
-- sort the solver stops with a sort error, but at the constructor's own sort the
-- binder and the constructor are one value, and a false post was proved
-- (FQ-NAME-COLLIDE-1, row 10). 'fqNameCollisions' rule R3 now flags such a
-- binder, and the emitter withdraws the owning function's VC.
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
-- FQ-ARITH-FLAT-1: an arithmetic chain keeps one outer pair; see 'arithChain'.
emitPred (FQBinArith op l r)  = "(" <> arithChain op l r <> ")"
-- FQ-FLAT-NEST-1: nested conjunctions (and nested disjunctions) are printed as one
-- flat chain. 'conjoin' builds two-operand pairs, so a body with a chain of calls
-- reached liquid-fixpoint as '((((a && b) && c) && d) ...)'. liquid-fixpoint
-- 0.9.6.3.1 itself (not z3) uses memory exponential in that nesting: measured
-- 2026-11-01 on examples/heartbleed/secure-channel/sc-channel.llmll, the emitted
-- file peaked at 4.7-6.8 GB over 50-63 s, and the same constraints printed flat
-- check Safe (304) in 0.9 s at 85 MB. Flattening is associativity only; the
-- predicate is the same. An empty conjunct is 'true' and an empty disjunct is
-- 'false', so dropping them keeps the meaning.
emitPred (FQAnd ps) = case flattenAnd ps of
  []  -> "true"
  qs  -> T.intercalate " && " (map emitPredParens qs)
emitPred (FQOr ps) = case flattenOr ps of
  []  -> "false"
  qs  -> T.intercalate " || " (map emitPredParens qs)
emitPred (FQNot p)            = "(not " <> emitPredParens p <> ")"
emitPred (FQKVar k args)      = "$" <> sanitizeFQId k <> "(" <> T.intercalate "," (map emitPred args) <> ")"
-- PAIR-BOOL-COMP-1: fixpoint parses only a term as an application argument, so a
-- predicate argument (`(pair2 n (n < 0))`, `(ctor_yes (not b))`) crashed the solver.
-- It is emitted as the bool term `(if P then true else false)`; other args unchanged.
emitPred (FQApp f args)       = "(" <> sanitizeFQId f <> " " <> T.unwords (map emitArg args) <> ")"
  where
    emitArg p | propShaped p = "(if " <> emitPredParens p <> " then true else false)"
              | otherwise    = emitPredParens p
    propShaped (FQBinPred {}) = True
    propShaped (FQNot _)      = True
    propShaped (FQAnd (_:_))  = True
    propShaped (FQOr  (_:_))  = True
    propShaped _              = False
emitPred (FQIte c a b)        = "(if " <> emitPredParens c <> " then " <> emitPredParens a <> " else " <> emitPredParens b <> ")"

-- | FQ-FLAT-NEST-1: splice nested 'FQAnd' operands into one list.
flattenAnd :: [FQPred] -> [FQPred]
flattenAnd = concatMap go
  where go (FQAnd qs) = flattenAnd qs
        go q          = [q]

-- | FQ-FLAT-NEST-1: splice nested 'FQOr' operands into one list.
flattenOr :: [FQPred] -> [FQPred]
flattenOr = concatMap go
  where go (FQOr qs) = flattenOr qs
        go q         = [q]

-- | FQ-ARITH-FLAT-1: an arithmetic chain, printed with no outer parentheses.
--
-- liquid-fixpoint's parser costs time exponential in parenthesis depth. At
-- each @(@, 'appliableExprP' tries 'tupleP' first, which reads the whole
-- expression and then fails for want of a comma, and @parens exprP@ reads the
-- same text again (liquid-fixpoint 0.9.6.3.7, src/Language/Fixpoint/Parse.hs
-- lines 987-988). A sum printed with one pair per operation cost 8 CPU s at 18
-- terms, and a 20-term sum stopped @verify@ at its time limit (exit 5); printed
-- flat it checks in 0.04 s. This is the arithmetic counterpart of
-- FQ-FLAT-NEST-1.
--
-- A pair is dropped only where the solver's fixity table (Parse.hs:944-947:
-- @*@ and @/@ at 7, @+@ and @-@ at 6, @mod@ at 5, all left-associative) reads
-- the same term back:
--
--   * a left operand of equal or higher precedence: @(a - b) - c@ prints
--     @a - b - c@, @(a * 2) + b@ prints @a * 2 + b@;
--   * a right operand of strictly higher precedence: @a + (b * 2)@ prints
--     @a + b * 2@;
--   * a right operand with the same associative operator, @+@ or @*@:
--     @a + (b + c)@ prints @a + b + c@, which the solver reads as
--     @(a + b) + c@. That is equal over unbounded @int@, which is the only
--     regrouping this function does. It applies only when every operator on
--     the operand's left spine at that precedence is the same one:
--     @a * ((b / 2) * c)@ keeps its pair, since @a * b / 2 * c@ reads as
--     @((a * b) / 2) * c@.
--
-- @mod@ never joins a chain, on either side: it binds looser than @+@, so
-- @a + b mod 3@ reads as @(a + b) mod 3@. A right operand that is a
-- subtraction, a division or a different operator of the same precedence
-- (@a - (b - c)@, @a * (b / 2)@, @a + (b - c)@) keeps its pair, and so does a
-- looser operand (@(a + b) * 2@). Anything that is not arithmetic prints as
-- before, through 'emitPredParens'.
arithChain :: FQBinOp -> FQPred -> FQPred -> Text
arithChain op l r = arithLeft l <> " " <> emitOp op <> " " <> arithRight r
  where
    arithLeft (FQBinArith o a b)
      | chainOp o, chainOp op, arithPrec o >= arithPrec op = arithChain o a b
    arithLeft e = emitPredParens e
    arithRight (FQBinArith o a b)
      | chainOp o, chainOp op, arithPrec o > arithPrec op = arithChain o a b
      | o == op, op `elem` [FQAdd, FQMul], pureSpine a    = arithChain o a b
    arithRight e = emitPredParens e
    -- The regrouped operand's left spine joins the outer chain, so every
    -- operator on it at this precedence must be 'op' too. Otherwise
    -- @a * ((b / 2) * c)@ would print @a * b / 2 * c@, which the solver reads
    -- as @((a * b) / 2) * c@: not equal under integer division.
    pureSpine (FQBinArith o a _)
      | chainOp o, arithPrec o == arithPrec op = o == op && pureSpine a
    pureSpine _ = True

-- | FQ-ARITH-FLAT-1: the operators that may share a chain. @mod@ is not one.
chainOp :: FQBinOp -> Bool
chainOp o = o `elem` [FQAdd, FQSub, FQMul, FQDiv]

-- | FQ-ARITH-FLAT-1: precedence in liquid-fixpoint's table, for 'chainOp' only.
arithPrec :: FQBinOp -> Int
arithPrec o
  | o `elem` [FQMul, FQDiv] = 7
  | otherwise               = 6

-- | Wrap compound predicates in parentheses to prevent precedence ambiguity.
-- FQAnd/FQOr sub-expressions must be parenthesized when used as operands.
--
-- FQ-ARITH-FLAT-1: 'FQNot' is not wrapped again. 'emitPred' already prints it
-- as @(not p)@, so the wrap gave @((not p))@, one more level that the solver's
-- parser reads twice (see 'arithChain'). One pair delimits it everywhere.
emitPredParens :: FQPred -> Text
emitPredParens p@(FQAnd _) = "(" <> emitPred p <> ")"
emitPredParens p@(FQOr  _) = "(" <> emitPred p <> ")"
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
emitOp FQMul = "*"
emitOp FQDiv = "/"
emitOp FQMod = "mod"

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

-- | FIXPOINT-UPGRADE-1: rewrite the qualifier lines of a @.fq@ text into the
-- syntax of liquid-fixpoint 0.9.6.3.4 and later.
--
-- 'emitQualifier' writes @qualif N(v : int): (p)@, the syntax up to 0.9.6.3.3.
-- From 0.9.6.3.4 the parser reads @qualif N(v : int) { p }@ and rejects the
-- colon. Neither version reads the other form, so the text stays in the old
-- form everywhere (proof artifacts, hashes, @--fq-out@ for an old solver) and
-- 'LLMLL.SolverGuard' applies this function to the file only when a probe of
-- the solver says it needs braces.
--
-- 'emitQualifier' puts each qualifier on one line, and its parameter list
-- holds no @)@, so the first @"): "@ ends the parameters. A line that does not
-- have that shape, including one already in the brace form, is unchanged, so
-- the function is idempotent.
qualifiersToBraces :: Text -> Text
qualifiersToBraces = T.intercalate "\n" . map line . T.splitOn "\n"
  where
    line l
      | "qualif " `T.isPrefixOf` l
      , (params, rest) <- T.breakOn "): " l
      , Just body <- T.stripPrefix "): " rest
      , "(" `T.isPrefixOf` body
      = params <> ") { " <> body <> " }"
      | otherwise = l

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

-- ---------------------------------------------------------------------------
-- FQ-FREEVAR-GUARD-1: the emission-boundary scope check
-- ---------------------------------------------------------------------------

-- | Every symbol a predicate names: a variable, an application head, and the
-- arguments of a kvar. Names come back in EMITTED form, because 'sanitizeFQId'
-- is what the solver reads. Two source names that sanitize to one symbol are one
-- symbol here, which is the collision 'fqCtorSym' documents.
predSymbols :: FQPred -> Set.Set Text
predSymbols p = case p of
  FQTrue           -> Set.empty
  FQFalse          -> Set.empty
  FQLit _          -> Set.empty
  FQVar v          -> Set.singleton (sanitizeFQId v)
  FQNot q          -> predSymbols q
  FQAnd ps         -> Set.unions (map predSymbols ps)
  FQOr  ps         -> Set.unions (map predSymbols ps)
  FQBinPred _ a b  -> predSymbols a `Set.union` predSymbols b
  FQBinArith _ a b -> predSymbols a `Set.union` predSymbols b
  FQKVar _ args    -> Set.unions (map predSymbols args)
  FQApp f args     -> Set.insert (sanitizeFQId f) (Set.unions (map predSymbols args))
  FQIte c a b      -> Set.unions (map predSymbols [c, a, b])

-- | FQ-FREEVAR-GUARD-1. Report, for each constraint, every symbol the constraint
-- names that its own environment does not declare.
--
-- liquid-fixpoint answers @Crash@ ("Constraint with free vars") instead of a
-- verdict when that set is not empty, so a caller must run this before it writes
-- the file. The scope is read and not inferred: 'conEnv' carries the
-- constraint's own binder IDs.
--
-- A symbol is IN SCOPE when one of these is true.
--
--   * A binder in 'conEnv' carries the name.
--   * The file declares it with @constant@. That covers the measure UFs and
--     every interned @strlit_@ name.
--   * The file declares it with @data@: the sort name, a constructor symbol, or
--     a selector field.
--   * The solver interprets it natively. That set is the @theory@ argument,
--     because the emitter decides which theory it uses, and this module does not.
--   * It is the refinement's own bound variable.
--
-- The environment is read as a CLOSURE, and not as the constraint's two
-- refinements alone. A @let@-bound projection puts the free symbol in the
-- refinement of an environment binder, and not in the goal. The narrower reading
-- misses it. Measured on cell c39b of @docs/design/resp-fact-proposal.md@: the
-- solver names @s@ on three constraints, and the narrower reading flags none.
fqFreeSymbols :: Set.Set Text -> FQFile -> [(FQConstraintId, [Text])]
fqFreeSymbols theory f =
    [ (conId c, Set.toList free)
    | c <- fqConstraints f
    , let free = constraintFree c
    , not (Set.null free) ]
  where
    bindMap = Map.fromList [ (bindId b, b) | b <- fqBinds f ]

    declared = Set.unions
      [ Set.fromList [ sanitizeFQId (fqcName k) | k <- fqConstants f ]
      , Set.fromList $ concat
          [ sanitizeFQId (ddName d)
            : [ fqCtorSym cn | (cn, _) <- ddCtors d ]
            ++ [ fqCtorSym cn <> "_" <> T.pack (show i)
               | (cn, flds) <- ddCtors d, i <- [0 .. length flds - 1] ]
          | d <- fqDataDecls f ]
      , theory ]

    reftFree r = Set.delete (sanitizeFQId (reftVar r)) (predSymbols (reftPred r))

    constraintFree c =
      let envBinds = [ b | i <- conEnv c, Just b <- [Map.lookup i bindMap] ]
          inScope  = Set.union declared
                       (Set.fromList [ sanitizeFQId (bindName b) | b <- envBinds ])
          named    = Set.unions
            ( reftFree (conLhs c)
            : reftFree (conRhs c)
            : [ reftFree (bindReft b) | b <- envBinds ] )
      in named Set.\\ inScope

-- ---------------------------------------------------------------------------
-- FQ-NAME-COLLIDE-1: the emission-boundary name check
-- ---------------------------------------------------------------------------

-- | Every name a predicate holds, as the emitter wrote it, BEFORE
-- 'sanitizeFQId': a variable and an application head, recursively, including
-- the arguments of a kvar. 'predSymbols' returns the printed form; this returns
-- the source form, so two spellings that print as one symbol stay apart.
predRawSymbols :: FQPred -> Set.Set Text
predRawSymbols p = case p of
  FQTrue           -> Set.empty
  FQFalse          -> Set.empty
  FQLit _          -> Set.empty
  FQVar v          -> Set.singleton v
  FQNot q          -> predRawSymbols q
  FQAnd ps         -> Set.unions (map predRawSymbols ps)
  FQOr  ps         -> Set.unions (map predRawSymbols ps)
  FQBinPred _ a b  -> predRawSymbols a `Set.union` predRawSymbols b
  FQBinArith _ a b -> predRawSymbols a `Set.union` predRawSymbols b
  FQKVar _ args    -> Set.unions (map predRawSymbols args)
  FQApp f args     -> Set.insert f (Set.unions (map predRawSymbols args))
  FQIte c a b      -> Set.unions (map predRawSymbols [c, a, b])

-- | FQ-NAME-COLLIDE-1. Report, for each constraint, the names that reach the
-- solver as one symbol although the program means two values. 'sanitizeFQId'
-- is not injective, and the emitter's internal names share one namespace with
-- the program's, so the solver can read two values as one and prove a false
-- post. The check reads the constraint and the closure of its environment, as
-- 'fqFreeSymbols' does. Three rules:
--
--   * R1, different source spellings. Two different raw names, among the
--     environment binders and the variables and application heads of every
--     refinement, that 'sanitizeFQId' maps to one symbol (@a-b@ and @a_b@).
--   * R2, one name bound twice. Two binders of the environment with one raw
--     name (a parameter @result@ beside the result binder, a parameter spelled
--     like a fresh @_bv_@ name). A raw name that holds @$@ is exempt: the
--     @.llmll@ lexer never produces @$@, so such a binder is internal, and
--     nested matches legitimately repeat the @x$tag@ binder. The JSON-AST
--     reader refuses @$@ in a binder, which is what makes the exemption sound.
--   * R3, a binder that is a declared symbol. An environment binder whose
--     printed name is a @constant@ (a measure, an interned @strlit_@), a
--     constructor symbol or a selector.
--
-- Each flagged constraint comes back with the clashing names, raw, for the
-- diagnostic. A file with no clash returns @[]@.
fqNameCollisions :: FQFile -> [(FQConstraintId, [Text])]
fqNameCollisions f =
    [ (conId c, names)
    | c <- fqConstraints f
    , let names = clashes c
    , not (null names) ]
  where
    bindMap = Map.fromList [ (bindId b, b) | b <- fqBinds f ]

    declared = Set.unions
      [ Set.fromList [ sanitizeFQId (fqcName k) | k <- fqConstants f ]
      , Set.fromList $ concat
          [ fqCtorSym cn
            : [ fqCtorSym cn <> "_" <> T.pack (show i) | i <- [0 .. length flds - 1] ]
          | d <- fqDataDecls f, (cn, flds) <- ddCtors d ] ]

    clashes c =
      let envBinds = [ b | i <- conEnv c, Just b <- [Map.lookup i bindMap] ]
          raw = Set.unions
            ( Set.fromList (map bindName envBinds)
            : predRawSymbols (reftPred (conLhs c))
            : predRawSymbols (reftPred (conRhs c))
            : [ predRawSymbols (reftPred (bindReft b)) | b <- envBinds ] )
          byImage = Map.fromListWith Set.union
            [ (sanitizeFQId n, Set.singleton n) | n <- Set.toList raw ]
          r1 = concat [ Set.toList ns | ns <- Map.elems byImage, Set.size ns > 1 ]
          r2 = [ n | (n, k) <- Map.toList (Map.fromListWith (+)
                                 [ (bindName b, 1 :: Int) | b <- envBinds ])
                   , k > 1, not ("$" `T.isInfixOf` n) ]
          r3 = [ bindName b | b <- envBinds
                            , sanitizeFQId (bindName b) `Set.member` declared ]
      in Set.toList (Set.fromList (r1 ++ r2 ++ r3))
