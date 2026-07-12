# RFC 1982 — Serial Number Arithmetic, by pipeline

DNS zone transfers ask one question: *is this serial newer than mine?* RFC 1982
defines the arithmetic that answers it — and the answer is famously **not**
`(< s1 s2)`, because serials wrap. This example translates RFC 1982 into
verified LLMLL by running the
[spec-from-RFC pipeline](../../docs/design/spec-from-rfc-pipeline.md) stage by
stage (S0→S5), as its §4 evaluation run. The scope matrix and the per-clause
inventory live in [`VERIFICATION_SCOPE.md`](VERIFICATION_SCOPE.md); the pipeline
findings live in `experiments/rfc1982-eval/findings.md`.

What the solver proves (SERIAL_BITS = 32, the DNS SOA width):

- **`serial-add`** — wrap-around addition. §3.1's `modulo` is expressed as a
  linear case split (an S0 scoping decision, not a verify-time discovery), so
  the exact result value AND the space bound are body-faithful `verified`.
- **`serial-lt` / `serial-gt`** — the §3.2 case-split relations, contracts
  authored as biconditionals shaped like the RFC's own sentences, bodies written
  as decision chains. Both `verified`.
- **The famous corner** — a pair at distance exactly 2^31 is *neither* less nor
  greater (§3.2/§4). The biconditionals encode it; a property demonstrates it.

And what the mutants show (every command below reproduced against the shipped
binary; the verdicts are frozen in `EXPECTED_VERDICTS.json`, run by
`make refute-crux-gate`):

```
$ llmll verify ./serial.llmll --strict-verified-core
✅ serial.llmll — SAFE (liquid-fixpoint)

$ llmll verify ./serial-lt-bad.llmll --strict-verified-core     # the historical bug: plain <
error: body verification of 'serial-lt' failed — implementation does not satisfy postcondition (constraint #0)
ERROR: --strict-verified-core: refuted: serial-lt

$ llmll verify ./serial-add-bad.llmll --strict-verified-core    # addition without the wrap
error: body verification of 'serial-add' failed — implementation does not satisfy postcondition (constraint #0)
ERROR: --strict-verified-core: refuted: serial-add

$ llmll verify ./serial-lt-weak.llmll --strict-verified-core    # weak spec: the SAME naive body survives
✅ serial-lt-weak.llmll — SAFE (liquid-fixpoint)
```

`serial-lt-bad` is the bug DNS implementations actually shipped: treat serials
as plain integers. Under the RFC-authored contract the solver refutes it — the
witness region is wraparound (`s1 = 2^32-1, s2 = 0`: the RFC says s1 *is less
than* s2; plain `<` says it is not).

`serial-lt-weak` is the co-evolution exhibit: the same naive body under a
*plausible partial reading* of §3.2 (one direction, near pairs only) verifies
SAFE. The clause inventory is what makes the gap visible — its Q5 row shows the
untranslated disjunct and iff-direction. One mechanized signal does fire here:
`--weakness-check` flags the weak post as satisfiable by `(lambda [...] true)`.

Adequacy (S4) on the clean module:

```
$ llmll verify ./serial.llmll --spec-coverage        # Effective coverage: 100% (3/3), no suppression
$ llmll verify ./serial.llmll --weakness-check       # No spec weaknesses detected.
$ llmll test  ./serial.llmll                         # 3/3 properties pass (§5-analog vectors + the undefined pair)
```

Regenerate twins: `llmll build ./<file>.llmll --emit -o .`
