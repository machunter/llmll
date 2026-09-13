# Stage F: name the characteristic core

Write `core.json`: the clauses that make this protocol **this protocol**, the handful whose
loss would mean you had not implemented it at all.

Do this **now**, before any disposition exists, so the set cannot be drawn around whatever
happens to succeed. That ordering is the whole value of this stage.

## Output contract

```json
{"core_ids": ["A012", "A013", "A016"],
 "rationale": "one sentence per id, saying why losing it would mean the protocol was not implemented"}
```

## How to choose

Ask of each candidate: if an implementation got this wrong but everything else right, would a
competent reviewer say it had implemented the protocol? If yes, it is not core. Expect a
handful to a couple of dozen rows, not a majority of the inventory.

Favor the clauses that carry the protocol's characteristic discipline: its sequencing rule, its
termination rule, its error behavior, and any rule a later document added specifically to fix a
known bug. Do not include a clause merely because it is important-sounding, and do not include
one because you expect it to be easy to verify. You do not yet know what will verify, and that
is deliberate.

## Consequence

No row named here may later be dispositioned out. If one is, the pipeline STOPs and the target
is re-scoped rather than re-graded. Choosing the core honestly now is what gives that condition
its force.

## The reconciled inventory

[
 {
  "id": "A1",
  "source": "RFC826",
  "line_start": 63,
  "line_end": 64,
  "section": "Notes",
  "quote": "Numbers here are in the Ethernet standard, which is high byte first.",
  "rule": "N3",
  "strength": "none",
  "obligation": "Multi-byte numeric fields of the packet are transmitted high byte first."
 },
 {
  "id": "A2",
  "source": "RFC826",
  "line_start": 65,
  "line_end": 66,
  "section": "Notes",
  "quote": "special care must be taken with the opcode field (ar$op) described below",
  "rule": "N3",
  "strength": "must",
  "obligation": "An implementation on a low-byte-first machine must encode and decode the ar$op field in high-byte-first order rather than native order."
 },
 {
  "id": "A3",
  "source": "RFC826",
  "line_start": 90,
  "line_end": 93,
  "section": "The Problem",
  "quote": "the 10Mbit Ethernet requires 48.bit addresses on the physical cable",
  "rule": "N10",
  "strength": "must",
  "obligation": "The protocol relies on Ethernet hardware addresses being 48 bits wide, which is what makes a hardware address length of 6 correct."
 },
 {
  "id": "A4",
  "source": "RFC826",
  "line_start": 123,
  "line_end": 123,
  "section": "Definitions",
  "quote": "ares_op$REQUEST (= 1, high byte transmitted first)",
  "rule": "N4",
  "strength": "none",
  "obligation": "The opcode value for a request is 1."
 },
 {
  "id": "A5",
  "source": "RFC826",
  "line_start": 123,
  "line_end": 123,
  "section": "Definitions",
  "quote": "ares_op$REQUEST (= 1, high byte transmitted first)",
  "rule": "N3",
  "strength": "none",
  "obligation": "The opcode value is transmitted with its high byte first."
 },
 {
  "id": "A6",
  "source": "RFC826",
  "line_start": 124,
  "line_end": 124,
  "section": "Definitions",
  "quote": "ares_op$REPLY   (= 2)",
  "rule": "N4",
  "strength": "none",
  "obligation": "The opcode value for a reply is 2."
 },
 {
  "id": "A7",
  "source": "RFC826",
  "line_start": 126,
  "line_end": 126,
  "section": "Definitions",
  "quote": "ares_hrd$Ethernet (= 1)",
  "rule": "N4",
  "strength": "none",
  "obligation": "The hardware address space value for 10Mbit Ethernet is 1."
 },
 {
  "id": "A8",
  "source": "RFC826",
  "line_start": 137,
  "line_end": 137,
  "section": "Packet format",
  "quote": "48.bit: Ethernet address of destination",
  "rule": "N3",
  "strength": "none",
  "obligation": "The first field of the Ethernet transmission layer is the 48-bit Ethernet address of the destination."
 },
 {
  "id": "A9",
  "source": "RFC826",
  "line_start": 138,
  "line_end": 138,
  "section": "Packet format",
  "quote": "48.bit: Ethernet address of sender",
  "rule": "N3",
  "strength": "none",
  "obligation": "The second field of the Ethernet transmission layer is the 48-bit Ethernet address of the sender."
 },
 {
  "id": "A10",
  "source": "RFC826",
  "line_start": 139,
  "line_end": 139,
  "section": "Packet format",
  "quote": "16.bit: Protocol type = ether_type$ADDRESS_RESOLUTION",
  "rule": "N3",
  "strength": "none",
  "obligation": "The 16-bit Ethernet type field of an address resolution packet carries the value ether_type$ADDRESS_RESOLUTION."
 },
 {
  "id": "A11",
  "source": "RFC826",
  "line_start": 141,
  "line_end": 142,
  "section": "Packet format",
  "quote": "16.bit: (ar$hrd) Hardware address space (e.g., Ethernet, Packet Radio Net.)",
  "rule": "N3",
  "strength": "none",
  "obligation": "The first field of the packet data is a 16-bit ar$hrd field naming the hardware address space."
 },
 {
  "id": "A12",
  "source": "RFC826",
  "line_start": 143,
  "line_end": 143,
  "section": "Packet format",
  "quote": "16.bit: (ar$pro) Protocol address space.",
  "rule": "N3",
  "strength": "none",
  "obligation": "The second field of the packet data is a 16-bit ar$pro field naming the protocol address space."
 },
 {
  "id": "A13",
  "source": "RFC826",
  "line_start": 143,
  "line_end": 145,
  "section": "Packet format",
  "quote": "For Ethernet hardware, this is from the set of type fields ether_typ$<protocol>.",
  "rule": "N4",
  "strength": "none",
  "obligation": "On Ethernet hardware the value of ar$pro is drawn from the set of Ethernet protocol type field values."
 },
 {
  "id": "A14",
  "source": "RFC826",
  "line_start": 146,
  "line_end": 146,
  "section": "Packet format",
  "quote": " 8.bit: (ar$hln) byte length of each hardware address",
  "rule": "N3",
  "strength": "none",
  "obligation": "The third field of the packet data is an 8-bit ar$hln field giving the byte length of each hardware address in the packet."
 },
 {
  "id": "A15",
  "source": "RFC826",
  "line_start": 147,
  "line_end": 147,
  "section": "Packet format",
  "quote": " 8.bit: (ar$pln) byte length of each protocol address",
  "rule": "N3",
  "strength": "none",
  "obligation": "The fourth field of the packet data is an 8-bit ar$pln field giving the byte length of each protocol address in the packet."
 },
 {
  "id": "A16",
  "source": "RFC826",
  "line_start": 148,
  "line_end": 148,
  "section": "Packet format",
  "quote": "16.bit: (ar$op)  opcode (ares_op$REQUEST | ares_op$REPLY)",
  "rule": "N3",
  "strength": "none",
  "obligation": "The fifth field of the packet data is a 16-bit ar$op opcode field holding either ares_op$REQUEST or ares_op$REPLY."
 },
 {
  "id": "A17",
  "source": "RFC826",
  "line_start": 149,
  "line_end": 150,
  "section": "Packet format",
  "quote": "nbytes: (ar$sha) Hardware address of sender of this packet, n from the ar$hln field.",
  "rule": "N3",
  "strength": "none",
  "obligation": "The sixth field of the packet data is ar$sha, the sender's hardware address, occupying exactly as many bytes as ar$hln states."
 },
 {
  "id": "A18",
  "source": "RFC826",
  "line_start": 151,
  "line_end": 152,
  "section": "Packet format",
  "quote": "mbytes: (ar$spa) Protocol address of sender of this packet, m from the ar$pln field.",
  "rule": "N3",
  "strength": "none",
  "obligation": "The seventh field of the packet data is ar$spa, the sender's protocol address, occupying exactly as many bytes as ar$pln states."
 },
 {
  "id": "A19",
  "source": "RFC826",
  "line_start": 153,
  "line_end": 154,
  "section": "Packet format",
  "quote": "nbytes: (ar$tha) Hardware address of target of this packet (if known).",
  "rule": "N3",
  "strength": "none",
  "obligation": "The eighth field of the packet data is ar$tha, the target's hardware address if known, occupying exactly as many bytes as ar$hln states."
 },
 {
  "id": "A20",
  "source": "RFC826",
  "line_start": 155,
  "line_end": 155,
  "section": "Packet format",
  "quote": "mbytes: (ar$tpa) Protocol address of target.",
  "rule": "N3",
  "strength": "none",
  "obligation": "The ninth and last field of the packet data is ar$tpa, the target's protocol address, occupying exactly as many bytes as ar$pln states."
 },
 {
  "id": "A21",
  "source": "RFC826",
  "line_start": 161,
  "line_end": 164,
  "section": "Packet Generation",
  "quote": "routing determines the protocol address of the next hop for the packet and on which piece of hardware it expects to find the station with the immediate target protocol address",
  "rule": "N10",
  "strength": "none",
  "obligation": "The generation path relies on routing having already supplied the next-hop protocol address and the piece of hardware on which that station is expected."
 },
 {
  "id": "A22",
  "source": "RFC826",
  "line_start": 164,
  "line_end": 169,
  "section": "Packet Generation",
  "quote": "some lower layer (probably the hardware driver) must consult the Address Resolution module ... to convert the <protocol type, target protocol address> pair to a 48.bit Ethernet address",
  "rule": "N1",
  "strength": "must",
  "obligation": "Before an Ethernet packet can be transmitted, a lower layer must consult the Address Resolution module to convert the <protocol type, target protocol address> pair into a 48-bit Ethernet address."
 },
 {
  "id": "A23",
  "source": "RFC826",
  "line_start": 169,
  "line_end": 170,
  "section": "Packet Generation",
  "quote": "The Address Resolution module tries to find this pair in a table.",
  "rule": "N1",
  "strength": "none",
  "obligation": "On being consulted, the Address Resolution module looks the <protocol type, target protocol address> pair up in its translation table."
 },
 {
  "id": "A24",
  "source": "RFC826",
  "line_start": 170,
  "line_end": 172,
  "section": "Packet Generation",
  "quote": "If it finds the pair, it gives the corresponding 48.bit Ethernet address back to the caller",
  "rule": "N1",
  "strength": "none",
  "obligation": "When the lookup succeeds, the module returns the corresponding 48-bit Ethernet address to the caller."
 },
 {
  "id": "A25",
  "source": "RFC826",
  "line_start": 172,
  "line_end": 172,
  "section": "Packet Generation",
  "quote": "(hardware driver) which then transmits the packet",
  "rule": "N1",
  "strength": "none",
  "obligation": "On receiving the resolved address, the caller transmits the pending packet to it."
 },
 {
  "id": "A26",
  "source": "RFC826",
  "line_start": 172,
  "line_end": 175,
  "section": "Packet Generation",
  "quote": "If it does not, it probably informs the caller that it is throwing the packet away",
  "rule": "N7",
  "strength": "none",
  "obligation": "When the lookup fails, the module discards the packet awaiting transmission."
 },
 {
  "id": "A27",
  "source": "RFC826",
  "line_start": 173,
  "line_end": 175,
  "section": "Packet Generation",
  "quote": "it probably informs the caller that it is throwing the packet away (on the assumption the packet will be retransmitted by a higher network layer)",
  "rule": "N1",
  "strength": "may",
  "obligation": "On discarding the packet the module informs the caller that the packet is being thrown away."
 },
 {
  "id": "A28",
  "source": "RFC826",
  "line_start": 175,
  "line_end": 176,
  "section": "Packet Generation",
  "quote": "generates an Ethernet packet with a type field of ether_type$ADDRESS_RESOLUTION",
  "rule": "N5",
  "strength": "none",
  "obligation": "On a lookup failure the module generates an Ethernet packet whose Ethernet type field is ether_type$ADDRESS_RESOLUTION."
 },
 {
  "id": "A29",
  "source": "RFC826",
  "line_start": 176,
  "line_end": 178,
  "section": "Packet Generation",
  "quote": "The Address Resolution module then sets the ar$hrd field to ares_hrd$Ethernet",
  "rule": "N5",
  "strength": "none",
  "obligation": "In the generated request the module sets ar$hrd to ares_hrd$Ethernet."
 },
 {
  "id": "A30",
  "source": "RFC826",
  "line_start": 178,
  "line_end": 179,
  "section": "Packet Generation",
  "quote": "ar$pro to the protocol type that is being resolved",
  "rule": "N5",
  "strength": "none",
  "obligation": "In the generated request the module sets ar$pro to the protocol type whose address is being resolved."
 },
 {
  "id": "A31",
  "source": "RFC826",
  "line_start": 179,
  "line_end": 180,
  "section": "Packet Generation",
  "quote": "ar$hln to 6 (the number of bytes in a 48.bit Ethernet address)",
  "rule": "N4",
  "strength": "none",
  "obligation": "In a request generated for 10Mbit Ethernet the module sets ar$hln to 6."
 },
 {
  "id": "A32",
  "source": "RFC826",
  "line_start": 180,
  "line_end": 180,
  "section": "Packet Generation",
  "quote": "ar$pln to the length of an address in that protocol",
  "rule": "N5",
  "strength": "none",
  "obligation": "In the generated request the module sets ar$pln to the byte length of an address in the protocol being resolved."
 },
 {
  "id": "A33",
  "source": "RFC826",
  "line_start": 181,
  "line_end": 181,
  "section": "Packet Generation",
  "quote": "ar$op to ares_op$REQUEST",
  "rule": "N5",
  "strength": "none",
  "obligation": "In the generated request the module sets ar$op to ares_op$REQUEST."
 },
 {
  "id": "A34",
  "source": "RFC826",
  "line_start": 181,
  "line_end": 182,
  "section": "Packet Generation",
  "quote": "ar$sha with the 48.bit ethernet address of itself",
  "rule": "N5",
  "strength": "none",
  "obligation": "In the generated request the module sets ar$sha to its own 48-bit Ethernet address."
 },
 {
  "id": "A35",
  "source": "RFC826",
  "line_start": 182,
  "line_end": 182,
  "section": "Packet Generation",
  "quote": "ar$spa with the protocol address of itself",
  "rule": "N5",
  "strength": "none",
  "obligation": "In the generated request the module sets ar$spa to its own protocol address."
 },
 {
  "id": "A36",
  "source": "RFC826",
  "line_start": 182,
  "line_end": 184,
  "section": "Packet Generation",
  "quote": "ar$tpa with the protocol address of the machine that is trying to be accessed",
  "rule": "N5",
  "strength": "none",
  "obligation": "In the generated request the module sets ar$tpa to the protocol address of the machine being accessed."
 },
 {
  "id": "A37",
  "source": "RFC826",
  "line_start": 184,
  "line_end": 185,
  "section": "Packet Generation",
  "quote": "It does not set ar$tha to anything in particular, because it is this value that it is trying to determine.",
  "rule": "N5",
  "strength": "none",
  "obligation": "In the generated request ar$tha is left unconstrained, and a receiver may not rely on its content."
 },
 {
  "id": "A38",
  "source": "RFC826",
  "line_start": 185,
  "line_end": 188,
  "section": "Packet Generation",
  "quote": "It could set ar$tha to the broadcast address for the hardware (all ones in the case of the 10Mbit Ethernet) if that makes it convenient for some aspect of the implementation.",
  "rule": "N8",
  "strength": "may",
  "obligation": "The module is permitted to set ar$tha of a generated request to the hardware broadcast address."
 },
 {
  "id": "A39",
  "source": "RFC826",
  "line_start": 188,
  "line_end": 190,
  "section": "Packet Generation",
  "quote": "It then causes this packet to be broadcast to all stations on the Ethernet cable originally determined by the routing mechanism.",
  "rule": "N5",
  "strength": "none",
  "obligation": "The generated request is broadcast to all stations on the piece of hardware that routing selected."
 },
 {
  "id": "A40",
  "source": "RFC826",
  "line_start": 197,
  "line_end": 199,
  "section": "Packet Reception",
  "quote": "When an address resolution packet is received, the receiving Ethernet module gives the packet to the Address Resolution module",
  "rule": "N1",
  "strength": "none",
  "obligation": "A received address resolution packet is handed by the Ethernet module to the Address Resolution module for processing."
 },
 {
  "id": "A41",
  "source": "RFC826",
  "line_start": 200,
  "line_end": 201,
  "section": "Packet Reception",
  "quote": "Negative conditionals indicate an end of processing and a discarding of the packet.",
  "rule": "N7",
  "strength": "none",
  "obligation": "Whenever any test in the reception algorithm fails, processing ends and the received packet is discarded."
 },
 {
  "id": "A42",
  "source": "RFC826",
  "line_start": 203,
  "line_end": 204,
  "section": "Packet Reception",
  "quote": "?Do I have the hardware type in ar$hrd?",
  "rule": "N2",
  "strength": "none",
  "obligation": "On reception the module tests whether it supports the hardware type named in ar$hrd, and proceeds only if it does."
 },
 {
  "id": "A43",
  "source": "RFC826",
  "line_start": 205,
  "line_end": 205,
  "section": "Packet Reception",
  "quote": "[optionally check the hardware length ar$hln]",
  "rule": "N8",
  "strength": "may",
  "obligation": "The module is permitted, but not required, to check the hardware address length in ar$hln at this point."
 },
 {
  "id": "A44",
  "source": "RFC826",
  "line_start": 206,
  "line_end": 206,
  "section": "Packet Reception",
  "quote": "?Do I speak the protocol in ar$pro?",
  "rule": "N2",
  "strength": "none",
  "obligation": "On reception the module tests whether it speaks the protocol named in ar$pro, and proceeds only if it does."
 },
 {
  "id": "A45",
  "source": "RFC826",
  "line_start": 208,
  "line_end": 208,
  "section": "Packet Reception",
  "quote": "[optionally check the protocol length ar$pln]",
  "rule": "N8",
  "strength": "may",
  "obligation": "The module is permitted, but not required, to check the protocol address length in ar$pln at this point."
 },
 {
  "id": "A46",
  "source": "RFC826",
  "line_start": 209,
  "line_end": 209,
  "section": "Packet Reception",
  "quote": "Merge_flag := false",
  "rule": "N6",
  "strength": "none",
  "obligation": "The module initialises Merge_flag to false before examining the translation table."
 },
 {
  "id": "A47",
  "source": "RFC826",
  "line_start": 210,
  "line_end": 213,
  "section": "Packet Reception",
  "quote": "If the pair <protocol type, sender protocol address> is already in my translation table, update the sender hardware address field of the entry with the new information in the packet",
  "rule": "N6",
  "strength": "none",
  "obligation": "If the <protocol type, sender protocol address> pair is already in the translation table, the module overwrites that entry's hardware address with the sender hardware address from the packet."
 },
 {
  "id": "A48",
  "source": "RFC826",
  "line_start": 213,
  "line_end": 213,
  "section": "Packet Reception",
  "quote": "and set Merge_flag to true.",
  "rule": "N6",
  "strength": "none",
  "obligation": "When such an existing entry is updated, the module sets Merge_flag to true."
 },
 {
  "id": "A49",
  "source": "RFC826",
  "line_start": 214,
  "line_end": 214,
  "section": "Packet Reception",
  "quote": "?Am I the target protocol address?",
  "rule": "N2",
  "strength": "none",
  "obligation": "The module tests whether ar$tpa is its own protocol address, and proceeds only if it is."
 },
 {
  "id": "A50",
  "source": "RFC826",
  "line_start": 216,
  "line_end": 218,
  "section": "Packet Reception",
  "quote": "If Merge_flag is false, add the triplet <protocol type, sender protocol address, sender hardware address> to the translation table.",
  "rule": "N6",
  "strength": "none",
  "obligation": "When the module is the target and Merge_flag is false, it adds the <protocol type, sender protocol address, sender hardware address> triplet to the translation table."
 },
 {
  "id": "A51",
  "source": "RFC826",
  "line_start": 219,
  "line_end": 219,
  "section": "Packet Reception",
  "quote": "?Is the opcode ares_op$REQUEST?",
  "rule": "N2",
  "strength": "none",
  "obligation": "The module tests whether ar$op is ares_op$REQUEST, and generates a reply only if it is."
 },
 {
  "id": "A52",
  "source": "RFC826",
  "line_start": 219,
  "line_end": 219,
  "section": "Packet Reception",
  "quote": "(NOW look at the opcode!!)",
  "rule": "N2",
  "strength": "none",
  "obligation": "The opcode is examined only after the sender information has been merged into or added to the translation table, not before."
 },
 {
  "id": "A53",
  "source": "RFC826",
  "line_start": 221,
  "line_end": 222,
  "section": "Packet Reception",
  "quote": "Swap hardware and protocol fields, putting the local hardware and protocol addresses in the sender fields.",
  "rule": "N1",
  "strength": "none",
  "obligation": "To build the reply the module swaps the sender and target hardware and protocol fields, placing its own hardware and protocol addresses in the sender fields."
 },
 {
  "id": "A54",
  "source": "RFC826",
  "line_start": 223,
  "line_end": 223,
  "section": "Packet Reception",
  "quote": "Set the ar$op field to ares_op$REPLY",
  "rule": "N2",
  "strength": "none",
  "obligation": "In the reply the module sets ar$op to ares_op$REPLY."
 },
 {
  "id": "A55",
  "source": "RFC826",
  "line_start": 224,
  "line_end": 225,
  "section": "Packet Reception",
  "quote": "Send the packet to the (new) target hardware address",
  "rule": "N2",
  "strength": "none",
  "obligation": "The reply is sent to the new target hardware address rather than broadcast."
 },
 {
  "id": "A56",
  "source": "RFC826",
  "line_start": 224,
  "line_end": 225,
  "section": "Packet Reception",
  "quote": "on the same hardware on which the request was received",
  "rule": "N2",
  "strength": "none",
  "obligation": "The reply is sent on the same piece of hardware on which the request arrived."
 },
 {
  "id": "A57",
  "source": "RFC826",
  "line_start": 231,
  "line_end": 234,
  "section": "Packet Reception",
  "quote": "if an entry already exists for the <protocol type, sender protocol address> pair, then the new hardware address supersedes the old one",
  "rule": "N6",
  "strength": "none",
  "obligation": "A newly received sender hardware address replaces the previously stored hardware address for the same <protocol type, sender protocol address> pair."
 },
 {
  "id": "A58",
  "source": "RFC826",
  "line_start": 236,
  "line_end": 237,
  "section": "Packet Reception",
  "quote": "The ar$hrd and ar$hln fields allow this protocol and packet format to be used for non-10Mbit Ethernets.",
  "rule": "N9",
  "strength": "none",
  "obligation": "The ar$hrd and ar$hln fields parameterise the packet format so that the same protocol works on hardware other than 10Mbit Ethernet."
 },
 {
  "id": "A59",
  "source": "RFC826",
  "line_start": 238,
  "line_end": 238,
  "section": "Packet Reception",
  "quote": "<ar$hrd, ar$hln> takes on the value <1, 6>.",
  "rule": "N4",
  "strength": "none",
  "obligation": "On 10Mbit Ethernet the pair <ar$hrd, ar$hln> carries the values 1 and 6."
 },
 {
  "id": "A60",
  "source": "RFC826",
  "line_start": 239,
  "line_end": 240,
  "section": "Packet Reception",
  "quote": "other hardware networks, the ar$pro field may no longer correspond to the Ethernet type field",
  "rule": "N9",
  "strength": "may",
  "obligation": "On hardware other than Ethernet, ar$pro is permitted to hold values that are not Ethernet protocol type field values."
 },
 {
  "id": "A61",
  "source": "RFC826",
  "line_start": 240,
  "line_end": 242,
  "section": "Packet Reception",
  "quote": "but it should be associated with the protocol whose address resolution is being sought",
  "rule": "N9",
  "strength": "should",
  "obligation": "On non-Ethernet hardware the value placed in ar$pro should identify the protocol whose address resolution is being sought."
 },
 {
  "id": "A62",
  "source": "RFC826",
  "line_start": 248,
  "line_end": 248,
  "section": "Why is it done this way??",
  "quote": "Periodic broadcasting is definitely not desired.",
  "rule": "N1",
  "strength": "none",
  "obligation": "An implementation does not periodically broadcast its address resolution information; information is distributed only as it is needed."
 },
 {
  "id": "A63",
  "source": "RFC826",
  "line_start": 260,
  "line_end": 261,
  "section": "Why is it done this way??",
  "quote": "This format does not allow for more than one resolution to be done in the same packet.",
  "rule": "N3",
  "strength": "none",
  "obligation": "A single address resolution packet carries exactly one resolution; multiple resolutions may not be multiplexed into one packet."
 },
 {
  "id": "A64",
  "source": "RFC826",
  "line_start": 268,
  "line_end": 269,
  "section": "Why is it done this way??",
  "quote": "a reply has the same length as a request",
  "rule": "N3",
  "strength": "none",
  "obligation": "A reply packet is the same length as the request that provoked it."
 },
 {
  "id": "A65",
  "source": "RFC826",
  "line_start": 272,
  "line_end": 273,
  "section": "Why is it done this way??",
  "quote": "The value of the hardware field (ar$hrd) is taken from a list for this purpose.",
  "rule": "N9",
  "strength": "none",
  "obligation": "The value placed in ar$hrd is drawn from the assigned list of hardware address space values, not chosen freely."
 },
 {
  "id": "A66",
  "source": "RFC826",
  "line_start": 273,
  "line_end": 274,
  "section": "Why is it done this way??",
  "quote": "Currently the only defined value is for the 10Mbit Ethernet (ares_hrd$Ethernet = 1).",
  "rule": "N4",
  "strength": "none",
  "obligation": "The hardware address space enumeration has exactly one defined value at the time of writing, 1 for 10Mbit Ethernet."
 },
 {
  "id": "A67",
  "source": "RFC826",
  "line_start": 288,
  "line_end": 291,
  "section": "Why is it done this way??",
  "quote": "the length of a protocol address should be determined by the hardware type (found in ar$hrd) and the protocol type (found in ar$pro)",
  "rule": "N9",
  "strength": "should",
  "obligation": "Address lengths should be derivable from the hardware type and the protocol type rather than depending on the length fields."
 },
 {
  "id": "A68",
  "source": "RFC826",
  "line_start": 291,
  "line_end": 292,
  "section": "Why is it done this way??",
  "quote": "It is included for optional consistency checking, and for network monitoring and debugging",
  "rule": "N8",
  "strength": "may",
  "obligation": "An implementation is permitted, but not required, to use the length fields for consistency checking."
 },
 {
  "id": "A69",
  "source": "RFC826",
  "line_start": 294,
  "line_end": 295,
  "section": "Why is it done this way??",
  "quote": "The opcode is to determine if this is a request (which may cause a reply) or a reply to a previous request.",
  "rule": "N8",
  "strength": "may",
  "obligation": "A request may cause a reply to be generated, and a reply is a response to a previous request; the opcode is what distinguishes the two."
 },
 {
  "id": "A70",
  "source": "RFC826",
  "line_start": 298,
  "line_end": 299,
  "section": "Why is it done this way??",
  "quote": "The sender hardware address and sender protocol address are absolutely necessary.",
  "rule": "N3",
  "strength": "must",
  "obligation": "Every address resolution packet must carry the sender hardware address and the sender protocol address."
 },
 {
  "id": "A71",
  "source": "RFC826",
  "line_start": 302,
  "line_end": 304,
  "section": "Why is it done this way??",
  "quote": "The target protocol address is necessary in the request form of the packet so that a machine can determine whether or not to enter the sender information in a table or to send a reply.",
  "rule": "N3",
  "strength": "must",
  "obligation": "A request must carry the target protocol address, because the receiver decides from it whether to record the sender and whether to reply."
 },
 {
  "id": "A72",
  "source": "RFC826",
  "line_start": 304,
  "line_end": 306,
  "section": "Why is it done this way??",
  "quote": "It is not necessarily needed in the reply form if one assumes a reply is only provoked by a request.",
  "rule": "N10",
  "strength": "none",
  "obligation": "The design relies on a reply being produced only in response to a request."
 },
 {
  "id": "A73",
  "source": "RFC826",
  "line_start": 313,
  "line_end": 314,
  "section": "Why is it done this way??",
  "quote": "Its meaning in the reply form is the address of the machine making the request.",
  "rule": "N3",
  "strength": "none",
  "obligation": "In a reply, ar$tha holds the hardware address of the machine that made the request."
 },
 {
  "id": "A74",
  "source": "RFC826",
  "line_start": 320,
  "line_end": 320,
  "section": "Why is it done this way??",
  "quote": "There are no padding bytes between addresses.",
  "rule": "N3",
  "strength": "none",
  "obligation": "The address fields are packed with no padding bytes between them."
 },
 {
  "id": "A75",
  "source": "RFC826",
  "line_start": 320,
  "line_end": 322,
  "section": "Why is it done this way??",
  "quote": "The packet data should be viewed as a byte stream in which only 3 byte pairs are defined to be words (ar$hrd, ar$pro and ar$op)",
  "rule": "N3",
  "strength": "should",
  "obligation": "The packet data is a byte stream in which only ar$hrd, ar$pro and ar$op are two-byte words."
 },
 {
  "id": "A76",
  "source": "RFC826",
  "line_start": 322,
  "line_end": 323,
  "section": "Why is it done this way??",
  "quote": "which are sent most significant byte first (Ethernet/PDP-10 byte style)",
  "rule": "N3",
  "strength": "none",
  "obligation": "The three word fields ar$hrd, ar$pro and ar$op are transmitted most significant byte first."
 },
 {
  "id": "A77",
  "source": "RFC826",
  "line_start": 337,
  "line_end": 339,
  "section": "Network monitoring and debugging",
  "quote": "When a monitor receives an Address Resolution packet, it always enters the <protocol type, sender protocol address, sender hardware address> in a table.",
  "rule": "N6",
  "strength": "none",
  "obligation": "A monitor enters the sender triplet of every received address resolution packet into its table, without applying the target protocol address test."
 },
 {
  "id": "A78",
  "source": "RFC826",
  "line_start": 419,
  "line_end": 421,
  "section": "Related issue",
  "quote": "If a host moves, any connections initiated by that host will work, assuming its own address resolution table is cleared when it moves.",
  "rule": "N10",
  "strength": "none",
  "obligation": "Recovery for a host that moves relies on that host clearing its own address resolution table when it moves."
 },
 {
  "id": "A79",
  "source": "RFC826",
  "line_start": 423,
  "line_end": 424,
  "section": "Related issue",
  "quote": "48.bit Ethernet addresses are supposed to be unique and fixed for all time, so they shouldn't change.",
  "rule": "N10",
  "strength": "may",
  "obligation": "The protocol relies on 48-bit Ethernet addresses being unique and never changing."
 },
 {
  "id": "A80",
  "source": "RFC826",
  "line_start": 427,
  "line_end": 430,
  "section": "Related issue",
  "quote": "there is always the danger of incorrect routing information accidentally getting transmitted through hardware or software error; it should not be allowed to persist forever",
  "rule": "N6",
  "strength": "should",
  "obligation": "Incorrect information in the translation table should not be allowed to persist indefinitely."
 },
 {
  "id": "A81",
  "source": "RFC826",
  "line_start": 430,
  "line_end": 432,
  "section": "Related issue",
  "quote": "Perhaps failure to initiate a connection should inform the Address Resolution module to delete the information on the basis that the host is not reachable",
  "rule": "N6",
  "strength": "should",
  "obligation": "A failure to initiate a connection should cause the corresponding translation table entry to be deleted."
 },
 {
  "id": "A82",
  "source": "RFC826",
  "line_start": 433,
  "line_end": 436,
  "section": "Related issue",
  "quote": "Or perhaps receiving of a packet from a host should reset a timeout in the address resolution entry used for transmitting packets to that host",
  "rule": "N6",
  "strength": "should",
  "obligation": "Receiving a packet from a host should reset the timeout on the translation table entry used to transmit to that host."
 },
 {
  "id": "A83",
  "source": "RFC826",
  "line_start": 436,
  "line_end": 437,
  "section": "Related issue",
  "quote": "if no packets are received from a host for a suitable length of time, the address resolution entry is forgotten",
  "rule": "N6",
  "strength": "none",
  "obligation": "A translation table entry is discarded when no packet has been received from that host for a suitable length of time."
 },
 {
  "id": "A84",
  "source": "RFC826",
  "line_start": 445,
  "line_end": 447,
  "section": "Related issue",
  "quote": "on a perfect Ethernet where a broadcast REQUEST reaches all stations on the cable, each station will be get the new hardware address",
  "rule": "N6",
  "strength": "none",
  "obligation": "A broadcast request that reaches every station causes every station holding an entry for the sender to take up the new hardware address."
 },
 {
  "id": "A85",
  "source": "RFC826",
  "line_start": 449,
  "line_end": 450,
  "section": "Related issue",
  "quote": "Another alternative is to have a daemon perform the timeouts.  After a suitable time, the daemon considers removing an entry.",
  "rule": "N6",
  "strength": "none",
  "obligation": "A daemon may perform table timeouts, considering an entry for removal after a suitable time has passed."
 },
 {
  "id": "A86",
  "source": "RFC826",
  "line_start": 451,
  "line_end": 453,
  "section": "Related issue",
  "quote": "It first sends ... an address resolution packet with opcode REQUEST directly to the Ethernet address in the table.",
  "rule": "N1",
  "strength": "none",
  "obligation": "Before removing an entry the daemon sends a REQUEST directly (not broadcast) to the Ethernet address held in that entry."
 },
 {
  "id": "A87",
  "source": "RFC826",
  "line_start": 451,
  "line_end": 452,
  "section": "Related issue",
  "quote": "(with a small number of retransmissions if needed)",
  "rule": "N1",
  "strength": "none",
  "obligation": "The daemon retransmits that probe request a small number of times if the first attempt draws no answer."
 },
 {
  "id": "A88",
  "source": "RFC826",
  "line_start": 453,
  "line_end": 454,
  "section": "Related issue",
  "quote": "If a REPLY is not seen in a short amount of time, the entry is deleted.",
  "rule": "N6",
  "strength": "none",
  "obligation": "If no reply to the probe arrives within a short time, the daemon deletes the table entry."
 },
 {
  "id": "A89",
  "source": "RFC826",
  "line_start": 459,
  "line_end": 460,
  "section": "Related issue",
  "quote": "Since hosts don't transmit information about anyone other than themselves",
  "rule": "N1",
  "strength": "none",
  "obligation": "A host transmits address resolution information only about itself, never about other hosts."
 },
 {
  "id": "A90",
  "source": "RFC826",
  "line_start": 464,
  "line_end": 466,
  "section": "Related issue",
  "quote": "Perhaps manually resetting (or clearing) the address mapping table will suffice.",
  "rule": "N6",
  "strength": "may",
  "obligation": "Stale mappings may be cleared by manually resetting the address mapping table."
 }
]

## The pinned RFC text

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
