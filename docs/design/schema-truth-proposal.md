---
name: schema-truth-proposal
title: "SCHEMA-OWN-1 / SCHEMA-VERSION-1 / SCHEMA-VALID-1 / SCHEMA-DESC-1: the AST schema's claims have no owner and no reader"
status: "Rev 0, ADJUDICATED 2026-09-14: parts 1 to 3 ACCEPTED (the `schemaVersion` enum, `kind` dispatch on the unions, and the gate over emitted documents), part 4 DEFERRED (pinning the 28 normative `description` strings), on the reading that part 4's value depends on part 3 existing. One prerequisite settled with it: `version_gate.sh` C3 stops asserting `schema.const == ParserJSON.expectedSchemaVersion` and asserts instead that `expectedSchemaVersion` is a MEMBER of the enum, which keeps one assertion and needs no new schema field. Roadmap row `SCHEMA-TRUTH-1` carries PLAN for parts 1 to 3. Two clauses later in this field are superseded by that: part A (ownership) SHIPPED at `e740caf`, and the row is filed rather than proposed. Four ships in one subject, sequenced, and the sequence came out of measurement rather than argument. The subject: docs/llmll-ast.schema.json states 153 prose claims and one machine-checkable structure, and nothing in the repository reads either. Measured at v0.23.6 over the 96 git-tracked .ast.json documents: ZERO validate against the published schema. 77 of them fail on the schemaVersion const alone, which contradicts both its own description string and the reader's acceptedSchemaVersions list, so the const must be repaired BEFORE any gate is wired or the gate reports 77 false failures. Six tracked documents carry a version the shipped compiler refuses to read at all. Three scaffold templates and two frozen ERC-20 benchmark documents fail on root keys. Validation cost is a real constraint and its cause is named: the statement and expression unions are undiscriminated oneOf, so a validator explores every branch. Part A (ownership) is doc-track and ready now. Parts B, C and D are code-track and sequenced B then C then D. Roadmap rows: proposed, none filed yet."
date: 2026-09-13
author: language-team
consumers: [compiler-engineer, documentation-lead, professor, user]
---

# The AST schema's claims have no owner and no reader

**One line.** `docs/llmll-ast.schema.json` holds 153 prose claims about compiler
behaviour and one machine-checkable document shape. Nothing reads either half,
and zero of the 96 tracked documents validate against it.

## 1. Summary

The subject arrived through `MODE-HTTP-1`, whose defect (iii) is that the
compiler emits documents its own schema rejects, and through the two `DefMain`
descriptions that restated rules `CONSOLE-INIT-1` and `EFFECT-RESP` had changed.
Both survived because nobody owns the file and no gate reads it.

Four ships, in this order. The order is forced: part C reports 77 false failures
if part B does not land first.

| Tag | What it settles | Track | Sequence |
|---|---|---|---|
| `SCHEMA-OWN-1` | The file has a named owner, and the ownership covers the `description` strings | doc-track | ready now, independent |
| `SCHEMA-VERSION-1` | The `schemaVersion` const stops contradicting its own description and the reader | code-track | first |
| `SCHEMA-VALID-1` | A gate validates emitted documents against the schema | code-track | after B |
| `SCHEMA-DESC-1` | The 28 normative descriptions get pinned the way `LLMLL.md` sentences are | code-track | after C |

## 2. What was measured

Every number below was produced at v0.23.6, at `f87f8a6`, with `jsonschema`
4.19.1 against `git ls-files '*.ast.json'`. Nothing here is read off the source.

| Measurement | Value |
|---|---|
| Tracked `.ast.json` documents | 96 |
| Of those, valid against the published schema | **0** |
| First failure is the `schemaVersion` const | 77 |
| Carry a version the shipped reader refuses (`0.2.0`, or absent) | 6 |
| Carry the root key `_fixture_note`, which `additionalProperties: false` forbids | 3 |
| Carry root keys `module` and `types`, which the reader ignores and the schema forbids | 2 |
| `description` strings in the schema | 153 |
| Of those, stating a rule (`must`, `rejects`, `cannot`, `mutually exclusive`) | 28 |
| Of those, naming a version | 34 |
| Scripts that validate any document against the schema | 0 |
| Scripts that read a `description` string | 0 |

`scripts/version_gate.sh` touches the schema twice, for the `schemaVersion`
const (C3) and the `$id` URL (C4). `compiler/test/Spec.hs` touches it once, to
assert that an error message cites its path. Neither reads the shape.

## 3. Part A. Ownership (`SCHEMA-OWN-1`)

### 3.1 The gap

`docs/UPDATE-PROTOCOL.md` names `docs/llmll-ast.schema.json` as the canonical
location for the JSON-AST schema, and names README and `LLMLL.md` as citing it
by version. It assigns no role to keeping the file true. The row directly below
it does exactly that for the other schema: the trust-report schema is marked
engineer-owned and schema-tied-to-output, a note added 2026-07-19 after 8 fields
and a stale const had drifted from about v0.10.8 to v0.14.53.

Same failure, other file, and the AST schema never got the same note.

### 3.2 Who owns it, and why

**The compiler-engineer owns it, and the ownership covers the `description`
strings.** Two reasons, and the second is the one that decides it.

The practice is already engineer-track. Of the last 20 commits that touch the
file, most are `feat` or `fix` commits that changed behaviour and the schema in
one patch: `8dff514` (DISCARD-1, schema 0.10.0), `5b913f9` (SRC-CONJ-1, 0.9.0),
`9f09925` (REC-DESCENT, 0.8.0), `4e5ff29` (PROC-BOUNDARY-1). The doc-track
commits are the catch-ups, `f87f8a6` being the most recent.

The mechanism decides it. A description restates a rule. The rule changes in a
compiler patch. The engineer's patch is the only place where a rule and its
restatement can move together. Doc-lead cannot own it, because doc-lead learns
that a rule changed after it shipped, and that delay is what produced two
descriptions nine months out of date.

### 3.3 Verbatim text for doc-lead

Add below the canonical-sources table in `docs/UPDATE-PROTOCOL.md`, in the shape
of the trust-report note that sits there already:

> **JSON-AST-schema ownership (added 2026-09-13).** `docs/llmll-ast.schema.json`
> is **engineer-owned**, schema-tied-to-output, on the same rule as the
> trust-report schema above. The ownership covers the `description` strings and
> not only the structural keywords. A description restates a rule the compiler
> enforces, so the patch that changes the rule changes the description. Doc-lead
> keeps the derived citations in README and `LLMLL.md` (cite by version) and does
> not own the file. Origin: the `init` and `step` descriptions on `DefMain`
> restated rules that `CONSOLE-INIT-1` (v0.23.6) and `EFFECT-RESP` had changed,
> and a hand sweep corrected them at `f87f8a6` because no gate reported them.

Add to the per-change update matrix (D1):

> | A compiler patch changes a rule that `docs/llmll-ast.schema.json` states, in a `description` string or in a structural keyword (`required`, `const`, `enum`, `oneOf`) | The schema, in the **same patch**: the structure, and every `description` that restates the changed rule. `schemaVersion` moves only when the document shape moves | `LLMLL.md` and README (both cite by schema version); the design-doc frontmatter |

## 4. Part B. The version const contradicts its own description (`SCHEMA-VERSION-1`)

### 4.1 Three statements that cannot all be applied

`AstEmit.hs` stamps `expectedSchemaVersion`, which is `"0.11.0"` in
`ParserJSON.hs`. `ParserJSON.hs` accepts six versions through
`acceptedSchemaVersions`: `0.11.0`, `0.10.0`, `0.9.0`, `0.8.0`, `0.7.0`, `0.6.0`.
The schema pins `schemaVersion` to `const "0.11.0"`, and the `description` on
that same property names all six accepted versions.

Each statement is true about a different thing. The const is true about what the
emitter writes. The description is true about what the reader accepts. A
validator can apply only one of them, so the published schema rejects every
document that any earlier release emitted: 77 of 96 tracked documents.

This is the F2 subject in one field. The prose half and the machine-checkable
half of the same property disagree, and no reader existed to notice.

### 4.2 The change

`schemaVersion` becomes an `enum` of the accepted versions, derived from the same
list the reader uses. The emitted version stays stated, in the description and in
one place a gate can read, so `version_gate.sh` C3 keeps its target. The
description then restates the enum rather than contradicting the const.

The rule the schema should express is the reader's rule, because the schema
describes documents the compiler consumes. A document the compiler reads is a
valid document.

### 4.3 A second finding, and it is not the schema's

Six tracked documents carry a version the shipped compiler refuses:
`compiler/examples/sketch/app_hole.ast.json`, `hole_sensitive`, `if_hole`,
`match_conflict` and `match_hole` are all at `0.2.0`, and
`experiments/rfc-swarm/runs/rfc826-llmll-2026-09-11/12-wave/roots.ast.json`
carries no `schemaVersion` at all. The five sketch examples sit under
`compiler/examples/`, so they are shipped surface and not run residue. Repairing
or retiring them is a separate small decision, and it does not block this part.

## 5. Part C. The validation gate (`SCHEMA-VALID-1`)

### 5.1 The population, which is the whole design

The gate validates **documents the current compiler emits**, not documents the
repository has committed. A committed document is a historical artifact that a
past release emitted, and an old document carrying an old shape is correct
behaviour, not drift. A gate over the committed corpus would report age.

So the gate emits and then validates: run `llmll build --emit` over the fixture
corpus, validate each emitted document, and fail on the first that its own schema
rejects. That closes `MODE-HTTP-1` defects (ii) and (iii) at the point where they
are produced.

### 5.2 Overlap with `REPORT-GATE-1`, which its row asked to check

Same class, different instrument, and they should not be folded.
`REPORT-GATE-1` asks for a fixture class that asserts on a **field or an output
line** of `verify --trust-report` or `build`. This gate asserts that a whole
emitted document satisfies a published schema. Both are "assert on what a command
emits", which is the class `DRIFT-CT-2` cannot express today, so they belong in
the same job and should be sequenced together. Neither subsumes the other: a
line-level assertion cannot express document validity, and document validity
cannot express a trust-report field's value.

### 5.3 Cost, and its named cause

Validation cost is a real constraint, and the cause is in the schema rather than
in the validator. The statement and expression unions are undiscriminated
`oneOf`, so a validator tries every branch at every node, and nested expressions
multiply the branches. With the version const in place the cost is hidden,
because most documents fail at the root before descending.

Measured with the const relaxed to the accepted enum. A 1,778-byte document with
one statement validates in 0.7 seconds and is **valid**, which is the first
tracked document to pass anything in this exercise. A 10,357-byte document with
14 statements does not finish in 120 seconds. Six times the bytes costs more than
170 times the time, so the cost is superlinear in document size and not in
document count.

The repair is `if`/`then` dispatch on the `kind` const, or its equivalent, so a
node is checked against one branch. That change is mechanical and it is a
prerequisite of the gate, not an optimization to add later.

### 5.4 The three residual failure classes

With the version const repaired, three classes remain in the committed corpus and
each needs a decision. None of them blocks the gate, whose population is emitted
documents.

1. **`_fixture_note` on three scaffold templates** under
   `experiments/minimal-agent/scaffold-templates/`. The harness writes a note key
   the schema forbids. Either the schema admits an `_`-prefixed extension
   namespace at the root, or the harness moves the note out of the document. I
   recommend the extension namespace, because a fixture that cannot carry a
   comment will grow one somewhere worse.
2. **`module` and `types` at the root of both ERC-20 benchmark documents.** The
   reader ignores unknown root keys, so these are dead keys in a frozen
   benchmark. Correcting a frozen benchmark is its own decision and belongs with
   whoever owns `BM-4`.
3. **`roots.ast.json` with no `schemaVersion`.** A run artifact. Leave it.

## 6. Part D. Pin the normative descriptions (`SCHEMA-DESC-1`)

28 of the 153 descriptions state a rule. Those 28 are normative claims in the
same sense as a sentence in `LLMLL.md` §0.1, and `DRIFT-CT-3` already pins those
sentences to `scripts/norm-claims/registry.json` by an `NC-NNN` marker with a
pinned `text` and a disposition.

The proposal reuses that mechanism rather than inventing one: a normative
description carries a marker, the registry row pins its text, and the
disposition names what stands under it (a fixture, a row, or `assumed`). The
other 125 descriptions stay unpinned by design. They describe shape, not rules.

28 is a small population, measured, so the cost is known before the work starts.
This part is sequenced last because a description pinned to a rule no gate
enforces is a record, not a check.

## 7. Edge cases and degenerate inputs

1. **A document at an accepted but older version, emitted by an older release.**
   Expected: valid. Under the published schema today it is invalid, which is the
   77-document failure class. Channel: contract, through the enum in part B.
   Citation: `acceptedSchemaVersions` in `ParserJSON.hs`.

2. **Positive witness for `SCHEMA-VALID-1`, the minimal firing input.** A
   `def-main` declaring `:mode http 9000`, emitted with `--emit`. `AstEmit.hs`'s
   `entryModeLabel` writes `"mode": "http:9000"`. The schema's `DefMain.mode` is
   `oneOf` a `["console","cli"]` string or a `{"kind":"http","port":INT}` object,
   and `"http:9000"` matches neither, so the gate fails on a document the
   compiler just produced. This is `MODE-HTTP-1` defect (iii), and it is
   constructible today rather than described abstractly. Channel: the gate.

3. **A document with an unknown `mode` string, for example `"consoel"`.**
   Expected after `MODE-HTTP-1` defect (i) ships: a decode error naming the
   accepted values. Expected today: it decodes to an HTTP program with zero
   diagnostics. The schema rejects it either way, so this gate catches the silent
   wrong answer even before the reader is repaired. Channel: the gate.

4. **A schema change with no compiler change.** Expected: the gate passes and
   nothing fires, because emitted documents did not move. This is the quiet case,
   and it is the majority case. Channel: none, by design.

5. **A new optional field, added additively.** Expected: old documents stay
   valid, new documents stay valid, the enum grows only when the shape changes.
   Channel: contract. Citation: the `expectedSchemaVersion` comment block in
   `ParserJSON.hs`, which already states the additive rule.

6. **A description that restates a rule nobody enforces.** Expected under part D:
   the registry disposition is `assumed`, and the assumed count carries it
   visibly, exactly as `NC-035` does today. Spec is not silent here; the
   mechanism reports the gap rather than hiding it.

## 8. Verification mapping

No proof obligation is introduced. Every part of this proposal is a
document-level check outside the solver, so nothing reaches QF-LIA, nothing is
nonlinear, and nothing escapes to Lean as `?proof-required`. The boundary in
`LLMLL.md` §5.3.3 and §5.3.5 is untouched, and no `.fq` query changes.

Stated explicitly because the alternative reading is available and wrong: a
JSON-Schema check is a syntactic admissibility check over a document, not a
verification condition over a program. It changes no verdict, no trust tier, and
no evidence record.

## 9. Affected surface

- `docs/UPDATE-PROTOCOL.md`: one canonical-sources note, one matrix row. Part A,
  doc-lead.
- `docs/llmll-ast.schema.json`: the `schemaVersion` enum, the `kind` dispatch on
  the statement and expression unions, and the root extension namespace if edge
  case 5.4.1 is accepted. Parts B and C, engineer.
- `compiler/src/LLMLL/ParserJSON.hs`: `acceptedSchemaVersions` becomes the single
  source the schema's enum derives from. Part B.
- `scripts/version_gate.sh`: C3 asserts the const today. It needs a target after
  the const becomes an enum. Part B.
- `.github/workflows/version-gate.yml`: the job installs `pytest` only, so a
  validator dependency is a new install line. Part C.
- `scripts/norm-claims/registry.json` and `scripts/norm_claims_gate.py`: the
  registry's scope widens to schema descriptions. Part D.
- `compiler/examples/sketch/app_hole.ast.json` and its four siblings: five
  documents the compiler cannot read. Separate decision, named in 4.3.

## 10. Risks and open questions

1. **The gate's population is emitted documents, so a hand-authored document is
   never checked.** Classify: scope. An agent that writes JSON-AST by hand is the
   language's primary consumer, and the gate does not see its output. Bite:
   complicates the claim. The gate proves the compiler's own output is
   schema-valid, which is narrower than "every document is valid". State it that
   way and do not overclaim.
2. **Discriminating the unions is a schema restructure, not an edit.** Classify:
   verification-ergonomics. Bite: complicates part C, and it is a prerequisite
   rather than an optional improvement. The measurement in 5.3 is the evidence.
3. **Part B changes what `version_gate.sh` C3 asserts.** Classify: spec-drift.
   Bite: blocks part B until the replacement target is named. C3 currently pins
   the const, and an enum has no single value to pin.
4. **The ERC-20 documents are frozen benchmark ground truth.** Classify: scope.
   Bite: only matters if the committed corpus is ever gated. It is not, under
   this proposal.
5. **Part D could grow into pinning all 153 descriptions.** Classify: scope.
   Bite: only at scale. The 28-row population is measured and the boundary is
   stated: a description that states a rule is pinned, a description that
   describes shape is not.

## 11. Hand-off

Part A is doc-track and needs no engineer. Doc-lead applies section 3.3 verbatim,
adds no INDEX row for this proposal until it settles, and touches nothing else.

Parts B, C and D are code-track and go to the compiler-engineer as one plan with
three stages in the stated order. The engineer's feasibility pass must construct
the positive witness in 7.2, which is a `def-main` with `:mode http 9000` emitted
through `--emit`, rather than tracing that the values are in scope.
