---
layout: default
---

# Writing a verified slice of TLS, with AI agents doing the typing

Who doesn't remember goto-fail and Heartbleed, the two bugs that broke the web's encryption in
2014? They both passed code review, passed their test suites, and compiled without error.
Neither defect lives in a line. One is a path a check does not take; the other is a bound nobody
wrote down.

This series takes the TLS logic where both bugs lived and builds it so that a compiler
**proves** each function meets a specification and **AI agents** do the authoring. It ends with
a verified model of the record layer's logic, 163 functions, in which a body that breaks the
invariants those bugs broke does not verify. The model is arithmetic: every value is an
integer, and no hash, MAC or cipher is computed.

The series is five posts and reads in order.

## The series

1. **[The bugs that looked like correct code](blog/post-1-the-bugs-that-looked-correct.md)**
   What goto-fail and Heartbleed have in common, and why reviews, tests, and type-checkers all
   slide past it.

2. **[A compiler that refuses](blog/post-2-a-compiler-that-refuses.md)**
   The smallest working loop: one contract, one agent, and a compiler that rejects the body
   which skips the check.

3. **[Composition, and the bound that wasn't there](blog/post-3-composition-and-the-missing-bound.md)**
   What the guarantee does at a call boundary, and why Heartbleed is a precondition nobody
   discharged.

4. **[Who writes the decomposition?](blog/post-4-who-writes-the-decomposition.md)**
   Splitting a contract into sub-contracts one step at a time, and the gate that stops a
   sub-contract which demands nothing.

5. **[A channel that stands where TLS fell](blog/post-5-the-payoff.md)**
   163 agent-filled functions verified as one program, who wrote what, and a precise
   statement of where the guarantee stops.

## What this does not claim

The series is deliberate about its boundaries, and Post 5 states them in full. In short:
cryptography is not modeled; the model is arithmetic, and the solver reasons about lengths,
sequence numbers and states, not arbitrary heap structure; the contracts in the flagship were
written by us and the bodies by agents; and the compiler proves that a contract
is met and not vacuous, **not** that it is the right contract. That last one is the open
frontier, and no solver closes it.

## Try it

The refusal from Post 2 runs in one command, with nothing to install but Docker:

```bash
docker run --rm ghcr.io/machunter/llmll verify /opt/llmll/examples/gotofail/finalize-bad.llmll
```

It prints `error: body verification of 'finalize' failed (else-branch does not satisfy
postcondition)`. Swap `finalize-bad` for `finalize` to see the guarded version verify.

## The code

Everything in the series is in the repository, and the commands in the posts are runnable.

- [github.com/machunter/llmll](https://github.com/machunter/llmll)
- goto-fail: [`examples/gotofail/`](https://github.com/machunter/llmll/tree/main/examples/gotofail)
- Heartbleed and the flagship: [`examples/heartbleed/`](https://github.com/machunter/llmll/tree/main/examples/heartbleed)
- agents inventing the decomposition: [`examples/secure-channel-emergent/`](https://github.com/machunter/llmll/tree/main/examples/secure-channel-emergent)
