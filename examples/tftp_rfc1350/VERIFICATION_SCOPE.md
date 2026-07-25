# TFTP (RFC 1350 + RFC 1123 §4.2.3.1): verification scope

> **Status:** Phase 0 output of the RFC-SWARM track, 2026-07-24. This is the S0/S1 artifact of
> the spec-from-RFC pipeline: the clause inventory and its dispositions, fixed before any
> contract is authored and before any agent runs.
> Roadmap: [`docs/design/rfc-swarm-roadmap-proposal.md`](../../docs/design/rfc-swarm-roadmap-proposal.md).
> Pre-registration: [`experiments/rfc-swarm/PRE-REGISTRATION.md`](../../experiments/rfc-swarm/PRE-REGISTRATION.md).

**The claim this file supports** is not "the RFC is verified". It is the disposition ledger:
*every normative clause of the target is dispositioned, with the protocol core verified
body-faithfully and every exclusion recorded with a cited reason.* The Encoded fraction is
stated first, in §4 below, because that is the number a reader should judge.

---

## 1. Source provenance

Extraction read verbatim RFC text only, pinned by hash so the inventory can be re-derived:

| Source | SHA-256 |
|---|---|
| RFC 1350 (TFTP Revision 2, July 1992), 618 lines, `https://www.rfc-editor.org/rfc/rfc1350.txt` | `39c9534e5fa6fecd3ac083ffd6256c2cc9a58f9f1058cb2e472d1782040231f9` |
| RFC 1123 (October 1989), 5782 lines, `https://www.rfc-editor.org/rfc/rfc1123.txt` | `3d019cc4777d1ead76c212711d56768bde9361312cd209846b62d2e41dd0301d` |
| RFC 1123 §4.2 excerpt (lines 2544-2760) | `f276196f9bb7885770014a64e316fcf84445908092999cd423b0bd5ccdf87bcf` |

Line numbers in the inventory table refer to these files. RFC 1123 rows cite lines within the
§4.2 excerpt.

## 2. The normativity rubric

RFC 1350 is dated July 1992; RFC 2119 (the MUST/SHOULD/MAY convention) is March 1997. The base
RFC therefore has no requirement-keyword discipline, and every normativity judgment on it is
interpretive. This rubric was written **before** extraction and applied uniformly by both
extractors; it is reproduced here because a denominator produced by an unstated rule is not
auditable.

**Normative (counts in the denominator).**

- **N1** imperative protocol behavior: what an implementation does or sends on an event.
- **N2** packet-format definition: field layout, widths, order, terminators, opcode values,
  admissible ranges.
- **N3** explicit lowercase must / should / may (1992 prose uses lowercase; the strength word is
  recorded per row).
- **N4** state-machine transition: what is sent or expected in response to a received packet,
  including initiation and termination.
- **N5** error and exception behavior: when an ERROR packet is sent, what each code means.

**Non-normative (recorded, excluded from the denominator).**

- **X1** motivation, rationale, commentary (including RFC 1123 DISCUSSION blocks).
- **X2** examples and illustrative traces.
- **X3** historical and mail-mode text.
- **X4** document metadata: status, summary, acknowledgements, references, headers, section
  titles.
- **X5** statements about another protocol's behavior not imposed on the implementation.

**Tie-breaks.** (1) One obligation per row; a sentence carrying two separable obligations
splits. (2) A sentence describing what can happen in the world is X1; one granting the
implementer latitude is N3. (3) A definition is N2/N4 when an implementation could violate it,
X4 when it only names a thing. (4) Where RFC 1350 and RFC 1123 conflict, RFC 1123 governs and
the conflict is recorded. (5) **When in doubt, mark normative.** An over-inclusive denominator
is conservative: it can only lower the Encoded fraction, never inflate it.

For RFC 1123, which states its own uppercase convention in its introduction, MUST / SHOULD / MAY
are read at face value.

## 3. How the inventory was built, and how complete it is

A single audited pass cannot answer "who checked that the inventory covers every normative
clause". So the census was performed **twice, independently and blind**, by two agents reading
the same pinned bytes under the same rubric, and reconciled mechanically by line-span overlap.

| Statistic | Value |
|---|---|
| Extractor A rows / Extractor B rows | 119 / 125 |
| Line-coverage Jaccard, RFC 1350 | **0.866** |
| Line-coverage Jaccard, RFC 1123 §4.2 | **0.725** |
| Rows matched 1:1 | 43 |
| Rows differing only in granularity | 64 |
| Genuine coverage disagreements | **11** (1 A-only, 10 B-only) |
| Rule agreement (N1-N5) on 1:1 matched rows | 95.4% raw, **Cohen's kappa 0.938** |
| Canonical inventory after adjudication | **124 rows** |

The two extractions agree closely on what the RFC requires. The dominant difference is
granularity, how finely a sentence splits into rows, not coverage.

**Adjudication of the 11 disagreements** (extraction A is the granularity spine):

- **Adopted into the canonical inventory (6).** The mail-mode recipient-form clause, which
  carries an explicit lowercase requirement word even though mail mode is deprecated (tie-break
  5, and it dispositions out below); the two-complementary-roles definition; the
  duplicate-request rejection rule; the source-port-is-the-TID rule; the datagram-checksum
  clause; and the extensions-are-optional clause.
- **Rejected (5).** RFC 1123 §4.2.4 requirements-summary rows that restate prose rows already
  counted (the Sorcerer's Apprentice fix, mail mode, the adaptive timeout, access control,
  broadcast requests). Counting a summary restatement beside the prose it summarizes would
  double-count the denominator; they are X4 metadata. The three summary rows that appear
  *nowhere* in the prose (netascii/octet support, extensions) are retained as real rows.

The roadmap estimated 20-30 normative clauses; the census found 124. The estimate counted
protocol-core concepts, while the rubric counts obligations (one row per error code, per format
constraint) and its conservative tie-break inflates. A larger denominator can only lower the
Encoded fraction, so the gap is in the safe direction.

---

## 4. Disposition summary

**Encoded: 46 of 124 rows (37.1%).** That is the first number, per the claim discipline.

| Disposition | Rows | Share |
|---|---:|---:|
| Encoded | 46 | 37.1% |
| Deployment-modeled | 20 | 16.1% |
| Vectored | 5 | 4.0% |
| Dispositioned out | 53 | 42.7% |
| **Total** | **124** | 100% |

By clause class:

| Class | Rows |
|---|---:|
| C1 state transition / protocol behavior | 29 |
| C2 arithmetic invariant | 10 |
| C3 length or packet format | 26 |
| C4 opaque primitive | 14 |
| C5 test vector | 5 |
| C6 timing, liveness, transport, trace-level | 40 |

## 5. Coverage of verifiable subject matter, and the STOP evaluation

The original quantitative STOP was a ratio ceiling (no more than ~30% of rows dispositioned out). It fired at 46.8%, and was then **retired by Amendment 1** as a defective instrument. The reason: every row in class C6 (timing, liveness, transport, trace-level) is excluded by the definition of the class, and C6 was 45/124 = 36.3% of the census as first classified (40/124 = 32.3% after Amendment 1 promoted the source-TID rows into C1). Either figure exceeds the ceiling on its own, so the threshold was breached by **class assignment alone**, before any scoping judgment was made, and the C1-C6 taxonomy predates the selection of RFC 1350. A ratio of that shape measures the genre composition of the document rather than the reach of the verifier: every complete protocol specification adds denominator in transport, timing, and deployment prose that can never add numerator, so no such RFC could pass. Full argument: `experiments/rfc-swarm/PRE-REGISTRATION.md` Appendix A.

**The instrument in force** is three conditions: coverage measured over verifiable subject matter, the characteristic-core invariant (unchanged), and a closed barrier list.

| Condition | Requirement | Measured | Verdict |
|---|---|---|---|
| Coverage of verifiable subject matter (C1+C2+C3) | reported, not thresholded | **62/65 carried = 95.4%** | reported |
| Characteristic-core rows dispositioned out | zero | none | **PASS** |
| Exclusions outside the closed barrier list | zero | none | **PASS** |

**All conditions pass. The target stands on the corrected instrument.**

For completeness, the raw ledger ratios: Encoded 46/124 = 37.1%, dispositioned out 53/124 = 42.7%. These are reported, not graded: the denominator counts obligations of every genre, including 40 rows about timing and transport that no body-level verifier of any language carries.

### The closed barrier list

Every exclusion cites exactly one barrier below. An exclusion that fits none of them is a STOP condition, which is what replaces the retired ratio ceiling.

| Barrier | Rows | What it covers |
|---|---:|---|
| B1 timing / liveness | 9 | Obligations about when to act, how long to wait, or what must eventually happen. Needs a timing model and reasoning over executions, not over one transition. |
| B2 transport binding | 22 | UDP port allocation and datagram mechanics beyond the modeled TID pair. Below the decoded-packet boundary this scope draws. |
| B3 trace-level property | 3 | Properties quantifying over all executions rather than a single transition, including the no-doubling property the duplicate-ACK fix secures. |
| B4 opaque transform | 3 | netascii character-set translation: an uninterpreted transform on payload content. |
| B5 string structure | 6 | NUL-terminated variable-length wire fields; splitting them is string structure, outside the decidable fragment by design. |
| B6 superseded / deprecated | 5 | Mail mode, obsolete per RFC 1350 itself and SHOULD NOT be supported per RFC 1123 4.2.2.1. |
| B7 true by construction | 1 | The model admits no constructor for the forbidden thing, so no mutant can exercise the row and it carries no verification evidence. |
| B8 outside any tool | 4 | Deployment environment and procurement guidance: no protocol transition exists to verify. |

## 6. The characteristic core

Fixed before the disposition pass, as the clauses that make TFTP what it is: the lock-step transfer discipline, block-number sequencing including the initial block number, the 512-byte short-block termination rule, the error latch, and the RFC 1123 duplicate-ACK rule. **15 rows** carry it. No row here may disposition out at any later phase; if one does, the demonstration is re-scoped rather than re-graded.

| Row | Source | Lines | Disposition | Obligation |
|---|---|---|---|---|
| T012 | RFC 1350 | 93-94 | Encoded | The sender must receive an ACK for a DATA packet before sending the next DATA packet (lock-step). |
| T013 | RFC 1350 | 94-95 | Encoded | A DATA packet with fewer than 512 data bytes signals the end of the transfer. |
| T016 | RFC 1350 | 105-105 | Encoded | An error terminates the connection except in the one case singled out below. |
| T032 | RFC 1350 | 187-188 | Encoded | An ACK carries the block number of the DATA packet it acknowledges. |
| T033 | RFC 1350 | 188-190 | Encoded | DATA block numbers start at one and are consecutive. |
| T034 | RFC 1350 | 190-192 | Encoded | The ACK that positively answers a WRQ carries block number zero. |
| T045 | RFC 1350 | 237-238 | Encoded | After the WRQ/ACK exchange the writer sends its first DATA packet with block number 1. |
| T063 | RFC 1350 | 357-359 | Encoded | DATA block numbers start at one and increment by one per new block. |
| T065 | RFC 1350 | 361-362 | Encoded | A full 512-byte data field means the transfer continues. |
| T066 | RFC 1350 | 362-363 | Encoded | A data field of 0 to 511 bytes signals the end of the transfer. |
| T067 | RFC 1350 | 366-367 | Encoded | Every packet except duplicate ACKs and termination packets is acknowledged, absent a timeout. |
| T073 | RFC 1350 | 382-384 | Encoded | An ACK's block number equals the block number of the DATA packet it acknowledges. |
| T074 | RFC 1350 | 384-385 | Encoded | The ACK answering a WRQ carries block number zero. |
| T081 | RFC 1350 | 418-419 | Encoded | A DATA packet with 0 to 511 data bytes marks the end of the transfer. |
| T113 | RFC 1123 | 46-60 | Encoded | The DATA sender must never retransmit the current DATA packet in response to a duplicate ACK; overrides RFC 1350's may-retransmit-on-duplicate rule. |

## 7. Full inventory

All 124 canonical normative rows, each with exactly one disposition. `core` marks membership of the characteristic core. Rows adopted from the second extraction during adjudication keep their original identifiers in the provenance record.

| Row | Src | Lines | Rule | Class | Disposition | Core | Obligation | Reason |
|---|---|---|---|---|---|---|---|---|
| T001 | 1350 | 64-65 | N3 | C6 | Dispositioned out |  | An implementation is permitted to run TFTP over datagram protocols other than UDP. | Choice of underlying datagram protocol is transport mechanics, outside the decidable fragment. |
| T002 | 1350 | 67-69 | N1 | C1 | Dispositioned out |  | An implementation provides only file read and write operations, with no directory listing and no user authentication. | True by construction: the request ADT has only RRQ/WRQ constructors, so no mutant can exercise a directory or authentication operation and the row carries no verific |
| T003 | 1350 | 70-71 | N2 | C3 | Deployment-modeled |  | File data is carried as 8-bit bytes. | Model: file data is a fixed bytes[512] buffer plus an int length; the 8-bit width of an individual byte is not represented. |
| T004 | 1350 | 73-76 | N2 | C4 | Dispositioned out |  | The netascii transfer mode is 8-bit ASCII per USAS X3.4-1968 with the Telnet Protocol Specification modifications. | Defining netascii by reference to USAS X3.4 and Telnet is an opaque character-set transform with no arithmetic or enum content. |
| T005 | 1350 | 78-79 | N2 | C4 | Deployment-modeled |  | The octet transfer mode carries raw 8-bit bytes and replaces the older "binary" mode name. | Model: octet mode is the string literal tag "octet" over an untransformed bytes[512]+len payload; the raw-byte claim is the identity of that buffer. |
| T006 | 1350 | 80-81 | N3 | C4 | Dispositioned out |  | An implementation must not implement or use the mail transfer mode. | RFC 1350 states "the mail mode is obsolete and should not be implemented or used" and RFC 1123 4.2.2.1 forbids it, so no mail constructor exists to verify. |
| T007 | 1350 | 82-82 | N3 | C4 | Dispositioned out |  | An implementation may define additional transfer modes by bilateral agreement with a cooperating peer. | Bilaterally defined extra modes are an open-ended set of undefined mode strings; string structure and unbounded extension put it outside the fragment. |
| T008 | 1350 | 84-85 | N3 | C6 | Dispositioned out |  | An implementation must also apply the TFTP directives of RFC 1123 section 4.2. | A directive to consult another document constrains the implementation corpus, not any single transition (trace-level). |
| T009 | 1350 | 89-90 | N4 | C1 | Encoded |  | Every transfer is initiated by an RRQ or WRQ, which simultaneously requests the connection. | Contract on the step function: from Idle only an RRQ or WRQ input yields a connected state. |
| T010 | 1350 | 90-92 | N4 | C1 | Encoded |  | On granting a request the server opens the connection and the file is transferred in fixed-length 512-byte blocks. | Contract on the grant transition: Idle plus a granted request yields Transferring, with block length invariant len <= 512. |
| T011 | 1350 | 92-93 | N2 | C3 | Encoded |  | A DATA packet carries exactly one block of data. | Contract on the send step: the DATA constructor carries one block number and one buffer, and the step advances the block index by exactly one. |
| T012 | 1350 | 93-94 | N3 | C1 | Encoded | yes | The sender must receive an ACK for a DATA packet before sending the next DATA packet (lock-step). | Contract precondition on the sender step: DATA n+1 is emitted only from a state whose last-acked block equals n. |
| T013 | 1350 | 94-95 | N4 | C3 | Encoded | yes | A DATA packet with fewer than 512 data bytes signals the end of the transfer. | Contract on the receive step: len < 512 implies the post-state is Terminating. |
| T014 | 1350 | 95-98 | N4 | C6 | Dispositioned out |  | On timeout a party may retransmit its last packet, which causes the peer to retransmit the lost packet; constrained by RFC 1123 4.2.3.1. | Timeout detection and retransmission scheduling are timing properties with no single-transition encoding. |
| T015 | 1350 | 98-100 | N1 | C6 | Dispositioned out |  | An implementation need buffer only one outstanding packet for retransmission. | One-packet retransmission buffering is a claim about the retransmission machinery, which is timing-driven and not modeled. |
| T016 | 1350 | 105-105 | N5 | C1 | Encoded | yes | An error terminates the connection except in the one case singled out below. | Error latch: contract states any state plus an ERROR input yields Terminated, and Terminated is absorbing. |
| T017 | 1350 | 105-106 | N5 | C1 | Encoded |  | An implementation signals an error by sending an ERROR packet. | Contract on the error transition: its output packet is the ERROR constructor. |
| T018 | 1350 | 106-107 | N5 | C1 | Encoded |  | An ERROR packet is neither acknowledged nor retransmitted. | Contract: the ERROR transition emits no acknowledgment and lands in the absorbing Terminated state, so no transition re-emits it. |
| T019 | 1350 | 107-108 | N3 | C1 | Deployment-modeled |  | A server or user may terminate immediately after sending an ERROR packet. | Model: the permission is resolved deterministically, with the post-state after emitting ERROR always Terminated. |
| T020 | 1350 | 109-110 | N5 | C6 | Dispositioned out |  | An implementation uses timeouts to detect a peer termination whose ERROR packet was lost. | Detecting a peer termination whose ERROR was lost is a timeout property; timing is outside the fragment. |
| T021 | 1350 | 110-124 | N5 | C1 | Deployment-modeled |  | An implementation raises an error on unsatisfiable request, unexplainable/malformed packet, or loss of a needed resource. | Model: the three error causes enter as input events (request-denied flag, unexplainable packet, resource-lost flag) feeding the ERROR transition. |
| T022 | 1350 | 126-127 | N5 | C1 | Encoded |  | An incorrect source port on a received packet is the only error that does not terminate the connection. | Modeled TID pair (Amendment 1). A wrong-source-TID packet is the one error that leaves the transfer state unchanged; expressible as a transition that does not enter  |
| T023 | 1350 | 128-128 | N5 | C1 | Encoded |  | On receiving a packet with an incorrect source port, an ERROR packet is sent to that packet's originator. | Modeled TID pair (Amendment 1). The transition emits an ERROR addressed to the offending originator; decidable over the modeled TID pair. |
| T024 | 1350 | 142-146 | N2 | C6 | Dispositioned out |  | A transmitted packet places the TFTP header after the local medium, Internet and Datagram headers, followed by the TFTP payload. | Ordering of local medium, Internet and Datagram headers is lower-layer encapsulation, below the decoded-packet model. |
| T025 | 1350 | 147-150 | N2 | C6 | Dispositioned out |  | TFTP uses the datagram source/destination port fields, and the datagram length field reflects the TFTP packet size. | Datagram source/destination port fields and the datagram length field are transport mechanics. |
| T026 | 1350 | 150-152 | N1 | C6 | Dispositioned out |  | An implementation passes its TIDs to the datagram layer to be used as port numbers. | Passing TIDs to the datagram layer as ports is TID allocation and transport plumbing. |
| T027 | 1350 | 152-152 | N2 | C2 | Encoded |  | A TID must be an integer in the range 0 to 65535. | Modeled TID pair (Amendment 1). TID range 0..65535 is a refinement on the modeled TID pair; pure QF-LIA. |
| T028 | 1350 | 155-156 | N2 | C3 | Deployment-modeled |  | Every TFTP packet begins with a 2-byte opcode field identifying its type. | Model: the opcode field is the constructor tag of the decoded packet ADT; the 2-byte field width is not represented. |
| T029 | 1350 | 175-179 | N2 | C6 | Dispositioned out |  | Header order on the wire is local medium, Internet, Datagram, then TFTP. | Figure 3-1 fixes lower-layer header order on the wire, which is transport encapsulation. |
| T030 | 1350 | 184-186 | N4 | C1 | Encoded |  | A client establishes a transfer by sending WRQ to write to the remote file system or RRQ to read from it. | Contract on the initiating step: the request constructor (RRQ or WRQ) fixes the transfer direction in the post-state. |
| T031 | 1350 | 186-187 | N4 | C1 | Encoded |  | The positive reply is an ACK for a write request and the first DATA packet for a read request. | Contract on the reply step: WRQ yields an ACK output and RRQ yields a DATA output. |
| T032 | 1350 | 187-188 | N2 | C2 | Encoded | yes | An ACK carries the block number of the DATA packet it acknowledges. | Contract on the ack step: the ACK block number equals the block number of the DATA being acknowledged (int equality). |
| T033 | 1350 | 188-190 | N2 | C2 | Encoded | yes | DATA block numbers start at one and are consecutive. | Contract on the sender spine: first block equals 1 and each successor block equals predecessor plus 1. |
| T034 | 1350 | 190-192 | N4 | C2 | Encoded | yes | The ACK that positively answers a WRQ carries block number zero. | Contract on the WRQ reply step: the acknowledging ACK carries block number 0, the initial block number of a write. |
| T035 | 1350 | 194-195 | N5 | C1 | Encoded |  | An ERROR packet in reply to a request means the request was denied. | Contract on the reply step: an ERROR reply to a request yields the Denied post-state rather than a transfer state. |
| T036 | 1350 | 197-199 | N1 | C6 | Dispositioned out |  | Each endpoint chooses one TID and keeps it for the whole connection. | Choosing and holding a TID is transport identity allocation, outside the fragment. |
| T037 | 1350 | 199-201 | N3 | C6 | Dispositioned out |  | An implementation should choose TIDs randomly so immediate reuse is improbable. | Random TID selection is transport allocation plus a probabilistic property, neither of which the fragment expresses. |
| T038 | 1350 | 201-203 | N2 | C6 | Dispositioned out |  | Every packet carries a source TID and a destination TID identifying the two connection endpoints. | Source and destination TIDs on every packet are transport identity, not part of the decoded packet model. |
| T039 | 1350 | 203-204 | N1 | C6 | Dispositioned out |  | An implementation maps the source and destination TIDs onto the datagram source and destination ports. | Mapping TIDs onto UDP source and destination ports is transport plumbing. |
| T040 | 1350 | 205-206 | N1 | C6 | Dispositioned out |  | The requesting host selects its own source TID by the random-choice rule. | Selection of the requestor's source TID is transport allocation. |
| T041 | 1350 | 206-207 | N2 | C6 | Dispositioned out |  | The initial RRQ/WRQ is addressed to destination TID 69 on the server. | Addressing the initial request to TID 69 names a UDP port, which is transport mechanics. |
| T042 | 1350 | 207-209 | N4 | C6 | Dispositioned out |  | The server answers the request from a newly chosen source TID rather than from TID 69. | Answering from a freshly chosen server TID is transport allocation. |
| T043 | 1350 | 209-210 | N4 | C6 | Dispositioned out |  | The server's response is addressed to the requestor's source TID as destination TID. | Addressing the response to the requestor's TID is transport addressing. |
| T044 | 1350 | 210-210 | N1 | C6 | Dispositioned out |  | Both endpoints use the agreed TID pair for the rest of the transfer. | Holding the agreed TID pair for the transfer is transport identity state, not modeled. |
| T045 | 1350 | 237-238 | N4 | C2 | Encoded | yes | After the WRQ/ACK exchange the writer sends its first DATA packet with block number 1. | Contract on the post-WRQ sender step: the first DATA emitted carries block number 1. |
| T046 | 1350 | 239-241 | N3 | C1 | Encoded |  | On every received packet a host should check that the source TID matches the TID agreed during connection setup. | Modeled TID pair (Amendment 1). Source-TID equality against the connection's agreed TID is a guard over modeled state. |
| T047 | 1350 | 241-242 | N3 | C1 | Encoded |  | A packet whose source TID does not match the connection must be discarded. | Modeled TID pair (Amendment 1). A non-matching source TID yields no state change and no data output; the injection-rejection crux. |
| T048 | 1350 | 242-244 | N5 | C1 | Encoded |  | An ERROR packet is sent to the originator of a wrong-TID packet without disturbing the ongoing transfer. | Modeled TID pair (Amendment 1). The wrong-TID ERROR leaves the ongoing transfer undisturbed; state-preservation is the discriminative part. |
| T049 | 1350 | 263-271 | N2 | C3 | Encoded |  | Exactly five packet types exist with opcodes 1=RRQ, 2=WRQ, 3=DATA, 4=ACK, 5=ERROR. | Contract on opcodeOf: the packet ADT has exactly five constructors mapped to the pinned ints 1 through 5. |
| T050 | 1350 | 273-274 | N2 | C3 | Encoded |  | Each packet's TFTP header carries the opcode of that packet's type. | Contract: opcodeOf is total over the packet ADT and returns that packet's own opcode constant. |
| T051 | 1350 | 287-292 | N2 | C3 | Deployment-modeled |  | An RRQ/WRQ packet is a 2-byte opcode, a Filename string, a zero byte, a Mode string, and a zero byte in that order. | Model: RRQ/WRQ is a decoded record (mode enum plus a filename handle); the NUL-terminated wire layout stays in the decoder. |
| T052 | 1350 | 295-296 | N2 | C3 | Deployment-modeled |  | RRQ uses opcode 1 and WRQ opcode 2, both with the Figure 5-1 layout. | Model: opcodes 1 and 2 are pinned on the ADT tags while the Figure 5-1 field layout is carried by the decoded request record. |
| T053 | 1350 | 296-297 | N2 | C3 | Dispositioned out |  | The Filename field is netascii bytes terminated by a single zero byte. | A zero-byte-terminated filename is string structure (NUL-terminated field splitting), which the fragment cannot express. |
| T054 | 1350 | 297-300 | N2 | C3 | Deployment-modeled |  | The Mode field is a netascii string equal to netascii, octet or mail, compared case-insensitively. | Model: mode is a decoded enum with the "octet" literal pinned; case-insensitive string matching stays in the decoder. |
| T055 | 1350 | 300-302 | N3 | C4 | Dispositioned out |  | A receiver in netascii mode must convert incoming netascii into its local text format. | Translating netascii into a local text format is an opaque character-set transform. |
| T056 | 1350 | 302-304 | N2 | C4 | Deployment-modeled |  | Octet mode transfers the file in the sending machine's native 8-bit format without translation. | Model: octet mode is the identity on the bytes[512]+len payload, with no transform function applied. |
| T057 | 1350 | 307-308 | N3 | C6 | Dispositioned out |  | An octet-mode round trip must return a byte-identical file. | A byte-identical round trip quantifies over a whole variable-length file across every block, which is trace-level. |
| T058 | 1350 | 309-310 | N3 | C4 | Dispositioned out |  | In mail mode the Filename field carries a recipient name and the transfer must start with a WRQ; superseded by the mail-mode deprecation and RFC 1123 4.2.2.1. | Mail mode is obsolete per RFC 1350 and SHOULD NOT be supported per RFC 1123 4.2.2.1, so no mail transfer exists in the model. |
| T059 | 1350 | 311-312 | N3 | C4 | Dispositioned out |  | A mail-mode recipient string should be username or username@hostname; superseded by the mail-mode deprecation. | The recipient form username@hostname is both mail mode (deprecated) and string structure. |
| T060 | 1350 | 334-343 | N3 | C4 | Dispositioned out |  | An implementation may define non-standard modes only by agreement between cooperating hosts and with care. | Privately agreed extra modes are an open set of undefined mode strings with no fixed obligation to verify. |
| T061 | 1350 | 348-353 | N2 | C3 | Deployment-modeled |  | A DATA packet is a 2-byte opcode, a 2-byte block number, then n bytes of data. | Model: DATA is (block:int, buf:bytes[512], len:int); the 2-byte field widths and the variable n data bytes stay in the decoder. |
| T062 | 1350 | 356-357 | N2 | C3 | Encoded |  | DATA uses opcode 3 and carries a block number field and a data field. | Contract: opcodeOf(DATA) = 3 and the DATA constructor exposes a block-number field and a data field. |
| T063 | 1350 | 357-359 | N2 | C2 | Encoded | yes | DATA block numbers start at one and increment by one per new block. | Contract on the sender spine: next block equals current block plus 1, with the first equal to 1. |
| T064 | 1350 | 361-361 | N2 | C3 | Encoded |  | The DATA data field length is between 0 and 512 bytes inclusive. | Contract on the DATA record: 0 <= len <= 512, checked against the fixed bytes[512] buffer bound. |
| T065 | 1350 | 361-362 | N4 | C3 | Encoded | yes | A full 512-byte data field means the transfer continues. | Contract on the receive step: len = 512 implies the post-state is still Transferring. |
| T066 | 1350 | 362-363 | N4 | C3 | Encoded | yes | A data field of 0 to 511 bytes signals the end of the transfer. | Contract on the receive step: 0 <= len <= 511 implies the post-state is Terminating. |
| T067 | 1350 | 366-367 | N4 | C1 | Encoded | yes | Every packet except duplicate ACKs and termination packets is acknowledged, absent a timeout. | Contract on the step function: every non-duplicate, non-terminal input packet produces a response packet; the timeout escape only weakens this, so the unconditional  |
| T068 | 1350 | 367-369 | N4 | C1 | Encoded |  | Transmitting the next DATA packet implicitly acknowledges the first ACK of the previous DATA packet. | Contract on the product-automaton spine: emitting DATA n+1 advances the joint state past ACK n, which is the implicit acknowledgment. |
| T069 | 1350 | 369-370 | N4 | C1 | Encoded |  | A WRQ or DATA packet is answered by an ACK or an ERROR packet. | Contract on the response step: the output constructor for a WRQ or DATA input is ACK or ERROR and nothing else. |
| T070 | 1350 | 370-381 | N4 | C1 | Encoded |  | An RRQ or ACK packet is answered by a DATA or an ERROR packet. | Contract on the response step: the output constructor for an RRQ or ACK input is DATA or ERROR and nothing else. |
| T071 | 1350 | 373-378 | N2 | C3 | Deployment-modeled |  | An ACK packet is exactly a 2-byte opcode followed by a 2-byte block number. | Model: ACK is a constructor carrying one int block field; the 2-byte opcode and block widths stay in the decoder. |
| T072 | 1350 | 381-382 | N2 | C3 | Encoded |  | ACK packets use opcode 4. | Contract: opcodeOf(ACK) = 4. |
| T073 | 1350 | 382-384 | N2 | C2 | Encoded | yes | An ACK's block number equals the block number of the DATA packet it acknowledges. | Contract on the receiver step: the emitted ACK block number equals the received DATA block number (int equality). |
| T074 | 1350 | 384-385 | N4 | C2 | Encoded | yes | The ACK answering a WRQ carries block number zero. | Contract: the ACK emitted in reply to a WRQ has block number 0. |
| T075 | 1350 | 399-404 | N2 | C3 | Deployment-modeled |  | An ERROR packet is a 2-byte opcode, a 2-byte error code, an ErrMsg string and a terminating zero byte. | Model: ERROR is a constructor carrying an int error code; the ErrMsg string and its zero terminator are not represented. |
| T076 | 1350 | 407-407 | N2 | C3 | Deployment-modeled |  | ERROR packets use opcode 5 with the Figure 5-4 layout. | Model: opcode 5 is pinned on the ERROR tag while the Figure 5-4 layout, including the ErrMsg string, is carried by the decoded record. |
| T077 | 1350 | 407-408 | N5 | C1 | Encoded |  | An ERROR packet is an admissible response to any packet type. | Contract: the step function is defined on an ERROR input from every state, yielding Terminated. |
| T078 | 1350 | 409-410 | N2 | C2 | Encoded |  | The ErrorCode field is an integer selected from the defined error-code table. | Contract: the error code is an enum whose constants are pinned to the defined ints, so no other value is emitted. |
| T079 | 1350 | 412-413 | N3 | C4 | Dispositioned out |  | The ErrMsg field should be netascii text meant for humans. | A human-readable netascii message is an opaque character-set transform with no functional property. |
| T080 | 1350 | 413-414 | N2 | C3 | Dispositioned out |  | The ErrMsg string, like every TFTP string, is terminated by a zero byte. | Zero-byte termination of ErrMsg is string structure, which the fragment cannot express. |
| T081 | 1350 | 418-419 | N4 | C3 | Encoded | yes | A DATA packet with 0 to 511 data bytes marks the end of the transfer. | Contract on the terminating step: 0 <= len <= 511 marks the final DATA; the datagram length < 516 restatement is transport arithmetic and not carried. |
| T082 | 1350 | 420-420 | N4 | C1 | Encoded |  | The final DATA packet is acknowledged with an ACK exactly like any other DATA packet. | Contract: the same ACK transition applies at the terminal block, so the final DATA is acknowledged like any other. |
| T083 | 1350 | 421-422 | N3 | C1 | Deployment-modeled |  | The acknowledger may close its side of the connection immediately after sending the final ACK. | Model: the permission is resolved deterministically, with the acknowledger moving to Done on emitting the final ACK; dallying is not modeled. |
| T084 | 1350 | 422-425 | N1 | C6 | Dispositioned out |  | The acknowledger should dally after the final ACK so it can retransmit that ACK if it is lost. | Dallying is a wait-before-terminating rule, which is timing. |
| T085 | 1350 | 425-426 | N4 | C6 | Dispositioned out |  | A repeated final DATA packet tells the dallying acknowledger its final ACK was lost and must be resent. | Inferring a lost ACK from a repeated final DATA depends on packet loss and retransmission timing. |
| T086 | 1350 | 427-428 | N3 | C6 | Dispositioned out |  | The sender of the last DATA packet must retransmit it until acknowledged or until it times out. | Retransmitting until acknowledged or timed out is liveness plus timing. |
| T087 | 1350 | 428-429 | N4 | C1 | Encoded |  | Receiving the ACK for the final DATA packet means the transfer completed successfully. | Contract on the sender step: receiving the ACK whose block equals the final block yields the Completed state. |
| T088 | 1350 | 433-434 | N4 | C6 | Dispositioned out |  | After the sender's final timeout the connection is considered closed regardless of outcome. | Closure after a final timeout is a timing property. |
| T089 | 1350 | 438-439 | N5 | C1 | Encoded |  | An implementation sends an ERROR packet when a request cannot be granted or an error occurs mid-transfer. | Contract on the error transition: a denied request or a detected mid-transfer fault emits the ERROR constructor. |
| T090 | 1350 | 439-440 | N5 | C1 | Encoded |  | The ERROR packet is sent once: it is neither retransmitted nor acknowledged. | Contract: the ERROR transition emits no acknowledgment and Terminated is absorbing, so no transition re-emits the packet. |
| T091 | 1350 | 441-441 | N3 | C6 | Dispositioned out |  | An implementation must use timeouts to detect errors that no ERROR packet reports. | Using timeouts to detect unreported errors is timing. |
| T092 | 1350 | 457-462 | N2 | C3 | Deployment-modeled |  | The TFTP opcode is the first 2 bytes following the datagram header. | Model: the opcode is the decoded packet ADT tag; its byte offset after the datagram header is not represented. |
| T093 | 1350 | 468-471 | N2 | C3 | Deployment-modeled |  | RRQ opcode 01 and WRQ opcode 02, each followed by Filename, zero byte, Mode, zero byte. | Model: the appendix RRQ/WRQ layout is the decoded request record; Filename and Mode with their zero bytes stay in the decoder. |
| T094 | 1350 | 472-475 | N2 | C3 | Deployment-modeled |  | DATA opcode 03 followed by a 2-byte block number and n data bytes. | Model: the appendix DATA layout is (block:int, buf:bytes[512], len:int); the 2-byte widths and variable n stay in the decoder. |
| T095 | 1350 | 476-479 | N2 | C3 | Deployment-modeled |  | ACK opcode 04 followed by a 2-byte block number and nothing else. | Model: the appendix ACK layout is a constructor with one int block field; byte widths are not represented. |
| T096 | 1350 | 480-483 | N2 | C3 | Deployment-modeled |  | ERROR opcode 05 followed by a 2-byte error code, an ErrMsg string and a zero byte. | Model: the appendix ERROR layout is a constructor with one int code field; ErrMsg and its zero byte are dropped. |
| T097 | 1350 | 515-515 | N5 | C5 | Vectored |  | Error code 0 means an undefined error described only by the accompanying message. | An executed check block pins the undefined-error constant to 0; the accompanying message text is not modeled. |
| T098 | 1350 | 516-516 | N5 | C5 | Vectored |  | Error code 1 is returned when the requested file does not exist. | An executed check block pins the file-not-found constant to 1; file existence is an environment condition outside the model. |
| T099 | 1350 | 517-517 | N5 | C5 | Vectored |  | Error code 2 is returned when the requester lacks permission for the file. | An executed check block pins the access-violation constant to 2; file permissions are an environment condition outside the model. |
| T100 | 1350 | 518-518 | N5 | C5 | Vectored |  | Error code 3 is returned when storage is exhausted or a quota is exceeded. | An executed check block pins the disk-full constant to 3; storage exhaustion is an environment condition outside the model. |
| T101 | 1350 | 519-519 | N5 | C2 | Encoded |  | Error code 4 is returned for a malformed or illegal TFTP operation. | Contract on the step function: a packet not admissible in the current state yields ERROR with code 4, a condition entirely inside the state machine. |
| T102 | 1350 | 520-520 | N5 | C6 | Dispositioned out |  | Error code 5 is returned to the source of a packet bearing an unknown transfer ID. | Code 5 fires on an unknown transfer ID, which is transport identity the model does not carry. |
| T103 | 1350 | 521-521 | N5 | C5 | Vectored |  | Error code 6 is returned when a write target already exists. | An executed check block pins the file-already-exists constant to 6; target existence is an environment condition outside the model. |
| T104 | 1350 | 522-522 | N5 | C4 | Dispositioned out |  | Error code 7 is returned when a mail-mode recipient does not exist. | Code 7 reports a missing mail recipient, and mail mode is obsolete per RFC 1350 and SHOULD NOT be supported per RFC 1123 4.2.2.1. |
| T105 | 1350 | 526-527 | N3 | C6 | Dispositioned out |  | An implementation is not obliged to use UDP as the underlying transport. | Whether UDP carries TFTP is transport choice. |
| T106 | 1350 | 545-545 | N2 | C6 | Dispositioned out |  | The destination port for an initial RRQ or WRQ is 69; thereafter it is the peer's chosen TID. | Destination port 69 for an initial request names a UDP port, which is transport mechanics. |
| T107 | 1350 | 547-547 | N2 | C6 | Dispositioned out |  | The datagram length field counts the whole UDP packet including its 8-byte header; RFC 1123 4.2.2.2 confirms this against RFC 783. | The UDP length field and its header accounting are transport mechanics. |
| T108 | 1350 | 554-555 | N1 | C6 | Dispositioned out |  | An implementation supplies its TIDs as the UDP source and destination port numbers. | Supplying TIDs as UDP port numbers is transport plumbing. |
| T109 | 1350 | 583-585 | N3 | C6 | Dispositioned out |  | A deployment must restrict the file-system rights of the TFTP server process because TFTP has no login or access control. | Restricting the server process's file-system rights constrains the deployment environment, not any protocol transition. |
| T110 | 1123 | 16-19 | N1 | C6 | Dispositioned out |  | Host vendors are expected to provide TFTP so hosts can be bootstrapped over the network. | Urging vendors to ship TFTP for booting is procurement guidance with no transition to verify. |
| T111 | 1123 | 28-28 | N3 | C4 | Dispositioned out |  | An implementation should not support the mail transfer mode; supersedes RFC 1350's mail-mode text. | RFC 1123 4.2.2.1 says mail SHOULD NOT be supported and RFC 1350 calls it obsolete, so the model has no mail mode to verify. |
| T112 | 1123 | 32-33 | N2 | C6 | Dispositioned out |  | The UDP Length field includes the 8-byte UDP header, correcting RFC 783's definition. | The UDP Length field definition is transport mechanics. |
| T113 | 1123 | 46-60 | N3 | C1 | Encoded | yes | The DATA sender must never retransmit the current DATA packet in response to a duplicate ACK; overrides RFC 1350's may-retransmit-on-duplicate rule. | Contract on the sender step: an ACK whose block number equals the already-acked block (duplicate, detected by int equality) emits no DATA and leaves the block index  |
| T114 | 1123 | 139-139 | N3 | C6 | Dispositioned out |  | An implementation must compute its retransmission timeout adaptively rather than using a fixed value. | An adaptive retransmission timeout is timing. |
| T115 | 1123 | 155-157 | N3 | C6 | Dispositioned out |  | A server should provide configurable access control over which pathnames TFTP operations may touch. | Configurable pathname access control is deployment policy over a file system, and pathname matching is string structure. |
| T116 | 1123 | 161-162 | N3 | C6 | Dispositioned out |  | A server should discard a TFTP request that arrived on a broadcast address without replying. | Recognising a broadcast address is transport mechanics. |
| T117 | 1123 | 195-195 | N3 | C4 | Deployment-modeled |  | An implementation must support the netascii transfer mode. | Model: the mode enum includes Netascii and the state machine accepts it, while the CR/LF translation itself stays opaque. |
| T118 | 1123 | 196-196 | N3 | C4 | Encoded |  | An implementation must support the octet transfer mode. | Contract on the request-accept step: mode equal to the string literal "octet" yields a transfer state rather than ERROR, using literal equality only. |
| T119 | 1123 | 198-198 | N3 | C6 | Dispositioned out |  | An implementation may add non-standard TFTP extensions, none of which are standardized. | An open permission to add unstandardized extensions constrains no transition (implementation-corpus, trace-level). |
| T120 | 1350 | 101-103 | N4 | C1 | Encoded |  | Each transfer has two complementary roles: DATA sender/ACK receiver and ACK sender/DATA receiver. | Contract on the product-automaton spine: the joint state pairs a DATA sender with an ACK sender and the invariant holds each step. |
| T121 | 1350 | 254-259 | N3 | C6 | Dispositioned out |  | A second (duplicate-request) response is rejected while the first connection continues. | Rejecting the second response while keeping the first connection requires comparing source TIDs, which is transport identity. |
| T122 | 1350 | 543-543 | N2 | C6 | Dispositioned out |  | The source port of each packet is the TID picked by the packet's originator. | The source port as the originator's TID is transport identity. |
| T123 | 1350 | 549-552 | N3 | C6 | Dispositioned out |  | The implementor should compute the datagram checksum with the correct algorithm, or send zero when unused. | Datagram checksum computation is transport mechanics. |
| T124 | 1123 | 148-151 | N1 | C6 | Dispositioned out |  | TFTP extensions are non-standard and optional; an implementation need not support any of them. | A statement that extensions are non-standard and optional constrains no transition (implementation-corpus, trace-level). |


## 8. Scope matrix: the boundaries, stated rather than implied

**The wire-format boundary.** The protocol core operates on **decoded packet ADTs**, not on the
byte stream. TFTP's RRQ/WRQ packets carry variable-length NUL-terminated filename and mode
fields; splitting a NUL-terminated string out of a buffer is string structure, which is outside
the decidable fragment by design. Rows describing that byte-level layout are therefore
`Deployment-modeled` (the decoded ADT stands in for the wire encoding) or `Dispositioned out`
(string structure), never `Encoded`. The `examples/tcp_rfc793/` scope drew this line implicitly
through its enum-typed scope; here it is stated.

**What the fixed-length bias buys.** DATA payloads are `bytes[512]` with a separate int length
field, which is exactly the shipped array class: content opaque, length proved. The 512-byte
short-block termination rule is a length obligation, not a content obligation, so it is
`Encoded` rather than modeled.

**The modeled TID pair (Amendment 1).** The connection's two transfer identifiers are carried in
the modeled state, which brings the source-TID **validation** rules inside the boundary: a
received packet whose source TID does not match the connection is discarded, an ERROR goes to
its originator, and the ongoing transfer is left undisturbed. This is the one part of TFTP's
transport surface that carries a genuine attacker model (off-path packet injection) and
therefore admits genuine mutants: accepting a wrong-TID packet is the vulnerability, and
terminating the transfer on one is a denial-of-service bug. Everything else in the transport
surface, UDP port allocation, the well-known port 69 rendezvous, datagram checksums, broadcast
handling, stays outside (barrier B2). The line is drawn at "does this rule defend against
something an attacker can do", not at "is this rule expressible", because expressibility alone
would let the ledger absorb transport mechanics that buy a number without buying assurance.

**Block numbers carry no order.** RFC 1350 defines no ordering on block numbers and does not
define rollover behavior; the wrap-to-0 versus wrap-to-1 divergence is a well-known
implementation split. The core therefore reasons by **equality and disequality only**. Any row
that needs an order (for instance "an already-acknowledged block") is `Deployment-modeled` with
the modeling decision stated, never an imported ordering the RFC does not contain. The RFC 1982
serial-arithmetic machinery shipped earlier is available to such a row; it is not a licence to
add clauses.

**The spine's event alphabet is fixed here.** The joint sender/receiver coupling invariant is
carried by a spine function stepping the product automaton. Its event alphabet **includes
duplicate delivery** of both DATA and ACK. This is not a detail: an invariant proved under
perfect lock-step delivery would exclude every behavior in which the Sorcerer's Apprentice bug
lives, which would make the duplicate-ACK crux decorative. Loss and timeout remain outside the
alphabet (C6).

## 9. The disclosed trusted composition schema

The spine proves that the coupling invariant is **preserved by every single step**. The step
from there to "the invariant holds on every reachable trace" is a trace induction, and trace
induction is outside the decidable fragment. That closure is therefore **disclosed as a trusted
schema**, not silently absorbed into the word "verified": the per-step lemmas are machine-proved,
the temporal closure is a small trusted step, exactly the shape used by mechanized
distributed-systems work that proves `Init ⟹ Inv` and `Inv ∧ Next ⟹ Inv'` inside a Hoare-style
tool and treats "hence always Inv" as a schema.

This is an inductive-invariant argument on the product automaton, **not** a bisimulation. A
refinement-mapping obligation would arise only if the demonstration claimed that a deployed
asynchronous sender/receiver pair refines this spine. It does not claim that.

Related, and equally not claimed: the emergent property the duplicate-ACK fix exists to secure,
the absence of a retransmission-doubling cascade, is a quantitative trace property. It has its
own inventory row and is carried, if at all, as a recorded informal derivation. The per-event
obligation (on an ACK whose block number differs from the block awaited, emit no DATA) is what is
`Encoded`, and it is a state-event safety property whose violation is exhibited by a single
transition, so a postcondition on the transition function is a faithful encoding of it.

## 10. Feasibility, established before authoring

Four probes were run against the shipped compiler (v0.14.65) before this scope was fixed:

| Probe | Verdict |
|---|---|
| Sender step: enum states, equality/disequality block numbers, 512-byte termination, six separately-sourced contract clauses | SAFE, body-faithful, `--strict-verified-core` |
| Sorcerer's Apprentice twin (resends current DATA on a duplicate ACK) | REFUTED, branch-localized |
| Ghost spine over an alphabet including duplicate delivery | SAFE, body-faithful, `--strict-verified-core` |
| Spine mutant (sender advances on a duplicate ACK) | REFUTED |

The protocol core is expressible in the shipped fragment: no `Σ_auto` extension is a
prerequisite, and dependent-length lists (Lever B) are not on this path. The probe **bodies** are
deliberately not committed, because they are working implementations of functions the swarm is
meant to invent; no reference solution exists in this tree.

## 11. Phase 1: the clause surface is authored and frozen

**Done.** [`roots/tftp.llmll`](roots/tftp.llmll) carries all 46 `Encoded` rows across 23 root
contracts, one clause per row, each with its `[Tnnn]`-tagged `:source`. `RFC-COV-1` passes at
freeze strength (`--roots --require-full-coverage`): 46/46 `Encoded` rows cited, 15/15 core
rows cited, no citation of an excluded row, provenance confined to the roots. Evidence,
feasibility, and the 9-of-9 kill matrix: [`roots/FREEZE.md`](roots/FREEZE.md).

Two corrections to this document's own dispositions were made during authoring, recorded
rather than applied silently:

- **T118's named contract shape was wrong.** Its reason above says the octet-mode obligation
  is carried "using literal equality only" on a string. Bare `string` equality against a
  literal falls back from body-faithful verification in v0.14.65, so the row is instead
  carried as `(= m Octet)` over the decoded `Mode` enum. That agrees with T054's model ("mode
  is a decoded enum with the `octet` literal pinned"). The row stays `Encoded`; only the
  named shape changes.
- **T022's obligation needed a guard.** "The only error that does not terminate the
  connection" is a statement about not *driving* a live transfer into termination, and holds
  vacuously once the connection is already `Terminated`.

**Phase 2 is done.** A wave of six concurrent blind agents filled all 23 holes:
whole tree SAFE and body-faithful under `--strict-verified-core`, `verified: 23`, the clause
surface byte-identical afterwards, and 8 of 8 mutants refuted against the agents' own bodies
with the good twin surviving. Results and the claim boundaries:
[`wave/RESULTS.md`](wave/RESULTS.md).

Its gate, MATCH-NULLARY-1
([`../../docs/design/finding-match-nullary-ctor-unsound.md`](../../docs/design/finding-match-nullary-ctor-unsound.md)),
is cleared: that soundness defect was found while authoring against this scope, returned a
false SAFE under `--strict-verified-core` (the per-fill acceptance bar), and was fixed in
v0.14.66.
