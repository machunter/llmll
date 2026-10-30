# Post 2: A compiler that refuses

*In [Post 1](post-1-the-bugs-that-looked-correct.md) we set the goal: build a model of
TLS's record-layer logic where a verifier proves the code and agents write it, so goto-fail
can't ship. This
post is the smallest working version of that loop: one function, one contract, one agent,
and a compiler that says no to the bug.*

## A hole is a contract

Start with what the agent is *given*. Not a blank file: a function with a specification
and a missing body. In LLMLL that is a `def-shell` with a `?body`:

```lisp
(type Step    (| Continue) (| Abort int))     ;; a stage's status
(type Verdict (| Verified) (| Rejected int))  ;; the outcome

;; sig = the signature-check status
(def-shell finalize [sig: Step payload: int] -> Verdict
  ;; return Verified ⇒ sig was Continue
  (post (=> (= result Verified) (= sig Continue)))
  ?body)
```

The `post` is the invariant goto-fail broke, written down: *if the result is `Verified`,
then the signature check `sig` was `Continue`.* The `?body` is the agent's job.

When an agent checks that hole out, here is what it receives (abridged; the full
brief also lists the remaining constructors, the type definitions, and staleness
hashes; nothing in it is a hint):

```json
{
  "pointer": "/statements/2/body",
  "expected_return_type": "Verdict",
  "postcondition_goal": "(=> (= result Verified) (= sig Continue))",
  "in_scope": [
    {"name": "sig",      "type": "Step",    "source": "param"},
    {"name": "payload",  "type": "int",     "source": "param"},
    {"name": "Continue", "type": "Step",    "source": "let-binding"},
    {"name": "Verified", "type": "Verdict", "source": "let-binding"}
  ],
  "available_functions": [
    {"name": "finalize", "status": "hole",
     "post": "(=> (= result Verified) (= sig Continue))", "pre": null}
  ],
  "token": "34a31bd3…"
}
```

The contract, the return type, the names in scope, and a lock token. **No worked example,
no hint, no nudge toward the answer.** The agent gets the same thing a careful engineer
would get from a ticket: here is the invariant, here are your materials, write the body.
The verdict does not depend on that: a body that passes meets its contract wherever the
body came from. What the bare brief protects is the evidence about agents. If the brief
carried the answer, a passing body would show only that the agent could copy it.

## The agent writes a body; the compiler judges it

Say the agent returns the correct body, delivering `Verified` only on the `Continue` arm:

```lisp
  (match sig ((Continue) Verified) ((Abort c) (Rejected c)))
```
when the hole is filled as such
```lisp
(def-shell finalize [sig: Step payload: int] -> Verdict
  ;; return Verified ⇒ sig was Continue
  (post (=> (= result Verified) (= sig Continue)))
  (match sig ((Continue) Verified) ((Abort c) (Rejected c))))
```
Saved as `finalize.llmll`, it verifies:
```
$ llmll verify finalize.llmll
   body-faithful: finalize
   Running liquid-fixpoint ...
✅ finalize.llmll — SAFE (liquid-fixpoint)
```

`body-faithful` is the phrase to notice: the solver did not trust the
contract, it proved the *body* establishes it. The `✅` means every function in the file
that carries a postcondition was proved from its body; when some are only assumed, `verify`
prints `⚠️ … partial` and names them, and when a proof holds only if a recursion terminates,
it prints `⚠️ … proved only if it terminates` and names those. The one path that returns `Verified` is the
one where `sig` was `Continue`.

Note which pass that is. `llmll build` gates on types and then emits Haskell, so it will
compile the broken body below without complaint. The proof is its own command, and the loop
in this series runs both. Everything that follows is the verifier's verdict, not a build
error.

Now say the agent makes the goto-fail mistake and returns `Verified` no matter what `sig`
was, the way the real code returned `err = 0` on every path:

```lisp
;; the Abort arm returns Verified too
(match sig ((Continue) Verified) ((Abort c) Verified))
```

```
$ llmll verify finalize-bad.llmll
   body-faithful: finalize
   Running liquid-fixpoint ...
error: body verification of 'finalize' failed
       (else-branch does not satisfy postcondition) (constraint #1)
```

**Refused**, and the solver points at the branch: the `else` branch, the one that returns
`Verified` when `sig` is `Abort`, which is the input the real bug shipped on. That branch
cannot establish the postcondition, and the compiler says so. This is not a lint warning you can turn off or a test case someone forgot to
add. Any body that can return `Verified` when `sig` is `Abort` fails the same way.

## What the contract does not say

The contract forbids one thing: accepting a failed check. It does not require accepting a
good one. A body that rejects everything satisfies it:

```lisp
(def-shell finalize [sig: Step payload: int] -> Verdict
  (post (=> (= result Verified) (= sig Continue)))
  (Rejected 0))   ;; never returns Verified, so the implication always holds
```

```
$ llmll verify examples/gotofail/finalize-always-reject.llmll
   body-faithful: finalize
   Running liquid-fixpoint ...
✅ examples/gotofail/finalize-always-reject.llmll — SAFE (liquid-fixpoint)
```

That is not a verifier bug. The contract is a safety property, and it holds. A server that
rejects every handshake is safe and useless. To rule it out, the contract has to say more:
with `<=>` in place of `=>`, so that the result is `Verified` *exactly* when `sig` is
`Continue`, the always-reject body fails and the guarded body still verifies. All three files
are in [`examples/gotofail/`](https://github.com/machunter/llmll/tree/main/examples/gotofail).

So a rejection can mean two different things. A body that breaks its contract is what the
verifier catches. A body that meets its contract and is still not what you wanted points
at the contract, and no solver can catch that, because the contract is the only statement
of intent it has. Which contract to write is a decision, and when agents write the
contracts too, it is the decision that matters most. That is the question of
[Post 4](post-4-who-writes-the-decomposition.md).

## A body that calls itself

The brief lists `finalize` among the available functions with `"status": "hole"`. That
matters more than it looks. An early brief listed the function being filled as an ordinary
filled function, and a blind agent answered with a call to itself. That type-checks and even
verifies: the proof of a recursive function assumes it terminates, and a body that never
terminates meets any postcondition vacuously.

The brief now marks the function as the hole, so an agent is not invited to call it. A
self-call that does appear is flagged: the `verify` headline drops the `✅` and prints
`⚠️ … proved only if it terminates` with the function's name, and the trust report marks it
`termination_unverified`. Declaring a `(decreases …)` measure turns the self-call into a hard
failure, because the solver cannot show the measure goes down.

## What just happened

That is the whole loop, in miniature:

1. A specification exists as something the compiler enforces, not as a comment.
2. An agent, given only that specification, writes a body.
3. `verify` proves the body meets the spec, or refuses it and points at the flaw.

The agent proposes; the compiler disposes. Neither half is new on its own. The
combination lets something fast and fallible write the body while the contract stays
enforced, because the fast, fallible thing does not get the last word. How much that is
worth depends on the contract, which a person still has to read.

The obvious objection is that `finalize` is one small function, and real protocols are
thousands of them calling each other. That is exactly right, and it is
[Post 3](post-3-composition-and-the-missing-bound.md): what happens to the guarantee when
one function's correctness depends on another's, which is where the *other* famous bug,
Heartbleed, lived.
