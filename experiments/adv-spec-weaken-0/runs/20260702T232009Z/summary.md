# adv-spec-weaken-0 run summary

- **Timestamp (UTC):** 20260702T232009Z
- **Compiler SHA:** `4d104c5` (main)
- **`llmll version`:** `llmll 0.14.4`

## Per-fixture signal by CLI config

| fixture | weakness-check-json | cdp-json | strict-verify-json | strict-verify-text |
|---|---|---|---|---|
| ax1-00-honest-baseline | effective:True | effective:True; cdp:withdraw:spec-too-tight-for-omega; cdp:withdraw:score=None; cdp:withdraw:entropy=strict | effective:True; cdp:withdraw:spec-too-tight-for-omega; cdp:withdraw:score=None; cdp:withdraw:entropy=strict | silent |
| ax1-01-loud-naked | effective:True; weakness-check-diag x2 | effective:True; cdp:withdraw:identity-satisfies-post,const-satisfies-post; cdp:withdraw:score=0.10175559829607284; cdp:withdraw:entropy=strict | effective:True; weakness-check-diag x2; cdp:withdraw:identity-satisfies-post,const-satisfies-post; cdp:withdraw:score=0.10175559829607284; cdp:withdraw:entropy=strict | spec-weakness x2 |
| ax1-02-loud-laundered-singlefn | effective:True | effective:True; cdp:withdraw:score=0.10175559829607284; cdp:withdraw:entropy=intentional | effective:True; cdp:withdraw:score=0.10175559829607284; cdp:withdraw:entropy=intentional | over-annotation-warning |
| ax1-03-diluted-above-threshold | effective:True | effective:True; cdp:withdraw:score=0.10175559829607284; cdp:withdraw:entropy=intentional; cdp:deposit:spec-too-tight-for-omega; cdp:deposit:score=None; cdp:deposit:entropy=strict | effective:True; cdp:withdraw:score=0.10175559829607284; cdp:withdraw:entropy=intentional; cdp:deposit:spec-too-tight-for-omega; cdp:deposit:score=None; cdp:deposit:entropy=strict | over-annotation-warning |
| ax1-04-diluted-below-threshold | silent | silent | silent | silent |
| ax2-00-list-honest-baseline | effective:True | effective:True; cdp:list-len-after-append:spec-too-tight-for-omega; cdp:list-len-after-append:score=None; cdp:list-len-after-append:entropy=strict | effective:True; cdp:list-len-after-append:spec-too-tight-for-omega; cdp:list-len-after-append:score=None; cdp:list-len-after-append:entropy=strict | silent |
| ax2-01-arith-tolerance-band | effective:True | effective:True; cdp:withdraw:spec-too-tight-for-omega; cdp:withdraw:score=None; cdp:withdraw:entropy=strict | effective:True; cdp:withdraw:spec-too-tight-for-omega; cdp:withdraw:score=None; cdp:withdraw:entropy=strict | silent |
| ax2-02-list-length-trapdoor | effective:True | effective:True; cdp:list-len-after-append:spec-too-tight-for-omega; cdp:list-len-after-append:score=None; cdp:list-len-after-append:entropy=strict | effective:True; cdp:list-len-after-append:spec-too-tight-for-omega; cdp:list-len-after-append:score=None; cdp:list-len-after-append:entropy=strict | silent |
