# Dormant explorations

Design docs that were **explored and dropped**, as distinct from
[`../shipped-design-specs/`](../shipped-design-specs/), which holds docs whose feature
**shipped**. The two carry different meanings and the archive policy in
[`../../UPDATE-PROTOCOL.md`](../../UPDATE-PROTOCOL.md) (Archive policy) asks that they not be
mixed: a reader who finds a doc in `shipped-design-specs/` may assume the design is realized in
the compiler, and that assumption is wrong for an abandoned exploration.

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

Intentionally empty. The directory was created by the 2026-07-26 sweep so the classification
has a home; no doc has been adjudicated into it yet. The standing candidates are the three
`**Dormant**`-labelled docs in `docs/design/` (`agent-orchestration.md`, `component-hub.md`,
`type-driven-development.md`) and `int-3-machine-int-sketch.md`, and **all four currently fail
test 1**: the first three are cited as R1/R2 sources and INT-3 remains roadmap status "P3 —
open". Moving any of them needs a `language-team` adjudication, not a doc-lead sweep.
