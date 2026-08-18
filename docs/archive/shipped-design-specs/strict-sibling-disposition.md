---
name: strict-sibling-disposition
archive-disposition: shipped
---

# STRICT-SIBLING (Same-Run Sibling Evidence for Strict-Core Admission) — Disposition

> **Status:** Settled (language-team disposition, 2026-07-12): **the bottom-up staging discipline
> is the recorded design**; same-run admission is declined, with its shape scoped for the record.
> Closes the roadmap row surfaced twice in the v0.14.32 session (examples-modernization
> `banking_ledger` promotion attempt; ENUM-EQ-FALLBACK sweep triage).

## The question

Strict-core admission accepts a user-defined callee only on **persisted, hash-valid, fully
verified sidecar evidence** (`TypeCheck.checkCalleeAdmissibility`, `:480-517`: the ADMIT-VERIFIED
conjunction — `isVerifiedLevel ∧ erBodyFaithful ∧ ¬erOverflowTainted ∧ erVerifiedHash present`,
plus `erTerminationVerified` for recursive callees). An all-`def` call chain in one file therefore
cannot verify in a single command: the caller's admission gate runs before this run's verification
produces any evidence, so the chain must be staged bottom-up (verify the leaf, producing its
sidecar; then the caller). Is that the design, or a gap to engineer away?

## Disposition: staging is the design

1. **The gate's position makes same-run evidence structurally unavailable, and that position is
   deliberate.** Admission runs during the strict-core *type-check* gate; verification runs after.
   The code states it: "everything in `tcContractStatus` is persisted/validated evidence … there is
   no in-pass 'fresh' evidence channel here (verification runs after type-check)"
   (`TypeCheck.hs:486-490`). Same-run admission is not a relaxed predicate on the existing gate —
   it is a different pipeline (verify-then-admit in topological order), i.e. real re-architecture
   of a soundness-critical seam.

2. **The sidecar is the evidence model.** The whole trust chain — hash validity
   (`downgradeStaleVerifiedSidecar`, REC-HASH-FORM), staleness downgrade, the `av2` semantics tag,
   fail-closed on absent hashes — is built on persisted records with one staleness story. An
   in-memory same-run evidence channel would be a second trust path with its own
   validity conditions, doubling the surface the ADMIT-VERIFIED audit has to cover.

3. **The designed composition idiom already verifies whole files in one command.**
   `examples/banking_ledger/banking.llmll` is the witness: `def` leaves (`safe-subtract`,
   `compute-fee`) under `def-shell` composition layers (`withdraw`, `transfer`, `clamp-withdraw`,
   `withdraw-twice`) — the three-level chain reaches `verified` in a single run via
   assume-guarantee, no staging. The wall is hit only by **post-hoc promotion** of a whole chain
   from `def-shell` to strict `def` — a migration/refactor activity, not an authoring or
   agent-repair flow, and migrations are naturally staged (the second command is deterministic and
   cheap; the CLI recomputes per build).

4. **No agent flow reaches the wall.** Scaffold/checkout/patch/refine verify whole modules with
   contracted holes and `def-shell` hosts; the strict gate meets agent-authored code only after
   evidence exists. The two recorded encounters were both the same promotion experiment.

## The declined option, scoped for the record (SAME-RUN-ADMIT)

If demonstrated friction ever justifies it: run verification in topological order over the
call-graph SCC condensation, admitting a sibling on **this run's** evidence (same conjunction,
sourced from the in-run verdict rather than the sidecar), refusing cycles exactly as today.
Soundness is preservable (it is the same solver run; the evidence is fresher than any sidecar) —
the cost is the pipeline inversion above plus a second evidence path through the admission audit.
Trigger for reopening: promotion-to-`def` becoming a repair-loop step agents actually execute, or
a real corpus where bottom-up staging is operationally painful (many-round-trip CI, not two
commands). Absent that, the two-command staging is documented behavior, not a defect.

## Verification mapping

No new obligations; no spec change. The disposition documents existing gate semantics
(`LLMLL.md §5.3.4` strict-core closure; `TypeCheck.hs:480-517`).
