---
name: driver-ll-phase4c-implementation-plan
title: "DRIVER-LL sub-phase 4c: implementation plan and running record"
status: "PARTIALLY IMPLEMENTED on branch `driver-ll-4c/stages-d-f-g`. Two increments landed and pushed, both green: `36f6476` shape.llmll (the proved content-shape channel, four body-faithful defs, three cruxes, refute-crux gate 71 to 75) and `3dc0162` the registry tables (behaviour-preserving, `stage-ported?` deliberately unchanged). THE SEQUENCER BODIES ARE NOT WRITTEN and are the remaining half; stages D, F and G are still stubbed, so the sub-phase is not acceptance-testable yet. Three findings came back, two of them correcting this plan's own predecessor: `regex-match` EXISTS so no narrowing is needed, the landing order INVERTS (D before F before G, by data dependency), and 4c constructs ConditionUnmet which proposal section 9.2 item 1 does not say. Delete or fold when 4c closes."
date: 2026-08-06
author: compiler-engineer
consumers: [compiler-engineer, language-team, experiment-lead, documentation-lead, user]
---

# DRIVER-LL sub-phase 4c — implementation plan and running record

Port stages D, F and G into `tools/llmll-driver/` as `def-shell` orchestration,
adding the content-shape validation channel
[`validate.llmll`](../../tools/llmll-driver/validate.llmll)`:56-63` reserved for
this sub-phase. Read proposal §9.2 and §3.6.1 first.

## What landed

**`36f6476` — [`shape.llmll`](../../tools/llmll-driver/shape.llmll), the proved channel.**
Four defs, **all four body-faithful and SAFE (liquid-fixpoint) on the first
attempt**: `extraction-conforms?`, `core-conforms?`, `dispositions-conform?`,
`barrier-condition-met?`. Three cruxes, frozen. Refute-crux gate **71 → 75
passed**.

**`3dc0162` — the registry tables, behaviour-preserving.** `stage-tag-count`,
`stage-tag-upper`, `stage-shape`, `stage-pre-count`, `stage-pre-mode`,
`stage-pre-proj`, and `stage-pre-path` / `stage-pre-key` / `stage-agent-label`
generalized to take an index. Verified identical rather than assumed: 4b suite
**8 passed**, refute-crux **75 passed**, pytest **132 passed**.

**`stage-ported?` is deliberately still 4b's three.** Flipping D, F and G before
their bodies exist marks three stages ported whose delegation path knows nothing
about tags, three-artifact preconditions or shape checks. That is a tree which
compiles and lies, and it is worse than one that does not compile.

## Why every parameter in the proved channel is a bool or an int

Two reasons, and the second was measured rather than reasoned.

**Subject-neutrality.** `verdict-of` earns it structurally by taking no string.
A content validator taking `Json` forfeits it: every row of every census would be
in scope and nothing but review would stop a body from reading one.

**Fragment preservation, and it corrects the plan.** The plan asserted LLMLL has
no regex and designed a `string-to-int` round-trip around it. **`regex-match`
exists** ([`TypeCheck.hs:143`](../../compiler/src/LLMLL/TypeCheck.hs),
[`Syntax.hs:502`](../../compiler/src/LLMLL/Syntax.hs)), so `check_extraction`'s
`^N\d+$` and `check_dispositioned`'s `^C[1-6]$` port **verbatim**. The round-trip
would have rejected `N01`, which the reference accepts, so the correction avoided
a silent narrowing. But `LLMLL.md:326` puts `regex-match` in the boolean-builtin
class, never auto, and `LLMLL.md:356` states the consequence: the carrying
function falls to `erBodyFallback`. So the regexes belong in the `def-shell`
extractor and the proved core stays in QF-LIA. Both reasons point the same way.

## Refute-crux measurements

Discrimination measured, not asserted, by verifying each body against post
subsets:

| Crux | Measured |
|---|---|
| `crux-shape-row-count-fitted` | four forward posts **SAFE**; `[D7-NO-HARDCODE]` alone **refutes** |
| `crux-shape-accepts-malformed` | all posts **SAFE** including the converse; `[D7-ROWS]` alone **refutes** |
| `crux-shape-barrier-vacuous` | both posts refute; **does not claim to discriminate** |

**The fitted mutant needs no second run to fail**, which is what makes it worth
freezing. Stage D runs two blind extractors and the committed pair disagrees on
census size: `extraction-a.json` has **119** normative rows, `extraction-b.json`
has **125**. A validator fitted to A rejects extractor B inside the **same run**,
on the stage whose docstring says blindness is structural. §7:288-291's "the next
run" arrives one loop iteration later.

The pair covers both directions: no forward post catches a validator that rejects
conforming input, and no converse post catches one that accepts too much.

`crux-shape-barrier-vacuous` refutes through both its posts because `[G6-CLOSED]`
is an equality between two booleans and so determines `result` entirely, making
`[G6-NOVACUOUS]` a named consequence in the sense `[V7-NO-FLOOR]` is one and
`gate.llmll`'s `[S6-REPORTED]` is one. Stated separately for findability, not as
an independent obligation.

## Where the port disagrees with a settled document

### 1. 4c constructs `ConditionUnmet`, and §9.2 item 1 does not say so

`check_dispositioned` holds six checks. Five are `require` and record `failed`
(`:483`, `:486`, `:487`, `:490`, `:499`). The sixth, `:493`, is **`require_spec`**
citing `driver-spec sec 6:229-231`, so proposal §3.5's rule makes it spec-defined
and it records **`stopped`**. The rig already asserts exactly that
(`test_rfc_pipeline_integration.py:334`, mode `bad-barrier`).

So **4c builds three of `Outcome`'s four arms where 4b built two.** §9.2 item 1
records that 4c constructs no `PartialThenHalt`, which holds, and stops there.

`[V7-ONLY-TWO]` remains **true** as stated, being a property of
`verdict-outcome`'s codomain rather than an invariant of the port. Its `:source`
prose is scoped to 4b and is **left alone**: a shipped proved module is not where
a later sub-phase's arithmetic goes. **Language-team.**

Consequence for the build: the barrier halt must **not** route through
`verdict-outcome`, which `[V7-NO-STOP]` correctly forbids for the three stages 4b
ported, none of which has a spec-defined halt. It uses the sequencer's existing
`halt-with rn k ConditionUnmet detail "driver-spec sec 6:229-231"` channel.

### 2. The landing order inverts

The plan said F, then G, then D, smallest first. The **data dependency runs the
other way**: F reads `04-reconcile/data/extraction-a.json`, which D stages there
(`:663-665`), and G reads the core F writes. A tree with D stubbed cannot
exercise F or G end to end, because the 4a stub writes each stage's own declared
outputs and not the directory the next stage reads. "Smallest first" was an
authoring argument and `shape.llmll` already discharged it. **The three land
together.**

### 3. The dict-or-list tolerance is at three sites, not two

F-20 named `:713` (stage F) and `:732` (stage G). `:482` is a third, inside
`check_dispositioned` itself. The port's narrowing must cover all three or one arm
silently keeps the tolerance. **Language-team**, as an F-20 amendment.

## Divergences from the reference, disclosed

1. **Mode `PROJECT`'s prompt bytes.** The reference emits
   `json.dumps(..., indent=1)` and, for `core_ids`, `json.dumps(sorted(set))`.
   LLMLL has `json-serialize` and **no sort builtin**, so the port carries the
   same members with different whitespace and, for `core_ids`, in the artifact's
   own order. §2.1's abstraction function retains a field when some specification
   obligation mentions it, and none mentions prompt whitespace or the element
   order of a prompt blob. `barriers-json` carries the same disclosure already
   (`sequencer.llmll:631`).
2. **Barriers substituted before the precondition values, not fourth of five.**
   The reference's keyword order is `rfc_text, inventory, core_ids, barriers,
   scope` (`:735-742`), and order matters because a substituted value carrying a
   later placeholder would be expanded by it. The port substitutes the barriers
   **constant** first, which cannot contain any placeholder, so no result can
   differ. Strictly safer than the reference's order rather than merely different.
3. **F's `merged` is not carried into any binding.** `:706` names extractor A's
   unmerged output `merged`; `reconcile.py` reads the pair and writes only
   `reconciliation.json` (`:75-76`, `:155-156`). §9.2 item 5 forbids inventing a
   merge, so the port reproduces the read and does not adopt the name.
4. **The duplicated barrier predicate.** The plan preferred sharing the row-level
   predicate with `spine.llmll:394` and held disclosed duplication as the fallback
   if spine's re-verify regressed. **The fallback was taken for a different
   reason:** sharing needs either shell JSON code inside the proved module,
   breaking `validate.llmll`'s precedent, or a second new module, and both cost
   more than the ~15 lines save. The reference itself enforces the condition twice
   on purpose (`test_rfc_pipeline_integration.py:325-329`). Retires at 4f, where
   the two programs unify.

## Not done: the sequencer bodies

The remaining half, with the design settled so it is not re-derived.

**The `Body` type change.** Today
(`sequencer.llmll:299-300`): `(k, (start, (pre-text, (idx, (names, acc)))))`.
Replace `pre-text: string` with `pvals: list[string]` and append `tag: int`:

```
(k, (start, (pvals, (idx, (names, (acc, tag))))))
(int, (int, (list[string], (int, (list[string], (string, int))))))
```

`pvals` replacing `pre-text` keeps the arity change to one field. **No separate
precondition index is needed**: the number read so far is `(list-length pvals)`.
Accessors move to `b-pvals` = `first (second (second …))`, `b-acc` gains one
`second`, and `b-tag` = `second (second^5 …)`. `mk-body`, `b-with-pre` (becomes
`b-add-pval`), `b-with-names`, `b-advance` and `fresh-body` follow.

**The `Pre` loop** mirrors `Src`'s existing idiom exactly, which is the reason
that idiom is worth following rather than inventing a second: `begin-body` reads
`stage-pre-path i 0` when `stage-pre-count i > 0`; `pre-step` projects per
`stage-pre-mode` (RAW / PARSE / PROJECT via `stage-pre-proj`), appends to
`pvals`, and re-enters `Pre` while `(< (list-length pvals) (stage-pre-count i))`,
else `after-pre`. A parse failure or a missing projected member halts `Malformed`
through `halt-verdict`, as B's parse already does.

**`render`** folds over `range 0 (stage-pre-count i)` substituting
`stage-pre-key i j` with `list-nth pvals j`, after `{{rfc_text}}` and the
barriers constant, plus `{{extractor}}` from `stage-tag-upper i j` for D.
`range` exists (`TypeCheck.hs:133`).

**Tag threading.** `agent-dir c i j` = `art-dir c i j` (the agent's directory IS
the directory of the invocation's declared output, which already holds for
`03-extraction/a` and `/b`); `prompt-file c i j`; `delegate-cmd rn i j rendered`
using `art-path c i j`; `outp-*` keyed on `j`. After tag 0's `Outp` completes,
re-enter `Delegate` for tag 1 while `(< (+ tag 1) (stage-tag-count i))`.

**D's copy fan-out**, a new phase with a loop over the `00-source` listing:
`wasi.fs.copy` each file into `03-extraction/<tag>/`, then write `rubric.md`
there. **The listing must NOT reuse `names-of`** (`sequencer.llmll:968-974`),
which filters to `.txt` via `txt?`; the reference copies every file (`:648-650`)
and `audit_blindness`'s allowed set (`:1836-1837`) lists `PROVENANCE.json`, so
filtering would silently drop a legitimate input.

**D's write-back.** `check_extraction` mutates its argument (`:425-427`) and D
then sets `doc["extractor"]` and rewrites its own declared output (`:657-658`);
D's log line reads the `counts` that mutation produced (`:660-661`). The
committed `extraction-a.json` carries `counts: {normative: 119, excluded: 85}`,
so the write-back is observable in the artifact and is not optional.

**The shape checks** read the declared output in `Outp`, extract facts with
`regex-match` in the shell, and call `shape.llmll` per `stage-shape i`. The shape
verdict and the floor verdict combine at the call site; both are `Malformed` on
failure and route through `verdict-outcome`, except G's barrier condition.

**Then:** `stage-ported?` flips D, F and G in the same change; `test_driver_ll_4c.py`
(~14 tests, including the port-side twin of the iteration-`b` cell landed at
`43ddb95`); `scripts/driver_ll_cover.py` extends from 31 cells; four
`EXPECTED_VERDICTS` additions for the changed modules;
[`tools/llmll-driver/README.md`](../../tools/llmll-driver/README.md).

## Gates at the checkpoint

Haskell **1651 examples, 0 failures** (measured, unchanged: no Haskell touched).
Python **132 passed, 1 skipped**. Refute-crux **75 passed** (71 before).
Doc lint **860 citations, all resolve**. Version gate **PASS at 0.14.87**.
`validate`, `registry` and `sequencer` all still SAFE.

**No compiler change is implied by this sub-phase**, and that was checked rather
than assumed: `json-array`, `json-get{,-string,-int,-bool}`,
`list-{filter,fold,map,length,nth}`, `range`, `regex-match`, `string-char-at`,
`string-to-int` and `wasi.fs.copy` all exist.

## Routing

- **language-team**: 4c constructs `ConditionUnmet` and §9.2 item 1 is silent on
  it; F-20's tolerance is at three sites, not two; §9's 4c row will owe a
  disclosure statement for `shape.llmll` as new proved surface, on the precedent
  `validate.llmll` set at 4b.
- **compiler-engineer**: the sequencer bodies above. `PROC-TIMEOUT-1` stays open
  and D, F and G each inherit an unreachable overrun halt; no cover cell may
  claim to exercise them.
- **documentation-lead**: nothing yet. No user-visible CLI change, no schema
  delta, no version movement. The driver's own surface is
  `tools/llmll-driver/README.md`, which is not one of the six.
