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


## Appendix — Professor review log (DEF-RET staleness-hash)

_Folded from `def-ret-staleness-hash-review.md` (DEF-RET shipped; standalone review archived to `../archive/professor-reviews/def-ret-staleness-hash-review.md`)._

# Professor review — DEF-RET augmented-hash staleness, the digest-to-digest cross-module fallback

Scope: the soundness of the *Risk-1 contingency fallback* only — "persist the resolved refinement predicate into the callee's sidecar at write time, and have cross-module staleness compare digest-to-digest, never re-resolving foreign aliases at the boundary." This is not a review of the settled DEF-RET augmented-hash fix (hashing the alias-resolved `augmentContractPre`/`augmentContractPost` output), which I take as given.

## Restatement

The contingency is: *if* a cross-module path were ever found to recompute an imported callee's evidence hash without the callee's alias map, the fix is to never recompute it across the boundary at all. Instead the callee's own (alias-in-scope) write-time computation is the sole producer of the digest, the digest is persisted in the callee's sidecar, and the importer's staleness check is a pure equality of *persisted digests* — the importer reads the callee's regenerated sidecar digest rather than re-deriving anything from the callee's source. The three questions are: (1) is digest-to-digest sound against alias redefinition; (2) does it reintroduce a surface-text-style redefinition gap *at the boundary*, and what invariant closes it; (3) is this the standard separate-compilation staleness discipline.

## Context located

1. `compiler/src/LLMLL/PBT.hs:585-606` — `canonicalDefEvidenceHash body mPre mPost`; SHA-256 over `(body, pre, post)` + `admitVerifiedSemanticsTag`. The settled DEF-RET fix moves the `mPre`/`mPost` it receives from RAW to alias-augmented; the hash *primitive* is alias-agnostic — it hashes whatever pre/post it is handed.
2. `compiler/src/LLMLL/TrustReport.hs:412-461` — `downgradeStaleVerifiedSidecar stmts persistedCS`; recomputes `canonicalDefEvidenceHash` from the *live* statements (`liveHashes`, :419-424) and compares to the *persisted* `erVerifiedHash`; demotes to `asserted`/`Nothing` on `Nothing`, drift, or live-def-gone. This is recompute-vs-persisted, not digest-vs-digest, *within a module*.
3. `compiler/src/LLMLL/TrustReport.hs:467-490` — `collectAllContractStatus`. **Decisive.** For every cached module it re-runs `downgradeStaleVerifiedSidecar (meStatements menv) (meContractStatus menv)` against *that module's own* live statements before qualifying the keys and admitting the evidence to upgrade a caller's tier. The importer-side recompute is over the *callee's* own statements, not the importer's.
4. `compiler/src/LLMLL/Module.hs:169-194` — `loadFromFile`. **Decisive for freshness.** Each load re-`parseFile`s the callee from disk (:170) and re-`loadVerified fp`s the callee's sidecar (:191), then merges into `meContractStatus` (:193-194). `meStatements`/`meContractStatus` are read fresh from disk per load; there is no persisted importer-side cache of a foreign digest.
5. `compiler/src/LLMLL/TypeCheck.hs:349-405` — `checkCalleeAdmissibility` / `erFullyVerifiedAdmissible`; the cross-module admission leg keys off `erVerifiedHash` *present* in `tcContractStatus`, which is seeded only *after* `downgradeStaleVerifiedSidecar` ran (:357-364). Fail-closed on absent hash. This is the `erVerifiedHash` guard the prompt calls the ADMIT-VERIFIED guard.
6. `docs/design/admit-verified-callee-proposal.md` (Rev 2, Option 2 built green); `docs/design/def-return-annotation-proposal.md §8` (Risk list; the alias-map/cross-module recompute is *not* among the enumerated risks — Risk-1 here is the prompt's hypothetical, not a doc-pinned one); `docs/design/compositional-trust-closure-proposal.md §4` (the modular call rule). No in-flight doc proposes the digest-to-digest fallback as such; this review is therefore first-principles against the compiler ground truth, not a review of an existing draft.

I searched for a "digest-to-digest" or "Risk-1" design clause and found none; the absence is itself information — the fallback is a contingency in the prompt, and the compiler *already* implements the discipline it describes (finding G1 below).

## Gaps and hazards

### G1 — Digest-to-digest is sound against alias redefinition, AND the compiler already enforces it. (soundness — confirmed, not a gap)

The soundness chain in question (1) holds, with one correction of vocabulary. The chain is: callee module re-verifies → its alias is redefined → `augmentContractPost`/`augmentContractPre` (`FixpointEmit.hs:1374-1424`) now resolve to a *different* predicate → the alias-augmented hash changes → the callee's regenerated sidecar carries the new digest → the importer's next staleness check observes a changed digest → demotes. The load is from `liveHashes` over the callee's *own* statements (`TrustReport.hs:419-424`, invoked on the callee module at `:486`), so the new alias body is in scope at the recompute site — exactly the precondition the prompt grants.

The soundness rests precisely where the prompt locates it: **the importer must re-read the callee's regenerated sidecar rather than cache a pre-redefinition digest.** Confirmed. And the compiler's freshness guarantee makes the antecedent automatic: `loadFromFile` re-`loadVerified`s the callee per load (`Module.hs:191`), so the importer never holds a stale foreign digest across a build — the digest it compares is, by construction, the one currently on disk.

One vocabulary correction the language-team should absorb: LLMLL today is *not* literally digest-to-digest at the importer. `collectAllContractStatus` re-runs `downgradeStaleVerifiedSidecar` over the callee's live statements (`TrustReport.hs:486`), i.e. it *recomputes* the callee's hash from the callee's source and compares to the callee's *persisted* `erVerifiedHash`. That is *recompute-vs-persisted on the callee's own source* — strictly stronger than digest-to-digest, because it also catches a callee whose sidecar digest was hand-edited or whose body drifted without a re-verify. The prompt's "never re-resolve foreign aliases at the boundary" property is satisfied for a different reason than the prompt assumes: the recompute *does* run, but it runs over the *callee's* statements with the *callee's* alias map in scope (it is the callee's module env, `menv`), not at the importer with a missing alias map. So Risk-1's antecedent — "a cross-module path recomputes the callee's hash while lacking the callee's alias map" — cannot arise in the current architecture: the only cross-module recompute site already carries the callee's alias map because it operates on the callee's module env. The fallback is sound *and* the failure it guards against is already structurally excluded. *Bite:* none on soundness; this de-risks the DEF-RET fix entirely. The fallback is a belt over an existing belt.

### G2 — The boundary staleness gap is real in principle and is closed by recompute-per-build, not by an explicit "importer-verdict-vs-callee-digest" binding. (soundness — closed, but the invariant is enforced operationally, not recorded)

Question (2): yes, digest-to-digest *would* reintroduce a surface-text-style gap *if* the importer's admitted verdict were ever cached and not re-checked against a regenerated callee digest — concretely (a) a stale module cache that survives a callee re-verify, or (b) an importer verified against an older callee sidecar and never re-checked. The precise invariant is exactly as the prompt states it:

> **XMOD-STALE invariant.** An importer's verified verdict is valid only relative to the set of callee-sidecar digests it was checked against; a change to any callee digest must demote the importer's verdict.

This is the cross-module analog of the *same-module* invariant `downgradeStaleVerifiedSidecar` enforces ("a verified verdict is valid only relative to the `(body,pre,post)`+tag it was hashed over"). LLMLL enforces the cross-module invariant **operationally** rather than by storing the binding: the importer does not persist "I was checked against callee digest D." Instead, every `buildTrustReport` rebuilds `collectAllContractStatus` from the *live* cache (`TrustReport.hs:481-489`), which re-validates each callee's evidence against the callee's live source on that build, and the importer's tier is recomputed downstream from that freshly-validated evidence. There is no persisted importer verdict that can outlive a callee change, because there is no persisted *cross-module* verdict at all — the importer's tier is recomputed each build (`Main.hs:1126/1226/1347` all call `buildTrustReport _cache stmts ...` from the freshly-loaded `_cache`). So case (b) is excluded by construction: the importer is never "verified against an older callee sidecar" in a way that persists.

Case (a) — a stale `ModuleCache` — is the one residual hazard, and it is a *build-driver* obligation, not a trust-logic one. The trust closure is sound *given a faithful cache*; `loadFromFile` rebuilds the cache from disk per invocation (`Module.hs:170,191`), so a single CLI invocation is always faithful. A *long-lived* cache (LSP server, watch mode, the `Serve.hs` path) that fails to invalidate a callee env on a callee-file or callee-sidecar mtime change would silently retain a pre-redefinition digest and violate XMOD-STALE. That is the precise place the language-team must pin the invariant: not in `collectAllContractStatus` (which is already correct given a fresh cache) but as a *cache-coherence obligation* on any persistent `ModuleCache` holder — "a callee's `ModuleEnv` must be evicted/reloaded whenever its source or sidecar changes." I did not find that obligation written down; `Module.hs` has no mtime/invalidation hook, and the CLI sidesteps it by always rebuilding. *Bite:* does not block the DEF-RET fix or batch (CLI) use; matters at scale for any incremental/server consumer, and should be recorded as an explicit XMOD-STALE invariant so the LSP/watch path is held to it rather than discovering the gap empirically.

So: does LLMLL's existing closure (the ADMIT-VERIFIED `erVerifiedHash` guard, the XMOD-TIER recompute, what the prompt calls XMOD-TIER-STALE) already enforce XMOD-STALE? **Yes, for the recompute-per-build (CLI) model — and it enforces a strictly stronger property than digest-to-digest.** It enforces it *operationally* (recompute each build) rather than *referentially* (store the digest the verdict depended on). The gap is only at a layer the trust code does not own: cache coherence in a persistent host.

### G3 — Persisting the resolved predicate into the callee sidecar is unnecessary for soundness and adds a drift surface; persist (or rather, keep) the *digest* only. (spec-drift / ergonomic — minor)

The fallback proposes persisting "the resolved refinement predicate" into the callee's sidecar. For the staleness decision this is redundant: the *digest* (already `erVerifiedHash`, `Syntax.hs:395`) is the sufficient witness, and the callee's recompute regenerates it from live source. Persisting the resolved predicate *text* additionally creates a second copy of alias-resolved state that can desynchronize from the live alias body — precisely the contract-drift-with-stable-body hole `canonicalDefEvidenceHash`'s doc comment (`PBT.hs:588-590`) was written to close, reintroduced one level up. If the resolved predicate is persisted *only* for external/human display (the machine consumer, the `caller_obligations` axis), that is fine — but it must not be an *input* to any staleness comparison; the digest is the sole staleness witness. *Bite:* avoid a self-inflicted drift surface; a one-line scope restriction in the proposal.

## Recommendation

Adopt the fallback's *conclusion* — never re-resolve foreign aliases at the boundary; compare digests, not predicates — and recognize that **LLMLL already implements a strictly stronger version of it**: `collectAllContractStatus` recomputes each callee's augmented hash over the callee's *own* live statements (alias map in scope) and compares to the callee's persisted `erVerifiedHash` (`TrustReport.hs:481-489`, `412-461`). Risk-1's antecedent (a boundary recompute lacking the callee's alias map) is structurally unreachable, so the contingency is a belt over an existing belt; ship the settled DEF-RET augmented-hash fix without it.

Two refinements, ranked:

1. **Record the XMOD-STALE invariant explicitly** (closes G2's residual): "an importer's verified verdict is valid only relative to the callee-sidecar digests it was checked against; any changed callee digest must demote it." LLMLL satisfies this *operationally* by recompute-per-build under a fresh cache. Pin it as a named invariant and attach the *real* obligation — cache coherence — to any persistent `ModuleCache` holder (`Serve.hs`/LSP/watch): a callee `ModuleEnv` must be evicted on callee source-or-sidecar change. This wins because it puts the obligation where the only surviving hazard lives (the cache layer) instead of over-engineering the trust logic, which is already correct.

2. **If the resolved predicate is persisted at all, scope it to display only** (G3). The digest is the sole staleness witness; the resolved-predicate text must never feed a comparison, or it reintroduces the stable-body/drifting-alias hole one level up.

Reject the fallback's "persist the resolved predicate *as a staleness input*" reading; accept its "digest-to-digest, no foreign re-resolution" reading, which the compiler already exceeds.

## On the literature (question 3)

This is the standard separate-compilation / recompilation-avoidance discipline, and the literature pins the invariant cleanly — LLMLL's `erVerifiedHash` is a fingerprint/ABI-hash in the GHC sense.

- **GHC recompilation checking** is the closest analog and the one to cite. Since the interface-hash redesign (the `mi_iface_hash` / per-declaration `mi_decl_hashes` / `mi_usages` machinery; Bolingbroke–Marlow, the GHC "recompilation avoidance" wiki/notes, c. 2010-2015) GHC stamps each interface with a hash and records, in each *consumer's* interface, the **set of dependency hashes it was compiled against** (the `usages`/`mi_usages` field). On rebuild, GHC recomputes the dependency's hash and compares to the recorded one; a changed *ABI hash* forces recompilation of the consumer, while a stable ABI hash permits skipping even if the source changed. That recorded dependency-hash set is exactly the *referential* form of the XMOD-STALE invariant in G2 — "a consumer's result is valid only relative to the dependency hashes it was built against." LLMLL today uses the *operational* form (recompute-every-build) rather than recording the dependency-hash set; GHC's model is what you converge to if you ever want to *skip* importer re-verification (the incremental/LSP case in G2). The augmented-hash-vs-raw-hash distinction is GHC's own **ABI hash vs. source hash**: hashing the alias-resolved contract is the analog of hashing the *exported ABI* (the thing consumers actually depend on) rather than the source text — the right granularity, for the same reason GHC hashes the ABI not the file.

- **Build systems / Make / Bazel** pin the *transitive* form: a target is stale if any transitive input's fingerprint changed (Bazel's action-cache keys over the hashes of all declared inputs; Make's coarser mtime version). Mokhov–Mitchell–Peyton Jones, *Build Systems à la Carte* (ICFP 2018; JFP 2020) is the clean formal pin: it defines *early cutoff* (skip a downstream rebuild when an upstream output is unchanged *by value/hash*, even if it was recomputed) and *minimality*, and shows hash-based "verifying/constructive traces" implement exactly the digest-to-digest discipline the fallback describes. Your "changed callee digest must demote the importer" is their early-cutoff key, run in the demotion direction; "unchanged callee digest need not demote" is early cutoff proper. That paper is the citation that pins the invariant most cleanly and abstractly.

- **Shao–Appel, "Smartest Recompilation" (POPL 1993)** is the precision frontier: it computes the *weakest* dependency under which a result stays valid, so a consumer is invalidated only on changes that actually affect it. LLMLL's augmented hash is a coarser-but-sound approximation (any change to the resolved contract demotes, even a semantically-equivalent reformulation — note `canonicalExpr` does *not* normalize alpha-equivalence, `PBT.hs:609-616`, the conservative direction). That conservatism is the correct trade for an assurance system: sound and cheap beats minimal and subtle. Cite Shao–Appel only to mark that you are *deliberately* coarser than the frontier, not to chase it.

The invariant the literature pins, in one line: **a consumer's cached result is valid exactly relative to the fingerprints of the dependency interfaces it was checked against; a changed fingerprint must invalidate it, an unchanged fingerprint may license skipping.** LLMLL enforces the "must invalidate" half soundly (operationally, via recompute-per-build); it has not yet *recorded* the dependency-fingerprint set, which is what the "may skip" half (incremental re-verification) would require — exactly G2's recommendation.

## Open questions for the language-team

1. Pin XMOD-STALE as a named invariant and state where the *cache-coherence* obligation lives for persistent `ModuleCache` holders (`Serve.hs`/LSP/watch): `collectAllContractStatus` is sound given a fresh cache (`TrustReport.hs:481-489`), but nothing in `Module.hs` invalidates a callee `ModuleEnv` on a callee source-or-sidecar change. Confirm whether any long-lived-cache consumer exists today; if so, that is where the only surviving Risk-1-shaped gap is, and it is a build-driver bug, not a trust-logic one.
