# Bug Report — `llmll verify` reporting path fails open on UNSAFE; `--trust-report` never surfaces `verified`

> **Status:** Resolved — VERIFY-RPT-1 shipped (`b914587`, 2026-06-06); all three defects fixed, regression tests VR-1..VR-8 landed
> **Date:** 2026-06-04
> **Reporter:** review pass (demo-readiness investigation)
> **Severity:** High — `verify` reports success on contract-violating code; the trust dashboard cannot show the `verified` tier
> **Environment:** binary `llmll 0.11.0` (`.stack-work/dist/aarch64-osx/ghc-9.6.6/build/LLMLL/llmll`, built 2026-06-02); HEAD `84d8166` (main); solver `fixpoint` (real liquid-fixpoint) present at `~/.local/bin/fixpoint`. **Note:** the `llmll` on `PATH` is a stale `0.10.8` build; all results below are reproduced on the **v0.11.0** binary. Line citations are against HEAD working tree.

---

## Summary

Three reporting-path defects in `llmll verify`. The **proof engine is correct** — the body-faithful VC is emitted correctly and the real solver returns the right verdict — but the verify-path *reporting layer* diverges from ground truth:

1. **`verify` fails open on UNSAFE.** A contract-violating function whose unsafe constraint IDs do not resolve against the `ConstraintTable` is reported `success: true`, exit 0, with no diagnostic. ([DiagnosticFQ.hs:106](../../compiler/src/LLMLL/DiagnosticFQ.hs#L106))
2. **`--trust-report` never shows `verified`.** Even after a successful proof writes `.verified.json` with `post: verified`, `verify --trust-report` renders `post: asserted`. ([Main.hs:1097-1103](../../compiler/app/Main.hs#L1097-L1103))
3. **`--strict-verified-core` does not catch a body-faithful UNSAFE.** It refuses only fallback/overflow-tainted functions, so a body-faithful function with an UNSAFE verdict passes. ([Main.hs:1149-1165](../../compiler/app/Main.hs#L1149-L1165))

The gate that *does* fail closed is `llmll patch` (`PatchVerifyError`, exit 1) — see [Working components](#working-components-do-not-regress).

## Why it matters

These are surfaced by the public repair-loop demo design (bad agent fill → diagnostic → repair → verified trust closure). The intended climax — `llmll verify --strict-verified-core --trust-report` showing the assurance lattice — currently shows the verifier blessing contract-violating code (Defect 1+3) and cannot render genuinely-proven code as `verified` (Defect 2). The demo cannot be wired from these commands until the reporting path is fixed.

---

## Shared reproduction

Fixture: [examples/withdraw-demo/withdraw.ast.json](../../examples/withdraw-demo/withdraw.ast.json) — `withdraw` with `pre (>= balance amount)`, `post (= result (- balance amount))`, body hole `?body_impl`.

Two fills of `/statements/1/body`:
- **wrong:** `(+ balance amount)` — type-correct (`int+int→int`) but violates the postcondition for all valid inputs (`amount > 0`).
- **correct:** `(- balance amount)`.

**Ground truth** (real solver, run directly on the emitted `.fq` for the wrong fill):
```
$ fixpoint /tmp/filled-wrong.ast.fq
Unsafe:
```
The emitted VC is correct:
```
lhs { result : int | (balance >= amount) && (result = (balance + amount)) }
rhs { result : int | (result = (balance - amount)) }
id 0  tag [0]
```

---

## Defect 1 — `verify` fails open on UNSAFE (High)

**Repro:**
```
$ llmll verify filled-wrong.ast.json
   .fq written to /tmp/filled-wrong.ast.fq
   body-faithful: withdraw
   Running liquid-fixpoint ...
$ echo $?
0
$ llmll verify filled-wrong.ast.json --json
{"diagnostics":[],"phase":"lh-fixpoint","success":true,"body_faithful":["withdraw"],"body_fallback":[]}
$ echo $?
0
```

**Expected:** non-zero exit, `success: false`, and a diagnostic pointing at `/statements/1/post`.
**Actual:** exit 0, `success: true`, empty diagnostics, no `UNSAFE` banner in text mode.

**Root cause:** [`DiagnosticFQ.hs:101-106`](../../compiler/src/LLMLL/DiagnosticFQ.hs#L101-L106):
```haskell
fqResultToReport fp table (FQUnsafe ids) =
  ...
    , reportSuccess     = null diags  -- might be unknown constraint IDs
```
The solver correctly returns `FQUnsafe [0]`, but constraint id `0` does not resolve to a source clause via `table` (the body-VC constraint is not registered in the `ConstraintTable` with a recoverable id → pointer mapping), so `diags == []` and `reportSuccess = null [] = True`. The verdict fails open exactly when diagnostic rebasing fails. The inline comment anticipates the unknown-id case and then resolves it the unsafe way.

Compounding: the text-mode `FQUnsafe` branch at [`Main.hs:1239-1240`](../../compiler/app/Main.hs#L1239-L1240) only `mapM_`-prints `reportDiagnostics` (empty here → no output) and there is no unconditional `exitFailure` on `FQUnsafe` in the `doVerify` text path.

**Suggested direction (CE owns):** (a) `reportSuccess` for `FQUnsafe` must be `False` regardless of whether `ids` resolve — an unmappable unsafe id is still unsafe; (b) on empty-but-unsafe, synthesize a fallback diagnostic (function-level, pointer to the `post` clause or `/`) so the payload is never empty; (c) ensure the text path exits non-zero on `FQUnsafe`. Item (a) is the load-bearing fix.

---

## Defect 2 — `--trust-report` never surfaces `verified` (High)

**Repro:**
```
$ rm -f filled-correct.ast.json.verified.json
$ llmll verify filled-correct.ast.json
✅ filled-correct.ast.json — SAFE (liquid-fixpoint)
   .verified.json written to filled-correct.ast.json.verified.json
$ python3 -c "import json;print(json.load(open('filled-correct.ast.json.verified.json'))['withdraw']['post']['display_level']['level'])"
verified
$ llmll verify filled-correct.ast.json --trust-report
  withdraw:
    pre:  asserted  |  post: asserted
```

**Expected:** `post: verified`.
**Actual:** `post: asserted`, even though the sidecar written by the immediately-preceding proof contains `display_level: {level: verified, prover: liquid-fixpoint}`. Reproduces on a second run with the sidecar already present, so it is not solely a within-run ordering artifact.

**Root cause (two contributing factors):**
1. The `--trust-report` block at [`Main.hs:1097-1103`](../../compiler/app/Main.hs#L1097-L1103) runs *before* the solver invocation at [`Main.hs:1208`](../../compiler/app/Main.hs#L1208), so within a single invocation it can only reflect pre-existing sidecar state, never the proof computed in that same run.
2. More seriously, `buildTrustReport _cache stmts sidecar` renders `asserted` *even when `sidecar` already carries `post: verified`* (confirmed on the second run). Either `_cache` (the parse-time cache from `Right (stmts, _cache, _)` at [`Main.hs:1087`](../../compiler/app/Main.hs#L1087)) takes precedence over `sidecar`, or `buildTrustReport`/`loadVerified` is not merging the sidecar's `display_level`. CE to isolate which.

**Suggested direction (CE owns):** trust-report rendering should reflect the proof computed in the same invocation (move the render after the solver, or feed `provenCS` into the report), and `buildTrustReport` must surface the sidecar's `verified` post-level when present. Without both, the single-command "prove and show verified" beat is impossible.

---

## Defect 3 — `--strict-verified-core` passes a body-faithful UNSAFE (Medium)

**Repro:**
```
$ llmll verify filled-wrong.ast.json --strict-verified-core --trust-report --obligation-report
Trust Report
  withdraw:
    pre:  asserted  |  post: asserted
Summary:
  verified: 0 ... asserted: 1
$ echo $?
0
```

**Expected:** strict mode rejects (non-zero) a function that went to the solver body-faithfully and came back UNSAFE.
**Actual:** exit 0. `--strict-verified-core` at [`Main.hs:1149-1165`](../../compiler/app/Main.hs#L1149-L1165) refuses only `erBodyFallback` and `erOverflowTaintedFns`. The wrong fill is *body-faithful* (the VC was emitted) with an UNSAFE solver verdict — neither category — so it passes. The trust report does correctly avoid labelling it `verified` (it shows `asserted`), so this is less severe than Defect 1, but strict mode silently tolerating an UNSAFE body-faithful result is wrong for a CI gate.

This defect is partly downstream of Defect 1: if `fqResult`/`reportSuccess` correctly carried UNSAFE, strict mode could key on it.

---

## Cross-cutting — empty diagnostics also hollow the `PatchVerifyError` payload

The same constraint-id → source-pointer rebasing gap behind Defect 1 also empties the diagnostic payload of the *working* patch gate:
```
$ llmll patch w.ast.json wp.json   # wrong fill
{"diagnostics":[],"result":"PatchVerifyError"}
$ echo $?
1
```
The verdict is correct (rejected, exit 1), but `diagnostics: []` means the "structured diagnostic with JSON pointer that the next agent reads" — central to the repair-loop value proposition — is empty. Fixing the fallback-diagnostic synthesis in Defect 1(b) should populate this too, since both paths route through `fqResultToReport` / `rebaseToPatch`.

---

## Working components (do not regress)

Confirmed correct on v0.11.0 — the bug is isolated to the verify-path reporting layer:

- **Proof engine / VC emission:** the body-faithful VC is correct; `fixpoint` returns `Unsafe` on the wrong fill, `Safe` on the correct fill.
- **`.verified.json` sidecar:** plain `llmll verify <correct>` writes `post: {display_level: verified, prover: liquid-fixpoint}` correctly.
- **`llmll patch` SMT gate:** `applyPatch` → `reVerify` ([PatchApply.hs:264, 363-393](../../compiler/src/LLMLL/PatchApply.hs#L363-L393)) returns `Just` on any `FQUnsafe` (independent of diagnostic resolution), yielding `PatchVerifyError` + exit 1. This is the gate that fails closed today.
- **`holes --deps`, `checkout`, `patch` (apply):** functional, emit JSON.

---

## Regression tests to add

1. `verify` on a body-faithful function with a falsifiable postcondition → `success: false`, exit ≠ 0, ≥1 diagnostic (even when constraint-id rebasing yields nothing).
2. `fqResultToReport (FQUnsafe [unknownId])` unit test → `reportSuccess == False`.
3. `verify <f>` then `verify <f> --trust-report` on a provable contract → trust report shows `post: verified`.
4. `verify --strict-verified-core` on a body-faithful UNSAFE → exit ≠ 0.
5. `patch` with a contract-violating fill → `PatchVerifyError` with a non-empty, pointer-bearing `diagnostics` array.
