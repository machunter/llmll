# Stage G2: does each stated reason match the clause it cites?

You are auditing a disposition ledger against the pinned source text. Write your verdicts to
`audit.json`.

The pipeline already checked, mechanically, that every citation resolves to the pinned bytes:
the source exists, the line span is inside it, and the quote's words come from that span. It
cannot check the thing that actually went wrong on a previous run, which is a **reason that
restates its own clause incorrectly** and then disposes of the row on the strength of the
restatement. That is your only job here.

## The one question

For each subject below: **does the stated `reason` describe the clause the row cites, as that
clause is actually worded in the pinned text?**

You are **not** asked whether the disposition is right. A row may be excluded for a reason that
reads its clause perfectly, and you should pass it even if you would have disposed of it
differently. You are also not asked whether the obligation is important, whether the barrier is
the best fit, or whether the model could carry it. Only: does the reason say what the clause
says.

## What a real finding looks like

The case this stage exists for. The pinned clause read:

> "Implementations MUST NOT add line feeds to base-encoded data **unless** the specification
> referring to this document explicitly directs base encoders to add line feeds after a specific
> number of characters."

and the reason opened:

> "The clause forbids inserting line feeds into base-encoded data **after a specific number of
> characters**."

The positional qualifier belongs to the `unless` exception. The reason moved it into the
prohibition, which narrows an unconditional obligation into a conditional one. That is a
`misreads`.

Things that are **not** findings: a reason that paraphrases loosely but faithfully; a reason
that quotes a different sentence of the same clause; a reason that adds analysis beyond the
clause; a reason you disagree with on the merits.

## Evidence is required, and it is checked

A `misreads` verdict must carry two literal strings, and the driver verifies both occur:

- `quote_phrase` — the words **from the cited quote** that the reason gets wrong. Must appear in
  the quote exactly as given there.
- `reason_phrase` — the words **from the reason** that get it wrong. Must appear in the reason
  exactly as given there.

If you cannot point at both, you do not have a finding, and the verdict is `matches`. A flag the
driver cannot check against the artifact is an assertion, and it will halt the run as one.

## Output contract

Every subject gets exactly one verdict. Omitting a subject is not an abstention and will fail
the stage: an audit that may quietly drop its hardest row reports the same thing as one that
found nothing.

```json
{"audited": [
  {"cid": "A14", "verdict": "matches"},
  {"cid": "A1", "verdict": "misreads",
   "quote_phrase": "unless the specification referring to this document",
   "reason_phrase": "after a specific number of characters",
   "note": "the positional qualifier belongs to the exception, not the prohibition; the obligation as written is unconditional"}
]}
```

`note` is one sentence, and only on a `misreads`.

## The subjects

These are the rows the gate reads: every characteristic-core row, and every row dispositioned
out. Each carries the quote as the census recorded it, the line span it cites, and the reason
the disposition pass wrote.

{{subjects}}

## The pinned source text

Read the clause here, at the cited lines, rather than from the `quote` field. The quote is what
the census claims the clause says; the text below is what it says.

```
{{rfc_text}}
```
