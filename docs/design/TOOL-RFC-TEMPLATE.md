---
name: tool-rfc-NNN-slug
title: "TOOL-RFC-NNN: <the gate>, in LLMLL"
status: "Rev 0, DRAFT. State: blocked | oracle | retired."
date: YYYY-MM-DD
author: <whoever ports it; not a role skill>
consumers: [compiler-engineer, documentation-lead, user]
tool_state: blocked
subject_script: scripts/<the script this replaces>
port_module: tools/<dir>/<module>.llmll
---

# TOOL-RFC-NNN: \<the gate\>, in LLMLL

> Copy this file to `docs/design/tool-rfc-NNN-<slug>.md`. The standard is
> [`llmll-tooling-campaign.md`](llmll-tooling-campaign.md); the gate that reads
> this file is
> [`scripts/tests/test_tool_rfc_standard.py`](../../scripts/tests/test_tool_rfc_standard.py).
> All nine sections are required, `## 7. Verification` included. Delete this
> quote block.
>
> `tool_state` is the tri-state of the campaign §4 and is checked against the
> filesystem: `blocked` (no port), `oracle` (both run), `retired` (the subject
> script is deleted). Moving to `retired` and deleting the script happen in one
> commit.

## 1. Subject

What is being replaced, how big it is, and where CI invokes it. Cite the
workflow file and job by name: the *job* is what determines §3, and getting it
wrong is the mistake TOOL-RFC-001 records.

## 2. Criteria

What the tool decides, enumerated. Quote the reference's own message text for
each, because the port owes the same messages and a cover that compares them
needs them written down somewhere that is not the reference.

State the reference's failure ORDER. A gate that exits on first failure has an
order, and it is part of the behaviour.

## 3. Distribution

Which job runs the port and how the binary gets there. The campaign settled on a
published release image; a port that needs anything else is proposing a change
to the campaign and should say so here rather than in a diff.

Name the constraint that makes this non-obvious. If the job has no toolchain,
say so and say what follows.

## 4. Feasibility

Every language feature the port needs, each marked available or a gap. Work from
the reference's actual behaviour rather than its description.

| Needs | LLMLL | Note |
|---|---|---|
| | | |

## 5. Gaps

Every gap from §4, each with **exactly one** disposition, per campaign §5:

- **BLOCKS**: the port cannot proceed; the language work ships first.
- **SHAPES**: the port proceeds and the language forced a different design.
  **State what the design would have been otherwise.**
- **COSMETIC**: noted, nothing follows.

Every BLOCKS and SHAPES row cites a roadmap tag. If no row exists, file one:
a gap with no row is the silent workaround the campaign exists to prevent.

| Gap | Disposition | Roadmap tag | What the design would have been |
|---|---|---|---|
| | | | |

## 6. Differential plan

How the port is checked against the reference. The mutation battery, one row per
criterion, plus at least one **negative control** that changes the input in a way
that must NOT fail.

Every mutant is asserted to fail under **both** implementations before their
answers are compared. Agreement on a passing tree is not evidence.

| Cell | Mutation | Criterion | Expect |
|---|---|---|---|
| | | | |

## 7. Verification

§6's battery is checked against the reference. **§8 deletes the reference.** From
that release on every cell in §6 is inoperable, and the port's only remaining
instrument is its live corpus passing, which is the port agreeing with itself.
This section names what survives that.

**Name two instruments that fail differently, and state what each catches that
the other cannot.** Not "is it proved". Two instruments that fail the same way
are one instrument.

| Instrument | Catches | Blind to | Survives §8? |
|---|---|---|---|
| | | | |

The differential cover is a legitimate entry and is usually the first row, but it
is blind by construction to a defect the port and the reference **share**, which
is the likely class when the port was written by reading the reference. It also
does not survive §8.

A **contract with at least one refuting case** is the usual second row, because it
references neither implementation and outlives the reference.
`--strict-verified-core` passing is not sufficient on its own: a module with no
body-faithful functions passes it vacuously, and a postcondition of `false` on a
fallback body reports SAFE. The refuting case is what separates a proof from a
green light, since a fallback function cannot be refuted.

**One row may be honest about absence.** "This half has one instrument", with a
roadmap tag, is an acceptable answer and follows §5's discipline. A recognizer
over arbitrary strings cannot be contracted today. Listing one instrument twice
under two names is not acceptable.

## 8. Retirement

The release at which the subject script is deleted, and what must be true first.
At minimum: the differential cover green, the port wired into a job that decides,
and one release elapsed in state `oracle`.

## 9. Decisions taken

**The policy calls, not the implementation.** Anything the author decided that a
reader could reasonably have decided otherwise, and that is not settled by the
reference or by the campaign. Placement, scope, what was deliberately not built.

This section exists because TOOL-RFC-001 was written after its port shipped, and
three of its four decisions here were made at the keyboard and reported
afterwards rather than asked first. That is the failure the RFC-first workflow is
for, and it is cheap to prevent and awkward to undo.
