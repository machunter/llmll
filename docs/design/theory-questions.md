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

---

## Q-003  (2026-08-07)  Status: OPEN

When a caller must decide whether it may rely on a callee, is reliance a property of the callee's
postcondition *tier* or of its body's *completeness*? If the former, a fill-state field is redundant
beside a trust label and the redundancy is a hazard rather than a convenience.

Context. The checkout brief carries two fields per available function: `status`, a fill-state enum,
and `tier`, the effective-level trust label. HOLE-STATUS-SIBLING makes `status` truthful for
siblings whose body is still a hole, on the reasoning that such a body is body-fallback and its post
is asserted rather than proved. But that reasoning derives the fill-state signal *from* the tier,
which raises the question of whether `status` carries anything `tier` does not. The two come apart
only if there is a case where a body is complete and the post is still asserted, or incomplete and
the post is verified. The first is common (a `def-shell` with a complete body). The second should be
impossible, and if it is impossible then fill-state is a strictly coarser view of the same fact.

The sharper form. Under assume-guarantee a caller relies on the callee's *contract*, never on its
body, so reliance ought to be tier-indexed by construction and body-completeness ought to be
irrelevant to soundness while remaining relevant to whether the whole program ever terminates in a
verified state. If that is right, `status` is a progress signal and not a soundness signal, and it
should be documented as one. The literature on assume-guarantee decomposition presumably settles
whether a partially-realized component is distinguishable from an asserted one at the level of the
proof rule.

Why it does not block. The proposed patch (HOLE-STATUS-SIBLING, not implemented as of this entry)
would mark unfilled siblings and change nothing about what a caller may assume; both fields are
already emitted and neither gates anything in the compiler. An answer would tell us which field the
agent-facing documentation should teach as authoritative, not what to emit.

---

## Q-004  (2026-08-07)  Status: OPEN

Is there an established treatment of vocabulary that is *offered* to a synthesizer but
*guaranteed-unusable* in the position it is offered for? Specifically, whether the honest move is to
withhold it, to offer it with an accurate label, or to make the offer depend on the enclosing
context.

Context. The checkout brief lists available functions for a hole. For a hole inside a strict-core
`def`, `TypeCheck.checkCalleeAdmissibility` will reject any call to a callee lacking persisted
verified evidence, so an unfilled sibling in that list is vocabulary the agent cannot use and will
only discover it cannot use by having its patch rejected. For a hole inside a `def-shell` the same
call is accepted, and `refine`'s cascading decomposition depends on exactly that: it spawns
contracted sub-holes which are meant to be called before they are filled. So the same list entry is
useful in one enclosing context and a guaranteed dead end in the other, and the brief does not
currently know which context it is assembling for.

Withholding breaks cascading refinement. Offering with a label (the shipped choice) costs the agent
a rejected attempt against its error budget, which is a real cost because a fill protocol that
budgets semantic retries separately from protocol retries will charge this to the wrong one.
Context-dependent offering makes the brief's contents a function of the enclosing definition's form,
which is more accurate and less predictable. The question is whether synthesis or program-repair
literature has a name for this trade and a default.

Why it does not block. The proposed patch (HOLE-STATUS-SIBLING, not implemented as of this entry)
takes the middle option, which is strictly more information than the status quo under either answer,
and the enclosing form is available at assembly time if the answer later favours context-dependence.
An answer would refine an agent-facing affordance, not the compiler's behaviour.
