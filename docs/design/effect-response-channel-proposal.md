---
name: effect-response-channel-proposal
title: "EFFECT-RESP: a response channel, so an LLMLL program can consume the result of its own effects"
status: "Rev 4, SETTLED. EFFECT-RESP (RC-1..RC-4) unchanged from Rev 2. Rev 4 closes the one item Rev 3 deferred: :deterministic true is NOT rejected on wasi.fs.* / wasi.http.*, because LLMLL.md §10a:1652 and §10:1122 define the flag as an opt-in to event-log capture rather than a claim that the effect is a function of its arguments, and §10a:1669-1672 makes it the condition for a replayable module. The flag is instead filed as a third instance of declared-surface-with-no-runtime (with WASI-RT and :read): capDeterministic is parsed and re-emitted, no event log is emitted, and ReplayStatus is never constructed. Rev 4 also moves the :read retirement from commit B to commit C, because removing the read property from DefMain is a JSON-AST schema delta and C already carries the 0.9.0 to 0.10.0 bump. Rev 3: EFFECT-RESP unchanged from Rev 2. DO-ACCUM-1 was reopened (its blast-radius and spec-gap claims were re-measured and refuted) and re-settled as P0-marker by user adjudication 2026-08-02, adding the DISCARD-1 step marker: LLMLL.md §9.6 stands, do-notation-design.md §2.4 is superseded, checkDiscardedCommand is promoted from warning to error. Rev 2: two professor rounds folded; Rev 0's Result-returning read withdrawn; RESUME-1 promoted to the design; CMD-A recorded as target."
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
| corpus effect census | 40 `wasi.io.stdout`, 2 `wasi.fs.write`, **1** `wasi.fs.read` (in `tools/llmll-driver/shell.llmll:46`, which returns the `Command` unconsumed). Every runnable example is `:mode console`. |

### Prerequisite found late: four of the seven `wasi.*` builtins have no runtime

Surfaced by the compiler engineer mid-plan and confirmed empirically here. `builtinEnv`
(`TypeCheck.hs:154-161`) declares seven `wasi.*` names. The codegen preamble
(`CodegenHs.hs:394-409`) defines **three**: `wasi_io_stdout`, `wasi_io_stderr`,
`wasi_http_response`. Missing: **`wasi.fs.read`, `wasi.fs.write`, `wasi.fs.delete`,
`wasi.http.post`**. `CodegenHs.hs:75` labels the whole `wasi.*` import class "stdlib preamble
handles it", which is true for three names out of seven.

Measured at v0.14.78 on a three-line module whose body is `(wasi.fs.read p)`:

```
llmll check  →  ✅ OK (2 statements)
llmll build  →  Lib.hs:240:4: error: [GHC-88464]
                  Variable not in scope: wasi_fs_read :: String -> IO ()
```

So the failure is not a type error, a capability error, or a verification refusal. It typechecks
clean and dies at GHC. The `check`-versus-`build` split is the same seam `IFACE-CONFORM` already
names for FFI (row **IFACE-CONFORM** in `docs/compiler-team-roadmap.md`), reached here without any FFI declaration.

**This is a hard prerequisite of EFFECT-RESP, not a parallel concern.** RC-1 delivers one response
per *performed* command, and the motivating command, `wasi.fs.read`, cannot be performed at all
today. A response channel wired to a builtin with no runtime would be untestable end to end. The
engineer should treat "give the four missing builtins a preamble definition" as Phase 1 step zero,
and it should carry its own roadmap row rather than hiding inside EFFECT-RESP's scope.

**Why it survived: nothing in the tree ever builds.** Measured by the engineer, `grep -rn 'llmll
build'` across `scripts/`, `.github/`, `compiler/test/`, `tools/`, and `Makefile` returns three hits
and all three are comments or doc-claim prose; `compiler/test/Spec.hs:13974` states outright that
`llmll build`'s own `stack build` self-check never ran. `check-examples.sh` typechecks. So the defect
is **latent, not a red gate**: no CI job would have caught it, and none will catch a regression in
the fix either until something builds. The census claims are confirmed (2 `wasi.fs.write`, 1
`wasi.fs.read`); those programs typecheck and cannot build, and no in-tree path asks them to. There
are zero in-tree `wasi.http.post` and `wasi.fs.delete` call sites.

That absence is the more interesting finding. A build gate over at least one effectful program is
worth a row of its own, because WASI-RT is the second defect in this proposal to live in the
`check`-passes / `build`-fails seam, and the `:step` arity change below will be the third.

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

### Four drifts found on the `do` construct, all compounding

1. The settled design (`docs/archive/do_notation/do-notation-design.md` r6, 2026-04-05, §2.3-§2.4)
   requires codegen to compose every step's command via `seq-commands`. `emitDo`
   (`CodegenHs.hs:741-757`) returns `(finalState, _cmdN)` and drops the rest.
2. `checkDiscardedCommand` (`TypeCheck.hs:1860-1865`) warns instead, with an in-code note deferring
   a hard error to **v0.8** (`:1858-1859`). Shipped is 0.14.78. Both prior cites of this function
   in this proposal and in the roadmap were off; the measured range is the one given here.
3. ~~The same design mandated that its non-monadic framing appear verbatim in `LLMLL.md §9`, and no
   such text exists.~~ **Retracted in Rev 3, refuted by measurement.** `LLMLL.md:1588` is
   `### 9.6 \`do\`-notation State Threading`, twenty-two lines with its own `#### Semantics`
   subsection. The zero-hit grep was an artifact: the heading writes `` `do` ``-notation with the
   backticks *inside* the term, so a literal search for `do-notation` misses it. What §9.6 says is
   worse than absence, and is the finding that replaces this one; see below.

**The real third drift: `LLMLL.md` §9.6 contradicts `do-notation-design.md` §2.4, and the emitter
follows §9.6.** `LLMLL.md:1604` states "the final result is `(lastState, lastCommand)`", which is
exactly what `emitDo` does. `LLMLL.md:1606` then documents the discard as *intended*: "Intermediate
commands are silently discarded by default… In LLMLL `def`/`def-shell`, effects are values, not
statements; sequencing them is the agent's explicit responsibility," and names the intended
direction as tightening "to a warn-or-error." Meanwhile `do-notation-design.md` carries
`Status: Approved — Pending Implementation` and governs "LLMLL v0.3"; it was never implemented.

So `emitDo` is not a regression from a shipped design. It is a partially-implemented v0.3 design
whose divergence was subsequently written into the normative spec as deliberate. The two normative
texts point in opposite directions: §2.4 says *compose*, §9.6 says *discard, and tighten to an
error*.

**Fourth drift, found while checking the line cites: §9.6's escape hatch does not exist.**
`LLMLL.md:1606` says non-final commands are discarded "unless explicitly wrapped in `seq-commands`
(see §9.3) or the future `(discard cmd)` marker." Measured, neither branch is reachable:

- `DoStep (Maybe Name) Expr` (`Syntax.hs:237`) binds **only the state component**;
  `inferDoSteps` does `withEnv [(bindName, si)]` (`TypeCheck.hs:1852-1854`) and never binds the
  command. A later step therefore cannot name an earlier step's `Command`, so it cannot
  `seq-commands` it.
- The `(discard cmd)` marker does not exist in the grammar, `builtinEnv`, or the JSON-AST.
- There is no nullary or no-op `Command` constructor (`TypeCheck.hs:154-161`); every producer takes
  arguments and `seq-commands` is binary, so a step cannot return a "nothing to do" command either.

And `checkDiscardedCommand` fires unconditionally on any non-final step, because `expectPairType`
forces every step to `(S, Command)` so `cmdTy == TCustom "Command"` always holds
(`TypeCheck.hs:1834-1836`, `:1862`). The in-code deferral note is explicit that the hard error was
gated on the missing marker: "Hard error deferred to v0.8 **when (discard expr) provides an explicit
opt-out**" (`:1858-1859`).

**Consequence, and it re-opened the adjudication.** Promoting the warning to an error without first
adding `(discard cmd)` does not mean "the agent writes `seq-commands` explicitly." It means every
`do`-block with more than one step becomes a hard error with no in-language workaround, which
removes multi-step `do` rather than tightening it. The P0-error option was put to the user, and
chosen, on the former description. That description was wrong. The choice was re-put with three
variants and re-settled on **2026-08-02 as P0-marker**: promote the check to an error, but gate it
on the `(discard …)` marker the in-code v0.8 note always intended. Specified below as DISCARD-1.

---

## DISCARD-1: the `discard` step marker

A new surface construct. The feature freeze lifted at v0.11 (the lifted-exclusions note under `docs/compiler-team-roadmap.md` §"What's NOT on this Roadmap (and why)")
names "new syntax constructs" among the lifted exclusions, subject to the normal pipeline with a
written soundness argument; that argument is at the end of this section.

### Surface

The marker attaches to the **step**, not to the command value. This is forced, not stylistic: a step
expression is frequently a call, as in the two-step witness above, and a call's `Command` component
is not syntactically reachable. There is nowhere to put a marker on the value. The binding site is
always syntactically present, and the discard is a property of the binding position anyway.

```lisp
(do
  [s1 <- (step-a s0) :discard]     ; non-final, command dropped, acknowledged
  [s2 <- (step-b s1) :discard]     ; non-final, likewise
  (step-c s2))                     ; final, command is the block's result, no marker
```

Anonymous non-final steps take the `_` binder rather than a bare expression, so the marker has a
bracket to sit in:

```lisp
(do
  [_ <- (log-it s0) :discard]
  (step-c s0))
```

JSON-AST: the `do-step` node gains an optional boolean.

```json
{ "kind": "do-step", "name": "s1", "discard": true, "expr": { … } }
```

`discard` defaults to `false` when absent, so every existing document parses. **Schema bump
recommended, 0.9.0 to 0.10.0.** The shipped schema is 0.9.0 (`docs/llmll-ast.schema.json:18`
`"const": "0.9.0"`, whose `$id` URI is versioned `v0.9`, and
`ParserJSON.hs:47 expectedSchemaVersion = "0.9.0"`). An earlier revision of this section said
"0.6.0 to 0.7.0"; that figure was read off `do_emit_ac.ast.json`'s own `schemaVersion` field, which
is stale fixture metadata rather than the schema, and it is retracted.

Two grounds for the bump, the second measured:

1. The field is optional for the *parser* but load-relevant for *legality*: a producer that omits it
   now emits a rejected program, so the contract an agent codes against has changed.
2. The `do-step` node declares `"additionalProperties": false` (`docs/llmll-ast.schema.json:822`)
   with `required: ["kind", "expr"]` and properties `kind` / `expr` / `name` / `state_type` only. So
   `discard` **cannot ride in unversioned**: a document carrying it fails validation against 0.9.0
   outright. This is not a preference about version hygiene; the current schema rejects the field.

**Settled by the engineer's measurement: minor, 0.9.0 to 0.10.0.** All four prior
additive-optional fields took minor bumps (`ParserJSON.hs:41-46`).

**One CI trap this section originally missed.** `scripts/version_gate.sh:76-83` (check C4) derives
`v<major>.<minor>` from `schemaVersion` and fails unless the schema's `$id` URL contains
`/schemas/v<major>.<minor>/`. A bump to 0.10.0 therefore **requires** moving `$id` to
`.../schemas/v0.10/ast.schema.json` in the same commit. Bumping the version constant alone turns the
version gate red.

### Semantics

The marker has **no runtime denotation**. It is a well-formedness annotation. Codegen is unchanged:
`emitDo` still binds `_cmd_i` and drops it, so the generated Haskell, the event log, and §10a replay
determinism are all bit-identical before and after.

Typing, with `n` steps indexed `0..n-1`:

```
Γ ⊢ e : (S, Command)     i < n-1     step_i marked
──────────────────────────────────────────────────────  [DO-DISCARD-OK]
Γ, x:S ⊢ (steps i+1..n-1)

Γ ⊢ e : (S, Command)     i < n-1     step_i unmarked
──────────────────────────────────────────────────────  [DO-DISCARD-ERR]
error "do-step-discards-command" at step i

Γ ⊢ e : (S, Command)     i = n-1     step_i marked
──────────────────────────────────────────────────────  [DO-DISCARD-FINAL]
error "do-discard-on-final-step" at step i
```

`[DO-DISCARD-FINAL]` matters: the final step's command *is* the block's result and is performed, so
marking it is a false claim about the program and is rejected rather than ignored.

`checkDiscardedCommand` (`TypeCheck.hs:1860-1865`) becomes the emitter of the first two rules. Its
current unconditional `when (cmdTy == TCustom "Command")` test stays as the trigger, because
`expectPairType` already forces every step to `(S, Command)`; what changes is that the marker is
consulted before deciding warn-versus-error, and the warning becomes an error. The deferral note at
`:1858-1859` is removed, its condition having been met.

### Edge cases and degenerate inputs

1. **Positive witness, the CI fixture itself.** `scripts/doc-claims/do-notation-discard-warn.llmll`
   is a two-step block with step 0 unmarked and non-final. Under DISCARD-1 it is a hard error via
   `[DO-DISCARD-ERR]`. **Channel: type.** Its `@expect` flips `warn:` to `check-error:` on the same
   pinned substring, so the fixture keeps pinning the same behaviour across the change instead of
   being retired.
2. **Single-step block.** `(do [x <- (step-a n)])`: the only step is final, its command is returned,
   no marker required, behaviour identical to today. **Channel: type**, and this preserves the
   closed decision at `do-notation-design.md:603` ("Single-step `(do expr)` block legal? Closed,
   yes"), which DISCARD-1 must not silently reverse.
3. **Marker on the final step.** Rejected by `[DO-DISCARD-FINAL]`. **Channel: type.** Without this
   rule the marker would be a no-op wherever it was most misleading.
4. **Empty block.** `inferDoSteps [] = pure TUnit` (`TypeCheck.hs:1829`) returns `TUnit`, not
   `(S, Command)`. DISCARD-1 does not touch it, and it is out of scope here, but it is **spec is
   silent (gap, flagged)**: a zero-step `do` typechecks to a type no `def-shell` return position
   accepts, so the failure surfaces later and elsewhere. Filed, not fixed.
5. **A marked step whose command is genuinely wanted.** There is no such case, and that is the point
   of the soundness argument below: the marker asserts a fact about codegen position, not about the
   programmer's intent, and position is checked.

### Verification mapping

| Obligation | Channel | Fragment |
|---|---|---|
| Every non-final `Command`-typed step bind is marked | **type** | Not an SMT obligation. A well-formedness side condition on `EDo`, discharged in `TypeCheck.hs`; it never reaches liquid-fixpoint. |
| The marker is absent on the final step | **type** | As above. |
| `Σ_auto` membership of any `do`-containing body | unchanged | `do` already lands in `def-shell` by the `LLMLL.md:451` rule, so no body-faithful VC is affected either way. |

**One authority-report consequence, named rather than discovered later.** A discarded command is
still *constructed*, so `primEffect` sees its `wasi.*` name and `joinEff` folds that capability into
the enclosing function's effect summary even though the command never runs. The summary therefore
claims authority for an effect that is not performed. This is sound, because B0 is a
may-over-approximation by design, but it is imprecision that lands squarely on the DRIVER-LL
campaign's goal of a non-vacuous authority report. DISCARD-1 deliberately does **not** subtract
discarded effects from the summary: doing so would make the report depend on codegen position, and a
may-analysis that under-reports is worse than one that over-reports. Filed as a known imprecision.

### Soundness argument, as the lifted-freeze policy requires

The marker is erasable. Erasing every `:discard` from a well-typed program changes no generated
Haskell, because codegen already drops non-final commands and the marker emits nothing. So the
construct adds no runtime semantics and cannot change the meaning of any program that currently
runs.

Its only effect is on the accept/reject boundary, and it moves that boundary in one direction per
case. Programs that today warn and silently drop an effect are now **rejected** unless annotated,
which is a strengthening. Programs that carry the annotation are accepted with exactly the behaviour
they have today. No program is newly accepted that was previously rejected.

The marker cannot be used to lie. It asserts "codegen will drop this command," which is a fact about
the step's position in the block, not a claim about programmer intent. Position is checked directly:
`[DO-DISCARD-FINAL]` rejects the marker exactly where the assertion would be false. There is no
input on which a marked step's command is performed.

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

Routed as its own row. Not a prerequisite of EFFECT-RESP's semantics, but it is sequenced first
because it is verifiable in isolation and because RC-2 gives `seq-commands` the meaning any
composing fix would depend on.

**Rev 3 status: RESCOPED and SETTLED as P0-marker** (user adjudication, 2026-08-02; plain P0-error was chosen first, then re-put after the fourth drift below). Rev 2 scoped
this as "conform `emitDo` to `do-notation-design.md` §2.4 and delete `checkDiscardedCommand`." Both
halves rest on claims that re-measurement refutes: the design being conformed to was never
implemented and the spec at HEAD says the opposite, and the warning has a live CI consumer. The
re-measurement and the adjudication are below.

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

**Blast radius, re-measured in Rev 3. Not zero: two artifacts, one of them CI-gated.**

1. `compiler/test/fixtures/pair_type_test/do_emit_ac.ast.json`: a two-step JSON-AST block whose
   step-0 command `(wasi.io.stdout input)` the current emitter drops, so the fixture is itself a
   positive witness. Referenced by no test; `check-examples.sh` sweeps `$EXAMPLES_DIR`, not
   `compiler/test/fixtures/`. Fixing the emitter neither pins nor breaks anything here.
2. `scripts/doc-claims/do-notation-discard-warn.llmll`: a two-step S-expression block shipped at
   v0.14.57 (`3e29beb`) and run on **every CI job** by `scripts/doc_claims_gate.sh`, wired at
   `.github/workflows/version-gate.yml:118`. Its header is
   `@expect: warn:discards this intermediate command` and its `@doc` cites `LLMLL.md §9.6`. Verified
   against the v0.14.78 binary: `llmll check` emits `✅ … OK (2 statements, 1 warning)` plus
   `warning: do-block step 0: current codegen discards this intermediate command.` The gate's `warn`
   branch (`doc_claims_gate.sh:104-111`) requires both `warning:` and that substring, so **deleting
   `checkDiscardedCommand` fails DRIFT-CT-2.**

The retracted "measured zero" claim counted two `(do ` hits in `examples/*/walkthrough.md` that are
English prose ("generated Haskell package (do not edit)"), and missed both real artifacts: an
S-expression-only grep cannot see JSON-AST, and neither `compiler/test/fixtures/` nor
`scripts/doc-claims/` was swept. Reproduce with
`grep -rn --include='*.llmll' -E '\(do($|[[:space:]])'` and
`grep -rl --include='*.json' '"kind"[[:space:]]*:[[:space:]]*"do"'`.

**Consequence for the campaign.** `driver-in-llmll-campaign.md` §Phase 0 carries a STOP condition:
"if any existing program's behaviour changes, the blast-radius measurement was wrong and the phase
pauses for re-measurement." That condition is already met before any code is written, which is the
correct outcome for it: the re-measurement happened here rather than after a broken CI run.

### The adjudication: SETTLED 2026-08-02, P0-marker

Two coherent targets were put to the user first, and **P0-error was chosen**, then re-put as three once the fourth drift showed P0-error had been mis-described; the settled outcome is **P0-marker**, P0-error plus DISCARD-1. All are recorded because the
rejected one is the shape a later reader will expect from `do-notation-design.md`.

**P0-compose, REJECTED.** `emitDo` composes intermediate commands via `seq-commands` per §2.4;
`checkDiscardedCommand` is deleted; `LLMLL.md:1604` and `:1606` are **rewritten**, not merely
augmented; the doc-claim fixture is deleted or re-pointed. Larger change, and it retracts shipped
normative spec text.

**P0-error, CHOSEN FIRST and then amended to P0-marker.** `emitDo` is unchanged; `checkDiscardedCommand` is **promoted from warning to
error**, which is the direction §9.6:1606 already names ("planned to tighten to a warn-or-error").
Silent effect loss becomes impossible; the agent writes `seq-commands` explicitly. §9.6 needs one
sentence changed, `do-notation-design.md` §2.4 is formally superseded, and the doc-claim fixture's
`@expect` flips `warn:` to `check-error:` with the same pinned substring. Smaller change, consistent
with the shipped spec.

**Ground for the choice**, specific to this proposal rather than to change size. Under RC-2,
`(seq-commands c1 c2)` yields `c2`'s response and discards `c1`'s. If `do`
auto-composes via `seq-commands` (P0-compose), then every non-final step's response in a `do`-block
is discarded by construction, so a `do`-block can never consume the result of an intermediate
effect. That is precisely the shape the driver needs (spawn a process, read its exit code, branch),
and it would be silently unavailable inside the notation that looks built for it. P0-compose buys
back the dropped commands at the cost of making `do` structurally incompatible with the response
channel. P0-error keeps the block from silently dropping effects, at the price of pushing genuinely
effectful sequences out of `do` entirely. (The clause that stood here, "leaves the sequencing
explicit, where the response rule is visible at the `seq-commands` the agent wrote", is **retracted**:
the fourth drift shows no step can write `seq-commands` over an earlier step's command.)

This interaction did not exist when Rev 2 scoped DO-ACCUM-1, because RC-2 was settled in the same
revision. It is the substantive reason to reopen, independent of the measurement errors.

**What P0-marker costs, stated rather than discovered later.** `do` still buys state threading and
not effect sequencing, and a block whose non-final step produces a `Command` is a hard error unless
the step carries `:discard`. There is no in-block recovery: a dropped command cannot be composed
back in, because no step binds an earlier step's `Command`. Code that needs sequenced effects must
leave `do` for nested `let` with explicit pair destructuring. Measured, the migration surface is the
two artifacts named above and no production code. `do-notation-design.md` §2.4's "the programmer never writes `seq-commands` inside a
`do`-block" is retracted; the programmer now always does.

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
   bound to `_cmd0` and dropped. **Channel: contract (warning), with the spec in conflict.** Rev 2
   classified this as "spec is silent (gap)"; that was wrong. `LLMLL.md:1606` documents the discard
   as intended and `checkDiscardedCommand` warns on it, so the behaviour is both specified and
   diagnosed. What is broken is agreement between two normative texts, not coverage: §2.4 mandates
   composition and §9.6 mandates discard. The live pin is
   `scripts/doc-claims/do-notation-discard-warn.llmll`, which asserts the §9.6 side in CI.
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

## Engineer findings folded, Rev 3 and Rev 4

Four items the compiler engineer routed back after planning against Rev 3, each verified here
against the tree before folding.

> **Rev 4 note on reading this section.** The engineer's own hand-off
> (`driver-ll-phase01-implementation-plan.md`, §"Findings routed back to language-team") re-routes
> four items, three of which are **already answered below** and one of which (`:mode console` count)
> reads Rev 2's figure rather than Rev 3's. That plan was written against Rev 3 while this section
> was being added, so the overlap is expected and is not a disagreement. The genuinely open item was
> `:deterministic`, settled at Rev 4 at the end of this section. Anyone reconciling the two documents
> should treat this section as the answer and the plan's routing list as its trigger.

**1. `defMainRead` is dead surface in exactly the slot this proposal fills. Retire it.**
`Syntax.hs:694` declares `defMainRead :: Maybe Expr -- ^ :read (console/cli only)` and it is the
**only** occurrence in `compiler/src/`: parsed, round-tripped, read by no emitter. `:read` was a
response-input channel that got designed and never wired, which is precisely what RC-1 does
properly. **Decision: retire `defMainRead` in the same breaking change as the `:step` arity move.**
Unimplemented surface an agent can write and have silently ignored is the worst failure mode for an
agent-authored language; shipping a second, working input channel beside it guarantees confusion;
and every console program is being migrated anyway, so retiring it is free at the margin. If a
`:read` shorthand is wanted later, re-derive it from the shipped response channel.

**Rev 4 refinement: the retirement belongs in commit C, not commit B.** Rev 3 said "the same
breaking change as the `:step` arity move," which is the engineer's commit B, and the engineer's
documentation hand-off records B as carrying "no JSON-AST schema delta." That is wrong for this
item: `read` is a declared property of `DefMain` in `docs/llmll-ast.schema.json:1028`, under
`"required": ["kind", "mode", "step"]` and `"additionalProperties": false` (`:1001-1002`), so
removing it **is** a schema delta and a breaking one for any document carrying the property. Commit C
already opens the schema for the `discard` node and already takes the `0.9.0` to `0.10.0` bump with
the `$id` co-commit the version gate requires, so putting `:read` there costs one bump instead of
two. Measured population at `f3f3091`: **zero** `.llmll` sources use `:read`, and **zero** of the six
in-tree `def-main` JSON-AST documents carry a `read` property, so the removal breaks nothing in the
corpus and the window between C and B is inert (the field has no emitter, so removing it early
changes no generated program). The retirement is also stronger than "dead": `:read` is parsed
(`Parser.hs:475`), round-tripped (`AstEmit.hs:172`), deliberately skipped in hole analysis
(`HoleAnalysis.hs:224` binds it `_mRead`), and **never type-checked**, since
`checkStatement (SDefMain{..})` (`TypeCheck.hs:1405`) destructures only `defMainStep` and
`defMainDone`. An agent may write `:read` with an ill-typed expression today and `check` says
nothing.

**2. Reject the stdout-capture route for the response payload, explicitly.** The current harness
does `output <- captureStdout cmd` (`CodegenHs.hs:944-950`). If the response payload were sourced
from that capture, `(wasi.io.stdout "x")` and `(wasi.fs.read p)` would be **indistinguishable in the
channel**: a program receiving `RText s` could not tell whether `s` came from a file or from its own
print. That is a strictly larger trust residue than the command-to-response pairing gap this
proposal discloses, and it would be undisclosed. The response must be produced by the harness
*performing* the command while knowing which command it performed, never by scraping the process's
own stdout. This is an RC-1 constraint, not implementation taste.

**3. The `:step` arity change has no `check`-time diagnostic today, and that is the migration's
whole risk.** Verified: `checkStatement (SDefMain {..})` (`TypeCheck.hs:1405-1414`) does
`_ <- inferExpr stepE` and discards the result; the only other `def-main` check is a **warning**
that `:done?` should return bool. So adding a `Response` parameter to `:step` is a breaking change
that `llmll check` reports on **no** program: every console program stays green at `check` and dies
at GHC. **The new arity check is not polish; it is the only diagnostic the migration has, and it
must land in the same commit.** Same `check`/`build` seam as WASI-RT, reached by a second
independent route in one release, which is the argument for the build gate named above.

**4. The migration surface is twelve programs, not five.** Six `.llmll` sources and six `.ast.json`
documents declare `:mode console`; no `cli` or `http` entry point exists in-tree. Risk 1 below is
corrected accordingly.

**Settled at Rev 4: should `:deterministic true` be rejected on `wasi.fs.*` / `wasi.http.*`? No.**
Rev 3 deferred this pending a reading of §10a and gave two candidate readings. The reading is done
and the spec is explicit, so reading (a) holds and reading (b) is refuted by the spec's own text.

`LLMLL.md §10a:1652`: "When `:deterministic true` is set, the runtime **captures the return value**
of every call and appends it to the Event Log. On replay, these calls **read from the log** instead
of invoking the real system call." `§10:1122` says the same in one line: the flag exists "to opt into
event-log capture for replay." The flag therefore makes **no claim about the world**. It does not say
a file read returns the same bytes twice; it requests that the bytes be logged so that replay injects
them rather than re-reading. `§10a:1669-1672`'s Replayability Status table closes it: a module is
`replayable` exactly when **all non-deterministic capabilities** carry `:deterministic true`. The
flag is the opt-in applied to the non-deterministic ones by design.

**Consequence: `(import wasi.fs (capability read :deterministic true))` is well-formed and is what
DRIVER-LL wants.** An auditable campaign run is precisely a run whose file reads and HTTP responses
are captured. A check rejecting the flag on those namespaces would make replayability unreachable for
every effectful program, which inverts §10a. Any such proposal is withdrawn.

**The real gap, reclassified.** The engineer's worry ("a module can declare `:deterministic true` and
assert something false, with nothing to contradict it") is misdiagnosed only in its object. Nothing
false is asserted, but nothing is delivered either: `capDeterministic` is parsed
(`Parser.hs:516`, `ParserJSON.hs:404`) and re-emitted (`AstEmit.hs:433`), and that is its whole life.
`grep 'capability' CodegenHs.hs` returns **zero** hits (engineer plan, Context located), no event log
is emitted, and `ReplayStatus` (`Syntax.hs:871-873`, exported at `:74`) is **never constructed
anywhere in `compiler/src/` or `compiler/app/`**. So `:deterministic true` is declared surface with
no runtime: the same class as WASI-RT's four builtins and the `:read` field retired above, and the
third instance of that class found in this campaign.

**Scope decision: file it, do not fix it here.** The event log is §10a's format, the capture path,
and the replay-injection path, which is a larger surface than the response channel and does not
belong inside EFFECT-RESP. What Phase 1 owes is disclosure, not implementation: a module declaring
`:deterministic true` today receives no capture, and no surface should imply otherwise. Nothing
currently does imply otherwise, because `ReplayStatus` is never computed, so this is a silence rather
than a false claim, and no soundness defect follows. Routed as its own roadmap row.

**Two named test obligations, folded into DISCARD-1's affected surface.** `DoStep` has no derived
JSON instances (both directions hand-written), so `doStepToJson` must **omit** `discard` when false
or `checkout`/`patch` rewrites every unmarked program in the corpus. And `canonicalStep`
(`PBT.hs:668-669`, which pattern-matches the two-field constructor) must **exclude** the marker from
the canonical form, or every do-containing `.verified.json` invalidates on the release. Both are the
`TypeDefEntry` ToJSON/FromJSON asymmetry class that has bitten this project before.

---

## Affected surface

0. `docs/llmll-ast.schema.json:1028` (Rev 4): the `read` property is **removed** from `DefMain`, and
   `compiler/src/LLMLL/Syntax.hs:694`, `Parser.hs:475`, `ParserJSON.hs:471`, `AstEmit.hs:172`, and
   `HoleAnalysis.hs:224` drop the corresponding field. This rides **commit C** with the `0.9.0` to
   `0.10.0` bump, not commit B. Numbered 0 because it is the one affected-surface item that moves
   between commits relative to Rev 3.
1. `compiler/src/LLMLL/CodegenHs.hs:741-757`: `emitDo` **untouched** under the settled P0-marker.
   Listed so the engineer does not open it expecting DO-ACCUM-1 work.
2. `compiler/src/LLMLL/CodegenHs.hs:917-975` — the console harness loop, restructured per RC-1..RC-4.
3. `compiler/src/LLMLL/TypeCheck.hs:154-161` — `Response` in `builtinEnv`; command result mapping.
4. `compiler/src/LLMLL/TypeCheck.hs:1828-1866`: `inferDoSteps`; `checkDiscardedCommand` **promoted
   from warning to error**, gated on the DISCARD-1 marker, and its in-code note deferring the error to v0.8 is removed.
4a. `scripts/doc-claims/do-notation-discard-warn.llmll`: `@expect` flips `warn:` to `check-error:`,
   same pinned substring; `@claim` re-worded from "emits a discard warning" to "is rejected". The
   DRIFT-CT-2 gate (`scripts/doc_claims_gate.sh`, `.github/workflows/version-gate.yml:118`, green at
   14 doc-claims on v0.14.78) must be re-run in the same commit. This artifact was missed by the
   Rev 2 blast-radius measurement.
4b. `compiler/test/fixtures/pair_type_test/do_emit_ac.ast.json`: its step-0 command becomes a hard
   error, so the fixture must be re-shaped or removed. It has no test consumer, so nothing asserts
   against it either way.
5. `compiler/src/LLMLL/TypeCheck.hs` — `def-main` `:step` arity check.
6. `LLMLL.md` §9.6 (`:1588-1609`): the `do` semantics subsection **exists**; Rev 2 said it did not.
   Under the settled P0-marker, `:1604` stands unchanged and `:1606`'s closing sentence ("This is
   planned to tighten to a warn-or-error … the syntactic surface is preserved during the warning
   phase") is replaced by the shipped rule: a non-final step whose `Command` component is not
   wrapped in `seq-commands` is rejected. The paragraph's preceding framing (effects are values,
   sequencing is the agent's responsibility) stands and is now enforced rather than advisory.
   Separately: §13.9 gains RC-2's sentence for `seq-commands`, and a new §9.x carries the response
   channel. Doc-lead's slot, after the engineer ships.
6a. `docs/archive/do_notation/do-notation-design.md`: §2.4 formally superseded. Its `Status:` line
   reads `Approved — Pending Implementation`; doc-lead should mark it superseded-by-§9.6 so the next
   reader does not re-derive DO-ACCUM-1 from it. This is the third time this construct has produced
   a drift finding.
7. Schema: JSON-AST unchanged, **no version bump**.
8. Freeze policy: not applicable, lifted at v0.11 (the lifted-exclusions note under `docs/compiler-team-roadmap.md` §"What's NOT on this Roadmap (and why)", which names
   "new syntax constructs" and "more WASI surface" among the lifted exclusions, subject to the normal
   pipeline with a written soundness argument, supplied here).

---

## Risks and open questions

1. **RESUME-1 changes `def-main` `:step` arity, a breaking change to every console program.**
   Classification: scope. **Twelve** in-tree programs use `:mode console` (six `.llmll`, six `.ast.json`); an earlier count of five was low. Worse, `check` reports nothing on the change (`TypeCheck.hs:1405-1414` discards the `:step` inferred type), so the new arity check is the migration's only diagnostic. Bite: complicates; a migration
   that adds an ignored `r: Response` parameter is mechanical.
2. **Turn granularity becomes control-flow granularity.** Classification: verification-ergonomics. A
   program performing N result-consuming reads needs N turns and a state constructor per resumption
   point; the driver's fifteen stages with per-stage reads become a state machine with a state per
   read. This is the defunctionalized-continuation cost (Reynolds, *Definitional Interpreters*,
   1972). Bite: does not block; it sets the size of `RunState` and the engineer must scope it up
   front rather than discover it at stage E.
3. **DO-ACCUM-1 was mis-scoped as a codegen defect; settled as P0-marker.** Classification:
   spec-drift (two normative texts in direct conflict) / scope. Cite: `LLMLL.md:1604`, `:1606`
   versus `do-notation-design.md` §2.4, the latter carrying `Status: Approved — Pending
   Implementation` for v0.3. Bite: **was blocking Phase 0; now resolved.** Rev 2 called this a
   shipped codegen defect with zero in-tree witnesses; both halves are refuted above. Residual bite:
   `do` after P0-marker buys state threading with acknowledged effect drops, so any future argument for command sequencing in
   the notation must re-open §9.6 rather than cite §2.4.
3a. **Deleting the discard warning breaks a CI gate.** Classification: scope. Cite:
   `scripts/doc-claims/do-notation-discard-warn.llmll`, `scripts/doc_claims_gate.sh:104-111`,
   `.github/workflows/version-gate.yml:118`. Bite: complicates rather than blocks (the fixture is
   one line of header to re-point), but it must be in the same commit, and it refutes "fixing the
   emitter pins nothing and breaks nothing."
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
