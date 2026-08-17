# DRIFT-CT-2, doc-claim drift gate

Guards against **documentation drifting from actual compiler behaviour**, specifically
the class of stale *restriction* claims found in the 2026-07-19 external-critique triage
([`docs/design/critique-2026-07-19-triage.md`](../../docs/design/critique-2026-07-19-triage.md)),
where a doc asserted a program is rejected/broken but the compiler in fact accepts it.

Sibling of [`scripts/version_gate.sh`](../version_gate.sh) (DRIFT-CI-1, which guards
banner/schema equality). This gate guards **compiler-behaviour** claims.

## Why this class of drift is dangerous

Restriction claims ("X is a parse error", "Y is silently ignored", "Z is rejected") are
negative statements. Nobody writes a *passing* example for "this should fail", so the
normal example tests never exercise them, and when the underlying limitation is fixed,
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

`@cmd` lets a fixture exercise a subcommand other than `check`, `{file}` is replaced
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
`warn`) pins a **cited diagnostic message**, not just the verdict class, so a doc that
quotes a specific error/warning string is guarded against that string drifting too.

Asserting `check-ok` on a formerly-"broken" program locks in the fix, the gate flags a
regression. Asserting `parse-error` / `check-error` on a genuine restriction is the
forward drift-catcher: when a future change relaxes the restriction, the gate flips and
forces the doc (named in `@doc`) to be updated in the same PR.

## Running

The shell gate `scripts/doc_claims_gate.sh` was DELETED on 2026-08-17 when
TOOL-RFC-003 retired. `tools/doc-claims/docclaims.llmll` is the only
implementation, and it is an LLMLL program, so it is built before it runs.

```bash
# build the gate, then run it
( cd tools/doc-claims && llmll build docclaims.llmll -o /tmp/docclaims )
GATE="$( (cd /tmp/docclaims && stack path --local-install-root) )/bin/docclaims"

# run it, naming the compiler it should exercise
"$GATE" --llmll "$(command -v llmll)"
```

CI runs it in the `spec-roundtrip` job of `.github/workflows/version-gate.yml`, after the
`llmll` build, with `LLMLL_BIN="stack exec llmll --"`. If no binary is found the gate
SKIPs (exit 0) rather than failing, it cannot assert behaviour without a compiler.

## Adding a fixture

1. When a doc adds a "this fails / isn't supported / is rejected" claim, add a fixture that
   encodes it (`@expect: parse-error` / `check-error`).
2. When a fix removes a restriction, flip the corresponding fixture to `@expect: check-ok`
   in the **same** change that fixes the doc.

**Engineer definition-of-done:** if a change alters parse/check/verify behaviour, run this
gate and reconcile any flip, the fixture's `@expect` *and* the doc section it names.
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
| `open-after-def-typecheck.llmll` | `(open …)` after a def that uses its bare names: `typecheck` exits **0** with only a warning | genuine restriction (`@cmd`, multi-module) |
| `open-after-def-verify.llmll` | the same program: `verify` exits **1** with `error:` | genuine restriction (`@cmd`, multi-module) |
| `open-aux-lib.llmll` | support module for the two above; its own claim is that it checks clean | positive behaviour |

The `open-after-def-*` pair is one claim needing two fixtures. The documented behaviour is that
`typecheck` and `verify` **disagree** on the same program, so neither command alone can guard it:
a single `typecheck` fixture would pass just as happily if `verify` also accepted the program, and
a single `verify` fixture would pass if `typecheck` also refused it. Guarding "green typecheck is
not evidence" needs both arms. `build` behaves identically to `verify` (exit 1, same message) and
is unguarded because it would pull GHC into the fast path for no additional discrimination.

*fixed-stale* fixtures lock in a corrected claim (alert on regression); *genuine
restriction* fixtures are forward drift-catchers (alert the day the restriction is
relaxed and the doc must be updated).

**Multi-module fixtures need no gate machinery.** `(import foo)` resolves `foo.llmll` relative to
the *importing file*, not the process CWD (verified v0.14.67 from a different working directory,
which is the CI condition). A support module therefore just sits in this directory, named to match
its module path. Because the gate globs every `*.llmll` here, the support module needs its own
valid header, so give it a `@claim` of its own rather than a placeholder: `open-aux-lib.llmll`
asserts that a well-formed module exporting a contracted `def` checks clean, which localizes a
failure to the support module instead of to the claim under test.

Known gaps (would need more machinery than a single-input fixture):

- **`patch` scope/op claims** (move/copy unsupported, scope containment), need a
  checked-out `.ast.json` plus a `patch.json`. Unlike the multi-module case above, these are
  multi-*format* fixtures: the extra input is not itself a `.llmll` the gate can glob.
- **JSON-AST-only claims** (e.g. the `let` simple-vs-pattern `oneOf`), a `.ast.json`
  fixture cannot carry the `;;`-comment header (invalid JSON); it would need a metadata
  sidecar. Worth adding if that seam proves to drift.
