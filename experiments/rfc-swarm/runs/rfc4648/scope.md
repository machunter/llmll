# Scope decision: RFC 4648 (Base16, Base32, Base64 encodings)

Written before any clause is extracted. The boundary below is fixed now so it cannot be redrawn
around whatever happens to classify in later.

Source: `00-source/rfc4648.txt`, sha256 `84e14418f795d503be5f34bf23ce4ebaa119e9ec7c9f667d8caeb111385b178f`,
1011 lines. All line citations refer to that file.

---

## 0. The awkward fact this document has to start with

For most protocol RFCs, "string structure is outside the fragment" removes the packet parser and
leaves a protocol core behind. RFC 4648 has no packets, no headers, no state machine, and no
peers. What it specifies *is* a total function from octet sequences to character sequences. The
thing the fragment cannot reason about is not a wrapper around the subject matter; it is the
subject matter.

So the boundary cannot be "exclude parsing, keep the protocol". It has to cut through the middle
of the encoding itself. The cut this document makes:

> **The verifier carries one quantum. It does not carry the sequence of quanta.**

A quantum is the fixed-width unit the RFC defines the encoding in terms of: 24 bits to 4 symbols
for base64 (lines 291-296), 40 bits to 8 symbols for base32 (lines 433-442), 8 bits to 2 symbols
for base16 (lines 548-552). Inside one quantum everything is finite and fixed-width. Across
quanta, everything is an unbounded sequence.

Stating the consequence up front rather than at the end: **most of what makes base encoding
*correct* as a whole lives across quanta, and that part is out of scope.** What is in scope is
the per-quantum core, the finite alphabet tables, and the length arithmetic. Those are real
clauses with real normative force, and several of them are where the RFC's own security
argument lives. But a reader who takes "RFC 4648 verified" to mean "base64 is injective on all
inputs" would be reading something this project does not deliver, and section 7 below says so
in the terms the writeup must use.

---

## 1. The fragment, concretely

Three things the core may use, all decidable:

1. **Finite enumerated domains.** The alphabets are 64, 64, 32, 32, and 16 constants (Tables 1-5,
   lines 302-321, 399-418, 460-471, 526-537, 567-573), plus the pad symbol. Symbol values are
   0..63 / 0..31 / 0..15. Every alphabet property is a check over at most 64 constants.
2. **Fixed-width bitvectors, at most 40 bits.** Bit slicing within one quantum, including the
   MSB-first convention the RFC states at lines 438-442.
3. **Presburger arithmetic on input length.** The final-quantum case analyses (base64 cases 1-3,
   lines 332-349; base32 cases 1-5, lines 482-500) are case splits on `N mod 3` and `N mod 5`
   where `N` is the octet count. `N` is unbounded, and that is fine: residue arithmetic over
   unbounded integers is decidable.

This gives the sharpest form of the boundary, sharper than "one quantum":

> **Length arithmetic is in. Content indexing is out.**
>
> The core may say "the input is `N` octets and `N mod 3 = 1`". It may not say "the character at
> position `i` of the output", "the output contains a character such that...", "this occurs
> before the end of the encoded data", or "the concatenation of these two encodings".

Two admissions that belong here rather than buried later:

- **What is inside the boundary is finite, not merely decidable.** Discharging "the base64
  alphabet is injective" is enumeration over 64 constants. This is closer to exhaustive checking
  than to theorem proving. A clause count from this RFC should not be read as a difficulty
  measure. The work of this project is where the line falls, not how hard the inside of it is.
- **Closed ground instances are decidable regardless of fragment.** The 28 test vectors at lines
  652-713 are string-level statements, but each is a single closed instance and can be settled by
  evaluation. They are recorded as validation of the extracted tables, and they are explicitly
  **not** evidence for any quantified statement. "We checked 28 test vectors" is not verification
  and will not be presented as such.

---

## 2. Boundary 1: the wire-format boundary

**The protocol core operates on quantum values, and the character stream is excluded.** Stated
positively, in the terms this RFC uses:

**Inside.** A quantum is modeled as a pair: a fixed-width bit group (24 / 40 / 8 bits, possibly
partial) and the tuple of symbol values it maps to (4 / 8 / 2 values, possibly with pad
positions). The bit slicing between them is a fixed-width function. The alphabet lookup is a
finite map. The pad-bit region of a partial final quantum is a named fixed-width subfield with a
value, and the number of pad symbols is a function of the residue class.

**Outside.** Segmenting a received character sequence into quanta. Concatenating encoded quanta
into an output sequence. Any predicate over the output string as a whole. Any positional
predicate.

Three clauses show exactly what this costs, and each is named now so it cannot be quietly
recovered later:

- **Line 200-203, "MUST reject the encoded data if it contains characters outside the base
  alphabet."** The per-symbol classification (this symbol is in-alphabet / is pad / is neither) is
  a finite decidable check and is in scope. The clause's actual force is the existential over an
  unbounded string plus the whole-message rejection it triggers. That is out of scope. The core
  carries the classifier, not the clause. This split will be reported as a split, not as a win.
- **Line 208-213, "MAY ignore the pad character '=' ... if it is present before the end of the
  encoded data."** "Before the end" is a positional predicate over an unbounded string. Out on
  those grounds independently of the fact that a MAY has no falsifiable content.
- **Line 652, `BASE64("") = ""`.** Zero quanta. A quantum-scope model has nothing to say about
  an input with no quanta. This is a genuine hole the boundary opens, and the empty-input case
  is recorded as uncovered rather than treated as vacuously satisfied.

The relationship between what is proved and what a reader wants proved, stated once, precisely:

> Per-quantum injectivity plus canonical pad bits is a **lemma toward** stream-level injectivity.
> The remaining step, that a unique segmentation of the stream into quanta exists and that
> concatenation of injective pieces is injective, is an induction over an unbounded list. That
> step is out of scope, is not attempted, and is not assumed as an axiom to make the top-level
> statement typecheck. The top-level statement is simply not among the results.

**Byte-level and NUL-related material, excluded on this boundary.** Line 751-752, "A decoder
should not break on invalid input including, e.g., embedded NUL characters," is both an
implementation-robustness statement and a statement about NUL inside a character sequence. Out.
Line 749-751, the buffer-overflow caution, is advisory prose with no testable predicate. Out.

---

## 3. Boundary 2: the ordering boundary

**RFC 4648 has no sequence numbers, no session, no counters, and therefore no rollover. There is
nothing here to import an order from, and none is imported.** The core reasons about symbols and
octets by **equality and disequality only**: alphabet membership, table injectivity, pad-symbol
identity, non-alphabet classification, and pad-bit-equals-zero are all equality predicates over
finite domains.

Two places where an order appears, and the different status of each:

**(a) The order the RFC itself defines: bit significance.** Lines 438-442 fix that a base32 bit
stream "must be presumed to be ordered with the most-significant-bit first," and the figures at
lines 584-588 and 595-607 fix the bit layout for base64 and base32. This is not an imported
order; it is the RFC defining its own bit indexing, and it is internal to a fixed-width quantum.
In scope, on the RFC's own authority.

**(b) The order the RFC asserts but does not define: sort order, line 519-521.** "One property
with this alphabet, which the base64 and base32 alphabets lack, is that encoded data maintains
its sort order when the encoded data is compared bit-wise."

This decomposes into two claims with different verdicts.

- **Per-symbol monotonicity: in scope.** For all values `v < w` in `0..31`, the base32hex encoding
  of `v` has a smaller US-ASCII code than that of `w`. This is 496 pairs over 32 constants, fully
  finite. It is also the claim's actual content, and it is true: values 0-9 map to `0x30..0x39`
  and values 10-31 map to `0x41..0x56`, both strictly increasing, with `0x39 < 0x41`. The
  contrast the RFC draws is likewise checkable: base32 breaks monotonicity at value 25 (`Z`,
  `0x5A`) to value 26 (`2`, `0x32`), and base64 at value 51 (`z`, `0x7A`) to value 52 (`0`,
  `0x30`).
- **String-level lexicographic lifting: out of scope, and out for a second reason beyond string
  structure.** The sentence does not say whether the compared data includes padding, and with
  padding the claim is false. Base32hex of the single octet `0x00` is `00======`; base32hex of
  the two octets `0x00 0x00` is `0000====`. The pad character `=` is `0x3D`, which sorts above
  the digits `0x30..0x39`, so `00======` sorts **above** `0000====`, while as octet sequences
  `[0x00]` is a proper prefix of `[0x00, 0x00]` and therefore sorts **below** it. The property
  holds for equal-length inputs, which is the NSEC3 usage the RFC cites at line 517, and the RFC
  does not state that restriction.

Point (b) is the concrete reason the string-level statement stays outside rather than being
attempted: promising it would mean promising something whose unrestricted form is not true.

**Positional order over the stream is not imported anywhere.** If a later stage finds it needs
"position `i` precedes position `j`", that is not available and is not to be added silently. It
would be a new recorded modeling decision, entered in section 5, with the reason it became
necessary.

---

## 4. Boundary 3: what the modeled state deliberately carries

Each item below is inside the boundary because it defends against something an attacker can do.
The attacker model is not invented; it is the RFC's own, at lines 194-198 and 749-768. The test
applied to each is "does this rule stop an attack", not "can this be expressed".

**(a) Three-way symbol classification: in-alphabet, pad, neither.** Not a two-way in/out flag.

*Attacker justification.* Lines 754-760: if non-alphabet characters are ignored rather than
rejected, "a covert channel that can be used to 'leak' information is made possible," and the
ignored characters "could also be used ... to avoid a string equality comparison or to trigger
implementation bugs." The attack lives exactly in the third class. The pad symbol needs its own
class rather than joining the non-alphabet class because lines 208-213 give `=` a distinct
permission that no other out-of-alphabet character has. Collapsing pad into non-alphabet would
make the model unable to state the rule the RFC actually wrote. A two-way flag would be equally
expressible and would misrepresent the specification.

**(b) The value of the pad bits in a final quantum, not only their count.**

*Attacker justification.* Lines 765-768: the non-significant bits "may be abused to leak
information or used to bypass string equality comparisons or to trigger implementation problems."
Line 253-263 makes the same point structurally: if pad bits are not zero, multiple encoded
strings decode to the same binary data. An attacker who controls those bits produces a distinct
encoding of identical data, defeating any receiver comparing encoded forms. Carrying only the
*width* of the pad region would be expressible, would let the model state cases 1-3 and 1-5, and
would prove nothing at all about this attack. The value is what makes line 257-258 defend
something.

**(c) The decoder leniency mode as an explicit state variable.** Two independent flags: reject
versus ignore non-alphabet characters (lines 200-206), and reject versus accept non-zero pad bits
(lines 265-268).

*Attacker justification.* The covert channel at lines 754-760 exists precisely in the lenient
setting and not in the strict one. The same clause set is safe under one mode and exploitable
under the other, so the mode is an attacker-relevant parameter rather than a configuration
detail. Carrying it means every conclusion is stated with the mode it holds under. Omitting it
would mean proving results under the strict default and presenting them as unconditional, which
is the precise error this stage exists to prevent.

### What the state refuses to carry, though it easily could

**Line position and line length (section 3.1, lines 150-163).** A line-position counter is
bounded at 76 or 64, trivially expressible, and would let the model state the line-feed rule as a
counter invariant. It is excluded. Line 161-163's "MUST NOT add line feeds" is an interoperability
rule, not a defense: no attacker gains anything from line position, and the RFC's security
section never mentions it. Adding the counter would produce a clause and an invariant and would
defend against nothing. This is the exact shape of what buys a number and proves nothing, and it
is named here so the temptation is on the record. The rule is retained only in its flat form: LF
is not in the encoder's output alphabet under the default profile.

**Buffer sizes, allocation, and memory behavior (lines 749-751).** Implementation properties, not
properties of the encoding. Excluded, and the corresponding advisory text is classified out in
section 6 rather than reshaped into something checkable.

**Case folding baked into the alphabet tables.** Excluded as a table property, carried instead as
a profile flag under (c). Reason in section 5, decision 1.

---

## 5. Recorded modeling decisions

Choices the RFC does not settle. Recorded now, so none of them is a silent import.

**Decision 1: alphabet tables are exact; decoder case folding is a profile flag defaulting to
off.** The RFC is genuinely ambiguous. Line 542-543 calls base16 "the standard case-insensitive
hex encoding", Table 5 lists only uppercase, line 458 says base32 characters are "selected from
US-ASCII digits and uppercase letters", and lines 231-235 discuss case-dependent decoder
leniency while directing that "by default it should not". Line 761-763 then treats case
alteration as an attack surface. The encoder tables are taken as written (uppercase). Acceptance
of lowercase on decode is a flag, not a table change, so that results state which case discipline
they hold under. The flag earns inclusion under the section 4 test via lines 761-763.

**Decision 2: the "unless the referring specification states otherwise" escape appears in three
MUST clauses (lines 161-163, 182-184, 200-203) and is modeled as a profile parameter defaulting
to strict.** Strict is the RFC's own default in each case. Every conclusion about these three
clauses is stated relative to the profile. None is stated unconditionally.

**Decision 3: the section 7 sort-order property is scoped to equal-length inputs.** Recorded as an
assumption rather than derived, because the RFC does not state it and the unrestricted claim is
false. Counterexample in section 3(b).

**Decision 4: the empty input is uncovered, not vacuous.** Zero quanta falls outside a
quantum-scope model. `BASE64("") = ""` and its four siblings at lines 652, 666, 687, 701 are
recorded as a gap in coverage, not as trivially satisfied.

---

## 6. The scope matrix

Pre-committed before extraction. `IN` = expected to classify into the fragment at quantum or
length scope. `SPLIT` = a decidable core is in, the clause as written is not, and both halves get
reported. `OUT` = not attempted.

| RFC location | Content | Verdict | Reason |
|---|---|---|---|
| L161-163 | MUST NOT add line feeds | IN (profile) | Flat output-alphabet predicate; no position counter (section 4) |
| L182-184 | MUST include pad characters | IN (profile) | Pad count is a function of residue class; Presburger on length |
| L186-188 | base16 needs no padding | IN | Residue mod 1 is always 0 |
| L200-203 | MUST reject non-alphabet characters | SPLIT | Per-symbol classifier IN; existential over unbounded string OUT |
| L206-208 | CRLF are non-alphabet characters | IN | Membership check over finite alphabet |
| L208-213 | MAY ignore `=` before the end; MAY ignore excess pads | OUT | Positional predicate over a string, and permissive modality |
| L215-249 | Choosing the alphabet | OUT | Advisory; its one "should" at L234-235 forwards to section 3.3 |
| L253-256, L259-263 | Non-canonical encodings collide | SPLIT | Per-quantum collision IN; stream-level uniqueness OUT |
| **L257-258** | **Pad bits MUST be set to zero** | **IN** | Fixed-width subfield of one quantum; strongest clause in the RFC |
| L265-268 | Decoders MAY reject non-zero pad bits | OUT as clause | MAY has no falsifiable content; the mode it names is carried per 4(c) |
| L287-296, Table 1 | base64 alphabet and 24-to-4 mapping | IN | 64 constants plus fixed-width slicing |
| L323-349 | base64 final-quantum cases 1-3 | IN | Finite case split on `N mod 3` |
| Table 2 (L399-418) | base64url alphabet | IN | Finite table; differs from Table 1 at indices 62, 63 |
| L367-370 | Naming: "should not be referred to as only base64" | OUT | Naming guidance, not a property of encoded data |
| L429-442, Table 3 | base32 alphabet, 40-to-8, MSB-first | IN | 32 constants; bit order defined by the RFC itself (section 3a) |
| L473-500 | base32 final-quantum cases 1-5 | IN | Finite case split on `N mod 5` |
| Table 4 (L526-537) | base32hex alphabet | IN | 32 constants |
| L519-521 | base32hex preserves sort order | SPLIT | Per-symbol monotonicity IN; string lifting OUT and false unrestricted (section 3b) |
| L545-552, Table 5 | base16 alphabet and 8-to-2 mapping | IN | 16 constants |
| L575-576 | No special padding for base16 | IN | Follows from residue mod 1 |
| L580-607 | Bit-layout figures | IN | Fixes bit indexing within a quantum |
| L623-648 | Three worked examples | IN as instances | Per-quantum ground truth; validation, not theorems |
| L652-713 | 28 test vectors | IN as instances | Closed instances, decidable by evaluation; explicitly not evidence for quantified claims |
| L735-745 | Reference C99 implementation | OUT | L742: "This code is not normative" |
| L749-752 | Buffer overflow; do not break on NUL | OUT | Implementation advice; NUL-in-string is string structure |
| L754-768 | Covert channel, case leak, pad-bit leak | OUT as clauses | Advisory prose with no MUST; source of the section 4 attacker model |
| L770-781 | Base encoding is not confidentiality | OUT | Advisory |
| — | Stream-level injectivity of any codec | OUT | Induction over an unbounded sequence; not attempted, not axiomatized |
| — | Empty input | OUT (gap) | Decision 4 |

Expected shape: roughly a dozen clauses fully IN, four SPLIT, and every statement quantified over
a whole encoded string OUT. If extraction returns materially more than that, the excess is to be
treated as a boundary violation to investigate, not as a better-than-expected result.

---

## 7. What would count as scope creep, pre-committed

Named now so that later work is measured against this list rather than against a boundary redrawn
to fit it.

1. **Any top-level statement of the form "BASE-N is injective" or "decode(encode(x)) = x" for
   unbounded `x`.** Either it smuggles in a string axiom or it quietly redefines `x` as a single
   quantum. Both are scope creep. If a general statement appears, the segmentation and
   concatenation step must be shown, and it cannot be, so it will not appear.
2. **Reporting the SPLIT rows as satisfied clauses.** Four rows have a decidable core and an
   undecidable clause. The writeup reports both halves for each, in the same sentence.
3. **Adding a line-position counter, a buffer-size variable, or a stream-position order** to make
   an additional clause classify in. Section 4 rejects the first two and section 3 rejects the
   third. Any of them appearing later is a regression against this document.
4. **Presenting the 28 test vectors or the 3 worked examples in a count alongside proved
   clauses.** They are validation instances. They go in a separate column with a separate label.
5. **Dropping the profile qualifier** from the three "unless the referring specification states
   otherwise" clauses, or the case-discipline qualifier from base16 and base32 results.
6. **Quoting the section 7 sort-order property without the equal-length restriction**, given that
   the unrestricted form has a counterexample recorded in section 3(b).

The headline of the writeup is this matrix, including the OUT column. It is not a disclaimer
appended after the numbers.
