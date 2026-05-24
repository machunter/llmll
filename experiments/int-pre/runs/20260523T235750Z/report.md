# INT-PRE report — 20260523T235750Z

**Adjudication:** `int-2-clear`
**Catalog:** `docs/design/int-2-boundary-shims.md` @ `32a796e`

## Per-benchmark regression factors (Variant B median / Variant A median)

| benchmark | phase | A median (ms) | B median (ms) | factor | A IQR | B IQR | n |
|---|---|---|---|---|---|---|---|
| b1 | verify_spec_coverage | 21.57 | 21.42 | 0.993 | 3.04 | 5.60 | 10 |
| b1 | verify_trust_report | 20.45 | 20.68 | 1.011 | 0.11 | 0.19 | 10 |
| b1 | build | 20.17 | 20.51 | 1.017 | 0.23 | 0.16 | 10 |
| b3 | verify_spec_coverage | 20.37 | 20.16 | 0.990 | 0.09 | 0.20 | 10 |
| b3 | verify_trust_report | 20.32 | 20.41 | 1.005 | 0.19 | 0.18 | 10 |
| b3 | build | 19.75 | 19.99 | 1.012 | 2.01 | 0.59 | 10 |
| b5 | verify_spec_coverage | 20.17 | 20.22 | 1.003 | 0.18 | 0.26 | 10 |
| b5 | verify_trust_report | 20.17 | 20.28 | 1.006 | 0.98 | 0.99 | 10 |
| b5 | build | 19.54 | 20.39 | 1.044 | 0.48 | 0.06 | 10 |
| totp | verify_spec_coverage | 20.09 | 19.49 | 0.970 | 0.33 | 0.69 | 10 |
| totp | verify_trust_report | 20.33 | 20.14 | 0.991 | 0.80 | 0.27 | 10 |
| totp | build | 19.65 | 19.99 | 1.017 | 0.91 | 1.30 | 10 |
| totp | test | 19.44 | 19.73 | 1.015 | 1.90 | 0.10 | 10 |
| erc20 | verify_spec_coverage | 19.99 | 20.29 | 1.015 | 0.33 | 0.47 | 10 |
| erc20 | verify_trust_report | 20.45 | 20.20 | 0.988 | 0.17 | 1.45 | 10 |
| erc20 | build | 20.25 | 20.28 | 1.002 | 0.11 | 0.10 | 10 |


## Control assertions

- **verify_spec_coverage_byte_identity**: holds=True; evidence=[]
- **verify_trust_report_byte_identity**: holds=True; evidence=[]

## Gate criterion

- Primary: totp.test.total_wallclock_ratio ≥ 5.0 → escalate INT-3 to freeze-exception (promote docs/design/int-3-machine-int-sketch.md from Rev 0 contingency to Rev 1 settled proposal)
- Secondary: totp.test.user_only_ratio ≥ 10.0 → INT-2 proceeds with finding routed to language-team on sealed-crypto-dominance contingency; INT-3 stays armed pending OBLIG-B arithmetic-density benchmark
