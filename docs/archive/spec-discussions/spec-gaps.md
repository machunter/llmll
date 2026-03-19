# LLMLL v0.1 — Specification Gaps & Ambiguities

> **Context:** This document was produced by writing a complete Hangman game
> (`examples/hangman_complete.llmll`) using **only** `LLMLL.md` as a reference.
> Every item below is a point where (a) the spec is silent, (b) the spec is
> self-contradictory, or (c) a reasonable implementation requires a construct
> that has no defined semantics.

---

## §1 — No Recursion or Loop Primitive

**Where encountered:** `word-chars`, `display-word`, `all-guessed?`

**Problem:** LLMLL v0.1 provides `list-fold`, `list-map`, and `list-filter`
for structural recursion over *existing* lists, but there is **no way to
produce a list of `n` integers** when `n` is a runtime value (e.g., the length
of the secret word), and there is **no general recursion or `letrec`**.  
The spec explicitly forbids mutation, and the grammar contains no `loop`,
`while`, `letrec`, or `fix` keyword.

**Workaround used in `hangman_complete.llmll`:**  
A hard-coded static list `[0..49]` is built with 50 successive `list-append`
calls, then `list-filter` trims it to `< (string-length word)`.  
This caps supported word length at 50 and is obviously unscalable.

**Proposed resolutions:**
1. Add a `(range from: int to: int) -> list[int]` built-in to §13.5.
2. Add `letrec` / `fix` (a fixed-point combinator) to the grammar so
   user-defined recursive functions are expressible.
3. Make `list-fold` accept an `int` accumulator for bounded iteration:
   `(repeat n seed (fn [acc: a] -> a))`.

---

## §2 — No Custom Algebraic Sum Types (ADTs / Variants)

**Where encountered:** `game-step` (dispatching on input type), IO command
types (`wasi.http.response`, `wasi.io.stdout`).

**Problem:** The spec defines `Result[t, e]` as the *only* built-in sum type
(§3) and shows `DelegationError` expressed as a `|` union (§11.2), but the
grammar in §12 contains **no `|` union / variant / enum declaration syntax**
outside of pattern-match arms.  There is no way to introduce a user-defined
tagged union such as:

```lisp
;; Cannot write this — no syntax defined:
(type GameInput
  (| Start Word)
  (| Guess Letter))
```

**Impact in hangman:** The `game-step` function must dispatch on a string tag
(`":start ..."` vs letter) because there is no typed discriminated union for
the two possible inputs.  This is fragile and defeats the type safety the
language advertises.

**Proposed resolutions:**
1. Add `(type T (| Ctor1 type1) (| Ctor2 type2) ...)` syntax to §3 and §12,
   mirroring the `DelegationError` example in §11.2.
2. Clarify whether `DelegationError` syntax in §11.2 is the intended ADT
   declaration form and generalise it.
3. Restrict to the existing encoding and add a guideline for `match` on
   `Result` and `string` tags, with appropriate doc warnings.

---

## §3 — IO Command Construction Syntax Undefined

**Where encountered:** `initialize-game`, `handle-guess`, `game-step`.

**Problem:** §9 describes the Command/Response model and shows examples such
as `(wasi.http.response 200 "OK")` as the return of a logic function, but the
spec **never defines**:

- How `wasi.io.stdout` (or any non-HTTP capability command) is constructed.
- Whether command constructors are bare function calls, special forms, or
  require the capability name as a namespace prefix.
- What the type of a `Command` is — can it appear in `let` bindings? Can
  two commands be composed?

The grammar (§12) allows `(app IDENT { expr })` which would fit
`(wasi.io.stdout "text")`, but the `IDENT` production is not defined to allow
dots, so `wasi.io.stdout` is technically not a valid `IDENT`.

**Proposed resolutions:**
1. Define a `QualIdent` production (`IDENT { "." IDENT }`) and explicitly
   allow capability-namespaced function calls as command constructors.
2. Add a `Command` type to §3 and list the standard command constructors
   (e.g., `wasi.io.stdout`, `wasi.io.stderr`, `wasi.http.response`) in §13.
3. Add a combinator `(seq-commands cmd1 cmd2) -> Command` so multiple effects
   can be batched into one return value.

---

## §4 — `def-interface` Function Signature Syntax is Inconsistent

**Where encountered:** `HangmanIO` interface definition.

**Problem:** The spec (§11.1) shows:

```lisp
(def-interface AuthSystem
  [hash-password (fn [raw: string] -> bytes[64])]
  [verify-token  (fn [token: string] -> bool)])
```

But the grammar in §12 defines:

```ebnf
fn-type = "(" "fn" "[" { type } "]" "->" type ")" ;
```

The grammar says `fn-type` uses `{ type }` (just bare types, no names), but
the §11.1 example uses named parameters (`raw: string`).  These are
**contradictory**.  It is also unclear whether `fn` in a `def-interface` is
a *type* (structural) or whether named parameters are required/optional.

**Proposed resolutions:**
1. Update the grammar to `fn-type = "(" "fn" "[" { typed-param } "]" "->" type ")" ;`
   (matching the example in §11.1).
2. Keep the grammar as-is (anonymous types only) and update the §11.1 example
   to remove parameter names.
3. Allow both forms and specify that named parameters in `fn-type` are
   documentation-only and stripped before type-checking.

---

## §5 — `->` vs `->` Encoding

**Where encountered:** Throughout `def-interface` and `fn-type`.

**Problem:** The spec uses the arrow `->` (ASCII hyphen + `>`) in prose and
examples, but the grammar §12 uses `"->"` (a two-character terminal).  The
grammar header states "All source files must be ASCII-only."  This is fine,
but the grammar contains no explicit production distinguishing the arrow
`->` used in return types from the inequality operator `>` when it appears
after a `-` subtraction.  Tokenisation order is unspecified (greedy? longest
match?).

**Proposed resolutions:**
1. State explicitly that the lexer uses maximal munch (longest match), making
   `->` always tokenised as a single arrow token.
2. Add a `ARROW = "->" ;` terminal to the grammar to make this unambiguous.

---

## §6 — `match` Pattern Coverage / Exhaustiveness

**Where encountered:** Designing `game-step` and result dispatch.

**Problem:** The spec defines `match` (§12) but does not specify:

- Whether the compiler checks **exhaustiveness** (all cases must be covered).
- Whether there is a **wildcard / default** arm (`_`).
- What happens at runtime when no arm matches (panic? `Result.Error`?).

The grammar lists `"_"` as a valid pattern, but there is no semantic
description of its meaning.

**Proposed resolutions:**
1. State that `_` is the catch-all wildcard and that a `match` without `_`
   that fails at runtime raises an `AssertionError`.
2. Require exhaustiveness at compile time (recommend this for v0.1 given
   the type-safety focus).
3. Specify that an unmatched `match` returns a `Result.Error "MatchFailure"`.

---

## §7 — Scope of `result` in `post` Conditions

**Where encountered:** `make-state`, `display-word`, `guess`.

**Problem:** §4 uses `result` as a special variable in `post` expressions
(`(= result (- balance amount))`), but this is **not defined in the grammar**
or as a built-in in §13.  It is unclear:

- Whether `result` is a reserved keyword in `post` clauses only.
- Whether it can appear in `pre` clauses (it should not, but the spec is silent).
- What happens if the user names a parameter `result`.

**Proposed resolutions:**
1. Add `result` as a reserved keyword in `post` clauses only, and add a
   note that it is bound to the return value of the function body.
2. Document it in §13 as a pseudo-binding available only in `post`.
3. Use the name `$result` or `@result` to avoid collision with user identifiers.

---

## §8 — `let` Syntax: Sequence vs Simultaneous Binding

**Where encountered:** Every function that uses intermediate values.

**Problem:** The grammar says:
```ebnf
let = "(" "let" "[" { "[" IDENT expr "]" } "]" expr ")" ;
```
and the key rule note says `(let [[x 1] [y 2]] body)`.  It is **not specified**
whether bindings are **sequential** (each binding can see previous ones,
as in Haskell `let` or Scheme `let*`) or **simultaneous** (as in Haskell
`where` or Scheme `let`).

In `hangman_complete.llmll`, `index-range-50` relies on sequential binding
(`l1` uses `l0`, `l2` uses `l1`, etc.).  If bindings are simultaneous, this
does not type-check.

**Proposed resolutions:**
1. Specify `let` as **sequential** (equivalent to Haskell `let` / Scheme
   `let*`): each binding is in scope for all following bindings.
2. Provide both forms: `let` (simultaneous) and `let*` / `let-seq`
   (sequential).
3. Note that because LLMLL has no mutation, the distinction is semantic
   (shadowing) rather than operational — clarify the shadowing rules.

---

## §9 — String Equality `=` vs Structural Equality

**Where encountered:** `game-status` comparisons (`= "won" ...`).

**Problem:** §13.2 states that `=` performs "structural equality (also works
on strings, bool)" but does not define:

- Whether string equality is byte-by-byte (ASCII) or locale-aware.
- Whether equality is defined for `list[t]`, `map[k,v]`, or nested pairs.
- Whether `=` is polymorphic (works on any type) or requires operands of the
  same primitive type.

**Proposed resolutions:**
1. State explicitly that `=` is a polymorphic structural equality operator,
   defined recursively over any LLMLL type.
2. Restrict `=` to primitives and require a separate `list-equal` /
   `map-equal` for compound types.
3. Add a `Eq` type class / constraint and document which built-in types
   implement it.

---

## §10 — `wasi.io.stdout` Return Type

**Where encountered:** All IO command returns.

**Problem:** When a `def-logic` returns `(pair new-state (wasi.io.stdout text))`,
the second element must have a type.  The spec does not define the return type
of `wasi.io.stdout`.  Candidates include `unit`, `Command`, or
`Result[unit, string]`.  Without knowing the type, the return type of
`handle-guess` cannot be inferred, breaking the type system's completeness
guarantee.

**Proposed resolutions:**
1. Add `wasi.io.stdout : string -> Command` to §13 or §9 as part of a
   standard command library.
2. Define a `Command` sum type in §3 listing all standard constructors.
3. Make the IO capability declare its command constructor signature in the
   `import` form, e.g.,
   `(import wasi.io (capability stdout :type (fn [string] -> Command)))`.

---

## §11 — `for-all` in `check` and Dependent Types as Parameters

**Where encountered:** Last two `check` blocks in §11.

**Problem:** The spec allows `(check ... (for-all [c: Letter] ...))` with a
dependent type parameter. However, there is no description of how the PBT
engine **generates** values for dependent types such as `Letter` (where
`string-length s = 1`) or `GuessCount` (where `n >= 0`).  A naïve random
string generator will rarely produce a 1-character string.

**Proposed resolutions:**
1. Specify that the PBT engine extracts the `where` predicate and uses
   constrained generation (e.g., restriction to valid generators).
2. Require users to register custom generators for dependent types via a
   `(gen Letter ...)` declaration.
3. Document that `for-all` with a dependent type silently filters out
   invalid samples (shrink-and-filter approach, with a minimum sample floor).

---

## Summary Table

| # | Issue | Severity | Blocking? |
|---|-------|----------|-----------|
| §1 | No recursion / integer range | **High** | Yes — word iteration impossible without workaround |
| §2 | No custom ADTs / sum types | **High** | Yes — typed input dispatch impossible |
| §3 | IO Command construction syntax undefined | **High** | Yes — IO return types unknown |
| §4 | `def-interface` fn-type param name inconsistency | Medium | Partial |
| §5 | `->` tokenisation / maximal munch unspecified | Low | No |
| §6 | `match` exhaustiveness & wildcard semantics | Medium | No |
| §7 | `result` in `post` not defined | Medium | No |
| §8 | `let` sequential vs simultaneous binding | **High** | Yes — multi-step let chains are ambiguous |
| §9 | `=` polymorphism scope | Low | No |
| §10 | `wasi.io.stdout` return type | **High** | Yes — return type of IO handlers unknown |
| §11 | PBT generation for dependent types | Medium | No |
