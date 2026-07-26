# Normativity rubric: RFC 826

**Source.** `00-source/rfc826.txt`, sha256
`01bc62fe6a37e90f1246ac43e8e145f1322b4ed1474836145c3da93d2bd3c8a6`, 470 lines. Every line
reference in this document and in every row produced under it points into those exact bytes.

**Status.** Written at Stage C, before any clause has been extracted. No row exists yet. The rules
below were derived from the document's grammar and section structure and from a mechanical census
of its requirement words (§1), not from a reading of candidate clauses. If this rubric had been
written after extraction it would be a description of what was found rather than a rule that
decides, and the denominator would not be auditable.

---

## 0. What this rubric decides, and what it does not

This rubric answers one question per span of text: **is this a statement an implementation of
RFC 826 could conform to or violate?** If yes, the span yields one or more normative rows and each
row enters the denominator. If no, it is recorded as non-normative with the X rule that excluded
it.

Three things it explicitly does not decide:

1. **Whether a row can be formalized.** That is Stage B's question, already answered in
   `01-scope/scope.md`. A normative row that cannot be expressed in the chosen fragment is a
   **barrier entry**, not a non-normative row. It stays in the denominator and appears on the
   barrier list. See T10.
2. **How strong an obligation is.** Strength (mandatory, recommended, permitted, hedged) is
   recorded per row and is never a reason to leave the denominator. See §2 and N11.
3. **Whether an obligation is a good idea.** Rationale quality, security adequacy, and modern
   practice are out. A row that specifies behavior nobody should implement today is still a row.

**Label namespace warning.** `01-scope/scope.md` already uses `X1` through `X10` for its
*formalization exclusions*. This rubric's `X1` through `X10` are *non-normativity* rules and mean
something different. In any cross-stage citation write `C:X4` for this document and `B:X4` for
scope.md. Bare `X4` in a downstream artifact is a defect and should be rejected in review.

---

## 1. The date check

**RFC 826 is dated November 1982 (line 3). RFC 2119 is dated March 1997. This document predates the
requirement-word convention by roughly fourteen years, and it does not declare any equivalent
convention of its own.**

Mechanical census over all 470 pinned lines:

| Probe | Count |
|---|---|
| `MUST`, `SHOULD`, `MAY`, `SHALL`, `REQUIRED`, `RECOMMENDED`, `OPTIONAL` in uppercase | **0** |
| A "Conventions" or "Requirements language" section, or any phrase like "key words", "interpreted as described" | **0** |
| lowercase `must` | 5 (lines 23, 65, 166, 348, 457) |
| lowercase `should` | 8 (lines 70, 240, 289, 321, 353, 429, 430, 434) |
| lowercase `may` | 8 (lines 239, 294, 316, 361, 362 ×2, 415, 438) |
| `optional` / `optionally` | 3 (lines 205, 208, 291) |
| `need` / `needed` / `necessary` / `necessarily` / `requires` | 18 |
| `probably`, `perhaps`, `could`, `might`, `would` | 23 |

Two findings follow, and both shape the rules below.

**Finding 1: every normativity judgment on this document is interpretive.** There is no keyword to
read at face value. The rubric is doing all of the work, which is the reason it has to be numbered,
written first, and frozen.

**Finding 2: keying on requirement words would produce a denominator concentrated in the wrong
sections.** Of the five occurrences of `must`, one is in the abstract (23), one is an editorial
caution about host byte order (65), one is in a section about a monitor role (348), and one is in
prose about forgotten table entries (457). Of the eight occurrences of `should`, one is a postal
instruction (70) and three sit inside a passage the RFC itself places outside its scope (429, 430,
434). Meanwhile the two sections that actually specify the protocol, Packet Generation (161-190)
and Packet Reception (197-234), are written almost entirely in bare present indicative and bare
imperative with no modal at all.

Therefore: **in this document, grammatical mood is the primary carrier of obligation and modal
words are secondary.** N1 and N2 are the rules that generate most of the denominator. N3 exists to
catch the rest, not to define the set.

**Per-row consequence.** Every row records `requirement_word`: the modal actually present in the
span, verbatim and lowercase, or the token `imperative` or `indicative` when the span carries
obligation by mood with no modal, or `none`. Closed vocabulary, no synonyms, no normalization to
RFC 2119 keywords:

```
must | should | may | can | could | will | would | might |
need | needed | necessary | necessarily | requires |
optional | optionally | probably | perhaps | definitely | absolutely |
imperative | indicative | none
```

If a span carries more than one, record all of them in text order. **No row may be labeled `MUST`,
`SHOULD`, or `MAY` in uppercase.** Translating 1982 prose into RFC 2119 keywords silently upgrades
or downgrades obligations and destroys the evidence a later reader would need to check the call.

---

## 2. The unit: what counts as one row

A **row** is one obligation, recorded with this schema:

| Field | Content |
|---|---|
| `id` | `R###`, assigned in document order, never reused |
| `lines` | line range into the pinned bytes |
| `quote` | the span verbatim |
| `verdict` | `normative` or `non-normative` |
| `rule` | the N or X rule that fired, by number; more than one may be listed, the first is the deciding one |
| `requirement_word` | closed vocabulary from §1 |
| `strength` | `mandatory`, `recommended`, `permitted`, `hedged` (see T5), or `prohibited` |
| `class` | stratification class from §6 |
| `actor` | `sender`, `receiver`, `both`, `monitor`, `registrar`, `none` |
| `doubt` | `true` when the row is normative only because T7 fired |
| `governed_by` | `rfc826` unless T6 assigns a later RFC |

Splitting and merging:

- **Split (T1).** A span stating N obligations yields N rows. The test is independent violation: if
  an implementation could satisfy one part and violate another, they are separate rows. A sentence
  assigning several packet fields yields one row per field assignment.
- **Merge.** Several sentences elaborating a single obligation without adding a separately
  violable requirement yield one row, with the full span in `lines`.
- **Pseudocode.** A conditional yields one row for the guard and one row per action in its
  consequent. A branch whose failure ends processing yields the guard row plus a discard row (N7).
- **Field lists and tables.** Each field definition line is its own row.
- **Restatement.** A span that repeats an obligation already rowed elsewhere is not a new row; it
  is recorded as a cross-reference on the existing row. The exception is T4.

---

## 3. Normative rules

A span is **normative** if any of the following fires.

**N1. Imperative algorithm step.** A line in an algorithm or procedure block written in the
imperative mood ("Set ...", "Send ...", "Swap ...", "add the triplet ..."). The imperative is a
direct instruction to the implementation and is normative regardless of any hedge on the block as
a whole (see T5). `requirement_word: imperative`.

**N2. Present-indicative behavior of a named module.** A statement of what a named component of the
implementation does when the protocol runs ("the Address Resolution module then sets ...", "it
gives the corresponding address back to the caller", "it then causes this packet to be
broadcast"). In a pre-2119 document this mood is the primary specification voice. Reading it as
description rather than requirement would empty the denominator of exactly the material the RFC
exists to convey. `requirement_word: indicative`.

**N3. Explicit requirement word directed at the implementation.** `must`, `should`, `may`,
`optional`, `optionally`, `is needed`, `is necessary`, `requires`, applied to something an
implementation does or emits. Normative whatever the mood, with `strength` recorded from the word.
This rule is a supplement to N1 and N2, not the main generator. A requirement word directed at a
human, a registrant, or a reader is not covered here (see X4, T8).

**N4. Packet format definition.** Field name, bit or byte width, position in the packet, presence,
and any rule that derives one field's width from another field's value. Each is normative because
a nonconforming packet is observable on the wire.

**N5. Constant and code point value.** A named value and the number bound to it, including protocol
type field values, opcode values, and hardware type values. A wrong value is a wire-visible
violation, so the binding is a requirement and not a naming convenience. Contrast X3: announcing a
shorthand name with no value attached is metadata.

**N6. Encoding, byte order, and padding.** Statements about transmission order of multi-byte
fields, which fields are treated as words, and the absence of padding between fields. Two
implementations that disagree here do not interoperate, so these are requirements.

**N7. Guard and its discard consequence.** A test whose outcome gates further processing. The guard
is one row. The behavior on the failing branch, including "end of processing and a discarding of
the packet", is a second row, class `DISC`. Error and exception behavior is normative even when
the RFC states it once in a preamble to a block rather than at each branch; in that case the
preamble is the row and each branch cross-references it.

**N8. Table state transition.** Creation, update, supersession, and the identity of the key under
which an entry is stored. The condition under which an entry is added rather than updated is a
separate row from the update itself (T1).

**N9. Emission trigger and delivery scope.** When a packet is generated, and whether it is
broadcast or sent to a specific hardware address, and on which hardware it goes out. Delivery
scope is normative and separately violable from packet contents, so it is always its own row.

**N10. Intra-algorithm ordering constraint.** A statement that one step happens before another
("before the opcode is looked at", "NOW look at the opcode"), where the order has an observable
consequence. An implementation can violate an ordering constraint while satisfying every
individual step, so the ordering is its own row.

**N11. Permission and optional behavior.** A span that permits rather than commands ("it could set
... if that makes it convenient", "optionally check ..."). Normative, `strength: permitted`.
Permissions carry two testable obligations: the actor is not in violation for exercising the
option, and no counterparty may require it. Optional behavior counts in the denominator. Excluding
permissions would let a rubric shrink the denominator by reclassifying the hardest rows as
non-requirements.

**N12. Generalization and parameter binding.** Rules that say what a field takes for a particular
hardware type, and what changes when the hardware is not the one the document was written for.
These constrain conforming implementations on both the original and the generalized medium.

**N13. Hedged-but-operative specification.** Text presented as approximate or suggested ("an
algorithm similar to the following", "the suggested processing algorithm") that is nonetheless the
document's only statement of the behavior. Normative, `strength: hedged`. See T5 for how the hedge
is honored without demoting the row.

**N14. Invariant an implementation could violate.** A property asserted of packets, tables, or
mappings that an implementation could construct a state to break, such as a uniqueness or
functionality condition on stored entries. Normative. Contrast X5: a property asserted of the
outside world that the implementation neither maintains nor checks is not an invariant of the
implementation.

---

## 4. Non-normative rules

A span is **non-normative** only if one of the following fires and no N rule and no tie-break
overrides it. Every non-normative verdict cites an X rule by number. "Reads like prose" is not a
verdict.

**X1. Motivation and rationale.** Text explaining why a design choice was made, where the choice
itself is stated as a requirement elsewhere in the document. Includes cost arguments, comparisons
with rejected alternatives, and appeals to simplicity. Subject to T4: rationale that is the only
statement of a behavior is promoted.

**X2. Example and illustrative trace.** A concrete walkthrough with named machines and named
addresses that restates behavior specified elsewhere. Non-normative per step, and each step is
recorded as a cross-reference on the row it illustrates so that the mapping is checkable. Subject
to T4.

**X3. Document metadata.** Title, author, affiliation, postal address, network mailbox, date, RFC
number, abstract framing, status disclaimers, acknowledgements, editorial notes in brackets,
section headings, and announcements of naming shorthand that bind no value. A statement about what
this document is or how it will refer to something is not a statement about what an implementation
does.

**X4. Administrative and registry process.** Instructions about who manages a name space, where to
send allocation requests, and what authority is needed. These constrain a registrant or an
administrator, not a packet or a state machine. See T8.

**X5. Statements about the world or another protocol not imposed on the implementation.** Behavior
of the underlying hardware, properties of address spaces belonging to other protocols, claims about
how addresses are allocated or are "supposed to be", market and deployment observations. These are
premises the document reasons from. Where a later stage relies on one, it is an assumption in
`scope.md` §7 and is labeled there, which is exactly why it must not also be counted as an
obligation here.

**X6. Self-declared out-of-scope text.** A passage the document itself places outside the protocol.
Non-normative even when it contains `should`, `may`, or an imperative, because the exclusion is
stated in the text rather than inferred by this rubric. This is the one place where an explicit
requirement word does not trigger N3. The exclusion must be quoted in the row's notes; without a
quotable disclaimer, X6 does not apply and T7 governs instead.

**X7. Speculative and deliberative prose.** Text that proposes an approach without fixing one:
"perhaps", "it may be desirable", "another alternative is", "this issue clearly needs more
thought", alternatives offered in the same breath as each other. The marker is disjunction without
resolution. If the text offers alternatives and then settles on one, the settlement is normative
under N2 or N3 and only the survey is excluded.

**X8. A role other than the specified implementation.** Text describing what a monitor, debugger,
daemon, or diagnostic tool does, where that role is optional tooling rather than the protocol
participant being specified. Guarded: if such text imposes an obligation on wire behavior that a
protocol participant would have to honor, the guard fails and the span is normative under N9 or
N7.

**X9. Prior practice and counterfactual narration.** Descriptions of what implementors currently
do, what a rejected design would have done, or what would happen under parameters the document does
not adopt. Historical and deprecated text falls here.

**X10. Bare cross-reference.** "See below", "described later", "discussed above", pointers with no
obligation attached.

---

## 5. Tie-breaks

These are applied in order. A later tie-break overrides an earlier verdict only where it says so.

**T1. One obligation per row.** The atomicity rule of §2. Test: could an implementation satisfy one
part and violate the other? If yes, split. Rows are cheap; a compound row is unprovable and
unauditable, and it hides a failure inside a pass.

**T2. Definition versus metadata.** A definition is **normative when an implementation could
violate it** and **metadata when it only names a thing**. Operational test: construct an
implementation that contradicts the definition. If the contradiction is detectable on the wire or
in the implementation's state, the definition is normative (N4, N5, N14). If the contradiction is
merely a different word for the same object, it is metadata (X3).

**T3. A status disclaimer does not de-normativize the body.** The document's own hedge about its
standing (lines 45-50, "This is not the specification of a Internet Standard") is metadata under
X3 and has no effect on any other row. The body specifies behavior in the imperative and the
indicative, and it is read that way. This matters concretely: RFC 826 was later elevated and is
STD 37. **That status is external to the pinned bytes**, so it is recorded here as a claim to be
confirmed against the RFC Editor index rather than asserted from the source, and no row depends on
it. The rule stands either way: a document that specifies wire behavior yields normative rows
whatever it calls itself.

**T4. Rationale-only and example-only obligations are promoted.** If a behavior appears nowhere
except in a why-section or a worked example, X1 and X2 do not fire and the span is normative. This
is the most common way a rubric under-counts: the specification sections are terse, and a detail
that appears only in the discussion is still the document's only statement of it. When T4 fires,
record it in the row's notes so the promotion is visible.

**T5. A hedge on an algorithm does not demote its steps.** Where the document presents a procedure
as approximate or suggested but supplies no other definition of the behavior, the steps are
normative (N13) with `strength: hedged`. The hedge is honored in a different place: it is what
lets a conforming implementation differ in unobservable internals. Externally observable effects,
the packets emitted and the table state reached, are held to the text. An implementation that
skips a step and produces a different packet is not "similar to the following".

**T6. A later amending RFC governs on conflict.** Where RFC 826's text conflicts with an RFC that
updates it, the later text decides what the obligation is. The row remains in this denominator with
`governed_by` set to the amending RFC, and the RFC 826 wording is retained in `quote` so the change
is visible. Two limits: an amending RFC **cannot add rows** to this denominator, which counts
RFC 826's obligations only; and a row that an amendment deletes outright is kept with
`strength: prohibited` or a superseded note rather than dropped, because dropping it would let the
denominator move after the fact. **The amendment list is external to the pinned bytes.** The known
updating RFCs are believed to be RFC 5227 (IPv4 address conflict detection) and RFC 5494 (IANA
allocation guidelines for ARP); this must be confirmed against the RFC Editor index before any row
sets `governed_by`, and no row may cite an amendment that has not been confirmed and recorded.

**T7. When in doubt, mark normative.** Doubt means: two readings of the span would produce
implementations that differ observably, and the text does not settle which is meant. In that case
the row is normative and `doubt` is set to `true`. Doubt is not the same as a stated exclusion
(X6) or a stated hedge (T5); both of those are settled by the text and are handled by their own
rules. This tie-break overrides every X rule.

**T8. Split by actor; a non-implementation actor is not an obligation.** A span constraining a
sender and a receiver differently splits into two rows under T1, each with its own `actor`. A span
whose only actor is a human, a registrant, an administrator, or an operator yields a non-normative
row under X4, regardless of the requirement word it contains.

**T9. Negative and absence statements are normative when they constrain.** "There is no padding
between fields", "it does not set this field to anything in particular", "it has no meaning in
this form" all constrain an implementation: the first fixes the encoding, the second releases the
sender from a constraint (N11), and the third forbids the receiver from relying on a value. Each
is a row. An absence statement is only non-normative when nothing follows from it for either side.

**T10. Normative and formalizable are different questions.** A row that this rubric marks normative
and that `01-scope/scope.md` places outside the fragment is a **barrier entry**: it counts in the
denominator, it is never discharged, and it appears by `id` on the closed barrier list with the
specific reason (sequences, arithmetic, order, quantifier structure). It is not reclassified as
non-normative. Any downstream artifact that moves a row out of the denominator by citing a
formalization limit is reporting a scope failure as a rubric result, and is wrong.

---

## 6. Stratification classes

Every normative row carries exactly one class. The gate measures coverage per class, so the classes
must be assigned by the rubric rather than invented at reporting time. Where a row could take two,
assign the one naming what the row constrains, not what it mentions.

| Class | Covers |
|---|---|
| `FMT` | packet field definitions, widths, order, derived lengths |
| `ENC` | byte order, word boundaries, padding |
| `CONST` | named constants and code point values |
| `GEN` | sender-side packet construction and field assignment |
| `RECV` | receiver-side processing steps and their ordering |
| `TBL` | translation table state: add, update, supersede, key |
| `DISC` | discard, end of processing, error and exception behavior |
| `DELIV` | delivery scope, broadcast versus directed, egress link |
| `PARAM` | hardware and protocol generalization, parameter bindings |
| `INV` | invariants over packets, tables, and mappings |

A class with zero rows at the end of extraction is a finding to report, not a blank cell. It means
either the document says nothing in that area, which is itself worth stating, or the extraction
missed a section.

---

## 7. The consequence of the conservative tie-break

T7 deliberately over-includes. Rows enter the denominator that a careful reader might have called
rationale, tooling, or commentary, and many of them will disposition out later as barriers,
duplicates, or obligations with no observable content. This is intended and it has a specific
price, stated here so nobody discovers it in the writeup:

1. **The denominator is safe.** Over-inclusion cannot hide an obligation. The failure this ordering
   prevents is the one that matters: a clause quietly judged non-normative, never extracted, never
   proved, and never counted, so that the ledger reports full coverage of a set that was trimmed to
   fit what succeeded.
2. **The exclusion ratio is meaningless.** Because T7 pushes ambiguous material into the normative
   set, and because barriers stay in the denominator under T10, the fraction of rows excluded or
   dispositioned out measures the rubric's conservatism, not the document's structure or the
   verification's quality. **No artifact downstream of this rubric may report an exclusion
   percentage, a coverage percentage over the raw denominator, or a "rows carried / rows found"
   ratio as a quality signal.** A ratio ceiling is not a gate condition and never becomes one.
3. **What the gate measures instead.** Class-stratified coverage from §6, plus a closed barrier
   list: every row not discharged appears by `id` with a named reason, and the list is complete. A
   result is judged by whether every class has been addressed and whether every gap is on the list,
   not by how large a fraction of rows survived.
4. **The over-inclusion is countable.** Because `doubt` is recorded per row, the number of rows
   that are normative only by T7 is a number, not an impression. Report it. It is the correct way
   to state how much the conservative default is carrying, and it lets a reviewer re-run the
   judgment on exactly those rows without re-reading the document.

---

## 8. Application shapes

Abstract shapes only, written before extraction so that no rule is fitted to a clause. The first
matching shape decides; if none matches, apply §3 and §4 directly, then §5.

| Shape | Verdict | Rule | Class |
|---|---|---|---|
| `<module> sets <field> to <constant>` | normative | N2, N5 | `GEN` |
| `Set <field> to <value>` inside a procedure block | normative | N1 | `RECV` |
| `?<test>` followed by branches, negative branch ends processing | 2+ rows: guard, discard | N7 | `RECV`, `DISC` |
| `<n>.bit: (<field>) <description>` | normative, one row per field | N4 | `FMT` |
| `<name> (= <number>)` | normative | N5 | `CONST` |
| `it could <action> if that makes it convenient` | normative, permitted | N11 | context |
| `X is included for completeness and network monitoring` | non-normative | X1 | n/a |
| `Let there exist machines X and Y ...` and everything following it in that block | non-normative, cross-referenced | X2 | n/a |
| `The implementation of these is outside the scope of this protocol` and its passage | non-normative | X6 | n/a |
| `<property> are supposed to be <property>` about the hardware | non-normative | X5 | n/a |
| A behavior stated only in a why-section | normative | T4 over X1 | context |
| A step stated only inside the worked example | normative | T4 over X2 | context |
| Anything the rubric cannot place | normative, `doubt: true` | T7 | best fit, noted |

---

## 9. Rubric failure protocol

1. **Frozen at Stage C.** The rules above are the rules extraction runs under. They may be
   clarified, never narrowed, once extraction has begun.
2. **Changes are dated and retroactive.** Any change gets an appended entry in §10 stating what
   changed, why, and which rows were re-classified. Every already-classified row is re-scanned
   under the amended rule. A rule changed without a re-scan invalidates the denominator.
3. **New rules surface, they do not hide.** If a span matches nothing here, do not improvise a
   verdict. Add a numbered rule with a written justification, then re-scan. A rule added late is
   still a rule; an unnumbered judgment is not.
4. **Every verdict cites a number.** No row carries `non-normative` without an X rule, and no row
   is promoted or demoted without a T rule. Rows failing this check are rejected in review.
5. **Report the rule-firing counts.** How many rows each N, X, and T rule produced. A rule that
   fired zero times and a rule that fired on nearly everything are both worth seeing, and both are
   invisible in a total.
6. **The census is reproducible.** The word counts in §1 were produced by a mechanical scan over
   all 470 lines, not by selection. Anyone auditing this rubric can regenerate them from the pinned
   sha256 and get the same table.

---

## 10. Amendment log

None. The rubric is at its Stage C state.
