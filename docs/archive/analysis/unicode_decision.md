# Design Decision: Unicode Symbol Aliases in LLMLL
*Date: 2026-03-13 — Language version: v0.1.1*

---

## Summary

LLMLL v0.1.1 lifts the ASCII-only source restriction and introduces a curated set of **Unicode mathematical symbol aliases**. Unicode identifiers remain forbidden. This document records the rationale, the alias table, the security constraints, and the precedents informing the decision.

---

## Background

The original spec required all source files to be ASCII-only. A developer's confusion over the `->` arrow token (two ASCII characters that must be parsed with maximal munch) triggered the review of this constraint.

The primary question: **Is there any good reason to restrict LLMLL to ASCII when the intended audience is an LLM, not a human typist?**

---

## Rationale for Accepting Unicode

### 1. The audience doesn't type

The historical reason for ASCII-only in programming languages is keyboard entry ergonomics. Humans have to type source code; Unicode math symbols are difficult to produce on standard keyboards. This constraint does not apply to LLMLL's primary author (an LLM), which outputs tokens directly from its sampler.

### 2. LLMs are trained on mathematical notation

Modern LLMs have been exposed to millions of papers, textbooks, and formal specifications written using the exact symbols in this alias table: `∀`, `→`, `∧`, `∨`, `¬`, `λ`. These symbols appear in every description of type theory, logic, and functional programming. Allowing them reduces the distance between the LLM's training signal and the syntax it must produce.

### 3. Disambiguation

`→` (U+2192) is a single, unambiguous codepoint. It cannot be confused with subtraction followed by greater-than. The developer confusion that triggered this review is impossible with `→` — the lexer rule is trivial: single codepoint, single token.

### 4. Lean 4 precedent

LLMLL's own roadmap targets Lean 4 for v0.3 interactive proofs. Lean 4 adopts exactly this policy: every ASCII construct has a Unicode alias (`→` for `->`, `∀` for `forall`, `∧` for `And`, `λ` for `fun`). Aligning with Lean 4's convention reduces friction when the v0.3 proof agent bridges the two languages.

---

## The Alias Table

| ASCII form | Unicode alias | U+ codepoint | Name |
|------------|---------------|--------------|------|
| `->` | `→` | U+2192 | RIGHTWARDS ARROW |
| `>=` | `≥` | U+2265 | GREATER-THAN OR EQUAL TO |
| `<=` | `≤` | U+2264 | LESS-THAN OR EQUAL TO |
| `!=` | `≠` | U+2260 | NOT EQUAL TO |
| `and` | `∧` | U+2227 | LOGICAL AND |
| `or` | `∨` | U+2228 | LOGICAL OR |
| `not` | `¬` | U+00AC | NOT SIGN |
| `for-all` | `∀` | U+2200 | FOR ALL |
| `fn` | `λ` | U+03BB | GREEK SMALL LETTER LAMBDA |

Both forms are accepted in all positions. They produce the **identical token kind**. The compiler's canonical output and error messages always use the ASCII form.

---

## What Is NOT Allowed

**Unicode identifiers are explicitly forbidden.** Variable names, function names, type names, and module names must remain ASCII-only identifiers.

Reason: Unicode identifiers open a significant attack surface in a multi-agent architecture:

- **Homoglyph attacks:** `Balance` (Latin B) and `Βalance` (Greek capital beta) are visually identical but semantically distinct. An adversarial or hallucinating agent could shadow a trusted binding using a visually indistinguishable name.
- **Invisible characters:** Zero-width joiners (U+200D), zero-width non-joiners (U+200C), and other invisible codepoints can be embedded inside identifiers to create names that display identically but hash differently.
- **AST-level merging safety:** The AST merge algorithm in §11.3 compares node identity. Unicode identifier exploits could cause merge collisions or false equivalences.

The alias policy is safe because:
1. Aliases map to a **closed, enumerated set** of codepoints — any codepoint not in the table is rejected by the lexer.
2. The aliased symbols are **operators and keywords**, not identifiers — they have no user-defined names and cannot be shadowed.

---

## Implementation Notes

The change is confined entirely to `Lexer.hs`:

1. `pArrow` accepts `→` (U+2192) via an `<|>` alternative to `"->"`.
2. `pOperator` accepts `≥` `≤` `≠` via `<|>` alternatives to their ASCII forms.
3. New `pUnicodeOperator` function handles `∧` `∨` `¬` `∀` `λ` — each maps to the same `TokenKind` as its keyword equivalent.
4. `pUnicodeOperator` is inserted into `pToken`'s dispatch before `pKeywordOrIdent`.

No changes to `Syntax.hs`, `Parser.hs`, `TypeCheck.hs`, `Codegen.hs`, or `Diagnostic.hs`. The canonical output of `kindToText` remains ASCII.

---

## Decision

Accepted. unicode aliases are part of the LLMLL v0.1.1 specification.
