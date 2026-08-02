# Implementation plan: WASI-RT, EFFECT-RESP Phase 1 (RC-1..RC-4), DISCARD-1

Engineer: `compiler-engineer`. Target compiler: `llmll 0.14.78` (confirmed via
`export PATH=$(cd compiler && stack path --local-install-root)/bin:$PATH; llmll version`).
No `llmll build` or `stack build` was run for this plan.

Risk ranking, highest first: **(B) EFFECT-RESP > (A) WASI-RT > (C) DISCARD-1**. The ordering is
not the implementation order. Implementation order is A, then C, then B, and the reason is in
§Plan summary.

---

## Restatement

Three roadmap items against the settled Rev 3 of `docs/design/effect-response-channel-proposal.md`:
(A) give the four `wasi.*` builtins that are declared in `builtinEnv` but absent from the codegen
preamble a runtime, closing a typecheck-clean / GHC-fails seam; (B) restructure the `def-main`
`:mode console` harness into a Mealy machine that delivers a compiler-supplied `Response` value to
each `:step` call, per invariants RC-1..RC-4; (C) promote the DO-1 intermediate-command discard
warning to an error gated on a new `:discard` step marker, with an optional `"discard"` boolean on
the `do-step` JSON-AST node.

---

## Context located

- `compiler/src/LLMLL/TypeCheck.hs:154-161`: seven `wasi.*` names in `builtinEnv`, all typed
  `TFn [...] (TCustom "Command")`.
- `compiler/src/LLMLL/CodegenHs.hs:394-409`: the preamble defines `wasi_io_stdout`,
  `wasi_io_stderr`, `wasi_http_response`, `seq_commands`. Four names have no definition.
- `compiler/src/LLMLL/CodegenHs.hs:72-84`: `classifyImport` maps any `wasi.` prefix to
  `WasiImport`, commented "stdlib preamble handles it". True for three of seven.
- `compiler/src/LLMLL/TypeCheck.hs:1427-1430`, call site `:1614`: CAP-1 capability enforcement.
  `grep 'capability' CodegenHs.hs` returns **zero** hits: capability is a typecheck-only gate.
- `compiler/src/LLMLL/CodegenHs.hs:906-968`: `emitMainBody` for `ModeConsole`, the harness to be
  restructured. `loopBody` at `:934-944` already does `output <- captureStdout cmd`.
- `compiler/src/LLMLL/TypeCheck.hs:1405-1414`: `checkStatement (SDefMain{..})`. **It does not
  check `:step` arity.** This is the single most consequential finding in this plan; see §B.2.
- `compiler/src/LLMLL/Syntax.hs:690-697`: `SDefMain` record, including a `defMainRead` field that
  no emitter reads.
- `compiler/src/LLMLL/TypeCheck.hs:1828-1866`: `inferDoSteps`, `checkDiscardedCommand`, and the
  v0.8 deferral note at `:1858-1859`.
- `compiler/src/LLMLL/Parser.hs:793-804`: `pDoExpr` / `pDoStep` / `pDoBind`.
- `compiler/src/LLMLL/Syntax.hs:236-238`: `data DoStep = DoStep (Maybe Name) Expr`, deriving
  `(Show, Eq, Generic)` only. **No derived JSON instances.**
- `compiler/src/LLMLL/AstEmit.hs:358-362` and `compiler/src/LLMLL/ParserJSON.hs:687-700`: the two
  hand-written halves of `DoStep` serialization.
- `compiler/src/LLMLL/PBT.hs:668-669`: `canonicalStep`, feeding the body hash used by
  ProofCache / VerifiedCache.
- `docs/llmll-ast.schema.json:818-829`: the `DoStep` node; `"additionalProperties": false` at
  `:822`; properties `kind` / `expr` / `name` / `state_type`.
- `compiler/src/LLMLL/ParserJSON.hs:41-47`: the schema-bump precedent chain and
  `acceptedSchemaVersions = ["0.9.0","0.8.0","0.7.0","0.6.0"]`.
- `scripts/version_gate.sh:61-83`: gates C3/C4, which tie `schemaVersion` to `ParserJSON`
  and to the `$id` URL path `/schemas/v<MAJOR>.<MINOR>/`.
- `docs/design/effect-response-channel-proposal.md` Rev 3: §DISCARD-1 (`:139-280`), §Design
  EFFECT-RESP (`:310-416`), §Affected surface (`:583-618`). Read at working-tree state.
- `docs/compiler-team-roadmap.md:50`: the EFFECT-RESP row, OPEN, design settled, not blocked.
- `scripts/doc_claims_gate.sh` + `.github/workflows/version-gate.yml:118`: DRIFT-CT-2.
  **Ran it: `DRIFT-CT-2 PASS: 14 doc-claim(s) match compiler behaviour`. Confirmed green at 14.**

Searched and found nothing: no in-flight design doc for WASI-RT specifically (the prerequisite is
described only inside the EFFECT-RESP proposal at `:36-68`); no `professor` critique of the WASI-RT
item; no existing `[CT]` roadmap row for WASI-RT (the proposal at `:64` asks for one to be created).

---

## Measurements taken for this plan

These are the numbers the plan rests on. Each was produced by running the command, not inferred.

**M1. In-tree `wasi.fs.*` / `wasi.http.post` call sites, excluding `experiments/` run copies and
`docs/design/`: three, all `wasi.fs`.**

| Site | Call |
|---|---|
| `tools/llmll-driver/shell.llmll:37` | `wasi.fs.write` |
| `tools/llmll-driver/shell.llmll:46` | `wasi.fs.read` |
| `tools/llmll-driver/crux-shell-undeclared-authority.llmll:19` | `wasi.fs.write` |

This confirms the proposal's census (2 write, 1 read) with one citation drift: the proposal says
`shell.llmll:45`, the actual line is `:46`. `wasi.http.post` and `wasi.fs.delete` have **zero**
in-tree call sites. The only other hits are `CHANGELOG.md` prose and vendored `LLMLL.md` copies
under `experiments/repair-loop/runs/`, which are inert.

**M2. The corpus is check-only. Nothing in-tree builds these programs.**
`grep -rn 'llmll build' scripts/ .github/ compiler/test/ tools/ Makefile` returns three hits, all
comments: `scripts/doc_path_lint.py:46`, `:76`, and `compiler/test/Spec.hs:13974`, the last of which
states outright that "`llmll build`'s own `stack build` self-check never ran in outDir". No CI
workflow, no shell gate, and no hspec case invokes `llmll build` on any corpus program.
`llmll check shell.llmll` returns `OK (15 statements, 1 warning)`, the warning being an unrelated
asserted-contract notice on `advancing`. **So the WASI-RT defect is latent, not a red gate.** It
blocks the driver campaign the moment anything tries to run, and it blocks EFFECT-RESP end-to-end
testing immediately, but it is not breaking CI today. This resolves the proposal's open question at
`:60-63`.

**M3. `:mode console` migration surface is twelve programs, not five.** Every `def-main` in the tree
is `:mode console`; there are no `cli` or `http` entry points in-tree.

S-expression sources (6):
`examples/proof_required_test/proof_required_test.llmll:29`,
`examples/tictactoe_sexp/tictactoe.llmll:174`,
`examples/life_sexp/main.llmll:34`,
`examples/hangman_sexp/hangman.llmll:154`,
`examples/replay-demo/replay-demo.llmll:19`,
`compiler/test/fixtures/pair_type_test/pair_type_test.llmll:6`.

JSON-AST documents (6), each carrying `"mode": "console"`:
`compiler/test/fixtures/pair_type_test/pair_type_test.ast.json:38`,
`examples/conways_life_json_verifier/life.ast.json:3243`,
`examples/hangman_json_verifier/hangman.ast.json:2194`,
`examples/tictactoe_json_verifier/tictactoe.ast.json:2222`,
`examples/life_json/main.ast.json:243`,
`examples/hangman_json/hangman.ast.json:2068`.

The proposal's risk 1 (`:621-624`) says "five in-tree programs". The correct figure is twelve
files. Four of the six pairs are the same program in two surfaces, but each file is an independent
migration edit, and the JSON ones are the ones an agent consumes.

**M4. `DoStep` is pattern-matched positionally at 28 sites across 9 modules.**
`ObligationAssembly.hs` 5 (`:272, :448, :560, :681, :835`);
`FixpointEmit.hs` 9 (`:1607, :1692, :2375, :2410, :2636, :2751, :4132, :4150, :4514`);
`TypeCheck.hs` 4 (`:1831, :1843, :2555, :2594`);
`CodegenHs.hs` 3 (`:753, :754, :756`);
`PBT.hs` 3 (`:367` via `goStep`, `:556`, `:669`);
`Parser.hs` 2 (`:799, :804`);
`ParserJSON.hs` 1 (`:697`); `TrustReport.hs` 1 (`:842`); `Spec.hs` 1 (`:13367`).
Every one is a 2-argument pattern. A third positional field breaks all 28.

**M5. `compiler/test/Spec.hs` has essentially no do-notation coverage.**
`grep -n 'do-block\|discards this intermediate\|EDo\|do-step' compiler/test/Spec.hs` returns
**one** hit, `:13367`, an `EDo [DoStep Nothing (ELit (LitInt 1))]` used incidentally inside another
test. The only artifact pinning DO-1 behaviour anywhere is the doc-claims fixture. This is the
largest gap in the existing test surface and the test plan below is sized to it.

**M6. `compiler/test/fixtures/pair_type_test/do_emit_ac.ast.json` has zero consumers.**
`grep -rn 'do_emit_ac' compiler/test/ scripts/ .github/` returns nothing. It also carries
`"schemaVersion": "0.6.0"`. Confirms the proposal's item 4b (`:578-580`), and adds that the fixture
is stale-versioned.

**M7. Test-count baseline is unmeasured and must be measured.** Literal `it "` sites:
`compiler/test/Spec.hs` 1271, `compiler/test/ModuleSpec.hs` 38, total 1309. The most recent
reported hspec example count is 1424 (2026-07-28), so hspec expands roughly 115 beyond literal
sites. Do not treat 1424 as the baseline; run `stack test` on the merge base and read the number.

---

## Plan summary

Ship three commits in the order A, C, B, on three branches off `main`.

**A first** because it is the only one of the three that is a pure addition with no breaking edge:
four preamble strings, one generated-`package.yaml` dependency, no AST change, no schema change, no
migration. It is also step zero of B, since RC-1 delivers one `Response` per performed command and
the motivating command (`wasi.fs.read`) has no runtime to perform.

**C second** because it carries the JSON-AST schema bump to 0.10.0, and doing the schema bump while
B is in flight would force a second bump or a rebase. C is mechanically large (28 pattern rewrites)
but semantically small: `emitDo` is untouched, generated Haskell is bit-identical, and the change is
confined to the accept/reject boundary.

**B last** because it is the only breaking change to running programs, because its correctness
depends on A having shipped, and because it needs a new arity check that does not exist today.

The shape of A that matters: the four preamble bodies are real IO for `fs.write` / `fs.delete`,
an effect-performing / result-discarding read for `fs.read`, and a loudly-diagnosed non-network stub
for `http.post`. B then replaces only the `fs.read` body, wiring its payload into a preamble-level
response slot the harness drains. Splitting the read this way means A does not have to anticipate
B's channel design, and B does not have to re-litigate the other three.

---

## (A) WASI-RT

### A.1 Affected surface

- `compiler/src/LLMLL/CodegenHs.hs:394-409`: four new entries in the preamble string list, placed
  immediately after `wasi_http_response` and before `seq_commands`.
- `compiler/src/LLMLL/CodegenHs.hs` preamble import block: needs `System.Directory (removeFile,
  doesFileExist)` and `Control.Exception (evaluate)` in the generated `Lib.hs` header; check the
  existing generated-module header emitter alongside `:394` and extend it.
- `compiler/src/LLMLL/CodegenHs.hs` `cgPackageYaml` emitter (field declared at `:61`): add
  `directory` to the generated project's dependency list. `directory` is a GHC boot package, so
  this adds no resolver risk.
- `compiler/src/LLMLL/CodegenHs.hs:64` `cgWarnings`: new codegen warning when the emitted program
  references `wasi.http.post`.
- `LLMLL.md §13.9`: no surface change; the builtin table already lists all seven. This is the
  compiler catching up to the spec, which is the correct direction for this drift.
- `docs/llmll-ast.schema.json`: no bump.
- `docs/compiler-team-roadmap.md`: **new row needed, tag `WASI-RT`.** Per the proposal at `:64`
  this should not hide inside EFFECT-RESP's scope. Row creation is `documentation-lead`'s edit on
  ship confirmation, not mine.

### A.2 The four bodies

Illustrative Haskell, not implementation. `Command` is `IO ()` throughout, unchanged.

```haskell
wasi_fs_write :: String -> String -> IO ()
wasi_fs_write path contents = writeFile path contents

wasi_fs_delete :: String -> IO ()
wasi_fs_delete path = do
  exists <- doesFileExist path
  when exists (removeFile path)

-- WASI-RT stage: performs the read so IO errors and permission failures surface,
-- then discards. EFFECT-RESP replaces this body (see B.4).
wasi_fs_read :: String -> IO ()
wasi_fs_read path = readFile path >>= evaluate . length >> return ()

-- No network runtime. Diagnosed at codegen AND at run time; never silently succeeds.
wasi_http_post :: String -> String -> IO ()
wasi_http_post url _body =
  hPutStrLn stderr ("wasi.http.post: no runtime in this backend (url=" ++ url ++ ")")
```

Three decisions inside that, each with its reason.

**`wasi_fs_delete` is idempotent rather than failing on a missing path.** `removeFile` on a
nonexistent path throws, and an uncaught exception inside a `Command` violates the property
`LLMLL.md:1747` states for `await` and that the language relies on generally, that logic functions
cannot crash from IO. The `doesFileExist` guard is the cheapest way to keep delete total. Note the
race: the guard is TOCTOU-unsound under concurrency. LLMLL's console harness is single-threaded
(`CodegenHs.hs:906-944` is a straight-line loop), so no witness exists in the current backend, and I
am recording the imprecision rather than paying for `removePathForcibly` semantics we cannot
currently exercise.

**`wasi_fs_read` performs and discards at the WASI-RT stage.** The proposal is right that a read
whose result is discarded is close to useless. It is not useless for three purposes that matter
before B lands: it makes the capability real (a program declaring `(capability read PATH)` and
reading an unreadable path now fails at run time, which is what a capability is for), it makes
`llmll build` succeed on `shell.llmll`, and it makes the IO error surface. `evaluate . length`
rather than a bare `readFile` because `readFile` is lazy and a discarded lazy result performs no IO
at all, which would make the stopgap a no-op and hide exactly the errors it exists to surface. This
is the one place where getting the Haskell subtly wrong yields a definition that compiles, runs, and
does nothing.

**`wasi_http_post` is a diagnosed stub, not an `error` and not a silent success.** A real
implementation needs `http-client` plus TLS in the generated project's dependency set, which is a
material dependency expansion for a builtin with zero in-tree call sites (M1). `error` would violate
the same no-crash property as above. Silent success would let a program believe it posted. The
stderr line plus a `cgWarnings` entry at codegen means the failure is visible twice, before the
program runs and while it runs. When a real call site appears, the row that adds `http-client` has a
witness to justify itself.

### A.3 Open questions answered

**Does the capability check gate anything at codegen?** No. CAP-1 lives entirely in
`TypeCheck.hs:1427-1430` with its call site at `:1614`; `grep 'capability' CodegenHs.hs` is empty.
`classifyImport` (`:72-84`) collapses every `wasi.*` import to a single `WasiImport` constructor
carrying no payload, and the preamble is a fixed string list emitted unconditionally. **Consequence
for this patch: the four new definitions are in scope in every generated `Lib.hs`, including
programs that import no `wasi.fs` capability.** That is safe, because CAP-1 rejects the call at
`check` before codegen ever runs, and generated identifiers are not user-reachable. But it means the
capability model is enforced at exactly one layer, and a codegen-only path into these names (a
future FFI re-export, a hand-edited `Lib.hs`) would bypass it. Recording as a disclosure, not
proposing to fix it here: adding capability-conditional preamble emission would make the preamble
non-constant and buy nothing against a threat model where the attacker already edits generated code.

**Does it interact with `:deterministic` replay (§10a)?** Not mechanically, and the reason is worth
naming. `capDeterministic` is parsed (`Parser.hs:516`, `ParserJSON.hs:404`), stored
(`Syntax.hs:836`), and JSON-emitted (`AstEmit.hs:433`), and it feeds the `Replayable` /
`BestEffortReplay` classification at `Syntax.hs:869-873`. It is a **declaration the compiler
records and never enforces**: no codegen path consults it. So giving `wasi.fs.read` a real body
changes no replay code. What it does change is the truth value of a claim a program can make: a
module writing `(import wasi.fs (capability read :deterministic true))` would be asserting that a
filesystem read is reproducible, which it is not, and nothing would contradict it. `shell.llmll:10`
declares `:deterministic false` on `wasi.io`, so the in-tree corpus does not exercise the bad case.
**Routing to language-team**: whether `:deterministic true` should be rejected outright on
`wasi.fs.read` / `wasi.http.post` is a spec question about what the flag asserts, and I am not
resolving it inside a preamble patch.

### A.4 Verification impact

None. No new obligations, no `Σ_auto` change, no fragment change, no VC emission touched. The four
names are already in `builtinEnv` and already verification-inert: they are not reflected by
`FixpointEmit`, so bodies mentioning them already take the existing fallback routing. Strict-verified
-core is unaffected; no function newly falls back, because no function's classification depends on
whether a builtin has a codegen definition.

### A.5 Performance budget

- GHC rebuild fan-out: `CodegenHs.hs` only. It is a leaf-ward module (imported by `Main`, not by
  `TypeCheck` / `FixpointEmit`), so recompilation is one module plus the executable link.
  Estimate under 90 seconds incremental.
- `stack test` runtime delta: under 1 second. New tests are string-shape assertions on emitted
  preamble text plus one round-trip; none invoke a solver.
- `llmll check` / `llmll verify` runtime delta: zero. Neither path runs codegen.
- Generated `Lib.hs` size delta: about 12 lines. Generated `package.yaml` gains one dependency.
- ProofCache / VerifiedCache hit rate: unaffected. Preamble text is not part of any body hash
  (`PBT.hs:645-669` canonicalizes the LLMLL AST, not emitted Haskell).

### A.6 Test plan

- `compiler/test/Spec.hs`, new describe block "codegen: wasi preamble completeness", **8 tests**:
  one per `wasi.*` builtin asserting that `cgLibHs` of a minimal module contains a top-level
  definition for the mangled name (7 tests), plus one asserting `generateHaskell` emits a
  `cgWarnings` entry when the source calls `wasi.http.post` and none when it does not.
  The 7-name test is written as a `forM_` over the `builtinEnv` `wasi.` prefix list so that
  **adding an eighth `wasi.*` builtin without a preamble definition fails the suite**. That is the
  regression that would have caught this defect four names ago.
- `compiler/test/Spec.hs`, **2 tests**: `wasi_fs_read`'s emitted body contains `evaluate`
  (pinning the strictness decision from A.2, which is the failure mode that compiles and does
  nothing), and `wasi_fs_delete`'s emitted body contains `doesFileExist` (pinning totality).
- `compiler/test/Spec.hs`, **1 test**: the emitted `package.yaml` lists `directory`.
- End-to-end: no new CLI flag. The exercising path is `llmll build` on
  `tools/llmll-driver/shell.llmll`, which per M2 nothing currently runs. **Recommend adding a
  build smoke gate**, but as a separate row: `scripts/build_smoke.sh` compiling one `wasi.fs`
  program end to end through GHC. It costs minutes of CI, which is why it is its own row and its own
  decision, and it is the only thing that would have caught this class of defect. I am naming the
  absence rather than silently adding a multi-minute CI step to an unrelated patch.
- Test-count target: measured baseline (run `stack test` on merge base) + 11.

### A.7 Rollback

Single revert. No schema pin, no AST change, no `.verified.json` migration, no `.fq` change. Worst
case unwind is one `git revert` and a rebuild. Cached `.verified.json` files in user environments
are unaffected because the change does not touch any hashed input.

---

## (B) EFFECT-RESP Phase 1, RC-1..RC-4

### B.1 Affected surface

Ordered from entry point to output.

- `compiler/src/LLMLL/TypeCheck.hs:154-161`: `Response` and its four constructors enter
  `builtinEnv` as a sealed nullary-parameter datatype. Name collision check: `grep -rn
  '"Response"\|RText\|RCode\|RNone\|RErr' compiler/src/` returns only `PBT.hs:509 HRNone`, an
  unrelated internal constructor. **Clean.**
- `compiler/src/LLMLL/TypeCheck.hs` (the type-definition environment feeding
  `checkPatternExhaustive`, called at `:1566`, defined at `:1887`): `Response` must register as a
  4-arm sum so `match` on it is exhaustiveness-checked. The proposal at `:401-404` leans on this
  explicitly: exhaustive matching is what converts an unexpected arm from a crash into a value.
  Confirm the registration path used by `Result` and reuse it.
- `compiler/src/LLMLL/TypeCheck.hs:1405-1414`: **new `:step` arity check.** See B.2.
- `compiler/src/LLMLL/CodegenHs.hs:906-968`: `emitMainBody ModeConsole`, restructured. `initBlock`
  (`:927-929`), `loopBody` (`:934-944`), `doneLines` (`:958-968`).
- `compiler/src/LLMLL/CodegenHs.hs:394-409`: preamble gains the `Response` datatype declaration,
  the response slot, and the replaced `wasi_fs_read` body (B.4).
- `compiler/src/LLMLL/TrustReport.hs`: new harness-assumption disclosure field. See B.5.
- All twelve files in M3: mechanical migration.
- `docs/llmll-ast.schema.json`: **no bump.** The `def-main` node shape is unchanged; only the
  arity of the function the `step` field names changes, which is a type-level fact the existing
  field already carries. Agreeing with the proposal at `:326-328`.
- `LLMLL.md` §9.x (new), §13.9 (RC-2 sentence): `documentation-lead`'s slot after ship.

### B.2 The finding that reorders the risk: `:step` arity is unchecked today

`checkStatement (SDefMain { defMainStep = stepE, defMainDone = doneE })` at `TypeCheck.hs:1405`
does exactly two things: `inferExpr stepE` with the result discarded at `:1407`, and a `:done?`
bool check at `:1410-1414` that emits a **warning**, not an error. The step expression is inferred
but never applied, so its arity is never constrained. A one-parameter step and a two-parameter step
typecheck identically today.

**Consequence.** Adding the `Response` parameter is a breaking change that `llmll check` will not
report. All twelve programs in M3 stay green at `check` and fail at GHC with an arity mismatch in
the generated `loop`. That is the identical check/build seam as the WASI-RT defect (proposal `:52`,
`IFACE-CONFORM` at `docs/compiler-team-roadmap.md:53`), reached a second time by a different route,
inside the same release.

**Therefore the arity check is not polish and cannot be deferred.** It is the migration's only
diagnostic, and it must land in the same commit as the harness restructure. Concretely: resolve
`stepE` to a `TFn ps r`, and for `ModeConsole` require `length ps == 3` with `ps !! 2` compatible
with `TCustom "Response"` and `r` a `TPair _ (TCustom "Command")`. Emit a structured error with
`diagKind = Just "def-main-step-arity"` naming the expected signature verbatim, in the register
`expectPairType` already uses at `:1867-1875`. Where `stepE` is an `ELambda`, the parameter list is
in hand directly. Where it is an `EVar`, resolve through the same environment `inferExpr` uses.

Bidirectional: the check must also fire when a program still has the **old** one-parameter step, and
that is the case the twelve migrations exercise. Build the witness before calling this feasible:
take `examples/replay-demo/replay-demo.llmll:19` unmodified, run `llmll check`, and require the new
`def-main-step-arity` error. If that error does not fire on an unmigrated program, the check is
dead code and the migration has no diagnostic.

### B.3 Harness restructure

Per RC-1..RC-4 (proposal `:331-361`), illustrative:

```
r0        <- perform initCmd     -- RNone when :init has no command (RC-3)
loop s r   = do
  let (s', cmd) = step s line r
  if done? s' then on-done s'    -- cmd NOT performed (RC-4)
              else perform cmd >>= \r' -> loop s' r'
```

Three notes the proposal's pseudocode leaves implicit and the emitter must get right.

**The stdin channel and the response channel are separate parameters.** The current loop reads
`line <- getLine` at `:936` and passes it as the step's second argument at `:938`. RC-1 adds a
third. The step signature is `(S, string, Response) -> (S, Command)`. Do not collapse stdin into
`RText`: that would make `:mode console`'s input indistinguishable from a `wasi.fs.read` payload and
would break every existing program's meaning rather than its arity.

**`done?` moves after the step call.** Today `doneLines` (`:958-968`) evaluates `done?` at the top
of the loop on `s`, before reading stdin. RC-4 requires it be evaluated on `s'`, a state produced by
a step that has received a response. This inverts the guard structure and eliminates the
`"      let _done = False"` placeholder at `:961`. The eof check at `:935` stays where it is.

**The terminating step's command is dropped, and that is the one place the harness constructs a
command it does not perform.** GHC will warn about the unused binding unless the emitter names it
`_cmd`. The existing emitter already uses the `_`-prefix convention for exactly this reason
(`CodegenHs.hs:754`, `emitDo`'s `_s_` / `_cmd` names, and the comment at `:734` citing
`-Wunused-binds`). Follow it.

### B.4 Where the response payload comes from

This is the question A.2 deferred. `Command` is `IO ()` and carries no result, so `perform cmd`
cannot return a payload through the type. Two mechanisms exist in the codebase; I rank them.

**Ranked first: a preamble-level response slot.** The preamble declares
`{-# NOINLINE llmll_response_slot #-} llmll_response_slot :: IORef Response`, initialized to
`RNone`. `wasi_fs_read` writes `RText contents` into it; `wasi_fs_write`, `wasi_fs_delete`,
`wasi_io_stdout`, `wasi_io_stderr` write `RNone`; a caught `IOException` in any of them writes
`RErr msg`; `wasi_http_response` writes `RCode n`. The harness's `perform` becomes
`\c -> c >> readIORef llmll_response_slot`, and RC-2's discard-left is then free: `seq_commands a b
= a >> b` already leaves `b`'s write as the last one in the slot, so `seq-commands` yields `c2`'s
response with no emitter change at all. That is a genuine argument for this mechanism over the
alternative, not a convenience: RC-2 falls out of `seq_commands`'s existing definition
(`CodegenHs.hs:405-406`) rather than needing to be implemented.

**Ranked second: stdout capture.** `loopBody` already does `output <- captureStdout cmd` at `:938`,
so `wasi_fs_read path = readFile path >>= putStr` would deliver the payload with zero new plumbing.
I rank it below the slot because it conflates two channels: `wasi.io.stdout "x"` and
`wasi.fs.read p` become indistinguishable in the response, and the program's actual console output
gets swallowed into the response value. That converts the proposal's disclosed unchecked-pairing
residue (`:393-416`, "the harness could supply the wrong arm") into something strictly worse (two
different commands are not separable in the channel at all). Do not take this path.

**Consequence to record either way.** The `IORef` slot is global mutable state in generated code.
It is safe under the current single-threaded console loop (`:906-944` is straight-line) and it is
confined to the stdlib preamble, but it does not survive concurrency, and `:mode http` would need a
per-request slot. `:mode http` does not run today (`CodegenHs.hs:980-994` emits an `error` stub), so
there is no witness, and the constraint should be written into the preamble comment so the person
who wires warp finds it there rather than in a design doc.

### B.5 The unchecked pairing, and where it surfaces in `TrustReport.hs`

The proposal (`:393-416`) requires the command-to-response pairing residue be disclosed as a
trust-channel assumption in the same category as TRUST-AXIOM. Measuring the available surface:

`TrustReport.hs:136` `trSuppressions :: [(Name, Text)]` is the only free-text channel, and it is
keyed to `SWeaknessOk` statements (`:623-626`), so it is the wrong shape: the pairing residue is not
a per-function suppression and has no `SWeaknessOk` to hang from. `trTierProfile` / `TrustSummary`
(`:218-239`, `:1254`) are integer counts. There is **no existing module-level assumption list**.

**So this needs a new field, not a reuse.** Recommend `trHarnessAssumptions :: [Text]` on the
`TrustReport` record near `:136`, populated with one fixed sentence whenever the module contains an
`SDefMain` with `defMainMode = ModeConsole`, emitted as a `harness_assumptions` JSON array. The
sentence names the specific gap: that the harness supplies a `Response` whose arm is not typed
against the command the step returned, and that the program's exhaustive `match` is what bounds the
consequence.

**Second-order finding the proposal does not name.** The trust-report JSON is versioned and has
external consumers: `TrustReport.hs:277-279` discusses "existing 1.5.0 consumers" and a label whose
reading changed under them. Adding a top-level array to that document is therefore itself a
trust-report schema change with a consumer-visible version, distinct from the JSON-AST
`schemaVersion` this proposal correctly says stays put. Locate the trust-report version constant and
bump it in the same commit. I am flagging it rather than resolving which digit moves, because the
trust-report versioning convention is not documented in the files I read.

### B.6 Dead surface found: `:read`

`defMainRead :: Maybe Expr` (`Syntax.hs:694`, commented "console/cli only") is parsed
(`Parser.hs:471`), JSON round-tripped (`AstEmit.hs:180`, `ParserJSON.hs:464`), and scanned for holes
(`HoleAnalysis.hs:224`, where it is bound as `_mRead` and discarded). **No emitter reads it.**
`emitMainBody ModeConsole` at `:906` does not bind it; neither does the `ModeCli` or `ModeHttp` arm.
It is accepted, stored, re-emitted, and ignored.

It also occupies precisely the conceptual slot EFFECT-RESP is filling: a per-turn input channel on
`def-main`. **Routing to language-team, not resolving here**: either `:read` is retired in the same
breaking change that alters `:step`'s arity (one migration instead of two), or the proposal should
say why a vestigial input channel survives alongside the new one. Retiring it is cheap right now and
expensive later.

### B.7 Verification impact

- Solver-time delta: **zero.** `def-main` is not a contracted function; `checkStatement` for
  `SDefMain` emits no VC and the harness is not reflected into `Σ_auto`. `Response` is a datatype
  whose values only ever appear in `def-shell` step bodies, and those bodies already fall back from
  body-faithful VC when they mention `Command` (`PBT.hs:360-371` `bodyMentionsCommand`).
- New obligations: **zero SMT obligations.** The RC invariants are properties of the emitted
  harness, not of the program. The only new checks are type-channel: the `:step` arity rule (B.2)
  and `Response` exhaustiveness, both discharged in `TypeCheck.hs`.
- Trust-model effect: one new disclosure field (B.5). No change to trust closure, no new
  suppressions, no evidence-freshness change.
- Fragment: unchanged, stays in QF-LIA. `Response`'s payload classes are `string` and `int`, both
  inside `Σ_auto` (int natively, string via the shipped STRLIT equality / distinctness / length
  support). The deliberate absence of `RBytes` (proposal `:388-392`) is what keeps it there:
  `bytes[n]` needs a literal type-level length and a file read's length is not statically known.
- Strict-verified-core: **no function newly falls back.** A step function that pattern-matches on
  `Response` already mentions `Command` in its return type and therefore already falls back today.
  Verify this claim on `examples/replay-demo/replay-demo.llmll` before and after, with
  `llmll verify --strict-verified-core`, rather than asserting it.

### B.8 Performance budget

- GHC rebuild fan-out: `TypeCheck.hs` is imported widely, so a change there triggers a broad
  rebuild. `TypeCheck.hs`, `CodegenHs.hs`, `TrustReport.hs` plus their dependents. Estimate 6 to 12
  minutes incremental on a warm cache, and this is the expensive one of the three items.
- `stack test` runtime delta: under 3 seconds, dominated by the twelve migrated fixtures being
  re-checked.
- `llmll check` runtime delta: the arity check adds one type resolution per `def-main`, at most one
  per module. Sub-millisecond.
- ProofCache / VerifiedCache: **no invalidation**, provided the twelve migrations only add a
  parameter to the `:step` function's signature. A signature change does alter that one function's
  hash and invalidates its cache entry. Twelve entries across the corpus. Acceptable.

### B.9 Test plan

- `compiler/test/Spec.hs`, "def-main step arity", **6 tests**: one-parameter step rejected with
  `diagKind = "def-main-step-arity"` (the migration witness from B.2); two-parameter rejected;
  three-parameter with `Response` third accepted; three-parameter with a non-`Response` third
  rejected; `ELambda` step form; `EVar` step form.
- `compiler/test/Spec.hs`, "Response exhaustiveness", **3 tests**: a `match` on `Response` missing
  `RErr` is rejected; all four arms accepted; a wildcard arm accepted.
- `compiler/test/Spec.hs`, "console harness RC invariants", **5 tests**, as emitted-text assertions
  on `emitMainHs`: RC-3, `:init` present, its command's response reaches the first `step` call;
  RC-3, `:init` absent, first response is `RNone`; RC-4, the terminating step's command is bound to
  a `_`-prefixed name and not performed; `done?` is evaluated on `s'` not `s`; the response slot is
  read after each `perform`.
- `compiler/test/Spec.hs`, "RC-2 discard-left", **1 test**: `seq_commands`'s emitted definition is
  unchanged, pinning that RC-2 is delivered by existing code rather than new code (B.4).
- Migration regression: all twelve M3 files updated, and the four `examples/*_json_verifier/`
  documents re-verified. `scripts/check-examples.sh` must stay at or above its current pass count;
  measure it before the change, since CHANGELOG records it drifting (163 and 165 passed at
  different releases, `CHANGELOG.md:124`, `:245`).
- End-to-end: `llmll build` then run on `examples/replay-demo/replay-demo.llmll` with a scripted
  stdin, asserting the event log at `<mod>.event-log.jsonl` is well-formed. This is the first
  end-to-end exercise of the harness in the suite and it depends on (A).
- Property-based: none. There is no contracted function in this change to write `check` /
  `for-all` blocks against.
- Golden regen: the six `.ast.json` documents in M3 after `:step` migration.
- Test-count target: measured baseline + 15.

### B.10 Rollback

Not a single clean revert, because the twelve migrations are source edits an agent or user may have
built on. Revertible as a pair of commits (compiler, then corpus) taken together. No schema pin to
unwind. `.verified.json` migration concern: the twelve `:step` functions' hashes change, so their
cache entries go stale in both directions; a revert re-staleness them. The existing
`downgradeStaleSidecar` path (`TrustReport.hs:517-545`) handles this correctly by demoting to
asserted with a diagnostic rather than trusting a stale record, so the failure mode is a visible
downgrade rather than a false verified. Worst-case unwind: two reverts plus a full re-verify of the
corpus, on the order of an hour.

---

## (C) DISCARD-1 / DO-ACCUM-1 as P0-marker

### C.1 Affected surface

- `compiler/src/LLMLL/Syntax.hs:236-238`: `DoStep` gains a discard field.
- 28 pattern-match sites (M4) across `ObligationAssembly.hs`, `FixpointEmit.hs`, `TypeCheck.hs`,
  `CodegenHs.hs`, `PBT.hs`, `Parser.hs`, `ParserJSON.hs`, `TrustReport.hs`, `Spec.hs`.
- `compiler/src/LLMLL/Parser.hs:798-804`: `pDoStep` / `pDoBind`.
- `compiler/src/LLMLL/ParserJSON.hs:687-700`: `parseDoStep`.
- `compiler/src/LLMLL/AstEmit.hs:358-362`: `doStepToJson`.
- `compiler/src/LLMLL/TypeCheck.hs:1828-1866`: `inferDoSteps`, `checkDiscardedCommand`, deferral
  note at `:1858-1859` removed.
- `compiler/src/LLMLL/PBT.hs:668-669`: `canonicalStep`, deliberately **not** extended. See C.5.
- `compiler/src/LLMLL/CodegenHs.hs:741-757`: `emitDo` **untouched**, per proposal `:585-586`.
- `docs/llmll-ast.schema.json:14-20, 818-829`: bump to 0.10.0, add `discard`, and see C.4 for
  the `$id` trap.
- `compiler/src/LLMLL/ParserJSON.hs:41-47`: `expectedSchemaVersion` and `acceptedSchemaVersions`.
- `scripts/doc-claims/do-notation-discard-warn.llmll`: `@expect` flip. See C.6.
- `compiler/test/fixtures/pair_type_test/do_emit_ac.ast.json`: `"discard": true` on step 0, plus
  `schemaVersion` bump. See C.7.

### C.2 Question 1: does the binding parser tolerate a trailing `:discard`?

Not today, and adding it is a one-line change with no ambiguity.

`pDoBind = brackets $ do { name <- pIdent; _ <- symbol "<-"; DoStep (Just name) <$> pExpr }`
(`Parser.hs:800-804`). `brackets` requires `]` immediately after `pExpr`, so
`[s1 <- (step-a s0) :discard]` currently fails at the `:`. The fix is
`optional (symbol ":discard")` inserted between `pExpr` and the closing bracket, inside `brackets`.

It is unambiguous for a specific reason, not by inspection: `pExpr` has already committed and
returned by the time the optional runs, and `:discard` cannot begin or continue an expression
because the lexer classifies `:`-prefixed words as keyword tokens (`Lexer.hs:300-310`, the
`TokKwDeterministic` pattern at `:304`) rather than identifiers. There is no expression grammar
production that could consume it. `try` is not needed on the optional, because a failed
`symbol ":discard"` consumes nothing.

**The surface is fine. I am not proposing an alternative.** It reads well, it attaches to the
binding position where the property actually lives, and the proposal's argument at `:147-152` that
the marker cannot attach to the command value (because a step expression is usually a call, whose
`Command` component is not syntactically reachable) is correct and forced.

**One sub-task with a real risk, flagged rather than assumed.** The anonymous form
`[_ <- (log-it s0) :discard]` requires `pIdent` to accept a bare `_`. I did not measure whether it
does. If `pIdent` rejects `_`, `pDoBind` needs `(pIdent <|> ("_" <$ symbol "_"))` and the resulting
`DoStep (Just "_") e` must not collide with the `_s_<i>` synthetic naming at `TypeCheck.hs:1838`
and `CodegenHs.hs:754`. Check `pIdent` first; if it accepts `_`, this is free, and if it does not,
it is three lines plus one test. Either way it is cheap, but it is the kind of thing that turns into
a mangled-identifier bug in codegen if it is assumed rather than checked.

### C.3 Question 2: `DoStep` breakage and the round-trip obligation

**Shape.** Recommend converting to a record rather than adding a third positional field:

```haskell
data DoStep = DoStep
  { dsName    :: Maybe Name
  , dsExpr    :: Expr
  , dsDiscard :: Bool
  } deriving (Show, Eq, Generic)
```

All 28 sites (M4) must change either way, since `DoStep _ e` is a 2-argument pattern and a third
field breaks it. Record form makes the next field free and makes the 24 sites that only want `dsExpr`
read as `DoStep{dsExpr = e}`, which does not break again. The four sites that need more are
`Parser.hs:804`, `ParserJSON.hs:697`, `TypeCheck.hs:1843`, `CodegenHs.hs:753-756`.

**JSON symmetry.** `DoStep` derives `(Show, Eq, Generic)` and nothing else (`Syntax.hs:238`); there
are no `instance ToJSON DoStep` / `FromJSON DoStep` anywhere in `compiler/src/LLMLL/`. Both halves
are hand-written: `AstEmit.hs:361-362` emits, `ParserJSON.hs:691-697` parses. The `TypeDefEntry`
precedent applies in **shape** (two hand-maintained halves that can silently diverge and break
`checkout` / `patch` for every affected program) but not in **mechanism** (that bug was a derived
instance disagreeing with a hand-written one). The risk here is a forgotten line in one of the two
functions, which is the same outcome by a different route.

**Named test obligation, and it has a specific asymmetry to pin.** A round-trip property over the
four-cell product `{dsName ∈ Nothing, Just "s1"} × {dsDiscard ∈ False, True}`, asserting
`parseDoStep (doStepToJson s) == Right s`. Plus a fifth assertion that is the one that actually
prevents the `checkout` / `patch` breakage: **`doStepToJson` must omit the `discard` key entirely
when `dsDiscard` is `False`**, not emit `"discard": false`. Without that omission, running
`checkout` on any existing unmarked program rewrites every `do-step` node in the file, producing a
gratuitous diff on a program the agent did not edit, and making `patch` conflict against documents
it should not touch. `doStepToJson` already follows exactly this convention for `name`
(`AstEmit.hs:361-362` has two clauses, one emitting `name` and one omitting it); follow it.

### C.4 Question 3: schema version, minor versus major

**0.10.0, minor. The precedent is uniform and there is no counterexample.** Every prior
additive-optional field took a minor bump, recorded in `ParserJSON.hs:41-46`:

| Change | Field added | Bump |
|---|---|---|
| LT-INV (v0.11) | (constraints) | 0.5.0 → 0.6.0 |
| DEF-RET (v0.13.x) | `return_type` on def/def-shell | 0.6.0 → 0.7.0 |
| REC-DESCENT (v0.14.24) | `decreases` on def-shell | 0.7.0 → 0.8.0 |
| SRC-CONJ-1 | `pre_clauses` / `post_clauses` | 0.8.0 → 0.9.0 |

`discard` is the same category: optional for the parser, load-relevant for legality, blocked from
riding unversioned by `"additionalProperties": false` at `:822`. Reserve 1.0.0 for a change that
removes or renames a required field or restructures a node, which this is not. Nothing about
"the field changes what an agent must emit to be accepted" distinguishes it from `decreases`, which
also changed what a producer had to emit to get a total-correctness verdict.

Mechanics: `expectedSchemaVersion = "0.10.0"` and
`acceptedSchemaVersions = ["0.10.0","0.9.0","0.8.0","0.7.0","0.6.0"]`.

**CI trap the proposal does not name.** `scripts/version_gate.sh:76-83` (gate C4) reads the
schema's `$id` and requires it to contain `/schemas/v<MAJOR>.<MINOR>/` derived from
`schemaVersion`. Bumping the `const` to `0.10.0` without editing `$id` to `/schemas/v0.10/` fails
version-gate. Gate C3 (`:61-74`) separately requires the schema `const` and
`ParserJSON.expectedSchemaVersion` to agree. Both edits go in the same commit as the field.

**What else should ride along.** Two things, and nothing else.

1. `minItems: 1` on `ExprDo.steps` (schema `:804-813`). See C.8; it is the correct home for the
   empty-`do` fix and it is free inside a bump that is happening anyway.
2. The `do_emit_ac.ast.json` `schemaVersion` (C.7).

Nothing from EFFECT-RESP rides along: (B) needs no schema change. Do not bundle a speculative field
against a future row; bundling raises the rollback cost of the bump and there is no second field
queued.

### C.5 The body hash must ignore the marker

`canonicalStep (DoStep mName e) = "(step " <> maybe "_" id mName <> " " <> canonicalExpr e <> ")"`
(`PBT.hs:669`) feeds `canonicalExpr` (`:650`), which produces the body hash used by ProofCache and
VerifiedCache.

**Recommend `canonicalStep` does not include `dsDiscard`.** The marker is erasable by the
proposal's own soundness argument (`:264-280`): erasing every `:discard` changes no generated
Haskell. Two programs differing only in the marker have identical semantics, so they should have
identical body hashes. Including it would invalidate the cached `.verified.json` for every
do-containing program the moment its author adds the annotation the compiler now demands, which is
a cache miss handed out for free on a body that did not change. Excluding it costs nothing, because
the marker's legality is a type-channel property checked on every run, not something a stale cache
could launder.

This is a decision, not an oversight to note in a comment. Write the reason at `PBT.hs:669`.

### C.6 The doc-claims fixture, and keeping the pin intact

`scripts/doc-claims/do-notation-discard-warn.llmll` pins the substring
`discards this intermediate command` via `@expect: warn:`. DRIFT-CT-2 is **green at 14 doc-claims
on v0.14.78, measured**.

The flip is `warn:` → `check-error:` on the same substring, which only works if
`checkDiscardedCommand`'s message retains that clause verbatim. It today reads
(`TypeCheck.hs:1863-1865`):

> `do-block step N: current codegen discards this intermediate command. Use \`seq-commands\` to sequence IO actions explicitly.`

**Keep the first sentence byte-identical and replace only the remedy**, so the pin survives and the
message names the new construct:

> `do-block step N: current codegen discards this intermediate command. Mark the step \`:discard\` to acknowledge, or fold the command into the final step with \`seq-commands\`.`

`[DO-DISCARD-FINAL]` needs a second, distinct message and a second fixture, since it pins a
different rule. Add `scripts/doc-claims/do-discard-on-final-step.llmll` with
`@expect: check-error:` on a substring of that message. DRIFT-CT-2 goes 14 → 15, and both fixtures
plus the gate re-run land in the same commit.

### C.7 The `do_emit_ac` fixture needs a consumer, not just a field

Per M6 it has zero consumers and carries `"schemaVersion": "0.6.0"`. Adding `"discard": true` to
step 0 without more is decorative: nothing asserts against it, so the proposal's central claim, that
generated Haskell is bit-identical, would ship untested.

Do three things: add `"discard": true` to step 0; bump the fixture's `schemaVersion` to `"0.10.0"`
(a 0.6.0 document carrying a 0.10.0 field parses fine in the compiler, since `.:?` is
version-blind, but is invalid against every published schema, and leaving it inconsistent is how
fixture metadata drifts a second time); and add a `Spec.hs` test that parses it and asserts
`emitDo`'s output equals the output for the same document with the marker removed. That test is the
bit-identical claim, and it is the reason to touch the fixture at all.

### C.8 Question 4: `inferDoSteps [] = pure TUnit`

**It can ride in this patch, but only because the schema is already being bumped. The coupling is
the schema bump, not the type rule, and that changes the answer from the one the framing implies.**

The empty `do` is **unreachable from the S-expression surface**: `pDoExpr` uses `some pDoStep`
(`Parser.hs:795`), and `some` requires at least one. It is reachable only through JSON-AST:
`ParserJSON.hs:610` does `o .: "steps" >>= mapM parseDoStep`, and `mapM` over `[]` succeeds, while
the schema's `ExprDo.steps` (`:804-813`) declares no `minItems`. So this is a JSON-AST-only
well-formedness gap, and the natural fix is a schema constraint, not a type rule.

Recommend both halves, together:

1. `"minItems": 1` on `ExprDo.steps`, riding the 0.10.0 bump at zero marginal cost.
2. Replace `pure TUnit` at `:1829` with a structured error in the register `expectPairType` already
   uses at `:1867-1875`, `diagKind = Just "do-step-type-error"`, message naming that a `do` block
   requires at least one step. This is the compiler-side enforcement for producers that skip schema
   validation, which is most of them.

`emitDo [] = "((), ())"` (`CodegenHs.hs:742`) then becomes unreachable. Leave it as a defensive
total case rather than deleting it; deleting it converts a future reachability bug from a wrong
value into a pattern-match failure at codegen.

Had the schema bump not been happening, I would route this to its own row, because a lone `minItems`
edit would force a bump of its own.

### C.9 Verification impact

- Solver-time delta: **zero.** Both new rules are type-channel, discharged in `TypeCheck.hs`; they
  never reach liquid-fixpoint. Agreeing with the proposal's mapping table at `:247-252`.
- New obligations: zero SMT. Two type-channel well-formedness rules.
- `Σ_auto`: unchanged. `do` already lands in `def-shell` by the `LLMLL.md:451` rule.
- Trust-model effect: none directly. **One imprecision inherited, named in the proposal at
  `:254-261` and confirmed here**: a discarded command is still constructed, so `primEffect` sees
  its `wasi.*` name and `joinEff` (`ObligationAssembly.hs:448`) folds that capability into the
  enclosing function's effect summary even though it never runs. B0 is a may-over-approximation by
  design so this is sound, and the proposal is right not to subtract discarded effects, because a
  summary that depends on codegen position is worse than one that over-reports. Recording, not
  fixing.
- Strict-verified-core: no change. `emitDo` untouched, bodies unchanged, hashes unchanged (C.5).

### C.10 Performance budget

- GHC rebuild fan-out: `Syntax.hs` is imported by every module, so this is a **full rebuild**, the
  widest of the three items. Estimate 10 to 20 minutes cold. Mitigation: none available and none
  needed; it is a one-time cost per build, not per compile.
- `stack test` runtime delta: under 2 seconds.
- `llmll check` runtime delta: one boolean read per do-step. Unmeasurable.
- `.fq` size delta: zero. The marker never reaches constraint emission.
- ProofCache / VerifiedCache: **zero invalidation**, by the C.5 decision. This is the payoff for
  keeping the marker out of `canonicalStep`.

### C.11 Test plan

- `compiler/test/Spec.hs`, "DISCARD-1 typing", **7 tests**: `[DO-DISCARD-OK]` marked non-final
  accepted; `[DO-DISCARD-ERR]` unmarked non-final rejected with the pinned substring;
  `[DO-DISCARD-FINAL]` marked final rejected; single-step block still legal, no marker required
  (pinning the closed decision at `do-notation-design.md:603` against silent reversal);
  three-step block with steps 0 and 1 marked accepted; three-step with only step 0 marked rejected
  at step 1; anonymous `[_ <- e :discard]` accepted.
- `compiler/test/Spec.hs`, "DoStep JSON round-trip", **5 tests**: the four-cell product from C.3
  plus the `discard`-omitted-when-`False` assertion.
- `compiler/test/Spec.hs`, "empty do", **2 tests**: JSON-AST `"steps": []` rejected with
  `do-step-type-error`; the S-expression surface still cannot express it.
- `compiler/test/Spec.hs`, "emitDo bit-identical", **1 test**: the C.7 fixture, marker present
  versus absent, identical emitted text.
- `compiler/test/Spec.hs`, "schema version", **2 tests**: a 0.10.0 document with `discard` parses;
  a 0.9.0 document without it still parses (backward compatibility, matching the
  `acceptedSchemaVersions` intent documented at `ParserJSON.hs:41-44`).
- Doc-claims: `do-notation-discard-warn.llmll` flipped, `do-discard-on-final-step.llmll` added,
  `bash scripts/doc_claims_gate.sh` re-run in the same commit. Target: **DRIFT-CT-2 14 → 15**.
- `scripts/version_gate.sh` run locally before push, for gates C3 and C4 (C.4).
- Property-based: none applicable; no contracted function is added.
- Golden regen: `do_emit_ac.ast.json` only.
- Test-count target: measured baseline + 17.

### C.12 Rollback

Single revert of the compiler commit, **plus a schema-version consideration**: any `.ast.json` an
agent emitted at 0.10.0 while the change was live becomes unreadable after the revert, because
`acceptedSchemaVersions` loses `"0.10.0"`. The blast radius is bounded by how long the change is on
`main` before a revert decision, and the failure is a clean structural version error from
`parseJSONAST` (`ParserJSON.hs:49-52`), not a silent misparse. No `.verified.json` migration, by
C.5. Worst-case unwind: one revert plus re-emission of any 0.10.0 documents.

---

## Risks and unknowns

Severity-ordered across all three items.

1. **`:step` arity is unchecked, so the EFFECT-RESP migration has no diagnostic unless one is
   built.** Classification: DX / build. Cite: `TypeCheck.hs:1405-1414`; twelve affected files at
   M3. Bite: **blocks (B) as specified.** Without the new check, twelve programs pass `llmll check`
   and die at GHC with an arity mismatch, which is the same check/build seam the WASI-RT defect
   already demonstrates. The check is cheap; omitting it is not an option, and the plan treats it as
   in-scope rather than as a follow-on.

2. **A second instance of the same check/build seam inside one release.** Classification:
   spec-drift / DX. Cite: proposal `:52`, `IFACE-CONFORM` at `docs/compiler-team-roadmap.md:53`,
   plus M2 showing nothing in-tree builds. Bite: complicates. Two independent defects of the form
   "typechecks clean, fails at GHC" reached by unrelated routes suggests the absence of a build
   smoke gate is a systemic gap rather than an oversight, and A.6 proposes the gate as its own row
   rather than smuggling minutes of CI into an unrelated patch.

3. **`Syntax.hs` change forces a full GHC rebuild.** Classification: performance / build. Cite:
   `Syntax.hs:236-238`, imported by every module. Bite: complicates only. 10 to 20 minutes cold,
   once. Sequencing C before B (which also touches widely-imported `TypeCheck.hs`) means two wide
   rebuilds instead of three.

4. **The response slot is global mutable state in generated code.** Classification: verification /
   scope. Cite: B.4; `CodegenHs.hs:906-944` is a single-threaded loop. Bite: only matters at scale,
   specifically when `:mode http` is wired. No witness exists today because the HTTP arm emits an
   `error` stub (`CodegenHs.hs:980-994`). Mitigation is a preamble comment stating the constraint
   where the next implementer will read it.

5. **The trust report has its own consumer-visible version and adding a field bumps it.**
   Classification: spec-drift. Cite: `TrustReport.hs:277-279` discussing 1.5.0 consumers; B.5. Bite:
   complicates. The proposal correctly says the JSON-AST `schemaVersion` does not move for (B), and
   does not notice that a different versioned document does.

6. **`:read` is dead surface occupying the slot EFFECT-RESP fills.** Classification: scope /
   spec-drift. Cite: `Syntax.hs:694`, `Parser.hs:471`, `AstEmit.hs:180`, `ParserJSON.hs:464`,
   `HoleAnalysis.hs:224`, and the absence of any read in `emitMainBody`. Bite: complicates. Cheap to
   retire in the breaking change already happening, expensive to retire later.

7. **`pIdent` may reject `_`, breaking the anonymous marked-step surface.** Classification: build.
   Cite: `Parser.hs:800`, proposal `:167-174`. Bite: complicates. Unmeasured; three lines and one
   test if it bites, free if it does not. Named because assuming it is how it becomes a codegen
   identifier bug.

8. **`wasi_fs_read`'s laziness.** Classification: build / correctness of the stopgap. Cite: A.2.
   `readFile` is lazy; a bare `readFile path >> return ()` performs no read and the stopgap becomes
   a silent no-op that compiles and passes every string-shape test. Bite: complicates. The
   `evaluate` is pinned by a test (A.6) precisely because the failure mode is invisible.

9. **`wasi_fs_delete` is TOCTOU-racy.** Classification: verification. Cite: A.2. Bite: only matters
   at scale, and there is no witness under the single-threaded harness. Recorded rather than paid
   for.

10. **The `directory` dependency in generated projects.** Classification: build. Cite: A.1. Bite:
    minimal; `directory` is a GHC boot package, so no resolver movement. Named because it is the
    only dependency-surface change in the plan.

---

## Findings routed back to language-team

Four things I am not resolving, with the reason each belongs upstream.

1. **`:read` (risk 6).** Whether `defMainRead` is retired in the same breaking change that alters
   `:step`'s arity is a surface decision, not an implementation one. My recommendation is retire it,
   because one migration is cheaper than two and a vestigial input channel next to a new one is a
   drift generator. But the spec has to say so.

2. **`:deterministic true` on a genuinely non-deterministic capability (A.3).** Once `wasi.fs.read`
   has a real body, a module can declare `(capability read :deterministic true)` and assert
   something false, with nothing to contradict it, because the flag is recorded and never enforced
   (`Syntax.hs:869-873`, no codegen consumer). Whether the flag should be rejected on `wasi.fs.*`
   and `wasi.http.*` is a question about what the flag asserts.

3. **The stdout-capture channel collision (B.4).** If anyone prefers stdout capture over the
   response slot on the grounds that the plumbing already exists, the cost is that `wasi.io.stdout`
   and `wasi.fs.read` become indistinguishable in the response channel and the program's console
   output is swallowed into the response value. That is a strictly larger residue than the one the
   proposal discloses at `:393-416`, and it should be rejected explicitly rather than discovered.

4. **The proposal's `:mode console` count (M3).** Risk 1 at `:621-624` says five programs; the
   measured figure is twelve files, six of them JSON-AST documents that agents consume directly. The
   migration is still mechanical, but it is more than twice the stated size and half of it is in the
   surface agents read.

---

## Documentation hand-off (held for post-ship, per DOC-CONSOLIDATE)

Three separate hand-offs, one per commit, produced at step 4 of the POST-PLAN workflow and delivered
at step 7. Sketched here only so the tags and doc surfaces are visible to the synthesizer:
`WASI-RT` (new roadmap row, `LLMLL.md §13.9` needs no change, no schema delta);
`DISCARD-1` (`LLMLL.md §9.6` `:1606` replaced, §12 grammar, schema 0.9.0 → 0.10.0 with `discard` and
`minItems`, `docs/archive/do_notation/do-notation-design.md` §2.4 marked superseded);
`EFFECT-RESP` (new `LLMLL.md` §9.x, §13.9 gains RC-2's sentence, no JSON-AST schema delta, trust-
report version delta).
