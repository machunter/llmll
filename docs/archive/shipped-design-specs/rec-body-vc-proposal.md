---
name: rec-body-vc-proposal
title: "REC-BODY-VC — recursive own-body VC, partiality marker, hash integrity, and call-site strict descent"
status: "Rev 1 (professor-folded) — increment 1 (b0) in compiler-engineer plan; increments 2–3 open. Feature freeze retired 2026-07-10, so REC-DESCENT (c) needs no freeze-exception sign-off — it goes through the normal design→review→ship pipeline"
date: 2026-07-10
author: language-team
consumers: [professor, compiler-engineer, documentation-lead]
---

# REC-BODY-VC — recursive own-body VC, partiality marker, hash integrity, and call-site strict descent

## Restatement

Close the F-1 class (`examples/secure-channel-emergent/`, v0.14.21) where a recursive
`def`/`def-shell` discharges its own contract *vacuously* at partial correctness and reaches
the `verified` tier. The roadmap row (`docs/compiler-team-roadmap.md:56`) framed this as "emit
the recursive own-body VC, lifting the v0.9 SCC exclusion." The empirical baseline (probes A–E
below) overturned that premise: the own-contract assume-guarantee emission **already ships** for
`def`/`def-shell` (the v0.14.13 §0.1 reconciliation) — and it is exactly what launders a vacuous
partial-correctness discharge into `verified`. The real work is therefore not to *add* the
emission but to (a) **mark** the partiality it produces, (b0) **close the one laundering path** into
the total-correctness tier, (b1) **state why** recursion is refused by default, and (c) supply the
**well-founded discharge** that lets a genuinely-terminating cycle back in.

## Background — the empirical baseline

All probes run against the installed `llmll 0.14.16`; the only `FixpointEmit.hs` deltas since
(`5adca0e` XMOD-AG, `9662acb` XMOD-CG-BRIEF) are cross-module cache seeding, identity on
single-file input.

| Probe | Input | Observed |
|---|---|---|
| A | `def f [x:int] -> int (post (= result x)) (f x)` | **Rejected** at strict-core admission — "callee 'f' is not body-faithful" (`TypeCheck.hs:395-417`) |
| A′ | same body, `def-shell` | `body_faithful`, SAFE; sidecar `post = verified (liquid-fixpoint)` + `verified_hash`; second-run trust report `effective_level: verified` |
| C | exact F-1 replica (`alert-admit` + `<=>` post + self-call) | `body_faithful`, SAFE |
| D | mutual `def-shell` pair `ping`/`pong` (each `(g x)`) | both `body_faithful`, SAFE (both non-terminating — vacuous) |
| E | verify as `def-shell` → rename to `def`, keep sidecar | **admitted** — plain verify AND `--strict-verified-core` pass, `body_faithful`, SAFE |

Probe E is the soundness event: a `def` (which claims strict-core / total-by-construction)
is admitted on evidence produced under `def-shell` (partial-correctness) semantics, because the
persisted-evidence admission leg (`TypeCheck.hs:407-410`) trusts a sidecar hash that does not
cover the def-form.

### Drift findings surfaced during the baseline

- **D1 (spec-internal contradiction).** Post-v0.14.13 `§0.1:13` says recursive cycles verify
  compositionally at partial correctness; `§5.3.5:1007` (`EApp` recursive self → ❌ contract-only),
  `§3.4.3` precondition 2 ("non-recursive"), `§9:962`, `docs/one-pager.md:76`, and `README.md:181`
  still say the opposite. The v0.14.13 reconciliation touched `§0.1` only. Code agrees with `§0.1`
  (probes A′, C, D).
- **D2 (F-1 mechanism misreport).** `secure-channel-emergent/README.md:73` claims the self-call fill
  "silently drops out of the body-faithful set" and `:48-49,:76` claim the body-faithful acceptance
  bar "closes the class." Probe C disproves both: the exact fill **is** body-faithful and SAFE. The
  v0.14.21 HOLE-STATUS fix removed the prompt-side inducement only; a degenerate self-call emitted
  anyway passes the harness bar today.
- **D3 (soundness gap — probe E).** The `def-shell → def` flip over an intact sidecar passes
  `--strict-verified-core`, violating `§4.2:464` ("recursion is outside the strict-core fragment")
  and destroying strict-core totality-by-construction.
- **D4 (dead spec claim).** `§4.2:475` promises a trust-report partial-correctness flag on
  `letrec`-derived `verified` claims; no such flag exists and a `letrec` cannot reach `verified`
  (no body VC ever, `FixpointEmit.hs:661`).
- **D5 (roadmap row premise).** Row `:56` asks to ship what v0.14.13 recorded as already shipped
  ("No behavior change — documentation + a compiler comment only"); only the `letrec` half of the
  SCC exclusion survives, on a legacy-only surface.

## Design proposal

Four increments. (a) is a derived marker; (b0) is a staleness-primitive edit; (b1) is spec text;
(c) is the new surface + obligations carrying the step-indexed soundness argument.

### (a) REC-PARTIAL-MARK — partiality marker on cycle members `[CT]`

A function is **termination-unverified** iff it is in a `CyclicSCC` of the current module's call
graph (`recursiveNames`, `ObligationAssembly.hs:286-290`) and its SCC has not been descent-discharged
per (c). The property is **derived at consumption time** — trust-report render, obligation report,
admission — never persisted; a body edit or def-form flip changes the call graph the consumer
recomputes, so there is no staleness class. Cross-module consumers hold `meStatements` in the cache
(`FixpointEmit.hs:315`), so the derivation is available module-crossing.

Surface: trust report per-entry `"termination_unverified": true` + top-level `partial_fns` list —
the `overflow_tainted_fns` / `refuted_fns` precedent (`§4.4.4`); `trust_report_version` 1.4.0 → 1.5.0.
No sidecar / EvidenceRecord / AST-schema change. Replaces `§4.2:475`'s dead claim with a true one, and
is the **unifying repair** for the Option-3 inconsistency (finding 3 below).

### (b0) REC-HASH-FORM — def-form in the evidence-hash preimage `[CT]`

Probe E succeeds because `canonicalDefEvidenceHash` (`PBT.hs:596-607`) hashes only
`(admitVerifiedSemanticsTag, body, pre, post)` — **the def-form is absent**. Extend the preimage:

```
payload = "(def-evidence " <> admitVerifiedSemanticsTag
        <> " (form " <> defFormTag <> ")"      -- NEW: "def" | "def-shell"  (equivalently rec|nonrec)
        <> " (body …) (pre …) (post …))"
```

`normalizeDefStmt` already discriminates the constructor at both hash sites — the write side
(`Main.hs:1454,1463`) and the read-side recompute (`TrustReport.hs:460,462`) — so the tag is in scope
and merely dropped today. After the fix, a `def-shell → def` rename invalidates the sidecar →
`downgradeStaleVerifiedSidecar` (`TrustReport.hs:465-469`) downgrades the stale entry → the def is
re-verified fresh → the normal `def` callee-admissibility rejects the self-call exactly as probe A
does. No new admission machinery; this rides the existing staleness path. This is the operational
form of "evidence independence": evidence is invalidated when the syntactic object it certifies
changes in a way that bears on admissibility — the discipline `PBT.hs:590-593` already applies to
the contract clauses.

**Cross-module flip (professor Q1).** The read-side recompute is same-module (`TrustReport.hs:454-455`).
A cross-module consumer seeds imported evidence from `meStatements` via `cacheAwareContractEnv`
(`FixpointEmit.hs:315-318`) and trusts the cached tier. Baking the def-form into the preimage **at the
write site** (`Main.hs:1454`) is sufficient: the tag is inside the persisted hash of the *defining*
module, so a flip there invalidates that module's own sidecar before any importer consumes it, and any
consumer re-deriving the expected hash from the callee's live `meStatements` reproduces the tag. The
only residual is a stale cached `.verified.json` whose source module was flipped without
re-verification — the general stale-cache hazard already owned by XMOD-STALE (`roadmap:51`), not
recursion-specific.

### (b1) Fail-closed default — the step-indexed account `[SPEC]`

With (b0) closing the laundering path, "strict-core refuses recursion" is not a guard to add — it is
the status-quo default (probe A: a `def` cannot self-call, because a recursive callee is never
body-faithful-admissible). The spec's job is to name *why*, and to describe the one door (c) opens.
The account, adopted from the professor's outward reading:

> A recursive call cycle is a **circular assume-guarantee** obligation — each member proves its body
> assuming its callees' (transitively its own) postconditions. Circular assume-guarantee is sound only
> when the circle is broken by a **well-founded discharge** (Abadi & Lamport, *Conjoining
> Specifications*, TOPLAS 17(3), 1995; McMillan, CAV 1999). The discharge is a **step-index**: a
> recursive assumption is usable only at a strictly smaller index (Appel & McAllester, *An Indexed
> Model of Recursive Types for Foundational PCC*, TOPLAS 23(5), 2001; Nakano's ▷ modality, LICS 2000).
> In LLMLL the index is the user-declared measure of REC-DESCENT (c): the descent constraint
> `eᵍ[a] < eᶠ` *is* the "one step later" side condition. With no declared measure the ▷ is never
> discharged, the circular assumption is unusable, and refusal from the total-correctness tier is the
> only sound default — today's behavior, now with a reason rather than an accident of the
> body-faithfulness predicate.

SCC membership is the operational proxy for "this edge closes a circle with no declared index."

### (c) REC-DESCENT — `(decreases e₁ e₂ … eₖ)` on `def-shell`, list surface, single-slice discharge `[SPEC→CT]`

Anticipates R7 (`roadmap:208`) and promotes its single-slice case out of the research track; the
emitted obligation is exactly R7's `measure(args′) < measure(args)`.

**Surface (S-expr) — metric list** (Dafny `decreases`; Liquid Haskell termination metrics both take a
list):

```lisp
(def-shell ackermann [m: int n: int] -> int
  (pre  (and (>= m 0) (>= n 0)))
  (decreases m n)          ;; lexicographic metric list — surface accepted in v1
  …)
```

v1 **discharges only k=1**. A `k>1` clause is accepted at surface and schema but **not discharged**:
the SCC stays `termination_unverified` (a) and `W-DECREASES-LEX` fires ("lexicographic descent (k>1)
not yet discharged; single-measure metrics discharge in this release"). This decouples surface
stability from discharge completeness — the DEF-RET additive-field move — so lexicographic discharge
later needs **no second schema bump**.

**Surface (JSON-AST).** Optional `"decreases": [<Expr>, …]` — a **list** of `Expr` on `DefShell`.
Additive optional field → `schemaVersion` 0.7.0 → 0.8.0. Absent field ≡ empty list ≡ no measure.

**Obligations (v1, per fully-body-faithful SCC where every member declares a k=1 metric `eᶠ`):**

1. **Well-foundedness**, per member: `preᶠ ⟹ eᶠ ≥ 0` — the existing letrec constraint shape
   (`FixpointEmit.hs:642-656`) relocated to `def-shell`.
2. **Strict descent**, per intra-SCC call site `g(a…)` in `f`'s body under that path condition:
   `preᶠ ∧ path ⟹ eᵍ[a/params_g] < eᶠ`. Common order `<` on ℕ (well-founded by the `≥ 0` floor);
   the shared-measure rule discharges decrementing mutual recursion (even/odd on `n−1`: both edges
   are `arg−1 < arg`). Call sites are explicit post-ANF (`aNormalizeBody`, v0.14.11), so each CallVC
   contributes one descent constraint beside its existing `cvPreObligation`.

**Verdict — `measure-not-decreasing`, hard exit-1 (renamed from Rev 0's `descent-refuted`).** A SAT
model for `preᶠ ∧ path ∧ ¬(eᵍ[a] < eᶠ)` witnesses that *the declared measure* does not decrease on
that edge — **not** that the function fails to terminate (it may terminate under a measure the author
did not declare). Labeling this `refuted` would collide with the existing `refuted` (`§4.4:533`,
postcondition disproved — a stronger, measure-independent claim). `measure-not-decreasing` asserts
exactly what the solver established, applying the v0.14.2 claim-accuracy discipline
(`spec-inconsistent` → `spec-inconsistent-or-unproven`) reflexively. The hard-fail exit-1 stance is
Dafny parity (LPAR-16 §3). F-1's `(decreases sev)` self-call yields `sev < sev`, UNSAT →
`measure-not-decreasing` — the roadmap's promised solver failure.

**Discharge semantics.** All obligations of all members SAFE → the SCC is *descent-discharged*:
partiality mark dropped (a), strict-core admissible, evidence upgraded partial→total (the classical
total-correctness recursion rule — assume-guarantee on a smaller measure argument, sound by
well-founded induction; Turing 1949; Hoare 1971; Apt, TOPLAS 1981 §3).

**SCC-granularity fail-closed rule.** Descent is an SCC-level property. If any member lacks a
translatable single-slice metric, the whole SCC stays `termination_unverified`; no member is
individually upgraded (a per-member upgrade is unsound — the cycle can spin through the unmeasured
member). A `k>1` metric on any member also holds the SCC at partial (per the v1 discharge restriction).

**Scope boundary — decidable-measure totality (professor hazard 5).** With (c), strict-core totality
is **decidable-measure totality**, not totality *simpliciter*. A recursion terminating for a reason
QF-LIA cannot express — structural recursion on an opaque `list`/`string` carrier, whose natural
measure is measure-only/untranslatable — is refused from strict-core by the (b1) default and **not
rescued by (c)** (its measure won't translate). Such a function routes to `def-shell` +
`termination_unverified`, or to the Lean tier under LEAN-GA. This is a scope divergence from
Dafny / Liquid Haskell (which accept structural metrics over algebraic data), not a soundness defect;
it is the boundary the data-scope-extension track (Lever C) will meet.

**letrec.** Retire the "own body VC for `letrec`" half as moot — legacy-grammar-only surface
(`LLMLL.md:475`), superseded by `def-shell` + `(decreases …)`. No engineering.

**Totality claim wording (professor Q2).** The claim is **"total modulo a decidable-measure witness,"**
not "total." The `§3.4.3` precondition-2 rewrite REC-DESCENT licenses is the witness-naming form:

> **2. Codegen is faithful.** Per §5.3.5: QF-LIA + the acyclic datatype / measure / Bool closure,
> compositional call-chain reasoning, and **either non-recursive or descent-discharged by a QF-LIA
> measure** (§4.2, REC-DESCENT). A recursive cycle without a discharged QF-LIA measure does not satisfy
> this precondition and is confined to `def-shell` at partial correctness (`termination_unverified`).

Not the weaker "non-recursive or descent-discharged" — that reads as though any descent argument
counts, whereas the compiler backs only the decidable-measure witness.

**Strict immutability.** Unaffected: `eᵢ` are pure expressions over parameters; no new binding or
effect forms.

### Finding 3 — Option-3 reconciliation (cross-proposal)

`cascading-refinement-proposal.md:90-94` (Option 3, Rev 2 — settled) degrades a *spawn-created* cycle
to **contract-only**, citing the pre-v0.14.13 `LLMLL.md:13,24`. Post-v0.14.13 a *hand-written* cycle
verifies **body-faithful at partial correctness** (`§0.1:13`). Same SCC shape → strictly weaker tier
via `refine` → a provenance-dependent trust verdict, which the trust model otherwise forbids (a
function's tier is a property of its proof, not its authoring path). Repair: REC-PARTIAL-MARK (a) —
both paths land at body-faithful-partial + `termination_unverified`; Option-3's "honest degradation"
is restated as "apply the (a) marker (and, once REC-DESCENT lands, offer the cycle members a
`decreases` metric to reach total)," not "drop to contract-only." Obligates a Rev 3 on the
cascading-refinement proposal (drop the `:13,24` citation, replace the `:90-94` degradation).

## Edge cases and degenerate inputs

1. **Degenerate self-call, no `decreases`** (`def-shell f … (f x)`). Verifies SAFE (unchanged); trust
   report marks `termination_unverified`; strict-core unaffected (never admissible — probe A).
   Channel: trust (a). Cite: `Main.hs:1428-1469`.
2. **Positive witness — measure refutation** (`f` + `(decreases x)`): `(>= x 0) ⟹ x < x`, UNSAT →
   `measure-not-decreasing`, exit 1. The concrete firing input for the (c) verdict. Channel: contract,
   QF-LIA.
3. **Positive discharge witness** (`countdown` + `(decreases n)`): `(>= n 0) ∧ ¬(n=0) ⟹ n−1 < n`
   discharges → SCC total, mark dropped, strict-core admissible. Channel: contract, QF-LIA.
4. **Flip attack (probe E)**: under (b0) the def-form is in the hash → flip invalidates sidecar →
   re-verify → probe-A rejection (`core-membership-violation`). Channel: trust (staleness) → type.
   Cite: `PBT.hs:599-603`, `TrustReport.hs:465-469`, `TypeCheck.hs:414`.
5. **Mutual SCC, one member lacks a metric** (`ping`/`pong`, measure on `ping` only): whole SCC stays
   `termination_unverified`; `ping`'s well-foundedness still emits; no descent constraints. Channel:
   trust, fail-closed.
6. **Lexicographic metric declared** (`ackermann` + `(decreases m n)`): surface + schema accept; v1
   does not discharge k>1; `W-DECREASES-LEX` fires; SCC stays `termination_unverified`. Channel:
   contract + diagnostic. The forward-compat witness — stable surface, staged discharge.
7. **`decreases` on a non-recursive `def-shell`**: no intra-SCC call sites → no descent constraints;
   well-foundedness still emitted; `W-DECREASES-UNUSED` flags the vacuous clause. Channel:
   contract + diagnostic.
8. **Nonlinear / opaque-carrier measure** (`(decreases (* n m))` or `(decreases (list-len xs))` on an
   opaque list): `exprToPred` returns `Nothing` → untranslatable → SCC stays `termination_unverified`
   with a diagnostic naming the untranslatable measure; never silently total, never
   `measure-not-decreasing`. The decidable-measure scope boundary made concrete. Channel: trust,
   fail-closed (`§3.4.5` firewall). Lean escape deferred to LEAN-GA.

## Verification mapping

| Obligation | Channel | Fragment | Cite |
|---|---|---|---|
| Def-form in evidence-hash preimage (b0) | trust | no solver obligation (staleness primitive) | `PBT.hs:596-607`; `TrustReport.hs:460`; `Main.hs:1454` |
| Well-foundedness `preᶠ ⟹ eᶠ ≥ 0` | contract | QF-LIA, auto-discharged | §5.3.3; `FixpointEmit.hs:642-656` |
| Strict descent `preᶠ ∧ path ⟹ eᵍ[a] < eᶠ` (k=1, body-faithful SCC) | contract | QF-LIA, auto-discharged | §5.3.3; `FixpointEmit.hs:1751-1759` |
| Lexicographic descent (k>1) | contract | not discharged in v1 — surface/schema accepted, `W-DECREASES-LEX`, partial-marked | §5.3.5; edge case 6 |
| Nonlinear / opaque-carrier measure | contract | outside QF-LIA → partial-marked, not emitted | §5.3.3 nonlinear boundary; edge case 8 |
| SCC membership / partiality mark (a) | trust | static call-graph analysis | `ObligationAssembly.hs:286-290` |
| Strict-core recursion refusal (b1 default) | type | no solver obligation (status-quo default, now reasoned) | `TypeCheck.hs:395-417` |

No obligation default-routes to Lean; the decidable core stays `Σ_auto` + one QF-LIA constraint class
per intra-SCC call site (k=1).

## Affected surface

- `compiler/src/LLMLL/PBT.hs:599-603` — **(b0)** def-form in the hash preimage. Single smallest edit
  that closes probe E; independently shippable.
- `compiler/src/LLMLL/` for (c): `Syntax.hs` (list-typed `decreases` field), `Parser.hs` /
  `ParserJSON.hs` / `AstEmit.hs` (round-trip), `FixpointEmit.hs` (descent constraints + SCC-discharge
  bookkeeping), `TypeCheck.hs` (`decreases` scope check), `TrustReport.hs` (the (a) mark + `partial_fns`,
  version 1.5.0; `measure-not-decreasing` surface), `ObligationAssembly.hs` (reuse `recursiveNames`).
- `docs/llmll-ast.schema.json` — list-typed optional `decreases` on `DefShell`; 0.7.0 → 0.8.0.
- `LLMLL.md`: §0.1, §3.4.3 precondition 2 (witness-naming rewrite), §4.2 (rewrite; step-indexed
  account; retire :475), §4.4 (`termination_unverified` mark + `measure-not-decreasing` verdict beside
  `refuted`), §5.3.5 rows :1007/:1013, §9:962, §11 (total-correctness recursion rule), §12 grammar.
  Doc-lead, post-ship.
- `docs/one-pager.md:76`, `README.md:181` — recursive-self row correction. Independent of CT; can ship
  with the D1 spec corrections.
- `examples/secure-channel-emergent/README.md:48-49,69-76,116` — F-1 mechanism correction (D2).
- `docs/design/cascading-refinement-proposal.md:90-94` — finding-3 Rev 3 reconciliation
  (language-team's own folder).
- `docs/compiler-team-roadmap.md:56` (restate as (a)/(b0)/(b1)/(c)); `:208` R7 (gains "promoted via
  REC-DESCENT single-slice; lexicographic deferred"). Doc-lead.
- **New surface:** `(decreases …)` is a new surface construct. With the feature freeze retired
  (2026-07-10) it needs no freeze-exception sign-off; it lands through the normal design→review→ship
  pipeline, carrying the (b1)/(c) step-indexed soundness argument as its design record.

## Risks and open questions

1. **(b0) invalidates existing recursive-`def-shell` sidecars on first re-verify** — scope/compat.
   One-time cache-miss + re-verify, not a soundness event; re-verify the corpus in one pass at ship.
   Complicates.
2. **`measure-not-decreasing` is hard-fail (exit 1)** — verification-ergonomics. Declaring a metric is
   a strict commitment (Dafny parity). Only bites authors who declare metrics; undeclared recursion
   keeps today's behavior + the (a) mark. Correct by design; flagged for the doc-lead's framing.
3. **Option-3 reconciliation touches a settled (Rev 2) design** — spec-drift. Forces a Rev 3 on
   `cascading-refinement-proposal.md`. Low bite; must actually happen.
4. **k>1 surface accepted but not discharged** — reads as silent no-op without the diagnostic.
   `W-DECREASES-LEX` is load-bearing for claim accuracy and must ship with the surface.
5. **Decidable-measure totality is narrower than Dafny/LH totality** — scope. Documentation-clarity
   risk, not soundness; matters when the data-scope track lands.

## Sequencing

1. **REC-HASH-FORM (b0) — ship now, compiler-engineer.** One-function preimage edit + corpus
   re-verify. Closes probe E (D3) surgically; strands no program; no surface, no schema bump. The
   security-relevant fix; should not wait on the design.
2. **REC-PARTIAL-MARK (a) + D1/D2/finding-3 spec reconciliation — next, split.** (a) is
   compiler-engineer (`TrustReport.hs`, reuse `recursiveNames`; `trust_report_version` → 1.5.0). The
   D1 / D2 / finding-3 corrections are doc-lead / language-team spec-track, no compiler dependency —
   parallel with (a). Makes refine-path and hand-written cycles agree; retires §4.2:475.
3. **REC-DESCENT (c) + the (b1) step-indexed spec text — the real REC-BODY-VC, compiler-engineer.**
   Turns F-1 into a solver failure and upgrades discharged SCCs to total; carries the list-shaped
   `decreases` surface and the schema bump (0.8.0). With the freeze retired it needs no exception
   sign-off — normal pipeline. Never ship (b1) as a standalone guard ahead of (c) — under (b0) the
   laundering path is
   already closed, so there is nothing to guard; (b1) is spec text landing with (c).

## Appendix — Professor review log

*(Standalone review at [`rec-body-vc-review.md`](../professor-reviews/rec-body-vc-review.md); folded here on settlement per
DOC-CONSOLIDATE M2. Rev 1 above incorporates all six findings + both open-question answers.)*
