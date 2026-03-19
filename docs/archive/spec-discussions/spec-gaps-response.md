# Response to SPEC-GAPS.md
*Assessment of developer feedback from the Hangman implementation exercise*

---

## Overall Assessment

This is the most valuable feedback the project has received to date. The developer did exactly the right thing: they wrote a real program under the spec constraints and documented every point where the spec failed them. The `hangman_complete.llmll` file is evidence-based critique — not conjecture. Every one of the 11 items is valid, and the severity ratings in the summary table are accurate.

The fact that the developer had to write 50 successive `list-append` calls to build `[0..49]` is not a workaround — it is a proof of failure. That block of code is the clearest possible signal that something is missing.

---

## Item-by-Item Verdict

### §1 — No Recursion or Integer Range — ✅ Valid / Critical

The 50-line `index-range-50` function is the most visible symptom of this gap. The developer's three proposals are all sound. **The right resolution is all three, stratified by version:**

- **v0.1 (immediate):** Add `(range from to) -> list[int]` as a built-in to §13. This is a trivial compiler built-in that unblocks most iteration patterns without requiring any new grammar.
- **v0.2:** Add `(repeat n seed fn) -> a`, the bounded accumulator form. Useful for loops where the iteration count is data-driven but finite.
- **v0.3:** Add `letrec` / `fix`. General recursion must be handled carefully in a language with formal verification ambitions — unrestricted recursion breaks SMT decidability. `letrec` should require a termination annotation (e.g., a structurally decreasing argument or a numeric bound), which the v0.2 Z3 layer can then verify.

The `range` built-in alone unblocks 80% of real programs. It goes into v0.1.

---

### §2 — No Custom ADTs / Sum Types — ✅ Valid / Critical

The `game-step` string-tag dispatch is the exact failure mode this gap produces. The developer correctly notes that string tags defeat the type safety the language advertises.

The right resolution is **Proposal 1**: add a proper `(type T (| Ctor1 t1) (| Ctor2 t2))` declaration form. The `DelegationError` example in §11.2 already implies this syntax exists — it just was never formalized.

The grammar needs to be updated to include:

```ebnf
type-decl = "(" "type" IDENT type-body ")" ;
type-body  = "(" "where" "[" typed-param "]" expr ")"   (* dependent type *)
           | { "(" "|" IDENT type ")" }                   (* sum type / ADT *)
           ;
```

This closes the gap between the `DelegationError` example in §11.2 and the grammar in §12 — both simultaneously.

---

### §3 — IO Command Construction Syntax Undefined — ✅ Valid / Critical

This is the most architecturally significant gap. The `wasi.io.stdout` call appears in `initialize-game` and `handle-guess`, but its type is nowhere specified, so the type checker cannot infer the return type of either function.

**Resolution plan:**

1. Add a `Command` type to §3 as a built-in opaque type. It is not constructable by the programmer directly — only via capability-namespaced constructors.
2. Add a `QualIdent` production to §12 (`IDENT { "." IDENT }`), making `wasi.io.stdout` a valid function reference.
3. Define a standard command library in a new §13.6 that specifies the types of every WASI capability constructor:

   ```lisp
   wasi.io.stdout  : string -> Command
   wasi.io.stderr  : string -> Command
   wasi.http.response : int -> string -> Command
   wasi.fs.write   : string -> bytes -> Command
   ```

4. Add `(seq-commands cmd1 cmd2) -> Command` as a sequencing combinator (Proposal 3 from the developer). This is needed for any function that must emit multiple side effects (display board AND read next input) — something every real IO-facing program will need.

---

### §4 — `def-interface` fn-type Parameter Inconsistency — ✅ Valid / Medium

The contradiction is real: §11.1 uses named parameters in `fn-type` but the §12 grammar uses anonymous types. **Resolution: Proposal 3** — allow both forms, where named parameters are documentation-only and erased before type checking. This is the least disruptive fix and is consistent with how most ML-family languages handle interface signatures.

Grammar update:

```ebnf
fn-type = "(" "fn" "[" { (type | typed-param) } "]" "->" type ")" ;
```

---

### §5 — `->` Tokenisation Ambiguity — ✅ Valid / Low

This is a real lexer ambiguity but in practice would never cause a problem because `-` (subtraction) is only a prefix in arithmetic expressions, not a type context. However, for spec correctness:

**Resolution: Proposal 1 + Proposal 2 together.** Add `ARROW = "->" ;` as a named terminal to the grammar *and* state that the lexer uses maximal munch. Both take three lines to specify and eliminate any tooling confusion.

---

### §6 — `match` Exhaustiveness and Wildcard — ✅ Valid / Medium

The grammar lists `_` but provides no semantics. This is a genuine spec omission.

**Resolution: a combination of Proposals 1 and 2.** Specifically:

- `_` is the catch-all wildcard (Proposal 1).
- In v0.1, a `match` without `_` that fails at runtime raises a typed `MatchFailure` error (Proposal 3 form — but as an error, not a `Result` wrapping, to avoid forcing every match to be error-handled).
- In v0.2, when Z3 liquid type checking is active, the compiler will statically verify exhaustiveness for `match` on ADT types — making the runtime error unreachable for well-typed programs.

---

### §7 — `result` in `post` Not Defined — ✅ Valid / Medium

This is a clean spec omission. `result` is used in the first code example in §4 but never enters the grammar or the built-in list in §13.

**Resolution: Proposal 1** — `result` is a reserved keyword bound only within `post` clauses, referring to the return value of the function body. It cannot appear in `pre` clauses (compile error if attempted). It cannot be used as a parameter name (shadowing error). Add it to §13 as a pseudo-binding under a new "Clause-Scoped Bindings" subsection.

The `$result` alternative (Proposal 3) is more syntax to introduce without benefit. `result` as a reserved keyword is simpler.

---

### §8 — `let` Sequential vs. Simultaneous Binding — ✅ Valid / Critical

The `index-range-50` function relies entirely on sequential binding (`l1` depends on `l0`, etc.). If `let` were simultaneous (Scheme `let`), this file would not type-check.

**Resolution: Proposal 1.** `let` in LLMLL is sequential (equivalent to Haskell `let` / Scheme `let*`): each binding is in scope for all subsequent bindings in the same `let` block. This must be stated explicitly in §8.

A separate `let-parallel` form (Proposal 2) is unnecessary for v0.1 and adds cognitive overhead for LLMs generating code.

---

### §9 — `=` Polymorphism Scope — ✅ Valid / Low

**Resolution: Proposal 1.** `=` is a polymorphic structural equality operator, defined recursively over any LLMLL type. The implementation must define equality coinductively (structural recursion over `pair`, `list`, `map`) and document it in §13.2. String equality is byte-by-byte (UTF-8 byte sequence comparison, locale-independent).

---

### §10 — `wasi.io.stdout` Return Type — ✅ Valid / Critical

This is the type-system completeness issue. Without a known return type for `wasi.io.stdout`, `initialize-game` and `handle-guess` cannot be type-checked.

This is directly resolved by the §3 resolution above: once `wasi.io.stdout : string -> Command` is defined in §13.6, type inference closes. These two gaps have the same root cause: the `Command` type is described in prose but never formally introduced.

---

### §11 — PBT Generation for Dependent Types — ✅ Valid / Medium

The `for-all [c: Letter]` block requires the PBT engine to generate random 1-character strings. A naïve generator rarely produces them, making the test almost always vacuous.

**Resolution: Proposal 2, with a default fallback.** Users can register custom generators via `(gen TypeName generator-expr)`. If no generator is registered for a dependent type, the engine uses rejection sampling (Proposal 3) with a minimum sample floor of 100 valid samples before reporting a generation failure. Document this behaviour in §5.

---

## Summary: What Goes Into Which Version

| Issue | Version | Action |
|---|---|---|
| §1 `range` built-in | **v0.1 patch** | Add `(range from to) -> list[int]` to §13 |
| §3 `Command` type + command library | **v0.1 patch** | Add `Command` to §3; add §13.6 standard commands |
| §3 `QualIdent` grammar | **v0.1 patch** | Add dotted identifier production to §12 |
| §8 `let` sequential semantics | **v0.1 patch** | Clarify in §8 that `let` is sequential |
| §7 `result` in `post` | **v0.1 patch** | Reserve keyword; document in §13 |
| §5 `->` tokenisation | **v0.1 patch** | Add `ARROW` terminal + maximal munch rule |
| §2 Custom ADTs | **v0.1 minor** | Add sum type declaration form to §3 + §12 |
| §4 `fn-type` parameter names | **v0.1 minor** | Allow named params in `fn-type`; doc-only |
| §6 `match` exhaustiveness | **v0.1 minor (runtime) / v0.2 (static)** | Specify wildcard + runtime `MatchFailure`; static check deferred to v0.2 |
| §9 `=` polymorphism | **v0.1 minor** | Specify in §13.2 |
| §10 `stdout` return type | resolved by §3 | — |
| §11 PBT generation | **v0.1 minor** | Add `gen` declaration; document rejection sampling |
| §1 `repeat` / `letrec` | **v0.2** | Bounded accumulator + termination-annotated recursion |

---

## Final Note

The developer's instinct to encode the program-under-test as `hangman_complete.llmll` (with holes in `hangman.llmll`) is itself a demonstration that hole-driven development works as a design discipline. The scaffold pattern — stub with holes, fill in the complete version — is exactly what the language was designed to enable. The feedback is a sign the core concept is sound; the gaps are specification debts, not design flaws.
