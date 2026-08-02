---
name: effect-response-channel-proposal
title: "EFFECT-RESP: a response channel, so an LLMLL program can consume the result of its own effects"
status: "Rev 2, SETTLED. Two professor rounds folded (in-session, 2026-08-02); Rev 0's Result-returning read withdrawn; RESUME-1 promoted from workaround to the design; CMD-A recorded as target; DO-ACCUM-1 routed as a separate shipped-codegen defect."
date: 2026-08-02
author: language-team
consumers: [compiler-engineer, professor, documentation-lead, user]
---

# EFFECT-RESP: a response channel

**One line.** `wasi.fs.read : string -> Command` and a `Command` is opaque, so no LLMLL program can
read a file and branch on the contents. The fix is a response channel in the `def-main` harness, not
a result-returning read builtin.

---

## Background

The gap was found by attempting to port the RFC-SWARM driver into LLMLL and discovering that stage A
of fifteen is inexpressible. It is not a missing capability. It is a property of the effect model.

### What was measured, at `llmll 0.14.78`

| Probe | Result |
|---|---|
| `(string-length (wasi.fs.read p))` | type error: *expected string, got Command* |
| `wasi.fs.read` signature | `TFn [TString] (TCustom "Command")` (`compiler/src/LLMLL/TypeCheck.hs:158`) |
| `Command` arity | nullary; `toHsType (TCustom "Command") = "IO ()"` (`CodegenHs.hs:830`) |
| `seq-commands` signature | `Command -> Command -> Command` (`TypeCheck.hs:161`) |
| console harness | `line <- getLine; let (s', cmd) = step s line; output <- captureStdout cmd; loop s'` (`CodegenHs.hs:944-950`). The command's output is captured for the event log and **not** passed to the next step. |
| `:mode cli` harness | `main = do args <- getArgs; print (step args)` (`CodegenHs.hs:970-975`). Executes no `Command` at all. |
| `:mode http` harness | emits `error "http mode: wire warp in package.yaml and uncomment above"` (`CodegenHs.hs:980-994`). Does not run. |
| corpus effect census | 40 `wasi.io.stdout`, 2 `wasi.fs.write`, **1** `wasi.fs.read` (in `tools/llmll-driver/shell.llmll:45`, which returns the `Command` unconsumed). Every runnable example is `:mode console`. |

### The accurate characterization

`Command` is nullary and `seq-commands` is its monoid operation, so LLMLL's effect type is not even
an applicative functor: it carries no result parameter. The consequence is not that effects are
unreadable; it is that **the effect structure cannot depend on any value**. That is the
applicative/monad boundary (McBride and Paterson, *Applicative Programming with Effects*, JFP 18(1)
2008, §5; the hierarchy in Lindley, Wadler and Yallop, *Idioms are Oblivious, Arrows are Meticulous,
Monads are Promiscuous*, MSFP 2008). LLMLL today is a language for pure transducers: a value arrives
on a fixed channel, a value and a batch of commands leave.

Programs that do **not** hit this: anything console-shaped (input arrives on the stdin channel),
anything emit-only, and agent delegation via `?delegate-async` / `await`. Programs that **do**:
anything that fetches its own inputs.

### Three drifts found on the `do` construct, all compounding

1. The settled design (`docs/archive/do_notation/do-notation-design.md` r6, 2026-04-05, §2.3-§2.4)
   requires codegen to compose every step's command via `seq-commands`. `emitDo`
   (`CodegenHs.hs:741-757`) returns `(finalState, _cmdN)` and drops the rest.
2. `checkDiscardedCommand` (`TypeCheck.hs:1857-1866`) warns instead, with an in-code note deferring
   a hard error to **v0.8**. Shipped is 0.14.78.
3. The same design mandated that its non-monadic framing appear verbatim in `LLMLL.md §9`. Grep for
   "not a monad", "structured let-binding", "pair-thread", "do-notation", "do-block": **zero hits**
   in `LLMLL.md`. `do` appears only in the keyword list (`:35`), the grammar (`:2124-2125`), and one
   diagnostic note (`:1605`). There is no semantics section for it.

This is why two independent readings of `LLMLL.md` could not settle whether the effect model was
deliberate: the document that answers it is in `docs/archive/`.

---

## What Rev 0 proposed and why it was withdrawn

Rev 0 proposed `wasi.fs.read-string : string -> Result[string, IoError]`, `def-shell`-only,
justified by analogy to `await : Promise[t] -> Result[t, DelegationError]`.

**Withdrawn on two grounds.**

First, it performs IO during evaluation of a pure expression. `LLMLL.md:415` states that all
functions are stateless and that IO-capable functions route effects through `Command` values and the
`def-main` shell. In codegen the builtin could only be `unsafePerformIO` or a type change to `IO`.
The existing `unsafePerformIO` compromise (`CodegenHs.hs:337-342`, used for `regex-match`) does not
license it: `subject =~ pattern` is referentially transparent and the wrapper exists only to
totalize a partial regex compile; `readFile p` is not a function of `p`. Worse, effect order would
depend on an evaluation order §12 does not pin, which breaks the §10a replay guarantee for exactly
the programs the feature exists to enable. The settled do-notation design already assigns command
*composition* to codegen (§2.4), so the project has committed to effects having positions in a
composed sequence; an effect performed during evaluation has no position in it.

Second, the `await` analogy was drawn from where the analyses abstain: `?delegate-async` is a
compile-time hole, an opaque hole maps to ⊤ in the authority summary
(`ObligationAssembly.hs:449`), and `LLMLL.md:795` places `await` and command constructors in the
`skip` set that contributes zero trust evidence.

**One half of that precedent is reinstated.** `Promise[t]` is a shipped, parameterized effect handle
with a `Result`-returning eliminator (`LLMLL.md:1743-1776`). That type-level shape is sound and is
exactly what CMD-A needs. Rev 1 over-withdrew it; Rev 2 restores it as CMD-A's precedent.

---

## Design: EFFECT-RESP

### Surface

The `:step` function of a `def-main` gains a response parameter. Illustrative only; the
`documentation-lead` formalizes the grammar after the engineer ships.

```lisp
(def-main
  :mode   console
  :init   (init-run)
  :step   drive
  :done?  finished?
  :on-done report)

(def-shell drive [s: RunState r: Response] -> (RunState, Command) …)
```

JSON-AST: the `def-main` node shape is unchanged. The `step` field's referent changes arity from
1 to 2, which is a type-level fact carried by the existing field. **No schema version bump.**

### Semantics: four invariants

**RC-1 (bijection).** Every command the harness performs yields exactly one `Response`, delivered as
the `r` argument of the next `step` call.

**RC-2 (`seq-commands` is discard-left).** `(seq-commands c1 c2)` performs `c1` then `c2` and yields
`c2`'s response; `c1`'s response is discarded. `seq-commands` is thereby the monoid's
sequence-and-drop operator, which is the sentence §13.9 does not currently contain. RC-1 is stated
per *step*, not per syntactic command, and RC-2 is what makes that well defined.

**RC-3 (initialization).** `:init`'s command, when present, yields the **first** response delivered
to `step`. With no `:init` command the first response is `RNone`. There is no special initial case
beyond this.

**RC-4 (termination).** `done?` is evaluated only on a state produced by a `step` that has received a
response. The harness therefore performs one final `step` to fold in the last response, and **the
command returned by that terminating step is not performed.**

The loop, illustrative:

```
r₀      = perform initCmd            -- or RNone when :init has no command
loop s r =
  let (s', cmd) = step s r
  in if done? s' then on-done s'     -- cmd is NOT performed
     else loop s' (perform cmd)
```

Commands performed are `initCmd` plus each non-terminating step's command; responses delivered are
`r₀` plus one per performed command. The bijection of RC-1 holds and the terminating step's command
never owes a response.

### `Response` is compiler-supplied, not program-declared

This answers the professor's second question and it is a decision, not a preference.

```lisp
;; illustrative shape; sealed in builtinEnv, not a user `type` declaration
Response = (| RNone) (| RText string) (| RCode int) (| RErr string)
```

Four reasons.

1. The response alphabet is a function of the **command** alphabet, and commands are sealed in
   `builtinEnv` (`TypeCheck.hs:154-161`; `LLMLL.md §13.9`). A program cannot introduce a command, so
   it cannot need an arm. Program-declaration would admit dead arms no command produces and omit
   arms some command does.
2. It settles `Σ_auto` admissibility **once for the language** rather than per program.
3. It keeps the harness contract a language-level property, so any conforming harness can drive any
   program. That matters directly here, because the driver's harness is Haskell today and may be
   LLMLL later.
4. It matches the shipped precedent: `await`'s error type `DelegationError` is compiler-supplied,
   not program-declared (`LLMLL.md:1747`).

`RErr` is required, not optional: an effect failure must arrive as a value, which is what preserves
"logic functions cannot crash from IO" (`LLMLL.md:1747`).

**Payload classes are `string` and `int` only.** Both are inside `Σ_auto` (int natively, string via
STRLIT equality/distinctness/length). There is deliberately **no `RBytes` arm**: `bytes[n]` requires
a literal length at the type level and a file read's length is not statically known. Binary reads are
a named residue of this proposal, not an oversight, and route to a future row.

### The command-to-response pairing is unchecked, and CMD-A closes it

Nothing types the pairing between the command issued and the response received. If a step returns
`(wasi.fs.read p)` and the harness supplies `RCode 5`, no type error occurs. Two things bound it:
exhaustive matching is enforced (`TypeCheck.hs:1887`, called at `:1566`), so the program must handle
the arm it did not expect and the mismatch is a value rather than a crash; and the residue is a
**trust-channel assumption on the harness**, the same category as TRUST-AXIOM
(`docs/compiler-team-roadmap.md:55`), to be reported the same way.

**Rev 1 routed this closure to R1 (indexed types) and that was wrong.** R1 is `Vect n a`, GADTs,
type-level arithmetic and bidirectional elaboration (`docs/compiler-team-roadmap.md:216`, declined by
professor consensus 2026-05-01). The pairing check needs only the effect handle to carry its own
result type, which is CMD-A's type parameter. It is cheaper than the GADT framing suggests for one
specific reason: the effect constructors live in the sealed `builtinEnv`, **not** in the user-facing
`type` grammar, so constructors at varying result index never reach the surface where LLMLL would
need GADT syntax. This proposal therefore **anticipates** CMD-A and **sidesteps** R1.

There is no cheap middle. Typing the response by the command a step actually returned makes the
step's result existential in the command's index, and eliminating that existential is a GADT match,
which is CMD-A proper. The monomorphic `Response` is the correct near-term shape and its residue has
a named closure.

---

## DO-ACCUM-1: a separate, shipped codegen defect

Routed as its own row. Not a prerequisite of EFFECT-RESP's semantics, but it must land first because
it is verifiable in isolation and because RC-2 gives `seq-commands` the meaning the fix depends on.

`emitDo` must compose per `do-notation-design.md` §2.4 instead of returning the last command.
`checkDiscardedCommand` is then **deleted**, not promoted to an error: after the fix there is nothing
to warn about. The verbatim §9 text the settled design mandated should land in the same release.

**Measured positive witness.** Source:

```lisp
(def-shell step-a [n: int] -> (int, Command) (pair (+ n 1) (wasi.io.stdout "A")))
(def-shell step-b [n: int] -> (int, Command) (pair (+ n 1) (wasi.io.stdout "B")))
(def-shell both  [n: int] -> (int, Command) (do [x <- (step-a n)] [y <- (step-b x)]))
```

Emitted at HEAD:

```haskell
both n = (let { (x, _cmd0) = (step_a (n)); (y, _cmd1) = (step_b (x)) } in (y, _cmd1))
```

`_cmd0` is bound and never used, so `"A"` is never printed. Typecheck passes with one warning.

**Blast radius measured zero.** `(do ` occurs twice in the whole tree, both in
`examples/*/walkthrough.md`. No `.llmll` or `.ast.json` program contains a do-block, which is why the
defect has survived. It fires the first time anyone writes sequencing code.

---

## CMD-A: parameterized `Command[a]` (recorded target, not scheduled)

The eventual move is the free-monad-over-signature construction: `Command[a]` with each operation
carrying its own result type, the harness as interpreter (Swierstra, *Data Types à la Carte*, JFP
18(4) 2008; Kiselyov and Ishii, *Freer Monads, More Extensible Effects*, Haskell Symposium 2015).

**Boundary, to be written into the CMD-A proposal rather than rediscovered:** take the
signature-plus-interpreter construction, **decline algebraic-effect handlers** (Plotkin and Pretnar,
ESOP 2009; Bauer and Pretnar, JLAMP 84(1) 2015). Handlers commit to delimited continuations and
multi-shot resumption, which would break the crash-freedom rule at `LLMLL.md:1747` and make a linear
event log an inadequate replay record.

**Strict-core admission is settled by the existing rule, not a new one.** `LLMLL.md:451` partitions
bodies: `def` admits linear arithmetic, `let`, conditionals, pair operations, `Result` two-arm
matching, and calls to builtins or body-faithfully verified functions; everything else including IO
is `def-shell`. A `Command[a]` bind is an IO construct and lands in `def-shell` under that rule. Its
continuation is a lambda, and `docs/compiler-team-roadmap.md:238` already records `ELambda`
higher-order body VCs as outside `Σ_auto` by design, so the exclusion is inherited rather than
decided. **CMD-A therefore adds no verification surface: it is a type-and-codegen change.**

---

## Edge cases and degenerate inputs

1. **Positive witness for DO-ACCUM-1**, reproduced above: a two-step do-block whose first command is
   bound to `_cmd0` and dropped. **Channel: spec is silent (gap, flagged)**, because `LLMLL.md` has
   no `do` semantics section; the authority is `do-notation-design.md` §2.4, which the emitter
   contradicts.
2. **First turn with no `:init` command.** `r = RNone`; the program must have an `RNone` arm.
   **Channel: type**, via `checkExhaustive` (`TypeCheck.hs:1887`).
3. **Response arm mismatched to the issued command.** Step returns `(wasi.fs.read p)`, harness
   supplies `RCode 5`. No type error; the program takes its `RCode` arm. **Channel: trust
   (disclosure required, not currently emitted).** Closed by CMD-A.
4. **A program whose final effect matters.** Under RC-4 the terminating step's command is not
   performed, so a program that must observe its last write has to issue it from a non-terminating
   step and terminate on the response. **Channel: spec is silent (intentional)**, and the spec must
   say so in §9 rather than leave it to be discovered.
5. **A step returning `(seq-commands c1 c2)`.** Both are performed in order; the delivered response
   is `c2`'s. **Channel: contract**, under RC-2. This is also what a composed do-block produces after
   DO-ACCUM-1, so the two rows meet here rather than being independent as Rev 1 claimed.
6. **A single-step do-block.** `(do [x <- (step-a n)])` is unchanged before and after DO-ACCUM-1,
   since the final command is the only command. **Channel: contract, vacuously.** This degenerate
   arity is correct under both the design and the current emitter, which is how the defect shipped.
7. **A binary file read.** No `RBytes` arm exists, so a program cannot consume one.
   **Channel: type**, by absence. Named residue; routes to a future row.

---

## Verification mapping

| Obligation | Channel | Fragment | Boundary |
|---|---|---|---|
| Step contracts over `S` and extracted response payloads | contract | QF-LIA, auto-discharged, unchanged from today | `LLMLL.md §5.3.3`; `tools/llmll-driver/*.llmll` is the shipped witness |
| `match` on `Response` | contract | QF-LIA plus acyclic datatype theory, polite-combined | `§5.3.3` datatype class; MATCH-WIDEN-2 (v0.14.26) covers n-arm sums |
| RC-1 through RC-4 | trust | no SMT obligation; harness invariants requiring disclosure | `§4.1` anti-laundering; TRUST-AXIOM shape |
| Command-to-response pairing | trust | no obligation; a disclosure surface until CMD-A | `docs/compiler-team-roadmap.md:55` |
| `:step` arity | type | not an SMT obligation | `TypeCheck.hs` `def-main` checking |
| DO-ACCUM-1 composition | none | codegen conformance to a settled design; no VC touched | `do-notation-design.md` §2.4 |
| CMD-A bind in a body | none | excluded from the core grammar with `ELambda` | `LLMLL.md:451`; `roadmap:238` |

**`Σ_auto` is unchanged by every item in this proposal.** No new sort, no new theory, no fragment
widening. The effect model can be repaired without touching the verification fragment, which is the
strongest property this design has.

---

## Affected surface

1. `compiler/src/LLMLL/CodegenHs.hs:741-757` — `emitDo` composition (DO-ACCUM-1).
2. `compiler/src/LLMLL/CodegenHs.hs:917-975` — the console harness loop, restructured per RC-1..RC-4.
3. `compiler/src/LLMLL/TypeCheck.hs:154-161` — `Response` in `builtinEnv`; command result mapping.
4. `compiler/src/LLMLL/TypeCheck.hs:1828-1866` — `inferDoSteps`; `checkDiscardedCommand` deleted.
5. `compiler/src/LLMLL/TypeCheck.hs` — `def-main` `:step` arity check.
6. `LLMLL.md` §9 — a `do` semantics subsection that does not exist, carrying the verbatim
   non-monadic framing `do-notation-design.md` mandated; §13.9 gains RC-2's sentence for
   `seq-commands`; a new §9.x for the response channel. Doc-lead's slot, after the engineer ships.
7. Schema: JSON-AST unchanged, **no version bump**.
8. Freeze policy: not applicable, lifted at v0.11 (`docs/compiler-team-roadmap.md:242`, which names
   "new syntax constructs" and "more WASI surface" among the lifted exclusions, subject to the normal
   pipeline with a written soundness argument, supplied here).

---

## Risks and open questions

1. **RESUME-1 changes `def-main` `:step` arity, a breaking change to every console program.**
   Classification: scope. Five in-tree programs use `:mode console`. Bite: complicates; a migration
   that adds an ignored `r: Response` parameter is mechanical.
2. **Turn granularity becomes control-flow granularity.** Classification: verification-ergonomics. A
   program performing N result-consuming reads needs N turns and a state constructor per resumption
   point; the driver's fifteen stages with per-stage reads become a state machine with a state per
   read. This is the defunctionalized-continuation cost (Reynolds, *Definitional Interpreters*,
   1972). Bite: does not block; it sets the size of `RunState` and the engineer must scope it up
   front rather than discover it at stage E.
3. **DO-ACCUM-1 is a shipped codegen defect with zero in-tree witnesses.** Classification:
   soundness (codegen) / spec-drift. Bite: blocks nothing today and fires on the first sequencing
   code written. Land it first, alone, so its verdict is attributable.
4. **The pairing residue is a trust assumption with no reporting surface.** Classification: trust
   disclosure. Bite: complicates; it must be disclosed in the trust report, not left implicit, and
   it is the same silence TRUST-AXIOM already names for builtin axioms.
5. **`:mode http` does not run and `:mode cli` performs no effects.** Classification: spec-drift.
   `CodegenHs.hs:980-994` and `:970-975`. Bite: only matters when someone builds a service or a CLI
   tool, which is the next thing after the driver. Not in this proposal's scope; routed.

---

## Review log

Two professor rounds, in-session on 2026-08-02, folded here rather than filed standalone because the
session predates any proposal file.

**Round 1** (on Rev 0). Hazard 1: the `Result`-returning read performs IO during pure evaluation and
leaves effect order unspecified; blocks the proposal. Hazard 2: the `await` precedent is drawn from
where the authority summary is ⊤ and the PBT channel abstains. Hazard 3: `do` already discards
intermediate commands with a stale deferral. Hazard 4: the effect type is a monoid, not an
applicative, and value-dependence is the applicative/monad boundary. Recommendation: reject the read
family, adopt the resumption formulation and stop calling it a workaround, target the freer monad,
decline handlers, route the do defect separately. **All adopted in Rev 1.**

**Round 2** (on Rev 1). Hazard 1: `seq-commands` batches have no answer in a scalar response channel;
Rev 2 answers with RC-2. Hazard 2: DO-ACCUM-1 and EFFECT-RESP are coupled, not independent; Rev 2
states the coupling in edge case 5. Hazard 3: **Rev 1's Q2 premise was false.** Bundle B0 was recast
from a must-lower-bound to a **may-over-approximation** in its own Rev 2 after an earlier professor
round (`docs/archive/shipped-design-specs/bundle-b0-effect-summary-proposal.md:100, :109`, §4.2), and
`ownEffects` joins both arms of every `EIf` and every match arm
(`ObligationAssembly.hs:443-444`), so the summary is already an over-approximation at the first
conditional in any program. Exactness was never a property of the analysis. CMD-A therefore costs
nothing on that axis and driver-spec §15.2's over-approximation phrasing was already the right match.
Hazard 4: the pairing residue is closed by CMD-A, not R1; Rev 2 corrects the routing and reinstates
the `Promise[t]` half of the precedent. Both round-2 questions are answered in the design above:
termination and `:init` by RC-3/RC-4, and `Response`'s provenance by the compiler-supplied decision.

**Convergence worth naming.** Both reviewers concluded independently that the effect machinery was
started and stopped, from different reading paths (language-team from `CommandResult` reserved in the
§10a event-log triple plus `EDo` marked "limited"; professor from `DoStep` binding state and
`emitDo` dropping writers). The archived design refines both: `do` was **settled as deliberately
non-monadic and then mis-implemented**, so the "unfinished" reading is correct of `Command` and wrong
of `do`.
