# TOTP RFC 6238 — Verification Scope Matrix

| # | Function | Pre | Post | Body | Check | Source |
|---|----------|-----|------|------|-------|--------|
| 1 | `compute-time-step` | ✅ contracted | ✅ contracted | ✅ implemented | ✅ 2 vectors | RFC 6238 §4.2 |
| 2 | `dynamic-truncate` | ✅ contracted | ✅ contracted | ✅ implemented | — | RFC 4226 §5.3 |
| 3 | `hmac-sha1-wrap` | ⊘ weakness-ok | ⊘ weakness-ok | ✅ builtin delegate | — | RFC 2104 |
| 4 | `generate-totp` | ✅ contracted | ✅ contracted | ✅ implemented | — | RFC 6238 §4 |
| 5 | `validate-totp` | ✅ contracted | — | ✅ implemented | ✅ reflexive | RFC 6238 §5.2 |
| 6 | `pad-otp` | — | ✅ contracted | ✅ implemented | ✅ padding | RFC 4226 §5.4 |

**Effective spec coverage:** 100% (5 contracted + 1 weakness-ok = 6/6)

## Legend

- **✅ contracted** — has a pre/post clause with `:source` provenance
- **⊘ weakness-ok** — intentionally underspecified with documented reason
- **✅ implemented** — hole is filled with a concrete body
- **✅ N vectors** — has N check blocks (RFC test vectors or property tests)
