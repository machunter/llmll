# Post 5: A channel that stands where TLS fell

*The [first post](post-1-the-bugs-that-looked-correct.md) asked whether we could build a
model of TLS's record-layer logic where a compiler proves the code and agents write it, so
a body that reintroduces the bugs that broke TLS does not verify. Posts 2 to 4 built the
parts: a contract an agent fills, composition across call boundaries, and a decomposition
grown one contracted step at a time under a gate. This
post is the whole thing.*

## 163 functions, filled by agents, verified as one program

The record layer's logic is here as a single verified program: **163 contracted holes
across seven modules** (record framing, sequence numbers, handshake, key schedule, flow
control, alerts, and the spine that ties them together). It is an arithmetic model: every
value is an integer, and a MAC or signature check appears as its result, not as a
computation. What it captures is the length, sequence and state discipline where both
bugs lived.

To be precise about authorship: no person wrote any of the LLMLL in this series. **The
decomposition was fixed in advance**: an authoring agent, working at our direction, wrote a
reference implementation, and the 163 contracts were carved out of it. **The bodies are the
fill agents'**: seven agents each filled one module. The agents were Claude subagents run from Claude Code;
the July 2026 run did not record which model version they used. Each
agent saw that module's contracts and the `slice-gate.llmll` composition pattern from
Post 3, and not the reference bodies. Six agents filled the six component modules (150
functions); the seventh filled the spine (13 functions that compose the others). The
companion build where agents
invent the decomposition too (Post 4's cascade, run at module scale with an import-linked
spine) is [`examples/secure-channel-emergent/`](https://github.com/machunter/llmll/tree/main/examples/secure-channel-emergent).

| | 163-function flagship (this post) | 25-function emergent build |
|---|---|---|
| Root contracts, where the invariants live | an authoring agent, at our direction | an authoring agent, at our direction |
| Decomposition into sub-contracts | the authoring agent, carved from its reference implementation | agents, through `refine`, with no reference solution |
| Function bodies | agents, one per module | agents, one fresh agent per hole |
| Checking each body against its contract | compiler and solver | compiler and solver |
| Whether the contracts say the right thing | a human reviewer; the compiler cannot check it | a human reviewer; the compiler cannot check it |

The emergent build is the cleaner evidence that agents can invent a decomposition; this
one shows the verification holding at 163 functions.

Then the whole program is verified at once:

```
$ llmll verify \
    examples/heartbleed/secure-channel/agent-fill/sc-channel-agentfilled.llmll
   body-faithful: …
✅ … — SAFE (liquid-fixpoint)

llmll verify   47.98s user   59.5s total
```

**SAFE**, every one of the 163 bodies faithful to its contract, in about a minute on a
laptop, with a peak of about 5 GB of memory. Not 163
functions checked in isolation, but checked *composed*, each standing on its callees'
contracts through the assume-guarantee reasoning of Post 3, so the cross-module invariants
(a byte is delivered only if MAC-verified and sequence-fresh and handshake-connected and
length-sound) hold across the whole graph.

## Reintroducing the bugs fails verification

The guarantee is not a badge the program wears; it is a property the compiler re-checks on
every run. Reintroduce goto-fail, making a finalize-style step report success on a path that
skipped its check, and the whole-program verify turns red at that function. Drop the bound
back out of the heartbeat responder and the call-site precondition fails, exactly as in
Post 3. The invariants that goto-fail and Heartbleed violated are wired into the program's
proof; you cannot edit them away and still get `SAFE`.

Two details from building it. The fills were blind in the sense that matters: no agent
saw a reference body for anything it filled. In a separate probe we went the
other way and actively pushed one agent *toward* the bug: its prompt claimed the MAC check
was redundant and asked for the "simplest, most efficient" body. It still wrote the guarded
fill (n = 1; the claim does not rest on it), and had it taken the bait the compiler refuses
that body deterministically; `agent-fill/adversarial/` keeps both the bait and its
refutation. In the emergent companion build the same goto-fail-shaped contract, with no
steering of either kind, also got the guarded body, and the unconditional-deliver mutation
is refuted there too. The backstop and the author are independent, and that is why
it helps to have both.

## Where the line is

A verification result is only worth what its scope statement says, so here is the scope,
precisely.

- **Cryptography is not modeled.** The program computes no hash, MAC, encryption or
  signature; a check's outcome enters as an integer. What is proven is the length,
  ordering, and state-machine discipline of the protocol, the layer where these bugs
  actually lived. The real Apple
  and Heartbleed fixes were control-flow and bounds fixes, not math fixes, for the same
  reason.
- **The data the solver reasons about is arithmetic and length, not arbitrary structure.**
  Buffers and messages are reasoned about through their lengths and orderings; in this
  program every value is an integer. The approach does not prove properties of rich heap
  data structures.
- **Recursion is total when a measure is given, partial when it isn't.** A recursive
  function that declares a `(decreases …)` measure has termination *proved*: the compiler
  discharges well-foundedness and strict descent at each call site, and the evidence is
  total correctness. Without a measure the contract is proved *if it terminates*, and the
  function carries an explicit `termination_unverified` flag rather than quietly claiming
  the stronger thing. Distributed-decrease and mixed-arity mutual cycles stay partial. The
  record layer's discipline is structural and does not lean on either case.
- **The compiler proves a contract is met and not vacuous, not that it is the *right*
  contract.** This is the deepest limit, and the open one. A specification that is
  precise, satisfiable, and wrong is the failure mode no solver closes; the vacuity gate of
  Post 4 removes the emptiest version of it, and human judgment still owns the rest.
- **The proof is about the generated program, and it trusts its tools.** A `SAFE` result
  trusts LLMLL's translation of the program into solver constraints, the solver itself
  (liquid-fixpoint and Z3), the Haskell code generator and GHC. It does not trust the
  agents.

None of those caveats touch the claim the series set out to demonstrate: a model of TLS's
record-layer logic, with bodies written by agents and proved by a compiler, in which a body
that reintroduces either of the two bugs that broke TLS does not verify.

## The point

We started with two duplicated-line-and-missing-comparison mistakes that passed review,
tests, and the compiler, and shipped into the encryption everyone depends on. The bet of
this series was that the answer to code that *looks* correct, whether human or machine, is a
checker that can *refuse* it, and that this is exactly what lets you put agents on the
keyboard for code that matters. The record layer model is that bet, paid off: agents wrote
its bodies, a compiler proved them, and it stands where TLS fell.

*The programs in this series were written against `llmll 0.14.67` and re-checked on
v0.26.4 with the same verdicts. The "about a minute" above was measured in July 2026; on
v0.26.4, on a laptop busy with other work, the 163-function run took about three minutes and
2.8 GB. goto-fail lives in
`examples/gotofail/`, Heartbleed and the flagship in `examples/heartbleed/`, cascading
refinement in `examples/refine-demo/`, and the emergent build in
`examples/secure-channel-emergent/`.*
