# Stage D: clause extraction (extractor {{extractor}})

You are one of **two independent extractors**. The other extractor is reading the same bytes
under the same rubric, in a directory you cannot see, and you cannot see its output. That is
deliberate: one audited pass cannot answer "who checked that the inventory is complete", and
two independent passes can. Do not speculate about what the other extractor did.

## Your task

Produce a **census of the normative clauses** of the RFC text below, applying the rubric below
uniformly. Write the result to `extraction.json` in your working directory.

## What you must NOT do

- **Assign no disposition.** Do not decide whether a clause is verifiable, in scope,
  implementable, or interesting. Keeping scoping out of extraction is what makes the two
  extractions comparable. A clause you believe is impossible to verify is still a row.
- **Do not extract from memory.** Every row cites a line span in the text below. If you
  believe the RFC says something that is not in the text below, it is not a row.
- **Do not summarize.** One obligation per row (rubric tie-break 1). A sentence carrying two
  separable obligations splits into two rows.

## Output contract

`extraction.json` is a JSON **object** with two row lists:

```json
{
  "extractor": "{{extractor}}",
  "normative": [
    {
      "id": "{{extractor}}1",
      "source": "RFC1350",
      "line_start": 93,
      "line_end": 94,
      "section": "2. Overview of the Protocol",
      "quote": "a short verbatim quote from the text",
      "rule": "N3",
      "strength": "must",
      "obligation": "one sentence, in your own words, stating what an implementation must do"
    }
  ],
  "excluded": [
    {
      "id": "{{extractor}}x1",
      "source": "RFC1350",
      "line_start": 30,
      "line_end": 32,
      "quote": "...",
      "rule": "X1",
      "reason": "motivation, imposes no obligation"
    }
  ]
}
```

- `id` is yours to assign, sequential, prefixed with your extractor letter.
- `source` is the pinned file the row came from, written `RFC1350` / `RFC1123`.
- `line_start` / `line_end` are **integers** and refer to the line numbers shown in the left
  margin of the text below. Reconciliation matches the two extractions by line-span overlap, so
  a wrong span silently becomes a "disagreement" that never happened. Get these right, and
  never guess: the numbers are printed for you.
- `rule` is the rubric rule you applied: `N1`..`Nn` in `normative`, `X1`..`Xn` in `excluded`.
- `strength` is the requirement word actually present (`must`, `should`, `may`, or `none` when
  the obligation is stated without one).

**`excluded` is required, not optional.** It records the text you read and judged
non-normative, and it is the evidence that the rubric was applied rather than skipped. An
extraction with an empty `excluded` list will be read as an extractor that never looked at the
prose.

Nothing else. No prose outside the JSON file.

## The rubric (apply uniformly; it was written before any extraction)

{{rubric}}

## The pinned RFC text

Line numbers below are authoritative for the `lines` field.

```
{{rfc_text}}
```
