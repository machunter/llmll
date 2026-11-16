# Vocabulary for RFC 1350 (TFTP), with the RFC 1123 §4.2 corrections

Citations: `R:n` is `rfc1350.txt` line n; `H:n` is `rfc1123-s4.2.txt` line n.

Reading of requirement words: RFC 1350 predates the capitalised keywords. A lowercase "must" is
taken as an obligation, "should" as an obligation whose strength the clause author records, and
"may" as a permission, which becomes a policy input (a `bool` or a budget) so that both
behaviours stay provable. RFC 1123 keywords are used as written.

## 1. Sorts (M-rows)

| # | Sort | Definition | Reason | Lines |
|---|------|-----------|--------|-------|
| M1 | `Opcode16` | `int`, `0 <= v < 65536` | The raw 2-byte opcode field, before classification. | R:155-156, R:287-289 |
| M2 | `PacketKind` | enum `KRrq KWrq KData KAck KError KInvalid` | The five packet types, plus one tag for every other opcode value so classification is total. | R:263-271 |
| M3 | `Tid` | `int`, `0 <= v < 65536`; constant `WELL_KNOWN_TID = 69` | Transfer identifier, handed to UDP as a port. | R:150-152, R:205-207, R:545 |
| M4 | `Block` | `int`, `0 <= v < 65536` | 2-byte block number; 0 appears only in the ACK of a WRQ. | R:189-192, R:348-350, R:357-358, R:384-385 |
| M5 | `DataLen` | `int`, `0 <= v <= 512` | Length of a DATA payload. | R:361-363 |
| M6 | `TftpLen` | `int`, `v >= 0` | Length of the TFTP packet (opcode included, UDP header excluded). | R:149-150, R:419, H:32-33 |
| M7 | `Mode` | enum `MNetascii MOctet MMail MOther` | Decoded mode string; `MOther` is any string that is none of the three. | R:73-82, R:297-300 |
| M8 | `ErrorCode` | enum `ENotDefined EFileNotFound EAccessViolation EDiskFull EIllegalOp EUnknownTid EFileExists ENoSuchUser` | The eight codes, values 0..7 in this order. Used for codes this side sends. | R:513-522 |
| M9 | `ErrCode16` | `int`, `0 <= v < 65536` | Raw error-code field of a received ERROR; may be outside 0..7. | R:399-401, R:409 |
| M10 | `Role` | enum `RSender RReceiver` | Which side originates DATA. Replaces client/server for the transfer loop (see D2). | R:101-103, H:46-48 |
| M11 | `Phase` | enum `PhAwaitFirst PhActive PhDally PhDone PhAborted PhTimedOut` | Connection state. `PhAwaitFirst`: request sent, peer TID not yet known. `PhDally`: final ACK sent, still answering duplicates. `PhDone`: success. `PhAborted`: ERROR sent or received. `PhTimedOut`: gave up retransmitting, outcome unknown. | R:184-187, R:421-434, R:105-110 |
| M12 | `TidVerdict` | enum `TvBind TvMatch TvStray` | Result of the source check on a received packet. | R:207-210, R:238-246 |
| M13 | `RxClass` | enum `RxStray RxAdvance RxDupCurrent RxOld RxPeerError RxIllegal RxUnboundReject RxIgnore` | One tag per distinct treatment of a received packet (see step S16 for the table). | R:119-128, R:238-246, R:356-363, H:46-60 |
| M14 | `Reply` | enum `RpNone RpAck RpData RpError` | The packet (if any) sent in direct response to a received packet. | R:366-385, R:407-408 |
| M15 | `LocalIo` | enum `IoOk IoDiskFull IoAccess IoOther` | Outcome of the local file operation the step depends on (write the received block; read the next block). An input, never computed. | R:123-124 |
| M16 | `ReqVerdict` | enum `RvGrant RvNotFound RvAccess RvDiskFull RvExists RvNoUser RvOther` | Local decision on a request (file system and access policy). An input. | R:119-120, R:438-439, R:515-522, H:155-157 |
| M17 | `ReqClass` | enum `RqServe RqIgnore RqReject` | Protocol-level classification of a packet arriving at TID 69, before the file system is consulted. | R:184-195, H:161-162 |
| M18 | `TimeoutAction` | enum `ToResend ToGiveUp ToClose ToNone` | What a timer expiry leads to. | R:95-98, R:421-430, H:126-135 |

## 2. Steps

### How the algorithm is divided

1. **Wire facts** (S1-S7): pure arithmetic and classification on decoded fields. Byte extraction is
   outside (X2); these steps start from integers.
2. **Request handling at TID 69** (S8-S12) and **request issue** (S13-S14): the only places where
   client and server differ.
3. **Transfer loop** (S15-S24): after the request, both ends are either the data sender or the
   data receiver (D2). A received packet goes through three stages: the source check (S15), a
   classification into `RxClass` (S16), and a family of projection functions that each return one
   component of the response (S17-S24). The projections exist because a function returns one
   value and a constructor carries at most one payload (D1). Classification is separated from
   response so that each RFC obligation attaches to one enum tag instead of to an arithmetic
   condition repeated in every clause (D3).
4. **Timer expiry** (S25-S29): time is outside the target, so expiry is an input event; the steps
   say what is permitted or required when it happens.

State facts carried between steps, all passed as parameters: `role`, `phase`, `peer: Tid`,
`cur: Block`, `last_len: DataLen`, `retries_left: int`. `cur` is the last block ACKed (receiver)
or the last block sent (sender); both start at 0 on the client, because the RRQ stands in for
"ACK 0" and the WRQ for "DATA 0" (R:366-370, R:381-385).

### Wire facts

| # | Signature | Purpose | Lines |
|---|-----------|---------|-------|
| S1 | `opcode_kind [op: Opcode16] -> PacketKind` | 1..5 to the five kinds, anything else to `KInvalid`. | R:263-271 |
| S2 | `kind_opcode [kind: PacketKind] -> int` | Opcode value to emit for a kind (0 for `KInvalid`, never emitted). | R:263-271 |
| S3 | `packet_wellformed [kind: PacketKind, tftp_len: TftpLen, strings_ok: bool, block: int] -> bool` | Length and field checks per kind: ACK length 4; DATA length 4..516 and block >= 1; RRQ/WRQ and ERROR need `strings_ok` (the decoder found every zero terminator). | R:287-300, R:348-363, R:373-385, R:399-414 |
| S4 | `data_len_of [tftp_len: TftpLen] -> int` | DATA payload length = TFTP length - 4. | R:348-350, R:419 |
| S5 | `udp_length [tftp_len: TftpLen] -> int` | UDP Length field = TFTP length + 8. | R:547, H:32-33 |
| S6 | `is_final_len [len: DataLen] -> bool` | True iff `len < 512`. | R:94-95, R:361-363, R:418-419 |
| S7 | `block_data_len [stream_len: int, block: Block] -> DataLen` | Payload length of block n of a stream of `stream_len` bytes: `stream_len - 512*(n-1)` clamped to 0..512. | R:91-95, R:357-363 |

### Requests

| # | Signature | Purpose | Lines |
|---|-----------|---------|-------|
| S8 | `request_class [kind: PacketKind, wellformed: bool, to_broadcast: bool, mode: Mode, mail_enabled: bool] -> ReqClass` | Server, packet at TID 69: ignore broadcasts, reject non-requests, malformed requests and unsupported modes, otherwise serve. | R:184-195, R:297-310, H:28, H:161-162, H:195-197 |
| S9 | `request_reply [cls: ReqClass, kind: PacketKind, verdict: ReqVerdict] -> Reply` | `RpData` for a granted RRQ, `RpAck` for a granted WRQ, `RpError` for a rejection or denial, `RpNone` when ignored. | R:184-195, R:438-439 |
| S10 | `request_error_code [cls: ReqClass, verdict: ReqVerdict] -> ErrorCode` | Code carried by the ERROR of S9. | R:119-120, R:513-522 |
| S11 | `request_reply_block [kind: PacketKind] -> Block` | 1 for the DATA answering an RRQ, 0 for the ACK answering a WRQ. | R:189-194, R:234, R:384-385, R:490 |
| S12 | `request_role [kind: PacketKind] -> Role` | Server role after a grant: `RSender` for RRQ (with `cur = 1`), `RReceiver` for WRQ (with `cur = 0`); phase is `PhActive`. | R:184-187 |
| S13 | `client_request_ok [kind: PacketKind, mode: Mode] -> bool` | A request the client may issue: kind is RRQ or WRQ, mode is one of the three, mail only with WRQ. | R:184-185, R:297-310 |
| S14 | `client_role [kind: PacketKind] -> Role` | Client role: `RReceiver` for RRQ, `RSender` for WRQ; `cur = 0`, phase `PhAwaitFirst`, destination `WELL_KNOWN_TID`. | R:205-207, R:231-232, R:487-488 |

### Transfer loop

| # | Signature | Purpose | Lines |
|---|-----------|---------|-------|
| S15 | `tid_verdict [phase: Phase, same_host: bool, src: Tid, peer: Tid] -> TidVerdict` | `TvBind` in `PhAwaitFirst` (peer TID not yet chosen); otherwise `TvMatch` iff `same_host` and `src = peer`, else `TvStray`. | R:207-210, R:238-246 |
| S16 | `rx_class [role: Role, phase: Phase, tv: TidVerdict, kind: PacketKind, wellformed: bool, block: int, cur: Block] -> RxClass` | Classify a received packet; table below. | R:119-128, R:238-259, R:356-363, R:418-427, H:46-60 |
| S17 | `rx_reply [role: Role, cls: RxClass, kind: PacketKind, last_len: DataLen, io: LocalIo] -> Reply` | Which packet answers it. | R:92-94, R:238-246, R:366-385, R:418-429, H:46-60 |
| S18 | `rx_reply_block [role: Role, block: Block, cur: Block] -> Block` | Block number in the reply: an ACK echoes `block`; a DATA carries `cur + 1`. | R:187-194, R:357-358, R:382-384 |
| S19 | `rx_error_code [cls: RxClass, io: LocalIo] -> ErrorCode` | Code in an `RpError` reply. | R:119-128, R:513-522 |
| S20 | `rx_next_phase [role: Role, phase: Phase, cls: RxClass, data_len: DataLen, last_len: DataLen, io: LocalIo] -> Phase` | Phase after the packet is handled. | R:105-110, R:126-128, R:418-434 |
| S21 | `rx_next_cur [role: Role, cls: RxClass, cur: Block, io: LocalIo, last_len: DataLen] -> Block` | `cur + 1` when a new block is accepted (receiver) or a new block is sent (sender); otherwise `cur`. | R:189-190, R:357-360 |
| S22 | `rx_binds_peer [cls: RxClass, tv: TidVerdict] -> bool` | True iff this packet fixes the peer TID for the rest of the transfer. | R:207-210, R:253-254 |
| S23 | `rx_delivers [role: Role, cls: RxClass, io: LocalIo] -> bool` | True iff the payload is appended to the destination (receiver, `RxAdvance`, `IoOk`). Expresses "each block delivered once, in order". | R:130-133, R:357-360 |
| S24 | `reply_dst_tid [cls: RxClass, src: Tid, peer: Tid] -> Tid` | Destination TID of the reply: always the source of the packet being answered. | R:207-209, R:241-244 |

`rx_class` table, first matching row wins:

| Condition | Class |
|-----------|-------|
| `tv = TvStray` | `RxStray` |
| phase is `PhDone`, `PhAborted` or `PhTimedOut` | `RxIgnore` |
| `kind = KError` | `RxPeerError` |
| `tv = TvBind`, and not (wellformed and ((receiver, `KData`, block 1) or (sender, `KAck`, block 0))) | `RxUnboundReject` |
| `tv = TvBind`, otherwise | `RxAdvance` |
| not wellformed, or `kind = KInvalid` | `RxIllegal` (in `PhDally`: `RxIgnore`) |
| `PhDally`: `KData` with `block = cur` | `RxDupCurrent`; anything else `RxIgnore` |
| receiver, `KData`: `block = cur + 1` / `block = cur` / `block < cur` / `block > cur + 1` | `RxAdvance` / `RxDupCurrent` / `RxOld` / `RxIllegal` |
| sender, `KAck`: `block = cur` / `block < cur` / `block > cur` | `RxAdvance` / `RxOld` / `RxIllegal` |
| any other kind for the role | `RxIllegal` |

Response per class (S17-S23):

| Class | Reply | Code | Next phase | Notes |
|-------|-------|------|-----------|-------|
| `RxStray` | `RpError`, or `RpNone` if `kind = KError` | `EUnknownTid` | unchanged | Transfer not disturbed. |
| `RxAdvance`, receiver, `IoOk` | `RpAck` of `block` | - | `PhDally` if `data_len < 512`, else `PhActive` | Delivers payload. |
| `RxAdvance`, receiver, io failed | `RpError` | by `io` | `PhAborted` | No delivery, no ACK. |
| `RxAdvance`, sender, `cur >= 1` and `last_len < 512` | `RpNone` | - | `PhDone` | Final block acknowledged. |
| `RxAdvance`, sender, otherwise, `IoOk` | `RpData` of `cur + 1` | - | `PhActive` | Length from S7. |
| `RxAdvance`, sender, io failed | `RpError` | by `io` | `PhAborted` | |
| `RxDupCurrent` | `RpAck` of `block` | - | unchanged | No delivery. |
| `RxOld` | `RpNone` | - | unchanged | Covers the duplicate-ACK rule. |
| `RxPeerError` | `RpNone` | - | `PhAborted` | |
| `RxIllegal` | `RpError` | `EIllegalOp` | `PhAborted` | |
| `RxUnboundReject` | `RpError` | `EUnknownTid` | unchanged (`PhAwaitFirst`) | Peer stays unbound. |
| `RxIgnore` | `RpNone` | - | unchanged | |

### Timer expiry

| # | Signature | Purpose | Lines |
|---|-----------|---------|-------|
| S25 | `timeout_action [role: Role, phase: Phase, retries_left: int, rx_timer: bool] -> TimeoutAction` | On expiry: resend the one packet on hand, give up, end the dally, or do nothing. | R:95-100, R:421-430, H:126-135 |
| S26 | `timeout_next_phase [phase: Phase, act: TimeoutAction] -> Phase` | `ToGiveUp` to `PhTimedOut`; `ToClose` (from `PhDally`) to `PhDone`; otherwise unchanged. | R:427-434 |
| S27 | `timeout_dst_tid [phase: Phase, peer: Tid] -> Tid` | Destination of a retransmission: `WELL_KNOWN_TID` in `PhAwaitFirst`, else `peer`. | R:205-210 |
| S28 | `timeout_retries [retries_left: int, act: TimeoutAction] -> int` | Budget after the expiry: one less on `ToResend`, otherwise unchanged. | R:427-430 |
| S29 | `rto_backoff [rto: int, rto_max: int] -> int` | Next timeout interval after an expiry: at least `min(2*rto, rto_max)`. | H:139-144 |

`timeout_action`: in `PhAwaitFirst`, and for the sender in `PhActive`, `ToResend` while
`retries_left > 0`, else `ToGiveUp`. For the receiver in `PhActive`: the same if `rx_timer`;
if not `rx_timer`, `ToNone` while `retries_left > 0` (the receiver only waits) and `ToGiveUp`
after. In `PhDally`: `ToClose`. In a closed phase: `ToNone`.

## 3. Modeling decisions (D-rows)

Each row: question; alternatives; choice; lines.

**Shape of the vocabulary**

- **D1. How does a step return several things (reply kind, block, code, next state)?** (a) One sum
  with a payload per constructor; (b) one projection function per component, all over the same
  inputs. Chosen (b): a constructor carries one payload, and the reply needs up to two numbers
  plus a next state. Cost: clauses about one event are spread over several functions. Tool manual.
- **D2. Client/server or sender/receiver as the main split?** (a) Four state machines (client-read,
  client-write, server-read, server-write); (b) two roles, with the request treated as block 0
  of the opposite packet type. Chosen (b). The RFC itself says WRQ is acknowledged like DATA and
  RRQ like ACK, and RFC 1123 defines "sender" as the side originating DATA. Client/server
  survives only in S8-S14 and in `PhAwaitFirst`. R:101-103, R:366-385, H:46-48.
- **D3. One response function over raw fields, or classify first?** Chosen classify first
  (`RxClass`), so later functions discriminate on an enum tag as the tool prefers.
- **D4. State as a record or as loose parameters?** No records available; state is `role`, `phase`,
  `peer`, `cur`, `last_len`, `retries_left` passed separately. `last_len` (length of the last
  DATA sent) replaces a separate "final block sent" phase.
- **D5. `last_len` when no DATA has been sent yet (WRQ client, `cur = 0`).** (a) A sentinel;
  (b) ignore `last_len` when `cur = 0`. Chosen (b): the sender is finished only when `cur >= 1`
  and `last_len < 512`. R:238, R:418-419.

**Wire format**

- **D6. Byte order of the 2-byte fields.** RFC 1350 never states it. Alternatives: big-endian
  (network order), unspecified. The vocabulary takes decoded integers, so the choice lives in the
  decoder (X2); big-endian is assumed there. R:155-156, R:287-289, R:348-350.
- **D7. Opcodes outside 1..5.** (a) Drop silently; (b) "incorrectly formed packet" leading to
  ERROR 4. Chosen (b) via `KInvalid`. R:119-122, R:519.
- **D8. Exact or minimum length for ACK.** (a) Exactly 4 bytes; (b) at least 4, trailing bytes
  ignored. Chosen (a); a longer ACK is malformed. RFC silent. R:373-378.
- **D9. DATA longer than 516 bytes.** (a) Malformed; (b) truncate to 512. Chosen (a).
  R:361.
- **D10. DATA with block 0.** (a) Malformed; (b) treated as an old duplicate. Chosen (a): DATA
  blocks "begin with one". R:189-190, R:357-358.
- **D11. Packets shorter than their fixed header** (under 2 bytes: no opcode; ACK/DATA/ERROR under
  4). The decoder reports `KInvalid` (under 2) or `wellformed = false`. RFC silent.
- **D12. Trailing bytes after the mode terminator of a request.** (a) Malformed; (b) ignored.
  Chosen (a), folded into `strings_ok`. RFC silent; this is where later option extensions live,
  and they are outside this RFC. R:287-292.
- **D13. ERROR packet without a terminator, or with an empty message.** Chosen: any packet with
  opcode 5 and a matching source is a peer error, wellformed or not (`RxPeerError` is tested
  before wellformedness); an empty message is fine. Alternative: malformed ERROR answered with
  ERROR 4, which makes two ends exchange errors. R:407-414.
- **D14. Meaning of "Datagram length < 516".** The appendix defines UDP Length as including the
  8-byte UDP header, and RFC 1123 repeats that; but 516 = 4 + 512 only if the header is excluded.
  Alternatives: UDP Length < 516 (payload < 504, contradicts R:361-363) or TFTP length < 516.
  Chosen: TFTP length; `TftpLen` and S5 keep the two apart. R:419, R:547, H:32-33.
- **D15. Mode comparison.** Case-insensitive match is string work and stays in the decoder; the
  vocabulary sees `Mode`. Any other string is `MOther`. R:297-300.
- **D16. Received error codes above 7.** (a) Map to `ENotDefined`; (b) keep raw. Chosen: the raw
  `ErrCode16` is not interpreted at all; every received ERROR ends the transfer the same way
  (D31), so no decoding function is needed. R:513-522.

**Requests**

- **D17. Mail mode.** RFC 1350: obsolete, "should not be implemented or used"; RFC 1123: SHOULD
  NOT be supported. Alternatives: remove `MMail`; always reject; policy input. Chosen: keep
  `MMail` with input `mail_enabled`, so both a conforming refusal and the legacy behaviour can be
  stated. R:79-81, H:28, H:197.
- **D18. Mail with RRQ.** "must begin with a WRQ": RRQ in mail mode is rejected (`RqReject`) even
  when `mail_enabled`. R:309-310.
- **D19. netascii and octet support.** RFC 1123 lists both as MUST, so `request_class` never
  rejects on those modes; there is no "octet only" policy input. H:195-196.
- **D20. Extension modes.** Allowed between cooperating hosts, not standardized. Chosen: `MOther`
  is always rejected; extensions are out (X8). R:82, R:334-345, H:148-151, H:198.
- **D21. Error code for a rejected mode** (unknown string, mail disabled, mail with RRQ). RFC
  silent. Alternatives: 4 (illegal operation), 0 (not defined), 7 for mail. Chosen 4 for all
  three. R:519.
- **D22. Non-request packet (DATA, ACK, invalid opcode) arriving at TID 69.** RFC silent.
  Alternatives: ERROR 4; ERROR 5; silence. Chosen ERROR 4 (`RqReject`), no connection created.
  An ERROR packet arriving at 69 is ignored (`RqIgnore`), never answered. R:205-207, R:519.
- **D23. Malformed request.** ERROR 4, same as D22. R:121-122.
- **D24. Broadcast request.** SHOULD be silently ignored. Alternatives: policy input; always
  ignore. Chosen always ignore; "addressed to broadcast" is an input bool because the IP header
  is outside. Tested before everything else, so a malformed broadcast packet also gets no ERROR.
  H:161-162.
- **D25. Mapping local denial to a code.** The table gives meanings, not triggers. Chosen: the
  environment reports `ReqVerdict` and the code follows one-to-one (`RvNotFound` 1, `RvAccess` 2,
  `RvDiskFull` 3, `RvExists` 6, `RvNoUser` 7, `RvOther` 0). Whether a WRQ may overwrite an
  existing file, whether `RvNoUser` can occur outside mail mode, and which verdicts are possible
  for RRQ versus WRQ are left to the environment. R:119-120, R:513-522, H:155-157.
- **D26. Duplicate requests at the server.** (a) Remember recent (host, TID) pairs and suppress;
  (b) treat every request independently. Chosen (b); the RFC's own example has the server open
  two connections with different TIDs. R:249-259.
- **D27. Server TID.** "Randomly chosen" is not checkable; the local TID is an input of sort
  `Tid`. Not modeled: that it differs from 69, from TIDs in use, or from the previous one. See
  Q3. R:197-201, R:207-209.
- **D28. Client retransmission of the request.** Goes to 69 with the same source TID, as a
  retransmission of "his last packet" (S27). Alternative: a fresh TID per attempt. R:95-98,
  R:205-207.

**Source check**

- **D29. What identifies the peer.** The RFC speaks of TIDs only. (a) TID alone; (b) host
  address and TID. Chosen (b) through the input `same_host`; a packet from another host with the
  same port number is "sent from somewhere else". An implementation on one host pair can pass
  `true`. R:238-246.
- **D30. When the peer TID is bound.** The client learns the server TID from the first reply.
  Alternatives: bind on the first packet of any kind; bind only on an acceptable first reply.
  Chosen: bind only on wellformed DATA 1 (reader) or ACK 0 (writer). R:207-210, R:253-254.
- **D31. Received ERROR.** Ends the transfer (`PhAborted`) whatever its code, including code 5
  and unknown codes; it is never acknowledged and never answered. In `PhAwaitFirst` an ERROR
  from any source counts as the denial of the request, since no TID exists to check it against
  (spoofable; accepted). R:105-108, R:194-195, R:407-408.
- **D32. Unacceptable first reply (wrong kind, wrong block, malformed) while unbound.** RFC
  silent. Alternatives: ERROR 4 and abort; ERROR 5 to the source and keep waiting; silence.
  Chosen ERROR 5 and keep waiting: the packet's source is not known to be the peer, so it is
  handled like a stray. R:238-246.
- **D33. Stray packet (TID mismatch).** "Should be discarded" and "an error packet should be
  sent". Chosen: always send ERROR 5 to the stray's source, leave every state fact unchanged.
  Alternative: a policy input allowing silence. R:126-128, R:241-246, R:520.
- **D34. Stray packet that is itself an ERROR.** RFC silent. Chosen: no reply, to avoid two hosts
  exchanging errors forever. Alternative: answer with ERROR 5 as for any stray.
- **D35. Packets after the connection is closed.** `RxIgnore`, no reply. In practice the port is
  released and the transport answers; that is outside. RFC silent. R:434.

**Transfer loop**

- **D36. Receiver gets a duplicate of the current block (`block = cur`).** RFC 1350 implies the
  final ACK is resent on a duplicate final DATA; RFC 1123 says a resent ACK is harmless once the
  sender ignores duplicates, and that dropping the receiver's resend is also allowed.
  Alternatives: re-ACK; stay silent; policy input. Chosen re-ACK always, payload not delivered
  again. R:423-426, H:62-64, H:126-134.
- **D37. Receiver gets an older block (`block < cur`).** Explained by delay or duplication, so
  not an error. Alternatives: ACK it; silence. Chosen silence. R:119-122, R:357-360.
- **D38. Receiver gets a block ahead (`block > cur + 1`).** Lock-step makes this impossible from
  a correct peer. Alternatives: ERROR 4 and abort; silence. Chosen ERROR 4. R:99-101,
  R:119-122, R:130-133.
- **D39. Sender gets a duplicate ACK.** RFC 1123 MUST: never resend the current DATA.
  "Duplicate" is taken as any ACK with `block < cur`, not only `cur - 1`. No reply of any kind,
  no state change, and the retransmit timer is not restarted by it (timer handling is outside
  anyway). This overrides RFC 1350's "may retransmit" reading. H:46-60, R:366-367.
- **D40. Sender gets an ACK ahead (`block > cur`).** Alternatives: ERROR 4 and abort; silence.
  Chosen ERROR 4. R:119-122.
- **D41. Wrong packet kind on an established connection** (ACK to a receiver, DATA to a sender,
  RRQ/WRQ to either). Cannot be explained by delay or duplication within this TID pair. Chosen
  ERROR 4 and abort. R:119-122, R:519.
- **D42. Does sending an ERROR end the sender's side?** "May terminate after sending". Chosen:
  yes, at once, with no dally and no retransmission, for every code except 5 sent to a stray or
  to an unacceptable first reply. R:105-110, R:126-128, R:438-441.
- **D43. Ordering on block numbers.** The RFC defines "begin with one and increase by one", so
  integer order on 0..65535 is used. No wrap-around order is imported.
- **D44. Block number after 65535.** RFC silent; the field is 2 bytes. Alternatives: wrap to 0;
  wrap to 1; fail the transfer; restrict the domain. Chosen: restrict. `rx_next_cur` and
  `rx_reply_block` are specified only for `cur < 65535`; a stream needing a block 65536
  (`stream_len >= 65535*512`) is outside the vocabulary, and the clause author records that as
  a precondition. R:348-350, R:357-358.
- **D45. End of transfer.** A block under 512 bytes ends it. Consequences taken as intended: an
  empty stream is one DATA of length 0, and a stream whose length is a positive multiple of 512
  ends with an extra DATA of length 0. S7 encodes both. R:94-95, R:361-363, R:418-419.
- **D46. What `stream_len` measures.** The bytes on the wire: in netascii the translated stream,
  not the local file. Translation is outside (X3). R:300-302.
- **D47. Local I/O failure during transfer.** `IoDiskFull` to code 3, `IoAccess` to code 2,
  `IoOther` to code 0; the ERROR replaces the ACK or DATA that would have been sent, and the
  block is not counted as delivered. R:123-124, R:438-439, R:515-518.
- **D48. Dallying.** "Encouraged", not required. Alternatives: policy bool; always dally. Chosen:
  the receiver always enters `PhDally`; an implementation that does not dally fires `ToClose`
  immediately. Success is already established on entering `PhDally`. R:421-426.
- **D49. Unexpected packets during the dally.** Only a duplicate of the final DATA is answered.
  Everything else from the peer (other blocks, wrong kinds, malformed) is ignored and the phase
  stays, so a completed transfer cannot turn into `PhAborted`; a peer ERROR still moves to
  `PhAborted` by the table order, which the clause author may want to revisit (Q7).
  Alternative: ERROR 4 as in `PhActive`. RFC silent.
- **D50. Outcome names.** `PhDone` is success as seen locally: the receiver after the dally, the
  sender on the ACK of the final block. A sender that gives up waiting for the final ACK is
  `PhTimedOut`, not failed: the RFC says the transfer may or may not have completed. A receiver
  cannot tell whether its final ACK arrived and does not need to. R:428-434.

**Timers**

- **D51. Timeout as an input event.** Clocks are outside; S25 is called when the environment says
  a timer expired. Nothing constrains when that is.
- **D52. Giving up.** "Not prepared to retransmit any more". Alternatives: a bool from the
  environment; a decreasing integer budget. Chosen the budget (`retries_left`), so "retransmit
  until acknowledged or timed out" is a statement about a counter. Its initial value is not in
  the RFC. R:427-430.
- **D53. Is retransmission on timeout required?** "May retransmit" in the overview; "must
  retransmit" for the final DATA; RFC 1123 says the sender requires a retransmit timer. Chosen:
  the sender and the unbound client must resend while budget remains; the receiver's resend is
  optional (`rx_timer`). R:95-98, R:427-428, H:128-135.
- **D54. What is retransmitted.** Exactly the last packet sent (request, DATA `cur`, or ACK
  `cur`), unchanged. Only one packet is kept. R:98-101.
- **D55. Adaptive timeout.** MUST, but only "at least exponential backoff" is concrete, and that
  in an IMPLEMENTATION note. Chosen: S29 with a doubling floor and a cap `rto_max`. The cap,
  the initial value, round-trip estimation, and when the interval resets are not in the source;
  the cap is an import, flagged. H:139-144.
- **D56. A receiver without a timer never resends, so when does it give up?** RFC 1123 allows
  removing the receiver's retransmission timer; RFC 1350 still says timeouts must detect lost
  ERROR packets. Chosen: the receiver always has a give-up path (`ToGiveUp` when the budget is
  0); `rx_timer` controls only whether it resends before that. R:109-110, R:441, H:128-133.

## 4. Exclusions (X-rows)

- **X1. Time.** Timer values, the dally duration, round-trip estimation. Only the event and the
  backoff floor are modeled (D51, D55). R:95-97, R:423-425, H:139-144.
- **X2. Byte-level parsing and encoding.** Extracting the opcode, block, error code; finding the
  zero terminators of filename, mode and message (offsets depend on packet content); byte order;
  case-folding the mode. The steps take decoded values and `strings_ok`. R:287-300, R:399-414.
- **X3. netascii.** Character set, line-end translation, the rule that a receiver must translate
  to its own format. R:73-78, R:300-302.
- **X4. File contents and octet fidelity.** That a stored and returned octet file is identical;
  the 8-bit format of a given machine. A property over two transfers and a file system.
  R:302-308.
- **X5. File names and access control.** The filename string, path rules, configurable access
  control, security of the server's file system. Reduced to the input `ReqVerdict`. R:296-297,
  R:583-588, H:155-157.
- **X6. Mail delivery.** Recipient syntax ("username", "username@hostname"), forwarding.
  R:309-313.
- **X7. Error message text.** Content and character set of ErrMsg. R:412-414.
- **X8. Extensions.** Additional modes between cooperating hosts, secure mode, anything negotiated
  in the request. R:82, R:315-345, H:148-151.
- **X9. TID selection.** Randomness and the "low probability of repetition" property.
  R:198-201.
- **X10. UDP, IP and local headers.** Checksum, IP addresses, detection of a broadcast
  destination, the UDP header layout, other datagram transports. R:137-153, R:524-555.
- **X11. The network.** Loss, delay, duplication and reordering as such; liveness (that a
  transfer finishes); the absence of the Sorcerer's Apprentice loop as a two-party trace
  property. Only the local rule that breaks the loop is expressible (D39). H:37-135.
- **X12. Several connections at once.** The server's table of active transfers, port allocation,
  concurrency. Each step sees one connection. R:249-259.
- **X13. Cross-packet invariants needing quantifiers.** "All older packets have been received",
  "the file received equals the file sent". Stated per step through `rx_delivers` and `cur`
  only. R:99-101.
- **X14. Performance remarks and the bootstrapping use case.** H:8-19.

## 5. Open questions for the RFC author

- **Q1.** What byte order do the opcode, block number and error code use? (D6)
- **Q2.** What happens after block 65535? Is a transfer limited to 65535 blocks? (D44)
- **Q3.** Must the server's TID differ from 69, and from TIDs of its other live connections? May
  a TID be 0? (D27)
- **Q4.** Is the peer identified by TID alone or by host and TID? (D29)
- **Q5.** In "Datagram length < 516", is the length the TFTP packet length? (D14)
- **Q6.** Before the client knows the server's TID, how should it treat a packet that is not an
  acceptable first reply, and should it trust an ERROR from any source? (D31, D32)
- **Q7.** Should a receiver resend its ACK on a duplicate DATA, now that the sender ignores
  duplicate ACKs? And what should a dallying receiver do with an ERROR or a block other than
  the final one? (D36, D49)
- **Q8.** Is a DATA or ACK ahead of the expected block an error (code 4) or something to drop?
  Same question for an older DATA. (D37, D38, D40)
- **Q9.** Which code answers an unsupported or unknown mode, and a non-request packet sent to
  TID 69? (D21, D22)
- **Q10.** Should an ERROR ever be sent in response to an ERROR (stray or malformed)? (D13, D34)
- **Q11.** Is an ACK longer than 4 bytes, a DATA longer than 516 bytes, or a request with bytes
  after the mode terminator malformed or tolerated? (D8, D9, D12)
- **Q12.** Does the host that receives ERROR 5 always terminate its transfer, even if the ERROR
  came from a host it believes to be its peer? (D31)
- **Q13.** Is retransmission on timeout required for every packet or only for the final DATA?
  How many attempts before giving up? (D52, D53)
- **Q14.** May a WRQ overwrite an existing file, or must it be refused with code 6? Can code 7
  occur outside mail mode? (D25)
- **Q15.** Does a client retransmit its request from the same TID or choose a new one? (D28)
- **Q16.** When the sender of an ERROR "may terminate", is there any case where it should stay
  to answer retransmissions? (D42)
