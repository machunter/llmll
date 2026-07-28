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

**The example below is invented.** It is not from this document or from any inventory, because a
worked example drawn from a row you are about to audit tells you that row's answer and this stage
would then be measuring the example rather than the ledger.

Suppose a pinned clause read:

> "A responder MUST verify **at least one** signature before accepting a bundle."

and its recorded reason opened:

> "The clause requires the responder to verify **every** signature on the bundle."

The obligation is existential and the reason made it universal. Nothing downstream reasons about
the clause any more; it reasons about a stronger rule the document never stated. That is a
`misreads`, and it would be one just as much in the other direction.

The general shape is that the clause attaches something to one part of the sentence and the
reason attaches it somewhere else, or drops it, or strengthens it. Classes worth checking
deliberately, since each has produced a real defect somewhere:

- **quantifier**: every / at least one / any / exactly one, swapped or inverted.
- **exception attachment**: a qualifier that belongs to an `unless`, `except`, `other than`,
  `only if` or `provided that` clause, restated as part of the main obligation, or the reverse.
- **modality**: a prohibition read as a permission, a requirement read as a default, `MUST NOT`
  read as `NOT REQUIRED`.
- **actor or direction**: the obligation moved from sender to receiver, or from the responder to
  whoever referred to the document.
- **dropped condition**: a precondition present in the clause and absent from the reason, so an
  obligation that applies sometimes is restated as applying always.

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

Shown with the invented row above, for shape only. Your `cid` values are the ones in the subject
list.

```json
{"audited": [
  {"cid": "X41", "verdict": "matches"},
  {"cid": "X42", "verdict": "misreads",
   "quote_phrase": "at least one signature",
   "reason_phrase": "verify every signature",
   "note": "the clause is existential and the reason states it universally"}
]}
```

`note` is one sentence, and only on a `misreads`.

Emit the JSON object as your reply. If a file-writing tool is available, also write it to
`audit.json`.

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
