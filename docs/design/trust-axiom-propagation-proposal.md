# TRUST-AXIOM propagation: design proposal

> **Status:** Rev 1, PROPOSED. Not settled. No compiler work authorized.
> **Answers:** the two open questions in
> [`trust-axiom-implementation-plan-review.md`](trust-axiom-implementation-plan-review.md).
> **Builds on:** [`trust-axiom-implementation-plan.md`](trust-axiom-implementation-plan.md)
> Rev 1 plus Rev 2, and the branch `trust-axiom/builtin-axiom-disclosure`.

---

## Restatement

The shipped branch discloses a sealed-builtin axiom on the function that uses
the builtin. The professor measured that the disclosure stops there: it does not
reach a caller, and it is lost at a module boundary. This proposal specifies how
the axiom set persists and propagates, and it settles which artifact owns it.

---

## Context located

1. `LLMLL.ObligationAssembly`, the `trAssumptions` field and the `assumptions`
   key it emits. **This is the declared TCB-assumption channel.**
2. `LLMLL.ObligationAssembly`, the comment on `assembleConsumedGuarantees`. It
   draws the exact distinction this proposal needs: a consumed guarantee is
   "sound iff the callee was itself verified", and it is explicitly "NOT a TCB
   assumption (that channel is `trAssumptions` / `ctAssumptions`)".
3. `LLMLL.VerifiedCache`, `erToJSON` and the soundness commentary above
   `needsReverify`. **The decisive constraint. See Finding B.**
4. `LLMLL.Syntax`, the `EvidenceRecord` declaration, and `erOverflowTainted`.
   The precedent for a trust-channel flag persisted in the sidecar.
5. `LLMLL.TrustReport`, `refutedClosure` and `markCallerObligations`. Two
   transitive-propagation precedents, as the professor cited.
6. `LLMLL.FixpointEmit`, `sealedAxiomBuiltins` on the branch. Four members.
7. `LLMLL.md` §13.12 and §5.4; `docs/proof-artifact.schema.json`.

### Finding A (spec-drift, and it answers professor Q1)

**The TCB-assumption channel already exists, is schema-visible, and has never
had a producer.** `trAssumptions` is assigned `[]` at exactly one site in
`LLMLL.ObligationAssembly` and is assigned nowhere else. I confirmed the
emitted report carries no `assumptions` key on a real run.

So LLMLL declared the channel a sealed-builtin axiom belongs on, described its
purpose in a code comment, and then shipped it empty. TRUST-AXIOM is its first
producer. This is not a new channel and it needs no new channel.

### Finding B (the constraint that shapes the whole design)

`LLMLL.VerifiedCache` records a failure the project already had, in the exact
shape this proposal risks repeating. The INT-1 trigger invalidated any verified
record lacking `overflow_tainted`, reading absence as "possibly tainted". That
was wrong, because the writer **legitimately omitted** the field on normal
records. Absence meant "normal", not "old". The comment names this as the cause
of Defect 2.

The repair pattern is recorded beside it. `saveVerifiedWith` emits
`checker_soundness_version` **unconditionally**, so absence can only mean
"written by an older binary" and never "normal".

**This governs the axiom set directly.** The branch emits `builtin_axioms` only
when non-empty. If the sidecar copies that rule, absence is ambiguous between
"this function uses no sealed builtin" and "written by a pre-TRUST-AXIOM
binary". A caller reading absence would report "no axioms" for a callee whose
axioms are merely unrecorded. That reintroduces the exact silence TRUST-AXIOM
exists to close, and it does so silently on every sidecar written before this
lands.

---

## Design proposal

### D1. The axiom set is a TCB assumption. Route it to `assumptions`

A sealed-builtin axiom is not a consumed guarantee. A consumed guarantee is
sound iff the callee was verified. An axiom is sound iff codegen is faithful,
and no amount of callee verification establishes it. The two belong on
different channels and `LLMLL.ObligationAssembly` already says so.

Three views, one set:

| view | artifact | content |
|---|---|---|
| local | trust report, per entry `builtin_axioms` | the function's OWN axioms, with predicates. Shipped on the branch. |
| propagated | obligation report, `assumptions` | the transitive union over the call graph, per originating def. New. |
| consolidated | proof artifact | composes both, per `LLMLL.md` §5.4. No new field. |

**This answers professor Q1.** The proof artifact does not own the set. It
already consolidates the trust report and the obligation report, and §5.4 states
that it "introduces no new proof obligation" and "composes `trust_report_version`
rather than bumping it". The obligation report owns the propagated set, because
that is where the declared TCB-assumption channel lives. The artifact picks it
up for free.

### D2. Persist the set unconditionally, or disambiguate absence explicitly

Forced by Finding B. Two admissible shapes, ranked:

**(a) Recommended. Emit `builtin_axioms` on every body-faithful verified
record, including as `[]`.** Absence then means "written by a pre-TRUST-AXIOM
binary" and nothing else. The reader renders that as `axioms: unrecorded`, never
as `axioms: none`. This is the `checker_soundness_version` pattern and it is
explicitly not the `overflow_tainted` pattern.

**(b) Alternative. Keep only-when-non-empty emission, and change
`checker_soundness_version`.** A differing stamp discards the old sidecar, so
every surviving record is one this binary wrote, and absence is then
unambiguous. This is heavier: it forces a full re-verify of the corpus for a
disclosure change that fixes no unsoundness. Reject unless the user wants the
re-verify for another reason.

**Cost of (a), named rather than implied.** Every committed
`examples/*.verified.json` for a verified record changes shape once. That is a
real diff and it must land in one deliberate commit, not as sweep residue from
an unrelated run.

**The staleness question needs no new machinery.**
`downgradeStaleVerifiedSidecar` hashes the canonical `(form, body, pre,
augmented-post)`. The axiom set is a function of the body, so any body edit that
could change the set already drifts the hash and drops the evidence the set
rides. No `checker_soundness_version` change is owed under shape (a).

### D3. Propagate by transitive union, and mark the source

The caller's `assumptions` array is the union of its own axiom set with the
recorded sets of its transitive callees. Each row names the def the axiom
originated at, so a reader can tell `bytes-zero used here` from `bytes-zero
reached through buf.make-buffer`. This mirrors the `refuted` versus
`depends-on-refuted` distinction that `markRefuted` already draws.

Sketch of one propagated row, illustrative only, for the language of the thing
rather than its encoding:

```
{ "kind": "builtin-axiom", "builtin": "bytes-zero",
  "origin": "buf.make-buffer", "via": "transitive",
  "category": "codegen-determined", "stamp": "codegen_semantics_version" }
```

### D4. Deduplicate to the set, not the occurrence

The professor measured three rows for a three-read body, differing only in an
index literal. The disclosure's content is which sealed builtins the evidence
rests on. That set is bounded by `sealedAxiomBuiltins` at four members.

- **Local view**: one row per `(def, builtin)`. Keep one representative
  predicate. Drop the per-occurrence index.
- **Propagated view**: one row per `(origin-def, builtin)`. Carry no predicate.
  A caller does not need the callee's index literals.

### D5. Name the sealed set in the spec

**This answers professor Q2: yes, the spec should name it.** `LLMLL.md` §13.12
already documents the reflection of each of these four builtins individually. It
should additionally name them as a closed set, with the statement that each
one's assumed post is disclosed rather than discharged.

The implementation keeps its single-site definition. The spec names the same set
normatively. Two reasons: the professor's proposed future allowlist gate needs
an auditable declaration, and a reader auditing the trusted base should not have
to read `LLMLL.FixpointEmit` to enumerate it.

**This makes TRUST-AXIOM a `[CT][SPEC]` row.** It carries `[CT]` today. The
engineer's plan §(d) used the absent `[SPEC]` tag as one argument for
disclosure-only. The professor was right to reject that argument, and D5 is the
reason it could not have carried weight: the tag was incomplete.

---

## Edge cases and degenerate inputs

### E1. The cross-module witness (positive witness, required)

**Input.** The professor's measured pair, verbatim:

```lisp
;; buf.llmll                          ;; use.llmll
(export make-buffer)                  (import buf) (open buf)
(def make-buffer [] -> bytes[32]      (def use-buffer [] -> int
  (post (= (bytes-length result) 32))   (post (= result 32))
  (bytes-zero))                         (bytes-length (make-buffer)))
```

**Expected under the proposal.** `use.llmll` emits one `assumptions` row:
`bytes-zero`, origin `buf.make-buffer`, `via: transitive`. Today it emits zero
rows and no `assumptions` key at all.

**Channel.** Trust. **Citation.** `LLMLL.ObligationAssembly` `trAssumptions`;
`LLMLL.TrustReport` `refutedClosure` for the closure shape.

### E2. A pre-TRUST-AXIOM sidecar

**Input.** Any `examples/*.verified.json` committed before this lands.

**Expected.** The reader renders `axioms: unrecorded`. It must NOT render
`axioms: none`. Under shape (a) this is decidable, because a record this binary
wrote always carries the key.

**Channel.** Trust, fail-closed. **Citation.** `LLMLL.VerifiedCache`, the
`needsReverify` commentary on the INT-1 over-invalidation and the
`checker_soundness_version` repair.

### E3. A callee with no body VC

**Input.** A callee at tier `asserted`, or one that fell back.

**Expected.** Its recorded set is `[]` under shape (a), and the propagated view
must distinguish "this callee assumed no axiom" from "this callee proved
nothing, so the question does not arise". The existing `callee_tier` field on
the consumed-guarantee row already carries the tier; the propagated row should
be suppressed when the callee has no body-faithful evidence, because an
unverified callee's guarantee is not being consumed on the axiom channel at all.

**Channel.** Trust. **Citation.** `LLMLL.ObligationAssembly`
`assembleConsumedGuarantees`, which sources `callee_tier` from
`teEffectiveLevel` and never hardcodes `verified`.

### E4. A diamond in the call graph

**Input.** `top` calls `left` and `right`; both call `buf.make-buffer`.

**Expected.** One row, not two. The union is over a set keyed by
`(origin-def, builtin)`, so the two paths collapse. This is D4's rule doing the
work at the propagated layer.

**Channel.** Trust. **Citation.** `LLMLL.TrustReport` `transitiveClose`, the
existing reachability fold.

### E5. A recursive callee

**Input.** A self-recursive `bytes[n]`-returning def-shell.

**Expected.** Its tier is already degraded, because its own body VC is excluded
by design. The axiom set still propagates if body-faithful evidence exists,
because the axiom is a property of the emitted VC and not of the tier. If no
body-faithful evidence exists, E3 suppresses the row.

**Channel.** Trust. **Citation.** `LLMLL.ObligationAssembly`
`assembleConsumedGuarantees`, the recursive-callee note.

---

## Verification mapping

**This proposal introduces no proof obligation.** Every item is disclosure.

| item | channel | fragment |
|---|---|---|
| local axiom rows | trust | none. No constraint is emitted. |
| persisted axiom set | trust | none. Additive sidecar data. |
| propagated union | trust | none. A fold over the existing call graph. |
| spec naming of the sealed set | type (documentation of §13.12) | none. |

No obligation enters QF-LIA, none is nonlinear, and none escapes to Lean. The
`LLMLL.md` §5.3.3 boundary is untouched, because no new symbol, sort or theory
is introduced. This matches the branch's measured result: 108 of 108 `.fq` files
byte-identical.

**The one place a future obligation could appear** is the professor's allowlist
gate: "the transitive axiom set is a subset of `sealedAxiomBuiltins`". That is a
set-inclusion check over report data, not an SMT obligation, so it would remain
outside the solver. It is out of scope here.

---

## Affected surface

- `compiler/src/LLMLL/Syntax.hs`: `EvidenceRecord` gains the axiom set.
- `compiler/src/LLMLL/VerifiedCache.hs`: `erToJSON` and `erFromJSONWarn`.
  **Unconditional emission** per D2(a).
- `compiler/src/LLMLL/ObligationAssembly.hs`: `trAssumptions` gains its first
  producer; the transitive union is folded here.
- `compiler/src/LLMLL/TrustReport.hs`: deduplication per D4; the caller-side
  view.
- `compiler/src/LLMLL/FixpointEmit.hs`: `collectBuiltinAxioms` deduplicates
  before publishing.
- `docs/proof-artifact.schema.json`: no change. The artifact composes.
- `LLMLL.md` §13.12: **[SPEC]**, names the sealed set (D5).
- `LLMLL.md` §988: the sentence "it is disclosed on no reporting channel today"
  becomes false when the branch lands. Already flagged by the engineer.
- `docs/compiler-team-roadmap.md`: TRUST-AXIOM becomes `[CT][SPEC]`.
- `examples/*.verified.json`: one-time reformat under D2(a).

**No addition.** No new builtin, construct, FFI tier or capability. Strict
immutability is untouched: nothing here is a value, only report metadata.

---

## Risks and open questions

1. **Sidecar reformat under D2(a).** Classify: scope. Every committed verified
   sidecar changes shape once. **Affects: the byte-identity gate on the landing
   commit.** It must be a deliberate commit, and the sweep must expect the diff
   rather than treat it as drift.

2. **`assumptions` has no consumer today.** Classify: spec-drift. The key is
   declared and always empty, so no reader parses it and no test pins it. Adding
   a producer means the key appears for the first time. **Affects: any consumer
   that assumed the key absent.** The checkout brief's `ctAssumptions` is the
   one adjacent surface to check.

3. **Propagation cost on a deep call graph.** Classify:
   verification-ergonomics. The union is a fold over `transitiveClose`, which
   the report already computes. **Only matters at scale**, and the set is
   bounded at four members per origin def.

4. **D5 changes the row's tag.** Classify: scope. Making TRUST-AXIOM
   `[CT][SPEC]` means `LLMLL.md` must land alongside the compiler work.
   **Complicates the landing; does not block it.**

---

## Open questions for the professor

None. Both questions routed to me were answerable from the tree: Q1 by the
`trAssumptions` channel and the §5.4 composition rule, Q2 by §13.12's existing
per-builtin documentation. The allowlist-gate design the professor proposed is
real, and it is downstream of this proposal rather than a question about it.

---

## Rev 2: D2 re-measured, and a third shape that dominates both

Rev 1 ranked D2(a) over D2(b) and named the cost of (a) as "every committed
verified sidecar changes shape once". **I measured that claim and it was
wrong in the direction that matters.**

### The measurement

| quantity | value |
|---|---|
| `.verified.json` files TRACKED in git | **5** |
| `.verified.json` files on disk (untracked build residue) | 536 |
| body-faithful clause records in the tracked five | **335** |
| of those, records in programs that use a sealed builtin | **0** |

Two of the five files hold 326 of the 682 clause records. They are the
secure-channel flagship and its agent-fill twin, which are the same program.

**No tracked program uses `bytes-get`, `bytes-set`, `bytes-zero` or `map-get`.**
The one program that does, `examples/bytes-bounds/zero-buffer.llmll`, has an
UNTRACKED sidecar.

### What that does to the ranking

Under D2(a) all 335 records gain `"builtin_axioms":[]` and not one of them gains
information. The whole diff exists to make absence unambiguous. That is a poor
trade, and Rev 1 recommended it only because I had assumed the informative
records and the reformatted records were the same population. They are disjoint.

### D2(c), recommended, and it dominates (a) and (b)

**Put the disambiguating marker at the sidecar's top level, once per file.
Keep the per-record key only-when-non-empty.**

The sidecar already carries two top-level keys beside the per-def entries:

```json
{"caller_obligations":[],"checker_soundness_version":"2",
 "make-buffer":{"post":{...}}}
```

Add one more, emitted unconditionally by `saveVerifiedWith`, in the same place
and on the same rule as `checker_soundness_version`. The reader then decides:

| top-level marker | per-record key | reader renders |
|---|---|---|
| present | present | the recorded axiom set |
| present | absent | `axioms: none` (the writer had nothing to record) |
| absent | absent | `axioms: unrecorded` (written by an older binary) |

**Cost: 5 files gain one key each. 335 records are untouched.** The semantics of
Finding B are fully preserved, because absence of the per-record key is now
disambiguated by a marker the writer always emits. This is the
`checker_soundness_version` pattern applied at the granularity where it is
cheap, rather than at the granularity where it is expensive.

**Why this is not D2(b).** Changing `checker_soundness_version` would DISCARD
every sidecar, because `needsReverify` discards on any value that differs from
the binary's. That forces a re-verify and it spends a soundness-epoch stamp on
a disclosure change that fixes no unsoundness. The stamp should stay reserved
for what it was built for.

**Revised recommendation: D2(c). Reject D2(a) on the measurement above. Reject
D2(b) as disproportionate.**

### One consequence worth stating plainly

The flagship does not exercise this channel. The secure-channel program models
its buffers without the bytes builtins, so the disclosure TRUST-AXIOM adds is
invisible on the repository's most prominent verified artifact. That is not an
argument against the row. It does mean the row's value is demonstrated by
`examples/bytes-bounds/`, and that the tracked-sidecar population is a poor
regression surface for it. A test that pins the disclosure must use its own
fixture, which is what the branch's pytest cells already do.

---

## Spec text draft for `LLMLL.md` §13.12 (D5)

Not for me to land. `documentation-lead` owns `LLMLL.md`. This is the text I
propose, in the spec's register rather than in STE.

**Placement:** after the builtin table in §13.12, before the "Map keys are
`{int, string}`" paragraph.

**Stage 1, true when the current branch lands:**

> **The sealed-builtin axiom set.** Four operations in this section reach the
> solver carrying an **assumed post** that no obligation discharges:
> `bytes-get`, `bytes-set`, `bytes-zero` and `map-get`. Each post equates the
> operation's result to the theory term it reflects to; `bytes-set` and
> `bytes-zero` additionally carry a length fact (`bytesLen(result) =
> bytesLen(b)` and `bytesLen(result) = n` respectively). These are **axioms
> about sealed builtins**. Each is valid because codegen emits the operation
> the term describes, so each rides the `codegen_semantics_version` stamp
> (§3.5) rather than a solver discharge. **The set is closed.** No other
> builtin contributes an assumed post, and adding one is a change to the
> trusted base rather than an implementation detail.
>
> Every such axiom is **disclosed rather than silent**. `llmll verify
> --trust-report` names each one on the function whose body VC assumed it,
> under the category `codegen-determined`, beside the `assumed_facts` rows that
> disclose the control-tag facts of §5.5. §5.4's anti-laundering invariant
> governs whether a record's own fields cohere; this disclosure governs what
> the record's tier rests on. The two are complementary and neither subsumes
> the other.

**Stage 2, add only when propagation lands:**

> A function inherits the axiom set of every function it calls, transitively.
> The obligation report's `assumptions` channel carries the inherited set, with
> each row naming the function the axiom originated at, so a caller's
> justification surface names the sealed builtins its evidence depends on even
> when its own body uses none.

**Correction owed in the same pass.** `LLMLL.md` §5.3.3, in the array-class
paragraph, currently ends: "and it is disclosed on no reporting channel today
(roadmap row TRUST-AXIOM)." That sentence becomes false at Stage 1. Proposed
replacement:

> and it is disclosed on the trust report as a `codegen-determined` builtin
> axiom (§13.12).
