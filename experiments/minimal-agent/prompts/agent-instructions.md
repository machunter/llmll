# Agent Instructions

You are in an isolated LLMLL experiment directory.

Inputs:

- `LLMLL.md`
- `problem.md`
- `PROBLEMS.md`

Goal: produce a first-round LLMLL solution for `problem.md`.

Rules:

1. Work only in this directory. Do not read or modify files outside it.
2. Use only `LLMLL.md`, `problem.md`, and diagnostics from tools you run.
3. Write the solution as `solution.llmll` unless you intentionally choose JSON-AST, in which case write `solution.ast.json`.
4. Do not edit `LLMLL.md`, `problem.md`, or `AGENT_INSTRUCTIONS.md`.
5. Append every issue, uncertainty, missing feature, failed command, or blocker to `PROBLEMS.md`.
6. Stop at the first error. A tool command with a nonzero exit code is an error.
7. If you cannot complete the solution, write `STOPPED.md` with the exact blocker and do not continue.

Expected final files:

- `solution.llmll` or `solution.ast.json`
- Updated `PROBLEMS.md`
- `STOPPED.md` only if blocked
