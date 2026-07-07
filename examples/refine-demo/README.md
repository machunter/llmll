# Cascading refinement — the `refine` op

`patch` fills a leaf. **`refine`** decomposes a hole: it installs a hole's body **and spawns new
contracted sub-holes the body calls**, atomically — growing a refinement tree top-down. An agent
doesn't fill in a human's pre-authored blanks; it *invents the decomposition*, and the compiler
verifies each step.

Two guardrails keep an invented decomposition honest:

- a **scope-relaxation safety predicate** — a spawned def must be *fresh*, *body-referenced*, and
  *hole-bodied*, added additively (no clobbering a sibling);
- a **CDP vacuity gate** — a spawned sub-contract that a trivial identity/constant/projection body
  already satisfies is rejected at spawn (it "verifies" nothing).

## The program

`base.llmll` (→ `base.ast.json`, what `refine` operates on) is a single hole:

```lisp
(def-shell verify-exchange [sig_ok: int payload: int] -> int
  (pre  (>= payload 0)) (post (= result (+ sig_ok payload))) ?body)
```

## Refine it — fill `verify-exchange` by calling a spawned `final-verdict`

```bash
llmll build examples/refine-demo/base.llmll --emit -o .     # regenerate base.ast.json
TOKEN=$(llmll checkout base.ast.json /statements/0/body --json | jq -r .token)   # lock the hole
#   splice TOKEN into refine-good.json, then:
llmll refine base.ast.json refine-good.json
#   → PatchSuccess
llmll verify base.ast.json
#   → body-faithful: verify-exchange, SAFE   (H verifies *modulo* final-verdict's contract)
llmll holes  base.ast.json
#   → final-verdict's body is a new frontier hole — the next thing to fill or refine
```

`refine-good.json` is a `refine` request: one `replace` at `verify-exchange`'s body with the call
`(final-verdict sig_ok payload)`, plus a `PatchAdd /statements/-` of the `final-verdict` def
(contract `(= result (+ ok pay))`, body `?impl`). `verify-exchange` verifies *assuming* that
contract; `final-verdict` becomes the next hole. That is one cascade step.

## The guardrails fire

```bash
llmll refine base.ast.json refine-vacuous.json
#   → refine gate: spawned sub-contract 'final-verdict' is vacuous — a trivial (identity/constant)
#     body already satisfies it, so it discriminates no real implementation; strengthen the contract
```
`refine-vacuous.json` weakens `final-verdict`'s post to `(>= result 0)` — which a constant `0` body
satisfies. The CDP gate rejects the spawn: an agent cannot decompose `H` into a sub-goal that
demands nothing. (Its unique value is the *loose-but-plausible* contract; a grossly-empty `(post
true)` is caught anyway — `H` cannot verify modulo `true`.)

```bash
llmll refine base.ast.json refine-orphan.json
#   → refine gate: spawned def 'orphan' is not referenced by the fill body
```
`refine-orphan.json` adds a def the fill body never calls. The safety predicate rejects it — a
`refine` may only introduce sub-functions the decomposition actually *uses*, so the scope
relaxation cannot become an arbitrary-write escape.

## Verified

Every command above was run against the built `llmll` (v0.14.13). The request `token` fields show
`<TOKEN-from-checkout>` — substitute the token `checkout` returns; a real token witnesses the file's
content hash and goes stale (compare-and-swap) if the file changed under you.
