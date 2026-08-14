---
name: env-channel-proposal
title: "ENV-READ-1: an environment channel, and why only one direction of it ships"
status: "Rev 2, SETTLED 2026-08-14 by user adjudication, and READY FOR COMPILER-ENGINEER. The read direction ships; the set direction is deferred and carries one requirement. It answers both professor questions from round 1 and accepts all five findings. TWO OF THE ACCEPTANCES CORRECT THE FINDING THEY ACCEPT, in each case by measurement. (i) The capture hazard is REAL and NARROWER than round 1 stated: `LLMLL.md` §10a does write a captured return value to `<module>.event-log.jsonl`, but a proof artifact carries NO event log, so the exposure is a working directory and whatever archives it, not a shared artifact. (ii) The professor's first question asks which of two properties gives way when an environment read is not captured. NEITHER DOES, because §10a's bitwise claim is already enumerated over clock and PRNG imports and never covered a third source; the sentence still needs an amendment, because an enumeration that reads as a universal is a defect once a third source exists. THE SECOND QUESTION IS ANSWERED BY MEASUREMENT AND THE ANSWER IS YES: an unset name, a name containing `=`, and the empty name all answer the same thing, so `RErr` conflates 'unset' with 'this name cannot name a variable', while a variable that is set and empty stays distinguishable. Rev 2 makes `:deterministic true` on a `wasi.env` import a TYPE ERROR rather than a default, because a default that fails open writes a credential to a file whenever somebody copies a clock import. Rev 1 justified the unary shape from `CAP-NULLARY-1`, which is a compiler artifact; Rev 2 justifies it from least privilege, so the shape no longer depends on where `checkWasiCapability` fires. The set direction is DEFERRED and carries one new requirement: it must express add-to-inherited, because the subject adds one variable and a replace-only record would take `PATH` away from the child. Roadmap rows: `ENV-READ-1` and `PROC-ENV-1`."
date: 2026-08-14
author: language-team
consumers: [compiler-engineer, professor, documentation-lead, experiment-lead, user]
---

# ENV-READ-1: an environment channel

## Summary

LLMLL has no environment channel in either direction. A program cannot read its
own environment, and a program cannot set the environment of a child it spawns.
Both gaps are filed. `ENV-READ-1` covers reading and `PROC-ENV-1` covers
setting.

**This proposal ships the read direction only.** It gives the read a shape that
does not make an existing weakness worse. It defers the set direction, and it
records one requirement that the deferred design must meet.

**The two directions are one namespace and two rows. Do not fold them.** They
are the same namespace and opposite directions. Folding two causes into one row
produced a row that was incorrect for a release at `ALIAS-LOWER-1`.

## 1. What raised this, and what the port actually needs

Port 006 of the TOOL-LL campaign raised both rows. See
[`tool-rfc-006-build-smoke.md`](tool-rfc-006-build-smoke.md).

`ENV-READ-1` is a reclassification and not a discovery. The campaign census
carried "no env access" as COSMETIC, and it gave the reason "argv carries it".
Port 005 tested that reason and it held. **It fails at its second use.**
`scripts/build_smoke.sh` tries three sources for the compiler in order:
`$LLMLL_BIN`, then `PATH`, then `$HOME/.local/bin/llmll`. A `--subject` flag
reproduces the first source. A bare `llmll` reproduces the second.
**The third source needs `$HOME`, and argv carries what a caller passes.** So
the port drops that branch, which is a behaviour difference and not an
invocation difference.

**A disposition tested against one port measures that port. It does not measure
the language.** That is the general result and it belongs in the census.

**`PROC-ENV-1` does not block port 006.** `scripts/build_smoke.sh` sets
`LC_ALL=C` for one child, then prints one of two verdicts. On Darwin it prints
`BUILD-GATE-1 NOT EXERCISED: the LC_ALL=C encoding claim (FS-ENCODING-1)`,
because GHC there resolves UTF-8 whatever `LC_ALL` says. Only Linux settles the
claim. A port that reproduces both branches is faithful.

**One consequence needs routing and it is not a spec change.** On Linux the
reference exercises the claim and the port cannot. Cell 1 of
[`tool-rfc-006-build-smoke.md`](tool-rfc-006-build-smoke.md) §6 requires both
implementations to pass every stage, so the two texts differ there. **Amend §6
to label the locale claim port-only.** That RFC already has the idiom: cell 7 is
labelled port-only because `wasi.proc.run` takes a timeout and the shell does
not. This is the experiment-lead's document and not this proposal's.

## 2. The read direction

### Surface

```lisp
(import wasi.env (capability read "HOME"))                     ;; legal
(import wasi.env (capability read "HOME" :deterministic true)) ;; TYPE ERROR

(wasi.env.get "HOME")     ;; -> Command, delivering RText value | RErr
(wasi.env.get "A=B")      ;; TYPE ERROR: a literal name cannot contain "="
(wasi.env.get "")         ;; TYPE ERROR: a literal name cannot be empty
```

Signature: `string -> Command`. Namespace: `wasi.env`, which is new.
`extractWasiNamespace` in `compiler/src/LLMLL/TypeCheck.hs` takes the first two
dotted segments, so it derives the new namespace with no change.

Effect label: `env.read`, beside the six labels
`compiler/src/LLMLL/ObligationAssembly.hs` already carries.

### Why the call takes one name

**A call names one variable, so the authority it exercises is one variable.**
That is least privilege and it is the whole argument.

An earlier revision argued from `CAP-NULLARY-1` instead. That row records that
`checkWasiCapability` runs only from the application case in
`compiler/src/LLMLL/TypeCheck.hs`, so a nullary builtin never reaches the
capability check. A nullary whole-environment read would therefore ship with no
capability enforcement at all.

**That argument is true and it is the wrong ground to stand on.** Choosing the
type of a builtin so that a traversal reaches a check is a compiler artifact,
not a design. If `CAP-NULLARY-1` closes, an argument built on it disappears.
The least-privilege argument does not depend on `CAP-NULLARY-1` and survives
its fix.

### Why an unset variable answers `RErr` and never the empty string

A variable can be set and empty. `RErr` separates that state from unset.

**The precedent is `JSON-SCALAR-1`.** `(json-get-string x "")` answers the empty
string on a scalar. A port ran its whole corpus with 50 flags silently dropped,
and the program type-checked and verified. A builtin that answers the empty
string for absence repeats that defect.

## 3. Why `:deterministic true` is refused

`LLMLL.md` §10a states that `:deterministic true` captures the **return value**
of every call and appends it to the Event Log.
`compiler/src/LLMLL/CodegenHs.hs` writes that log to
`<module>.event-log.jsonl` in the working directory.

**The environment is the one namespace that carries credentials by convention.**
A capture of an environment read therefore writes a secret to a file in
plaintext.

**The two features are each correct alone.** Capture suits a clock and a PRNG,
because those values carry no confidentiality. An environment read is the first
proposed source whose captured value is secret, so it breaks an assumption the
`:deterministic` flag was built on.

**The exposure is bounded, and stating the bound is the point.** Two
measurements taken 2026-08-14 bound it.

| Question | Answer |
|---|---|
| Does a proof artifact carry the event log? | **No.** `compiler/src/LLMLL/ProofArtifact.hs` carries eleven fields and none is an event log. Its replay reproduces a solver verdict, which is a different mechanism. |
| Is the log committed? | **No.** `.gitignore` ignores `*.event-log.jsonl`. |

So the exposure is a plaintext file in a working directory, and anything that
archives that directory. **A CI runner that uploads a workspace is the live
case**, and this campaign's ports run in CI.

**The refusal is a type error and not a default.** A default that fails open
writes a credential whenever somebody copies a clock import. The diagnostic
names the redaction proposal.

### What the refusal costs

A replayed run reads the live environment. So a module that reads the
environment is replayable in its control flow and is not replayable in that
value.

**This contradicts no claim that `LLMLL.md` makes.** §10a item 8 says replay is
bitwise deterministic for modules that use `:deterministic true` flags **on
clock and PRNG imports**. The claim enumerates two source kinds. An environment
read is a third kind, and the sentence never covered it.

**§10a still needs an amendment, and it is owed whether or not this ships.** An
enumeration that reads as a universal becomes a defect once a third source
exists. The sentence should state its scope: replay is bitwise deterministic
with respect to the captured sources.

## 4. Edge cases and degenerate inputs

**1. Set and empty, against unset.** Export `FOO=` and read it. The read answers
`RText ""`. Read an unset `BAR` and it answers `RErr`. Channel: trust, through
the five-arm `Response` match. Measured 2026-08-14.

**2. Positive witness for the capture refusal.** This module must fail to
type-check:

```lisp
(module leak
  (import wasi.env (capability read "AWS_SECRET_ACCESS_KEY" :deterministic true))
  (def-shell f [] -> Command (wasi.env.get "AWS_SECRET_ACCESS_KEY")))
```

Channel: type. Without the refusal this module compiles, and it writes the
secret to `leak.event-log.jsonl`. **The counter-witness is why the rule is a
refusal.** Delete `:deterministic true` and the module is legal, so the two
cases differ by exactly the flag.

**3. A computed name that cannot name a variable.**
`(wasi.env.get (string-concat k "=v"))` answers `RErr`, and that is
indistinguishable from unset. Channel: spec is silent, and this proposal makes
the silence explicit. The literal side condition cannot reach a computed
argument.

**Measured 2026-08-14, and this is the answer to a professor question.** An
unset name, a name containing `=`, and the empty name all answer the same
thing. A variable that is set and empty stays distinguishable. So the conflation
is on the **name** side and not on the value side.

**4. The granted target is not enforced.** Write `(capability read "HOME")` and
then read `AWS_SECRET_ACCESS_KEY`. The read succeeds. Channel: spec is silent,
and here the silence is a gap. `LLMLL.md` §13 documents this for every
capability. This proposal does not fix it and does not deepen it.

## 5. Verification mapping

| Obligation | Channel | Fragment |
|---|---|---|
| A capability import is present for `wasi.env.*` | type | Not a proof obligation. `checkWasiCapability` decides it during inference. |
| `:deterministic true` is refused on a `wasi.env` import | type | Not a proof obligation. A side condition on the import clause. |
| A literal name is well formed | type | Not a proof obligation. A side condition on a literal argument. |
| The value that a read delivers | trust | **No fragment.** A `Command` result is not a value in the refinement logic, so no predicate constrains it. Every caller takes the `asserted` tier, as with the other `wasi.*` builtins. |

**This proposal adds no QF-LIA obligation and none of its obligations escapes to
Lean.** That is the correct classification and not a deferral. The channel
carries opaque text from outside the program, so no refinement predicate can
speak about it. See `LLMLL.md` §5.3.3 and §5.3.5 for the boundary.

## 6. The set direction, deferred

**Do not add an eighth positional parameter to `wasi.proc.run`.**
`PROC-REDIRECT-1` already records that the trailing same-typed positional
strings are the defect. That row states that `PROC-STDIN-1`'s placement after
the `int` is a coincidence of the current signature, and that a second added
path has no second `int`. An eighth positional makes a filed problem worse.

**Do not add a `wasi.env.set` that changes ambient state.** LLMLL has no mutable
references. A call that changes ambient state for a later `wasi.proc.run` is
order-dependent across steps. That is the aliasing the language excludes.

**Fold the environment into the redirection record that `PROC-REDIRECT-1`
already asks for.** One record carries stdout, stderr, stdin and environment,
and `wasi.proc.run` takes it as one argument. One construct then closes two
filed rows. `PROC-REDIRECT-1` records that no builtin takes a `TCustom`
argument today, so this is first of its kind and is not free.

**The deferred design must express add-to-inherited.** `System.Process` inherits
the parent environment on `Nothing` and **replaces** it on `Just`, and POSIX
`execve` replaces. `scripts/build_smoke.sh` writes `LC_ALL=C` before one
command, which adds one variable to an inherited environment. **A replace-only
record would hand the child one variable and take `PATH` away from it.** So
replace-only is a design error for the call this row exists to serve.

## 7. Affected surface

- `compiler/src/LLMLL/TypeCheck.hs`: one `builtinEnv` entry, which takes the
  count from 14 to 15, plus two side conditions.
- `compiler/src/LLMLL/CodegenHs.hs`: one preamble binding.
- `compiler/src/LLMLL/ObligationAssembly.hs`: a capability mapping and the
  `env.read` effect label.
- `LLMLL.md` §13 and §10a item 8, through documentation-lead after the engineer
  ships. **The §10a amendment is owed whether or not this ships.**
- [`compiler-team-roadmap.md`](../compiler-team-roadmap.md): the `ENV-READ-1`
  and `PROC-ENV-1` rows.
- [`tool-rfc-006-build-smoke.md`](tool-rfc-006-build-smoke.md) §6: the port-only
  label for the locale claim. **Routed to experiment-lead.**

**The feature freeze does not apply.** The roadmap lifted the freeze-era
exclusions, and new builtins now go through the normal design, review and ship
pipeline. **The `language-team` skill file still states a freeze through v0.10
and is therefore incorrect.** That is recorded here so the next turn does not
inherit it.

## 8. Risks

1. **A module that reads the environment is not replayable in that value.**
   Classify: verification ergonomics. Cite: `LLMLL.md` §10a item 8. Cost:
   accepted deliberately. The redaction rule is a separate proposal.
2. **A computed name conflates two failures.** Classify: spec gap, now
   documented. Cost: complicates. It does not block.
3. **The capability target is not enforced.** Classify: soundness of the
   access-control model. Cite: `LLMLL.md` §13. Pre-existing. Cost: matters at
   scale, and it matters more for this namespace than for any other, because
   this namespace holds credentials by convention.
4. **`CAP-NULLARY-1` stays open.** Classify: spec drift. Cost: it no longer
   affects this proposal, because Rev 2's shape does not rest on it.

## 9. Review history

**Round 1, professor, 2026-08-13.** Five findings, all accepted. The review is
in conversation and is not yet a standalone file, so no fold-and-archive is
owed.

| Finding | Disposition |
|---|---|
| `:deterministic true` writes credentials to disk | **Accepted, and strengthened.** Rev 1 proposed the flag. Rev 2 makes it a type error. Scope corrected: no proof artifact carries the event log. |
| Cell 1 of the 006 differential plan fails on Linux | **Accepted.** Amend §6 with a port-only label, on the cell 7 precedent. Routed to experiment-lead. |
| The set direction does not say inherit or replace | **Accepted.** §6 of this proposal now requires add-to-inherited. |
| The construct named `capability` is not a capability | **Accepted** as the answer to Rev 1's open question. The names are ambient authority and least privilege. Pre-existing. |
| The unary shape rested on a compiler artifact | **Accepted.** The justification is replaced with least privilege, and the shape now survives a `CAP-NULLARY-1` fix. |

**Convergence worth naming.** The professor reached the `RErr` shape from the
history of Haskell's `base` library, where `lookupEnv` was added because
`getEnv` throwing was wrong for the common case. This proposal reached the same
shape from `JSON-SCALAR-1`, which is internal. Two reading paths, one answer.

**One scope divergence, named so that nobody redesigns around it.** A
security-typed treatment would propagate an environment read through a lattice
and track the taint. LLMLL never adopted an information-flow lattice. The coarse
`env.read` effect label is a sound over-approximation of the same idea, and it
is the deliberate choice rather than an oversight.

## Findings routed out of this proposal

1. **`TOOL-RFC-006` F7 is reconciled, and the reconciliation is a measurement.**
   F7 records that two counts of the `wasi.*` set disagree, at fourteen and at
   sixteen, and that the RFC did not measure whether the set changed between the
   two dates. **It did not change.** The count is 14 at every release from
   v0.14.90 through v0.14.99. `compiler/src/LLMLL/TypeCheck.hs` holds exactly 16
   distinct `wasi.*` strings, of which 14 are `builtinEnv` entries and two are
   the capability namespaces `wasi.fs` and `wasi.io`. Both counts were correct
   about different things, and the difference is a category error rather than
   history. Route to documentation-lead.

2. **The `language-team` skill file states a feature freeze that the roadmap
   lifted.** Route to the user, because the skill files are not in the six
   target documents.
