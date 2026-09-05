---
name: resp-fact-implementation-plan
title: "RESP-FACT-1: implementation plan for Rev 6"
status: "PLAN, revision 2, awaiting approval. Written against resp-fact-proposal.md Rev 6 (working tree) after professor round 5 accepted the direction. Revision 1 targeted Rev 5, found cells W and D, and proposed an entry-module rule that round 5 refuted with cell E. This revision carries the delivery rule with its (t5) row, the two-part export condition, the three-case premise disclosure, and the corrected boundary argument. No code has been written."
date: 2026-09-04
author: compiler-engineer
consumers: [user, professor, language-team, documentation-lead]
---

# RESP-FACT-1: implementation plan for Rev 6

## Restatement

Implement `docs/design/resp-fact-proposal.md` Rev 6. The compiler declares a fact per `(builtin, arm)`. A syntactic pass binds each control tag to one builtin over the entry module's pair-returning defs. A step whose `pre` proves `(= p T)` receives the bound builtin's fact on its `Response` match-arm binder, but only when its tag and `Response` parameters are delivered from `:step` by the §5.3 grammar. The module must satisfy the entry-module rule and the export condition of §5.2. The trust report names the assumed fact per function and says what discharged its premise. Revision 1 of this plan is superseded; its two findings are folded into Rev 6, and its entry-module argument is corrected below.

## Context located

1. `docs/design/resp-fact-proposal.md` Rev 6: §1.5-1.7 (cells R-4, R-5, R-6), §2.1 rows c34-c43, §5.1 (fact request, defined), §5.2 (entry-module rule, export condition, state shape), §5.3 (delivery rule, grammar t1-t5), §5.4 (harness lemma), §8 items 14-23, §9, §10, §11 item 1, §12, §14, §16 items 7-11.
2. `docs/archive/professor-reviews/resp-fact-proposal-review.md` `## Round 5`: accepts the direction; refuses implementation until Rev 6 carries the three changes; adds cell E and row (t5).
3. `docs/compiler-team-roadmap.md` rows `RESP-FACT-1` (:87), `FS-STAT-1` (:60), `TRUST-AXIOM` (:102), `CMD-A` (:98).
4. **Correction to revision 1.** Revision 1 argued that no module can import the entry module without a cycle. Cell E (`amain.llmll` with `def-main`, imported and opened by `bmain.llmll`) checks, verifies SAFE and builds. The argument was wrong. The export condition of Rev 6 §5.2 replaces it, and `(export)` with no names parses (`Parser.hs:420-427`).
5. `compiler/src/LLMLL/HoleAnalysis.hs:52-53` (imports `Syntax` and `Diagnostic` only) and `:606-616` (`buildCallGraph`). `TypeCheck.hs:80`, `FixpointEmit.hs:129` and `TrustReport.hs:64` already import it. So a new module that imports `Syntax`, `TypeAdmissibility` and `HoleAnalysis` closes no cycle when the three consumers import it.
6. `compiler/src/LLMLL/FixpointEmit.hs:1015-1031`: `adtRefs` seeds `refEnv` per `<param>$<Ctor>`; `bindArm` (:3862-3868) declares the arm binder at that refinement. The receiving seam; unchanged from revision 1.
7. `compiler/src/LLMLL/FixpointEmit.hs:2508-2513` (`sigPairUnsafe`). Every pair-returning def falls back (cell c34), so the premise needs its own emission and the issuing def's own `pre` is discharged by no caller in the fragment.
8. `compiler/src/LLMLL/FixpointEmit.hs:1309-1360`: the call-pre emission shape the premise reuses. `:2648`: the `EApp` row of `desugarCtorValues` that leaves `EApp "Ran" []` intact (cell c23).
9. `compiler/src/LLMLL/TypeCheck.hs:1352` (`checkStatements`), `:567` (`tcError`), `:1895` (`checkStepArity`: state, input, `Response`), `:1805-1817` (`SDefMain`), `:2209-2214` (checker η-rule). `Syntax.hs:715-718` (`defMainStep` is an `EVar` or an `ELambda`), `:741` (`SExport [Name]`).
10. `compiler/app/Main.hs:1205-1209` and `:1304`. `verify` exits on a strict-check error; emitter diagnostics print as warnings and fail nothing. Every hard error of this design is raised in the checker.
11. `compiler/src/LLMLL/Module.hs:274-283`: constructors export as values under the `(export …)` filter. `TypeCheck.hs:1748-1752`: `open` injects exported names bare.
12. `compiler/src/LLMLL/TrustReport.hs:74-120` (`TrustEntry`), `:300-303` (additive keys do not change the emit version), `:304-325` (`harnessAssumptions`). `VerifiedCache.hs:290-291`, `:325-326` (`checkerSoundnessVersion`).
13. `compiler/src/LLMLL/CodegenHs.hs:526-530` (`RCode (fromIntegral code)`), `:479-482` (`RCode Integer`), `:1839-1844` (the harness loop), `:1592-1600` (`emitDo` discards commands).
14. `tools/doc-claims/docclaims.llmll:260-268`, `:272-273`, `:506-516`, `:550-555`; it has no `(export …)` list today.
15. `compiler/test/Spec.hs:7430-7478` (solver-gated pattern), `:9905-9945` (COMP-4 (b) `refEnv` tests). `.github/workflows/version-gate.yml:295-311` installs `fixpoint` and z3.
16. Measured baseline, this session: `stack test` reports `1774 examples, 0 failures` in 15.8 s; `scripts/tests/` holds 189 `def test_` functions.

## Plan summary

Add one pure module, `compiler/src/LLMLL/RespFact.hs`, holding the fact table and four analyses over the entry module's statements: fact requests, the issuing pass `Sites`, the delivery pass with grammar (t1) to (t5), and the export condition. One entry point, `analyzeRespFacts`, returns either a list of errors or a plan (per-def `refEnv` entries, premise sites, disclosure rows). The checker calls it once per module and turns every error into `tcError`, so `check`, `verify` and `build` fail loudly and nothing is withheld quietly. The emitter calls it for the `refEnv` union at `FixpointEmit.hs:1031` and emits one `call-pre:<builtin>` constraint per premise site whose argument is a parameter. The trust report calls it for one `assumed_facts` row per requesting def, carrying the premise case. Two emitter fixes land with it: `desugarCtorValues` lowers `EApp C []`, and a closed call-pre RHS is folded when true and kept when false. `checkerSoundnessVersion` moves to `"2"`. No codegen, JSON-AST or builtin change. Cost: about 550 lines in the new module, a five-site parameter thread into `emitFnConstraints`, about fifty tests, and one full re-verify of every tree from the version change.

## Affected surface

Ordered from entry to output.

- `compiler/src/LLMLL/RespFact.hs` (new, about 550 lines). Imports `Syntax`, `TypeAdmissibility`, `HoleAnalysis`. Exports `analyzeRespFacts :: AliasMap -> [Statement] -> Either [Text] RespFactPlan`, the table, and the four analyses for unit tests.
  - **Table.** `Map (Name, Name) RespFact`; one entry, `(("wasi.http.response","RCode"), RespFact (FactProgram 0) ("v", EOp ">=" [EVar "v", ELit (LitInt 100)]))`. `FactCodegen` is not declared: no shipped builtin is in that category, and `FS-STAT-1` adds it with its clamp as the firing witness.
  - **Requests** (§5.1). A def with a `pre` conjunct `(= p T)` or `(= T p)`, `p` typed by an `STypeDef` sum of this module, `T` its constructor, and a parameter resolving to `Response`. Conjuncts are split over nested `EApp "and"`. `T` is admitted as `EVar T` or `EApp T []`.
  - **Entry-module rule** (§5.2). The tag type must be an `STypeDef` of `stmts`; the program must hold a console `SDefMain`; a pair-returning callee not defined in `stmts` is `⊥`. Each failure names the type or the def.
  - **Tag type shape.** `nullaryEnumArity am ty` must be `Just n` (`TypeAdmissibility.hs:461-472`); otherwise an error naming the type and the requesting def (§8 item 5).
  - **`Sites`** (§5.2). Rows as specified: pair row over `EPair (EPair _ T) C`; `EIf`; `EMatch`; `ELet` with copy propagation of a command-valued binding; substitution row for calls to entry-module pair-returning defs; `PARAM` when a component resolves to the def's own parameter; `⊥` otherwise, including `EDo`, `EPair s c` with `s` a variable, and a cycle in the pair-returning call graph. `seq-commands` takes the head of the right operand. `:init` is walked as an expression. Memo keyed on (def, substituted argument list). Each element carries (tag, builtin, argument expressions, origin def, origin statement index). Rule 1 failure on a requested tag yields the warning `W-RESP-FACT-UNBOUND` naming the tag and both builtins; the fact is withheld. `⊥` yields an error naming the def and the form.
  - **Delivery** (§5.3). Greatest fixpoint over every call site in `stmts`, including the `:step` body, `ELambda` bodies and `:init`. Sources: the `:step` def's parameters 0 and 2, or the `:step` lambda's. The walk carries a scope of live bindings; a `let` pattern variable or a lambda parameter that rebinds a name removes it. Rows (t1) to (t5) exactly as §5.3 states; (t5) is implemented by pushing the arm's constructor onto a delivered-tag context while walking that arm's body, when the scrutinee is (t1) to (t4). A requesting def whose tag parameter or any `Response` parameter leaves the fixpoint gets an error naming the def, the parameter and the first refusing call site.
  - **Export condition** (§5.2). Find `SExport ns` (`Syntax.hs:741`). No list with a request present: error naming the first requesting def and stating `(export)`. For each `n ∈ ns`: a constructor of the tag type is an error; a def in the reverse closure of the requesting defs over `buildCallGraph stmts` (`HoleAnalysis.hs:606-616`) is an error naming `n` and the requesting def it reaches.
  - **Premise sites.** For each `Sites` element whose tag is requested and whose builtin has `FactProgram i`: argument `i` after let-copy-propagation must be an int literal (folded at check: pass, or error naming the site and the literal) or a scalar parameter of the origin def (emitted by the emitter); anything else is an error naming the site.
- `compiler/src/LLMLL/TypeCheck.hs:1352-1400` (`checkStatements`). One call after the per-statement pass, with the module's own aliases unioned with `builtinAliases`: `either (mapM_ tcError) (const (pure ())) (analyzeRespFacts am stmts)`. Inert when no request exists.
- `compiler/src/LLMLL/FixpointEmit.hs:2648`. `EApp f [] | f ∈ tags, f ∉ bound -> tagLit f`.
- `compiler/src/LLMLL/FixpointEmit.hs:1340-1360`. Fold a closed RHS: skip the constraint when it reduces to true; emit `FQFalse` when it reduces to false. Closed means every leaf is a literal after `desugarCtorValues`.
- `compiler/src/LLMLL/FixpointEmit.hs:426-475`, `:531-570`, `:650-676`. Compute the plan once; thread `Map Name RefEnv` into `emitFnConstraints` (new parameter, five call sites); after the statement loop emit premise constraints with binders from `buildSortEnv aliases params` of the origin def, `lhs` = the origin def's desugared `pre` (or `FQTrue`), `rhs` = the fact with `v := param`, tag `[origin, "call-pre:" <> builtin]`, origin pointer `/statements/<idx>/body`, recorded through `addCallPre`.
- `compiler/src/LLMLL/FixpointEmit.hs:1031`. `refEnv = Map.union respRefs (Map.fromList (resultRefs ++ adtRefs))`.
- `compiler/src/LLMLL/FixpointEmit.hs`, the `reifyBytesZeroLen` and `(bytes-zero)` comments. Replace the stale `TypeCheck.hs:1216 / :1250` citation by NAMING the LEVER-A0 determining-context arms rather than citing lines, which drift (§16 item 6). The same citation is repeated in `Contracts.hs`'s `reifyBytesLen` twin.
- `compiler/src/LLMLL/TrustReport.hs:74-120`, `:343`, `:1529-1532`. `teAssumedFacts :: [AssumedFact]` with tag, builtin, arm, rendered predicate, category, and `premise` ∈ {`folded-literal`, `call-pre:<origin def>`}. The second form names the def whose `pre` the premise rests on, and the reader follows that def's existing effective-pre line (`teEffectivePreLevel`) to see whether it was proved or asserted. Text render one line per row; JSON key `assumed_facts`, additive, no emit-version change (precedent `:300-303`).
- `compiler/src/LLMLL/VerifiedCache.hs:326`. `checkerSoundnessVersion` from `"1"` to `"2"`.
- `compiler/test/fixtures/resp-fact/` (new, twenty fixtures; test plan).
- `compiler/test/Spec.hs`. One new `describe "RESP-FACT-1"` block.
- `docs/llmll-ast.schema.json`. No change.
- `LLMLL.md` §13, §9.7, §5.3.3, §5.3.5; `docs/compiler-team-roadmap.md` row `RESP-FACT-1`; `docs/design/INDEX.md:94` (still says Rev 2). Doc-lead, after ship.

## Verification impact

- **New obligations.** One `call-pre:wasi.http.response` constraint per premise site whose argument is a scalar parameter, only for a requested tag. Zero on the measured consumer. Zero on the positive witness, whose argument `200` folds.
- **Refined binders.** The `$RCode` binder of each delivered `Response` parameter of a requesting def declares `v >= 100` instead of `FQTrue`.
- **Fragment.** QF-LIA throughout (`LLMLL.md` §5.3.3, §5.3.5). The delivery pass, the export condition and the entry-module rule are checker-side syntactic rules with no SMT obligation.
- **Body-faithful set.** Unchanged. A `refEnv` entry never routes a def to fallback.
- **Solver time.** Under a millisecond per premise constraint and per refined binder; cell w_full runs end to end in about 0.2 s today.
- **Trust model.** Tiers do not move. `--strict-verified-core` does not read `assumed_facts` in this slice. On the measured consumer the dispatcher and every issuing def fall back (`sigPairUnsafe`), so a step's `(= p T)` is an asserted caller obligation and a parameter premise rests on an asserted `pre`. The `premise` field makes that visible per fact.
- **Harness.** `trHarnessAssumptions` already discloses the delivery assumption the §5.4 lemma rests on. No new harness claim.

## Performance budget

- **GHC build.** `FixpointEmit.hs` (4647 lines), `TypeCheck.hs` (3147), `TrustReport.hs`, `VerifiedCache.hs` and the new module recompile; their importers relink. No new package.
- **Test suite.** Baseline 1774 examples in 15.8 s. About fifty examples added, about ten solver-gated at roughly 0.2 s each. Expected about 23 s.
- **Compiler runtime.** One linear request scan per module. When a request exists: `Sites` is memoized on (def, arguments) with the acyclicity condition; the delivery fixpoint is at most `#params` iterations over `#call sites`; the export condition is one reverse-closure over the call graph. On the consumer: 13 pair-returning defs, about 30 call edges, under a millisecond.
- **`.fq` size.** One constraint per emitted premise, one refinement string per refined binder.
- **Caches.** The `checker_soundness_version` change discards every existing sidecar once (`VerifiedCache.hs:290-300`).

## Contract plan

No LLMLL function lands in the provable fragment from this change; the deliverable is Haskell. The fixtures carry contracts, fixed here before their bodies exist.

- **`ran-step` in `witness.llmll`.** `(pre (= p Ran))`, `(post (>= result 100))`, body `(match x ((RCode n) n) (_ 100))`. Refuting body `(match x ((RCode n) (- n 1)) (_ 100))`. Refuting fixture `r3-fan.llmll`, where `Ran` also pairs with `wasi.proc.args`.
- **`ran-issue` in `premise-param.llmll`.** `(pre (>= code 100))` on `[r: int code: int]`, body `(go r Ran (wasi.http.response code ""))`. Refuting variant deletes the `pre` and is refuted on `call-pre:wasi.http.response`.
- **Module placement.** One entry module per fixture, with `(export)`, by the entry-module rule and the export condition. `go` is a `def-shell`, so no sibling-admissibility check fires.
- **What stays unproved.** The pass-through rides `codegen_semantics_version` (trust). The harness delivery rides `harness_assumptions` (trust). The dispatcher's discharge of `(= p T)` over a `Json` state is an asserted caller obligation (`TRUST-PRE`). The dispatcher shapes that would discharge it in the fragment crash the solver today (cells c39, c40) and are routed.

## Test plan

Fixtures under `compiler/test/fixtures/resp-fact/`, each with an `@expect` header and a Spec test that reads it:

1. `witness.llmll`, `witness-refuted.llmll`. §8 item 1 with `(export)`, a `:step` that passes the literal tag inside each arm (row t5). Expect SAFE and body-faithful `ran-step` with `v >= 100` on `x$RCode`; the refuted variant refuted.
2. `r3-fan.llmll`. §1.4. Expect warning `W-RESP-FACT-UNBOUND` and `listing-step` refuted.
3. `w-provenance.llmll`. Cell W. Expect a `check` error naming `outer`, `(h t x)` and `p`.
4. `w-ctor.llmll`. Cell c42 shape. Expect a `check` error naming the constructor argument.
5. `bottom.llmll`, `stay-put.llmll`, `do-body.llmll`. §8 items 10, 17, 18. Expect a `check` error naming the def; the last two must state the rewrite.
6. `payload-ctl.llmll`. §8 item 5. Expect an error naming `Ctl` and the requesting def.
7. `compiler/test/fixtures/resp-fact/open-lib/lib.llmll`, `compiler/test/fixtures/resp-fact/open-lib/main.llmll`. Cell D. Expect the entry-module error naming `Ctl`.
8. `compiler/test/fixtures/resp-fact/wrap-machine/amain.llmll`, `compiler/test/fixtures/resp-fact/wrap-machine/bmain.llmll`. Cell E with `(export)` in `amain`. Expect `bmain` to fail `check` on the unbound name `a-step`.
9. `export-missing.llmll`, `export-reaching.llmll`, `export-ctor.llmll`, `export-ok.llmll`. §8 item 20 and its neighbours: no list; a list naming the dispatcher that reaches the requesting step; a list naming `Ran`; a list naming a helper that reaches nothing. Expect three errors naming the offending name and the reached step, and one pass.
10. `arm-literal.llmll`. §8 item 16. Expect `check` clean, no call-pre constraint in the `.fq` for the folded `(1 = 1)`, and SAFE.
11. `closed-false.llmll`. §8 item 21: `(h Boot x)` inside the `((Boot) …)` arm. Expect the delivery rule to admit it and the solver to refute the `(0 = 1)` call-pre.
12. `wrapper-depth.llmll`, `let-cmd.llmll`, `seq-cmd.llmll`, `init-pair.llmll`. `Sites` rows. Expect the stated bindings.
13. `premise-param.llmll`, `premise-param-refuted.llmll`, `premise-literal-bad.llmll`. Expect SAFE; refuted on `call-pre:wasi.http.response`; a `check` error naming the literal.
14. `docclaims-nullary.llmll`. A copy of the consumer with `Ctl` nullary, the exit code moved into `Rc`, `(export)` added, and the dispatcher passing the literal tag per arm. Expect the eight bindings §10 lists and `check` clean. The live tool is not edited in this row.

Unit tests in `Spec.hs`: the `EApp C []` row (cells b20 and b23 emit byte-identical `.fq`); closed-true folded and closed-false kept (two); `factRequests` on a bare, a parenthesized and an `and`-conjunct clause (three); every `Sites` row (seven), `PARAM` at depth one and two, cycle is `⊥`, memo key includes the arguments; delivery rows (t1) to (t5) admitted (five), and a literal, a shadowed name, a lambda-rebound name, a constructed value and a let-bound literal refused (five); the export condition's three refusals and one pass; `refEnv` carries the entry only for a delivered parameter; the table equals one entry and `wasiRuntimePreamble` contains `llmll_publish (RCode (fromIntegral code))` (§8 item 12); `assumed_facts` present on the witness with `premise = folded-literal`, present on `premise-param` with `premise = call-pre:ran-issue`, absent on a corpus file; `checker_soundness_version` is `"2"`.

Counts: about fifty examples. Target: 1774 measured on the merge base, to at least 1824 after. Python: 189 `def test_` functions, no change, and `python -m pytest scripts/tests/` must stay green.

End to end: `llmll check` on fixtures 3 to 9; `llmll verify` on 1, 2, 10, 11, 13; `llmll verify --trust-report --json` on 1 and 13.

## Rollback

One commit, one revert. No codegen change. No flag: the feature is opt-in by program shape, and a module with no request sees no analysis, no error and no `.fq` change. No schema change; the trust report key is additive. The version change discards existing sidecars once in each direction; worst case is one full re-verify of a tree.

## Risks and unknowns

1. **Rev 6 awaits round 6 or the user's settlement.** Scope. `resp-fact-proposal.md` frontmatter. The delivery grammar and the export condition are the professor's own recommendations, folded verbatim, so the residual risk is a wording change. Complicates nothing; gates the branch.
2. **Only one dispatcher shape verifies in the fragment today.** DX. Cells c39, c40 crash the solver; c41 and row (t5) work. Routed as `PAIR-PROJ-LET-1` and `CALL-PRE-ARGCALL-1`. Complicates adoption on a scalar state; the consumer falls back instead.
3. **The delivery grammar is conservative.** DX. §5.3. A delivered value reaching a step by an unlisted route is refused loudly, with the call site named. Complicates; grows one row per measured idiom.
4. **The export condition forces `(export)` onto program modules.** DX. §5.2. The consumer has no list today and must add one. Complicates; local and cheap.
5. **Path guards dropped from premise obligations.** Verification. Sound and incomplete; a branch-chosen code must be lifted into a parameter with a `pre`. Scale only.
6. **`TRUST-AXIOM` granularity.** Trust. §11 item 3, §12. This row renders per function, per pair, with the premise case, for its own population; the `bytes-set` and `bytes-zero` axioms stay under their row. The user decides whether that meets §11 item 3.
7. **`docs/design/INDEX.md:94` says Rev 2.** Spec-drift. Doc-lead.

## Open questions for the professor

None. Both of round 5's questions are answered in Rev 6 §5.2 and §5.3, and this revision implements those answers. The next step is the user's approval, after which the branch is `resp-fact-1/control-tag-facts`.

## Appendix: the three witness cells, verbatim

All ran against the binary at HEAD (`llmll 0.16.2`, built 2026-08-19, no `compiler/` commit since).

### Cell W (R-4), `w_full.llmll`

```lisp
(import wasi.http (capability response :deterministic false))
(import wasi.proc (capability run :deterministic false))
(import wasi.io (capability stdout :deterministic false))
(type Ctl (| Probe) (| Ran) (| Halt))
(def-shell go [r: int p: Ctl c: Command] -> ((int, Ctl), Command)
  (pair (pair r p) c))
(def-shell h [p: Ctl x: Response] -> int
  (pre (= p Ran))
  (post (>= result 100))
  (match x ((RCode n) n) (_ 100)))
(def-shell outer [q: Ctl x: Response] -> int
  (pre (= q Probe))
  (post (>= result 100))
  (let [(t Ran)] (h t x)))
(def-shell probe-step [r: int x: Response] -> ((int, Ctl), Command)
  (go (outer Probe x) Ran (wasi.http.response 200 "")))
(def-shell ran-step [r: int x: Response] -> ((int, Ctl), Command)
  (go r Halt (wasi.io.stdout "done")))
(def-shell step [s: (int, Ctl) input: string x: Response] -> ((int, Ctl), Command)
  (match (second s)
    ((Probe) (probe-step (first s) x))
    ((Ran)   (ran-step (first s) x))
    ((Halt)  (go (first s) Halt (wasi.io.stdout "")))))
(def-shell done? [s: (int, Ctl)] -> bool
  (match (second s) ((Halt) true) ((Probe) false) ((Ran) false)))
(def-main :mode console
  :init (pair (pair 0 Probe) (wasi.proc.run "/bin/sh" ["-c" "exit 1"] "." "/dev/null" "/dev/null" 5 "/dev/null"))
  :step step
  :done? done?)
```

Output at HEAD, `llmll verify w_full.llmll`:

```
   body-faithful: h, outer
   body-fallback: go, probe-step, ran-step
   call-pre obligations: outer
   Running liquid-fixpoint ...
error: body verification of 'h' failed (then-branch does not satisfy postcondition) (constraint #0)
```

Under Rev 5 the only delta is the `x$RCode` binder of `h`, which gains `v >= 100`. The runtime value on the first turn is `RCode 1`. Under Rev 6 the delivery rule refuses `(h t x)` at `check`.

### Cell D (R-5), `lib.llmll` and `main_open.llmll`

```lisp
;; lib.llmll
(type Ctl (| Boot) (| Ran))
(def-shell mk-lib [] -> Ctl Ran)
```

```lisp
;; main_open.llmll
(import lib)
(open lib)
(def-shell mk [] -> Ctl Ran)
(def-shell mk2 [] -> Ctl (Ran))
(def-shell recv [p: Ctl] -> int
  (pre (= p Ran))
  (post (= result 0))
  0)
```

Output at HEAD: `llmll check main_open.llmll` passes with five statements; `llmll verify main_open.llmll` reports `body-faithful: recv` and SAFE; `llmll build main_open.llmll` passes.

### Cell E (R-6), `amain.llmll` and `bmain.llmll`

```lisp
;; amain.llmll
(import wasi.io (capability stdout :deterministic false))
(type Ctl (| Boot) (| Ran))
(def-shell go [r: int p: Ctl c: Command] -> ((int, Ctl), Command)
  (pair (pair r p) c))
(def-shell a-step [s: (int, Ctl) input: string x: Response] -> ((int, Ctl), Command)
  (go (first s) Ran (wasi.io.stdout input)))
(def-shell a-done [s: (int, Ctl)] -> bool false)
(def-main :mode console
  :init (pair (pair 0 Boot) (wasi.io.stdout "a"))
  :step a-step
  :done? a-done)
```

```lisp
;; bmain.llmll
(import wasi.io (capability stdout :deterministic false))
(import wasi.proc (capability run :deterministic false))
(import amain)
(open amain)
(def-shell b-step [s: (int, Ctl) input: string x: Response] -> ((int, Ctl), Command)
  (pair (first (a-step s input x)) (wasi.proc.run "/bin/true" [] "." "/dev/null" "/dev/null" 5 "/dev/null")))
(def-shell b-done [s: (int, Ctl)] -> bool false)
(def-main :mode console
  :init (pair (pair 0 Boot) (wasi.io.stdout "b"))
  :step b-step
  :done? b-done)
```

Output at HEAD: `llmll check bmain.llmll` passes; `llmll verify bmain.llmll` reports SAFE; `llmll build bmain.llmll` passes. With `(export)` in `amain.llmll`, `bmain` cannot name `a-step`.
