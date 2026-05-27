# CDP-0 baseline run summary

- **Timestamp (UTC):** 20260527T140751Z
- **Compiler SHA:** `121815a` (lt-cdp/discriminative-power-axis)
- **`llmll version`:** `llmll 0.10.8`
- **CDP scope:** `CDPScopeAllDefLogic`
- **Adjudication:** `cdp-discriminating-weak`

## Aggregate

- Contracted functions across corpus: **20**
- Defined-score functions: **5** (25.0%)
- Midrange (0 < DP < 1) functions: **1** (20.0% of defined)

### Score distribution (defined scores only)

- mean: **0.529**, median: **0.644**
- min: 0.000, p10: 0.000, p50: 0.644, p90: 1.000, max: 1.000

### Warning counts

- `const-satisfies-post`: 5
- `identity-satisfies-post`: 2
- `not-requested`: 11
- `vacuous-over-omega`: 4

### spec-entropy annotation counts

- `strict`: 20

## Primary corpus results

- **b1** (examples/benchmarks/b1-withdraw.llmll): 1 contracted fn(s)
- **b3** (examples/benchmarks/b3-safe-first.llmll): 1 contracted fn(s)
- **b5** (examples/benchmarks/b5-double.llmll): 1 contracted fn(s)
- **totp** (examples/totp_rfc6238/totp_filled.ast.json): 5 contracted fn(s)
- **erc20** (examples/erc20_token/erc20_filled.ast.json): 6 contracted fn(s)
- **banking** (examples/banking_ledger/banking.llmll): 6 contracted fn(s)
