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

The **F-002 terminal pair**, moved here 2026-07-26 from `shipped-design-specs/`, where they
were miscategorized: neither ever shipped, so a reader finding them under "shipped" would draw
exactly the wrong conclusion.

| Document | Evidence it did not ship |
|---|---|
| [`expiring-intentional-proposal.md`](expiring-intentional-proposal.md) | Own status line: **"Abandoned (Rev 0.3)"**. The `W614` guard proved unsatisfiable at implementation; it is cited in [`../../UPDATE-PROTOCOL.md`](../../UPDATE-PROTOCOL.md) D2 as the cautionary precedent for the positive-witness rule. Absent from `CHANGELOG.md`. |
| [`spec-entropy-reason-string-proposal.md`](spec-entropy-reason-string-proposal.md) | Status "Proposed (Rev 0.2)"; Slice-2 dropped and Slice-1 recorded as the *terminal* recommendation. F-002 was settled with no follow-on mechanism. Absent from `CHANGELOG.md`. |

Absence from `CHANGELOG.md` is corroborating, not decisive on its own (27 of the archive's
files are absent from it), but each of these also carries an explicit abandoned/terminal
status line, and together those are conclusive.

## Not admitted, and why

The four standing candidates all fail test 1 and stay in `docs/design/`: `agent-orchestration.md`,
`component-hub.md` and `type-driven-development.md` are cited as R1/R2 sources, and
`int-3-machine-int-sketch.md` remains roadmap status "P3 — open". Moving any of them needs a
`language-team` adjudication, not a doc-lead sweep.
