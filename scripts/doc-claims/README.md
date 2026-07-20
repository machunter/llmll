# DRIFT-CT-2 — doc-claim drift gate

Guards against **documentation drifting from actual compiler behaviour** — specifically
the class of stale *restriction* claims found in the 2026-07-19 external-critique triage
([`docs/design/critique-2026-07-19-triage.md`](../../docs/design/critique-2026-07-19-triage.md)),
where a doc asserted a program is rejected/broken but the compiler in fact accepts it.

Sibling of [`scripts/version_gate.sh`](../version_gate.sh) (DRIFT-CI-1, which guards
banner/schema equality). This gate guards **compiler-behaviour** claims.

## Why this class of drift is dangerous

Restriction claims ("X is a parse error", "Y is silently ignored", "Z is rejected") are
negative statements. Nobody writes a *passing* example for "this should fail", so the
normal example tests never exercise them — and when the underlying limitation is fixed,
the doc that documented it rots silently. All three stale claims in the 2026-07-19 review
were this shape. These claims are falsifiable against the compiler, so they can be gated.

## Fixture format

Each fixture is a `.llmll` file with a header:

```lisp
;; @doc:    <doc file and section the claim lives in>
;; @expect: check-ok | parse-error | check-error | warn:<substring>
;; @claim:  <the human-readable claim being guarded>
<the program>
```

### Verdicts

| `@expect`        | Passes when `llmll check` output…                              |
| ---------------- | -------------------------------------------------------------- |
| `check-ok`       | shows `✅ … OK` with no error (guards "this now works")         |
| `parse-error`    | contains `:phase parse` (guards a genuine syntactic restriction) |
| `check-error`    | contains a semantic `error:` but no parse error                |
| `warn:<substr>`  | contains a `warning:` line whose text includes `<substr>`      |

Asserting `check-ok` on a formerly-"broken" program locks in the fix — the gate flags a
regression. Asserting `parse-error` / `check-error` on a genuine restriction is the
forward drift-catcher: when a future change relaxes the restriction, the gate flips and
forces the doc (named in `@doc`) to be updated in the same PR.

## Running

```bash
# locally (auto-detects llmll on PATH or ~/.local/bin/llmll)
bash scripts/doc_claims_gate.sh

# explicit binary
LLMLL_BIN=/path/to/llmll bash scripts/doc_claims_gate.sh
```

CI runs it in the `spec-roundtrip` job of `.github/workflows/version-gate.yml`, after the
`llmll` build, with `LLMLL_BIN="stack exec llmll --"`. If no binary is found the gate
SKIPs (exit 0) rather than failing — it cannot assert behaviour without a compiler.

## Adding a fixture

1. When a doc adds a "this fails / isn't supported / is rejected" claim, add a fixture that
   encodes it (`@expect: parse-error` / `check-error`).
2. When a fix removes a restriction, flip the corresponding fixture to `@expect: check-ok`
   in the **same** change that fixes the doc.

**Engineer definition-of-done:** if a change alters parse/check/verify behaviour, run this
gate and reconcile any flip — the fixture's `@expect` *and* the doc section it names.
Drift detection belongs at the point of change, not a downstream audit.

## Current seed (from the 2026-07-19 sweep)

| Fixture | Guards |
| ------- | ------ |
| `list-literal-in-if.llmll` | list literal as fn arg inside `if` parses (was a stale "unexpected ]" claim) |
| `import-after-def.llmll` | capability import after a `def-shell` is honored (was "silently ignored") |
| `def-invariant-sexpr.llmll` | `(def-invariant …)` parses in `.llmll` source (was "rejected") |
| `stale-import-syntax-rejected.llmll` | bare `(import wasi.io stdout)` is genuinely rejected (forward drift-catcher) |

Natural next fixture: the `do`-notation intermediate-command discard **warning**
(`@expect: warn:discards this intermediate command`) — needs a valid do-block program.
