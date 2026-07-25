# RFC-SWARM coverage widening: can language work recover the 58 dispositioned-out rows?

> **Rev 0, 2026-07-24**
> **Status:** DRAFT - language-team analysis, awaiting professor review and user adjudication.
> **Input:** the Phase 0 census, [`examples/tftp_rfc1350/VERIFICATION_SCOPE.md`](../../examples/tftp_rfc1350/VERIFICATION_SCOPE.md)
> (124 canonical normative rows; 40 Encoded / 21 Deployment-modeled / 5 Vectored / 58 Dispositioned out).
> **Re-opens:** [`rfc-swarm-roadmap-proposal.md`](rfc-swarm-roadmap-proposal.md) §5.1, the standing rule against
> putting Lever B or C on the critical path.

---

## Restatement

The owner asks whether coverage depth on RFC 1350 is worth new language work: can any of the 58
dispositioned-out rows be recovered by widening `Σ_auto`? The situation is not a failing target.
All 15 characteristic-core rows are Encoded and four feasibility probes came back SAFE and
body-faithful against the shipped compiler at v0.14.65 (`VERIFICATION_SCOPE.md` §10). The question
is therefore about the *ledger's* depth, not about whether the demonstration is buildable.

**The answer this analysis reaches: no, and for a reason more interesting than "the features are
expensive".** The 58 rows are dominated by *modeling scope* decisions, not by `Σ_auto`'s reach.
Thirty-four of the 58 (58.6%) are recoverable with **zero language change**, by widening the
modeled state and event alphabet using precedents this same ledger already applies elsewhere.
Only three of the 58 (5.2%) are recoverable by a bounded, decidability-preserving language
feature, and those three have a cheaper route through the shipped `check` (Vectored) channel.

---

## Context located

1. `examples/tftp_rfc1350/VERIFICATION_SCOPE.md` §4-§8. The wire-format boundary (§8, "decoded
   packet ADTs, not the byte stream") and the spine's fixed event alphabet ("loss and timeout
   remain outside the alphabet") are the two scoping decisions that generate most of the 58.
2. `docs/design/rfc-swarm-roadmap-proposal.md` §1.1 (four-member disposition set), §1.4.1
   (Deployment-modeled rows must carry refute cruxes), §1.5.1 (a temporal rule's *per-event
   consequence* is a separate Encoded row), §3.1 ("required by the recommended RFC: nothing"),
   §4.1 (STOP text), §5.1 (the standing rule).
3. `docs/design/data-scope-extension.md` Posts 1-2, 4, 7 and `:335-342` (the Lever A residues).
4. `LLMLL.md` §5.3.3 (the `Σ_auto` equation, the four completeness facts, the Lean-path row),
   §5.3.4 (body-VC shape, 4096-path cap, strict-core admission), §5.3.5 `:1019-1025`, §13.6
   (`regex-match` is `Σ_ref \ Σ_auto`), §13.12 (bytes/map PROVE-polarity read preconditions).
5. `docs/compiler-team-roadmap.md` `:79` (LEAN-GA parking lot), `:134-157` (Levers A/B/C),
   `:216-230` ("What's NOT on this Roadmap"; `:230` records the freeze lifted at v0.11, so nothing
   below is blocked by freeze policy).
6. `docs/design/leanstral-integration-scope.md` §1-§6 - the three-layer LEAN-GA finding.
7. `docs/design/spec-from-rfc-pipeline.md` §1.2 - the C1-C6 clause classes.

**Drift found while reading (four findings, routed at the end).**

- **D1 (internal, roadmap proposal).** §1.1 says the qualitative condition "dominates" and that
  "the constant alone is arbitrary"; §4.1 makes the 30% quantitative line an independent trip-wire
  joined by `or`. The Phase 0 artifact reads §4.1 (`VERIFICATION_SCOPE.md` §5: "A STOP condition
  fired"). Which reading governs decides whether the owner must act at all.
- **D2 (roadmap proposal vs Phase 0 application).** §1.5.1 licenses the *per-event consequence* of
  a temporal clause as its own Encoded row, in disequality form. The Phase 0 pass applied that rule
  to exactly one row (T113, the duplicate-ACK amendment) and to none of the nine timing rows, three
  of which (T084, T085, T088) are pure per-event safety properties once a `Timeout` event exists.
- **D3 (stale estimate).** §2.1 still reads "estimated 20-30 normative clauses"; the census found
  124. `VERIFICATION_SCOPE.md` §3 acknowledges the gap; the proposal text does not. Doc-lead item.
- **D4 (Leanstral scope doc vs shipped state).** `leanstral-integration-scope.md` §5 records the
  `sanitizeProof` anti-laundering guard as "Uncommitted, pending review/merge" in a worktree;
  `LLMLL.md` §5.3.3 states it as shipped and active. The scope doc's status line is stale.

---

## Design proposal

### Part 1 - Row-by-row triage of the 58

Four categories, disjoint and exhaustive over the 58.

| Category | Count | Share of the 58 |
|---|---:|---:|
| **(a)** Recoverable by MODELING, no language change | **34** | 58.6% |
| **(b)** Recoverable by a bounded, decidability-preserving language feature | **3** | 5.2% |
| **(c)** Requires leaving `Σ_auto` | **4** | 6.9% |
| **(d)** Unverifiable in principle, or correctly excluded | **17** | 29.3% |

#### Category (a) - 34 rows, six modeling changes

Each modeling change below is an instance of a precedent the *same ledger* already applies. None
touches `Σ_auto`. Naming them:

- **M-TID.** The connection state carries `(local_tid: int, peer_tid: int)`; every packet record
  carries `(src_tid: int, dst_tid: int)`. Ints under equality and range refinement only. Precedent:
  the block-number treatment (`VERIFICATION_SCOPE.md` §8, "equality and disequality only").
- **M-ENV.** A datagram-envelope record `(src_port: int, dst_port: int, dg_len: int)` with the
  arithmetic tie `dg_len = 8 + tftp_len`. Precedent: T061's `(block, buf, len)` decode.
- **M-TMO.** The step function's event alphabet gains a `Timeout` constructor; the state gains
  `retries: int` against a literal cap. Timeout is an **uninterpreted input event**; no clock is
  modeled. Precedent: T021, where the three error causes "enter as input events".
- **M-DALLY.** The acknowledger's state enum gains `Dallying`. Precedent: any enum state.
- **M-FLAG.** Two environment input flags, `arrived_on_broadcast: bool` and `path_allowed: bool`.
  Precedent: T021 again.
- **M-MODE.** The mode enum **retains** `Mail`, and the request-accept step is contracted to reject
  it. This inverts the current model, which erased `Mail` from the type and thereby erased the
  clause. Precedent: T054 already models mode as a decoded enum over all three RFC-defined modes.

| Row | Model | Target disposition | What refutes |
|---|---|---|---|
| T022 | M-TID | Encoded | latch mutant: TID mismatch drives post-state to `Terminated` |
| T023 | M-TID | Encoded | `dst_tid` of the emitted ERROR set to `peer_tid` instead of the packet's `src_tid` |
| T025 | M-ENV | Encoded | `dg_len` off by the header width |
| T026 | M-TID | Deployment-modeled | (by construction; see the mutation caveat below) |
| T027 | M-TID | Encoded | boundary +/-1 on the 0..65535 refinement |
| T036 | M-TID | Encoded | a transition that rewrites `local_tid` mid-transfer |
| T038 | M-TID | Deployment-modeled | (field presence, the T028 precedent) |
| T039 | M-TID | Deployment-modeled | (identification; see caveat) |
| T040 | M-TID | Deployment-modeled | (selection as input) |
| T041 | M-TID | Encoded | initial `dst_tid` set to something other than 69 |
| T042 | M-TID | Encoded | server answers from 69 |
| T043 | M-TID | Encoded | response addressed to the server's own TID |
| T044 | M-TID | Encoded | a mid-transfer transition that swaps the pair |
| T046 | M-TID | Encoded | guard-omission: the step admits a packet without the TID check |
| T047 | M-TID | Encoded | mismatch mutates the state instead of preserving it |
| T048 | M-TID | Encoded | mismatch terminates the transfer (the arm-omission mutant) |
| T102 | M-TID | Encoded | code 4 emitted instead of code 5 on TID mismatch |
| T106 | M-TID | Encoded | post-setup destination reverts to 69 |
| T107 | M-ENV | Encoded | 8-byte header omitted from the length sum |
| T108 | M-TID | Deployment-modeled | (identification; see caveat) |
| T112 | M-ENV | Encoded | same as T107, the RFC 783 correction restated |
| T116 | M-FLAG | Deployment-modeled | broadcast arrival produces a reply |
| T121 | M-TID | Encoded | the second response is accepted and the first connection dropped |
| T122 | M-TID | Deployment-modeled | (identification; see caveat) |
| T020 | M-TMO | Deployment-modeled | timeout exhaustion leaves the state non-terminal |
| T084 | M-TMO + M-DALLY | Encoded | `Dallying` exits to `Done` on the repeated DATA instead of re-ACKing |
| T085 | M-TMO + M-DALLY | Encoded | repeated final DATA produces no ACK |
| T088 | M-TMO | Encoded | `retries = N` leaves the connection open |
| T091 | M-TMO | Deployment-modeled | (totality over the widened alphabet; see caveat) |
| T114 | M-TMO | Deployment-modeled | a `next-rto` that returns a constant violates the monotone-increase post |
| T115 | M-FLAG | Deployment-modeled | `path_allowed = false` accepted instead of ERROR code 2 |
| T006 | M-MODE | Encoded | request-accept honors a `Mail` request |
| T104 | M-MODE | Deployment-modeled | error code 7 emitted on some path |
| T111 | M-MODE | Encoded | same crux as T006 (RFC 1123 governs; one clause per row) |

Twenty-two of the 34 reach **Encoded**; twelve reach **Deployment-modeled**.

**Three rows in this table deserve separate emphasis, because they are ledger-integrity gaps rather
than count gaps.** T016 (the error latch) is Encoded and is a characteristic-core row; T022, the
RFC's single stated *exception* to that latch, is dispositioned out. A ledger that carries a rule
and drops its only exception has a coverage asymmetry a reviewer will find. The same holds for
T006/T111: RFC 1123 §4.2.2.1's prohibition on mail mode is a genuine, refutable, single-transition
obligation, and the current model erased it by removing the constructor the clause is about. Those
three rows are worth recovering on assurance grounds independent of any percentage.

**The mutation caveat.** Eight of the twelve Deployment-modeled targets (T026, T038, T039, T040,
T091, T108, T122, and arguably T115) hold *by construction*: no mutant of the artifact violates
them, because their content is a typing or field-presence fact. `rfc-swarm-roadmap-proposal.md`
§1.4.1(d) requires every Deployment-modeled row to carry a refute crux, and §4.4's STOP rule says a
clause with no constructible refuting mutant is re-dispositioned. Those eight should therefore be
expected to fail Phase 4 and return to `Dispositioned out`. The ceiling arithmetic below reports
both a nominal and a mutation-adequate figure for exactly this reason.

#### Category (b) - 3 rows, one bounded feature

| Row | Obligation | What it needs |
|---|---|---|
| T004 | netascii is 8-bit ASCII per USAS X3.4-1968 with the Telnet modifications | a bounded index quantifier over `bytes[n]`: every byte `<= 127`, and `b[i] = CR` implies `b[i+1] ∈ {LF, NUL}` |
| T053 | the Filename field is netascii bytes terminated by a single zero byte | `b[len] = 0` (pure Lever A today) **and** no interior zero (bounded index quantifier) |
| T080 | the ErrMsg string, like every TFTP string, is terminated by a zero byte | same shape as T053 |

All three become bytes-shaped once the filename and ErrMsg fields are modeled as `bytes[k]` plus an
int length, which is the DATA-payload dodge the scope matrix already blesses (`VERIFICATION_SCOPE.md`
§8, "content opaque, length proved"). The *terminator-position* half of T053/T080 is already inside
shipped Lever A (`bytes-get b len = 0`, `LLMLL.md` §13.12). The *no-interior-zero* half and all of
T004 need a bounded universal over the buffer. Design sketch in Part 2.

#### Category (c) - 4 rows, outside `Σ_auto` by construction

| Row | Obligation | Logic needed | Where it would be discharged |
|---|---|---|---|
| T014 | on timeout a party may retransmit, *which causes the peer to retransmit the lost packet* | two-party trace property (a causal consequence on the other automaton) | LTL/TLA over the product automaton: a model checker (TLC/SPIN) on a bounded instance, or Lean over an explicit trace semantics. Neither is on the roadmap. |
| T086 | the sender must retransmit the last DATA *until acknowledged or until it times out* | liveness (unbounded repetition under fairness) | same; liveness needs a fairness assumption no `Σ_auto` predicate can carry |
| T057 | an octet-mode round trip must return a byte-identical file | induction over the block sequence (a fold), plus symbolic-length buffers | Lever B (dependent lengths) + Lever C (induction), i.e. the Lean tier via LEAN-GA, currently parked (`compiler-team-roadmap.md:79`) |
| T037 | TIDs should be chosen randomly so immediate reuse is improbable | probabilistic program logic (pRHL, union-bound logic) | **nothing.** No LLMLL track carries probabilistic reasoning, and none is proposed. |

T014 and T086 each have a per-event residue that §1.5.1 would license as a *new* Encoded row (on a
timeout, emit the *last* packet, not a new one). Splitting them is permitted by the rubric's own
tie-break (1), but it moves the denominator, so this analysis holds the denominator fixed at 124 and
dispositions each row by its whole stated obligation. T057 is the most substantive exclusion in the
entire ledger: it is TFTP's end-to-end functional correctness, and it is the one row where Levers B
and C would buy something real. It is still not worth the campaign, for the reasons in Part 4.

**Category (c) is where the Leanstral question lands.** Part 5 answers it per row group; the short
version is that Lean buys proof *power* over a stated obligation and buys no *model*, so it recovers
exactly one of the 58, and that one is gated on Levers B and C as well as on LEAN-GA.

#### Category (d) - 17 rows, correctly excluded

| Reason class | Rows | Count |
|---|---|---:|
| Permission or corpus directive constraining no transition | T001, T007, T008, T060, T105, T110, T119, T124 | 8 |
| Undefined target, or no functional content | T055 (the "local text format" is host-defined and the RFC does not fix it), T059, T079 | 3 |
| Below the artifact: the implementation under verification does not construct these headers | T024, T029 | 2 |
| Superseded by RFC 1123 §4.2.2.1 | T058 | 1 |
| Deployment environment, not a protocol transition | T109 | 1 |
| Opaque transform over the whole datagram | T123 | 1 |
| Modelable only by construction, and the model has no constructible refuting mutant | T015 | 1 |

T015 ("need buffer only one outstanding packet") is the instructive one. It *is* modelable: a state
record with exactly one `last_sent` field satisfies it by construction, which is the T002 precedent
verbatim. But no mutant violates it, so under §1.4.1(d) it would ship with zero evidence its model
constrains anything, and Phase 4 would re-disposition it. Recording it as correctly excluded now is
cheaper than discovering that in Phase 4.

### Part 2 - Design sketch for the one feature worth sketching

Only category (b) admits a feature proposal. Two variants, plus one refusal.

#### B1a - `for-index`, a bounded index quantifier over literal-length `bytes[n]` (RECOMMENDED IF ANYTHING)

**Surface.** An expression form legal only inside `pre`/`post` clauses and `check` bodies:

```lisp
(for-index [i 0 512] (<= (bytes-get b i) 127))
```

S-expression shape `(for-index [<var> <lo> <hi>] <bool-expr>)`, half-open `[lo, hi)`. JSON-AST: a new
`ForIndex` node carrying `var`, `lo`, `hi`, `body`, minor-version schema bump (the SRC-CONJ-1
precedent at 0.9.0 shows the bump machinery is live).

**Theory and decidability.** The quantifier is **eliminated at emission time**, not handed to the
solver. When `lo` and `hi` are integer literals and `hi - lo <= K`, the emitter expands the form into
`hi - lo` conjuncts of quantifier-free array selects. The resulting VC is QF-AX + QF-LIA, exactly the
array class already in `Σ_auto` (`LLMLL.md` §5.3.3, "Array class - complete"; Stump-Barrett-Dill-Levitt
LICS 2001, combined by polite-theory combination). Decidability is not merely preserved, it is
untouched: no new theory enters. This is deliberately *not* the E-matching route, which §5.3.3's
emission side-condition already rules out ("the quantified form forfeits completeness").

**`Σ_auto` admissibility rule.** `for-index` reflects exactly when (i) `lo` and `hi` are integer
literals, (ii) `hi - lo <= K` for a compile-time constant `K` (proposed `K = 64`), (iii) the body is
itself in `Σ_auto` after substituting each concrete index, and (iv) the bound variable appears only
as a direct index argument to `bytes-get`, never inside a nested `bytes-get` index. Violating any
clause routes the whole function to the fallback channel under the shipped exact-reflection rule
(`data-scope-lever-a-arrays-proposal.md` §6.1, cited at `LLMLL.md` §5.3.3), which is the existing
whole-function-fallback discipline, not a new one.

**What refutes.** An off-by-one terminator (`b[len - 1] = 0` instead of `b[len] = 0`) refutes T053's
contract. A netascii writer that emits a byte `> 127` refutes T004's range clause. A CR written
without its following LF or NUL refutes T004's adjacency clause. All three are branch-localized
counterexamples of the shape the Lever A regression witness `examples/bytes-bounds/` already produces.

**Effort class: S** (days). The emitter already walks `pre`/`post` expressions and already emits
per-occurrence ground facts; this is a syntactic expansion pass plus an admissibility guard plus the
schema node.

**Risks.** (1) *VC size.* At `K = 64` a single `for-index` contributes 64 conjuncts; under the
4096-path cap (`LLMLL.md` §5.3.4) a `for-index` inside a deeply-branched body multiplies. Mitigation:
the `K` cap and the whole-function fallback. (2) *Solver-performance degradation* is the real risk
here, and it is bounded by `K`; the Lever A perf basis (`experiments/cdp-perf-0/`) is the
measurement harness. (3) *Unsoundness* risk is low because no new theory is admitted; the failure
mode is a mis-implemented expansion, which is a test-coverage problem, not a metatheory problem.

#### B1b - the array-property fragment, for symbolic bounds (NOT RECOMMENDED)

The principled generalization is Bradley-Manna-Sipma's array property fragment (*What's Decidable
About Arrays?*, VMCAI 2006): `∀i. guard(i) => value-constraint(i)` is decidable when index guards
are conjunctions of comparisons, the quantified index is used only as a direct select index, and no
`select` appears in the guard. That admits **symbolic** bounds, which B1a does not. Effort **M**,
and not recommended for one reason: TFTP's buffers are literal-length by scope decision, so no
clause in this inventory needs a symbolic bound. Record B1b as the right design for a future target
rather than building it now.

#### B2 - SMT string theory (REFUSE)

The precise decidability statement, because the imprecise version is what gets a project into
trouble. **Word equations alone** (concatenation, no length) are **decidable** (Makanin 1977;
PSPACE per Plandowski 1999/2006), and stay decidable with **regular-language membership**. **Word
equations plus length constraints is OPEN**: not known decidable, not proved undecidable. That open
combination is exactly what LLMLL would need, because `string-length` is already in `Σ_auto` as a
measure (`LLMLL.md` §5.3.3) and every realistic string-structure contract relates a substring to a
length. The **straight-line fragment** (each string variable assigned once from concatenation or
replace over previously-defined variables, plus regular constraints) is **decidable**,
EXPSPACE-complete (Lin and Barceló, POPL 2016; Chen et al., POPL 2019 extend it to transducers and
to length in the acyclic case), and NUL-terminated field splitting does sit inside it.

So a decidable design exists. Refuse it anyway, on three grounds. (i) **Yield.** It buys at most
T053, T080, T059; two are reachable through B1a plus the bytes dodge and T059 dispositions out on
mail-mode deprecation regardless. Net new rows: zero to one. (ii) **Boundary risk.** `Σ_auto`'s
whole value is that "SAFE is a decidable predicate on a fixed VC" (`data-scope-extension.md` Post 1;
`LLMLL.md` §3.4.5 Theorem B). A theory whose decidability rests on a *syntactic* straight-line
restriction puts that claim's correctness into a classifier, and a classifier bug admits an
`unknown`-prone VC to the body-faithful tier, which is the degradation Theorem B names.
(iii) **Practice.** Z3 and CVC5 return `unknown` on shapes nominally inside the fragment; a tier
whose verdict is `unknown` in production is not the `verified` tier. Effort **L**, risk **high**.

#### B3 - a temporal or trace tier for category (c) (REFUSE)

The project already has its answer to trace-level closure and it is not a language feature: the
**disclosed trusted composition schema** (`VERIFICATION_SCOPE.md` §9; roadmap §1.3). Per-step
preservation is proved in `Σ_auto`; the closure is recorded as a small trusted step, the IronFleet
shape. Adding a temporal logic to convert four rows would replace a one-paragraph disclosure with a
multi-week metatheory obligation and a second solver. Refuse. Part 5 treats the Lean-tier variant
of the same question, and reaches the same answer for a sharper reason.

---

## Part 3 - The recomputed ceiling

Four scenarios. The denominator is fixed at 124 throughout; only dispositions move.

| Scenario | Encoded | Deployment-modeled | Vectored | Out | Encoded % | Out % |
|---|---:|---:|---:|---:|---:|---:|
| **Today (Phase 0, Rev 0)** | 40 | 21 | 5 | 58 | **32.3%** | **46.8%** |
| **(a) only** - all modeling, no language work | 62 | 33 | 5 | 24 | **50.0%** | **19.4%** |
| **(a) + (b)** - modeling plus `for-index` | 65 | 33 | 5 | 21 | **52.4%** | **16.9%** |
| **(a) + Vectored route** - `check` blocks instead of `for-index` | 62 | 33 | 8 | 21 | **50.0%** | **16.9%** |
| **(a) + (b), mutation-adequate** - the 8 by-construction rows fail Phase 4 and return | 65 | 25 | 5 | 29 | **52.4%** | **23.4%** |

Read the table in this order.

1. **The (a)-only row is the finding.** Doing no language work at all takes Encoded from 32.3% to
   50.0% and takes Dispositioned-out from 46.8% to 19.4%, which **clears the pre-registered 30%
   STOP line** (roadmap §4.1). The STOP condition fired on modeling scope, not on `Σ_auto`.
2. **The (b) increment is 3 rows, or +2.4 percentage points of Encoded**, in exchange for a new
   expression form, a schema bump, and an emitter pass. That is the ROI the owner is being asked to
   approve.
3. **The Vectored route delivers the same out-percentage as (b) with zero language work**, at the
   cost of executed-rather-than-proved evidence on three rows. Vectored is a shipped disposition
   (roadmap §1.1) and `llmll test` evaluates `map`/`bytes` operations as of v0.14.63, so a bounded
   scan over a 512-byte buffer is directly executable today.
4. **The mutation-adequate row is the number to quote in the writeup**, because Phase 4's own gate
   will produce it. 23.4% out, still inside the STOP line, with 8 rows returned to exclusion.

---

## Part 4 - Recommendation, ranked

**R1. Build nothing in the language. Re-run the disposition pass with the six modeling changes.**
This is the whole recommendation, and everything else is contingent on it. It recovers 34 rows,
clears the quantitative STOP line, and closes three genuine ledger-integrity gaps (T022's
error-latch exception, T006/T111's mail-mode prohibition). It costs a Rev 1 of
`VERIFICATION_SCOPE.md` and a larger artifact.

**R2. Route T004, T053, T080 to the Vectored channel before considering `for-index`.** Three `check`
blocks, zero compiler work, same out-percentage. If the owner then finds the executed-not-proved
evidence unsatisfying on a row that matters, that is the empirical promotion signal §3.1's watch
item describes, and `for-index` (B1a, effort S) is the response.

**R3. Build `for-index` (B1a) only if R2's telemetry demands it.** Conditional, effort S, low risk.

**R4. Refuse B2 (SMT strings), B1b (array-property fragment, symbolic bounds), B3 (temporal tier),
and any pull-forward of Lever B or Lever C.** Record the refusals with their decidability citations
in `compiler-team-roadmap.md`'s "What's NOT on this Roadmap" table so the next asker gets the answer
without re-deriving it.

**R5. LEAN-GA stays parked; see Part 5 for the full argument.** It recovers 0 of 58 rows on its own,
and the one Lean-shaped row (T057) is gated on Levers B and C, which R4 refuses. The Lean work that
*would* be valuable, discharging the trusted composition schema and the no-doubling theorem, is a
Phase 4 side artifact outside the wave, not a language or fragment move.

### The case for building nothing AND changing nothing (shipping at 32.3%)

This case is stronger than it looks and the owner should weigh it seriously.

The pre-registration fixed the 30% line **before** the census. The census returned 46.8%. Adjusting
the model until the number passes is the exact failure mode pre-registration exists to prevent. A
reviewer who sees Rev 0 at 46.8% and Rev 1 at 19.4%, with no new verification technology in between,
is entitled to ask what changed other than the will to pass. That question does not have a good
answer unless every modeling decision is defended individually.

The disarming conditions are three, and they are all met by the analysis above, but they must be
*executed*, not asserted: (i) every modeling change cites an existing precedent in the same ledger
(M-TID cites §8's block-number treatment, M-TMO and M-FLAG cite T021, M-MODE cites T054, M-ENV cites
T061); (ii) every moved row carries a named refuting mutant, and rows that cannot (the eight
by-construction rows, plus T015) stay out; (iii) Rev 1 preserves and reports the Rev 0 numbers
side by side, so the delta is auditable rather than silent. If the owner is not prepared to do all
three, shipping at 32.3% with the current ledger is the better outcome, because a defensible 32.3%
beats a contested 50.0%.

### Should §5.1's standing rule hold or be amended?

**Hold, and amend in one respect.** The rule as written ("choose the RFC to fit the shipped
fragment, and let wave telemetry, not anticipation, promote residues") is correct and this analysis
vindicates it: the target was chosen well, nothing in `Σ_auto` needs to move, and the one feature
worth sketching would recover 3 rows out of 124.

The amendment is that the rule governs the **fragment** axis and is silent on the **modeling** axis,
and Phase 0 shows the modeling axis is where the rows actually went. Proposed addition to §5.1:

> A `Dispositioned out` reason must name which of four barriers it hits: **(1)** the obligation is
> outside `Σ_auto`; **(2)** the obligation is inside `Σ_auto` but its subject is outside the modeled
> state or event alphabet; **(3)** the clause constrains no transition; **(4)** no refuting mutant is
> constructible. Barrier (2) is a **re-openable** disposition subject to a cost/benefit pass before
> the STOP condition is evaluated. Barriers (1), (3), and (4) are terminal for the target.

Under that amendment, Phase 0's STOP evaluation would have been run *after* the barrier-(2) pass, and
the quantitative condition would not have fired. This strengthens the rule rather than weakening it:
it keeps `Σ_auto` off the critical path while denying a scoping decision the authority to force a
re-target.

---

## Part 5 - How Leanstral would play a role

Grounding: the v0.14.8 demo slice proves a *faithfully-translatable nonlinear* obligation in Lean 4
plus Mathlib and records `verified-lean` (`DLVerifiedLean`), a **peer** of SMT `verified` in the
lattice, not a tier above it, with a re-checkable `.lean` certificate (`LLMLL.md` §5.3.3; §5.3.4).
LEAN-GA's deferred production rebuild is three layers, not one integration
(`leanstral-integration-scope.md` §1): **L1** `LeanTranslate.hs` reads only the contract and never
the body, so `result` and parameters are free variables and the emitted theorem is misstated (§2);
**L2** the obligations that need Lean land at `erBodyFallback -> asserted` and are never marked
`?proof-required`, so they never enter the pipeline (§3); **L3** `lean-lsp-mcp` is a checker, not a
prover, and the trust-correct shape is T-B, where the model proposes and the kernel gates (§4).

### 5.1 Which of the 58 are Lean-tier candidates

The discriminating question is not "is this hard to prove". It is **"is there a proposition to
prove, stated against a semantics that exists"**. Lean buys proof power over a stated obligation.
It buys no model, no event alphabet, and no trace semantics. Against the four-barrier taxonomy of
Part 4: Lean helps only at barrier (1), and only when the obligation is statable.

- **Timing-liveness (9 rows): zero Lean candidates.** Not one of the nine is blocked by proof
  difficulty. Six (T020, T084, T085, T088, T091, T114) are blocked by the event alphabet, which is
  barrier (2), and recovering them needs M-TMO, not a prover. T015 is barrier (4), no constructible
  mutant. T014 and T086 need a **trace semantics with fairness**, which LLMLL does not have: the
  body-VC is the single-transition Hoare triple `pre ∧ result = ⟦body⟧ => post` (`LLMLL.md`
  §5.3.4), and there is no reachability relation to quantify over. Lean cannot prove a theorem
  nobody has stated. Activating LEAN-GA moves this group by zero rows.
- **Trace-level (4 rows): one candidate.** T008, T119, T124 are barrier (3), permissions and
  corpus directives that constrain no transition; there is no proposition, so no prover applies.
  **T057** (octet round trip returns a byte-identical file) is the single genuine Lean-tier row in
  the entire 58: an induction over the block sequence, which is exactly the class `LLMLL.md` §5.3.3
  names as not yet shipped ("general inductive properties in particular are **not** yet shipped").
  It additionally needs symbolic-length buffers, so it is gated on **Lever B and Lever C together**,
  with LEAN-GA as the discharge route for the induction. LEAN-GA on its own recovers it not at all.
- **Elsewhere in the 58: none.** T123 (datagram checksum) is a conformance claim against an
  external algorithm definition, not a theorem. T037 (random TID choice) *is* statable in Mathlib
  (`MeasureTheory`, `PMF`), but LLMLL has no probabilistic semantics to translate from, so the
  result would be a hand-authored Lean development disconnected from the artifact, which certifies
  nothing about the artifact. T004, T053, T080 are bounded quantifiers and belong in `Σ_auto` via
  B1a, where the discharge is decidable; routing them to Lean would be a strict downgrade.

**Net: 1 of 58 rows is a Lean-tier candidate, and LEAN-GA alone recovers 0 of 58.**

### 5.2 Could Leanstral discharge the trusted composition schema?

This is the better question, because the schema is not one of the 58: it is the demonstration's
single disclosed trusted assumption (`VERIFICATION_SCOPE.md` §9). Per-step preservation is proved
in `Σ_auto`; the closure from per-step preservation to "the invariant holds on every reachable
trace" is trusted, in the IronFleet shape.

In principle yes. Concretely it needs three things, and their cost ordering is the point.

1. **A trace semantics for the spine, in Lean.** The state type, the event alphabet, the step
   relation, and `Reachable : State -> Prop` as an inductive predicate. Roughly 50-150 lines of
   hand-authored Lean, not a translation output.
2. **A faithfulness argument** tying that Lean step relation to the LLMLL spine function. This is
   L1's problem generalized and made strictly harder: L1 today does not pass the body in at all
   (`leanstral-integration-scope.md` §2), and translating a *whole step function* faithfully is a
   larger obligation than translating one body-VC.
3. **The theorem itself, which is the cheap part.** `Init => Inv` plus `Inv ∧ Next => Inv'` gives
   `∀ s, Reachable s -> Inv s` by a three-line induction on `Reachable`. Mathlib is barely needed.

**So the trade is unfavourable at current L1 maturity, and that is the finding.** Discharging the
schema would convert one trusted step, trace induction, which is named, standard, and accepted
across the mechanized distributed-systems literature, into a different trusted step: the fidelity
of a bespoke, unaudited LLMLL-to-Lean translation of an entire step function. The disclosure is
worth more than the proof until L1 is production-grade and independently tested. A kernel-checkable
certificate over a misstated theorem is worse than no certificate, which the scope doc states in
its own terms (§4, "the C-property survives the whole stack only if layers 1-2 are fixed first").

### 5.3 The no-doubling property

The emergent property the Sorcerer's Apprentice fix secures, the absence of a retransmission
cascade, is a quantitative trace property carried today "as a recorded informal derivation"
(`VERIFICATION_SCOPE.md` §9). It is the most attractive Lean target in the whole demonstration on
technical grounds: it is a counting theorem, an arithmetic invariant carried by induction over the
trace, of the shape "sends are bounded by distinct blocks plus timeouts". Mathlib's `Nat` and
`List.length` machinery is a good fit and the proof is short.

Its cost is entirely the §5.2 prerequisite: the trace semantics plus the faithfulness argument.
Given those, the marginal cost of this second theorem is small, perhaps 30-60 lines. **If the owner
ever builds the Lean trace semantics, prove both theorems, because the second is nearly free and it
is the one with the famous bug attached to its name.**

The caution: the per-event clause the fix encodes is **already Encoded and already refuted-twin
confirmed** (T113, characteristic core; probe 2 in `VERIFICATION_SCOPE.md` §10 refutes the
Sorcerer's Apprentice twin and localizes the branch). Proving the emergent consequence adds
narrative completeness about the protocol, not assurance about the artifact's conformance to the
clause. That distinction should be stated wherever the theorem is reported.

### 5.4 Process integrity: who authors the Lean?

Roadmap §1.2 enumerates the human touchpoints exhaustively (S0 scoping, dual-extraction
reconciliation and the S1-S3 audit, harness operation, the post-wave refute layer) and §1.4.2
pre-registers human interventions after freeze at zero. Two cases, and they separate cleanly.

**Case 1: compiler-routed obligation discharge (T-B).** A Leanstral proof term produced for an
obligation the *compiler itself* routed, kernel-checked by `lean-lsp-mcp`, gated by `sanitizeProof`,
and stored as a re-checkable certificate is **not a human intervention**. It is a tool invocation
inside the verification step, epistemically the same category as invoking Z3: untrusted search, a
checkable artifact, a trusted gate. **This is compatible with the wave's integrity claim as
written**, needs no new agent channel, and no fill agent ever sees Lean. Note it is also worth
nothing here, because §5.1 shows the compiler would route zero obligations for this target.

**Case 2: the trace-semantics development of §5.2 and §5.3.** This is different in kind. It is not
an obligation the compiler routes; it is a hand-authored Lean artifact about the protocol. Whoever
writes it is a human, or an unbriefed agent, touching the deliverable after freeze, and that is not
covered by any of the four enumerated touchpoints. **Inside the wave, it breaks the budget.**

**Sequencing answer: put it outside the wave, in Phase 4.** Phase 4 already admits human authorship
(the mutant taxonomy and the kill matrix are human-authored against the frozen tree). Declaring the
Lean development a Phase 4 deliverable keeps Phase 3's zero-intervention budget intact and keeps
the Lean work from touching a single LLMLL body. The writeup then reports two separable claims: the
swarm built the artifact under brief-only conditions, and the artifact's trace-level closure was
proved afterwards by a separately-attributed effort. That is cleaner reporting than folding them
together, and it is the only sequencing that preserves both claims.

### 5.5 Ranked call on Leanstral

- **L1. LEAN-GA stays parked for RFC-SWARM.** It recovers 0 of 58 rows on its own and 1 of 58 in
  combination with Levers B and C, which are themselves refused for this target (Part 4, R4). The
  three-layer rebuild is effort **L** on the project's own assessment
  (`leanstral-integration-scope.md` §6) and its value here is zero rows.
- **L2. The trusted composition schema stays disclosed, not proved.** Trading a literature-standard
  schema for a bespoke translator's fidelity is a downgrade at current L1 maturity (§5.2).
- **L3. If a Lean deliverable is wanted from this project, the right one is the no-doubling theorem
  (§5.3), sequenced as a Phase 4 side artifact outside the wave (§5.4), with its own faithfulness
  gap disclosed exactly as §9 discloses the current one.** Effort L, value narrative rather than
  assurance. Recommended only if the demonstration's audience specifically asks for the Sorcerer's
  Apprentice property, not on general principle.
- **L4. Independent of all the above, L1 and L2 are the right first moves whenever LEAN-GA is
  activated for any target**, because a certificate over a misstated theorem is the one Lean-tier
  failure mode that would damage the trust story rather than merely fail to help it.

---

## Part 6 - The strategic argument: does coverage depth strengthen the claim?

The demonstration asserts a **disposition ledger plus a verified characteristic core**, worded in
roadmap §1.1 as "every normative clause dispositioned: verified, modeled, tested, or excluded with
cause; the protocol core verified body-faithfully". It does not assert "the RFC is verified", and
`VERIFICATION_SCOPE.md` opens by saying so.

Against that claim, the Encoded fraction is a **secondary** statistic. What carries the claim is:
(i) every one of the 124 rows has exactly one disposition; (ii) every exclusion cites a reason;
(iii) all 15 characteristic-core rows are Encoded and body-faithful; (iv) every Encoded and modeled
row has a refuting mutant in a frozen kill matrix. Conditions (i) through (iv) hold today at 32.3%.

So the correct answer to "does higher coverage strengthen the claim" is **mostly no, with two
exceptions that are worth the work anyway.**

**Where it just moves a number.** Not one of the 34 category-(a) rows is a characteristic-core row,
and no proposed feature touches one. The core was Encoded before this analysis and stays Encoded
after it. Raising 32.3% to 50.0% adds TID plumbing, envelope arithmetic, and timeout bookkeeping to
the ledger; those are real obligations, but nobody's TFTP outage lives there, and the demonstration's
adversarial reader is not counting rows, they are asking whether the rows that matter are proved and
whether the excluded rows were excluded for stated reasons.

**Where it is a genuine integrity repair.** Two clusters are different in kind. T022, T047, T048
are the RFC's stated *exception* to the error latch, and T016 (the latch itself) is a
characteristic-core Encoded row. Carrying a rule while dropping its only exception is a coverage
asymmetry that invites the reader to ask what else was dropped. T006 and T111 are RFC 1123's
prohibition on mail mode, and the current model erased them by deleting the constructor the clause
is about; a prohibition modeled away is not a prohibition dispositioned, and the difference is
exactly what the ledger claims to track. Those five rows should be recovered because the ledger is
weaker without them, not because 50.0% reads better than 32.3%.

**The cost nobody has priced yet.** The 34-row recovery enlarges the artifact. §2.1 estimated 25-35
functions across 6-8 modules; TID checking, envelope arithmetic, a `Timeout` arm on every state, a
`Dallying` state, and mail-mode rejection plausibly push that to 40-55 functions. Phase 3's wave
grows proportionally, Phase 4 owes a mutant and a good twin for each of the 34 new rows, and §4.3's
STOP rule pauses the wave at three exhausted holes. The coverage gain is real; so is the schedule.

**One more caution on M-TMO.** Modeling a timeout as an uninterpreted input event flattens a timing
property into a per-event safety property. That is legitimate, it is exactly the move §1.5.1 already
blesses, and it is what makes T084/T085/T088 Encodable. But the resulting verified statement is "if
a timeout event is delivered, the response is correct", and it says nothing about *when* timeouts
fire. If the writeup reports the timing rows as covered without that sentence beside them, the demo
has overclaimed on the one axis this project is most careful about. The disclosure is one sentence;
it must not be optional.

**And the same test applied to Leanstral.** The demonstration currently carries exactly one
disclosed trusted assumption, and it is a named, standard one (`VERIFICATION_SCOPE.md` §9). A
reader's trust in the artifact is a function of how few such assumptions there are and how well
each is named. Discharging that assumption in Lean would not reduce the count; it would swap a
well-named assumption for a bespoke one (translation fidelity, §5.2), and it would do so on a
translator the project's own spike calls structurally unfaithful today. The strategic point
generalizes past Lean: **the claim is strengthened by reducing the number of unnamed assumptions,
not by raising the number of proved rows.** Both the coverage question and the Leanstral question
resolve the same way under that test, which is why the recommendation is the same for both.

---

## Edge cases and degenerate inputs

1. **`for-index` with a symbolic upper bound.** Input: `(for-index [i 0 len] (!= (bytes-get b i) 0))`,
   `len` a parameter. Expected: admissibility clause (i) fails; the whole function routes to
   contract-only fallback and then fails the body-faithful bar as a normal rejection. **This is the
   positive witness for the admissibility guard**, the minimal concrete firing input, and it fires
   on the most natural thing an agent will write, which is why the guard must emit a readable
   diagnostic rather than fall back silently. Channel: contract (`LLMLL.md` §5.3.3 exact-reflection
   rule; `data-scope-extension.md:335-342`).
2. **`for-index` with `lo >= hi`.** Input: `(for-index [i 5 5] ...)`. Expected: the empty
   conjunction, `true`. Vacuous, and `--weakness-check` must fire on a contract whose only content
   is a degenerate `for-index`, as it does on implication-only bool posts (roadmap §1.5.2, F-1982-4).
   Channel: contract + trust. The spec states the empty-range value; the expander does not decide it.
3. **A category-(a) row whose refuting mutant does not exist.** Input: T038 modeled as record
   fields. Expected: no mutant violates it, Phase 4 re-dispositions it out, and the ceiling drops to
   the mutation-adequate row of Part 3. Channel: trust (the kill matrix). Designed behavior under
   roadmap §4.4, not a gap.
4. **M-TMO interacting with the error latch.** Input: `Timeout` delivered in the absorbing
   `Terminated` state. Expected: the step must be total over the widened alphabet
   (`Terminated + Timeout -> Terminated`); without that arm the typechecker's exhaustiveness check
   rejects the module. Channel: type. The interesting failure is the other order: a body that lets
   `Timeout` resurrect a terminated connection refutes T016, a characteristic-core row, so widening
   the alphabet strengthens a core crux rather than diluting it.
5. **A `Mail`-mode request under M-MODE.** Input: `RRQ(filename, Mail)`. Expected: request-accept
   emits ERROR and lands in `Denied`; a body that transfers refutes T006. Channel: contract. Note
   T104: a conforming implementation never emits code 7, so its contract is the negative universal
   `(!= (err-code result) 7)`, weak but not vacuous. It is Deployment-modeled rather than Encoded
   for that reason; promoting weak negative universals is how an Encoded fraction stops meaning
   anything.
6. **A Lean certificate over a misstated theorem.** Input: LEAN-GA activated with L1 unrepaired, so
   the emitted theorem carries free `result` and parameters (`leanstral-integration-scope.md` §2).
   Expected: `sanitizeProof` passes (the proof term is non-degenerate), the kernel check passes (the
   theorem elaborates under auto-bound implicits), and `verified-lean` is recorded for a proposition
   that is not the LLMLL obligation. Channel: **spec is silent (gap, flagged)**. This is the one
   Lean-tier failure mode that would damage the trust story rather than fail loudly, and it is why
   Part 5's L4 puts L1 and L2 ahead of any activation.

---

## Verification mapping

| Obligation introduced | Channel | Fragment | Citation |
|---|---|---|---|
| `for-index` over literal bounds, expanded to `k` array-select conjuncts | contract | **QF-AX + QF-LIA, auto-discharged.** No new theory; the array class of `Σ_auto` | `LLMLL.md` §5.3.3 "Array class - complete"; §5.3.5 row `:1020`; `FixpointEmit.hs` array-guard block |
| `for-index` admissibility (literal bounds, width `<= K`, direct-index use) | contract | side condition on emission, not an SMT obligation; violation routes to whole-function fallback | exact-reflection rule, `LLMLL.md` §5.3.3; `data-scope-lever-a-arrays-proposal.md` §6.1 |
| M-TID: TID range refinement, equality and disequality on TID fields | contract | **QF-LIA, auto-discharged** | `LLMLL.md` §5.3.3 QF-LIA core |
| M-ENV: `dg_len = 8 + tftp_len` and packet-size arithmetic | contract | **QF-LIA, auto-discharged** | same |
| M-TMO: `retries` counter against a literal cap, `Timeout` arm postconditions | contract | **QF-LIA + acyclic datatype (the widened event sum), auto-discharged** | `LLMLL.md` §5.3.3 datatype class; §5.3.4 n-arm `EMatch` coverage |
| M-MODE: mail-mode rejection post over the mode enum | contract | **QF-LIA int-tag, auto-discharged** (nullary enums stay pure QF-LIA) | `LLMLL.md` §5.3.4, scrutinee-constructor desugar |
| T057 round-trip fidelity, were it ever pursued | contract | **escapes `Σ_auto`**: needs induction over the block sequence plus symbolic buffer length; `?proof-required`, Lean tier | `LLMLL.md` §5.3.3 Lean path row; `compiler-team-roadmap.md:150` Lever C |
| T014/T086/T037 | none | **escapes `Σ_auto`** with no discharge home on any current track | `data-scope-extension.md` Post 7; this document Part 1(c) |
| Trusted composition schema (per-step to all-traces closure) | trust | **escapes `Σ_auto`**; today a disclosed trusted schema, not an obligation. Lean-dischargeable only after a trace semantics plus a faithfulness argument exist (Part 5.2) | `VERIFICATION_SCOPE.md` §9; roadmap §1.3 |

Nothing in the recommended path (R1, R2, R5) introduces an obligation outside `Σ_auto`, and nothing
in it adds a trusted assumption. That is the point of recommending it.

---

## Affected surface

**If R1 (modeling) only, which is the recommendation:**

- `examples/tftp_rfc1350/VERIFICATION_SCOPE.md` - Rev 1: 34 re-dispositioned rows with the M-* model
  named per row, the Rev 0 counts preserved side by side, §5's STOP evaluation re-run, §8's scope
  matrix amended (the event alphabet gains `Timeout`; the TID and envelope boundaries move).
- `docs/design/rfc-swarm-roadmap-proposal.md` - §5.1 amendment (the four-barrier rule above), §2.1's
  stale 20-30 estimate (D3), §1.1 vs §4.1 STOP reading reconciled (D1), §1.5.1 applied uniformly to
  the timing rows (D2). Doc-lead slot, not mine.
- `experiments/rfc-swarm/PRE-REGISTRATION.md` - the mutant-class taxonomy gains rows for the 34; the
  Phase 4 budget grows accordingly.
- No compiler module. No schema. No `LLMLL.md` change.

**If R3 (`for-index`) is later triggered:**

- `compiler/src/LLMLL/Syntax.hs` (new expression node), `ParserJSON.hs`, `docs/llmll-ast.schema.json`
  (minor bump), `TypeCheck.hs` (bound-variable scoping, int-typed index), `FixpointEmit.hs` (the
  expansion pass and the admissibility guard), `Contracts.hs` (clause-position legality).
- `LLMLL.md` §5.3.3 (array-class paragraph), §5.3.5 (a new row), §12 (grammar), §13.12 (a note that
  `for-index` composes with `bytes-get`'s PROVE-polarity precondition: each expanded index must
  independently discharge `0 <= i < n`, which it does by construction when `[lo, hi) ⊆ [0, n)` and
  fails loudly otherwise).
- `docs/compiler-team-roadmap.md` - a new row, plus the B2/B1b/B3 refusals in "What's NOT on this
  Roadmap".

---

## Risks and open questions

1. **Threshold gaming (severity: highest).** Class: scope / process integrity. Re-modeling after
   seeing the census is post-hoc, and the STOP line was pre-registered. Cite roadmap §4.1 and
   `PRE-REGISTRATION.md`. **Bite: blocks R1 unless the three disarming conditions in Part 4 are
   executed in full.** This is the decision the owner actually faces; the language question is
   secondary to it.
2. **Artifact growth blows the Phase 3 budget.** Class: scope. 25-35 functions becomes plausibly
   40-55; §4.3's STOP pauses the wave at three exhausted holes. **Bite: complicates R1; measure by
   re-running the §10 feasibility probes against a TID-and-timeout-carrying step function before
   committing.**
3. **Deployment-modeled inflation.** Class: verification-ergonomics. Twelve of the 34 land in
   Deployment-modeled, and eight of those hold by construction with no refuting mutant. **Bite:
   only matters at Phase 4, where it self-corrects into the mutation-adequate column; the risk is
   quoting the nominal number in the writeup instead of the mutation-adequate one.**
4. **The M-TMO disclosure gets dropped in editing.** Class: overclaim. A per-event timeout model
   verified without the "the clock is not modeled" sentence beside it is the one overclaim this
   demonstration could plausibly commit. **Bite: complicates R1; mitigated by making the sentence a
   row in the scope matrix, not prose in the writeup.**
5. **`for-index` VC blowup.** Class: decidability-adjacent (performance, not soundness). `K = 64`
   conjuncts times a branched body under the 4096-path cap. **Bite: only at scale; the `K` cap and
   whole-function fallback bound it; `experiments/cdp-perf-0/` is the measurement basis.**
6. **D1's STOP reading is unresolved.** Class: spec-drift. If §1.1's "the qualitative dominates"
   governs, no STOP fired and none of this is urgent; if §4.1 governs, a STOP fired and the owner
   must act. **Bite: determines whether R1 is required or merely available. Resolve before anything
   else.**
7. **A Lean certificate over a misstated theorem** (edge case 6). Class: soundness. L1 is
   structurally unfaithful today (`leanstral-integration-scope.md` §2) and the failure is silent:
   `sanitizeProof` and the kernel both pass. **Bite: blocks any LEAN-GA activation until L1 and L2
   land with independent tests; does not bite while LEAN-GA stays parked, which is R5.**

---

## Open questions for the professor

1. **Is post-census re-modeling defensible under pre-registration discipline, and what is the
   external reference class?** The DO-178C and Common Criteria traceability practice the roadmap
   cites (§1.1) governs *dispositioning*, but does the certification literature have a settled
   convention for revising a scope model after a completeness census, other than "record both
   revisions"? If the convention is stricter than Part 4's three disarming conditions, R1 should be
   refused outright and the demonstration should ship at 32.3%.

2. **Two questions about naming and trading trusted assumptions, which are the same question.**
   (a) Is "timeout as an uninterpreted input event" a recognized idiom with a name and a stated
   caveat in the distributed-systems verification lineage? It converts a real-time property into a
   per-event safety property, and the project already uses its analogue for error causes (T021); if
   a standard caveat sentence exists, it should go into the scope matrix verbatim rather than be
   invented here. (b) Part 5.2 argues that discharging the trusted composition schema in Lean would
   *swap* a named, standard assumption (trace induction, the IronFleet shape) for a bespoke one
   (translation fidelity), and that this is a net loss until the translator is production-grade. Is
   there a settled treatment of that trade in the mechanized-verification literature, where a
   proof-assistant development replaces a schema but introduces a model-fidelity obligation of its
   own? seL4 and CompCert both confront it; if either states a rule for when the swap is worth
   making, that rule should govern L2 and L3 rather than this document's judgment.
