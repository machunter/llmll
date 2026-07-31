# Onboarding Summary

## Project State
- PROJECT.md: present
- REQUIREMENTS.md: present
- ROADMAP.md: present
- STATE.md: present

## Codebase Context
- Brownfield repo: yes
- Map readiness: complete
- Codebase map: `.planning/codebase/` (complete codebase map)
- Fast map available: yes

## Docs Context
- Existing ADR/PRD/SPEC/RFC candidates: 16 detected by the projection; 127 matched the ingest
  discovery patterns, over the v1 cap of 50.
- Ingested: 18, selected by manifest (`.planning/ingest-manifest.yaml`). The selection rule is
  status recorded in `docs/design/INDEX.md`: open, queued, draft, or parked. Excluded were all 84
  files under `docs/archive/` (shipped, superseded, dormant, or professor reviews already folded),
  plus settled, fixed, and active-reference docs. Zero files matched the ADR/PRD/SPEC/RFC directory
  conventions, so every discovery hit came from the generic `docs/**/*.md` fall-through.
- Result: 45 requirements, 51 constraints, 24 decisions (0 locked, since the set contains no
  ADR-typed document), 6 context topics.

## Conflicts resolved during ingest
The first synthesis pass returned 1 blocker and 2 competing variants and the safety gate held, so
no planning file was written. All three were resolved before the re-run, and each is recorded as
INFO in `.planning/INGEST-CONFLICTS.md` so it stays reversible.

- **Cross-reference cycle** between `rfc-swarm-playbook.md` and `spec-from-rfc-pipeline.md`
  (playbook:18 cites pipeline, pipeline:7 cites playbook), which withheld both from synthesis.
  Resolved by splitting manifest precedence 1 / 2, which transcribes the ordering both documents
  declare about themselves at `spec-from-rfc-pipeline.md:7` and `rfc-swarm-playbook.md:22`.
- **RET-BRANCH-PREF Stage 2 vs RET-RESOLVE SC3'.** Collapsed into `REQ-ret-resolve` as SC3', a
  sandboxed verification-facing pass conditioned on same-SCC membership. Authority is
  `ret-resolve-proposal-review.md` Round 1 finding 1, which classifies the unconditioned form
  soundness-adjacent and recommends the SCC condition.
- **SPEC-AGREE-1 scope.** Settled by revising `docs/design/spec-agreement-proposal.md` to Rev 1
  rather than by picking between the proposal's and the review's claims. The scope question was
  decided by running the measurement the review's F-1 prescribed: the comparable fraction is 9/85
  = 10.6% across the two runs that passed gate J, an upper bound. Rev 1 also records a new finding,
  the `Sigma_witness` limit at `Feasibility.hs:187-191`, routed to compiler-engineer.

## Milestone scope
The 45 requirements span four largely independent tracks. This milestone is the **compiler backlog
targeting v0.15** and phases only the five requirements carrying precedence-0 authority from
`docs/compiler-team-roadmap.md`. The other 40 are carried in REQUIREMENTS.md as a deferred backlog
in 11 track groups, not dropped. Phase completion is defined as a shipped release: a CHANGELOG
entry, a version bump, and `scripts/version_gate.sh` passing.

(Six requirements were phased at bootstrap; `REQ-int-3` was scoped out on 2026-07-31, see Open
items below.)

## Open items
- ~~**`REQ-int-3` (Phase 5) is dormant by the backlog of record.**~~ **RESOLVED 2026-07-31: scoped
  out.** `docs/compiler-team-roadmap.md:61` reads "promote to P1 if INT-PRE shows TOTP regression
  > 5× (cleared at 1.015×, so dormant)". The promotion condition is not met, so the requirement
  returned to the deferred backlog under the integer-semantics track and the milestone is now four
  phases cutting v0.15.0 at Phase 4.
- **`REQ-fact-ag` (Phase 3) has no acceptance clause and unmeasured reach.** Least-defined phase.
- Three of the five carry `acceptance: (absent)`: `REQ-fact-ag`, `REQ-oblig-1-def-invariant`,
  `REQ-contract-read-lint-residual`. Criteria in those phases are goal-backward starting points,
  not authority.
- Two deferred requirements have no backing roadmap row and need confirming before scheduling:
  `REQ-do-1-discard-warn-or-error`, `REQ-rfc-swarm-harness-resubmit-protocol`.
- The 10.6% figure in `REQ-spec-agree-*` approximates `classifyContractFragment`. Re-run it through
  the real Haskell predicate before publishing it anywhere.

## Recommended Next Step
- `/gsd-manager`
