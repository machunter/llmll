# Normativity rubric: RFC 4648 (Base16, Base32, Base64 encodings)

Written before any clause is extracted. The rules below decide which spans of the RFC are
normative and therefore enter the denominator. They are fixed now so that the denominator is the
output of a stated rule rather than a description of whatever the extractor happened to produce.

Source: `00-source/rfc4648.txt`, sha256
`84e14418f795d503be5f34bf23ce4ebaa119e9ec7c9f667d8caeb111385b178f`, 1011 lines. All citations are
`L<start>-<end>` against that file.

---

## 0. What this document decides, and what it does not

**Decides:** whether a span of RFC 4648 imposes an obligation, and therefore whether it occupies a
row in the denominator.

**Does not decide:** whether that obligation is expressible in the verifiable fragment. That is
`01-scope/scope.md`, and it is a separate axis. A row can be normative here and `OUT` there, and
for several classes below that combination is the expected majority rather than an anomaly.

The separation is the point. If normativity were decided with the fragment in view, every clause
that turned out to be hard to express would quietly stop being a requirement, and the denominator
would shrink to flatter the numerator. The denominator belongs to this rubric. The numerator
belongs to the scope document. Neither is permitted to adjust the other.

**One consequence to state immediately.** Section 5 of `scope.md` records modeling decisions and
section 6 records `IN` / `SPLIT` / `OUT` verdicts. None of those verdicts is an input to any rule
below. Where this rubric and `scope.md` reach the same conclusion about a passage (the C99 code,
the test vectors), the agreement is derived independently here, and the derivation is shown so
that it can be checked rather than taken on the coincidence.

---

## 1. Date check: RFC 4648 postdates RFC 2119, and it does not matter as much as that sounds

RFC 4648 is dated October 2006 (L9). RFC 2119 is March 1997. The document declares the convention
at L140-142, citing [2] = RFC 2119 at L854-855, and lists RFC 2119 as a normative reference. So
the post-2119 branch applies: **uppercase keywords are read at face value.**

Then the census of what that buys. Every uppercase RFC 2119 keyword in the body of RFC 4648:

| Line | Token | Subject |
|---|---|---|
| L161 | `MUST NOT` | Implementations, adding line feeds |
| L182 | `MUST` | Implementations, including pad characters |
| L200 | `MUST` | Implementations, rejecting non-alphabet characters |
| L208 | `MAY` | Referring specifications, ignoring `=` before the end |
| L212 | `MAY` | Excess pad characters at the end |
| L257 | `MUST` | Conforming encoders, pad bits set to zero |
| L266 | `MAY` | Decoders, rejecting non-zero pad bits |

Seven instances. Four `MUST`-family, three `MAY`, zero `SHOULD`, zero `SHALL`, zero `REQUIRED`,
zero `RECOMMENDED`, zero `OPTIONAL`. All seven fall inside section 3 (L144-268), the section the
document itself describes as the place where it will "mandate a specific recommended behavior"
(L146-148).

Sections 4 through 8, which contain the entire definition of base64, base64url, base32, base32hex,
and base16, contain **no uppercase requirement word at all**. Neither do Tables 1 through 5.

So a keyword-triggered denominator for this RFC would be 7 rows, and it would omit the alphabets,
the bit grouping, the quantum widths, the MSB-first convention, and every final-quantum case. It
would omit the specification. The 2119 declaration is real and is honored, but it does not carry
the normativity judgment on this document. **Rule N2, the violation test, carries it**, and the
rules are ordered below to reflect that.

**The lowercase problem.** The body uses lowercase keywords heavily, and at least one of them is
behavior-defining in the strongest sense: L438-439, "the bit stream must be presumed to be ordered
with the most-significant-bit first", determines the output bit-exactly. Others are advisory
(L749, "care should be taken"), naming guidance (L368-369), or plain English (L273, "may be
referred to as base64").

The convention adopted here, and it is an interpretive decision rather than something the pinned
text settles:

> **Lowercase keywords carry no requirement level.** They do not confer normativity by themselves
> and they do not deny it. Normativity for those spans is decided by N2 on the sentence's
> behavioral content, and the token actually present is recorded per row with its case preserved,
> so an auditor who prefers the opposite convention can re-derive the denominator from the same
> table without re-reading the RFC.

The basis is RFC 8174 (BCP 14, May 2017), which updates RFC 2119 and states that lowercase uses
of these words carry their ordinary English meaning. RFC 8174 postdates RFC 4648 by eleven years
and is outside the pinned artifact; applying it is tie-break T7 reaching outward, and it is
flagged here rather than absorbed silently.

The practical effect is that the discipline the pre-2119 branch prescribes (record the word
actually present, judge interpretively, accept that the rubric is doing the work) is adopted for
this document anyway, for the roughly nine tenths of it that no uppercase keyword touches.

---

## 2. The unit: what counts as a row

A **row** is one obligation, on one addressee, in one situation, with one citation range.

Rows are not sentences, not keyword occurrences, and not sections. A sentence can yield two rows
(T1); two sentences in different sections can yield one row (T4); a table of 65 entries is one row
(T3).

Every row carries this schema. The `basis` field is the audit hook: a row that cannot name the
rule that admitted it does not belong in the denominator.

| Field | Values |
|---|---|
| `cite` | `L<start>-<end>` against the pinned sha |
| `text` | the span, verbatim, page furniture elided per T12 |
| `basis` | the rule id that admitted it: `N1`..`N11` |
| `class` | exactly one of `ALPH`, `QUANT`, `PAD`, `REJECT`, `FRAME`, `NAME`, `PROP`, `SEC` |
| `addressee` | `IMPL-ENC`, `IMPL-DEC`, `IMPL-BOTH`, or `SPEC` |
| `word` | the requirement token verbatim with case, or `none (declarative)` |
| `exception` | the qualifier attached to this obligation, or `none` |
| `violation` | one line naming a concrete behavior the row forbids (required by N2, see T13) |
| `xref` | citations merged into this row under T4/T5, or `none` |

`class` is declared here and not later, because the gate measures class-stratified coverage. A
class list invented after the results are known can be drawn around whatever was covered. These
eight are drawn from the document's own structure:

- **`ALPH`** value-to-character mappings and the sentences fixing subset size and index semantics
- **`QUANT`** group widths, symbol counts, left-to-right order, bit significance
- **`PAD`** pad-bit values, pad-character emission, final-quantum case analysis, base16's exemption
- **`REJECT`** decoder acceptance, rejection, and leniency for input it cannot map
- **`FRAME`** the shape of the emitted character stream beyond the symbols themselves
- **`NAME`** identification and labeling obligations
- **`PROP`** properties the document asserts about its own encodings without imposing new behavior
- **`SEC`** security-considerations directives that constrain an implementation

---

## 3. Normative rules

**N1. Declared requirement word, uppercase.** Any span containing an uppercase RFC 2119 keyword
per the declaration at L140-142 is normative. Read at face value.

This includes `MAY`. A permission is normative because it withdraws an obligation that would
otherwise follow from a `MUST` elsewhere in the document, and because whether a referring
specification is conforming turns on it. That a `MAY` cannot be violated makes it undischargeable
later; it does not make it non-normative now. Undischargeable is a disposition, not an exclusion,
and the difference is what keeps the denominator a record of what the document says rather than a
record of what could be discharged.

**N2. The violation test.** A span is normative if a conforming-looking implementation could be
built that contradicts it. The test is discharged by naming, in one line, a concrete encoder or
decoder behavior the span forbids. If no such behavior can be named, N2 does not fire.

N2 is independent of requirement word and independent of section placement. It is the rule that
admits the definition of base64, and on this document it admits more rows than all the other rules
combined.

**N3. Alphabet and format definitions.** Tables 1 through 5 and the prose fixing subset size
(L287-289, L429-431, L545-546) and index semantics (L298-300, L455-458, L554-556). The
value-to-character map is this RFC's wire format: it is the artifact two implementations must
agree on byte for byte, and it plays the role the packet-format diagram plays elsewhere.

**N4. Quantum formation and bit order.** Spans fixing group widths (24, 40, 8), output symbol
counts (4, 8, 2), the left-to-right traversal, the concatenation of input groups, and the
MSB-first convention at L438-442. Each determines the output bit-exactly, so N2 fires on every one
of them; N4 exists to name the class rather than to add coverage.

**N5. Final-quantum and padding behavior.** Pad-bit values, the zero-fill on the right, the pad
character, the "full encoding quantum is always completed" statements (L324-325, L474-475), and
each numbered final-quantum case (base64 cases 1 to 3, base32 cases 1 to 5). Each numbered case is
its own row under T3: an implementation can get case 2 right and case 3 wrong, and a rubric that
merged them would hide that.

**N6. Error and exception behavior.** What a decoder does with input it cannot map: rejection
(L200-203), the ignore alternative (L203-206), the consequence that CRLF are non-alphabet
characters and are ignored (L206-208), the pad-character permissions (L208-213), and non-zero pad
bit rejection (L265-268).

**N7. Obligations on the referring specification.** Normative, `addressee = SPEC`.

These are not third-party protocol behavior under X4, because RFC 4648 is imposing them rather
than reporting them. They are the hinge the three `MUST` clauses turn on: the content of L161-163,
L182-184, and L200-203 is not determinable without knowing what a referring specification is
permitted to say. Excluding them would leave three `MUST` rows whose meaning is stored outside the
denominator.

**N8. Self-declared normativity governs, in both directions.** Where the document states the
status of a passage, that statement wins over every other rule here. The negative direction fires
at L742, "This code is not normative", and is cross-listed as X7. The positive direction fires at
L146-148, where section 3 announces that it will mandate behavior.

**N9. Naming and identification obligations.** L367-370 and L514-516, the "should not be regarded
as the same" and "should not be referred to as only" pairs. N2 fires weakly: the constrained
artifact is a label a producer emits rather than an encoded octet, but a label is emitted, and an
implementation that advertises base64url output as "base64" has done the thing the sentence
forbids. Admitted under T9, recorded with the lowercase token, and expected to disposition out.

**N10. Security-considerations directives that constrain an implementation.** Section 12's
lowercase directives are normative when their predicate is a property of the artifact, for example
L751-752, "A decoder should not break on invalid input including, e.g., embedded NUL characters".
They are not normative when their only predicate is a person's mental state; see X6 for the line
and section 8(h) for the worked pair.

**N11. Asserted properties of the document's own encodings.** Statements the RFC makes about what
its encodings guarantee, which impose no obligation not already imposed by the tables and the
grouping rules, but which an implementer will rely on. The clearest instance is L519-521, the
base32hex sort-order claim. Also L259-263 (canonicity), L186-188 (which alphabets need padding),
L372-373 and L523-524 (identical-except-the-delta), L575-576 (base16 needs no padding).

These are claims, not commands, and a rubric that classed them as rationale under X1 would drop
them. They are kept, class `PROP`, for a specific reason: **if the claim is false, the document is
wrong, and an implementation that relied on it is broken by the document rather than by itself.**
That failure mode is worth a row. `scope.md` section 3(b) records that the unrestricted form of
one of these claims is in fact false, which is what a `PROP` row is for.

---

## 4. Non-normative rules

**X1. Motivation, rationale, and statements of purpose.** Section 1 in full. The discrepancy
narratives at L146-148 (the framing half), L152-159, L177-181, L192-198. The alphabet-choice
rationale bullets at L217-249, excluding the parenthetical at L234-235 (see T4). The explanatory
worked reasoning at L253-256. The alternative-alphabet discussion at L356-361.

**X2. Examples and illustrative traces.** Section 9 in full (L578-648) and section 10 in full
(L650-713). The figures at L584-588 and L595-607 restate bit layouts already fixed by N4 prose and
are merged as cross-references under T4. The three worked examples and the 28 test vectors go to
the validation register in section 7 below, which is neither the denominator nor the discard pile.

**X3. Historical, changelog, and superseded text.** Section 13 (L791-805). The `Obsoletes: 3548`
header (L9). The "In the past, different applications..." framing at L127-133.

**X4. Another protocol's behavior, not imposed here.** MIME's 76-character line limit and PEM's 64
(L152-159). "as MIME does" (L203-204). The IMAP variant (L246-249). The NSEC3 usage note
(L516-517). Provenance notes: "derived from [3], [4], [5], and [6]" (L272-273), "derived from [11]
(with corrections)" (L422-423), "derived from [7]" (L513), "has been used in [12]" (L353-354),
"borrowed from [5]" (L582), "borrowed from [7]" (L590-591).

The test in every case: does RFC 4648 require anything of an implementation by saying this, or is
it reporting what another document does? Reporting is X4. A sentence that grants a referring
specification a permission is N7, not X4, even when it names MIME as the example.

**X5. Document metadata and boilerplate.** Running headers and footers (every `Josefsson
Standards Track [Page N]` line and every `RFC 4648 Base-N Encodings October 2006` line), blank
lines, the title block (L7-13), Status of This Memo (L15-21), Copyright Notice (L23-25), the
Abstract (L27-33), the Table of Contents (L63-87), section 2 itself as a convention declaration
(L138-142), Acknowledgements (L807-819), Copying Conditions (L821-834), the References lists
(L847-893), Author's Address (L903-907), Full Copyright (L959-973), Intellectual Property
(L975-997), and the RFC Editor acknowledgement (L999-1002).

The reference **entries** are metadata. The normative dependency an entry carries travels with the
body row that cites it: the US-ASCII dependency on [1] attaches to the N3 rows at L287-289,
L429-431, and L545-546, not to L851-852.

Section 2 is metadata under X5 despite being the source of N1's authority. It tells the reader how
to read other rows; it imposes nothing on an implementation. This is T2 applied to the document's
own machinery.

**X6. Directives whose only predicate is a person's mental state.** L759-760, "The implications of
ignoring non-alphabet characters should be understood in applications that do not follow the
recommended practice." Nothing an implementation emits or accepts can conform to or violate this.
Contrast L751-752, which forbids a behavior of the artifact and is N10.

X6 is narrow on purpose and is the only place where a directive addressed to a human is excluded.
If the addressee is unclear, T9 applies and the row goes normative.

**X7. Self-declared non-normative passages.** L735-745, section 11, on the authority of L742,
"This code is not normative." The URL at L740 and the procedural note at L744-745 go with it.

---

## 5. Tie-breaks

**T1. One obligation per row.** One obligation, one addressee, one situation. A sentence carrying
two requirement words yields two rows: L367-370 is two `NAME` rows, and L208-213 is two `REJECT`
rows. An exception qualifier is **not** its own row; it is the `exception` field on the host row.
The phrase "unless the specification referring to this document explicitly states otherwise"
appears in three `MUST` sentences (L161-163, L182-184, L200-203) and contributes three `exception`
field values, not three additional rows.

**T2. The definition test.** A definition is normative when an implementation could violate it and
metadata when it only names a thing.

Both directions occur here and are worth stating with their instances. "This encoding may be
referred to as 'base64url'" (L367) attaches a name and constrains nothing: metadata, X5. "A
65-character subset of US-ASCII is used, enabling 6 bits to be represented per printable
character" (L287-288) constrains the output character set and the information content of each
symbol: normative, N3.

**T3. Granularity follows the document's own smallest addressable unit.** Where the RFC labels a
unit, that label is the row boundary. Numbered items `(1)` through `(3)` and `(1)` through `(5)`
are separate rows because the RFC numbers them separately and refers to them individually. Tables
are single rows because the RFC refers to them as single objects ("identified in Table 3, below",
L457). Below the labeled level the unit is the sentence, and below that only when T1 forces a
split.

A table row carries `entries=N` so that its width is visible in the audit rather than hidden
inside a count of 1: Table 1 `entries=65`, Table 2 `entries=65`, Table 3 `entries=33`, Table 4
`entries=33`, Table 5 `entries=16`.

This rule is stated in terms of the document's own typography rather than the extractor's judgment
precisely so that it cannot be tuned. The alternative, one row per table entry, would add 212 rows
and would make the denominator a measure of how many characters ASCII has.

**T4. Restatement does not add a row.** A span that imposes no obligation not already imposed
elsewhere is recorded as an `xref` on the primary row. Both citations survive; only one row does.

Instances: the parenthetical at L234-235, "(However, by default it should not; see previous
section.)", restates the default set by L200-203. The figures at L584-588 and L595-607 restate the
bit layouts of L291-296 and L433-442. L186-188 forward-references sections 4, 6, and 8.

T4 is a counting rule, not a normativity rule. A restated obligation is still an obligation; it is
just not a second one.

**T5. Definition-by-reference does not clone rows.** "This encoding is technically identical to the
previous one, except for the 62:nd and 63:rd alphabet character" (L372-373) is **one** row
asserting the delta. It does not replicate section 4's rows into section 5. Same for L523-524 in
section 7.

Without this rule the denominator for base64url and base32hex is either zero or a full copy of the
section they inherit from, and which one you get depends on the extractor's mood.

**T6. Ground instances go to the validation register, never to the clause denominator.** See
section 7. A ground instance that contradicts the rows that entail it is promoted to a normative
row and flagged as an internal inconsistency, because at that point it is no longer an instance of
anything.

**T7. A later amending document governs on conflict.** Two directions are live:

- RFC 4648 obsoletes RFC 3548 (L9). Where text descends from 3548, the 4648 wording governs, and
  section 13's changelog is the map of where the two differ.
- RFC 8174 updates RFC 2119 on the uppercase question. Applied in section 1, flagged there as
  reaching outside the pinned artifact.

No document in the pinned artifact amends RFC 4648. If an approved erratum or a successor RFC is
introduced at any later stage, it is entered here as a dated amendment to this rubric and the
affected rows are re-derived. It is not applied to individual rows in passing.

**T8. The requirement word is recorded, not decisive.** Every row carries the token verbatim with
its case, or `none (declarative)`. Uppercase gets face value per L140-142. Lowercase gets no
requirement level but does not block N2. The expected plurality value across the denominator is
`none (declarative)`, and that fact is the shape of this RFC rather than a defect in the
extraction.

**T9. When in doubt, mark normative.** Doubt means the rules above do not resolve the span, not
that the span looks weak. Section 9 states what this costs.

**T10. Section placement is a weak signal; N2 governs.** A section titled "Security
Considerations" can contain normative rows, and does. A section titled "Illustrations and
Examples" is not automatically X2; its contents happen to fall to X2 and T4 on their own merits,
and the derivation is shown rather than assumed from the heading.

**T11. Addressee is recorded, and only one value excludes.** `IMPL-ENC`, `IMPL-DEC`, `IMPL-BOTH`,
and `SPEC` are all normative. An addressee who is neither an implementation nor a referring
specification excludes only under X6's narrow predicate test.

**T12. Page furniture is elided, and a row may span it.** The running header, the running footer,
the form-feed gap, and the blank lines around them are X5 and are removed when reconstructing a
span. A citation range may contain elided furniture, and crossing a page boundary never splits a
row. This is not cosmetic: base64's case 1 sits at L332-334 and cases 2 and 3 at L343-349, with a
page break between them, and section 3.5's canonicity argument at L253-263 sits directly under
one.

**T13. Every row states its violation in one line.** N2's test is not a mental step; it is a
recorded field. A row whose `violation` field cannot be filled was admitted by N1 alone (a `MAY`,
or a requirement on a `SPEC`) and must say so. This is what makes the denominator auditable
row by row rather than in aggregate.

---

## 6. Rule precedence

Applied in order. The first rule that fires decides.

1. **N8** self-declaration, either direction
2. **X5** document metadata and page furniture
3. **T4 / T5** restatement and definition-by-reference merging
4. **T6** ground instances to the validation register
5. **N1** uppercase requirement word
6. **N2** the violation test, with T13's recorded line
7. **X1, X3, X4, X6, X7** the remaining exclusions
8. **T9** when in doubt, normative

N1 sits above N2 so that an unfalsifiable `MAY` is admitted rather than dropped for failing T13.
X5 sits above N1 so that section 2's own recitation of the keywords at L140-142 does not admit
itself seven times over.

---

## 7. The validation register

The 28 test vectors (L652-713) and the 3 worked examples (L623-648) are closed ground instances.
Each is entailed by the `ALPH`, `QUANT`, and `PAD` rows that produce it, and each is settled by
evaluation rather than by proof.

They are held in a **separate register with its own count**, reported under its own label, and
they never enter the clause denominator. Two independent reasons, and the first is sufficient on
its own:

1. They impose no obligation not already imposed. Under T4 they would merge into the rows that
   entail them; T6 sends them to the register instead so that their validation value is not lost
   in the merge.
2. A count that mixed 31 evaluations with N proved clauses would report a number that means
   nothing, since the two are not the same kind of evidence and are not the same amount of work.

Composition of the register: 7 vectors each for BASE64, BASE32, BASE32-HEX, and BASE16, plus the
three worked examples at L625-630, L632-639, and L641-648.

Five of the 28 are the empty-input cases (L652, L666, L687, L701). `scope.md` decision 4 records
that the empty input is uncovered rather than vacuous. This rubric records the orthogonal fact:
they are in the validation register like every other vector, and their entailment failing for
scope reasons is a coverage gap to be reported, not a reason to quietly drop them from the
register's denominator.

---

## 8. Calibration: the rules applied to ten hard passages

This is **not** the extraction and not a partial denominator. These ten were chosen because they
are the passages where the rules could plausibly go either way, and they are worked here so that
stage D inherits a decision rather than a judgment call.

**(a) L257-258, "These pad bits MUST be set to zero by conforming encoders."**
N1 fires on `MUST`. `class=PAD`, `addressee=IMPL-ENC`, `word=MUST`, `exception=none`.
`violation`: an encoder that emits `Zm8=` for input `fo` but `Zm9=` for the same input by leaving
the low four bits of the third symbol non-zero.

**(b) L438-442, "the bit stream must be presumed to be ordered with the most-significant-bit
first."**
N1 does not fire; the token is lowercase. N2 fires without difficulty. `class=QUANT`,
`addressee=IMPL-BOTH`, `word=must (lowercase)`. `violation`: an encoder that slices each octet
LSB-first and encodes `f` (0x66) as a different pair of symbols.

This row is the reason N2 leads and the requirement word does not. A rubric keyed to uppercase
would drop the bit order of base32 out of the specification.

**(c) Table 1, L302-321.**
N3 fires. One row under T3, `entries=65`, `class=ALPH`, `addressee=IMPL-BOTH`,
`word=none (declarative)`. `violation`: an implementation that maps value 62 to `-` instead of
`+`, which is exactly Table 2's alphabet and exactly the confusion section 5 exists to prevent.

**(d) L332-334 and L343-349, base64 final-quantum cases (1), (2), and (3).**
Three rows under T3, spanning a page break under T12. `class=PAD`, `addressee=IMPL-ENC`,
`word=none (declarative)`. `violation` for case (2): an encoder that emits one `=` rather than two
for a final quantum of exactly 8 bits.

Note the contrast with (c), and the rule that produces it. The cases are separate rows because the
RFC numbers them separately; the table is one row because the RFC names it as one object. Both
follow from T3 without further judgment.

**(e) L367-370, "This encoding should not be regarded as the same as the 'base64' encoding and
should not be referred to as only 'base64'."**
T1 splits this into two rows. N9 admits both. `class=NAME`, `addressee=IMPL-BOTH`,
`word=should not (lowercase)`. `violation`: a library that documents its `base64()` function as
producing RFC 4648 base64 while emitting `-` and `_`.

Expected to disposition out later as unverifiable. It stays in the denominator regardless, because
the reason it fails is a property of the verifier and not of the document.

**(f) L519-521, "encoded data maintains its sort order when the encoded data is compared
bit-wise."**
N11 fires, `class=PROP`, `word=none (declarative)`, `addressee=IMPL-BOTH`. T13's `violation` field
is filled in the `PROP` form: not a behavior the row forbids, but the statement whose falsity would
break a reliant implementation.

The alternative classing, X1 rationale, is tempting because the sentence sits in a paragraph that
reads like motivation for the extended hex alphabet. It is rejected under T10: the sentence
asserts a checkable property of the encoding, and `scope.md` section 3(b) records a counterexample
to its unrestricted form. A rubric that classed it as rationale would have discarded the one row in
this document that turns out to be wrong.

**(g) L735-745, section 11, the ISO C99 implementation.**
X7 fires on L742, "This code is not normative", and N8 gives the self-declaration precedence over
everything else. The URL and the RFC 3978 procedural note go with it. Zero rows.

**(h) L751-752 against L759-760, the section 12 pair.**
"A decoder should not break on invalid input including, e.g., embedded NUL characters (ASCII 0)":
N10 fires, `class=SEC`, `addressee=IMPL-DEC`, `word=should not (lowercase)`. `violation`: a
decoder that segfaults on `Zm9v\0YmFy`.

"The implications of ignoring non-alphabet characters should be understood in applications that do
not follow the recommended practice": X6 fires. The predicate is `understood`, held by a person.
No row.

The line between them is whether the predicate attaches to the artifact or to the reader. L749-750,
"care should be taken not to introduce vulnerabilities to buffer overflow attacks", attaches to the
artifact (does-not-contain) and is therefore N10, even though it will disposition out as a property
of the implementation rather than of the encoding. That is the correct order of operations: admit
on the predicate, dispose on the fragment.

**(i) L208-213, the two `MAY` sentences.**
Two rows under T1. N1 admits both; N7 sets `addressee=SPEC` on the first. `class=REJECT`,
`word=MAY`. T13's `violation` field is empty on both, and both must say so.

These rows are undischargeable and will be reported as such. They are in the denominator because
RFC 4648 said them and a referring specification's conformance depends on them.

**(j) L234-235, "(However, by default it should not; see previous section.)"**
T4 fires. The obligation is the default already set by L200-203. Recorded as an `xref` on that row.
No new row. The surrounding bullet at L231-235 is X1 rationale.

---

## 9. Pre-registered expectations, and what a miss means

Committed before extraction so that stage D's output is checked against a prediction rather than
described after the fact.

| Class | Expected rows | Principal spans |
|---|---|---|
| `ALPH` | 10 to 14 | Tables 1-5, subset-size and index sentences, two T5 delta rows |
| `QUANT` | 9 to 14 | L291-296, L433-442, L548-552, quantum-completion statements |
| `PAD` | 15 to 20 | L182-184, L257-258, L323-330, L473-480, 8 numbered cases, L575-576 |
| `REJECT` | 7 to 10 | L200-213, L265-268 |
| `FRAME` | 1 | L161-163 |
| `NAME` | 4 | L367-370, L514-516 |
| `PROP` | 4 to 7 | L186-188, L259-263, L372-373, L519-521, L523-524 |
| `SEC` | 4 to 7 | L749-752, L754-768, L770-781 |
| **Total** | **55 to 75** | |
| Validation register | 31 | 28 vectors, 3 worked examples |

Diagnostics if extraction lands outside the range, stated now so the miss is read as a process
failure rather than a finding:

- **Under 40.** The extractor is keyword-triggering. N2 was not applied, or was applied only where
  a lowercase keyword happened to appear. Check whether Tables 1-5 and the section 4, 6, 7, and 8
  prose produced rows at all.
- **Over 90.** T3, T4, or T5 was violated. Check for per-entry table rows, for restatements
  counted twice, and for base64url or base32hex carrying a full copy of the section they inherit
  from.
- **Any class at zero except `FRAME`.** A class defined here with no rows means either the rule
  that defines it was not applied or the class was wrong. Both are worth stopping for. `FRAME` is
  the exception because it has exactly one span and could legitimately merge.

The range is a prediction, not a target. If a rule as written produces rows outside it, **the rule
governs and the prediction was wrong.** The rules are not to be adjusted to bring the count into
the band, and the band is not to be revised after the count is known. Either outcome is recorded
as a dated amendment with the reason.

---

## 10. What the conservative tie-break costs

T9 over-includes on purpose. Rows enter the denominator that will not survive: three `MAY` rows
with nothing to discharge, four `NAME` rows about what a library calls its function, `SEC` rows
about buffer management that are properties of an implementation rather than of an encoding. On
the estimate above that is somewhere between ten and fifteen rows, a fifth of the denominator,
admitted knowing they will disposition out.

That is the trade, and both halves of it should be stated together.

**What it buys:** the denominator is safe. Nothing the document requires is missing from it, and
no row was excluded by a rule invented after someone saw how hard the row would be. An auditor
disagreeing with any single verdict can find the rule that produced it, in this file, written
before the verdict existed.

**What it destroys:** the exclusion ratio. "We covered 62% of normative clauses" is not a
meaningful sentence about a denominator built this way, because the denominator was deliberately
inflated with rows that were never dischargeable. Raising or lowering that percentage is a matter
of how generously T9 was applied, which is to say it measures the rubric and not the work.

So the ratio is not reported as a headline, not reported as a target, and not compared across
documents. What is reported instead:

1. **Class-stratified coverage.** Eight classes, each with its own count and its own disposition
   breakdown. `ALPH` at full coverage and `REJECT` at none is a completely different result from
   the reverse, and a single percentage renders them identical.
2. **A closed barrier list.** Every row that did not discharge, with the reason, drawn from a
   finite set of barrier kinds fixed before extraction. Closed means no row may exit through an
   unnamed reason, and a new barrier kind is a dated amendment to this file rather than a free
   choice at write-up time.

There is no ratio ceiling anywhere in the gate, and adding one later would reintroduce exactly the
incentive this rubric was written to remove.
