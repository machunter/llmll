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
;; @cmd:    <optional; subcommand+args to run, default "check {file}">
;; @expect: check-ok | parse-error | check-error | warn:<substring> | output:<substring>
;; @claim:  <the human-readable claim being guarded>
<the program>
```

`@cmd` lets a fixture exercise a subcommand other than `check` — `{file}` is replaced
with the fixture path (e.g. `@cmd: checkout {file}`). For non-`check` subcommands, pair it
with the `output:<substring>` verdict, which just asserts the cited string appears in the
command's output (the check-specific verdicts assume `check`'s output shape).

### Verdicts

| `@expect`               | Passes when `llmll check` output…                                     |
| ----------------------- | --------------------------------------------------------------------- |
| `check-ok`              | shows `✅ … OK` with no error (guards "this now works")                |
| `parse-error[:<sub>]`   | contains `:phase parse` (and, if given, the substring `<sub>`)        |
| `check-error[:<sub>]`   | contains a semantic `error:` but no parse error (and `<sub>` if given) |
| `warn:<substr>`         | contains a `warning:` line whose text includes `<substr>`             |
| `output:<substr>`       | output contains `<substr>` (subcommand-agnostic; for `@cmd` fixtures) |

The optional `:<substring>` on `parse-error`/`check-error` (and the required one on
`warn`) pins a **cited diagnostic message**, not just the verdict class — so a doc that
quotes a specific error/warning string is guarded against that string drifting too.

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

## Fixtures

Seeded from the 2026-07-19 sweep, then broadened by a systematic pass over the docs'
restriction claims (which surfaced the `export`/`trust` ordering cluster below).

| Fixture | Guards | Kind |
| ------- | ------ | ---- |
| `list-literal-in-if.llmll` | list literal as fn arg inside `if` parses (was "unexpected ]") | fixed-stale |
| `import-after-def.llmll` | capability import after a `def-shell` is honored (was "silently ignored") | fixed-stale |
| `def-invariant-sexpr.llmll` | `(def-invariant …)` parses in `.llmll` source (was "rejected") | fixed-stale |
| `decl-order-independent.llmll` | `export` + `(trust …)` after a def are honored (were "must appear before defs") | fixed-stale |
| `do-notation-discard-warn.llmll` | non-final do-step `Command` emits the discard warning (DO-1) | positive behaviour |
| `missing-capability.llmll` | `wasi.io.stdout` without a capability import is a compile error | genuine restriction |
| `def-logic-rejected.llmll` | `def-logic` rejected with `removed-construct` | genuine restriction |
| `letrec-default-rejected.llmll` | `letrec` rejected under the default grammar | genuine restriction |
| `stale-import-syntax-rejected.llmll` | bare `(import wasi.io stdout)` is rejected | genuine restriction |
| `checkout-requires-astjson.llmll` | `checkout` rejects a `.llmll` source (needs `.ast.json`) | genuine restriction (`@cmd`) |

*fixed-stale* fixtures lock in a corrected claim (alert on regression); *genuine
restriction* fixtures are forward drift-catchers (alert the day the restriction is
relaxed and the doc must be updated).

Known gaps (would need more machinery than a single-input fixture):

- **`patch` scope/op claims** (move/copy unsupported, scope containment) — need a
  checked-out `.ast.json` plus a `patch.json`, i.e. multi-file fixtures.
- **JSON-AST-only claims** (e.g. the `let` simple-vs-pattern `oneOf`) — a `.ast.json`
  fixture cannot carry the `;;`-comment header (invalid JSON); it would need a metadata
  sidecar. Worth adding if that seam proves to drift.
