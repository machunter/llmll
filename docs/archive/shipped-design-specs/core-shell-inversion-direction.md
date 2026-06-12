# Core/Shell Inversion — Professor Direction Memo (v0.11)

> **Status:** Professor direction memo (Rev 2) — awaiting `language-team` LT-proposal(s).
> **Origin:** External critique (2026-05-23) processed through the professor channel; consolidates this turn's findings on architectural defaults and v0.11 routing.
> **Last updated:** 2026-05-23 (Rev 2 — adds §8 empirical validation gate).
> **Companion documents:** `docs/design/verification-debate.md` (Path A vs B), `docs/design/invariant-discovery-review.md` (contract discriminative power), `docs/design/proof-required-predicate-carrier.md` (predicate-carrying form), `docs/design/strategic-positioning.md` (verification-as-coordination thesis).

---

## Thesis

LLMLL should become a verified-core language embedded in an explicit coordination shell, not a coordination shell with an optional verified-core flag. The mechanisms that support this inversion are mostly shipped — what is wrong is the architectural default: today the source grammar treats the mixed regime as canonical, and the verified core is reached through a CLI flag (`--strict-verified-core` at `compiler/app/Main.hs:246` / `1119-1124`) and per-function trust-report inspection. A CLI flag says *"the mixed language is normal; strict core is a mode."* A grammar inversion says *"the core is normal; the shell is explicitly marked."* The architectural problem is which regime the source grammar treats as canonical, not whether the verifier has the right mechanisms.

## Background and self-correction

This memo consolidates an external critique (substance: LLMLL optimizes for *making reasoning obligations explicit* rather than for *making programs intrinsically easy to reason about*) with the professor-channel response, including a self-correction on backward-compatibility hedging that the initial response carried.

The original professor turn defended the existing architecture by inventorying shipped mechanisms (the evidence diamond at `LLMLL.md §4.4.1:325-344`, `--strict-verified-core`, the obligation report, `--weakness-check`, refinement aliases, the trust report). That defense was correct on the facts and wrong on the question. The external critique is not *do these mechanisms exist*; it is *when an agent reads or writes ordinary LLMLL, is the reasoning-minimal fragment the normal language, or is it an opt-in diagnostic regime?* Today the answer is the latter, and the latter is what the critique is about. Treating shipped architecture as evidence against changing architecture is question-begging when the question is whether the architecture is the right architecture.

Because LLMLL is pre-stable — no shipped consumer outside the example programs in `examples/`, schema-version churn within patch releases (`README.md:7` documents `schemaVersion 0.4.0 → 0.5.0` in v0.10.6), feature-freeze policy at `docs/compiler-team-roadmap.md:28-33` justified on *narrow the verification boundary* rather than on consumer-API stability — backward compatibility should not govern the v0.11 design conversation. If the current grammar encodes the wrong default, v0.11 should break it deliberately. The legacy worth preserving is narrow: benchmark comparability, regression-test fixtures, historical examples as migration material, the design record. The current source grammar should not be preserved merely because it exists.

## Routing summary

| Item | Routing | Reason |
|---|---|---|
| Core/shell grammar inversion | `language-team` LT-proposal for v0.11 | Existing flag does not change the canonical source shape; core membership must be local and syntactic. |
| Contract discriminative power as first-class evidence axis | Promote from research track to v0.11 LT-proposal | Fills a measurable blind spot in the v0.10 obligation report: weak `verified` is indistinguishable from strong `verified`. |
| Predicate-carrying `?proof-required` | Re-open the deferred design now | Empirical 5/12 agent ambiguity plus external demand together appear to satisfy the revisit conditions at `docs/design/proof-required-predicate-carrier.md:62-67`. |
| Effect rows on `Command` | Schedule as Bundle B, separate from the indexed-types research track | Not full dependent typing; HM + row polymorphism is a cheaper cost class than the `compiler-team-roadmap.md:48` exclusion bundles together. |
| Path-B foundations work | Do not re-open | Agent-cognition problem is solvable at the surface level via grammar inversion; no costed Path-B proposal exists. |
| Keyword choice (`def` vs `def-core` vs `def-logic`-retained) | `language-team` adjudicates | The polarity matters more than the name; both directions are defensible. |
| **Empirical validation gate** (v0.11 ship condition) | `experiment-lead` runs pre/post comparison on `experiments/minimal-agent/` baseline; `language-team` adjudicates pass/fail | The inversion is an architectural hypothesis, not a proven win; the project has the experimental instrument to test it before committing irreversibly. See §8. |
| Spec/schema version drift | P0, separate from inversion | `README.md:1` declares v0.10.6; `LLMLL.md:1` declares v0.10.1 — five releases of version-anchor drift. |
| Integer-semantics gap | P1, separate from inversion | Documented at `LLMLL.md §5.3.5:756-759`; requires a coherent runtime/verifier model choice. |
| EOp argument checking | **Unverified in this turn** — route to `compiler-engineer` | Claim was imported from a parallel channel; not derived from this conversation's reading path. |
| Multi-subject PBT over-credit | **Likely stale** — route to `experiment-lead` | `README.md:7` describes OBLIG-PBT-4 (v0.10.6) as explicitly closing this gap. |

---

## 1. The grammar inversion

### 1.1 What is wrong with the current default

The verification matrix at `LLMLL.md §5.3.5:736-756` partitions every syntactic construct into *body-faithful SMT*, *contract-only*, and *runtime assertion* verification regimes. The partition is correct. What is wrong is that **all three regimes are reachable from the same `def-logic` keyword** — a reader looking at one `def-logic` does not know, without inspecting the trust report or running `llmll verify`, which regime the function inhabits. The diamond lattice at `LLMLL.md §4.4.1:325-344` prevents silent coalescence in the *trust label*, but the *source surface* does not encode which lattice point a function reaches.

`--strict-verified-core` at `compiler/app/Main.hs:246` / `1119-1124` is the existing mitigation: hard-error if any function falls back from body-faithful verification. The flag works, but it is a *verifier mode*, not a *source-level constraint*. A function whose body uses non-core constructs can be authored, parsed, and type-checked under the current grammar; the failure surfaces only at `llmll verify --strict-verified-core`. The polarity is wrong: the permissive form is the syntactic default, and the strict reading is a flag.

### 1.2 The recommended move

Invert the polarity at the grammar level. A definition form whose grammar production *excludes* fallback constructs becomes the canonical form for "logic." A separate definition form admits the boundary constructs (`EDo`, general-ADT `EMatch`, `ELambda`, `EPair`, non-linear arithmetic, `Command` return type, `?proof-required`). Trust caps in the lattice are unchanged; what changes is that `verified` becomes *structurally* reachable only from the core form.

Two polarity questions for the `language-team` to adjudicate:

(a) **Keyword choice.**

- *Option 1* — keep `def-logic` for the strict core; introduce `def-boundary` / `def-effectful` / `def-shell` for the marked form. Preserves the project's central keyword for its strongest reading; smaller documentation/migration delta.
- *Option 2* — rename to `def` (or `def-core`) for the strict core; repurpose or retire `def-logic`. Gives the shortest spelling to the canonical form and removes the keyword's pre-inversion connotations.

Both are defensible. The polarity matters more than the name; the permissive form **must** be the marked one. Option 2 is a larger break and is more aligned with the no-backward-compatibility logic; Option 1 is more conservative. This memo does not pick — `language-team` decides as part of the LT-proposal.

(b) **Whitelist vs blacklist grammar.** Defining the core as *everything except known fallback constructs* admits future syntax accidentally into the core before the verifier supports it. Defining it as a whitelist — only constructs with body-faithful VC emission may appear inside a core definition — closes that admission path. The whitelist is the right discipline; `language-team` formalizes the production.

### 1.3 Illustrative grammar boundary

The table below is **illustrative**, derived from the verification matrix at `LLMLL.md §5.3.5:736-756`. The `language-team` formalizes the grammar production at `LLMLL.md §12`.

| Admitted in core | Excluded from core |
|---|---|
| `ELit` (int, bool); `EVar` (int-typed) | `EVar` non-int (Option-A scope; relaxable) |
| `EOp` over QF-LIA: `+`, `-`, `=`, `<`, `<=`, `>=`, `>`, `!=`; boolean connectives | `EOp` non-linear: `*`, `/`, `mod`, `rem` |
| `ELet` (single `PVar`, int RHS) | `ELet` (pattern / non-int RHS) |
| `EIf` under the 4096-path limit | `EIf` exceeding the path limit |
| `EApp` to a contracted callee with body-faithful verified evidence (see callout below) | `EApp` to uncontracted / recursive-self / opaque callees |
| `EMatch` on `Result` (two-arm) per `LLMLL.md §5.3.4` | `EMatch` general ADT; `EPair`; `ELambda`; `EDo`; `Command` construction |
| Refinement-aliased types per `LLMLL.md §3.4:229-241` | `?proof-required`; opaque crypto; untrusted FFI calls |

Two callouts the `language-team` should decide explicitly:

- **`EApp` to contracted callees.** Today, v0.9.0 assume-guarantee at `LLMLL.md §5.3.4:717-722` admits any contracted callee. The strictest reading of the core (*transitive verified-on-asserted does not leak in*) would narrow this to callees whose **bodies** are body-faithfully verified — a real restriction beyond current v0.9.0 behavior, requiring core-callable functions to form a transitive closure. The relaxed reading keeps the v0.9.0 mechanism unchanged. The strict reading is more aligned with the inversion's purpose; it is also more expensive in surface migration. This is **not** a synthesis of the prior professor turn; it is a sharper refinement raised in the external critique. `language-team` adjudicates.

- **`letrec` and recursion.** Today, `letrec` at `LLMLL.md §4.2:272-296` checks measure well-formedness (`measure ≥ 0`) but not strict call-site descent — descent is research-track per `LLMLL.md §5.3.3:684-691`. Under the inversion, `letrec` cannot live in the core grammar as currently verified. Two routes:
  - (i) Keep `letrec` outside the core as a boundary form. Faster; example programs with recursive helpers migrate to the boundary form.
  - (ii) Schedule strict-descent verification as a v0.11+ implementation item to admit verified-total `letrec` into the core. Preserves more expressiveness in the core at meaningful cost in `FixpointEmit.hs`.

### 1.4 Holes versus proof escapes

`LLMLL.md §6:763-789` and `compiler/src/LLMLL/HoleAnalysis.hs` treat all hole forms uniformly at the parser. Under the inversion, two hole forms must be distinguished:

- **`?hole`, `?name`** (typed implementation holes) — *acceptable* inside a core definition. A function containing them simply does not verify-complete. They are an authoring intermediate, not an evidence escape.
- **`?proof-required`** (`compiler/src/LLMLL/Syntax.hs:242`, `HProofRequired Text`) — *forbidden* inside a core definition. It is an asserted escape hatch; admitting it inside the core grammar would re-introduce the very semantic-uniformity defect the inversion is fixing.

This distinction is not encoded in `HoleAnalysis.hs` today because the grammar treats holes uniformly; the inversion forces it.

### 1.5 Migration scope

Concretely: twelve example directories under `examples/` plus the `examples/benchmarks/` suite. The `*_verifier` examples (`examples/hangman_json_verifier/`, `examples/tictactoe_json_verifier/`, `examples/conways_life_json_verifier/`) likely remain in the core form, since their verified contracts are already in QF-LIA. The interactive game examples (hangman, tictactoe, life) split between an effect-boundary form (game loops returning `Command`) and the shell form (general-ADT match, pair destructuring, etc.). A mechanical classifier — the same one needed for core-membership checking — can auto-migrate by syntactic inspection of the function body:

```
old:
    (def-logic f ... body)

new:
    if body is syntactically core:
        (def f ... body)              ;; or whichever Option-2 keyword
    else:
        (def-boundary f ... body)     ;; or whichever Option-1 keyword
```

This is exercise material, not legacy. There is no API-stability obligation; v0.10.6 just shipped a `schemaVersion` bump in a patch release (`README.md:7`).

---

## 2. Contract discriminative power as a first-class evidence axis

`docs/design/invariant-discovery-review.md §6:322-336` defines contract discriminative power as the inverse of the number of observationally-distinguishable implementations satisfying a specification, over a reference test suite. The concept is named and adopted into the project vocabulary. It is tracked at `docs/compiler-team-roadmap.md:224` as a research-track item.

The original professor turn defended this status as *already named*. That defense was too weak. Naming a concept in a research-track row is not the same as exposing it as a routine reporting dimension, and the v0.10 obligation report has a measurable blind spot the existing axes do not cover:

- Evidence level answers: *do we know this implementation satisfies the specification?*
- Contract discriminative power answers: *does the specification rule out enough wrong implementations?*
- A `verified` weak spec and a `verified` strong spec receive the same label.

The two axes are orthogonal. The discriminative-power axis directly fills a v0.10 gap the existing four-level lattice cannot.

### 2.1 Operationalization (CDP-0)

`--weakness-check` at `LLMLL.md §5.3.1:600-613` is the operational predecessor: it enumerates trivial bodies (identity, constant-zero, empty-string, `true`, empty-list) against the contract and flags whether any pass. The promotion is to extend this enumeration into a **divergence metric** — count the candidate set, count satisfying candidates, count distinct observed behaviors over a fixed generated test suite, surface distinguishing inputs.

The `language-team` formalizes the metric. **Illustrative** report shape only:

```
contract_discriminative_power:
  basis: observational-candidate-set
  candidate_count
  satisfying_candidate_count
  distinct_observed_behavior_count
  distinguishing_inputs
  warnings   ;; e.g. "identity implementation satisfies current postcondition"
```

The score is reported **with provenance**, not as a scalar replacement for the evidence lattice. A function may simultaneously be `verified` (evidence axis) and low-discriminative-power (spec-strength axis); the report must make both visible. The prior professor review at `docs/design/invariant-discovery-review.md §4.1:267-279` flagged the healthy-diversity-vs-underspecification tension; the implementation must honor it (intentionally weak contracts annotated as such should not raise the warning).

### 2.2 Routing

Promote contract discriminative power from the research-track row at `docs/compiler-team-roadmap.md:224` to a v0.11 implementation item, building on `compiler/src/LLMLL/WeaknessCheck.hs`. Sequence after the inversion in §1: the metric reports against the *core* form first, where the trivial-body enumeration is decidable; extending it to the shell is a later step.

---

## 3. Predicate-carrying `?proof-required` — re-open now

The deferred design at `docs/design/proof-required-predicate-carrier.md` captures the move from a leaf-tag `?proof-required` to one that carries the intended unverifiable predicate inline. The re-open conditions at `docs/design/proof-required-predicate-carrier.md:62-67` require:

> **(1)** Feature freeze is lifted, **and**
> **(2)** Either (a) ≥2 experiment batches post-DL-B show recurrent agent demand not explained by §13.8 confusion, **or** (b) a downstream consumer would meaningfully benefit from the predicate being machine-readable.

The empirical 5/12 agent-ambiguity signal already documented at `findings/postmortem-smoketest-001-002.md` finding #1 plus the external critique's downstream-consumer demand (Lean-discharge ingestion, obligation-report mining, runtime-assertion fallback) together satisfy condition (2)(b) in spirit. Condition (1) is policy: the freeze runs through v0.10, which has shipped. The freeze rationale is *no new escape hatches*; this proposal is the opposite — it makes an **existing** escape hatch carry more information **without widening the verification surface**. The verifier is unchanged; the predicate is not sent to liquid-fixpoint; the trust label stays at `asserted`. The change is informational, not soundness-relevant.

Two design clauses the `language-team` should fix:

(a) **Trust-level effect.** Today the marker routes to `asserted`. With a predicate present and a runtime-assertion fallback emitted, this becomes either `asserted-with-runtime-check` (a new fourth status alongside the diamond lattice) or unchanged. Either is defensible; `language-team` chooses. The deferred-design doc flags this at `docs/design/proof-required-predicate-carrier.md:75`.

(b) **Core-grammar interaction.** Per §1.4 above, `?proof-required` (predicate-carrying or not) must remain forbidden inside the core form. The point of the inversion is that the core is a no-escape-hatch fragment; admitting a predicate-carrying escape hatch undoes that. The predicate-carrying form is a boundary-form feature.

### Routing

Schedule an LT-proposal / professor-review pair on the predicate-carrying form for v0.11. The proposal lands at `docs/design/proof-required-predicate-carrier-proposal.md`; the professor review at `docs/design/proof-required-predicate-carrier-review.md`. Naming pattern matches `docs/design/oblig-pbt-3-proposal.md` / `docs/design/oblig-pbt-3-review.md`.

---

## 4. Effect rows for `Command` — reclassify, schedule later

The original professor turn dismissed `Eff [stdout, fs.read] a` and `Command {stdout} a` under the indexed-types exclusion at `docs/compiler-team-roadmap.md:48`. That dismissal was wrong by bundle: the roadmap conflates row-typed effects with indexed types proper (`Vect n a`, GADTs, dependent elimination, type-level arithmetic). The cost classes are meaningfully different.

Row-polymorphic effects are HM extended with row polymorphism — Leijen, *Extensible records with scoped labels* (2005); the Koka and Frank effect-row treatments. Algorithm W extension, not replacement. The current type checker at `compiler/src/LLMLL/TypeCheck.hs` is bidirectional HM with refinement aliases; row polymorphism is a tractable add-on at decidable typing cost.

The wins, scoped against today's `Command` mechanism:

- **Function-type-level effect surface.** Today the type `Command` is opaque; effect membership is decoded by reading the module's `(import wasi.* (capability ...))` declarations at `compiler/src/LLMLL/TypeCheck.hs:641-660`. The agent reads the function's type and must follow back to module imports to know what effects are reachable. Row types push the effect set into the function type directly.
- **Per-function least authority.** Authority is per-module today: a module that imports `wasi.fs.write` for one function makes that authority reachable in every function within the module. Row types let each function declare only the effects it uses; the checker verifies subset-of-declared.
- **Effect-aware composition.** `seq-commands` today: `(Command, Command) → Command`. Under rows: `seq-commands : Command {e1} a → Command {e2} b → Command {e1 ∪ e2} b`. Union as the natural composition rule.

### Bundle B (staged path)

| Stage | Content |
|---|---|
| B0 | Function-level effect *summaries* in reports — derive effect sets from module-import + body inspection; surface in the obligation report. No type-system change. |
| B1 | Explicit row-annotated `Command {stdout, fs.read} a` types in function signatures (opt-in). |
| B2 | Row-polymorphic effect inference: `Command {ρ} a` with row variables. |
| B3 | Effect-aware contracts: `seq-commands : Command {e1} a → Command {e2} b → Command {e1 ∪ e2} b`. |

**Guardrail:** start with coarse capability labels (`stdout`, `fs.read`, `net.http`) — **not** value-indexed paths (`fs.read "/data"`). Value-indexed labels push toward singleton types and dependent typing; the existing capability mechanism already handles path / scope authority at the import declaration. Keep that separation deliberate.

### Routing

Bundle B is **not** part of v0.11. The inversion in §1 is the v0.11 spine; Bundle B is a v0.12+ language-design candidate that `language-team` scopes on its own merits, post-inversion. The point of this section is to reclassify it out of the indexed-types research track at `docs/compiler-team-roadmap.md:48`, where it does not belong, and into its own scheduling line.

---

## 5. Path A holds; the agent-cognition critique is solved locally

The original professor turn classified the external critique's *the semantic anchor is too large* claim as Path-A-vs-Path-B re-litigation and pointed to the prior debate at `docs/design/verification-debate.md:8-15`. That classification was correct on the metatheory question and incomplete on the agent-cognition question.

The Path-A debate at `docs/design/verification-debate.md:118-124` was about *academic verification standards*: does LLMLL have a formal small-step semantics, a proven-correct codegen, a proven-correct liquid-fixpoint encoding? The conclusion was no — LLMLL is engineering-first with explicit limitations — and the conclusion stands. Path B (a separate small-step semantics, a soundness theorem for codegen, a soundness theorem for the liquid-fixpoint encoding) remains a different project class and should not be re-opened without a costed proposal.

The external critique is making a **different** argument: when an agent reads one LLMLL function, what mental model does it need to maintain? Today the answer is the full pipeline — source → JSON-AST → typechecker → verifier encoding → trust classification → codegen → Haskell runtime — because the function's meaning depends on which path through the verification matrix at `LLMLL.md §5.3.5` the function takes, and that is not visible from the surface. The grammar inversion in §1 solves *this* problem at the source level: inside a core definition, the agent knows that fallback constructs are syntactically unavailable, and that the function is either body-faithfully verified or rejected. The five-stage pipeline still exists in the implementation, but the agent does not need to model it to read one function.

**Local reading rule** (informal; `language-team` formalizes if useful):

> Inside a core definition, an agent should not need to model the entire source → AST → typechecker → verifier-encoding → codegen → Haskell pipeline. It should know that unsupported constructs are syntactically unavailable and that the remaining code is either body-faithfully verified or rejected.

This is what the inversion buys, without abandoning Path A globally.

---

## 6. Items requiring separate verification

Two items in the original processed memo were imported as professor-channel P0/P1 routing without being derived from this conversation's reading path. They are routed here for verification before they can be treated as professor-channel findings.

### 6.1 Verified in this turn — keep

- **Spec/schema version drift — P0.** `README.md:1` declares `# LLMLL — v0.10.6`. `LLMLL.md:1` declares `(v0.10.1)`. Five releases of drift between the two top-of-file version anchors. The fix is a CI gate that asserts version coherence across `README.md`, `LLMLL.md`, `CHANGELOG.md`, the schema `$id`, and `schemaVersion`. Scope: `documentation-lead` plus `compiler-engineer` (CI hook).

- **Integer-semantics gap — P1.** `LLMLL.md §5.3.5:756-759` documents that Z3 reasons over mathematical integers while Haskell `Int` wraps at 2⁶³. Contracts proven by the solver may not hold at overflow boundaries. `language-team` should pick a coherent model in a separate LT-proposal:
  - (i) source-level `int` means mathematical integer; `compiler/src/LLMLL/CodegenHs.hs` emits `Integer` (real runtime perf cost; closes the verifier-runtime gap);
  - (ii) keep `Int`; emit no-overflow obligations alongside QF-LIA proofs (cheaper runtime; spec-side surface);
  - (iii) move the verifier to QF-BV (most expensive; sharpest soundness).

  Not a v0.11 inversion blocker; should be on the v0.11 docket as a separate spec decision.

### 6.2 Requires verification before professor-channel attribution

- **EOp argument checking** (claimed P0 in the processed memo). The memo claims operator arguments are silently ignored in the typechecker. **Not inspected in this conversation.** The claim is plausible and worth investigating, but it should not be attributed to a professor-channel finding until verified. **Route to `compiler-engineer`**; if confirmed, schedule as a separate P0 from the inversion work.

- **Multi-subject PBT over-credit** (claimed P1 in the processed memo). `README.md:7` describes v0.10.6 OBLIG-PBT-4 as explicitly closing *"the Pacheco-Lahiri-Ernst overallocation gap left by the v0.10.5 head-position singleton fallback on multi-callee metamorphic-relation properties."* Either the v0.10.6 fix is incomplete (residual gap must be stated by `experiment-lead` or `compiler-engineer`), or the item is stale. **Route to `experiment-lead`** for residual-gap assessment; remove from professor-channel routing if no residual is identified.

---

## 7. What is not being recommended

To prevent mis-routing, the following are explicitly out of scope for v0.11 inversion work:

1. **Path-B foundations work** — a separate small-step semantics, a codegen soundness theorem, a liquid-fixpoint encoding soundness theorem. Not re-opened. `docs/design/verification-debate.md:118-124` stands.

2. **Full indexed types** — `Vect n a`, GADTs, dependent pattern matching, type-level arithmetic, full Idris-style elaboration. Remain in the research track per `docs/compiler-team-roadmap.md:48`. Effect rows (§4) are **not** in this bundle and must be tracked separately.

3. **Removal of the trust diamond, weakness check, obligation report, refinement aliases, capability declarations.** All shipped, all sound, all keep their place under the inversion. The inversion changes which lattice point is *syntactically* reachable from the canonical definition form; it does not remove the lattice.

4. **Typeclass-law machinery beyond `def-interface :laws`.** `LLMLL.md §8.8.1` ships the `:laws` extension; deeper typeclass infrastructure is feature-frozen per `docs/compiler-team-roadmap.md:260`.

---

## 8. Acceptance criteria — empirical validation gate

The inversion described in §1 is an **architectural hypothesis** grounded in cognitive-load and search-space arguments: a smaller grammar surface inside the core form should reduce LLM hallucination surface, produce local parse-time rejection in place of pipeline-traversal verifier diagnostics, and (via §2) expose specification weakness as honest signal to the consuming agent. The hypothesis is plausible. It is not yet measured. **v0.11 must not ship the inversion as a proven win; it must ship it as a hypothesis tested against the existing experimental harness.** The original v0.10 obligation report was the project's prior bet on what helps LLMs (surface rich obligations); the inversion is a *different* bet (limit the grammar surface). Both are defensible. Choosing between them is empirical, and the project has the discipline to make it empirically.

The instrument exists. `experiments/minimal-agent/001-two-agent-auth` (18 attempts × 5 models, documented in `experiments/minimal-agent/findings/`) and the post-DL-B follow-up batches are the comparison surface. The v0.11 inversion ships behind a pre/post empirical gate.

### 8.1 Axes `experiment-lead` measures

`experiment-lead` formalizes the experimental protocol; this memo names the axes that matter, not the metrics themselves.

- **Grade distribution** — does the inversion shift the pass/fail distribution on the `001-two-agent-auth` baseline and post-DL-B follow-ups, holding model and prompt budget fixed? Improvement on at least one of (a) overall pass rate, (b) `verified` evidence fraction at pass, or (c) `?proof-required` emission rate on out-of-core contracts is the success signal.
- **First-pass success vs retry count** — does the inversion reduce the number of agent-loop iterations before a passing solution? The competing prediction (smaller grammar surface → more parse errors → more retries) is real; if iteration count rises while pass rate stays flat, the inversion has made authoring harder without making outcomes better.
- **Spec-strength distribution** — does the discriminative-power axis in §2 surface a non-trivial number of `verified` weak-spec functions in the existing benchmarks? If the metric never flags anything, it is not paying for its complexity; if it flags consistently on the post-v0.10 baselines, it is doing real work.
- **Boundary-form usage distribution** — across the migrated example programs (per §1.5), what fraction of functions land in the core form, the boundary form, the effect boundary, the shell? If migration produces near-100% boundary-form usage, the inversion has not changed where LLM-generated code lives; the canonical form is canonical in name only.

### 8.2 What counts as a passed gate

`language-team` adjudicates against `experiment-lead`'s results. Professor-channel recommendation: at least one of (a) overall pass rate, (b) `verified` evidence fraction at pass, or (c) `?proof-required` emission rate on out-of-core contracts must improve over the pre-inversion baseline on the existing benchmarks — **and** no axis must regress materially. *Materially* is `experiment-lead`'s call against the existing variance baseline established in `experiments/minimal-agent/findings/`.

### 8.3 What happens if the gate fails

v0.11 inversion is a deliberate breaking change with no backward-compatibility shim (per §Background). If the empirical gate fails, the project has spent v0.11 on the wrong architectural bet, and the right response is **not** to ship the inversion anyway. Two rollback paths:

- (i) **Demote the inversion to opt-in.** Keep the grammar change available behind a per-module pragma or `--grammar=core-inversion` flag; default remains the v0.10 mixed regime. The grammar work is preserved; the polarity claim is retracted until a future cycle.
- (ii) **Retract the grammar change; ship §§2–3 only.** Contract discriminative power and predicate-carrying `?proof-required` are valuable independently of the inversion; both can ship without the grammar work. v0.11 becomes an evidence-axis and obligation-channel release rather than an architectural-polarity release.

Architectural intuitions are not load-bearing without empirical evidence. The inversion does not get a free pass on the discipline the project applies elsewhere.

### 8.4 Sequencing — gate runs before irreversible commitments

The v0.11 implementation must be sequenced so the empirical gate runs **before** the schema-version bump and example-program migration are finalized:

1. `language-team` settles LT-proposals on §§1–3.
2. `compiler-engineer` ships the grammar change behind an explicit opt-in flag (e.g. `--grammar=core-inversion`), not as the default.
3. `experiment-lead` runs the pre/post comparison on `001-two-agent-auth` and the post-DL-B batches.
4. **If the gate passes**, `compiler-engineer` flips the default; `documentation-lead` migrates examples and bumps schemas.
5. **If the gate fails**, route to (i) or (ii) above.

This protects against the worst failure mode: shipping a v0.11 that the existing benchmarks reveal as a regression after the schema and example migration are irreversible.

§§2–3 (discriminative power axis, predicate-carrying `?proof-required`) are **not** gated on §1's empirical result and can ship independently. Their value is preserved under either rollback path.

---

## 9. Final routing

1. **v0.11 is a breaking design correction**, not a backward-compatibility-preserving release. Schema, syntax, and example fixtures migrate. No source-level compatibility shims. Subject to the empirical validation gate in §8.
2. **Promote the core form** — `language-team` adjudicates `def` vs `def-core` vs `def-logic`-retained, with the constraint that the permissive form is the **marked** one.
3. **Mark the shell** — the current broad `def-logic` surface becomes `def-boundary` / `def-shell` (name follows from item 2).
4. **Make fallback syntactically impossible in the core** — whitelist grammar production; `?proof-required` forbidden inside the core; `?hole` permitted but the function does not verify-complete until filled.
5. **Add contract discriminative power as a first-class evidence axis** alongside the diamond lattice, building on `compiler/src/LLMLL/WeaknessCheck.hs`.
6. **Implement predicate-carrying `?proof-required`** — informational, no evidence upgrade, forbidden inside the core.
7. **Name effect rows as Bundle B** for v0.12+, separate from the indexed-types research bundle.
8. **Do not re-open Path B** absent a costed proposal.
9. **Address spec/schema drift as a P0** via a CI gate; route to `documentation-lead` and `compiler-engineer`.
10. **Address the integer-semantics gap on the v0.11 docket as a separate decision** — coherent model choice, not a v0.11 inversion blocker.

---

## Hand-offs

- **`language-team`** owns LT-proposal(s) on:
  - (a) the grammar inversion in §1 — keyword choice, whitelist grammar, `letrec` routing, callee-restriction strictness;
  - (b) contract discriminative power evidence axis in §2;
  - (c) predicate-carrying `?proof-required` in §3;
  - (d) integer-semantics model choice in §6.1.

  Each is a distinct proposal. Bundling them risks the multi-topic inconsistency the language-team flagged on LT-A.

- **`professor`** reviews each LT-proposal as it lands; companion review docs follow the `oblig-pbt-3-*` naming pattern.
- **`compiler-engineer`** is blocked on settled LT-proposals for v0.11 implementation; separately, verify the EOp argument-checking claim in §6.2.
- **`experiment-lead`** designs and runs the v0.11 empirical validation gate per §8 — formalizes the experimental protocol against the axes named in §8.1, runs the pre/post comparison on `001-two-agent-auth` and post-DL-B batches, reports the result to `language-team` for pass/fail adjudication per §8.2; separately, verifies residual multi-subject PBT over-credit per §6.2.
- **`documentation-lead`** owns the spec/schema version-coherence CI gate per §6.1; migrates example programs per §1.5 once the grammar lands.

---

## Final position

LLMLL should not stabilize around a coordination shell with an optional verified-core flag. It should become a verified-core language embedded in an explicit coordination shell. Break the surface now; migrate examples mechanically; stabilize only after the core/shell polarity is correct **and** the empirical gate in §8 confirms the architectural bet on the existing benchmarks. The inversion is a hypothesis the project is equipped to test; it should not get a free pass on the discipline applied elsewhere.
