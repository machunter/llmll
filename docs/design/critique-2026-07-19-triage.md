# External Critique Triage — 2026-07-19

> **Status:** Record of an external technical review of `main` at HEAD [`e284fe0`](https://github.com/machunter/llmll/commit/e284fe0c737b6b623a33392277ebbb7f3b25fecc) (`v0.14.53`, 2026-07-19). The reviewer cloned `main`, ran the version gate (README / `LLMLL.md` / CHANGELOG / cabal+package metadata / schema `0.8.0` internally consistent), but did **not** run the Haskell/Z3/liquid-fixpoint suite. This document is the durable capture + routing table; downstream skills consume §2.
> **Prior triage:** [`critique-2026-05-23-triage.md`](critique-2026-05-23-triage.md) (fourteen-section external critique; seventeen routed items).

---

## 1. The review's bottom line

The reviewer's strategic read **matches the project's own positioning** ([`strategic-positioning.md`](strategic-positioning.md)): the novel center is *verification as an agent-coordination protocol* — typed holes, `checkout`/`patch`/`refine`, trust reports, caller obligations, transitive dependency trust, and decomposition-trust gates — not a new type theory or SMT technique. The trust lattice's separation (`verified` / `contract-checked` / `tested` / `asserted` / `refuted`, plus caller-obligations and discriminative power) is called out as one of the project's best instincts. The `v0.14.53` decomposition-trust meet ("weakest unvouched subtree below a generated decomposition") is named as a good direction.

Verdict: *a promising agent-verification workbench, not a soundness story to bet a production security boundary on.* Recommended next step is hardening the semantic story, smoothing agent footguns, and fixing release/license hygiene — **not** adding features. No design-team adjudication is required for any item below; the disposition is recorded inline.

The critique raises **one new, verified defect** (license hygiene) and several partially- or fully-captured items re-raised. Nothing in it contradicts a shipped design decision.

## 2. Routing table

Tags follow the project's `XXX-N` convention. Lifecycle: *open → routed → in-progress → shipped*.

| Tag | Item | Priority | Owner | Status |
|---|---|---|---|---|
| **LIC-1** | Build manifests declare `license: MIT` while `LICENSE` + README + one-pager are **GPLv3 + LLMLL Runtime Library Exception**. | P1 | engineer | **SHIPPED (this triage)** — `compiler/package.yaml:5` + `compiler/llmll.cabal:13` `MIT → GPL-3`. `LICENSE` already carries GPLv3 text + the exception (v1.0, §677–696); no LICENSE change needed. The reviewer's secondary "exception text may be missing" read was a search-truncation artifact — verified present. |
| **IMPORT-LINT-1** | "Imports placed after definitions are silently ignored." | P2 | docs | **VERIFIED STALE DOC — fixed.** Does not reproduce: a capability import placed *after* a `def-shell` parses and checks fine (`(import wasi.io (capability stdout))` after its use → `✅ OK`). Imports are collected regardless of position (`[imp \| SImport imp <- stmts]`). The claim lived only in `getting-started.md §4.8`, whose example also used stale syntax `(import wasi.io stdout)`. Corrected there. |
| **LIST-IF-1** | "List literals in `if` branches hit a parse limitation." | P2 | docs | **VERIFIED STALE DOC — fixed.** Does not reproduce: the exact doc-failing expression `(if won (wasi.io.stdout (string-concat-many ["You won! " word "\n"])) …)` parses `✅ OK`. The `unexpected ]` restriction was fixed in the parser; `getting-started.md §4.7/§4.8` still warned about it. Corrected there. |
| **DO-1** *(existing)* | `do`-notation silently discards non-final intermediate `Command`-typed binds. | P2 | — | **VERIFIED ALREADY IMPLEMENTED.** `checkDiscardedCommand` (`TypeCheck.hs:1592`) already emits a warning on every non-final `Command` step ("current codegen discards this intermediate command…"). Only the *hard-error* tightening is deferred by design (`(discard expr)` opt-out). Not open work. |
| **DEFINV-1** | `def-invariant` semantic enforcement "not fully realized." | P2 | docs | **VERIFIED — split.** (1) *Enforcement* (Z3 invariant-verification on AST merge) is genuinely deferred — **Phase 2b**, and already honestly disclosed (schema `DefInvariant` + `LLMLL.md §11.4`). Building it is a feature, not a footgun fix; out of scope for this sweep. (2) `§11.4` ALSO carried a **stale sub-claim** that the S-expression parser rejects `def-invariant` in `.llmll` source — false: it parses (added v0.12.1, `Parser.hs:173`; verified `✅ OK`). Corrected `§11.4`. No compiler work; enforcement stays an honest known-gap. |

## 3. Re-raises of already-settled items (no new action)

| Reviewer point | Disposition |
|---|---|
| Large trusted base; no independent mechanized formal semantics. | **Declined by prior adjudication.** Path B (mechanized soundness vs an independent operational semantics) is the recorded Path-A stance in [`verification-debate.md`](verification-debate.md); LLMLL is engineering-first by design. The reviewer explicitly credits the docs for saying so. |
| Spec adequacy is the central unsolved risk — a bad-but-discriminative contract still verifies. | **Known central risk.** CDP, `--weakness-check`, RFC traceability, and `:source` annotations *measure* spec quality; they do not prove the spec is the right one. Acknowledged limitation, not a regression. The cascade Layer-3 work sharpens the measurement, not the guarantee. |
| Crypto (SHA/HMAC) is stubbed/opaque — must not be marketed as verified crypto. | **CRYPTO-1 PARTLY RETRACTED 2026-08-03; corrected here 2026-08-18.** This row read "**CRYPTO-1 shipped.** `sha1`/`hmac` carry stub/asserted trust tiers". **There is no stub tier.** `rg 'stub-backend' compiler/` returns zero hits and `TrustReport.hs:1630` emits `"asserted"`; the commit credited with shipping the channel was documentation-only. See `critique-2026-05-23-triage.md` rows `CRYPTO-1` (the retraction) and `CRYPTO-2` (what actually holds; routed to a roadmap row 2026-08-18 and **EXECUTED 2026-08-19 at `b0d03e6`**). **What does hold, and is sufficient:** the `asserted` cap on every function whose trust closure reaches `sha1` / `hmac-sha1` is real and emitted, and the TOTP and ERC20 examples state their opacity. The reviewer's point stands unchanged: the docs are candid and the residual risk is reader over-reading. **This line is cited by line number** from `compiler/src/LLMLL/CodegenHs.hs:918` and `compiler/test/Spec.hs:14868`, which is why it was rewritten in place rather than moved or split. |
| Fast `0.14.x` release cadence is good for a sprint, less so for ecosystem stability. | Stylistic observation on a pre-1.0 research prototype. No action; noted. |

## 4. Items explicitly declined or deferred

| Item | Disposition |
|---|---|
| Path B mechanized soundness theorem | Declined — inherited from [`verification-debate.md`](verification-debate.md). |
| "Add more features" as the next step | Explicitly **rejected by the reviewer too**; the agreed direction is hardening + hygiene. |

---

## 5. Verification outcome (2026-07-19)

Each "agent-hostile edge" the reviewer flagged was reproduced against the compiler before routing. The
reviewer stated they did not run the suite; the edges turned out to be **stale documentation**, not
compiler defects:

- **IMPORT-LINT-1** and **LIST-IF-1** — both non-reproducing. The precise doc-failing programs parse and
  check cleanly on the current parser. `Parser.hs` and `TypeCheck.hs` are unchanged since `v0.14.51`
  (`git log v0.14.51..HEAD` empty for both), so the tested binary is behaviorally identical to HEAD. The
  false claims lived in `getting-started.md §4.7/§4.8` and were corrected in this release.
- **DO-1** — the compiler already warns (`checkDiscardedCommand`); only the deferred hard-error remains,
  by design.

The reviewer trusted `getting-started.md` and repeated its stale gotchas as current — a direct example of
the doc being the footgun. Fixing the docs (not the compiler) is the correct remediation.

**Durable procedure (added post-triage).** To stop this class recurring, the docs' falsifiable
restriction-claims are now gated in CI: `scripts/doc_claims_gate.sh` (**DRIFT-CT-2**, sibling of the
DRIFT-CI-1 version gate) runs each claim's program through `llmll check` and fails when the observed
verdict diverges from the doc — pointing at the exact `@doc` section. Seeded with the claims above;
format + how-to-extend in [`scripts/doc-claims/README.md`](../../scripts/doc-claims/README.md). Wired into
the `spec-roundtrip` job of `.github/workflows/version-gate.yml`. The compiler-engineer definition-of-done
gains one line: *a change that alters parse/check/verify behaviour must run this gate and reconcile any flip.*

**End of triage record.** Net: **LIC-1** fixed (manifests), three stale gotchas corrected in
`getting-started.md`, `DO-1` confirmed already-implemented. **No open compiler engineering** remains from
this critique. Strategic points re-raise already-settled items (§3–§4).
