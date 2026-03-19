# LLMLL v0.1.1 — AI Implementor Feedback

**From:** AI implementor (Tic-Tac-Toe exercise)  
**To:** LLMLL Language Design & Compiler Team  
**Date:** 2026-03-15  
**Context:** Implemented a complete text-based Tic-Tac-Toe game from scratch using only [LLMLL.md](file:///Users/burcsahinoglu/Documents/llmll/LLMLL.md) and [build-instructions.md](file:///Users/burcsahinoglu/Documents/llmll/docs/getting-started/build-instructions.md) as references.

---

## Summary

The language spec is readable and the pipeline (`llmll check → llmll build → cargo run`) works end-to-end. However, several **gaps between the specification and the actual compiler behavior** required debugging and manual workarounds. These gaps are silent: the spec says something is legal, the compiler silently fails, and there is no error message pointing to the real cause. For an AI code generator, silent mis-specification is more damaging than a hard error — it leads to a hallucination loop where generated code looks correct but never parses.

---

## Issue 1 — Pair Types in Typed Parameters Are Not Parseable

### What the spec says
Section 3.2 defines [(a, b)](file:///Users/burcsahinoglu/Documents/llmll/generated/tictactoe/src/lib.rs#137-138) as a valid compound type ("2-tuple / product type"). Section 12 (Grammar) shows `pair-type = "(" type "," type ")"` as a valid `type` production, and `typed-param = IDENT ":" type` accepts any `type`.

### What actually happens
The parser **fails silently** with a cryptic `TrivialError` when a pair type appears in any typed-parameter position:

```lisp
;; FAILS — pair type in def-logic parameter
(def-logic state-board [s: (list[string], (string, string))]
  (first s))

;; ALSO FAILS — pair type in lambda parameter
(fn [acc: (string, int) cell: string] ...)
```

The error message produced is a Megaparsec internal `TrivialError` dump — not a user-facing diagnostic. There is no "pair type not supported in v0.1.1" note anywhere in the spec.

### Workaround required
Use **untyped parameters** wherever the type would be a pair:

```lisp
(def-logic state-board [s]   ;; must omit type entirely
  (first s))

(fn [acc cell]               ;; must omit types in lambda params too
  ...)
```

This sacrifices type documentation and weakens the `pre`/`post` contract system, which relies on knowing parameter types.

### Recommendation
Either:
- **(a) Fix the parser** to accept `pair-type` in `typed-param` position (as the grammar specifies).
- **(b) Add a clear spec note** in §3.2 and §12: "In v0.1.1, `pair-type` is only valid as a return type annotation and in `let` binding targets. It is not accepted in `typed-param` position."
- **(c) Emit a proper diagnostic**: "Pair type in parameter position is not yet supported (v0.1.1). Use an untyped parameter instead."

---

## Issue 2 — `module` and `import` Declarations Do Not Parse at Top Level

### What the spec says
Section 8 shows `module` as the canonical way to organize code with imports. Section 12 (Grammar) lists `module-decl` and `import` as valid `statement` productions at the top level of a `program`.

### What actually happens
Both [(module ...)](file:///Users/burcsahinoglu/Documents/llmll/generated/tictactoe/src/lib.rs#137-138) and [(import ...)](file:///Users/burcsahinoglu/Documents/llmll/generated/tictactoe/src/lib.rs#137-138) at the top level of a file cause the parser to return **zero statements** and leave the first `(` unconsumed, producing the same opaque `TrivialError`. A top-level file with only `def-logic` statements compiles fine.

The root cause appears to be that the parser tries `statement → expr → app` for any `(` token; since `module` and `import` are keywords (not `IDENT`), the [app](file:///Users/burcsahinoglu/Documents/llmll/generated/tictactoe/src/lib.rs#248-253) parse fails non-fatally, and `{statement}` quietly stops — leaving the entire file unparsed except for 0 items.

### Workaround required
Write all code at the top level using only `def-logic`, `type`, and `check` statements. Skip all `module` and `import` declarations entirely. This means capability declarations are never made — which leads to Issue 3.

### Recommendation
- Fix the statement parser to commit to `module-decl` or `import` when it sees the `module` or `import` keyword after `(`, before attempting `expr`.
- In the interim, add a prominent **"Known Limitation (v0.1.1)"** box in §8: "The standalone `module` form and top-level `import` are parsed only inside a `module-decl` body. Files with only `def-logic` and `type` statements at top level are the supported form for v0.1.1."

---

## Issue 3 — `wasi.io.stdout` Works Without a Capability Import

### What the spec says
Section 9.2 states: "Each [command constructor] requires the corresponding `import` declaration — the compiler will reject a call to a command constructor whose capability has not been imported."

### What actually happens
Since top-level `import` doesn't parse (Issue 2), there is no way to declare capabilities. Yet `wasi.io.stdout` compiles and works at runtime without any import. The compiler does **not** enforce capability checking.

### Impact
This is a silent security bypass — the capability sandboxing mechanism that §7 presents as a core design pillar is not active. An AI generating code that relies on this guarantee for security reasoning will be wrong.

### Recommendation
- Add a spec note: "Capability enforcement is deferred to v0.2. In v0.1.1, `wasi.io.stdout` and related constructors are available unconditionally."
- Alternatively, provide a way to declare capabilities at the top-level file scope (a simpler [(using wasi.io.stdout)](file:///Users/burcsahinoglu/Documents/llmll/generated/tictactoe/src/lib.rs#137-138) declaration) that the current parser can handle without a full `module` block.

---

## Issue 4 — Generated [lib.rs](file:///Users/burcsahinoglu/Documents/llmll/generated/tictactoe/src/lib.rs) Is Missing Key Standard Library Functions

### What the spec says
Section 13 defines a full standard library including `string-slice`, `string-to-int`, [ok](file:///Users/burcsahinoglu/Documents/llmll/generated/tictactoe/src/lib.rs#137-138), [err](file:///Users/burcsahinoglu/Documents/llmll/generated/tictactoe/src/lib.rs#138-139), `is-ok`, [unwrap](file:///Users/burcsahinoglu/Documents/llmll/generated/tictactoe/src/lib.rs#142-149), `unwrap-or`, and the `-` (subtraction) operator.

### What actually happens
The generated [lib.rs](file:///Users/burcsahinoglu/Documents/llmll/generated/tictactoe/src/lib.rs) from `llmll build` is missing implementations for:

| Missing | Type |
|---------|------|
| [string_slice](file:///Users/burcsahinoglu/Documents/llmll/generated/tictactoe/src/lib.rs#125-131) | `string int int -> string` |
| [string_to_int](file:///Users/burcsahinoglu/Documents/llmll/generated/tictactoe/src/lib.rs#131-137) | `string -> Result[int, string]` |
| [ok](file:///Users/burcsahinoglu/Documents/llmll/generated/tictactoe/src/lib.rs#137-138) | `a -> Result[a, e]` |
| [err](file:///Users/burcsahinoglu/Documents/llmll/generated/tictactoe/src/lib.rs#138-139) | `e -> Result[a, e]` |
| [is_ok](file:///Users/burcsahinoglu/Documents/llmll/generated/tictactoe/src/lib.rs#139-142) | `Result[a, e] -> bool` |
| [unwrap](file:///Users/burcsahinoglu/Documents/llmll/generated/tictactoe/src/lib.rs#142-149) | `Result[a, e] -> a` |
| [unwrap_or](file:///Users/burcsahinoglu/Documents/llmll/generated/tictactoe/src/lib.rs#149-155) | `Result[a, e] a -> a` |
| `Sub` trait impl for `LlmllVal` | Needed for `-` operator |

`cargo build` fails with "cannot find function" errors in the generated code, which calls these functions but doesn't define them.

### Workaround required
Manually edit [lib.rs](file:///Users/burcsahinoglu/Documents/llmll/generated/tictactoe/src/lib.rs) to add all missing implementations — 50 lines of Rust boilerplate that should have been generated automatically. This breaks the "DO NOT EDIT" contract on the generated file and means any `llmll build` re-run would wipe the fixes.

### Recommendation
- Complete the standard library implementation in the code generator. These are all simple, self-contained functions.
- Add a [generated/tictactoe/Cargo.toml](file:///Users/burcsahinoglu/Documents/llmll/generated/tictactoe/Cargo.toml) test step to `llmll build` that runs `cargo check` before reporting success, so the "✅ Generated Rust crate" message is only shown when the generated code actually compiles.

---

## Issue 5 — The Compiler's `check` Step Gives No Guidance on Missing Builtins

### What happens
`llmll check` reports `✅ OK (21 statements)` even though calling `wasi.io.stdout`, `string-slice`, and `string-to-int` in the same program will produce a broken [lib.rs](file:///Users/burcsahinoglu/Documents/llmll/generated/tictactoe/src/lib.rs) that doesn't `cargo check`. The type-checker does not model the standard library.

### Recommendation
The `check` phase should verify that every `qual-app` or [app](file:///Users/burcsahinoglu/Documents/llmll/generated/tictactoe/src/lib.rs#248-253) call corresponds to a known built-in or declared function. Unknown calls should be at minimum a **warning**, not silently accepted. This is especially important for `wasi.io.*` commands where the spec explicitly says an unmatched import is a compile error.

---

## Issue 6 — Error Output Is Not AI-Friendly

### What happens
Parse failures print a raw Megaparsec internal `ParseErrorBundle` Haskell value including the full file input as an escaped string. Example:

```
error: ParseErrorBundle {bundleErrors = TrivialError 464 
  (Just (Tokens ('(' :| ""))) (fromList [EndOfInput]) :| [], 
  bundlePosState = PosState {pstateInput = "(module tictactoe\n  ...entire file...
```

The useful part (`TrivialError 464`) is buried and the offset is byte-level (not line:column). An AI must calculate `content[:464].count('\n')` to find which line caused the error.

### Recommendation
The spec (§10, step 2) says the compiler reports "structured S-expression diagnostics." The actual output is Haskell debug format. Implement this:

```lisp
(error :phase parse
       :file "examples/tictactoe.llmll"
       :line 14 :col 3
       :message "unexpected keyword `module`; expected expression"
       :hint "module declarations require a surrounding (module ...) form")
```

This is the single change that would most dramatically improve the AI development loop.

---

## Issue 7 — No REPL Feedback on Individual Expressions

### What the spec says
Section 3.5 shows a REPL that accepts expressions and returns their parsed AST. This is the ideal tool for ad-hoc syntax exploration.

### What actually happens
The REPL works for loading files (`:check`, `:holes`), but typing [(def-logic f [s: (a, b)] s)](file:///Users/burcsahinoglu/Documents/llmll/generated/tictactoe/src/lib.rs#137-138) in the REPL and seeing an immediate parse error would have saved hours of binary-search debugging on the pair-type issue.

### Recommendation
Ensure the REPL properly surfaces parse errors at the expression level, not just for file-level loads. Especially: if a `typed-param` with a pair-type fails to parse, the REPL should say so immediately.

---

## What Worked Well

- The **`result` keyword in `post` clauses** is elegantly specified and the compiler enforces it correctly.
- **`list-fold` with an untyped accumulator** covers most iteration patterns cleanly once pair types in lambdas are avoided.
- The **`match` on `Result` ADTs** (`Success`/`Error`) works correctly in the generated Rust code, including the pattern-match generation.
- The **`pre` contract assertion** in `apply-move` compiled and the generated `assert!()` in Rust is correct.
- The **[range](file:///Users/burcsahinoglu/Documents/llmll/generated/tictactoe/src/lib.rs#97-100) builtin** makes indexed iteration extremely ergonomic compared to manual recursion.
- The **build-instructions.md** document is clear and the overall pipeline concept (LLMLL → Rust → `cargo run`) is a good design.

---

## Priority Recommendations

| Priority | Action |
|----------|--------|
| 🔴 High | Make error messages S-expression structured with line:col (Issue 6) |
| 🔴 High | Add missing stdlib to generated [lib.rs](file:///Users/burcsahinoglu/Documents/llmll/generated/tictactoe/src/lib.rs) (Issue 4) |
| 🔴 High | Fix or document the pair-type param restriction (Issue 1) |
| 🟡 Medium | Fix or document module/import top-level parsing (Issue 2) |
| 🟡 Medium | Add `cargo check` validation to `llmll build` (Issue 5) |
| 🟢 Low | Document that capability enforcement is v0.2 (Issue 3) |
| 🟢 Low | Improve REPL expression-level error reporting (Issue 7) |
