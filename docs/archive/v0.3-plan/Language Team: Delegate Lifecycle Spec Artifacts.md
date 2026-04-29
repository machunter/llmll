# Language Team: Delegate Lifecycle Spec Artifacts

Branch: `feature/delegate-lifecycle-spec`

The compiler team's [Item 6 plan](../../../docs/archive/analysis/v0.3%20plan/Item%206:%20%3Fdelegate%20JSON-Patch%20Lifecycle.md) assigns five spec artifacts to the language team. Two are deferred (formal inference rules, Z3 encoding). Three are actionable now and block the compiler team's implementation.

---

## Deliverables

| # | Artifact | Blocking | Timing |
|---|----------|----------|--------|
| D1 | `await` returns `Result[t, DelegationError]` — update `LLMLL.md §11.2` | Phase 1 | Now |
| D2 | Checkout/patch workflow — update `LLMLL.md §11.2` | Phase 2 | Now |
| D3 | JSON-AST schema — patch envelope + `ExprAwait` description update | Phase 3 | Now |
| D4 | Formal inference rules for checkout/patch judgments | — | Deferred |
| D5 | Z3 encoding of Lock Exclusivity (§5.3) | — | Deferred |

This plan covers D1–D3. D4 and D5 are out of scope.

---

## Proposed Changes

### D1: `await` Type Change (LLMLL.md §11.2)

#### [MODIFY] [LLMLL.md](../../../LLMLL.md)

**§11.2 "Async Delegation"** (L869–889): Rewrite to document:

1. **`await` returns `Result[t, DelegationError]`**, not bare `t`. The generated code wraps `Async.wait` in exception handling. This is a breaking change from v0.2 where `await` was a no-op returning bare `t`.

2. **Update the example** — the current `build-report` example passes the `await` result directly to `wasi.http.response`. The corrected version must include the **full function context** (professor's review §1) and `match` on `Success`/`Error`:

   ```lisp
   (def-logic build-report [state: AppState data: ReportData]
     (let [[chart-future (?delegate-async @viz-agent
                            "Render a bar chart from data"
                            -> Promise[ImageBytes])]]
       (let [[chart-result (await chart-future)]]
         (match chart-result
           (Success img) (pair state (wasi.http.response 200 img))
           (Error err)   (pair state (wasi.http.response 500 "Agent failed"))))))
   ```

3. **Add IMPORTANT alert** — document the type signature: `await : Promise[t] → Result[t, DelegationError]`.

4. **Add WARNING alert** — document the v0.2 → v0.3 breaking change for agents that used `await` without pattern matching.

5. **Update the Delegation Outcome Table** — split the `?delegate-async failure` row into two rows for success/failure, both referencing `Result`.

> [!IMPORTANT]
> The spec change must be precise enough that the compiler team's `TypeCheck.hs` change (L662–668: `TPromise t → TResult t TDelegationError`) and `CodegenHs.hs` change (L480: exception-safe `try`/`Async.wait`) are both justified by the spec text.

---

### D2: Checkout/Patch Workflow (LLMLL.md §11.2)

#### [MODIFY] [LLMLL.md](../../../LLMLL.md)

**§11.2** — add a new subsection "Hole Resolution via JSON-Patch (v0.3)" after the Delegation Outcome Table (~L889). Content:

1. **Workflow overview** — four steps: checkout → patch → re-verify → commit/reject.

2. **`llmll checkout`** — CLI command, validates RFC 6901 pointer targets a `hole-*` node, creates `.llmll-lock.json` with bearer token, 1-hour TTL, `--release` and `--status` flags.

3. **Patch envelope format** — the RFC 6902 JSON envelope with embedded token, supported ops (`replace`, `add`, `remove`, `test`), explicit `move`/`copy` deferral.

4. **Scope containment rule** — all patch ops must target descendants-or-self of the checked-out pointer.

5. **Diagnostic rebasing** — type errors from patches reference `patch-op/<index>/...` pointers.

6. **CLI command table** — `checkout`, `checkout --release`, `checkout --status`, `patch`.

7. **HTTP endpoints** — `POST /checkout`, `POST /checkout/release`, `POST /patch` governed by same auth as `POST /sketch`.

8. **NOTE alert** — `.ast.json` only; S-expression rejection message; hole-filling only in v0.3.

#### [MODIFY] [README.md](../../../README.md)

Add `checkout` and `patch` to the CLI command table (L15–25). These are new v0.3 commands.

#### [MODIFY] [getting-started.md](../../../docs/getting-started.md)

Add `§2.x checkout` and `§2.x patch` command documentation sections following the pattern of existing command docs (check, holes, test, build, verify, etc.).

---

### D3: JSON-AST Schema Updates

#### [MODIFY] [llmll-ast.schema.json](../../../docs/llmll-ast.schema.json)

1. **`ExprAwait` description** (L690–699) — update from `"Await a Promise[t]: (await promise-expr)."` to document that the expression's type is `Result[t, DelegationError]`, not bare `t`.

2. **New `PatchEnvelope` definition** — add a top-level `$def` for the patch request format:

   ```json
   "PatchEnvelope": {
     "description": "LLMLL patch request envelope. Submitted to 'llmll patch' or POST /patch.",
     "type": "object",
     "required": ["token", "patch"],
     "properties": {
       "token": { "type": "string", "description": "Checkout bearer token" },
       "patch": { "type": "array", "items": { "$ref": "#/$defs/PatchOp" } }
     }
   }
   ```

3. **New `PatchOp` definition** — RFC 6902 operations with conditional `value` requirement (professor's review §3):

   ```json
   "PatchOp": {
     "type": "object",
     "required": ["op", "path"],
     "properties": {
       "op":    { "type": "string", "enum": ["replace", "add", "remove", "test"] },
       "path":  { "type": "string", "description": "RFC 6901 JSON Pointer" },
       "value": { "description": "Required for replace/add/test. Must be absent for remove." }
     },
     "if": { "properties": { "op": { "enum": ["replace", "add", "test"] } } },
     "then": { "required": ["value"] }
   }
   ```

4. **New `CheckoutToken` definition** — the token response format:

   ```json
   "CheckoutToken": {
     "type": "object",
     "required": ["pointer", "token", "ttl"],
     "properties": {
       "pointer":   { "type": "string" },
       "hole_kind": { "type": "string" },
       "token":     { "type": "string" },
       "ttl":       { "type": "integer", "description": "Seconds remaining" }
     }
   }
   ```

> [!NOTE]
> The `PatchEnvelope`, `PatchOp`, and `CheckoutToken` definitions are not part of the AST schema proper (they don't appear in the `Statement`/`Expr` oneOf). They're documented in the same file as companion definitions for agent tooling.

---

## Files Modified

| File | Change |
|------|--------|
| [LLMLL.md](../../../LLMLL.md) | §11.2: `await` return type + checkout/patch workflow |
| [CHANGELOG.md](../../../CHANGELOG.md) | v0.3 breaking change entry for `await` return type (professor's review §5) |
| [README.md](../../../README.md) | CLI command table: add `checkout`, `patch` |
| [getting-started.md](../../../docs/getting-started.md) | New command docs for `checkout` and `patch` |
| [llmll-ast.schema.json](../../../docs/llmll-ast.schema.json) | `ExprAwait` description + `PatchEnvelope`/`PatchOp`/`CheckoutToken` defs |

No new files. No compiler source changes — those belong to the compiler team's branch.

---

## Open Questions

> [!IMPORTANT]
> **Schema version bump?** The JSON-AST schema is currently `"const": "0.2.0"`. Adding `PatchEnvelope`/`PatchOp` definitions does not change the AST node shapes, so no version bump is needed. However, the `ExprAwait` description change (documenting `Result[t, DelegationError]` return type) is a semantic change. Should we bump to `0.3.0` now, or wait until the compiler team's Phase 1 lands and actually changes `TypeCheck.hs`?
>
> **Recommendation:** Do not bump yet. The schema version gates the *parser* — it controls which JSON-AST structures are accepted. The `await` return type is a *type checker* concern, not a parser concern. The schema version should bump when/if we add new AST node kinds (e.g., if checkout/patch introduce new statement kinds). Coordinate the bump with the compiler team's `ParserJSON.hs` changes in Phase 3.

---

## Verification Plan

### Automated

- `stack build` — no compiler source changes, so this is just a sanity check that we haven't broken anything.
- `stack test` — 69/69 tests must still pass. Our changes are documentation-only.

### Manual

- Verify `LLMLL.md` renders correctly (all alerts, code blocks, tables).
- Verify `llmll-ast.schema.json` is valid JSON after edits.
- Cross-reference every claim in the spec text against the compiler team's plan to ensure consistency.
