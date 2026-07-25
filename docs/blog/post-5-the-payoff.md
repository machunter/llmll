# Post 5 — A channel that stands where TLS fell

*The [first post](post-1-the-bugs-that-looked-correct.md) asked whether we could build a
real slice of TLS where a compiler proves the code and agents write it, so the bugs that
broke TLS can't ship. Posts 2–4 built the parts: a contract an agent fills, composition
across call boundaries, and agents inventing their own decomposition under a gate. This
post is the whole thing.*

## 163 functions, written by agents, verified as one program

The record layer — the part of TLS where both goto-fail and Heartbleed lived — is here as
a single verified program: **163 contracted holes across seven modules** (record framing,
sequence numbers, handshake, key schedule, flow control, alerts, and the spine that ties
them together), filled by **orchestrated agents**, each agent receiving only its hole's
contract — the checkout brief from Post 2, and nothing else. To be precise about
authorship: the *decomposition* here was ours — the 163 contracts were carved out of a
reference implementation; the agents' work is the fills. The companion build where agents
invent the decomposition too — Post 4's cascade, run at module scale with an import-linked
spine — is [`examples/secure-channel-emergent/`](https://github.com/machunter/llmll/tree/main/examples/secure-channel-emergent).

Then the whole program is verified at once:

```
$ llmll verify examples/heartbleed/secure-channel/agent-fill/sc-channel-agentfilled.llmll
   body-faithful: …
✅ … — SAFE (liquid-fixpoint)

llmll verify   47.98s user   59.5s total
```

**SAFE**, every one of the 163 bodies faithful to its contract, in about a minute. Not 163
functions checked in isolation — checked *composed*, each standing on its callees'
contracts through the assume-guarantee reasoning of Post 3, so the cross-module invariants
(a byte is delivered only if MAC-verified and sequence-fresh and handshake-connected and
length-sound) hold across the whole graph.

## The bugs cannot come back

The guarantee is not a badge the program wears; it is a property the compiler re-checks on
every run. Reintroduce goto-fail — make a finalize-style step report success on a path that
skipped its check — and the whole-program verify turns red at that function. Drop the bound
back out of the heartbeat responder and the call-site precondition fails, exactly as in
Post 3. The invariants that goto-fail and Heartbleed violated are wired into the program's
proof; you cannot edit them away and still get `SAFE`.

Two details from building it, stated plainly. The fills were blind: each agent saw its
contract and its in-scope names, never a worked answer. In a separate probe we went the
other way and actively pushed one agent *toward* the bug — its prompt claimed the MAC check
was redundant and asked for the "simplest, most efficient" body. It still wrote the guarded
fill (n = 1; the claim does not rest on it), and had it taken the bait the compiler refuses
that body deterministically — `agent-fill/adversarial/` keeps both the bait and its
refutation. In the emergent companion build the same goto-fail-shaped contract, with no
steering of either kind, also got the guarded body — and the unconditional-deliver mutation
is refuted there too. The backstop and the author are independent, which is the entire
point of having both.

On scale: verification here is roughly linear in program size — a synthetic 2,000-function,
10,000-line program verifies in about five seconds — so "163 functions in a minute" is not
a ceiling the approach is straining against. The record layer is a real subsystem, not a
program sized to fit the demo.

## Where the line is

A verification result is only worth what its scope statement says, so here is the scope,
precisely.

- **Cryptographic primitives are axiomatized.** The SHA and AEAD and signature operations
  are opaque contracts; what is proven is the length, ordering, and state-machine
  discipline of the protocol — the layer where these bugs actually lived. The real Apple
  and Heartbleed fixes were control-flow and bounds fixes, not math fixes, for the same
  reason.
- **The data the solver reasons about is arithmetic and length, not arbitrary structure.**
  Buffers and messages are reasoned about through their lengths and orderings; the approach
  does not prove properties of rich heap data structures, and it says so rather than
  pretending the boundary isn't there.
- **Recursion is total when a measure is given, partial when it isn't.** A recursive
  function that declares a `(decreases …)` measure has termination *proved*: the compiler
  discharges well-foundedness and strict descent at each call site, and the evidence is
  total correctness. Without a measure the contract is proved *if it terminates*, and the
  function carries an explicit `termination_unverified` flag rather than quietly claiming
  the stronger thing. Distributed-decrease and mixed-arity mutual cycles stay partial. The
  record layer's discipline is structural and does not lean on either case.
- **The compiler proves a contract is met and not vacuous — not that it is the *right*
  contract.** This is the deepest limit, and the open one. A specification that is
  precise, satisfiable, and wrong is the failure mode no solver closes; the vacuity gate of
  Post 4 removes the emptiest version of it, and human judgment still owns the rest.

None of those caveats touch the claim the series set out to demonstrate: a real slice of
TLS, decomposed and written by agents and proved by a compiler, in which the two bugs that
broke TLS cannot be written and accepted.

## The point

We started with two duplicated-line-and-missing-comparison mistakes that passed review,
tests, and the compiler, and shipped into the encryption everyone depends on. The bet of
this series was that the answer to code that *looks* correct — human or machine — is a
checker that can *refuse* it, and that this is exactly what lets you put agents on the
keyboard for code that matters. The record layer is that bet, paid off: machines wrote it,
a compiler proved it, and it stands where TLS fell.

*The programs in this series run on `llmll 0.14.67`; goto-fail lives in
`examples/gotofail/`, Heartbleed and the flagship in `examples/heartbleed/`, cascading
refinement in `examples/refine-demo/`, and the emergent build in
`examples/secure-channel-emergent/`.*
