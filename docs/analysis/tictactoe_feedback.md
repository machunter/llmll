# Tic-Tac-Toe Implementation Feedback (LLMLL v0.1.1)

Here are the issues and discrepancies encountered while building the Tic-Tac-Toe program in LLMLL:

## 1. Parser requires a `target` for `capability` that contradicts the documentation
In section 13.9 of the `LLMLL.md` specification, it shows the following example for importing `stdout`:
```lisp
(import wasi.io (capability stdout :deterministic false))
```
However, the `v0.1.1` parser (`Parser.hs`) defines `capability` as requiring a `target` string/int/ident between the kind and the deterministic flag:
`target <- pStringLiteral <|> ... <|> pIdent`
This causes real-world code matching the spec to throw a confusing parser error (`unexpected '(' expecting ')'`). The workaround was to inject a dummy target like `"console"`:
```lisp
(import wasi.io (capability stdout "console" :deterministic false))
```

## 2. Confusing error message for `pair-type` restriction in parameters
The documentation correctly states the current `v0.1.1` limitation that `typed-params` cannot accept `pair-type` syntax like `acc: (int, string)`. However, if a developer makes this mistake, the parser fails completely at the lambda syntax and outputs a misleading error pointing to top-level constructs:
```text
unexpected '('
expecting ')'" :hint "use def-logic, type, import, or check at the top level
```
A more context-aware error message explaining that "pairs are unsupported in parameter types" would be helpful.

## 3. `seq-commands` is missing from the generated Rust prelude
The `LLMLL.md` specification introduces `seq-commands` to sequence multiple IO commands together (Section 9.3). 
However, the Rust code generation (`build` subcommand) does not emit a `pub fn seq_commands` wrapper into the `src/lib.rs` standard library preamble. 
When the generated Rust crate is compiled with `cargo`, it fails with:
`error[E0425]: cannot find function seq_commands in this scope`
The workaround was to nest `string-concat` calls into a single massive string to only call `wasi.io.stdout` once, bypassing the need for `seq-commands`.

## 4. Cascading type-mismatch errors when omitting types for tuples
Because we cannot define parameter types as tuples, we have to fall back to untyped bindings like `[acc item]`. However, this causes the `v0.1.1` type checker to assign `TCustom "_"` to param `acc`, which then causes rippling `type mismatch in 'X': expected _, got int` errors downstream when returning integer pairs or using recursive standard-library functions like `list-fold`. It makes the type-checker very noisy and heavily degrades the developer experience when managing game state.
