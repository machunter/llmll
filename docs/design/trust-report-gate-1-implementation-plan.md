---
title: TRUST-REPORT-GATE-1 — implementation plan
status: Rev 1, APPROVED 2026-10-14 (Rev 0 + amendments A1-A3)
design: trust-report-gate-1-proposal.md Rev 1 (SETTLED, 8a6eeb2)
row: TRUST-REPORT-GATE-1 (G1)
release: v0.30.0
---

# TRUST-REPORT-GATE-1 — implementation plan

## Restatement

The plan implements the settled design [`trust-report-gate-1-proposal.md`](trust-report-gate-1-proposal.md) Rev 1:

- `verify --trust-report` and `verify --spec-coverage` run the solver.
- `verify --json` prints one envelope that carries `exit_code`.
- The solver-less renders move to `llmll trust-report` and `llmll spec-coverage`.
- A SAFE write keeps `tested` and `verified-lean` evidence only when a new key check passes.

The plan is four commits on one branch. Each commit leaves `main` releasable.

## Context located

1. [`trust-report-gate-1-proposal.md`](trust-report-gate-1-proposal.md) Rev 1, "Hand-off": the settled surface, the exit law, the envelope and §3.5.
2. [`trust-report-gate-1-review.md`](trust-report-gate-1-review.md) Rev 0 and Rev 1: the professor findings that the design folds.
3. `compiler/app/Main.hs:1305-1349`, `:1358-1376`: the two early exits to delete.
4. `compiler/app/Main.hs:1459`, `:1498`, `:1683-1727`, `:1737`, `:1832-1841`, `:1930`, `:1950`, `:1980-1985`: every stdout JSON emit on the `verify` path after type-check. Today they print up to four documents.
5. `compiler/app/Main.hs:1498-1530`: solver absent. Prints a JSON object and exits 3.
6. `compiler/app/Main.hs:1755-1799`: the SAFE branch builds `provenCS` and writes it with `saveVerifiedWithAxioms`, which replaces the file (`VerifiedCache.hs:421-433`).
7. `compiler/app/Main.hs:61-90` (`doTest`): has `stmts` and `cache` and calls `pbtTrustWriteback` (`PBT.hs:795-830`). It builds no `KeyEnv` today.
8. `compiler/src/LLMLL/Syntax.hs:510-513`: `PbtWitness` has two fields. It has five construction sites. `EvidenceRecord` has 73 positional construction sites, so the key goes in the witness, not the record.
9. `compiler/src/LLMLL/TrustReport.hs:898-948` (`downgradeStaleVerifiedSidecarIn`): the read check with a `KeyEnv`. It returns tests as positive-tier only (`:930`). Callers: `Main.hs:1283`, `loadCheckedSidecar` (`Main.hs:3225`), `ProgramGraph.hs:63`.
10. `compiler/src/LLMLL/TrustReport.hs:840-856` (`downgradeStaleSidecar`): the witness liveness check, inside `buildTrustReport`, which has no `KeyEnv`.
11. `compiler/src/LLMLL/TrustReport.hs:571`: `tested-joint` is assigned at report time from `tested` records. It is never saved. So §3.5 needs no separate check for it.
12. `compiler/src/LLMLL/ProofCache.hs:48-53`, `:109-113`, `:170-184`: `ProofEntry` carries `peObligationHash`. `lookupProof` checks it. `upgradeLeanstralPosts` does not.
13. `compiler/app/Main.hs:2186-2188`: the obligation hash is `computeObligationHash` of the theorem text from `translateObligation name params ret contract body`. **That is a pure function of the def. The live hash does not need the emitter.** The subcommand can apply the check. This answers the design's open item in §3.5.
14. `compiler/app/Main.hs:3265`, `ProofArtifact.hs:205-208`: hard-coded composed versions. The live constants are `trustReportEmitVersion = "1.9.0"` (`TrustReport.hs:427`) and `expectedSchemaVersion = "0.12.0"` (`ParserJSON.hs:74`).
15. `compiler/src/LLMLL/VerifiedCache.hs:340-344`, `:370`: `checkerSoundnessVersion = "2"` gates revalidation of a whole sidecar.
16. `compiler/test/Spec.hs`: no test runs the `verify` CLI. Tests call library functions, so only the JSON-shape and the `downgrade*` cells change.
17. `scripts/fallback_census.py:142-175`: runs `--json verify --strict-verified-core` and takes the last JSON line with `body_faithful`. The envelope keeps the verdict keys at the top level, so the census needs no change.
18. `scripts/tests/test_sidecar_admit_1.py:28-30`: the CLI pytest suites skip without `LLMLL_BIN`. The `spec-roundtrip` CI job sets it. The `version-gate` job does not.
19. Baseline measured on 2026-10-14, at code identical to `main` (4da84c9): `stack test` **2299 examples, 0 failures**; `python -m pytest scripts/tests/` with `LLMLL_BIN` set **442 passed, 5 skipped** (356 s).

## Plan summary

Four commits, in this order:

1. **C1, artifact versions:** compute the composed versions from the live constants.
2. **C2, evidence key checks (§3.5):**
   - `PbtWitness` gains the subject's evidence key.
   - The read check and the SAFE write accept a `tested` record only when the key matches.
   - `upgradeLeanstralPosts` takes a map of live obligation hashes and runs on every SAFE write and solver-path render.
3. **C3, subcommands:** `llmll trust-report` and `llmll spec-coverage` take over the solver-less render with `discarded_records`. The tests that pin that render move to them.
4. **C4, the flip:** delete the two early exits. Route every `verify --json` emit through one envelope printer. Migrate the callers.

C2 lands before C4 because C4 makes every report run write the sidecar. Without C2, C4 erases `tested` evidence. The cost is mostly in C4's envelope refactor of `doVerify`, which has fifteen exit and emit points. Runtime cost: 0.05 to 0.5 s per report call on the in-tree inputs (design, context item 13).

## Affected surface

### C1. Proof artifact composed versions

- `compiler/app/Main.hs:3265`: replace the literals with `trustReportEmitVersion` and `expectedSchemaVersion`.
- `compiler/src/LLMLL/ProofArtifact.hs:207`: update the comment, which says "1.4.0 at time of writing".
- `compiler/test/Spec.hs`: one cell asserts that the composed versions equal the live constants.
- Replay of an artifact minted before C1 still reads it. `composed` is informational, and `llmll replay-artifact` does not gate on it. The engineer confirms this at implementation, and a replay test of an old artifact covers it.

### C2. Evidence key checks (design §3.5)

- `compiler/src/LLMLL/Syntax.hs:510-513`: `PbtWitness` gains `pwSubjectKey :: Maybe Text`. The five construction sites change.
- `compiler/src/LLMLL/VerifiedCache.hs:197-200` and the reader at `:145-150`: the JSON form gains an optional `subject_key`.
- `compiler/src/LLMLL/PBT.hs:795-830` (`pbtTrustWriteback`) gains an argument: a function from a subject name to its live key.
- `compiler/app/Main.hs:61-90` (`doTest`) builds the key map. It runs `typeCheckWithCacheRet` and `buildKeyEnv`, as `doVerify` does at `:1281-1282`.
  - A subject in the entry module uses the entry `KeyEnv`.
  - A subject in an imported module uses `moduleKeyEnv cache m` (the qualified-key case, `PBT.hs:808`).
- `compiler/src/LLMLL/TrustReport.hs:898-948` (`downgradeStaleVerifiedSidecarIn`) gains a branch for a `tested` record. It is valid only when a witness has `pwSubjectKey == Just live` for the record's name, using the plain key variant. Otherwise the record is demoted to `asserted`, with a diagnostic.
  - The existing property-body liveness check in `downgradeStaleSidecar` (`:840-856`) stays. A record must pass both checks.
  - The function returns `[(Name, Text)]` in place of `[Text]`, so C3 can build `discarded_records`. Its three callers change.
- `compiler/src/LLMLL/ProofCache.hs:170-184`: `upgradeLeanstralPosts` gains a first argument `Map Name Text`, the live obligation hashes. An entry upgrades a post only when `peObligationHash` equals the live hash.
- A new pure helper builds that map: `liveObligationHashes :: [Statement] -> Map Name Text`. It maps each `normalizeDefOrLetrec` def through `translateObligation` and `computeObligationHash`. It lives in `Main.hs` beside `runLeanstralPipeline`, which uses the same pair (`:2186-2188`). A `LeanUnsupported` result gives no entry, so that post never upgrades.
- `compiler/app/Main.hs:1755-1799`, the SAFE write:
  - Load the pre-run sidecar's `tested` records that pass the C2 check.
  - Write `upgradeLeanstralPosts live pc (Map.unionWith mergeCS provenCS validTested)`.
  - `mergeCS` (`Module.hs:374-387`) keeps `verified` over `tested` and `tested` over `asserted`.
  - The re-stamp at `:2014-2031` is no longer under the `--leanstral` guard. The upgrade now happens at the write.
- `compiler/app/Main.hs:1945-1952`, `:1975-1979`: the post-solver renders apply `upgradeLeanstralPosts live pc` to the loaded sidecar, as the solver-less render does at `:1337`.
- `compiler/src/LLMLL/VerifiedCache.hs:370`: change `checkerSoundnessVersion` from `"2"` to `"3"`. A sidecar written by an older binary then reads as needing revalidation. Its `tested` records have no `subject_key` and demote in any case.

### C3. Subcommands

- `compiler/app/Main.hs:178-227`: add `command "trust-report"` and `command "spec-coverage"`. Each takes a file argument and the global `--json`.
- New `doTrustReport` and `doSpecCoverage` in `Main.hs`. Each moves code from the early exits at `:1305-1349` and `:1358-1376` unchanged, then adds:
  - the C2 `upgradeLeanstralPosts live pc`, in place of the presence-based upgrade at `:1337`;
  - the discarded list from C2's `[(Name, Text)]`, rendered as `records discarded (key mismatch): N` in text and `discarded_records` in JSON;
  - the existing footer, unchanged.
- Each subcommand exits 1 if type-check fails, as `verify` does. Otherwise it exits 0. No solver, no emitter and no sidecar write.
- `compiler/src/LLMLL/TrustReport.hs` (`formatTrustReportJson`, `formatTrustReport`): an optional `discarded_records` field, emitted only when non-empty. Increase `trustReportEmitVersion` from `1.9.0` to `1.10.0`.
- `compiler/src/LLMLL/SpecCoverage.hs` (`formatCoverageJson`): the same optional field.
- `docs/llmll-trust-report.schema.json`: add `discarded_records` (array of strings, optional). Increase the version. This doc is allowed in the engineer's change set because it ships with the field.
- In C3, `verify --trust-report` and `verify --spec-coverage` still early-exit. The tree has both paths for one commit.
- The pytest suites that pin the solver-less render move to the subcommand, with assertions unchanged:
  - `scripts/tests/test_sidecar_admit_1.py` cell A (`:80-91`), plus an assertion on `discarded_records`;
  - `scripts/tests/test_hash_pre_asym.py` `_report` (`:56-59`) and `:243`;
  - `scripts/tests/test_trust_axiom_1.py` cell 4 (`:153-165`).

### C4. The flip and the envelope

- `compiler/app/Main.hs:1305-1349`, `:1358-1376`: delete both early exits. `--trust-report` and `--spec-coverage` then defer to the post-solver path, as they already do under `--cdp` and `--strict-verify`.
- The post-solver trust render today exists only under `cdpFlag` (`:1938`) or `strictCore` (`:1965`). Add the plain case: render without `discriminative_axis`, through the same marker chain as `:1945-1952`.
- **The envelope.**
  - Add a local accumulator in `doVerify`: an `IORef [(Key, Value)]` for nested reports.
  - Add one printer, `finishVerify :: ExitCode -> IO a`. It prints the envelope and exits.
  - Every JSON emit in context item 4 appends its value under its §3.3 key instead of printing.
  - Every exit after type-check goes through `finishVerify`: `:1482`, `:1530`, `:1629`, `:1959`, `:1998`, `:2035-2037`. So does `contradictionExit` (`:3250-3257`), which keeps its stderr message and passes code 4.
  - `exit_code` is the argument of `finishVerify`, so it cannot differ from the process status.
- The envelope's top level, in this order:
  - `verify_json_version: "1.0.0"`;
  - `exit_code`;
  - `solver_verdict`;
  - `composed`: `trust_report_version` from `trustReportEmitVersion`, `schema_version` from `expectedSchemaVersion`, `obligation_report_schema_version` from `ObligationAssembly.hs:1251` when that report is present;
  - every key of today's verdict object (`:1683-1727`), unchanged, so `fallback_census.py` still works (context item 17);
  - the nested report keys: `trust_report`, `spec_coverage`, `weakness`, `obligation_suggestions`, `obligation_report`, `strict_errors`.
- **`solver_verdict` gets one new value, `not-run`.** The design names `safe`, `refuted` and `error`. Two exits come before any verdict: the pre-solver strict-core refusal (`:1459-1482`) and solver absent (`:1498-1530`). Both use `not-run`. This is additive and is flagged to the documentation-lead as a spec detail the design did not pin.
- **The text mode stays as today,** except the deleted footer lines. Under `--trust-report`, the report prints after the solver lines. The footer belongs to the subcommand.
- **Callers:**
  - `scripts/benchmark-totp.sh:73,98-103` and `scripts/benchmark-erc20.sh:67,92` and following: change the jq paths to `.trust_report.*` and `.spec_coverage.*`. Each script runs `llmll test` before `verify` if it counts `tested` (design risk 5). If neither script counts `tested`, it is left alone. The engineer records which.
  - `tools/llmll-driver/spine.llmll:735-760`: `roots-file` and `root-count` read `trust_report` from the parsed envelope. Rebuild the driver binary and run `self_test`.
  - `scripts/tests/test_headline_term_1.py:308-316` and `test_partial_fns_graph_1.py:149`: the `_json` helpers find `trust_report_version` and `partial_fns` under `trust_report`. Each test already runs `verify` first, so the expected values are unchanged.
  - `scripts/tests/test_trust_axiom_1.py` cells 1 to 3 and 5: the helper at `:131-138` finds the trust report under `trust_report`.
  - `scripts/tests/test_rfc_pipeline_integration.py:228-235`: the stub prints the envelope shape.
  - `scripts/tests/test_rfc_coverage.py`: no change (not an `llmll` caller).
- `README.md`, `LLMLL.md` §4.4.4 and the `--spec-coverage` section, `CHANGELOG.md` and the roadmap are documentation-lead scope. They are listed in the hand-off.

## Verification impact

- **Solver time:** no change per solver run. The number of solver runs increases: each `verify --trust-report` and `verify --spec-coverage` call now runs one. On the in-tree inputs the call costs 0.10 to 0.24 s, against 0.05 to 0.11 s for the solver-less render (design, context item 13).
- **New obligations:** none. No VC changes. The `.fq` output is byte-identical, and C4 checks this on the three inputs.
- **Trust model:**
  - `tested` now requires a key match. That removes `tested` from a function whose body changed after the test.
  - `verified-lean` now requires an obligation-hash match.
  - Both changes only lower tiers. Neither raises any tier.
  - A SAFE write carries forward `tested` records, which raises the persisted tier in the order `test` then `verify` back to what `verify` then `test` already gives.
- **Fragment:** QF-LIA, unchanged (`LLMLL.md §5.3.3`, `§5.3.5`).
- **Strict-verified-core:** no function newly falls back. The admission leg (`TypeCheck.checkCalleeAdmissibility`) reads `verified` with `erVerifiedHash` only. C2 does not touch `erVerifiedHash`, so admission is unchanged. This is the reason the key goes in `PbtWitness`, not in `erVerifiedHash`.

## Performance budget

- **GHC build:** C2 changes `Syntax.hs` (`PbtWitness`), which most modules import. Expect a full rebuild of `compiler/src`, one time. C1, C3 and C4 change `Main.hs` and three leaf modules.
- **Test runtime:** about 25 new hspec examples, all pure, under 1 s in total. The new pytest cells run the binary: about 15 calls at 0.1 to 0.3 s each.
- **Compiler runtime:**
  - `llmll test` gains one non-strict type-check pass for the key map. It is lazy, and the test run is dominated by the build of the test harness.
  - `verify` on SAFE gains one sidecar read and `liveObligationHashes`, which runs `translateObligation` once per def. That is linear in defs and not measured yet. C2 measures it on the TFTP roots file (22.6 KB). If it exceeds 50 ms, the engineer restricts it to defs that have a `/post/` entry in the proof cache.
  - `llmll trust-report` costs the same as today's solver-less render.
- **Sidecar size:** one `subject_key` string (71 bytes) per witness.
- **Cache effect:**
  - Every pre-v0.30.0 `tested` record demotes once.
  - `checkerSoundnessVersion` 3 forces revalidation of every old sidecar on first read. Revalidation is a read-side check, not a solver run.
  - A `verified-lean` post whose obligation changed loses the tier until `--leanstral` runs again.

## Contract plan

This change lands nothing in the provable fragment. Every change is in the Haskell compiler (`compiler/app/Main.hs` and modules under `compiler/src/LLMLL/`), outside LLMLL's verified surface. The one LLMLL source change is `spine.llmll` stage L. It is a `def-shell` driver path, and its two helpers carry no contracts today. The edit changes only a JSON field path.

## Test plan

**Baseline, measured 2026-10-14 at code identical to `main` (4da84c9):** `stack test` 2299 examples, 0 failures. `python -m pytest scripts/tests/` with `LLMLL_BIN` set: 442 passed, 5 skipped.

**New hspec cells (`compiler/test/Spec.hs`), about 25:**
- C1: composed versions equal `trustReportEmitVersion` and `expectedSchemaVersion` (1).
- C2, `PbtWitness` JSON round-trip with and without `subject_key` (2).
- C2, `downgradeStaleVerifiedSidecarIn` on `tested` (4):
  - key match keeps the record;
  - key mismatch demotes it;
  - absent key demotes it;
  - the diagnostic names the function.
- C2, the witness check and the key check together: a live property with a changed function body demotes the record (1).
- C2, `upgradeLeanstralPosts` (3): hash match upgrades; mismatch does not; a tainted proof does not, whatever the hash.
- C2, `liveObligationHashes` (2): equals `computeObligationHash` of `translateObligation` for a def; omits a `LeanUnsupported` def.
- C2, carry-forward (3):
  - `mergeCS` of `provenCS` with valid `tested` keeps `verified` over `tested`;
  - keeps `tested` over `asserted`;
  - drops an invalid record.
- C3: the trust-report and coverage JSON emit `discarded_records` only when non-empty (2). The schema-drift cell at `Spec.hs:5239-5265` still passes against the updated schema.
- C4: the envelope builder (7):
  - key order;
  - `exit_code` equals the argument;
  - each nested key appears only when its flag is set;
  - `not-run` on the two pre-verdict exits;
  - `composed` values;
  - every verdict key from today is still present.

**New pytest cells, `scripts/tests/test_trust_report_gate_1.py` (runs under `LLMLL_BIN`, about 14):**
- **Flag law** (design §3.1). Use the refuted `inc` and the correct `inc`. For each flag in the three classes, assert both lines of the law against plain `verify`. One parametrized cell per flag: 10 flags plus `--leanstral-mock`. The design's positive witness is edge case 1.
- **Document count:** `verify --json` with `--strict-verify --obligation-report` prints exactly one top-level JSON value, and its `exit_code` equals the process status (design edge cases 3 and 14).
- **Evidence carry** (design edge cases 10 to 13):
  - `test` then `verify --trust-report` shows `tested`;
  - a body edit then `verify --trust-report` shows `asserted` and `discarded_records`;
  - a hand-written pre-v0.30.0 record with no `subject_key` demotes;
  - a `--leanstral-mock` entry with an edited obligation does not upgrade. The mock is tainted, so this cell writes a non-tainted `leanstral` entry into `.proof-cache.json` directly.
- **Subcommands:** `llmll trust-report` on a forged sidecar matches cell A. `llmll spec-coverage` on the refuted `inc` exits 0 and prints the footer.

**Moved pytest cells:** listed in C3 and C4. Their assertions are unchanged except the JSON path.

**End to end:**
- `scripts/benchmark-totp.sh` and `scripts/benchmark-erc20.sh` pass.
- `tools/llmll-driver` `self_test` passes with stage L on the envelope.
- `.fq` byte-identity holds on the three inputs, before and after C4.

**Target:** `stack test` at least 2324 (2299 + about 25), 0 failures. The pytest count increases by about 14 plus parametrized cases, 0 failures.

## Rollback

- **Commits:** each commit reverts alone in reverse order, C4 then C3, C2, C1.
  - Reverting C4 alone restores the early exits. The subcommands stay, which is harmless.
  - Reverting C2 alone is not safe after C4, because C4 then erases `tested`. Revert C4 first.
- **No flag:** the change is not behind a flag. A flag would keep the defect reachable, which the design rejects.
- **Saved files in user environments:**
  - Sidecars written by v0.30.0 carry `subject_key` and `checkerSoundnessVersion` 3. An older binary reads `subject_key` as an unknown key and ignores it. It reads version 3 as "needs revalidation" (`VerifiedCache.hs:343` compares for inequality) and revalidates. No crash and no false tier.
  - `.proof-cache.json` does not change shape.
- **Worst-case unwind:** revert four commits and release v0.30.1. Users lose `tested` tiers once more and run `llmll test` again.

## Risks and unknowns

1. **The envelope refactor touches fifteen exit points in a 900-line function.** Class: build. Cite: context item 4 and `Main.hs:1252-2040`. Bite: complicates C4. The document-count and flag-law pytest cells catch a missed exit. The `finishVerify` single printer is the structural guard: no `TIO.putStrLn` of a JSON value remains in `doVerify` after C4, and a grep in the C4 test gate checks it.
2. **Importers may read `tested` without the new check.** Class: verification. Cite: `ProgramGraph.hs:63` applies `downgradeStaleVerifiedSidecarIn`. The module loader's own read of `meContractStatus` is not audited yet. Bite: complicates C2. C2 starts by listing every read of a dependency's sidecar. Each read either applies the check or is shown not to render tiers.
3. **`liveObligationHashes` cost on large modules.** Class: performance. Cite: `translateObligation`, called once per def. Bite: only matters at scale. Measured in C2, with a mitigation named in "Performance budget".
4. **`not-run` is a new `solver_verdict` value.** Class: spec-drift. Cite: design §3.3, which lists three values. Bite: does not block. It is additive and goes to the documentation-lead.
5. **The `spine.llmll` edit needs a driver rebuild.** Class: build. Cite: `tools/llmll-driver/spine.llmll:735-760`. Bite: complicates C4. The driver binary is rebuilt by the existing `tools/` build path, and `self_test` gates it.
6. **The benchmarks may count `tested`.** Class: scope. Cite: design risk 5. Bite: only matters if they do. C4 records whether they do, before it changes them.

## Hand-off notes (filled at implementation)

- Pytest baseline: 442 passed, 5 skipped (2026-10-14). Re-measured at implementation against a copy of the 0.29.1 binary built from 8a6eeb2: 442 passed, 5 skipped (365 s). `stack test` baseline re-measured: 2299 examples, 0 failures.
- C2 measurement of `liveObligationHashes` (cold first call, compiled library, `stack exec runghc` harness): `tftp.llmll` 0.52 ms (23 defs, 0 translate to Lean, so the map is empty), `totp_filled.ast.json` 0.015 ms (6 defs, 0 translate), `erc20_filled.ast.json` 0.36 ms (6 defs, 1 translates). All far under the 50 ms threshold, so the mitigation (restrict to defs with a `/post/` proof-cache entry) was not applied. The binding is lazy in `doVerify`, so a run with no proof-cache entry never forces it.
- Importer read audit (risk 2). Every read of a sidecar, and whether it renders a tier:
  - `Module.hs:202-210` (the module loader) merges a dependency's sidecar raw into `meContractStatus`. Its consumers:
    - `TrustReport.collectAllContractStatus` (`:1061`) runs `downgradeStaleVerifiedSidecarIn` with `moduleKeyEnv` over each cached module, so the C2 `tested` check applies to every imported module's own records. Covered.
    - `ProgramGraph.validated` (`:63`) runs the same check and then reads `positiveTier` only, which is false for `tested`. Covered and renders no tested tier.
    - `Main` build paths (`:746`, `:827`) pass it to `instrumentContracts`, which strips a runtime check only for `isVerifiedLevel && erBodyFaithful`. Does not read `tested`.
    - **Not covered:** `TypeCheck.hs:1636` seeds `tcContractStatus` from it raw, and `emitTrustGap` (`TypeCheck.hs:1411-1424`, call site `:2816-2818`) reads the callee's level. A stale imported `tested` record changes the cross-module trust-gap WARNING's text from `asserted` to `tested`, and a `(trust f :level tested)` declaration silences that warning on a record the C2 check would demote. It is a warning only: no report tier, no exit status, no admission. Left as is (applying the check in the loader or the type-checker is outside the plan's surface).
  - Entry-sidecar reads in `Main.hs`: `:1283` (pre-strict-check, checked), `loadCheckedSidecar` (checked), the deferred coverage (`:1923`, checked), the new subcommands (checked). The `--obligations` read (`:1734`) is raw but `mineObligations` reads only `teDeps` (call-graph names), never a tier. `doTest` (`:651`) reads raw to merge before a write; every later read checks.
  - **Finding (imported subjects):** `llmll test` writes a `tested` record for an imported subject under the qualified key (`lib.sq`, `PBT.buildQualMap`) in the ENTRY sidecar, stamped with the key from `moduleKeyEnv` as planned. The planned read check looks the record's name up in the entry module's plain key map, which has no qualified names, so such a record always demotes ("no live definition for this name"). Fail-closed and sound, but the stamped key is never used. Measured: baseline renders `lib.sq` as `tested-joint`, C2 renders `asserted`. Resolving it needs the read check to resolve a qualified name through the module cache, which changes `downgradeStaleVerifiedSidecarIn`'s inputs; not done.
    **Resolved by amendment A2:** `downgradeStaleVerifiedSidecarIn` now takes the `ModuleCache` and resolves a `tested` record's name that is not a local definition through the defining module's `moduleKeyEnv` (`TrustReport.qualifiedPlainKey`). Measured: a matching `lib.sq` renders `tested-joint` again, and an edit of `lib`'s body demotes it and lists `lib.sq` in `discarded_records`. hspec GT-18, pytest `test_e10b_an_imported_subject_keeps_its_tested_record` (fails on the pre-A2 binary).
- Benchmarks (risk 6): neither `scripts/benchmark-totp.sh` nor `scripts/benchmark-erc20.sh` counts `tested`. They read `.entries | length`, `.summary.no_contract`, `.summary.drifts`, `.suppressions | length`, `pre_source`/`post_source` presence, and the coverage `summary.contracted/suppressed/unspecified/total/effective_coverage`. No `llmll test` step is needed.

## Rev 1 amendments (approved 2026-10-14, after C1 to C3)

- **A1, C4 caller list.** Rev 0 missed these consumers of the `verify --trust-report --json` shape. Each one reads `.trust_report` from the C4 envelope, so it sees the report only after a solver pass:
  - `scripts/rfc_coverage.py` (top-level `entries`);
  - `tools/llmll-driver/sequencer.llmll` stage L (with `spine.roots-file`);
  - `scripts/rfc_to_implementation.py` stage L and `self_test`;
  - `scripts/tools_verification.py` (it counts zeros silently on a missed key);
  - `experiments/repair-loop/targets/llmll.json`.
  The switch to `llmll trust-report` is rejected because it restores the ungated report.
- **A2, imported `tested` subjects (C2 fix).** `downgradeStaleVerifiedSidecarIn` looks a qualified name such as `lib.sq` up in the key env of the module that defines it (`moduleKeyEnv`), not only in the entry module. Add one hspec cell and one pytest cell: a qualified `tested` record with a matching key renders `tested-joint`.
- **A3, tracked sidecars.** With `checkerSoundnessVersion` "3", regenerate the 5 tracked `.verified.json` files on the branch with the new binary. After C4, `verify --trust-report` in stage L and the driver `self_test` writes `examples/tftp_rfc1350/roots/tftp.llmll.verified.json`. The regenerated file is the expected output.
- **Not changed:** `TypeCheck` seeds the callee status raw for `emitTrustGap` (a warning only). This goes to a follow-up row through the documentation-lead. `llmll spec-coverage` keeps no footer, as the old render had none.
- **Target:** `stack test` at least 2325, 0 failures.

## Hand-off notes for the amendments and C4 (filled at implementation)

- **A2 state** (`after-C2b.patch`): hspec 2319, 0 failures; pytest 451 passed, 5 skipped; 213 warnings, none new.
- **A1 callers migrated:** `scripts/rfc_coverage.py`, `tools/llmll-driver/spine.llmll`, `tools/llmll-driver/sequencer.llmll`, `scripts/rfc_to_implementation.py`, `scripts/tools_verification.py` and `experiments/repair-loop/targets/llmll.json`.
  - `rfc_coverage.py` takes `trust_report` out of a document that carries `verify_json_version`. It uses any other document as a bare report, so `test_rfc_coverage.py`'s fixtures are unchanged. An envelope with no report yields no entries, so RFC-COV-1 fails closed.
  - `sequencer.llmll` reads the report through `spine.roots-file`, so only its comment changed.
  - The repair-loop target JSON only names the argv. The readers are `experiments/repair-loop/scripts/run_repair_loop.py` and `evaluate_run.py`, and both now take `.trust_report` out of the envelope.
  - **Also needed, not in A1:** `scripts/driver_ll_cover.py` cell L1 reads `entries` out of stage L's `trust-report.json`. It now reads `.trust_report.entries`.
- **A3:** the 5 tracked sidecars were regenerated with the C4 binary. In each one, only `checker_soundness_version` changed ("2" to "3"). `examples/tftp_rfc1350/roots/tftp.llmll.verified.json` is gitignored (`.gitignore:25`), so the stage L and self_test rewrite of it does not dirty the tree.
- **C4 structure:**
  - New leaf module `LLMLL.VerifyEnvelope`, registered in both `package.yaml` and `llmll.cabal`. It holds the pure builder and renderer, so the 7 envelope cells can be tested from Spec.
  - It renders the object by hand, because an aeson `Object` sorts its keys.
  - The verdict keys come from `toJSON report` and the body metadata, in the pre-v0.30.0 order.
  - `doVerify` uses three `IORef`s, `finishVerify :: ExitCode -> IO a`, and `postSolverExit`, which renders any deferred `--spec-coverage` and then finishes.
  - `contradictionExit` takes the finish callback.
- **C4 deviations:**
  - The Leanstral pipeline and the re-stamp moved ahead of the report renders. On SAFE only, as before. The post-solver trust render exits on the verdict, so without the move `--leanstral --trust-report` would skip the prover that the deleted early exit used to run.
  - `--json --obligations` now emits `obligation_suggestions`. The old JSON emit sat inside the text-mode branch and never printed.
  - `weakness` nests whenever the check ran, with an empty list when it found nothing.
  - `--spec-coverage` renders on every post-solver exit, refuted included (design edge case 2).
  - The solver-absent banner names `llmll trust-report` (design edge case 4).
  - The non-strict `--obligation-report` exit is unchanged in flow. It exits before the trust, CDP and weakness renders, as it did before, so those keys are absent there.
- **(d) `.fq` identity:** baseline and C4 outputs are byte-identical on `totp_filled.ast.json`, `erc20_filled.ast.json` and `tftp.llmll`, with and without `--trust-report`.
- **(e) grep gate:** in `doVerify` the only stdout print of a JSON value is `renderEnvelope` in `finishVerify`. The two remaining `TIO.putStrLn reportText` calls are the text-mode branches of `if json` (the obligation report prints in text mode, as before).
- **Final gate:**
  - `stack build`: 213 warnings, none new.
  - `stack test`: 2326 examples, 0 failures.
  - pytest with `LLMLL_BIN`: 477 passed, 5 skipped.
  - Benchmarks: TOTP 14/0, ERC-20 11/0.
  - Driver: `driver_ll_cover.py` 81 passed, 0 failed, with the sequencer rebuilt from the edited sources; `spine.llmll` and `sequencer.llmll` verify SAFE.
  - `rfc_to_implementation.py --self-test` PASS; `version_gate.sh` PASS.
  - The doc-claims fixtures `termination-unverified-mark` and `effective-level-post-meet` still match their `@expect` substrings.
