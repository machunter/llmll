# Stage D: clause extraction (extractor A)

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
  "extractor": "A",
  "normative": [
    {
      "id": "A1",
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
      "id": "Ax1",
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

# Rubric: which sentences of RFC 826 are normative

**Stage C artifact. Written before any clause has been extracted.**

Source: `00-source/rfc826.txt`, sha256 `01bc62fe6a37e90f1246ac43e8e145f1322b4ed1474836145c3da93d2bd3c8a6`,
470 lines. Hash and line count re-verified against `00-source/PROVENANCE.json` at the time this
document was written. All line references are to that pinned file.

This document states the rule that decides normativity, and therefore produces the denominator of
every coverage claim this run makes. It is written before extraction so that the denominator is the
output of a stated rule rather than a byproduct of whatever was convenient to extract. Section 10
records the pre-commitments that make the ordering checkable after the fact.

---

## 0. The date check, and what it costs

RFC 826 is dated November 1982 (line 3). RFC 2119 is March 1997, fourteen years later. **RFC 826
predates the MUST/SHOULD/MAY discipline entirely, declares no keyword convention, and contains no
uppercase requirement words.** Every normativity judgment on this document is therefore
interpretive, and this rubric is doing all of the work.

Verified by direct count over the pinned text:

- Uppercase `MUST`, `SHALL`, `SHOULD`, `REQUIRED`, `RECOMMENDED`, `MAY`, `OPTIONAL`, `NOT`: **zero
  occurrences, all 470 lines.**
- The all-caps tokens that do occur are protocol and opcode names (`REQUEST` 11, `REPLY` 7,
  `CHAOS`, `PUP`, `TCP`, `TELNET`, `SUPDUP`, `ADDRESS`/`RESOLUTION`, `TYPE`), address and host
  abbreviations from the worked example (`IPA`, `EA`, `ET`, `IP`), organisational names (`DOD`,
  `DEC`, `ARPA`, `MIT`, `MC`, `SCRC`, `MOON`, `DCP`, `PDP`, `RFC`, `BSP`), and exactly two emphasis
  words: `NOW` (line 219) and `AFTER` (line 309). **None of these is a requirement word**, and a
  keyword-shaped extractor pointed at this document would return opcode names.

Lowercase modal inventory over the pinned text: `will` 23, `can` 12, `should` 8, `may` 8,
`probably` 6, `could` 6, `perhaps` 5, `must` 5, `would` 4, `necessary` 3, `need`/`needs` 3,
`optionally` 2, `might` 2.

The thirteen `must`/`should` occurrences land at lines 23, 65, 70, 166, 240, 289, 321, 348, 353,
429, 430, 434, 457. Read those positions: one is in the abstract describing Ethernet hardware, one
is a caution to implementors about host byte order, one directs where to mail a registry request,
one is parenthetical about which software layer calls the module, four sit inside the section the
RFC declares outside its own scope, and the remainder sit in rationale prose. Meanwhile the
document's densest obligations, the reception algorithm at lines 203 to 225, contain **no modal at
all**: they are bare imperatives and bare conditionals.

**Consequence, and it is the reason this file exists:** requirement-word presence in RFC 826 is
close to anti-correlated with obligation. The word cannot decide the row. So:

> **W-RULE.** Every row records field `W`, the requirement word actually present, verbatim, or one
> of the `none-*` codes of section 3. `W` is **recorded on every row and used as the deciding test
> on none of them.** Recording it is what lets a reviewer check that the classification did not
> secretly track the keyword, and lets a reader of the final writeup see the interpretive distance
> between this document and a post-1997 RFC.

`W` codes, closed list:

| code | meaning | example shape in this document |
| --- | --- | --- |
| `W:<token>` | a lowercase modal appears in the unit; record it verbatim | `W:should`, `W:may`, `W:optionally`, `W:could`, `W:probably` |
| `W:none-imperative` | imperative mood, no modal | "Set the ar$op field to ares_op$REPLY" |
| `W:none-indicative` | present indicative describing what the module does | "It then causes this packet to be broadcast" |
| `W:none-declarative` | definitional or format statement | "16.bit: (ar$op) opcode" |
| `W:none-conditional` | a guard line in the algorithm block | "?Am I the target protocol address?" |

---

## 1. What this rubric decides, and what it is forbidden to consider

**Decides:** for each candidate unit of text, whether it is **normative** (it constrains an
implementation) and therefore enters the denominator.

**Does not decide, and must not be influenced by:**

1. **Verification scope.** `01-scope/scope.md` fixes what the model carries. That is a different
   axis. A unit can be normative and outside the verification boundary; it stays in the denominator
   and takes a named barrier at disposition time. **No X rule in section 4 may cite scope.md, and
   "out of scope" is never a reason to mark a unit non-normative.** This is the firewall, and it
   matters here specifically because Stage B was written first and already names clauses it intends
   to exclude. Those exclusions are dispositions, not normativity judgments.
2. **Provability, fragment membership, difficulty, or cost.** A unit that needs arithmetic, a clock,
   or a byte model is normative if it constrains an implementation. It is counted, then it is
   dispositioned out with a reason.
3. **Standards-track force.** Line 50 says "This is not the specification of a Internet Standard."
   That is a statement about the document's authority, not about whether its sentences constrain an
   implementation. Normativity here means: *an implementation could comply with this sentence or
   fail to*. It does not mean *a standards body will enforce it*. If authority decided normativity,
   this document would have an empty denominator and the run would be vacuous.
4. **Hedging in the document's own framing.** Line 199 offers "an algorithm similar to the
   following" and line 307 calls it "the suggested processing algorithm". Under T5 the hedge is
   recorded in the row's `strength` field and does not remove the row. The hedge is real and it is
   carried forward into the conditional form of every property claim (Stage B, F2); it is handled
   there, once, and not a second time by quietly shrinking the denominator here.
5. **Severity or interest.** A boring obligation counts the same as an attack-relevant one.

---

## 2. The single test underneath every rule

> **The violability test.** A unit is normative when an implementation could violate it: when there
> exists a program that parses, emits, or behaves in a way the unit forbids or fails to do what the
> unit requires, and that difference is observable on the wire or in the implementation's
> externally visible state.

N1 through N10 are the shapes that test takes in this document. X1 through X9 are the shapes of
text that fails it. When a unit is genuinely ambiguous under the test, T11 fires and the unit is
normative with `doubt=1`.

Two boundaries on the test, stated now because both are easy to slide:

- **Violable by an implementation of this protocol.** Text that constrains a human, a registry, a
  reader, or another protocol's implementers fails the test (X6, X4).
- **Present in the text.** The test asks whether *this sentence* constrains an implementation, not
  whether the protocol *would need* such a constraint to be safe. Missing obligations are gaps, not
  rows. See T12; it is the necessary counterweight to T11.

---

## 3. Segmentation: what a row is made of

**U1. Prose.** The base unit is the sentence. Split further per T1 when one sentence carries more
than one obligation; merge per T2 when one obligation is spread over consecutive sentences.

**U2. The packet format block (lines 135 to 155).** One unit per field line. The two framing lines
("Ethernet transmission layer", "Ethernet packet data") are units, since they assign fields to
layers.

**U3. The algorithm block (lines 203 to 225).** One unit per guard line and one per action line,
following the block's own indentation. The blank-else convention of lines 200 to 201 is handled by
T7.

**U4. Definition lists (lines 115 to 126).** One unit per named constant.

**U5. Regions classified wholesale by an X rule** may be recorded at region granularity: one X row
carrying a line range and the rule that covers it, rather than one row per sentence. N rows are
never collapsed this way; they are always one obligation each. This keeps the artifact finite
without letting anything vanish: **every region of the 470 lines is accounted for by at least one
row, N or X.** The denominator is a filter over a visible list, not a silent selection.

**U6. Anchors are mandatory.** Every row cites line numbers in the pinned file and quotes the span
verbatim. A row without a line anchor is not a row.

### Row schema

| field | values |
| --- | --- |
| `id` | `R###`, stable, never reused or renumbered |
| `lines` | line range in the pinned file |
| `quote` | verbatim span |
| `principal` | `sender`, `receiver`, `either`, `monitor`, `registry`, `reader` |
| `normative` | `yes` (in denominator) or `no` |
| `rule` | exactly one primary `N#` or `X#`; secondaries listed separately |
| `W` | per section 0 |
| `strength` | `mandatory`, `suggested`, `permitted`, `unconstrained` |
| `doubt` | `0`, or `1` when T11 decided the row |
| `class` | one of `C1`..`C11`, closed list, section 8 |
| `on-false` | for guard rows: the behavior when the guard fails (usually discard, per T7) |
| `corroborated-by` | line refs to restating prose that did **not** create its own row (T6) |
| `flags` | `example-only`, `rationale-origin`, `self-excluded` where T8, T6, T10 apply |

`strength` is descriptive, never a filter. `mandatory` and `suggested` rows sit in the same
denominator; the field exists so the writeup can say which obligations the document actually
insisted on and which it merely proposed.

---

## 4. Normative rules

**N1. Imperative protocol behavior.** A unit directing an implementation to perform or refrain from
an externally observable action: transmit, broadcast, discard, set a field, consult a table, give a
value back to a caller. Covers the imperative mood, the present indicative used to describe module
behavior ("It then causes this packet to be broadcast"), and modal prose.

**N2. Conditional behavior: guard plus consequent.** A unit of the form *when condition C holds, do
A*. The guard is normative because an implementation can test the wrong thing; the consequent is
normative because it can do the wrong thing. Guards and consequents are separate rows (T1) linked
by `on-false`.

**N3. Failure and exception behavior.** What happens when a test fails, a lookup misses, or an input
is unrecognised: end processing, discard the packet, inform the caller, fall back to a broadcast
request. Explicit discard semantics are normative; so is a stated absence of recovery.

**N4. Packet format.** Any unit fixing a field's existence, name, position in the sequence, width,
layer, or admissible value set; and the encoding rules over those fields, including byte order and
padding. An implementation that emits a different layout is violating a format statement, so format
statements pass the violability test without argument.

**N5. Constant and enumeration bindings.** A named constant bound to a value, or a name introduced
as a member of a field's value set. An implementation that picks a different number is
non-interoperable, which is violation.

**N6. Field content and meaning.** A declarative unit fixing what value a sender places in a field,
or what a receiver may take a field to denote ("hardware address of sender of this packet"). These
read as definitions and behave as obligations: they are the entire content of the format's
semantics, and an implementation can fill a field wrongly.

**N7. Permissions and options.** A unit granting latitude: an optional check, a value a sender "could"
use, a behavior stated as available rather than required. Normative because it bounds the space a
conforming implementation may occupy and therefore what a peer must tolerate. Recorded with
`strength = permitted`. Where the document makes a check optional, both settings conform, and the
gate must treat each setting as a case to cover rather than picking the convenient one.

**N8. Ordering constraints among processing steps.** A unit fixing the order in which an
implementation performs internal steps, where that order is externally observable. Interleaving is
violable and the document is explicit that one particular ordering is intended.

**N9. State and table semantics.** A unit constraining what an implementation records, updates,
replaces, or removes in its translation table, and under which condition. The table is not a wire
artifact but its contents determine later transmissions, so table statements are observable.

**N10. Parameter bindings for a named medium or protocol.** A unit fixing concrete values for a
specific hardware or protocol type, or generalising a field's interpretation to other hardware. An
implementation on that medium can violate the binding.

---

## 5. Non-normative rules

**X1. Motivation and rationale.** Text explaining why a design choice was made, what alternatives
were rejected, and what the choice costs or saves. Distinguishing marks: it argues rather than
directs, and deleting it changes no implementation. Where rationale restates a rule, T6 governs;
where rationale states a rule found nowhere else, it is normative under the relevant N rule and
carries `flags: rationale-origin`.

**X2. Examples and illustrative traces.** Worked scenarios with named participants, and the
concrete field values inside them. An example instantiates obligations; it does not create them.
Exception at T8.

**X3. Document metadata.** Title, author, affiliation, postal and network address, date, RFC number,
abstract, acknowledgements, editorial notes about the document's status, section headings,
typographic structure.

**X4. Statements about another protocol, another document, or the physical world.** Address widths
of CHAOS, PUP, and Internet; what the 10Mbit Ethernet specification requires; the claim that 48-bit
Ethernet addresses are unique and fixed for all time. These are facts the document relies on, not
obligations it imposes. They are recorded because a false one would invalidate reasoning built on
it, but they are not implementation obligations and do not enter the denominator.

**X5. Text the document declares outside its own scope, and deliberative text.** A region the RFC
itself places out of scope yields no normative row even where the prose inside it looks imperative.
Deliberative markers: "It may be desirable", "Perhaps", "Another alternative", "this issue clearly
needs more thought". The self-exclusion is recorded per T10 rather than deleted.

**X6. Obligations directed at parties other than an implementation.** Registry submissions,
instructions to readers, requests for comment, guidance to the community, appeals for future work.
Fails the violability test on the principal, not on the content.

**X7. Problem statement and deployment narrative.** Descriptions of the situation the protocol
addresses and trends motivating it. Argument and context, no directive content.

**X8. Pure restatement.** A unit that repeats an obligation anchored elsewhere and adds nothing.
Recorded as `corroborated-by` on the anchored row, not as a row of its own (T6).

**X9. Implementation conveniences framed as such.** Notes that a buffer may be reused or registers
saved, where the document presents the point as a property of the format rather than as a directive.
Where the same text can be read as a permission, T11 fires and it becomes an N7 row with `doubt=1`.

---

## 6. Tie-breaks

**T1. One obligation per row.** An obligation is one `(principal, condition, required behavior)`
triple. A sentence carrying two verbs directed at an implementation yields two rows. This is the
rule most responsible for the size of the denominator, so it is stated first and applied uniformly:
no collapsing several actions into one row because they occur together.

**T2. One row per obligation.** The converse. An obligation spread over consecutive sentences is one
row with the full line range, not one row per sentence.

**T3. A definition is normative when an implementation could violate it, and metadata when it only
names a thing.** Fixing a value, a width, a field's contents, or a term's extent in a way that
constrains behavior is normative (N4, N5, N6). Introducing a label purely so the prose can refer to
it later, with no constraint attached, is X3. The test is the same violability test, applied to the
definition rather than to an action.

**T4. A later amending RFC governs on conflict.** Where a later RFC that updates this one contradicts
it, the later text wins and the row records the conflict. RFC 826 is recorded by the RFC Editor as
updated by RFC 5227 and RFC 5494, and the protocol was later elevated to STD 37; **none of those
documents is pinned in this run**, so this tie-break does not fire anywhere in Stage D and no row
may cite an unpinned document as authority. It is stated because a rubric that silently omitted it
would look like it had judged RFC 826 to be the last word, which it is not. Introducing an amending
text later requires re-running Stage D against the enlarged pin, not patching rows in place.

**T5. Hedged obligations stay in.** "Should", "probably", "similar to the following", "suggested",
"perhaps" in the presence of a directive do not remove the row. The hedge goes in `strength`
(`suggested`), and `W` records the token. Rationale: in a pre-2119 document the hedge is as often
prose register as it is deliberate latitude, and there is no convention available to tell the two
apart. Excluding on hedges would let 1982 prose style set the denominator.

**T6. Rationale that restates a rule does not create a row.** The row is anchored at the behavioral
text, and the rationale lines are listed in `corroborated-by`. If the rationale states something
absent from the behavioral text, it creates its own row under the relevant N rule with
`flags: rationale-origin`, which is a signal that the document's normative content leaked into its
argument section and is worth reporting in the writeup.

**T7. Implicit else-branches are attributes, not rows.** Where the document states a blanket
convention that a failed test ends processing and discards the packet, that convention is **one**
N3 row. Each guard row then records the discard in `on-false` rather than spawning its own row.
Reason: the alternative inflates the denominator by construction (one free row per guard) while
adding no distinct obligation. The coverage consequence is stated now so the gate cannot be
weakened later: **the blanket row counts as covered only when every guard row's `on-false` behavior
has been verified.** Granularity was reduced; the obligation was not.

**T8. Example-only obligations.** An example creates no row (X2). If extraction finds an obligation
that appears *nowhere* except inside the worked example, a row is created, anchored at the example,
with `flags: example-only`. That flag is a finding about the document, not a normal row, and the
writeup names every one of them.

**T9. An explicit non-constraint is normative.** Where the document says a field is not set to
anything in particular, or that no padding exists, or that a value is deliberately unspecified, that
is a statement an implementation and its peers can violate: it licenses a sender and it removes
whatever a receiver might otherwise assume. Recorded with `strength = unconstrained`. This does
**not** license inventing the receiver-side corollary; see T12.

**T10. Self-exclusion is recorded, not deleted.** When the document declares a region outside its own
scope, the region gets an X5 row at range granularity carrying `flags: self-excluded` and the line
number of the sentence that does the excluding. T11 does not fire there: the document removed the
doubt itself, and that is the one form of external authority this rubric accepts, because it is the
document speaking about its own extent.

**T11. When in doubt, mark normative.** If after applying sections 4 and 5 a unit could reasonably
be read either way, it is normative, with `doubt=1`. No unit is left out because deciding it was
hard. `doubt=1` is a stratification key, never a filter.

**T12. Doubt about present text resolves to normative; absent text creates nothing.** T11 applies to
classifying a sentence that exists. It does not license writing a row for an obligation the document
*should* have contained. A missing constraint is recorded as a gap note in the writeup, outside the
denominator. Without this rule, T11 would let the analyst's own protocol design inflate the
denominator and then score coverage against it.

**T13. Principal before content.** Determine who the unit binds before classifying what it says.
Directive text aimed at a registry, a reader, or another protocol's implementers is X6 or X4 no
matter how imperative it reads.

**T14. No row is ever deleted.** A row that later proves misclassified is reclassified in place with
a dated amendment line stating the old value, the new value, and the reason. The denominator may
change only by amendment, never by silent edit, and never after Stage D publishes it except by
amendment.

---

## 7. Calibration cases, decided here

These are the places where the rubric will be under pressure. They are decided now, from the
document's headings and structure, so that Stage D cannot decide them in whichever direction is
convenient once the clause list is visible. Choosing them required looking at the document's shape,
which is a partial look at the text; that cost is accepted, because the alternative is deciding them
during extraction, which is the failure this stage exists to prevent.

| # | Case | Ruling |
| --- | --- | --- |
| K1 | The reception algorithm is offered as "similar to the following" (line 199) and "suggested" (line 307) | Normative. N1/N2/N9 rows, `strength = suggested`. T5. The hedge is carried by the F2 antecedent on every property claim, not by the denominator. |
| K2 | The byte-order note (lines 63 to 66) sits under "Notes" and is excluded by the verification scope | Normative, N4. The firewall of section 1.1 applies: scope exclusion is a disposition. It enters the denominator and takes a barrier. |
| K3 | The registry submission address (lines 68 to 75) contains "should" | Non-normative, X6, `principal = registry`. T13. A `should` aimed at a human is not an implementation obligation. |
| K4 | The monitoring and debugging section (lines 326 to 364) describes a monitor's behavior | Normative, `principal = monitor`, class C9. The monitor is an implementation and its described behavior is violable. Whether the run verifies the monitor is a disposition, not a normativity question. |
| K5 | The worked example (lines 367 to 410) is the only place several field values appear together | Non-normative, X2, one region row. T8 applies only if an obligation appears nowhere else. |
| K6 | The aging and timeout discussion (lines 412 to 470), which the document places outside its own scope | Non-normative, X5, region row, `flags: self-excluded`, citing the excluding sentence. T10. Four of the document's thirteen `must`/`should` tokens live here and none of them creates a row. |
| K7 | "Why is it done this way??" (lines 245 to 323), which restates several rules while arguing for them | X1 by default, with T6 governing restatement. Any N row found here carries `flags: rationale-origin` and is reported. |
| K8 | Statements that a field is deliberately unset, and that a sender may instead use a broadcast value | Two rows: one T9 non-constraint (`strength = unconstrained`) and one N7 permission (`strength = permitted`). T1 separates them. No third row for a receiver-side non-reliance obligation, because the document does not state one (T12). |
| K9 | Optional consistency checks | N7, `strength = permitted`. Both settings conform, so the gate covers this row only when both settings are covered. |
| K10 | Abstract, acknowledgements, and the bracketed editorial note about the document's status | X3, region rows. Line 50's "not the specification of a Internet Standard" is metadata about authority and does not move any other row (section 1.3). |

---

## 8. Classes for stratification

Closed list. Every row carries exactly one. The gate measures coverage **within** each N class, so a
run cannot look complete by covering the cheap classes.

| class | contents | N or X |
| --- | --- | --- |
| C1 | Constants and enumerations | N |
| C2 | Packet format: fields, widths, order, layers, encoding, padding | N |
| C3 | Field content and meaning | N |
| C4 | Sender side: generation, lookup miss, broadcast | N |
| C5 | Receiver side: dispatch guards and discard behavior | N |
| C6 | Table semantics: merge, add, supersede | N |
| C7 | Reply construction and transmission | N |
| C8 | Options, permissions, explicit non-constraints | N |
| C9 | Monitor role | N |
| C10 | Generalization and parameter bindings for a medium | N |
| C11 | Non-normative: metadata, rationale, examples, self-excluded, foreign-protocol facts | X |

Adding a class after extraction begins is an amendment to this file with a date and a reason, per
T14. Rows may not be moved between classes to flatten a coverage gap.

---

## 9. What the conservative tie-break costs

T11 deliberately over-includes. A unit that is arguably rationale and arguably an obligation becomes
an obligation. That systematically adds rows which later disposition out with reasons like "outside
the verification boundary", "needs a byte model", "needs a clock", "monitor role not modeled".

**The direct consequence: the exclusion ratio is meaningless.** "We covered 62% of normative
clauses" is not a fact about this run, because the denominator was inflated on purpose and the size
of the inflation is set by how aggressively T11 fired, which is a property of the rubric and not of
the protocol or the proof. Any ratio computed from these rows is uninterpretable, and the writeup
does not compute one. That is an accepted trade, and the reason it is acceptable is the asymmetry
between the two failure directions:

- An over-included row is **visible**. It sits in the table with a disposition and a reason, and a
  reviewer can argue that the disposition is wrong.
- An under-included row is **invisible**. A sentence never written down as a row cannot be argued
  about, and its absence is undetectable from the artifact. Nothing downstream can recover it.

A denominator that errs toward inclusion is auditable; one that errs toward exclusion is not. So the
rubric errs toward inclusion and pays for it in disposition labor.

**What replaces the ratio.** The gate measures, and only these:

1. **Class-stratified coverage.** Per N class in section 8: rows total, rows discharged, rows
   dispositioned, by barrier. An empty or near-empty class is reported as such and not averaged
   away against a full one.
2. **A closed barrier list.** Every normative row that is not discharged maps to one named barrier
   from a list fixed before disposition begins. A row whose barrier is "other", or whose barrier is
   invented to fit it, is a gate failure.
3. **Stratification by `doubt`, `strength`, and `principal`.** So a reader can see whether the
   discharged rows are the mandatory receiver obligations or the hedged permissions.

No ratio ceiling, no aggregate percentage, no single headline number.

---

## 10. Pre-commitments

Written before extraction so that the sequence rubric-then-extraction is checkable afterward.

**10.1 Regions predicted to yield normative rows**, derived from the document's headings alone:

| lines | region | prediction |
| --- | --- | --- |
| 63-66 | Notes: byte order | few N rows, C2 |
| 112-126 | Definitions | N rows, C1 |
| 128-155 | Packet format | N rows, C2 and C3; the densest region in the document |
| 158-190 | Packet Generation | N rows, C4 |
| 194-225 | Packet Reception | N rows, C5, C6, C7, plus the T7 blanket discard row |
| 227-242 | Notice paragraphs and Generalization | mostly T6 corroboration; Generalization yields C10 |
| 326-364 | Monitoring and debugging | N rows, C9 |

**10.2 Regions predicted to yield zero normative rows**: 1-50 (title, abstract, editorial note),
52-62 and 67-75 (notes other than byte order, registry), 77-110 (problem, motivation), 245-323
(rationale, subject to T6 and the `rationale-origin` flag), 367-410 (example, subject to T8),
412-470 (self-excluded).

**10.3 Predicted denominator size: 45 to 80 normative rows.** Registered as a calibration check, not
a target. Landing outside the band is not an error; failing to explain why is. If Stage D returns 20
rows, either T1 was applied loosely or whole regions were skipped. If it returns 200, segmentation
fragmented single obligations. Either way the explanation goes in the writeup and this file is
amended per T14, rather than the count being nudged toward the band.

**10.4 Falsifiers.** Any of the following means this rubric or the extraction that used it is wrong,
and the run reports that rather than adjusting quietly:

- Zero N rows from 128-155 or from 194-225.
- N rows from 245-323 or 367-410 without `rationale-origin` or `example-only` set.
- Any row lacking a line anchor, a `W` value, or a class.
- Any X row whose stated reason is scope, fragment membership, difficulty, or provability
  (section 1 firewall).
- Any row citing RFC 5227, RFC 5494, or STD 37 as authority while those documents are unpinned
  (T4).
- Any row deleted rather than amended (T14).
- Any coverage figure expressed as a single ratio over the whole denominator (section 9).

**10.5 Freeze.** Once Stage D publishes the row table, the denominator is frozen. Later stages may
add dispositions, barriers, and amendment lines. They may not add, remove, or renumber rows except
through a dated T14 amendment recorded in this file and in the row table.


## The pinned RFC text

Line numbers below are authoritative for the `lines` field.

```
===== rfc826.txt =====
    1| Network Working Group                                   David C. Plummer 
    2| Request For Comments:  826                                  (DCP@MIT-MC)
    3|                                                            November 1982
    4| 
    5| 
    6| 	     An Ethernet Address Resolution Protocol
    7|                             -- or --
    8|               Converting Network Protocol Addresses
    9|                    to 48.bit Ethernet Address
   10|                        for Transmission on
   11|                         Ethernet Hardware
   12| 
   13| 
   14| 
   15| 
   16| 
   17| 			    Abstract
   18| 
   19| The implementation of protocol P on a sending host S decides,
   20| through protocol P's routing mechanism, that it wants to transmit
   21| to a target host T located some place on a connected piece of
   22| 10Mbit Ethernet cable.  To actually transmit the Ethernet packet
   23| a 48.bit Ethernet address must be generated.  The addresses of
   24| hosts within protocol P are not always compatible with the
   25| corresponding Ethernet address (being different lengths or
   26| values).  Presented here is a protocol that allows dynamic
   27| distribution of the information needed to build tables to
   28| translate an address A in protocol P's address space into a
   29| 48.bit Ethernet address.
   30| 
   31| Generalizations have been made which allow the protocol to be
   32| used for non-10Mbit Ethernet hardware.  Some packet radio
   33| networks are examples of such hardware.
   34| 
   35| --------------------------------------------------------------------
   36| 
   37| The protocol proposed here is the result of a great deal of
   38| discussion with several other people, most notably J. Noel
   39| Chiappa, Yogen Dalal, and James E. Kulp, and helpful comments
   40| from David Moon.
   41| 
   42| 
   43| 
   44| 
   45| [The purpose of this RFC is to present a method of Converting
   46| Protocol Addresses (e.g., IP addresses) to Local Network
   47| Addresses (e.g., Ethernet addresses).  This is a issue of general
   48| concern in the ARPA Internet community at this time.  The
   49| method proposed here is presented for your consideration and
   50| comment.  This is not the specification of a Internet Standard.]
   51| 
   52| Notes:
   53| ------       
   54| 
   55| This protocol was originally designed for the DEC/Intel/Xerox
   56| 10Mbit Ethernet.  It has been generalized to allow it to be used
   57| for other types of networks.  Much of the discussion will be
   58| directed toward the 10Mbit Ethernet.  Generalizations, where
   59| applicable, will follow the Ethernet-specific discussion.
   60| 
   61| DOD Internet Protocol will be referred to as Internet.
   62| 
   63| Numbers here are in the Ethernet standard, which is high byte
   64| first.  This is the opposite of the byte addressing of machines
   65| such as PDP-11s and VAXes.  Therefore, special care must be taken
   66| with the opcode field (ar$op) described below.
   67| 
   68| An agreed upon authority is needed to manage hardware name space
   69| values (see below).  Until an official authority exists, requests
   70| should be submitted to
   71| 	David C. Plummer
   72| 	Symbolics, Inc.
   73| 	243 Vassar Street
   74| 	Cambridge, Massachusetts  02139
   75| Alternatively, network mail can be sent to DCP@MIT-MC.
   76| 
   77| The Problem:
   78| ------------
   79| 
   80| The world is a jungle in general, and the networking game
   81| contributes many animals.  At nearly every layer of a network
   82| architecture there are several potential protocols that could be
   83| used.  For example, at a high level, there is TELNET and SUPDUP
   84| for remote login.  Somewhere below that there is a reliable byte
   85| stream protocol, which might be CHAOS protocol, DOD TCP, Xerox
   86| BSP or DECnet.  Even closer to the hardware is the logical
   87| transport layer, which might be CHAOS, DOD Internet, Xerox PUP,
   88| or DECnet.  The 10Mbit Ethernet allows all of these protocols
   89| (and more) to coexist on a single cable by means of a type field
   90| in the Ethernet packet header.  However, the 10Mbit Ethernet
   91| requires 48.bit addresses on the physical cable, yet most
   92| protocol addresses are not 48.bits long, nor do they necessarily
   93| have any relationship to the 48.bit Ethernet address of the
   94| hardware.  For example, CHAOS addresses are 16.bits, DOD Internet
   95| addresses are 32.bits, and Xerox PUP addresses are 8.bits.  A
   96| protocol is needed to dynamically distribute the correspondences
   97| between a <protocol, address> pair and a 48.bit Ethernet address.
   98| 
   99| Motivation:
  100| -----------
  101| 
  102| Use of the 10Mbit Ethernet is increasing as more manufacturers
  103| supply interfaces that conform to the specification published by
  104| DEC, Intel and Xerox.  With this increasing availability, more
  105| and more software is being written for these interfaces.  There
  106| are two alternatives: (1) Every implementor invents his/her own
  107| method to do some form of address resolution, or (2) every
  108| implementor uses a standard so that his/her code can be
  109| distributed to other systems without need for modification.  This
  110| proposal attempts to set the standard.
  111| 
  112| Definitions:
  113| ------------
  114| 
  115| Define the following for referring to the values put in the TYPE
  116| field of the Ethernet packet header:
  117| 	ether_type$XEROX_PUP,
  118| 	ether_type$DOD_INTERNET,
  119| 	ether_type$CHAOS, 
  120| and a new one:
  121| 	ether_type$ADDRESS_RESOLUTION.  
  122| Also define the following values (to be discussed later):
  123| 	ares_op$REQUEST (= 1, high byte transmitted first) and
  124| 	ares_op$REPLY   (= 2), 
  125| and
  126| 	ares_hrd$Ethernet (= 1).
  127| 
  128| Packet format:
  129| --------------
  130| 
  131| To communicate mappings from <protocol, address> pairs to 48.bit
  132| Ethernet addresses, a packet format that embodies the Address
  133| Resolution protocol is needed.  The format of the packet follows.
  134| 
  135|     Ethernet transmission layer (not necessarily accessible to
  136| 	 the user):
  137| 	48.bit: Ethernet address of destination
  138| 	48.bit: Ethernet address of sender
  139| 	16.bit: Protocol type = ether_type$ADDRESS_RESOLUTION
  140|     Ethernet packet data:
  141| 	16.bit: (ar$hrd) Hardware address space (e.g., Ethernet,
  142| 			 Packet Radio Net.)
  143| 	16.bit: (ar$pro) Protocol address space.  For Ethernet
  144| 			 hardware, this is from the set of type
  145| 			 fields ether_typ$<protocol>.
  146| 	 8.bit: (ar$hln) byte length of each hardware address
  147| 	 8.bit: (ar$pln) byte length of each protocol address
  148| 	16.bit: (ar$op)  opcode (ares_op$REQUEST | ares_op$REPLY)
  149| 	nbytes: (ar$sha) Hardware address of sender of this
  150| 			 packet, n from the ar$hln field.
  151| 	mbytes: (ar$spa) Protocol address of sender of this
  152| 			 packet, m from the ar$pln field.
  153| 	nbytes: (ar$tha) Hardware address of target of this
  154| 			 packet (if known).
  155| 	mbytes: (ar$tpa) Protocol address of target.
  156| 
  157| 
  158| Packet Generation:
  159| ------------------
  160| 
  161| As a packet is sent down through the network layers, routing
  162| determines the protocol address of the next hop for the packet
  163| and on which piece of hardware it expects to find the station
  164| with the immediate target protocol address.  In the case of the
  165| 10Mbit Ethernet, address resolution is needed and some lower
  166| layer (probably the hardware driver) must consult the Address
  167| Resolution module (perhaps implemented in the Ethernet support
  168| module) to convert the <protocol type, target protocol address>
  169| pair to a 48.bit Ethernet address.  The Address Resolution module
  170| tries to find this pair in a table.  If it finds the pair, it
  171| gives the corresponding 48.bit Ethernet address back to the
  172| caller (hardware driver) which then transmits the packet.  If it
  173| does not, it probably informs the caller that it is throwing the
  174| packet away (on the assumption the packet will be retransmitted
  175| by a higher network layer), and generates an Ethernet packet with
  176| a type field of ether_type$ADDRESS_RESOLUTION.  The Address
  177| Resolution module then sets the ar$hrd field to
  178| ares_hrd$Ethernet, ar$pro to the protocol type that is being
  179| resolved, ar$hln to 6 (the number of bytes in a 48.bit Ethernet
  180| address), ar$pln to the length of an address in that protocol,
  181| ar$op to ares_op$REQUEST, ar$sha with the 48.bit ethernet address
  182| of itself, ar$spa with the protocol address of itself, and ar$tpa
  183| with the protocol address of the machine that is trying to be
  184| accessed.  It does not set ar$tha to anything in particular,
  185| because it is this value that it is trying to determine.  It
  186| could set ar$tha to the broadcast address for the hardware (all
  187| ones in the case of the 10Mbit Ethernet) if that makes it
  188| convenient for some aspect of the implementation.  It then causes
  189| this packet to be broadcast to all stations on the Ethernet cable
  190| originally determined by the routing mechanism.
  191| 
  192| 
  193| 
  194| Packet Reception:
  195| -----------------
  196| 
  197| When an address resolution packet is received, the receiving
  198| Ethernet module gives the packet to the Address Resolution module
  199| which goes through an algorithm similar to the following.
  200| Negative conditionals indicate an end of processing and a
  201| discarding of the packet.
  202| 
  203| ?Do I have the hardware type in ar$hrd?
  204| Yes: (almost definitely)
  205|   [optionally check the hardware length ar$hln]
  206|   ?Do I speak the protocol in ar$pro?
  207|   Yes:
  208|     [optionally check the protocol length ar$pln]
  209|     Merge_flag := false
  210|     If the pair <protocol type, sender protocol address> is
  211|         already in my translation table, update the sender
  212| 	hardware address field of the entry with the new
  213| 	information in the packet and set Merge_flag to true. 
  214|     ?Am I the target protocol address?
  215|     Yes:
  216|       If Merge_flag is false, add the triplet <protocol type,
  217|           sender protocol address, sender hardware address> to
  218| 	  the translation table.
  219|       ?Is the opcode ares_op$REQUEST?  (NOW look at the opcode!!)
  220|       Yes:
  221| 	Swap hardware and protocol fields, putting the local
  222| 	    hardware and protocol addresses in the sender fields.
  223| 	Set the ar$op field to ares_op$REPLY
  224| 	Send the packet to the (new) target hardware address on
  225| 	    the same hardware on which the request was received.
  226| 
  227| Notice that the <protocol type, sender protocol address, sender
  228| hardware address> triplet is merged into the table before the
  229| opcode is looked at.  This is on the assumption that communcation
  230| is bidirectional; if A has some reason to talk to B, then B will
  231| probably have some reason to talk to A.  Notice also that if an
  232| entry already exists for the <protocol type, sender protocol
  233| address> pair, then the new hardware address supersedes the old
  234| one.  Related Issues gives some motivation for this.
  235| 
  236| Generalization:  The ar$hrd and ar$hln fields allow this protocol
  237| and packet format to be used for non-10Mbit Ethernets.  For the
  238| 10Mbit Ethernet <ar$hrd, ar$hln> takes on the value <1, 6>.  For
  239| other hardware networks, the ar$pro field may no longer
  240| correspond to the Ethernet type field, but it should be
  241| associated with the protocol whose address resolution is being
  242| sought.
  243| 
  244| 
  245| Why is it done this way??
  246| -------------------------
  247| 
  248| Periodic broadcasting is definitely not desired.  Imagine 100
  249| workstations on a single Ethernet, each broadcasting address
  250| resolution information once per 10 minutes (as one possible set
  251| of parameters).  This is one packet every 6 seconds.  This is
  252| almost reasonable, but what use is it?  The workstations aren't
  253| generally going to be talking to each other (and therefore have
  254| 100 useless entries in a table); they will be mainly talking to a
  255| mainframe, file server or bridge, but only to a small number of
  256| other workstations (for interactive conversations, for example).
  257| The protocol described in this paper distributes information as
  258| it is needed, and only once (probably) per boot of a machine.
  259| 
  260| This format does not allow for more than one resolution to be
  261| done in the same packet.  This is for simplicity.  If things were
  262| multiplexed the packet format would be considerably harder to
  263| digest, and much of the information could be gratuitous.  Think
  264| of a bridge that talks four protocols telling a workstation all
  265| four protocol addresses, three of which the workstation will
  266| probably never use.
  267| 
  268| This format allows the packet buffer to be reused if a reply is
  269| generated; a reply has the same length as a request, and several
  270| of the fields are the same.
  271| 
  272| The value of the hardware field (ar$hrd) is taken from a list for
  273| this purpose.  Currently the only defined value is for the 10Mbit
  274| Ethernet (ares_hrd$Ethernet = 1).  There has been talk of using
  275| this protocol for Packet Radio Networks as well, and this will
  276| require another value as will other future hardware mediums that
  277| wish to use this protocol.
  278| 
  279| For the 10Mbit Ethernet, the value in the protocol field (ar$pro)
  280| is taken from the set ether_type$.  This is a natural reuse of
  281| the assigned protocol types.  Combining this with the opcode
  282| (ar$op) would effectively halve the number of protocols that can
  283| be resolved under this protocol and would make a monitor/debugger
  284| more complex (see Network Monitoring and Debugging below).  It is
  285| hoped that we will never see 32768 protocols, but Murphy made
  286| some laws which don't allow us to make this assumption.
  287| 
  288| In theory, the length fields (ar$hln and ar$pln) are redundant,
  289| since the length of a protocol address should be determined by
  290| the hardware type (found in ar$hrd) and the protocol type (found
  291| in ar$pro).  It is included for optional consistency checking,
  292| and for network monitoring and debugging (see below). 
  293| 
  294| The opcode is to determine if this is a request (which may cause
  295| a reply) or a reply to a previous request.  16 bits for this is
  296| overkill, but a flag (field) is needed.
  297| 
  298| The sender hardware address and sender protocol address are
  299| absolutely necessary.  It is these fields that get put in a
  300| translation table.
  301| 
  302| The target protocol address is necessary in the request form of
  303| the packet so that a machine can determine whether or not to
  304| enter the sender information in a table or to send a reply.  It
  305| is not necessarily needed in the reply form if one assumes a
  306| reply is only provoked by a request.  It is included for
  307| completeness, network monitoring, and to simplify the suggested
  308| processing algorithm described above (which does not look at the
  309| opcode until AFTER putting the sender information in a table).
  310| 
  311| The target hardware address is included for completeness and
  312| network monitoring.  It has no meaning in the request form, since
  313| it is this number that the machine is requesting.  Its meaning in
  314| the reply form is the address of the machine making the request.
  315| In some implementations (which do not get to look at the 14.byte
  316| ethernet header, for example) this may save some register
  317| shuffling or stack space by sending this field to the hardware
  318| driver as the hardware destination address of the packet.
  319| 
  320| There are no padding bytes between addresses.  The packet data
  321| should be viewed as a byte stream in which only 3 byte pairs are
  322| defined to be words (ar$hrd, ar$pro and ar$op) which are sent
  323| most significant byte first (Ethernet/PDP-10 byte style).  
  324| 
  325| 
  326| Network monitoring and debugging:
  327| ---------------------------------
  328| 
  329| The above Address Resolution protocol allows a machine to gain
  330| knowledge about the higher level protocol activity (e.g., CHAOS,
  331| Internet, PUP, DECnet) on an Ethernet cable.  It can determine
  332| which Ethernet protocol type fields are in use (by value) and the
  333| protocol addresses within each protocol type.  In fact, it is not
  334| necessary for the monitor to speak any of the higher level
  335| protocols involved.  It goes something like this:
  336| 
  337| When a monitor receives an Address Resolution packet, it always
  338| enters the <protocol type, sender protocol address, sender
  339| hardware address> in a table.  It can determine the length of the
  340| hardware and protocol address from the ar$hln and ar$pln fields
  341| of the packet.  If the opcode is a REPLY the monitor can then
  342| throw the packet away.  If the opcode is a REQUEST and the target
  343| protocol address matches the protocol address of the monitor, the
  344| monitor sends a REPLY as it normally would.  The monitor will
  345| only get one mapping this way, since the REPLY to the REQUEST
  346| will be sent directly to the requesting host.  The monitor could
  347| try sending its own REQUEST, but this could get two monitors into
  348| a REQUEST sending loop, and care must be taken.
  349| 
  350| Because the protocol and opcode are not combined into one field,
  351| the monitor does not need to know which request opcode is
  352| associated with which reply opcode for the same higher level
  353| protocol.  The length fields should also give enough information
  354| to enable it to "parse" a protocol addresses, although it has no
  355| knowledge of what the protocol addresses mean.
  356| 
  357| A working implementation of the Address Resolution protocol can
  358| also be used to debug a non-working implementation.  Presumably a
  359| hardware driver will successfully broadcast a packet with Ethernet
  360| type field of ether_type$ADDRESS_RESOLUTION.  The format of the
  361| packet may not be totally correct, because initial
  362| implementations may have bugs, and table management may be
  363| slightly tricky.  Because requests are broadcast a monitor will
  364| receive the packet and can display it for debugging if desired.
  365| 
  366| 
  367| An Example:
  368| -----------
  369| 
  370| Let there exist machines X and Y that are on the same 10Mbit
  371| Ethernet cable.  They have Ethernet address EA(X) and EA(Y) and
  372| DOD Internet addresses IPA(X) and IPA(Y) .  Let the Ethernet type
  373| of Internet be ET(IP).  Machine X has just been started, and
  374| sooner or later wants to send an Internet packet to machine Y on
  375| the same cable.  X knows that it wants to send to IPA(Y) and
  376| tells the hardware driver (here an Ethernet driver) IPA(Y).  The
  377| driver consults the Address Resolution module to convert <ET(IP),
  378| IPA(Y)> into a 48.bit Ethernet address, but because X was just
  379| started, it does not have this information.  It throws the
  380| Internet packet away and instead creates an ADDRESS RESOLUTION
  381| packet with
  382| 	(ar$hrd) = ares_hrd$Ethernet
  383| 	(ar$pro) = ET(IP)
  384| 	(ar$hln) = length(EA(X))
  385| 	(ar$pln) = length(IPA(X))
  386| 	(ar$op)  = ares_op$REQUEST
  387| 	(ar$sha) = EA(X)
  388| 	(ar$spa) = IPA(X)
  389| 	(ar$tha) = don't care
  390| 	(ar$tpa) = IPA(Y)
  391| and broadcasts this packet to everybody on the cable.
  392| 
  393| Machine Y gets this packet, and determines that it understands
  394| the hardware type (Ethernet), that it speaks the indicated
  395| protocol (Internet) and that the packet is for it
  396| ((ar$tpa)=IPA(Y)).  It enters (probably replacing any existing
  397| entry) the information that <ET(IP), IPA(X)> maps to EA(X).  It
  398| then notices that it is a request, so it swaps fields, putting
  399| EA(Y) in the new sender Ethernet address field (ar$sha), sets the
  400| opcode to reply, and sends the packet directly (not broadcast) to
  401| EA(X).  At this point Y knows how to send to X, but X still
  402| doesn't know how to send to Y.
  403| 
  404| Machine X gets the reply packet from Y, forms the map from
  405| <ET(IP), IPA(Y)> to EA(Y), notices the packet is a reply and
  406| throws it away.  The next time X's Internet module tries to send
  407| a packet to Y on the Ethernet, the translation will succeed, and
  408| the packet will (hopefully) arrive.  If Y's Internet module then
  409| wants to talk to X, this will also succeed since Y has remembered
  410| the information from X's request for Address Resolution.
  411| 
  412| Related issue:
  413| ---------------
  414| 
  415| It may be desirable to have table aging and/or timeouts.  The
  416| implementation of these is outside the scope of this protocol.
  417| Here is a more detailed description (thanks to MOON@SCRC@MIT-MC).
  418| 
  419| If a host moves, any connections initiated by that host will
  420| work, assuming its own address resolution table is cleared when
  421| it moves.  However, connections initiated to it by other hosts
  422| will have no particular reason to know to discard their old
  423| address.  However, 48.bit Ethernet addresses are supposed to be
  424| unique and fixed for all time, so they shouldn't change.  A host
  425| could "move" if a host name (and address in some other protocol)
  426| were reassigned to a different physical piece of hardware.  Also,
  427| as we know from experience, there is always the danger of
  428| incorrect routing information accidentally getting transmitted
  429| through hardware or software error; it should not be allowed to
  430| persist forever.  Perhaps failure to initiate a connection should
  431| inform the Address Resolution module to delete the information on
  432| the basis that the host is not reachable, possibly because it is
  433| down or the old translation is no longer valid.  Or perhaps
  434| receiving of a packet from a host should reset a timeout in the
  435| address resolution entry used for transmitting packets to that
  436| host; if no packets are received from a host for a suitable
  437| length of time, the address resolution entry is forgotten.  This
  438| may cause extra overhead to scan the table for each incoming
  439| packet.  Perhaps a hash or index can make this faster.
  440| 
  441| The suggested algorithm for receiving address resolution packets
  442| tries to lessen the time it takes for recovery if a host does
  443| move.  Recall that if the <protocol type, sender protocol
  444| address> is already in the translation table, then the sender
  445| hardware address supersedes the existing entry.  Therefore, on a
  446| perfect Ethernet where a broadcast REQUEST reaches all stations
  447| on the cable, each station will be get the new hardware address.
  448| 
  449| Another alternative is to have a daemon perform the timeouts.
  450| After a suitable time, the daemon considers removing an entry.
  451| It first sends (with a small number of retransmissions if needed)
  452| an address resolution packet with opcode REQUEST directly to the
  453| Ethernet address in the table.  If a REPLY is not seen in a short
  454| amount of time, the entry is deleted.  The request is sent
  455| directly so as not to bother every station on the Ethernet.  Just
  456| forgetting entries will likely cause useful information to be
  457| forgotten, which must be regained.
  458| 
  459| Since hosts don't transmit information about anyone other than
  460| themselves, rebooting a host will cause its address mapping table
  461| to be up to date.  Bad information can't persist forever by being
  462| passed around from machine to machine; the only bad information
  463| that can exist is in a machine that doesn't know that some other
  464| machine has changed its 48.bit Ethernet address.  Perhaps
  465| manually resetting (or clearing) the address mapping table will
  466| suffice.
  467| 
  468| This issue clearly needs more thought if it is believed to be
  469| important.  It is caused by any address resolution-like protocol.
  470| 
  471| 
```
