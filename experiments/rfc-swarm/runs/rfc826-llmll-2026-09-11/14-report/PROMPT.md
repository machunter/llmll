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
{
 "driver-ll": "4a stub",
 "stage": "J",
 "artifact": "09-gate/gate.json"
}

```

### Coverage lint (stage L)
```
driver-ll 4a stub
stage=L
artifact=11-freeze/rfc-cov-1.txt

```

### Reconciliation (stage E)
```json
{
 "driver-ll": "4a stub",
 "stage": "E",
 "artifact": "04-reconcile/SUMMARY.json"
}

```

### Wave (stage M)
```json
{
 "driver-ll": "4a stub",
 "stage": "M",
 "artifact": "12-wave/wave.json"
}

```

### Kill matrix (stage N)
```json
[
 {
  "name": "merge-after-opcode",
  "good_twin": false,
  "verdict": "unwritable",
  "as_expected": true,
  "reason": "not-authored (NOT unwritable): no implemented tree. 12-wave/roots.ast.json is the driver-ll stage-M stub, the wave never ran, and there is no function body to mutate. Pre-registration 0.3 consequence 4 and booking rule 5.7.4: stage N writes the full register unauthored, this entry stays in the kill-required denominator, and the kill matrix is VOID, not zero-survivors."
 },
 {
  "name": "promiscuous-add",
  "good_twin": false,
  "verdict": "unwritable",
  "as_expected": true,
  "reason": "not-authored (NOT unwritable): no implemented tree. 12-wave/roots.ast.json is the driver-ll stage-M stub, the wave never ran, and there is no function body to mutate. Pre-registration 0.3 consequence 4 and booking rule 5.7.4: stage N writes the full register unauthored, this entry stays in the kill-required denominator, and the kill matrix is VOID, not zero-survivors."
 },
 {
  "name": "old-address-wins",
  "good_twin": false,
  "verdict": "unwritable",
  "as_expected": true,
  "reason": "not-authored (NOT unwritable): no implemented tree. 12-wave/roots.ast.json is the driver-ll stage-M stub, the wave never ran, and there is no function body to mutate. Pre-registration 0.3 consequence 4 and booking rule 5.7.4: stage N writes the full register unauthored, this entry stays in the kill-required denominator, and the kill matrix is VOID, not zero-survivors."
 },
 {
  "name": "spoof-binding",
  "good_twin": false,
  "verdict": "unwritable",
  "as_expected": true,
  "reason": "not-authored (NOT unwritable): no implemented tree. 12-wave/roots.ast.json is the driver-ll stage-M stub, the wave never ran, and there is no function body to mutate. Pre-registration 0.3 consequence 4 and booking rule 5.7.4: stage N writes the full register unauthored, this entry stays in the kill-required denominator, and the kill matrix is VOID, not zero-survivors."
 },
 {
  "name": "merge-key-substituted",
  "good_twin": false,
  "verdict": "unwritable",
  "as_expected": true,
  "reason": "not-authored (NOT unwritable): no implemented tree. 12-wave/roots.ast.json is the driver-ll stage-M stub, the wave never ran, and there is no function body to mutate. Pre-registration 0.3 consequence 4 and booking rule 5.7.4: stage N writes the full register unauthored, this entry stays in the kill-required denominator, and the kill matrix is VOID, not zero-survivors."
 },
 {
  "name": "merge-flag-not-set",
  "good_twin": false,
  "verdict": "unwritable",
  "as_expected": true,
  "reason": "not-authored (NOT unwritable): no implemented tree. 12-wave/roots.ast.json is the driver-ll stage-M stub, the wave never ran, and there is no function body to mutate. Pre-registration 0.3 consequence 4 and booking rule 5.7.4: stage N writes the full register unauthored, this entry stays in the kill-required denominator, and the kill matrix is VOID, not zero-survivors."
 },
 {
  "name": "merge-flag-leaks",
  "good_twin": false,
  "verdict": "unwritable",
  "as_expected": true,
  "reason": "not-authored (NOT unwritable): no implemented tree. 12-wave/roots.ast.json is the driver-ll stage-M stub, the wave never ran, and there is no function body to mutate. Pre-registration 0.3 consequence 4 and booking rule 5.7.4: stage N writes the full register unauthored, this entry stays in the kill-required denominator, and the kill matrix is VOID, not zero-survivors."
 },
 {
  "name": "discard-suppressed",
  "good_twin": false,
  "verdict": "unwritable",
  "as_expected": true,
  "reason": "not-authored (NOT unwritable): no implemented tree. 12-wave/roots.ast.json is the driver-ll stage-M stub, the wave never ran, and there is no function body to mutate. Pre-registration 0.3 consequence 4 and booking rule 5.7.4: stage N writes the full register unauthored, this entry stays in the kill-required denominator, and the kill matrix is VOID, not zero-survivors."
 },
 {
  "name": "tha-harvest",
  "good_twin": false,
  "verdict": "unwritable",
  "as_expected": true,
  "reason": "not-authored (NOT unwritable): no implemented tree. 12-wave/roots.ast.json is the driver-ll stage-M stub, the wave never ran, and there is no function body to mutate. Pre-registration 0.3 consequence 4 and booking rule 5.7.4: stage N writes the full register unauthored, this entry stays in the kill-required denominator, and the kill matrix is VOID, not zero-survivors."
 },
 {
  "name": "reply-fields-not-swapped",
  "good_twin": false,
  "verdict": "unwritable",
  "as_expected": true,
  "reason": "not-authored (NOT unwritable): no implemented tree. 12-wave/roots.ast.json is the driver-ll stage-M stub, the wave never ran, and there is no function body to mutate. Pre-registration 0.3 consequence 4 and booking rule 5.7.4: stage N writes the full register unauthored, this entry stays in the kill-required denominator, and the kill matrix is VOID, not zero-survivors."
 },
 {
  "name": "reply-op-request",
  "good_twin": false,
  "verdict": "unwritable",
  "as_expected": true,
  "reason": "not-authored (NOT unwritable): no implemented tree. 12-wave/roots.ast.json is the driver-ll stage-M stub, the wave never ran, and there is no function body to mutate. Pre-registration 0.3 consequence 4 and booking rule 5.7.4: stage N writes the full register unauthored, this entry stays in the kill-required denominator, and the kill matrix is VOID, not zero-survivors."
 },
 {
  "name": "reply-broadcast",
  "good_twin": false,
  "verdict": "unwritable",
  "as_expected": true,
  "reason": "not-authored (NOT unwritable): no implemented tree. 12-wave/roots.ast.json is the driver-ll stage-M stub, the wave never ran, and there is no function body to mutate. Pre-registration 0.3 consequence 4 and booking rule 5.7.4: stage N writes the full register unauthored, this entry stays in the kill-required denominator, and the kill matrix is VOID, not zero-survivors."
 },
 {
  "name": "reply-to-reply",
  "good_twin": false,
  "verdict": "unwritable",
  "as_expected": true,
  "reason": "not-authored (NOT unwritable): no implemented tree. 12-wave/roots.ast.json is the driver-ll stage-M stub, the wave never ran, and there is no function body to mutate. Pre-registration 0.3 consequence 4 and booking rule 5.7.4: stage N writes the full register unauthored, this entry stays in the kill-required denominator, and the kill matrix is VOID, not zero-survivors."
 },
 {
  "name": "request-unicast",
  "good_twin": false,
  "verdict": "unwritable",
  "as_expected": true,
  "reason": "not-authored (NOT unwritable): no implemented tree. 12-wave/roots.ast.json is the driver-ll stage-M stub, the wave never ran, and there is no function body to mutate. Pre-registration 0.3 consequence 4 and booking rule 5.7.4: stage N writes the full register unauthored, this entry stays in the kill-required denominator, and the kill matrix is VOID, not zero-survivors."
 },
 {
  "name": "spa-tpa-transposed",
  "good_twin": false,
  "verdict": "unwritable",
  "as_expected": true,
  "reason": "not-authored (NOT unwritable): no implemented tree. 12-wave/roots.ast.json is the driver-ll stage-M stub, the wave never ran, and there is no function body to mutate. Pre-registration 0.3 consequence 4 and booking rule 5.7.4: stage N writes the full register unauthored, this entry stays in the kill-required denominator, and the kill matrix is VOID, not zero-survivors."
 },
 {
  "name": "lookup-key-partial",
  "good_twin": false,
  "verdict": "unwritable",
  "as_expected": true,
  "reason": "not-authored (NOT unwritable): no implemented tree. 12-wave/roots.ast.json is the driver-ll stage-M stub, the wave never ran, and there is no function body to mutate. Pre-registration 0.3 consequence 4 and booking rule 5.7.4: stage N writes the full register unauthored, this entry stays in the kill-required denominator, and the kill matrix is VOID, not zero-survivors."
 },
 {
  "name": "hit-returns-other",
  "good_twin": false,
  "verdict": "unwritable",
  "as_expected": true,
  "reason": "not-authored (NOT unwritable): no implemented tree. 12-wave/roots.ast.json is the driver-ll stage-M stub, the wave never ran, and there is no function body to mutate. Pre-registration 0.3 consequence 4 and booking rule 5.7.4: stage N writes the full register unauthored, this entry stays in the kill-required denominator, and the kill matrix is VOID, not zero-survivors."
 },
 {
  "name": "miss-emits-nothing",
  "good_twin": false,
  "verdict": "unwritable",
  "as_expected": true,
  "reason": "not-authored (NOT unwritable): no implemented tree. 12-wave/roots.ast.json is the driver-ll stage-M stub, the wave never ran, and there is no function body to mutate. Pre-registration 0.3 consequence 4 and booking rule 5.7.4: stage N writes the full register unauthored, this entry stays in the kill-required denominator, and the kill matrix is VOID, not zero-survivors."
 },
 {
  "name": "request-op-reply",
  "good_twin": false,
  "verdict": "unwritable",
  "as_expected": true,
  "reason": "not-authored (NOT unwritable): no implemented tree. 12-wave/roots.ast.json is the driver-ll stage-M stub, the wave never ran, and there is no function body to mutate. Pre-registration 0.3 consequence 4 and booking rule 5.7.4: stage N writes the full register unauthored, this entry stays in the kill-required denominator, and the kill matrix is VOID, not zero-survivors."
 },
 {
  "name": "sha-foreign",
  "good_twin": false,
  "verdict": "unwritable",
  "as_expected": true,
  "reason": "not-authored (NOT unwritable): no implemented tree. 12-wave/roots.ast.json is the driver-ll stage-M stub, the wave never ran, and there is no function body to mutate. Pre-registration 0.3 consequence 4 and booking rule 5.7.4: stage N writes the full register unauthored, this entry stays in the kill-required denominator, and the kill matrix is VOID, not zero-survivors."
 },
 {
  "name": "pro-substituted-on-emit",
  "good_twin": false,
  "verdict": "unwritable",
  "as_expected": true,
  "reason": "not-authored (NOT unwritable): no implemented tree. 12-wave/roots.ast.json is the driver-ll stage-M stub, the wave never ran, and there is no function body to mutate. Pre-registration 0.3 consequence 4 and booking rule 5.7.4: stage N writes the full register unauthored, this entry stays in the kill-required denominator, and the kill matrix is VOID, not zero-survivors."
 },
 {
  "name": "hrd-substituted-on-emit",
  "good_twin": false,
  "verdict": "unwritable",
  "as_expected": true,
  "reason": "not-authored (NOT unwritable): no implemented tree. 12-wave/roots.ast.json is the driver-ll stage-M stub, the wave never ran, and there is no function body to mutate. Pre-registration 0.3 consequence 4 and booking rule 5.7.4: stage N writes the full register unauthored, this entry stays in the kill-required denominator, and the kill matrix is VOID, not zero-survivors. The separate M-ONELINK unwritable question for this entry is undetermined, not resolved."
 },
 {
  "name": "pln-from-packet",
  "good_twin": false,
  "verdict": "unwritable",
  "as_expected": true,
  "reason": "not-authored (NOT unwritable): no implemented tree. 12-wave/roots.ast.json is the driver-ll stage-M stub, the wave never ran, and there is no function body to mutate. Pre-registration 0.3 consequence 4 and booking rule 5.7.4: stage N writes the full register unauthored, this entry stays in the kill-required denominator, and the kill matrix is VOID, not zero-survivors."
 },
 {
  "name": "unsolicited-reply-merges",
  "good_twin": true,
  "verdict": "unwritable",
  "as_expected": true,
  "reason": "not-authored (NOT unwritable): no implemented tree. 12-wave/roots.ast.json is the driver-ll stage-M stub, the wave never ran, and there is no correct body to write a variant of. Pre-registration 0.3 consequence 4 and booking rule 5.7.4: stage N writes the full register unauthored, this good twin stays in the good-twin denominator, and the kill matrix is VOID. Its SAFE verdict was not obtained, so the over-strong-contract guard was not exercised."
 },
 {
  "name": "tha-arbitrary",
  "good_twin": true,
  "verdict": "unwritable",
  "as_expected": true,
  "reason": "not-authored (NOT unwritable): no implemented tree. 12-wave/roots.ast.json is the driver-ll stage-M stub, the wave never ran, and there is no correct body to write a variant of. Pre-registration 0.3 consequence 4 and booking rule 5.7.4: stage N writes the full register unauthored, this good twin stays in the good-twin denominator, and the kill matrix is VOID. Its SAFE verdict was not obtained, so the over-strong-contract guard was not exercised."
 },
 {
  "name": "optional-checks-omitted",
  "good_twin": true,
  "verdict": "unwritable",
  "as_expected": true,
  "reason": "not-authored (NOT unwritable): no implemented tree. 12-wave/roots.ast.json is the driver-ll stage-M stub, the wave never ran, and there is no correct body to write a variant of. Pre-registration 0.3 consequence 4 and booking rule 5.7.4: stage N writes the full register unauthored, this good twin stays in the good-twin denominator, and the kill matrix is VOID. Its SAFE verdict was not obtained, so the over-strong-contract guard was not exercised and obligation O2 is not evidenced by this run."
 },
 {
  "name": "multi-owner-target",
  "good_twin": true,
  "verdict": "unwritable",
  "as_expected": true,
  "reason": "not-authored (NOT unwritable): no implemented tree. 12-wave/roots.ast.json is the driver-ll stage-M stub, the wave never ran, and there is no correct body to write a variant of. Pre-registration 0.3 consequence 4 and booking rule 5.7.4: stage N writes the full register unauthored, this good twin stays in the good-twin denominator, and the kill matrix is VOID. Its SAFE verdict was not obtained, so the over-strong-contract guard was not exercised."
 },
 {
  "name": "structural-variant",
  "good_twin": true,
  "verdict": "unwritable",
  "as_expected": true,
  "reason": "not-authored (NOT unwritable): no implemented tree. 12-wave/roots.ast.json is the driver-ll stage-M stub, the wave never ran, and there is no correct body to write a variant of. Pre-registration 0.3 consequence 4 and booking rule 5.7.4: stage N writes the full register unauthored, this good twin stays in the good-twin denominator, and the kill matrix is VOID. Its SAFE verdict was not obtained, so the over-strong-contract guard was not exercised."
 },
 {
  "name": "hw-type-agnostic",
  "good_twin": true,
  "verdict": "unwritable",
  "as_expected": true,
  "reason": "not-authored (NOT unwritable): no implemented tree. 12-wave/roots.ast.json is the driver-ll stage-M stub, the wave never ran, and there is no correct body to write a variant of. Pre-registration 0.3 consequence 4 and booking rule 5.7.4: stage N writes the full register unauthored, this good twin stays in the good-twin denominator, and the kill matrix is VOID. Its SAFE verdict was not obtained, so the over-strong-contract guard was not exercised."
 }
]
```
