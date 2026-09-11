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
