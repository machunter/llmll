---
name: tool-rfc-003-doc-claims
title: "TOOL-RFC-003: the doc-claim drift gate, in LLMLL"
status: "Rev 1. Written before any code, which is now the campaign's default rather than its exception. BOTH section 8 questions are now ANSWERED: the port reproduces the reference's two SKIP paths faithfully and the silent-success behaviour is filed as its own roadmap row (user adjudication 2026-08-08); the @expect grammar is implemented in FULL, which turned out not to be a free choice at all. State: ORACLE. The port lands with its differential cover green (17 cells, 3 negative controls) and both implementations wired adjacent in `spec-roundtrip`. The cover found TWO real defects in the port before either shipped, which is the campaign premise landing on the campaign for the second time."
date: 2026-08-08
author: experiment-lead
consumers: [compiler-engineer, documentation-lead, user]
tool_state: oracle
subject_script: scripts/doc_claims_gate.sh
port_module: tools/doc-claims/docclaims.llmll
---

# TOOL-RFC-003: the doc-claim drift gate, in LLMLL

## 1. Subject

[`scripts/doc_claims_gate.sh`](../../scripts/doc_claims_gate.sh), **97 code
lines** excluding comments and blanks, 145 total. Smaller than 002's subject
(124) and larger than 001's (58).

**CI invokes it from
[`.github/workflows/version-gate.yml`](../../.github/workflows/version-gate.yml),
job `spec-roundtrip`, step "Run doc-claim drift gate (DRIFT-CT-2)".** Naming the
job is what determines §3, and this one is already the Stack-bearing job that
hosts 002's port and its reference, so 003 inherits a toolchain that 001 and 002
each had to argue for. It is invoked with `working-directory: compiler` and
`LLMLL_BIN: stack exec llmll --`.

**That invocation is a trap the port must not inherit.** `stack exec` resolves
against whatever stack project the cwd sits in; it works here only because
`compiler/` is one. The restart record §7 carries the incident where the same
idiom, run from `tools/refute-crux`, silently retargeted the global project and
tried to install GHC 9.10.3 on a Linux runner. The port takes the absolute
`$(cd compiler && stack path --local-install-root)/bin/llmll` as `--subject`,
the way 002 does.

**What it decides.** It runs each of **16 fixtures** in
[`scripts/doc-claims/`](../../scripts/doc-claims/) through the compiler and
asserts the observed verdict matches the fixture's `;; @expect:` header. Its
purpose is documentation that has drifted from compiler behaviour, specifically
stale *restriction* claims: a doc saying a program is rejected when the compiler
accepts it, or the reverse.

Fixture census, taken at v0.14.91:

| `@expect` base | Fixtures |
|---|---|
| `check-ok` | 6 |
| `parse-error` | 3 |
| `check-error` | 3 |
| `warn` | 2 |
| `output` | 1 |

Three fixtures carry `@cmd`, overriding the default `check {file}`, with values
`checkout {file}`, `typecheck {file}` and `verify {file}`.

**REV 1 SAID THIS GATE NEEDS A SOLVER. IT DOES NOT, AND THE SENTENCE CONTRADICTED
ITSELF IN ITS OWN SECOND HALF.** It read: "**The `verify` one means this gate
needs a solver**, which the job has only since campaign prerequisite P3; before
that it was one of the three gates that 'decide without a proof' and is named as
such in the workflow's own comment." Both halves cannot be true, and **the
workflow's comment was the correct one**.

`open-after-def-verify.llmll` expects `check-error:call to unknown function`. That
is a name-resolution failure, reached before any verification condition is built,
so `llmll verify` never reaches the solver. **Measured three ways rather than
argued:**

1. the reference gate scores **16/16, exit 0**, under `PATH=/usr/bin:/bin:/usr/local/bin`,
   which holds neither `fixpoint` nor z3 on the machine it was run on;
2. `verify` on that fixture under the same PATH prints `error: call to unknown
   function 'inc'`, not the exit-3 "solver unavailable";
3. the differential cover has **never had a solver available on either side** (it
   pins that same restricted PATH for both implementations, deliberately, so they
   are asked the same question) and all 17 cells pass, the three negative controls
   included. Those controls require both implementations to **pass** the
   unmutated tree, so a gate that silently needed a solver could not have got
   green there.

**CI settles it independently of any local measurement**, and this is the
stronger evidence because nobody arranged it: the two doc-claims steps run at
positions 7 and 8 of `spec-roundtrip`, while z3 is installed at step 10 and
`fixpoint` reaches `PATH` at step 13. Both gates decide three steps before the
solver exists.

**Why the error is worth keeping rather than deleting.** It is finding 7's shape
pointed at the SUBJECT instead of the language: a property was read off a
fixture's `@cmd` field (it says `verify`, so it must verify) rather than off what
the fixture's expectation actually makes the compiler do. The cost would have
landed on 004 and 005, which would have inherited "this class of gate needs a
solver" as a settled fact.

## 2. Criteria

Each fixture is `(@doc, @expect, @claim, @cmd?)`. The port owes these messages
verbatim, so they are written here rather than only in the reference.

**Verdict classification**, `observed_verdict()`, and **the order is load-bearing
and stated in the reference's own comment**: a parse error prints as
`(error :phase parse ...)` and would also match the generic semantic case, so it
must be tested first.

| Order | Condition | Verdict |
|---|---|---|
| 1 | output contains `:phase parse` | `parse-error` |
| 2 | output matches `error:` at line start or after whitespace (ERE `(^ or space)error:`) | `check-error` |
| 3 | output contains `✅` **and** contains `OK` | `check-ok` |
| 4 | otherwise | `unknown` |

**Expectation forms.** `@expect` is `<verdict>` or `<verdict>:<substring>`. The
substring, when present, must also appear in the output: that is what pins a
cited diagnostic rather than only a verdict class. Three bases behave
differently:

| Base | Match rule |
|---|---|
| `output` | subcommand-agnostic; the substring must appear anywhere. Observed is the literal `output` |
| `warn` | output must contain `warning:` **and** the substring; observed is `warn`, else `no-warning` |
| anything else | `observed_verdict()` must equal the base, **and** the substring must appear |

**Per-fixture messages:**

| Condition | Reference output |
|---|---|
| match | `  ✔ <basename>  expect=<expect> [<docref>]` |
| mismatch | a five-line block: `  ✘ <basename>`, then `expect`, `observed`, `doc`, `claim`, then the captured output indented four spaces under `--- llmll check output ---` |

**Summary:** `DRIFT-CT-2 PASS: N doc-claim(s) match compiler behaviour` (exit 0),
or `DRIFT-CT-2 FAIL: N of M doc-claim(s) drifted from compiler behaviour`
(exit 1) followed by every failure report and the two-line instruction to fix
**both** the fixture header and the doc section named in `@doc`.

**The failure order, which is part of the behaviour:**

1. **It does not exit on first failure.** All fixtures run, failures accumulate
   in `FAIL_REPORTS`, and the decision is at the end. Same shape as 002.
2. **Failure reports are printed AFTER the summary line**, not interleaved with
   the per-fixture ticks. A port that streams them changes what a red log looks
   like.
3. **The per-fixture tick line is printed for passes only.** Failures print
   nothing at their position in the loop.

**TWO SKIP PATHS, AND THEY ARE THE REASON §8 HAS A QUESTION IN IT.** The gate
exits **0** and asserts nothing when no `llmll` binary is found, and again when
the fixture directory is empty. Both print a `DRIFT-CT-2 SKIP:` line. This is
finding 6's class in the reference itself: a gate that cannot decide reports
success. See §8 question 1.

## 3. Distribution

**The same job and the same step neighbourhood as 002**, `spec-roundtrip`, and
this is the first port in the campaign for which that needs no argument: the job
already builds the compiler, installs jq, installs z3 and builds `fixpoint`,
because 002's port forced all of it (finding 12). 003 is the first port to
inherit a complete toolchain rather than establish one.

**Of that toolchain it needs only the compiler**, which §1 now records against
its own earlier claim. That is why both doc-claims steps can sit at positions 7
and 8, ahead of the solver setup, and it is a property to preserve rather than an
accident: a cheap gate that runs before the expensive setup fails faster when it
fails.

**The harness/subject split is the same as 002's and is not optional.** The
harness is the port; the SUBJECT is the `llmll` under test, named by an explicit
argument. Conflating them would grade a released compiler while appearing to
grade the branch, which is ENUM-EQ-FALLBACK's shape.

**The transitional state is unchanged**: the campaign's settled distribution is
jobs pulling a published release image, and this port, like 001 and 002, runs a
binary the job builds. Now that v0.14.88 through v0.14.91 are all published, the
blocker recorded in 002 §3 (no image exists) is gone, so the move is available
whenever the campaign takes it. **This RFC does not take it**, because doing so
for one port and not the other two would leave the job pulling and building at
the same time.

## 4. Feasibility

Worked from the reference's behaviour. **Read this table as a list of things to
go and try, not as a clearance**: 002's Rev 0 concluded "nothing here is BLOCKS"
and "no new gap was discovered", and building it found four defects. A
feasibility table enumerates what the language HAS; the defects are in what it
DOES.

| Needs | LLMLL | Note |
|---|---|---|
| enumerate `scripts/doc-claims/*.llmll` | `wasi.fs.list` + filter | 002's `ends-with?` / `llmll-files` are directly reusable. Non-recursive, so `FS-WALK-1` does not bite |
| read a fixture's header | `wasi.fs.read` | whole file as `RText` |
| find the `@expect:` line | `string-split "\n"` + `list-filter` + `string-contains` | the reference's `grep -m1` is FIRST match; `list-head` of the filtered list |
| strip the `@field:` prefix | `string-split ":"` + rejoin | the reference's `sed`. Values may themselves contain `:` (`warn:<substring>`), so the tail must be rejoined, not taken as element 1 |
| trim leading space | `string-trim` | exists; the reference's `[[:space:]]*` |
| `${expect%%:*}` / `${expect#*:}` | `string-split ":"` | first element and the rejoined rest |
| `{file}` substitution in `@cmd` | `string-split` + `list-fold` | no replace builtin; 002's `dashed` already hand-rolls exactly this shape |
| split `@cmd` into argv | `string-split " "` | the reference's `read -r -a` |
| spawn the subject, capture output | `wasi.proc.run` | **and this is the first port that can use PROC-MERGE-1**: the reference captures `2>&1`, and equal stdout/stderr path strings now merge onto one handle (v0.14.91). 002 had to read two files and concatenate |
| a nonzero exit is not an error | `RCode c` | the reference brackets its call in `|| true`; several fixtures expect a failing compile |
| `grep -q ':phase parse'` | `string-contains` | |
| `grep -q '✅'` | `string-contains` on a non-ASCII literal | **and this is the first port that can rely on CAPTURE-ENCODING-1** (v0.14.90). Before it, a `✅` in a literal reached the running program as `05` |
| `grep -qE` for `error:` at line start or after whitespace | **GAP** | `regex-match` typechecks, verifies, and then fails at GHC: `REGEX-LOWER-1`. §5 |
| exit 0 / 1 | `:status` | 002's clamped `rc-status` is reusable |
| the whole program shape | **GAP** | `MODE-CLI-1`: `console` is the only entry mode that can touch the world, so this is a stdin-driven step machine, not a loop. §5 |
| bounded character scan, if needed | `range` + `string-char-at` | **VERIFY BEFORE RELYING ON IT.** Restart-record finding 2 says "there is no character decomposition at all, so a scan must be a fold over a literal index list with a hand-written bound". But `string-char-at : string int -> string` and `range : int int -> list[int]` both exist ([`TypeCheck.hs:133-142`](../../compiler/src/LLMLL/TypeCheck.hs)), which looks like a bounded scan with a computed bound. **Either finding 2 is stale or one of these does not do what its type says.** Probe it; do not assume either way |

## 5. Gaps

| Gap | Disposition | Roadmap tag | What the design would have been |
|---|---|---|---|
| `:mode cli` cannot perform a command or set an exit status | SHAPES | `MODE-CLI-1` | A straight-line program: list a directory, run 15 subprocesses, classify, decide, exit. Instead a `console` state machine driven by stdin, exiting 70 on EOF. The same expansion 001 and 002 paid; the nesting here is shallower than 002's (fixture, then one spawn) so the budget is far smaller |
| `regex-match` does not survive codegen, so the `error:` line-anchored match has no direct counterpart | SHAPES | `REGEX-LOWER-1` | One `regex-match` call reproducing the reference's ERE exactly. Instead: split the captured output on `"\n"`, and per line test `starts-with "error:"` or `string-contains " error:"` or the tab form. **The residue is real and must be recorded rather than glossed**: POSIX `[[:space:]]` also matches vertical tab, form feed and carriage return, which the port would not. No current fixture output contains those, which makes this a divergence with an empty firing population TODAY and a trap for whoever adds a fixture whose diagnostic wraps oddly |
| two SKIP paths report success without deciding | COSMETIC | | Noted here, disposed as a DECISION rather than a gap: it is the reference's behaviour and not a language limitation. §8 question 1 |
| the fixture directory is read non-recursively | COSMETIC | | `FS-WALK-1` exists but does not bite: `scripts/doc-claims/` is flat, and the reference's own glob is `*.llmll` with no `**` |

**No BLOCKS row.** Stating that plainly, and stating equally plainly that 002's
Rev 0 said the same thing and was wrong. The two rows most likely to become
BLOCKS on contact are the `range`/`string-char-at` question in §4 and the
`@cmd` argv split, neither of which has been executed.

## 6. Differential plan

`scripts/doc_claims_cover.py`, the shape 001 and 002 use: mutate a scratch tree,
run **both** implementations, assert both fail, then compare their answers.
**Every mutant is asserted to fail under both before their answers are
compared.** Agreement on a passing tree is not evidence.

| Cell | Mutation | Criterion | Expect |
|---|---|---|---|
| 1 | flip a `check-ok` fixture's `@expect` to `check-error` | verdict equality | both fail |
| 2 | flip a `parse-error` fixture's `@expect` to `check-error` | classification ORDER (a parse error also matches the semantic test) | both fail |
| 3 | flip a `check-error` fixture's `@expect` to `parse-error` | classification order, other direction | both fail |
| 4 | corrupt the `:<substring>` of an `@expect` that has one | substring pin | both fail |
| 5 | drop the `warning:` trigger from a `warn` fixture's source | `warn` needs `warning:` present | both fail |
| 6 | corrupt an `output`-base fixture's substring | subcommand-agnostic path | both fail |
| 7 | change a fixture's `@cmd` to a subcommand whose output cannot match | `@cmd` override is honoured | both fail |
| 8 | delete a fixture's `@cmd` line so it falls back to `check {file}` | the `check {file}` default | both fail |
| 9 | break a `check-ok` fixture so the compiler rejects it | the gate reads the COMPILER, not the header | both fail |
| 10 | empty the fixture directory | the empty-directory path | **see §8 q1**: both SKIP today |
| 11 | point `LLMLL_BIN` at a nonexistent path | the no-binary path | **see §8 q1**: both SKIP today |
| 12 | two fixtures broken at once | failures accumulate; the run does not exit on the first | both fail, both report TWO |
| 13 | break the LAST fixture only | the loop does not stop early | both fail |
| N1 | reformat a fixture's header whitespace | trimming | both pass |
| N2 | edit a `@claim` line only | `@claim` is reported, never matched against | both pass |
| N3 | unmutated tree | the control that says the harness can pass | both pass |

**THE COVER FOUND A COMPILER DEFECT ON ITS FIRST LINUX RUN, AND IT IS NOT IN
EITHER IMPLEMENTATION.** `TOOL-ENCODING-1`'s second half, which the roadmap
called unmeasured and unmeasurable on macOS, and whose corpus census the same row
said nobody had taken. The cover scrubs the environment so both sides are asked
the same question, which means it hands the compiler **no locale at all**; on
Linux that is the POSIX locale, `llmll` decodes `.llmll` source through
`TIO.readFile`, and every one of the 15 fixtures died with

```
hGetContents: invalid argument (cannot decode byte sequence starting from 194)
```

194 is `0xC2`, a UTF-8 lead byte. **The census, now taken: 15 of 15 fixtures hold
non-ASCII bytes** (`§` and `—` in their `@doc` and `@claim` headers), so the
population is not merely non-empty, it is total for that directory.

**What makes it legible as a subject defect rather than a port defect is the
shape of the failure, and this is the cover's design paying off.** Cells 1
through 13 all reported `ok`: both implementations failed, identically, so they
still agreed. What reddened was the **three negative controls**, which require
both sides to PASS an unmutated tree. A battery with mutation cells alone would
have gone green here while the compiler could not read a single fixture.

Pinned back to `C.UTF-8` on both sides, **as a workaround pre-marked for removal**
when `TOOL-ENCODING-1` closes. The pin restores the locale every real consumer
already has (the `Dockerfile` sets the same two variables). The repair that must
NOT be made is dropping the scrubbing: that would trade a measured compiler
defect for an unmeasurable comparison, which is the bug this cover already fixed
once.

Cells 10 and 11 are written as open because their expected answer depends on §8
question 1. **If the port refuses where the reference skips, they become
divergence cells rather than agreement cells**, and the cover must say which it
is asserting. That is the reason the question is asked before the code.

## 7. Retirement

`scripts/doc_claims_gate.sh` is deleted at the release **after** all of:

1. the differential cover green, all cells plus the three negative controls;
2. the port wired into `spec-roundtrip` as a step that decides, adjacent to the
   reference, both running on the same tree in the same run;
3. one full release elapsed in state `oracle`;
4. at least one Linux run behind it, per findings 10 and 12: nothing in this
   campaign is trusted from macOS alone, and this gate spawns subprocesses and
   matches a non-ASCII literal, both of which have platform-shaped failure modes
   already recorded.

Flipping `tool_state` to `retired` and deleting the script happen in **one
commit**, per campaign §4.

## 8. Decisions taken

**Two are NOT taken and are put to the user. They are policy, not
implementation, and deciding them at the keyboard is the failure this workflow
exists to prevent.**

**Question 1: ANSWERED 2026-08-08 by the user. The port reproduces both SKIP
paths faithfully, and the reference's silent success is filed as its own
roadmap row rather than fixed inside a port commit.** The reasoning recorded so
it is not relitigated: a port's job is to REPRODUCE, and the v0.14.91 precedent
points the same way rather than the other way. There the reference already had
the solver preflight and the PORT lacked it, so making them agree meant changing
the port. Here the reference SKIPs, so making them agree means the port SKIPs.
Both are fidelity. Cover cells 10 and 11 are therefore AGREEMENT cells: both
implementations SKIP, and the cover asserts that they agree on skipping rather
than that either decides. The original question follows.

**Question 1 (original): does the port reproduce the reference's two SKIP paths, or refuse?**
The reference exits **0** when it finds no compiler and again when it finds no
fixtures, printing `DRIFT-CT-2 SKIP:`. A port owes the same decisions as its
reference, and campaign §2's retirement rule depends on the two agreeing. But
this is exactly finding 6's class inside the reference: a gate that cannot
decide reports success, and CI would go green with the doc-claim gate asserting
nothing. **The precedent cuts the other way**: v0.14.91 added a solver preflight
to 002's port that REFUSES rather than grading verdicts it cannot decide, and
the reference had grown the same refusal in the same place. Options: (a) port
the SKIPs faithfully and file the behaviour as a separate roadmap row against
the reference; (b) make both refuse, changing the reference in the same commit;
(c) port faithfully and do nothing. **A choice is needed before the cover is
written**, because cells 10 and 11 assert opposite things under (a) and (b).

**Question 2: ANSWERED, and it is settled by the campaign rather than by
taste. FULL grammar: all five bases, the optional `:<substring>` on any of them,
and `@cmd`.** Campaign §2's retirement rule deletes the reference one release
after the port lands. A port implementing less than its reference makes that
deletion a capability regression, and the thin population (`output` has one
fixture, `@cmd` has three) is an argument for the opposite of what it first looks
like: a base with one user is exactly the one a later fixture would reach for and
find missing. The original framing follows, because the reasoning that made it
look like a choice is worth keeping.

**Question 2 (original): how much of the `@expect` grammar does the port implement?**
The reference supports five bases (`check-ok`, `parse-error`, `check-error`,
`warn`, `output`), an optional `:<substring>` on any of them, and an `@cmd`
override. The in-tree population uses all five, but thinly: `output` has ONE
fixture and `@cmd` has three. Options: (a) full grammar, the port being a
drop-in replacement; (b) the population that exists, refusing loudly on an
unimplemented base so a new fixture cannot silently pass. **(b) is smaller and
is how a silent-success defect gets built**, which argues for (a); (a) is more
code for a path with one user. Naming it because a reader could reasonably
choose either and the answer changes the port's size.

**Decisions I have taken, which a reader could have taken otherwise:**

1. **The port lives at `tools/doc-claims/docclaims.llmll`**, matching
   `tools/refute-crux/refutecrux.llmll`, rather than joining an existing tool
   directory. One directory per ported gate keeps `tool_state` checkable against
   the filesystem, which is what the standard's test asserts.
2. **The subject is an explicit `--subject` argument**, not `LLMLL_BIN` from the
   environment as the reference takes it. The reference's environment-variable
   convention is what lets CI pass `stack exec llmll --`, which is the §1 trap.
   An explicit argument also keeps harness and subject separable, which §3
   requires.
3. **The merged capture uses PROC-MERGE-1** rather than reproducing 002's
   two-file read. The reference captures `2>&1` and every criterion here tests
   containment, so the merge is both closer to the reference and simpler. This
   makes 003 the first consumer of a gap 002 filed.
4. **The cover is a new `scripts/doc_claims_cover.py`**, not cells added to an
   existing cover. Covers are per-gate in this campaign and mixing them would
   make a red cell ambiguous about which gate diverged.
