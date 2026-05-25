# int-pre harness — findings (consolidated 2026-05-25 per DOC-CONSOLIDATE §M1)

> Previously fanned out across `findings/{compiler-team,language-team,documentation-team}.md`. Collapsed to H2-per-role per `docs/design/doc-consolidation-2026-05-24-proposal.md` §4.3. On-disk role filenames (`compiler-team.md`, `documentation-team.md`) normalize to the canonical role anchors (`## Compiler-engineer`, `## Documentation-lead`) per §M1's H2-per-consuming-role contract. The `experiment-lead` role had no findings file on this harness; an empty H2 stub is preserved for the grep-anchor contract.

## Compiler-engineer


> **Status:** Template; populated as INT-PRE runs surface engineering-track patterns.
> **Format reference:** `experiments/minimal-agent/findings/compiler-team.md`
> **Routing rule:** Findings here imply a compiler bug, codegen issue, or harness defect that requires a code change. State the implication; do not author the fix.

### Active fragments

(Per fragment: F-NNN. Title. Evidence. Why. Fix-in-prose. Acceptance.)

### Withdrawn items

(Engineering-track claims that did not survive verification.)

### Cross-references

- INT-2 boundary-shim catalog: `docs/design/int-2-boundary-shims.md`
- INT-3 contingency sketch: `docs/design/int-3-machine-int-sketch.md`
- Variant B implementation commit: `03d5722` on `int-pre/variant-b`
- Variant A baseline commit: `009a6f0` on `release/v0.10.7`

---

## Language-team


> **Status:** Template; populated as INT-PRE runs surface spec-track patterns.
> **Format reference:** `experiments/minimal-agent/findings/language-team.md`
> **Routing rule:** Findings here imply a spec move — catalog correction, refinement-predicate vocabulary adjustment, INT-3 promotion, etc. State the implication; do not author the spec.

### Active fragments

(Per fragment: F-NNN. Title. Evidence. Why. Spec-implication-in-prose. Acceptance.)

### Withdrawn items

(Spec-track claims that did not survive verification. The existing pattern in `minimal-agent/findings/language-team.md:180-188` is the reference; preserve withdrawn items as first-class hygiene.)

### Cross-references

- INT-2 boundary-shim catalog: `docs/design/int-2-boundary-shims.md`
- INT-3 contingency sketch: `docs/design/int-3-machine-int-sketch.md`
- Catalog SHA pinned in `experiments/int-pre/manifest.json` `catalog_ref.sha` field

---

## Experiment-lead

(no findings recorded for this harness)

---

## Documentation-lead


> **Status:** Template; populated only via the loop after engineer / language-team have actioned upstream findings.
> **Format reference:** `experiments/minimal-agent/findings/documentation-team.md`
> **Routing rule:** Experiment-lead does not hand documentation patches to doc-lead directly. Doc-lead is invoked downstream after the engineer ships and the spec move is settled. Fragments here surface for doc-lead consumption only when the upstream consumer (engineer or language-team) routes them.

### Active fragments

(Per fragment: which of the six doc-lead target docs is affected, verbatim resolution text, cross-references. Empty until upstream routing brings a fragment here.)

### Cross-references

- Six doc-lead target docs: `README.md`, `LLMLL.md`, `CHANGELOG.md`, `docs/getting-started.md`, `docs/llmll-ast.schema.json`, `docs/compiler-team-roadmap.md`
- Doc-lead input contract: an approved engineer ship OR an approved language-team spec-track hand-off
