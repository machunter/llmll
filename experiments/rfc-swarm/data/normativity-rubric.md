# Normativity rubric for pre-RFC-2119 prose (RFC-SWARM Phase 0)

Authored before extraction, applied uniformly, recorded per row. Required by the professor
review finding F-2: RFC 1350 is dated July 1992 and RFC 2119 (the MUST/SHOULD/MAY convention)
is March 1997, so the base RFC carries no requirement-keyword discipline and every normativity
judgment on it is interpretive. A rubric fixed in advance is what makes the denominator
auditable.

## Scope of application

- **RFC 1350** (TFTP Revision 2, July 1992): pre-2119. Apply the N/X rules below.
- **RFC 1123 §4.2** (October 1989): states its own uppercase requirement convention in its
  introduction, so MUST / SHOULD / MAY are read directly at face value. The N/X rules still
  decide what is a clause versus commentary (its DISCUSSION and IMPLEMENTATION blocks are
  explicitly non-normative).

## Normative (counts in the denominator)

- **N1 Imperative protocol behavior.** A sentence stating what an implementation does, sends,
  or is required to do on an event, in imperative or declarative-obligation form.
  Example shape: "The host sending the last DATA packet must ...".
- **N2 Packet-format definition.** Field layout, widths, order, terminators, opcode values,
  admissible value ranges, and the size discipline of any field.
- **N3 Explicit lowercase must / should / may.** 1992 prose uses lowercase requirement words;
  they carry normative force. Record the strength word in the row.
- **N4 State-machine transition.** What is sent or expected in response to a received packet,
  including initiation, continuation, and termination conditions.
- **N5 Error and exception behavior.** When an ERROR packet is sent, what each error code
  means, and what the recipient does with it.

## Non-normative (recorded, excluded from the denominator)

- **X1 Motivation, rationale, design commentary.** Includes RFC 1123 DISCUSSION blocks.
- **X2 Examples and illustrative traces.** Includes the RFC 1123 §4.2.3.1 numbered exchange.
- **X3 Historical notes and mail-mode text.** RFC 1350 retains mail mode only as deprecated
  history.
- **X4 Document metadata.** Status of memo, summary, acknowledgements, references, table of
  contents, page headers and footers, section titles.
- **X5 Statements about another protocol's behavior** not imposed on the TFTP implementation
  (for example how UDP or the underlying transport behaves).

## Tie-break rules

1. **One obligation per row.** A sentence carrying two separable obligations splits into two
   rows. A parenthetical qualifying a single obligation stays inside that row.
2. **Possibility versus permission.** A sentence describing what *can happen* in the world
   (a packet may be delayed) is X1. A sentence granting the implementer latitude (an
   implementation may choose) is N3.
3. **Definitions that constrain.** A definition is N2 or N4 when an implementation could
   violate it; it is X4 when it only names a thing.
4. **Amendment precedence.** Where RFC 1350 and RFC 1123 §4.2 conflict, RFC 1123 governs and
   the conflict is recorded on both rows.
5. **When in doubt, mark normative.** An over-inclusive denominator is conservative for the
   completeness claim: it can only lower the Encoded fraction, never inflate it.

## Output discipline

Every extracted row records: source file and line span, a short verbatim quote, the rule
applied (N1-N5 or X1-X5), and a one-sentence statement of the obligation. Rows are extracted
from the verbatim RFC text only. No disposition (Encoded / Deployment-modeled / Vectored /
Dispositioned out) is assigned during extraction: disposition is a downstream scoping decision,
and keeping it out of extraction is what makes the two independent extractions comparable.
