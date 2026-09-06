---
name: norm-claim-proposal
title: "NORM-CLAIM-1: every normative sentence in LLMLL.md names what stands under it"
status: "Rev 1, SETTLED AND SHIPPED v0.20.0 on 2026-09-06 (the LLMLL port is owed; the cover is a self-cover of the reference until it lands). The user approved the five design choices (the fifth disposition informative, text pinning, the NC- prefix, the registry under scripts/norm-claims, one change for the tagging pass and the gate) and the seven routings: F1 to DUP-DEF-1 (its own row and plan), F2 as a rewording, F3 to F6 as rewordings applied in the tagging pass, F7 corrected in the triage record. Written against v0.19.1; probes ran on the 0.19.0 binary, which differs only in tests. Implementation is in flight on the same day."
date: 2026-09-06
author: language-team
consumers: [user, professor, compiler-engineer, documentation-lead]
style: "ASD-STE100 Simplified Technical English. Spec text quoted from LLMLL.md keeps the spec's register."
---

# NORM-CLAIM-1: every normative sentence in `LLMLL.md` names what stands under it

> **Status:** Rev 1, settled and shipped v0.20.0 on 2026-09-06 by user adjudication of every choice and routing in sections 4 and 9. Shipped: markers, registry, reference gate, 16-cell cover, CI step, sixteen fixtures. Owed: the LLMLL port and its TOOL-RFC record. Roadmap row `NORM-CLAIM-1` in [`docs/compiler-team-roadmap.md`](../compiler-team-roadmap.md), filed 2026-09-05 from [`critique-2026-09-05-triage.md`](critique-2026-09-05-triage.md) item A1. The gate proposed here is the fourth member of the DRIFT family and takes the unused alias `DRIFT-CT-3`.

---

## 1. Restatement

`DRIFT-CT-2` checks that a claim which has a fixture still holds. Nothing checks that a claim has a fixture. This proposal adds that check. It is `LLMLL.md` §4.6 in the reverse direction: a contract clause names the standard it came from, and a spec sentence will name the artifact that grounds it. The pilot is §0.1 and §1. The whole file comes later.

The pilot has already produced its first result. The tagging pass over 33 sentences found six that are stale or imprecise against the compiler at HEAD. Section 4 lists them. None was found by an instrument aimed at the spec before this pass, which is the roadmap row's premise, confirmed on the row's own pilot.

## 2. Context located

1. `docs/compiler-team-roadmap.md`, row `NORM-CLAIM-1`: the design sketch this proposal follows, and the four dispositions it names. Rows `DISCLOSE-ROW-1` (consumer of the `row` links), `SKIP-SILENT-1` and `FRONTMATTER-GATE-1` (the two neighbours), `TRUST-BASE-1`, `CAP-1-REAL`, `LEAN-GA`, and the v0.14.23 release line (`REC-PARTIAL-MARK`).
2. [`critique-2026-09-05-triage.md`](critique-2026-09-05-triage.md) §2 row A1 and §3 item 2: the `falsified-by` disposition and the refute-crux count that section 4 finds does not reproduce.
3. `LLMLL.md` §0.1 (one paragraph, 8 sentences) and §1 (six numbered items, 25 sentences): the pilot text. §4.6: the `:source` discipline this design reverses. §5.3.3 table row "Termination" and §5.3.5 matrix row `EApp` (recursive): the `(decreases …)` clause is shipped. §12 note 5: `let` bindings are sequential.
   These are four citations into one file; the list form is the reason the line is long.
4. [`scripts/doc-claims/README.md`](../../scripts/doc-claims/README.md): the fixture header format (`@doc`, `@cmd`, `@expect`, `@claim`), the verdict table, the "same PR" discipline, and the rule that `build` stays out of the fast path.
5. [`tools/doc-claims/docclaims.llmll`](../../tools/doc-claims/docclaims.llmll), `header-field`: a header line is found by its `@name:` marker, so an added `@norm:` line is inert to the existing gate.
6. [`tools/refute-crux/refutecrux.llmll`](../../tools/refute-crux/refutecrux.llmll): the suite list ("the twelve suites", addressed by repo-relative path) and the `EXPECTED_VERDICTS.json` contract.
7. [`tools/doc-archive/docarchive.llmll`](../../tools/doc-archive/docarchive.llmll), `governed?`: the ratchet pattern (a count asserted against a bound that may shrink and never grow without a reason). Also the fact that only `shipped-design-specs` and `dormant-explorations` are governed, so this draft carries no `archive-disposition`.
8. [`tool-ll-RESTART.md`](tool-ll-RESTART.md) item 14: a new gate is a claim, and the claim is that the gate can fail. Item 15: the encoding failure that only negative controls caught.
9. [`docs/UPDATE-PROTOCOL.md`](../UPDATE-PROTOCOL.md) D2: a proposal that introduces a guard carries a concrete positive witness.
10. [`compiler/src/LLMLL/TrustReport.hs`](../../compiler/src/LLMLL/TrustReport.hs): `assumedFactJson` (the disclosure shape the `assumed` disposition copies), `teEffectivePostLevel` and the `effective_level` headline (TRUST-PRE Position B). [`compiler/src/LLMLL/SpecCoverage.hs`](../../compiler/src/LLMLL/SpecCoverage.hs): `csSuppressionDebt`, the ratio the `assumed` ratio copies.
11. [`compiler/src/LLMLL/CodegenHs.hs`](../../compiler/src/LLMLL/CodegenHs.hs), `emitHole`: a hole lowers to a runtime `error` call. [`compiler/src/LLMLL/TypeCheck.hs`](../../compiler/src/LLMLL/TypeCheck.hs): duplicate-name checks exist for constructors and sealed types and for nothing else.
12. No prior draft exists. `docs/design/INDEX.md` and the folder have no `norm-claim` entry.

**External anchor for the vocabulary choice.** ISO/IEC Directives Part 2 separates normative from informative elements. Requirements-traceability practice (DO-178C) requires each requirement to trace to a verification artifact. The five dispositions below are that vocabulary, cut down to what this repository can check.

## 3. Design proposal

### 3.1 The unit: a sentence, defined by the gate

The gate defines "sentence" so that the population is fixed and not a matter of reading. The rule was run over the pilot text and returned 33 sentences, which matched a manual reading.

1. A line is in scope when it sits under a heading named in the registry's `scope` list and before the next heading of equal or higher level.
2. A line is prose when it is not blank, not a heading, not a table row, not an HTML comment, and not inside a fenced block.
3. A leading list marker (`1.`, `4a.`, `-`) and a leading `>` are removed.
4. Text splits at `.`, `!` or `?` followed by whitespace, when the next non-space character is uppercase, `*`, a backtick, `(` or `[`. Text inside a code span never splits. The abbreviations `e.g.`, `i.e.`, `vs.`, `cf.`, `etc.` and `et al.` never split.
5. Prose in scope conforms to this rule. If the rule splits a sentence wrongly, the author edits the prose. The rule does not grow.

### 3.2 The marker

Each sentence in scope ends with a marker immediately after its terminal punctuation, with no space: `error.[NC-011]`. The identifier is `NC-NNN`, three digits, assigned once and never reused or renumbered, on the `Q-NNN` precedent in [`theory-questions.md`](theory-questions.md). The prefix `NC` is not used by any other tag family; `N1`–`N3` name cover cells and `C1`–`C4` name DRIFT-CI-1 criteria, so a bare `N-` or `C-` would collide.

The marker is markdown text. CommonMark renders `[NC-011]` literally when no reference definition exists. The next sentence begins after a space, so the `](` and `][` link forms never occur. The marker has no backticks and no slash, so `DRIFT-DOC-4` ignores it. `spec_roundtrip.py` reads fenced blocks only.

A marker is the reverse of `:source`. `:source` puts a citation on a clause and points outward to a standard. `[NC-NNN]` puts an identifier on a sentence and points inward, through the registry, to what the repository holds.

### 3.3 The registry

One committed JSON file holds the disposition of every identifier. The proposed path is scripts/norm-claims/registry.json, beside the doc-claims fixture directory (written without backticks here because the file does not exist yet and `DRIFT-DOC-4` resolves backticked paths). The engineer may move it when `DISCLOSE-ROW-1` needs the compiler to read it. The spec carries identifiers only, so the spec grows by about eight bytes per sentence.

```json
{
  "gate": "DRIFT-CT-3",
  "spec": "LLMLL.md",
  "scope": ["## 0.1 Semantic Foundation", "## 1. Core Philosophy"],
  "assumed_bound": 6,
  "claims": [
    { "id": "NC-004", "section": "0.1",
      "text": "Verification conditions emitted by `llmll verify` are sound with respect to …",
      "disposition": "falsified-by", "target": "gate:refute-crux" },
    { "id": "NC-029", "section": "1.6",
      "text": "A module reaches no part of the system it has not imported, and the compiler rejects a `wasi.*` call whose namespace the calling module did not declare.",
      "disposition": "fixture", "target": ["scripts/doc-claims/missing-capability.llmll"] },
    { "id": "NC-031", "section": "1.6",
      "text": "The `capability` clause on an import records the intended verb and target but is **not yet enforced** (§7); the checked property is namespace declaration, not least authority.",
      "disposition": "row", "target": "CAP-1-REAL" },
    { "id": "NC-001", "section": "0.1",
      "text": "LLMLL's operational semantics are defined by the generated Haskell program.",
      "disposition": "assumed", "reason": "definitional stance; TRUST-BASE-1 names the base" },
    { "id": "NC-033", "section": "1.6",
      "text": "See §7 for the sandbox implementation and the enforcement gap.",
      "disposition": "informative" }
  ]
}
```

**`text` pins the affirmed wording.** The registry stores the sentence with its marker removed and whitespace collapsed, and the gate compares byte for byte. An edit to a tagged sentence fails the gate until the registry row is re-affirmed in the same change. This is the `.verified.json` sidecar discipline applied to prose. A hash was considered and declined for two reasons. The LLMLL port would have to hash non-ASCII text through its own byte path, which is the `TOOL-ENCODING-1` trap. And a hash hides what changed, while a text diff shows it.

### 3.4 The five dispositions

The roadmap row names four. A fifth is required, because without it the gate cannot tell an informative sentence from a forgotten one, and a gate that only checks tagged sentences repeats the `DRIFT-CT-2` direction problem. The population question is "is every sentence in scope tagged", on the census lesson that the question is never "is the list empty".

| Disposition | Target | What the gate checks | Counted in the ratio |
|---|---|---|---|
| `fixture` | one or more paths under `scripts/doc-claims/` | Each path is in the git index. Each named file carries a header line `;; @norm: NC-NNN[, NC-NNN…]` that names this identifier. `DRIFT-CT-2` keeps running the fixture; this gate only checks that it exists and claims the sentence. | denominator |
| `falsified-by` | `suite:<family>` or `gate:refute-crux` | For `suite:`, an `EXPECTED_VERDICTS.json` with that `family` value is in the git index. For `gate:`, the refute-crux step exists in `version-gate.yml` and at least one suite exists. The target names the instrument, never a count. | denominator |
| `row` | a roadmap tag | The Active Items table has a row `\| **TAG** (…) \| **OPEN…` and the status cell, column 2, begins with `OPEN`. A row whose status cell begins with `SHIPPED`, with or without residue, is closed for this purpose, and the sentence must be re-dispositioned in the same change. This is the closure re-run the roadmap row asks for. | denominator |
| `assumed` | a `reason` string | Present, and the total count is at most `assumed_bound`. Rendered in the gate's report the way `assumedFactJson` renders a fact. The bound may go down freely and up only with a reason recorded in the registry. | numerator and denominator |
| `informative` | none | The sentence asserts nothing about the language or the compiler: a cross-reference, a motivation, a restatement, or guidance to agents. | neither; reported separately |

The gate reports the norm-claim ratio: the `assumed` count divided by the sum of the `fixture`, `falsified-by`, `row` and `assumed` counts. It sits beside `csSuppressionDebt`, which is the suppressed count divided by the total.

### 3.5 What fails

Every condition below is a failure with the identifier and the reason on one line. There is no SKIP. A missing registry, an unparseable registry, an unreadable spec, or a scope heading not found is a failure, on the `SKIP-SILENT-1` and `FRONTMATTER-GATE-1` precedents: a gate that cannot decide does not say PASS.

1. A sentence in scope has no marker.
2. A marker's identifier has no registry row.
3. An identifier appears twice in the spec.
4. A registry row's identifier appears nowhere in scope (an orphan; a deleted sentence deletes its row).
5. A sentence's text differs from its row's `text`.
6. A `fixture` path is absent from the git index, or present and not naming the identifier in `@norm:`.
7. A `falsified-by` target names no suite in the git index.
8. A `row` target is absent from the Active Items table, or its status cell does not begin with `OPEN`.
9. The `assumed` count exceeds `assumed_bound`.

On success the gate prints one line, and that line is what a caller greps: `DRIFT-CT-3: 33 sentences dispositioned (fixture 14, falsified-by 3, row 3, assumed 6, informative 7); assumed ratio 0.23, bound 6`. The counts are the pilot's proposed values from section 3.7.

### 3.6 The three artifacts

The roadmap row prescribes the campaign's shape. The three paths below are written without backticks because the files do not exist yet. The reference is scripts/norm_claims_gate.py, in Python like DRIFT-DOC-4's reference was, because sentence splitting in shell is not worth writing twice. The port is tools/norm-claims/normclaims.llmll. It reads `LLMLL.md` through the path `pathlint.llmll` reads markdown today, and it parses JSON with the §13.13 builtins the archive gate already uses. The cover is scripts/norm_claims_cover.py, and it mutates a scratch copy of the spec, the registry, one fixture and one roadmap row. Section 5 names the cells. The step lands in the `spec-roundtrip` job after the doc-claims step. Both run on every push and pull request to `main`, so a row closure in a pull request re-runs the gate before merge.

The tagging pass and the gate land together. A tagged spec with no gate is unchecked, and a gate with an untagged spec fails on every sentence. The doc-lead's pass produces the markers, the registry, the `@norm:` lines and the six rewordings. The engineer's PR carries the three artifacts and the CI step. They merge as one change.

### 3.7 Pilot table

The 33 sentences of §0.1 and §1 in document order, each with its proposed disposition. "New" marks a fixture that does not exist yet. "Measured" marks a behaviour probed on 2026-09-06. The drift findings are section 4.

| ID | § | Sentence (abridged) | Disposition | Target or reason |
|---|---|---|---|---|
| NC-001 | 0.1 | operational semantics are defined by the generated Haskell program | assumed | definitional stance; `TRUST-BASE-1` names the base |
| NC-002 | 0.1 | the compiler is the reference implementation | assumed | definitional |
| NC-003 | 0.1 | there is no separate formal semantics document | informative | describes the document set |
| NC-004 | 0.1 | verification conditions are sound … modulo the `Int64` gap | falsified-by | `gate:refute-crux`; `SAFE-ARG` is its one recorded falsification |
| NC-005 | 0.1 | the verifier proves `f` satisfies `g`'s pre and assumes `g`'s post | fixture | new: single-module chain, `@cmd: verify`, `output:call-pre obligations: f` (measured) |
| NC-006 | 0.1 | assume-guarantee composition is sound when both are verified | assumed | metatheoretic; no per-instance instrument |
| NC-007 | 0.1 | recursive cycles verified by the mutual-recursion rule at partial correctness | fixture | new: two-function cycle, `output:body-faithful:` |
| NC-008 | 0.1 | termination is not discharged … the trust report does not yet flag the partiality | falsified-by after rewording | **F3**; the rewording yields two sentences: `suite:total-recursion` for the `decreases` clause, a fixture on `termination_unverified` for the mark |
| NC-009 | 1.1 | there are no variables, only constants | assumed | no mutation construct exists to reject |
| NC-010 | 1.1 | state is transformed, never mutated | informative | restates NC-009 |
| NC-011 | 1.1 | re-binding the same name in the same scope is a compile error | row | **F1**; `DUP-DEF-1` until `check` rejects it, then fixture `check-error` |
| NC-012 | 1.1 | shadowing in nested scopes is permitted; the verifier alpha-renames | fixture | new: `(let [(n (+ n 1))] n)` under a contract, `@cmd: verify`, `output:SAFE` (measured) |
| NC-013 | 1.2 | ambiguity is a first-class citizen represented by holes | informative | motivation |
| NC-014 | 1.2 | a program with holes can be type-checked but not executed | fixture after rewording | **F2**; arm 1 `check-ok` on a holed def, arm 2 `@cmd: run`, `output:hole:` |
| NC-015 | 1.2 | always prefer a typed hole over a hallucinated implementation | informative | guidance to agents |
| NC-016 | 1.3 | every expression has a type | assumed | metatheoretic |
| NC-017 | 1.3 | the type system prevents null dereferences, type mismatches, unguarded IO | fixture | new `check-error` on a type mismatch; existing `missing-capability.llmll` for unguarded IO; no null construct exists |
| NC-018 | 1.4a | logic functions declare `pre` and `post` | fixture | existing `open-aux-lib.llmll` |
| NC-019 | 1.4a | contracts are the trust interface between agents | informative | motivation |
| NC-020 | 1.4a | QF-LIA verified at compile time; outside it, runtime assertions flagged `?proof-required` | fixture after rewording | **F4**; `@cmd: verify` on a nonlinear post, `output:body-fallback:` (measured) |
| NC-021 | 1.4a | Lean 4 via Leanstral is designed but not yet shipped | row after rewording | **F5**; `LEAN-GA` |
| NC-022 | 1.4a | each clause carries a display level: verified, contract-checked, tested, asserted | fixture | new: `@cmd: verify {file} --trust-report`, `output:post: verified (liquid-fixpoint)` (measured) |
| NC-023 | 1.4b | no `verified` conclusion rests silently on an `asserted` assumption | fixture | new two-module fixture with no callee sidecar, `warn:inherits this trust gap` (measured); the roadmap's own positive witness |
| NC-024 | 1.4b | effective level is the meet of own level and all callees' levels | fixture after rewording | **F6**; `--json` trust report, `output:"effective_level"` |
| NC-025 | 1.5 | verification extends beyond isolated functions | informative | restatement |
| NC-026 | 1.5 | proves the callee's pre, assumes its post | fixture | same fixture as NC-005; one file, two `@norm` identifiers |
| NC-027 | 1.5 | body-faithful verification across call chains without inlining | fixture | same fixture as NC-005, `output:body-faithful: f`; "without inlining" is not separately checkable |
| NC-028 | 1.5 | recursive cycles at partial correctness (termination unverified) | falsified-by after rewording | **F3**; `suite:total-recursion` |
| NC-029 | 1.6 | rejects a `wasi.*` call whose namespace the module did not declare | fixture | existing `missing-capability.llmll` |
| NC-030 | 1.6 | imports are non-transitive | fixture | new two-module fixture, `check-error:requires (import wasi.io` (measured) |
| NC-031 | 1.6 | the `capability` clause is not yet enforced | row | `CAP-1-REAL` |
| NC-032 | 1.6 | every side effect is a `Command` value; the outcome returns as a `Response` | assumed | architectural invariant of codegen; NC-017's fixture witnesses one corner |
| NC-033 | 1.6 | see §7 | informative | cross-reference |

Totals: fixture 14, falsified-by 3, row 3, assumed 6, informative 7. Normative denominator 26. Assumed ratio 6/26 = 0.23. Proposed `assumed_bound`: 6. The roadmap row estimated 20 to 25 sentences; the rule finds 33 because §1's items hold three to five sentences each.

## 4. Findings from the tagging pass, each owed a routing

Every finding was measured on 2026-09-06 with the 0.19.0 binary built at 06:28 the same day; v0.19.1 changed the test suite and no compiler behaviour. Each needs a user decision before the doc-lead tags the sentence.

**F1. NC-011 is false at `check`.** A module with two `(def f …)` declarations passes `llmll check` with `OK (3 statements)`. `llmll build` then fails inside GHC with `Multiple declarations of 'f'`. `TypeCheck.hs` checks duplicate names for constructors and for sealed types and for nothing else. A `(let [(x n) (x (+ x 1))] x)` also passes, and that is correct: §12 note 5 makes `let` bindings sequential, so the second `x` is a nested shadow, not a rebinding. The spec sentence is true only at the GHC stage, and `check` is the command agents run. Recommendation: file `DUP-DEF-1` `[CT]`, `check` rejects a duplicate top-level name; NC-011 takes `row` until it ships, then `fixture` with `check-error`. The alternative is to reword the sentence to "rejected at build", which would put GHC in the doc-claims fast path for one claim.

**F2. NC-014 is not what the compiler does.** `llmll build` on a def whose body is `?f-impl` succeeds, and the generated `Lib.hs` holds `error ("hole: " ++ "f-impl")` at the hole (`emitHole`). `llmll run` refuses only because the file has no `def-main`. So a program with holes builds, and a reached hole aborts at run time. Two repairs exist. The first rewords the sentence to "a hole that is reached at run time aborts with `hole: <name>`", with a `check-ok` arm and a `run` arm. The second makes `build` refuse a holed program. Recommendation: reword. The abort is a deliberate lowering with its own comment marker. Refusing would need a survey of every workflow that builds a scaffold before its holes are filled, and this proposal did not do that survey.

**F3. NC-008 and NC-028 are stale on both clauses.** §5.3.3's table row "Termination" reads **Shipped** and §5.3.5's `EApp` row reads "total with a discharging `(decreases …)`". The sentence "Termination is not discharged (the R7 strict-descent item would upgrade partial→total)" predates that. Its second clause, "the trust report does not yet flag the partiality", predates `REC-PARTIAL-MARK` at v0.14.23, which gives every cycle member a `termination_unverified` mark. Recommendation: reword both sentences to "partial by default, total with a discharging `(decreases …)` clause; the trust report marks the partial case"; dispositions as in the table.

**F4. NC-020's flagging clause is not emitted by anything.** A `def-shell` with the post `(= result (* n n))` verifies as `body-fallback: g` and reports `post: asserted`. No output line and no report field carries `?proof-required`. That token is a hole kind an author writes (`HProofRequired`, and the legacy body-position form). Since v0.19.0 a fallback carries one of six `fallback_reason` values. Recommendation: reword "flagged with `?proof-required`" to "reported as `body-fallback` with a recorded `fallback_reason`, and enforced as runtime assertions"; disposition `fixture` on `output:body-fallback:`.

**F5. NC-021 overstates the gap.** Row `LEAN-GA` records "Demo slice shipped v0.14.8: `--leanstral` proves a faithfully-translatable nonlinear obligation", and README calls it experimental and opt-in (triage item B3, already true). Recommendation: reword to "experimental and opt-in (`--leanstral`); general Lean verification is designed and not shipped (§5.3.3)"; disposition `row: LEAN-GA`.

**F6. NC-024 contradicts TRUST-PRE Position B.** The sentence says the effective level is the meet of "its own level and all transitively reachable callees' levels". `TrustReport.hs` computes `teEffectivePostLevel` and the `effective_level` headline from post levels; a callee's pre level does not floor the caller, which is what TRUST-PRE settled. Recommendation: reword "levels" to "post levels"; disposition `fixture` on the JSON headline field.

**F7. The refute-crux count in the triage record does not reproduce.** [`critique-2026-09-05-triage.md`](critique-2026-09-05-triage.md) §3 item 2 says "13 suites and 89 cases". `refutecrux.llmll`'s suite list is commented "the twelve suites". The twelve `EXPECTED_VERDICTS.json` files in the tree hold 80 `cases` entries between them: 36 in `tools/llmll-driver`, 44 across eleven `examples/` suites. Recommendation: the doc-lead corrects the record to the gate's own enumeration. The `falsified-by` target names the gate and never a count, so the registry does not carry this class of error.

**F0, for the record.** The probe binary printed `llmll 0.19.0` while the tree is at v0.19.1. The v0.19.1 release changed `compiler/test` and the smoke fixtures. No probe in this document depends on that release.

### 4.1 Exact replacement text, held for the tagging pass

Routed on 2026-09-06 by the user's instruction to route the findings. F1 went to the compiler-engineer ([`dup-def-1-engineer-plan.md`](dup-def-1-engineer-plan.md)) and the doc-lead filed row `DUP-DEF-1`. F7 was corrected in the triage record by its author. F2 to F6 are doc-lead edits to `LLMLL.md`, and they are held, not applied: the doc-lead's input contract needs an approved proposal, and section 3.6 lands the rewordings with the markers and the gate in one change. The text below is the spec text the tagging pass applies verbatim, in the spec's register.

**F2, §1 item 2, NC-014.** Before: "A program with holes can be analyzed and type-checked but not executed until the holes are filled." After: "A program with holes can be analyzed, type-checked, and built; a hole that execution reaches aborts the program with `hole: <name>` (`emitHole`), so the program does no useful work until the holes are filled."

**F3, §0.1 last sentence, NC-008.** Before: "Termination is not discharged (the R7 strict-descent item would upgrade partial→total), and the trust report does not yet flag the partiality on the `def-shell` recursive path (§4.3)." After, two sentences: "Termination is discharged only by a `(decreases …)` clause (§4.2, §5.3.3), which upgrades the cycle to total correctness; without one the verdict is partial. The trust report marks every member of an undischarged cycle `termination_unverified` (§4.4.4)." The old sentence cites §4.3, which is the `result` keyword; the partial-correctness caveat is in §4.2.

**F3, §1 item 5 last sentence, NC-028.** Before: "Recursive cycles are verified compositionally via the mutual-recursion assume-guarantee rule at **partial** correctness (termination unverified — §4.3), not contract-only." After: "Recursive cycles are verified compositionally via the mutual-recursion assume-guarantee rule, not contract-only: at **partial** correctness by default, and at total correctness with a discharging `(decreases …)` clause (§4.2)." Same §4.3 mis-citation, same repair.

**F4, §1 item 4a, NC-020.** Before: "…contracts outside that fragment are enforced as runtime assertions and flagged with `?proof-required`." After: "…a function whose contract or body leaves that fragment is reported as `body-fallback` with a recorded `fallback_reason`, its contracts are enforced as runtime assertions, and an author may route the obligation to Lean with a `?proof-required` hole (§5.3.3)." Adjacent drift, outside the pilot: §5.3.3 item 3 makes the same claim ("Flagged with `?proof-required` holes when the predicate is detected as non-linear"), and `fallback_reason` and `body-fallback` appear nowhere in `LLMLL.md`. Both belong to the whole-file pass; the doc-lead does not widen this pass to them.

**F5, §1 item 4a, NC-021.** Before: "An interactive proof path (Lean 4 via Leanstral) is designed but not yet shipped (see §5.3.3)." After: "An interactive proof path (Lean 4 via Leanstral, `--leanstral`) ships as an experimental, opt-in demo that records `verified-lean`; the production Lean tier is designed and deferred (see §5.3.3)." This matches §5.3.3's own row: "Experimental `--leanstral` demo shipped (v0.14.8); production deferred".

**F6, §1 item 4b, NC-024.** Before: "A function's effective display level is the lattice meet of its own level and all transitively reachable callees' levels." After: "A function's effective display level is the lattice meet of its own `post` level and the `post` levels of all transitively reachable callees; a callee's `pre` level does not lower it (§4.4.4, TRUST-PRE)." Source: `TrustReport.hs`, the `teEffectiveLevel` comment ("The own pre and the transitive callees' pres are excluded").

## 5. Edge cases and degenerate inputs

Each row gives the input, the expected outcome, the channel, and the citation. The gate is a CI instrument outside the three obligation channels, like `DRIFT-CT-2`, so the channel column names the gate or the fixture verdict it delegates to.

1. **Untagged sentence (positive witness, exists today).** Input: `LLMLL.md` §1 item 4b at HEAD, no marker, no registry row. Expected: `DRIFT-CT-3 FAIL: untagged sentence in 1.4b: "Trust levels propagate through call chains: …"`. Channel: gate, failure 1. Citation: roadmap row `NORM-CLAIM-1`, "§1.4b has no fixture, no marker and no open row, so it fails today".
2. **Row closure (positive witness, constructible).** Input: registry row `NC-031` with `"target": "CAP-1-REAL"`, and a roadmap edit that sets that row's status cell to `**SHIPPED v0.20.0**`. Expected: `FAIL: NC-031 names row CAP-1-REAL, status SHIPPED; re-disposition`. Channel: gate, failure 8. Citation: roadmap row `NORM-CLAIM-1`, "it must re-run on row closure".
3. **Text edit without re-affirmation.** Input: §1.6's NC-029 gains the word "always". Expected: `FAIL: NC-029 text differs from registry`. Channel: gate, failure 5. Citation: the sidecar discipline, `LLMLL.md` §4.4.4 and the `verified_hash` field.
4. **Fixture present, claim absent.** Input: `missing-capability.llmll` exists and has no `@norm:` line. Expected: a FAIL line naming NC-029, the fixture path, and "does not name NC-029". Channel: gate, failure 6. Citation: `docclaims.llmll` `header-field`.
5. **Orphan row.** Input: a registry row `NC-034` and no marker in scope. Expected: `FAIL: NC-034 has no sentence`. Channel: gate, failure 4. This is the deletion direction of closure.
6. **Informative sentence (negative control).** Input: NC-033, "See §7 …", disposition `informative`, no target. Expected: PASS, counted in neither term of the ratio. Channel: gate. Risk 3 names the abuse path.
7. **Marker inside a fence (negative control).** Input: a fenced block in scope containing `[NC-999]`. Expected: PASS; fenced lines are not prose (rule 3.1.2). Channel: gate.
8. **Non-ASCII sentence (negative control, encoding).** Input: NC-004, which contains `—` and `§`. Expected: PASS in the reference and in the port, byte-identical `text`. Channel: gate; cover cell. Citation: `tool-ll-RESTART.md` item 15 (`TOOL-ENCODING-1`).
9. **Empty scope, missing registry, malformed JSON.** Input: `"scope": []`, or no registry file, or a registry with a trailing comma. Expected: FAIL in all three, never SKIP or PASS. Channel: gate. Citation: rows `SKIP-SILENT-1` and `FRONTMATTER-GATE-1`.
10. **Ratchet.** Input: a seventh `assumed` row with `assumed_bound` at 6. Expected: `FAIL: assumed 7 exceeds bound 6`. Raising the bound requires a `bound_reason` string in the registry. Channel: gate, failure 9. Citation: `docarchive.llmll`'s bound.
11. **A sentence that names two fixtures, and a fixture that names two sentences.** Input: NC-017 with two paths; the NC-005 fixture with `@norm: NC-005, NC-026, NC-027`. Expected: PASS both ways. Channel: gate. Citation: the `open-after-def-*` pair in the doc-claims README, one claim needing two fixtures.
12. **A `fixture` sentence whose fixture fails at `DRIFT-CT-2`.** Input: NC-011 given `fixture` with `check-error` at HEAD. Expected: `DRIFT-CT-3` passes (the fixture exists and names the ID) and `DRIFT-CT-2` fails (the compiler accepts the program). Channel: doc-claims verdict `check-error`. This is why NC-011 takes `row` in the pilot, and it shows the two gates' division of labour.

## 6. Verification mapping

This proposal introduces no proof obligation in any channel. Every check in section 3.5 is structural over committed files: the spec text, one JSON file, fixture headers, the roadmap table and the git index. The three channels of `LLMLL.md` §5.3.3 and §5.3.5 are not entered.

Where a `fixture` row delegates to `DRIFT-CT-2` and the fixture runs `verify`, the obligations discharged are the ones the fixture's program already carries: QF-LIA, auto-discharged by liquid-fixpoint, inside the §5.3.3 scope. NC-012's and NC-022's fixtures are of that kind. No fixture in the pilot needs a nonlinear obligation or a Lean escape; NC-020's fixture deliberately asks the verifier to fall back and pins the fallback line, not a proof.

## 7. Affected surface

1. `LLMLL.md` §0.1 and §1: 33 markers; six rewordings (F1 to F6). One new sentence at the end of §0.1 or in a new §0.2 stating the marker convention in two sentences, so a reader of the raw spec knows what `[NC-011]` is. Doc-lead.
2. New: scripts/norm-claims/registry.json and a README beside it in the shape of the doc-claims README. Doc-lead writes the registry; engineer writes the README with the gate.
3. The fixtures under [`scripts/doc-claims/README.md`](../../scripts/doc-claims/README.md): `@norm:` header lines on `missing-capability.llmll` and `open-aux-lib.llmll`, and eleven new fixture files (NC-005, whose file also names NC-026 and NC-027; NC-007; NC-012; NC-014 in two arms; NC-017; NC-020; NC-022; NC-023; NC-024; NC-030). The README's fixture table gains their rows.
4. `tools/doc-claims/docclaims.llmll`: no change required; `header-field` ignores lines it is not asked for. The engineer confirms with one fixture carrying `@norm:`.
5. New: the reference scripts/norm_claims_gate.py, the port tools/norm-claims/normclaims.llmll, the cover scripts/norm_claims_cover.py. Engineer.
6. `.github/workflows/version-gate.yml`, job `spec-roundtrip`: one step after the doc-claims step, building the port the way the archive and doc-claims steps do, and one cover invocation. Engineer.
7. `docs/compiler-team-roadmap.md`: `NORM-CLAIM-1` status; a new row `DUP-DEF-1` `[CT]` if F1 is routed as recommended; `DISCLOSE-ROW-1` gains its input contract (the registry's `row` rows). Doc-lead.
8. `docs/UPDATE-PROTOCOL.md`, per-change matrix: "editing a tagged sentence re-affirms its registry row in the same change; closing a row re-dispositions every sentence that names it". Doc-lead.
9. `docs/design/critique-2026-09-05-triage.md` §3 item 2: the count (F7). Doc-lead.
10. `CHANGELOG.md`: the release entry. Doc-lead.
11. No builtin, no syntax, no schema change. The freeze policy is not touched. `[NC-NNN]` is markdown, not language surface.

## 8. Risks and open questions

1. **Six stale sentences in a 33-sentence pilot.** Spec-drift. Source: section 4, measured. This blocks the tagging pass until the user routes F1 to F6. It is also the proposal's strongest evidence that the gate is worth its cost: 18% of the pilot was wrong or imprecise, and the whole file has about 2,900 lines.
2. **Every edit to a tagged sentence costs a registry touch.** Verification-ergonomics. Source: section 3.3. Bounded at 33 sentences; at whole-file scale it is the price of the instrument and the reason the pilot is a pilot. The same-change discipline is what `DRIFT-CT-2` already asks of fixtures.
3. **`informative` is an escape hatch that no check closes.** Scope. Source: section 3.4. A normative sentence marked `informative` leaves the population silently. ISO Directives have the same hole and close it by review. Mitigation: the gate reports the informative count on its success line, and the doc-lead's pass lists every informative sentence in its PR. Only matters if the count drifts upward.
4. **The sentence rule is the definition, and prose must conform.** Decidability of the population. Source: section 3.1 rule 5. A sentence with `vs.` mid-clause or a period inside parentheses may split wrongly; the fix is an edit to the prose, and the rule stays small. Complicates the whole-file pass, not the pilot, which the rule already splits correctly.
5. **The `row` check depends on the roadmap table's shape.** Spec-drift. Source: the census lesson that row text lies both ways and only the status cell is read. If the table's column layout changes, the gate fails loudly on every `row` target rather than passing quietly, which is the intended failure mode.
6. **Non-ASCII through the port's read path.** Verification-ergonomics. Source: `tool-ll-RESTART.md` item 15. The pilot text carries `—`, `§` and `→`. `pathlint.llmll` already reads these files in CI, so the path exists; the cover's cell 8 is what proves the port agrees with the reference byte for byte.
7. **NC-014's second arm puts GHC in the doc-claims step.** Scope. Source: the doc-claims README's rule that `build` stays out of the fast path. A `run` fixture compiles with GHC. `spec-roundtrip` already builds four LLMLL ports with GHC, so the cost is one more package, but the README's rule would need an explicit exception for this fixture. The alternative is to disposition the abort clause `assumed`.
8. **The refute-crux count error (F7) is the class the `falsified-by` target format prevents.** Spec-drift. A target that names a count would need re-affirmation every time a suite is added; a target that names the gate does not.

## 9. Hand-off

Not settled. Rev 0 awaits adjudication of F1 to F7 and of five design choices. The choices are: the fifth disposition `informative`; text pinning rather than a hash; the `NC-NNN` identifier; the registry under scripts/norm-claims; and landing the tagging pass and the gate as one change. When settled, the doc-lead runs the tagging pass: markers, registry, `@norm:` lines, six rewordings, and the §0.1 convention sentence. The engineer then ships the three artifacts and the CI step against it. `DISCLOSE-ROW-1` reads the registry's `row` rows afterwards.
