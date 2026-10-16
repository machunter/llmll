---
title: TRUST-LEVEL-FLOOR-1 — a trust declaration states the evidence the caller accepted
status: Rev 0, SETTLED 2026-10-15
row: TRUST-LEVEL-FLOOR-1 (not yet filed; doc-lead files the row)
review: none (the user skipped the professor step)
---

# TRUST-LEVEL-FLOOR-1 — a trust declaration states the evidence the caller accepted

**Status: Rev 0, SETTLED 2026-10-15.** The user chose the floor semantics and chose a hard error for `:level verified` on 2026-10-15. This question came up after TRUST-GAP-KEY-1 (`0a325ce`, merged `57bfc04`). That fix corrected the warning label. It did not change which declarations silence the warning.

## Restatement

`(trust f :level L)` silences the cross-module trust-gap warning for `f`. The spec does not say how `L` compares with `f`'s checked evidence level.

- **Ceiling (the compiler before this change).** `L` is the amount of trust the caller grants. The declaration silences a gap when declared ≥ actual.
- **Floor (this proposal).** `L` is the evidence level the caller accepted. The declaration silences a gap only while actual ≥ declared.

The two readings agree when the declared level equals the actual level. They disagree in every other case.

**Design-reference set.** Liquid Haskell's `assume`, Dafny's `{:axiom}` and F\*'s `admit` are unconditional. None of them records the evidence level that the author saw. LLMLL's declaration does record one, and this proposal makes the compiler check it.

## Context located

1. `compiler/src/LLMLL/TypeCheck.hs`, `emitTrustGap`: the only reader of a declaration's level. It silences when `evidenceCovers tl vl`, that is, declared ≥ actual.
2. `compiler/src/LLMLL/TypeCheck.hs`, the `tcTrusts` field: filled from `STrust` statements in `checkStatements`. No other module reads `trustLevel`. A declaration does not reach the trust report, `evidenceMeet`, the sidecar or strict-core admission.
3. `compiler/src/LLMLL/Diagnostic.hs`, `mkTrustGapWarning`: the fix-it text is `Silence with: (trust f :level <actual>)`. The hint suggests the level that the caller saw.
4. `compiler/src/LLMLL/Parser.hs`, `pTrustLevel`: accepts `verified`, `tested` and `asserted`. It rejects `contract-checked` with a named error (TRUST-CC-1).
5. `compiler/src/LLMLL/Syntax.hs`, `evidenceCovers`: the lattice order. A peer top covers everything, and everything covers `DLAsserted`. Solo-tested covers joint-tested, and joint-tested does not cover solo-tested.
6. `compiler/test/Spec.hs`, the trust-gap tests under `typeCheckWithCache`. The test "trust at asserted does NOT suppress tested-level gap" locks the ceiling direction in place. The parse test for `(trust z3.verify :level verified)` expects success.
7. `LLMLL.md §4.4.3`: the declaration "acknowledge[s] the gap". An auditor "can enumerate all `(trust ...)` declarations to see which unproven contracts it depends on". The section does not state the comparison direction.
8. `LLMLL.md §4.4.5`: "The `tested` display level can be assigned … from (a) a source-annotated `(trust f :level tested)` declaration". **Spec drift.** Item 2 shows that no code path does this. The code is correct and the spec must move: a declaration must not create evidence.
9. `docs/archive/shipped-design-specs/verification-debate-action-items.md`, "`(trust ...)` Mechanism": each declaration is a point where the author accepts responsibility, and tooling should make declarations uncomfortable.
10. `docs/design/verification-debate.md`: LLMLL is "sound modulo `(trust ...)` declarations".
11. The v0.3 CHANGELOG entry (Item 7b) introduced `STrust` without a rationale for the direction. No design document in `docs/design/INDEX.md` decides it.

## Design proposal

### Semantics

A declaration silences a gap only while the checked evidence covers the declared level.

```
  vl = the checked level of f's clause      ¬ isSolverBacked vl
  (trust f :level tl) ∈ Σ                   evidenceCovers vl tl
 ───────────────────────────────────────────────────────────────  (Gap-Silenced)
                       no trust-gap warning for f
```

In every other case the warning fires. The checked level is the level after the evidence-key checks, as TRUST-GAP-KEY-1 delivers it (`TrustReport.checkCacheEvidence`).

| Declared | Actual | Before | After |
|---|---|---|---|
| `tested` | `tested` | silent | silent |
| `tested` | `asserted` | silent | **warns** |
| `asserted` | `tested` | warns | **silent** |
| `asserted` | `asserted` | silent | silent |
| `tested` | `tested-joint` | silent | **warns** |
| `verified` | any | silent | **rejected** |

Rationale:

1. **The audit claim in §4.4.3 depends on it.** Under the ceiling reading, a declaration can state a level above the evidence, and nothing reports it.
2. **Freshness.** The evidence-key checks demote a stale `tested` record to `asserted`. Under the ceiling reading, a caller that declared `tested` never learns about the demotion.
3. **Monotone in evidence.** Under the floor reading, stronger evidence never adds a warning, and weaker evidence always adds one.
4. **`:level verified` acknowledges nothing.** A solver-backed clause never produces a gap, so the declaration can never silence one.

Exact match (silence only when declared = actual) was rejected. It warns when evidence becomes stronger, and that warning has no audit value.

### Diagnostics

**Gap with no declaration.** The existing warning is kept unchanged:

```
Function lib.f has an unproven contract (level: tested). Your module inherits this trust gap. Silence with: (trust lib.f :level tested)
```

**Gap with a declaration that no longer holds.** A new form names both levels:

```
Function lib.f has an unproven contract (level: asserted). Your (trust lib.f :level tested) declares tested, which this evidence no longer meets. Silence with: (trust lib.f :level asserted)
```

The diagnostic kind stays `trust-gap`. Both forms print `tested-joint` for `DLTestedJoint`. Before this change the warning printed `unknown` for that level, which is a label defect.

### Surface

`(trust f :level verified)` is a check-time error in both the S-expression parser and the JSON-AST parser. The message follows the TRUST-CC-1 precedent:

```
trust level 'verified' acknowledges nothing: a solver-backed clause has no trust gap (TRUST-LEVEL-FLOOR-1); declare the level the trust-gap warning reports
```

`tested` and `asserted` are unchanged. `tested-joint` gets no surface form. A caller that accepts joint-tested evidence declares `asserted`.

### Schema delta

The `STrust` JSON-AST node keeps its shape. The `level` field loses the value `verified`.

**Schema drift found while reading.** `docs/llmll-ast.schema.json` gives the trust `level` enum as `["proven", "tested", "asserted"]`. `parseTrustDecl` in `compiler/src/LLMLL/ParserJSON.hs` rejects `proven` as an unknown trust level and accepts `verified`, which the enum does not list. The schema is incorrect and must move. After this change the enum is `["tested", "asserted"]`, which matches the parser for the first time. The engineer decides whether removing an enum value needs a schema-version change; TRUST-CC-1 removed `contract-checked` from the parser as precedent.

### Spec text for doc-lead, after the engineer ships

- §4.4.3 gains: "A declaration silences the warning only while the function's checked evidence is at least the declared level. When the evidence falls below it, the warning returns and names both levels. `:level verified` is rejected."
- The §4.4.5 (a) clause is deleted. The sentence becomes: "The `tested` display level is assigned to a function's post clause by a passing `(check ...)` block under the lift rule below."
- §12 grammar: `TRUST_LEVEL` loses `verified`.
- The CHANGELOG `Unreleased` bullet "`(trust f :level tested)` is unchanged" gets rewritten.

## Edge cases and degenerate inputs

1. **Positive witness: stale tested evidence.**
   - Input: module `lib` has `(def f …)` with a post, plus a `(check …)` block that lifts `f` to `tested`. The caller declares `(trust lib.f :level tested)` and calls `lib.f`. Run `llmll test` on `lib`, and then edit `lib.f`'s body.
   - Behavior: the record's `subject_key` no longer matches, so the checked level is `asserted`. `evidenceCovers DLAsserted (DLTested 0)` is False, so the warning fires in its two-level form.
   - Channel: trust.
   - Citation: the fixture of `test_tgk1_the_trust_gap_warning_reads_the_checked_level` in `scripts/tests/test_trust_report_gate_1.py`, with the declaration added.
2. **Evidence becomes stronger.**
   - Input: declared `asserted`, actual `tested`.
   - Behavior: `evidenceCovers (DLTested _) DLAsserted` is True, so the module is silent.
   - Channel: trust. The Spec.hs test "trust at asserted does NOT suppress tested-level gap" flips.
3. **`:level verified`.**
   - Input: `(trust lib.f :level verified)`, in S-expression or JSON-AST form.
   - Behavior: the parse fails with the error above, so the module does not type-check.
   - Channel: type (check-time rejection). Citation: `pTrustLevel`; the `STrust` case of `ParserJSON.hs`.
4. **Joint-tested evidence.**
   - Input: declared `tested`, actual `tested-joint`.
   - Behavior: `evidenceCovers (DLTestedJoint _) (DLTested _)` is False, so the warning fires with the label `tested-joint` and the hint `:level asserted`.
   - Channel: trust. The spec says nothing about a `tested-joint` surface level, and that is intentional.
5. **No declaration.**
   - Behavior: unchanged. The warning fires at the actual level with the existing text.
6. **A declaration for a function that is never called, or a duplicate declaration.**
   - Behavior: unchanged. An unused declaration produces no diagnostic, and duplicates stay idempotent (§4.4.3). The spec says nothing about unused declarations, and that is intentional; it is out of scope.

## Verification mapping

No proof obligation is introduced. The change is a trust-channel decision computed at check time by one `evidenceCovers` call with its arguments swapped. Nothing reaches liquid-fixpoint or Lean, so no fragment classification applies (`LLMLL.md §5.3.3`). The trust closure, `evidenceMeet`, the sidecar and strict-core admission do not change, because none of them reads a declaration (Context item 2).

## Affected surface

- `compiler/src/LLMLL/TypeCheck.hs`, `emitTrustGap`:
  - swap to `evidenceCovers vl tl`;
  - pass the declared level to the diagnostic when a declaration exists;
  - label `DLTestedJoint` as `tested-joint`.
- `compiler/src/LLMLL/Diagnostic.hs`, `mkTrustGapWarning`: add the two-level form.
- `compiler/src/LLMLL/Parser.hs`, `pTrustLevel`: reject `verified` with the named error.
- `compiler/src/LLMLL/ParserJSON.hs`, the `STrust` case: reject `verified` with the same error.
- `docs/llmll-ast.schema.json`: the trust `level` enum becomes `["tested", "asserted"]`. This removes `proven`, which the parser already rejects (see Schema delta).
- `compiler/test/Spec.hs`:
  - flip "trust at asserted does NOT suppress tested-level gap";
  - make the `:level verified` parse test expect a rejection, in both parsers;
  - add edge cases 1 (in module form), 2, 4 and the two-level message text.
- `scripts/tests/test_trust_report_gate_1.py`: add edge case 1 end to end. The run must re-warn after the body edit.
- Doc-lead, after the engineer ships: the spec text listed under "Spec text for doc-lead"; the roadmap row TRUST-LEVEL-FLOOR-1; the CHANGELOG `Unreleased` entry.
- No addition: no new builtin, construct, FFI tier or capability.

## Risks

1. **Warnings appear on existing code.** (Scope.)
   - Code that declared a level above its evidence starts to warn. Those are the cases this change exists to report.
   - The grep at 2026-10-15 found no `(trust …)` declaration in `examples/`. `scripts/doc-claims/decl-order-independent.llmll` declares `:level asserted`, which still silences.
   - A warning does not fail a build. This complicates nothing.
2. **The `verified` rejection fails any external file that uses it.** (Scope.) The user accepted this on 2026-10-15. The error message names the replacement.
3. **The §4.4.5 (a) drift is independent of this decision.** (Spec drift.) It is incorrect under either reading. Doc-lead corrects it in the same pass.
4. **The schema enum is already wrong.** (Spec drift.) An agent that writes JSON-AST from the schema and emits `proven` gets a parse error today. The fix in this change corrects that error.
