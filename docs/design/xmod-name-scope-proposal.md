---
name: xmod-name-scope-proposal
title: "XMOD-SCOPE: a build's top-level names share one scope"
status: "Rev 1, SETTLED 2026-10-03. Covers TYPE-SHADOW-1, XMOD-CTOR-SEVERITY-1 and XMOD-QUAL-CTOR-1. Measured on v0.27.4. The user chose R3 (qualified values resolve) over R3-min (§4.3). No professor review. Code-track: the engineer plans next."
date: 2026-10-03
author: language-team
consumers: [user, compiler-engineer, documentation-lead]
reviews: "none"
related: "dup-def-1-engineer-plan (v0.20.0, the same-module precedent); driver-ll-phase4-RESTART §6 Finding 1 (where TYPE-SHADOW-1 was found); resp-fact-proposal §16 items 5 and 10 (where the two XMOD rows were routed)"
---

# XMOD-SCOPE: a build's top-level names share one scope

## 1. Problem

The roadmap holds three open rows about names that cross a module boundary. Each row has a DECIDE marker:

- `TYPE-SHADOW-1`: two opened modules declare the same type name. `check` accepts the program and treats the two types as one. `build` fails.
- `XMOD-CTOR-SEVERITY-1`: an imported constructor written without `open` gives a warning at `check` and an error at `build`.
- `XMOD-QUAL-CTOR-1`: a qualified imported constructor such as `lib.Ran` does not type-check.

The question under all three is this. Does `LLMLL.md` §1 item 1 ("Re-binding the same name in the same scope is a compile error", norm claim `NC-011`) govern names that `open` brings into a scope?

**The answer in this proposal: yes, but `open` is the wrong boundary.** Codegen concatenates every module in a build into one `Lib.hs` (`LLMLL.md` §8.5). The whole build is therefore one scope for top-level names. GHC enforces that today at `build`. The checker does not enforce it at `check`. All three rows follow from that gap, plus one rule about type identity.

The design-reference set is the module systems of Haskell, Liquid Haskell, F\*, Idris and Dafny. All five give a nominal type an identity made of its declaring module and its name. All five reject an ambiguous unqualified name at its use site. LLMLL currently does neither. §4 explains why the smallest correct step for LLMLL is stricter than those languages for now.

## 2. Measurements (v0.27.4)

All reproductions ran against the stack build of `0.27.4` on 2026-10-03. Each entry module sits beside its imported modules. Callers are `def-shell`, so the strict-core admissibility check does not hide the result.

### 2.1 Source files

```lisp
;; modp1.llmll
(type Phase (| P1 int))
(def mk-p1 [n: int] -> Phase (P1 n))

;; modp2.llmll
(type Phase (| P2 int))
(def take-p2 [p: Phase] -> int 7)

;; fa.llmll                               ;; fb.llmll
(def f [n: int] -> int (+ n 1))           (def f [n: int] -> int (+ n 2))

;; ca.llmll                               ;; cb.llmll
(type A (| Ran int))                      (type B (| Ran int))
                                          (def take-b [b: B] -> int 3)

;; lib.llmll
(type Ctl (| Ran) (| Stop))
(def f [n: int] -> int n)

;; wrap.llmll                             ;; priv.llmll
(import fa) (open fa)                     (export pub)
(def w [n: int] -> int n)                 (def h [n: int] -> int n)
                                          (def pub [n: int] -> int n)
```

### 2.2 Results

| Id | Entry module | `check` | `build` |
|---|---|---|---|
| t1 | import and open `modp1`, `modp2`; `(def-shell go [n: int] -> int (take-p2 (mk-p1 n)))` | OK, 1 warning: `open-shadow-warning: 'Phase' from modp2` | fails: `Multiple declarations of 'Phase'` |
| t8 | as t1, body `(take-p2 n)` (the control) | error: `expected P2, got int` | not run |
| t10 | as t1, but `(open modp1 (mk-p1))` and `(open modp2 (take-p2))` | **OK, no warning** | fails: `Multiple declarations of 'Phase'` |
| t13 | import `modp1`, `modp2`; no `open`; body uses neither | **OK, no warning** | `Lib.hs` has two `data Phase` |
| t2 | import and open `fa`, `fb`; call `f` | OK, 1 warning | fails: `Multiple declarations of 'f'` |
| t3 | import and open `fa`; local `(def f …)` | OK, 1 warning | fails: `Multiple declarations of 'f'` |
| t11 | import and open `wrap` only; local `(def f …)` | **OK, no warning** | `Lib.hs` has two `f ::` |
| t12 | import and open `priv`; local `(def h …)` | **OK, no warning** | `Lib.hs` has two `h ::` |
| t4 | import and open `ca`, `cb`; `(take-b (Ran n))` | OK, 1 warning | fails: `Multiple declarations of 'Ran'` |
| t19 | one module: `(type A (\| Ran int))` and `(type B (\| Ran int))` | OK, 1 warning: duplicate constructor | error: the same text |
| t5 | import `lib`; `(def-shell mkq [] -> lib.Ctl lib.Ran)` | error: `expected lib.Ctl, got Ctl` | not run |
| t14 | import and open `lib`; `(def-shell mkq [] -> lib.Ctl Ran)` | error: `expected lib.Ctl, got Ctl` | not run |
| t15 | import and open `lib`; `(def-shell mkq [c: lib.Ctl] -> Ctl c)` | error: `expected Ctl, got lib.Ctl` | not run |
| t16 | import and open `lib`; `(def-shell mkq [] -> Ctl Ran)` | OK | builds |
| t6 | import `lib`; `(def-shell g [n: int] -> int (lib.f n))` | OK, 1 warning: `dotted function name 'lib.f' … not supported` | fails: `Variable not in scope: lib_f` |
| t7 | import `lib`; `(def-shell mkr [] -> lib.Ctl Ran)` | OK, 1 warning: `unbound variable 'Ran' (may be in scope at runtime)` | error: the same text; `check --strict` gives the error too |
| t18 | import and open `lib` twice each | OK, 2 warnings: `'Stop'` and `'f'` shadow an existing binding | builds |
| t17 | module `bi` declares `(def abs …)`; entry opens it and calls `abs` | OK, 1 warning | fails in GHC |

### 2.3 Census

The tracked tree has 22 programs that import a user module. The census ran `build --emit-only` on each and searched the emitted `Lib.hs` for a repeated top-level value, type or constructor name. **No program has one.** Four programs emit no `Lib.hs`; each one is an expected failure (two cycle fixtures, two `open`-after-`def` doc claims). A rule that rejects a repeated name across the build rejects no tracked program.

## 3. Findings

**F1. The collision does not depend on `open`.** t13, t11 and t12 pass `check` with no diagnostic, and each emits a `Lib.hs` that declares a name twice. The collision exists when two modules in one build declare a name. An `import` without `open`, an indirect import (t11) and an unexported helper (t12) are each enough. The `TYPE-SHADOW-1` row frames the defect as an `open` defect; the defect is wider.

**F2. `LLMLL.md` §8.6's collision policy describes programs that never build.** The policy is "the second `open` wins (last wins). The compiler emits a `WARNING`." t1 and t2 are that policy's own case, and both fail in GHC. Under the single-`Lib.hs` codegen, no "last wins" program can build. This is spec drift: the spec states a behaviour that the build cannot deliver.

**F3. The checker gives a nominal type the identity of its spelling.** The rule is the `TCustom` clause of `compatibleWith` in `compiler/src/LLMLL/TypeCheck.hs`: two custom types are compatible when their names are equal as text. The one rule causes two opposite failures:

- Two declarations with one spelling are one type. This is `TYPE-SHADOW-1` outcome (ii). t10 shows it with no `Phase` in the bare scope and no warning.
- One declaration with two spellings is two types. `lib.Ctl` and the opened `Ctl` are incompatible in both directions (t14, t15). This, and not constructor resolution, is the cause of `XMOD-QUAL-CTOR-1`. In t5, `lib.Ran` resolves to a value of type `Ctl`, and the mismatch is against the annotation `lib.Ctl`.

**F4. `LLMLL.md` §8.5 overstates what the checker accepts.** It says qualified references "are accepted by the type-checker but fail at codegen". That is true for a qualified function call only, and the checker warns on it (t6). A qualified type or constructor is rejected at `check` (t5, t14, t15). The verifier already accepts a qualified call: `compiler/test/fixtures/xmod-ag/use_double_qual.llmll` proves `lib.double` through the qualified key in the body-VC contract environment. Only codegen lacks qualified values.

**F5. `XMOD-CTOR-SEVERITY-1` is one case of the general `check` and `build` severity split.** `tcWarnOrError` in `TypeCheck.hs` gives a warning when `tcStrictMode` is off and an error when it is on. Plain `check` runs with it off. `build` and `check --strict` run with it on (`doCheck` in `compiler/app/Main.hs`). An imported constructor is one case of an unknown name. The warning text "may be in scope at runtime" is literally true: the name is in the flat `Lib.hs`. The strict build rejects it by policy, because §8.6 requires `open`.

**F6. A comment in the DUP-DEF-1 pass is incorrect.** The comment above `checkDuplicateTopLevel`'s caller says "a duplicate constructor still builds". t19 shows that `build` rejects it, through the same `tcWarnOrError` split. Within one module, a duplicate constructor therefore has the F5 shape too.

**F7. The same module reached twice gives spurious warnings.** t18 builds, but `check` reports two shadow warnings. The `SOpen` handler compares names only. It does not ask whether the existing binding came from the same declaration.

## 4. Design

### 4.1 R1: one scope per build

**Rule.** Let the build closure of an entry module be the entry module plus every module it reaches through `import`, directly or indirectly. Within a build closure, each top-level name is declared by one module. A second declaration of the name in another module is a `check` error in both strictness modes.

**Namespaces.** There are two namespaces, as in DUP-DEF-1 and in the emitted Haskell:

- the type namespace: `type` and `def-interface` names;
- the value namespace: `def`, `def-shell` and constructor names.

`(type Box (| Box int))` therefore stays legal.

**Identity of a declaration.** A declaration is the pair (declaring module path, name). One declaration reached by two paths is not a collision. t18 must check with no diagnostic.

**Diagnostic.** The error names both declaring modules and the import path to each. Example: `duplicate top-level definition 'Phase': type declared in modp1 and in modp2; a build's top-level names share one scope (LLMLL.md §1, §8.5)`. Proposed `diagKind`: `duplicate-definition`, the DUP-DEF-1 kind, so a tool that handles one handles both.

**What R1 replaces.** The `open-shadow-warning` has no remaining case. Any collision it reports is now an R1 error, except the t18 case, which is not a collision. The §8.6 "last wins" policy is withdrawn.

**Same-module constructors.** A constructor declared twice in one module becomes an unconditional error, as DUP-DEF-1 made a duplicate binding (F6, t19).

### 4.2 R2: a nominal type is its declaring module plus its name

**Rule.** The identity of a declared type is (declaring module path, name). The spellings `M.T` and an opened `T` denote one type when M declares T.

**Why R1 makes this cheap.** Under R1, a bare type name in a build closure has exactly one declaring module. A qualified spelling `M.T` can therefore be resolved by checking that M declares T and that the current module imports M, then dropping the qualifier. `compatibleWith` keeps its text comparison over resolved names.

**Effect.** t14 and t15 check. `TYPE-SHADOW-1` outcome (ii) cannot occur, because R1 rejects its precondition. The type-identity statement still gets its own test, as the roadmap row asks: a value of one sum must not satisfy an annotation that names another sum.

### 4.3 R3: a qualified value resolves (chosen 2026-10-03)

**Rule.** `M.f` and `M.C` resolve when the current module imports M and M exports f or C. `open` is not required. Codegen emits the bare Haskell name.

**Why R1 makes this safe.** The bare name is unique in `Lib.hs`, so erasing the qualifier cannot capture another declaration. The verifier already accepts the qualified call (F4). This delivers what §8.5.1 calls "planned" without per-module Haskell output.

**Smaller alternative (R3-min).** Reject every qualified value reference at `check` in both modes. The message says `add (open M)`. This keeps the release a pure repair and adds no surface. The cost: `use_double_qual.llmll` changes from a passing fixture to a rejected one, and §8.5.1 stays unshipped.

**Decision (Rev 1, user, 2026-10-03): R3.** R3-min is not taken. R3 adds a working surface form, so under the roadmap's lifted-exclusions note it is an addition and carries a soundness argument. The argument is the paragraph above. R1 is its precondition, and R3 must not ship without R1.

### 4.4 R4: a name that exists in an imported module but is not in scope is an error

**Rule.** At an unknown bare name x, look up x in the build closure. If an imported module declares x, report an error in both strictness modes. The message names the module and the fix:

- x is exported and the module is not opened: `'Ran' is declared in lib; add (open lib) or write lib.Ran`. With R3-min, the second option is dropped.
- x is not exported: `'a-step' is declared in amain and is not exported`.

**Scope of R4.** An unknown name that no module in the closure declares keeps plain `check`'s current warning. That policy serves holes and incomplete programs, and this proposal does not change it.

**Effect on `RESP-FACT-1`.** `resp-fact-proposal.md` §16 item 5 says the design needs the behaviour and does not need the asymmetry. Its test RF-E8 asserts the check warning `unknown function 'a-step'`. Under R4 the same condition gives an error with a different text. The test changes; the RESP-FACT-1 guarantee does not.

### 4.5 What does not change

- No surface syntax changes. With R3, an existing form starts to work.
- No JSON-AST schema change. A qualified name is already a dotted string in the `name` fields.
- No change to per-module Haskell output. §8.5.1's per-module codegen stays the long-term path. When it ships, R1 can narrow from "one scope per build" to "one scope per module plus its opened names". §8.6 must then choose a rule for an ambiguous bare name. This proposal recommends an error at the use site, not "last wins", to match the five reference languages.

## 5. Edge cases

| # | Input | Expected behaviour | Channel | Handled by |
|---|---|---|---|---|
| E1 | t13: two imports declare `Phase`; nothing opened; nothing used. **Positive witness:** the minimal input that must fire. | R1 error naming `modp1` and `modp2` | type | R1, build-closure pass |
| E2 | t1, t10: the `TYPE-SHADOW-1` witness, with full or selective `open` | R1 error at the second `Phase`; type identity is never reached | type | R1 |
| E3 | t12: a local `h` and a library's unexported `h` | R1 error. A usability cost, accepted (§7 risk 1) | type | R1 (unexported names are in the closure) |
| E4 | t11: the collision is reached through an indirect import | R1 error; the message gives the import path `t11 → wrap → fa` | type | R1 |
| E5 | t18: the same module imported and opened twice | No diagnostic | type | R1 declaration identity |
| E6 | t4: constructor `Ran` under types `A` and `B` in two modules | R1 error (value namespace) | type | R1 |
| E7 | `(type Box (\| Box int))` in one module, imported elsewhere | No diagnostic (two namespaces) | type | R1 namespaces |
| E8 | t14, t15: `lib.Ctl` against the opened `Ctl` | Accepted; one type | type | R2 |
| E9 | t8 as a regression control: `int` where `Phase` is expected | Still rejected | type | unchanged |
| E10 | t5, t6: `lib.Ran`, `lib.f` without `open` | R3: accepted and builds. R3-min: error with the `open` hint | type | R3 or R3-min |
| E11 | t7, RF-E8: imported name without `open`; unexported name | R4 error in both modes | type | R4 |
| E12 | t19: one module declares `Ran` under two types | Error in both modes | type | §4.1 same-module rule |
| E13 | t17: a module declares `abs`, which is a builtin | Spec is silent (gap, flagged). Outside this proposal; §6 routes it | none | not handled |

## 6. Verification mapping

All four rules are name resolution in the type channel. Each is a set-membership question over a finite closure, decidable in time linear in the number of top-level declarations.

- **New proof obligations:** none. Nothing is emitted to liquid-fixpoint, and nothing escapes to Lean (`LLMLL.md` §5.3.3, §5.3.5 are not touched).
- **Effect on the solver namespace:** R1 makes the `ctor_`-prefixed constructor symbols (`FixpointIR.fqCtorSym`) unique across a build. Two same-named constructors could otherwise reach one `.fq` file. That case was not measured, and R1 makes it unreachable.
- **Trust:** no change. R3 lets a qualified call reach the contract environment through the key the verifier already uses.

## 7. Affected surface

- `compiler/src/LLMLL/TypeCheck.hs`: widen `checkDuplicateTopLevel` from one module to the build closure (R1); make the same-module constructor duplicate an error (§4.1); retire the warning in the `SOpen` handler (R1, F7); resolve qualified type spellings before `compatibleWith` (R2); resolve qualified values (R3) or reject them (R3-min); the R4 lookup at the two `call to unknown function` sites and the `unbound variable` site.
- `compiler/src/LLMLL/Module.hs`: expose the declarations of every module in the closure, with their declaring path and export status. The checker today sees exported names under qualified keys only.
- `compiler/src/LLMLL/CodegenHs.hs`: emit the bare name for a resolved qualified value (R3 only).
- Tests whose expectations change: RF-E8 in `compiler/test/Spec.hs`; the `open-shadow-warning` test in `compiler/test/ModuleSpec.hs`. Under R3, `use_double_qual.llmll` gains a build test: it must build and run.
- Spec, for documentation-lead after the code ships: `LLMLL.md` §1 item 1 (state that a build's top-level names share one scope); §8.5 (correct F4); §8.5.1 (shipped under R3, or unchanged under R3-min); §8.6 (withdraw "last wins"). Norm claim `NC-011` gains a second fixture: the E1 witness.
- Roadmap, for documentation-lead: close the three DECIDE markers to PLAN. File a new row for E13 (a module may declare a builtin's name).

## 8. Risks

1. **Unexported helpers collide.** Usability. A hub library's private `helper` blocks a local `helper` (E3). This states the current codegen honestly: GHC already rejects these programs. Only per-module Haskell output removes the cost (§4.5). The census found no tracked case. Bite: complicates adoption at scale; does not block.
2. **R3 is an addition, not a repair.** Scope. It must ship after R1 or with it. If the user wants a pure repair now, take R3-min. Bite: a decision, not a defect.
3. **Diagnostics change for existing tests.** Spec drift resolution. Two tests assert today's warnings (§7). Each assertion is changed in the same commit, with the reason. Bite: small.
4. **The closure lookup in R4 depends on what `Module.hs` keeps.** Verification ergonomics. Unexported names must be visible to the checker for the diagnostic and invisible for resolution. A mistake makes an unexported name usable. Bite: complicates the engineer's plan; one negative test (E11, unexported case) covers it.
