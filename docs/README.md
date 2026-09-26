# LLMLL documentation: start here

Most files under `docs/` are the team's working material. If you are new, read these, in this order:

| Read | For |
|---|---|
| [`../README.md`](../README.md) | What LLMLL is, a worked refutation, and what is proven versus not |
| [`getting-started.md`](getting-started.md) | Building the compiler, known-good patterns, schema versioning |
| [`../LLMLL.md`](../LLMLL.md) | The language specification (types, syntax, contracts, verification matrix in §5.3.5) |
| [`one-pager.md`](one-pager.md) | Project overview with a claim-to-evidence map, including what is planned or not shipped |
| [`../ROADMAP.md`](../ROADMAP.md) | The public roadmap: what shipped, what is next, deliberate boundaries |
| [`../experiments/README.md`](../experiments/README.md) | The experiments and their results |
| [`orchestrator-walkthrough.md`](orchestrator-walkthrough.md) | An end-to-end multi-agent orchestration exercise |
| [`../CHANGELOG.md`](../CHANGELOG.md) | Release notes by version |

## Schemas

- [`llmll-ast.schema.json`](llmll-ast.schema.json): the JSON-AST form that agents read and patch.
- [`llmll-trust-report.schema.json`](llmll-trust-report.schema.json): the `verify --trust-report --json` output.
- [`proof-artifact.schema.json`](proof-artifact.schema.json): the record written by `verify --proof-artifact`.

Known gap: the AST schema rejects every tracked `.ast.json` file, an open item in the internal log (SCHEMA-TRUTH-1). The trust-report schema accepts every report the compiler emits, and a test fails when the two disagree.

## Working material

- [`design/`](design/INDEX.md) holds design proposals and reviews. Its [`INDEX.md`](design/INDEX.md) gives each document's status. These are working drafts, not specifications; settled content is promoted into `LLMLL.md`.
- `archive/` holds superseded and shipped design material, kept for history.
- [`compiler-team-roadmap.md`](compiler-team-roadmap.md) is the team's internal work log: every open item with its evidence, plus the shipped-release history. It is long and written for the team. Start from [`../ROADMAP.md`](../ROADMAP.md) instead.
- [`UPDATE-PROTOCOL.md`](UPDATE-PROTOCOL.md) says which document is canonical for what, and which documents a change must update.
- `assets/` holds the images and GIFs the README uses.
