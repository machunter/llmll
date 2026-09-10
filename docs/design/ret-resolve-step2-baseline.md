---
name: ret-resolve-step2-baseline
title: "RET-RESOLVE step 2: the pre-change baseline, and what capturing it found"
status: "Rev 1, MEASURED 2026-09-10 at v0.23.0 against HEAD 585815a, with the preserved baseline binary. Step 2 of the nine-step sequence in docs/design/ret-resolve-implementation-plan.md; changes no compiler source. This is the PRE half only. Step 8 runs the same procedure with the patched binary and step 9 adjudicates the diff, so no acceptance verdict is available yet and none is claimed here. THE BASELINE IS VALIDATED, not merely captured: the census over a pristine tree with the preserved binary reproduces the committed ratchet EXACTLY, strict_pass identical at 98 files and ratio 0.9844 (695 of 706 body-faithful, 490 with no goal). Four findings. (1) The plan's cost estimate is high by about 5x: the sweep is 4m16s over 318 files with zero timeouts, not the 20 to 25 minutes budgeted. (2) diff -r compares 298 .liquid/*.smt2 SMT queries as well as 298 .fq files, and all 298 were checked for absolute paths and timestamps and carry neither, so the gate is finer-grained than the plan claims at no cost. (3) 20 files emit no .fq today, almost all deliberate negative fixtures that fail before emission; that is the correct baseline and not a sweep defect. (4) examples/totp_rfc6238/totp_filled.ast.json is broken by AST-RETURNS-KEY-1 and NOT by anything RET-RESOLVE fixes: all six of its definitions carry a discarded returns key, hmac-sha1-wrap declares bytes[20] through it, and renaming that one key takes the file from a hard type error to SAFE. RET-RESOLVE cannot resolve that head, because its body calls an unmodeled function."
date: 2026-09-10
author: compiler-engineer
consumers: [user, language-team, professor, documentation-lead]
---

# RET-RESOLVE step 2: the pre-change baseline

**One line.** The baseline reproduces the committed ratchet exactly, the gate is cheaper and
sharper than the plan assumed, and capturing it turned up a shipped example that fails for a reason
this row does not own.

## 1. What step 2 is

Step 2 captures the artifacts step 8 diffs against. It is one half of a procedure run twice: step 2
with the pre-change binary, step 8 with the patched one, step 9 adjudicating every non-empty diff per
channel with its direction named.

**No acceptance verdict is available from this document and none is claimed.** Half one is the `.fq`
bytes and half two is the channels those bytes cannot carry, and both are comparisons. This is the
left-hand side of both.

## 2. Preparation, and the traps that are real

1. **The binary was preserved before any rebuild**, at v0.23.0 from a clean `264e8c5` tree, and its
   version was confirmed rather than assumed. The plan's warning is correct and is the reason this
   worked: a later `stack build` overwrites the install root and the negative half then has nothing
   to run against.
2. **The sweep runs on a copied tree.** `llmll verify` writes a `.verified.json` sidecar beside the
   source, so a sweep over the repository dirties tracked files. Confirmed in practice: the sidecars
   appeared in the scratch copy.
3. **`-o` is required, not optional.** Without it the constraint file goes to `/tmp/<name>.fq`, and
   this corpus collides heavily on basenames (`world.llmll` twice, `hangman.ast.json` twice,
   `compose.llmll` twice). Every output is slugged by full path here.
4. **The census reads `git ls-files`.** A scratch tree needs a populated git index or the census
   reports an empty population. That happened once and cost a run.

## 3. What was captured

| Artifact | Contents |
|---|---|
| `pre/fq/` | 298 `.fq`, plus 298 `.liquid/*.smt2` |
| `pre/out/` | 318 stdout and stderr captures, scratch paths stripped so pre and post diff cleanly |
| `pre/record.json` | per-file exit code and duration |
| `pre/census.json` | the full census record |
| `pre/trust/` | 13 directories, 114 files, `verify --trust-report --json` |

**The artifacts are session-local and are deliberately not committed.** At 4m16s for the sweep, a
later session re-runs step 2 more cheaply than it stores 8.4 MB. What is worth keeping is this
record.

## 4. The baseline is validated, not merely captured

This is the control, and without it "captured a baseline" means nothing.

| Figure | Committed `BASELINE.json` / roadmap | This run |
|---|---|---|
| Population | 250 files | **250** |
| Body-faithful over functions with a goal | 695 / 706 | **695 / 706** |
| Ratio | 0.9844 | **0.9844** |
| Excluded, no goal | 490 | **490** |
| Fallback | 11 | **11** |
| `strict_pass` set | 98 files | **98, set-identical** |

The `strict_pass` sets were compared as sets, not as counts. They are identical.

Census outcomes: `pass` 98, `fallback` 83, `scaffold` 32, `no-goal` 31, `check-failed` 4,
`refuted` 2. Causes: `no-post` 246, `unfilled-hole` 244, `body-outside-fragment` 9,
`contract-post-outside-fragment` 2.

Those last two figures are the ones `FRAGMENT-BASIS-1` settled against, and they reproduce here.

## 5. Finding 1: the gate costs about a fifth of the estimate

**318 files in 256 seconds, zero timeouts.** The plan budgets 20 to 25 minutes of sweep time and
warns that a repeated sweep per adjudication round is a cost worth avoiding.

Four files exceed 10 seconds and two dominate:

| File | Sweep | Census |
|---|---|---|
| `examples/heartbleed/secure-channel/agent-fill/sc-channel-agentfilled.llmll` | 57.4s | 92s |
| `examples/heartbleed/secure-channel/sc-channel.llmll` | 47.0s | 84s |
| `examples/secure-channel-emergent/work/spine.ast.json` | 26.2s | 35s |
| `examples/secure-channel-emergent/audit/mutation-check/spine-gotofail.ast.json` | 13.1s | |

**This changes the economics of step 9.** The plan's risk 9 treats a repeated sweep as a cost that
argues for fewer adjudication rounds. At four minutes it does not. There is also now no reason to run
half one without half two.

## 6. Finding 2: `diff -r` compares the SMT queries too, and that is free precision

liquid-fixpoint writes a `.liquid/` subdirectory beside the output file, holding one `.smt2` per
constraint file: the query it hands to Z3. A `diff -r fq-pre fq-post` therefore compares **596 files,
not 298**.

**All 298 `.smt2` files were checked for absolute paths and for date stamps. Neither appears in any of
them.** So they are byte-stable across runs and machines, and including them is sound.

This is worth stating because it is the opposite of the usual case. A generated intermediate is
normally the thing that breaks a byte-comparison gate. Here it strengthens it: two artifacts move
when the emitter's output moves, and the second is closer to what the solver actually decides.

One consequence to record so it is not mistaken for a defect later: a naive count of the output
directory returns **299**, because `.liquid` is itself an entry.

## 7. Finding 3: twenty files emit no `.fq`, and that is the correct baseline

Half one compares 298 constraint files, not 318. The 20 absences are almost entirely deliberate
negative fixtures that fail before emission: fourteen under `compiler/test/fixtures/resp-fact/`,
two circular-import fixtures, an unsound-pattern fixture, and a fixture with a call to an unknown
function.

The 108 non-zero exits decompose as **68 refuted-postcondition** (bad twins behaving correctly) and
**40 check-time errors**. Neither number indicates a sweep defect.

**The acceptance criterion needs one sentence the plan does not have.** A file that emits no `.fq`
today can emit one after the pass, through channel 1 (crash to verdict), and that is an intended
repair rather than a gate failure. Half one's "empty diff" must therefore be read as "empty diff
except for enumerated channel-1 arrivals", in the same way half two is already read as "empty except
for the enumerated demotion set".

## 8. Finding 4: a shipped example is broken, and this row does not own it

`examples/totp_rfc6238/totp_filled.ast.json` fails at check time today:

```
error: type mismatch in 'dynamic-truncate': expected bytes[20], got ? (an unannotated return type).
A bytes[20] value carries a length the verifier must prove at this position, and inference cannot
supply it; annotate the callee's return type.
```

**The author did annotate the callee's return type.** All six definitions in that file carry a
`returns` key and a null `return_type`, and `hmac-sha1-wrap` declares
`{"kind": "bytes", "length": 20}` through it. `AST-RETURNS-KEY-1` records that the parser discards
that key. So the compiler threw the annotation away and then emitted a diagnostic instructing the
author to write the annotation they had written.

**Measured, not argued.** Renaming `returns` to `return_type` on those six heads, changing nothing
else in the file, moves it from that error to `SAFE (liquid-fixpoint)`, with three
`W-BODY-FALLBACK` warnings that are unrelated to the key.

**RET-RESOLVE would not fix this file.** `hmac-sha1-wrap`'s body is `(hmac-sha1 key message)`, a call
to the unmodeled function the file marks `weakness-ok`. Nothing in the body determines a return type,
so the Kleene pass leaves the head a wildcard and the error stands. Only the discarded annotation
carries `bytes[20]`.

**This is the first reaching consequence of `AST-RETURNS-KEY-1`.** The row was filed on the strength
of 24 heads whose declared returns are never checked, which is a silent gap. This is not silent: it
removes a shipped example from verification and reports a reason that contradicts the source. Route
it to that row.

## 9. What is owed

1. **Step 3 onward is unblocked by this document and unstarted.** Steps 1 and 2 are both measurement
   and both complete. Step 3 is the first code.
2. **The plan owes two small corrections**, both to sections this document measured against: its
   risk-9 cost estimate, and its half-one acceptance criterion per section 7 above. Its risk-2
   blind-spot list still owes the fifth entry that step 1 found.
3. **`AST-RETURNS-KEY-1` gains section 8 as evidence**, and the `examples/` fix it implies is a
   six-key rename in one file that is independently verifiable in one command.
