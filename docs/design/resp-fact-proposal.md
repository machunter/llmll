---
name: resp-fact-proposal
title: "RESP-FACT-1: an effect's result carries a proved property to its caller"
status: "Rev 6, SETTLED and SHIPPED as v0.17.0 (`d5dd5a8`, 2026-09-04). Rev 5's receiving rule admitted a false SAFE (cell R-4) and its completeness measurement missed `open` (cells R-5, R-6). Rev 6 adds the delivery rule (§5.3), the entry-module rule and the export condition (§5.2), folds the three cells, lowers `(Serve)` in the emitter instead of refusing it (§11), and states the premise's three disclosure cases (§12). All three §11 prerequisites are discharged; §16 records which routed findings the ship closed and which stay open."
date: 2026-09-04  # Rev 6
author: language-team
consumers: [compiler-engineer, professor, documentation-lead, user]
reviewed_by: docs/archive/professor-reviews/resp-fact-proposal-review.md (folded into the Appendix below at v0.17.0)
---

# RESP-FACT-1: an effect's result carries a proved property to its caller

**One line.** A builtin that establishes a property cannot hand it to the program, so the caller
writes a runtime guard. Rev 1 attached the fact to the **match-arm binder** and the professor round
refuted that: one arm carries the replies of many builtins. Rev 2 attaches the fact to the
program's **own control tag**, which the program must prove it holds. Rev 6 adds the half Rev 2 left
implicit: the tag a step proves and the response it reads must both be the ones the harness delivered
on the current turn (§5.3).

---

## 0. What changed in Rev 2

| Review finding | Rev 2 response |
|---|---|
| 1. The per-builtin fact and the per-arm attachment do not agree (`LLMLL.md:1770`) | **Accepted. Rev 1 §4.1 is withdrawn.** The fact now reaches a binder only under a proved control-tag precondition (§5) |
| 2. The `bytes-zero` analogy does not carry, because codegen writes the constructor and not the payload | **Accepted, and sharpened by measurement.** There are three payload sources, not two (§6). Rev 1's §7 mapped all facts to one stamp |
| 3. The precedent's soundness came from a syntactic restriction that §3 left behind | **Accepted.** Rev 2 carries the restriction over to the **issuing** seam, where the command is in scope (§5.2) |
| 4. §6 omitted the degenerate input that refutes the design | **Accepted.** The refuting cells are now §1, written before the design |
| 5. §8 rests on `TRUST-AXIOM`, whose granularity is open | **Accepted.** §12 states the granularity Rev 2 needs, and names it a ship prerequisite |
| 6. Session types supply the property by construction, and are out of scope | **Accepted as scope, with a correction.** The project already tracks this as `CMD-A`, and neither Rev 1 nor the review cites it (§5.5) |

Three claims in the review and in Rev 1 did not survive measurement. §1.2, §2.3 and §16 give them.

---

## 1. The refuting cells, written first

The review asks for the refuting cell before anything else. This section is that cell, plus the
cell that refutes **Rev 2**. All builtins used here ship at v0.16.2.

### 1.1 R-1: a fact leaks to a second producer of the same arm

Three shipped builtins publish `RCode`: `wasi.http.response` (`CodegenHs.hs:530`),
`wasi.clock.monotonic` (`CodegenHs.hs:732`) and `wasi.proc.run` (`CodegenHs.hs:880-881`).

Declare, in Rev 1's per-builtin table, that `wasi.http.response` delivers `RCode` with payload
`{v : int | v >= 100}`. The bound is true of an HTTP status. Now write a program that never calls
`wasi.http.response`:

```lisp
;; Producer 2 of the SAME arm. wasi.proc.run answers RCode 0 on a clean exit.
(def-shell run-step [r: Rc] -> ((Rc, Ctl), Command)
  (go r (Running)
      (wasi.proc.run "/bin/true" [] "." "/dev/null" "/dev/null" 60 "/dev/null")))

;; The receiving step. Under Rev 1 the RCode binder carries v >= 100 here,
;; because Rev 1 attaches the fact BY ARM.
(def-shell status-out [x: Response] -> int
  (post (>= result 100))
  (match x
    ((RCode n) n)
    (_         100)))
```

**What running it shows.** At HEAD, with no fact, `status-out` is refuted. That is measured: cell
c6 in §2.1 is this shape and liquid-fixpoint reports the `RCode` arm does not satisfy the post.
Under Rev 1 §4.1 the binder gains `n >= 100`, the arm satisfies the post, and `status-out` reports
SAFE. A run of the program delivers `RCode 0`, so `status-out` returns 0. **A verified verdict then
stands over a false post.** That is `SAFE-ARG`, and the cell exhibits it rather than describing it.

The cell is a reaching-SAFE witness, not a class member. It turns a correct refutation into a false
SAFE, and the delta is one declared fact.

### 1.2 The review's own cell does not refute, for two reasons

The review's cell gives `wasi.fs.stat` the fact `{v : int | v >= 0}` and takes
`wasi.clock.monotonic` as the second producer. Two measurements say that cell would pass.

1. **`wasi.fs.stat` does not exist at v0.16.2.** `builtinEnv` declares eighteen `wasi.*` names
   (`TypeCheck.hs:158-274`) and `wasi.fs.stat` is not among them. `rg 'wasi\.fs\.stat'` over
   `compiler/src/` returns nothing. The builtin is a proposal in
   `fs-capability-trio-proposal.md` §4. The cell cannot be built.
2. **The leaked fact is true of the second producer.** `wasi_clock_monotonic` publishes
   `RCode (fromIntegral ns)` where `ns` comes from `getMonotonicTimeNSec`
   (`CodegenHs.hs:729-732`). That function returns a `Word64`, so every reading is non-negative and
   `n >= 0` holds. The cell leaks a true fact and shows no failure.

A cell whose leaked fact is true of the second producer passes vacuously. The review names this
discipline itself, at `MATCH-TERM-EQ-1` (roadmap :71), and its own cell does not meet it. **The
defect the review found is real. The cell it wrote does not display the defect.** R-1 above leaks a
fact that is false of the second producer, so it does.

### 1.3 R-2: one arm, two different codegen guarantees

`RList` has two producers and codegen treats them differently.

- `wasi_fs_list` returns `RList (sort entries)` (`CodegenHs.hs:683`). The `sort` is emitted by the
  compiler, and `CodegenHs.hs:166` emits its import.
- `wasi_proc_args` returns `RList as` (`CodegenHs.hs:720`). There is no `sort`.

A sortedness fact declared for the `RList` arm, and attached by arm, reaches an argument-vector
binder that codegen never sorted. This refutes Rev 1 §4.3's arm-level `RList` admission directly. It
also shows that the guarantor question (§6) and the attachment question (§5) are one question.

### 1.4 R-3: the cell that refutes Rev 2

Rev 2 rests on the issuing rule in §5.2. This cell is its acceptance test, and it must be in the
gate before the feature ships.

```lisp
;; One tag, two different commands. The issuing rule must bind (Listing) to
;; NOTHING, so listing-step must NOT receive wasi.fs.list's fact.
(def-shell fan [r: Rc b: bool] -> ((Rc, Ctl), Command)
  (if b
      (go r (Listing) (wasi.fs.list "/tmp"))
      (go r (Listing) (wasi.proc.args))))
```

**What running it shows.** The verifier must withhold the fact, so a `listing-step` whose post
depends on it must be refuted. If the fact is granted, the implementation collected one producing
site and not all of them, and Rev 1's defect has reappeared at a new seam. An implementation that
walks a single `def`, rather than the whole module, fails this cell.

### 1.5 R-4: a delivered response reaches a step under a different tag

Rev 5's receiving rule grants the fact to any def whose `pre` proves `(= p T)`. Nothing ties `p` or
`x` to the current turn. This cell satisfies every Rev 5 rule and reaches a false SAFE.

```lisp
(type Ctl (| Probe) (| Ran) (| Halt))
(def-shell go [r: int p: Ctl c: Command] -> ((int, Ctl), Command)
  (pair (pair r p) c))
;; Ran is BOUND to wasi.http.response: probe-step is its only producer.
(def-shell h [p: Ctl x: Response] -> int
  (pre (= p Ran))
  (post (>= result 100))
  (match x ((RCode n) n) (_ 100)))
;; outer runs under Probe, whose reply is wasi.proc.run's exit code, and
;; hands that reply to h with a tag it wrote itself.
(def-shell outer [q: Ctl x: Response] -> int
  (pre (= q Probe))
  (post (>= result 100))
  (let [(t Ran)] (h t x)))
(def-shell probe-step [r: int x: Response] -> ((int, Ctl), Command)
  (go (outer Probe x) Ran (wasi.http.response 200 "")))
;; :init pairs Probe with (wasi.proc.run "/bin/sh" ["-c" "exit 1"] ...), and
;; step dispatches on (second s). Full file: resp-fact-implementation-plan.md, appendix.
```

**What running it shows.** At HEAD `verify` refutes `h` and nothing else, so `outer`'s call-pre
`(= t Ran)` discharges through the let equality. Under Rev 5, `Probe` binds to `wasi.proc.run`,
`Ran` binds to `wasi.http.response`, and `h` receives `n >= 100` on its `RCode` binder. `h` then
verifies. At runtime the first reply is `RCode 1`, `outer` passes it to `h`, and `h` returns 1.
**A verified verdict stands over a false post.** The delta is the one granted fact. A constructed
value, `(h Ran (RCode 5))`, is the same defect: `RCode` is a callable value (`TypeCheck.hs:292-300`)
and that file checks, verifies and builds (c42). §5.3 adds the rule that refuses both.

### 1.6 R-5: `open` puts the tag constructor in an importer's expression position

Rev 5 §5.2 said a second module cannot produce the tag and cannot write the precondition. Cells c30,
c31 and c33 measured that without `open`. With it, both halves cross.

```lisp
;; lib.llmll
(type Ctl (| Boot) (| Ran))
(def-shell mk-lib [] -> Ctl Ran)
```

```lisp
;; main.llmll
(import lib)
(open lib)
(def-shell mk [] -> Ctl Ran)
(def-shell mk2 [] -> Ctl (Ran))
(def-shell recv [p: Ctl] -> int
  (pre (= p Ran))
  (post (= result 0))
  0)
```

**What running it shows.** `llmll check` passes. `llmll verify` reports `recv` body-faithful and
SAFE. `llmll build` passes. `Module.hs:274-283` exports constructors as values under the same
`(export …)` filter as functions, and `TypeCheck.hs:1748-1752` injects opened exports as bare names.
So a library-declared tag type is producible and preconditionable wherever the library is opened.

### 1.7 R-6: a program module is importable, and an importer can replace its command

The engineer's plan proposed an entry-module rule and argued that no module can import the entry
module without a cycle. Professor round 5 refuted the argument with this cell.

```lisp
;; amain.llmll: Ctl, go, a step a-step, and a console def-main. No export list.
;; bmain.llmll:
(import amain)
(open amain)
(def-shell b-step [s: (int, Ctl) input: string x: Response] -> ((int, Ctl), Command)
  (pair (first (a-step s input x))
        (wasi.proc.run "/bin/true" [] "." "/dev/null" "/dev/null" 5 "/dev/null")))
```

**What running it shows.** `bmain` checks, verifies SAFE and builds. It keeps the tag `a-step`
set and replaces the command, so on the next turn the harness delivers `wasi.proc.run`'s reply
under `amain`'s tag. If `amain` held a fact-requesting step reached from `a-step`, that step would
run on a reply its fact does not describe, and `amain`'s sidecar would say verified. `bmain`
requests no fact, so an analysis that is opt-in per module is inert there. The condition that
closes this is on `amain`'s exports, and §5.2 states it.

---

## 2. What was measured, at `llmll 0.16.2`

The binary is the one built after `0fa4452` (MATCH-TERM-EQ-1) and it reports `llmll 0.16.2`.

### 2.1 Verification cells

Each cell is a small file passed to `llmll verify`. Every post below is **false of the body**, so a
correct body-faithful verdict is a refutation. A `SAFE` line therefore reports a lost refutation.

`RList` is written `RL` below. "Names `RL`" means the match has an arm of the form `((RList l) …)`.

| Cell | Shape | Names `RL`? | Verdict |
|---|---|---|---|
| c1 | `def`, `x: Response`, arms `(RCode n)` and a catch-all `_` | no | **body-faithful**, refuted |
| c2 | `def`, a user four-arm sum, same shape | n/a | **body-faithful**, refuted |
| c3 | `def`, all five arms, payloads written `_` | yes | **rejected at check**: "unrestricted match" |
| c6 | `def-shell`, arms `(RCode n)` and a catch-all `_` | no | **body-faithful**, refuted |
| c10 | `def-shell`, **four** named arms plus a catch-all `_` | no | **body-faithful**, refuted |
| c11 | c10 with one payload written `(RText _)` | no | **body-fallback**, SAFE |
| c13 | a user sum with one payload written `_` | n/a | **body-fallback**, SAFE |
| c14 | the same user sum, every payload named | n/a | **body-faithful**, refuted |
| c20 | `(pre (= p Serve))`, three arms, post `(= result 0)` | n/a | **body-faithful**, SAFE |
| c21 | c20 with the `pre` deleted (negative control) | n/a | **body-faithful**, refuted |
| c22 | tag `pre`, `Response` match, and a dispatching caller | no | **body-faithful** both; `call-pre` on the caller; refuted on the `RCode` arm |
| c23 | c20 with `(Serve)` written in place of `Serve` | n/a | **liquid-fixpoint crash**: "The sort Phase is not numeric" |
| c24 | `def-shell`, **all five** arms named, no catch-all | **yes** | **body-fallback**, SAFE |
| c25 | c24 written as a `def` | **yes** | **body-fallback**, SAFE |
| c26 | a user **four**-arm sum, all arms named, no catch-all | n/a | **body-faithful**, refuted |
| c27 | a user **five**-arm sum, all payloads `int`/`string`, no catch-all | n/a | **body-faithful**, refuted |
| c28 | `def-shell`, `(RCode n)`, `(RList l)`, and a catch-all `_` | **yes** | **body-fallback**, SAFE |
| c29 | a user sum with a `list[string]` arm named, catch-all present | n/a | **body-fallback**, SAFE |
| c30 | an importing module, `def`, writes an imported nullary constructor | n/a | **rejected at `check`**: callee not body-faithful, not in the trusted prelude |
| c31 | c30 as a `def-shell` | n/a | `check` **passes with a warning**; `llmll build` **fails** with the same text as an error |
| c32 | an importing module takes the tag type as a parameter and matches on it | n/a | **checks clean**. Patterns cross the module boundary |
| c33 | an importing module writes `(pre (= p Ran))` on that parameter | n/a | **`error: unbound variable 'Ran'`**. A contract clause is expression position, so the receiving side is module-local |
| c34 | `def-shell` returning `((int, Ctl), Command)`, with a `post` | n/a | **body-fallback** (`sigPairUnsafe`, `FixpointEmit.hs:2508-2513`): `Command` is not sortable |
| c35 | an importing module writes `(open lib)`, then `Ran`, `(Ran)` and `(pre (= p Ran))` | n/a | **checks, verifies SAFE, builds** (R-5) |
| c36 | a module imports and opens a `def-main` module, wraps its step, replaces the command | n/a | **checks, verifies SAFE, builds** (R-6) |
| c37 | `(export)` with no names | n/a | **parses** (`Parser.hs:420-427`, `many pIdent`) |
| c38 | a caller passes a literal tag, `(h Ran x)`, to a def with `(pre (= p Ran))` | n/a | **liquid-fixpoint crash**: "RHS without single conjunct" on the closed-true `(1 = 1)` |
| c39 | `(let [(p (second s))] (match p …))` over a pair parameter | n/a | **liquid-fixpoint crash**: "Constraint with free vars [s]" |
| c40 | a body-faithful dispatcher passes `(ctl-of s)` to a tag-preconditioned def | n/a | **liquid-fixpoint crash**: free call-result binder |
| c41 | a dispatcher takes `p: Ctl` as a parameter and passes it bare inside its `((Ran) …)` arm | n/a | **body-faithful**, `call-pre` emitted, SAFE |
| c42 | a `def-shell` writes `(RCode 5)` and passes it to a `Response` parameter | n/a | **checks, verifies, builds** |
| c43 | the generated `data Response` | n/a | `RCode Integer` (`CodegenHs.hs:479-482`): the pass-through does not wrap |

Four results decide this proposal.

1. **A match on a `Response` parameter is body-faithful when it does not name the `RList` arm and
   binds every payload it does name** (c1, c6, c10, c22). It falls back otherwise (c24, c25, c28).
   The `RCode` binder is reflected in the first shape. The emitter seeds a payload-sort key for
   each payload-bearing constructor (`FixpointEmit.hs:968-974`, `adtKeys`, whose guard is
   `length ctors >= 2` and is marked n-ary), a tag key (`FixpointEmit.hs:979-985`), and it resolves
   `TCustom "Response"` to its `TSumType` body through `builtinAliases`
   (`TypeAdmissibility.hs:258-270`, unioned by `buildAliasMap` at `:237-239`).

   **Two independent triggers send the def to fallback, and neither is a catch-all.** The first is
   naming an arm whose payload sort is outside the fragment. `admissiblePayload`
   (`FixpointEmit.hs:2561-2566`) accepts `TInt`, `TBool` and `TString` and rejects `TList TString`,
   so `adtKeys` seeds no key for `RList` and a match that names that arm cannot be translated. The
   second is writing a payload as `_` rather than binding a name (c11, c13).

   **The refuting cells for the broader rules.** A rule stated as "`def` against `def-shell`" is
   refuted by c25 against c10. A rule stated as "a catch-all arm is what keeps the match in the
   fragment" is refuted **twice**: c27 has no catch-all and is body-faithful, and c28 has a
   catch-all and falls back. A catch-all correlates with the fragment only because, for `Response`
   specifically, it is how a program avoids naming the one inadmissible arm. c29 shows the trigger
   is general rather than `Response` specific: a user sum with a `list[string]` arm behaves the
   same way.
2. **The `RCode` binder is unconstrained today** (c6, c22). That is the gap this row names.
3. **A control-tag precondition works, and it does real work** (c20 against c21). The pair
   discriminates: the same body is SAFE with the precondition and refuted without it. The
   precondition is admitted because an all-nullary enum parameter is not value-opaque
   (`FixpointEmit.hs:1523-1526`, the ENUM-EQ-FALLBACK note), and it is integer equality after the
   tag desugaring, so it stays in QF-LIA.
4. **A caller discharges the tag precondition on the call-pre channel** (c22 reports
   `call-pre obligations: dispatch`).

Together those four say the seam Rev 2 needs is shipped. Only the fact is missing.

Cells c34 to c43 were added at Rev 6. Three of them decide the receiving side: c35 and c36 refute the
module-local completeness claim, and c42 shows a `Response` value is constructible. c34 and c38 to c41
bound the shapes a program can write today, and §10 and §16 carry them.

### 2.2 The c10 reconciliation

A second reader re-ran c10 and reported `body-fallback`. The two runs disagreed because they were
two different programs, and the fault is in this document's own row description. Rev 1 of this
section described c10 as "five branches, every payload named", which reads as five named
constructors. It is four named constructors and a catch-all. Here is the file, verbatim:

```lisp
(def-shell r5-bad [x: Response] -> int
  (post (>= result 1))
  (match x
    ((RCode n) 0)
    ((RText t) 1)
    ((RErr e)  1)
    ((RNone)   1)
    (_         1)))
```

Re-run at HEAD, verbatim, the output is:

```
   .fq written to /tmp/c10_five_nolist.fq
   body-faithful: r5-bad
   Running liquid-fixpoint ...
error: body verification of 'r5-bad' failed (then-branch does not satisfy postcondition) (constraint #0)
```

**c10 replicates.** The other reader's cell enumerated all five constructors, `RList` included, which
is c24 in the table above and does fall back. Both measurements are correct. The row description was
not, and it is corrected above.

The reconciliation produced the sharper rule in §2.1, and it also refuted the first rule proposed to
explain it. The catch-all is not the mechanism: c27 has none and stays in the fragment, and c28 has
one and leaves it. Naming an arm whose payload sort is outside the fragment is the mechanism, and
c29 shows it is not specific to `Response`.

### 2.3 Two records are incorrect, and one of them is Rev 1's own

**`LLMLL.md:1782-1786` is half right, and the two halves need separating.** The NOTE in §9.7 says
matching on `Response` is outside the body-faithful fragment, and that a `def` that matches on it
falls back to contract-only verification.

- **The NOTE describes correctly** the shape that names the `RList` arm. Cells c24, c25 and c28 all
  fall back, and the code comment at `TypeAdmissibility.hs:265-268` says exactly this about that
  arm: its payload "reflects to the opaque FQList carrier, so a body matching this arm falls back".
- **The NOTE gets wrong** the shape that does not name `RList` and binds its payloads. Cells c1,
  c6, c10 and c22 are body-faithful and refute a false post. That shape is the common one, and it
  is the shape this proposal depends on.

So the defect is a scope error, not a false statement: the NOTE promotes a claim that holds of one
arm into a claim about the whole type, and it names §5.3.5 as the reason, which points at the
payload-sort boundary rather than at `Response`. The accurate sentence is that a match **naming the
`RList` arm** falls back, as any list-mentioning body does. **Routed to doc-lead. `LLMLL.md` is not
edited here.**

**Rev 1 §1's own probe row was wrong.** It recorded "A pure `def` matching on `Response` falls back
from body-faithful VC", and added "An identically shaped user sum behaves the same". The second half
is correct and refutes the first: cell c2 shows an identically shaped user sum is body-faithful and
refuted. Rev 1 then contradicted itself, because its §6 item 1 promised a verdict that is
"verified, body-faithful". Rev 1 measured one shape and generalised it to the type, which is the
same scope error the spec NOTE makes.

**The severity claim survives the narrowing, and the narrowing strengthens it.** The question is
whether a wrongly attached fact reaches a real constraint. Under Rev 1 the fact attaches at the
`RCode` binder. `RCode`'s payload is `int`, which `admissiblePayload` accepts, so a match that names
`RCode` without naming `RList` is body-faithful, and the fact lands in a constraint that a false
post can then satisfy. Cell c6 is that shape and cell R-1 in §1.1 is built on it. **The live shape
and the fact-carrying shape are the same shape.** The inert shape is the one that names `RList`,
and §7 excludes `RList` from carrying a fact for independent reasons, so nothing this proposal
grants lands in an inert position. Rev 1 believed the fallback was universal, which would have made
the defect harmless everywhere. It is not harmless anywhere a fact is granted.

### 2.4 Where each arm payload comes from

Read the emitted body of each builtin and ask which sub-expression supplies the arm's payload.

| Builtin | Arm | Payload sub-expression | Source |
|---|---|---|---|
| `wasi.http.response` | `RCode` | `RCode (fromIntegral code)` (`CodegenHs.hs:530`) | the **program**'s own argument |
| `wasi.proc.run` | `RCode` | `RCode 0` (`CodegenHs.hs:880`) | **codegen**, a literal |
| `wasi.proc.run` | `RCode` | `RCode (fromIntegral c)` from `ExitFailure c` (`CodegenHs.hs:881`) | the **OS** |
| `wasi.clock.monotonic` | `RCode` | `getMonotonicTimeNSec` (`CodegenHs.hs:731`) | the **OS** |
| `wasi.fs.list` | `RList` | `sort entries` (`CodegenHs.hs:683`) | **codegen** for the order, the **OS** for the entries |
| `wasi.proc.args` | `RList` | `as` from `getArgs` (`CodegenHs.hs:720`) | the **OS** |
| `wasi.fs.read` | `RText` | file contents (`CodegenHs.hs:668`) | the **OS** |

One builtin spans two sources on two paths. `wasi.proc.run` is codegen on the success path and the
OS on the failure path. §6 gives the composition rule for that.

---

## 3. Rev 1's seam is refuted, and the spec says why

`LLMLL.md:1770` states it: "Arms classify shape, not provenance." The same sentence continues that
`RCode` carries HTTP statuses, process exit codes and clock readings alike. §2.4 measures exactly
that: three builtins, one arm.

Rev 1 declared the fact table per builtin (§4.2) and attached the fact per arm (§4.1). A `Response`
carries no record of the command that produced it, so no rule maps one to the other at the arm. The
delivery rules put the two ends in different functions. `LLMLL.md:1761-1762` gives a step the
response to the command **it returned on the previous turn**, as a parameter of the next step. The
measured consumer has that shape: `docclaims.llmll:395-506` holds seven step functions, each taking
`x: Response`, and no one function sees both ends.

**One correction to the review here.** The review writes that `seq-commands` "closes the last
route", citing discard-left (`LLMLL.md:1512`). Discard-left closes the route at the **receiving**
site, which is the review's point and it is right. It does not close the route at the **issuing**
site, where the whole command expression is in scope and the rule is deterministic: a composed
command yields the right operand's response. §5.2 reads that rule rather than being stopped by it.

---

## 4. The coupling the program already writes

`LLMLL.md:1771-1773` says a program that needs to know which command a response answers "records
that in its own state, where the coupling is visible in the program's type". The measured consumer
does exactly this, and the coupling is written in one expression.

`docclaims.llmll:272-273` declares the constructor of a step return:

```lisp
(def-shell go [r: Rc p: Ctl c: Command] -> ((Rc, Ctl), Command)
  (pair (pair r p) c))
```

Every `go` call names the next control tag and the command in the same application.
`docclaims.llmll:395-405` shows one def doing it twice, on two branches:

```lisp
(if (string-empty? named)
    (go r2 (Probe)   (wasi.proc.run ...))
    (go r2 (Listing) (wasi.fs.list (fixture-dir r2))))
```

`probe-step` (`docclaims.llmll:407-409`) also pairs `(Listing)` with `wasi.fs.list`. So both
producers of the tag `Listing` agree. On the receiving side, `dc-step`
(`docclaims.llmll:506-516`) matches the tag and dispatches:

```lisp
(match (ctl-of s)
  ((Listing)  (listing-step (rc-of s) x))
  ...)
```

`listing-step` is reached only from that arm. Its `x: Response` is therefore `wasi.fs.list`'s reply,
and the tag `Listing` is what says so. **The coupling is not missing. It is unread.**

---

## 5. Design: the fact is keyed on the control tag

The review ranks a projection whose precondition names the program's own state tag first. Rev 2
takes it, and adds the part the review left unspecified: what binds a tag to a builtin. Without that
part, option 1 relocates the fact to a better channel and still has no discharge.

### 5.1 Surface

A **control tag** is a parameter whose declared type is an all-nullary enum. A step that wants a
fact takes one, and declares a precondition naming it.

```lisp
(type Ctl (| Boot) (| Probe) (| Listing) (| Ran))

;; Every producer of (Ran) pairs it with wasi.http.response, so (Ran) is BOUND
;; to it. The declared fact for (wasi.http.response, RCode) is {v : int | v >= 100},
;; which is program-determined under section 6 and therefore admitted.
(def-shell ran-step [p: Ctl r: Rc x: Response] -> int
  (pre (= p Ran))
  (post (>= result 0))
  (match x
    ((RCode n) n)          ;; n : {v : int | v >= 0} in this arm
    (_         0)))
```

The program writes no runtime guard. The precondition is the citable obligation that replaces it,
and the caller proves it. Write the constructor **bare** in the clause. §11 says why.

The JSON-AST does not change. The fact is compiler-side, the tag is an ordinary parameter, and the
precondition is an ordinary `pre`.

**A fact request, defined (Rev 6).** A def holds a fact request when its `pre` has a conjunct
`(= p T)` or `(= T p)`, `p` is a parameter whose type is a sum declared in this module, `T` is a
constructor of that sum, and the def has a parameter of type `Response`. Every rule of §5.2 and
§5.3 is inert in a module with no request, which is what makes the design opt-in.

### 5.2 The issuing rule: which builtin a tag is bound to

This rule is syntactic and the compiler checks it. It is `bytes-zero`'s discipline, moved to the
seam where the command is in scope. `TypeCheck.hs:1595-1600` and `:1633-1634` admit `(bytes-zero)`
only where the declared return determines its length. The rule below admits a tag binding only where
the returned pair determines its command.

**The collection runs over the defs that RETURN the pair, not over the expressions that build it.**
Rev 2 collected "every site that builds a `(State, Command)` pair". Professor round 2 refuted that
against the measured consumer. **The census is thirteen defs, and both earlier counts were wrong.**
`docclaims.llmll` declares thirteen defs whose return type is `((Rc, Ctl), Command)`: `go` (`:272`),
`finish` (`:369`), `skip` (`:375`), `boot-step` (`:395`), `probe-step` (`:407`), `listing-step`
(`:420`), `next-fixture` (`:426`), `readfix-step` (`:433`), `ran-step` (`:453`), `readout-step`
(`:456`), `score` (`:489`), `dc-init` (`:496`) and `dc-step` (`:506`). Only two of them build a pair
directly. Professor round 3 said eight, from a truncated search, and its table omitted `ran-step`,
`readout-step`, `score` and `dc-step`. That count is corrected here and routed back in §17. The
omission does not change round 3's conclusion, because adding defs cannot remove a `⊥`. `go` (`:273`) builds every pair in the program out of its own
parameters, so its command component is the variable `c`, and a rule reading build sites binds
nothing at all. §1.4's own acceptance cell is written through `(go r (Listing) …)`, so Rev 2's test
already assumed the rule reads call sites.

**A transparent constructor is excluded from the collection, and it is classified on the result
rather than on the syntax.** A pair-returning def builds a pair it does not choose when a component
resolves to one of that def's own parameters. `go` (`:273`) is the measured case: its body is
`(pair (pair r p) c)` over the parameters `p` and `c`. Rev 3 analyzed `go` directly, found a
parameter where it wanted a constructor, and returned `⊥`, which under Rev 4's module-global reading
would stop every module that has such a helper.

Rev 4 classified transparency by reading the def's own pair expression. Professor round 4 found that
test is one level deep. A wrapper that returns `(go r (Listing) c)`, with `c` its own parameter,
builds no pair of its own. It is not classified transparent, its `Sites` reaches `go`'s pair through
the substitution row, and the command component is then a variable that `ρ` does not map. The result
is `⊥` and the module stops. **Rev 5 classifies on the result, so a wrapper at any depth classifies
with `go`.**

`Sites(D)` returns one of three things: a set of `(tag, builtin)` pairs, the marker `PARAM`, or the
marker `⊥`. `PARAM` means every failure came from a component that resolved to one of `D`'s **own**
parameters. `⊥` means some other form defeated the recursion. `⊥` wins over `PARAM` when both occur.

**`D` is a transparent constructor when `Sites(D)` contains `PARAM`.** It then contributes nothing of
its own to the module union, and it is read only through the substitution row at each of its call
sites, where its parameters are bound to actual arguments. `go` yields `PARAM` directly. The wrapper
above yields `PARAM` through the substitution, because the component resolves to the wrapper's own
parameter. Both classify the same way and at any depth.

Define `Sites(D)` for a def `D` whose declared return type is a `(σ, Command)` pair. Each element of a
set result is a pair of a control tag and a builtin name. The definition is a structural recursion on
`D`'s body, in an environment `ρ` that carries the let bindings in scope.

| Body form | `Sites` |
|---|---|
| `(pair (pair _ T) C)`, with `T` a nullary constructor written in the source, and `C` either a builtin name, an application whose head is one, or a variable that `ρ` maps to either | `{(T, head C)}` |
| `(if e a b)` | `Sites(a)` union `Sites(b)` |
| `(match e (p₁ a₁) … (pₙ aₙ))` | the union of every `Sites(aᵢ)` |
| `(let [(x₁ e₁) … (xₖ eₖ)] b)` | `Sites(b)`, in `ρ` extended by each `xᵢ` whose `eᵢ` is a builtin name or an application whose head is one |
| `(D' e₁ … eₙ)`, where `D'` returns a `(σ, Command)` pair, transparent or not | `Sites(D')`, with each `eᵢ` substituted for `D'`'s parameter `i` |
| `(pair (pair _ T) C)` where `T` or `C` resolves to one of `D`'s own parameters | `PARAM` |
| any other form | `⊥` |

Two rows changed from Rev 3. The `let` row now carries the surface form the language actually uses,
a bracketed binding group (`docclaims.llmll:396`), and it propagates a binding whose right side is a
command. Without that propagation, `(let [(c (wasi.fs.list p))] (go r (Listing) c))` reaches the pair
row with a variable and yields `⊥`. The propagation is syntactic copy propagation over one form, so
it terminates and it adds no analysis power beyond reading what the program wrote.

**`⊥` withholds every binding in the module, and it is a hard error.** Rev 3 said only "No element is
`⊥`" and professor round 3 found two readings of it. The local reading, where a `⊥` def contributes
nothing and other defs still bind, is **unsound**: a `⊥` def is the one the analysis could not read,
so it may pair the same tag with a different builtin. Rev 4 takes the module-global reading and
states it.

A tag `T` is **bound** to builtin `B` when both of these hold, over the union of `Sites(D)` for every
pair-returning `D` in the module whose result is a set, and over `Sites` of the `:init` expression. A
def whose result is `PARAM` contributes through its call sites and not on its own.

1. Every element carrying `T` carries the same `B`.
2. No `Sites` computation in that union returned `⊥`.

**An implementation may memoize, and the key is the substitution.** `Sites(D')` changes with the
arguments substituted at a call, so a cache keyed on the def alone is wrong. Key it on the def
together with its substituted arguments. The acyclicity condition is what keeps that table finite:
without it the same def could be reached under unboundedly many substitutions.

**When rule 2 fails, the compiler reports an error and names the def.** It does not withhold the fact
quietly. A module that declares no control-tag fact is unaffected, so the rule is opt-in per module.
The quiet alternative fails in a way this project has already routed as a defect: §16 finding 2
records a `def-shell` that downgrades silently where a `def` rejects loudly, and the issuing rule
must not add a second instance of that shape. A withheld fact shows up as a refuted post in an
unrelated def, with nothing naming the cause.

Otherwise `T` is bound to nothing and no fact reaches a step preconditioned on it. Cell R-3 in §1.4
tests rule 1, and because it is written through `go` it also tests that the collection reads call
sites through a transparent constructor.

**`:init` is an expression and `Sites` applies to it.** `LLMLL.md:1533` declares `:init init-expr`
and `:1555` requires only that it return a `(State, Command)` pair. The measured consumer writes
`:init (dc-init)` (`docclaims.llmll:552`), which is a call and which the substitution row reads. An
inline pair reaches the pair row. Anything else is `⊥` and rule 2 then fails.

**Termination.** The substitution row follows the call graph of pair-returning defs. Require that
subgraph to be acyclic, and treat a cycle as `⊥`. The measured consumer needs two hops:
`next-fixture` (`:426-432`) returns `(finish r)` on one branch, and `finish` (`:369-371`) returns
`(go r (Ending …) …)`. A one-hop rule does not read it.

**Cross-module completeness needs one local condition, and Rev 6 states it below.**
Rev 2 rule 3 required the control-tag type to be declared in the same module as every def that
returns it. Professor round 2 objected that the granting module cannot check a condition about
modules it does not see. Measured at `llmll 0.16.2`, the objection does not apply, because a second
module cannot produce the tag unless it opens the declaring module (cell c35, Rev 6). A `def` in an importing module that writes `(Ran)` is rejected
at `check`: "callee 'Ran' is not body-faithful and not in the trusted prelude". A `def-shell` that
writes it passes `check` with `warning: call to unknown function 'Ran'`, and then **fails
`llmll build` with that same text as an error**. The type itself does cross the boundary: an
importing module may take a `Ctl` parameter and `match` on its constructors, and that checks clean.
So constructor patterns cross and constructor application does not. A module-local collection is
therefore complete for a tag whose type the module declares and whose constructors no importer can
open. **Rule 3 is withdrawn**, and the export condition below is the local rule that replaces it. §16 routes the `check`-against-`build` asymmetry, which is a defect
on its own.

**The receiving side is module-local too, and that is the stronger half of the argument.** Professor
round 4 measured it. An importing module that writes `(pre (= p Ran))` fails with
`error: unbound variable 'Ran' (may be in scope at runtime)`. Cell c32 already showed the matching
**pattern** `((Ran) …)` checks clean in the same module. A constructor resolves in pattern position
across a module boundary and does not resolve in expression position, and a contract clause is
expression position. So a step that could receive a fact cannot be written outside the declaring
module at all. That does not depend on finding every producer, which the producer half does. Professor round 5
measured the same clause under `(open lib)`, and it checks and verifies (c35). So this half also rests
on the export condition below.

**The entry-module rule, Rev 6.** The control-tag type, every pair-returning def, `def-main` and
every step that preconditions on the tag must be statements of the entry module, the module
`llmll verify` runs on. Two facts of the compiler force it. Per-function VC emission is entry-only
(`FixpointEmit.hs:430-432`), so a requesting step in an imported module is never verified with a
fact in any run. The delivery rule of §5.3 takes its source from `:step`, which lives beside
`def-main`. A tag type declared in an imported module, or a pair-returning callee in an imported
module, is refused with an error naming the type or the def. The measured consumer satisfies the
rule today. A program that grows past one module keeps the machine together or gives up the fact.

**The export condition, Rev 6.** The entry-module rule does not close the import boundary on its
own, because a module with `def-main` is importable and openable (cell c36, R-6). A module that
holds a fact request must declare an `(export …)` list, and that list must name no constructor of
the control-tag type and no def from whose body a requesting step is reachable in the call graph.
`(export)` with no names satisfies both and is the idiom this proposal teaches for a program module.
Rev 6 states the two-part rule rather than "export nothing" because the two-part rule is exactly
the condition the soundness argument uses, and it leaves a program free to export a helper that
touches neither the tag nor a requesting step. Both parts are local: the call graph exists
(`HoleAnalysis.hs:606-616`) and the export filter exists (`Module.hs:280-283`). A module with a
request and no export list, or with a list naming such a def, gets an error naming the def and the
requesting step it reaches. This answers professor round 2's objection to Rev 2 rule 3: the
granting module checks a property of its own export list, not of modules it does not see.

**The state shape is scope.** The pair row reads `(pair (pair _ T) C)`, so the supported state is
`(σ, Ctl)` with the tag second, under a `((σ, Ctl), Command)` return. A bare `Ctl` state, or a pair
with the tag first, is `⊥` at every site. Two ordinary idioms are `⊥` as well, and correctly:
`(pair s c)` with `s` the incoming state pairs every tag with one command, and a `do` body discards
every command but the last (`CodegenHs.hs:1592-1600`). The error for either names the rewrite: write
the tag constructor in the returned pair.

**`seq-commands` is handled, not excluded.** When the command component is
`(seq-commands a b)`, take the head of `b`, recursively. `LLMLL.md:1512` makes that the response's
producer, and the rule is deterministic.

### 5.3 The receiving rule: the fact enters under a proved precondition, on delivered values

A step `D` receives the declared fact for `(B, arm)` on each `Response` arm binder when three
conditions hold. First, `D`'s declared precondition entails `(= p T)` for a parameter `p` of the
control-tag type and a tag `T` bound to `B` by §5.2. Second, `p` is a **delivered tag** of `D`.
Third, every `Response` parameter of `D` is a **delivered response** of `D`. A step with no such
precondition receives `FQTrue`, which is today's behaviour. A step with the precondition and a
parameter that is not delivered gets a hard error naming `D`, the parameter and the first call site
that refuses it. Rev 5 had the first condition only, and cell R-4 refutes it.

The caller discharges `(= p T)` on the call-pre channel. Cell c22 measures that the obligation is
raised and reaches the caller. Cell c20 against c21 measures that the precondition then does work.

**Delivered values, defined.** Let `S` be the `:step` function, a def named in `def-main` or a `fn`
form written there. `checkStepArity` (`TypeCheck.hs:1895`) fixes its parameters as a state, an
input string and a `Response`. `S`'s state parameter is the **delivered state** and `S`'s
`Response` parameter is the **delivered response**, by the harness edge (§5.4). For every other
def `D` in the entry module, a parameter at position `i` is delivered when every call
`(D e₁ … eₙ)` in the entry module passes, at position `i`, an expression the grammar below admits
in the scope of the calling def. An in-module call of `S` is checked like any other call. The
definition is a greatest fixpoint: start with every parameter delivered, remove a parameter when
one call site refuses it, and repeat until nothing changes.

**The grammar of delivered expressions.** Scope tracks `let` and `fn` bindings. A name rebound by a
`let` or by a `fn` parameter is not delivered inside that binding's extent, whatever it was outside.

| Kind | Admitted form |
|---|---|
| state | a bare variable that is a delivered-state parameter of the enclosing def |
| tag | (t1) a bare variable that is a delivered-tag parameter of the enclosing def |
| tag | (t2) `(second v)` with `v` a delivered state |
| tag | (t3) `(F v)` with `v` a delivered state and `F` an entry-module def of one parameter `q` whose body is `(second q)` |
| tag | (t4) a `let`-bound name whose right side is (t2) or (t3), read inside the binding's extent |
| tag | (t5) the bare constructor `T`, or `(T)`, written inside the arm `((T) …)` of a `match` whose scrutinee is (t1) to (t4) |
| response | a bare variable that is a delivered-response parameter of the enclosing def |

Every other form is not delivered: a literal tag outside its own arm, a `let`-bound literal, a
constructor application, a call result, a projection other than `second` of the state, and a value
taken out of a `Result` or a user sum. Row (t5) is sound because the arm establishes that the
scrutinee equals `T`, so passing `T` passes the delivered tag's value. It also matters for
ergonomics: c40 measures that passing `(ctl-of s)` crashes the solver today, and c38 measures that
passing a literal produces a closed-true call-pre, which the engineer's plan folds. A dispatcher
therefore writes `(ran-step Ran (rc-of s) x)` inside its `((Ran) …)` arm.

**What the rule is.** It is an integrity-flow discipline. The harness is the only source of a
delivered value, a bare-variable copy preserves the property, and everything the program builds does
not. Professor round 5 names the tradition: the tag is an auxiliary variable in the sense of Owicki
and Gries, and it is sound only when the program cannot assign it independently of the value it
describes. `CMD-A` retires the rule, because a `Command[a]` index puts the producer in the type of
`x` (§5.5).

**Why this is not Rev 1 with extra words.** In Rev 1 the fact and its attachment came from two
sources: a table keyed by builtin, and a binder typed by arm. Nothing joined them. In Rev 6 the tag
names the builtin by rule 5.2, the caller proves the tag under the precondition, and the delivery
rule ties both the tag and the response to the turn the harness produced. Cell R-4 is the case
where the third link was missing.

### 5.4 The three delivery rules, each checked

`LLMLL.md:1759-1768` lists four delivery rules. Three of them touch this design.

- **`:init` supplies the first response.** Its command is performed and its reply reaches the first
  step. So the `:init` pair is a collected site under rule 5.2. A program with **no** `:init` starts
  at `RNone`, so its start tag binds to nothing.
- **The terminating step's command is not performed.** A tag reached only by the terminating step
  receives no response, so any fact keyed on it is unused rather than unsound.
- **One response per performed command.** This is what makes the chain close. Step N returns tag `T`
  with command `B`. Step N+1 is dispatched on `T` and receives `B`'s reply.

**The harness lemma, Rev 6.** The console loop is `loop s r = let (s', cmd) = step s line r in …
loop s' (perform cmd)` (`CodegenHs.hs:1839-1844`), with `r0 = perform initCmd`. So on every turn
the state `s` and the response `r` that `step` receives belong together: `r` is the reply to the
command that was returned in the same pair as `s`, by the previous step or by `:init`. Rule 5.2
says every returned pair whose tag is `T` carries a command whose head is `B_T`. Together: if
`(second s)` is `T`, then `r` is `B_T`'s reply. The delivery rule of §5.3 makes a step's `p` equal
to `(second s)` and its `x` equal to `r` for the current turn, so `(= p T)` entails that `x` is
`B_T`'s reply. `seq-commands` keeps the lemma, because the reply is the right operand's
(`LLMLL.md:1512`). RC-4 keeps it vacuously, because a terminating step's command is not performed
and no step receives its reply. The lemma rests on `harness_assumptions` (`TrustReport.hs:304-325`),
which the trust report already discloses.

### 5.5 This is not the existential that `CMD-A` rules out

`effect-response-channel-proposal.md:528-547` already names this problem: "Nothing types the pairing
between the command issued and the response received." It routes the closure to **`CMD-A`**,
parameterized `Command[a]` (`:649-668`). Neither Rev 1 nor the review cites either passage. The
review reaches for session types and parameterised monads from outside, and the project has a
settled internal row for the same property. **Rev 2 records the link, which is the credit the
project's own design memory is owed.**

That section also says "There is no cheap middle", because typing the response by the command makes
the step's result existential in the command's index. Rev 2 does not contradict it. Rev 2 does not
**type** the pairing. It leaves `Response` monomorphic, and asks the program to **prove** which tag
it is in. Nothing is existential: the tag is a first-order value the program already carries, the
equality is integer equality after desugaring, and the fact applies only under that proved equality.
Rev 2 therefore **anticipates** `CMD-A` and does not substitute for it. When `CMD-A` lands, the
issuing rule becomes redundant and the fact rides the type.

**Rev 6 adds one sentence to that link.** The delivery rule of §5.3 is the syntactic surrogate for
the index `CMD-A` would put in the type of `x`. When `Command[a]` lands, the `Response` a step
receives carries its producer, the tag precondition is redundant for the fact, and the delivery rule
retires with it.

---

## 6. The criterion for the fact table, and the stamps

This answers the review's second open question. The criterion is a syntactic test on the emitted
builtin body: **which sub-expression supplies the payload argument of the arm constructor.** §2.4
applies it. There are three answers, not two.

| Category | Test | Who proves the property | Stamp |
|---|---|---|---|
| **Program-determined** | the payload is a command argument the program supplied | the **program**, at the issuing site, on the effective-precondition channel | `codegen_semantics_version` covers only the pass-through |
| **Codegen-determined** | the payload is a literal, or a pure total function the compiler emits | **codegen** | `codegen_semantics_version` (`LLMLL.md` §3.5) covers the whole fact |
| **OS-determined** | the payload comes from a syscall result | **nobody, inside LLMLL** | **no existing stamp.** Needs its own disclosure, naming the assumed behaviour and the platform |

**So the two do not share a stamp.** Program-determined and codegen-determined facts both ride
`codegen_semantics_version`, and they ride it for different amounts: the first stamps only that
codegen passed the value through, the second stamps the value itself. OS-determined facts ride
nothing that exists today.

**Composition rule.** An arm reachable on several paths takes the **weakest** category over those
paths. `wasi.proc.run`'s `RCode` is codegen-determined on the success path (`RCode 0`) and
OS-determined on the failure path (`ExitFailure c`), so the arm is OS-determined.

**Rev 2 admits program-determined and codegen-determined facts only.** OS-determined facts are
deferred until the disclosure channel exists. That line is what makes §12 a precise prerequisite
rather than a general worry.

One correction to the review. The review writes that an `RList` fact "usually does not" qualify
because listing order rests on OS behaviour. Measurement says order is the half that **does**
qualify: `wasi_fs_list` applies `sort` in the emitted body (`CodegenHs.hs:683`). Length and element
content are the OS half. The split runs through the arm, not around it.

---

## 7. Which arms may carry a fact in Rev 2

| Arm | Payload | Rev 2 |
|---|---|---|
| `RCode` | `int` | **Admitted**, for program-determined and codegen-determined facts. Linear integer bounds, QF-LIA |
| `RList` | `list[string]` | **Excluded**, for two independent reasons (below) |
| `RText`, `RErr` | `string` | **Excluded.** String structure sits outside Σ_auto (`STRLIT-BODY-1`) |
| `RNone` | none | No payload, so no fact |

`RList` is excluded twice over, and Rev 1 §4.3 admitted it. First, `admissiblePayload`
(`FixpointEmit.hs:2561-2566`) accepts `TInt`, `TBool` and `TString` and rejects `TList TString`, so
`adtKeys` seeds no sort key for the `RList` arm and there is no binder to refine. Second, a length
or content fact is OS-determined under §6. A **sortedness** fact for `wasi.fs.list` is
codegen-determined and would qualify on the second ground, and it still fails on the first. It is
the natural first extension once the arm has a sort.

The first reason costs more than the `RList` arm alone. Cells c24, c25 and c28 measure that naming
the arm sends the **whole def** to body-fallback, so a fact granted on that def's `RCode` binder
would be unused. A program that wants a fact must reach `RList` through a catch-all rather than
name it. §10 records that constraint against the measured consumer.

---

## 8. Edge cases and degenerate inputs

1. **Positive witness, concrete, with a shipped builtin and an admitted category.**
   `wasi.http.response` (`TypeCheck.hs:160`) declares its `RCode` payload `{v : int | v >= 100}`.
   That fact is **program-determined** under §6, which is a category this proposal admits.
   **`wasi.proc.run` is not the witness.** §6's composition rule makes its `RCode` arm
   OS-determined, through the `ExitFailure c` path, and §6 excludes that category. Rev 2 offered
   both builtins here, and professor round 2 found that the first names a fact this proposal does
   not grant. Every `go` producing `(Ran)` pairs it with that builtin. `ran-step` in §5.1 declares `(pre (= p Ran))` and `(post (>= result 0))`, and its
   body is the match in §5.1. Today, measured as cell c22, the binder is unconstrained and the def
   is refuted. Under this proposal it verifies body-faithfully.
   **Channel: contract. Fragment: QF-LIA.**
2. **A tag paired with two builtins.** Cell R-3. The tag binds to nothing, so the fact is withheld
   and the dependent post is refuted. **Channel: type (a compiler-checked syntactic rule), §5.2.**
3. **A step with no control-tag precondition.** The binder gets `FQTrue`, exactly today's
   behaviour. This is the migration story: no corpus moves until a program adds a precondition.
   **Channel: spec is silent (intentional).**
4. **A tag paired with a computed command.** The body does not match §5.2's pair row, so `Sites` is
   `⊥`. Under Rev 4 rule 2 then **fails with an error naming the def**, in a module that declares a
   control-tag fact. A module that declares none is unaffected.
   A program that selects its command with an `if` inside the command position gets no fact.
   **Channel: type, §5.2.**
5. **A control tag that is not an all-nullary enum.** The rule is opt-in per module, so a program
   that declares no fact sees no change. A program that declares one, and that still carries a
   payload arm on the tag it pairs, gets the §5.2 error rather than a quiet withdrawal.
   `docclaims.llmll:260-268` is the measured case: `Ctl` carries `(| Ending int)` and `(| Done int)`. `nullaryEnumArity`
   (`TypeAdmissibility.hs:461-472`) returns `Nothing` for a payload-bearing sum, and
   `clauseOverOpaqueSumParam` (`FixpointEmit.hs:1515-1526`) then treats the parameter as opaque and
   forces contract-only verification. **The one measured consumer does not qualify today.** §10
   states what that costs.
6. **`seq-commands` in the command position.** The head is taken from the right operand,
   recursively, per `LLMLL.md:1512`. **Channel: type, §5.2.**
7. **An importing module that names the tag.** It cannot produce one. A `def` writing `(Ran)` is
   rejected at `check`, and a `def-shell` writing it fails `llmll build`. A `match` on an imported
   tag type checks clean, so patterns cross and construction does not. The module-local collection
   in §5.2 is complete for that reason, and not because of a rule this proposal states.
   **Channel: type, measured at `llmll 0.16.2`.**
8. **A program with no `:init`.** The first response is `RNone`, so the start tag binds to nothing
   and no fact is granted on the first turn. **Channel: type, §5.2 and §5.4.**
9. **A transparent constructor, at two depths.** `go` (`:273`) returns the pair and builds it from
   its parameters `p` and `c`, so `Sites(go)` is `PARAM` directly. A wrapper that returns
   `(go r (Listing) c)` with `c` its own parameter builds no pair of its own, and reaches `go`'s pair
   through the substitution row, where the command component resolves to the wrapper's own
   parameter. `Sites` is `PARAM` there too. Both contribute nothing of their own and both are read
   at their call sites. Rev 4 classified on the def's syntax and caught only the first, so the second
   became `⊥` and stopped the module. **Channel: type, §5.2.**
10. **Positive witness for the new error.** A module declares one control-tag fact, and it also holds
    one pair-returning def whose body the table cannot read, for example a def that returns the pair
    out of a `match` on a string. `Sites` for that def is `⊥`, rule 2 fails, and the compiler
    **reports an error naming that def**. It does not verify with the fact withheld. This is the
    firing case: without it the rule would be a guard that only ever stays quiet.
    **Channel: type, §5.2.**
11. **A match shape that leaves the body-faithful fragment.** Two shapes do it, and a granted fact is
   then unused rather than unsound. Writing a payload as `_`, as in `((RText _) 1)` instead of
   `((RText t) 1)`, downgrades the whole def: cell c11 against c10 isolates that to one token.
   Naming the `RList` arm does the same: cells c24, c25 and c28. In a `def` the first shape is
   rejected loudly; in a `def-shell` both are silent. Neither depends on a catch-all, which c27 and
   c28 refute in both directions. **Channel: spec is silent (gap, and §16 routes it).**
12. **A wrong fact in the table.** The single unsound direction, identical in kind to a wrong arity
   in `nullaryEnumArity`. Tests must pin it, and §12 discloses it. **Channel: trust.**
13. **A program whose own contract names the `Response` parameter by bare name.** Still falls back
    through `clauseOverOpaqueSumParam`. Not fixed here; this is Rev 1's P2 and it belongs with
    `MATCH-WIDEN`. **Channel: spec is silent (gap).**

14. **A delivered response passed under a tag the program wrote.** Cell R-4. `outer` holds the
    delivered response under `Probe` and passes it to `h` with a `let`-bound `Ran`. The delivery
    rule refuses the call: `t` is a `let`-bound literal, not (t1) to (t5). The error names `outer`,
    the call `(h t x)` and the parameter `p`. **Channel: type, §5.3. This is the positive witness
    for the delivery error.**
15. **A constructed `Response`.** `(h Ran (RCode 5))`, cell c42. The second argument is a
    constructor application, so `x` is not delivered and the call is refused. **Channel: type,
    §5.3.**
16. **A dispatcher passes the literal tag inside its arm.** `(match (ctl-of s) ((Ran) (ran-step Ran
    (rc-of s) x)) …)` with `s` the delivered state. `(ctl-of s)` is (t3), so the arm admits `Ran`
    under (t5), and `x` is `S`'s response. The call-pre `(= p Ran)` is closed and true after the
    tag desugaring, and the emitter folds it rather than emitting the constraint c38 crashes on.
    **Channel: type for the admission, contract for the fold. §5.3 and §16 item 7.**
17. **The stay-put idiom.** `(pair s (wasi.io.stdout ""))` with `s` the incoming state. `Sites` is
    `⊥` and the error says to write the tag constructor in the returned pair. The measured
    consumer already does (`docclaims.llmll:515-516`). **Channel: type, §5.2.**
18. **A `do` body in a pair-returning def.** `Sites` is `⊥`, because `emitDo` discards every
    command but the last. Same error. **Channel: type, §5.2.**
19. **An importer opens the tag type.** Cell R-5. The importer is the entry of its own run, and
    `Ctl` is declared elsewhere, so the entry-module rule refuses its request with an error naming
    `Ctl`. **Channel: type, §5.2.**
20. **An importer wraps the machine.** Cell R-6. With `(export)` in `amain`, `bmain` cannot name
    `a-step`, and `check` reports an unbound name. Without an export list, `amain`'s own `check`
    fails first: it holds a request and exports `a-step`, from which the requesting step is
    reachable. **Channel: type, §5.2. This is the positive witness for the export error.**
21. **A closed-false call-pre.** `(h Boot x)` where `h` requires `(= p Ran)`. The substituted
    predicate is `(0 = 1)`. The emitter must keep it, so the refutation stands. **Channel:
    contract.**
22. **Two `Response` parameters on one requesting step.** Both must be delivered, and then both are
    the same value. **Channel: type, §5.3.**
23. **A requesting step that calls itself.** `(h p x)` inside `h` passes bare delivered parameters,
    and the greatest fixpoint keeps them delivered. **Channel: type, §5.3.**

---

## 9. Verification mapping

| Obligation | Channel | Fragment |
|---|---|---|
| The control-tag precondition `(= p T)` at a call site | **contract** (effective precondition) | **QF-LIA**, auto-discharged. The tag desugars to its declaration index, and an all-nullary enum parameter is not value-opaque (`FixpointEmit.hs:1523-1526`). Measured: c20, c21, c22 |
| An `RCode` payload bound at a match-arm binder, under a proved tag | **contract** | **QF-LIA**, auto-discharged by liquid-fixpoint. `LLMLL.md` §5.3.3 |
| Tag-to-builtin binding (rule 5.2) | **type** | Not an SMT obligation. A syntactic check over the module's returned pairs, in the class of `bytes-zero`'s determining-context rule (`TypeCheck.hs:1595-1600`) |
| Delivery of `p` and `x` (rule 5.3) | **type** | Not an SMT obligation. A greatest fixpoint over the entry module's call sites, with the grammar of §5.3 |
| The export condition and the entry-module rule (§5.2) | **type** | Not an SMT obligation. A read of the module's `(export …)` list against the call graph, and of the declaring module of the tag type |
| The program-determined premise at an issuing site | **contract** | Three cases. A literal argument folds at `check`: it passes or it is an error. A scalar parameter of the issuing def yields one `call-pre:<builtin>` constraint in **QF-LIA**, with the issuing def's `pre` as hypothesis and no path guard, which is sound and incomplete. Any other argument is a `check` error naming the site |
| The declared fact's own validity, program-determined | **trust**, reduced | The value property is proved by the program. The residue is codegen's pass-through, on `codegen_semantics_version` (`LLMLL.md` §3.5) |
| The declared fact's own validity, codegen-determined | **trust** | Not discharged. Rides `codegen_semantics_version`, as `bytes-zero` does |
| The declared fact's own validity, OS-determined | **trust** | Rides no stamp that exists. **Excluded from Rev 2** (§6) |
| A string-payload property | contract | **Outside Σ_auto.** Excluded, per `STRLIT-BODY-1` |

No new sort. No new theory. No new predicate vocabulary. No new builtin, so the freeze policy is
not engaged.

---

## 10. What Rev 2 does not deliver

The review asks that the trade be stated plainly rather than hidden.

**The program writes something.** It declares a control-tag parameter and a precondition. That
replaces a runtime guard with a citable proof obligation, and it is more text, not less.

**The one measured consumer does not qualify today.** `docclaims.llmll`'s `Ctl` carries an `int` on
two arms (`:260-268`), so it is not an all-nullary enum and a clause naming it falls back (edge case
5). The fix is program-side and small: move the exit code into the `Rc` record and leave `Ctl`
nullary. It is not a compiler change. Until some program does it, the delivered value is zero, and
Rev 2 claims no corpus movement on its own.

**A second constraint stacks on top, and the measured consumer trips both halves of it.**
`docclaims.llmll:291-297` (`code-in`) writes `((RErr _) 127)`, `((RText _) 127)` and
`((RList _) 127)`. That is three wildcard payloads, which is cell c11's shape, and it names the
`RList` arm, which is cell c28's shape. Either alone sends the def to body-fallback, so a fact on
its `RCode` binder would be inert. The remedy is to bind the payload names and to reach `RList`
through a catch-all instead of naming it. The phase 4a plan already records the first half of that
discipline for `def` bodies (`driver-ll-phase4a-implementation-plan.md:150-154`); the second half is
new here and §16 routes it.

**A third program-side change stacks under §5.2.** Professor round 2 found that the collection rule
must read call sites, because every pair in the measured consumer is built inside `go`. Rev 3's
rule does read them, so the program needs no rewrite for this reason. The cost moved into the
compiler instead: the rule is now a recursion over pair-returning defs with substitution at calls,
and it needs an acyclicity condition. That is a larger piece of work than a check over literal
build sites, and §14 says it has no existing home.

**The acceptance target is concrete, and it is eight tags.** After the `Ctl` repair above, and with
transparent constructors excluded, `Sites` over `docclaims.llmll` binds `Boot` to `wasi.proc.args`,
`Probe` to `wasi.proc.run`, `Listing` to `wasi.fs.list`, `ReadFix` to `wasi.fs.read`, `Ran` to
`wasi.proc.run`, `ReadOut` to `wasi.fs.read`, `Ending` to `wasi.io.stdout` and `Done` to
`wasi.io.stdout`. Two tags may name one builtin; the rule constrains a tag to one builtin and not the
other direction. That set is what an acceptance test asserts, and it replaces Rev 3's weaker
statement that the delivered value is zero until a program changes. **The test must be written inside
one module.** All eight tags, every producing def and every preconditioned step sit in the module
that declares `Ctl`, and §5.2 records why they must: a control-tag precondition does not resolve
outside the declaring module. An acceptance test split across two modules fails for a reason that has
nothing to do with the issuing rule.

**Two more program-side changes stack, and Rev 6 states the verdict they buy.** The consumer has
no `(export …)` list, so it must add `(export)` before it can request a fact. Its steps must take
the tag as a parameter, and its dispatcher must pass the literal tag inside each arm (edge case 16)
or `(ctl-of s)` (row t3). `dc-step` (`:506`) falls back under `sigPairUnsafe` because `Rc` is a
`Json` value (c34), so it emits no call-pre and never discharges a step's `(= p T)` in the
fragment. Every issuing def falls back for the same reason, so the premise of a program-determined
fact chains to an asserted `pre` unless the argument is a literal. The verdict the consumer can earn
is therefore: the requesting step verifies body-faithfully, under one asserted caller obligation and
one disclosed assumed fact. §12 requires the trust report to say exactly that.

**A recursive step machine disables the feature for its module.** §5.2 treats a cycle among
pair-returning defs as `⊥`, and `⊥` is now module-global, so one step function that loops by calling
itself withholds every binding in that module and reports the error. Recursion is otherwise supported
with a measure and a total-correctness discharge (`LLMLL.md` §4.2). The measured consumer has no such
cycle: `listing-step` reaches `next-fixture`, which reaches `finish`, and the graph closes. Rev 4
states the cost rather than hiding it in a termination note, because a program that adopts the
feature must choose between the fact and a self-calling step.

**`RList` gains nothing** (§7), and several open builtin rows deliver `RText`, which stays out.

---

## 11. Prerequisites, in order

1. **The emitter lowers a parenthesized nullary constructor; the type checker does not refuse it.**
   `(pre (= p Serve))` verifies. `(pre (= p (Serve)))` crashes liquid-fixpoint with "The sort Phase
   is not numeric" (cell c23). `desugarCtorValues` (`FixpointEmit.hs:2636-2670`) lowers a bare
   `EVar` to its tag and leaves `EApp "Serve" []` intact at its `EApp` row (`:2648`). The type
   checker already treats `(Serve)` as the value `Serve` (`TypeCheck.hs:2209-2214`). Rev 3 asked
   for a type-checker rule that refuses the parenthesized form in a clause. Rev 6 withdraws that
   rule: it would make clause position stricter than body position for one form the checker
   admits. The fix is one row in `desugarCtorValues`, and the test is that c23 and c20 emit
   byte-identical `.fq`. The same row lowers `(h (Ran) x)` in a body.
2. **The fact and the runtime must land in one commit.** A declared fact whose emitted code does not
   establish it is simply false.
3. **`TRUST-AXIOM` must settle its granularity before this ships.** §12. **DISCHARGED at
   v0.17.0.** The prerequisite asked for the granularity to settle, not for the `TRUST-AXIOM` row
   to close. §12 states the granularity, and `d5dd5a8` implements it as the per-function
   `assumed_facts` rows. The roadmap `TRUST-AXIOM` row records this ship as its first disclosed
   population. That row stays **OPEN** for the `bytes-set` and `bytes-zero` axioms, which this
   proposal does not touch.

---

## 12. Coupling to `TRUST-AXIOM`

`TRUST-AXIOM` (roadmap :102) records that a builtin's assumed fact reaches the solver on no channel
of the trust report. Rev 1 §8 asked to be its first disclosed population and the review answered
that a population cannot be first for a mechanism whose granularity is undecided. That is correct,
and Rev 2 states the granularity it needs rather than asking for one.

**The disclosure must be per function and per `(tag, builtin)` pair.** Per artifact is not enough,
for the same reason the arm was not enough: a reader must be able to see which builtin's fact a
given verdict rests on, and under Rev 2 the tag is what names it. A line saying only that some
axiom was used repeats Rev 1's discrimination failure on the reporting surface.

Rev 2 reduces the population rather than only enlarging it. Program-determined facts (§6) put the
value property on the contract channel, so only the pass-through is disclosed. Codegen-determined
facts are disclosed whole. OS-determined facts are excluded until the channel carries them, which is
why §6 draws the line where it does.

**The line must also say what discharges the premise, Rev 6.** For a program-determined fact the
issuing argument is one of three things: a literal that folded at `check`, a parameter whose
`call-pre:<builtin>` constraint the solver proved under the issuing def's `pre`, or that same
constraint where the issuing def's `pre` is itself an asserted caller obligation because its caller
fell back (c34). The trust report names the case per fact. A line that says only "assumed fact"
repeats, on the reporting surface, the discrimination failure this section exists to prevent.

---

## 13. Routing: `RESP-FACT-1` is a prerequisite of `FS-STAT-1`

Carried forward from Rev 1 §9, unchanged, and the review confirms it.

`FS-STAT-1` (roadmap :60) still states in bold that the clamp "discharges `[S12-DOM]`'s first
conjunct (`(>= newest-artifact-age 0)`) **by construction**". `RESP-FACT-1` (roadmap :87) states
that the claim was corrected because it named no channel. Both cannot hold at HEAD. The discharge
claim is false today and becomes true once a `Response` fact has a channel. So **`RESP-FACT-1` is a
prerequisite of `FS-STAT-1`**, and `FS-STAT-1`'s row should say so rather than claim a discharge it
cannot perform. Routed to doc-lead, not fixed here.

Rev 2 adds one measured note. `wasi.fs.stat` does not exist at v0.16.2 (§1.2), so `FS-STAT-1` needs
its builtin as well as this channel. The clamp, when written, is **codegen-determined** under §6, so
it falls inside the categories Rev 2 admits and needs no new disclosure.

---

## 14. Affected surface

- `compiler/src/LLMLL/TypeCheck.hs`: the per-builtin fact table beside `builtinEnv` (`:158-274`)
- `compiler/src/LLMLL/TypeAdmissibility.hs`: the fact predicate, beside `nullaryEnumArity`
  (`:461-472`)
- `compiler/src/LLMLL/FixpointEmit.hs`: the match-arm binder seam, beside the `adtKeys` seeding
  (`:968-974`); the module has zero `Response` occurrences today
- A new pure module, `compiler/src/LLMLL/RespFact.hs`, holding the fact table, the request scan,
  `Sites`, and the delivery pass. The engineer's plan puts it there because `FixpointEmit.hs` does
  not import `TypeCheck.hs` and both need the table. The checker calls it once per module and turns
  every failure into a hard error; the emitter calls it for the `refEnv` entries; the trust report
  calls it for the disclosure line
- `compiler/src/LLMLL/TypeCheck.hs`: the call from `checkStatements` (`:1352`), and the export
  condition read against the module's `(export …)` list
- `compiler/src/LLMLL/VerifiedCache.hs`: `checkerSoundnessVersion` (`:325-326`) changes, because a
  verdict now depends on the fact table
- `compiler/src/LLMLL/FixpointEmit.hs:2648`: the `EApp` row of `desugarCtorValues` lowers a
  parenthesized nullary constructor (§11 prerequisite 1). The type-checker rejection Rev 3 asked
  for is withdrawn
- `compiler/src/LLMLL/FixpointEmit.hs:1340-1360`: a call-pre whose substituted predicate is closed
  and true is folded, not emitted (c38); a closed and false one is kept (edge case 21)
- `LLMLL.md` §13 (per-builtin facts), §9.7 (`Response`, and the incorrect NOTE at `:1782-1786`),
  §5.3.3 and §5.3.5 (the boundary)
- `docs/design/fs-capability-trio-proposal.md` §5: this proposal supersedes that placeholder
- `docs/design/effect-response-channel-proposal.md` §528-547: `CMD-A`'s relationship to this row
  (§5.5)
- Roadmap rows `RESP-FACT-1`, `TRUST-AXIOM` (§12), `FS-STAT-1` (§13)

---

## 15. Risks

1. **One unreadable pair-returning def stops the feature for its whole module.** Verification
   ergonomics. §5.2. `⊥` is module-global, by design and for soundness. The failure is now loud, so
   a program learns which def to rewrite, but a module with one unanalyzable step gets no facts at
   all until that def changes. **Effect: complicates. It is the price of the sound reading.**
2. **The issuing rule is a whole-module analysis, and its completeness rests on a measurement.**
   Soundness. §5.2. The collection is module-local. It is complete only because an importing module
   cannot apply the tag's constructor, which cells c30 and c31 measure at `llmll 0.16.2`. That is a
   property of the current compiler and not a stated language guarantee, so a future change to
   constructor visibility would make the collection incomplete and let a fact reach an unbound tag.
   **Effect: blocks unless the property is pinned. Pin it with c30 and c31 in the gate, beside cell
   R-3, which tests rule 1.**
3. **The fact and the codegen must land together.** Soundness. §11 item 2.
   **Effect: blocks. One commit, not two.**
4. **Undisclosed assumed facts.** Trust. `TRUST-AXIOM`, and §12.
   **Effect: complicates. Settle the granularity first.**
5. **The delivered value is zero until a program changes.** Verification-ergonomics. §10.
   **Effect: only matters at scale, and it makes the row hard to demonstrate. Pair it with the
   `docclaims` `Ctl` change so the first cell is real.**
6. **The wildcard-payload cliff makes a granted fact silently inert.** Verification-ergonomics.
   Edge case 8, cell c11. **Effect: complicates. §16 routes it.**
6. **Rev 1's P2 stays open.** Spec-drift. A bare `Response` parameter in a clause still falls back.
   **Effect: complicates. Name it; do not imply it is fixed.**
7. **Strings stay out.** Verification-ergonomics. `STRLIT-BODY-1`. Several open builtin rows deliver
   `RText`. **Effect: only matters at scale.**

8. **Only one dispatcher shape verifies today.** Verification ergonomics. c39 and c40 crash the
   solver on a let-bound projection and on a call-result argument; c41 is the shape that works,
   and row (t5) admits the literal-in-arm form. §16 routes the two crashes. **Effect: complicates
   adoption for a scalar-state program. The measured consumer falls back instead of crashing.**
9. **The delivery rule is syntactic and conservative.** Verification ergonomics. §5.3. A value that
   is delivered by any route the grammar does not name is refused, loudly. **Effect: complicates.
   The grammar grows by measurement, one row per refused idiom, as the pair row did.**
10. **The export condition forces `(export)` onto program modules.** Scope. §5.2. A program that
    wants a fact and exports a def reaching a requesting step must split the export or drop the
    fact. **Effect: complicates. It is the local price of a sound import boundary.**

---

## 16. Findings routed out of this proposal

**Closure state, measured against HEAD on 2026-09-05.** Items 1, 4, 6 and 7 are closed. Items 2, 3,
5, 8, 9 and 10 stay open and each one needs a roadmap row. Item 11 is deferred to a named row. Do
not read this list as the record of what shipped; the CHANGELOG entry `## v0.17.0` and `d5dd5a8`
are that record.

1. **`LLMLL.md:1782-1786` states a per-arm boundary as a whole-type one.** §2.3. The NOTE is
   correct for a match that names the `RList` arm (c24, c25, c28) and wrong for one that does not
   (c1, c6, c10, c22). The accurate sentence is that a match **naming the `RList` arm** falls back,
   as any list-mentioning body does, which is what `TypeAdmissibility.hs:265-268` already says.
   **To doc-lead. CLOSED** (`2c0a6f3`). The NOTE in `LLMLL.md` §9.7 now names the `RList` arm and
   the `_`-payload trigger, and says that neither trigger is specific to `Response`.
2. **Two shapes silently downgrade a `def-shell` to body-fallback, and both can hide a false post.**
   First, naming an arm whose payload sort is outside the fragment (c24, c25, c28, and c29 on a
   user sum). Second, writing a payload as `_` rather than binding it (c11, c13, isolated to one
   token against c10 and c14). In a `def` the second shape is rejected at `check` with "unrestricted
   match", which is loud and is recorded (`driver-ll-phase4a-implementation-plan.md:150-154`,
   `Syntax.hs:810`). In a `def-shell` neither shape is reported, and a false post then reaches SAFE.
   Both are general, not `Response` specific. **To compiler-engineer, as a new row. OPEN, and the
   row is not filed.** The row needs a tag; this proposal does not assign one.
3. **A parenthesized nullary constructor in a contract clause crashes liquid-fixpoint.** Cell c23
   against c20. The type checker accepts both forms and only one reaches a verdict.
   **To compiler-engineer, as a new row. OPEN, and the row is not filed.** The row needs a tag;
   this proposal does not assign one. `d5dd5a8` lowers the parenthesized form in
   `desugarCtorValues` (§11 prerequisite 1), so this proposal's own witness no longer crashes. The
   general defect in contract-clause position is unchanged.
4. **"`LLMLL.md` §4.1" is the wrong citation for the anti-laundering clause.** `LLMLL.md:419` is
   "Function Declarations". The clause is at `LLMLL.md:1068`, inside §5.4 "The Proof Artifact"
   (`:1062`), and the "§4.1" is
   `docs/archive/shipped-design-specs/proof-artifact-proposal.md:52`. Rev 1 §8, the review's
   finding 2, and the roadmap `TRUST-AXIOM` row all repeat it. **To doc-lead. CLOSED.** No live
   document cites `§4.1` for the anti-laundering clause now. The roadmap `TRUST-AXIOM` row and the
   `v0.14.0` row both cite `§5.4`.
5. **A cross-module constructor application warns at `check` and fails at `build`.** Cells c30 to
   c32. A `def-shell` in an importing module that writes an imported nullary constructor passes
   `llmll check` with `warning: call to unknown function 'Ran'`, and `llmll build` then fails with
   the same text as an error. A `def` is rejected at `check`. The condition is identical and the
   severity is not, so a program can pass the check gate and fail the build gate on one token.
   This proposal depends on the behaviour (§5.2 cross-module completeness) and does not need the
   asymmetry. **To compiler-engineer, as a new row. OPEN, and the row is not filed.** The row
   needs a tag; this proposal does not assign one. `d5dd5a8` keeps the warning at `check` for
   cell E's importer, which the CHANGELOG records as a deviation from the plan.
6. **`FixpointEmit.hs:3425-3427` cites stale line numbers.** The comment says `TypeCheck.hs:1216`
   and `:1250` restrict `(bytes-zero)`. At HEAD those lines are the `typeCheck` entry point and a
   cache comment. The restriction is real and lives at `TypeCheck.hs:1595-1600`, `:1633-1634` and
   `:2655-2657`. The review quoted the comment accurately, so the defect is in the comment.
   **To compiler-engineer. CLOSED, and both the item and its replacement targets were wrong.**
   `d5dd5a8` repaired one comment and left `CodegenHs.hs:582-586` incorrect inside that same
   comment. A sweep of every cross-file citation in `compiler/src` on 2026-09-05 found **nine**
   incorrect citations, not one: four in the `(bytes-zero)` family, two for the map and `=` typing
   rules, and three in `HoleAnalysis.hs`, `LeanTranslate.hs` and `TypeCheck.hs`. All nine are
   repaired. The targets this item names (`:1595-1600`, `:1633-1634`, `:2655-2657`) had themselves
   drifted before the repair ran; the rule is at `checkStatement`'s LEVER-A0 arms for `SDef` and
   `SDefShell`, and at the polymorphic-builtin error path.

   **The durable lesson is the repair method, not the count.** A citation that names a line becomes
   incorrect when any line above it moves, and `d5dd5a8` itself moved `TypeCheck.hs` by one line at
   the import and by twelve more at `checkStatements`. The repairs therefore name the construct and
   tell the reader to grep. No gate catches this class, so it can recur; see the routing note
   below.

7. **A call-pre whose substituted predicate is closed and true crashes liquid-fixpoint.** Cell c38:
   `(h Ran x)` yields `(1 = 1)` and the sanitizer reports "RHS without single conjunct". The
   engineer's plan folds it in-row, because the row's own witness produces the shape.
   **To compiler-engineer, in-row. CLOSED** (`d5dd5a8`, `evalClosedFQ`). A closed and true call-pre
   is folded and not emitted. A closed and false one is emitted as `false`, per edge case 21.
8. **A let-bound projection of a pair parameter leaves the parameter free.** Cell c39. **To
   compiler-engineer, as a new row `PAIR-PROJ-LET-1`. OPEN, and the row is not filed.**
9. **A call-result argument to a call-pre leaves its binder free.** Cell c40. **To
   compiler-engineer, as a new row `CALL-PRE-ARGCALL-1`. OPEN, and the row is not filed.**
10. **A qualified imported constructor does not type-check.** `(def-shell mkq [] -> lib.Ctl lib.Ran)`
    reports `expected lib.Ctl, got Ctl`. So `open` is the only cross-module route to a constructor,
    which is what makes R-5 the whole boundary. **To compiler-engineer, as a new row
    `XMOD-QUAL-CTOR-1`. OPEN, and the row is not filed.**
11. **A module with `def-main` is importable and openable.** Cell c36. Whether a program module
    should be a library at all is a language question this proposal does not decide; the export
    condition makes the answer irrelevant to soundness here. **To language-team, as a scope
    question for a later revision of the module section. DEFERRED, not taken now.** The
    language-team defers it to a `[DESIGN]` roadmap row, `MOD-PROGLIB-1`. The question is normative
    and not empirical: cell c36 measures that a `def-main` module imports and opens today, so no
    grep settles whether it should. It does not belong in `docs/design/theory-questions.md`, which
    holds questions the repository cannot answer. This proposal's export condition makes the answer
    irrelevant to `RESP-FACT-1`'s soundness, so the deferral costs nothing here.

---

**Rows this section owes.** Seven, not three. Items 2, 3 and 5 are routed "as a new row" and carry
no tag. Items 8, 9 and 10 carry `PAIR-PROJ-LET-1`, `CALL-PRE-ARGCALL-1` and `XMOD-QUAL-CTOR-1`.
Item 11 is deferred to `MOD-PROGLIB-1`. Item 6's sweep found a defect class that no gate catches,
which is an eighth candidate row for the compiler-engineer to accept or refuse.

---

## 17. Review history

**Professor round 1, 2026-08-29** (`docs/archive/professor-reviews/resp-fact-proposal-review.md`). Verdict: reject the Rev 1
shape. Six findings, two open questions. §0 maps each finding to its Rev 2 response. Both open
questions are answered: question 1 in §4 and §5, question 2 in §6.

**Rev 2, 2026-09-03.** Withdraws Rev 1 §4.1. Adds the issuing rule, the three-way guarantor split,
and eighteen measured verification cells. Records three claims that did not survive measurement: the
review's refuting cell passes vacuously and names a builtin that does not exist (§1.2); the review's
`RList` guarantor claim inverts which half is codegen's (§6); and `seq-commands` closes the
receiving route only, not the issuing one (§3). Records that Rev 1's own §1 probe row contradicted
its §6 (§2.3).

**Professor round 2, 2026-09-03** (`docs/archive/professor-reviews/resp-fact-proposal-review.md`, `## Round 2`). Verdict:
accept the direction, refuse §5.2 as written. Five findings. The review upholds none of Rev 2's
claims against itself by default: it records that all four of Rev 2's rebuttals against round 1 are
correct, and then raises new findings. Rev 3 answers all five. Finding 1 (the collection rule reads
build sites and the consumer has none) is fixed in §5.2. Finding 2 (rule 3 is not checkable in the
granting module) is answered by **withdrawing rule 3**: the two-module witness the review asked for
was built, and it shows a second module cannot produce the tag, so the completeness rule 3 asserted
is already a property of the language. Finding 3 is fixed in §8. Finding 4 is accepted and moved
into §14. Finding 5 is recorded in §10.

**Professor round 3, 2026-09-04** (`docs/archive/professor-reviews/resp-fact-proposal-review.md`, `## Round 3`). Verdict: accept
the direction, do not send §5.2 to the engineer until `⊥` is decided. The round executed `Sites` by
hand and found two readings, one unsound and one that binds nothing. Rev 4 answers all five findings:
it states the module-global reading, makes the failure a hard error, adds the transparent-constructor
exclusion, adds let copy propagation with the language's own binding form, and applies `Sites` to the
`:init` expression.

**One correction back to that round.** Its table says `docclaims.llmll` has eight pair-returning defs
and lists them. The file has thirteen. The round missed `ran-step` (`:453`), `readout-step` (`:456`),
`score` (`:489`) and `dc-step` (`:507`), and it did not count `go` (`:272`) itself. The conclusion is
unaffected, because adding defs cannot remove a `⊥`, and one of the omitted facts strengthens it:
`go` is a pair-returning def whose components are parameters, so under Rev 3 the module held a `⊥`
that no program change could remove. §5.2 carries the corrected census.

**Professor round 4, 2026-09-04** (`docs/archive/professor-reviews/resp-fact-proposal-review.md`, `## Round 4`). Verdict: Rev 4
is sound. One item blocked the hand-off, and Rev 5 fixes it: the transparent-constructor test read
the def's own syntax, so a wrapper one level out was not classified and became `⊥`, which Rev 4 had
just made a hard error. The round also measured the receiving side and found it module-local, which
is a stronger completeness argument than the producer half Rev 4 gave. Rev 5 folds the measurement,
states the scope limit that follows, adds the memoization note and puts the module condition on
§10's acceptance target.

**Compiler-engineer plan, 2026-09-04** (`docs/design/resp-fact-implementation-plan.md`). Built
cells W and D and found the two defects Rev 6 answers. Proposed a delivery rule and an entry-module
rule, the `desugarCtorValues` lowering in place of the type-checker rejection, the closed-true
call-pre fold, the `checker_soundness_version` change, and the per-function `assumed_facts` line.
Measured c34, c38 to c42.

**Professor round 5, 2026-09-04** (`docs/archive/professor-reviews/resp-fact-proposal-review.md`, `## Round 5`). Verdict:
accept the plan's direction; do not implement until Rev 6 carries the delivery rule, the export
condition and the folded cells. Built cell E (c36), which refutes the entry-module rule on its own,
and measured c37 and c43. Named the delivery rule's tradition and the harness lemma it needs, and
added row (t5). Two questions: the admission grammar with its scoping, and the form of the export
condition. Rev 6 answers both in §5.3 and §5.2.

**Rev 6, 2026-09-04.** Adds the delivery rule to §5.3 with its grammar (t1) to (t5), the harness
lemma to §5.4, the entry-module rule and the two-part export condition to §5.2, and the state-shape
scope. Defines a fact request in §5.1. Folds cells R-4, R-5 and R-6 into §1 and c34 to c43 into
§2.1. Withdraws the type-checker rejection of §11 item 1 in favour of the emitter lowering. Adds
the three-case premise disclosure to §9 and §12. Adds edge cases 14 to 23, risks 8 to 10, and
routed findings 7 to 11. Corrects §5.2's sentence that a second module cannot produce the tag.

**Rev 5, 2026-09-04.** Classifies a transparent constructor on the `Sites` result rather than on the
def's syntax, using a `PARAM` marker distinct from `⊥`, so a wrapper at any depth classifies with
`go`. Adds cell c33. **Rev 5 was settled and ready for the compiler-engineer.** At Rev 5, shipping still
waited on `TRUST-AXIOM`, per §11 prerequisite 3; Rev 6 discharged that prerequisite and shipped.

**Rev 4, 2026-09-04.** Excludes transparent constructors from the collection. States that `⊥` is
module-global and reports an error naming the def. Adds copy propagation for a let-bound command and
corrects the `let` form to the bracketed binding group. Applies `Sites` to the `:init` expression.
Records the acceptance target in §10: eight tags bind on the measured consumer after the `Ctl`
repair. Adds edge cases 9 and 10, the second of which is the positive witness for the new error.

**Rev 3, 2026-09-04.** Restates the §5.2 collection over pair-returning defs, with substitution at
call sites, an acyclicity condition, and the two-hop case the measured consumer needs. Withdraws
rule 3 against cells c30 to c32. Corrects the positive witness to `wasi.http.response`, the one
builtin whose fact §6 admits. Adds the `check`-against-`build` asymmetry to §16.

**Independent re-run of §2, 2026-09-03.** A second reader could not replicate cell c10 and reported
`body-fallback`. §2.2 reconciles it: c10 replicates verbatim, and the other reader ran the
all-five-arms shape, which is c24 and does fall back. This document's row description for c10 was
the fault and is corrected. The re-run forced §2.1's rule to be narrowed from "a match on a
`Response` parameter is body-faithful" to the measured condition, and six cells were added (c24 to
c29) to find the discriminator. The catch-all rule proposed to explain the disagreement was itself
refuted by c27 and c28. §2.3 now separates which shape the spec NOTE describes correctly from which
it gets wrong, and states why the severity claim in §1.1 survives the narrowing.

---

## Appendix — Professor review log

Per DOC-CONSOLIDATE §M2 (settled 2026-05-24), the standalone professor review for this proposal is
folded here and the source file archived to
[`docs/archive/professor-reviews/resp-fact-proposal-review.md`](../archive/professor-reviews/resp-fact-proposal-review.md).
Folded at the close of the line, v0.17.0, with `RESP-FACT-1` shipped.

**Source:** `docs/archive/professor-reviews/resp-fact-proposal-review.md` at commit
`51a428a9f98ae2750e78d1b3767e0e22e9d0645d` (reviewed 2026-08-29 to 2026-09-04; reviewer: Lead Consultant for Formal Language Design).
Five rounds. The per-round dispositions are in [17. Review history](#17-review-history) above and are
not repeated; what follows is each round's ranked recommendation and where it landed.

### Round 1 recommendation, against Rev 1, and its outcome

**Reject the Rev 1 shape; do not send §4.1 to the compiler-engineer.** The match-arm binder cannot
carry a per-builtin fact, because the arm does not name which command the response answers. The
reviewer's direction came from `LLMLL.md` itself: a program that needs to know which command a
response answers records that in its own state, so make the coupling the program already records
readable by the verifier rather than inventing a provenance the type does not carry.

Ranked first was **a projection whose precondition names the program's own state tag**. Rev 2 adopted
exactly that and it is the shape that shipped: the fact is keyed on the program's control tag and
reaches a binder only under a proved precondition. Rev 1 §4.1 is withdrawn.

### Rounds 2 to 4, against Revs 2 to 4, and their outcomes

Round 2 accepted the direction and settled the rule that binds a tag to a builtin. Round 3 forced the
meaning of `⊥` to be module-global and to report an error naming the def. Round 4 found Rev 4 sound
and named one definitional gap: the transparent-constructor test was one level deep. Rev 5 closed it
by classifying a transparent constructor on the `Sites` result rather than on the def's syntax, so a
wrapper at any depth classifies. Round 4 also supplied the missing stronger half of the completeness
argument.

### Round 5 recommendation, against Rev 5 and the engineer's plan, and its outcome

**Refuse implementation until Rev 6 carries three changes.** Round 5 reviewed the plan and Rev 5
together and refuted the receiving side with cells it built:

1. **Cell W** reaches a false SAFE under every Rev 5 rule. The answer is the **delivery rule** (§5.3):
   a fact is admitted only on values that reach the step from `:step` unchanged. Rev 6 carries it.
2. **Cell D** shows `(open lib)` lets an importer write the tag constructor in a `pre`. The answer is
   the **export condition** (§5.2), and `(export)` with no names is the idiom. Rev 6 carries it.
3. **Cell E**, new for that round, shows a module with `def-main` is importable and openable, and an
   importer can keep the imported machine's tag while replacing its command. Rev 6 carries the
   entry-module rule; the residual normative question is deferred as roadmap row `MOD-PROGLIB-1`
   (§16 item 11).

All three landed in Rev 6 and shipped at v0.17.0. The round also produced §16 items 7 to 11, of which
item 7 was fixed in-row by `d5dd5a8`.
