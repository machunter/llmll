---
name: finding-match-nullary-ctor-unsound
title: "MATCH-NULLARY-1: a bare nullary constructor in a match arm verifies unsoundly"
status: "FIXED in v0.14.66; found 2026-07-25 against v0.14.65"
severity: "soundness (false SAFE under --strict-verified-core) — resolved"
found_by: main-agent, during RFC-SWARM Phase 1 contract authoring
consumers: [compiler-engineer, language-team, user]
---

# MATCH-NULLARY-1: a bare nullary constructor in a match arm verifies unsoundly

**One line.** Writing a nullary constructor without parentheses in a `match` arm —
`(A 1)` instead of `((A) 1)` — parses it as a *catch-all binder named `A`*. The verifier
reasons about that catch-all reading and proves postconditions the generated program
violates. Nothing warns.

This was found while authoring the TFTP root contracts, whose model is enum- and
ADT-heavy. It blocked the RFC-SWARM wave, because `--strict-verified-core` is the per-fill
acceptance bar (playbook stage M) and it was exactly the gate that returned the false
verdict.

> **RESOLVED in v0.14.66.** `TypeCheck.checkPatternExpanded` now hard-errors when a match-arm
> pattern is a bare `PVar` naming a constructor of the scrutinee's type (user sum types and
> `Result`), naming the correct form in the message. `LLMLL.md` §3.4 states the rule; tests
> MN-1..MN-6; 1411 examples, 0 failures. The rest of this document is the analysis as found,
> kept because the reasoning is the reusable part.

## Reproduction

```lisp
(type E (| A) (| B) (| C))

;; post is TRUE under the catch-all misreading ("first arm always taken -> result = 1"),
;; FALSE under the real semantics (returns 2 for B, 3 for C).
(def-shell s1 [x: E] -> int
  (post (= result 1) :source "[T001] unsound-probe")
  (match x (A 1) (B 2) (C 3)))
```

```
$ llmll verify s1only.llmll --strict-verified-core
   body-faithful: s1
   Running liquid-fixpoint ...
✅ s1only.llmll — SAFE (liquid-fixpoint)
```

The **same body** with spec-correct parenthesized patterns is refuted, as it should be:

```lisp
(def-shell s2 [x: E] -> int
  (post (= result 1) :source "[T001] control")
  (match x ((A) 1) ((B) 2) ((C) 3)))
```

```
error: body verification of 's2' failed (else-branch does not satisfy postcondition) (constraint #2)
error: body verification of 's2' failed (else-branch does not satisfy postcondition) (constraint #3)
```

## The generated program contradicts the proof

`llmll build` emits the constructor match correctly, because Haskell reads an uppercase
identifier in a pattern as a constructor:

```haskell
s1 :: E -> Integer
s1 x =
  (let { result = (case x of { A -> (1 :: Integer); B -> (2 :: Integer); C -> (3 :: Integer) }) }
   in (if (not (result == (1 :: Integer))) then (error "Postcondition violated in s1") else result))
```

Executed:

```
s1 A = 1
s1 B = Main.hs: Postcondition violated in s1
```

So the statically-proved postcondition is refuted at runtime **by the generated code's own
assertion for that same postcondition**. Static verification and codegen disagree about
what the program means.

## Root cause

`compiler/src/LLMLL/Parser.hs` (pattern alternatives, ~line 761-773):

```haskell
  , try $ parens $ do   -- (Ctor arg1 arg2 ...) constructor pattern
      name <- pIdent
      args <- many pPattern
      pure $ PConstructor name args
  , PLiteral <$> pLiteral
  , PVar <$> pIdent     -- also matches _foo as a single named binder
```

A match arm is `(pattern body)`. For `(A 1)`, `pPattern` consumes the bare `A` via the last
alternative and yields `PVar "A"`, a binder; `1` becomes the arm body. The parenthesized
form `((A) 1)` takes the `parens` alternative and yields `PConstructor "A" []`.

The emitted AST confirms the reading:

```json
{ "arms": [ { "body": {"kind":"lit-int","value":1},
              "pattern": {"kind":"bind","name":"A"} }, ... ] }
```

Capitalization is not consulted, and **no downstream check tests a `PVar` pattern against
the scrutinee type's declared constructors**. The three symptoms follow from that one gap:

1. The first bare arm becomes a catch-all, so every later arm is dead.
2. The verifier proves the postcondition against the catch-all reading — unsound whenever
   the real body's other arms would violate it.
3. Codegen emits the name verbatim, which Haskell then reads as a constructor. Codegen's
   rule is right for genuine (lowercase) binders and *accidentally* right here; that
   accident is what makes the two halves disagree instead of merely both being wrong.

Note the interaction that hides it: a bind-pattern arm is outside the admissible match
class, so many such functions merely fall back (`body-fallback`) and lose precision
silently. The unsound case is the subset where the catch-all reading still yields a
body-faithful VC, as in `s1`.

## Spec status

`LLMLL.md` §3.4 "Pattern arity" states: *"Each constructor pattern's sub-pattern count must
equal the declared arity of the constructor at its declaration site. ... Mismatch produces
a typechecker warning."* No warning fires here — `llmll check` reports `OK` with no
diagnostics — because the bare form never becomes a constructor pattern in the first place,
so the arity rule never engages. The spec's canonical examples already use the correct
parenthesized form (`((Red) "stop")`).

## Blast radius: zero existing occurrences

Every `.llmll` source in the tree was compiled to JSON-AST and scanned for match arms whose
pattern is `{"kind":"bind"}` with a capitalized name:

| Scanned | Occurrences |
|---|---:|
| `.llmll` sources under `examples/`, `compiler/test/`, `tools/` (127 files, all emitted cleanly) | **0** |
| `*.ast.json` already committed in the tree (1526 files) | **0** |

**No shipped verified claim in this repository is affected.** The defect is latent: it
traps newly written code, which is precisely what a fill swarm produces.

## The fix `[CT]` — shipped v0.14.66

The parser cannot decide this alone (it does not know the scrutinee's type), so the check
belongs in the typechecker, where the scrutinee type and its constructor set are both known:

> When a `match` arm pattern is `PVar n` and `n` is a declared constructor of the
> scrutinee's type, **hard-error**.

A hard error rather than a silent reinterpretation-as-constructor, because:

- the spec-correct form `((A) 1)` already exists and is what the §3.4 examples use;
- silently reinterpreting would change the meaning of a program that today (mis)compiles,
  and would make a genuine catch-all named after a constructor impossible to express;
- an error message can name the fix directly (`write ((A) ...) for the nullary constructor A`).

Shipped exactly as stated above. Two residuals were **not** taken and stay open:

- The §3.4 *arity* mismatch (a constructor pattern with the wrong sub-pattern count) still
  warns rather than errors, as the spec says. That path was never the unsound one.
- Rejecting any capitalized `PVar` binder in pattern position, even when the name is not a
  constructor of the scrutinee type, was considered and declined: it would outlaw a legal
  binder on a naming convention alone, and the soundness hole is closed without it.

## Regression fixture

`compiler/test/fixtures/match-nullary/` — `unsound.llmll` (rejected as of v0.14.66 with the
constructor-pattern diagnostic; verified SAFE before the fix) and `correct.llmll` (the
parenthesized control, still typechecks and is still refuted). Both carry the expected
verdicts in-file. Unit coverage is MN-1..MN-6 in `compiler/test/Spec.hs`.
