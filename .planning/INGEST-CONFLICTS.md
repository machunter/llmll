## Conflict Detection Report

Mode: new. Re-run of a prior synthesis whose 1 blocker and 2 warnings are all resolved upstream.
Precedence: manifest integer overrides (0 = `docs/compiler-team-roadmap.md`, 1 = the 10 open/parked
design proposals plus `docs/design/rfc-swarm-playbook.md`, 2 = `docs/design/spec-from-rfc-pipeline.md`
and the 6 reviews/findings/triage), falling back to `ADR > SPEC > PRD > DOC`. Lower integer wins.
18 classifications consumed (12 SPEC, 6 DOC; 0 ADR, 0 PRD, 0 UNKNOWN; all `confidence: high`,
all `manifest_override: true`). Zero decisions are LOCKED, so no LOCKED-vs-LOCKED check fired.
Cycle detection re-run over the 18-node cross-reference graph: the prior cycle is now traversed in
manifest precedence order and no synthesis loop occurred. **All 18 docs synthesized.**

### BLOCKERS (0)

None.

### WARNINGS (0)

None.

### INFO (20)

[INFO] INFO-1 — BLOCKER-1 resolved: the playbook/pipeline pair is now traversed, not withheld
  Found: docs/design/rfc-swarm-playbook.md:18 cites docs/design/spec-from-rfc-pipeline.md, and docs/design/spec-from-rfc-pipeline.md:7 cites docs/design/rfc-swarm-playbook.md
  Note: the manifest now assigns rfc-swarm-playbook.md precedence 1 and spec-from-rfc-pipeline.md precedence 2, transcribing the ordering both documents declare about themselves. spec-from-rfc-pipeline.md:7 and rfc-swarm-playbook.md:22 each read "Where the two disagree, the playbook is authoritative, having come from an execution rather than a design." The pair is traversed in precedence order, so the mutual citation is a resolved ordering rather than an unresolvable loop, and both docs are synthesized. This blocker is not re-raised.

[INFO] INFO-2 — WARNING-1 adjudicated: the if-join fork collapses to RET-RESOLVE SC3'
  Found: docs/design/ret-branch-pref-proposal.md (Stage 2, "recorded but not proposed") routed the general form through the type channel, gated on a corpus `.fq` byte-diff AND a typecheck-acceptance diff over `examples/`
  Found: docs/design/ret-resolve-proposal.md (SC3') routed the same scope through a sandboxed verification-facing pass conditioned on same-SCC membership, gated on a byte-identical `.fq` across all 128 corpus files
  Note: adjudicated in favour of SC3'. Authority: docs/design/ret-resolve-proposal-review.md Round 1 finding 1 (lines 19-27) classifies the unconditioned if-join preference as "soundness-adjacent" and recommends conditioning on same-SCC membership, "which generalizes Stage 1's self-call condition to its natural boundary", citing Milner 1978, Damas and Milner POPL 1982, and Jones, *Typing Haskell in Haskell*, Haskell Workshop 1999 §11; the same finding notes this makes the SCC decomposition necessary and gives a one-pass algorithm in reverse topological order. `REQ-ret-branch-pref-stage2` is withdrawn and its scope is folded into `REQ-ret-resolve`, whose acceptance now carries SC3' as the general form. Recorded here so the adjudication stays reversible: reinstating the type-channel variant means re-splitting `REQ-ret-resolve` and restoring the two-diff gate.

[INFO] INFO-3 — RET-BRANCH-PREF Stage 1 is shipped and is not re-emitted as forward work
  Note: docs/design/ret-branch-pref-proposal.md records Stage 1 as SHIPPED v0.14.72, narrowed to **self-recursion only**. `REQ-ret-resolve` records that fact and states that SC3' generalizes the self-call condition to its natural boundary (same-SCC membership). No requirement re-asks for Stage 1.

[INFO] INFO-4 — WARNING-2 settled: SPEC-AGREE-1 is read at Rev 1, and Rev 0's §1 and §6 are withdrawn
  Found: docs/design/spec-agreement-proposal.md at HEAD is "Rev 1 - professor review folded; scope settled by measurement; Sigma_witness gap routed to compiler-engineer" (dated 2026-07-31)
  Note: Rev 0's §1 applicability claim ("applies to every `Encoded` row") and §6 effort table ("small `[CT]`") are withdrawn by the document itself. Requirements are emitted from Rev 1 only. `REQ-spec-agree-1-v1-proposal-scope`, `REQ-spec-agree-1-v2-review-scope` and `REQ-spec-agree-1-backend-decision` from the prior run are all withdrawn; nine Rev 1 requirements replace them. The settled shape: the domain is `Sigma_subsume`, computed per contract via `qfContract`; abstaining rows are reported `not-comparable` and **remain in the `Encoded` denominator**; the instrument is therefore neither a pipeline stage for all `Encoded` rows nor class-scoped to C2.

[INFO] INFO-5 — the measured comparable fraction is 10.6%, and it is an upper bound
  Found: docs/design/spec-agreement-proposal.md Rev 1 §0.3 reports 7/46 on TFTP (RFC 1350), 2/39 on ARP (RFC 826), 9/85 combined = 10.6%, across the two runs that passed gate J
  Note: §0.2 approximates `classifyContractFragment` as "at least one clause present", which is generous, so every figure is an upper bound and the true fraction is at or below 10.6%. The proposal's own "Provenance of §0" requires a re-run through the real `classifyContractFragment`, `contractMentionsArrOp` and `ufBearing` before any figure is published outside the document; that re-run is emitted as `REQ-spec-agree-1-remeasure-comparable-fraction`. Treat 10.6% as an upper bound, not a settled figure.

[INFO] INFO-6 — the constructor-capable backend is in scope, re-sequenced ahead of the harness, with no Lever A dependency
  Found: docs/design/spec-agreement-proposal.md Rev 1 §6.1 answers the review's Q2 in scope, and §0.4 finding M-3 measures all 18 abstentions firing on `ufBearing`'s uppercase-head clauses, with zero on `contractMentionsArrOp` and zero on a measure
  Note: the Lever A dependency the review assumed does not bind on this evidence. Effort is corrected from "`[CT]` small" to "`[CT]` medium-to-large". Emitted as `REQ-spec-agree-1a-constructor-backend`, ahead of `REQ-spec-agree-1-gloss-experiment` and `REQ-spec-agree-1-nway-adversarial`.

[INFO] INFO-7 — Sigma_witness is a new Rev 1 finding and bounds the backend's payoff
  Found: docs/design/spec-agreement-proposal.md Rev 1 §6.2 records that `baseSortText` (`Feasibility.hs:187-191`) admits Int and Bool only, abstaining for every other type after alias and refinement resolution, and that `witnessOf`/`minimizeWitness` (`:256-284`) range only over `qInputs`
  Note: widening comparison to constructor terms unlocks the C1 transition rows whose distinguishing input **is** a constructor value, and that value cannot be rendered, so those rows return a bare "these differ" bit with no exhibit. The eliminative claim survives (the `sat` verdict alone falsifies "both readings are faithful"); what is lost is the adjudication affordance. Routed as a feasibility read to compiler-engineer (`REQ-spec-agree-1-basesorttext-feasibility`) with the paired professor question (`REQ-spec-agree-1-unrendered-defeater-question`), which decides whether the `baseSortText` widening is a prerequisite of the backend or an enhancement to it.

[INFO] INFO-8 — SPEC-AGREE-1 reporting: detection yield, never an unstratified agreement rate
  Found: docs/design/spec-agreement-proposal.md Rev 1 §3 (Reporting rule) adopts review finding F-8 without qualification
  Note: the headline is the count and per-row list of `Encoded` rows where witness adjudication changed the frozen contract, as a fraction of rows that reached comparison, published beside the `not-comparable` count and the comparable fraction. Rev 0's "agreement rate as a headline measurement" is withdrawn. Recorded as a decision in `.planning/intel/decisions.md` and as acceptance on `REQ-spec-agree-1-nway-adversarial`.

[INFO] INFO-9 — no ADR- or PRD-typed documents in the ingest set
  Note: the 18 classifications are 12 SPEC and 6 DOC. `.planning/intel/decisions.md` therefore contains zero LOCKED decisions; its 24 entries are decision statements the sources themselves record as decided, declined, deferred, or adjudicated, all at `status: proposed`. `.planning/intel/requirements.md` is derived from the open/unshipped remainder of SPEC-typed docs rather than from PRDs, with the provenance rule stated in that file's header.

[INFO] INFO-10 — partially-shipped proposals: only the unshipped remainder was emitted
  Note: docs/design/ret-branch-pref-proposal.md (Stage 1 shipped v0.14.72; the general form is folded into `REQ-ret-resolve`), docs/design/oblig-0-spec.md (APPROVED; OBLIG-1/MOD-1 unblocked, OBLIG-2 gated), docs/design/rfc-swarm-roadmap-proposal.md (Phase 0 complete and SRC-CONJ-1 shipped v0.14.65; Phases 1-4 open), docs/design/incremental-reverify-r8-proposal.md (implementation shipped v0.14.61; latency benchmark deferred), docs/design/data-scope-extension.md (Lever A shipped v0.14.33-51; Levers B and C open), docs/design/leanstral-integration-scope.md (§5 anti-laundering guard BUILT but uncommitted; layers 1-3 open), and docs/design/spec-from-rfc-pipeline.md (see INFO-15). Shipped work is recorded as context, not as forward requirements.

[INFO] INFO-11 — auto-resolved: roadmap (precedence 0) supersedes oblig-0-spec (precedence 1) on OBLIG status
  Note: docs/design/oblig-0-spec.md (Rev 8, dated 2026-05-02) states "APPROVED — OBLIG-1/MOD-1 unblocked; OBLIG-2 gates on §4.2.3/§4.2.4". docs/compiler-team-roadmap.md (OBLIG-1-FOLLOWON row) records v1 + v2a + v2b as SHIPPED with one deferred province (`def-invariant` axioms). The roadmap wins as the backlog of record; only OBLIG-2 and the `def-invariant` province were emitted as requirements. This finding is preserved from the prior run and still holds.

[INFO] INFO-12 — auto-resolved: roadmap (precedence 0) supersedes critique-triage (precedence 2) on REF-META-2..5
  Note: docs/design/critique-2026-05-23-triage.md §4 records REF-META-2..5 as `open` (P2-P3, language-team drafts). docs/compiler-team-roadmap.md records "Recently retired (shipped): REF-META, Bundle B0, NIW Phase 1 (v0.12.0)". The roadmap wins; no REF-META requirement was emitted. The triage row is preserved in `.planning/intel/context.md`. This finding is preserved from the prior run and still holds.

[INFO] INFO-13 — auto-resolved and reconciled: the FQ-RESULT-SORT-1 "residual closed" phrasing
  Note: docs/compiler-team-roadmap.md (FQ-RESULT-SORT-1 row) says "SHIPPED v0.14.72; residual closed by RET-BRANCH-PREF". docs/design/ret-resolve-proposal.md (Background) says "The roadmap row claims the residual is closed by RET-BRANCH-PREF. Measured against v0.14.72, nine shapes survive." The two reconcile on a careful read: the roadmap's phrase is scoped to the single accepted residual (probe `T4a`, the `then`-position recursive self-call), while the nine surviving shapes are the separate RET-RESOLVE scope the roadmap's own RET-RESOLVE row already records ("closes nine measured crash shapes at the root"). Roadmap precedence 0 stands; no requirement changed.

[INFO] INFO-14 — auto-resolved: proposal Rev 1 (precedence 1) supersedes the review (precedence 2) on three measured points
  Found: docs/design/spec-agreement-review.md F-1 estimates the comparable set at "roughly a fifth to a quarter" of `Encoded`; Rev 1 §0.3 measures 10.6%
  Found: docs/design/spec-agreement-review.md Q2 frames the datatype-capable backend as carrying "its own Lever A dependency"; Rev 1 §0.4 M-3 measures zero array and zero measure abstentions, so the dependency does not bind
  Found: docs/design/spec-agreement-review.md Context records `examples/tftp_rfc1350/` as holding only `VERIFICATION_SCOPE.md` and concludes stage K has not run; Rev 1 §0.1 records that at HEAD the directory holds `roots/` and `wave/`, so stage K has run and two further runs exist under `experiments/rfc-swarm/runs/`
  Note: precedence and measurement agree in all three cases, so these auto-resolve to the proposal. The superseded review figures are preserved as history in `.planning/intel/context.md` under the SPEC-AGREE-1 review topic, annotated as history rather than as current claims. The review's non-superseded findings (F-2 through F-13) are adopted by Rev 1 and are carried in `.planning/intel/constraints.md`.

[INFO] INFO-15 — auto-resolved: the playbook (precedence 1) is the operational authority over the pipeline doc (precedence 2)
  Found: docs/design/spec-from-rfc-pipeline.md §1 assigns S1 clause extraction to a single "agent, human-reviewed" pass; docs/design/rfc-swarm-playbook.md stage D requires **two extractors that cannot see each other** on identical bytes under the identical rubric, and §3 anti-pattern 7 states that self-audit cannot answer the completeness question
  Found: the two docs use different stage vocabularies, S0-S5 (pipeline: what the parts are) versus A-O (playbook: how to run it, in what order, with what decision rules, and what stops you)
  Note: the playbook wins on both, by manifest precedence and by both docs' own declaration. Neither divergence is a contradiction of content: the stage vocabularies are complementary and both are extracted to `.planning/intel/constraints.md` with their sources attached. Also auto-resolved in the same direction: the pipeline's §S3 `:source` format convention is retained and the playbook's executed `"[T045] ..."` bracketed-inventory-tag convention is recorded alongside it as the form that makes coverage mechanically checkable.

[INFO] INFO-16 — spec-from-rfc-pipeline.md yields zero forward requirements
  Note: its §6 gaps table records G1 CLOSED (first persisted clause inventory, RFC 1982 run, 2026-07-12), G2 CLOSED at v0.14.65 (SRC-CONJ-1, per-conjunct provenance), G4 CLOSED (the §4 evaluation executed on RFC 1982, all six criteria pass), and G3 accepted with no owner (C4 provenance is an unchecked reason-string convention, "revisit only if an auditor consumer materializes"). G3 is emitted as a decision, not a requirement. The §4 evaluation plan text is retained in the doc as the procedure future candidates rerun; the forward screening work is already carried by `REQ-rfc-fourth-run-screening`, so no duplicate requirement was emitted. The doc's contribution to this synthesis is six constraints and one decision.

[INFO] INFO-17 — SPEC-AGREE-1 §7 proposes an unlanded amendment to playbook stage K
  Found: docs/design/spec-agreement-proposal.md Rev 1 §7 proposes amending docs/design/rfc-swarm-playbook.md stage K (fix signatures, add the EC-6 naming rule to the freeze, gate on `qfContract` per row, send only the comparable set for N-way blind authoring)
  Note: both docs sit at precedence 1, and this is not a contest: the amendment is proposed and unlanded, so the playbook's stage K text remains the operational authority until it ships. The amendment is emitted as `REQ-spec-agree-1-stage-k-amendment` rather than folded silently into the stage K constraint.

[INFO] INFO-18 — two requirements have no backing row in the backlog of record
  Note: `REQ-do-1-discard-warn-or-error` is recorded only at precedence 2 (docs/design/critique-2026-05-23-triage.md §4, dated 2026-05-23) and has no corresponding row in docs/compiler-team-roadmap.md. `REQ-rfc-swarm-harness-resubmit-protocol` is recorded prescriptively at precedence 1 (docs/design/rfc-swarm-playbook.md stage M, "Recorded here so the next harness does not"), is not recorded as built, and likewise has no roadmap row. Silence is not contradiction, so both were emitted with an explicit note that they are absent from the backlog of record and should be confirmed before scheduling. `REQ-rfc-swarm-harness-resubmit-protocol` refines rather than competes with `REQ-swarm-1-concurrency-protocol`: SWARM-1 is the protocol note plus runner, and the playbook supplies the executed resolution of its token-granularity question (per-hole advisory lock, per-FILE compare-and-swap).

[INFO] INFO-19 — dangling cross-references to un-ingested documents
  Note: cross-references pointing outside the ingest set are informational, never blockers, per the ingest scope rule. The two mutual citations between rfc-swarm-playbook.md and spec-from-rfc-pipeline.md now resolve inside the set. Design docs cited but not ingested: `finding-fq-result-sort-default.md`, `finding-match-nullary-ctor-unsound.md`, `finding-fq-ctor-name-collision.md`, `contract-position-reads-disposition.md`, `cascading-refinement-proposal.md`, `agent-orchestration.md`, `strategic-positioning.md`, `specification-sources.md`, `verification-debate.md`, `int-3-machine-int-sketch.md`, `type-driven-development.md`, `archive-organization-proposal.md`, `scope.md`. Archived docs cited: `archive/shipped-design-specs/` (rec-body-vc, match-widen-stretch-plan, refine-reuse-gate, proof-artifact, bundle-b0-effect-summary, leanstral-demo-spec, data-scope-lever-a, string-valued-maps, string-literal-distinctness, a4-flagship-token-revocation-plan, int-2-boundary-shims, core-shell-inversion, refinement-metatheory-of-record, contract-discriminative-power, proof-required-predicate-carrier), `archive/professor-reviews/`, `archive/research-track.md`, `archive/wasm-investigations/`. Non-doc targets cited: `LLMLL.md`, `CHANGELOG.md`, `docs/UPDATE-PROTOCOL.md`, `compiler/src/LLMLL/*.hs`, `experiments/*`, `examples/*`, `scripts/*`, `site/blog/*`.

[INFO] INFO-20 — scope-disjoint and intra-document supersessions, neither surfaced as conflicts
  Note: docs/design/rfc-swarm-roadmap-proposal.md (Rev 1.1) ratifies TFTP/RFC 1350 and sequences Phases 0-4 for that run, while docs/design/rfc-swarm-target-selection.md (Rev 1) records three completed runs and screens candidates for a **fourth**; the two cover different runs, both at precedence 1, so no precedence rule was applied. Intra-document supersessions were honoured rather than surfaced: docs/design/rfc-swarm-target-selection.md §3 describes a two-call pre-flight screen and §5 retires it the same day on its own controls, and §5's ~30-minute estimate is corrected to 45-60 minutes in §6; docs/design/ret-branch-pref-proposal-review.md F-3 classifies the unrestricted rule as a soundness blocker and the "Ruling on the recorded divergence" section withdraws that classification; docs/design/rfc-swarm-playbook.md stage G records Amendment 1 (2026-07-27) rewriting the `B7` rule after RFC 4648, replacing the undecidable "no mutant can exercise the row" form. In each case the later text within the same document governs, and the superseded text was not extracted.
