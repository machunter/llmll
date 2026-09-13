# Stage D: clause extraction (extractor B)

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
  "extractor": "B",
  "normative": [
    {
      "id": "B1",
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
      "id": "Bx1",
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

# Stage C: Normativity rubric for RFC 826

**Written before any clause is extracted.** No rule below was chosen by looking at a clause list,
because no clause list exists yet. The rules are stated so that a second reader with the same
pinned text can rebuild the denominator and get the same number, or else point at the rule that
was misapplied.

Source under study: `00-source/rfc826.txt`, sha256
`01bc62fe6a37e90f1246ac43e8e145f1322b4ed1474836145c3da93d2bd3c8a6`, 470 lines. All line
citations refer to that file. This is the same pinned artifact Stage B committed to
(`01-scope/scope.md` section 0).

---

## 0. What this rubric decides, and what it does not

This rubric decides one thing: **is a given obligation in RFC 826 normative?** Normative rows are
the denominator. Everything else about a row (whether it is in the verification fragment,
whether it was discharged, why it was not) is decided elsewhere.

**The normativity axis and the scope axis are orthogonal, and they are kept orthogonal on
purpose.** Stage B assigned dispositions (`IN-CORE`, `OUT-WIRE`, `OUT-ORDER`,
`OUT-ENVIRONMENT`, `OUT-NONNORMATIVE`, `OUT-BY-SOURCE`). Those answer "can this run be expected
to check it". This rubric answers "does the document require it". The two answers are
independent in three of four combinations:

| | Normative (this rubric) | Non-normative (this rubric) |
| --- | --- | --- |
| **In the fragment** (Stage B) | Counted; expected to be discharged | Not counted; not a row at all |
| **Outside the fragment** (Stage B) | **Counted, carries a barrier code** | Not counted; not a row at all |

The cell that matters is the bottom-left. A byte-order rule is a real requirement of RFC 826 and
Stage B put byte-level parsing outside the verification boundary. It is a normative row, it sits
in the denominator, and it carries the barrier code `OUT-WIRE`. It does not get to disappear
because this run cannot check it.

Stage B's `OUT-NONNORMATIVE` disposition is the one place the two axes touch. Where they
disagree, **this rubric governs the denominator** and the disagreement is logged (section 11).
Stage B assigned dispositions to line ranges as a planning estimate; this rubric classifies
obligations one at a time.

One rule the rubric enforces against itself, stated first because every other rule is corruptible
by it:

> **T12 (stated early because it outranks everything).** Verifiability is never an argument about
> normativity. If a classification argument contains, in any form, "we could not check that
> anyway", "that would need a bigger model", or "that would not produce a clean row", the
> argument is void and the row is normative. The cost of a row that cannot be discharged is one
> line in a barrier list. The cost of deleting it is a denominator that reports the model's
> convenience rather than the document's content.

---

## 1. The date check

**RFC 826 is dated November 1982. RFC 2119 is dated March 1997, fourteen years and four months
later. RFC 826 therefore has no MUST/SHOULD/MAY discipline, declares no keyword convention, and
supplies no requirement levels.** Every normativity judgment made on this document is
interpretive. There is no keyword to fall back on and no convention to cite. The rubric is doing
all of the work, which is why it is written down before extraction rather than reconstructed
afterward.

A scan of the pinned text confirms this directly:

- **Zero occurrences** of `MUST`, `SHALL`, `SHOULD`, `MAY`, `REQUIRED`, `RECOMMENDED`, or
  `OPTIONAL` as uppercase keywords.
- Uppercase tokens that do appear (`REQUEST`, `REPLY`, `ADDRESS RESOLUTION`, `NOW` at line 219,
  `AFTER` at line 309) are opcode names, protocol names, or typographic emphasis. A keyword
  scanner would report them as requirement words. They are false friends and are never read as
  requirement levels.
- The lowercase modal inventory is in Appendix A: 5 `must`, 8 `should`, 8 `may`, 1 `optional`,
  2 `optionally`, 12 `can`, 6 `could`, 23 `will`, and a substantial hedge vocabulary
  (6 `probably`, 5 `perhaps`, 1 `hopefully`, 1 `desirable`, 1 `supposed`).

### 1.1 Why the words cannot carry the classification

All five occurrences of `must`, read in place:

| Line | Text | Binds an implementation of this protocol? |
| --- | --- | --- |
| 23 | "a 48.bit Ethernet address must be generated" | No. A statement about Ethernet in the abstract. |
| 65 | "special care must be taken with the opcode field" | Yes. An encoding obligation. |
| 166 | "some lower layer ... must consult the Address Resolution module" | Yes. The one core `must`. |
| 348 | "care must be taken" (monitor request loop) | No. Advice about an optional role. |
| 457 | "cause useful information to be forgotten, which must be regained" | No. A consequence in rationale. |

Two of five. The protocol itself is carried almost entirely in the **present indicative**: "it
gives the corresponding 48.bit Ethernet address back to the caller", "The Address Resolution
module then sets the ar$hrd field to ares_hrd$Ethernet", "Send the packet to the (new) target
hardware address". Reading only the modal verbs would produce a denominator of roughly a dozen
rows, most of them in rationale sections, and would omit the entire reception algorithm.

> **Recorded reading decision R-1 (indicative mood).** In this document the present indicative,
> used with the Address Resolution module or a host as subject, states a requirement. It is read
> at the same strength as `must` and recorded with requirement word `(indicative)`. The
> alternative reading, that the document merely describes one possible implementation, is
> available and is what line 199 ("goes through an algorithm similar to the following") and line
> 307 ("the suggested processing algorithm") literally say. That reading makes the document
> contain no requirements at all, which is not a usable rubric, so it is rejected here and the
> rejection is recorded rather than assumed.

### 1.2 The document's own status disclaimer

Lines 45 to 50 say: "The method proposed here is presented for your consideration and comment.
This is not the specification of a Internet Standard." Taken literally, nothing in RFC 826 binds
anyone and the denominator is zero.

> **Recorded reading decision R-2 (counterfactual conformance).** The document is read as
> specifying conformance for an implementation that claims to implement this protocol, not as a
> discussion paper. Justification internal to the pinned text: lines 106 to 110 state the
> document's purpose is that "every implementor uses a standard so that his/her code can be
> distributed to other systems without need for modification", and the packet format section
> exists to make independently written implementations interoperate. Justification external to
> the pinned text: RFC 826 was subsequently elevated to Internet Standard (STD 37). That external
> fact is **not** in the pinned corpus, is not relied on, and is recorded here only so that a
> reader who knows it does not think it was overlooked. R-2 rests on lines 106 to 110.

### 1.3 What every row must record

Because the requirement level is interpretive, each row carries the evidence for its own
classification:

- **`word`**: the requirement or modal word **actually present**, verbatim and lowercase, with
  its line number. When the obligation is carried by mood rather than by a word, the value is
  `(indicative)` or `(imperative)`. When it is carried by a field listing with no verb at all,
  the value is `(none: format line)`. The field is never blank and never filled with a word that
  is not in the text.
- **`strength`**: the local ladder below. Strength **never** decides whether a row is in the
  denominator. It stratifies rows for reporting and it tells the extraction stage how hard to
  read the obligation.

| Code | Source words in this document | Reading |
| --- | --- | --- |
| `R-REQ` | `must`, `necessary`, `absolutely necessary`, `needed`, `requires` | Requirement |
| `R-IND` | none (present indicative or pseudo-code imperative) | Requirement, per R-1 |
| `R-REC` | `should` | Recommendation |
| `R-OPT` | `optional`, `optionally`, `may`, `can`, `could`, "if that makes it convenient" | Permission |
| `R-HEDGE` | `probably`, `perhaps`, `hopefully`, `desirable`, `supposed`, `might`, "will likely" | Suggestion the document declines to require |

`will` is **not** a requirement word by default in this document: 23 occurrences, nearly all
narrative future inside rationale and the worked example ("X still doesn't know how to send to
Y"). A `will` sentence rows only when it states protocol behavior in a rule position, and then
the row's strength comes from its context, not from the word.

---

## 2. The unit of judgment

The unit is **one obligation**, not one sentence and not one line. A sentence can carry two
obligations (line 172 to 175 carries a discard and an up-call), and one obligation can be spread
over three lines of the algorithm block.

Every candidate becomes a row with these fields:

| Field | Meaning |
| --- | --- |
| `id` | Stable row identifier assigned at extraction |
| `lines` | Line span in the pinned file |
| `quote` | Verbatim text, enough to identify the obligation without the file open |
| `verdict` | `normative` or `non-normative` |
| `rule` | The rule that decided it: `N1`..`N10`, `X1`..`X8`, plus any tie-break that fired |
| `word` | Requirement word actually present, per section 1.3 |
| `strength` | `R-REQ` / `R-IND` / `R-REC` / `R-OPT` / `R-HEDGE` |
| `class` | One of the coverage classes in section 7 (normative rows only) |
| `confidence` | `clear` or `doubt`; `doubt` means T5 fired and is the audit trail for over-inclusion |
| `barrier` | Empty, or exactly one code from the closed list in section 8 (normative rows only) |

Format demonstration, using a case worked in section 9 (this is a schema example, not an
extraction result):

```
lines:      65-66
quote:      "special care must be taken with the opcode field (ar$op) described below"
verdict:    normative
rule:       N3 (encoding), N8 (explicit word)
word:       "must" (line 65)
strength:   R-REQ
class:      C-ENCODE
confidence: clear
barrier:    OUT-WIRE   [Stage B section 2]
```

---

## 3. Normative rules

**N1. Behavior assigned to a party of this protocol.** The subject is the Address Resolution
module, a sending or receiving host, or the hardware driver acting as this module's caller, and
the verb describes an action taken while generating, processing, or emitting an address
resolution packet. Mood is irrelevant: imperative ("Set the ar$op field to ares_op$REPLY", line
223), indicative ("It then causes this packet to be broadcast", lines 188 to 190), and modal all
qualify. Per R-1, the indicative is this document's ordinary requirement mood.

**N2. The reception algorithm, lines 197 to 225.** Every conditional test, every assignment,
every branch action, and the fall-through convention at lines 200 to 201 ("Negative conditionals
indicate an end of processing and a discarding of the packet") is a candidate row. Indentation in
the algorithm block is control flow and is part of the obligation, not decoration to be dropped.
The sentence at line 219 that orders the opcode test after the merge is itself a row: ordering
between two steps is an obligation an implementation can violate while performing both steps.

**N3. Packet format and encoding, lines 131 to 155, 63 to 66, 320 to 323.** Each field line of
the packet format is a row: field identity, position in the packet, width, and stated meaning. A
field line has no verb and still binds, because an implementation violates it by emitting a
packet with a different layout. Encoding statements row under this rule too: which fields are
words, byte order, and the absence of padding between addresses.

**N4. Constants and enumeration values that are visible on the wire.** `ares_op$REQUEST (= 1)`,
`ares_op$REPLY (= 2)`, `ares_hrd$Ethernet (= 1)` (lines 122 to 126), `<ar$hrd, ar$hln>` taking
`<1, 6>` for 10Mbit Ethernet (line 238), `ar$hln` set to 6 (line 179). A wrong value is
observable by a peer. For names given without values, see T2.

**N5. Field assignment rules for generated packets, lines 176 to 190.** Each assignment is its
own row under T1: `ar$hrd`, `ar$pro`, `ar$hln`, `ar$pln`, `ar$op`, `ar$sha`, `ar$spa`, `ar$tpa`,
the non-assignment of `ar$tha`, and the broadcast destination.

**N6. State transitions on the translation table.** The merge of an existing entry (lines 209 to
213), the addition of the triplet when `Merge_flag` is false (lines 216 to 218), supersession of
an old hardware address by a new one (lines 231 to 234), and the setting of `Merge_flag` itself.
These are the state-machine transitions of the protocol's only state variable.

**N7. Discard, fall-through, and exception behavior.** Discard on unknown hardware type, on an
unspoken protocol, on a failed optional length check, on a target mismatch, and the discard of the
outbound packet when the table lookup misses (lines 170 to 175, the part whose actor is this
module). Error behavior is normative even when the document states it once as a convention
covering many branches.

**N8. Explicit requirement and permission words applied to a party of this protocol.** `must`,
`should`, `needed`, `necessary`, `requires`, `may`, `can`, `could`, `optional`, `optionally`. The
word is recorded verbatim. **Permissions row as well as obligations**: the optional length checks
at lines 205 and 208 and the permission to set `ar$tha` to the broadcast address at lines 186 to
188 bound what a peer may rely on, which is exactly why Stage B modeled the optional checks as
free booleans rather than as fixed choices (`01-scope/scope.md` section 4 item 4).

**N9. Parameterization and generalization rules.** Lines 236 to 242 (the `ar$hrd` and `ar$hln`
fields generalize the protocol to non-Ethernet hardware; `ar$pro` "should be associated with the
protocol whose address resolution is being sought") and lines 288 to 291 (address lengths are
determined by the hardware type and the protocol type). These state how the protocol behaves
outside the 10Mbit Ethernet case and an implementation can violate them.

**N10. Environment assumptions the protocol relies on.** Statements about the world that some
rule in this document depends on for its correctness: "48.bit Ethernet addresses are supposed to
be unique and fixed for all time" (lines 423 to 424); the 48-bit width of an Ethernet address that
makes `ar$hln = 6` correct (lines 91 to 93, 179). An implementation cannot violate these, so T2's
violability test alone would drop them. They row anyway, under class `C-ASSUME`, because a model
that assumes them owes the reader a statement of what it assumed. The test that separates N10
from X4 is **reliance**: does any rule in this document depend on the statement being true? If
yes, N10. If it is background about a neighboring protocol, X4.

---

## 4. Non-normative rules

**X1. Motivation and rationale.** Text that explains why a rule exists rather than stating one.
Presumptively: "The Problem" (lines 77 to 97), "Motivation" (lines 99 to 110), and the
explanatory body of "Why is it done this way??" (lines 245 to 323). Defeasible by T7: a rule
stated nowhere else is normative even when it sits in a rationale section. Lines 288 to 291 are
the standing example of X1 losing.

**X2. Examples and illustrative traces.** "An Example" (lines 367 to 410). The example restates
obligations already stated in the generation and reception sections; under T1 the first statement
site owns the row. Stage B uses the example as a bounded validation trace and as disambiguation
evidence for the reply construction (`01-scope/scope.md` section 7). Neither use creates a row.

**X3. Document metadata and front matter.** The RFC header and title (lines 1 to 17), the abstract
(lines 19 to 33), acknowledgments (lines 37 to 40), the status disclaimer (lines 45 to 50), and
terminology conventions that tell the reader how to read the document rather than telling an
implementation what to do ("DOD Internet Protocol will be referred to as Internet", line 61).

**X4. Statements about other protocols, other layers, or hardware, not imposed on this
implementation.** The list of coexisting protocols (lines 83 to 88), the address widths of CHAOS,
Internet, and PUP (lines 94 to 95), Ethernet's type-field multiplexing (lines 88 to 90). Defeasible
by N10's reliance test.

**X5. Speculation, open problems, and future work.** "There has been talk of using this protocol
for Packet Radio Networks" (lines 274 to 277), "It is hoped that we will never see 32768
protocols" (lines 285 to 286), "This issue clearly needs more thought if it is believed to be
important" (lines 468 to 469).

**X6. Obligations addressed to someone other than an implementation of this protocol.** The
registration instruction at lines 68 to 75 binds a person who wants a hardware number assigned,
and the sentence about an authority that does not yet exist binds nobody at all. Applied via T3.

**X7. Implementation notes with no peer-observable consequence.** Buffer reuse (lines 268 to 270),
"this may save some register shuffling or stack space" (lines 315 to 318), "Perhaps a hash or
index can make this faster" (line 439). A statement about resource use inside one implementation
that no peer can detect does not bind. Note the boundary: the *format property* that makes buffer
reuse possible ("a reply has the same length as a request") is a claim about the format and rows
under N3 if it is not already owned by a format row.

**X8. Descriptions of a role the document does not require a conforming node to play.** The
monitor (lines 326 to 364). A conforming ARP implementation is not required to be a monitor, and
most of the monitor text restates core rules. X8 is narrow: it covers the monitor's application
description and its restatements. The sentence at lines 337 to 340, "it always enters the
<protocol type, sender protocol address, sender hardware address> in a table", states a table rule
that **conflicts** with the target gate at line 214, so it is not a restatement and X8 does not
reach it. See section 9, case 9.

---

## 5. Tie-breaks

**T1. One obligation per row.** Split conjunctions and split multi-obligation sentences: the nine
field assignments at lines 176 to 184 are nine rows, not one. Deduplicate in the other direction:
when the same obligation is stated twice, the **first statement site owns the row** and the
restatement is recorded as a cross-reference. Deduplication happens before the denominator is
counted, so a restatement never inflates it. When it is unclear whether two statements are the
same obligation, T1's direction is to split, and T5 then keeps both.

**T2. The definition test: violability versus naming.** A definition is **normative when an
implementation could violate it** and **metadata when it only names a thing**. Worked inside a
single paragraph, lines 115 to 126: `ether_type$XEROX_PUP`, `ether_type$DOD_INTERNET`,
`ether_type$CHAOS`, and `ether_type$ADDRESS_RESOLUTION` are introduced as names with no values, so
nothing about them can be violated at that site and they are metadata (X3). `ares_op$REQUEST
(= 1, high byte transmitted first)`, `ares_op$REPLY (= 2)`, and `ares_hrd$Ethernet (= 1)` fix
values a peer will compare against and are normative (N4). The name
`ether_type$ADDRESS_RESOLUTION` acquires an obligation later, at line 139, where the packet format
requires the Ethernet type field to hold it; that is a separate row under N3.

**T3. The addressee test.** A row is normative only if its obligation binds an implementation of
this protocol, or a host running one. Obligations on readers, on registrants, on a
not-yet-existing numbering authority, or on the underlying hardware are X6. Doubt about the
addressee resolves normative.

**T4. A later amending RFC governs on conflict.** If an amending RFC changes what a sentence of
RFC 826 requires, the amended reading governs and the row records both. Conditions on invoking
this rule, because the pinned corpus is `rfc826.txt` alone: the invoking row must cite the
amending document by number and section; an amendment may change a row's **reading or
normativity** but may never **add** a row, since rows come only from the pinned text; and every
invocation is logged in section 11. Known updaters, none of which is in the pinned corpus and none
of which has been consulted: RFC 5227 (IPv4 Address Conflict Detection) and RFC 5494 (IANA
allocation guidelines for ARP) both update RFC 826, and RFC 1122 section 2.3.2 imposes additional
host requirements on ARP implementations. If extraction reaches for any of these, it says so in
the row.

**T5. When in doubt, mark normative.** Operationally: if two careful readers with this rubric in
hand could reach different verdicts, or if the classifier's own verdict is anything short of
`clear`, the row is **normative** and `confidence` is set to `doubt`. T5 fires last, after every
other rule has had its chance, and it applies to the normativity axis only. It is never a reason
to call something in scope, verified, or discharged.

**T6. Hedged text still rows.** `probably`, `perhaps`, `may be desirable`, `will likely`: the
hedge goes in the `strength` field as `R-HEDGE` and the row stays. A document that declines to
require something has still said something about it, and the place to record that the document
declined is the strength field, not the absence of a row.

**T7. Location is evidence, content decides.** Section membership creates a presumption, not a
verdict. An X presumption (X1, X2, X8) loses to an N rule when the text states an obligation that
appears nowhere else in the document. It holds when the text restates an obligation already owned
by a row elsewhere.

**T8. Pseudo-code, tables, and field lists are prose.** The algorithm block at lines 203 to 225
and the packet format at lines 141 to 155 are read line by line as candidate rows. Formatting does
not lower or raise normativity.

**T9. Multiple readings do not multiply rows.** Where one sentence has two readings with different
obligations, it produces **one** row, with both readings recorded in the row. Choosing between
them is a modeling decision made at extraction and recorded as such, in the style of Stage B's
decision O-1. The optional length check at lines 205 and 208 is the live instance: Stage B
(section 2) identifies a type-consistency reading that is inside the fragment and an
encoded-byte-length reading that is not.

**T10. Negative and permissive statements row.** "It does not set ar$tha to anything in
particular" (line 184) is an obligation: it tells an implementation that the field is
unconstrained and tells a peer not to rely on it. "This format does not allow for more than one
resolution to be done in the same packet" (lines 260 to 261) constrains the format. Both row.

**T11. A self-scoping disclaimer supplies a disposition, not a deletion.** When the document
declares a topic outside its own scope ("The implementation of these is outside the scope of this
protocol", lines 415 to 416), the disclaimer sentence itself is metadata (X3), and the obligations
stated around it still row, carrying the barrier code `OUT-BY-SOURCE`. This is the single largest
source of deliberate over-inclusion in this rubric, and section 8 accepts the consequence.

**T12. Verifiability is never an argument.** Stated in section 0, repeated here so the numbered
list is complete.

### Precedence order

When rules disagree, they are applied in this order, and the first one that produces a verdict
wins:

1. **T12** (verifiability arguments are void) is checked first and discards the argument, not the
   row.
2. **T4** (an amending RFC on the point, if one is cited).
3. **T3** (addressee: does it bind an implementation of this protocol at all?).
4. **T2** (for definitions: violability versus naming).
5. **T7** (content beats section location).
6. **T1** (atomicity and first-site deduplication).
7. **T5** (doubt resolves normative). Residual: it fires only when 1 through 6 leave the verdict
   open, and when it fires the row is marked `doubt`.

---

## 6. What is not a reason

Recorded so that these arguments are recognizable when they appear:

- "It is in a rationale section." Presumption only, defeated by T7.
- "It is hedged." Recorded in `strength`, defeated by T6.
- "It has no requirement word." Expected in a 1982 document, defeated by R-1.
- "It is obvious." Obvious obligations are obligations.
- "The example already shows it." Only a reason when the example restates a row that exists
  elsewhere, per T1; never a reason to drop the obligation entirely.
- "It would not be checkable." Void under T12.

---

## 7. Coverage classes

Every normative row carries exactly one class. Coverage is reported per class, because a single
aggregate number lets a run look complete by discharging many easy format rows and no reception
rows.

| Class | Contents | Expected principal sites |
| --- | --- | --- |
| `C-FORMAT` | Field identity, order, and meaning in the packet | 131-155 |
| `C-ENCODE` | Byte order, word-versus-byte, padding, widths, variable-length extents | 63-66, 146-155, 320-323 |
| `C-CONST` | Enumeration and constant values visible on the wire | 122-126, 179, 238 |
| `C-GEN` | Packet generation and field assignment for emitted packets | 158-190 |
| `C-RECV` | Reception algorithm tests, branches, and ordering between steps | 197-225 |
| `C-TABLE` | Translation table state transitions: merge, add, supersede | 209-218, 231-234 |
| `C-ERR` | Discard, fall-through, and exception behavior | 170-175, 200-201 |
| `C-PARAM` | Generalization beyond 10Mbit Ethernet, length determination | 236-242, 288-291 |
| `C-ASSUME` | Environment assumptions the protocol relies on (N10) | 91-93, 423-424 |

---

## 8. The consequence of the conservative tie-break

T5 and T11 deliberately over-include. Rows will enter the denominator that are then dispositioned
out: the whole aging and timeout discussion (lines 415 to 457) rows under T11 and leaves again
under `OUT-BY-SOURCE`; the monitor conflict sentence rows under T5 and leaves under `OUT-ROLE`;
every encoding rule rows under N3 and leaves under `OUT-WIRE`.

This is the intended behavior, and it has one specific consequence that is stated here rather than
discovered later:

> **The exclusion ratio is meaningless and will not be reported as a quality measure.** A rubric
> that over-includes on purpose can be made to show any ratio at all by adjusting how aggressively
> T5 fires. The denominator is safe (it does not shrink to fit what was checked), and the price is
> that "N% of rows were excluded" carries no information about the work. The writeup does not
> present such a ratio, and a ratio ceiling is not a gate criterion.

What is measured instead:

1. **Class-stratified coverage** from section 7: discharged, dispositioned out, and outstanding,
   reported per class.
2. **A closed barrier list.** Every normative row that is not discharged carries exactly one code
   from this list and nothing else:

| Barrier | Meaning | Stage B basis |
| --- | --- | --- |
| `OUT-WIRE` | Below the decode boundary: bytes, offsets, lengths as extents | section 2 |
| `OUT-ORDER` | Needs an order the RFC does not define (time, recency, sequence) | section 3 |
| `OUT-ENVIRONMENT` | An obligation on another layer or another component | section 5 |
| `OUT-ROLE` | An obligation on a role a conforming node is not required to play | section 5 item 5 |
| `OUT-BY-SOURCE` | The document declares the topic outside its own scope | section 7 |
| `OUT-MULTINODE` | Needs more than one modeled node or a network-wide claim | section 1 |
| `UNDERSPECIFIED` | The document states no determinate obligation to check | section 4 item 3 |

No row may carry a code outside this list, no row may carry two, and "not attempted" is not a
code. Extending the list requires an amendment under section 11 that names the row which forced
the extension. The point of closing the list now is that a barrier vocabulary invented while
writing up results can absorb any failure.

---

## 9. Worked applications

These demonstrate the rules on the cases most likely to be decided inconsistently. They are rule
demonstrations, not an extraction and not a clause list. They **bind**: if extraction classifies
one of these differently, either extraction is wrong or the rubric is amended under section 11.

1. **Line 23, "a 48.bit Ethernet address must be generated" (abstract).** A requirement word
   inside metadata. T3 runs before everything else that could save it: the addressee is Ethernet
   hardware, not this module. Verdict non-normative (X3), with `word: "must"` recorded so the
   audit can see that a `must` was declined and why.

2. **Lines 65 to 66, "special care must be taken with the opcode field".** Normative (N3, N8),
   `word: "must"`, `strength: R-REQ`, `class: C-ENCODE`, `barrier: OUT-WIRE`. The bottom-left cell
   of section 0: a genuine requirement of the document that this run cannot check.

3. **Line 70, "requests should be submitted to David C. Plummer".** A `should` that binds a person
   registering a hardware number. T3 fires before T5 gets a chance. Non-normative (X6),
   `word: "should"`.

4. **Lines 115 to 126, the definitions paragraph.** Split by T2 inside one paragraph: the four
   `ether_type$` names arrive without values and are metadata (X3); `ares_op$REQUEST (= 1)`,
   `ares_op$REPLY (= 2)`, and `ares_hrd$Ethernet (= 1)` fix wire-visible values and are normative
   (N4, `class: C-CONST`). Line 139 separately requires the Ethernet type field to carry
   `ether_type$ADDRESS_RESOLUTION` (N3, `class: C-FORMAT`).

5. **Line 166, "some lower layer (probably the hardware driver) must consult the Address
   Resolution module".** Normative (N1, N8), `word: "must"`, `class: C-GEN`. The hedge `probably`
   qualifies **which layer** does the consulting, not whether the consultation happens, so
   `strength` stays `R-REQ`. Recording which word the hedge attaches to is part of the row.

6. **Lines 170 to 175, the lookup miss.** One sentence, three obligations, split by T1: the table
   lookup on a hit returns the address to the caller (normative, `C-GEN`); on a miss the packet is
   discarded (normative, `C-ERR`); and the module "probably informs the caller that it is throwing
   the packet away" (normative under T5 and T6, `word: "probably"`, `strength: R-HEDGE`,
   `barrier: OUT-ENVIRONMENT` per Stage B section 7). The third row is exactly the kind T5 adds and
   disposition removes.

7. **Lines 184 to 188, `ar$tha` in a generated request.** Two rows under T1, not one. First: "It
   does not set ar$tha to anything in particular" is a normative underspecification (T10, N5,
   `strength: R-IND`, `barrier: UNDERSPECIFIED`), which is what lets Stage B carry the field as an
   unconstrained value (`01-scope/scope.md` section 4 item 3). Second: "It could set ar$tha to the
   broadcast address ... if that makes it convenient" is a normative permission (N8,
   `word: "could"`, `strength: R-OPT`). A reader who merged these into one row would lose the
   distinction between "unconstrained" and "one named legal value", so T1 splits.

8. **Lines 415 to 457, aging and timeouts.** The disclaimer sentence at 415 to 416 is metadata
   (X3). Everything around it rows under T11: "it should not be allowed to persist forever" (line
   429, `R-REC`), "Perhaps failure to initiate a connection should inform the Address Resolution
   module to delete the information" (lines 430 to 432, `R-HEDGE`), "perhaps receiving of a packet
   from a host should reset a timeout" (lines 434 to 437, `R-HEDGE`), and the daemon procedure
   (lines 449 to 455, `R-HEDGE`). All normative, all `class: C-TABLE`, all
   `barrier: OUT-BY-SOURCE`, several also `OUT-ORDER`; where both apply, `OUT-BY-SOURCE` is
   recorded, because the document's own declaration is the stronger and earlier reason. This
   single decision adds several rows that all disposition out together, which is the trade section
   8 accepts.

9. **Lines 337 to 340, the monitor's unconditional table entry.** "When a monitor receives an
   Address Resolution packet, it always enters the <protocol type, sender protocol address, sender
   hardware address> in a table." X8 does not reach it, because it is not a restatement: it
   contradicts the target gate at line 214. A reader could take it as permission for a mode a
   conforming node may implement, which is precisely the disagreement T5 is for. Normative,
   `confidence: doubt`, `class: C-RECV`, `barrier: OUT-ROLE` per Stage B section 5 item 5.

10. **Lines 423 to 424, "48.bit Ethernet addresses are supposed to be unique and fixed for all
    time".** No implementation can violate it, so T2's violability test alone would drop it. The
    reliance test in N10 rescues it: the protocol's correctness argument at lines 419 to 424
    depends on it. Normative, `class: C-ASSUME`, `word: "supposed"`, `strength: R-HEDGE`,
    `barrier: OUT-ENVIRONMENT`.

11. **Lines 441 to 447, "on a perfect Ethernet where a broadcast REQUEST reaches all stations on
    the cable, each station will be get the new hardware address".** A `will` in a rationale
    section stating a network-wide outcome under an explicit idealization. T7 gives the rationale
    presumption a chance and T5 takes it back, since a reader could read this as the supersession
    rule's intended effect. Normative, `confidence: doubt`, `class: C-TABLE`,
    `barrier: OUT-MULTINODE`, and related to Stage B's gap G-2.

---

## 10. What this rubric refuses to do

- It does not decide whether a row is checkable, in scope, or discharged. Those are Stage B and
  later stages.
- It does not repair the document. Where RFC 826 is ambiguous (T9), underspecified (T10), or
  internally inconsistent (case 9 above), the row records that and stops. A rubric that resolves
  ambiguities silently produces a denominator for a protocol nobody wrote, which is the same
  failure Stage B named in its section 5 item 2.
- It does not import requirements from RFC 1122, RFC 5227, RFC 5494, or from what ARP
  implementations actually do. Rows come from the pinned text only, and T4 is the single narrow
  channel through which an external document can affect a row at all.
- It does not weight rows. A packet field row and the merge rule each count one. Importance is
  reported through classes (section 7), not through a weighting the rubric would have to invent.

---

## 11. Amendment rule

This rubric is wrong if any of the following happens during extraction:

1. A sentence of RFC 826 carries an obligation and no `N` rule or `X` rule reaches it without a
   new rule being invented.
2. Two rows both claim to own the same obligation, and T1's first-site rule does not separate
   them.
3. A normative row needs a barrier code that is not in the closed list in section 8.
4. This rubric's verdict conflicts with a Stage B disposition of `OUT-NONNORMATIVE` on the same
   text (this rubric governs the denominator; the conflict is still logged).
5. T4 is invoked, which requires naming the amending document and section.

The fix in every case is an **appended, dated amendment** naming the row that forced it and the
rule that failed. Numbered rules above are not edited and verdicts already recorded are not
rewritten. A rubric that is allowed to follow the extraction results is a rubric fitted to the
clauses, which is the failure this stage exists to prevent.

**Amendment log:** empty at time of writing.

---

## Appendix A: requirement-word census of the pinned text

Uppercase RFC 2119 keywords: **zero occurrences** of `MUST`, `SHALL`, `SHOULD`, `MAY`,
`REQUIRED`, `RECOMMENDED`, `OPTIONAL`. Uppercase `REQUEST`, `REPLY`, `NOW` (line 219), and
`AFTER` (line 309) are opcode names and emphasis, never requirement levels.

Lowercase modal and requirement words, with every line on which each appears:

| Word | Count | Lines |
| --- | --- | --- |
| `will` | 23 | 57, 59, 61, 174, 230, 254, 265, 275, 276, 285, 344, 346, 359, 363, 407, 408, 409, 419, 422, 447, 456, 460, 465 |
| `can` | 12 | 75, 108, 282, 303, 331, 339, 341, 357, 364, 439, 461, 463 |
| `needed` | 9 | 27, 68, 96, 133, 165, 258, 296, 305, 451 |
| `should` | 8 | 70, 240, 289, 321, 353, 429, 430, 434 |
| `may` | 8 | 239, 294, 316, 361, 362 (x2), 415, 438 |
| `probably` | 6 | 166, 173, 231, 258, 266, 396 |
| `could` | 6 | 82, 186, 263, 346, 347, 425 |
| `perhaps` | 5 | 167, 430, 433, 439, 464 |
| `must` | 5 | 23, 65, 166, 348, 457 |
| `would` | 4 | 262, 282, 283, 344 |
| `necessary` | 3 | 299, 302, 334 |
| `optionally` | 2 | 205, 208 |
| `might` | 2 | 85, 87 |
| `supposed` | 1 | 423 |
| `requires` | 1 | 91 |
| `optional` | 1 | 291 |
| `needs` | 1 | 468 |
| `hopefully` | 1 | 408 |
| `desirable` | 1 | 415 |

Reproduction command:

```
rg -oin '\b(must|shall|should|may|might|can|could|will|would|required|requires|necessary|needed|needs|optional|optionally|probably|perhaps|hopefully|recommended|desirable|supposed)\b' 00-source/rfc826.txt
```

Two observations that shaped section 1. The hedge vocabulary (`probably`, `perhaps`, `could`,
`might`, `hopefully`, `desirable`, `supposed`: 22 occurrences) is larger than the obligation
vocabulary (`must`, `necessary`, `requires`: 9 occurrences, of which several bind nobody in this
protocol). And the densest requirement region in the document, the reception algorithm at lines
197 to 225, contains exactly two modal words, both of them `optionally` (lines 205 and 208), both
marking a check the implementation may skip. Every obligation in the algorithm block, including
every test, assignment, and branch, is carried by imperative or indicative mood with no
requirement word present. A rubric that leans on words would score this document's core as
non-normative.


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
