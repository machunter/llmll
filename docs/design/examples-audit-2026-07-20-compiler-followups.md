# Examples-audit compiler follow-ups (2026-07-20)

Two defects surfaced by the full `examples/` audit that are compiler/CI issues, not
example-content edits. This is an implementation **plan** (compiler-engineer track),
not a landed change. No compiler source or example files were modified producing it.

**Role routing:**
- **R1** (liquid-fixpoint crash on a return-type-less boolean helper used as an `if` guard): **compiler-engineer** — VC emission sort bug in `FixpointEmit.hs`.
- **R2** (erc20 weakness-check gate is a structural dead branch + frozen ground truth is wrong): **compiler-engineer** owns the shell-gate logic fix (`scripts/benchmark-erc20.sh`); **experiment-lead** owns the frozen `EXPECTED_RESULTS.json` ground-truth decision; **documentation-lead** owns the `WALKTHROUGH.md` claim.

---

## R1 — liquid-fixpoint crash: `and (Bool Bool) Bool` supplied Int

### Restatement
`llmll verify examples/conways_life_json_verifier/life.ast.json` hard-crashes the
solver (`crash: SMTLIB2 respSat = Error "... Sort mismatch at argument #1 for
function (declare-fun and (Bool Bool) Bool) supplied sort is Int"`). The
body-faithful VC for `neighbor-alive` binds the opaque call-result of the boolean
predicate `in-bounds?` at sort `int`, but the enclosing `if`-guard consumes it as a
bare `Bool` proposition. The two halves of the BOOL-FRAG migration (v0.14.14) are out
of sync. This is a regression: the committed sidecar
`examples/conways_life_json_verifier/life.ast.json.verified.json` still records
`next-cell`/`count-neighbors` as `verified (liquid-fixpoint)`.

### Context located
- `examples/conways_life_json_verifier/life.ast.json` — `in-bounds?` def has **no**
  return-type annotation (keys `kind/name/params/body`, no `returnType`, no `post`);
  its body is `(and (>= x 0) (and (< x width) ...))` — syntactically boolean-valued.
  It is a **body-fallback** (opaque) function per verify output
  (`body-fallback: make-world, cell-at, in-bounds?, ...`).
- `neighbor-alive` body = `(if (in-bounds? cells width x y) (cell-at ...) 0)` — the
  `in-bounds?` call is the `if` condition, and `neighbor-alive` itself returns `int`.
- Emitted `/tmp/life.ast.fq` proves the disagreement:
  - `bind 13 _bv_call_in_bounds__1 : { v : int | (v = _bv_call_in_bounds__1) }` — the
    call-result binder is **int**-sorted.
  - constraint `id 0` lhs: `(_bv_call_in_bounds__1 && ((_bv_call_cell_at_2 >= 0) && ...))`
    and constraint `id 1` lhs: `((not _bv_call_in_bounds__1)) && (result = 0)` — the
    same binder used as a bare **Bool** proposition. liquid-fixpoint elaborates `&&`
    to SMT `and (Bool Bool) Bool`, receives the Int-sorted `_bv_call_in_bounds__1`,
    and crashes.
- `compiler/src/LLMLL/FixpointEmit.hs:2981-2984` — `calleeRetSort`, the origin of the
  int binder: `_ -> maybe FQInt typeToSort mRetType`. With `in-bounds?`'s
  `mRetType = Nothing`, the sort defaults to `FQInt`. `cvResultSort = retSort`
  (`:3084`) carries it into the CallVC binder.
- `compiler/src/LLMLL/FixpointEmit.hs:1439` — BOOL-FRAG comment: "a bool param/binder
  gets FQBool via typeToSort and is reasoned about" — confirms `typeToSort TBool =
  FQBool` and that a bool-sorted binder is the intended representation for the guard.
- `compiler/src/LLMLL/FixpointEmit.hs:220` — `type ContractEnv = Map Name ([(Name,
  Type)], Contract, Maybe Type)` — the consumer at `:2967` reads only
  `(params, contract, mRetType)`; it does **not** carry the callee body.
- `compiler/src/LLMLL/FixpointEmit.hs:234-263` — `buildContractEnvWith`; the `go`
  clauses (`SDef name params mRet contract _body`, etc.) **do** bind the body (the
  trailing `_`). This is where a synthesized return type can be computed, because the
  body is in scope here and not at the `:2984` consumer.

### Plan summary
Synthesize a boolean return type for an annotation-less function whose body is
syntactically boolean-valued, at ContractEnv construction, so the call-result binder
sort (`calleeRetSort`, `:2984`) agrees with the `if`-guard consumer. Concretely: in
`buildContractEnvWith`'s `go` clauses, when `mRet == Nothing`, replace the stored
third-tuple element with `Just TBool` iff `bodyIsSyntacticallyBoolean body`; otherwise
leave `Nothing` (current behavior). `in-bounds?` then sorts `FQBool`, the binder and
its bare-Bool use agree, and the crash becomes a clean body-faithful verify —
restoring the committed sidecar's recorded outcome. This is the minimal fix that
re-syncs the two halves of the BOOL-FRAG migration; the alternative (int-coerce the
guard consumer to `(x /= 0)`) reintroduces the int-0/1 guard encoding BOOL-FRAG
deliberately retired and is rejected.

### Affected surface
- `compiler/src/LLMLL/FixpointEmit.hs:255-263` — `buildContractEnvWith` `go` clauses:
  thread each def's body through a new `synthRetType mRet body` before storing the
  tuple's `Maybe Type`. Entry point of the change.
- `compiler/src/LLMLL/FixpointEmit.hs` (new local helper, ~12-15 lines) —
  `bodyIsSyntacticallyBoolean :: Expr -> Bool`: `True` when the top constructor is a
  logical/relational op (`and`, `or`, `not`, `=`, `!=`, `<`, `<=`, `>`, `>=`), a bool
  literal, or an `if`/`match` all of whose branches are boolean-valued; `False`
  otherwise. Pure syntactic, no type environment, no solver.
- `compiler/src/LLMLL/FixpointEmit.hs:2981-2984` — **no change**; `calleeRetSort`
  already routes `Just TBool` through `typeToSort` to `FQBool`. The fix is upstream,
  in what `mRetType` holds.
- `docs/llmll-ast.schema.json` — **no** schema bump (no node-shape change; return-type
  synthesis is internal).
- `LLMLL.md` — surface form **unchanged**; no user-visible syntax or CLI change.
- `compiler/test/fixtures/` + `compiler/test/Spec.hs` — new regression fixture + test
  (see Test plan).
- `examples/conways_life_json_verifier/life.ast.json.verified.json` — regenerate after
  the fix lands (documentation/example-content follow-up, not part of the compiler
  patch); the sidecar currently over-claims until then.

### Verification impact
- **Solver-time delta:** the target program (`life.ast.fq`, 116 lines, 3 body-faithful
  fns) goes from *crash* to a normal solve; the synthesis adds one `Expr` traversal per
  annotation-less def at cenv-build time (microseconds), zero solver cost. No new
  obligations, no new constraints.
- **New obligations:** none. The change only re-sorts an existing binder.
- **Trust-model effect:** none on the trust closure; `in-bounds?` stays body-fallback
  (opaque). `neighbor-alive`/`count-neighbors`/`next-cell` return to body-faithful
  `verified` instead of crashing.
- **Verification fragment:** stays in QF-LIA; a Bool-sorted opaque call result is
  already the BOOL-FRAG representation (`:1439`). No escape to nonlinear/Lean.
- **Strict-verified-core impact:** strictly positive — three functions that currently
  crash (worse than fallback) return to body-faithful VC.

### Performance budget
- **GHC build delta:** one module recompiled (`FixpointEmit.hs`) plus its downstream
  fan-out; the helper is self-contained. No dependency-surface change.
- **Test-suite runtime delta:** +1 fixture solve (~sub-second).
- **Compiler runtime delta:** one extra `Expr` fold per annotation-less def during
  `buildContractEnvWith`; negligible against constraint generation.
- **`.fq` size delta:** none.
- **ProofCache/VerifiedCache:** the `life.ast.json` verified cache entry must be
  invalidated on the fix (its recorded verdict predates the crash); no other cached
  entry changes sort.

### Test plan
- **New Haskell test** (`compiler/test/Spec.hs`, +1): a minimal two-function program —
  an annotation-less boolean predicate `p?` with a logical body, called as the `if`
  guard of a body-faithful `int`-returning caller — asserts `verify` reaches SAFE
  (regression guard against the exact `and`-sort crash). Keeps the count rising
  (570→571 Haskell).
- **New fixture** (`compiler/test/fixtures/…`): the two-function `.llmll` (or JSON-AST)
  above, plus a golden `.fq` snapshot showing the guard binder now `{ v : bool | ... }`.
- **Discrimination test** (same file, asserts no over-fix): an annotation-less
  function with an `int`-valued body (an `if` with numeric branches, mirroring
  `neighbor-alive`) still sorts `FQInt` — synthesis must not fire on non-boolean
  bodies.
- **End-to-end:** `llmll verify examples/conways_life_json_verifier/life.ast.json`
  exits SAFE; wire this example into `scripts/refute-crux-gate.sh` only if a bad twin
  is added (separate example-content task — the gate currently has no life entry).
- **Test-count target:** 570 Haskell + 37 Python → **571 Haskell** + 37 Python.

### Rollback
Single-revert plausible (one module, one helper, no schema pin). No `.verified.json`
migration risk beyond re-verifying `life.ast.json`; user environments that cached the
old (crashing) run simply re-solve. Worst-case unwind: revert the `go`-clause change
and the fixture; behavior returns to the crash.

### Risks and unknowns
1. **Bool-bodied helper consumed arithmetically** — verification/soundness — a
   function with a boolean body used in an int context (`(+ (p? ...) 1)`, treating the
   predicate as 0/1) would, after synthesis, sort `FQBool` and mis-elaborate the
   arithmetic use. Bite: complicates. Mitigation: this is exactly the int-0/1-as-bool
   pattern BOOL-FRAG retires; scope the synthesis conservatively to fire only when
   `mRet == Nothing` **and** the callee has no contract post (`in-bounds?` qualifies),
   deferring mixed-use functions to require an explicit annotation. Construct the
   witness before widening: no current example exercises arithmetic-on-boolean-body, so
   the conservative scope is safe today.
2. **`match`-bodied predicates** — verification — `bodyIsSyntacticallyBoolean` over a
   `match` must require *every* arm boolean-valued, else a mixed-arm body could be
   mis-synthesized. Bite: only matters if such a body exists; the helper's `match`
   clause must be all-arms-boolean or return `False`.
3. **Interaction with `augmentContractPost`** (`:257`, `aug params mRet contract`) —
   spec-drift — `aug` reads `mRet`; feeding it a synthesized `Just TBool` changes the
   post-fold input. Bite: none for `in-bounds?` (no post → `aug` no-op), but the
   conservative no-post scope in risk 1 sidesteps this entirely.

### Open questions for the professor
None. The fix restores the intended BOOL-FRAG binder sort; soundness is unchanged (a
predicate's opaque result is Bool-sorted, matching its only consumer).

---

## R2 — erc20 weakness-check gate is a dead branch; frozen ground truth is wrong

### Restatement
`scripts/benchmark-erc20.sh` cannot detect a spec-weakness regression: the `SAFE`
branch always fires before the `spec weakness` branch, so the gate reports pass
regardless. This let a real drift ship: the compiler now reports **15** weaknesses
(**2 confirmed** — `total-supply`, `balance-of`) on `erc20_filled.ast.json`, while
`WALKTHROUGH.md` and the frozen `EXPECTED_RESULTS.json` both assert none.

### Context located
- `scripts/benchmark-erc20.sh:123-131` — the dead branch:
  ```
  WEAK_OUTPUT=$(... $LLMLL verify "$FILLED" --weakness-check 2>&1 || true)
  if   grep -q "No spec weaknesses detected"  → pass
  elif grep -q "SAFE"                         → pass  ("no weak functions (SAFE)")
  elif grep -q "spec weakness"                → fail   # UNREACHABLE
  ```
  `--weakness-check` first runs verify, which prints `✅ … — SAFE`; that line is always
  in `WEAK_OUTPUT` (captured with `2>&1`), so the second `elif` matches before the
  third is tested. The current run prints the 15 warnings but **not** "No spec
  weaknesses detected", so branch 1 is false, branch 2 (SAFE) is true → dead-pass.
- Observed (`llmll verify examples/erc20_token/erc20_filled.ast.json --weakness-check`):
  `⚠ 15 spec weakness(es) detected`, including two confirmed —
  `Spec weakness detected for total-supply` and `for balance-of`: their post
  `EOp ">=" [result, 0]` is satisfied by `(lambda [state] state)` (the identity, which
  is their body). The other 13 are `could not be validated … outside the checkable
  (QF-LIA) fragment` (unknown, not confirmed weak).
- `examples/erc20_token/WALKTHROUGH.md:84` and `examples/erc20_token/EXPECTED_RESULTS.json:96`
  — both assert "No weaknesses expected / `weak_functions: []`", contradicted by the
  run above.

### Plan summary
Fix the gate to test `spec weakness` before any `SAFE` signal, and stop treating
`SAFE` as evidence of no weakness (a program is SAFE **and** weak simultaneously — that
is the whole point of the check). Separately, reconcile the frozen ground truth: the
two confirmed weaknesses are real, so either record them as expected (experiment-lead
call) or strengthen the two contracts (example-content call). The gate fix is
compiler-engineer scope; the ground-truth decision is not.

### Affected surface
- `scripts/benchmark-erc20.sh:123-131` — reorder/rewrite the branch cascade:
  1. `grep -q "spec weakness"` → **fail** (report the confirmed count);
  2. else `grep -q "No spec weaknesses detected"` → pass;
  3. else unexpected → skip with the captured head.
  Remove the `SAFE`-means-no-weakness branch entirely. Optionally scope the grep to the
  output after the `Running weakness check ...` line so the verify banner cannot leak
  into the decision.
- `examples/erc20_token/EXPECTED_RESULTS.json:96` — **experiment-lead**: set
  `weak_functions` to the two confirmed (`total-supply`, `balance-of`) with the 13
  `unknown` recorded as such, OR keep `[]` if the contracts are strengthened.
- `examples/erc20_token/WALKTHROUGH.md:84` — **documentation-lead**: replace "No
  weaknesses expected" with the confirmed-2 statement (or the strengthened-contract
  statement), and reprint the stale `--spec-coverage` block (currently prints
  `Verified 0 / Asserted 6`; the committed `erc20_filled.ast.json.verified.json` yields
  `Verified 3 / Asserted 3` on a fresh clone).
- No compiler-source change; no schema change. The compiler's weakness-check is
  behaving correctly — only the shell gate and the frozen expectations are wrong.

### Verification impact
None on the solver. The gate is a CI shell script; the compiler's `--weakness-check`
output is already correct (2 confirmed / 13 unknown, no false confirmations — the 13
are honestly reported as outside QF-LIA, not asserted weak).

### Performance budget
None (shell-only).

### Test plan
- **Gate self-test:** after the reorder, `scripts/benchmark-erc20.sh` must **fail** on
  the current `erc20_filled.ast.json` until the ground truth is reconciled — that
  failing state is the proof the gate now has teeth. Add a second fixture with a
  genuinely non-trivial contract that reports zero weaknesses to prove the pass path.
- **Python harness:** if this gate is counted among the 37 Python tests, keep the count
  stable; the fix is bash, not pytest.
- **Recommended contract strengthening** (if option-b chosen): give `total-supply` /
  `balance-of` a post that is not identity-satisfiable — e.g. tie `result` to the
  queried key of the state map rather than `result >= 0`. This removes the confirmed
  weakness and lets the gate pass on merit. Concrete post shape is an example-content
  decision; the compiler already discharges map-get-valued posts (A2.2 line).

### Rollback
Single-revert of the shell branch. No state migration.

### Risks and unknowns
1. **Ground-truth decision is not the engineer's** — scope — recording the 2 confirmed
   weaknesses vs strengthening the contracts is an experiment-lead / example-content
   call. Bite: the compiler-engineer fix (the gate reorder) is independent and can land
   first; the gate will then correctly fail until the decision is made, which is the
   desired forcing function.
2. **Other benchmark gates may share the pattern** — DX — the same
   `SAFE`-shadows-`weakness` cascade may exist in sibling `scripts/benchmark-*.sh`.
   Bite: only matters if reused; grep the `scripts/` dir for the same `elif grep -q
   "SAFE"` idiom before closing.
