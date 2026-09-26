# conways_life_json_verifier: Conway's Life with contracts, partially proved

A single-module Game of Life in JSON-AST with contracts on 6 of its 21
functions. It shows where the decidable fragment ends: the cell rule and the
neighbor arithmetic are proved from their bodies, while grid reads through
`list-nth` stay outside the fragment and are only assumed. Of the three game
verifiers in `examples/`, this is the one that proves anything.

| File | Contents |
|---|---|
| `life.ast.json` | The whole program: world accessors, `cell-at`, `neighbor-alive`, `count-neighbors`, `next-cell`, `step-world`, rendering, console loop |
| [`VERIFICATION_SCOPE.md`](VERIFICATION_SCOPE.md) | Per-function contract and tier table, and why each contract lands where it does |

The uncontracted twins are [`../life_json/`](../life_json/) and
[`../life_sexp/`](../life_sexp/).

## What `verify` prints

Reproduced on llmll 0.26.5:

```
$ llmll verify ./life.ast.json
   body-faithful: neighbor-alive, count-neighbors, next-cell
   body-fallback: make-world, cell-at, in-bounds?, count-alive, render-cell, render-row-life, render-grid, set-alive
   ⚠️  W-BODY-FALLBACK: 'cell-at' fell back from body-faithful verification (body-outside-fragment), so its post is assumed and not proved. Refused by: let.
   ⚠️  W-BODY-FALLBACK: 'count-alive' fell back from body-faithful verification (body-outside-fragment), so its post is assumed and not proved. Refused by: if.
   Running liquid-fixpoint ...
⚠️  ./life.ast.json — SAFE (liquid-fixpoint), partial: 3 of 5 contracted functions proved; 2 assumed, not proved: cell-at, count-alive
   (--strict-verified-core fails on assumed functions)
```

Exit 0. SAFE with `partial` means no contradiction was found, not that every
contract was proved.

## Two tiers per function

`--trust-report` separates a function's own proof from what it depends on:

```
$ llmll verify ./life.ast.json --trust-report
  ...
  count-neighbors:
    pre:  —  |  post: verified (liquid-fixpoint)
    ↳ calls neighbor-alive (pre: —, post: verified (liquid-fixpoint))
    ⚠ count-neighbors is verified (liquid-fixpoint), but depends on cell-at which is asserted
  ...
  next-cell:
    pre:  asserted  |  post: verified (liquid-fixpoint)
  ...
Summary:
  verified:         1
  asserted:         4
  no contract:      16
  ⚠ epistemic drifts: 2
```

`neighbor-alive` and `count-neighbors` discharge their own postconditions, but
both rest on `cell-at`'s bound, which is assumed. The report flags each as an
epistemic drift and counts only `next-cell`, which depends on no assumed
function, as `verified`. See [`VERIFICATION_SCOPE.md`](VERIFICATION_SCOPE.md)
for the reasoning, and `LLMLL.md` §5.3.5 for the fragment boundary.
