# Post 5: 163 agent-written functions, verified against their contracts

*An arithmetic model of the TLS record layer's control flow and bounds. Not a verified TLS
implementation: no hash, MAC or cipher is computed.*

*The [first post](post-1-the-bugs-that-looked-correct.md) asked whether we could build a
model of TLS's record-layer logic where a verifier proves the code and agents write it, so
that a body which reintroduces the bugs that broke TLS does not verify. Posts 2 to 4 built
the parts: a contract an agent fills, composition across call boundaries, and a
decomposition grown one contracted step at a time. This post is the whole thing.*

## 163 functions, verified as one program

The record layer's logic is here as a single program: **163 contracted functions across
seven modules** (record framing, sequence numbers, handshake, key schedule, flow control,
alerts, and the spine that ties them together). It is an arithmetic model: every value is an
integer, and a MAC or signature check appears as its result, not as a computation. What it
captures is the length, sequence and state discipline where both bugs lived.

Agents wrote all 163 bodies. The contracts were not theirs: an authoring agent wrote a
reference implementation at our direction, and the 163 contracts were carved out of it. The
fill agents saw the contracts and never the reference bodies. [Who wrote what](#who-wrote-what)
has the full account.

The whole program is verified at once:

```
$ llmll verify \
    examples/heartbleed/secure-channel/agent-fill/sc-channel-agentfilled.llmll
   body-faithful: …
✅ … — SAFE (liquid-fixpoint)
```

**SAFE**, with every one of the 163 bodies proved against its contract, in about a minute on
a laptop (memory and timing figures are in the note at the end). The functions are not checked in isolation but
*composed*: each stands on its callees' contracts through the assume-guarantee reasoning of
Post 3, so the cross-module invariants (a byte is delivered only if MAC-verified and
sequence-fresh and handshake-connected and length-sound) hold across the whole graph.

## Reintroducing the bugs fails verification

Each mutation below changes one function body in the 163-function program and leaves every
contract exactly as it was. Each is a committed diff, and
[`mutations/run.sh`](https://github.com/machunter/llmll/blob/main/examples/heartbleed/secure-channel/agent-fill/mutations/run.sh)
applies it to a copy and verifies the copy.

**goto-fail.** [`gotofail.diff`](https://github.com/machunter/llmll/blob/main/examples/heartbleed/secure-channel/agent-fill/mutations/gotofail.diff)
makes `deliver-len` return the payload length whether or not the MAC verified:

```diff
-  (if (= mac_ok 1) payload_len 0))
+  payload_len)   ;; MUTATION: deliver unconditionally (goto-fail)
```

```
$ bash examples/heartbleed/secure-channel/agent-fill/mutations/run.sh gotofail
error: body verification of 'deliver-len' failed — implementation does not satisfy
       postcondition (constraint #194)
```

**Heartbleed.** [`heartbleed.diff`](https://github.com/machunter/llmll/blob/main/examples/heartbleed/secure-channel/agent-fill/mutations/heartbleed.diff)
makes `heartbeat-response` echo as many bytes as the peer claims, without checking them
against what arrived:

```diff
-  (if (<= claimed_len received_len) (copy-bytes received_len claimed_len) (copy-bytes received_len 0)))
+  (copy-bytes received_len claimed_len))   ;; MUTATION: echo claimed_len unchecked (Heartbleed)
```

```
$ bash examples/heartbleed/secure-channel/agent-fill/mutations/run.sh heartbleed
error: body verification of 'heartbeat-response' failed — implementation does not satisfy
       postcondition (constraint #275)
error: call-site precondition of 'copy-bytes' not satisfied in 'heartbeat-response' —
       caller does not prove callee's precondition (constraint #276)
```

The second error is the refutation from Post 3, now inside the full program: the copy's
bound is a precondition, and the mutated caller cannot prove it.

What this establishes is specific: the verifier rejects a body that violates the contracts
the program keeps. Editing the contracts is a different matter. Drop the MAC clause from
`deliver-len`'s postcondition, and the unconditional body verifies against what is left. The
failure moves up a level: on v0.33.0, `deliver-checked`, `deliver-window` and `recv-record`
then fail, because their own contracts relied on the promise that was removed. To get `SAFE`
back, the edit has to weaken every contract on the way up to the requirement it was
protecting. So the guarantee is only as good as the contracts at the top, and whether those
say the right thing is a separate question, taken up [below](#where-the-line-is).

Two related checks. In a separate probe, one agent was actively pushed *toward* the bug: its
prompt claimed the MAC check was redundant and asked for the "simplest, most efficient" body.
It still wrote the guarded fill (n = 1; nothing rests on it), and the bait body is refuted
deterministically; [`agent-fill/adversarial/`](https://github.com/machunter/llmll/tree/main/examples/heartbleed/secure-channel/agent-fill/adversarial)
keeps both. In the emergent build from Post 4, the same goto-fail-shaped contract, with no
steering either way, also got the guarded body, and its unconditional-deliver mutation is
refuted too. The verifier and the author are independent checks, and that is why it helps to
have both.

## Who wrote what

No person wrote any of the LLMLL in this series. In this program, **the decomposition was
fixed in advance**: the authoring agent's reference implementation set the 163 functions and
their contracts. **The bodies are the fill agents'**: seven agents each filled one module.
Each saw that module's contracts and the `slice-gate.llmll` composition pattern from Post 3,
and not the reference bodies. Six agents filled the six component modules (150 functions);
the seventh filled the spine (13 functions that compose the others).

The companion build where agents choose the decomposition too is
[`examples/secure-channel-emergent/`](https://github.com/machunter/llmll/tree/main/examples/secure-channel-emergent),
described in [Post 4](post-4-who-writes-the-decomposition.md#what-blind-agents-actually-chose).

| | 163-function program (this post) | 25-function emergent build |
|---|---|---|
| Root contracts, where the invariants live | an authoring agent, at our direction | an authoring agent, at our direction |
| Decomposition into sub-contracts | the authoring agent, carved from its reference implementation | agents, through `refine`, with no reference solution |
| Function bodies | agents, one per module | agents, one fresh agent per hole |
| Checking each body against its contract | compiler and solver | compiler and solver |
| Whether the contracts say the right thing | a human reviewer; the compiler cannot check it | a human reviewer; the compiler cannot check it |

The emergent build is the evidence that agents can choose a decomposition; this one shows the
verification holding at 163 functions.

## Where the line is

A verification result is only worth what its scope statement says, so here is the scope,
precisely.

- **Cryptography is not modeled.** The program computes no hash, MAC, encryption or
  signature; a check's outcome enters as an integer. What is proven is the length,
  ordering, and state-machine discipline of the protocol, the layer where these bugs
  actually lived. The real Apple and Heartbleed fixes were control-flow and bounds fixes,
  not math fixes, for the same reason.
- **The data the solver reasons about is arithmetic and length, not arbitrary structure.**
  Buffers and messages are reasoned about through their lengths and orderings; in this
  program every value is an integer. The approach does not prove properties of rich heap
  data structures.
- **No proof here depends on termination.** `verify` prints `✅` only when no function's
  proof assumes that a recursion terminates, and this program gets it. How LLMLL handles
  recursion in general, proved total with a `(decreases …)` measure and flagged partial
  without one, is in [the language reference](https://github.com/machunter/llmll/blob/main/LLMLL.md).
- **The compiler proves a contract is met, not that it is the *right* contract.** This is
  the deepest limit, and the open one. A specification that is precise, satisfiable, and
  wrong is the failure mode no solver closes. The vacuity gate of Post 4 removes the
  emptiest version of it, and only for sub-contracts agents invent through `refine`: it
  rejects a contract that a trivial body (identity, a constant, a projection) already
  satisfies. This program's 163 contracts were carved from a reference implementation and
  did not pass through it. Human judgment owns the rest.
- **The proof is about the LLMLL program, and it trusts its tools.** `verify` generates its
  proof obligations from the LLMLL source. To run the program, the compiler generates
  Haskell and GHC compiles it; that output is not verified separately. It is trusted to
  behave as the LLMLL semantics say. So a `SAFE` result trusts LLMLL's translation of the
  program into solver constraints, the solver itself (liquid-fixpoint and Z3), the Haskell
  code generator and GHC. It does not trust the agents.

## The point

We started with two mistakes, a duplicated line and a missing comparison, that passed review,
tests and the compiler, and shipped into the encryption everyone depends on. The bet of this
series was that the answer to code that *looks* correct, whether a person or a machine wrote
it, is a checker that can *refuse* it, and that this is what lets you put agents on the
keyboard for code that matters. The record-layer model is that bet, paid off: agents wrote
its bodies, the verifier proved each one against its contract, and putting either bug back
fails verification.

*Reproducibility. The fill agents were Claude subagents run from Claude Code; the July 2026
run did not record which model version they used. The programs in this series were written
against `llmll 0.14.67` and re-checked on v0.28.0 with the same verdicts; the 163-function
program was re-checked again on v0.33.0, still `SAFE`. On v0.33.0 the 163-function verify took 54 seconds with a peak of 8.0 GB resident memory on a
laptop; on v0.28.0 it took about a minute and 5.1 GB on a lightly loaded laptop, and about
three minutes on one busy with other work. The two mutation verdicts above were produced on
v0.33.0. goto-fail lives in
[`examples/gotofail/`](https://github.com/machunter/llmll/tree/main/examples/gotofail), Heartbleed and
the 163-function program in [`examples/heartbleed/`](https://github.com/machunter/llmll/tree/main/examples/heartbleed),
cascading refinement in [`examples/refine-demo/`](https://github.com/machunter/llmll/tree/main/examples/refine-demo),
and the emergent build in
[`examples/secure-channel-emergent/`](https://github.com/machunter/llmll/tree/main/examples/secure-channel-emergent).*
