---
name: trust-cc-1-proposal
title: "TRUST-CC-1: retire the contract-checked tier, and report the state it was named after as a marker"
status: "Rev 2, second professor review folded, awaiting user adjudication. `contract-checked` is one of the two middle elements of the evidence lattice and NOTHING IN THE COMPILER ASSIGNS IT. The question routed here was whether `verify` should start assigning it or whether it should leave the lattice; the answer is a third thing. **The lead argument is `ProofArtifact.mkFnRecord`, the project's own LCF kernel, which ALREADY REJECTS a positive tier carrying a fallback reason and names `contract-checked` as positive.** The spec's stated acquisition path and the kernel were in direct contradiction, and the kernel is the side that is enforced. The tier's definition also fails on its own terms: the sentence admits two readings, one false for any contract that constrains the result and one vacuous, and neither yields an implementable check (Rev 1 made this reading-independent after the review showed Rev 0's single reading was contestable). The state the name was reaching for is real and worth reporting, but it is a MARKER beside `asserted`, not a tier above it, and the project has already invented that shape three times (`termination_unverified`, `overflow_tainted`, `refuted`). The marker is LOCAL, not transitive: `NC-024` already floors a caller through the meet, and `NC-034`'s cycle-wide marking does not transfer because termination is a property of the cycle while body-faithfulness is a property of one body. The retirement is behaviourally inert on every real run because the element has no producer. The proposal rejects a third option the first review raised (keep the constant, strip the eliminations) on an audit count of five eliminations plus the false-affordance cost to an agent reading the spec. It files `SIDECAR-ADMIT-1` separately rather than absorbing it. Supplies the design for DISCLOSE-ROW-1's def-shell half rather than duplicating it. Roadmap row: TRUST-CC-1 (to be filed). **Rev 2 corrects two Rev 1 claims by running the artifact path rather than reading it.** The kernel rule is LIVE, not the counterfactual Rev 1 described: it fires today, and its input is a forged sidecar claiming a positive tier for a function this run classified as body-fallback. Rev 1 also bounded SIDECAR-ADMIT-1 wrongly; a SOLVER-BACKED run consumes the forged value and overwrites the file only afterwards. Section 12 now carries the channel split (the artifact kernel catches it, the trust report does not, and both exit 0) and answers why: on a plain --trust-report the emitter never runs, so that path CANNOT apply the invariant, and its repair is disclosure rather than a check."
date: 2026-09-08
author: language-team
consumers: [compiler-engineer, professor, documentation-lead, user]
---

# TRUST-CC-1: retire the `contract-checked` tier

**One line.** A trust tier that nothing produces is not a conservative default.
It is a claim surface with no evidence source, and the state it was named after
belongs beside `asserted`, not above it.

## 1. Summary

`LLMLL.md` §4.4 describes four display levels. Three of them have producers:
`verify` assigns `verified`, the Leanstral bridge assigns `verified-lean`, and
PBT write-back assigns `tested`. `asserted` is the default. The fifth name,
`contract-checked`, sits in the middle of the lattice and **no component of the
compiler assigns it**.

This was found while correcting the §4.4 table at v0.22.1, and the correction
recorded the measurements without settling the design. This proposal settles it.

The recommendation is not "assign it" and not simply "delete it". It is:

- **Retire `DLContractChecked` from `DisplayLevel`.** The diamond lattice
  collapses to a chain.
- **Report the state the name was reaching for as an orthogonal marker**,
  `body_fallback`, on the model `termination_unverified` already establishes.

## 2. What the tier claims, and why no reading of it is implementable

The spec defines the level as:

> The solver proved contract consistency (pre ⇒ post is valid — holds for all
> models of the contract pair), but the function body was not encoded as a VC.

The sentence admits at least two readings, and **both are fatal**. Rev 0 argued
only the first, which let a reviewer answer by preferring the second. Rev 1
argues both, so the conclusion does not depend on the choice.

**Reading one: `result` is free.** Then `pre ⇒ post` is valid only when the
postcondition is implied by the precondition **alone**. For any contract that
constrains the result it is false. Consider `(pre (> k 0))` with
`(post (> result 5))`: take `result = 0` and the implication fails. A faithful
implementation would mark exactly the contracts that say nothing about the
result and refuse every contract that does its job.

**Reading two: "models of the contract pair" means models in which the pair
holds.** Then `pre ⇒ post` holds in every such model by construction. The check
is vacuous and marks every contract equally.

Neither reading yields an implementable check. **The tier cannot be given a
producer that matches its own definition**, whichever reading is taken.

A different check is plausible and does exist in this repository: contract
**non-vacuity**, the feasibility (no-miracle) gate that rejects a spawned
sub-contract no body can discharge (`LLMLL.Feasibility`, cascading refinement).
That is a **gate**, not a tier, and it already has a home.

## 3. What the name was actually reaching for

There is a real state, and it is distinguishable: *`verify` ran, the emitter
refused this body, and the post is assumed rather than proved.*

Today that state is reported as `asserted`, the same level a function gets when
`verify` was never run on it. The tier channel conflates "assumed, the body left
the fragment" with "assumed, never examined".

The project's own flagship program shows the vocabulary gap. Three comments in
[`../../tools/llmll-driver/sequencer.llmll`](../../tools/llmll-driver/sequencer.llmll),
[`oracle.llmll`](../../tools/llmll-driver/oracle.llmll) and
[`spine.llmll`](../../tools/llmll-driver/spine.llmll) each use "contract-checked"
to mean *fell back to contract-only verification*. The spec taught a name for the
state, the compiler never assigned it, and the driver adopted the name anyway.

## 4. Why the state is a marker and not a tier

### 4.1 The kernel already forbids the acquisition path the spec stated

`mkFnRecord` in
[`../../compiler/src/LLMLL/ProofArtifact.hs`](../../compiler/src/LLMLL/ProofArtifact.hs)
is labelled "THE KERNEL" and is the sole gate to a `FnRecord`. Its first rule
rejects a positive tier that carries a fallback reason, as
`PositiveWithFallback`, and its haddock names the tier in the positive set:
"A positive tier (verified / **contract-checked** / tested) is rejected when ...
it carries a fallback reason (it did not, in fact, stay body-faithful)."
`isPositiveTier` includes `TContractChecked`.

`LLMLL.md` §4.4 gave the acquisition path as "`llmll verify` reports SAFE for a
fallback function". The spec and the kernel were in direct contradiction, and
the kernel is the side that is enforced.

**The rule is live, not hypothetical, and Rev 2 states it that way after Rev 1
argued it as a counterfactual.** It fires today. Its input is a `.verified.json`
sidecar that claims a positive tier for a function this run classified as
body-fallback. Measured on a `def-shell` whose body is `(* n n)`:

```
   Running liquid-fixpoint ...
   proof-artifact NOT written (internal inconsistency): ill-formed artifact:
     function 'sq3' carries a positive tier but a non-empty fallback_reason
```

So the project already refuses to mint evidence for the combination the spec
described as this tier's acquisition path. That settles the "give it a producer"
option on evidence that is executed rather than argued. Section 4.2 reaches the
same conclusion from the trust surface, and it reasons about a hypothetical.

The input that fires this rule is the subject of section 12, and the two
findings are the same mechanism seen from two sides.

### 4.2 A tier above `asserted` grants trust

**Anything above `asserted` grants trust.** `isSolverBacked` returns `True` for
`DLContractChecked`, and `emitTrustGap` in
[`../../compiler/src/LLMLL/TypeCheck.hs`](../../compiler/src/LLMLL/TypeCheck.hs)
skips the cross-module trust-gap warning for a solver-backed callee. A tier above
`asserted` therefore silences a warning on a function whose implementation was
never examined.

`SHELL-FALLBACK-SILENT-1` measured what that would cost. A `def-shell` whose
match arm discards its payload falls back, admits a **false** postcondition, and
reports SAFE; the fixture pair
[`../../compiler/test/fixtures/shell-fallback-silent/wild.llmll`](../../compiler/test/fixtures/shell-fallback-silent/wild.llmll)
and [`bound.llmll`](../../compiler/test/fixtures/shell-fallback-silent/bound.llmll)
differ by one character and produce opposite verdicts. Elevating that function
above `asserted` would invert the disclosure v0.22.1 shipped.

**The project has the right shape already, three times.** `LLMLL.md` §4.4.4
describes `termination_unverified` as "an orthogonal informational marker, not a
`DisplayLevel` element", derived at report-build time, never persisted to the
sidecar, feeding neither `evidenceMeet`, the effective level, `refutedClosure`,
nor strict-core admission. `refuted` and `overflow_tainted` have the same shape.
A verdict that needs a qualifier gets a marker in this project, and this is that
case.

### 4.3 Why an evidence lattice differs from a policy lattice

A reviewer can answer sections 4.1 and 4.2 with: an element no analysis produces
is a harmless reservation for a future evidence source. That answer holds for a
**policy** lattice and not for an **evidence** lattice, and the distinction
decides this proposal.

In an information-flow system after Denning (1976) and Volpano, Smith and Irvine
(1996), a label with no producer is legitimate. Labels are *declared* by the
programmer, and the lattice is fixed by the policy independently of what any
analysis derives. Display levels are not declarations. They are propositions
about what was checked, and a proposition needs an introduction rule.

`DLContractChecked` has **elimination rules and no introduction rule**.
`isSolverBacked` extracts trust from it, `evidenceMeet` and `evidenceCovers`
compute with it, `emitTrustGap` suppresses a warning on it, and `isPositiveTier`
counts it as positive. Nothing introduces it. Under the harmony criterion that
Gentzen's inversion principle motivates, and that Prawitz and Dummett make
precise, eliminations must be justified by the corresponding introductions.
Eliminations with no introduction extract more than anything can put in. That is
the principled statement of the defect, and it is what separates this case from
a policy-lattice reservation.

This argument arrived from the professor review. Section 1's reasoning and this
one reach the same conclusion from different directions, which is the reason the
proposal states both.

## 5. The proposal

### 5.1 Retire the element

Remove `DLContractChecked` from `DisplayLevel`. The lattice becomes a chain:

```
      DLVerified  ≡  DLVerifiedLean     (peers, top)
                 |
        DLTested / DLTestedJoint
                 |
            DLAsserted                  (bottom)
```

The "diamond lattice" naming in the `Syntax.hs` haddock and the incomparability
paragraph in `LLMLL.md` §4.4 both exist to support the retired element and go
with it.

**The incomparability paragraph retires with the element rather than
relocating**, and the reason needs stating because the paragraph looks like it is
protecting something more general. Measured this turn:
`evidenceCovers (DLVerified _) _ = True` ("top covers everything") and
`evidenceMeet (DLVerified _) b = b`. The verified peers are a genuine top, so
**`verified` has always covered `tested`**, and those two were never
incomparable. The paragraph orders `contract-checked` against `tested`, and its
stated purpose is to stop "a `tested`-only function from being silently treated
as equivalent to a **solver-checked** function". Once no
solver-checked-but-not-body-checked element exists, `tested` has nothing left to
be conflated with. The paragraph's subject does not survive the retirement, so
neither does the paragraph.

### 5.2 Report the state as `body_fallback`

Add an orthogonal marker to the trust report, per function, carrying the fallback
cause and the closed construct labels. Both already exist: `FALLBACK-REASON-CONST-1`
computes the cause and `SHELL-FALLBACK-SILENT-1` computes the labels, including
the body side. No new analysis is required.

A reader then sees, on one line:

```
  classify:
    pre:  —  |  post: asserted   [body_fallback: match-wildcard-payload]
```

and can separate the two meanings of `asserted` that the tier channel merges.

### 5.3 The marker's contract, stated so it cannot drift upward

The marker is **not** a `DisplayLevel`. It follows `termination_unverified`
exactly:

- derived at report-build time, from the emit result of the same run;
- never persisted to the `.verified.json` sidecar;
- invisible to `evidenceMeet`, `evidenceCovers`, `isSolverBacked`, the effective
  level, `refutedClosure`, and `--strict-verified-core` admission;
- informational only, so it can never raise or lower a tier;
- **local, not transitive.** A caller of a fallback function does not carry it.

The locality clause needs its reason, because the nearest precedent is
transitive and a reader will expect the same shape. `NC-034` marks **every
member** of an undischarged cycle, and `partialFns = cyclicSccMembers`. That
precedent does not transfer, for two reasons.

First, the caller is already covered by a different channel: `NC-024` makes a
function's effective display level the meet over **all transitively reachable
callees**, so a caller of a fallback function is floored at `asserted` through
the tier. The marker owes that caller nothing.

Second, the two properties differ in kind. Termination is a property of the
**cycle**, so no member can carry it alone. Body-faithfulness is a property of
**one function's own body**. A caller whose own body was encoded faithfully has
not lost that, and marking it would misdescribe the caller.

## 6. Why the retirement is inert

Retiring a lattice element normally changes every meet that could take it as an
operand. Here it changes none, because **no run has ever computed a meet with it
as an operand**: nothing assigns it. The meets among `verified`,
`verified-lean`, `tested`, `tested-joint` and `asserted` are untouched.

The one non-inert path is a `.verified.json` sidecar carrying the string, covered
in section 7 case 5.

## 7. Edge cases and degenerate inputs

**1. Positive witness: the marker fires.**
[`../../compiler/test/fixtures/shell-fallback-silent/wild.llmll`](../../compiler/test/fixtures/shell-fallback-silent/wild.llmll),
a `def-shell` carrying `(post (> result 5))` whose arm writes `(HoldsI _)`.
Measured at v0.22.1: `body-fallback: classify`, verdict SAFE, trust report
`post: asserted`. Under this proposal the line gains
`[body_fallback: match-wildcard-payload]`. Channel: trust.

**2. A function with no post.** The cause is `no-post` and the emitter never
reaches the body path. **The marker is suppressed**: no proof goal was lost.
Channel: trust. This matches `W-BODY-FALLBACK`, so the diagnostic channel and the
trust channel agree on the same function.

**3. A scaffold.** The cause is `unfilled-hole`; nothing is written to prove. The
marker is suppressed, on the same reasoning as case 2. Channel: trust.

**4. A body-faithful function.** `post: verified (liquid-fixpoint)`, no marker.
Channel: trust.

**5. A sidecar carrying `"contract-checked"` after the retirement.** `dlFromJSON`
must neither fail closed nor silently drop the record. **Rule: read it as
`DLAsserted` and emit one warning naming the retired level.** Measured: 0 of 5
tracked sidecars carry it, so the rule protects out-of-tree artifacts only. This
class of problem is exactly why the replacement is derived and never persisted.
Channel: trust. A sidecar claiming any **other** level shares the mechanism but
not the scope; see section 12.

The retirement also narrows the artifact kernel's input set by one, and nothing
is lost by it. After the retirement a sidecar forging `"contract-checked"` reads
as `DLAsserted` under the rule above, so `mkFnRecord` sees a non-positive tier
and its `PositiveWithFallback` rule does not fire. There is nothing for it to
catch: `asserted` beside a fallback reason is the legitimate combination. A
sidecar forging `verified` still fires the rule, which is the case section 12
measures.

**6. A solver-less `--trust-report` render.** The marker is derived from the emit
result, which runs before the solver, so it is available. A render that did not
run the emitter shows **no marker**, and the tier still reads `asserted`. The
absence of the marker never reads as a claim of proof. Channel: trust; fail-safe
by construction.

**7. A `Result` match with wildcard payloads.** Core syntax in both `def` forms,
falls back anyway, cause `body-outside-fragment`, label
`match-wildcard-payload`. The marker fires and reports the same label the census
records. Channel: trust.

## 8. Verification mapping

**This proposal introduces no proof obligation.** Nothing is added to the QF-LIA
constraint set, nothing becomes nonlinear or quantified, and nothing escapes to
Lean as `?proof-required`. `LLMLL.md` §5.3.3 and §5.3.5 are untouched, and the
`.fq` for any program is byte-identical.

Three claims need discharging. All are checkable rather than provable, and all
are the engineer's acceptance criteria. The third was already enforced before
this proposal was written:

1. **The retirement changes no meet.** Discharged by the measurement in section
   6: the element has no producer, so no meet has ever taken it. The test is the
   existing trust-report suite plus a `.fq` byte-identity check.
2. **The marker grants no trust.** Discharged by construction: it is not a
   `DisplayLevel`, so `isSolverBacked` cannot see it, `emitTrustGap` cannot be
   suppressed by it, and strict-core admission cannot consult it. This is the
   same argument `termination_unverified` already carries in §4.4.4.
3. **A fallback function may not carry a positive tier.** Already discharged, and
   not by this proposal: `mkFnRecord` rejects that combination as
   `PositiveWithFallback` (section 4.1). The engineer's test is that the rule
   still fires over the remaining positive tiers after the retirement.

## 9. Affected surface

1. [`../../compiler/src/LLMLL/Syntax.hs`](../../compiler/src/LLMLL/Syntax.hs):
   the constructor, the diamond haddock, and the `evidenceMeet`,
   `evidenceCovers`, `isSolverBacked`, `dlProverName` and `dlLabel` clauses.
2. [`../../compiler/src/LLMLL/ProofCache.hs`](../../compiler/src/LLMLL/ProofCache.hs):
   delete `proofToLevel` and its export. It is a fossil of the pre-Leanstral
   design: its own haddock says the cache yields `contract-checked` and `Main`
   upgrades it, and `bridgeProofCache` superseded that by assigning
   `DLVerifiedLean` directly. It has **no callers**.
3. [`../../compiler/src/LLMLL/VerifiedCache.hs`](../../compiler/src/LLMLL/VerifiedCache.hs):
   the `dlToJSON` clause; `dlFromJSON` gains the section 7 case 5 rule.
4. [`../../compiler/src/LLMLL/Parser.hs`](../../compiler/src/LLMLL/Parser.hs) and
   [`ParserJSON.hs`](../../compiler/src/LLMLL/ParserJSON.hs): the
   `:trust … contract-checked` surface. 0 tracked uses.
5. [`../../compiler/src/LLMLL/TrustReport.hs`](../../compiler/src/LLMLL/TrustReport.hs),
   [`SpecCoverage.hs`](../../compiler/src/LLMLL/SpecCoverage.hs) and
   [`../../compiler/app/Main.hs`](../../compiler/app/Main.hs): the summary
   buckets and `verifMap`; the marker is rendered here.
6. [`../../compiler/src/LLMLL/ProofArtifact.hs`](../../compiler/src/LLMLL/ProofArtifact.hs):
   `TContractChecked`. See risk 1: this is a persisted, replayable format and
   is the one place "inert" does not hold.
7. [`../../LLMLL.md`](../../LLMLL.md) §4.4 table row and incomparability
   paragraph, plus §1.4a's four-name sentence, which is registered as **NC-022**
   with disposition `fixture`. Its fixture
   [`../../scripts/doc-claims/display-level-verified.llmll`](../../scripts/doc-claims/display-level-verified.llmll)
   pins `post: verified (liquid-fixpoint)` only and stands unchanged.
   Documentation-lead's slot.
8. [`../../experiments/minimal-agent/scripts/evaluate_run.py`](../../experiments/minimal-agent/scripts/evaluate_run.py)
   and
   [`../../experiments/repair-loop/scripts/run_repair_loop.py`](../../experiments/repair-loop/scripts/run_repair_loop.py):
   both expect the string. `evaluate_run.py` scrapes
   `contract-checked:\s+(\d+)` from the summary, a field that has always been
   zero. Experiment-lead's slot.
9. The three driver comments named in section 3. Prose drift; follow-on.

No JSON-AST schema change. The feature freeze does not apply; it was lifted at
v0.11.

**Convergence, named rather than left implicit.** The marker specified in section
5.2 **is** the `def-shell` disclosure line that roadmap row `DISCLOSE-ROW-1`
asks for. This proposal supplies that row's design rather than duplicating it.
Close the row with this change, or narrow it explicitly to its `capability`
half.

## 10. Risks and open questions

1. **`ProofArtifact`'s READ path is a persisted format.** Classify: scope.
   **Re-priced in Rev 1, downward.** Rev 0 treated the whole module as the risk.
   Section 4.1 shows the kernel rule is an argument *for* the proposal, and that
   rule keeps working over the remaining positive tiers after the retirement. The
   exposure is confined to `tierFromText "contract-checked"` on artifacts already
   written to disk, which `replay-artifact` reads fail-closed. That is a
   read-path migration and not a kernel change. Complicates the plan; the
   engineer prices the migration. This is still the one surface where section 6's
   inertness argument does not hold.
2. **NC-022's registered sentence names four levels.** Classify: spec-drift.
   Changing it is a registry edit plus a doc edit; the fixture is unaffected,
   measured. Complicates only.
3. **Two harness scripts expect the string.** Classify: scope. The fix improves
   `evaluate_run.py`, which has been reading a permanently-zero field, but the
   edit belongs to experiment-lead. Matters at scale only.
4. **The driver's three comments use the retired name.** Classify: spec-drift.
   They describe the state correctly and name it wrongly; the retirement makes
   that visible rather than creating it. Matters at scale only.
5. **The counter-position is that the tier should get a producer instead.**
   Classify: verification-ergonomics. Section 2 rejects it on the definition,
   section 4.1 on the kernel rule that already forbids it, and section 4.2 on the
   SHELL-FALLBACK-SILENT-1 evidence. Recorded here so a reviewer has the position
   to argue with rather than having to reconstruct it.
6. **The middle option: keep the constant, strip the eliminations.** Classify:
   scope. **Added in Rev 1 from the professor review, and rejected.** The option
   is to make `isSolverBacked` return `False` for the tier and leave the
   constructor, the sidecar vocabulary and `tierFromText` untouched. It costs
   nothing in risks 1, 2 or 3, so it deserves a stated rejection rather than
   silence.
   **The count.** Stripping is not one edit. The eliminations number at least
   five: `isSolverBacked`, `isPositiveTier`, `evidenceMeet`, `evidenceCovers`,
   and the trust-report and spec-coverage summary buckets. `isPositiveTier` is
   the one that decides it, because `mkFnRecord` consumes it. Leaving the tier
   positive there while stripping `isSolverBacked` keeps the kernel treating it
   as evidence. Stripping therefore needs the same audit as retirement.
   **The cost.** It leaves a constant with no introduction and no meaningful
   elimination, still in the tier vocabulary and still documented in
   `LLMLL.md` §4.4. LLMLL's stated primary consumer is an agent reading the spec
   as prompt context. A documented tier that cannot be obtained is a false
   affordance, and an agent that plans toward it plans toward nothing.
   Retirement is the same audit with the residue removed.

## 11. Open questions

**For the professor: none.** Every candidate dissolved under a grep, a read of
`compiler/src/LLMLL/`, or a probe against the built compiler, and each was run.

The question a reviewer should press hardest is whether "no producer" is
sufficient grounds to retire a lattice element, or whether an unassigned tier is
a harmless reservation for future evidence sources. Section 2 is the answer:
the tier cannot be given a producer that matches its own definition, so the
reservation is for a thing that cannot be built as specified.

## 12. `SIDECAR-ADMIT-1`, filed separately and not absorbed

Rev 0 raised the `.verified.json` sidecar as a trust entry point specific to this
tier, then withdrew the framing on finding that `verified` is equally writable.
The observation was right and the withdrawal was too quick: the correct
conclusion is not that the channel is fine, but that it is **a separate and
larger finding**. Rev 1 files it and does not fold it into this proposal.

`downgradeStaleVerifiedSidecar` in
[`../../compiler/src/LLMLL/TrustReport.hs`](../../compiler/src/LLMLL/TrustReport.hs)
states its own scope: "Records that are **not** `erBodyFaithful` are passed
through untouched (they make no body-faithful admission claim)." A record that
claims `display_level: verified` while leaving the body-faithful flag unset is
therefore never hash-checked. Reproduced: a hand-written sidecar renders
`post: verified (hand-written)` for a function whose body is `(* n n)` and falls
back.

**Rev 1 stated a bound here and the bound was wrong.** It said a forged value
"survives only a solver-less `--trust-report` render or a cache-hit path". A
**solver-backed** run reads the forged sidecar, feeds it to the trust report and
to the artifact builder, and writes the corrected sidecar only afterwards.
Measured: the run below ran the solver, consumed the forged value, and left
`asserted` in the file when it finished. The overwrite repairs the file, not the
run.

### 12.1 Two channels, and only one of them catches it

| Channel | Forged sidecar claiming `verified` on a fallback function |
|---|---|
| `verify --proof-artifact` | **Caught.** The kernel refuses to mint: "carries a positive tier but a non-empty fallback_reason". No artifact file is written. |
| `verify --trust-report` | **Not caught.** Renders `post: verified (forged)` and counts `verified: 1` in the summary. |
| exit status | **0 in both cases.** |

The split is the useful half of the finding, because it says where a repair
belongs.

### 12.2 Why the two channels differ, which is not what it looks like

The obvious reading is that the trust report simply omits a check the artifact
kernel performs, and that the repair is to add it. **That reading is wrong on
one of the two report paths, and the reason is an early exit.**

`Main.hs` runs the emitter inside the `--trust-report` branch only when the
Leanstral pipeline is requested. On a plain `llmll verify --trust-report` the
emitter never runs. Measured with `-o` naming a `.fq` path: no `.fq` file is
produced under `--trust-report`, and one is produced under `--strict-verify`.
The project already records this behaviour in the `NC-022` fixture
[`../../scripts/doc-claims/display-level-verified.llmll`](../../scripts/doc-claims/display-level-verified.llmll),
whose `@claim` says `--strict-verify` is required because "`verify --trust-report`
prints an all-asserted report and exits before the solver runs".

So on the plain path the report **cannot** apply the kernel's invariant. The
invariant needs two inputs, the claimed tier and this run's fallback set, and
the second one was never computed.

### 12.3 The scope this gives `SIDECAR-ADMIT-1`

Three parts, and they are not one repair:

1. **Where the emitter runs in the same invocation** (`--strict-verify`,
   `--proof-artifact`, the post-solver path), the report has both inputs and
   should apply the kernel's invariant. A claimed tier contradicted by this run's
   emit result is downgraded rather than rendered. The mechanism is not new:
   `downgradeStaleVerifiedSidecar` is already a downgrade-on-read guard, and this
   is a widening of its trigger from hash drift to contradiction.
2. **On the plain `--trust-report` early exit**, no check is possible. The
   honest repair is disclosure: the render should say it is sidecar-only and was
   not validated against a run of the emitter.
3. **The detection has no consequence.** The kernel names laundered evidence and
   the process exits 0, because the exit status follows the solver verdict. A
   gate that identifies laundered evidence and does not fail the run is advisory.
   This is the shape `SHELL-FALLBACK-SILENT-1` closed on a different channel at
   v0.22.1.

Whether any of this sits inside the project's stated "sound modulo trust"
position ([`verification-debate.md`](verification-debate.md)) is a real question
and it is not this proposal's to answer.

Filed as **`SIDECAR-ADMIT-1`**, a gap in `ADMIT-VERIFIED`'s coverage rather than
a new subject. It does not block TRUST-CC-1, and TRUST-CC-1 does not repair it.

## 13. Revision history

**Rev 1 (2026-09-08), professor review folded.** Six changes, none of which moved
the recommendation.

1. Section 4.1 added, promoting `mkFnRecord` to the lead argument. Risk 1
   re-priced downward as a consequence.
2. Section 2 rewritten to argue both readings of the spec sentence, after the
   review showed Rev 0's single reading was contestable.
3. Risk 6 added: the middle option, stated and rejected on an audit count.
4. Section 12 added: `SIDECAR-ADMIT-1` filed rather than dropped.
5. Section 5.3 gained the locality clause and its two reasons.
6. Section 5.1 answers where the incomparability paragraph goes, and corrects a
   premise: `verified` has always covered `tested`, so those two were never the
   incomparable pair.

Section 4.3 is new and comes from the review's outward reading path. Rev 0
reached the conclusion inward, from the absent producer and the
SHELL-FALLBACK-SILENT-1 disclosure. The review reached it through harmony in the
Gentzen tradition. The convergence is the reason both are stated.

**Rev 2 (2026-09-08), second professor review folded.** Three corrections, all
from running the artifact path rather than reading it. The recommendation did
not move.

1. Section 4.1 rewritten. Rev 1 argued the kernel rule as a counterfactual
   ("Had `verify` done that"). The rule is live and fires today; Rev 2 carries
   the rejection message it prints and names the input that produces it. A
   counterfactual guard invites the dead-guard objection this project applies to
   its own gates.
2. Section 12 corrected and expanded. Rev 1's bound was wrong: a solver-backed
   run consumes the forged value and overwrites the file afterwards. Section 12.1
   adds the channel split, 12.2 explains it, and 12.3 gives
   `SIDECAR-ADMIT-1` a three-part scope including the exit-0 item.
3. Section 7 case 5 gained the note that the retirement narrows the kernel's
   input set by one, and that nothing is lost by it.

**Section 12.2 answers the review's open question, and it rejects both offered
positions.** The review asked whether the trust report should adopt the kernel's
invariant or whether the divergence is deliberate. Neither. On the plain
`--trust-report` path the emitter never runs, so the report lacks the invariant's
second input and no check is possible there. Measured with `-o`: no `.fq` is
written under `--trust-report`, and one is written under `--strict-verify`. The
`NC-022` fixture already records the same early exit in its own `@claim`.
