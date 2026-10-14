---
title: TRUST-REPORT-GATE-1 — a reporting flag never changes the verdict
status: Rev 1, SETTLED 2026-10-14
row: TRUST-REPORT-GATE-1 (G1)
review: trust-report-gate-1-review.md (professor, Rev 0 and Rev 1, both folded here)
---

# TRUST-REPORT-GATE-1 — a reporting flag never changes the verdict

**Status: Rev 1, SETTLED 2026-10-14.** Folds the professor review [`trust-report-gate-1-review.md`](trust-report-gate-1-review.md), Rev 0 and Rev 1. Direction set by the user on 2026-10-14: candidate 1 of triage item D, applied to `--trust-report` and `--spec-coverage`, released as v0.30.0. On the same date the user chose the professor's answer to review Rev 1 open question 1: a SAFE `verify` keeps non-solver evidence that still matches its key (§3.5).

## Restatement

`llmll verify` has two flags that skip the solver: `--trust-report` and `--spec-coverage`. Each renders the saved `.verified.json` and exits 0. On a function that the solver refutes, plain `verify` exits 1, and each of these flags exits 0. A script that uses either flag as a gate passes a disproved function.

This proposal states one rule for every `verify` flag and moves the solver-less renders to two subcommands. Their names do not say `verify`. It also fixes the `--json` output so that `verify` prints exactly one JSON document.

**Design-reference set.** The competition is Dafny, F\*, Lean and Liquid Haskell, not the Python/Go measurement set. All four tie the verdict to the run: Dafny names its opt-out (`--no-verify`), and the other three write no artifact for a module that fails. This proposal keeps LLMLL's permissive trust tiers (refuted-status proposal §7 risk 3) and closes the exit-status gap only.

## Context located

1. `compiler/app/Main.hs:1305-1349`: the `--trust-report` early exit. It reads the sidecar, prints a footer and calls `exitSuccess`.
2. `compiler/app/Main.hs:1358-1376`: the `--spec-coverage` early exit. It has the same shape. Measured: `verify bad.llmll --spec-coverage` prints `Effective coverage: 100% (1/1)`, exit 0.
3. `compiler/app/Main.hs:1938-1959`: the solver path for `--trust-report --cdp`. It marks `refuted` and exits on the solver verdict (VERIFY-RPT-1).
4. `compiler/app/Main.hs:3238-3257`: `contradictionExit`, exit 4, "laundered evidence refused". It escalates from success only.
5. `compiler/app/Main.hs:308-333`: the `verify` flags. The `--trust-report` help text says "instead of running fixpoint".
6. `LLMLL.md:634` (§4.4.4) says `--trust-report` "prints a per-function trust summary after verification". **Spec drift:** the help text (item 5) is correct and the spec is not.
7. `LLMLL.md:664`: "a plain `llmll verify --trust-report` exits before the emitter runs". This is correct today and becomes incorrect after this change.
8. `compiler/app/Main.hs:3246-3247`: a comment says exit 4's JSON-mode routing "keeps stdout a single valid JSON document". **Code-comment drift:** see item 9.
9. Measured on `llmll 0.28.0`. With `--trust-report --cdp --json`, stdout holds two JSON documents (the verdict object, then the trust report). With `--strict-verify --json`, it holds three (verdict, trust report, coverage). This is true for SAFE and refuted inputs.
10. [`../archive/shipped-design-specs/verified-contract-refuted-status-proposal.md`](../archive/shipped-design-specs/verified-contract-refuted-status-proposal.md) §3.2: `refuted` is a status beside the display level, and it is not saved.
11. `compiler/src/LLMLL/EvidenceKey.hs:1-29` (HASH-PRE-ASYM): the key covers everything a proof read. That removes §3.2's reason for not saving `refuted` (review H5).
12. `compiler/app/Main.hs:1283`: `downgradeStaleVerifiedSidecarIn` returns `_staleDiags`, which the render path discards. This list is the input for the discarded-record count in §3.4.
13. Cost, measured on copies of the in-tree inputs with `llmll 0.28.0` (wall time, warm). The solver-less render takes 0.05 to 0.11 s. Plain `verify` takes 0.10 to 0.24 s. `--trust-report --cdp` takes 0.11 to 0.58 s. Inputs: `totp_filled.ast.json`, `erc20_filled.ast.json` and `tftp_rfc1350/roots/tftp.llmll`. The worst in-tree case is the `VERIFY-MEMORY-1` file (5.5 GB). It was not run.

14. `compiler/app/Main.hs:1755-1799` and `compiler/src/LLMLL/VerifiedCache.hs:421-433`: a SAFE `verify` builds the sidecar from this run only and replaces the file. `llmll test` merges into the file instead (`Main.hs:648-655`, `Module.hs:374-387` `mergeCS`).
15. `compiler/src/LLMLL/PBT.hs:805-808`: a `tested` record carries a property-body hash (`PbtWitness`) and no evidence key (`erVerifiedHash = Nothing`). `TrustReport.hs:840-856` (`downgradeStaleSidecar`) checks only that the property body is still live. **Gap:** a `tested` record survives an edit of the tested function's body.
16. `compiler/src/LLMLL/ProofCache.hs:170-184`: `upgradeLeanstralPosts` gives a post `verified-lean` when an untainted `/post/<name>` entry exists in `.proof-cache.json`. It does not compare the entry's `obligation_hash` with the live obligation. **Gap:** a `verified-lean` post survives an edit of the function. The render-only path applies it at `Main.hs:1337`. The SAFE write applies it only under a `--leanstral` flag (`Main.hs:2014-2031`).
17. `compiler/src/LLMLL/TrustReport.hs:968-973`: `positiveTier` is true for `verified` and `verified-lean`, false for `tested`. The SIDECAR-ADMIT-1 read check (`:937-941`) demotes a positive record that is not body-faithful. A saved `verified-lean` record is therefore always demoted on read, and the proof cache is its only source.
18. `compiler/app/Main.hs:3259-3265`: the proof artifact composes a verdict and a trust report with hard-coded versions `1.4.0` and `0.7.0`. The emitter is at `1.9.0` (`test_headline_term_1.py:310`) and the schema at `0.12.0`.
19. The `solver_verdict` field of the verdict object takes `safe`, `refuted` or `error`.

No earlier draft on this topic exists in `docs/design/`.

## Design proposal

### 3.1 The flag rule

One law covers every `verify` flag. Its first line is the safety property that the original defect broke: **no flag turns a failing run into a passing one.** Its second line says which non-zero codes a flag may add to a passing run.

```
For every flag F and every input x:
  exit(verify x) ≠ 0  ⟹  exit(verify F x) = exit(verify x)        (no flag masks a failure)
  exit(verify x) = 0  ⟹  exit(verify F x) ∈ Adds(F) ∪ {0}
```

The flags fall into three classes, which differ only in `Adds(F)`:

| Class | Flags | `Adds(F)` |
|---|---|---|
| **Reporting** | `--trust-report`, `--spec-coverage`, `--cdp`, `--weakness-check`, `--obligations`, `--obligation-report`, `--proof-artifact`, `--fq-out`, `--strict-verify` (sugar for four reporting flags) | `{4}` |
| **Prover** | `--leanstral`, `--leanstral-mock`, `--leanstral-cmd`, `--leanstral-timeout`, `--leanstral-model`, `--leanstral-lean-project` | `{4}` |
| **Gate** | `--strict-verified-core` | `{1, 4}` |

The documentation-lead puts the law into the spec's own wording.

**Exit 4 is part of the law, not an exception to it.** Exit 4 means that a saved record contradicts this run, so the report cannot be printed honestly (`Main.hs:3238-3244`). Every `contradictionExit` call is guarded on success (`Main.hs:1628`, `:1674`, `:1958`, `:2002`), so exit 4 never replaces a failure. Rev 0 wrote the rule as "equal, unless the flagged run exits 4". That wording allowed exit 1 to become exit 4, which the code forbids.

**Exit 3 needs no clause.** Plain `verify` also exits 3 when the solver is absent (`Main.hs:1530`), so the first line of the law covers it.

**Answer to professor open question 1.** `--obligation-report` is a reporting flag. It already exits on the solver verdict (`Main.hs:1628-1629`). The `--leanstral` flags are prover flags. A prover adds evidence for fallback obligations, and a fallback obligation never sets the exit status. `runLeanstralPipeline` (`Main.hs:2141` onward) contains no exit call, so `Adds(prover) = {4}` holds today. One case needs a gate test: a fallback function that the solver refutes keeps exit 1 under `--leanstral`. The early-exit block at `Main.hs:1315-1318`, which runs Leanstral before the render, goes away with the early exit. Leanstral already runs on the solver path.

### 3.2 `verify --trust-report` and `verify --spec-coverage` run the solver

Delete both early exits. Each flag renders on the post-solver path, which marks `refuted` and exits on the verdict. The early exits now at `Main.hs:1305-1349` and `Main.hs:1358-1376` are not kept behind any `verify` flag.

`verify --trust-report` writes `.verified.json` on SAFE, because plain `verify` does (review H7). Before Rev 0, a report run never wrote the sidecar. §3.5 states what that write keeps.

### 3.3 One JSON document on stdout

Under `--json`, `llmll verify` prints exactly one top-level JSON document on stdout, for every combination of flags. Diagnostics and refusals go to stderr, as exit 4 does today.

**The document is the verdict object.** Each requested report nests under a fixed key:

| Flag | Key |
|---|---|
| `--trust-report` | `trust_report` |
| `--spec-coverage` | `spec_coverage` |
| `--weakness-check` | `weakness` |
| `--obligations` | `obligation_suggestions` |
| `--obligation-report` | `obligation_report` |
| `--strict-verified-core` refusal | `strict_errors` |

**The document states its own outcome.** Two keys come first:

- `exit_code`: the status the process returns.
- `solver_verdict`: the existing field, `safe`, `refuted` or `error`.

A consumer that reads only stdout and ignores the process status still sees the outcome beside the report. Stage L of `spine.llmll` is such a consumer. SARIF 2.1.0 (OASIS) puts `invocations[].exitCode` in its log document for the same reason.

**The document states the versions it composes.** It carries a version field for its own shape. It also carries a `composed` block naming the version of each nested report, on the proof artifact's convention (`ProofArtifact.hs:205-208`). The values are computed from the emitters, not hard-coded. The proof artifact's hard-coded `1.4.0` and `0.7.0` (context item 18) are incorrect today, and this change fixes them in the same way.

**Rejected alternative 1: the trust report as the document, with the verdict added under one key.** That keeps `.entries` at the top level for the current callers. It fails for `--spec-coverage` alone and for `--strict-verify`, where two reports must share one document. That gives two document shapes chosen by flags. One shape for every flag set is the smaller contract, and v0.30.0 is breaking in any case.

**Rejected alternative 2: one tagged document per line.** Cargo's `--message-format=json`, `go test -json` and GHC 9.10's `-fdiagnostics-as-json` use this shape. It is the cheapest migration here, because each document already prints on one line and two pytest helpers already scan lines by key. It is rejected because this row's defect is a consumer that ignores the exit status. A stream puts the verdict and the report on different lines, so a consumer that reads one line misses the other. One document keeps them together.

### 3.4 The solver-less renders become subcommands

```
llmll trust-report  <file> [--json]
llmll spec-coverage <file> [--json]
```

Each subcommand reads `.verified.json` through the existing key check (`downgradeStaleVerifiedSidecarIn`). Each runs no emitter and no solver, and each exits 0 when the file type-checks. The text footer stays. Under `--json`, each prints today's bare report shape, with no verdict object. The subcommands accept no prover flag, because a prover run is computation.

**Answer to professor open question 2: yes, print the discarded-record count.** The key check already returns the list (`Main.hs:1283`, `_staleDiags`), and the render discards it. The text output adds `records discarded (key mismatch): N`. The JSON output adds `discarded_records: [name, …]`. A reader can then tell "no record" from "a record that no longer matches the source" without the solver. The count covers the entry module. An imported module's discards are counted if the module loader exposes them. The engineer reports whether it does.

**Why two subcommands and not one with flags.** Each name matches the `verify` flag it replaces, so the migration is a word swap. Neither name says `verify`.

### 3.5 A SAFE write keeps non-solver evidence that still matches

**The problem.** A SAFE `verify` builds the sidecar from this run's solver result and replaces the file (context item 14). A `tested` record written by `llmll test` is lost. The solver-less render showed it, so under Rev 0 a report run would erase evidence that the report showed before. The sidecar content also depends on which command ran last: `test` then `verify` loses the record, and `verify` then `test` keeps it.

**The rule.** A SAFE write keeps a non-solver record when, and only when, the record still describes the live function. The solver's own result takes precedence where both exist, by the existing `mergeCS` rule (`Module.hs:374-387`). The rule needs a check that does not exist today for either non-solver tier, so it comes with one for each.

**`tested` and `tested-joint`.** Today these records carry only a property-body hash (context item 15). An edit of the tested function's body leaves the record valid, so carrying it forward would label untested code `tested`. Therefore:

1. The PBT write-back (`PBT.hs:805-808`) stamps the subject function's evidence key (`evidenceKey`, plain variant) on the record, beside the witness.
2. A record is valid when a witness is live **and** the stamped key equals the live key. A record with no stamped key is not valid. That covers every record written before v0.30.0, so the check fails closed, as ADMIT-VERIFIED does for an absent hash.
3. The SAFE write keeps a valid record and drops an invalid one.
4. Every read applies the same check: `downgradeStaleSidecar` (`TrustReport.hs:840-856`), and so the subcommands and every importer. A dropped or demoted record is listed in `discarded_records` (§3.4).

**`verified-lean`.** A saved `verified-lean` record is demoted on every read (context item 17), so `.proof-cache.json` is its only source. Today the upgrade is presence-based (context item 16). Therefore:

1. `upgradeLeanstralPosts` upgrades a post only when the proof-cache entry's `obligation_hash` equals the hash of the live obligation.
2. Every SAFE write applies the upgrade, not only a run with a `--leanstral` flag. That replaces the re-stamp at `Main.hs:2014-2031`.
3. Every render on the solver path applies the upgrade, as the render-only path does today at `Main.hs:1337`.
4. The live obligation hash may need the emitter. If it does, `llmll trust-report` (no emitter) does not upgrade and renders `asserted`. The engineer reports which case holds.

**Solver tiers.** `verified (liquid-fixpoint)` records are rewritten by each run, as today.

**Strict immutability.** Unaffected. These are rules about a file the compiler writes between runs, not about program semantics.

**Why this is in scope.** Rev 0 made every report run write the sidecar. Without this section, the row would turn a solver-less render that showed `tested` into a solver run that erases it. The two key checks are the smallest addition that makes "still matches" a checkable claim.

### 3.6 Out of scope: the importer's view of a refuted callee

The importer view stays as it is. Review H4 shows that it is a loss of precision, not a soundness hole. An imported callee with no positive record renders `asserted`. Its caller gets asserted-dependency drift, and `--strict-verified-core` conjunct (d) refuses it. No path claims `verified` for a refuted callee. Option (c), a new label for this case, is dropped because it adds no information.

**File a new G1 row, `TRUST-REFUTED-PERSIST-1`.** It saves a `refuted` record in `.verified.json`, keyed by `evidenceKey`, so an importer renders the callee `refuted`. The saved meaning is "the body VC is not entailed by the declared contracts" (review H5). A refuted VC is relative to callee contracts and uninterpreted measures, so it is not necessarily a run-time failure. The row reverses refuted-status proposal §3.2 and cites HASH-PRE-ASYM as the reason the reversal is now safe. Next-action marker: **DECIDE**.

## Edge cases and degenerate inputs

1. **Positive witness: the refuted `inc`.** The input is `(def inc [x: int] -> int (pre (>= x 0)) (post (> result x)) x)`. The command is `llmll --json verify inc.llmll --trust-report`. The expected result is exit 1 and one JSON document. Its verdict says refuted, and `trust_report.refuted_fns` is `["inc"]`. Today the command prints `asserted` and exits 0. Channel: trust (the contract-channel verdict is shown on the trust channel). Cite `Main.hs:1938-1959`.
2. **The same function under `--spec-coverage`.** Expected: exit 1, and `spec_coverage` nested in the one document. Today: exit 0 and `Effective coverage: 100% (1/1)`. Channel: trust. Cite `Main.hs:1358-1376`.
3. **A correct `inc` (body `(+ x 1)`) under `--strict-verify --json`.** Expected: exit 0 and one document with `trust_report` and `spec_coverage` keys. Today: exit 0 and three documents. Channel: none (output contract). Cite context item 9.
4. **The solver is absent.** Expected: exit 3 and one document whose verdict says unavailable. No `trust_report` key appears, because no report was computed. The text output names `llmll trust-report` as the way to read saved evidence. Channel: trust. Cite `Main.hs:1530`.
5. **A saved record contradicts the run (SIDECAR-ADMIT-1).** Expected: exit 4 on a run that would otherwise succeed, with the refusal on stderr. This is the only exit that a reporting flag can add. Channel: trust. Cite `Main.hs:3238-3257`.
6. **A `def-shell` or a body that falls back.** No body VC exists, so the function cannot be refuted. It renders `asserted` (or a Leanstral tier under a prover flag), and the exit status does not change. Channel: trust. Cite `LLMLL.md §5.3.4`.
7. **The file fails `check`.** Expected: exit 1 and no report, the same as today. `test_hash_pre_asym.py:243-249` relies on this for its refute-crux fixtures. Channel: type.
8. **`llmll trust-report` on a file with a forged sidecar** (SIDECAR-ADMIT-1 cell A). Expected: `post: asserted`, the footer, exit 0, and the forged record named in `discarded_records`. Channel: trust. Cite `test_sidecar_admit_1.py:80-91`.
9. **An importer whose callee module was refuted.** The callee renders `asserted`, and the caller shows asserted-dependency drift. Under `--strict-verified-core`, the importer refuses. Behaviour is unchanged. Spec is silent (intentional, deferred to `TRUST-REFUTED-PERSIST-1`).
10. **Positive witness for §3.5: a tested record survives a report run.** The input is a fallback function `f` with a post and a `(check …)` property naming `f` as its subject. The steps are `llmll test`, then `llmll verify --trust-report`. Expected: `f` renders `tested`, and the sidecar still holds the record. Today, plain `verify` drops it. Channel: trust. Cite `Main.hs:648-655`, `:1799`.
11. **The same function after a body edit.** After step 10, change `f`'s body and keep the property. Run `llmll verify --trust-report`. Expected: the stamped key no longer matches, so `f` renders `asserted` and `discarded_records` names `f`. Today the solver-less render still shows `tested`. Channel: trust. Cite `TrustReport.hs:840-856`.
12. **A `tested` record written before v0.30.0.** It has no stamped key. Expected: it is demoted on the first read and listed in `discarded_records`. Running `llmll test` again writes a keyed record. Channel: trust (fails closed).
13. **A Leanstral proof after a post edit.** A post proved by Leanstral is then strengthened. Run `llmll verify --trust-report`. Expected: the proof-cache entry's `obligation_hash` differs from the live one, so the post renders `asserted`. Today the upgrade is presence-based and still shows `verified-lean`. Channel: trust. Cite `ProofCache.hs:170-184`.
14. **The positive witness reported on stdout only.** Edge case 1, read by a consumer that ignores the process status. Expected: the document carries `exit_code: 1` and `solver_verdict: "refuted"`. Channel: none (output contract). Cite §3.3.

## Verification mapping

This proposal adds no proof obligation. It changes which runs compute the existing verdict, and how the verdict is reported.

- **Channel:** trust. The `refuted` status is shown on the trust channel and is computed from the contract channel's body VC (refuted-status proposal §5).
- **Fragment:** QF-LIA, auto-discharged by liquid-fixpoint, unchanged. No obligation moves to nonlinear or Lean. Cite `LLMLL.md §5.3.3` and `§5.3.5`.
- **Boundary:** the flag rule in §3.1 is a statement about the CLI, not a judgment. It is checked by tests, not by the solver.

## Affected surface

- `compiler/app/Main.hs`:
  - Delete the two early exits (`:1305-1349`, `:1358-1376`).
  - Fold every `--json` emit on the `verify` path into one document (`:1690-1727`, `:1938-1959`, `:1975-2002`, and the coverage, weakness and obligation emits).
  - Add `trust-report` and `spec-coverage` to the command parser (`:178-227`).
  - Route the discarded-record list to the render.
- `compiler/src/LLMLL/TrustReport.hs`, `SpecCoverage.hs`: add the `discarded_records` field. No change to tiers or the meet.
- §3.5, `tested`: `compiler/src/LLMLL/PBT.hs:805-808` stamps the subject's evidence key. `TrustReport.hs:840-856` (`downgradeStaleSidecar`) checks it. `Main.hs:1755-1799` carries valid records into the SAFE write. The sidecar format gains one optional field on a `tested` record. Increase the sidecar's format marker so an older binary's records read as unkeyed.
- §3.5, `verified-lean`: `compiler/src/LLMLL/ProofCache.hs:170-184` compares `obligation_hash`. `Main.hs:2014-2031` moves out of the `--leanstral` guard. The post-solver renders apply the upgrade.
- `compiler/app/Main.hs:3265`: compute the proof artifact's `composed` versions.
- `docs/llmll-trust-report.schema.json`: add `discarded_records` (optional, additive). Increase `trust_report_version` by a minor version.
- A schema for the `verify --json` document, or a section in `LLMLL.md`, that names the nested keys in §3.3. The engineer and the documentation-lead decide which.
- `LLMLL.md` §4.4.4 (`:632-664`), the `--spec-coverage` section (`:963-1004`), and a new statement of the flag rule. Each is doc-lead's slot after the engineer ships. Correct the drift in context items 6 and 7.
- `README.md:142` (command table) and `:59-63` (the Leanstral demo uses `--trust-report`).
- **Caller migration.** Each line names the caller, what it relies on, and what changes:
  - `scripts/benchmark-totp.sh:73,98` and `scripts/benchmark-erc20.sh:67,92`: they read `.entries` and `.summary` under `set -euo pipefail`. Change them to `.trust_report.*` and `.spec_coverage.*`. A refuted fill now stops the script, which is correct for a benchmark.
  - `tools/llmll-driver/spine.llmll:715-760` (stage L): it parses the whole file with one `json-parse`, and `roots-file` reads the report. Read the nested `trust_report` key. Stage L still ignores the exit status. Today's self-test pins the exit status only.
  - `scripts/tests/test_sidecar_admit_1.py` cell A: move to `llmll trust-report`, assertions unchanged. Add an assertion on `discarded_records`.
  - `scripts/tests/test_hash_pre_asym.py:56-59,243`: the helper is named "the solver-less trust report", and the suite tests that the key check works without the solver. Move it to `llmll trust-report`, unchanged.
  - `scripts/tests/test_trust_axiom_1.py` cell 4 (`:153-165`): it pins the sidecar-only path. Move it to `llmll trust-report`. Cells 1 to 3 and 5 use `--strict-verify` and need the nested key.
  - `scripts/tests/test_headline_term_1.py:308` and `test_partial_fns_graph_1.py:149`: each scans stdout lines for an object with a given key. The keys move under `trust_report`. Update the helper or switch to the subcommand. Each test already runs `verify` first, so either choice works.
  - `scripts/tests/test_rfc_pipeline_integration.py:228-235`: a stub `llmll`. Update the stub to the nested shape so that it still models stage L.
  - `scripts/tests/test_rfc_coverage.py`: no change. Its `--trust-report` is an argument of `scripts/rfc_coverage.py`, not of `llmll`.
  - `compiler/test/Spec.hs:4767` and the JSON-shape cells (`:2052`, `:5229-5265`, `:14540`, `:14776`): audit each for a call through the CLI path. Pure `TrustReport` unit tests are unaffected.
- **New gates.**
  - A flag-law test: for each flag, run the positive witness (edge case 1) and its correct twin. Assert both lines of the §3.1 law.
  - A document-count test: `verify --json` with every report flag prints one top-level document, and its `exit_code` equals the process status.
  - An evidence-carry test: edge cases 10 to 13.

No new builtin, construct, FFI tier or capability.

## Risks and open questions

1. **Every JSON consumer of `verify` must migrate at once.** Class: scope. Cite: the caller list in "Affected surface". Bite: complicates the release. The list above is the full in-tree set, found by grep. Out-of-tree agents that parse `verify --trust-report --json` break silently on `.entries`. The CHANGELOG entry must name the new key path and the subcommand.
2. **Cost on large files.** Class: verification-ergonomics. Cite: context item 13 and `VERIFY-MEMORY-1`. Bite: only matters at scale. On the in-tree benchmarks the solver adds 0.05 to 0.5 s. A caller that polls a large file moves to `llmll trust-report`, which is now named for that use.
3. **Exit 4 stays the one exception.** Class: spec-drift. Cite: `Main.hs:3238-3257`. Bite: does not block. The alternative is to run the contradiction check in plain `verify` too, so the rule needs no exception. Plain `verify` loads no records to render, so the check would refuse nothing that it reports. Keeping the exception is the smaller change.
4. **The verdict object's own shape becomes a public contract.** Class: spec-drift. Cite: `Main.hs:1690-1727` (the object has no schema file today). Bite: complicates the change. It must carry a version field before reports nest under it.
5. **Existing `tested` tiers drop once at upgrade.** Class: scope. Cite §3.5 and edge case 12. Bite: complicates the release. Every `tested` record written before v0.30.0 has no key, so it demotes until `llmll test` runs again. This is the fail-closed choice. The CHANGELOG must say it, and the benchmark scripts must run `llmll test` before they read tiers if they count `tested`.
6. **Report runs now refuse Leanstral proofs of edited functions.** Class: scope. Cite edge case 13. Bite: only matters at scale. Today such a post shows `verified-lean` for code the proof never saw, so the change removes an incorrect claim. A user runs `--leanstral` again to restore it.
7. **Stage L may want the subcommand, not `verify`.** Class: scope. Cite: `spine.llmll:712-713` ("verify the frozen TFTP root surface"). Bite: does not block. The comment says verify, so this proposal keeps `verify` there. If stage L only wants the list of roots, `llmll trust-report` is cheaper and keeps today's shape.

## Professor review fold

| Review finding | Disposition |
|---|---|
| H1, two JSON documents | Adopted as §3.3, widened to every flag set (three documents measured under `--strict-verify`) |
| H2, `--spec-coverage` | Adopted in §3.2 and §3.4 |
| H3, the flag rule | Adopted as §3.1. Classes were added because `--strict-verified-core` must be able to fail a passing run |
| H4, drop option (c) | Adopted in §3.6 |
| H5, save `refuted` | Filed as `TRUST-REFUTED-PERSIST-1`, out of scope here |
| H6, cost | Measured (context item 13). Risk 2 |
| H7, sidecar write | Stated in §3.2 |
| Open question 1 | Answered in §3.1 |
| Open question 2 | Answered in §3.4 |
| **Review Rev 1** | |
| R1-1, a report run erases `tested` | Adopted as §3.5 by user decision. Widened: neither non-solver tier had a key to check, so §3.5 adds one for each (context items 15 and 16) |
| R1-2, `exit_code` in the envelope; stream alternative | Adopted in §3.3, with the stream recorded as rejected alternative 2 |
| R1-3, composed versions; proof-artifact constants | Adopted in §3.3 and "Affected surface" |
| R1-4, the monotone law | Adopted as §3.1. Exit 4 is no longer an exception |

## Revision log

- **Rev 0 → Rev 1 (2026-10-14).** Folds review Rev 1. §3.1 now states one law with two lines. §3.3 adds `exit_code`, `solver_verdict`, a computed `composed` block and the rejected stream alternative. New §3.5 keeps non-solver evidence across a SAFE write. Reading for §3.5 found that a `tested` record has no evidence key and that the `verified-lean` upgrade checks no hash. Each check is added, and each fails closed. The importer section moves to §3.6. Edge cases 10 to 14 and risks 5 and 6 are new.
- **Rev 1 settled (2026-10-14)** by the user, without further change.

## Hand-off

**To the compiler-engineer (code track).**

*What is settled:* Rev 1 of this file. The professor review [`trust-report-gate-1-review.md`](trust-report-gate-1-review.md) (Rev 0 and Rev 1) is complete and ready for fold-and-archive by the documentation-lead after the release.

*Surface:*
- `verify --trust-report` and `verify --spec-coverage` run the solver. Both early exits go (`Main.hs:1305-1349`, `:1358-1376`).
- New subcommands `llmll trust-report <file>` and `llmll spec-coverage <file>` take the solver-less render. They exit 0, keep the footer, print today's bare JSON shape, and list `discarded_records`.

*Exit law (§3.1):*
- No flag changes a non-zero exit.
- On a passing run, reporting and prover flags may add only exit 4. `--strict-verified-core` may add only 1 or 4.

*Output (§3.3):*
- `verify --json` prints one document: the verdict object with `exit_code`, `solver_verdict`, a version field, and a computed `composed` block.
- Each report nests under a fixed key: `trust_report`, `spec_coverage`, `weakness`, `obligation_suggestions`, `obligation_report`, `strict_errors`.
- Fix the proof artifact's hard-coded composed versions (`Main.hs:3265`).

*Evidence (§3.5):*
- `llmll test` stamps the subject's evidence key on `tested` and `tested-joint` records. Reads and the SAFE write keep a record only when a witness is live and the key matches. An unkeyed record fails closed.
- `upgradeLeanstralPosts` requires a matching `obligation_hash` and runs on every SAFE write and every solver-path render.
- Report whether the live obligation hash needs the emitter. If it does, the subcommand does not upgrade.

*Verification mapping:* no new proof obligation. The fragment is unchanged (QF-LIA).

*Modules:* `compiler/app/Main.hs`, `TrustReport.hs`, `SpecCoverage.hs`, `PBT.hs`, `ProofCache.hs`, `VerifiedCache.hs`, `ProofArtifact.hs`.

*Schemas:*
- `docs/llmll-trust-report.schema.json`: add `discarded_records` and increase the minor version.
- The sidecar's format marker increases.
- The `verify --json` document gets a schema or a spec section.

*Callers to migrate:* listed under "Affected surface".

*New gates:* the flag-law test, the document-count test and the evidence-carry test (edge cases 10 to 13).

*Release:* v0.30.0.

*Roadmap (documentation-lead):*
- Move the `TRUST-REPORT-GATE-1` marker from DECIDE to PLAN.
- File `TRUST-REFUTED-PERSIST-1` in G1 with a DECIDE marker (§3.6).
- Add a `docs/design/INDEX.md` row for this proposal.
