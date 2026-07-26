# Scope: RFC 826 (Ethernet Address Resolution Protocol)

**Source.** `rfc826.txt`, sha256 `01bc62fe6a37e90f1246ac43e8e145f1322b4ed1474836145c3da93d2bd3c8a6`, 470 lines.
All line references below are into those exact bytes.

**Status.** Written at Stage B, before any clause has been extracted and before any proof has been
attempted. The denominator is frozen here: 15 proof obligations (12 expected to hold, 3 expected to
fail). The final ledger reports against this list. A clause that classifies out later is a Stage B
scoping error and is reported as one, not as a footnote on a success rate.

---

## 1. The scope matrix

### 1.1 Carried: clauses the verifier will discharge

| ID | RFC lines | Clause | Depends on |
|----|-----------|--------|------------|
| C1 | 209-213, 227-234 | **Merge precedes opcode.** If `<ar$pro, ar$spa>` is already in the receiver's table, the entry's hardware address is overwritten with `ar$sha`, regardless of `ar$op` and regardless of whether the receiver owns `ar$tpa`. | A-WF |
| C2 | 214-218, 302-309 | **Add only if target.** A `<ar$pro, ar$spa>` pair not already present is inserted only when the receiver owns `ar$tpa`. Holds for `ar$op = REPLY` as well as `REQUEST`. | A-WF |
| C3 | 219-225 | **Emission gate.** A packet is emitted only when: `ar$hrd` is supported, `ar$pro` is spoken, the receiver owns `ar$tpa`, and `ar$op = REQUEST`. Corollary: receipt of a REPLY never provokes a packet. | A-WF |
| C4 | 221-223, 393-401 | **Reply field map.** The emitted reply has `ar$op := REPLY`, `ar$sha :=` receiver's hardware address, `ar$spa :=` the matched `ar$tpa`, `ar$tha :=` request's `ar$sha`, `ar$tpa :=` request's `ar$spa`; `ar$hrd`, `ar$pro`, `ar$hln`, `ar$pln` unchanged. | A-WF, MD3 |
| C5 | 224-225, 311-318, 400-401 | **Reply delivery.** The reply is unicast to its own `ar$tha`, on the link the request arrived on. | A-WF, MD2 |
| C6 | 459-464 | **No third-party relay.** Under A-CONF, the sender fields of every emitted packet name the emitter; therefore no station ever transmits a mapping for another station, and every table entry originates from the station it names. | A-CONF |
| C7 | 210, 232-233 | **Table functionality.** The table is a partial function from `<ar$pro, ar$spa>` to a hardware address (at most one per key), and every transition preserves this. | MD1 |
| C8 | 176-190, 382-391 | **Request generation.** A generated request has `ar$op := REQUEST`, `ar$hrd := ares_hrd$Ethernet`, `ar$hln := 6`, `ar$sha`/`ar$spa` the emitter's own, `ar$tpa` the address sought, and is broadcast. `ar$tha` is unconstrained. | none |
| C9 | 184-187, 311-314 | **`ar$tha` irrelevance on receipt.** Two received packets differing only in `ar$tha` produce identical table state and identical emissions. This is what makes "don't care" (line 389) safe. | A-WF |
| C10 | 200-208 | **Discard on unsupported hardware or protocol.** Unsupported `ar$hrd` or unspoken `ar$pro` yields no table change and no emission. | A-WF |
| C11 | 179, 236-238 | **Ethernet parameter agreement.** Conforming Ethernet generation satisfies `<ar$hrd, ar$hln> = <ares_hrd$Ethernet, 6>`. | none |
| C12 | 288-292 | **Optional checks are non-rejecting.** Under A-REDUNDANT, the optional `ar$hln`/`ar$pln` consistency checks (205, 208) never reject a packet produced by conforming generation. | A-REDUNDANT |

### 1.2 Carried: obligations expected to fail, where the model must exhibit the witness

These are stated as claims and expected to be refuted. A refutation with a concrete witness counts as
discharged; silence does not. Listing them here stops the ledger from booking a false claim as
merely unproved.

| ID | RFC lines | Claim under test | Expected |
|----|-----------|------------------|----------|
| R1 | 461-464 | "The only bad information that can exist is in a machine that doesn't know that some other machine has changed its 48.bit Ethernet address." | **Refuted.** Under A1 and A2, one unicast REPLY with attacker-chosen `ar$sha`/`ar$spa` installs a mapping at any station that owns the chosen `ar$tpa`. Bad information has a second source: C6 holds only under A-CONF, and A-CONF is an assumption about stations, not a property of the protocol. |
| R2 | 445-447 | "On a perfect Ethernet where a broadcast REQUEST reaches all stations on the cable, each station will get the new hardware address," read as a claim about what caches end up holding. | **Refuted as a safety claim, upheld as recovery behavior.** The same broadcast reach that gives fast recovery under A-CONF + A-PERFECT lets a single attacker packet overwrite the entry at every station on the link. Both directions are the same transition; the model must show it. |
| R3 | 302-309 | "[The target protocol address] is not necessarily needed in the reply form if one assumes a reply is only provoked by a request." | **Assumption is required.** Under A4 (unsolicited replies), `ar$tpa` in a REPLY gates the add branch of C2, so it is doing real work. The rationale's conclusion does not survive without A-CONF. |

### 1.3 Excluded

| ID | RFC lines | Excluded | Reason |
|----|-----------|----------|--------|
| X1 | 146-155, 320-323 | Byte-level parse of `ar$sha`, `ar$spa`, `ar$tha`, `ar$tpa` | Field offsets are computed from the values of `ar$hln` and `ar$pln` carried in the same packet. Variable-length, value-dependent extraction over a byte stream is sequence structure plus length arithmetic, outside the fragment. See §2. |
| X2 | 63-66, 320-323 | Byte order ("high byte first") for `ar$hrd`, `ar$pro`, `ar$op` | Bit and byte level; same side of the boundary as X1. |
| X3 | 205, 208 | Enforcement of the optional length checks against actual byte counts | Depends on X1. Survives only as the A-WF precondition and, at the value level, as C12. |
| X4 | 268-270 | "A reply has the same length as a request", buffer reuse | A claim about byte lengths; depends on X1. Included here because it looks provable and is not: it is a consequence of the wire format, which is the excluded side. |
| X5 | 415-416, 430-439, 449-457 | Table aging, timeouts, daemon probing, retransmission | RFC 826 puts these outside its own scope at line 416. Carrying them would require a time sort with an order (see §3). |
| X6 | 326-355 | The monitor role | Descriptive ("goes something like this", 335), a distinct role from the resolver, and its stated hazard (347-348, two monitors in a request loop) is a liveness property under an unbounded attacker. Not carried. |
| X7 | 135-139, 315-318 | The Ethernet frame header (destination, source, type) | The reception algorithm at 197-234 never reads it. Carrying it would let the model state and prove a check RFC 826 does not specify, such as `ar$sha` against the frame source address. That proves a property of a strengthened protocol and reports it as RFC 826. See §4.3. |
| X8 | 248-258, 260-266, 279-296 | Design rationale: periodic broadcast cost, no multiplexing, 16-bit opcode width, keeping protocol and opcode separate | Prose justification, no transition relation. |
| X9 | 419-430 | Consequences of a host moving, persistence of misrouted information | Outcome commentary contingent on X5. |
| X10 | 68-75 | Hardware name space registry | Administrative. |

Twelve carried clauses, three refutation targets, ten excluded regions.

---

## 2. The wire-format boundary

**The protocol core operates on decoded packet values. Parsing is excluded.**

RFC 826 makes this boundary sharper than most. The address fields are not merely variable-length:
their offsets are functions of the values of two other fields in the same packet. `ar$sha` is
`ar$hln` bytes, `ar$spa` is `ar$pln` bytes, `ar$tha` is `ar$hln` bytes, `ar$tpa` is `ar$pln` bytes
(146-155), and line 320 states that "there are no padding bytes between addresses" and that the data
"should be viewed as a byte stream in which only 3 byte pairs are defined to be words". Locating
`ar$tpa` requires computing `8 + 2*ar$hln + ar$pln`. That is arithmetic over lengths applied to a
sequence, which is exactly the structure the fragment excludes.

What crosses the boundary and how:

- **Into the model:** a decoded tuple `<hrd, pro, hln, pln, op, sha, spa, tha, tpa>` whose components
  inhabit uninterpreted sorts. The transition relation reads this tuple and nothing else.
- **Discharged by assumption, not by proof:** A-WF, the claim that decoding succeeded and produced
  well-sorted values. The verifier cannot prove A-WF, because proving it means reasoning about bytes.

The cost of this line is specific and needs saying now rather than at writeup time. The classic
length-confusion failure, a packet declaring `ar$hln = 6` while carrying fewer bytes, lives entirely
on the excluded side. The RFC's own hedge helps here but does not rescue it: the length checks at
lines 205 and 208 are marked "optionally", so they are not normative, and nothing in the reception
algorithm depends on them. C12 recovers the only part that is stateable at the value level, that
under A-REDUNDANT the optional checks never reject a conforming packet. No claim is made that a
conforming implementation resists malformed byte streams. Any such claim would be scoping optimism.

---

## 3. The ordering boundary

**RFC 826 defines no sequence numbers, no timestamps, no generation counters, and no version fields.
There is no order in the source to import. The core reasons by equality and disequality only.**

The numbers that do appear are `ares_op$REQUEST = 1`, `ares_op$REPLY = 2` (123-124),
`ares_hrd$Ethernet = 1` (126), and `ar$hln = 6` for Ethernet (179, 238). None of these carries a
defined order or arithmetic anywhere in the protocol's behavior. Line 281-286 explicitly declines to
combine the opcode with the protocol field, and the discussion of 32768 protocols is about
allocation, not comparison. Accordingly:

- `Op`, `HwType`, `ProtoType`, `Len` are uninterpreted sorts with distinct named constants.
- No successor, no addition, no `<`, no bitwidth.
- The only place arithmetic on `Len` would be needed is offset computation, which is X1.

**The temptation, and the ruling.** Lines 209-213 and 227-234 say the new hardware address
"supersedes" the old, and line 213 speaks of "the new information in the packet". It would be easy
to model this as recency over a time domain, giving a table that holds "the most recent" mapping.
That would import a total order the RFC does not define, and it would do so in the one area where
RFC 826 explicitly disclaims coverage: line 415-416, "It may be desirable to have table aging and/or
timeouts. The implementation of these is outside the scope of this protocol."

Ruling (MD6): supersession is modeled as function update inside the transition relation. The table
holds the hardware address written by the last accepted packet for that key, expressed as a
state-machine invariant, not as a maximum over timestamps. No time sort exists in the signature.

If a later stage finds it needs "most recent" as a first-class notion, that is a new modeling
decision. It must be recorded with the specific order introduced, its source (which will not be
RFC 826), and its cost to the fragment. It must not be added inside a proof.

---

## 4. What the modeled state deliberately carries

The test applied to each item below is whether the rule defends against something the attacker can
do, not whether it can be written down.

### 4.1 The attacker

A station on the same link. RFC 826 defines no authentication and no check tying any field to its
emitter, so:

- **A1.** Emits packets with arbitrary values in every field, including `ar$sha` and `ar$spa`.
- **A2.** Chooses delivery: broadcast to every station on the link, or unicast to a chosen hardware
  address.
- **A3.** Receives every broadcast and every unicast to a hardware address it claims.
- **A4.** Emits at any time, unsolicited, any number of times.

**Not granted: modification or deletion of other stations' packets.** This is a spoofing attacker,
not a medium attacker. The reason is that a full medium attacker refutes every cache-correctness
claim trivially, and a ledger of trivial refutations distinguishes nothing. The spoofing attacker is
the one that separates C6 from R1, which is the separation that matters for ARP.

### 4.2 Carried, with justification

| | Carried | Attacker justification |
|---|---|---|
| S1 | Delivery scope: broadcast versus unicast to a hardware address | Directly A2. It sets how many caches one attacker packet reaches. The RFC turns on this repeatedly: broadcast request (189-190), unicast reply (224-225, 400-401), broadcast recovery (445-447), unicast probe "so as not to bother every station" (454-455). Dropping it collapses R1 and R2 into the same statement. |
| S2 | Link membership, and "the same hardware on which the request was received" (224-225) | Bounds the attacker to on-link. Without it, "on-link attacker" has no content and ARP's threat model disappears. |
| S3 | Hardware-address ownership as a *relation*, not a function | An attacker claims addresses it does not uniquely own. Making ownership a function assumes the attack away. This is the switch A-UNIQ. |
| S4 | Protocol-address ownership as a relation | Same reason, and it is what "Am I the target protocol address" (214) tests. |

### 4.3 Not carried, with justification

The Ethernet frame header (135-139, and the "14.byte ethernet header" of line 315) stays out. It is
expressible, and there is a real defense that lives there: compare `ar$sha` against the frame source
address. RFC 826 does not specify that check anywhere. Carrying the header would let the model prove
a property that holds for a protocol nobody in 1982 specified, and the ledger would book it against
RFC 826. That is the failure this section exists to prevent, so the header is out and no result may
depend on it.

Also out for the same reason: frame sizes, minimum frame length, padding, collisions, CSMA, cable
topology, and table capacity or eviction. Table capacity in particular would import arithmetic and
let a proof turn on a bound the RFC never states.

---

## 5. Signature and fragment

Many-sorted first-order logic with equality. Uninterpreted sorts, relations only, no arithmetic, no
order, no sequences. Target fragment: EPR, with an acyclic quantifier-alternation graph.

**Sorts.** `Host`, `HwAddr`, `ProtoAddr`, `ProtoType`, `HwType`, `Op`, `Len`.

**Constants.** `eth : HwType`, `req, rep : Op` with `req != rep`, `six : Len`.

**Relations.**

```
owns_hw  (Host, HwAddr)
owns_pa  (Host, ProtoType, ProtoAddr)
speaks   (Host, ProtoType)
supports (Host, HwType)
tbl      (Host, ProtoType, ProtoAddr, HwAddr)
```

`tbl` carries the functionality axiom
`forall h,pt,pa,x,y. tbl(h,pt,pa,x) & tbl(h,pt,pa,y) -> x = y`, which is universal and stays in
fragment. This is C7 as a state constraint.

**No `Packet` sort** (MD8). Packets appear as tuples of field values parameterizing transitions, plus
a network relation over those field values and a delivery scope. Introducing a `Packet` sort with
field functions is harmless by itself, but any existential "there is a packet with these fields"
Skolemizes into `Packet` and creates a cycle. Avoiding the sort avoids the question.

**Stratification obligation.** The named risk is ownership totality. Asserting
`forall ha. exists h. owns_hw(h, ha)` gives an edge `HwAddr -> Host`; asserting
`forall h. exists ha. owns_hw(h, ha)` gives `Host -> HwAddr`. Together they cycle and leave EPR.
Neither is asserted. If a proof needs one, it is a new axiom for the register in §7, not a step
inside the proof. If a proof needs an ordered sort, arithmetic, or sequences, the clause classifies
out and is reported as such.

---

## 6. Recorded modeling decisions

RFC 826 leaves these open. Each is a choice, made here rather than absorbed silently into an
extraction.

| ID | RFC lines | Question | Decision |
|----|-----------|----------|----------|
| MD1 | 210, 232-233, 236-242 | Does the table key include the hardware type? | No. Key is `<ar$pro, ar$spa>`, following the text at 210 and 232-233. `ar$hrd` is a per-link constant. One hardware type per link. |
| MD2 | 210 versus 224-225 | Is the table per-link or global? | A single link is modeled, so the question does not arise. Multi-link and multi-interface are out of scope, and **no result may claim cross-link isolation.** Recorded because such a claim would otherwise look proved and be vacuous. |
| MD3 | 214, 221-223 | May a station own several protocol addresses for one protocol? | Yes; ownership is a relation. The reply's `ar$spa` is the `ar$tpa` that matched. This is the only reading of "putting the local hardware and protocol addresses in the sender fields" (221-222) consistent with the example at 393-401. |
| MD4 | 197-234 | What if `ar$spa` equals one of the receiver's own protocol addresses? | RFC 826 has no conflict detection. The algorithm applies as written, so a station will cache a mapping for its own address. Later ARP conflict handling is an anachronism and is not imported. |
| MD5 | 446 versus everywhere else | Is delivery reliable? | No. Delivery is lossy and nondeterministic by default. Perfect broadcast reach is the named axiom A-PERFECT, used only where line 446 states it. No safety result may cite it. |
| MD6 | 209-213 | How is "supersedes" modeled? | Function update in the transition relation. No time sort, no recency order. See §3. |
| MD7 | 122-126, 146-147, 179 | How are numeric field values modeled? | Uninterpreted sorts with distinct named constants. No successor, no arithmetic, no comparison. |
| MD8 | 131-155 | Is there a `Packet` sort? | No. Field-value tuples parameterize transitions. See §5. |

---

## 7. Assumption register

Every result in the ledger is labeled with the assumptions it cites. A result citing an assumption
not listed here is a Stage B failure.

| ID | RFC lines | Statement | Default | Cited by |
|----|-----------|-----------|---------|----------|
| A-WF | 146-155 | The received packet decoded to a well-sorted field tuple. | On | C1, C2, C3, C4, C5, C9, C10 |
| A-CONF | 459-460 | Every station runs the algorithm of 197-234 and emits only its own addresses in the sender fields. | **Off** where an attacker is present | C6; R1 and R3 test its removal |
| A-UNIQ | 423-424 | "48.bit Ethernet addresses are supposed to be unique and fixed for all time." | **Off** for security results, on for conformance results | labeled per result |
| A-PERFECT | 446 | A broadcast reaches every station on the link. | **Off** | R2 recovery direction only |
| A-REDUNDANT | 288-291 | `ar$hln` is determined by `ar$hrd`, and `ar$pln` by `ar$hrd` and `ar$pro`. | Off | C12 |

A-UNIQ deserves the emphasis. It is the hinge of the whole exercise. With it, cache correctness is
provable; without it, the attacker of §4.1 is definitionally present. RFC 826 states it as a property
of the world ("are supposed to be"), not as something the protocol checks or enforces, and nothing in
the reception algorithm tests it. Results that need it are conformance results about a cooperative
link, and the ledger will say so on each line rather than once in a preamble.

---

## 8. Scope failure protocol

The rules that keep this document from being rewritten around whatever succeeds:

1. **The denominator is frozen.** Fifteen obligations: C1 through C12, R1 through R3. The final
   ledger reports discharged, refuted-as-expected, and failed against exactly this list.
2. **Movement is one-way.** A clause may go from carried to excluded, with a recorded reason and a
   line in the writeup. Nothing moves from excluded to carried. Adding X1 back because a parse proof
   happened to work would be drawing the boundary around the outcome.
3. **New axioms surface, they do not hide.** A proof needing an assumption outside §7 stops. The
   assumption goes into the register with an attacker justification, or the clause classifies out.
4. **No encoding around the fragment.** A proof needing an order, arithmetic, or sequences means the
   clause classifies out. Report it. Do not substitute a total order for the missing one and continue.
5. **Refutations need witnesses.** R1, R2, R3 are discharged by an exhibited counterexample trace,
   not by failure to find a proof.
6. **The matrix is the headline.** §1 leads the writeup. Ten excluded regions, three expected
   refutations, and MD2's vacuity warning appear there, not in a closing caveat.
