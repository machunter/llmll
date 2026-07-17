# token-revocation-emergent — the A4 data flagship

The data counterpart of [`../secure-channel-emergent/`](../secure-channel-emergent/):
an OAuth-shaped token introspection/revocation service (RFC 7662 / RFC 7009) in
which **both origins are machine-auditable** — every contract clause carries
`:source` provenance from RFC text (the spec-from-RFC pipeline), and every body
was invented by a fresh, blind, tool-disabled agent through cascading `refine`
(the emergent discipline; no reference solution ever existed).

Plan of record: [`docs/design/a4-flagship-token-revocation-plan.md`](../../docs/design/a4-flagship-token-revocation-plan.md).
Scope + clause inventory (Q1–Q9): [`VERIFICATION_SCOPE.md`](VERIFICATION_SCOPE.md).

## Result

**8 functions across 5 modules, all `verified` body-faithful, whole-service SAFE**
— 2 of the 8 (`token-status-active`, `token-unexpired`) were *invented by an
agent*, contracts included. Zero compiler findings; every fill accepted within
2 attempts. The spine's trust report: `verified: 5`, nothing asserted.

The exercised data surface is the whole v0.14.33–48 arc: string-tagged map
values with literal distinctness (`"active"` ≠ `"revoked"` doing proof work),
int-map expiry arithmetic, presence-gated defensive reads, a string-map-returning
revocation write, `bytes[32]` bounds, and cross-module assume-guarantee.

## The two headline fills

**The spontaneous cascade** (`audit/introspection/`): handed only `introspect`'s
RFC 7662 contract, the first agent REFINEd — decomposing the `active` definition
into two functions it named and *contracted itself*, each filled blind by a later
agent:

```text
REFINE
(and (token-status-active tokens tid) (token-unexpired exp tid now))
(def-shell token-status-active … (post (= result (and (map-has tokens tid) (= (map-get tokens tid) "active")))) ?impl)
(def-shell token-unexpired    … (post (= result (and (map-has exp tid) (< now (map-get exp tid))))) ?impl)
```

**The cross-module composition** (`audit/spine/`): `serve`'s agent, seeing
`introspect` and `grant` only as imported contracts, wrote

```text
(if (introspect tokens exp tid now) (grant tokens exp tid now) 0)
```

— and the solver discharged `grant`'s validate-before-grant precondition (RFC
7662 §4) from `introspect`'s postcondition **across the module boundary**: the
assume-guarantee obligation, proven, not assumed.

## The refute layer (author-injected, CI-frozen)

After the wave verified, each accepted fill was mutated into a famous-bug twin;
all are frozen in [`EXPECTED_VERDICTS.json`](EXPECTED_VERDICTS.json) and gated by
`make refute-crux-gate`:

| Crux | Bug class | Verdict |
|---|---|---|
| `crux-introspect-expiry-skip` | token accepted past expiry (validity-window conjunct dropped) | **refuted** — and this one is the v0.14.48 witness: before the STRLIT body-channel flip the buggy body fell back and verified *vacuously SAFE* |
| `crux-revoke-dropped-put` | revocation silently lost (store returned unchanged) | **refuted** |
| `crux-method-gate` | verb tampering (CWE-650): GET reaches the POST-only revocation action | **refuted at the call site** — `strlit_GET ≠ strlit_POST`, the STRLIT distinctness fact carrying a security property |
| `crux-serve-unconditional` | use-after-revoke / goto-fail shape: unconditional grant | **refuted** |
| `crux-fp-false-accept` | fingerprint match claimed without byte equality | **refuted** |

Good twins (the agents' actual bodies, inlined where the wave's version composes
imports) stay SAFE in the same gate.

## The channel discipline

Identical to secure-channel-emergent, harness copied verbatim
(`audit/OPERATION-MANUAL.md`, `audit/runner.py`): each hole filled by a fresh,
stateless `claude -p` with **all tools disabled**; its entire input is the fixed
operation manual + the compiler-emitted checkout brief (contract, in-scope
names, callable contracts — imported ones included). Retries receive only the
compiler/harness error text. Acceptance per fill: verify `SAFE` **and**
body-faithful. Every prompt, reply, and verdict is under `audit/`.

## Findings

1. **F-1 (harness, fixed before the wave):** the reply converter rejected a
   *bare-atom* body (`tid` — legal LLMLL) on a paren-counting technicality; the
   pilot agent worked around with the semantically identical `(+ tid 0)`, which
   stands in the audit trail. Converter fixed (`convert_reply.py`).
2. **F-2 (compiler limitation, pre-existing, value-type-agnostic):** a
   map-returning **bare tail call** (`(revoke tokens tid)` as the whole body)
   is not a `mapRetChain` shape and routes to contract-only fallback, so the
   natural sibling composition was rejected by the body-faithful bar; the agent
   inlined the transition instead (`audit/revocation/step02`). Follow-on
   candidate: pin the caller's `result$has/$val` to the callee's via the
   component substitution that call-intermediate results already use.
3. **F-3 (process):** `refute-crux-gate` runs `stack exec`, which does not
   rebuild — a stale stack binary made the new family's refutes vacuously SAFE
   until `stack build` was rerun. The 35-case gate now passes on the current
   binary; keep `stack build` in the gate's preflight when the compiler has
   changed.
4. **F-4 (positive):** data-contract holes are fillable blind — 8/8 accepted
   within 2 attempts, one spontaneous 2-function cascade, one unprompted
   cross-module composition discharging an assume-guarantee obligation.

## Reproduce

```bash
# re-verify the filled service (any module):
llmll verify work/spine.ast.json --trust-report
# the frozen refute layer:
make refute-crux-gate
# re-run a module's cascade from its roots (destructive to work/):
llmll build roots/introspection.llmll --emit -o work
LLMLL_BIN=$(cd compiler && cabal list-bin llmll) python3 audit/runner.py introspection
```
