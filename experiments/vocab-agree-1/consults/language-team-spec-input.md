---
title: "SPEC-INPUT: what a developer should author for LLMLL, if not an RFC"
status: "Rev 0, DRAFT (language-team, 2026-11-15). Saved in experiments/vocab-agree-1/consults/. It is not in docs/design/."
author: language-team
consumers: [user, professor, compiler-engineer, experiment-lead]
relates: "spec-from-rfc-pipeline.md (Rev 1), rfc-swarm-playbook.md (Rev 0), spec-agreement-proposal.md (SPEC-AGREE-1 Rev 1), spec-agree-1-witness-weight-review.md, specification-sources.md, ~/Downloads/spec-elicitation-loop.md (user draft)"
---

# SPEC-INPUT: what a developer should author for LLMLL, if not an RFC

## Restatement

The user's premise is that the developer's job moves left, into the specification. The question is
whether an RFC is the best input for LLMLL to implement, and what the state of the art offers instead.

In LLMLL terms the question is this. Which authored artifact maps most directly onto `pre`/`post`
clauses with `:source`, `check` blocks, refinement aliases and typed holes? And which artifact
maximises the share of clauses that reach body-faithful `verified` inside `Σ_auto`?

**Short answer.** An RFC is good *evidence* and a poor *input*. An RFC is written for a human who
implements a wire protocol. Most of the RFC pipeline's stages exist to recover structure that the
RFC author did not write down: clause IDs, normativity, the vocabulary of types, the dispositions,
the characteristic core and the examples. A developer who works "shift left" should author that
structure directly. I propose a **clause sheet**: a controlled-English dialect whose sentence
templates each compile to exactly one contract clause, with a vocabulary block, an example table, a
decision log and an exclusion ledger. The RFC, where one exists, becomes a cited source of the sheet
and not its substitute.

**Two reference classes.** The *measurement* set for this question is the in-repo RFC runs (RFC 1982,
TFTP, ARP, RFC 4648, TCP, TOTP). The *design-reference* set is what LLMLL competes with for the "spec
first" developer: Kiro and Spec Kit on the structured-English side, and Dafny, Verus, SPARK and P on
the formal side. A proposal is good if it beats the first group on proof and the second group on
authoring cost. It is not enough to beat the RFC pipeline.

## Context located

1. `LLMLL.md §5.3.3` - `Σ_auto` = QF-LIA core, measures, admissible sums and pairs, `bytes[n]` and maps
   with exact reflection. `if` in a `pre`/`post` is outside the fragment (`CONTRACT-IF-1`), so case
   splits must be written with `=>`.
2. `LLMLL.md §5.3.4` - body VC `P ∧ result = ⟦B⟧ ⟹ Q`. `verified` means the body satisfies the
   contract for all well-typed inputs. It says nothing about whether the contract is the intent.
3. `LLMLL.md §4.6` - `:source` is free-form metadata, per clause since SRC-CONJ-1 (v0.14.65). Nothing
   checks it.
4. `LLMLL.md §5.1` - `check`/`for-all` blocks produce `tested`, not `verified`.
5. `docs/design/spec-from-rfc-pipeline.md` §1-§3 - stages S0-S5 and classes C1-C6. §2 states that
   `:source` is "a traceability pointer, not a fidelity proof".
6. `docs/design/rfc-swarm-playbook.md` stages A-L - dual blind census, characteristic core before
   dispositions, closed barrier list B1-B8, artifact audit G2, root contracts K, coverage lint L.
7. `experiments/rfc1982-eval/findings.md` - 9/9 clauses dispositioned, 3/3 functions `verified`,
   mutants refuted, CDP gave no signal on biconditional posts.
8. `experiments/rfc-swarm/SUMMARY.md` - TFTP, ARP, RFC 4648 ledgers. Corrected C1+C2+C3 coverage is
   78.5% / 55.3% / 84.6%. 22 of 22 mutants refuted, 6 of 6 good twins survive.
9. `experiments/rfc-swarm/runs/*/inventory-dispositioned.json` - barrier tallies, counted for this
   draft: ARP `B5` 22, `B2` 11, `B7` 8, `B8` 6, `B1` 1; RFC 4648 `B7` 8, `B8` 7, `B5` 4, `B3` 1.
10. `experiments/rfc-swarm/runs/rfc826/roots.llmll` header - about fifteen encoding decisions (opaque
    sorts as `int`, relations as instantiated guards, no Packet sort, no byte offsets). None of them
    carries a `:source`. This is where fidelity is decided and nothing traces it.
11. `docs/design/spec-agreement-proposal.md` §0 - only 9 of 85 `Encoded` rows (10.6%; ARP 5.1%) are
    comparable by `Σ_subsume`. All 18 abstentions are constructor terms.
12. `docs/design/spec-agree-1-witness-weight-review.md` - no two-contract difference query exists;
    `FQVerifyResult` carries no model. Recommends finite case-splitting over constructors.
13. `docs/design/byte-io-proposal.md` Rev 2a - unsized `bytes`, `bytes-slice` with a `pre`, a
    `bytes-length` guard arm. Step 3 is in flight on branch `byte-io/step-3`.
14. `/Users/burcsahinoglu/Downloads/spec-elicitation-loop.md` - user draft, read as data. It proposes
    loose English, N readings, solver witnesses, A/B questions, frozen contracts.

**In-flight drafts on this topic.** `spec-agreement-proposal.md` (SPEC-AGREE-1) and the user's
elicitation-loop draft both address the fidelity link. This proposal is upstream of both: it reduces
the number of sentences that need N-way agreement at all. It *anticipates* SPEC-AGREE-1 and does not
replace it.

**Drift found while reading.**

- **D1 (user draft vs code).** The draft states that the comparison query "always terminates with a
  definite answer" inside "the linear-arithmetic, array and datatype fragment". At HEAD the
  comparison path is `Σ_subsume`, which is QF-LIA scalars only, and no difference query exists
  (`spec-agree-1-witness-weight-review.md` hazard 1). The claim is true of `Σ_auto` in principle and
  false of the shipped tool. The draft's baseline is v0.28.0; HEAD is v0.39.0.
- **D2 (user draft vs code).** The draft names `diverge-report`'s `outside_fragment` partition as
  the fragment gate for a reading. That partition classifies *fills* against one contract. It does not
  classify a contract clause. The correct gate is `qfContract` (`RefineReuse.hs`) for comparison, or
  `classifyContractFragment` for verification.
- **D3 (doc vs doc).** `spec-from-rfc-pipeline.md` §1.2 lists six classes. The playbook's barrier
  list has eight reasons (`B8` "outside any tool"). The pipeline doc does not mention barriers. This is
  minor and is a doc-lead item.

## Design proposal

### Part 1. Where RFCs worked and failed as LLMLL input

**What became verified contracts.** Four clause shapes reached body-faithful `verified` across the
runs.

| Shape | Evidence | Why it works |
|---|---|---|
| C1 transition table over finite enums, outcome as a real sum | TCP `step` (totality post), ARP 31 C1 rows Encoded, TFTP 15/15 core rows | Enums and admissible sums are in the datatype class of `Σ_auto`. An exhaustive table is a conjunction of guarded equalities. |
| C2 linear arithmetic with a range | RFC 1982 `serial-add`/`serial-lt`/`serial-gt`, 3/3 `verified`; TOTP `compute-time-step` | QF-LIA, after S0 rewrote `modulo 2^32` as one conditional subtraction. |
| C3 fixed-length or fixed-width format | RFC 4648 24 C3 rows Encoded; TOTP `pad-otp` | Closed measure class (`string-length`, `bytesLen`). |
| C5 test vectors | TOTP §A.1, RFC 1982 §5 (width-adapted) | `check` blocks. `tested`, not `verified`. |

**What was excluded, and why.** The barrier tallies show two kinds of exclusion. They need different
responses.

1. **Genre exclusions (C6, B1-B3).** Timing, retransmission, transport binding and trace properties.
   ARP has 14 C6 rows and 11 `B2` rows. Every complete protocol RFC carries this prose. The playbook's
   stage J already stopped grading on it, because an exclusion ratio "measures the genre composition
   of the target document, not the reach of the verifier". No input format changes this, and no
   planned fragment widening reaches it (B3 temporal tier is REFUSED in
   `rfc-swarm-coverage-widening.md` R4).
2. **Fragment exclusions (B5 string structure, B4 opaque, part of B8).** ARP's length-driven fields
   need `8 + 2*ar$hln + ar$pln` over a byte sequence. That one fact accounts for 22 of ARP's 34
   excluded C1-C3 rows. RFC 4648 halted at gate J on line wrapping (L161-163, B5). TOTP's HMAC core is
   C4 and is `asserted`. These rows are the fragment's real limit.

**Where fidelity was lost.** Fidelity loss did not happen where the pipeline measures. It happened at
four places.

- **F-1. The modeling layer has no provenance.** `roots.llmll` for ARP opens with roughly fifteen
  encoding decisions. Examples: "Host, HwAddr, ProtoAddr and ProtoType ... are modelled as int"; "No
  Packet sort (MD8), no time sort (MD6) ... no byte offsets". Each decision changes what a clause can
  mean. None is a `:source`-bearing object, and RFC-COV-1 does not see them. ARP's `B7` row A63 rests
  on such a decision (`SUMMARY.md` "A `B7` row under the corrected criterion").
- **F-2. Over-crediting a model.** TFTP counted 11 format rows as carried under Deployment-modeled
  although the model had no byte widths. Corrected coverage fell from 95.4% to 78.5%. The error was
  in disposition, not in proof.
- **F-3. Misreading a clause.** RFC 4648 row A1 moved a qualifier out of an `unless` exception. A
  human found it, and stage G2 now finds it too. The cause is that an English exception clause has
  no fixed attachment.
- **F-4. Omitted totality.** `step-weak` (TCP) and `serial-lt-weak` (RFC 1982) verify SAFE with an
  under-specified post. `--weakness-check` catches only the implication-only bool shape
  (F-1982-4). The totality-omission shape gets no flag.

**The cost structure is the second finding.** Stages A to G2 of the playbook (pin, census twice,
reconcile, core, disposition, audit) spend most of a run recovering a clause inventory. The same
inventory is what a spec-first developer would write anyway. On RFC 4648 the run spent 76 minutes in
stages A-I before it halted.

**Conclusion for Part 1.** RFCs work as input when the subject matter is enum-state-machine plus
linear arithmetic plus fixed width. They fail on length-driven formats, crypto and time. Independent
of fit, the RFC form loses fidelity at the modeling layer, at exception attachment and at totality.
None of those three losses is a fragment problem. All three are input-format problems.

### Part 2. State of the art in spec-first development (checked 2026-11-15)

Items marked **[unverified]** come from memory or from secondary sources only.

| Family | Representative work, 2024-2026 | What it produces | What it lacks for LLMLL |
|---|---|---|---|
| Structured English | EARS (Mavin et al., RE 2009); Kiro (AWS, preview July 2025) uses EARS acceptance criteria and derives property-based tests from them; Kiro "Requirements Analysis" (announced 2026-05-12) rewrites requirements, translates them to logic and runs an SMT solver for conflicts and gaps, and asks either/or questions; GitHub Spec Kit (open-sourced Sept 2025, freeform `spec.md`); Tessl | Tests, task plans, consistency checks of the requirements | No proof that code meets the sentences. Kiro's own docs say PBT "is not formal verification". Requirement-to-code link is by LLM. |
| BDD / Gherkin | Given/When/Then scenarios executed by Cucumber | Executable examples | Examples only, no universal claim. Maps to C5, not to `post`. |
| Example / test-vector specs | TiCoder (Lahiri, Fakhoury et al.; TSE 2024 user study, DOI 10.1109/TSE.2024.3428972): intent fixed by yes/no answers on generated tests. Simulated-user MBPP pass@1 48.4% to 70.5% after one query (2022 preprint figures) | Tests that pin intent | Tests cannot express "for all". |
| Executable reference specs | AWS Cedar: a Lean model of the authorization semantics plus differential random testing against the Rust engine **[unverified, from memory]** | A second implementation that is the spec | The spec is a program. It can be as wrong as the code. |
| Lightweight formal models | Alloy (bounded instances); TLA+; P at AWS (S3 strong consistency, PObserve log checking since 2023, Brooker and Desai, CACM 2025); PeasyAI generates P machines from design docs | Model-checked designs | Model-to-code gap. PObserve checks logs at run time, not code statically. |
| Contract languages | Dafny, Verus, SPARK, F\*. Vericoding benchmark (arXiv 2509.22908): from formal specs, off-the-shelf models reach about 82% Dafny, 44% Verus, 27% Lean. DafnyComp (arXiv 2509.23061): compositional spec generation about 7% at Pass@8 | Verified code | The spec must already be formal. Writing it is the hard part. |
| NL to formal spec | nl2postcond (Endres, Fakhoury, Chakraborty, Lahiri, FSE 2024): LLM postconditions caught 64 Defects4J bugs. "Eliciting Specifications: When Does Interactive Clarification Help?" (NeurIPS 2026, Verina Lean 4, 189 tasks): same-model clarification lowered strict pass@1; cross-model gave up to +6.3 points; postconditions degraded most **[abstract only]** | Candidate contracts | Fidelity still rests on human review or on agreement. |

**The pattern across 2025-2026.** Two lines converge. The tools line (Kiro, Spec Kit) moved English
toward structure, and in May 2026 Kiro added a solver over the *requirements*. The verification line
shows that, given a formal spec, LLMs now write verified code at high rates (vericoding, about 82% in
Dafny), and that the spec is the bottleneck (DafnyComp, NeurIPS 2026 elicitation). This supports the
user's premise. It also says where LLMLL can win. No surveyed tool both (a) makes the requirement
sentence the unit of provenance, and (b) proves the code against that sentence. LLMLL already has
(b) and half of (a) through per-clause `:source`. The search behind this table was short and is not
a novelty claim.

### Part 3. The proposed input: a clause sheet

**Principle.** Move every interpretive decision that the RFC pipeline makes *after* reading into an
artifact the developer authors *before* any agent reads it. Make the English-to-formula step
mechanical wherever a template can carry it. Keep free English, but tag it and route it to
agreement and elicitation.

**Six parts of a clause sheet.** Each part maps to a shipped LLMLL surface.

| Part | Developer writes | Compiles to | Replaces playbook stage |
|---|---|---|---|
| 1. Vocabulary (`M`-rows) | Types, enums, refinement aliases, signatures. Each modeling decision has an ID and a cited reason. | `type` declarations, refinement aliases, `def-shell` signatures with `?` bodies | The un-sourced header of `roots.llmll` (F-1) |
| 2. Clauses (`S`-rows) | One sentence per obligation, from a closed template set (below) | One `pre` or `post` clause, `:source "[S3] ..."` | Census, disposition and authoring (A-G, K) |
| 3. Examples (`E`-rows) | Input/output rows per function | `check` blocks (C5) and a static pinning check (below) | Vectored rows, width adaptation (F-1982-3) |
| 4. Decisions (`D`-rows) | Each ambiguity the author resolved, with the alternative rejected | `:source` text that names `[Dn]`; later a structured kind | The elicitation draft's "decision" kind; G2's misreading audit |
| 5. Exclusions (`X`-rows) | Each obligation deliberately not carried, with a barrier code `B1`-`B8` | The disposition ledger | Gate J's closed barrier list |
| 6. Core | The list of `S`-rows without which this is not the system | Gate J's core invariant | Stage F |

**Clause templates.** Each template has one fixed translation. The templates are chosen so that the
translation stays in `Σ_auto` whenever the terms do.

| Template | Translation | Note |
|---|---|---|
| `<f> REQUIRES <p>.` | `(pre p)` | |
| `<f> ENSURES <p>.` | `(post p)` | `p` may mention `result` |
| `WHEN <g>, <f> SHALL return <t>.` | `(post (=> g (= result t)))` | `=>`, not `if`: `if` in a contract is outside the fragment (`CONTRACT-IF-1`) |
| `OTHERWISE, <f> SHALL return <t>.` | `(post (=> (not (or g1 … gk)) (= result t)))` over the preceding WHEN guards | Closes the case set; this is the fix for F-4 |
| `<f> MAY return any <T> WHEN <g>.` | no clause; a recorded implementation freedom | Makes partiality explicit instead of silent |
| `IN <state> ON <event>, <f> SHALL go to <state'> [AND emit <out>].` | one row of a C1 totality post over the enum product | The table must be closed by OTHERWISE |
| `the length of result SHALL be <n>.` | `(post (= (string-length result) n))` or the `bytes[n]` return type | C3, measure class |
| free sentence | no automatic translation; tagged `informal` | Routed to SPEC-AGREE-1 / elicitation loop |

**Two static checks the sheet enables.** Both need no body and no agent.

1. **Closure lint.** A function whose `WHEN` set has no `OTHERWISE` and no `MAY` row is reported
   *partial*. Disjointness of the guards is a QF query; overlap with different results is a
   contradiction and is reported. This targets the `step-weak` shape, which today gets no flag.
2. **Example pinning.** For each example `E = (ā, o)`: (a) evaluate `pre(ā)` and `post(ā, o)` with
   the static evaluator; both must be `true`, else the example contradicts the spec. (b) Ask the
   solver `∃r. pre(ā) ∧ post(ā, r) ∧ r ≠ o`. If `sat`, the spec does not determine the result at
   that input, and the model `r` is the witness ("the spec also allows 1 here"). That is either a
   declared `MAY` freedom or a gap. Part (a) is ground evaluation. Part (b) is a quantifier-free
   query over one free constant at the return sort.

Check (b) is the most valuable piece. It turns examples, which every SOTA tool already collects, into
evidence about the *specification* and not only about the code. It also produces exactly the A/B
question the elicitation draft wants, with the solver as the only source of questions, which is the
condition under which the NeurIPS 2026 result does not apply.

**Worked example: RFC 1982 `serial-add` (§3.1).**

The RFC text is: "Serial numbers may be incremented by the addition of a positive integer n, where n
is from the range of integers [0 .. (2^(SERIAL_BITS - 1) - 1)]. ... s' = (s + n) modulo
(2 ^ SERIAL_BITS)". The clause sheet the developer writes:

```text
sheet serial-1982            source: RFC 1982 (pinned)
vocabulary
  M1  Serial = int where 0 <= v < 4294967296      -- RFC 1982 §2, SERIAL_BITS = 32 (DNS SOA)
  M2  Step   = int where 0 <= v <= 2147483647     -- RFC 1982 §3.1, n-range; other n undefined
function serial-add (s: Serial, n: Step) -> Serial
  S1  WHEN s + n < 4294967296, serial-add SHALL return s + n.             -- RFC 1982 §3.1
  S2  OTHERWISE, serial-add SHALL return s + n - 4294967296.                -- RFC 1982 §3.1, D1
examples
  E1  s = 4294967295, n = 1           -> 0                                  -- §5.2, D2
  E2  s = 0,          n = 2147483647  -> 2147483647
decisions
  D1  "modulo 2^SERIAL_BITS" is one conditional subtraction: s + n < 2^33 under M1 and M2.
  D2  §5 vectors stated at SERIAL_BITS = 8 are restated at 32 ("255 + 1 = 0" becomes E1).
exclusions
  (none)
core: S1, S2
```

The mechanical translation:

```lisp
(type Serial (where [v: int] (and (>= v 0) (< v 4294967296))))
(type Step   (where [v: int] (and (>= v 0) (<= v 2147483647))))

(def-shell serial-add [s: Serial n: Step] -> Serial
  (post (=> (< (+ s n) 4294967296) (= result (+ s n)))
    :source "[S1] RFC 1982 §3.1 - s' = s + n below the wrap")
  (post (=> (not (< (+ s n) 4294967296)) (= result (- (+ s n) 4294967296)))
    :source "[S2] RFC 1982 §3.1 [D1] - modulo as one conditional subtraction")
  ?serial-add)

(check "[E1] RFC 1982 §5.2 [D2] - (2^32 - 1) + 1 wraps to 0"
  (for-all [k: int] (= (serial-add 4294967295 1) 0)))
(check "[E2] largest step from 0"
  (for-all [k: int] (= (serial-add 0 2147483647) 2147483647)))
```

The ranges move from the `pre`/`post` of the shipped `examples/rfc1982_serial/serial.llmll` into the
refinement aliases `Serial` and `Step`. `augmentContractPre`/`augmentContractPost` fold them into the
effective contract, so the VC is the same. This also lets `M1` and `M2` carry their own provenance.

**What the pinning check does on the weak variant.** Suppose the author omits S2. The closure lint
reports `serial-add` partial: S1 has no OTHERWISE. Example pinning on E1 asks
`∃r. Serial(r) ∧ (4294967296 < 4294967296 ⟹ r = 4294967296) ∧ r ≠ 0`. That is `sat` with `r = 1`.
The report reads "E1: the spec also allows result = 1 at s = 4294967295, n = 1". That is the
`serial-add-bad` defect class, found before any body exists and without a mutant.

**What the developer authors, in summary.** A developer who shifts left writes five things: the
vocabulary with reasons, template sentences, examples, decisions and exclusions. The developer does
not write LLMLL. The developer does not write bodies. The developer answers solver-originated A/B
questions for `informal` sentences and for unpinned examples. An agent may draft any part, but the
sheet is the artifact the developer signs.

**Where the RFC goes.** The RFC is cited, in `source:` and in per-row comments. The G2 artifact audit
runs against the sheet's citations exactly as it runs against the census today. For a target with no
RFC (the common case for a product developer), the sheet is the whole specification.

### Part 4. The binding constraint

**Two different constraints bind two different quantities.**

- **The share of a target that can be `verified` is bound by the fragment.** ARP's `B5` rows, RFC
  4648's line wrapping and TOTP's HMAC stay out whatever the input format is. A clause sheet makes
  this visible earlier, because each template sentence is classified against `Σ_auto` at authoring
  time (an automated S0), but it cannot carry an obligation the fragment cannot state.
- **The share of `verified` code that means what was intended is bound by the input format.** F-1 to
  F-4 are all format losses. SPEC-AGREE-1 measured that the agreement instrument reaches 10.6% of
  rows, and that the whole gap is constructor terms in `Σ_subsume`. That is a *tooling* gap between
  `Σ_subsume` and `Σ_auto`, not a fragment limit. A template sentence needs no agreement instrument,
  because its translation is fixed. So the template dialect raises fidelity coverage on exactly the
  rows SPEC-AGREE-1 cannot compare.

**For the user's premise the input format binds first.** A developer who writes the spec chooses the
model. A developer who writes "decoded fields, not byte offsets" has made ARP's B5 decision
deliberately, and the sheet records it as `M`-row and `X`-row. The fragment then decides how much of
the *chosen* model verifies. On the in-repo evidence that is high for state machines and linear
arithmetic: TFTP and ARP wave 23/23 and 22/22 verified, RFC 1982 3/3.

**Language changes that follow.** In order of payoff per cost.

1. **None for version 1.** The clause sheet compiles to shipped surface: refinement aliases,
   `def-shell` with `?` bodies, multi-clause `pre`/`post` with `:source`, `check`. It is a front-end
   tool beside `scripts/rfc_coverage.py`, which already reads bracketed tags.
2. **Example pinning (new check, `[CT]`).** Part (a) reuses the static evaluator
   (`evalExprStaticWith`). Part (b) needs a `(get-model)`-bearing z3 query in the `Feasibility.hs`
   style. It is a one-contract query at a fixed input, so it is simpler than the two-contract
   difference query the professor asked for, and it can share that code. At constructor return sorts
   it needs the finite case split the witness-weight review recommends.
3. **Structured provenance (`[CT]`, schema change).** `:source` becomes optionally
   `{kind: sentence|decision|model|example|rfc, id, text}`. The trust report then computes the
   draft's fidelity axis (`sourced` / `elicited` / `inferred`) mechanically, and
   `--strict-verified-core` can refuse a core function with an `inferred` clause. This needs a
   JSON-AST minor version increase.
4. **SPEC-AGREE-1a, re-scoped (`[CT]`).** Still needed for `informal` sentences. Build order per the
   witness-weight review: difference query, then nullary enums, then payload sums by case split.
5. **Fragment work driven by `X`-row counts, not by targets.** BYTE-IO step 3 (unsized `bytes`,
   `bytes-slice` with a PROVE `pre`, the `bytes-length` guard) is the candidate for ARP's `B5`
   class, since `8 + 2*hln + pln` is linear with a ground constant multiplier. Whether it recovers
   those rows is a measurement for experiment-lead after step 3 ships. Do not claim it before then.
   Temporal (B3) and SMT strings (B2) stay refused.

Contract-position holes (elicitation draft §3) are **not** recommended for version 1. A template
sentence needs no hole. For an `informal` sentence, `checkout --multi` on a clause slot is a schema
and hole-flow change whose value depends on SPEC-AGREE-1a, which does not exist yet.

## Edge cases and degenerate inputs

1. **Overlapping WHEN guards with different results.** `WHEN x > 0, return 1. WHEN x > 5, return 2.`
   Expected: the closure lint reports a contradiction at `x = 6`, with the witness. Channel: contract
   (solver query on the effective post). Citation: closure lint, Part 3; the post is unsatisfiable at
   the overlap, which `Feasibility.hs` already detects as a no-miracle failure in `refine`.
2. **Positive witness for the pinning check.** The minimal firing input is the weak `serial-add`
   above: `def-shell serial-add`, post S1 only, example E1 `(4294967295, 1) -> 0`. Expected: `sat`,
   witness `result = 1`. Channel: contract. Citation: Part 3, worked example.
3. **An example at a constructor return sort.** `IN Closed ON Syn, step SHALL go to SynRcvd` with
   example `step(Closed, Syn) -> SynRcvd`. Expected: part (a) evaluates; part (b) needs the result
   ranged over constructors. Version 1 case-splits over the `k` nullary constructors. Channel:
   contract. Citation: `spec-agree-1-witness-weight-review.md` Recommendation; `baseSortText` in
   `Feasibility.hs` admits `Int`/`Bool` only today, so without the split this is "spec is silent
   (gap - flag)".
4. **A template sentence whose terms leave `Σ_auto`.** `WHEN n > 0, return (mod s n)`. Expected: the
   sheet compiles, the clause is classified `non_qf_lia` at authoring time, and the row is shown as
   contract-only before any body is written. Channel: trust (`asserted`). Citation: `LLMLL.md §5.3.3`
   four-item routing.
5. **A modeling decision that makes a clause vacuous.** `M3 HwAddr = int` and a sentence about address
   *length*. Expected: the sentence cannot be stated over `int` and must become an `X`-row under `B5`,
   naming M3. It may not be weakened to a statable vacuous surrogate. Channel: spec is silent
   (intentional), enforced by the playbook's B7 rule. Citation: `rfc-swarm-playbook.md` stage G.
6. **`MAY` freedom and pinning together.** `MAY return any Serial WHEN s = n` and an example at
   `s = n`. Expected: pinning `sat` is reported as declared freedom, not a gap. Channel: contract.
   Citation: Part 3 template table.

## Verification mapping

| Obligation | Channel | Fragment | Cite |
|---|---|---|---|
| Template clause, linear terms | contract | (a) QF-LIA, auto-discharged | `LLMLL.md §5.3.3`; `FixpointEmit.hs` |
| Template clause over enums/sums | contract | (a) datatype class of `Σ_auto` | `LLMLL.md §5.3.3` datatype class |
| Template clause with variable `/`, `mod`, `^` | trust | (c) `?proof-required`, `asserted` | `LLMLL.md §5.3.3` "Outside" |
| Closure lint: guard disjointness and coverage | contract (pre-body) | (a) QF-LIA, ground over parameters | same as body VC |
| Pinning (a): `pre(ā) ∧ post(ā, o)` | dynamic | ground evaluation, no solver | `Contracts.hs` `evalExprStaticWith` |
| Pinning (b): `∃r. pre(ā) ∧ post(ā,r) ∧ r ≠ o` | contract | (a) QF-LIA at Int/Bool; datatype by case split | `Feasibility.hs` query style |
| Examples as `check` | dynamic | `tested`, not `verified` | `LLMLL.md §5.1` |
| `informal` sentence agreement | contract | `Σ_subsume` today (10.6%) | `spec-agreement-proposal.md` §0 |

No obligation in this proposal escapes to Lean except template clauses whose own terms are nonlinear.

## Affected surface

- **New tool, no compiler change:** a clause-sheet compiler emitting `roots.llmll` (or JSON-AST),
  beside `scripts/rfc_coverage.py`. Experiment-lead or a driver phase owns it.
- **`compiler/src/LLMLL/Feasibility.hs`:** the pinning query (b) and its case split. Addition; it owes
  a soundness argument: `unsat` means the post determines the result at `ā`; `sat` is validated by
  exact evaluation of the model before it is reported, as the product-class `refuted` rule does.
- **`compiler/src/LLMLL/Syntax.hs`, `ParserJSON.hs`, `docs/llmll-ast.schema.json`:** structured
  `:source` kind (change 3). Schema minor version increase.
- **`compiler/src/LLMLL/TrustReport.hs`:** fidelity axis from the source kind.
- **`docs/design/spec-from-rfc-pipeline.md`, `rfc-swarm-playbook.md`:** stages A-G and K collapse to
  "author or draft the sheet, then audit it". Doc-lead slot after settlement.
- **`docs/design/spec-agreement-proposal.md`:** scope narrows to `informal` sentences.

## Risks and open questions

1. **Templates too narrow for real requirements.** Scope / verification-ergonomics. If most
   sentences fall to `informal`, the dialect gains nothing over SPEC-AGREE-1. Bite: complicates.
   Measure first: re-express the committed TFTP and ARP `Encoded` rows in the templates and count
   how many fit. This is homework for experiment-lead, not a question.
2. **Vocabulary is still where ambiguity hides.** Soundness of the claim, not of the system. The
   solver cannot compare two readings that disagree about types (the elicitation draft says the
   same). The sheet makes vocabulary decisions citable; it does not check them. Bite: bounds the
   fidelity claim; state it.
3. **Pinning over-reports on intended nondeterminism.** Verification-ergonomics. Every `sat` on a
   relational post without a `MAY` row becomes a question. Bite: only matters at scale; the `MAY`
   template is the release valve.
4. **Mechanical translation is not fidelity.** Soundness of the claim. A template fixes the formula
   for a sentence; it does not make the sentence right. The claim ceiling is "the contract says what
   the sheet says", plus examples pinned. Bite: blocks any wording that says "faithful to intent".
5. **Spec drift between the sheet and `roots.llmll`.** Spec-drift. If agents edit the generated
   contracts, the sheet becomes incorrect. Rule: generated root contracts are frozen (stage L
   already freezes `:source`-bearing roots); edits go through the sheet.
6. **Correlated LLM drafting of the sheet.** Scope. If an agent drafts the sheet from an RFC, F-3
   (exception attachment) moves into the sheet. G2's audit must run on the sheet's citations.

Open questions for the professor: omitted. The one candidate (is example pinning a known
construct?) is answered by literature the team can read itself: it is a ground instance of
functional-determinacy checking, close to Alloy's instance validation. It does not block the design.
