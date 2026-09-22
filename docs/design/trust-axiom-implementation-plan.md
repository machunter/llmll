# TRUST-AXIOM Implementation Plan

> **Status:** Rev 1, REVIEW-READY. Not approved. No code written.
> **Row:** [`docs/compiler-team-roadmap.md`](../compiler-team-roadmap.md) TRUST-AXIOM, G1, `[CT]`, marker **PLAN**.
> **Base:** `11b526a` (v0.23.16).
> **Prior design record:** none. This is the first role on the row.

---

## Restatement

Two builtin axioms enter the solver and appear on no channel of the trust
report. Disclose them as a new per-function trust-channel line. Enumerate the
line from the emitted verification condition, not from a second walk of the
source.

---

## Context located

1. `docs/compiler-team-roadmap.md` row TRUST-AXIOM: the ticket. Marker is
   **PLAN**. Tag is `[CT]` with no `[SPEC]`.
2. `docs/design/INDEX.md`: searched for a TRUST-AXIOM design record. **None
   exists.** The absence is why this plan settles design questions instead of
   citing a settled proposal.
3. `LLMLL.RespFact`, the `FactCategory` declaration: the `FactCodegen`
   constructor. Its comment states the class this row must disclose: *"an AXIOM
   about a sealed builtin, of the same class as `bytes-set`'s
   length-preservation fact, and it is DISCLOSED rather than discharged"*. The
   compiler already names TRUST-AXIOM's own class.
4. `LLMLL.RespFact`, the `AssumedFact` declaration: seven fields, keyed on
   `afTag` and `afArm`.
5. `LLMLL.RespFact`, the `premiseText` helper: FS-STAT-1's rule. An empty
   field reads as a missing value. Name the axiom instead.
6. `LLMLL.FixpointEmit`, the four builtin `CallVC` arms of `bodyToPredM`:
   `bytes-get`, `bytes-set`, `bytes-zero`, `map-get`. These are the axiom sites.
7. `LLMLL.FixpointEmit`, `collectCallSites`: the `BodyVC` traversal to copy.
8. `LLMLL.FixpointEmit`, the `EmitResult` declaration: where a per-function
   emission fact is published to callers.
9. `LLMLL.TrustReport`, `markBodyFallback` and the `trBodyFallback` seed: the
   post-emit stamping precedent this plan follows exactly.
10. `compiler/app/Main.hs`, the four `markBodyFallback` call sites: where the
    new stamp attaches.
11. `LLMLL.TypeCheck`, `checkCalleeAdmissibility`: the full
    `--strict-verified-core` conjunction, which question (d) needed.
12. `LLMLL.Syntax`, the `erOverflowTainted` note: INT-1. **The counter-precedent
    to disclosure-only.** Section (d) answers it.
13. `LLMLL.FixpointEmit`, `injectRangeFacts`: a THIRD assumed-fact family the
    row does not name.

---

## Plan summary

Add a `BuiltinAxiom` row type beside `AssumedFact`. Collect the rows by walking
the `BodyVC` tree that `bodyToPredM` returns. Publish them on `EmitResult`.
Stamp them onto the trust report with a new `markBuiltinAxioms`, called at the
four sites that already call `markBodyFallback`. Render one additive per-entry
JSON key, `builtin_axioms`, and one text line. The change adds no constraint,
so the `.fq` bytes stay identical and every verdict stays identical. The cost is
one new record type, one traversal function, one `EmitResult` field, one stamp
function, and the render code.

---

## (a) Row keying. DECISION: a sibling type, not a widened `AssumedFact`

**Add `BuiltinAxiom` as its own record. Do not widen `AssumedFact`.**

`AssumedFact` is keyed on control-tag coordinates. A builtin axiom has no
control tag and no arm. Three options exist and two fail:

- **Sentinel in `afTag`** fails on the project's own stated rule. The
  `premiseText` helper in `LLMLL.RespFact` says an empty field reads as a missing
  value rather than as an absent obligation. An empty `afTag` would read as a
  lost control tag, not as a fact that never had one. FS-STAT-1 already rejected
  this shape once.
- **`afTag :: Maybe Name`** changes the rendered JSON of every existing row.
  `assumedFactJson` would emit `"tag": null` where RESP-FACT-1 and FS-STAT-1
  consumers read a string. That cost is paid by working consumers for no gain.
- **A sibling record** costs the existing consumers nothing. `markAssumedFacts`
  and `assumedFactJson` are untouched.

Proposed shape, illustrative only:

```
data BuiltinAxiom = BuiltinAxiom
  { baDef       :: Name   -- the function whose evidence rests on the axiom
  , baBuiltin   :: Name   -- "bytes-set", "bytes-zero", "bytes-get", "map-get"
  , baPredicate :: Text   -- the rendered assumed post
  , baCategory  :: Text   -- from factCategoryName FactCodegen
  , baStamp     :: Text   -- "codegen_semantics_version"
  } deriving (Show, Eq)
```

`baCategory` reads `factCategoryName FactCodegen` and is never written as a
literal. `LLMLL.RespFact` states that discipline at the `factCategoryName`
declaration: a reader must tell a proved fact from an assumed one, so the name
is derived at one site.

**`trust_report_version` does not change.** The additive-key precedent is stated
four times in `LLMLL.TrustReport`: `harness_assumptions`, `joint_pbt_witnesses`,
`partial_fns`, and `assumed_facts` itself. Each landed as an additive key with
no version change. `builtin_axioms` is the fifth.

---

## (b) Enumeration. DECISION: walk the emitted `BodyVC`; the seam exists

**The trust report does not need a source re-walk. Three precedents already
carry an emission fact into it.**

`LLMLL.TrustReport` seeds three fields empty and fills them after the fact:

- `trRefutedFns`, filled by `markRefuted`, post-solver.
- `trMeasureNotDecreasingFns`, filled by `markMeasureNotDecreasing`, post-solver.
- `trBodyFallback`, filled by `markBodyFallback`, **post-emit**.

`markBodyFallback` is the exact template. Its data path is:

1. `emitFixpointWithCache` opens an `IORef` accumulator (`bodyFallbackRef`).
2. Emission writes each per-function fact into it.
3. The accumulator drains into `EmitResult` as `erBodyFallbackCauses`.
4. `compiler/app/Main.hs` reads `erBodyFallbackCauses emitR`, builds
   `bodyFallbackMarks`, and passes it to `markBodyFallback`.

Follow it. Add `erBuiltinAxioms :: [(Text, [BuiltinAxiom])]` to `EmitResult`.
Add `markBuiltinAxioms` to `LLMLL.TrustReport`. Call it at the four
`markBodyFallback` call sites in `compiler/app/Main.hs`.

**Collect the rows from the `BodyVC` tree, following `collectCallSites`.** That
function already walks `CallVC` continuations and returns the callee and its
arguments. A sibling walks the same spine, keeps a node whose callee is in the
sealed-builtin table, and renders its `cvPostAssumption`.

**This satisfies the row's constraint, and the distinction is not a word game.**
The row forbids re-deriving the disclosure. A `BodyVC` walk does not re-derive:
the tree is the output of the axiom-emitting arms. A `CallVC "bytes-zero"` node
exists in that tree **only because** the `bytes-zero` arm of `bodyToPredM` built
it. Delete the arm and the node goes, so the row goes. That coupling is
mechanical and the negative control below measures it.

A source re-walk inside `LLMLL.TrustReport` would be the forbidden shape, for a
concrete reason rather than a stylistic one. Emission is activation-gated:
`bodyToPredFromR` builds a `callNames` set and hoists only `bytes-get`,
`bytes-set` and `map-get`. A `BodyVC` walk inherits that gate at no cost. A
source re-walk would have to mirror the gate, and a mirrored gate drifts. The
project has a named precedent for exactly that drift: `LLMLL.FixpointEmit`
records at the `TypeAdmissibility` note that the checker's guard and the
emitter's gate were once mirrored functions, that they disagreed, and that the
repair was to make them one function.

---

## (c) Population: measured, three families, and the row names only part of one

I enumerated every builtin `CallVC` construction in `LLMLL.FixpointEmit` rather
than accepting the row's two examples.

### Family A: the `bytesLen` axioms. IN SCOPE. The row names both.

| Site | Assumed post | Axiom conjunct |
|---|---|---|
| `bytes-set` arm | `r = Map_store(b,i,v) ∧ bytesLen(r) = bytesLen(b)` | conjunct 2, length preservation |
| `bytes-zero` arm | `r = Map_default(0) ∧ bytesLen(r) = n` | conjunct 2, constructor axiom |

**The set is complete at two.** I checked the other two builtin arms: the
`bytes-get` post is `r = Map_select(b,i)` and the `map-get` post is
`r = Map_select(vl,k)`. Neither carries a `bytesLen` conjunct. The row's pair is
the whole `bytesLen` family.

### Family B: the exact-reflection conjuncts. IN SCOPE. The row does not name them.

Every one of the four arms equates a fresh result variable to a theory term:
`Map_select(b,i)`, `Map_store(b,i,v)`, `Map_default(0)`, `Map_select(vl,k)`.

Each is valid for the same reason family A is valid: codegen emits the operation
the term reflects. Each rides the same `codegen_semantics_version` stamp. Under
the row's own criterion (an assumed fact about a sealed builtin that reaches
the solver on no reporting channel), family B qualifies. Excluding it would disclose
the length half of a `bytes-set` post and stay silent on the store half.

**Granularity: one row per `(def, builtin)`, not per conjunct.** The predicate
field carries the whole rendered post. This covers families A and B with one row
each and keeps the row count equal to the builtin-occurrence count.

### Family C: the ground range facts. OUT OF SCOPE. File a follow-on row.

`injectRangeFacts` conjoins ground facts into the constraint left-hand side:

- `m(t) >= 0` for every measure term (REF-META-2 §4, family 1).
- `0 ≤ Map_select(arr,i) ≤ 255` when `arr` is bytes-rooted (family 2).
- `0 ≤ Map_select(arr,k) ≤ 1` when `arr` is bool-value-rooted (LEVER-A2.2).

These are assumed facts about the sealed representation and they belong to the
row's class. They are **out of scope for this landing** because the plumbing
differs, not because they are exempt. `injectRangeFacts` runs on the assembled
`FQConstraint`, after the `BodyVC` tree is built, so a `BodyVC` walk cannot see
them. They need their own accumulator at the `injectRangeFacts` seam.

Naming them here is deliberate. If the row closes claiming the builtin-axiom
channel is complete, that claim is false while family C is undisclosed.

### One candidate refuted

`LLMLL.md` §988 claims a bool-valued map read carries a ground `0 ≤ select ≤ 1`
fact. `injectRangeFacts` excludes `$val`-suffixed roots from the byte-range arm,
which looked like spec drift. **It is not drift.** A separate `boolValRooted`
arm in the same function supplies the `{0,1}` fact at the value sort. The spec
and the compiler agree. No finding.

### Scope exclusion confirmed

FACT-AG-LEN stays excluded, per the row. Stage 2 inherited the silence and
Stage 3 does not close it.

---

## (d) `--strict-verified-core`. DECISION: disclosure-only, on different grounds

**Recommendation: disclosure-only. The reasoning in the task brief is partly
wrong, and the correct argument is stronger.**

### Correction 1: `refutedClosure` is the wrong citation

The brief asked me to check the claim against `TrustReport.hs:589`. That
function is `refutedClosure`. Its own comment scopes it: it is the refusal set
for **conjunct (c)** and it returns refuted functions plus their transitive
callers. It is about disproved bodies. It says nothing about assumed facts and
neither supports nor refutes the claim.

The admission conjunction lives at `checkCalleeAdmissibility` in
`LLMLL.TypeCheck`:

```
isVerifiedLevel(erDisplayLevel) ∧ erBodyFaithful ∧ ¬erOverflowTainted
  ∧ erVerifiedHash present ∧ fragment-pure
```

### Correction 2: a counter-precedent exists and the brief did not cite it

The brief argued disclosure-only because RESP-FACT-1 and FS-STAT-1 shipped
disclosure-only. **That argument is not decisive, because INT-1 went the other
way.** `erOverflowTainted` marks verified evidence that is sound only modulo the
Int64 overflow gap, and `--strict-verified-core` refuses it. `LLMLL.Syntax` states
this at the `erOverflowTainted` note; `LLMLL.TypeCheck` enforces it with the
`not (erOverflowTainted er)` conjunct. So the project already composes one
trust-channel dependency into admission. Two disclosure-only precedents and one
admission-gating precedent do not settle the question by counting.

### The deciding difference

`erOverflowTainted` marks a fact that **can be false on a correct toolchain**. An
LLMLL program can overflow Int64, the verification condition does not catch it,
and the verdict is then wrong. Refusing it is a soundness repair.

The bytes axioms cannot be false on a correct toolchain. A store preserves
length and codegen emits a store. They fail only if codegen is wrong, which is
the condition `codegen_semantics_version` exists to track. The two cases are not
the same kind of dependency.

### The decisive consequence

Family B rests on the identical trust channel as family A. If an axiom taint
gated `--strict-verified-core`, consistency forces tainting every `Map_select`
reflection too. That removes the **entire array class** from strict-core
admission. That is a capability deletion, not a disclosure, and it would undo
what LEVER-A shipped across v0.14.33 to v0.14.51.

### What would flip this

One condition: if the project decides `codegen_semantics_version` is evidence of
an unaudited gap rather than a tracked stamp, then every codegen-faithfulness
fact becomes INT-1-shaped and admission gating follows for all of them at once.
That is a language-team question about the stamp, not a question about this row,
and it is larger than TRUST-AXIOM.

**I am making this call as the engineer.** The user may prefer to adjudicate it,
given INT-1 exists. The tag convention (`[CT]` with no `[SPEC]`) agrees with
disclosure-only but is the weakest of the three arguments and should not carry
the decision by itself.

---

## Affected surface

**`compiler/src/LLMLL/FixpointEmit.hs`**
- The `EmitResult` declaration: add `erBuiltinAxioms :: [(Text, [BuiltinAxiom])]`.
- A new `collectBuiltinAxioms`, sibling to `collectCallSites`, same spine walk.
- A sealed-builtin table naming the four arms. One site, so the collector and
  the emitting arms cannot disagree about membership.
- `emitFixpointWithCache`: one `IORef` accumulator, mirroring `bodyFallbackRef`.
- Export list: add `BuiltinAxiom(..)` and `collectBuiltinAxioms`.

**`compiler/src/LLMLL/TrustReport.hs`**
- `TrustEntry`: add `teBuiltinAxioms :: [BuiltinAxiom]`.
- The `buildTrustReport` entry seed: `teBuiltinAxioms = []`, with the
  `markBuiltinAxioms post-emit` comment matching the `trBodyFallback` line.
- `markBuiltinAxioms`: sibling of `markAssumedFacts`.
- `builtinAxiomJson`: sibling of `assumedFactJson`.
- The per-entry JSON emitter: additive `builtin_axioms` key, emitted only when
  the list is non-empty, matching how `assumed_facts` is emitted.
- The text renderer: one line per row, beside the `assumed_facts` line.

**`compiler/app/Main.hs`**
- Four `markBuiltinAxioms` insertions at the existing `markBodyFallback` call
  sites: the obligation-report path, the proof-artifact path, the CDP
  post-solver path, and the strict-core path.

**`compiler/test/Spec.hs`**: new hspec cases, listed below.

**`scripts/tests/`**: new pytest cases, listed below.

**`docs/llmll-ast.schema.json`**: **no change.** This is a report shape, not an
AST node shape.

**`LLMLL.md`**: no change in this patch. The documentation-lead handles §5.4 and
§13.12 wording after the commit, per DOC-CONSOLIDATE.

---

## Verification impact

- **Solver-time delta: zero.** The change emits no constraint and no fact. It
  reads the `BodyVC` tree after emission.
- **New obligations: zero.** No PROVE-polarity anything. The rows are disclosure.
- **`.fq` byte-identity: REQUIRED, and this change can meet it.** FACT-AG-LEN
  Stage 2 could not, because a fresh axiom binder shifted the body counter. This
  change mints no binder. **Any `.fq` byte difference is a defect, not an
  expected effect.** That is the cheapest available gate and it is exact.
- **Verification fragment: unchanged.** Stays in QF-LIA. No term is added.
- **Trust-model effect: disclosure only.** No tier moves. No function newly
  falls back. `--strict-verified-core` admission is unchanged, per (d).
- **`checker_soundness_version`: no change.** No rule changes.
- **Evidence freshness: no change.** The evidence hash folds contract
  augmentation, which this patch does not touch, so
  `downgradeStaleVerifiedSidecar` behaves identically.

---

## Performance budget

- **GHC fan-out:** `FixpointEmit.hs` and `TrustReport.hs` are both large and both
  widely imported. Changing `EmitResult` and `TrustEntry` recompiles their
  dependents, which includes `Main.hs`, `ObligationAssembly.hs`, `PBT.hs` and
  `ProofArtifact.hs`. Estimate a full rebuild of the dependent set. This is the
  dominant cost of the patch and it is a build cost, not a runtime cost.
- **Compiler runtime:** one extra traversal of each `BodyVC` spine, per
  function, bounded by the tree the emitter just built. Below measurement noise.
- **Test-suite runtime:** the new cases are unit-level. Estimate under one
  second added.
- **`.fq` size:** zero, by the byte-identity requirement above.
- **Trust-report JSON size:** grows by one array per function that uses a bytes
  or map builtin. Zero for every other function, because the key is omitted when
  the list is empty.
- **ProofCache / VerifiedCache hit rate:** unchanged. No hashed input moves.

---

## Contract plan

**This change lands nothing in the provable fragment.** It adds Haskell compiler
code and a report key. It defines no LLMLL `def`, so there is no `pre` or `post`
to write and no refuting body to construct.

---

## Test plan

Baseline, measured at base `11b526a` on 2026-09-21:

- **pytest: 338 tests collected** (`python3 -m pytest scripts/tests/
  --collect-only -q`). Measured by me at plan time.
- **hspec: 2034 examples, 0 failures.** This figure comes from the v0.23.16
  release gate on 2026-09-21, not from a run at plan time. **Re-measure on the
  merge base at branch time before trusting it.**

### hspec, `compiler/test/Spec.hs`: 8 new examples

1. `collectBuiltinAxioms` on a `bytes-zero` body returns one row naming
   `bytes-zero` with the `bytesLen` conjunct present in the predicate.
2. Same, on a `bytes-set` body, for the length-preservation conjunct.
3. Same, on a `bytes-get` body: family B, reflection conjunct only.
4. Same, on a `map-get` body: family B.
5. **Negative:** an arithmetic body with no bytes or map operation returns the
   empty list. This pins the activation gate.
6. `markBuiltinAxioms` attaches a row to the entry whose name matches and to no
   other entry. Mirror the existing `markAssumedFacts` test.
7. `builtinAxiomJson` renders the five fields, and `baCategory` reads
   `codegen-determined`.
8. The per-entry JSON omits `builtin_axioms` entirely when the list is empty.

Note for the implementer: `bodyToPredFrom` is the exported test entry point and
takes no `mRet`, so it cannot reify `bytes-zero`. `LLMLL.FixpointEmit` says so at
the un-reified `bytes-zero` fall-through. Case 1 must drive the reified form or
go through `bodyToPredFromR`.

### pytest, `scripts/tests/`: 3 new tests

1. `llmll verify --trust-report` on `examples/bytes-bounds/zero-buffer.llmll`
   prints a line naming `bytes-zero` and `codegen-determined`. This fixture is
   the construction-class artifact FACT-AG-LEN Stage 2 added; it exists.
2. The same command with `--json` emits `builtin_axioms` under that function's
   entry, and `trust_report_version` is unchanged from the base value.
3. **Negative:** a bytes-free example emits no `builtin_axioms` key at all.

Search both suites before claiming a pin is absent. This repository has been
wrong in that direction before.

---

## Gate

**Primary, and it is exact: `.fq` byte-identity across the whole corpus.** The
change adds no constraint. Run the FALLBACK-CENSUS-1 sweep with `--jobs 1`,
passing the compiler as an absolute path. Every `.fq` must be byte-identical and
every verdict must be identical. A single differing byte means the patch touched
emission, which it must not.

Normalize the `-o` output directory as well as the tree path before diffing the
sweep captures. An un-normalized output path produces one spurious differing
line per file.

**Secondary: the disclosure appears.** `verify --trust-report` on
`examples/bytes-bounds/zero-buffer.llmll` names `bytes-zero` and its axiom.
Today the same command prints `post: verified (liquid-fixpoint)` and names the
lemma nowhere.

---

## Negative control

The gate above proves the row appears. It does not prove the row is **driven by
the axiom site**. A disclosure that is re-derived from the source would pass the
gate and fail the row's actual requirement. Two controls separate the cases.

**Control 1: delete the axiom conjunct.** Remove the `bytesLen(r) = n` conjunct
from the `bytes-zero` arm's post. Rebuild. Two effects must occur together:

- The disclosure row **disappears**.
- `zeros8` flips SAFE to REFUTED.

The second effect is the measurement FACT-AG-LEN Stage 2 already used, so it is
a known-good probe. If the row survives the conjunct's deletion, the enumeration
is re-derived and the patch fails the row's constraint. Restore the conjunct
after the measurement.

**Control 2: the activation gate.** A bytes-free and map-free program must
produce zero axiom rows and an unchanged report. This proves the change is inert
off the bytes and map path, and that the `BodyVC` walk inherited the gate rather
than mirroring it.

Before running control 1, copy the pre-change binary aside. `stack build`
overwrites the install root, and the negative half must run against the copy.
`stack exec` from the repository root runs the wrong compiler; set the path from
`stack path --local-install-root` and confirm with `llmll version`.

---

## Rollback

Single revert. The patch adds a record type, a traversal, one `EmitResult`
field, one `TrustEntry` field, one stamp and the render code. Nothing is
removed and no behavior is replaced.

- **No schema-version pin.** `docs/llmll-ast.schema.json` is untouched.
- **No `trust_report_version` change**, so no consumer needs to branch on a
  version.
- **No `.verified.json` migration.** No hashed input moves, so a cached sidecar
  written before the patch stays valid after it.
- **Worst-case unwind:** revert the commit. A report written by the patched
  binary carries an extra key that an older binary ignores.

---

## Risks and unknowns

1. **The row closes while family C stays undisclosed.** Scope. Cited in (c):
   `injectRangeFacts` carries three ground-fact families on the same trust
   channel and is not reachable from a `BodyVC` walk. **Bite: affects the
   closure claim, not the patch.** The patch is correct either way. File the
   follow-on row before closing TRUST-AXIOM, or the row's closure asserts a
   completeness it does not have.

2. **Family B multiplies rows on map-heavy and bytes-heavy programs.**
   Performance and DX. Every `bytes-get` and `map-get` occurrence produces a
   row. A read-modify-write chain produces several. **Bite: complicates the
   patch.** Mitigation: deduplicate per `(def, builtin)` at the stamp, so a
   function using `bytes-get` eight times gets one row. Decide this at
   implementation and record which was chosen.

3. **`EmitResult` and `TrustEntry` are widely imported.** Build. Both records
   gain a field, so the dependent set recompiles. **Bite: build time only.**

4. **The four `markBodyFallback` call sites are easy to under-patch.** Build and
   DX. `compiler/app/Main.hs` calls it on four separate paths and one of them
   (the strict-core CDP branch) has already been missed once, which its own
   comment records. **Bite: a missing call produces an empty disclosure on one
   path and a populated one on another.** Mitigation: the pytest cases must
   exercise `--trust-report`, `--json` and `--obligation-report`, not one of
   them.

5. **The hspec baseline is recalled, not measured at plan time.** Scope. The
   2034 figure is from the v0.23.16 release gate. **Bite: only if it has moved.**
   Re-measure on the merge base at branch time.

---

## Open questions for the professor

None. Every question this plan raised was answerable from the compiler, the
roadmap or the spec, and the one genuinely open decision (d) is an engineering
call with a stated flip condition, not a soundness ambiguity.

---

## Hand-off preview (for `documentation-lead`, after the commit)

Not owed yet. It is owed at ship time and will carry: tag `TRUST-AXIOM`; the
user-visible change is one new trust-report line and one additive
`builtin_axioms` JSON key; no schema delta; no `trust_report_version` change; the
test delta; and the `LLMLL.md` §5.4 and §13.12 wording that records the
disclosure. `LLMLL.md` §988 currently states the `bytes-zero` axiom "is
disclosed on no reporting channel today (roadmap row TRUST-AXIOM)". **That
sentence becomes false when this ships and must be updated in the same doc
pass.**

---

## Rev 2: implementation findings

Rev 1 was written before any code. These are the points where implementation
contradicted it or added to it. The plan is left above as written, so the record
shows what the measurement changed.

### 1. The negative control's prediction was wrong, and the real one is stronger

Rev 1 said the disclosure row must DISAPPEAR when the axiom conjunct is deleted.
It does not. The row discloses the whole assumed post at builtin granularity, so
deleting the length conjunct leaves a row carrying the reflection conjunct and
changes its PREDICATE.

Measured, by deleting `bytesLen(r) = n` from the `bytes-zero` arm and rebuilding:

| build | verdict | disclosed predicate |
|---|---|---|
| axiom deleted | REFUTED | `(result = (Map_default 0))` |
| axiom present | SAFE | `(result = (Map_default 0)) && ((bytesLen result) = 32)` |

This discriminates re-derivation MORE sharply than disappearance would. A
disclosure re-derived from the source would still print `(bytesLen result) = 32`,
because the source still reads `(bytes-zero)` under a `-> bytes[32]` return. The
predicate tracking the arm is the coupling the row asked for.

The verdict half reproduces FACT-AG-LEN Stage 2's own measurement, so it is a
known-good probe rather than a new one.

### 2. `markBuiltinAxioms` takes the report, not the entry list

Rev 1 called it a sibling of `markAssumedFacts`, which maps over `[TrustEntry]`.
That is the wrong shape for a post-emit stamp. `markAssumedFacts` runs INSIDE
`buildTrustReport`, where entries are in hand. This stamp runs in
`compiler/app/Main.hs` after the report exists, so it takes and returns a
`TrustReport`, matching `markBodyFallback`.

### 3. The disclosure reaches only the paths that run the emitter

**This is the one finding that needs a user decision.** Plain
`llmll verify --trust-report` is a SIDECAR-ONLY read: it reports evidence from
`.verified.json` without re-running emission, and it prints its own caveat
("evidence is read from .verified.json and was NOT validated against a run of
the VC emitter"). It therefore has no axiom set and discloses none.
`--strict-verify` runs the emitter and discloses.

That is correct behaviour rather than a gap in the patch: the sidecar path
genuinely does not know what the body VC assumed. But a reader of the
sidecar-only report still sees `verified` with no axiom named, which is the same
silence in a different place. Two options:

- **Accept, and note it.** The path already discloses its own limitation. No
  further work. This is what the patch does today.
- **Persist the rows into `.verified.json`** so the sidecar path replays them.
  Larger: it touches the sidecar schema and needs an evidence-hash decision.

Recommendation: accept for this landing and file the sidecar half as a follow-on
row, so the row's closure does not claim a disclosure it makes on one path only.

### 4. A post-less function discloses nothing, and that is correct

A function with no post and a non-`bytes[n]` return has nothing to prove, so no
body VC is emitted and no axiom is assumed by anything. Disclosing there would
name a dependency that no verdict rests on. `bytes[n]`-returning functions are
the contrast: FACT-AG-LEN Stage 3 gives them an automatic post, so they have a
body VC. Pinned as hspec case TA-9.

### 5. A cost Rev 1 did not name: positional `TrustEntry` constructions

Adding a field to `TrustEntry` broke two construction sites in
`compiler/test/Spec.hs`, one record-syntax and one positional. Both were
updated. Rev 1's "Affected surface" listed the test file but not this reason.

### 6. The result binder needed normalizing

The raw post renders the alpha-renamed binder (`_bv_call_bytes_zero_0`), which
is an emission-order artifact. The row now substitutes `result` via the existing
`applySubst`. Pinned as TA-7 and by a pytest cell.

### 7. Measured results

- **`.fq` byte-identity: 108 of 108 files identical** across `examples/`,
  base `11b526a` against the patched build. The primary gate passes exactly.
- **Verdict identity: 109 of 109 identical.**
- **hspec: 2034 to 2043**, 0 failures. Nine cases added (TA-1 to TA-9). The 2034
  baseline was confirmed by running the suite, not recalled.
- **pytest: 338 collected at base, 343 after.** Five cells added. With
  `LLMLL_BIN` set: 338 passed, 5 skipped.
- **No new GHC warnings.** The build carries 42 warnings, all pre-existing; none
  names an identifier this patch introduced.
- The fixture's length is **32**, not the 8 Rev 1's gate text assumed.
