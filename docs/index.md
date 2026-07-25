---
layout: page
title: Writing a verified slice of TLS, with AI agents doing the typing
---

# Writing a verified slice of TLS, with AI agents doing the typing

Two of the most consequential bugs in the web's encryption, goto-fail and Heartbleed, passed
code review, passed their test suites, and compiled without error. Neither defect lives in a
line. One is a path a check does not take; the other is a bound nobody wrote down.

This series takes the layer of TLS where both bugs actually lived and builds it so that a
compiler **proves** each function meets a specification and **AI agents** do the authoring. It
ends with a working slice of the protocol in which those two bug classes cannot be written and
accepted.

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
   Agents inventing their own sub-contracts, and the gate that stops one from inventing a
   contract which demands nothing.

5. **[A channel that stands where TLS fell](blog/post-5-the-payoff.md)**
   163 agent-written functions verified as one program, and a precise statement of where the
   guarantee stops.

## What this does not claim

The series is deliberate about its boundaries, and Post 5 states them in full. In short:
cryptographic primitives are axiomatized rather than proved; the solver reasons about
arithmetic and lengths, not arbitrary heap structure; and the compiler proves that a contract
is met and not vacuous, **not** that it is the right contract. That last one is the open
frontier, and no solver closes it.

## The code

Everything in the series is in the repository, and the commands in the posts are runnable.

- [github.com/machunter/llmll](https://github.com/machunter/llmll)
- goto-fail: [`examples/gotofail/`](https://github.com/machunter/llmll/tree/main/examples/gotofail)
- Heartbleed and the flagship: [`examples/heartbleed/`](https://github.com/machunter/llmll/tree/main/examples/heartbleed)
- agents inventing the decomposition: [`examples/secure-channel-emergent/`](https://github.com/machunter/llmll/tree/main/examples/secure-channel-emergent)
