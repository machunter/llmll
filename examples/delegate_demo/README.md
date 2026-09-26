# delegate_demo: filling a `?delegate` hole through checkout and patch

The smallest delegate-hole round trip. `program.ast.json` has one `def`,
`compute-value`, whose body is a `hole-delegate` addressed to
`@math-agent` ("Compute the square of x and return (state, result)").
`patch-request.json` is the agent's answer: an RFC 6902 JSON Patch that first `test`s
the hole is still at `/statements/1/body`, then `replace`s it with
`(pair state (* x x))`.

Neither function has a postcondition, so this shows the hole-resolution protocol, not
verification.

| File | What it is |
|---|---|
| `program.ast.json` | Two functions: `add-numbers` (a `def-shell`) and `compute-value` with the delegate hole |
| `patch-request.json` | The fill, as a JSON Patch carrying a checkout token |

## Commands (outputs reproduced against llmll 0.26.5)

Run from this directory, on a copy: `checkout` writes `program.llmll-lock.json`, and a
successful `patch` rewrites `program.ast.json` in place.

```bash
llmll holes ./program.ast.json
```
```
./program.ast.json — 1 holes (0 blocking)
  [AGENT] ?delegate @math-agent in def compute-value
```

**The committed token is from an earlier session**, so the patch as shipped is
refused:
```bash
llmll patch ./program.ast.json ./patch-request.json
```
```
{"message":"invalid or expired checkout token","result":"PatchAuthError"}
```
Exit 1. A patch is accepted only under a live lock on that hole.

**Check out the hole, put the new token in the request, and patch.**
```bash
llmll checkout ./program.ast.json /statements/1/body   # prints a JSON brief with "token" and "ttl":3600
jq --arg t <token> '.token=$t' patch-request.json > patch-live.json
llmll patch ./program.ast.json ./patch-live.json
```
```
{"result":"PatchSuccess","reuse_suggestions":[],"statements":2}
```
Exit 0. Afterwards `llmll holes ./program.ast.json` reports `0 holes`, and
`llmll verify ./program.ast.json` prints `SAFE (liquid-fixpoint), nothing proved: no
function carries a postcondition` (exit 0).

For the same flow over a larger module with several agents, see
[`../orchestrator_walkthrough/`](../orchestrator_walkthrough/); for checkout and patch
with contracts and rejected fills, see [`../withdraw-demo/`](../withdraw-demo/).
