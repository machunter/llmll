---
name: roadmap-regroup-proposal
title: "ROADMAP-REGROUP-1: the Active Items table sorted into eight groups, ranked, with a decision queue"
status: "Rev 1, SETTLED and APPLIED 2026-09-07. Spec-track: no compiler work. The user adjudicated DRIVER-LL live (section 5, G0) and instructed the document update; the roadmap restructure, the three UPDATE-PROTOCOL rows, and the design-record updates (2026-09-05 triage section 5, phase-4 restart status, open-work R-10 and R-12, 2026-05-23 triage CRYPTO-2) landed with this revision. The marker convention (section 4 item 2) was applied under that instruction; reverting it is one edit per Next Action cell."
date: 2026-09-07
author: language-team
consumers: [user, documentation-lead, compiler-engineer]
style: "ASD-STE100 Simplified Technical English."
---

# ROADMAP-REGROUP-1

## 1. Restatement

The Active Items table of `docs/compiler-team-roadmap.md` holds 66 rows in no order and no grouping. Its own note says the rows are "not in priority order". The user wants the rows grouped, consolidated where two rows are one finding, and ranked by group and inside a group.

## 2. Population, measured 2026-09-07 at `f2f6aa0`

| Table | Rows | Source |
|---|---|---|
| Open work (v0.12+ lane) | 65 | roadmap lines 59-123 |
| Adversarial benchmark | 1 | line 131, settled |
| Externally-Blocked Parking Lot | 2 | LEAN-GA, MCP |
| Future: Module System Codegen | 4 | MOD-2, MOD-3, MOD-4, MOD-5 |
| Future: WASM | 1 line of work (4 phases) | |
| Future: Data Scope | 2 | Lever B, Lever C |
| Research track | 3 live | R1, R2, R4 (R3, R5, R7, R8 shipped or promoted) |

Total: 78 items. The user's "approximately 70" is the Active Items table.

## 3. Findings from the reading (drift inside the roadmap)

| # | Finding | Evidence | Disposition |
|---|---|---|---|
| F1 | `RET-RESOLVE` says "queued behind WILD-ASSUME-2". WILD-ASSUME-2 shipped at v0.14.74. | Shipped Releases row v0.14.74 | Status cell incorrect. The row is unblocked and its design is settled (Rev 2). It is engineer-ready. |
| F2 | `EVENT-CAPTURE-1` and `EVENT-LOG-2` parts D-1, D-2, D-3 are one finding filed twice. Both cite the §10a capture sentence and both offer the same fork: build it or delete the guarantee. | EVENT-CAPTURE-1 Next Action cites `env-read-1-implementation-plan.md` F1; EVENT-LOG-2 status cites EFFECT-RESP Rev 4 | Merge EVENT-CAPTURE-1 into EVENT-LOG-2. The merged row cites both sources. `REPLAY-INJECT` stays separate: it is the "build it" branch. |
| F3 | `IFACE-CONFORM` (Active, OPEN) and `MOD-5` (Future, prerequisite MOD-2) describe the same work: wire the §8.8 conformance check. IFACE-CONFORM says the data is in `ModuleEnv` at typecheck time, so the MOD-2 prerequisite MOD-5 states is not needed. | roadmap line 99 and line 165 | Fold MOD-5 into IFACE-CONFORM. Drop the MOD-2 prerequisite. |
| F4 | `FS-RMDIR-1` says FS-EXISTS-1 and FS-STAT-1 "STAY OPEN". Both shipped v0.18.0 and sit in the Closed table. | Closed table lines 530-531 | FS-RMDIR-1 is closed by its own text. Move to Closed. Its FR-5 note (a pin by preamble shape, not behaviour) is not a defect and needs no row. |
| F5 | `REPORT-GATE-1` is cited as "still unrouted" by `CRYPTO-2` and by `driver-ll-open-work.md` R-12, and has no row. | roadmap line 109; open-work line 213 | File the row. LIST-KIND-1's own text names this failure mode: a gap carried "with no tag and no row". |
| F6 | The adversarial benchmark row is "MEASURED — settled" and sits in Active Items. The census counts it as "neither". | line 131 | Move to Resolved cross-cutting items. |
| F7 | `DRIVER-LL` says "Nothing is queued" and is OPEN. What remains is 4d (stages H, K, N), 4f and program unification, stage A a STOP on HTTP-GET-1, and the Phase 5 conformance claim. The user adjudicated 2026-09-07: the campaign is LIVE. | line 90 status tail; `driver-ll-phase4-RESTART.md` status ("Phase 4 has no queued sub-phase") | The row is the campaign lane G0 (section 5) and its status cell names the next sub-phase. The RESTART record's status is rewritten the same way. HTTP-GET-1 is G7 rank 1. |
| F8 | `ENV-READ-1` and `CRYPTO-2` are SHIPPED and owe no compiler work. ENV-READ-1's residue is a census lesson. CRYPTO-2's residues are four design-doc references (language-team's) and REPORT-GATE-1 (F5). The CHANGELOG records CRYPTO-2 at line 332. | lines 87, 109; CHANGELOG.md:332 | Move both to Closed. File REPORT-GATE-1. Language-team owes the four reference corrections in one doc pass. |
| F9 | Sixteen rows wait on a decision and no turn is scheduled for it. Nothing in the table lets a reader find them. | section 6 | A `DECIDE:` marker and one decision session. |
| F10 | `PAIR-PROJ-LET-1` and `CALL-PRE-ARGCALL-1` do not say which way the free binder fails: a free binder in a hypothesis makes a constraint vacuous (false SAFE); a free binder in a goal makes it undischargeable (fallback or refutation). The rank of both rows depends on this. | lines 110-111 | The first Next Action of each row is the classification. Until then both sit at the top of group 1. |

## 4. Structure

Four changes to the roadmap. All are doc-lead moves.

1. **Eight themed sub-tables** under `### ` headings inside Active Items, each heading carrying its priority tier and a one-line admission rule. Same three columns. Row order inside a sub-table is the recommended order. The census method survives unchanged: every sub-table sits between the Active Items and Upcoming Releases headings.
2. **A marker at the start of the Next Action cell**: `DECIDE:` (waits on a language-team or user decision), `PLAN:` (design settled, engineer can plan), `DOC:` (doc-lead only), `MEASURE:` (a reproduction or census comes first). Greppable. The census reports the four counts. A decision closes by editing the marker in the commit that records it, which `docs/UPDATE-PROTOCOL.md` row 50 already requires for triage items.
3. **The Externally-Blocked Parking Lot widens to "Trigger-gated"**, keeping its `ID | Description | Trigger` shape. It absorbs the eleven Active rows in section 7. Every trigger names a greppable artifact: a version, a tag in Closed, a file. The census greps each trigger. RET-RESOLVE (F1) is the positive witness: its trigger names a tag that appears in Shipped Releases, so the grep fires.
4. **A shipped row with a residue** moves its ship narrative to Closed and keeps a one-line `<TAG> residue (n)` row in its group. Precedent: `BUILTIN-BODY-1 residue (1)`, commit `2b19d2d`. Four rows: PROC-BOUNDARY-1, TOOL-ORACLE-1, MATCH-TERM-EQ-1, NORM-CLAIM-1.

## 5. Groups, tiers and disposition of every row

Tier rule, from the roadmap's governing criterion (line 5: iteration burden, obligation completeness, repair distance):

- **P1**: a claim the project makes today that the tree falsifies (a verdict that is wrong or undisclosed; a built program that crashes or hangs after SAFE).
- **P2**: repair distance (a program passes one gate and fails the next; a decision that blocks a line).
- **P3**: design decisions and demand-gated surface with a measured workaround.
- **P4**: instruments over the repository, not the language.

Rank inside a group is the recommended order. `←` names the group a row is cross-referenced from.

### G0 (campaign lane). DRIVER-LL

Admission: a phased `[EXP]` campaign whose sub-phases file rows into G1 to G8. G0 is not tiered against them: it is the lane that produces their rows. It takes one engineer slot per sub-phase and one language-team slot per design it blocks on.

**Why a lane and not a tier.** A tier ranks fixes by the harm of leaving them unfixed. A campaign is an instrument: its value is the rows it files, and nine rows in this table came from it (CAP-1-REAL, CONSOLE-INIT-1, FS-STAT-1, MATCH-CATCHALL-1, PROC-BOUNDARY-1, PROC-TIMEOUT-1, REPLAY-FRAME-1, RESERVED-NAME-1, STRLIT-BODY-1). Ranking the instrument against its own findings fails one of two ways: above P1, the campaign runs and what it filed stays unfixed; below P1, fifteen G1 rows go first and the campaign gets no turn for months. The priority of a lane is a written sequence, not a label.

**The sequence, with one measured coupling.** The driver is built of `def-shell`: sequencer 174, wave 90, spine 51, registry 24, manifest 14, shell 5, against about fifty `def`s (measured 2026-09-07 over `tools/llmll-driver/`). SHELL-FALLBACK-SILENT-1 (G1 rank 2) says a `def-shell` downgrades to body-fallback silently in two shapes and a false post can reach SAFE unannounced. FALLBACK-CENSUS-1 (G1 rank 1) is the instrument that reports the driver's body-faithful ratio. Phase 5 states the driver's tier claim per driver-spec §15.4, so it cannot be written before those two rows close. Sub-phase 4d depends on neither. The order is therefore:

1. 4d prerequisite and 4d (engineer) in parallel with HTTP-GET-1 design (language-team);
2. FALLBACK-CENSUS-1, then SHELL-FALLBACK-SILENT-1 (G1 ranks 1 and 2);
3. HTTP-GET-1 ship, 4f and program unification;
4. Phase 5.

G1 ranks 3 onward interleave with steps 1 and 3 as slots allow. The row's status cell carries this sequence.

The row's status cell is rewritten: "Nothing is queued" becomes "Next: the 4d census prerequisite, then sub-phase 4d (H, K, N)". `driver-ll-phase4-RESTART.md`'s status says the same thing today and is rewritten with it. The sub-items below are the row's Next Action, in order, each with its marker.

| Order | Sub-item | Marker | Source | Cross-reference |
|---|---|---|---|---|
| 1 | 4d prerequisite: correct the `test_driver_ll_4c.py` census predicate (receiver-qualified and unaliased) | PLAN | phase4 proposal Rev 15 §9.3 item 1, measured at `b9cbf00` | none |
| 2 | Sub-phase 4d: stages H, K, N | PLAN | phase4 proposal §9.3, three settlements written; no `driver-ll-phase4d-implementation-plan.md` exists yet, so the engineer's next artifact is that plan | `oracle.llmll` and `--llmll-cmd` landed at v0.14.88 |
| 3 | Stage A: `wasi.http.get` | DECIDE (language-team design) | HTTP-GET-1 row; campaign STOP rule | G7 rank 1 |
| 4 | 4f and program unification (stage O with its §13 validator) | PLAN, after 4d | phase4 proposal §9 table | none |
| 5 | Phase 5: conformance claim and disclosure `[SPEC]` | DOC | campaign doc "Phase 5"; driver-spec §15.4 | SPEC-TIER-1 and FS-ISOLATION-1 (phase4 proposal §14) are its recorded constraints; PROC-TIMEOUT-1 (G2) bounds what it may claim about timeouts |

Rows the campaign filed and still waits on, by group: HTTP-GET-1 (G7), CAP-1-REAL (G5), CONSOLE-INIT-1 (G2), PROC-TIMEOUT-1 (G2), STRLIT-BODY-1 (G1), MATCH-CATCHALL-1 (G2), RESERVED-NAME-1 (G3). Each stays in its group; the campaign row names them and does not duplicate them.

### G1 (P1). The verdict: soundness and disclosure

Admission: the row changes what `verify` reports or what the trust report discloses.

| Rank | Row | Marker | Note |
|---|---|---|---|
| 1 | FALLBACK-CENSUS-1 | PLAN | The instrument. Emits the ratio and the cause histogram per CI run. Sizes rows 2, 8, 9, 14 before any of them is planned. |
| 2 | SHELL-FALLBACK-SILENT-1 | DECIDE | The only row whose text says a false post reaches SAFE unannounced. Recommendation: warning at `check` for a `def-shell`, error under `--strict`, mirroring the `def` error. |
| 3 | PAIR-PROJ-LET-1 | MEASURE | Classify the direction (F10). Reproduce c39. |
| 4 | CALL-PRE-ARGCALL-1 | MEASURE | Classify the direction (F10). Reproduce c40. Decide whether one fix covers 3 and 4 before planning either. |
| 5 | ADT-CYCLE-TLIST | PLAN | A list-recursive sum receives a fielded decl. `LLMLL.md:452` says it must not. |
| 6 | ARR-RANGE-NAME | PLAN | A ground fact decided on a variable-name suffix. |
| 7 | TRUST-AXIOM | PLAN | `bytes-set` and `bytes-zero` axioms still undisclosed; RESP-FACT-1's `assumed_facts` is the channel to reuse. |
| 8 | RET-RESOLVE | PLAN | Unblocked (F1). Design Rev 2 settled. Nine crash shapes. |
| 9 | CLAUSE-CTOR-PAREN-1 | PLAN | Body position fixed at v0.17.0; clause position crashes liquid-fixpoint. Assert byte-identical `.fq` for c23 and c20. |
| 10 | STRLIT-BODY-1 | PLAN | Fragment gap: a string-literal comparison in a body falls back. |
| 11 | DISCLOSE-ROW-1 | DECIDE | Which open `[SPEC]` rows a report names. Recommendation: the registry's `row` links (NC-031 → CAP-1-REAL today) are the source, so the report reads the registry and prints one line per touched row. |
| 12 | TRUST-BASE-1 | DOC | One paragraph in §0.1. Any turn. |
| 13 | REPORT-GATE-1 (new, F5) | DECIDE | No gate covers a spec claim about report shape. Recommendation: a fixture class for DRIFT-CT-2 that runs `verify` and asserts a JSON field is present or absent. |
| 14 | HASH-PRE-ASYM | PLAN | Empty in-tree population. Lowest in G1. |
| 15 | MATCH-TERM-EQ-1 residue (1) | PLAN | Disclosed as fallback, so not unsound. `result` binder carries `true` for a payload sum named by the post. |

### G2 (P1). Crash-freedom of built programs

Admission: `check` passes and the built program crashes, hangs, or runs with a state it did not declare.

| Rank | Row | Marker | Note |
|---|---|---|---|
| 1 | MATCH-CATCHALL-1 | PLAN | Mixed constructor/literal arms lose the catch-all; GHC exception inside a `Command`. |
| 2 | SPLIT-EMPTY-1 | DECIDE | Diverges and verifies. Recommendation: an empty separator yields the characters of the subject, the one total answer that also closes the missing character decomposition. |
| 3 | CONSOLE-INIT-1 | DECIDE | Recommendation: adopt the row's rule. `:init` is required unless the declared state type is `unit`. |
| 4 | PROC-TIMEOUT-1 | MEASURE | Reproduce on a small generated program. The one-line `-threaded` fix did not move the RTS. |
| 5 | RESULT-CTOR-RRW | PLAN | Partial fix v0.14.82. Thread the declaring type. |
| 6 | RUN-STDIN-1 | PLAN | Three defects, one patch: inherit stdin, propagate the child's exit code, stop buffering. |

### G3 (P2). One verdict across gates: `check`, `build`, diagnostics

Admission: `check` and GHC disagree, or a diagnostic misleads.

| Rank | Row | Marker | Note |
|---|---|---|---|
| 1 | RESERVED-NAME-1 | MEASURE | Enumerate the collision population first. DUP-DEF-1 (v0.20.0) is the precedent for the fix shape. |
| 2 | XMOD-CTOR-SEVERITY-1 | DECIDE | Recommendation: error at `check`. A `def` already errors and `build` fails anyway; the warning only delays the failure by one gate. |
| 3 | DONE-TYPE-1 | PLAN | Fires on every correct console program. Expand the inferred type and take the return position. |
| 4 | ALIAS-LOWER-1 | PLAN | Normalize the six glyphs at parse time. §2.4 requires identical AST nodes. |
| 5 | DIAG-KIND-SEXPR-1 | PLAN | Additive field on the S-expression channel. |
| 6 | PROC-BOUNDARY-1 residue (1) | PLAN | The §6.3 `tcWarn`: `:status` names a function with no range post. |

### G4 (P2). Command, Response and replay

Admission: the row changes what a `Command` result carries or what the event log records.

| Rank | Row | Marker | Note |
|---|---|---|---|
| 1 | RESP-FACT-2 | PLAN | The experiment that schedules CMD-A. Candidate fact named: `wasi.fs.sha256` answers an `RText` of length 64. |
| 2 | EVENT-LOG-2 (absorbs EVENT-CAPTURE-1, F2) | DECIDE | Recommendation: (b) delete the §10a capture guarantee and narrow item 8, after one measurement: replay a program that reads a file, change the file, and record what `replayOne` reports. No in-tree consumer needs a self-contained trace today. D-4 (`replayable` flag) is decided with it. |
| → | CMD-A | trigger-gated | Trigger: RESP-FACT-2 reports that a second fact needs a new delivery rule. |
| → | REPLAY-INJECT | trigger-gated | Trigger: EVENT-LOG-2 decides (a), or a consumer needs a self-contained trace. Owns `:init` output logging either way; if (b) is chosen, that piece moves to EVENT-LOG-2. |

### G5 (P2). Capability enforcement

Admission: the `capability` clause and what it enforces.

One row, not three (Rev 1 corrected 2026-09-07, section 13). The registry's `row` claim NC-031 targets the tag `CAP-1-REAL`, and `scripts/norm_claims_gate.py` fails when that tag leaves the Active Items table or its status cell stops beginning `**OPEN`. The three parts are sub-items of the one row.

| Rank | Row | Marker | Note |
|---|---|---|---|
| 1 | CAP-1-REAL | PLAN for WF and VERB; DECIDE for TARGET | Status cell keeps the `**OPEN` prefix. Sub-items in the Next Action cell: **CAP-1-WF** (zero migration cost, measured) and **CAP-1-VERB** (total static check; migration is `smoke.llmll` plus one crux caveat) ship in one release; **CAP-1-TARGET** stays a design question, because a path is a value-level property and a prefix predicate over strings is outside Σ_auto. When WF and VERB ship, NC-031 is re-dispositioned from `row` to `fixture` in the same commit, and the row stays OPEN on TARGET. |

### G6 (P3). Module system

Admission: import, open, qualification, interface conformance, per-module emission.

| Rank | Row | Marker | Note |
|---|---|---|---|
| 1 | IFACE-CONFORM (absorbs MOD-5, F3) | PLAN | §8.8 specifies the check; `ModuleEnv` holds the data. No MOD-2 dependency. |
| 2 | XMOD-QUAL-CTOR-1 | DECIDE | Recommendation: a qualified constructor type-checks, because §8.5.1 makes qualified access operational for functions and constructors are the gap. Until then the error text says `open` is required. |
| → | MOD-PROGLIB-1 | trigger-gated | Trigger: the next revision of the module section of `LLMLL.md`. |
| → | MOD-2, MOD-3, MOD-4 | trigger-gated | Trigger unchanged: a use case needing namespace isolation. Stay in their Future section. |

### G7 (P3). WASI and builtin surface

Admission: a new name or a widened signature. Group rule: a request ships when a second consumer appears, or when the workaround moves trust or correctness. Every row here has a measured workaround, so rank follows the measured firing population.

| Rank | Row | Marker | Note |
|---|---|---|---|
| 1 | HTTP-GET-1 | DECIDE | The group's one critical-path row: DRIVER-LL stage A is a STOP on it (G0 item 3). The only row in the group whose workaround moves trust: TLS trust sits in an ambient `curl` invoked with an unchecked argv. Next language-team design slot. |
| 2 | PATH-NORM-1 | PLAN | 58 of 947 live citations contain `..`. Highest measured population among the demand-gated rows. |
| 3 | REGEX-CASE-1 | PLAN | Fires on real prose and is silent in the dangerous direction. Recommendation: a `string-lower` builtin, the smaller and exact closure. |
| 4 | MODE-CLI-1 | DECIDE | Recommendation: (a) complete it: `:step` returns `(state, Command)`, `:status` honoured. The mode is advertised in three places and every TOOL-LL port wanted it. Fixture first. |
| 5 | BYTES-READ-1 | DECIDE | Recommendation: (a) hex-text read on the `wasi.fs.sha256` precedent, described as (a). |
| 6 | BYTES-WRITE-1 | DECIDE | Paired with 5: a hex-text write. One proposal, two names. |
| 7 | LIST-KIND-1 | PLAN | An entry kind on the `RList` arm, or a probe. |
| 8 | PROC-ENV-1 | PLAN | An environment parameter on `wasi.proc.run`. Workaround measured working. |
| 9 | PLATFORM-1 | DECIDE | Recommendation: keep the `uname` spawn as the interim and say so; a platform name is a one-consumer builtin today. |
| 10 | PROC-REDIRECT-1 | DECIDE | Recommendation: defer until a second `wasi.proc` path is added; the one-`int` mitigation holds until then and the row records it as an interim. |
| 11 | REGEX-CAPTURE-1 | PLAN | Measured cost is one `string-split` and zero disagreements over 955 citations. Lowest. |
| → | SHA1-DOMAIN-1 | trigger-gated | Trigger: the real crypto backend replaces the stub (§13.11). |

### G8 (P4). Instruments over the repository

Admission: a gate, a test, or an example; no language change.

| Rank | Row | Marker | Note |
|---|---|---|---|
| 1 | TOTP-CHECK-1 | DECIDE | Recommendation: repair the example (an RFC flagship) and wire its gate; `check-examples.sh` runs in no CI job (open-work R-1). Do not fold the two. |
| 2 | SKIP-SILENT-1 | DECIDE | Recommendation: a gate that cannot decide exits non-zero and prints `SKIP`. The two cover cells flip. |
| 3 | READ-SILENT-1 | DECIDE | Recommendation: a `Result` over the read. Shared disposition with row 2, separate fix, as the row itself argues. |
| 4 | NORM-CLAIM-1 residue (1) | PLAN | The LLMLL port, three artifacts, in `spec-roundtrip`. |
| 5 | SRC-CITE-DRIFT-1 | DECIDE | Recommendation: the cheap negative gate (no `.hs:NNN` in a comment under `compiler/src`), not the resolving gate. Enforces the cite-the-construct rule at the source. |
| 6 | FRONTMATTER-GATE-1 | PLAN | PyYAML 6.0.1 available; 67 files. |
| 7 | JSON-TESTSUITE-1 | PLAN | Differential test against the nst JSONTestSuite corpus. |
| 8 | SPEC-LAYOUT-1 | PLAN | One-line layout fix; do it with the next touch of the file. |
| 9 | TOOL-ORACLE-1 residue (1) | PLAN | Depth: three ports prove only exit status; extracting a token-to-verdict function restructures a live gate. Lowest. |

## 6. The decision queue (F9)

Sixteen rows carry `DECIDE:`. One language-team session settles them; the recommendations are in section 5. Rows: SHELL-FALLBACK-SILENT-1, DISCLOSE-ROW-1, REPORT-GATE-1, SPLIT-EMPTY-1, CONSOLE-INIT-1, XMOD-CTOR-SEVERITY-1, EVENT-LOG-2, CAP-1-TARGET, XMOD-QUAL-CTOR-1, MODE-CLI-1, BYTES-READ-1, BYTES-WRITE-1, PLATFORM-1, PROC-REDIRECT-1, TOTP-CHECK-1, SKIP-SILENT-1, READ-SILENT-1, SRC-CITE-DRIFT-1. (Eighteen with the two merged or split rows counted separately.)

Each decision is one paragraph. Six of them (SPLIT-EMPTY-1, CONSOLE-INIT-1, XMOD-CTOR-SEVERITY-1, XMOD-QUAL-CTOR-1, SKIP-SILENT-1, READ-SILENT-1) need no proposal document: the row's Next Action already states both options and the recommendation fits in the cell. Four (EVENT-LOG-2, CAP-1-TARGET, MODE-CLI-1, the BYTES pair) need a short proposal because they touch `LLMLL.md`.

## 7. Rows that leave the open-work table

| Row | Goes to | Ground |
|---|---|---|
| FS-RMDIR-1 | Closed | F4 |
| ENV-READ-1 | Closed | F8 |
| CRYPTO-2 | Closed | F8; REPORT-GATE-1 filed |
| Adversarial spec-weakening benchmark | Resolved cross-cutting | F6 |
| EVENT-CAPTURE-1 | merged into EVENT-LOG-2 | F2 |
| CMD-A | Trigger-gated: RESP-FACT-2 result | G4 |
| REPLAY-INJECT | Trigger-gated: EVENT-LOG-2 decides (a) | G4 |
| MOD-PROGLIB-1 | Trigger-gated: module-section revision | G6 |
| SHA1-DOMAIN-1 | Trigger-gated: crypto backend | G7 |
| PROC-PATH-LINT-1 | Trigger-gated: a second `wasi.proc.run` path, or a writer hits it | deliberately not built |
| CDP default-on | Trigger-gated: wall-clock under 1.5× on the examples set | deferred |
| INT-3 | Trigger-gated: TOTP regression over 5× (cleared at 1.015×) | dormant |
| OBLIG-1-FOLLOWON residual | Trigger-gated: a consumer of def-invariant axioms | deferred |
| RET-BRANCH-PREF Stage 2 | Trigger-gated: a crash shape Stage 1 does not cover | recorded, not proposed |

Count after the moves: 66 − 4 (closed or resolved) − 1 (merged) − 9 (trigger-gated) + 1 (REPORT-GATE-1) = **53** rows in nine sub-tables (G0 to G8; CAP-1-REAL stays one row, section 13; DRIVER-LL and HTTP-GET-1 stay, F7). Trigger-gated section: 9 from Active plus LEAN-GA and MCP = 11 rows, plus pointers to the three Future sections.

## 13. NORM-CLAIM-1 and the norm-claims gate: where each relative lands, and three interactions with this restructure

Measured 2026-09-07 from `scripts/norm-claims/registry.json` and `scripts/norm_claims_gate.py`: 35 claims, fixture 16, falsified-by 3, row 1, assumed 8, informative 7; `assumed_bound` 8, so the assumed count sits AT its bound.

| Relative | Lands in | Link to NORM-CLAIM-1 |
|---|---|---|
| NORM-CLAIM-1 residue (1), the LLMLL port | G8 rank 4, PLAN | The row's own owed item: three artifacts in `spec-roundtrip`. Narrative to Closed. |
| CAP-1-REAL | G5, one row | NC-031 is the registry's only `row` claim and targets this tag. |
| TRUST-BASE-1 | G1 rank 12, DOC | NC-001's `reason` already names TRUST-BASE. The paragraph adds sentences under §0.1, which is in the gate's scope. |
| DISCLOSE-ROW-1 | G1 rank 11, DECIDE | Consumes the registry's `row` links; the report prints one line per touched row. |
| REPORT-GATE-1 (new) | G1 rank 13, DECIDE | The fixture class DRIFT-CT-2 cannot express. Two witnesses share the cause (the harness runs `check` only) and the fix (a fixture class that runs `verify` or `build`): CRYPTO-2's report-shape claim, and NC-035, the `hole: <name>` abort at run time, `assumed` today for exactly this reason. Folded on the same-cause-same-fix rule of section 8 item 4. |
| SKIP-SILENT-1 | G8 rank 2, DECIDE | The gate's docstring cites it: DRIFT-CT-3 never SKIPs. The recommendation in G8 makes every gate behave the same way. |
| SRC-CITE-DRIFT-1, FRONTMATTER-GATE-1 | G8 ranks 5 and 6 | Gate-class siblings of DRIFT-DOC-4 and DRIFT-CT-3 over `docs/`. |
| TOOL-ORACLE-1 residue (1) | G8 rank 9 | Same port class: a port's adjudicator carries a contract and a refuting case; NORM-CLAIM-1's port owes the same. |
| DUP-DEF-1 (pilot finding F1) | Closed, v0.20.0 | The one pilot finding that became a row. |
| NC-002, NC-006, NC-009, NC-016, NC-032 | no row | Definitional or metatheoretic; the permanent `assumed` set. |
| NC-021 (LEAN-GA) | Trigger-gated, outside the gate's population | Stays `assumed`. The gate reads rows between `## Active Items` and the next `## ` heading only. |

**Interaction 1: a `row` target must stay in the table with an `**OPEN` status prefix.** The gate fails on a target that is "not in the Active Items table" or whose cell does not start `**OPEN`. So: CAP-1-REAL stays one row (G5 corrected). The markers go in the Next Action cell (column 3) and never in the status cell. `###` sub-headings are safe; the gate breaks only on `## `. The Trigger-gated section stays outside the population, which is the intended meaning of `row`: an OPEN row stands under the sentence.

**Interaction 2: the assumed count is at its bound.** TRUST-BASE-1's paragraph lands under §0.1, in scope. Every new sentence needs a marker; one new `assumed` sentence fails the gate. The paragraph is written as `informative` sentences naming the base (GHC, the codegen preamble, the VC emitter, liquid-fixpoint and Z3, the sidecar hash), or the bound is raised with a `bound_reason`. Doc-lead runs DRIFT-CT-3 locally before the commit.

**Interaction 3: the gate re-runs on every move this proposal makes.** NORM-CLAIM-1's Next Action requires re-running on row closure, not only on row opening. None of the rows moved to Closed or Trigger-gated is a `row` target today, so the moves pass; the CAP-1-REAL split was the one move that would have failed, and it is withdrawn.

## 14. Reading B of the 2026-09-05 triage, re-presented 2026-09-07

The reading was adjudicated on 2026-09-05: B1 declined as posed (TRUST-BASE-1 survived), B2 partial and owed a count, B3 already true, B4 reproduces open rows, B5 routed as DISCLOSE-ROW-1, B6 not adjudicated there. The count B2 owed is now run and recorded in `docs/design/critique-2026-09-05-triage.md` section 5, with a same-day correction: of 190 example files, 80 pass, 52 are intended refutations, 36 are unfilled scaffolds refused under a fallback label, and 17 hole-free programs fall back. Over those 17, the cause is the contract post leaving the fragment in 51 of 61 entries; bodies account for 7. No regression was measured. Disposition: strict stays the audit path; the ratio is tracked by FALLBACK-CENSUS-1 (G1 rank 1), whose Next Action gains three items (exclude holes or add a `hole` cause bucket; bucket contract-post causes by construct; ratchet the strict-pass set), and lowered by contract-vocabulary widening, which is Lever B's lever and now has a measured trigger. The tiers of this proposal are Reading B's item 4 and item 5 in order; its "stop widening" is G7's admission rule. Two doc-lead edits follow: the triage's B2 row records the count and its disposition; FALLBACK-CENSUS-1's cell cites the interim record.

## 8. Edge cases

1. **A row that fits two groups.** SHELL-FALLBACK-SILENT-1 (soundness and disclosure); XMOD-CTOR-SEVERITY-1 (module and gate agreement). Rule: one row, one group, chosen by where the FIX lands, not where the finding was made. Cross-reference in the cell. Double-listing would break the census, which counts lines. Channel: convention; the census is the check.
2. **A residue row whose parent tag is in Closed.** `<TAG> residue (n)` keeps the tag greppable in both tables, which is the intent. Precedent `BUILTIN-BODY-1 residue (1)`. Channel: convention.
3. **A trigger that has fired and nobody moved the row.** Positive witness: RET-RESOLVE, trigger WILD-ASSUME-2, present in Shipped Releases at v0.14.74. Rule: a trigger names a greppable artifact and the census greps it. Channel: the census note's method.
4. **Two rows, one finding.** Merge only when both rows cite the same spec sentence and the same fix. Positive witness: EVENT-CAPTURE-1 and EVENT-LOG-2 D-1 to D-3. Negative control: SKIP-SILENT-1 and READ-SILENT-1 share a class and not a fix, and stay separate, per the row's own text and FS-RMDIR-1's "folding is the ALIAS-LOWER-1 error".
5. **A soundness row with no stated direction.** PAIR-PROJ-LET-1 and CALL-PRE-ARGCALL-1. Rule: a G1 row's first sentence names the failure direction (false SAFE, false refutation, fallback); if unknown, the first Next Action is the classification and the row sits at the top of G1 until classified.

## 9. One adjudication for the user

DRIVER-LL was adjudicated LIVE on 2026-09-07 (section 5, G0). One question stays open.

1. **The marker convention.** `DECIDE:` / `PLAN:` / `DOC:` / `MEASURE:` at the start of the Next Action cell. Cost: sixteen cells now, one edit per decision after. Benefit: the decision queue becomes a grep.

## 10. Verification mapping

This proposal introduces no proof obligation. The checkable claims are the census counts and the trigger greps, both mechanical.

## 11. Affected surface

- `docs/compiler-team-roadmap.md`: Active Items restructured (section 4), rows moved (section 7), census note rewritten to count per sub-table and per marker. Doc-lead.
- `docs/UPDATE-PROTOCOL.md`: one row for the residue convention and one for the trigger-gated move. Doc-lead.
- `docs/design/driver-ll-open-work.md` R-12 and `critique-2026-05-23-triage.md` row CRYPTO-2: status cells updated when REPORT-GATE-1 gets its row and CRYPTO-2 closes. The 2026-05-23 triage's archive trigger is re-evaluated. Language-team, one pass.
- `CHANGELOG.md`: no version. A doc-only change; the next release's entry names it.

## 12. Risks

1. **Cross-group dependencies hidden by theme grouping** (HTTP-GET-1 ↔ DRIVER-LL; CMD-A ↔ RESP-FACT-2; REPLAY-INJECT ↔ EVENT-LOG-2). Scope. Mitigation: the trigger column names the tag.
2. **Rank goes stale silently**, the "Next is 4c" failure. Spec-drift. Mitigation: rank is a recommendation inside a group; the tier is what the census checks.
3. **A stale `DECIDE:` on a decided row** is the same class as F1. Spec-drift. Mitigation: the marker changes in the commit that records the decision.
4. **Merging EVENT-CAPTURE-1 loses its provenance.** Scope, small. Mitigation: the merged row cites both sources.
5. **A campaign row whose cell says "nothing is queued" reads as parked.** Spec-drift, the same class as F1. The DRIVER-LL cell and the phase4 RESTART record both say it today. Mitigation: G0's first sentence names the next sub-phase, and the RESTART record is rewritten in the same commit.
