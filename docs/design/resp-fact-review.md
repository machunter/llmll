---
name: resp-fact-review
title: "RESP-FACT-1 professor review, rounds 1 and 2"
status: "Standalone, not folded. Round 1 REJECTED Rev 1. Round 2 ACCEPTS Rev 2's direction and returns five findings; the §5.2 issuing rule must be restated before an engineer reads it."
date: 2026-08-31
author: professor
consumers: [language-team, user, compiler-engineer]
reviews: docs/design/resp-fact-proposal.md
style: "ASD-STE100 Simplified Technical English."
---

# RESP-FACT-1: professor review, rounds 1 and 2

## Restatement

The proposal gives a builtin a way to declare a refinement on the payload of the
`Response` arms it delivers. The fact enters the program as an antecedent on the
**match-arm binder**, not on the `Response` value, so it stays in QF-LIA and does
not name an opaque sum in a clause. The fact's validity is a trust dependency on
codegen rather than a contract discharge.

## Context located

1. `docs/design/resp-fact-proposal.md` §1-§11 - the artifact under review.
2. `LLMLL.md:1770` (§9.7) - **"Arms classify shape, not provenance."** This one
   sentence decides the review.
3. `LLMLL.md:1759-1768` (§9.7 delivery rules) - a step receives the response to
   the command it returned **on the previous turn**; `seq-commands` is
   discard-left.
4. `LLMLL.md:1741-1747` - the arm table. `RCode` is "a numeric outcome" from
   "operations whose result is a status or code". One arm, many producers.
5. `compiler/src/LLMLL/TypeCheck.hs:292-298` - `RCode : TFn [TInt] (TCustom
   "Response")`. The arm accepts any `TInt`.
6. `compiler/src/LLMLL/FixpointEmit.hs:3405-3430` - the `bytes-zero` axiom. Note
   the emission site: `bodyToPredM` matches the syntactic application `EApp
   "bytes-zero" [ELit (LitInt n)]`.
7. `compiler/src/LLMLL/FixpointEmit.hs:3425-3427` - the comment that carries the
   soundness argument: "There is no laundering path into it: `TypeCheck.hs:1216`
   / `:1250` restrict `(bytes-zero)` to the whole body of a def with a literal
   `-> bytes[n]` return."
8. `compiler/src/LLMLL/CodegenHs.hs:521-560` - what codegen actually builds.
   `wasi_http_response code body` passes the program's own `code` through.
   `wasi_fs_read` takes its `RText` payload from the file.
9. `tools/doc-claims/docclaims.llmll:395-506` - the real consumer shape. Seven
   `*-step` functions, each with a `x: Response` parameter, coupled through the
   program's own `Ctl` state.
10. `docs/compiler-team-roadmap.md:102` (`TRUST-AXIOM`) - the granularity
    question is open: per-function or per-artifact, and disclosure-only or
    admission-composing.

## Gaps and hazards

### 1. The provenance premise is false at the chosen seam

**Class: soundness. Effect: blocks. This refutes the Rev 1 shape.**

§4.2 declares the fact table **per builtin**. §4.1 attaches the fact **per arm**,
at a match-arm binder. Those two seams do not agree, because a `Response` does not
record which command produced it. `LLMLL.md:1770` states this as spec: "`RCode`
therefore carries HTTP statuses, process exit codes, and clock readings alike."

The refuting cell is small. Give `wasi.fs.stat` the declared `RCode` fact `{v :
int | v >= 0}`, per §6 item 1. Now take an unrelated program that issues
`wasi.clock.monotonic` and matches the reply. Its `RCode n` binder receives the
same arm. If the emitter attaches the fact by arm, the clock program gets `n >= 0`
with nothing discharging it. **That is `SAFE-ARG`.** It is the exact defect §5
exists to prevent.

§5's table does not catch this, and the reason is instructive. The table asks *who
guarantees the fact* and sorts the answer into three categories. It never asks
*which values the fact is attached to*. A fact can have a real guarantor and still
be attached to values the guarantor never touched. `nullaryEnumArity` is safe
because it reads the **declared type** of the binder, so the fact and the
attachment come from one source. A per-builtin fact has no such property: the
declared type at the seam is `Response`, which is shared.

The delivery model makes local recovery impossible, not merely difficult.
`LLMLL.md:1761-1762` puts the response in the **next** `:step`, as a parameter.
The `def` that returned the `Command` and the `def` that matches the `Response`
are different functions on different turns. `docclaims.llmll:395-506` is the
measured shape: seven step functions, each taking `x: Response`, with the coupling
held in the program's `Ctl` value. No single `def` sees both ends. Recovering
provenance needs interprocedural dataflow over the program's own state machine.
That is not a sibling of `emitParamBind`'s type-level consultation, and §10
describes it as one.

`seq-commands` closes the last route. It is discard-left (`LLMLL.md:1512`,
§9.7), so a composed command yields only the right operand's response. Even inside
one turn, the command-to-response map is structural rather than syntactic.

### 2. §3's analogy to `bytes-zero` does not hold

**Class: soundness. Effect: blocks the trust argument as written.**

§3 says codegen constructs every `Response`, so "a fact about a `Response` payload
rides the identical stamp, for the identical reason". The reason is not identical,
and the difference decides which facts are admissible.

For `bytes-zero`, codegen emits an n-length zero value **from the same annotation
the axiom reads** (`FixpointEmit.hs:3421-3423`). The stamp covers the whole fact.
For a `Response`, codegen writes the **constructor** and the payload arrives from
somewhere else. `wasi_http_response` passes the program's own `code` through
(`CodegenHs.hs:530`). `wasi_fs_read` takes its payload from the file.
`codegen_semantics_version` covers arm construction. It does not cover a property
of a payload that codegen did not compute.

`wasi.fs.stat`'s clamp does qualify, because codegen would apply the clamp. An
`RList` fact usually does not: a claim about listing order or distinctness rests on
OS behaviour. §4.3 admits `RList` length facts with **no criterion** separating the
two cases, and §7 maps every fact to one stamp. A fact resting on the OS would then
be stamped as resting on codegen. That is a mis-citation of the trust channel, and
`LLMLL.md` §5.4 exists to prevent exactly that.

### 3. The precedent's soundness argument is the part §3 did not carry over

**Class: soundness, and method. Effect: blocks.**

`FixpointEmit.hs:3425-3427` says why the shipped axiom is sound: the construct is
**syntactically restricted so the fact cannot reach a value it does not describe**.
`TypeCheck.hs:1216` and `:1250` confine `(bytes-zero)` to the whole body of a def
with a literal `-> bytes[n]` return. §3 quotes the precedent for its *emission
shape* and leaves the restriction behind.

The emission sites also differ in the property that matters. `bytes-zero`'s axiom
fires from `bodyToPredM` on a syntactic application, so the fact is attached **at
the call the body performs**. RESP-FACT-1 attaches a fact to a binder with no call
in scope. Finding 1 is the consequence of that difference.

### 4. §6 omits the degenerate input that refutes the design

**Class: method. Effect: complicates, and it explains how finding 1 survived.**

§6 lists six edge cases. None of them is "the scrutinee came from a different
builtin" or "the scrutinee is a parameter". Item 2 reads "A builtin with no
declared fact. The arm binder gets `FQTrue`." That sentence assumes a binder is
associated with a builtin, which is the premise under review.

This project has already recorded the corrective discipline twice. `MATCH-TERM-EQ-1`
froze a refuting sibling "because a fixture asserting only that the matched form is
SAFE would pass vacuously" (roadmap :71). The three negative controls were the only
cells that caught the `ALIAS-LOWER-1` defect. Rev 2 should write the refuting cell
in finding 1 before it writes anything else.

### 5. §8's coupling recommendation rests on an unsettled design

**Class: scope. Effect: complicates.**

§8 asks to ship coupled with `TRUST-AXIOM`, or to be its first disclosed
population. `TRUST-AXIOM` (roadmap :102) leaves its prerequisite question open:
whether the trust line is per-function or per-artifact, and whether it composes
into `--strict-verified-core` admission or stays disclosure-only.

RESP-FACT-1 cannot be the first population of a mechanism whose granularity is
undecided, and the granularity is not neutral here. A per-artifact line cannot say
**which builtin's** fact a given verdict rests on. That is the same discrimination
finding 1 shows is missing at the seam. So §8 and finding 1 are one question seen
from two sides, and §8 does not say so. Settle the granularity first. It must be
per-function and per-builtin, or the disclosure does not name what a reader needs.

### 6. A scope divergence, named as scope and not as a defect

**Class: scope. Effect: it does not block. I do not recommend the redesign.**

The provenance problem has a standard treatment that the proposal and the roadmap
row do not cite. The Command/Response step machine is a binary session protocol:
the program sends, and the harness replies with the dual. Session types (Honda,
Vasconcelos and Kubo, ESOP 1998; Gay and Vasconcelos, JFP 2010) and parameterised
monads (Atkey, "Parameterised Notions of Computation", JFP 2009) supply the missing
property **by construction**: the continuation type after sending `stat` is the type
that receives `stat`'s reply. Typestate (Strom and Yemini, IEEE TSE 1986) is the
older framing.

LLMLL has rejected provenance in the arm set deliberately. `LLMLL.md:1774` says
"naming an arm after the capability that produced it is not admissible". So a
session-typed redesign is out of scope, and asking for one would ask the project to
give up a settled decision. I cite the literature for one reason: it names the
property Rev 2 must reproduce by other means, and §9.7 already points at where.

The roadmap row's own citations (Vazou et al., ICFP 2014, on Liquid Haskell's
`assume` for primitives; F\*'s `assume val`; Dafny's `{:axiom}`) are the right
family for the *declaration*, and all three share a feature this proposal drops: the
assumption is attached to a **named primitive**, so the caller cites which
assumption it used. An arm is not a primitive. It is a shape shared by many.

## Recommendation

**Reject the Rev 1 shape. Do not send §4.1 to the compiler-engineer.** The
match-arm binder cannot carry a per-builtin fact, and the reason is in the spec
section the proposal cites.

The direction for Rev 2 is already written in `LLMLL.md:1770-1774`: a program that
needs to know which command a response answers "records that in its own state,
where the coupling is visible in the program's type rather than implicit in the
harness". Do not invent a provenance the type does not carry. Make the coupling the
program already records readable by the verifier. Ranked:

1. **Preferred. A projection whose precondition names the program's own state
   tag.** The program holds a state value already (`Ctl`, `docclaims.llmll:260-271`).
   Let the fact become available when the program **proves** it is in the state that
   issued the command. The obligation is then real and discharged by the caller, on
   the effective-precondition channel. That moves the fact into §5's **first**
   category, not its third. This is where `SAFE-ARG`'s correction put the `bytes[n]`
   length (`bytesLenParamPre`, v0.14.76), so the project's settled precedent already
   points here. The cost is that the program writes something. It writes a citable
   proof obligation instead of a runtime guard, and that is the trade to state
   plainly rather than to hide.
2. **Acceptable, and smaller.** A sealed single-command step form. Restrict a
   fact-carrying response to a shape the compiler can check syntactically, where one
   def returns exactly one command and the response it answers is pinned. Follow
   `bytes-zero`'s discipline literally, including the `TypeCheck.hs` restriction.
   Rev 2 must then say plainly that the multi-state driver loop the six ports use
   does **not** qualify, so the delivered value is smaller than Rev 1 claims.
3. **Rejected.** The Rev 1 shape.

Two constraints apply to whichever option lands. First, split the fact table by
what guarantees the payload: codegen-computed facts ride
`codegen_semantics_version`, and OS-supplied facts do not and need their own
disclosure. §4.3 admits `RList` without that split. Second, write the finding 1
refuting cell first: a second builtin delivering the same arm, whose binder must
**not** receive the fact.

§9 of the proposal is correct and stands. `RESP-FACT-1` is a prerequisite of
`FS-STAT-1`, and `FS-STAT-1`'s discharge claim is false at HEAD. This review does
not change that routing. It changes how long the prerequisite will take.

## Open questions for the language-team

1. **Justify the per-builtin fact table against `LLMLL.md:1770`.** Name the
   mechanism that ties a match-arm binder to the builtin whose fact is applied. The
   response reaches a **later** `:step` as a parameter, and `seq-commands` is
   discard-left, so a lexical answer does not exist. If the answer is "the program's
   own state", say which construct the verifier reads and on which channel the
   coupling is discharged.
2. **Specify the criterion separating a codegen-computed payload fact from an
   OS-supplied one.** Say whether the two share `codegen_semantics_version` or need
   separate stamps. §4.3's `RList` admission cannot be implemented until this is
   settled.

---

## Round 2: Rev 2, and the rule that binds a tag to a builtin

Reviewed 2026-09-03, against `docs/design/resp-fact-proposal.md` Rev 2 (`4e7cc93`) at
`llmll 0.16.2`.

### Restatement

Rev 2 withdraws Rev 1 §4.1. The fact is now keyed on a **control tag**, which is an all-nullary
enum parameter the program already carries. A syntactic **issuing rule** (§5.2) binds a tag to one
builtin. A step declares a precondition naming the tag, the caller proves it, and the declared fact
then enters the match-arm binder under that proved equality. The fact moves from the trust channel
to the effective-precondition channel, which is where round 1 asked for it.

### Context located

1. `docs/design/resp-fact-proposal.md` §2 to §16, Rev 2. The document under review.
2. `tools/doc-claims/docclaims.llmll:272-273`, `:369`, `:375`, `:395`, `:407`, `:420`, `:426`,
   `:433`, `:497`. Eight defs **return** `((Rc, Ctl), Command)`. Exactly two expressions **build**
   that pair: `go` at `:273` and `dc-init` at `:497`.
3. `compiler/src/LLMLL/Module.hs:318`, `toExport (STypeDef name body)`. A module exports its type
   definitions. `:248-249` applies a filter only when an `SExport` declaration is present.
4. `compiler/src/LLMLL/TypeCheck.hs:160`. `wasi.http.response` is in `builtinEnv`, so §8's
   admitted witness names a builtin that exists.
5. Cells run for this round at `llmll 0.16.2`. They replicate Rev 2's c20, c21 and c23 exactly:
   the tag precondition gives `body-faithful` and SAFE; deleting it gives `body-faithful` and
   refuted; the parenthesized constructor crashes liquid-fixpoint with "The sort Phase is not
   numeric".
6. `compiler/src/LLMLL/FixpointEmit.hs:2561-2566` and `:968-974`. `admissiblePayload` and the
   `adtKeys` seeding, which decide §2.1's fallback rule. Confirmed.

### Round 1's rebuttals are upheld

Rev 2 argues against round 1 on four points. All four are correct, and this review records that
before it raises new findings.

1. **Round 1's refuting cell cannot be built.** `wasi.fs.stat` is not in `builtinEnv`. The leaked
   fact `v >= 0` is also true of `wasi.clock.monotonic`, whose payload is a `Word64`, so the cell
   would have passed vacuously. The defect round 1 named is real. The cell it offered does not
   display it.
2. **`CMD-A` already records the property.** `effect-response-channel-proposal.md:528-547` and
   `:649-668`. Round 1 cited session types from outside the project and missed the project's own
   row. Rev 2 §5.5 states correctly that it anticipates `CMD-A` rather than substituting for it.
3. **`seq-commands` closes the receiving site only.** Round 1 wrote that it closes the last route.
   At the issuing site the whole command expression is in scope, and `LLMLL.md:1512` makes the
   right operand the producer, so the rule is deterministic there.
4. **The `RList` guarantor split was inverted in round 1.** Order is codegen-determined:
   `CodegenHs.hs:683` emits `RList (sort entries)`. Length and content are the OS half.

A fifth claim was raised between the rounds and is also refuted. A rule stating that a catch-all arm
keeps a match in the body-faithful fragment fails in both directions: c27 has no catch-all and stays
faithful, c28 has one and falls back. The mechanism is `admissiblePayload`, as Rev 2 §2.1 says.

### Gaps and hazards

#### 1. The issuing rule collects sites that the measured consumer does not have

**Classification: specification incompleteness. It blocks implementation of §5.2 as written.**

§5.2 says "Collect every site in the module that builds a `(State, Command)` pair", then requires
that the command component's head is "a builtin name written in the source". In `docclaims.llmll`
exactly two expressions build that pair. One is `go` (`:273`), whose command component is the
parameter `c`. Under rule 2 that site has a computed command, so **every tag binds to nothing**.

§4 shows the coupling as `(go r2 (Probe) (wasi.proc.run ...))` at `:395-405`. That is a **call of**
`go`, not a site that builds a pair. The rule therefore does not read the coupling that §4 spends a
section proving is present. §4's closing sentence, "The coupling is not missing. It is unread",
describes §5.2 as accurately as it describes the compiler today.

The gap is independent of §8's edge case 5. Making `Ctl` all-nullary does not move a single pair out
of `go`. Two repairs exist and Rev 3 must choose one and write it. Either collect at call sites of
functions whose return type is a `(State, Command)` pair, and propagate through their parameters,
which is interprocedural and needs its termination and its cross-module story stated. Or require the
pair to be built literally in the def that returns it, which is a program-side restriction that
every step in the measured consumer currently violates.

This under-binds rather than over-binds, so it is not a soundness defect. It is a delivery defect:
implemented as written, the rule grants no fact to the program Rev 2 was designed from.

#### 2. Rule 3 is not checkable in the module that grants the fact

**Classification: soundness. It blocks, and the repair is small.**

Rule 3 requires that "the control-tag type is declared in the same module as every def that returns
it". A module exports its type definitions (`Module.hs:318`), and the export filter applies only
when an `SExport` declaration is present (`:248-249`). So a second module may import the tag type,
construct the same nullary constructor, and pair it with a different builtin. The module that grants
the fact cannot see that module, so it cannot check rule 3 as stated.

The unsound direction is concrete. Module A binds tag `T` to builtin `B` and grants the fact.
Module B pairs `T` with builtin `C`. A step preconditioned on `T` then receives `C`'s reply while
assuming `B`'s fact. **I did not build the two-module witness**, and Rev 3 should: it is the R-3
cell moved across a module boundary.

The repair is module-local and cheap. Require that the control-tag type is **not exported**, and
check it against the module's own export surface (`meExports`) rather than against a set of defs the
compiler cannot enumerate. State it as a condition on the tag type, not as a condition on other
modules.

#### 3. §8's positive witness names a fact §6 excludes

**Classification: method. It complicates the proposal rather than blocking it.**

§8 edge case 1 offers the witness as `wasi.proc.run` declaring `{v : int | v >= 0}` "as an
OS-determined fact, or `wasi.http.response`" declaring `{v : int | v >= 100}` "as a
program-determined one". §6 admits program-determined and codegen-determined facts and **excludes
OS-determined facts**. §6's own composition rule then classifies `wasi.proc.run`'s `RCode` arm as
OS-determined, because the failure path carries `ExitFailure c`.

So the first half of the positive witness is a fact this proposal does not grant. The witness must
name `wasi.http.response` alone. This matters because the project's standard is that a proposal
carries a witness that actually fires; `adv-spec-weaken-0` records what happens when it does not.

#### 4. §5.1's surface rule is a convention, and breaking it crashes the solver

**Classification: ergonomic. It matters at the point a program first adopts the feature.**

§5.1 instructs the program to write the constructor bare, and §11 explains why. Nothing enforces it.
The type checker accepts `(pre (= p (Serve)))` and liquid-fixpoint then crashes with "The sort Phase
is not numeric", which I reproduced. Rev 2 routes the defect in §16 and states correctly that it
does not block, because the working form exists.

It should still be a check rather than a convention. Rev 2 teaches a surface whose one-token error
mode is a solver crash rather than a diagnostic. Recommend that Rev 3 make the surface restriction a
type-checker rule, so that the feature it introduces cannot be written the crashing way.

#### 5. The delivered value on the current corpus is zero, and three program-side changes stand in the way

**Classification: scope. It is not a defect, and it should reach the roadmap row.**

§10 states two of them: `Ctl` must become an all-nullary enum (edge case 5), and `code-in` must bind
its payload names and reach `RList` through a catch-all (cells c11 and c28). Finding 1 adds a third:
the pairs must be built where the issuing rule can read them. All three land in one file, which is
the good news, but the row should say that `RESP-FACT-1` ships behind a program-side change and not
in front of it.

### Recommendation

**Accept Rev 2's direction. Do not send §5.2 to the compiler-engineer as written.**

The mechanism is measured and it works. A tag precondition is admitted, it discriminates, and the
caller discharges it. That is the property Rev 1 lacked and round 1 asked for, and Rev 2 supplies it
from one source rather than two. The three-way guarantor split in §6 is a real improvement on round
1's two-way split, and the `RList` correction is right.

Rev 3 is a revision and not a redesign. Three changes make it implementable:

1. **Restate the collection rule of §5.2** so that it reads the coupling §4 measures. Name whether
   the rule is interprocedural. If it is, state how it terminates and what it does at a module
   boundary. If it is not, state the program-side restriction plainly and count the cost against the
   measured consumer, which currently builds every pair in one helper.
2. **Restate rule 3 as a condition on the tag type's export**, checkable in the granting module.
   Add the two-module version of cell R-3, and run it.
3. **Correct §8's witness** to the admitted case, and make §5.1's bare-constructor rule a check.

`TRUST-AXIOM`'s granularity is answered well enough to proceed. §12 states the granularity Rev 2
needs, per function and per `(tag, builtin)` pair, rather than asking `TRUST-AXIOM` to choose one.
Round 1's finding 5 is discharged by that.

### Open questions for the language-team

None. Both of round 1's questions are answered in Rev 2, and the five findings above say what to
change rather than what to justify.
