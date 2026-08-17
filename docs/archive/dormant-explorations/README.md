# Dormant explorations

Design docs whose feature **did not ship**, as distinct from
[`../shipped-design-specs/`](../shipped-design-specs/), which holds docs whose feature **shipped**.
The two carry different meanings and the archive policy in
[`../../UPDATE-PROTOCOL.md`](../../UPDATE-PROTOCOL.md) (Archive policy) requires that they not be
mixed: a reader who finds a doc in `shipped-design-specs/` may assume the design is realized in the
compiler, and that assumption is wrong for anything filed here.

## The vocabulary is four-valued, and this directory holds two of the four

Not-shipped is not the same as abandoned. A design can be **deferred**: considered, not chosen, and
kept against a future need. Collapsing that into "dropped" asserts an abandonment the document
itself denies, which is the same category error this directory exists to prevent, one level down.

Each archived doc may declare its side in YAML frontmatter:

| `archive-disposition:` | Meaning | Directory |
|---|---|---|
| `shipped` | the design is realized in the compiler | `../shipped-design-specs/` |
| `superseded` | a successor shipped; this doc is kept for lineage | `../shipped-design-specs/` |
| `dropped` | explored and abandoned; no part shipped | **here** |
| `deferred` | not chosen and not abandoned; captured against a future need | **here** |

`superseded` is deliberately shipped-side: the *line* shipped and this document is its predecessor.
Where the successor was itself abandoned, the author writes `dropped` directly, so nothing has to
follow a supersession chain it can only see the first link of.

[`../../../tools/doc-archive/docarchive.llmll`](../../../tools/doc-archive/docarchive.llmll) (**DRIFT-DOC-3**)
asserts every declared value against its directory and fails CI on disagreement. It is a
consistency gate: it catches the field and the path disagreeing, not both being wrong together.

## Admission test

A doc belongs here when **both** hold:

1. It is not referenced by a live roadmap item, an open Active-Items row, or a research-track
   entry (`R1`–`R8`). A doc a roadmap item still cites is dormant-but-open, not dropped, and
   stays in `docs/design/`.
2. Its feature did not ship in any form. A partially-shipped line goes to
   `shipped-design-specs/` with the residue recorded in the roadmap, not here.

A doc that fails test 1 stays in `docs/design/` with a `**Dormant**` status label in
[`../../design/INDEX.md`](../../design/INDEX.md). Dormancy is a label, not a location.

## Current contents

All three arrived from `shipped-design-specs/`, where they were miscategorized: none shipped, so a
reader finding them under "shipped" would draw exactly the wrong conclusion.

| Document | Side | Evidence it did not ship |
|---|---|---|
| [`expiring-intentional-proposal.md`](expiring-intentional-proposal.md) | `dropped` | Own status line: **"Abandoned (Rev 0.3)"**. The `W614` guard proved unsatisfiable at implementation; it is cited in [`../../UPDATE-PROTOCOL.md`](../../UPDATE-PROTOCOL.md) D2 as the cautionary precedent for the positive-witness rule. Absent from `CHANGELOG.md`. Moved 2026-07-26. |
| [`spec-entropy-reason-string-proposal.md`](spec-entropy-reason-string-proposal.md) | `dropped` | Status "Proposed (Rev 0.2)"; Slice-2 dropped and Slice-1 recorded as the *terminal* recommendation. F-002 was settled with no follow-on mechanism. Absent from `CHANGELOG.md`. Moved 2026-07-26. |
| [`contract-clause-refactor.md`](contract-clause-refactor.md) | `deferred` | Titled "Deferred Design"; status "Deferred — captured for future reference". Records that Option A (sibling fields) was chosen for v0.6 and Option B documented here "for when the contract representation needs richer structure". Zero `CHANGELOG.md` citations, zero roadmap citations. Moved 2026-07-26, second sweep. |

Absence from `CHANGELOG.md` is corroborating, not decisive on its own (27 of the archive's files
are absent from it), but each of these also carries an explicit status line stating its own
disposition, and together those are conclusive.

**Why the third file needed a second sweep.** The first sweep searched for abandonment vocabulary
and `contract-clause-refactor.md` is *deferred*, not abandoned, so it did not match. The gap was
found by measuring how many archived status lines actually decide the shipped-side question: 55 of
57 carry a marker, but only 21 of 57 decide the axis by keyword, because most state lifecycle
("Approved", "BUILT", "CLOSED") rather than disposition. That measurement is why this directory now
has a declared field and a gate rather than a convention and a periodic sweep.

## Not admitted, and why

The four standing candidates all fail test 1 and stay in `docs/design/`: `agent-orchestration.md`,
`component-hub.md` and `type-driven-development.md` are cited as R1/R2 sources, and
`int-3-machine-int-sketch.md` remains roadmap status "P3 — open". Moving any of them needs a
`language-team` adjudication, not a doc-lead sweep.

Note that they fail test 1 on being *referenced*, not on having shipped. A doc a roadmap item still
cites is dormant-but-open, and dormancy is a label rather than a location, so it stays in
`docs/design/` with a `**Dormant**` label in [`../../design/INDEX.md`](../../design/INDEX.md) and
declares no `archive-disposition` at all: the field says which archive directory is correct, and
these are not archived.
