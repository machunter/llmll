---
name: driver-ll-program-unification-proposal
title: "DRIVER-LL program unification: the definition nineteen documents use and none wrote"
status: "Rev 5, 2026-09-11. JOB (a) SPLITS IN TWO and Rev 1 to Rev 4 conflated them, which the implementation found and the design did not. Section 2 clause 3 requires stage-ported? deleted; section 4.3 describes a merge that CANNOT delete it. Measured: started-step branches on stage-ported? and the unported path writes a STUB, and the section 4.3 merge changes only which def-main survives. (a1) ONE BINARY is graded by section 2 clauses 1, 2, 4 and 5, is ungated, and four commits have landed toward it. (a2) RETIRE THE STUB TABLE is graded by clause 3 plus a new clause that every stage writes a real artifact, and it is SUB-PHASE SIZED for three measured reasons in section 4.10: the spine's logic is a 17-arm state machine and not callable functions; stage M's artifact count is holes TIMES attempts and the registry is keyed [i: int] with a STATIC stage-out-count, so stage M fits no registry entry; and the Ctl arm shape is one delegation per stage. JOB (b) DEPENDS ON (a2), NOT (a1): a driver that stubs five of sixteen stages cannot replace rfc_to_implementation.py, so the critical path is longer than the G0 row states. (a2) needs a stage-M multiplicity design that DOES NOT EXIST and that this proposal deliberately does not write. Also corrected: jset is the FIFTH silent homonym, which Rev 3 named without classifying. Rev 4, 2026-09-11: Rev 4 records what the first implementation commit measured and the design did not predict: `verify-safe?` was in the COLLAPSE set by BODY EQUALITY, the move was TRIED, and TWO COVERS FAILED. 4d pins the sequencer's copy as an abstraction function over the compiler's transcript; 4e lists the wave's copy in SEAM, the wave functions that read another process's stdout and prove nothing about it. Identical bodies, two seams, two pins. Section 2 clause 2 now carries `verify-safe?` as a NAMED EXCEPTION and the COLLAPSE set is SEVEN. The general rule is in section 4.9: body equality is NECESSARY and NOT SUFFICIENT for collapsing a duplicate, because a pin is about the seam a copy sits on and not about its behaviour. Checked against the other seven: three are pinned at their CALL SITES, which a move does not touch, and four carry no pin. Rev 3, 2026-09-11: Job (b) stays gated on Phase 4 acceptance. Rev 3 records the section 4.7 DECISION the user made: Cfg is two records sharing a name, and the wave's is DERIVED from the campaign's rather than merged with it or left independent. wave's type is renamed WaveCfg and one function wave-cfg-of constructs it. That rename removes all four SILENT HOMONYMS at their source, so Rev 2's blocking risk 2b is UNBLOCKED. New at Rev 3, measured BEFORE the decision was adopted rather than after: five of the wave's eight fields derive from the campaign record and THREE DO NOT, so wave-cfg-of cannot be total over Cfg alone and takes tree, err0 and proto0 as parameters. Two behaviour changes are named: the .wave workdir default disappears, and the wave's --agent-cmd parsing is deleted rather than reconciled, which is the one operator-visible flag job (a) removes. Rev 2, 2026-09-11: Rev 2 folds a compiler-engineer probe that REFUTED Rev 1's escape route and found a defect class Rev 1 did not know about. MEASURED: a colliding (open X) warns per name and EXITS 0, --strict does NOT escalate it, and the IMPORTED binding wins; when both arms carry the same type the program checks clean and nothing distinguishes it; qualified function calls are NOT supported, so Rev 1's import-without-open escape does not exist. The sequencer/wave collision set is 17 functions, 3 constructors and the type Cfg; sequencer/spine collide on NOTHING, so spine merges first and wave last. The 17 split into COLLAPSE 8, SILENT HOMONYMS 4 and LOUD HOMONYMS 5, and the SILENT four are the finding: cfg-workdir reads slot 0 in the sequencer and slot 1 in the wave, both returning string, so a shadowed call would use a stage filter as a directory path and every gate would pass. Cfg is TWO RECORDS SHARING A NAME, ten slots against eight with no slot meaning the same thing; section 4.7 puts three readings and recommends the third. Rev 1's risk 2 is RETIRED by census: zero sibling def-to-def calls across all 11 defs. Rev 1 also named body-faithful-all? as a shared helper and it is not one. Rev 1, 2026-09-11: Defines program unification, which the G0 roadmap row records as named by nineteen places that all USE it and none DEFINE it. It is TWO jobs with DIFFERENT GATES and they must not be one work item: (a) merge the three executables, UNGATED and startable now; (b) port the plumbing campaign section 5.3 excluded, GATED on Phase 4 acceptance, which is the live clause 2 run. (a) is also a PREREQUISITE of (b). Measured for this proposal: job (a) needs NO compiler change and no feature-freeze exception, and it cannot break a proved core, because the three executables hold 424 def-shell against 11 def and all 11 are leaves composed by def-shell. The completion test is decidable today and its sharpest clause is the ORPHAN SET, which must not grow. Corrects one carried figure: the tree holds 14 library modules, not the fifteen the roadmap says."
date: 2026-09-11
author: language-team
consumers: [compiler-engineer, user, documentation-lead, experiment-lead]
---

# DRIVER-LL program unification

Program unification is the last item on the `DRIVER-LL` critical path before the
Phase 5 conformance claim, and it is the only one with no design. The G0 row in
[`compiler-team-roadmap.md`](../compiler-team-roadmap.md) records the shape of the
problem: the phrase appears in nineteen places that all use it and none define it,
and what it names is two jobs under one name.

This proposal writes the definition, separates the two jobs by their gates, and
measures the one question that decides whether job (a) is safe.

## 1. The definition

**Program unification converts the driver from three programs that share a
directory into one program plus a library set, so that every predicate answering
a question about "the driver" has exactly one implementation and one answer.**

**The defect it repairs is not file count.** It is that the driver's
self-description is per-executable while the questions asked of it are
campaign-wide. Four instances are live today, and each is a sentence true of one
executable and false of the driver.

| Site | What it says | What is true |
|---|---|---|
| [`registry.llmll`](../../tools/llmll-driver/registry.llmll) `stage-ported?` | false for E, G2, J, L, M | all five are ported: E, G2, J and L in [`spine.llmll`](../../tools/llmll-driver/spine.llmll), M in [`wave.llmll`](../../tools/llmll-driver/wave.llmll) |
| [`sequencer.llmll`](../../tools/llmll-driver/sequencer.llmll) `verify-safe?`, `body-faithful-all?` | two implementations | one behaviour, duplicated from `wave.llmll` |
| `wave.llmll` `flag-value` | copied from `sequencer` | one behaviour, copied |
| `spine.llmll` header | stage A is not here | true of the spine, false of the campaign |

"Merge the files" is the wrong framing. The merge is the mechanism. One answer per
question is the goal, and it is what makes the completion test in §2 decidable.

## 2. The completion test

Unification is done when all four hold.

1. `_programs()` in [`test_driver_ll_callers.py`](../../scripts/tests/test_driver_ll_callers.py)
   returns exactly one name.
2. No function body appears in two modules, **except `verify-safe?`**, which is a
   named exception added at Rev 4 and is described in §4.9.
3. `stage-ported?` is **deleted, not corrected**. A per-executable table has no
   meaning once one executable holds every stage. Flipping its five false arms to
   true would preserve the category error and hide it better.
4. **The orphan set is unchanged at `{liveness, shell}`.**

5. **No `open-shadow-warning` appears on the unified program's `llmll check`
   output.** Added at Rev 2. §4.4 measured that this warning exits 0 and that
   `--strict` does not escalate it, so the gate greps the tool's own output line. An
   exit status reports success over a live shadow.

**Clause 4 is the sharp one and it is worth stating why.** The orphan test in
`test_driver_ll_callers.py` records that `fill` and `token` left the orphan set
when `wave.llmll` acquired a `def-main` and imported them, "which is the remedy an
orphan takes: an import from a program, not a call site". When `wave` stops being
a program, they return to the orphan set unless the unified program imports them.
**A grown orphan set means the merge dropped an import**, and the existing cover
names which one.

## 2.5 Rev 5: job (a) is TWO jobs, and Rev 1 to Rev 4 conflated them

**The inconsistency, found during implementation and not during design.** §2 clause 3
requires `stage-ported?` to be deleted. §4.3 describes a merge that cannot delete it.
Both were written at Rev 1 and neither was checked against the other.

**Measured at Rev 5**, in `sequencer.llmll`'s `started-step`: the stage loop branches
on `stage-ported?`, and the unported path calls `write-cmd`, which is a `mkdir` and a
write of `stub-body`. The merge §4.3 describes changes which `def-main` survives. It
does not touch that branch. **Five of sixteen stages would still write stubs in a
driver that had passed every clause of §2 except clause 3.**

So job (a) splits:

**(a1) ONE BINARY.** Delete two `def-main` declarations, add the outer sum of §4.3,
dispatch in `:step`. Retires the three-program structure and every name collision.
**Does NOT retire `stage-ported?`.**

**(a2) RETIRE THE STUB TABLE.** Give stages E, G2, J, L and M real bodies inside the
sequencer's stage loop, then delete `stage-ported?`.

**Acceptance splits with them.** (a1) is graded by §2 clauses 1, 2, 4 and 5. (a2) is
graded by clause 3 plus a clause Rev 5 adds: **every stage writes a real artifact and
none writes a stub**. Clause 3 alone is not enough, because deleting the table without
landing the bodies would leave `started-step` with one arm and the wrong one.

**THE CAMPAIGN CLAIM IS THE REASON THIS SPLIT MATTERS.** If (a1) ships and the
roadmap records "program unification complete", the driver still stubs five of sixteen
stages and the record says otherwise. The G0 row names program unification as one step
before Phase 5; it is two, and the second is sub-phase sized.

**Job (b) depends on (a2) and not on (a1).** Campaign §8.1 retires
`rfc_to_implementation.py` when the LLMLL driver can replace it. A driver that stubs
five stages cannot. Rev 1 to Rev 4 sequenced (b) behind "program unification" without
saying which half, and the half it needs is the larger one.

## 3. Two jobs, two gates

The roadmap states both gates and does not draw the conclusion. They are stated
here as the reason the two jobs cannot share a work item.

- **(a) merge the three executables. UNGATED.** Nothing waits on it.
- **(b) port the plumbing campaign §5.3 excluded. GATED on Phase 4 acceptance**,
  per the campaign's §8.1 and the §5.3 Rev 2 qualification, which lifts the
  porting exclusion "at the retirement step" and not before. Phase 4 acceptance is
  acceptance clause 2, which is the live run
  ([`../../experiments/rfc-swarm/CLAUSE-2-PRE-REGISTRATION.md`](../../experiments/rfc-swarm/CLAUSE-2-PRE-REGISTRATION.md)).

**(a) is also a prerequisite of (b).** Job (b) ports an operator CLI surface:
`--agent-cmd`, `--workdir`, `--self-test`, `--audit-blindness`. In a driver that is
three programs, "which program takes `--workdir`" has no answer. Port the surface
first and it is ported three times, or once and arbitrarily.

## 4. Job (a): merge the three executables

### 4.1 It needs no compiler change

[`LLMLL.md`](../../LLMLL.md) §9.5 makes a module without a `def-main` a library:
"Without a `def-main`, the compiler generates a **library only** (no `Main.hs`)."
[`TypeCheck.hs`](../../compiler/src/LLMLL/TypeCheck.hs) rejects a duplicate
`def-main` **inside one module**, not across modules.
[`CodegenHs.hs`](../../compiler/src/LLMLL/CodegenHs.hs) filters `def-main` out of
the library emission and writes `Main.hs` only when one is present. Nothing in
[`Module.hs`](../../compiler/src/LLMLL/Module.hs) rejects importing a module that
carries one.

So job (a) is a refactor inside the existing module system. No new builtin, no new
syntax, no FFI tier, no WASI capability. Nothing under the feature freeze.

### 4.2 The `wave.llmll` objection is correct, and this proposal adopts its remedy

`wave.llmll` states why `flag-value` is copied: "Copied rather than imported:
`sequencer` is a program, not a library, and importing it would put its whole stage
loop behind this module." That is a hygiene argument about what a library should
expose, not a compiler limitation, and it is right. `sequencer.llmll`'s
`verify-safe?` comment names the remedy already: "sharing needs a fourth module,
and the 4c barrier duplication already set the precedent that retires at program
unification."

This proposal adopts that remedy rather than arguing with it.

### 4.3 Shape

- `sequencer` keeps the single `def-main`.
- `wave` and `spine` lose theirs and become libraries the unified program imports.
- A new library module takes the **COLLAPSE set of §4.6**, which is eight functions
  and not the three Rev 1 named. The name is the engineer's call.
- `stage-ported?` is deleted.

**One `def-main` means one state type, and the three programs have three.** Measured
at Rev 2:

| Program | State | Control arms |
|---|---|---|
| `sequencer` | `(Run, Ctl)` | **34** |
| `wave` | `(Wv, WCtl)` | **12** |
| `spine` | `int` | linear counter |

`def-main :step` takes a state of one type, so the merge is not two deletions. It is
an outer sum over the three machines plus a dispatching `:step`, with each machine
keeping its own arms in its own module. Flattening `Ctl` and `WCtl` into one 46-arm
control type is rejected: it collides on `Boot`, `Ending` and `Done` by
construction, and §4.4 shows what a collision costs.

**`spine`'s `def-main` declares four fields, not five**: `:mode`, `:init`, `:step`,
`:done?`, with no `:on-done` and no `:status`. The unified exit path must decide
what a spine-phase termination reports. New behaviour must not ride in on a
refactor, so it exits through the sequencer's existing `drv-status` unchanged.

**Rev 1 named `body-faithful-all?` as a shared helper and it is not one.** Measured:
`sequencer.llmll` holds `body-faithful-all? [out: string] -> bool`, and
`wave.llmll` holds `body-faithful? [out: string target: string] -> bool`. Different
names, different arity, and different second conjuncts: the sequencer excludes
`body-fallback:` and the wave checks that `target` appears. They do not collide and
one cannot absorb the other. The `verify-safe?` comment's phrase "duplicated with
one strengthening" describes this pair, and the two predicates test different
things, so that phrase is worth re-reading before anyone relies on it.
`verify-safe?` itself IS identical in both and does collapse.

### 4.4 MEASURED at Rev 2: the escape Rev 1 assumed does not exist

Rev 1 reasoned that a colliding `open` could be avoided by importing without it and
using qualified references. A `compiler-engineer` probe over a purpose-built
two-module case refuted that, and the four results below are the reason §4.6 exists.

| Probe | Result |
|---|---|
| Colliding `(open X)` | `open-shadow-warning` per name, **exit 0** |
| Library arm `string`, local arm `int` | `error: type mismatch in 'Boot': expected string, got int` |
| Both arms `int`, type-discriminating consumer | **checks clean, exit 0, nothing distinguishes** |
| `(import X)` with no `open`, qualified call | `dotted function name ... in app position is not supported; use (open <module-path>)` |
| `llmll check --strict` on the collision | still **exit 0** |

Three consequences, and each one changes the plan.

**The collision is diagnosed and not blocked.** `Diagnostic.hs` emits a named
warning, so it is not silent. `llmll check` exits 0 anyway, and `--strict` does not
escalate it, because `--strict` covers unbound variables and unknown functions. Any
acceptance gate for this work must grep for `open-shadow-warning` on the tool's own
output. An exit status will report success.

**The imported binding wins.** The string-against-int probe proves it: the local
`int` arm was rejected in favour of the imported `string` signature. This is the
opposite direction from `TypeCheck.hs`'s note that local `STypeDef`s win the
alias-map union, which governs type aliases and not constructors.

**Qualified references are not an escape, because they do not exist for functions.**
Type names do resolve unqualified without `open`. Functions in application position
do not, and the compiler's own message directs the author back to `open`. So a
colliding name must be renamed or collapsed. It cannot be hidden.

### 4.5 Merge order is forced by the collision data, not chosen

`sequencer` and `spine` collide on **nothing**: no function, no constructor, no
type. `wave` and `spine` collide on `jset` alone. Every other collision is
`sequencer` against `wave`.

**CORRECTED at Rev 5: `jset` is the FIFTH silent homonym, and Rev 3 named it without
classifying it.** Measured: the wave's falls back to the ORIGINAL object
(`(unwrap-or (json-set o k v) o)`) and the spine's to an EMPTY one
(`(unwrap-or (json-set o k v) json-object)`), on identical signatures. Opposite
behaviour when `json-set` fails. The silent count in §4.6 is five, not four. Naming a
collision is not classifying it, and this is the second time in this proposal that a
name-level census missed a behaviour-level difference; the first was `verify-safe?`
in §4.9.

So `spine` merges first and carries almost no risk. `wave` merges last, behind the
deletions in §4.6, because it carries the whole collision set.

### 4.6 The collision taxonomy

`sequencer` against `wave`: **17 functions, 3 constructors (`Boot`, `Ending`,
`Done`), and 1 type (`Cfg`)**. The 17 classify by body and by full signature, and
the classes take different remedies.

**COLLAPSE (8).** One behaviour in two places. These become the new library module.

`argv-of`, `dflt`, `flag-value`, `flag-values`, `int-flag`, `last-field`,
`split-on`, `verify-safe?`

`dflt` is in this set on a measurement rather than on its text: the two bodies
differ only in a parameter name (`s` against `v`), which the type checker does not
see.

**SILENT HOMONYMS (4).** Identical parameter list AND identical return type,
different behaviour. **Under `open` these shadow with no diagnostic beyond the
warning §4.4 shows exits 0.**

| Name | Signature | Why it differs |
|---|---|---|
| `cfg-workdir` | `[c: Cfg] -> string` | reads slot 0 in `sequencer`, slot 1 in `wave` |
| `parse-cfg` | `[as: list[string]] -> Cfg` | builds a different record; see §4.7 |
| `missing-flags` | `[c: Cfg] -> string` | different required-flag set |
| `text-of` | `[r: Response] -> string` | different response handling |

**This class is the reason unification cannot be done by deleting two `def-main`
declarations.** A `sequencer` call to `cfg-workdir` under `(open wave)` reads slot
1, which in the sequencer's own `Cfg` is `cfg-only`. The driver would use a stage
filter as a directory path, and every gate would pass.

**LOUD HOMONYMS (5).** The signature differs, so the type checker rejects the
shadow. `boot-step`, `cfg-agent`, `done-code`, `enter`, `go`. Four of the five
differ because they are typed over `(Run, Ctl)` against `(Wv, WCtl)`, which is the
state-machine split of §4.3 showing through. `cfg-agent` differs in return type:
`AgentCfg` against `string`.

**The asymmetry inside the `cfg-*` pair is the finding.** `cfg-agent` fails loudly
and `cfg-workdir` does not fail at all. A merge that fixed only what the compiler
complained about would repair the loud one and ship the silent one.

### 4.7 `Cfg` is two concepts under one name, and this proposal does not settle it

| Slot | `sequencer` | `wave` |
|---|---|---|
| 0 | `cfg-workdir` : string | `cfg-tree` : string |
| 1 | `cfg-only` : string | `cfg-workdir` : string |
| 2 | `cfg-halt-at` : string | `cfg-compiler` : string |
| 3 | `cfg-halt-kind` : string | `cfg-agent` : string |
| 4 | `cfg-forced` : bool | `cfg-agent-args` : list[string] |
| 5 | `cfg-agent` : AgentCfg | `cfg-timeout` : int |
| 6 | `cfg-llmll` : string | `cfg-err0` : int |
| 7 | `cfg-refdir` : string | `cfg-proto0` : int |
| 8 | `cfg-rfc-url` : string | — |
| 9 | `cfg-amend-urls` : list[string] | — |

Ten slots against eight. **No slot carries the same meaning in both**, and each
module has its own `parse-cfg` building its own record.

**This is a finding and not a rename.** A rename assumes one concept with two
names. Here there are two records that share a name: a campaign configuration and a
fill-wave configuration.

**DECIDED 2026-09-11 by the user: the wave's record is DERIVED from the campaign's.**
`wave`'s type is renamed `WaveCfg`, and one function `wave-cfg-of [c: Cfg] -> WaveCfg`
constructs it. The relationship becomes a function rather than a coincidence, which
is what the measurement in §4.8 shows it already is. The two rejected readings: one
merged record forces every `wave` accessor to move and puts retry budgets in a
record nothing else reads; two independent records record the duplication
permanently without saying why it exists.

### 4.8 The derivation, measured before it was adopted

Read from both `parse-cfg` bodies and the `AgentCfg` accessors. **Five of the wave's
eight fields derive from the campaign record. Three do not.**

| `WaveCfg` field | Derives from | Flag agreement |
|---|---|---|
| `workdir` | `cfg-workdir c` | both read `--workdir`; **defaults differ**, `.` against `.wave` |
| `compiler` | `cfg-llmll c` | both read `--llmll-cmd`; exact |
| `agent` | `ag-exe (cfg-agent c)` | **flags differ**: wave reads `--agent-cmd`, sequencer reads `--agent-exe` |
| `agent-args` | `ag-args (cfg-agent c)` | both read `--agent-arg`; exact |
| `timeout` | `ag-timeout (cfg-agent c)` | both read `--timeout`; wave defaults 900 |
| `tree` | **nothing** | `--tree` has no campaign counterpart |
| `err0` | **nothing** | `--error-budget`, a wave-only retry budget |
| `proto0` | **nothing** | `--protocol-budget`, a wave-only retry budget |

**`wave-cfg-of` therefore cannot be total over `Cfg` alone.** The three underived
fields are genuine wave parameters, so the signature is
`wave-cfg-of [c: Cfg tree: string err0: int proto0: int] -> WaveCfg`. A single-argument
version would have to invent the three, and inventing a retry budget is exactly the
kind of implicit initialization `CONSOLE-INIT-1` is filed against.

**Two behaviour changes the derivation forces, named here rather than found later.**

1. **The `.wave` workdir default disappears.** Under derivation the wave inherits the
   campaign's workdir, whose default is `.`. Anything that relied on a bare `wave`
   invocation landing in `.wave` changes. That is acceptable because the wave stops
   being separately invocable at all, which is the point of job (a), but the 4e cover
   must be read for a dependence on the old default.

2. **`--agent-cmd` against `--agent-exe` is a flag-surface divergence, not a
   derivation problem.** The wave still carries the reference's flag name; the
   sequencer carries the port's. The derivation reads the sequencer's `AgentCfg`, so
   the wave's `--agent-cmd` parsing is deleted rather than reconciled. **This is the
   one place job (a) removes an operator-visible flag**, and it is worth stating
   because §3 says job (b) owns the operator CLI surface. Deleting a flag that only
   a now-unreachable entry point parsed is inside job (a); adding or renaming one is
   not.

### 4.4 The measurement that decides feasibility

A `def` cannot call a sibling `def` in the same module: the callee is not yet
body-faithful, and the admissibility check fires at check time before verification
runs. Merging modules is therefore a verification question and not only a
refactoring question, and this is what makes job (a) worth measuring before
scoping.

Measured over [`../../tools/llmll-driver/`](../../tools/llmll-driver/) on
2026-09-11:

| Module set | `def-shell` | `def` |
|---|---|---|
| The three executables (`sequencer`, `wave`, `spine`) | **424** (283, 90, 51) | **11** (2, 0, 9) |
| The nine proved-core modules (`stage`, `shape`, `validate`, `oracle`, `token`, `fill`, `gate`, `skip`, `report`) | **0** | **20** |
| The shell-side tables (`registry`, `manifest`) | 46 | 0 |

**The proved cores are not in the merge set.** The nine modules holding them are
pure `def` with zero `def-shell`, and job (a) does not touch them.

**The 11 `def`s inside the executables are leaves composed by `def-shell`.**
`spine.llmll`'s `stage-l-outcome` takes `passes: bool` as a parameter rather than
calling `stage-l-passes` itself; the composition happens at a `def-shell` call
site. A `def-shell`-to-`def` call is admitted. Merging modules whose `def`s are
leaves cannot create the intra-module `def`-to-`def` call that admissibility
rejects.

**This is a spot check on `stage-l`, not a census.** The engineer measures all 11
before starting. §7 item 2 carries it as a risk rather than a settled fact.

### 4.9 `verify-safe?` stays duplicated, and body equality is why the census missed it

**Added at Rev 4, after the move was tried and two covers failed.** The COLLAPSE set
in §4.6 was built from body equality. `verify-safe?` is identical in both modules,
so the census put it in the set. The census was wrong, and the covers said so
immediately:

- `test_driver_ll_4d.py` pins the **sequencer's** copy, asserting `"SAFE"` appears in
  it. The pin is on the abstraction function over the compiler's transcript.
- `test_driver_ll_4e.py` lists the **wave's** copy in `SEAM`, the set of wave
  functions that take an `out: string` and call `string-contains`: the functions
  that read another process's stdout and prove nothing about it.

Identical bodies, two different seams, two different pins. Collapsing the function
erases both and trades a verification-disclosure claim for seven saved lines.

**The general rule, because it will recur.** Body equality is necessary and **not
sufficient** for collapsing a duplicate. A function can be identical in two modules
and still be independently pinned in each, because the pin is about the seam the
copy sits on and not about the behaviour. A future collapse census runs the covers
before it trusts its own output.

**Checked against the other seven.** `flag-value`, `flag-values` and `split-on` are
pinned too, but at their **call sites** (`(flag-value as "--rfc-url")` inside
`parse-cfg`), which a move does not touch. `argv-of`, `dflt`, `int-flag` and
`last-field` carry no pins. Only `verify-safe?` has a definition-site pin, and it
has two. The COLLAPSE set is therefore **seven**.

Both surviving copies carry a comment naming the other and naming the cover that
pins it. The older comment in `sequencer.llmll` said this duplication "retires at
program unification", which is now false, and it is replaced rather than left.

### 4.10 Why (a2) is a sub-phase and not a refactor

Three measurements, taken at Rev 5 after the §2.5 split was found.

**1. The spine's stage logic is a state machine, not a set of callable functions.**
`spine-step` is a linear counter with seventeen arms, `s = 0` through `s = 16`,
driving `wasi.proc.run` commands for stages E, J, L and G2. Porting them means
mapping seventeen steps onto the sequencer's `Ctl` arms. There is no function to call.

**2. Stage M does not fit the registry, and this is a design problem.** Every registry
accessor is keyed on the stage index: `stage-out-count [i: int] -> int` gives a
**static** artifact count per stage. Stage M's artifact count is holes times attempts,
settled at run time. It is not a function of `i`. Folding stage M in therefore needs
either a registry shape that admits variable multiplicity, or a mechanism that keeps
stage M outside the per-stage artifact accounting. **Neither exists and neither is
designed.** `wave.llmll`'s header recorded this at 4e and deferred it: Rev 12 found
stage M "fitting no `[i: int] -> int` registry entry", and the header calls folding it
in "a restructure of a 1760-line module".

**3. The sequencer's `Ctl` carries one `Delegate Body` arm per stage**, which the wave
header describes as "one delegation, one exit status". Stage M is many delegations and
many exit statuses. The arm shape is wrong for it, not merely unoccupied.

**What (a2) needs before an engineer can scope it.** A design for stage M's
multiplicity: either the registry admits a run-time artifact count, or stage M is
accounted for differently from the other fifteen and the difference is written down.
That is a `language-team` question and **this proposal does not answer it.** Rev 5
scopes (a2) and stops there, because answering it inside a revision whose subject is
job (a)'s shape would be the same conflation §2.5 exists to undo.

## 5. Job (b): port the plumbing

Scope is [`../../scripts/rfc_to_implementation.py`](../../scripts/rfc_to_implementation.py),
**2032 lines on 2026-09-11** against the campaign document's 1814, so the figure has
already moved once. Any scope estimate for (b) is measured when (b) starts and never
carried from the campaign document.

The excluded surface is argparse, `copytree`, tempdir handling, path juggling, the
four operator flags, and the run layout. Campaign §8.1 reports the result as
utility and not as a language result. That framing is settled and this proposal
does not reopen it.

## 6. Edge cases

1. **The orphan set grows after the merge.** `wave` loses its `def-main` and the
   unified program does not import `fill` and `token`. The orphan assertion in
   `test_driver_ll_callers.py` fails and names the returned modules. Channel:
   trust, through the existing cover. **This is the positive witness and it is not
   hypothetical**: the cover records `fill` and `token` leaving the orphan set at
   the moment `wave` acquired a `def-main`, so this is that measured event run
   backwards.

2. **A `def` acquires a sibling-`def` call during the merge.** A later edit
   composes `stage-l-passes` inside `stage-l-outcome`'s body once both sit in one
   module. The admissibility check fires at check time, before verification runs,
   and no ordering of runs escapes it. Channel: contract, at check time.

3. **Two merged modules declare the same name.** `sequencer`'s `flag-value` and
   `wave`'s copy both land in one module. Rejected at check time as a
   redefinition. Channel: type. This is the mechanical form the duplication takes
   once the copies lose the module boundary that separated them, so the merge
   cannot silently keep both.

4. **`stage-ported?` is corrected instead of deleted.** An engineer flips the five
   false arms to true. Rejected in review under §2 clause 3. Channel: spec is
   silent, and the silence is a gap this proposal closes by naming deletion in the
   completion test.

## 7. Verification mapping

**This proposal introduces no new proof obligation, and that is a result rather
than an omission.** Job (a) moves existing `def`s between modules and deletes
duplicated `def-shell` bodies. It adds no contract clause and no predicate.

- **Channel**: none new. The 20 proved cores keep their contracts and do not move.
- **Fragment**: unchanged. No obligation crosses the QF-LIA boundary in
  [`LLMLL.md`](../../LLMLL.md) §5.3.3 / §5.3.5, because none is added or restated.
- **The one obligation re-emitted rather than new**: the 11 `def`s inside the
  merged executables are re-checked in their new module. Their verification
  condition does not change, because a body-faithful VC does not depend on the
  module name. The admissibility check is what could change, and §6 item 2 is
  where it would appear.

Job (b) touches `def-shell` only. `def-shell` sits outside the body-faithful
fragment, so (b) contributes nothing to the trust closure.

## 8. Affected surface

1. `sequencer.llmll`, `wave.llmll`, `spine.llmll` — the merge. Two `def-main`
   deletions.
2. `registry.llmll` — `stage-ported?` deleted.
3. A new library module for the shared helpers.
4. [`test_driver_ll_callers.py`](../../scripts/tests/test_driver_ll_callers.py) —
   the program-set and orphan assertions both move. **This is the cover behaving
   as designed**: its docstring records that it was built to fail when the program
   set moves, and that "the rows that acquired callers are deleted; the assertion
   is not widened."
5. [`test_driver_ll_4c.py`](../../scripts/tests/test_driver_ll_4c.py) — the
   ported-stage census pinned to `stage-ported?` retires with it.
6. `spine.llmll` header — the stage A sentence.
7. `rfc_to_implementation.py` — job (b) only, and not before Phase 4 acceptance.
8. No compiler module changes. No JSON-AST delta. No schema version move. Nothing
   under the feature freeze.

## 9. Risks

1. **Job (a) is a large mechanical edit over 4517 lines with a real review cost.**
   Classify: scope. Mostly deletion and relocation, and the §2 test is decidable,
   but no test asserts behavioural equivalence across the merge. Land it in steps,
   each keeping every cover passing, rather than as one commit.

2. **RETIRED at Rev 2, by measurement.** Rev 1 asked for a census of all 11 `def`s,
   because its admissibility argument rested on a `stage-l` spot check. The
   `compiler-engineer` ran it: every body extracted, every one scanned for calls to
   the other ten, **zero sibling `def`-to-`def` calls**. The spot check generalizes
   and the risk is closed rather than carried.

2b. **A silent homonym survives the merge.** Classify: soundness. Source: §4.6, the
   four-name SILENT class, and §4.4's measurement that the warning exits 0. This is
   the risk Rev 1 did not know about, and it is more severe than anything Rev 1
   listed. A `cfg-workdir` reading the wrong slot type-checks, builds, and passes
   every gate the driver has. **It blocked job (a) at Rev 2 and is UNBLOCKED at
   Rev 3**, because the §4.7 decision renames `wave`'s type to `WaveCfg` and its
   accessors follow, which removes all four SILENT names at their source rather than
   relying on a reviewer to notice them. §2 clause 5 is the standing guard.

3. **`twin-skip-reassociated.llmll` has no stated disposition.** Classify: scope.
   Ten lines, no `def-main`, a proof twin rather than a module the program uses. It
   is not in the merge set and this proposal does not place it.

4. **Job (b)'s target keeps moving.** Classify: spec-drift. 2032 lines against
   1814. Only matters at scale, and §5 states the rule that answers it.

5. **The roadmap says fifteen module files and the tree holds fourteen.**
   Classify: spec-drift. Counted by absence of `def-main` on 2026-09-11; one of the
   fourteen is a 10-line proof twin. Does not block. Routed to
   `documentation-lead`, not corrected here.
