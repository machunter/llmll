---
name: driver-ll-stage-m-agent-contract-proposal
title: "DRIVER-LL stage M: the agent contract sub-phase 4e did not port"
status: "Rev 1, 2026-09-12, SETTLED. Implements the adjudication recorded as Rev 18 of driver-ll-phase4-proposal.md, which the professor concurred with and the user accepted. Sub-phase 4e settled that the checkout brief is the agent's only input; driver-spec section 8 does not say that, and the phase 4 proposal's own section 5 item 1 refutes it before section 8 does. This proposal is the repair, in five items, and it is sub-phase sized. THE DESIGN DECISION THIS DOCUMENT ADDS, which Rev 18 did not settle: stage M CANNOT reuse the sequencer's prompt renderer. Every placeholder in stage-pre-key names an artifact read ONCE per stage before delegating. Stage M's template needs the hole name, the checkout brief and the previous attempt's compiler output, all three of which are per-attempt runtime values the stage loop never sees. So the rendering happens in wave.llmll, per attempt, and the registry keeps only the template basename. NO PROOF OBLIGATION IS INTRODUCED. Every function involved is def-shell. The four proved cores keep their call sites and their contracts, and what changes is what the running program feeds them. NOT A STRUCTURAL HARDENING: wasi.proc.run takes no confinement parameter, so the port reproduces the reference's isolation posture exactly and files the residue as FS-ISOLATION-1."
date: 2026-09-12
author: language-team
consumers: [compiler-engineer, experiment-lead, documentation-lead, user]
---

# Stage M: the agent contract

Program unification job (a2) folded stage M into the sequencer's stage loop at
v0.23.2. The fold was correct and the stage it folded in was not. This proposal
states what stage M owes its agent, and why four of the five items are conformance
rather than ergonomics.

## 1. The defect, and the witness is measured

Run the `wave` sub-command with the argument vector the 2026-09-11 clause 2 campaign
actually used. The agent receives:

```
["--model", "claude-opus-5", "{prompt}", "{out}",
 "wd/h0-a0/brief.json", "wd/h0-a0/body.json"]
```

The placeholders arrive unsubstituted. The committed wrapper at
[`agent-wrapper.sh`](../../experiments/rfc-swarm/runs/rfc826-llmll-2026-09-11/agent-wrapper.sh)
tests its third argument for readability and exits 2 on the literal, before any model
is reached.

**The cause is one list serving two conventions.** Every other delegated stage maps
`ag-args` through `subst-arg`. `fan-cfg` passes `ag-args` raw, and the wave appends its
own two paths.

**This violates the phase 4 proposal's own settled contract**, so no reading of a
target specification is needed to find it. Section 5 item 1 settled `--agent-exe` plus
repeatable `--agent-arg`, **with the placeholders substituted per argument**.

## 2. What the target specification requires

**driver-spec §9** constrains acceptance, removal before retry, budget separation and
finding classification. It says nothing about the agent's inputs.

**driver-spec §8** does, in three parts that matter here.

1. Independence MUST be **structural rather than instructed**.
2. Each agent gets a directory holding **only its declared inputs**, and MUST NOT be
   given a peer's directory, a peer's output, or a worked answer.
3. The driver MUST be able to report any file in an agent's directory **that was not
   among its declared inputs**.
4. Where the agent needs a copy of the subject to check its own work, the copy **MUST
   be the original, unmodified subject**.

**Part 3 settles the term by definition.** An audit clause that compares against *its
declared inputs* makes a declared input a driver-side commitment, not a spec-side
enumeration. A rendered task statement is a declared input because the driver declares
it. Part 2's prohibition list reaches the same conclusion by inference; part 3 is
direct, and it is the reading this project had not used.

## 3. What the port has, and what it lacks

| §8 or reference element | Port at v0.23.2 |
|---|---|
| The checkout brief | present |
| Task statement, output format, acceptance bar | absent |
| The pristine subject copy of §8 part 4 | absent |
| The previous attempt's compiler output | absent |
| The isolation audit of §8 part 3 | absent, filed as `FS-ISOLATION-1` |

**The pristine copy is the sharpest of these.** `FS-COPY-1` in the phase 4 proposal
§14 shipped `wasi.fs.copy` **citing driver-spec §8:336-337**, which is part 4. Sub-phase
4e then used that builtin for its per-attempt backup and restore, and never for the
agent's copy. The mechanism exists and the clause it was built for is unmet.

## 4. The design

### 4.1 Substitute the argument vector

Stage M maps `ag-args` through the same substitution every other delegated stage uses.
`{prompt}` takes the rendered prompt path and `{out}` takes the body path, both
per attempt. The wave stops appending its own two paths.

**The model pin survives, and that is not incidental.** The clause 2 pre-registration
§6.2 checks the pin by reading the argument vector the run recorded. An invocation that
dropped `--model` would break that check for eleven of a campaign's agent sessions.

### 4.2 Render the prompt in the wave, not in the stage loop

**Stage M cannot reuse the sequencer's renderer, and this is the design decision Rev 18
did not settle.** Every placeholder in `stage-pre-key` names an artifact read once per
stage before delegating: `{{provenance}}`, `{{rubric}}`, `{{inventory}}`, `{{scope}}`
and the rest. Stage M's template needs three values the stage loop never sees:

- `{{hole}}`, the function name, known only inside the hole loop
- `{{brief}}`, the checkout brief, re-taken per attempt
- `{{errors}}`, the previous attempt's compiler output

`{{llmll}}` is the exception; the stage loop already substitutes it through
`stage-needs-llmll?`.

So the wave reads the template and renders it per attempt. **The registry keeps only
the basename**, which is what `stage-prompt` holds for every other stage, and
`stage-pre-count` for stage M stays zero because stage M reads no artifact before
delegating.

`stage-prompt` for stage M becomes `stage-M-fill.md`. Its current comment argues that
the row must stay empty. That comment was written at the (a2) fold, it reasons from
cover cell W1, and it is wrong; see §5.

### 4.3 Provision the pristine copy

The agent's directory gets a copy of the **unmodified** subject, which is
`10-roots/roots.llmll` rather than the live tree the wave patches. This is §8 part 4
and it is the clause `FS-COPY-1` shipped for.

**Two provisioning mechanisms, and they are not one.** `stage-provision-ref?` copies
`LLMLL.md` and the AST schema from `--reference-dir`; the reference calls it at stage M
and the port's row is false. The pristine copy comes from the stage's own input and has
no flag. Both are owed; conflating them loses one.

### 4.4 Thread the error channel

The reference sets its error string from each failed attempt and renders it into the
next prompt. The port's `at-next` clears the token and the body and carries only the two
budgets, so **attempt n+1 receives byte-identical input to attempt n**.

`Att` gains one slot for the previous attempt's transcript. The arms that already read
that transcript supply it.

**Why this is not cosmetic.** driver-spec §9 requires two separately counted retry
budgets and makes only an exhausted error budget a finding. With identical input the
error budget samples agent nondeterminism rather than measuring repair. The proved core
`fill.next-error-budget` is unaffected and still correct; what changes is whether the
running program supplies the input that gives the budget meaning. This is the same shape
as the Rev 15 contention finding, where a proved core was right and the port never
produced the distinguishing input.

### 4.5 Add the cover cell that would have caught this

No cell passes `--agent-arg`. Cell W1 asserts a two-argument invocation, which is the
untemplated case and the only one the cover exercises. `driver_ll_cover.py` stopped
selecting stage M at the fold, and the clause 2 run never reached stage M because stage
M was stubbed. **Three gates, and the templated path is outside all three.**

## 5. What cover cell W1 pins, and what it does not

W1's comment reads: *the agent's whole input is the brief path and an output path. A
third argument would be a side channel.*

**The claim is right and the mechanism is wrong.** §8 forbids a peer's directory, a
peer's output and a worked answer. An argument count establishes none of that. Under
this proposal the agent still receives exactly two paths, so W1's assertion survives as
written; what changes is that the first path names a rendered prompt rather than the raw
brief, and the cell's comment must cite §8 instead of an argument count.

## 6. Edge cases

1. **POSITIVE WITNESS, measured rather than constructed.** §1's argument vector. Under
   this proposal the third element is a readable rendered prompt and the wrapper
   proceeds. Channel: **spec is silent (gap)** today, and the §4.5 cover cell after.
2. **An agent that reads the live tree.** Nothing structurally prevents it; the wrapper
   grants `Read`. The reference removes the motive with the pristine copy and discourages
   the act by instruction. The port will do the same and no more. Channel: **trust, and
   the check is deferred** as `FS-ISOLATION-1`.
3. **A template missing from `--prompts-dir`.** Every other delegated stage halts on the
   read. Stage M gains the same condition and the same halt. Channel: contract.
4. **First attempt, no prior error.** The reference renders the literal `(first
   attempt)`. A port rendering an empty string would leave a section header with nothing
   under it. Channel: spec is silent (intentional); the reference's literal is the
   port's obligation.

## 7. Verification mapping

**This proposal introduces no proof obligation.** Every function it touches is
`def-shell`, and a `def-shell` emits no verification condition. Per `LLMLL.md` §5.3.3
nothing enters or leaves QF-LIA, and nothing escapes to Lean.

`fill.fill-accepted`, `fill.next-error-budget`, `fill.is-finding` and
`token.token-during` keep their call sites, their contracts and their refute cruxes.

What changes is **trust**: what the proved cores are fed, and whether §8's isolation
claim has structural support. Neither has a proposition for a prover, which is the
disclosure `wave.llmll`'s header already carries for its four abstraction functions.

## 8. The port does not harden beyond the reference

`wasi.proc.run` takes an executable, an argument vector, a working directory, three
handle paths and a timeout. **It takes no confinement parameter**, and `LLMLL.md`'s
effect summary names it an opaque boundary at the top element, because it runs an
arbitrary program and can reach anything the catalog names and more. The capability
clause bounds the parent and says nothing about the child.

So the port reproduces the reference's posture exactly. Three reasons, in order of
weight: confinement is not expressible today, so choosing it is a language change and
not a port decision; new behaviour must not ride in on a port, which is the rule the
registry applies at stage I and stage O; and a structurally stronger port would diverge
from the oracle in a direction the comparator cannot attribute.

`FS-ISOLATION-1` therefore changes content rather than status. A confining spawn is
recorded as `Q-008` in [`theory-questions.md`](theory-questions.md).

## 9. Affected surface

1. [`registry.llmll`](../../tools/llmll-driver/registry.llmll): `stage-prompt` and
   `stage-provision-ref?` for stage M, and the two comments written at the fold that
   argue the opposite of this proposal.
2. [`wave.llmll`](../../tools/llmll-driver/wave.llmll): render per attempt; provision
   the pristine copy and the reference; widen `Att`; substitute rather than append.
3. [`sequencer.llmll`](../../tools/llmll-driver/sequencer.llmll): `fan-cfg` passes a
   substituted vector and the prompts directory.
4. [`wave_cover.py`](../../scripts/wave_cover.py): the `--agent-arg` cell, and W1's
   comment recited against §8.
5. [`driver-ll-stage-m-fanout-proposal.md`](driver-ll-stage-m-fanout-proposal.md): Rev
   3, withdrawing §3.2 correction B, which kept `stage-prompt` empty.
6. **Not affected:** `compiler/src/LLMLL/`. No compiler change, no builtin, no schema.
   The v0.8.1a to v0.10 freeze lifted at v0.11.

## 10. Risks

1. **The rendered prompt is the agent's whole task statement, so its content now decides
   whether an attempt can succeed, where the brief alone did not.** Classify: scope. The template is the
   reference's and is pinned; the port renders it and does not author it. **Bite:
   complicates**, and it is why §4.2 keeps the basename in the registry.
2. **The error channel widens `Att` and changes retry semantics.** Classify:
   verification-ergonomics. That is the point rather than a side effect. **Bite:
   complicates.**
3. **Two provisioning mechanisms can be conflated into one.** Classify: spec-drift.
   Different sources, different flags, different failure modes. **Bite: complicates.**
4. **`FS-ISOLATION-1` stays open and the disclosure at phase close grows.** Classify:
   scope. **Bite: only matters at phase close**, and the row now carries both halves.

## 11. Acceptance

1. With `--agent-arg` carrying placeholders, stage M's agent receives a readable
   rendered prompt in the slot the wrapper expects, and the model pin survives.
2. The agent's directory holds the rendered prompt, the pristine subject copy, and the
   language reference, and nothing else the driver did not declare.
3. Attempt n+1 receives the previous attempt's compiler output.
4. A cover cell passes `--agent-arg` and fails if the substitution is lost.
5. Cell W1's two-argument assertion still holds, and its comment cites §8.
6. All nine existing wave cover cells pass, all 63 driver cover cells pass, and no
   proved core moves.

Clause 2 stays stopped until 1 through 6 hold. The re-run is then worth its cost, and
not before.
