# Vocabulary for RFC 826 (ARP), receiver/sender node

Source: rfc826.txt, cited as "l.N". The modelled subject is ONE node (a host's Address Resolution module), Ethernet hardware, one local protocol address per protocol type. State = one translation table. Inputs = decoded field values plus local-configuration facts. No wire bytes.

## 1. Sorts (M-rows)

| Id | Sort | Definition | Reason | RFC |
|---|---|---|---|---|
| M1 | `U8` | `(where [v: int] (and (>= v 0) (< v 256)))` | ar$hln, ar$pln are 8-bit | l.146-147 |
| M2 | `U16` | `(where [v: int] (and (>= v 0) (< v 65536)))` | ar$hrd, ar$pro, ar$op are 16-bit; protocol type is an ether_type value | l.141-148 |
| M3 | `Hw48` | `(where [v: int] (and (>= v 0) (< v 281474976710656)))` | 48-bit Ethernet address as a number (ar$sha, ar$tha, table value) | l.9, 137-138, 149-154 |
| M4 | `PAddr` | `(where [v: int] (and (>= v 0) (< v 4294967296)))` | protocol address (ar$spa, ar$tpa, local address) as a number; 32 bits covers the 8/16/32-bit examples (D2) | l.94-95, 151-155 |
| M5 | `Opcode` | enum `OpRequest`, `OpReply`, `OpOther` | ares_op$REQUEST=1, REPLY=2; other 16-bit values are possible and must be handled (D9) | l.123-124, 148, 294-296 |
| M6 | `Gate` | enum `Proceed`, `Discard` | outcome of the "do I have hrd / speak pro / lengths" filters; "negative conditionals end processing" | l.200-208 |
| M7 | `Action` | enum `NoAction`, `SendReply` | what reception does on the wire after table handling | l.219-225 |
| M8 | `Lookup` | sum `Miss` (nullary) / `Hit(Hw48)` | table query result; one payload | l.169-172 |
| M9 | `Resolve` | enum `SendFrame`, `DropAndRequest` | outcome of the transmit-side consultation: hardware address known, or packet dropped and a broadcast REQUEST emitted | l.169-190 |
| M10 | `Table` | `map[int, int]`: key = `table_key(pro, pa)`, value = a `Hw48` | the translation table of triplets `<protocol type, sender protocol address, sender hardware address>`; one hw value per `<pro, pa>` key | l.210-218, 232-234 |

## 2. Steps

Division. The RFC's reception algorithm (l.203-225) interleaves four concerns: the filters (hrd, pro, optional lengths), the merge-update, the target-conditional insert, and the opcode-conditional reply. A solver-friendly split gives one function per concern. Because a step cannot return two things (sums carry one payload; no records), the reception outcome is split into two pure functions of the same inputs: `rx_table` (new table) and `rx_action` (wire action). Reply-packet content and request-packet content are one function per field, because a result cannot hold several fields, and each RFC field-setting sentence becomes one checkable function. Transmit side (l.161-190) is `tx_resolve` plus the request field builders. All local facts (what hardware/protocol I speak, my addresses) are parameters; none is stored.

Names: `pro` = ar$pro, `spa`/`tpa`/`sha` = ar$spa/ar$tpa/ar$sha.

### Decoding and table primitives
- S1 `classify_opcode [op: U16] -> Opcode` — 1 to OpRequest, 2 to OpReply, else OpOther. l.123-124, 219.
- S2 `rx_gate [hrd_mine: bool, pro_mine: bool, hln_check_on: bool, hln_ok: bool, pln_check_on: bool, pln_ok: bool] -> Gate` — Proceed iff hrd_mine and pro_mine and (hln check off or hln_ok) and (pln check off or pln_ok). l.203-208.
- S3 `table_key [pro: U16, pa: PAddr] -> int` — `pro * 4294967296 + pa`; injective on the domain (D1). l.210, 216.
- S4 `tbl_has [t: Table, pro: U16, pa: PAddr] -> bool` — whether the pair is in the table. l.210-211; this is Merge_flag.
- S5 `tbl_get [t: Table, pro: U16, pa: PAddr] -> Lookup` — Hit(hw) if present else Miss. l.169-172.

### Reception (l.197-225)
- S6 `tbl_merge [t: Table, pro: U16, spa: PAddr, sha: Hw48] -> Table` — if pair present, replace its hardware address by sha; otherwise unchanged. l.210-213, 232-234.
- S7 `rx_learn [t: Table, pro: U16, spa: PAddr, sha: Hw48, merged: bool, am_target: bool] -> Table` — if am_target and not merged, add the triplet; else unchanged. l.214-218.
- S8 `rx_table [t: Table, gate: Gate, pro: U16, spa: PAddr, sha: Hw48, tpa: PAddr, my_pa: PAddr] -> Table` — new table after reception: Discard gives t; Proceed gives `rx_learn(tbl_merge(t..), tbl_has(t..), tpa == my_pa)`. l.203-218.
- S9 `rx_action [gate: Gate, opc: Opcode, tpa: PAddr, my_pa: PAddr] -> Action` — SendReply iff Proceed and tpa == my_pa and opc == OpRequest; else NoAction. l.214, 219-225, 404-406.

### Reply packet content (l.221-225), defined only when rx_action = SendReply
- S10 `reply_op [] -> Opcode` — OpReply. l.223.
- S11 `reply_sha [my_hw: Hw48] -> Hw48` — local hardware address. l.221-222, 399-400.
- S12 `reply_spa [my_pa: PAddr] -> PAddr` — local protocol address. l.221-222.
- S13 `reply_tha [req_sha: Hw48] -> Hw48` — request's sender hardware address. l.221, 313-314.
- S14 `reply_tpa [req_spa: PAddr] -> PAddr` — request's sender protocol address. l.221.
- S15 `reply_dest [req_sha: Hw48] -> Hw48` — hardware destination of the reply frame (unicast to the new target hardware address). l.224-225, 401.
- S16 `reply_hrd [req_hrd: U16] -> U16` — unchanged (D13). l.221, 268-270.
- S17 `reply_pro [req_pro: U16] -> U16` — unchanged. l.268-270.
- S18 `reply_hln [req_hln: U8] -> U8` — unchanged. l.268-270.
- S19 `reply_pln [req_pln: U8] -> U8` — unchanged. l.268-270.

### Transmit side (l.161-190)
- S20 `tx_resolve [t: Table, pro: U16, tpa: PAddr] -> Resolve` — SendFrame iff the pair is in the table, else DropAndRequest. l.169-176.
- S21 `req_hrd [] -> U16` — 1 (ares_hrd$Ethernet). l.126, 177-178.
- S22 `req_pro [pro: U16] -> U16` — the protocol type being resolved. l.178-179.
- S23 `req_hln [] -> U8` — 6. l.179-180.
- S24 `req_pln [pro_len: U8] -> U8` — length of an address in that protocol, supplied by local configuration (D8). l.180.
- S25 `req_op [] -> Opcode` — OpRequest. l.181.
- S26 `req_sha [my_hw: Hw48] -> Hw48` — own hardware address. l.181-182.
- S27 `req_spa [my_pa: PAddr] -> PAddr` — own protocol address. l.182.
- S28 `req_tpa [target_pa: PAddr] -> PAddr` — address being resolved. l.182-184.

(There is deliberately no `req_tha`: D14.)

## 3. Modeling decisions (D-rows)

- D1 Table key for `<protocol type, address>`. Q: how to key a pair in a map of int keys with only linear arithmetic? Alts: (a) `pro * 2^32 + pa` (constant multiple, linear); (b) string concatenation; (c) a map per protocol (maps of maps unavailable); (d) a list of triplets. Chose (a), made safe by M4's 32-bit bound so the encoding is injective. l.210, 216-217, 227-228.
- D2 Protocol address width and identity. Q: RFC addresses are byte strings whose length is given by ar$pln; numbers lose length (the 4-byte 0.0.0.1 and 1-byte 1 coincide). Alts: bytes of variable length; number plus separate length in the key; number only. Chose number only, bounded to 32 bits, and no length in the key, because the RFC calls the lengths redundant given hrd and pro. l.94-95, 288-292.
- D3 Hardware address width. Q: Ethernet 48 bits only, or hln-general? Alts: unbounded int; Hw48. Chose Hw48; the generalization is excluded (X1). l.9, 236-242.
- D4 Does the table also key on the hardware interface? Reception says reply "on the same hardware on which the request was received" and routing picks a piece of hardware. Alts: table per interface; single table. Chose a single table, one interface. l.163-165, 225.
- D5 Does a reception update the table when the packet is not for me? Alts: update only when target (as with the insert); merge-update regardless. The text puts the "already in table, update" step BEFORE the "am I target" test, so a known entry is refreshed even for third-party packets, while a new entry is only added when target. Chose literal order: tbl_merge always (after gate), insert only if target. l.210-218.
- D6 The "discarded" contradiction. Q: "negative conditionals ... discarding of the packet" yet the merge happened before the target test. Alts: discard rolls back the merge; discard only means no further processing. Chose: a Gate failure leaves the table untouched; a non-target packet has already had its merge applied and stays applied. l.200-201, 210-218.
- D7 Optional length checks. Q: lengths "optionally" checked. Alts: never; always; per-node switch. Chose a per-node switch (`*_check_on`) plus a match boolean supplied by the decoder, so contracts hold for both settings. A failed enabled check yields Discard. l.205, 208, 288-292.
- D8 Where does ar$pln come from on transmit? RFC: "the length of an address in that protocol". Chose a parameter from local protocol configuration (`pro_len`), not derived from the table or a function of pro. l.180.
- D9 Unknown opcodes. Q: an opcode that is neither 1 nor 2. The RFC says "NOW look at the opcode" only after merging, and only tests REQUEST. Alts: discard in the gate; learn then do nothing. Chose learn (table effect as for a reply), NoAction, via OpOther. l.219, 227-229.
- D10 Replies. A REPLY that reaches me as target gets learned and produces no reply; a REPLY not for me is only merged if present. Chose to state this through `rx_table` independent of opcode (the table step takes no opcode on purpose). l.219-229, 404-406.
- D11 "Am I the target protocol address?" Q: compared how, and for which protocol? Alts: a boolean `am_target` supplied by caller; compare `tpa` with a single local address. Chose comparison inside the step with `my_pa`, the node's address for `pro`; the node has one address per protocol type. This allows contract clauses about the equality. Multi-address and multi-homed hosts excluded (D4). l.214, 395.
- D12 Spurious senders. Silent on: sha = broadcast or multicast; sha or spa equal to my own; spa = 0; spa = tpa (gratuitous). Alts: validate and discard; accept as given. Chose accept without special cases, because the RFC lists no such check; recorded as an open question (Q1, Q2). l.210-218.
- D13 Which reply fields are "swapped". "Swap hardware and protocol fields" can read as swapping only sha/spa with tha/tpa, or all. Alts: reply may change hrd/pro/hln/pln; they stay. Chose they stay the same as the request (S16-S19), because the reply has the same length and shares fields. l.221, 268-270.
- D14 Request ar$tha. RFC allows anything ("does not set ... in particular", may be broadcast, "don't care"). Alts: fix to zero; fix to broadcast; unconstrained. Chose unconstrained: no step, and consumers must not assume a value. l.184-188, 389.
- D15 Reply's hardware destination. The frame source is not exposed (l.135-137 "not necessarily accessible"), and the RFC says to send "to the new target hardware address", so the destination is the request's ar$sha, not the frame's source address. Alt: frame source. Chose ar$sha. l.224-225, 315-318, 401.
- D16 Table value reuse in the reply. Q: does the reply take the requester's address from the packet or the just-merged table? Same value by construction when learned. Chose the packet field (S13, S15). l.221-225.
- D17 What does a failed lookup do besides drop? Text: "probably informs the caller that it is throwing the packet away". Alts: queue the packet; drop silently; drop and inform. Chose a two-valued outcome: Resolve = DropAndRequest means the original packet is dropped and one REQUEST is emitted; queueing is not modeled. The word "probably" is treated as not binding on the REQUEST, which is stated without hedging. l.172-176.
- D18 Is the request broadcast to the cable? "causes this packet to be broadcast". The destination address is not a packet field, so broadcast-ness is the meaning of DropAndRequest (and is stated in the comment, not a field). Alt: a request-destination step. Chose no step; recorded in Q5. l.186-190.
- D19 Table lookup on transmit uses `<protocol type, target protocol address>`, and a hit returns the most recent hardware address. Alts: could return a list. Chose Lookup with one payload (map). l.168-172, 232-234.
- D20 Table has one hw address per key. Two hosts claiming one protocol address cannot coexist; the newest wins. Alt: keep a set. Chose map semantics, from "supersedes the old one". l.232-234, 396-397.
- D21 Order of state and output. Q: do the table update and reply happen atomically? Chose two pure functions of the same inputs and the same pre-state; the reply does not depend on the post-state. Alt: one step returning a pair (impossible here). l.219-225.
- D22 Opcode representation. Q: carry the 16-bit number or an enum? Alts: int with equality to 1/2; enum. Chose the enum with `OpOther`, produced by `classify_opcode`, as the target prefers enum comparison. The 1 and 2 values live only in S1. l.123-124.
- D23 hrd/pro locality. "Do I have the hardware type" / "Do I speak the protocol" are node configuration. Alts: model a set of supported values; booleans. Chose booleans computed by the caller (`hrd_mine`, `pro_mine`), since sets cannot be quantified over. The parenthetical "(almost definitely)" is not normative. l.203-207.
- D24 Is hrd=1 forced on transmit? Yes, the request sets ares_hrd$Ethernet, so `req_hrd` is constant 1; reply echoes. The node never emits other hrd values. l.126, 177-178.
- D25 Merge_flag. The flag is the table membership test taken on the table BEFORE the update, passed into `rx_learn` as `merged`. Alt: re-test after update (would always be true for a present entry; the insert would then be skipped wrongly only for the absent case, equal result). Chose pre-state flag to mirror the text. l.209-217.
- D26 Learning without a pending request. Replies are accepted and learned with no record of an outstanding request, and requests from anyone are learned. Alts: only accept replies to my requests. Chose accept (no state), matching "enters ... the information"; recorded as Q3. l.216-218, 306-309.
- D27 The packet must be an ARP frame at the Ethernet type. Assumed true of any input to reception; the type field is not a parameter. l.139, 176, 197-198.
- D28 Reply when I am the target but the request's sha is not unicast-able (e.g., broadcast). Not addressed; chose no check (see D12).
- D29 Scope of "target" for monitoring nodes. A monitor "always enters" the sender triplet; this role is excluded (X4) and `rx_table` follows the ordinary node.
- D30 Table size. Insert never fails and never evicts. Alts: bounded table with eviction. Chose unbounded (a bound would add a capacity parameter the RFC never states). l.415-416, 438-439.

## 4. Exclusions (X-rows)

- X1 Non-Ethernet hardware and hln other than 6; protocol lengths above 4 bytes. Generalization is described only loosely. l.31-33, 236-242, 272-277.
- X2 Byte layout, field offsets, padding, byte order, packet length and truncation; decoding is assumed done. l.63-66, 128-155, 320-323.
- X3 The Ethernet header (destination, source, type), the 14-byte header, and hardware drivers. l.135-139, 315-318.
- X4 The network monitor/debugger role and its table rules. l.326-364.
- X5 Aging, timeouts, table clearing, deletion on failed connections, and the verification daemon with retransmissions. All time-based or external. l.412-466.
- X6 Time, retransmission of requests, higher-layer retransmission of dropped packets, request rate. l.172-175, 450-453.
- X7 Network delivery: that a broadcast reaches all stations ("perfect Ethernet"), that a unicast arrives, the hosts X and Y example as a two-node system. l.388-391, 446-447.
- X8 Routing and next-hop choice; choosing the hardware; the protocol layers above. l.161-165.
- X9 Concurrency and several interfaces/addresses; the table-scan cost and hashing. l.438-439.
- X10 Authority for assigning hardware-space values, and the numeric registry of ether_type values. l.68-75, 115-121.
- X11 Security: spoofed or unsolicited packets are accepted by design (D26) and no property about authenticity is stated.
- X12 Design rationale for the format (periodic broadcast cost, no multiplexing, field sizes). Non-normative. l.245-324.
- X13 "Why a reply has the same length / buffer reuse" as an implementation hint. l.268-270.

## 5. Open questions for the RFC author

- Q1 Should a packet with ar$sha equal to a broadcast/multicast address, or ar$spa equal to my own address, be learned? l.210-218.
- Q2 Is a gratuitous packet (spa = tpa) meant to update other hosts' entries, given the target test? l.214-218.
- Q3 Should a REPLY be accepted when I have no outstanding REQUEST? l.216-218, 306-309.
- Q4 When the target test fails, the packet is "discarded" but the merge already happened: is the merge intended to survive? l.200-201, 210-214.
- Q5 Is the request's destination required to be the hardware broadcast address, or may it be sent to a specific address? l.188-190.
- Q6 Should ar$pln mismatch with the table's known length for that protocol be an error even when length checking is "optional"? l.205, 208, 288-292.
- Q7 Is ar$tha in a request required to be anything, and must it be ignored on receipt? l.184-188, 311-314.
- Q8 May the reply be sent to the frame's source address instead of the sender hardware address if they differ? l.224-225, 315-318.
- Q9 What if the opcode is neither REQUEST nor REPLY: discard, or learn as in D9? l.219, 227-229.
- Q10 For a node with several protocol addresses or interfaces, is "Am I the target protocol address" any of them, and does the reply carry the receiving interface's address? l.214, 221-225.
- Q11 Is the "probably informs the caller" drop of the original packet optional, and may the packet be queued instead? l.172-176.
