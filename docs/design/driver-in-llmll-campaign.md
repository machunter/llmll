---
name: driver-in-llmll-campaign
title: "DRIVER-LL: a fully functional RFC-SWARM driver written in LLMLL, and the language work it requires"
status: "Rev 3, READY FOR ENGINEER, commit A cleared to start. Rev 3 settles one decision the engineer routed back and adds it as §8.3: BUILD-GATE-1 lands INSIDE commit A rather than as its own follow-on row, overriding the A.6 recommendation, because the gate is the only observer of the defect commit A fixes and the row it would otherwise wait on is UNSCHEDULED. Acceptance is a positive witness (red on the merge base, green after), which is the part that fails quietly. Rev 2: §8's two open decisions are SETTLED by user adjudication 2026-08-02: the LLMLL driver REPLACES the Python one, and tools/llmll-driver/ is the home. The retirement gate moved from self_test() to Phase 4 acceptance, because self_test() replays the mechanical stages only and cannot gate a decision about all fifteen. Rev 2 also adds the per-phase build-acceptance clause §3a called for but did not specify, and corrects §3a's grep count (three to five, matching the BUILD-GATE-1 roadmap row). Rev 1: Phase 0 was reopened (its blast-radius and spec-gap claims were re-measured and refuted) and re-scoped as P0-marker by user adjudication 2026-08-02 (a first adjudication chose plain P0-error; that option was mis-described and was re-put): LLMLL.md §9.6 stands, do-notation-design.md §2.4 is superseded, checkDiscardedCommand is promoted from warning to error gated on a new (discard) step marker, specified as DISCARD-1. Scope authorized by the user 2026-08-02, superseding rfc-swarm-roadmap-proposal.md §5.2. Depends on effect-response-channel-proposal.md (Rev 4, SETTLED)."
date: 2026-08-02
author: language-team
consumers: [compiler-engineer, documentation-lead, experiment-lead, professor, user]
---

# DRIVER-LL: the swarm driver in LLMLL

**Goal, as set by the user.** (1) Write a fully functional swarm driver in LLMLL. (2) Continue
building the project's tooling in LLMLL where that is the right call. The purpose is dogfooding: the
gaps this surfaces are the deliverable alongside the driver itself.

**Scope authorization.** `docs/design/rfc-swarm-roadmap-proposal.md` §5.2 (Rev 1.1, 2026-07-24)
says "Do not build a bespoke multi-agent framework, and do not activate R2", on the ground that an
LLMLL-self-hosted orchestrator adds surface without serving any acceptance criterion of the
RFC-SWARM demo. That reasoning was scoped to the demo's criteria. **The user has authorized this
campaign explicitly, on the ground that gap discovery is itself the criterion.** §5.2 stands for the
demo and is superseded for this campaign; doc-lead should record the amendment where §5.2 sits rather
than deleting it, so the original reasoning survives.

---

## 1. What already exists

`tools/llmll-driver/` (shipped v0.14.70) carries driver-spec §15.1, the **proved tier**: nine
functions across six modules (`stage`, `skip`, `gate`, `fill`, `token`, `liveness`), every one
body-faithful and clearing `--strict-verified-core`, with 26 contract clauses each `:source`-cited to
the section it discharges. `EXPECTED_VERDICTS.json` freezes eight refuting mutants and one good twin;
**five of the eight are defects that shipped in the Python driver**, and one
(`crux-gate-single-remedy`) refutes what the Python driver does today.

`shell.llmll` demonstrates §15.2's discipline over five operations and is labelled a partial artifact
by the spec's own terms: the fifteen-stage orchestration is unwritten, and §15.4 says an
implementation whose effectful surface lives in another language does not conform.

The specification is `experiments/rfc-swarm/targets/driver-spec.txt`, an Internet-Draft with
fifteen numbered sections and a three-tier trust split at §15.

**The decision logic is done. This campaign builds the program around it.**

---

## 2. The measured gap, at `llmll 0.14.78`

Counted against `scripts/rfc_to_implementation.py` (1814 lines), by call site.

| Driver need | Python sites | LLMLL surface today | Row |
|---|---|---|---|
| Consume any effect result | pervasive | **impossible**: `wasi.fs.read : string -> Command`, opaque | EFFECT-RESP |
| Perform a filesystem or outbound-HTTP effect at all | pervasive | **`wasi.fs.read` / `write` / `delete` and `wasi.http.post` are declared in `builtinEnv` (`TypeCheck.hs:154-161`) but absent from the codegen preamble (`CodegenHs.hs:394-409`), which defines only `stdout` / `stderr` / `http.response`. Measured: `(wasi.fs.read p)` gives `check` OK and `build` `[GHC-88464] Variable not in scope: wasi_fs_read`.** | **WASI-RT** (new; prerequisite of EFFECT-RESP) |
| Spawn and await a subprocess | 19 `subprocess.` | none; `haskell.process` FFI works but yields ⊤ authority | CAP-PROC |
| JSON read, write, parse | 18 `json.` | none; no dynamic type | JSON-1 |
| Regex and tokenizing | 15 `re.` | `regex-match` (bool), `string-split`, `string-concat-many`, `string-trim` | covered |
| Thread pool for the wave | 1 `ThreadPoolExecutor` | none | out of scope, see §5 |
| Workdir management | 7 `shutil.`, 5 `os.` | `wasi.fs.read` / `write` / `delete` only | CAP-PROC |
| sha256 file digest | 2 `hashlib` | `sha1` / `hmac-sha1` over `bytes[20]` only | CAP-PROC |
| Clock | 5 `time.` | `wasi.clock.monotonic` documented at `LLMLL.md:1125`, `:1661`; **unknown function** (warns, typechecks) | CAP-PROC (drift) |
| Fetch the source document | 2 `urllib` | `wasi.http.post` only | CAP-PROC |

Two structural facts govern the plan. First, the **authority collapse**: `primEffect`
(`ObligationAssembly.hs:419-431`) maps every `haskell.*`, `c.*` and unrecognized `wasi.*` name to
`Unbounded`, and `joinEff` makes ⊤ absorbing (`:408`), so one FFI call anywhere in a call graph makes
every function above it report `unbounded`. Routing the driver's effects through FFI would satisfy
driver-spec §15.2's letter (⊤ is an over-approximation) while making the report vacuous. Second, the
**FFI signature seam is unchecked**: a declared `(fn [cmd: string] -> int)` against
`callCommand :: String -> IO ()` typechecks, codegens, and builds, failing only at GHC and only when
a use forces the type. It cannot reach the proved tier (a `def` refuses an FFI callee at strict-core
admission), so it is an asserted-tier disclosure gap, not a soundness defect. The **IFACE-CONFORM**
row in `docs/compiler-team-roadmap.md` already names the FFI split as "stated in no spec section";
this campaign supplies the measured witness.

**Standing rule for this campaign, pre-registered.** Every `haskell.*` or `c.*` declaration written
in driver code is a **filed gap with a named missing capability**, and the FFI declaration count is a
reported metric of every phase. The acceptance bar from Phase 3 onward is **zero FFI declarations**.
Without this rule the exercise measures persistence rather than the language: each wall can be
papered over at the moment it is found, and the result is a program that runs and taught nothing.

---

## 3. Phases

Each phase has standalone value; the sequence degrades gracefully if it stops early.

### Phase 0: DO-ACCUM-1 `[CT][SPEC]` (M), **RE-SCOPED as P0-marker, Rev 1**

Rev 0 scoped this as: fix `emitDo` to compose intermediate commands via `seq-commands` per
`docs/archive/do_notation/do-notation-design.md` §2.4, delete `checkDiscardedCommand`, and land §9
text that does not exist. Re-measurement refutes the premises of all three. See
`effect-response-channel-proposal.md` (Rev 3), §DO-ACCUM-1, for the evidence; in summary:

- `LLMLL.md:1588` **is** a `do` semantics subsection (§9.6). The zero-hit grep missed it because the
  heading writes `` `do` ``-notation with the backticks inside the term.
- §9.6 does not merely fail to mandate composition; at `:1604` and `:1606` it specifies the current
  discard behaviour as intended and names the future direction as tightening to a **warn-or-error**.
  `do-notation-design.md` carries `Status: Approved — Pending Implementation` for v0.3 and was never
  implemented. Two normative texts, opposite directions.
- Blast radius is **two artifacts, not zero**: the JSON-AST fixture
  `compiler/test/fixtures/pair_type_test/do_emit_ac.ast.json` (no test consumer), and
  `scripts/doc-claims/do-notation-discard-warn.llmll`, which is run on every CI job by
  `scripts/doc_claims_gate.sh` (`.github/workflows/version-gate.yml:118`) and whose `@expect` pins
  the discard warning. Confirmed against the v0.14.78 binary. Deleting the warning fails DRIFT-CT-2.

**STOP condition already met, and discharged.** Rev 0's STOP read "if any existing program's
behaviour changes, the blast-radius measurement was wrong and the phase pauses for re-measurement."
The measurement was wrong; the phase paused here rather than after a red CI run, and the
re-measurement above discharges it.

**Settled scope (user adjudication, 2026-08-02, re-put once): P0-marker.** `LLMLL.md` §9.6 stands;
`do-notation-design.md` §2.4 is superseded.

A first adjudication chose plain P0-error, on my description that the agent would "write
`seq-commands` explicitly." **That description was wrong and the choice was re-put.** Measured,
`DoStep` binds only the state component (`Syntax.hs:237`, `TypeCheck.hs:1852-1854`), so no step can
reference an earlier step's `Command`, and §9.6:1606's "unless explicitly wrapped in `seq-commands`"
escape hatch is unreachable. Plain P0-error would therefore have made every multi-step `do` illegal
with no workaround. The settled variant gates the error on the `(discard …)` marker that the in-code
v0.8 note always intended ("Hard error deferred to v0.8 **when (discard expr) provides an explicit
opt-out**", `TypeCheck.hs:1858-1859`). Full spec: `effect-response-channel-proposal.md` §DISCARD-1.

The work is:

1. **DISCARD-1, a new surface construct.** `[s1 <- (step-a s0) :discard]` in S-expressions; an
   optional `"discard": true` on the `do-step` JSON-AST node, defaulting to `false`. Schema bump
   **0.9.0 to 0.10.0** recommended (the shipped schema is 0.9.0: `docs/llmll-ast.schema.json:18`,
   `ParserJSON.hs:47`), engineer to confirm against prior additive-field precedent. Freeze
   lifted at v0.11 (the lifted-exclusions note under `docs/compiler-team-roadmap.md` §"What's NOT on this Roadmap (and why)"); the required soundness argument is written
   in §DISCARD-1 and rests on the marker being erasable with no runtime denotation.
2. `checkDiscardedCommand` (`TypeCheck.hs:1860-1865`) is **promoted from warning to error**, gated on
   the marker, plus a second rule rejecting the marker on the final step. The deferral note at
   `:1858-1859` is removed. `emitDo` is **not touched** and generated Haskell is bit-identical.
3. `LLMLL.md:1606` becomes the shipped rule: the `(discard cmd)` marker moves from "future" to
   present tense, and the unreachable `seq-commands` escape-hatch clause is struck as measured-false.
   `:1604` stands. Doc-lead's slot.
4. `scripts/doc-claims/do-notation-discard-warn.llmll`: `@expect` flips `warn:` to `check-error:`
   with the same pinned substring; `@claim` re-worded from "emits a discard warning" to "is
   rejected". Same commit as (2).
5. `compiler/test/fixtures/pair_type_test/do_emit_ac.ast.json` re-shaped by adding
   `"discard": true` to its step 0, which is better than removing it: it then exercises the new
   field. No test consumer, so nothing asserts against it either way.
6. `docs/archive/do_notation/do-notation-design.md` marked superseded-by-§9.6 so the next reader
   does not re-derive DO-ACCUM-1 from it. Doc-lead's slot.

- **Why the error family rather than P0-compose:** under RC-2 an auto-composing `do` discards every
  non-final step's response and so could never consume an intermediate effect result: the exact
  shape stages E and G2 need. See `effect-response-channel-proposal.md` Rev 3, §DO-ACCUM-1.
- **Acceptance:** a two-step do-block with an **unmarked** non-final `Command` is a `check` error;
  DRIFT-CT-2 green at 14 doc-claims; `LLMLL.md §9.6` states one rule rather than two.
- **Cost, stated up front:** `do` still cannot sequence effects; it threads state and now requires
  every dropped command to be marked. The agent cannot recover a dropped command by writing
  `seq-commands` inside the block, because no step binds an earlier step's `Command`. Code that
  genuinely needs sequenced effects must leave `do` and use nested `let` with explicit pair
  destructuring. The marker makes that boundary visible instead of silent.
- **Does not block Phases 1-5.** EFFECT-RESP's RC-1..RC-4 are independent of this choice; `do` is
  sugar over the pair-thread model and the driver spine can be written without it. Phase 0 is
  sequenced first for attributability, not because anything depends on it.

### Phase 1 — EFFECT-RESP `[CT][SPEC]` (M), with **WASI-RT as step zero**

Implement the response channel per `effect-response-channel-proposal.md` Rev 3: RC-1..RC-4, the
compiler-supplied `Response` sum, the `:step` arity change, the console-harness restructure.

**Step zero, WASI-RT.** Four of the seven declared `wasi.*` builtins have no codegen definition, so
`wasi.fs.read` cannot be performed at all: `check` passes, `build` dies at GHC with
`Variable not in scope: wasi_fs_read`. RC-1 delivers one response per *performed* command, so the
channel has nothing to attach to until this lands. See §2 and the proposal's prerequisite section.

- **Acceptance:** a program reads a file and branches on its contents; the **twelve** in-tree console
  programs are migrated and behave identically (six `.llmll`, six `.ast.json`; an earlier count of
  five was low); `Σ_auto` unchanged (corpus `.fq` byte-identical for every file not using the
  channel); the RC-1 bijection is exercised by a fixture that counts performed commands against
  delivered responses; **and the build-acceptance clause (§3a): the reading program is emitted by
  `llmll build`, compiles under GHC, and is executed on at least one input.** For this phase the
  clause is not ceremonial. It is the only criterion that distinguishes a working `wasi.fs.read`
  from the lazy no-op the engineer plan's risk 8 describes.
- **The migration has no `check`-time diagnostic until it is built.** `checkStatement (SDefMain{..})`
  (`TypeCheck.hs:1405-1414`) discards the `:step` inferred type, so every unmigrated console program
  stays green at `check` and dies at GHC. The new arity check must land in the same commit; it is the
  migration's only warning.
- **STOP:** if the corpus `.fq` is not byte-identical for non-participating files, the change reached
  the verification surface, which the design says it must not.

### Phase 2 — CAP-PROC `[CT][SPEC]` (M) and JSON-1 `[CT][SPEC]` (M), parallel

**CAP-PROC** gives the driver's effects real capability names so authority stays bounded:
`wasi.proc.spawn`, `wasi.proc.await`, `wasi.clock.monotonic` (closing the documented drift),
`wasi.fs.list`, `wasi.fs.mkdir`, `wasi.http.get`, and `sha256`. Each needs one `EffectLabel`
constructor, one `primEffect` clause, one `builtinEnv` signature, and one codegen case. **Each
response-bearing operation must map to an existing `Response` arm**; none requires a new one, which
is the check that the arm set chosen in Phase 1 was right.

`wasi.proc.spawn` is the first capability that can leave the sandbox by construction, so its grant
must name the executable, mirroring `(capability read-write "/rfc-swarm-runs")` rather than granting
spawn in general. That soundness argument belongs in the CAP-PROC design record, per the lifted-freeze
policy: the lifted-exclusions note under `docs/compiler-team-roadmap.md` §"What's NOT on this Roadmap (and why)".

**JSON-1** adds a **sealed `Json` builtin ADT**, `def-shell`-only: `json-parse : string ->
Result[Json, string]`, `json-serialize : Json -> string`, and typed accessors returning `Result`.
`Json` is recursive, which is Lever C territory for verification, and that is fine precisely because
it is sealed and opaque: it never enters a body-faithful VC, exactly as `list[a]` does not today. The
alternative, `haskell.aeson` through FFI, is rejected by the standing rule in §2 and by the authority
collapse.

- **Acceptance (CAP-PROC):** a `def-shell` that spawns a process and reads a file reports bounded
  authority, not `unbounded`, in `verify --obligation-report --json`.
- **Acceptance (JSON-1):** a round trip `json-serialize (json-parse s)` over the committed
  `EXPECTED_VERDICTS.json` and one `manifest.json`; `Json` rejected in a `def` body at strict-core
  admission.
- **Acceptance (both):** the build-acceptance clause (§3a). The spawning `def-shell` and the JSON
  round trip are each built and run, not only checked; a new `builtinEnv` signature with no codegen
  case is the WASI-RT defect repeated, and this phase adds seven of them.
- **STOP (either):** a needed operation has no `Response` arm. That is a Phase 1 design error and
  routes back to language-team rather than being patched with a new arm ad hoc.

### Phase 3 — the mechanical spine `[EXP][CT]` (M)

Port stages **A, E, G2, J, L** (the five typed `mechanical` or `gate` in
`rfc_to_implementation.py:1334-1376`) as `def-shell` orchestration over the existing proved cores in
`tools/llmll-driver/`. These are the stages whose decision logic is already verified, so the port
adds the program around a proved centre rather than duplicating it.

- **Acceptance:** the five stages run end to end against the committed TFTP execution and reproduce
  `self_test()`'s pinned results (`rfc_to_implementation.py:1378`); **zero FFI declarations**; every
  ported function's authority is bounded; the proved cores are called, not reimplemented; the
  build-acceptance clause (§3a). Clearing this phase is what licenses running a campaign off the
  LLMLL driver; it does **not** license retiring the Python one, which is Phase 4's gate (§8.1).
- **STOP:** any stage requiring an unavailable effect halts the phase and files the gap; it does not
  get an FFI workaround.

### Phase 4 — the agent-delegated stages and the wave `[EXP][CT]` (L)

Port B, C, D, F, H, I, K, M, N, O. Stage M (the wave) ships **serial**: agents are spawned and
awaited one at a time.

Serial is a decision, not a limitation discovered late. LLMLL has no concurrency surface
(`Control.Concurrent.Async` sits in the generated preamble as codegen-internal with no language-level
form), and adding one would be a larger language change than everything else in this campaign
combined. Parallelism is a throughput optimization, not a correctness property, and a serial wave
exercises the token discipline `token.llmll` proves just as well. Whether to add a concurrency
surface is a decision for after the driver runs, informed by measured wall-clock rather than by
anticipation.

- **Acceptance:** a complete run reproduces a committed campaign's artifacts; zero FFI declarations;
  the driver's own authority report is bounded end to end; §15.1's seven obligations are discharged
  by the proved cores the program calls; the build-acceptance clause (§3a).
- **This acceptance list is the Python driver's retirement gate (§8.1).** It is the first criterion
  in the campaign that exercises all fifteen stages, which is why the retirement rides here rather
  than on `self_test()`. Retirement does not follow automatically from the phase closing: the
  plumbing lifted from §5.3 is ported first, and the claim is worded per §5.4.
- **STOP:** if serial wall-clock makes a campaign impractical, stop and file the concurrency
  requirement with the measurement attached. Do not add a concurrency surface mid-campaign.

### Phase 5 — conformance claim and disclosure `[SPEC]` (S)

State the driver's tier claim per driver-spec §15.4, which requires distinguishing proved from
asserted obligations. Add the FFI-seam sentence to §15.2 (the declaration bounds nothing and enforces
nothing, and it cannot reach the proved tier). Report the campaign's gap inventory: every filed gap,
its phase, and whether it was closed or deferred.

- **Acceptance:** the claim distinguishes tiers per obligation; the gap inventory is complete; no
  claim is made about the §10 token property beyond the per-step form already disclosed at
  `tools/llmll-driver/README.md:39-41`; and, per §8.1, the retirement of the Python driver is stated
  as a language-expressiveness result and **not** as an assurance result. The orchestration is
  `def-shell` throughout and adds no proved obligation, so "the verified driver replaced the
  unverified one" is the one sentence this campaign must not produce.
- **The build-acceptance clause (§3a) is vacuous here.** This phase emits documents. Stated so a
  reader does not have to decide whether a document counts.

---

## 3a. The campaign is the first thing in this repository that has to build

Measured while planning Phase 1, and it reframes the risk profile of everything above.

No in-tree path invokes `llmll build`. `grep -rn 'llmll build'` across `scripts/`, `.github/`,
`compiler/test/`, `tools/`, and `Makefile` returns five hits, all comments or doc-claim prose
(`scripts/doc_path_lint.py:46` and `:76`, `scripts/doc-claims/checkout-requires-astjson.llmll:4`,
`scripts/doc-claims/open-after-def-verify.llmll:4`, `compiler/test/Spec.hs:13974`), and
`compiler/test/Spec.hs:13974` records that `llmll build`'s own `stack build` self-check never ran.
`check-examples.sh` typechecks. The corpus is a **check-only** corpus. (Rev 1 said three; re-measured
at `f3f3091`. The BUILD-GATE-1 roadmap row already said five.)

**Three defects already sit in the resulting `check`-passes / `build`-fails seam**, and all three
were found in the last day:

1. **WASI-RT.** Four declared `wasi.*` builtins have no runtime; `(wasi.fs.read p)` typechecks and
   fails at GHC.
2. **The `:step` arity change** Phase 1 requires. `checkStatement (SDefMain{..})`
   (`TypeCheck.hs:1405-1414`) discards the `:step` inferred type, so a breaking arity change is
   invisible to `check` on every program.
3. **`IFACE-CONFORM`** (row of that name in `docs/compiler-team-roadmap.md`), which already names the FFI signature
   split as "stated in no spec section". WASI-RT reaches the same seam with no FFI in sight.

DRIVER-LL's goal is a *fully functional* driver, which means a **running binary**, which makes this
campaign the first artifact in the repository that must clear GHC end to end. Everything the campaign
touches will be exercised through a code path that has never had a gate on it.

**Consequence for the phase plan, stated up front rather than discovered at Phase 3.** Expect
build-tier defects at a rate the `check`-tier history does not predict, and do not read a green
`check` as evidence a phase is done. A minimal build gate over one effectful program is routed as its
own roadmap row; until it exists, every phase's acceptance should include building at least the
artifact that phase produces.

**The build-acceptance clause (Rev 2).** Rev 1 stated that intent without specifying it, and a phase
whose other criteria are all `check`-tier can satisfy them while the binary is broken. Every phase
from 1 through 4 carries this conjunct, written into its acceptance list rather than left as a note:

> The artifact this phase produces is emitted by `llmll build`, compiled by GHC, and the resulting
> binary is executed on at least one input.

Three conditions, not one, because this campaign has already produced a defect at each seam. WASI-RT
passes `check` and dies at GHC, so emitting is not compiling. And per the engineer plan's risk 8, a
`wasi_fs_read` body written as `readFile path >> return ()` performs no read under lazy IO while
compiling clean and satisfying every test that checks the command's shape, so compiling is not
running. Phase 5 produces documents and the clause is vacuous there; that is stated so a reader does
not have to decide whether a document counts.

This is not BUILD-GATE-1. That row is a CI gate over one program, filed separately, and this clause
does not wait on it existing.

---

## 4. Dependency order

```
Phase 0 (DO-ACCUM-1)   [independent; sequenced first for attributability only]

Phase 1 (EFFECT-RESP)             ← the wall; nothing reads a file before this
   ├─> Phase 2a (CAP-PROC)
   └─> Phase 2b (JSON-1)
          └─> Phase 3 (mechanical spine: A, E, G2, J, L)
                 └─> Phase 4 (agent stages + serial wave)
                        └─> Phase 5 (conformance claim)
```

**Corrected in Rev 1.** Rev 0 drew Phase 0 as a strict predecessor of Phase 1, on the rationale that
"RC-2 gives `seq-commands` the meaning DO-ACCUM-1's composition depends on." That rationale holds
only under P0-compose, which Rev 1 retracts: under the settled P0-marker there is no composition, so
nothing in Phase 1 depends on Phase 0. The two are independent and may land in either order or
concurrently. Phase 0 is still listed first, for one reason that survives the re-scoping: it is small
and self-contained, so landing it alone keeps an unexpected diff attributable. Phases 2a and 2b are
independent of each other.

---

## 5. What NOT to do

1. **Do not reach for `haskell.*` FFI to get past a wall.** It works end to end and it defeats the
   exercise: the authority report collapses to ⊤ for the whole call graph above the call, and the
   declared signature is unchecked against the real one. Every FFI declaration is a filed gap, and
   the count is reported per phase (§2, standing rule).
2. **Do not add a concurrency surface to make the wave parallel.** Serial is the Phase 4 decision.
   Revisit only with a measured wall-clock argument after the driver runs.
3. **Do not port `argparse`, `shutil.copytree`, tempdir handling, or path juggling faithfully.**
   Roughly 300 of the 1814 lines carry the marginal teaching: the stage sequencer, the fill protocol
   and its separated retry budgets, the token discipline, and the wave scheduler. The rest establishes
   that LLMLL lacks utilities everyone already knows it lacks.
   **Rev 2 qualification, forced by the replacement decision (§8.1).** Under "runs beside," a driver
   that ports the 300 teaching lines and skips the plumbing is a complete artifact. Under
   "replaces," the skipped lines include the operator's whole CLI surface (`--agent-cmd`,
   `--workdir`, `--self-test`, `--audit-blindness`) and the run layout, which a replacement cannot
   do without. The exclusion therefore holds **through Phase 4** and is **lifted at the retirement
   step only**, where the plumbing is ported as utility work with no teaching claimed for it and no
   phase acceptance riding on it. Anything ported under this lifted exclusion is reported as
   utility, not as a language result.
4. **Do not report this campaign as assurance progress.** Every orchestration function is `def-shell`
   and produces no new proved obligation. The proved tier is already done and its claim is sharp
   (`tools/llmll-driver/README.md:74-76`); a larger shell dilutes it. The deliverable is a running
   program and a gap inventory.
5. **Do not let the Python driver diverge silently.** It runs real campaigns. `self_test()` is the
   oracle for the port; do not run a campaign off the LLMLL driver until that oracle passes.
   **Rev 2 correction.** `self_test()` is the oracle for **Phase 3**, not for the port as a whole:
   `--self-test` replays the committed TFTP Phase 0 data through the **mechanical** stages
   (`scripts/rfc_to_implementation.py:46`, `:49`), which is A, E, G2, J, L. The ten agent-delegated
   stages are not exercised by it. It gates "may run a campaign"; it does not gate "may retire the
   Python driver." See §8.1.
6. **Do not fix `:mode http` or `:mode cli` as part of this.** Both are broken
   (`CodegenHs.hs:980-994` errors out; `:970-975` executes no command) and both are out of scope.
   File them; they are the next thing after the driver, not part of it.

---

## 6. Collected today, independent of the phases

`crux-gate-single-remedy` refutes what the Python driver does now: `gate.llmll:30-44` requires the
remedy to follow from the barrier's class, and `rfc_to_implementation.py:904-945` emits a generic
message per condition against a flat `BARRIERS` dict (`:87-96`). Fixing the Python driver against the
verified contract is a day of work, needs none of the language changes above, and is the cheapest
demonstration that the dogfood pays. Experiment-lead owns it.

---

## 7. Roadmap delta, staged for documentation-lead

The roadmap is doc-lead's slot. **Rev 1 note:** this delta was applied by doc-lead at `cb90c3b`, so
the table below is now a record of what was staged, not a pending request, with one exception. The
**DO-ACCUM-1** row needs a further doc-lead pass: the applied version at
`docs/compiler-team-roadmap.md:50` corrected the blast radius to one JSON-AST fixture, which is
closer than "zero" but still incomplete, and it repeats two claims that Rev 1 refutes: that no
`.llmll` source contains a do-block, and that `LLMLL.md §9` has no do-notation text. The corrected
row text is given below. Everything else in the applied delta stands.

Original staging target: the **Open work (v0.12+ lane)** table at `docs/compiler-team-roadmap.md:48-67`.

> **Rev 1 closing note. This table is now a historical record, not a live delta.** Doc-lead has
> since applied every correction and more: the roadmap's DO-ACCUM-1 row at
> `docs/compiler-team-roadmap.md:50` carries P0-marker, DISCARD-1, the two-artifact blast radius,
> and the corrected schema pair. The rows below still read **P0-error**, still cite
> `TypeCheck.hs:1857-1866` (the measured range is `:1860-1865`, note at `:1858-1859`), and do not
> mention DISCARD-1. **The roadmap is the live surface and is correct; read it, not this table.**
> Preserved unedited so the staging step stays auditable.
>
> One row is missing from both this table and the roadmap: **WASI-RT**, the four declared `wasi.*`
> builtins with no codegen definition (see §2 above). It is held pending the engineer's scope read
> so it gets written once rather than written and then amended.

| Item | Current Status | Next Action |
|------|---------------|-------------|
| **EFFECT-RESP** (a response channel, so a program can consume the result of its own effects) `[CT][SPEC]` | **OPEN**: design SETTLED (Rev 3; two professor rounds folded at Rev 2) | `wasi.fs.read : string -> Command` and `Command` is opaque, so no program can read a file and branch on it; measured, `(string-length (wasi.fs.read p))` is a type error. The effect type is a **monoid**, not an applicative: `Command` is nullary (`TypeCheck.hs:158`, `CodegenHs.hs:830`) and `seq-commands` is its `<>` (`TypeCheck.hs:161`), so the effect structure cannot depend on any value. Fix is a Mealy response channel in the `def-main` harness, not a result-returning read builtin (Rev 0's proposal, withdrawn: it performs IO during pure evaluation, abandoning `LLMLL.md:415`, and leaves effect order dependent on an evaluation order §12 never pins). Four invariants: one response per performed command, `seq-commands` yields the right component's response, `:init`'s command supplies the first response, and the terminating step's command is not performed. `Response` is **compiler-supplied**, not program-declared, because the command alphabet is sealed. `Σ_auto` unchanged; no schema bump. The command-to-response pairing is unchecked and is a **trust-channel disclosure** closed by CMD-A, **not** by R1. Design: [`design/effect-response-channel-proposal.md`](design/effect-response-channel-proposal.md) (Rev 3). |
| **DO-ACCUM-1** (a non-final `do` step's `Command` is silently discarded) `[CT][SPEC]` | **OPEN**: re-scoped **P0-error** by user adjudication 2026-08-02; **not** a plain codegen defect | **Corrected in Rev 1; supersedes the row applied at `docs/compiler-team-roadmap.md:50`, including its title.** `emitDo` ([`CodegenHs.hs:741`](../../compiler/src/LLMLL/CodegenHs.hs)) returns `(finalState, _cmdN)` and drops every earlier command. That matches `LLMLL.md:1604` ("the final result is `(lastState, lastCommand)`") and `LLMLL.md:1606`, which documents the discard as **intended** ("effects are values, not statements; sequencing them is the agent's explicit responsibility") and names the future direction as tightening "to a warn-or-error." It contradicts [`archive/do_notation/do-notation-design.md`](archive/do_notation/do-notation-design.md) §2.4, which mandates `seq-commands` composition but carries `Status: Approved — Pending Implementation` for **v0.3** and was never implemented. Two normative texts in conflict, not a regression. **Settled P0-error:** `emitDo` untouched; `checkDiscardedCommand` (`TypeCheck.hs:1860-1865`) promoted warning → **error** with its v0.8 deferral note removed; `LLMLL.md:1606`'s closing sentence becomes the shipped rule and `:1604` stands; §2.4 marked superseded. Chosen over P0-compose because under EFFECT-RESP RC-2 an auto-composing `do` discards every non-final step's response and could never consume an intermediate effect result: stages E and G2's shape. **Blast radius: two artifacts, not zero and not one.** (a) `compiler/test/fixtures/pair_type_test/do_emit_ac.ast.json`, a two-step JSON-AST block whose step-0 command the emitter drops; no test consumer, so it pins nothing. (b) `scripts/doc-claims/do-notation-discard-warn.llmll`, a two-step **S-expression** block shipped at v0.14.57 (`3e29beb`) and run on every CI job by `scripts/doc_claims_gate.sh` (`.github/workflows/version-gate.yml:118`); `@expect: warn:discards this intermediate command`, confirmed emitted by the v0.14.78 binary, so **any change to the warning moves DRIFT-CT-2**: under P0-marker the fixture's `@expect` flips to `check-error:` in the same commit; under the retracted P0-compose scoping, deleting the warning would simply have failed the gate. Two prior claims are retracted: "zero do-blocks in `.llmll` sources" (this fixture is one) and "`LLMLL.md §9` has no do-notation text" (`LLMLL.md:1588` is section 9.6, "`do`-notation State Threading"; the zero-hit grep missed it because the heading writes the backticks inside the term). Reproduce with `grep -rn --include='*.llmll' -E '\(do($\|[[:space:]])'` **and** `grep -rl --include='*.json' '"kind"[[:space:]]*:[[:space:]]*"do"'`; either grep alone under-reports. Design: [`design/effect-response-channel-proposal.md`](effect-response-channel-proposal.md) (Rev 3). |
| **CAP-PROC** (the capability surface the driver's effects need) `[CT][SPEC]` | **OPEN** — depends on EFFECT-RESP | `wasi.proc.spawn` / `wasi.proc.await`, `wasi.clock.monotonic`, `wasi.fs.list` / `wasi.fs.mkdir`, `wasi.http.get`, `sha256`. Each is one `EffectLabel`, one `primEffect` clause (`ObligationAssembly.hs:419-431`), one `builtinEnv` signature, one codegen case. The point is **bounded authority**: `primEffect` maps every `haskell.*`, `c.*` and unrecognized `wasi.*` name to ⊤ and `joinEff` makes ⊤ absorbing (`:408`), so routing these through FFI makes every function above them report `unbounded`, satisfying driver-spec §15.2's letter while making the report vacuous. `wasi.clock.monotonic` is **drift, not a new feature**: documented at `LLMLL.md:1125` and `:1661`, measured as an unknown function that only warns. `wasi.proc.spawn` is the first capability that can leave the sandbox by construction, so the grant must name the executable; that soundness argument is required by the lifted-freeze policy (`:242`). |
| **JSON-1** (a sealed `Json` builtin, `def-shell`-only) `[CT][SPEC]` | **OPEN** — depends on EFFECT-RESP | The driver has 18 JSON call sites and LLMLL has no JSON and no dynamic type. `json-parse : string -> Result[Json, string]`, `json-serialize`, typed `Result`-returning accessors. `Json` is recursive, which is Lever C for verification and irrelevant here because it is **sealed and opaque**: it never enters a body-faithful VC, exactly as `list[a]` does not today. Rejected alternative: `haskell.aeson` through the FFI tier, which collapses authority to ⊤ and carries an unchecked signature. |
| **DRIVER-LL** (a fully functional RFC-SWARM driver in LLMLL) `[EXP][CT]` | **OPEN** — Phase 0 ready; scope authorized 2026-08-02 | Five phases: DO-ACCUM-1, EFFECT-RESP, CAP-PROC + JSON-1, the mechanical spine (stages A/E/G2/J/L over the proved cores in `tools/llmll-driver/`), then the agent stages with a **serial** wave, then the §15.4 conformance claim. Standing rule: every `haskell.*` declaration is a filed gap and the FFI count is a reported metric; the bar from Phase 3 is **zero**. Supersedes [`design/rfc-swarm-roadmap-proposal.md`](design/rfc-swarm-roadmap-proposal.md) §5.2 ("do not activate R2") for this campaign only; §5.2 stands for the demo. Design: [`design/driver-in-llmll-campaign.md`](design/driver-in-llmll-campaign.md). |
| **CMD-A** (parameterize `Command[a]`) `[CT]` | **RECORDED TARGET — not scheduled** | The free-monad-over-signature construction (Swierstra JFP 2008; Kiselyov and Ishii, Haskell '15): each operation carries its own result type and the harness is the interpreter. Closes EFFECT-RESP's command-to-response pairing residue. Cheaper than the GADT framing suggests, because the effect constructors live in the sealed `builtinEnv` and never reach the user-facing `type` grammar. **Adds no verification surface**: a bind is an IO construct so it lands in `def-shell` by the existing `LLMLL.md:451` rule, and its continuation is a lambda, already excluded from `Σ_auto` at `:238`. **Declines algebraic-effect handlers** (Plotkin and Pretnar ESOP 2009; Bauer and Pretnar JLAMP 2015): delimited continuations would break the crash-freedom rule at `LLMLL.md:1747` and make a linear event log an inadequate replay record. |

Two amendments to existing rows.

**R2** (`:217`, Self-Hosted Orchestrator, research track): note that DRIVER-LL is a scoped, authorized
activation of the same idea for the RFC-SWARM driver rather than for `llmll-orchestra`, and that R2's
promotion criterion (agent accuracy on the auth exercise) does not govern it.

**Bundle B1** (`:405`, "awaits a B1-native experiment"): DRIVER-LL is the candidate experiment, being a
six-module effectful artifact with a written external requirement that authority be a declaration
rather than a matter of inspection (driver-spec §15.2). **Correction to the record:** an earlier
language-team turn worried that CMD-A would degrade B0's summary from exact to approximate. That
premise was false. B0 Rev 2 recast the summary as a **may-over-approximation** with ⊤ at opaque
boundaries (`archive/shipped-design-specs/bundle-b0-effect-summary-proposal.md:100, :109`, §4.2), and
`ownEffects` joins both arms of every `EIf` and every match arm (`ObligationAssembly.hs:443-444`), so
the approximation is realized at the first conditional in any program. Exactness was never a property
of this analysis.

Also: `docs/design/INDEX.md` gains one-liners for both new proposals, and
`rfc-swarm-roadmap-proposal.md` is currently referenced from **nowhere** in
`docs/compiler-team-roadmap.md` despite constraining R2; a pointer beside the R2 row would close that.

**One live delta, added at Rev 3.** The **BUILD-GATE-1** row at `docs/compiler-team-roadmap.md:55`
closes with "Cost and placement are the engineer's call; this row records the gap and the three
witnesses." Placement is no longer the engineer's call: §8.3 settles it inside commit A by user
adjudication. That sentence should be replaced with the §8.3 outcome, and the row's status should
move from a standalone **OPEN** to **OPEN, riding commit A (WASI-RT)** so that no reader schedules it
separately. Cost remains the engineer's call in the sense §8.3 leaves open, namely which program the
gate compiles. This is a doc-lead edit; the roadmap row reads stale until it is made.

---

## 8. Settled decisions (Rev 2)

Both were put to the user on 2026-08-02 and both are answered. Rev 1 held them open.

### 8.1 The LLMLL driver **replaces** the Python one

**Settled: replaces.** The Python driver is retired once the LLMLL driver clears the gate below. This
is a change from Rev 1's working assumption ("beside") and it has three consequences, all recorded
here rather than discovered during Phase 4.

**The gate is Phase 4 acceptance, not `self_test()`.** The decision was put with `self_test()` named
as its trigger, and that trigger is insufficient for it: `--self-test` replays the committed TFTP
Phase 0 data through the **mechanical** stages only (`scripts/rfc_to_implementation.py:46`, `:49`),
so it covers A, E, G2, J, L and leaves B, C, D, F, H, I, K, M, N, O unexercised. Retiring the driver
that runs real campaigns on a test covering five of fifteen stages would retire the tested artifact
on the strength of a partial test. **Phase 4's acceptance already states the sufficient criterion**
(a complete run reproduces a committed campaign's artifacts, with zero FFI declarations and bounded
authority end to end), so the retirement rides on that. `self_test()` keeps its Rev 1 role unchanged:
it gates whether a campaign may be run off the LLMLL driver at all, which is the Phase 3 boundary.

**§5.3's porting exclusion is lifted at the retirement step.** A replacement needs the CLI surface
and the run layout that §5.3 excludes as teaching-free. The exclusion holds through Phase 4 and the
plumbing is ported afterward as utility work. See the Rev 2 qualification on §5.3.

**Retirement is not an assurance result, and §5.4 governs how it is reported.** Every orchestration
function is `def-shell` and produces no new proved obligation. "The verified driver replaced the
unverified one" would be false in the way that matters: what was demonstrated is that the language
can express the program, not that the program carries more proof than its predecessor. Phase 5's
claim states this explicitly, alongside the tier split it already owes driver-spec §15.4.

### 8.2 `tools/llmll-driver/` is the home

**Settled: `tools/llmll-driver/`.** The nine proved cores are already there and the orchestration
calls them, so co-location avoids a cross-tree import for no gain. The cost is that the directory's
README currently says "what is here is not the driver," which goes stale on completion; that is a
doc-lead fix at Phase 3, not a reason to split the tree. §5.4's warning against diluting the proved
tier's claim (`tools/llmll-driver/README.md:74-76`) is a reporting discipline and is not discharged
by directory layout either way.

### 8.3 BUILD-GATE-1 lands **inside commit A**, not as a follow-on (Rev 3)

**Settled by user adjudication 2026-08-02: the build smoke gate ships in the same commit as the four
WASI-RT preamble bodies.** This overrides the engineer's A.6 recommendation
(`driver-ll-phase01-implementation-plan.md` §A.6), which proposed the gate as its own row on the
grounds that a multi-minute CI step should not ride into an unrelated patch. The recommendation was
reasonable about CI hygiene and wrong about which patch is unrelated: the gate is the only thing that
observes what commit A fixes, so shipping them apart ships the fix and its blind spot together and
leaves closing the blind spot to a row that is currently **UNSCHEDULED**
(`docs/compiler-team-roadmap.md:55`).

**The argument that decides it is the witness count, not the cost.** Three independent defects of the
form "passes `llmll check`, fails at GHC" were found in this seam within one release: WASI-RT's four
undefined builtins, the `:step` arity change that `checkStatement (SDefMain {..})` cannot report
because it discards `inferExpr stepE`'s result (`TypeCheck.hs:1405-1414`), and `IFACE-CONFORM`,
reached with no FFI declaration in sight. Three witnesses by three unrelated routes is a systemic
absence of a gate, not three oversights, and §3a already commits the campaign to being the first
artifact in this repository that must clear GHC end to end.

**Scope, unchanged from the roadmap row: one effectful program built in CI, not a build sweep.**
`scripts/build_smoke.sh` runs `llmll build` on a single program whose source calls all four of the
newly defined builtins, invoked from `.github/workflows/version-gate.yml` alongside the existing
`scripts/doc_claims_gate.sh` step. Candidate program is
[`../tools/llmll-driver/shell.llmll`](../../tools/llmll-driver/shell.llmll), which already calls
`wasi.fs.read` (`:46`) and `wasi.fs.write` (`:37`); if it carries unrelated blockers, a purpose-built
fixture is acceptable, and the only binding requirement is that every one of the four bodies is
exercised. Choosing the program is the engineer's call; whether the gate exists is not.

**Acceptance is a positive witness, and this is the part that can go wrong quietly.** The gate must
be demonstrated **red on the merge base and green after the four bodies land**, with the failing GHC
output recorded in the commit message. A build gate that passes both before and after the patch has
not been shown to observe anything, which is precisely how the four missing definitions survived from
whenever `builtinEnv` last grew: the absence is invisible unless something forces the compile. The
same discipline applies to A.6's `forM_` over the `builtinEnv` `wasi.` prefix list, whose stated
purpose is that an eighth builtin without a preamble definition fails the suite; that test is the
`check`-tier guard and the smoke gate is the `build`-tier one, and neither substitutes for the other.

**Cost, stated rather than elided.** Minutes of CI on every job, paid from the first commit of the
campaign onward. That is the price of the seam having no observer at all today, and it is not
recovered by deferring it, because the four bodies are exactly what the gate would be added to guard.
