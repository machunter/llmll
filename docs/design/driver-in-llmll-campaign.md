---
name: driver-in-llmll-campaign
title: "DRIVER-LL: a fully functional RFC-SWARM driver written in LLMLL, and the language work it requires"
status: "Rev 0, READY FOR ENGINEER. Scope authorized by the user 2026-08-02, superseding rfc-swarm-roadmap-proposal.md §5.2. Depends on effect-response-channel-proposal.md (Rev 2, SETTLED)."
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
admission), so it is an asserted-tier disclosure gap, not a soundness defect. `IFACE-CONFORM`
(`docs/compiler-team-roadmap.md:53`) already names the FFI split as "stated in no spec section"; this
campaign supplies the measured witness.

**Standing rule for this campaign, pre-registered.** Every `haskell.*` or `c.*` declaration written
in driver code is a **filed gap with a named missing capability**, and the FFI declaration count is a
reported metric of every phase. The acceptance bar from Phase 3 onward is **zero FFI declarations**.
Without this rule the exercise measures persistence rather than the language: each wall can be
papered over at the moment it is found, and the result is a program that runs and taught nothing.

---

## 3. Phases

Each phase has standalone value; the sequence degrades gracefully if it stops early.

### Phase 0 — DO-ACCUM-1 `[CT]` (S)

Fix `emitDo` to compose intermediate commands via `seq-commands` per
`docs/archive/do_notation/do-notation-design.md` §2.4; delete `checkDiscardedCommand`; land the
verbatim §9 text the settled design mandated.

- **Acceptance:** the two-step do-block witness in `effect-response-channel-proposal.md` emits both
  commands; no warning remains; `LLMLL.md §9` contains a `do` semantics subsection.
- **Why first:** it is a shipped codegen defect with a settled design to conform to and **zero
  in-tree witnesses** (`(do ` occurs twice in the tree, both in walkthrough markdown), so its verdict
  is attributable in isolation and cannot be confounded by Phase 1.
- **STOP:** if any existing program's behaviour changes, the blast-radius measurement was wrong and
  the phase pauses for re-measurement.

### Phase 1 — EFFECT-RESP `[CT][SPEC]` (M)

Implement the response channel per `effect-response-channel-proposal.md` Rev 2: RC-1..RC-4, the
compiler-supplied `Response` sum, the `:step` arity change, the console-harness restructure.

- **Acceptance:** a program reads a file and branches on its contents; the five in-tree console
  programs are migrated and behave identically; `Σ_auto` unchanged (corpus `.fq` byte-identical for
  every file not using the channel); the RC-1 bijection is exercised by a fixture that counts
  performed commands against delivered responses.
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
policy at `docs/compiler-team-roadmap.md:242`.

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
- **STOP (either):** a needed operation has no `Response` arm. That is a Phase 1 design error and
  routes back to language-team rather than being patched with a new arm ad hoc.

### Phase 3 — the mechanical spine `[EXP][CT]` (M)

Port stages **A, E, G2, J, L** (the five typed `mechanical` or `gate` in
`rfc_to_implementation.py:1334-1376`) as `def-shell` orchestration over the existing proved cores in
`tools/llmll-driver/`. These are the stages whose decision logic is already verified, so the port
adds the program around a proved centre rather than duplicating it.

- **Acceptance:** the five stages run end to end against the committed TFTP execution and reproduce
  `self_test()`'s pinned results (`rfc_to_implementation.py:1378`); **zero FFI declarations**; every
  ported function's authority is bounded; the proved cores are called, not reimplemented.
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
  by the proved cores the program calls.
- **STOP:** if serial wall-clock makes a campaign impractical, stop and file the concurrency
  requirement with the measurement attached. Do not add a concurrency surface mid-campaign.

### Phase 5 — conformance claim and disclosure `[SPEC]` (S)

State the driver's tier claim per driver-spec §15.4, which requires distinguishing proved from
asserted obligations. Add the FFI-seam sentence to §15.2 (the declaration bounds nothing and enforces
nothing, and it cannot reach the proved tier). Report the campaign's gap inventory: every filed gap,
its phase, and whether it was closed or deferred.

- **Acceptance:** the claim distinguishes tiers per obligation; the gap inventory is complete; no
  claim is made about the §10 token property beyond the per-step form already disclosed at
  `tools/llmll-driver/README.md:39-41`.

---

## 4. Dependency order

```
Phase 0 (DO-ACCUM-1)
   └─> Phase 1 (EFFECT-RESP)          ← the wall; nothing reads a file before this
          ├─> Phase 2a (CAP-PROC)
          └─> Phase 2b (JSON-1)
                 └─> Phase 3 (mechanical spine: A, E, G2, J, L)
                        └─> Phase 4 (agent stages + serial wave)
                               └─> Phase 5 (conformance claim)
```

Phase 0 and Phase 1 are strictly ordered because RC-2 gives `seq-commands` the meaning DO-ACCUM-1's
composition depends on, and because landing them together makes an unexpected diff unattributable.
Phases 2a and 2b are independent of each other.

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
4. **Do not report this campaign as assurance progress.** Every orchestration function is `def-shell`
   and produces no new proved obligation. The proved tier is already done and its claim is sharp
   (`tools/llmll-driver/README.md:74-76`); a larger shell dilutes it. The deliverable is a running
   program and a gap inventory.
5. **Do not let the Python driver diverge silently.** It runs real campaigns. `self_test()` is the
   oracle for the port; do not run a campaign off the LLMLL driver until that oracle passes.
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

The roadmap is doc-lead's slot; the text below is staged, not applied. Insert into the **Open work
(v0.12+ lane)** table at `docs/compiler-team-roadmap.md:48-67`.

| Item | Current Status | Next Action |
|------|---------------|-------------|
| **EFFECT-RESP** (a response channel, so a program can consume the result of its own effects) `[CT][SPEC]` | **OPEN** — design SETTLED (Rev 2, two professor rounds folded) | `wasi.fs.read : string -> Command` and `Command` is opaque, so no program can read a file and branch on it; measured, `(string-length (wasi.fs.read p))` is a type error. The effect type is a **monoid**, not an applicative: `Command` is nullary (`TypeCheck.hs:158`, `CodegenHs.hs:830`) and `seq-commands` is its `<>` (`TypeCheck.hs:161`), so the effect structure cannot depend on any value. Fix is a Mealy response channel in the `def-main` harness, not a result-returning read builtin (Rev 0's proposal, withdrawn: it performs IO during pure evaluation, abandoning `LLMLL.md:415`, and leaves effect order dependent on an evaluation order §12 never pins). Four invariants: one response per performed command, `seq-commands` yields the right component's response, `:init`'s command supplies the first response, and the terminating step's command is not performed. `Response` is **compiler-supplied**, not program-declared, because the command alphabet is sealed. `Σ_auto` unchanged; no schema bump. The command-to-response pairing is unchecked and is a **trust-channel disclosure** closed by CMD-A, **not** by R1. Design: [`design/effect-response-channel-proposal.md`](design/effect-response-channel-proposal.md) (Rev 2). |
| **DO-ACCUM-1** (a `do` block performs only its last command) `[CT]` | **OPEN** — shipped codegen defect, blast radius measured **zero** | `emitDo` (`CodegenHs.hs:741-757`) returns `(finalState, _cmdN)` and drops every earlier command, while the settled design ([`archive/do_notation/do-notation-design.md`](archive/do_notation/do-notation-design.md) §2.4) requires codegen to compose them via `seq-commands`. `checkDiscardedCommand` (`TypeCheck.hs:1857-1866`) warns instead, with an in-code note deferring a hard error to **v0.8**; shipped is 0.14.78. Witness: a two-step do-block emits `(let { (x, _cmd0) = …; (y, _cmd1) = … } in (y, _cmd1))`, so the first command never runs. Measured zero in-tree uses (`(do ` appears twice, both in walkthrough markdown), which is why it survived; it fires on the first sequencing code written. Fix conforms the emitter to the design and **deletes** the warning. Third drift on the same construct: the design mandated its non-monadic framing appear verbatim in `LLMLL.md §9` and **no such text exists** (zero hits for "not a monad", "pair-thread", "do-notation"); `do` appears only in the keyword list, the grammar, and one diagnostic note. |
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

---

## 8. Open decisions, for the user

1. **Does the driver replace the Python one, or run beside it?** The plan assumes beside, with
   `self_test()` as the oracle and no campaign run off the LLMLL driver until it passes. Replacing it
   is a separate decision and should not be made implicitly by the port finishing.
2. **Is `tools/llmll-driver/` the home, or a new tree?** The proved cores live there and the
   orchestration would join them, which makes the directory's README claim ("what is here is not the
   driver") stale on completion. Doc-lead's slot once Phase 3 lands, but the location is the user's
   call now, because it determines where the engineer writes.
