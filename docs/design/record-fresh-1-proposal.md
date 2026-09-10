---
name: record-fresh-1-proposal
title: "RECORD-FRESH-1: a live record's next pointer is a denormalized fact, so gate the copy"
status: "Rev 0, DRAFT 2026-09-10. Measured, not argued: the co-edit rule is REFUTED (119 alarms in 180 days, and it catches 1 of the 3 real failures). Proposes DRIFT-DOC-6, a freshness stamp with git as its oracle, riding on FRONTMATTER-GATE-1 / DRIFT-DOC-5 which must ship first. Not filed as a roadmap row; no code written."
date: 2026-09-10
author: compiler-engineer (draft)
consumers: [user, language-team, compiler-engineer]
---

# RECORD-FRESH-1: a live record's next pointer is a denormalized fact, so gate the copy

## 1. The defect, measured

`docs/design/driver-ll-phase4-RESTART.md`'s frontmatter `status:` field is the first
thing a restarting session reads. The campaign record says so, and
`project_driver_ll_phase01` in the session memory says so. It has been corrected
**three times for one defect**:

| When | What the field said | What was true |
|---|---|---|
| 2026-08-18 (`196969a`) | the next thing is the CI-gate port | that port had closed at v0.16.1 |
| 2026-09-10 (`ea41731`) | 4d parked, stage A a filed STOP | both had shipped, v0.21.1 and v0.21.2 |
| 2026-09-10 (`ce6c830`) | 4f has not started | 4f had shipped at v0.23.1 |

The field's own text now records this, which is how the third one was found.

## 2. The mechanism, and it kills the obvious rule

The obvious rule is a co-edit requirement: if a commit changes the body of a record,
it must also change the `status:` field. Two independent measurements refute it.

**It is too loud.** Over 180 days, 342 file-touches landed on the 88 tracked documents
that carry a `status:` field. **119 of them changed the body and not the status line.**
A gate firing 119 times in six months on a population this small is not a gate, it is a
new source of noise. Most of those 119 are correct: an appendix, a typo, a link repair.

**It is aimed at the wrong event, and this is the decisive half.** The status line of
the driver record was edited in **17 of the 28** commits that touched the file in five
weeks. This field is not neglected. It goes wrong anyway, because **two of the three
failures were caused by commits that never touched the file at all.** The third failure
was caused by `ecaf418`, the 4f merge, which changed `tools/llmll-driver/` and did not
go near `docs/design/`. A rule that reads the diff cannot see the commit that does the
damage.

So the check must evaluate a claim **against the live tree on every push**, which is
what the four existing DRIFT gates already do, and not against a diff.

## 3. What F-002 forbids, and what it leaves open

`experiments/adv-spec-weaken-0/findings.md` settles **F-002** over the `:intentional`
annotation, whose construct in `LLMLL.md` is the `:intentional` bullet of section 4.4.6
(Contract Discriminative Power): a self-attestation channel admits no per-instance oracle by
construction. `archive-organization-proposal.md`:71-72 names a `Status:` line as exactly
that channel, and restates it at :536-539.

> **Found while writing this section, and it is the defect in miniature.**
> `archive-organization-proposal.md`:414 cites F-002 as `LLMLL.md`:708. That line now
> holds the Pacheco-Lahiri-Ernst overallocation note; the `:intentional` construct the
> citation means sits at :740, 32 lines down. A second copy of a fact drifted from its
> source, in the very document that argues a drifting second copy needs a maintaining
> mechanism. Nothing detected it, because `DRIFT-DOC-4` resolves whether a path exists
> and not whether a line number still means what it meant. This is not routed here.

**So do not gate the prose.** No check can decide whether "the next thing is program
unification" is true, and proposing one would run into a settled refutation.

What F-002 leaves open is the move `archive-organization-proposal.md`:130-131 already
made for the archive: **denormalize deliberately and supply the maintaining mechanism.**
A directory name is a second copy of a fact stated in a document, and DRIFT-DOC-3 is
what licenses that copy. The same shape applies here. The proposal below adds a second
copy of a fact whose source is git, and gates the copy. It does not attest to anything.

## 4. The proposal

A record that declares itself live carries a structured freshness stamp beside its
prose status, and a gate checks the stamp against git.

```yaml
verified-against:
  - path: tools/llmll-driver/
    head: e49e968
  - path: docs/design/driver-ll-phase4f-implementation-plan.md
    head: e49e968
```

**The assertion, and it is one line of git per entry.** For each entry, `git log -1
--format=%h -- <path>` equals `head`. If it differs, the gate fails and names the file,
the path, the stamped sha and the current one.

**What the failure means.** Not "this record is wrong". It means the subject area moved
after the record was last checked against it, so the record's claims about that area are
unverified. The remedy is to read the record, correct what moved, and re-stamp. The
message should say that, because a gate whose message implies the document is wrong will
be silenced by re-stamping without reading.

**Where it runs.** The banner job, which needs no compiler. It ships as **DRIFT-DOC-6**
on the existing four-gate naming.

**FRONTMATTER-GATE-1 is a hard prerequisite.** That row (roadmap G8, OPEN, planned as
DRIFT-DOC-5) adds YAML well-formedness over the 67-file frontmatter population using
PyYAML, which is already available to the harness. A stamp that is not parsed is not
checked, and that row's own finding is that today's two frontmatter readers are line
regexes that return usable values from a malformed block. DRIFT-DOC-6 must read its key
with a real parser, so it lands after DRIFT-DOC-5 or not at all.

## 5. Replay against the three failures

Not argued. Each row below is `git log -1 -- <path>` evaluated at that commit.

| Failure | Stamp would have read | Truth at that point | Fires? |
|---|---|---|---|
| 2026-09-10, 4f (`ecaf418`) | `3e1c1af` | `e49e968` | **yes** |
| 2026-09-10, the refresh that left the field (`b7ccee4`) | `9f4592d` (2026-08-17, its prior correction) | `3e1c1af` (2026-09-08) | **yes** |
| 2026-08-18, the closed CI-gate port (`196969a`) | a `tools/llmll-driver/` stamp | the claim ranged over `tools/`, whose head was `b6b0262` | **only if `tools/` is stamped** |

**Two of three with a single path. Three of three only if the stamp list covers every
path the record's claims range over, and nothing mechanically forces that list to be
complete.** That is the instrument's boundary and it belongs in its own disclosure: the
gate decides freshness for declared paths and decides nothing about undeclared ones. A
record that stamps one path and makes claims about five is checked on one fifth of its
surface, silently.

## 6. Negative controls the cover must carry

A passing run over the live tree proves nothing on its own, which is the lesson
FRONTMATTER-GATE-1's PLAN states for DRIFT-DOC-5 and `versiongate.llmll`'s vacuous
`--strict-verified-core` pass demonstrates one directory over. The cover needs at least:

1. **The gate removed.** With the check deleted, the corrupted-stamp cell must pass, or
   the cell is not testing the gate.
2. **A stale stamp on a live tree.** Rewind a stamp by one commit; the gate must fail and
   name both shas.
3. **A stamp on a path with no commits.** Must fail loudly rather than treat an empty
   `git log` as agreement, which is the empty-set failure this repository keeps finding.
4. **A record with no `verified-against` key.** Must be skipped explicitly and counted in
   the run's output, so the covered population is visible rather than assumed.
5. **A deleted path.** A stamp naming a path that no longer exists must fail, not pass by
   an empty comparison.

## 7. Cost, and the population it would cover

88 of 185 tracked documents under `docs/` and `docs/design/` carry a `status:` field.
**Covering all 88 is the wrong scope.** The defect concentrates: over 180 days the
body-without-status touches ranked `tool-ll-RESTART.md` 28, `llmll-tooling-campaign.md`
18, `driver-ll-phase4-RESTART.md` 10, and a long tail of single digits.

So the covered set is opt-in by the presence of the key, not by a status-prose pattern.
Measured: `status:` values today begin with `LIVE`, `CLOSURE RECORD`, `Rev 7` and
`ACTIVE ROUTING RECORD`, so **no mechanical class marker exists** and inventing one would
be a second unmaintained denormalization. Three files would carry the key on day one.

## 8. Where it sits in the taxonomy

`archive-organization-proposal.md`:63-68 splits the existing gates in two, and Rev 1 of
that document had them as one class:

- **Consistency, no oracle.** DRIFT-CI-1 asserts equality among four records all
  maintained by hand inside this repository. DRIFT-DOC-3 is its sibling.
- **Claim, with an oracle.** DRIFT-CT-2 executes the compiler and compares an observed
  verdict to a claimed one.

**DRIFT-DOC-6 is in the second class.** Its oracle is the git history, which is computed
rather than hand-maintained, so it is a sibling of DRIFT-CT-2 and not of DRIFT-CI-1. This
matters for where the cover's burden sits: a claim gate can be checked by mutating the
oracle's answer, which is what control 2 above does.

## 9. What this does not decide

- Whether the prose beside the stamp is true. F-002 says nothing can decide that, and
  this proposal does not try.
- Whether the two existing line-oriented frontmatter readers should move to a real
  parser. FRONTMATTER-GATE-1 deliberately does not pre-empt that and neither does this.
- Whether `llmll-tooling-campaign.md` and `tool-ll-RESTART.md` should carry the key. Both
  are closure records rather than live pointers, and a closure record's staleness may be
  the intended state.

## 10. Status

**Nothing is filed and no code is written.** This is a draft for the user to route. If it
proceeds it wants a roadmap row under G8 beside FRONTMATTER-GATE-1, sequenced after it,
and an `INDEX.md` row for this file.
