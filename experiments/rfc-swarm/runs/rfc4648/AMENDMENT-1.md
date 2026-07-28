# Amendment 1: A1's barrier, and the `B7` criterion

> **Dated 2026-07-27**, after the RFC 4648 run halted at gate J and after the artifact audit.
> Amends the **disposition record** and the **barrier list**. It does **not** amend
> [`../rfc4648-PREDICTION.md`](../rfc4648-PREDICTION.md), which is pre-registered text and stays
> as written, nor the gate's verdict, which stands.
>
> Filed under the playbook's anti-pattern 6: a fired STOP is never silently reinterpreted. The
> argument is shown, the evidence is reproducible, and the STOP is unchanged.

## What is amended

**(1) Row A1's barrier changes from `B7` to `B5`.** Its disposition, `Dispositioned out`, does
not change.

**(2) The `B7` criterion is tightened**, because the run demonstrated that its stated test is
not the test anyone can apply.

## Why: what stage G recorded, and what is actually true

Stage G excluded A1 under `B7`, "true by construction," on this reasoning:

> "every position of a quantum's output tuple is filled by `TABLE[v]` or by the pad constant
> `0x3D`, so the model admits no constructor that places `0x0A` anywhere and **no mutant can
> exercise the row**."

Two separate problems, found by two separate checks.

### The clause was misread

Stage G's reason opens: *"The clause forbids inserting line feeds into base-encoded data after a
specific number of characters."* The pinned source, `00-source/rfc4648.txt` lines 161-163, reads:

> "Implementations MUST NOT add line feeds to base-encoded data **unless** the specification
> referring to this document explicitly directs base encoders to add line feeds after a specific
> number of characters."

The positional qualifier belongs to the **exception**, not to the prohibition. The obligation is
unconditional: do not add line feeds. Extractor A's rendering was faithful and preserved the
`unless`; the misreading entered at disposition. This was found by reading three lines of the
file stage A pins for exactly that purpose.

### The stated `B7` test does not hold for A1

Four probes, run against `llmll 0.14.67`, the same binary the run used:

| Probe | Contract | Body | Verdict |
|---|---|---|---|
| `a1-alone` | A1 clause only, `(not (= result 10))` | emits LF for `v = 0` | **REFUTED** |
| `a1-alone-twin` | same | never emits LF | **SAFE** |
| `a1-redund2` | pre = Table 1 code range + pad; post = A1 clause | identity | **SAFE** |
| `a1-redund2-mutant` | pre widened to admit the control range 0-31 | identity | **REFUTED** |

`a1-alone` refutes. **A mutant can exercise the row**, so the model does admit a constructor that
places `0x0A`: a table entry. The twin's SAFE verdict shows the contract is not merely
over-strong. `a1-redund2` shows the per-quantum surrogate is entailed by A18 (Table 1), and its
mutant shows that probe is testing the entailment rather than passing vacuously.

So the surrogate is **redundant given A18**, which is a different property from true by
construction: it is exercisable the moment A18 moves.

### Why the exclusion nonetheless stands, under a different barrier

The obligation is that an encoder must not **add** line feeds to its output. Adding is a stream
operation, independent of whether it happens at fixed intervals, so correcting the misreading
does not make the clause reachable. No per-quantum model carries insertion between quanta. The
barrier naming that is `B5`, string structure, which is what stage G's own reason argues in its
second sentence: *"That form needs the output as a positioned character sequence."*

The redundancy of the surrogate is recorded as a secondary observation, not as the ground of
exclusion.

## What does not change

| | Before | After |
|---|---|---|
| A1 disposition | `Dispositioned out` | **unchanged** |
| A1 characteristic-core membership | core | **unchanged** |
| Gate J | STOP on the characteristic-core condition | **unchanged** |
| C1+C2+C3 carried | 44/52 | **unchanged**; A1 is excluded either way |
| A1 barrier | `B7` | **`B5`** |

The run halted, it stays halted, and it halted on the same row for the same condition. No
disposition moves as a result of this amendment, so no coverage figure moves.

## The `B7` criterion, tightened

The old text set a test nobody can apply and that this run showed false in its first use:

> "If the model admits no constructor for the forbidden thing, no mutant can exercise the row."

Determining that no mutant exists is the equivalent-mutant problem, undecidable in general
(Budd and Angluin, *Two Notions of Correctness and Their Relation to Testing*, Acta Informatica
18, 1982). The replacement is decidable and states which of the two properties is being claimed:

> **`B7`, entailed by the model or by a sibling row.** Admissible only when the row's own
> obligation is expressible and is entailed either by the declared types alone or by the clauses
> carrying other inventory rows, which must be named. A row whose obligation is not expressible
> is not `B7`; it exits under the barrier naming why it is not expressible. "I could not think of
> a mutant" is not a barrier.

Two consequences for a future run. A `B7` row must name what entails it, which A14, A20, A31 and
A38 already did unprompted ("carried by A2 and A23 to A25"). And a `B7` grant that rests on a
sibling row is contingent on that sibling, so it is not evidence that the row is unreachable in
principle.

## Reproducing this

```bash
export PATH=$(cd compiler && stack path --local-install-root)/bin:$PATH
llmll version    # 0.14.67
```

The four probe sources are reproduced in [`RESULTS.md`](RESULTS.md) §"The A1 probes". Probe
bodies are deliberately not committed as files, per playbook stage H.

## Scope of this amendment

It records that one row's barrier was wrong and that one barrier's definition was wrong. It does
**not** claim the other 19 excluded rows were audited for disposition correctness. What was
checked across all 64 rows is narrower and is reported in [`RESULTS.md`](RESULTS.md) §"Artifact
audit": that citations resolve to the pinned bytes, that normativity strengths are not inflated,
and that each stated reason matches the clause it cites.
