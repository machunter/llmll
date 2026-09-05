---
name: fs-stat-1-implementation-plan
title: "FS-STAT-1 + FS-EXISTS-1: implementation plan"
status: "Revision 1, 2026-09-05. Implements docs/design/fs-capability-trio-proposal.md Rev 3 sections 4, 5, 6, 7 and 8. The two rows ship TOGETHER, settled by the user 2026-09-05, because they share one probe. TWO FINDINGS AGAINST REV 3's AFFECTED SURFACE ARE RECORDED IN SECTION 10: the generated project needs `time`, which Rev 3 section 9 does not list; and the `:deterministic` refusal breaks ZERO in-tree programs, measured rather than assumed."
date: 2026-09-05
author: compiler-engineer
consumers: [user, professor, documentation-lead, language-team]
implements: docs/design/fs-capability-trio-proposal.md
style: "ASD-STE100 Simplified Technical English."
---

# FS-STAT-1 + FS-EXISTS-1: implementation plan

## 1. Restatement

Add two `wasi.fs` builtins that share one filesystem probe. Declare a fact for
one of them, which needs a second fact category in the shipped `RESP-FACT-1`
machinery. The fact is an axiom and the trust report must say so.

## 2. Context located

1. `docs/design/fs-capability-trio-proposal.md` Rev 3 §4, §5, §6, §7, §8. The
   settled design. §5 is new at Rev 3 and carries the fact.
2. `docs/compiler-team-roadmap.md` rows `FS-STAT-1`, `FS-EXISTS-1`,
   `TRUST-AXIOM`, `RESP-FACT-1`. The last shipped at v0.17.0.
3. `compiler/src/LLMLL/TypeCheck.hs` `builtinEnv`. Eight `wasi.fs.*` names
   today: read, write, delete, rmdir, copy, list, mkdir, sha256.
4. `compiler/src/LLMLL/ObligationAssembly.hs` `primEffect`. The `wasi.`
   fallthrough trap is recorded three times in that function already.
5. `compiler/src/LLMLL/CodegenHs.hs` `runtimePreamble`. `wasi_clock_monotonic`
   is the `RCode` precedent; `wasi_fs_read` is the `RText` precedent.
6. `compiler/src/LLMLL/RespFact.hs`. `respFactTable`, `FactCategory`, the
   premise-site builder and the disclosure builder.
7. `docs/compiler-team-roadmap.md:297`. **The v0.8.1a to v0.10 feature freeze was
   LIFTED at v0.11.** A new builtin is in scope through the normal pipeline.

## 3. Plan summary

Add `wasi.fs.stat` and `wasi.fs.exists` as `string -> Command`. Both resolve one
`getModificationTime` probe classified through `System.IO.Error`. `stat`
publishes `RCode age-seconds`, and publishes `RErr` when the computed age is
negative. `exists` publishes `RText` carrying one of four kind strings.

Then declare `("wasi.fs.stat", "RCode") -> {v : int | v >= 0}` in
`respFactTable`. That needs a second `FactCategory` constructor, because the age
is not an argument the program passes and no premise exists to prove. The
category is an axiom about generated code. Two one-constructor assumptions in the
shipped code must be relaxed, and the disclosure must name the category so the
trust report does not present an assumption as a proof.

## 4. Affected surface, in patch order

**Stage A, the builtins. No fact yet.**

1. `compiler/src/LLMLL/TypeCheck.hs`, `builtinEnv`. Two entries,
   `TFn [TString] (TCustom "Command")`, beside the existing `wasi.fs.*` block.
2. `compiler/src/LLMLL/ObligationAssembly.hs`, `primEffect`.
   `wasi.fs.exists` joins the existing `wasi.fs.read || wasi.fs.list` clause
   (`EFsRead`). `wasi.fs.stat` takes its own clause,
   `Just (Caps (Set.fromList [EFsRead, ENonDet]))`, on the `wasi.fs.sha256` and
   `wasi.fs.copy` precedent. **Both must sit ABOVE the `wasi.` fallthrough.**
   Pin the negative (`NOT Just Unbounded`), not the positive alone, as the
   existing tests for `wasi.proc.args` and `wasi.env.get` do.
3. `compiler/src/LLMLL/CodegenHs.hs`, `runtimePreamble`. One shared probe plus
   two bodies. `stat` computes `diffUTCTime` between `getCurrentTime` and
   `getModificationTime`, truncates to seconds, and calls `ioError` when the
   result is negative so `llmll_publish_io` answers `RErr`. `exists` classifies
   the probe, then refines the kind. **Test `pathIsSymbolicLink` BEFORE
   `doesDirectoryExist`**, because the latter follows a symlink to a directory.
4. `compiler/src/LLMLL/CodegenHs.hs`, generated-project dependency list. **Add
   `time`.** See §10 finding F-1.
5. `compiler/src/LLMLL/TypeCheck.hs`, the import-capability check that refuses
   `:deterministic true`. Extend the `wasi.env` condition to `wasi.fs`. The
   refusal is on the IMPORT, not the call, matching the existing comment.

**Stage B, the fact. Stage A must be green first.**

6. `compiler/src/LLMLL/RespFact.hs`, `FactCategory`. Add
   `FactCodegen` beside `FactProgram Int`. The type stops being a newtype.
7. `compiler/src/LLMLL/RespFact.hs`, `respFactTable`. One entry:
   `(("wasi.fs.stat","RCode"), RespFact FactCodegen "v" (v >= 0))`.
8. `compiler/src/LLMLL/RespFact.hs`, the premise-site builder. It binds
   `let FactProgram i = rfCategory f` as an **irrefutable pattern**. A second
   constructor makes that partial. Convert it to a `case`, where `FactCodegen`
   emits **no premise site and no error**: an axiom has no argument to check.
9. `compiler/src/LLMLL/RespFact.hs`, the disclosure builder. `afCategory` is the
   string literal `"program-determined"`. Derive it from `rfCategory`.
   `afPremise` must render `codegen:<builtin>` for the axiom case, because
   `T.intercalate` over the empty premise list yields `""`, and an empty field
   reads as a missing value rather than as an absent obligation.
10. `compiler/src/LLMLL/TrustReport.hs`, the `≈ assumes` text line. State that a
    `codegen-determined` fact is ASSUMED and rides `codegen_semantics_version`.

**Not touched, and each is a measured claim.** `deliveredParams` and
`exportCondition` in `RespFact.hs` take no `RespFact` and never read
`rfCategory`, so the delivery rule and the export condition need no change.
`VerifiedCache.checkerSoundnessVersion` stays `"2"`; see §5.

`docs/llmll-ast.schema.json` needs **no** version change. No node shape moves; a
builtin name is not a schema term.

## 5. Verification impact

- **New obligations: ZERO.** A `FactCodegen` fact emits no `call-pre` constraint,
  which is exactly what makes it an axiom. `FactProgram` emits one per issuing
  site; this category emits none.
- **Solver-time delta: none measurable.** No constraint is added. The fact enters
  `refEnv` as an antecedent, which liquid-fixpoint already handles for the
  `wasi.http.response` entry.
- **Fragment: QF-LIA.** `v >= 0` is linear over one int binder. Nothing escapes
  to nonlinear arithmetic and nothing escapes to Lean.
- **Strict-verified-core: no function newly falls back.** The fact only ever
  strengthens an antecedent.
- **Trust model: the trusted set GROWS BY ONE AXIOM.** This is the real cost and
  it is not a solver cost. A `codegen-determined` fact is valid only because
  generated code cannot publish a violating value. It rides
  `codegen_semantics_version`, as `bytes-set` and `(bytes-zero)` do.
- **`checker_soundness_version` does NOT change.** It moved to `"2"` at v0.17.0
  because a verdict began to depend on the fact table. Adding an entry changes
  that table, so the question is fair. **The affected population is empty**: no
  tracked `.verified.json` can name a builtin that does not exist. This is the
  argument FACT-AG-LEN Stage 3 used, which is to identify the population rather
  than to assume it is non-empty.

## 6. Performance budget

- **GHC fan-out: five modules.** `TypeCheck.hs`, `ObligationAssembly.hs`,
  `CodegenHs.hs`, `RespFact.hs`, `TrustReport.hs`. `TypeCheck.hs` and
  `RespFact.hs` are wide dependencies, so expect a near-full library rebuild,
  about the same as the `RESP-FACT-1` change measured.
- **Generated-project closure: 33 to 34 packages.** `time` is a GHC boot package
  and is already a compiler dependency, so the LTS snapshot is cached in CI. That
  is the `directory` precedent, stated in `CodegenHs.hs` at the dependency list.
- **`llmll check` and `llmll verify`: no measurable delta.** Two `builtinEnv`
  entries and one table entry are constant-factor lookups.
- **`stack test` runtime: expect under one second added** for roughly 20 new
  examples, against 13.4 seconds measured for 1831 examples at HEAD.
- **ProofCache and VerifiedCache hit rates: unchanged.** No existing program can
  call either name.

## 7. Contract plan

**No new LLMLL function lands in the provable fragment.** This change adds two
builtins and compiler internals. The contracts that matter belong to the
positive-witness fixture, and they are stated here before the fixture exists.

A new fixture, `fs-stat-fact.llmll`, under `compiler/test/fixtures/resp-fact/`:

```lisp
(def-shell age-step [p: Ctl x: Response] -> int
  (pre (= p Probed))
  (post (>= result 0))
  (match x ((RCode age) age) (_ 0)))
```

**The refuting body**, which a reader would plausibly have written and which the
contract must reject:

```lisp
  (match x ((RCode age) (- age 1)) (_ 0))
```

Under the fact, `age >= 0`, so `age - 1 >= -1` and the post `(>= result 0)` is
**refuted**. Without the fact `age` is unconstrained and the original body is
refuted too, which is the discriminating property §8 turns into the acceptance
test.

**Module placement.** `age-step` is a `def-shell`, so the sibling-call
restriction that forces one `def` per module does not apply. The fixture stays
one file.

## 8. Test plan

Baseline, measured at HEAD: **1831 hspec examples, 0 failures.** Target: about
**1851**.

**The discriminating cell, which is the acceptance criterion.**

- `fs-stat-fact.llmll` VERIFIES with the `respFactTable` row present.
- The SAME fixture REFUTES with the row deleted.

A fixture that verifies under both tables proves nothing about the fact. Pin both
directions. The second cell needs a table the test can vary, so expose the table
through the existing test seam rather than editing source between runs.

**Runtime cells, from Rev 3 §7.** These need a real filesystem, so they belong
with the `scripts/tests/` Python suite or a `build_smoke` stage, NOT with hspec,
which does not build and run generated programs. That limit is recorded at
`FS-RMDIR-1`'s `FR-5`.

1. **Future mtime.** `touch -d tomorrow`, then `wasi.fs.stat`. Expect `RErr`, not
   `RCode 0`. This is the clamp withdrawal's own witness.
2. **Mode-0000 parent.** `wasi.fs.exists` on a present file. Expect `RErr`, not
   `RText "absent"`. This is why `doesFileExist` was rejected.
3. **Mode-0111 parent.** `wasi.fs.exists` on a known name. Expect `RText "file"`,
   while `wasi.fs.list` on the same parent answers `RErr`. This is §6's
   refutation and it is a DISCLOSURE case, not a defect to fix.
4. **Symlink to a directory.** Expect `RText "symlink"`, never `RText "dir"`.
   This cell decides the probe order and fails if the order is wrong.

**Static cells, hspec.**

5. `primEffect "wasi.fs.stat" == Just (Caps {EFsRead, ENonDet})`, and the
   NEGATIVE `/= Just Unbounded`, which is the fallthrough trap.
6. `primEffect "wasi.fs.exists" == Just (Caps {EFsRead})`, plus the same
   negative.
7. A `wasi.fs` import with `:deterministic true` is a type error.
8. `respFactTable` holds exactly two entries, pinned by content.
9. The disclosure row for `wasi.fs.stat` reads category `codegen-determined` and
   premise `codegen:wasi.fs.stat`, and is NOT empty.
10. `W-RESP-FACT-NONE` fires for a tag bound to `wasi.fs.exists`, which declares
    no fact.

## 9. Rollback

Single revert is plausible. The change is additive: two names, one table entry,
one constructor. No schema version moves and no `.verified.json` migration is
needed, because no cached sidecar can name either builtin.

The one non-additive edit is the `:deterministic` refusal, which rejects programs
that `check` today. **Measured: the in-tree population is ZERO** (§10, F-2), so
the unwind cost is the revert alone.

## 10. Risks and findings

**F-1. Rev 3 §9's affected surface omits `time`, and the change needs it.**
Classify: build. `getModificationTime` returns `UTCTime`, and computing an age
needs `getCurrentTime` and `diffUTCTime`, both from `time`. The generated
project's dependency list in `CodegenHs.hs` carries base, containers, QuickCheck,
async, regex-tdfa, directory, process, cryptohash-sha256 and bytestring, plus a
shared `unix`. It does NOT carry `time`. **Bite: complicates, does not block.**
`time >= 1.12` is already a compiler dependency and is a GHC boot package, so the
LTS snapshot is cached and the resolver does not move. That is the argument
`CodegenHs.hs` already records for `directory`. The `unix` alternative is refused
because Rev 2 §6 chose `base` classification to avoid a POSIX-only restriction.

**F-2. The `:deterministic true` refusal on `wasi.fs` breaks no in-tree program.**
Classify: scope. **Measured, and the first measurement was a false positive.** A
file-level search finds two `.llmll` files that carry the string
`:deterministic true` and also import `wasi.fs`. Reading them shows **both
occurrences are inside comments** that explain the flag would be a type error on
`wasi.env`. Every real import in both files carries `:deterministic false`. Bite:
none. Recorded because the refusal is on the import rather than the call, so it
would have rejected any `wasi.fs` user whether or not it called `stat`.

**R-3. The axiom is undisclosed if step 10 is dropped.** Classify: soundness.
Cite: `TRUST-AXIOM` roadmap row, Rev 3 §5 and §10 risk 1. Bite: **complicates,
and it is the one step that must not be deferred.** Shipping the fact without the
category and premise text would present an assumption as a proof, inside the row
that first disclosed the assumption class. The disclosure is the price of the
axiom.

**R-4. `stat` and `exists` disagree under a race.** Classify: scope. The two
calls are separate commands and the filesystem can move between them. Bite: only
matters at scale. Rev 2 already withdrew a probe-then-act interlock as a
check-then-act race, so the design does not claim atomicity.

**R-5. `RCode` now carries a fourth unit.** Classify: DX. Exit statuses,
monotonic nanoseconds, and now ages in seconds, with the unit nowhere in the
type. Bite: only matters at scale. This is a scope boundary LLMLL has chosen; the
in-scope move is to name the unit in the declared contract.
