# Vocabulary for RFC 826 (ARP)

Source: `rfc826.txt` only. "L" numbers are line numbers in that file.

Shape of the model: every step is a pure, total function over decoded field values and state
facts. The translation table is never passed as a value; a step receives the facts about the one
table key it concerns (`entry_present`, `entry_hw`) and returns the facts after the step (see D9).
A packet is never a record; each field of an outgoing packet has its own function (the target has
no two-field constructors).

## 1. Sorts (M-rows)

| Id | Sort | Definition | Reason | RFC |
|----|------|------------|--------|-----|
| M1 | `U8` | `int` where `0 <= v < 256` | The two length fields are 8 bits. | L146-147 |
| M2 | `U16` | `int` where `0 <= v < 65536` | `ar$hrd`, `ar$pro`, `ar$op` are 16-bit words. | L141-148, L320-323 |
| M3 | `HwAddr` | `int` where `0 <= v < 281474976710656` (2^48) | A hardware address as one number; the bound is the 10Mbit Ethernet instance (`hln = 6`). Only equality is used. | L137-138, L149-150, L179-180, L238 |
| M4 | `ProtoAddr` | `int` where `v >= 0` | A protocol address as one number. No upper bound in the generic sort, because the bound is `256^pln` (D8). Only equality is used. | L151-152, L94-95 |
| M5 | `OpClass` | enum `OpRequest`, `OpReply`, `OpOther` | What a received opcode means to the receiver. `OpOther` covers every value the RFC does not define. | L123-124, L148, L219, L294-296 |
| M6 | `OutKind` | enum `OutRequest`, `OutReply` | The two kinds of packet a host can emit. Separate from `OpClass` so that no step can emit "other". | L148, L181, L223 |
| M7 | `Gate` | enum `GateOpen`, `DropHrd`, `DropHln`, `DropPro`, `DropPln` | Result of the checks that precede any table change. One tag per negative conditional and per optional check. | L200-208 |
| M8 | `TableAction` | enum `TableKeep`, `TableUpdate`, `TableInsert` | What reception does to the entry for `<ar$pro, ar$spa>`. | L209-218 |
| M9 | `Disposition` | enum `Discard`, `SendReply` | What reception does with the packet after the table step. | L200-201, L219-225 |
| M10 | `ResolveResult` | sum `Found HwAddr`, `NotFound` | Result of the outbound table lookup. | L169-176 |
| M11 | `LinkDst` | sum `Broadcast`, `Unicast HwAddr` | Link-layer destination of an emitted packet. `Broadcast` is a tag, not the all-ones number, so the sort survives other hardware. | L186-190, L224-225, L400-401 |
| M12 | `AddrField` | enum `FSha`, `FSpa`, `FTha`, `FTpa` | Names the four variable-length fields for the layout function. | L149-155 |

Named constants (values the RFC fixes): `ares_op$REQUEST = 1`, `ares_op$REPLY = 2`,
`ares_hrd$Ethernet = 1` (L123-126), Ethernet `hln = 6` (L179-180, L238). The RFC gives no number for
`ether_type$ADDRESS_RESOLUTION` or for any protocol's ether type (D29).

## 2. Steps

### How the algorithm is divided

The RFC has two procedures: Packet Generation (L158-190) and Packet Reception (L194-225). I split
them into four groups.

1. **Wire layout and codes** (P): the facts about the format that are linear arithmetic or a code
   table. Kept apart so the behavioural steps never mention bytes.
2. **Reception decision** (R1-R7): the reception algorithm cut at each point where the RFC names
   an intermediate result: the gate (L203-208), `Merge_flag` (L209-213), the target test (L214),
   the table change (L210-218), the reply decision (L219-220). Each cut is one function, so each
   RFC sentence maps to one clause about one function.
3. **Reply construction** (R8-R15): one function per field of the reply (L221-225).
4. **Request generation** (G): the lookup and one function per field of the request (L169-190).

Steps after the gate take the `Gate` tag as a parameter rather than repeating its inputs. Steps
after the table decision take the `TableAction` tag. This follows the tool's advice to discriminate
on enum tags.

### P. Wire layout and codes

| Id | Signature | Purpose | RFC |
|----|-----------|---------|-----|
| P1 | `u16_of_bytes [hi: U8, lo: U8] -> U16` | Value of a 16-bit word from its two bytes, first byte most significant (`256*hi + lo`). | L63-66, L123, L320-323 |
| P2 | `body_len [hln: U8, pln: U8] -> int` | Length in bytes of the ARP packet data: `8 + 2*hln + 2*pln`. | L141-155, L268-270, L320 |
| P3 | `field_offset [f: AddrField, hln: U8, pln: U8] -> int` | Byte offset of an address field in the packet data: 8, `8+hln`, `8+hln+pln`, `8+2*hln+pln`. | L149-155, L320-321 |
| P4 | `classify_op [op: U16] -> OpClass` | Meaning of a received opcode: 1 is request, 2 is reply, all else other. | L123-124, L148, L219 |
| P5 | `encode_op [k: OutKind] -> U16` | Opcode value of an emitted packet. | L123-124, L181, L223 |
| P6 | `out_dst [k: OutKind, peer_ha: HwAddr] -> LinkDst` | Link-layer destination: a request is broadcast, a reply goes to `peer_ha` only. | L188-190, L224-225, L400-401 |

### R. Reception

Inputs named below: `hrd pro hln pln op sha spa tha tpa` are the decoded fields of the received
packet. `have_hrd` and `speak_pro` are the receiver's answers to the two questions at L203 and
L206. `entry_present` and `entry_hw` are the table facts for the key `<pro, spa>` before the step.
`local_ha` and `local_pa` are the receiver's own addresses for that hardware and protocol.

| Id | Signature | Purpose | RFC |
|----|-----------|---------|-----|
| R1 | `recv_gate [have_hrd: bool, check_hln: bool, hln: U8, want_hln: U8, speak_pro: bool, check_pln: bool, pln: U8, want_pln: U8] -> Gate` | The checks before any table change, in RFC order; the first failure gives the tag. | L203-208, L288-292 |
| R2 | `merge_flag [g: Gate, entry_present: bool] -> bool` | The RFC's `Merge_flag`: true exactly when the gate is open and the entry already exists. | L209-213 |
| R3 | `is_target [tpa: ProtoAddr, local_pa: ProtoAddr] -> bool` | "Am I the target protocol address?" | L214, L395-396 |
| R4 | `table_action [g: Gate, entry_present: bool, target: bool] -> TableAction` | Update if the entry exists; insert if it does not and the receiver is the target; otherwise keep. Keep whenever the gate is not open. | L210-218, L227-234 |
| R5 | `entry_present_after [a: TableAction, entry_present: bool] -> bool` | Whether `<pro, spa>` is in the table after reception. | L210-218 |
| R6 | `entry_hw_after [a: TableAction, entry_hw: HwAddr, sha: HwAddr] -> HwAddr` | Hardware address stored for `<pro, spa>` after reception: `sha` on update or insert, `entry_hw` on keep. | L211-213, L216-218, L231-234 |
| R7 | `recv_disposition [g: Gate, target: bool, c: OpClass] -> Disposition` | `SendReply` exactly when the gate is open, the receiver is the target and the opcode is a request. | L200-201, L214, L219-225 |
| R8 | `reply_hrd [hrd: U16] -> U16` | Reply keeps the request's hardware space. | L221-223, L268-270 |
| R9 | `reply_pro [pro: U16] -> U16` | Reply keeps the request's protocol space. | L221-223, L268-270 |
| R10 | `reply_hln [hln: U8] -> U8` | Reply keeps the hardware length. | L268-270 |
| R11 | `reply_pln [pln: U8] -> U8` | Reply keeps the protocol length. | L268-270 |
| R12 | `reply_sha [local_ha: HwAddr] -> HwAddr` | Reply's sender hardware address is the replier's own. | L221-222, L398-399 |
| R13 | `reply_spa [tpa: ProtoAddr] -> ProtoAddr` | Reply's sender protocol address is the request's target protocol address (D16). | L221-222 |
| R14 | `reply_tha [sha: HwAddr] -> HwAddr` | Reply's target hardware address is the request's sender hardware address. | L221, L313-314 |
| R15 | `reply_tpa [spa: ProtoAddr] -> ProtoAddr` | Reply's target protocol address is the request's sender protocol address. | L221 |

The reply's opcode is `encode_op OutReply` (P5) and its destination is `out_dst OutReply sha` (P6).
R8-R15 describe the reply; they bind only when R7 gives `SendReply`.

### G. Request generation

Inputs: `pro` and `target_pa` are the pair being resolved; `entry_present` and `entry_hw` are the
table facts for `<pro, target_pa>`; `local_hrd`, `local_hln`, `local_ha` describe the sender's
hardware; `proto_pln` and `local_pa` describe the sender in protocol `pro`.

| Id | Signature | Purpose | RFC |
|----|-----------|---------|-----|
| G1 | `resolve [entry_present: bool, entry_hw: HwAddr] -> ResolveResult` | Table lookup for an outgoing packet: `Found entry_hw` or `NotFound`. `NotFound` is the trigger for a request. | L169-176 |
| G2 | `req_hrd [local_hrd: U16] -> U16` | Request's hardware space (1 on Ethernet). | L176-178, L382 |
| G3 | `req_pro [pro: U16] -> U16` | Request's protocol space is the protocol being resolved. | L178-179, L383 |
| G4 | `req_hln [local_hln: U8] -> U8` | Request's hardware length (6 on Ethernet). | L179-180, L384 |
| G5 | `req_pln [proto_pln: U8] -> U8` | Request's protocol length is the address length of that protocol. | L180, L385 |
| G6 | `req_sha [local_ha: HwAddr] -> HwAddr` | Request's sender hardware address is the sender's own. | L181-182, L387 |
| G7 | `req_spa [local_pa: ProtoAddr] -> ProtoAddr` | Request's sender protocol address is the sender's own. | L182, L388 |
| G8 | `req_tpa [target_pa: ProtoAddr] -> ProtoAddr` | Request's target protocol address is the address being resolved. | L182-184, L390 |

The request's opcode is `encode_op OutRequest` and its destination is `out_dst OutRequest _`
(`Broadcast`, whatever the second argument). There is no `req_tha` (D23).

## 3. Modeling decisions (D-rows)

| Id | Question | Alternatives | Choice | RFC |
|----|----------|--------------|--------|-----|
| D1 | Is the reception algorithm binding? The text says "an algorithm similar to the following" and the document says it is not a standard. | (a) Treat it as illustration only. (b) Treat its results as binding and its internal order as free. | (b). Clauses constrain the gate result, table facts after, disposition and reply fields; they do not constrain how an implementation gets there. | L45-50, L197-201 |
| D2 | Are `ar$hrd` and `ar$pro` enums or numbers? | (a) Enums of known spaces. (b) `U16`. | (b). Both sets are open (new hardware values expected; protocol set is the ether type set), and the RFC names only one number. | L141-145, L272-280 |
| D3 | How is "Do I have the hardware type in ar$hrd?" expressed? | (a) `hrd == local_hrd` for one local value. (b) Lookup in a `map[int,bool]`. (c) A bool fact `have_hrd` supplied by the caller. | (c). The RFC does not say how many hardware types a host has or how arrival interface relates to `ar$hrd`. (a) is the special case `have_hrd = (hrd == local_hrd)`. | L203-204 |
| D4 | How is "Do I speak the protocol in ar$pro?" expressed? | Same three as D3. | (c), bool fact `speak_pro`. A host can speak several protocols (the bridge at L264 speaks four). | L206-207, L264-266 |
| D5 | The length checks are "optional". Who decides, and what is compared? | (a) Never check. (b) Always check. (c) Flags `check_hln`, `check_pln` plus expected values `want_hln`, `want_pln` as inputs. | (c). The expected length is "determined by the hardware type and the protocol type", so it is a fact about the receiver's knowledge, passed in. | L205, L208, L288-292 |
| D6 | What happens when an optional length check fails? The RFC says only "check"; the discard rule is stated for "negative conditionals", which are the `?` questions. | (a) Discard without touching the table. (b) Report and continue. | (a), with tags `DropHln` and `DropPln`. A check with no consequence is not a check. Flagged as open question Q2. | L200-201, L205, L208 |
| D7 | Is the order of the gate checks fixed? | (a) RFC order: hrd, hln, pro, pln. (b) Any order; one `Drop` tag. | (a), distinct tags. The order changes only which tag is returned, never whether the gate is open. Contract authors who think the tag is not an obligation can state clauses over `g == GateOpen` only. | L203-208 |
| D8 | How are addresses represented? | (a) Fixed-length byte arrays. (b) One `int` per address. | (b). Only equality between addresses is ever needed. The number is the bytes read first-byte-most-significant; that convention is mine, the RFC defines byte order only for the three words (D28). No ordering on addresses is used. `HwAddr` is bounded for Ethernet. `ProtoAddr` has no generic bound because `256^pln` is nonlinear; an instance adds its own alias (32 bits Internet, 16 CHAOS, 8 PUP). | L94-95, L146-155, L320-323 |
| D9 | How is the translation table represented? Its key is a pair `<protocol type, protocol address>`; the target's maps take one key. | (a) One `map[int,int]` per protocol type. (b) Encode the pair as one integer. (c) No table value: steps take and return the facts for the one key concerned. | (c). (b) needs a bound on `ProtoAddr` that does not exist generically. (a) is compatible with (c): `entry_present` is `has`, `entry_hw` is `get`, and R5/R6 describe one `set`. | L168-171, L210-218 |
| D10 | Does reception change any other table entry? | (a) State a frame condition. (b) Leave it implicit. | (b) at this level: a frame condition over all keys needs a quantifier. With one map per protocol (D9a) it follows from the map's single `set`. | L210-218 |
| D11 | What does an entry hold besides the hardware address? Hardware type, interface, age? | (a) Hardware address only. (b) Also `hrd` or interface. | (a). The RFC's triplet is `<protocol type, sender protocol address, sender hardware address>`. A host with several hardware types needs one table per hardware; that is outside the vocabulary (X8). | L216-218, L227-228, L298-300 |
| D12 | Is an existing entry updated when the receiver is not the target? | (a) Yes. (b) Only when target. | (a). The update comes before the target question, and the RFC relies on it so every station learns a moved host's new address from one broadcast. | L210-214, L441-447 |
| D13 | Is an unknown sender entered when the receiver is not the target? | (a) No. (b) Yes (the monitor's behaviour). | (a), `TableKeep`. Insert happens only under "Yes" to the target question. | L214-218, L302-304, L337-339 |
| D14 | When the entry exists and `sha` equals the stored address, is that `TableUpdate` or `TableKeep`? | Either; the table facts after are the same. | `TableUpdate` whenever the entry exists, because `Merge_flag` becomes true regardless of whether the value changed. | L210-213 |
| D15 | Is `Merge_flag` part of the vocabulary or an implementation variable? | (a) Hidden; only `table_action`. (b) Exposed as a step. | (b). The RFC names it and states its value; a clause can cite it. `table_action` is consistent with it by definition. | L209-217 |
| D16 | "Swap hardware and protocol fields, putting the local hardware and protocol addresses in the sender fields": is the reply's `spa` the request's `tpa` or the replier's `local_pa`? | (a) `tpa` (the swap). (b) `local_pa` (the "putting"). | (a). They are equal whenever a reply is sent, because the receiver is the target. (a) stays right if a host has several addresses in one protocol. | L221-222, L398-399 |
| D17 | "Am I the target protocol address?": one local address or several? | (a) One `local_pa` per protocol; `is_target` is equality. (b) A set; target is membership, passed as a bool fact. | (a), with `target: bool` as the parameter of the later steps so that (b) can replace R3 without touching R4 and R7. Answering for another host's address is not in the RFC and is not modeled. | L214, L343, L395-396 |
| D18 | What becomes of the received `ar$tha`? | (a) Ignored on reception for both opcodes. (b) Checked against `local_ha` on a reply. | (a). The algorithm never reads it. It "has no meaning in the request form"; in a reply it is the requester's address but no check is prescribed. It does not appear in any reception step. | L153-154, L184-185, L311-314 |
| D19 | Where is the reply sent: to the new `ar$tha` or to the link-layer source of the request? | (a) New `tha`, which is the request's `ar$sha`. (b) Ethernet header source. | (a). "Send the packet to the (new) target hardware address"; the header may not be visible to the module. The two can differ and the RFC does not say what then (Q5). | L135-136, L224-225, L315-318, L400-401 |
| D20 | Which reply fields are unchanged from the request? | (a) `hrd`, `pro`, `hln`, `pln` copied. (b) Rebuilt from local knowledge. | (a). The algorithm changes only the address fields and the opcode, and "several of the fields are the same". | L221-223, L268-270 |
| D21 | Opcode is neither 1 nor 2. | (a) Discard before the table step. (b) Run the table step, send no reply. | (b). The opcode is looked at only after the merge, and the only question is "is it REQUEST". `OpOther` and `OpReply` behave the same in every step. | L219, L227-229, L308-309 |
| D22 | Is a reply accepted only if a request is outstanding? | (a) Track pending requests. (b) No such state. | (b). The algorithm merges without looking at the opcode. The RFC notes the "only provoked by a request" assumption but does not enforce it. | L210-218, L305-309 |
| D23 | What goes in `ar$tha` of a request? | (a) Zero. (b) Broadcast address. (c) Unconstrained. | (c). "It does not set ar$tha to anything in particular." There is no `req_tha` function, so no clause can constrain it. | L184-188, L389 |
| D24 | Link destination of a request. | (a) Always broadcast. (b) Also unicast (the aging daemon's probe). | (a). The unicast probe belongs to the timeout discussion, which the RFC puts out of scope (X1). | L188-190, L449-455 |
| D25 | On a lookup miss, what happens to the packet that needed the address? | (a) Dropped. (b) Queued. (c) Not specified. | (c). The RFC says "probably" throws it away. `resolve` returns `NotFound`; nothing is said about the original packet. | L172-175, L379-380 |
| D26 | Does every miss generate a request? | (a) Yes. (b) Suppressed while one is pending or rate limited. | (a) as far as the vocabulary goes: `NotFound` is the only precondition for the request field functions. Suppression needs time or pending state, which the RFC does not describe. | L172-176 |
| D27 | Are `req_hrd` and `req_hln` the Ethernet constants or parameters? | (a) Constants 1 and 6. (b) Parameters `local_hrd`, `local_hln`. | (b), with the Ethernet values as named constants. The RFC says the fields exist so other hardware can use the protocol; the example writes `length(EA(X))`. | L176-180, L236-238, L384 |
| D28 | Byte order. | (a) Model bytes for all fields. (b) Model only the three words' order. | (b), via P1. Addresses are byte streams with no numeric meaning in the RFC. | L63-66, L320-323 |
| D29 | Value of `ether_type$ADDRESS_RESOLUTION` and of protocol ether types. | (a) Supply the known numbers. (b) Leave them out. | (b). The RFC gives none, and the brief makes the RFC the only source. Dispatch on the link-layer type happens before the module is called. | L115-121, L139, L197-198 |
| D30 | Packet shorter or longer than `body_len`. | (a) Add a gate tag for bad length. (b) Give the layout only. | (b). The RFC has no rule about total length, truncation or trailing bytes. P2 and P3 let a caller state its own precondition. | L141-155, L320-323 |
| D31 | `hln = 0` or `pln = 0`, or lengths that disagree with the sorts' bounds. | (a) Forbid. (b) Allow. | (b) in `U8`. The RFC sets no minimum. `HwAddr`'s bound assumes `hln = 6`; a non-Ethernet instance replaces the alias. | L146-147, L236-238 |
| D32 | Sender validity: `spa` equal to the receiver's own address, `sha` equal to the broadcast address or to `local_ha`. | (a) Drop or flag. (b) No special case. | (b). The RFC is silent; the algorithm merges whatever the sender fields say. | L210-218 |
| D33 | Table full. | (a) Insert can fail. (b) Insert always succeeds. | (b). No capacity or eviction rule in the RFC. | L216-218 |
| D34 | Value of `entry_hw_after` when the entry is absent after the step. | Any; the function is total. | Returns `entry_hw` unchanged on `TableKeep`. It carries meaning only when `entry_present_after` is true. | L210-218 |
| D35 | The monitor section describes a station that always enters the sender triplet. Is that a mode of the same steps? | (a) A `monitor: bool` input to `table_action`. (b) Excluded. | (b), X3. It contradicts D13 and is described as a separate use of the protocol. | L337-348 |
| D36 | One gate function or one predicate per question? | (a) Four predicates. (b) One `Gate` enum. | (b). The later steps then take one tag instead of four bools. | L203-208 |
| D37 | Is `reply_sha` the receiver's address on the arrival hardware? | (a) Yes, one `local_ha`. (b) Chosen per interface. | (a). "On the same hardware on which the request was received"; interface selection is not modeled (X8). | L221-225 |

## 4. Exclusions (X-rows)

| Id | Not modeled | Why | RFC |
|----|-------------|-----|-----|
| X1 | Table aging, timeouts, deletion on connection failure, the probing daemon and its retransmissions, manual clearing. | The RFC puts them outside the protocol; they need time, which the target cannot express. | L415-469 |
| X2 | Byte-level parsing and serialization of the packet. | Field offsets depend on `hln` and `pln` read from the same packet. P2 and P3 give the layout as arithmetic only. | L141-155 |
| X3 | Monitor behaviour: unconditional learning, display for debugging, a monitor's own requests and the loop warning. | A different station role (D35). | L326-364 |
| X4 | The Ethernet header: its destination, source and type fields, and the handoff from the Ethernet module. | "Not necessarily accessible to the user"; no type value is given (D29). Only the destination of emitted packets is kept, as `LinkDst`. | L135-139, L197-198 |
| X5 | Fate of the original outgoing packet on a miss, and retransmission by higher layers. | Stated as "probably"; no obligation (D25). | L172-175, L406-408 |
| X6 | Routing: choice of next hop and of the cable to broadcast on. | Input to ARP, decided before it. | L161-164, L189-190 |
| X7 | Pending-request state, request suppression and rate limiting. | Absent from the RFC (D22, D26). | L172-176 |
| X8 | Several interfaces or hardware types on one host; a table per interface. | The RFC mentions "the same hardware" once and nothing else (D11, D37). | L224-225 |
| X9 | Table capacity, eviction, hashing or indexing. | Implementation matters with no rule (D33). | L438-439 |
| X10 | Concurrent reception and generation against one table. | Outside the target; each step is described in isolation. | L194-225 |
| X11 | The actual transmission and the reuse of the packet buffer for the reply. | I/O and an implementation convenience. | L188-190, L268-270 |
| X12 | Assignment of hardware space values and the naming authority. | Administrative. | L68-75, L272-277 |
| X13 | Semantics of protocol addresses, and any ordering on addresses. | The RFC uses addresses only for equality. | L353-355 |
| X14 | The reasoning sections (why no periodic broadcast, why one resolution per packet, why separate fields). | Rationale, no obligation. | L245-296 |

## 5. Open questions for the RFC author

- Q1. Is the reception algorithm normative, or may an implementation differ as long as requests
  for its address are answered? (L199)
- Q2. When an optional length check fails, is the packet discarded before the table step? (L205,
  L208)
- Q3. Should an opcode other than 1 or 2 still cause the sender to be merged? (L219, L227-229)
- Q4. Should a host that is not the target and has no entry for the sender really learn nothing,
  given that communication is assumed bidirectional? (L214-218, L229-231)
- Q5. If `ar$sha` differs from the link-layer source address, which one receives the reply, and is
  the packet acceptable at all? (L224-225, L315-318)
- Q6. In the reply, is `ar$spa` the request's `ar$tpa` or the replier's configured address, for a
  host with more than one address in a protocol? (L221-222)
- Q7. May a host answer for a protocol address that is not its own? (L214)
- Q8. What should a receiver do when `ar$spa` is its own protocol address with a different
  `ar$sha`? (L210-213)
- Q9. Should a received reply be merged if no request was sent, and should its `ar$tha` be checked
  against the receiver's hardware address? (L305-306, L313-314)
- Q10. Is there a required value for `ar$tha` in a request, and must a receiver ignore it? (L184-188)
- Q11. What is the numeric value of `ether_type$ADDRESS_RESOLUTION`? (L121)
- Q12. What should a receiver do with a packet whose data is shorter than `8 + 2*hln + 2*pln`, or
  longer? (L141-155)
- Q13. Is the table keyed per hardware interface, and does an entry record `ar$hrd`? (L216-218,
  L224-225)
- Q14. On a miss, must the original packet be dropped, and must a request be sent on every miss?
  (L172-176)
- Q15. Are `ar$hln = 0` or `ar$pln = 0` legal? (L146-147)
- Q16. Are the bytes of an address ever to be read as a number, and if so in what order? (L320-323)
