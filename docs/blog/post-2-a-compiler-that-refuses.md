# Post 2 — A compiler that refuses

*In [Post 1](post-1-the-bugs-that-looked-correct.md) we set the goal: build a slice of
TLS where a compiler proves the code and agents write it, so goto-fail can't ship. This
post is the smallest working version of that loop — one function, one contract, one agent,
and a compiler that says no to the bug.*

## A hole is a contract

Start with what the agent is *given*. Not a blank file — a function with a specification
and a missing body. In LLMLL that is a `def-shell` with a `?body`:

```lisp
(type Step    (| Continue) (| Abort int))     ;; a stage's status
(type Verdict (| Verified) (| Rejected int))  ;; the outcome

(def-shell finalize [sig: Step payload: int] -> Verdict   ;; sig = signature-check status
  (post (=> (= result Verified) (= sig Continue)))   ;; return Verified ⇒ sig was Continue
  ?body)
```

The `post` is the invariant goto-fail broke, written down: *if the result is `Verified`,
then the signature check `sig` was `Continue`.* The `?body` is the agent's job.

When an agent checks that hole out, here is what it receives (abridged — the full
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

(That `"status": "hole"` matters more than it looks: an early brief presented the
function being filled as an available *filled* function, and a blind agent's answer
was a degenerate call to itself — which type-checks, and even verifies, since a
nonterminating body satisfies any contract vacuously. The brief now marks it as the
hole, and a fill must verify *body-faithful*, so that dodge is closed.)

The contract, the return type, the names in scope, and a lock token. **No worked example,
no hint, no nudge toward the answer.** The agent gets the same thing a careful engineer
would get from a ticket: here is the invariant, here are your materials, write the body.
This matters for what comes next — if the demo fed the agent the answer, the compiler's
verdict would prove nothing.

## The agent writes a body; the compiler judges it

Say the agent returns the correct body — deliver `Verified` only on the `Continue` arm:

```lisp
  (match sig ((Continue) Verified) ((Abort c) (Rejected c)))
```
when the hole is filled as such 
```lisp
(def-shell finalize [sig: Step payload: int] -> Verdict
  (post (=> (= result Verified) (= sig Continue)))   ;; return Verified ⇒ sig was Continue
  (match sig ((Continue) Verified) ((Abort c) (Rejected c))))
```
in the finalize.llmll. We can verify the result
```
$ llmll verify finalize.llmll
   body-faithful: finalize
   Running liquid-fixpoint ...
✅ finalize.llmll — SAFE (liquid-fixpoint)
```

`body-faithful` is the phrase that carries the weight: the solver did not trust the
contract, it proved the *body* establishes it. The one path that returns `Verified` is the
one where `sig` was `Continue`.

Now say the agent makes the goto-fail mistake — returns `Verified` no matter what `sig`
was, the way the real code returned `err = 0` on every path:

```lisp
(match sig ((Continue) Verified) ((Abort c) Verified))   ;; Abort arm returns Verified too
```

```
$ llmll verify finalize-bad.llmll
   body-faithful: finalize
   Running liquid-fixpoint ...
error: body verification of 'finalize' failed (else-branch does not satisfy postcondition) (constraint #1)
```

**Refused** — and the solver names the branch: the `Abort` arm. It found the exact input
the real bug shipped on (`sig = Abort`, `result = Verified`) and reported that it violates
the contract. This is not a lint warning you can turn off or a test case someone forgot to
add. The postcondition makes the body that skips the check the one body that does *not*
pass.

## What just happened

That is the whole loop, in miniature:

1. A specification exists as something the compiler enforces, not as a comment.
2. An agent, given only that specification, writes a body.
3. The compiler proves the body meets the spec — or refuses it and points at the flaw.

The agent proposes; the compiler disposes. Neither half is new on its own. The
combination is a way to let something fast and fallible write code, and still get a
result you can stand behind — because the fast, fallible thing does not get the last word.

The obvious objection is that `finalize` is one small function, and real protocols are
thousands of them calling each other. That is exactly right, and it is
[Post 3](post-3-composition-and-the-missing-bound.md): what happens to the guarantee when
one function's correctness depends on another's — which is where the *other* famous bug,
Heartbleed, lived.
