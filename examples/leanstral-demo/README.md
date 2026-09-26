# leanstral-demo: a nonlinear post moves from `asserted` to `verified-lean`

**Experimental, opt-in.** `square(n) = n * n` claims `result >= 0`. The body is
nonlinear, outside the QF-LIA fragment Z3 decides, so the SMT path can only
assume the post (`asserted`) and says so. With `--leanstral`, LLMLL states the
obligation as a Lean theorem, the Leanstral model writes a proof, and the Lean
kernel with Mathlib checks it. The function then records the `verified-lean`
tier and a `.lean` certificate anyone can re-check. What stays trusted is
LLMLL's translation of the contract into the theorem statement.

| File | What it is |
|---|---|
| `square.llmll` | the one obligation. It uses `def-shell`, because strict `def` rejects a nonlinear body at typecheck |
| `demo.sh` | the scripted demo that records `docs/assets/leanstral.gif` (shown in the top-level [README](../../README.md)) |

## Without a key (reproduced on v0.26.5)

```text
$ llmll verify ./square.llmll
   body-fallback: square
   ⚠️  W-BODY-FALLBACK: 'square' fell back from body-faithful verification (body-outside-fragment), so its post is assumed and not proved. Refused by: nonlinear:*.
   Running liquid-fixpoint ...
⚠️  ./square.llmll — SAFE (liquid-fixpoint), partial: 0 of 1 contracted functions proved; 1 assumed, not proved: square
   (--strict-verified-core fails on assumed functions)
```

Exit 0. `--trust-report` shows `post: asserted`, and `--strict-verified-core`
exits 1 (`1 function(s) fell back from body-faithful verification: square`).

`--leanstral` with no `LLMLL_LEANSTRAL_API_KEY` set degrades cleanly: the same
partial verdict, then

```text
   1 obligation(s) for Leanstral.
   square: unavailable: LLMLL_LEANSTRAL_API_KEY not set
```

and exit 0. The tier stays `asserted`.

## With a key: `demo.sh`

The full path needs `LLMLL_LEANSTRAL_API_KEY`, a local Lean 4 + Mathlib project
in `LEAN_PROJECT`, and `llmll`, `lake` and `jq` on `PATH`. The script checks
all of these before it starts (setup steps are in its header). It copies
`square.llmll` into a fresh temp dir, so no sidecar, proof cache or certificate
lands next to the tracked file, and then runs four beats:

1. show the `square` definition;
2. `llmll verify square.llmll`: the `W-BODY-FALLBACK`, partial verdict above;
3. `llmll verify square.llmll --leanstral --leanstral-lean-project "$LEAN_PROJECT"`:
   Leanstral proves the theorem and the kernel checks it;
4. `jq . square.llmll.verified.json` and `cat square.verified.lean`: the trust
   record and the certificate.

```bash
bash examples/leanstral-demo/demo.sh          # tap Enter per command
bash examples/leanstral-demo/demo.sh --auto   # unattended
```

The run calls a paid API. `make demo-gifs` does not record this GIF for that
reason.
