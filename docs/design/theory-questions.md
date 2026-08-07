---
name: theory-questions
title: "Deferred theory questions: what the repository cannot answer"
status: "PERMANENT REGISTER, opened 2026-08-06. Append-only. Question text is immutable once written; a Status may move OPEN to ANSWERED, WITHDRAWN or PROMOTED, and an answer is appended beneath its question carrying its own date. Nothing here blocks anything: every entry is a question whose answer would refine confidence rather than change what gets built, which is the admission test. Unlike the routing records in this folder, this file is not deleted when a phase closes."
date: 2026-08-06
author: language-team
consumers: [professor, language-team, user]
---

# Deferred theory questions

Questions raised during design that are theoretical, answerable only from the literature, and
irrelevant to whether the proposal that raised them settles. The triage that admits an entry, and
the negative test that keeps this file from becoming a parking lot for unexecuted claims, are in the
language-team skill under "Deferred theory questions".

**Append only.** Do not reword a question, do not delete one, do not renumber. `Q-NNN` is monotonic
and never reused. If a question turns out to block something, its Status becomes `PROMOTED` and the
routing is named; it is not removed, because where a question came from is part of what it says.

**Cite by name, never by line.** A question keyed to a line number is undecidable a month later and
the doc lint cannot check it.

---

## Q-001  (2026-08-06)  Status: OPEN

Is a compiler-checked total abstraction function, plus exhaustive case coverage over its domain,
adequate evidence for a refinement mapping when the concrete side is unmodeled code? Or is that
precisely the gap refinement mappings exist to forbid closing cheaply?

Context. The driver's `tools/llmll-driver/token.llmll` proves a memoryless per-phase property: a
total function from a three-arm phase sum to a two-arm token state, verified body-faithfully. The
target property quantifies over moments of a run rather than over the function's inputs, and it
follows pointwise once you have the equation relating the driver's actual token state to that
function applied to the driver's actual phase. That equation is a refinement mapping in the sense of
Abadi and Lamport. Under the settled encoding it acquires a syntactic witness, a total function from
the sequencer's stage-phase sum into the token module's lifecycle phase, whose totality the compiler
checks. What no check reaches is whether the arm assignments correspond to the driver's real control
flow, and the sequencer has no formal step relation to check them against.

The literature discharges refinement mappings against a step relation. The question is whether any
weaker discipline is established for the case where the abstract side is machine-verified and total
and the concrete side is unmodeled, or whether the honest answer is that the residue stays in the
trust channel and no amount of totality buys it down.

Why it does not block. Sub-phase 4d settles either way: the residue is disclosed as trust-channel
and discharged by construction plus a cover cell. An answer would tell us how much that disclosure
is worth, not what to build.

---

## Q-002  (2026-08-06)  Status: OPEN

For a per-resource discipline proved over an unindexed phase type, is there an established
characterization of exactly what breaks when the resource count goes above one, short of redoing
the proof in a concurrent logic?

Context. The driver's token discipline is proved over a phase type carrying no index, and the
reference obtains one token per hole. A serial wave keeps at most one hole live, so the index is
recoverable from context and the unindexed type is adequate. Under concurrent fills the property
itself stays expressible per hole, but the type has one slot where it needs an index, and the
cross-hole case (one hole's token held while another hole's agent works) is not expressible at all.
The campaign permits adding a concurrency surface later if serial wall-clock proves impractical,
which would invalidate the adequacy of a shipped proved module with nothing in that module to say
so.

The interesting half is not the concurrency proof, which is standard, but whether the *degradation*
has a name: a proof that is sound under a cardinality constraint, silent about the constraint, and
whose failure mode on relaxation is a type that is too coarse rather than a theorem that is false.
Owicki-Gries and rely-guarantee describe the destination. The question is whether anything describes
the transition, in a form that would let a module declare the cardinality it assumes.

Why it does not block. Concurrency is deferred by the campaign's own stop condition, and the
mitigation that matters (recording the single-threaded precondition on the proved module) is already
settled and needs no literature.
