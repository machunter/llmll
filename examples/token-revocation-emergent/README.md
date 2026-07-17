# token-revocation-emergent — the A4 data flagship (in progress)

The data counterpart of [`../secure-channel-emergent/`](../secure-channel-emergent/):
an OAuth-shaped token introspection/revocation service (RFC 7662 / RFC 7009)
whose **spec origin and implementation origin are both machine-auditable** —
contracts derived from RFC text with `:source` clause provenance (the
spec-from-RFC pipeline), bodies to be invented by blind agents through
cascading `refine` (the emergent discipline; no reference solution exists).

Plan of record: [`docs/design/a4-flagship-token-revocation-plan.md`](../../docs/design/a4-flagship-token-revocation-plan.md).
Scope + clause inventory: [`VERIFICATION_SCOPE.md`](VERIFICATION_SCOPE.md).

## Status

- **Phase 1 (compiler residue lift)** — ✅ v0.14.47 (+ the STRLIT body-channel
  flip, v0.14.48, found while feasibility-probing the seed).
- **Phase 2 (seed contracts)** — ✅ `roots/*.llmll`: five modules, seven root
  `def-shell` contracts with `?impl` bodies, every clause `:source`-tagged,
  every contract `qf_lia`.
- **Phase 3 (pilot)** — pending: 2–3 blind data-contract hole fills gate the wave.
- **Phase 4 (the emergent wave)** / **Phase 5 (refute twins + close-out)** — pending.

## The human-authored surface (all of it)

| Module | Root contract(s) | Invariant it pins |
|---|---|---|
| `introspection` | `introspect` | RFC 7662 §2.2 `active` = present ∧ status-`"active"` ∧ within validity window; unknown → false, not an error |
| `revocation` | `revoke`, `handle-revocation` | RFC 7009 §2.1 immediate invalidation (status transition to `"revoked"`); POST-only endpoint gate |
| `enforcement` | `grant` | RFC 7662 §4 validate-before-grant — the pre a caller must PROVE (assume-guarantee) |
| `spine` | `serve` | fail-closed: grant exactly when active-and-valid, else 0 (the stated—not steered—use-after-revoke shape) |
| `fingerprint` | `fp-byte-match` | no-false-accept byte comparison over `bytes[32]` (deployment-modeled token-hash practice) |

No bodies exist and none were drafted. The status vocabulary
(`"active"`/`"revoked"`/`"expired"`), the two-map data model, and the int
token-handle gate are recorded in `VERIFICATION_SCOPE.md` §S0.
