# Compositional Trust Closure in the Demo — Surfacing Shipped Assume-Guarantee as Verified Call Edges

> **Version:** Rev 4 (2026-06-19) — **CLI ground-truth: composition reaches `verified`; demo is VIABLE.** Corrects the Rev-3 "Wall C blocks the demo" misdiagnosis (a cold-`--trust-report` render + non-working fixture shapes, not a compiler wall — see §0). §10 fixture needs a Rev-5 reshape onto working shapes. Prior: Rev 3 — implementation surfaced the walls; Rev 2 — three consults folded (Professor A on the assumptions-channel split; Professor B on the recursion boundary; compiler-engineer feasibility read). Rev 1 (2026-06-18) framed the call rule as new spec content and overloaded the `trAssumptions` channel; Rev 2 reframes it as *surfacing already-shipped v0.9.0 assume-guarantee composition*, splits the channel per the TCB-boundary finding, corrects four field/scope errors the engineer caught, and re-scopes recursion as future-R7 (not permanent / not Lean).
> **Date:** 2026-06-18 (Rev 1; Rev 2)
> **Working handle:** DEMO-COMP (roadmap tag to be assigned by documentation-lead)
> **Implements:** surfaces shipped compositional (assume-guarantee) verification — `LLMLL.md §2` (line 56), `§5.3.3` (lines 983–1006, esp. the trust-tier side-condition at 998), `§4.2` (line 1000), the "v0.9.0 assume-guarantee tier" at line 1044 — into the agent-facing obligation report, checkout brief, and patch surfaces; closes the two plumbed-but-unpopulated `checkout` fields named in `examples/withdraw-demo/DemoPost.md:565-577`.
> **Prerequisites:** v0.9.0 compositional verification (`CallVC`, `FixpointEmit.hs:135-139`); OBLIG-0/1 (obligation report + inline checkout brief); `TrustReport.hs` transitive closure (`teEffectiveLevel`, `refutedClosure`); Bundle B0 effect_summary (the runbook §7 authority axis). Feature freeze **lifted** for v0.11+.
> **Reviewed:** Professor consult A (2026-06-18, assumptions-channel split — closes §9.1 *resolved-yes*); Professor consult B (2026-06-18, recursive-composition boundary — closes §9.2: QF-LIA-but-unbuilt, roadmap R7); compiler-engineer feasibility read (2026-06-18 — confirms net-new verification logic = zero; four field/scope corrections F2–F5 folded; F1 recursion-fence finding folded with empirical refinement). No standalone `-review.md` files were produced; the three consults are folded directly in the Appendix per the REF-META appendix pattern.
> **Status:** **Rev 4 — VIABLE (composition reaches `verified`, CLI-confirmed). Infra green.** Remaining: Rev-5 reshape of the §10 fixture onto working shapes + runbook cold-pattern handling + three targeted DX/display fixes (DEFECT-1/2/3). The Rev-3 "BLOCKED / Wall C" framing was a misdiagnosis, corrected in §0.

---

## 0. Implementation findings — Rev 4 (READ FIRST; supersedes earlier §0 and §3.3/§5/§6/§10)

Implemented and **empirically verified through the CLI (2026-06-18/19)**. **Composition DOES reach trust-tier `verified` — the demo is viable.** Firsthand confirmation: a module with a pre-free leaf `double` plus three composers — whole-body call `(double x)`, let-bound call→call chain `(let [[t (double x)]] (double t))`, and let-bound call→builtin-op `(let [[d (double x)]] (+ d 1))` — verifies SAFE with **`verified: 4, asserted: 0`** (every composer `post: verified`). The project's own `examples/banking_ledger` (four `def-shell` composers, all `post: verified` in its CLI-produced sidecar) corroborates. Adjudication (engineer ground-truth + professor): **(c) the spec is *correct*** — `§5.3.5`'s ✅✅✅✅ is a true body-VC-emission claim; the earlier "Wall C — composition never reaches `verified`" conclusion was a **misdiagnosis** (corrected below).

**Two traps that produced the false Rev-3 conclusion (both now understood):**
1. **The cold `--trust-report` render.** `llmll verify --trust-report` renders the `.verified.json` sidecar, written *during* the run — so on a **cold first pass** it shows every function `asserted` even when the run is SAFE and all bodies are body-faithful. Run `verify` (writes the sidecar) *then* `verify --trust-report` (reads it), or run twice. The Rev-3 probes read the cold render and mistook it for fallback. *(This is itself a real DX wart — DEFECT-3.)*
2. **Non-working fixture shapes.** Three shapes genuinely fall back at emission (`bodyToPredM` constraint-gen limits): inline `(+ (g x) 1)` (call result as a builtin-op operand *without* a let-binding) and nested-call args `(g (h x) y)`. **Working shapes:** whole-body single call; let-bound chains (incl. `(let [[d (g x)]] (+ d 1))`). **The §10 fixture's `quadruple = (double (double x))` and `withdraw-twice = (withdraw (withdraw …) …)` are BOTH nested-call args → they fall back and must be reshaped.**

**Standing corrections to the sections below:**
- **Wall A — admissibility: FIXED** ([`admit-verified-callee-proposal.md`](admit-verified-callee-proposal.md), green). `def-shell` composers (the banking_ledger pattern) reach `verified` single-pass. Strict-core `def`→`def` additionally needs a two-step *verify-leaf-then-re-verify* warm seed on a cold build — a DX gap (**DEFECT-2**), not a blocker.
- **Wall B — §3.3/§5 edge 2/§6/§10's "withdraw-twice → 2 call-site obligations" is FALSE** (nested-call-arg fallback → 0). The whole §10 fixture is built on nested-call shapes and must be reshaped to working forms.
- **DEFECT-1 (summary display, real, *entangled*):** the trust **summary** counts `teEffectiveLevel = meet(csPre, csPost)`, and `csPre` is always `asserted` (preconditions are caller obligations), so it counts every *pre-bearing* function `asserted` even when its `post:` is `verified`. The per-entry `post:` label is correct. **This is the same mechanism the existing withdraw-demo relies on for its intended "proven-but-assumed" floor** — so whether to change it is a language-team/professor adjudication, not a unilateral fix.

**Net:** the `consumed_guarantees` channel, the SAFE call-pre obligation, and the `callee-precondition-unmet` patch reason are real and shipped; **composition works; the demo is viable.** The remaining work is a **Rev 5 reshape** of the §10 fixture onto working shapes + a runbook that handles the verify-then-report cold pattern, plus three targeted DX/display fixes (DEFECT-1/2/3). No fundamental wall remains. *(The motivation/semantics sections below — §1, §4 — are substantially correct; only the §10 fixture shapes and the §3.3/§5/§6 obligation counts were wrong.)*

---

## 1. Motivation

The public repair-loop demo (`examples/withdraw-demo/`) stages **three independent leaf functions** with **zero call edges**, so the transitive-trust-closure subsystem — the literal subject of `TrustReport.hs` and the thing `--strict-verified-core` promises "transitively over the call graph" — runs on an empty graph: every `teDeps` is `[]`, every `teEffectiveLevel` equals the function's own level, `refutedClosure` never fires, and the `assumptions`/`available_functions` checkout fields come back empty *because there is nothing to assume and nothing to call*.

This is a **demonstration gap, not a capability gap**, and Rev 2 states the point Rev 1 under-cited: **LLMLL already ships the verification machinery.** Compositional reasoning has been spec-of-record since v0.9.0 — `LLMLL.md §2` (line 56): "when function `f` calls contracted function `g`, the verifier proves that `f` satisfies `g`'s precondition (obligation) and assumes `g`'s postcondition (hypothesis); this assume-guarantee composition is sound when both functions are independently verified; functions in recursive call cycles are excluded from compositional encoding." The engineer's read confirms it in code: `CallVC` (`FixpointEmit.hs:135-139`) carries `cvPreObligation` (PROVE, down) + `cvPostAssumption` (ASSUME, up), and `bodyToPredM (EApp …)` (`:874-928`) does the param→arg substitution, instantiating `pre_f[aᵢ/xᵢ]` (`:908`) and `post_f[aᵢ/xᵢ]` (`:916`). **Net-new verification logic for DEMO-COMP = zero; solver-time delta = 0ms.**

DEMO-COMP is therefore a **surfacing-and-field-population** change: it makes the shipped assume-guarantee accounting *visible to agents* (obligation report, checkout brief, patch result), and makes `withdraw`'s precondition — currently apologized for in the runbook with no caller to honor it — load-bearing. It is also the axis on which the **design-reference set** (Liquid Haskell, F\*, Dafny, Idris) sets the bar: modular contract verification under agent-authoring conditions, distinct from the Python/Go **measurement set**, which has no verification surface to compose at all. The perennial "isn't this a toy?" objection lands precisely because the demo shows no composition; a verified call edge answers it with machinery the project already trusts.

## 2. Scope

**In scope.** (a) Surfacing the shipped `T-App-Contract`/assume-guarantee accounting (§4) into three agent-facing surfaces. (b) A **separate `consumed_guarantees` channel** for discharged callee postconditions, distinct from the existing TCB-extension `assumptions` channel (§3.1; Professor A). (c) Population of the **contracted**-vocabulary list with `{pre, post, tier}` (§3.2; corrected target per engineer F2). (d) Per-call-site `PreconditionObligation` surfacing **on SAFE** + a discriminated patch sub-reason (§3.3). (e) A soundness constraint on how `callee_tier` is sourced for recursive callees (§5 edge 3; engineer F1, empirically refined). (f) A five-node demo fixture (§10).

**Out of scope — recursion, re-scoped (Professor B).** Recursive / mutually-recursive self-post assumption that would let a recursive function reach `verified` on its *own* post is excluded — but this is a **scoped-future extension (roadmap R7), not a permanent fragment limit, and not a Lean problem** (Rev 1 mis-stated it as a Lean escape). The descent obligation `μ(args') < μ(args)` is the same QF-LIA shape as the already-shipped non-negativity obligation `μ ≥ 0` (`FixpointEmit.hs:486-489`, §5.3.3 Termination = Shipped); the permanent fragment boundary is the **Liquid Haskell boundary**: linear/lexicographic measures auto-discharge in QF-LIA, structural-only measures escape via the existing `?proof-required(complex-decreases)`. R7 is a constraint-emission task plus a trust-tier increment (§9), not a fragment change. DEMO-COMP keeps the fence; the demo fixture is straight-line.

**Also out of scope.** Any change to the trust `meet`/closure algorithm (shipped, correct). Effect/authority composition (Bundle B0, already in runbook §7). No new builtin, no new surface syntax.

## 3. Surface (schema delta)

Additive deltas to the obligation report (`ObligationAssembly.hs`) and the checkout brief (`Checkout.hs`). Schema bump: `orSchemaVersion "0.12.0" → "0.12.1"`; add a `brief_version` field (the brief is currently unversioned — engineer F4).

### 3.1 Two separate channels — `assumptions` (TCB) vs. `consumed_guarantees` (discharged)

Rev 1 proposed tagging two kinds inside `trAssumptions`. **Rev 2 splits them into separate channels**, on Professor A's finding that this is the **TCB boundary** — the most-named distinction in deductive verification (Liquid Haskell `assume` vs. checked signatures; Dafny `assume`/`{:axiom}` vs. consumed `ensures`; F\* `assume` vs. `Lemma`). A discharged callee post is **not an assumption** — in rely-guarantee terms it is the callee's *guarantee* consumed as an *available hypothesis*, the opposite of a TCB escape hatch. The engineer corroborates from the type side: `AssumptionKind` is `Ord`-derived (`Syntax.hs:401-405`, lattice-positioned), so a discharged post — which is not order-comparable with escape hatches — does not belong in that type at all.

- **`assumptions`** (existing `trAssumptions`, reserved): genuine TCB extensions — the `AssumptionKind = AKRuntimePrimitive | AKCompilerBuiltin | AKExternalOpaque` escape hatches. **Do not add a fourth constructor** (it would mis-floor a verified-through-composition function like `quadruple` by filing a *proven* fact in the *unproven* bucket).
- **`consumed_guarantees`** (new, orthogonal informational channel — mirrors the `effect_summary` precedent at `LLMLL.md:1837`, which "never affects a function's trust tier"):

```json
{ "callee": "double",
  "guarantee": "(= result (+ x x))",
  "instantiated": "(= <call-result> (+ x x))",
  "callee_tier": "verified",
  "status": "discharged" }
```

The discriminating value pair is **`discharged` vs. `admitted`/`axiom`** (Dafny/F\*'s own words), **not** Rev 1's `trust-provenance` tag (which described both kinds and so named nothing). On the brief side, **keep `ctAssumptions :: Maybe [Text]` unchanged** (escape-hatch labels) and **add a new structured `ctConsumedGuarantees` field** — this resolves engineer F3 (no breaking type change to the existing field).

> **Honesty carve-out (engineer F5).** The `instantiated` *up-hypothesis* `post_f[aᵢ/xᵢ]` is **not** in the constraint table — it is a hypothesis with no goal constraint, living transiently in `CallVC.cvPostAssumption`. To populate it, the assembler re-runs the (pure, re-callable) substitution against the `ContractEnv`. The field therefore carries **re-derived, not solver-witnessed, text** — the one genuinely net-new *extraction* (not net-new *verification*). The `status: discharged` claim rests on the callee's own verification, surfaced via `callee_tier`, not on this string.

### 3.2 Contracted-vocabulary list with `{pre, post, tier}` (corrected target — engineer F2)

Rev 1 targeted `ooAvailableFns` (`:969`). **That field is builtins-only and contractless**; the callable *contracted user* vocabulary the demo wants (`double`, `withdraw` with their contracts) lives in `ooContractedFns`, already populated for hole obligations (`:822`). Rev 2 retargets the seam: add `pre`, `post`, `tier`, `return_type` to the **`contracted`** record (`assembleFunctionLists`, `:633-663`) and to the brief's `FuncEntry` (`Checkout.hs:90-107`, currently `{name, params, returns, status}`). The brief's agent-facing `available_functions` is the `ctAvailableFunctions` merge in `Checkout.hs`, a separate object from `ooAvailableFns` — the schema/doc must name precisely which is which.

### 3.3 Call-site obligation — first-class entry (on SAFE) + discriminated patch reason

`PreconditionObligation` is wired (`ObligationAssembly.hs:90,197`) but assembled **only on `FQUnsafe`** (`:714-718`). Rev 2: emit it **per call site on SAFE too**, reusing the existing `call-pre:<callee>` constraint origins (`FixpointEmit.hs:617-618`) and `coJsonPtr` pointers — a report-level read of constraints already solved (count rises by contracted-call-site count: `withdraw-twice` → 2, `quadruple` → 0). And give `patch` a discriminated sub-reason **as an optional payload on the existing `PatchVerifyError`** (not a new constructor — preserves existing consumers; engineer):

```json
{ "result": "PatchVerifyError",
  "reason": "callee-precondition-unmet",
  "callee": "withdraw",
  "required_pre": "(>= balance amount)",
  "call_site_pointer": "/statements/4/body/args/0" }
```

keyed on the `call-pre:` origin tag at the verify-fail branch (`PatchApply.hs:265`). This turns the demo's two-channel rejection (type → body-post) into a **three-shape** rejection (type → body-post → call-site-pre).

## 4. Semantics — the modular call rule (shipped; restated for the record)

This restates `LLMLL.md §5.3.3` / §2's assume-guarantee composition; it is **not new spec**. For a call `(f a₁ … aₙ)` to a contracted callee `f`:

```
  Γ ⊢ aᵢ : Tᵢ                                    (type channel, existing)
  Γ ; PC ⊢ pre_f[aᵢ/xᵢ]                          -- call-site obligation, PROVE / down (CallVC.cvPreObligation)
  ──────────────────────────────────────────────────────────────────  [T-App-Contract]
  Γ ⊢ (f a₁ … aₙ) : T_f   with  result ▷ post_f[aᵢ/xᵢ]
                                                  -- ASSUME / up hypothesis (CallVC.cvPostAssumption)
```

The two accountings the runbook calls "orthogonal" are exactly the **assume-guarantee decomposition** the spec already names: the VC is the *guarantee discharge*; the tier `meet` (`teEffectiveLevel = meet(self, ⊓ callees)`, `TrustReport.hs:60,214-218`) is the *rely propagation*. Refinement-predicate instantiation is substitution of actuals into the callee contract, staying QF-LIA where the callee contract is QF-LIA (e.g. `double.post[double x/x]` ⇒ hypothesis `r₁ = x+x`, linear; `withdraw.pre` at the outer site ⇒ goal `(balance−amount) ≥ amount`, linear).

## 5. Edge cases and degenerate inputs

1. **Callee only `asserted` (has its own pre).** `withdraw-twice` over `withdraw`. The body leans on `withdraw`'s proven *post*, yet the function transitively inherits `withdraw`'s `asserted` floor via `meet`. **Channel: trust.** Post-line `verified`, effective-line `asserted` — the §6 two-number story across an edge. Cite `TrustReport.hs:60`; `LLMLL.md §4.4.1` (evidenceMeet); `§4.4.5` side-cond 6.
2. **Caller fails to discharge callee precondition.** `withdraw-twice` with pre weakened to `(>= balance amount)` — the outer call's obligation `(balance−amount) ≥ amount` is unmet. **Channel: contract.** `PatchVerifyError / callee-precondition-unmet` at the outer call site, distinct from a body-post failure. Cite `FixpointEmit.hs:617`; `ObligationAssembly.hs:90`.
3. **Recursive callee, consumed by a caller (soundness-critical — engineer F1, refined).** By design (`FixpointEmit.hs:870-873`, "Issue 4 resolution: SCC guard removed"), a recursive callee's *own body VC* is excluded (`§5.3.5` line 1031), so its tier is **already degraded** (contract-only, not body-faithful), and a caller may assume-guarantee against its degraded contract. **The `consumed_guarantees` record is sound iff `callee_tier` is sourced from the callee's actual `teEffectiveLevel`, never a hardcoded `verified`** — for a recursive callee that tier is already below `verified`, so no false "proven" label arises. **Defensive constraint:** filter self/SCC self-edges from `consumed_guarantees` via `recursiveNames` (`ObligationAssembly.hs:280,696`) — a function listing its *own* post is meaningless, not just unsound. **Channel: trust.** *Note:* self-recursive `def` is a hard error under the current `GrammarCoreInversion` (`checkCalleeAdmissibility`, core-membership-violation); the warning-only path is `GrammarLegacy`-only (`TypeCheck.hs:1052`) — confirm `GrammarLegacy` reachability, but it is not a DEMO-COMP blocker given the `callee_tier`-sourcing constraint.
4. **Callee `refuted` / UNSAFE, caller depends on it.** `refutedClosure` (`TrustReport.hs:276-281`) marks transitive callers `depends-on-refuted`; `--strict-verified-core` errors transitively. **Channel: trust.** Shipped; the new fixture finally exercises it.
5. **Mutually recursive callees (cycle).** Same as (3) under the SCC analysis; the `recursiveNames` filter and `callee_tier`-from-`teEffectiveLevel` rule cover it. **Channel: trust (out of demo scope).**

## 6. Verification mapping

| Obligation | Channel | Fragment | Cite |
|---|---|---|---|
| Caller body VC with callee-post hypothesis (`quadruple` ⊢ `result = 4x` given `r = x+x`) | contract | **QF-LIA**, auto-discharged (shipped `CallVC`) | `LLMLL.md §5.3.3`; `FixpointEmit.hs:874-928` |
| Call-site precondition (`(balance−amount) ≥ amount`) | contract | **QF-LIA**, auto-discharged (shipped `call-pre:`) | `LLMLL.md §5.3.5`; `FixpointEmit.hs:617` |
| Transitive trust floor (`meet(self, withdraw) = asserted`) | trust | **not an SMT obligation** — lattice meet, pure | `TrustReport.hs:60,214-218` |
| Recursive self-post → `verified` (out of scope; future R7) | contract | **QF-LIA but unbuilt** — descent `μ(args')<μ(args)` is the same shape as the shipped `μ≥0`; **not a Lean escape** | `FixpointEmit.hs:486-489`; §5.3.3 Termination row; roadmap R7 |

Everything in the fixture stays **QF-LIA, auto-discharged — no Lean, no nonlinear strengthening**. The recursion row is corrected from Rev 1's "escapes to Lean": it is an *unbuilt QF-LIA constraint* (Professor B), a far cheaper future than Rev 1 implied.

## 7. Affected surface (engineer's module map)

- `compiler/src/LLMLL/ObligationAssembly.hs` — new `consumed_guarantees` assembler (typed record → `Value`, not hand-built objects, for test-stability), sourcing `callee_tier` from the trust report and filtering `recursiveNames` (`:280`); add `pre/post/tier/return_type` to the **`contracted`** record (`:633-663`); assemble per-call-site `PreconditionObligation` on SAFE from `call-pre:` origins (`:714-718`); bump `orSchemaVersion` (`:733`).
- `compiler/src/LLMLL/FixpointEmit.hs` — **no emission change.** Re-derive the `instantiated` post via the pure substitution against `ContractEnv` (engineer F5); prefer recovering call-site pointers from the `ConstraintTable` (`call-pre:` origins) over adding an `EmitResult` field (avoids large GHC fan-out).
- `compiler/src/LLMLL/Checkout.hs` — extend `FuncEntry` with `fePre/fePost/feTier` (`:90-107`); **add** `ctConsumedGuarantees :: Maybe [Value]` (leave `ctAssumptions :: Maybe [Text]` unchanged); thread through `CheckoutContext`; add `brief_version`.
- `compiler/src/LLMLL/PatchApply.hs` — optional `CalleePreUnmet` payload on `PatchVerifyError` (`:78-84`); populate at the verify-fail branch by inspecting `call-pre:` origins (`:265`).
- `compiler/app/Main.hs` — wire the two deferred `Nothing`s: `ccFunctions` (`:1666`), `ccConsumedGuarantees` (`:1672`).
- `docs/llmll-ast.schema.json` — additive: `contracted_functions[].{pre,post,tier,return_type}`, `consumed_guarantees[]` object, the SAFE `precondition-obligation` entry, the patch `callee-precondition-unmet` reason, `brief_version`.
- `LLMLL.md §11` / `§4.4` (cross-reference §5.3.3/§4.2 assume-guarantee), `docs/compiler-team-roadmap.md` (new `[CT]` row) — **documentation-lead, post-ship.**

## 8. Risks and open questions

1. **`callee_tier` mis-sourcing for recursive callees** *(soundness).* If the `consumed_guarantees` assembler hardcodes `verified` instead of reading `teEffectiveLevel`, a recursive callee's degraded contract reads as proven. **Bite: blocks the channel's "discharged" claim until sourced correctly** — §5 edge 3 constraint + the `recursiveNames` filter; test case 6 is its guard.
2. **`instantiated` is re-derived, not solver-witnessed** *(verification-ergonomics).* Engineer F5. **Bite: complicates seam 1** — mitigated by re-running the pure substitution; the `status: discharged` claim rests on `callee_tier`, not the string.
3. **Separate `consumed_guarantees` channel vs. wire-economy** *(scope — user-override point).* Professor A's open question: is any downstream consumer required to receive discharged-posts and escape-hatches in one array? The engineer found no hard requirement, so the separate channel is free to add (recommended). **Bite: only if a single-array wire-shape is later mandated** — fallback is one neutral `dependencies` array with `status ∈ {discharged, admitted}`.
4. **Brief unversioned** *(spec-drift).* `CheckoutToken` has no schema-version field. **Bite: mechanical** — add `brief_version` in the same change.
5. **Obligation-report JSON churn** *(spec-drift).* Additive, but the runbook pins exact JSON; `jq` projections need re-capture. **Bite: mechanical** — one golden re-capture pass (~6 modules recompile, <1s test runtime, 0ms solver; single-commit rollback, no `.fq`/`.verified.json` migration).

## 9. Open questions — disposition

- **§9.1 (assumptions split) — RESOLVED-YES (Professor A).** The proven-vs-assumed split is the TCB boundary, named across LH/Dafny/F\*. Decision: separate `consumed_guarantees` channel, tags `discharged`/`admitted`, no fourth `AssumptionKind`. Folded into §3.1.
- **§9.2 (recursive self-post) — RESOLVED (Professor B).** Non-recursive is correct for the demo and this release; the permanent boundary is the LH boundary (arithmetic measures auto-discharge, structural escape). Folded into §2/§6.
- **Carried to roadmap R7 (downstream of DEMO-COMP, not blockers):** (a) specify the trust-tier rule for *descent-discharged* recursion before R7 reaches the compiler — the lattice currently has no slot for "postcondition proven, termination assumed"; (b) confirm the first R7 increment is single-variable `:decreases n` (recommended) vs. fixed-arity lexicographic (adds a bounded disjunctive QF-LIA encoding). These are language-team items *before* they are compiler items.

## 10. Demo fixture (downstream demo-construction target)

Five-node call graph; `quadruple` (clean `verified` *through* `double`) and `withdraw-twice` (inherits `withdraw`'s `asserted` floor transitively, discharges `withdraw.pre` at both call sites):

```lisp
;; existing leaves: withdraw (pre+post, asserted-floor), double (no-pre, verified), maxi (no-pre, verified)

(def quadruple [x: int]
  (post (= result (+ (+ x x) (+ x x))))
  (double (double x)))                          ; leans on double.post twice; double has no pre → no call-site obligation

(def withdraw-twice [balance: int amount: PositiveInt]
  (pre  (>= balance (+ amount amount)))
  (post (= result (- balance (+ amount amount))))
  (withdraw (withdraw balance amount) amount))   ; leans on withdraw.post twice; MUST discharge withdraw.pre at both sites
```

Three new didactic beats: **trust flows up** (`quadruple` reaches `verified` through `double`); **trust floors** (`withdraw-twice` inherits `asserted` transitively — an assumed precondition cannot be laundered by wrapping); **obligation flows down** (the bad-fill: weaken `withdraw-twice`'s pre → `callee-precondition-unmet` at the outer site). The runbook step slots between current §5 and §6; the ending stays on the trust report. **A test-only recursion-fence negative fixture** (a `recursiveNames` member that must emit *no* self-edge `consumed_guarantee`) is required by §5 edge 3 and is **not** part of the §10 demo fixture.

---

## Appendix — Consult log (Rev 2)

**Professor A — assumptions-channel split (folded into §3.1).** The proven-vs-assumed distinction is the TCB boundary (LH `assume` vs. checked; Dafny `assume`/`{:axiom}` vs. consumed `ensures`; F\* `assume` vs. `Lemma`). "Assumption" is the wrong word for a discharged callee post (rely-guarantee: it is a *consumed guarantee / available hypothesis*). Adopt a separate channel; do not add a fourth `AssumptionKind`; tags `discharged` vs. `admitted`, not `trust-provenance`. *Citation correction (verified against HEAD):* A cited "§4.4.6" as the spec's assume-guarantee accounting — §4.4.6 is **CDP**; the actual loci are §2 (line 56), §5.3.3 (lines 983–1006, esp. 998), §4.2 (line 1000), and the "v0.9.0 assume-guarantee tier" at line 1044. A ran without WebSearch; external citations are from knowledge, flagged for primary-source check before any LLMLL.md promotion.

**Professor B — recursive-composition boundary (folded into §2/§6/§9).** The fence is sound and stays, but recursion is **not** a Lean problem: the descent obligation `μ(args')<μ(args)` is the same QF-LIA shape as the shipped `μ≥0` (`FixpointEmit.hs:486-489`), making it roadmap R7 (constraint-emission + tier-rule increment), not a fragment extension. Permanent boundary = the Liquid Haskell boundary. R7 needs a trust-tier rule for "termination-discharged recursion" *first* (language-team).

**Compiler-engineer — feasibility (folded throughout).** Confirms net-new verification logic = zero (`CallVC` ships `[T-App-Contract]` in full); 0ms solver delta; ~6 modules recompile; 570 → ~585 tests; single-commit rollback. Corrections: **F2** retarget the contracted-vocabulary seam from `ooAvailableFns` (builtins-only) to `ooContractedFns`; **F3** keep `ctAssumptions :: Maybe [Text]`, add a new structured field (resolved by the separate-channel decision); **F5** the `instantiated` up-hypothesis is re-derived, not solver-witnessed — the one net-new *extraction*; **F1** the recursion hazard, empirically refined: the SCC guard removal is *by design*, a recursive callee's tier is already degraded, so the real lever is sourcing `callee_tier` from `teEffectiveLevel` (never hardcoded) plus a defensive `recursiveNames` self-edge filter — and self-recursive `def` is already a hard error under the current `GrammarCoreInversion` grammar.
