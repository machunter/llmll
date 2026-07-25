# Post 4 — Who writes the decomposition?

*[Posts 2](post-2-a-compiler-that-refuses.md) and [3](post-3-composition-and-the-missing-bound.md)
handed agents contracts and asked them to fill and compose them. A record layer has a
hundred-plus contracts, and someone has to invent them — the sub-problems, and the
specification of each. This post is about agents inventing that structure themselves,
top-down, one level at a time, and what keeps an invented contract from being hollow.*

## Refining a hole into a narrower tree

The operation is `refine`. Where `patch` fills a leaf, `refine` lets an agent fill a hole
by *calling functions that do not exist yet*, spawning them as new holes with their own
contracts. Applied over and over, it grows a tree of sub-problems from the root down.

Start with the whole problem as one hole. `admit-byte` decides whether a received record
byte may be delivered — return `true` exactly when the record is authenticated **and**
ordered (MAC matches, handshake connected at state `2`, sequence fresh, length within what
was received). With a `bool` result and `<=>`, the contract reads as that one sentence:

```lisp
(def-shell admit-byte
    [computed: int expected: int hs_state: int
     seq: int last: int claimed: int received: int] -> bool
  (post (<=> result (and (and (= computed expected) (= hs_state 2))
                         (and (> seq last) (<= claimed received)))))
  ?admit-byte-body)
```

No agent is handed that whole conjunction. The first agent, given only this hole's contract,
splits it into *authenticated* and *ordered* — filling `admit-byte`'s body with
`(and (authenticated …) (ordered …))` and spawning those two as fresh holes, each carrying
the sub-contract it just invented. `admit-byte` then verifies, *assuming* those two contracts.
A second agent takes `authenticated` and splits it into `mac-matches` and `handshake-up`; a
third splits `ordered` into `seq-fresh` and `length-sound` — each agent seeing only its own
hole's brief, never its siblings' work. The leaves are then simple enough to implement
directly: each *is* one comparison, a `bool` returned straight.

Every step verifies against the current frontier's contracts. Starting from the single
`admit-byte` hole, the open-hole count fans out as agents decompose, then contracts to zero
as they fill the leaves — every intermediate program `SAFE`:

| step | the agent's move | open holes |
|:---:|---|:---:|
| 1 | refine `admit-byte`, spawning `authenticated` and `ordered` | 2 |
| 2 | refine `authenticated`, spawning `mac-matches` and `handshake-up` | 3 |
| 3 | refine `ordered`, spawning `seq-fresh` and `length-sound` | 4 |
| 4 | patch `mac-matches` with `(= computed expected)` | 3 |
| 5 | patch `handshake-up` with `(= hs_state 2)` | 2 |
| 6 | patch `seq-fresh` with `(> seq last)` | 1 |
| 7 | patch `length-sound` with `(<= claimed received)` | 0 |

The tree the agents built, none of it authored in advance:

```
admit-byte                     deliver iff authenticated ∧ ordered
├── authenticated              iff MAC matches ∧ handshake connected
│   ├── mac-matches            iff computed = expected
│   └── handshake-up           iff hs_state = CONNECTED
└── ordered                    iff sequence fresh ∧ length sound
    ├── seq-fresh              iff seq > last
    └── length-sound          iff claimed ≤ received     ← the Heartbleed bound, again
```

Each function verifies against the contracts of the children below it, and the finished
program verifies as one whole — seven functions, zero holes. That last leaf, `length-sound`,
is the exact bound from Post 3: Heartbleed reappears at the bottom of a decomposition an agent
invented, and it is proved.

## The failure this opens, and the two gates that close it

If an agent both invents a sub-contract and then relies on it, what stops it from inventing
one that demands nothing? A hole that "verifies" against a contract satisfied by any trivial
body has proved nothing. Two gates guard each spawn.

**Vacuity.** Suppose an agent weakens `authenticated`'s `<=>` to a one-way `(=> (and …) result)`
— "if the checks pass, return `true`," dropping the converse. A constant `true` body satisfies
that (it never has to return `false`), so the sub-goal discriminates nothing — and the refine
gate rejects the spawn:

> refine gate: spawned sub-contract 'authenticated' is vacuous — a trivial
> (identity/constant) body already satisfies it … strengthen the contract

Rejected at the spawn. The gate asks whether a trivial identity, constant, or projection
body would already pass the proposed contract; if so, the sub-goal discriminates nothing
and the decomposition is refused. An agent cannot make progress by breaking a hard problem
into an easy one that means nothing.

**Scope.** Suppose an agent tries to add a function the fill body never calls — the gate
rejects that too:

> refine: spawned def 'audit-log' is not referenced by the fill body

Also rejected. A `refine` may only introduce sub-functions the decomposition *uses* — fresh
names, referenced by the body, with hole bodies, nothing clobbered — so the operation cannot
become a way to write arbitrary code into the module.

## One module, one writer at a time

The seven steps above were applied one after another to a single module, and that is a
property of the module, not a limitation of the agents. The agents *reason* independently —
each has only its hole's brief — but a module carries a whole-file compare-and-swap: the
moment one agent's refine lands, any other outstanding checkout goes stale and must be taken
again. So application to one module is serialized; a checkout is re-taken immediately before
each step.

For agents that write *truly* in parallel, the move is to give each subtree its own module
that one agent owns, then assemble the modules through their contracts. The 163-function
channel in [Post 5](post-5-the-payoff.md) used that module-per-agent split — though there
the *decomposition* was authored up front and the agents filled it. The build where the
modules' internals are grown exactly as in this post — root contracts only, agents
inventing the sub-contracts, an import-linked spine composed across module boundaries —
is [`examples/secure-channel-emergent/`](https://github.com/machunter/llmll/tree/main/examples/secure-channel-emergent):
twenty-five functions, every step gated and verified, the full blind-agent transcript
committed alongside.

## Why this is the hard part

Filling a contract is checkable — the compiler proves the body or refuses it, as in Posts 2
and 3. Inventing a *good* contract is the deeper problem, because a bad contract fails
silently: it passes, and tells you nothing. The vacuity gate is a first, concrete answer —
it catches the decomposition that demanded nothing. It does not certify that an invented
contract is the *right* specification; that remains the open frontier, and the final post is
precise about it. What the gate does buy is real: an agent can grow a tree of its own
sub-problems, and the compiler polices both that every step is proved and that no step was
made easy by hollowing out its goal.
