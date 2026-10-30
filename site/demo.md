# LLMLL: a goto-fail body, rejected before the edit lands

*Burc Sahinoglu · 29 October 2026. A self-contained demonstration. The [five-post
series](index.md) tells the longer story, up to 163 functions.*

LLMLL is a programming language built for AI agents to write. A function starts as a contract,
a precondition and a postcondition, with a typed hole where the body goes. An agent checks the
hole out, proposes a body, and the compiler hands the body and the contract to an SMT solver.
A body the solver cannot prove is rejected before it lands, and the program is left as it was.

This page runs that loop once, on the invariant behind a real bug, and shows every diagnostic it
produces.

<p><img src="assets/gotofail.gif" width="760" alt="A goto-fail hole is checked out, a fill that returns Verified on every path is rejected with a verification error and leaves the program unchanged, the guarded fill is accepted, and the program verifies SAFE"></p>

The two fills in the recording are scripted stand-ins for agents: fixed patch files committed to
the repository, so the rejection is reproducible. Script:
[`examples/gotofail/demo.sh`](https://github.com/machunter/llmll/blob/main/examples/gotofail/demo.sh).

## The contract

In 2014, Apple's goto-fail bug (CVE-2014-1266) reported a TLS handshake as successful on a path
where the signature check never ran. The mistake was about whether a check executes. Written as
a contract, the invariant is: return `Verified` only if the check passed.

```lisp
(type Step    (| Continue) (| Abort int))
(type Verdict (| Verified) (| Rejected int))

(def-shell finalize [sig: Step payload: int] -> Verdict
  (post (=> (= result Verified) (= sig Continue)))   ;; return Verified => sig was Continue
  ?body)
```

`?body` is the hole. An agent asks for it with `llmll checkout`, which locks the hole and returns
a brief: the postcondition, the return type, the names in scope and a lock token. The brief has
no reference body and no hint.

```json
{
  "postcondition_goal": "(=> (= result Verified) (= sig Continue))",
  "expected_return_type": "Verdict"
}
```

## A wrong fill is rejected

Say the agent makes the goto-fail mistake and returns `Verified` on every path:

```lisp
(match sig ((Continue) Verified) ((Abort c) Verified))
```

It submits the body as a JSON-Patch against the program's JSON-AST, with `--require-proof`:

```
$ llmll patch finalize-hole.ast.json wrong.json --require-proof
{
  "diagnostics": [
    {
      "kind": "lh-unsafe",
      "message": "body verification of 'finalize' failed (else-branch does not satisfy postcondition) (constraint #1)",
      "pointer": "patch-op/1",
      "severity": "error"
    }
  ],
  "result": "PatchVerifyError"
}
```

The patch is refused and the file is byte-for-byte unchanged. The diagnostic names the branch
that fails: the `else` branch, the one that returns `Verified` when `sig` is `Abort`. That is
the input the real bug shipped on.

## The guarded fill is accepted

```lisp
(match sig ((Continue) Verified) ((Abort c) (Rejected c)))
```

```
$ llmll patch finalize-hole.ast.json right.json --require-proof
{"result":"PatchSuccess","reuse_suggestions":[],"statements":3,"verification":[{"body_faithful":true,"fn":"finalize"}]}

$ llmll verify finalize-hole.ast.json
   body-faithful: finalize
   Running liquid-fixpoint ...
✅ finalize-hole.ast.json — SAFE (liquid-fixpoint)
```

`body_faithful` means the solver proved the postcondition from the body itself. It did not
assume the contract.

## What the contract leaves open

This contract is a safety property. It forbids returning `Verified` when the check failed,
and it does not require returning `Verified` when the check passed, so a body that always
returns `(Rejected 0)` also verifies. Ruling that out takes a stronger contract, with `<=>`
in place of `=>`. [Post 2](blog/post-2-a-compiler-that-refuses.md#what-the-contract-does-not-say)
runs both versions.

## Which pass rejects it

The rejection comes from the verifier, not from the type checker. `llmll build` checks types and
emits Haskell, and it compiles the wrong body without complaint. The proof runs in `llmll
verify`, and in `llmll patch`, which re-verifies the patched function before writing anything.
With `--require-proof`, a patch is also refused when its function passes only because the
solver fell back to assuming the postcondition.

## What this shows, and what it does not

**Why a language for this, and not a verifier behind an agent tool.** The verifier is not the
new part: Dafny, Liquid Haskell or F\* would reject the same body, and LLMLL's proofs run on
liquid-fixpoint and Z3. What LLMLL adds is the loop around the proof, built into the
toolchain:

- The unit of work is a hole with a contract. `checkout` hands an agent that hole's contract
  and the names in scope as JSON, and locks it.
- `patch` applies the agent's body and verifies it before writing, so a rejected edit leaves
  the program byte-for-byte unchanged, and the lock stays with the agent so it can retry.
- A rejection is JSON with a kind, a message and a pointer into the patch, so a repair loop
  can act on it without parsing compiler text.
- `refine` lets an agent split a hole into helper holes with contracts of their own, while
  the parent stays held to its original contract
  ([Post 4](blog/post-4-who-writes-the-decomposition.md)).

None of this needs a stronger solver. It lets you hand one function at a time to an agent
and take back only bodies that verify, with the rest of the program untouched. How contracts
compose across calls is [Post 3](blog/post-3-composition-and-the-missing-bound.md).

**Scope.**

- As of `llmll` 0.33, the solver covers linear integer arithmetic, booleans, non-recursive
  sums, pairs, fixed-size bytes, maps and string literals, each with restrictions listed in
  [the language reference](https://github.com/machunter/llmll/blob/main/LLMLL.md#533-verification-scope).
  Outside that fragment a postcondition is assumed, `verify` names the function, and
  `--require-proof` refuses the fill.
- A proof shows that the body meets the contract, for every input that satisfies the
  precondition. It does not show that the contract is right. Whether the contract says the
  right thing is a human reviewer's job.
- The example is one function. The series scales it up to an arithmetic model of the TLS record
  layer's control flow and bounds: 163 agent-written functions, verified as one program
  ([Post 5](blog/post-5-the-payoff.md)). That model computes no hash, MAC or cipher, and it is
  not a verified TLS implementation.
- A verdict trusts its tools: LLMLL's translation to solver constraints, liquid-fixpoint, Z3,
  the Haskell code generator and GHC.

## Run it

With Docker and nothing else, see the rejection:

```bash
docker run --rm ghcr.io/machunter/llmll verify /opt/llmll/examples/gotofail/finalize-bad.llmll
```

It prints `error: body verification of 'finalize' failed (else-branch does not satisfy
postcondition)`. Swap `finalize-bad` for `finalize` to see the guarded body verify.

To run the whole checkout-and-patch loop from the recording, build `llmll` from
[the repository](https://github.com/machunter/llmll) and run
`bash examples/gotofail/demo.sh`. It needs `liquid-fixpoint`, `z3` and `jq` on your PATH.

## Try to break it

Two kinds of report are useful, and they show different things:

- **A body that breaks its contract and still verifies.** That is a verifier bug, and the
  most serious kind of report this project can get.
- **A body that meets its contract and is still wrong**, like the always-reject body above.
  That shows a contract that says too little.

Either way, [open an issue](https://github.com/machunter/llmll/issues).

## Read on

The [series](index.md) goes from this one function to 163:

1. [The bugs that looked like correct code](blog/post-1-the-bugs-that-looked-correct.md)
2. [A compiler that refuses](blog/post-2-a-compiler-that-refuses.md)
3. [Composition, and the bound that wasn't there](blog/post-3-composition-and-the-missing-bound.md)
4. [Can agents invent the helper functions too?](blog/post-4-who-writes-the-decomposition.md)
5. [163 agent-written functions, verified against their contracts](blog/post-5-the-payoff.md)
