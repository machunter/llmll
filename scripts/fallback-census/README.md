# FALLBACK-CENSUS-1 — the body-faithful census and its ratchet

`../fallback_census.py` measures, once per CI run, how much of the committed
LLMLL tree reaches body-faithful verification and what refuses the rest. This
directory holds the ratchet floor the gate compares against.

## Why the instrument exists

The tree-wide body-faithful ratio decides whether `RESP-FACT-1` scales faster
than the `wasi.*` alphabet grows. Before this gate it appeared in no committed
file. It had been counted by hand three times and the first two readings were
wrong in the same direction, because the compiler labelled an unfilled hole and
a written body that leaves the fragment with the same string: the first
histogram's 252 `body-outside-fragment` entries were 245 scaffolds plus 7 real
bodies. The compiler now separates them (`unfilled-hole`, `no-post`), and this
gate turns the labels into a number a later run can diff.

## What it measures

    ratio = functions reaching body-faithful / functions with a post

A function with no post has no proof goal, and an unfilled hole has nothing
written to prove. Neither is a fallback in the sense the ratio asks about, so
both leave the denominator and are reported beside it.

The population is every tracked `*.llmll` and `*.ast.json` under `examples/`,
`tools/` and `scripts/build-smoke/`, at any depth. It comes from `git ls-files`,
so gitignored build output is not measured and not copied.

## How it runs

One `llmll --json verify --strict-verified-core FILE` per file, from the file's
own directory, inside a copy of the tracked tree. Each worker gets its own copy
and each run deletes the sidecar it creates, so the result does not depend on
`--jobs` and the measured tree is never modified.

A negative verdict is re-run once, alone, before it is believed. One file has
been seen to report `refuted` during a loaded census and `pass` on five
isolated runs and eight concurrent ones. A file that disagrees with itself is
reported as `unstable` and named; the gate does not turn a flaky verdict into a
red build, and does not hide it either.

## Where it runs

**Locally, not in CI.** The CI step was removed on the day it shipped, after the
runner killed it twice. One example,
`examples/heartbleed/secure-channel/sc-channel.llmll`, peaks between 4.68 GB and
6.83 GB of resident memory in a single verify, re-measured over five isolated
samples on 2026-09-09; the peak is not stable. Its agent-filled twin peaks at
5.34 GB. This script gives its workers the biggest files first, so those two
multi-gigabyte verifies started together. The cost is liquid-fixpoint's and not
the compiler's: `fixpoint` alone on the emitted `.fq` reaches the whole peak. The
roadmap rows `VERIFY-MEMORY-1` and `FALLBACK-CENSUS-1 residue (1)` carry the
measurement and the three candidate fixes. Until one is chosen, run
`make fallback-census` before a release.

## The ratchet

`BASELINE.json` records the set of files that pass `--strict-verified-core`.

- The set may grow freely. The gate says so and asks for a refresh.
- The set may not shrink. A file that stops passing fails the gate.
- To shrink it deliberately, add the path to `waivers` with a reason. An empty
  reason does not count.
- A file that did not pass this run because its verdict is unstable is reported,
  not failed.

`recorded` in that file is the ratio at the time it was written. It is a record,
not a threshold: the gate does not compare ratios, because a new example with a
string-valued post would fail a ratio threshold for doing nothing wrong.

## Refreshing the baseline

    python3 scripts/fallback_census.py \
      --llmll "$(cd compiler && stack path --local-install-root)/bin/llmll" \
      --repo . --write-baseline

Refresh it in the commit that grows the set, not in a later one.

Locally, `make fallback-census` builds the compiler first and runs the same
command CI runs. Run the script directly only when the binary is already
current: `stack exec` does not rebuild, so a compiler change measured against
the old binary reports the old tree.

## Reading a run

    python3 scripts/fallback_census.py --llmll <bin> --repo . --out census.json

`census.json` carries the per-file outcomes, the cause histogram, the refusing
constructs and the per-kind split. It carries no timestamp, so two runs over one
tree produce identical bytes and a diff shows only what changed.

Its cover is `../tests/test_fallback_census.py`: 18 cells over a stub compiler
and 3 against a real one.
