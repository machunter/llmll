# DRIFT-DOC-3 self-test fixtures

Read by [`../../tools/doc-archive/docarchive.llmll`](../../tools/doc-archive/docarchive.llmll) before it scans `docs/archive/`.

The real corpus is expected to be conformant, so the gate's failure branch would otherwise never
execute in CI: a documentation gate that only ever runs its passing path is untested code that
happens to exit 0. These fixtures drive both branches on every invocation.

| Tree | Expected | Drives |
|---|---|---|
| `pass/` | 0 violations, 4 gated files | the clean path (one file per vocabulary value), and catches over-firing |
| `fail/` | exactly 4 violations | mis-filed shipped-side, mis-filed dormant-side, unknown vocabulary value, declaration outside the governed directories |

The counts are asserted, not merely reported. `fail/` returning 3 is a gate regression just as much
as `pass/` returning 1, which is why the gate compares against 4 rather than against "nonzero". The
`pass/` tree also asserts that 4 files were *gated*, so a change that stops reading the frontmatter
fails here instead of quietly passing everything.

The fourth case was added after it fired for real: the archived professor review of the proposal
that specified this gate declared `archive-disposition: superseded` while sitting in
`professor-reviews/`, which is outside the shipped-side/dormant-side split. The gate read the field,
found no governed directory to check it against, and said nothing.

These files are fixtures, not archived documents. Do not move them into `docs/archive/`, and do not
"fix" the `fail/` tree: its whole purpose is to be wrong.
