---
title: CTOR-AS-VALUE — a constructor of bool or Result is not a value
status: Rev 0, SETTLED 2026-10-17
row: RESERVED-NAME-1 residue (4) (G3)
review: none (the user skipped the professor step)
---

# CTOR-AS-VALUE — a constructor of bool or Result is not a value

**Status: Rev 0, SETTLED 2026-10-17.** The user chose option (A), rejection, and included `Success` and `Error` in the same rule.

## Restatement

`True` and `False` are the constructors of `bool` in a `match` pattern (`LLMLL.md` §3.3). In expression position they are unbound names. Plain `check` reports them as warnings, and `check --strict`, `build` and `verify` report the same text as errors. `Success` and `Error` (`LLMLL.md` §13.8) have the same disagreement. The row asks the language team to choose between rejecting them as values and accepting them.

## Context located

1. `docs/compiler-team-roadmap.md`, row `RESERVED-NAME-1 residue (4)` (G3, DECIDE), measured at `0691e19a`.
2. `LLMLL.md` §3.3, "Reserved constructor names": `True` and `False` are the constructors of `bool`; `(True)` and `(False)` are its patterns; the values are `true` and `false`.
3. `LLMLL.md` §13.8: `ok` and `err` build a `Result`; `Success` and `Error` are its patterns. `Result` already separates the value spelling from the pattern spelling.
4. `compiler/src/LLMLL/TypeCheck.hs`, `unknownName` (XMOD-SCOPE R4): a name the build closure declares is an error in both strictness modes, with the fix in the message. A name no module declares keeps the warning, which serves holes and incomplete programs.

**Measured on v0.30.2:**

| Input | Plain `check` | `--strict`, `build`, `verify` |
|---|---|---|
| `(if (> n 0) True False)` | OK, 2 warnings `unbound variable 'True' (may be in scope at runtime)` | errors, exit 1 |
| `(post (= result True))` | OK, 1 warning | error |
| `(Success n)` as a value | OK, warning `call to unknown function 'Success'` | `build`: error |
| `(match b ((True) 1) ((False) 0))` | clean | clean |
| `[True: int]` as a parameter; `(let [(False 2)] …)` | clean | builds (RESERVED-NAME-1 renames the binding) |

No tracked `.llmll` file uses `True`, `False`, `Success` or `Error` as a value.

## Design proposal

### Rule

In expression position, an **unbound** `True`, `False`, `Success` or `Error` is a check error in both strictness modes, of kind `constructor-as-value`. The rule covers a bare name and the head of an application.

```
x ∈ {True, False, Success, Error}     x ∉ dom(Γ)
──────────────────────────────────────────────────  (Ctor-As-Value)
check error constructor-as-value at x
```

### Messages

- `True`: "`True` is a constructor of `bool`, usable only as a `match` pattern `(True)`. The value is `true`." `False` reads the same with `false`.
- `Success`: "`Success` is a constructor of `Result`, usable only as a `match` pattern `(Success x)`. Build the value with `(ok x)`." `Error` reads the same with `(err e)`.

### Why rejection

1. **One spelling for each value.** Acceptance would make `True` and `true` two spellings of one value, and the JSON-AST would need a normalization step for both to emit and verify alike. One spelling serves one-shot correctness.
2. **`Result` already makes this split.** `ok` and `err` are values; `Success` and `Error` are patterns. A consistent acceptance would also type `(Success x)` as a function, which is an addition and not a repair.
3. **The R4 precedent.** A name the compiler knows is wrong is an error that names the fix. The warning "may be in scope at runtime" is false for these four names: nothing binds them at run time.

### Unchanged

The patterns `(True)`, `(False)`, `(Success x)` and `(Error e)`; the values `true`, `false`, `ok` and `err`; and a **bound** name `True` (a parameter or a `let` binding), which RESERVED-NAME-1 left legal.

## Edge cases and degenerate inputs

1. **Positive witness.** `(def-shell f [n: int] -> bool (if (> n 0) True False))`: plain `check` exits 1 with two `constructor-as-value` errors naming `true` and `false`. Control: `(if (> n 0) true false)` passes. Channel: type.
2. **In a contract.** `(post (= result True))`: the same error; contract clauses take the same name path, as the measured warning shows. Channel: type.
3. **The pattern.** `(match b ((True) 1) ((False) 0))`: clean, exhaustiveness unchanged.
4. **A bound name.** `[True: int]` with the body `True`, or `(let [(False 2)] …)`: clean. The rule fires only on an unbound name. The spec is silent by design: §3.3 reserves these names as constructors, not as binders.
5. **Result constructors.** `(Success n)` or a bare `Error`: `constructor-as-value`, naming `(ok n)` and `(err e)`. Channel: type.
6. **JSON-AST.** `{"kind":"var","name":"True"}` or `{"kind":"app","fn":"Success",…}`: the same error; the rule sits in the type checker, after both parsers. Channel: type.
7. **Sketch mode.** The error is reported as a diagnostic like any check error. The spec is silent by design.

## Verification mapping

No proof obligation. A type-channel diagnostic only; nothing reaches liquid-fixpoint or Lean (`LLMLL.md` §5.3.3). The rule fires only where `build` already fails, so no program that builds today changes.

## Affected surface

- `compiler/src/LLMLL/TypeCheck.hs`: the unbound-name path and the unknown-callee path test the four names before the fallback warning, and emit `constructor-as-value` in both strictness modes.
- `compiler/src/LLMLL/Diagnostic.hs`: one message constructor for the two texts.
- `compiler/test/Spec.hs`: cells for edge cases 1 to 6, plain and `--strict` agreeing.
- `LLMLL.md`, by doc-lead after shipping: one sentence each in §3.3, "Reserved constructor names", and §13.8.
- `docs/compiler-team-roadmap.md`, by doc-lead: the row closes.
- No change to the JSON-AST schema, the parsers, codegen or the verifier. No addition.

## Risks

1. **The rule must key on an unbound name, not on the spelling.** (Spec drift, if done wrongly.) A spelling rule would reject `[True: int]`, which builds today. Edge case 4 pins the unbound reading.
