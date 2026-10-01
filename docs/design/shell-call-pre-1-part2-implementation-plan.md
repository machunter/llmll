---
name: shell-call-pre-1-part2-implementation-plan
title: "SHELL-CALL-PRE-1 Part 2: implementation plan"
status: "Approved 2026-10-01. Stage A IMPLEMENTED (commit 514057b, branch shell-call-pre-1/part2-walker, unmerged) and the gate decided 0 of 16 tool call sites, so the risk 2 stop rule applies. Stage B NOT BUILT; Part 2 PARKED 2026-10-01. Implements shell-call-pre-1-proposal.md Rev 3."
date: 2026-10-01
author: compiler-engineer
consumers: [user, llmll-patch-implementer, documentation-lead]
implements: "shell-call-pre-1-proposal.md (Rev 3)"
---

# SHELL-CALL-PRE-1 Part 2: implementation plan

## Restatement

At each call site of a callee with a `pre` in `Σ_auto`, inside a caller with
no body VC, the verifier tries to prove the `pre` from facts that translate
faithfully. A side query gives each site one of four outcomes. The outcomes
reach the `verify` output and the trust report. They never change the exit
status, a verdict, or the generated code.

## Context located

1. `docs/design/shell-call-pre-1-proposal.md` Rev 3: the settled design. Section 4.2 lists the kept facts and the four outcomes.
2. `docs/compiler-team-roadmap.md` row `SHELL-CALL-PRE-1` (G1): DECIDE marker; Part 1 shipped v0.26.14.
3. `compiler/src/LLMLL/FixpointEmit.hs` `bodyToPredM` / `bodyToPredFromRS`: returns `Maybe BodyVC`, all or nothing. A body that falls back has no tree to walk.
4. `compiler/src/LLMLL/FixpointEmit.hs` `collectCallPreObligations`: the in-fragment site walk over `BodyVC`. Part 2 copies its outputs, not its input type.
5. `compiler/src/LLMLL/FixpointEmit.hs`, the `call-pre:` emission block in `emitFixpointWithCache`: the binder, `ctxCalls`, `inScopeLbs` and `evalClosedFQ` handling that the side query copies.
6. `compiler/src/LLMLL/FixpointEmit.hs` `inScopeLbs` and `exprToPred`: the fact translators. `exprToPred` handles `and`, `or`, `=>` as both `EApp` and `EOp`.
7. `compiler/app/Main.hs` `checkWeaknessCandidate`: the side-query precedent. It writes its own `.fq` and runs `fixpoint` once.
8. `compiler/src/LLMLL/DiagnosticFQ.hs` `parseFQResult`: `FQUnsafe` carries the failing constraint ids. One solver run can decide every site.
9. `compiler/src/LLMLL/TrustReport.hs` `uncheckedCallPres`, `markCallerObligations`, `collectDeclaredRequires`: the Part 1 surface, at pair level.
10. `compiler/src/LLMLL/CallGraph.hs` `resolveIn`, `qualifiedCallGraph`: the resolver for names reached through `open`.
11. `compiler/src/LLMLL/ObligationAssembly.hs` `assembleSafePreObligations` and the `call-pre:` classifier: how `precondition-obligation` rows get a status today.
12. `compiler/app/Main.hs` `doVerify`: the trust report is built in process from `emitR` by a chain of `mark*` functions. No sidecar read is needed for Part 2.
13. Measured 2026-10-01 on v0.27.0: 15 `call-pre unchecked` pairs in 4 tool programs (proposal measurement 3).

## Plan summary

Add one walker over the surface `Expr` of each caller with no body VC. It
records each call site of a `pre`-bearing callee with its context Γ_s. For each
site, emit three kvar-free constraints into a separate `.fq` file. Run
`fixpoint` once on that file. Read the failing ids, and derive each site's
outcome in the design order. The cost is one extra solver run when at least
one site exists, and none otherwise. Stage A stops after the outcome counts
print, so the user can see the yield before stage B adds the trust-report and
obligation-report rows.

## Affected surface

**Stage A (prototype and gate).**

- `compiler/src/LLMLL/FixpointEmit.hs`: a new walker `collectFallbackCallSites`. It takes the caller's params with sorts, its `pre`, the `ContractEnv`, and the body. It returns one record per site: callee, surface args, kept facts, declared binders, and an `unproved` reason when the site cannot be emitted. It does not touch `bodyToPredM` or `collectCallPreObligations`.
- `compiler/src/LLMLL/FixpointEmit.hs`: a new function `emitCallSiteQuery`. It renders the side `.fq` text and a table from constraint id to (site, check). It reuses `exprToPred`, `inScopeLbs`, `evalClosedFQ`, and the binder declarations of the `call-pre:` block.
- `compiler/src/LLMLL/FixpointEmit.hs` `EmitResult`: a new field `erCallSites`. It carries the site records for callers in `erBodyFallback` and for callers with no `post`.
- `compiler/app/Main.hs` `doVerify`: run the side query after the main query. Print one line, `call sites: <n> proved, <n> unreachable, <n> violated-if-reached, <n> unproved`. Skip the run when there are no sites.
- `compiler/test/`: the walker and outcome cells in the test plan.

**Stage B (report surfaces, after the user reviews the stage A counts).**

- `compiler/app/Main.hs`: the headline counts from proposal Section 4.2. Filter the `call-pre unchecked:` line to sites that are not `proved`. A pair with a callee passed as a value, with no application site, stays on the line.
- `compiler/src/LLMLL/TrustReport.hs`: a new `markCallSiteOutcomes`. `markCallerObligations` drops a callee only when every site to it is `proved` and no value use exists. One helper applies the mark at every `buildTrustReport` call in `doVerify`, so the nine call sites cannot disagree.
- `compiler/src/LLMLL/TrustReport.hs`: `inherited-axiom` rows for each `post` that a `proved` site used and that nothing proves. `trustReportEmitVersion` changes from `1.8.0` to `1.9.0`.
- `compiler/src/LLMLL/ObligationAssembly.hs`: sited `precondition-obligation` rows with the outcome as `status`. The site id uses `renderCallSite`, the OBLIG-D4 discriminator. `orSchemaVersion` changes from `0.12.4` to `0.13.0`.
- `docs/llmll-ast.schema.json`: no change. No node shape changes.
- `.verified.json` sidecar: no change. Outcomes are recomputed on each `verify` and are not persisted.

## Walker rules

The walker follows proposal Section 4.2 exactly. These rules are the
engineering detail the design leaves open.

1. **Callee resolution.** A call `(g ...)` is a site only if `g` resolves through `resolveIn` to a function with a `pre`, and `g` is not a local binder. A `let`, lambda or match binder named `g` shadows it. The same resolution applies to an argument call `h(...)`, so a `post` reached through `open` is found. This prevents a second instance of finding D2.
2. **Arguments.** Each argument gets a fresh variable with the callee's parameter sort. The walker adds `v = exprToPred(aᵢ)` when it translates. For an argument call `h(...)`, it adds `h`'s `post` over a fresh result variable, after substituting `h`'s translated arguments. An argument that does not translate gets no fact. If the `pre` mentions that variable, the reason is `argument-outside-fragment`.
3. **Scope.** The walker keeps a scope set and a list of `let` and `do` bindings. It filters them with `inScopeLbs` at each site. A rebinding removes the outer fact for that name (edge case 6).
4. **Guards.** `EIf c t e` adds `exprToPred c` in `t` and its negation in `e`. `and`, `=>`: the left operand is true in the right. `or`: the left operand is false in the right. Both the `EApp` and the `EOp` spellings are handled (edge case 8). `<=>` adds nothing.
5. **Lambdas.** `ELambda` keeps the enclosing facts and scope. Its parameters enter scope with no fact.
6. **Match.** `EMatch` adds no fact. Its pattern binders enter scope with no fact, and they shadow.
7. **Builtin call-pre.** `bytes-get`, `bytes-set` and `map-get` sites are out of scope for Part 2. The design names user callees only.
8. **Trust level of a proved site.** The meet ranges over every callee `post` kept in Γ_s, not only the posts the proof used. Unsat-core extraction is deferred (`PROOF-ARTIFACT` record). This can understate a site's level and never overstates it.

## Verification impact

- **New obligations.** At most three constraints for each site, all kvar-free, in a separate query. On the 15 measured pairs this is about 50 constraints.
- **Fragment.** QF-LIA only. Every fact and goal passes through `exprToPred`, so nothing nonlinear and nothing for Lean (`LLMLL.md` §5.3.3).
- **Verdicts.** No change. The main `.fq` is byte-identical before and after. A test compares the main `.fq` of every `tools/` entry program before and after the patch.
- **Strict-verified-core.** No change. No function newly falls back.
- **Trust model.** A callee leaves `caller_obligations` only when all its sites are `proved`. The new `inherited-axiom` rows can only lower a displayed level.

## Performance budget

- **GHC build.** `FixpointEmit.hs`, `TrustReport.hs`, `ObligationAssembly.hs` and `Main.hs` change. These modules recompile on most changes already.
- **`llmll verify`.** One extra `fixpoint` process when any site exists. Expected 0.1 to 0.3 s on `sequencer.llmll`. Stage A measures it. The limit is 10 % of the `verify` time of each of the 4 programs.
- **Programs with no site.** No extra run. The 5 other tool programs and most examples are in this group.
- **`stack test`.** About 20 new hspec cells and 2 end-to-end cells. Expected under 5 s added.

## Contract plan

This change lands nothing in the provable fragment. It is Haskell inside the
compiler, and the compiler is not written in LLMLL.

## Test plan

Baseline: re-measure `stack test` and `python -m pytest scripts/tests/` on the
branch base. The v0.27.0 figures were hspec 2174 and pytest 431.

**Stage A, hspec cells (`compiler/test/Spec.hs`), one per row:**

| Cell | Input | Expected outcome |
|---|---|---|
| A1 | edge case 1, `let` to `-1` | `violated-if-reached` |
| A2 | edge case 2, nested contradictory guards | `unreachable` |
| A3 | edge case 3, literal `(- 0 5)` | `violated-if-reached` |
| A4 | edge case 4, helper with no `post` | `unproved (context)` |
| A5 | edge case 4 with `(post (>= result 0))` on the helper | `proved` |
| A6 | edge case 5, `(>= x 0)` guard | `proved` |
| A7 | edge case 5, guard outside the fragment | `unproved (context)` |
| A8 | edge case 6, inner `x` shadows `x = -1` | `unproved (context)`, never `violated-if-reached` |
| A9 | edge case 6 reversed, inner `x = -1` shadows a non-negative `x` | `violated-if-reached`, never `proved` |
| A10 | edge case 7, lambda parameter as argument | `unproved (argument-outside-fragment)` |
| A11 | edge case 7, captured variable under a guard | `proved` |
| A12 | edge case 8, `(and (>= x 0) (ok? x))` | `proved` |
| A13 | edge case 8, `(or (>= x 0) (ok? x))` | `violated-if-reached` |
| A14 | edge case 8, `(=> (>= x 0) (ok? x))` | `proved` |
| A15 | edge case 8, the `EOp` spelling of A13 | `violated-if-reached` |
| A16 | edge case 9, zero-parameter `(k)` with a `post` | `proved` |
| A17 | edge case 10, callee through `open` | the site is found, with an outcome |
| A18 | edge case 11, `pre` outside `Σ_auto` | `unproved (pre-outside-fragment)` |
| A19 | a `let` binder named like the callee | no site |
| A20 | main `.fq` of each `tools/` entry program | byte-identical before and after |

A8, A9, A13 and A15 are the soundness cells. Each must fail when the matching
walker rule is removed. The implementer runs that negative control once and
reports it.

**Stage A, gate measurement.** Run `llmll verify` on the 4 programs of
proposal measurement 3. Report a table: program, sites, and the count for each
outcome. Report the `verify` time before and after. Stop and hand the table to
the user.

**Stage B, cells.**

- B1: `verify --trust-report` on a fixture with one `proved` and one `unproved` site to the same callee. The callee stays in `caller_obligations`.
- B2: the same fixture with both sites `proved`. The callee leaves `caller_obligations`, and an `inherited-axiom` row names the helper `post`.
- B3: `--obligation-report` gives two `precondition-obligation` rows with different site ids.
- B4: `--contracts=unproven` on a `proved` site. The generated `Lib.hs` still contains the `Precondition violated` check.
- B5 (pytest): the headline line on one fixture, and exit 0 on a `violated-if-reached` site.

Target: hspec baseline + 24, pytest baseline + 1.

## Rollback

Each stage is one commit, and each reverts alone. Stage A changes only an
extra output line. Stage B changes two report version stamps. A consumer that
pins `trust_report_version` 1.8.0 must accept 1.9.0. No sidecar or `.fq`
cache migration exists, because outcomes are not persisted.

## Risks and unknowns

1. **Walker soundness at shadowing and `or`.** Verification. A wrong rule gives a false `proved` in a report. Cells A8, A9, A13 and A15 with their negative control block the stage A commit.
2. **Low yield.** Scope. The sequencer sites pass booleans from `is-ok` and `has-arr?` and values from JSON reads. Many sites may end `unproved (context)`. The stage A table decides whether stage B is worth its cost. If fewer than 3 of the sites are `proved` or `violated-if-reached`, the plan recommends shipping stage A's disclosure counts only.
3. **Sort of an argument variable.** Build. A parameter of sort `Json`, `string` or a datatype needs a declared sort in the side `.fq`. The walker copies the sort mapping that `calleeSorts` gives the main path. A sort it cannot map makes the site `unproved (argument-outside-fragment)` instead of an ill-sorted `.fq`.
4. **Nine `buildTrustReport` call sites in `doVerify`.** DX. A mark missed on one path gives two trust reports that disagree. Stage B routes all nine through one helper, and cell B1 runs through two of the paths.
5. **`fixpoint` sanitizer.** Build. A closed-true goal is rejected as an RHS. The emitter applies the `evalClosedFQ` rule from the `call-pre:` block: closed-true makes check 2 `proved` without a constraint, and closed-false is kept as `false`.
6. **Spec drift.** None found against `LLMLL.md` §4.7 or the Part 1 paragraph in §5.3.4. Doc-lead owns the §5.3.4, §5.3.5 and §11.2 text after stage B ships.

## Documentation hand-off (held until stage B ships)

Tag `SHELL-CALL-PRE-1` Part 2. `verify` prints the call-site outcome counts in
the headline and lists only sites that are not proved on `call-pre unchecked:`.
`trust_report_version` 1.9.0 and obligation-report schema 0.13.0 add sited
outcomes. CHANGELOG candidate: "`verify` now proves, refutes or marks
unreachable a callee's `pre` at each call from a body that falls back, in a
side query that does not change the verdict."
