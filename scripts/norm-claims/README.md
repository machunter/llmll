# DRIFT-CT-3, the norm-claim gate (NORM-CLAIM-1)

`DRIFT-CT-2` ([`../doc-claims/README.md`](../doc-claims/README.md)) checks that a claim which
has a fixture still holds. This gate checks the other direction: that every sentence in the
governed sections of `LLMLL.md` names what stands under it. Design and pilot findings:
[`docs/design/norm-claim-proposal.md`](../../docs/design/norm-claim-proposal.md) (Rev 1,
settled 2026-09-06). It is the reverse of `LLMLL.md` §4.6: a contract clause names the standard
it came from with `:source`; a spec sentence names the repository artifact that grounds it with
`[NC-NNN]`.

## The two halves

**Markers in the spec.** Every sentence in a governed section ends with `[NC-NNN]` immediately
after its terminal punctuation. The identifier is assigned once and is never renumbered or
reused (the `Q-NNN` precedent in `docs/design/theory-questions.md`). Governed sections are the
`scope` list in the registry; today that is §0.1 and §1 of `LLMLL.md`.

**Rows in the registry.** [`registry.json`](registry.json) holds one row per identifier:

```json
{ "id": "NC-029", "section": "1.6",
  "text": "A module reaches no part of the system it has not imported, and the compiler rejects a `wasi.*` call whose namespace the calling module did not declare.",
  "disposition": "fixture", "target": ["scripts/doc-claims/missing-capability.llmll"] }
```

`text` is the sentence with its marker removed and whitespace collapsed, and the gate compares
it byte for byte. **Editing a tagged sentence fails the gate until its row is re-affirmed in the
same change.** That is the `.verified.json` sidecar discipline applied to prose, and it is why
the registry stores the text rather than a hash: a diff shows what changed.

## The five dispositions

| Disposition | Target | What the gate checks | In the ratio |
|---|---|---|---|
| `fixture` | one or more paths under `scripts/doc-claims/` | each path is in the git index and carries a header line `;; @norm: NC-NNN[, ...]` naming this id; `DRIFT-CT-2` keeps running the fixture | denominator |
| `falsified-by` | `suite:<family>` or `gate:refute-crux` | a committed `EXPECTED_VERDICTS.json` with that `family` exists; or the refute-crux step exists in `version-gate.yml` and at least one suite does. Names the instrument, never a count | denominator |
| `row` | a roadmap tag | the Active Items table has the row and its status cell (column 2) begins with `OPEN`. A closed row fails the gate until the sentence is re-dispositioned, which is how a row closure re-runs the check | denominator |
| `assumed` | a `reason` string | present; the count is at most `assumed_bound`. The bound goes down freely and up only with `bound_reason` | numerator and denominator |
| `informative` | none | the sentence asserts nothing about the language or the compiler | reported separately |

The success line reports the counts and the ratio, the same way `SpecCoverage` reports
`suppression_debt`:

```
DRIFT-CT-3: 35 sentences dispositioned (fixture 16, falsified-by 3, row 1, assumed 8, informative 7); assumed ratio 0.29, bound 8
```

## The sentence rule is the definition

Prose in a governed section conforms to the splitter; the splitter does not grow to fit prose.
A line is prose unless it is blank, a heading, a table row, an HTML comment, `---`, or inside a
fenced block. A leading list marker (`1.`, `4a.`, `-`) and a leading `>` are removed. Text
splits at `.`, `!` or `?` outside a code span, optionally followed by a marker, then whitespace
and an uppercase letter, `*`, a backtick, `(` or `[`, unless the word before the punctuation is
`e.g.`, `i.e.`, `vs.`, `cf.`, `etc.` or `et al.`. If the rule splits a sentence wrongly, edit the
prose.

## What fails

There is no SKIP (`SKIP-SILENT-1`, `FRONTMATTER-GATE-1`). A missing, unreadable or malformed
registry, an unreadable spec, an empty scope, or a scope heading not found is a FAIL. So is: an
untagged sentence; a marker with no row; an identifier twice in the spec; a row with no sentence;
a text mismatch; a fixture missing from the index or not naming the id; a suite that does not
exist; a row that is absent or not `OPEN`; an `assumed` count over the bound.

## Running

```bash
python3 scripts/norm_claims_gate.py --repo .          # the reference; exit 0 with the line above
python3 scripts/norm_claims_gate.py --repo . --dump   # marker, line, text per sentence; no checks
python3 scripts/norm_claims_cover.py --repo .         # 16 mutation cells against the reference
python3 scripts/norm_claims_cover.py --repo . --port "$GATE"   # differential, once the port exists
```

CI runs the reference and the cover in the `spec-roundtrip` job of
`.github/workflows/version-gate.yml`, after the doc-claims step, on every push and pull request
to `main`. A pull request that closes a roadmap row named by a `row` disposition therefore fails
until the sentence is re-dispositioned in that pull request.

## Adding or changing a sentence

1. Write the sentence and end it with the next unused identifier: `…text.[NC-036]`.
2. Add its row to the registry with the exact text and one disposition.
3. For `fixture`, add `;; @norm: NC-036` to the fixture's header (a fixture may name several ids,
   and a sentence may name several fixtures).
4. Run the gate. Never renumber an existing identifier; a deleted sentence deletes its row.

## Port status

The LLMLL port (tools/norm-claims/normclaims.llmll, not yet on disk) is owed under the TOOL-LL campaign's
three-artifact shape and is not yet written; the cover runs as a self-cover of the reference
until it exists, and says so on its summary line.
