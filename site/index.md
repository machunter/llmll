---
layout: default
---

# LLMLL: AI agents fill function bodies; a verifier checks their contracts

LLMLL is a programming language built for AI agents to write. Every function has a contract: a
precondition and a postcondition the code must satisfy. An agent fills in the body, and
`llmll verify` hands the body and its contract to an SMT solver. If the solver cannot prove the
body meets the contract, the body is rejected, and the error names the branch that fails.

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

- **The TLS model is arithmetic.** What it covers is the control flow and bounds of the record
  layer: every value is an integer, and no hash, MAC or cipher is computed. This is not a
  verified TLS implementation.
- **The solver reasons about lengths, sequence numbers and states**, not about arbitrary heap
  structure.
- **People own the specifications.** No person wrote the flagship's LLMLL: an authoring agent
  wrote its contracts at our direction, and fill agents wrote the bodies. Whether a contract
  says the right thing is checked by a human reviewer, not by the compiler.
- **A verified contract is met. That does not make it the right contract.** The one automated
  check on contract quality, the vacuity gate in [Post 4](blog/post-4-who-writes-the-decomposition.md),
  runs only on sub-contracts that agents invent during decomposition. It rejects a contract
  that a trivial body (identity, a constant, a projection) already satisfies. It does not
  establish that a contract is adequate.
- **The verdict trusts its tools**: LLMLL's translation to solver constraints, liquid-fixpoint,
  Z3, the Haskell code generator and GHC.

[Post 5](blog/post-5-the-payoff.md) states the full scope.

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

4. **[Who writes the decomposition?](blog/post-4-who-writes-the-decomposition.md)**
   Splitting a contract into sub-contracts one step at a time, and the gate that stops a
   sub-contract which demands nothing.

5. **[163 agent-written functions, verified against their contracts](blog/post-5-the-payoff.md)**
   An arithmetic model of the TLS record layer's control flow and bounds: who wrote what, and
   exactly where the guarantee stops.

## Try to break it

Weaken a contract, or write a body that should fail, and report what the verifier accepts.
A wrong body that verifies is the most useful bug report this project can get:
[open an issue](https://github.com/machunter/llmll/issues).

## The code

Every command in the posts runs against the repository.

- [github.com/machunter/llmll](https://github.com/machunter/llmll)
- goto-fail: [`examples/gotofail/`](https://github.com/machunter/llmll/tree/main/examples/gotofail)
- Heartbleed and the flagship: [`examples/heartbleed/`](https://github.com/machunter/llmll/tree/main/examples/heartbleed)
- agents inventing the decomposition: [`examples/secure-channel-emergent/`](https://github.com/machunter/llmll/tree/main/examples/secure-channel-emergent)
