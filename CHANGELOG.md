# CHANGELOG

---

<a id="Latest"></a>

## v0.14.92: the third gate, and two defects the live corpus could not reach (2026-08-08)

**Nothing under `compiler/` moves in this release.** The `llmll` binary, the
JSON-AST schema and the language surface are identical to v0.14.91. What ships
is the TOOL-LL campaign's third port, the differential battery that graded it,
and the CI wiring that makes it decide.

### Added: TOOL-RFC-003, the doc-claim drift gate in LLMLL

[`tools/doc-claims/docclaims.llmll`](tools/doc-claims/docclaims.llmll)
reproduces [`scripts/doc_claims_gate.sh`](scripts/doc_claims_gate.sh): each of
the 15 fixtures in `scripts/doc-claims/` runs through a named compiler, and the
observed verdict is asserted against that fixture's `;; @expect:` header. The
gate exists to catch documentation that has drifted from compiler behaviour,
specifically stale *restriction* claims: a doc saying a program is rejected when
the compiler accepts it, or the reverse.

`tool_state: oracle`. Both implementations run as adjacent steps in
`version-gate.yml`'s `spec-roundtrip` job, over the same tree in the same run,
so a reader compares them without cross-referencing two job logs.

**The `@expect` grammar is implemented in full**: all five bases (`check-ok`,
`parse-error`, `check-error`, `warn`, `output`), the optional `:<substring>` pin
on any of them, and the `@cmd` override. That was a decision rather than a
default. The in-tree population is thin, `output` having one fixture and `@cmd`
three, and a port covering only what exists would be smaller; campaign §2
deletes the reference one release after the port lands, which turns any
shortfall into a capability regression at retirement.

**The port names the compiler it grades explicitly (`--subject`)**, where the
reference takes `LLMLL_BIN` from the environment. CI passes that variable as
`stack exec llmll --`, an idiom that resolves against whatever stack project the
working directory sits in and that once installed GHC 9.10.3 on a runner before
answering "Executable named llmll not found".

Three things this port inherited rather than paid for, all of them bills the
first two ports settled: a job that already builds the compiler and installs jq
and z3 and `fixpoint`; `CAPTURE-ENCODING-1` (v0.14.90), without which the `✅`
its classifier matches reached the running program as `05`; and `PROC-MERGE-1`
(v0.14.91), which is what lets one call reproduce the reference's `2>&1` where
002 had to read two files and concatenate them.

### The cover earned its place on its first run, twice

`scripts/doc_claims_cover.py`: 17 cells and 3 negative controls, every mutant
asserted to fail under **both** implementations before their answers are
compared, because agreement on a passing tree is not evidence. **Two cells found
real defects in the port, and neither was reachable from the live corpus**,
which always names a working compiler and always passes.

- **Cell 5.** The port promoted a `warn` observation on the presence of
  `warning:` alone. The reference promotes it only when the warning **and** the
  pinned substring both match, so a fixture citing a warning the compiler had
  stopped emitting would have passed against any other warning in the output.
- **Cell 11.** The port probed its subject unconditionally and **skipped** where
  the reference **fails**. An explicitly named binary is used as given and never
  second-guessed; only the unnamed path probes. A gate pointed at a compiler
  that does not exist must not report success.

**Two bugs in the cover itself, one of them instructive.** A cell anchored on a
fixture that lacked the header it wanted, caught by the anchor guard that fails
rather than skips. Then the two implementations were given **different
environments**, so the port found an `llmll` on `PATH` that the reference could
not see and the no-compiler cell had one side run the whole corpus while the
other skipped. A differential cover that varies the environment between its two
sides is comparing two worlds, not two implementations.

**What it normalises is blank lines and nothing else.** The port's `console`
harness emits one per step, which is a property of the entry mode rather than of
a verdict. v0.14.90's lesson is why the list stops there: the arrow-normalising
line in `refute_crux_cover.py` hid a real encoding defect for a release. The
port reproduces the reference's `%-30s` and `%-11s` padding so the comparison
can be exact.

**Cell 11 compares the decision only, deliberately.** When the named subject
does not exist, the reference's captured output is bash's own diagnostic text,
which no port can reproduce and none should try to.

### Filed: `SKIP-SILENT-1`, and why it was not fixed here

`doc_claims_gate.sh` exits **0** having asserted nothing in two cases: no
`llmll` can be resolved, and the fixture directory is empty. Both print
`DRIFT-CT-2 SKIP:`. The port reproduces both, on the rule that a port
reproduces its reference and does not improve on it, and the behaviour is filed
as its own roadmap row instead of repaired inside a port commit.

The exposure is bounded and stating the bound is the point: CI names a freshly
built compiler and the fixtures are in the repository, so neither path fires
there. It fires for a developer whose `llmll` is not on `PATH`, who gets a green
gate that read nothing. Cover cells 10 and 11b assert that the two
implementations **agree on skipping**, not that either decides, so closing the
row means changing both in one commit.

`refute-crux-gate.sh` already chose refusal for its solver preflight (v0.14.91),
so the repository is currently inconsistent between two gates about what an
undecidable run should report. That inconsistency is what the row owes an
answer to.

**Tests:** 1666 Haskell, 197 Python, neither moving. What this release adds is a
differential cover and a gate step, both invoked by CI rather than by pytest.

## v0.14.91: two absences, and what the callers did instead (2026-08-08)

Both gaps in this release were filed by the TOOL-LL campaign's second port and
deliberately left open there, because campaign §9 makes the SHAPE of a
`[CT][SPEC]` gap language-team's call and not the porter's. Both are the same
species: an operation the language did not have, whose absence every call site
worked around locally, so nothing in the toolchain could see a defect.

### Added: a scalar element of a JSON array can be read back as a value

`JSON-SCALAR-1`. `json-array` returns `list[Json]`, and every element accessor
took a **key** and read a **field of an object**. No operation read a scalar
`Json` as a value, so `["--strict-verified-core"]` could not be turned back into
a `string` at all.

Four builtins close it, shaped as the field family minus the key:

| | |
|---|---|
| `json-as-string` | `Json → Result[string,string]` |
| `json-as-int` | `Json → Result[int,string]`, strict on `1.0` |
| `json-as-bool` | `Json → Result[bool,string]` |
| `json-as-number` | `Json → Result[string,string]`, the source lexeme |

`json-array` was already a projection of exactly this shape, so this completes a
family that had one member rather than introducing a new kind of operation.
Together the five partition `Json`: no input satisfies two of them.

**`Result`-valued rather than `""`-on-failure, and that is the whole
adjudication.** The entire cost of this defect was that its failure was
indistinguishable from an empty string.

**The mechanism of that silence, corrected while closing the row.** It was
recorded that `(json-get-string x "")` on a scalar *answers* `""`. It does not:
`json-get` on a non-object is `err`, so the accessor is `err` too. The empty
string came from the **caller**. The refute-crux port's `jstr` wraps every field
read in `(unwrap-or ... "")`, a reasonable habit for an absent field, which
turned a type error into a plausible value; the port then invoked its subject
with no flags at all and reported 30 passed / 50 failed, where 50 is exactly the
count of flagged cases. The correction strengthens the row: the defect was not
one builtin answering wrongly, it was a missing operation whose absence every
caller papered over, which is why no gate could see it.

The workaround this forced (`json-serialize`, then strip the quotes it renders)
is deleted from the port. It was also **wrong and not merely verbose**: the
emitted `jsonQuote` escapes every character above `~` as `\uXXXX`, so a flag
carrying a non-ASCII character came back as six literal characters.

### Added: `wasi.proc.run` can merge a child's stdout and stderr

`PROC-MERGE-1`. **Equal path strings mean merge**: one handle, passed to both
`std_out` and `std_err`, which is what a shell's `2>&1` does. The signature does
not change. Passing the same path twice previously opened **two** handles at
position 0 over one file and they wrote over each other, so no working program
can depend on the old behaviour and this repairs a silent corruption rather than
altering a contract.

**The prior question was settled by measurement before the mechanism was
chosen, and it decided the shape. Ordering is not part of the contract and
cannot be.** A merged stream's interleaving is the order the **child** flushes,
not the order it writes: probed directly, a child writing stdout first and
stderr second lands **stderr first**, because stdout is block-buffered when its
fd is a file and stderr is not. A port promising byte-identical excerpts would
have been promising something the child owns.

**The test is string equality, not path identity**, so `"log"` and `"./log"` do
not merge. Canonicalizing would need a syscall against a file that does not
exist yet, and a merge convention that depends on the filesystem's state is
worse than one a reader can settle from the call site.

### Gates: two executed fixtures, each shown to discriminate

Neither defect is visible to a check-only gate: for `JSON-SCALAR-1` the whole
family was absent, and absence type-checks and verifies; for `PROC-MERGE-1` the
signature, the effect label and the response arm are all unchanged. So both
fixtures are **built and run** by `build_smoke.sh`.

`json_scalar.llmll` reads one scalar of each type out of its own single-element
array, and its assertion is the two **refusals** rather than the three values:
`1.5` through `json-as-int` and `7` through `json-as-string` must both be `err`.
`proc_merge.llmll` spawns `/bin/sh` twice, once with equal paths and once with
unequal ones, and asserts containment in both directions; the second run is what
stops an unconditional merge from passing.

**Both gates were mutation-checked rather than assumed to work.** Making the
merge unconditional flips the split control to `OUT=n|ERR=n`; making
`json-as-string` coerce and `json-as-int` narrow flips exactly the two refusal
cells while all three value cells stay correct, which is the measured argument
for why the value cells alone would not have caught either.

### Fixed: the refute-crux port now refuses to grade verdicts it cannot decide

Two implementations of one gate are both declared `oracle`, meaning either is
supposed to answer for the other. On a host without `fixpoint` or z3 they did
not. `llmll verify` exits **3** without a solver ("solver unavailable, the proof
did not run"), and finding 12's fix had gone into the shell reference only, so
the reference refused by name while `refutecrux.llmll` had no preflight at all.

The port now probes `which fixpoint` and `which z3` before reading its first
manifest and refuses with the reference's message and exit 1. The discriminator
is the exit code alone: 0 is found, 1 is `which` running and not finding it, and
127 is the port's score for a spawn failure, which is what happens if `which`
itself is absent. Every non-zero case refuses, so an unusual environment fails
safe. The probe writes to `/dev/null` twice, a path that always exists so the
check cannot fail for a reason unrelated to the solver.

**The pre-fix behaviour was worse than recorded: it DEADLOCKS.** The restart
record predicted the port "would still grade 80 undecidable cases and report
them diverged". Measured against the pre-fix binary with `fixpoint` and z3
hidden and nothing else changed, it stops dead instead: 1882 bytes of output
frozen, 1.11s of CPU not moving across a 90-second sample, sleeping. Reproduced
five times at exactly the same byte count, with stdin from a file and stdout to
a file and the process detached, so it is not the launching harness. A short run
completes normally, which puts the deadlock near step 1882 of the ~1997 a full
run takes: just before the end, with the report never flushed.

So the two `oracle` implementations did not disagree about a number. One refused
by name in under a second and the other hung indefinitely. The deadlock is left
unexplained and is now unreachable through the gate.

**Tests:** 1666 Haskell (from 1656), 197 Python.

## v0.14.90: a handle with no encoding to set (2026-08-08)

### Fixed — a console program could not put a non-ASCII character on its own stdout

`CAPTURE-ENCODING-1`. A string literal survived the compiler intact and the
running program then emitted **the codepoint's low byte**: `→` (U+2192) went out
as `c2 92`, `✔` as `14`, `✅` as `05`, and an astral character as a **NUL**.

**The cause is that `System.Posix.IO.fdToHandle` returns a handle in BINARY
mode, and binary mode is the ABSENCE of a text codec rather than a wrong one.**
That distinction is the whole defect. The emitted `main` already called
`setLocaleEncoding utf8` and pinned `utf8` on all three standard handles, and
the source said in a comment that this "covers the event-log handle and the
createPipe/fdToHandle pair without naming them". The event-log half was right —
`openFile` creates a text handle and the locale reaches it. The pipe half was
false, because there is no codec on a binary handle for a locale to inform.
Measured directly rather than inferred:

```
setLocaleEncoding utf8 ; getLocaleEncoding   -> UTF-8
createPipe >>= fdToHandle >>= hGetEncoding   -> Nothing   (both ends)
... after hSetEncoding h utf8                -> Just UTF-8
```

Fixed by pinning `utf8` on both ends of the capture pipe in `captureStdout`.
Both are required and each was ablated: with only the write end pinned the pipe
carries correct UTF-8 and the unpinned read decodes it as latin-1
(`c3 a2 c2 86 c2 92`); with only the read end pinned the write truncates and the
UTF-8 read rejects the lone continuation byte. **Placement is part of the fix
too, and measured**: the write-end pin must precede `hDuplicateTo writeEnd
stdout`, because the redirect copies that handle onto stdout — moved one line
down it fails with `cannot decode byte sequence starting from 146`, and note it
fails on the READ, so an ordering bug reads as a problem with the other handle.

**Why nothing caught it.** No committed `.llmll` carried a non-ASCII character in
a string literal that reached stdout, so the firing population was zero. The one
encoding fixture the repository had, `fs_encoding.llmll`, uses `§` (U+00A7)
throughout — and **`§` is a fixed point of this bug**: every codepoint below
U+0100 survives truncate → latin-1 → UTF-8 unchanged. That fixture could not have
detected this defect no matter how often it ran.

### Added — a fixture and a gate that can fail

`scripts/build-smoke/capture_encoding.llmll`, run by `build_smoke.sh`, which
compares **bytes** and not characters: the broken output carries control bytes
and a NUL, which shells and terminals mangle in their own ways, so a corrupted
string can match a corrupted pattern. Its five BMP characters are chosen so that
four of them move under the bug and `§` does not, and it emits `string-length`
beside them so a corrupted WRITE is distinguishable from a literal that never
survived the front end. Unlike the `LC_ALL=C` half of stage 5, this stage is
**exercised on every platform** — the defect never depended on the locale.

`scripts/tests/test_codegen_capture_fd.py` gains two source-level pins (both
handles encoded, write-end pin before the redirect) so a regression fails in the
toolchain-free job in milliseconds rather than minutes into the Stack job.

### Changed — two workarounds removed

`refutecrux.llmll` writes a real `→` in its case labels, and
`refute_crux_cover.py`'s matching normalisation is gone: the two
implementations' labels are now **compared** rather than reconciled. Both sites
were marked for exactly this moment. If the truncation ever returns, the port
emits U+0092 and the cover fails — which the normalisation would have hidden.

## v0.14.89: the gate that could not survive its own corpus (2026-08-07)

### Fixed — every generated console program leaked a file descriptor per step

`FD-CAPTURE-1`. `captureStdout` duplicates stdout on every step
(`oldStdout <- hDuplicate stdout`), restores through it, and **never closed it**.
`writeEnd` is closed explicitly and `readEnd` is closed by `hGetContents` at EOF;
the duplicate was reclaimed only when GC happened to finalize the `Handle`, which
is not a bound. Under the non-threaded RTS the program then dies with
`file descriptor NNNN out of range for select (0--1024)` once descriptor numbers
pass `FD_SETSIZE`.

**Nothing in the tree had hit it.** `versiongate.llmll` takes nine steps and the
driver few enough; the first program to need four figures of steps was the first
to find it, and it found it by dying at fd 1103 partway through its corpus.

**The measurement is what makes it a defect rather than a theory.** `lsof` on a
live run showed **139 open write handles to the program's own redirected
stdout**, growing with the run (2 case-directories to 11 descriptors, 29 to 353).
Three isolation probes each survive and so name what it is *not*: 1400
stdout-only steps, 1400 `wasi.fs.copy` steps, and 400 `wasi.proc.run` spawns of
both a trivial binary and the real compiler. The leak is a race between
descriptor creation and finalization that a long console run loses.

The fix is `hClose oldStdout` after the restore, and **the placement is part of
it**: closing before the restore would leave stdout pointing at a closed
descriptor, which no descriptor count would catch. **This changes the emitted
Haskell for every generated `console` program**, which is why this is a bump and
not a patch to a gate.

**The regression test deliberately does not run steps and count.** The defect is
GC-timing dependent, so "N steps and no crash" passes on a broken tree whenever
the collector keeps up. `scripts/tests/test_codegen_capture_fd.py` pins the
emitted source instead: every handle `captureStdout` opens is closed, and the
close follows the restore. Both assertions were checked against the unfixed tree
and fail there.

### Added — TOOL-RFC-002, the refute-crux gate in LLMLL

[`tools/refute-crux/refutecrux.llmll`](tools/refute-crux/refutecrux.llmll)
reproduces all **80 frozen verdicts** across twelve suites and agrees with the
shell reference. `tool_state: oracle`: both now run, as adjacent steps in
`version-gate.yml`'s `spec-roundtrip` job, so the comparison is legible in one
job log.

**The port names the compiler it grades explicitly (`--subject`).** The harness
and the subject are two different binaries, and conflating them is the failure
this gate exists to catch: once the job pulls a published image instead of
building, an implicit subject would be the image's compiler and all 41 refuted
cases would go vacuously green.

`scripts/refute_crux_cover.py` is the differential battery: mutants that must be
caught under **both** implementations before their answers are compared, plus
three negative controls. It compares the ordered per-case decision and the exit
code rather than bytes, because the reference streams and the port emits once;
the weakening is stated rather than glossed.

### Two gaps the RFC's feasibility read missed, and said it had not

Rev 0 of the RFC concluded "nothing here is BLOCKS" and "no new gap was
discovered". **Both were false**, and building the thing is what showed it. The
RFC's §5 keeps the wrong conclusion quoted above the correction rather than
amending it, because the campaign's premise is that porting a gate finds what
reading about it does not.

- **`JSON-SCALAR-1`** (new, OPEN): a bare scalar in a JSON array has no
  accessor. `json-get-string` reads a FIELD of an object, so it answers `""` on
  the scalar `Json` that `json-array` returns. Measured: the port invoked its
  subject with **no flags at all**, and the 50 cases carrying
  `--strict-verified-core` failed while the 30 flagless ones passed. It
  type-checks, it verifies, and no gate sees it.
- **`PROC-MERGE-1`** (new, OPEN): `wasi.proc.run` takes separate stdout and
  stderr paths, so a shell's `2>&1` has no counterpart. No verdict moves, since
  every criterion tests containment; the three-line excerpt under a failing case
  does.

- **`llmll` gains no new command or flag**, and the JSON-AST schema does not
  move.
- The **Makefile** now builds before `refute-crux-gate`. The stale-binary guard
  (finding F-3) moved out of the shell gate to the caller that still needs it,
  so the LLMLL port carries no dependency on a Haskell build system. It is not
  dropped: CI builds before the gate runs.

---

## v0.14.88: the sibling holes the brief called filled, and six gates that had to be found before they could be ported (2026-08-07)

### Fixed — a checkout brief reported every sibling as `filled`, including the ones that were holes

`HOLE-STATUS-SIBLING`, a follow-on to `HOLE-STATUS` (v0.14.21). That fix made the brief tell the
truth about the function whose hole is being checked out; it left every OTHER function reading
`filled` unconditionally. A sibling whose body still holds a hole was therefore presented to a
fill agent as an available callable carrying a discharged contract, and **the brief is the sole
information channel to that agent**. Measured on a three-def fixture, checking out `hole-one`:
`hole-two` read `filled` while genuinely being a hole, indistinguishable from a real one.

`status` becomes three-way: the enclosing function keeps `hole`, a body containing a hole reads the
new **`unfilled`**, everything else stays `filled`. The enclosing function deliberately does NOT
fold into `unfilled`: the brief carries no `enclosing_function` field, so `hole` is its only
identification of the target by name, and collapsing it would destroy a live affordance.

**Unfilled siblings are marked, not withheld.** `refine` deliberately spawns contracted sub-holes
meant to be called before they are filled, and a caller may rely on an unfilled sibling's contract
under assume-guarantee. Withholding would break cascading decomposition.

The predicate is a positive match on `HoleKind`, not a negation of `holeStatus'`: that classifier
ends in a catch-all that collapses `HNamed` into the same bucket as `HProofRequired`, so filtering
on it is a no-op on exactly the holes this ticket is about. That was the first implementation
attempt and it was caught by measuring rather than by reading.

`brief_version` moves to **0.12.3**.

### Added — DRIVER-LL sub-phase 4e

The `def-main` state machine for `wave.llmll`, with tier-4e cover and its documentation closure.

### Added — TOOL-LL, the campaign to port the six CI gates to LLMLL

A standard ([`docs/design/llmll-tooling-campaign.md`](docs/design/llmll-tooling-campaign.md)), an
eight-section RFC template, and a pytest gate that enforces both. Scope, distribution and retirement
are settled; the gap discipline requires every gap to take exactly one of BLOCKS, SHAPES or
COSMETIC, and every SHAPES row to state what the design would have been and cite a roadmap tag.

- **`TOOL-RFC-001`** records the already-shipped version-gate port **retroactively**, and its §8 says
  which decisions that cost: three of four were made at the keyboard and reported afterwards.
- **`TOOL-RFC-002`** is the first port **written before its code**, for the refute-crux gate. Its
  feasibility read found no BLOCKS gap and no new gap. It records a split the first port did not
  have: the harness and the compiler it grades are two different binaries, and conflating them
  would make all 41 refuted cases vacuously green.
- Three previously unknown language defects were filed from the first port: **`MODE-CLI-1`**
  (`:mode cli` emits a pure `print`, so it can neither do IO nor set an exit status),
  **`SPLIT-EMPTY-1`** (`string-split ""` does not terminate, and typechecks, and verifies), and
  **`FS-WALK-1`** (`wasi.fs.list` is flat).

### Fixed — `refute-crux-gate.sh` froze 80 verify verdicts and no workflow ran it

It was a `make` target only, despite its own header calling itself a CI gate. It now runs in
`version-gate.yml`'s `spec-roundtrip` job, which is the Stack-bearing one. **The regression class it
exists to catch was itself uncaught**: refutation of the `tcp_rfc793` and `session-pay` wrong twins
was silently lost for twenty versions (v0.14.12 to v0.14.31, `ENUM-EQ-FALLBACK`) because no gate
froze those verdicts. The gate was then written in response to exactly that, and never wired into a
workflow, so the answer to the incident ran only when someone typed `make`.

Found by applying the campaign's own §1 to the port before any code was written, which is what the
RFC-first order is for.

### Release hygiene — v0.14.84 through v0.14.87 are now tagged and published

Those four releases shipped with **no git tag and no ghcr image**; the newest tag on origin was
`v0.14.83` while all five banner sites read `0.14.87`. `version_gate.sh` compares the banners to
each other and to no tag, so nothing in CI could catch it. The four tags are backfilled from their
release-doc commits, each verified to carry a banner matching its own tag, and each says in its
message that it was tagged after the fact.

- **`llmll` gains no new command or flag**, and the JSON-AST schema does not move: `$id` stays at
  `v0.11` and `schemaVersion` at `0.11.0`.
- The brief's `status` field gains a third value, which is a **behaviour change for any consumer
  that treats it as a two-valued flag**.

---

## v0.14.87: a slice that clamps, and a validator the subject cannot reach into (2026-08-05)

### Fixed — `string-slice` returned the wrong LENGTH, not the wrong offset

`string_slice s from to` was `take (to - from) (drop from s)`. Haskell's `drop` no-ops on a negative
count while `take` does not, so a negative `start` inflated the window instead of shifting it:

- `(string-slice "abc" -1 1)` returned `"ab"`, two characters for a one-character window
- `(string-slice "abc" -3 0)` returned `"abc"`, the whole string for a window ending at zero

Both endpoints now clamp into `[0, string-length s]`. A transposed pair still yields `""`. The
convention is not new: the sibling **`string-char-at`** already returns `""` for negative and
out-of-bounds indices, and this brings the family into agreement. Reachable from ordinary surface
syntax, a program with literal negative starts passes `llmll check` and builds. Nothing in the tree
depended on the old behaviour; the one in-tree caller guards its negative case and is byte-identical
under the clamp. No verification impact: `string-slice` is uninterpreted, and of the string builtins
only `string-length` reaches the SMT layer.

### Fixed — the schema-version rejection cited a file that never existed

`schema-version-mismatch` told users to see `docs/json-ast-versioning.md`. There is no such file and
there never was; old run artifacts under `experiments/cdp-0` have the message frozen, so users did
hit it. Both sites now point at the `description` field of
[`docs/llmll-ast.schema.json`](docs/llmll-ast.schema.json), which is the canonical source rather than
a second one. **`doc_path_lint` cannot catch this class**: it reads prose in tracked markdown, so a
citation compiled into the binary and printed to users is invisible to it. A new test scans the
rejection message for `docs/` paths and asserts each resolves on disk.

### Added — DRIVER-LL sub-phase 4b

Stages B, C and I, and §6's validation obligations as one shared facility. **`verdict-of` takes no
string**, so no subject's filename or byte-count conventions are in scope, and its `[V7-NO-HARDCODE]`
clause states that every present output above the declared floor passes, which refutes a validator
fitted to one run's sizes rather than merely avoiding one. Floors are stage-contract constants. The
cover goes 15 to 31 cells; `[V7-ONLY-TWO]`, `[V7-NO-STOP]` and `[V7-NO-PARTIAL]` **prove** that 4b
constructs exactly two of `Outcome`'s four arms, where the design had asserted it.

- **`llmll` gains no new command or flag**, and the JSON-AST schema does not move.
- **`LLMLL.md` §13.6** documents `string-slice`'s clamp; **§13.9**'s `wasi.http.post` row now points
  at the disclosure that the body is discarded and the command publishes `RErr`.
- Filed and not fixed: **`wasi.proc.run`'s timeout does not fire in a built program**
  (`PROC-TIMEOUT-1`), found by the 4b port.

**Tests:** 1651 Haskell, 131 Python.

---

## v0.14.86: the program wrote the bytes correctly, then died printing them (2026-08-05)

`main` had been red on CI since 2026-08-04, on four gate failures plus a missing file. There was one
defect. `FS-ENCODING-1`, which arrived at v0.14.84, pinned UTF-8 on the two filesystem handles and
left the generated program's **standard** handles on the ambient locale; its acceptance gate reported
PASS throughout that release because the platform it was written on cannot express the condition it
names. A shipped feature was incomplete, and its own gate was structurally unable to say so.

### Fixed, the generated program's standard handles (`FS-ENCODING-1`, second half)

Under `LC_ALL=C` the `fs-encoding` fixture wrote `section § marker` to disk as correct UTF-8 (17
bytes, verified on disk), read it back correctly, and then died printing it:

    <stdout>: hPutChar: invalid argument (cannot encode character '\167')

Steps 3 through 9 never ran. One encode failure on stdout therefore surfaced as four independent gate
failures plus an absent `big.copy`, and the report named **`wasi.fs.copy`, which had not executed at
all**. The same binary under `LC_ALL=C.UTF-8` passes every assertion with matching digests, which is
what identifies the encode as the whole defect rather than one of several. CI run 31035476326.

`main` now moves the locale and pins the standard handles, in both entry modes that run:

    setLocaleEncoding utf8
    hSetEncoding stdin  utf8     -- console only; the cli harness reads no stdin
    hSetEncoding stdout utf8
    hSetEncoding stderr utf8

Both halves are needed and neither substitutes for the other. The RTS creates the three standard
handles before `main` runs, so `setLocaleEncoding` cannot reach them retroactively and each needs its
own explicit pin. In the other direction, GHC's `dupHandle_` rebuilds a duplicate's codec from
`getLocaleEncoding`, so the `hDuplicate` / `hDuplicateTo` pair that `captureStdout` runs three times
per step **reset** stdout's encoding to the locale's whatever the source handle carried; moving the
locale is what makes those duplicates UTF-8, and it covers the event-log handle and the `createPipe`
/ `fdToHandle` pair without enumerating them. Ordering is asserted rather than presence alone: a pin
placed after the first write has already lost the byte it existed to protect, and the locale move has
to precede the event log's `openFile`, whose handle resolves its codec at creation. The fs bodies'
own `hSetEncoding` calls stay, stating the filesystem contract locally.

**This changes the emitted Haskell for every generated `console` and `cli` program, and that is a
behaviour change even though it is a repair.** A program that could previously encode its output in a
non-UTF-8 locale's bytes now writes UTF-8. Under a POSIX locale those writes failed outright, so
nothing that worked stops working; under a locale that could encode them, the bytes on the wire
differ. The `http` mode's `main` is untouched, being a scaffold that ends in `error` and performs no
user IO.

### Changed, the `LC_ALL=C` gate reports NOT EXERCISED where it cannot fail

GHC 9.6.6 on macOS resolves UTF-8 under every value of `LC_ALL`, even where the system's own locale
database says otherwise. Measured 2026-08-05, macOS 25.5.0: `LC_ALL=C locale charmap` reports
`US-ASCII`, and a probe printing `getLocaleEncoding` under the same environment reports `UTF-8`. The
platform cannot express the condition, so the encoding half of `build_smoke.sh` stage 5b is a
structural no-op there. That is not a hypothetical risk: it reported PASS on the developer's machine
for the whole of v0.14.84 while the property it names was false, and failed on the first line it
printed the first time it ran anywhere else.

Every assertion still runs on every platform, the copy and truncation halves being
locale-independent. Only the verdict changes. On Darwin the stage now prints

    BUILD-GATE-1 NOT EXERCISED: the LC_ALL=C encoding claim (FS-ENCODING-1).

and names Linux CI as the only thing that settles the encoding claim, instead of a PASS it has not
earned. The discriminator is the platform rather than a probe, because after the fix the program
behaves identically under both locales by construction, so nothing the fixture can print separates a
working pin from a missing one. Should GHC on macOS ever start honouring `LC_ALL`, the stage
under-claims, which is the safe direction.

### Fixed, `build_smoke.sh` resolved the compiler after changing directory

A second defect, independently blocking, which only stopped recurring because stage 5b failed first.
The replay and DRIVER-LL stages `cd` out of the caller's directory (into the temp `OUTDIR`, and into
`tools/llmll-driver`) and then invoke `$LLMLL_BIN`, and CI sets `LLMLL_BIN="stack exec llmll --"`.
`stack` took the temp directory for its project root and reported `Executable named llmll not found
on path`. `LLMLL_BIN` is now resolved to an absolute binary once, at the top of the script, while the
cwd is still the caller's. It never fired locally because a macOS run already has `llmll` on `PATH`
at an absolute path. It is a separate defect rather than a symptom of the first, proven by A/B in the
container: the fixed codegen with the old script still fails the replay stage with the exact error
the previous release produced.

### Also in this release

- **Verified red to green in Linux, not inferred.** A `haskell:9.6.6` container running the CI
  invocation exactly: the unmodified tree reproduces the failure byte-identically to CI run
  31035476326, down to the `178890` figure, and the final tree passes all six stages.
- **Four new Haskell tests** assert the three pins, the locale move and its import, the ordering
  against the event-log `openFile`, and the `cli` mode's pair. They run everywhere; the end-to-end
  oracle is stage 5b on Linux, and cannot be anything on macOS.
- **A failing `wc -c` no longer leads the stage's own diagnostic.** `wc -c < missing` fails in the
  shell before `wc` runs, so a `2>/dev/null` on `wc` does not suppress it, and the CI output opened
  with a bare `No such file or directory` naming a line number rather than a cause. An absent file
  now reports 0 bytes, which is the fact.
- **Two residues of the same class are recorded and untouched**, filed as `TOOL-ENCODING-1` on the
  roadmap: `llmll replay`'s `CreatePipe` handles and the compiler's own reading of `.llmll` source
  both take locale-derived encodings, and nothing in the tree exercises either. The shipped
  `Dockerfile`'s `LANG=C.UTF-8` is the workaround already in place for the second.
- **`llmll` gains no new command or flag**, and the JSON-AST schema does not move.
- **`LLMLL.md` §13.9** states the pin for the program's standard handles beside the filesystem ones.

**Tests:** 1642 Haskell, 123 Python.

---

## v0.14.85: argv in, status out, and a starved stdin stops reporting success (2026-08-05)

The process boundary DRIVER-LL sub-phase 4a is blocked on: an entry point that both receives the
argument vector and reports a defined terminal status. The two halves are deliberately different
categories, and splitting them on that line is what keeps the whole boundary inside the
auto-discharged verification fragment. Nothing escapes to Lean and nothing is nonlinear.

### Added, `wasi.proc.args` (`PROC-BOUNDARY-1`)

    wasi.proc.args : Command

Nullary, so it is a value rather than a call, the same shape as `wasi.clock.monotonic`. It delivers
the process argument vector on the **existing** `RList` response arm under the **existing**
`ENonDet` effect label, `argv[0]` excluded. **The catalog does not grow**: six effect labels before,
six after, and `Response` gains no sixth arm. The name lands in the `wasi.proc` namespace and CAP-1
matches the namespace rather than the verb, so the `(import wasi.proc (capability exec ...))` clause
a program already writes for `wasi.proc.run` grants this too.

It rides RC-3 rather than moving an entry point's arity: a program issues `wasi.proc.args` as
`:init`'s command and reads the vector as `r0` on its first `:step`. `:init`'s arity does not move,
so every console program shipped to date keeps working. An invocation with no arguments publishes
`RList` with zero entries and **not** `RNone`, on `wasi.fs.list`'s rule: `RNone` is what the response
slot holds when nothing published, so collapsing the two would make "invoked with no arguments"
indistinguishable from "no command published anything".

### Added, `def-main :status` (`PROC-BOUNDARY-1`)

One new optional `def-main` field, a total function from the state type to `int`, applied to the
final state when `:done?` holds; the process then exits with the result. Absent means exit 0, which
is every shipped program's behaviour today, so the field is additive.

| `:done?` | Terminal path | Exit |
|---|---|---|
| declared | it holds | `:status` applied to the final state; **0** when `:status` is absent |
| declared | stdin exhausts first | a fixed **70**; `:status` is **not** consulted |
| not declared | stdin exhausts | **0**, normal termination |

The second row is the defect this closes. The console loop ended at `if eof then return ()`, so a
program whose stdin ran out before it reached its own terminal state wrote partial state and exited
**0**, with no diagnostic of any kind. Measured both ways rather than read off the diff: one fixture,
emitted by the pre-change compiler and by the post-change compiler, same GHC and same inputs, exits
0 then **70** on a starved run and 0 then **42** on a completed one. Before this release a program
had no way to produce 42 at all, which is what made sub-phase 4a's acceptance criterion unmeetable
rather than awkward.

**There is no breaking behaviour change, and the third row is why.** The exhaustion rule is gated on
whether `:done?` is **declared**, not on whether it fired. A program that declares no completion
predicate can never signal completion, so exhaustion is its only terminal path; gating on firing
would have made every run of such a program exit 70, a false alarm on a successful run. A program
with no completion predicate is a stream processor, and for it EOF is the normal end of input rather
than starvation. All three in-tree console programs that declare no `:done?` (`examples/replay-demo`,
`examples/proof_required_test`, `compiler/test/fixtures/pair_type_test`) were built and run, and all
three exit 0 before and after. That is the whole measured population, not a sample. The guarantee
survives exactly where it means anything: **no program that declares a completion predicate can exit
0 without reaching it**, whatever its state type.

**Declare the range yourself; the compiler injects nothing.**

```lisp
(def exit-status [s: RunState] -> int
  (post (and (>= result 0) (<= result 255)))
  ...)
```

POSIX truncates a status to the low 8 bits. With that postcondition the obligation is ground QF-LIA
and liquid-fixpoint discharges it; without it a `:status` returning 300 truncates to 44, and one
returning 256 exits **0 and reports success**. `llmll check` warns when `:status` is declared on a
non-console mode, when it is declared with no `:done?` (the settle path is unreachable, so the
projection is dead code and the author will silently get 0 every run), and when the named function's
return position is not `int`. It does **not** yet warn when that function carries no range
postcondition; that diagnostic is named in the settled design and is the one piece of
`PROC-BOUNDARY-1` still owed.

**70 is not reserved from the program.** A `:status` may return 70 deliberately, so a shell can tell
that neither outcome is success but cannot separate exhaustion from a deliberate 70. Reserving it was
considered and rejected: it buys a distinction nothing currently needs, at the cost of a hole in an
otherwise total 0..255 range.

### Also

- **JSON-AST schema 0.10.0 to 0.11.0**, additive: one optional `status` property on `DefMain`, `$id`
  moved to `/schemas/v0.11/`, nothing removed. `0.10.0` stays in the accepted-versions list, no field
  changed meaning, and a `def-main` without `:status` round-trips byte-identically. A document
  written by the new emitter that reaches an old reader fails on the version constant rather than
  parsing wrongly.
- **A new build gate**, [`scripts/build-smoke/proc_boundary.llmll`](scripts/build-smoke/proc_boundary.llmll),
  built and run: it asserts four exit codes and both argv cases, plus a fifth assertion on
  [`examples/replay-demo/replay-demo.llmll`](examples/replay-demo/replay-demo.llmll), a **shipped**
  program with no `:done?`, which must exit 0. That last one deliberately is not a purpose-built
  fixture: the claim it makes is a no-regression claim about a corpus that predates the change, and
  only a program from that corpus can make it. The `|| true` idiom the neighbouring stages use is
  unavailable here, because the exit code **is** the observation.
- **A pre-existing sibling defect, found by executing rather than by reading**, is filed as
  `DONE-TYPE-1` and deliberately left alone: the `:done?` check compares the whole expression's
  inferred type against `bool` where `:done?` names a *function*, so it warns on every correct
  console program in the corpus. `:status`'s check was written from scratch rather than copied and
  reads the return position instead. Fixing the sibling changes an unrelated diagnostic on every
  console program in the tree, which is its own row and its own release note.
- **`llmll` gains no new command or flag.** The command table is unchanged.
- **`LLMLL.md` §9.5, §12 and §13.9** carry the new surfaces.

**Tests:** 1638 Haskell, 120 Python.

---

## v0.14.84: the bytes the text channel could not carry (2026-08-04)

Two filesystem gaps that DRIVER-LL Phase 4 needed, and the halt distinction the Python driver had
been unable to express.

### Fixed, `wasi.fs.read` / `wasi.fs.write` (`FS-ENCODING-1`)

Both went through `readFile`/`writeFile`, which decode and encode via the ambient locale. Under a
POSIX locale a read of a **valid** UTF-8 file fails on the lead byte, and a write of any non-ASCII
string fails to encode. Both bodies now open the handle explicitly and pin `utf8`, so the byte image
of a read or a write is a property of the program rather than of the shell that launched it.

The design record stated the mechanism wrong and this release corrects it. The claim was that a
decode failure throws inside a `Command` and is therefore a crash-freedom hazard. Nothing throws:
`llmll_publish_io`'s `try` and the existing `evaluate` already made it a value. The defect was
**availability**, a spurious `RErr` on input the program was right about, and the tests are written
against that. A gate asserting the absence of a traceback would have passed before and after.

Measured with a forced ASCII handle encoding, which is what `localeEncoding` yields under `LANG=C`
on Linux. macOS GHC uses UTF-8 regardless of `LC_ALL`, so the simulation is faithful at the encoding
layer and **is not a Linux run**; the new gate below is what will confirm it on CI.

One behaviour change worth naming: a non-UTF-8 locale that *could* encode a string previously wrote
locale bytes and now writes UTF-8. Under a POSIX locale those writes failed outright, so nothing
that worked stops working.

### Added, `wasi.fs.copy` (`FS-COPY-1`)

    wasi.fs.copy : string -> string -> Command

The text channel loses bytes that are not valid UTF-8, so read-then-write cannot express a copy of a
binary artifact at all: `wasi.fs.read` of one returns `RErr` under UTF-8 as much as under any other
encoding. Carries `Caps {EFsRead, EFsWrite}`, exactly what a read-then-write composition already
carries, so no caller's effect row widens by using it, and that is now a test rather than an
argument. No new `Response` arm, no seventh effect label, no new capability namespace, no schema
change.

Known limitation, recorded beside the clause: the label set cannot distinguish an operation that
moves arbitrary bytes from one bounded by the text channel's UTF-8 domain. `Σ_eff` names operation
occurrence, not payload shape, which is the same asymmetry already recorded for `wasi.fs.list`.

### Fixed, the driver's halt channels

`scripts/rfc_to_implementation.py` had two manifest writers and rendered all four `driver-spec` §4
statuses, but only one way to reach them: every `require()` raised `StopCondition`, so a malformed
agent output and a fired gate recorded the same status. §4:135-137 names that as the one confusion
the pipeline cannot afford. Three raising forms now replace one, `require()` defaults to `failed` so
a site added later is wrong only in the safe direction, and both `stopped` forms take the
driver-spec clause as a **required** argument. 37 sites moved; nine stay `stopped` and are
enumerated by clause.

### Also

- **A new build gate, `scripts/build-smoke/fs_encoding.llmll`**, built and run under `LC_ALL=C`. It
  hashes a source and its copy and compares them, which is the only byte-faithfulness check
  expressible from inside the language, and it round-trips a multi-buffer file. The second is not
  decoration: `hGetContents` is lazy and `bracket` closes the handle on the way out, so a force
  placed after the bracket returns truncated contents with no error and publishes a well-formed
  `RText`. Mutation-checked by moving the force: the gate reports "178890 bytes in, 93 out". A short
  string survives that bug.
- **DRIVER-LL Phase 4 is specified**, [`docs/design/driver-ll-phase4-proposal.md`](docs/design/driver-ll-phase4-proposal.md)
  Rev 5. Its §3.6 is the one that changed the code: `stage.record-outcome` proves four `Outcome`
  constructors and the classification rule used two, so the port would have lost `PartialThenHalt`,
  which `driver-spec` §4:146-147 requires for a stage that wrote an artifact and then halted.
- **`llmll` gains no new command or flag.** The command table is unchanged.

**Tests:** 1616 Haskell, 115 Python.

---

## v0.14.83: four stages of the driver, and the replay that could not check them (2026-08-04)

DRIVER-LL Phase 3's porting work finishes. `tools/llmll-driver/spine.llmll` runs stages **E, J, L
and G2** end to end against the committed TFTP execution, with **nine** body-faithful `def`s
carrying the pins as contracts, zero FFI declarations, and every proved core called rather than
reimplemented.

The larger part of this release is not the driver. Writing a program that *is* the driver put
`llmll replay` under load for the first time, and it had misread its own log format since the log
existed.

### Fixed, `llmll replay` (P1-P5)

A turn's wire bytes are `output ++ "\n"`, so an event occupies `count('\n')+1` lines.
`Replay.replayOne` read exactly one.

- **A trailing newline made replay blame the wrong turn.** The event *matched*, because the reader
  stripped the discrepancy; the unconsumed line then desynchronized the stream and the divergence
  was reported against the FOLLOWING event. An oracle that misattributes is worse than one that
  fails. A two-line step replayed 0/2.
- **`actual=` was the constant `"<no output>"`**, so wrong output was indistinguishable from none.
  It now carries what the program wrote, EOF stays distinguishable, and the diagnostic escapes
  newlines so a report stays on one line.
- **Line-count alignment is total by construction.** Zero-newline events read one line as before;
  interior newlines could not strip-match a single line, so they only go mismatch to match;
  trailing-newline events matched before and after and stop leaking a line. No case converts match
  to mismatch, which is why no deprecation path is needed. One test per branch pins that argument
  by name.
- **The settle entry's result kind is `none`, not `stdout`.** RC-4 performs no command
  (`LLMLL.md:1561`), so the old `"stdout"` entry claimed an output never produced and could match
  only when a program happened to print a bare newline. Program stdout bytes are unchanged and old
  logs behave exactly as before.
- **`W-REPLAY-INIT`** warns that `:init`'s output is printed but not logged. The stray line count
  is `count('\n')` in that output, so 0, 1, or unbounded, and "discard one leading line" repairs
  the shifted case while breaking the fused one. The fix is deferred to `REPLAY-INJECT`; it
  reverses a deliberate decision and changes shipped programs' stdout bytes.

**Nothing anywhere ran `llmll replay`**, which is why none of this was caught. `build_smoke.sh`
gains a stage that replays two fixtures and asserts both directions: clean logs replay 2/2, and
logs with every `stdout` value tampered must exit non-zero. Two `Spec.hs` mock fixtures used
framing the emitter does not produce and were passing because `T.strip` hid it; correcting them was
mandatory, not cosmetic.

**Known limit, stated rather than left implicit:** `:on-done`'s output is outside the capture, so a
green `llmll replay` is not evidence that `:on-done` ran. Bringing it inside needs newline-framing
that would change shipped programs' bytes; that trade belongs to `REPLAY-INJECT`.

### Added, DRIVER-LL Phase 3 stages L and G2

- **Stage L** pins exactly one value, because `self_test` pins one: RFC-COV-1's exit status at
  freeze strength. Measured, it exits 0 over 23 root contracts. The 23 and RFC-COV-1's 46/46 and
  15/15 figures are **reported and pinned by nothing**; pinning them would be the port inventing an
  acceptance criterion the original does not have.
- **Stage G2** ports the **strength half only**. The pinned RFCs are deliberately absent from this
  repository, so its citation half cannot be replayed here at all, and porting a check that cannot
  fail is not porting it. The strength half reproduces 124 canonical rows and the three cids whose
  declared strength is absent from their own quote.
- **G2 required a rule Python does not use, and the port owns the divergence.** Python lowercases
  the quote; LLMLL has no `string-lower`, so the port searches the lowercase and uppercase forms.
  These are not the same function: a mixed-case "Must" is found by Python and missed here. Measured
  over the committed census both rules yield the same three cids and title-case variants change
  nothing. That is agreement on one artifact, not equivalence. Without any case handling the check
  yields seven cids rather than three.

### Stage A is a STOP, and Phase 3 closes with it filed

Stage A fetches the RFC over HTTP GET; LLMLL has only `wasi.http.post` (`HTTP-GET-1`). Its fetch is
skippable only `if dest.exists()` and **no RFC source bytes are committed anywhere in this
repository**. `self_test()` carries no stage A block, so it contributes nothing to the acceptance
clause. The campaign's STOP rule prescribes halting and filing the gap rather than taking a
workaround, so **`HTTP-GET-1` is now on the driver's critical path**, which its roadmap row
previously denied.

### Also

- **`spine.llmll` is now in the frozen-verdict gate**, with a stage J refute crux; the driver family
  goes 17 to 19 cases. Neither stage E's nor stage J's verdict had been protected against
  regression, which is the `ENUM-EQ-FALLBACK` shape the gate exists for.
- **Three findings were withdrawn under independent reproduction**, recorded in
  `experiments/rfc-swarm/DRIVER-LL-PORT-FINDINGS.md` with their refutations. In two the observation
  was correct and the mechanism wrong, and in both the wrong mechanism pointed at a fix that would
  have made things worse. One was a claim that higher-order list builtins lack a core gate:
  composing the fallback is already gated on the default path, and five `trustedPrelude` names fall
  back by design, so admission and body-faithfulness were never coupled.
- **`native-json-proposal.md` to Rev 4**, reconciled at fourteen builtins. The settled proposal said
  thirteen; `json-get-number` was re-admitted during implementation because Phase 3's acceptance
  clause reads four floats, and the census that closed the count had measured stages rather than the
  clause that grades them.
- **The Phase 3 acceptance clause now distinguishes a gate's decision from its passing.** Stage J's
  pins reproduce and the gate halts; without the distinction a faithful port reads as a failed one.
- **`doc_path_lint` does not see untracked files**, so a new document's citations are unchecked
  until it is committed. Found the hard way.

---

## v0.14.82: JSON, and the driver that runs on it (2026-08-03)

`JSON-1` closes DRIVER-LL Phase 2, and Phase 3's spine immediately used it to become the first
LLMLL program that *is* the driver rather than a proved fragment of one. Writing that program
found three defects a check-only corpus cannot see, and all three are fixed here.

### Added, JSON-1 (fourteen `def-shell`-only builtins, new §13.13)

A sealed opaque `Json` carrier plus `json-parse`, `json-serialize`, five typed projections
(`json-get` and `-string` / `-int` / `-bool` / `-number`), `json-array`, `json-object`,
`json-set`, and four scalar injections. No JSON-AST schema delta; schema stays 0.10.0.

- **Numbers are stored as source lexemes**, not doubles, so a parsed number round-trips byte for
  byte and a large integer keeps full precision. `json-get-int` is strict on `1.0`: integral
  value, not an integer lexeme. `json-get-number` returns the lexeme, which also keeps a
  comparison against a literal inside `Σ_auto` where a float comparison would not be.
- **Duplicate member names are rejected** per RFC 7493 §2.3, compared after unescaping. RFC 8259
  §4 leaves this to the implementation; rejecting makes `json-set` replace-in-place total, so
  `(json-get (json-set v k x) k)` is `(ok x)` unconditionally.
- **Equality is denied at `Json`.** `=`, `!=`, and `list-contains` are rejected at any argument
  type mentioning `Json`, including `list[Json]` and `Result[Json,string]`. Structural equality
  would make member order observable; compare serializations instead.
- **No new generated-project dependency.** The parser and serializer are hand-rolled in the
  codegen preamble. `aeson` would have added a measured **40 packages** to a generated project's
  closure, against the 46 that dropped `wasi.http.get` at v0.14.81.

### Changed, strict-core admission (closes a claim that was false)

`§4.1` has said the typechecker enforces `def-shell` for functions performing IO via `wasi.*`.
It did not: `checkCalleeAdmissibility` admitted every `builtinEnv` member unconditionally, and a
`def` calling `wasi.fs.read` type-checked clean. CORE-EXCL now covers `wasi.*` alongside
`json-*`, with a new **`core-excluded-builtin`** diagnostic whose remedy is reachable (move the
caller to `def-shell`) rather than impossible (verify a sealed builtin). Blast radius measured
across the whole corpus: **0 of 303** `def`-form functions.

### Added, DRIVER-LL Phase 3 spine

[`tools/llmll-driver/spine.llmll`](tools/llmll-driver/spine.llmll) runs stage E end to end: it
invokes the reconciler through `wasi.proc.run`, reads the artifact through `wasi.fs.read`, parses
it with JSON-1, and discharges `self_test()`'s six pinned values against the committed TFTP
execution. Built and run, not merely type-checked. Zero FFI declarations.

The verdict is eliminative: perturbing a pinned literal flips it from `stage-E=complete` to
`stage-E=stopped`, and `stopped` rather than `failed` is the proved core working — a
non-reproducing pin is `ConditionUnmet`, which `stage.record-outcome`'s verified contract maps to
`Stopped` per driver-spec §4. `stage-e-passes` and `stage-e-outcome` are both body-faithful.

### Fixed, three defects found by writing the driver

- **`XMOD-CTOR-1`.** A sum-type constructor imported via `(import m) (open m)` worked in *pattern*
  position but was unbound as an *expression* — a warning at `check`, an **error** at `verify`.
  Patterns read the constructor set off the scrutinee's `TSumType`, which `meAliasMap` carries
  cross-module; expressions resolve against the value env, which `seedCacheEnv` builds from
  `meExports`, and `buildModuleEnv` never emitted constructors. An importer could match an
  imported sum but not construct one, which is exactly what calling a proved core taking an
  `Outcome` requires.
- **`RESULT-CTOR-COLLIDE`.** `CodegenHs.rewriteCtor` rewrites any constructor named `Success` or
  `Error` to `Right` or `Left` unconditionally, with no knowledge of the declaring type, because
  `Result[t,e]` emits as `Either e t`. `tools/llmll-driver/stage.llmll` declared `(| Error)` and
  had type-checked **and verified** in that state since July; it emitted `Left` with no argument
  and GHC refused it. Nothing had ever built it. Now a check-time `reserved-constructor-name`
  error instead of a silent miscompile; the constructor is renamed `Errored` and its refute-crux
  twin still refutes.
- **`STRLIT-BODY-1`** (documented, not fixed). A `def` whose *body* performs a string-literal
  comparison falls back to `contract-checked` whatever its contract says; §5.3.5's STRLIT
  reflection covers contract-position predicates, not the body's own comparison. This narrows
  what any proved centre can cover and is recorded in the spine's source rather than hidden.

**Tests:** 1594 Haskell, 107 Python.

---

## v0.14.81: four capability operations, and a gate that runs them (2026-08-03)

CAP-PROC reaches five operations and closes there. Phase 2's remaining four ship with an execution
stage on BUILD-GATE-1: the gate no longer stops at "it compiled" but runs the generated binary and
checks its output against known answers. That stage paid for itself on first use. **One breaking
change for report consumers:** the effect label `random` is renamed `nondet`.

### Added, CAP-PROC (four operations; the row closes at five)

`wasi.fs.mkdir : string -> Command`, `wasi.fs.sha256 : string -> Command`,
`wasi.clock.monotonic : Command`, and
`wasi.proc.run : string list[string] string string string int -> Command`. None needed a new
`Response` arm, which was Phase 1's prediction and is now measured: `mkdir` delivers `RNone`,
`sha256` a lowercase hex digest as `RText`, `monotonic` nanoseconds as `RCode`, and `proc.run` the
child's exit status as `RCode`.

- **`wasi.proc.run` reports `unbounded`, by design.** It runs an arbitrary program, so a bounded
  label would be unsound rather than imprecise: `EffectSummary` is a may-over-approximation, and an
  "EProc" label would claim the function may spawn and may not write files while the child may.
- **It takes an executable and an argument vector, never a shell string**, so there is no
  quoting-dependent injection surface. Authority delivered through argv is unbounded.
- **`wasi.fs.sha256` takes a path, not bytes.** `wasi.fs.read` fails closed on binary input, so
  composing it with a pure hash cannot mis-hash a binary file; it cannot read one at all.
- **`wasi.http.get` is dropped, not deferred, and CAP-PROC closes at five.** Two independent
  grounds. Its Phase 1 arm mapping is `RText`, which cannot reproduce the driver's intake stage,
  since that writes bytes and hashes the file, and an `RText` round trip is not byte-faithful. And
  `http-client` plus `http-client-tls` moves a generated project's dependency closure from **33
  packages to 79**, none of them compiler dependencies, so CI's snapshot cache misses. Refiled as
  `HTTP-GET-1`, signature and atomicity clause already settled.

### Changed, effect labels (breaking for report consumers)

`ERandom` is renamed `ENonDet` and its serialized string moves from `random` to `nondet`. Any
consumer keyed on the old string must move. `wasi.clock.monotonic` is now its only producer.

### Added, BUILD-GATE-1 execution stage

`scripts/build_smoke.sh` gains a fixture that is built **and run**, output checked against known
answers.

- **It caught a defect on first use.** Against a missing executable, `createProcess` throws and
  `RErr` is correct, but two redirect handles leaked still-open, and the **next** `wasi.fs.read` of
  that path returned `resource busy (file is locked)`: a failed spawn corrupted a later read. Fixed
  with `onException` guards, pinned by `CP-17`. No compile-only check could have seen it.

### Fixed, R-13

`random-int` held a `trustedPrelude` entry, a `primEffect` clause and a codegen stub returning `42`,
and had no `builtinEnv` declaration. The `trustedPrelude` entry suppressed the core-membership error
a call would otherwise get, so `llmll check` reported `OK` with an unknown-function warning while
`llmll verify` errored: an agent running `check` saw a usable function that does not exist. Being
undeclared it also had no arity, so `(random-int lo hi)` was accepted against a nullary stub.

- **No soundness hole, no trust-closure change.** `verify` rejects a call in every mode, so no
  function carrying one received a tier, and the `primEffect` clause classified an effect no
  reachable program could have.
- Both tests pinning the removed sites were **retargeted rather than deleted**, each being
  discriminating. `INV-C3` demonstrated `trustedPrelude` membership suppressing the error and now
  covers the undeclared-callee path, which nothing tested. `CP-8` asserted the shared label and now
  guards the removal; the label stays covered by `CP-7`.
- `LLMLL.md §5.2`'s note stated the membership and the stub in the present tense, and is corrected.

**Tests:** 1566 Haskell examples, 0 failures (+22); 107 Python.

Design: [`docs/design/driver-in-llmll-campaign.md`](docs/design/driver-in-llmll-campaign.md) §3 Phase 2.
Open work carried past this release, including the four residues this release named, is recorded in
[`docs/design/driver-ll-open-work.md`](docs/design/driver-ll-open-work.md).

---

## v0.14.80: an effect returns a value the program can branch on (2026-08-03)

DRIVER-LL Phases 0 and 1, in three commits. Until this release a `Command` was nullary: a program
could perform an effect and could not observe its result, so `wasi.fs.read` read a file that nothing
downstream could see. A console `:step` now receives a `Response` carrying what the previous command
produced, which is the property a driver cannot be written without. **Two breaking changes**, taken
together rather than in two releases: the JSON-AST schema moves **0.9.0 to 0.10.0**, and every
console `:step` gains a third parameter.

### Changed, DISCARD-1 (breaking)

A non-final `do` step whose `Command` is dropped must now say so with a `(discard ...)` marker;
`checkDiscardedCommand` is promoted from warning to error, gated on the marker. The marker on a final
step is rejected, since a final step's command is the block's result and is never dropped. `:read` is
retired from `def-main`.

- **JSON-AST schema 0.9.0 to 0.10.0**, with `$id` moved to `/schemas/v0.10/` in the same commit.
- The re-scope from plain `P0-error` to `P0-marker` was user-adjudicated twice. The first adjudication
  was put on a mis-described option (it cited a `seq-commands` escape hatch that is not reachable from
  a `do`-step) and was re-put.

### Added, EFFECT-RESP (breaking)

A console `:step` takes `(state, input: string, response: Response)` and returns `(state, Command)`.
`Response` has five arms: `RNone`, `RText string`, `RCode int`, `RErr string`, `RList list[string]`.

- **RC-1, one response per performed command.** `performStep` clears the response slot before
  performing and reads it after, so a step receives its own command's response and never a stale one.
- **RC-2, `seq-commands` is discard-left.** `(seq-commands a b)` yields `b`'s response; `a`'s is
  overwritten. This follows from the `Command` monoid's `a >> b` and needed no code.
- **RC-3, `:init` supplies the first response.** There is no special initial case; init's command is
  performed through the same path, and its output is not logged, as it was not before.
- **RC-4, the terminating step's command is not performed.** `done?` is evaluated on the state a step
  produced, so the step that ends the loop contributes no effect. **This changes observable output for
  programs that rendered from the terminating step:** `examples/hangman_sexp` emits twelve fewer lines
  on identical stdin, losing the final board while `:on-done` still fires. The repair is to render
  from `:on-done`, which is the pattern RC-4 mandates. The four game examples are not yet repaired.
- **`wasi.fs.read` returns contents as `RText`** and IO failure as `RErr` rather than raising.
- Twelve programs migrated, six `.llmll` and six `.ast.json`. The migration's only diagnostic is the
  new `def-main-step-arity` check, which fires on a two-parameter step, a one-parameter step, and a
  wrong third type.
- The trust report gains `harness_assumptions`. No `trust_report_version` bump.
- **Σ_auto is unchanged.** All 151 corpus `.fq` files are byte-identical against a pre-EFFECT-RESP
  compiler, including the twelve migrated programs, whose step functions already fell back on
  `Command`. This was the campaign's Phase 1 STOP condition and it is cleared by measurement.

### Added, CAP-PROC (first of six operations)

`wasi.fs.list : string -> Command`, with `RList list[string]` as its response arm. Output is sorted,
an empty directory yields `RList` with zero entries rather than `RNone`, and a missing directory
yields `RErr`. It shares the `EFsRead` effect label rather than widening the closed six-label
catalog, so `Response` is now strictly finer than `Σ_eff`: the arm set distinguishes `RText` from
`RList` while both producers map to `fs.read`. Not a soundness defect (`effect_summary` is scoped
informational and orthogonal to trust, `LLMLL.md §11.2`), recorded so it is not rediscovered.

The arm set is settled under a four-part admissibility rule, so a later operation needing an arm that
*fails* the rule is a design error rather than ordinary alphabet growth.

### Fixed, spec disclosure

- **`LLMLL.md §13.9`'s v0.14.79 note was inverted by this release.** It said a `Command` "carries an
  effect, never a result", that `wasi.fs.read`'s contents are "not reachable from the program", and
  that "a program cannot branch on what it read". All three are now false for console programs.
  Rewritten rather than appended to.
- **Four capability claims were never true.** `checkWasiCapability`
  ([`TypeCheck.hs:1543-1553`](compiler/src/LLMLL/TypeCheck.hs)) tests `importPath imp == ns` and never
  reads `importCapability`, so a bare `(import wasi.fs)` with no clause authorizes every `wasi.fs.*`
  call, and the granted verb and path are decorative: `(capability read "/tmp")` already authorizes
  `wasi.fs.delete` and a write to any path. `LLMLL.md` claimed enforcement at four places, including
  "the principle of least authority" and a runtime `CapabilityError`; `CodegenHs` contains zero
  capability references. Corrected to describe the property that holds, namespace membership, and to
  name the gap. **Docs only in this release.** The design question, whether LLMLL wants
  object-capabilities or has module-scoped effect-namespace declarations, is filed as `CAP-1-REAL`.

**Tests:** 1544 Haskell examples, 0 failures (+55); 107 Python.

Design: [`docs/design/effect-response-channel-proposal.md`](docs/design/effect-response-channel-proposal.md)
(Rev 5, arm set settled) and [`docs/design/driver-in-llmll-campaign.md`](docs/design/driver-in-llmll-campaign.md)
(Rev 4). Open work carried past this release, including two findings that do not close with it, is
recorded in [`docs/design/driver-ll-open-work.md`](docs/design/driver-ll-open-work.md).

---

## v0.14.79: four declared builtins get runtimes, and the tree builds in CI for the first time (2026-08-02)

WASI-RT and BUILD-GATE-1, the first two items of the DRIVER-LL campaign. `builtinEnv` declared seven
`wasi.*` names and the codegen preamble defined three; a program calling any of the other four passed
`llmll check` and died at GHC. The defect survived because **nothing in this repository ever ran
`llmll build`**: the corpus was a check-only corpus, and three independent defects of the shape
"typechecks clean, fails at GHC" were found in this seam within one release. Codegen and CI edits
only. No schema change, no grammar change, no builtin-signature change, no `checker_soundness_version`
bump.

### Added, WASI-RT

- **`wasi.fs.read`, `wasi.fs.write`, `wasi.fs.delete` and `wasi.http.post` now have runtimes.**
  Four definitions beside the three that existed, plus `System.Directory (doesFileExist, removeFile)`
  and `Control.Monad (when)` in the generated import block and `hPutStrLn` added to the `System.IO`
  import. Generated projects gain a `directory` dependency, a GHC boot package already in the
  compiler's own dependency set, so no resolver movement.
- **`wasi.fs.delete` is idempotent rather than failing on a missing path.** `removeFile` throws on a
  path that is not there, and an uncaught exception inside a `Command` breaks the crash-freedom
  property §10 relies on. The `doesFileExist` guard is TOCTOU-racy under concurrency; the console
  harness is a single-threaded loop, so the imprecision is recorded rather than paid for.
- **`wasi.fs.read` performs the read and discards the result.** `Command` is `IO ()` and carries no
  return channel until EFFECT-RESP lands, so this stage makes the capability real (a declared
  capability over an unreadable path now fails at run time) without pretending to be a read. The body
  forces with `evaluate . length` for a reason worth stating: `readFile` is lazy, so
  `readFile p >> return ()` performs no read at all. It would compile, run, raise nothing on an
  unreadable path, and pass every string-shape test. That is the one place in the block where subtly
  wrong Haskell yields a definition that does nothing, and it is pinned by a test.
- **`wasi.http.post` is a diagnosed stub, not an error and not a silent success.** A real body needs
  `http-client` plus TLS in every generated project for a builtin with zero in-tree call sites.
  `error` would break the same crash-freedom property as delete; a silent no-op would let a program
  believe it posted. It is diagnosed twice instead: `stmtWarnings` (previously a `_ -> []` stub) emits
  a codegen warning, and the body writes to stderr at run time.

### Added, BUILD-GATE-1

- **`scripts/build_smoke.sh` compiles a fixture end to end through GHC on every CI run**, wired into
  the `spec-roundtrip` job, which already has a warm Stack cache. It is affordable there because
  generated projects pin the same resolver as the compiler (`lts-22.43`). The fast `version-gate` job
  is deliberately Stack-free and was not touched.
- **The gate does not trust `llmll build`'s exit code alone.** `runGhcCheck` returns success when
  neither `stack` nor `ghc` is on PATH, so a gate reading only the exit code would go green in any
  environment without a toolchain while observing nothing. It fails closed on a missing toolchain
  rather than skipping, asserts every expected `wasi_*` name is defined in the emitted `src/Lib.hs`,
  and asserts the log shows a real GHC invocation.
- **Acceptance was a positive witness, both sides.** The gate was demonstrated red against a pre-fix
  compiler (six `GHC-88464` "Variable not in scope" errors) and green after. A gate that passes on
  both sides of its patch has not been shown to observe anything, which is how four missing
  definitions survived since `builtinEnv` last grew.
- **The completeness test folds over `builtinEnv` rather than listing seven cases**, so adding an
  eighth `wasi.*` builtin without a preamble definition fails the suite. That is the regression that
  would have caught this four names ago.

### Fixed, CI

`gh run list --branch main` showed the version-gate workflow failing on the **last six commits**,
spanning the v0.14.76, v0.14.77 and v0.14.78 releases. Two pytest failures, both of which pass
locally and fail on the runner, which is why they survived three releases.

- **`rfc_to_implementation.self_test()` raised instead of skipping.** Its RFC-COV-1 section prints
  "llmll not on PATH" as its skip reason, but as written that branch only fired when `llmll` **ran**
  and printed something that was not JSON: an absent binary raises `FileNotFoundError` out of
  `subprocess.run` first, so the one case the message named was the one case it did not handle. The
  fast CI job installs no Stack and no `llmll`, which is exactly that configuration. Resolved with
  `shutil.which` before running, and the two skip reasons are now distinguishable. This is not
  cosmetic for DRIVER-LL: `self_test()` is the campaign's Phase 3 boundary gate, and Phase 3
  acceptance requires the LLMLL driver to reproduce its oracle.
- **DRIFT-DOC-4 had eight unresolved prose path citations.** Six `ALLOW` entries added, each stating
  why. Three are `docs/`-relative citations inside the campaign doc's staged roadmap-delta table,
  whose rows were authored to be pasted into `docs/compiler-team-roadmap.md` (where they resolve) and
  are preserved unedited so the staging step stays auditable; one is a forward reference to a fixture
  the DISCARD-1 commit creates, carrying a delete-this-row note for when that lands; two are paths
  gitignored by construction.
- **`test_every_entry_has_a_comment` asserted the opposite of its own message.** It read
  `len(entries) >= len(comments)` against a failure message saying "more comments than entries is
  fine; zero comments is not", so it failed a well-justified `ALLOW` table and passed a thinly
  justified one. It went unnoticed only because the table carried terse one-line comments; adding six
  properly explained entries surfaced it. Replaced with a group-aware check matching the class
  docstring.

**Tests:** 1489 Haskell examples, 0 failures (+14); 107 Python. Verified in the CI configuration
rather than only locally: a fresh worktree at HEAD with no `llmll` on PATH under Python 3.11 runs 107
Python tests green with DRIFT-DOC-4 reporting all citations resolved.

Design: [`docs/design/driver-in-llmll-campaign.md`](docs/design/driver-in-llmll-campaign.md) (Rev 3,
§8.3 settles BUILD-GATE-1 into this commit) and
[`docs/design/effect-response-channel-proposal.md`](docs/design/effect-response-channel-proposal.md)
(Rev 4). WASI-RT is a hard prerequisite of EFFECT-RESP, which is not in this release.

## v0.14.78: the bytes[n] length is earned at every position, and the line closes (2026-08-01)

FACT-AG-LEN **Stage 3 of 3**, the return position, and **the line is closed**: no `bytes[n]` length
now enters a VC antecedent from a declaration without an obligation discharging it. Emitter and
type-checker edits plus test and fixture surface. No schema change, no grammar change, no
builtin-signature change, no `checker_soundness_version` bump.

### Changed, FACT-AG-LEN Stage 3

- **A body now proves its own result length instead of assuming it.** `bytesLenRetPost` is the
  symmetric twin of Stage 1's `bytesLenParamPre`: it conjoins `bytesLen(result) = n` into
  `returnRefinementPost`, so `augmentContractPost` folds the length into the effective post and the
  body VC carries it as a goal rather than as an antecedent. `resultLenFact` is **deleted** from
  `lhsPred`, which was the half that made it an antecedent. Callers lose nothing: they recover the
  length as an assumed post through the existing assume-guarantee step (§5.3.4), which is the same
  channel a hand-written `post` uses.
- **The length is now earned at every position it can occupy.** Parameter into the effective pre
  (Stage 1, v0.14.76), construction by the `(bytes-zero)` constructor axiom (Stage 2, v0.14.77),
  return into the effective post (this release). `bytesLenReft` is deleted along with `resultLenFact`;
  Stage 1 had already moved its sort role into `emitParamBind`'s own `bytesLenOf` case, so the
  deletion is textual.
- **`admits` narrows to `boolValuedMapTy`, which is where it lands and not where it pauses.**
  `LLMLL.TypeAdmissibility`'s module header claimed the predicate's principled terminal state was the
  EMPTY predicate, reached by routing every type-derived fact through assume-guarantee. That claim is
  withdrawn here. The `map[k,bool]` value range is established by the sealed `map-empty` / `map-put`
  constructors and is uniform over the type constructor's inhabitants rather than parametric in an
  index, so there is nothing to earn and nothing to export. The bytes arm leaves; the map arm stays,
  permanently, and no peer row is opened for it.
- **`admits` and the WILD-ASSUME seams could not stay one predicate.** The settled design asked for
  two things that are jointly unsatisfiable while the seams read `admits`: that `admits` lose
  `bytesLenOf`, and that both `TypeCheck` seams keep rejecting a bare `?` at a `bytes[n]` position.
  Dropping the arm from a shared predicate makes the seams stop firing. The split is `admits` = the
  **soundness** set, exactly what the emitter injects unearned, now `boolValuedMapTy` alone, and a new
  exported `wildAssumeRejects` = the **diagnostic** set, `admits` plus the bytes arm. The containment
  `admits ⟹ wildAssumeRejects` holds **by construction**, since the latter is defined as the former
  disjoined with `bytesLenOf`, rather than being asserted as a property over the two. There is a
  **third** `admits` call site the design named as two: `unify` re-tests the predicate to choose which
  diagnostic to emit after `compatibleWith` has already rejected, so it is a router rather than a
  guard and had to move in step or degrade a rejection to the generic mismatch message.
- **The rejection message says which of the two things it is refusing.** `wildAssumeFactNoun` now
  carries a verb per arm, because the two facts reach the solver by different routes: a `bytes[n]`
  position carries "a length the verifier must prove at this position", a `map[k,bool]` position "a
  per-key value range that the verifier asserts from the declaration". One shared verb would have to
  be wrong about one of them.

### Fixed

- **A contract-free `bytes[n]`-returning callee crashed the solver instead of returning a verdict,
  and Stage 3 empties that class.** `calleeRetSort` sorts a bytes callee's result binder at
  `byteArraySort` only when the callee's **stored contract** mentions a bytes op, so a callee with no
  contract at all bound its call result at `FQInt`, and a gated caller applying `bytesLen` to it
  failed liquid-fixpoint on "The sort (Map_t int int) is not numeric". No revision of the design
  predicted this. Stage 3 empties the population as a side effect, because every `bytes[n]` return
  now carries `bytes-length` in its augmented post, and the `FQInt` fall-through on the `TBytes` arm
  becomes dead (named in place, not removed). Both new fixtures,
  `examples/bytes-bounds/relay-buffer.llmll` and `relay-overflow.llmll`, were `SOLVER-CRASH` at
  Stage 2 and are SAFE / REFUTED here.
- **Contract-free `bytes[n]`-returning functions become body-faithful and verifiable.** This is the
  user-visible capability the whole line existed to enable: a `bytes[n]` return now has a post to
  prove even when the author wrote no `post` clause, so `(def mk32 [] -> bytes[32] (bytes-zero))` and
  a `bytes-set`-bodied writer move from `body-fallback` to `body-faithful`, and their trust tier moves
  from "no contract" to `verified`. Composition across a function boundary is what Stage 2 could not
  reach and Stage 3 does.

### Not in this release

**The class is NOT closed for recursive `bytes[n]`-returning functions.** A self-recursive `def` or
`def-shell` with a declared `bytes[n]` return keeps its post on the assumption channel at tier
`asserted`, exactly as the design's edge case 10 predicts. Separately, `letrec` cannot reach the class
at all, because both parsers hardcode `SLetrec`'s return type to `Nothing` (`Parser.hs:200`,
`ParserJSON.hs:343`), so the only route in is a self-recursive `def` / `def-shell`.

**The identity function on bytes still cannot prove its own length.** `bodyToPredM`'s variable clause
admits `FQInt`, `FQBool` and `FQStr` only, so a bare array-sorted variable as a whole body yields no
`BodyVC` and the function falls back before the effective post is considered. Measured identical at
Stage 2, so this is a pre-existing body-VC fragment boundary and not a regression introduced here.
It is the one shape in the bytes population whose post rides the assumption channel; every other
shape (a `bytes-zero` body, a `bytes-set` body, a call tail) is body-faithful.

**An evidence-hash asymmetry stands, owed by Stage 1's ceremony rather than this one.** The hash
preimage is `(formTag, body, RAW pre, AUGMENTED post, decreases)` on both the write and the read side,
so Stage 1's **pre** augmentation moved no hash at v0.14.76. A caller that gained a call-site length
obligation there, without a bytes type of its own, therefore keeps a `verified` sidecar written by
v0.14.73 through v0.14.75, and that obligation can turn SAFE into REFUTED. In-tree the population is
**empty** (Rev 3 measured it as zero on both halves), so nothing in the corpus is affected. Tracked as
**HASH-PRE-ASYM** on the roadmap.

**TRUST-AXIOM is untouched.** Stage 2's constructor axiom and `bytes-set`'s preservation lemma still
appear on no channel of the trust report. Stage 3 neither creates nor closes that silence.

### Gates

**Stage 3's gate is the corpus sweep with a declared delta set, not verdict-identity.** Stage 2's gate
was verdict-identity because the same fact reached the solver twice; Stage 3 removes the constraint-LHS
copy, so verdicts may legitimately move. Sweep: **252 files, 250 verdict-identical**. The two that
changed are the two fixtures this release adds, and both were `SOLVER-CRASH` at Stage 2. **No
pre-existing file moved, in either direction.**

**A green 250/252 does not stand alone here.** Before these fixtures landed, `examples/` held no
bytes-composition program and no bytes-construction program, so the sweep is a regression check over a
corpus that mostly does not exercise this change. The real witness set for Stage 3 is the two new
fixtures plus `compiler/test/Spec.hs`.

**No `checker_soundness_version` bump, and the reason differs from Stage 1's and Stage 2's.** The
stamp discards sidecars **wholesale**. SAFE-ARG spent it because its affected population was not
identifiable per function; here it is, and the identification is already wired.
`canonicalDefEvidenceHash` folds `augmentContractPost` on both the write side (`Main.hs:1531`) and the
read side (`TrustReport.hs:586`), so every `bytes[n]`-returning function's hash moves and
`downgradeStaleVerifiedSidecar` downgrades exactly that entry. Measured: `zeros8`'s `verified_hash`
moves from `sha256:1ec9910e…` to `sha256:afdc70c4…`. The population whose hash does **not** move is the
population with no `bytes[n]` return, and for it a stale `verified` can only be conservative: a caller
of a bytes-returning function gains an assumption and keeps its goal, so a Stage-2 SAFE stays SAFE,
while a Stage-2 REFUTED or CRASH wrote no `verified` sidecar to begin with. A bump would invalidate
every unaffected sidecar in every user environment for no soundness gain.

`scripts/refute-crux-gate.sh` goes from 59 to **61 cases, 0 failed**; the `bytes-bounds` family is now
six cases. `scripts/check-examples.sh` reports **165 passed, 1 failed**. The single failure
(`examples/totp_rfc6238/totp_filled.ast.json`) is the pre-existing v0.14.73 rejection recorded under
§v0.14.74, unrelated to this change; its message is reworded here, and now reads `A bytes[20] value
carries a length the verifier must prove at this position, and inference cannot supply it; annotate
the callee's return type.`

### Tests

**1463 → 1475.** The additions pin the four things that could each be wrong on their own: that the
length reaches the effective post and not the constraint LHS, that `resultLenFact` is gone rather than
shadowed, that `wildAssumeRejects` contains `admits` at both seams while `admits` no longer contains
the bytes arm, and that a contract-free bytes-returning callee now sorts array-wise at the call site.

### Spec

- **§5.3.3's bytes-length clause closes.** It previously recorded the return half as still asserted
  from the declared type onto the constraint LHS and discharged by no obligation, ending on the
  sentence that named Stage 3 as the fix. The length is now earned at all three positions, and
  `resultLenFact` no longer exists. The `map[k,bool]` value-range fact keeps its
  asserted-and-unearned reading, permanently, and the reason is unchanged. The section also records
  the new capability: a `bytes[n]`-returning function is body-faithful and verifiable with **no**
  hand-written contract, since its return type alone now supplies a post to prove. Two reflection
  lines that described `bytesLen(b) = n` as a ground per-binder fact (§5.3.3's operation list and
  §5.3.5's `EApp` row) are corrected to say the equation is earned per position; the reflection of
  `bytes-length` itself is unchanged.
- **§3.4.6's WILD-ASSUME paragraph loses its soundness half on the bytes arm.** The whole bytes arm
  is now a diagnostic: it rejects a bare `?` at a `bytes[n]` position to produce a type error naming
  the remedy instead of a refuted obligation or an unlocalized fallback. The section records that the
  predicate backing the restriction is `wildAssumeRejects`, distinct from the soundness predicate
  `admits`, and why the two differ. The `map[k,bool]` arm remains a genuine soundness claim, so the
  section still has one.

Design: [`docs/design/fact-ag-proposal.md`](docs/design/fact-ag-proposal.md) (Rev 4, SETTLED and
COMPLETE), whose professor review is folded into that file's review-log appendix and archived to
[`docs/archive/professor-reviews/fact-ag-proposal-review.md`](docs/archive/professor-reviews/fact-ag-proposal-review.md)
under DOC-CONSOLIDATE §M2.

## v0.14.77: the bytes constructor establishes its own length instead of borrowing it (2026-08-01)

FACT-AG-LEN **Stage 2 of 3**, the `(bytes-zero)` constructor axiom. Two emitter edits plus test and
fixture surface. No schema change, no grammar change, no builtin-signature change, no
`checker_soundness_version` bump.

### Changed, FACT-AG-LEN Stage 2

- **The language's only bytes constructor now establishes its own length.** `(bytes-zero)` translates
  to `Map_default(0)`, a total function in the array theory that carries no length, so `bytesLen`
  applied to it is uninterpreted and a constructed buffer's length came entirely from `resultLenFact`
  on the constraint LHS. A new `bodyToPredM` equation emits it as an axiom instead: a `CallVC` with
  `cvPreObligation = Nothing` and `cvPostAssumption = Just (r = Map_default(0) and bytesLen(r) = n)`.
  ASSUME polarity with no PROVE side is what an axiom is, and the data type already separates the two
  by that `Nothing`. `bytes-set`'s length-preservation fact is the shipped precedent for the shape;
  `SimpleVC` cannot carry it, since its first field is `[LetBinding]` and yields only `r = rhs` with
  no seam for a free-standing fact.
- **Reify, then match, because `bodyToPredM` cannot see the return type.** That function receives
  neither an `AliasMap` nor an `mRet`, and threading `mRet` through forty-odd clauses to serve one
  call site is not the shape of this change. New `reifyBytesZeroLen` rewrites a whole-body
  `(bytes-zero)` to carry its declared length as a literal argument, applied at the `body'` seam where
  `mRet` is already read. It deliberately mirrors `Contracts.buildFuncEnv`'s `reifyBytesLen`, which
  performs the same rewrite for the `llmll test` symbolic evaluator: two reifications, one match
  shape, two consumers, and each site now carries a TWIN comment naming the other.
- **The match is head-syntactic on `TBytes n`, deliberately not through `bytesLenOf`.** The checker's
  determining-context rule (`TypeCheck.hs:1216`, `:1250`) and codegen (`CodegenHs.hs:586`) both match
  that way. Chasing aliases here would let the emitter admit a construct the checker rejects.
- **The axiom does real work rather than restating an antecedent already present.** Measured: delete
  `resultLenFact` from `lhsPred` without adding the axiom, rebuild at v0.14.76, and
  `(def zeros8 [] -> bytes[8] (post (= (bytes-length result) 8)) (bytes-zero))` flips SAFE to REFUTED.
- **The axiom's validity is a trust-channel dependency, not a contract discharge.** It holds because
  codegen reads the same annotation to emit an n-length zero value, so it rides the
  `codegen_semantics_version` stamp (§3.5). The category already existed rather than being opened
  here: `bytes-set`'s `bytesLen(r) = bytesLen(b)` is the same kind of claim, shipped.
- **The un-reified nullary equation stays as a fall-through.** `bodyToPredFrom`, the exported test
  entry point, takes no `mRet` and therefore cannot reify; roughly thirty direct calls in
  `compiler/test/Spec.hs` would meet a pattern-match failure without it. The production path always
  reifies first, so the clause is dead there.

### Not in this release

**Stage 3 is open, and the stage ordering remains a correctness constraint, not a preference.**
Stage 3 moves `resultLenFact` off the constraint LHS into the effective post, so the body VC proves
its own result length and call sites recover it as an assumed post. It could not land first: without
the constructor axiom the body VC for a `(bytes-zero)`-bodied def is UNSAT. Stage 3 changes the
evidence hash of every bytes-returning function and owes the SAFE-ARG revalidation ceremony.

**The bytes algebra does not close here.** Rev 2 of the design claimed it did, on the grounds that one
constructor axiom plus `bytes-set`'s preservation lemma covers every introduction and update. The two
lemmas cannot meet inside one body: `(bytes-set (bytes-zero) 0 1)` is a type error, because
`(bytes-zero)` is admissible only as a whole body. Every real composition crosses a function boundary,
and the length reaches the caller only through the callee's effective post, which is Stage 3. Stage 2
makes the constructor self-supporting; Stage 3 makes it composable, and the algebra closes there.

**A builtin axiom still appears on no channel of the trust report.** Measured at this stage:
`bytes-set`'s length-preservation fact is absent from every reporting surface. `TrustReport.hs`,
`ObligationMining.hs`, `ObligationAssembly.hs` and `WeaknessCheck.hs` carry no reference to it, and
`cvPostAssumption` is consumed only inside `FixpointEmit`. A `verified` tier therefore already rests
on a codegen-faithfulness assumption the report never names, and Stage 2's axiom inherits that
silence. Tracked as **TRUST-AXIOM** on the roadmap; it is not Stage 2's work and is not fixed here.

**SAFE-ARG is not closed by this release.** Stage 2 gives the constructor an establishing axiom of
its own instead of a borrowed antecedent, which is an assumption with a named trust dependency rather
than a proof; the return position is still shielded by `verify` rather than discharged by an
obligation.

### Gates

**The gate is verdict-identity on the `bytes-zero`-bodied population plus the two new tests, not the
corpus sweep.** `resultLenFact` is untouched, so the same fact reaches the solver twice and no verdict
can move; what has to be shown is that the axiom is present, array-sorted, pre-free, and sourced from
the declared return, which is what the new tests assert.

The corpus sweep ran before and after over **273 files with 0 verdict deltas**, and it is recorded as
a regression check only. `examples/` contained no `bytes-zero` at all before this release, so the
sweep has **no witness for the construct**: it is silent on Stage 2 rather than passing it. `.fq`
byte-identity is unavailable as a gate, because the fresh axiom binder shifts the file-scoped body
counter.

`examples/bytes-bounds/zero-buffer.llmll` is new and closes that witness gap ahead of Stage 3: the
bytes-**construction** class had no fixture under `examples/` and no verified artifact anywhere in the
tree, so Stage 3's evidence-hash revalidation would have had nothing to revalidate. It is frozen into
the family's `EXPECTED_VERDICTS.json`, taking `scripts/refute-crux-gate.sh` from 58 to **59 cases, 0
failed**.

`scripts/check-examples.sh` reports **163 passed, 1 failed**. The single failure
(`examples/totp_rfc6238/totp_filled.ast.json`) is the pre-existing v0.14.73 bytes-arm rejection
recorded under §v0.14.74, unrelated to this change. No `checker_soundness_version` bump: the change
adds an antecedent logically implied by one already present.

### Tests

**1461 → 1463.** `A1-11` pins the axiom's shape: a fresh call binder at the byte-array sort, the
`Map_default(0)` equation and the `bytesLen(...) = n` conjunct on that binder, the result equation
joining them, and **no** call-pre obligation, since a constructor has nothing to prove. `A1-12` is the
discriminative negative for edge case 7: a program declaring `(post (= (bytes-length result) 16))`
against a `-> bytes[8]` return must emit `= 8` on the axiom binder and never `= 16`, so an
implementation reading `n` from the contract instead of the return type is caught rather than
verified. `A1-4` gains the axiom conjunct alongside the reflection assertions it already carried.

### Spec

- **§5.3.3 and §3.4.6 are reconciled with Stage 1, which v0.14.76 shipped without doing.** Both still
  described the `bytes[n]` length as a binder fact discharged by no obligation, which stopped being
  true of the parameter position a release ago. Both now state the split: the parameter length is
  earned at the call site, the return length is still asserted onto the constraint LHS until Stage 3,
  and the `map[k,bool]` arm is unchanged and permanent. §3.4.6 additionally records that WILD-ASSUME's
  bytes-parameter arm is retained as a **diagnostic** rather than for soundness, since a bare `?`
  there now yields a worse message rather than an unsound verdict.
- **§13.12's `bytes-zero` entry** gains the constructor length axiom: the declared return gives the
  constructor its length in verification and not only at runtime, `n` is read from the return and
  never from the `post`, and validity rides the `codegen_semantics_version` stamp. **§5.3.3** records
  that `Σ_auto` is unchanged by the axiom, which introduces no new symbol, sort, or theory.

Design: [`docs/design/fact-ag-proposal.md`](docs/design/fact-ag-proposal.md) (Rev 3), with the
standalone [`docs/design/fact-ag-proposal-review.md`](docs/design/fact-ag-proposal-review.md).

## v0.14.76: the bytes[n] length is earned at the call site, not asserted from the declaration (2026-08-01)

FACT-AG-LEN **Stage 1 of 3**, the parameter position. One emitter change plus test surface. No
schema change, no evidence-hash change, no `checker_soundness_version` bump.

### Changed, FACT-AG-LEN Stage 1

- **The fact moves off the binder and into the precondition.** A `bytes[n]` parameter carried
  `bytesLen(v) = n` as its binder refinement (`bytesLenReft` at `emitParamBind`), so the equality
  entered every VC antecedent with nothing discharging it. That is the SAFE-ARG class: WILD-ASSUME
  (v0.14.73, v0.14.74) polices the one type-compatibility path by which an unvalidated declaration
  reaches the site, but it does not make the fact earned. New `bytesLenParamPre` contributes
  `(= (bytes-length n) len)` per bytes-typed parameter, conjoined at `paramRefinementPre`, so
  §5.3.4's call rule proves it at each call site under PROVE polarity and assumes it inside the
  callee, exactly as for a hand-written `pre`. `buildContractEnvWith` already augments the stored
  `ContractEnv`, so one edit supplies both the definition-site assume and the call-site prove.
- **The gate self-activates, and `typeToSort` is untouched.** `bytes-length` is in `bytesOpNames`
  and `arrGateActive` reads the **augmented** contract, so a bytes-typed function turns the LEVER-A1
  gate on for itself and its parameters bind at `byteArraySort`. The alternative raised in review,
  widening `typeToSort` for `TBytes`, would have array-sorted `Result` and ADT components where no
  `bytesLen` machinery is in scope; it was rejected on that measurement, not on preference.
- **`emitParamBind` keeps the sort and drops only the predicate.** That clause supplied
  `byteArraySort` as well as the fact, so deleting it outright falls through to `typeToSort`'s
  conservative `FQInt` default and emits ill-sorted `bytesLen` applications. The design document
  said to delete it and was wrong.
- **The elaboration is deliberately not folded into `resolveAllRefinements`.** Four other consumers
  must not see it. One is `returnRefinementPost`, which is Stage 3, and Stage 3 without Stage 2
  refutes every `bytes-zero` body; another is `payloadRefinement`, which would defeat the
  component-position exclusion.

### Not in this release

**Stages 2 and 3 are open, and the stage ordering is a correctness constraint, not a preference.**
Stage 2 is the `bytes-zero` constructor axiom: `(bytes-zero)` translates to `Map_default(0)` and
carries no length, so landing Stage 3 first makes the body VC for a `-> bytes[n]` function UNSAT and
refutes every bytes-constructing function in the corpus. Stage 3 is the return position, and it will
change the evidence hash of every bytes-returning function.

**The return position is still shielded rather than discharged.** `resultLenFact` remains on the
constraint LHS, so a declared return's length is assumed about the body rather than proved of it.
Ten shapes were attempted against it and **no witness was constructed**; that is a measured absence,
not a proof. One result narrows the claim rather than closing it: an `if` whose arms carry different
declared lengths passes `llmll check` with only a warning, and `llmll verify` promotes it to a hard
error, so the shield is `verify`, not the type checker.

**SAFE-ARG is not closed by this release.** Stage 1 retires the unearned antecedent at the parameter
position only.

### Gates

Corpus sweep **251 files, zero verdict delta**, with the baseline taken by revert-and-rebuild.
Evidence hashes unchanged, which confirms Stage 1 moves no hash.

Three delta populations were declared before the sweep ran, and only one has an in-tree witness:
functions carrying a `bytes[n]` (8 `.llmll` across 8 files, 11 JSON-AST across 7 files), of which
1 `.llmll` and 7 JSON-AST move from off-gate to gated. The other two, a function carrying `bytes[n]`
and `map[int,int]` together and a non-bytes direct caller of a bytes-typed function, have **zero**
in-tree instances. The sweep validates the bytes population and is **silent** on the other two: they
are unmeasurable by this corpus, not passing against it.

### Tests

**1460 → 1461.** `A1-1`, `A1-7` and `A1-8` are re-pointed, each gaining a `shouldNotSatisfy` that
pins the binder fact as gone; `A1-8` additionally pins the callee's length as a discharged caller
obligation. `A1-7` previously encoded byte-inertness for op-free bytes parameters, a property Stage 1
retires by design; what it holds now is that an op-free function still gains no op machinery, no
exact pinning and no family-2 range facts. New `A1-10` covers an aliased `bytes[n]` parameter, the
CR-01 shape at the head position.

Design: [`docs/design/fact-ag-proposal.md`](docs/design/fact-ag-proposal.md) (Rev 2), with the
standalone [`docs/design/fact-ag-proposal-review.md`](docs/design/fact-ag-proposal-review.md).

## v0.14.75: one type-admissibility predicate, so the checker and the emitter cannot disagree (2026-08-01)

A refactor with no user-visible behaviour change on any accepted or rejected program, and one latent
divergence fixed. Zero acceptance delta across the 151-file corpus; `.fq` byte-identical 145/145.

### Changed, ADMIT-SHARED

- **The class, not the clause.** v0.14.74 fixed CR-01 by teaching `assumesFact` to strip
  `TDependent`. The defect was not the missing clause: it was that LLMLL carried **two**
  type-membership algorithms serving one semantic notion with nothing relating them —
  `TypeCheck.assumesFact` matching at the outermost constructor, and `FixpointEmit.resolveAliasTy`
  plus the `is*Like` predicates chasing aliases and stripping refinements. The checker guarded a
  strictly narrower set than the emitter asserted for. A second instance was already queued behind
  CR-01 at component positions, because `assumesFactBoolValue` had no `TCustom` clause.
- **One predicate, in a leaf module both channels import.** New `LLMLL.TypeAdmissibility` holds
  `AliasMap`, `buildAliasMap`, `resolveAliasTy`, `isIntLike` / `isBoolLike` / `isStrLike` /
  `isScalarLike`, `bytesLenOf`, `boolValuedMapTy`, `normalizeTy`, and `admits`. The predicate is
  **defined over the emitter's own fact-injection gates** rather than mirroring them —
  `admits am t = isJust (bytesLenOf am t) || boolValuedMapTy am t` — so agreement is definitional
  and the disagreement is unrepresentable. `FixpointEmit` re-exports the four names its three
  consumers use, so `RefineReuse`, `ObligationAssembly` and `ObligationMining` are untouched.
- **Total on unnormalized input.** `admits` normalizes what it inspects instead of requiring its
  caller to have done so. A "has been normalized" precondition is inexpressible in `Type`, which
  carries no normalization index, so nothing in the project could have checked it. `compatibleWith`
  gains an `AliasMap` parameter so the guard lives **inside** the structural predicate and every
  caller inherits it; hoisting it to `unify` would have avoided the threading and put the guard back
  on the call-site-dependent footing this change exists to remove.
- **ADMIT-OVER, stated rather than left derivable.** `admits` must hold whenever any emitter site can
  inject a fact derived from a declaration. The containment is one-directional: too wide costs a
  needless rejection, too narrow is a false SAFE. CR-01 was too narrow. `admits` deliberately ignores
  `arrGateActive`, which every injection site conjoins, because that gate is a function of the
  callee's **body** — consulting it would make type acceptance depend on a callee's body and differ
  between `check` and `verify`. The shipped `assumesFact` over-approximated identically; this
  documents an existing property rather than widening one.

### Fixed

- **A non-contractive alias no longer diverges.** `FixpointEmit.resolveAliasTy` chased alias chains
  with no cycle guard and was shielded only by `check` failing on a contractiveness error before
  `verify` ran. Moving the predicate into the checker removes that shield, so every alias-chasing
  recursion in the shared module is guarded. Confirmed by mutation: without the guard the ADM-4 run
  does not terminate. `Norm-Stuck` now covers two documented populations — an unbound name, and a
  non-contractive alias, which denotes no regular tree and therefore has no fact to assert. That is
  an intrinsic reason rather than "the checker errors first"; resting on pass ordering is the shape
  of argument that produced CR-01.

### Tests

**1449 → 1460.** `ADM-1..4` exercise `admits` on **unnormalized** input, which no end-to-end test can
reach because both seams pre-expand — including the component-position case `assumesFactBoolValue`
answered `False` for. `SA-18` / `SA-18b` are the non-contractive termination guards on both arms.
`SA-19` / `SA-19b` are a liveness pair driven through the new `runTCWithAliases`: the `structuralUnify`
seam reads `tcAliasMap`, and `runTC` seeds it empty, so a direct unit test over an aliased asserting
type would otherwise have exercised a disabled guard and passed vacuously — a dead WILD-ASSUME guard
has shipped twice on this line already. Three QuickCheck properties carry the acceptance criterion as
**two** obligations rather than one equation: A1 (congruence closure, whose bite is entirely at
component positions) and A2 (expansion equivalence, tested against the real `expandAlias`). A1 ships
in two forms because measurement showed the general generator **misses** the CR-01 sibling that the
component-position generator catches.

### Not in this release

`checker_soundness_version` is **not** bumped: acceptance is unchanged by construction and the corpus
gate measured it. No schema change. `Module.compatibleTy` was left alone — it is reachable only from
`ModuleSpec.hs`, which closed the open question about a third compatibility relation by measurement
rather than by argument.

## v0.14.74: the map[k,bool] arm of WILD-ASSUME, with no reaching-SAFE witness (2026-07-31)

Two compiler changes to `assumesFact`'s discriminant and the diagnostic it drives, plus a corpus and suite re-measurement.

This closes a measured member of the SAFE-ARG class with no reaching-SAFE witness.
The phase closes a class member; it does not refute a demonstrated exploit.
Both the return shape and the argument shape crash on a sort mismatch before a verdict, so this arm is neither known exploitable nor known safe.

### Fixed, WILD-ASSUME-2

- **The class.** A `map[k,bool]` binder carries the ground fact `0 <= select(m$val,k) <= 1`,
  asserted from its declared value type the same way the `bytes[n]` arm asserts `bytesLen(v) = n`
  (v0.14.73). `assumesFact` now covers the map class with the same key/value admissibility
  `FixpointEmit.boolValuedMapTy` already uses (int-or-string key, bool value), reaching both seams
  through the same predicate: `structuralUnify` for arguments, `compatibleWith`/`unify` for returns.
- **Two fixtures prove it live, not one fixture run twice.** SA-8 launders a `map[int,bool]`
  through an unannotated hop at the argument seam; SA-9 does the same at the return seam. Both
  launder through the hop deliberately, so the guard is exercised against the `freshenFnType`-
  produced `?$N` form rather than the bare `TVar "?"`, the exact failure mode that left the first
  SAFE-ARG implementation dead. SA-8's liveness is proven by revert-and-restore: with the map
  clause temporarily removed, SA-8 flips to a `reportSuccess` expected-`False`-got-`True` failure;
  restored, the diff against the committed source is empty.
- **Four fixtures hold the line against over-breadth.** SA-6 and SA-14 confirm `(map-empty)` still
  type-checks at every position; SA-10 confirms an annotated hop is unaffected; SA-12 confirms a
  non-bool value component does not fire; SA-15 confirms the construction path. SA-11 (alias
  coverage) answers a research open question by measurement: an aliased `map[int,bool]` is already
  refused with zero code change to `TypeCheck.hs`, because `expandAlias`/`unify` alias-resolve both
  sides before `assumesFact` ever sees them.
- **The diagnostic now names the fact per class.** `wildAssumeFactNoun` interpolates into
  `tcWildAssumeError`'s message: "a length" for the bytes arm, "a per-key value range" for the map
  arm, a neutral "a fact" fallback elsewhere, keeping the function total. SA-16 asserts both arms
  in one fixture.
- **`checker_soundness_version` is NOT bumped.** `doVerify`'s type-check gate runs, and exits on
  failure, before every sidecar-consuming render branch; `Module.hs`'s per-module sidecar merge is
  discarded whenever that module's own hard errors are non-empty. A program the widened checker
  newly rejects can therefore never reach a branch that renders a cached verdict. Neither of the
  rule's two bump conditions holds: no corpus verdict flipped, and no cached sidecar reaches a
  consumer without a successful type check gating it first.

### Also fixed, found by this phase's own code review

- **A `where`-wrapped base type evaded the restriction entirely, on both arms.** `assumesFact`
  matched `TBytes`/`TMap` at the outermost constructor only, so a `TDependent` wrapper fell through
  to `False`, while `FixpointEmit.resolveAliasTy`, the function that decides whether the emitter
  asserts the ground fact, does strip that wrapper. The checker therefore guarded a strictly
  narrower set than the emitter asserts for, and a return position declared as
  `(type B (where [m: map[int bool]] true))` accepted a laundered wildcard. This was **not**
  map-specific: the same evasion defeated the `bytes[n]` arm shipped in v0.14.73, so the affected
  range for the wrapped shape is v0.14.34 through v0.14.73. `assumesFact` now strips `TDependent`
  before dispatching, matching `resolveAliasTy` and matching what the key/value helpers already did
  for the inner components. SA-17 is the fixture, asserted on both arms; removing the new clause
  turns it red with a `reportSuccess` expected-`False`-got-`True` failure, the false-accept symptom.
- **The rejection wording no longer degrades behind an alias.** `unify` passed the unexpanded type
  to `tcWildAssumeError`, so `wildAssumeFactNoun` read a `TCustom` and every aliased rejection
  reported the generic "a fact" fallback. The diagnostic now takes the alias name for its label and
  the expanded type for its noun, so a wrapped `map[k,bool]` reports "a per-key value range" and a
  wrapped `bytes[n]` reports "a length". SA-17 asserts both.

### Measured

- **Suite:** 1449 examples, 0 failures (baseline 1439 + 10: SA-8 through SA-17).
- **Corpus:** `scripts/check-examples.sh` reports `passed=162 failed=1 skipped=0`, identical to the baseline. The one failure (`examples/totp_rfc6238/totp_filled.ast.json`) is the pre-existing bytes-arm rejection from v0.14.73, unrelated to this change.
  The corpus run is recorded as a regression check, not as evidence the fix works.

### Spec

- **`LLMLL.md` §3.4.6** now states the WILD-ASSUME class as `bytes[n]` and `map[k,bool]` together,
  with the same evidence-limit language stated inline for the map arm.
- **§5.3.5's array-class completeness argument** now records the map arm's
  `0 ≤ select(m$val,k) ≤ 1` fact as shipped rather than deferred.

**Tests:** 1449 Haskell examples, 0 failures (+10). No Python delta. No `.fq` byte change: this is a
type-checker-only widen of what `assumesFact` refuses; the emitter is untouched.

## v0.14.73: a length asserted from an unvalidated declaration proved an out-of-bounds read safe (2026-07-30)

A correctness advisory. One compiler change plus a sidecar-invalidation stamp. Unlike every prior
defect on this line, this one did **not** fail closed: it reported `SAFE`, wrote a `.verified.json`,
and recorded `verified` with `body_faithful: true` for a program that reads past the end of a buffer.

### Fixed, SAFE-ARG

- **The defect.** The type channel let a `bytes[32]` value satisfy a `bytes[64]` parameter when it
  passed through one function with no declared return type, because a bare inference wildcard is
  compatible with everything. The callee's VC then asserted `bytesLen(b) = 64` as a ground fact
  *from that parameter's declared type* and discharged its index-in-bounds obligation against it.
  Eight lines reproduce it; `consume` was certified for every `i` in `[0,64)` on a 32-byte buffer.
- **Affected range: v0.14.34 through v0.14.72.** The ground fact and the obligation it discharges
  were introduced by the same commit (`c4ad7b6`, LEVER-A1), so the defect is coeval with the array
  class. Verified SAFE at v0.14.71, v0.14.72, and at `c4ad7b6` itself; `bytesLen` does not occur in
  `FixpointEmit.hs` at `c4ad7b6^`, so no earlier version has an obligation to discharge falsely.
- **What was falsely certified, and what was not.** Codegen emits a dynamic bounds check
  (`CodegenHs.hs:275`), so the generated program traps rather than reading out of bounds. The false
  claim is the index-in-bounds obligation itself: a runtime failure in a program the verifier
  certified free of exactly that failure.
- **The rule, WILD-ASSUME.** A bare inference wildcard no longer satisfies a type that contributes a
  fact to a VC antecedent that no obligation discharges. Stage 1 is `bytes[n]`-only. Refinement
  aliases and nullary enums are deliberately excluded and measured REFUTED on a laundered value,
  because their type-level data is an *obligation on the producer*, not an assumption.
- **Two seams, because the live path is argument passing.** `structuralUnify`'s wildcard clause
  covers arguments; `compatibleWith`'s covers returns and `checkExpr`. Actual side only: a wildcard
  in *expected* position is the absence of a declaration, so there is no asserted fact to falsify.
- **The discriminant is the bare wildcard and its freshened instances.** Exact equality with
  `TVar "?"` was specified in the design and endorsed in review, and left the rule completely dead:
  `freshenFnType` alpha-renames signature TVars per call site, so an unannotated return arrives as
  `TVar "?$0"`. Named holes and polymorphic builtin variables stay excluded, so sketch mode and
  `(map-empty)` are unaffected.
- **`.verified.json` gains `checker_soundness_version`.** Stamped unconditionally, which is what
  makes *absence* a sound "written by an older binary" signal — unlike the INT-1 field-absence
  trigger, which over-invalidated because the writer legitimately omitted its field. Every sidecar
  written in the affected range revalidates once on first run.

### Known residue

- **The `map[k,bool]` arm is deferred.** Its `0 ≤ v ≤ 1` value-range fact is a member of the same
  class, has no reaching-SAFE witness, and needs the `(map-empty)` over-breadth fixture before it
  ships. Recorded in [`docs/design/finding-arg-position-false-safe.md`](docs/design/finding-arg-position-false-safe.md), not closed here.

### Spec

- **`LLMLL.md` §3.4.6 states WILD-ASSUME**: a bare `?` does not satisfy a position whose type
  contributes a fact no obligation discharges, directionally and at every position.
- **§5.3.3's array class** now records that the `bytesLen(b) = n` binder fact is asserted from the
  declared type and is sound only where that declaration is validated.

**Tests:** 1439 Haskell examples, 0 failures (+11: SA-1..7, SS-1..4); 107 Python. The Python delta
against v0.14.72's 106 is `eaf7bc1`, not this change. Corpus sweep over all 151 `.llmll` files:
zero WILD-ASSUME rejections, so the accepted-program set is unchanged. No `.fq` byte-diff was run;
the emitter is untouched by this patch.

## v0.14.72: the `result` binder's sort comes from the checker, not from the annotation (2026-07-29)

Four compiler changes. The verification channel used to re-derive the sort of the `result`
binder from the OPTIONAL `-> RetType` annotation, defaulting to `int` when it was absent, while
the type channel derived it from the synthesized body type. Where the two disagreed the emitted
`.fq` was ill-sorted and liquid-fixpoint refused the file. Failed closed throughout, so no prior
verdict was affected.

### Fixed, FQ-RESULT-SORT-1 (was routed as FQ-BOOL-SORT-1)

- **The defect was not bool-specific.** String and pair returns crashed identically, and a
  *computed* bool body crashed whenever the post eliminated the boolean (`and` / `or` / `not`
  over `result`). The surviving shape was `(= result e)` alone. Twenty-four configurations
  measured; ten fired.
- **Stage (a), the contract channel.** The checker now records `tau_ret = mRet |> tau_body` on
  `TCState`, and `effRet` substitutes it at the `emitFnConstraints` boundary. One substitution
  fixes the sort derivation and also makes `sigPairUnsafe` / `resultReturnUnsafe` evaluate
  against the real return type instead of failing open on `Nothing`.
- **Stage (b), across module and synthetic paths.** `seedImportedContracts` rebuilds an imported
  `ContractEnv` from statements rather than from `meContracts`, so a new `meRetTypes` on
  `ModuleEnv` carries `tau_ret` cross-module; `emitSynthetic` gives the weakness-check, CDP and
  diverge-fill paths their own map instead of the `FQInt` default.
- **`toExport` and `synthRet` were deliberately not changed.** `meExports` seeds the *importing*
  module's `TypeEnv`, and narrowing its wildcard would make the importer's checker strictly
  stronger; the checkout-brief path has no `tau_ret`, so retiring `synthRet` would regress the
  v0.14.14 R1 fix there.
- **A third stage was implemented and withdrawn.** HOLE-RET (fall back visibly when `tau_ret` is
  the `?` wildcard) demoted 12 corpus functions from `verified` to `asserted`, because a wildcard
  return is idiomatic rather than a defect signal: 104 unannotated `def` heads corpus-wide, 72
  alongside another unannotated callee. Reverted before commit.

### Added, RET-BRANCH-PREF Stage 1

- **`preferConcreteOnSelfCall`.** At an `if` join, the concrete branch's type wins over a branch
  that synthesized the `?` wildcard, but only when that branch is a **self-recursive** call.
  There the wildcard is the enclosing function's own return type and the concrete branch
  determines it, so the preference is a least-fixpoint step rather than a guess. Closes the last
  member of the FQ-RESULT-SORT-1 trigger set. Conservative: only a bare `EApp` headed by the
  enclosing function matches, so a self-call under `let` or wrapped in an operator declines.

### Fixed, emitter warnings reach `--json`

- **`fqResultToReport` built the verify payload from the solver result alone**, so every
  emission-time warning (the >4096-path fallback, `W-DECREASES-UNUSED`, `W-DECREASES-LEX`) was
  printed to stdout and dropped from `--json`. Agents read the JSON, so the warnings were
  invisible to the primary consumer. Emitter diagnostics are warnings, never errors, so folding
  them in cannot flip `reportSuccess`.

### Spec

- **`LLMLL.md` §3.4.6 now defines the `?` wildcard**: it denotes *inference produced no usable
  type at this position*, not *any type*, and because LLMLL erases without casts (§3.4.5) the
  compatibility it licenses is an **unchecked** admission rather than a deferred check.
- **§3.4.6's `if`-reconciliation sentence was wrong** and is corrected: it described the
  hole-branch route and generalized it to every `if`. There are three routes.
- **§12 Grammar Key Rule 1 was wrong** and is corrected: it asserted "Return types are always
  inferred" and denied that the annotation exists, contradicting §4.1 and the `[ ARROW type ]`
  element in the productions above it. Stale from before DEF-RET.

**Tests:** 1428 Haskell examples, 106 Python (+12: FQRS-1..9, RBP-1..3, EMITDIAG-1). Corpus `.fq`
byte-diff against a rebuilt pre-change compiler: all 128 files byte-identical. CDP invariance
across 11 axis rows.

## v0.14.71: stage G2, the artifact audit; and three checks that were never run (2026-07-28)

Pipeline tooling and CI. No compiler source changed, no schema change, no Haskell test added or
removed.

### Added, stage G2, the artifact audit against the pinned bytes

- **Nothing checked that a citation resolves.** Driver-spec section 7 makes the driver validate a
  delegated output against its declared *shape*, which a reason misreading its own quote satisfies
  perfectly. Section 14 pins the source and requires every later stage to read it, and no check
  confirmed that any of them did. On RFC 4648 one disposition reason in twenty moved a positional
  qualifier out of an `unless` exception and into the prohibition, and a person caught it by
  reading three lines of the file stage A exists to pin, after the run had already halted.

- **The stage runs between the disposition pass and the probes**, not after the gate. A citation
  that resolves to nothing should not cost forty-five minutes of feasibility probes, and stage J
  rules on exactly the rows this audit reads.

- **Split by what a machine can decide.** *STOP, mechanical:* the cited document is one that was
  pinned, the span lies inside it, and the quote's words come from that span. *Reported and never
  thresholded, mechanical:* a span one line short of its own sentence, and a declared strength
  absent from the quote. Both of those fire on correct rows, so failing closed on either would
  demand that a correct row be mangled to pass, which is the reasoning
  [`scripts/doc_path_lint.py`](scripts/doc_path_lint.py) records for staying advisory.
  *Delegated:* whether a stated reason describes the clause it cites, which is a reading. The
  agent returns a catalogue and the driver evaluates it, per section 7.

- **A flag must carry the words it rests on, from both sides, and the driver checks they occur.**
  A finding it cannot locate in the artifacts is an assertion, and section 6 forbids a gate to
  rest on one. A misread reason on a **characteristic-core** row is a STOP, because that is
  precisely the unevidenced input stage J would otherwise rule on.

- **The mechanical test is token coverage, and the threshold is measured rather than chosen.**
  Building this corrected an assumption in the RFC 4648 write-up, which reported "quote appears
  verbatim within its cited line span, 64/64" as though a substring test would reproduce it. It
  does not: against the committed TFTP census and the real RFC 1350 bytes a substring test fails
  **22 of 113 correct rows**, because a census abbreviates a long clause with an ellipsis and
  flattens a multi-line packet diagram onto one line. Token coverage separates instead: every true
  citation scores **≥ 0.875**, and the same quotes against 6655 same-width wrong spans reach
  **0.500** at the 99th percentile, mean 0.086, with the band [0.833, 0.875] empty. 1.02% of wrong
  spans still clear the floor, so this catches a citation that plainly does not resolve and is not
  a detector of subtle misplacement; the docstring says so rather than leaving the miss rate to be
  discovered.

- **Replayed over the committed TFTP census and the real RFC 1350 bytes**, it resolves 109/109
  citations, reports the 6 spans that are one line short, and passes. Sections 7 and 14 carry the
  requirement, playbook stage G2 carries the procedure, and both forward-looking lists are updated.
  **Not established:** it has never seen a live run.

### Fixed, the self-test skipped the one gate condition its own data fails

- **Gate J has three conditions and `--self-test` evaluated two.** The third, an exclusion citing
  no barrier from the closed list, is not evaluable on the TFTP artifact: the closed list postdates
  that run, so none of its **53 exclusions carries a `barrier` field**. The per-barrier tally
  exists as prose in `VERIFICATION_SCOPE.md` and never as data, so "zero exclusions outside the
  closed barrier list" was tallied by hand and cannot be checked from the artifact. Replayed
  through the shipped driver, that ledger fails `check_dispositioned` and then STOPs at the gate.

- **A skipped condition let a green self-test report a pinned mechanical spine** while the one
  condition that would fire on its own data went unevaluated. That is a gate kept green by its own
  blind spot, the same shape as the stage that was skipped whenever its outputs existed. The zero
  is now asserted, so the ledger gaining barriers fails the pin and forces it to be re-taken, and
  the gap is printed rather than absent.

- **`--self-test` was in no CI job and no test invoked it**, so figures it pins to the first real
  run were only ever checked by hand. A pytest now runs it and asserts both coverage gaps are
  stated, which puts it in the fast `version-gate` job through the existing pytest step. Stage G2
  is pinned in the half needing no source bytes: three canonical rows declare a strength their own
  quote does not contain (T117-T119, all citing RFC 1123's requirements-summary table), which pins
  the reason that check reports instead of halting.

### Fixed, the refute-crux gate had no verdict kind for a capability violation

- **A program the type checker rejected counted as one the solver disproved.** The script knew
  `safe` and `refuted` only, and filed a capability violation as `refuted` because the branch
  greps for `error:`. Both kinds print `error:` and exit 1, so the suite would have gone on
  reporting a green refutation after the solver stopped being reached at all.

- **`capability` matches the missing-capability diagnostic** rather than a bare error, and
  optionally the capability it names; `refuted` now rejects that diagnostic explicitly, so the two
  cannot drift back together. `crux-shell-undeclared-authority` moves to the new kind. Checked
  rather than assumed: relabelling it `refuted` turns the gate red, and no existing case emits a
  capability diagnostic, so the eleven `examples/` families are unaffected.

### Fixed, the retired `B7` test, annotated where it still governs

- Amendment 1 replaced `B7`'s test on 2026-07-27 and updated the driver, the stage-G prompt and the
  playbook. Two frozen records still carry the retired form, and each gets a **dated note rather
  than a rewrite**. `VERIFICATION_SCOPE.md`'s barrier table stays as written because it records the
  list in force for that run; its single `B7` row clears the corrected criterion anyway.

- **ARP's four retired-phrasing `B7` rows, re-read: three clear the corrected criterion and `A63`
  does not.** It rests on `MD2`, a decision that run made about what to model, where the
  replacement admits only the declared types or named sibling rows. No disposition moves and the
  exclusion may well stand under `B2`; deciding that is a re-disposition, which a later reading
  does not do to a frozen ledger.

- **That answers half of an open question without a fourth run**, and sharpens the rest. Six of
  eight on RFC 4648 and three of four on ARP named what entails them unprompted. `A63`'s failure
  mode is not "named no entailment" but "named one, from the wrong kind of thing", which a prompt
  demanding an entailment gets either way. Both forward-looking lists say so.

**Gates:** DRIFT-CI-1 pass, DRIFT-DOC-3 pass, DRIFT-DOC-4 clean (508 prose citations across 132
living files, all resolve), refute-crux gate 58 passed / 0 failed, driver `--self-test` pass,
harness pytest 106 passed (91 to 106, +15). Haskell test count unchanged; no compiler source in
this cut.

---

## v0.14.70: the driver's own spec verified in LLMLL; gate J halts a run for the first time (2026-07-28)

Tooling, experiment records and CI. No compiler source changed, no schema change, no Haskell test
added or removed.

### Added, `tools/llmll-driver/`, the pipeline driver's specification verified in LLMLL

- **The driver is specified as an Internet-Draft** at
  [`experiments/rfc-swarm/targets/driver-spec.txt`](experiments/rfc-swarm/targets/driver-spec.txt),
  deliberately, so that it can be read by the same pipeline it describes. Its section 15 splits
  its own obligations into three tiers; this directory implements the first two.

- **Section 15.1, the proved tier: all seven obligations discharged "by proof over all inputs, not
  by testing."** Nine functions across six modules, every one body-faithful and clearing
  `--strict-verified-core`, which is the acceptance bar section 9 defines for a fill. 26 contract
  clauses, each carrying a `:source` citation to the section it discharges, which is what section
  11 requires of a carried clause. [`stage.llmll`](tools/llmll-driver/stage.llmll) (the four
  statuses, and that an error is never recorded as stopped),
  [`skip.llmll`](tools/llmll-driver/skip.llmll) (a stage is skipped only on manifest, presence and
  digest together), [`gate.llmll`](tools/llmll-driver/gate.llmll) (the halt decision, and the
  remedy a barrier's class implies), [`fill.llmll`](tools/llmll-driver/fill.llmll) (fill
  acceptance, the separated retry budgets, and what counts as a finding),
  [`token.llmll`](tools/llmll-driver/token.llmll) (a token is not held while an agent is working),
  [`liveness.llmll`](tools/llmll-driver/liveness.llmll) (advancement judged from any artifact, not
  from the log).

- **Two properties are stated in ways worth knowing.** "Coverage MUST NOT be thresholded" is
  encoded by pinning `gate-halts`'s result entirely to the two enforced conditions, so any body
  that consulted the coverage counts would have to disagree with the post on some input: a
  non-interference property becomes an ordinary refinement obligation. And section 10 is proved
  **per step, not per trace**. The closure to "no token is ever held while any agent works, across
  a whole wave" is an induction over an unbounded sequence of fills, and is not claimed.

- **Section 15.2, the asserted tier: [`shell.llmll`](tools/llmll-driver/shell.llmll).** The spec
  holds that effectful operations cannot be proved and "MUST NOT be exiled from the program in
  order to say so." Every effect is reached through a declared capability (`wasi.io`, `wasi.fs`) or
  through a `Host` interface for the operations no shipped capability names. The section's hardest
  requirement is an over-approximation, for any function, of the capabilities reachable through
  its call graph, and Bundle B0's `effect_summary` is exactly that: `finish-stage` reports
  `[fs.write, stdout]` while performing no effect of its own, inherited entirely from the two
  shells it calls, and nothing reaches `unbounded`. Two further clauses hold by construction.
  Authority is enforced rather than declared: `crux-shell-undeclared-authority` writes the
  filesystem while importing only `wasi.io`, and fails at **type-check**, not at the solver. And a
  runtime-enforced obligation is not presented as a proved one: every shell function falls back
  from body-faithful verification and carries no proved level, while the core functions it calls
  report `verified (liquid-fixpoint)`.

- **`EXPECTED_VERDICTS.json` freezes 17 cases, and five of the eight refuting cruxes are not
  invented.** They are defects that shipped in the Python driver, or behaviour it still has: a
  stage was skipped whenever its outputs existed, so a failed freeze gate was bypassed by its own
  report; the checkout token was held across a whole agent call, which wedged fourteen holes;
  `--status` judged advancement from `run.log`, which cannot move while a delegated stage runs; the
  exclusion-ratio ceiling, retired as a defective instrument by
  [`rfc-swarm-coverage-review.md`](docs/design/rfc-swarm-coverage-review.md) F-1; and one remedy
  string for every barrier class, which is what the driver does **today**. That last crux refutes
  the shipped implementation, which is the spec being ahead of the code.

- **This is not the driver, and the README says so.** Section 15.4 holds that an implementation
  whose effectful surface lives in another language does not conform, "since nothing then bounds
  its authority or enforces its contracts," so this is a partial artifact by the spec's own terms.
  Section 15.2 is satisfied in shape rather than in coverage: the shell demonstrates the tier's
  discipline over a handful of operations, and the orchestration that would actually run fifteen
  stages is not written.

### Added, the RFC 4648 run record, the first STOP for a real reason

- **Gate J halted on the characteristic-core condition** after stages A through I, 76 minutes,
  without reaching the wave. Two prior runs had passed every gate, and gate L's one failure on ARP
  was a hardcoded tag prefix in our own lint, which the resume bug then bypassed. A method whose
  stop conditions have never stopped anything has not shown that it has working stop conditions;
  across three runs that condition has now been observed in both states.

- **Scored against the prediction committed at `c212fc0` before launch: the conclusion is right and
  the reasoning behind it is wrong.** It expected the bit-regrouping core to hit the same `B5`
  string-structure wall that took ARP's `8 + 2*ar$hln + ar$pln`. Bit regrouping verified as
  fixed-width arithmetic within a quantum (6/6 probes SAFE, 6/6 mutants refuted), and **line
  wrapping** halted the run. Carried C1+C2+C3 was predicted below 20% and the ledger recorded
  **84.6%**, the highest of the three runs, so RFC 4648 is not the bad-fit target it was chosen to
  be.

- **The halt is a finding rather than a tautology because stage F is blind.** Its 75KB prompt
  contains zero occurrences of `scope.md`, "decidable fragment" or `LLMLL`, and instructs the agent
  "you do not yet know what will verify, and that is deliberate." A fragment-blind agent named the
  core; a fragment-aware stage excluded a row from it; neither could see the other. The same
  blindness produced the run's most interesting non-result: 22 of the 23 core rows sit inside the
  boundary stage B drew.

- **[`AMENDMENT-1.md`](experiments/rfc-swarm/runs/rfc4648/AMENDMENT-1.md) re-barriers A1 from `B7`
  to `B5` on probe evidence**, dated, with the argument shown, per the playbook's anti-pattern 6.
  The disposition, the core membership, the STOP and every coverage figure are unchanged.

- **An artifact audit of all 64 rows against the bytes stage A pinned** found citations verbatim
  64/64, line spans in bounds 64/64, declared RFC 2119 strengths uninflated 64/64, core obligations
  faithful 23/23, and **one disposition reason in twenty that misreads its own quote**, moving a
  positional qualifier out of an `unless` exception and into the prohibition. Found by reading
  three lines of the file stage A exists to pin. Nothing in the pipeline does this today.

### Fixed, the `B7` barrier's test was undecidable, and false in its first use

- `B7` read "true by construction: if the model admits no constructor for the forbidden thing, no
  mutant can exercise the row." A probe refuted that on A1, the row that fired gate J: a mutant
  **can** place a line feed, because the constructor is a table entry. Whether a mutant exists is
  also undecidable in general (Budd and Angluin, *Acta Informatica* 18, 1982), so the test could
  not be applied even where it holds, and could be asserted where it does not.

- **Replaced by an entailment the disposition must name**: admissible only when the row's own
  obligation follows from the declared types alone or from the clauses carrying other inventory
  rows, which must be named. Six of the run's eight `B7` rows already did this unprompted. `B7`
  now applies only to rows whose obligation the model can express, so weakening a clause until it
  is vacuous and then excluding it for vacuity is the move the rule forbids. Driver `BARRIERS`
  label, stage-G prompt rule 2, playbook stage G rule 2. The gate checks barrier keys rather than
  labels, so `--self-test` is unaffected.

### Fixed, driver-spec section 6, rewritten from the observed STOP

Section 6 was written before any gate had fired, so its content came from reading the driver rather
than from watching it work. Three requirements it lacked. A reason on the closed barrier list
**MUST** be defined by a test an implementer can apply, since a reason defined by the absence of
something unbounded states no test: it cannot be applied where it holds, and it can be asserted
where it does not. A reason **MUST** carry a class fixed before the run, saying whether the
exclusion is a property of the verifier's reach or of the chosen model, and the gate **MUST**
report the remedy that class implies, because one remedy for every reason misdirects in both
directions. And an exclusion asserting that nothing the implementation could do would violate a
clause **MUST** carry evidence, which the gate **MUST NOT** accept unevidenced. A fourth lesson,
that a citation must be checkable against the pinned bytes, belongs in sections 7 and 14 and is
left for a separate change.

### Fixed, three ways the driver failed unreadably

- **A budget overrun crashed instead of stopping.** `subprocess.TimeoutExpired` was uncaught, so an
  overrun propagated out of `main()` as a traceback: the stage recorded nothing and the manifest
  was left mid-run, making the agent's partial work look like debris rather than a resumable state.
  It is now a `StopCondition` naming the budget, pointing at the partial work, and saying the
  overrun may itself be treated as a finding.

- **A run could be put where the OS will delete it.** A reboot destroyed an eight-stage RFC 4648
  run whose workdir was under `/private/tmp`; the prediction survived because it was committed, and
  nothing else survived at all. The driver now refuses a workdir under a root the OS may reclaim
  before running any stage, with `--allow-volatile-workdir` as a loud override. It also refuses an
  in-repo workdir, because the committed records of earlier runs live there and section 8 forbids
  an agent to see them. Durability and blindness pull against each other, and
  `~/rfc-swarm-runs/<name>` is the shape that satisfies both.

- **`--status` judged advancement from `run.log`**, which cannot move while the driver is blocked
  on a delegated stage, and delegated stages are most of a run, so every healthy agent stage read
  as `STALE`. It now judges from any file under the workdir. Separately, a stage raising anything
  other than a `StopCondition` is recorded `failed` and reported apart from `stopped`: a stop is a
  verdict and is a result, a crash is an accident and is not. All three are now normative
  requirements of the spec (sections 4, 5, 12), so the LLMLL driver does not reinherit them.

### Fixed, the refute-crux gate could not address a suite outside `examples/`

- **Suites are named by repo-relative path** rather than by a bare name under `examples/`. The
  eleven existing families gain an `examples/` prefix and are otherwise untouched.

- **Each case is verified against a copy of the whole suite directory** rather than of the single
  case file, because a case that imports a sibling module cannot resolve it from a one-file copy.
  `verify` still checks only the named file, so the extra siblings change no verdict, and that is
  measured rather than assumed: the eleven existing families produce 41 passed / 0 failed before
  and after, and the suite total goes 41 to 58 purely by addition.

- **Known gap, recorded in the suite's `note` rather than papered over.** The script's verdict
  vocabulary is `safe` and `refuted` only, and a capability violation is neither.
  `crux-shell-undeclared-authority` is filed as `refuted` because the branch greps for `error:`,
  though it fails at type-check rather than at the solver. A third expect kind would fix it.

- **Eight generated `.verified.json` sidecars were committed with the suite**, and are now ignored
  and untracked. `tools/llmll-driver/` matched none of the existing ignore patterns, so a
  directory-wide `git add` picked them up. No canonical exceptions there.

### Routed, FQ-BOOL-SORT-1, a bool-literal body crashes the solver

A contracted `def` whose body is a boolean literal crashes liquid-fixpoint with a sort-unification
error. The `result` binder is emitted at sort `int` although the function returns `bool`, and the
body's reflection then puts `result = true` against it. **Annotating the return type is the
workaround**: the identical `def` written `-> bool` emits `bind 1 result : { v : bool | true }` and
returns a normal verdict, so the sort is defaulting rather than being derived from the inferred
body type. Controls isolate the trigger to the literal body and not the `post` shape. **Fails
closed throughout** (exit 1, a crash, never a false SAFE), so no prior verdict is affected, and no
bool-returning contracted `def` exists in the fixtures or examples, which is consistent with this
never having been hit. Found while probing RFC 4648 row A1; filed on
[`docs/compiler-team-roadmap.md`](docs/compiler-team-roadmap.md) with the two candidate emit sites.
Not fixed here.

**Gates:** DRIFT-CI-1 pass, DRIFT-CT-2 pass (14 doc-claims), DRIFT-DOC-3 pass, DRIFT-DOC-4 clean
(504 prose citations across 131 living files, all resolve), refute-crux gate 58 passed / 0 failed
(41 to 58, +17), driver `--self-test` pass, harness pytest 91 passed. Haskell test count unchanged;
no compiler source in this cut.

---

## v0.14.69: DRIFT-DOC-4, prose path citations swept and linted (2026-07-26)

Documentation and CI only. No compiler source, no schema change, no Haskell test added or
removed.

### Fixed, 58 stale prose path citations across 22 files

- **Markdown links have always been checkable; bare-backtick prose citations were not.**
  `docs/design/foo.md` written in running text is followed by no tool, so it rots silently when
  the file moves. 22 files carried citations into `docs/design/` for documents that had been
  archived, plus one rename basename matching cannot follow
  (`docs/design/empirical-methodology.md` moved to `experiments/methodology.md` on 2026-05-25
  under DOC-CONSOLIDATE Phase 2; the redirect stub was correctly deleted a cycle later).

- **The `findings/<role>.md` cluster, 18 occurrences, rewritten to `findings.md` plus the H2
  section.** Per-role findings files were consolidated into H2-per-role sections inside
  `findings.md`; the citations were never updated.

- **Verified target-only.** All 57 changed lines are a path token swap or an inserted
  `` `## <Role>` ``, checked token by token against `HEAD`, with balanced line counts in every
  file. No prose was reworded.

### Added, DRIFT-DOC-4 as an ADVISORY lint

- **[`scripts/doc_path_lint.py`](scripts/doc_path_lint.py) reports unresolved prose path
  citations and always exits 0.** Wired into the fast `version-gate` job. `STRICT=1` opts in to
  a nonzero exit for local use; CI deliberately does not set it.

- **It is advisory because one class cannot be decided, and never will be.** A rationale
  legitimately names a location that does not exist, where the non-existence *is* the point.
  From `experiments/language-comparison-backlog.md`: the backlog "lives at the root rather than
  inside `experiments/repair-loop/` ... **It can later move into
  `experiments/repair-loop/BACKLOG.md`** via `git mv` if cross-cutting visibility ceases to
  matter." That citation is correct, and a fail-closed gate would demand it be mangled. This
  would have been the first gate in the repo that can be wrong about correct input, so it
  reports instead. The module docstring says so, and a test pins the exit contract.

- **The exclusions are what make it usable, and they are tested.** Without them the same scan
  reports roughly 450 findings, nearly all correct prose. Four classes: **historical files**
  (postmortems, frozen run records, append-only CHANGELOG, archived docs, all of which describe
  the tree as it was); **historical lines** (a living doc holding a past-tense sentence, as in
  `UPDATE-PROTOCOL.md`'s archive table, where rewriting the cited path would turn "X moved to Y"
  into "Y moved to Y"); **placeholders** (`postmortem-NNN.md`, `text/NNNN-name.md`,
  `turn_NN/verifier.json`, elided paths); and **link labels**, where the backticked text sits
  inside `[label](target)` and the target already resolves.

- **`ALLOW` carries a reason per entry**, since an unexplained entry is indistinguishable from a
  stale citation someone gave up on. Nine entries: one counterfactual, and paths that are not
  repo paths at all (`src/Lib.hs` is `llmll build` output, `.llmll/templates/…` is created at
  runtime, `scratchpad/…` is never committed).

- **18 tests** in `scripts/tests/test_doc_path_lint.py`, covering each exclusion predicate plus
  a `test_clean_on_live_repo` regression guard: move a file without updating the prose naming
  it, and the suite goes red even though the lint itself passes.

**Gates:** DRIFT-CI-1 pass, DRIFT-CT-2 pass (14 doc-claims), DRIFT-DOC-3 pass, DRIFT-DOC-4 clean
(492 prose citations across 130 living files, all resolve), harness pytest 87 passed (69 to 87,
+18). Haskell test count unchanged.

---

## v0.14.68: DRIFT-DOC-3: the archive invariant is gated; `open`-ordering claim guarded (2026-07-26)

Documentation and CI only. No compiler source changed, no schema change, no Haskell test added or
removed.

### Added, DRIFT-DOC-3, the third drift gate

- **[`scripts/doc_archive_gate.sh`](scripts/doc_archive_gate.sh) asserts that an archived design
  doc sits in the directory its declared disposition names.** Docs may carry
  `archive-disposition: shipped | superseded | dropped | deferred` in YAML frontmatter; the first
  two are shipped-side (`docs/archive/shipped-design-specs/`), the last two dormant-side
  (`docs/archive/dormant-explorations/`). Wired into the fast `version-gate` job, which needs no
  Stack because the gate has no compiler dependency. **Fail-closed:** unlike DRIFT-CT-2 there is no
  SKIP path, because nothing it needs can be absent.

- **It is a *consistency* gate, sibling of DRIFT-CI-1, not of DRIFT-CT-2.** `version_gate.sh` and
  this one both compare records maintained inside the repository and detect *disagreement*;
  `doc_claims_gate.sh` executes the compiler, so it has an oracle and detects *falsity*. DRIFT-DOC-3
  cannot catch a field and a path being wrong together, which is the structural limit of a
  self-attestation channel that **F-002** already settled (`LLMLL.md §4.4.6`). The gate's header
  and `docs/UPDATE-PROTOCOL.md` both say so rather than implying the stronger claim.

- **Opt-in field with a ratchet, not an allowlist.** Files without the field are ungated; the gate
  counts them and fails if the count exceeds `UNGATED_BOUND` (58 at landing), so a newly archived
  doc either declares the field or forces a visible bound raise. A named allowlist with a
  shrink-only *convention* had no forcing function, since growing it was a one-line edit in the
  same file.

- **A declaration outside the two governed directories is also a failure.** `professor-reviews/`,
  `wasm-investigations/` and any future archive category sit outside the shipped-side/dormant-side
  split, so a disposition declared there is a claim the gate cannot check. Reading it and saying
  nothing is how an opt-in field quietly stops covering anything: the author believes the file is
  gated and it is not. Found by walking into it, when the archived professor review of the proposal
  that specified this gate declared `superseded` from `professor-reviews/`.

- **[`scripts/doc-archive-fixtures/`](scripts/doc-archive-fixtures/) self-test, 8 files.** The gate
  runs `pass/` (4 files, one per vocabulary value, expect 0 violations and 4 *gated*) and `fail/`
  (4 files: mis-filed shipped-side, mis-filed dormant-side, value outside the vocabulary,
  declaration outside the governed directories, expect exactly 4) before scanning `docs/archive/`.
  Every count is asserted, so `fail/` returning 3 is a regression just as much as `pass/` returning
  1. Unlike DRIFT-CT-2, whose corpus is expected to contain failures, this gate's corpus is
  expected to be conformant, so its failure branch would otherwise never execute in CI. A
  zero-file guard exists for the same reason: the first draft scanned nothing and reported PASS,
  because the scan function ran under command substitution and its counters were discarded in the
  subshell.

### Fixed, a third mis-filed archive doc, and why two sweeps missed it

- **`contract-clause-refactor.md` moved to `dormant-explorations/` with
  `archive-disposition: deferred`.** Titled "Deferred Design", status "Deferred, captured for
  future reference", Option B documented and never chosen, zero `CHANGELOG.md` and zero roadmap
  citations. The 2026-07-26 first sweep searched for *abandonment* vocabulary and this document is
  *deferred*, so it did not match, and the archive-organization proposal's Rev 1 claim that the
  shipped/dropped split "already landed" was wrong.

- **The vocabulary is four-valued for that reason.** Collapsing `deferred` into `dropped` would
  assert an abandonment the document denies, which is the same category error the split exists to
  prevent. Measured: 55 of 57 archived files carry a status marker, but only **21 of 57** decide
  the shipped-side question by keyword, because most state lifecycle ("Approved", "BUILT",
  "CLOSED") rather than disposition. That measurement is why the gate reads a declared field
  instead of scanning prose, and it converges with the over-fire direction: "superseded" appears in
  body prose describing a superseded characterization, triage row, construct, and adjudication in
  four different files.

### Added, DRIFT-CT-2: the `open`-ordering claim, 11 → 14 fixtures

- **The order-sensitive half of the "must appear before defs" cluster is now guarded.**
  `import-after-def.llmll` and `decl-order-independent.llmll` guard the position-*independent*
  half; `getting-started.md` §4.8/§4.9 assert that `(open …)` placed *after* a `def` using its bare
  names leaves the call unresolved, and nothing checked it.

- **One claim, two fixtures, because the documented behaviour is a disagreement.**
  `open-after-def-typecheck.llmll` (`@cmd: typecheck`) asserts exit **0** with only
  `warning: call to unknown function`; `open-after-def-verify.llmll` (`@cmd: verify`) asserts exit
  **1** with `error:` on the same program. Neither arm alone guards "a green typecheck is not
  evidence the ordering is right". `build` behaves identically to `verify` and is unguarded, since
  it would pull GHC into the fast path for no additional discrimination. `open-aux-lib.llmll` is
  the support module and carries its own claim, so a failure localizes to it rather than to the
  claim under test.

- **Multi-module DRIFT-CT-2 fixtures need no gate machinery.** `(import foo)` resolves
  `foo.llmll` relative to the importing file, not the process CWD, verified from a different
  working directory (the CI condition). The `doc-claims/README.md` "known gaps" note that implied
  otherwise is corrected; the remaining gap is multi-*format* fixtures (`patch`), where the extra
  input is not a `.llmll` the gate can glob.

### Documentation, the version-bucket policy is retired, by decision

- **`docs/UPDATE-PROTOCOL.md` Archive policy rewritten.** The `v0.6/`…`v0.14/` sub-categorization
  line, carried as "well overdue" since DOC-CONSOLIDATE settled 2026-05-24, is retired.
  `shipped-design-specs/` is flat **by decision, not by neglect**; version lineage is queried from
  `CHANGELOG.md` and the roadmap's `## Shipped Releases`, which P1 already names authoritative.
  Adjudicated by the user 2026-07-26 on
  [`docs/design/archive-organization-proposal.md`](docs/design/archive-organization-proposal.md)
  Rev 2, with a professor review at
  [`archive-organization-review.md`](docs/design/archive-organization-review.md).

- **Two named criteria replace taste for the next filing question.** *Criterion R* (retrieval): does
  the partition narrow a scan a reader performs, measured by **effective** class count rather than
  nominal. The document-kind axis scored 2.5 effective classes against a nominal 9, with the modal
  class holding 61%, and the filename already carries the same information for 46 of 57 files;
  the feature-line axis scores roughly 40 classes over 57 files. Both declined. *Criterion I*
  (inference guard): does misplacement make a reader conclude something false. The shipped/dormant
  split scores near zero on R and is kept on I alone. Version buckets fail both, and for the 11
  files with no version signal at any source a bucket would *induce* a false claim rather than
  prevent one.

- **The general rule is now stated: encode only what is immutable in a path.** Rust keeps
  `rust-lang/rfcs` `text/` flat and GHC keeps `proposals/` flat for the same reason, both carrying
  status in document metadata. Link cost was never the deciding argument but is not close either:
  roughly 158 links point into the directory, **38 in append-only `CHANGELOG.md` sections**, so any
  bucketing requires breaking the append-only invariant or accepting permanently broken links.

- **`docs/archive/dormant-explorations/README.md`** gains the four-valued vocabulary and the side
  mapping, and its opening framing widens from "explored and dropped" to "did not ship", which was
  narrower than both the directory's name and its contents. **`docs/design/INDEX.md`** archive
  table reconciled: the `shipped-design-specs/` cell no longer carries version prose the retired
  policy contradicts, and rows are added for the proposal and its review.

**Gates:** DRIFT-CI-1 pass, DRIFT-CT-2 pass (14 doc-claims, up from 11), DRIFT-DOC-3 pass
(self-test 4 pass / 3 fail, 1 declared disposition, 58 ungated at bound), harness pytest 65 passed
(unchanged: measured on this tree and on `v0.14.67` HEAD). Haskell test count unchanged from
v0.14.67, since no `compiler/` source or test file was touched.

---

## v0.14.67 — fix: FQ-CTOR-COLLIDE-1, a binder named like a constructor crashed the solver (2026-07-25)

### Fixed — constraint-file namespace collision

- **A parameter or `let` binder spelled like the lowercasing of any in-scope ADT constructor
  took the same symbol as that constructor in the emitted `.fq`, and liquid-fixpoint failed
  with a sort error naming a type the function need not even mention.** Constructor symbols and
  ordinary binders share one flat namespace; constructors were emitted as the bare lowercasing
  of their source name, so an `XferState` with a `Denied` state and a `denied: bool` flag
  collided. Merely *declaring* the type was enough, because the datatype declaration lands in
  the same file:

  ```
  data XferState 0 = [ | idle { } | ... | denied { } | terminated { }]
  bind 1 denied : { v : bool | true }        <-- same symbol, different sort
  ...
  crash: SMTLIB2 Error "Sort mismatch at argument #1 for function
         (declare-fun or (Bool Bool) Bool) supplied sort is XferState"
  ```

  User (uppercase-initial) constructors now emit through a single new
  `FixpointIR.fqCtorSym` with a reserved `ctor_` prefix — `Denied` → `ctor_denied`, selectors
  `ctor_denied_0` — while the built-in lowercase symbols (`ok`, `err`, `pair2`) stay verbatim,
  since their declaration and use sites both spell them that way. The declaration site and all
  four translation sites route through that one function, which is the thing that was missing:
  the convention previously existed only as a comment asking the sites to agree. No type
  qualification is needed, because the typechecker already rejects a duplicate constructor name
  within or across type definitions, so constructor names are unique per module.

  **This failed closed** — a collision crashed the solver and was never a false SAFE — so no
  prior verdict is affected. It cost an agent a retry against an unactionable message, which is
  why it was worth fixing before a fill swarm runs on an enum-heavy protocol model, where
  `data`, `error`, `ack`, and `denied` are all natural parameter names.

  Residual, deliberately accepted and documented at `fqCtorSym`: identifier sanitization maps
  every illegal character to `_`, so a binder literally named `ctor_denied` would still collide.
  That is reachable only by naming a binder after the internal convention, and it still fails
  closed.

  Analysis: [`docs/design/finding-fq-ctor-name-collision.md`](docs/design/finding-fq-ctor-name-collision.md).
  Fixtures `compiler/test/fixtures/fq-ctor-collide/`; tests FQCOLL-1..4 plus an updated FQDATA-1
  pinning the emitted symbol shape. 1415 examples, 0 failures.

- **`.fq` byte-change notice.** Every constraint file containing a user sum type now spells its
  constructor symbols with the `ctor_` prefix. Cached `.verified.json` evidence is unaffected
  (verdicts are unchanged), but any tooling that pattern-matched raw `.fq` constructor symbols
  needs the prefix.

## v0.14.66 — fix: MATCH-NULLARY-1, a bare nullary constructor in a match arm verified unsoundly (2026-07-25)

### Fixed — soundness

- **A nullary constructor written bare in a `match` arm parsed as a catch-all binder, and the
  verifier proved postconditions the generated program violated.** `(A 1)` rather than the
  spec's `((A) 1)` (`LLMLL.md` §3.4) fell through `Parser.hs`'s `PVar <$> pIdent` alternative to
  a *binder* named `A`. The arm silently became a catch-all and every later arm was dead. The
  verifier reasoned about that reading, while codegen emitted the name verbatim into Haskell,
  where an uppercase identifier in a pattern **is** a constructor. The two halves therefore
  disagreed about what the program meant, and the disagreement was reachable as a **false SAFE
  under `--strict-verified-core`**:

  ```lisp
  (type E (| A) (| B) (| C))
  (def-shell s1 [x: E] -> int
    (post (= result 1))            ;; true under the catch-all misreading, false in fact
    (match x (A 1) (B 2) (C 3)))   ;; verified SAFE; the built program errors on B
  ```

  `TypeCheck.checkPatternExpanded` now hard-errors when a match-arm pattern is a bare `PVar`
  naming a constructor of the scrutinee's type (user sum types and `Result` alike), and the
  message names the correct form: *"pattern 'A' names a constructor of the scrutinee type
  (A | B | C), so it binds as a catch-all instead of matching that constructor; write
  ((A) ...) for the constructor pattern"*. A hard error rather than a silent
  reinterpretation-as-constructor: `((A) ...)` already exists, and rewriting would change the
  meaning of a program that previously compiled. A genuine catch-all whose name is not a
  constructor of the scrutinee type is unaffected.

  Found while authoring the TFTP root contracts (RFC-SWARM Phase 1), whose model is enum-heavy.
  **Blast radius was zero**: 0 occurrences across 127 in-tree `.llmll` sources and 1526
  committed JSON-ASTs, so no shipped verified claim was affected — the defect trapped newly
  written code, which is what a fill swarm produces. Full analysis, reproduction, and the
  runtime transcript: [`docs/design/finding-match-nullary-ctor-unsound.md`](docs/design/finding-match-nullary-ctor-unsound.md).
  Fixtures: `compiler/test/fixtures/match-nullary/`. Tests: MN-1..MN-6 (1411 examples, 0 failures).

### Known issue — FQ-CTOR-COLLIDE-1 (open, fail-closed)

- A parameter or `let` binder whose name equals the **lowercasing** of any in-scope ADT
  constructor collides with it in the emitted `.fq` namespace (`FixpointEmit.hs` applies
  `T.toLower` to constructor names), and liquid-fixpoint crashes with a sort error naming a type
  the function need not even mention. This **fails closed** — it is never a false SAFE — and is
  not fixed in this release. Analysis and recommended fix:
  [`docs/design/finding-fq-ctor-name-collision.md`](docs/design/finding-fq-ctor-name-collision.md).

## v0.14.65 — feat: SRC-CONJ-1 per-conjunct `:source` provenance (2026-07-24)

### Added — multi-clause contract sides keep every clause's citation (JSON-AST 0.9.0)

- **The G2 close-out.** Since v0.6, and-combining multiple `(pre ...)` clauses dropped every
  `:source` annotation as "ambiguous provenance" (`LLMLL.md` §4.6), so a function whose
  precondition encodes two distinct RFC clauses could not carry both citations. Each authored
  clause now keeps its own `:source`: `Contract` gains a parse-time-only
  `contractPreClauses`/`contractPostClauses :: [ProvClause]` channel beside the untouched
  and-folded scalar predicates. Multiple `(post ...)` clauses are newly accepted, symmetric with
  `pre` (§12 grammar).
- **JSON-AST 0.9.0.** Additive `pre_clauses`/`post_clauses` arrays (new `ContractClause` def:
  `{"expr", "source"?}`), mutually exclusive with the scalar `pre`/`pre_source` shape; a
  one-element array normalizes to the scalar shape; the emitter writes the array form only for
  2+ clauses, so existing corpus output is byte-identical and multi-clause programs now
  round-trip faithfully (previously lossy). Readers accept 0.8.0/0.7.0/0.6.0. Also fixes a
  pre-existing schema drift: `pre_source`/`post_source` were never listed in the schema despite
  `additionalProperties: false`, so every `:source`-carrying JSON-AST was schema-invalid since
  v0.6.
- **Report and sidecar threading.** `EvidenceRecord` gains `erSources`; `--trust-report --json`
  emits `pre_sources`/`post_sources` arrays in author order (the index surface for the upcoming
  RFC-COV-1 coverage lint); `.verified.json` records carry `sources` (symmetric codec, additive
  back-compat). `contractVouched` (Cascade L3(d)) generalizes: a multi-clause side is vouched
  only when EVERY conjunct carries `:source`; before this release such a contract was
  structurally unvouchable because the sources were already dropped.
- **Verification-inert.** The VC surface consumes only the folded scalars: `.fq` output is
  byte-identical with and without per-clause sources (regression SC6-1), and `:source` stays
  outside `canonicalDefEvidenceHash`, so no sidecar re-verify wave. Phase 1 gate of the
  RFC-SWARM roadmap (SRC-CONJ-1 default, decided before TFTP root authoring).
- **1405 Haskell examples, 0 failures** (Python suite unchanged at 45); refute-crux corpus
  41/41 unchanged; version-gate and doc-claims gates green.

## v0.14.64 — fix: map-store conditional bodies verify body-faithfully (2026-07-24)

### Fixed — a conditional in a map-returning body no longer falls back to contract-only

- **Coverage hole.** A conditional (`if`) inside a map-returning body fell back from body-faithful
  verification — both a map-valued `if` (`(if c (map-put …) bal)`) and a conditional stored value
  (`(map-put bal a (if c …))`) — even though straight-line stores reflect and refute correctly. Under
  `--strict-verified-core` a *wrong* conditional-map body passed via the contract-only fallback instead of
  being refuted; the body-faithful map fragment was limited to straight-line store bodies.
- **Fix.** `mapRetChain` (`FixpointEmit.hs`) now returns a guarded `MapRetTree`, and the map-return emission
  path-splits it into one guard-conjoined component-pin constraint per arm with arm-localized provenance
  (`body-post-then`/`-else`); `expandMapLets` if-floats a conditional stored value out of a strict, pure,
  call-free `map-put`/`bytes-set`/`+`/`-` argument, reducing it to the map-valued-`if` case. Reflection stays
  in the QF-AUFLIA array class (`select`/`store` under a Boolean case-split); the 4096-path cap is preserved;
  emission is activation-gated so non-map functions emit byte-identical `.fq`. No `FQ` ite constructor, no CLI
  or schema change. **Strictly trust-tightening**: a wrong conditional-map body now refutes body-faithfully.
- Surfaced by the minimal-agent solver-catches campaign (F-011.3). **1391 Haskell examples, 0 failures**
  (Python suite unchanged at 45); refute-crux corpus 41/41 unchanged.

## v0.14.63 — fix: map/bytes ops in the property-test evaluator (2026-07-23)

### Fixed — `llmll test` property-checks map/bytes code instead of skipping it

- **Discard, not skip.** The static property evaluator (`evalBuiltinApp` in `Contracts.hs`, driving
  `llmll test` via `PBT.hs`) had no reduction clauses for `map-has`/`map-get`/`map-put`/`map-empty` or
  `bytes-get`/`bytes-set`/`bytes-zero`/`bytes-length`, so every `check` body calling one failed to reduce,
  QuickCheck discarded all samples, and the property reported **`Skipped`** with no `tested` evidence. Now
  those bodies reduce: present-key and in-bounds reads evaluate and count.
- **Precondition-guarded discard.** A sample that violates a callee precondition — an absent key for
  `map-get`, an out-of-bounds index for `bytes-get` (§13.12) — is **discarded**, contributing to neither the
  pass count nor a falsification, rather than fabricating a value. `map-has` is total; `map-get`/`bytes-get`
  are partial. Maps use a McCarthy store-chain (last-writer-wins); `buildFuncEnv` reifies a whole-body
  `bytes-zero`'s declared `bytes[n]` length so `bytes-get` can decide the bound. This keeps the §4.4.5
  PBT-Lift sound: a fabricated pass on an out-of-precondition read would mint unsound `tested` evidence.
- **Verify path unchanged.** `FixpointEmit.hs` and the SMT trust closure are untouched; map/bytes still
  verify in the QF-LIA array class (§5.3.3). Spec gap closed: the precondition-guarded discard semantics is
  now stated in `LLMLL.md §4.4.5`. No CLI, flag, or schema change. **1384 Haskell examples, 0 failures**
  (Python suite unchanged at 45).

## v0.14.62 — fix: boolean-return sort for annotation-less predicate helpers (2026-07-21)

### Fixed — `verify` no longer crashes liquid-fixpoint on a boolean predicate used as an `if`-guard

- **Sort crash.** An annotation-less, post-less function with a syntactically boolean body (e.g. a predicate
  `(and (>= x 0) (< x 10))`) had its opaque call-result binder default to `FQInt` in CallVC (`calleeRetSort`,
  `FixpointEmit.hs`), while an enclosing `if`-guard consuming it elaborated `&&` at `Bool` — liquid-fixpoint
  crashed with `Sort mismatch at argument #1 for function (declare-fun and (Bool Bool) Bool) supplied Int`.
  Regression of the BOOL-FRAG migration (v0.14.14). `examples/conways_life_json_verifier` verifies **SAFE**
  again, with `next-cell`/`count-neighbors` back to body-faithful `verified (liquid-fixpoint)`.
- **Fix.** `buildContractEnvWith` synthesises a `TBool` return type for exactly that case — no declared
  return type **and** no post **and** a syntactically boolean body — so `calleeRetSort` sorts the binder
  `FQBool`. New helpers `bodyIsBoolean`/`isBoolHead` reuse `exprToPred` for leaf op-classification and recurse
  through `if`/`let`/`match` control forms. Scoped conservatively: an explicit return type or a result-typing
  post suppresses synthesis, and int/arithmetic bodies are never mis-sorted (the in-file `neighbor-alive` int
  body stays `FQInt`).
- No CLI, flag, or schema change. Surfaced by the examples audit
  ([`docs/design/examples-audit-2026-07-20-compiler-followups.md`](docs/design/examples-audit-2026-07-20-compiler-followups.md) R1). **1370 Haskell examples, 0 failures** (Python suite unchanged at 45).

## v0.14.61 — R8: incremental patch re-verification (2026-07-20)

### Changed — `patch` re-verifies only the patched function, not the whole module

- **Sliced re-verify.** `llmll patch` re-verified the **whole merged module** on every fill
  (`reVerify` over all statements). It now re-verifies only the **patched function `{F}`**. The slice is
  **sound and complete**, not heuristic: a patch fills a *body*-position hole (contract-position holes are
  excluded from checkout, `HoleAnalysis`), so no contract changes; and VCs are assume-guarantee modular
  (`FixpointEmit` has no cross-function body coupling), so every other function's body-VC is
  character-identical. Therefore re-verifying `{F}` discharges exactly the obligations that changed.
  Design + soundness argument: `docs/design/incremental-reverify-r8-proposal.md`.
- **Implementation.** New `EmitOptions.emitBodyVCTargets :: Maybe [Name]` (`Nothing` = all, the default —
  every existing caller is unchanged; `Just [F]` = emit only F's body-VC, all contracts still registered as
  context). `PatchApply.patchTargetFns` resolves `F` from the patch op paths and **fails safe** to
  whole-module (`Nothing`) on anything unresolvable — a `/statements/-` refine-style add, ops spanning >1
  statement, or an out-of-range index. No schema/trust/verdict change: identical SAFE/UNSAFE, fewer
  constraints emitted and solved.
- Verdict-preservation is proven: every existing patch test passes through the sliced path, plus 4 new
  `patchTargetFns` unit tests. **1368 examples, 0 failures.** The repair-loop latency benchmark (the
  roadmap's O(module)→O(1) demonstration) is deferred residue — the correctness/soundness is the shipped part.

## v0.14.60 — OBLIG-PBT-5b: `tested-joint` evidence tier (2026-07-20)

### Added — a real `tested-joint` tier for jointly PBT-tested functions

- **`DLTestedJoint`.** A `(check … :subjects [f g])` property tests N functions jointly from one body;
  crediting each as fully `tested` over-credits. 5a (v0.10.7) handled this by *demoting* joint-only clauses
  to `asserted` — sound, but it hid that the function was tested at all. 5b introduces a genuine
  `tested-joint` tier in the evidence lattice: **below `tested`, above `asserted`, incomparable to
  `contract-checked`**. Joint-only `DLTested` post clauses are reclassified to `DLTestedJoint`
  (`reclassifyJointCS`) **before** the transitive meet, so the tier **propagates to callers** through
  `evidenceMeet`. The EVID-0 lattice laws (commutativity, associativity — 125 triples) were extended and
  stay green.
- **Report surface.** Additive `tested_joint` count in `summary` and every `tier_profile`; the
  `tested-joint` label on level fields; `trust_report_version` **1.5.0 → 1.6.0**
  (`docs/llmll-trust-report.schema.json` updated). `EvidenceRecord.scope` was intentionally **not** added —
  joint-ness is derived at report-build from the shared witness hashes (`computeJointHashes`), avoiding a
  persisted field. `SpecCoverage` counts `tested-joint` with `tested`; the proof-artifact anti-laundering
  maps it to the positive `TTested` tier.
- Tests: lattice placement + EVID-0 laws extended, `J1`/`J2` retargeted to the tier, new `J7` label/count.
  **1364 examples, 0 failures.**

## v0.14.59 — CONTRACT-READ-LINT: `contract-read-oob` warning (2026-07-20)

### Added — a non-blocking warning for verified-yet-always-crashing contract reads

- **`contract-read-oob`.** A literal index against a literal `bytes[n]` bound in a `pre`/`post` — e.g.
  `(bytes-get b 9)` where `b : bytes[8]` — now emits a warning. The contract type-checks and can verify
  (contract reads are total selects, `FixpointEmit.exprToPred`), but its generated runtime assertion
  aborts on **every** execution. The lint is syntactic (no solver), **non-blocking** (stays a warning
  even under `--strict`), and **JSON-visible** via `diagKind` (the F-001 lesson: a guardrail invisible to
  `--json` is invisible to agents). `TypeCheck.lintContractReads` + `Diagnostic.mkContractReadOOBWarning`,
  hooked into `SDef` / `SDefShell` / `SDefLogic`; a non-literal (variable) index is left alone (outside the
  decidable slice). Implements disposition (c) of
  [`docs/design/contract-position-reads-disposition.md`](docs/design/contract-position-reads-disposition.md);
  the `map-get`-without-`map-has` heuristic tier and the Dafny-style well-formedness side-obligation
  (disposition (b)) remain deferred. **+6 tests; +1 DRIFT-CT-2 fixture (`contract-read-oob`, now 11).**

## v0.14.58 — DRIFT-CT-2: non-`check` subcommand support + `checkout` claim (2026-07-20)

### Added — gate can now exercise subcommands beyond `check`

- **`@cmd` header + `output:<substr>` verdict.** A DRIFT-CT-2 fixture can now run a subcommand other than
  `check` (`@cmd: checkout {file}`, with `{file}` → fixture path) and assert a cited message appears anywhere
  in the output (`output:<substr>`, subcommand-agnostic). New fixture `checkout-requires-astjson` guards that
  `checkout` rejects a `.llmll` source with "checkout requires .ast.json input …" (the claim matched the
  compiler — no doc fix needed). 10 fixtures, all pass. Remaining seams recorded as known gaps in
  `scripts/doc-claims/README.md`: `patch` multi-file claims (need a checked-out `.ast.json` + `patch.json`)
  and JSON-AST-only claims (a `.ast.json` fixture can't carry the `;;`-comment header).

## v0.14.57 — DRIFT-CT-2 broadened; `export`/`trust` ordering cluster corrected (2026-07-20)

### Fixed — stale "must appear before defs" ordering cluster

- **`export` and `(trust …)` are position-independent**, not "must appear before the first def". A
  systematic pass over the docs' restriction claims (extending the 2026-07-19 sweep) found the same stale
  root as the already-corrected imports rule: `export`-after-def and `(trust …)`-after-def both check
  `✅ OK`. Corrected `getting-started.md §4.9` (export), `LLMLL.md §4.4.3` (trust), and the `LLMLL.md §12`
  export grammar comment. (The `open` grammar comment is left as-is — `open` is a multi-file construct not
  exercised by this pass.)

### Added — DRIFT-CT-2 coverage broadened 4 → 9 fixtures

- New fixtures: `decl-order-independent` (export/trust after def), `do-notation-discard-warn` (the DO-1
  warning — the gap left in v0.14.56), `missing-capability`, `def-logic-rejected`, `letrec-default-rejected`.
  The gate's `@expect` now accepts an optional `:<substring>` on `parse-error`/`check-error` (matching the
  existing `warn:<substr>`) to pin a cited diagnostic message, not just the verdict class. All 9 pass; the
  drift-catch behaviour was re-verified. See `scripts/doc-claims/README.md`.

## v0.14.56 — DRIFT-CT-2 doc-claim drift gate (2026-07-20)

### Added — `scripts/doc_claims_gate.sh` (DRIFT-CT-2)

- **Doc-claim drift gate.** A CI gate (sibling of the DRIFT-CI-1 version gate) that runs each documented
  *restriction claim* through `llmll check` and fails when the doc and the compiler disagree — the class of
  stale gotcha the 2026-07-19 external critique tripped over (docs claiming a program is rejected/broken
  while the compiler accepts it). Fixtures live in `scripts/doc-claims/` with `@doc`/`@expect`/`@claim`
  headers (verdicts: `check-ok` / `parse-error` / `check-error` / `warn:<substr>`); on failure the gate
  names the exact doc section to fix. Seeded with the four claims from the 2026-07-19 sweep. Wired into the
  `spec-roundtrip` job of `.github/workflows/version-gate.yml` (runs against the freshly-built binary;
  SKIPs cleanly when no binary is present). Format + how-to-extend: `scripts/doc-claims/README.md`.

## v0.14.55 — `def-invariant` §11.4 doc reconciliation (DEFINV-1) (2026-07-20)

### Fixed — stale `def-invariant` claim in `LLMLL.md §11.4`

- **`def-invariant` parses in `.llmll` source.** §11.4 claimed the S-expression parser *rejects*
  `def-invariant` ("known compiler bug, fix in progress"); in fact the `(def-invariant …)` form landed in
  the S-expression parser in v0.12.1 (`Parser.hs`) and parses today (verified `✅ OK`). Corrected §11.4:
  it parses on **both** surfaces (JSON-AST + S-expression), is type-checked, and registers as a VC-env
  predicate. The **enforcement** gap it also documents — Z3 verification of declared invariants on AST
  merge — is genuinely deferred (**Phase 2b**) and unchanged. Closes `DEFINV-1`, the last of the four
  "agent-hostile edges" from the 2026-07-19 external critique — all four resolved as stale-doc or
  already-implemented, none a live compiler defect.

## v0.14.54 — license-metadata reconciliation + 2026-07-19 external-critique triage (2026-07-19)

### Fixed — `LIC-1`: build manifests declared the wrong license

- **License metadata.** `compiler/package.yaml` and `compiler/llmll.cabal` declared `MIT` while
  `LICENSE`, `README.md`, and `docs/one-pager.md` all state **GPLv3 with the LLMLL Runtime Library
  Exception**. Both manifests corrected `MIT → GPL-3`. The exception text (v1.0) was already present in
  `LICENSE`; no license-text change was needed. Surfaced by an external review of `main` at `e284fe0`.

### Fixed — stale `getting-started.md` gotchas (surfaced by the critique)

- **Three "agent-hostile edges" were verified to be stale documentation, not compiler bugs**, and
  corrected in `docs/getting-started.md §4.7/§4.8`:
  - **List literals in `if` branches** — the docs warned of a `unexpected ]` parse error; the exact
    doc-failing expression now parses `✅ OK`. Restriction removed; `let`-hoist noted as no-longer-required.
  - **Imports after definitions** — the docs claimed they are "silently ignored"; a capability import
    placed *after* a `def-shell` is honored (`✅ OK`). Corrected to "position does not matter"; the stale
    `(import wasi.io stdout)` example fixed to the real `(import wasi.io (capability stdout))` form.
  - **`do`-notation intermediate-command discard** — the compiler already warns (`checkDiscardedCommand`,
    `TypeCheck.hs:1592`); only the hard-error tightening remains deferred by design.
  - Verified against the parser/checker (`Parser.hs`/`TypeCheck.hs` unchanged since `v0.14.51`).

### Docs — external-critique triage captured

- **`docs/design/critique-2026-07-19-triage.md`.** Records + adjudicates the external review of
  `e284fe0`/v0.14.53. New defect: `LIC-1` (fixed above). The three edges above are logged as
  **verified-stale-doc** (§5 verification outcome). Strategic points re-raise already-settled items (large
  trusted base → Path B declined; spec adequacy → known central risk; crypto opacity → CRYPTO-1); the
  review's strategic read matches the project's own `strategic-positioning`.

## v0.14.53 — decomposition-trust meet for `refine` cascades (2026-07-19)

### Added — `unvouched_cdp_meet`: the decomposition's weakest-link CDP, report-only

- **The decomposition-trust meet.** `verify --trust-report --cdp` now reports, per function, an
  `unvouched_cdp_meet` inside its `discriminative_axis`: the lattice meet (weakest) of CDP scores over
  the function's **unvouched** transitive-callee subtree — a cascade with one hollow invented
  sub-contract reads weak even when every node is `verified`. Two-axis (professor-hardened): a
  `quality_meet` (`hollow ⊏ scored ⊏ strong`; `null` when nothing is measured, kept distinct from
  hollow) plus a `coverage` object (`measured` / `unmeasured` / `in_scope_total` / `excluded_vouched` /
  `excluded_fns`). The abstain warnings and the epistemic `WarnSpecInconsistentOrUnproven` land in
  `unmeasured`, never folded into the meet. New `LLMLL.CDP` types `DecompQuality`/`UnvouchedMeet`;
  `computeDecompMeet` in `LLMLL.TrustReport`.
- **Scope = unvouched, self-revealing exclusion.** The meet ranges only over subtree contracts with an
  unvouched clause (a present `pre`/`post` lacking `:source`); a fully `:source`-anchored contract is
  excluded but **named** in `excluded_fns`, so a forged `:source` exclusion of a hollow spawn is
  visible. A contract-only cyclic-SCC member sets `floored_by_cycle` without collapsing the quality meet.
- **Report-only.** Like `refuted` / `termination_unverified`, `unvouched_cdp_meet` is an orthogonal
  informational marker — it never feeds `effectiveLevel`, the `DisplayLevel`, admission, or
  `--strict-verified-core`. No solver: a pure fold over the already-computed CDP map, nothing enters
  `Σ_auto`. A cooperative-author diagnostic; adversarial forgery is caught by R5 (Layer 3(c)), not this
  signal. Closes Cascading-Refinement **Layer 3(d)** — the last item in the line (design
  [`cascading-refinement-proposal.md`](docs/design/cascading-refinement-proposal.md) Rev 8, three
  professor rounds).

**Tests:** 1279 Haskell, 45 Python (+6: forged-exclusion self-revealing, cooperative hollow drag,
all-unmeasured reads null, cyclic member keeps real CDP, all-vouched, classify + self-exclusion). No
AST-schema or CLI-surface change; `trust_report_version` stays 1.5.0 (additive field, per the
`joint_pbt_witnesses` precedent).

## v0.14.52 — feasibility (no-miracle) gate for `refine` (2026-07-18)

### Added — a spawned sub-contract no body can discharge is rejected at refine time

- **The feasibility (no-miracle) gate.** `refine` now rejects a spawned sub-contract that is
  *infeasible* — some input satisfies `pre` while **no** `result` satisfies the post (including the
  return-type refinement): `∃input. pre ∧ ∀result. ¬post`. The query is discharged by z3 under the
  `qsat` tactic — a **complete** decision for the quantified-LIA fragment — and returns a **minimal
  witnessing input**, reported in the rejection (`refine gate: spawned sub-contract 'G' is infeasible
  — at <witness> (satisfying pre) no result satisfies the postcondition; tighten the precondition`).
  New module `LLMLL.Feasibility` (driver `firstInfeasibleSpawn` in `refineGate`).
- **Runs before the CDP vacuity pass** — an infeasible spawn short-circuits, so the heavier
  per-candidate Horn loop never runs on a contract no body can satisfy. **Fail-open**: no z3, or a
  result outside the decidable Int/Bool LIA fragment (unknown/abstain), falls through to the CDP
  vacuity gate unchanged — the gate only ever *rejects* on a definitive `Infeasible`.
- **Realizes the reserved CDP `WarnSpecInconsistentOrUnproven` check** — the Ω-independent
  semantic-UNSAT query the CDP module reserved (a structurally different existential SAT query, not an
  extension of the per-candidate Horn-refutation loop) is now the refine feasibility gate.
  `FixpointEmit` exports the refinement-resolution helpers it needs (`resolveAllRefinements`,
  `resolveAliasTy`, `renameVar`). Closes Cascading-Refinement **Layer 3 — feasibility gate**
  (design [`cascading-refinement-proposal.md`](docs/design/cascading-refinement-proposal.md) Rev 5);
  the decomposition-trust meet remains the sole open Layer-3 item.

**Tests:** 1273 Haskell, 45 Python (+12: feasibility verdicts — infeasible/feasible/abstain,
minimal-witness rendering, the fail-open no-z3 / out-of-fragment paths, run-before-CDP ordering). No
schema or CLI-surface change. `make refute-crux-gate` passes.

## v0.14.51 — string map KEYS: `{int, string}` is the key class — Lever A closed (2026-07-17)

### Added — string-keyed maps verify (the final Lever-A item)

- **`map[string,int]`, `map[string,bool]`, `map[string,string]` join the array-encoded class.** The arrays
  proposal's §87 v1.5 sketch, delivered: literal keys reflect via the STRLIT interned constants, ground
  pairwise **distinctness makes literal-keyed reasoning exact** (the aliased-key crux, string edition:
  `put "a", put "b", get "a"` proves 1 and refutes 2 — `strlit_a ≠ strlit_b` excludes the identifying model),
  and **literal/var key pairs get no fact** (§87(iii): a var key may equal any literal — the no-fact refute is
  a genuine counterexample). The theory is key-sort polymorphic, so keys are **self-sorting terms**
  (`mapKeyTerm`: int-in-context or strlit/Str-carrier) — no key-sort threading; the `$has`/`$val` binder
  sorts generalize per dimension (`mapHasArraySort`/`mapValArraySort`, four combos; return markers via
  `isMapArrRetSort`/`markerValSort`/`markerHasSort`). Presence-gated var-key reads, both-dims
  `map[string,string]`, and string-keyed map **returns** all verify body-faithfully.
- **The typechecker's v1 int-only key gate widens** to `{int, string}` (key argument checked against the
  map's key sort; other key sorts stay a diagnostic on the operation — `map[bool,int]` etc.).
  `boolValuedMapTy` goes key-agnostic (string-keyed bool maps get the 0/1 bridge + range facts).
- **Lever A is closed**: bytes + maps over `{int,string}` keys × `{int,bool,string}` values, construction
  included, RMW/returns/tail-call composition/cross-module A-G included. Remaining fallback (deliberate):
  non-`{int,string}` key sorts; direct reads on `(map-empty)`.

**Tests:** 1261 Haskell, 45 Python (+3: A2S-15 aliased-key crux, A2S-16 literal/var no-fact + presence-gated
var keys, A2S-17 both-dims + string-keyed returns; `A0-2`/`A3-3` retargeted to the bool-key residue). No
schema or CLI-surface change. `make refute-crux-gate` passes.

## v0.14.50 — string `map-empty` construction verifies + two latent elaborator crashes fixed (2026-07-17)

### Fixed — two elaborator crashes latent since the A2.2-string arc

- **A bare `(map-empty)` tail on a string-map return crashed** (`mapRetChain`'s terminal emitted the int
  default `Map_default 0` against the Str-sorted `result$val` binder — "Cannot unify Str with int") and
  **a contract-channel strlit put on `map-empty` crashed** (the type-blind `mapPairTermsC` stored a `strlit_`
  into an int-defaulted array). Both surfaced by residue probing; both now **verify** (below), and the
  degenerate direct-get/has-on-`(map-empty)` shape — an always-absent read whose int default meets Str
  contexts ill-sorted — routes to fallback in every channel (never a crash).

### Added — string `map-empty` construction (a Lever-A residue item closed)

- **Type-directed defaults.** `Map_default` is polymorphic in the fixpoint theory (`func(2, [@(1);
  (Map_t @(0) @(1))])` — the default *element* determines the array type), so the element sort is now
  **inferred from the put value** (a strlit or Str-carrier var ⟹ a Str-defaulted value array,
  `defaultElemFor FQStr` = the interned empty-string constant, semantically inert under the presence
  obligation) and threaded to the `map-empty` leaf (`mapPairTermsBWith`/`mapPairTermsC`; `mapRetChain` passes
  the return type's element sort). `(map-put (map-empty) k "x")` chains — body, contract, and
  string-map-return positions — now verify body-faithfully, with the wrong-value twin refuted; the
  Str-defaulted root is self-identifying downstream (`strValArrTerm`), so gets over fresh string stores sort
  correctly. Int/bool empty-rooted chains are byte-equivalent (regression-checked).
- **Residue (clean fallback):** direct get/has on `(map-empty)`; a string-**param** put value on an
  empty-rooted chain in a **contract** clause (the type-blind channel cannot infer a var's sort —
  `badPutValue` blocks it; the body channel infers it from the `SortEnv` and verifies). String **keys**
  remain the sole open Lever-A item.

**Tests:** 1258 Haskell, 45 Python (+1 A2S-14 crash regressions; A2S-5 retargeted — construction now
verifies, the degenerate shapes pin the fallback). No schema or CLI-surface change. `make refute-crux-gate`
passes.

## v0.14.49 — MAP-RET-CALL: map-returning tail calls verify via component pins (A4 finding F-2) (2026-07-17)

### Added — a map-returning function may delegate to a map-returning callee

- **The bare tail call composes.** `(revoke tokens tid)` as the whole body of a map-returning function —
  the composition the A4 wave agent tried and had rejected (it inlined instead) — now verifies
  body-faithfully. The whole-map equation `result = rVar` the two-array split cannot express becomes the
  **component pins** `result$has = rVar$has ∧ result$val = rVar$val` (the `mapRetChain` terminal discipline
  extended to call tails). Everything else was already on the path: the callee's post rides
  component-substituted (`resultCompSubst`, value-sort-aware since v0.14.47) and the callee-result
  components are declared (`compLBs`). Works for int-, bool-, and string-valued maps; branch tails where
  **every** arm is a map-returning call result compose too.
- **Refuse-not-pad preserved.** A mixed tail (a call arm alongside a param/pure-map arm), and the original
  ill-sorted case (an int-returning function with an array-sorted tail), still route to contract-only
  fallback whole — the new path is gated on `mapArrEncodableTy` of the return type and on **every**
  flattened path's tail being a marker-sorted call result (`pinnableTail`).
- Refutation stays exact: the wrong-status twin (caller post demanding `"active"` from a `"revoked"`-posting
  callee) is refuted, not vacuous.

**Tests:** 1257 Haskell, 45 Python (+2: A2S-12 the F-2 witness pair, A2S-13 int-map tail + mixed-tail
fallback guard). No schema or CLI-surface change. `make refute-crux-gate` passes (now with the v0.14.48
stack-build preflight, finding F-3).

## v0.14.48 — STRLIT body-channel flip: string-conditional bodies verify (closes the Stage-1 watch item) (2026-07-17)

### Added — string comparisons in bodies are body-faithful (was vacuous-SAFE fallback)

- **String-conditional bodies discharge.** The STRLIT Stage-1 watch item ("string-conditional `if`-bodies
  fall back → vacuous SAFE") is closed with the body-channel flip, three small widenings mirroring the
  contract channel: the guard channel (`classifyGuardM`) admits **Str-sorted vars** (an ANF-hoisted string
  map-get result / a seeded put-value param can only be a comparison operand — a bare Str guard atom is
  ill-typed upstream) and **string literals** (interned via `strlitConst`); `bodyToPredM` admits **Str vars**
  and **string-literal leaves**. So `(if (= (map-get m k) "active") … …)`, string-literal branch leaves
  (`(if (map-has m k) (map-get m k) "none")`), and `(= t "status")` as a bool result all verify body-faithfully.
- **The A4 introspect shape is fully discriminative** (A2S-11): RFC 7662 §2.2 `active` = present ∧
  status-`"active"` ∧ within validity window (two maps — `map[int,string]` status + `map[int,int]` expiry) —
  the reference body verifies SAFE and the classic **expiry-skip bug refutes** (was a vacuous SAFE through
  the fallback). Discovered as a Phase-2 blocker of the A4 flagship plan: the central seed contract's natural
  body shape was Advisory-only.
- **`strlitConst`/`strlitLen` moved to `FixpointIR`** (re-exported from `FixpointEmit`) so the guard channel
  interns literals without an import cycle.

**Tests:** 1255 Haskell, 45 Python (+1 A2S-11; the two carrier-rejection tests retargeted to `FQList` — the
still-out carrier — with Str-acceptance twins, their second retargeting after BOOL-FRAG). No schema or
CLI-surface change. `make refute-crux-gate` 26/26.

## v0.14.47 — A2.2-string residue lift: string-map returns + param-string put values (2026-07-17)

### Added — the A4-flagship API shapes verify (Phase 1 of the A4 plan)

- **String-valued map RETURNS reflect.** `revoke : map[int,string] → map[int,string]` (put-then-return) now
  verifies body-faithfully, with its wrong-status twin refuted. The string-map return marker is
  `strMapArraySort` (`FQArr FQInt FQStr`, mirroring the int-map convention where the marker equals the
  component sort); every `== mapArraySort` return-dispatch site widens via `isMapArrRetSort` /
  `markerValSort` (result$val binders, `mapRetChain` gate + `MRGet` value sort, call-context component
  declarations ×2, callee-return marker (`syntMapRetSort`), cross-call component substitution, CallVC
  result seeding, flatten-side component LetBindings, `arrayResultPath`).
- **Param-string put values reflect.** `set(m, k, s)` with `s : string` round-trips (`(= result s)` SAFE,
  literal twin refuted — not vacuous). The coordinated change: `mapPutValVars` (a type-blind collector over
  contract + body) feeds both the `FQStr` carrier binder (via `measureVars`) and the body-channel `SortEnv`
  seeding (`strParamKeys`), so `strValTerm`'s var leg resolves.
- **String RMW chains** discharge (`MRGet` carries the chain's value sort — a let-bound string-map read feeds
  the put back), and **cross-call string-map assume-guarantee** works: a caller failing a callee's
  string-status pre (`(= (map-get m k) "active")`) is refuted at the call site (the A2.1 substitution probed
  on string maps — the A4 plan's watch item, cleared).
- **Remaining residue** (clean fallback, never a crash): string `map-empty` construction (its `Map_default 0`
  value root is int-sorted) and string **keys**. Design records updated:
  `docs/design/string-valued-maps-proposal.md`, `docs/design/a4-flagship-token-revocation-plan.md` (Phase 1 ✅).

**Tests:** 1254 Haskell, 45 Python (+4: A2S-7 return/revoke shape, A2S-8 param put value, A2S-9 string RMW,
A2S-10 cross-call A-G; `A3-3`/`A2S-5` retargeted to the post-lift residue — string keys / map-empty
construction). No schema or CLI-surface change. `make refute-crux-gate` 26/26.

## v0.14.46 — A2.2-string: string-valued maps (`map[int,string]`) reflect + STRLIT range-fact crash fix (2026-07-17)

### Added — string-valued maps discharge (was Advisory)

- **`map[int,string]` joins the array-encoded map class.** The value component array threads a genuine `Str`
  element sort (`$val : (Map_t int Str)`, via `mapValArraySort`), so a `map-get` is a `Str`-EUF term comparable
  to the interned `strlit_` constants (STRLIT) — the "unreflected symbol" firewall that routed these clauses to
  Advisory is gone (the STRLIT enabler, arrays proposal §89). Get-after-put with a string value **verifies**;
  value distinctness across distinct keys rides `injectStrLitDistinct` (`get(k=1) ≠ "b"` proves; the `= "b"`
  twin refutes); `string-length` on a map value composes with STRLIT Stage 2 (`injectStrLitLen`). The two
  body-channel result/value sorts are recovered from the `SortEnv` (`mapSelValSort` / `strValTerm`) — no
  `AliasMap` needed. `isStrLike` / `mapStrValuedTy` widen the admission gate; `okVal` admits a string put value.
- **Scope:** Stage 1 = string-**literal** values on param maps (the status/tag-map pattern), get / put /
  comparison / length. String-**param** put values, string-valued map **returns**, string `map-empty`
  construction, and string **keys** are staged follow-ons — each routes to Advisory fallback (sound, never a
  crash; firewalled via `mapClauseBlocked` + a `SortEnv`-rooted string-array check). Whole-map equality stays
  firewalled (`wholeArrEqClause`, value-type-agnostic). Design record + professor fold:
  `docs/design/string-valued-maps-proposal.md`.

### Fixed — STRLIT range-fact crash (latent since v0.14.44)

- **`injectRangeFacts` no longer emits `strlit_… >= 0`.** The measure-range catch-all treated an interned
  nullary `Str` literal constant as an int measure application and conjoined `strlit_… >= 0` (`Str >= int`,
  ill-sorted) → liquid-fixpoint crash. It fires whenever a string literal meets `string-length` or a
  string-valued map value. `injectRangeFacts` now excludes `strlit_`-prefixed constants. Regression: A2S-6.

**Tests:** 1250 Haskell, 45 Python (+6 A2.2-string: emission, get-after-put crux, value distinctness, length
composition, firewall-no-crash, strlit range-fact regression; `A2-8`/`A3-3`/`A3-4` retargeted to the new
residue boundary — string values reflect, returns/construction deferred). No schema or CLI-surface change.
`make refute-crux-gate` 26/26.

## v0.14.45 — STRLIT Stage 2: literal-length pinning (`strLen(strlit_s) = |s|`, code points) (2026-07-14)

### Added — string-literal length-consistency reasoning discharges

- **Each string literal's code-point length is now pinned.** A ground fact `strLen(strlit_s) = |s|` is conjoined
  per occurring literal constant (`injectStrLitLen`, a pure per-constraint pass mirroring `injectStrLitDistinct`,
  over LHS ∪ RHS), composing with the existing `string-length → strLen` reflection. Length-consistency now
  discharges: under `pre (= s "GET")`, the goal `(= (string-length s) 3)` **verifies** (congruence:
  `strLen s = strLen strlit_GET = 3`) and the `= 5` twin **refutes**. Recovers the length-uniqueness completeness
  gap Stage 1 documented.
- **`|s|` is the code-point count** (`T.length s`), recovered exactly from the interned name (`strlitLen`:
  `strlitConst` emits fixed-width 6-hex per code point, so `(len − |"strlit_"|) / 6 = T.length s`). This matches
  the runtime `string_length` (`CodegenHs.hs:302-303`; `Data.Text.length` counts code points): `"😀"` (U+1F600)
  → **1** (not 4 bytes or 2 UTF-16 units), `"e" + U+0301` → **2**, `"é"` (U+00E9 precomposed) → **1**, `""` → **0**.
  A UTF-8 byte or UTF-16 word count is a §5.3.4 claim-accuracy break and is forbidden.
- **Sound by construction.** Each length fact is a true, mutually-consistent ground equation (`strLen`
  uninterpreted; `strlitConst` injectivity ⇒ one length per constant), so it only strengthens the hypothesis —
  it can close a spurious refute, never open one, and never contradicts (no vacuous SAFE unless a precondition is
  genuinely infeasible, which is correct). The extra `strLen` application makes the preamble sweep declare
  `strLen : (Str) → int` even when the program has no `string-length` call. Byte-inert without string literals.
- **Scope:** Stage 2 completes the STRLIT line (equality + distinctness + length). String *structure*
  (concat / substr / regex / interpreted length) stays out — word equations with length is open (Ganesh et al.,
  HVC 2012). Design record: `docs/design/string-literal-distinctness-proposal.md` (§Stage 2, SHIPPED).

**Tests:** 1244 Haskell, 45 Python (+3 STRLIT: length emission, length crux SAFE/UNSAFE, code-point convention
regression — ASCII / astral / combining / precomposed / empty). No schema or CLI-surface change.
`make refute-crux-gate` 26/26 (no example verdict flips).

## v0.14.44 — STRLIT: string literals reflect into `Σ_auto` via interned constants + distinctness (2026-07-14)

### Added — string-literal equality/distinctness discharges (was Advisory)

- **String literals now reflect.** A string literal reflects to a content-interned nullary `Str` constant
  (`strlitConst`: each code point → fixed-width 6-hex, **injective** and sanitize-stable, so distinct literals
  never collide post-`sanitizeFQId` — a collision would be a false verify, so never a hash), and a ground
  pairwise-distinctness fact `c_i /= c_j` is conjoined over the occurring literal constants
  (`injectStrLitDistinct`, a pure per-constraint pass mirroring `injectRangeFacts`, over LHS ∪ RHS, distinct
  pairs only). Contracts like `(= method "GET")`, `pre (= s "admin")`, and string-tag / enum-as-string patterns
  now **verify or refute** instead of routing to Advisory. The reflection flip and the distinctness pass land
  atomically: the flip alone is UNSAFE-unsound (a model identifying two literals spuriously refutes — §6.1 F2).
  Classifier follows by construction (`isQfLia = isJust . exprToPred`).
- **String params compared to a literal get an `FQStr` carrier binder** (`strEqOperandVars` widens the NIW
  measure-carrier mechanism) — else the reflected `s = strlit_…` carries a free var and the solver rejects it.
- **The injective encoding is soundness-load-bearing.** `"a-b"` and `"a_b"` intern to *distinct* constants
  (`strlit_…2d…` vs `strlit_…5f…`); a naive `-→_` escape would collapse them into a false verify.
  Probe-confirmed on the pinned fixpoint (nullary `Str` constant + `/=`, both verdicts).
- **Scope:** Stage 1 (reflection + distinctness). Literal-length pinning is **Stage 2 (deferred — the next
  step)**; string *structure* (concat / substr / regex) stays out (undecidable — word equations with length is
  open). Design record: `docs/design/string-literal-distinctness-proposal.md` (Rev 1).

**Tests:** 1241 Haskell, 45 Python (+6 STRLIT: emission, distinctness crux, literal/variable no-fact, duplicate
literal, injectivity/collision-avoidance, no-op; `CM-1`/`CM-3` retargeted — they codified the old
string-literals-out classification, now flipped; `CM-4` classify==emitter meta-test unchanged). No schema or
CLI-surface change. `make refute-crux-gate` 26/26.

## v0.14.43 — LEVER-A2.2: bool-valued maps discharge via the int-0/1 value bridge (2026-07-13)

### Added — `map[int,bool]` joins the array-encoded map class

- **Bool-valued maps verify statically.** `map[int,bool]` now rides the two-array encoding: `true`/`false`
  lower to `1`/`0` at the `map-put` value and at every `(map-get m k) = <bool-literal>` comparison
  (literal-bridge), and each occurring bool value read carries the ground fact `0 ≤ select(m$val, k) ≤ 1` —
  the byte-range discipline (`injectBoolValRangeFacts`) at the value sort, making the `{0,1}` encoding
  **exact** on occurring keys. Was Advisory fallback.
- **Closes a disequality-in-hypothesis spurious refutation.** A `pre (!= (map-get m k) true)` proving
  `post (= (map-get m k) false)` was wrongly **refuted**: over the unpinned ℤ range the solver picked value
  `2` (`2 ≠ 1`, yet `2 ≠ 0`). The value-range fact makes `(s ≠ 1) ⟹ (s = 0)` valid — verified. It also
  closes the get-vs-get disequality case a literal-only normalization could not (`(!= (map-get m k1) (map-get
  m k2))` transitively concludes `s ≠ 1` with no literal to normalize), and recovers the value-domain
  tautology `(=> (!= get true) (= get false))`.
- **Scope + fallback discipline.** Admissibility widens to `map[int,{int,bool}]` (`mapArrEncodableTy`); the
  re-guard (`boolMapUnsafe`) blocks only the ill-sorted shapes — a bare bool `map-get` in a boolean position
  (`not`/`and`/`or`/`if`), a get compared against a bool **variable**, and a bool-variable `map-put` value —
  which fall back whole, never ill-sorted FQ. Contract channel only; the body channel stays int-only.
  String-valued maps stay out (Str-EUF value arrays — future).
- **No-op guarantee.** An int-valued map's value select gets **no** `0 ≤ v ≤ 1` fact; the fact is scoped to
  bool-map `$val` arrays, so int/bytes `.fq` is byte-identical (the sole existing-test change is A2.1-5, which
  codified the old whole-fallback and is retargeted).

**Tests:** 1235 Haskell, 45 Python (+7: get-after-put crux + dropped-put twin, the spurious-refute witness,
get-vs-get disequality, the value-domain tautology, the false path, the int-map no-op, and the deferred-residue
fallbacks; A2.1-5 retargeted). No schema or CLI-surface change.

## v0.14.42 — COVERAGE-TIER: `--spec-coverage` reports the same tiers as `--trust-report` (2026-07-12)

### Fixed — coverage tiers now consistent with the trust report by construction

- **`verify --spec-coverage` printed `Verified: 0` beside the same tree's `--trust-report` `verified: 3`.** Two
  layers: the coverage call sites passed no evidence at all (`runCoverage … Map.empty`, a literal Sprint-3 TODO),
  and even fed the sidecar, `computeSummary` counted `verified` as `isVer pre && isVer post` — so every verified
  function, whose *own* precondition is `asserted` at its own site (it discharges at call sites, not in its body),
  fell into the `asserted` bucket. Coverage now classifies on the trust report's per-function headline level (the
  TRUST-PRE Position B rule — a precondition never floors the function's tier), via a new shared
  `TrustReport.entryHeadlineLevel` extracted from the four sites that had the tier logic copied verbatim. Coverage
  and trust tiers agree by construction, including the transitive-callee meet. A tree with no discharged sidecar
  still shows `Verified: 0` (correct — nothing proven yet).
- Same visit: a stale PBT multi-callee diagnostic told authors to "wait for `:subject` metadata in OBLIG-PBT-4"
  though `:subjects [f g]` is shipped and working; the message now points at the shipped annotation.

**Tests:** 1228 Haskell, 45 Python (+2: coverage-tier == trust-tier consistency on a verified-post/asserted-pre
function; the 2-arg own-post fallback). No verdict movement; `make refute-crux-gate` 26/26. No schema or CLI-surface
change.

## v0.14.41 — LEVER-A2.1: map discharge covers read-modify-write, cross-module, and map-returning shapes (2026-07-12)

### Added — three map-discharge deferrals lifted (Lever A stage A2.1)

- **Read-modify-write map bodies discharge.** `(map-put m k (+ (map-get m k) 1))` — the most common map shape —
  now verifies: `mapRetChain` peels a straight-line let-spine of `map-get`s and scalar defs terminating in a pure
  map term, each `map-get` emitting its presence PROVE obligation and an exact pin. Crux: the RMW post verifies,
  the wrong-increment twin refutes, and an RMW on an unproven key refutes at the inner `map-get`.
- **Cross-module map assume-guarantee discharges.** A contracted callee whose pre/post mentions map ops now
  participates in the caller's VC via component-aware `p$has`/`p$val` → caller-component substitution. A caller that
  proves the callee's `(map-has m k)` precondition verifies; **a caller that does not proves refutes at the call
  site** — the earlier development state where this bad twin wrongly passed (a shared-name substitution
  false-positive) was the dropped-obligation bug this stage had to close, and it does. Map-returning callee results
  (`result$has`/`result$val`) participate too.
- **Infrastructure:** a new `FQMapArr` sort constructor distinguishes map returns from bytes returns at the Haskell
  level (both were `FQArr FQInt FQInt`, so map-return guards misfired on bytes returns and had broken an A1 crux)
  while rendering **identically** to `(Map_t int int)` in `.fq` — a 68-file sweep is byte-identical to v0.14.40.
- **Still deferred (A2.2):** string/bool-**valued** maps fall back whole — bool values are solver-feasible via an
  int-0/1 bridge (probe-confirmed) but need value-path threading; string values need `Str`-EUF value arrays.

**Tests:** 1226 Haskell, 45 Python (+4: cross-call emission + solver crux, RMW emission + solver crux,
deferred-residue whole-fallback). `make refute-crux-gate` 26/26. The `extractQualifiers` watch-item was
investigated and is correct as-is (array preds are caught by the existing free-symbol guard; body VCs are fully
path-enumerated, so qualifiers only feed wf-inference).

## v0.14.40 — CLASSIFY-MEASURE: the obligation classifier is now literally the emitter (2026-07-12)

### Fixed — classifier–emitter drift closed by construction

- **`isQfLia = isJust . exprToPred`** — sixty lines of hand-mirrored classification deleted; any future
  `exprToPred` case classifies correctly by construction, and a table-driven classify==emitter meta-test (CM-4,
  recomputed from the emitter's exported pieces) breaks if anyone reintroduces a parallel classifier. The
  emitter's ungated type-level guards are shared via the new `FixpointEmit.contractSigGuardsBlock`, which
  `mPostPred` itself now composes — the sharing is literal, not parallel.
- **Both recorded drifts fixed** (with live before/after evidence): measure-class contracts
  (`(>= (string-length s) 1)`) classified Advisory while discharging body-faithful (under-label); string-literal
  contracts classified `qf_lia` while falling back (over-label — a promised tier the verifier never delivered).
- **Five more instances found by the sweep and fixed**: pair selectors/`EPair` (PAIR-RET class), Result `ok`/`err`,
  uppercase constructor applications (COMP-4 class), the `!=` spelling, and n-ary `=>`/`<=>` corners (emitter is
  binary-only). The A3 array hand-mirror is deleted (now exprToPred-backed). The A3-recorded classifier callee-leg
  imprecision remains, conservative at the emitter.
- Reuse-retrieval abstains explicitly on UF-bearing contracts (measures, pair ops, `ok`/`err`, constructor terms) —
  its standalone Horn driver declares no UF constants; previously these hit the solver-error fail-safe after a
  doomed spawn (same A3.x driver disposition). The checkout brief's let-definitional `assumptions` RHS filter
  widens intentionally with the classifier (measure/pair/constructor RHS — each is VC-assumed).

**Tests:** 1222 Haskell, 45 Python (+4: the 8-row pinned battery, both recorded instances at the tier level, the
classify==emitter meta-assertion). 64-file sweep: zero verdict movement; refute-crux gate 22/22 (26 with the
rfc1982 family).

## v0.14.39 — R3 evaluation run: RFC 1982 through the pipeline, all six criteria pass (2026-07-12)

### Added — `examples/rfc1982_serial/` (the spec-from-RFC pipeline validated by procedure)

- **RFC 1982 (DNS serial number arithmetic) ran S0→S5 through
  [`spec-from-rfc-pipeline.md`](docs/design/spec-from-rfc-pipeline.md) by procedure, passing all six §4 success
  criteria** — closing the pipeline doc's own completion gap (G4). `serial-add`/`serial-lt`/`serial-gt` all reach
  body-faithful `verified` (trust report `verified: 3, asserted: 0`) with one `:source` per contracted clause;
  the S0 stage dispositioned §3.1's `modulo` into a linear conditional subtraction *before* authoring
  (SERIAL_BITS = 32). Two authored mutants refute — `serial-lt-bad` is the historical naive-`<` DNS comparison
  bug, refuted and localized — and `serial-lt-weak` is the recorded weak-spec co-evolution exhibit. The first
  persisted **clause inventory** (9/9 normative clauses dispositioned, the G1 template) lives in the example's
  `VERIFICATION_SCOPE.md`. Verdicts frozen: the family joins `make refute-crux-gate` (22 → 26 cases).
- Pipeline findings: [`experiments/rfc1982-eval/findings.md`](experiments/rfc1982-eval/findings.md) — no taxonomy
  gap, no scoping error; five findings routed (two compiler report-surface, three pipeline-doc revisions).

### Found (tracked, not fixed) — COVERAGE-TIER

- `--spec-coverage`'s tier column prints `Verified: 0 / Asserted: 3` while the same tree's trust report says
  `verified: 3` — the coverage summary doesn't read solver evidence (TERM-REPORT-PLAIN family; new roadmap row,
  which also carries the stale OBLIG-PBT-4 diagnostic text found alongside it).

**Tests:** 1218 Haskell, 45 Python (examples/scripts-only change); `make refute-crux-gate` 26/26.

## v0.14.38 — LEVER-A3: reporting surfaces catch up with the array verifier (2026-07-12)

### Fixed — array contracts classify in-fragment (obligation report)

- **An exactly-reflectable bytes/map contract now classifies `qf_lia` in `verify --obligation-report`** instead of
  the Advisory-tier `non_qf_lia` mislabel it carried while the verifier was already discharging it body-faithful.
  Classification derives from the emitter's own §6.1 guards (`FixpointEmit.contractArrGuardsBlock`, exported and
  shared — the CLASSIFY-EOP lesson: no parallel reimplementation that can drift), applied with the enclosing
  function's types: whole-array `=`, string/bool-valued maps, and non-int put values stay `non_qf_lia`. The
  `qf_lia` label is retained per the design's own acceptance wording (its haddock now reads "in the auto-discharge
  fragment `Σ_auto`"); no schema bumps (`orSchemaVersion`/`brief_version` stay 0.12.2).

### Added — checkout-brief array vocabulary

- **A hole with a bytes/map type visible in scope gets the array ops as `builtin` entries in
  `available_functions`**, each carrying its PROVE precondition over display binders (`bytes-get`:
  `(and (>= p1 0) (< p1 (bytes-length p0)))`; `map-get`: `(map-has p0 p1)`). Type-relevance gated — every
  pre-A3 brief is byte-unchanged. The brief's let-definitional `assumptions` (v2a) now also admit an array-op RHS
  (`(= y (bytes-get b i))` — the body VC pins exactly this equality since A1).
- Refine reuse-retrieval abstains on array-op contracts (its standalone Horn driver sorts binders without
  `$has`/`$val` splitting — a driver limitation, tracked as A3.x, not a classification gap).

### Found (tracked, not fixed) — CLASSIFY-MEASURE

- The same classifier–emitter drift family exists outside arrays: measure-class contracts classify `non_qf_lia`
  yet discharge; string-literal contracts classify `qf_lia` yet fall back. New roadmap row.

**Tests:** 1218 Haskell, 45 Python (+6: A3-1..6 — parser-faithful flips, three-guard residue, bad put value,
vocabulary gating with alias resolution, assumptions widening; A0-6 flipped in place per its recorded note).
64-file sweep: zero verdict movement; refute-crux gate 22/22.

## v0.14.37 — LEVER-A2: `map[int,int]` obligations discharge statically (2026-07-12)

### Added — map discharge via the two-array presence encoding (Lever A stage A2)

- **`map[int,int]` verification is real: a read without a presence proof, an aliased-key confusion, or a dropped
  update in a verified function is *refuted*.** A gated map binder splits into the two-array presence-plus-value
  encoding (`m$has`/`m$val`, presence as an **int 0/1 array** — the Rev 1.1 amendment; bool-element arrays crash
  the pinned solver bridge): `map-has` reflects as `select(m$has,k) = 1`, `map-get` as a presence-gated value
  select whose key-presence precondition is a PROVE call-site obligation, `map-put` as paired stores, `map-empty`
  as const arrays. Get-after-put discharges including the realistic let-bound pipeline shape
  (`(let [(m2 (map-put m k v))] (map-get m2 k))` — a pure-map-let expansion pre-pass, §6.1-exact). A defensive
  `(if (map-has m k) (map-get m k) d)` read discharges from the path condition.
- **The A1 landmine is resolved:** byte-range fact synthesis (`0 ≤ select ≤ 255`) is re-rooted on bytes-rooted
  selects only — a map-component select acquires no phantom range fact. Demonstrated by a mixed bytes+map program
  pair: the unbounded-map-value post refutes (a phantom fact would have made it vacuously SAFE) while its
  pre-bounded twin verifies through the bytes select's still-emitted fact.
- **Exact-reflection discipline (§6.1) holds at the new boundary:** string/bool-valued maps, a map-op contract on
  a cross-file callee, and non-pure map-returning bodies fall back **whole** (tracked as A2.1); whole-map `=`
  never reflects (review F1). F7 verdict inventory: 71-file sweep, zero output/`.fq` diffs; refute-crux gate 22/22.
- Spec: the §5.3.3 array class extends to maps; §5.3.5 map-op row flips; §13.12 updated (int values = the v1
  reflected class).

**Tests:** 1212 Haskell, 45 Python (+10: A2-1..10 — pinning emission, crux pair, pipeline, aliased keys, presence
pair, landmine, F1 routing, string-value fallback-not-crash, defensive read, cross-call deferral).

## v0.14.36 — TERM-REPORT-PLAIN + RUN-EXEC + SCRUT-PTR (2026-07-12)

### Fixed — plain trust-report honors persisted descent discharge (TERM-REPORT-PLAIN)

- **The render-only `verify --trust-report` path (non-strict, non-CDP) now reads the sidecar's
  `termination_verified` bit** (`TrustReport.sidecarDischargedSet` — the same field the strict-core admission gate
  trusts), so a function whose `(decreases)` measure was discharged no longer renders `termination_unverified` +
  `partial_fns` on that path. A file with no discharged sidecar keeps the conservative mark. Diagnosis narrowed
  from the roadmap row: the plain path never runs the solver, and `measure-not-decreasing` is a same-run solver
  verdict that is never persisted (the `refuted` analog) — so the "bad-measure stamp on the plain path" half of the
  row was not a defect but the recorded design; only the discharged-flag half was real.

### Fixed — `llmll run` executes programs (RUN-EXEC)

- **`llmll run` was broken end-to-end for argument-less programs, and the defect was triple:** `doRun` never built
  the generated package, passed no executable name to `stack exec` (which therefore printed its usage text), and
  discarded the child's stdout. It now builds fail-closed, executes the generated binary by its sanitized package
  name, and streams the program's output. (Pre-existing, untouched: the child gets empty stdin — interactive `run`
  is a separate concern.)

### Fixed — scrutinee-position hole pointer (SCRUT-PTR)

- **A hole in match-scrutinee position (`(match ?h …)`) records its own pointer** (`…/scrutinee` segment, matching
  the JSON-AST shape) instead of its parent match node's, so `checkout` resolves its context (`in_scope`,
  contracts) rather than returning null — the LET-PTR defect class, fixed with the same `withSegment` discipline
  (v0.14.31 precedent).

**Tests:** 1202 Haskell, 45 Python (+3: TRP-1/TRP-2 sidecar-bit rendering, SCRUT-PTR pointer + scope; RUN-EXEC
accepted by live transcript — spawning stack subprocesses in-suite has no precedent and costs minutes per run).

## v0.14.35 — Examples hardening: refute-crux CI gates + `total-recursion` + `bytes-bounds` (2026-07-12)

### Added — frozen refute-crux gates (the ENUM-EQ-FALLBACK lesson, institutionalized)

- **Six example families now carry frozen-verdict CI gates** (`EXPECTED_VERDICTS.json` per family +
  `scripts/refute-crux-gate.sh`; Makefile target `refute-crux-gate`, wired into `benchmark-all`): tcp_rfc793,
  session-pay, gotofail, outcome-totality, total-recursion, bytes-bounds — 22 cases. The gate verifies a temp copy
  and checks **verdict + exit code + refutation localization only**; obligation-report/trust-report/classification
  fields are deliberately unfrozen (arrays stage A3 legitimately changes classification). Rationale: `step-bad`
  verified SAFE for twenty versions (v0.14.12–31) because nothing froze the showcased refutations; that class of
  silent loss now fails CI loudly.

### Added — two new examples

- **`examples/total-recursion/`** — the first `(decreases …)` presence in `examples/`: `sum-to` verifies **total**
  (termination discharged, strict-core admits the recursion, no `termination_unverified` flag) and the
  byte-identical-body `sum-to-bad-measure` twin fails on the distinct termination channel
  (`decreases-condition`/`descent-condition … not verified`; `measure-not-decreasing` drift stamp).
- **`examples/bytes-bounds/`** — the LEVER-A1 witness: `read-at` with the correct `<` bound is SAFE including under
  `--strict-verified-core`; the off-by-one twin (`<=`) and an out-of-range `bytes-set` (value 300) are refuted at
  their call sites. Its README names the stage-A3 reporting caveat; this example is A3's acceptance fixture.

### Fixed — runbook claim re-check (post-ENUM-EQ-FALLBACK)

- Every claimed verdict in the tcp_rfc793/session-pay runbooks and scope docs re-reproduced verbatim against the
  shipped binary; fixes were cosmetic drift only (output path prefixes, one fragment-name imprecision, banned-word
  headings). LLMLL.md §4.2 gains one sentence mapping the `measure-not-decreasing` verdict name to its CLI
  constraint messages.
- Found and tracked (not fixed): TERM-REPORT-PLAIN — the plain (non-strict) trust-report path misses same-run
  descent marks (roadmap row; strict-core and CDP paths are correct).

**Tests:** 1199 Haskell, 45 Python (examples/scripts-only change); `make refute-crux-gate` 22/22.

## v0.14.34 — LEVER-A1: `bytes[n]` obligations discharge statically (2026-07-11)

### Added — the array class enters `Σ_auto` (Lever A stage A1)

- **`bytes[n]` verification is real: an out-of-bounds read is now *refuted*, not asserted.** Bytes params/returns
  of functions whose contract or body mentions a bytes op lower to the solver's native array sort (`Map_t int int`
  — the probe-proven liquid-fixpoint spelling); `bytes-get`/`bytes-set` reflect as exact-pinning call obligations
  (index-in-bounds and value-range, PROVE polarity, riding the existing call-pre machinery), `bytes-length b`
  reflects as the per-binder ground fact `bytesLen(b) = n`, `bytes-zero` as the const array; byte-range facts
  (`0 ≤ select ≤ 255`) are emitted ground per occurring read (the path-(a) discipline extended). The design's §11
  off-by-one crux — a bounds check written `<=` where `<` is required — refutes with call-site localization; the
  corrected twin verifies SAFE, including under `--strict-verified-core`. Aliased symbolic indices refute;
  cross-function call sites carry the obligation.
- **Refutation-completeness discipline (proposal §6.1) enforced:** a body-faithful VC is emitted only when every
  symbol reflects exactly. Map operations stay unreflected (stage A2) and route to fallback unchanged; whole-bytes
  `=` never reflects to array equality (review F1); a mixed bytes+map obligation falls back whole.
- **Zero-flip verdict inventory (review F7 gate):** 85-example sweep, base vs A1 binary — 0 verify-output diffs,
  0 emitted-`.fq` byte diffs. Ungated functions are byte-identical by construction (activation gate); the crypto
  builtins' `bytes[20]` signatures acquire no new obligations.
- Spec: `Σ_auto` gains the array class (LLMLL.md §5.3.3 bullet + signature, §5.3.5 matrix rows, §13.12 flip).

**Tests:** 1199 Haskell, 45 Python (+9: `LEVER-A1` block — emission shapes, solver-gated crux pair, store/value-range,
const array, map-op routing, F1 routing, crypto-shape inertness, cross-function activation, mixed-body fallback).

## v0.14.33 — LEVER-A0: the bytes/map operation family, verification-inert (2026-07-11)

### Added — eight bytes/map builtins (Lever A stage A0)

- **`bytes-length` / `bytes-get` / `bytes-set` / `bytes-zero` and `map-has` / `map-get` / `map-put` / `map-empty`
  ship as typed, compilable, runnable builtins** (LLMLL.md §13.12) — the surface stage of the data-scope Lever A
  design ([`docs/design/data-scope-lever-a-arrays-proposal.md`](docs/archive/shipped-design-specs/data-scope-lever-a-arrays-proposal.md),
  Rev 1.1). Reads carry PROVE-polarity preconditions (index-in-bounds, key-presence) enforced at this stage as
  runtime assertions in the generated code (the §5.3.4 backstop) — a violating `bytes-get` aborts with
  `index 9 out of bounds for bytes[8]`. Typing is dedicated (`inferArrayOp`): the v1 **int-only map-key gate** is a
  diagnostic on the operation (the `map[k,v]` type former stays unrestricted), `bytes-set` is length-preserving,
  and `(bytes-zero)` is legal only as the whole body of a `def`/`def-shell` with a literal `-> bytes[n]` return
  (the return type determines `n`; no let-annotation surface exists to widen the context — routed to
  language-team).
- **Verification-inert, demonstrated:** no FixpointEmit/classifier/sort-env change; an 85-file `examples/` sweep
  shows 0 verify-output diffs and 0 emitted-`.fq` byte diffs; contracts mentioning the ops classify out-of-fragment
  and route through the §5.3.3 fallback exactly as any opaque builtin does today. Reflection into VCs is stage A1
  (`bytes[n]`) / A2 (`map`).
- Found en route (pre-existing, tracked as RUN-EXEC, not fixed here): `llmll run` never passes the executable name
  to `stack exec`, so argument-less programs fail with stack usage text.

**Tests:** 1190 Haskell, 45 Python (+9: `LEVER-A0` block — eight-op acceptance, key-gate diagnostic + type-former
legality, non-bytes arg rejection, `bytes-zero` context rule both ways, `bytes[n]` preservation, classifier
`non_qf_lia`, codegen seams/shims, emission fallback-no-crash). E2e: an eight-op program builds and prints the
designed `208042`; both precondition assertions fire on violating calls.

## v0.14.32 — checkout `assumptions` v2b: match-scrutinee case hypotheses + nullary-enum refutation restored (ENUM-EQ-FALLBACK) (2026-07-11)

### Checkout brief — `assumptions` gains match-scrutinee case hypotheses (OBLIG-1 v2b)

- **The checkout brief's `assumptions` field now also surfaces the case hypothesis of each enclosing match arm:**
  a hole under `((Ctor x) …)` on a variable scrutinee `s` carries `(= s (Ctor x))` (nullary arm: bare `(= s Ctor)`,
  matching the contract-position convention). Hypotheses accumulate outermost-first across nested and sequential
  matches; entering a binder scope that rebinds a name mentioned by a stacked hypothesis drops that hypothesis
  (shadow guard — loses completeness, never soundness). Captured at sketch time (`SketchHole.shHyps` via
  `matchHypothesis`/`withHyp`), rendered brief-time after the v1 (param-refinement) and v2a (let-definitional)
  provinces; type-check cost, no solver, no schema bump. Complex scrutinees and wildcard/variable/literal arms are
  silently skipped (the sound-but-incomplete bar); the residual OBLIG-1 province is `def-invariant` axioms.

### Fixed — nullary-enum contracts no longer force body-fallback (ENUM-EQ-FALLBACK)

- **A contract equality atom on an all-nullary enum param (`(= state Closed)`) no longer forces contract-only
  fallback.** The v0.14.12 MATCH-WIDEN guard `clauseOverOpaqueSumParam` matched *any* sum-typed param named bare in
  a pre/post — including all-nullary enums, which are int-tag-desugared (COMP-3b-general, v0.13.5) and
  solver-visible — so every operator contract over an enum param fell back and its designed-wrong twins verified
  SAFE on a merely-asserted post. Refutation was silently lost v0.14.12–v0.14.31 for `tcp_rfc793/step-bad` and all
  three `session-pay` wrong twins. The guard now fires only for payload-bearing (genuinely value-opaque) sums; its
  protective case is pinned by a regression test. An 85-file examples sweep confirms exactly the 4 intended
  SAFE→refuted flips plus 3 fallback→body-faithful upgrades (verdicts unchanged); all other files line-identical.
  Surfaced by the examples-modernization pass; root-caused to commit `8c61f30`.

### Examples — modernized to the shipped surface

- `tcp_rfc793`, `session-pay`, `outcome-totality`: contract posts rewritten from `(or (not A) B)` to `(=> A B)`
  (v0.14.16 sugar); JSON-AST twins regenerated. `gotofail/nary.llmll` promoted `def-shell` → strict `def` (n-arm
  strict core, v0.14.27). All refute cruxes re-verified against the fixed compiler; both contract forms refute.

### Docs — review wave through v0.14.31 + two new design docs

- `llmll refine` documented across README, `LLMLL.md` §11.2, and getting-started (shipped v0.14.13, previously
  absent from all three); `assumptions` docs match the three shipped provinces; §5.3.3/§5.3.5 termination rows
  describe the shipped k=1 + lexicographic descent discharge; `decreases-clause` added to the §12 grammar;
  getting-started schema/`--help`/coverage text re-captured; XMOD-STALE closed (no long-lived `ModuleCache`
  consumer exists — `Serve.hs` is stateless per request by recorded design); four settled design docs archived with
  redirect stubs; INDEX labels refreshed.
- New design docs: [`docs/design/data-scope-lever-a-arrays-proposal.md`](docs/archive/shipped-design-specs/data-scope-lever-a-arrays-proposal.md)
  (Lever A — QF array theory for `bytes[n]`/`map[k,v]`, Rev 0, awaiting professor review) and
  [`docs/design/spec-from-rfc-pipeline.md`](docs/design/spec-from-rfc-pipeline.md) (R3 pipeline design, Rev 0;
  remaining = its §4 evaluation run, experiment-lead-owned).
- New roadmap rows: SCRUT-PTR (scrutinee-position hole records its parent pointer — LET-PTR defect class, low) and
  STRICT-SIBLING (same-run sibling evidence for strict-core admission, surfaced twice this session).

**Tests:** 1181 Haskell, 45 Python (+10: OA-9..13 — payload/nullary/nested/let+match-compose/shadow-drop;
ENUM-EQ-FALLBACK block — if/match ctor atoms, or-not pre form, wrong-body in-fragment refute, payload-sum guard
preserved). E2e: a match-nested hole's brief carries `["(> limit 0)", "(= y (+ c 1))", "(= s (Abort c))"]`;
`step-bad` refutes on both contract forms.

## v0.14.31 — checkout `assumptions` v2a: let-definitional equalities + let-nested hole context (LET-PTR) (2026-07-11)

### Checkout brief — `assumptions` gains let-definitional equalities (OBLIG-1 v2a)

- **The checkout brief's `assumptions` field now also surfaces, for each in-scope let-binding with a QF-LIA RHS,
  the definitional equality `(= y e)`.** A let-binding appears in a hole's scope only when the hole is inside its
  body, so `(= y e)` genuinely holds at the hole (the body VC already assumes it). The QF-LIA filter (now
  `EOp`-aware, v0.14.30) keeps the field in-fragment — a call/opaque RHS is skipped — and, since only real
  let-bindings carry a recorded RHS, the alias-name / enclosing-fn-name leaks that share the `let-binding` scope
  tag are naturally excluded. This is the professor's named v2 province; still deferred: match-scrutinee case
  hypotheses and `def-invariant` axioms (the latter needs a schema bump + assume-vs-assert provenance). No schema
  bump.

### Fixed — `checkout` context for let-nested holes (LET-PTR)

- **A hole inside a `let` body now resolves its checkout context.** The sketch's `let`-body traversal did not push
  the `body` pointer segment (unlike function bodies, `if`-branches, and `match`-arms), so a let-nested hole
  recorded sketch pointer `/statements/N/body` while its AST node is `/statements/N/body/body`. `checkout`
  validates the pointer against the AST node and then matches the sketch hole by pointer — the mismatch meant
  **every let-nested hole returned `null` `in_scope` and `null` `assumptions`**. Fixed by wrapping the body in
  `withSegment "body"`. This repairs the full context surface (`in_scope`, contract fields, `assumptions`) for
  all let-nested holes, not only OBLIG-1. Surfaced by the OBLIG-1 v2a end-to-end verification.

**Tests:** 1171 Haskell, 45 Python (+4: OA-6 let-def surfaced, OA-7 non-QF-LIA call RHS skipped, OA-8 param +
let-def compose; LET-PTR pointer regression + let-binding-in-scope). E2e: a let-nested hole checkout now yields
`in_scope [f,x,y]` and `assumptions ["(> x 0)", "(= y (- x 1))"]`.

## v0.14.30 — QF-LIA classifier recognizes the `EOp` operator form (CLASSIFY-EOP) (2026-07-11)

### Fixed — obligation classification for operator-bearing contracts

- **`isQfLia` / `classifyContractFragment` now recognize the `EOp` operator node, not only `EApp`.** Both parsers
  emit an operator predicate (`(>= x 0)`, `(> result x)`) as `EOp` (S-expr `Parser.hs:897`, JSON
  `ParserJSON.hs:558`), but every operator case in `isQfLia` matched `EApp` only — so a normal operator-bearing
  contract fell through to the non-QF-LIA default. The obligation report's `contract_fragment` therefore
  mislabeled **every** real contract `non_qf_lia`, and `ObligationMining`'s per-obligation Verified/Advisory tier
  downgraded QF-LIA obligations to Advisory. **Not a soundness defect** — the verifier was never affected
  (`FixpointEmit` normalizes `EOp → EApp` before VC emission at `:1916`), so contracts always verified correctly;
  the bug was in the classification/reporting an agent reads to judge auto-dischargeability. One-line central fix
  (`EOp op args` classified as the equivalent `EApp op args`); REFINE-REUSE's local `normContractOps` workaround
  removed (its `normOps` canonical-key path is unaffected). Surfaced by REFINE-REUSE's end-to-end verification
  (v0.14.29). Empirically: `(pre (>= x 0)) (post (> result x))` read `contract_fragment: non_qf_lia` before,
  `qf_lia` after.

**Tests:** 1167 Haskell, 45 Python (+4: OA-CF-EOP, IQ-4/5/6 — `EOp`-faithful; the prior classifier tests
constructed `EApp` directly, bypassing the parser, which is exactly why the bug survived).

## v0.14.29 — checkout-brief `assumptions` (OBLIG-1) + `refine` reuse-retrieval (REFINE-REUSE) (2026-07-11)

### Checkout brief — `assumptions` field wired (OBLIG-1)

- **The checkout brief's reserved `assumptions` field now carries the refinement predicates of in-scope
  refinement-typed parameters.** For a checked-out hole, each in-scope PARAM binder `x` whose type resolves —
  directly or through a same-file type alias — to a refinement type `{v | φ}` contributes `φ` with the bound
  variable α-renamed to `x` (e.g. `x: (where [v:int] (> v 0))` → `assumptions: ["(> x 0)"]`). Previously
  `assumptions` was always `null`; the predicate was surfaced nowhere else (`in_scope` shows `int (constrained)`,
  `type_definitions` the base type), and for an inline refinement it was not even derivable by the consumer.
  Sourced strictly from the hole's in-scope binder set, so path-correct by construction (out-of-scope /
  sibling-branch binders never appear). Type-check cost — no solver, no constraint emission. **No schema bump**
  (`ctAssumptions` was already `[string]`-shaped; the report-side `trAssumptions` is untouched).
- **v1 scope is refinement-typed parameters only** — a sound-but-deliberately-incomplete view of the hole's
  hypothesis context (professor review). Out of scope, documented: let-definitional equalities `y = e` (which
  the body VC *does* assume — a disclosed brief-vs-verifier asymmetry), match-scrutinee case hypotheses, and
  `def-invariant` axioms (deferred pending provenance tagging, an unverified invariant being a TCB assumption).

### `refine` — advisory reuse-retrieval (REFINE-REUSE)

- **`refine` now surfaces in-scope defs whose contract subsumes a spawned sub-contract, as an advisory
  `reuse_suggestions` field, plus a non-blocking `W-REUSE` on an exact contract-equivalent.** For each contracted
  sub-hole a cascading `refine` spawns, the compiler retrieves in-scope `def`/`def-shell`s that could serve it —
  subsumption is contract subtyping (Liskov-Wing): `D` subsumes `Cₛ` iff `preₛ ⟹ pre_D` (contravariant) ∧
  `post_D ⟹ postₛ` (covariant), emitted as two standalone liquid-fixpoint refinement-subtyping Horn constraints
  over α-normalized binders (params → `p0…pn` positionally, result → `v`). An exact contract-equivalent
  (α-normalized canonical key, no solver) additionally raises `W-REUSE`. **NON-REJECTING**: never blocks a
  well-formed refine; orthogonal to the CDP vacuity gate. A signature pre-filter (arity + param sort-vector +
  result sort) and a QF-LIA gate bound solver work; with no solver installed only the exact-key tier runs
  (graceful skip). `reuse_suggestions` is present (possibly `[]`) on every `ScopeRefine` success; **no AST schema
  bump** (the refine result JSON is unversioned).
- Incidental fix surfaced by end-to-end verification: the QF-LIA fragment classifier
  (`classifyContractFragment` / `isQfLia`) recognized only the `EApp` operator form, but the JSON parser emits
  `EOp` — so a *parsed* contract mis-classified as non-QF-LIA. REFINE-REUSE normalizes `EOp → EApp` before the
  gate; the broader classifier blind spot is tracked as a follow-on.

**Tests:** 1163 Haskell, 45 Python (+13: OBLIG-1 +5 [OA-1..5]; REFINE-REUSE +8 [RR-1..8, RR-1..3 real
liquid-fixpoint solves]).

## v0.14.28 — obligation-report `expected_type` uses sketch inference (2026-07-11)

### Obligation report — richer per-hole `expected_type`

- **`verify --obligation-report` now reports a hole's sketch-inferred type where the structural pass leaves it
  untyped.** The per-hole `expected_type` was sourced from `analyzeHoles` (structural) alone, which reads
  `unknown` for value-position holes — e.g. `?bump` in `(+ x ?bump)` — that the checkout brief's `runSketch`
  already types as `int`. Because a fill agent gates its callable-vocabulary suggestions on `expected_type`,
  `unknown` ungated the full (capped) OBLIG-VOCAB-GATE list instead of the typed subset. `assembleReport` now
  runs the same sketch the brief uses (type-check cost, no solver), joins holes by RFC-6901 pointer, and prefers
  the sketch type **only where the structural type is absent** — the structural type still wins when present, and
  an un-inferable hole stays `unknown` (no false precision). Closes roadmap row **OBLIG-HOLE-TYPE** (surfaced by
  the v0.14.20 OBLIG-VOCAB-GATE fix). No schema bump: `expected_type` already existed; only its value is sharper.

**Tests:** 1150 Haskell, 45 Python (+2: OHT-1 value-position `(+ x ?bump)` reads `int` in the report where the
structural pass is untyped; OHT-2 bare `?whole` stays `unknown`).

## v0.14.27 — lexicographic descent (k>1) + n-arm matches in strict-core `def` (2026-07-11)

### Verify — lexicographic termination measures

- **A k>1 `(decreases e₁ … eₖ)` measure now discharges termination via the lexicographic order on ℕᵏ.**
  Previously k>1 was accepted but only warned `W-DECREASES-LEX` and stayed `termination_unverified`. The
  per-call-site descent constraint generalizes from the scalar `e[args'] < e` to the QF-LIA disjunction
  `⋁ᵢ (e₁'=e₁ ∧ … ∧ e_{i-1}'=e_{i-1} ∧ eᵢ'<eᵢ)`, with well-foundedness `eⱼ≥0` per component. `lexLess [g] [f]`
  is a bare `g<f`, so the k=1 encoding is byte-identical (no shipped sidecar invalidates). Self-recursion
  and **equal-arity** mutual recursion discharge (different measures per member allowed — the common-ℕᵏ
  criterion); a k>1 measure that does not lexicographically decrease is `measure-not-decreasing` (the same
  verdict, over the tuple). No schema/hash change (the measure was list-shaped since REC-DESCENT Phase 1).
- **Soundness — uniform-arity discharge gate.** A recursive SCC discharges to total **only if every member
  declares a `decreases` tuple of the same length** (extracted to `ObligationAssembly.descentDischargedFns`).
  A mismatched-arity edge emits no descent constraint, so without this gate a mixed-arity mutual SCC would
  verify vacuously-SAFE (nothing to fail) and be stamped total — claiming termination for a divergent
  function. Mixed-arity now stays `termination_unverified` (refuse-not-pad).

### Verify — n-arm matches in strict-core `def` bodies

- **`isCoreBodySyntactic` admits n-arm payload-bearing sum matches**, so a strict-core `def` body may now
  contain a >2-arm mixed/payload `match` (previously rejected "use def-shell", even though the verifier —
  MATCH-WIDEN-2, v0.14.26 — could already discharge it body-faithful). The two payload match cases widen
  from `length cases == 2` to `>= 2`; `isMixedNullaryPayloadArms` generalizes to any arity. Sound: the
  verifier already discharges these matches and `checkExhaustive` already enforces coverage, so a `def`
  body sees no new obligation — the grammar gate catches up to the verifier. The widening lifts only the
  arity cap: a non-core arm body, a multi-payload constructor pattern, and non-exhaustive matches stay
  rejected.

### Examples

- **`examples/gotofail/`** exploits MATCH-WIDEN-2: adds `sequential.llmll` / `sequential-bad.llmll` (the
  faithful `(let [(h (match hash …))] (match sig …))` sequential pipeline) and `nary.llmll` (a 3-arm sum);
  the stale README scope-limits (two-arm-only, sequential-falls-back) are corrected.

**Tests:** 1148 Haskell, 45 Python. (Lexicographic descent +5 [LEX-1..5; LEX-4 is the mixed-arity soundness
regression test]; n-arm strict-core +5 [CNARY-1..5]; +1 MW2B-5 sequential-refutation coverage. 1137 → 1148.
No AST schema change [stays 0.8.0].)

## v0.14.26 — MATCH-WIDEN-2: n-arm sums + sequential matches (2026-07-10)

Widens the body-faithful match fragment from two arms to any arity, and to sequential matches — same int-tag QF-LIA theory as v0.14.12, no new fragment, no schema change.

### Verify — n-arm payload-bearing sum matches (Commit A)

- **A match on an admissible sum of any arity now verifies body-faithful.** A `(match s ((Continue) 0)
  ((Stop n) n) ((Retry m) m))` over a 3+-constructor mixed nullary/payload sum previously fell back; it
  now discharges via an n-way int-tag chain (arm *i* guards on `<v>$tag = i`, the final arm or a wildcard
  is the `¬prior` else). Generalizes `classifyTwoArmAdtArms` → `classifyNArmAdtArms` and the binary
  `buildOpaqueSumBranch` → `buildOpaqueSumBranchN`. Exhaustiveness is enforced upstream by the type
  checker (a non-exhaustive match is a type error), so the verifier only sees exhaustive matches. An
  all-nullary n-arm enum already verified (the int-tag desugar); a recursive/non-admissible payload arm
  still falls back (firewall). **n=2 is byte-identical to the prior binary encoding** — no shipped
  two-arm sidecar invalidates.

### Verify — sequential matches (Commit B)

- **Two sequential matches in one body now verify body-faithful.** A `(let [(x (match a …))] (match b …))`
  — a multi-path match bound in a `let` and threaded into a following match — previously fell back; the
  multi-path let-RHS is now grafted into the body (§S4), translating the continuation fresh at each
  RHS-branch leaf (fresh skolems per path, since `collectBranchBinders` does not dedup). The branch
  guards and payload binders are preserved; refutation is preserved (a mid-pipeline violating arm still
  refutes). Scoped to the multi-path let-RHS path, so single-match bodies are byte-identical. The
  `countPathsBounded 4096` cap bounds sequential path products.

**Tests:** 1137 Haskell, 45 Python. (+11: Commit A +7 MW2A-1..7 [n-arm mixed verifies, 4-arm, wildcard
tail, all-nullary no regression, non-admissible firewall, n=2 byte-identity, non-exhaustive type error];
Commit B +4 MW2B-1..4 [sequential 2-arm, n-arm-then-2-arm, single-match unchanged, untranslatable
continuation falls back]. No schema change.)

## v0.14.25 — REC-DESCENT Phase 2+3: termination discharge + strict-core admission (2026-07-10)

Completes the REC-BODY-VC line: a `def-shell` with a discharging `(decreases e)` measure now verifies **total** correctness and becomes strict-core admissible.

### Verify — descent obligations + the `measure-not-decreasing` verdict (Phase 2)

- **A single-measure `(decreases e)` on `def-shell` now discharges termination.** The verifier emits
  well-foundedness (`pre ⟹ e ≥ 0`) and, at each intra-cycle call site, strict descent
  (`pre ∧ path ⟹ e[args'] < e`) — QF-LIA over the well-founded order `<` on ℕ. Different measures on
  distinct cycle members are permitted (they share the ℕ order — Floyd's ranking criterion); the
  discharge is per-edge, so a terminating cycle whose decrease is distributed across edges rather than
  holding on each edge is conservatively rejected.
- **`measure-not-decreasing` — a new hard-fail verdict, distinct from `refuted`.** A declared measure
  that does not strictly decrease fails the build (exit 1) as `measure-not-decreasing`: the *declared
  measure* is refuted, **not** the postcondition. Surfaced in the trust report
  (`measure_not_decreasing_fns` + a per-entry flag) and the obligation report (a `termination-obligation`
  with `status: measure-not-decreasing`; obligation-report `schema_version` `0.12.1` → `0.12.2`), never
  mislabeled `refuted`.
- **Diagnostics:** `W-DECREASES-LEX` (a lexicographic k > 1 clause is accepted but not yet discharged;
  the SCC stays partial), `W-DECREASES-UNUSED` (a measure on a non-recursive `def-shell`), and an
  untranslatable-measure firewall (nonlinear / opaque-carrier → no constraint, stays partial, never
  silently total). Also fixes a latent letrec well-foundedness sort-crash (the `≥ 0` constraint emitted
  the measure as a bool predicate).

### Verify — discharge feedback + strict-core admission (Phase 3)

- **A descent-discharged cycle upgrades partial → total.** When every member of a recursive SCC declares
  a discharging k = 1 measure and is body-faithful (the whole-SCC gate), the SCC is descent-discharged:
  a new persisted `erTerminationVerified` bit is stamped, the `termination_unverified` flag / `partial_fns`
  membership is dropped, and the recursion becomes **strict-core admissible** — a `def` may now call it.
- **Admission tightening (closes a live gap).** `checkCalleeAdmissibility` gates a *recursive* callee on
  `erTerminationVerified`: a descent-discharged recursion is admitted, while a **verified-but-measureless**
  recursion is now **refused** from strict-core (previously partial-correctness recursion could reach the
  strict core through a callee). Non-recursive callees are unchanged; rides the existing two-pass
  persisted-evidence model. Corpus sweep: no example was a strict-core `def` calling a recursive
  `def-shell`, so nothing needed measures — the gap was latent.
- **The measure is part of the total-correctness evidence.** `canonicalDefEvidenceHash` folds the
  `decreases` measure into its preimage, so editing the measure invalidates the cached total verdict;
  byte-inert for the empty list (decreases-free defs' hashes unchanged). `erTerminationVerified`
  absent-on-read defaults `False` (fail-closed).

Settled by professor rulings: hash the measure (it is a load-bearing input to the cached total verdict,
not a tactic hint); admit different-measure mutual recursion via the common-ℕ Floyd criterion, with the
`≥ 0` floor gating the whole SCC and the per-edge (not per-cycle) incompleteness documented.

**Tests:** 1126 Haskell, 45 Python. (Phase 2 +8 RD2, Phase 3 +5 RD3; 1113 → 1126. No AST schema change
[stays `0.8.0`]; obligation-report `schema_version` `0.12.2`; `EvidenceRecord` gains `erTerminationVerified`
[63-site migration].)

## v0.14.24 — REC-DESCENT Phase 1: the `(decreases …)` surface + schema 0.8.0 (inert) (2026-07-10)

### Surface — an optional termination-measure clause on `def-shell`

- **`def-shell` now accepts an optional `(decreases e₁ … eₖ)` clause** — a list of int-typed measure
  expressions over the parameters (`result` is not in scope, as in `pre`), parsed in both the S-expression
  and JSON-AST surfaces and round-tripped losslessly (`AstEmit` emits the `decreases` array only when
  non-empty, so a decreases-free `def-shell` is byte-identical to before). New AST field
  `defShellDecreases :: [Expr]` on `SDefShell`. `TypeCheck` gates the measures (int-typed over params;
  `result` rejected with a §4.3 diagnostic). The list shape ships now so it need not change when
  lexicographic (k > 1) discharge is added later.
- **This release is verification-inert.** No obligation is emitted, `canonicalDefEvidenceHash` is
  untouched, and a recursive `def-shell` with a `decreases` clause verifies **exactly** as without it —
  it still carries the `termination_unverified` flag (v0.14.23). Well-foundedness (`e ≥ 0`), per-call-site
  strict descent (`eᵍ[args] < eᶠ`), the `measure-not-decreasing` verdict, folding the measure into the
  evidence hash, and the strict-core admission lift are the next phase (REC-DESCENT Phase 2/3). The
  surface lands first so the AST shape and the schema bump validate on their own.
- **Increment 3 Phase 1 of REC-BODY-VC** ([`docs/design/rec-body-vc-proposal.md §c`](docs/archive/shipped-design-specs/rec-body-vc-proposal.md)).

### Schema — JSON-AST 0.7.0 → 0.8.0

- **`schemaVersion` 0.7.0 → 0.8.0** for the additive optional `decreases` array on the `def-shell` node
  (`$id` → `/schemas/v0.8/`, const `0.8.0`, `expectedSchemaVersion` `0.8.0`). `0.7.0` documents still parse
  (backward-compatible read); emission stamps `0.8.0`.

**Tests:** 1113 Haskell, 45 Python. (+6: RD1-1..2 S-expr↔JSON round-trip [k=1, k=3], RD1-3 measure
scope/type-check [`result` and non-int rejected], RD1-4 inertness [a `decreases` clause does not change the
verdict], RD1-5 schema 0.8.0 stamp + 0.7.0 backward-parse, RD1-6 decreases-free byte-inertness. ~82
positional `SDefShell` sites migrated for the new field.)

## v0.14.23 — REC-PARTIAL-MARK: termination_unverified flag for recursive cycles (2026-07-10)

### Trust report — a visible partiality marker for recursion

- **Every function in a recursive call-graph cycle now carries a `termination_unverified` flag** — a
  per-entry `termination_unverified: true` plus a top-level `partial_fns` list — derived at
  report-build time from the whole-program call graph (`buildCallGraph` over the entry module plus
  cached `meStatements`). Like `refuted` / `overflow_tainted` it is an **orthogonal informational
  marker**, not a `DisplayLevel` element: it never feeds `evidenceMeet`, the effective level,
  `refutedClosure`, or strict-core admission, and it is never persisted to the sidecar — so it is
  present even on a solver-less `--trust-report` render (unlike `refuted_fns`, which is verify-time
  only). A recursive `def-shell` keeps whatever tier its body VC earned (typically a `verified` post at
  partial correctness) and simply carries the flag. `--trust-report` text output gains a
  `Termination-unverified (recursive, partial correctness)` section. `trust_report_version` 1.4.0 → 1.5.0.
- **Increment 2 (a) of REC-BODY-VC** ([`docs/design/rec-body-vc-proposal.md`](docs/archive/shipped-design-specs/rec-body-vc-proposal.md));
  increments (b1) fail-closed default and (c) `(decreases …)` strict descent remain open. Makes the
  `LLMLL.md §4.2` partiality-flag claim true (it previously promised a flag that did not exist), and
  unifies the tier of a refine-path cycle with a hand-written one (cascading-refinement Option 3, now
  Rev 3).

### Docs — recursion partial-correctness spec reconciliation (D1/D2)

- **`§5.3.5`, the one-pager, and the README** verification-matrix rows split `EApp (uncontracted /
  recursive self)`: an uncontracted callee stays contract-only, but a **recursive self / cycle of a
  contracted function verifies body-faithful at partial correctness** (assume-guarantee over the cycle,
  `§0.1`) carrying `termination_unverified` — correcting the prior "contract-only" claim that
  contradicted `§0.1`. `§4.2` and a new `§4.4.4` paragraph document the marker.
- **`examples/secure-channel-emergent/README.md`** F-1 corrected: the degenerate self-call fill **is**
  body-faithful + SAFE (it does not drop from the set), so the honest per-fill acceptance bar is
  `SAFE ∧ body-faithful ∧ ¬termination_unverified`; the v0.14.21/22/23 layers of fixes are named.

**Tests:** 1107 Haskell, 45 Python. (+5: PM-1 recursive marked, PM-2 non-recursive unmarked, PM-3
mutual-recursion SCC marks both, PM-4 derived-not-persisted [present on a solver-less render], PM-5
refuted + termination_unverified compose. No AST schema change; `trust_report_version` 1.5.0.)

## v0.14.22 — REC-HASH-FORM: def-form in the evidence hash (probe-E laundering closed) (2026-07-10)

### Verify — evidence-hash integrity for the strict-core admission gate

- **`canonicalDefEvidenceHash` now folds the def-form into its preimage** (`SDef` → `"def"`,
  `SDefShell` → `"def-shell"`, via the new `Syntax.defFormTag`), and `admitVerifiedSemanticsTag`
  bumps `av1` → `av2`. The persisted `verified_hash` previously covered only `(semantics-tag, body,
  pre, post)` — not the def-form — so a `def-shell` → `def` **rename over an intact `.verified.json`**
  preserved the hash, and the persisted-evidence admission leg admitted the self-callee: partial-
  correctness recursion laundered into the total-correctness (`verified`) tier under
  `--strict-verified-core` (probe E). The def-form drift now downgrades the stale sidecar through the
  existing `downgradeStaleVerifiedSidecar` path → the flipped `def` re-verifies fresh → its self-call
  is rejected at strict-core admission (`core-membership-violation`), exactly as a from-scratch
  recursive `def` already was (probe A).
- **Increment 1 (b0) of REC-BODY-VC** ([`docs/design/rec-body-vc-proposal.md`](docs/archive/shipped-design-specs/rec-body-vc-proposal.md));
  increments (a) partiality marker, (b1) fail-closed default, and (c) `(decreases …)` call-site strict
  descent remain open.
- **Sidecar invalidation (one-time):** the `av1` → `av2` bump changes every persisted `verified_hash`,
  so existing `.verified.json` files drift once and re-verify fail-closed on next `verify` (no verdict
  changes — a genuinely body-faithful function re-derives the same evidence). The four git-tracked
  example sidecars are re-verified under `av2` in this release. No schema change (`schemaVersion` stays
  `0.7.0`).

**Tests:** 1102 Haskell, 45 Python. (+4: RHF-1 probe-E regression, RHF-2 fresh-def parity, RHF-3
non-recursive no-drift, RHF-4 form-tag hash sensitivity. Probe E confirmed closed end-to-end against
the built binary.)

## v0.14.21 — checkout brief marks the enclosing function "hole" (HOLE-STATUS) (2026-07-09)

### Checkout — the brief no longer invites a self-call fill

- **The function whose hole is being checked out now reads `status: "hole"` in the brief's
  `available_functions`, not `"filled"`.** Every same-file entry was hardcoded `"filled"` — including
  the enclosing function itself, presenting the agent with an "available" function whose contract
  exactly matches its goal. Observed live (secure-channel-emergent blind-fill run): the agent answered
  the `alert-admit` brief with `(alert-admit latched sev)` — and that degenerate self-call **patches
  cleanly and verifies SAFE**, because a nonterminating body discharges its own contract vacuously at
  partial correctness (the R7/TERM-1 gap; the self-recursive function silently drops out of the
  body-faithful set, so plain `verify` shows no failure). `"hole"` is the documented-but-never-emitted
  third value of the `feStatus` enum.
- **Harness note (for orchestrators):** the enforceable per-fill acceptance bar is *verify SAFE ∧ the
  filled function appears in `body-faithful`* — a fill that lands recursive/contract-only is not a
  verified fill even when the whole file reports SAFE. `--strict-verified-core` catches it at
  whole-program acceptance; the per-step check catches it at fill time.
- The `available_functions` construction is extracted from `Main.assembleCheckoutContext` to
  `Checkout.buildCheckoutFuncs` (testable; regression test DC-8). No schema change; `brief_version`
  stays `0.12.2` (the `"hole"` value was already documented in the enum).

**Tests:** 1098 Haskell, 45 Python. (+1 DC-8; e2e-confirmed — re-briefed, the same blind agent
produced the real body `(and (= sev 1) (not latched))`, verified body-faithful.)

## v0.14.20 — obligation-report vocabulary gate fix (OBLIG-VOCAB-GATE) (2026-07-09)

### Obligation report — an unknown-typed hole no longer empties the function lists

- **The return-type gate applies only when the hole's type is known.** The per-hole
  `contracted_functions` / `available_functions` lists gated every candidate on return-type
  compatibility against `fromMaybe TUnit (holeInferredType …)` — so an unknown-typed hole (common for
  expression-position holes, where the report's structural `analyzeHoles` inference is weaker than the
  checkout brief's sketch inference) behaved as "expects unit": every `-> T`-annotated function and
  every monomorphic-return builtin was dropped, and the lists silently read as "no callable functions"
  where the truth was "type unknown". Worse, the filter inverted DEF-RET's incentive — annotating a
  return type (v0.13.1) made a function *disappear* from unknown-typed holes' vocabulary while
  unannotated ones stayed (vacuously compatible). `assembleFunctionLists` now takes `Maybe Type`:
  unknown ⇒ the full (still cap-8) vocabulary; known ⇒ gated exactly as before.
- **Display:** with an unknown hole type, an annotated function shows its declared `return_type`; an
  unannotated one shows `"?"` (the checkout brief's existing convention) instead of impersonating the
  hole's type. The pre-DEF-RET comment claiming surface forms never carry return annotations is retired.
- **Scope:** `verify --obligation-report` only — the checkout brief has no such gate and is unaffected.
  No live consumer feeds these lists to agents today (orchestrator and harness read the checkout
  token's `available_functions`; the harness captures the report for analysis), so this is latent-debt
  removal on a documented repair-loop surface.
- **Root-cause follow-on tracked as OBLIG-HOLE-TYPE** (roadmap): give the report path the sketch
  inference the brief uses, so an expression-position hole reads its real type and gets the correctly
  *filtered* vocabulary rather than the ungated-full safe default.
- **No schema change** (`schema_version` 0.12.1 unchanged — values only; `expected_type` already
  emits `"unknown"`).

**Tests:** 1097 Haskell, 45 Python. (+3 DC-7 cases: ungated contracted list with `"?"` display,
ungated builtins with cap-8 truncation, known-type gating regression guard; e2e-confirmed — the
cross-module expression-position hole that surfaced the defect now lists both its same-file and
imported callables.)

## v0.14.19 — imported names in brief scope/function channels (XMOD-SCOPE-BRIEF) (2026-07-09)

### Checkout & obligation report — the callable vocabulary is cache-aware

- **`available_functions` lists imported callables.** The checkout brief's function list was built
  from same-file statements only, so an `import`-ed contracted function was invisible as a callable
  even though `consumed_guarantees` (v0.14.18) showed it once called. A new `importedContractedFns`
  lists every imported **exported** contracted function under the name the entry module calls it by —
  bare when an `(open ...)` admits it (selective filter honored; a same-named local def shadows the
  import, which then falls back to its qualified name), qualified otherwise — with `status: "imported"`
  alongside the existing `"filled"`/`"builtin"` provenance values. Non-exported functions never appear
  (`meContracts` is unfiltered; the `meExports` gate keeps the brief from suggesting an
  untypecheckable call).
- **`in_scope` carries imported names.** The brief's sketch env is now seeded with qualified cache
  exports (shared `seedCacheEnv`, extracted from `typecheck --sketch`'s seeding), so the walk's
  existing `SOpen` handler injects bare aliases with the `open-import` source label; the qualified
  name also appears (default `let-binding` label, matching the shipped `--sketch` path).
  `type_definitions` resolves against the merged (cache-aware) alias map, so an imported scope
  type still yields its definition.
- **The obligation report's per-hole `contracted_functions` gains the same vocabulary.**
  `assembleFunctionLists` is cache-aware (same naming rules), and its trust map is bare-aliased via
  `injectOpenedAliases` so an opened import's tier resolves to its qualified trust entry instead of
  the `"builtin"` fallthrough — the same keying fix v0.14.18 applied to the checkout path.
- **`brief_version` 0.12.1 → 0.12.2** (additive: `"imported"` status value; imported entries in
  `in_scope` / `available_functions`). Obligation-report `schema_version` unchanged (new entries,
  no shape change). No AST schema change (`schemaVersion` stays `0.7.0`).

**Tests:** 1094 Haskell, 45 Python. (+6 XMOD-SCOPE cases: bare/qualified naming, local-shadow,
export filter, selective open, seeded-scope provenance; e2e-confirmed on a cross-module fixture
via `checkout` and `verify --obligation-report`.)

## v0.14.18 — cache-aware checkout brief (XMOD-CG-BRIEF) (2026-07-09)

### Checkout — consumed_guarantees sees imported callees

- **The checkout brief's `consumed_guarantees` channel now includes imported callees.** The brief
  assembly built its `ContractEnv` from the entry file's statements only (`Main.assembleCheckoutContext`),
  so a call to an `import`-ed contracted function was silently dropped from the channel while the
  identical same-file call appeared — the confirmed layer-5 residual of the XMOD-COMP finding. The brief
  now seeds its `ContractEnv` from the module cache with the exact recipe the verify path uses
  (`cacheAwareAliasMap` + `cacheAwareContractEnv`, extracted from `emitFixpointWithCache`), so verify and
  checkout consume the same contract set. Brief-completeness only — the guarantee was always consumed in
  the verify VC; no verification behavior changes.
- **`callee_tier` resolves through the qualified trust entry.** Imported trust entries are keyed by
  their qualified name (`lib.double`), so a bare (opened-import) callee would have surfaced the
  `"builtin"` fallthrough tier — the untested keying path the finding doc flagged. XMOD-TIER's
  `injectOpenedAliases` bare-aliasing discipline (selective `open` honored, a local def shadows the
  import) is generalized over the map's value type and applied to the brief's trust map, so the callee's
  real tier surfaces.
- **Observed residual (tracked as XMOD-SCOPE-BRIEF):** the same brief's `available_functions` and
  `in_scope` channels remain same-file-only (the sketch env is not cache-seeded), so an imported callable
  contract still does not appear there. Same family, different channel; untouched by this release.
- **No surface or schema change.** `brief_version` unchanged — this populates an existing field;
  `schemaVersion` stays `0.7.0`.

**Tests:** 1088 Haskell, 45 Python. (+4 XMOD-CG-BRIEF cases incl. a pre-fix contrast control;
e2e-confirmed via `checkout` on a cross-module fixture — the brief carries the imported callee's
guarantee with its real tier.)

## v0.14.17 — body-faithful cross-module assume-guarantee (2026-07-08)

### Verification — cross-module assume-guarantee (XMOD-AG)

- **A caller of an `import`-ed contracted function now verifies body-faithful.** Previously a function
  whose callee was imported fell back to contract-only (`erBodyFallback`) and lost the `verified` tier,
  while the identical same-file call stayed body-faithful. The body-VC `ContractEnv` is now seeded with
  the imported callees' contracts (`emitFixpointWithCache`), so the same assume-guarantee VC discharges
  across the boundary — prove the imported callee's `pre`, assume its `post`; the imported *body* is
  never re-verified. A program can be split into `import`-linked modules and stay `verified` under
  `--strict-verified-core`.
- **Tier still rides the §5.3.4 meet.** A caller of an imported `asserted`/`tested` function is
  body-faithful but tier-`asserted` (not a fallback, not `verified`). The cross-module tier meet and the
  transitive imported-sidecar staleness check were already in place (XMOD-TIER, v0.10-era); this release
  adds only the body-VC side.
- **Nullary-ctor tags stay coherent across the boundary.** Imported contracts are desugared against a
  single cache-aware alias map (entry ∪ imported `STypeDef`s, local-wins) that matches the type
  checker's nominal resolution, so a constructor value in an imported contract and the caller's own body
  get the same int tag; `buildCtorTagMap`'s unambiguous-only guard fail-closes any residual clash. Dead
  `buildContractEnvWithImports` retired in favor of `seedImportedContracts` (dual-keyed bare + qualified).
- **Inherited limitation.** Cross-module ADT identity is nominal-by-name (`compatibleWith` compares
  constructor names, not structure — the unshipped MOD-5 item); this feature rides the type checker's
  existing resolution and does not widen that gap.
- **No surface or schema change.** `import` / `open` / qualified calls already parsed and type-checked;
  `schemaVersion` stays `0.7.0`. `emitFixpointWith` is now a thin empty-cache wrapper over
  `emitFixpointWithCache`, so single-file `.fq` output is byte-identical.

**Tests:** 1084 Haskell, 45 Python. (+6 cross-module body-faithful cases; flagship still 163/163 body-faithful.)

## v0.14.16 — implication sugar =>/<=> (2026-07-07)

### Surface — implication sugar

- **Symbolic `=>` (implication) and `<=>` (biconditional).** A contract invariant "result = 1
  exactly when C" now reads as `(<=> (= result 1) C)` instead of the nested
  `(and (or (not …) …) (or (not …) …))`. Both are binary `bool → bool → bool`.
- **Pure sugar, zero verification change.** `(=> p q)` ≡ `(or (not p) q)` and
  `(<=> p q)` ≡ `(and (or (not p) q) (or (not q) p))`, desugared at VC emission — the emitted `.fq`
  is byte-identical to the `or`/`not` form, so nothing in the decidable fragment changes.
- **First-class in both surfaces.** S-expr `(=> p q)` and JSON-AST `{"op": "=>"}` / `"<=>"`; the AST
  retains them through round-trip. The JSON-AST schema op enum was extended additively —
  `schemaVersion` stays `0.7.0` (compiler-validated; a bump would reject existing files).

## v0.14.15 — fix: bool value-op in body-return position (2026-07-07)

### Verification — bug fix

- **`(not b)` (and any `not` applied to a `bool` value) in a body/return position no longer crashes
  liquid-fixpoint** — a regression introduced by v0.14.14. `not` is valid only in *predicate* position
  in the fixpoint grammar (unlike `&&`/`||`, which are tolerated as expression operands), so
  `result = (not b)` leaked `not` as a free symbol (`Constraint with free vars [not]`).
- **Fix:** `emitPred` rewrites `X = ¬Y` to `X ≠ Y` — a valid two-valued-boolean equivalence, sound
  because `not` on an `int` is TypeCheck-rejected so an `FQNot` operand of `=`/`≠` is always `bool` —
  collapsing nested `not`. Qualifier parameters now also carry their real sorts instead of a hardcoded
  `int`. `not`-value bodies and two-bool-variable equality `(= b1 b2)` now verify body-faithful.

**Tests:** 1073 Haskell, 0 failures.

## v0.14.14 — bool in the body-faithful fragment (2026-07-07)

### Verification — `bool` admitted to `Σ_auto`

- **A native `bool` value now verifies body-faithful** — a `bool` parameter, result, refinement atom,
  or `if`-condition — instead of dropping the carrying function to contract-only (`erBodyFallback`).
  The root was `isIntLike` returning `False` for `TBool`, so a `bool` param never entered the sort
  environment and any body/contract reference to it fell out of the fragment; the sort infrastructure
  (`FQBool`, `emitSort`, `typeToSort TBool`) already existed.
- **Fix:** `isScalarLike = isIntLike ∨ isBoolLike` at the two sort-env sites, plus a `bool`-atom case
  in `classifyGuardM` (a bare `bool` `if`-guard) and in `bodyToPredM`'s bare-`EVar` clause. The
  contract/post translator already mapped `EVar → FQVar` and `LitBool → FQTrue/FQFalse`, so no new
  atom-emission code was required. `QF-LIA + Bool` is decidable — a fourth `Σ_auto` component alongside
  QF-LIA / the measure class / the acyclic-datatype theory (§5.3.3).
- **Scope boundary unchanged:** `float`/`string`/`unit` remain outside the body-faithful fragment —
  `float` is TypeCheck-rejected inside integer predicates, `string` stays measure-only; `(+ b 1)` on a
  `bool` is a TypeCheck error, not a VC coercion.
- **Follow-on:** the flagship gate examples and the cascade leaves can now drop the `int`-0/1 boolean
  disguise (and the `(or (= x 0) (= x 1))` domain preconditions) for real `bool`.

**Tests: 1064 → 1071 Haskell, 45 Python (unchanged).** Seven new `BOOL-FRAG` cases: the positive
witness (a `bool`-gated function goes body-faithful), the refute (a body ignoring its `bool` param
fails — `bool` is reasoned about, not skolem-dropped), the `(= b true)` surface form, a `bool` return,
a `bool` `let`-binding, and the scope-boundary assertions (`FQBool` accepted, `FQStr` still `Nothing`).

## v0.14.13 — Cascading refine op + CDP vacuity gate; cycle-verification spec reconciliation (2026-07-06)

### Orchestration — the `refine` op (cascading decomposition)

- **`llmll refine` — fill a hole AND spawn the contracted sub-holes it calls, atomically.** The dual of
  `patch` (which fills a leaf): a `refine` request installs a hole `H`'s body and adds new top-level
  contracted defs `Gᵢ` (each with a `?body`) that the body references, in one operation reusing the
  whole `applyPatch` lifecycle (staleness compare-and-swap + assume-guarantee re-verify → zero new
  verify code). `H` verifies **modulo** each `Gᵢ`'s contract; each `Gᵢ` becomes a new frontier hole.
  This makes decomposition *emergent* — agents grow a refinement tree top-down — rather than filling a
  human's pre-authored blanks. Demo: `examples/refine-demo/`.
- **Scope-relaxation safety predicate** bounds the op so it cannot become an arbitrary-write escape: a
  `refine` may add a def only if it is (1) introduced by exactly one body-replace + additive
  `PatchAdd /statements/-` ops (no clobbering a sibling), (2) **fresh** (name unbound — enforced
  explicitly, since the type-checker does not reject duplicate top-level defs), (3) **body-referenced**
  by the fill, and (4) hole-bodied.
- **CDP vacuity gate** rejects a spawn whose invented sub-contract a trivial identity / constant /
  projection body already satisfies (it "verifies" nothing). Uses the `WarnIdentity/ConstSatisfiesPost`
  CDP signal (an unfilled `?body` lacks the verification status a satisfying-fraction would need). Not
  yet: the feasibility (no-miracle) gate and a per-instance θ are follow-ons.

### Spec — cycle-verification reconciliation (`§0.1`)

- **`§0.1` corrected: recursive cycles are verified compositionally at *partial* correctness, not
  "contract-only".** `§0.1` previously claimed recursive call cycles fall back to contract-only, which
  contradicted `§4.3` and the compiler: since the "Issue 4" SCC-guard removal, a recursive `def-shell`
  cycle is verified by the **mutual-recursion assume-guarantee rule** (each member assumes its callees'
  posts, proves its own body) — sound at partial correctness (Hoare 1971; Apt 1981). Termination is
  unverified (R7 strict descent would upgrade partial→total); the partial-correctness auto-flag on the
  `def-shell` recursive path (`§4.3`) remains a follow-on. Stale `FixpointEmit.hs` comment fixed. No
  behavior change — documentation + a compiler comment only.

## v0.14.12 — MATCH-WIDEN: mixed-arm & nested matches, scrutinee-constructor posts verify (2026-07-06)

### Compiler — verify (body-VC / EMatch)

- **Mixed nullary+payload two-arm sums now verify body-faithful.** A user sum with one nullary and one single-payload arm (e.g. `Verdict = (| Verified) (| Rejected int)`) — both construction (`(if c Verified (Rejected n))`) and a two-arm `match` on it — previously fell to `body-fallback`; it now discharges. **Nested** matches (a match inside an arm body) discharge at depth.
- **Scrutinee-constructor posts now discharge.** A post that references the *matched value's* constructor (`result = Verified ⇒ sig = Continue`, `sig : Step`) previously left the scrutinee unsorted (`body-fallback`). The arm discriminant changed from a free boolean guard to a **free int-tag equality** `(= scrut$tag k)` + a range fact, with a `desugarScrutCtor` pass rewriting `sig = Continue` → `sig$tag = k`. This is a **conservative extension** — every existing sum-match verdict is unchanged (`settle` / `withdraw-outcome` / `classify` and their `-bad` twins) — and stays in **QF-LIA** (no datatype testers). Arm *declaration* tags are threaded so reordered arms do not false-refute; an un-matched-scrutinee constructor post falls back cleanly.
- **Enables the flagship goto-fail (CVE-2014-1266) pipeline** as one body-faithful function with real `Step` / `Verdict` sum types — `examples/gotofail/` (`pipeline.llmll` verifies; `pipeline-bad.llmll` refutes the skip; `nested.llmll` verifies at depth).
- **Not yet:** sequential matches (two top-level matches in one body) fall back (`asserted`, safe); `> 2`-arm mixed matches; recursive sums (firewall). No JSON-AST schema change.

## v0.14.11 — body-VC A-normalization: calls in argument position verify (2026-07-05)

### Compiler — verify (body-VC)

- **Nested / argument-position calls now verify instead of silently falling back.** The body-VC translation (`bodyToPredM`) emits a contracted call's obligation only when the call's *arguments* are already QF-LIA atoms — so a call in **argument position** (`(f (g x))`), as a **pair component** (`(pair (g x) (h y))`), or in an **if-condition** hit `translateCallArg` (which accepts only a `SimpleVC` argument, not a nested `CallVC`) and fell the whole function back to `body-fallback` → its post was only `asserted` (or a hard error under `--strict-verified-core`). A new **A-normalization pass** — `aNormalizeBody`, run before `bodyToPredM` — lifts such calls into fresh `let` bindings, so every call has the enclosing `let` the emitter's `CallVC`-threading already expects. Calls in tail position and let-rhs are unchanged.
  - The pass is **identity on any expression with no call in argument position**, so it never perturbs a function that already verified body-faithfully (full suite unchanged at 1064/0).
  - **Impact:** a relational pair post over composed calls, and multi-boundary call chains, now verify (`post: verified`) written *naturally* — no manual `let`. This unblocks natural agent-written code across large multi-function programs (see `docs/design/flagship-secure-channel-proposal.md`).
  - The DEMO-COMP §10 `withdraw-twice` nested-call fixture now surfaces its two `call-pre:withdraw` origins (previously zero — the documented limitation this closes).

## v0.14.10 — R5: concurrency-safe `diverge-report` classification (2026-07-05)

> **EXPERIMENTAL.** Affects the R5 `diverge-report` classification path only. No change to the mainline `verify`/`checkout`/`patch` paths.

### Compiler — diverge-report

- **Concurrency-safe fill classification.** `classifyFillStatus` wrote its fixpoint query to a fixed `/tmp/llmll-diverge-<fname>.fq`. When multiple `diverge-report` processes classify a fill for the **same function name** concurrently (e.g. two single-hole scaffolds that share a hole-fn name, run in parallel), that file races — one process's `.fq` can be overwritten mid-solve, corrupting the verified/refuted verdict. Each classification now writes to a unique `openTempFile` path (removed after the solve).
  - Surfaced by the R5-at-scale campaign harness running cells concurrently; a fixed unit test would itself be non-deterministic, so validated via the harness: 10 holes × 4 repeats × concurrency 6 → 100% stable verdicts (serial and concurrent now agree). Full suite 1064/0.

## v0.14.9 — R5: sibling-calling fills classify correctly (`diverge-report`) (2026-07-05)

> **EXPERIMENTAL.** Affects the R5 divergence pipeline (`checkout --multi` / `diverge-report`), an experimental under-constraint **witness generator**. No change to the mainline `verify`/`checkout`/`patch` paths.

### Compiler — diverge-report (R5 stage-1 classification)

- **Sibling-call suppression fixed.** `diverge-report`'s per-fill classification previously used isolated synthetic emission, so any fill calling a user-defined sibling helper classified as `type-error` and was silently dropped from the verified partition — a witness-suppression false-negative (proposal Rev 3; `r5-validation/findings.md` Case 5). Classification now verifies each fill in the **shared program's context**: the hole-fn's body is substituted by the fill, sibling defs are kept and pinned to the trusted shared definitions (a fill cannot weaken a helper it calls), and property `check`s are dropped (R5 grades against the contract, not the checks). A `def-shell` fill's post now verifies **modularly** through helper calls — each callee's contract discharges the call.
  - **Impact:** helper-composing corpora (payments-core / withdraw) become usable with R5; the negative branch's false-negative channels drop from two to **one** (common-mode correlation alone).
  - **Residual (conservative):** a strict-`def` hole-fn calling a sibling stays `type-error` — this isolated pass does not run the pipeline's leaf-verification pre-pass. Never a manufactured witness; R5 hole-fns are `def-shell` by convention.
  - Re-validated end-to-end through the real solver: sibling-divergence (`(maxi x lo)` vs `lo`) → `under-constraint-witness` `{x:0, lo:-1}`; the real payments-core `transfer` datapoint (both fills call `debit`) → both `verified`. Full suite **1064/0**.

### Docs

- `differential-implementation-pressure-proposal.md` → Rev 4 (sibling-call bound → fixed); `experiments/r5-validation/findings.md` dated addendum.

## v0.14.8 — Leanstral demo: experimental `verified-lean` vertical slice (2026-07-05)

> **EXPERIMENTAL / demo-only.** The `--leanstral` path below is a scoped "three-lite" demo, **not** the production Lean verification path (roadmap `LEAN-GA`). It requires a Leanstral API key (`LLMLL_LEANSTRAL_API_KEY`) **and** a local Lean 4 + Mathlib project; with either absent it fails closed and records nothing. It discharges one obligation *shape* — a faithfully-translatable nonlinear-arithmetic body — and makes **no** claim of faithful translation across the other QF-LIA escape classes. The production rebuild (translator faithfulness across all escape classes, the retry-with-error loop, hash-revalidated Lean staleness) remains deferred.

### Compiler — verify (Leanstral demo, three-lite slice)

- **`feat(verify)`: `--leanstral` discharges a faithfully-translatable obligation end-to-end against the live Lean kernel, recording a new `verified-lean` evidence tier.** A "three-lite" vertical slice — a deliberate fraction of the production `LEAN-GA` translator: (1) **faithful obligation translation** (`LeanTranslate.hs`) emits a Lean 4 theorem with `result` **bound to the body** (`h_body : result = ⟦body⟧`) instead of the prior contract-only, body-decoupled form; a minimal `bodyToLean` translates QF-LIA + integer `*` faithfully and returns `Unsupported` (**fail-closed**) for `/`, `mod`, `^`, lists, matches, or any residual free var. (2) **nonlinear-body routing** (`Main.hs`, `HoleAnalysis.hs`) adds one targeted route so a function that lands `erBodyFallback` because its body is nonlinear integer arithmetic (the QF-NIA escape Z3 cannot discharge, `LLMLL.md §5.3.3`) is handed to the Leanstral pipeline instead of terminating at `asserted`. (3) **direct call + kernel-check + evidence** (`MCPClient.hs`) calls `labs-leanstral-1-5`, extracts the ` ```lean ` fenced proof, and **kernel-checks it with `lake env lean` under a local Lean 4 + Mathlib project** before recording any evidence. The demo obligation is `examples/leanstral-demo/square.llmll` — `(post (>= result 0))` over `(* n n)`, proved `by rw [h_body]; nlinarith`.
- **New `verified-lean` DisplayLevel (`DLVerifiedLean`, `Syntax.hs`) — a PEER of SMT `verified`, not a level above it.** Both `isVerifiedLevel`, mutually `evidenceCovers`, and equal-strength under `evidenceMeet`; `verified-lean` additionally carries a Lean-kernel-checked certificate — a *quality* the display string records, not a strength ranking. A `verified-lean` post is assumable in the trust closure exactly where a `verified` one is, and tier counts treat the two identically (`LLMLL.md §5.3.4`).
- **`verified-lean` threads coherently through the trust artifacts** (`TrustReport.hs`, `ProofCache.hs`, `VerifiedCache.hs`, `ObligationAssembly.hs`): the trust report, the `.verified.json` sidecar, and the proof cache each record the tier plus a re-checkable `.lean` certificate, so a third party can independently re-run the kernel check.
- **Config surface.** `--leanstral` (opt in to the live path), `--leanstral-model` (default `labs-leanstral-1-5`), `--leanstral-lean-project DIR` (the Lean 4 + Mathlib project used for the kernel check), `--leanstral-timeout SECS` (default `30`; the model call and the `lake` check share it). The API key is read from the environment (`LLMLL_LEANSTRAL_API_KEY`), never a flag. The pre-existing `--leanstral-mock` (emits `by sorry`, rejected by the v0.14.7 `sanitizeProof` anti-laundering guard) is unchanged.
- **Fail-closed on a missing toolchain.** With `lake` off `PATH` the kernel check returns a `LeanstralUnavailable` diagnostic ("lake not found on PATH — install Lean via elan …") instead of crashing on `execvp`; a missing `--leanstral-lean-project` likewise fails closed. No degenerate proof term can reach `verified-lean` — the v0.14.7 `sanitizeProof` LCF chokepoint (`PROOF-ARTIFACT §4.1`) still gates every `ProofFound`.
- Design of record: `docs/design/leanstral-demo-spec.md` (Rev 0) + `docs/design/leanstral-integration-scope.md §8`/`§8.1` (Step-0 empirical validation: nonlinear kernel-checks 2/2 one-shot; inductive/list is one-shot-miss → one-retry-fix, deferred to production).

No `schemaVersion` change (the demo adds a CLI flag and an evidence-tier value, not an AST-node shape) and no `trust_report_version` change (stays `1.4.0` — `verified-lean` is a new value of the existing display-level field, following the additive-field precedent).

**Tests: 1040 → 1064 Haskell, 45 Python (unchanged).** Twenty-four new: the `verified-lean` evidence threading (trust report / `.verified.json` sidecar / proof cache), `bodyToLean` faithful-translation plus fail-closed-on-`Unsupported`, the nonlinear-body `--leanstral` route, the `lake`-not-found `LeanstralUnavailable` fail-closed path, live-path error surfacing, and the Gap-B follow-on (`isNonLinear` flags operator-form `EOp` nonlinear arithmetic).

## v0.14.7 — R5 differential-implementation-pressure (obs) + anti-laundering guard (2026-07-04)

### Compiler — verify (R5, observational stages 1-2)

- **`feat(verify)`: differential implementation pressure — multi-agent divergence as an existential spec-adequacy witness.** `N` agents fill one hole via the new `llmll checkout --multi N <file> <pointer>`, and among the fills that *all* verify, observational divergence over a shared probe set `Ω` is reported by the new `llmll diverge-report <file> <session>` as an `under-constraint-witness` (the contract admits >1 verified behavior — the spec is under-constrained), `no-divergence-observed` on agreement (no spec-tightness claim is made), or `suppressed-intentional` under `(spec-entropy :intentional)`. This turns agent hallucination-diversity into a signal about the *contract*, not the code: if two independently-verified fills disagree on `Ω`, the specification—not either implementation—is the thing under-specified.
- **New `LLMLL.DivergenceCheck` module** — status partition (verified / type-error / refuted) plus `Ω`-replay bucketing via `evalExprStaticWith`, emitting a standalone `divergence_witness` JSON record (verdict label, verified-fill buckets, a distinguishing witness on divergence). Stage-3 *semantic* equivalence is a marked stub, deferred: no counterexample-model extraction exists yet (see the design's Appendix B).
- **Session isolation.** `checkoutHoleMulti` / `promoteDivergenceWinner` (`Checkout.hs`) run the divergence session on a **disjoint `.llmll-diverge.json` sidecar** with an **isolated scratch copy per token** — the shared working tree is never written and the `CheckoutToken` schema is untouched (no schema-version change). `diverge-report`'s per-fill classification uses isolated synthetic emission, so a fill that calls a sibling hole classifies as `type-error` (a documented bound, design Appendix B).
- Design of record: `docs/design/differential-implementation-pressure-proposal.md` (Rev 2).

### Compiler — verify (anti-laundering guard)

- **`fix(verify)`: degenerate proof terms can no longer launder a proof hole to a verified tier (PROOF-ARTIFACT `§4.1` LCF invariant).** New `MCPClient.sanitizeProof` chokepoint routes every `ProofFound` construction and rejects an empty/whitespace-only proof term, or one using the `sorry` / `admit` tactic, to a `ProofError` instead of accepting it. Matching is **word-boundary aware** — identifiers like `admittance` or `sorry_free` still pass. The `--leanstral-mock` prover emits the degenerate term `by sorry`, which now maps to `ProofError` and **writes an empty cache instead of laundering** a `verified`/`leanstral`-tier entry. The real MCP protocol path is documented as `STUBBED` (matching the code), correcting prior docstring drift that read "implemented but untested".
- Design: `docs/design/leanstral-integration-scope.md §5`.

No `schemaVersion` change (R5 adds no AST-node schema change; the `CheckoutToken` schema is unchanged) and no `trust_report_version` change (the divergence witness is a standalone `divergence_witness` record, not a trust-report field).

**Tests: 1024 → 1040 Haskell, 45 Python (unchanged).** Sixteen new: eleven `R5 DivergenceCheck` cases (positive `under-constraint-witness`, `no-divergence-observed` on agreement, `:intentional` suppression, status partitioning, `Ω`-bucketing, sidecar/session isolation) and five `MCPClient` anti-laundering cases (a genuine `by decide` proof survives; `by sorry` / `by admit` / whitespace-only rejected; word-boundary identifiers pass). Full suite green at HEAD.

## v0.14.6 — zero-install Docker image (2026-07-03)

### Packaging — distribution

- **`feat(packaging)`: a slim (~229 MB) verify-capable Docker image** so a user with no Haskell toolchain can run `llmll verify` and see the SMT refutation. Two-stage build (`haskell:9.6.6` builder → `debian:bookworm-slim` runtime, new `Dockerfile`) bundling the `llmll` binary, the liquid-fixpoint `fixpoint` binary (pinned `0.9.6.3.1`, with `smtlib-backends`/`smtlib-backends-process` extra-deps absent from `lts-22.43`), `z3`, and the baked demo examples. `ENV LANG=C.UTF-8` so GHC's text IO reads non-ASCII sources under the slim base. Because the solver is bundled, the container never reaches the `SOLVER NOT FOUND` (exit 3) path. This is distribution packaging of the compiler only — unrelated to the Docker sandbox that isolates untrusted agent code.
- **`.github/workflows/docker-publish.yml`** — builds the image and runs the container acceptance gate (`scripts/tests/docker-acceptance.sh`: `conserve-bad` → refuted exit 1, `conserve` → SAFE exit 0, never exit 3) on every PR touching the image inputs; on a `vX.Y.Z` tag it enforces `scripts/version_gate.sh`, asserts the tag equals the `LLMLL.md` line-1 banner, then pushes `ghcr.io/machunter/llmll:<version>` + `:latest`.
- **`scripts/llmll`** — thin host wrapper (`./scripts/llmll verify myfile.llmll`); mounts the cwd at `/work`, image overridable via `LLMLL_IMAGE`.

No `compiler/src` change; no schema change; no `LLMLL.md` language surface change (packaging adds no construct, subcommand, or flag). Off-roadmap adoption work; closes the "zero-install/Docker packaging" item flagged in `docs/compiler-team-roadmap.md`'s Active-Items header.

**Tests: 1024 Haskell, 45 Python (unchanged).** Packaging change; the new acceptance coverage is the CI container gate (`scripts/tests/docker-acceptance.sh`), not a Haskell/pytest suite.

## v0.14.5 — trust-report over-annotation-warning JSON gap (2026-07-03)

### Compiler — Trust report

- **`fix(trust-report)`: the module-level `over-annotation-warning` diagnostic (`LLMLL.md §4.4.6`, the guardrail against bulk `(spec-entropy :intentional)` self-attestation gaming) was computed correctly but never reachable via any `--json` output, at any ratio.** `overAnnotationRatio`/`overAnnotationThreshold` (`CDP.hs`) were compared correctly in `Main.hs`, but the emission was a stdout line gated `unless json` — no JSON consumer could ever see it. Found by the new `experiments/adv-spec-weaken-0/` adversarial benchmark (F-001), which showed a single laundered contract in a module of ≥4 functions with genuine contracts produces zero signal in any output mode. Fixed: new `TrustReport.trOverAnnotation` field, emitted as a top-level `over_annotation: {ratio, threshold, warning}` object in `--trust-report --json`, populated whenever a trust report is built (via `--cdp`, `--weakness-check`, or `--strict-verify`). No `trust_report_version` bump (stays `1.4.0`), following the `joint_pbt_witnesses`/`overflow_tainted_fns`/`refuted_fns` additive-field precedent — existing consumers ignore the new key. `--weakness-check --json` alone and `--cdp --json` alone (both without `--trust-report`) remain out of scope; neither had a comparable module-level JSON object before this fix.
- **New benchmark: `experiments/adv-spec-weaken-0/`** — the roadmap's "Adversarial spec-weakening benchmark" (experiment-lead-owned), testing whether `--weakness-check`/`--cdp`/`--spec-coverage` catch a contract deliberately weakened until wrong code verifies. Confirms the closed candidate-set Ω's documented observational-vs-semantic limit (`LLMLL.md §4.4.6`) on two type-classes (arithmetic, list-length), and that the module-ratio guardrail above has a dilution floor a single-function attack clears for free in any module of ordinary size — a design-scope limitation, not a defect, per the CDP proposal's own Risk #3 framing.

**Tests: 1019 → 1024 Haskell, 45 Python (unchanged).** Five new: `C27a`–`C27e` (`over_annotation` reflects ratio/threshold/fired above and below the 30% threshold; JSON-emit shape; `trust_report_version` unchanged).

## v0.14.4 — CDP spec-entropy suppression fix + --strict-verify (2026-07-02)

### Compiler — CDP

- **`fix(cdp)`: `(spec-entropy :intentional | :unknown)` now actually suppresses the low-DP diagnostics `LLMLL.md §4.4.6` documents.** `CDP.hs`'s `buildWarnings` took the annotation as a parameter named `_annotation` — unused — so `identity-satisfies-post`/`const-satisfies-post` fired regardless of annotation under both `--cdp` and `--weakness-check`; `WeaknessCheck.hs` had no annotation-awareness at all. Annotating a contract has been inert since the feature shipped in v0.11 (`121815a`) through v0.14.2 — the only prior test (`C21`) checked the module-level over-annotation *ratio*, never per-function suppression. `WarnSpecInconsistentOrUnproven`/`WarnSpecTooTightForOmega` are deliberately left ungated — a different axis (possible spec inconsistency, not permissiveness-by-design) the annotation was never meant to cover. Closes CDP default-on precondition (c) (`docs/compiler-team-roadmap.md`).
- **New `--strict-verify` flag** — sugar for `--trust-report --weakness-check --spec-coverage --cdp` together, the roadmap's recommended serious-verify path. Deliberately excludes `--strict-verified-core` (stays separate) and deliberately does not change bare `llmll verify`'s default: no wall-clock characterization of the `--cdp` candidate-sweep exists anywhere in the repo (`experiments/cdp-0/README.md` explicitly disclaims measuring it), so changing the cost of an unadorned `verify` invocation was out of scope.
- **Fixed along the way: `--spec-coverage`'s early exit swallowed `--weakness-check`/`--cdp`/`--trust-report` output whenever combined.** Pre-existing on `main`, confirmed identical without this patch — `--spec-coverage` has always hard-exited before the solver pipeline runs. Standalone `--spec-coverage` keeps its fast, solver-free early exit unchanged; only deferred under `--strict-verify` specifically, printing as a trailing section after the full pipeline runs instead.

**Tests: 1014 → 1019 Haskell, 45 Python (unchanged).** Five new: `C23`/`C24` (`:intentional`/`:unknown` suppress `identity-satisfies-post`, score still reported), a `:strict`-regression guard, `C25` (`WarnSpecInconsistentOrUnproven` NOT suppressed by `:intentional`), `C26` (`wcSpecEntropy` threads through `tryCandidate`/`generateCDPCandidates`/`generateWeaknessCandidates`). `--strict-verify` verified by manual CLI smoke test (not a Haskell unit test — `Main.hs`'s CLI parser isn't exposed as a library for `Spec.hs` to test; no existing flag has CLI-level Haskell coverage either). No schema or `trust_report_version` change.

## v0.14.3 — 15-bug pass surfaced by a full documentation + examples audit (2026-07-02)

A from-scratch audit of every core doc and every `examples/` directory (empirical replay of every shown command against a live build, not just prose review) surfaced 15 real, previously-undetected bugs across the parser, codegen, trust-report JSON, CLI, hub, and the Python orchestrator — none were doc issues, all were genuine behavioral defects the audit's command-replay caught that a text-only review would have missed. Each was independently re-verified live (not trusted from a fix report) before merging: rebuilt from scratch, re-ran the full test suite, and reproduced the specific symptom-then-fix for the highest-severity items.

### Compiler — Parser

- **`get-bytes` WASI capability import could never parse.** `pCapKind`'s `get`/`get-bytes` alternatives were tried in the wrong order — `symbol "get"` matched the `get` prefix of `get-bytes` and consumed it, leaving `-bytes` dangling. Fixed via longest-match-first, matching the existing `read-write`/`read` precedent.
- **`def-invariant` had no S-expression production at all.** Only the JSON-AST path (`ParserJSON.parseDefInvariant`) worked; LLMLL.md's own §12 grammar documents an S-expression form that silently failed to parse. Added, producing the same `SDefInvariant` node as the JSON-AST path.
- **False-positive "infinite type" error, not a real occurs-check cycle.** An unannotated empty list's leaked type variable (`TVar "a"`) collided with the builtin `second`'s own fixed type-variable placeholder (also `"a"`) — the checker never freshened type variables per instantiation site, so two logically-unrelated uses of the same variable name spuriously unified. Fixed by freshening a callee's type variables at each call site (scoped to call sites, not full let-polymorphism generalization — sufficient since every observed collision required a builtin's fixed name). This blocked `examples/hangman_json_verifier/hangman.ast.json` entirely; it now typechecks cleanly.

### Compiler — Codegen

- **Generated `Main.hs` for any `def-main` program was uncompilable**, and `llmll build`'s own "stack build OK" self-check never caught it: `runGhcCheck` ran `stack build` in the *caller's* cwd, not the generated package's output directory — a false-positive gate that always built the (already-working) compiler itself. Root defect: `emitEventLogPreamble` over-escaped a lambda (`\\c ->` instead of `\c ->`) and a char literal, both invalid Haskell. Fixing the self-check to actually build `outDir` surfaced two more previously-invisible defects in the same preamble: `hDupTo` doesn't exist (real export is `hDuplicateTo`), and a missing `unix` package.yaml dependency for `def-main` programs. Verified end-to-end: `hangman_json` now builds and runs standalone.
- **Precondition and postcondition runtime checks were dead code under Haskell's laziness (correctness-critical).** `wrapPre`/`wrapPost` bound the check to a `let` binding the function body never referenced, so under call-by-need it was simply never forced — both pre- and post-condition violations silently passed through at runtime. The `asserted` trust tier's entire documented meaning is "not solver-proven, but runtime-checked"; this bug meant that guarantee didn't actually hold for any `asserted` function. Fixed by gating the body directly behind the check as an `EIf` (strict in its scrutinee by construction) instead of routing through a discarded `let`.
- **Any `def-main` program with an underscore in its filename failed to build.** `emitPackageYaml` wrote the raw filename straight into a Cabal `dependencies:` entry as a self-dependency; hpack rejects underscores there. Sanitized (underscore → hyphen) consistently across `name:`, the `executables:` key, and the dependency entry.
- **Two more `def-main` codegen bugs, found while live-verifying the `llmll replay` fix below:** `captureStdout` echoed each step's output via `putStr` (no newline), corrupting event-log line framing; and `hDuplicateTo` doesn't reliably preserve `NoBuffering` across a stdout redirect/restore round trip. Both caused independent replay deadlocks; both fixed in the same preamble.

### Compiler — Trust report & JSON output

- **`pre_source`/`post_source` (RFC-citation provenance strings) always rendered `null`/absent**, despite being correctly parsed (`ParserJSON.hs`) and correctly wired for display (`TrustReport.hs`'s text and JSON formatters) — `collectAllContractStatus`'s `mkCS`/`mkER` never threaded `contractPreSource`/`contractPostSource` through into `erSource`. Broken since a v0.11-era commit (`3391713`), invisible because nothing exercised it. Fixed by threading the source strings through.
- **JSON output double-encoded any non-ASCII text into mojibake** (`§` → `Â§`, em-dash → `â`) — found immediately after the fix above finally put real Unicode citation text on the JSON path for the first time. Root cause: ~20 `--json` formatters (`TrustReport.hs`, `ObligationMining.hs`, `SpecCoverage.hs`, and 17 sites in `app/Main.hs`) built their output via `T.pack . BLC.unpack . encode` — `Data.ByteString.Lazy.Char8.unpack` reinterprets each UTF-8 *byte* as a Latin-1 codepoint rather than decoding it, so a multi-byte sequence becomes two codepoints, and re-encoding that back to UTF-8 downstream double-encodes it. General-purpose bug, present on every affected path, simply never exercised with real non-ASCII content before. Fixed by switching every site to `Data.Aeson.Text.encodeToLazyText`, which builds `Text` directly from the `Value` with no byte-level round-trip.
- **Doubled `@` in `?delegate` hole messages** (`?delegate @@agent` instead of `?delegate @agent`), plus the actual root inconsistency it was masking: the S-expression parser's `pAgentRef` stripped the `@` prefix, while every other source format (JSON-AST fixtures, `AstEmit.hs`, the Python orchestrator) kept it. Fixed both so the invariant holds across every source format, not just patched the display symptom.

### Compiler — CLI

- **`llmll replay` was completely non-functional for every program, always.** `doReplay` calls `doBuild` internally to build before replaying, but `doBuild` unconditionally calls `exitSuccess`/`exitFailure`, terminating the whole process before `doReplay`'s actual replay logic ran — dead code, never reached, no test exercised the real CLI path (only `runReplay` directly). Fixed via a captured-exit wrapper (`runCapturingExit`) so `doReplay` can inspect the build result and continue. Verified live: replaying a real event log now prints "N/N events matched" instead of silently exiting after the build step.
- **`llmll hub fetch --from-file` installed packages one directory level too shallow.** Tar extraction stripped the top-level `<package>-<version>/` directory instead of reconstituting it into the cache's `<package>/<version>/...` layout, colliding across packages. Fixed to rebuild the intended path.
- **`build --help` said "Compile .llmll to Rust"** — a leftover from an early prototype; actual, correctly-documented behavior is Haskell codegen. Corrected.
- **Removed a `docker run ... ghcr.io/machunter/llmll` pointer from the solver-missing banner.** No Dockerfile or published image exists yet (confirmed via a repo-wide grep, zero other references) — the banner's own advice failed for anyone who followed it.

### Orchestrator (`tools/llmll-orchestra`)

- **Checkout-TTL renewal read a JSON key that doesn't exist** (`remaining_seconds`; the CLI emits `remaining_ttl`), so `_ensure_checkout()` always believed a freshly-acquired token was already expired and immediately re-checked-out, colliding with its own lock — every hole-fill attempt failed. The test suite's mock hardcoded the same wrong key, hiding this from CI. Fixed the key name in both the orchestrator and the mock, and added a test that would have caught it.
- **Checkout responses aren't wrapped in `"context"` like `compiler.py` expected** (the real CLI response has flat top-level keys), so the scope-aware prompt-enrichment feature (`_format_context()`) always received `{}` and was silently dead code. Fixed `checkout()` to build a real `context` dict from the actual response shape.
- **`_format_context()` itself read JSON keys that don't exist** (`signature`, `definition`) in the real `FuncEntry`/`TypeDefEntry` shapes (`returns`/`return_type`, no `definition` key) — so even with the fix above, function signatures and type definitions still rendered as `?` placeholders in the agent prompt. Fixed to render from the real fields.

### Examples — fixture-level fixes

These aren't compiler bugs — they're broken or stale content in `examples/` fixtures and their companion docs, found the same way (empirically replaying every claim against a live build) and fixed directly rather than routed to compiler-engineer. Each fix's regression coverage is noted, since none of these have a `compiler/test/Spec.hs` unit test:

- **`pair_type_test/{pair_type_test,do_emit_ac,pair_match_ac4}.ast.json`** predated CAP-1 capability enforcement — missing the `wasi.io` capability import node, so `llmll check` hard-errored on all three. Added the import. *Coverage: `llmll check` on these files directly.*
- **`delegate_demo/{program.ast.json,patch-request.json}`** called nonexistent builtins `int-add`/`int-mul` (real names: `+`/`*`); the documented checkout → patch flow failed with `PatchTypeError` when actually run, not just a cosmetic warning. Fixed to use real operator names; verified the full flow now returns `PatchSuccess`. *Coverage: the checkout/patch flow against this fixture, exercised in `docs/getting-started.md`'s worked example.*
- **`proof_required_test/proof_required_test.llmll`**'s `safe-div` had a bare, contract-free `?proof-required` hole — the Leanstral pipeline was never actually invoked (every run printed "unsupported (empty contract)"), so the fixture's own documented 3-step proof-caching test procedure could never be demonstrated. Added a real `pre`/`post` pair. *Coverage: the fixture's own documented test procedure (`--leanstral-mock` run twice: "proof found" then "cached proof (skip)"), now genuinely reproducible.*
- **`life_json/{world,main}.ast.json`** were each missing an `(open ...)` statement after their `(import ...)` — bare calls to imported functions failed with "unknown function," so `llmll build` never produced a package at all. Added the missing statements. *Coverage: `llmll build` + a from-scratch `stack build` on the output, both now succeed; confirmed the generated executable renders the glider pattern correctly.*
- **`conways_life_json_verifier/life.ast.json`**'s `count-neighbors` was previously outright *refuted* (its callee `neighbor-alive` had no postcondition at all, so the solver had no information to prove `count-neighbors`' own `0<=result<=8` bound against). Added `0<=result<=1` postconditions to `cell-at`/`neighbor-alive`. `count-neighbors`' own body-VC now genuinely discharges, though its *effective*/reported tier stays `asserted` — it transitively depends on `cell-at`, whose body reads a list via `list-nth`, structurally outside the body-faithful fragment, so it can never itself reach `verified`. This is the epistemic-drift mechanism working as designed, documented rather than papered over. *Coverage: `llmll verify --trust-report` (no more refutation; drift warning correctly names the dependency).*
- **`erc20_token/` and `totp_rfc6238/` "frozen ground truth" benchmarks both hard-failed** (`make benchmark-erc20`/`benchmark-totp`), predating three deliberate, already-shipped semantic changes: BODY-VC (v0.8.0), LT-INV core/shell inversion (v0.11.0), and TRUST-PRE/ADMIT-VERIFIED (v0.13.0). For erc20: added missing preconditions to `total-supply`/`balance-of` (now genuinely `verified`) and changed `transfer`/`transfer-from` to `def-shell` (required to call them at all under strict-core admissibility, which needs *persisted* verified evidence a same-file callee can't have yet at type-check time). For totp: `EXPECTED_RESULTS.json`'s `no_contract`/`asserted` counts were stale relative to TRUST-PRE's post-only effective-tier rule. Both `EXPECTED_RESULTS.json` files re-baselined against what's actually achievable today (not silently inflated back to the old "all proven" aspiration) — `erc20_token/EXPECTED_RESULTS.json` gained a `future_work` note on what a genuinely-all-verified version would require (real per-account balance state, not the current single-`int` ledger model). Both gate scripts (`scripts/benchmark-{erc20,totp}.sh`) also had a stale JSON key name (`proven`, from a v0.3.0-era schema) renamed to `verified`. *Coverage: `make benchmark-erc20` (11/11) and `make benchmark-totp` (14/14), both CI gates, now genuinely passing rather than hard-erroring or silently accepting stale expectations.*

**Tests: 978 → 1014 Haskell, 37 → 45 Python.** Every compiler bug above has at least one named regression test (`compiler/test/Spec.hs`); the mojibake and occurs-check fixes were each confirmed necessary by reverting and observing the new test fail before restoring the fix. No schema or `trust_report_version` change.

## v0.14.2 — CDP deep-dive: candidate-basis fix + body-faithfulness gate (2026-07-01)

### Compiler — CDP

- **`fix(cdp)`: the candidate basis now emits real `ok`/`err` candidates instead of the raw internal `Success`/`Error` names.** `768ab11`'s Ω-adequacy gate suppressed the resulting false-positive symptom (any `TResult`-returning contract scored `datatype-return-out-of-scope`) without fixing the mechanism: `WeaknessCheck.hs`'s trivial-body catalog referenced constructor names unregistered in `builtinEnv`, so an independent, lenient-mode re-typecheck let a type-unsound candidate reach the solver. `ok`/`err` are registered with correct polymorphic signatures; `TrivConstError` now carries the real error-payload type instead of a hardcoded string. The now-dead 768ab11 gate (`WarnDatatypeReturnOutOfScope`) is removed. `list-cons` → the actually-registered `list-prepend` (same defect class, different builtin).
- **New general defense: `checkCDPCandidate`/`checkWeaknessCandidate` check `erBodyFallback` before trusting a solver verdict on a candidate's own synthetic body.** A solver-SAFE verdict on a body-fallback emission (list-valued return expressions, e.g., aren't in the QF-LIA-translatable fragment) is not evidence the candidate satisfies the contract — this is the same "unvalidated path reaches solver, reports vacuous SAFE" defect class as the TResult bug, via a different trigger. New typed warning `body-unfaithful-candidates-excluded` (wire label), new `excluded_candidate_count` field (additive) on the `discriminative_axis` JSON block; excluded candidates count toward neither the numerator nor the denominator. `--weakness-check` gets a parallel new diagnostic kind, `weakness-check-candidate-unvalidated`, distinct from `spec-weakness` — a candidate that couldn't be validated is reported as unknown, not silently dropped and not wrongly flagged weak.
- **A second, independently confirmed gap in the same isolated-emission pattern:** `checkCDPCandidate`/`checkWeaknessCandidate`'s per-candidate `.fq` emission omitted the module's `STypeDef` statements, unlike `tryCandidate`'s independent re-typecheck (which already prepends them, F-006). Any candidate referencing a custom sum-type constructor spuriously fell back even when body-faithful with the type-def present. Both call sites now take a `[Statement]` type-defs parameter. `withdraw-outcome` in `examples/withdraw-demo/` now gets genuine CDP measurement (`spec-too-tight-for-omega`, same as its three siblings) instead of the retired blanket suppression.
- **`fix(cdp)`: `WarnSpecInconsistent` renamed `WarnSpecInconsistentOrUnproven`** (wire label `spec-inconsistent` → `spec-inconsistent-or-unproven`). The shipped semantics never implemented the F-005 Rev 4 adjudication the old label claimed (a solver-UNSAT-on-pre∧post check, independent of `Ω`) — no such check exists; the condition actually measured is Ω-relative ("zero candidates satisfy, no independent verification evidence") and cannot distinguish a genuinely vacuous contract from one merely tight-and-unverified. The rename corrects the claim to match the measurement; a true Ω-independent semantic-UNSAT check remains future work.
- **CLI text and JSON put the typed flag first, the graded score parenthetical.** `--cdp`'s stdout summary reorders from `score=X (Y/Z candidates satisfy) [warnings]` to `[warnings] score=X (...)` (score omitted entirely when undefined, rather than printing `score=undefined`). New additive `headline` field on `discriminative_axis` (first warning label, or `"measured"`/`"not-requested"`) gives JSON consumers the same headline-first read without re-deriving it from `score == null`.
- **`fix(cdp)`: `--strict-verified-core --trust-report --cdp --json` now populates `discriminative_axis` correctly.** The strict-core JSON branch called `buildTrustReport` instead of `buildTrustReportWithCDP`, dropping every function's `discriminative_axis` to `"not-requested"` regardless of whether `--cdp` was passed — a pre-existing bug since the flag combination first became reachable. One-line fix, threading the already-computed `cdpResults`.

### Compiler — verify pipeline

- **`fix(verify)`: a function whose post-condition references `list-length` and whose body falls back to non-body-faithful verification no longer crashes liquid-fixpoint.** `usedMeasures` (the `.fq` preamble's measure-constant sweep) scanned constraints and binders but never the auto-synthesized qualifiers (`extractQualifiers`). A body-fallback function emits no constraint mentioning `listLen`, but its `list-length` postcondition still synthesizes a qualifier referencing it — an undeclared symbol, and liquid-fixpoint crashed with `Qualifier with free vars`. Found empirically while verifying the CDP fix above, not CDP-specific; confirmed via revert-and-rerun against the new regression test.

### Known limitation (not fixed, documented)

- **String-payload `Result` construction still falls back in body-VC translation.** `(err "some string")`-shaped candidates or real function bodies are excluded (safely — via the new `body-unfaithful-candidates-excluded` gate above) rather than mis-scored, but never scored either: `bodyToPredM` has no case for string literal *values* (only int/bool); this project's `Str` sort is a documented opaque carrier for measures (`string-length`) only. Extending literal-value support for strings is a real capability question for a future proposal, not a bug fix — see `docs/compiler-team-roadmap.md`'s `CDP default-on` row.

**Tests: 978 Haskell + 62 Python** (+12 net vs. the last recorded count — 966 in the v0.14.1 entry never accounted for `768ab11`'s +5 test delta, which shipped with no doc-lead pass; this entry's 978 is 971 + 7 new (`CDP-BODYFAITHFUL-1..3`, `CDP-CANDBASIS-1..3`, `NIW-B5`)). No `trust_report_version` bump (additive-field precedent for the `discriminative_axis` block); no `schemaVersion` change.

## v0.14.1 — checkout-lock sum-type fix (2026-06-30)

### Compiler — checkout/patch

- **`fix(checkout)`: a sum-type `TypeDefEntry` now round-trips through the checkout lock.** The lock emitter wrote a sum type's constructors as `{name, payload?}` objects, but the parser decoded the `constructors` field via the default `[(Text, Maybe Text)]` instance, which expects two-element arrays. So a checkout lock for **any program with a `data`/sum type in scope** serialized a `type_definitions` entry that `loadLock` could not parse back — `loadLock` returned `Nothing`, and every subsequent `llmll patch` rejected its valid token as `"invalid or expired checkout token"`. This silently broke the agent checkout → patch repair-loop protocol for all datatype programs. The parser now reads the constructor objects the emitter writes. Regression test added (`Checkout helpers`: `decode (encode td) == Just td` for a sum-type `TypeDefEntry`). No schema change, no CLI surface change.

### Examples

- **`withdraw-demo` integrates `withdraw-outcome` as a third fillable hole** — `withdraw`'s total-`Result` sibling (same signature, but it drops the precondition and returns `err Insufficient` instead of demanding `balance ≥ amount`). The repair-loop runbook re-threads to three holes; `withdraw`'s fill shows the contract channel, and the new step 4b carries the full type→contract escalation on `withdraw-outcome` (a `Result`-typed hole). This integration is what surfaced the checkout bug above — a fillable sum-type hole is impossible without the fix.

**Tests: 966 Haskell + 62 Python**

## v0.14.0 — PROOF-ARTIFACT: unified, replayable verification record (staged MVP) (2026-06-30)

### Compiler — the proof artifact

- **`llmll verify <file> --proof-artifact <FILE>`** emits one serializable record per run that consolidates the previously scattered justification surfaces — the trust report, the obligation report, the `.fq` VC, and the `.verified.json` sidecar — plus the determinism-pin delta fields (solver versions/options, codegen-semantics stamp, source hash). The value delivered is a *hermetic, auditable, version-pinned re-verification record* (the F\*-`.hints` / Dafny-caching precedent), **not** a verdict checkable without the solver. A synthesis: no new proof obligation, no `Σ_auto` growth, no `trust_report_version` semantic bump (it composes `1.4.0`).
- **`llmll replay-artifact <FILE>`** re-derives the recorded verdict — recompute the source hash, re-run the stored VC under the pinned solver — and **fails closed** on any source/AST hash mismatch, solver-determinism-input mismatch, or an `unknown`/timeout outcome (a distinct non-verdict, never read as SAFE/UNSAFE).
- **Anti-laundering (LCF discipline).** A positive-tier per-function record (`verified`/`contract-checked`/`tested`) is *structurally unconstructible* without its coherent qualifiers — not refuted, no `fallback_reason` when verified, a `basis` for any recorded discriminative axis. Enforced through a smart constructor on **both emit and deserialization**: a hand-forged artifact claiming `verified` while flagged `refuted` fails to parse. New module [`LLMLL.ProofArtifact`](compiler/src/LLMLL/ProofArtifact.hs).
- The SMT tier ships the **replay (R-) property** only; independent checkability (the C-property) is reserved for the future Lean tier (the reserved `certificate` field), and Z3 proof-object serialization is explicitly rejected. **`unsat_core` is deferred** (a reserved schema field — Z3's core is not cheaply surfaced through liquid-fixpoint); the staged MVP ships the R-property on the full `vc`.

### Schema

- **New [`docs/proof-artifact.schema.json`](docs/proof-artifact.schema.json)** — the artifact schema (the emitter validates against it). No change to `docs/llmll-ast.schema.json` (`schemaVersion` `0.7.0`).

### Docs

- **`LLMLL.md` §5.4** documents the two commands, the R-/C-property split, and the LCF anti-laundering invariant. Design of record: [`docs/design/proof-artifact-proposal.md`](docs/archive/shipped-design-specs/proof-artifact-proposal.md) (Rev 2, settled).

**Tests: 965 Haskell + 62 Python** (+4 `PA-1`..`PA-4`; emit/replay/fail-closed/laundering-reject CLI-probe-verified). Roadmap: PROOF-ARTIFACT shipped (staged MVP).

## v0.13.14 — datatype-tail: admissibility closed under acyclic composition (2026-06-29)

### Compiler — composed-datatype construction

- **The datatype-admissibility predicates now recurse over the acyclic composition of scalar / pair / sum / Result**, completing the construction matrix opened by PAIR-RET → COMP-4-RESULT. A **pair-of-`Result`** component (`(int, Result[int,int])`) is body-faithful, and **nested** (`Result[Result[int,int],int]`) and **composed** (`Result[(int,int),int]`) payloads verify. Two predicates in [`FixpointEmit.hs`](compiler/src/LLMLL/FixpointEmit.hs) changed: `sortableComponent` (`TResult` was a leaf `False` → now recurses on its payloads) and `resultReturnUnsafe`'s payload check (`TPair`/`TResult` recurse). A `list`-carrier payload and a genuinely-recursive type stay firewalled — the deliberate final boundary; they fall back cleanly, never crash (the recursion bottoms out at `admissibleDatatype`). No new solver capability (spike-confirmed the nested applied sorts); `examples/payments-core/settle.llmll` is byte-identical.

### Docs

- **`LLMLL.md` §5.3.3** — the datatype-class clause notes admissibility is closed under acyclic composition (pair-of-`Result`, nested/composed payloads), correcting the v0.13.13 "nested-`Result` falls back" note.

**Tests: 961 Haskell + 62 Python** (+3 `CT-1`..`CT-3`; `PR2-5`/`CR-5` updated for the moved boundary). No schema change (`schemaVersion` `0.7.0`).

## v0.13.13 — COMP-4-RESULT: `ok`/`err` construction is body-faithful (2026-06-29)

### Compiler — Result construction reflects (drift-closure)

- **`(ok e)`/`(err e)` construction is now body-faithful.** A `-> Result[…]` function with a construction post — `(= result (ok n))` or an `if`-totality `(if g (ok x) (err y))` — discharges via the datatype theory (a wrong constructor refutes). Closes a COMP-4 (a) drift: the construction reflection fired only for *uppercase* constructors, so the lowercase Result builtins `ok`/`err` fell back — even though `§5.3.3` / `§5.3.5` already asserted `(Ctor e)` construction over an admissible sum discharges. Result is promoted from fully-opaque to a native polymorphic datatype (the Result analog of `Pair2`): a `typeToSortA` `TResult` case lowering to `(Result a b)`, `ok`/`err` reflection in `exprToPred`/`bodyToPredM`, and a one-time gated `data Result 2 = [ | ok { ok_0 : @(0) } | err { err_0 : @(1) } ]` decl ([`FixpointEmit.hs`](compiler/src/LLMLL/FixpointEmit.hs)). Scoped to scalar and admissible-sum `ok`/`err` payloads (`Result[int,int]`, `Result[int,Box]`).
- **A non-admissible Result payload falls back cleanly.** `resultReturnUnsafe` firewalls a `-> Result` return whose payload is a list / recursive sum / nested Result — `erBodyFallback`, never a solver crash. Return-only, so Result *params* (the skolem-based d-elim path) are untouched: `examples/payments-core/settle.llmll` (Result-param elimination) is byte-identical with an unchanged verdict.

### Docs — verification matrix

- **`LLMLL.md` §5.3.3 / §5.3.5** — the `(Ctor e)` construction clauses now name the Result builtins `ok`/`err` explicitly (scalar / admissible-sum payloads; list / recursive / nested-Result payloads fall back).

**Tests: 958 Haskell + 62 Python** (+6 `CR-1`..`CR-6`). No schema change (`schemaVersion` `0.7.0`). `ok`/`err` ↔ a user `Ok`/`Err` constructor (lowercased) is a flagged niche collision.

## v0.13.12 — PAIR-RET-2: admissible sum/ADT-typed pair components (2026-06-29)

### Compiler — alias-aware pair-component sorts + crash-to-fallback

- **A pair with an *admissible* sum/ADT component now verifies a projection over that component.** `typeToSortA` gains an alias-aware, recursive `TPair` case, so `(int, Box)` lowers to `(Pair2 int Box)` instead of collapsing the sum component to `int`; a post like `(= (second result) (Full n))` discharges via the datatype theory ([`FixpointEmit.hs`](compiler/src/LLMLL/FixpointEmit.hs): `typeToSortA`). Nested `(int, (int, int))` and list `(int, list[int])` components already verified (the recursive `typeToSort`) — unchanged.
- **A non-admissible pair component now falls back cleanly instead of crashing the solver.** A `Result`/`ok`-`err` or recursive-sum component previously mis-sorted the binder (`(Pair2 int int)` for `(int, Box)`) and crashed liquid-fixpoint (`"sort Box is not numeric"`) when the component was projected. New `sortableComponent`/`sigPairUnsafe` route such a function to `erBodyFallback` (the §5.3.3 firewall); a `syntacticUnsafePairRet` guard closes the same residual on the compositional call-VC path. This also removes a latent mis-sorted binder in the scalar-projection-over-sum-component path.

### Docs — verification matrix

- **`LLMLL.md` §5.3.5** — the `EPair`/`first`/`second` row widens: scalar **and** admissible-sum/ADT/nested/list components discharge; `Result` and recursive-sum components fall back via the §5.3.3 firewall.

**Tests: 952 Haskell + 62 Python** (+6 `PR2-1`..`PR2-6`). No schema change (`schemaVersion` `0.7.0`). `Result`-builtin construction (`(ok n)` not body-faithful even without a pair) remains a separate COMP-4 follow-on.

## v0.13.11 — PAIR-RET: refinement predicates over pair/tuple returns (2026-06-29)

### Compiler — pair projections discharge through the datatype theory

- **A refinement post over a pair/tuple return now verifies instead of falling back to `asserted`.** `first`/`second` reflect to datatype selectors and `(pair a b)` to the constructor, so a post like `(= (+ (first result) (second result)) k)` is discharged (`verified`/`refuted`). A 2-tuple is the polymorphic product `data Pair2 2 = [ | pair2 { pair2_0 : @(0), pair2_1 : @(1) } ]` — the single-constructor restriction of the COMP-4 datatype class ([`FixpointEmit.hs`](compiler/src/LLMLL/FixpointEmit.hs): `typeToSort` `TPair`, `exprToPred`/`bodyToPredM` projection + construction reflection; [`FixpointIR.hs`](compiler/src/LLMLL/FixpointIR.hs): `FQDataApp`/`FQTyVar` sorts). Scoped to QF-LIA-scalar components (int/bool/string-measure); an opaque-pair return or a non-`Σ_auto` component operation falls back per the §5.3.3 firewall. Roadmap: PAIR-RET.
- **Fix — datatype selectors are no longer swept into measure constants.** The measure-constant collector excluded constructors but not their selectors; a selector applied in goal position (`(pair2_0 r)`, new with PAIR-RET) emitted a spurious `constant pair2_0`. The sweep now excludes selector names too (retroactively protects COMP-4 selectors).

### Examples — two-account conservation

- **New [`examples/payments-core/conserve.llmll`](examples/payments-core/conserve.llmll)** (+ refuted `conserve-bad`) proves `(first result) + (second result) = from + to` at the body-faithful tier — the sum-conservation headline the single-int `transfer` could not express. DEMO-RUNBOOK Beat C added.

### Docs — verification matrix + Σ_auto reconciliation

- **`LLMLL.md` §5.3.5** — the `EPair`/`first`/`second` row's SMT-contract and SMT-body-faithful columns flip ❌→✅ (scalar components). **§5.3.3** — the datatype class admits single-constructor products; the recursion-exclusion rationale is re-attributed to the recursive-*measure* boundary (the QF recursive-datatype theory is itself decidable — Barrett–Shikanian–Tinelli CADE 2007, Reynolds–Blanchette JAR 2018), not datatype-theory undecidability.

**Tests: 946 Haskell + 62 Python** (+7 `PR-1`..`PR-7`). No schema change (`schemaVersion` `0.7.0`).

## v0.13.10 — COMP-4 polish: nullary-variant typing fix, sentinel-free demos, spec reconciliation (2026-06-28)

### Compiler — nullary-variant construction types as its sum

- **A nullary variant of a payload-bearing sum, constructed via application — `(Empty)` — now types as its sum, not `unit`.** `inferExpr (EApp func [])` for a nullary constructor returned `TUnit` (a "might be a constructor call" placeholder), so `(= result (Empty))` failed type-checking; it now returns the sum type (η: `(f)` ≡ `f`), unblocking a payload-free arm like `(| Accepted int) (| Rejected)` ([`TypeCheck.hs`](compiler/src/LLMLL/TypeCheck.hs)). The payload form `(Full n)` was already fine. Test `C4AC-3`.

### Examples — tcp_rfc793 + session-pay drop the int sentinel

- **Both demos return a real payload-bearing outcome sum instead of the `-1`/`5` int sentinel** (now that COMP-4 (a)/(c) ships native construction). `session-pay` `open-and-pay -> PayOutcome (| Paid int) (| Rejected int)`; `tcp_rfc793` `step -> StepOutcome (| Next int) (| Rejected int)` with a **full transition-table totality** post — stronger than the prior partial state-safety. Outcomes constructed natively, discharged by constructor equality / injectivity. All twins hold their verdicts (3 refuted; `step-weak` survives); `.ast.json` regenerated, DEMO-RUNBOOK / VERIFICATION_SCOPE updated.

### Docs — LLMLL.md verification matrix reconciled

- **`LLMLL.md` §3.4 / §5.3.3 / §5.3.4 / §5.3.5 reconciled to the shipped sum-type surface.** The auto-discharge fragment is now `Σ_auto = QF-LIA ∪ measure class ∪ datatype class (admissible sums)` — the acyclic SMT datatype theory (Barrett–Shikanian–Tinelli; combined with QF-LIA by polite-theory combination), the first discharge beyond pure QF-LIA. The match-verification prose (stale since v0.13.6) now states: a two-arm sum match (`Result`, or a user ADT with **both** arms single-payload) at any nesting depth, consuming the matched payload's refinement; an admissible-sum constructor application; with `>2`-arm / nullary-arm matches and recursive-datatype constructors falling back.

**Tests: 939 Haskell + 62 Python** (+1 `C4AC-3`). No schema change (`schemaVersion` `0.7.0`).

## v0.13.9 — COMP-4 (a)/(c): native datatype construction — the COMP-4 line completes (2026-06-28)

### Compiler — COMP-4 (a): native FQData construction

- **A constructor application over an admissible two-arm sum reflects into a native datatype term** — `(Full n)` / `(Rejected reason)` lower to the FQData constructor, and a function returning such a sum binds its result at the datatype sort ([`FixpointEmit.hs`](compiler/src/LLMLL/FixpointEmit.hs): `typeToSortA`, the `bodyToPredM`/`exprToPred` constructor clauses; [`FixpointIR.hs`](compiler/src/LLMLL/FixpointIR.hs) `emitDataDecl` real-arity fields). A **construction post** `(= result (Full n))` discharges by constructor equality; a wrong payload `(= result (Full 0))` over arbitrary `n` is **refuted** by injectivity.
- **Provenance-partitioned representation:** a nullary enum keeps the int-tag (COMP-3c), an opaque-received sum keeps the skolem-branch (d-elim/(b)), only a *constructed* admissible payload-sum uses the native datatype (`typeToSortA` gates on a real payload field; the strict-core gate admits admissible-sum constructors). A recursive datatype (`Tree = Node Tree Tree`) is firewalled by `admissibleDatatype` (transitive-closure acyclicity) and falls back.
- **First verification beyond pure QF-LIA:** a constructed sum value's constraints are QF-LIA + the SMT datatype theory (constructors / selectors / distinctness, z3-discharged; decidability via polite-theory combination). The int-tag / opaque-skolem / int paths stay pure QF-LIA.

### Compiler — COMP-4 (c): payload-carrying outcome totality

- **A payload-bearing `Accepted`/`Rejected` outcome now verifies a totality post** — `legal -> Accepted(n)`, `illegal -> Rejected(n)` — by constructor equality, the payload-carrying discrimination the int sentinel could not express (uses the (a) mechanism; no separate compiler change).

### Examples — outcome-totality

- **New [`examples/outcome-totality/`](examples/outcome-totality/)** — `classify` (`n >= 0 -> Accepted(n)`, else `Rejected(n)`) reaches `verified` on the legal/illegal totality post; the always-`Accepted` twin is `refuted`.

### Design — COMP-4 complete

- **[`docs/design/comp-4-payload-sums-proposal.md`](docs/archive/shipped-design-specs/comp-4-payload-sums-proposal.md) fully shipped:** COMP-3c (v0.13.5) → COMP-3b-general (v0.13.6) → (d-elim) (v0.13.7) → (b) (v0.13.8) → (a)/(c) (v0.13.9). Sum-type elimination *and* introduction both reachable.

**Scope limits.** (i) A nullary *variant* of a payload sum cannot yet be constructed via application — `(Empty)` types as `unit` (nullary-ctor-value gap; follow-on). (ii) The `tcp_rfc793` / `session-pay` int-sentinel reshape (dropping `-1 = REJECTED` for a real `Rejected` variant) is a deliberate follow-on — the capability ships here, the demo migration is separate.

**Tests: 938 Haskell + 62 Python** (+2 `C4AC-*`). No schema change (`schemaVersion` `0.7.0`).

## v0.13.8 — COMP-4 (b): refined sum payloads — elimination + call-site subtyping (2026-06-28)

### Compiler — COMP-4 (b): a matched sum payload carries its declared refinement

- **A `match` arm now consumes the matched two-arm-sum payload's own refinement** — matching `r: Result[PositiveInt, E]`, the `Success` arm knows `n > 0` (before (b) the payload bound at the trivial refinement, an opaque skolem). Mechanism ([`FixpointEmit.hs`](compiler/src/LLMLL/FixpointEmit.hs)): the `BranchVC` binder field carries an `FQPred`; a read-only refinement env (`RefEnv`) is threaded as a `ReaderT` context (the `bodyToPredM` equations untouched), seeded by the driver from refined-payload params (`payloadRefinement`), so a matched payload binds at its declared refinement instead of `FQTrue`. Applies to `Result` and two-arm user ADTs; an unrefined payload stays `FQTrue` (the d-elim behavior). Stays QF-LIA.
- **The consumption is sound because the refinement is now a caller obligation (introduction).** At every call passing an argument to a refined-payload sum param, the verifier emits a payload-subtyping obligation `∀v. p_arg(v) ⟹ p_param(v)` — a standalone refinement-subtyping Horn constraint discharged by liquid-fixpoint, with a syntactic-reflexivity fast-path (no constraint for param-forwarding). A caller forwarding a weaker payload (`Result[int, E]` → a `Result[PositiveInt, E]` param) is **refused**: `payload subtyping for call to '<callee>' not satisfied in '<fn>' — argument's payload does not satisfy the callee param's declared refinement (COMP-4 b)`. **Declaration-driven** — the refinement is a caller contract derivable from the signature, as a `Word` param's bound is.
- **Migration:** a refined-payload sum param now carries a caller obligation it did not before. A pre-flight scan of `examples/`, `compiler/test/`, fixtures found ZERO refined-payload sum params (the corpus uses only unrefined `Result[int, string]`), so no existing code is affected.

### Examples — refined-payload showcase

- **New [`examples/refined-payload/`](examples/refined-payload/)** — `first-positive` matches a `Result[Pos, string]` and uses the `Success` payload's `> 0` to discharge `(>= result 1)` (elimination); `forward` forwards a `Result[Pos]` arg (reflexive subtyping, accepted). Twins: `-bad-elim` (post `(>= result 2)` — `Pos` yields only `>= 1`) → `refuted`; `-bad-forward` (forwards a `Result[int]` arg) → payload-subtyping refused (introduction).

**Tests: 936 Haskell + 62 Python** (+4 `C4B-*`). No schema change (`BodyVC` binder field is internal; `schemaVersion` stays `0.7.0`). COMP-4 line: (d-elim) v0.13.7, **(b) here**; (a)/(c) construction remain.

## v0.13.7 — COMP-4 (d-elim) + ContractEnv enum-desugar fix (2026-06-27)

### Compiler — COMP-4 (d-elim): two-arm user-ADT opaque-sum elimination

- **A match on a two-arm *user* sum type with QF-LIA-scalar payloads (`int`/`bool`/`string`) now reaches body-faithful `verified`** — the opaque-sum skolem-branch ([`FixpointEmit.hs`](compiler/src/LLMLL/FixpointEmit.hs)) generalized beyond `Result` (`classifyTwoArmAdtArms`, `buildOpaqueSumBranch`, per-constructor derived `SortEnv` keys). Stays QF-LIA, exhaustiveness-only: each arm's payload binds as an unconstrained skolem; consuming a matched payload's own refinement is a later COMP-4 slice. A payload that is itself a sum/recursive type falls back via the soundness firewall. The strict-core `def` body gate (`isCoreBodySyntactic`) admits two-arm single-payload-constructor matches. Implements [`docs/design/comp-4-payload-sums-proposal.md`](docs/archive/shipped-design-specs/comp-4-payload-sums-proposal.md) §3. No schema change.

### Compiler — fix: nullary-enum constructors desugared in the ContractEnv (compositional crash)

- **A verified function calling another whose *contract* uses nullary-enum constructors no longer crashes liquid-fixpoint** with `Constraint with free vars`. `buildContractEnv` stored augmented-but-un-desugared contracts, so compositional assume-guarantee pulled raw enum constructors into the caller's `.fq`; the desugar had covered only the definition site, not the call edge. Fix: `buildContractEnv` desugars stored contracts (the per-function bound-set preserves shadowing). Not `def-shell`-specific.

### Examples — nested-result: the v0.13.6 headline gets a showcase

- **New [`examples/nested-result/`](examples/nested-result/)** — `safe-withdraw` matches a `Result` param *inside* a `let` (nested, not the top-level body) and reaches body-faithful `verified` via COMP-3b-general; the wrong twin returns the raw `Success` payload and is `refuted`. Closes the gap that the only Result-match example (`payments-core/settle`) was the top-level form.

### Design — COMP-4 payload-sums settled

- **[`docs/design/comp-4-payload-sums-proposal.md`](docs/archive/shipped-design-specs/comp-4-payload-sums-proposal.md) (Rev 3)** settled (two professor reviews folded): the elimination/introduction split, native-`FQData` construction, transitive-closure-acyclicity admissibility, and the (d-elim)-first staging. (d-elim) ships here; (b) completeness and (a)/(c) construction remain.

**Tests: 932 Haskell + 62 Python.** No schema change (`schemaVersion` `0.7.0`).

## v0.13.6 — COMP-3b-general: opaque-sum elimination at any nesting depth (2026-06-27)

### Compiler — COMP-3b-general: a Result-variable match verifies at any nesting depth

- **A function whose body matches a `Result`-typed *variable* scrutinee (a param or a `let`-bound value) now reaches body-faithful `verified` at any nesting depth** — not just when the match is the top-level body. Previously a nested `Result`-variable match (under `let`/`if`) fell back to `asserted`: a `Result` variable is absent from the int-only `SortEnv`, so the scrutinee failed to translate. Mechanism ([`FixpointEmit.hs`](compiler/src/LLMLL/FixpointEmit.hs)): `BranchVC` now carries its match-introduced binders (the synthetic guard + arm payloads); `collectBranchBinders` declares them across the whole VC tree (the sole emitter, replacing the former single-shot `extraResultBinds`); a new leading `EMatch` clause detects a `Result`-variable scrutinee via derived `SortEnv` payload-sort keys (`<v>$ok`/`<v>$err`; `$` is not a legal source identifier char) the driver seeds for each `Result` param. Stays QF-LIA. **Exhaustiveness-only:** the post is proven for an arbitrary payload (a fresh `FQTrue` skolem per arm); a matched payload's own refinement is not consumed (that completeness step is future).
- **The v0.13.3 top-level flat-`Result` special-case is subsumed and deleted** — its scrutinee discovery moves into the new `EMatch` clause, its binder declaration into `collectBranchBinders`. The synthetic guard is now the generic `_bv__match_success_N` (the `_flat_` marker is retired) and the arm payloads are alpha-renamed; both bind at their real ok/err sorts (an `Error` payload of type `string` binds at `Str`, not the int default).

### Compiler — refuted-arm localization fix

- **A refuted arm in a nested match is now attributed to the correct branch.** The per-arm obligation tag was computed by a path-index midpoint (`pathIdx < length paths / 2`), correct only for balanced arms; under unbalanced then/else path counts (which nested matches routinely produce) it mislabeled which arm a refutation belonged to. The tag now derives from structural branch provenance (`pathBranchSides`), positionally aligned with `flattenBodyVC`.

**Tests: 928 Haskell + 62 Python** (+4 `C3BG-*`; `C3B-2`/`C3B-3` updated for the subsumed guard name and alpha-renamed payloads). No schema change (`BodyVC` is internal; `schemaVersion` stays `0.7.0`).

## v0.13.5 — Nullary-enum verification (COMP-3b-general Phase 1) + connected session demo (2026-06-27)

### Compiler — COMP-3b-general Phase 1: nullary-enum match + constructor-as-value

- **Idiomatic nullary-enum types matched and used as values in a `def` body now reach body-faithful `verified`**, retiring the int-encoding workaround. A scope-aware pre-translation desugar (`desugarCtorValues`, [`FixpointEmit.hs`](compiler/src/LLMLL/FixpointEmit.hs)) lowers a nullary-constructor value `EVar → ELit` tag and an enum `EMatch → ` right-nested `EIf` on `(= scrut tag_i)`; existing QF-LIA machinery handles the rest (no `BranchVC`/`exprToPred` change, no `FQData` — the S3 invariant holds, stays QF-LIA). `buildSortEnv`/`isIntLike` admit nullary-enum params as int tags; the strict-core `def` gate (`Syntax.isCoreBodySyntactic`) admits N-arm exhaustive enum matches; nullary constructors register as values of their sum type (`TypeCheck.collectConstructors`).
- **Soundness:** the desugar mirrors the type-checker's local→constructor→top-level resolution. Local shadowing is handled via the bound-set (a param `Red` shadowing constructor `Red` stays a variable); cross-enum duplicate constructor names are rejected at type-check. Verified end-to-end on [`examples/tcp_rfc793/`](examples/tcp_rfc793/): `step` (real `(type ConnState …)`) → `verified`; `step-bad` (illegal `Closed+ActiveOpen→Established`) → `refuted`; `step-weak` (post omits the LISTEN clause) → survives. **Scope (Phase 1):** the typed post proves state-safety (no `CLOSED`/`LISTEN→ESTABLISHED` skip), not full illegal→`REJECTED` totality (needs a payload-carrying `Rejected` variant → Phase 2); verify-time only — the runtime/PBT evaluator does not yet evaluate constructor values.

### Examples — tcp_rfc793 re-typed to real enums; connected session demo

- **`examples/tcp_rfc793/` re-typed** from the int-encoded sentinel to real `(type ConnState …)` / `(type Event …)` matched in the body, reaching `verified` via COMP-3b-general — no int-encoding workaround in the source. DEMO-RUNBOOK + VERIFICATION_SCOPE drop the int-sentinel caveat and add the two scope-limit notes (state-safety not totality; verify-time-only constructor values).
- **New [`examples/session-pay/`](examples/session-pay/)** — one verified scenario composing protocol state-safety (`tcp_rfc793 step`), a verified payment (`payments-core debit`), and a bounded amount (`return-refine Word`). `open-and-pay` reaches `verified` through the `step` and `debit` call edges (verified:3, asserted:0); three wrong twins each break one safety rule — `bad-step` (pays pre-handshake) → `refuted`, `unsafe` (no funds guard) → call-site refusal, `unbounded` (`amount:int` not `Word`) → call-site refusal. Single self-contained module, additive QF-LIA throughout.
- **DEMO-RUNBOOKs added** for `withdraw-demo` (return-refine companion beat), `payments-core`, and `tcp_rfc793`; all command output captured from real runs.

**Tests: 924 Haskell + 62 Python.**

## v0.13.4 — Loud verify + protocol & payments demos (2026-06-23)

### Docs — withdraw-demo: complex-return beat (the type is the contract)

- **New [`examples/withdraw-demo/return-refine.llmll`](examples/withdraw-demo/return-refine.llmll) and `return-refine-bad.llmll`** demonstrate a complex (refinement-aliased) return where the return type *is* the contract: a saturating add declared `-> Word` discharges `0 ≤ result ≤ 65535` per-branch via the DEF-RET Unit 2 effective-post fold (no hand-written `post`). The wrong twin (no cap) type-checks and passes in-range tests but is `refuted` body-faithfully — the `maxi` shape lifted to a complex return. Mirrors the `compose` / `compose-bad` repair pair.
- **`verify` reporting caveat documented** ([`docs/getting-started.md`](docs/getting-started.md), [`README.md`](README.md)): `--trust-report` reloads persisted evidence *instead of running fixpoint*, so a solver-refutable function renders as `asserted`, not `refuted`. Use the default `verify` (which runs fixpoint) or `verify --strict-verified-core` to surface `refuted`.

### CLI — `verify` is loud when no solver is present

- **`verify` no longer silently no-ops without a solver.** When neither `liquid-fixpoint`/`z3` is on `PATH`, `verify` prints a `SOLVER NOT FOUND — NOTHING WAS PROVEN` banner and exits `3` (distinct from `1` = refuted), instead of writing a `.fq` stub and exiting `0`. A missing solver can no longer be mistaken for a pass.

### Examples — verified protocol & payments demos

- **New [`examples/payments-core/`](examples/payments-core/)** — a verified `transfer` over a `debit` call edge (no-overdraw + all-or-nothing failure-stasis); `transfer-bad` is `refuted`, `transfer-unsafe` is refused at the call site; `settle` exercises the COMP-3b `Result`-match refinement return. **New [`examples/tcp_rfc793/`](examples/tcp_rfc793/)** — an RFC 793 connection state machine reaching `verified` on the legal-successor invariant; `step-bad` is `refuted` on an illegal transition, `step-weak` shows an under-specified contract letting the bug through. Both stay in the QF-LIA verified core.

**Tests: 914 Haskell + 62 Python (unchanged from v0.13.3).**

## v0.13.3 — Sum-Type Verification Fixes (ADT emission + COMP-3b) (2026-06-23)

### Compiler — fix: liquid-fixpoint ADT declarations no longer crash on user sum types

- **`.fq` ADT (`data`) declarations now emit with source-case type names and `| ctor { }` constructor syntax** ([`FixpointIR.hs`](compiler/src/LLMLL/FixpointIR.hs)). `emitDataDecl` previously produced `data <lowercase> = [ctor 0 | …]`, which liquid-fixpoint rejects on two counts — the type-name position requires an uppercase identifier, and constructors require `| ctor { }` form — so any program containing a user sum type (`(type T (| A) (| B) …)`) crashed the solver with a `.fq` parse error instead of verifying body-faithfully. **No schema change.**

### Compiler — fix: refinement-aliased returns over a two-arm `Result` match (COMP-3b)

- **A function returning a refinement-aliased type whose body is a two-arm `match` on a `Result`-typed parameter now produces a body-faithful VC** ([`FixpointEmit.hs`](compiler/src/LLMLL/FixpointEmit.hs)). COMP-3's `EMatch` encoding previously bailed because the `Result`-variable scrutinee could not translate (the SortEnv is int-only), so the function fell back to `asserted` and a refinement-violating arm was never `refuted`. The body-VC driver now intercepts a flat `match` on a `Result`-typed scrutinee, binds each arm's payload at its declared ok/err sort, and declares the synthetic discriminator and payloads as binders so liquid-fixpoint sees no free variables. A clean fill reaches `verified`; a refinement-violating arm reads `refuted` (per-arm localization). Constructor-dependent postconditions still fall back (unchanged); the encoding stays `Result`-specific and remains in QF-LIA. **Scope:** applies when the function body *is* the match; a match nested under `let`/`if` still falls back (COMP-3b-general, future). **No schema change.**

**Tests: 908 → 914 Haskell (+2 FQDATA, +4 COMP-3b); 62 Python unchanged.**

## v0.13.2 — Return-Refinement Discharge (DEF-RET Unit 2) (2026-06-21)

### Compiler — a refinement-aliased return now discharges (DEF-RET Unit 2)

- **A refinement-aliased return (`-> PositiveInt`) folds into the function's effective postcondition** (commit [`0b27be5`](compiler/src/LLMLL/FixpointEmit.hs)) via a new `augmentContractPost` — the guarantee-side dual of the existing `augmentContractPre`. The body-VC now **proves** the return refinement: the function reads `verified` when the predicate is `Σ_auto` and the body-VC is SAFE, `refuted` when the body violates it, and `erBodyFallback` (asserted) when the predicate is non-`Σ_auto` (the §3.4.5 firewall, now reached via the existing untranslatable-post fallback rather than a special guard). This replaces the Unit-1 conservative "always fall back on a refinement-aliased return" behavior.
- **The return refinement is exported as a caller-assumable guarantee.** It is folded into the effective post in `buildContractEnv`, so a caller of `f : -> PositiveInt` may assume `result > 0` via assume-guarantee (the §3.4.1 elimination at the call site). The composed tier rides the existing §5.3.4 meet: a `verified` callee composes to a `verified` caller, an `asserted` callee floors the caller, and a `refuted` callee is not assumable.
- **A bare `-> RetType` function (no explicit `post`) is now credited `verified`** in the trust report (previously `asserted`) — the return refinement gives such a function a `csPost` slot for the sidecar's verified evidence to surface.

### Compiler — soundness: staleness hash covers the augmented contract

- **The staleness hash (`canonicalDefEvidenceHash`) now covers the *augmented* contract** on write (`Main` `provenCS`) and on same-module revalidate (`TrustReport` `liveHashes` / `collectAllContractStatus`). Editing a `-> RetType` annotation, or redefining an alias's predicate, now invalidates a stale `verified` sidecar — closing a cache-poisoning hole. The same change closes the pre-existing **param-side NIW** staleness hole. Recompute is same-module (alias map in scope), so the augmented hash is reproducible; there is no cross-module recompute site (professor-confirmed, [`def-ret-staleness-hash-review.md`](docs/archive/professor-reviews/def-ret-staleness-hash-review.md)).
- **One-time consequence:** every existing v0.13.1 `.verified.json` sidecar is one-time stale on upgrade and regenerates on the next verify (fail-closed demote-to-reverify, benign).
- **Fixed a pre-existing staleness bypass:** the solver-less `--trust-report` reloaded a raw sidecar (`loadVerified`) instead of the staleness-gated one (`entrySidecar`), so it would have rendered a stale `verified` for a `post`-clause (or return-annotation) edit too. Now staleness-gated.

### Notes

- **No schema change.** JSON-AST `schemaVersion` stays `0.7.0`; `trust_report_version` stays `1.4.0`; obligation-report `orSchemaVersion` stays `0.12.1`. (Design: [`def-return-annotation-proposal.md`](docs/archive/shipped-design-specs/def-return-annotation-proposal.md), Rev 3.)

**Tests: 905 → 908 Haskell (+3 DEF-RET Unit 2); 62 Python unchanged.**

## v0.13.1 — Optional Return-Type Annotation (DEF-RET / OBLIG-1-FOLLOWON) (2026-06-21)

### Compiler — `def` / `def-shell` accept an optional `-> RetType` (DEF-RET)

- **`def` and `def-shell` now accept an optional return-type annotation** (commit [`a948deb`](compiler/src/LLMLL/Parser.hs)) — `-> RetType` immediately after the parameter brackets in the S-expression form (`(def f [params] -> RetType (pre…)(post…) body)`), and an optional `return_type` `Type` field on `DefCore`/`DefShell` in the JSON-AST. Absent the annotation, parsing and semantics are byte-identical to today (`mRet = Nothing`, full inference). This closes a §3.4.6-vs-§12 spec-vs-surface drift: REF-META-5 ([`LLMLL.md §3.4.6`](LLMLL.md), shipped v0.12.0), the AST slot (`SDef.mRet`), `collectTopLevel`, and `checkStatement` already consumed a declared `Just retTy`, but neither frontend nor the schema could *produce* one. (Design: [`def-return-annotation-proposal.md`](docs/archive/shipped-design-specs/def-return-annotation-proposal.md), Settled Rev 2; language-team → professor → compiler-engineer.)
- **When declared, the body is checked against the return type** (`TypeCheck.hs`): a bare named-hole body records `HoleTyped T` (Check-Hole); otherwise the body is synthesized and unified against `T` with a mismatch attributed to the function name (Check-by-Synth). This is §3.4.6 specialized to the def-body return position — no new proof obligation and no new channel.
- **`expected_return_type` is now populated for a function-body hole** when the enclosing function declares a return type (and continues to be populated for sub-expression holes via local inference). Previously it was always absent on the canonical case because `def`/`def-shell` had no return surface to record (`mRet` was structurally `Nothing`). This is the OBLIG-1-FOLLOWON value path; `available_functions` and `assumptions` remain reserved.
- **A refinement-aliased return (`-> PositiveInt`) is handled conservatively (Unit 1).** Checking the body against `A ≜ (where [x:τ] p)` joins the §3.4.1 introduction obligation `p[body/result]` to the body-VC set; a non-`Σ_auto` predicate is non-emittable and forces `erBodyFallback`, so the function is not claimed `verified` on an undischarged return refinement — the §3.4.5 firewall. **Unit 2 — the `augmentContractPost` discharge join that would let a refinement-aliased *concrete* return reach `verified` — is deferred.**
- **Schema:** JSON-AST `schemaVersion` **`0.6.0` → `0.7.0`** (additive-optional `return_type`; `$id` URL bumped to `/schemas/v0.7/`). The reader accepts **both** `0.7.0` and `0.6.0` for backward-compatible reads. `trust_report_version` stays `1.4.0`; obligation-report `orSchemaVersion` stays `0.12.1`.
- **Demo:** [`examples/withdraw-demo/`](examples/withdraw-demo/) — `withdraw`, `double`, and `maxi` now declare `-> int` so the checkout brief surfaces a populated `expected_return_type`. **Tests: 900 → 905 Haskell (+5 DEF-RET); 62 Python unchanged.**

## v0.13.0 — Caller-Obligation Axis + Verified Composition (2026-06-19)

### Compiler — a precondition no longer floors a function's trust tier (TRUST-PRE)

- **A function's effective trust tier now reflects its postcondition evidence, not `meet(csPre, csPost)`** (commit [`4d827b1`](compiler/src/LLMLL/TrustReport.hs)). A precondition is always `asserted` (a caller-side obligation the function never proves), so `evidenceMeet(asserted, _) = asserted` floored every `requires`-bearing function — conflating its *verification status* with its *caller's obligation*, a category error with no precedent in Dafny/F\*/Liquid Haskell (all of which report a `requires`-bearing function `verified`). The summary classifiers (`computeSummary`, `aggregateTiers`), the JSON `effective_level`, and the transitive callee meet (`calleeMinLevel`) now read the post-side level; `teEffectiveLevel` converges onto `teEffectivePostLevel`. A pre-bearing function that proves its post reads `verified`; a composer that discharges a callee's precondition and proves its own post reaches `verified` too. (Design: [`precondition-tier-proposal.md`](docs/archive/shipped-design-specs/precondition-tier-proposal.md).)
- **New first-class `caller_obligations` axis** — per function, carrying the predicate (`{"fn":"withdraw","requires":"(>= balance amount)"}`) on an axis separate from the trust tier, with a co-located `carries_caller_obligations` boolean so the cheapest single-field report read still exposes the conditionality. The axis is **persisted** to `.verified.json` and present on every report path (a `requires` is a static contract property; unlike `refuted` it cannot go stale). `trust_report_version` **1.3.0 → 1.4.0** (additive). The escaped-obligation propagation case is non-strict-core-only — a body-faithful `verified` caller necessarily discharged every callee precondition via a SAFE `call-pre:` VC — so no new `--strict-verified-core` conjunct is required.

### Compiler — strict-core `def`→`def` composition admission (ADMIT-VERIFIED)

- **A strict-core `def` may now call a contracted callee carrying persisted verified evidence** (commit [`62bc65f`](compiler/src/LLMLL/TypeCheck.hs)). The v0.11 LT-INV core-membership check rejected a `def` calling a contracted user function until it was independently verified, but the admissibility seed never loaded persisted evidence — making the v0.9.0 assume-guarantee composition the spec promised unreachable in strict core. `checkCalleeAdmissibility` gains a persisted-evidence leg gated on the full `--strict-verified-core` conjunction (`isVerifiedLevel ∧ erBodyFaithful ∧ ¬erOverflowTainted ∧ hash-valid`), fail-closed on absent hash; `EvidenceRecord` gains `erVerifiedHash` (a canonical `(body, pre, post)` + version-tag hash) with a `downgradeStaleVerifiedSidecar` guard demoting stale imported evidence. (Design: [`admit-verified-callee-proposal.md`](docs/archive/shipped-design-specs/admit-verified-callee-proposal.md).)

### Compiler — assume-guarantee surfaced to agents (DEMO-COMP)

- **`checkout` now returns a `consumed_guarantees` axis** — for a hole's enclosing function, the contracted-callee posts it may assume without re-proving (`{"callee":"withdraw","guarantee":"…","status":"discharged"}`). **`verify --obligation-report` emits per-call-site precondition obligations on SAFE**, and contracted-function records now carry `pre`/`post`/`tier`. **`patch` rejects a fill that calls a callee without discharging its precondition** with a discriminated `PatchVerifyError / callee-precondition-unmet` payload. Obligation-report `orSchemaVersion` **0.12.0 → 0.12.1** (additive). (Design: [`compositional-trust-closure-proposal.md`](docs/archive/shipped-design-specs/compositional-trust-closure-proposal.md).)

### Compiler — cross-module fixes + three bug fixes

- **XMOD-ALIAS** (pre-existing, ~commit `9931a77a`, ~3 months): an imported refinement-type alias (`(type PositiveInt (where [x: int] …))`) now unfolds to its base `int` for arithmetic/comparison in the importing module; previously `(>= balance amount)` / `(- balance amount)` on an imported-typed value failed with `expected int, got PositiveInt`. The importer's `tcAliasMap` is seeded with imported aliases.
- **XMOD-TIER:** an imported `verified` function's tier now reaches the importer's trust report — a bare-vs-qualified name mismatch silently dropped the cross-module dependency edge (`injectOpenedAliases` + a cross-module staleness guard).
- **Parser (serious):** the `do` keyword matched without a word boundary, so any function named `double`/`done`/`dot…` was silently mis-lexed as a `do`-block and miscompiled. Fixed with a `notFollowedBy` guard.
- **ObligationAssembly:** the contracted-function list excluded every `def`/`def-shell` (a `Just ret` filter against parsers that hardcode `defReturn = Nothing`).
- **Checkout:** a `FuncEntry` param JSON round-trip asymmetry (object-shape encode vs. array-shape decode).

### Docs — withdraw-demo re-scripted to two axes + composition

- **The repair-loop demo's trust-closure climax is now two-axis** ([`examples/withdraw-demo/`](examples/withdraw-demo/)): all three functions `verified` (summary `verified: 3`), with `withdraw` carrying a visible `caller_obligations` axis — replacing the prior "`withdraw` floors to `asserted`" beat (removed by TRUST-PRE). A new **§6.5 composition** step (`compose.llmll`, `compose-bad.llmll`) shows "obligation flows down": a composer that discharges `withdraw`'s precondition reaches `verified` (with `consumed_guarantees`); one that drops it is refused at the call-site precondition VC.

### Docs — known gap tracked (XMOD-COMP)

- **Cross-module *verified composition* is a five-layer gap** ([`cross-module-composition-finding.md`](docs/archive/shipped-design-specs/cross-module-composition-finding.md)): layers 1–3 shipped (admission, type-alias, tier-edge); layers 4–5 open (the caller's body-VC emission `ContractEnv` does not carry the imported callee's contract; `consumed_guarantees.callee_tier` shares the bare/qualified miss). Recommended as one dedicated effort gated by a binary-level end-to-end test. A latent same-file sidecar staleness gap is noted there.

### Docs — `LLMLL.md` `def-logic` examples migrated to `def-shell` (v0.12.1 follow-up) (2026-06-17)

- **19 `def-logic` occurrences in `LLMLL.md` prose examples migrated to `def-shell`** — 18 `(def-logic …)` definition forms (`transfer`, `display-word`, `handle-request`, `log-and-respond`, `process-turn`, `login-route`, `build-report`, the 5-form `make-state` record-pattern block, `safe-divide`, `verify-token`, `initialize-game`, `add`, `hmac-sha1-wrap`, and the `sort-list` weakness-demo) plus one CDP-scope comment line. Completes the "Known follow-up" flagged in the v0.12.1 roadmap entry: `def-logic` became a hard parse error under all grammar modes in v0.12.1, so these illustrative snippets no longer parsed. Conservative `def-shell` target (the permissive superset; most of these bodies — `do`-notation, `?delegate`/`?delegate-async`, `seq-commands`, `pair`-records — are strict-core-excluded and require `def-shell` regardless). No behavioral or schema change; `schemaVersion` stays `0.6.0`. Prose/example reconciliation only; no test-count change (862 Haskell + 62 Python).

### Docs — roadmap shipped-history tidy (2026-06-17)

- **v0.11 planning block relocated** into the `Shipped Releases` collapsed `<details>` (consistent with the existing v0.1.1–v0.10 collapsed history); the historical v0.8–v0.10 critical-path ASCII diagram wrapped in `<details>`. v0.12.1 Shipped-Releases follow-up note updated from "await engineer migration" to reflect completion. Roadmap structural tidy; no row-status or acceptance-criteria changes.

**Tests: 862 → 900 Haskell + 62 Python** (+38).

## v0.12.1 — def-logic Removal + def-invariant Node (2026-06-17)

### Compiler — `def-logic` removed from both grammar frontends (LT-INV Rev 4) (2026-06-16)

- **`def-logic` is now a hard parse error under all grammar modes** (commit [`4362ebd`](compiler/src/LLMLL/Parser.hs)) — no auto-rewrite, no `--grammar=legacy` escape valve. The S-expression parser rejects it via `pDefLogicRemoved`; the JSON-AST parser `fail`s on `{"kind":"def-logic"}`. Both emit the new **`removed-construct`** diagnostic kind suggesting `def` (strict-core) or `def-shell` (permissive). `letrec` and `--grammar=legacy` are retained (legacy still parses `letrec`); only `def-logic` is withdrawn from the legacy arm.
- **`def-invariant` promoted to its own `SDefInvariant` AST node** — AstEmit now round-trips `def-invariant` faithfully instead of re-emitting it as `def-logic` (fixes a latent lossy-emit bug). `SDefInvariant` is handled identically to its prior `SDefLogic` storage across the consumer fan-out; the residual `SDefLogic` AstEmit arm is an internal invariant guard (unreachable post-removal).
- **Parse-error diagnostics no longer recommend the removed `def-logic`** (commit [`0256839`](compiler/src/LLMLL/Diagnostic.hs)) — the generic S-expression top-level hint (`megaparsecToDiagnostic`) and the JSON `legacy-grammar-violation` suggestions (`ParserJSON.hs`) now point at `def`/`def-shell` (and `letrec` under `--grammar=legacy`) instead of `def-logic`, which is itself rejected under all modes.
- **Schema:** dead `DefLogic` `$def` removed from [`docs/llmll-ast.schema.json`](docs/llmll-ast.schema.json) (already absent from `Statement.oneOf` since v0.11.1 `d3de0da`); `schemaVersion` stays `0.6.0` (non-breaking — no valid document referenced it). **Tests: 855 → 862 Haskell + 62 Python** (+7: `DEFLOGIC-REMOVE-1/2`, `DEFINV-1/2/3`, `HINT-1/2`).

## v0.12.0 — Refinement Metatheory of Record + Effect/Authority Summaries (2026-06-15)

### Compiler — Bundle B0: `effect_summary` composes across module imports (2026-06-15)

- **`verify --obligation-report` now propagates imported functions' reachable capabilities** (commit [`85d2a7d`](compiler/src/LLMLL/ObligationAssembly.hs)) — `computeEffectSummary` folds the loaded `ModuleCache` into its call-graph fixpoint, so a function reaching `wasi.fs.write` only through an imported callee now reports `fs.write` (previously a cross-module callee contributed `∅`, silently under-reporting). The **`∅`-iff-fully-walked** rule: a callee contributes `∅` only if it is a resolved function (local or imported), a known builtin/constructor, or a recognized primitive; any other applied name — e.g. a call into a module not loaded — joins ⊤ (`"unbounded"`). The obligation report's `cross_module` field is now **computed** (`"single-file"` / `"supported"`), replacing a hardcoded `"unsupported"`. Informational only — preserves the B0 trust-orthogonality invariant; single-file `effect_summary` is byte-identical. **Tests: 851 → 855 Haskell + 62 Python.**

### Compiler — JSON-AST `module` forms now flatten instead of discarding the body (2026-06-14)

- **Fixed:** the JSON-AST `module` form was parsed to a no-op (commit [`15cb8c6`](compiler/src/LLMLL/ParserJSON.hs)) — `parseModuleDecl` discarded the module's imports and body and returned a unit statement, so any module-wrapped JSON-AST submission compiled to an **empty program** and verified vacuously (false `effect_summary: []`, capability-import enforcement bypassed). The parser now **flattens** a `module` into its `imports` ++ body (recursively for nested modules), matching the S-expression parser's `pModuleFlattened`. Module-wrapped programs that previously passed may now legitimately fail type/capability checks — they were never actually checked before. No schema change (the `module` node shape already existed; `schemaVersion` stays `0.6.0`). **Tests: 846 → 851 Haskell + 62 Python.**

### Docs — filesystem import namespace reconciled to `wasi.fs` (LLMLL.md §7, §13.9) (2026-06-14)

- **Corrected the documented filesystem capability-import namespace from `wasi.filesystem` to `wasi.fs`** in §7 (FFI & Capability System) and the §13.9 Standard Command Constructors table. The compiler (`llmll 0.11.2`) has always required `(import wasi.fs (capability ...))`; calls to `wasi.fs.read`/`wasi.fs.write`/`wasi.fs.delete` under `(import wasi.filesystem ...)` are rejected with *"wasi.fs.write requires (import wasi.fs (capability ...))"*. The call names and the §7 line-1443 example were already correct — only four import spellings had drifted. Spec-text reconciliation only; no behavioral change. Surfaced empirically (3/18 attempts of a minimal-agent B0 run followed the stale form).

### Compiler — Bundle B0: per-function effect/authority summary in the obligation report (2026-06-14)

- **`verify --obligation-report` now emits a per-function `effect_summary`** (commit [`b2d9c1a`](compiler/src/LLMLL/ObligationAssembly.hs)) — a sound **may-over-approximation** of the coarse capabilities a function may reach through its call graph (object-capability "authority" sense). A union value: a sorted array of catalog labels (`stdout`, `fs.read`, `fs.write`, `net.http`, `random`, `crypto`) **or** the string `"unbounded"` (⊤ — "may exercise any capability"), the latter at opaque boundaries: `?delegate`/`?scaffold` holes, `haskell.*`/`c.*` FFI, unrecognized `wasi.*`.
- **Informational, orthogonal to trust.** The summary never enters the trust meet, the `EvidenceRecord`, or `verified`/`--strict-verified-core` admissibility — it changes no verification verdict (authority ⊥ trust). Computed as a monotone least-fixpoint over the call graph (`computeEffectSummary`, [`ObligationAssembly.hs`](compiler/src/LLMLL/ObligationAssembly.hs)); the effectful-builtin catalog is closed (`builtinEnv`).
- **Schema:** obligation-report `orSchemaVersion` `0.11.0` → **`0.12.0`** (additive `effect_summary` field). `trust_report_version` stays `1.3.0`; JSON-AST `schemaVersion` stays `0.6.0` (no AST change). Settled proposal: [`docs/archive/shipped-design-specs/bundle-b0-effect-summary-proposal.md`](docs/archive/shipped-design-specs/bundle-b0-effect-summary-proposal.md) (Rev 2; language-team → professor → engineer). Stage B0 of the effect-rows track; the B0 experiment (`experiments/minimal-agent/001-two-agent-auth`) gates the B1 engineer build. **Tests: 838 → 846 Haskell + 62 Python.**

### Spec — REF-META-5: type-assignment judgment (LLMLL.md §3.4.6) (2026-06-14)

- **Type-assignment judgment promoted** to [`LLMLL.md §3.4.6`](LLMLL.md) ([`docs/archive/shipped-design-specs/ref-meta-5-type-assignment-proposal.md`](docs/archive/shipped-design-specs/ref-meta-5-type-assignment-proposal.md), Settled Rev 2; pipeline: language-team → professor → language-team). Spec-track only — documents the existing checker (`TypeCheck.hs` `inferExpr` ⇒ / `checkExpr` ⇐) as **local type inference** (Pierce–Turner, TOPLAS 2000) over a Damas–Milner core, with REF-META-1's checking-mode rule embedding as the refinement-alias instances (`⇐-Refine` / `⇒-Var-Refine`).
- **Not "complete bidirectional."** Per Dunfield–Krishnaswami (*Bidirectional Typing*, CSUR 2021 §3.1), a checking judgment whose only non-hole rule is synthesize-then-unify (`checkExpr`, `TypeCheck.hs:896`) *is* type assignment. LLMLL has exactly one genuine bidirectional rule — hole-goal recording (`TypeCheck.hs:892`) for the sketch flow. The mode-switch is decidable definitional type equality (`expandAlias` + `stripDep` + `unify`), not subsumption (non-goal #1, no subtyping).
- **Completes the REF-META metatheory of record (1–5).** No compiler change, no schema change; `schemaVersion` stays `0.6.0`, `trust_report_version` stays `1.3.0`.

### Spec — REF-META-4: erasure theorem (LLMLL.md §3.4.5) (2026-06-13)

- **Erasure theorem promoted** to [`LLMLL.md §3.4.5`](LLMLL.md) ([`docs/archive/shipped-design-specs/ref-meta-4-erasure-proposal.md`](docs/archive/shipped-design-specs/ref-meta-4-erasure-proposal.md), Settled Rev 3; pipeline: language-team → professor → compiler-engineer trace → language-team). Spec-track only — no compiler change; both the codegen erasure and the soundness firewall already exist. States when the predicate-blind erasure of refinement aliases is sound, in two faces: **Theorem A** (type-level erasure as a phase distinction — sound under the proof-irrelevance fragment, non-goals #2/#4/#5/#6) and **Theorem B** (construction-side discipline — the invariant holds at runtime because it was discharged at `verified` tier at construction and composes via `--strict-verified-core`).
- **`M2 ↔ erasability` demoted** to a co-occurrence: erasability is governed by proof-irrelevance, M2 by verification decidability. `§3.4.4` "Erasability" reworded to drop the M2-causation claim and add non-goals #5/#6.
- **Soundness firewall** identified as the existing body-faithful-VC fallback policy: a non-`Σ_auto` refinement predicate is non-emittable (`exprToPred → Nothing`), forcing `erBodyFallback` ([`FixpointEmit.hs:891-901`](compiler/src/LLMLL/FixpointEmit.hs)) off `verified`/strict-core — an engineer-confirmed sound carve-out. Theorem B's verified-tier scope is co-extensive with REF-META-2's `Σ_auto`.
- **Spec-drift fix:** `§5.3.5` non-QF-LIA alias-intro-obligation row corrected — a refinement-typed binding emits **no** runtime assertion (`augmentContractPre` is verifier-local), contra the prior "runtime assertion" Fallback text. The "Runtime assert" column on both alias-intro rows now carries an in-cell qualifier separating host `pre`/`post` assertions (which fire) from the alias predicate (solver-only).
- **`§3.4.3`** forward-reference to "REF-META-4 territory" resolved to `§3.4.5`. No schema change; `schemaVersion` stays `0.6.0`, `trust_report_version` stays `1.3.0`. **REF-META-5 unblocked.**

### Compiler — NIW: path-(a) measure emission + non-int refinement widening Phase 1 (2026-06-13)

- **Measure-class refinement predicates now verify body-faithfully** (commits [`1b21973`](compiler/src/LLMLL/FixpointIR.hs), [`a0f352b`](compiler/src/LLMLL/FixpointEmit.hs), [`0a3c5c2`](compiler/src/LLMLL/FixpointEmit.hs)). Predicates using `string-length` / `list-length` with QF-LIA arithmetic on their integer images previously routed to runtime (`exprToPred` returned `Nothing`); they now emit as uninterpreted-function applications with **ground range facts** (`(strLen t) >= 0` per occurring measure-term — REF-META-2 §4 local-theory-extension discipline, not a quantified axiom), discharged as QF-LIA+EUF. Implements the path-(a) axiomatization that [`LLMLL.md §3.4.4`](LLMLL.md) / `§5.3.3` (REF-META-3 / REF-META-2) were written ahead of.
- **`.fq` IR gains uninterpreted functions** (Commit A, inert): `FQApp` term node, `FQConstant` function-sorted declarations, `FQStr`/`FQList` opaque carrier sorts. Measure-free programs emit byte-identical `.fq`.
- **Refinement-aliased params verify** (Commit C, F-NIW-1 elim-side): a param of measure-refined-alias type (`w: Word`) gets its carrier sort and its predicate folded into the effective precondition, assumed in the body VC. Stacked aliases (`NonEmptyWord` over `Word`) conjoin both predicates at one witness (`§3.4.4`). Refined `int` params get full intro+elim (call-pre proves them).
- **Intro-side call-pre for measure-refined params** (F-NIW-2, commit [`0b05916`](compiler/src/LLMLL/FixpointEmit.hs)): a caller passing a value to a `Word`-typed param now proves the refinement at the call site (carrier-aware call-argument translation + caller-side carrier binding; also closes a latent `applySubst` gap that left measure-application args un-substituted). Measure-refined params get **full intro+elim**, matching `int`-refined — NIW Phase 1 caller-side complete.
- **Identifier sanitization** (F-NIW-3, commit [`25c489d`](compiler/src/LLMLL/FixpointIR.hs)): LLMLL identifiers admit `-` / `.` / `?` (`Lexer.hs`), but liquid-fixpoint's lexer accepts only `[A-Za-z0-9_]` — a kebab-case function/param/var name with a comparison clause crashed the solver at parse (`unexpected '-'`). Names are now mapped to legal identifiers at the single `.fq` emission chokepoint (`FixpointIR.hs`), covering qualifier names, binders, references, `freshName` result vars, and type/constructor names; identity on already-legal names, so existing `.fq` output is byte-identical. Surfaced during NIW, not NIW-caused.
- **Sound compositional call-pre over let-bound call results** (F-NIW-4, commit [`a801112`](compiler/src/LLMLL/FixpointEmit.hs)): a precondition referencing an earlier call's result — e.g. `withdraw-twice`'s `(let [[after-first (withdraw …)]] (withdraw after-first …))` — left the intermediate a free variable in the verifier emission, so `examples/banking_ledger/withdraw-twice` was *spuriously* `verified` for its whole history (masked pre-F-NIW-3 by liquid-fixpoint mis-lexing the hyphenated name; F-NIW-3 surfaced it as a crash). The later call's obligation now carries the prior call's assumed post (assume-guarantee), so the reference is provable; `banking_ledger` verifies genuinely SAFE and passes `--strict-verified-core`. Single-call programs byte-identical. Not NIW-caused — pre-existing, NIW-exposed.
- **Let-bound non-call values into call-pre** (F-NIW-4b, commit [`3b74d24`](compiler/src/LLMLL/FixpointEmit.hs)): a `let`-bound *non-call* value feeding a later call's precondition — `(let [[y (+ x 1)]] (g y))` where `g`'s pre references `y` — previously left `y` a free variable, because `prependLB` parks such bindings at the leaf of the `CallVC` continuation, below the call-pre obligation. `collectCallPreObligations` now threads the continuation's let-bindings (`subtreeLbs`) into the call-pre constraint environment as their defining equalities (`v = rhs`), filtered by an `inScopeLbs` fixpoint to the subset whose free variables are all in scope at the call (param binders + prior call results) — branch-local and after-call bindings are excluded. Completes the compositional call-pre coverage that F-NIW-4 opened for call results. No JSON-AST schema change. **Tests: 836 Haskell + 62 Python** (inherited from engineer `stack test`).

**v0.12.0 totals: 855 Haskell + 62 Python.** Highlights: REF-META 2–5 (metatheory of record complete — solver-completeness, predicate WF, erasure theorem, type-assignment judgment); Bundle B0 effect/authority summary + cross-module propagation; NIW Phase 1 (non-int refinement widening, intro+elim); JSON-AST `module`-flatten and `wasi.fs` reconciliation soundness fixes. `def-logic` surface removal deferred to v0.12.1.

---

## v0.11.2 — Checkout Context Population (OBLIG-1) (2026-06-11)

### Compiler — OBLIG-1: `llmll checkout` returns the per-hole brief inline (2026-06-11)

- **`llmll checkout` now emits the hole's contract + typing context inline** instead of `null` (commit [`f2262c5`](compiler/app/Main.hs)). `doCheckout` runs parse + sketch type-check — no constraint emission, no solver, so checkout stays at type-check cost — and populates `contract_pre`, `postcondition_goal`, `path_condition` via the new shared extractor [`ObligationAssembly.holeContractBrief`](compiler/src/LLMLL/ObligationAssembly.hs) (reusing the same `enclosingFunc` / `findFunctionInfo` / `collectHoleGuards` / `exprToSExpr` primitives as `mkHoleObl`), plus `in_scope` and `type_definitions` via the Phase-C `buildScopeEntries` / `collectTypeDefinitions` producers — the C3 `Main.hs` threading marked done but never landed. Closes the **OBLIG-1 population gap**: this per-hole brief was previously delivered only by `verify --obligation-report` (OBLIG-2), which remains the whole-program view (all holes, unproven contracts, call-site failures, `refuted_fns`, cross-module).
- **Reserved, not yet populated:** `expected_return_type` and `available_functions` (require sketch-mode hole-type capture in `SketchHole`; `available_functions` additionally depends on the former for monomorphization), and `assumptions`. Cross-module hole scope uses single-file scope. All additive — populating them later needs no token-shape change. `LLMLL.md §11.2` marks these fields reserved.
- **Schema: none.** The OBLIG-1 `CheckoutToken` fields exist since v0.10; the checkout response is a CLI payload, not JSON-AST. `schemaVersion` stays `0.6.0`; `trust_report_version` stays `1.3.0`.
- **4 new tests** (OBR-1..OBR-4 in [`compiler/test/Spec.hs`](compiler/test/Spec.hs)): `holeContractBrief` on a contracted hole (pre + post, empty path), a contract-free hole (all empty), a branch hole (path condition surfaced), and an unknown pointer (empty brief). **Tests: 807 → 811 Haskell + 62 Python.**

**Tests: 811 Haskell + 62 Python.**

---

## v0.11.1 — Verify Fail-Open Closure + Schema-Gap Catch-Up (2026-06-06)

### Compiler — VERIFY-RPT-1: verify reporting fail-open + refuted trust status (2026-06-06)

- **`llmll verify` no longer fails open on UNSAFE** (commit [`b914587`](compiler/app/Main.hs)). `fqResultToReport (FQUnsafe …)` set `reportSuccess = null diags`, so an UNSAFE verdict whose constraint ids did not resolve (the text scrape of liquid-fixpoint's ANSI `Unsafe:` banner yielded `FQUnsafe []`) projected `success:true`, exit 0, empty diagnostics. Now `reportSuccess = False` unconditionally on `FQUnsafe`, a function-level fallback diagnostic (pointer `/statements/N/body`) is synthesized when no id resolves, and `doVerify` routes the exit through the `FQVerifyResult` constructor — not the lossy `reportSuccess` projection.
- **`fixpoint -q --json` for pointer recovery.** `doVerify` and `PatchApply.reVerify` now invoke the solver with `-q --json`; `DiagnosticFQ.parseFQResultJSON` decodes the tag-keyed envelope (`{"tag":"Unsafe","contents":[stats,[ids]]}`) so unsafe ids resolve to `/statements/N/body` source pointers. Also populates the previously-empty `PatchVerifyError` payload. Text `parseFQResult` retained as fallback.
- **`--trust-report` surfaces `verified` again** (Defect 2). `VerifiedCache.sidecarNeedsRevalidation`'s INT-1 field-absence trigger invalidated every v0.11 verified sidecar (LT-INT legitimately omits `overflow_tainted`), so `loadVerified` returned `Map.empty` and the report rendered `asserted`. The field-absence trigger is disarmed; an in-code trip-wire pins re-arm to `machine-int`/INT-3 via a codegen-semantics-version check, not field-absence.
- **`refuted` trust status + `--strict-verified-core` solver-verdict conjunct** (spec companion [`verified-contract-refuted-status-proposal.md`](docs/archive/shipped-design-specs/verified-contract-refuted-status-proposal.md), settled). A body-faithful function the solver reports UNSAFE is now *refuted* — distinct from `asserted`. `--strict-verified-core` refuses it transitively (assume-guarantee). `refuted` is an orthogonal verify-time status (not a `DisplayLevel`; `evidenceMeet`/`evidenceCovers` unchanged), surfaced as per-entry `refuted`, top-level `refuted_fns`, and a `depends-on-refuted` drift. Not persisted to `.verified.json`. **`trust_report_version` `1.2.0` → `1.3.0`** (additive). The `--trust-report`/`--obligation-report`/`--cdp` early exits are deferred under strict mode so the gate is reachable.
- **8 new tests** (VR-1..VR-8 in [`compiler/test/Spec.hs`](compiler/test/Spec.hs)); T13 updated to assert the corrected non-invalidation. No JSON-AST schema change. **Tests: 801 Haskell + 62 Python.**

### Schema — LT-INV schema-update subtask: DefCore/DefShell (2026-06-02)

- **`docs/llmll-ast.schema.json`: `DefCore` and `DefShell` definitions added to `$defs`; `Statement.oneOf` updated; `DefLogic` deprecated** (commit [`d3de0da`](compiler/test/Spec.hs)). Under `GrammarCoreInversion` (default since v0.11), `{"kind":"def-logic"}` was rejected by the compiler but `DefLogic` was still the only function-definition node in the schema — any LLM generating from the schema produced files the compiler rejected with `core-grammar-violation`. Closes the LT-INV schema-update subtask recorded in [`docs/archive/shipped-design-specs/core-shell-inversion-proposal.md`](docs/archive/shipped-design-specs/core-shell-inversion-proposal.md) Rev 4.
- **`DefCore`** (`kind:"def"`; required: `kind, name, params, body`; optional: `pre, post, spec_entropy`): strict-core function node. Description cites the core-body whitelist and the `GrammarCoreInversion` default. Two `examples` blocks added (`withdraw`, `clamp`).
- **`DefShell`** (`kind:"def-shell"`; same required/optional fields): permissive-shell function node. Description notes lambda, recursion, `wasi.*`, `?proof-required` are admitted. One `examples` block added (`factorial` with self-recursive call).
- **`DefLogic`** (`kind:"def-logic"`): retained in `$defs` with a `DEPRECATED — v0.11 (LT-INV)` description header; **removed from `Statement.oneOf`**. Schema validators now reject `kind:"def-logic"` (no matching `oneOf` branch); the compiler already rejected it since v0.11. Will be removed from `$defs` entirely in v0.12.
- **`spec_entropy` field** added to `DefCore` and `DefShell` (backfills the LT-CDP JSON-AST gap: `ParserJSON.hs:parseDefCore/parseDefShellJSON` accepted `spec_entropy` via `.:?` since LT-CDP shipped, but `additionalProperties: false` in the old `DefLogic` definition blocked schema-conforming files from including it).
- **`TrustDecl` description** updated: "Must appear before any def-logic" → "Must appear before any `def` or `def-shell` function declaration."
- **`schemaVersion` const and `$id` URL unchanged** (`"0.6.0"`, `/schemas/v0.6/`). DRIFT-CI-1 C3/C4 PASS confirmed by `scripts/version_gate.sh`.
- **4 new tests** (SCHEMA-1..4 in [`compiler/test/Spec.hs`](compiler/test/Spec.hs)): SCHEMA-1 `kind:"def-shell"` parses as `SDefShell` under `GrammarCoreInversion`; SCHEMA-2/3 `spec_entropy` round-trip for `def` and `def-shell`; SCHEMA-4 `kind:"def-logic"` diagnostic carries suggestion referencing `def`/`def-shell`. **Tests: 793 Haskell + 62 Python.**

### Schema — WeaknessOkDecl v0.6 schema gap closure (2026-06-06)

- **`docs/llmll-ast.schema.json`: `WeaknessOkDecl` added to `$defs` and `Statement.oneOf`** (commit [`6af4975`](compiler/src/LLMLL/ParserJSON.hs)). `kind:"weakness-ok"` was dispatched by `ParserJSON.hs:179` and emitted by `AstEmit.hs:200-202` since v0.6.0, but was absent from `Statement.oneOf` — `examples/totp_rfc6238/totp.ast.json` and `totp_filled.ast.json` failed external JSON Schema validation, and any LLM generating from the schema could not produce a conforming `weakness-ok` node. `WeaknessOkDecl` requires `kind, name, reason`; `reason` carries `minLength: 1`, aligning the schema with `LLMLL.md §4.5:621` ("the parser rejects bare `weakness-ok` without a reason string"). `schemaVersion` unchanged at `"0.6.0"`.
- **Empty-reason guard added to `parseWeaknessOkDecl`** ([`compiler/src/LLMLL/ParserJSON.hs:397`](compiler/src/LLMLL/ParserJSON.hs)). The S-expression parser (`Parser.hs:447`) has enforced non-empty reason since v0.6; the JSON path did not — `{"reason":""}` was silently admitted. `when (T.null reason) $ fail "weakness-ok requires a non-empty reason string"` closes the asymmetry. `Control.Monad (when)` added to imports.
- **3 new tests** (WO-J1..WO-J3 in [`compiler/test/Spec.hs`](compiler/test/Spec.hs)): WO-J1 positive parse as `SWeaknessOk`; WO-J2 empty-reason rejection (`json-decode-error`); WO-J3 co-parse alongside a `def` node. **Tests: 804 → 807 Haskell + 62 Python.**

### Doc lead — CHANGELOG `## Latest` anchor restored (2026-06-03)

- **`<a id="Latest">` anchor re-added to `CHANGELOG.md`** (commit [`84d8166`](CHANGELOG.md)). The `README.md:5` "Current version" callout links to `CHANGELOG.md#Latest`; the anchor had been dropped, breaking the deep-link. Prose backtick citations in the affected entries converted to hyperlinks. Doc-infra only; no schema, spec, code, test, or version change.

**Tests: 807 Haskell + 62 Python.**

---

## v0.11.0 — Core/Shell Grammar Inversion + Evidence-Axis Enrichment (2026-05-31)

### Compiler — LT-INV: CDP fixture + test surface def-logic cleanup (2026-05-31)

- **`compiler/test/fixtures/cdp/*.llmll` migrated `def-logic` → `def`/`def-shell`** (commit `56f00dd`). These three fixture files (`verified-strong.llmll`, `verified-weak.llmll`, `intentional.llmll`) were dead — no test loads them — but carried `def-logic` and single-semicolon comments, neither of which parse under `GrammarCoreInversion` (lexer requires `;;`). `verified-strong.llmll` and `verified-weak.llmll` → `def` (QF-LIA / `EVar-int` bodies); `intentional.llmll` → `def-shell` (`spec-entropy :intentional` marks intentional CDP suppression; `def-shell` scope is semantically appropriate). Return-type annotations (`-> int`) stripped from all three (`def`/`def-shell` do not parse return-type annotations).
- **Tests C12-C15 (`Spec.hs:6577-6604`) updated** from `GrammarLegacy`+`def-logic` to `GrammarCoreInversion`+`def-shell`. These tests cover the `(spec-entropy ...)` annotation parse path; the annotation is valid on `def-shell` under `GrammarCoreInversion`. `SDefLogic` pattern matches in C12-C13 → `SDefShell`; C14 JSON `"kind":"def-logic"` → `"kind":"def-shell"`; C15 rejection test updated to `def-shell` (grammar-mode independent for the bogus-`spec_entropy` error path). **No remaining `def-logic` keyword instances** in `compiler/test/fixtures/` or in explicit grammar-mode test paths. Residual `SDefLogic` AST constructor usages in `Spec.hs` (programmatic AST construction) are v0.12 scope when `def-logic` is removed from `GrammarLegacy`. **Tests: 788 Haskell + 62 Python** (no change).

### Compiler — LT-INV: sexp example migration complete; version bump 0.11.0 (2026-05-31)

- **17 `.llmll` S-expression example files migrated from `def-logic` to `def`/`def-shell`** (commits [`283f4e5`](compiler/test/Spec.hs), [`5241965`](compiler/package.yaml)). 38 functions → `def` (49.4%), 39 → `def-shell` (50.6%) per `isCoreBodySyntactic` ([`Syntax.hs:602-624`](compiler/src/LLMLL/Syntax.hs)) + `checkCalleeAdmissibility` ([`TypeCheck.hs:347-361`](compiler/src/LLMLL/TypeCheck.hs)) classification, cross-referenced against commit `f09c498` JSON-AST migration. All `examples/**` S-expression source now parses under the default `GrammarCoreInversion` mode without `--grammar=legacy`. Four `parseStatements GrammarLegacy` file-reading calls in [`compiler/test/Spec.hs`](compiler/test/Spec.hs) (lines 154, 5158, 5173, 5190) updated to `GrammarCoreInversion`; three `SDefLogic` golden patterns (lines 5163, 5177, 5193) updated to `SDef`. No test count delta. **Tests: 788 Haskell + 62 Python.**
- **`tictactoe_sexp/tictactoe.llmll` and `pair_type_test/pair_type_test.llmll` migration completed (commit `17d0da6`, 2026-05-31).** These 2 files were reverted from `def-logic` → `def-shell` after `283f4e5` and remained at `def-logic` in HEAD. `tictactoe_sexp/tictactoe.llmll`: 15 `def-logic` → `def-shell` (list ops, string ops, WASI IO, pair state throughout). `pair_type_test/pair_type_test.llmll`: additionally fixes three pre-existing issues masked by the earlier parse failure — (a) return-type annotation `: (string, string)` stripped (`def`/`def-shell` do not support return-type annotations); (b) `def-main :console` → `def-main :mode console` (legacy shorthand retired); (c) `lambda` → `fn` with typed params; (d) `wasi.io` capability import added (CAP-1). `make-pair` reclassified `def-shell` (`s: string` is `EVar-non-int`). All 17 `examples/**` `.llmll` files now parse under `GrammarCoreInversion` without `--grammar=legacy`. **Tests: 788 Haskell + 62 Python** (no change).
- **Version bump `0.10.8 → 0.11.0`** in [`compiler/package.yaml`](compiler/package.yaml) and [`compiler/llmll.cabal`](compiler/llmll.cabal).

### Language team / Doc lead — LLMLL.md §2.1, §2.5, §4.1, §4.2 canonicalization (2026-05-31)

- **`LLMLL.md §4.1` rewritten: `def` and `def-shell` are now the canonical function-declaration keywords.** Section heading `### 4.1 def-logic (Pure Functions)` → `### 4.1 Function Declarations (def and def-shell)`. Opening prose, syntax skeleton, and `withdraw` example updated; `def-logic` relegated to a `> Legacy grammar` blockquote. A `def` vs `def-shell` selection rule table added.
- **`LLMLL.md §4.2` rewritten: recursive functions documented as `def-shell`.** Section heading `### 4.2 letrec (Recursive Functions with Termination Measures)` → `### 4.2 Recursive Functions (def-shell)`. `countdown` `def-shell` example replaces `letrec`; partial-correctness caveat preserved. `letrec` form relegated to `> Legacy grammar` blockquote.
- **`LLMLL.md §4.3` examples updated:** `def-logic` → `def`; `(* x 2)` function body → `(+ x x)` (multiplication not in strict-core whitelist — `isCoreBodySyntactic` rejects `EOp "*"` at `Syntax.hs:622`; `(+ x x)` is semantically equivalent and core-admissible). `also-bad [result: int]` example dropped — compiler does not enforce `result` as a reserved parameter name; prior "COMPILE ERROR" claim was inaccurate (spec-compiler drift; compiler-engineer scope).
- **`LLMLL.md §2.1` keywords bullet, §2.5 naming table, §4.4.1 trust table, §4.4.3 trust ordering:** phrase updates replacing `def-logic`/`letrec` references with `def`/`def-shell` and `--grammar=legacy` notes. No test count delta. No schema delta.

### Doc lead — getting-started.md §1–§4.13 def-logic/letrec prose canonicalization (2026-06-01)

- **`docs/getting-started.md §1–§4.13`: prose references to `def-logic` and `letrec` updated** to name `def`/`def-shell` as canonical and `def-logic`/`letrec` as `--grammar=legacy`-only forms. Seven prose sites updated; code-block examples left untouched (stale code-block findings are compiler-engineer scope). §4.10 section heading and prose rewritten around the existing `letrec` code blocks; §4.11 `?proof-required(complex-decreases)` table row qualified; §3 coverage sentence updated; §4.7 import-ordering table and blockquote prose updated; §4.8 export-ordering prose updated. No test count delta. No schema delta.
- **`docs/getting-started.md §4.15+`: two remaining prose sites updated.** `§4.17` let-generalization sentence and `§4.17` `Known limitation` NOTE updated: `def-logic`/`letrec` → `def`/`def-shell` (canonical) plus `def-logic`/`letrec` (legacy). Six stale `def-logic` code-block examples in §4.15–§4.19 deferred to compiler-engineer pass.

### Compiler — self-recursion warning gated to GrammarLegacy (2026-05-31)

- **Self-recursion warning suppressed under `GrammarCoreInversion`** ([`TypeCheck.hs:1043`](compiler/src/LLMLL/TypeCheck.hs)). Previously, a `def-shell` self-recursive call emitted `"self-recursive call to '…' inside def-logic; use (letrec … [...] :decreases ...) …"` — a stale message referencing `def-logic` and `letrec`, neither of which are available under the default grammar. Under `GrammarCoreInversion`, `def-shell` self-calls are correct by design (`LLMLL.md §4.2`); `def` self-calls already receive the more precise `core-membership-violation` from `checkCalleeAdmissibility`. Warning retained unchanged under `GrammarLegacy` where `def-logic` and `letrec` are the applicable forms. Existing mixed-mode test (`Spec.hs:801`) corrected: `typeCheck GrammarCoreInversion` → `typeCheck GrammarLegacy` to match the `GrammarLegacy` parse side. New test: `def-shell` self-recursive call under `GrammarCoreInversion` asserts no self-recursion warning. **Tests: 789 Haskell + 62 Python.**

### Doc lead — getting-started.md §4.15–§4.19 code-block migration (2026-06-01)

- **17 stale `def-logic` code-block instances in `docs/getting-started.md` migrated to `def`/`def-shell`** (commits `ed009f0` / merge `eb5f82e`). Pure functions (`use-nonneg`, `use-pair`, `use-nested`, `id`, `bad`, `safe-divide`, `clear-screen`, `sort`, name-template pattern) → `def`; side-effecting and hole-bearing functions (`transfer`, `greet` ×2, `log-login`, `build-report` ×2) → `def-shell`. One prose line in the §2 output-layout table updated (`"all def-logic, types, builtins preamble"` → `"all def/def-shell, types, builtins preamble"`); the `--weakness-check` trivial-body output snippet in §3 updated (`def-logic sort-list` → `def sort-list`). Intentional legacy-prose references (the `--grammar=legacy` section at §4.14, the let-generalization NOTE at §4.17, and the pitfall table) preserved unchanged. Closes the "compiler-engineer scope" deferral in `### Doc lead — getting-started.md §1–§4.13 def-logic/letrec prose canonicalization` above. No test count delta. No schema delta.

### Experiments — §8 gate: EL-5 clean gate run (20260530T052351Z)

- **Run `20260530T052351Z`** ([`experiments/minimal-agent/findings/postmortem-006-el5-clean-gate.md`](experiments/minimal-agent/findings/postmortem-006-el5-clean-gate.md)) used the EL-1+EL-2+E3+F-GATE-7 evaluator under `GrammarCoreInversion` enforcement (llmll `b8c15dd`, compiled 2026-05-29). 8 attempts: claude-opus-4-7 ×5, gemini-3-pro-preview ×3; 0 exclusions — first gate run with 0 gemini quota failures across all 3 cells.
- **Axis (c): 8/8 (100%) `?proof-required` emission; 6/8 `prc_accepted` (asserted-ceiling path).** F-GATE-7 (`normalize_trust_status` suffix-strip) and F-GATE-8 (`guardDelegate` blocks `DLTested` lift for `def-shell + hole-delegate`) fully eliminate all prior contamination. Grade-A paths confirmed: Path A — `def-shell + hole-delegate` → `asserted` via F-GATE-8 (claude try01, try05); Path B — `def + hole-delegate + unevaluable pre` → whole-function `asserted` via pre-clause unevaluability propagation (claude try02–04). Gemini try01/03 grade A via `tested` trust status accepted under F-GATE-7 fix.
- **Grade distribution: 7/8 grade A, 1/8 grade C.** Gemini-try02 grade C is a PBT property coverage gap (3/3 properties gave up after 1000 discards each) — unrelated to grammar mode, trust guard, or contract quality (`contracts_met: True`, `prc_accepted: 1`). F-EL5-2 filed as observation for experiment-lead.
- **§8 gate adjudication: PASS — definitive.** Axis (c) 0/6 pre-arm → 8/8 EL-5. No exclusions. PM-005 was not a clean reference run (F-GATE-7 + F-GATE-8 confounders); PM-006 is the clean dataset. Grammar default flip and schema bump unblocked. See [`experiments/minimal-agent/findings.md`](experiments/minimal-agent/findings.md) §Language-team for the four-axis gate table. F-EL5-3 (language-team + compiler): `def + hole-delegate` → `asserted` unconditionally; adjudicated language-team 2026-05-30; compiler fix (commit `63b9bb3`) confirmed; `LLMLL.md §4.4.5/§5.3.5/§6` pending markers closed this pass; see `### Compiler — F-EL5-3` below. **Tests: 783 Haskell + 62 Python** (no change this pass).

### Compiler — LT-INV CE-3: grammar default → GrammarCoreInversion; schema re-bump 0.5.0 → 0.6.0 (EL-5 confirmed, 2026-05-30)

- **`GrammarCoreInversion` is now the default grammar mode** — re-applied after CE-2 rollback (`b8c15dd`, 2026-05-29). EL-5 clean gate run (PM-006, above) is the definitive empirical basis; §8 gate PASS is no longer conditional. All `llmll` subcommands parse under `--grammar=core-inversion` by default. Programs using `def-logic` or `letrec` must pass `--grammar=legacy` explicitly. `llmll --help` reports "core-inversion (default) or legacy (v0.10 compatibility)".
- **`expectedSchemaVersion` re-bumped to `"0.6.0"`** in [`compiler/src/LLMLL/ParserJSON.hs:41`](compiler/src/LLMLL/ParserJSON.hs). Files with `"schemaVersion": "0.5.0"` are rejected with `schema-version-mismatch` (exit 1). Submitted `.ast.json` files must carry `"schemaVersion": "0.6.0"`.
- **`docs/llmll-ast.schema.json` re-bumped:** `$id` URL `v0.5 → v0.6`, `title` updated, `schemaVersion.const` → `"0.6.0"`, `schemaVersion.description` updated. DRIFT-CI-1 C3+C4 PASS confirmed by `scripts/version_gate.sh`.
- **Internal test fixture sync.** Six `.llmll` fixtures (`compiler/test/fixtures/modules/` ×4 + `compiler/test/fixtures/pbt-cross-module/imported.llmll`) re-migrated `def-logic` → `def` (reversal of CE-2). Two `ModuleSpec.hs` call sites (M-06, M-08.5) re-flipped to `GrammarCoreInversion`. 20 inline JSON `"schemaVersion"` strings in `Spec.hs` re-bumped to `"0.6.0"`.
- **`examples/withdraw-demo/withdraw.ast.json` `schemaVersion` bumped to `"0.6.0"`.** Required because `applyPatch` in [`compiler/src/LLMLL/PatchApply.hs`](compiler/src/LLMLL/PatchApply.hs) calls `parseJSONASTValue` which gates on `expectedSchemaVersion`; OBLIG-1/OBLIG-2 tests exercise this path. The `"kind":"def-logic"` body in this file is unchanged — `parseJSONASTValue` hardcodes `GrammarLegacy`. This is the only `examples/` file migrated on this pass; remaining 20 `.ast.json` + 17 `.llmll` S-expression files were deferred (see migration-complete bullet below).
- **`examples/**` JSON-AST migration complete (commit `f09c498`, 2026-05-30).** 20 `.ast.json` files bumped `schemaVersion` `0.5.0`/`0.1.3` → `0.6.0`; 145 `def-logic` nodes reclassified to `"kind":"def"` (72, 47.7%) or `"kind":"def-shell"` (73, 52.3%) per LT-INV §6 classifier (`isCoreBodySyntactic` + trusted-callee check, `TypeCheck.hs:338-361`); 6 `letrec` nodes → `"kind":"def-shell"` with `decreases` field removed. `withdraw-demo/withdraw.ast.json` `def-logic` → `def` (schema already `0.6.0`). Boundary-form distribution 47.7% `def` satisfies §8.1 ≥25% gate. All `examples/**` `.ast.json` files now parse under default `GrammarCoreInversion` without `--grammar=legacy`. OBLIG-1/OBLIG-2 confirmed clean (`parseJSONASTValue` accepts `"kind":"def"` under `GrammarLegacy`). **Pending: 17 `.llmll` S-expression files** (separate compiler-engineer pass); four `parseStatements GrammarLegacy` calls in `Spec.hs` (B1, B3, withdraw benchmarks) + three `SDefLogic` golden patterns.
- **Tests: 785 Haskell + 62 Python.** Count as of `f09c498`; no new tests added in this pass. 2-test delta from CE-3 baseline (783→785) is not attributable to this pass — intermediate tests not captured in a prior CHANGELOG entry.
- **`getting-started.md §4.1` JSON example corrected (commit `13eab90`, 2026-05-30).** `"kind":"def-logic"` renamed to `"kind":"def"` in the State Accessor Functions JSON snippet; the legacy form emitted `core-grammar-violation` under default `GrammarCoreInversion`. No test delta. Residuals tracked: (a) param `s: string` is a pre-existing type mismatch against `first :: pair[a,b] → a` (`TypeCheck.hs:93`, U2-lite v0.4; same issue in `examples/hangman_json_verifier/hangman.ast.json:state-word`) — compiler-engineer scope, correct param to `pair-type`; (b) prose note at §4.1 "first/second accept any pair-like value regardless of annotation" deferred pending param fix to avoid note/example inconsistency — doc-lead scope after (a) lands.
- **`getting-started.md §4.1` param-type and `hangman.ast.json` state type corrected (commit `67c1e15`, 2026-05-30).** Closes CE-3 doc-pass residuals (a) and (b) from `13eab90`. (a) `s: string` → `s: pair-type[string,string]` in the §4.1 JSON snippet; `first :: pair[a,b] → a` (`TypeCheck.hs:93`, U2-lite v0.4) now correctly typed at the call site. (b) Prose note "first/second accept any pair-like value regardless of annotation" corrected: "`first :: pair[a,b] → a` and `second :: pair[a,b] → b` require a `pair-type` parameter." Additionally, 11 `unit`-typed state/accessor params in [`examples/hangman_json_verifier/hangman.ast.json`](examples/hangman_json_verifier/hangman.ast.json) corrected to `pair[string,pair[list[string],pair[int,MaxWrong]]]` per `make-state` body shape. No test delta. Remaining findings for next CE pass: `examples/conways_life_json_verifier/life.ast.json` (9 world-state `unit` params) and `examples/tictactoe_json_verifier/tictactoe.ast.json` (6 game-state `unit` params).
- **`life.ast.json` and `tictactoe.ast.json` state/world params corrected (commit `d3deb7d`, 2026-05-30).** Closes the CE-3 `unit`-param residual chain flagged in `67c1e15`. [`examples/conways_life_json_verifier/life.ast.json`](examples/conways_life_json_verifier/life.ast.json): 9 `w`/`world` params corrected to `pair[list[int],pair[int,pair[int,int]]]` per `make-world` body shape. [`examples/tictactoe_json_verifier/tictactoe.ast.json`](examples/tictactoe_json_verifier/tictactoe.ast.json): 6 `s`/`state` params corrected to `pair[list[string],pair[string,string]]` per `make-state` body shape. No test delta. CE-3 `unit`-param residual chain fully closed across all three example files (`hangman`, `life`, `tictactoe`).

### Compiler — F-EL5-3: extend delegation-hole guard to SDef (2026-05-30)

- **`pbtTrustWriteback` now blocks `DLTested` write-back for `def` (strict-core) functions whose body is a `?delegate` or `?delegate-async` hole.** F-GATE-8 (`f62a38b`, 2026-05-29) introduced the `delegateBodies` guard for `def-shell`; F-EL5-3 extends it to `SDef` on the same rationale — delegation holes make return values opaque pre-resolution regardless of enclosing grammar form. [`compiler/src/LLMLL/PBT.hs:693-694`](compiler/src/LLMLL/PBT.hs) gains two new list-comprehension arms (`SDef + EHole(HDelegate _)` and `SDef + EHole(HDelegateAsync _)`) added to `delegateBodies`; the `guardDelegate` helper is unchanged. Pre-fix, a `def` function with an evaluable precondition and a `?delegate` body could be incorrectly promoted to `DLTested n` when a passing `(check ...)` block called it — the static evaluator observed only the `delegateOnFailure` fallback, not the real delegated implementation. Post-fix, `trust_status` reports `asserted` unconditionally for delegation-bounded `def` functions under `llmll verify --trust-report`, consistent with the language-team adjudication in the 2026-05-30 spec-track doc pass. The fix applies to both the OBLIG-PBT-4 explicit-`:subject` path and the singleton-head-position scan.
- **2 new tests** (FG8-7, FG8-8) added under the existing `"F-GATE-8 def-shell hole-delegate PBT trust guard"` describe block in [`compiler/test/Spec.hs`](compiler/test/Spec.hs): FG8-7 asserts `SDef + EHole(HDelegate _)` body suppresses lift; FG8-8 asserts `SDef + EHole(HDelegateAsync _)` body also suppressed. These tests account for the 2-test delta noted in the CE-3 entry (783 → 785). **Tests: 785 Haskell + 62 Python.**
- **Spec closed (this pass):** PBT-Lift inference rule at `LLMLL.md §4.4.5` generalized — `SDefLogic f _ _ c _` premise replaced by `f ∈ contractedNames(Σ ∪ importedExposed(Σ))` covering all contracted statement forms (`SDefLogic`, `SLetrec`, `SDef`, `SDefShell`); `body(f) ∉ { EHole(HDelegate _), EHole(HDelegateAsync _) }` side condition (SC-7) added. Same generalization applied to PBT-Lift-Annotated per-subject premise and conclusion range. Side condition 5 generalized from "`def-logic` posts" to "contracted-callee posts." `LLMLL.md §5.3.5` row 883 and `§6` NOTE box F-EL5-3 "pending" markers closed. No schema delta; no `trust_report_version` bump; no new surface.

### Language team — spec NOTE: hub-import grammar-mode; LT-INV Rev 4; v0.12 direction (2026-05-31)

- **`LLMLL.md §8.2`:** NOTE added documenting grammar-mode inheritance for imported modules. All imports — resolved from local source root, extra roots, or the `llmll-hub` cache — are parsed under the invoking command's `GrammarMode` (default `GrammarCoreInversion` in v0.11+). Hub publishers must ship `schemaVersion 0.6.0` modules using `def`/`def-shell` node kinds. `wasi.*`/`haskell.*`/`c.*` builtin-namespace imports are exempt (they carry no parseable file). Source: [`compiler/src/LLMLL/Module.hs:138,215`](compiler/src/LLMLL/Module.hs) — `loadModule`/`parseFile` thread `GrammarMode` from the entry-point parse, including the hub-cache path at `:99`. Closes the deferred item "checkStatement (SImport imp) guard for hub-import grammar enforcement" from `### Compiler — LT-INV: TypeCheck GrammarMode API collapse (2026-05-30)`: no statement-level grammar guard is needed; `parseFile` enforces the grammar mode before `checkStatement` is called. (Note: `doHubQuery` in `Main.hs` passes `GrammarLegacy` explicitly for the `llmll hub query` signature-search command — that path loads hub files for signature matching, not compilation import, and is unaffected by this NOTE.)
- **`LLMLL.md §8.9`:** One-sentence cross-reference NOTE added pointing hub-import users to §8.2.
- **`docs/archive/shipped-design-specs/core-shell-inversion-proposal.md` → Rev 4:** Def-logic deprecation timeline settled — v0.12 removes `def-logic` entirely (parse error under all grammar modes; no auto-rewrite). The 17 pending `.llmll` S-expression files (engineer scope) are the v0.12 release gate for this removal. v0.11 auto-rewrite-with-warning remains the migration aid through the v0.11 release cycle.
- **`docs/archive/shipped-design-specs/v0.12-direction.md` published (Rev 1):** Sequences three post-freeze clusters — REF-META-2..5 (spec-track, parallel LT proposals, no gate), Bundle B (B0 additive obligation-report effect-summary field in-scope for v0.12 spec+engineer; B1 LT proposal in v0.12, engineer build gated on B0 experiment result), non-int widening (LT proposal after REF-META-3; engineer build gated on `FixpointEmit.hs` path-a axiomatization). No code change.
- **`docs/design/INDEX.md`:** Updated in the language-team pass: LT-INV row → Settled (Rev 4); v0.11 direction memo row amended; v0.12 direction memo row added. No further change in this doc-lead pass.
- **Tests: 788 Haskell + 62 Python** (no change this pass).

### Compiler — LT-INV: TypeCheck GrammarMode API collapse (2026-05-30)

- **All `TypeCheck` entry points take `GrammarMode` as first argument; dual-tier `*WithMode` variants retired.** `typeCheck`, `typeCheckModule`, `typeCheckWithCache`, `typeCheckStrict`, `typeCheckStrictWithCache`, `runTC`, `runTCSketch`, and `runTCStrict` in [`compiler/src/LLMLL/TypeCheck.hs`](compiler/src/LLMLL/TypeCheck.hs) each take `GrammarMode` as first parameter; the mode is threaded into `TCState.tcGrammarMode` at construction, replacing the hardcoded `GrammarLegacy` default. `typeCheckWithCacheMode` becomes the sole shared implementation parameterised by both `GrammarMode` and the strict flag. Consumer call sites updated: [`compiler/app/Main.hs`](compiler/app/Main.hs) (`doCheck`, `doBuild`, `doBuildFromJson`, `doRun`, `replLoop`; `doHubQuery` passes `GrammarLegacy` explicitly per hub pre-migration policy); [`compiler/src/LLMLL/CDP.hs`](compiler/src/LLMLL/CDP.hs); [`compiler/src/LLMLL/Module.hs`](compiler/src/LLMLL/Module.hs); [`compiler/src/LLMLL/Serve.hs`](compiler/src/LLMLL/Serve.hs); [`compiler/src/LLMLL/WeaknessCheck.hs`](compiler/src/LLMLL/WeaknessCheck.hs) (`generateWeaknessCandidates`, `generateCDPCandidates`, and `generateForStmt` each gain `GrammarMode` as first parameter). All `typeCheck`/`runTC`/`runTCSketch` call sites in `Spec.hs` and `ModuleSpec.hs` updated to pass explicit `GrammarCoreInversion`. No user-visible CLI or behavior change; no new diagnostics, flags, or exit codes; no schema delta; `schemaVersion` stays `"0.6.0"`. Deferred: `checkStatement (SImport imp)` guard for hub-import grammar enforcement — open design question; filed as separate follow-on item.
- **No new tests.** Tests: 788 Haskell + 62 Python (unchanged from `8542033`).

### Compiler — parser: JSON-AST def/def-shell guard under --grammar=legacy (2026-05-30)

- **`parseStatement` in `ParserJSON.hs` now rejects `{"kind":"def"}` and `{"kind":"def-shell"}` under `--grammar=legacy` with a `legacy-grammar-violation` diagnostic** (commit `8542033`). Previously both forms were admitted unconditionally regardless of grammar mode, contradicting `LLMLL.md §4.1` ("Under `--grammar=legacy`, `def` and `def-shell` are unavailable") and the `§12` EBNF comment. The text parser (`Parser.hs`) already enforced the symmetric constraint via `GrammarMode` arms in `pStatement`; the JSON-AST parser did not. Defect found by language-team during §4.1 audit post-CE-3. `diagSuggestion` for `legacy-grammar-violation` advises dropping `--grammar=legacy` or reverting to `def-logic`/`letrec` for v0.10-compatible output. `diagCode` is `E011` (same as `core-grammar-violation`).
- **`parseJSONASTValue` signature changed to `GrammarMode -> Value -> Either [Diagnostic] [Statement]`**, resolving the hardcoded-`GrammarLegacy` TODO at former `ParserJSON.hs:86-87`. `GrammarMode` is now threaded through `applyPatch` (`PatchApply.hs`; first parameter), `doPatch` (`Main.hs`; CLI `gm` value propagated from `optGrammarMode`), and `Serve.handlePatch` (`Serve.hs`; hardcoded `GrammarCoreInversion`, consistent with `Serve.hs`'s own parse paths at `Serve.hs:143-150`). Patch-apply against a `--grammar=legacy` host now parses the patched JSON under `GrammarLegacy`, preserving correct behavior for legacy-mode patch-apply.
- **3 new tests:** INV-P15 (JSON-AST `def` rejected under `GrammarLegacy`), INV-P16 (JSON-AST `def-shell` rejected under `GrammarLegacy`), INV-P17 (`parseJSONASTValue GrammarCoreInversion` accepts `def`). Three pre-existing `applyPatch` call sites in `Spec.hs` (OBLIG-1, OBLIG-2, OBLIG-3) updated to pass `GrammarCoreInversion`; OBLIG-3 inline fixture migrated from `"kind":"def-logic"` → `"kind":"def"`. No schema delta; no `.verified.json` invalidation. **Tests: 788 Haskell + 62 Python.**

### Compiler — F-GATE-8: def-shell hole-delegate PBT trust guard

- **`pbtTrustWriteback` now blocks `DLTested` write-back for `def-shell` functions whose body is a `hole-delegate` or `hole-delegate-async` hole.** Pre-fix, a check block whose body evaluated successfully via the delegate's `on_failure` fallback could lift the function's post-clause trust to `tested`, even though the static evaluator never observed the real delegated implementation — only the `delegateOnFailure` path. `processRun` in [`compiler/src/LLMLL/PBT.hs:641–755`](compiler/src/LLMLL/PBT.hs) gains a `guardDelegate` predicate: when the resolved PBT subject is in the `delegateBodies` set (any `SDefShell` with `EHole(HDelegate _)` or `EHole(HDelegateAsync _)` body), the `DLTested` lift is suppressed and an informational diagnostic is emitted. The fix applies to both the OBLIG-PBT-4 explicit-`:subject` path and the singleton-head-position scan. Post-clause trust for delegation-bounded functions now consistently reports `asserted` under `llmll verify --trust-report`, matching the grade-B/A boundary in the experiment harness's `delegation-excluded` gate. Root cause of the pre-fix inconsistency: two runs in `experiments/minimal-agent/runs/20260528T204620Z/` — `try02` (pre `string-length` guard, accidentally correct `asserted`) and `try03` (tautology check block, incorrect `tested`) — differed only in check-block structure, not in function structure.
- **`evalBuiltinApp` in [`compiler/src/LLMLL/Contracts.hs`](compiler/src/LLMLL/Contracts.hs) gains `string-length` and `string-empty?`.** Both were registered in `TypeCheck.hs:109,118` but absent from the static evaluator. `string-length` returns `T.length` of a `LitString` literal as a `LitInt`; `string-empty?` returns `T.null` as a `LitBool`. Non-literal arguments fall through to `Nothing` (constant-folding only). Without the primary `delegateBodies` fix, adding these would have caused check blocks using `string-length` in their conditions to also incorrectly lift; both fixes are required for correctness.
- **6 new tests** (FG8-1–FG8-6) under `"F-GATE-8 def-shell hole-delegate PBT trust guard"` in [`compiler/test/Spec.hs`](compiler/test/Spec.hs): `string-length`/`string-empty?` literal evals; `HDelegate` body blocks lift; non-delegate concrete body permits lift (regression guard); `HDelegateAsync` body also blocked. **Tests: 783 Haskell + 62 Python.**

### Experiments — §8 gate: redesigned run (20260528T204620Z, EL-1+EL-2+E3)

- **Run `20260528T204620Z`** ([`experiments/minimal-agent/findings/postmortem-005-s8-gate-redesigned-run.md`](experiments/minimal-agent/findings/postmortem-005-s8-gate-redesigned-run.md)) used the EL-1+EL-2+E3 evaluator (E3 Option 2, commit `0d5037e`) under `GrammarCoreInversion` enforcement (F-GATE-1 + F-GATE-1b). 8 attempts: claude-opus-4-7 ×5, gemini-3-pro-preview ×3; 2 excluded (gemini-try02: `def-logic` with no in-session correction; gemini-try03: TerminalQuotaError). Valid dataset: n=6.
- **Axis (c) improves: `?proof-required` emission 0/6 → 3/6 (50%)** — gate pass criterion met. Three grade-A paths exercised: (1) `def` + bare `?proof-required` → `"asserted"`; (2) `def-shell` + arithmetic `string-length` pre → `"asserted"`; (3) `def-shell` + predicate-carrying LT-PPR form → `"asserted"`. First empirical exercise of the predicate-carrying form in a live agent run. Grade distribution: 3× A, 3× C; grade B absent (E3 Option 2 makes `login-handler.post` a required contract — absent `?proof-required` → grade C, not B). Axis (d): `def-logic` in final solutions 0/10 (0%); `def`/`def-shell` 10/10. Axes (a)(b): no change from baseline.
- **Run contaminated — gate pass conditional.** F-GATE-7 (`normalize_trust_status` did not strip `"tested (100 samples)"` suffix; 3/5 claude attempts mislabelled grade C; fix applied to `evaluate_run.py` post-run). F-GATE-8 (`def-shell` + `hole-delegate` body post trust-status pre-clause-dependent; compiler fix `f62a38b`, 2026-05-29). PM-005 is not a clean reference run; sample composition post-fix would differ.
- **§8 gate adjudication (language-team, 2026-05-29):** axis (c) criterion met; run contaminated by F-GATE-7 and F-GATE-8 post-hoc fixes; gate pass conditional. Rollback path (1) adopted per [`docs/archive/shipped-design-specs/v0.11-cross-proposal-rollback-discipline.md §2.2`](docs/archive/shipped-design-specs/v0.11-cross-proposal-rollback-discipline.md): `--grammar=core-inversion` remains the explicit opt-in; grammar default and schema bump deferred; redesigned gate experiment scheduled post-F-GATE-8 fix. **Tests: 783 Haskell + 62 Python** (from F-GATE-8 entry; no count change this pass).
- **Gate adjudication definitive (2026-05-29):** F-GATE-8 fix (commit `f62a38b`, `### Compiler — F-GATE-8` above) removes the contamination source. Rollback path (1) is no longer conditional — it is the definitive §8 gate outcome. Redesigned gate experiment is unblocked; scheduling is experiment-lead scope.

### LT-INV — §8 rollback: grammar default deferred; schema stays at 0.5.0 (2026-05-29)

- **Grammar default reverts to `GrammarLegacy`.** Commit `5cab1b7` flipped `GrammarCoreInversion` to the CLI default (2026-05-28). Rolled back: grammar default returns to `GrammarLegacy`. `--grammar=core-inversion` is the explicit opt-in for `def`/`def-shell`. **Compiler-engineer action required:** revert `compiler/app/Main.hs` grammar default; revert `compiler/test/fixtures/` `def` → `def-logic` fixture migrations (commit `5cab1b7`); revert `compiler/test/Spec.hs` `GrammarCoreInversion` test-mode changes and inline version-string changes.
- **`docs/llmll-ast.schema.json` reverted to 0.5.0.** `$id` `v0.6/ast.schema.json` → `v0.5/ast.schema.json`; `title` `v0.6` → `v0.5`; `schemaVersion.const` `"0.6.0"` → `"0.5.0"`. `kind:"def"` / `kind:"def-shell"` JSON-AST nodes remain admitted by the `Statement.kind` enum for opt-in consumers under `--grammar=core-inversion`; they are not canon at `0.5.0` and not required. Bump to `0.6.0` deferred. **Compiler-engineer action required (DRIFT-CI-1 C3 blocker):** revert `compiler/src/LLMLL/ParserJSON.hs:41` `expectedSchemaVersion` `"0.6.0"` → `"0.5.0"`; revert `examples/**` `schemaVersion` and `kind` migrations (commit `afe80df`); revert `compiler/test/Spec.hs` 20 inline `"0.6.0"` strings.
- **`examples/*` migration not applied.** Per `v0.11-cross-proposal-rollback-discipline.md §2.2`: example migration applies only under Outcome 0. The migration committed at `afe80df` is rolled back under compiler-engineer scope above.
- **`kind:"def"` / `kind:"def-shell"` additions remain in the grammar** behind `--grammar=core-inversion`. Not finalized as canonical. Redesigned gate experiment will determine Outcome 0 / 1 / 2 definitively.
- **Doc surface reverted (this pass):** `docs/llmll-ast.schema.json`, `LLMLL.md §5/§12`, `docs/getting-started.md §4.14`, `README.md` version callout. Roadmap LT-INV summary updated; grammar-default-flip and schema-bump Unreleased entries annotated below.

### Experiments — E3 Option 2: experiment 001 grade-A gate and axes (b)/(c)

- **`CONTRACT_EXPECTATIONS[1]["login-handler"]` restructured** in [`experiments/minimal-agent/scripts/evaluate_run.py`](experiments/minimal-agent/scripts/evaluate_run.py): the `pre` expectation (`proof_required: False`) is removed; a `post` expectation (`proof_required: True`) is added. The pre clause on `login-handler` is QF-LIA-tractable but structurally asserted (the function contains `?delegate`); keeping it with `proof_required: False` caused `asserted_without_proof = 1` on every solution, imposing a B ceiling that no contract configuration could lift. Removes the latent grade-B floor from the contract-assessment path. See [`experiments/minimal-agent/findings/postmortem-001-el-a-revalidation.md`](experiments/minimal-agent/findings/postmortem-001-el-a-revalidation.md) F-201 for the prior E3-revert history.
- **`REQUIRED_FEATURES[1]` gains `"post"`**: solutions that omit the post clause on `login-handler` receive F on the feature scan, not merely a contract-quality penalty. Grade gradient: missing post → F; post present but no `?proof-required` marker → C (`all_required_contracts_met: false`); post with `?proof-required`, all tests delegation-excluded → B; post with `?proof-required` and at least one non-delegation-dependent check → A.
- **[`experiments/minimal-agent/experiments/001-two-agent-auth.md`](experiments/minimal-agent/experiments/001-two-agent-auth.md)** gains two new items: item 6 — a `post` contract on `login-handler` asserting the returned hash is non-empty, marked `?proof-required` (delegation-bounded postcondition per `LLMLL.md §13.8`); item 7 — a non-delegation-dependent `check` block asserting a pure property of the pre-condition predicate without invoking `login-handler` or `validate-session`. Item 7 is necessary to clear the `effective_total == 0` test-exclusion B gate, which fires independently of contract quality.
- **3 new Python tests** in [`experiments/minimal-agent/scripts/test_evaluate_run.py`](experiments/minimal-agent/scripts/test_evaluate_run.py): `ContractExpectationE3Tests` restructured (pre-absent guard, post-proof-required guard, post-in-REQUIRED_FEATURES guard); `QualityGradeTests.test_e001_grade_a_with_nondelegation_check_and_proof_required_post` added. **Tests: 770 Haskell + 62 Python** (resolves the acknowledged EL-A count discrepancy; canonical suite is now 41 `test_evaluate_run.py` + 21 `scripts/tests/`).

### Compiler — LT-INV grammar default flip (§8 gate: PASS)

- **`GrammarCoreInversion` is now the default grammar mode** (commit `5cab1b7`, 2026-05-28). All `llmll` subcommands (`check`, `verify`, `test`, `build`, `holes`, `typecheck`, and the HTTP serve endpoint) parse under `--grammar=core-inversion` by default. Programs using `def-logic` or `letrec` must pass `--grammar=legacy` explicitly; the flag is available on all subcommands. `llmll --help` reports "core-inversion (default) or legacy (v0.10 compatibility)".
- **`GrammarMode` threaded through the module-import loader.** `Module.hs::loadModule`, `loadFromFile`, `loadOneImport`, and `parseFile` accept and propagate the active grammar mode; imported `.llmll` modules are parsed with the same grammar as the entry file. Previously all imports were hardcoded to `GrammarLegacy`. `HubQuery.hs` retains `GrammarLegacy` explicitly (hub packages are pre-migration). The HTTP serve endpoint (`Serve.hs`) follows the CLI default.
- **Test fixture migration.** Six `.llmll` fixtures (`compiler/test/fixtures/modules/` ×4 + `compiler/test/fixtures/pbt-cross-module/` ×2) migrated from `def-logic` to `def`.
- **§8 empirical-validation gate:** PASS. Combined postmortem-004/005 data (2026-05-28): axis (a) grade A achieved for first time (2/5 claude-opus-4-7 primary-arm attempts); axis (c) `?proof-required` emission non-zero for first time (2/5 `proof_required_ceiling_accepted`); axis (d) 0 `def-logic` in all primary-arm final solutions. Gate adjudicated by language-team, 2026-05-28. See [`experiments/minimal-agent/findings/postmortem-005-s8-gate-redesigned-run.md`](experiments/minimal-agent/findings/postmortem-005-s8-gate-redesigned-run.md).
- **Pending (next pass):** `examples/*` migration from `def-logic` → `def`/`def-shell` (compiler-engineer scope); schema bump `0.5.0 → 0.6.0` (blocked on `expectedSchemaVersion` update in `compiler/src/LLMLL/ParserJSON.hs:41`).
- **+3 Haskell tests** (INV-DEFAULT-1, INV-DEFAULT-2, INV-MODULE-THREAD-1). **Tests: 773 Haskell + 62 Python.**
- **Rolled back 2026-05-29.** Redesigned gate run `20260528T204620Z` (PM-005) was contaminated by F-GATE-7 (evaluator suffix mismatch) and F-GATE-8 (compiler trust-status bug; fix `f62a38b`); language-team adjudicated rollback path (1) per [`v0.11-cross-proposal-rollback-discipline.md §2.2`](docs/archive/shipped-design-specs/v0.11-cross-proposal-rollback-discipline.md). Grammar default reverts to `GrammarLegacy`; schema stays `0.5.0`. See `### LT-INV — §8 rollback` above.

### Experiments — §8 gate: post-arm checkpoint (20260528T145727Z)

- **Gate run IDs:** pre-arm `20260528T012230Z` (GrammarLegacy, 6 attempts); post-arm checkpoint `20260528T145727Z` (GrammarCoreInversion, 5 valid attempts; `20260528T014158Z` excluded — F-GATE-1 enforcement absent). See [`experiments/minimal-agent/findings/postmortem-004-s8-gate-post-arm-rerun.md`](experiments/minimal-agent/findings/postmortem-004-s8-gate-post-arm-rerun.md).
- **Axis (d): complete shift.** `def-logic` in final solutions: pre-arm 12/12 (100%) → post-arm 0/10 (0%). `def`/`def-shell` statements: 0/12 → 10/10. Claude-only pass rate 3/3 both arms; gemini compromised by API HTTP 429 throttling (try01 excluded, 0 output; try03 grade F, 20 retries, 429-degraded — excluded from grade analysis).
- **Axes (a), (b), (c): flat.** Overall harness pass rate: claude-only 3/3 pre and post. Verified fraction: 0/6 → 0/5. `?proof-required` emission: 0/6 → 0/5.
- **E3 instrument limitation.** Axis (c) flatness is not a clean null result. The pre-E3 evaluator held `CONTRACT_EXPECTATIONS[1]["login-handler"]` with `proof_required: False` on the pre clause, imposing a structural B ceiling on every solution regardless of `?proof-required` authoring — agents had no harness-backed incentive to emit the marker. Axes (b) and (c) were not meaningfully measurable; flatness on these axes does not constitute evidence against the polarity claim. See F-201 in [`experiments/minimal-agent/findings/postmortem-001-el-a-revalidation.md`](experiments/minimal-agent/findings/postmortem-001-el-a-revalidation.md) and `### Experiments — E3 Option 2` above for the E3 defect and fix.
- **Rollback path (1) adopted; polarity claim deferred.** Language-team / experiment-lead adjudication at `20260528T145727Z`: gate pass/fail undecidable given E3 instrument defect. Rollback path (1) — inversion retained behind `--grammar=core-inversion` flag, grammar default not flipped — adopted pending E3 fix and re-run. Polarity claim deferred. E3 Option 2 fix (commit `0d5037e`) corrected `CONTRACT_EXPECTATIONS` and added item 7 (non-delegation-dependent check); follow-up run `20260528T204620Z` (postmortem-005) shifted axis (c) from 0/6 to 3/6; gate declared PASS; polarity claim reinstated; grammar default flipped at `5cab1b7` (see `### Compiler — LT-INV grammar default flip` above).

### Compiler — LT-INV schema bump 0.5.0 → 0.6.0 + examples migration

- **`expectedSchemaVersion` bumped to `"0.6.0"`** in [`compiler/src/LLMLL/ParserJSON.hs:41`](compiler/src/LLMLL/ParserJSON.hs) (commit `afe80df`, 2026-05-28). Files with `"schemaVersion": "0.5.0"` are rejected with a `schema-version-mismatch` diagnostic (exit 1). All submitted `.ast.json` files must carry `"schemaVersion": "0.6.0"`. Closes the schema-bump gate gated on the §8 empirical-validation gate pass.
- **`docs/llmll-ast.schema.json` bumped:** `$id` URL `v0.5 → v0.6`, `title` updated, `schemaVersion.const` updated, `schemaVersion.description` updated. DRIFT-CI-1 C3 confirms `schema.const == ParserJSON.expectedSchemaVersion`. No new fields, no deprecated fields, no node-shape change.
- **`examples/**` migration:** 17 `.llmll` files (`def-logic` → `def-shell`); 21 `.ast.json` files (`"kind":"def-logic"` → `"kind":"def-shell"`, `schemaVersion` `"0.5.0"` → `"0.6.0"`; legacy `"0.1.3"` → `"0.6.0"` in `tictactoe_json`, `hangman_json`); 3 `.ast.json` files with `"kind":"letrec"` migrated to `"kind":"def-shell"` with `"decreases"` field removed (`hangman_json_verifier` ×2, `conways_life_json_verifier` ×3, `tictactoe_json_verifier` ×1). Conservative first-pass migration: all `def-logic` → `def-shell` (semantically equivalent to `def-logic` under v0.10 semantics); selective `def` upgrade (functions whose bodies satisfy `isCoreBodySyntactic`) is a future pass.
- **Zero test count delta.** 20 inline `"0.5.0"` strings in `Spec.hs` updated to `"0.6.0"`; 4 example-reading tests updated from `GrammarLegacy` to `GrammarCoreInversion`; 3 `SDefLogic` pattern matches updated to `SDefShell` in benchmark golden tests. **Tests: 773 Haskell + 62 Python.**
- **Rolled back 2026-05-29.** `docs/llmll-ast.schema.json` reverted to `0.5.0` in this doc pass. Compiler-engineer must revert `expectedSchemaVersion` in `ParserJSON.hs:41` and `examples/**` migration as a companion PR; DRIFT-CI-1 C3 is blocked until both are done. See `### LT-INV — §8 rollback` above.

### Compiler — LT-CDP: CDPScopeCoreOnly flip + WarnSpecTooTightForOmega rename (§8 Outcome 0)

- **`CDPScopeAllDefLogic` → `CDPScopeCoreOnly` in [`compiler/app/Main.hs:1339`](compiler/app/Main.hs) (commit `3af3c06`, 2026-05-29).** Per [`v0.11-cross-proposal-rollback-discipline.md §2.1`](docs/archive/shipped-design-specs/v0.11-cross-proposal-rollback-discipline.md) Outcome 0 (§8 gate PASSED 2026-05-28), `--cdp` now measures `discriminative_axis` for `def`-form (`SDef`) functions only. `def-shell` and legacy `def-logic` functions receive `WarnDefShellOutOfScope` entries with `"score": null` and `"warnings": ["def-shell-out-of-scope"]`; the result map remains uniform (every contracted function has an entry).
- **`computeCDPFor` scope filtering wired in [`compiler/src/LLMLL/CDP.hs:207-271`](compiler/src/LLMLL/CDP.hs).** The `_scope` parameter was previously accepted but ignored. Under `CDPScopeCoreOnly`, only `SDef` enters the measurement pipeline; `SDefShell`, `SDefLogic`, and `SLetrec` are routed to `outOfScopeResult` (no solver call). `CDPScopeAllDefLogic` retains all-forms measurement for `--grammar=legacy` contexts.
- **`WarnVacuousOverOmega` → `WarnSpecTooTightForOmega`; wire-line label `"vacuous-over-omega"` → `"spec-too-tight-for-omega"` (F-005 CE follow-up, [`docs/archive/shipped-design-specs/contract-discriminative-power-proposal.md §5 Rev 4`](docs/archive/shipped-design-specs/contract-discriminative-power-proposal.md)).** Fires when a body-faithful-verified contract admits no §4.3.1 trivial-body candidate — the spec is tight with respect to the candidate set, not semantically inconsistent. `"spec-inconsistent"` is retained for the distinct case where no verification evidence exists.
- **+4 Haskell tests** (CDP-SCOPE-1–4) in [`compiler/test/Spec.hs`](compiler/test/Spec.hs) under `"CDP-SCOPE: CDPScopeCoreOnly scope filtering"`: `SDef` in-scope (score populated); `SDefLogic` and `SDefShell` out-of-scope (`WarnDefShellOutOfScope`); `CDPScopeAllDefLogic` + `SDefLogic` legacy path (score populated). **Tests: 777 Haskell + 62 Python.**

### Compiler — LT-INV (v0.11): core/shell grammar inversion

- **`--grammar=core-inversion` global flag activates the core/shell grammar split** across all `llmll` subcommands. Under this mode, `def` declares a strict-core function (`SDef`) and `def-shell` declares a permissive function (`SDefShell`). Default is `--grammar=legacy`; all existing programs are unaffected. The flag is threaded through `parseSrc` / `loadStatements` / `loadStatementsMulti` in [`compiler/app/Main.hs`](compiler/app/Main.hs) and forwarded to the REPL loop; library-internal callers (`HubQuery`, `Module`, `Serve`) unconditionally use `GrammarLegacy`. `GrammarMode` is the discriminant in [`compiler/src/LLMLL/Syntax.hs`](compiler/src/LLMLL/Syntax.hs); parser entry-points in [`compiler/src/LLMLL/Parser.hs`](compiler/src/LLMLL/Parser.hs) and [`compiler/src/LLMLL/ParserJSON.hs`](compiler/src/LLMLL/ParserJSON.hs) dispatch on `GrammarCoreInversion` to activate `pDef` / `pDefShell`; `{"kind":"def-logic"}` in JSON-AST is rejected with a `core-grammar-violation` diagnostic under this mode (F-GATE-1, commit `cabb1fd`).
- **`def` (SDef) admits a restricted core-body whitelist** enforced by `isCoreBodySyntactic` in [`compiler/src/LLMLL/Parser.hs`](compiler/src/LLMLL/Parser.hs): `ELit`, `EVar` (int-typed), QF-LIA `EOp` (linear ops only — `*` and `/` are excluded), `ELet` (PVar + int RHS), `EIf`, `EApp` to admitted callees, `EMatch` on `Result` 2-arm, and `?hole`/`?name`/`?choose`/`?request-cap`/`?scaffold`/`?delegate`/`?delegate-async`. Excluded: `ELambda`, `EDo`, `EPair`, non-linear arithmetic, `?proof-required`. The type-checker enforces the transitive callee restriction at every `EApp` inside an `SDef` body via `checkCalleeAdmissibility` in [`compiler/src/LLMLL/TypeCheck.hs`](compiler/src/LLMLL/TypeCheck.hs): a callee is admitted if it has body-faithful verified evidence, is in the `trustedPrelude` set (11 pure stdlib functions), or is a member of `builtinEnv` (all built-in LLMLL operators, including those used in contract clause expressions such as `>=`, `+`, `and`). The third condition — `builtinEnv` admission — is formalized in [`docs/archive/shipped-design-specs/core-shell-inversion-proposal.md`](docs/archive/shipped-design-specs/core-shell-inversion-proposal.md) §4 Rev 3 (language-team, 2026-05-27) and promoted to `LLMLL.md §5.3.5`.
- **`def-shell` (SDefShell) is the permissive form**: no body whitelist, no callee admission check. Functions declared with `def-shell` may freely call unverified callees, use `ELambda`, `EDo`, etc. The type-checker does not emit `core-grammar-violation` or `core-membership-violation` inside `SDefShell` bodies.
- **Two new diagnostic kinds** in [`compiler/src/LLMLL/Diagnostic.hs`](compiler/src/LLMLL/Diagnostic.hs): `core-grammar-violation` (body contains a disallowed construct) and `core-membership-violation` (callee not body-faithful, not in `trustedPrelude`, not a builtin). Both are errors (not warnings) when emitted inside an `SDef` body.
- **Full compiler fan-out:** `SDef`/`SDefShell` arms added to all 15 modules with pattern-exhaustive matches: `Module.hs`, `CodegenHs.hs`, `AstEmit.hs`, `TrustReport.hs`, `FixpointEmit.hs`, `ObligationAssembly.hs`, `ObligationMining.hs`, `WeaknessCheck.hs`, `Contracts.hs`, `SpecCoverage.hs`, `CDP.hs`, `PBT.hs`, `HubQuery.hs`, `PatchApply.hs`, `HoleAnalysis.hs`. `extractContract` and `runLeanstralPipeline` in `Main.hs` extended with `SDef`/`SDefShell` cases (two missed fan-out sites found during build). Library callers `HubQuery.hs`, `Module.hs`, `Serve.hs` updated to pass `GrammarLegacy` to parser entry-points.
- **No schema bump on this pass.** `schemaVersion` stays `0.5.0`. `SDef`/`SDefShell` dispatch rides `"kind": "def"` / `"kind": "def-shell"` JSON keys via `ParserJSON.hs` dispatchers without new required-field declarations. Schema bump `0.5.0 → 0.6.0` and default-flip from `GrammarLegacy` to `GrammarCoreInversion` are gated on the §8 empirical-validation gate (per [`docs/compiler-team-roadmap.md`](docs/compiler-team-roadmap.md) §8.4 step 4).
- **28 new LT-INV regression tests** (`INV-P1`–`INV-P8`, `INV-W1`–`INV-W7`, `INV-A1`–`INV-A5`, `INV-C1`–`INV-C5`, `INV-G1`–`INV-G3`) in [`compiler/test/Spec.hs`](compiler/test/Spec.hs) under a new `LT-INV (v0.11): core/shell grammar inversion` `describe` block.
- **F-GATE-1 (`parseJSONAST` grammar enforcement, commit [`cabb1fd`](compiler/src/LLMLL/ParserJSON.hs)): `{"kind":"def-logic"}` in `.ast.json` input is now rejected under `--grammar=core-inversion`** with a `core-grammar-violation` diagnostic (exit 1). Pre-fix, `parseJSONAST` ignored `GrammarMode` entirely — agents could submit `def-logic` solutions under `--grammar=core-inversion` and receive exit 0, making the §8 empirical-validation gate produce null data across all four axes (confirmed by Postmortem 003, `experiments/minimal-agent/findings/postmortem-003-s8-gate-pre-post.md`). Fix: `parseJSONAST` gains a `GrammarMode` parameter threaded to `parseProgram` / `parseStatement`; the `"def-logic"` dispatch branch fails with a `core-grammar-violation` sentinel under `GrammarCoreInversion`. `parseJSONASTValue` (used by `PatchApply`) retains its current signature and routes internally to `GrammarLegacy` (patch callers have no grammar-mode context). **3 new tests** INV-P9/P10/P11 in [`compiler/test/Spec.hs`](compiler/test/Spec.hs): INV-P9 — JSON-AST `def-logic` rejected under `GrammarCoreInversion`; INV-P10 — JSON-AST `def` accepted under `GrammarCoreInversion`; INV-P11 — JSON-AST `def-logic` still accepted under `GrammarLegacy` (backwards-compatibility regression guard).
- **F-GATE-1b (`letrec` enforcement + S-expression symmetry):** `{"kind":"letrec"}` in `.ast.json` input is now rejected under `--grammar=core-inversion`** with a `core-grammar-violation` diagnostic (exit 1), symmetric with `{"kind":"def-logic"}` (F-GATE-1). Companion fix: `pDefLogic` and `pLetrec` moved from the unconditional tail of `pStatement`'s `choice` list into the `GrammarLegacy` arm — `GrammarCoreInversion` arm: `[pDef, pDefShell]`; `GrammarLegacy` arm: `[pDefLogic, pLetrec]` — closing the S-expression-path asymmetry noted in F-GATE-1. `diagSuggestion` on `core-grammar-violation` updated to name both `def-logic` and `letrec` as rejected kinds. INV-P6 assertion inverted from "parses as SDefLogic" to "fails to parse" (the assertion was documenting the unintended behaviour; it now documents correct rejection). **3 new tests** INV-P12/P13/P14 in [`compiler/test/Spec.hs`](compiler/test/Spec.hs): INV-P12 — S-expression `(letrec ...)` fails to parse under `GrammarCoreInversion`; INV-P13 — JSON-AST `{"kind":"letrec"}` rejected with `core-grammar-violation`; INV-P14 — JSON-AST `{"kind":"letrec"}` accepted under `GrammarLegacy`. **Spec alignment note:** `LLMLL.md §4.1` and `getting-started.md §4.14` already stated that `letrec` is rejected under `--grammar=core-inversion`; this fix brings the compiler into alignment with the existing spec text.
- **Tests: 770 Haskell + 58 Python** (F-GATE-1b +3 INV-P12–P14; F-GATE-1 +3 INV-P9–P11; LT-INV +28; 4 additional tests from F-005 `WarnVacuousOverOmega` fix, commit `0b5b249`, account for the gap between the F-006/F-005 entry count of 712 and the 716 pre-LT-INV baseline).

### Compiler — LT-INT (v0.11): `int → Integer` codegen switch

- **LLMLL `int` lowers to Haskell `Integer` (unbounded mathematical-integer semantics)** at codegen, closing the documented `Int64` overflow gap on file since v0.8.1a per [`LLMLL.md §5.3.5`](LLMLL.md). Three primary codegen sites flip per [`docs/archive/shipped-design-specs/int-2-boundary-shims.md`](docs/archive/shipped-design-specs/int-2-boundary-shims.md) §8: [`compiler/src/LLMLL/CodegenHs.hs:441`](compiler/src/LLMLL/CodegenHs.hs#L441) `mapLlmllPrimType "int"`, [`:706`](compiler/src/LLMLL/CodegenHs.hs#L706) `emitLit (LitInt n)` ascription, [`:723`](compiler/src/LLMLL/CodegenHs.hs#L723) `toHsType TInt`. The verifier already reasoned over unbounded mathematical integers at [`compiler/src/LLMLL/FixpointEmit.hs:188-194`](compiler/src/LLMLL/FixpointEmit.hs#L188-L194); INT-2 aligns the Haskell-runtime side with the verifier-side semantics. INT-PRE cleared the regression at 1.015× TOTP test-phase against the 5× gate threshold (commit `8cac520`, [`experiments/int-pre/findings/postmortem-001.md`](experiments/int-pre/findings/postmortem-001.md)). Closes LT-INT / INT-2 row at [`docs/compiler-team-roadmap.md:170`](docs/compiler-team-roadmap.md).
- **Class B preamble entries lifted to `Integer`** per catalog §3.2: `llmll_abs`, `llmll_min`, `llmll_max` (polymorphic `abs`/`min`/`max` instantiated at `Integer`), `int_to_string` (`show` polymorphic), `string_to_int` (reads-target retyped `ReadS Integer`; closes a silent-truncation hazard for inputs exceeding `maxBound :: Int`), `range :: Integer -> Integer -> [Integer]`.
- **Class A indexing primitives keep concrete `Int` Haskell signatures** per catalog §3.1 rows 1–6 (`list_length`, `list_nth`, `string_length`, `string_slice`, `string_char_at`); codegen wraps `int`-typed arguments in `fromIntegral` at the LLMLL-to-Haskell call seam via new `emitApp` clauses at [`compiler/src/LLMLL/CodegenHs.hs:595-603`](compiler/src/LLMLL/CodegenHs.hs#L595-L603). `Int`-returning primitives (`list_length`, `string_length`) lift back to `Integer` at the call site. `wasi_http_response` refactored to `Integral i => i -> String -> IO ()` with `{-# SPECIALIZE :: Integer #-}` pragma (catalog §3.1 row 7, polymorphic sub-pattern).
- **INT-1 overflow-taint trigger dormant on `int`** per catalog §4. The body-VC emitter call to `addOverflowTainted` at [`compiler/src/LLMLL/FixpointEmit.hs:516`](compiler/src/LLMLL/FixpointEmit.hs#L516) is commented out under LT-INT; the walker `bodyHasOverflowArith` and the `erOverflowTainted` record field remain defined across the trust-report / sidecar / obligation surface (constructor, propagation rule, strict-core refusal preserved per catalog §4 "machinery preserved"). INT-3 (`machine-int`) re-arms the trigger by re-enabling the call with a type-aware predicate.
- **`examples/banking_ledger/banking.llmll` now passes `--strict-verified-core`.** `safe-subtract`'s `(- balance amount)` body — overflow-tainted in v0.10.8 — is no longer refused under the dormant trigger. Sidecar regenerated at [`examples/banking_ledger/banking.llmll.verified.json`](examples/banking_ledger/banking.llmll.verified.json) without the `overflow_tainted: true` tag.
- **8 new LT-INT regression tests** (L1–L8) in [`compiler/test/Spec.hs`](compiler/test/Spec.hs) cover the three primary sites, composite-type lowering, Class A shim assertions for `list-length` / `list-nth` / `string-slice`, and a preamble structure check. T10 (INT-1 end-to-end) repurposed as the dormant-trigger regression: a `(+ x 1)` body must NOT taint post-INT-2 while remaining body-faithful. Three Async codegen tests updated to reflect `TInt → Integer` lowering inside `TPromise`.
- **No language-surface change.** No new keywords, builtins, syntax constructs, or SMT theory. **No schema bump:** `schemaVersion` stays `0.5.0`; `trust_report_version` stays `1.1.0`. **No JSON-AST migration.** Pre-v0.11 `.verified.json` sidecars on `int`-only verified evidence load cleanly; sidecars previously carrying `overflow_tainted: true` are regenerated to drop the tag on next verify.
- **Spec drifts flagged (catalog Rev 4 candidates, routed to language-team):** (i) [`docs/archive/shipped-design-specs/int-2-boundary-shims.md`](docs/archive/shipped-design-specs/int-2-boundary-shims.md) §8 says "no `FixpointEmit.hs` changes" but §4 requires the trigger to be empty on `int`; engineer resolved by disarming at the emitter call site rather than the walker. (ii) The §3.4 `range`/`range_idx` split is intentionally not realized — corpus audit (`examples/{life,hangman,tictactoe}_sexp/*.llmll`) shows all `range` uses are `(range 0 N)` index-iteration patterns handled correctly by Class A `fromIntegral` shims; per-element conversion cost is within the INT-PRE budget. Engineer-shipped on branch `lt-int/integer-codegen-switch`, commit `9c37a5c4fd0bec7fe1076813c69085d2fbee4077`. **Tests:** 680 Haskell + 58 Python tests (LT-INT adds 8 Haskell tests; Python suite unchanged from the DRIFT-CI-1 entry below).

### Compiler — LT-CDP (v0.11): contract discriminative power evidence axis

- **`llmll verify --cdp` computes contract discriminative power per function** alongside the existing diamond-lattice evidence axis. The new metric extends [`compiler/src/LLMLL/WeaknessCheck.hs`](compiler/src/LLMLL/WeaknessCheck.hs)'s trivial-body enumeration from a binary "any trivial body passes?" check (legacy `--weakness-check`) to a Shannon-normalized counted-divergence score `DP_Ω(S) = 1 − log|⟦S⟧_Ω| / log|B_{T,U,Ω}|` over the closed v0.11 candidate set at [`docs/archive/shipped-design-specs/contract-discriminative-power-proposal.md`](docs/archive/shipped-design-specs/contract-discriminative-power-proposal.md) §4.3.1 (identity over each param + small ints `{0, 1, -1, 42}` + both bools + `{"", "a"}` + list-empty / list-singleton + `Success`-default / `Error "default"` + pair-of-defaults). Implements [LT-CDP](docs/compiler-team-roadmap.md) v0.11 Implementation Item 2.
- **New module [`compiler/src/LLMLL/CDP.hs`](compiler/src/LLMLL/CDP.hs)** owns score computation, observational-equivalence partition (naive O(N²) per proposal Risk #5; v0.12+ adopts Union-Find), and the typed-warning enumeration of proposal §5 — `identity-satisfies-post`, `const-satisfies-post`, `spec-inconsistent`, `enumeration-too-narrow`, `def-shell-out-of-scope`, `candidates-empty-under-limit`, `over-annotation-warning`, `not-requested`. The seven warnings distinguish *non-applicability* (`def-shell-out-of-scope`, `not-requested`) from *measurement weakness* (`enumeration-too-narrow`, `candidates-empty-under-limit`); downstream consumers must respect the distinction.
- **`CDPScope` is gate-conditional** per [`docs/archive/shipped-design-specs/v0.11-cross-proposal-rollback-discipline.md`](docs/archive/shipped-design-specs/v0.11-cross-proposal-rollback-discipline.md) §2 — defaults to `CDPScopeAllDefLogic` (Outcome 2 semantics) until LT-INV ships and the §8 empirical gate selects the post-gate default. The CDP implementation does not need re-shipping when the gate runs; only the scope-parameter default flips.
- **New `(spec-entropy :strict | :intentional | :unknown)` contract-level annotation** on `def-logic` / `letrec`, parsed in both S-expression ([`compiler/src/LLMLL/Parser.hs`](compiler/src/LLMLL/Parser.hs) `pSpecEntropyClause`) and JSON-AST ([`compiler/src/LLMLL/ParserJSON.hs`](compiler/src/LLMLL/ParserJSON.hs) `parseSpecEntropyField`) frontends. Strict — unknown labels are a parse error, not a silent default. Absent annotation defaults to `Nothing` on the `Contract` record (treated as `:strict` at consumption sites); `Just _` is explicit author intent. `:intentional` suppresses the low-DP diagnostic per proposal §3 / Risk #3 (self-attestation discipline; LH `{-@ assume @-}` precedent).
- **`trust_report_version` bumped `1.1.0 → 1.2.0` (additive)** at [`compiler/src/LLMLL/TrustReport.hs`](compiler/src/LLMLL/TrustReport.hs). New per-entry `discriminative_axis` JSON block per proposal §5 carrying `score`, `basis`, `candidate_count`, `satisfying_candidate_count`, `distinct_observed_behavior_count`, `distinguishing_inputs`, `spec_entropy_annotation`, `warnings`. Without `--cdp`, the block populates with `score: null`, `basis: "not-measured"`, and `warnings: ["not-requested"]` so consumers see a uniform shape and do not need to special-case absence. [`docs/llmll-trust-report.schema.json`](docs/llmll-trust-report.schema.json) `$id` URL `v1.1 → v1.2`, new `$defs/DiscriminativeAxis` with strict warning enumeration. Existing `tier_profile`, `tier_profile_pre/post`, `joint_pbt_witnesses`, `overflow_tainted_fns` unchanged.
- **Module-level `over-annotation-warning` diagnostic** fires when the ratio of `(spec-entropy :intentional)` to total contracted functions exceeds the threshold (default 30%, per proposal §10 Risk #3). Informational, not blocking; threshold is fixed in v0.11 (env-var configurability deferred).
- **Score is observational over Ω.** This distinction carries the claim (proposal §1 Rev 2): `DP_Ω(S) = 0.82` means "82% of *observed* candidate behaviors over the chosen observation set `Ω` are ruled out," **not** "82% of wrong implementations are ruled out" in any semantic sense. Cross-function and cross-version score comparison requires same-`Ω` discipline; the `basis` field makes `Ω`'s identity auditable. Consumers setting CI gates on CDP scores must respect this distinction or risk gating on the wrong reading.
- **Catalog widening — legacy `--weakness-check` unchanged.** `WeaknessCheck.hs` factors into two entry points: `generateWeaknessCandidates` preserves the v0.10 5-enumerator catalog (`TrivConstZero` subsumed into `TrivConstInt 0`, `TrivConstEmptyStr` into `TrivConstString ""`, `TrivConstTrue` into `TrivConstBool True`); `generateCDPCandidates` ships the §4.3.1 closed enumeration. Legacy `--weakness-check` diagnostic surface is unchanged — no new spec-weakness flags fire on existing programs.
- **Schema notes.** **No JSON-AST `schemaVersion` bump** — stays `0.5.0`. Per [`v0.11-cross-proposal-rollback-discipline.md`](docs/archive/shipped-design-specs/v0.11-cross-proposal-rollback-discipline.md) §2, the `(spec-entropy …)` annotation rides the LT-INV bundle (Outcomes 0/1 — `0.5.0 → 0.6.0`) or coordinates with LT-PPR (Outcome 2 — independent `0.5.0 → 0.5.1`). The parser accepts the field today; the schema declaration follows in the sibling-ship turn. **No `expectedSchemaVersion` change**, **no `.verified.json` migration**, **no solver-time delta** (CDP reuses the existing `emitFixpoint` + liquid-fixpoint loop per candidate; no new SMT fragment expansion per proposal §8).
- **22 new tests** (`C1`–`C22`) under a new `LT-CDP (v0.11): contract discriminative power` `describe` block in [`compiler/test/Spec.hs`](compiler/test/Spec.hs) — candidate enumeration per return type (C1–C7), score-formula edge cases (C8–C11), spec-entropy parse + roundtrip in both frontends (C12–C15), trust-report JSON shape and the seven typed warnings (C16–C19), joint-witness compatibility regression guard (C20), over-annotation diagnostic (C21), and `computeCDPFor` end-to-end with a stub solver (C22). Three new fixtures under [`compiler/test/fixtures/cdp/`](compiler/test/fixtures/cdp/) (`verified-strong.llmll`, `verified-weak.llmll`, `intentional.llmll`). Engineer-shipped on branch `lt-cdp/discriminative-power-axis`, commit `121815a`. Intermediate test count: 702 Haskell + 58 Python.

### Compiler — LT-PPR (v0.11): predicate-carrying `?proof-required`

- **`(?proof-required :reason "tag" pred-expr)` is a new S-expression form** accepted in `pre` and `post` contract positions inside `def-logic` and `def-shell` (LT-PPR, commit `3391713`). The bare `?proof-required` leaf and the `(?proof-required :reason "tag")` form without a predicate are unchanged. `pred-expr` is type-checked as `bool` by [`compiler/src/LLMLL/TypeCheck.hs`](compiler/src/LLMLL/TypeCheck.hs). `isCoreBodySyntactic` in [`compiler/src/LLMLL/Parser.hs`](compiler/src/LLMLL/Parser.hs) rejects `?proof-required` (both forms) from strict-core `def` bodies under `--grammar=core-inversion`, consistent with its pre-LT-PPR treatment.
- **A predicate-carrying `?proof-required` in `pre`/`post` position emits a Haskell runtime assertion** in generated code (`if <pred> then () else error "proof-required: <reason>"`), instead of the previous no-op. Pre-LT-PPR, all `?proof-required` in `pre`/`post` were no-ops at codegen; the clause was marked `asserted` and otherwise ignored at runtime. Body-position `?proof-required` continues to emit an `error "proof-required"` stub; no runtime assertion change there.
- **Non-linear predicates in the predicate-carrying form emit a `QF-LIA` warning at `llmll check`** when `pred-expr` contains `*`, `/`, `mod`, or `^`. The warning names the function and clause. Non-linearity detection reuses `isNonLinear` now exported from [`compiler/src/LLMLL/HoleAnalysis.hs`](compiler/src/LLMLL/HoleAnalysis.hs) and shared with the type-checker.
- **`hole-proof-required` JSON-AST node gains an optional `"predicate"` field** (`{ "$ref": "#/$defs/Expr" }`). The bare-leaf form omits the field; the predicate-carrying form sets it. The `"reason"` field semantics are unchanged. **No `schemaVersion` bump** — stays `0.5.0` per [`docs/archive/shipped-design-specs/v0.11-cross-proposal-rollback-discipline.md`](docs/archive/shipped-design-specs/v0.11-cross-proposal-rollback-discipline.md) §2; schema bump is bundled with the LT-INV default-flip gate.
- **`--trust-report --json` per-entry output gains six additive fields** when a predicate-carrying `?proof-required` is present on the entry's function: `pre_predicate_form` (form-mode label: `"runtime"` in v0.11), `pre_predicate_text` (JSON-encoded predicate expression), `pre_runtime_check_emitted` (only-when-true bool), and `post_*` equivalents. Note: `predicate_form` is the enforcement-mode label, not an expression string; `predicate_text` is the expression, not a label — these descriptions correct an inversion in a prior draft of this entry. Fields are emitted only when non-default; absent-predicate entries see no shape change. `trust_report_version` stays `1.2.0` (set by LT-CDP; PPR fields are strictly additive). Schema: [`docs/llmll-trust-report.schema.json`](docs/llmll-trust-report.schema.json) `$defs/TrustEntry` gains the six fields.
- **+20 new LT-PPR regression tests** (`PPR-P1`–`PPR-P4`, `PPR-T1`–`PPR-T5`, `PPR-A1`–`PPR-A2`, `PPR-TR1`–`PPR-TR4`, `PPR-CG1`–`PPR-CG3`, `PPR-G1`–`PPR-G2`) in [`compiler/test/Spec.hs`](compiler/test/Spec.hs). Running total at cluster commit `3391713`: 764 Haskell + 58 Python (before F-GATE-1 follow-ons; see LT-INV entry above for post-F-GATE-1 aggregate).

### Compiler — fix: DiagnosticFQ partial-record crash on `--json verify` SAFE (F-001)

- **Three branches of `fqResultToReport` in [`compiler/src/LLMLL/DiagnosticFQ.hs:94-115`](compiler/src/LLMLL/DiagnosticFQ.hs) now initialize the `reportPhase :: Text` field to `"lh-fixpoint"`.** Pre-fix the field was omitted at construction and fell to ⊥; any consumer accessing it — notably `formatReportJson` at [`compiler/src/LLMLL/Diagnostic.hs:352`](compiler/src/LLMLL/Diagnostic.hs) — crashed with `Missing field in record construction reportPhase`. Latent across the entire `--trust-report` lifetime because the typical `--json verify --trust-report` SAFE path early-exited at [`compiler/app/Main.hs:1078`](compiler/app/Main.hs) before reaching the verifier loop; surfaced by the LT-CDP code-path change at commit `121815a` and reproduced empirically by the experiment-lead CDP-0 baseline harness (finding F-001 in `experiments/cdp-0/findings/postmortem-001-cdp-baseline-blocked.md`).
- **Phase string `"lh-fixpoint"`** follows the convention at [`compiler/src/LLMLL/TypeCheck.hs:413`](compiler/src/LLMLL/TypeCheck.hs) (`"typecheck"`) and [`compiler/src/LLMLL/PatchApply.hs:254`](compiler/src/LLMLL/PatchApply.hs) (`"patch"`) — short lowercase kebab tokens naming the source phase.
- **GHC `-Wmissing-fields` warned at compile time** (GHC-20125 at lines 96, 102, 108) but was filtered as "pre-existing" during the LT-CDP build inventory; the bug had zero test coverage (no test imported `fqResultToReport` or `formatReportJson`). Four regression tests (DF-1 through DF-4) in [`compiler/test/Spec.hs`](compiler/test/Spec.hs) close the test gap by forcing evaluation of `reportPhase` both directly and through the Aeson JSON encoder; drop the field-init and DF-4 fails with the same runtime exception observed on the CLI.
- **End-to-end smoke verified.** `stack exec llmll -- --json verify ../examples/benchmarks/b1-withdraw.llmll` returns exit 0 with a JSON object containing `"phase":"lh-fixpoint"`; the CDP-0 harness is unblocked. Net build-warning delta: −5 (three `-Wmissing-fields` + two `-Wunused-matches` eliminated by the same field-initialization patch).
- **Zero schema delta, zero solver-time delta, zero trust-model effect, zero language-surface change.** Engineer-shipped on branch `fix/diagnosticfq-partial-record` (off `lt-cdp/discriminative-power-axis`), commit `e5e6d04`. **Tests:** 706 Haskell + 58 Python (LT-CDP added 22 Haskell tests; F-001 added 4; Python suite unchanged from the LT-INT entry above; observed-vs-published Python-count discrepancy of +3 carried forward as a follow-up routing item).

### Compiler — fix: WeaknessCheck zero-candidate generation (F-006 / F-005 ancillary)

- **`generateCDPCandidates` now produces non-zero `candidate_count` for functions whose parameters carry custom type aliases (e.g. `PositiveInt`).** Root cause (F-006): `tryCandidate` called `typeCheck builtinEnv [syntheticStmt]` with an empty `tcAliasMap`; `expandAlias (TCustom "PositiveInt")` returned the opaque `TCustom` node unchanged, causing `structuralUnify` to fail the synthetic pre-condition check and filter every candidate. Fix: `generateForStmt` now receives the full module-level `[Statement]` list; `tryCandidate` prepends `[s | s@STypeDef{} <- allStmts]` to the synthetic type-check call, so `checkStatements` populates `tcAliasMap` with module-level aliases before checking the contract. Restores `b1::withdraw` and `b3::safe-first` from `candidate_count = 0` to `candidate_count ≥ 2` per [`experiments/cdp-0/findings/postmortem-002-cdp-baseline-rerun.md`](experiments/cdp-0/findings/postmortem-002-cdp-baseline-rerun.md) acceptance criteria.
- **`cdpCatalog` now generates the full §4.3.1 constant enumeration for sexp-parsed functions whose return type is unannotated (`mRet = Nothing`).** Root cause (F-005 ancillary): `matchesReturnType _ Nothing = False` suppressed all constant generation; only identity candidates were produced. Fix: new private helper `matchesReturnTypeOrUnknown :: Type -> Maybe Type -> Bool` (`_ Nothing = True`) used in the `ints`, `bools`, and `strings` arms of `cdpCatalog`; `Nothing` arms added to the `lists` (`[TrivConstEmptyList]`) and `sums` (`[TrivConstError]`) cases. The type-checker (INV-4) filters incompatible candidates before the solver. `legacyCatalog` and the `--weakness-check` diagnostic surface are unchanged. Restores `b5::double` from `candidate_count = 1` (identity-only) to `candidate_count ≥ 5` (1 identity + 4 int constants).
- **`WarnVacuousOverOmega` CDP warning added** for the tight-but-verified case: when a `def-logic` function has body-faithful verified evidence (`DLVerified`/`DLContractChecked`) and no candidate satisfies the contract over Ω, the warning is `WarnVacuousOverOmega` rather than `WarnSpecInconsistent`. `WarnSpecInconsistent` is now reserved for functions without verification evidence. `provenCS` hoisted out of the `FQSafe` sidecar arm to share the verified-map oracle between CDP and the trust-report path. Engineer-shipped on branch `fix/diagnosticfq-partial-record`, commit `0b5b249` (F-005 follow-on). +4 Haskell tests.
- **Zero language-surface change, zero CLI flag change, zero schema change.** `--cdp` behavior is externally identical for functions with fully annotated types; the fix removes false-negative filtering on the type-alias and unannotated-return code paths only. Engineer-shipped on branch `fix/diagnosticfq-partial-record`, commit `6f2ea39`. **Tests:** 716 Haskell + 58 Python (+6 Haskell: F6-1–F6-6 candidate-generation regression tests in [`compiler/test/Spec.hs`](compiler/test/Spec.hs) under the `"LT-CDP (v0.11): contract discriminative power"` describe block; +4 Haskell: `WarnVacuousOverOmega` disambiguation tests, commit `0b5b249`).

### CI — DRIFT-CI-1 version-gate workflow + harness

- **Closes both DRIFT-CI-1 residuals named on [`docs/compiler-team-roadmap.md:304`](docs/compiler-team-roadmap.md) and [`docs/design/critique-2026-05-23-triage.md:111`](docs/design/critique-2026-05-23-triage.md):** the `.github/workflows/version-gate.yml` automation and the whole-spec round-trip harness for C5. Content (C1–C5) was already satisfied at v0.10.8 via doc-lead Pass 6 + Pass 7; this patch adds the mechanical enforcement that prevents future drift.
- **[`scripts/version_gate.sh`](scripts/version_gate.sh)** implements C1+C2+C3+C4. C1+C2: banner equality across `README.md` line 1, `LLMLL.md` line 1, the first `## vX.Y.Z` heading in `CHANGELOG.md`, `compiler/package.yaml` `version:` field, and `compiler/llmll.cabal` `version:` field. C3: `docs/llmll-ast.schema.json` `$defs.Program.properties.schemaVersion.const` equals `compiler/src/LLMLL/ParserJSON.hs::expectedSchemaVersion`. C4: schema `$id` URL contains `/schemas/vMAJOR.MINOR/` derived from the `schemaVersion` const. Pure POSIX shell + `grep`/`awk`/`jq`; no Stack/GHC dependency; runs in well under a second locally. Exits 0 on all-pass, exits 1 with a single-line `DRIFT-CI-1 FAIL: <criterion> ...` message on first failure.
- **[`scripts/spec_roundtrip.py`](scripts/spec_roundtrip.py)** implements C5 as an *opt-in* harness. Spec authors mark a fenced ` ```lisp ` or ` ```llmll ` block with `<!-- ci:roundtrip -->` (or `<!-- ci:roundtrip: strict -->` for warnings-as-errors) immediately above the fence opener, allowing at most one blank line in between. The script writes each opted-in block to a tempfile and shells out to `llmll check` (overridable via `LLMLL_BIN`; default `stack exec llmll --`). Failures surface as `FAIL <path>:<line> ...` and a non-zero exit. Opt-in (rather than default-on with skip annotations) was chosen after on-tree inspection of `LLMLL.md`: nearly every `lisp` block references unbound names or undefined refinement types per spec convention, so default-on would require ~50+ skip markers and pollute the spec with CI noise. Doc-lead extends the opt-in surface in subsequent passes.
- **Initial opt-in set: one block** at [`LLMLL.md:396`](LLMLL.md) (the §4.4.3 `(trust ...)` example), chosen because it parses cleanly without external context. The block exercises the harness end-to-end against the real `llmll` binary in CI so a misconfigured `LLMLL_BIN` invocation surfaces in the workflow rather than silently passing on zero blocks.
- **[`.github/workflows/version-gate.yml`](.github/workflows/version-gate.yml)** is the first GitHub Actions workflow in this repository. Two jobs trigger on `push` to `main` and on `pull_request` against `main`. Job `version-gate` (Ubuntu, no Stack toolchain, target wall-clock <1 min): installs `jq`, runs `scripts/version_gate.sh`, runs the 21-case pytest suite at `scripts/tests/`. Job `spec-roundtrip` (Ubuntu, Stack toolchain with `~/.stack` + `compiler/.stack-work` cached against `compiler/stack.yaml.lock`, target wall-clock ~5 min steady-state): builds `llmll`, runs `scripts/spec_roundtrip.py` against `LLMLL.md` opt-in blocks. Scope discipline: workflow is intentionally named `version-gate.yml`, not `ci.yml`, and does not run `stack test` or the harness/orchestra Python suites — those belong to a separate ticket. Security posture: no `run:` block interpolates `${{ github.event.* }}` or any attacker-controllable context; the only `${{ }}` expressions used are `runner.os` and `hashFiles(...)`.
- **21 new pytest cases at [`scripts/tests/`](scripts/tests/)** — 11 for `version_gate.sh` (live-tree pass, synthetic-repo pass, one failure case per criterion + a substring-extraction edge case) and 10 for `spec_roundtrip.py` (no-opt-in pass, opt-in stub pass/fail, blank-line-gap allowed, distance-gap rejected, `strict` flag pass-through both directions, `llmll` tag accepted alongside `lisp`, mixed pass/fail aggregation, missing-spec-file error). Tests inject a Python `llmll` stub via the `LLMLL_BIN` env var so they have no Stack dependency and run in under a second.
- **Inside-freeze, narrowing.** No new syntax, no new builtins, no new SMT theory, no schema bump (`expectedSchemaVersion` stays `0.5.0`), no `trust_report_version` change, no verifier or type-checker surface change, no `.verified.json` migration, no solver-time delta. Pure CI scaffolding; rollback is a single revert. **Test count: 672 Haskell + 58 Python (37 prior + 21 new DRIFT-CI-1 harness cases).**

### Docs — DOC-CONSOLIDATE documentation consolidation and SOP

- **DOC-CONSOLIDATE — Project documentation consolidation and SOP** (settled at [`docs/design/doc-consolidation-2026-05-24-proposal.md`](docs/archive/shipped-design-specs/doc-consolidation-2026-05-24-proposal.md) Rev 1, 2026-05-24). Introduces [`docs/UPDATE-PROTOCOL.md`](docs/UPDATE-PROTOCOL.md) codifying P1 canonical-source bindings and the per-change update matrix (§3.1–3.3 verbatim); collapses per-experiment per-role findings to a single `experiments/<harness>/findings.md` with H2-per-role per §M1/§4.3; folds settled professor reviews into proposal `## Appendix — Professor review log` sections per §M2 and archives the standalone review files; archives pre-roadmap-reorganization wasm spike docs per §M4; H2-anchor reorg of [`docs/compiler-team-roadmap.md`](docs/compiler-team-roadmap.md) per §M5 small-cut plus P1 strip of the roadmap header's version stamp; migrates the active items from `docs/research-track.md` into the roadmap with a deferred-overlap-audit wrapper. No language-surface change, no schema bump (`expectedSchemaVersion` stays `0.5.0`), no `trust_report_version` change, no compiler change, no test count delta. Eliminates the three-source status-drift pattern flagged in proposal §1 by routing through P1 canonical sources for the *version* and *implementation-routing* bindings; the *design-doc-status* P1 binding (M6 INDEX.md demotion to one-liners) is deferred to a follow-up doc-lead pass.
- **Files added:** [`docs/UPDATE-PROTOCOL.md`](docs/UPDATE-PROTOCOL.md) (§3 verbatim); [`experiments/minimal-agent/findings.md`](experiments/minimal-agent/findings.md), [`experiments/int-pre/findings.md`](experiments/int-pre/findings.md), [`experiments/repair-loop/findings.md`](experiments/repair-loop/findings.md) (H2-per-role per §M1); `docs/archive/professor-reviews/` and `docs/archive/wasm-investigations/` subdirs.
- **Files archived (with 2-line redirect stub at old path for one release cycle):** `docs/design/{invariant-discovery,oblig-pbt-3}-review.md` → `docs/archive/professor-reviews/` (M2 case 1; preceded by `## Appendix — Professor review log` fold into the matching proposals); `docs/{effectful-wasm-spike,wasm-poc-report}.md` → `docs/archive/wasm-investigations/` (M4); `docs/design/proof-required-predicate-carrier.md` → `docs/archive/shipped-design-specs/` (M2 case 2 superseded-seed); `docs/research-track.md` → `docs/archive/` (M4; per-item overlap audit deferred to language-team).
- **Files edited:** [`README.md`](README.md) (M3 ~70-line CHANGELOG-shaped-paragraph strip; stale-callout refresh; repository-layout and Documentation-table refresh); [`docs/compiler-team-roadmap.md`](docs/compiler-team-roadmap.md) (M5 small-cut ToC + H2-anchor normalization for `Upcoming Releases` / `Cross-cutting concerns` / `Summary` / `Shipped Releases`; P1 header version-stamp strip; research-track migration R1–R7 with overlap-audit-deferred wrapper); [`docs/design/invariant-discovery-proposal.md`](docs/design/invariant-discovery-proposal.md) and [`docs/design/oblig-pbt-3-proposal.md`](docs/archive/shipped-design-specs/oblig-pbt-3-proposal.md) (`## Appendix — Professor review log` fold per §M2).
- **Skill blocks (verified, no edit):** all 5 `.claude/skills/*/SKILL.md` files already carry `## Documentation discipline` sections per §4.1–4.5 referencing [`docs/UPDATE-PROTOCOL.md`](docs/UPDATE-PROTOCOL.md); applied in a prior pass, no further edit on this PR.
- **Deferred to follow-up:** `docs/design/INDEX.md` M6 demotion to one-line entries; per-item overlap audit of migrated research-track items R1–R7 against existing roadmap rows. Both surfaced as findings in the doc-lead plan and routed to language-team for the follow-up pass.
- **R1–R7 overlap audit close-out** (DOC-CONSOLIDATE §11 follow-up): four cross-references applied to roadmap research-track section, R3 partial-criterion flagged; DOC-CONSOLIDATE fully closed.
- **Net active doc surface:** −11 active files (−9 role files folded; −6 docs/ files archived; +4 new files: UPDATE-PROTOCOL.md + 3 findings.md). All archive moves carry 2-line redirect stubs at the old paths for one release cycle. **No test count delta** — the closing 672 Haskell + 58 Python figure inherited from the DRIFT-CI-1 entry above stands for the whole Unreleased section.
- **Design-folder Phase 2 cleanup** (DOC-CONSOLIDATE §4.4 follow-up): re-homed two orphan empirical docs to `experiments/` ([`experiments/methodology.md`](experiments/methodology.md), [`experiments/repair-loop/findings/phase3-problem-shape-audit.md`](experiments/repair-loop/findings/phase3-problem-shape-audit.md)) with 2-line redirect stubs at the old `docs/design/` paths for one release cycle; codified pre-planned archive moves as [`docs/UPDATE-PROTOCOL.md`](docs/UPDATE-PROTOCOL.md) §3.4 (gated archive-trajectory table for ten in-flight design docs); flagged the `docs/archive/shipped-design-specs/` sub-categorization threshold (~20 entries; currently 11) and a forward-looking `docs/archive/dormant-explorations/` subdir in §3.3; deleted the resolved `## Orphan / Empirical-Track Notes` section from [`docs/design/INDEX.md`](docs/design/INDEX.md). Net active-doc delta: −2 files in `docs/design/` (orphan-section removal + 2 relocations); +2 redirect stubs (auto-delete one release cycle later); +1 protocol appendix; +2 files under `experiments/`. Zero schema, spec, code, test, version, or trust-report change.
- **Design-folder N1 status audit** (DOC-CONSOLIDATE §4.4 follow-up): archived `docs/archive/shipped-design-specs/lead-agent.md` → `docs/archive/shipped-design-specs/lead-agent.md` (v0.4 design shipped end-to-end per [`docs/compiler-team-roadmap.md`](docs/compiler-team-roadmap.md) §v0.4 phases 0–2; status-drift closure matching the existing shipped-design-specs pattern) with 2-line redirect stub at the old path for one release cycle; relabeled `agent-orchestration.md`, `component-hub.md`, `type-driven-development.md` as **Dormant** with reason suffixes (no change to `language-comparison-experiments.md`, which stays Active per audit). [`docs/design/INDEX.md`](docs/design/INDEX.md) Future Infrastructure row count: 5 → 4 (1 active + 3 dormant); Archived Material `shipped-design-specs/` listing extended. Net delta: −1 active doc in `docs/design/`; +1 archive file; +1 redirect stub. Zero schema, spec, code, test, version, or trust-report change.

---

## v0.10.8 — INT-1 Overflow-Taint Marking + Strict-Core Refusal (2026-05-24)

### Compiler — INT-1 Overflow-Taint Propagation on Verified Evidence

- **`erOverflowTainted :: Bool` added to `EvidenceRecord` at [`compiler/src/LLMLL/Syntax.hs:326-331`](compiler/src/LLMLL/Syntax.hs#L326-L331).** The flag marks `DLVerified` body-faithful evidence whose function body contains LLMLL-level integer arithmetic over non-literal operands. The flag's semantic is: "this evidence is sound at the verifier level but the underlying Haskell `Int` arithmetic may overflow, making the codegen-level guarantee weaker than the Z3-level guarantee." This is the operational discharge of the documented `Int64` overflow gap at [`LLMLL.md §5.3.5:765-770`](LLMLL.md#L765-L770), which has been on the books since v0.8.1a's documentation-boundary pass. Per the 2026-05-23 critique-triage routing at [`docs/design/critique-2026-05-23-triage.md`](docs/design/critique-2026-05-23-triage.md) row INT-1; inside-freeze, narrowing fix.
- **Body-VC emitter activates the tag.** [`compiler/src/LLMLL/FixpointEmit.hs:506-516`](compiler/src/LLMLL/FixpointEmit.hs#L506-L516) calls `when (bodyHasOverflowArith body) (addOverflowTainted name)` immediately after `addBodyFaithful name`, gated on body-faithful VC success. The new helper `bodyHasOverflowArith :: Expr -> Bool` (exported for testing, defined at [`compiler/src/LLMLL/FixpointEmit.hs:597-642`](compiler/src/LLMLL/FixpointEmit.hs#L597-L642)) runs a pure syntactic walk over the body Expr looking for `EOp` / `EApp` whose head is in `{+, -, *, /, mod, rem, ^, **}` and whose operands are not all integer literals whose folded value fits `Int64`. Pure-literal arithmetic like `(+ 40 2)` clears (the compile-time constant is in `Int64`); any non-literal operand or out-of-range literal taints the surrounding op. No new SMT constraints emitted, no QF-BV introduced, no solver-time delta — the cost is one Expr walk per body-faithful function (estimated <100µs on TOTP-scale inputs).
- **`--strict-verified-core` refuses overflow-tainted verified evidence.** [`compiler/app/Main.hs:1119-1158`](compiler/app/Main.hs#L1119-L1158) extends the refusal set from `erBodyFallback` to `erBodyFallback ∪ erOverflowTaintedFns`. The two causes are mutually exclusive (taint is gated on body-faithful success) and each gets a distinct error message: fallbacks report "fell back from body-faithful verification"; taints report "carry overflow-tainted verified evidence (unbounded-Int arithmetic; clear via `?proof-required` + Leanstral or wait for INT-2 unbounded `int`)". JSON-mode output structures the two causes as separate `strict_errors` entries with `cause`, `fns`, and `msg` fields. The non-strict consumer behavior is unchanged: trust report, obligation report, and sidecar continue to surface the tag without exiting non-zero.
- **Trigger set is empty post-INT-2.** Once the v0.11 INT-2 codegen switch lands (`int → Integer` at codegen, per [`docs/archive/shipped-design-specs/int-2-boundary-shims.md`](docs/archive/shipped-design-specs/int-2-boundary-shims.md) §4), `int`-typed arithmetic lowers to unbounded `Haskell.Integer`; no overflow event exists to propagate. The taint machinery becomes dormant on `int` and re-arms naturally on the post-freeze `machine-int` opt-in primitive tracked at [`docs/design/int-3-machine-int-sketch.md`](docs/design/int-3-machine-int-sketch.md) §3.2. INT-1 is therefore neither dead code post-INT-2 nor active-on-`int` post-INT-2 — it is dormant on `int`, armed for `machine-int`.
- **Closes `LLMLL.md §3` doc-lead gating.** [`docs/compiler-team-roadmap.md:300`](docs/compiler-team-roadmap.md) (DRIFT-1 row) explicitly gated the §3 type-system catch-up on INT-1 shipping; this release unblocks the doc-lead Pass 7 on `LLMLL.md §3`.

### Compiler — Sidecar JSON Encoding + Invalidate-on-Missing

- **`.verified.json` gains optional `overflow_tainted: true` per-clause.** [`compiler/src/LLMLL/VerifiedCache.hs:71-94`](compiler/src/LLMLL/VerifiedCache.hs#L71-L94) extends `erToJSON` to emit the field only when `True` (matching the additive-back-compat shape used for `pbt_witnesses` at line 78). `erFromJSON` defaults the absent field to `False` for additive-back-compat reads; the older v0.10.7-vintage sidecars without the field decode cleanly into untainted records.
- **`loadVerified` invalidates pre-v0.10.8 sidecars to avoid silent under-strictness.** [`compiler/src/LLMLL/VerifiedCache.hs:158-216`](compiler/src/LLMLL/VerifiedCache.hs#L158-L216) gains `sidecarNeedsRevalidation` that returns `True` when any `DLVerified` body-faithful entry lacks the `overflow_tainted` field. Such sidecars return `Map.empty`, forcing a re-verify under v0.10.8's taint scan. The targeted-invalidation contract is: untainted entries that lack the field are read as untainted (back-compat), but verified body-faithful entries are re-checked under the new rule so strict-core consumers never see a silent false-negative on a stale sidecar. CI pipelines that hash-pin `.verified.json` artefacts may see one-time hash changes after upgrading; the new shape is stable thereafter.

### Compiler — Trust-Report and Obligation-Report Surfacing

- **`--trust-report --json` aggregates `overflow_tainted_fns` at the top level + per-entry `overflow_tainted: true`.** [`compiler/src/LLMLL/TrustReport.hs:701-735`](compiler/src/LLMLL/TrustReport.hs#L701-L735) adds an `"overflow_tainted_fns": [names…]` array next to the existing `"joint_pbt_witnesses"` aggregate, and a per-entry `"overflow_tainted": true` (emitted only when true) on the matching trust-report entries. `trust_report_version` stays `"1.1.0"` per the OBLIG-PBT-5a precedent at line 712: the field is purely additive at JSON-shape level, readers ignore unknown keys, the JSON shape grows monotonically.
- **`--obligation-report --json` per-clause trust channel gains `overflow_tainted`.** [`compiler/src/LLMLL/ObligationAssembly.hs:114-119, 543, 549-550, 582-592, 628-634, 802-812`](compiler/src/LLMLL/ObligationAssembly.hs#L114-L119) extends `TrustChannel` with `trOverflowTainted :: Bool`, threads the `erOverflowTaintedFns` set from `EmitResult` through `assembleHoleObligations` / `mkHoleObl`, and emits `"overflow_tainted": true` on the trust channel only when set. Untainted obligations preserve their pre-v0.10.8 trust-channel JSON byte-identically.
- **Verify-text mode summary line.** [`compiler/app/Main.hs:1107-1119`](compiler/app/Main.hs#L1107-L1119) adds an `overflow-tainted: <names>` summary line, parallel to existing `body-faithful` and `body-fallback`. Emitted only when non-empty.

### Examples — Regen with Overflow-Taint Awareness

- **`examples/banking_ledger/banking.llmll.verified.json` regenerated.** The `safe-subtract` function (body `(- a b)` over two `int` parameters) now carries `overflow_tainted: true` on its DLVerified body-faithful post. `withdraw`, `transfer`, `clamp-withdraw`, and `withdraw-twice` do not taint at their own body level (each body is a user-function call, not direct arithmetic); transitive trust over the tainted `safe-subtract` is not propagated to caller-level taint because the taint is per-function-body, not per-trust-closure. `--strict-verified-core` on this fixture now hard-errors at `safe-subtract` — design-intended per the deliberate narrowing.
- **Other tracked sidecars unchanged in semantic content.** `examples/erc20_token/erc20_filled.ast.json.verified.json` uses a pre-v0.8.1b sidecar shape (`level` field directly, no `display_level` wrapper) that was already stale on read before INT-1; not regenerated in this release.

### Schema — Trust-Report Output Schema Additive Update

- **`docs/llmll-trust-report.schema.json`** (post-engineer-ship doc-lead scope) is expected to gain an optional `overflow_tainted_fns: [string]` top-level property and an optional `overflow_tainted: const true` boolean on `TrustEntry`. `trust_report_version` stays `"1.1.0"` per the additive-field policy.
- **`docs/llmll-ast.schema.json`** unchanged. No AST node shape change in this release; `expectedSchemaVersion` stays `0.5.0`.

### Test surface

- **+16 Haskell test cases** under `describe "INT-1 (v0.10.8): overflow taint propagation"` in [`compiler/test/Spec.hs`](compiler/test/Spec.hs), covering: T1 literal-only arithmetic clearance; T2-T6 propagation across `EOp` / `EApp` / nested heads; T7 Class A indexing primitives stay untainted; T8 `ELet` rhs propagation; T9 `EIf` branch propagation; T10 end-to-end emit through `emitFixpointWith`; T11 pure-predicate body stays untainted end-to-end; T12 sidecar round-trip preserves `overflow_tainted: true`; T13 pre-v0.10.8 verified body-faithful sidecar is invalidated; T14 v0.10.7 asserted-only sidecar loads normally (targeted invalidation); T15 trust-report JSON aggregation; T16 small-sample literal-arithmetic clearance property.
- **Test count: 656 → 672 Haskell + 37 Python = 709 total passing.** No existing test regressed under the EvidenceRecord field addition (eight positional construction sites in `compiler/src/LLMLL/{Module,TrustReport,PBT}.hs`, `compiler/app/Main.hs`, and ~30 sites in `compiler/test/Spec.hs` were mechanically updated to add the fifth `False` argument; one `Spec.hs:5521` multi-line case kept the literal in place).

---

## v0.10.7 — EOp Arity/Type-Check Fix + Joint PBT Witness Exclusion (2026-05-23)

### Compiler — TC-EOP-1 EOp Arity and Argument-Type Checking

- **`inferExpr (EOp op args)` now checks arity and unifies each argument against the corresponding parameter type.** Pre-fix the function ignored `args` entirely at [`compiler/src/LLMLL/TypeCheck.hs:981-988`](compiler/src/LLMLL/TypeCheck.hs#L981-L988) and returned the `builtinEnv` result type unconditionally, so `(+ 1)`, `(+ 1 2 3)`, `(+ "x" 1)`, `(not 1)`, `(= 1 "1")`, `(and true 0)`, etc. silently typechecked. The rewrite mirrors the `EApp` path at lines 920-973: arity check + `foldM` over args with `structuralUnify`'s per-call-site substitution map, `withSegment "args"` pointer-stack discipline, and `EHole` bypass via `checkExpr`. Polymorphic operators (`=`, `!=`) bind `TVar "a"` from arg 0 and require arg 1 to unify against the same type — no `any × any → bool` degrade. Per the 2026-05-23 critique-triage routing at [`docs/design/critique-2026-05-23-triage.md`](docs/design/critique-2026-05-23-triage.md) row TC-EOP-1; narrowing fix admitted under the v0.10-era freeze.
- **No example regressions.** The full `examples/` corpus (16 `.llmll` + 18 `.ast.json` shipping fixtures) typechecks unchanged under the new arity/type discipline. Pre-existing parse failures on `examples/pair_type_test/pair_type_test.llmll` (return-type comma surface) are orthogonal.

### Compiler — OBLIG-PBT-5a Joint PBT Witness Exclusion

- **Scalar `tested` counts no longer over-credit `:subjects [f g …]` joint lifts.** OBLIG-PBT-4 emits one `EvidenceRecord` per declared subject with a shared `canonicalPropBodyHash`; the v0.10.6 trust-report counted each as `+1 tested`, so N subjects sharing one property body contributed N to `summary.tested` / `tier_profile.tested` / `tier_profile_post.tested`. v0.10.7 computes a `jointHashes :: Set Text` (hashes appearing on ≥2 distinct subjects' post-clause witnesses) in [`compiler/src/LLMLL/TrustReport.hs`](compiler/src/LLMLL/TrustReport.hs) and demotes any `DLTested` entry whose post-clause evidence has non-empty `erPbtWitnesses` AND every hash in `jointHashes` to `DLAsserted` at classification time. The underlying `EvidenceRecord` is left intact on the entry (and in `.verified.json` sidecars) so the clean OBLIG-PBT-5b fix can promote a `tested-joint` display level post-freeze without losing data.
- **The "every witness is joint" predicate does the real work.** A subject with both a joint-shared witness AND a solo (single-subject) witness on the same evidence record keeps its `+1 tested` credit — only pure-joint entries are demoted. Source-annotated `DLTested` from `:trust tested` markers (empty `pbt_witnesses`) is also unaffected because the predicate requires non-empty witnesses. This preserves OBLIG-PBT-3 v0.10.5 semantics for the non-`:subjects` path.
- **Additive emit at every surface.** Per-entry JSON gains an optional `joint_pbt_witness: true` field (omitted when false to keep emit minimal). Top-level JSON gains `joint_pbt_witnesses: [{hash, subjects: [...]}]` listing the deterministic-ordered groupings. Text mode adds a "Joint PBT witnesses" section between the existing suppressions and stale-downgrade blocks. `trust_report_version` stays `1.1.0` per the 2026-05-23 triage explicit constraint at [`docs/design/critique-2026-05-23-triage.md`](docs/design/critique-2026-05-23-triage.md) row OBLIG-PBT-5a; the clean version-bumped fix is OBLIG-PBT-5b in the v0.12+ post-freeze lane.
- **Demotion target.** Joint-only `DLTested` demotes to `DLAsserted` (the existing diamond-meet sink), not into a new `tested-joint-only` slot — the latter requires a `trust_report_version` bump (OBLIG-PBT-5b). Documented at [`docs/compiler-team-roadmap.md`](docs/compiler-team-roadmap.md) v0.10.x patch-lane row.

### Schema — Trust-Report Output Schema Additive Update

- **`docs/llmll-trust-report.schema.json`** gains optional `joint_pbt_witnesses` top-level property (`JointPbtWitness` `$def` requires `subjects.length >= 2` and `hash` matches `^sha256:[0-9a-f]{64}$`) and an optional `joint_pbt_witness: const true` boolean on `TrustEntry`. `additionalProperties: false` on the top-level object now lists the new key explicitly; `TrustEntry`'s pre-existing `additionalProperties: true` admits the per-entry flag without further change. `trust_report_version` stays `1.1.0`.
- **`docs/llmll-ast.schema.json`** unchanged. No AST node shape change in this release; `expectedSchemaVersion` stays `0.5.0`.

### Test surface

- **656 Haskell tests + 37 Python tests** (up from 640 + 37 at v0.10.6). New: 10 tests under `TC-EOP-1 EOp arity and arg-type checking` covering arity errors (under/over), arg-type mismatches across `+` / `not` / `=` / `and`, polymorphic equality both positive and negative, the `EHole`-in-EOp bypass, and JSON-AST frontend parity; 6 tests under `OBLIG-PBT-5a joint PBT witness exclusion` covering the joint-only demotion (J1), the solo+joint mix predicate (J2), the source-annotated empty-witness non-demotion (J3), the singleton-head-position non-demotion (J4), the per-entry `joint_pbt_witness: true` emit gating (J5), and the no-`trust_report_version`-bump additive emit invariant (J6).
- **No solver-time delta.** TC-EOP-1 is a type-checker-only tightening; OBLIG-PBT-5a is a trust-report consumer-side classification refinement after VC emission has completed. Verification fragment unchanged (stays in QF-LIA).

### Empirical close-state

- **TC-EOP-1 closed.** Pre-fix `(+ "x" 1)`, `(not 1)`, `(= 1 "1")`, `(+ 1)` all silently typechecked; post-fix all four produce structured `type-mismatch` / arity diagnostics with `expected` / `got` fields. Both the S-expression and JSON-AST frontends route through the same `inferExpr (EOp ...)` path, regression-locked by case 9 of the test block.
- **OBLIG-PBT-5a closed.** A `:subjects [encrypt decrypt]` roundtrip property that previously credited 2 against `tpTested` now credits 0; the same property combined with a solo `:subject encrypt` property credits 1 (encrypt) instead of 2.

### What this does NOT close

- **INT-1 (`overflow_tainted` marking).** P1 inside-freeze item from the same triage record; not bundled in v0.10.7 to keep the patch tightly scoped to TC-EOP-1 + OBLIG-PBT-5a per the engineer hand-off prompt at [`docs/design/critique-2026-05-23-triage.md`](docs/design/critique-2026-05-23-triage.md) §6. Deferred to v0.10.8 paired with INT-PRE measurement.
- **DRIFT-CI-1 (5-criterion version-gate CI).** Infra / doc-lead scope; not in the engineer turn. Tracked for the next doc-lead pass.
- **OBLIG-PBT-5b (clean fix with new `tested-joint` display level).** Requires `trust_report_version` major bump and a new `DisplayLevel` constructor; explicitly post-freeze per [`docs/compiler-team-roadmap.md`](docs/compiler-team-roadmap.md) v0.12+ lane.

---

## v0.10.6 — :subjects Metadata + PBT Body-Static-Eval Coverage + Residual Builtin Coverage (2026-05-14)

### Compiler — OBLIG-PBT-4 `:subject` / `:subjects` Metadata on `(check ...)`

- **`(check "d" :subject f (for-all …))` and `(check "d" :subjects [f₁ … fₖ] (for-all …))` accepted.** Optional keyword metadata between the description and the for-all opts a property into explicit-subject lift mode at the OBLIG-PBT-3 writeback site. Absent annotation = the v0.10.5 head-position singleton-fallback continues to apply; non-empty annotation = head-position scan is bypassed entirely and each declared subject with a postcondition receives its own `DLTested n` evidence record, all sharing one `pbt_witnesses` hash (per `docs/design/oblig-pbt-3-proposal.md` §11.1, pinned 2026-05-14). Empty `:subjects []` is rejected at parse time per S6. Duplicates are deduped.
- **`Property` record gains `propSubjects :: [Name]`.** Default `[]` preserves all existing constructions; both parsers (sexp `Parser.hs:pCheckBlock`, JSON `ParserJSON.hs:parseCheckDecl`) populate from the new keyword/field. `AstEmit.hs` emits `subjects` only when non-empty.
- **`pbtTrustWriteback`'s `processRun` branches on `propSubjects`.** When non-empty: fold over the subject list, emit one `csPost` `EvidenceRecord` per subject (with shared `PbtWitness`); subjects without a postcondition skip with an info diagnostic (S3); cross-module subjects key under their qualified path via the existing `qualMap` (S8). When empty: the v0.10.5 singleton-head-position path is unchanged.
- **Pacheco-Lahiri-Ernst overallocation mitigation: explicit annotation is the agent's consent to joint-evidence allocation.** The unannotated multi-callee diagnostic at `PBT.hs:pbtTrustWriteback` continues to refuse implicit lift; the new keyword opts in. Matches the JML `@testing`-per-method route over the conjoint-record alternative on schema-cost grounds (no `trust_report_version` bump, no `EvidenceRecord` reshape).

### Compiler — F-033 Body-Side Static-Eval Coverage Extension

- **`Contracts.hs:evalBuiltinApp` gains `unwrap` clauses.** `unwrap (Success v) → Just v`; `unwrap (Error _) → Nothing`; `unwrap _ → Nothing`. The `unwrap` builtin was already registered in `TypeCheck.hs:128` but had no static-evaluator clause — c02-shape property bodies dereferencing `(unwrap (balance …))` discarded universally on every pre-generated sample (`experiments/repair-loop/findings/postmortem-001-apparatus-validation.md` Addendum 17 §"F-033 / Evidence"). The Error path returns `Nothing` because the static evaluator has no panic value; the property body then discards on Error samples, which is the soundness-preserving conservative.
- **`PBT.hs:runQC` threads an `IORef`-counted body-discard counter through the `forAll` property.** `resultsToQCRun` consumes the count alongside QuickCheck's `Result`; on `GaveUp { numTests = 0 }` with `bodyDiscards > 0`, the new `gaveUpDiag` returns `"property body did not reduce on any sample (… likely unmodeled builtin or unreduced callee body in property body)"` instead of the previous misleading `"too many precondition failures"`. The `samples_run > 0` `GaveUp` arm keeps the precondition-failure phrasing.

### Compiler — F-034 Residual `evalBuiltinApp` Coverage on c02/c03-shape

- **Five missing clauses added at `Contracts.hs:evalBuiltinApp`** for builtins already registered in `TypeCheck.hs:88-119` but absent from the static evaluator: `list-empty` (returns `(nil)`), `list-prepend` (cons cell with head prepended; distinct from `list-append` which appends at the tail), `list-filter` (delegates to a new `filterCons` helper mirroring `mapCons`' fuel discipline), `int-to-string` (canonical decimal via `T.pack ∘ show`), `string-concat-many` (delegates to a new `stringConcatMany` helper walking a cons-chain of `LitString` literals; returns `Nothing` on non-literal elements so the property body discards). Addendum-18 surfaced these clauses as the proximate c02/c03 unblocker — every transfer-body dispatch through `map_get` / `map_insert` / `create_ledger` / `find-account` short-circuited to `Nothing` and the property discarded universally on every QuickCheck sample.
- **`list-head` / `list-tail` return-shape correctness fix.** The pre-F-034 clauses at `Contracts.hs:434-435` returned the raw element / tail, but the type-checker signatures at `TypeCheck.hs:100-101` are `[list[a]] -> Result a string` / `[list[a]] -> Result (list[a]) string`. Any property body matching `(match (list-head xs) ((Success v) ...) ((Error _) ...))` against the typed surface failed to reduce. Post-F-034: `list-head [hd, …]` → `(Success hd)`, `list-head [nil]` → `(Error "list-head: empty list")`; symmetric for `list-tail`. The fix is back-compatible with `(unwrap-or (list-head xs) default)` patterns widespread in `examples/*` (e.g., `life_json/world.ast.json`, `tictactoe_json_verifier/tictactoe.ast.json`) — `unwrap-or` of a `Success`-tag returns the payload exactly as before; the only behavior change is that `(match (list-head xs) ((Success v) ...) ((Error _) ...))` now reduces instead of discarding.
- **`filterCons` returns `Nothing` if the predicate fails to reduce to a `Bool` literal** — conservative behavior matching `mapCons` / `foldCons`. `stringConcatMany` returns `Nothing` on any non-literal cons element or unresolved structure. Both helpers share `applyLambda`'s existing fuel decrement.

### JSON-AST Schema — Additive `CheckDecl.subjects` Field

- **`schemaVersion` bumped `0.4.0 → 0.5.0`** (`ParserJSON.hs:41` and `docs/llmll-ast.schema.json`). `CheckDecl` now has an optional `subjects: [string]` field with `minItems: 1` — `additionalProperties: false` is preserved. Existing fixtures (~30 `.ast.json`) bumped mechanically; no shape changes elsewhere.
- **`trust_report_version` stays `1.1.0`.** No change to `EvidenceRecord`, `tier_profile_pre`/`tier_profile_post`, `DLTested n`, or `pbt_witnesses` shape. The per-subject records under `:subjects [f g]` reuse the same record kind; the shared `pbt_witnesses` hash is detectable by inspection.

### Test surface

- **640 Haskell tests + 37 Python tests** (up from 614 + 37 at v0.10.5). New: F-033 `unwrap` static-eval coverage (3 tests), F-033 PBTSkipped diagnostic classification (1 test), F-034 residual builtin coverage `F-034 evalBuiltinApp residual builtin coverage` block (10 tests covering `list-empty`, `list-prepend`, `list-filter` true/false predicates, `int-to-string`, `string-concat-many`, `list-head`/`list-tail` Success-wrap and nil-Error arms, end-to-end `list-filter ∘ list-head` chain), OBLIG-PBT-4 `:subjects` edge cases S1/S2/S3/S4/S5/S7/S9 (7 tests), OBLIG-PBT-4 parser surface sexp + JSON (4 tests), OBLIG-PBT-4 S8 cross-module in `ModuleSpec.hs` (1 test).
- **No solver-time delta.** PBT does not feed liquid-fixpoint; verifier surface unchanged. F-034 is body-evaluator-only.

### Empirical close-state

- **c01-shape (OBLIG-PBT-4) closed empirically** under the Addendum-18 re-probe: c01-subjects (5/5 tries) emit per-subject `DLTested(100)` records with shared canonical-body hash; 4/5 tries lift `tier_profile_post.tested = 1` (the remaining 1/5 missed on orthogonal near-threshold QC variance, not an OBLIG-PBT-4 defect). The 3 contracted callees with `asserted` upstream dependencies remain correctly bounded by R6d's `effective_level` body-faithful meet.
- **c02/c03-shape (F-034) closed empirically** under the Addendum-19 re-probe (2026-05-15) on the v0.10.6-shipped binary: c02 **10/10** and c03 **10/10** property×try records achieve `samples_run ≥ 1` (Addendum-18 candidate-binary baseline: 0/10 + 0/10). PBTPassed rates c02 9/10, c03 7/10; residual PBTSkipped on both shapes is near-threshold QC precondition-failure discard, orthogonal to F-034. Run: `experiments/repair-loop/runs/20260515T072155Z-reprobe-pbt45-c01c02c03-v0.10.6-shipped/`. Addendum-19 additionally validates the OBLIG-PBT-4 `:subjects` path on c02-shape end-to-end (c02-subjects 3/5 tries `tier_profile_post.tested ≥ 1`).

### What this does NOT close

- **Coverage-instrumented `evaluatedSamples` (QC `classify`/`cover`)** named in the original OBLIG-PBT-4 row is sequenced to a later iteration. The current ship is the linkage rule + diagnostic — sufficient for the c01 / c02 / c03 representative shapes per the Addendum-18 close-state above.
- **R6d `effective_level` upgrade past `asserted`** for `transfer` / `balance` on c01-shape requires upstream `find-balance` / `update-balance` to reach `contract_checked` or `tested` independently — body-faithful behavior, not a F-034 / OBLIG-PBT-4 defect.

---

## v0.10.5 — PBT Complex-Type Generators + PBT-to-Trust-Report Write-Back (2026-05-13)

### Compiler — PBT Complex-Type Generators + Static Evaluator Extensions (OBLIG-PBT-2, F-032)

- **`llmll test` now executes `(check ...)` blocks whose `for-all` bindings include complex types.** Properties bound at `TPair`, `TList`, `TResult`, `TSumType`, or `TCustom` aliases run end-to-end instead of skipping with the previous "Property contains non-constant expressions — requires full runtime evaluation" message. The prior `PBT.hs:generateValue` catch-all returned `LitInt` for any non-primitive type, producing type-incorrect samples the static evaluator could not reduce. Closes F-032 (`experiments/repair-loop/findings/postmortem-001-apparatus-validation.md` Addendum 16).
- **`generateValue` retyped** from `Type → IO Literal` to `TypeAliasEnv → Int → Type → IO Expr`. New cases for `TPair` (element-wise recurse, return `EPair`), `TList` (length-bounded cons-chain via `EApp "cons"/"nil"`), `TResult` (random tag + recurse), `TSumType` (random constructor choice + recurse, preferring nullary at depth-cap), `TCustom` (resolve via pure `expandAliasPure` against the `STypeDef`-extracted alias env, cycle-guarded). Recursion bounded by `maxGenDepth = 5` and `listMaxLen = 8`.
- **`evalExprStaticWith` extended for `EPair` and `ELambda`.** Pairs reduce element-wise; lambdas are first-class values for higher-order builtins. The extension also benefits contract VC constant-folding at `Contracts.hs:275, 286` — contracts that destructure pairs or fold lists now fold to constants before reaching liquid-fixpoint.
- **`evalBuiltinApp` signature refactored** from `Name → [Expr] → Maybe Expr` to `FuncEnv → Int → Name → [Expr] → Maybe Expr`. New §13 builtin reductions: `pair` / `first` / `second`; `cons` / `nil` / `list-head` / `list-tail` / `list-is-empty?` / `list-length` / `list-append`; `list-fold` / `list-map` (higher-order via new `applyLambda` helper, fuel-decremented); `unwrap-or` / `some` / `none` / `is-some`.
- **`maxFuel` raised 64 → 256.** Realistic agent emissions (`transfer → find-balance → list-fold → update-balance → list-fold` chains) exhausted the prior budget before reaching a terminal Bool. The 4× bump preserves the non-termination guard while giving real property bodies room to reduce.
- **`tryQuickCheck`'s `isSimpleType` whitelist removed.** The prior `TInt | TBool | TDependent _ TInt` gate excluded `TString` and every complex type. Replaced with universal fall-through routed through the broadened generator.
- **No syntax change, no schema bump.** Surface form of `(check ...)` and `(for-all [...] ...)` unchanged; `expectedSchemaVersion` stays `"0.4.0"`. The change is an evaluator-and-generator extension, not a language extension.
- **Empirical:** Phase-2 cell c01's solution lifts from `0/3 skipped` to `3/3 passed` under `llmll test`. Cells c02 and c03 still skip via QuickCheck-discard saturation (deeper unfold chains; orthogonal to type coverage).
- **Tests:** 10 new tests under two `OBLIG-PBT-2` describe blocks in `Spec.hs` covering (a) `TPair` / `TList` / `TResult` / `TSumType` / `TCustom`-alias PBT end-to-end, (b) recursive `STypeDef` depth-cap termination, (c) `evalExprStaticWith` `EPair` reduction, (d) `evalBuiltinApp` `first`/`second`, `list-fold` over a 3-element cons-chain, `list-length ∘ list-append`. 594 → 604 Haskell tests; 37 Python tests unchanged.

### Closed — F-033 PBT-to-Trust-Report Write-Back

- **Closed by OBLIG-PBT-3** (see below). `PBTPassed` results now lift the post clause of the singleton head-position contracted callee to `DLTested n` evidence; the `tier_profile.tested` slot of `--trust-report` reflects actually-passing `(check ...)` blocks through the new `tier_profile_post` per-clause aggregate (the per-function meet of pre and post is structurally unchanged).

### Compiler — PBT-to-Trust-Report Write-Back (OBLIG-PBT-3, F-033)

- **`llmll test` now writes `DLTested n` evidence to `.verified.json` on the post clause of the singleton head-position contracted callee inside every `PBTPassed` property body.** The linkage rule: a `(check ...)` block lifts at most one function — the unique `def-logic`/`letrec` reachable as an `EApp` operator inside `propBody` whose contract has a `post` clause. Multi-subject properties (≥2 contracted callees in head position) produce an informational diagnostic and no lift. `PBTFailed`, `PBTSkipped`, and `PBTError` runs contribute zero evidence. Closes F-033 (`postmortem-001-apparatus-validation.md` Addendum 16). Settled design + paired professor review at `docs/design/oblig-pbt-3-proposal.md` and `docs/archive/professor-reviews/oblig-pbt-3-review.md`.
- **New `pbt_witnesses` field on `.verified.json` evidence records** (`compiler/src/LLMLL/Syntax.hs:320-340`, `compiler/src/LLMLL/VerifiedCache.hs:70-110`). Each PBT-derived `DLTested` entry carries a list `[{hash, description}]` where `hash` is `sha256:` + 64 hex chars over a canonical s-expression serialization of the property body (`canonicalPropBodyHash` in `PBT.hs`; an exhaustive `Expr` walker independent of the incomplete `ObligationAssembly.exprToSExpr`). On read, `buildTrustReport` validates each evidence record's `pbt_witnesses` against the set of live property-body hashes and downgrades stale entries to `DLAsserted` with a per-clause diagnostic surfaced under `--trust-report`. Editing a property body invalidates its cached `DLTested`; deleting a property removes the lift. Back-compatible read of v0.10.4 sidecars (missing `pbt_witnesses` defaults to `[]`).
- **Within-channel `max` join across multiple properties on the same subject** (`mergePbtWriteback` in `PBT.hs`). When N passing `(check ...)` blocks cover the same `f`, `evaluatedSamples` aggregates as `max { samples(p) | p covers f }` and `pbt_witnesses` is the union deduplicated by `pwHash`. Distinct from `Module.mergeCS`'s cross-load lattice-monotonic merge, which is the GLB across sidecar-vs-base. Independence assumptions are not made — `sum` was considered and rejected.
- **Cross-module qualified sidecar keys.** A local `(check ...)` covering an imported function `f` from module `lib` writes the entry under qualified key `lib.f` in the local file's sidecar. The existing `collectAllContractStatus` build path at `TrustReport.hs:148-155` already merges by qualified name across the module cache, so the change is read-side compatible. The sidecar invariant statement is documented in `LLMLL.md §4.4.4`.
- **`trust_report_version` bumps `1.0.0 → 1.1.0`.** The JSON emit gains two new top-level fields parallel to `tier_profile`: `tier_profile_pre` and `tier_profile_post`. Each classifies functions by their per-clause effective level (clause own ER meeting the transitive-callee effective level); a function with `pre=DLAsserted` and `post=DLTested n` increments `tier_profile_pre.asserted` and `tier_profile_post.tested` rather than collapsing both into `tier_profile.asserted` via the diamond meet. The scalar `tier_profile` is unchanged in shape and continues to use the per-function meet — existing v1.0.0 consumers ignore the new fields. The schema at `docs/llmll-trust-report.schema.json` bumps to v1.1.0 additively. The source JSON-AST `expectedSchemaVersion` stays `"0.4.0"` — no source-schema delta; the parallel-track versioning between source `schemaVersion` and emit `trust_report_version` is the same separation established at v0.10.4.
- **`evaluatedSamples` semantics.** `DLTested n` records that `n` property-body evaluations reduced to `True`, with no evaluation reducing to `False`. This is a lower bound on assertions of the postcondition: under an implication-shape property `(if pre then post else true)`, samples for which `pre` fails count as `True` evaluations vacuously. Coverage-instrumented counts distinguishing genuine postcondition witnesses from vacuous evaluations are routed to **OBLIG-PBT-4** (new roadmap row). Disclosure in `LLMLL.md §5.1.1`.
- **PBT-Lift inference rule.** Formalised in the new `LLMLL.md §4.4.5` ("PBT-Derived Trust Evidence"), slotted between the existing §4.4.4 (Trust Report) and §4.5 (Suppression Governance). The rule's six side conditions (subject scoping, multi-subject suppression, skip/fail suppression, `PBTError` treated as skipped, interface laws excluded, `csPost`-only target) are stated alongside the within-channel `max` accumulation formula.
- **`:subject` keyword deferred to OBLIG-PBT-4.** The head-position-singleton fallback is the v0.10.5 mechanism; agents that wish to explicitly declare joint-evidence across multiple contracted callees in a single property will use `:subject f` (or `:subjects [f g]`) metadata in a future release. Existing canonical agent-emitted properties (`withdraw`, the F-032 closure cells, typical Phase-3 problem shapes) are already singleton and lift without annotation.
- **Design-divergence disclosure.** `LLMLL.md §4.4.1` documents the deliberate departure from Liquid Haskell (`Vazou et al., POPL 2014`) on admitting a statistical evidence channel into the trust-report partial order. The diamond-incomparability of `DLContractChecked` and `DLTested` at `Syntax.hs:355-357` (their meet is `DLAsserted`, not either) prevents agents from silently treating statistical evidence as logical.
- **Verification fragment unchanged.** No new SMT VCs, no new EMatch instantiations, no new Lean obligations. `aggregateTiers` is a pure traversal; `aggregateTiersPre` / `aggregateTiersPost` add two more passes. Sub-millisecond runtime delta on `llmll verify --trust-report`. Two file-I/O ops added to `llmll test` (`loadVerified` + `saveVerified`).
- **Tests:** 10 new tests under an `OBLIG-PBT-3 PBT-to-trust-report write-back` describe block in `Spec.hs` covering (E2) same function in multiple head positions lifts once, (E3) multi-subject diagnostic and no lift, (E5) per-clause split surfaces post-tested under asserted-pre meet, (E6) `DLVerified` preserved by `mergeCS` (non-degrading), (E8) cross-module subject keys writeback under qualified name, (E10) idempotent re-run dedups `pbt_witnesses` by hash, (E12) mixed pass/fail on same fn — passing run lifts and failing does not, (E13) edited property body downgrades stale `DLTested` to `DLAsserted`, (E14) deleted property downgrades stale `DLTested` to `DLAsserted`, (E15) v1.1.0 emit carries parallel `tier_profile_{pre,post}`. Pre-existing R6d JSON-emit test re-pinned at `trust_report_version: "1.1.0"`. 604 → 614 Haskell tests; 37 Python tests unchanged.

---

## v0.10.4 — R6d (Trust-Report Tier Profile + Harness Predicate) (2026-05-13)

### Compiler — Trust Report Tier-Count Aggregate (R6d)

- **`llmll verify --trust-report --json` now emits a `tier_profile` aggregate** alongside the existing `entries` / `summary` / `suppressions` blocks. The aggregate is a six-Int record `{verified, proved, contract_checked, tested, asserted, no_contract}` over per-function effective tier classifications (the same path that backs `summary` — `teEffectiveLevel`, falling back to the local meet of `tePre` / `tePost`). The repair-loop harness consumes this profile to compose its credibility predicate `Cred(R)` over LLMLL cells without ranking the diamond-incomparable `contract_checked ‖ tested` levels.
- **Diamond-meet semantics.** Per `LLMLL.md §4.4.1:344` and `Syntax.hs:356-357` (`evidenceMeet`), a function with `pre = contract-checked` and `post = tested` has effective level `asserted` (the diamond meet) and increments only `tpAsserted` — never both `tpContractChecked` and `tpTested`. Test `TP-3` in `Spec.hs` regression-locks this against future drift.
- **`proved` slot is structural-zero in v1.0.0.** No `DLProved` constructor exists in `DisplayLevel` today; the field is reserved for a future Lean-discharged tier so that a later compiler version can populate it without bumping the trust-report emit's major version. Documented in `docs/llmll-trust-report.schema.json`.
- **No spec change.** `LLMLL.md` gains no consumer-predicate prose; per R6d, `Cred` lives in `experiments/repair-loop/` harness docs, not in the language spec. The trust-report emit's pre-existing `summary` block is unchanged (consumers and the v0.3.2 substring tests at `Spec.hs:2253-2256` keep passing).
- **No verifier delta.** `aggregateTiers` is a pure traversal over the already-enriched entries; zero solver work, zero EMatch instantiations, zero new VC constraints, sub-microsecond runtime on a typical module.
- **Tests:** 5 new tests under a `v0.10.4 tier-count profile (R6d)` describe block in `Spec.hs` covering (a) empty → zero vector, (b) uniform-`verified`, (c) diamond-asymmetry (contract-checked / tested / mixed-meet → asserted), (d) mixed-tier, (e) JSON emit carries `trust_report_version` and structurally-valid `tier_profile`. 589 → 594 Haskell tests; 37 Python tests unchanged.

### Schema — Trust-Report Output Schema v1.0.0

- **New file `docs/llmll-trust-report.schema.json`** documents the trust-report JSON emit shape. Independent of the source JSON-AST schema (`docs/llmll-ast.schema.json`); the two surfaces are versioned separately because they describe different artifacts — parser input vs verifier emit. `$id`: `https://llmll.dev/schemas/v0.2/trust-report.schema.json`.
- **New `trust_report_version: "1.0.0"` field** on every `--trust-report --json` emit. Consumers can pin to this version to detect breaking shape changes; additive-only changes within a major version.
- **`tier_profile` shape**: six required integer fields (`verified`, `proved`, `contract_checked`, `tested`, `asserted`, `no_contract`), each with `minimum: 0` and `additionalProperties: false`. Schema explicitly documents the diamond-meet classification rule and the structural-zero `proved` slot.
- **Source JSON-AST `schemaVersion` is NOT bumped.** `expectedSchemaVersion` stays `"0.4.0"` (`ParserJSON.hs:41`). The change is to an emit-only output, semantically orthogonal to the source-input parser version; bumping the source schema would force ~22 `.ast.json` fixture rewrites for a change those fixtures do not touch. The R6d plan's `schemaVersion 0.4.0 → 0.5.0` line is honored by the new emit-side `trust_report_version` field instead — same versioning intent, smaller blast radius.
- **Round-trip semantics.** The trust-report JSON is emit-only; `ParserJSON.hs` and `AstEmit.hs` do not ingest or emit it. JSON-level re-decode (via `Aeson.Value`) preserves the field; full Haskell-side `TrustReport ↔ JSON` round-trip is N/A by design.

### Experiments — Repair-Loop Harness Cred(R) + H1 Bifurcation (R6d)

- **`experiments/repair-loop/README.md`** — new "Credibility predicate and the H1 split (R6d)" section. Defines `Cred(R) ≡ (|R| > 0) ∧ (n_asserted = 0) ∧ (n_no_contract = 0)` as the universal lattice-meet reading; defines the H1 bifurcation (H1-Correctness via testkit cross-target; H1-Assurance via per-target `tier_profile`, never scalarized cross-paradigm); states the no-scalarization discipline with citations to `LLMLL.md §4.4.1:344, :346-347` and `docs/design/language-comparison-experiments.md:27, :29-35`.
- **`experiments/repair-loop/scripts/run_repair_loop.py`** — `_count_bad_trust_tiers` drops `"asserted"` from `accepted_levels` (R6d universal tightening); docstrings cite §LT-A. `_run_turn` extracts `tier_profile` from the verify result and surfaces it at the per-turn `verifier.json` payload and the returned turn-record dict.
- **`experiments/repair-loop/scripts/evaluate_run.py`** — `_summarize_trust_report` extended with `tier_profile`, `cred`, `trust_report_version` fields (None on pre-R6d trust reports).
- **`experiments/repair-loop/manifest.phase2-calibration.json`** — `terminal_target.value` strings relabelled `"all-expected-contracts-verified-or-asserted"` → `"all-expected-contracts-above-asserted"`. Added `_r6d_note` field cross-referencing the README section.
- **Closes §LT-A / F-026 / F-027.** Re-probe of three Phase-2 cells (`runs/20260512T031938Z-matrix/`) under the v0.10.4-pre compiler: all three invert to `Cred=false`; `tier_profile` distinguishes c02 (6 asserted) from c03 (3 asserted + 3 no_contract). Full evidence: `experiments/repair-loop/findings/postmortem-001-apparatus-validation.md` Addendum 15. No new agent runs, no API spend.

### Experiments — Repair-Loop Matrix Runner

- **New `experiments/repair-loop/scripts/run_matrix.py`** (`5895792`) — matrix runner layered on top of `run_repair_loop.py` that enumerates cells in `(target × experiment × agent × attempt)` order, generates per-cell synthetic manifests, invokes the single-cell orchestrator, runs `evaluate_run.py` after each cell, and aggregates `matrix_report.json` / `matrix_summary.md`. Cells contiguous-by-`(target, experiment, agent)` for adapter-specific debugging.
- **`--resume-from-cell N`** — 1-based cell indexing required under the ~6.75h wall-clock ceiling of a 9-cell Phase-2 run at k=5 × 540s/turn. Required for crash recovery.
- **Pre-flight prereq checks** — per-agent `required_env` and `required_executables` declared in the manifest, validated before any cell launches; failures accumulated and surfaced in one pass.
- **`terminal_target_per_target` dispatch** — matrices spanning mixed verification surfaces (Phase 2 uses `trust-tier` for `llmll` and `all-pass` for Python / Go) resolve the per-target terminal target from a manifest-level map, falling back to the manifest's default `terminal_target` when a target is not in the map. This is the dispatch the R6d harness patch's predicate change rides on top of.
- **Harness README** (`experiments/repair-loop/README.md`) — new "Run a Matrix" and "Matrix-runner extensions" sections documenting the script and its manifest extensions.

---

## v0.10.3 — Cross-Module PBT + Spec Pedagogy (2026-05-12)

### Compiler — PBT Cross-Module Visibility (MOD-PBT-1, F-018)

- **`llmll test` now resolves cross-module `def-logic` in `(check ...)` bodies.** `doTest` switches from `loadStatements` (single-module) to `loadStatementsMulti`; a new `assembleTestStatements` helper in `LLMLL.PBT` concatenates each `(open path)`-targeted imported module's `SDefLogic` declarations ahead of the local statement list before invoking `runPropertyTests`. The PBT static evaluator's `FuncEnv` (built unchanged by `buildFuncEnv`) now sees imported function bodies, so a `(check ...)` block calling an imported function evaluates instead of silently skipping. Closes F-018 / F-030 (repair-loop Phase-2 postmortem Addendum 8 / Addendum 11); LLMLL cells whose `(check ...)` blocks depend on standard-prelude or sibling-module `def-logic` can now elevate trust-report entries from `asserted` to `tested` tier.
  > **Erratum (post-OBLIG-PBT-2):** The closing claim that MOD-PBT-1 elevates trust-report entries from `asserted` to `tested` was aspirational and is empirically not true — the PBT-to-trust-report write-back is tracked separately as F-033 / OBLIG-PBT-3 and remains unimplemented. MOD-PBT-1 does correctly make imported `def-logic` resolvable in `(check)` bodies; the FuncEnv-visibility claim is intact.
- **Filtering:** imported declarations are filtered by `meExports` (respects `(export ...)`) and by the optional restricted-open name list (`(open path (n1 n2))`). Imports come first, local stmts last — `Map.fromList` right-bias gives local-shadows-import semantics matching the type-checker's `(open ...)` resolution.
- **Scope boundaries (intentional):** Only `SDefLogic` is forwarded — imported `SCheck` blocks and `SDefInterface` laws stay with their owning module (`llmll test foo.llmll` should not silently run imports' own tests). Qualified-name resolution (`solution.plus-one`) remains out of scope per `LLMLL.md §8.5`; under the current flat-codegen runtime, qualified names do not resolve, and PBT honoring them would over-promise relative to the rest of the runtime. The existing `SLetrec` exclusion in `buildFuncEnv` (`Contracts.hs:306`) propagates to imports — recursive imported `def-logic` remains invisible to the static evaluator; tracked separately under PBT fuel-bound recursion handling.
- **Surface preserved:** `runPropertyTests :: [Statement] -> IO PBTResult` signature unchanged; the existing in-process Spec.hs tests calling it directly are untouched. JSON-AST schema unchanged (no shape changes). No solver-time delta (PBT does not feed liquid-fixpoint). `llmll test small.llmll` with no imports is identical to pre-patch behavior.
- **Tests:** 5 new tests in `ModuleSpec.hs` M-08 block — `M-08.1` full open, `M-08.2` restricted-open filter, `M-08.3` `meExports` filter (covers Risk #3 from approved plan), `M-08.4` local-shadows-import via `Map.fromList` right-bias, `M-08.5` fixture-driven end-to-end via `loadModule` against `test/fixtures/pbt-cross-module/{imported,local}.llmll`. 584 → 589 Haskell tests. 37 Python tests unchanged.

### Roadmap — Governing Criterion Disambiguation

- **Governing design criterion (roadmap header)** — Disambiguated the v0.10-era criterion text. Previous wording read as both (a) a design criterion for compiler deliverables and (b) a measurement stop-policy for empirical instruments. The revision preserves (a) as *progress toward one-shot correctness* and removes (b) by explicitly endorsing repair-loop experiments as a measurement regime. Resolves the internal contradiction between the roadmap header (line 6) and the v0.10 OBLIG-B success metric (line 98). Diagnosis and rationale folded into [`experiments/methodology.md`](experiments/methodology.md) (the original `docs/design/empirical-methodology.md` was a redirect stub, since retired). Unblocks repair-loop experiment design under `experiment-lead`.

### Spec — Naming Conventions

- **`LLMLL.md` §2.5 (new)** — Documents the canonical naming conventions for LLMLL identifiers: kebab-case for functions / variables / parameters; PascalCase for type names and constructors; trailing `?` for boolean predicates; kebab-case for keywords and builtins; lowercase for reserved identifiers (`result`, `unit`, `true`, `false`). Includes a cross-language API translation note: when a language-neutral problem statement uses snake_case or camelCase, the LLMLL solution transliterates to kebab-case. Pedagogical only — the grammar continues to accept both `_` and `-` per §2.1's identifier character class; the convention is stylistic, not syntactic. Closes the gap surfaced by the repair-loop Phase-2.0 probe where agents emitted parseable but non-idiomatic identifiers and consumed evaluation budget on style drift.

### Spec — Match-Arm Surface Form Correction

- **`LLMLL.md` §3.3 / §9 / §13.5** — Corrected the informal `match` examples to use the canonical wrapped match-arm form `(pattern body)`. The §17 grammar (`match-arm = "(" pattern expr ")"`), the parser, the AST (`EMatch Expr [(Pattern, Expr)]`), the JSON-AST schema (`MatchArm = { pattern, body }`), and every shipping example in `examples/` already use the wrapped form; only the informal prose at three sites had drifted to the sibling form `(pattern) body`. Documentation-only — grammar, parser, schema, and examples are unchanged. Closes the spec self-inconsistency surfaced by the repair-loop Phase-2.0 probe (Gemini reproduced the drifted §3.3 surface and hit a parse failure at the first arm body; bisection in [`experiments/repair-loop/findings/postmortem-001-apparatus-validation.md`](experiments/repair-loop/findings/postmortem-001-apparatus-validation.md) Addendum 10).

### Spec — Unit-Payload vs Nullary Constructor Pedagogy

- **`LLMLL.md` §3.2 / §3.3** — Resolved the spec/compiler drift on unit-payload vs nullary sum-type constructor declarations. The §3.3 prose at lines 203/216 promised that variants declared `(| Ctor unit)` would accept the elided match form `((Ctor) body)`; the typechecker at `compiler/src/LLMLL/TypeCheck.hs:1185-1208` treats declared `unit` as a payload type like any other and requires arity-1 match. The forms are observably distinct in the generated Haskell (per Semantic Anchor A in [`docs/design/verification-debate.md`](docs/design/verification-debate.md)): `(| Red unit)` codegens to `data Color = Red () | …` (a constructor of type `() → Color`) while `(| Red)` codegens to `data Color = Red | …` (a constructor of type `Color`) — see `compiler/src/LLMLL/CodegenHs.hs:413-419`. The spec moves to match the compiler: §3.2's "no literal" claim for `unit` is corrected to identify `()` as the unit literal; §3.3's introductory `Color` example is recast in truly-nullary form `(| Red) (| Green) (| Blue)`; §3.3's pattern-arity prose is rewritten so that declared arity equals match arity uniformly; the unit-payload form `(| Variant unit)` is preserved by the parser as a distinct AST shape, but **discouraged** for new declarations (reserved for the narrow case of Haskell-codegen interop where a downstream consumer destructures the `Variant ()` shape directly). Documentation-only — grammar, parser, AST, typechecker, codegen, and schema are unchanged. Discharges the adjacent drift finding surfaced in the R5a doc-lead pass (commit `ecdf42f`); fully closes F-024 acceptance.

---

## v0.10.2 — Soundness Blockers + Diagnostic Surface (2026-05-10)

### Compiler — Delegate Fallback Typechecking

- **`?delegate (on-failure e)`** — fallback expression now typechecked against delegate return type (`TypeCheck.hs` `inferHole HDelegate`). Previously parsed but never visited; ill-typed fallbacks (`Result.Error DelegationError`, unknown identifiers) silently passed.
- **`?delegate-async on_failure`** — rejected at parse time (`ParserJSON.hs`). Use sync `?delegate` with `on-failure`, or handle errors after `(await ...)`.
- **`emitHole (HDelegate spec)`** — codegen routes through fallback when present (`CodegenHs.hs`). Previously emitted unconditional runtime `error`, masking PBT-eligible properties.
- **EHole unification** — `checkExpr` for hole expressions now unifies inferred against expected type. Previously discarded.

### Compiler — PBT Discard Semantics

- **Unevaluable samples** — `runQC` returns `QC.discard` on samples that do not reduce to `LitBool` (`PBT.hs`). Previously defaulted to `True`, silently counting as success.
- **FuncEnv-driven evaluation** — `runPropertyWith` threads a top-level function environment built from `def-logic` statements; property bodies reach user-defined logic.
- **Static evaluator expansion** — `evalExprStaticWith` adds fuel-bounded recursion (`maxFuel = 64`), `ELet`, `EMatch` with pattern bindings, `EHole HDelegate` fallback, and `ok`/`err`/`is-ok` builtin evaluators (`Contracts.hs`). `ok` and `err` canonicalize to internal `Success` and `Error` tags so match patterns evaluate correctly. Pure surface; no VC generation impact.
- **Operator coverage** — `evalOp` now handles `=`/`!=` on `Bool` and `String`.
- **`evalContract` isolation preserved** — contract evaluation continues to use the backward-compatible `evalExprStatic` wrapper (empty `FuncEnv`), so contracts do not silently inline `def-logic` calls.
- **Async PBT limitation** — `?delegate-async` and `await` remain unevaluable in the static evaluator; check blocks involving them report `PBTSkipped`. The async error-recovery path is exercised at runtime via `Result` matching, not compile-time evaluation.

### Compiler — Diagnostic Surface

- **`llmll check` text mode** — accumulated warnings now render on success (`Main.hs doCheck`). Previously suppressed.
- **Dotted fn warning** — `(EApp "Foo.Bar" ...)` warns at typecheck time (`TypeCheck.hs inferExpr`). Suggests `(open <module-path>)` and bare names.

### Schema — JSON-AST v0.4.0

- **`schemaVersion` const bumped 0.3.0 → 0.4.0** to signal new identifier-shape regex constraints. Compiler enforces via `expectedSchemaVersion`. 20 example fixtures updated to match.
- **`ExprApp.fn` regex** — `^[^.]+$`. Permissive on purpose: legal `app.fn` values include operator identifiers (`+`, `-`, `<=`, etc.). Stricter identifier-only validation can land in a future release via `oneOf`.
- **`ExprQualApp.qual_fn` regex** — `^[A-Za-z_][A-Za-z0-9_?\\-]*(\\.[A-Za-z_][A-Za-z0-9_?\\-]*)+$`. Enforces ≥ 1 dot per `LLMLL.md §12` EBNF.

### Spec — Delegate Fallback Typing (§11.2)

- **§11.2 inference rules** — added `?delegate @A "desc" -> T (on-failure e) ⊢ T` with side condition `Γ ⊢ e : T`, alongside the existing rules for `?delegate-async` and `await`. Formalizes the rule the v0.10.1 typechecker silently dropped.
- **§11.2 example fix** — login-handler `(on-failure ...)` example now uses `(err DelegationError)`. The previous `(Result.Error DelegationError)` form was never a registered constructor name and only typechecked via the v0.10.1 fallback dropthrough.

### Spec — Result Patterns and `?proof-required` (§13.8)

- **Three-layer Result rule** — Result values have three distinct surfaces: *construct* via `(ok x)` / `(err e)`, *match* via `Success` / `Error` patterns, *test* via `(is-ok x)`. `Result.Ok` and `Result.Error` are not registered constructor names.
- **`?proof-required` pedagogical hook** — Result-returning function contracts whose postconditions are asserted but unverifiable (delegated calls, nonlinear arithmetic, map invariants) should be marked `?proof-required`. Cross-references the formal definition at §6.

### Spec — JSON-AST Identifier Regex (§12)

- **Grammar Key Rule 9** — JSON-AST identifier shape is schema-enforced via `^[^.]+$` on `ExprApp.fn` (no dots; permissive on character class to admit operator identifiers) and the full identifier regex on `ExprQualApp.qual_fn` (≥ 1 dot, identifier character class per §2.1).

### Spec — Identifier Character Class (§2.1)

- **§2.1 identifier character class** — `?` is now documented as accepted in identifier-terminal position only (e.g., `done?`, `string-empty?`, `is-game-over?`). Documents pre-existing compiler behavior since v0.1.

### Spec — PBT Outcome Reporting (§5.1)

- **§5.1 outcomes table** — `check` blocks report one of `pass` / `fail` / `skip`. A `skip` is not a `pass`. Property bodies that fail to reduce to a literal Bool (delegate without fallback, command constructors, await) are reported `skip` and contribute zero trust evidence.

**Tests:** 584 Haskell (was 570; +14 across delegate / PBT / diagnostic / evalContract isolation), 37 Python.

---

## v0.10.1 — Patch Release (2026-05-09)

### Compiler — `llmll version` Command

- **`llmll version`** — New subcommand prints compiler version and exits. Supports `--json` for `{"version":"…"}` output.
- **`llmll --version`** — Top-level `--version` flag (via `optparse-applicative` `infoOption`) as an alternative to the subcommand.

### Compiler — Exit Code Fixes

- **`doCheck` / `doHoles` exit code** — `llmll check` and `llmll holes` now exit with rc=1 on parse errors. Previously they returned rc=0 silently on `Left ()` (parse failure), while every other command handler correctly used `exitFailure`. `llmll typecheck` (non-sketch) is also fixed since it delegates to `doCheck`.
- **`--help` exit code** — All 17 subcommands (14 top-level + 3 hub sub-subcommands) now respond to `--help` with exit 0. Previously `llmll build --help` treated `--help` as an unknown argument and exited non-zero.

### Compiler — Type Alias Resolution Overhaul

- **Structural + transitive `expandAlias`** — `expandAlias` was non-structural (only resolved outermost `TCustom`) and non-transitive (stopped after one alias hop). Both defects blocked constructor-injection on aliased ADTs. Rewritten to recursively traverse composite type structures (`TList`, `TMap`, `TResult`, `TPair`, `TPromise`, `TFn`, `TSumType`, `TDependent`) and chase alias chains transitively. Per-traversal `Set` cycle guard prevents divergence on cyclic aliases.
- **`compatibleExpanded` helper** — Expand-then-compare helper migrated to 13 direct `compatibleWith` call sites. `checkPattern` now expands scrutinee type at entry, fixing `PConstructor "pair"` against alias-of-`TPair` and `"Success"`/`"Error"` against alias-of-`TResult`.
- **Unsound `TCustom`/`TSumType` bridge removed** — `compatibleWith` no longer treats any `TCustom` as compatible with any `TSumType`. All call sites now expand before reaching `compatibleWith`.
- **Alias-cycle diagnostic** — Alias cycles (e.g., `(type A B) (type B A)`) are detected at `checkStatements` time via graph-based DFS reachability. `TSumType` payloads exempted (recursive ADTs are legitimate self-reference, not alias cycles).
- **Diagnostic preservation** — `unify` reports original (unexpanded) types in diagnostics, preserving alias names like `Color` instead of `(Red | Green | Blue)`.
- **Known regression:** `structuralUnify` (EApp path) shows expanded leaf types in diagnostics instead of alias names. Follow-up needed.

### Compiler — Async Delegate Normalization

- **`?delegate-async` return type** — `return_type` is now the inner type `T`, not `Promise[T]`. The compiler wraps it in `Promise[T]` automatically. A top-level `Promise[...]` in `return_type` is stripped as a legacy compatibility measure. `Promise[Promise[T]]` is a parse error. Both `Parser.hs` and `ParserJSON.hs` updated. Inference rules added to LLMLL.md §11.2.
- **ADT constructor registration** — `collectConstructors` extracts `TFn` bindings from `TSumType` variants. Dual-stage collision detection: Phase 1 catches intra-module duplicate constructors; Phase 2 catches constructor/function shadowing (skips `TCustom` type-namespace entries).
- **`withFunctionContext` combinator** — Structural scope cleanup for `tcCurrentFn` and `tcIsLetrec`, mirroring `withTaggedEnv`. Eliminates false-positive self-recursion warnings on subsequent `SCheck`/`SDefInterface`/`SExpr` statements.

### Compiler — DelegationError Type Normalization

- **`resolveNamedType`** — Both `ParserJSON.hs` and `Parser.hs` now map well-known type names (`"DelegationError"`) to their built-in `Type` constructors (`TDelegationError`) instead of falling through to `TCustom`. Closes the `TCustom`/`TDelegationError` mismatch that caused false type errors when JSON-AST programs used `DelegationError` in type annotations.
- **Disambiguated type mismatch diagnostic** — When `typeLabel` produces identical strings for structurally different types (e.g., `TDelegationError` vs `TCustom "DelegationError"`), the error now appends the internal constructor tag: `expected DelegationError (built-in), got DelegationError (named)`.

### Compiler — Build Fix

- **macOS case-insensitive path warning suppressed** — Moved executable `Main.hs` from `src/` to `app/` so the executable component builds in a separate directory from the library's `LLMLL/` modules. Added `-optP-Wno-nonportable-include-path` and `-optc-Wno-nonportable-include-path` to executable `ghc-options`.

**Tests:** 570 Haskell (was 556; +14 alias resolution tests), 37 Python (unchanged).

---

## v0.10.0 — Obligation-Guided Agent Coding (2026-05-03)

### Compiler — Structured Obligation Reports

- **OBLIG-0** — Design spec for obligation report JSON schema (schema version `0.10.0`). Three channels: type, contract, trust. `EMatch` branch obligations. Repair suggestion generation. Benchmark suite definition.
- **MOD-1** — Cross-module `ContractEnv`: `meContracts` field in `ModuleEnv` (`Syntax.hs`). Populated from `buildModuleEnv`. `ctVerifiedHash` staleness guard for imported `.verified.json` files.
- **OBLIG-1** — Enriched typed holes: `CheckoutToken` extended with contract preconditions, postcondition goal, path condition, assumption set, source/evidence hashes. New fields emitted unconditionally on `llmll checkout`.
- **OBLIG-2** — Goal-state display: `ObligationAssembly.hs` module. Structured JSON obligation report for each `?hole`, each unproven contract clause, and each failed call-site precondition. `assembleReport` top-level entry point. `--obligation-report` flag on `llmll verify`. `GuardClassifier.hs` extracted from `FixpointEmit.hs` for shared guard classification.
- **OBLIG-3** — `EMatch` branch obligations: `assembleBranchObligations` (two-pass, parent-id linkage). `patternBindings` (recursive on `PConstructor`). `lookupConstructorPayload` with alias-aware type resolution. `inferScrutineeType` for `EVar` and `EApp` (builtin lookup via `builtinEnv`). Branch-specific fields (`parent_id`, `branch_index`, `constructor`, `bindings`) conditionally emitted.
- **OBLIG-4** — Repair suggestions: `generateCandidates` in `ObligationMining.hs` (O(n²) bounded arithmetic search, cap-8). `CandidateExpr` type. Pre-filtered via `isIntLike` with `AliasMap` (avoids double-filter bug on dependent type aliases like `PositiveInt`). Wired into `mkHoleObl` for int-typed holes.
- **OBLIG-5** — Repair loop integration: `llmll verify --obligation-report` emits reports end-to-end via `assembleReport`. Trust report records final evidence.
- **OBLIG-B** — Benchmark suite: 3 benchmark programs (`b1-withdraw`, `b3-safe-first`, `b5-double`) with golden tests. Fingerprint stability test (INT-1). 11 new Phase 4 tests.

### Compiler — Function Lists (spec §8)

- **`assembleFunctionLists`** — Contracted functions (user-defined with compatible return types) and available builtins (non-WASI, type-compatible) with cap-8 and truncation signals. `isTypeCompatible` with `AliasMap`, `TVar` wildcard matching, `TDependent` refinement stripping, `TCustom` alias resolution, and `Result` unwrapping. `trustLabel` from `effectiveLevel`. Builtin params populated from `TFn` with positional names.

### Compiler — Bug Fixes

- **F7: Path condition key mismatch** — `holeName` carries `?` prefix; `collectHoleGuards` emits without. Fixed by stripping `?` prefix in consumer. Path conditions were silently empty for all hole obligations.
- **F6: `inferScrutineeType` for `EApp`** — Extended to look up `builtinEnv` for function return types (e.g., `list-head` → `Result[a, string]`). Previously returned `Nothing` for all non-`EVar` scrutinees.
- **R2: `resolveType` strips `TDependent`** — `lookupConstructorPayload` now correctly resolves dependent type aliases when looking up constructor payload types.

### Compiler — New Modules

- **`ObligationAssembly.hs`** — 800+ line module. Obligation report assembly pipeline: hole obligations, branch obligations, constraint obligations, function lists, repair suggestions, JSON encoding. Schema version `0.10.0`.
- **`GuardClassifier.hs`** — Extracted from `FixpointEmit.hs`. Shared guard classification logic used by both the `.fq` emitter (verification) and `ObligationAssembly` (presentation).

### Benchmarks

- **`examples/benchmarks/b1-withdraw.llmll`** — `withdraw` with `PositiveInt` alias (tests type-aware candidate generation)
- **`examples/benchmarks/b3-safe-first.llmll`** — `safe-first` with `EMatch` on `list-head` (tests branch obligations)
- **`examples/benchmarks/b5-double.llmll`** — `double` with single int param (tests `(+ n n)` candidate)

**Tests:** 556 Haskell (was 452; +104 across Phases 1–4), 37 Python (unchanged).

---

## v0.9.0 — Compositional Verification (2026-05-01)

### Compiler — Assume-Guarantee Reasoning

- **COMP-1** — `CallVC` constructor on `BodyVC` ADT (7 record fields: callee, args, preObligation, postAssumption, resultVar, resultSort, continuation). `ContractEnv` type and `buildContractEnv` for extracting contracts from statements. `applySubst` (capture-free predicate substitution, 7 `FQPred` cases). `isConstructorDependent` (TCB guard for constructor-dependent postconditions, Issue 2). `bodyToPredM` extended with `ContractEnv` + `Set Name` (SCC set). EApp case with three-way pre distinction (Issue 1): no pre → pass, translatable pre → obligation, untranslatable pre → fallback. `CallVC` returned directly from EApp (Issue 3). SCC guard removed — callers may use assume-guarantee against recursive functions' contracts (Issue 4). `ELet` continuation threading for `CallVC` RHS. `flattenBodyVC`/`countPathsBounded`/`prependLB` extended for `CallVC`. `collectCallPreObligations` helper. Call-pre constraint emission with PROVE polarity. `EmitResult.erCallPreFns` tracking.
- **COMP-2** — SCC detection via `Data.Graph.stronglyConnComp` in `emitFixpointWith`. Exported `buildCallGraph` from `HoleAnalysis.hs`. Recursive functions excluded from body VCs.
- **COMP-3** — `EMatch` on `Result a e` (two-path encoding): `classifyResultArms` (detects Success/Error two-arm pattern in either order), synthetic boolean guard `_match_success_N`, sort derivation from `ContractEnv` `TResult okType errType` (Issue 5), `setCallVCContinuation` for EMatch-over-call desugaring (§5.4). Falls back on non-Result types, non-two-arm matches, complex scrutinees.
- **COMP-5** — `call-pre:` tag in `ConstraintOrigin` (`DiagnosticFQ.hs`). `toDiag` mapping for UNSAFE call-site preconditions. Structured error: "call-site precondition of '<callee>' not satisfied in '<caller>'." Call-pre obligation reporting in verify output.
- **COMP-6** — `--strict-verified-core` CLI flag: hard-error if any function is in `erBodyFallback`. JSON and text error output with fallback function names.
- **COMP-T** — 18 COMP golden tests: `applySubst` (4), `isConstructorDependent` (3), `bodyToPredM` with `ContractEnv` (4), `collectCallPreObligations` (2), end-to-end call-pre emission (1), `EMatch` on Result (4). **452 total tests passing** (434 → 452).

### Design

- **COMP-0** — Design spec `docs/archive/shipped-design-specs/comp-0-spec.md` produced and approved (Rev 2). Five soundness issues resolved: three-way pre distinction, constructor-dependent postcondition guard, CallVC direct return, SCC guard relaxation, sort derivation from ContractEnv.

### v0.10 Carryover

> **v0.10 carryover:** COMP-5 structured repair suggestions, 13 remaining golden tests (stripping regression, trust degradation chains), and `--strict-verified-core` post-solver enforcement are deferred to v0.10 (Obligation-Guided Agent Coding).

---

## v0.8.1b — Evidence Model Refactor (2026-05-01)

### Compiler — DisplayLevel Diamond Lattice

- **EVID-1** — `VerificationLevel` total order replaced with `DisplayLevel` partial-order diamond lattice in `Syntax.hs`. Four tiers: `DLVerified > DLContractChecked ∥ DLTested > DLAsserted`. `EvidenceRecord` type (display level + body-faithful flag + source provenance). `AssumptionKind` taxonomy (`AKRuntimePrimitive`, `AKCompilerBuiltin`, `AKExternalOpaque`). `ContractStatus` restructured to `csPre`/`csPost` (`Maybe EvidenceRecord`) + `csAssumptions`. `evidenceMeet` (GLB), `evidenceCovers` (partial-order check), `isSolverBacked`, `isVerifiedLevel`, `dlLabel`.
- **EVID-1a–1e** — Consumer modules updated: `ProofCache.hs`, `AstEmit.hs`, `TypeCheck.hs`, `Parser.hs`, `ParserJSON.hs`, `ObligationMining.hs`.
- **EVID-2** — `VerifiedCache.hs` rewritten with `EvidenceRecord`/`DisplayLevel`/`AssumptionKind` JSON serialization. Hard break: old `.verified.json` files return empty map (no backward compatibility).
- **EVID-3** — `TrustReport.hs` refactored: `TrustEntry` uses `Maybe EvidenceRecord`, `TrustSummary` has 6 fields (adds `tsContractChecked`), `effectiveLevel` uses `evidenceMeet`.
- **EVID-4** — `SpecCoverage.hs` refactored: `FunctionEntry` uses `Maybe DisplayLevel`, summary adds `csVerified`/`csContractChecked'`.
- **EVID-5** — `Contracts.hs` updated: `filterContracts` checks `isVerifiedLevel && erBodyFaithful`.
- **EVID-6** — `Module.hs` updated: `mkCS`/`mergeCS` use `EvidenceRecord` and `evidenceCovers`.
- **EVID-7** — `Main.hs` updated: verify pipeline builds `EvidenceRecord (DLVerified "liquid-fixpoint") True`.
- **FixpointEmit.hs** — `erBodyFaithful` renamed to `erBodyFaithfulFns` to resolve name collision with `EvidenceRecord.erBodyFaithful`.
- **EVID-T** — All 322 tests updated and passing. Replaced `vlTier`/`trustCovers` tests with `evidenceCovers`/`evidenceMeet` lattice tests.

### Design

- **EVID-0** — Design spec `docs/archive/shipped-design-specs/evid-0-spec.md` produced and approved.

---

## v0.8.1a — Documentation Boundary Clarity (2026-04-30)

### Spec (LLMLL.md)

- **RENAME-1** — §3.4 heading renamed from "Dependent Types (Logic-Constrained)" to "Refinement Type Aliases (Logic-Constrained)." Removed prose comparing LLMLL to Idris or Lean for dependent elimination. LLMLL has no dependent types — the terminology now accurately reflects refinement-like annotations.
- **MATRIX-1** — §5.3.5 per-construct verification matrix added (17 rows × 6 columns: typechecked, runtime-asserted, SMT contract, SMT body-faithful, QuickCheck, fallback).
- **BOUNDARY-2** — Integer overflow model gap documented in §5.3.5: Z3 reasons over mathematical integers; Haskell `Int` wraps at 2⁶³.

### README.md

- **MATRIX-2** — Compressed verification matrix added to "Verification Boundary" section.

### One-Pager (docs/one-pager.md)

- **RENAME-2** — Removed Idris/Lean comparison; reworded to "Inspired by refinement types (Liquid Haskell)."
- **MATRIX-3** — Compressed verification matrix added.
- **BOUNDARY-1** — Status section now leads with the QF-LIA boundary sentence.
- **ROADMAP-2** — What's Next table updated with v0.8.1a/v0.8.1b/v0.9 milestones.

### Roadmap (docs/compiler-team-roadmap.md)

- **ROADMAP-1** — Roadmap restructured with v0.8.1a/v0.8.1b/v0.9 plan. Feature freeze policy. Critical path diagram updated. Old v0.8.1 items moved to parking lot.

**No code changes. No test changes. Zero regression risk.**

---

## v0.8.0 — Faithfulness Core (2026-04-29)

### Compiler — Body-Faithful Verification Conditions (BODY-VC)

- **BODY-VC-1** — `bodyToPred` for QF-LIA fragment. Encodes `ELet` (with alpha-renaming for shadowed variables), `EIf` (path-sensitive constraint emission), and linear arithmetic as `.fq` body verification conditions. Conservative `Nothing` fallback for unsupported constructs (`letrec`, `EMatch`, non-linear expressions). Path limit: >4096 execution paths trigger fallback with diagnostic warning.
- **BODY-VC-2** — Wired into `emitFnConstraints` in `FixpointEmit.hs`. When `bodyToPred body = Just bvc`, flattened paths emitted as `.fq` constraints. EIf-in-let hoisting (conservative single-path). Early-exit fix: replaced no-op `when (cond) $ return ()` with actual `if/then/else/do` short-circuit.
- **BODY-VC-3** — Postconditions marked body-faithful per function via `csPostBodyFaithful` field in `ContractStatus` (`Module.hs`). `Contracts.hs` strips postcondition assertions only when `VLProvenSMT ∧ csPostBodyFaithful = True`. Preconditions never stripped.
- **BODY-VC-T** — 25 new tests: T01–T05 (body-VC golden), F01–F03 (fallback), N01–N04 (negative), P01–P04 (parsed-source), T11 (SUPP-DEBT), plus SortEnv, Parens, Flatten, E08 edge cases.

### Compiler — Soundness Fixes

- **EOp delegation** — `exprToPred (EOp op args) = exprToPred (EApp op args)`. The parser emits `EOp` for operators, but `exprToPred` only handled `EApp`. Contract clauses using operators were silently skipped and falsely marked as proven.
- **`!=` operator** — Added to both `exprToPred` and `lookupPredOp` (parser emits `!=`, not `/=`).
- **Clause-level emission tracking** — `erEmittedPre`/`erEmittedPost` fields in `EmitResult`. Sidecar generation checks membership before promoting to `VLProvenSMT`; skipped clauses remain `VLAsserted`.

### Compiler — Spec Coverage

- **SUPP-DEBT** — `spec_coverage` (contracted / total) and `suppression_debt` (suppressed / total) fields added to `--spec-coverage` JSON output alongside existing `effective_coverage`.

### Compiler — Verify JSON

- Verify JSON output now includes `body_faithful` and `body_fallback` metadata per function.

### Spec (LLMLL.md)

- §0.1 — Semantic foundation section added
- §4.4.1 — Body-faithfulness caveat added to trust tier documentation
- §5.3.2 — SUPP-DEBT fields documented in spec coverage JSON example
- §5.3.4 — New section: Body-Faithful Verification (BODY-VC coverage, path limit, two-tier status)

**Tests:** 320 Haskell (was 294; +26), 37 Python (unchanged).

---

## v0.7 — Hardening (2026-04-29)

### Compiler — Builtin Hardening

- **BUILTIN-2** — `string-char-at` negative index guard. Added `i >= 0` check to prevent negative index crash. The function now returns `""` for out-of-bounds indices in both directions.
- **BUILTIN-1** — `regex-match` → POSIX ERE via `regex-tdfa`. Replaces the `isInfixOf` stub with proper regex matching. Invalid patterns are caught via `unsafePerformIO`/`try`/`evaluate` and return `False` (total function). `PREAMBLE COMPROMISE` comment explains the `unsafePerformIO` usage. Import cleanup: removed `isInfixOf`; added `evaluate`, `Text.Regex.TDFA`, `System.IO.Unsafe`. Added `regex-tdfa` to generated `package.yaml` dependencies.

### Compiler — Do-Block Diagnostic

- **DO-1** — Discarded command warning. Intermediate `TCustom "Command"` types in `do`-blocks now emit a warning: "current codegen discards" (blames codegen limitation, not user). Step 0 now binds `cmd0` (was `_`); recursive steps bind `cmdTy` (was `_`). `checkDiscardedCommand` helper in `TypeCheck.hs`. Warning-only in all modes; hard error deferred to v0.8 (DO-2: `(discard expr)`).

### Compiler — Trust Model Refinement

- **TRUST-2a** — `VLProvenSMT` constructor + `Ord` instance removal. Added `VLProvenSMT { vlSMTSolver :: Text }` to `VerificationLevel`. Removed `instance Ord VerificationLevel` — replaced with explicit preorder helpers: `trustCovers` (was `>=`), `trustMin` (was `min`), `isProvenLevel`, `vlProverName`. All four helpers exported from `Syntax`. 10 consumer files updated: `TypeCheck.hs`, `TrustReport.hs`, `SpecCoverage.hs`, `AstEmit.hs`, `Contracts.hs`, `VerifiedCache.hs`, `Main.hs`, `ProofCache.hs`, `Module.hs`. `.verified.json` serializes as `"proven-smt"`.

### Spec (LLMLL.md)

- §4.4.1 — Trust tier vs. evidence provenance note + body-faithfulness caveat added
- §13.6 — `string-char-at` and `regex-match` documentation updated

### Discovered Issues (not in original plan)

- **Module.hs `mergeCS`** — Used `max` on `VerificationLevel`, which depended on the removed `Ord` instance. Fixed with explicit `vlTier` comparison. Not caught in the original 18 planned consumer sites because it appeared in the module loader.
- **Spec.hs `compare` tests** — Five tests tested the `Ord` instance via `compare`. Replaced with `vlTier`/`trustCovers`/`isProvenLevel` tests. Added `VLProvenSMT` tier equality test.
- **Spec.hs round-trip test** — Used `VLProven "liquid-fixpoint"` which now serializes as `"proven-smt"`. Updated to `VLProvenSMT`.

**Tests:** 294 Haskell (was 289; +5 trust-tier tests), 37 Python (unchanged). Build compiles cleanly (`stack build`, no `Ord` residuals).

---

## Pre-v0.7 Hygiene (2026-04-28)

> Items from the external consultant review (2026-04-28). Not a versioned release — these are test drift and documentation drift fixes applied before starting v0.7.

### Test — TEST-DRIFT

- **Python dry-run fixture updated** — Stub plan in `agent.py:385` defined `stub-fn` with no contract, which was rejected by the spec-quality gate added in v0.6.0. Fixture now includes a minimal `(post true)` contract.

### Spec (LLMLL.md) — DOC-DRIFT

- **§5.3.2 JSON example reconciled with `SpecCoverage.hs`** — The spec described `suppression_debt` and `spec_coverage` as current JSON fields, but `SpecCoverage.hs` only emits `effective_coverage`. Fixed: JSON example updated to match the actual `summary`/`entries`/`laws`/`warnings` envelope emitted by `formatCoverageJson`. Deferred fields (`suppression_debt`, `spec_coverage`) moved to a "Planned (v0.8.0, SUPP-DEBT)" note.

---

## v0.6.3 — Trust Model Fixes (2026-04-26)

### Compiler — Trust Model Hardening

Seven critical bugs from the v0.6.3 engineering audit, all resolved:

- **BUG-1** — `result` removed from precondition environments (`TypeCheck.hs`). `result` in a `pre` clause is now a hard error per §4.3. `exprContainsVar` helper validates recursively.
- **BUG-2** — Contract instrumentation wired into `doBuild`/`doBuildFromJson`/`doRun`. `instrumentContracts` replaces `applyContractsMode` in the build pipeline. `CodegenHs.hs` lowers `(runtime-error msg)` to Haskell `error msg`.
- **BUG-3** — Transitive trust closure (`TrustReport.hs`). Fixed-point iteration via `transitiveClose` computes the full reachable set. `enrichEntry` recomputes drifts and `teEffectiveLevel = min(self, transitive deps)`. JSON output includes `effective_level`.
- **BUG-4** — Typecheck gate before codegen. `typeCheckStrict`/`typeCheckStrictWithCache` enforce hard errors on unbound variables, unknown functions, type mismatches, and unknown operators. `doBuild`, `doBuildFromJson`, `doRun`, and `doVerify` all gate on strict typecheck. `llmll check --strict` CLI flag added.
- **BUG-5** — Termination documentation corrected (`LLMLL.md` §4.2, §5.3.3). Claims of "verified automatically" replaced with accurate "checked for non-negativity (`n ≥ 0`)". Strict descent encoding deferred to v0.7 research track.
- **BUG-6** — Body-faithfulness guard on contract stripping (`Contracts.hs`). `filterContracts` now only strips `VLProven` clauses when `isBodyFaithful` returns `True` (currently returns `False` for all provers). Prevents unsound assertion removal.
- **BUG-7** — Proof laundering protection (`ProofCache.hs`). `isTaintedProof` detects `sorry`/`mock`/`admit` in proof text. `proofToLevel` caps tainted proofs at `VLAsserted`. Mock prover tagged `"mock"` instead of `"leanstral"`.

### Compiler — Strict Mode (`tcStrictMode`)

- **`TCState.tcStrictMode`** — New field. When `True`, `tcWarnOrError` emits errors instead of warnings at four permissive sites (unbound variables, unknown functions, unknown operators, branch type mismatch).
- **`typeCheckStrict`** — Strict counterpart to `typeCheck` (no module cache).
- **`typeCheckStrictWithCache`** — Strict counterpart to `typeCheckWithCache`.
- **`llmll check --strict`** — CLI flag for CI gates on completed programs.

### Spec (LLMLL.md)

- §4.2 — Termination claims corrected (non-negativity only, not strict descent)
- §5.3.3 — Verification-scope matrix updated to reflect actual capability

**Tests:** 289 examples, 0 failures. ERC-20 (11/11) and TOTP (14/14) benchmarks green.

---

## v0.6.2 — Algebraic Interface Laws (2026-04-24)

### Compiler — Interface Laws (`def-interface :laws`)

- **`:laws` clause** — `def-interface` gains an optional `:laws` section containing `(for-all ...)` algebraic properties. Laws are first-class: parsed, type-checked (methods + bindings in scope), and enforced via QuickCheck codegen.
- **`Syntax.hs`** — `defInterfaceLaws` field changed from `[Expr]` to `[Property]` (LAWS-1).
- **`Parser.hs`** — `:laws [(for-all [x: T] expr)]` clause parsing (LAWS-2).
- **`ParserJSON.hs`** — `parseLawProperty` for JSON-AST law round-trip (LAWS-3).
- **`TypeCheck.hs`** — `for-all` law expressions type-checked with interface methods and bindings in scope (LAWS-4).
- **`CodegenHs.hs`** — QuickCheck `prop_` function emission for each law property (LAWS-5).
- **`AstEmit.hs`** — JSON-AST law emission for round-trip compatibility (LAWS-6).
- **`SpecCoverage.hs`** — Separate "Interface laws" section in spec coverage report (LAWS-7).
- **`PBT.hs`** — Interface laws wired into `runPropertyTests` (LAWS-PBT).

### Compiler — Verification-Scope Matrix Backfill

- **VSM-1** — All three verifier examples (`hangman_json_verifier`, `tictactoe_json_verifier`, `conways_life_json_verifier`) now have `VERIFICATION_SCOPE.md` files documenting per-function classification and verification boundary.

### Spec (LLMLL.md)

- §8.8.1 — New section: `def-interface :laws` syntax and semantics
- §14 — v0.6.2 roadmap section marked ✅ Shipped

**Tests:** 279 → 289 Haskell (+10: T1–T10 interface laws), 37 Python (unchanged).

---

## v0.6.1 — TOTP Benchmark & Hub Query (2026-04-23)

### Compiler — Cryptographic Builtins (§13.11)

- **`hmac-sha1`** — New builtin: `bytes[20] → bytes[20] → bytes[20]`. RFC 2104 HMAC with SHA-1. Preamble implementation in `CodegenHs.hs` using `Data.Bits.xor`.
- **`sha1`** — New builtin: `bytes[20] → bytes[20]`. Simplified SHA-1 stub. Returns 20 bytes derived from input.
- **Agent spec** — Both builtins auto-reflected in `llmll spec` output.

### Compiler — TOTP RFC 6238 Benchmark

- **`examples/totp_rfc6238/totp.ast.json`** — Skeleton with 6 functions (all holes), RFC `:source` annotations, 100% effective spec coverage.
- **`examples/totp_rfc6238/totp_filled.ast.json`** — Complete implementation with 4 check blocks (RFC 6238 §A.1 test vectors, reflexive validation, padding).
- **`examples/totp_rfc6238/EXPECTED_RESULTS.json`** — Frozen expected results for CI regression.
- **`scripts/benchmark-totp.sh`** — CI gate script (14 assertions: parse, spec coverage, trust report, provenance, scope matrix, check blocks).
- **`make benchmark-totp`** — Makefile target. `make benchmark-all` now runs both ERC-20 (11) and TOTP (14) gates.

### Compiler — Hub Query-by-Signature

- **`LLMLL.HubQuery`** — New module. Brute-force scan of `~/.llmll/modules/` for functions matching a type signature.
- **`structuralMatch`** — Structural type matching: TVar wildcards, TDependent stripping, order-sensitive parameter matching.
- **`llmll hub query --signature "int -> int -> int"`** — New CLI subcommand (text + JSON output).
- **`CheckoutToken.ctHubSuggestions`** — New `Maybe [QueryResult]` field for checkout-time hub suggestions (HUB-3).

### Compiler — v0.6.0 Carryover

- **PROV-3** — `:source` annotations now displayed in `--trust-report` text output (`formatEntry`) and JSON output (`entryJson`).
- **BM-4** — ERC-20 CI gate (`scripts/benchmark-erc20.sh`, `make benchmark-erc20`) with 11 frozen assertions.

---

## v0.6.0 — Specification Quality (2026-04-22)

### Compiler — Spec Coverage Gate

- **`SpecCoverage.hs`** — New module. Classifies every function in a module as **contracted** (has `pre`/`post`), **suppressed** (has `weakness-ok`), or **unspecified**, then computes the effective coverage ratio. Used by `llmll verify --spec-coverage`.
- **`llmll verify --spec-coverage`** — New flag. Walks `[Statement]`, counts `SDefLogic`/`SLetrec` with/without contracts, cross-references `.verified.json` sidecar for verification levels. Emits coverage report with per-function breakdown (text and JSON).
- **`effective_coverage` metric** — Formula: `(contracted + suppressed) / total_functions`. SC-PO-1: division guard — 0 functions → 100%.
- **Governance guardrails** — WO-1 (`W601`): `weakness-ok` target doesn't match any function. WO-2 (`W602`): function has contracts AND `weakness-ok` (contracts take priority). D10 (`W603`): more than 50% of functions are suppressed.

### Compiler — Suppression Governance (`weakness-ok`)

- **`SWeaknessOk` AST node** — New `Statement` constructor: `SWeaknessOk { weaknessTarget :: Name, weaknessReason :: Text }`.
- **`(weakness-ok fn-name "reason")`** — S-expression parser support. Mandatory non-empty reason string (empty reason is a parse error).
- **JSON-AST support** — `ParserJSON.hs` accepts `{"kind": "weakness-ok", "name": "...", "reason": "..."}`.
- **Integration** — Handled in `TypeCheck.hs` (no-op), `CodegenHs.hs` (no-op), `AstEmit.hs` (round-trip), `HoleAnalysis.hs` (excluded from hole analysis).
- **TrustReport integration** — `--trust-report` output includes an "Intentional Underspecification" section listing all `weakness-ok` declarations with reasons. JSON output includes `suppressions` array.

### Compiler — Clause-Level Provenance (`:source`)

- **`:source` annotation** — S-expression syntax: `(pre expr :source "RFC 8446 §7.1")` and `(post expr :source "safety invariant")`. JSON-AST: `"pre_source"` / `"post_source"` optional string fields.
- **`contractPreSource` / `contractPostSource`** — New `Maybe Text` fields in `Contract` (`Syntax.hs`). Per-clause provenance, not per-contract.
- **`csPreSource` / `csPostSource`** — New `Maybe Text` fields in `ContractStatus` for sidecar persistence and trust report threading.
- **Multiple pre clauses** — When multiple `(pre ...)` clauses are combined with `and`, the `:source` annotation is dropped (ambiguous provenance).
- **Backward compatible** — Omitting `:source` yields `Nothing`. No effect on type checking, verification, or codegen.

### Compiler — ERC-20 Benchmark

- **`examples/erc20_token/`** — Frozen benchmark with 4 files:
  - `erc20.ast.json` — Full ERC-20 skeleton with 6 typed functions and contracts
  - `erc20_filled.ast.json` — Filled version with implementations
  - `EXPECTED_RESULTS.json` — Ground truth: verification-scope matrix (10 properties), expected spec coverage (100%), weakness check (no weak functions), trust report
  - `WALKTHROUGH.md` — End-to-end: external spec → LLMLL contracts → verified code → weakness detection → spec coverage

### Spec (LLMLL.md)

- §4.5 — New section: `weakness-ok` syntax and governance rules
- §5.4 — New section: `--spec-coverage` command and effective coverage formula
- §4.1 — `:source` annotation documented in contract syntax
- §14 — v0.6.0 roadmap section marked ✅ Shipped
- Release history table — v0.6.0 entry added

**Tests:** 264 → 279 Haskell (+15: 4 `:source` annotation, 11 spec coverage + weakness-ok), 37 Python (unchanged).

---

## v0.5.0 — U-Full Soundness (2026-04-21)

### Compiler

- **Occurs check** — `TVar "a"` cannot unify with a type that contains itself (e.g., `list[TVar "a"]`). Prevents infinite type construction. `occursIn` helper is structurally total over the `Type` ADT, including `TSumType`.
- **Let-generalization** — Top-level `def-logic` and `letrec` functions are let-generalized: each call site gets fresh type variable instantiation. Inner `let`-bound lambdas are not generalized (deferred to v0.7).
- **TVar-TVar wildcard closure** — Type variable bindings now propagate through chains. Closes the gap where `TVar "a" ~ TVar "b"` followed by `TVar "b" ~ int` would leave `TVar "a"` unresolved.
- **Bound-TVar consistency fix** — Recursive `structuralUnify` replaces `compatibleWith` at L1044 for bound type variable comparison (Language Team Issue 2).
- **L1055 asymmetric wildcard** — Documented as safe under per-call-site scoping (Language Team Issue 3). Each `EApp` gets fresh type variables, so the asymmetry does not leak across call boundaries.

### Spec (LLMLL.md)

- §3.2 — U-Full type variable note added
- §4.17 — New section in `getting-started.md` documenting occurs check and let-generalization with examples
- §10.7 — Pipeline notes updated with v0.5.0 entry
- §14 — v0.5.0 roadmap section marked ✅ Shipped

**Tests:** 257 → 264 Haskell (+7 U-Full), 37 Python (unchanged).

---

## v0.4.0 — Lead Agent + U-Lite Soundness (2026-04-20)

### Compiler — Lead Agent

- **`llmll-orchestra --mode plan`** — Intent-to-architecture-plan generation. Produces structured JSON plan from natural language intent.
- **`llmll-orchestra --mode lead`** — Plan-to-skeleton generation. Produces validated JSON-AST skeleton with typed `def-interface` boundaries and `?` holes.
- **`llmll-orchestra --mode auto`** — End-to-end pipeline: plan → skeleton → fill → verify in sequence.
- **Quality heuristics** — Skeleton quality checks flag: low parallelism, all-string types, missing contracts, unassigned agents.

### Compiler — U-Lite Soundness

- **Per-call-site substitution-based unification** — Each `EApp` gets fresh type variable instantiation via α-renaming. Substitution map does not escape the `EApp` boundary. `list-head 42` is now correctly rejected as a type error.
- **`first`/`second` retyped** — From `TVar "p" → TVar "a"` to `TPair a b → a` / `TPair a b → b` in `builtinEnv`. `first 42` is now a type error.
- **TDependent resolution** — Strip-then-Unify (Option A). `TDependent` strips to base type during unification — no constraint propagation, no proof obligations. Formalizes existing `compatibleWith` behavior.

### Compiler — CAP-1 Capability Enforcement

- **Compile-time capability check** — `wasi.*` function calls without a matching `(import wasi.* (capability ...))` in the module's statement list produce a type error. Check is in `inferExpr (EApp ...)`, covering all nesting contexts: `let` RHS, `if` branches, `match` arms, `do` steps, contract expressions.
- **Non-transitive propagation** — Each module must declare its own capability imports. Module B cannot inherit Module A's capabilities.

### Compiler — Invariant Pattern Registry

- **`InvariantRegistry.hs`** — New module. Pattern database keyed by `(type signature, function name pattern)`. ≥5 patterns: list-preserving, sorted, round-trip, subset, idempotent.
- **`llmll typecheck --sketch`** — Now emits `invariant_suggestions` field from the pattern registry.

### Compiler — Downstream Obligation Mining

- **`ObligationMining.hs`** — New module. When `llmll verify` reports UNSAFE at a cross-function boundary, suggests postcondition strengthening on the callee. Leverages `TrustReport.hs` transitive closure infrastructure.

### Compiler — Aeson FFI

- **`(import haskell.aeson Data.Aeson)`** — Codegen emits `import Data.Aeson` + adds `aeson` to `package.yaml`. Manual Haskell bridge file required for JSON instance derivation.

### Orchestrator

- **`lead_agent.py`** — Lead Agent skeleton generation with plan/lead/auto modes.
- **`quality.py`** — Skeleton quality heuristics module.

**Tests:** 225 → 257 Haskell (+32), 12 → 37 Python (+25).

---

## v0.3.5 — Agent Effectiveness (2026-04-19)

### Track B: Context-Aware Checkout (C1–C6)

- **Provenance-tagged environment snapshots** — `ScopeSource` (Param | LetBinding | MatchArm | OpenImport) and `ScopeBinding` types track the origin of each in-scope binding. `SketchHole.shEnv` captures the typing environment delta at hole sites.
- **`withTaggedEnv`** — New scope combinator that pushes provenance-tagged bindings and restores on exit.
- **Context-aware `CheckoutToken`** — Extended with `ctInScope` (Γ), `ctExpectedReturnType` (τ), `ctAvailableFunctions` (Σ), and `ctTypeDefinitions`. JSON schema bumped to v0.3.0.
- **`normalizePointer`** (EC-3) — Strips leading zeros from RFC 6901 pointer segments.
- **`collectTypeDefinitions`** (C4) — Depth-bounded (5-level) recursive alias expansion with cycle detection (EC-4).
- **`monomorphizeFunctions`** (C5) — Presentation-only type variable substitution. Idempotent (INV-1), does not mutate `builtinEnv` (INV-2).
- **`truncateScope`** (C6) — Priority-based scope retention: Params > LetBindings > MatchArms > OpenImports.
- **EC-1 bug fix** — `inferExpr (ELet ...)` was leaking `tcInsert` mutations to sibling if-branches. Fixed by save/restore around the binding `foldM`.

### Track W: Weak-Spec Counter-Examples (W1–W2)

- **`WeaknessCheck.hs`** — New module. Trivial body catalog: identity, constant-zero, empty-string, true, empty-list. Type-checks synthetic statements (INV-4) before fixpoint emission.
- **`--weakness-check`** — New flag on `llmll verify`. After SAFE, runs trivial body analysis. SAFE trivial bodies produce `spec-weakness` diagnostics.
- **`mkSpecWeakness`** — Structured diagnostic with precondition text (EC-7), suggestion, and `kind: "spec-weakness"`.

### Track A: Orchestrator End-to-End (O1–O5)

- **O2: Formatted retry diagnostics** — `_format_diagnostics()` renders compiler diagnostics as human-readable actionable text (not raw JSON) for agent follow-up prompts.
- **O3: Checkout TTL handling** — `_ensure_checkout()` checks remaining TTL; re-checkouts on expiry with EC-6 token re-assignment.
- **O4: Integration tests** — 12 Python tests covering happy path, retry, lock expiry, token update, all-fail, and prompt formatting.
- **O5: Context-aware prompt** — `_format_context()` renders scope as markdown table, functions as signature list, types as definition list. Falls back to JSON for unknown keys.

**Tests:** 211 → 225 Haskell (14 new), 12 Python tests (all new).

---

## v0.3.4 — Agent Spec + Orchestrator Hardening (2026-04-19)

### Compiler — `llmll spec`

- **New `LLMLL.AgentSpec` module** — Reads `builtinEnv` from `TypeCheck.hs` directly and serializes it as a structured agent specification. Partitions builtins (36) from operators (14) via an explicit `operatorNames` set matching `CodegenHs.emitOp`. Excludes `wasi.*` functions. Deterministic alphabetical output.
- **`llmll spec [--json]` CLI command** — Emits the agent spec to stdout. Text output (default) is token-dense for direct system prompt inclusion. JSON output includes constructors, evaluation model, pattern kinds, and type nodes.
- **7 faithfulness property tests** — `covers all builtinEnv`, `no phantom entries`, `disjoint partition`, `unary not`, `deterministic order`, `excludes wasi.*`, `includes seq-commands`. Adding a new builtin without a spec entry is caught automatically.

### Compiler — Builtin changes

- **New builtin: `string-empty?`** — `string → bool`. Added to `builtinEnv` + runtime preamble (`string_empty' s = null s`). Documented in `LLMLL.md` §13.6.
- **New preamble: `regex-match`** — `string → string → bool`. Runtime implementation: `regex_match pattern subject = pattern \`isInfixOf\` subject`. Added `isInfixOf` import to generated Haskell.
- **Removed: `is-valid?`** — Phantom builtin removed from `builtinEnv`. Was not used by any example or test.
- **Exported `builtinEnv`** — Now part of the public `TypeCheck` module API for consumption by `AgentSpec`.

### Orchestrator — Phase A prompt enrichment

- **Composable system prompt** — `agent.py` refactored: `SYSTEM_PROMPT` split into `_SYSTEM_PROMPT_HEADER` + injected spec + `_SYSTEM_PROMPT_FOOTER`. New `build_system_prompt(compiler_spec)` function.
- **Compiler integration** — `compiler.py` gains `spec()` method wrapping `llmll spec` with backward-compat fallback (returns `None` for pre-v0.3.4 compilers). `orchestrator.py` calls `compiler.spec()` at start of `run()`.
- **Legacy fallback** — `_LEGACY_BUILTINS_REF` in `agent.py` provides static reference for compilers without `spec` command.
- **New prompt sections** — pair/first/second usage, Result construction vs pattern matching (ok/err vs Success/Error), letrec note, fixed-arity operator rule with parametricity note, `pair-type` and `fn-type` type nodes.

**Tests:** 194 → 211 (+7 AgentSpec faithfulness + 10 other).

---

## v0.3.3 — Agent Orchestration (2026-04-16)

### Compiler — `llmll holes --json --deps`

- **Annotated dependency graph** — Each hole entry in `--json` output includes `depends_on` edges with `{pointer, via, reason}` and `cycle_warning` flag. Dependency = "hole B's enclosing function calls a function whose body contains hole A" (`calls-hole-body`).
- **Tarjan's SCC cycle detection** — `HoleAnalysis.hs` walks the call graph and detects mutual-recursion cycles. Deterministic back-edge removal (highest statement index). `cycle_warning: true` per hole.
- **`--deps-out FILE`** — New flag persists the dependency graph to a file (implies `--deps`). Compiler does not manage lifecycle — orchestrator owns the file.
- **RFC 6901 pointer fix** — `holePointer` rewritten to track structural AST position (`/statements/N/body`, etc.) — compatible with `llmll checkout`. Previous context-based pointer generation was non-functional.
- **Scope exclusions** — `?proof-required` holes and contract-position holes excluded from the dependency graph.
- **Call-graph analysis** — New internal functions in `HoleAnalysis.hs`: `extractCalls`, `buildCallGraph`, `buildFuncBodyHoles`, `computeHoleDeps`.

### Docs

- `docs/orchestrator-walkthrough.md` — Full end-to-end walkthrough: skeleton authoring → hole scanning → tier scheduling → agent filling → Haskell compilation. Includes conceptual model (metavariables, CEGIS), related work (Agda, Synquid, ChatDev, Airflow), and evaluation questions.
- `docs/archive/shipped-design-specs/agent-prompt-semantics-gap.md` — Agent prompt gap analysis: what's missing from the agent system prompt, 3-phase solution (A: enhanced prompt, B: `llmll spec --agent`, C: context-aware checkout). Reviewed and approved by Language Team and Professor.
- `docs/archive/shipped-design-specs/lead-agent.md` — Design for automated skeleton generation: Lead Agent loop (decompose → generate AST → `llmll check` → iterate), quality heuristics, phased implementation.
- `examples/orchestrator_walkthrough/` — Auth module exercise files (`auth_module.ast.json`, `auth_module_filled.ast.json`).

**Tests:** 194 (unchanged from v0.3.2 — this release is compiler analysis + external tooling).

---

## v0.3.2 — Trust Hardening + WASM PoC (2026-04-16)

### Compiler

- **Cross-module trust propagation tests** — 7 test cases covering the asserted/tested/proven verification level matrix, mixed levels, and `(trust ...)` declaration suppression. Validates that `VLProven` importing `VLAsserted` is correctly capped.
- **`llmll verify --trust-report`** — New output mode prints a per-function trust summary after verification: contract verification level (proven/tested/asserted), transitive closure of cross-module calls, and epistemic drift warnings ("Function `withdraw` is proven, but depends on `auth.verify-token` which is asserted"). JSON output with `--json`. New `LLMLL.TrustReport` module.
- **GHC WASM proof-of-concept** — Analyzed `hangman_json_verifier` generated Haskell for WASM compatibility. Conditional GO verdict — pure logic compiles cleanly; ~6-7 days engineering for v0.4. See `docs/archive/wasm-investigations/wasm-poc-report.md`.

**Tests:** 181 → 194 (7 trust propagation + 6 trust report).

---

## v0.3.1 — Event Log + Leanstral MCP (2026-04-11)

### Event Log (Phase A)

- **JSONL event logging** — Generated `Main.hs` for console programs writes `.event-log.jsonl` with true JSONL format (one JSON object per line, crash-safe).
- **stdout capture** — `captureStdout` via `hDuplicate`/`hDupTo` captures program output for the `result` field. Forced lazy I/O evaluation prevents pipe read bugs.
- **`llmll replay`** — New subcommand parses `.event-log.jsonl` files and reports events with input/result values.
- **`Replay.hs`** — JSONL line-by-line parser with crash tolerance (partial logs parseable up to last flushed line).

### Leanstral MCP (Phase B — Mock-Only)

- **`LeanTranslate.hs`** — Translates LLMLL contract AST (`EOp`/`EApp`) to Lean 4 `theorem` obligations. Supports linear arithmetic, list structural induction, quantified variables.
- **`MCPClient.hs`** — MCP JSON-RPC client with `--leanstral-mock` mode (`ProofFound "by sorry"`). Real protocol implemented but untested.
- **`ProofCache.hs`** — Per-file `.proof-cache.json` sidecar with SHA-256 invalidation. Follows `VerifiedCache` pattern.
- **`holeComplexity`** — `HoleAnalysis.hs` gains `holeComplexity :: Maybe Text` field. `normalizeComplexity` classifies proof-required holes as `:simple`, `:inductive`, or `:unknown`. JSON output includes `"complexity"` field.
- **`inferHole (HProofRequired)`** — Added missing type checker pattern for `?proof-required` holes.

### Integration (Phase C)

- `examples/event_log_test/` and `examples/proof_required_test/` — minimal programs for end-to-end validation.

### Replay Execution (Phase D)

- **`runReplay`** — Spawns compiled executable, feeds inputs step-by-step via blocking `hGetLine` (synchronized I/O), compares captured outputs against logged results.
- **`doReplay`** — Full pipeline: parse JSONL → build program → find executable → run replay → report matches/divergences.

### Verify Integration (Phase E)

- **`--leanstral-mock`** / `--leanstral-cmd` / `--leanstral-timeout`** — CLI flags on `llmll verify` to enable Leanstral proof pipeline.
- **`runLeanstralPipeline`** — Scans `[Statement]` directly for `SDefLogic`/`SLetrec` with `HProofRequired` body. Runs translate → prove → cache flow.

### SHA-256 Hardening (Phase F)

- **`computeObligationHash`** — `cryptohash-sha256` dependency. Real SHA-256 hash (64-char hex) for proof cache invalidation.

**Tests:** 145 → 181 (36 new: 5 event log + 10 Leanstral MCP + 5 integration + 16 coverage gaps).

---

## v0.3.0-dev — Do-Notation + Type Soundness (in progress)

### Compiler — Stratified Verification + Feature Completion (2026-04-11)

- **Stratified Verification (Item 7b)** — `VerificationLevel` ADT (`VLAsserted`, `VLTested n`, `VLProven prover`) with custom `Ord` instance (asserted < tested < proven). `ContractStatus` tracks per-function pre/post levels. Type checker seeds contract status from imported modules via `VerifiedCache` sidecar files. Trust-gap warnings emitted for calls to unproven cross-module functions lacking `(trust ...)` declarations.
- **`(trust ...)` declaration (Item 7b)** — new `STrust` statement kind. Parsed in both S-expression (`(trust foo.bar :level tested)`) and JSON-AST. Silences trust-gap warnings for explicitly acknowledged dependencies.
- **`--contracts` CLI flag (Item 8)** — `llmll build --contracts=full|unproven|none`. `applyContractsMode` pre-processes statements before codegen, stripping contract clauses by mode. `ContractsNone` removes all pre/post assertions; `ContractsUnproven` strips only clauses with proven verification status; `ContractsFull` (default) preserves all.
- **`.verified.json` sidecar write (Item 9)** — `llmll verify` now calls `saveVerified` after a `FQSafe` result from liquid-fixpoint, writing per-function `ContractStatus` with `VLProven "liquid-fixpoint"` to a sidecar file. Subsequent `llmll build --contracts=unproven` reads this sidecar via `loadVerified` + `mergeCS` to strip proven assertions.
- **`string-concat` variadic sugar (Item 10)** — `Parser.hs` desugars `(string-concat e1 e2 e3 …)` with 3+ args to `(string-concat-many [e1 e2 e3 …])` at parse time. Already shipped; confirmed in audit.
- **`?scaffold` CLI (Item 11)** — `llmll hub scaffold <template> [--output DIR]`. `Hub.hs` adds `scaffoldCacheRoot` (`~/.llmll/templates/`) and `resolveScaffold`. Hub command upgraded from single `--from-file` option to `fetch`/`scaffold` subcommand group. Explicit `emitHole (HScaffold ...)` clause added to CodegenHs.
- **Async codegen verification (Item 14)** — confirmed `TPromise` → `Async.Async`, `EAwait` → `try (Async.wait ...)` with `SomeException` catch-all, generated preamble imports `Control.Concurrent.Async` + `Control.Exception`, `package.yaml` includes `async` dependency. 10 regression tests added.
- **Tests:** 69 → 121 → 128 → 145 across the v0.3 cycle.


### Compiler — PRs 1–3 (2026-04-05 – 2026-04-08)

- **`TPair` introduction (PR 1)** — new `TPair Type Type` constructor in `Syntax.hs`. `EPair` expressions are now typed `TPair a b`, replacing the unsound `TResult a b` approximation. Fixes two incorrect behaviours: (1) `llmll build --emit json-ast` emitted `{"kind":"result-type",...}` for pair-typed expressions; (2) `match` exhaustiveness on pair-typed scrutinee incorrectly cited `Success`/`Error` constructors. Surface syntax unchanged.
- **`DoStep` collapse (PR 2)** — `DoStep (Maybe Name) Expr` replaces the previous `DoBind Name Expr` / `DoExpr Expr` split. Unified AST node simplifies all downstream passes. Type checker now enforces that every step in a `do`-block returns `(S, Command)` with identical state type `S` across all steps (pair-thread enforcement).
- **`emitDo` rewrite (PR 3)** — do-notation codegen replaced with a pure `let`-chain emitter. Named steps `[s <- expr]` bind the state component via `let`; anonymous steps `(expr)` discard it. `seq-commands` folds accumulated commands. No Haskell `do` or monads emitted — sound in `def-logic` pure contexts.
- **JSON parser do-step migration** — `ParserJSON.hs` rejects old `"bind-step"` and `"expr-step"` kinds with a clear migration error pointing to `"do-step"`. No backward compatibility — do-notation never shipped in a stable release.

### Compiler — PR 4 (shipped)

- **Pair destructuring in `let` bindings** — `(let [((pair s cmd) expr)] body)` destructures pair-typed expressions into two bindings. Nested destructuring is supported: `(let [((pair w (pair g r)) state)] ...)`.
  - `Syntax.hs`: `ELet` binding head changed from `Name` to `Pattern`.
  - `Parser.hs`: `pLetBinding` calls `pPattern`; `pPattern` now accepts `(pair p1 p2)` as a constructor despite `pair` being a reserved word.
  - `ParserJSON.hs`: `parseLet1Binding` supports `"name"` (ergonomic shorthand) and `"pattern"` (full destructuring) with strict key validation.
  - `TypeCheck.hs`: `inferExpr (ELet ...)` dispatches `PVar` (simple binding) vs `checkPattern` (destructuring); pair constructor at line 829.
  - `CodegenHs.hs`: `emitLet` uses `emitPat`; `emitPat (PConstructor "pair" [p1,p2])` emits Haskell tuple pattern.
  - `AstEmit.hs`: `bindingToJson` emits `"name"` for `PVar`, `"pattern"` for other patterns.
  - `llmll-ast.schema.json`: `ExprLet` binding items have `"name"` + `"pattern"` with `oneOf` constraint.
- **Acceptance:** All 7 criteria verified — 3 new test fixtures pass, existing examples unaffected, no `-Wincomplete-patterns`, 69/69 unit tests pass.

### Spec (LLMLL.md)

- §5 scope note, §9.6 do-notation, §12 EBNF grammar, §14 roadmap — updated to reflect PRs 1–3
- §12 EBNF `do-step` production corrected: `[IDENT "<-" expr]` (was `("<-" IDENT expr)`)
- Stale v0.1.x restriction notes, workarounds, and version provenance tags removed throughout
- **§11.2 `await` return type (v0.3)** — `await` now returns `Result[t, DelegationError]` instead of bare `t`. Programs using `await` must pattern-match on `Success`/`Error`. This is a breaking change from v0.2.
- **§11.2 Checkout/Patch workflow (v0.3)** — new subsection documenting the `llmll checkout` / `llmll patch` lifecycle for agent-driven hole resolution via RFC 6902 JSON-Patch.
- **Principle 4 renamed** from "Runtime Contract Verification" to "Design by Contract with Stratified Verification." Contracts now carry a verification level (`proven`, `tested`, `asserted`). `--contracts` flag controls runtime assertion compilation. Trust-level propagation warns downstream modules about unproven dependencies.
- **§4.4 Contract Semantics rewritten** — new subsections §4.4.1 (Verification Levels), §4.4.2 (Runtime Assertion Modes), §4.4.3 (Trust-Level Propagation). `(trust ...)` syntax introduced for acknowledging unproven dependencies.
- **§12 EBNF grammar** — `trust-decl` production added.

### Docs

- `getting-started.md` — §4.13 backward-compat claim corrected (bind-step/expr-step are rejected, not parsed); `typecheck` and `serve` added to `--help` output; `checkout` and `patch` command docs added
- `llmll-ast.schema.json` — stale v0.1.x notes removed from TypedParam, TypePair, ExprLambda, DoStep descriptions; `ExprAwait` description updated for `Result[t, DelegationError]` return type; `PatchEnvelope`, `PatchOp`, `CheckoutToken` companion definitions added; `TrustDecl` node kind added to `Statement` oneOf
- `README.md` — 6 missing examples and 4 missing compiler modules added to repo layout; `checkout` and `patch` added to CLI command table

---

## v0.2.0 — Phase 2a/2b/2c: Module System, Compile-Time Verification, Sketch API (2026-03-28)

### Compiler — Phase 2c (2026-03-28)

- **`llmll typecheck --sketch <file>`** — new subcommand for partial-program type inference. Accepts a program with holes anywhere; returns each hole's inferred type (`null` if indeterminate) and all detectable type errors annotated with `holeSensitive: bool`. `holeSensitive: true` means the error may resolve once holes are filled.
- **`llmll serve [--host H] [--port P] [--token T]`** — exposes `--sketch` as `POST /sketch` HTTP endpoint for distributed agent swarms. Binds `127.0.0.1:7777` by default. Every request is stateless (fresh type-check context per call — safe for concurrent agent use). `--token` enables `Authorization: Bearer` auth; TLS is delegated to a reverse proxy.
- **Pair-type in typed parameters** — `[acc: (int, string)]` is now valid in `def-logic`, lambda, and `for-all` parameter lists. Parsed as `TResult A B` internally (v0.3 PR 1 replaces this with `TPair A B`). Workaround note removed from `LLMLL.md §3.2` and `getting-started.md §4.7`.
- **`string-concat` arity hint (N2)** — arity mismatch error on `string-concat` with more than 2 arguments now appends `— use string-concat-many for joining more than 2 strings`.
- **Strict `let` key validation (N3)** — JSON-AST `let` binding objects with unexpected keys (e.g. `kind`, `op` alongside `name`/`expr`) now produce a clear parse error naming the offending key. Previously accepted silently, producing corrupt AST nodes.
- **`LLMLL.Sketch`** — new module. `HoleStatus` ADT (`HoleTyped`, `HoleAmbiguous`, `HoleUnknown`); `runSketch`; `encodeSketchResult`. Hole-constraint propagation at `EIf` (sibling branch), `EMatch` (two-pass arm loop), and `EApp` (function signature via `unify`).

### Compiler — Phase 2b (2026-03-27)

- **`llmll verify <file>`** — new subcommand (D4). Emits a `.fq` constraint file from the typed AST and runs `liquid-fixpoint` + Z3 as a standalone binary. Reports SAFE or contract-violation diagnostics with RFC 6901 JSON Pointers back to the original `pre`/`post` clause. Gracefully degrades when `fixpoint`/`z3` are not in `PATH`.
- **Static `match` exhaustiveness (D1)** — post-inference pass `checkExhaustive` rejects any `match` on an ADT sum type that does not cover all constructors. GHC-style error with pointer to the missing arm.
- **`letrec` + `:decreases` (D2)** — new statement kind for self-recursive functions. Mandatory `:decreases` termination measure is verified by `llmll verify`. Self-recursive `def-logic` emits a non-blocking warning.
- **`?proof-required` holes (D3)** — compiler auto-emits `?proof-required(non-linear-contract)` and `?proof-required(complex-decreases)` for predicates outside the decidable QF linear arithmetic fragment. Non-blocking; runtime assertion remains active.
- **`LLMLL.FixpointIR`** — ADT for the `.fq` constraint language (sorts, predicates, refinements, binders, constraints, qualifiers) + text emitter.
- **`LLMLL.FixpointEmit`** — typed AST walker → `FQFile` + `ConstraintTable` (constraint ID → JSON Pointer). Auto-synthesizes qualifiers from `pre`/`post` patterns, seeded with `{True, GEZ, GTZ, EqZ, Eq, GE, GT}`.
- **`LLMLL.DiagnosticFQ`** — parses `fixpoint` stdout (SAFE / UNSAFE) → `[Diagnostic]` with `diagPointer` (RFC 6901 JSON Pointer) via the `ConstraintTable`.
- **`TSumType` refactor** — structured ADT representation in `Syntax.hs` replacing the previous untyped constructor list. Prerequisite for exhaustiveness checking.
- **`unwrap` preamble alias** — generated `Lib.hs` now exports `unwrap = llmll_unwrap`. Fixes `Variable not in scope: unwrap` GHC errors at call sites.
- **Operator-as-app fix** — `emitApp` now intercepts arithmetic/comparison operators used in `{"kind":"app","fn":"/"}` position and delegates to `emitOp`. Fixes `(/ (i) (width))` fractional-section GHC errors for integer division inside lambdas.
- **`.fq` constructor casing fix** — `emitDataDecl` lowercases ADT sort names and constructor names. Fixes liquid-fixpoint parser rejection of capitalized identifiers (e.g. `X 0` in `[X 0 | O 0]`).

### New Examples

- `examples/conways_life_json_verifier/` — Conway's Game of Life with verified `count-neighbors` and `next-cell` contracts
- `examples/hangman_json_verifier/` — Hangman with verified `apply-guess` pre/post
- `examples/tictactoe_json_verifier/` — Tic-Tac-Toe with verified `set-cell` bounds and `make-board` postcondition

### Spec (LLMLL.md)

- v0.2 scope note updated: Phase 2c complete
- §3.2 — pair-type restriction removed; `[acc: (int, string)]` documented as supported
- §4.2 `letrec` — new section documenting bounded recursion with `:decreases`
- §4.4 Contract Semantics — updated: runtime + compile-time enforcement described
- §5.3 — renamed "Verification (Phase 2b — Shipped)"; documents `llmll verify` command and qualifier synthesis strategy

### Schema (`docs/llmll-ast.schema.json`)

- `hole-proof-required` expression node added with `reason` enum: `manual | non-linear-contract | complex-decreases`


---


## v0.1.3 / v0.1.3.1

### Compiler

- **`first`/`second` pair projectors** — now accept any pair argument regardless of explicit type annotations. Previously a parameter annotated as any type (e.g. `s: string`) that was actually a pair would cause `expected Result[a,b], got string`. The `untyped: true` workaround is no longer required on state accessor parameters.
- **`where`-clause binding variable in scope** — `TDependent` now carries the binding name; `TypeCheck.hs` uses `withEnv` during constraint type-checking. Eliminates `unbound variable 's'` false warnings on all dependent type aliases.
- **Nominal alias expansion** — `TCustom "Word"` is now expanded to its structural body before `compatibleWith`. Eliminates all `expected Word, got string` / `expected GuessCount, got int` spurious errors. All examples now check with **0 errors**.
- **New built-ins** — `(string-trim s)`, `(list-nth xs i)`, `(string-concat-many parts)`, `(lit-list ...)` (JSON-AST list literal node).
- **PBT skip diagnostic** — `llmll test` skipped properties now distinguish between "Command-producing function" and "non-constant expression". `bodyMentionsCommand` heuristic narrowed to only genuine WASI/IO prefixes — eliminates false-positive skips on user-defined functions.
- **Check label sanitization** — `check` block labels containing special characters (`(`, `)`, `+`, `?`, spaces) are now automatically sanitized before being used as Haskell `prop_*` function names. Previously these caused `stack build` failures with `Invalid type signature`.
- **S-expression list literals in expression position** — `[a b c]` and `[]` are now valid in S-expression expression position (not just parameter lists). Desugars to `foldr list-prepend (list-empty)`, symmetric with JSON-AST `lit-list`.
- **`ok`/`err` preamble aliases** — generated `Lib.hs` now exports `ok = Right` and `err = Left` alongside the existing `llmll_ok`/`llmll_err`. Fixes `Variable not in scope: ok` GHC errors on programs using `Result` values.
- **Console harness `done?` ordering** — `:done?` predicate is now checked at the **top** of the loop (before reading stdin) instead of after `step`. Eliminates the extra render that occurred when a game ended.
- **`--emit-only` flag** — `llmll build` and `llmll build-json` accept `--emit-only` to write Haskell files without invoking the internal `stack build`. Resolves the Stack project lock deadlock when build is called from inside a running `stack exec llmll -- repl` session.
- **`-Wno-overlapping-patterns` pragma** — generated `Lib.hs` now suppresses GHC spurious overlapping-pattern warnings from match catch-all arms. Also extended exhaustiveness detection for Bool matches and any-variable-arm matches.
- **JSON-AST schema version `0.1.3`** — `expectedSchemaVersion` in `ParserJSON.hs` and `llmll-ast.schema.json` bumped from `0.1.2` to `0.1.3`. The docs already showed `0.1.3` in examples; now the compiler accepts it.
- **`:on-done` codegen fix** — generated console harness now calls `:on-done fn` inside the loop when `:done?` returns `true`, before exiting. Previously it was emitted after the `where` clause (S-expression path: GHC parse error) or silently omitted (JSON-AST path).

### Spec (LLMLL.md)

- **§3.2** — pair-type issues split into Issue A (pair-type-param, parse error, Fixed v0.2) and Issue B (first/second, Fixed v0.1.3.1)
- **§12** — check label identifier rule added; S-expr list-literal production documented
- **§13.5** — `lit-list` JSON-AST node and S-expr `[...]` syntax documented (v0.1.3.1+)
- **§10** — `:on-done` console harness note updated: callback now fires inside the loop, not after the `where` clause

---

## v0.1.2

### Compiler

- **Haskell codegen backend** — replaces the Rust backend entirely. Generated output: `src/Lib.hs` + `package.yaml` + `stack.yaml`, buildable with `stack build`.
- **JSON-AST input** — `llmll build` auto-detects `.ast.json` extension and parses JSON directly. Avoids S-expression parser ambiguities for AI-generated code.
- **`def-main` support** — new `def-main :mode console|cli|http` entry-point declaration generates a full `src/Main.hs` harness:
  - `:mode console` — interactive stdin/stdout loop with `hIsEOF` guard (no `hGetLine: end of file` on exit)
  - `:mode cli` — single-shot from OS args
  - `:mode http PORT` — stub HTTP server
- **`llmll holes`** — works on files with `def-main` (previously crashed with non-exhaustive pattern)
- **Let-scope fix** — sequential `let` bindings now each extend the type environment for subsequent bindings; unbound variable false-positives eliminated
- **Overlapping pattern fix** — `match` codegen no longer emits a redundant `_ -> error "..."` arm when the last explicit arm is already a wildcard
- **Both `let` syntaxes accepted** — single-bracket `(let [(x e)] body)` (v0.1.2 canonical) and double-bracket `(let [[x e]] body)` (v0.1.1, backward-compat) both compile to identical AST

### Spec (LLMLL.md)

- **§9.5 `def-main`** — fully documented: syntax, all three modes, key semantics, S-expression + JSON-AST examples
- **§12 Formal Grammar** — `def-main` EBNF production added; `def-main` added to `statement` production
- **§14 Migration notes** — corrected: both `let` forms are accepted; not "replaced"

### Examples

- Rust-era examples removed (`tictactoe`, `my_ttt`, `ttt_3`, `tasks_service`, `todo_service`, `hangman_complete`, `specifications/`)
- `examples/hangman_sexp/` and `examples/hangman_json/` added — both compile and run end-to-end
