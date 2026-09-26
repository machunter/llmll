# erc20_token: ERC-20 contracts and where the solver stops

The six ERC-20 (EIP-20) functions written as LLMLL contracts in JSON-AST, first as a
holed skeleton, then filled. The example shows the verification-scope split: the
three non-negativity posts (`total-supply`, `balance-of`, `allowance`) are proved;
the conservation posts on `transfer` and `transfer-from` are stated but stay
`asserted`; `approve` has only a precondition. It also shows `--weakness-check`
flagging posts that a trivial body already satisfies.

`transfer` cannot reach `verified` here by design of the benchmark, not by a missing
annotation: the whole ledger is one bare `int`, `transfer`'s body is a stub, and its
conservation post calls `total-supply` only inside the post clause. The reasons are
in [`WALKTHROUGH.md`](WALKTHROUGH.md) §2. For conservation that is proved, see
[`../payments-core/`](../payments-core/).

| File | What it is |
|---|---|
| `erc20.ast.json` | Skeleton: 6 holes, full contract suite |
| `erc20_filled.ast.json` | The filled version |
| `erc20_filled.ast.json.verified.json` | Tracked sidecar; `verify` rewrites it |
| [`EXPECTED_RESULTS.json`](EXPECTED_RESULTS.json) | Frozen trust counts, weak functions, and the `future_work` note |
| [`WALKTHROUGH.md`](WALKTHROUGH.md) | Spec-to-contract mapping, scope matrix, strengthening workflow |

## Commands (outputs reproduced against llmll 0.26.5)

Run from this directory, on a copy (`verify` rewrites the tracked sidecar).

```bash
llmll check ./erc20.ast.json
```
```
✅ ./erc20.ast.json — OK (6 statements)
```

**Three of five contracted functions proved.**
```bash
llmll verify ./erc20_filled.ast.json
```
```
   body-faithful: total-supply, balance-of, allowance
   body-fallback: transfer, approve, transfer-from
   Running liquid-fixpoint ...
⚠️  ./erc20_filled.ast.json — SAFE (liquid-fixpoint), partial: 3 of 5 contracted functions proved; 2 assumed, not proved: transfer, transfer-from
   (--strict-verified-core fails on assumed functions)
```
Exit 0. `--trust-report` summarizes the same run as `verified: 3`, `asserted: 2`,
`no contract: 1` (`approve`), matching `EXPECTED_RESULTS.json`.

**Weakness check: three posts a trivial body satisfies.**
```bash
llmll verify ./erc20_filled.ast.json --weakness-check
```
Exit 0, with `Spec weakness detected` for `total-supply`, `balance-of` and
`allowance`: each post is `result >= 0`, which the identity body or the constant
`0` already meets. The candidates for `transfer`, `approve` and `transfer-from` print
as "could not be validated ... unknown, not confirmed weak" because their bodies fall
outside the checkable fragment. These three weak functions are frozen in
`EXPECTED_RESULTS.json`, so a new or dropped weakness changes the result.

`make benchmark-erc20` (`scripts/benchmark-erc20.sh`) checks spec coverage, the trust
report and the weakness check against `EXPECTED_RESULTS.json`. It is a local target;
CI does not run it.
