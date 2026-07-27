---
name: archive-organization-proposal
title: "DRIFT-DOC-3: retire version buckets, gate the shipped/dropped invariant"
status: "Rev 1, SETTLED on the flat-vs-bucketed question (user, 2026-07-26): archive stays FLAT, version buckets retired. P1+P2 ready for documentation-lead; P3 + the edge-case-5 fixture ready for compiler-engineer. Not yet professor-reviewed."
date: 2026-07-26
author: language-team
consumers: [user, professor, compiler-engineer, documentation-lead]
---

# DRIFT-DOC-3 — Archive organization: retire version buckets, gate the invariant that is groundable

## Restatement

The routed question is whether `docs/archive/shipped-design-specs/` should be sub-categorized
into `v0.6/`…`v0.14/` buckets, per the Archive-policy line in
[`../UPDATE-PROTOCOL.md`](../UPDATE-PROTOCOL.md) that has stood as "well overdue" since
DOC-CONSOLIDATE settled 2026-05-24.

This proposal treats it as a narrower question than filing convention: **what is a directory
path permitted to assert, and what checks that assertion.** That places it in the same class as
DRIFT-CI-1 and DRIFT-CT-2 rather than in the class of tidiness chores, and the answer follows
from the project's own drift discipline rather than from taste.

> **Adjudicated 2026-07-26 (user): FLAT.** The version-bucket line is retired;
> `shipped-design-specs/` stays flat by decision. This settles the only question Rev 0 put to
> the user and unblocks P1 and P2 for `documentation-lead`. The remaining open items are the two
> professor questions below, which bear on the *rationale* recorded in the policy text, not on
> the outcome: the directory is flat either way. P3 and the edge-case-5 fixture were never gated
> on this decision.

## Context located

1. [`../UPDATE-PROTOCOL.md`](../UPDATE-PROTOCOL.md), Archive policy bullets and the 2026-07-26
   measurement note: the version-bucket line and the recorded blockage.
2. [`INDEX.md`](INDEX.md) archive table: the `shipped-design-specs/` cell still opens
   "Shipped/superseded design specs" and carries version prose.
3. [`../../scripts/version_gate.sh`](../../scripts/version_gate.sh) (**DRIFT-CI-1**): banner and
   schema equality; the project's first named drift class.
4. [`../../scripts/doc_claims_gate.sh`](../../scripts/doc_claims_gate.sh) and
   [`../../scripts/doc-claims/README.md`](../../scripts/doc-claims/README.md)
   (**DRIFT-CT-2**): **the governing precedent.** A gate that runs fixtures through the compiler
   and asserts the observed verdict matches the claimed one, built after
   [`critique-2026-07-19-triage.md`](critique-2026-07-19-triage.md) found three stale
   restriction claims.
5. `../../scripts/doc-claims/import-after-def.llmll` and `decl-order-independent.llmll`: the
   existing ordering-claim cluster, both guarding position-independence.
6. External reference class: the Rust RFC process (`rust-lang/rfcs`) and the GHC proposals
   process (`ghc-proposals/ghc-proposals`).

### Measurements (taken 2026-07-26, over the directory as it stood at 59 files)

| Axis | Groundable | Ungroundable |
|---|---|---|
| **Shipped version** | 32 of 59 cited in `CHANGELOG.md` | 27 cited nowhere in it; of those, 16 yield only *proximity* matches from INDEX / UPDATE-PROTOCOL / roadmap, and **11 yield no version signal at any source** |
| **Status (shipped vs dropped)** | 55 of 57 carry a `Status` marker | 2: `body-vc-0-spec.md`, `verification-debate-action-items.md` |
| **Document kind** | 46 of 57 by filename suffix (28 `-proposal`, 5 `-spec`, 4 `-plan`, 2 `-spike`, 2 `-finding`, 2 `-direction`, 1 `-impl`, 1 `-addendum`, 1 `-bug`) | 11 singletons with no suffix |

A proximity match is not an attribution: `cascading-refine-protocol-spike` yields v0.14.8,
v0.14.12 **and** v0.14.13 with nothing in any source to choose between them.

No in-flight draft existed on archive organization; `INDEX.md` had no matching entry. This is a
from-scratch proposal.

## Design proposal

**Recommendation: retire the version-bucket line.** Adopt a status-grounded invariant in its
place and mechanize it. Three moves.

### Move 1 — A directory path is an assertion, and this project does not ship unchecked assertions

`shipped-design-specs/v0.14/foo.md` asserts "foo shipped in v0.14." The project has already
named two drift classes and built a gate for each: **DRIFT-CI-1** for banner and schema
equality, **DRIFT-CT-2** for compiler-behaviour claims. A version bucket would be a third
assertion with no ground truth to check against and, worse, none to *author* from: 11 of 57
files admit no version at all.

An assertion that can be neither verified nor sourced is strictly worse than the flat directory
it replaces, because a reader cannot distinguish a bucket assigned from `CHANGELOG` evidence
from one assigned by guess. The flat directory makes no claim it cannot support.

### Move 2 — The external reference class already made this decision

Rust keeps `text/` flat, files numbered by merge order, with status carried in the RFC book and
issue metadata. GHC keeps `proposals/` flat, with status in the document header and a table in
the repository README. Both processes had status-directories available and both declined, for
the reason that applies here: **a document's status changes after filing, and its path should
not have to.**

LLMLL has a live instance. `proof-required-predicate-carrier.md` reads "Superseded by LT-PPR
(v0.11)", a fact that arrived long after the file was written and filed.

### Move 3 — The groundable axis is shipped-versus-dropped, and it is half-built

55 of 57 files carry a `Status` marker against 11 ungroundable on version. That ratio is the
whole argument: it is the difference between a convention that can be enforced and one that
cannot be authored.

- **P1 (spec-track).** Retire the `v0.6/`…`v0.14/` sentence from Archive policy.
  `shipped-design-specs/` stays flat **by decision, not by neglect**. Version lineage is
  *queried* from `CHANGELOG.md` and the roadmap's `## Shipped Releases`, which the P1
  canonical-sources table already names authoritative for release narrative. Costs zero link
  churn, against roughly 158 rewrites for any move.
- **P2 (spec-track).** Promote shipped-versus-dropped from filing suggestion to stated
  invariant, keyed on the document's own `Status` line, with the admission test already drafted
  in [`../archive/dormant-explorations/README.md`](../archive/dormant-explorations/README.md).
- **P3 (code-track).** **DRIFT-DOC-3**, sibling of DRIFT-CI-1 and DRIFT-CT-2: assert that no
  file under `shipped-design-specs/` carries an abandoned, terminal, or withdrawn status
  marker, and no file under `dormant-explorations/` carries a shipped-version citation.

### Declined: the document-kind axis

Derivable for 46 of 57 by filename suffix, and declined anyway: it re-sorts on a fact already
legible in the filename, buys a reader no information they lack, and costs the full link
rewrite. Recorded here so the option is visibly considered rather than overlooked.

## Edge cases and degenerate inputs

### 1. Positive witness for DRIFT-DOC-3

Required by [`../UPDATE-PROTOCOL.md`](../UPDATE-PROTOCOL.md) D2, and **not hypothetical**.

- **Input shape.** Until commit `b7f1266` (2026-07-26),
  `docs/archive/shipped-design-specs/expiring-intentional-proposal.md` carried the literal line
  `> **Status:** **Abandoned (Rev 0.3)**` while sitting in the shipped directory.
- **Expected behavior.** The status scan matches `Abandoned`, the path is under
  `shipped-design-specs/`, the gate exits 1 naming the file.
- **Channel.** Enforcement gate.
- **Constructible today**, which is what D2 requires of a firing case:
  `git show b7f1266~1:docs/archive/shipped-design-specs/expiring-intentional-proposal.md`.

The document that motivated D2 is the document that witnesses the gate D2 governs. That is
worth stating rather than leaving for a reader to notice.

### 2. Status-less document

- **Input shape.** `body-vc-0-spec.md`, `verification-debate-action-items.md`: no `Status`
  marker in the first 3000 characters.
- **Expected behavior.** Warning, not error, against a named allowlist containing exactly these
  two, declared in the gate itself. The allowlist **may shrink and must never grow.**
- **Channel.** Enforcement gate, fail-open by allowlist. Failing closed would block CI on
  history predating the convention.

### 3. Superseded, but the successor shipped

- **Input shape.** `proof-required-predicate-carrier.md`, status "Superseded by LT-PPR (v0.11)".
- **Expected behavior.** Neither abandoned nor shipped of itself: the *line* shipped and this
  document is its predecessor. The gate treats `Superseded by X` as a **shipped-side** signal
  and the file stays in `shipped-design-specs/`.
- **Channel.** Spec is explicit (this clause), then enforcement gate. Without the clause the
  regex gets re-litigated per file.

### 4. Citation into `dormant-explorations/`

- **Input shape.** `UPDATE-PROTOCOL.md` D2 cites `expiring-intentional-proposal.md` as the
  positive-witness precedent, so the dormant directory is load-bearing for an active policy
  clause, not inert history.
- **Expected behavior.** No special handling. Relative-link integrity is a separate concern,
  already swept (`31bd1a6`) to two known and intended dangling links.
- **Channel.** Spec is silent, intentionally.

### 5. Separate finding, routed not resolved: the `open`-ordering claim is ungated

[`../getting-started.md`](../getting-started.md) §4.8 and §4.9 now assert that an `open` placed
after a `def` using its bare names leaves the call unresolved, that `typecheck` exits **0** with
only `warning: call to unknown function`, and that `verify` and `build` exit **1**. Verified
against v0.14.67 with a two-module repro.

That is precisely the falsifiable restriction shape DRIFT-CT-2 exists to guard, in the same two
doc sections and the same "must appear before defs" cluster as the two existing fixtures.
`import-after-def.llmll` and `decl-order-independent.llmll` guard the *position-independent*
half; the newly documented *order-sensitive* half has no fixture.

- **Channel.** Spec is silent (**gap, flagged**).
- **Routing.** `compiler-engineer`, as a DRIFT-CT-2 fixture addition. Note the fixture needs a
  two-module program and a non-default `@cmd:`, since the claim is that `check`/`typecheck`
  passes while `verify` fails; a single-file `@expect: check-ok` fixture would assert the wrong
  half.

## Verification mapping

**This proposal introduces zero proof obligations.** It adds no surface form, no refinement
predicate, no typing rule, and no builtin, so the type/contract/trust channels and the
QF-LIA / nonlinear / Lean fragment classification of `LLMLL.md §5.3.3` and `§5.3.5` do not
apply. Asserting a fragment here would be fabrication; the correct move is to say so rather than
pass the buck downstream.

The analogous classification for a documentation-governance proposal is **enforcement channel**,
for which the project already has a working three-tier vocabulary:

| Invariant | Enforcement channel | Precedent |
|---|---|---|
| `shipped-design-specs/` holds no abandoned or terminal doc | Script gate (proposed DRIFT-DOC-3) | `scripts/version_gate.sh`, `scripts/doc_claims_gate.sh` |
| `dormant-explorations/` admission test holds | Same gate | `archive/dormant-explorations/README.md` |
| Version lineage is queried, never encoded in a path | Behavioral, UPDATE-PROTOCOL P1 | P1 already names `CHANGELOG.md` canonical for release narrative |
| Document-kind organization | None; declined | n/a |

The load-bearing claim is that rows one and two move from **behavioral to mechanical**. That is
the identical move DRIFT-CT-2 made for restriction claims after the 2026-07-19 triage, and it is
why this proposal recommends a gate rather than another protocol paragraph: the archive policy
has been behavioral since 2026-05-24 and drifted to 59 flat files and two miscategorized
documents.

## Affected surface

| Surface | Change | Slot |
|---|---|---|
| `docs/UPDATE-PROTOCOL.md` Archive policy | Retire the version sentence; state the shipped/dropped invariant; name DRIFT-DOC-3 | documentation-lead |
| `docs/design/INDEX.md` archive table | The `shipped-design-specs/` cell carries version prose the retired policy contradicts; add this proposal's one-liner row | documentation-lead |
| `docs/archive/dormant-explorations/README.md` | Add the "Superseded by X counts as shipped-side" clause (edge case 3) | documentation-lead |
| `scripts/` | New gate, sibling naming DRIFT-DOC-3 | compiler-engineer |
| `.github/workflows/version-gate.yml` | Gate invocation | compiler-engineer |
| `scripts/doc-claims/` | New fixture for the `open`-ordering claim (edge case 5, independent finding) | compiler-engineer |

Not touched: `LLMLL.md`, `CHANGELOG.md`, `README.md`, `compiler/src/LLMLL/`. No freeze flag
applies; this proposal introduces no construct.

## Risks and open questions

1. **Gate regex brittleness.** *Spec-drift.* Status lines are prose, and the observed signal
   vocabulary is already four-valued (`Abandoned`, `terminal`, `Superseded by`, `cautionary`). A
   regex over prose will both miss and over-fire. **Bite: complicates, does not block.**
   Mitigation: the gate asserts over a small closed vocabulary that the spec names, and
   documents wanting gating adopt it. This is the same bargain `@expect:` headers make in
   DRIFT-CT-2.
2. ~~**Amending a verbatim lift is not language-team's authority.**~~ **Withdrawn (checked
   2026-07-26).** Rev 0 claimed P1 needed DOC-CONSOLIDATE-level authority because
   [`../UPDATE-PROTOCOL.md`](../UPDATE-PROTOCOL.md):3 declares the file "Lifted verbatim from
   §3.1–3.3." That header does not cover the version-bucket sentence. The file was created at
   `1a8733f`; the sentence entered later at `0e4e2d4` ("design-folder Phase 2 cleanup"), and the
   source proposal contains no version-bucket text at all (`grep` for `sub-categorize` /
   `crosses ~20` over
   [`../archive/shipped-design-specs/doc-consolidation-2026-05-24-proposal.md`](../archive/shipped-design-specs/doc-consolidation-2026-05-24-proposal.md)
   returns nothing). It is ordinary doc-lead-authored prose. **P1 is a normal documentation edit
   inside documentation-lead's own slot and needs only the user's preference, not a governance
   ruling.**
3. **Allowlist ossification.** *Verification-ergonomics.* A two-entry allowlist with no forcing
   function becomes permanent, and the invariant quietly degrades to "everything except the two
   files nobody looks at." **Bite: only matters at scale.** Mitigation: the shrink-only rule,
   stated in the gate.
4. **Link churn under the rejected options.** *Scope.* Roughly 158 link occurrences point into
   the directory, 38 of them in append-only `CHANGELOG.md` sections. **Bite: complicates
   options (b) and (c); zero under the recommendation.**

## Open questions for the professor

1. The Rust and GHC precedents both govern **homogeneous** corpora (proposals only). LLMLL's
   archive is heterogeneous: 28 proposals, 5 specs, 4 plans, 2 spikes, 2 findings, a bug record,
   an action-item list, assorted singletons. Is there an established treatment, in
   configuration-management or software-architecture-documentation literature, of the threshold
   at which a heterogeneous document corpus warrants kind-partitioning rather than
   flat-plus-metadata? The kind axis is declined here on an information-redundancy argument; a
   sharper criterion would confirm that or overturn it.
2. Is **"path as assertion"** a named anti-pattern with a crisper statement than the one used
   here? The claim this proposal rests on is that encoding *mutable* status in a *stable
   identifier* is the same error as encoding it in a filename, and that both instantiate a
   general principle about derived data in identifiers. If the literature names the condition
   precisely, Archive policy should cite that rather than this restatement.

## Hand-off

**Spec-track (P1, P2) to `documentation-lead` — UNBLOCKED.** The user adjudicated FLAT on
2026-07-26 (see the Adjudication note under Restatement); risk 2, which claimed a governance
block, is withdrawn above as unfounded. Affected: `docs/UPDATE-PROTOCOL.md` Archive policy (retire the version-bucket sentence, state
the status-keyed invariant, name DRIFT-DOC-3), `docs/design/INDEX.md` (reconcile the
`shipped-design-specs/` cell, add this proposal's one-liner), and
`docs/archive/dormant-explorations/README.md` (the `Superseded by X` clause). The
shipped/dropped split itself already landed at `b7f1266`; these updates make the policy text
match the tree.

**Code-track (P3, and edge case 5 independently) to `compiler-engineer`.** DRIFT-DOC-3 is a
path-and-status gate with no compiler dependency, so unlike DRIFT-CT-2 it cannot SKIP on a
missing binary and should fail closed. The edge-case-5 fixture is unrelated to the archive and
can ship on its own; it does have a compiler dependency and needs a two-module program plus a
non-default `@cmd:`, because the claim under guard is that `typecheck` passes while `verify`
fails.

No standalone `<proposal>-review.md` exists yet; if the user routes this to the professor, the
M2 fold-and-archive trigger applies on settlement.
