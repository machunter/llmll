# RFC 4648 (Base16/32/64): the run that stopped

> **Status:** 2026-07-27, compiler v0.14.67. Driver:
> [`scripts/rfc_to_implementation.py`](../../../../scripts/rfc_to_implementation.py), stages A-I
> then halted at gate J. Prediction, committed before launch:
> [`../rfc4648-PREDICTION.md`](../rfc4648-PREDICTION.md). Barrier correction:
> [`AMENDMENT-1.md`](AMENDMENT-1.md).
> Prior runs: [`../rfc826/RESULTS.md`](../rfc826/RESULTS.md),
> [`examples/tftp_rfc1350/`](../../../../examples/tftp_rfc1350/).

## Why this run exists

Two runs had passed every gate. **No stop condition had ever fired for a real reason.** Gate J
passed on TFTP and on ARP; gate L failed once on ARP and only because of a hardcoded tag prefix
in our own lint, which the resume bug then bypassed rather than halting.

A method whose stop conditions have never stopped anything has not shown that it has working
stop conditions. This run existed to fire one, and it did.

RFC 4648 was chosen because it is **plausibly attemptable**. It talks about octets and groups of
bits, its normative rules are crisp, and nothing on its surface announces that it is out of
reach. A target obviously beyond the fragment, like a hash function, would have made a refusal
meaningless.

## Result

```
[rfc-swarm] stage J [gate] the gate
[rfc-swarm]   coverage of verifiable subject matter (C1+C2+C3): 44/52 (reported, not graded)
[rfc-swarm]   characteristic core: 23 rows, 1 dispositioned out
[rfc-swarm] STOP at stage J: STOP (stage J): characteristic-core rows dispositioned out: ['A1'].
             The target is re-scoped, not re-graded.
```

Stages K through O never started. The run cost 4565s of wall clock, about 76 minutes, and never
reached the wave.

| | RFC 4648 | ARP | TFTP |
|---|---|---|---|
| dual-extraction line-coverage Jaccard | **0.9732** | 0.8551 | 0.8655 / 0.725 |
| rule agreement (Cohen's kappa) | **0.8057** | 0.824 | 0.9378 |
| inventory | **64 rows** | 91 | 124 |
| Encoded / modeled / vectored / out | **39 / 5 / 0 / 20** | 39 / 3 / 1 / 48 | 46 / 20 / 5 / 53 |
| characteristic core | **23, one dispositioned out** | 19, none out | 15, none out |
| coverage of C1+C2+C3 | **44/52 = 84.6%** | 42/76 = 55.3% | 51/65 = 78.5% corrected |
| feasibility probes | **6/6 SAFE, 6/6 mutants refuted** | 6/6 | 4/4 |
| gate J | **STOP** | PASS | PASS |
| implementation | **never reached** | 22/22 verified | 23/23 verified |

## Scored against the committed prediction

The prediction was written and committed at `c212fc0`, before the driver started, so it could not
be retrofitted.

| Predicted | Outcome |
|---|---|
| 1. STOP at gate J on the characteristic-core condition | **Fired, exactly that condition** |
| 2. Failing that, STOP on the barrier list | n/a; `exclusions_outside_barrier_list` was empty |
| 3. Failing both, completion with C1+C2+C3 **below 20%** | did not complete; the ledger recorded **84.6%** |
| Falsifier: a green kill matrix | did not occur |
| Cost note: halts at J, spends only A through I, never reaches the wave | **exactly what happened** |

**The headline prediction is right and the reasoning behind it is wrong**, which is worth more
than if both had been right.

The prediction expected the encode/decode correspondence to hit the same B5 string-structure wall
that took ARP's `8 + 2*ar$hln + ar$pln`: "24 bits regrouped into four 6-bit symbols, with
padding." It did not. Bit regrouping verified as fixed-width arithmetic within a quantum, and
stage H returned 6/6 probes SAFE with 6/6 mutants refuted, including the base64 tail cases the
prediction named as the wall. What halted the run was **line wrapping**, a clause the prediction
never considered.

The third clause is contradicted in the direction that matters. 84.6% of verifiable subject
matter carried is higher than either prior run. **RFC 4648 is not the bad-fit target it was
chosen to be.** It is a good fit for its per-quantum core, and it halted on a single clause about
the output stream.

## Why the STOP means something: stage F was blind

The core condition only decides the target if the core was not drawn around what happens to
succeed. Checked at the time rather than assumed: stage F's 75KB prompt contains the task, the
output contract, the selection criteria, the reconciled inventory, and the pinned RFC text. It
contains **zero** occurrences of `scope.md`, `01-scope`, "scope decision", "decidable fragment",
"fragment", or `LLMLL`. The scope document stage B wrote is not in it, and neither is any
description of what the verifier can reach. The prompt says so directly:

> "Do not include a clause merely because it is important-sounding, and do not include one
> because you expect it to be easy to verify. **You do not yet know what will verify, and that is
> deliberate.**"

So a fragment-blind agent named A1 core, and a fragment-aware stage excluded it. Neither could
see the other. That is what makes the halt a finding rather than a tautology.

The same blindness produced the run's most interesting non-result: of 23 core rows, **22 sit
inside the boundary stage B drew**. Asked what makes base64 *be* base64, an agent that had never
been told what the verifier can do returned alphabet tables, per-quantum bit splits, MSB-first
traversal, right-side zero fill, and the eight final-quantum pad cases. All of them verify.

## What actually halted it

A1 is RFC 4648 lines 161-163, "Implementations MUST NOT add line feeds to base-encoded data."
Stage F named it core: an encoder that wraps its output in line feeds is producing MIME's
Content-Transfer-Encoding rather than the base encoding this document defines, and line wrapping
is one of the two discrepancies section 1 says the RFC exists to settle.

Stage G excluded it. The stated barrier was `B7`, "true by construction," and
[`AMENDMENT-1.md`](AMENDMENT-1.md) corrects that to `B5`, string structure, on evidence. The
short version: an encoder must not **add** line feeds, adding is a stream operation, and no
per-quantum model carries insertion between quanta.

**The prediction's mechanism is therefore partly rehabilitated by the correction.** The wall is
the B5 string-structure wall it named. It fell on a clause about line wrapping rather than on bit
regrouping.

## The A1 probes

Run against `llmll 0.14.67`, the binary the run used. These settled by measurement what four
rounds of design argument had not.

| Probe | Contract | Body | Verdict |
|---|---|---|---|
| `a1-alone` | A1 clause only, `(not (= result 10))` | emits LF for `v = 0` | **REFUTED** |
| `a1-alone-twin` | same | never emits LF | **SAFE** |
| `a1-redund2` | pre = Table 1 code range + pad; post = A1 clause | identity | **SAFE** |
| `a1-redund2-mutant` | pre widened to admit the control range 0-31 | identity | **REFUTED** |

```lisp
;; a1-alone: is A1 unfalsifiable on its own?  It is not: this REFUTES.
(def encode-symbol [v: int]
  (pre (and (>= v 0) (<= v 63)))
  (post (not (= result 10)))
  (if (= v 0) 10 65))

;; a1-redund2: is the per-quantum surrogate entailed by Table 1?  SAFE: yes.
(def a1-implied-by-table [code: int]
  (pre (or (and (>= code 65) (<= code 90))
       (or (and (>= code 97) (<= code 122))
       (or (and (>= code 48) (<= code 57))
       (or (= code 43) (or (= code 47) (= code 61)))))))
  (post (not (= result 10)))
  code)
```

`a1-alone` refuting is the decisive one: a mutant **can** exercise the row, so the model does
admit a constructor placing `0x0A`, namely a table entry. The `B7` criterion as written was false
on the row that fired the gate. The surrogate is redundant given A18 rather than true by
construction, and redundancy is contingent: it is exercisable the moment A18 moves.

Probe bodies are not committed as files, per playbook stage H.

## Artifact audit

Every row's citations were checked against the bytes stage A pinned, because the pipeline's whole
provenance claim rests on later stages reading those bytes rather than recollection.

| Check | Result |
|---|---|
| Quote appears verbatim within its cited line span | **64/64** |
| Line spans in bounds and correctly placed | **64/64** |
| Declared RFC 2119 strength actually present in the quote | **64/64**, zero inflation |
| Core-row obligation faithfully renders its quote | **23/23** |
| Excluded-row reason matches the clause it cites | **19/20** |
| Tables 1-4 carry a pad row, Table 5 does not (the `B7` arguments for A3 and A57 depend on this) | **true as stated** |

The one defect is A1's disposition reason, which restates the clause as forbidding line feeds
"after a specific number of characters," moving the positional qualifier out of the `unless`
exception and into the prohibition. Extraction was faithful and preserved the exception; the
misreading entered at disposition.

**Scope of this audit.** It checked that each stated reason matches the clause it cites. It did
**not** re-derive whether each disposition is correct; that is a different claim and this audit
does not support it.

One census defect surfaced without being looked for. **A3 bundles two obligations in one row**,
a restatement of sections 4 and 6 plus a genuine claim about base16 needing no padding, against
the rubric's one-obligation-per-row rule. Stage G diagnosed the bundling correctly. The defect is
at extraction, and it is the kind of thing the dual-extraction reconciliation is supposed to
catch and did not.

## Two things the strength distribution says about this target

RFC 4648 is dated 2006 and declares the RFC 2119 convention at L140-142, so uppercase keywords
are read at face value. The rubric then counted what that buys: **seven uppercase instances in
the entire document**, four MUST-family and three MAY, zero SHOULD, zero SHALL, zero REQUIRED.
Across the 64-row inventory the strengths are 5 must, 6 should, 5 may, and **48 declarative**.

So the post-2119 branch applies and buys almost nothing. The substance of this RFC lives in
declarative definitions and five alphabet tables, and a keyword-triggered extraction would have
missed the specification. That is worth recording because it is the opposite of what the
document's date suggests.

The other statistic worth noting is the split between the two agreement measures. Line-coverage
Jaccard is the highest of the three runs at 0.9732, with 218 lines in both censuses, 224 in the
union, and one genuine coverage disagreement in the whole document. Rule agreement is the lowest
at kappa 0.8057. The extractors agreed almost exactly on **which text is normative** and
disagreed more about **which rubric rule licenses it**. The denominator is well determined here;
the classification is not.

## What this run cost, and what it bought

The prediction said a working gate makes a bad-fit run cheap: it halts at J, having spent only
stages A through I, and never reaches the wave. That is exactly what happened, at 76 minutes and
no wave.

What it bought:

1. **A stop condition fired for a real reason**, for the first time in three runs. Before this,
   the claim that the method has working stop conditions rested on gates that had never stopped
   anything.
2. **A defect in the barrier list**, found by using it. `B7`'s stated test was undecidable as
   written and false on its first consequential application. Corrected in
   [`AMENDMENT-1.md`](AMENDMENT-1.md).
3. **A clause misread by an agent, caught by reading the pinned source.** One `sed` on the file
   stage A exists to pin.
4. **A compiler bug**, below.
5. **A target that is a better fit than predicted**, which is a fact about the method's reach
   that two passing runs could not have produced.

## Compiler bug found in passing

A contracted `def` whose body is a **boolean literal** crashes liquid-fixpoint:

```lisp
(module crash-min)
(def f [n: int] (pre (> n 0)) (post (not (= n 10))) true)
```

```
ERROR: liquid-fixpoint: ... elaborate solver elabBE 2 "VV##0" ...
The sort bool is not numeric / Cannot unify int with bool in expression: VV##0 == true
in environment  VV##0 := int
```

The emitted constraint names the defect directly:

```
bind 1 result : { v : int | true }
constraint:
  lhs { result : int | (n > 0) && (result = true) }
  rhs { result : int | (not (n = 10)) }
```

The `result` binder is emitted at sort `int` although the function returns `bool`, and the
body's reflection then puts `result = true` against it. **Annotating the return type is the
workaround**: the identical def written `-> bool` emits `bind 1 result : { v : bool | true }`
and returns a normal verdict. So the sort is defaulting rather than being derived from the
inferred body type.

Controls isolate the trigger. Bool returns with no contract, with a `pre` only, or with a
*computed* bool body (`(> n 0)`) all verify; `(post (= result true))` with a literal body also
crashes, so it is the literal body and not the post shape. Fails closed throughout: exit 1, a
crash, never a false SAFE, so no prior verdict is affected. No bool-returning contracted `def`
exists in the fixtures or examples, which is consistent with this never having been hit.

Routed as **FQ-BOOL-SORT-1** in
[`docs/compiler-team-roadmap.md`](../../../../docs/compiler-team-roadmap.md), with the two
candidate emit sites; not fixed here.

## What this run implies for the driver spec

The driver's own specification,
[`../../targets/driver-spec.txt`](../../targets/driver-spec.txt), is written as an RFC and its
section 6 governs gates. Four things this run taught are not in it. Recorded here because the
rewrite is owed and has not been done.

**Section 6, the remedy follows from the barrier's class.** The gate emits one string for every
barrier, "The target is re-scoped, not re-graded." That is correct for some barriers and useless
for others, because the members of the closed list do not have the same modal status:

| Class | Barriers | Asserts | Remedy on a core row |
|---|---|---|---|
| fragment-relative | `B3`, `B4`, `B5`, `B8` | `Σ_auto` does not reach it; no re-scoping inside the fragment recovers it | choose a different target |
| model-relative | `B2`, `B7` | the scope decision determines it | revisit the scope decision |
| document-relative | `B6` | the row is not live subject matter | extraction or core-selection error |

A1's correction makes this concrete: under `B7` the halt pointed at stage B, under `B5` it points
at the target. Each assignment above has a prior ruling behind it in
[`../../../../docs/design/rfc-swarm-coverage-review.md`](../../../../docs/design/rfc-swarm-coverage-review.md):
`B2` from F-6, `B3` from F-7 and F-13, `B5` from F-8. `B1` is deliberately unassigned, because
every property is an intersection of a safety property and a liveness property (Alpern and
Schneider, *Defining Liveness*, IPL 21(4), 1985) and the safety half is often reachable, so one
modality for it would be wrong in one direction or the other. No `B1` row has fired yet.

**Section 6, a barrier's definition must state a test someone can apply.** The closed-list
requirement constrains membership but not decidability. `B7` was defined as "no mutant can
exercise the row," which is undecidable in general and was false on the first row that fired the
gate. Corrected in [`AMENDMENT-1.md`](AMENDMENT-1.md).

**Section 6, a gate condition must not rest on an unevidenced input.** The gate evaluated its
condition correctly over an input that was an unchecked assertion. Section 6 requires the gate to
check the condition; nothing requires the condition's inputs to carry evidence.

**Sections 7 and 14, a citation must be checkable against the pinned bytes.** Section 7 requires
delegated output to be validated against its declared shape, which cannot catch a reason that
misreads its own quote. Section 14 pins the source and requires later stages to read it, but
nothing verifies that they did. The audit in this document took one pass and found one.

*Written, 2026-07-28.* Both sections now carry it, and the driver runs it as **stage G2** between
the disposition pass and the probes. Building it corrected one thing this document assumed. The
audit reported "quote appears verbatim within its cited line span, 64/64", which reads as though
a substring test would reproduce it; it would not. Run against the committed TFTP census and the
real RFC 1350 bytes, a substring test fails **22 of 113 correct rows**, because a census
abbreviates a long clause with an ellipsis and flattens a multi-line packet diagram onto one
line. The mechanical check is therefore token coverage, whose threshold is measured rather than
chosen: true citations bottom out at 0.875, and the same quotes against 6655 wrong spans reach
0.500 at the 99th percentile.

## What a fourth run should test

**Not another bad-fit target.** Gate J's characteristic-core condition is binary and its truth
table is now complete across three runs: no core row excluded, pass, twice; one core row
excluded, stop, once. A target that fails harder reaches the same verdict by the same path, so it
teaches nothing about that condition. This run also showed that fit prediction is something the
method does poorly, since RFC 4648 was selected as bad-fit and carried the most of the three.

1. **A run that reaches the wave.** Gate L and the per-fill acceptance bar in stage M have still
   never fired for a real reason: ARP's gate L failure was a hardcoded tag prefix in our own
   lint, and this run halted at J without reaching either. The next target should be chosen to
   **pass** gate J, the opposite of this run's heuristic.
2. **The gate's inputs, not its logic.** The one firing on record was triggered by an exclusion
   whose stated reasoning did not survive a probe. A person checked that, not the pipeline.
   **Stage G2 now does**, as of 2026-07-28: it resolves every citation against the pinned bytes
   mechanically, delegates the reading of each stated reason, and halts on a core row whose
   reason misreads its clause. It has never run live, so what is settled is that the check is
   buildable and what it costs, not that it catches anything a person would not.
3. **A `B7` row under the corrected criterion.** Six of this run's eight `B7` rows named what
   entails them unprompted. Whether that holds when the rule requires it is untested.
4. **No human in the loop at all.** Still not achieved, and this run moved backwards: it needed a
   person to read three lines of the RFC and to write four probes.
