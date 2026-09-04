---
name: resp-fact-review
title: "RESP-FACT-1 professor review: the match-arm binder does not know which command answered"
status: "Rev 1 review, standalone. Verdict: REJECT the Rev 1 shape. Rev 2 direction given in Recommendation."
date: 2026-08-31
author: professor
consumers: [language-team, user, compiler-engineer]
reviews: docs/design/resp-fact-proposal.md
style: "ASD-STE100 Simplified Technical English."
---

# RESP-FACT-1: professor review of Rev 1

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
