# cdp-perf-0 run summary

- **Timestamp (UTC):** 20260703T051103Z
- **Compiler:** `llmll 0.14.5` (`v0.14.5`, `e50b1f1`)
- **Reps:** 5 measured + 1 warmup, median reported

## Per-fixture

| fixture | bare median (ms) | cdp median (ms) | overhead (ms) | total candidate_count |
|---|---|---|---|---|
| b1 | 436.1 | 799.6 | 363.5 | 6 |
| b3 | 551.9 | 1387.2 | 835.2 | 4 |
| b5 | 578.9 | 794.0 | 215.1 | 5 |
| totp | 413.9 | 418.9 | 4.9 | 0 |
| erc20 | 405.7 | 1181.1 | 775.4 | 15 |
| banking | 536.5 | 950.7 | 414.3 | 11 |

## Fit: overhead_ms ~ a + b * total_candidate_count

- n = 6 fixtures
- a (fixed overhead, ms) = 197.40
- b (marginal cost per candidate, ms) = 34.73
- R² = 0.3347
