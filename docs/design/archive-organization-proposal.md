---
name: archive-organization-proposal
title: "DRIFT-DOC-3: retire version buckets, gate the shipped/dormant invariant"
status: "Rev 2, professor review folded. FLAT settled by the user 2026-07-26; not reopened. P3 respecified: an opt-in frontmatter field replaces the prose regex, and the gate acquires a live witness plus a fixture pair. P1+P2 ready for documentation-lead; P3 + the edge-case-6 fixture ready for compiler-engineer."
date: 2026-07-26
author: language-team
reviewed_by: docs/design/archive-organization-review.md
consumers: [user, professor, compiler-engineer, documentation-lead]
---

# DRIFT-DOC-3, Archive organization: retire version buckets, gate the invariant that is groundable

## Restatement

The routed question is whether `docs/archive/shipped-design-specs/` should be sub-categorized
into `v0.6/`…`v0.14/` buckets, per the Archive-policy line in
[`../UPDATE-PROTOCOL.md`](../UPDATE-PROTOCOL.md) that has stood as "well overdue" since
DOC-CONSOLIDATE settled 2026-05-24.

This proposal treats it as a narrower question than filing convention: **what is a directory path
permitted to assert, and what maintains that assertion.** That places it in the same class as
DRIFT-CI-1 and DRIFT-CT-2 rather than in the class of tidiness chores, and the answer follows from
the project's own drift discipline rather than from taste.

> **Adjudicated 2026-07-26 (user): FLAT.** The version-bucket line is retired;
> `shipped-design-specs/` stays flat by decision. Rev 2 does not reopen it: the professor review
> confirms the outcome from an independent reading path
> ([`archive-organization-review.md`](archive-organization-review.md), Q1 and Q2), and both routed
> questions now answer *in favour of* flat with sharper reasons than Rev 0 had.

### What changed in Rev 2

Folded from [`archive-organization-review.md`](archive-organization-review.md). Seven changes,
plus two findings that emerged while re-measuring for G3 and which change the proposal's own
claims about the tree.

| # | Change | Source |
|---|---|---|
| 1 | DRIFT-DOC-3 reclassified as a **consistency** gate, sibling of DRIFT-CI-1 only, not of DRIFT-CT-2 | G1 |
| 2 | Prose regex plus named allowlist replaced by an **opt-in `archive-disposition` frontmatter field** over a closed vocabulary, with a ratcheting ungated-count assertion | G4, G5 |
| 3 | Gate acquires a **fixture pair** so both branches execute on every run | G2 |
| 4 | Move 1 rewritten on Cool-URIs and update-anomaly; Move 2 rewritten on flat-plus-ordinal, with the settlement ordinal explicitly declined | Q2 |
| 5 | Kind declination restated quantitatively (effective-class count); the **feature-line axis** recorded as considered and declined; the retrieval-versus-inference-guard distinction stated | Q1 |
| 6 | Link churn under the rejected options upgraded from "complicates" to **infeasible** | G6 in the review's ranking |
| 7 | Measurement denominators stated per row | G7 |
| **A** | **The vocabulary is four-valued, not two-valued.** `deferred` is a distinct observed state and the split is shipped-side versus not-shipped-side | new, from the G3 re-measurement |
| **B** | **The tree is not already correct.** `contract-clause-refactor.md` is a live mis-filing, so the gate fires on HEAD | new, from the G3 re-measurement |

Finding B retracts a claim in Rev 1's Hand-off ("The shipped/dropped split itself already landed
at `b7f1266`"). It did not land completely.

## Context located

1. [`archive-organization-review.md`](archive-organization-review.md), the professor critique this
   revision folds. Rev 2 is a revision of Rev 1 against it.
2. [`../UPDATE-PROTOCOL.md`](../UPDATE-PROTOCOL.md), Archive policy bullets and the 2026-07-26
   measurement note: the version-bucket line and the recorded blockage. Lines 89 and 95 record
   two batch sweeps that left CHANGELOG links on stubs "(append-only)", which is the project's own
   statement of the constraint that makes options (b) and (c) infeasible rather than merely
   expensive.
3. [`INDEX.md`](INDEX.md) archive table: the `shipped-design-specs/` cell still opens
   "Shipped/superseded design specs" and carries version prose.
4. [`../../scripts/version_gate.sh`](../../scripts/version_gate.sh):1-40 (**DRIFT-CI-1**): asserts
   equality among four records that are all maintained inside this repository. No external oracle.
   **This is DRIFT-DOC-3's true sibling.**
5. [`../../scripts/doc_claims_gate.sh`](../../scripts/doc_claims_gate.sh):1-22 (**DRIFT-CT-2**):
   executes the compiler and compares an observed verdict to a claimed one. It has an oracle, and
   DRIFT-DOC-3 does not. Rev 1 filed them as one class; they are two.
6. [`../../LLMLL.md`](../../LLMLL.md):708 and
   [`../../experiments/adv-spec-weaken-0/findings.md`](../../experiments/adv-spec-weaken-0/findings.md):35-40:
   **F-002**, settled. A self-attestation channel admits no per-instance oracle by construction.
   A `Status:` line is that channel. This is the project's own precedent for the wording in Move 4.
7. `../../scripts/doc-claims/import-after-def.llmll` and `decl-order-independent.llmll`: the
   existing ordering-claim cluster, both guarding position-independence.
8. External reference class: the Rust RFC process (`rust-lang/rfcs`), the GHC proposals process
   (`ghc-proposals/ghc-proposals`), and, supplied by the review, Berners-Lee's *Cool URIs don't
   change* (W3C Style, 1998) with the update-anomaly framing from Codd (1971).

### Measurements

Taken 2026-07-26. **Denominator per row**, since the directory changed size mid-measurement: the
version row was measured before the `b7f1266` move (59 files), the rest at HEAD (57 files).

| Axis | n | Groundable | Ungroundable |
|---|---|---|---|
| **Shipped version** | 59 | 32 cited in `CHANGELOG.md` | 27 cited nowhere in it; of those, 16 yield only *proximity* matches from INDEX / UPDATE-PROTOCOL / roadmap, and **11 yield no version signal at any source** |
| **Status marker present** | 57 | 55 carry a marker (blockquote `> **Status:**`, 45; YAML `status:`, 10) | 2: `body-vc-0-spec.md`, `verification-debate-action-items.md` |
| **Marker decides shipped-side vs not** | 57 | **21** by keyword | **36** need a human to read the line |
| **Document kind** | 57 | 46 by filename suffix (28 `-proposal`, 5 `-spec`, 4 `-plan`, 2 `-spike`, 2 `-finding`, 2 `-direction`, 1 `-impl`, 1 `-addendum`, 1 `-bug`) | 11 singletons with no suffix |
| **Feature line** | 57 | ref-meta 4, match-widen + match-fragment 5, six pairs | roughly 38 singletons |

A proximity match is not an attribution: `cascading-refine-protocol-spike` yields v0.14.8,
v0.14.12 **and** v0.14.13 with nothing in any source to choose between them.

**Row 3 is new in Rev 2 and it is the row that changes the design.** Rev 1 read row 2 (55 of 57)
as the groundable axis. Presence of a marker is a weaker property than *the marker deciding the
axis*, and the gap is large: 36 of 57 markers are ambiguous to a keyword scan, because the
observed vocabulary is lifecycle vocabulary (`Approved, ready for implementation`, `APPROVED , 
ready for COMP-1`, `Rev 2, Option 2 BUILT and green`, `CLOSED, all five layers fixed`,
`Deferred — captured for future reference`) rather than disposition vocabulary. Lifecycle status
and archive disposition are different attributes, and Rev 1 conflated them. This is the argument
for Move 4's explicit field, and it converges with the review's G4 from a different direction: G4
says a prose regex *over-fires*, row 3 says it *under-decides*.

No in-flight draft existed on archive organization before Rev 0; `INDEX.md` had no matching entry.

## Design proposal

**Recommendation: retire the version-bucket line.** Adopt a disposition-grounded invariant in its
place and mechanize it. Four moves.

### Move 1, Encode only what is immutable

`shipped-design-specs/v0.14/foo.md` asserts "foo shipped in v0.14." The principle that decides
this is not specific to directories: **do not encode in a stable identifier anything that
changes**, because the identifier then has to change when the world does. That is Berners-Lee's
*Cool URIs don't change* (W3C Style, 1998), which names status, ownership, subject and format as
exactly the things not to put in a URI. Archive paths are URIs in practice, cited as `github.com`
blob links from commits and issues, even though `docs/` is not published by Pages today (the
published tree is `site/`, per `.github/workflows/pages.yml`).

The relational-model framing supplies the remedy vocabulary and, more usefully, **unifies P1 and
P3 into one decision applied twice**. A bucket directory is a denormalized second copy of an
attribute already recorded in the document, and divergence between copies is an *update anomaly*
(Codd, *Further Normalization of the Data Base Relational Model*, 1971). So:

- **Version: normalize.** No maintaining mechanism can exist, because 11 of 57 files admit no
  version at any source. The single copy stays in `CHANGELOG.md`, which the P1 canonical-sources
  table already names authoritative for release narrative.
- **Disposition: denormalize deliberately, and supply the maintaining mechanism.** The directory
  is a second copy of a fact stated in the document. DRIFT-DOC-3 *is* what licenses that copy.

Stated this way the gate stops reading as an add-on. It is the thing that makes the second copy
admissible at all, and without it the archive is running an unmaintained denormalization, which is
what it has been doing since 2026-05-24.

### Move 2, The external reference class encodes exactly one fact, and it is immutable

Rust's `text/` and GHC's `proposals/` are not flat-plus-metadata; they are flat-plus-*ordinal*:
`text/NNNN-name.md`, `proposals/NNNN-title.rst`. Both encode exactly one fact in the path, and it
is the one fact that can never change, the merge order. Status lives in the RFC book, the document
header, and issue metadata, never in the path. The rule the precedent supports is therefore not
"encode nothing," it is "encode only what is immutable," which is Move 1 restated by two projects
that had status directories available and declined them.

LLMLL has a live instance of the mutability that defeats status-in-path:
`proof-required-predicate-carrier.md` reads "Superseded by LT-PPR (v0.11)", a fact that arrived
long after the file was written and filed.

**The settlement ordinal is declined, explicitly.** Adopting `NNNN-name.md` would give LLMLL the
same immutable identifier Rust and GHC have. It is declined because its benefit is prospective and
its cost is retrospective: renaming 57 existing files incurs the full link rewrite that Move 3
rejects for the bucket options, and it buys immutability the current filenames already have in
practice, since nothing renames them. The one thing an ordinal buys that names do not is a
settlement ordering, and `CHANGELOG.md` already supplies that. Recorded here so the option is
visibly considered; if the archive were being created today rather than reorganized, the ordinal
would be the right identifier.

### Move 3, Two criteria decide a partition, and version buckets fail both

Rev 1 argued the kept split and the declined split on the same grounds. They are decided by
different criteria and saying so is what makes the policy reusable on the next filing question.

**Criterion R (retrieval).** A partition is worth its cost when it materially narrows a scan the
reader actually performs. Its computable form is the *effective* number of classes, not the
nominal count, because a skewed partition delivers far less than its class count suggests
(Simpson, Nature 1949; Hill, Ecology 1973; Jost, *Entropy and diversity*, Oikos 2006). For the
kind axis over the 46 classified files, counts 28/5/4/2/2/2/1/1/1:

| Quantity | Value |
|---|---|
| Nominal classes | 9 |
| Inverse Simpson, `1 / Σp²` | **2.52** |
| Shannon entropy | **2.04 bits** (perplexity 4.11) |
| Modal class share | 28 of 46, **60.9%** |
| Including the 11 unsuffixed as a tenth class, over 57 | inverse Simpson **3.38** |

Against `log2(57) = 5.83` bits needed to identify one document, kind resolves 2.04 of them, and
the filename already carries those same bits for free in 46 of 57 cases. **Declined.**

The **feature-line axis** fails criterion R harder: roughly 40 classes over 57 files, most of them
singletons. Recorded as considered so it does not return as a fresh idea.

**Criterion I (inference guard).** A partition is worth its cost when misplacement causes a reader
to conclude something false, independent of any retrieval benefit. The shipped-side/dormant split
scores almost nothing on criterion R (55 against 2 is 0.22 bits) and is worth its directory
anyway, because a reader who finds an abandoned exploration under `shipped-design-specs/`
concludes the design is realized in the compiler, and it is not.

**Version buckets fail both.** Readers query `CHANGELOG.md` for version, so R is near zero; and
for the 11 unsourceable files a bucket would *induce* a false inference rather than prevent one,
so I is negative.

### Move 4, Ground the invariant in a declared field, not in prose

Row 3 of the measurements is the reason: 36 of 57 status markers do not decide the axis by
keyword, because they state *lifecycle* (`Approved`, `BUILT`, `CLOSED`, `Deferred`) and the gate
needs *disposition*. A regex cannot recover disposition from lifecycle prose, and the same prose
scan over-fires: "superseded" appears in body text describing a superseded *characterization*
(`ref-meta-4-erasure-proposal.md`:51,155), superseded *triage rows*
(`contract-discriminative-power-proposal.md`:283), a superseded *construct*
(`rec-body-vc-proposal.md`:201), and a superseded *adjudication*
(`core-shell-inversion-proposal.md`:469).

**An opt-in YAML frontmatter field over a closed vocabulary.** This is the bargain `@expect:`
headers make in DRIFT-CT-2: the gate reads a field the author declares, rather than hunting for a
phrase in running text. This proposal's own header is the self-precedent, as are the 10 archived
files that already carry YAML frontmatter.

```yaml
archive-disposition: shipped | superseded | dropped | deferred
```

| Value | Meaning | Side |
|---|---|---|
| `shipped` | the design is realized in the compiler | shipped-side |
| `superseded` | a successor shipped; this document is kept for lineage | shipped-side |
| `dropped` | explored and abandoned; no part shipped | dormant-side |
| `deferred` | not chosen and not abandoned; captured against a future need | dormant-side |

**The vocabulary is four-valued because the observed vocabulary has a third state.** Rev 1 assumed
shipped-versus-dropped is total. `contract-clause-refactor.md` is titled "Deferred Design", reads
`> **Status:** Deferred — captured for future reference`, records that Option A was chosen and
Option B documented "for when the contract representation needs richer structure", and has zero
`CHANGELOG.md` and zero roadmap hits. It is neither shipped nor abandoned. Collapsing it into
`dropped` would assert an abandonment the document denies, which is the same category error the
whole proposal is about, one level down.

The split is therefore **shipped-side versus not-shipped-side**, and
[`../archive/dormant-explorations/README.md`](../archive/dormant-explorations/README.md)'s opening
phrase "explored and dropped" is narrower than both the directory's name and its contents. P2
corrects it.

Two records, not three. The `> **Status:**` blockquote stays prose and the gate does not read it;
it carries revision history and fold state that no closed vocabulary can hold. The gated records
are exactly two, the field and the path, and the gate asserts their agreement. That is DRIFT-CI-1's
shape exactly.

The gate is not ceremonial, because the two records are written at different times by different
actors: the field is set by the document's owner when disposition changes, the path by
documentation-lead at sweep time. DRIFT-CI-1 has value for the same reason (the README banner is
written at release, the schema const at schema change).

### The three moves as tickets

- **P1 (spec-track).** Retire the `v0.6/`…`v0.14/` sentence from Archive policy.
  `shipped-design-specs/` stays flat **by decision, not by neglect**. Version lineage is *queried*
  from `CHANGELOG.md` and the roadmap's `## Shipped Releases`. Record criteria R and I as the test
  future filing proposals are decided against.
- **P2 (spec-track).** Promote shipped-side-versus-not from filing suggestion to stated invariant,
  keyed on `archive-disposition`, with the admission test already drafted in
  [`../archive/dormant-explorations/README.md`](../archive/dormant-explorations/README.md), and
  widen that README's "explored and dropped" framing to cover `deferred`.
- **P3 (code-track).** **DRIFT-DOC-3**, sibling of **DRIFT-CI-1** (see Move 4 and Verification
  mapping): for every file carrying `archive-disposition`, assert that its value's side matches
  its directory. Report the count of files lacking the field, and assert that count is
  non-increasing against a bound recorded in the gate.

## Edge cases and degenerate inputs

### 1. Positive witness, live on HEAD

Required by [`../UPDATE-PROTOCOL.md`](../UPDATE-PROTOCOL.md) D2. **Rev 2 upgrades this from a
historical witness to a current one.**

- **Input shape.** `docs/archive/shipped-design-specs/contract-clause-refactor.md`, today: titled
  "Deferred Design", status `Deferred — captured for future reference`, zero `CHANGELOG.md` hits,
  zero roadmap hits. Option B was documented and not chosen.
- **Expected behavior.** Once the file declares `archive-disposition: deferred`, the value's side
  is dormant, the path is `shipped-design-specs/`, the gate exits 1 naming the file. The fix is to
  move it to `dormant-explorations/`.
- **Channel.** Enforcement gate.
- **Why this matters beyond D2.** Rev 1's Hand-off claimed the split "already landed at
  `b7f1266`." It did not. The gate has a live finding on the tree it will be built against, which
  is the strongest possible answer to the concern that a documentation gate is ceremonial.

The historical witness from Rev 1 stands as a second case:
`expiring-intentional-proposal.md` carried `> **Status:** **Abandoned (Rev 0.3)**` while sitting
in the shipped directory until `b7f1266`, constructible via
`git show b7f1266~1:docs/archive/shipped-design-specs/expiring-intentional-proposal.md`. The
document that motivated D2 is a document that witnesses the gate D2 governs.

### 2. Fixture pair, so the firing branch survives its own fix

- **Input shape.** Edge case 1 is a witness that *disappears when fixed*. After the move, no file
  on the tree drives the failing branch, and the gate's own failure path stops executing.
- **Expected behavior.** The gate ships with a two-file fixture tree, one synthetic shipped-side
  and one synthetic dormant-side, that it is pointed at explicitly and that exercises both
  verdicts on every invocation. DRIFT-CT-2 has this structurally via `scripts/doc-claims/`;
  DRIFT-DOC-3 needs it deliberately, because unlike a compiler-behaviour gate its corpus is
  expected to be conformant.
- **Channel.** Enforcement gate, self-test.

### 3. Document with no `archive-disposition`

- **Input shape.** All 57 files at landing time, since the field is new.
- **Expected behavior.** Not gated. The gate reports the ungated count and asserts it against a
  bound recorded in the gate: fail if above, warn ("lower the bound to N") if below. A new
  archived file must either carry the field or force a visible bound raise in the diff.
- **Channel.** Enforcement gate, ratchet.
- **Why not the Rev 1 allowlist.** A named two-entry allowlist with a shrink-only *convention* has
  no forcing function, since growing it is a one-line edit in the same file. A ratcheting count
  has one. Zero migration cost: nothing has to be annotated for the gate to land, and every
  annotation lowers the bound.

### 4. Status-less document

- **Input shape.** `body-vc-0-spec.md`, `verification-debate-action-items.md`: no status marker in
  any form.
- **Expected behavior.** Indistinguishable from edge case 3 under the new design, and that is the
  point. Rev 1 needed a special allowlist for these two precisely because it read prose; a
  declared field makes "has no marker" and "has not adopted the field" the same state.
- **Channel.** Enforcement gate, ratchet.

### 5. Superseded, where the successor's own fate is unknown

- **Input shape.** `proof-required-predicate-carrier.md`, prose status "Superseded by LT-PPR
  (v0.11)".
- **Expected behavior.** The author writes `archive-disposition: superseded` and the file stays
  shipped-side. **The transitivity problem dissolves rather than being solved:** a document
  superseded by a successor that was itself abandoned gets `dropped` from its author, and the gate
  never has to follow a supersession chain it can only see the first link of.
- **Channel.** Spec is explicit (the vocabulary table), then enforcement gate.
- **Contrast with Rev 1**, which ruled `Superseded by X` shipped-side syntactically. That rule is
  right for this file and wrong in general, and a regex cannot tell which case it is in.

### 6. Separate finding, routed not resolved: the `open`-ordering claim is ungated

Unchanged from Rev 1 and independent of everything above.

[`../getting-started.md`](../getting-started.md) §4.8 and §4.9 assert that an `open` placed after a
`def` using its bare names leaves the call unresolved, that `typecheck` exits **0** with only
`warning: call to unknown function`, and that `verify` and `build` exit **1**. Verified against
v0.14.67 with a two-module repro.

That is the falsifiable restriction shape DRIFT-CT-2 exists to guard, in the same two doc sections
and the same "must appear before defs" cluster as the two existing fixtures.
`import-after-def.llmll` and `decl-order-independent.llmll` guard the *position-independent* half;
the newly documented *order-sensitive* half has no fixture.

- **Channel.** Spec is silent (**gap, flagged**).
- **Routing.** `compiler-engineer`, as a DRIFT-CT-2 fixture addition. The fixture needs a
  two-module program and a non-default `@cmd:`, since the claim is that `check`/`typecheck` passes
  while `verify` fails; a single-file `@expect: check-ok` fixture would assert the wrong half.

### 7. Citation into `dormant-explorations/`

- **Input shape.** `UPDATE-PROTOCOL.md` D2 cites `expiring-intentional-proposal.md` as the
  positive-witness precedent, so the dormant directory carries an active policy clause rather than
  inert history.
- **Expected behavior.** No special handling. Relative-link integrity is a separate concern,
  already swept (`31bd1a6`) to two known and intended dangling links.
- **Channel.** Spec is silent, intentionally.

## Verification mapping

**This proposal introduces zero proof obligations.** It adds no surface form, no refinement
predicate, no typing rule, and no builtin, so the type/contract/trust channels and the QF-LIA /
nonlinear / Lean fragment classification of `LLMLL.md §5.3.3` and `§5.3.5` do not apply. Asserting
a fragment here would be fabrication. The professor review reached the same conclusion
independently and named the convergence.

The analogous classification for a documentation-governance proposal is **enforcement channel**,
and Rev 2 splits that vocabulary in two, which Rev 1 did not:

| Gate | Compares | Has an external oracle? | Detects |
|---|---|---|---|
| **DRIFT-CI-1** (`version_gate.sh`) | four in-repo records | no | disagreement |
| **DRIFT-CT-2** (`doc_claims_gate.sh`) | claim against compiler execution | **yes** | falsity |
| **DRIFT-DOC-3** (proposed) | declared field against directory path | no | disagreement |

**DRIFT-DOC-3 is a consistency gate, not a correctness gate, and Rev 2 states the limit rather
than implying otherwise.** It detects that two self-attested records disagree. It cannot detect
both being wrong: an author who abandons a design and updates neither the field nor the path
leaves the gate green. That limit is not a defect to be engineered away, it is the same limit the
project already adjudicated as structural for self-attestation channels in **F-002**
(`LLMLL.md`:708; `experiments/adv-spec-weaken-0/findings.md`:35-40), where the resolution was to
document the channel's nature rather than add a second signal on the same channel.

Rev 1 claimed this was "the identical move DRIFT-CT-2 made for restriction claims." It is not:
DRIFT-CT-2 moved a claim from unchecked to *oracle-checked*. DRIFT-DOC-3 moves two records from
independently-drifting to *mutually-checked*, which is DRIFT-CI-1's move and is worth making on
its own terms.

| Invariant | Enforcement channel | Precedent |
|---|---|---|
| `archive-disposition` side agrees with directory | Script gate (DRIFT-DOC-3), consistency-class | `scripts/version_gate.sh` |
| Ungated-file count does not grow | Same gate, ratchet | new |
| Version lineage is queried, never encoded in a path | Behavioral, UPDATE-PROTOCOL P1 | P1 already names `CHANGELOG.md` canonical |
| Document-kind organization | None; declined under criterion R | n/a |
| Feature-line organization | None; declined under criterion R | n/a |

## Affected surface

| Surface | Change | Slot |
|---|---|---|
| `docs/UPDATE-PROTOCOL.md` Archive policy | Retire the version sentence; state the shipped-side invariant keyed on `archive-disposition`; record criteria R and I; name DRIFT-DOC-3 | documentation-lead |
| `docs/design/INDEX.md` archive table | The `shipped-design-specs/` cell carries version prose the retired policy contradicts; add this proposal's one-liner row and the review's | documentation-lead |
| `docs/archive/dormant-explorations/README.md` | Widen "explored and dropped" to cover `deferred`; state the four-valued vocabulary and the side mapping | documentation-lead |
| `docs/archive/shipped-design-specs/contract-clause-refactor.md` | Mis-filed (edge case 1). Move to `dormant-explorations/` with `archive-disposition: deferred` | documentation-lead |
| `scripts/` | New gate, sibling naming DRIFT-DOC-3 | compiler-engineer |
| `scripts/doc-archive-fixtures/` (new) | Two-file fixture tree so both gate branches run (edge case 2) | compiler-engineer |
| `.github/workflows/version-gate.yml` | Gate invocation | compiler-engineer |
| `scripts/doc-claims/` | New fixture for the `open`-ordering claim (edge case 6, independent finding) | compiler-engineer |

Not touched: `LLMLL.md`, `CHANGELOG.md`, `README.md`, `compiler/src/LLMLL/`. No freeze flag
applies; this proposal introduces no construct. The `archive-disposition` field is markdown
frontmatter, not LLMLL surface, so `docs/llmll-ast.schema.json` is unaffected and no schema
version moves.

## Risks and open questions

1. **The gate cannot detect a document whose field and path are both wrong.** *Scope, structural.*
   Named in Verification mapping and grounded in **F-002** (`LLMLL.md`:708). **Bite: bounds what
   the gate may be claimed to establish; does not block it.** No mitigation is proposed, because
   the project has already ruled that adding a second signal on the same self-attestation channel
   is not defense in depth.
2. ~~**Gate regex brittleness.**~~ **Resolved in Rev 2 by Move 4.** The gate reads a declared field
   over a closed vocabulary and never scans prose, so neither the over-fire cases
   (`ref-meta-4-erasure-proposal.md`:51 and three others) nor the under-decide cases (36 of 57
   markers) reach it.
3. ~~**Amending a verbatim lift is not language-team's authority.**~~ **Withdrawn (checked
   2026-07-26).** Rev 0 claimed P1 needed DOC-CONSOLIDATE-level authority because
   [`../UPDATE-PROTOCOL.md`](../UPDATE-PROTOCOL.md):3 declares the file "Lifted verbatim from
   §3.1–3.3." That header does not cover the version-bucket sentence. The file was created at
   `1a8733f`; the sentence entered later at `0e4e2d4` ("design-folder Phase 2 cleanup"), and the
   source proposal contains no version-bucket text at all. It is ordinary doc-lead-authored prose.
   **P1 is a normal documentation edit inside documentation-lead's own slot.**
4. ~~**Allowlist ossification.**~~ **Resolved in Rev 2 by edge case 3.** The named allowlist is
   replaced by a ratcheting count, which has the forcing function the shrink-only convention
   lacked.
5. **Adoption of `archive-disposition` may stall at zero.** *Verification-ergonomics.* The field is
   opt-in and nothing forces a backfill of the 57 existing files, so the gate could sit green over
   a corpus it never inspects. **Bite: only matters at scale.** Mitigation: the ratchet makes every
   *new* archived document carry the field or raise a visible bound, so the annotated fraction is
   monotone even with no backfill campaign. Whether to backfill is documentation-lead's call, not
   a gate requirement.
6. **Link churn under the rejected options is not expensive, it is infeasible.** *Scope.* Roughly
   158 link occurrences point into the directory, **38 of them in append-only `CHANGELOG.md`
   sections.** `UPDATE-PROTOCOL.md`:89 and :95 record two prior sweeps that left CHANGELOG links
   on stubs specifically because those sections are append-only. Options (b) and (c) therefore
   require either breaking the append-only invariant or accepting permanently broken links in the
   release record. **Bite: eliminates options (b) and (c); zero under the recommendation.** Rev 1
   rated this "complicates," which understated it.

## Professor questions, answered

Both were routed to the professor in Rev 1 and both are answered in
[`archive-organization-review.md`](archive-organization-review.md). Folded above; recorded here so
the resolution is legible without opening the review.

1. **Kind-partitioning threshold for a heterogeneous corpus.** No size threshold exists in the
   literature; the question was the wrong shape. What exists is a set of conditions (stability,
   query-conditioning, adequate extension) with faceted classification (Ranganathan 1933) as the
   framing result: a single tree carries exactly one facet, so the question is always "which
   facet is worth the one tree," never "sub-categorize or not." The third condition has a
   computable form, the effective class count, which is folded into Move 3 as criterion R. The
   retrieval-versus-inference-guard distinction (criteria R and I) is the review's structural
   contribution and is what makes the policy answer the *next* filing question rather than only
   this one.
2. **"Path as assertion" as a named anti-pattern.** Named three times over: *Cool URIs don't
   change* (Berners-Lee, W3C Style, 1998), the smart-key anti-pattern with its update-anomaly
   failure mode (Codd 1971), and identifier opacity in the persistent-identifier literature (ARK,
   Handle, DOI). Move 1 is rewritten on the first two, and the normalization frame is what unifies
   P1 and P3 into one principle. Move 2 also gains the correction that the Rust and GHC precedents
   are flat-plus-*ordinal* rather than flat-plus-metadata, and the settlement ordinal is now
   declined explicitly rather than left unconsidered.

**Answering the review's two hand-back questions:**

- **Which criterion decides the shipped-side/dormant split?** Criterion I, the inference guard. It
  is stated as such in Move 3 and P1 carries it into the policy text, because it is the criterion
  that decides the next split proposal and it was written down nowhere.
- **Does the field replace the `> **Status:**` blockquote or coexist with it?** Coexist, with a
  clean division of labour that avoids the second update anomaly the question anticipates: the
  blockquote is prose lifecycle narrative and **the gate does not read it**; `archive-disposition`
  is the gated disposition record. Exactly two machine-readable copies exist, the field and the
  path, and the gate asserts their agreement. The blockquote stands to prose the way a CHANGELOG
  entry's body text stands to `version_gate.sh`, which reads only the heading.

## Hand-off

**Spec-track (P1, P2) to `documentation-lead`, UNBLOCKED.** The user adjudicated FLAT on
2026-07-26 and Rev 2 does not reopen it. Affected: `docs/UPDATE-PROTOCOL.md` Archive policy
(retire the version-bucket sentence, state the disposition-keyed invariant, record criteria R and
I, name DRIFT-DOC-3), `docs/design/INDEX.md` (reconcile the `shipped-design-specs/` cell, add
one-liners for this proposal and the review), and
`docs/archive/dormant-explorations/README.md` (four-valued vocabulary and side mapping; widen
"explored and dropped" to cover `deferred`). **One tree change is now part of the spec-track
hand-off and was not in Rev 1:** `contract-clause-refactor.md` moves to `dormant-explorations/`
with `archive-disposition: deferred`, per edge case 1. Rev 1's claim that the split "already
landed at `b7f1266`" is retracted.

**Code-track (P3, and edge case 6 independently) to `compiler-engineer`.** DRIFT-DOC-3 is a
path-and-field gate with no compiler dependency, so unlike DRIFT-CT-2 it cannot SKIP on a missing
binary and should fail closed. It reads YAML frontmatter over a four-value closed vocabulary,
never prose; it ships with a two-file fixture tree so both branches execute on every run; and its
ungated-file count ratchets against a bound recorded in the gate. The edge-case-6 fixture is
unrelated to the archive, can ship on its own, does have a compiler dependency, and needs a
two-module program plus a non-default `@cmd:`.

A standalone review exists at
[`archive-organization-review.md`](archive-organization-review.md), folded into Rev 2 but not
inlined. **M2 fold-and-archive applies on settlement:** documentation-lead folds it as
`## Appendix, Professor review log` and archives the file to `docs/archive/professor-reviews/`.

## Appendix, Professor review log

Standalone review folded on settlement per DOC-CONSOLIDATE M2. Original at `docs/archive/professor-reviews/archive-organization-review.md`. Rev 2 above already acts on every item; this appendix preserves the critique as an independently readable artifact, which is the point of the fold-after-settlement pattern.

## Restatement

The proposal decides a filing question by reclassifying it as an identifier-design question: a
directory path is an assertion, assertions in this project are gated, and the version axis admits
no ground truth to gate against. It therefore retires the version-bucket line, keeps the archive
flat, and proposes DRIFT-DOC-3 to mechanize the shipped-versus-dropped split instead. The FLAT
outcome is already adjudicated by the user; what remains open is the rationale recorded in the
policy text and the specification of the gate.

I confirm the outcome and dispute three of the claims supporting it. The gate's specification
needs replacing, not adjusting.

## Context located

1. [`archive-organization-proposal.md`](archive-organization-proposal.md) Rev 1, the artifact
   under review. Its two routed questions are answered in the next section.
2. [`../../scripts/version_gate.sh`](../../scripts/version_gate.sh):1-40. DRIFT-CI-1 asserts
   *equality among four self-maintained records* (README banner, `LLMLL.md` banner, CHANGELOG
   heading, schema const versus `ParserJSON.hs::expectedSchemaVersion`). No external oracle.
3. [`../../scripts/doc_claims_gate.sh`](../../scripts/doc_claims_gate.sh):1-22. DRIFT-CT-2 runs
   fixtures through the compiler and compares the *observed* verdict to the claimed one. It has
   an oracle. These two gates are epistemically different and the proposal treats them as one
   class (finding G1).
4. [`../../LLMLL.md`](../../LLMLL.md):708 and
   [`../../experiments/adv-spec-weaken-0/findings.md`](../../experiments/adv-spec-weaken-0/findings.md):35-40.
   F-002, settled: `:intentional` "is a self-attestation channel with no independent oracle,"
   audited by rate rather than per site. The adjudication is at
   [`../archive/professor-reviews/contract-discriminative-power-review.md`](../archive/professor-reviews/contract-discriminative-power-review.md):126-132.
   A `Status:` line is the same channel.
5. Measured over `docs/archive/shipped-design-specs/` at HEAD (57 files): kind-suffix
   distribution 28/5/4/2/2/2/1/1/1 with 11 unsuffixed; frontmatter present in 12 of 57, the other
   45 using a `> **Status:**` blockquote; leading status tokens {Settled, Shipped, Resolved,
   Resolution, Proposed, Rev N, Scoped}; feature-line clusters ref-meta 4, match-widen plus
   match-fragment 5, six pairs, roughly 38 singletons.
6. Body-prose occurrences of "superseded" describing something other than the document's own
   status: `ref-meta-4-erasure-proposal.md`:51,155 (a characterization), `contract-discriminative-power-proposal.md`:283
   (triage rows), `rec-body-vc-proposal.md`:201 (a construct), `core-shell-inversion-proposal.md`:469
   (an adjudication). Four false-fire candidates for a prose regex.
7. No prior review file existed on this topic; `INDEX.md` had no matching row. This is the first
   critique turn.

## Answers to the two routed questions

Taken first because they were the assignment, and because the answer to (1) rejects the premise
of the question rather than supplying the requested number.

### Q1. The threshold for kind-partitioning a heterogeneous corpus

**There is no size threshold in the literature, and asking for one is the wrong shape.** What the
literature supplies is a set of conditions, and a computable version of the one that decides this
case.

The framing result is faceted classification (Ranganathan, *Colon Classification*, 1933): a single
hierarchy can carry exactly one facet, so any document with several simultaneously-valid
classifications is misfiled under all but one. The question is therefore never "sub-categorize or
not," it is "which of the available facets is worth the one tree you get." Version, status, and
kind are three facets competing for one directory. The document-management literature reaches the
same place from the systems side and recommends flat-plus-properties with hierarchy as a derived
view (Dourish et al., *Presto*, TOCHI 1999; Dourish et al., TOIS 2000 on user-specific active
properties), and the personal-information-management findings agree that filing pays only when
retrieval is by category rather than by recognition or search (Malone, TOIS 1983, on files versus
piles; Barreau and Nardi, SIGCHI Bulletin 1995; Whittaker and Sidner, CHI 1996).

Three conditions, then, rather than a threshold:

1. **Stability.** The facet must not change over the document's lifetime. This is Parnas's
   decomposition criterion (CACM 1972, 15(12):1053-1058) applied to identifiers: partition by what
   changes independently, and a stable identifier may only encode what does not change.
2. **Query-conditioning.** A directory name is a proximal cue for distal content (Pirolli and
   Card, *Information Foraging*, Psychological Review 1999). It buys nothing if the reader's query
   is not conditioned on the facet. Readers arriving by link or by `grep` extract no scent from
   the tree.
3. **Adequate extension.** The partition must be total, and its classes populated enough to be
   worth a heading.

Condition 3 is the one that decides LLMLL's kind axis, and it can be made computable rather than
left to taste. Report the **effective number of classes**, the standard remedy for the fact that a
raw class count overstates a skewed partition (Simpson, Nature 1949; Hill, Ecology 1973; Jost,
*Entropy and diversity*, Oikos 2006, on reporting effective numbers rather than raw indices).

Over the 46 kind-classified files, with counts 28/5/4/2/2/2/1/1/1:

| Quantity | Value |
|---|---|
| Nominal classes | 9 |
| Inverse Simpson, `1 / Σp²` | **2.52** |
| Shannon entropy | **2.04 bits** (perplexity 4.11) |
| Modal class share | 28 of 46, **60.9%** |
| Including the 11 unsuffixed as a tenth class, over 57 | inverse Simpson **3.38** |

Against `log2(57) = 5.83` bits needed to identify one document, the kind partition resolves 2.04
of them, and the filename already carries those same 2.04 bits, for free, in 46 of 57 cases. The
reader gains a division into between 2.5 and 4 effective groups, one holding 61% of the classified
set, in exchange for roughly 158 link rewrites. The proposal's information-redundancy argument is
correct; this is its quantitative form, and it is the form that generalizes to the next filing
question instead of having to be re-argued.

**The axis the proposal did not consider, and the next reader will:** partition by feature line
rather than by kind, since `match-widen*` plus `match-fragment*` is 5 files on one line and
`ref-meta-*` is 4. Measured, that axis yields roughly 40 classes over 57 files, most of them
singletons. It fails condition 3 harder than kind does. Record it as considered so it does not
return.

**The distinction the proposal blends, and this is the part worth taking into Rev 2.** A partition
can be justified on retrieval grounds, per the above, or as an **inference guard**, which is a
different criterion with a different test. The shipped-versus-dropped split carries almost no
retrieval value: 55 against 2 is 0.22 bits, essentially nothing. It is nonetheless worth its
directory, because a reader who finds an abandoned exploration under `shipped-design-specs/`
concludes the design is in the compiler, and that conclusion is false. The split exists to prevent
a specific wrong inference, not to shorten a scan. Version buckets fail both tests: readers query
`CHANGELOG.md` for version, and for the 11 unsourceable files a bucket would *induce* a false
inference rather than prevent one. A proposal that keeps one split while declining another should
name which criterion each is decided under; Rev 1 argues both on retrieval grounds and thereby
makes the kept split look weaker than it is.

### Q2. "Path as assertion" is named, three times, in three literatures

The crispest statement for this proposal is Berners-Lee, **"Cool URIs don't change"** (W3C Style,
1998), whose argument is precisely the proposal's: do not encode in an identifier anything that
changes, status and ownership and subject and format among them, because the identifier then has
to change when the world does. Archive paths are URIs in practice, as `github.com` blob links
cited from commits and issues, even though `docs/` is not published by Pages today (the published
tree is `site/`, per `.github/workflows/pages.yml`). The principle applies to the paths as cited,
not only as browsed.

The remedy vocabulary comes from the relational side. A bucket directory is a **denormalized
second copy** of an attribute already recorded in the document header, and divergence between the
copies is an **update anomaly** (Codd, *Further Normalization of the Data Base Relational Model*,
1971). The practitioner name for putting mutable meaning into a key is the **smart key** (or
intelligent key) anti-pattern, and its prescription is a surrogate, meaningless identifier plus
attributes. The persistent-identifier literature arrives at the same rule from a third direction
and calls it **identifier opacity**: a semantic identifier acquires a maintenance obligation
proportional to the mutability of what it encodes (Kunze and Rodgers, *The ARK Identifier Scheme*,
2008; the CNRI Handle System and DOI rationales).

**Take the normalization frame into Rev 2, because it unifies P1 and P3 into one principle instead
of two arguments.** Both are the same decision applied to two attributes with different oracles:

- **Version: normalize.** No maintaining mechanism can exist, since 11 of 57 files admit no
  version at any source. The single copy stays in `CHANGELOG.md`, which the P1 canonical-sources
  table already names authoritative.
- **Status: denormalize deliberately, and supply the maintaining mechanism.** DRIFT-DOC-3 *is* the
  maintaining mechanism. Stated this way the gate stops reading as an add-on and becomes the
  thing that licenses the second copy.

**One correction to the precedent reading in Move 2.** Rust's `text/` and GHC's `proposals/` are
not flat-plus-metadata; they are flat-plus-*ordinal*: `text/NNNN-name.md`, `proposals/NNNN-title.rst`.
Both encode exactly one fact in the identifier, and it is the one fact that can never change, the
merge order. The rule the precedent supports is therefore not "encode nothing in the path," it is
"encode only what is immutable," which is the same rule Berners-Lee states and is strictly more
useful than the version Rev 1 extracts. Rev 2 should either adopt a settlement ordinal or decline
one explicitly; leaving it unaddressed wastes the precedent.

## Gaps and hazards

### G1. DRIFT-DOC-3 is a consistency gate, and the proposal files it with the wrong sibling

**Class:** spec-drift, claim discipline. **Bite: does not block; it changes what the gate may be
claimed to establish.**

`scripts/version_gate.sh`:1-40 asserts equality among records that are all maintained by the same
authors in the same commits. It detects *disagreement*; it cannot detect *both copies being
wrong*, since it has no oracle outside the repository. `scripts/doc_claims_gate.sh`:1-22 is a
different animal: it executes the compiler and compares an observed verdict to a claimed one, so a
passing fixture is evidence about the world.

DRIFT-DOC-3 compares a directory path against a prose status line, both authored by the same
person, usually in the same commit. It is in DRIFT-CI-1's class and not DRIFT-CT-2's. The proposal
calls it "sibling of DRIFT-CI-1 and DRIFT-CT-2" (Move 3 P3, and again in the Hand-off) without the
distinction, and its Verification-mapping section claims the invariants move "from behavioral to
mechanical," which is true, and then says this "is the identical move DRIFT-CT-2 made," which is
not: DRIFT-CT-2 moved a claim from unchecked to *oracle-checked*.

This matters here more than it would in most projects, because the project has already ruled on
exactly this epistemics. F-002 settled that a self-attestation channel admits no per-instance
oracle by construction (`LLMLL.md`:708; `experiments/adv-spec-weaken-0/findings.md`:35-40), and
the adjudication that supplied it is a professor review in this same folder's archive
(`contract-discriminative-power-review.md`:126-132). A `> **Status:** Abandoned` line is a
self-attestation. Rev 2 should state that DRIFT-DOC-3 detects disagreement between two
self-attested records, which is worth having and is what DRIFT-CI-1 has always been, and stop
short of the DRIFT-CT-2 comparison.

### G2. The gate passes vacuously on the current tree and has no in-tree firing fixture

**Class:** ergonomic, D2 compliance. **Bite: complicates; fix is cheap.**

Both dropped-side documents were moved out at `b7f1266`, so no file under `shipped-design-specs/`
carries a dropped-side marker today. The measured leading-token vocabulary over the 57 is
{Settled, Shipped, Resolved, Resolution, Proposed, Rev N, Scoped}; none of them is dropped-side.
The gate will be green from the day it lands, on every run, on the firing branch as well as the
quiet one.

Edge case 1 supplies a positive witness and it is a real one, but it is reachable only through
`git show b7f1266~1`, so the firing path is exercised in history rather than in CI. This is the
same shape as the EXPIRING-INTENTIONAL precedent that motivated D2 in the first place, one step
removed: not a guard that cannot fire, but a guard whose firing branch nothing runs. DRIFT-CT-2
avoided it structurally by owning `scripts/doc-claims/`, a directory whose files exist precisely to
drive both verdicts on every invocation.

**Fix:** give DRIFT-DOC-3 a two-file fixture tree (one synthetic shipped-side, one synthetic
dropped-side, in a directory the gate is pointed at explicitly), so both branches run every time.
Without it the gate's own correctness is untested and its first real firing will also be its first
execution of that code path.

### G3. "55 of 57 carry a Status marker" measures marker presence, not decidability of the axis

**Class:** spec-drift, measurement. **Bite: does not overturn the recommendation; it weakens the
specific ratio Move 3 calls "the whole argument."**

Move 3 sets 55-of-57 against 11-ungroundable and reads the ratio as "the difference between a
convention that can be enforced and one that cannot be authored." The two numbers are not
measurements of the same predicate. The version figure measures *whether the fact can be sourced
at all*. The status figure measures *whether a marker is present*, which is a weaker property than
*whether the marker decides shipped-versus-dropped*.

Observed counter-instances: `> **Status:** Settled (Rev 1), awaiting language-team / professor /
compiler-engineer adjudication` leads with Settled and is not shipped; `> **Status:** Proposed
(Rev 3). **Stages 1–2 SHIPPED**` leads with Proposed and is shipped. Seven distinct leading tokens
appear, and the mode, Settled, is silent on the axis. The decidable fraction is materially below
55 of 57 and the proposal does not measure it.

Rev 2 should either re-measure decidability directly or restate the claim as presence and rest
Move 3 on the version argument, which stands on its own.

### G4. A regex over prose will over-fire, and the proposal names the fix without taking it

**Class:** ergonomic. **Bite: complicates.**

"Superseded" occurs in body prose describing something other than the document's own status in at
least four files: a characterization (`ref-meta-4-erasure-proposal.md`:51,155), triage rows
(`contract-discriminative-power-proposal.md`:283), a construct (`rec-body-vc-proposal.md`:201), and
an adjudication (`core-shell-inversion-proposal.md`:469). Two of those are inside the first fifty
lines, so the header-window scan edge case 2 describes does not reliably exclude them.

Risk 1 anticipates the class and mitigates with "a small closed vocabulary that the spec names,"
adding that "documents wanting gating adopt it. This is the same bargain `@expect:` headers make
in DRIFT-CT-2." That is the right instinct and the right precedent. Edge case 2 then specifies a
prose scan plus a named allowlist, which is not that bargain: `@expect:` is a *structured field
the gate reads*, not a phrase the gate hunts for in running text. Rev 1 states the fix in Risks and
specifies something else in Edge cases.

### G5. The named-file allowlist has no forcing function; a count assertion has one

**Class:** ergonomic. **Bite: only matters at scale, and the fix is free.**

Risk 3 states the problem exactly, that a two-entry allowlist with no forcing function becomes
permanent, and mitigates it with a shrink-only rule that is a convention rather than a mechanism.
The gate cannot enforce "never grow" against its own source, since growing it is a one-line edit
in the same file.

Under the structured field of G4 the allowlist disappears rather than needing a rule: a file
without the field is simply not gated, the gate *reports the count* of ungated files, and the
count is asserted non-increasing. That is mechanical, it needs no migration (45 of 57 files have
no frontmatter today, and all 45 stay ungated until someone adds the field), and it gives the
forcing function Risk 3 admits is missing.

### G6. `Superseded by X` is specified syntactically and the property is transitive

**Class:** scope. **Bite: only matters at scale.**

Edge case 3 rules `Superseded by X` shipped-side. That is right for
`proof-required-predicate-carrier.md` because LT-PPR shipped. It is wrong for any document whose
successor was itself dropped, and a regex cannot follow the chain: the property is "the terminus
of the supersession chain shipped," and only the first link is visible in the file.

Under G4's structured field the author declares the side directly and the transitivity question
never arises. If the prose scan survives, Rev 2 should state the assumption explicitly, along the
lines of "a supersession target is assumed shipped-side unless it lives under
`dormant-explorations/`," rather than let a syntactic rule stand in silently for a semantic one.

### G7. The measurement table mixes denominators

**Class:** spec-drift, reporting. **Bite: cosmetic.**

The heading says "over the directory as it stood at 59 files," the version row is over 59, and the
status and kind rows are over 57. Both are defensible readings of a directory measured on either
side of the `b7f1266` move, but the table does not say which row is which. In a proposal whose
argument is a measurement, and in a project whose claim discipline is strict elsewhere, state the
denominator per row.

### Convergence worth naming

The Verification-mapping section declines to assert a QF-LIA / nonlinear / Lean classification on
the ground that the proposal introduces no proof obligation, and says so rather than manufacturing
one. That is correct and it is the behaviour D2 is trying to produce. I reached the same place
independently: there is no obligation here to classify, and a documentation-governance proposal
that claimed a fragment would be fabricating a verification story.

## Recommendation

**Do not reopen FLAT.** Both routed questions confirm it, and Q1's quantitative form makes the
kind declination stronger than the redundancy argument alone: 2.5 effective classes against a
nominal 9, with the modal class holding 61%, and 2.04 of the 5.83 identification bits already free
in the filename.

**Rev 2, seven changes, ranked by value:**

1. **Reclassify DRIFT-DOC-3 as consistency-class** (G1). Sibling of DRIFT-CI-1 only. State that it
   detects disagreement between two self-attested records and cannot detect both being wrong, and
   cite F-002 as the project's own precedent for saying so.
2. **Replace the prose regex and the named allowlist with an opt-in frontmatter field over a
   closed vocabulary, plus a non-increasing ungated-count assertion** (G4, G5). This collapses
   Risk 1 and Risk 3, dissolves edge case 3 (G6), needs no migration, and it is the bargain Risk 1
   already names. The proposal's own header is the self-precedent: it carries YAML frontmatter,
   as do 12 of the 57 archived files.
3. **Add an in-tree fixture pair so both gate branches execute on every run** (G2). Without it the
   firing path lives only in git history.
4. **Rewrite Move 1 on the Cool-URIs and update-anomaly frame, and Move 2 on flat-plus-ordinal**
   (Q2). One principle, "encode only what is immutable," replaces two arguments, and P1 and P3
   become normalize-versus-denormalize-with-a-maintaining-mechanism rather than separate moves.
   Decide the settlement-ordinal question explicitly, either way.
5. **Fold the Q1 criterion into the policy text** (Q1). Three conditions, effective-class count as
   the computable form of the third, the retrieval-versus-inference-guard distinction, and the
   feature-line axis recorded as considered and declined at roughly 40 classes over 57 files.
6. **Upgrade the append-only point.** Risk 4 rates the link churn "complicates" for options (b)
   and (c). With 38 of the 158 occurrences in append-only `CHANGELOG.md` sections, those options
   are not expensive, they are infeasible without either breaking the append-only invariant or
   accepting permanently broken links. That is the strongest practical argument in the document
   and it is currently understated.
7. **Fix the denominators** (G7).

**P1 and P2 need not wait on any of this.** They write down the flat decision, the decision is
settled and correct, and nothing above touches them. Only P3's specification changes, and it
changes enough that the compiler-engineer should be handed Rev 2 rather than Rev 1. The
edge-case-5 fixture is unrelated to all of it and can ship immediately.

## Open questions for the language-team

1. **Which criterion is the shipped-versus-dormant split decided under?** Rev 1 argues it on the
   same retrieval grounds it uses to decline kind, and on those grounds it is the weaker of the
   two: 0.22 bits against 2.04. If it is an inference guard, as I believe it is, say so in the
   policy text, because that criterion is what decides the next filing proposal and it is not
   currently written down anywhere.
2. **Does the frontmatter field replace the `> **Status:**` blockquote or coexist with it?** 12 of
   57 files carry frontmatter and 45 carry the blockquote. Coexistence gives each document two
   status records that can disagree, which is the update anomaly of Q2 reproduced one level down.
   Pick one: either the field is the gated record and the blockquote is prose, in which case say
   the gate ignores the blockquote, or the blockquote is canonical and the field is redundant, in
   which case G4's fix does not apply and the regex problem returns.
