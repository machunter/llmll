# token-revocation-emergent — verification scope (S0/S1 record)

The spec-from-RFC pipeline's S0 fragment-scoping + S1 clause-inventory artifact
(`docs/design/spec-from-rfc-pipeline.md` discipline, second instance after
`examples/rfc1982_serial/`), for the A4 flagship
(`docs/archive/shipped-design-specs/a4-flagship-token-revocation-plan.md`). Root contracts only —
bodies are agent-authored under the emergent-cascade discipline.

## S0 — data model and fragment scoping (decided before authoring)

- **Token handles are `int`** (`tid`). The v1 map class admits int keys only
  (`data-scope-lever-a-arrays-proposal.md` §3 F2); token strings/hashes are
  deployment carriers, modeled by the `fingerprint` module at fixed
  `bytes[32]` width.
- **`tokens : map[int,string]`** — the status store; values are the closed
  status vocabulary `"active"` / `"revoked"` / `"expired"` (string-tag
  literals; STRLIT distinctness makes them pairwise-provably distinct).
- **`exp : map[int,int]`** — the expiry store; `now` is the evaluation
  instant; "within validity window" = `now < exp[tid]` (strict, per RFC 7662
  §2.2 exp "expire on or after").
- **Invalidation is a status transition, not deletion** — `revoke` leaves the
  token present with status `"revoked"`, so a later `introspect` finds it and
  reports inactive via the not-revoked conjunct. This keeps the whole surface
  inside the shipped map fragment (presence + value read/write).
- Everything lands in **QF-LIA ⊕ QF_AX ⊕ QF_EUF** (`Σ_auto`): int arithmetic,
  the two-array map encoding, interned `Str` constants + distinctness/length.
  Confirmed: every root contract classifies `contract_fragment: qf_lia`
  (obligation report, 2026-07-17, v0.14.48).

## S1 — normative clause inventory

| # | Clause (verbatim anchor) | Disposition | Root contract |
|---|---|---|---|
| Q1 | RFC 7662 §2.2 — `active`: "token … issued by this authorization server, has not been revoked …, and is within its given time window of validity" | **Encoded** — `introspect`'s post, the three-conjunct definition (presence ∧ status-`"active"` ∧ `now < exp[tid]`) | `introspection.llmll` / `introspect` |
| Q2 | RFC 7662 §2.2 — unknown/inactive token → introspection response `active: false`, **not** an error | **Encoded** — `introspect` is total over presence (no presence pre); the post forces `result = false` off the presence conjunct | `introspection.llmll` / `introspect` |
| Q3 | RFC 7009 §2.1 — "the authorization server invalidates the token; the invalidation takes place **immediately**, and the token cannot be used again after the revocation" | **Encoded** — `revoke`'s post pins `result[tid] = "revoked"`; composed with Q1, a revoked token can never introspect active (the use-after-revoke refutation of Phase 5) | `revocation.llmll` / `revoke` |
| Q4 | RFC 7009 §2 — "the client requests the revocation … by making an **HTTP POST** request" | **Encoded** — `handle-revocation`'s pre `(= method "POST")` (the STRLIT method gate; the GET twin is a Phase-5 refute) | `revocation.llmll` / `handle-revocation` |
| Q5 | RFC 7009 §2 — an invalid/unknown token at the endpoint yields success (200), no error | **Dispositioned out** — HTTP-response behavior, not state semantics; the verified core scopes revocation to known tokens (`revoke`'s pre). Recorded, not encoded. | — |
| Q6 | RFC 7662 §4 — the protected resource validates the token before granting access | **Encoded** — `grant`'s pre IS the validity proof obligation (the assume-guarantee surface: a caller that skips introspection is refuted at the call site) | `enforcement.llmll` / `grant` |
| Q7 | RFC 7009 §2 — "the client MUST NOT use the token again after the revocation" (service side: nothing is served for a non-active token) | **Encoded** — `serve`'s fail-closed post: grant `tid` exactly when Q1 holds, else 0 (the stated—not steered—use-after-revoke shape) | `spine.llmll` / `serve` |
| Q8 | OAuth 2.0 Security BCP practice — store token **hashes**, not raw tokens | **Deployment-modeled** (no numbered normative clause claimed) — `fp-byte-match`'s one-directional no-false-accept post over `bytes[32]`; carries the bytes index-in-bounds obligation | `fingerprint.llmll` / `fp-byte-match` |
| Q9 | RFC 7662 §2 — introspection calls are authorized/authenticated | **Dispositioned out** — client authentication is transport/credential machinery outside the data model; recorded, not encoded. | — |

## Acceptance (Phase-2 gate — met 2026-07-17)

Every root parses, verifies at the contract level, and classifies
`contract_fragment: qf_lia`; each hole obligation surfaces the full
postcondition goal + typed in-scope params in the obligation report (the
checkout-brief content the fill agents will receive). Reference feasibility:
the `introspect` shape was probe-verified body-faithful SAFE with its
expiry-skip twin REFUTED (A2S-11) before seed authoring.
