---
layout: default
---

# LLMLL: AI agents fill function bodies; a verifier checks their contracts

LLMLL is a programming language built for AI agents to write. Every function has a contract: a
precondition and a postcondition the code must satisfy. An agent fills in the body, and
`llmll verify` hands the body and its contract to an SMT solver. If the body breaks the
contract, verification fails, and the error names the branch that fails. If the body uses a
construct the solver does not handle, the postcondition is assumed rather than proved and
`verify` names the function. The agent loop in these examples runs with `--require-proof`,
which rejects those bodies too.

Three ways in:

- **[See a rejected bug](#a-rejected-bug)**: a plausible wrong body and the verifier's verdict on it.
  [The demonstration](demo.md) runs the whole loop, from checkout to rejection to the fix.
- **[Run the demo](#run-it)**: one Docker command.
- **[Read the series](#the-series)**: five posts, from one function to 163.

## A rejected bug

In 2014, two bugs broke the encryption most of the web relied on. goto-fail reported a TLS
handshake as successful on a path where the signature check never ran. Heartbleed copied as
many bytes as the peer asked for, without checking that many existed. Both passed review and
tests. One is about whether a check executes, the other about whether a length is bounded, and
both can be written as contracts.

<p><img src="assets/gotofail.gif" width="760" alt="A goto-fail hole is checked out, a fill that returns Verified on every path is rejected and leaves the program unchanged, the guarded fill is accepted, and the program verifies SAFE"></p>

The fills in the recording are scripted stand-ins for agents, so the rejection is reproducible.
[The demonstration](demo.md) walks through it step by step.

Here is goto-fail's invariant as a contract: a function may return `Verified` only when the
check passed.

```lisp
(def-shell finalize [sig: Step payload: int] -> Verdict
  (post (=> (= result Verified) (= sig Continue)))   ;; Verified => the check passed
  (match sig ((Continue) Verified) ((Abort c) (Rejected c))))
```

That body verifies. Now make the goto-fail mistake: return `Verified` on every path.

```lisp
  (match sig ((Continue) Verified) ((Abort c) Verified))
```

```
$ llmll verify finalize-bad.llmll
   body-faithful: finalize
   Running liquid-fixpoint ...
error: body verification of 'finalize' failed
       (else-branch does not satisfy postcondition) (constraint #1)
```

The rejection comes from `verify`, not from `build`. `llmll build` checks types and emits
Haskell, and it compiles the bad body without complaint. The proof is a separate pass, and
the agent loop in this series runs both. [Post 2](blog/post-2-a-compiler-that-refuses.md)
walks through this example in full.

## Run it

You need Docker and nothing else:

```bash
docker run --rm ghcr.io/machunter/llmll verify /opt/llmll/examples/gotofail/finalize-bad.llmll
```

It prints the error above. Swap `finalize-bad` for `finalize` to see the guarded version verify.

## What this does not claim

- **The TLS model is arithmetic**: the record layer's control flow and bounds, with no hash,
  MAC or cipher computed. It is not a verified TLS implementation.
- **A verified body meets its contract. That does not make it the right contract.** Whether a
  contract says what was meant is a person's job.
- **The verdict trusts its tools**: LLMLL's translation to solver constraints, liquid-fixpoint,
  Z3, the Haskell code generator and GHC.

[Post 5](blog/post-5-the-payoff.md#where-the-line-is) states the full scope.

## The series

The five posts read in order, but each one stands on its own.

1. **[The bugs that looked like correct code](blog/post-1-the-bugs-that-looked-correct.md)**
   What goto-fail and Heartbleed have in common, and why reviews, tests, and type-checkers all
   slide past it.

2. **[A compiler that refuses](blog/post-2-a-compiler-that-refuses.md)**
   The smallest working loop: one contract, one agent, and a verifier that rejects the body
   which skips the check.

3. **[Composition, and the bound that wasn't there](blog/post-3-composition-and-the-missing-bound.md)**
   What the guarantee does at a call boundary, and why Heartbleed is a precondition nobody
   discharged.

4. **[Can agents invent the helper functions too?](blog/post-4-who-writes-the-decomposition.md)**
   Agents splitting a contract into helper functions with contracts of their own, and why a
   helper contract cannot quietly weaken the one above it.

5. **[163 agent-written functions, verified against their contracts](blog/post-5-the-payoff.md)**
   An arithmetic model of the TLS record layer's control flow and bounds: who wrote what, and
   exactly where the guarantee stops.

## Try to break it

Two kinds of report are useful, and they show different things:

- **A body that breaks its contract and still verifies.** That is a verifier bug, and the
  most serious kind of report this project can get.
- **A body that meets its contract and is still wrong.** That shows a contract that says
  too little. The `finalize` contract above is one: a body that always returns
  `(Rejected 0)` satisfies it, as [Post 2](blog/post-2-a-compiler-that-refuses.md#what-the-contract-does-not-say)
  shows.

Either way, [open an issue](https://github.com/machunter/llmll/issues).

## The code

Every command in the posts runs against the repository.

- [github.com/machunter/llmll](https://github.com/machunter/llmll)
- goto-fail: [`examples/gotofail/`](https://github.com/machunter/llmll/tree/main/examples/gotofail)
- Heartbleed and the flagship: [`examples/heartbleed/`](https://github.com/machunter/llmll/tree/main/examples/heartbleed)
- agents inventing the decomposition: [`examples/secure-channel-emergent/`](https://github.com/machunter/llmll/tree/main/examples/secure-channel-emergent)
