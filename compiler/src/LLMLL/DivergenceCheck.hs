-- |
-- Module      : LLMLL.DivergenceCheck
-- Description : R5 "Differential Implementation Pressure" — OBSERVATIONAL
--               increment (stages 1–2). Given N submitted fills for ONE hole,
--               partition them by verify outcome and, over the verified ones,
--               witness observational divergence on a shared probe set Ω.
--
-- Motivation. A single verified fill proves the fill satisfies the contract; it
-- says nothing about whether the contract PINS the behaviour. If two agents can
-- both submit fills that verify yet compute different outputs on some input,
-- the specification is UNDER-CONSTRAINED — it admits more than one intended
-- behaviour. R5 turns that latent slack into an explicit, replayable witness.
--
-- Two-stage pipeline (this module implements stages 1–2 only):
--
--   * Stage 1 — status partition. Bucket the submitted fills by verify outcome
--     {verified, refuted, type-error}. ONLY 'FSVerified' fills carry the
--     divergence signal (a refuted or ill-typed fill is not a competing correct
--     implementation, it is simply wrong).
--
--   * Stage 2 — observational bucketing. Evaluate each verified fill over a
--     shared finite probe set Ω (the cartesian product of small per-parameter
--     value sets — the same "observational over a closed Ω" discipline used by
--     'LLMLL.WeaknessCheck' / 'LLMLL.CDP', reusing the pure evaluator
--     'LLMLL.Contracts.evalExprStaticWith'). Bucket the verified fills by their
--     output-vector over Ω:
--
--       - 1 bucket  → 'VNoDivergenceObserved'. Report EXACTLY that: no
--                     divergence was OBSERVED on Ω. This carries NO
--                     spec-tightness claim — agreement on a finite Ω is not a
--                     proof of behavioural equality (that is stage 3, below).
--       - ≥2 buckets → 'VUnderConstraintWitness', carrying the distinguishing
--                     probe input and the divergent output-vectors — UNLESS the
--                     enclosing function is annotated @(spec-entropy
--                     :intentional)@, read the same way '--cdp' reads it (via
--                     'resolveSpecEntropy'), in which case the divergence is
--                     self-attested by-design and the verdict is
--                     'VSuppressedIntentional'.
--
--   * N = 1 submitted → 'VInsufficientFills' (nothing to compare).
--
-- STAGE 3 (semantic equivalence) is DELIBERATELY OUT OF SCOPE here — see
-- 'semanticEquivalenceStub'. It needs a net-new relational-VC path that is
-- being planned separately; this module only WITNESSES divergence, it never
-- certifies equivalence.
--
-- Faithfulness. This module performs no IO and never invokes the solver. Stage
-- 1 statuses are supplied by the caller (Main.hs owns the type-checker + solver
-- and classifies each fill exactly as '--cdp'/'--weakness-check' classify
-- their candidates); stage 2 is a pure fold over the existing evaluator. The
-- emitted 'divergence_witness' JSON record is standalone and MUST NOT be merged
-- into or overloaded onto the CDP @discriminative_axis@ block.
module LLMLL.DivergenceCheck
  ( -- * Fills & status partition (Stage 1)
    Fill(..)
  , FillStatus(..)
  , fillStatusLabel
  , ClassifiedFill(..)
    -- * Probe set Ω (Stage 2)
  , ProbeInput
  , probeSet
  , probeValuesFor
    -- * Report
  , DivergenceVerdict(..)
  , verdictLabel
  , OutputVector
  , VerifiedBucket(..)
  , DistinguishingWitness(..)
  , DivergenceContext(..)
  , DivergenceReport(..)
  , buildDivergenceReport
    -- * Standalone JSON record
  , divergenceReportJson
    -- * Stage 3 seam (NOT IMPLEMENTED — observational increment only)
  , semanticEquivalenceStub
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Map.Strict as Map
import Data.Aeson (Value(..), object, (.=), toJSON)
import qualified Data.Aeson.Key as K
import qualified Data.List as L

import LLMLL.Syntax
  ( Expr(..), Literal(..), Type(..), Name, SpecEntropy(..) )
import LLMLL.Contracts (FuncEnv, evalExprStaticWith, maxFuel)

-- ---------------------------------------------------------------------------
-- Stage 1 — fills & status partition
-- ---------------------------------------------------------------------------

-- | One submitted fill for a hole: a stable identifier (the checkout token, a
-- scratch-copy label, or a caller-chosen tag) and the filled expression that
-- replaces the hole.
data Fill = Fill
  { fillId   :: Text   -- ^ stable identifier (token / label)
  , fillBody :: Expr   -- ^ the expression written at the hole site
  } deriving (Show, Eq)

-- | Verify outcome for a fill. Determined by the caller (Main.hs) exactly as
-- the CDP / weakness pipelines classify their candidates: type-check first,
-- then run the solver on a body-faithful emission.
data FillStatus
  = FSVerified    -- ^ type-checked AND solver reported SAFE against the contract
  | FSRefuted     -- ^ type-checked but the solver refuted the contract
  | FSTypeError   -- ^ failed the type-checker (or the hole was never filled)
  deriving (Show, Eq)

-- | Wire-line label for a 'FillStatus'.
fillStatusLabel :: FillStatus -> Text
fillStatusLabel FSVerified  = "verified"
fillStatusLabel FSRefuted   = "refuted"
fillStatusLabel FSTypeError = "type-error"

-- | A fill paired with its stage-1 verify status.
data ClassifiedFill = ClassifiedFill
  { cfFill   :: Fill
  , cfStatus :: FillStatus
  } deriving (Show, Eq)

-- ---------------------------------------------------------------------------
-- Stage 2 — the probe set Ω
-- ---------------------------------------------------------------------------

-- | A single probe: one assignment of every parameter name to a literal value
-- expression. The list order follows the parameter order.
type ProbeInput = [(Name, Expr)]

-- | Per-type probe value set. Small, closed, and observational — mirroring the
-- closed §4.3.1 candidate enumeration in 'LLMLL.WeaknessCheck'. The int set
-- includes both 0 and 5 so the canonical R5 witness (a clamp-style fill vs. a
-- constant fill diverging at x=5, lo=0) is reachable, plus a small negative and
-- a large value for boundary coverage.
probeValuesFor :: Type -> [Expr]
probeValuesFor TInt    = map (ELit . LitInt) [0, 1, 5, -1, 42]
probeValuesFor TBool   = [ELit (LitBool True), ELit (LitBool False)]
probeValuesFor TString = [ELit (LitString ""), ELit (LitString "a")]
probeValuesFor TFloat  = [ELit (LitFloat 0.0), ELit (LitFloat 1.0)]
probeValuesFor TUnit   = [ELit LitUnit]
probeValuesFor _       = [ELit (LitInt 0)]  -- opaque carrier: single default

-- | Upper bound on |Ω| so a wide parameter list cannot blow the cartesian
-- product up. The observational signal is a WITNESS, not a proof — a bounded
-- probe grid is sufficient and keeps stage 2 cheap.
probeCap :: Int
probeCap = 64

-- | Build the shared probe set Ω as the (capped) cartesian product of the
-- per-parameter value sets. A nullary parameter list yields the single empty
-- probe (one trivial observation).
probeSet :: [(Name, Type)] -> [ProbeInput]
probeSet params =
  let valueLists = [ [ (n, v) | v <- probeValuesFor t ] | (n, t) <- params ]
  in take probeCap (sequence valueLists)

-- | Evaluate one fill body under one probe using the existing pure evaluator.
-- 'Nothing' means the body did not reduce to a value on that probe (e.g. it
-- calls an un-modelled builtin) — a legitimate, comparable output-vector slot.
evalOnProbe :: FuncEnv -> Expr -> ProbeInput -> Maybe Expr
evalOnProbe fe body probe =
  evalExprStaticWith fe maxFuel (Map.fromList probe) body

-- ---------------------------------------------------------------------------
-- Report types
-- ---------------------------------------------------------------------------

-- | The output-vector of a verified fill: its evaluation result at each probe
-- in Ω, in probe order. Two fills share a bucket iff their vectors are equal.
type OutputVector = [Maybe Expr]

-- | One observational-equivalence class of verified fills over Ω.
data VerifiedBucket = VerifiedBucket
  { vbOutputVector   :: OutputVector  -- ^ shared output-vector over Ω
  , vbFills          :: [Text]        -- ^ fill ids in this bucket (first-seen order)
  , vbRepresentative :: Text          -- ^ representative fill id (the first one)
  } deriving (Show, Eq)

-- | The distinguishing probe: the first probe (in Ω order) at which the
-- verified buckets do not all agree, together with each bucket's output there.
data DistinguishingWitness = DistinguishingWitness
  { dwInput   :: ProbeInput            -- ^ the probe assignment
  , dwOutputs :: [(Text, Maybe Expr)]  -- ^ (bucket representative, its output at the probe)
  } deriving (Show, Eq)

-- | The verdict of the observational analysis.
data DivergenceVerdict
  = VInsufficientFills       -- ^ N = 1 submitted: nothing to compare
  | VNoDivergenceObserved    -- ^ ≤1 verified bucket: no divergence OBSERVED on Ω
  | VUnderConstraintWitness  -- ^ ≥2 verified buckets: spec admits divergent behaviours
  | VSuppressedIntentional   -- ^ ≥2 buckets but (spec-entropy :intentional): by design
  deriving (Show, Eq)

-- | Wire-line label per verdict.
verdictLabel :: DivergenceVerdict -> Text
verdictLabel VInsufficientFills      = "insufficient-fills"
verdictLabel VNoDivergenceObserved   = "no-divergence-observed"
verdictLabel VUnderConstraintWitness = "under-constraint-witness"
verdictLabel VSuppressedIntentional  = "suppressed-intentional"

-- | Everything the pure analysis needs about the hole's enclosing function.
data DivergenceContext = DivergenceContext
  { dcSession     :: Text             -- ^ divergence-session id
  , dcHole        :: Text             -- ^ hole pointer (RFC 6901)
  , dcParams      :: [(Name, Type)]   -- ^ enclosing function parameters (drives Ω)
  , dcSpecEntropy :: SpecEntropy      -- ^ resolved (spec-entropy ...) annotation
  , dcFuncEnv     :: FuncEnv          -- ^ sibling functions available to fills during eval
  }

-- | The standalone divergence report.
data DivergenceReport = DivergenceReport
  { drSession               :: Text
  , drHole                  :: Text
  , drNSubmitted            :: Int
  , drStatusVerified        :: [Text]  -- ^ ids of verified fills
  , drStatusRefuted         :: [Text]  -- ^ ids of refuted fills
  , drStatusTypeError       :: [Text]  -- ^ ids of type-erroring fills
  , drVerifiedBuckets       :: [VerifiedBucket]
  , drVerdict               :: DivergenceVerdict
  , drWitness               :: Maybe DistinguishingWitness
  , drSpecEntropySuppressed :: Bool
  } deriving (Show, Eq)

-- ---------------------------------------------------------------------------
-- Core (pure)
-- ---------------------------------------------------------------------------

-- | Run stages 1–2 over the classified fills. Pure: stage-1 statuses are
-- supplied by the caller and stage 2 folds the existing evaluator over Ω.
buildDivergenceReport :: DivergenceContext -> [ClassifiedFill] -> DivergenceReport
buildDivergenceReport ctx cfs =
  let nSub       = length cfs
      verifiedF  = [ cfFill cf | cf <- cfs, cfStatus cf == FSVerified ]
      refutedIds = [ fillId (cfFill cf) | cf <- cfs, cfStatus cf == FSRefuted ]
      typeErrIds = [ fillId (cfFill cf) | cf <- cfs, cfStatus cf == FSTypeError ]

      -- Stage 2: evaluate each verified fill over the shared Ω.
      probes  = probeSet (dcParams ctx)
      evald   = [ (fillId f, map (evalOnProbe (dcFuncEnv ctx) (fillBody f)) probes)
                | f <- verifiedF ]
      buckets = bucketByVector evald
      nBuckets = length buckets

      intentional = dcSpecEntropy ctx == SpecEntropyIntentional

      (verdict, suppressed, witness)
        | nSub <= 1                    = (VInsufficientFills,     False, Nothing)
        | nBuckets >= 2 && intentional = (VSuppressedIntentional, True,  mkWitness probes buckets)
        | nBuckets >= 2                = (VUnderConstraintWitness, False, mkWitness probes buckets)
        | otherwise                    = (VNoDivergenceObserved,  False, Nothing)
  in DivergenceReport
       { drSession               = dcSession ctx
       , drHole                  = dcHole ctx
       , drNSubmitted            = nSub
       , drStatusVerified        = map fillId verifiedF
       , drStatusRefuted         = refutedIds
       , drStatusTypeError       = typeErrIds
       , drVerifiedBuckets       = buckets
       , drVerdict               = verdict
       , drWitness               = witness
       , drSpecEntropySuppressed = suppressed
       }

-- | Group (fillId, output-vector) pairs into observational-equivalence classes,
-- preserving first-seen order both across buckets and within a bucket.
bucketByVector :: [(Text, OutputVector)] -> [VerifiedBucket]
bucketByVector = L.foldl' ins []
  where
    ins acc (fid, vec) =
      case break (\b -> vbOutputVector b == vec) acc of
        (before, b : after) ->
          before ++ [ b { vbFills = vbFills b ++ [fid] } ] ++ after
        (before, []) ->
          before ++ [ VerifiedBucket vec [fid] fid ]

-- | The first probe at which the buckets disagree, with each bucket's output
-- there. 'Nothing' when there is a single bucket (no disagreement possible).
mkWitness :: [ProbeInput] -> [VerifiedBucket] -> Maybe DistinguishingWitness
mkWitness probes buckets =
  let width      = case buckets of { (b:_) -> length (vbOutputVector b); [] -> 0 }
      disagreeAt i = length (L.nub [ vbOutputVector b !! i | b <- buckets ]) >= 2
  in case filter disagreeAt [0 .. width - 1] of
       (i:_) -> Just DistinguishingWitness
                  { dwInput   = probes !! i
                  , dwOutputs = [ (vbRepresentative b, vbOutputVector b !! i) | b <- buckets ]
                  }
       []    -> Nothing

-- ---------------------------------------------------------------------------
-- Standalone JSON record
-- ---------------------------------------------------------------------------

-- | Emit the standalone @divergence_witness@ record. Deliberately its own
-- top-level object — never folded into the CDP @discriminative_axis@ block.
divergenceReportJson :: DivergenceReport -> Value
divergenceReportJson r = object
  [ "divergence_witness" .= object
      [ "session"     .= drSession r
      , "hole"        .= drHole r
      , "n_submitted" .= drNSubmitted r
      , "status_partition" .= object
          [ "verified"   .= drStatusVerified r
          , "refuted"    .= drStatusRefuted r
          , "type_error" .= drStatusTypeError r
          ]
      , "verified_buckets" .= map bucketJson (drVerifiedBuckets r)
      , "verdict"          .= verdictLabel (drVerdict r)
      , "distinguishing_witness" .= maybe Null witnessJson (drWitness r)
      , "spec_entropy_suppressed" .= drSpecEntropySuppressed r
      ]
  ]

bucketJson :: VerifiedBucket -> Value
bucketJson b = object
  [ "output_vector"  .= map renderOutput (vbOutputVector b)
  , "fills"          .= vbFills b
  , "representative" .= vbRepresentative b
  ]

witnessJson :: DistinguishingWitness -> Value
witnessJson w = object
  [ "input"   .= renderProbe (dwInput w)
  , "outputs" .= [ object [ "representative" .= fid, "output" .= renderOutput o ]
                 | (fid, o) <- dwOutputs w ]
  ]

-- | Render one probe as a name→value object using JSON-native scalars.
renderProbe :: ProbeInput -> Value
renderProbe probe = object [ K.fromText n .= litValue v | (n, v) <- probe ]

-- | A probe input is always a literal; render it as a JSON-native scalar.
litValue :: Expr -> Value
litValue (ELit (LitInt n))    = toJSON n
litValue (ELit (LitFloat f))  = toJSON f
litValue (ELit (LitString s)) = toJSON s
litValue (ELit (LitBool b))   = toJSON b
litValue (ELit LitUnit)       = Null
litValue e                    = String (renderExpr e)

-- | Render an output value. Reduced values render to their surface form; a
-- non-reducing output renders as the bottom marker so the vector length is
-- preserved and buckets stay comparable in the JSON.
renderOutput :: Maybe Expr -> Value
renderOutput Nothing  = String "\8869"  -- ⊥ : did not reduce on this probe
renderOutput (Just e) = String (renderExpr e)

-- | Small surface renderer for evaluator outputs (literals plus the structured
-- value shapes the evaluator produces: pairs and constructor applications).
renderExpr :: Expr -> Text
renderExpr (ELit l)     = renderLit l
renderExpr (EPair a b)  = "(pair " <> renderExpr a <> " " <> renderExpr b <> ")"
renderExpr (EApp f as)  = "(" <> f <> T.concat (map ((" " <>) . renderExpr) as) <> ")"
renderExpr (EVar v)     = v
renderExpr e            = T.pack (show e)

renderLit :: Literal -> Text
renderLit (LitInt n)    = T.pack (show n)
renderLit (LitFloat f)  = T.pack (show f)
renderLit (LitString s) = "\"" <> s <> "\""
renderLit (LitBool b)   = if b then "true" else "false"
renderLit LitUnit       = "unit"

-- ---------------------------------------------------------------------------
-- Stage 3 seam — NOT IMPLEMENTED (observational increment only)
-- ---------------------------------------------------------------------------

-- | R5 STAGE 3 — semantic equivalence — is INTENTIONALLY NOT IMPLEMENTED in
-- this observational increment (stages 1–2 only).
--
-- Stage 2 answers only: "do these two verified fills produce different outputs
-- on the finite probe set Ω?" — an Ω-relative signal that can WITNESS
-- divergence but can never certify equivalence (agreement on Ω is not a proof
-- of ∀-equality; cf. the "observational over a closed Ω" caveat in
-- 'LLMLL.CDP').
--
-- Stage 3 would replace the Ω-relative bucketing with a RELATIONAL
-- verification query — for all inputs satisfying the shared precondition,
-- @fillA(inputs) = fillB(inputs)@ — discharged by the solver via a net-new
-- product/relational-VC emission path (two candidate bodies threaded through a
-- single contract). That path is being designed separately; this stub marks
-- the seam and MUST NOT be mistaken for a decided equivalence.
--
-- Returns 'Nothing' unconditionally: "no stage-3 verdict available".
semanticEquivalenceStub :: Fill -> Fill -> Maybe Bool
semanticEquivalenceStub _ _ = Nothing  -- TODO(R5 stage 3): relational-VC path
