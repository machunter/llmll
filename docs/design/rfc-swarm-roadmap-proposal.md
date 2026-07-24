---
name: rfc-swarm-roadmap-proposal
title: "RFC-SWARM: a swarm of agents implements a full RFC in LLMLL, verified"
status: "Rev 1.1: professor review folded (F-1..F-13, record in Appendix); TFTP target user-ratified 2026-07-24"
date: 2026-07-24
author: language-team
consumers: [professor, user, compiler-engineer, experiment-lead]
---

# RFC-SWARM: a swarm of agents implements a full RFC in LLMLL, verified

**Status: REVIEWED - professor findings folded; TFTP target ratified by user 2026-07-24**
(Rev 1.1, 2026-07-24; the professor review is folded into this document and the standalone
review file is retired; per-phase verdicts ACCEPT / ACCEPT-WITH-CHANGES, no redesign required;
full review record in the Appendix).

## Restatement

The project owner has set the terminal demonstration: a swarm of LLM agents implements a full RFC
in LLMLL, and the artifact is verified. The pieces exist separately: the spec-from-RFC pipeline is
complete and evaluated (R3, `docs/design/spec-from-rfc-pipeline.md` Rev 1;
`experiments/rfc1982-eval/findings.md`), emergent decomposition via cascading `refine` is complete
(`docs/design/cascading-refinement-proposal.md` Rev 8, Layers 1-4 shipped v0.14.13-53), two
emergent flagships exist (`examples/secure-channel-emergent/`, 25 fns / 7 modules;
`examples/token-revocation-emergent/`, 8 fns / 5 modules, contracts `:source`-derived), and the
empirical loop is closed (frontier agents one-shot the verified fragment;
`experiments/minimal-agent/SUMMARY.md`). What does not exist: a target RFC whose *whole* normative
surface has been dispositioned and carried; genuinely concurrent multi-agent operation on one
module tree; per-conjunct provenance at multi-clause scale; and a falsifiable measurement for a
demo whose agents are known not to fail. This proposal defines the acceptance criterion, selects
the RFC, enumerates the gaps by owner, and sequences the work. Rev 1 folds the professor review of
2026-07-24 (all seven MAJOR dispositions adopted; the claim wording, the pre-2119 normativity
rubric, the duplicate-ACK encoding, the spine channel model, the mutation-adequacy design, the
firewall scope, and the provenance default are all repaired below).

## Context located

1. `docs/compiler-team-roadmap.md:55`: R3 row: pipeline complete, gaps G2 (per-conjunct
   `:source`, deferred behind a schema-bump occasion) and G3 (accepted).
2. `docs/compiler-team-roadmap.md:146-158`: Data Scope Extension: Lever A complete
   (v0.14.33-51); Lever B (dependent-length lists) proposed; Lever C research-gated on LEAN-GA.
3. `docs/compiler-team-roadmap.md:161-189`: Cascading Refinement line complete; the standing
   evaluation-integrity rule (checkout brief is the sole channel, no forced failures, no hints).
4. `docs/compiler-team-roadmap.md:205,208,210`: R2 (self-hosted orchestrator, dormant), R5
   (`checkout --multi` + `diverge-report`, shipped v0.14.7-10), R8 (incremental patch re-verify,
   SHIPPED v0.14.61, slice = the singleton patched function).
5. `experiments/minimal-agent/SUMMARY.md:25-42`: the benchmark is saturated: 0 grade-A across 69
   attempts on the assume-guarantee ordering task; the verifier's error-catching value is
   established by construction (hand-written wrong fills refute), not by observed agent error.
6. `examples/secure-channel-emergent/README.md:48-52` (the per-fill acceptance bar: SAFE and
   body-faithful and not `termination_unverified`), `:65-68` (six leaf modules ran as parallel
   *independent* cascades; concurrency within one module tree has never been exercised), and
   `:114-131` (the results table). Citation split corrected per review F-9.1.
7. `examples/token-revocation-emergent/README.md:56-65`, `VERIFICATION_SCOPE.md`: the A4
   flagship: 9-clause S1 inventory (Q1-Q9, two dispositioned out); the frozen gate holds 9 cases
   composed of **5 refute cruxes plus 4 good twins expected SAFE** (corrected per review F-9.2;
   note the roadmap row at `compiler-team-roadmap.md:148` phrases this as "9 frozen cruxes",
   the same drift, routed to documentation-lead); 8/8 fills accepted within 2 attempts, one
   spontaneous agent-invented 2-function cascade.
8. `docs/design/spec-from-rfc-pipeline.md` §1.2 (C1-C6 taxonomy), §2 (`:source` is a
   traceability pointer, not a fidelity proof), §6 (G2 at `LLMLL.md:746`).
9. `docs/design/data-scope-extension.md:335-388`: the shipped wall: map keys `{int,string}`,
   values `{int,bool,string}`; `bytes[n]` length is a literal; no lists; string literals reflect
   (equality, distinctness, code-point length) but string structure does not.
10. `docs/design/strategic-positioning.md:16-18` (the differentiator: verification as the
    coordination protocol between agents), `:54-61` (the overclaim table), `:90-93` (the
    don't-say list). Citation corrected per review F-9.4.
11. `docs/design/agent-orchestration.md:20-28`: compiler owns verification primitives,
    orchestrator owns scheduling; R2 status: dormant, Phase 2 deferred on scope.
12. MEMORY / v0.14.64 (`docs/compiler-team-roadmap.md:242`): map-store conditional bodies now
    reflect body-faithfully (F-011.3); the Lever A residue named there is closed.
13. The professor review of Rev 0 (2026-07-24): folded into this document (full record in the
    Appendix; the standalone review file is retired); its literature anchors (HOL TCP, seL4,
    CompCert claim discipline; Alpern-Schneider; IronFleet; Verdi; Budd-Gopal and the
    mutation-adequacy line; DO-178C traceability) are cited inline below where the corresponding
    repair lands.

---

## 1. Goal statement: what "a swarm implements a full RFC, verified" means

The claim decomposes into four defined terms. Each is an acceptance criterion, not a slogan.

### 1.1 The completeness criterion: disposition ledger plus verified characteristic core

**Claim wording (review F-1, adopted).** The verification literature reserves "full RFC,
verified" for an encoded-only reading it will not grant here (HOL TCP claimed a validated
specification with enumerated deltas; seL4 and CompCert enumerate their assumption surfaces).
The external claim is therefore worded as the criterion actually is: **"every normative clause
dispositioned: verified, modeled, tested, or excluded with cause; the protocol core verified
body-faithfully"**, with the Encoded fraction reported as the *first number* in the writeup.
The disposition-ledger form matches certification traceability practice (DO-178C, Common
Criteria: every requirement dispositioned and traced, exclusions recorded). The phrase "full
RFC" survives only as the mission's internal shorthand for this criterion, never as the external
headline.

The unit of completeness is the S1 clause inventory (`spec-from-rfc-pipeline.md` §S1).
**Complete** means: every normative clause of the target RFC appears as an inventory row with
exactly one disposition, and the disposition set is closed at four members (review F-11 added
the fourth):

- **Encoded**: the clause is carried by a contract clause with `:source` provenance, and the
  carrying function reaches the tier §1.3 assigns to its class.
- **Deployment-modeled**: the clause is realized by a scoped model (the A4 precedent: Q8's
  `bytes[32]` fingerprint), with the modeling decision recorded in the inventory. Modeled rows
  carry refute cruxes like Encoded rows do (§1.4).
- **Vectored**: the clause is carried by a `check` block, executed rather than proved (the C5
  dynamic channel, `spec-from-rfc-pipeline.md` §1.2). Previously this channel overlapped the
  §1.3 table without a disposition of its own. RFC 1350 contains no test-vector appendix, so
  Vectored rows for this target are synthesized from prose examples or absent; Phase 0 records
  which, rather than discovering it mid-wave.
- **Dispositioned out**: the clause is excluded with an RFC-cited reason (C4 opaque primitive,
  C6 timing/liveness/transport). Exclusion is a recorded, auditable row, never a silent drop.

**Normativity rubric for pre-RFC-2119 prose (review F-2, adopted).** RFC 1350 is dated July
1992; RFC 2119 (the MUST/SHOULD/MAY convention) is March 1997, so the base RFC has no
requirement-keyword discipline and every normativity judgment on it is interpretive. Phase 0
therefore produces a written rubric, applied uniformly and recorded per row: normative =
imperative protocol behavior, packet-format definitions, explicit lowercase must/should;
non-normative = motivation, examples, historical mail-mode text. For sources that state a
keyword convention (RFC 1123 declares its uppercase usage in its introduction, so §4.2.3.1's
MUST is real), keywords map directly: MUST/SHALL to `pre`/`post` obligations (Encoded, each
refutable per §1.4), SHOULD to Encoded where decidable else Dispositioned out with the reason
naming the SHOULD, MAY to a recorded scope decision. The delta from every prior example is the
denominator: rfc1982 covered 9 clauses of a 5-page RFC, A4 covered a 9-clause *core* of RFC
7009/7662. Here the inventory must cover the whole RFC, and the inventory's own completeness is
defended by dual extraction (§3.2.3), not by a single audited pass.

**Descope boundary, two conditions (review F-1, adopted).** (a) Quantitative: if more than
roughly 30% of the inventory rows *classified normative under the rubric* disposition out, the
claim is not supportable for that RFC and the target must change (Phase 0 STOP line, §4.1).
(b) Qualitative, which dominates: a pre-registered **characteristic-core clause set** (the
clauses that make TFTP TFTP: the lock-step transfer discipline, block-number sequencing,
short-block termination, the error latch, the duplicate-ACK rule) may not contain any
dispositioned-out row, whatever the percentage says. The constant alone is arbitrary; the
constant plus the named-core invariant is defensible. The recommended target in §2 is chosen so
that the protocol core lands Encoded and the excluded set is confined to transport, timing, and
character-set translation.

### 1.2 "The swarm" = concurrent, role-separated, brief-only agents

- **N ≥ 4 concurrently operating agents** on one module tree, each fresh, stateless, and
  tool-disabled, coordinating *only* through the compiler's checkout/patch/refine protocol.
  This operationalizes the project's stated differentiator (verification as the coordination
  protocol, `strategic-positioning.md:18`): no shared conversational context, no message bus,
  no lead agent narrating. Prior waves were sequential within a module
  (`secure-channel-emergent/README.md:65-68`: parallel across modules, serial within); the swarm
  claim requires genuine intra-tree concurrency (§3.3).
- **Two agent roles**, firewalled in time:
  1. **Spec-extraction** (S1-S3 of the pipeline): an agent drafts the clause inventory and the
     root contracts from verbatim RFC text; the inventory's completeness is defended by **dual
     extraction** (a second, independent extraction performed blind to the first, reconciled,
     with the inter-extractor agreement reported; review F-10) and the clause-to-predicate
     fidelity by the pipeline §2 audit. The rfc1982 run was n=1 operator-executed
     (`findings.md`); EXT-AGENT-1 (§3.2.3) upgrades this.
  2. **Decomposition and fill** via `refine`/`patch`: blind agents against checkout briefs, the
     shipped discipline, unchanged.
  **The freeze firewall, scoped (review F-6, adopted).** The frozen set is the *clause-carrying*
  surface: the root contracts bearing `:source`, closed at Phase 1 acceptance, before any fill
  agent runs. `refine` necessarily grows the contract surface (that is its definition), so
  spawned sub-contracts are **additive, never edits**: they carry no `:source` (provenance
  authorship is the extraction role's monopoly, lint-enforced by RFC-COV-1: a `:source` string
  on a non-root contract is a lint error, §3.2.2), and they are governed by the shipped spawn
  gates (vacuity, feasibility, decomposition-trust meet;
  `cascading-refinement-proposal.md` Layer 3). Why this preserves the F-002 defense:
  assume-guarantee discharges a root's obligations *using spawned contracts as assumptions*
  (`FixpointEmit.hs:32-34` polarity), so weakening a spawned contract makes the root's VC
  harder to discharge, not easier; there is no laundering path from the spawn channel to the
  clause layer. `patch` fills only body-position holes by construction (`HoleAnalysis.hs:622`,
  the R8 soundness premise), and no edit to a `:source`-bearing contract is permitted mid-wave.
- **Repair** is not a separate role: retries with compiler error text only, **semantic retries
  ≤ 3 per hole**; protocol-level CAS retries are budgeted and counted separately (§3.3.1, review
  F-8), so concurrency cannot mechanically consume the agent's error budget.
- **Human touchpoints, exhaustively:** S0 fragment scoping (decided before authoring, per the
  pipeline), the dual-extraction reconciliation and S1-S3 audit, harness operation, and the
  post-wave refute layer (§1.4). Nothing else. Zero hints, zero forced failures, zero reference
  solutions: the evaluation-integrity rule (`compiler-team-roadmap.md:152-157`) is a hard
  constraint, and its audit trail is a deliverable.

### 1.3 "Verified" = tier assignment per clause class, with the strict bar on the core

Per-function tiers are the shipped evidence lattice (`LLMLL.md` §5.3.3/§5.3.5; trust report):

| Clause class (§1.2 of pipeline doc) | Disposition (§1.1) | Required tier |
|---|---|---|
| C1 state transition, C2 arithmetic invariant, C3 length/format | Encoded | **`verified`, body-faithful**, under `--strict-verified-core`; not `termination_unverified` |
| C4 opaque primitive | Deployment-modeled or Dispositioned out | `weakness-ok` with provenance-bearing reason (the accepted G3 convention) or `asserted` with `?proof-required`; enumerated in the trust report |
| C5 test vector | Vectored | `check` block, executed (`llmll test`, map/bytes evaluation shipped v0.14.63) |
| C6 excluded | Dispositioned out | inventory row only |

The per-fill acceptance bar is the secure-channel bar verbatim: verify SAFE, the filled function
in the body-faithful set, not flagged `termination_unverified`
(`secure-channel-emergent/README.md:48-52`). Whole-artifact acceptance: every module SAFE under
`--strict-verified-core`, including the import-linked spine (cross-module assume-guarantee,
XMOD-AG v0.14.17+), 100% effective `--spec-coverage` with every suppression citing the RFC.

**One disclosed trust boundary (review F-4, adopted).** The joint sender-receiver invariant is
carried by a ghost spine function on the product automaton (§2.1); its per-step preservation is
proved in `Σ_auto`, but the closure from per-step preservation to "holds on every reachable
trace" is a trace induction outside `Σ_auto`. That closure is recorded once, visibly, as the
demo's **trusted composition schema** (the IronFleet shape: Init and Inv-preservation proved as
lemmas, the temporal closure a small trusted step), a paragraph in the writeup and a candidate
Lean-tier item later. It is never silently absorbed into "verified".

### 1.4 "Demonstrated" = mutation adequacy plus process integrity, not agent failure

The benchmark is saturated (`SUMMARY.md:38`: 0 grade-A / 69 attempts); a demo premised on
catching agent error is unfalsifiable at the frontier tier. The measurable claims are instead:

1. **Mutation adequacy, not mutant existence (review F-5, adopted).** A single refuted mutant
   per clause is an existential criterion (it shows the contract excludes *one* wrong behavior);
   the mutation-testing lineage (Budd-Gopal specification mutation; the coupling-effect
   literature) and vacuity/coverage work in model checking say the mutant *class* determines
   what a kill means. Therefore: (a) a **mutant-class taxonomy per clause class**,
   pre-registered in Phase 0: C1 gets transition-retarget, arm-omission, and guard-inversion;
   C2 gets comparison-flip, off-by-one, and wrap-omission; C3 gets boundary ±1; historically
   attested bugs (Sorcerer's Apprentice here; the naive-`<` and goto-fail shapes as the
   register) are mandatory members. (b) The full **kill matrix is reported, survivors
   included**: an authored-but-surviving mutant is a finding (weak contract, or
   re-disposition), never silently dropped. (c) **Good twins** are retained (the A4 gate's
   composition: 5 refutes plus 4 good twins expected SAFE): the guard against over-strong
   contracts, the dual failure mode. (d) The refute requirement extends to
   **Deployment-modeled rows**, so a modeled clause cannot ship with zero evidence its model
   constrains anything. All frozen in `EXPECTED_VERDICTS.json` under `make refute-crux-gate`.
2. **Process integrity:** the audit trail shows every fill derived from brief-only input, with
   pre-registered budgets (semantic retries ≤ 3, protocol retries counted separately, human
   interventions = 0 post-freeze) met.
3. **Swarm viability:** intra-tree concurrency at N ≥ 4 completes without integrity violations,
   with conflict/retry metrics recorded against a pre-registered numeric fallback trigger
   (§3.3.1, §4.3).
4. **Contract tightness via divergence (review answer 2, adopted).** R5's `checkout --multi` +
   `diverge-report` runs on selected high-value holes: semantically distinct fills that all
   verify measure the slack the contracts leave, the one quantitative answer to "verified but
   vacuous" that requires no agent to fail. A measured axis, reported; not an acceptance
   criterion.

The external claim follows the positioning guardrails (`strategic-positioning.md:54-61,90-93`)
and the F-1 wording in §1.1: machine-auditable assurance of a swarm-built artifact, Encoded
fraction stated first, never "agents would have failed without us."

### 1.5 Degenerate inputs the criterion must classify (edge cases)

1. **A normative clause with only temporal content** ("retransmit until acknowledged"):
   disposition C6, out; but any per-event consequence of the rule (what the *sender* may not do
   on a duplicate ACK) is a separate Encoded row in disequality form (§2.1), and the emergent
   trace-level property the rule secures (no retransmission doubling) is its *own* row,
   dispositioned C6 or carried as a recorded informal derivation in the writeup, never claimed
   as verified (review F-3/F-4). Channel: inventory + human audit; the split is the S0 job.
2. **An Encoded clause whose only expressible contract is vacuous** (implication-only bool post):
   `--weakness-check` fires on this shape (F-1982-4, the mechanized floor); the clause must be
   re-dispositioned or its contract strengthened before freeze. Channel: contract + trust.
3. **Two concurrent `refine` requests spawning the same fresh name**: the second apply must fail
   its freshness check (Layer 2 condition (b), `cascading-refinement-proposal.md`) and retry
   under resync, never merge. Channel: protocol; positive witness required in the SWARM-1 test
   plan (§3.3).
4. **A fill agent writing a direct read on `(map-empty)` or a non-`{int,string}`-keyed map**
   (the deliberate Lever A residues, `data-scope-extension.md:335-342`): clean whole-function
   fallback to contract-only, which then *fails the body-faithful bar* and surfaces as a normal
   rejection with compiler text. Channel: contract; this is the designed behavior, not a gap.

---

## 2. Candidate RFC analysis

Constraints from the shipped fragment (`Σ_auto`, `LLMLL.md` §5.3.3/§5.3.5;
`data-scope-extension.md:335-342`): ints and bools; non-recursive ADTs of any arity; pairs and
`Result`; `bytes[n]` at literal length; `map` over `{int,string}` keys and `{int,bool,string}`
values; string literals (equality, distinctness, code-point length) but no string structure
(concat/substr/regex); no lists; recursion at partial correctness unless a `(decreases)` measure
discharges; no whole-structure equality. The selection bias this induces is explicit: favor
fixed-length data, enum state machines, and integer/modular arithmetic; avoid parsing-heavy and
crypto-cored RFCs.

### 2.1 RFC 1350 (TFTP, revision 2) + the RFC 1123 §4.2.3.1 amendment: **RECOMMENDED**

- **Size:** ~11 pages; estimated 20-30 normative clauses under the §1.1 rubric (packet-type
  table, lock-step transfer discipline, block-number sequencing, 512-byte block rule and
  termination, error semantics, TID and mode rules, the RFC 1123 duplicate-ACK amendment folded
  in as one imported clause, the Q8 precedent). Estimated 25-35 functions across 6-8 modules
  (packet model and validation, sender FSM, receiver FSM, block sequencing, termination, error
  latch, spine); larger than secure-channel-emergent's 25, so it advances the scale claim rather
  than repeating it.
- **Data-theory demands vs shipped fragment:** states are enums (C1, the tcp_rfc793 class);
  block numbers are 16-bit ints compared **by equality only** in the protocol core; data-block
  length is an int measure with the termination rule `len < 512` (C3, the Heartbleed length
  discipline: content opaque, length proved); buffers are `bytes[512]` with an int length field
  (fixed literal length, exactly the shipped bias); the mode field scopes to the `"octet"`
  string literal (STRLIT equality/distinctness shipped). **Nothing in `Σ_auto` needs to move.
  Lever B is not a prerequisite.** On block-number ordering (review F-3, adopted): RFC 1350
  defines **no order** on block numbers and does not define rollover (the wrap-to-0 vs wrap-to-1
  implementation divergence is famous); the core therefore never states an order, and if Phase 0
  wants one (e.g. "an already-acknowledged block"), it lands as a **Deployment-modeled row**
  with the modeling decision explicit. The RFC 1982 serial machinery is banked value available
  to such a row; it is not a license to import clauses the RFC does not contain. The wire
  format's variable-length NUL-terminated string fields (filename, mode spelling) are the one
  surface that dispositions out (string structure); the protocol core operates on decoded packet
  ADTs, a boundary the TFTP scope matrix states explicitly at S0 (the tcp_rfc793 scope,
  `examples/tcp_rfc793/VERIFICATION_SCOPE.md:1-23`, drew it implicitly via its enum-typed scope;
  review F-9.3).
- **State-machine shape and the famous bug (review F-3/F-4, adopted):** two coupled lock-step
  FSMs (sender, receiver) plus an error latch; discriminative contracts abound: accept ACK n
  only at n = current block; emit block n+1 only after ACK n; terminate exactly on a short
  block; nothing sent after error. The **Sorcerer's Apprentice Syndrome** fix (RFC 1123
  §4.2.3.1: the sender must not retransmit the current DATA packet in response to a duplicate
  ACK) is encoded **per event, in disequality form**: *on an ACK event whose block number
  differs from the block awaited, the transition emits no DATA*. Equality on ints, trivially
  QF-LIA, no ordering imported, cites the amendment clause verbatim. This is a state-event
  invariant, a safety property whose violation is a single transition (the Alpern-Schneider
  sense), so a transition-function post is a faithful encoding under the standard reading that
  the system's behaviors are the iterated applications of `step`; the writeup states that
  reading. The emergent property the fix exists to secure (no retransmission-doubling cascade)
  is trace-level and is **not claimed**: it gets its own inventory row (C6, or a recorded
  informal derivation), per §1.5.1.
- **The ghost spine and its channel model (review F-4, adopted):** the joint block-number
  agreement invariant is carried by a spine function stepping the sender-receiver product and
  carrying the coupling invariant in its post: the standard inductive-invariant method on the
  product automaton (the IronFleet lemma shape), not a hidden bisimulation; a
  refinement-mapping obligation would arise only if the demo claimed the deployed asynchronous
  pair refines the spine, and it does not claim that. Two mandatory disclosures: (a) **the
  spine's event alphabet includes duplicate delivery** (the Verdi fault-model point: a joint
  invariant proved under perfect lock-step delivery excludes every behavior where the famous
  bug lives, making the duplicate-ACK crux decorative); loss and timeout may remain C6. Phase 0
  fixes this alphabet. (b) The trace-induction closure is the disclosed trusted composition
  schema of §1.3. The joint invariant is expressible per-step in QF-LIA over enums and ints and
  is **not** scoped out as C6: it is the protocol's center.
- **Demo value:** a complete, universally recognized protocol; the §1.1 claim is supportable
  because the RFC is small enough that the inventory covers it, and the excluded set (timers,
  TID/port transport mechanics, netascii CR/LF translation, obsolete mail mode) is short,
  C6/C4-shaped, and citable row by row.
- **Risks:** netascii is arguably mandatory-to-support in a full implementation; under the §1.1
  rubric it lands as a normative row dispositioned C4 (opaque transform) or excluded with the
  mandatory-support caveat argued in the row (review F-13). The disposition must survive both
  §1.1 descope conditions; current estimate is that it does, comfortably, but Phase 0 exists to
  verify this before commitment.

### 2.2 Full RFC 7009 + 7662 (completing the A4 flagship): fallback / complement

- **Size delta over A4:** the residual clauses are Q5/Q9-class (HTTP response codes, client
  authentication) plus response-field enumeration (`scope`, `client_id`, `iat`, JSON encoding)
  and `token_type_hint` handling.
- **Assessment:** most of the residue is C4/C6 (HTTP encoding, credential machinery, JSON
  serialization: string structure). Completing it moves the inventory's Encoded fraction only
  marginally; the verified core *is already the A4 artifact*. As the swarm target it under-serves
  both halves of the claim: the "full" delta is mostly exclusions, and the module tree is too
  small (8 fns) to need a swarm. **Retain as the Phase-2 dry-run substrate** (§4.3): re-running
  the existing tree under the concurrent protocol is the cheapest swarm-viability test, with
  known-good expected verdicts.

### 2.3 RFC 6455 subset (WebSocket framing + §7.4 close codes): rejected

The §7.4 close-code state machine is a clean C1 second data point (the pipeline doc's own
alternate, `spec-from-rfc-pipeline.md` §4). But the framing layer stalls three ways: masking is
per-byte XOR (not in QF-LIA and not worth a bespoke theory), payload length is a 7/16/64-bit
variable encoding (bit-field extraction via div/mod chains at best, variable-length `bytes` at
worst: Lever B territory), and the opening handshake requires SHA-1/base64 (C4 wall). A "full
RFC 6455" claim is unreachable; a subset claim forfeits the mission's headline. Rejected as
target; §7.4 remains a candidate for a future second pipeline rerun, off this critical path.

### 2.4 RFC 5905 subset (NTP era/serial arithmetic): rejected

The era arithmetic is C2 and in-fragment, but RFC 5905 is ~110 pages of clock discipline,
filtering, and floating-point process description; a full-inventory disposition would be
dominated by exclusions (far past the quantitative descope line), and the subset framing fails
the completeness criterion by construction. The arithmetic value is already banked by rfc1982.

### 2.5 Recommendation

**RFC 1350 + the 1123 amendment.** It is the only candidate where "whole normative surface,
dispositioned" and "the verified fragment carries the protocol core with no language work" are
simultaneously true, and it adds scale (25-35 fns), concurrency surface (two FSMs + shared
modules), and a famous-bug refute story the project does not yet have. The review stress-tested
this selection and the rejections (F-13): adjacent candidates not discussed in Rev 0 do not beat
it (ARP/RFC 826 shares the pre-2119 prose problem with no famous refutable bug; UDP/RFC 768 is
too small to carry the claim and its ones-complement checksum is C4-shaped).

---

## 3. Gap analysis, by owner

### 3.1 Language / verification surface (owner: language-team → compiler-engineer)

**Required by the recommended RFC: nothing.** This is a deliberate outcome of §2's selection, and
it should be defended against scope creep: every clause class TFTP's core needs (C1 enums and
sums, C2 ints under equality, C3 length measures, `bytes[n]` literal-length buffers, STRLIT
tags) is shipped and evaluated. The v0.14.64 map-conditional fix closed the last known Lever A
behavioral residue.

**Nice-to-have, explicitly not on the critical path:**
- **Lever B (dependent-length lists / symbolic `bytes` length)**
  (`compiler-team-roadmap.md:149`): would let the data block be `bytes[len]` with symbolic `len`
  instead of `bytes[512]` + an int length field. The modeling dodge is standard (the Heartbleed
  flagship used it) and costs nothing in refutability. Lever B stays sequenced after this
  demonstration, pulled forward only if Phase 0 finds a clause that cannot be stated without it
  (none is currently foreseen).
- **Whole-structure equality, string concat/substr:** not needed; wire-format clauses that would
  need them disposition out at S0.

**Watch item (spec-drift class):** fill agents at 25-35-fn scale will explore more of the map/
bytes surface than 8 fills did; the deliberate residues (`map-empty` direct reads,
non-`{int,string}` keys) surface as body-faithful-bar rejections (§1.5.4). If wave telemetry
shows a residue rejected repeatedly, that is the empirical promotion signal for the specific
residue, routed as a normal roadmap row, not a prerequisite.

### 3.2 Pipeline (owner: language-team / compiler-engineer / experiment-lead)

1. **SRC-CONJ-1 is the default path, decided before S3 authoring (review F-7, adopted).** G2
   (per-conjunct `:source`, `spec-from-rfc-pipeline.md` §6, `LLMLL.md:746`) becomes live at this
   scale: rfc1982 dodged it structurally (one `pre` per function); a 25-35-fn artifact will have
   functions whose precondition draws on two clauses, and the drop makes the clause-coverage
   audit lossy exactly where the completeness claim needs it. The traceability literature is
   unambiguous (DO-178C bidirectional many-to-many trace data; CC ADV correspondence; seL4's
   semantically organized spec): finer provenance belongs in the *artifact*, and restructuring
   code to make trace links singleton is architecture distortion. Therefore **SRC-CONJ-1 [CT]**
   (per-conjunct provenance list on `pre`/`post`; JSON-AST schema delta + `--trust-report`/
   sidecar threading, the schema-bump occasion G2 waited for) is the **default**, and its fate
   is decided **before S3 root authoring begins**: the sequencing hazard is that roots authored
   under the splitting discipline invite re-authoring if SRC-CONJ-1 lands later. The
   contract-splitting fallback (one clause per function) is demoted to a **mechanically
   enforced emergency mode**: if taken, RFC-COV-1 *fails* on any multi-clause `pre`/`post`
   lacking per-conjunct provenance, and the writeup states that clause coverage is
   function-granularity rather than conjunct-granularity.
   **STATUS: SHIPPED v0.14.65 (2026-07-24, commits 5b913f9 + b0e3296).** The go/no-go resolved
   GO before any root authoring; the splitting fallback never activates. Per-conjunct
   provenance is live: repeated `pre`/`post` clauses each keep `:source`, JSON-AST 0.9.0
   `pre_clauses`/`post_clauses`, trust-report `pre_sources`/`post_sources` in author order
   (RFC-COV-1's index surface), sidecar `sources`, all-conjuncts-sourced vouched rule.
2. **Clause-coverage adequacy is currently hand-audited.** `--spec-coverage` measures
   functions-with-contracts; no tool measures clauses-with-contracts
   (`spec-from-rfc-pipeline.md` §S1). Mint **RFC-COV-1 [CT]**: a syntactic lint/report that
   cross-references the persisted S1 inventory against the module's `:source` strings both ways
   (with SRC-CONJ-1: every Encoded row cited by ≥ 1 *conjunct* and every conjunct's citation
   resolving to an inventory row), **fails** on a multi-clause contract without per-conjunct
   provenance when the fallback mode is active (F-7), and **fails** on any `:source` string
   appearing on a non-root contract (the extraction-role provenance monopoly, F-6). No solver,
   no fidelity claim (that stays with the §2 human audit and F-002's settled limit: the
   self-attestation channel has no per-instance oracle, `LLMLL.md` §4.4.6). The lint makes the
   *denominator* mechanical; fidelity remains human-audited plus mutation-refuted.
3. **The inventory's completeness defense is dual extraction (review F-10, adopted).**
   **EXT-AGENT-1 [EXP]**: a blind agent executes S1-S3 for the target RFC from verbatim source
   text (F-1982-5 input discipline), and a **second independent extraction** (human, or a second
   blind agent) is performed *before seeing the first*; the two inventories are reconciled and
   the inter-extractor agreement reported as a statistic. This converts the audit from "were
   the deltas heavy" into a quantitative completeness argument for the denominator, at near-zero
   extra cost. If agent-side extraction quality is poor, the demo's claim downgrades from
   "agent-extracted, dual-checked" to "human-extracted, dual-checked" for this iteration,
   recorded; the swarm claim rests on the fill side and survives either outcome.
4. **Hint leakage through `:source` prose:** contracts (and thus briefs) carry `:source`
   strings; the extraction role writes them. The paraphrase must state the *requirement* (which
   the predicate already states formally), never solution shape. Add this as an audit checklist
   line in the operation manual; it is a rule, not a mechanism.

### 3.3 Orchestration (owner: experiment-lead, with one [CT] item)

What the swarm needs that single-agent cascading refine did not:

1. **Concurrent checkout on one tree, with the soundness argument stated (review F-8,
   adopted).** The substrate exists: advisory locks, checkout tokens, compare-and-swap resync on
   `patch`/`refine` (`cascading-refinement-proposal.md` Layer 2, `:127-131`;
   `examples/withdraw-demo/` concurrency model). Mint **SWARM-1 [DESIGN+EXP]**, whose design
   note states, rather than leaves implicit: applies are serialized, so there is a
   linearization; the CAS refuses stale tokens fail-closed; under the scoped freeze (§1.2) a
   CAS-refused `patch` may be **re-applied verbatim after resync without re-prompting the
   agent**, because its verdict depends only on contracts (the R8 premise: body-position holes
   over assume-guarantee-modular VCs); `refine` must resync fully; stale briefs err in the
   conservative direction (a brief can be missing newly spawned callees); and the
   decomposition-trust meet is interleaving-insensitive because serialized applies produce the
   same final tree. **Token granularity:** as shipped the CAS token is tree-global (any
   structural commit invalidates all outstanding tokens), so at N agents the conflict rate
   approaches one invalidation per apply and optimism degenerates to
   serialize-with-re-checkout; SWARM-1 either **pre-registers that expectation** (wall clock
   still wins while model inference dominates) or narrows token scope to the checked-out hole
   plus its contract closure, and the narrowing requires a short soundness note (it is exactly
   the R8 premise, available for `patch`, **not** available for `refine`). **Retry accounting:**
   protocol (CAS) retries are budgeted and reported separately from semantic retries (≤ 3 per
   hole). The protocol also covers conflict policy, retry/backoff, spawned-name freshness under
   concurrency with the §1.5.3 positive witness, and deterministic audit ordering; implemented
   in `audit/runner.py` / `tools/llmll-orchestra`, in Python. **No compiler change is
   expected**; the orchestrator absorbs retries (the boundary of
   `agent-orchestration.md:20-28` holds).
2. **Merge does not exist and must not be built.** Concurrent fills touch disjoint body holes;
   apply is serialized; there is no textual merge problem by construction. The one collision
   class is refine-spawned names (§1.5.3), handled by freshness-check-then-retry.
3. **Incremental re-verify: R8 covers `patch`, not `refine`.** R8's shipped slice (v0.14.61) is
   sound because `patch` fills body holes over assume-guarantee-modular VCs; `refine` *grows the
   module*, so it re-typechecks and re-verifies whole (`cascading-refinement-proposal.md` Layer
   1, the named structural cost). At 30+ fns × N agents this multiplies. **Measure first** (the
   R8 lesson: the latency benchmark was deferred residue precisely because correctness shipped
   without it): mint **REFINE-SLICE-1 [CT], contingent** on Phase 2 telemetry showing refine
   re-verify dominating wall clock; the plausible slice (patched function + spawned functions +
   nothing else, since spawns are fresh and contracts elsewhere unchanged) needs its own
   soundness note before implementation.
4. **Divergence (R5) is a measured axis on selected holes (upgraded from stretch; review answer
   2).** `checkout --multi` + `diverge-report` (v0.14.7-10) runs redundant fills on selected
   high-value holes; the divergence statistic is the contract-tightness observable of §1.4.4.
   Reported, budget-bounded, still not an acceptance criterion.
5. **R2 (self-hosted orchestrator) stays dormant.** The Python harness is the shipped, audited
   instrument; rewriting it in LLMLL is a self-hosting flourish orthogonal to every acceptance
   criterion here (see §5).

### 3.4 Evaluation (owner: experiment-lead)

1. **The falsifiable measurement set** (given saturation, §1.4): (a) the mutation kill matrix
   (per-class taxonomy, survivors reported, good twins, Deployment-modeled rows included;
   §1.4.1), frozen and CI-gated; (b) pre-registered process budgets met (semantic retries,
   protocol retries counted separately, zero post-freeze human touches, brief-only channel),
   with the full prompt/reply/verdict trail published as in both emergent flagships; (c)
   swarm-concurrency telemetry (conflict rate, CAS retries, wall clock) against the sequential
   baseline of the Phase 2 dry-run, judged by a **pre-registered numeric fallback trigger**
   (review F-8: e.g. wall clock ≥ the sequential baseline, or conflict-retry fraction above a
   stated bound; the exact numbers are fixed in Phase 0, not post hoc); (d) the R5 divergence
   statistic on selected holes (§3.3.4). Pre-registration happens in Phase 0, before any agent
   runs.
2. **The integrity rule gains a new surface** at swarm scale: concurrent agents must not see one
   another's rejected attempts (each retry prompt carries only that agent's own error text). The
   runner enforces per-agent isolation; the audit trail must make cross-contamination checkable.
3. **What the demo does not claim:** that agents would have failed unverified (unfalsifiable
   here); that `:source` proves fidelity (§2 of the pipeline doc); that the trace-level
   no-doubling property is verified (§2.1: its row is C6 or an informal derivation); that the
   trace-induction closure is machine-checked (it is the disclosed trusted schema, §1.3); or
   that contract quality in the middle of the refinement tree is certified (the secure-channel
   scope note: observed, not certified; the vacuity/feasibility gates remove the emptiest
   failure modes, the root contracts and the refute layer carry the ends).
4. **Optional appendix arm: a weaker model tier (review F-12, accepted).** Same briefs, same
   protocol, a deliberately weaker model population, results reported separately as an appendix.
   This is the cheap route to converting the safety net's value from by-construction to
   observed-at-least-once, and it does not violate the no-forced-failure rule (a weaker model is
   a different population, not a rigged input). Outside the acceptance criteria, off the
   headline, budget-permitting.

---

## 4. Sequenced workstreams

Effort classes: S = days, M = 1-2 weeks, L = multi-week.

### Phase 0: Target ratification and scope freeze [SPEC][DESIGN] (S-M)

- S0 + S1 for RFC 1350 (+ RFC 1123 §4.2.3.1): the **normativity rubric** for pre-2119 prose
  written first and applied per row (F-2); full clause inventory, every row dispositioned per
  §1.1's four-member set, with the Vectored channel's emptiness-or-synthesis recorded (F-11);
  the **characteristic-core clause set** named and pre-registered (F-1); the **spine channel
  model** fixed (event alphabet includes duplicate delivery; loss/timeout C6) (F-4); the
  duplicate-ACK crux stated in disequality form in the crux plan (F-3); module architecture
  sketch (6-8 modules, root contract skeletons); the netascii / mode / TID disposition decisions
  written with RFC citations; the decoded-ADT wire-format boundary stated explicitly in the
  scope matrix (F-9.3).
- Pre-registration: acceptance criteria (§1), budgets and the numeric concurrency fallback
  trigger (§3.4.1), the measurement set, the **mutant-class taxonomy** per clause class with
  mandatory historically-attested members (F-5), and the dual-extraction procedure (F-10).
- **Acceptance:** persisted `VERIFICATION_SCOPE.md`-style inventory at 100% clause coverage
  under the rubric, dual-extracted and reconciled with the agreement statistic recorded;
  professor review of the criterion mapping; user sign-off on the target.
- **STOP/descope:** if > ~30% of rubric-normative rows disposition out, **or any
  characteristic-core clause dispositions out**, or a core clause turns out inexpressible
  without Lever B, halt and re-target (candidate queue: §2.2's completion framing with reduced
  headline, or a re-scoped claim). Do not widen `Σ_auto` to rescue the target.

### Phase 1: Pipeline hardening [CT][EXP] (M; parallel with Phase 2, but SRC-CONJ-1 decided before S3 authoring)

- **SRC-CONJ-1 [CT]** (M): per-conjunct `:source` provenance, the **default path** (the G2
  close-out; JSON-AST schema delta, trust-report/sidecar threading). **SHIPPED v0.14.65**
  (2026-07-24; go/no-go resolved GO before any root authoring, per §3.2.1's status note); the
  splitting fallback never activates and RFC-COV-1 lints at conjunct granularity.
- **RFC-COV-1 [CT]** (S): the inventory↔`:source` cross-check lint (§3.2.2), including the
  fallback-mode failure and the `:source`-on-roots-only monopoly check (F-6/F-7). Syntactic, no
  solver.
- **EXT-AGENT-1 [EXP]** (S): blind-agent S1-S3 plus the independent second extraction and
  reconciliation; the agreement statistic is the finding (§3.2.3).
- **Acceptance:** target roots authored under the decided provenance mode, every contracted
  clause carrying resolvable provenance at the mode's granularity, RFC-COV-1 green, the
  clause-carrying surface frozen (the §1.2 scoped firewall). Roots verify at contract level and
  classify `contract_fragment: qf_lia` (the A4 Phase-2 gate, reused verbatim).
- **STOP/descope:** EXT-AGENT-1's agent arm failing does not block; it downgrades the
  extraction-role claim (§3.2.3) and the wave proceeds on dual-checked human extraction.

### Phase 2: Swarm protocol, proven on a known tree [DESIGN][EXP][CT-contingent] (M)

- **SWARM-1 [DESIGN+EXP]** (M): the concurrency protocol note (explicit soundness argument,
  token-granularity resolution, separated retry budgets; §3.3.1) + runner implementation;
  positive-witness test for the spawn-name collision (§1.5.3).
- **Dry run:** re-run the `token-revocation-emergent` tree (known-good expected verdicts) under
  N ≥ 4 concurrent agents; compare against the sequential baseline; record conflict/latency
  telemetry against the Phase 0 numeric trigger.
- **REFINE-SLICE-1 [CT], contingent** (M if triggered): only if dry-run telemetry shows refine
  re-verify dominating; requires its own soundness note first (§3.3.3).
- **Acceptance:** dry-run tree reaches the same verdicts as the sequential record, zero
  integrity violations, telemetry published.
- **STOP/descope:** if the **pre-registered numeric trigger** fires (wall clock ≥ sequential
  baseline, or conflict-retry fraction above the Phase 0 bound), ship the swarm as
  parallel-per-module cascades (the secure-channel shape) with the limitation stated in the demo
  writeup; on a 6-8 module tree, N ≥ 4 concurrent per-module cascades remains a defensible
  swarm; only the intra-tree half of the claim is sacrificed, and neither the completeness nor
  the verified half.

### Phase 3: The wave [EXP] (M)

- Blind swarm fills the frozen TFTP roots under the Phase 2 protocol; per-fill bar per §1.3;
  semantic retries ≤ 3 with error-text-only feedback, protocol retries counted separately; full
  audit trail.
- **Acceptance:** whole artifact SAFE under `--strict-verified-core`; all Encoded-clause
  functions body-faithful; budgets met; audit trail complete.
- **STOP/descope:** a hole that exhausts retries is a *finding* (routed to compiler-engineer or
  back to Phase 0's inventory as a scoping error), never a hint occasion. If ≥ 3 holes exhaust,
  pause the wave and adjudicate before continuing; do not lower the bar mid-wave.

### Phase 4: Refute layer, freeze, and writeup [EXP][SPEC] (S-M)

- Execute the Phase 0 mutant taxonomy: per-class mutants for every Encoded **and
  Deployment-modeled** row (the duplicate-ACK crux mandatory); freeze `EXPECTED_VERDICTS.json`;
  wire `make refute-crux-gate`; good twins stay SAFE in the same gate; the **full kill matrix
  is reported, survivors included**, each survivor adjudicated as weak-contract-fixed or
  re-dispositioned (F-5).
- Demo document: inventory with the Encoded fraction stated first (F-1), tier table, kill
  matrix, process metrics, the integrity trail, the trusted-composition-schema disclosure
  (F-4), and the §1.4 claim discipline.
- **Acceptance:** every Encoded and Deployment-modeled clause has its taxonomy mutants
  authored, the kill matrix frozen and green in CI (survivors resolved); writeup passes the
  positioning guardrails review.
- **STOP/descope:** a clause with no constructible refuting mutant is re-audited: either the
  contract is weak (fix and re-verify, a recorded co-evolution exhibit per the pipeline's S4.4)
  or the clause is re-dispositioned; neither silently ships.

Dependency summary: Phase 1 and Phase 2 are independent of each other, except that SRC-CONJ-1's
go/no-go precedes S3 root authoring; Phase 3 requires 0, 1, 2; Phase 4 requires 3. Existing tags
reused: R3 (pipeline, complete: this consumes it), R5 (measured-axis lane), R8 (shipped;
REFINE-SLICE-1 is its refine-side sibling), XMOD-AG, STRLIT, Lever A. New tags minted:
SRC-CONJ-1, RFC-COV-1, SWARM-1, REFINE-SLICE-1 (contingent), EXT-AGENT-1.

---

## 5. What NOT to do

1. **Do not put Lever B (or C) on the critical path.** No clause in the recommended target needs
   dependent-length lists; induction (Lever C) is research-gated on LEAN-GA and unlocks nothing
   this demo requires. Widening `Σ_auto` to rescue a target RFC inverts the selection logic:
   choose the RFC to fit the shipped fragment, and let *wave telemetry* (not anticipation)
   promote residues.
2. **Do not build a bespoke multi-agent framework, and do not activate R2.** The
   compiler-owns-verification / orchestrator-owns-scheduling boundary
   (`agent-orchestration.md:20-28`) is correct; the Python runner plus checkout/patch/refine is
   the entire coordination substrate the differentiator claim needs. A message bus, agent
   registry service, or LLMLL-self-hosted orchestrator each adds surface without adding to any
   acceptance criterion.
3. **Do not choose a parsing-heavy RFC.** URI syntax, HTTP field grammar, JSON serialization,
   WebSocket masking: each stalls on string structure or bitwise theory and converts the demo
   into a language-extension campaign. The wire-format boundary (decoded ADTs in, S0-recorded
   parsing exclusion) is stated explicitly in the Phase 0 scope matrix and holds here.
4. **Do not let the clause-carrying surface stay editable during the wave.** The scoped freeze
   firewall (§1.2) is what keeps F-002's self-attestation limit from becoming a live laundering
   channel: `:source`-bearing root contracts are immutable post-freeze, and spawned
   sub-contracts are additive, `:source`-free, and spawn-gate-governed, never edits to the
   clause layer. A "the fill agent proposes a contract fix" loop, however tempting
   operationally, reopens the laundering channel.
5. **Do not frame the demo as verification catching agent error.** Saturation says the frontier
   tier will likely produce correct fills; a demo that needs agent failure will not get it. The
   claim is assurance and auditability of a swarm-built artifact (§1.4); the refute layer, not
   agent behavior, carries the deterministic guarantee. (The F-12 weaker-model arm is an
   appendix observation, not the frame.)
6. **Do not ship an existential refute layer.** One mutant per clause is the move a reviewer
   dismantles with "why *that* mutant" (F-5); the taxonomy, the kill matrix with survivors, and
   the good twins are the difference between a count and a claim. Do not skip them to ship
   faster, and do not omit the Deployment-modeled rows from the gate.

---

## 6. Questions resolved by the review; decisions standing for adjudication

Rev 0's five professor questions are answered in the review record (Appendix, "The review's
answers") and folded as follows; none remains open for the professor.

1. **Completeness criterion** → defensible as criterion, not as headline; reworded with the
   characteristic-core condition (§1.1; F-1, F-2).
2. **Measuring a saturated process** → no off-the-shelf methodology exists; the set is right in
   kind, upgraded in degree (mutation-adequacy design §1.4.1; R5 divergence promoted to a
   measured axis §1.4.4/§3.3.4; F-12's weaker-model appendix arm §3.4.4).
3. **Temporal flattening** → sound as a per-event safety encoding under the iterated-step
   reading; restated in disequality form; the trace-level no-doubling property is not claimed
   (§2.1; F-3, F-4).
4. **Coupled FSMs** → ghost spine is the accepted inductive-invariant idiom; adopted with the
   two disclosures (duplicate delivery in the event alphabet; the trace-induction closure as the
   disclosed trusted schema) (§1.3, §2.1; F-4).
5. **Provenance granularity** → artifact-side provenance wins; SRC-CONJ-1 is the default,
   decided before S3; splitting is a lint-enforced emergency mode (§3.2.1; F-7).

**The two decisions the review flagged as must-not-slip, as they now stand:** SRC-CONJ-1 is the
default provenance path with its go/no-go scheduled before root authoring (§3.2.1, §4.2); the
spine's channel model includes duplicate delivery in its event alphabet, fixed at Phase 0
(§2.1, §4.1). Both are ADOPTED without dispute; the user adjudicates the revision as a whole.

---

## Appendix: professor review record (Rev 0 review, folded 2026-07-24)

> Rev 0 was reviewed by the professor (outside-PL metatheory and formal-methods persona) on
> 2026-07-24. The standalone review file is retired; this appendix is the surviving record. The
> reviewer verified the proposal's claims against the repo before critiquing (four citation
> drifts found, F-9, fixed in this revision). Verdict in one line: "the architecture is sound
> and the target is right; the headline wording, the normativity rubric for a pre-1997 RFC, the
> duplicate-ACK formalization, and the provenance default all need repair before Phase 0
> executes." No redesign was required; the two decisions flagged as must-not-slip (SRC-CONJ-1's
> default status, the spine's channel model) are fixed in §3.2.1 and §2.1/Phase 0.

### Per-phase verdicts

- **Phase 0: ACCEPT-WITH-CHANGES.** Add the normativity rubric (F-2), the disequality
  restatement of the duplicate-ACK crux (F-3), the spine channel-model decision (F-4), dual
  extraction (F-10), the disposition-set repair (F-11); pre-register the reworded headline (F-1)
  and the mutant taxonomy (F-5).
- **Phase 1: ACCEPT-WITH-CHANGES.** SRC-CONJ-1 default, decided before S3 authoring; splitting
  fallback lint-enforced; RFC-COV-1 polices the `:source`-on-roots-only monopoly (F-6, F-7).
- **Phase 2: ACCEPT-WITH-CHANGES.** SWARM-1 states the soundness argument explicitly, resolves
  token granularity, separates protocol from semantic retry budgets, pre-registers a numeric
  fallback trigger (F-8). The dry-run-on-known-tree design is right.
- **Phase 3: ACCEPT.** The discipline is the shipped, audited practice; its one defect (the
  firewall wording) is repaired upstream by F-6. The STOP conditions are adequate.
- **Phase 4: ACCEPT-WITH-CHANGES.** Per-class mutant taxonomy, Deployment-modeled rows in the
  gate, kill matrix with survivors, good twins retained (F-5); writeup carries the
  trusted-schema note (F-4) and the claim wording (F-1).

### Fold ledger

Dispositions: ADOPTED / ADOPTED-MODIFIED / DISPUTED. No finding is DISPUTED.

| Finding | Disposition | Where it landed |
|---|---|---|
| F-1 (MAJOR, headline vs criterion) | ADOPTED | §1.1 claim wording + characteristic-core set; §1.4 tail; Phase 0/4 |
| F-2 (MAJOR, pre-2119 normativity) | ADOPTED | §1.1 rubric; descope restated over rubric-normative rows; Phase 0 |
| F-3 (MAJOR, duplicate-ACK ordering) | ADOPTED | §2.1 disequality form, no imported order; ordering only as a Deployment-modeled row; §1.5.1 |
| F-4 (MAJOR, safety flatten + spine disclosures) | ADOPTED | §1.3 trusted composition schema; §2.1 event alphabet incl. duplication, no-doubling not claimed; §3.4.3; Phase 0 |
| F-5 (MAJOR, mutation adequacy) | ADOPTED | §1.4.1 taxonomy / kill matrix with survivors / good twins / modeled rows; §5.6; Phase 0 + Phase 4 |
| F-6 (MAJOR, freeze vs refine) | ADOPTED | §1.2 scoped firewall + anti-laundering argument; RFC-COV-1 monopoly lint §3.2.2; §5.4 |
| F-7 (MAJOR, SRC-CONJ-1 default) | ADOPTED | §3.2.1 default + pre-S3 decision + lint-enforced fallback; Phase 1 |
| F-8 (MINOR, swarm protocol specifics) | ADOPTED-MODIFIED | §3.3.1 soundness argument + token granularity (pre-register expectation, narrowing optional with soundness note) + split retry budgets; numeric trigger §3.4.1 + Phase 2 STOP |
| F-9 (MINOR, citation drift ×4) | ADOPTED | Context items 6, 7, 10; §2.1 tcp_rfc793 boundary; roadmap:148 same-drift note routed to doc-lead (Context 7) — **CLOSED**: fixed in commit b0e3296 (v0.14.65 doc pass) |
| F-10 (MINOR, dual extraction) | ADOPTED | §1.2 role 1; §3.2.3 EXT-AGENT-1 upgraded; Phase 0/1 |
| F-11 (MINOR, C5 disposition) | ADOPTED-MODIFIED | §1.1 fourth disposition **Vectored** (option (a) of the finding); §1.3 table column; Phase 0 records vector emptiness/synthesis |
| F-12 (OBSERVATION, weaker-model arm) | ADOPTED (as optional) | §3.4.4 appendix arm, off headline, outside acceptance criteria; §5.5 note |
| F-13 (OBSERVATION, candidate stress-test) | ADOPTED | §2.5 (ARP/UDP noted); §2.1 risks (netascii under the rubric) |

Also folded from the review's Answers: Answer 2's R5-divergence promotion (§1.4.4, §3.3.4) and
Answer 6's protocol-soundness statement (§3.3.1). Handled per the spec-drift discipline: the
`compiler-team-roadmap.md:148` "9 frozen cruxes" phrasing shares the F-9.2 drift and is routed
to documentation-lead (Context item 7).

### Finding record (condensed from the review)

- **F-1 (MAJOR, claim discipline).** "Full RFC, verified" parses as "all normative requirements
  verified" and is false under its natural reading when up to ~30% of clauses may disposition
  out. The disposition-ledger criterion matches certification practice (DO-178C, Common
  Criteria: every requirement dispositioned and traced, exclusions recorded), but the
  verification literature reserves such headlines for the encoded surface: HOL TCP (Bishop et
  al., SIGCOMM 2005; "Engineering with Logic", J. ACM 2019) claimed a validated specification
  with enumerated deltas, never "full RFC 793, verified"; seL4 (Klein et al., SOSP 2009)
  enumerates its assumption list; the TLS 1.3 analyses (Cremers et al., CCS 2017; Bhargavan et
  al., S&P 2017) claim properties of a model; CompCert names its unverified parts. Secondary
  attack surfaces: the 30% ceiling is an unprincipled constant, and the denominator is produced
  in-project (F-10). Repair: reword, Encoded fraction first, characteristic-core set beside the
  ceiling.
- **F-2 (MAJOR, criterion well-formedness).** RFC 1350 (July 1992) predates RFC 2119 (March
  1997): it has no requirement-keyword discipline, so a MUST-based ceiling has no well-defined
  extension on it (RFC 1123 states its own uppercase convention, so the amendment side is fine).
  Repair: a written normativity rubric for pre-2119 prose, applied uniformly per row; the
  ceiling restated over rubric-normative rows.
- **F-3 (MAJOR, formalization soundness).** Rev 0's crux form "on ACK m with m < current, emit
  nothing" presupposed a total order on wrapping 16-bit block numbers that RFC 1350 never
  defines (rollover itself is a famous implementation divergence: wrap to 0 vs 1); importing RFC
  1982 serial comparison would be a modeling invention with an empty `:source`. The order is
  also unnecessary: RFC 1123 §4.2.3.1 is per-event disequality (the sender awaiting block n
  retransmits on timeout only, never in response to an ACK whose block number differs). Repair:
  disequality form; any ordering becomes a Deployment-modeled row.
- **F-4 (MAJOR, soundness / claim discipline).** The per-event flatten is sound: a state-event
  invariant is a safety property whose violation is a single transition (Alpern-Schneider, IPL
  1985 / Dist. Comp. 1987), faithfully encoded as a transition post under the standard
  iterated-step reading. The emergent no-doubling property (Sorcerer's Apprentice absence) is a
  quantitative trace property reachable only by trace induction outside `Σ_auto`: not claimed,
  dispositioned as its own row. The ghost spine is the accepted product-automaton
  inductive-invariant idiom (IronFleet's Init/Inv/Next lemma shape, Hawblitzel et al., SOSP
  2015), not a hidden bisimulation; refinement-mapping obligations (Abadi-Lamport, TCS 1991)
  arise only if the deployed asynchronous pair is claimed to refine the spine, which the demo
  does not claim. Two mandatory disclosures: the spine's event alphabet must include duplicate
  delivery, or the joint invariant is proved over a model excluding the famous bug (Verdi's
  fault-model point, Wilcox et al., PLDI 2015); the trace-induction closure is recorded as the
  disclosed trusted composition schema.
- **F-5 (MAJOR, evaluation methodology).** One refuted mutant per clause is an existential
  criterion; mutant choice determines what a kill means (Budd-Gopal 1985 specification
  mutation; Andrews-Briand-Labiche, ICSE 2005, and Just et al., FSE 2014, on mutant-fault
  coupling; the vacuity/coverage line in model checking, Beer et al.;
  Chockler-Kupferman-Vardi). Repair: pre-registered per-class mutant taxonomy with mandatory
  historically-attested members, full kill matrix with survivors reported, good twins retained
  (the guard against over-strong contracts), Deployment-modeled rows in the gate.
- **F-6 (MAJOR, internal consistency / trust model).** Rev 0's blanket "no contract edit
  mid-wave" firewall forbade the refine mechanism the wave relies on. Repair: freeze the
  `:source`-bearing root layer only; spawns are additive, `:source`-free, spawn-gate-governed.
  Anti-laundering holds because assume-guarantee discharges a root's obligations using spawned
  contracts as assumptions: weakening a spawn makes the root's VC harder, not easier.
- **F-7 (MAJOR, traceability / sequencing).** Requirements-tracing practice (DO-178C
  bidirectional many-to-many trace data; Common Criteria ADV correspondence; seL4's
  semantically organized spec) puts finer provenance in the artifact and does not restructure
  code to make trace links singleton (recognized as architecture distortion). SRC-CONJ-1 is
  therefore the default; because roots authored under the splitting discipline would invite
  re-authoring, its go/no-go precedes S3 authoring. The splitting fallback survives only as a
  lint-enforced emergency mode with the coverage claim downgraded to function granularity.
- **F-8 (MINOR, protocol design; no soundness hole found).** The soundness story is good and
  must be stated, not left implicit: serialized applies linearize; the CAS refuses stale tokens
  fail-closed; under the scoped freeze a CAS-refused `patch` may be re-applied verbatim after
  resync (the R8 premise); stale briefs err conservative; the decomposition-trust meet is
  interleaving-insensitive. Gaps: the tree-global CAS token makes optimism nominal at N agents
  (pre-register the expectation, or narrow token scope with its own soundness note); protocol
  (CAS) retries budgeted separately from semantic retries; the Phase 2 STOP needs a
  pre-registered numeric trigger.
- **F-9 (MINOR, citation drift).** Four instances, all fixed: secure-channel parallel-cascades
  line numbers; "9 frozen refute cruxes" for A4 (the frozen gate is 5 refutes plus 4 good
  twins); tcp_rfc793's decoded-ADT boundary is implicit (no README), so TFTP's Phase 0 states
  it explicitly rather than by precedent; strategic-positioning line numbers.
- **F-10 (MINOR, evaluation methodology).** The inventory denominator is produced and audited
  in-project; the standard defense is two independent extractions with reconciliation and a
  reported inter-extractor agreement statistic (systematic-review dual extraction; DO-178C
  review-independence objectives). EXT-AGENT-1 upgraded accordingly.
- **F-11 (MINOR, criterion well-formedness).** The three-member disposition set had no place
  for the C5 test-vector channel (`check` blocks are executed, unproved); a fourth disposition
  (Vectored) added. RFC 1350 has no test-vector appendix, so the C5 row is empty or synthesized
  from prose examples, recorded at Phase 0.
- **F-12 (OBSERVATION).** A weaker-model appendix arm (same briefs, same protocol, weaker model
  tier, reported separately) is the cheap route to converting the safety net's value from
  by-construction to observed at least once; not a forced failure (a different population, not
  a rigged input); off the headline.
- **F-13 (OBSERVATION).** The TFTP choice survives stress; no dismissed candidate was dismissed
  too quickly. ARP (RFC 826) has the same pre-2119 problem and no famous refutable bug; UDP
  (RFC 768) is too small and its ones-complement checksum is C4-shaped. Netascii lands under
  the F-2 rubric as C4 or excluded-with-cause.

### The review's answers to Rev 0's questions

1. **Completeness criterion.** Defensible as a criterion, indefensible as the headline; the
   disposition-ledger form matches certification traceability practice, the verification
   literature reserves "full"/"verified" for the encoded surface. Reword per F-1, rubric per
   F-2.
2. **Measuring a saturated process.** No established off-the-shelf methodology exists for
   multi-agent verified construction at near-zero per-agent error; the closest analogues are
   certification-style process evidence plus spec-mutation adequacy plus vacuity/coverage
   reasoning. The proposed set is right in kind, weak in degree: upgrade per F-5, and promote
   R5 divergence to a measured axis (semantically distinct fills all passing measures the slack
   the contracts leave; the one quantitative answer to "verified but vacuous" that needs no
   agent failure). F-12's weaker-model arm is the optional observed-catch route.
3. **Temporal flattening.** Sound, because the RFC 1123 clause is itself per-event
   (Alpern-Schneider safety of the most local kind); restate in disequality form per F-3; the
   emergent no-doubling property is trace-level and is not claimed (F-4).
4. **Two coupled FSMs.** The ghost spine is the accepted inductive-invariant idiom on the
   product automaton, not a hidden bisimulation; two mandatory disclosures per F-4 (duplicate
   delivery in the event alphabet; the trace-induction closure as the disclosed trusted
   schema). Do not scope the joint invariant out as C6: it is the protocol's center and is
   expressible per-step in QF-LIA.
5. **Provenance granularity.** The traceability literature favors finer provenance in the
   artifact over finer decomposition of the code. SRC-CONJ-1 default, decided before S3; the
   splitting fallback only as a mechanically enforced mode; the choice sets RFC-COV-1's claim
   at conjunct vs function granularity (F-7).
6. **Swarm protocol soundness.** No soundness defect found: serialized apply linearizes,
   tree-global CAS fails closed, stale briefs err conservative, patch replay after resync is
   verdict-preserving under the scoped freeze, the trust meet is interleaving-insensitive. The
   costs are throughput-shaped, not soundness-shaped (F-8); the Phase 2 fallback
   (parallel-per-module) is the right containment.
