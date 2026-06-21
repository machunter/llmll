# DEF-RET — Optional Return-Type Annotation for `def` / `def-shell`

> **Version:** Rev 3 — Unit 2 shipped (v0.13.2): the deferred `augmentContractPost` discharge join landed; return refinement now discharges + exports + is staleness-hash-covered (see Rev 3 addendum). Rev 2 folded the professor review (coherence question settled; monotonicity claim corrected to two named properties; the post-clause tier interaction resolved inward via the §3.4.1 introduction/elimination split + §3.4.5 firewall). Rev 1 (2026-06-20) was the initial drift-closure proposal.
> **Date:** 2026-06-20 (Rev 1; Rev 2); 2026-06-21 (Rev 3)
> **Implements:** unblocks `OBLIG-1-FOLLOWON` (`docs/compiler-team-roadmap.md`) — the `expected_return_type` body-hole value path. Closes a spec-vs-surface drift between REF-META-5 (`LLMLL.md §3.4.6`) and the §12 grammar.
> **Prerequisites:** None new. The AST (`SDef`/`SDefShell` carry `mRet :: Maybe Type`), `collectTopLevel` ([`TypeCheck.hs:680-683`](../../compiler/src/LLMLL/TypeCheck.hs)), and `checkStatement` ([`:786-823`](../../compiler/src/LLMLL/TypeCheck.hs)) already handle `Just retTy`. The `checkExpr`-at-return change is already built on branch `oblig-1-followon/expected-return-type` (professor-cleared). The return-refinement introduction join in `FixpointEmit` is new (Rev 2; mirrors `augmentContractPre` at [`FixpointEmit.hs:1361-1368`](../../compiler/src/LLMLL/FixpointEmit.hs)).
> **Origin:** OBLIG-1-FOLLOWON investigation (2026-06-20). The `expected_return_type` field is reserved/unpopulated because a function-body hole under a declared return is recorded `HoleUnknown`; the root cause is that `def`/`def-shell` have no return-type surface in either frontend (`Parser.hs:212/233`, `ParserJSON.hs:218/231`) and the schema's `DefCore`/`DefShell` lack a `return_type` property.
> **Reviewed:** Professor review (2026-06-20, in-conversation) — coherence question adjudicated (not a smell; hybrid/refinement/gradual-typing-standard), one monotonicity correction, one soundness item (post tier) resolved inward. Folded as `## Appendix — Professor review log`; no standalone `-review.md`.
> **Status:** Settled (Rev 3) — **Shipped:** Unit 1 v0.13.1 (surface + checking + `expected_return_type` value path; conservative refinement-return fallback); Unit 2 v0.13.2 (commits `0b27be5`/`12210b0` — `augmentContractPost` discharge + export + staleness-hash coverage). See Rev 3 addendum.

---

## 1. Motivation

`expected_return_type` (checkout brief / sketch / obligation report) tells an agent the type shape a function-body hole must produce. It is empirically empty for the canonical case: the withdraw demo's `?body_impl`/`?maxi_body` report `inferredType: null`. The root cause is neither plumbing nor the type-checker — it is that **`def`/`def-shell` have no surface to declare a return type.** `pDef`/`pDefShell` hardcode `mRet = Nothing` (`Parser.hs:212,233`); `parseDefCore`/`parseDefShellJSON` hardcode `Nothing` (`ParserJSON.hs:218,231`); the `DefCore`/`DefShell` schema `$defs` (`llmll-ast.schema.json:55,112`) have no `return_type`. So `mRet` is structurally always `Nothing`, and a body hole has no declared type to report.

**Spec-vs-surface drift (the load-bearing finding).** REF-META-5 / §3.4.6 (`LLMLL.md:430`, shipped v0.12.0) already states the checker supplies expected types "at parameter / **return** / annotated-`let` positions (checked via Check-by-Synth; `⇐-Refine` when the annotation is a refinement alias) and at holes (Check-Hole)." The AST slot (`mRet`), `collectTopLevel`, and `checkStatement` all already consume `Just retTy`. Only the two parsers and the schema fail to *produce* it. The metatheory and the compiler internals presuppose a return-position expected type the grammar cannot express. This is almost certainly a regression introduced by the LT-INV `def-logic → def/def-shell` migration. The proposal closes the drift by **adding surface, not weakening §3.4.6** (see Appendix — convergence with the professor).

## 2. Scope

**In scope.** An *optional* return-type annotation on `def`/`def-shell` (both frontends), the schema delta, and the `FixpointEmit` treatment of a refinement-aliased return.

**Out of scope.** Required returns (breaks backward-compat, contradicts synthesis-primary §3.4.6). Post-derived hole-type inference (deriving a hole's type from the `post` predicate) — a distinct heuristic mechanism, deliberately excluded, possibly a future proposal. Return annotations on legacy `letrec`/`def-logic` (def-logic removed v0.12.1). The other reserved OBLIG-1-FOLLOWON fields (`available_functions`, `assumptions`).

## 3. Surface

**S-expression** — optional `-> RetType` immediately after the parameter brackets, before contract clauses (mirrors the existing `pFnType` `[params] -> ret` idiom, `Parser.hs:279-289`, and the `pArrowSym` token at `:50-51`):

```
(def withdraw [balance: int amount: PositiveInt] -> int
  (pre  (>= balance amount))
  (post (= result (- balance amount)))
  ?body_impl)
```

Absent the `->`, parsing and semantics are byte-identical to today (`mRet = Nothing`).

**JSON-AST** — optional `return_type` field (a `Type`) on `DefCore`/`DefShell`, reusing the existing `o .: "return_type" >>= parseType` idiom (`ParserJSON.hs:447,659`):

```json
{ "kind": "def", "name": "withdraw", "params": [...],
  "return_type": { "kind": "int" },
  "post": ..., "body": { "kind": "hole", "name": "body_impl" } }
```

## 4. Semantics

Optional, checking-mode. Two rules, both already implemented in `checkStatement`:

- **DEF-RET-DECLARED** (`mRet = Just T`): `Γ, params ⊢ body ⇐ T`. Check-Hole at a hole body records `HoleTyped T` (`TypeCheck.hs:996-997`); Check-by-Synth otherwise (`inferExpr body >>= unify T`, mismatch attributed to the function `name`). This is §3.4.6 specialized to the def-body return position.
- **DEF-RET-INFER** (`mRet = Nothing`): `Γ, params ⊢ body ⇒ T'`. Unchanged from today.

Optionality is correct, not required: §3.4.6 frames the checker as **synthesis-primary** — the annotation is a refinement supplying an expected type, not a precondition for type-checking.

### 4.1 Monotonicity (two named properties)

Adding a return annotation satisfies (these replace Rev 1's over-strong "never changes which programs type-check," which is false — the annotation *can* narrow acceptance):

- **Acceptance-conservativity (downward).** It never *widens* the set of accepted concrete (hole-free) programs — there is no subsumption to loosen — only *narrows* it by rejecting `declared ≠ inferred`. Removing it never narrows. This is the **static gradual guarantee** (Siek–Vitousek–Cimini–Boyland, *Refined Criteria for Gradual Typing*, SNAPL 2015) specialized to optional return annotations; true here because `checkExpr e T = inferExpr e >>= unify T` for non-holes (`TypeCheck.hs:1001`), so the annotated form accepts a subset.
- **Obligation-additivity.** A refinement-aliased return only *adds* the §3.4.1 obligation; no obligation is removed by adding an annotation. This is the hybrid-type-checking property (Knowles–Flanagan, *Hybrid Type Checking*, TOPLAS 2010 — a refinement annotation generates a static obligation).

### 4.2 Refinement-aliased return: introduction at the return, elimination in the post

For `-> A` where `A ≜ (where [x:τ] p)`:

- **Return position = §3.4.1 introduction.** Checking the body against `A` makes `p[body/result]` join the body-VC obligation set (`LLMLL.md:273-283`), co-discharged with the `post` against `result = ⟦body⟧`. On a concrete body, e.g. `(def f [x:int] -> PositiveInt (+ x 1))` incurs `(> (+ x 1) 0)`. This is a verification enrichment via existing machinery — implemented as the guarantee-side mirror of `augmentContractPre` (`FixpointEmit.hs:1361-1368`), call it an `augmentContractPost`-style introduction join.
- **`result : A` in the post = §3.4.1 elimination.** `(> result 0)` is available to the post-VC as a lexically-scoped hypothesis (the post-clause `result` is typed at `T`, `TypeCheck.hs:809/836`).
- **Soundness of the post eliminating the return refinement — by the §3.4.5 firewall, no new side condition.** If the return refinement is non-`Σ_auto` it is non-emittable (`exprToPred → Nothing`), forcing `erBodyFallback` and excluding the function — and its post — from `verified`/strict-core (`LLMLL.md §3.4.5:379`, §3.4.3). So there is **no path** where the post reads `verified` while eliminating an only-`asserted` return refinement; the tier meet the professor flagged (`meet(post-evidence, return-refinement-tier)`) is enforced by the existing firewall, not new machinery. **The engineer must gate the post's result-elimination hypothesis on the same emittability check** so a non-emittable return refinement does not silently seed the post-VC.

## 5. Edge cases and degenerate inputs

1. **Declared ≠ inferred, concrete body** — `(def f [x:int] -> string (+ x 1))`. *Behavior:* type error attributed to `f`. *Channel:* type. *Cite:* `TypeCheck.hs:786-823` (Just-concrete branch).
2. **Refinement-aliased return, concrete body** — `(def f [x:int] -> PositiveInt (+ x 1))`. *Behavior:* §3.4.1 introduction obligation `(> (+ x 1) 0)`; verified/asserted per its fragment. *Channel:* contract. *Cite:* §3.4.1 / §3.4.6 `⇐-Refine`; §4.2.
3. **Bare-hole body under declared return** — `(def f [...] -> int ?body)`. *Behavior:* `?body` records `HoleTyped int`; `expected_return_type: "int"` (the value path). *Channel:* type. *Cite:* `TypeCheck.hs:996-997`.
4. **Declared return over `EIf`/`EMatch` body with branch holes** — `(def f [b:bool] -> int (if b ?x ?y))`. *Behavior:* the overall if-type unifies with `int`, but `?x`/`?y` are typed from their **siblings** (or `HoleUnknown` if both holes), **not** from `retTy` — `checkExpr (EIf …)` falls through to `inferExpr` (no EIf checkExpr clause). *Channel:* type. *Cite:* professor review (sibling propagation is more specific than the return; do not override).
5. **No annotation** — unchanged; `mRet = Nothing`, full inference, `expected_return_type` absent. *Channel:* spec is silent (intentional — backward compatibility).
6. **Non-`Σ_auto` refinement-aliased return** — `(def f [...] -> BlockID …)` with `BlockID ≜ (where [s:string] (regex-match …))`. *Behavior:* the return-refinement introduction obligation is non-emittable → `erBodyFallback` → function (and post) excluded from `verified`; the post cannot inherit `verified` while eliminating the asserted return refinement. *Channel:* trust (firewall). *Cite:* `§3.4.5:379`, `§5.3.3`. This is the firewall-gated case that makes edge case 2/the §4.2 elimination sound.

## 6. Verification mapping

The annotation **mechanism introduces no new proof obligation** (§3.4.6: "introduces no new proof obligation and no new channel").

- **Type channel** (always): `body ⇐ T` is type-equality `≡` via `unify` (`TypeCheck.hs:1001`); no VC.
- **Contract channel** (refinement-aliased return only): the §3.4.1 introduction obligation `p[body/result]`, joined to the body-VC goal alongside the post; classified per `LLMLL.md §5.3.3` — **QF-LIA core / measure-class auto-discharged / non-`Σ_auto` → `erBodyFallback`** (§3.4.5). The post's result-elimination hypothesis is the same predicate, firewall-gated. Same fragment behavior as any existing refinement introduction/elimination pair; **nothing new escapes to Lean.**
- **Trust channel:** the function's effective tier is the meet over its own obligation set (post + return-refinement introduction), per the existing §3.4.3 strict-core closure. No new meet rule.

## 7. Affected surface

- `compiler/src/LLMLL/Parser.hs:198-203 / 219-224` — `pDef`/`pDefShell`: parse optional `pArrowSym *> pType` after `params`, before pre-clauses; pass to `SDef`/`SDefShell`.
- `compiler/src/LLMLL/ParserJSON.hs:209-218 / 222-231` — `parseDefCore`/`parseDefShellJSON`: parse optional `return_type`.
- `compiler/src/LLMLL/AstEmit.hs` — round-trip `return_type` **only when present** (else existing `.ast.json` round-trips change — see Risks).
- `compiler/src/LLMLL/TypeCheck.hs:786-823` — **already built** (the `checkExpr`-at-return change, professor-cleared, on branch); activates once parsers populate `mRet`.
- `compiler/src/LLMLL/FixpointEmit.hs` — **new (Rev 2):** the `augmentContractPost`-style return-refinement introduction join (mirror of `augmentContractPre` at `:1361-1368`), with the post's result-elimination hypothesis gated on `exprToPred` emittability.
- `compiler/src/LLMLL/Checkout.hs` + `app/Main.hs` — the `expected_return_type` plumbing (OBLIG-1-FOLLOWON) reads `shStatus`, which now carries `HoleTyped T` for body holes.
- `docs/llmll-ast.schema.json` — `DefCore`/`DefShell` + optional `return_type`; **`schemaVersion 0.6.0 → 0.7.0`** (engineer ships the schema with the patch).
- `LLMLL.md §9` (functions), `§12` (grammar EBNF: optional `("->" type)?`), `§3.4.x` (return position = introduction; post result-elimination = firewall-gated) — doc-lead, post-ship.
- `docs/compiler-team-roadmap.md` — `OBLIG-1-FOLLOWON` body-hole path unblocked — doc-lead.

## 8. Risks and open questions

1. **`AstEmit` must not emit `return_type` on `Nothing`** — *round-trip.* Add a round-trip regression test. *Bite:* complicates the emit patch.
2. **Return-refinement introduction join in `FixpointEmit`** — *soundness/scope.* New emitter work; must discharge the return refinement as an introduction obligation and gate the post's result-elimination hypothesis on emittability. *Cite:* `FixpointEmit.hs:1361-1368` (param-side analog). *Bite:* complicates the engineer plan; sound-by-construction once mirrored + firewall-gated.
3. **Schema bump `0.6.0 → 0.7.0`** — *scope.* Additive-optional, backward-compatible reads. *Bite:* external schema consumers only.
4. **Demo benefit requires demo edits** — *scope.* `withdraw`/`double`/`maxi` must declare `-> int`. *Bite:* one-line demo edits (experiment-lead/doc-lead), not blocking.
5. **Freeze policy** — *freeze-policy.* Freeze lifted (`roadmap:47`); written soundness argument: optional (no existing program changes), no new proof obligation or fragment (§3.4.6), reuses §3.4.1 machinery for refinement returns, AST/checker already implement it — completes wiring and closes a §3.4.6-vs-§12 drift rather than adding semantics.

## 9. Tracked-concept relation

- **Closes a spec-vs-surface drift** between REF-META-5 (§3.4.6, shipped v0.12.0) and the §12 grammar — not a new feature; the metatheory already prescribes the return position.
- **Unblocks** `OBLIG-1-FOLLOWON` (the body-hole `expected_return_type` value path).
- **Laundering adjudication.** Refinement-return laundering-by-omission is not a new surface (intrinsic to optional refinements everywhere; LH/F\*/Dafny), already measured by `--spec-coverage` and CDP (LT-CDP). In the orchestrator model, the return annotation is part of the **lead-authored signature** in the checkout brief — the hole-filler is held to it — so DEF-RET *reduces* the laundering surface in its intended use. DEF-RET refinement returns participate in `--spec-coverage`/CDP.

---

## Appendix — Professor review log

Professor review of Rev 1 (2026-06-20, in-conversation), folded per DOC-CONSOLIDATE M2.

- **Central coherence question — settled, not a smell.** An optional annotation that strengthens the static obligation set is the defining behavior of hybrid (Knowles–Flanagan, TOPLAS 2010) and refinement (Vazou et al., POPL 2014) type checking, not incoherence. The monotonicity is the **static gradual guarantee** (Siek et al., SNAPL 2015). Approved.
- **Monotonicity claim corrected (Rev 1 → Rev 2).** Rev 1's "never changes which programs type-check" is false — the annotation *can* narrow acceptance (reject `declared ≠ inferred`). Restated as acceptance-conservativity (downward) + obligation-additivity (§4.1).
- **Post-clause tier interaction — the one genuine soundness item, resolved inward (Rev 2 §4.2).** The professor framed `result : A` as putting `(> result 0)` in scope as a hypothesis for the post, raising whether `meet(post-evidence, return-refinement-tier)` must be a new side condition. Resolution: the return position is §3.4.1 *introduction* (obligation), the post's result-use is §3.4.1 *elimination* (hypothesis); the §3.4.5 firewall forces `erBodyFallback` on a non-`Σ_auto` return refinement, so the meet is enforced by existing machinery. The engineer must gate the post's elimination hypothesis on emittability.
- **Optionality confirmed** (inference-primary lineage: ML/Haskell/LH/F\*; required belongs to non-inferring Dafny/Java).
- **Convergence named:** close the drift by adding surface, not weakening §3.4.6 — language-team reached it from "AST/checker already wired for `Just retTy`," professor from "the metatheory is the source of truth; the parser lags."

---

## Rev 3 addendum — Unit 2 shipped (v0.13.2, commits `0b27be5` / `12210b0`)

Unit 2 lands the deferred `augmentContractPost` discharge join (§4.2). A refinement-aliased return now:

1. **Discharges** — `augmentContractPost` (the guarantee-side dual of `augmentContractPre`) folds the return refinement, instantiated at `result`, into the function's effective postcondition. The body-VC therefore proves `p[result/x]`: `verified` when `p` is `Σ_auto` and the body-VC is SAFE, `refuted` when the body violates it, `erBodyFallback` when `p` is non-`Σ_auto` — reached via the *existing* untranslatable-post fallback (`mPostPred = Nothing`), so the §4.2 "gate the post's elimination on emittability" requirement is satisfied with no special guard. The Unit-1 conservative `retRefined → addBodyFallback` branch ([`FixpointEmit.hs`](../../compiler/src/LLMLL/FixpointEmit.hs)) is removed.
2. **Exports** — the augmented post is folded in `buildContractEnv`, so a caller of `f : -> A` may assume the refinement via assume-guarantee (the §3.4.1 elimination at the call site). The composed tier rides the existing §5.3.4 meet: `verified` callee → composable `verified`; `asserted` → floored; `refuted` → not assumable. A bare `-> RetType` function (no explicit `post`) now gets a `csPost` slot and is credited `verified`.
3. **Is staleness-hash-covered** — `canonicalDefEvidenceHash` now hashes the augmented contract at write (`Main` `provenCS`) and on same-module revalidate (`TrustReport` `liveHashes` / `collectAllContractStatus`), so editing a `-> RetType` annotation or redefining an alias's predicate invalidates a stale verified sidecar. This also closes the pre-existing **param-side NIW** staleness hole. Recompute is same-module (alias map in scope) → reproducible; there is no cross-module recompute site. Existing v0.13.1 sidecars are one-time stale on upgrade (fail-closed demote-to-reverify, benign). Separately, the solver-less `--trust-report` staleness-bypass (raw `loadVerified` instead of the staleness-gated `entrySidecar`) is fixed.

**No schema change in Unit 2** (`schemaVersion` stays `0.7.0`; `trust_report_version` `1.4.0`). The cross-module digest-to-digest contingency (Risk-1) was reviewed and found unnecessary — the only cross-module recompute site already carries the callee's alias map; the residual **XMOD-STALE** cache-coherence invariant is recorded on the roadmap as a build-driver obligation for persistent `ModuleCache` holders (LSP/Serve/watch). See [`def-ret-staleness-hash-review.md`](def-ret-staleness-hash-review.md). 908 Haskell + 62 Python tests.
