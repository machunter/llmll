---
title: FFI determinism — may an FFI callee be trusted as a function for CALL-CONGRUENCE-1?
status: Rev 1, SETTLED 2026-10-31 (user-approved). Rev 1 adopts the professor review of Rev 0 (verdict "accept with changes", C1–C7). For C1, the user chose the professor's smaller alternative after a build measurement on 0.33.4.
rows: FFI-TIER2-REFUSE-1, REGEX-ASYNC-1 (new, G1, PLAN; prerequisites of CALL-CONGRUENCE-1); CALL-CONGRUENCE-1 (G1, PLAN; amended to the rules below); FFI-DOC-DRIFT-1 (new, G3, DOC); FFI-TIER2-1 (new, G7, DECIDE); FFI-DETERM-GATE-1 (new, G7, PLAN); FFI-UNINTERP-1 (G1, DECIDE; one sentence added)
review: one professor pass (of Rev 0, 2026-10-31), folded below as the Appendix. The standalone review was never committed, so no archive copy and no redirect stub exist.
---

# FFI determinism — may an FFI callee be trusted as a function for CALL-CONGRUENCE-1?

**Status: Rev 1, SETTLED 2026-10-31.** The language-team wrote Rev 0 on 2026-10-31. The professor reviewed Rev 0 the same day with the verdict "accept with changes" (C1–C7). The user then measured that a `c.*` program does not build, and chose the professor's smaller alternative for C1. Rev 1 makes every change. The professor review is folded below as the [Appendix](#appendix--professor-review-log).

## Decisions (settled by the user, 2026-10-31)

1. **First, a small release.** `check` refuses every `c.*` import until Tier 2 is built properly (`FFI-TIER2-REFUSE-1`). The same release makes `llmll_rxTotal` rethrow asynchronous exceptions (`REGEX-ASYNC-1`).
2. **Then `CALL-CONGRUENCE-1`, under the rules in Part 3.** A Tier 1 `haskell.*` callee is trusted as deterministic (Option B). The D9 row text says "deterministic within one run" and is recorded as a strengthening.
3. **Option C (an opt-in purity attestation) stays rejected.** Option A (exclusion) is not adopted. Option D is kept only as a growth gate (`FFI-DETERM-GATE-1`).
4. **Proper Tier 2 work is a separate decision** (`FFI-TIER2-1`). It covers C type marshalling, the D4 effect refusal and the `ffi_assumptions` disclosure for `c.*`.

## Changes from Rev 0

| Review item | Disposition | Where |
|---|---|---|
| C1 (H1): the fallback "skip function-parameter pairs" is unsound, because W8 reaches `c.*` through a `def-shell` wrapper | **Adopted, smaller alternative.** The fallback is deleted. The user measured that no `c.*` program builds, so `check` refuses `c.*`. `FFI-TIER2-DISCLOSE-1` is not filed; its content moves to `FFI-TIER2-1`. | Part 1; "Measurements" |
| C2 (H2): rewording D9 is a strengthening, not a sharpening; "within one run" | **Adopted.** | Part 3, rule R4 |
| C3 (H3): `llmll_rxTotal` is inside the partial-correctness guarantee | **Adopted.** Rev 0's "outside partial correctness" claim is withdrawn. The fix is row `REGEX-ASYNC-1`, a prerequisite. | Part 2 |
| C4 (H4): replace the sort list with a criterion | **Adopted.** `float` is excluded on both sides. The native-string forward condition is recorded. | Part 3, rule R2 |
| C5 (H6): key pairs on binder identity; shadowing fixture | **Adopted.** | Part 3, rule R3 |
| C6 (H5): `FFI-UNINTERP-1` keeps the binder-only Ackermann form | **Adopted.** One sentence goes into that row. | Part 6 |
| C7 (H7, H8): remove `def-logic`; split the `c.*` D4 refusal | **Adopted.** `def-logic` is a removed construct (`LLMLL.md` §4.1, legacy-grammar note). The D4 refusal for `c.*` moves to `FFI-TIER2-1`. Under the refusal it has no live case. | Part 5; Part 7 |
| Professor open question 1: does a `c.*` program build end to end? | **Answered: no.** Three defects stop it (see "Measurements", M-BUILD). | "Measurements" |

## Restatement

`CALL-CONGRUENCE-1` emits the Ackermann hypothesis `(args_i = args_j) ⇒ (r_i = r_j)` for each pair of calls to one callee in one constraint environment. That hypothesis is sound only when the callee is a deterministic function of its arguments within one run. This record decides which callees meet that condition. It also decides how the trust report discloses the assumption, and what happens to Tier 2 (`c.*`), which no current rule covers.

## Summary of findings

1. **A direct call to an FFI entry never reaches the solver today.** The contract environment holds no interface entry, so the body falls back with `Refused by: app:<entry>`. The row's clause "over non-FFI callees" excludes nothing that the Ackermann pass sees.
2. **FFI reaches congruence by two other paths.** Path 1 is a `def-shell` wrapper that calls an entry (W-WRAP, W8). Path 2 is an entry passed to a function-typed parameter (W-VAL, W-C). An exclusion by name covers neither path.
3. **For Tier 1, congruence needs no new assumption once D9 says "deterministic".** The D9 row already assumes "no hidden effects at the declared type". Under the broad reading of "effects", that gives determinism. Rev 1 writes the broad reading into the row text (rule R4).
4. **Tier 2 is outside every Tier 1 rule, and it does not build.** No D4 refusal, no D3 result check and no `ffi_assumptions` row reaches `c.*`. W8 shows a `c.*` callee that congruence would make `verified` with no disclosed assumption. The measured build failure makes refusal at `check` the smallest sound move.
5. **LLMLL-native callees are deterministic, with one runtime defect.** `llmll_rxTotal` catches asynchronous exceptions inside `unsafePerformIO`. That defect can make two equal calls disagree in a run that ends normally. `REGEX-ASYNC-1` removes it.

## Context located

1. `docs/compiler-team-roadmap.md` — `CALL-CONGRUENCE-1` (G1), with its former "Decide first" clause.
2. `docs/compiler-team-roadmap.md` — `FFI-CONTRACT-1` and `FFI-UNINTERP-1` (G1, DECIDE); `FFI-OPAQUE-1` (G7, DECIDE).
3. `docs/compiler-team-roadmap.md` — `SAFE-HASKELL-CLAIM-1`: the generated runtime uses `unsafePerformIO`.
4. `docs/design/ffi-tier1-proposal.md` — D4 (effect refusal), D5 (closed nine-module set), D9 (row meaning), E6 (an entry used as a value is accepted).
5. `docs/design/byte-io-proposal.md` — P16 (modular reading of `refuted`), P18 (binder-only Ackermann form), witnesses A1, A2, A4.
6. `docs/design/fn-param-uf-1-proposal.md` — "Congruence": true for calls that return, under call-by-value.
7. `LLMLL.md` §4.7 (call-by-value; reuse of an earlier call's value), §5.3.3 (abstraction verdict; `ELet` alpha-renaming), §7 (Tier table, reach table, trust report, Tier 2 example and pitfall), §9.1 ("The AI's logic is pure").
8. `compiler/src/LLMLL/FixpointEmit.hs` — `buildContractEnvWith` (no `SImport` clause), `fnParamCallees` (unioned without the `FN-SHADOW-1` filter), `scopedContractEnv`.
9. `compiler/src/LLMLL/Ffi.hs` — `ffiPackageModules` (nine modules), `ffiImportErrors` (returns `[]` for any non-`haskell.*` import), `entryErrors` (`ffi-effect-refused`).
10. `compiler/src/LLMLL/TypeCheck.hs` — the import clause runs `ffiImportErrors` for every import.
11. `compiler/src/LLMLL/CodegenHs.hs` — `classifyImport` (`CLibImport`), `emitFfiModHs`, `emitFfiStub`, `emitFfiDecl` (`foreign import ccall "<LLMLL name>" <hs name> :: <emitted type>`), `llmll_rxTotal`.
12. `compiler/src/LLMLL/TrustReport.hs` — `markFfiAssumptions` (`haskell.*` only); the row note string `ffiNote`.
13. `compiler/test/Spec.hs` — test "AT-3 the FFI re-export module and each C stub carry the pragma": the only test that exercises `c.*` (four lines: the `ImportAt "c.mylib"` value and three assertions on `cgFfiModHs` and `cgFfiFiles`).
14. `docs/llmll-trust-report.schema.json` — `ffi_assumptions` description.

## Measurements

All runs used llmll 0.33.4 (built 2026-10-31, with the `ABSTRACTION-VERDICT-1` rule).

| Id | Program | Outcome today | Under the Rev 0 row text |
|---|---|---|---|
| W-DIR | `twice-len` = `(- (length s) (length s))`, `length` a `haskell.text` entry, post `(= result 0)` | fallback, `Refused by: app:length`; `≈ assumes haskell.text export length` | unchanged |
| W-WRAP | `g` = `(length s)`; `twice-g` = `(- (g s) (g s))` | `abstraction:app:g` fallback; `≈ inherits haskell.text export length via g` | `verified` |
| W-VAL | `apply-twice [f: (fn [string] -> int) x]` = `(- (f x) (f x))`; `use` passes `length` | `abstraction:app:f` fallback; `use` carries `≈ assumes … length` | `apply-twice` `verified` |
| W-C | as W-VAL, with `c.stdlib` `rand-of` passed to `apply-twice [f: (fn [int] -> int)]` | `abstraction:app:f` fallback; **no assumption row** | `apply-twice` `verified`; no row |
| W8 | `def-shell g` = `(rand-of x)`, `rand-of` a `c.stdlib` entry; `twice-g` = `(- (g x) (g x))` (professor) | `abstraction-unsafe; abstraction:app:g`; **no assumption row** | `twice-g` `verified`; no row |
| M-BUILD | `(import c.stdlib (interface [[rand-of (fn [x: int] -> int)]]))`, called from `def-main` `:init` (user) | `check` passes; **`build` exits 1** | — |

**M-BUILD shows three independent defects.** Each one alone stops the build.

1. The generated `src/FFI/Stdlib.hs` declares `foreign import ccall "rand-of" rand_of :: Integer -> Integer`. GHC refuses it: "`Integer` cannot be marshalled in a foreign call" (GHC-89401). LLMLL `int` lowers to `Integer`, so no stub with an `int` in its type compiles.
2. The C symbol in the `ccall` string is the LLMLL entry name (`rand-of`). A hyphen is not legal in a C identifier, so the declaration cannot name the intended C function.
3. `Main.hs` reports `Variable not in scope: rand_of`. `emitFfiModHs` writes the `FFI` re-export module, but nothing in `CodegenHs.hs` emits `import FFI` into `Lib.hs` or `Main.hs`. So no call site resolves, whatever the entry's type.

No tracked program imports `c.*` (`git grep` over `*.llmll` and `*.json`). `LLMLL.md` §7 says that an unimplemented stub "will compile but fail at link time or panic at runtime". That is incorrect: with an `int` type, it does not compile (drift D3).

## Design

### Part 1 — Refuse `c.*` at `check` (`FFI-TIER2-REFUSE-1`)

**Rule.** `check` refuses every import whose path begins `c.`, with or without an `interface` list, in S-expression and JSON-AST source. The refusal is an error with a new diagnostic kind. Proposed kind and message:

```
ffi-tier2-refused: c.stdlib: Tier 2 (C) imports are not supported. The generated
stub cannot marshal LLMLL types, and no call site can reach it. Use a haskell.*
Tier 1 import or a wasi.* builtin.
```

**Placement.** `ffiImportErrors` in `Ffi.hs` returns `[]` for a non-`haskell.*` path today. It gains a `c.` case. `TypeCheck.hs` already calls it for every import, so no new call site is needed.

**Soundness argument.** This is a removal, not an addition. The refused surface never produced a running program (M-BUILD). After the refusal, no `c.*` entry is in `tcEnv`, so W-C and W8 fail `check` and cannot reach `verify`. The Tier 1 argument in Part 3 is then the complete argument for FFI.

**Codegen.** The Tier 2 generator (`emitFfiModHs`, `emitFfiStub`, `emitFfiDecl`) becomes unreachable from the command line. The engineer chooses to keep it for `FFI-TIER2-1` or to delete it. Spec.hs test AT-3 calls `generateHaskell` directly, below `check`. If the generator stays, AT-3 stays and is labelled as a codegen-only test. If the generator goes, AT-3 loses its `c.*` half. In both cases, a new test runs `check` on the M-BUILD witness and expects `ffi-tier2-refused`.

**Fixture.** The M-BUILD witness is refused by `check` with `ffi-tier2-refused`, exit 1. W8 is refused the same way.

### Part 2 — Rethrow asynchronous exceptions in `llmll_rxTotal` (`REGEX-ASYNC-1`)

`llmll_rxTotal` runs `try (evaluate …)` under `unsafePerformIO` and catches `SomeException`. That also catches `StackOverflow`, `HeapOverflow` and `UserInterrupt`. Without the catch, such an exception ends the run, and partial correctness holds vacuously. With the catch, the run continues and ends normally with the fallback value. GHC also keeps that value in the thunk. So two equal calls can disagree inside a run that the guarantee covers (professor H3). Rev 0 said the case was outside the guarantee; that claim is withdrawn.

**Rule.** `llmll_rxTotal` rethrows any exception for which `fromException e :: Maybe SomeAsyncException` is `Just`. A synchronous exception (an invalid pattern) keeps the fallback. That fallback is deterministic, because it does not depend on which synchronous exception occurred. The runtime preamble's `Control.Exception` import list grows by the names the rethrow needs.

**Fixture.** A Haskell-level test that `llmll_rxTotal` returns the fallback for an `ErrorCall` and rethrows a `UserInterrupt` thrown inside the forced value.

### Part 3 — The congruence rules (`CALL-CONGRUENCE-1`)

**R1. Callee scope (Option B).** Every callee in the contract environment and every function-typed parameter gets Ackermann hypotheses. The emitter carries no FFI test. A Tier 1 interface entry that later enters the contract environment (`FFI-UNINTERP-1`) gets them too, under Part 6.

**R2. Sort criterion (replaces the sort list).** A pair of calls gets a hypothesis only when both conditions hold.

- Each argument sort has Leibniz equality at run time, and the run-time-to-model abstraction is injective on it.
- The result sort's model `=` agrees with LLMLL `=` at run time.

The current instances are `int` (run-time `Integer` and Z3 `Int` are both unbounded), `bool`, and `string` (structural `Eq`; the model sort is the opaque carrier `FQStr`). `float` is excluded on both sides: NaN breaks reflexivity on a result, and `+0.0 == -0.0` breaks substitution on an argument. **Forward condition for `string`.** If `Str` moves onto SMT-LIB native strings, the model's character range is smaller than Haskell `Char`. The abstraction is then not injective, and string-argument congruence must be justified again. **Forward condition for `float`.** A future float reflection maps LLMLL `=` to `fp.eq` and never uses it as a congruence.

**R3. Callee identity.** Pairs are keyed on the callee binder after alpha-renaming, not on the surface name. `fnParamCallees` is unioned into the contract environment without the `FN-SHADOW-1` filter. So a body that rebinds a parameter name (`(let [[f h]] …)`, or a `match` arm that binds `f`) must not equate `(f x)` with `(h x)`. **Fixture:** a shadowed function-typed parameter whose post needs the two calls to agree. It stays `refuted` or falls back, and never becomes `verified`.

**R4. D9 row text (strengthening, C2).** The row meaning becomes:

> this verdict assumes `<package>.<export>` is deterministic within one run at the declared type (equal arguments give equal results), total, and with no hidden effects.

This is a strengthening of the disclosed assumption, not a rewording. "No hidden effects" alone has a narrow reading (no observable writes) under which a function may still read a clock or an address. `CALL-CONGRUENCE-1` is the first verifier rule that depends on the row: today a direct FFI call and a wrapper both fall back, so no proof uses D9 determinism. `trust_report_version` does not change, because a stronger stated assumption does not make an earlier verdict incorrect. "Within one run" is deliberate. A per-process hash salt is constant within a run, so it does not break congruence. The text changes in three places: `ffiNote` in `TrustReport.hs`, the `ffi_assumptions` description in `docs/llmll-trust-report.schema.json`, and `LLMLL.md` §7 "Trust report".

**R5. Placement of the assumption.** In W-VAL, `apply-twice` is verified for every deterministic `f`. The assumption enters where the FFI value is injected, at `use`, and `use` already carries the row. In W-WRAP, `twice-g` already carries `≈ inherits … via g`. So no new trust key and no new trust level are needed.

**Prerequisites.** `FFI-TIER2-REFUSE-1` and `REGEX-ASYNC-1` ship first, or in the same release. `ABSTRACTION-VERDICT-1` (shipped v0.34.0) stays the sound backstop for every pair that R1–R3 do not cover.

**Fixtures.** A1, A2, W5 and `gs` verify. A4 returns to `refuted`. The R3 shadowing fixture never becomes `verified`. W-WRAP's `twice-g` is `verified` and keeps its `≈ inherits` row. New `verified` records appear, so the committed sidecars are verified again.

### Part 4 — Options considered

**Option A, exclude FFI from congruence.** Sound only in a transitive form: no hypothesis for a callee whose trust entry would carry an `ffi_assumptions` row, and none for any function-typed parameter. The second clause loses W5. It also makes the verifier treat Tier 1 determinism as doubtful while the trust report assumes it. That is two policies for one fact. **Not adopted.**

**Option B, trust FFI as deterministic by default.** Adopted for Tier 1 (R1, R4). The argument: D4 and D7 put each entry at a non-`IO` Haskell type. At such a type, a Haskell function denotes a function unless the library hides an effect, and D9 (as reworded) assumes and discloses that it does not. Congruence needs less than D9: it does not need totality (Part 6). The modular reading of `refuted` (P16) quantifies the callee over functions, and the Ackermann hypothesis is the functionality axiom of that quantifier.

**Option C, opt-in purity attestation (`:pure` on an entry).** **Rejected.** An unattested entry is still assumed effect-free by D9, so the attestation adds no information. A missing attestation creates an incoherent state: assumed effect-free by the trust report and treated as impure by the verifier. C also needs Option A's transitive machinery for unattested entries. Why3's `val function` is the opt-in precedent; Tier 1 already holds that position through D4, D5 and D7 (professor, "Literature precedent").

**Option D, trust only an allowlist of modules.** The allowlist exists: D5 closes Tier 1 to nine modules. A `ghc -e ':browse'` sweep in `lts-22.43` found no nondeterministic export reachable under D3 and D10. So D, applied today, equals B. **Kept as a growth gate** (`FFI-DETERM-GATE-1`, below).

### Part 5 — LLMLL-native callees

Native callees are `def`, `def-shell`, `letrec`, `def-invariant`, and function-typed parameters bound to LLMLL values. (Rev 0 listed `def-logic`. It is a removed construct, and the `SDefLogic` clause in `buildContractEnvWith` is dead code for it.)

- Every `wasi.*` builtin returns `Command`. Evaluating a `Command` builds an action and does not run it (`LLMLL.md` §4.7). A response reaches logic only as a function argument (§9.7). So no logic function reads the world.
- `do` lowers to a pure `let` chain. Closures capture immutable values. A hole fails at every call.
- In the runtime, the `llmll_strIx` cache gives the same answer with or without the cache. The response slot is written and read only inside `IO`. `timeout` wraps only `waitForProcess`.
- The one defect is `llmll_rxTotal` (Part 2). After `REGEX-ASYNC-1`, native callees are deterministic within one run.

### Part 6 — Note for `FFI-UNINTERP-1` (C6)

The Ackermann hypothesis relates existing result binders only. It adds no function symbol and no term for a call that was not reached. Under call-by-value with strict codegen, a result binder exists only on paths where the call returned. So congruence needs no totality. When `FFI-UNINTERP-1` admits an FFI entry, it keeps this binder-only form. An axiom form (`∀x. pre(x) ⇒ post(x, f x)`) over a partial `f` can be inconsistent, so that form brings a totality obligation.

### Part 7 — Proper Tier 2 work (`FFI-TIER2-1`, DECIDE)

Tier 2 can return after the refusal only with all of these parts:

1. **Type marshalling.** A mapping from LLMLL types to C types (`int` to a sized `CLLong` or similar, with a range rule), so that the generated `foreign import` compiles. The narrowing is partial, as in `FFI-NARROW-1`.
2. **Symbol names.** An explicit C symbol per entry, separate from the LLMLL name.
3. **Reach.** An `import FFI` (or a qualified import) in `Lib.hs` and `Main.hs` when a `c.*` import exists.
4. **D4 for `c.*`.** `ffi-effect-refused` for an entry that mentions `Command` or `Promise`.
5. **D9 for `c.*`.** `markFfiAssumptions` covers `c.*`, with `package: "c.<lib>"`. The row text names the stub file: "assumes the developer-written stub in `src/FFI/<Lib>.hs` is deterministic within one run, total, and with no hidden effects". This assumption is much stronger than the Tier 1 one, so the text must say so plainly (professor H9).
6. **Fixtures.** W-C and W8 build and run. Under congruence, `apply-twice` and `twice-g` are `verified`, and `use` and `twice-g` carry a `c.stdlib` row.

The decision this row waits on is demand. No tracked program uses `c.*`, and Tier 1 plus `wasi.*` cover the measured cases.

### Part 8 — Determinism gate on Tier 1 growth (`FFI-DETERM-GATE-1`)

D5 gains one sentence. A package or boundary type added to Tier 1 carries a determinism review of the exports it makes reachable. An export with undefined or effectful behaviour at a pure type is refused at `check` by name. The first case is `Data.Vector.unsafe*` (`unsafeIndex`, `unsafeHead`, `unsafeLast` and the rest). Out-of-bounds use reads undefined memory, so two equal calls can disagree. They are unreachable today because `Vector` has no boundary type. They become reachable when `FFI-OPAQUE-1` ships. `ffi-name-unmappable` is the precedent for a refusal by name. A per-export denylist in `Ffi.hs` is sufficient.

## Edge cases and degenerate inputs

1. **W8, a `c.*` callee through a `def-shell` wrapper.** Expected: `check` refuses the import with `ffi-tier2-refused`. Channel: type (`check`). Citation: Part 1.
2. **W-C, a `c.*` entry passed as a value.** Expected: refused the same way. Channel: type. Citation: Part 1.
3. **A `c.*` import with no `interface` list, or in JSON-AST.** Expected: refused; the rule reads the import path only. Channel: type. Citation: Part 1.
4. **A `c.*` import inside an imported LLMLL module.** Expected: refused when that module is checked; the importer fails `check`. Channel: type. Citation: the import clause in `TypeCheck.hs`.
5. **W-WRAP, a Tier 1 wrapper called twice.** Expected: `twice-g` `verified`, and it keeps `≈ inherits haskell.text export length via g`. Channel: contract plus trust. Citation: R1, R5.
6. **W-DIR, two direct calls to a Tier 1 entry.** Expected: unchanged fallback `app:length`; no interface entry is in the contract environment. Channel: contract (fallback). Becomes live under `FFI-UNINTERP-1`, under Part 6.
7. **A shadowed function-typed parameter (R3 fixture, positive witness).** `(def-shell k [f: (fn [int] -> int) h: (fn [int] -> int) x: int] -> int (post (= result 0)) (- (f x) (let [[f h]] (f x))))`. Expected: never `verified`; the two calls name different binders. Channel: contract. Citation: R3.
8. **A partial Tier 1 export called twice with equal arguments** (`split-on` with an empty separator). Expected: the hypothesis is sound; the first call stops the run. Channel: spec is silent (intentional); totality is not needed. Citation: Part 6.
9. **Equal arguments on some paths only** (A2: `(if (= a b) (- (g a) (g b)) 0)`). Expected: `verified`; the hypothesis fires where the solver derives `a = b`. Channel: contract. Citation: `byte-io-proposal.md` A2.
10. **A false post that needs two self-calls** (A4). Expected: `refuted`; the hypothesis removes no real countermodel. Channel: contract.
11. **A regex call under heap exhaustion or Ctrl-C.** Expected after `REGEX-ASYNC-1`: the exception ends the run; no fallback value is produced. Channel: runtime; partial correctness holds vacuously. Citation: Part 2.
12. **A `float` argument or result.** Expected: no hypothesis. Today a `float` binder falls back anyway. Channel: emitter rule. Citation: R2.
13. **`Data.Vector.unsafeIndex` after `FFI-OPAQUE-1`.** Expected: refused by name at `check`. Channel: type. Citation: Part 8.

## Verification mapping

| Obligation or fact | Channel | Fragment |
|---|---|---|
| Ackermann hypothesis `(a_i = a_j) ⇒ (r_i = r_j)` at sorts that meet R2 | contract (a hypothesis in the constraint environment, not an obligation) | (a) QF-LIA plus `Str` carrier equality; no new symbol (`LLMLL.md` §5.3.3) |
| FFI determinism (Tier 1) | trust (`ffi_assumptions` row, strengthened text) | not a VC; assumed and disclosed |
| `ffi-tier2-refused` | type (`check`) | syntactic |
| Determinism denylist | type (`check`) | syntactic |
| Asynchronous-exception rethrow | runtime | not a VC |

No obligation routes to Lean.

## Affected surface

- `compiler/src/LLMLL/Ffi.hs` — the `c.` case in `ffiImportErrors` (Part 1); later, the denylist (Part 8).
- `compiler/src/LLMLL/CodegenHs.hs` — `llmll_rxTotal` and the preamble's `Control.Exception` import (Part 2); the Tier 2 generator kept or removed (Part 1).
- `compiler/test/Spec.hs` — test AT-3; a new `check` test for the refusal; a test for the rethrow.
- `compiler/src/LLMLL/FixpointEmit.hs` — the Ackermann pass, keyed on binder identity (R3), with the sort criterion (R2).
- `compiler/src/LLMLL/TrustReport.hs` (`ffiNote`) and `docs/llmll-trust-report.schema.json` — row text (R4).
- `LLMLL.md` §7 — Tier table (Tier 2 refused), Tier 2 example and pitfall, reach table (D1), trust-report row meaning (R4). Documentation-lead's slot (`FFI-DOC-DRIFT-1` and each release's doc pass).
- `docs/design/ffi-tier1-proposal.md` — D5 gate sentence and D9 text, by amendment note.
- No JSON-AST change. No addition: Part 1 removes a surface; Parts 2 and 3 change existing rules.

## Spec drift found

- **D1 (minor).** The `LLMLL.md` §7 reach table says `directory` and `process` reach "none, every export is IO". Measured with `ghc -e ':browse'` in `lts-22.43`: `System.Directory.exeExtension :: String` and `System.Process.showCommandForUser :: FilePath -> [String] -> String` are pure and reachable under D3. Each is deterministic. The table moves, not the rule.
- **D2 (closed by Part 1).** `LLMLL.md` §7 puts `c.*` under the same "declared interface" heading as `haskell.*`, but no Tier 1 rule reaches it.
- **D3.** `LLMLL.md` §7, the Tier 2 pitfall, says an unimplemented stub "will compile but fail at link time or panic at runtime". M-BUILD shows that a stub with an `int` type does not compile. After `FFI-TIER2-REFUSE-1`, the Tier 2 example and pitfall describe a refused surface.
- **D4 (code, minor).** `buildContractEnvWith` keeps an `SDefLogic` clause for a construct the parser refuses. No action is filed.

**Ownership.** The language-team does not edit `LLMLL.md`. D1 and D3 go to the documentation-lead as `FFI-DOC-DRIFT-1`. The D3 rewrite lands with the `FFI-TIER2-REFUSE-1` release, because the correct text is "refused".

## Risks

1. **D9 is an unchecked assumption.** Class: soundness (trust). No compiler check backs it (`SAFE-HASKELL-CLAIM-1`), and Safe Haskell would not help, because a `Trustworthy` module may use `unsafePerformIO`. Bite: matters at package-set growth; `FFI-DETERM-GATE-1` covers it.
2. **Tier 2 comes back without its disclosure.** Class: soundness. Bite: blocks any lift of the refusal; `FFI-TIER2-1` lists disclosure as a required part.
3. **New `verified` records at `CALL-CONGRUENCE-1`.** Class: verification ergonomics. Bite: complicates that release (sidecars); no soundness effect.
4. **Removing a documented surface.** Class: scope. No tracked program uses `c.*`, and no `c.*` program builds, so no working program breaks. Bite: none measured.

## Hand-off

**Engineer, first release.** `FFI-TIER2-REFUSE-1`: a `c.` case in `ffiImportErrors` returns `ffi-tier2-refused`; the M-BUILD witness and W8 are refused at `check`; Spec.hs AT-3 is updated (Part 1). `REGEX-ASYNC-1`: `llmll_rxTotal` rethrows `SomeAsyncException` (Part 2). No JSON-AST change and no report-version change.

**Engineer, second release.** `CALL-CONGRUENCE-1` under R1–R5: Ackermann over every contract-environment callee and function-typed parameter, keyed on the alpha-renamed binder, at sorts that meet R2 (today `int`, `bool`, `string`; `float` excluded); the D9 text in `ffiNote` and the schema description; fixtures A1, A2, W5, `gs`, A4, the R3 shadowing fixture and W-WRAP.

**Documentation-lead.** `FFI-DOC-DRIFT-1` (D1, D3); the §7 Tier 2 text with the first release; the D9 row meaning in §7 with `CALL-CONGRUENCE-1`; amendment notes in `ffi-tier1-proposal.md` for D5 and D9; the INDEX label when rows ship.

## Appendix — Professor review log

Folded 2026-10-31 at settlement of Rev 1. The review is copied unchanged below, without its frontmatter (reviews: Rev 0; verdict: ACCEPT WITH CHANGES, C1–C7). The standalone file was never committed, so it has no archive copy and no redirect stub. Its witness W8 is reproduced in "Measurements".

### Review of Rev 0 (2026-10-31)

#### Restatement

The language-team proposes Option B. Every contract-environment callee and every function-typed parameter gets the Ackermann functional-consistency hypothesis `(a_i = a_j) ⇒ (r_i = r_j)`, with no FFI test in the emitter. The justification is that the D9 trust row already assumes each Tier 1 export has "no hidden effects at the declared type", and that this assumption entails congruence. The proposal closes the `c.*` gap with a new disclosure row, `FFI-TIER2-DISCLOSE-1`. It offers a temporary fallback that skips function-parameter pairs. It also restricts result sorts to `int`/`bool`/`string`, and it claims that native callees are deterministic except for `llmll_rxTotal`.

#### Context located

1. `docs/compiler-team-roadmap.md:100` — the row, "over non-FFI callees", "Decide first".
2. `docs/design/ffi-tier1-proposal.md:233-238` — D9 row meaning: "total and has no hidden effects".
3. `docs/design/ffi-tier1-proposal.md:353` — "no hidden effects (`unsafePerformIO`)"; builtins share this status.
4. `docs/design/byte-io-proposal.md:990-992` — P18, the Ackermann form and its sort guard.
5. `docs/design/fn-param-uf-1-proposal.md:121-136` — congruence "true … for calls that return".
6. `LLMLL.md:22`, `CodegenHs.hs:233`, `:450` — EVAL-STRICT-1: codegen is call-by-value with bang patterns.
7. `LLMLL.md:148` — `int` is `Integer` at run time and mathematical `Int` in Z3.
8. `LLMLL.md:1412` — `string` → `hs-text` replaces lone surrogates (not injective).
9. `compiler/src/LLMLL/FixpointEmit.hs:3296` — `TString ↦ FQStr`, an opaque carrier sort.
10. `compiler/src/LLMLL/FixpointEmit.hs:1185`, `:4245-4255` — `fnParamCallees` is unioned in without the `localBinderNames` filter.
11. `compiler/src/LLMLL/CodegenHs.hs:716-728` — `llmll_rxTotal` catches `SomeException` inside `unsafePerformIO`.
12. `compiler/src/LLMLL/CodegenHs.hs:1393`, `:1438` — `timeout` wraps only `waitForProcess`, so it does not reach pure code.
13. `LLMLL.md:547` — `def-logic` is removed. The proposal still lists it as a native callee (minor drift).
14. New measurement W8 (compiler 0.33.4; the program imports `(import c.stdlib (interface [[rand-of (fn [x: int] -> int)]]))`). A `def-shell g` calls the `c.stdlib` entry `rand-of`, and `twice-g` = `(- (g x) (g x))`. `check` passes. `verify --trust-report` gives `twice-g` the result `body_fallback: abstraction-unsafe; abstraction:app:g` and **no assumption row**.

#### Gaps and hazards

##### H1. The temporary fallback for Tier 2 is unsound. Class: soundness. Bite: blocks the proposed ordering.

The proposal says that if `FFI-TIER2-DISCLOSE-1` cannot ship first, the pass should skip function-parameter pairs, "because W-C has no other guard". That is false. W8 is the `c.*` analogue of W-WRAP. The callee `g` is an ordinary `def-shell`, so the fallback does not exclude it. With congruence, `twice-g` becomes `verified`, and the report carries no row. The run returns a nonzero value. So the fallback closes the value path only, and the wrapper path stays open. A sound fallback would need the transitive reach walk (`markFfiAssumptions`, `TrustReport.hs:1439-1462`) extended to `c.*`, plus the parameter exclusion. That walk is most of the work of the disclosure row itself. **Drop the fallback.** Make the Tier 2 disclosure a hard precondition, in the same release or earlier.

##### H2. "No hidden effects" implies congruence only under a broad reading of "effects". The rewording is therefore a change of meaning. Class: soundness (trust semantics). Bite: complicates; the fix is in the proposal already, but its status is wrong.

Effect systems separate read effects from write effects (Lucassen and Gifford, POPL 1988). A narrow reading of "no hidden effects" is "no observable writes". Under that reading, a function can still read a clock, an entropy source, or an address (`StableName`, pointer equality) and stay "effect-free". Congruence needs **within-one-run functional determinism of the boundary-converted values**. That is a no-hidden-inputs condition. The parenthetical "(`unsafePerformIO`)" at `ffi-tier1-proposal.md:353` supports the broad reading, but the row text at `:238` does not state it.

So condition (i) is not a "sharpening". It is the step that makes B's argument step 3 true. Record it as a strengthening of the disclosed assumption. It is also the first time that a verifier rule depends on the row. Today a direct FFI call and a wrapper both fall back, so no proof uses D9 determinism (W-DIR and W-WRAP measured). No `trust_report_version` change is needed: a stronger stated assumption does not invalidate earlier verdicts, because those verdicts depended on less.

The equivalence question has a second half. Congruence is **strictly weaker** than D9 in one direction, because it does not need totality (see H5). In the other direction, congruence needs nothing more than determinism. One qualification applies: determinism is needed only within one run. A per-process hash salt (as in `hashable`) is constant within a run, so it is harmless here. The D9 text should say "within one run" so that later reviewers do not refuse such libraries without cause.

##### H3. `llmll_rxTotal` is inside the partial-correctness guarantee, not outside it. Class: soundness (runtime). Bite: small; the fix is cheap, so make it a condition.

The proposal says that a heap-exhaustion disagreement is "outside LLMLL's partial-correctness guarantee". The reasoning is wrong. Partial correctness speaks about runs that terminate normally. Without the `catch`, `HeapOverflow`, `StackOverflow` or `UserInterrupt` ends the run, and the guarantee holds vacuously. With the `catch` at `CodegenHs.hs:726-728`, the run **continues and terminates normally with the fallback value**. That run is inside the guarantee, and two equal calls disagree in it.

Asynchronous exceptions are not part of the denotation of pure code (Marlow, Peyton Jones, Moran and Reppy, *Asynchronous Exceptions in Haskell*, PLDI 2001). Catching them under `unsafePerformIO` converts them into observable value nondeterminism. GHC also memoises the fallback in the thunk, so the effect can persist. `UserInterrupt` (Ctrl-C) is not resource exhaustion, so the "stated limit" framing does not cover it.

The disagreement is also specific to congruence today. Regex results are opaque to the verifier, so no other proof uses a regex value. The standard fix is a three-line change: rethrow when `fromException e :: Maybe SomeAsyncException` is `Just`. `AsyncException` sits under `SomeAsyncException` since base 4.7. Make this a condition of the row, not an unfiled note. A synchronous pattern error stays deterministic and keeps its fallback.

##### H4. The sort side condition is necessary, but its stated reason is too narrow. The correct criterion is Leibniz equality plus an injective abstraction. Class: soundness. Bite: latent today, and it decides future sort extensions.

Ackermann's reduction is sound only when the antecedent equality is a congruence for every callee. In practice this means Leibniz (substitutive) equality at run time. It also needs the run-time-to-model abstraction α to be **injective on argument sorts**. Each actual run must induce a model of all the hypotheses, and a non-injective α breaks that: two different run-time arguments could map to one model value while the results differ. The result sort needs only that model `=` agrees with LLMLL `=` at run time.

- **`float`.** IEEE `==` fails both conditions. NaN ≠ NaN breaks reflexivity on results, and +0.0 == −0.0 breaks substitutivity on arguments (`1/x`, `atan2`). So exclude `float` on both sides; the row already excludes float arguments. The deeper defect is any translation of LLMLL `=` on `float` to SMT `=`. Witness `f1.llmll` `h` (`(= y y)` on NaN) would be refuted today even without congruence. It is latent only because float binders fall back (`f2`). File the general rule against any future float reflection: map `=` to `fp.eq` and never use it as a congruence.
- **`int`.** The run-time `Integer` and Z3 `Int` are both unbounded (`LLMLL.md:148`), so α is the identity. `hs-int` (bounded `Int`) overflow happens inside the callee, and it does not affect determinism. The boundary converter `Integer → Int` is a function; if it wraps, more arguments share a result, which is harmless. Sufficient.
- **`bool`.** Trivially sufficient.
- **`string`.** The run-time `string` has structural `Eq`. The model sort is `FQStr`, an opaque carrier (`FixpointEmit.hs:3296`), so an injective α exists. Sufficient today. The lone-surrogate collapse of `pack` (`LLMLL.md:1412`) makes the *callee's* input conversion non-injective. That is harmless, because a non-injective function of the argument preserves congruence. **Record one forward condition.** If `Str` ever moves onto SMT-LIB native strings, the character range is 0..0x2FFFF (SMT-LIB 2.6 Unicode Strings theory), while Haskell `Char` reaches 0x10FFFF and admits lone surrogates. α is then not injective with a faithful character semantics, so string-argument congruence has to be re-justified.

The criterion "Leibniz `Eq` + injective α on arguments; model `=` matches LLMLL `=` on results" is what the row should state, with `int`/`bool`/`string` as its current instances. A bare list will drift when pairs or ADTs gain exact sorts.

##### H5. Partiality, laziness and exceptions: sound as proposed, and the reason is the Ackermann encoding. Class: soundness (confirmation with one side condition). Bite: none if the side condition holds.

Under call-by-value with strict codegen (EVAL-STRICT-1, `CodegenHs.hs:233`, `:450`), a result binder exists in a constraint environment only on paths where the call returned a value. A diverging or failing call ends the run, and every later VC holds vacuously. The Ackermann hypothesis relates **existing binders only**. It introduces no function symbol and no term for an unreached call. So it avoids two classic failures:

1. The lazy-binder unsoundness of Liquid Haskell. A refinement of an unevaluated, diverging binder enters the environment and proves `false` (Vazou, Seidel, Jhala, Vytiniotis and Peyton Jones, *Refinement Types for Haskell*, ICFP 2014, §3).
2. The totality obligation that an uninterpreted-function or axiom encoding brings. A `∀x. pre(x) ⇒ post(x, f x)` axiom over a partial `f` can be inconsistent. This is why Liquid Haskell reflection requires termination (Vazou et al., *Refinement Reflection*, POPL 2018). It is also why F* admits only `Tot`/`GTot` functions in specifications, and why Dafny checks termination of every `function`.

So the proposal's step 4 is correct. Totality is not needed. Imprecise exceptions (Peyton Jones, Reid, Hoare, Marlow and Henderson, PLDI 1999) are harmless here, because the only pure-code `catch` is `llmll_rxTotal` (H3), and its fallback does not depend on which exception was raised. **Side condition for `FFI-UNINTERP-1`:** when that row admits an FFI entry, it must keep the binder-only Ackermann form. Otherwise it inherits the totality obligation that this proposal correctly says congruence does not need.

##### H6. Callee identity is keyed by name, and `fnParamCallees` escapes the FN-SHADOW-1 filter. Class: soundness (implementation hazard). Bite: complicates; it needs one fixture.

`FixpointEmit.hs:1185` builds `Map.union (fnParamCallees aliases params) (scopedContractEnv …)`. `scopedContractEnv` removes names that a local binder shadows (FN-SHADOW-1). `fnParamCallees` is not filtered. Suppose a body rebinds a parameter name to another function value, for example `(let [[f h]] …)`, or a `match` arm binds `f`. If the Ackermann pass pairs calls by surface name, it then equates `f x` with `h x`. That is a false `verified`. The emitter alpha-renames `let` variables (`LLMLL.md:1158`), but this review did not measure whether it renames a callee position. The row must key pairs on binder identity after alpha-renaming, and it must add a shadowed-parameter fixture that has to stay `refuted` or fall back.

##### H7. "Native callees are deterministic" holds. Class: confirmation. Bite: none.

Every `wasi.*` builtin is `Command`-typed. `do` lowers to `let`. `llmll_strIx` has a cache whose answer does not depend on the cache, and lost writes under `EAwait` concurrency are answer-independent too. The response slot lives in `IO`. `timeout` wraps only `waitForProcess` (`CodegenHs.hs:1393`, `:1438`), so it cannot interrupt pure code in the program; it can still do so in an external harness. The one exception is H3, and its framing must change. Remove `def-logic` from the list, because it is a removed construct (`LLMLL.md:547`). `SDefLogic` survives in `buildContractEnvWith`, which is dead code for the removed construct.

##### H8. The D4 effect refusal for `c.*` is not a precondition of congruence. Class: scope. Bite: complicates sequencing without need.

Congruence applies only to result sorts `int`/`bool`/`string`. A `c.*` entry declared at a `Command` result never gets a hypothesis. So only the **disclosure** half of `FFI-TIER2-DISCLOSE-1` must ship before congruence. Split the D4 refusal for `c.*` into its own row, so the precondition stays small.

##### H9. The `c.*` default is a much stronger assumption than the Tier 1 default. Class: scope (trust calibration). Bite: only matters at scale.

Tier 1 determinism rests on a vetted nine-module set and a `:browse` sweep. Tier 2 determinism rests on arbitrary developer-written Haskell over arbitrary C, where effects are the norm. The literature splits on this point:

- Why3 separates `val function` (pure, functional, usable in logic) from plain `val` (a program function that may be nondeterministic). Plain `val` gets **no** functionality.
- SPARK assumes that every function is deterministic unless it carries `Volatile_Function`.
- The Haskell 2010 FFI report (§8.4) says that a foreign import at a non-`IO` type *asserts* purity, and that behaviour is undefined if the import is impure.
- CompCert axiomatises determinism of external calls as an explicit hypothesis (`ec_determ` in `common/Events.v`).

Default trust plus disclosure, as in SPARK, Dafny and the Haskell FFI report, is defensible and consistent with LLMLL's trust-report design. The disclosure text for `c.*` must be blunt. It must name the stub file and say "deterministic within one run".

#### Literature precedent (item 5)

- **Ackermann reduction.** Ackermann 1954. Bryant, German and Velev, ACM TOCL 2(1), 2001. Kroening and Strichman, *Decision Procedures*, 2nd ed., §4.2. Functional-consistency constraints over existing terms are complete for EUF and need no function symbol. This is the encoding already chosen in P18.
- **Liquid Haskell.** Liquid Haskell treats every Haskell binding as a pure function, including `unsafePerformIO` code and non-`IO` foreign imports. It does no purity check, and `assume` specifications are trusted. It confronted divergence under laziness (ICFP 2014) and required totality for reflection (POPL 2018). LLMLL's strict codegen plus a binder-only encoding avoids both requirements. The LLMLL trust row gives *more* disclosure than Liquid Haskell does.
- **Dafny.** A `function` is a mathematical function in the logic, so functionality is built in. A `{:extern}` function is trusted to be deterministic and to agree with its specification. Nondeterministic externals must be `method`s. Dafny 4 requires `{:axiom}` on bodyless functions and lemmas, and `dafny audit` lists externs and axioms as assumptions. This is the closest precedent to `ffi_assumptions`, and it supports B with disclosure.
- **F\*.** `Tot`/`GTot` functions are pure and usable in specifications. An `assume val` at a `Tot` type is a trusted purity claim. `ML`/`Dv` code cannot appear in specifications, which is F*'s way of refusing congruence to effectful or partial code.
- **Why3 and SPARK.** See H9. Why3 is the opt-in precedent, and SPARK is the default-trust precedent. LLMLL Tier 1 has D4 + D5 + D7, so it is already in Why3's `val function` position. This confirms that rejecting Option C is correct for Tier 1.
- **CompCert.** `ec_determ`: determinism of external calls is a named axiom of the semantics. This is the model for writing "deterministic" into D9.

The language-team and this review reach the same Tier 1 conclusion by different routes: the team by a `:browse` sweep, this review by the precedents above. That agreement is a signal.

#### Recommendation

**Accept with changes.** Option B is correct for Tier 1. Its central argument holds once D9 states determinism, and the Ackermann encoding needs no totality. Make these changes before settlement:

- **C1 (H1).** Delete the "skip function-parameter pairs" fallback. Make the disclosure half of `FFI-TIER2-DISCLOSE-1` a hard precondition of `CALL-CONGRUENCE-1`, in the same release or earlier. Add W8 (the `c.*` wrapper) beside W-C as a required fixture: after the change, `twice-g` is `verified` and carries a `c.stdlib` row. **Simpler alternative:** first measure whether a Tier 2 program builds end to end. If it does not, refuse `c.*` imports at `check` until Tier 2 works. That is the smallest sound move, and it removes a surface that cannot run.
- **C2 (H2).** Reword the D9 row as "deterministic within one run at the declared type (equal arguments give equal results), total, and with no hidden effects". Record the change as a strengthening of the disclosed assumption. State that `CALL-CONGRUENCE-1` is the first verifier rule that uses this row.
- **C3 (H3).** Make `llmll_rxTotal` rethrow `SomeAsyncException` a condition of the row. Remove the claim that the case is "outside partial correctness".
- **C4 (H4).** Replace the sort list with the criterion: Leibniz `Eq` and an injective abstraction for argument sorts; model `=` matching LLMLL `=` for result sorts. Name `int`/`bool`/`string` as its current instances. Add the forward condition about native SMT strings. File the `fp.eq` rule for any future float reflection.
- **C5 (H6).** Key pairs on alpha-renamed binder identity. Add a shadowed-function-parameter fixture that must not become `verified`.
- **C6 (H5).** Add one sentence to `FFI-UNINTERP-1`: admission keeps the binder-only Ackermann form, or it takes on a totality obligation.
- **C7 (H7, H8).** Remove `def-logic` from the native list. Split the `c.*` D4 refusal out of the precondition row.

Keep: removing "non-FFI callees" from row 100, the D5 growth gate with the `Data.Vector.unsafe*` denylist, the rejection of Option C for Tier 1, and the reach-table fix D1.

#### Open questions for the language-team

1. Measure whether a `c.*` program builds and runs end to end today (`Lib.hs` has no `import FFI`). The answer chooses between C1's disclosure row and the smaller refusal.
