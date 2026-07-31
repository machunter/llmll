# Roadmap

**Milestone:** compiler backlog, targeting v0.15
**Released version at milestone start:** v0.14.73
**Granularity:** standard (no `.planning/config.json` present; defaults applied)
**Coverage:** 6/6 in-scope requirements mapped, no orphans, no duplicates

The milestone is a hard boundary. These five phases cover exactly the six requirements the user
scoped in, all carrying precedence-0 authority from `docs/compiler-team-roadmap.md`. The other 39
extracted requirements are tracked as a deferred backlog in `.planning/REQUIREMENTS.md` and carry
no phase.

## Definition of Done (applies to every phase)

A phase is complete when it **ships**:

1. The change lands in `CHANGELOG.md` under a new `## vX.Y.Z` heading with a dated title.
2. The version agrees across `README.md` line 1, `LLMLL.md` lines 1 and 5, the top `## vX.Y.Z`
   heading in `CHANGELOG.md`, `compiler/package.yaml`, and `compiler/llmll.cabal`.
3. `scripts/version_gate.sh` exits 0 (this also checks `docs/llmll-ast.schema.json` schemaVersion
   against `ParserJSON.expectedSchemaVersion`, and the `$id` URL against the derived major.minor).
4. `stack test` is green and the examples gate (`scripts/check-examples.sh`) reports no new
   failures.

The release ceremony is part of the phase, not follow-up work. Where a requirement carries its own
acceptance clause, that clause is the functional criterion and the release gate sits on top of it.

**Build hygiene precondition for every measurement in this milestone.** Before trusting any
verdict, run `(cd compiler && stack build --dry-run llmll)`; "Nothing to build." means the binary
is current. `llmll version` is not sufficient and mtime comparison is wrong about correct input.

## Phases

- [ ] **Phase 1: Close the map arm of WILD-ASSUME** - Stop `map[k,bool]` value-range facts entering a VC antecedent through a bare inference wildcard
- [ ] **Phase 2: Resolve wildcard return types at the root (RET-RESOLVE SC3')** - Transitive `tau_ret` resolution in a sandboxed verification-facing pass, with the SCC-conditioned if-join preference
- [ ] **Phase 3: Route type-derived facts through assume-guarantee (FACT-AG)** - Generalize the WILD-ASSUME approximation to the rule it approximates
- [ ] **Phase 4: Disclose what the verifier assumed and where it did not check** - `def-invariant` axioms in the obligation report, plus the two deferred contract-read lint tiers
- [ ] **Phase 5: MachineInt under QF-BV (INT-3)** - A machine-integer type whose obligations are checked at machine width

## Phase Details

### Phase 1: Close the map arm of WILD-ASSUME

**Goal**: A `map[k,bool]` value that reached its binder through a bare inference wildcard can no
longer contribute a value-range fact that no obligation discharges.
**Depends on**: Nothing (first phase)
**Requirements**: `REQ-wild-assume-2`
**Target version**: v0.14.74 (indicative; must be a monotonic bump)

**Success Criteria** (what must be TRUE):
1. The `(map-empty)` over-breadth fixture `SA-6` is committed **before** the restriction widens,
   and `(map-empty)` still type-checks at every position it does today. This is the stated
   prerequisite: `map-empty : TFn [] (TMap (TVar "k") (TVar "v"))` relies on componentwise wildcard
   absorption, so a discriminant broader than the bare wildcard breaks every use of it.
2. `assumesFact` covers the map class, and the discriminant recognizes both the bare `TVar "?"` and
   its `freshenFnType` instances `?$N`. A fixture exercises the `?$N` form directly, so the guard
   cannot go dead the way the first SAFE-ARG implementation did.
3. A fixture exhibits the rejection: a `map[k,bool]` value laundered through an unannotated hop is
   refused at the seam instead of injecting `0 <= select(m$val,k) <= 1` into a VC antecedent.
4. The release notes state the evidence limit rather than overclaiming: this arm is a **measured
   member of the SAFE-ARG class with no reaching-SAFE witness**, because both the return and
   argument shapes crash on a sort mismatch before a verdict. The phase closes a class member; it
   does not refute a demonstrated exploit. A corpus run with no new failures is recorded as a
   regression check, not as evidence the fix works.
5. Shipped per the Definition of Done above.

**Plans**: TBD

---

### Phase 2: Resolve wildcard return types at the root (RET-RESOLVE SC3')

**Goal**: An unannotated return type resolves transitively before the verification channel sees it,
closing nine measured crash shapes at the root instead of one shape at a time, with acceptance
unchanged by construction.
**Depends on**: Phase 1
**Requirements**: `REQ-ret-resolve`
**Target version**: v0.14.75 (indicative)

**Ordering is a hard constraint, not a preference.** One of four behaviour channels
(`resultLenFact` assumption injection) can turn a crash into `verified`, so this must not land
before WILD-ASSUME is in place.

**Scope note.** RET-BRANCH-PREF Stage 1 shipped v0.14.72 for self-recursion only. This phase is
the unshipped generalization to same-SCC membership. The Stage 2 type-channel variant is withdrawn,
not deferred; authority is `ret-resolve-proposal-review.md` Round 1 finding 1, and the adjudication
is reversible (INFO-2 / INFO-3 in `.planning/INGEST-CONFLICTS.md`).

**Success Criteria** (what must be TRUE):
1. Kleene iteration of the monotone update over `tcRetTypes` converges, one pass per SCC in reverse
   topological order, and each of the nine measured crash shapes now reaches a verdict instead of a
   sort-mismatch crash. This is stated as a `tau^0`-biased update, not as a lattice join.
2. **SC1 holds**: only bare `TVar "?"` is refined. Named-hole types are retained and a concrete
   `tau^0` is never revised. A component with no concrete anchor stays bare-wildcard and keeps
   today's behavior.
3. **SC2' holds**: the pass is sandboxed and only the return-type map is extracted, so the type
   channel's accept/reject set and the sketch-hole registry are unchanged by construction, not by
   inspection.
4. **SC3' holds**: the if-join concrete-branch preference fires only when the wildcard branch's
   head calls a member of `SCC(f)`. The negative fixture `(if c (g x) 1)`, with `g` a different
   unannotated function, still synthesizes the wildcard.
5. **Gate**: `.fq` is byte-identical across all 128 corpus files with zero demotions, the same gate
   that refuted the withdrawn HOLE-RET. A demotion count above zero stops the phase rather than
   being explained.
6. Shipped per the Definition of Done above.

**Plans**: TBD

---

### Phase 3: Route type-derived facts through assume-guarantee (FACT-AG)

**Goal**: No fact derived from a type enters a VC antecedent unless the function that declared that
type has discharged it, carried on the existing assume-guarantee channel rather than asserted from
an annotation.
**Depends on**: Phase 1, Phase 2
**Requirements**: `REQ-fact-ag`
**Target version**: v0.14.76 (indicative)

⚠️ **Acceptance criteria are absent in the source.** The roadmap row records FACT-AG as research
track with no acceptance stated. The criteria below are derived goal-backward from the requirement
text; they are a starting point for `/gsd-discuss-phase`, not authority. Author acceptance before
planning this phase.

**Success Criteria** (what must be TRUE, pending acceptance authoring):
1. A type-derived fact reaching a VC antecedent is carried on the `consumed_guarantees` / §5.3.4
   meet channel, with the producer's verification status in the antecedent. Recording the channel
   alone is insufficient: the fact's truth depends on a producer whose annotation may never have
   been validated.
2. The criterion "contributes a VC assumption that no obligation discharges" is applied
   mechanically rather than by enumeration. The set of type-derived facts is re-derived from the
   emitter, so a fact class added later is caught by construction. (The `tau_ret` consumer count
   moved 1 → 2 → 4 → 4-plus-parameters across four review rounds, each increment found by reading;
   that is the argument for deriving the set rather than listing it.)
3. The reach beyond `bytes` and `map` is **measured and published**, because it is unmeasured
   today. The phase reports the classes it covered rather than claiming general closure.
4. WILD-ASSUME's two seams (`structuralUnify` for arguments, `compatibleWith` for returns and
   `checkExpr`) are reconciled with the general rule, so the approximation and the rule do not
   disagree about the same program.
5. Shipped per the Definition of Done above.

**Plans**: TBD

---

### Phase 4: Disclose what the verifier assumed and where it did not check

**Goal**: A consumer reading the obligation report can see every assumption the verifier relied on,
including the ones no obligation discharges, and gets warned at the contract-position reads the
verifier does not check.
**Depends on**: Phase 3
**Requirements**: `REQ-oblig-1-def-invariant`, `REQ-contract-read-lint-residual`
**Target version**: v0.14.77 (indicative)

These two requirements are grouped because both extend the same surface: what the report and the
diagnostics disclose about assumptions the verifier did not discharge. The Dafny-style
well-formedness item is itself a side-obligation, so it lands in the obligation machinery this
phase already touches.

⚠️ **Acceptance criteria are absent in the source for both requirements.** OBLIG-1-FOLLOWON records
only that it needs provenance tagging (hence a schema bump) and that an unverified invariant is a
TCB assumption. CONTRACT-READ-LINT records both tiers as deferred with no criteria. Author
acceptance before planning.

**Success Criteria** (what must be TRUE, pending acceptance authoring):
1. The obligation report's `assumptions` field carries `def-invariant` axioms alongside the shipped
   v1 (refinement predicates of in-scope refinement-typed params), v2a (let-definitional
   equalities), and v2b (match-scrutinee case hypotheses) provinces.
2. Each assumption carries provenance, and the report `schema_version` is bumped so a consumer can
   tell the pre-bump and post-bump shapes apart without guessing.
3. A reader can distinguish an unverified invariant from a discharged one, so a TCB assumption is
   visible in the artifact rather than implied by its absence.
4. `lintContractReads` emits `contract-read-oob` on the `map-get`-without-`map-has` shape, and the
   lint stays **non-blocking and report-only**: a report-only check that acquires blocking power is
   the defect pattern this project already recorded.
5. The Dafny-style well-formedness side-obligation fires on contract-position reads, and its
   decidable-slice boundary is stated in the diagnostic rather than left implicit.
6. Shipped per the Definition of Done above.

**Plans**: TBD

---

### Phase 5: MachineInt under QF-BV (INT-3)

**Goal**: A program can declare a machine-width integer type whose obligations are checked at that
width, instead of being idealized to unbounded integers by the QF-LIA fragment.
**Depends on**: Phase 4
**Requirements**: `REQ-int-3`
**Target version**: v0.15.0 (the milestone cut; marks the milestone boundary, not the size of this
item)

⚠️ **Scheduling flag.** The source records INT-3 as **dormant**: its stated acceptance is a
promotion condition (promote P3 to P1 only if INT-PRE shows a TOTP regression > 5x), and INT-PRE
cleared at 1.015x, so the gate never fired. Scheduling INT-3 into this milestone overrides that
recorded dormancy. It is sequenced last so that if the milestone shortens, this is what is lost
and the four preceding releases stand on their own.

**Success Criteria** (what must be TRUE):
1. `LLMLL.md` defines `MachineInt`: width, wrap semantics, and the boundary against the QF-LIA
   `int` fragment. This is the language-team design the requirement's acceptance names, and it
   lands before or alongside the implementation per the `[SPEC]` tagging rule.
2. A program declaring `MachineInt` emits QF-BV constraints and reaches a verdict.
3. A refute crux exists and kills: a fixture whose obligation holds over unbounded integers but
   fails at machine width is **refuted**, not reported SAFE. Without that fixture the phase has
   shown only that the new path does not crash.
4. The fragment boundary is a real boundary and not a global switch: `.fq` output is unchanged for
   corpus sources that do not use `MachineInt`.
5. Shipped per the Definition of Done above, cutting v0.15.0.

**Plans**: TBD

## Progress

| Phase | Plans Complete | Status | Target Version | Completed |
|-------|----------------|--------|----------------|-----------|
| 1. Close the map arm of WILD-ASSUME | 0/0 | Not started | v0.14.74 | - |
| 2. RET-RESOLVE SC3' | 0/0 | Not started | v0.14.75 | - |
| 3. FACT-AG | 0/0 | Not started | v0.14.76 | - |
| 4. Assumption and lint disclosure | 0/0 | Not started | v0.14.77 | - |
| 5. MachineInt under QF-BV | 0/0 | Not started | v0.15.0 | - |

Version targets are indicative. The binding rule is that each phase ships a monotonic bump above
the prior phase and that v0.15.0 marks milestone completion.

## Requirement Coverage

| Requirement | Phase |
|---|---|
| `REQ-wild-assume-2` | 1 |
| `REQ-ret-resolve` | 2 |
| `REQ-fact-ag` | 3 |
| `REQ-oblig-1-def-invariant` | 4 |
| `REQ-contract-read-lint-residual` | 4 |
| `REQ-int-3` | 5 |

6/6 mapped. The 39 deferred requirements in `.planning/REQUIREMENTS.md` are intentionally unmapped.
