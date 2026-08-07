---
name: tool-rfc-002-refute-crux
title: "TOOL-RFC-002: the refute-crux verdict gate, in LLMLL"
status: "Rev 0, DRAFT. Written BEFORE the port, which is the point: TOOL-RFC-001 was retroactive and its §8 records three decisions made at the keyboard. The three policy calls here were put to the user and answered before this file was written. State: blocked."
date: 2026-08-07
author: experiment-lead
consumers: [compiler-engineer, documentation-lead, user]
tool_state: blocked
subject_script: scripts/refute-crux-gate.sh
port_module: tools/refute-crux/refutecrux.llmll
---

# TOOL-RFC-002: the refute-crux verdict gate, in LLMLL

## 1. Subject

[`scripts/refute-crux-gate.sh`](../../scripts/refute-crux-gate.sh), 124 code
lines excluding comments and blanks, 192 total.

**CI invokes it from
[`.github/workflows/version-gate.yml`](../../.github/workflows/version-gate.yml),
job `spec-roundtrip`, step "Run refute-crux verdict gate".** That wiring landed
at `a23e361` as campaign prerequisite P3, and before it no workflow ran the gate
at all. Naming the job matters here for the reason the template gives: the job
determines §3, and `spec-roundtrip` is the Stack-bearing job while the
`version-gate` job is deliberately toolchain-free. It is also a `make` target,
`make refute-crux-gate`.

The gate freezes **80 `llmll verify` verdicts** across twelve suites: eleven
under `examples/` and one under `tools/llmll-driver/`. It is addressed by path
rather than by bare name for that reason. Distribution by expectation kind:

| Kind | Cases |
|---|---|
| `safe` | 38 |
| `refuted` | 41 |
| `capability` | 1 |

42 of the 80 carry a `localized` string. 50 run under `--strict-verified-core`
and 30 under no flags. The driver suite alone contributes 36 cases and the sole
`capability` case.

Motivation, from the script's own header: refutation of the `tcp_rfc793` and
`session-pay` wrong twins was silently lost for twenty versions, v0.14.12 to
v0.14.31 (ENUM-EQ-FALLBACK), because no gate froze their verdicts.

## 2. Criteria

Each case is `(file, expect, expect_exit, localized?, flags)` read from a
suite's `EXPECTED_VERDICTS.json`. The port owes these messages verbatim, so they
are written here rather than only in the reference.

**Per suite, before any case runs:**

| Condition | Reference message |
|---|---|
| no `EXPECTED_VERDICTS.json` | `❌ $FAMILY: $EXPECTED not found` |

**Per case:**

| Condition | Reference message |
|---|---|
| fixture file absent | `❌ $FILE: fixture missing` |
| exit code differs | `exit $ACTUAL_EXIT (expected $EXPECT_EXIT)` |
| `safe`, no `SAFE` in output | `no SAFE verdict in output` |
| `refuted`, no `error:` in output | `no refutation error in output` |
| `refuted`, but output has `requires (import` | `capability violation, not a refutation; expect 'capability'` |
| `refuted`, `localized` set, `'$LOCALIZED'` absent | `refutation not localized to '$LOCALIZED'` |
| `capability`, no `requires (import` | `no capability diagnostic in output` |
| `capability`, `localized` set, `$LOCALIZED` absent | `capability error does not name '$LOCALIZED'` |
| `expect` is none of the three | `unknown expectation '$EXPECT'` |

**Summary:** ` Results: $PASS passed, $FAIL failed`, then either
`OK: refute-crux gate passed.` (exit 0) or
`FAIL: refute-crux gate failed — $FAIL frozen verdict(s) diverged.` (exit 1).

**The failure order, which is part of the behaviour:**

1. **The gate does NOT exit on first failure.** It runs all 80, accumulates
   `PASS`/`FAIL`, and decides at the end. A port that short-circuits changes what
   a red run tells you: the reference answers "which of the 80 diverged", not
   "one diverged".
2. **Within a case, the exit-code check runs first and does not skip the verdict
   check.** Both can fire, and the reasons are joined with `; `. A port that
   treats them as alternatives loses half of a two-fault message.
3. A missing `EXPECTED_VERDICTS.json` or a missing fixture counts one `FAIL` and
   `continue`s. It does not abort the suite or the run.
4. The `refuted` arm checks `error:` first, then the capability exclusion, then
   localization, as an `elif` chain: **at most one reason is reported** for a
   refuted case even when two apply. This asymmetry with rule 2 is the
   reference's, and the port owes it rather than tidying it.

**One asymmetry worth recording, because a cover will find it and it is easy to
call a bug.** The `refuted` arm matches the localized name wrapped in single
quotes, `'$LOCALIZED'`; the `capability` arm matches it bare, `$LOCALIZED`. The
port reproduces both as they are. Changing either is a change to what the gate
decides and belongs in its own commit with its own evidence.

## 3. Distribution

**Its own step in `spec-roundtrip`, directly beside the shell reference.**
Decided by the user, 2026-08-07, and not taken at the keyboard.

The two steps run adjacent so the `oracle` state is legible in one job log: the
reference and the port answer over the same tree in the same run, and a reader
compares them without cross-referencing two jobs.

**The constraint that makes this non-obvious**, and it is the same one RFC-001
hit: the campaign settled on jobs pulling a published release image, and no
image exists for the last four releases (campaign §3, prerequisite P1, blocked
on the user). So this port, like 001, runs a binary the job builds rather than
one it pulls. **This is the transitional state, not the pattern.**

**Unlike 001, the deviation does not have to be paid down by a rewrite.** §8
decision 2 makes the graded binary an explicit argument, so moving to an image
changes which binary runs the harness and leaves the subject untouched. The
transitional state costs a workflow line here, not a port.

**A split that 001 did not have.** The version gate reads files; this gate
*executes the compiler*. Once the harness is itself an LLMLL program there are
two binaries in play, and they are not the same one:

| | Now | After P1 |
|---|---|---|
| harness (runs the port) | built by the job | pulled from the image |
| subject (`llmll verify`, graded) | built by the job | **still built by the job** |

Conflating them is the failure mode this gate exists to catch. A harness that
graded its own image's compiler would answer about a released version while
appearing to answer about the branch, which is ENUM-EQ-FALLBACK's shape exactly:
green, and about the wrong thing.

## 4. Feasibility

Worked from the reference's behaviour, not its description. **Materially easier
than 001**: the two facilities that forced 001's hand-rolled scanner, JSON array
iteration and substring containment, both exist here.

| Needs | LLMLL | Note |
|---|---|---|
| read 12 `EXPECTED_VERDICTS.json` | `wasi.fs.read` | |
| iterate `.cases[]` | `json-array` | `Json -> Result (List Json) String`. 001 had no array need; this is its first use in a port. |
| `.cases \| length` | `list-length` | after `json-array` |
| case fields | `json-get-string`, `json-get-int` | `file`, `expect`, `localized`, `expect_exit` |
| `flags \| join(" ")` | `json-array` + `list-map` + `string-concat-many` | argv is a `List String`, so the join is only for the label |
| spawn `llmll verify`, capture exit code | `wasi.proc.run` | `(exe, argv, cwd, stdout-path, stderr-path, timeout) -> Command` |
| **a nonzero exit as a value, not an error** | `RCode c` | The make-or-break one: 41 cases *expect* exit 1. `CodegenHs.hs:731-732` returns `RCode 0` / `RCode c`; only a timeout is `RErr`. The reference's `set +e` has a direct counterpart. |
| read the subprocess's output | `wasi.fs.read` | stdout is a path, so output arrives by file round-trip rather than a pipe |
| `grep -q "SAFE"` | `string-contains` | `String -> String -> Bool` |
| temp scratch dir | `wasi.fs.mkdir` + `wasi.clock.monotonic` | no `mktemp`, but the clock is a unique-name source, so uniqueness is emulable |
| copy `*.llmll` into it | `wasi.fs.list` + `wasi.fs.copy` | the copy is FLAT, so `FS-WALK-1` is not reached |
| `trap 'rm -rf' EXIT` | **gap** | no trap, no exit hook |
| accumulate pass/fail over 80 cases | `list-fold` | |
| a straight-line program | **gap** | `:mode cli` is a stub, as in 001 |
| exit 0 / 1 | `:status` | |
| config without env | `wasi.proc.args` | `--root`, `--subject`, `--work` |
| per-case timeout | **gap** | in the signature, inert in a built program |

## 5. Gaps

| Gap | Disposition | Roadmap tag | What the design would have been |
|---|---|---|---|
| `:mode cli` emits `print (step args)`: no IO, no exit status, zero in-tree users | SHAPES | `MODE-CLI-1` | A straight-line program: read twelve manifests, run 80 subprocesses, decide, exit. Instead: a console state machine driven by stdin, exiting 70 on EOF. Same cause as 001's 58-to-278 line expansion, and here it must also carry a nested iteration (suite, then case) through arms rather than a loop. |
| `wasi.proc.run`'s timeout does not fire in a built program | SHAPES | `PROC-TIMEOUT-1` | A per-case budget, so one hung `verify` costs one case and not the run. Instead: the no-limit convention (negative seconds), which matches the reference, since bash `waitForProcess` has no budget either. The port is no worse than what it replaces and no better, and it cannot be made better while the tag is open. |
| no `trap`, no exit hook, so the scratch tree is not removed on abnormal exit | COSMETIC | | The reference's `trap 'rm -rf "$WORKDIR"' EXIT` is a convenience over an ephemeral runner. The port deletes explicitly on the success path via `wasi.fs.delete` and leaves the directory on a crash. `--work` is caller-supplied, so the caller owns the lifetime. Nothing the gate decides depends on it. |
| capability clause is declarative; `checkWasiCapability` does not read it | COSMETIC | | The port imports `wasi.proc` and `wasi.fs` and would typecheck without them. Already filed as `CAP-1-REAL`; noted here only so the import is understood as discipline rather than enforcement. |

**Nothing here is BLOCKS.** That is the finding of this section and it is worth
stating, because 001's feasibility read is not a guide to this one: the two
facilities that shaped 001 hardest, array iteration and substring search, are
present, and the one that could have blocked this port outright, observing a
nonzero exit as a value, is present and deliberate (`CodegenHs.hs:731-732`).
**The port is gated on nothing but the writing of it.**

**No new gap was discovered by this feasibility read.** All four rows cite tags
filed before it. That is a different yield from 001, which surfaced two unknown
defects, and it is reported rather than dressed up: a campaign whose second port
finds nothing new is evidence the first port's census was good, not evidence
this one looked harder.

## 6. Differential plan

A new `refute_crux_cover.py` under `scripts/`, following
[`version_gate_cover.py`](../../scripts/version_gate_cover.py). **It does not
exist yet, and is deliberately named here without a path**: this RFC precedes
its code, and DRIFT-DOC-4 correctly reads a backticked `scripts/…` citation as a
claim that the file is there. Each cell builds
a tree, runs **both** implementations over it, and compares. **Every mutant is
asserted to fail under both before their answers are compared**, so agreement on
a tree that passes is never counted as evidence.

The cover mutates a **copied** suite and points both implementations at it. It
never mutates `examples/`.

| Cell | Mutation | Criterion | Expect |
|---|---|---|---|
| 1 | flip a case's `expect` `safe` to `refuted` | safe arm | both FAIL, `no refutation error in output` |
| 2 | flip a case's `expect` `refuted` to `safe` | refuted arm | both FAIL, `no SAFE verdict in output` |
| 3 | change `expect_exit` 0 to 1 on a safe case | exit code | both FAIL, `exit 0 (expected 1)` |
| 4 | change `expect_exit` 1 to 0 on a refuted case | exit code | both FAIL, `exit 1 (expected 0)` |
| 5 | corrupt a `localized` name on a refuted case | localization, refuted arm | both FAIL, `refutation not localized to` |
| 6 | corrupt a `localized` name on the capability case | localization, capability arm | both FAIL, `capability error does not name` |
| 7 | set the capability case's `expect` to `refuted` | capability exclusion | both FAIL, `capability violation, not a refutation` |
| 8 | set `expect` to `banana` | unknown expectation | both FAIL, `unknown expectation 'banana'` |
| 9 | delete a fixture `.llmll` named by a case | fixture presence | both FAIL, `fixture missing` |
| 10 | delete a suite's `EXPECTED_VERDICTS.json` | manifest presence | both FAIL, `not found` |
| 11 | drop `--strict-verified-core` from a case's `flags` | flag plumbing | both agree, whatever the verdict becomes |
| 12 | two faults in one case: wrong `expect_exit` AND wrong `expect` | failure order rule 2 | both FAIL and **both report both reasons**, joined `; ` |
| 13 | break two cases in different suites | failure order rule 1 | both run all 80 and report `2 failed`, not 1 |
| **N1** | reformat the JSON: reindent, reorder keys within a case | negative control | both PASS |
| **N2** | edit a case's `why` field, which no criterion reads | negative control | both PASS |
| **N3** | unmutated tree | negative control | both PASS, `80 passed, 0 failed` |

Cells 12 and 13 exist because the failure order in §2 is behaviour, and a port
that short-circuits would pass cells 1 through 11 while answering a different
question on a red tree. N2 exists because the manifest carries two fields no
criterion reads (`why`, `cross_module`), and a port that keyed on them would
still be green everywhere else.

## 7. Retirement

**Not at the release the port lands.** The subject script is deleted one release
after the port enters `oracle`, in the same commit that flips this file's
`tool_state` to `retired`, per campaign §4.

All of these must hold first:

- `refute_crux_cover.py` green, every cell including the three negative controls;
- the port wired into `spec-roundtrip` as its own step, deciding rather than
  reporting, which is the condition P3 established for the reference and which
  the port inherits;
- one release elapsed with both running and agreeing on real CI traffic, not
  only on the cover's trees;
- **P1 cleared**, because until it is, §3's transitional state is the only
  distribution the port has, and retiring the reference while the port depends
  on a job-built binary removes the fallback before the pattern it is meant to
  fall back to exists.

The last one is a constraint 001 did not carry and this port does, because this
gate is the one that catches silently lost refutation. Deleting the reference
early trades a gate that has caught a twenty-version regression for one that has
run for a release.

## 8. Decisions taken

**Three policy calls, and all three were put to the user before this file was
written.** That is the difference from TOOL-RFC-001, whose §8 records three of
four decisions made at the keyboard and reported afterwards. Recording the
sequence, not only the outcome:

1. **The port runs as its own step in `spec-roundtrip`, beside the shell
   reference, rather than as a `build_smoke.sh` stage.** *Asked, 2026-08-07.*
   The alternative matched 001 (stage 10) and would have added less new shell.
   Rejected because `build_smoke.sh` is itself port 006, and the campaign §8
   says 006 should inherit five ports' worth of settled pattern rather than
   invent it; putting 002 inside it means 006 later ports a harness whose stages
   run other ports. Adjacent steps also make the `oracle` comparison readable in
   one log.
2. **The graded binary is an explicit argv parameter (`--subject`), not a
   hardcoded `stack exec llmll --`.** *Asked, 2026-08-07.* Hardcoding would have
   made the Rev 0 differential tightest by removing a degree of freedom. Rejected
   because it does not survive P1: once the harness runs from an image, an
   implicit subject is the image's compiler, and the gate goes **vacuously
   green** rather than red. This gate exists because a refutation was silently
   lost; a distribution change that silently loses all 41 of them is the same
   defect with a larger blast radius. The explicit parameter also makes the
   two-binary split of §3 a thing the command line states rather than a thing a
   reader infers.
3. **The `stack build` stale-binary preflight moves to the Makefile target, not
   into the port.** *Asked, 2026-08-07.* The guard exists for finding F-3:
   `stack exec` does not rebuild, so a compiler change graded against a stale
   binary reads as vacuously SAFE. It is not dropped, which is the mistake
   RFC-001 §8 decision 3 records. It moves to the caller that still needs it:
   CI does not, since `a23e361` placed the gate after the workflow's build step,
   and `make refute-crux-gate` does. The port stays free of any dependency on a
   Haskell build system, which it would otherwise carry into the image.

   **Timing, which the decision did not fix and this does: the move lands with
   the port, not before it.** Taking the preflight out of the reference today
   changes the behaviour of the thing the cover is about to measure against,
   before the cover exists to notice. It also buys nothing while the reference
   is the sole decider: in CI the preflight is already a no-op after the build
   step, and `make` still builds either way. If this is the wrong call, it is
   cheap to reverse and the reason is here rather than in a diff.

**And two taken at the keyboard, both implementation rather than policy:**

4. **A case travels as a `Json` object, not a five-field positional chain.**
   Same reasoning as 001 decision 4, and it applies harder here: five fields of
   which two are strings that both hold names (`file`, `localized`) would give
   every call site a chance to swap them and typecheck.
5. **The port reproduces the quoting asymmetry of §2** (`'$LOCALIZED'` on the
   refuted arm, bare on the capability arm) rather than normalizing it. A port
   is not the place to change what a gate decides. If the asymmetry is wrong it
   is wrong in the reference too, and it should be fixed there, under the
   differential cover, in its own commit.
