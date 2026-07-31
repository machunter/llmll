# Requirements

**Milestone:** compiler backlog, targeting v0.15
**Source:** `.planning/intel/requirements.md` (45 extracted), scoped by user directive to six.
**Provenance rule inherited from the ingest:** no PRD-typed document was present. Requirements are
the **open / unshipped remainder** recorded in SPEC-typed docs. Work a source records as already
shipped is deliberately not emitted. `docs/compiler-team-roadmap.md` is the backlog of record
(precedence 0); where a proposal disagrees with it, the roadmap wins.

---

## In Scope (v1, this milestone)

All six carry precedence-0 authority from `docs/compiler-team-roadmap.md`.

### REQ-wild-assume-2

**Phase:** 1
**Source:** `docs/compiler-team-roadmap.md` (Active Items, WILD-ASSUME-2 row);
`docs/design/finding-arg-position-false-safe.md` (Rev 2)

Extend the WILD-ASSUME restriction from `bytes[n]` (stage 1, shipped v0.14.73) to the `map[k,bool]`
arm. A `map[k,bool]` binder carries the ground fact `0 <= select(m$val,k) <= 1` asserted from its
declared value type (`injectRangeFacts`, `boolValRooted`), the same class SAFE-ARG closed for
bytes: a fact no obligation discharges, believed from a declaration the type channel need not have
validated.

**Acceptance (from source):** `assumesFact` extended to the map class. **Prerequisite:** the
`(map-empty)` over-breadth fixture (`SA-6`) must be in place first, because
`map-empty : TFn [] (TMap (TVar "k") (TVar "v"))` relies on componentwise wildcard absorption, so
any discriminant broader than the bare wildcard breaks every use of it.

**Scope:** WILD-ASSUME, `map[k,bool]` value-range facts, `assumesFact`, SA-6 fixture.

**Evidence limit to preserve in the writeup:** a measured member of the class **with no
reaching-SAFE witness**. Both the return and argument shapes crash on a sort mismatch before a
verdict, so the arm is neither known exploitable nor known safe. The phase closes a class member;
it does not refute a demonstrated exploit.

---

### REQ-ret-resolve

**Phase:** 2
**Source:** `docs/compiler-team-roadmap.md` (Active Items, RET-RESOLVE row);
`docs/design/ret-resolve-proposal.md` (Rev 2, SETTLED);
`docs/design/ret-branch-pref-proposal.md` (Stage 1 / Stage 2);
`docs/design/ret-resolve-proposal-review.md` (Round 1, finding 1, lines 19-27)

Resolve a wildcard `tau_ret` transitively in a verification-facing pass. `collectTopLevel`
registers an unannotated return as `TVar "?"`, callers inherit it through `inferExpr`, and `sortA1`
lowers it to `FQInt`. Kleene iteration of a monotone update over the recorded return-type map
(`tcRetTypes`) closes nine measured crash shapes at the root instead of one shape at a time. **This
requirement carries the whole if-join wildcard-preference scope**, including the generalization
beyond self-recursion previously tracked as RET-BRANCH-PREF Stage 2.

**Acceptance (from source):** three side conditions hold.

- **SC1** wildcard-only refinement: bare `TVar "?"` only; named-hole types retained; a concrete
  `tau^0` is never revised.
- **SC2'** a sandboxed pass from which only the return-type map is extracted, so the type channel's
  accept/reject set and the sketch-hole registry are unchanged by construction.
- **SC3'** an SCC-conditioned `if`-join preference: the concrete branch is preferred only when the
  wildcard branch's head calls a member of `SCC(f)`.
- **Gate:** the corpus census predicts a **byte-identical `.fq` across all 128 files** and zero
  demotions, the same gate that refuted the withdrawn HOLE-RET.
- **Cycle rule:** a component with no concrete anchor stays bare-wildcard and keeps today's
  behavior.

**Scope:** `collectTopLevel`, `inferExpr`, `sortA1`, `calleeRetSort`, `FixpointEmit.hs`,
`TypeCheck.hs`, `HoleAnalysis.hs`, `Module.hs`, if-join branch preference.

**Ordering constraint:** queued **second**, behind WILD-ASSUME-2. One of four behaviour channels
(`resultLenFact` assumption injection) can turn a crash into `verified`, so this must not land
before WILD-ASSUME is in place.

**Prior shipped scope, not re-emitted:** RET-BRANCH-PREF Stage 1 shipped v0.14.72 for
**self-recursion only**. SC3' generalizes that condition to same-SCC membership. Scope this phase
to the unshipped generalization.

**Adjudication (reversible).** The RET-BRANCH-PREF Stage 2 type-channel variant is **withdrawn**,
not deferred. Authority: `docs/design/ret-resolve-proposal-review.md` Round 1 finding 1 classifies
the unconditioned if-join preference as "soundness-adjacent" and recommends the SCC condition,
citing Milner 1978, Damas and Milner POPL 1982, and Jones, *Typing Haskell in Haskell*, Haskell
Workshop 1999 §11. Recorded as INFO-2 / INFO-3 in `.planning/INGEST-CONFLICTS.md`.

---

### REQ-fact-ag

**Phase:** 3
**Source:** `docs/compiler-team-roadmap.md` (Active Items, FACT-AG row);
`docs/design/ret-resolve-proposal-review.md` (Round 4)

Route type-derived VC assumptions through assume-guarantee. No fact derived from a *type* enters a
VC antecedent unless the function that declared that type has discharged it, carried on the
existing `consumed_guarantees` / §5.3.4 meet channel rather than asserted from an annotation. The
criterion is "contributes a VC assumption that no obligation discharges", which is FACT-AG
inverted.

**Acceptance:** ⚠️ **ABSENT in source.** Recorded as research track with no acceptance criteria
stated. This requirement needs acceptance criteria authored before its phase is planned. Nothing
has been inferred here.

**Scope:** VC antecedents, `consumed_guarantees`, §5.3.4 meet channel, type-derived facts.

**Note:** the general form of what WILD-ASSUME approximates. Scope beyond `bytes` / `map` is
**unmeasured**.

---

### REQ-oblig-1-def-invariant

**Phase:** 4
**Source:** `docs/compiler-team-roadmap.md` (OBLIG-1-FOLLOWON row)

Populate the one deferred province of the obligation-report `assumptions` field: `def-invariant`
axioms. v1 (refinement predicates of in-scope refinement-typed params), v2a (let-definitional
equalities), and v2b (match-scrutinee case hypotheses) have shipped.

**Acceptance:** ⚠️ **ABSENT in source.** Deferred; the source records only that it needs provenance
tagging, hence a schema bump, and that an unverified invariant is a TCB assumption. Acceptance
criteria must be authored before planning.

**Scope:** obligation report, `assumptions` field, `def-invariant` axioms, schema version.

---

### REQ-contract-read-lint-residual

**Phase:** 4
**Source:** `docs/compiler-team-roadmap.md` (CONTRACT-READ-LINT row)

Two deferred tiers of the contract-position partial-read lint: (a) the `map-get`-without-`map-has`
heuristic tier (disposition (c), "may ship later"), and (b) the Dafny-style well-formedness
side-obligation (disposition (b)).

**Acceptance:** ⚠️ **ABSENT in source.** Both recorded as deferred, no criteria stated. Acceptance
criteria must be authored before planning.

**Scope:** `TypeCheck.lintContractReads`, `contract-read-oob` warning, map reads.

**Settled context:** contract-position reads are total selects, sound in both directions; the
disposition of record (2026-07-12) is status quo plus a scoped non-blocking lint on the decidable
slice, with the v1 `bytes-zero` context rule blessed.

---

### REQ-int-3

**Phase:** 5
**Source:** `docs/compiler-team-roadmap.md` (INT-3 row);
`docs/design/critique-2026-05-23-triage.md` §4 (INT-3 row)

`MachineInt` QF-BV alias, a post-freeze machine-integer type under QF-BV verification scope.

**Acceptance (from source):** language-team design when scheduled. Promote from P3 to P1 only if
INT-PRE shows a TOTP regression > 5x; it cleared at 1.015x, so the item is dormant.

**Scope:** integer semantics, QF-BV, `MachineInt`.

⚠️ **Scheduling flag.** The source records INT-3 as **dormant**, and its stated acceptance is a
promotion condition (a cost gate that did not fire) plus a design deliverable, not an
implementation criterion. Scheduling it into this milestone overrides that recorded dormancy. If
the milestone needs to shorten, this is the drop candidate, and it is sequenced last for that
reason.

---

## Deferred Backlog (39 requirements, carried forward)

Not dropped. A future milestone picks one track up. Full text for each:
`.planning/intel/requirements.md`.

### Module system codegen (4)

| ID | One-line | Note |
|---|---|---|
| `REQ-mod-2-per-module-emission` | `[CT]` per-module `.hs` emission with export lists | prerequisite for MOD-3 and MOD-5 |
| `REQ-mod-3-qualified-access` | `[CT]` translate `module.function` to Haskell qualified imports | needs MOD-2 |
| `REQ-mod-4-strict-typecheck-migration` | `[CT]` `loadFromFile` to `typeCheckStrictWithCache` | needs MOD-1; all examples need correct `(open ...)` |
| `REQ-mod-5-interface-mismatch` | `[CT]` `checkInterfaceMismatch` wiring | needs MOD-2; closes XMOD-AG nominal-by-name ADT identity |

Group trigger: a production use case requiring true namespace isolation.

### Sandboxing / WASM (1)

| ID | One-line | Note |
|---|---|---|
| `REQ-wasm-build-target` | Replace Docker with WASM-WASI as the primary sandbox, 4 phases (~7 days) | trigger: untrusted agent code outside dev environments. Risk: `ghc-wasm-meta` is low bus-factor |

### Data scope (3)

| ID | One-line | Note |
|---|---|---|
| `REQ-lever-a-residue-a3x` | A3.x residue: reuse-retrieval abstains on array contracts, CDP array-sorted candidate bases, classifier callee-leg imprecision | DATA class itself complete (v0.14.33-51) |
| `REQ-lever-b-dependent-lengths` | `list[t]{len = n}` plus a widened total-measure catalog | decidable, stays in `Sigma_auto`; overlaps R1 |
| `REQ-lever-c-induction` | Inductive datatypes, PLE, refinement reflection | undecidable in general, **leaves `Sigma_auto`**; gated on LEAN-GA |

### Lean tier / LEAN-GA (4)

| ID | One-line | Note |
|---|---|---|
| `REQ-lean-ga-layer1-translator` | Translate the **obligation**, not the contract; new `bodyToLean` | trust root, must lead the sequence |
| `REQ-lean-ga-layer2-routing` | Route `erBodyFallback` obligations into `runLeanstralPipeline` | coupled to layer 1; Gap B (`isNonLinear` has no `EOp` case) first |
| `REQ-lean-ga-layer3-transport` | T-B server-as-checker transport, model search plus kernel check | accept iff zero errors, zero open goals, no `sorry` |
| `REQ-lean-ga-anti-laundering-guard` | `sanitizeProof` chokepoint rejecting `sorry`/`admit`/empty | recorded BUILT in a worktree, uncommitted, pending review. Non-negotiable prerequisite of layer 1 shipping |

### Obligations and spec text (2)

| ID | One-line | Note |
|---|---|---|
| `REQ-oblig-2` | OBLIG-2 | gated on OBLIG-0 §4.2.3 / §4.2.4 |
| `REQ-wildcard-semantics-spec` | `[SPEC]` land what `?` denotes in `LLMLL.md §3.4.6`; fix the `if`-reconciliation drift at `:399` | lands whether or not the if-join preference ships; route the drift independently |

### Patch / refine slicing (2)

| ID | One-line | Note |
|---|---|---|
| `REQ-r8-latency-benchmark` | The repair-loop latency benchmark R8 shipped without | correctness already proven; this is the measurement |
| `REQ-refine-slice` | The refine-side sibling of R8 (additive slice for spawned functions) | contingent: build only if Phase 2 dry-run telemetry shows refine re-verify dominating, soundness note first |

### RFC-SWARM phases 1 to 4 (7)

| ID | One-line | Note |
|---|---|---|
| `REQ-rfc-cov-1` | `[CT]` inventory-to-`:source` cross-check lint | Phase 1; syntactic, no solver |
| `REQ-ext-agent-1` | `[EXP]` blind-agent stages S1-S3 plus independent second extraction | Phase 1; agent-arm failure downgrades the claim, does not block |
| `REQ-swarm-1-concurrency-protocol` | `[DESIGN+EXP]` concurrency protocol note plus runner, plus dry run | Phase 2 |
| `REQ-rfc-swarm-phase3-wave` | `[EXP]` blind swarm fills the frozen TFTP roots | Phase 3; needs 0, 1, 2 |
| `REQ-rfc-swarm-phase4-refute-freeze` | `[EXP][SPEC]` mutant taxonomy, frozen kill matrix, demo writeup | Phase 4; needs 3 |
| `REQ-rfc-fourth-run-screening` | Screen fourth-run RFC candidates via `--only A..G2,J` | quota-bound, multi-window; 3 candidates unscreened, RFC 6298 REJECTed at gate J |
| `REQ-rfc-swarm-barrier-field-backfill` | Make gate J condition 3 evaluable on the pinned TFTP artifact | 53 exclusions carry no `barrier` field |

### SPEC-AGREE-1, Rev 1 build order a to e plus open work (9)

| ID | One-line | Build-order slot |
|---|---|---|
| `REQ-spec-agree-1a-constructor-backend` | `[CT]` constructor-capable comparison backend | (a) |
| `REQ-spec-agree-1-effective-contract-and-verdicts` | Effective-contract comparison plus three-valued verdicts | (b) |
| `REQ-spec-agree-1-comparison-cli` | Product-position CLI, two-contract difference query, `result` in the witness vector | (c) |
| `REQ-spec-agree-1-gloss-experiment` | Two-arm gloss experiment (withhold the inventory obligation gloss from one arm) | (d) |
| `REQ-spec-agree-1-nway-adversarial` | N = 3 with adversarial framings; report detection yield, never an unstratified rate | (e) |
| `REQ-spec-agree-1-stage-k-amendment` | Amend playbook stage K; EC-6 "no parameter named `result`" joins the freeze rules | open work |
| `REQ-spec-agree-1-unrendered-defeater-question` | Does an unrendered defeater carry evidential weight on its own? | open, addressed to the professor |
| `REQ-spec-agree-1-basesorttext-feasibility` | Feasibility read on `baseSortText` widening and the `FixpointEmit` declaration path | open, addressed to the compiler-engineer |
| `REQ-spec-agree-1-remeasure-comparable-fraction` | Re-derive the comparable fraction through the real classifier | every §0 figure is an upper bound until this runs |

### Research track (5)

| ID | One-line | Note |
|---|---|---|
| `REQ-r1-indexed-dependent-types` | `Vect n a`, GADTs, type-level arithmetic, bidirectional typechecking | deferred by professor consensus 2026-05-01; overlaps Lever B |
| `REQ-r2-self-hosted-orchestrator` | Rewrite `llmll-orchestra` as LLMLL `def-main :mode cli` | promotion criterion: agent accuracy >= 80% on the auth-module exercise |
| `REQ-r4-synthetic-training-corpus` | Hackage back-translation, transpiler plus spec lifting plus benchmark | no competing roadmap row |
| `REQ-cascading-refinement-gating-question` | Per-contract versus composed gating | the one open question the acyclicity policy left |
| `REQ-mcp-integration` | MCP integration for the compiler CLI | trigger: a concrete external integration request |

### No backing roadmap row, confirm before scheduling (2)

| ID | One-line | Note |
|---|---|---|
| `REQ-do-1-discard-warn-or-error` | Compiler-side warn-or-error on non-final `Command`-typed binds in `do` | recorded **only at precedence 2** (2026-05-23 triage); spec text shipped, enforcement open. INFO-18 |
| `REQ-rfc-swarm-harness-resubmit-protocol` | Wave harness submission protocol (release token, re-checkout, rebuild patch under lock) | stated prescriptively; the roadmap carries no corresponding row. INFO-13 |

---

## Traceability

| Requirement | Phase | Acceptance in source | Status |
|---|---|---|---|
| `REQ-wild-assume-2` | Phase 1 | Yes | Pending |
| `REQ-ret-resolve` | Phase 2 | Yes | Pending |
| `REQ-fact-ag` | Phase 3 | ⚠️ Absent | Pending |
| `REQ-oblig-1-def-invariant` | Phase 4 | ⚠️ Absent | Pending |
| `REQ-contract-read-lint-residual` | Phase 4 | ⚠️ Absent | Pending |
| `REQ-int-3` | Phase 5 | Promotion condition only | Pending |

**Coverage:** 6/6 in-scope requirements mapped to exactly one phase each. No orphans, no
duplicates. The 39 deferred requirements are intentionally unmapped and carry no phase.

**Acceptance gaps:** three of the six (`REQ-fact-ag`, `REQ-oblig-1-def-invariant`,
`REQ-contract-read-lint-residual`) carry `acceptance: (absent)` from their sources. Nothing was
invented. Their phases carry success criteria derived goal-backward from the requirement text, and
each is marked as needing user-authored acceptance before planning. A fourth (`REQ-int-3`) states a
promotion condition rather than an acceptance criterion.

---
*Generated 2026-07-31 from `.planning/intel/` (18 classified documents, 45 extracted requirements)*
