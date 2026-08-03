---
name: driver-ll-open-work
title: "DRIVER-LL open work: what v0.14.80 owes, and the two findings that must not close with it"
status: "ACTIVE ROUTING RECORD, opened 2026-08-03. Phases 0 and 1 of the DRIVER-LL campaign are implemented and committed but NOT released: four commits sit ahead of origin/main with the release ceremony unperformed. This file exists so a session with no prior context can finish the release and route the open findings without re-measuring anything. Delete it when every row below is either shipped or has a roadmap row of its own."
date: 2026-08-03
author: compiler-engineer
consumers: [documentation-lead, compiler-engineer, language-team, user]
---

# DRIVER-LL open work

Read this before touching the campaign. Every measurement below was taken; none needs repeating.

---

## 0. Exact state

```
8b723a6  docs(design): settle the Response arm set; record Phase 1 as measured
1036245  feat(cap-proc): the fifth Response arm ships with its producer, wasi.fs.list
bc78057  feat(effect-resp): one response per performed command; :step gains its arity check   <- main
8dff514  feat(discard-1): the dropped command must be declared; retire :read; schema 0.10.0
2dc3548  docs(release): v0.14.79                                                    <- origin/main
```

Branch `cap-proc/fs-list-arm` holds the top two and fast-forwards onto `main` cleanly.
`main` is two commits ahead of `origin/main`. **Nothing is pushed and nothing is tagged.**

Tests **1544, 0 failures**. Schema **0.10.0**, `$id` at `/schemas/v0.10/`. Version banner still
says **v0.14.79** everywhere, which is why `version_gate.sh` is currently green: the pins agree with
each other, they just do not yet describe what is in the tree.

All gates green at `8b723a6`: `stack test`, `version_gate.sh`, `doc_archive_gate.sh`,
`doc_claims_gate.sh` (15 claims), `build_smoke.sh`, `refute-crux-gate.sh` (61),
`doc_path_lint.py`, `pytest scripts/tests/` (107), `spec_roundtrip.py`.
`check-examples.sh` is 165 passed / 1 failed, and that one failure is pre-existing (row R-3 below).

---

## 1. IMMEDIATE: the v0.14.80 release ceremony

`documentation-lead`'s slot. Merge `cap-proc/fs-list-arm` into `main` first (fast-forward), then one
`docs(release):` commit, then `version_gate.sh`, then push `main` and the tag together. The project
rule is that the ceremony is owed **at merge time**; a bare merge leaves breaking changes on `main`
labelled with the previous version.

What the release carries, in commit order:

- **`8dff514` DISCARD-1.** A non-final `do`-step whose command is dropped must carry `:discard`; the
  marker on a final step is rejected; `:read` retired from `def-main`. **JSON-AST schema 0.9.0 to
  0.10.0**, `$id` moved in the same commit.
- **`bc78057` EFFECT-RESP RC-1..RC-4.** Console `:step` gains a third parameter `response: Response`
  (arms `RNone` / `RText string` / `RCode int` / `RErr string`). One response per performed command;
  `seq-commands` yields the right operand's; `:init` supplies the first; `done?` is evaluated on the
  state a step produced, so **the terminating step's command is not performed**. `wasi.fs.read`
  returns contents as `RText` and IO failures as `RErr` instead of raising. Twelve programs migrated.
  New `def-main-step-arity` check, which is the migration's only diagnostic. Trust report gains
  `harness_assumptions`, no `trust_report_version` bump.
- **`1036245` CAP-PROC first operation.** Fifth arm `RList list[string]` plus its sole producer
  `wasi.fs.list`. Shares the `EFsRead` label rather than widening the closed six-label catalog.
- **`8b723a6`** design records only.

Doc surface owed: `LLMLL.md` §9.6 (replace the "planned to tighten to a warn-or-error" sentence with
the shipped rule), a new §9.x for the response channel **including the RC-4 terminating-command
rule**, §13.9 gains one sentence giving `seq-commands` discard-left semantics and one for
`wasi.fs.list`. `docs/design/INDEX.md` status labels for both design docs. Roadmap: DO-ACCUM-1 and
EFFECT-RESP shipped, CAP-PROC amended to six remaining operations, BUILD-GATE-1 amended (witness (b),
the `:step` arity change, is now covered by the widened `smoke.llmll`).

**Spec drift to fix in the same pass, not silently:** the WASI-RT roadmap row still describes
`wasi.fs.read`'s body as "performs and discards", which `bc78057` replaced.

---

## 2. BLOCKER-1 — `CAP-1-REAL`: the capability system does not do what four spec sentences say

**Do not let the release close over this.** It is not a documentation nit. The campaign's Phase 5
conformance claim rests on language this finding invalidates.

### What was measured

`checkWasiCapability` (`compiler/src/LLMLL/TypeCheck.hs:1528-1537`) is:

```haskell
matchesWasiImport ns (SImport imp) = importPath imp == ns
```

It consults `importPath` and nothing else. `importCapability` is a `Maybe Capability`
(`Syntax.hs:848-852`) and is never read. Consequences, all confirmed at HEAD:

1. A bare `(import wasi.fs)` **with no capability clause at all** authorizes every `wasi.fs.*` call.
2. The capability **verb** is decorative. `(capability read "/tmp")` already authorizes
   `wasi.fs.write` and `wasi.fs.delete` today.
3. The capability **target path** is decorative. `capKind` and `capTarget` have exactly one consumer
   outside `Syntax.hs`, and it is JSON re-emission (`AstEmit.hs:438-454`).
4. `pCapKind` (`Parser.hs:499-511`) ends in a `CapCustom <$> pIdent` fallthrough, so any invented
   verb parses and is ignored.

### What the spec claims

| Cite | Claim | Reality |
|---|---|---|
| `LLMLL.md:25` | access granted "via a `capability` import" | the import alone suffices |
| `LLMLL.md:1114` | checker "verifies that a matching `SImport` with a `Capability` is present", and names "the principle of least authority" | verifies namespace membership only; POLA is not earned |
| `LLMLL.md:1118-1119` | `(capability read-write "/data")`, `(capability post "https://…")` | the path and URL are unenforced |
| `LLMLL.md:1487` | runtime "verify permissions … raises a `CapabilityError` and halts" | `CodegenHs` contains zero capability references |

`tools/llmll-driver/crux-shell-undeclared-authority.llmll` asserts driver-spec §15.2 ("effects MUST
be reached only through a DECLARED capability") and discriminates **namespace absence only**. It
passes for a coarser reason than its comment claims.

### Why it is not fixed, and what the fix is not

`1036245` deliberately did **not** enforce a verb for `wasi.fs.list`. Enforcing one name while six
existing names remain unchecked is worse than uniform non-enforcement, because it invites a reader
to assume the others are checked too.

The fix is **not** "make `matchesWasiImport` read `capKind`". That still yields ACLs keyed on module
identity. What LLMLL has today is namespace-scoped module ACLs; whether it wants capabilities in the
object-capability sense is a design decision nobody has taken. Frame the row that way.

### Routing

Open **`CAP-1-REAL`**, `[CT][SPEC]`, and merge **WASI-RT residue (ii)** into it (that residue reads
"the four definitions land capability-blind, CAP-1 being enforced at typecheck only", which is the
same finding seen from one operation). Language-team owns the design question; doc-lead owns the four
`LLMLL.md` corrections; the corrections should not wait on the design.

Two open questions already put to language-team and unanswered:

1. Is §15.2's claim intended to survive as a namespace-membership property, in which case its wording
   must change, or does Phase 5's conformance claim depend on enforcement that does not exist?
2. Rev 5's rule 4 forbids capability-named arms and rule 1 admits by shape, which together force
   `RCode` to carry HTTP statuses, exit codes, and clock readings. Accept the overloading explicitly,
   or justify a provenance-tagged alternative.

---

## 3. BLOCKER-2 — a console `def-main` with no `:init` cannot build

**Do not let the release close over this either.** It blocks the build-acceptance clause that every
campaign phase from 1 through 4 carries.

`emitMainBody ModeConsole` emits `let state0 = ()` when `:init` is absent
(`compiler/src/LLMLL/CodegenHs.hs`, the `initBlock` `Nothing` branch), **regardless of the step
function's declared state type**. Unchanged from before `bc78057`; found while constructing the
Phase 1 witness, not introduced by it.

In-tree victims: `examples/replay-demo/replay-demo.llmll` and
`examples/proof_required_test/proof_required_test.llmll`, both with `string` state and no `:init`.
Both typecheck clean and fail at GHC. This is a **fourth** instance of the check-passes /
build-fails seam that WASI-RT, the `:step` arity change, and IFACE-CONFORM already occupy.

Candidate fixes, unranked because the choice is a design call: infer `state0` from the step's first
parameter type; require `:init` for any non-unit state; or emit a typed `undefined` with a diagnostic.
The first is the only one that keeps existing programs working.

Phase 3's acceptance requires built-and-run artifacts, so this surfaces there if it is not filed now.

---

## 4. Named residues, lower severity

| Tag | Item | Evidence |
|---|---|---|
| **R-1** | `check-examples.sh` and `refute-crux-gate.sh` run in **no CI job**. `refute-crux-gate.sh` is in `Makefile:26` only; `check-examples.sh` appears nowhere under `.github/`. Fifth and sixth instances of the unobserved-check pattern BUILD-GATE-1 was created for. | measured 2026-08-02 |
| **R-2** | The four game examples lose their final render under RC-4. Measured: `hangman_sexp` emits **twelve fewer lines** on identical stdin, losing the losing turn's board while `:on-done` still fires. **Deferred by user adjudication**; examples are revisitable. The repair, when taken, is to render the final board from `:on-done` rather than from the terminating step, which is the pattern RC-4 mandates. | measured against a baseline binary |
| **R-3** | `examples/totp_rfc6238/totp_filled.ast.json` fails `check-examples.sh` on a `bytes[20]` WILD-ASSUME error from the FACT-AG-LEN line. Pre-existing, unrelated to this campaign, and invisible because of R-1. | 165 passed / 1 failed |
| **R-4** | The RC-1 bijection is exercised by a **run, not a committed fixture**. The program: one 11-byte read per turn, accumulator reaching 33 over three performed reads while the terminating step contributes nothing. Wants a home in `compiler/test/` or `examples/`. | Phase 1 acceptance, partially met |
| **R-5** | **CLOSED at the v0.14.80 release pass.** `scripts/doc_path_lint.py` carried a DELETE-THIS-ROW `ALLOW` entry for a doc-claims fixture never created under the name the plan proposed; the sibling that exists is `do-notation-discard-marker.llmll`, and the final-step rule is tested by the `do-discard-final` case in `Spec.hs` rather than by a doc-claim. The plan's two citations now name the shipped fixture, the `ALLOW` row is dropped, and this row no longer cites the dead path. **It was not merely cosmetic:** `test_doc_path_lint.py::test_clean_on_live_repo` gates the lint in `pytest`, which `.github/workflows/version-gate.yml:86` runs, so this row's own text left `main` red in CI from `b85f001` until the release pass. The lint's "does not fail the build" message is wrong about itself. | closed |
| **R-6** | Two committed sidecars (`examples/banking_ledger/banking.llmll.verified.json`, `examples/erc20_token/erc20_filled.ast.json.verified.json`) gain a `checker_soundness_version` field on any re-verify. Hashes unchanged. Any corpus-wide verify produces a two-file diff that is noise. | revert it when it appears |
| **R-7** | Rule 3 of the arm-set admissibility rule (file-indirection) systematically enlarges **REPLAY-INJECT**: every payload the rule keeps out of the response channel is a payload the event log does not capture. This is the gap between value determinism and output determinism. Language-team owes the sentence in Rev 5's own rule text. | professor review, 2026-08-02 |
| **R-8** | The arm set is now strictly **finer** than the effect catalog: `Response` distinguishes `RText` from `RList` while `Sigma_eff` maps both producers to `fs.read`. Not a soundness defect (`LLMLL.md:1860` scopes `effect_summary` as informational and orthogonal to trust), but an asymmetry that should be recorded rather than rediscovered. | professor review, 2026-08-02 |
| **R-9** | The checkout brief does not describe `Response`'s arms. An agent filling a step hole is told the parameter's type name and not its constructors, and the brief is the only channel it gets. Will matter at Phase 3. | named, unscheduled |

---

## 5. Measurements already taken. Do not repeat these.

- **Corpus `.fq` byte-identity: 151 of 151 identical** against both `2dc3548` (pre-EFFECT-RESP) and
  `bc78057`. Sigma_auto is unchanged across the entire EFFECT-RESP + arm-set line, including the
  twelve participating programs, whose step functions already fall back on `Command`. The Phase 1
  STOP is cleared.
- **Migration surface is exactly twelve programs**, six `.llmll` and six `.ast.json`. Zero `cli` or
  `http` entry points in-tree. A `:mode console` grep finds three of the six sources; use
  `grep -rln --include='*.llmll' 'def-main'` **and** `grep -rln --include='*.json' '"def-main"'`
  (excluding `docs/llmll-ast.schema.json`).
- **`RList` witnesses, built and run:** two files yields `RList n=2`; an empty directory yields
  `RList n=0` taking the `RList` arm and **not** `RNone`; a missing directory yields `RErr` with
  exit 0.
- **The `:step` arity check fires** on an unmigrated two-parameter step, on one parameter, and on a
  wrong third type. Before `bc78057` the same three-parameter program returned `OK`.
- **A pure `def` matching on `Response` falls back** from body-faithful VC, and so does an
  identically-shaped user-declared sum used as a control. Matching on a payload-carrying sum is a
  pre-existing Sigma_auto boundary; `Response` sits exactly where a user type sits.
- **Six of Phase 2's seven operations need no new arm**, because the driver routes bulk payloads
  through the filesystem (`scripts/rfc_to_implementation.py:211-215`, `:419-420`). `wasi.proc.spawn`
  and `wasi.proc.await` collapse into a synchronous `wasi.proc.run`; there is no `Popen` in the
  driver.

---

## 6. Gotchas that cost time. Each was paid for at least once.

1. **Stale binary.** Use `LL="$(cd compiler && stack path --local-install-root)/bin/llmll"` by
   absolute path and check `"$LL" version` first. An unrelated `llmll 0.14.71` at `~/.local/bin`
   wins on `PATH` whenever a `cd` fails and produces believable wrong results. This bit twice.
2. **Shell working directory persists between tool calls.** A `cd` in one command changes where the
   next one runs. Use absolute paths.
3. **Version constants have two halves.** `ParserJSON` has `expectedSchemaVersion` (what the emitter
   stamps) and `acceptedSchemaVersions` (what the reader accepts). Moving one without the other
   compiles fine and makes the compiler refuse to read its own output.
4. **A schema bump requires moving `$id`** to the matching `/schemas/vX.Y/` in the same commit, or
   `version_gate.sh` check C4 goes red.
5. **Adding a record field breaks positional constructions elsewhere.** `TrustReport` had exactly one
   in `Spec.hs` and it cost a compile cycle.
6. **Hand-written JSON instances.** `AstEmit` and `ParserJSON` have no derived instances; a field
   added to one and not the other compiles and fails at round-trip.
7. **Editing JSON corpus files with a naive `json.dump` reformats the whole document.** Splice by
   bracket-matching on the raw text instead; the migration diff should be seven lines per file.
8. **Positive-witness discipline.** Any new guard, gate, or check must be demonstrated **firing** on
   a concrete constructed input. A gate green on both sides of its patch has not been shown to
   observe anything. BUILD-GATE-1 was held to this (red against a deliberately broken emitter, green
   on restore) and so was the `:step` arity check.
