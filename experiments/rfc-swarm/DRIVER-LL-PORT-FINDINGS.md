# DRIVER-LL Phase 3: what the port of stages E and J found

> Session 2026-08-03, compiler v0.14.82, branch `driver-ll/phase-3-stage-j` at `5a55fac`
> (one commit above `main` at `9cec606`). Campaign:
> [`../../docs/design/driver-in-llmll-campaign.md`](../../docs/design/driver-in-llmll-campaign.md)
> §"Phase 3". Port: [`../../tools/llmll-driver/spine.llmll`](../../tools/llmll-driver/spine.llmll).
> Source stages: [`../../scripts/rfc_to_implementation.py`](../../scripts/rfc_to_implementation.py).

> **Second pass, 2026-08-04.** A compiler-engineer replication pass reproduced the three replay
> findings and corrected two of them, refuted F-B, and added F-I. Corrections are folded in place
> below rather than appended, and each says what the first pass got wrong. Measurements attributed
> to that pass are marked; the rest are this role's own.
>
> **Line citations resolve against the compiler as it stood BEFORE the replay repair.**
> `compiler/src/LLMLL/Replay.hs`, `compiler/src/LLMLL/CodegenHs.hs`,
> `compiler/src/LLMLL/TypeCheck.hs` and `compiler/app/Main.hs` were all changed by that repair
> (`25eabde`), which by design moved the very lines these findings describe. Read every
> `<file>:<line>` below against `5a55fac`, the commit this file was written against.

Phase 3 ports stages A, E, G2, J and L of the Python driver into LLMLL as `def-shell`
orchestration around the proved cores in `tools/llmll-driver/`. Stage E shipped in `c3681b0`,
stage J in `5a55fac`. This file records what porting them surfaced, which is mostly not about
the two stages.

**Three of the five findings carried into this session did not survive re-measurement, and all
three were headed for the compiler-engineer's queue.** What did survive is one cluster: `llmll
replay` cannot reproduce a clean run of a console program, for four separate reasons, and no gate
anywhere would have noticed.

## The replay, reproduced independently

Run from the repository root against
[`data/inventory-dispositioned.json`](data/inventory-dispositioned.json), stdin fed nine blank
lines:

```
stage-J-counts=rows:124 encoded:46 core:15 core-out:0 carried:62/65 excluded:53 bad-barrier:53
stage-J-pins=reproduced
stage-J=stopped
stage-J-halt=gate J condition 3, exclusions citing no barrier from the closed list
```

All seven of `self_test()`'s stage-J pins reproduce (`rfc_to_implementation.py:1413-1444`), and
`experiments/rfc-swarm/data/reconciliation.json` came back byte-identical, so stage E reproduces
too. The gate nonetheless halts, and that is the correct replay rather than a port defect: gate
J's third condition counts exclusions whose `barrier` is not in the closed list
(`rfc_to_implementation.py:918-920`), no row in this artifact carries a `barrier` key at all, so
all 53 exclusions qualify. `rfc_to_implementation.py:1425-1437` states exactly this outcome in
prose, and `self_test()` does not exercise the condition (`:1442-1444` prints
`NOT EXERCISED`).

That distinction is the whole of F-D below.

## Findings

| # | Finding | Consumer | Status |
|---|---|---|---|
| F-A | terminal step's command is discarded | compiler-engineer | **withdrawn**, refuted below |
| F-B | higher-order list builtins have no core gate | compiler-engineer | **withdrawn**, refuted below |
| F-C | JSON builtin count drift, thirteen against fourteen | language-team | **withdrawn**, closed in tree |
| F-D | Phase 3 acceptance conflates a gate's decision with its passing | user | **open** |
| F-E | `spine.llmll` outside the frozen-verdict gate | experiment-lead | **closed this session** |
| F-F | unlogged `:init` output injects `count('\n')` stray lines into replay | compiler-engineer | **new, live**, mechanism corrected |
| F-G | the settle entry's logged `""` is a constant, not a capture | compiler-engineer | **new, live**, narrowed |
| F-H | replay's `actual` field is a hardcoded literal | compiler-engineer | **new, live**, unchanged |
| F-I | replay reads one line per event; an event is `count('\n')+1` lines | compiler-engineer | **new, live**, engineer pass |

---

### F-A. The terminal step's discarded command. Withdrawn.

**Filed as:** the generated console loop tests `done?` on the state a step returns and settles
before performing that step's command, so the terminal step's command is silently discarded;
open question, defect or an undocumented `settle` contract.

**The behaviour is real and was reproduced.** A two-step console program whose terminal step
issues `(wasi.io.stdout "TERMINAL-COMMAND-RAN")` prints `init-ran` and `step-0-ran` and nothing
else, exit 0. The generated loop is `Main.hs:62-64`:

```haskell
let (s', cmd) = spine_step s line r
if spine_done' s' then settle s' seqN line logHandle else do
  (output, resp) <- performStep cmd
```

Emitted by `CodegenHs.hs:1564-1568` (`doneLines`) and `:1573-1580` (`settleDef`).

**But it is neither a defect nor undocumented.** It is RC-4, and it is specified:

- `LLMLL.md:1561`, in a section titled *The `:on-done` hook, and the terminating step*:
  "**The terminating step's command is not performed.**" The three-step sequence at `:1564-1568`
  spells out that `cmd` is **discarded**, with the reason at `:1570-1572` (a response can only be
  delivered to a step that runs).
- `LLMLL.md:1574-1576` names the exact failure mode observed: "A `:step` that renders the final
  board on the turn that ends the game renders nothing at all ... **Terminal output for the final
  state must move into `:on-done`.**" An anti-pattern and canonical-pattern pair follows at
  `:1578-1596`.
- `docs/getting-started.md:862` teaches the same remedy.
- `CodegenHs.hs:1510-1516` states it at the emitter: "The consequence is visible and is the
  design's, not an accident."

**The remedy works, measured.** The same program with `:on-done d-result` declared prints
`ON-DONE-RAN` after `step-0-ran`.

**Residue, and it is small.** `spine.llmll:463-467` describes the behaviour as something the
generated loop does to it, and works around it with a throwaway `(pair 9 (wasi.io.stdout ""))`
where the spec names `:on-done`. That is a comment and a stylistic choice in a file another track
may reshape, not a compiler item. Separately, `LLMLL.md:1602-1606` already records that "The four
game examples under `examples/` have not yet been repaired and are known to be affected", so the
one live consequence of RC-4 is filed and owned.

**Why it was filed anyway.** The claim was assembled by reading the generated `Main.hs` and the
emitter, which are both accurate and both silent about the spec section that governs them. Reading
`LLMLL.md §9.5` was the step that refuted it, and it costs one grep.

---

### F-B. Higher-order list builtins have no explicit core gate. Withdrawn, refuted.

**Consumer:** compiler-engineer. **Filed by this role; the diagnosis was wrong.**

**The observation stands and is reproduced below.** The diagnosis built on it does not, and the
fix it pointed at (add `list-filter`, `list-map`, `list-fold` to `coreExcludedBuiltins`) would
have made the situation worse rather than better. Three measurements refute it; this role
reproduced the first two independently before accepting them, and the third is the engineer
pass's.

**(a) Composing the fallback is already gated, on the default path, cold.** Reproduced here with
no `.verified.json` sidecar present. Adding one strict-core caller to the witness below:

```lisp
(def twice-count [xs: list[int]] -> int
  (post (>= result 0) :source "[T] a doubled count is non-negative")
  (+ (count-pos xs) (count-pos xs)))
```

`llmll check` exits 1:

```
error: def 'twice-count': callee 'count-pos' is not body-faithful and not in the trusted
prelude; only verified (body-faithful) functions and trusted builtins are admissible in
strict-core bodies
```

So the ungated case is exactly a **leaf** `def` that nothing in strict core calls. A leaf
contributes to no trust closure, and `--strict-verified-core` catches it anyway. The original
finding measured the leaf and generalized it to the class.

**(b) Trusted-prelude membership never implied body-faithfulness.** Reproduced here:

```lisp
(def tag [n: int] -> string
  (post (>= n 0) :source "[T] a tagged count is non-negative")
  (string-concat "n=" (int-to-string n)))
```

calls only `trustedPrelude` members and lands at `body-fallback`, SAFE, exit 0. Five prelude
names fall back by design, `string-concat` and `int-to-string` among them. Admission and
body-faithfulness were therefore never coupled, so the two-set mechanism the original finding
claimed was failing to gate the fallback was never the fallback gate at all.

**(c) The affected class is at least 37 admitted builtins absent from the emitter, not three**
(engineer pass; not reproduced by this role). Adding the three named builtins would gate three
cases and imply by omission that the other 34 were covered, which is a worse state than the
current uniform silence.

**What is actually owed** is a scope correction to the source comment at `TypeCheck.hs:264-265`,
whose sentence about what the `json-` exclusion buys reads, in context, as a claim about
fallbacks in general. That is assigned to the engineer.

**Recorded so it is not re-filed.** The observation that `count-pos` passes `llmll check` and
falls back silently under a bare `llmll verify` is correct and reproducible. It is not evidence
of an ungated class.

<details>
<summary>The original witness, retained because the observation is real</summary>

> Read under (a) above: every `def` in this block is a leaf. Add one strict-core caller and
> `llmll check` rejects it. Nothing here is evidence of an ungated class.

**Witness, reproduced in a scratch directory outside the repository:**

```lisp
(module named)
(def is-pos [x: int] -> bool (post (= result (> x 0)) :source "[T] positivity") (> x 0))
(def count-pos [xs: list[int]] -> int
  (post (>= result 0) :source "[T] a count is non-negative")
  (list-length (list-filter xs is-pos)))
```

| command | result |
|---|---|
| `llmll check` | OK, 2 statements, exit 0 |
| `llmll verify` | SAFE, exit 0. `body-faithful: is-pos`, `body-fallback: count-pos`. No diagnostic. |
| `llmll verify --strict-verified-core` | exit 1, `1 function(s) fell back from body-faithful verification: count-pos` |

**The lambda route is gated and the named-callee route is not.** The same body written with an
inline `(fn [x: int] -> bool (> x 0))` is rejected at `llmll check`, exit 1:

```
error: def 'count-pos': body contains non-core syntax — lambda, do, await, non-linear
arithmetic, or unrestricted match; use def-shell for permissive bodies
```

(`TypeCheck.hs:1466`.) Passing the predicate as a named `def` reaches `list-filter` with no
diagnostic at all.

**Set memberships, which are facts and not the diagnosis.** `coreExcludedBuiltins`
(`TypeCheck.hs:814-817`) is exactly `json-*` union `wasi.*`. `trustedPrelude` (`:780-784`) admits
`list-head`, `list-tail`, `list-length`, `list-is-empty?` but not `list-filter`, `list-map` or
`list-fold`, which are declared at `:129-131`. The three are in neither set. Per (b) above, that
fact does not decide whether they fall back, because prelude membership does not either.

</details>

---

### F-C. Thirteen builtins in the design record, fourteen in the compiler. Withdrawn, closed in tree.

**Consumer:** language-team, already owned.

**Verified at HEAD `5a55fac`.** `docs/design/native-json-proposal.md` was titled "the thirteen
builtins the driver needs", status Rev 3 SETTLED. Its `:101` read "No `json-get-number`", and D-3
at `:415` deferred exactly that name. The shipped surface is fourteen: `builtinEnv` carries
fourteen `json-` entries at `TypeCheck.hs:272-303`, the extra being `json-get-number` at `:290`,
re-admitted during implementation on the rationale at `:283-289` (four of `self_test()`'s six
stage-E pins are floats, `rfc_to_implementation.py:1405-1409`, so without it the LLMLL driver can
produce the artifact but not check it). `LLMLL.md:152`, `LLMLL.md:2629` (§13.13) and
`CHANGELOG.md:13` all said fourteen, so the drift was confined to the design folder.

**Closed during this session by the parallel track.** `docs/design/native-json-proposal.md` is
modified in the working tree at Rev 4, "SETTLED, reconciled against the shipped compiler. The
surface is FOURTEEN builtins, not thirteen", carrying the same `TypeCheck.hs:290` and `:283-289`
citations. Nothing is owed.

**Recorded because the sequencing is the point.** The finding was true at HEAD and false in the
tree within the same session. A findings file that had asserted it without opening the target
document would have routed work that was already done.

---

### F-D. Phase 3's acceptance clause conflates a gate's decision with its passing. Open.

**Consumer:** user, for adjudication. **Not edited here.**

`driver-in-llmll-campaign.md:286-287` reads: "the five stages run end to end against the committed
TFTP execution and reproduce `self_test()`'s pinned results".

For a `mechanical` stage those are the same sentence. For a `gate` stage they pull apart, and
stage J is the instance: its seven pins reproduce, and the stage stops. Read literally the clause
is satisfied and the phase looks blocked; read as intended it is satisfied and the phase is not.
The port cannot make the halt go away, because the halt is what the Python driver does on this
data (`rfc_to_implementation.py:1425-1431`).

**Implication.** Acceptance for a gate stage should be that the gate's DECISION is reproduced,
including a STOP, and not that the gate passes. RFC-SWARM already holds the general form of this
position: `SUMMARY.md:37` is titled "The third run stopped, and that is the result", and
`:39-42` argues that a method whose stop conditions have never stopped anything has not shown it
has working stop conditions. The same argument applied to a port says a ported gate that cannot
halt has not been shown to be a gate.

**Acceptance.** The Phase 3 clause distinguishes the two stage kinds, or records why it does not
need to.

---

### F-E. `spine.llmll` was outside the frozen-verdict gate. Closed this session.

**Consumer:** experiment-lead. This one was ours.

`scripts/refute-crux-gate.sh` freezes verify verdicts per family from each family's
`EXPECTED_VERDICTS.json` (`:86-92`). The `llmll-driver` family had 17 cases and `spine.llmll` was
not among them, so neither stage E's nor stage J's verdict was protected against regression, in
the one directory whose whole purpose is frozen verdicts. There was also no crux for the stage-J
proved logic.

Two cases added, gate re-run:

| | cases | gate |
|---|---|---|
| before | 17 driver cases, 61 total | 61 passed, 0 failed |
| after | 19 driver cases, 63 total | 63 passed, 0 failed |

- `spine.llmll`, no flags, expect `safe` / exit 0. The verdict frozen is the split: five defs
  body-faithful (`stage-e-passes`, `stage-e-outcome`, `stage-j-pins`, `bad-barrier-count`,
  `stage-j-outcome`) and the `def-shell` orchestration at body-fallback.
- `crux-stage-j-coverage-pin.llmll`, `--strict-verified-core`, expect `refuted` / exit 1,
  localized to `stage-j-pins`. It is `spine.llmll`'s `stage-j-pins` with the `[J-COVERAGE]` post
  moved to 63 against a body that still admits 62. An **invented mutant**, not a shipped defect;
  the family's five shipped-defect cruxes are unchanged and `EXPECTED_VERDICTS.json`'s `note`
  says so.

**Measured both ways, which is the crux discipline.** The perturbation is refuted at
`error: body verification of 'stage-j-pins' failed — implementation does not satisfy
postcondition`, and perturbing the contract and the body TOGETHER verifies SAFE. So the frozen
verdict proves the pin is enforced against its own body; it does not prove the pin equals
`rfc_to_implementation.py:1413-1444`, which stays a reading obligation.

**Incidental, and worth knowing before citing one.** Constraint indices are per-`.fq` file. The
identical perturbation reports constraint #0 in the standalone crux and constraint #3 applied
inside `spine.llmll`, because the spine's `.fq` carries more constraints ahead of it. A constraint
number is not a portable citation.

---

### F-F. Unlogged `:init` output injects stray lines into the replay stream. New, live.

**Priority:** High. **Consumer:** compiler-engineer.
**Mechanism corrected by the engineer pass. The first pass called this an off-by-one; it is not.**

**Measurement, n = 3 console programs, one variable changed.**

| program | `:init` command | events matched |
|---|---|---|
| `discard` | `(wasi.io.stdout "init-ran")` | **0/2** |
| `ondone` | `(wasi.io.stdout "init-ran")`, plus `:on-done` | **0/2** |
| `noinit` | `(wasi.io.stdout "")` | **1/2** |

`discard` reports `DIVERGE seq 0: expected="step-0-ran"` against a program that demonstrably
prints `step-0-ran`. `noinit` is the same program with the `:init` string emptied and seq 0
matches.

**Mechanism.** `:init`'s command is performed through `llmll_perform` before the loop
(`CodegenHs.hs:1550-1551`) and is deliberately not logged (`:1543-1546`: "it is not logged, as it
was not before"). `replayOne` (`Replay.hs:141-153`) writes one input and reads one line with
`hGetLine`. `:init`'s bytes are therefore on the stream and in no event.

**The stray line count is `count '\n'` in `:init`'s output, so it is 0, 1, or unbounded** (engineer
pass). The two regimes behave differently and no single repair covers both:

| `:init` prints | stray lines | effect |
|---|---|---|
| `"init-ran"` | 0 | **fuses** with seq 0's output on one line, `init-ranstep-0-ran`; seq 0 alone is polluted |
| `"init-ran\n"` | 1 | a true shift that never recovers; every event after it is compared against its predecessor's line |
| `k` newlines | `k` | shift by `k` |

Fusion confirmed here on the byte stream: `discard` emits exactly
`i n i t - r a n s t e p - 0 - r a n \n`, one line, because `wasi.io.stdout` writes without a
trailing newline and `captureStdout` supplies one (`CodegenHs.hs:1461`).

**Why the correction matters, and it is the reason this came back.** The first pass's repair,
"consume and discard one leading line", fixes the newline-terminated regime and **breaks** the
fused one, where the single line carries seq 0's own output and discarding it destroys a good
event. A mechanism stated as an off-by-one invites exactly that fix.

**Implication.** Any console program with a non-empty `:init` command replays dirty, which is
every program the driver campaign has produced. A repair has to be regime-independent: log the
init command as its own event, or read the stream by event framing rather than by line
(which is F-I's fix and subsumes this one), or emit no init output onto the compared stream.

**Acceptance.** `discard` and a newline-terminated variant of it both replay 2/2 under one change.

---

### F-G. The settle entry's logged `""` is a constant, not a capture. New, live, narrowed.

**Priority:** High. **Consumer:** compiler-engineer.
**Narrowed by the engineer pass. The first pass's universal claim is refuted; see below.**

**What the first pass claimed:** every console program declaring `:done?` diverges on its final
event. **Measured false** (engineer pass): a program declaring `:done?` whose `:on-done` prints
exactly `"\n"` replays 2/2, exit 0.

**What is true is narrower and worse in kind.** The settle branch writes the terminating turn's
logged output as the string literal `""` (`CodegenHs.hs:1577`,
`hPutStrLn logHandle (eventJsonL seqN "stdin" line "stdout" "")`). It is a constant, not a
capture of anything the program did. So the entry:

- **matches** whenever the program happens to put a bare line terminator on the stream at settle,
  carrying no information about what settle actually produced, and
- **fails** only for programs printing nothing at settle.

A logged value that can pass while recording nothing is a weaker defect than one that always
fails, because it produces green replays that attest to nothing.

**Two sub-claims from the first pass that do replicate.**

1. `ondone` prints `ON-DONE-RAN` at settle and still reports `DIVERGE seq 1: expected=""`. So the
   logged expectation does not track on-done's output.
2. `:on-done`'s output is absent from the event log entirely. `LLMLL.md:1598-1600` specifies where
   it appears on stdout and says nothing about the log.

`spine.llmll` is affected: it declares `:done?`, prints nothing at settle (it terminates on a
throwaway `(pair 9 (wasi.io.stdout ""))`, `spine.llmll:467`), and so takes the failing branch.

**Where the first pass went wrong.** Three programs were measured, all diverged at settle, and the
result was generalized to the class. None of the three printed a bare newline at settle, so the
sample contained no instance of the matching branch and could not have exhibited it. The
generalization was not supported by n=3 and was not marked as an inference.

**Implication.** The settle entry needs to record what settle produced, or to stop being an event.
Either way the constant has to go. Interacts with F-I, which subsumes the alignment half.

**Acceptance.** The settle entry's logged value is a capture, so a program printing `X` at settle
records `X` and a program printing nothing records something replay can match without accident.

---

### F-H. Replay's `actual` field is a hardcoded literal. New, live.

**Priority:** Low, defence-in-depth. **Consumer:** compiler-engineer.
**Replicated exactly by the engineer pass; no correction.**

`Replay.hs:130` builds every divergence tuple as
`(evSeq e, evResultVal e, T.pack "<no output>")`. The third component is the string printed as
`actual=` by `app/Main.hs:2599-2602`. It is a constant, so a divergence where the program produced
the *wrong* output is indistinguishable in the diagnostic from one where it produced *none*.

**Witness.** `ondone` reports `DIVERGE seq 1: ... actual="<no output>"` for a turn on which the
program printed `ON-DONE-RAN`. `discard` reports `actual="<no output>"` at seq 0 for a turn whose
line was `init-ranstep-0-ran`. In both cases output existed and the diagnostic denies it.

`replayOne` already has the observed string in hand at `Replay.hs:150-153` and discards it,
returning `Bool`.

**Withdrawn sub-claim.** An earlier reading of this measurement recorded that `llmll replay` exits
0 while reporting total divergence. That was a measurement artifact: `$?` was read through a pipe
into `tail`. Re-measured without the pipe, replay exits 1 on divergence, which
`app/Main.hs:2603` (`when (replayMatched result /= replayTotal result) exitFailure`) is the code
for. The exit code is correct.

**Acceptance.** A divergence on a turn that produced output prints that output.

---

### F-I. Replay reads one line per event; an event is `count('\n')+1` lines. New, live.

**Priority:** Blocker for any claim resting on replay. **Consumer:** compiler-engineer.
**Found by the engineer pass. It subsumes F-F and F-G's alignment half and is larger than either.**

`replayOne` reads exactly one line per event (`Replay.hs:147`, a single `hGetLine`). The wire
bytes an event occupies are `output ++ "\n"` (`CodegenHs.hs:1461`, `putStrLn output` inside
`captureStdout`), while the event log stores `output` unframed. An event is therefore
`count('\n' in output) + 1` lines on the stream and one line to the reader, and the two agree
only in the single-line case.

**Two failure shapes, both measured by the engineer pass:**

| step output | replay | what goes wrong |
|---|---|---|
| two lines | **0/2** | the reader is a line behind from the first event on, and the DIVERGE report itself breaks, because the embedded newline splits the printed line |
| ends in `"\n"` | seq 0 **matches** | `T.strip` (`Replay.hs:151-152`) erases the trailing-newline discrepancy, the unconsumed blank line desynchronizes the stream, and the divergence surfaces at **seq 1** |

The second is the one to remember. A false green is followed by a divergence attributed to the
wrong turn, so the diagnostic actively misdirects: the turn it names is not the turn that broke.
`T.strip` is what converts a framing mismatch into a passing comparison, and it is also what makes
the unit tests pass (below).

**Implication.** The alignment fix cannot be a line-count adjustment at any of the three sites
F-F, F-G and F-I touch independently. Replay has to read by the same framing the emitter writes.
Adjudicate F-F, F-G and F-I as one change.

**Acceptance.** A console program whose step prints two lines replays 2/2, and a program whose
step output ends in a newline either matches for the right reason or diverges at the turn that
diverged.

---

### The root cause behind F-F, F-G, F-H and F-I: nothing runs `llmll replay`

Worth stating plainly, because it explains why four defects in one code path coexisted in a
shipped command. **No gate anywhere runs `llmll replay`.** The only coverage is three `runReplay`
unit tests against bash mocks, and their fixtures use framing the emitter does not produce:
`compiler/test/Spec.hs:5002-5003` logs expected values as `"Got: hello\n"`, terminated, where the
emitter logs `output` unframed. They pass because `T.strip` (`Replay.hs:151-152`) hides the
mismatch, which is the same call that produces F-I's false green.

So the tests that exist are green for the reason the command is broken. That is the
`crux-liveness-log-only` shape from this very directory: an instrument whose own output is what
keeps it quiet.

This is the gap `refute-crux-gate.sh` closed for verify verdicts and nothing has closed for
replay. F-E added `spine.llmll` to the verify gate this session; its event log still has no gate
at all.

---

## Operational note: the event log lands in the working directory

`CodegenHs.hs:1528` emits `openFile "<module>.event-log.jsonl" WriteMode` with no path handling,
so the log is created in the process's current directory unconditionally. `spine.llmll` reads its
inputs by repository-relative path (`experiments/rfc-swarm/data/...`, `spine.llmll:399-400`,
`:417`, `:432`), so it must be run from the repository root, and running it drops
`spine.event-log.jsonl` there. Measured: 1322 bytes, untracked, deleted after the run.

Not a finding on its own, and it interacts with F-F and F-G: the artifact this drops is the one
that cannot currently be replayed clean.

## Withdrawn items

- **F-A**, that the discarded terminal command is a defect or an undocumented contract. Refuted by
  `LLMLL.md:1555-1606` and `docs/getting-started.md:862`, which specify it, name it RC-4, name the
  observed failure mode, and give the remedy. The remedy was then measured to work.
- **F-B**, that higher-order list builtins are an ungated class. Refuted by three measurements
  (F-B above). Composition is gated cold on the default path, prelude membership never implied
  body-faithfulness, and the class is at least 37 builtins rather than three. The proposed fix
  would have gated three cases and implied 34 others were covered.
- **F-C**, that the JSON design record and the compiler disagree on the builtin count. True at
  HEAD `5a55fac`, closed in the working tree by the language-team track during this session.
- **F-G's universal form**, that every console program declaring `:done?` diverges on its final
  event. Refuted by a program whose `:on-done` prints `"\n"` and replays 2/2. The narrowed
  finding is worse in kind, not milder.
- **F-F's mechanism**, that the stray-line effect is an off-by-one. It is `count '\n'` in
  `:init`'s output, so 0, 1, or unbounded, and the two regimes need different repairs.
- **F-H's exit-code half**, that replay exits 0 on total divergence. A pipe artifact; replay
  exits 1.

## Null results

- **No new stage-E or stage-J port defect.** Both stages were replayed independently against
  `data/inventory-dispositioned.json` and all seven stage-J pins and the stage-E artifact
  reproduce. The gate halt is the shipped driver's behaviour on this data, not a port defect. n =
  1 artifact, which is all that exists; a second dispositioned inventory carrying a `barrier`
  field would exercise gate J's third condition for real and none is committed.

## What the two passes say about method

Both corrected findings, F-B and F-G, were filed on a **correct observation** with a **wrong
diagnosis**, and in both cases the wrong diagnosis pointed at a fix that would have made things
worse: F-B would have gated three builtins and implied 34 others were covered; F-G's framing as a
universal failure would have sent an engineer looking for why the settle entry never matches,
when the defect is that it sometimes does. F-F is the same shape one degree milder, where the
observation and the two-regime table are both right but "off-by-one" named a repair that breaks
half the cases.

The observation and the mechanism are separately checkable, and **the mechanism is the part that
got skipped.** In all three the observation was measured directly and the mechanism was inferred
from reading the code that produces it, which is exactly the failure mode F-A already recorded:
the generated `Main.hs` and its emitter are both accurate and both silent about the rule that
governs them.

The cheap discipline this implies, and it is not a new one, is that a finding's mechanism needs
its own witness. For F-B that is one strict-core caller, three lines. For F-G it is one program
that prints a newline at settle. Neither costs more than the finding did, and both were skipped
because the observation felt sufficient.

Not a coincidence worth over-reading: n = 3 corrected findings in one session is not a rate.

## What this leaves the compiler-engineer

| # | Finding | Priority | Shape of the fix |
|---|---|---|---|
| F-I | one line read per event, `count('\n')+1` written | Blocker for replay claims | read by the emitter's framing, not by line |
| F-F | `:init` output injects `count('\n')` stray lines | High | regime-independent; subsumed by F-I's framing fix |
| F-G | settle entry's `""` is a constant | High | capture what settle produced, or stop emitting the event |
| F-H | `actual` is a constant | Low | thread the observed string out of `replayOne` |
| (root) | no gate runs `llmll replay`; unit fixtures use framing the emitter does not produce | High | a replay case in CI, and fixtures generated rather than hand-written |

F-A, F-B and F-C are off the queue. F-F, F-G, F-H and F-I are one code path and one file
(`compiler/src/LLMLL/Replay.hs`, with F-F and F-I reaching into `CodegenHs.hs:1461` and
`:1543-1551`) and should be adjudicated together, because three of the four have repairs that
interact and two of them have repairs that conflict.

The one item outside the replay cluster is F-B's residue: a scope correction to the source comment
at `TypeCheck.hs:264-265`, already assigned.
