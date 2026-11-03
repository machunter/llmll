---
name: post-conj-split-proposal
title: "POST-CONJ-SPLIT-1: prove the admitted conjuncts of a post, and record a partly proved post"
status: "Rev 1, DRAFT 2026-11-02. Not reviewed. Written by the language-team for the DECIDE on roadmap row POST-CONJ-SPLIT-1."
date: 2026-11-02
author: language-team
rows: POST-CONJ-SPLIT-1 (G1, DECIDE); proposes two follow-up rows, not filed (PRE-CONJ-DROP-1, POST-CONJ-DIAG-1)
consumers: [user, professor, compiler-engineer, documentation-lead]
---

# POST-CONJ-SPLIT-1: prove the admitted conjuncts of a post, and record a partly proved post

**Status: Rev 1, DRAFT 2026-11-02.** No professor review yet. All measurements are on `llmll 0.35.1` (the main checkout build, liquid-fixpoint 0.9.6.3.7), run one file at a time under a memory and time watchdog.

## Summary

1. **Recommendation: split.** `verify` flattens the top-level `and` of a function's effective `post` into conjuncts. It proves the conjuncts that translate, and it records the others `asserted`, one record for each conjunct.
2. **One body VC per path, as today.** The right side of each path constraint is the conjunction of the admitted conjuncts. When every conjunct translates, the `.fq` is byte-identical to today.
3. **No conjunct is assumed while another is proved.** The fragment is total in the logic, so no conjunct needs an earlier one to be well defined. A refuted admitted conjunct refutes the whole post.
4. **Callers assume the admitted conjuncts.** Today a caller assumes nothing from a post that does not translate whole. That causes false refutations of correct callers (measured, §2.2).
5. **The clause stays `asserted`.** A partly proved post keeps `display_level: asserted` and `body_faithful: false` at the clause level. Every existing reader of the clause therefore behaves as it does today. The per-conjunct evidence is a new, additive field.
6. **`--strict-verified-core` still fails** on a partly proved function. `--contracts=unproven` still keeps the whole post as a run-time assertion.
7. **The netpbm transforms are not fixed by this row.** Four separate refusals stack on them (§2.1). The row text says the split "would have verified the header half of 8 transforms". That claim is false on 0.35.1.

---

## 1. Restatement

A `post` is translated into the `Σ_auto` fragment as one unit. If any sub-term does not translate, the emitter withdraws the whole post. The function then falls back with cause `contract-post-outside-fragment`, and callers assume nothing from the post. The question is whether `verify` should treat a top-level `and` as a list of separate proof goals. It must also say how the trust report, the `.verified.json` sidecar, `--strict-verified-core`, call sites, weakness checks and CDP record and read a post that is partly proved.

## 2. Reproduction on 0.35.1

### 2.1 Netpbm F6: reproduced, and the split alone does not fix it

I copied `examples/netpbm/*.llmll` to the scratchpad. I verified the modules in the order of `examples/netpbm/build.sh`. `netpbm.llmll` then reports, for `invert`, `threshold`, `hflip` and `vflip`:

```
W-BODY-FALLBACK: 'invert' fell back from body-faithful verification
(contract-post-outside-fragment), so its post is assumed and not proved.
Refused by: app:image-ok?, app:img-header.
```

So F6 reproduces exactly. Then I removed the refusals one at a time, to find what a split would get:

| Variant of the transform contract | Result on 0.35.1 |
|---|---|
| As written: `pre (image-ok? img)`, `post (and (image-ok? result) (= (img-header result) (img-header img)))` | fallback, `contract-post-outside-fragment; app:image-ok?, app:img-header` |
| `post (= (img-header result) (img-header img))` (the "header half" alone) | fallback, `contract-post-outside-fragment; app:img-header` |
| `post (= (first result) (first img))`, pre kept | fallback, `contract-pre-outside-fragment; app:image-ok?` |
| `post (= (first result) (first img))`, no pre | fallback, `body-outside-fragment; app:list-map, lambda` (`vflip`: `app:list-reverse`; `blur`: seven constructs) |

Four refusals stack on each transform:

1. The out-of-fragment conjunct `image-ok?`. This row addresses it.
2. A call to a user function (`img-header`) in a clause. `exprToPred` has no case for a user call, so every user call in a clause is refused (`compiler/src/LLMLL/FixpointEmit.hs:3736-3934`). That is `POST-CALL-XMOD-1`, and it applies within one module too.
3. The pre `(image-ok? img)`. A def-site pre that does not translate withdraws the body VC (`FixpointEmit.hs:1587-1597`). This proposal files it as a follow-up (§4.6).
4. The body. `list-map`, `lambda` and `list-reverse` are outside `Σ_auto`. No open row admits a list-transforming body as an opaque term.

**Finding 1 (row text is incorrect).** The roadmap row says the split "would have verified the header half of 8 transforms". It would not. Refusals 2, 3 and 4 remain. Refusal 4 alone blocks every conjunct, because no conjunct can be proved without a body VC.

**Finding 2 (F6 sub-claim is incorrect).** F6 says the label "names a verified callee (`img-header`) as refused". The label is correct. A user call in a clause is refused whatever the callee's evidence, because `exprToPred` has no case for it (finding 2 above, `POST-CALL-XMOD-1`).

**Finding 3 (citation drift).** The row cites `examples/netpbm-swarm/FRICTION.md` for "netpbm F6". Swarm F6 is about verify cost. The conjunct problem is only in `examples/netpbm/FRICTION.md` F6. Swarm F10 (no failing-conjunct diagnostic) is related; see §4.7.

**Finding 4 (F6 second complaint explained).** F6 also says the body's own causes are not reported. The emitter decides the post before it tries the body (`FixpointEmit.hs:1586-1597`). A refused post therefore hides every body cause. With the split, a partly admitted post reaches the body, so the body causes become visible.

### 2.2 A minimal witness where the split helps, and a false refutation today

Scratch file `split.llmll`:

```lisp
(def-shell all-pos? [xs: list[int]] -> bool
  (list-fold xs true (fn [acc: bool x: int] (and acc (> x 0)))))

(def-shell pos-or-one [n: int] -> int
  (post (and (>= result 1) (all-pos? [result])))
  (if (> n 0) n 1))

(def-shell use-it [n: int] -> int
  (post (>= result 2))
  (+ (pos-or-one n) 1))
```

| File | `pos-or-one` | `use-it` | exit |
|---|---|---|---|
| `split.llmll` (as above) | asserted, `contract-post-outside-fragment; app:list-empty` | **refuted** | 1 |
| `only.llmll` (post is `(>= result 1)` only) | verified | verified | 0 |
| `bad.llmll` (first conjunct `(>= result 5)`, a wrong body) | asserted, fallback | **refuted** | 1 |
| `badonly.llmll` (post is `(>= result 5)` only) | **refuted** | depends-on-refuted | 1 |

Two defects show in `split.llmll`:

- **A correct caller is refuted.** `use-it` is correct. The call site assumes nothing from `pos-or-one`, because its post does not translate whole (`FixpointEmit.hs:4648-4666`, `contractPost contract >>= exprToPred`). The caller VC then fails. This is a stronger reason for the split than netpbm F6.
- **A wrong callee is not refuted; its caller is.** In `bad.llmll` the wrong function is `pos-or-one`. Today `verify` blames `use-it` instead.

Under this proposal, `split.llmll` gives: `pos-or-one` post conjunct 0 `verified`, conjunct 1 `asserted`; `use-it` SAFE. `bad.llmll` gives: `pos-or-one` refuted on conjunct 0; `use-it` depends-on-refuted. These two files are the positive witnesses for the acceptance tests.

## 3. Context located

- `compiler/src/LLMLL/FixpointEmit.hs:1514-1597`: the body-VC entry. `postCause` holds the whole-contract guards; `mPostPred` is `contractPost contract >>= exprToPred`, one unit. A `Nothing` routes to `contractFallback FallbackContractPost`.
- `FixpointEmit.hs:1599`, `:1845`, `:2017`: `postPred` is the right side of each path constraint (`FQReft "result" retSort postPred`).
- `FixpointEmit.hs:3791`: `exprToPred (EApp "and" args) = FQAnd <$> mapM exprToPred args`. This line withdraws the whole conjunction when one operand fails.
- `FixpointEmit.hs:3736-3934`: `exprToPred`. No case for a user call; `list-nth`, `list-head`, `let`, `lambda` fall to `exprToPred _ = Nothing`.
- `FixpointEmit.hs:3936-3960`: `refusedConstructs`, the minimal refusing sub-terms (FALLBACK-CENSUS-1). It already walks conjuncts.
- `FixpointEmit.hs:200-264`: `FallbackCause`, a closed set, and `renderFallbackCause`.
- `FixpointEmit.hs:4633-4720`: call site. An untranslatable callee pre withdraws the call; an untranslatable callee post is not assumed (`mPostPred`, three sort guards). `cvPostAssumption` is the assumed post.
- `FixpointEmit.hs:5693-5745`: CALL-CONGRUENCE-1 `addCongruence`. It reads call keys, not posts.
- `FixpointEmit.hs:6469-6476`: `augmentContractPost` folds a return refinement as `(and post rpost)`.
- `compiler/src/LLMLL/FixpointIR.hs:340-381`: FQ-FLAT-NEST-1 prints nested `FQAnd` flat. Byte-identity of §4.2 depends on it.
- `compiler/src/LLMLL/Syntax.hs:431-453`: `Contract`; SRC-CONJ-1 `contractPostClauses`, the scalar post is their left `and`-fold.
- `compiler/src/LLMLL/Syntax.hs:561-593`: `EvidenceRecord`, with SRC-CONJ-1 `erSources` per authored clause.
- `compiler/src/LLMLL/VerifiedCache.hs:150-260`: sidecar codec; unknown keys are ignored on read. `:398-399`: `checkerSoundnessVersion = "6"`.
- `compiler/src/LLMLL/TrustReport.hs:466-467`: `trustReportEmitVersion = "1.10.0"`. `:1563-1604`: `enrichEntry`; a caller meets each transitive callee's `csPost` level (TRUST-PRE).
- `compiler/src/LLMLL/Contracts.hs:229-254`: `filterContracts`; `--contracts=unproven` strips a post only when the clause is verified and body-faithful.
- `compiler/app/Main.hs:1658-1676`: `refutedSet` is UNSAFE origins intersected with `erBodyFaithfulFns`.
- `compiler/app/Main.hs:2390`, `:2420`: weakness and CDP candidates in `erBodyFallback` are reported unvalidated, not solved.
- `compiler/src/LLMLL/ProofArtifact.hs:159-163`: `mkFnRecord` rejects a positive tier with a `fallback_reason`.
- `LLMLL.md §4.4.1`: display levels and the sidecar read rules (verified without `body_faithful` is downgraded; the checker epoch rule).
- `LLMLL.md §4.7`, `§13.3`: `and` is short-circuit at run time.
- `LLMLL.md §5.3.4`: the body VC `P ∧ (result = ⟦B⟧) ⟹ Q`; short-circuit operators in bodies (AND-GUARD-PRE-1); contract stripping; strict verified core.
- `CHANGELOG.md` v0.33.4 (AND-GUARD-PRE-1), v0.35.0 (FQ-FLAT-NEST-1, CALL-CONGRUENCE-1), v0.14.65 (SRC-CONJ-1).
- Related open rows: `POST-CALL-XMOD-1`, `SIG-SCALAR-ARM-1`, `PAIR-NEST-PROJ-1`, `WEAKNESS-MUTANT-1` (`docs/compiler-team-roadmap.md:102-106`).
- No in-flight draft on this topic exists in `docs/design/`.

## 4. Design proposal

### 4.1 Conjunct list

**Definition.** The conjunct list of a function is the flattening of the top-level `and` nodes of its effective post. The effective post is the post after the SRC-CONJ-1 clause fold and the DEF-RET return-refinement fold (`augmentContractPost`). Flattening goes through `and` only.

```
conj(and(a, b)) = conj(a) ++ conj(b)
conj(e)         = [e]            -- e is not an `and` node
```

The list is in author order. The return-refinement conjunct, when present, is last. Each conjunct has an index `k` (0-based) and an origin: `author` or `return-refinement`.

Flattening does not go through `let`, `if`, `match`, `=>`, `<=>`, `or` or `not`. A conjunct with one of these at its head is one conjunct. See §5 E6 to E8.

**Surface.** No change. `(post (and a b))`, `(post (and a (and b c)))`, and repeated `(post a) (post b)` clauses all give a flat list. The JSON-AST is unchanged, so `schema_version` does not change.

### 4.2 Definition-site obligation

Let `A` be the admitted conjuncts: those `c_k` where `exprToPred c_k` is `Just q_k`. Let `R` be the refused conjuncts. The cases:

| `A` | `R` | Behaviour |
|---|---|---|
| all | empty | As today. One body VC per path, right side `FQAnd [q_0 … q_n]`. The `.fq` is byte-identical (FQ-FLAT-NEST-1 prints the same flat chain). |
| empty | all | As today. Fallback, cause `contract-post-outside-fragment`. |
| non-empty | non-empty | **New.** One body VC per path, right side `FQAnd [q_k | k ∈ A]`. The function is *partly proved*. |

The rule for the new case:

```
  P  ∧  path  ∧  result = ⟦B⟧   ⟹   ⋀_{k ∈ A} q_k          (one constraint per path)
```

The pre `P` is the full translated pre. If the pre does not translate, the function falls back as today (`contract-pre-outside-fragment`); §4.6 files the pre side separately.

**Guards stay whole.** The whole-contract guards in `postCause` (`FixpointEmit.hs:1544-1568`: signature guard, whole-structure equality, map-clause guard) still refuse the whole contract. Only the `exprToPred` refusal is split. This keeps the sort-crash firewall of §5.3.3 unchanged. A per-conjunct guard is a possible later widening (§5 E9).

**Verdicts.**

- SAFE: every `k ∈ A` gets `verified (liquid-fixpoint)`, body-faithful. Every `k ∈ R` gets `asserted`, with its refusing constructs from `refusedConstructs c_k`.
- UNSAFE on a constraint of this function: the function is **refuted**. The hypotheses are complete (full `P`, full body), so an UNSAFE answer disproves the conjunction of `A`. A post whose conjunct is false in a model is false in that model, whatever `R` evaluates to. So the refutation is a refutation of the whole authored post, in the modular sense of §4.4.1.
- UNSAFE that ABSTRACTION-VERDICT-1 reclassifies: the function falls back with cause `abstraction-unsafe`, as today. All conjuncts are `asserted`.

### 4.3 Well-definedness and the order of conjuncts

**Rule: each admitted conjunct is proved without assuming any other conjunct.** One constraint with a conjunctive right side is valid exactly when each conjunct is valid under the same hypotheses. So §4.2 already gives independent obligations.

The question was whether proving `c_1` may assume `c_0`, as Dafny does for well-formedness under `&&`. The answer is no, for three reasons:

1. **The fragment has no partial terms.** Every term `exprToPred` admits is total in the logic: `listLen`, `strLen`, `pair2_i`, `Map_select`, constructor selectors, and `*`, `/`, `mod` only with a constant operand and a divisor > 0 (`constArithTerm`). The partial operations that need a guard (`list-nth`, `list-head`, a user call with a `pre`) are refused. So an admitted conjunct never needs an earlier conjunct to be meaningful in the logic.
2. **Assuming an admitted earlier conjunct adds nothing.** If `c_0 ∈ A` is proved, then `P ∧ B ⟹ c_0`, so `P ∧ B ∧ c_0` and `P ∧ B` have the same models. If `c_0` is refuted, the function is refuted anyway.
3. **Assuming an asserted earlier conjunct is not available, and would be wrong.** A refused conjunct has no FQ form, so it cannot be assumed. If a later revision admitted a conjunct only partly (for example by abstraction), assuming it would make a `verified` record depend on an `asserted` fact. The record would then claim more than its evidence.

**Run time is unchanged.** The built program still evaluates the whole post with short-circuit `and` (§4.7, §13.3). A refused conjunct that needs an earlier guard, such as `(and (> (list-length xs) 0) (= (list-head xs) (ok result)))`, keeps that guard at run time, because the post is not stripped (§4.5).

**The example from the brief.** `(and (> (list-length xs) 0) (= (list-nth xs 0) (ok result)))`: conjunct 0 is admitted (`listLen`), conjunct 1 is refused (`app:list-nth`). Conjunct 0 is proved alone. `list-nth` answers `Error` out of range (`LLMLL.md §13.5`), so conjunct 1 is also defined at run time without the guard.

### 4.4 Call sites: what a caller may assume

**Rule: a caller assumes the admitted conjuncts of the callee post, and only those.** At a call, `cvPostAssumption` becomes `FQAnd [q_k[args, r/result] | k ∈ A_callee]`. The three existing call-site sort guards (`FixpointEmit.hs:4648-4666`) apply to each conjunct, and a guarded conjunct is dropped. Dropping a hypothesis is a sound weakening.

This is the same assume-guarantee policy as today: a caller assumes a translatable callee post whatever its tier, and the trust closure records the tier. Today the unit of translation is the whole post; it becomes the conjunct.

**CALL-CONGRUENCE-1.** No change. The congruence fact reads the call key (callee, argument sorts), not the post (`FixpointEmit.hs:5701-5745`).

**Cross-module.** The imported `ContractEnv` is rebuilt from `meStatements` (`seedImportedContracts`, `FixpointEmit.hs:581`), so the importer computes the same conjunct list and the same `A`. No new data crosses the module boundary for the VC.

**Caller tier.** Two options:

- **Option A (conservative).** The caller meets the callee's clause level, which is `asserted` for a partly proved post. `use-it` in §2.2 becomes SAFE but stays `asserted`.
- **Option B (recommended).** The caller meets the callee's *assumed level*: the meet of the per-conjunct levels of `A`. That is the evidence the caller's VC actually used. `use-it` becomes `verified`.

Option B is sound in the sense of `LLMLL.md` nc-005/nc-006: a caller's proof rests only on the callee facts it assumed. The refused conjuncts never enter the caller's VC. They remain run-time assertions in the callee. Option B needs the per-conjunct levels of an imported callee from its sidecar. A missing or unreadable record reads `asserted` (fail closed). In `TrustReport.enrichEntry` (`:1595-1599`), the fold over `csPost` becomes a fold over the assumed level. `ObligationAssembly`'s `callee_tier` reads the same value through `teEffectiveLevel`.

The downstream trust warning (§4.4.3) still fires for a partly proved imported callee, because its clause is `asserted`. Its text names the state: `post partly proved (1 of 2 conjuncts verified)`.

### 4.5 Records and consumers

**Clause level stays `asserted`.** A partly proved post keeps `display_level: asserted` and `body_faithful: false`. Each consumer that reads the clause therefore sees what it sees today:

| Consumer | Behaviour for a partly proved post |
|---|---|
| `--contracts=unproven` (`Contracts.hs:229-254`) | Keeps the whole post as a run-time assertion. Stripping the proved conjuncts only is a possible later change; it is not in Rev 1. |
| Strict-core callee admission (`checkCalleeAdmissibility`) | Not admissible (no body-faithful clause record). |
| `--strict-verified-core` | Fails. The function is in `body_fallback` with the new cause. A strict core means every post in it is proved in full. |
| `--weakness-check`, `--cdp` (`Main.hs:2390`, `:2420`) | Unchanged: the synthetic candidate is in `body_fallback`, so it is reported unvalidated. Running the candidates against `A` is a follow-up (§9). |
| Leanstral route (`Main.hs:2133`) | Unchanged: the function is in `body_fallback`. |
| Proof artifact (`mkFnRecord`) | Records the clause level (`asserted`) and the fallback reason. Per-conjunct tiers are not written in Rev 1, so `PositiveWithFallback` cannot fire. |

**New fallback cause.** `FallbackContractPostPartial`, rendered `contract-post-partly-outside-fragment`. The closed set grows from eleven to twelve. A function with this cause is listed in `body_fallback`, and in a new emitter list of partly proved functions. It is not in `erBodyFaithfulFns`. `refutedSet` (`Main.hs:1672-1676`) must take the union of the body-faithful list and the partly proved list. Without that change, a partly proved function could never be refuted.

**Footer.** `SAFE (liquid-fixpoint), partial: 3 of 33 contracted functions proved; 1 partly proved; 29 assumed, not proved: …`.

### 4.6 Schema delta

**Sidecar (`.verified.json`).** The post record of a partly proved function gains `conjuncts`. Each entry carries its own evidence, so the existing read rules apply to each entry:

```json
"pos-or-one": {
  "post": {
    "display_level": {"level": "asserted"},
    "conjuncts": [
      {"index": 0, "origin": "author", "text": "(>= result 1)",
       "display_level": {"level": "verified", "prover": "liquid-fixpoint"},
       "body_faithful": true, "verified_hash": "sha256:…"},
      {"index": 1, "origin": "author", "text": "(all-pos? [result])",
       "display_level": {"level": "asserted"},
       "refused_by": ["app:list-empty"]}
    ]
  }
}
```

- Written only for a partly proved post. A fully proved post and a fully refused post keep today's shape.
- `verified_hash` is the function's existing hash (it covers the effective post, so the index is stable while the hash matches).
- Read rule: the `LLMLL.md §4.4.1` downgrade (verified without `body_faithful`, absent hash, hash drift, no live definition) applies to each entry.
- An old binary ignores `conjuncts` (unknown keys are ignored, `VerifiedCache.hs:150-260`) and reads the clause as `asserted`. A new binary that reads an old sidecar finds no `conjuncts` and reads the whole clause.
- **`checker_soundness_version` stays `"6"`.** Every post that translated before emits the same term. The change only makes clauses translate that did not, and only adds caller hypotheses. Adding a hypothesis cannot turn a recorded SAFE into UNSAFE. This is the "keeps the stamp" case of §4.4.1. The release shows it with a byte-identical `.fq` sweep over every file with no partly admitted post.

**Trust report.** `trust_report_version` goes from `1.10.0` to `1.11.0`. Each entry gains `post_conjuncts` (the same objects as the sidecar, without the hash) and `post_assumed_level` (Option B). Text form:

```
  pos-or-one:
    pre:  —  |  post: asserted, 1 of 2 conjuncts verified   [body_fallback: contract-post-partly-outside-fragment; app:list-empty]
      post[0] verified (liquid-fixpoint)   (>= result 1)
      post[1] asserted                     (all-pos? [result])   refused by app:list-empty
```

The version increases although the change is additive, because `post_assumed_level` changes what a caller's level means. The precedent is `1.9.0` (MODE-CLI-1), which increased for an additive key.

**`verify --json`.** `body_fallback_causes` can carry the new value. The verdict object is open (`docs/llmll-verify.schema.json`), so `verify_json_version` stays `1.0.0`. `docs/getting-started.md:567` says "one of eleven fixed" values; that becomes twelve.

**Proof artifact.** `docs/proof-artifact.schema.json:76` enumerates `fallback_reason`. Adding a value breaks a validator of the old schema, so `proof_artifact_version` goes from `0.1.0` to `0.2.0`.

**Compiler version.** A minor release (`0.36.0`). A function that was silently `asserted` can now be refuted (§5 E4), so `verify` exit codes change on some programs.

### 4.7 Follow-up rows (proposed, not filed)

- **PRE-CONJ-DROP-1.** At the definition site, drop the pre conjuncts that do not translate, and prove the post under the admitted pre. A weaker hypothesis is sound. But an UNSAFE answer under a dropped hypothesis is not a disproof of the authored contract. It must fall back with cause `contract-pre-partly-outside-fragment`, never `refuted` (the ABSTRACTION-VERDICT-1 precedent). The call-site pre stays whole: it is a PROVE obligation, and the call is withdrawn when it does not translate (`FixpointEmit.hs:4641-4642`).
- **POST-CONJ-DIAG-1.** Emit one constraint per admitted conjunct, so an UNSAFE answer names the failing conjunct (swarm F10). It multiplies constraints per path by `|A|`, so it needs a cost measurement under VERIFY-BUDGET-1 limits first.

## 5. Edge cases and degenerate inputs

**E1. Positive witness: a partly proved post.**
Input: `pos-or-one` in §2.2. Behaviour: conjunct 0 `verified`, conjunct 1 `asserted`, cause `contract-post-partly-outside-fragment`. `use-it` is SAFE (today it is refuted). Channel: contract (conjunct 0), trust (conjunct 1). Cite: §4.2, §4.4.

**E2. Every conjunct admitted.**
Input: `(post (and (>= result 0) (<= result 10)))`. Behaviour: as today; byte-identical `.fq`. Channel: contract. Cite: §4.2 row 1; `FixpointIR.hs:340-381`.

**E3. Every conjunct refused, or no `and`.**
Input: `(post (image-ok? result))`, or `(post (and (image-ok? result) (all-pos? xs)))`. Behaviour: as today, `contract-post-outside-fragment`. Channel: trust. Cite: §4.2 row 2.

**E4. An admitted conjunct is false (a new refutation).**
Input: `bad.llmll` in §2.2, or `(post (and false (image-ok? result)))`. Behaviour: the function is refuted; callers are depends-on-refuted. Today the function is silently `asserted` and exit status blames a caller. Channel: contract. Cite: §4.2 verdicts; `Main.hs:1672-1676` (must include the partly proved list).

**E5. A guard conjunct before a refused conjunct.**
Input: `(and (> (list-length xs) 0) (= (list-head xs) (ok result)))`. Behaviour: conjunct 0 proved alone; conjunct 1 `asserted`; the run-time post keeps the short-circuit order. Channel: contract and trust. Cite: §4.3.

**E6. A refused guard before an admitted conjunct that needs it.**
Input: `(and (image-ok? result) (>= (first (first result)) 1))` where the second conjunct holds only when the first does. Behaviour: the solver may answer UNSAFE on conjunct 1. That is a genuine refutation of the authored post: in the model, either `image-ok?` is false or conjunct 1 is false, so the post is false. The author must strengthen the body, or move the fact into the refused conjunct. Channel: contract. Cite: §4.3 reason 3. Spec is silent on warning the author (intentional; the refutation names the function).

**E7. `and` under `let`, `if` or `match`.**
Input: `(let [(h (img-header result))] (and … …))`, `(if c (and a b) d)`, or `main.llmll:84` `(match result ((Success out) (and …)) ((Error e) true))`. Behaviour: one conjunct; refused whole if any part is refused, as today. Strict immutability makes `let`-distribution (`let x = e in (a ∧ b)` to `(let x = e in a) ∧ (let x = e in b)`) a valid rewrite, and `if` and `match` arms can be split as implications. Spec is silent (intentional, Rev 1 scope).

**E8. `=>` with a conjunctive consequent, and `not`/`or`.**
Input: `(=> p (and a b))`, `(not (or a b))`. Behaviour: one conjunct each. `(=> p (and a b))` to `(and (=> p a) (=> p b))` is sound and is a natural Rev 2 widening. Spec is silent (intentional).

**E9. A guard refusal on one conjunct.**
Input: a post with a whole-structure `=` on a `bytes` operand in one conjunct and a scalar fact in another. Behaviour: the whole contract is refused, cause `contract-post-outside-fragment`, label `guard:whole-structure-eq`, as today. Spec is silent (intentional: the guards protect against solver sort crashes, and a per-conjunct guard needs its own review).

**E10. A refused return-refinement conjunct.**
Input: a return alias whose predicate is outside `Σ_auto`, and an author post that translates. Behaviour: author conjuncts proved; the refinement conjunct is `asserted` with origin `return-refinement`. Today the whole post falls back (§3.4.5 firewall, `FixpointEmit.hs:1515-1520`). Channel: trust. **Gap (flag):** an alias predicate has no run-time residue (`LLMLL.md` §3, "Channel distinction"), so this `asserted` conjunct has no run-time assertion behind it. The same gap exists today for a whole-post fallback with a folded refinement. The report should say `asserted (no run-time check)` for this origin.

**E11. Call-site sort guard drops one conjunct.**
Input: a callee post with a datatype term in one conjunct, called where the result binder is not datatype-sorted. Behaviour: that conjunct is not assumed; the others are. Today the whole post is not assumed. Channel: contract. Cite: `FixpointEmit.hs:4655-4664`.

**E12. A stale per-conjunct record.**
Input: the body changes after a partly proved SAFE run. Behaviour: the hash drifts, every `verified` conjunct entry reads `asserted`. Channel: trust. Cite: `LLMLL.md §4.4.1` read rules, applied per entry.

## 6. Verification mapping

| Obligation | Channel | Fragment | Cite |
|---|---|---|---|
| `P ∧ path ∧ result = ⟦B⟧ ⟹ ⋀_{k∈A} q_k` | contract | QF-LIA within `Σ_auto`, auto-discharged by liquid-fixpoint. Same class as today's body VC: each `q_k` passed `exprToPred`. | `LLMLL.md §5.3.3`, `§5.3.4`; `FixpointEmit.hs:1845`, `:2017` |
| Caller assumes `⋀_{k∈A} q_k[args, r]` | contract (ASSUME polarity) | QF-LIA within `Σ_auto` | `LLMLL.md §5.3.4` compositional chain; `FixpointEmit.hs:4714` |
| Each `c_k`, `k ∈ R` | trust (run-time assertion under `--contracts=full`) | Outside `Σ_auto`; not routed to Lean in Rev 1. A later row could route each refused conjunct as its own `?proof-required` obligation. | `LLMLL.md §5.3.5` |

No obligation leaves its current fragment. No nonlinear or quantified obligation is introduced.

## 7. Affected surface

- `compiler/src/LLMLL/FixpointEmit.hs`: conjunct flattening; the partial case in the body-VC entry (`:1586-1600`); `FallbackContractPostPartial` (`:200-264`); per-conjunct `cvPostAssumption` (`:4648-4690`); a new `EmitResult` list of partly proved functions with per-conjunct verdict inputs.
- `compiler/app/Main.hs`: `refutedSet` (`:1672-1676`); the SAFE path that writes the sidecar; the footer; `--json` causes.
- `compiler/src/LLMLL/VerifiedCache.hs`: `conjuncts` codec; per-entry read rules.
- `compiler/src/LLMLL/Syntax.hs`: a per-conjunct evidence type beside `EvidenceRecord`.
- `compiler/src/LLMLL/TrustReport.hs`: `post_conjuncts`, `post_assumed_level`, `enrichEntry` (Option B), text rendering, `trustReportEmitVersion`.
- `compiler/src/LLMLL/ProofArtifact.hs` and `docs/proof-artifact.schema.json`: the new `fallback_reason` value; `proof_artifact_version`.
- `scripts/fallback_census.py`: count the new cause as its own bucket.
- `LLMLL.md §4.4.1`, `§4.4.4`, `§5.3.4` (body VC, contract stripping, strict core); `docs/getting-started.md:567`. Doc-lead's slot after the engineer ships.
- `docs/compiler-team-roadmap.md` row text for POST-CONJ-SPLIT-1 (Finding 1, Finding 3). Doc-lead's slot.
- No new builtin, construct, FFI tier or capability.

## 8. Risks and open questions

1. **New refutations in existing programs.** Classify: verification-ergonomics. A function that was silently `asserted` can become refuted (E4, E6), and its file then exits 1. Cite: §4.2. Bite: complicates. The census must list every file whose verdict changes before the release.
2. **The partly proved list must enter `refutedSet`.** Classify: soundness. If the engineer adds the function to neither `erBodyFaithfulFns` nor the refuted path, a false admitted conjunct is silently `asserted`, and callers assume it at `verified` under Option B. Cite: `Main.hs:1672-1676`. Bite: blocks, if missed. An acceptance test with `bad.llmll` closes it.
3. **Option B changes what a caller's level means.** Classify: soundness (argued sound in §4.4) and spec-drift. Cite: `TrustReport.hs:1578-1599`. Bite: complicates. It is the one decision here with an outside-PL reading; see §10.
4. **Unknown scale.** Classify: scope. I did not measure how many corpus functions have a partly admitted post and an in-fragment body. The census in `scripts/fallback_census.py` cannot tell today, because a refused post hides the body decision (Finding 4). Bite: matters at scale only. The engineer's first step is that count.
5. **Netpbm stays unproved.** Classify: scope. The motivating example needs `POST-CALL-XMOD-1`, PRE-CONJ-DROP-1 and an opaque list-body term as well (§2.1). Bite: does not block this row; it corrects its stated benefit.
6. **E10 asserted conjunct with no run-time check.** Classify: spec-drift. Pre-existing for whole-post fallback. Bite: complicates the report wording only.

## 9. Decisions for the user

1. Split or not. Recommendation: split (§4.1 to §4.3).
2. Option A or Option B for the caller tier. Recommendation: B.
3. Keep weakness/CDP unvalidated on partly proved functions in Rev 1, or run the candidates against `A`. Recommendation: keep unvalidated; a trivial body that satisfies `A` says `A` is weak, which is useful but is a separate report surface.
4. File PRE-CONJ-DROP-1 and POST-CONJ-DIAG-1 as rows.
5. Correct the POST-CONJ-SPLIT-1 row text (Findings 1 and 3).

## 10. Open questions for the professor

1. **Caller tier under partial discharge (decides Option A or B).** A callee post `Q = Q_A ∧ Q_R` has `Q_A` proved against the body and `Q_R` only checked at run time. The caller's VC assumes `Q_A` only. Option B labels the caller `verified`. Is there an established treatment of this split in hybrid or gradual verification (for example Flanagan's hybrid type checking, or gradual verification in the style of Bader, Aldrich and Tanter) that labels such a caller statically verified? Or does that literature require the caller to inherit the run-time-checked residue, as Option A does?
