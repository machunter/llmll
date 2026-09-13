# Stage B: Verification Scope for RFC 826

**Written before any clause is extracted.** Nothing below is chosen by looking at what the
solver happens to discharge. The boundary stated here is the boundary the writeup reports,
whether or not the clauses that land inside it turn out to be interesting.

## 0. What this document is committing to

Source under study: `00-source/rfc826.txt`, sha256
`01bc62fe6a37e90f1246ac43e8e145f1322b4ed1474836145c3da93d2bd3c8a6`, 470 lines, from
`https://www.rfc-editor.org/rfc/rfc826.txt`. All line citations below refer to that file.

Three commitments, in order of how much trouble they save later:

1. The protocol core operates on **decoded packet values**. Byte-level parsing is outside.
2. The core reasons by **equality and disequality only**. RFC 826 defines no sequence space,
   no timestamps, no version counters, and no order on any field. None is imported.
3. Everything the modeled state carries beyond the protocol's own variables is justified by
   an attacker model, and where the attacker-model test fails, the item is excluded even
   though it is expressible and would have produced another checked row.

## 1. The fragment

Obligations are discharged as quantifier-free queries in the combination of:

- **Uninterpreted functions and equality (EUF)** over uninterpreted sorts `HwType`,
  `ProtoType`, `HwAddr`, `ProtoAddr`, `Len`.
- **Algebraic datatypes** for the decoded packet record and for the translation-table key.
- **Extensional arrays** (`select` / `store`) for the translation table.
- A **finite enumeration** for the opcode: `REQUEST`, `REPLY`, `OTHER`.

No arithmetic. No strings or sequences. No quantifiers in the verification conditions; frame
conditions on the table are expressed with `store` rather than with a universally quantified
"all other keys unchanged". The combination is decidable, and each query stays inside it.

Proof obligations come in exactly two shapes:

- **Single-step verification conditions**: one reception or one generation event, pre-state to
  post-state. Quantifier-free, decidable.
- **k-induction over one node's step relation**, when a clause is stated as an invariant. The
  base and step queries are each quantifier-free and decidable.

Explicitly not attempted: unbounded quantification over a set of nodes, over table keys, or
over network topologies. Multi-node claims (for example the X/Y exchange at lines 370-410) are
checked as **bounded traces** only. The RFC's own network-wide claim at lines 459-466 ("Bad
information can't persist forever by being passed around from machine to machine") is
therefore not going to be proved in its global form; see section 8.

### Sorts and the functions over them

| Symbol | Type | Source |
| --- | --- | --- |
| `hlen` | `HwType -> Len` | lines 288-291, "length ... determined by the hardware type" |
| `plen` | `ProtoType -> Len` | lines 288-291 |
| `six` | `Len` | lines 179, 238; `hlen(Ethernet) = six` |
| `bcast` | `HwType -> HwAddr` | lines 186-187, broadcast address is hardware-specific |
| `haveHw` | `HwType -> Bool` | line 203, "?Do I have the hardware type in ar$hrd?" |
| `speaks` | `ProtoType -> Bool` | line 206, "?Do I speak the protocol in ar$pro?" |
| `myHw` | `HwAddr` | lines 181, 221-222 |
| `myPa` | `ProtoType -> ProtoAddr` | lines 182, 214; a node has one address per protocol |
| `table` | `Array(Key, Option(HwAddr))`, `Key = (ProtoType, ProtoAddr)` | lines 210-213 |

`Len` is an uninterpreted sort with named constants, not a number. Every use of a length in
the core is an equality (`hln = hlen(hrd)`, `hln = six`), never a comparison or an offset.
This is the length-field analogue of the ordering commitment in section 3.

## 2. The wire-format boundary

**The protocol core operates on decoded packet values. Parsing is excluded.**

RFC 826's packet data (lines 141-155) is not a fixed-layout record. Four of its nine fields
are variable-length, and their lengths come from two other fields in the same packet:

```
 8.bit: (ar$hln) byte length of each hardware address
 8.bit: (ar$pln) byte length of each protocol address
nbytes: (ar$sha)  n from the ar$hln field
mbytes: (ar$spa)  m from the ar$pln field
nbytes: (ar$tha)
mbytes: (ar$tpa)
```

Lines 320-323 make the byte-stream reading explicit: no padding between addresses, and only
three of the fields (`ar$hrd`, `ar$pro`, `ar$op`) are words, sent most significant byte first.

Recovering the four address fields means computing offsets `8`, `8+n`, `8+n+m`, `8+2n+m` and a
total extent `8+2n+2m`, then slicing a byte sequence at attacker-chosen, length-dependent
positions. That is arithmetic over lengths plus indexed extraction from a sequence: the theory
of strings/sequences with length-parameterized substring, which is not in the fragment of
section 1 and is not decidable in general. Pulling it inside would either import integer
arithmetic and an order on lengths (forbidden by section 3) or force quantification over byte
indices.

The boundary is therefore an assumed interface:

```
decode : ByteString -> Option(Packet)
```

The core assumes exactly one thing about `decode`: when it yields `Some(p)`, the fields of `p`
are well-sorted values of the sorts in section 1. The core does **not** assume `decode` is
total, injective, length-checking, or that `encode . decode` round-trips. No obligation
discharged inside the core says anything about `decode`.

### What this costs, stated now rather than in a disclaimer

- **The entire malformed-input class is outside.** An attacker chooses `ar$hln` and `ar$pln`,
  and those two bytes are what a real implementation uses as slice bounds. Truncated packets,
  length fields that overrun the frame, `hln`/`pln` of zero or 255: this is where ARP parsers
  actually break, and the verified region says nothing about any of it.
- **The optional length check has two readings, and only one is inside.** Lines 205 and 208
  suggest checking `ar$hln` and `ar$pln`. Read as "the declared length matches the length
  expected for this hardware and protocol type" (which is what lines 288-291 describe), it is
  `hln = hlen(hrd)` and is inside. Read as "the declared length matches the actual byte length
  of the encoded `ar$sha`", it is outside, because inside the boundary an address is an opaque
  value with no length at all. The core checks the first and cannot state the second.
- **Byte-order clauses are outside by construction.** Lines 63-66 (high byte first, "special
  care must be taken with the opcode field") and lines 320-323 are about encoding, and they
  classify as OUT-WIRE, not as unverified.

### The one asymmetry, and why it is there

Incoming frame headers are excluded (section 5, item 2). Outgoing hardware destinations are
included (section 4, item 5). The reason is not convenience: RFC 826 **assigns** the outgoing
destination normatively ("broadcast to all stations", lines 188-190; "Send the packet to the
(new) target hardware address", lines 224-225; "sends the packet directly (not broadcast)",
lines 400-401) and **never reads** an incoming frame header anywhere in the reception
algorithm. An emission destination is an output of a clause the RFC states. An arrival frame
header is an input to no clause the RFC states.

## 3. The ordering boundary

**The core reasons by equality and disequality only.**

RFC 826 defines no sequence numbers, no message identifiers, no timestamps, no generation
counters, and no version field. There is nothing in the packet that a receiver could compare
for recency, so there is no rollover question and no wrap-around semantics to model. Any order
in the model would be an import, not a reading.

Three places look like ordering and are not:

**Merge before opcode (lines 219, 227-229, 308-309).** "Notice that the ... triplet is merged
into the table before the opcode is looked at." This is control-flow sequencing inside the
handling of a single packet. It is compiled into the step relation as straight-line structure.
It is not an order on any data value, and it needs nothing from the fragment beyond what
section 1 provides.

**Supersession (lines 231-234, 443-445).** "if an entry already exists for the <protocol type,
sender protocol address> pair, then the new hardware address supersedes the old one." Nothing
in a packet tells a receiver which of two packets is newer. "New" here means "arriving later in
this node's event sequence", and the sequence is supplied by the model, not by the protocol.

> **Recorded modeling decision O-1.** Recency is the step index of the transition system. The
> table is threaded as state through a step relation, and "supersedes" is last-writer-wins with
> respect to step order. The step index is an index on the model's trace; it is never a field,
> never compared against packet contents, and no clause may be stated in terms of it beyond
> "the post-state of step i is the pre-state of step i+1". If a later stage needs to compare
> two packets for recency, that is a new modeling decision requiring its own record, because
> RFC 826 gives no basis for it.

**Timers and aging (lines 415-457).** The RFC puts these outside its own scope at lines
415-416: "It may be desirable to have table aging and/or timeouts. The implementation of these
is outside the scope of this protocol." The whole section is hedged ("perhaps", "may be
desirable", "another alternative"). Excluding it keeps a clock, a time order, and arithmetic
out of the core, and does so on the source's authority rather than on convenience.

Consequence, stated up front: no liveness or convergence property that depends on elapsed time
is in scope. No property of the form "a stale entry is eventually removed" will be claimed.

## 4. What the modeled state deliberately carries

Each item names the clause that cannot be stated without it.

1. **The translation table**, keyed by `(ProtoType, ProtoAddr)`. This is the protocol's own
   state variable. The merge rule (lines 210-213), the add rule (lines 216-218), and the
   supersession rule (lines 231-234) are all statements about it. Modeled as an extensional
   array so that "the entry for this key changed and nothing else did" is a `store` equation
   rather than a quantified frame condition.

   The key is `(protocol type, sender protocol address)` exactly as written at lines 210-213
   and restated at lines 232-233. `ar$hrd` is **not** in the key. This is transcribed as the
   RFC has it, not repaired; see section 8, gap G-3.

2. **The receiver's own configuration**: `haveHw`, `speaks`, `myHw`, `myPa`. The reception
   algorithm branches on all four (lines 203, 206, 214, 221-222). Uninterpreted predicates and
   functions, so a node is not tied to one hardware type or one protocol, which is what the
   generalization at lines 236-242 asks for.

3. **All nine decoded packet fields, including `ar$tha`**, even though line 312 says it "has no
   meaning in the request form" and line 184 says the sender "does not set ar$tha to anything
   in particular". The field is carried precisely so the underspecification is representable:
   in a generated REQUEST, `ar$tha` is an unconstrained value, and any obligation whose truth
   depends on it is a defect in the obligation. Dropping the field would silently resolve an
   ambiguity the RFC leaves open.

4. **Two free boolean constants** for the optional checks at lines 205 and 208
   (`checkHln`, `checkPln`). The RFC marks both as optional ("[optionally check ...]", and
   lines 288-292, "included for optional consistency checking"). Modeling them as free
   constants rather than as fixed choices means every obligation is discharged for both
   settings, so no property may quietly depend on an implementation doing an optional check.

5. **The emission**: whether a packet is emitted, its payload, and its destination hardware
   address. Required by the generation clauses (lines 176-190) and the reply clause (lines
   221-225). `bcast(hrd)` is a distinguished constant per hardware type, per lines 186-187.

   This is the one piece of transport surface brought inside, and it earns its place under the
   attacker-model test: a reply is unicast to the requester (lines 224-225, and lines 400-401,
   "sends the packet directly (not broadcast)"), so the rule constrains **who learns the
   mapping**. An implementation that broadcast replies would hand every station on the cable a
   free mapping it never asked for, which is something an attacker benefits from and a
   conforming implementation denies. The rule has content, so it is admitted.

## 5. What the modeled state deliberately excludes

The test applied to each is: does modeling this let the core check a rule that defends against
something an attacker can do, in the model as scoped? Where the answer is no, the item is out
even when it is easy to express.

1. **Arrival interface identity, and multi-interface nodes.** Lines 224-225 say to send the
   reply "on the same hardware on which the request was received". Tagging arrivals and
   emissions with an opaque interface identifier and asserting `reply.iface = request.iface`
   would cost one uninterpreted sort compared by equality, stay inside the fragment, and add a
   checked row.

   It is excluded anyway. In a single-interface node model the equality is true by
   construction, so the row would record a tautology and defend against nothing. Making it
   mean something requires a node with several interfaces carrying distinct hardware types and
   distinct hardware addresses, which is a materially larger model. That model is not in scope
   for this run, so the clause at lines 224-225 is classified OUT-ENVIRONMENT (an obligation
   on the host's interface dispatch layer), not verified. This is the case the
   attacker-model test exists to catch, so it is written down as the worked example of the
   test rather than quietly resolved.

2. **The Ethernet frame header** (lines 135-139: destination address, source address, type
   field). The tempting rule is "the frame source address must equal `ar$sha`", which is a real
   defense against a real attack. RFC 826 does not contain that rule, and the reception
   algorithm at lines 197-225 never reads the frame header. Carrying the header would let the
   core check a rule the source does not state, which produces a verified row about a protocol
   nobody wrote. Excluded, and recorded as gap G-1.

3. **Timers, aging, TTLs, retransmission counters, and the timeout daemon** (lines 415-457).
   Out on the source's own authority (lines 415-416), and out because they would require a
   clock and an order.

4. **Rate limits, table-size caps, and flood defenses.** Not in RFC 826 in any form. Entirely
   expressible as counters, and they would defend against a real attacker, and they would still
   be the ledger absorbing mechanics that buy a number and prove nothing about this document.
   Excluded.

5. **The monitor role** (lines 337-348). The monitor "always enters the <protocol type, sender
   protocol address, sender hardware address> in a table", with no target check. This is an
   application described inside a rationale section, not a requirement on a conforming node,
   and its rule directly contradicts the target gate at line 214. Admitting it would turn every
   table property into a disjunction over roles and weaken all of them. Excluded, along with
   the monitor's own REQUEST-loop hazard at lines 346-348.

6. **Upper-layer behavior.** "it probably informs the caller that it is throwing the packet
   away (on the assumption the packet will be retransmitted by a higher network layer)", lines
   172-175. Hedged, and about a layer above this protocol. Environment.

7. **Broadcast delivery semantics.** The core states that a request's destination is
   `bcast(hrd)`. Which stations receive it, and whether the cable is "perfect" in the sense of
   line 446, is environment.

8. **Buffer reuse** (lines 268-270). An implementation note about reusing the packet buffer for
   the reply. Not a constraint on observable behavior.

## 6. The attacker model

RFC 826 has no authentication of any kind. Sender fields are whatever the sender wrote. The
accurate attacker is therefore also the cheapest one, and it needs no additional state:

> At every step, the environment may deliver to the node under study **any well-sorted decoded
> packet**: arbitrary `ar$hrd`, `ar$pro`, `ar$hln`, `ar$pln`, `ar$op` (including `OTHER`),
> and arbitrary sender and target addresses, with no relation to any packet the node sent and
> no relation to any real station.

Two consequences follow directly from the boundaries above, and both are consequences to
report rather than weaknesses to hide:

- The attacker is **unbounded above** the wire boundary: it may forge every field the core can
  see, so cache-poisoning behavior is fully in scope and is expected to be demonstrable rather
  than refutable.
- The attacker is **cut off below** the wire boundary: it cannot deliver a byte string that
  fails to decode, because decoding is outside. Malformed-packet attacks are out of scope by
  the same decision that put parsing out, not by a separate judgment (section 2).

One specific in-scope consequence worth naming before extraction, because it follows from the
algorithm's own structure: the merge at lines 210-213 happens before the opcode test at line
219, so a packet with an opcode that is neither REQUEST nor REPLY still updates an existing
entry. Line 200-201 ("Negative conditionals indicate an end of processing and a discarding of
the packet") discards it only after the table has already been written.

## 7. Scope matrix

Dispositions: **IN-CORE** (clauses extracted and discharged), **OUT-WIRE** (byte-level, section
2), **OUT-ORDER** (needs an order the RFC does not define, section 3), **OUT-ENVIRONMENT**
(another layer or another component), **OUT-NONNORMATIVE** (rationale, example, or hedged
suggestion), **OUT-BY-SOURCE** (the RFC declares it out of its own scope).

| Lines | Content | Disposition | Reason |
| --- | --- | --- | --- |
| 1-111 | Front matter, abstract, the problem, motivation | OUT-NONNORMATIVE | Framing; no requirements |
| 63-66 | High byte first, care with `ar$op` | OUT-WIRE | Encoding |
| 112-126 | Definitions of `ares_op$REQUEST`, `ares_op$REPLY`, `ares_hrd$Ethernet` | IN-CORE (constants only) | Names the enumeration values; no behavior |
| 131-155 | Packet format, field widths and layout | Split | Field *identity* is the record signature (IN-CORE); widths, offsets, variable-length extents (OUT-WIRE) |
| 158-175 | Resolution lookup, discard on miss, request generation trigger | IN-CORE, partly | Table lookup and the decision to emit are IN-CORE; informing the caller and higher-layer retransmission are OUT-ENVIRONMENT (lines 172-175) |
| 176-190 | Field assignments for a generated REQUEST | IN-CORE | Equalities between emitted fields and local state |
| 184-188 | `ar$tha` "not set to anything in particular", may be broadcast | IN-CORE as underspecification | Modeled as unconstrained; see section 4 item 3 |
| 188-190 | Broadcast the request | IN-CORE (destination value only) | `dst = bcast(hrd)`; delivery is OUT-ENVIRONMENT |
| 197-201 | Discard on a negative conditional | IN-CORE | Defines the fall-through of every branch |
| 203-208 | Hardware-type gate, protocol gate, optional length checks | IN-CORE | With `checkHln` / `checkPln` free (section 4 item 4); actual-length reading is OUT-WIRE |
| 209-213 | Merge_flag, update sender hardware address for an existing key | IN-CORE | Core table clause |
| 214-218 | Target test, add triplet when Merge_flag is false | IN-CORE | Core table clause |
| 219-223 | Opcode test, swap, set `ar$op := REPLY` | IN-CORE | Reply construction |
| 224-225 | Send to the new target hardware address | IN-CORE (destination value) | Unicast to `req.sha` |
| 224-225 | "on the same hardware on which the request was received" | OUT-ENVIRONMENT | Section 5 item 1; vacuous in a single-interface model |
| 227-234 | Rationale for merge-before-opcode and supersession | IN-CORE as restatement | Extraction prefers the algorithm text; see O-1 for "supersedes" |
| 236-242 | Generalization to non-Ethernet hardware | IN-CORE as parametricity | `hrd` and `hln` stay uninterpreted |
| 245-287 | Why periodic broadcast is undesirable, one resolution per packet, buffer reuse, opcode width | OUT-NONNORMATIVE | Design rationale |
| 288-292 | Length fields redundant, determined by `hrd` and `pro` | IN-CORE | Supplies `hlen` / `plen` and the meaning of the optional check |
| 294-318 | Meaning of opcode, sender fields, `ar$tpa`, `ar$tha` | IN-CORE as underspecification records | Notably line 312, `ar$tha` has no meaning in a request |
| 320-323 | Byte stream, no padding, three words MSB first | OUT-WIRE | Encoding |
| 326-364 | Network monitoring and debugging, monitor algorithm, monitor REQUEST loop | OUT-NONNORMATIVE, and OUT by section 5 item 5 | Alternative role in a rationale section |
| 367-410 | The X/Y worked example | OUT-NONNORMATIVE as a clause source; used as a validation trace | See below |
| 396-401 | Reply field assignment as performed in the example | Disambiguation evidence only | Confirms the reading of "swap ... putting the local addresses in the sender fields" |
| 412-457 | Table aging, timeouts, the daemon, retransmissions | OUT-BY-SOURCE | Lines 415-416 declare it outside this protocol; also OUT-ORDER |
| 459-466 | "Hosts don't transmit information about anyone other than themselves"; bad information cannot propagate | IN-CORE in local form only | See gap G-2 |
| 468-470 | "This issue clearly needs more thought" | OUT-NONNORMATIVE | Not a requirement |

**The worked example at lines 367-410 is not a clause source.** It is used in two ways only:
as a bounded trace the model must be able to reproduce (a sanity check on the step relation),
and as disambiguation evidence for the reply construction at lines 221-222, where "swap" alone
would put the old target fields into the sender fields but lines 398-401 show the local
addresses going there. Both uses are recorded as such, and neither produces a verified row.

## 8. Gaps stated before extraction, not after

- **G-1. No frame-level sender check.** RFC 826 defines no relation between the Ethernet frame
  source address and `ar$sha`. The core cannot state one, because the frame header is out
  (section 5 item 2). The practical consequence is that a packet's sender fields are
  attacker-chosen, which the attacker model in section 6 represents directly.
- **G-2. The no-propagation claim does not survive the attacker model in its global form.**
  Lines 459-466 claim bad information cannot persist by being passed from machine to machine.
  What is provable here is the local form: every packet emitted by a conforming node carries
  that node's own `myHw` and `myPa(pro)` in the sender fields (lines 181-182 for a request,
  lines 221-222 for a reply). The global claim additionally requires every emitter to conform,
  and the attacker does not. The local form will be attempted; the global form will not be
  claimed.
- **G-3. `ar$hrd` is not part of the table key.** Lines 210-213 and 232-233 key the table on
  `<protocol type, sender protocol address>` while lines 236-242 contemplate a node speaking
  more than one hardware type. Whether that admits a collision is a question about a
  multi-hardware node, which is the model excluded in section 5 item 1. The key is transcribed
  as written and the question is recorded, not answered.
- **G-4. No liveness, no convergence, no timing.** Follows from section 3.
- **G-5. Nothing about parsing.** Follows from section 2, and it is the largest single gap by
  attack surface.

## 9. No promises about what classifies in

Sections 4 and 7 say where in-core clauses are expected to come from (the reception algorithm
at lines 197-225, the generation clauses at lines 176-190, and the length-determination rule
at lines 288-292). That is an expectation about extraction, not a commitment to a count and
not a claim that any particular clause will be discharged. No clause is promised verified
before Stage C extracts it and the classifier runs on it.

## 10. Amendment rule

This document is wrong if Stage C extracts a normative clause that falls into none of the
IN-CORE categories in section 4 and is covered by none of the OUT categories in sections 2, 3,
5, and 7.

If that happens, the fix is an **appended amendment**, dated, naming the clause and the reason
the original matrix missed it. Rows in section 7 are not edited and dispositions are not
rewritten. The point of writing the boundary before extraction is lost the moment the boundary
is allowed to follow the results, so the amendment record is what makes the scope matrix in
the writeup checkable rather than merely asserted.
