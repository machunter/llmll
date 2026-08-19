---
name: driver-ll-open-work
title: "DRIVER-LL open work: what v0.14.80 owes, and the two findings that must not close with it"
status: "ACTIVE ROUTING RECORD, opened 2026-08-03. Its body describes the v0.14.80 and v0.14.81 line and is correct for that line; the stamp said `updated 2026-08-03` while the tree moved to v0.16.1, so it was REMEASURED on 2026-08-18. All three blockers it filed still have live roadmap rows: HTTP-GET-1 (stage A STOPPED on it), CAP-1-REAL and CONSOLE-INIT-1. R-11 was promoted to HTTP-GET-1 and R-13 closed at v0.14.81, both unchanged. Nothing in this file was discharged since it was written; the routing is what is live, not the release narrative around it."
date: 2026-08-18
author: compiler-engineer
consumers: [documentation-lead, compiler-engineer, language-team, user]
---

# DRIVER-LL open work

Read this before touching the campaign. Every measurement below was taken; none needs repeating.

---

## 0. Exact state

**Updated 2026-08-03, after the v0.14.80 release and the CAP-PROC Phase 2 work.**

```
64e60f6  docs: the four CAP-PROC operations, and two claims the shipped design refuted
a46d361  feat(cap-proc): four Phase 2 operations, and a build gate that runs them
ef2bd49  docs(release): v0.14.80 — the response channel, DISCARD-1, and wasi.fs.list  <- main, origin/main, tagged
```

**v0.14.80 SHIPPED** (`ef2bd49`, pushed and tagged); §1's former ceremony content is discharged.
Branch **`cap-proc/four-operations`** holds the top two commits. **Nothing is pushed; there is no
version bump.**

Tests **1565, 0 failures** (was 1544 at `ef2bd49`). Schema **0.10.0** unchanged, no JSON-AST delta.
Version banner reads **v0.14.80** across all five pins, which is why `version_gate.sh` is green: the
pins agree with each other and do not yet describe what is on the branch.

All gates green at `64e60f6`: `stack test` (1565), `version_gate.sh`, `doc_claims_gate.sh` (15),
`build_smoke.sh` (**now with an execution stage**, see §5), `pytest scripts/tests/` (107).
`check-examples.sh` is 165 passed / 1 failed, and that failure is pre-existing (row R-3 below).

---

## 1. IMMEDIATE: the v0.14.81 release ceremony

The v0.14.80 ceremony is **done**. What is owed now is v0.14.81 for the two branch commits.

The bump is the **engineer's** slot (`compiler/package.yaml`, `compiler/llmll.cabal`); the ceremony is
`documentation-lead`'s. Order: bump the two pins, then merge `cap-proc/four-operations` into `main`,
then one `docs(release):` commit carrying the CHANGELOG entry and the README / `LLMLL.md` banner,
then `version_gate.sh`, then push `main` and the tag together.

The CHANGELOG entry is **drafted and held** rather than written, because a section cannot be authored
against pins that name an already-released version. Its content: CAP-PROC reaches 5 of 6;
`wasi.http.get` dropped with both measurements; the `random` → `nondet` label rename, which is
**breaking for any consumer keyed on the old string**; `wasi.proc.run` reporting `unbounded`;
BUILD-GATE-1's execution stage and the handle-leak defect it caught. Tests 1565 Haskell, 107 Python.

The roadmap **CAP-PROC** row still reads "OPEN, 1 of 6 shipped" and cannot be flipped until a version
exists to name, since the row's established form cites one (`wasi.fs.list` shipped v0.14.80, commit
`1036245`). CAP-PROC now closes at **five** operations, not six; see R-11.

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

Two open questions, **both DISCHARGED by language-team 2026-08-03**. Answers below; do not re-open.

**1. §15.2 — ANSWERED BY READING IT.** `experiments/rfc-swarm/targets/driver-spec.txt:517-528` was
not opened by anyone in the thread that filed this question. It has two paragraphs and they have
different fates.

¶1 requires that effectful operations "be reached only through a declared capability or a named
interface declared in the program itself." That is a property of the **declaration surface**, it is
satisfied today by namespace membership (`checkWasiCapability`), and **its wording does not need to
change**. It never consults the effect summary, so the "⊤ satisfies §15.2's letter while making the
report vacuous" framing at `driver-in-llmll-campaign.md:67` and in the CAP-PROC roadmap row is an
**over-read**: ⊤ is neither satisfying nor violating ¶1, because ¶1 does not ask this catalog
anything.

¶2 requires that an implementation "enforce the contracts of this tier at runtime where it cannot
prove them." LLMLL enforces nothing at runtime. **Yes, a Phase 5 conformance claim as currently
imagined would depend on enforcement that does not exist.** The correct Phase 5 move is to claim ¶1
and disclose ¶2. The gap is `CAP-1-REAL`'s, not CAP-PROC's, and no choice of effect-label granularity
touches it.

**2. `RCode` overloading — ACCEPTED EXPLICITLY.** Rev 5's rule 1 admits arms by payload shape and
rule 4 forbids capability-named arms; one integer arm with several producers is the intended
consequence of a rule chosen to keep the arm set small, not an accident. A provenance-tagged
`RCode` is a capability-named arm wearing a payload disguise and fails rule 4.

`TrustReport.hs:313-325` already discloses the overloading in `harness_assumptions`, naming all three
producers (HTTP status, process exit code, clock reading) and naming **CMD-A** as the closure. A
proposed `RCode` → `RInt` rename was raised twice and is now **CLOSED WITHOUT ACTION**: it is
cosmetic relative to CMD-A, it makes no mispairing ill-typed, and if CMD-A ever lands then `Command`
is parameterised by its result and `RCode` ceases to exist, so the name can never become
load-bearing.

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
| **R-10 `CRYPTO-2`** | **`asserted-with-stub-backend` does not exist.** `LLMLL.md §13.11` describes it as a trust-report channel; `grep -rn 'stub-backend' compiler/` returns **zero hits** and `TrustReport.hs:1630` emits `"asserted"`. `critique-2026-05-23-triage.md:122` marks CRYPTO-1 **Shipped**, crediting `7ccd925`, which `git show --stat` shows is a **docs-only** commit. Two archived proposals then built on it as a real admissibility criterion (`core-shell-inversion-proposal.md:162`, `refinement-metatheory-of-record-proposal.md:143`). Retract the channel; the `asserted` cap on stub-reaching functions is unchanged and sufficient. The principled version is **not a tier** (a tier must be monotone under composition; "reaches a known-false axiom" says the assumption set is inconsistent) but an axiom-dependency report over the closure, i.e. Lean's `#print axioms` / Coq's `Print Assumptions`. Named `assumed_axioms`, **not scheduled**; it would sit *beside* the tier, not subsume it, so it is an additive report field rather than a trust-model change, and `computeEffectSummary` (`ObligationAssembly.hs:467-470`) already has the fixpoint it would reuse. **EXECUTED 2026-08-19 at `b0d03e6`**: the `LLMLL.md` §13.11 retraction landed, both archived proposals carry a dated note, and the roadmap row is SHIPPED. The sweep found twelve citations across seven files where this row named two. `assumed_axioms` stays unscheduled, and `R-12` `REPORT-GATE-1` stays unrouted. | measured 2026-08-03; executed 2026-08-19 |
| **R-11 `HTTP-GET-1`** | **`wasi.http.get` is dropped from CAP-PROC and refiled.** Two independent grounds, either sufficient. (i) Rev 5's arm table maps it to `RText` body, which **cannot reproduce `stage_A_intake`**: the driver does `dest.write_bytes(r.read())` then hashes the FILE (`rfc_to_implementation.py:419-426`), and an `RText` round trip is not byte-faithful. (ii) `http-client` + `http-client-tls` moves a generated project's dependency closure from **33 to 79 packages** (`stack ls dependencies`, lts-22.43: crypton, tls, four crypton-x509-\*, three asn1-\*, socks, pem, hourglass, cereal…), none of which are compiler deps, so CI's snapshot cache misses. Settled signature for whenever it lands: `wasi.http.get : string -> string -> Command` (url, dest), `RNone` on 2xx and `RErr` carrying the status otherwise, **plus an atomicity clause: `dest` is either absent or contains the complete 2xx body, never a prefix.** Without that clause a truncated transfer feeds `wasi.fs.sha256` a valid-looking pin over a partial download, and that pin is the campaign's provenance root. Interim: a granted `curl` through `wasi.proc.run`, zero deps, byte-faithful, and it moves TLS trust into an ambient binary invoked with an unchecked argv. **CAP-PROC closes at five operations, not six.** | measured 2026-08-03 |
| **R-12 `REPORT-GATE-1`** | **No gate covers report-shape doc claims.** `doc_claims_gate.sh` (DRIFT-CT-2) runs `.llmll` fixtures through `llmll check` and compares an `expect=` verdict (`:4-22`, `:28`, `:78-79`), so it guards claims about *what the compiler rejects*. A claim that the trust report emits a given field has no expressible fixture in that harness. This is the gap R-10 propagated through: a documented mechanism with no implementation survived a Shipped status flip and reached two admissibility criteria. Seventh instance of the unobserved-check pattern BUILD-GATE-1 was created for, and the first on the *documentation* side. | named, unscheduled |
| **R-14 `PROC-ENV-1`** | **`wasi.proc.run` has no env parameter.** Filed by DRIVER-LL Phase 4 (`driver-ll-phase4-proposal.md` §14) and **deliberately unscheduled**: it blocks nothing, in Phase 4 or after it. It stays an R-item rather than becoming a roadmap row on the rule R-11 established in the other direction: the Active Items table is the table CI-relevant work is read from, and a gap with no blocker dilutes it. Promote it the moment something is blocked on it, which is exactly how R-11 became `HTTP-GET-1`. | named, unscheduled; language-team routing 2026-08-05 |
| **R-15 `STATE-PROD-1`** | **A sum constructor carries at most one payload; there is no n-ary product.** `pSumArm` parses `optional pType` (`Parser.hs:328-333`), so the driver's per-phase state arms pay **one pair per arm** rather than a chain per field. Filed by DRIVER-LL Phase 4 and settled there as a non-blocker: `driver-ll-phase4-proposal.md` §4 gives the worked encoding (a pair of the run-common record and an n-arm sum over stage phases, maximum projection depth two) and names the cost. The strict-core question is deliberately deferred — `LLMLL.md:963` already reflects a single-constructor product to `(Pair2 s0 s1)` and an n-ary product is the same theory at wider arity — because Phase 4 needs the construct only in `def-shell`. Becomes a row if a sub-phase's port needs it, not before. | named, unscheduled; language-team routing 2026-08-05 |
| **R-13** | **`random-int` is declared nowhere and admitted anyway.** It has a `trustedPrelude` entry (`TypeCheck.hs:727`), a `primEffect` clause (`ObligationAssembly.hs:457`), and a codegen body (`CodegenHs.hs:658`, `random_int :: IO Int`, a `return 42` stub), and **no `builtinEnv` declaration**. It is the only name on the `trustedPrelude` list with that gap: `string-length` (`TypeCheck.hs:131`) and its line-mate `int-to-string` (`:142`) both carry real `builtinEnv` types. Consequences: `check` passes it with an unknown-function warning while `verify` errors, so an agent running `check` sees a usable function that does not exist; and because it is undeclared **nothing checks its arity**, so `(random-int lo hi)` against a nullary binding is accepted by both the checker and `Spec.hs:13435`. **No soundness hole** (see §5 probes: `verify` rejects it in every mode, so it never receives a tier). Recommended: remove all three sites and **retarget** `Spec.hs:13435` rather than deleting it. Zero `.llmll` / `.ast.json` callers. **Two tests pin the sites, not one:** `Spec.hs:14276` (CP-8) asserts `primEffect "random-int" == Just (Caps {ENonDet})` and fails the moment the `ObligationAssembly` clause goes, so it must be retargeted alongside INV-C3. CP-8's label coverage is already carried in full by CP-7 (`:14272-14274`, `wasi.clock.monotonic`). **Doc surface owed:** `LLMLL.md:823` asserts the `trustedPrelude` membership and the orphaned stub as present tense and goes false on removal; no gate covers it (R-12). | measured 2026-08-03; CP-8 + `LLMLL.md:823` found 2026-08-03 during implementation |

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

### Added 2026-08-03, CAP-PROC Phase 2

- **`time.time()` reaches no persisted artifact.** `rfc_to_implementation.py:1596` lives in
  `print_status()` and feeds exactly two printed lines (`:1598`, `:1607`) plus a `stalled` boolean
  that is also only printed; the function returns 0 at `:1641` and writes nothing. It is differenced
  against filesystem `st_mtime`, which is *why* it must be wall-clock: a monotonic reading has no
  shared origin with `st_mtime`. What does persist is `time.monotonic()` at `:1808`, into
  MANIFEST.json's `seconds`, whose only consumer is a display at `:1622`. **No clock operation was
  added.** Porting `--status` would need `wasi.clock.now` *and* a file-mtime accessor, neither of
  which exists; it is excluded from the port instead.
- **Generated-project dependency closure, `stack ls dependencies` against lts-22.43: 33 packages**
  with `process` + `cryptohash-sha256` + `bytestring` added (all three already compiler deps, so the
  snapshot is cached), **79** if `http-client` + `http-client-tls` are added. See R-11.
- **The `random-int` probe set.** Four programs, one minute, and it refuted three separate claims
  that had been argued from reading code alone. All at `GrammarCoreInversion`, the CLI default
  (`app/Main.hs:170`).

  | Probe | Body | Result |
  |---|---|---|
  | (a) | `(string-length s)` | clean |
  | (b) | `(random-int lo hi)` | `OK`, `warning: call to unknown function` — **no core-membership error** |
  | (c) | `(totally-made-up lo hi)` | **`error: callee is not body-faithful and not in the trusted prelude`** |
  | (d) | probe (b) under `llmll verify` | **`error: call to unknown function`**, in every mode |

  (b) vs (c) differ only in `trustedPrelude` membership, so **the entry is live and load-bearing**:
  it is exactly what suppresses the error (c) gets. That refutes "INV-C3 passes vacuously" (professor)
  and "the `trustedPrelude` entry is dead" (language-team). (d) refutes "a real unsoundness in the
  strict-verified-core" (language-team, Rev 3): `verify` rejects before any tier is assigned, so a
  function calling `random-int` cannot enter the trust closure at all. **`Spec.hs:13435` is therefore
  a discriminating test, not a dead one** — delete the `trustedPrelude` entry and probe (b) becomes
  probe (c). The lesson worth keeping: the reading path was wrong three times and the probes were
  cheap; construct the witness first.
- **`wasi.fs.read` fails closed on binary input.** `readFile` + `evaluate (length …)` inside
  `llmll_publish_io`'s `try` (`CodegenHs.hs:517-524`) turns an encoding failure into `RErr`, not a
  wrong value. So composing it with a pure hash does not mis-hash a binary file, it cannot read one
  at all, which is the argument for `wasi.fs.sha256` taking a path.
- **A failed spawn used to corrupt a later read.** Against `/bin/does-not-exist-xyz`,
  `createProcess` throws and `RErr` is correct, but the two redirect handles leaked still-open and
  the **next** `wasi.fs.read` of that path returned `resource busy (file is locked)`. Fixed in
  `a46d361` with `onException` guards; pinned by `Spec.hs` CP-17. Found by the execution stage, not
  by any compile-only check.

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
