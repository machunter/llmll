# Spec-from-RFC Pipeline (R3)

> **Status:** Rev 1 — **§4 evaluation EXECUTED** (RFC 1982, 2026-07-12: all six criteria pass — [`examples/rfc1982_serial/`](../../examples/rfc1982_serial/), findings [`experiments/rfc1982-eval/findings.md`](../../experiments/rfc1982-eval/findings.md); outcome appendix below). Rev 1 folds F-1982-3 (C5 width adaptation), F-1982-4 (S4.4 shape-accurate flag floor), F-1982-5 (S1 verbatim source-text input). Rev 0 was the design doc for the roadmap R3 Active row (promoted 2026-06-23; worked-example criterion met by `examples/totp_rfc6238/` + `examples/tcp_rfc793/`).
> **Owner:** language-team. Consumers: experiment-lead (runs the evaluation plan), compiler-engineer (named gaps only), documentation-lead (INDEX entry, roadmap close-out).
> **Supersedes nothing.** Generalizes source #1 ("External Standards") of [`specification-sources.md`](specification-sources.md) into a repeatable pipeline; that doc remains the survey, this is the operating procedure for its strongest lane.

## Restatement

LLMLL's bet is that in its target domains the specification already exists as an external document, and the agent's job is *translation*, not invention ([`specification-sources.md`](specification-sources.md) §1). Two worked examples exist — TOTP/RFC 6238 and the TCP/RFC 793 state machine — but each was built ad hoc. This doc states the pipeline they instantiate, so a third RFC can be run through it by procedure rather than by imitation.

The pipeline's claim is deliberately bounded: it produces **traceable** contracts (every checkable clause points at its RFC clause via `:source`) with **classified** verification strength (verified / asserted / suppressed-with-reason), not a proof that the translation is faithful. Fidelity is an audit property (§2).

## 1. Pipeline stages

| # | Stage | Input | Output | Actor | Exists today |
|---|-------|-------|--------|-------|--------------|
| S0 | Fragment scoping | RFC + `Σ_auto` boundary | scope matrix (proven-vs-trusted) | human (+agent draft) | pattern: `VERIFICATION_SCOPE.md` in both examples |
| S1 | Clause extraction | RFC **source text** (verbatim access, not paraphrase) | clause inventory | agent, human-reviewed | first persisted instance: `examples/rfc1982_serial/VERIFICATION_SCOPE.md` (was **gap G1**) |
| S2 | Clause classification | clause inventory | per-clause translation class (§1.2) | agent, human-reviewed | implicit — taxonomy stated here for the first time |
| S3 | Contract authoring + `:source` binding | classified clauses | `pre`/`post`/`weakness-ok`/`check` with provenance | agent | shipped surface (`LLMLL.md` §4.6, §4.5, §5.1) |
| S4 | Adequacy checking | contracted module | coverage + vacuity + mutant evidence | compiler + human | `--spec-coverage`, `--weakness-check`/`--cdp`, authored mutants |
| S5 | Verification + freeze | filled module | verified/refuted verdicts + frozen CI gate | compiler | `verify --strict-verified-core`; `EXPECTED_RESULTS.json` + `scripts/benchmark-totp.sh` |

### S0 — Fragment scoping (before extraction, not after failure)

Decide, per RFC section, whether its obligations land inside `Σ_auto` (QF-LIA + non-recursive ADTs + closed length measures + bool; `LLMLL.md` §5.3.3/§5.3.5) or outside (crypto primitives, unbounded data, liveness). The two examples bracket the range: RFC 793's transition table is *entirely* inside (state machine over enums, outcome sum → `verified`); RFC 6238's core is *outside* (HMAC-SHA1 correctness is not QF-LIA), so its pipeline output is structural verification + `asserted` contracts + suppression governance. **What can go wrong:** scoping optimism — promising `verified` for a clause that later classifies nonlinear. The scope matrix is written first and is the demo headline, not a post-hoc disclaimer (`examples/tcp_rfc793/DEMO-RUNBOOK.md` says exactly this).

### S1 — Clause extraction

Inventory the RFC's normative material: MUST/SHALL sentences, transition tables, formulas, length/format rules, and appendix test vectors. **S1's inputs include the RFC source text itself** — clause quotes must be verbatim, so the stage requires fetch/file access to the standard, not a from-memory paraphrase (a paraphrase fails the §2 audit's side-by-side read; F-1982-5). Output is a **clause inventory** — clause ID, quoted text, disposition. The inventory format is a table in the example's `VERIFICATION_SCOPE.md`; the first persisted instance (and the template future runs copy) is `examples/rfc1982_serial/VERIFICATION_SCOPE.md` (9/9 clauses — gap G1, closed 2026-07-12). The two Rev 0 examples predate the convention and cite clauses directly from their contracts. The inventory matters because `--spec-coverage` measures "functions with contracts" while no tool measures "RFC clauses with contracts"; the inventory is the denominator that makes the second ratio auditable by a human (§2).

### S2 — Clause classification

Each inventoried clause gets one translation class. The taxonomy, grounded in what the two examples actually used:

| Class | RFC clause shape | LLMLL target | Fragment | Worked instance |
|---|---|---|---|---|
| **C1** state transition / table | "in state S on event E, do X" | totality `post` over enum + outcome sum | QF-LIA + acyclic datatype theory — **auto-discharged** | `step` post, RFC 793 §3.2 (`examples/tcp_rfc793/step.llmll:43-56`) |
| **C2** arithmetic invariant / range | formulas, bounds, floor division | refinement `pre`/`post` | QF-LIA — **auto-discharged** (nonlinear subterms need restriction or land `asserted`) | `compute-time-step` (RFC 6238 §4.2), `dynamic-truncate` bound (RFC 4226 §5.3) |
| **C3** length / format rule | "output is d digits", padding | length-measure `post` (`(= (len result) d)`) | closed measure set — **auto-discharged** | `pad-otp` (RFC 4226 §5.4) |
| **C4** opaque primitive | "compute HMAC-SHA1(K, T)" | typed builtin + `weakness-ok` with provenance-bearing reason | outside `Σ_auto` — **trust channel**, `asserted`/suppressed | `hmac-sha1-wrap` (RFC 2104; `LLMLL.md:2424-2427`) |
| **C5** test vector | appendix tables — **width-parametric**: an RFC may state its examples at a different parameter width than the instance (RFC 1982 §5 uses SERIAL_BITS = 2/8); vectors must be adapted to the instance width and **the adaptation recorded in the clause inventory** (F-1982-3) | `check` block (`LLMLL.md` §5.1) | dynamic channel — **executed, not proved** | 4 vectors from RFC 6238 §A.1 (verbatim); RFC 1982 §5 vectors width-adapted to 32 bits (`examples/rfc1982_serial/`) |
| **C6** untranslatable | SHOULD-prose, liveness, timing, concurrency, security arguments | recorded exclusion in scope matrix | none — **spec is silent (intentional)** | RFC 793 retransmission/timeout text; RFC 6238 §5.2 resync window |

A clause that classifies C2-nonlinear or quantified has two dispositions, in preference order: restrict the surface form to stay QF-LIA, or mark the clause `?proof-required` so it promotes to the trust channel as `asserted` (`LLMLL.md:2296`). Weakening the predicate to silence the verifier is the named anti-pattern.

### S3 — Contract authoring and `:source` binding

Author the contract *from the RFC text*, not from the intended body — RFC 793's post is the full transition-table totality, which is why a handshake-skipping body refutes. Binding conventions:

- One `:source` string per `pre`/`post` clause: `"RFC NNN §X.Y — eight-to-fifteen-word paraphrase"` (grammar: `LLMLL.md:1979-1980`; semantics: §4.6 — pure metadata, threaded to `--trust-report` and `.verified.json`).
- **Provenance granularity limit:** when multiple `pre` clauses are `and`-combined, `:source` is dropped as ambiguous (`LLMLL.md:746`). A function whose precondition draws on two distinct RFC clauses cannot carry both provenances today — **gap G2** (compiler-engineer, deferred: per-conjunct provenance list; JSON-AST schema delta, so it queues behind a schema-bump occasion).
- **C4 convention:** `weakness-ok` functions have no `pre`/`post` to suffix, so RFC provenance lives in the reason string (`LLMLL.md:2427`). This is a convention, not a checked channel — the trust report cannot distinguish an RFC-cited reason from a free-form one. Acceptable at current scale; recorded as the boundary of what §2's audit can lean on.

### S4 — Adequacy checking

Three mechanized checks plus one human loop, in order of what they actually catch:

1. **Coverage** — `--spec-coverage` (`LLMLL.md:846`): every function contracted or `⊘`-suppressed with a reason; the TOTP gate freezes effective coverage at 100% (6/6 with one `⊘`).
2. **Vacuity** — `--weakness-check` (trivial-body pass, `LLMLL.md:829`) and `--cdp` (counted discriminative-power metric, `LLMLL.md:842`): catches a translated clause so weak that identity/constant bodies satisfy it.
3. **Refutation witness** — an authored mutant per core invariant (`step-bad`: one wrong transition, refuted and branch-localized). This is the project's standing discriminative-example bar applied per-RFC: a clause translation without a refuting mutant has no evidence it constrains anything.
4. **The human co-evolution loop** — `step-weak` demonstrates the check that does *not* mechanize: an under-specified post (totality clause forgotten) lets a wrong body verify SAFE. **The mechanized floor is shape-dependent** (n=2 across two RFCs, F-1982-4): no flag fires on the totality-omission shape (`step-weak`), but `--weakness-check` *does* fire on an implication-only bool post (`serial-lt-weak` — "indistinguishable from `(lambda [...] true)`") — so the floor is higher than "nothing fires" for one shape class, and the human-loop conclusion stands for the rest. CDP measures vacuity against a closed candidate catalog, not fidelity against the RFC; the `adv-spec-weaken-0` finding F-002 settled that the self-attestation channel has no per-instance oracle (`LLMLL.md` §4.4.6). Under-specification is caught by the S1 inventory (a clause with no contract is visible as an uncovered row) and by human review of clause↔predicate pairs — the pipeline makes the weakness *visible and enumerable*, it does not auto-detect it.

### S5 — Verification and freeze

`verify --strict-verified-core` (or the bundled `--strict-verify`) on the clean, mutant, and weak fixtures; freeze the expected verdicts, coverage numbers, and trust-report shape (`EXPECTED_RESULTS.json`, 14-assertion gate in `scripts/benchmark-totp.sh`) so the RFC example becomes a CI regression fixture rather than a demo that rots.

## 2. What `:source` claims — the provenance model

`:source` is a **traceability pointer, not a fidelity proof**. It claims: this clause was authored against that RFC location, and the claim survives into `--trust-report` output and `.verified.json` sidecars (§4.6) so an auditor can enumerate every contract↔standard edge mechanically. It does **not** claim the predicate is a correct formalization of the cited text — nothing checks the string against anything.

Audit procedure (human, per clause): read the cited RFC text and the predicate side by side; confirm direction (the RFC's MUST maps to the contract's obligation, not its assumption); confirm totality clauses are present when the RFC's table is exhaustive (the `step-weak` failure mode); confirm units/encodings (seconds vs steps in RFC 6238 §4.2 is exactly where a silent transposition would live). The S1 clause inventory is the audit's checklist; without it the auditor re-derives the denominator from the RFC each time — which is what G1 exists to fix.

## 3. Generalization limits

Translates today, with evidence: state machines over finite enums with payload-bearing outcome sums (C1 — reaches `verified`); linear arithmetic invariants, ranges, floor/mod arithmetic within QF-LIA (C2); fixed-length/format rules within the closed measure set (C3); appendix test vectors (C5). Does not translate: cryptographic function correctness (C4 — governed suppression, `asserted` at best); liveness, retransmission, timing, and concurrency text (C6 — out of scope, and `Σ_auto` has no temporal fragment); unbounded-data invariants over lists/arrays/maps (blocked on the data-scope extension track, Lever A first — [`data-scope-extension.md`](data-scope-extension.md)); SHOULD-level prose (policy, not predicate).

Degenerate inputs the pipeline must classify rather than mishandle:

1. **A clause spanning two RFC sources** (e.g. RFC 6238 delegating truncation to RFC 4226 §5.3) — expected: one clause, `:source` cites the operative section; the inventory row records the delegation chain. Channel: audit/human; G2 is the eventual mechanized fix.
2. **A constructor-valued test vector** (C5 over a sum type) — expected: `check` block parses but the property evaluator skips constructor-valued vectors (the RFC 793 runbook's verify-time-vs-run-time boundary); the vector's content is instead carried by the C1 post. Channel: spec is silent on runtime evaluation of constructed sums — intentional today, flagged in the scope matrix.
3. **An RFC clause quantified over unbounded time** ("for all future time steps") — expected: C6, or C2 restricted to the per-call obligation (`t ≥ t0` as `pre`, not a temporal invariant). Channel: type/contract per call; the temporal claim is recorded as out of scope.
4. **A weakness-ok'd function later given a contract** — expected: W602 fires, contract wins, `weakness-ok` reported redundant (`LLMLL.md:721-722`). Channel: trust.

## 4. Evaluation plan — one unseen RFC

> **Executed 2026-07-12** on the primary candidate (RFC 1982) — all six criteria pass; see the outcome appendix and [`experiments/rfc1982-eval/findings.md`](../../experiments/rfc1982-eval/findings.md). The plan text below is kept as written (it is the procedure future candidates rerun).

Run the pipeline by-procedure (S0→S5) on an RFC not yet in the repo, chosen from the classes the taxonomy says should work. Primary candidate: **RFC 1982 serial number arithmetic** — pure modular-comparison arithmetic (C2, famously subtle, historically a source of real DNS bugs) with a small clause inventory; alternate: **RFC 6455 §7.4 WebSocket close-code state machine** (C1, a second data point for the transition-table class). Owner: experiment-lead executes; language-team adjudicates taxonomy failures.

Success = all of: (i) a persisted S1 clause inventory with every normative clause dispositioned into C1–C6; (ii) at least one core invariant reaching body-faithful `verified`; (iii) every contracted clause carrying `:source`; (iv) an authored mutant refuted and localized; (v) an authored weak-spec variant documented as the co-evolution exhibit; (vi) 100% effective coverage with every `⊘` reason citing the RFC. Failure modes that count as *findings, not embarrassments*: a clause that fits no C-class (taxonomy gap → revise this doc); a scoped-in clause that turns out nonlinear (S0 procedure gap); pipeline effort dominated by a stage this doc calls "agent" work but which needed a human (actor-assignment error — feeds the orchestrator design, [`agent-orchestration.md`](agent-orchestration.md)).

## 5. Case studies as pipeline instances

**RFC 793 / `examples/tcp_rfc793/`** — S0: transition table scoped fully inside `Σ_auto` (`VERIFICATION_SCOPE.md` is the artifact). S1/S2: §3.2 table → one C1 clause (five legal pairs + totality), retransmission/timeout text → C6. S3: totality post authored from the table with `:source "RFC 793 §3.2 — connection state transition table; illegal pairs -> REJECTED"` (`step.llmll:56`); outcome is a real sum, no int sentinel. S4: `step-bad` (handshake skip) refuted and branch-localized; `step-weak` (totality clause dropped) verifies SAFE — the documented co-evolution exhibit. S5: `--strict-verified-core`, `verified`. The example demonstrates the pipeline's ceiling: core invariant proved, wrong implementation impossible.

**RFC 6238 / `examples/totp_rfc6238/`** — S0: crypto core scoped *out* (HMAC correctness ⊄ QF-LIA). S1/S2: §4.2 formula → C2 (`compute-time-step`), RFC 4226 §5.3 bound → C2, §5.4 padding → C3 (`pad-otp`), HMAC → C4 (`hmac-sha1-wrap`, provenance in the `weakness-ok` reason per `LLMLL.md:2427`), §A.1 vectors → C5 (4 `check` blocks). S4/S5: 100% effective coverage with one `⊘`; trust report `verified: 0, asserted: 4, no_contract: 2` — exactly what a crypto-cored RFC should report; frozen by the 14-assertion CI gate. The example demonstrates the pipeline's floor: when the core is opaque, the output is structural verification plus a fully enumerated, governed trust surface — which is still more than an unverified implementation offers, and the report says exactly how much more.

## 6. Gaps, with owners

| ID | Gap | Owner | Weight |
|----|-----|-------|--------|
| G1 | ~~No persisted clause-inventory convention~~ — **CLOSED**: first persisted inventory delivered by the RFC 1982 run (`examples/rfc1982_serial/VERIFICATION_SCOPE.md`, 9/9 clauses; the template future runs copy) | language-team | closed 2026-07-12 |
| G2 | `:source` dropped on `and`-combined `pre` clauses; no multi-source provenance (`LLMLL.md:746`) | compiler-engineer | deferred — JSON-AST schema delta; queue behind next schema-bump occasion |
| G3 | C4 provenance is an unchecked reason-string convention | none (accepted) | recorded boundary, revisit only if an auditor consumer materializes |
| G4 | ~~Evaluation run (§4) not yet executed~~ — **CLOSED**: executed on RFC 1982, all six criteria pass (outcome appendix) | experiment-lead | closed 2026-07-12 |

## Appendix — §4 evaluation outcome (Rev 1 fold)

Executed 2026-07-12 on **RFC 1982 (DNS serial number arithmetic)**, the §4 primary candidate, at compiler v0.14.38. Artifact: [`examples/rfc1982_serial/`](../../examples/rfc1982_serial/) (verdicts frozen in the family's `EXPECTED_VERDICTS.json` under `make refute-crux-gate`). Full findings: [`experiments/rfc1982-eval/findings.md`](../../experiments/rfc1982-eval/findings.md).

| # | Criterion (§4) | Result |
|---|---|---|
| i | Persisted S1 clause inventory, all clauses dispositioned | **PASS** — 9/9 (C2 ×6, C2+C5 ×1, C5 ×1, C6 ×1); the first G1 artifact |
| ii | ≥1 core invariant body-faithful `verified` | **PASS, exceeded** — 3/3 (`serial-add`/`serial-lt`/`serial-gt`); trust report `verified: 3, asserted: 0` |
| iii | Every contracted clause carries `:source` | **PASS** — 6/6 (one `pre` per function; the G2 drop never triggers) |
| iv | Authored mutant refuted + localized | **PASS ×2** — `serial-lt-bad` (the historical naive-`<` DNS bug), `serial-add-bad` (no wrap) |
| v | Weak-spec co-evolution exhibit | **PASS** — `serial-lt-weak` (partial §3.2 reading); inventory row Q5 makes the gap enumerable |
| vi | 100% effective coverage, `⊘` reasons cite the RFC | **PASS** — 100% (3/3), zero `⊘` needed (the `⊘` half is vacuous for this RFC) |

The S0 decision that mattered: RFC 1982 §3.1's `modulo` was dispositioned into a linear conditional subtraction *before* authoring (SERIAL_BITS = 32) — the fragment-scoping stage doing exactly its job. **No taxonomy gap, no S0 scoping error, no actor-assignment error observed** (n=1 operator run; a blind-agent repetition would be needed before claiming S1–S3 are agent-doable unassisted). **CDP null result:** `[spec-inconsistent-or-unproven]`, zero reliable candidates on all three functions — no adequacy signal from CDP on biconditional-bool/case-split contract shapes, consistent with the tcp-recorded caveat and with §S4.4's division of labor.

Rev 1 folds from this run: **F-1982-3** (§1.2 C5 row — width-parametric vectors, adaptation recorded in the inventory), **F-1982-4** (§S4.4 — the mechanized flag floor is shape-dependent; `--weakness-check` fires on implication-only bool posts), **F-1982-5** (§S1 — verbatim RFC source-text access is a stage input). Compiler-side findings F-1982-1/-2 are tracked on the roadmap as COVERAGE-TIER.
