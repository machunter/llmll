# Stage O: the writeup

Write `REPORT.md` from the artifacts below.

## Lead with the right number

Lead with **class-stratified coverage** (rows carried within the verifiable classes) and the
**characteristic-core count**. Do not lead with the raw ledger ratio: the denominator counts
obligations of every genre, including timing and transport rows that no body-level verifier of
any language carries, so the raw ratio measures the document's genre composition rather than
the verifier's reach.

## State the claim precisely

The claim this pipeline supports is:

> Given an RFC, an orchestrating agent built a formal specification traceable clause by clause
> to the source text, and a swarm of blind agents produced an implementation the compiler proves
> satisfies it. Every normative clause is dispositioned: verified, modeled, tested, or excluded
> with a cited reason. The protocol core is verified body-faithfully.

## State what is NOT claimed, explicitly

- **not** that the RFC as a whole is "verified"
- **not** that the agents would have failed without verification (the benchmark is saturated, so
  that is unfalsifiable, and it is not what was measured)
- **not** that `:source` provenance proves fidelity to the RFC; it is a traceability pointer
- **not** that trace-level or timing properties hold

Never frame the result as verification catching agent error.

## Disclose every trusted step

Any closure from per-step invariant preservation to an all-traces property is a **trace
induction**, which is outside the decidable fragment. Disclose it as a trusted schema; do not
let it hide inside the word "verified".

## Report detection yield, not concordance

Report defects found and fixed, each with a concrete witness. Do not report agreement rates or
absence-of-failure. "Found 7 defects, each with a concrete witness, all adjudicated against the
source text" is a stronger sentence than "the formalizations agreed 94% of the time", and it is
the one that means something.

Report the kill matrix **including survivors**. A killed mutant is eliminative evidence that the
contract excludes one behavior; an unkilled mutant set proves nothing.

## Artifacts

### Gate (stage J)
```json
{{gate}}
```

### Coverage lint (stage L)
```
{{coverage}}
```

### Reconciliation (stage E)
```json
{{reconcile}}
```

### Wave (stage M)
```json
{{wave}}
```

### Kill matrix (stage N)
```json
{{kill_matrix}}
```
