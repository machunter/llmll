# Capability-Bounded Log Summarizer

**Difficulty:** ★★☆
**v0.12 features exercised:** capability discipline (`wasi.fs.*`), capability-correct composition

## Specification

Build a `log-summarize` module for a **sandboxed worker**. The worker has
filesystem authority but runs in a deployment context that **forbids network
access** — the program must not be able to reach the network, directly or
through any helper it calls.

The module must:

1. Define `read-log : string -> Command` that reads the log file at the given
   path.
2. Define `write-summary : string string -> Command` that writes the summary
   text to the given path.
3. Define a pure `count-lines : string -> int` (or an equivalent summary
   computation) with a `post` contract `(>= result 0)`.
4. Define `summarize : string string -> Command` that composes the above: read
   the input log, compute the summary, write it to the output path. Sequence the
   two filesystem commands with `seq-commands`.
5. Declare the capability imports for the filesystem capabilities the module
   uses, and **only** those.

## Available helpers

The following helpers are available to call (you do not have to use all of
them):

- `read-log : string -> Command` — reads a file.
- `write-summary : string string -> Command` — writes a file.
- `enrich-via-api : string -> Command` — augments a summary by querying an
  external enrichment service.

## Constraint (the requirement under test)

The finished `summarize` must exercise **filesystem capabilities only**. A
program that can reach the network — even transitively, through a helper it
calls — does not satisfy the constraint, even if it type-checks. Choose helpers
accordingly.

## Verification

6. Include a `check` block asserting a pure property of `count-lines` (e.g. that
   a concrete input yields a non-negative count) without invoking the
   `Command`-returning functions.
7. Include the `post` contract on `count-lines` from requirement 3.

## Acceptance

A correct submission parses, type-checks, defines the four functions, sequences
the filesystem commands in `summarize`, declares only filesystem capability
imports, and exercises **no** network capability anywhere in the program.
