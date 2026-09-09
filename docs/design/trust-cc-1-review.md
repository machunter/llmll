---
title: "Professor review: TRUST-CC-1, retiring a lattice element that nothing produces"
status: "Standalone review, TWO rounds. Not folded into the proposal; doc-lead folds on settlement (DOC-CONSOLIDATE M2). Round 1 reviewed Rev 0 and produced Rev 1; round 2 reviewed Rev 1 and produced Rev 2. Both rounds ADOPTED the proposal. Round 2's single open question was ANSWERED by the language-team in Rev 2 §12.2, and it rejected both positions this review offered, on a measurement this review did not take."
author: professor
date: 2026-09-08
reviews: "docs/design/trust-cc-1-proposal.md (Rev 0, then Rev 1)"
---

# TRUST-CC-1: retiring a lattice element that nothing produces

## What the proposal says

`contract-checked` is one of two middle elements of the evidence lattice in
`LLMLL.md` §4.4, and no component of the compiler assigns it. The proposal
retires `DLContractChecked` from `DisplayLevel` and reports the state the name
denoted as an orthogonal `body_fallback` marker on the trust report, following
the `termination_unverified` precedent.

**Both rounds adopted it.** Neither round found a soundness objection to the
retirement. Every finding below concerns the *arguments* the proposal used, the
scope of a finding it filed, or a claim it made without running the case.

---

# Round 1, on Rev 0

## Gaps and hazards

**1. The decisive evidence sits in `ProofArtifact.hs`, and Rev 0 filed it as a
risk.** Classify: soundness, in the proposal's favour. `mkFnRecord` in
[`../../compiler/src/LLMLL/ProofArtifact.hs`](../../compiler/src/LLMLL/ProofArtifact.hs)
is labelled "THE KERNEL" and is the sole gate to a `FnRecord`. Its first rule
rejects a positive tier that also carries a fallback reason, as
`PositiveWithFallback`, and its haddock names the tier in the positive set:
"A positive tier (verified / contract-checked / tested) is rejected when ... it
carries a fallback reason (it did not, in fact, stay body-faithful)."
`isPositiveTier` includes `TContractChecked`. The kernel therefore already
forbids the acquisition path `LLMLL.md` §4.4 stated. Bite: this settles the
"give it a producer" option on internal evidence, and it is stronger than the
`isSolverBacked` argument Rev 0 led with.

**2. §2's "anti-signal" argument rests on a contestable reading.** Classify:
ergonomic. The spec sentence reads "pre ⇒ post is valid, holds for all models of
the contract pair". Rev 0 took `result` as free and concluded the check is an
anti-signal. A reviewer can answer that "models of the contract pair" means
models in which the pair holds, under which the sentence is trivially true. Both
readings are fatal and Rev 0 argued only one. Bite: complicates.

**3. A third option exists and Rev 0 prices only two.** Classify: scope. The
middle option is to keep the constant and remove its unjustified eliminations,
making `isSolverBacked` return `False` while leaving the constructor, the
sidecar vocabulary and `tierFromText` untouched. Rev 0 recorded only the
"give it a producer" counter-position. Bite: complicates.

**4. The sidecar finding was withdrawn too quickly.** Classify: soundness. Rev 0
withdrew its sidecar framing on the correct observation that `verified` is
equally writable, then dropped the subject.
`downgradeStaleVerifiedSidecar` in
[`../../compiler/src/LLMLL/TrustReport.hs`](../../compiler/src/LLMLL/TrustReport.hs)
states its own scope: "Records that are not `erBodyFaithful` are passed through
untouched (they make no body-faithful admission claim)." A record claiming
`verified` with the body-faithful flag unset is therefore never hash-checked.
Bite: does not block, and belongs in its own row rather than dropped.

**5. The marker's propagation is unspecified.** Classify: ergonomic. Rev 0 §5.3
said "derived at report-build time" without saying whether the marker is local
or transitive. The precedent is not silent: `NC-034` marks every member of an
undischarged cycle. Bite: complicates.

**6. The anti-conflation rationale needs a home.** Classify: spec-drift, minor.
Rev 0 §5.1 removes the incomparability paragraph from `LLMLL.md` §4.4 without
saying where its rationale goes. Bite: matters at scale only.

## Recommendation

Adopt. Retire the element and ship the marker. Rank: retirement first,
elimination-stripping second, producer-assignment rejected.

The reason retirement wins is not hygiene, and Rev 0 did not state it in these
terms. **An evidence lattice is not a policy lattice.** In an information-flow
system after Denning (1976) and Volpano, Smith and Irvine (1996), a label with no
producer is a legitimate policy reservation, because labels are declared by the
programmer and the lattice is fixed independently of what any analysis derives.
Evidence levels are not declarations. They are propositions about what was
checked, and a proposition needs an introduction rule.

`DLContractChecked` has **elimination rules and no introduction rule**:
`isSolverBacked` extracts trust from it, `evidenceMeet` and `evidenceCovers`
compute with it, `emitTrustGap` suppresses a warning on it, and `isPositiveTier`
counts it as positive. Nothing introduces it. Under the harmony criterion that
Gentzen's inversion principle motivates, and that Prawitz and Dummett make
precise, eliminations must be justified by the corresponding introductions.
Eliminations with no introduction extract more than anything can put in. That is
the principled statement of the defect, and it is what separates this case from a
policy-lattice reservation.

Three revisions: promote hazard 1 into the argument; rewrite §2 per hazard 2;
add the elimination-stripping option and reject it.

I do not recommend a graded-modality treatment. Grading in the sense of Granule
or quantitative type theory buys compositional arithmetic on the grade, and
nothing here composes.

## Open questions, round 1

**Q1. Specify the marker's propagation, and say why.** I believe the answer is
local, because `NC-024` already floors a caller's effective level through the
meet over transitively reachable callees.

**Q2. Say where the anti-conflation rationale goes when the diamond collapses.**
Confirm whether the resulting ordering asserts what the paragraph was written to
deny.

## Disposition of round 1

Rev 1 folded all six findings. Q1 was answered as local, with an added reason
this review did not have: termination is a property of the cycle, so no member
carries it alone, while body-faithfulness is a property of one body.

**Q2 was answered, and it corrected a misread in the question.** Measured by the
language-team: `evidenceCovers (DLVerified _) _ = True` and
`evidenceMeet (DLVerified _) b = b` in
[`../../compiler/src/LLMLL/Syntax.hs`](../../compiler/src/LLMLL/Syntax.hs) make
the verified peers a genuine top, so **`verified` has always covered `tested`**
and those two were never incomparable. The paragraph orders `contract-checked`
against `tested`. Its subject does not survive the retirement, so the paragraph
retires with the element rather than relocating. This review accepts that
correction in full.

---

# Round 2, on Rev 1

Round 2 was driven by running the artifact path rather than reading it.

## Measurements

A forged `.verified.json` sidecar claiming `verified` for a function that falls
back, on a `def-shell` whose body is `(* n n)`:

| Channel | Result |
|---|---|
| `verify --proof-artifact` | Caught. `proof-artifact NOT written (internal inconsistency): ill-formed artifact: function 'sq3' carries a positive tier but a non-empty fallback_reason`. No artifact file. |
| `verify --trust-report` | Not caught. Renders `post: verified (forged)`; summary counts `verified: 1`. |
| exit status | 0 in both cases. |
| sidecar after a solver-backed run | Overwritten to `asserted`, after the forged value was consumed. |

## Gaps and hazards

**1. Rev 1's `SIDECAR-ADMIT-1` bound is false.** Classify: soundness, of the
filed finding's scope rather than of TRUST-CC-1. Rev 1 said a forged value
"survives only a solver-less `--trust-report` render or a cache-hit path". A
solver-backed run reads the forged sidecar, feeds it to the trust report and the
artifact builder, and writes the corrected sidecar only afterwards. The overwrite
repairs the file, not the run. Bite: does not block, and the row would have been
prioritized against a bound wrong in the unsafe direction.

**2. Rev 1 omits that one channel already catches this.** Classify: scope. The
split is the useful half of the finding, because it says where a repair belongs.
Bite: complicates.

**3. §4.1 states its strongest evidence as a counterfactual.** Classify:
ergonomic. Rev 1 wrote "Had `verify` done that, every proof artifact minted for
such a function would have been rejected". The rule is live and its input is the
forged sidecar in hazard 1. A reviewer can dismiss a counterfactual guard as
unexercised, which is the dead-guard objection this project applies to its own
gates. Bite: complicates.

**4. The kernel detects laundered evidence and the run exits 0.** Classify:
ergonomic, adjacent to soundness. `mkFnRecord` returns `Left`, `Main` prints the
refusal, and the process exits on the solver verdict, which was SAFE. A gate that
names laundered evidence and does not fail the run is advisory. This is the shape
`SHELL-FALLBACK-SILENT-1` closed on a different channel at v0.22.1. Bite: does
not block; belongs on `SIDECAR-ADMIT-1`.

**5. Retirement narrows the artifact defense by one input.** Classify: scope,
minor. After retirement a sidecar forging `"contract-checked"` reads as
`DLAsserted`, so `mkFnRecord` does not fire. Nothing is lost, because `asserted`
beside a fallback reason is a legitimate combination. Bite: matters at scale only.

## Recommendation

Settle Rev 1 with three edits: rewrite §4.1 around the observed behaviour,
correct §12's bound and add the channel split and the exit-0 item, and add one
sentence to §7 case 5.

On the substance I have nothing further. The retirement is correct, the marker is
the right shape, the locality argument is right, and risk 6 disposes of the
middle option on a count I checked.

## Open question, round 2

**Q3. State whether the trust report should adopt the artifact kernel's
invariant, or whether the two are intended to differ.** `mkFnRecord` refuses to
mint a record for a positive tier with a fallback reason. `formatTrustReport`
renders the same combination without complaint, from the same `TrustReport` value
in the same run. Either the report should apply the check, or the divergence is
deliberate because a report describes what the sidecar claims while an artifact
asserts what was proved.

## Disposition of round 2

Rev 2 folded all five findings.

**Q3 was answered, and the answer rejects both positions this review offered.**
The language-team took a measurement round 2 did not take.
[`../../compiler/app/Main.hs`](../../compiler/app/Main.hs) runs the emitter
inside the `--trust-report` branch **only when the Leanstral pipeline is
requested**. On a plain `llmll verify --trust-report` the emitter never runs, so
the report lacks the invariant's second input and no check is possible there.
Confirmed with `-o` naming a `.fq` path: no `.fq` is written under
`--trust-report`, and one is written under `--strict-verify`. The `NC-022`
fixture
[`../../scripts/doc-claims/display-level-verified.llmll`](../../scripts/doc-claims/display-level-verified.llmll)
already records the same early exit in its own `@claim`.

Rev 2 §12.2 carries this and splits the repair three ways: apply the invariant
where the emitter runs, disclose the limitation on the early-exit path, and treat
the exit-0 behaviour as its own item. That is a better answer than either option
in Q3, and this review adopts it.

---

# The convergence

Three independent surfaces reject a positive tier on a function whose body was
never encoded. The agreement across surfaces is the signal, and the proposal
states all three for that reason.

1. **Inward, from the language-team.** The element has no producer, and elevating
   a fallback function above `asserted` would invert the disclosure
   `SHELL-FALLBACK-SILENT-1` shipped at v0.22.1.
2. **Outward, from this review.** `DLContractChecked` has eliminations and no
   introduction, which fails harmony in the Gentzen tradition, and that is what
   distinguishes an evidence lattice from a policy lattice.
3. **Enforced, from the compiler.** `mkFnRecord`'s `PositiveWithFallback` rule
   already refuses to mint evidence for the combination, and it fires today.

The third surface is the one no reading path predicted. It was found by running
the artifact command against a forged sidecar, after two turns had read the
module without executing it.
