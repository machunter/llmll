---
name: archive-organization-review
title: "Professor review of DRIFT-DOC-3 (archive organization), Rev 1"
status: "Rev 1. Standalone critique of archive-organization-proposal.md Rev 1. Confirms the FLAT outcome; disputes three of its load-bearing claims and rewrites the specification of the P3 gate."
date: 2026-07-26
author: professor
reviews: docs/design/archive-organization-proposal.md
consumers: [user, language-team, compiler-engineer]
---

# Professor review: DRIFT-DOC-3, archive organization (Rev 1)

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

1. [`archive-organization-proposal.md`](../../design/archive-organization-proposal.md) Rev 1, the artifact
   under review. Its two routed questions are answered in the next section.
2. [`../../scripts/version_gate.sh`](../../../scripts/version_gate.sh):1-40. DRIFT-CI-1 asserts
   *equality among four self-maintained records* (README banner, `LLMLL.md` banner, CHANGELOG
   heading, schema const versus `ParserJSON.hs::expectedSchemaVersion`). No external oracle.
3. [`../../scripts/doc_claims_gate.sh`](../../../scripts/doc_claims_gate.sh):1-22. DRIFT-CT-2 runs
   fixtures through the compiler and compares the *observed* verdict to the claimed one. It has
   an oracle. These two gates are epistemically different and the proposal treats them as one
   class (finding G1).
4. [`../../LLMLL.md`](../../../LLMLL.md):708 and
   [`../../experiments/adv-spec-weaken-0/findings.md`](../../../experiments/adv-spec-weaken-0/findings.md):35-40.
   F-002, settled: `:intentional` "is a self-attestation channel with no independent oracle,"
   audited by rate rather than per site. The adjudication is at
   [`../archive/professor-reviews/contract-discriminative-power-review.md`](contract-discriminative-power-review.md):126-132.
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
