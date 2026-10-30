# Post 4: Can agents invent the helper functions too?

*[Posts 2](post-2-a-compiler-that-refuses.md) and [3](post-3-composition-and-the-missing-bound.md)
showed a contract that refuses a wrong body, and contracts that compose across calls. A
record layer has a hundred-plus contracts, and someone has to write them. Decomposition
means choosing the helper functions and their contracts: which sub-problems exist, and what
each must guarantee. This post asks whether agents can do that part too, one level at a time,
and what stops an agent from inventing helper contracts that make its own job easy.*

## Refining a hole into a narrower tree

The operation is `refine`. Where `patch` fills a leaf, `refine` lets an agent fill a hole
by *calling functions that do not exist yet*, spawning them as new holes with their own
contracts. Applied over and over, it grows a tree of sub-problems from the root down.

Start with the whole problem as one hole. `admit-byte` decides whether a received record
byte may be delivered, returning `true` exactly when the record is authenticated **and**
ordered (MAC matches, handshake connected at state `2`, sequence fresh, length within what
was received). With a `bool` result and `<=>`, the contract reads as that one sentence:

```lisp
(def-shell admit-byte
    [computed: int expected: int hs_state: int
     seq: int last: int claimed: int received: int] -> bool
  (post (<=> result (and (and (= computed expected) (= hs_state 2))
                         (and (> seq last) (<= claimed received)))))
  ?body)
```

Here is the tree this post builds from that one hole:

```
admit-byte                     deliver iff authenticated ∧ ordered
├── authenticated              iff MAC matches ∧ handshake connected
│   ├── mac-matches            iff computed = expected
│   └── handshake-up           iff hs_state = CONNECTED
└── ordered                    iff sequence fresh ∧ length sound
    ├── seq-fresh              iff seq > last
    └── length-sound           iff claimed ≤ received   ← the Heartbleed bound
```

The walkthrough that builds it is scripted: each step is a committed request file in
[`examples/refine-demo/`](https://github.com/machunter/llmll/tree/main/examples/refine-demo),
so you can replay it exactly. It demonstrates the protocol each agent works under, not what
agents choose on their own. That is the blind run, [further down](#what-blind-agents-actually-chose).

Each step is the request one agent would send, written in advance. Step 1 is in the
position of the agent that checks out the root hole, so its brief is the root contract
above, the whole conjunction. Its request fills `admit-byte` with
`(and (authenticated …) (ordered …))` and spawns those two as fresh holes, each carrying a
proposed sub-contract. Every later step is in the position of an agent that checks out one
of those holes, and its brief is that hole's contract only: the brief for `authenticated`
shows `authenticated`'s contract, not the root's and not its sibling's. Step 2 splits
`authenticated` into `mac-matches` and `handshake-up`, and step 3 splits `ordered` into
`seq-fresh` and `length-sound`. The leaves are simple enough to implement directly: each
*is* one comparison, a `bool` returned straight.

Every step verifies against the current frontier's contracts. The open-hole count fans out
as the tree is decomposed, then falls to zero as the leaves are filled. Every intermediate
program is `SAFE` with the open holes' contracts assumed, so `verify` marks it `⚠️ … partial`
and names them; the last step, with no hole left, is the first to earn the `✅`:

| step | the move | open holes |
|:---:|---|:---:|
| 1 | refine `admit-byte`, spawning `authenticated` and `ordered` | 2 |
| 2 | refine `authenticated`, spawning `mac-matches` and `handshake-up` | 3 |
| 3 | refine `ordered`, spawning `seq-fresh` and `length-sound` | 4 |
| 4 | patch `mac-matches` with `(= computed expected)` | 3 |
| 5 | patch `handshake-up` with `(= hs_state 2)` | 2 |
| 6 | patch `seq-fresh` with `(> seq last)` | 1 |
| 7 | patch `length-sound` with `(<= claimed received)` | 0 |

The finished program verifies as one whole: seven functions, zero holes. Its last leaf,
`length-sound`, is the exact bound from Post 3.

## Why a bad decomposition cannot weaken the root

If an agent both proposes a sub-contract and then relies on it, it might seem the unchecked
assumptions have only moved down a level. They have not, because two separate proofs pin each
proposed contract from both sides.

**From above: the parent must still meet its original contract.** When step 1 lands,
`admit-byte` is verified against the root contract it was given, assuming only what the
proposed contracts of `authenticated` and `ordered` promise. Suppose the agent proposes an
`authenticated` that promises too little: "if the checks pass, return `true`", without the
converse. Then `admit-byte` can no longer prove its own `<=>` from it, and the step fails.
A child contract weak enough to be easy is too weak for the parent to use.

**From below: each child must earn its contract.** A spawned function is a hole, and its
contract is assumed only until a body is proved against it. Until every hole is filled, `verify`
reports the program as partial and names the functions whose contracts are still assumed. The
`✅` arrives only when every contract in the tree, the invented ones included, has been proved
from a body. A child contract too strong to implement never gets there.

So the root requirement holds whenever the whole tree verifies: each parent is proved from its
children's contracts, and each child's contract is proved from its body. The root contract is
the anchor, and what the proofs do not check is whether the root says the right thing.

## Gates at the spawn

The two proofs above would eventually catch a bad sub-contract. Three gates catch some of them
earlier, at the moment of the spawn, so a bad decomposition is rejected before anyone builds on
it.

**Feasibility.** A proposed contract that no body could satisfy is rejected, with an input
that shows why. Without this gate, an impossible child would surface only as a hole nobody can
fill. The gate decides integer and boolean contracts with Z3, and outside that fragment it
admits the spawn rather than guessing.

**Vacuity.** The weak `authenticated` from above, `(=> (and …) result)`, is satisfied by a
body that always returns `true`. The gate rejects the spawn:

> refine gate: spawned sub-contract 'authenticated' is vacuous — a trivial
> (identity/constant) body already satisfies it … strengthen the contract

The check is narrow, and it is meant to be. It asks whether any of a fixed set of trivial
bodies (identity, a constant, a projection of an argument) already satisfies the proposed
contract, and if one does, it rejects the spawn. A contract that passes can still say the wrong
thing. A contract that fails is not necessarily empty: one that admits constant `true` may
still rule out many other bodies, and for some sub-problems a constant or a projection is the
correct implementation. The gate is a policy about acceptable decomposition: a spawned helper
must demand more than a trivial body delivers. It is not a theorem about contract quality.

**Scope.** Suppose an agent tries to add a function the fill body never calls. The gate
rejects that too:

> refine: spawned def 'audit-log' is not referenced by the fill body

A `refine` may only introduce sub-functions the decomposition *uses* (fresh names, referenced
by the body, with hole bodies, nothing clobbered), so the operation cannot become a way to
write arbitrary code into the module.

## What blind agents actually chose

The walkthrough is scripted. The experiment is
[`examples/secure-channel-emergent/`](https://github.com/machunter/llmll/tree/main/examples/secure-channel-emergent),
and it was not. An authoring agent wrote seven modules of root contracts, at our direction,
and nothing else was written in advance: no reference solution, no decomposition. Each hole
then went to a fresh agent with every tool disabled, whose entire input was a fixed
[operation manual](https://github.com/machunter/llmll/blob/main/examples/secure-channel-emergent/audit/OPERATION-MANUAL.md)
and that hole's checkout brief. On a rejection, the retry prompt added only the compiler's
error text. Every prompt, reply and verdict is committed under
[`audit/`](https://github.com/machunter/llmll/tree/main/examples/secure-channel-emergent/audit),
one folder per module.

The agents built 25 functions in 25 steps. Once a compiler bug the run exposed was fixed, every
step was accepted on its first attempt, and all seven modules verify. What the agents chose:

- **They mostly did not decompose.** Of 25 steps, 4 were refines and 21 were direct fills.
  Given a contract they could implement outright, agents implemented it, sometimes by
  simplifying it: one filled a four-clause conjunction with a logically equivalent two-clause
  body, and the solver proved the equivalence. Decomposition happened where a contract was
  genuinely wide.
- **One invented the Heartbleed bound.** Asked to fill a wide record-admission contract, an
  agent spawned `len-ok`, which returns `true` exactly when `claimed ≥ 0 ∧ claimed ≤ received`:
  the bound from Post 3, proposed as a sub-contract by an agent that never saw the CVE.
- **They reused each other's helpers.** The agent filling `deliver-count` called
  `claim-in-window`, a helper a different agent had invented for a sibling function.
- **The gates never fired.** Every invented sub-contract was an exact `<=>` or a conditional
  equality, so no spawn was infeasible, vacuous or out of scope. The run shows that agents can
  propose usable helper contracts. It does not show the gates catching an agent, because none
  needed catching.

This is the evidence for the post's question, and it is one run of 25 functions: agents can
choose the sub-problems as well as solve them, when the problem is wide enough to need them.

## Why this is the hard part

Filling a contract is checkable: the compiler proves the body or refuses it, as in Posts 2
and 3. Inventing a *good* contract is the deeper problem, because a bad contract fails
silently: it passes, and tells you nothing. Inside a decomposition the risk is smaller than it
looks, because a parent is proved from its children's contracts and each child from its body,
so a helper contract cannot quietly weaken the root. What remains unchecked is whether the
contracts, the root above all, say what you meant; that is the open frontier, and the
[final post](post-5-the-payoff.md) is precise about it. The gates narrow it at the edges: a
helper no body can meet, or one a trivial body already meets, is refused at the spawn.

## Implementation note: one writer per module

The seven walkthrough steps were applied one after another to a single module. Agents reason
independently, each with only its own hole's brief, but writes to one module are serialized:
the module carries a whole-file compare-and-swap, so when one agent's refine lands, every other
outstanding checkout on that module goes stale and must be taken again. The walkthrough re-takes
its checkout immediately before each step.

For agents that write in parallel, each subtree gets its own module, owned by one agent, and the
modules are assembled through their contracts. The emergent build ran its six component modules
as parallel cascades this way and composed them in an import-linked spine. The 163-function
program in [Post 5](post-5-the-payoff.md) used the same module-per-agent split, though there the
decomposition was written in advance and the agents only filled it.
