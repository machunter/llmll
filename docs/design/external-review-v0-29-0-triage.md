---
name: external-review-v0-29-0-triage
title: "Intake triage: five technical recommendations from an external v0.29.0 review"
status: "Rev 0, 2026-10-14. TRIAGE, NOT A PROPOSAL. Roadmap updated 2026-10-14: TRUST-REPORT-GATE-1 (G1, DECIDE) and HUB-CONTRACT-1 (parking lot) filed; B, C and A recorded as notes. No design is settled."
date: 2026-10-14
author: language-team
consumers: [user, professor, compiler-engineer, documentation-lead]
related: "shell-call-pre-1-proposal.md; driver-ll-campaign-close.md; leanstral-integration-scope.md; refine-reuse-gate-proposal.md; theory-questions.md Q-001"
---

# Intake triage: external v0.29.0 review

## Restatement

An external review of v0.29.0 makes five technical recommendations, A to E. The user receives the review as LLM-generated text. Its claims come mostly from `README.md`. This note decides, for each item, which of four outcomes applies: (1) a new design-queue item, (2) folded into an existing item, (3) already planned, or (4) declined. Each new item has a one-paragraph sketch. No item is a settled proposal.

## Summary

| Item | Recommendation | Already covered by | Recommended disposition | Priority |
|---|---|---|---|---|
| D | `verify --trust-report` reports a refuted function as `asserted` | README:142 caveat; a footer line in the report | **New G1 item.** Measured below. Exit status 0 is the defect, more than the label. | **High** |
| E | Hub query by contract subsumption | `RefineReuse.hs` (same-scope only); `hub query --signature` | **New item, low priority.** It depends on READ-SILENT-1 and on cross-scope symbol resolution. | Low |
| B | A fixed Lean prelude, plus a `lean-crux` gate of false theorems | `leanstral-integration-scope.md` Layer 1; LeanTranslate restricts to `int`/`bool` | **Fold the `lean-crux` gate into the LEAN-GA scope.** Decline the prelude for now. | Low (trigger-gated) |
| C | Z3 relational equivalence across verified fills | R5 stage 3, `DivergenceCheck.semanticEquivalenceStub` | **Already planned.** One new angle is recorded below. | No change |
| A | Ghost-state trace contracts for `def-shell` | SHELL-CALL-PRE-1 Part 2 (parked on yield); driver-ll campaign close §1 | **Decline as a queue item now.** File it as a theory question. Revisit after a yield count. | Deferred |

## D. `--trust-report` shows a refuted function as `asserted`, and exits 0

**Measurement (2026-10-14, installed binary `llmll 0.28.0`, repeated on a v0.29.0 build with the same result).** The fixture below has a body that does not meet its postcondition.

```
(def inc [x: int] -> int
  (pre (>= x 0))
  (post (> result x))
  x)
```

- `llmll verify bad.llmll` prints `body verification of 'inc' failed` and exits **1**.
- `llmll verify bad.llmll --trust-report` prints `inc: pre: asserted | post: asserted` and exits **0**.
- The second command prints this footer: `sidecar-only report: evidence is read from .verified.json and was NOT validated against a run of the VC emitter; use --strict-verify for that`.

The v0.29.0 build gives the same exit statuses (1, 0) and the same output. `--strict-verify` exits 1.

**What the review got right, and what it missed.** The review says that the label hides `refuted`. That is true. But the report already discloses its own mode in a footer, so the label alone is a disclosure-strength issue. The larger defect is the exit status. A script that uses `verify --trust-report` as a gate passes on a disproved function. The tree has such callers: `scripts/benchmark-totp.sh` and `scripts/benchmark-erc20.sh` (`verify --trust-report --json`), and the driver's stage L in `tools/llmll-driver/spine.llmll`. Each caller must be audited to see whether it reads the exit status or only the JSON.

**Sketch.** The flag name `verify --trust-report` tells the reader that `verify` runs. The design must make the command do what its name says, or rename the mode. There are two candidates:

1. **Run, then report.** `verify --trust-report` runs liquid-fixpoint, writes the sidecars, and then renders. `refuted` then appears, and the exit status follows the solver verdict. A new `llmll trust-report <file>` subcommand (or `--cached`) keeps the render-only path, under a name that does not say `verify`.
2. **Keep render-only, and strengthen the disclosure.** Each entry gets a third state, `unchecked (sidecar-only)`, in place of `asserted`. The command exits non-zero when it cannot read a positive tier for a function that has a body VC.

**Recommendation: candidate 1.** A command named `verify` that does not verify will mislead an agent. Agents do not read footers. Candidate 2 keeps the trap and only labels it. The cost of candidate 1 is time: the render-only path exists because it is fast, and some pytest suites depend on it (for example `scripts/tests/test_sidecar_admit_1.py`). The engineer must count those dependents first. The fix carries no proof obligation: it changes reporting and exit status only.

**Edge cases.**
1. A function with no body VC (a `def-shell`, or a body that falls back). Under candidate 1 it stays `asserted`, and the exit status does not change. Channel: trust.
2. A function that is refuted in an imported module. The importer's report must not render it as `asserted` either. Run-then-report reads the import's sidecar, and `refuted` is never persisted (`TrustReport.hs`, the `refuted` axis comment). This is a real gap. The importer's view of a refuted callee needs its own decision. Channel: trust, spec is silent (gap, flag).
3. Positive witness: the `inc` fixture above. Under candidate 1, the command must print `refuted` and exit 1.
4. A sidecar that is newer than the source but was written by an older compiler. The existing SIDECAR-ADMIT-1 guard covers it. Channel: trust.

## E. Hub query by contract subsumption

**What exists.** `RefineReuse.reuseRetrieval` tests contract subtyping (`pre_s ⟹ pre_D` and `post_D ⟹ post_s`). It emits two Horn constraints to liquid-fixpoint. It has one stated limit: candidates are **same-scope** defs, "so free symbols resolve in the common scope". `HubQuery.queryBySignature` matches structurally on types only, by a brute-force scan of the hub directory (~/.llmll/modules).

**Sketch.** `llmll hub query --contract <hole-pointer>` takes the hole's `contract_pre` and `postcondition_goal` from `checkout`. It filters hub exports by signature first, which is cheap. It then runs the RefineReuse subsumption pair on each survivor. The new design work is in free symbols. A hub contract can name the hub module's own helpers, measures or constructors, and these do not resolve in the hole's scope. The rule must be: a candidate whose contract names a symbol that does not resolve in the query scope is **not a match** and is listed as `unresolved`, never silently dropped. Both obligations are QF-LIA when both contracts are in the fragment. A contract outside the fragment gives `unknown`, not `no match`.

**Prerequisite.** READ-SILENT-1 is open. `HubQuery.hs` reports a failed read as an empty success. A contract query on top of it would report "no subsuming function" when it could not read the hub. That row must close first.

**Priority: low.** There is no measured demand. The hub has no registry, and no experiment has asked for cross-module reuse.

## B. Lean trusted base: a prelude and a `lean-crux` gate

**What exists.** `LeanTranslate.hs` translates only `int` and `bool`, and rejects division and modulo. Floor-versus-truncation is named as production work. `leanstral-integration-scope.md` records the floor/truncation mismatch as a verified faithfulness risk. Its Layer 1 already moves translation from the contract to the obligation, with the body bound to `result`. LEAN-GA is trigger-gated.

**The prelude: decline for now.** A prelude (`Llmll.Semantics`) earns its cost when the translation covers maps, `bytes[n]`, ADTs and `Result`. Today the translation covers two types and refuses the rest. A prelude for types it refuses would be unused text. The idea is sound for the LEAN-GA rebuild. Record it in `leanstral-integration-scope.md` as a Layer 1 option, not as a separate row.

**The `lean-crux` gate: fold into LEAN-GA, and consider it earlier.** A frozen set of **false** nonlinear obligations tests that the translation does not produce a provable theorem from a false contract. That is the same discipline `refute-crux` applies to the SMT path. The gate does not need a live Leanstral. It needs only the translation and a Lean kernel check that the statement is **not** provable by `decide`/`omega`/`nlinarith`, with a stated budget. A smaller version can ship before LEAN-GA: it checks that each emitted theorem keeps its hypotheses (no hypothesis is dropped, and `h_pre` is not `True`). That is a syntactic check on `translateObligation` output. Fragment: the gate itself proves nothing, so it introduces no obligation.

## C. Relational equivalence across verified fills

**Already planned.** This is R5 stage 3. `DivergenceCheck.hs` states that stage 3 "needs a net-new relational-VC path that is being planned separately". `semanticEquivalenceStub` returns `Nothing`. Stages 1 and 2 already witness under-constraint over a finite probe set Ω.

**One new angle.** Stage 2 finds a witness only inside Ω. A relational VC can also give a witness outside Ω, and that witness is the review's "underspecification witness". The stage 3 design should state that a SAT relational query yields a **concrete input**, and that this input is added to Ω for later replay. That keeps the stage-2 witness format as the only format. Fragment: the relational obligation `pre(x) ⟹ f_i(x) = f_j(x)` is QF-LIA only when both bodies are body-faithful in the fragment. A fill that falls back is excluded, as stage 1 already excludes it. No other change.

## A. Ghost-state trace contracts for `def-shell`

**What exists, and what it says.** `driver-ll-campaign-close.md` §1 states that the 91% unproved share is "the result rather than a shortfall". Orchestration is effects. The transferable claim is "a proved centre with an unproved shell around it". The token module already proves a per-phase lifecycle property, and theory question Q-001 records the open gap: no formal step relation exists for the sequencer.

The closest shipped work is SHELL-CALL-PRE-1. Its Part 2 emits call-site `pre` obligations inside bodies that fall back. It was **parked on yield**: stage A decided 0 of 16 call sites in `tools/`. A ghost-state ordering check is a stronger version of the same idea. It would face the same yield problem first.

**Sketch, for the record only.** A `def-shell` declares a ghost parameter of an enum type, for example `(ghost phase : Phase)`, and a contract over it: `(pre (= phase Locked))`, `(post (= phase' Released))`. Each `do` step threads the ghost value. The checker then proves that each call's ghost `pre` follows from the previous step's ghost `post`. This is QF-LIA over enum tags. It preserves strict immutability because the ghost value is threaded, not stored. It is the "linear-style threading" pattern. The hard part is not the logic. The hard part is that a shell body falls back today, so no body VC exists to carry the thread. That is exactly the SHELL-CALL-PRE-1 Part 2 obstacle.

**Recommendation: decline as a queue item now.** The precondition is a count. Before any design, measure how many `def-shell` bodies in `tools/llmll-driver/` sequence two or more calls whose order matters. If the count is near zero, as Part 2's count was, the feature has no customer. Record the refinement-mapping question in `theory-questions.md` beside Q-001. Q-001 already covers it, so no new `Q-NNN` is written by this note.

## Risks and open questions

1. **D may have more callers that depend on the exit status than the three named here.** Class: soundness of gates. The engineer must grep every caller of `--trust-report` before choosing candidate 1. Effect: it complicates D, and does not block it.
2. **D, edge case 2 (an importer of a refuted callee) is a spec gap.** Class: spec-drift. `LLMLL.md` describes `refuted` as verify-time-only and not persisted. A cross-module report cannot show it. Effect: it needs a decision before D settles.
3. **E's free-symbol rule may reject most real hub candidates.** Class: verification-ergonomics. No hub corpus exists to measure. Effect: it matters only at scale.

## Hand-off

The user decides each item. The suggested next steps:

- **D:** a language-team proposal (Rev 0), then compiler-engineer. Filed as `TRUST-REPORT-GATE-1` (G1, DECIDE) on 2026-10-14.
- **E:** filed as `HUB-CONTRACT-1` in the Trigger-gated Parking Lot on 2026-10-14, triggered by READ-SILENT-1. No proposal yet.
- **B:** recorded on the LEAN-GA parking-lot row on 2026-10-14. `leanstral-integration-scope.md` can carry the same two notes when LEAN-GA is next revised.
- **C:** add the "witness outside Ω joins Ω" note to the R5 stage 3 plan when that plan is written.
- **A:** no action. Optionally, experiment-lead counts the order-sensitive shell bodies.
