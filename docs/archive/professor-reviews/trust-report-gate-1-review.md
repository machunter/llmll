---
name: trust-report-gate-1-review
title: "TRUST-REPORT-GATE-1: professor review of the direction and of the proposal Rev 0"
status: "Folded and archived (M2, 2026-10-15) into trust-report-gate-1-proposal.md's professor-review-log appendix. Rev 0 reviews the direction; Rev 1 reviews the proposal Rev 0."
date: 2026-10-14
author: professor
consumers: [language-team, user]
reviews: "trust-report-gate-1-proposal.md (direction, then Rev 0)"
---

# TRUST-REPORT-GATE-1 — Professor review of the direction

**Rev 0, 2026-10-14.** Reviews the direction for `TRUST-REPORT-GATE-1` that was discussed in session. No language-team proposal exists yet. The input is item D of [`external-review-v0-29-0-triage.md`](../../design/external-review-v0-29-0-triage.md) and the current lean:

1. Candidate 1: `verify --trust-report` runs the solver.
2. The render-only path moves to a new `llmll trust-report <file>` subcommand.
3. An imported function with no saved record renders `unverified (no record)` (option c). Saving a `refuted` record (option a) gets its own row.
4. The change ships as v0.30.0.

Measurements in this review use the installed `llmll 0.28.0` on the triage's `inc` fixture. The fixture's body is `x`, and its post is `(> result x)`.

## Restatement

The defect is that a reporting flag changes the verdict. `verify` exits 1 on a refuted body VC. `verify --trust-report` skips the solver at `compiler/app/Main.hs:1305`, renders the saved `.verified.json`, and exits 0. The lean makes the solver run for every `verify` invocation. It moves the solver-less render to a command whose name does not claim verification.

## Context located

1. `compiler/app/Main.hs:1305-1349`: the solver-less early exit. It always ends with `exitSuccess`.
2. `compiler/app/Main.hs:1938-1952`: the solver path (VERIFY-RPT-1). It marks `refuted` and exits on the solver verdict.
3. `compiler/app/Main.hs:1358-1376`: `--spec-coverage` has the same solver-less early exit and the same unconditional `exitSuccess`.
4. [`../archive/shipped-design-specs/verified-contract-refuted-status-proposal.md`](../shipped-design-specs/verified-contract-refuted-status-proposal.md) §3.2 and §7 risk 1: `refuted` is not saved because "a since-fixed function would carry a stale `refuted` tag."
5. `compiler/src/LLMLL/EvidenceKey.hs:1-29` (HASH-PRE-ASYM): the key now covers the body, the contracts, the callee contracts and the type declarations that a proof read. This postdates item 4.
6. `compiler/src/LLMLL/FixpointEmit.hs:3849-3850`: body VCs are path-enumerated and contain no kvars.
7. [`trust-axiom-propagation-proposal.md`](../../design/trust-axiom-propagation-proposal.md): a precedent for a saved fact that crosses the module boundary.
8. `scripts/benchmark-totp.sh:12,98-103`: `set -euo pipefail`, then `jq '.entries | length'` on the captured stdout.
9. `tools/llmll-driver/spine.llmll:715-760`: stage L parses the whole stdout file with one `json-parse`.

## Gaps and hazards

### H1. Dropping the early exit gives two JSON documents on stdout under `--json`

**Class:** spec-drift (output contract). **Bite:** blocks candidate 1 as currently stated.

The solver path prints the verdict object first. It then prints the trust report as a second object. This review measured the count:

- `verify bad.llmll --trust-report --cdp --json` exits 1 and prints two documents. The first has keys `diagnostics`, `phase`, `success`, …. The second has keys `entries`, `harness_assumptions`, ….
- `good.llmll` (body `(+ x 1)`) exits 0 and also prints two documents.

All three in-tree callers read one document:

- `benchmark-totp.sh:100` gets `null` and then a number from `jq '.entries | length'`. The comparisons that follow then fail.
- The same failure applies to `benchmark-erc20.sh`.
- Stage L of `spine.llmll` gets `stage-L=parse-failed`.

So "drop the early exit" is not the whole change. The proposal must state an output contract: `verify --trust-report --json` prints exactly one JSON document. The smallest change embeds the verdict fields in the report under one key. Today the same two-document output already applies to `--trust-report --cdp --json`, so the fix also repairs a live case.

### H2. `--spec-coverage` has the same defect, and the row does not name it

**Class:** scope. **Bite:** without it, the fix is half-done.

`verify bad.llmll --spec-coverage` exits 0 and prints `Effective coverage: 100% (1/1)` (measured). The cause is `Main.hs:1376`. The path reads the sidecar, runs no solver, and calls `exitSuccess`. It is the same pattern as `--trust-report`, and it carries the same verb. One rule should cover both flags. If the fix covers only `--trust-report`, the next external review finds this one.

### H3. The rule to settle is flag orthogonality, not one flag's behaviour

**Class:** spec-drift. **Bite:** decides the shape of the proposal.

Mature tool chains keep reporting flags apart from the verdict. GHC's `-ddump-*` flags change output and never change the exit status. Dafny separates skipping from verifying by name. `--no-verify` is an explicit opt-out. Dafny also gives a verification failure its own exit code, apart from parse and resolution errors.

The language-team should state this rule in `LLMLL.md`:

> For every reporting flag F, `exit(verify F x) = exit(verify x)`.

Two exceptions keep their meaning: the exit-3 "solver unavailable" case at `Main.hs:1530`, and `contradictionExit`. Candidate 1 satisfies the rule. Candidate 2 cannot satisfy it, because a render-only path does not know the verdict.

This rule, not the triage's argument about footers, is the principled reason to reject candidate 2.

### H4. The importer gap is a loss of precision, not a soundness hole; option (c) is mostly a relabel

**Class:** scope. **Bite:** changes the recommended scope.

Under assume-guarantee composition, an importer's SAFE verdict depends on the callee's verification. Dafny, F\*, Lean and Liquid Haskell all verify modularly in this sense:

- F\* writes a `.checked` file only for a module that checks.
- Lean writes an `.olean` file only for a module that elaborates.
- Liquid Haskell fails the GHC compile.

None of the four can have an "imported, refuted" state. A dependency that does not check stops the importer's build.

LLMLL chose a permissive tier model instead (refuted-status proposal §7 risk 3). In that model, a callee with no positive record already renders `asserted`. Two things follow:

- The importer's caller gets asserted-dependency drift.
- `--strict-verified-core` conjunct (d) already refuses it.

So the importer never claims `verified` for a refuted callee. The defect is that `asserted` merges two cases: "never attempted" and "attempted and refuted." Option (c) renames `asserted` for one population and still merges the two cases. It adds a label and no information. Do not do option (c).

### H5. The reason not to save `refuted` no longer holds

**Class:** scope. **Bite:** makes option (a) cheap and principled. It does not block this row.

The 2026 refuted-status proposal did not save `refuted` because a fixed function would keep an incorrect tag. HASH-PRE-ASYM (`EvidenceKey.hs:12-23`) removes that risk. A fixed body changes the key, so the loader discards the record exactly as it discards an incorrect `verified` record. A strengthened callee post also changes the key.

Leino and Wüstholz, "Fine-grained caching of verification results" (CAV 2015), cache Boogie results keyed on checksums. As this reviewer recalls, they also re-report cached errors, so negative results are cached too. "Build systems à la carte" (Mokhov, Mitchell, Peyton Jones, ICFP 2018) gives the general condition: a cached result is valid when its verifying trace matches. That condition holds for a positive result and for a negative one.

One qualifier must go into the record's meaning. A refuted body VC is a counterexample relative to the callees' declared contracts and the uninterpreted measures (`strLen`, `listLen`). It is not necessarily a run-time failure. The refuted-status proposal §3.4 decides that question only for the fixed QF-LIA VC. Option (a) should save "not entailed by the declared contracts" and render it that way.

### H6. Cost moves onto every report consumer

**Class:** ergonomic. **Bite:** complicates the change; measure it before shipping.

The render-only path exists because it is fast. After the change, a report on the `VERIFY-MEMORY-1` file costs the 5.5 GB solver run. Any agent loop that polls `--trust-report` pays the full solver cost on each poll. That is correct for a verdict. It is wrong for a dashboard, which is the reason to keep the subcommand.

### H7. A report command now writes `.verified.json`

**Class:** ergonomic. **Bite:** minor.

The solver path writes the sidecar on SAFE. `verify --trust-report` thus gains a write side effect. Plain `verify` already has it, so the rule in H3 makes this consistent. The proposal should state it because of the concurrency history in VERDICT-UNSTABLE-1.

## Recommendation

1. **Take candidate 1, stated as the rule in H3.** Apply it to `--trust-report` and `--spec-coverage` together (H2). Reject candidate 2 because it cannot satisfy that rule.
2. **Make one JSON document a condition of the change (H1).** Fold the verdict object into the report under one key. Add a gate that counts the top-level documents on stdout for `--trust-report --json`, for SAFE and refuted inputs. Fix the `--cdp` case in the same change, because it has the defect today.
3. **Keep the render-only path as `llmll trust-report <file>`.** It exits 0 and keeps the footer. Do not add a flag on `verify`, because the defect is the verb. Move `test_sidecar_admit_1.py` cell A to the subcommand unchanged. Do the same for a solver-less `llmll spec-coverage`, or drop the solver-less coverage path.
4. **Drop option (c) (H4).** Record in the proposal that the importer cannot claim `verified` for a refuted callee today, and why.
5. **File option (a) as its own G1 row, with H5 as its rationale.** It closes the "attempted and refuted" merge at the import boundary. The saved status means "not entailed by the declared contracts." It is the only change that gives the importer the information.
6. **Ship as v0.30.0.** The change modifies exit status and stdout shape for documented commands. Increase `trust_report_version` if the verdict moves into the report.

## Open questions for the language-team

1. Under H3, state whether `--obligation-report` and `--leanstral` are reporting flags or mode flags. `--leanstral` runs a proof pipeline inside the early-exit path (`Main.hs:1315-1318`), so the line between "reports" and "computes" needs one sentence in the spec.
2. State whether `llmll trust-report` should print the key-mismatch count (records discarded as incorrect). With that count, a reader can tell "no record" from "record no longer valid" without the solver.

---

# Rev 1 — review of the proposal Rev 0 (2026-10-14)

Reviews [`trust-report-gate-1-proposal.md`](../../design/trust-report-gate-1-proposal.md) Rev 0. The user asked for three focus points: the §3.3 nesting decision, the §3.1 flag taxonomy with its exit-4 exception, and anything else missed.

## Restatement

Rev 0 deletes the two solver-less early exits in `verify`. It moves the cached renders to `llmll trust-report` and `llmll spec-coverage`. It makes `verify --json` print one document, the verdict object, with each report nested under a fixed key. It states an exit-status rule for three classes of flag.

## Context located

1. `compiler/app/Main.hs:1755-1799`: the SAFE branch builds `provenCS` from the source only. A body-faithful post gets `verified`, and every other contract gets `asserted`. `saveVerifiedWithAxioms` then writes it.
2. `compiler/src/LLMLL/VerifiedCache.hs:421-433`: `saveVerifiedWithAxioms` replaces the whole file with `BL.writeFile`. It does not merge with the records already in the file.
3. `compiler/app/Main.hs:648-655`: `llmll test` merges its `tested` records into the existing sidecar (`Map.unionWith mergeCS`). The two writers are asymmetric.
4. `compiler/app/Main.hs:3259-3265`: the proof artifact already composes a verdict and a trust report. It hard-codes `cvTrustReport = "1.4.0"` and `cvSchema = "0.7.0"`.
5. `scripts/tests/test_headline_term_1.py:310`: the emitter's `trust_report_version` is `1.9.0`.
6. `compiler/app/Main.hs:2141-2142` onward: `runLeanstralPipeline` contains no exit call. The proposal's claim about prover flags holds.
7. `compiler/app/Main.hs` (the `solver_verdict` field): its values are `safe`, `refuted` and `error`.

## Gaps and hazards

### R1-1. A report run now erases `tested` evidence

**Class:** spec-drift (evidence monotonicity). **Bite:** complicates the proposal, and it changes report contents.

Today, `llmll test` writes a `tested` record for a fallback function into the sidecar (context item 3). The solver-less `verify --trust-report` then shows `tested`. Under Rev 0, `verify --trust-report` runs the solver and, on SAFE, rewrites the whole sidecar from `provenCS` (context items 1 and 2). The `tested` record is gone, and the report shows `asserted`. `--spec-coverage` tiers drop with it, because coverage reads the same headline levels.

Plain `verify` already behaves like this. So the defect predates the proposal: the sidecar content depends on whether `test` or `verify` ran last. Rev 0 makes it matter more, because every report run now overwrites the sidecar. Before Rev 0, a report run never wrote it.

Rev 0 §3.2 says the report "writes `.verified.json` on SAFE, because plain `verify` does". It does not say what that write destroys.

Build systems treat this as a correctness property: a rebuild of one target must not invalidate an unrelated, still-valid result ("Build systems à la carte", Mokhov, Mitchell, Peyton Jones, ICFP 2018, §2 on minimality and correctness). A `tested` record that still matches its key is such a result.

### R1-2. The nesting decision is right, and the verdict must say its exit status

**Class:** ergonomic. **Bite:** a refinement, not a block.

Rev 0 compares two hosts for the document, the verdict object and the trust report. It does not consider the third common shape: a stream of tagged documents, one per line. Cargo's `--message-format=json` (a `reason` tag on each line), `go test -json` and GHC 9.10's `-fdiagnostics-as-json` all use it. LLMLL is close to it already, because each document prints on one line. Two pytest helpers already scan lines by key (`test_headline_term_1.py:157-165`, `test_partial_fns_graph_1.py:129-137`). A tag would make the current output a valid stream at the lowest migration cost.

Reject the stream for this row anyway. The defect class here is a consumer that ignores the process exit status. Stage L of `spine.llmll` is one of them. A stream puts the verdict and the report on different lines, and a consumer that reads one line misses the other. One envelope puts them in the same object. SARIF 2.1.0 (OASIS) chose the same: one log document, with `invocations[].exitCode` and `executionSuccessful` inside the document beside the results.

So keep §3.3, and take SARIF's point further. The envelope must carry the exit status the process will return, as a field. A consumer that reads only stdout then still sees `1` beside a refuted report. The top-level verdict should be the existing `solver_verdict` (`safe`, `refuted`, `error`) plus that exit status.

### R1-3. The envelope repeats the proof artifact, and the artifact's composed versions are incorrect

**Class:** spec-drift. **Bite:** minor, but it affects this change directly.

`--proof-artifact` already composes a verdict and a trust report into one record, and it states which versions it composes (`ProofArtifact.hs:205-208`). The constants are `trust_report_version` `1.4.0` and `schema_version` `0.7.0` (`Main.hs:3265`). The emitter is at `1.9.0` (context item 5) and the schema at `0.12.0`. The artifact therefore states a version it does not contain.

Rev 0 increases `trust_report_version` again and creates a second composing document. Use the artifact's `composed` convention for the envelope, so each nested report's version is stated once. Compute the values, do not hard-code them. Fix the artifact's constants in the same change.

### R1-4. Write the flag rule as one monotone law; exit 4 is not an exception

**Class:** spec-drift. **Bite:** a rewording, but it is the statement the spec will keep.

Rev 0 §3.1 writes the reporting rule as "equal, unless the flagged run exits 4". That wording permits a failing run (exit 1) to become exit 4. The code forbids that: every `contradictionExit` call is guarded on success (`Main.hs:1628`, `:1674`, `:1958`, `:2002`). The written rule is weaker than the code.

The property that the original defect broke is one direction only: **no flag turns a failing run into a passing one.** State that as the law for every flag. Then the classes differ only in which non-zero codes a flag may add to a passing run:

```
For every flag F and input x:
  exit(verify x) ≠ 0  ⟹  exit(verify F x) = exit(verify x)        (no flag masks a failure)
  exit(verify x) = 0  ⟹  exit(verify F x) ∈ Adds(F) ∪ {0}
  Adds(reporting) = Adds(prover) = {4},   Adds(--strict-verified-core) = {1, 4}
```

Under this law, exit 4 belongs to the reporting class and is not an exception. Context item 6 confirms that prover flags add nothing beyond 4. The first line is the safety property, and the flag-rule test should check it on the positive witness for every flag.

## Recommendation

Settle Rev 0 after four revisions, in this order of importance.

1. **State what a report run does to non-solver evidence (R1-1).** The recommended answer: the SAFE write keeps every record that the solver did not produce (`tested`, `verified-lean`) when the record's key still matches. It uses the same `mergeCS` rule that `llmll test` already uses. If the language-team declines, Rev 1 must say that `verify --trust-report` shows this run's solver evidence only. Then file the write-order defect as its own row.
2. **Put `exit_code` and `solver_verdict` at the top of the envelope (R1-2).** Record the rejected stream alternative with its reason.
3. **Use a computed `composed` version block in the envelope, and fix the proof artifact's constants (R1-3).**
4. **Replace the §3.1 rule with the monotone law (R1-4).** Exit 4 then needs no exception.

Rev 0's other decisions stand: the two subcommands, the discarded-record count, the out-of-scope importer view and `TRUST-REFUTED-PERSIST-1`.

## Open questions for the language-team

1. Decide recommendation 1. Should a SAFE `verify` keep a `tested` or `verified-lean` record whose key still matches? Or is a `verify` run defined to show only its own solver evidence? The choice changes report contents on any file that `llmll test` has touched.
