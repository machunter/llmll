---
name: fs-capability-trio-proposal
title: "FS-RMDIR-1, FS-STAT-1 and FS-EXISTS-1: three filesystem rows, and the one language gap under them"
status: "Rev 3, 2026-09-05. REV 3 RECONCILES THIS PROPOSAL WITH `RESP-FACT-1`, WHICH SHIPPED AT v0.17.0 AND WHICH SECTION 5 FILED AS AN OPEN GAP. Section 5 is rewritten: the gap is closed, and `wasi.fs.stat` needs a SECOND fact category, `FactCodegen`, which the shipped `respFactTable` names and leaves undeclared. THE CATEGORY IS ASSUMED, NOT EARNED, and section 5 says so in those words. The routing that professor round 1 rejected is inherited UNCHANGED; what grows is the trusted set, by one codegen-faithfulness axiom of the `bytes-set` class. `checker_soundness_version` does NOT change, because the affected population is empty: no sidecar can name a builtin that does not exist. `wasi.fs.exists` declares NO fact, its kind being `RText` where fact predicates are int-only. Scope settled by the user 2026-09-05: `FS-STAT-1` and `FS-EXISTS-1` ship TOGETHER. FOUR RECORDS THAT STILL DESCRIBED THE WITHDRAWN CLAMP WERE CORRECTED 2026-09-05, one of them a comment in shipped compiler source. Rev 2 follows. Rev 2, professor round 1 folded. THE THREE ROWS DO NOT SHIP TOGETHER, and that is the proposal's main change from Rev 1. `FS-RMDIR-1` ships first and alone, because port 006 is blocked on it and nothing in its design survived the review with a scar. `FS-STAT-1` and `FS-EXISTS-1` follow as one change. TWO SETTLED ITEMS ARE OVERTURNED BY MEASUREMENT. (i) The clamp on `wasi.fs.stat` is WITHDRAWN. A negative computed age answered zero, which reports maximal freshness inside a liveness check, so the failure direction was open. It now answers `RErr`. This contradicts `driver-ll-phase4-proposal.md` section 14 and the roadmap row, and both need the correction. (ii) The Rev 1 soundness argument for `wasi.fs.exists` is FALSE and was refuted by running it. Under a parent directory at mode 0111 the probe answers, and `wasi.fs.list` on that same parent fails, so the probe is not a subset of listing. The authority claim is rewritten rather than repaired. A THIRD ITEM IS NARROWED RATHER THAN ACCEPTED: the review found `doesFileExist` reports False for a file that exists and cannot be reached, which is correct and which kills Rev 1's chosen primitive. It does not kill the design. `getModificationTime` classified through `System.IO.Error` gives the three-way answer using `base` alone, measured, so the dependency cost stays zero. Rev 1's `RCode` kind encoding is REVERSED to `RText` on the review's finding 7. Rev 1's probe-then-act interlock is WITHDRAWN as a check-then-act race. Filed out of this proposal: `RESP-FACT-1`, and a delete defect that is live today. Roadmap rows: `FS-RMDIR-1`, `FS-STAT-1`, `FS-EXISTS-1`."
date: 2026-08-15
author: language-team
consumers: [compiler-engineer, professor, documentation-lead, experiment-lead, user]
---

# FS-RMDIR-1, FS-STAT-1 and FS-EXISTS-1

## Summary

LLMLL cannot ask three questions about a file. It cannot ask whether a path is
there. It cannot ask how old a path is. It cannot remove a directory.

Port 006 of the TOOL-LL campaign raised all three. The port carries state
`blocked` in `docs/design/INDEX.md`, and `FS-RMDIR-1` is what blocks it.

**The three rows stay three rows.** They share a namespace and a raising port.
They do not share an answer. Folding two causes into one row produced a row
that was incorrect for a release at `ALIAS-LOWER-1`.

**The three rows do not share a change.** Rev 1 proposed one design round for
all three. The professor round refuted two of its claims by running them, so
Rev 2 splits the work. `FS-RMDIR-1` ships alone and first.

## 1. What raised these rows

`scripts/build_smoke.sh` stage 5 runs `rm -rf /tmp/llmll-capproc-exec` before
its fixture runs. It then asserts that the directory exists. That assertion is
how the gate grades `wasi.fs.mkdir`.

Without the delete, a directory left by an earlier run satisfies the assertion
whatever this run's `mkdir` did. So `tools/build-smoke/buildsmoke.llmll`
measures whether the directory pre-existed. It then prints
`NOT GRADED: wasi.fs.mkdir` instead of reporting a pass it did not earn.

**That is the row's own witness, and it is `SKIP-SILENT-1`'s class.** A gate
that cannot decide must not report that it decided. Hold that sentence. Section
4 applies it to a second row where Rev 1 did not apply it.

`FS-EXISTS-1` came from port 005. `os.path.exists` has no equivalent, so
existence is decided by attempting a read. On the live corpus that costs
77.0 MB across about 1900 calls. `FS-STAT-1` came from DRIVER-LL Phase 4,
where `liveness.advancing` takes an age in seconds and no builtin produces one.

## 2. Why three rows arrived as one request, and what that means

The rows are a **standard library that was never written**, not a design
failure. The measurement supports this and it is worth recording.

Of 82 distinct roadmap row names, **22 are operating-system surface**:
`FS-*`, `PROC-*`, `ENV-*`, `HTTP-*`, `PATH-*`, `REGEX-*`, `LIST-*`, `RUN-*`.
**None of the 22 concerns types, refinement predicates, contracts, the
obligation channels, or the trust model.**

Gap discovery is also not uniform across the campaign. Ports 001 through 004
process text, version banners, doc claims and archive state. Together they
filed about one gap. Ports 005 and 006 touch the filesystem and the process
table. They filed ten.

**So the language's text and logic surface carried four gates without change.
The operating-system surface did not exist.** That is the finding, and it is
different from either branch of "the language works" and "the language does
not work".

**A process consequence follows and it belongs in a separate proposal.** These
three rows each received a full design pipeline for about 60 lines of Haskell.
A tier policy that routes a sealed builtin differently from a type-system
change is the fix. This proposal does not settle that policy. It records that
the need is real.

## 3. `wasi.fs.rmdir`, which ships first and alone

### Surface

```lisp
(import wasi.fs (capability delete "/tmp"))
(wasi.fs.rmdir "/tmp/llmll-capproc-exec")   ;; -> Command, delivering RNone | RErr
```

Signature: `string -> Command`. Effect: `Caps {EFsWrite}`, the label
`wasi.fs.delete` and `wasi.fs.mkdir` already carry. No new `Response` arm. No
new effect label. No new capability namespace. No schema change.

### It removes an empty directory only

Four grounds. The first two are each sufficient.

**No runtime capability check exists.** `LLMLL.md` states that the compiler
emits no capability code at all, and that the granted verb is not checked. So a
recursive delete would run under a root that is declared and not enforced. That
row is `CAP-1-REAL`.

**The mitigation the spec names for the existing dangerous name does not run.**
`wasi.fs.delete` is marked **sensitive**, and the sensitive-command review is
not implemented. Do not ship a more dangerous name under an absent mitigation.

**Measured: empty-only closes the witness site.**
`scripts/build-smoke/capproc_exec.llmll` writes exactly three flat files into
the scratch directory. They are `in.txt`, `out.txt` and `err.txt`. The fixture
creates no subdirectory. Three `wasi.fs.delete` calls and one `wasi.fs.rmdir`
clear it.

**Recursion built in LLMLL is unsound over symlinks today.** `listDirectory`
follows a symlink to a directory, which is `LIST-KIND-1`'s second cause. So
"compose the recursion in the port" is not a clean answer either. Empty-only
makes the divergence a visible `RErr`.

The external precedent agrees. POSIX `rmdir` is empty-only by specification,
and recursive removal is a userspace loop over `unlinkat(AT_REMOVEDIR)` walking
an `openat` chain, so the recursion is bounded by descriptors and not by a path
string.

### A missing path answers `RNone`, and Rev 1 said otherwise

Rev 1 answered `RErr` on a missing path. It justified the break from
`wasi.fs.delete`'s idempotence by saying the caller can probe with
`wasi.fs.exists` first.

**That is a check-then-act race and Rev 2 withdraws it.** Probe-then-act on a
shared path is the canonical time-of-check-to-time-of-use pattern (Bishop and
Dilger, *Checking for Race Conditions in File Accesses*, Computing Systems 9(2),
1996; Tsafrir, Hertz, Wagner and Da Silva, *Portably Solving File TOCTTOU Races
with Hardness Amplification*, FAST '08). `compiler/src/LLMLL/CodegenHs.hs`
already records that the existing `doesFileExist` guard in `wasi_fs_delete` is
racy under concurrency. Rev 1 turned a recorded hazard into the recommended
calling convention.

The scratch directory sits under `/tmp` and `wasi.proc.run` spawns children, so
the race has real witnesses. The single-threaded-harness argument does not
cover it.

**`wasi.fs.rmdir` is therefore idempotent, like `wasi.fs.delete`.** The gate
observes the **post-state**: it calls `rmdir`, then asks about the result. An
assertion about an observed state is race-free in the way a guarded action is
not.

## 4. `wasi.fs.stat`, and the clamp that is withdrawn

### Surface

```lisp
(import wasi.fs (capability read "/tmp"))
(wasi.fs.stat "/tmp/a")     ;; -> Command, delivering RCode age-seconds | RErr
```

Signature: `string -> Command`. Effect: `Caps {EFsRead, ENonDet}`. An age
changes with the clock even when the filesystem does not move, which is why
`ENonDet` applies here and not to `wasi.fs.exists`.

### A negative computed age answers `RErr`

`driver-ll-phase4-proposal.md` section 14 and the roadmap row both specify a
clamp: a negative age returns zero. **Rev 2 withdraws the clamp.**

A negative age means clock skew, a tampered mtime, or an artifact unpacked from
an archive. **Clamping it to zero reports maximal freshness.** The consumer is
`liveness.advancing`, a liveness check. So the one input that should make a
liveness gate abstain became the strongest available evidence of progress.

That is `SKIP-SILENT-1`'s class, quoted in section 1 of this document. Rev 1
applied that discipline to `wasi.fs.exists` and left it unapplied here.

**The clamp also bought nothing in the verification channel**, which is section
5's finding. So withdrawing it costs no discharge that anybody had.

### Correction owed to two records

`driver-ll-phase4-proposal.md` section 14 and the `FS-STAT-1` roadmap row state
that the clamp "discharges `[S12-DOM]`'s first conjunct by construction". Both
sentences go. Section 5 states why the sentence was wrong even with the clamp
in place.

## 5. `RESP-FACT-1` has shipped, and `wasi.fs.stat` needs its second category

**Rev 2 filed this section as an open gap. Rev 3 closes it.** `RESP-FACT-1`
shipped at v0.17.0 (`d5dd5a8`). A `Command` result now carries a proved property
to its caller, keyed on the program's own control tag.

Rev 2's text is kept below as the record of why the row was filed. What follows
first is what changed.

### The fact `wasi.fs.stat` declares

With section 4's `RErr` rule, the `RCode` arm carries only a non-negative age.
So the declared fact is:

```
("wasi.fs.stat", "RCode")  ->  {v : int | v >= 0}
```

**The fact holds because the negative case never reaches the arm.** It does not
hold because a clamp rewrote the value. That distinction is section 4's, and it
is the whole reason the clamp went.

### The category is `FactCodegen`, and it is ASSUMED rather than EARNED

`respFactTable` in `compiler/src/LLMLL/RespFact.hs` ships one entry, and its
category is `FactProgram 0`: `wasi.http.response`'s `RCode` payload is the
program's own first argument, so a premise exists and the compiler proves it as
one `call-pre:wasi.http.response` constraint.

**A filesystem age is not an argument the program passes.** There is no premise
to prove. The fact is true because the generated code cannot produce a violating
value.

That is a **trust-channel axiom about a sealed builtin**. It is the same class as
`bytes-set`'s length-preservation fact and `(bytes-zero)`'s constructor axiom,
both of which ride `codegen_semantics_version` rather than any solver discharge.
The `TRUST-AXIOM` roadmap row records that class and records that it reached no
reporting surface until `RESP-FACT-1` landed the first disclosed population.

**Rev 3 concedes the asymmetry rather than hiding it.** A `FactProgram` fact is
earned. A `FactCodegen` fact is assumed. The disclosure must say which, or the
trust report lies by omission, and that omission is exactly what `TRUST-AXIOM`
exists to record.

### Why it belongs in `respFactTable` and not in a second mechanism

The question is whether `FactCodegen` is a different mechanism wearing the same
name. It is not, and the reason is what professor round 1 rejected.

Round 1 rejected Rev 1 because a per-arm attachment let a fact reach a binder
**no builtin guarantees**. That objection is about ROUTING: which value carries
the fact, and how the compiler knows the value came from the builtin that
guarantees it. Revs 2 to 6 answered it with the issuing rule, the delivery rule
and the export condition.

**A `FactCodegen` fact needs that routing without one change.** It inherits it.
What differs is only the SOURCE of the guarantee, not the delivery of it.
Building a second mechanism would duplicate the routing and give a reader two
places to check, which is the error `ALIAS-LOWER-1` records.

**So the soundness argument is not weakened, and the trusted set grows by one
axiom.** Those are different claims and Rev 3 makes both.

### The delivery rule and the export condition apply unchanged

Measured, not assumed. `deliveredParams` and `exportCondition` in
`compiler/src/LLMLL/RespFact.hs` take no `RespFact` argument and never read
`rfCategory`. The delivery rule constrains how a `Response` value reaches a
step. The export condition constrains who can write the tag constructor. Neither
depends on why the fact is true.

### The disclosure row, which is the one thing that must change

`AssumedFact` carries `afCategory` and `afPremise`. Today `afCategory` is the
string literal `"program-determined"` at the disclosure site, and `afPremise`
lists `folded-literal` or `call-pre:<def>` per premise site.

A `FactCodegen` fact has no premise site, so `afPremise` would render empty.
**An empty premise field reads as a missing value, not as an absent obligation.**
Rev 3 requires:

- `afCategory` becomes `codegen-determined` for this class, derived from
  `rfCategory` rather than written as a literal.
- `afPremise` becomes `codegen:<builtin>`, naming the axiom, and the trust
  report's text line states that the fact is assumed and rides
  `codegen_semantics_version`.

**Two seams in the shipped code make this concrete**, and the engineer should
expect both. `RespFact.hs` binds `let FactProgram i = rfCategory f` as an
irrefutable pattern at its premise-site builder, so a second constructor makes
that a partial match. The disclosure builder writes the category as a literal.
Both are one-constructor assumptions and neither is a design problem.

### `checker_soundness_version` does NOT change

It moved to `"2"` at v0.17.0 because a verdict began to depend on the fact
table. Adding an entry changes that table again, so the question is fair.

**The affected population is empty.** No tracked `.verified.json` can name a
builtin that does not exist, and `wasi.fs.stat` does not exist. Nothing in the
tree can change verdict. That is the same argument FACT-AG-LEN Stage 3 used to
avoid spending the stamp: identify the population rather than assume it is
non-empty.

The new axiom rides `codegen_semantics_version`, exactly as `bytes-set` and
`(bytes-zero)` do.

### `wasi.fs.exists` declares NO fact

Its kind is `RText`, and `renderFact` writes every fact as `{v : int | ...}`.
Fact predicates are int-only today. A kind-string fact would need a predicate
sort the table does not carry, and the four kinds are already exhaustive on the
`RText` arm, so a refinement would add nothing a match does not give.

A program that requests a fact for a tag bound to `wasi.fs.exists` therefore
gets `W-RESP-FACT-NONE`, which is the warning v0.17.0 added.

---

**Rev 2's text follows, as the record of why `RESP-FACT-1` was filed.**

### Rev 2 text: `RESP-FACT-1` as the gap under all three rows

`RCode` carries a bare `TInt` in `compiler/src/LLMLL/TypeCheck.hs`.
`compiler/src/LLMLL/FixpointEmit.hs` contains **zero** occurrences of
`Response`.

**So no effect can carry a proved property to its caller.** A program issues
`wasi.fs.stat`, receives an integer with no lower bound, and must guard or
re-prove what the builtin already established. To call `advancing` it must show
`(>= newest-artifact-age 0)`, and nothing in scope shows it. The caller writes a
runtime guard, the path-sensitive `EIf` encoding discharges the conjunct, and
the builtin's own behaviour never enters the logic.

The established shape puts the fact in the primitive's **declared type**.
Liquid Haskell uses `assume` for primitives (Vazou, Seidel, Jhala, Vytiniotis
and Peyton Jones, *Refinement Types for Haskell*, ICFP 2014). F\* uses
`assume val`. Dafny uses `{:axiom}`. In each the caller discharges against a
citable assumption and the trusted set stays enumerable, which is the LCF
discipline `LLMLL.md` already applies at its anti-laundering clause.

**This is filed as `RESP-FACT-1` and it is not fixed here.** Two readers reached
it independently in one session: the language-team from the verification
mapping, and the professor from the primitive-assumption literature. Six ports
routed around it and none filed it, because writing a guard looks like ordinary
programming.

## 6. `wasi.fs.exists`, and the argument that measurement refuted

### Surface

```lisp
(import wasi.fs (capability read "/tmp"))
(wasi.fs.exists "/tmp/a")   ;; -> Command, delivering RText kind | RErr
```

Kinds: `"absent"`, `"file"`, `"dir"`, `"symlink"`. Effect: `Caps {EFsRead}`.

### The kind is `RText`, and Rev 1 said `RCode`

Rev 1 encoded the kind as a small integer on `RCode`. **Rev 2 reverses this.**

`RCode` already carries exit statuses, monotonic nanoseconds and, under section
4, ages. Adding a kind enum makes `RCode 0` mean exit success, zero nanoseconds,
age zero, and path absent. The first is normally good and the last is normally
bad. `Response` is a sum whose discriminating power is the reason EFFECT-RESP
added it, and overloading one arm with unrelated enumerations spends that power.

A string comparison is the cost. One meaning per arm is the benefit.

### Rev 1's soundness argument is false

Rev 1 argued that the probe grants no authority `wasi.fs.list` already grants.
**Running the argument refuted it.** With a parent directory at mode 0111
(search, no read):

```
listDirectory  = EXCEPTION (RErr)
exists(id_rsa) = True
exists(absent) = False
```

So the probe answers about a directory the program cannot enumerate. A program
can test for `/root/.ssh/id_rsa` without listing `/root/.ssh`. Execute-without-
read is a standard configuration for a shared parent, not a corner case.

**The claim is rewritten rather than repaired.** The probe grants an authority
bounded by the operating system, which the declared capability clause does not
constrain. That is already true of every `wasi.fs` name, because `CAP-1-REAL`
means no capability code runs. **The spec must disclose it rather than assert a
subset relation that does not hold.**

The comparison class is worth naming. Capsicum (Watson, Anderson, Laurie and
Kennaway, *Capsicum: practical capabilities for UNIX*, USENIX Security 2010) and
WASI preview 1's `path_open` both resolve a path beneath a pre-opened directory
descriptor, so a name outside the grant cannot be written. LLMLL takes an
absolute string. **That is a scope boundary LLMLL has chosen, and this proposal
does not move it.**

### The three-way answer needs the right primitive, and it is in `base`

The review found that `doesFileExist` reports `False` for a file that exists and
cannot be reached. Measured under a parent at mode 0000, it returns `False`, not
an exception. **That is correct and it kills Rev 1's chosen primitive**, whose
whole design separates absent from undecidable.

It does not kill the design. `getModificationTime` classified through
`System.IO.Error` gives the three-way answer. Measured this session:

```
/tmp/lp/secret/f  -> UNDECIDABLE(perm)     (parent at mode 0000)
/tmp/lp/nosuch    -> ABSENT
/tmp/lp           -> PRESENT
```

`isDoesNotExistError` and `isPermissionError` are in `base`. **No `unix`
dependency, so no POSIX-only restriction and no resolver movement.**

**`wasi.fs.exists` and `wasi.fs.stat` therefore share one probe.** The same call
answers presence and age. The kind refinement runs only after the probe reports
present, so the permission case is already excluded when
`pathIsSymbolicLink` and `doesDirectoryExist` run. Test the symlink first,
because `doesDirectoryExist` follows a symlink to a directory.

## 7. Edge cases and degenerate inputs

1. **`wasi.fs.rmdir` on a missing path. Positive witness.** Input:
   `(wasi.fs.rmdir "/tmp/llmll-capproc-exec")` with nothing there. Expected:
   `RNone`. Channel: **trust**. This matches `wasi.fs.delete` and removes the
   race section 3 withdraws.
2. **`wasi.fs.rmdir` on a non-empty directory.** Input: the same call while
   `in.txt` is present. Expected: `RErr`. Channel: **trust**.
   `removeDirectory` raises and `llmll_publish_io` catches it.
3. **`wasi.fs.stat` on a file whose mtime is in the future.** Expected: `RErr`,
   not `RCode 0`. Channel: **trust**. Reachable by `touch -d tomorrow`, by an
   unpacked archive, and by clock skew across machines.
4. **`wasi.fs.exists` on a present file under a mode-0000 parent.** Expected:
   `RErr`. Channel: **trust**. Measured. `doesFileExist` would have answered
   `False` and conflated it with absent.
5. **`wasi.fs.exists` on a known name under a mode-0111 parent.** Expected:
   `RText "file"`, while `wasi.fs.list` on that parent answers `RErr`. Channel:
   **spec must disclose (gap)**. This is section 6's refutation.
6. **`wasi.fs.exists` on a symlink to a directory.** Expected: `RText "symlink"`,
   never `RText "dir"`. Channel: **trust**. This decides the probe order.
7. **A `wasi.fs` import carrying `:deterministic true` once `wasi.fs.stat`
   lands.** Expected: **type error**, on `ENV-READ-1`'s precedent. Channel:
   **type**. `capDeterministic` reaches one serializing consumer plus that
   refusal, and `EVENT-CAPTURE-1` records that the capture is not implemented.
   So the flag would claim replay determinism over a clock-dependent operation
   and deliver nothing.

### Rev 3 edge cases, for the declared fact

8. **POSITIVE WITNESS (D2). The fact fires and discharges a post with no runtime
   guard.** Input, the minimal firing program:

   ```lisp
   (import wasi.fs (capability read "/tmp"))
   (import wasi.io (capability stdout :deterministic false))
   (export)
   (type Ctl (| Boot) (| Probed) (| Halt))
   (def-shell go [r: int p: Ctl c: Command] -> ((int, Ctl), Command)
     (pair (pair r p) c))
   (def-shell age-step [p: Ctl x: Response] -> int
     (pre (= p Probed))
     (post (>= result 0))
     (match x ((RCode age) age) (_ 0)))
   (def-shell step [s: (int, Ctl) input: string x: Response] -> ((int, Ctl), Command)
     (match (second s)
       ((Boot)   (go (first s) Probed (wasi.fs.stat "/tmp/a")))
       ((Probed) (go (age-step Probed x) Halt (wasi.io.stdout "done")))
       ((Halt)   (go (first s) Halt (wasi.io.stdout "")))))
   ```

   Expected: `Probed` binds to `wasi.fs.stat`, the `RCode` binder `age` carries
   `{v : int | v >= 0}`, and `(post (>= result 0))` is **discharged from the
   fact**. Channel: **contract**, QF-LIA.

   **The discriminating test, and it is the acceptance criterion.** Delete the
   `wasi.fs.stat` row from `respFactTable` and re-run. `age` is then an
   unconstrained int and the post must be **refuted**. A fixture that verifies
   under both tables proves nothing about the fact, which is the failure the
   `RESP-FACT-1` cells `c27` and `c28` recorded in another form.

9. **A match that names the `RErr` arm gets no fact.** Input:
   `(match x ((RCode a) a) ((RErr m) 0) (_ 0))`. Expected: the `RCode` binder
   carries the fact and the `RErr` binder carries nothing. Channel: **contract**.
   The table is keyed on `(builtin, arm)`, so no other arm is reachable.

10. **A program requests a fact for a tag bound to `wasi.fs.exists`.** Expected:
    `W-RESP-FACT-NONE`, the warning v0.17.0 added. Channel: **trust
    (disclosure)**. Section 5 states why that builtin declares no fact.

11. **A tag bound to both `wasi.fs.stat` and `wasi.io.stdout`.** Expected: the
    module stops with the `⊥` error naming the def, unchanged from
    `RESP-FACT-1` §5.1. Channel: **type**. The category does not enter this rule.

## 8. Verification mapping

| Obligation | Channel | Fragment |
|---|---|---|
| A capability import is present for `wasi.fs.*` | type | Not a proof obligation. `checkWasiCapability` decides it during inference |
| `:deterministic true` is refused on a `wasi.fs` import | type | Not a proof obligation. A side condition on the import clause |
| The value any of the three deliver | trust, and **contract once the fact is declared** | **Was "no fragment", and that is `RESP-FACT-1`, which SHIPPED at v0.17.0.** When this row was written a `Command` result was not a value in the refinement logic and every caller took the `asserted` tier. A declared fact now reaches the `Response` arm binder under a proved control-tag precondition. For `wasi.fs.stat` the fact is `{v : int \| v >= 0}` on `RCode`, holding because §4's `RErr` rule keeps a negative age out of the arm. Its category is **not** program-determined (`FactProgram`), the age being the filesystem's and not an argument the program passes, so it needs the `FactCodegen` category `RespFact.hs` names and leaves undeclared. **Rev 3 owes that entry**, and `RespFact.hs`'s comment naming the clamp as its firing witness is stale on the same withdrawal |
| `[S12-DOM]`'s first conjunct | contract | **QF-LIA at the caller**, discharged from a runtime guard through the path-sensitive `EIf` encoding, not from the builtin |
| Σ_eff join over the three names | type | Unchanged. `joinEff` is untouched and nothing widens to `Unbounded` |

Nothing here is nonlinear. Nothing escapes to Lean.

## 9. Affected surface

- `compiler/src/LLMLL/TypeCheck.hs`: three `builtinEnv` signatures, one
  `:deterministic` side condition.
- `compiler/src/LLMLL/ObligationAssembly.hs`: three `primEffect` clauses.
  **Each must sit above the `wasi.` fallthrough.** Below it the name reports the
  lattice top and every caller's `effect_summary` goes vacuous. That trap is
  recorded twice already, for `wasi.proc.args` and for `wasi.env.get`.
- `compiler/src/LLMLL/CodegenHs.hs`: one shared probe and three bodies. Add
  `System.IO.Error`, which is `base`. Add `doesDirectoryExist`,
  `pathIsSymbolicLink`, `removeDirectory` and `getModificationTime` from
  `directory`, which is already a generated-project dependency.
- `LLMLL.md` section 13.9: three table rows, plus the disclosure section 6
  requires.
- `docs/compiler-team-roadmap.md`: three rows, the `FS-STAT-1` clamp correction,
  a new `RESP-FACT-1` row, and a row for the delete defect below.
- `docs/design/driver-ll-phase4-proposal.md` section 14: the clamp sentence.
- `docs/design/llmll-tooling-campaign.md`, `docs/design/tool-ll-RESTART.md`,
  `docs/design/tool-rfc-006-build-smoke.md`: census and gap tables.
- `scripts/build_smoke.sh` and `tools/build-smoke/buildsmoke.llmll`: a stage
  that grades the three, and the port that consumes them.

**Not touched:** `docs/llmll-ast.schema.json` stays at 0.11.0. The `Response`
arm set, the Σ_eff label set and the capability namespace set are unchanged.

**A sixth `Response` arm is not available, and the cost is measured.** The tool
corpus writes all five arms explicitly and uses **zero** wildcards.
`checkExhaustive` appends to `tcErrors`, so a missing arm is a hard type error.
Count: **48 exhaustive `Response` matches across 16 files**. CAP-PROC's
no-new-arm rule is therefore a measurement here and not an assertion.

## 10. Risks

1. **`RESP-FACT-1` SHIPPED at v0.17.0, and Rev 3 restates this risk.** The old
   text read that the row was larger than these three and blocked none of them.
   Both halves have expired. Classify: soundness. Bite: **complicates this
   proposal and does not block it.** The residual risk is not the missing
   mechanism; it is that `FactCodegen` enlarges the trusted set by one
   codegen-faithfulness axiom, whose validity no solver checks. Section 5 states
   the mitigation: derive the disclosed category from `rfCategory`, name the
   axiom in the premise field, and ride `codegen_semantics_version`. **An
   undisclosed axiom here would recreate `TRUST-AXIOM` inside the row that first
   disclosed it.**
2. **The mode-0111 disclosure has no home in the spec today.** Classify:
   soundness. Bite: complicates. Every `wasi.fs` name already has the property,
   so the disclosure is owed once and covers the namespace.
3. **`wasi.fs.rmdir` and `wasi.fs.delete` are not atomic as a pair.** Classify:
   scope. Bite: only matters at scale. The reference runs `rm -rf`, which is
   also not atomic, so the port does not diverge.
4. **Port 006 stays `blocked` until `FS-RMDIR-1` ships.** Classify: scope.
   Bite: this is why section 3 ships first and alone.

## 11. Findings routed out of this proposal

**`RESP-FACT-1`**, section 5. A `Command` result cannot carry a proved property
to its caller. New row. **FILED, AND SHIPPED at v0.17.0** (`d5dd5a8`), design
`docs/design/resp-fact-proposal.md` Rev 6. Section 5 is rewritten against the
shipped mechanism. **Two follow-on items are owed to the compiler-engineer by
this proposal rather than by that one**: `rfCategory` gains a second constructor,
which makes an irrefutable pattern in `RespFact.hs` partial; and the disclosed
category is a string literal that must become derived.

**`wasi.fs.delete` reports success on a directory and removes nothing.** Its
body reads `exists <- doesFileExist path; when exists (removeFile path);
return RNone` in `compiler/src/LLMLL/CodegenHs.hs`. Measured under the
compiler's own GHC: `doesFileExist` on a directory is `False` and
`doesDirectoryExist` is `True`. **So the guard never fires and the command
answers `RNone`.** This is live today, it is independent of all three rows, and
it is the same collapse `RNone` suffers elsewhere: the arm means both "done" and
"nothing happened". New row, and route it with section 3.

**A tier policy for standard-library rows.** Section 2. Separate proposal.

## 12. Review history

### Rev 3, 2026-09-05

Reconciles the proposal with `RESP-FACT-1`, which section 5 filed as a gap and
which shipped at v0.17.0. No professor round; the changes follow the shipped
mechanism rather than a critique.

- **Section 5 is rewritten.** The gap is closed. `wasi.fs.stat` declares
  `{v : int | v >= 0}` on `RCode`, under a new `FactCodegen` category. Rev 2's
  text is kept below the new content as the record of why the row was filed.
- **The category is stated as ASSUMED, not earned**, and the disclosure must say
  so. This is conceded rather than argued away: a `FactProgram` fact is proved
  and a `FactCodegen` fact is a codegen-faithfulness axiom of the `bytes-set`
  class.
- **The routing is inherited unchanged.** Professor round 1 rejected Rev 1 over
  routing, and `deliveredParams` and `exportCondition` read no category.
  Measured, not assumed.
- **`checker_soundness_version` does not change.** The affected population is
  empty, because no sidecar can name a builtin that does not exist.
- **`wasi.fs.exists` declares no fact.** Fact predicates are int-only and its
  kind is `RText`.
- Four edge cases added, one a positive witness with a stated discriminating
  test. Risk 1 restated. Section 11's routing marked shipped.
- **Scope settled by the user**: `FS-STAT-1` and `FS-EXISTS-1` ship together.

**Four records still described the clamp Rev 2 withdrew on 2026-08-19, and were
corrected on 2026-09-05**: the `FS-STAT-1` roadmap row, `driver-ll-phase4-proposal.md`
section 14 (annotated, not rewritten, because it is settled), this proposal's own
section 8 verification mapping, and a comment in `compiler/src/LLMLL/RespFact.hs`
that named the withdrawn clamp as the `FactCodegen` firing witness. That comment
shipped at v0.17.0, sixteen days after the withdrawal. Section 4's correction
notice asked for two of the four and the request was not carried out.

### Professor round 1, 2026-08-15

| Finding | Disposition |
|---|---|
| `doesFileExist` cannot express the three-way answer | **Narrowed, by measurement.** The primitive was wrong and the design was not. `getModificationTime` plus `System.IO.Error` gives the answer in `base`, so the `unix` dependency the finding predicted is not needed |
| The `wasi.fs.exists` authority argument is false under mode 0111 | **Accepted.** Section 6 rewrites the claim instead of repairing it |
| The clamp on `wasi.fs.stat` fails open | **Accepted, and it overturns settled content.** Section 4 withdraws the clamp and names the two records that need correction |
| The probe-then-act interlock is a TOCTOU race | **Accepted.** Section 3 withdraws it and makes `wasi.fs.rmdir` idempotent |
| No channel exists to state the clamp | **Accepted, and it is convergence.** Both readers reached it independently. Filed as `RESP-FACT-1` in section 5 |
| `:deterministic` on a `wasi.fs` import is unaddressed | **Accepted.** Edge case 7 |
| `RCode` collapses four meanings | **Accepted, reversing Rev 1.** Section 6 reports the kind as `RText` |
| Ship `wasi.fs.rmdir` alone and first | **Accepted.** It is the document's structure now |

### Rev 1, 2026-08-15

Proposed all three in one change, with a kind code on `RCode`, a clamp on the
age, a non-idempotent `rmdir`, and a subset claim for the probe's authority.
Four of those five are withdrawn above.
