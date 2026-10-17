---
title: REGEX-CAPTURE-1 and REGEX-CASE-1 — capture, scan and case for text processing
status: Rev 0, SETTLED 2026-10-17; amended 2026-10-17 after implementation (A1, A2)
rows: REGEX-CAPTURE-1, REGEX-CASE-1 (G7)
review: none (the user skipped the professor step)
---

# REGEX-CAPTURE-1 and REGEX-CASE-1 — capture, scan and case for text processing

**Status: Rev 0, SETTLED 2026-10-17.** The user put both rows in one pass on 2026-10-17, added `string-lower` and `string-upper` to the same phase, and sent the proposal to the compiler engineer without a professor review. Two amendments followed the implementation (`9175da47`, `d4557731`); see [Amendments after implementation](#amendments-after-implementation). Edge case 3 and Risk 2 are corrected in place, each marked.

## Restatement

LLMLL has one regex builtin, `regex-match : string string -> bool`. It cannot extract text, locate a match, scan for every match, or match without regard to case. This pass closes both G7 rows with new builtins. It does not change the type system and adds no verification obligation.

Two reference sets apply. The measurement set is Python's `re` and Go's `regexp`: agents write against them, so their habits decide what agents will try (`(?i)`, `findall`, group 0 as the whole match). The design-reference set is Liquid Haskell, Dafny and F\*. None of them verifies regex: Liquid Haskell and F\* treat a regex library as trusted code, and Dafny has no regex in its standard library. LLMLL loses nothing against that set by keeping regex outside `Σ_auto`. The bar is a trusted text library that does not fail silently.

## Context located

1. `docs/compiler-team-roadmap.md`, rows `REGEX-CASE-1` and `REGEX-CAPTURE-1` (G7), both `PLAN`. CASE offers a flag on `regex-match` or a `string-lower` builtin, and notes that the two close different amounts of the row. CAPTURE asks for "positions or matched text". Its workaround (split on the delimiter, then match each segment) was measured correct, but two plausible versions of the split are wrong (16 citations against 94).
2. `docs/design/tool-rfc-005-doc-path-lint.md` §4, §5 and D3: where both gaps were found. D3 chose per-letter bracket classes over lower-casing first. No earlier proposal exists for either row.
3. `LLMLL.md` §13.6: `regex-match` takes the pattern first and matches POSIX ERE through `regex-tdfa`. "Invalid patterns return `False` (total)."
4. `LLMLL.md` §5.3.3 and the predicate-class table in §3: `regex-match` is in the boolean-builtin class, never auto-discharged and never in `Σ_auto`.
5. `compiler/src/LLMLL/CodegenHs.hs`, the preamble binding `regex_match`: it runs `=~` inside `try`/`evaluate` under `unsafePerformIO`, and any exception becomes `False`.
6. `compiler/src/LLMLL/CodegenHs.hs`, the `esResultForcers` table (EVAL-STRICT-1): a builtin that returns a string or a list needs an entry.
7. `compiler/src/LLMLL/CodegenHs.hs`, the preamble-name list that names `regex_match`. It feeds the RESERVED-NAME-1 rename set, `reservedHsNames`.
8. `compiler/src/LLMLL/TypeCheck.hs`, `builtinEnv`: `("regex-match", TFn [TString, TString] TBool)`.
9. `compiler/src/LLMLL/Parser.hs`, the REGEX-LOWER-1 note: a hyphenated builtin parses as an `EApp` and lowers through `toHsIdent`, so a new `regex-*` or `string-*` name needs no parser change.
10. `docs/llmll-ast.schema.json` does not name `regex-match`. Builtins are ordinary application nodes, so there is no schema change.
11. `compiler/package.yaml`: the compiler does not depend on `regex-tdfa`. Only generated programs do.
12. In-tree use: 29 `regex-match` sites under `examples/` and `tools/`. One passes a literal pattern at the call site (`"clock=[0-9]+"`). `tools/doc-path-lint/pathlint.llmll` passes its pattern through a nullary def, `(path-pat)`. No site uses `(?i)`.
13. **Measured on regex-tdfa 1.3.2.2, 2026-10-17**, with a scratch program on the compiler's stack resolver:
    - `(?i)` is a parse error (`parseRegex … unexpected "?"`), so `regex_match` returns `False`. This confirms the row's claim and names its cause.
    - Case-insensitive compile (`caseSensitive = False`): `previously` matches `Previously`; `[a-z]+ly` matches `PREVIOUSLY`; `[^a-z]` does not match `ABC`; `ä` matches `Ä`.
    - `([a-z]+)=([0-9]+)?` on `key=val` gives `["key=","key",""]`: a group that took no part reads `""`.
    - `(a|ab)(b?)` on `ab` gives `["ab","ab",""]`, POSIX leftmost-longest. PCRE and Python give `["ab","a","b"]`.
    - `a*` on `baaab` gives `["","aaa","",""]`: empty matches are kept, as in Python.
    - `getAllMatches` gives character offsets: `ab` in `xxab ab` gives `[(2,2),(5,2)]`.
    - Invalid patterns `(` and `a{2,1}` raise exceptions, which the `try` wrapper catches.
14. **Measured on `Data.Char`, 2026-10-17:** `toLower` and `toUpper` mapped over each character keep the length on every input tried. See the table under `string-lower` and `string-upper`.

No drift between `LLMLL.md` and the compiler was found. §13.6 describes what the preamble does.

## Design proposal

### Surface

Five new builtins, one pattern rule shared by the four `regex-*` builtins, and one check-time error.

| Builtin | Signature | Meaning |
|---|---|---|
| `regex-find` | `string string -> list[string]` | `(regex-find pattern subject)`: the leftmost match. `[]` when nothing matches. Otherwise `[m, g1, …, gN]`: the whole match, then each of the pattern's N capture groups. |
| `regex-find-all` | `string string -> list[list[string]]` | Every non-overlapping match, left to right, each shaped like a `regex-find` result. Empty matches are kept. |
| `regex-spans` | `string string -> list[pair[int, int]]` | The `(start, end)` half-open character indices of each match that `regex-find-all` gives, in the same order, on `string-slice`'s index convention. |
| `string-lower` | `string -> string` | Each character to its lower-case form, Unicode simple case mapping. Independent of the locale; keeps the length. |
| `string-upper` | `string -> string` | Each character to its upper-case form, on the same rules. |

The `regex-*` builtins take the pattern first, as `regex-match` does. The §13.6 argument-order warning gains one sentence: "the four `regex-*` builtins take the pattern first."

**The `(?i)` prefix.** A pattern that begins with exactly the four characters `(?i)` compiles the rest without regard to case. `(?i)` anywhere else is not supported and makes the pattern invalid. `regex-match` gets this rule too. No existing call changes meaning: a `(?i)` pattern returned `False` before, and no in-tree pattern begins with `(?i)` (Context 12).

`(?i)` is chosen over a flag argument and over separate builtins:

- A flag argument changes `regex-match`'s arity and breaks every existing call.
- A `-ci` twin for each of the four doubles the catalog.
- `(?i)` is what agents already write (Context 13). This turns a silent failure into the behaviour the agent meant.

`string-lower` alone does not close `REGEX-CASE-1` once captures exist. Lower-casing the subject returns every captured group lower-cased, so the original text is lost. Lower-casing the pattern breaks a class such as `[A-Z]`. The two forms serve different uses:

- **Match without regard to case: `(?i)`.** Captures keep the subject's original text, and classes stay correct.
- **Normalize before comparing or storing: `string-lower` or `string-upper`.** Map keys, `string-contains` without regard to case, equality of identifiers.
- **The wrong combination**, which §13.6 prints as a counterexample: `(regex-find "[A-Z]+" (string-lower s))` never matches.

**Check-time rejection of an invalid literal pattern.** When the pattern argument of a `regex-*` call is a string literal, `check` compiles it under the same rules, the `(?i)` prefix included. A failure is a check error of kind `invalid-regex` that carries the library's message. A pattern that is not a literal stays total at run time: `regex-match` gives `False` and the find forms give `[]`.

### Semantics

```
Γ ⊢ p : string    Γ ⊢ s : string
───────────────────────────────────────────  (T-RegexFind)
Γ ⊢ (regex-find p s) : list[string]

Γ ⊢ p : string    Γ ⊢ s : string
───────────────────────────────────────────  (T-RegexFindAll)
Γ ⊢ (regex-find-all p s) : list[list[string]]

Γ ⊢ p : string    Γ ⊢ s : string
───────────────────────────────────────────  (T-RegexSpans)
Γ ⊢ (regex-spans p s) : list[pair[int, int]]

Γ ⊢ s : string                          Γ ⊢ s : string
──────────────────────────────  (T-Lower)   ──────────────────────────────  (T-Upper)
Γ ⊢ (string-lower s) : string           Γ ⊢ (string-upper s) : string

p is a string literal    compile(p) fails
───────────────────────────────────────────  (Check-RegexLit)
check error: invalid-regex at p
```

Evaluation, as spec text for §13.6:

- Matching is POSIX ERE through `regex-tdfa`, leftmost-longest, including for capture groups. A group that took no part reads `""`.
- Matching is newline-sensitive (A2): `.` and a negated bracket such as `[^`]` do not match a newline, and `^` and `$` match at the start and end of each line. This is `regex-tdfa`'s default, which `regex-match` has always used.
- A non-empty `regex-find` result has length N+1, where N is the number of capture groups in the pattern.
- `regex-find-all` and `regex-spans` follow `regex-tdfa`'s scan for every match. Empty matches are kept, and the scan moves one character forward after an empty match. The spec prints the measured `a*` / `baaab` result.
- Indices count characters, as `string-length` and `string-slice` do. For each span, `0 ≤ start ≤ end ≤ (string-length s)`, and `(string-slice s start end)` equals group 0 of the matching `regex-find-all` element.
- `string-lower` and `string-upper` map one character to one character and keep the length: `(string-length (string-lower s))` equals `(string-length s)`. This is not full Unicode case folding: `ß` does not become `SS`, a final `Σ` becomes `σ` and not `ς`, and ligatures such as `ﬁ` do not change.

Measured `Data.Char` behaviour (Context 14):

| Input | `string-lower` | `string-upper` | Same length |
|---|---|---|---|
| `Previously` | `previously` | `PREVIOUSLY` | yes |
| `straße` | `straße` | `STRAßE` | yes |
| `İstanbul` | `istanbul` | `İSTANBUL` | yes |
| `ΣΟΦΟΣ` | `σοφοσ` | `ΣΟΦΟΣ` | yes |
| `ǅ` | `ǆ` | `Ǆ` | yes |
| `ﬁ` | `ﬁ` | `ﬁ` | yes |
| `123-_ \n` | unchanged | unchanged | yes |

### Builtin signature and soundness argument

The five builtins are pure. They join no effect label, need no capability and map to no `Response` arm. The `regex-*` builtins join the existing preamble compromise (`AKCompilerBuiltin`, `try`/`evaluate` under `unsafePerformIO`).

1. **Strict immutability.** Each builtin is a pure function of immutable strings and builds a new value. Nothing is shared or mutated.
2. **Totality.** The regex builtins catch every exception the library raises at compile or match time. An invalid pattern gives `[]`, as `regex-match` gives `False`. The case builtins are defined for every `Char` and raise nothing. No built program can crash through these builtins, so G2 gains nothing to cover.
3. **Determinism.** `regex-tdfa` is a deterministic automaton with no backtracking, and `Data.Char` case mapping does not read the locale. The result depends only on the arguments, so a replay gives the same values.
4. **Trust.** All five are outside `Σ_auto`, as `regex-match` is. The emitter has no model of them, so a `def` that calls one falls back and stays `asserted` (`LLMLL.md` §5.3.3). No `verified` claim rests on them. The trusted base grows by the preamble functions, as it did for `regex-match`.

### Schema delta

None. Builtins are ordinary application nodes; the schema version stays 0.12.0.

## Edge cases and degenerate inputs

1. **Positive witness for Check-RegexLit.** `(def f [s: string] (regex-find "(?i)prev(" s))`: `check` exits 1 with `invalid-regex`, naming the unclosed group. Control: `(regex-find "(?i)previously" s)` passes, and on `"Previously seen"` gives `["Previously"]`. Channel: type. Citation: Check-RegexLit; Context 13.
2. **Positive witness for capture.** `(regex-find "([a-z]+)=([0-9]+)?" "x key= y")` gives `["key=", "key", ""]`. Channel: none (an executable result); pinned by a test. Citation: Context 13.
3. **The citation scan behind `REGEX-CAPTURE-1`.** *Corrected 2026-10-17 (A2).* ``(regex-find-all "`([^`]*)`" body)`` gives one element per backtick span on one line, with group 1 the text inside it. A span that crosses a newline is not matched: `[^`]` does not match a newline in `regex-tdfa`'s newline-sensitive mode. The Rev 0 text said it was matched, which was incorrect. Acceptance, measured 2026-10-17: the TOOL-RFC-005 citation pattern over the 262 living Markdown files gives 5,514 matches (2,221 citations with a slash) and zero disagreements with the retired Python reference. The reference's pattern cannot cross a newline either, so A2 does not change that result.
4. **POSIX against PCRE.** `(regex-find "(a|ab)(b?)" "ab")` gives `["ab", "ab", ""]`; Python gives `["ab", "a", "b"]`. The spec is silent by design and prints the example, because agents expect PCRE.
5. **Empty matches.** `(regex-find-all "a*" "baaab")` gives `[[""], ["aaa"], [""], [""]]`. The engineer measures the matching `regex-spans` list and the spec prints it. Silent by design; pinned by a test.
6. **An invalid pattern that is not a literal.** `(regex-find (path-pat) s)` where `path-pat` returns `"("` gives `[]` at run time, with no message. Channel: a gap, flagged. Extending Check-RegexLit to a nullary `def` whose body is a literal covers the shape `pathlint.llmll` uses; the engineer measures the cost, and it is not required.
7. **A pattern with a large compile cost**, such as `(a{1000}){1000}`. Building the automaton may use a large amount of memory, the same exposure `regex-match` has today. Silent by design: this is resource exhaustion, not a wrong value.
8. **`(?i)` not at the start.** `"x(?i)y"` is invalid: a check error as a literal, otherwise `False` or `[]` at run time. Channel: type, for a literal.
9. **Positive witness for the case builtins.** `(string-contains (string-lower "See PREVIOUSLY") "previously")` gives `true`. Pinned by a test.
10. **Characters that do not round-trip.** `(string-upper "straße")` gives `"STRAßE"`. `(string-lower "İ")` gives `"i"`, so lower then upper gives `"I"`, not `"İ"`. Silent by design: simple case mapping is the stated semantics, and the measured table is the evidence.
11. **The empty string.** `string-lower`, `string-upper` and the three `regex-*` find forms on `""` behave as stated: `""` for the case builtins, and the scan of one position for the regex forms. Pinned by a test.

## Verification mapping

No new proof obligation.

| Item | Channel | Fragment |
|---|---|---|
| The five builtin types | type | Not a solver question. |
| `invalid-regex` | type (check-time diagnostic) | Not a solver question. |
| A call in a `def` body | trust: the body falls back and the `def` stays `asserted` | Outside `Σ_auto`. The boolean-builtin class of `LLMLL.md` §5.3.3 extends to the regex builtins; the case builtins are uninterpreted. Not sent to Lean, and not `?proof-required` by default. |

**Deliberately not proposed: facts about results.** Some are QF-LIA in shape: the length of a `regex-find` result is 0 or N+1; `0 ≤ start ≤ end ≤ string-length s`; `string-lower` keeps the length. The span and group facts quantify over list elements, which is outside `Σ_auto`. The length fact for `string-lower` would be an axiom on an uninterpreted function, an addition to the closed measure catalog (`LLMLL.md` §3, which requires team consensus). All of them wait for a real program that needs them. This holds back the `RESP-FACT` pattern; it does not break from it.

## Affected surface

- `compiler/src/LLMLL/TypeCheck.hs`, `builtinEnv`: five entries.
- `compiler/src/LLMLL/TypeCheck.hs`: the `invalid-regex` check on every `regex-*` call whose pattern is a literal. This adds `regex-tdfa` as a compiler dependency, which must resolve to the version generated programs use (Risk 1).
- `compiler/src/LLMLL/CodegenHs.hs`, the preamble: `regex_find`, `regex_find_all`, `regex_spans`, `string_lower`, `string_upper`; one shared helper that removes a leading `(?i)` and compiles with `caseSensitive = False`, used by `regex_match` too; the new imports.
- `compiler/src/LLMLL/CodegenHs.hs`, `esResultForcers`: entries for all five.
- `compiler/src/LLMLL/CodegenHs.hs`, the preamble-name list: the five Haskell names, so the RESERVED-NAME-1 rename set covers a user `def` with the same name.
- `compiler/test/Spec.hs`: type, codegen and check-error cells for edge cases 1, 2, 4, 5, 8, 9, 10 and 11.
- pytest: an end-to-end `build` and run for edge cases 1 to 5 and 9, including `regex-match` with `(?i)`.
- `LLMLL.md`, by doc-lead after shipping: five §13.6 rows, the `(?i)` rule, the POSIX note, the case-mapping note and its counterexample, and the argument-order sentence; the boolean-builtin class in §3 and §5.3.3 names the four regex builtins. §12 grammar: no change.
- No change to `Parser.hs`, `ParserJSON.hs`, the schema or `FixpointEmit.hs`.
- **Additions:** five builtins, each with the soundness argument above.

## Risks

1. **The check-time and run-time pattern compilers can differ.** (Soundness of the diagnostic.) The compiler builds on `compiler/stack.yaml`; a generated program builds on the stack project `llmll build` writes. If the resolvers pick different `regex-tdfa` versions, `check` can accept a pattern that fails at run time, or reject one that works. The engineer confirms one resolver and adds a test that fails when they differ. Complicates; does not block.
2. **Agents expect PCRE.** (Verification ergonomics.) *Corrected 2026-10-17 (A1).* Non-greedy `*?`, `(?:…)` and lookaround are parse errors in `regex-tdfa`. The Rev 0 text put `\d` in the same list, which was incorrect: `\d`, `\w`, `\s` and `\n` compile and match the letters d, w, s and n. Amendment A1 makes each of them a check error as a literal. Every one of these constructs is still a silent `[]` or `False` when the pattern is computed. §13.6 names the constructs that are not supported.
3. **Edge case 6, the silent failure of a pattern that is not a literal.** (Scope.) The in-tree tool `pathlint.llmll` has this shape. The nullary-def extension closes it, at a measured cost.
4. **`regex-spans` is the only part that answers "where".** (Scope.) Without it, `REGEX-CAPTURE-1` closes for "what" only. It also makes a replace function possible with `string-slice` and `string-concat-many`. Kept in the catalog.

No professor question survives the negative test. The POSIX-against-PCRE point was settled by measurement, and the result facts are deferred to demand.

## Amendments after implementation

Both amendments were found by measurement during implementation, on regex-tdfa 1.3.2.2 (LTS 22.43). The user approved A1 with the engineer plan on 2026-10-17. A2 keeps existing behaviour and is recorded here so the spec text states it.

**A1. A letter escape that regex-tdfa reads as the letter is a check error.** `\d+` matches `ddd` and not `123`; `\w`, `\s` and `\n` behave the same way. Check-RegexLit therefore also rejects a backslash before an ASCII letter, outside a bracket expression, unless regex-tdfa gives the escape a meaning. The meaningful letters are `b` and `B` (word boundaries); `\<`, `\>`, `` \` `` and `\'` are also anchors. The diagnostic suggests the POSIX form: `[0-9]` or `[[:digit:]]` for `\d`, `[[:alnum:]_]` for `\w`, `[[:space:]]` for `\s`, and the literal character for `\n`. The allowed set is measured against the library by `Spec.hs` RX-7, not trusted.

```
p is a string literal, or the body of a nullary local definition
validatePattern(p) = RxEscape c      (c an ASCII letter, c ∉ {b, B})
───────────────────────────────────────────  (Check-RegexEscape)
check error: invalid-regex at p
```

**A2. Matching is newline-sensitive.** `regex-tdfa` compiles with `multiline = True` by default. Under it, `.` and a negated bracket do not match a newline, and `^` and `$` match at each line. `regex-match` has always compiled this way, so the four builtins keep it and agree with each other. A pattern that must cross a line has no inline flag in this pass; it can split the subject with `string-split` first. Edge case 3 above is corrected to match.

**Also measured.** The reach of Check-RegexLit includes a nullary local `def`, `def-logic` or `def-shell` whose whole body is a string literal (edge case 6), at about fifteen lines of type-checker code. `regex-spans "a*" "baaab"` gives `[(0,0), (1,4), (4,4), (5,5)]`, as edge case 5 expected.

