# Pre-registration: RFC 826 wave (Stage I)

**Written before Stage J (the gate), before Stage K (contract authoring), before Stage L (freeze),
and before any wave agent runs.** Nothing below is fitted to a result, because no result exists yet:
there is no `roots.llmll`, no hole, no fill, and no kill matrix.

**The rule that governs this document.** The pre-registered text is never edited. Outcomes are
recorded in Appendix A. If an instrument registered here turns out to be defective, the defect is
written into Appendix B as an amendment that states the defect, shows the argument, and names the
adjudication asked of a human. It is not reinterpreted in place, and it is not ignored.

**No ratio ceiling.** On the previous run of this pipeline a pre-registered exclusion-ratio ceiling
fired and the instrument was the thing that was wrong: every clause in the timing/transport class is
excluded by the definition of that class, so the threshold was breached by class assignment before
any scoping judgment had been made. It was retired by written amendment. No exclusion ratio, no
coverage percentage over a raw denominator, and no "rows carried / rows found" figure appears
anywhere in this pre-registration or in any artifact downstream of it. Rubric §7.2 already forbids
it; this document does not reintroduce it under a new name.

---

## 0. The instrument, pinned

| Item | Value |
|---|---|
| Source bytes | `00-source/rfc826.txt`, sha256 `01bc62fe6a37e90f1246ac43e8e145f1322b4ed1474836145c3da93d2bd3c8a6`, 470 lines |
| Toolchain | `llmll 0.14.67` |
| Driver | `scripts/rfc_to_implementation.py`, sha256 `f45102b96cd83b18c27df35c0050234a2f0d5f717c881211d9c459d309f3b97c` |
| Scope decision | `01-scope/scope.md`, frozen at Stage B, 15 obligations (C1..C12, R1..R3) |
| Rubric | `02-rubric/rubric.md`, 10 stratification classes, closed barrier list B1..B8 |
| Inventory | `06-disposition/inventory-dispositioned.json`, 91 rows: 39 Encoded, 3 Deployment-modeled, 1 Vectored, 48 Dispositioned out |
| Characteristic core | 19 rows: A25, A26, A30, A36, A37, A38, A39, A42, A46, A53, A55, A57, A58, A59, A60, A61, A62, A64, A65 |
| Feasibility | `07-feasibility/feasibility.json`, 6 probe/mutant pairs over 5 probe programs: every probe SAFE and body-faithful, every mutant refuted |

**Naming collision, resolved once.** Stage B's obligations are named C1..C12. Stage G's clause
classes are also named C1..C6. They are different things and they appear in the same sentences
below. In this document and in every artifact that cites it:

- an **obligation** is written `C1`..`C12`, `R1`..`R3` (Stage B §1);
- a **clause class** is written `CC1`..`CC6`, aliasing Stage G's `C1`..`C6` exactly:

| Alias | Stage G label | Covers | Rows | Encoded |
|---|---|---|---|---|
| CC1 | C1 | state transition | 37 | 31 |
| CC2 | C2 | arithmetic invariant | 3 | 0 |
| CC3 | C3 | length or format | 36 | 8 |
| CC4 | C4 | opaque primitive | 0 | 0 |
| CC5 | C5 | test vector | 1 | 0 (1 Vectored) |
| CC6 | C6 | timing / liveness / transport / trace-level | 14 | 0 |

The alias is presentational. The inventory file keeps its `class` field unchanged, and no artifact
rewrites it.

---

## 1. Acceptance criteria

### 1.1 A successful fill

A fill of one hole is **accepted** when every condition holds. F1 to F3 are the driver's per-fill
bar. F4 to F8 are conditions the driver does not check and that the operator checks mechanically at
wave end from the recorded artifacts.

| | Condition | Checked by | Evidence |
|---|---|---|---|
| F1 | `llmll verify` on the tree does not refute the filled function, and the module reports SAFE | driver `_verify_fn` | `12-wave/wave.json` `status: filled` |
| F2 | the filled function appears in the `body-faithful:` list, not `body-fallback:` | driver `_verify_fn` | same |
| F3 | the body arrived through `llmll patch` under a token issued for that pointer | driver `_apply` | `agent-NN-*/patch-request.json` |
| F4 | the function is not flagged `termination_unverified` | operator | whole-tree `verify --trust-report --json` and `--weakness-check`, captured at wave end |
| F5 | no `:source`-bearing clause changed during the wave | operator | byte-compare of the frozen clause surface (Stage L) against the post-wave tree |
| F6 | the accepted body contains no arithmetic and no order: no `+`, `-`, `*`, `<`, `>`, `<=`, `>=` over any field-value sort, and no computed map key | operator | AST scan of the accepted body |
| F7 | the agent directory contains nothing outside the provisioned set | operator | directory listing per agent |
| F8 | if the fill spawned sub-contracts via `refine`, every spawned sub-hole is itself filled and body-faithful at wave end, and no spawned contract carries `:source` | operator | whole-tree trust report |

**F4 is not redundant.** The Stage M fill prompt states three acceptance conditions to the agent,
but the driver's `_verify_fn` evaluates only two of them (`SAFE`, `body-faithful`, plus
not-refuted). Nothing in the pipeline tests `termination_unverified`. A fill that the driver accepts
while carrying that flag is booked as **accepted below the stated bar** and counted in its own
column (M3d), not silently merged with clean fills.

**F6 is the fragment tripwire.** Stage B §3 records that RFC 826 defines no order, no timestamp, no
sequence number, and no arithmetic on any field value, and rules (MD6) that supersession is a
function update rather than a maximum over a time domain. A body that reaches for arithmetic has
imported structure the source does not contain. Such a body may still verify; if it does, it is
accepted by the tool and **reported as a fragment breach**, which is a finding under §6.

**Provisioned set for F7.** `PROMPT.md`, `BRIEF.json`, `scratch.llmll` and its `.verified.json`
sidecar, `LLMLL.md`, `llmll-ast.schema.json`, `body.json`, `patch-request.json`, `checkout.err`,
`agent.stdout.log`, `agent.stderr.log`, and any scratch file the agent wrote inside its own
directory. Anything else, in particular the live tree `12-wave/roots.ast.json`, another agent's
`body.json`, or any file from `07-feasibility/` (which holds working implementations of functions
the wave is meant to invent), is a **blindness breach**: that fill is reported as breached and is
excluded from every fill statistic while remaining in the denominator.

### 1.2 A successful run

Two levels, because they answer different questions. **Validity** decides whether any number may be
reported at all. **Success** decides whether the run delivered what it was run for.

**Validity (V).** All of these, or the run is reported as invalid and its fill statistics are not
reported:

- **V1** Stage L froze the clause surface and RFC-COV-1 passed at freeze strength.
- **V2** The frozen clause surface is byte-identical before and after the wave (F5 across all holes).
- **V3** Every hole has a terminal status drawn from the closed vocabulary in §2 M3, and the count
  of unclassified statuses is zero.
- **V4** Every `checkout-failed` status has been classified by the discriminator in §4.3 into
  contention, lock retention, or stale lock file, with the naming artifact recorded.
- **V5** The whole-tree `--strict-verified-core` verdict is recorded verbatim, whatever it is.
- **V6** No forbidden intervention occurred (§3.5).

**Success (S).** Validity, plus:

- **S1** Every one of the 15 frozen obligations carries a verdict from the vocabulary in §6, with a
  named evidence artifact or a named reason for its absence.
- **S2** R1, R2 and R3 each have an exhibited witness artifact. A refutation target with no witness
  is not discharged, however plausible the argument, per Stage B §8.5.
- **S3** Every mutant and good twin registered in §5 was executed, and the full matrix including
  survivors is reported. A taxonomy entry that could not be written in the fragment is recorded as
  `unwritable` with its reason; it is not removed.
- **S4** The cross-function agreement review of §1.3 was performed and its verdict recorded.
- **S5** Detection yield is reported with witnesses, itemised by locus.

**Success is not conditioned on the size of the detection yield, and zero is a permitted successful
outcome.** A success criterion that requires finding defects rewards manufacturing them. It is also
not conditioned on the fill rate: a hole that cannot be filled within its budget is a finding routed
to the compiler team or back to the inventory, which is a product of this pipeline rather than a
failure of it.

### 1.3 The standing review obligation the toolchain cannot discharge

Stage H established (FINDINGS §3) that a user-defined callee inside a `pre` or `post` clause forces
body-fallback, so a cross-function joint invariant cannot be written by calling the other function
from a contract. The emission gate therefore appears as an inline predicate inside more than one
contract, and **nothing in the toolchain checks that the copies agree**.

Registered as an acceptance condition (S4): after the wave, the copies of any duplicated gate
predicate are compared textually, the comparison is recorded in Appendix A.6 as the literal
predicate text from each site, and a verdict of `agree` or `disagree` is written. A disagreement is a
finding of exactly the kind this pipeline exists to surface. Skipping the review fails S4.

### 1.4 What is not an acceptance criterion

- **Agreement between the two Stage D extractors.** Stage E measured raw agreement 0.8462 and
  Cohen's kappa 0.824. That is a process fact about extraction and it enters no acceptance test and
  no results table. Two formalisations agreeing entails nothing, since both can be wrong the same
  way, and shared training makes that likely.
- **Absence of failure.** "No mutant survived", "no contradiction found", and "the tree verified"
  are not results on their own. Each is reported only alongside what it eliminates.
- **The fill rate.** `filled / holes` is recorded (M3) because the ledger must add up, and it is
  never presented as a quality score.
- **Any metric that rises when a contract weakens.** If a proposed number would go up by deleting a
  conjunct from a postcondition, it is not reported.

---

## 2. The measurement set

Every number the run will report, its denominator, and the artifact it comes from. A number not on
this list is not reported. A number on this list is reported even when it is unflattering.

| ID | Number | Denominator | Source |
|---|---|---|---|
| M1 | Obligation ledger: verdict per obligation | **15**, frozen at Stage B (C1..C12, R1..R3) | §6 booking rules, Appendix A.2 |
| M2 | Hole count `H` | none (H is itself the figure) | `_ast_holes` on the first Stage M invocation, recorded in Appendix A.1 **before any agent runs** |
| M3 | Fill outcomes: (a) filled, (b) semantic finding, (c) protocol event, (d) accepted below the stated bar, (e) blindness breach, (f) unclassified | **H** | `12-wave/wave.json` plus the §4.3 classification |
| M4 | Semantic attempts per hole, 1..3 | per hole | `wave.json` `attempts`, cross-checked against `fill-<hole>#<n>` lines in the run log |
| M5 | Protocol events: (a) stale-CAS retries inside `_apply`, (b) checkout failures by cause, (c) submissions that exhausted the 5-retry protocol budget | per submission (a, c); **H** (b) | run log, `patch-request.json`, `checkout.err` |
| M6 | Kill matrix: killed / survived / unwritable, per entry | **15 mutants**, reported separately from **5 good twins** (§5) | `13-kill-matrix/kill-matrix.json` |
| M7 | **Detection yield**: defects found, each with a concrete witness, itemised by locus (contract, fill, driver or compiler, RFC claim) | **none. Yield is a count, never a rate** | Appendix A.5 |
| M8 | Class-stratified carriage from the gate: carried / total within CC1+CC2+CC3 | as computed by Stage J | `09-gate/gate.json`, reported, not thresholded |
| M9 | Human interventions after freeze, by class | **none** (a log, not a rate) | Appendix A.4 |
| M10 | Cost: wall clock per stage, agent invocations in the wave | none | `MANIFEST.json`, run log |

**M4 and M5 are never summed and never displayed in the same column.** That separation is the whole
point of §3: contention must not be able to consume an agent's error budget, and a report that adds
the two hides exactly the confusion the separation exists to prevent.

**M6 reporting rule.** "14 of 14 killed" is not reportable on its own. The matrix is reported entry
by entry with the survivors named, and every kill is stated as what it eliminates: a killed mutant
proves the contract excludes one specific behaviour. It is eliminative evidence. It does not
corroborate that the contract says what the RFC says, because one side of that question is English
prose and has no formal answer.

**Witness artifacts, not numbers.** R1, R2 and R3 are discharged by exhibited traces. Each is
recorded in Appendix A.3 as a file path plus the transition it exhibits plus the assumption set it
runs under (Stage B §7). "We could not prove it" is not a witness.

**Numbers forbidden by name:** exclusion ratio; coverage percentage over the raw 91-row denominator;
extractor concordance presented as evidence of correctness; any aggregate kill score without the
survivor list; any figure over a denominator chosen after the outcomes were seen.

---

## 3. Process budgets

### 3.1 Semantic retries

**Three per hole** (`--semantic-retries 3`, the driver default). A retry re-invokes the fill agent
with the compiler's error text and nothing else added. No hint, no reference solution, no sibling's
body, no relaxation of the contract. A hole that exhausts the semantic budget is a **finding**,
routed to the compiler team or back to the inventory as a scoping error, and it is never an occasion
for a hint.

### 3.2 Protocol retries

**Five per submission** (`--protocol-retries 5`, the driver default), counted in a separate column
from M4. A protocol retry involves **no agent call**: the same body is re-applied against a fresh
checkout after a stale-context rejection. The compare-and-swap is per file, not per hole, so the
first patch to land invalidates every outstanding brief on the tree however unrelated the holes are.
Reproduced while writing this document:

```
$ llmll checkout roots.ast.json /statements/6/body    -> token A
$ llmll checkout roots.ast.json /statements/22/body   -> token B
$ llmll patch roots.ast.json p6.json                  -> {"result":"PatchSuccess","statements":28}
$ llmll patch roots.ast.json p22.json                 -> {"result":"PatchAuthError",
                                                          "message":"obligation context is stale
                                                           ... re-checkout required
                                                           (source file changed)"}
```

A submission that exhausts all five protocol retries is reported as **lost work**, never as a
semantic failure of the agent, and it fires trigger T5 in §4.

### 3.3 A defect in the retry instrument, recorded before the run rather than after

The two budgets are separated in the driver's design and are **not** separated in its behaviour, for
a reason that is mechanical and reproducible. Measured with `llmll 0.14.67`:

| Patch outcome | Lock after the call | Evidence |
|---|---|---|
| `PatchSuccess` | released | `checkout --status <token>` returns `token not found (may have expired)` |
| `PatchVerifyError` | **retained** | `checkout --status <token>` returns `{"remaining_ttl":3600}`; re-checkout of the same pointer returns `hole at /statements/N/body is already checked out` |
| `PatchAuthError` (stale) | **retained** | re-checkout of the same pointer fails identically |

The driver releases the token it holds at the top of each protocol retry, so the stale path is
handled. The `PatchVerifyError` path is not: `_apply` returns `(False, err)` with the fresh token
still held, the fill loop continues to its next semantic attempt, `_checkout` on the same pointer
fails, and the hole terminates with `status: "checkout-failed"` before any agent is invoked.

**Consequence, stated in advance.** For a hole whose body is rejected by `patch`'s own verifier, the
effective semantic budget is **1, not 3**, and the loss is recorded under a status that reads like
contention. This is not a prediction about RFC 826: it is what the previous run of this pipeline
already did. In `tftp-wave`, 23 holes at 6 concurrent agents produced 9 accepted on attempt 1 and 14
`checkout-failed`, with no `#2` agent invocation anywhere in the run log, and the summary line
printed all 14 as `FINDINGS (exhausted budget; routed, never hinted)` when no budget had been spent.

**Registered handling. The operator chooses one branch before the wave starts and records the choice
in Appendix A.1 with the driver's sha256.**

- **Branch AS-IS.** Run the driver unchanged. Then the pre-registered semantic budget is **1
  effective attempt** for any hole rejected at patch time, every `checkout-failed` is presumed a
  lock-retention artifact unless §4.3 classifies it otherwise, and **no `checkout-failed` hole may be
  booked as a semantic finding** without the forensic re-derivation of §3.4.
- **Branch FIXED.** Release the fresh token on the `PatchVerifyError` path before the wave starts.
  Then the budget is 3 as registered in §3.1. The change is to the harness only: it touches no
  contract, no brief, no body, and no taxonomy. The modified driver's sha256 is recorded in Appendix
  A.1 and **no further driver change is permitted once the wave has started**; a driver change
  mid-run ends the run, which is then reported as ended, and any continuation is a new run with its
  own pre-registration reference.

Both branches are pre-registered so that neither is chosen after seeing which produces the better
number.

### 3.4 Forensic re-derivation (no agent, no hint)

`wave.json` records `last_error` only for holes that terminate as `finding`; a `checkout-failed`
hole loses its compiler diagnostic. To recover it: copy the frozen tree and the hole's recorded
`patch-request.json` into a scratch directory, re-run `llmll patch`, and record the diagnostic. This
is deterministic, involves no agent call and no contract change, and is the only permitted route
from a `checkout-failed` status to a semantic verdict.

### 3.5 Human interventions after freeze

The clause surface freezes at Stage L. From that moment:

| Class | Permitted | Budget | Recorded |
|---|---|---|---|
| P1 | Pre-wave preflight of Appendix C, executed before the first agent runs | 1 execution | A.1 |
| P2 | Restart of a stage that failed for an environmental reason (network, disk, process kill), with no artifact edited | 2 | A.4 |
| P3 | One serialised re-run under §4.4 | 1 | A.4 |
| P4 | Writing amendments and appendices | unlimited | B |
| X | Editing a contract, a brief, a body, the taxonomy, the obligation list, or any denominator | **0** | run is invalid (V6) |
| X | Giving a fill agent a hint, a reference solution, or a sibling's body | **0** | run is invalid (V6) |
| X | Deleting or editing the lock file while the wave is running | **0** | run is invalid (V6) |

Each P2, P3 and P4 entry records timestamp, actor, exact command, and reason. Removing a **stale**
lock file during the preflight, before any agent runs, is part of P1 and does not count against P2.

---

## 4. The numeric concurrency trigger

### 4.1 How many agents

**Four** (`--wave-agents 4`, the driver default). Recorded now so it cannot be tuned to the outcome.
Four exercises the per-file compare-and-swap (any N greater than 1 does) and is the configuration
the driver ships. The comparison point is the previous run at N=6 over 23 holes.

`H`, the number of holes, is not known at registration: Stage K has not authored `roots.llmll`. `H`
is whatever `_ast_holes` returns on the first Stage M invocation and is written into Appendix A.1
before any agent runs. A re-run with a different `H` is a different run and is reported separately.

### 4.2 Conflict events, defined

| Event | Definition | Witness |
|---|---|---|
| **E1 stale CAS** | `llmll patch` returns `PatchAuthError` because another fill landed first | run log, retried inside `_apply` |
| **E2 checkout failure** | `llmll checkout POINTER` returns no brief | `agent-NN-*/checkout.err`, `wave.json` `status: checkout-failed` |
| **E3 budget exhaustion** | five consecutive `PatchAuthError` on one submission | `wave.json`, run log |

### 4.3 Classifying E2, which is mandatory before any booking (V4)

`checkout-failed` has three causes and they mean different things. The discriminator uses artifacts
the driver already writes:

| Cause | Discriminator | Reading |
|---|---|---|
| **Lock retention** (§3.3) | `patch-request.json` exists in that agent's directory, so a prior attempt reached submission | Self-inflicted, independent of N. Not contention, and not evidence about the agent's competence. Route through §3.4 before saying anything semantic. |
| **True contention** | no `patch-request.json` and no `body.json`, and the pointer was never submitted by this run | N-dependent. This is what the trigger below is about. |
| **Stale lock file** | `12-wave/roots.llmll-lock.json` predates the wave | Preflight failure (Appendix C, C3). Invalidates the concurrency measurement for every affected hole. |

The lock file deserves its own line because it is easy to miss: for a tree named `roots.ast.json`
the lock is written as **`roots.llmll-lock.json`**, it survives deletion of `roots.ast.json*`, and it
persists across processes. A leftover lock from an earlier partial run poisons every checkout on a
previously locked pointer.

### 4.4 The triggers, in numbers fixed now

Let `conflict_rate = (E2 events classified as true contention) / H`.

| ID | Condition | Consequence |
|---|---|---|
| **T1** | zero E1 events across the whole wave | The per-file CAS was never exercised. Register that fact in the report and make **no claim** that concurrent filling is safe under this driver. |
| **T2** | `conflict_rate >= 0.20` | **Finding.** Reported with witness (`checkout.err` text, the two competing pointers, the timestamps), against the coordination protocol, not against any agent. |
| **T3** | `conflict_rate >= 0.50` | The wave's semantic statistics (M3a, M3b, M4) are **not reported as semantic results**. Only the protocol finding is reported, and the serialised re-run below is mandatory before any obligation is booked. |
| **T4** | any single hole with 2 or more E2 events | **Finding**, reported per hole with its cause classification. |
| **T5** | any E3 event | **Finding.** That submission is reported as lost work. The hole is never booked as a semantic failure on the strength of it. |
| **T6** | any E2 classified as lock retention | **Finding** against the driver, reported with the count, regardless of the branch chosen in §3.3. Expected to be non-zero on Branch AS-IS; recording it is what keeps the AS-IS numbers readable. |

**The serialised re-run (P3).** Permitted once, only when T3 fires or when T6 accounts for holes that
never consumed a semantic attempt. Conditions, all of them:

1. `--wave-agents 1`, same driver, same tree, same contracts, same briefs.
2. Only holes that are not already `filled` are re-run.
3. **The semantic budget carries over.** Total agent invocations per hole across both runs is at most
   3, counted from `fill-<hole>#<n>` lines in both run logs. The re-run is a way to spend a budget
   that contention or lock retention prevented spending, not a second budget.
4. Both runs are reported. The first run's numbers are not replaced by the second run's.
5. At N=1, true contention is 0 by construction. If E2 events persist at N=1, the cause is not
   contention and must be reported as such.

---

## 5. The mutant-class taxonomy

### 5.1 What a mutant is here

One change, in one function body, expressing one specific wrong behaviour that a named row forbids.
A mutation that lands on a comment or a type declaration is a broken instrument, not a weak contract,
so every mutant is checked for having actually changed the body it names. A behaviour the RFC permits
is a **good twin** and must survive; classifying one as a mutant would claim RFC 826 forbids
something it allows.

The taxonomy is **closed at the names below**. Stage N may not add entries, rename them, or drop
them. An entry that cannot be written inside the fragment is recorded as `unwritable` with the
reason and stays in the denominator.

### 5.2 Mutation operators, per clause class

| Class | Operators | Rationale |
|---|---|---|
| **CC1** state transition (31 Encoded rows) | O1 guard-drop, O2 guard-invert, O3 order-swap, O4 update-suppress, O5 branch-substitute, O6 field-substitute, O7 delivery-scope-flip, O8 discard-suppress, O9 irrelevant-field-sensitivity | This is where the protocol lives: the reception algorithm at 197-234 and generation at 176-190 |
| **CC2** arithmetic invariant (0 Encoded) | **none** | All 3 rows dispositioned out. Stage B §3 puts no arithmetic in the signature, and the only place arithmetic would be needed is offset computation, which is X1 |
| **CC3** length or format (8 Encoded) | O10 constant-substitute, O11 constant-swap, O12 field-preservation-drop | Value level only. Byte-level parse is X1, byte order is X2, and the optional length checks against actual byte counts are X3 |
| **CC4** opaque primitive (0 rows) | **none** | RFC 826 has no checksum, no transform, no keyed operation. The empty class is reported as empty, which is itself a fact about the document |
| **CC5** test vector (1 row, A90) | O13 vector-field-perturbation | The worked example at 382-401 gives concrete field values; the vector is a comparison against those values |
| **CC6** timing / liveness / transport / trace (0 Encoded) | **none** | All 14 rows dispositioned out under B1, B2, B3. Aging, timeouts, daemon probing and retransmission are X5, and RFC 826 puts them outside its own scope at line 416 |

**Tripwires for the empty classes.** If any registered mutant is killed by reasoning that needs
arithmetic, an order, a retransmission, a timer, or a trace, the contract has imported structure the
scope excluded. That kill is not counted as a kill: it is reported as a **scoping finding** under §6.

### 5.3 The mutant register (15 kill-required entries)

`targets` are inventory row ids. `probes` names the Stage B obligation the entry exercises.
Every entry is expected to be **refuted**.

| # | `name` | Class | Targets | Probes | The one change |
|---|---|---|---|---|---|
| 1 | `promiscuous-cache` | CC1 O1 | A55, A57 | C2 | Adds the `<protocol type, sender protocol address, sender hardware address>` triplet without testing whether the receiver owns `ar$tpa` |
| 2 | `merge-after-opcode` | CC1 O3 | A64, A53 | C1 | Performs the merge of the sender triplet only after the target test and the opcode test, so a station never updates an existing entry from a packet not addressed to it |
| 3 | `old-address-wins` | CC1 O4 | A65, A53 | C1 | An existing entry keeps its stored hardware address instead of being superseded by `ar$sha` |
| 4 | `reply-to-reply` | CC1 O1 | A58, A77 | C3 | Emits a reply without testing `ar$op = ares_op$REQUEST`, so a received REPLY provokes a packet |
| 5 | `reply-ignores-tpa` | CC1 O1 | A81, A55, A57 | C2, R3 | Processing a REPLY takes the add branch without the `ar$tpa` ownership test |
| 6 | `unicast-request` | CC1 O7 | A42 | C8 | A generated request is sent to a single hardware address instead of broadcast |
| 7 | `reply-broadcast` | CC1 O7 | A62, A88 | C5 | The reply is broadcast instead of being sent to the hardware address now held in the target hardware address field |
| 8 | `reply-fields-swapped` | CC1 O6 | A59, A60 | C4 | The reply keeps the requester's addresses in the sender fields, so it carries no mapping for the replying station |
| 9 | `discard-suppressed` | CC1 O8 | A46, A47, A49 | C10 | A negative branch continues processing instead of ending it and discarding the packet |
| 10 | `tha-sensitive-receive` | CC1 O9 | A82 | C9 | The receive step's table effect or emission depends on `ar$tha` |
| 11 | `merge-key-substituted` | CC1 O5 | A52, A79 | C7, C1 | The table is keyed on, or updated from, the target fields rather than `<ar$pro, ar$spa>` |
| 12 | `hln-constant-wrong` | CC3 O10 | A34, A67 | C11 | A generated Ethernet request carries a value other than 6 in `ar$hln` |
| 13 | `op-constant-swap` | CC3 O11 | A17, A36, A61 | C8, C4 | The REQUEST and REPLY code points are exchanged in generation and in the reply |
| 14 | `reply-drops-parameters` | CC3 O12 | A76, A66 | C4, C12 | The reply does not carry `ar$hrd`, `ar$pro`, `ar$hln`, `ar$pln` through unchanged |
| 15 | `vector-reply-mismatch` | CC5 O13 | A90 | C4, C5 | Instantiated at the worked example's field values (382-401), the constructed reply differs from the example's stated reply in `ar$tha`. Registered with the expectation that it may come back `unwritable` if no contract instantiates the vector; that outcome is recorded, not removed |

### 5.4 Good twins (5 entries, expected SAFE)

A contract set that refutes everything, including correct implementations, is as useless as one that
refutes nothing. Each of these is behaviour RFC 826 permits or requires.

| # | `name` | Targets | Why it must survive |
|---|---|---|---|
| G1 | `good-twin-unsolicited-reply-merges` | A53, A64 | A REPLY arriving with no outstanding request, from a station that is not the owner of the mapping it carries, merges into an existing entry. Lines 209-213 and 227-234 **require** this merge, and lines 441-447 rely on it for recovery. If it is killed, some contract has imported a check RFC 826 never specifies, most likely the frame-header check that Stage B §4.3 excludes as X7 |
| G2 | `good-twin-tha-arbitrary` | A40, A41, A82 | A generated request whose `ar$tha` is the broadcast address, or zero, or anything else. Line 389 marks it a don't-care and rows A40/A41 are Deployment-modeled |
| G3 | `good-twin-optional-checks-omitted` | A48, A50 | A receiver that performs neither optional length check. Lines 205 and 208 say "optionally"; a kill would mean a contract made an optional check mandatory |
| G4 | `good-twin-multi-owner-target` | MD3, A55, A60 | A station owning several protocol addresses replies with the matched `ar$tpa` as its `ar$spa`. This is the reading Stage B fixed as MD3 and the example at 393-401 supports |
| G5 | `good-twin-structural-variant` | none | A correct body written differently (an `if` chain where the accepted fill used `match`, or arms reordered). Guards against a contract that fixes syntax rather than behaviour |

### 5.5 The mandatory members

Five entries are mandatory in the sense that the taxonomy is defective without them, and each is
attested rather than invented:

| Entry | Attestation |
|---|---|
| **1 `promiscuous-cache`** | Attested in deployed stacks: caching the sender mapping from packets not addressed to the receiver is common enough that implementations expose switches to control it. Already refuted once in this pipeline as `07-feasibility/recv-table-promiscuous.llmll` |
| **2 `merge-after-opcode`** | Attested by RFC 826 itself. Lines 227-234 exist to forbid it, in the document's own emphatic voice ("NOW look at the opcode!!", line 219), and lines 441-447 name the recovery failure it causes |
| **3 `old-address-wins`** | Attested by RFC 826 lines 231-234 and 443-447: without supersession, "each station will be get the new hardware address" is false and a station never recovers when a host moves |
| **4 `reply-to-reply`** | Attested as a loop hazard by the RFC's own monitor discussion at 347-348, and by row A77 (a received reply does not cause a reply) |
| **G1 `good-twin-unsolicited-reply-merges`** | This is ARP cache poisoning, the historically attested failure of this protocol, and the claim R1 tests at lines 461-464. **It is registered as a good twin, not as a mutant, because the behaviour conforms to RFC 826.** Booking it as a killed mutant would report that RFC 826 forbids what it in fact requires, which is exactly the direction of error this pipeline is built to avoid |

G1 is the sharpest instrument in this taxonomy. It is the entry that catches a contract set which has
quietly proved a better protocol than the one from 1982.

### 5.6 Obligations with no refutation pressure, declared in advance

Registering this now stops it being discovered at writeup and presented as a caveat.

| Obligation | Why no mutant |
|---|---|
| **C6** (no third-party relay) | Quantifies over all emitted packets rather than describing one transition. Stage H did not test this shape and flagged it (FINDINGS §4). A single-body mutation does not express it. Its verdict is booked as `discharged (no refutation pressure)` or as a finding about the shape, never as an ordinary discharge |
| **C5**, the "same hardware on which the request was received" half | Vacuous under MD2: one link is modelled, so the clause has no content to refute. The delivery-scope half is covered by mutant 7. MD2's vacuity warning appears in the results, not in a closing caveat |
| **C7**, the functionality half | Discharged by representation: a `map` is a partial function by construction and emits no verification condition. Only the frame condition (every key the packet does not name is untouched) carries proof content, and that is what the ledger books. Booking the functionality half would be booking the datatype |
| **R1, R2, R3** | Discharged by exhibited witness traces, not by mutants. R3 additionally has mutant 5 as its formal shadow; the mutant's kill is evidence about the model, and R3 still needs its witness under A4 |

---

## 6. Booking rules for the 15 obligations

Closed verdict vocabulary. One verdict per obligation, with its evidence artifact.

| Verdict | Requires |
|---|---|
| `discharged` | A contract clause citing the relevant rows verified body-faithful in the final tree, **and** at least one mutant mapped to that obligation in §5.3 killed |
| `discharged (no refutation pressure)` | The verification, where §5.6 registers that no mutant exists. Reported with that label attached, every time, so it is never read as equally supported |
| `refuted-with-witness` | R rows only. An exhibited trace artifact, its transition, and its assumption set from Stage B §7 |
| `classified-out` | A recorded reason naming the fragment feature required (order, arithmetic, sequence) or the barrier. Reported as a **Stage B scoping error**, per Stage B §8.1, not as a footnote on a success rate |
| `unfilled` | The hole exists, no fill was accepted within budget, and the §4.3 classification says the cause was semantic and not protocol. A finding |
| `not-attempted` | No contract carries the obligation. Must be 0 for C1..C12 unless `classified-out` |

Two rules that decide the cases most likely to be gamed:

- **Failure to find a proof is not a refutation.** R1, R2, R3 need witnesses (Stage B §8.5).
- **A killed mutant is not a discharge.** It is eliminative evidence about one behaviour. The
  discharge comes from the verified contract; the mutant shows the contract is not vacuous.

A **finding** is: a defect in a contract, a fill, the driver, the compiler, or a claim in RFC 826,
with a concrete witness (a file, a diagnostic, a trace, a command that reproduces it). Detection
yield (M7) counts findings, itemised by locus, with no denominator, because the total number of
defects present is unknown and any denominator would be invented.

---

## 7. Amendment procedure

An amendment is appended to Appendix B and contains, in order:

1. **The instrument named**, by section and ID as registered above.
2. **The defect**, stated as what the instrument measures instead of what it was meant to measure.
3. **The argument**, with the artifact or command that demonstrates it.
4. **What the amendment does not do**: it does not change a denominator, a threshold, or a verdict
   already booked.
5. **The adjudication asked of a human**, phrased as a decision, not a recommendation.

Amendments append. The pre-registered text above is never edited, including when it goes against the
run. That is the only property that makes this document worth writing.

---

## Appendix A: outcomes

*Empty at registration. Completed after the run. Nothing in this appendix edits anything above it.*

**A.1 Pre-wave record** (written before the first wave agent runs): `H` =, hole list =, driver
sha256 =, §3.3 branch chosen =, preflight (Appendix C) result =, `12-wave/roots.llmll-lock.json`
absent = .

**A.2 Obligation ledger**: 15 rows, verdict, evidence artifact, assumptions cited.

**A.3 Witnesses**: R1, R2, R3, each with file path, transition exhibited, assumption set.

**A.4 Intervention log**: class (P2/P3/P4), timestamp, actor, exact command, reason.

**A.5 Detection yield**: one row per finding, with locus and witness.

**A.6 Cross-function agreement review** (S4): duplicated predicate text per site, verdict.

**A.7 Kill matrix**: 15 mutants and 5 good twins, verdict per entry, survivors named and resolved.

**A.8 Concurrency record**: E1/E2/E3 counts, E2 classification per hole, `conflict_rate`, triggers
fired.

## Appendix B: amendments

*Empty at registration.*

## Appendix C: pre-wave preflight (P1)

Executed once, before the first wave agent runs, recorded in A.1.

| | Check | Fail action |
|---|---|---|
| C1 | Stage L reported the clause surface FROZEN and RFC-COV-1 passed | Stop. The wave does not start |
| C2 | `12-wave/roots.ast.json` was built from the frozen `10-roots/roots.llmll` in this run | Rebuild before starting |
| C3 | `12-wave/roots.llmll-lock.json` does not exist | Delete it and record the deletion in A.1. Deleting a stale lock **before** the wave is P1; deleting one during the wave invalidates the run |
| C4 | No `.verified.json` sidecars are present next to the tree from an earlier run | Remove them, so no result depends on a warm cache |
| C5 | Each agent directory is empty of anything but what §1.1 F7 provisions | Clear it |
| C6 | `llmll --version` reports 0.14.67 and the driver sha256 matches A.1 | Record the actual values; a mismatch makes this a different instrument and a different run |
