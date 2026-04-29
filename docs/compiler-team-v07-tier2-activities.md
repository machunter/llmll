# Compiler Team Activity List: v0.7 Tier-2 Items (Consultant Review)

> **Source:** Post-v0.6.3 review triage — Tier 2 engineering items  
> **Prerequisite:** v0.6.3 shipped (trust model fixes)  
> **Estimated effort:** ~6.5 hours (1 day) for v0.7 batch; TRUST-2b deferred  
> **Priority:** v0.7 backlog — these are spec-implementation gaps and trust-model refinements identified by the external review.  
> **Status:** Final consensus — professor + language team + compiler team (2026-04-26)

---

## Dependency Graph

```
BUILTIN-2 (string-char-at)         ← standalone, trivial
BUILTIN-1 (regex-match)            ← standalone, adds dependency
DO-1 (discarded commands)          ← standalone, TypeCheck change
TRUST-2a (VLProvenSMT)             ← v0.7, do AFTER v0.6.3 BUG-6
TRUST-2b (VLProvenLean+TrustedBase)← DEFERRED to Lean integration milestone
```

> [!NOTE]
> No dependencies between v0.7 items. Can be done in any order or in parallel.
> TRUST-2a is the high-value subset: distinguishes SMT proofs from generic `VLProven` in JSON output and trust reports.
> TRUST-2b is deferred because `VLProvenLean` is dead code today (Lean is mock-only) and `VLTrustedBase` has no behavioral change beyond labeling.

---

## Activity 1: BUILTIN-2 — Fix `string-char-at` negative index crash (~30 min)

**File:** `CodegenHs.hs`

**Problem:** [Line 273](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/CodegenHs.hs#L273) in `runtimePreamble`:
```haskell
string_char_at s i = if i < length s then [s !! i] else ""
```

Checks `i < length s` but not `i >= 0`. Negative indices reach Haskell's partial `!!`, which crashes at runtime (list index underflow).

| Step | Action |
|------|--------|
| 1.1 | At [CodegenHs.hs:273](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/CodegenHs.hs#L273), replace the guard: |

```diff
- "string_char_at s i = if i < length s then [s !! i] else \"\""
+ "string_char_at s i = if i >= 0 && i < length s then [s !! i] else \"\""
```

| Step | Action |
|------|--------|
| 1.2 | Add test: `(string-char-at "hello" (- 0 1))` → `""` (not crash) |
| 1.3 | Add test: `(string-char-at "hello" 5)` → `""` (existing behavior preserved) |
| 1.4 | Add test: `(string-char-at "hello" 0)` → `"h"` (existing behavior preserved) |

**Verify:** `stack build && stack test` — 0 new failures.

---

## Activity 2: BUILTIN-1 — Replace `regex-match` substring stub with POSIX ERE (~2 hr)

**File:** `CodegenHs.hs`, `package.yaml` template

**Problem:** [Line 294–295](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/CodegenHs.hs#L294-L295) in `runtimePreamble`:
```haskell
regex_match pattern subject = pattern `isInfixOf` subject
```

The spec (`LLMLL.md §13`) says `regex-match` is "Regex predicate (POSIX ERE)." The implementation is `isInfixOf` — plain substring matching. This means `(regex-match "^[0-9]+$" "abc123")` returns `True` (because `"^[0-9]+$"` is not literally a substring, but `isInfixOf` won't match it either — the behavior is simply wrong for any pattern using regex metacharacters).

| Step | Action |
|------|--------|
| 2.1 | Add `regex-tdfa` to the generated `package.yaml` dependencies. In [CodegenHs.hs](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/CodegenHs.hs) `emitPackageYaml`, add `"regex-tdfa"` to the base dependencies list |
| 2.2 | Add `import Text.Regex.TDFA ((=~))` to the generated `Lib.hs` imports. In `emitLibHs`, add to the standard import block |
| 2.3 | Replace the `regex_match` preamble entry: |

```diff
- "regex_match :: String -> String -> Bool"
- "regex_match pattern subject = pattern `isInfixOf` subject"
+ "regex_match :: String -> String -> Bool"
+ "regex_match pattern subject = subject =~ pattern :: Bool"
```

| Step | Action |
|------|--------|
| 2.4 | Remove `isInfixOf` from the `regex_match` definition (it's used for `string_contains` separately — confirm `string_contains` still uses its own `isInfixOf`) |
| 2.4a | Remove `isInfixOf` from the generated `import Data.List (isPrefixOf, isInfixOf, ...)` at [line 154](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/CodegenHs.hs#L154). After this fix, `isInfixOf` is unused in generated code — `string_contains` uses `isPrefixOf`/`tails` directly. Leaving it causes `-Wunused-imports` warnings in generated projects. |
| 2.5 | Add test: `(regex-match "^[0-9]+$" "12345")` → `True` |
| 2.6 | Add test: `(regex-match "^[0-9]+$" "abc123")` → `False` |
| 2.7 | Add test: `(regex-match "hello" "say hello world")` → `True` (backward compat with simple patterns) |
| 2.8 | Verify `string_contains` is unaffected — it has its own `isPrefixOf`/`tails` implementation at [line 263](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/CodegenHs.hs#L263) |

**Verify:** `stack build && stack test`. Then build a sample LLMLL program using `regex-match` and confirm the generated Haskell compiles and runs with `regex-tdfa`.

> [!WARNING]
> This adds a new external dependency (`regex-tdfa`) to all generated projects. Confirm it resolves under the pinned LTS resolver (`lts-22.43`). Run `stack ls dependencies | grep regex` after building a sample project.

---

## Activity 3: DO-1 — Hard error for discarded intermediate commands (~2 hr)

**File:** `TypeCheck.hs`

**Problem:** [inferDoSteps](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/TypeCheck.hs#L941-L961) processes anonymous do-steps (where `mName = Nothing`) by binding the state to a synthetic `_s_N` variable, but does not warn or error when the command component of a non-final step is discarded.

The `do` block emitter ([CodegenHs.hs:642–659](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/CodegenHs.hs#L642-L659)) destructures each step as `(state, _cmdN)` and only returns the final step's command. Intermediate `_cmdN` bindings are dead code — the IO actions are silently dropped.

The spec warns about this (`LLMLL.md §9.6`), but the external reviewer argues that a verification-oriented language should make this a hard error, not a documentation footnote.

| Step | Action |
|------|--------|
| 3.1 | In [TypeCheck.hs:955](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/TypeCheck.hs#L955), change the destructuring pattern to bind the command type (currently discarded as `_`): |

```diff
- (si, _) <- expectPairType ("do-block step " <> tshow i) t
+ (si, cmdTy) <- expectPairType ("do-block step " <> tshow i) t
```

| Step | Action |
|------|--------|
| 3.2 | After the `unify` call, add the discarded-command check: |

```haskell
  -- DO-1: warn when an intermediate anonymous step produces a Command that
  -- will be silently discarded by the codegen emitter.
  when (isNothing mName && not (null rest)) $ do
    when (cmdTy == TCustom "Command") $
      if tcStrictMode st
        then tcError $ "do-block step " <> tshow i
          <> ": intermediate command will be discarded. "
          <> "Use `seq-commands` to sequence, or name the step to suppress."
        else tcWarn $ "do-block step " <> tshow i
          <> ": intermediate command will be discarded. "
          <> "Use `seq-commands` to sequence, or name the step to suppress."
```

| Step | Action |
|------|--------|
| 3.3 | **Severity (resolved):** Warning in `check` (permissive), hard error in `build`/`verify` (strict). Leverages `tcStrictMode` from BUG-4. |
| 3.4 | **Suppression semantics (resolved):** Naming the step (`[s2 <- expr]`) suppresses the warning for backward compatibility. This is a known imprecision — the name binds *state*, not the command. A future two-binding syntax (`[s2, _ <- expr]`) is deferred to v0.8. |
| 3.5 | Add test: anonymous intermediate step returning `(S, Command)` → warning in `check`, error in `build` |
| 3.6 | Add test: named intermediate step (`[s2 <- expr]`) → no warning |
| 3.7 | Add test: anonymous **final** step → no warning (final command is used) |

**Verify:** `stack build && stack test` — 0 new failures. Warning/error appears only for anonymous non-final steps.

---

## Activity 4: TRUST-2a — Add `VLProvenSMT` constructor (~2 hr)

**Files:** `Syntax.hs`, `Main.hs`, `VerifiedCache.hs`, `TrustReport.hs`, `SpecCoverage.hs`, `AstEmit.hs`, `ProofCache.hs`

**Problem:** The current `VerificationLevel` type ([Syntax.hs:248–252](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/Syntax.hs#L248-L252)) uses `VLProven "liquid-fixpoint"` for SMT proofs — the same constructor used for generic/legacy proofs. JSON output and trust reports cannot distinguish "SMT solver verified this" from "some prover verified this."

**Scope:** Add `VLProvenSMT` only. Keep `VLProven` as the legacy fallback. No `VLProvenLean` or `VLTrustedBase` — those are deferred to TRUST-2b.

| Step | Action |
|------|---------|
| 4.1 | In [Syntax.hs:248–252](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/Syntax.hs#L248-L252), add `VLProvenSMT`: |

```haskell
data VerificationLevel
  = VLAsserted                        -- ^ Runtime assertion only; no evidence
  | VLTested   { vlSamples :: Int }   -- ^ QuickCheck passed N samples
  | VLProven   { vlProver  :: Text }  -- ^ Formally verified (generic — legacy compat)
  | VLProvenSMT  { vlSMTSolver :: Text }  -- ^ SMT solver proof (e.g. "liquid-fixpoint")
  deriving (Show, Eq, Generic)
```

| Step | Action |
|------|---------|
| 4.2 | Update `vlTier` — `VLProvenSMT` at tier 2 (same as `VLProven`): |

```haskell
vlTier VLAsserted    = 0
vlTier VLTested{}    = 1
vlTier VLProven{}    = 2  -- legacy
vlTier VLProvenSMT{} = 2
```

| Step | Action |
|------|---------|
| 4.3 | In `Main.hs` [line 1113–1114](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/Main.hs#L1113-L1114) (`doVerify`): change `VLProven "liquid-fixpoint"` → `VLProvenSMT "liquid-fixpoint"`. This is the **only emission site** that changes. |
| 4.4 | In `VerifiedCache.hs` [line 41](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/VerifiedCache.hs#L41) (`vlToJSON`): add `VLProvenSMT solver -> object ["level" .= ("proven-smt" :: Text), "prover" .= solver]` |
| 4.5 | In `VerifiedCache.hs` [line 56](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/VerifiedCache.hs#L56) (`vlFromJSON`): add `"proven-smt" -> VLProvenSMT p`. Keep `"proven"` → `VLProven` for backward compat. |
| 4.6 | In `TrustReport.hs` [line 272](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/TrustReport.hs#L272): add `vlLabel (VLProvenSMT p) = "proven-smt (" <> p <> ")"` |
| 4.7 | In `TrustReport.hs` [line 291](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/TrustReport.hs#L291): add `VLProvenSMT{}` to `isProven` |
| 4.8 | In `SpecCoverage.hs` [line 213](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/SpecCoverage.hs#L213) and [line 347](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/SpecCoverage.hs#L347): add `VLProvenSMT{}` arms to `isProven` and `vlLabel` |
| 4.9 | In `AstEmit.hs` [line 169](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/AstEmit.hs#L169): add `vlLabel (VLProvenSMT _) = "proven-smt"` |
| 4.10 | In `Contracts.hs` [line 178](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/Contracts.hs#L178): add `VLProvenSMT p | isBodyFaithful p -> Nothing` arm (same behavior as `VLProven`) |
| 4.11 | In `ProofCache.hs` [line 140](file:///Users/burcsahinoglu/Documents/llmll/compiler/src/LLMLL/ProofCache.hs#L140) (`proofToLevel`): change `VLProven (peProver pe)` → `VLProvenSMT (peProver pe)` when prover is `"liquid-fixpoint"`, keep `VLProven` for other provers |
| 4.12 | Update `Syntax.hs` module exports to include `VLProvenSMT` |
| 4.13 | Compile with `-Wincomplete-patterns` — GHC will flag any missed match sites |
| 4.14 | Write tests: JSON round-trip for `"proven-smt"`, trust report labels correctly, legacy `"proven"` sidecars still parse |

> [!IMPORTANT]
> **Backward compatibility:** Old `.verified.json` files with `"level": "proven"` must still deserialize to `VLProven`. New sidecars will use `"proven-smt"` for liquid-fixpoint results.

**Verify:** `stack build && stack test` — 0 new failures. JSON output contains `"proven-smt"` for liquid-fixpoint results. Legacy `"proven"` sidecars still parse correctly.

---

## Activity 5 (DEFERRED): TRUST-2b — Add `VLProvenLean` + `VLTrustedBase` constructors

> [!WARNING]
> **Deferred to Lean integration milestone.** This activity is documented for completeness but is NOT part of the v0.7 batch. Ship when either (a) real Lean proofs are available, or (b) `VLTrustedBase` governance is on the critical path.

**Rationale for deferral (compiler team + language team consensus):**
- `VLProvenLean` is dead code today — Lean integration is mock-only. Adding it means 20 pattern match arms that never fire.
- `VLTrustedBase` adds labeling clarity but no behavioral change (since `isBodyFaithful` returns `False` for everything). The existing `VLProven ""` via `STrust` works.
- When Lean integration ships, the pattern matches should be designed with real semantics, not guesses.

**Scope when activated:**
- Add `VLProvenLean { vlLeanModule :: Text }` and `VLTrustedBase { vlBuiltin :: Text }` to `Syntax.hs`
- All proven variants at tier 2 (flat ordering — SMT and Lean are orthogonal, not ranked)
- `VLTrustedBase` is engineer-declared only (via `STrust` AST node), not auto-emitted
- `isBodyFaithful` stays `False` for `VLProvenLean` until Lean proofs are confirmed non-mock
- `computeSummary` in `TrustReport.hs` should have a separate `trusted` counter (not lumped with `proven`)
- Estimated effort: ~3 hours
- Files: `Syntax.hs` + 9 consumer files

---

## Summary

### v0.7 Batch (ship now)

| # | ID | Description | Effort | Files |
|---|-----|-------------|--------|-------|
| 1 | **BUILTIN-2** | `string-char-at` negative index guard | 0.5 hr | `CodegenHs.hs` |
| 2 | **BUILTIN-1** | `regex-match` → POSIX ERE via `regex-tdfa` + `isInfixOf` cleanup | 2 hr | `CodegenHs.hs`, `package.yaml` |
| 3 | **DO-1** | Warn/error on discarded intermediate commands | 2 hr | `TypeCheck.hs` |
| 4 | **TRUST-2a** | Add `VLProvenSMT` constructor | 2 hr | `Syntax.hs` + 7 consumer files |

**v0.7 total: ~6.5 hours (1 day).**

### Deferred (Lean integration milestone)

| # | ID | Description | Effort | Files |
|---|-----|-------------|--------|-------|
| 5 | **TRUST-2b** | Add `VLProvenLean` + `VLTrustedBase` constructors | ~3 hr | `Syntax.hs` + 9 consumer files |
