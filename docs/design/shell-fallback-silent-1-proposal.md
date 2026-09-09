---
name: shell-fallback-silent-1-proposal
title: "SHELL-FALLBACK-SILENT-1: two warnings for a lost body-faithful claim, and three corrections to the row"
status: "Rev 0, DRAFT, awaiting user adjudication. The row asks for a reporting severity. The answer is a warning, at two emission points, and NEITHER of them is where the decision packet put it. The row's own wording is wrong in three ways and every correction was measured against llmll 0.22.0, not argued: (a) trigger 1 is NOT def-shell specific, because a plain def with an inadmissible payload passes check, falls back, and reports a false post as SAFE; (b) the admissible payload set is exactly int, bool and string, so a NON-recursive user sum falls back too and recursion is not the line; (c) trigger 2 reaches a Result match with wildcard payloads, which is core syntax in both forms and still falls back, so the packet's narrower reading misses it. The severity is a warning at both points, because an error would refuse programs LLMLL.md section 4.1 admits. The population numbers decide the gates: 9 body-outside-fragment entries tree-wide carry a post, and 83 functions carry a repairable wildcard arm of which ZERO carry a post, so the check-time rule is gated on a post and fires zero times today by design. Two drift findings came out of the reading and are in section 10. One deferred theory question is registered as Q-007. Roadmap row: SHELL-FALLBACK-SILENT-1."
date: 2026-09-08
author: language-team
consumers: [compiler-engineer, professor, documentation-lead, user]
---

# SHELL-FALLBACK-SILENT-1: two warnings for a lost body-faithful claim

**One line.** A function can lose body-faithful verification, admit a false
postcondition, and report `SAFE`. This proposal makes the compiler say so, at
the two points where it knows.

## 1. Summary

The roadmap row `SHELL-FALLBACK-SILENT-1` carries the **DECIDE** marker and
asks the language team for one thing: the reporting severity. The decision
packet is
[`fallback-census-1-implementation-plan.md`](fallback-census-1-implementation-plan.md)
section 10. It recommends one warning, `W-SHELL-FALLBACK`, at `check`.

This proposal accepts the severity and rejects the shape. The defect is two
defects. They have different triggers, different populations, and different
information available at different phases. One warning cannot carry both.

- **Rule 1**, `W-BODY-FALLBACK`, is raised by the emitter. It names the
  construct that refused the body. It fires on at most **9** functions across
  the tracked tree today.
- **Rule 2**, `W-MATCH-WILDCARD-PAYLOAD`, is raised at `check`. It is purely
  syntactic. Gated on a post, it fires on **zero** functions today, and it
  fires on the first function that gains one.

Neither rule is an error. An error would refuse programs that
[`../../LLMLL.md`](../../LLMLL.md) section 4.1 admits.

The soundness position does not move. Contract-only verification of a fallback
function is sound. What is missing is the disclosure that a claim was lost.

Every claim below was measured against `llmll 0.22.0`, the shipped head. The
method is in section 11 so a later reader can reproduce it.

## 2. What is silent today, measured

The row says a `def-shell` "silently downgrades". That is too strong for the
shipped compiler and too narrow for the defect. `FALLBACK-REASON-CONST-1`
(v0.19.0) and `FALLBACK-CENSUS-1` (v0.22.0) both shipped after the row was
filed on 2026-09-05, and both added disclosure.

Measured, per channel:

| Channel | Body-faithful | Fallback | What it says |
|---|---|---|---|
| `check` | `OK` | `OK` | nothing |
| `verify`, human | `body-faithful: f` | `body-fallback: f` | the function, not the cause |
| `verify --json` | `body_faithful` | `body_fallback`, `body_fallback_causes`, `fn_kinds` | the cause bucket |
| `verify --strict-verified-core` | passes | `ERROR` with function and cause | fails closed |
| `--trust-report` | `post: verified (liquid-fixpoint)` | `post: asserted` | the tier, not the reason |
| top-line verdict | `SAFE` | `SAFE` | the same word |

Three gaps survive.

**Gap A. The construct list is empty for every body-side cause.**
`erFallbackConstructs` in
[`../../compiler/src/LLMLL/FixpointEmit.hs`](../../compiler/src/LLMLL/FixpointEmit.hs)
is populated only for a contract-side refusal, and its own haddock says so. The
recording site passes a literal empty list when it records `FallbackBody`. The
machine channel therefore names the function and the bucket, and never the arm.

**Gap B. `check` is silent for a `def-shell` and loud for a `def`.**
`checkStatement` for `SDef` gates on `isCoreBodySyntactic` and reports
`def 'wild': body contains non-core syntax`, with a suggestion to use
`def-shell`. `checkStatement` for `SDefShell` runs no such gate, by design. The
author who chose the permissive form learns nothing.

**Gap C. The verdict word does not move.** A false post reaches `SAFE`. This is
the positive witness in section 7, case 1.

## 3. Rule 1: `W-BODY-FALLBACK`, at the emitter

### 3.1 The rule

When the emitter records the cause `FallbackBody` for a function, it must also
record the sub-terms that `bodyToPredM` refused, and raise one warning for that
function. The warning names three things: the function, the cause, and the
minimal refusing construct. When the refusal is a match arm, it names the
constructor and the payload type.

### 3.2 The carrier already exists

Use `mkWarning` from
[`../../compiler/src/LLMLL/Diagnostic.hs`](../../compiler/src/LLMLL/Diagnostic.hs),
with `diagCode` set to `W-BODY-FALLBACK` and `diagKind` set to
`body-fallback-cause`. `mkReuseWarning` is the closest existing shape.

The warning goes into `erDiagnostics`. The human path in
[`../../compiler/app/Main.hs`](../../compiler/app/Main.hs) already prints
emitter diagnostics with a warning mark. `EMIT-DIAG-JSON` already folds them
into `verify --json`. No new channel is built.

### 3.3 The construct list

Populate `erFallbackConstructs` for body-side causes with a body-side analogue
of `refusedConstructs`. The vocabulary must be closed, on the same reasoning
that `refusedConstructs` and `FallbackCause` are closed: a histogram over runs
needs buckets that do not drift. `FALLBACK-CENSUS-1` reads this field, so an
open vocabulary would break the instrument that measures the population.

### 3.4 The post gate is automatic

`FallbackNoPost` is decided before the body path is reached. A function with no
post never reaches `FallbackBody`. Rule 1 therefore fires only where a proof
goal was actually lost, without any gate being written.

Population today: at most **9** functions across the whole tracked tree. That
is the `body-outside-fragment` count in the first recorded census run,
[`fallback-census-1-implementation-plan.md`](fallback-census-1-implementation-plan.md)
section 12.2.

### 3.5 The name

The packet calls this `W-SHELL-FALLBACK`. This proposal renames it to
`W-BODY-FALLBACK`, because the defect is not `def-shell` specific. Section 6
carries the measurement that forces the rename.

## 4. Rule 2: `W-MATCH-WILDCARD-PAYLOAD`, at `check`

### 4.1 The rule

A function that carries a post, and whose body contains a match arm of the form
`(Ctor _)`, gets one warning. The condition is that binding each such payload
by a name leaves the arm set inside `isCoreBodySyntactic`. The warning names
the function, the constructor, and the repair.

The test is purely syntactic. It needs no type information and no alias map. It
reuses the four arm predicates that already sit inside `isCoreBodySyntactic` in
[`../../compiler/src/LLMLL/Syntax.hs`](../../compiler/src/LLMLL/Syntax.hs):
`isResultArm`, `isNullaryEnumArm`, `isPayloadCtorArm` and
`isMixedNullaryPayloadArms`.

### 4.2 Why the condition is written this way

The obvious condition is "the arm set is non-core, and repair makes it core".
That reading is wrong and it was measured. `isResultArm` matches a `Success` or
`Error` arm whatever its sub-patterns are. So a `Result` two-arm match with
wildcard payloads is **already** core syntax, in a `def` as well as a
`def-shell`. It still falls back at the emitter, and binding the payloads still
repairs it. The narrower reading misses that case completely.

The condition is therefore: an arm of the form `(Ctor _)` is present, **and**
the repaired arm set is core.

### 4.3 Severity and exit status

Warning. `check` keeps exit 0 and already renders a warning count beside its OK
line.

### 4.4 The post gate is a decision, and here is its number

Across **2371** top-level `def` and `def-shell` definitions in the tracked
tree, **83** functions contain a repairable wildcard arm, over **265** arms in
**10** files. **Every one of them has no post.**

- Ungated, Rule 2 fires 83 times and costs nothing to any of those functions.
- Gated on a post, Rule 2 fires **zero** times today, and it fires on the first
  function that gains a post.

The driver's Phase 5 tier claim is exactly that event. The roadmap row
`DRIVER-LL` records that the driver is built of `def-shell` and that both G1
rows must close before the tier claim.

Gate it on the post.

### 4.5 Holes

Suppress Rule 2 while the body contains a hole. This matches the treatment
`FallbackHole` already receives: a scaffold has nothing written to prove. The
rule fires once the hole is filled. The alternative, warning on a scaffold,
tells an agent something true about a body it has not written yet.

## 5. What this proposal does not build

- **No error.** An error would refuse programs section 4.1 admits.
- **No new tier**, no change to `evidenceMeet`, no change to strict-core
  admission.
- **No `.fq` change.** The acceptance check is in section 12.
- **No JSON-AST schema change** and no schema version change.
- **No trust-report line.** That line belongs to the roadmap row
  `DISCLOSE-ROW-1`, and Rule 1's construct list is its input. Building it here
  would duplicate a mechanism that row owns.
- **No growth of `FallbackCause`.** The set stays at eight values.

## 6. Three corrections the row needs

The row's Status cell states two triggers. All three statements below were
produced by running the compiler, not by reading it.

### 6.1 Trigger 1 is not `def-shell` specific

A plain `def` with an inadmissible payload passes `check`, falls back at the
emitter, and reports a false post as `SAFE`:

```
(type Tree (| Node Tree) (| Leaf))
(type Box2 (| Holds Tree) (| Nothing2))
(def defrec [b: Box2] -> int
  (post (> result 5))
  (match b ((Holds t) 1) ((Nothing2) 0)))
```

`check` reports OK. `verify` reports `body-fallback: defrec` and the verdict
`SAFE`. `verify --json` reports `fn_kinds` of `def`.

The arm set is core syntax, so the `def` gate never fires. The payload type is
what the fragment refuses, and the type is not known at `check`. The row's
title and its scope both need widening, and this is why Rule 1 lives at the
emitter.

### 6.2 The trigger is a payload outside `{int, bool, string}`

`admissiblePayload` admits `int`, `bool` and `string`, and nothing else. The
packet corrected the row's "non-integer" reading to "recursive". Recursion is
not the line either. A **non-recursive** user sum payload also falls back:

```
(type Inner (| A) (| B))
(type Outer (| Wrap Inner) (| None4))
(def-shell sumpay [b: Outer] -> int
  (post (> result 5))
  (match b ((Wrap i) 1) ((None4) 0)))
```

Verdict `SAFE` on a false post. The same shape over a `bool` payload is
body-faithful and the false post is refuted on both branches. So the boundary
is the three base sorts, not recursion and not integrality.

### 6.3 Trigger 2 reaches a `Result` match

```
(def-shell reswild [r: Result[int,string]] -> int
  (post (> result 5))
  (match r ((Success _) 1) ((Error _) 0)))
```

`check` reports OK, in both `def` and `def-shell` form. `verify` reports
`body-fallback: reswild` and the verdict `SAFE`. Binding both payloads by name
makes the function body-faithful and the false post is refuted.

Section 4.2 carries the consequence for Rule 2's condition.

## 7. Edge cases and degenerate inputs

**1. Positive witness. One character buys the refutation.**

```
(type BoxI (| HoldsI int) (| NoneI))
(def-shell falsewild [b: BoxI] -> int
  (post (> result 5))
  (match b ((HoldsI _) 1) ((NoneI) 0)))
```

Measured: `body-fallback: falsewild`, verdict `SAFE`, exit 0. Replace `_` with
`n` and the same false post is refuted on both branches, exit 1. Rule 1 fires,
because the cause is `body-outside-fragment`. Rule 2 fires, because a post is
present and the repair is core. Channel: contract.

**2. A `def`, not a `def-shell`, with an inadmissible payload.** Section 6.1.
Rule 1 fires. Rule 2 does not, because no arm writes `_`. This is the case the
row's `def-shell` scoping loses. Channel: contract.

**3. A `def-shell` with `_` and no post.** 83 functions today. Neither rule
fires. The cause is `no-post`, not `body-outside-fragment`, and there is no
proof goal to lose. Channel: the spec is silent, and intentionally so.

**4. A `Result` match with `_` payloads and a post.** Section 6.3. `check`
accepts the arm set in both forms. The emitter falls back. Rule 1 fires. Rule 2
fires under the condition in section 4.2, and does not under the narrower
reading. Channel: contract.

**5. A multi-payload constructor arm, `(Ctor a b)`.** Measured: 4 matches
tree-wide. Rule 1 fires when a post is present. Rule 2 does not, because
binding does not repair it: `isPayloadCtorArm` admits one sub-pattern by
construction. Channel: the spec is silent (intentional).

**6. An unfilled hole in the body.** The cause is `unfilled-hole`, so Rule 1
does not fire. Rule 2 is suppressed by section 4.5. Channel: the spec is silent
(intentional).

**7. A path-cap fallback.** The cause is `path-cap-exceeded` and the emitter
already warns on it. Neither new rule fires. Channel: contract.

## 8. Verification mapping

**This proposal introduces no proof obligation.**

Both rules are diagnostics over information the compiler already computes.
Nothing is added to the QF-LIA constraint set. Nothing becomes nonlinear or
quantified. Nothing escapes to Lean as `?proof-required`. `LLMLL.md` sections
5.3.3 and 5.3.5 are unchanged by this proposal.

One classification is worth stating as a negative. Rule 1 reads the result of
`bodyToPredM`'s refusal and must not alter it, so the emitted constraint set
stays byte-identical. Section 12 gives the check.

The soundness position is unchanged and was never in question. Contract-only
verification of a fallback function is sound (`LLMLL.md` sections 4.1 and 4.4).
The two rules disclose a lost claim. They do not make a new one.

## 9. Affected surface

1. [`../../compiler/src/LLMLL/FixpointEmit.hs`](../../compiler/src/LLMLL/FixpointEmit.hs):
   a body-side analogue of `refusedConstructs` over `bodyToPredM`; the
   `FallbackBody` recording site gains a real construct list; one `mkWarning`
   into `erDiagnostics`. `FallbackCause` does not grow.
2. [`../../compiler/src/LLMLL/TypeCheck.hs`](../../compiler/src/LLMLL/TypeCheck.hs):
   one clause in `checkStatement` for `SDefShell`, gated on a post.
3. [`../../compiler/src/LLMLL/Syntax.hs`](../../compiler/src/LLMLL/Syntax.hs):
   the repairable-arm predicate, beside the four arm predicates it already
   holds.
4. [`../../compiler/src/LLMLL/Diagnostic.hs`](../../compiler/src/LLMLL/Diagnostic.hs):
   two warning constructors, on the `mkReuseWarning` pattern.
5. [`../../compiler/app/Main.hs`](../../compiler/app/Main.hs): no change
   required. Both warnings ride channels that exist.
6. [`../compiler-team-roadmap.md`](../compiler-team-roadmap.md): the row's own
   wording, per section 6. Documentation-lead's slot.
7. [`../../LLMLL.md`](../../LLMLL.md) section 4.1: one sentence recording that
   a lost body-faithful claim is reported. Documentation-lead's slot.
8. No schema file changes. No `.fq` changes.

**Feature freeze does not apply.** The v0.8.1a to v0.10 freeze was lifted at
v0.11, recorded under "What's NOT on this Roadmap" in
[`../compiler-team-roadmap.md`](../compiler-team-roadmap.md).

**CI trap, checked rather than predicted.**
[`../../scripts/doc-claims/nonlinear-body-fallback.llmll`](../../scripts/doc-claims/nonlinear-body-fallback.llmll)
pins `output:body-fallback: g`. The port matches an `output:` expectation with
`string-contains`, so appending a cause to that line keeps the fixture passing.
No `@expect` in the doc-claims corpus pins a `check` warning count, and no file
in that corpus contains a wildcard payload arm.

## 10. Risks and drift findings

1. **Spec drift, `LLMLL.md` section 4.4.** The trust-tier table gives
   `contract-checked` as what a fallback function earns when `verify` reports
   `SAFE`. Measured: it earns `asserted`, including when the pre implies the
   post, and the sidecar records `asserted`. `DLContractChecked` is assigned
   only by `proofToLevel` in
   [`../../compiler/src/LLMLL/ProofCache.hs`](../../compiler/src/LLMLL/ProofCache.hs)
   from the proof cache, and by an explicit `:trust` annotation. The same
   table row's third example, a self-recursive `def-shell`, is also incorrect:
   a self-recursive shell is body-faithful today and carries
   `termination_unverified`. Classify: spec-drift. Effect: complicates this
   proposal, because a reader of `--trust-report` cannot separate "asserted,
   never attempted" from "asserted, the body left the fragment". Route to
   documentation-lead, or to `DISCLOSE-ROW-1` if the disclosure line is the
   repair.
2. **Rule 2's post gate leaves 83 functions unwarned.** Classify:
   verification-ergonomics. Those functions are the driver and the TOOL-LL
   ports. Phase 5's tier claim will add posts to some of them, and the warning
   arrives then. Effect: matters at scale only, and the alternative was
   measured at 83 firings for zero present cost.
3. **The census population and this proposal's population differ.** Classify:
   scope. The census reads `examples/`, `tools/` and `scripts/build-smoke/`.
   Section 11's counts come from every tracked `*.llmll`. The counts are a
   lower bound and are not the census denominator. Effect: no conclusion
   changes direction.
4. **A body-side construct vocabulary can drift.** Classify: spec-drift.
   `refusedConstructs` gets its stability from a closed label set. A body-side
   walker needs the same discipline, or `FALLBACK-CENSUS-1`'s histogram loses
   its buckets. Effect: one design constraint on the engineer, stated here.
5. **Rule 2 ships with no in-tree firing case.** Classify:
   verification-ergonomics. A warning that fires zero times is a dead guard
   until it fires. Effect: blocks acceptance of Rule 2 unless the section 7
   case 1 witness ships as a fixture. Precedent: `EXPIRING-INTENTIONAL` and
   [`../UPDATE-PROTOCOL.md`](../UPDATE-PROTOCOL.md) D2.

## 11. Measurement method

Reproduce with `llmll 0.22.0` or later. Put the built compiler on `PATH` first;
a stale binary reads as "the patch did not work".

**The witnesses.** Sections 6 and 7 give complete programs. Each was written to
a scratch directory and run under `llmll check`, `llmll verify`,
`llmll verify --trust-report` and `llmll --json verify`. Note that `--json` is
a global flag and precedes the subcommand.

**The population counts.** `git ls-files '*.llmll'` gives 330 files. 326 emit a
JSON-AST under `llmll build --emit`; 4 fail, which matches the census's
`check-failed` count. Basenames collide in the output directory, so 309
directories hold the result and the counts are a lower bound.

The arm predicates are then applied to the emitted AST. One trap: `patternToJson`
renders `PVar` as `"bind"`, not `"var"`. Reading `"var"` alone reports every
correctly bound payload as a refusal, and inverts the result.

**Cross-check.** A regular expression over the sources counts 265 occurrences of
a wildcard payload arm. The AST walk counts 265. The two methods agree.

## 12. Acceptance

1. The section 7 case 1 witness ships as a fixture, in both its firing and its
   repaired form, and the two verdicts differ.
2. `examples/leanstral-demo/square.llmll` still emits **335 bytes** of `.fq`,
   the v0.19.0 figure that `FALLBACK-CENSUS-1` pins. This is the byte-identity
   check for section 8.
3. `scripts/doc-claims/nonlinear-body-fallback.llmll` still passes, per section
   9.
4. The census ratio does not move. Neither rule changes a verdict, a cause, or
   a denominator.
5. `body_fallback_constructs` is non-empty for a body-side cause, and its
   labels come from a closed set.

## 13. Open questions

**For the professor: none.** Every candidate question was answerable by running
the compiler, and it was run.

One question survives as deferred theory and is registered as **`Q-007`** in
[`theory-questions.md`](theory-questions.md): whether reporting what a verifier
*would* have proved under a minimal edit has a name and a settled cost
statement. It does not block. Both rules ship either way.
