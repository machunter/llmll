# Postmortem 001 — CDP-0 baseline halted (F-001 + F-003)

> **Date:** 2026-05-26
> **Status:** **Closed.** F-001 closed by compiler-engineer commit `e5e6d04` (`fix: DiagnosticFQ — initialize reportPhase to "lh-fixpoint" (F-001)`); F-003 closed by harness patch in the experiment-lead session at 2026-05-26T23:35Z (uncommitted `experiments/cdp-0/scripts/cdp_baseline.py:83-100`). Successful re-run documented at [`postmortem-002-cdp-baseline-rerun.md`](postmortem-002-cdp-baseline-rerun.md).
> **Compiler SHA at run time:** `121815a` (LT-CDP feature ship; the F-001 latent bug was unmasked by LT-CDP's `--cdp --trust-report --json` deferred-emit path).
> **Run directories preserved as evidence:** `runs/20260526T202516Z-baseline/`, `runs/20260526T233107Z-baseline/`, `runs/20260526T233313Z-baseline/` — all empty (every fixture failed before per-fixture write).

## Headline finding

CDP-0 baseline harness invoked `python3 experiments/cdp-0/scripts/cdp_baseline.py` against the 6 primary + 30 secondary fixtures defined in [`experiments/cdp-0/manifest.json`](../manifest.json). Across three sequential attempts, **0 of 36 fixture invocations produced a successful CDP measurement**. Two distinct blockers compounded: a latent compiler bug (F-001) and a harness flag-placement bug (F-003). The two masked one another — F-001's fixture-wide crash hid the F-003 misconfiguration. After F-001 fix shipped at `e5e6d04`, the second attempt exposed F-003; after F-003 patch in-session, the third attempt exposed a third bug (cwd-relative path resolution under `stack exec`'s `cwd=compiler/`); after that one-line absolute-path fix, the fourth attempt collected data — documented in postmortem-002.

## Sample composition

- **Total fixture invocations:** 36 × 3 attempts = 108. **Successful CDP measurements collected:** 0.
- **Primary corpus (6):** `b1`, `b3`, `b5`, `totp`, `erc20`, `banking` per [`manifest.json:primary_corpus`](../manifest.json).
- **Secondary corpus (30):** discovered via `examples/**/*.{llmll,ast.json}` minus the `proof_required_test/` and `delegate_demo/` exclusions.
- **Compiler version (all three attempts):** SHA `121815a8c45596f8d125e85b3333bdf7b850582b`, branch `lt-cdp/discriminative-power-axis`, runtime `llmll 0.10.8`.
- **Harness git SHA:** uncommitted across all three attempts; F-003 patch landed in the working tree between attempt 2 and attempt 3.

## Verified findings

### F-001. `fqResultToReport` partial-record crash on `--json verify` SAFE results

**Priority:** Blocker (initial baseline halt)
**Consumer:** compiler-engineer
**Status:** **Closed by commit `e5e6d04`** on branch `fix/diagnosticfq-partial-record` off `lt-cdp/discriminative-power-axis`. CHANGELOG entry at commit `cc712aa` under `### Compiler — fix: DiagnosticFQ partial-record crash on \`--json verify\` SAFE (F-001)`. Four regression tests (DF-1..DF-4) in [`compiler/test/Spec.hs`](../../../compiler/test/Spec.hs) close the test gap.

#### Evidence

[`compiler/src/LLMLL/DiagnosticFQ.hs:95-111`](../../../compiler/src/LLMLL/DiagnosticFQ.hs) (pre-fix) defines `fqResultToReport :: FilePath -> ConstraintTable -> FQVerifyResult -> DiagnosticReport` with three branches (`FQSafe`, `FQUnsafe ids`, `FQError txt`). Each branch constructed `DiagnosticReport { reportDiagnostics = …, reportSuccess = … }` using record syntax, omitting the `reportPhase :: Text` field defined at [`compiler/src/LLMLL/Diagnostic.hs:82-86`](../../../compiler/src/LLMLL/Diagnostic.hs):

```haskell
data DiagnosticReport = DiagnosticReport
  { reportPhase       :: Text
  , reportDiagnostics :: [Diagnostic]
  , reportSuccess     :: Bool
  } deriving (Show, Eq, Generic)
```

GHC fills the omitted field with `⊥` at construction; the exception fires on access. [`compiler/src/LLMLL/Diagnostic.hs:352`](../../../compiler/src/LLMLL/Diagnostic.hs) (`formatReportJson`) accesses it: `[ "phase" .= reportPhase r, ... ]`.

Direct CLI reproduction at SHA `121815a` (pre-fix):

```
$ stack exec llmll -- --json verify ../examples/benchmarks/b1-withdraw.llmll
llmll: src/LLMLL/DiagnosticFQ.hs:(96,3)-(99,5): Missing field in record construction reportPhase
```

GHC's `-Wmissing-fields` warned at compile time (GHC-20125 at lines 96, 102, 108) but was filtered as "pre-existing" during the LT-CDP build inventory. Pre-LT-CDP, the typical `--json verify --trust-report` SAFE path early-exited at [`compiler/app/Main.hs:1078`](../../../compiler/app/Main.hs) before reaching `fqResultToReport`, masking the bug; LT-CDP at commit `121815a` split that early-exit (`when (trustReport && not cdpFlag) $ do { ... }`) so `--cdp --trust-report --json` falls through to the solver loop and hits `formatReportJson`, surfacing the crash.

#### Why we saw what we saw

The CDP-0 harness was the first consumer to exercise `--cdp --trust-report --json` end-to-end across a corpus. The combination is necessary because CDP scores live only in the trust-report JSON's `discriminative_axis` block (engineer-shipped in commit `121815a` itself); collecting them programmatically requires both `--cdp` (to compute) and `--trust-report --json` (to emit). LT-CDP added the only code path that exposes the latent partial-record bug.

#### Closure

Engineer plan delivered the minimal three-line fix (initialize `reportPhase = "lh-fixpoint"` in each branch of `fqResultToReport`), four regression tests, and an end-to-end smoke confirming `--cdp --trust-report --json` returns a valid trust-report JSON with `discriminative_axis` populated. Net build-warning delta: −5. Test count delta: 702 H → 706 H. Shipped on branch `fix/diagnosticfq-partial-record`, commit `e5e6d04`. Documented in CHANGELOG `## Unreleased` at commit `cc712aa`.

### F-003. CDP-0 harness places `--json` after the subcommand; absolute-path resolution missing

**Priority:** Blocker (post-F-001 re-run halt)
**Consumer:** experiment-lead (self-routed; harness owner)
**Status:** **Closed by in-session harness patch** at 2026-05-26T23:35Z. Two-line fix in [`experiments/cdp-0/scripts/cdp_baseline.py:83-100`](../scripts/cdp_baseline.py) (uncommitted; will commit with this postmortem on user authorization).

#### Evidence

After F-001 fix shipped, attempt 2 (`runs/20260526T233107Z-baseline/`) re-ran with the harness unchanged from the prior session. Result: identical 36/36 failure pattern. Direct subprocess reproduction of one fixture revealed two harness-side bugs:

**Bug A — flag placement.** `llmll --help`:

```
Usage: llmll [--version] COMMAND [--json]
```

`--json` is documented as a top-level option, not a `verify`-subcommand option. `verify --help` does not list it. Pre-patch, the harness placed `--json` after `verify`:

```python
# pre-patch
cmd = ["stack", "exec", "llmll", "--",
       "verify", "--cdp", "--trust-report", "--json", rel_path]
```

The compiler rejects this with `Invalid option `--json'`.

**Bug B — cwd-relative path.** Even with `--json` repositioned, attempt 3 (`runs/20260526T233313Z-baseline/`) failed every fixture. Reproduction via subprocess:

```
$ python3 -c "
import subprocess
proc = subprocess.run(
    ['stack', 'exec', 'llmll', '--', '--json', 'verify', '--cdp', '--trust-report',
     'examples/benchmarks/b1-withdraw.llmll'],
    cwd='/Users/burcsahinoglu/Documents/llmll/compiler',
    capture_output=True, text=True)
print(proc.stderr)
"
llmll: examples/benchmarks/b1-withdraw.llmll: openFile: does not exist
```

`stack exec` requires `cwd=compiler/` (where `stack.yaml` lives); the fixture path was relative to repo root. The bug masked itself in my manual smoke (which used `../examples/…`) but fired in the harness path.

#### Why we saw what we saw

I authored the harness in the prior experiment-lead session (2026-05-26 morning) without running `llmll verify --help` to verify flag placement. I had assumed the post-subcommand `--flag` convention from other CLIs without checking the running compiler — violating the skill's "verify against the running compiler" discipline I was applying to docs but not to my own code. The cwd-vs-path mismatch (Bug B) was a related authoring error: the manifest defines fixture paths relative to repo root, but the subprocess was invoked from `compiler/`. Both bugs manifested only after F-001 was fixed, because pre-F-001 every fixture failed before the harness reached the parse logic that would have surfaced the JSON-decode failure.

#### Closure

Two-line patch:

1. Moved `--json` from post-subcommand to top-level: `["stack", "exec", "llmll", "--", "--json", "verify", "--cdp", "--trust-report", abs_path]`.
2. Constructed `abs_path = str(REPO_ROOT / rel_path)` so resolution is cwd-independent.

Docstring at the top of the script updated to reflect the corrected invocation shape. After both patches, attempt 4 (`runs/20260526T233504Z-baseline/`) collected real data on 28 verify-clean fixtures; outcomes documented in [postmortem-002](postmortem-002-cdp-baseline-rerun.md).

## Withdrawn items

None. F-001 and F-003 are both real, root-caused, and closed.

## Null results

None — the run produced no DP measurements on either the primary or null hypothesis; both questions are now addressable post-fix via the data in postmortem-002.

## Priority matrix

| # | Finding | Consumer | Priority | Status |
|---|---------|----------|----------|--------|
| F-001 | DiagnosticFQ partial-record crash | compiler-engineer | Blocker | **Closed by `e5e6d04`** |
| F-003 | Harness `--json` placement + abs-path | experiment-lead | Blocker | **Closed in-session** |

## Cross-references

- [postmortem-002-cdp-baseline-rerun.md](postmortem-002-cdp-baseline-rerun.md) — the successful baseline measurement that runs after both blockers cleared.
- [`experiments/cdp-0/findings.md`](../findings.md) `## Compiler-engineer` (F-001 closure cite); `## Experiment-lead` (F-003 closure cite).
- CHANGELOG.md `## Unreleased` `### Compiler — fix: DiagnosticFQ partial-record crash on \`--json verify\` SAFE (F-001)` (commit `cc712aa`).
