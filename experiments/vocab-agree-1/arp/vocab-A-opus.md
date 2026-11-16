# Vocabulary for RFC 826 (ARP)

Source: `rfc826.txt` (470 lines). Line numbers are cited as `L123` or `L123-130`.
This file defines sorts, step functions and modeling decisions only. It has no contracts and no code.

Reading of the RFC in one paragraph: there are two paths. On transmit (L161-190), the module looks up
`<pro, target protocol address>` in a table. On a hit it returns the hardware address. On a miss it
discards the outgoing packet and broadcasts a REQUEST. On receive (L197-225), the module gates on
`ar$hrd`, an optional check of `ar$hln`, `ar$pro` and an optional check of `ar$pln`. It then merges
the sender pair into the table, decides whether it is the target, adds the entry if it is the target
and nothing was merged, and only then looks at the opcode to decide whether to reply. A monitor
variant (L337-348) is described too.

---

## 1. Sorts (M-rows)

| ID | Sort | Definition | Reason | RFC |
|---|---|---|---|---|
| M1 | `U16` | `(where [v: int] (and (>= v 0) (< v 65536)))` | `ar$hrd`, `ar$pro`, `ar$op` are 16-bit words | L141-148, L320-323 |
| M2 | `U8` | `(where [v: int] (and (>= v 0) (< v 256)))` | `ar$hln`, `ar$pln` are 8-bit lengths. Also one raw byte of the fixed header | L146-147 |
| M3 | `HwAddr` | `(where [v: int] (and (>= v 0) (< v 281474976710656)))`, which is 2^48 | Ethernet hardware address as a big-endian integer. Fixed to 48 bits, see D3 | L9, L23, L137-138, L179-180 |
| M4 | `ProtoAddr` | `(where [v: int] (>= v 0))` | Protocol address as a big-endian integer, with no upper bound because `ar$pln` is per protocol (see D3, D34) | L151-155, L94-95 |
| M5 | `ProtoType` | alias of `U16` | Value of `ar$pro`. For Ethernet it is an `ether_type$` value. The RFC gives no numeric values, so it is kept opaque | L143-145, L279-281 |
| M6 | `HwType` | alias of `U16` | Value of `ar$hrd`. Only `ares_hrd$Ethernet = 1` is defined, but other values are anticipated, so not an enum | L126, L272-277 |
| M7 | `Opcode` | enum `OpRequest \| OpReply \| OpOther` | Classification of `ar$op`. Only 1 and 2 are defined. The other 65534 values need a tag so the receive algorithm stays total (D12, D32) | L123-124, L148, L294-296 |
| M8 | `TableKey` | `(where [v: int] (>= v 0))`, built only by `table_key` | Single int encoding of the pair `<protocol type, sender protocol address>`, because maps key on one int (D1) | L210-211, L232-233, L443-444 |
| M9 | `Table` | `map[int, int]`, TableKey to HwAddr | The translation table: pair to hardware address. One per interface (D43) | L170, L210-218, L227-233 |
| M10 | `MyAddrs` | `map[int, int]`, ProtoType to ProtoAddr | The local host's protocol address for each protocol it speaks. `has` means "I speak it" and `get` means "my address in it" (D8, D9) | L206, L214, L182, L221-222 |
| M11 | `ProtoLens` | `map[int, int]`, ProtoType to U8 | Expected protocol-address byte length per protocol. Used by the optional `ar$pln` check and by request generation | L180, L208, L288-291 |
| M12 | `RxGate` | enum `GateAccept \| DropHrd \| DropHln \| DropPro \| DropPln` | Result of the four guards that come before the merge. A negative result ends processing and discards the packet | L200-208 |
| M13 | `RxAction` | enum `RxDiscard \| RxAbsorb \| RxReply` | What happens to the packet after the table step: dropped at a gate, consumed without a reply, or turned into a reply | L200-201, L219-225, L341-344 |
| M14 | `Lookup` | sum `Found HwAddr \| Miss` | Result of a transmit-side table lookup | L170-176 |
| M15 | `TxAction` | enum `TxSend \| TxDiscardAndRequest` | Transmit decision: send the packet to the found address, or throw it away and broadcast a REQUEST | L171-176 |
| M16 | `Dest` | sum `DestBroadcast \| DestUnicast HwAddr` | Link destination of an ARP packet the module emits. The request is broadcast and the reply is unicast to the new target | L189, L224-225, L391, L400-401 |
| M17 | `Role` | enum `RoleHost \| RoleMonitor` | Selects the normal receive algorithm or the monitor algorithm | L197-225, L337-344 |

Named constants (nullary functions, not sorts): `ARES_OP_REQUEST = 1`, `ARES_OP_REPLY = 2`,
`ARES_HRD_ETHERNET = 1`, `ETHER_HLN = 6`, `ETHER_BROADCAST = 2^48 - 1` (L123-126, L179, L186-187, L238).

---

## 2. Steps

### How the algorithm is split, and why

The target has no records with several fields and no multi-value results. So one RFC action that
produces "a new table and maybe a reply packet" becomes several total functions over the same inputs.
There is one function per result component: the new table, the action tag, and each reply field. Each
RFC sentence then maps to exactly one step, so a clause writer can attach one obligation to one
function. The receive algorithm (L203-225) splits along its own control points: the gate (L203-208),
the merge flag (L209-213), the target test (L214), the add (L216-218), the opcode test (L219) and the
reply rewrite (L221-225). Transmit (L170-190) splits into lookup, decision and request fields. Packet
parsing is limited to the 8-byte fixed-offset header (D31). The variable-offset address fields come in
already decoded (X3).

### 2a. Header decoding (fixed offsets only)

| ID | Signature | Purpose | RFC |
|---|---|---|---|
| S1 | `decode_u16 [hi: U8 lo: U8] -> U16` | Big-endian word, `256*hi + lo` | L63-66, L123, L320-323 |
| S2 | `opcode_of [op: U16] -> Opcode` | 1 gives `OpRequest`, 2 gives `OpReply`, anything else gives `OpOther` | L123-124, L148 |

### 2b. Receive: gate

| ID | Signature | Purpose | RFC |
|---|---|---|---|
| S3 | `hrd_ok [hrd: HwType my_hrd: HwType] -> bool` | "Do I have the hardware type in ar$hrd?" | L203 |
| S4 | `hln_ok [hln: U8 my_hln: U8 check: bool] -> bool` | Optional hardware length check. Always true when `check` is false | L205, L288-292 |
| S5 | `speaks [pro: ProtoType mine: MyAddrs] -> bool` | "Do I speak the protocol in ar$pro?" is `has(mine, pro)` | L206 |
| S6 | `pln_ok [pro: ProtoType pln: U8 lens: ProtoLens check: bool] -> bool` | Optional protocol length check against `get(lens, pro)` | L208, L288-292 |
| S7 | `rx_gate [hrd: HwType hln: U8 pro: ProtoType pln: U8 my_hrd: HwType my_hln: U8 mine: MyAddrs lens: ProtoLens chk_hln: bool chk_pln: bool] -> RxGate` | Runs S3-S6 in RFC order and returns the first failure, or `GateAccept` | L200-208 |

### 2c. Receive: table and decision

| ID | Signature | Purpose | RFC |
|---|---|---|---|
| S8 | `table_key [pro: ProtoType spa: ProtoAddr] -> TableKey` | `pro + 65536*spa`, which is injective because `pro < 65536` (D1) | L210, L232-233 |
| S9 | `merge_flag [tbl: Table pro: ProtoType spa: ProtoAddr] -> bool` | Whether the pair is already in the table (the value of Merge_flag after L209-213) | L209-213 |
| S10 | `is_target [pro: ProtoType tpa: ProtoAddr mine: MyAddrs] -> bool` | "Am I the target protocol address?" is `has(mine,pro) and get(mine,pro) = tpa` | L214, L302-304 |
| S11 | `rx_table [tbl: Table pro: ProtoType spa: ProtoAddr sha: HwAddr tpa: ProtoAddr mine: MyAddrs] -> Table` | Table after a GateAccept packet. If the pair is present, set it to `sha`. Else if this host is the target, add it. Else leave the table unchanged | L209-218, L227-233, L443-445 |
| S12 | `rx_action [gate: RxGate op: Opcode target: bool] -> RxAction` | `RxDiscard` unless GateAccept. Otherwise `RxReply` if target and `OpRequest`, else `RxAbsorb` | L200-201, L214-225 |
| S13 | `rx_table_final [gate: RxGate tbl: Table pro: ProtoType spa: ProtoAddr sha: HwAddr tpa: ProtoAddr mine: MyAddrs] -> Table` | `tbl` unchanged unless gate is GateAccept, otherwise S11 | L200-201, L209 |

### 2d. Receive: reply construction (only meaningful when S12 = RxReply)

| ID | Signature | Purpose | RFC |
|---|---|---|---|
| S14 | `reply_op [] -> U16` | `ARES_OP_REPLY` | L223 |
| S15 | `reply_sha [my_ha: HwAddr] -> HwAddr` | Local hardware address goes into the sender field | L221-222, L398-399 |
| S16 | `reply_spa [pro: ProtoType mine: MyAddrs] -> ProtoAddr` | Local protocol address goes into the sender field | L221-222 |
| S17 | `reply_tha [sha: HwAddr] -> HwAddr` | Old sender hardware address becomes the target field | L221, L313-314 |
| S18 | `reply_tpa [spa: ProtoAddr] -> ProtoAddr` | Old sender protocol address becomes the target field | L221 |
| S19 | `reply_dest [sha: HwAddr] -> Dest` | `DestUnicast sha`, the new target hardware address and not a broadcast | L224-225, L400-401, L345-346 |
| S20 | `reply_hdr_word [w: U16] -> U16` and `reply_hdr_byte [b: U8] -> U8` | Identity on `hrd`, `pro` and `hln`, `pln`. The reply reuses the request's header (D19) | L268-270 |

### 2e. Transmit

| ID | Signature | Purpose | RFC |
|---|---|---|---|
| S21 | `resolve [tbl: Table pro: ProtoType tpa: ProtoAddr] -> Lookup` | Table lookup on `<protocol type, target protocol address>` | L168-172 |
| S22 | `tx_action [hit: bool] -> TxAction` | `TxSend` on a hit, `TxDiscardAndRequest` on a miss. `hit` is the constructor test on S21 | L171-176 |
| S23 | `tx_table [tbl: Table] -> Table` | Identity. Transmitting a request does not change the table (D26) | L170-190 (no table write) |
| S24 | `req_hrd [my_hrd: HwType] -> HwType` | `ar$hrd` is the interface's hardware type, which is `ARES_HRD_ETHERNET` on Ethernet | L177-178, L382 |
| S25 | `req_pro [pro: ProtoType] -> ProtoType` | `ar$pro` is the protocol being resolved | L178-179, L383 |
| S26 | `req_hln [my_hln: U8] -> U8` | `ar$hln` is 6 on Ethernet | L179-180, L384 |
| S27 | `req_pln [pro: ProtoType lens: ProtoLens] -> U8` | `ar$pln` is the address length of that protocol | L180, L385 |
| S28 | `req_op [] -> U16` | `ARES_OP_REQUEST` | L181, L386 |
| S29 | `req_sha [my_ha: HwAddr] -> HwAddr` | The module's own hardware address | L181-182, L387 |
| S30 | `req_spa [pro: ProtoType mine: MyAddrs] -> ProtoAddr` | The module's own protocol address in `pro` | L182, L388 |
| S31 | `req_tha [fill: HwAddr] -> HwAddr` | Unspecified. Returns a caller-chosen filler, typically 0 or `ETHER_BROADCAST` (D20) | L184-188, L389 |
| S32 | `req_tpa [tpa: ProtoAddr] -> ProtoAddr` | The protocol address being resolved | L182-184, L390 |
| S33 | `req_dest [] -> Dest` | `DestBroadcast` | L188-190, L391 |

### 2f. Monitor role (optional profile)

| ID | Signature | Purpose | RFC |
|---|---|---|---|
| S34 | `mon_table [tbl: Table pro: ProtoType spa: ProtoAddr sha: HwAddr] -> Table` | The monitor always enters the triplet: `set(tbl, key, sha)` | L337-339 |
| S35 | `mon_action [op: Opcode target: bool] -> RxAction` | REPLY gives `RxAbsorb`. REQUEST addressed to the monitor gives `RxReply`. Otherwise `RxAbsorb` | L341-344 |

Reply fields for a monitor reply reuse S14-S20, "as it normally would" (L344).

---

## 3. Modeling decisions (D-rows)

| ID | Question | Alternatives | Choice | RFC |
|---|---|---|---|---|
| D1 | The table is keyed by a pair, but maps key on a single int or string | (a) `pro + 65536*spa`; (b) one map per protocol, keyed by `spa`; (c) string key built by concatenation | (a). Linear (a constant multiple), injective since `0 <= pro < 65536`, and one map covers every protocol. Strings are excluded because building them is not decidable arithmetic | L210, L97, L131 |
| D2 | Addresses as byte arrays or as integers | (a) big-endian int; (b) fixed byte arrays | (a). Equality and map keys need scalars, and byte arrays have a fixed length while `pln` varies | L149-155, L63-64 |
| D3 | `ar$hln` and `ar$pln` are variable, so the address width depends on a packet value | (a) bound HwAddr by `2^(8*hln)`, which is nonlinear; (b) fix hardware to 48 bits and leave ProtoAddr unbounded; (c) fix both to Ethernet/IPv4 (6/4) | (b). The title and every worked example are Ethernet (L6-11, L238). Protocol widths vary among supported protocols (8, 16, 32 bits, L94-95), so a fixed bound would wrongly exclude some | L146-155, L236-242 |
| D4 | "Do I have the hardware type": one value or a set? | (a) equality with the receiving interface's `my_hrd`; (b) membership in a set of supported types | (a). Processing is per piece of hardware (L163, L225), and one interface has one hardware type | L203-204 |
| D5 | The `ar$hln` check is "optional": include it, drop it, or make it mandatory? | (a) mandatory; (b) omitted; (c) a `check` flag parameter | (c). Contracts can then cover both conforming variants. Expected value: `my_hln` (6 for hrd 1, L238) | L205, L288-292 |
| D6 | Same question for the `ar$pln` check, and where the expected value comes from | (a)/(b)/(c) as in D5; source from `ProtoLens` or from the packet | (c) with `get(lens, pro)`. L289-291 says length is "determined by" `<hrd, pro>`, so it comes from local configuration | L208, L288-292 |
| D7 | Order of the gates and which failure is reported | Any order; report a set of failures | RFC nesting: hrd, then hln, then pro, then pln. The first failure is the result (RxGate) | L203-208 |
| D8 | "Speak the protocol" versus "have an address in it": separate notions? | (a) a separate `speaks` set plus an address map; (b) conflate them, so speaking means having an address | (b). L214 and L221-222 need a local address in `pro` whenever processing gets that far. A host that speaks a protocol with no address would merge but never be a target. That case is listed as an open question | L206, L214, L221-222 |
| D9 | One or several local protocol addresses per protocol | (a) one (`map pro -> addr`); (b) a set | (a). The RFC always writes "the protocol address of itself" (L182) in the singular. Aliases are an open question | L182, L214 |
| D10 | Does the update of an existing entry depend on being the target? | (a) update only if target; (b) update whenever present | (b). The update at L210-213 is outside the "Am I the target" branch, and L443-447 relies on every station updating from a broadcast | L210-213, L443-447 |
| D11 | Is a new entry added when the host is not the target? | (a) yes, a monitor-like learn-all; (b) no | (b) for RoleHost. The add sits inside the "Yes" of L214. RoleMonitor uses (a), see D38 | L214-218, L337-339 |
| D12 | Is the opcode checked before merging, or are unknown opcodes dropped? | (a) drop `OpOther` at the gate; (b) merge regardless of opcode | (b). "NOW look at the opcode!!" (L219) and L227-229 put the merge before any opcode inspection. So REPLY and unknown opcodes also merge and add | L219, L227-229, L307-309 |
| D13 | What happens to `OpOther` after the merge | Reply; discard; absorb | `RxAbsorb`, with no reply. Only `= REQUEST` triggers the swap | L219-225 |
| D14 | Reply condition | target and REQUEST; REQUEST alone | target and REQUEST. The opcode test is nested inside the target test | L214-225 |
| D15 | Reply `ar$spa`: the local address or the request's `tpa`? | (a) `get(mine, pro)`; (b) `tpa` | (a). L221-222 says "local ... protocol addresses". Under the reply guard (S10) the two are equal, which a clause can state | L221-222 |
| D16 | Reply `ar$sha`: which local hardware address? | The receiving interface's address; any local address | The receiving interface's `my_ha`. The reply goes out "on the same hardware" (L225) | L221-225, L398-399 |
| D17 | Exact meaning of "swap hardware and protocol fields" | (a) tha := sha, tpa := spa, and the senders become local; (b) a literal swap that also moves the old tha into sha | (a). The swap is immediately qualified as "putting the local ... addresses in the sender fields" (L221-222). The example confirms it (L398-399) | L221-222, L313-314 |
| D18 | Reply destination | Broadcast; old `sha`; Ethernet header source | Unicast to the new `tha`, which is the old `sha`. The header source is not modeled (D29) | L224-225, L400-401 |
| D19 | Reply `hrd/pro/hln/pln`: copied or regenerated? | (a) copied from the request; (b) regenerated from local configuration | (a). The buffer is reused (L268-270) and only op and the address fields are said to change. When the checks are off, a request's wrong `hln/pln` is echoed back. That consequence is accepted and flagged | L221-223, L268-270 |
| D20 | Request `ar$tha` value | (a) fixed 0; (b) fixed broadcast; (c) unconstrained | (c). The RFC says "not ... anything in particular" and "don't care". Broadcast is only permitted. Clause writers must not assert a value. S31 takes a free `fill` | L184-188, L389, L312-313 |
| D21 | What address is "broadcast" for the request destination | All ones; a parameter | `DestBroadcast` as a tag. All ones (`2^48-1`) is the Ethernet instance | L186-190 |
| D22 | Request `ar$hrd` value outside Ethernet | Hard-code 1; the interface's type | The interface's `my_hrd`. On Ethernet it equals `ARES_HRD_ETHERNET`, matching the L177-178 text | L177-178, L236-242 |
| D23 | Source of request `ar$pln` | Packet; config; computed | `get(lens, pro)`, "the length of an address in that protocol" | L180 |
| D24 | On a miss, is the original packet discarded or queued? | (a) discard; (b) queue until reply | (a). The RFC says "probably ... throwing the packet away", relying on higher-layer retransmission. Queueing would need state and time | L172-176, L379-380 |
| D25 | Is the request repeated, or rate limited, on repeated misses? | Throttle; one request per miss | One request per miss with no state. Throttling needs time (X1) | L170-176 |
| D26 | Does sending a request create a pending or incomplete entry? | Add a placeholder; no change | No change (S23). The RFC writes the table only on reception | L170-190, L209-218 |
| D27 | Is a reply accepted only if it matches an outstanding request? | Match pending requests; accept any | Accept any. No pending-request state exists. A reply merges or adds like any packet whose `tpa` is ours | L305-306, L404-405 |
| D28 | A received packet whose `spa` is one of my own addresses (a loopback of my own broadcast, or a conflict) | Special-case it, drop it, or literal processing | Literal processing. It may add or update an entry for my own address. Flagged as an open question | L209-218 (silent) |
| D29 | Ethernet header source differs from `ar$sha` | Prefer the header; check equality; ignore the header | Ignore the header. Only `ar$sha` is put in the table (L298-300), and the header may be inaccessible (L135-136, L315-318) | L135-139, L298-300 |
| D30 | Checking that the Ethernet type is `ether_type$ADDRESS_RESOLUTION` | A step; assume already dispatched | Assume it was dispatched before ARP sees the packet ("receiving Ethernet module gives the packet", L197-198). No numeric value is given anyway | L139, L197-198 |
| D31 | Byte order and which fields can be decoded in-model | Decode all fields; decode none | Decode only the 8-byte fixed header (hrd, pro, hln, pln, op at fixed offsets 0-7) with S1, big-endian. The address fields are inputs | L63-66, L141-148, L320-323 |
| D32 | Opcode classification of values other than 1 and 2 | Partial; error; a tag | The `OpOther` tag. No ordering on opcodes is imported, and classification uses equality to 1 and 2 only | L123-124, L294-296 |
| D33 | Should "high byte first" for `ar$op` be a separate obligation? | Separate; folded into S1 | Folded into S1. "Special care" (L65-66) is exactly the decode order | L63-66 |
| D34 | Protocol address equality when leading zero bytes could differ with `pln` | Compare `(pln, value)` pairs; compare values | Compare integer values. They are canonical when the `pln` check is on. With the check off, packets that differ only in `pln` look identical. Accepted and flagged | L151-155, L214 |
| D35 | Must hardware addresses be unique across table entries? | Reverse-uniqueness invariant; none | None. Several protocol addresses (and protocols) may map to one hardware address (L264-265, a bridge with four protocols) | L210-213, L264-266 |
| D36 | Table capacity and eviction | Bounded with eviction; unbounded | Unbounded, no eviction. The RFC is silent. Aging is out of scope (L415-416) | L415-416 |
| D37 | Tie between `hrd` and the expected `hln` | Derive `hln` from `hrd`; configure it | Configure `my_hln` per interface, with the documented instance `<1, 6>` | L238, L288-291 |
| D38 | Monitor algorithm: does it gate on `hrd`/`pro`? Does "enters" overwrite? | Gate like a host; no gate. Add-only; overwrite | No `speaks` gate (L333-334: it need not speak the protocols). "Always enters" is an unconditional `set`. The `hrd` gate is unspecified, and the monitor profile applies after `hrd_ok` only | L333-339 |
| D39 | Monitor "target protocol address matches the protocol address of the monitor" | Same as `is_target`; different | Same as S10, with the monitor's own `MyAddrs` | L342-344 |
| D40 | Value stored in a table entry | HwAddr only; an entry with metadata | HwAddr only. "Update the sender hardware address field of the entry" implies other fields, but none is defined that is in scope (age is X1) | L211-212 |
| D41 | One table per interface or a global table | Global with an interface in the key; per interface | Per interface. Resolution is tied to "which piece of hardware" (L163), and the reply goes out on the receiving hardware (L225). The singular "my translation table" is read per interface | L163, L210-211, L225 |
| D42 | Is the gate's failure discard different from "absorb"? | Merge them; keep them apart | Keep them apart. Discard happens before any table write, while absorb happens after the merge, so a contract can say "a gate failure implies the table is unchanged" | L200-201, L341-342 |
| D43 | Values of `hln`/`pln` equal to 0 | Reject; allow | Allowed by U8. The optional checks reject them when enabled. The RFC is silent | L146-147 |
| D44 | What the caller receives on a miss | Error tag; nothing | `TxDiscardAndRequest`. The caller is "probably" informed (L173), modeled as this tag | L172-174 |
| D45 | Which protocol address is the target of the request (next hop or final destination) | Final; next hop | Next hop, supplied by routing (L161-164), passed as `tpa` | L161-169 |
| D46 | Reply `ar$op` byte order | Host order; network order | Network order, the same as S1. The constant is 2 | L63-66, L123-124 |

---

## 4. Exclusions (X-rows)

| ID | Not modeled | Why | RFC |
|---|---|---|---|
| X1 | Table aging, timeouts, deletion daemon, timeout reset on reception, probe retransmission | Time and clocks are outside the target. The RFC also puts them outside the protocol's scope | L415-416, L434-457 |
| X2 | Actual transmission, broadcast delivery, the Ethernet header fields | Network I/O is outside the target. Steps return `Dest` and field values only | L135-139, L189, L224-225 |
| X3 | Parsing `sha/spa/tha/tpa` out of the byte stream | Their offsets depend on `hln/pln` read from the same packet. They are taken as decoded inputs | L149-155, L320-323 |
| X4 | Higher-layer retransmission and queueing of the discarded datagram | Outside ARP, and stateful over time | L174-175, L406-408 |
| X5 | Routing (choice of next hop and interface) | Input to ARP, not part of it | L161-164, L189-190 |
| X6 | Multiple interfaces and choosing between them | One interface per call (D41). The cross-interface behaviour is not specified | L163, L225 |
| X7 | A monitor sending its own REQUESTs, and the two-monitor loop | Explicitly discouraged ("care must be taken"). Needs state and time | L346-348 |
| X8 | Display and debugging of packets | No observable protocol obligation | L357-364 |
| X9 | Hardware name-space authority and assignment of `hrd` values | Administrative | L68-75, L272-277 |
| X10 | Deleting entries on connection failure, and manual table clearing | Triggered by events outside ARP. A clear would be `empty`, but no RFC step defines one | L430-433, L464-466 |
| X11 | Multiple resolutions in one packet | Forbidden by the format | L260-266 |
| X12 | Concurrency between transmit and receive on the same table | Concurrency is outside the target | (silent) |
| X13 | Spoofing, authentication, cache poisoning defenses | Not in the RFC, and they would change D10 | L428-430 (mentions only accidental errors) |
| X14 | Hardware-specific semantics for non-Ethernet media (packet radio) | Only parameters (`my_hrd`, `my_hln`) carry the generalization. HwAddr stays 48 bits (D3) | L31-33, L236-242, L274-277 |
| X15 | Numeric `ether_type$` values, including `ether_type$ADDRESS_RESOLUTION` | Not given in the RFC. They are opaque U16 parameters | L115-121 |
| X16 | Host moves and reboot clearing of the host's own table | Lifecycle events. The RFC assumes the moving host's table is cleared but defines no step for it | L419-423, L459-461 |
| X17 | Packet-length and truncation checks, and the trailing bytes after `tpa` | Byte-level, value-dependent. The input is assumed well formed | L320-323 |

---

## 5. Open questions for the author

1. Should a packet whose `ar$op` is neither REQUEST nor REPLY still update or add table entries (D12)? Literally it does.
2. If the optional `hln`/`pln` checks are skipped and the packet's lengths are wrong, should the reply echo them, or be rebuilt from local values (D19)?
3. Is "I speak the protocol" (L206) different from "I have an address in the protocol"? If a host speaks a protocol but has no address in it, what does L214 mean (D8)?
4. Can a host have several addresses in one protocol, and is it the target if `tpa` matches any of them (D9)?
5. What should happen when a received packet's `spa` equals the receiver's own address in that protocol: a duplicate, or its own broadcast looped back (D28)?
6. Must `ar$sha` agree with the Ethernet source address, and what if it does not (D29)?
7. Is one translation table shared across interfaces, or is there one per interface (D41)?
8. When the requester misses, may it keep the datagram instead of discarding it (L173, "probably")?
9. Should a host learn from REQUESTs not addressed to it when the pair is absent? Only update-if-present is specified (D10, D11).
10. Does the monitor check `ar$hrd` before entering the triplet (D38)?
11. Should a REPLY that answers no outstanding request be accepted (D27)?
12. Does sending a REQUEST create any table state, for example to suppress duplicate requests (D25, D26)?
13. Is `ar$tha` in a REPLY required to equal the requester's `ar$sha`, or only "its meaning" (L313-314)?
14. What should a receiver do with `ar$hln` or `ar$pln` equal to 0 (D43)?
