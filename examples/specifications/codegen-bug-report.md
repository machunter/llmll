# LLMLL v0.1.1 — Codegen Bug Report
_Generated during Tasks Service implementation exercise, 2026-03-16_

---

## Bug 1 — Multiple `(pre ...)` clauses rejected by parser

**What happened:**
```lisp
(def-logic tasks-add [...]
  (pre (> (string-length title) 0))   ;; first pre
  (pre (valid-priority? priority))    ;; parse error here
  ...)
```

**Root cause:** A spec ambiguity. Section 4.1 shows the grammar as `[ pre-clause ]` — the `[ ]` notation means *optional*, but does not explicitly say *at most one*. A reader can plausibly interpret this as "zero or more optional pre-clauses." The formal grammar in §12 is unambiguous (exactly one), but the discrepancy between prose and grammar is easy to miss.

**Suggested fix:**
- Option A: Emit a clearer error: `"only one pre clause allowed — use (pre (and ...)) to combine conditions"`.
- Option B: Accept multiple `pre` clauses and desugar them to `(pre (and ...))` automatically.

---

## Bug 2 — Chained `if` without explicit else branches → bracket mismatch

**What happened:**
A 5-arm routing chain of nested `(if cond then else)` forms was written where some arms were missing their explicit else-branch, causing a paren imbalance that the parser caught far from the actual mistake:
```
error: unexpected '(' expecting ')'
```

**Root cause:** A code-generation slip caused by the verbosity of deeply nested S-expressions in a language with no `cond`/`when` multi-arm dispatch form. Each `(if ...)` requires exactly three sub-expressions. When writing 5 chained conditions across many lines it is easy to introduce an off-by-one closing paren. Scheme-family languages provide `cond` for exactly this pattern.

**Suggested fix:**
- Option A: Add a `(cond [(cond1 expr1)] [(cond2 expr2)] [(_ fallback)])` form to v0.2.
- Option B: Improve the parse error to say `"if expects exactly 3 sub-expressions; found 2 — missing else branch?"` instead of the generic `"unexpected '('"`.

---

## Bug 3 — `wasi.http.response` documented as built-in but missing from generated Rust preamble

**What happened:**
`wasi.http.response` is listed in §13.9 as a standard Command constructor. After adding `(import wasi.http (capability serve 8080))`, the LLMLL type-checker (`check`) passed and `holes` reported 0 — but `cargo check` on the generated Rust failed:

```
error[E0425]: cannot find function `wasi_http_response` in this scope
```

**Root cause:** A spec-vs-compiler gap. The v0.1.1 codegen preamble only materialises `wasi_io_stdout` and `wasi_io_stderr`. `wasi_http_response` is referenced in the emitted Rust code but never defined. The LLMLL type-checker did not catch this because capability enforcement is explicitly deferred to v0.2 — so a call to a capability-namespaced function that has no preamble definition passes `check` silently and only fails at `cargo check`.

This is the most impactful gap: the spec **promises** a built-in, the compiler **emits a call** to it, but the runtime preamble **does not define it**.

**Suggested fix:**
- Option A (quick): Add `wasi_http_response` to the Rust preamble template in `Codegen.hs`.
- Option B (robust): Have the `check` phase emit a **warning** when a `qual-app` to `wasi.http.*` (or any capability-namespaced function) resolves to a symbol absent from the preamble template — making the checker a faithful pre-flight for codegen.

---

## Summary

| # | Bug | Stage detected | Root cause | Recommended fix |
|---|-----|---------------|------------|-----------------|
| 1 | Multiple `pre` clauses | Parse | Prose implies ≥1; grammar says exactly 1 | Clearer error or auto-desugar |
| 2 | Missing `if` else branches | Parse | No `cond` form; deep nesting causes bracket slip | Add `cond`; better error message |
| 3 | `wasi_http_response` missing from preamble | `cargo check` | Spec promises built-in; codegen omits it | Add to preamble in `Codegen.hs` |
