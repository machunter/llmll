# Post 3 — Composition, and the bound that wasn't there

*[Post 2](post-2-a-compiler-that-refuses.md) verified one function against its contract. A
record layer is a hundred-plus functions calling each other, and the second famous bug,
Heartbleed, lived precisely in the gap *between* two of them. This post is about what the
guarantee does at a call boundary.*

## Proving functions one at a time

If verifying a 163-function program meant reasoning about all 163 at once, it would not
scale, and it would not survive an agent editing one function next week. So it doesn't
work that way. When function `f` calls function `g`, the compiler does two things: it makes
`f` *prove* `g`'s precondition at the call site, and it lets `f` *assume* `g`'s
postcondition afterward. `g` is verified once, against its own contract; every caller
reasons against that contract, never against `g`'s body.

This is assume-guarantee reasoning, and it is what makes the whole thing composable. It
also means a precondition is a real obligation the *caller* has to discharge, which is
where Heartbleed shows up.

## Heartbleed is a precondition nobody discharged

The memcpy at the heart of Heartbleed reads `n` bytes from a buffer. Reading `n` bytes is
only safe when `n` does not exceed what the buffer holds. Write that down as the
primitive's precondition:

```lisp
(def copy-bytes [src_len: int n: int] -> int
  ;; may copy n bytes only if n ≤ src_len
  (pre  (and (>= n 0) (<= n src_len)))
  (post (= result n))
  n)
```

`(<= n src_len)` is the bound whose absence *was* Heartbleed. Now the responder. It takes
the length the peer *claimed* and the number of bytes that *actually arrived*, and it must
never return more than arrived:

```lisp
(def-shell heartbeat-response [claimed_len: int received_len: int] -> int
  (pre  (and (>= claimed_len 0) (>= received_len 0)))
  ;; never echo more than we received
  (post (<= result received_len))
  (if (<= claimed_len received_len)
      (copy-bytes received_len claimed_len)   ;; checked: claimed ≤ received
      (copy-bytes received_len 0)))
```

```
$ llmll verify heartbleed-safe.llmll
   body-faithful: copy-bytes, heartbeat-response
   call-pre obligations: heartbeat-response
✅ heartbleed-safe.llmll — SAFE (liquid-fixpoint)
```

The `if` is the check that the real code was missing. Because the true branch has already
established `claimed_len ≤ received_len`, the call `(copy-bytes received_len claimed_len)`
can discharge `copy-bytes`' precondition (`claimed_len ≤ received_len = src_len`), and the
responder's own postcondition follows. Verified.

Now write Heartbleed, copying the claimed length with no check, exactly the CVE:

```lisp
(def-shell heartbeat-response [claimed_len: int received_len: int] -> int
  (pre  (and (>= claimed_len 0) (>= received_len 0)))
  (post (<= result received_len))
  (copy-bytes received_len claimed_len))   ;; THE BUG: claimed_len, unchecked
```

```
$ llmll verify heartbleed-bug.llmll --strict-verified-core
error: body verification of 'heartbeat-response' failed
       — implementation does not satisfy postcondition (constraint #1)
error: call-site precondition of 'copy-bytes'
       not satisfied in 'heartbeat-response'
       — caller does not prove callee's precondition (constraint #2)
ERROR: --strict-verified-core: refuted: heartbeat-response
```

**Refused twice over, and the second refusal is the new kind.** Constraint #1 is
goto-fail's class again: the responder's own postcondition fails. Constraint #2 is the
one this post is about: the compiler cannot prove, *at the call site*, that
`claimed_len ≤ received_len`, because it isn't true; the attacker sets `claimed_len`.
goto-fail broke a function's own postcondition; Heartbleed also breaks a *callee's
precondition at a call boundary*. Two of the most consequential bugs in TLS, two
different verification obligations, both unmeetable by the buggy code. The approach is
not a single trick that happens to catch one bug shape.

## The invariant that spans components

Real protocol rules are not one call deep. A record layer should deliver a plaintext byte
only if it was MAC-verified **and** sequence-fresh **and** handshake-connected **and**
length-sound: four separate checks, computed by four separate functions, and *all four*
required. In the `slice-gate` example the delivering function's postcondition is that
four-way conjunction, and it is provable only by threading the four leaf contracts
together:

```
$ llmll verify slice-gate.llmll        # SAFE, all four leaves compose
$ llmll verify slice-gate-bug.llmll    # gate-mac verifies alone,
error: body verification of 'deliver-plaintext' failed   # composition refused
```

The instructive line is the second one: a version where each *leaf* still verifies on its
own, but one is wired into the delivery decision wrong, so the *composition* fails. A
system can be built entirely from individually-correct parts and still be wrong at the
seam. Assume-guarantee is what puts the compiler at every seam.

That is the mechanism that makes scale possible: no function is re-verified when another
changes, each stands on its callees' contracts, and the guarantee holds across the whole
call graph. [Post 4](post-4-who-writes-the-decomposition.md) asks the question that scale
forces: when there are hundreds of these contracts, *who writes them?* And what stops an
agent from inventing a contract that looks like a specification but demands nothing?
