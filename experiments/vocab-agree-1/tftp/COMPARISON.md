# TFTP vocabularies compared: R (frozen) against three blind vocabularies A, B, C

Citations: `1350:N` is `reference/rfc1350.txt` line N; `1123:N` is `reference/rfc1123-s4.2.txt` line N
(the copies in `a/`, `b/`, `c/` are byte-identical, same sha256). `A:D12`, `B:S15`, `C:X3` are rows of
the three vocabularies. For R: `R:§8` is `reference/VERIFICATION_SCOPE.md` §8, `R:T067` an inventory
row of that file, `R:llmll:171` a line of `reference/tftp.llmll`, `R:FREEZE` the freeze record.

| | R | A | B | C |
|---|---|---|---|---|
| Declared sorts | 5 types (`Role`, `XferState`, `PacketKind`, `Mode`, `Packet`); int ranges as predicates/pres | 19 (M1-M19) | 19 (M1-M19) | 18 (M1-M18) |
| Steps | 23 root functions | 31 (S1-S31) | 27 (S1-S28, no S19) | 29 (S1-S29) |
| Decision rows | none as a list; recorded in §8, §9, §11, FREEZE "model shape", Amendment 1, and per-row disposition reasons | 49 | 60 | 56 |
| Exclusion rows | 53 dispositioned-out rows + 20 deployment-modeled, under barrier list B1-B8 | 12 | 20 | 14 |

R was written with the inventory and compiler constraints in hand; A, B, C from the two RFC files
and the brief only. None is treated as correct below.

---

## 1. Sorts

| Concept | R | A | B | C |
|---|---|---|---|---|
| Packet kind | `PacketKind` = 5 nullary tags, no invalid tag (decoder outside); `opcode-of` tag→int | raw `Word16` + `Opcode` with `OpInvalid` (M5); decoder `opcode_of` raw→tag | `Opcode` 5 tags + sum `OpcodeCls = BadOp \| GoodOp(Opcode)` (M1, M2) | raw `Opcode16` + `PacketKind` with `KInvalid` (M1, M2); both directions (S1, S2) |
| Emitted packet / response | sum `Packet = RRQ \| WRQ \| DataPkt int \| AckPkt int \| ErrPkt int \| NoPacket` | sum `Action = ActNone \| ActSendData int \| ActSendAck int \| ActSendError ErrCode \| ActRetransmit \| ActRejectStranger` (M12) | **none**: per-step verdict enums (`SendAct`, `RecvAct`, `TidVerdict`, `ReqVerdict`, `InitVerdict`, `TimeoutAct`) imply what is sent | enum `Reply = RpNone \| RpAck \| RpData \| RpError` (M14) + separate block/code/destination projections |
| Transfer mode | `Mode = Netascii \| Octet \| Mail` (no "other") | `ModeNetascii \| ModeOctet \| ModeMail \| ModeOther` (M6) | `Netascii \| Octet \| Mail \| OtherMode` (M3) | `MNetascii \| MOctet \| MMail \| MOther` (M7) |
| Block number | plain `int`, only `>= 0` in pres; **no upper bound** | `BlockNum` 0..65535 (M3) + `NextBlock` 1..65535 (M19) | `Block` 0..65535 (M4) | `Block` 0..65535 (M4) |
| Block order | none: equality, disequality, successor only (R:§8, R:llmll:33-36) | integer `<` (A:D7) | none: equality + successor (B:D21) | integer `<` (C:D43) |
| Block wrap after 65535 | none stated; successor is unbounded (`sender-next-block` returns `acked+1` for every `acked >= 0`, R:llmll:171-182) | forbidden: precondition `current < 65535` (A:D1) | **wraps to 0** (B:S13, B:D1) | domain restricted to `cur < 65535` (C:D44) |
| Block classification | none; `dup: bool` input on `step-responds`, `ackblk ≠ acked` on `sender-reply` | `BlockClass = Expected \| Duplicate \| Stale \| Future` (M14) | `RecvAct = RecvNew \| RecvDupLast \| RecvOther` (M15); sender `SendAct` (M16) | `RxClass` 8 tags (M13) incl. `RxAdvance`, `RxDupCurrent`, `RxOld`, `RxIllegal` |
| Data length | `int` 0..512 beside a `bytes[512]` buffer | `DataLen` 0..512 (M4) | `DataLen` 0..512 (M6) + `data_len_ok` on raw int | `DataLen` 0..512 (M5) |
| Packet / datagram length | not represented (T081 reason) | not represented (A:D3) | `total_len` (S4), `data_datagram_len` (S7), `udp_length_field` (S8) | `TftpLen` (M6), `data_len_of` (S4), `udp_length` (S5) |
| Payload content | opaque `bytes[512]` | none | none | none; `stream_len` for block lengths (S7) |
| TID | int, 0..65535 via `tid-valid` (T027) | `Tid` = Word16 (M2) | `Tid` 0..65535 (M5) | `Tid` 0..65535 + constant `WELL_KNOWN_TID = 69` (M3) |
| Peer identity | TID only (`tid-matches [conn src]`) | TID only (A:D14) | source TID only (B:D16) | host **and** TID (`same_host: bool`, C:D29) |
| TID binding | none: `conn` is given | `TidVerdict = TidMatch \| TidMismatch \| TidBind` + `peer_bound` (M13, S6) | `TidVerdict = TidOk \| TidDiscard \| TidDiscardAndError` (M12); binding via `init_response` | `TidVerdict = TvBind \| TvMatch \| TvStray` (M12) + `rx_binds_peer` (S22) |
| Port 69 | out (T041, T106) | absent | `request_dest_ok` (S10) | `WELL_KNOWN_TID`, `timeout_dst_tid` (S27) |
| Error codes (sent) | `int` 0..7 (`error-code-valid`) | `ErrCode` 8 tags + `ErrUnassigned` (M7) | `ErrCode` 8 tags (M7) | `ErrorCode` 8 tags (M8) |
| Error codes (received) | not modeled | `ErrUnassigned` (A:D34) | `ErrCodeCls = UnknownCode \| KnownCode(ErrCode)` (M8) | raw `ErrCode16`, never interpreted (M9, C:D16) |
| Error cause | bools `refused`, `fault`, `admissible` | bool oracles (`path_allowed`, `write_allowed`, `file_exists`, `overwrite_allowed`) | `ErrReason` 9 tags (M9) | `ReqVerdict` 7 tags (M16) + `LocalIo` 4 tags (M15) |
| Request verdict | `granted: bool` | `RequestVerdict = ReqGrant \| ReqDeny ErrCode \| ReqIgnore` (M16) | `ReqVerdict = ReqServe \| ReqIgnore \| ReqRefuse` (M13) | protocol `ReqClass = RqServe \| RqIgnore \| RqReject` (M17) + local `ReqVerdict` |
| First-reply verdict | none | via S11/S12 | `InitVerdict` (M14) | rows of `rx_class` under `TvBind` |
| Role | `Role = DataSender \| AckSender` | `Role` (requester/server, M8) × `Direction` (M9) → `Side` (M10) | `Direction` (M10) + `is_sender: bool` input; no role sort | `Role = RSender \| RReceiver` (M10) |
| Connection state | `XferState = Idle \| Transferring \| Terminating \| Completed \| Denied \| Terminated` | `Phase` 7: Listen, AwaitFirstReply, AwaitAck, AwaitData, Dally, Done, Aborted (M11) | `ConnState` 4: Requesting, Established, Dallying, Closed (M11) | `Phase` 6: AwaitFirst, Active, Dally, Done, Aborted, TimedOut (M11) |
| Outcome | `Completed` state | `Outcome` Pending/Success/Failed/Indeterminate (M17) | `Outcome` Completed/Failed/Unknown/Pending (M18) | folded into phase (`PhDone`, `PhTimedOut`, `PhAborted`) |
| Retry / timeout | none | `RetryCount` int + `max_retries`, `receiver_timer` (M18) | `retries_left: bool`, `ack_timer_enabled`, `TimeoutAct` (M17) | `retries_left: int`, `rx_timer`, `TimeoutAction` (M18) |
| Backoff | none | none (X1) | `Ticks` + `backoff_next` = 2×cur (M19, S22) | `rto_backoff` ≥ min(2·rto, rto_max) (S29) |
| Broadcast | none (T116 out) | `AddrClass` (M15) | `is_broadcast: bool` | `to_broadcast: bool` |
| Dally | none (T083: no dally) | `PhDally` + `dally: bool` | `Dallying` + `dally` | `PhDally`, always entered (C:D48) |
| Two-ended joint state | `spine-coupled`, `spine-implicit-ack` over `dblk`, `ablk` | none (X8) | none (X11) | none (X11, X13) |
| Delivery | none | none | none | `rx_delivers` (S23) |

### Material differences

1. **Block numbers: order and wrap.** Four different positions on two questions the RFC leaves open
   (1350:348-350 gives a 2-byte field; 1350:357-358 says "begin with one and increase by one";
   1350:359-360 says one number discriminates new packets from duplicates; nothing on 65535).
   - **A and C import an integer order** (A:D7, C:D43), arguing the order is the RFC's own
     ("increase by one"), and make it sound by forbidding the wrap (A:D1 precondition, C:D44 domain
     restriction). Both then split "not the expected block" into old and future.
   - **B imports a wrap** (65535 → 0, B:S13, B:D1), which no source line defines, and in exchange
     uses equality only (B:D21). B notes itself that the wrap breaks any order. Its `RecvOther`
     cannot tell an old block from a future one, so B must treat both the same (B:D22).
   - **R imports neither order nor wrap by its own account** (R:§8), but its block numbers are
     unbounded `int`s: `sender-next-block` must return `acked + 1` for every `acked >= 0`, so it
     demands block 65536, which the 2-byte field cannot carry. R imports an unbounded block space
     rather than a wrap. Like B, its equality-only stance makes old and future ACKs
     indistinguishable, so `sender-reply` answers every `ackblk ≠ acked` with `NoPacket` (T113
     clause, R:llmll:193).
   - What this changes: in A and C one can state "a DATA/ACK ahead of the lock step gets ERROR 4"
     and "an older one is dropped" separately. In R and B the only possible statements are about
     "the expected one" vs "anything else". B is also the only one where "next block = b + 1" is
     false at one point.
2. **What a step returns.** R and A return a constructed packet (`Packet`, `Action`) with an explicit
   "nothing" value. C returns an enum `Reply` and projects the block, code and destination into
   separate functions. B has **no response sort at all**. Whether anything is sent, and of which
   kind, is implied by verdict tags. This alone makes T069 and T070 unstatable over B (§3).
3. **Role.** R and C key the transfer on data sender vs data receiver. A keeps requester/server
   *and* direction and derives `Side`. B has no role sort: `is_sender` comes from outside
   (B:D20), so no step relates the request type to who sends data.
4. **Connection state granularity.** R separates `Denied` from `Terminated` and has a receiver-side
   `Terminating`. It has no dally state and no requester-side waiting state. A splits waiting into
   AwaitAck/AwaitData. B has four states and cannot tell a successful close from an aborted one
   (`Closed`). C has a separate `PhTimedOut` for the sender's undecided outcome.
5. **Requests.** R reduces the server's decision to `granted: bool` (+ `Mode`) and has no
   requester-side first-reply step. A, B, C all model the first reply and broadcast. B and C split
   the protocol-level verdict from the file-system verdict differently (B leaves the latter outside,
   B:D52; C takes it as `ReqVerdict`).
6. **Peer identity.** C alone requires the host to match as well as the TID (`same_host`, C:D29).
7. **Mode.** R's `Mode` has no "other" constructor, so an unknown mode is unrepresentable rather
   than refused. A, B, C carry `Other` so the refusal (A, C) or the policy (B) can be stated.
8. **Time.** R models no timeout event. A, B, C model the timer firing as an input event. B and C
   also model a backoff floor, and C adds a cap.

---

## 2. Decomposition

| Concern | R (23 functions) | A (31 steps) | B (27 steps) | C (29 steps) |
|---|---|---|---|---|
| Decode / format | `opcode-of`, `data-length-valid`, `error-code-valid`, `tid-valid` | S1-S5 (opcode, errcode both ways, side, is_final) | S1-S8 (classify opcode/mode/errcode, length checks, datagram/UDP length) | S1-S7 (opcode both ways, well-formedness, lengths, final test, block length from stream) |
| Request at server | `request-direction`, `request-next-state`, `request-reply` | S8 `server_on_request` (one step, all oracles), S9 `server_first_action`, S10 `initial_phase` | S9 `check_request`, S10 `request_dest_ok`; **no server reply step** | S8 `request_class`, S9 `request_reply`, S10 `request_error_code`, S11 `request_reply_block`, S12 `request_role` |
| Request at client | none | S10 (requester phase) | none (S20 covers retransmission) | S13 `client_request_ok`, S14 `client_role` |
| First reply (requester) | none | S11/S12 dedicated action + phase | S11 `init_response` | folded into `rx_class` (`TvBind` rows) |
| TID validation | `tid-matches`, `wrong-tid-next-state`, `wrong-tid-reply` (peer known) | S6 `check_tid` (binds on first reply), S20/S21 stranger action/phase | S12 `check_tid` (no binding; binding is `init_response`) | S15 `tid_verdict` + `rx_binds_peer`, `reply_dst_tid` |
| Data/ack loop, sender | `sender-next-block`, `sender-reply`, `sender-next-state` | S16-S19 action / phase / next block / length rule | S13 `next_block`, S18 `sender_on_ack` | one classifier S16 `rx_class` + projections S17-S24 keyed on `role` |
| Data/ack loop, receiver | `receiver-next-state`, `receiver-ack-block` | S13-S15 action / phase / next expected | S15 `recv_on_data`, S16 `recv_ack_block`, S17 `recv_advance` | same classifier and projections |
| Generic response rules | `step-responds`, `step-reply-kind` | none (per handler) | none | none (table) |
| Error handling | `error-next-state`, `error-reply`, `error-is-terminal`, `illegal-op-reply` | S22/S23 peer ERROR, S24/S25 bad packet, S26 local failure | S26 `err_code_for`, S27 `error_ends_transfer`, S28 `error_received_state` | classes `RxPeerError`, `RxIllegal`, `io` input on projections |
| Termination / dally | via `receiver-next-state`, `sender-next-state` | S14, S17, S27 (dally re-ACK), S31 `outcome_of` | S14, S23 `final_ack_state`, S24 `reack_final`, S25 `sender_outcome` | `rx_next_phase` + `timeout_next_phase` |
| Timeouts | none | S28-S30 | S20-S22 | S25-S29 |
| Two-ended | spine (2 functions) | none | none | none |

**Where the boundaries differ.**

- **Axis of decomposition.** R is cut by obligation: one function per group of inventory rows,
  sometimes with no event behind it (`step-responds`, `error-is-terminal`). A is cut by event ×
  output, with triples `_action`/`_next_phase`/`_next_*` (A:D46). B is cut by decision, one step per
  question a host answers (B:§0). C is cut by stage: one source check, one master classifier, and
  eight projections (C:D1, C:D3).
- **Classification first.** A and C classify before handling (A:D47, C:D3). B classifies only the
  receiver's DATA (`recv_on_data`); its sender step compares raw ints. R does not classify: it
  takes `dup`, `admissible`, `refused`, `fault` as bool inputs, so the classification itself has no
  contract.
- **The first reply** is its own step in A and B, a classifier row in C, and absent from R.
- **TID binding** happens in a different step in each vocabulary. A binds inside `check_tid` on any
  first reply. B binds in `init_response`. C binds through `rx_binds_peer` only on an acceptable
  first reply. R never binds (`conn` is a parameter).
- **Server's positive reply.** A has it (S9) and C has it (S9, S11). B has no step that emits the
  server's DATA 1 or ACK 0, so the obligations about it can only be restated from the requester's
  side (§3).
- **Error handling.** A splits errors by source (peer ERROR, malformed packet, local failure,
  stranger). B splits them into a reason→code table and a reason→terminates table, with no emission
  step. C classifies them into reply classes. R splits them by output (next state, reply, latch).
- **State transitions.** B deliberately has no transition table (B:D56). Only S23 and S28 return
  `ConnState`, so the post-state of a request, a stray packet or a local fault is not a function
  result in B.

---

## 3. Re-expressibility of R's 46 tagged obligations

**Rules used.** I judged the RFC obligation each tag carries, not R's particular formula.
- **yes**: one template sentence on one existing step, after renaming. A refinement precondition
  the vocabulary already declares (A:D1, C:D44) still counts as yes.
- **reshaped**: expressible, but only by splitting across steps, by restating from the other end, by
  needing a precondition the vocabulary's own semantics does not supply, or only through the same
  state proxy R itself uses.
- **no**: a needed sort, parameter or step is missing.
- **conflict**: a modeling decision of the vocabulary makes the obligation false in a case the
  source does not itself exempt. Where a vocabulary's exception rests on another source sentence
  (for example, a stray ERROR is not answered, 1350:106-107), I scored **yes** and recorded the
  exception under §4.

| Tag | Obligation (lines) | R function | A | B | C | Reason when not yes |
|---|---|---|---|---|---|---|
| T009 | only RRQ/WRQ open a connection (1350:89-90) | request-next-state | yes | yes | yes | |
| T010 | granted request opens connection (1350:90-92) | request-next-state | reshaped | **no** | reshaped | A: the grant is in S8, the opened phase in S10, and S10 has no grant parameter. B: no step returns the server's post-request state (B:D56), and the file-system half of the grant is outside (B:D52). C: "opened" is restated as `request_reply` returning RpData/RpAck under RvGrant; PhActive appears only in S12's prose |
| T011 | DATA carries one block; index advances (1350:92-93) | sender-next-block | yes | yes | yes | |
| T012 | lock step: DATA n+1 only after ACK n (1350:93-94) | sender-reply | yes | yes | yes | |
| T013 | < 512 bytes ends transfer (1350:94-95) | receiver-next-state | yes | yes | yes | |
| T016 | error terminates; latch (1350:105) | error-next-state | yes | yes | yes | |
| T017 | error signalled by ERROR packet (1350:105-106) | error-reply | yes | reshaped | yes | B has no emitting step: ReqRefuse (code 4, B:D8) covers the request half, and `err_code_for` gives only the code for a mid-transfer fault |
| T018 | ERROR not acked, not retransmitted (1350:106-107) | error-is-terminal | yes | reshaped | yes | B: only R's own state proxy (`error_received_state` = Closed). There is no reply output for a received ERROR, and the timer steps S20/S21 take no state |
| T022 | wrong source port does not terminate (1350:126-127) | wrong-tid-next-state | yes | yes | yes | B through `error_ends_transfer(RForeignTid) = false` |
| T023 | ERROR to originator of wrong-port packet (1350:128) | wrong-tid-reply | yes | yes | yes | all three exempt a stray ERROR (§4 Q39) |
| T027 | TID in 0..65535 (1350:152) | tid-valid | yes | yes | yes | |
| T030 | RRQ reads, WRQ writes; fixes direction (1350:184-186) | request-direction | yes | reshaped | yes | B: no request→sender function (B:D20); statable only via `init_response`'s expected first reply |
| T031 | positive reply: ACK for WRQ, DATA for RRQ (1350:186-187) | request-reply | yes | reshaped | yes | B: no server reply step; restated on the requester side, `init_response(WriteXfer, Ack, 0)` / `(ReadXfer, Data, 1)` = InitEstablished |
| T032 | ACK carries acknowledged block (1350:187-188) | receiver-ack-block | yes | yes | yes | |
| T033 | DATA blocks start at 1, consecutive (1350:188-190) | sender-next-block | yes | reshaped | yes | B: `next_block` wraps 65535→0 (B:D1), so the clause needs a `REQUIRES b < 65535` that B's own semantics does not give |
| T034 | ACK to WRQ carries 0 (1350:190-192) | request-reply | yes | reshaped | yes | B: as T031 |
| T035 | ERROR reply = request denied (1350:194-195) | request-next-state | yes | yes | yes | R puts it on the server's post-state; A, B, C put it on the requester (A: PhAborted; B: InitDenied; C: RxPeerError→PhAborted) |
| T045 | first DATA after WRQ/ACK is block 1 (1350:237-238) | sender-next-block | yes | yes | yes | B through `next_block(0) = 1` (B:D27) |
| T046 | check source TID (1350:239-241) | tid-matches | yes | yes | yes | C also requires the host to match |
| T047 | mismatched packet discarded (1350:241-242) | wrong-tid-next-state | yes | yes | yes | |
| T048 | ERROR to stray, transfer undisturbed (1350:242-244) | wrong-tid-next-state | yes | yes | yes | |
| T049 | opcodes 1..5 (1350:263-271) | opcode-of | yes | yes | yes | |
| T050 | header carries own opcode; nothing outside 1..5 (1350:273-274) | opcode-of | reshaped | reshaped | yes | A, B: decode direction only (raw→tag); there is no tag→opcode encoder. C has `kind_opcode`, with `REQUIRES kind ≠ KInvalid` |
| T062 | DATA is opcode 3 (1350:356-357) | opcode-of | yes | yes | yes | |
| T063 | blocks start at 1, +1 per block (1350:357-359) | sender-next-block | yes | reshaped | yes | B: as T033 |
| T064 | data field 0..512 (1350:361) | data-length-valid | yes | yes | yes | |
| T065 | 512 bytes continues (1350:361-362) | receiver-next-state | yes | yes | yes | |
| T066 | 0..511 ends (1350:362-363) | receiver-next-state | yes | yes | yes | |
| T067 | every packet but dup ACKs and termination packets is acknowledged (1350:366-367) | step-responds | **conflict** | **conflict** | **conflict** | A:D8 (stale DATA → ActNone). B:D22/D23 (RecvOther dropped; re-ACK of a duplicate only permitted; future ACK ignored). C:D37 (older DATA → RpNone). Each leaves a DATA packet unanswered that is neither a duplicate ACK nor a termination packet |
| T068 | DATA n+1 implicitly acks ACK n (1350:367-369) | spine-implicit-ack | reshaped | reshaped | reshaped | No vocabulary has a joint state (A:X8, B:X11, C:X11). Each can only restate it single-ended as the lock step (A:D31 → S16; B: `recv_advance`; C: RxAdvance + `rx_next_cur`) |
| T069 | WRQ/DATA answered by ACK or ERROR only (1350:369-370) | step-reply-kind | reshaped | **no** | reshaped | A: split over `server_first_action`/`server_on_request` and `receiver_on_data_action`. B: no output carries the answer's kind. C: `request_reply` plus `rx_reply` by role |
| T070 | RRQ/ACK answered by DATA or ERROR only (1350:370-381) | step-reply-kind | reshaped | **no** | reshaped | as T069. In B an ACK can never be answered by ERROR (future ACK → SendIgnore) |
| T072 | ACK is opcode 4 (1350:381-382) | opcode-of | yes | yes | yes | |
| T073 | ACK echoes DATA block (1350:382-384) | receiver-ack-block | yes | yes | yes | |
| T074 | ACK to WRQ is block 0 (1350:384-385) | request-reply | yes | reshaped | yes | B: as T031 |
| T077 | ERROR admissible from every state (1350:407-408) | error-next-state | yes | yes | yes | C ignores an ERROR in a closed phase (§4 Q50) |
| T078 | error code from table 0..7 (1350:409-410) | error-code-valid | yes | yes | yes | A needs `SHALL NOT return ActSendError ErrUnassigned` |
| T081 | 0..511 bytes marks end (1350:418-419) | receiver-next-state | yes | yes | yes | |
| T082 | final DATA ACKed like any DATA (1350:420) | receiver-ack-block | yes | yes | yes | |
| T087 | ACK of final DATA = success (1350:428-429) | sender-next-state | yes | yes | yes | |
| T089 | ERROR on ungrantable request or mid-transfer fault (1350:438-439) | error-reply | yes | reshaped | yes | B: as T017 |
| T090 | ERROR sent once (1350:439-440) | error-is-terminal | yes | reshaped | yes | B: as T018 |
| T101 | code 4 for illegal operation (1350:519) | illegal-op-reply | yes | yes | yes | |
| T113 | never resend DATA on duplicate ACK (1123:46-60) | sender-reply | yes | yes | yes | |
| T118 | MUST support octet (1123:196) | request-next-state | yes | yes | yes | |
| T120 | two complementary roles (1350:101-103) | spine-coupled | yes | reshaped | yes | B: no role sort, only `is_sender: bool` (B:D20, B:D59). R's coupling invariant `dblk ∈ {ablk, ablk+1}` cannot be stated in any of the three; only the role definition can |

### Totals (per distinct tag, 46)

| | yes | reshaped | no | conflict | expressible (yes + reshaped) |
|---|---:|---:|---:|---:|---:|
| A | 40 | 5 | 0 | 1 | **45** |
| B | 29 | 13 | 3 | 1 | **42** |
| C | 41 | 4 | 0 | 1 | **45** |

- **Expressible in all three: 42 of 46.** The four that are not are T067 (conflict in all three), and
  T010, T069, T070 (no in B).
- **Lost everywhere: 1, T067.** Every blind author independently chose to drop some DATA silently,
  and that contradicts the letter of 1350:366-367.
- **Never "yes" anywhere: T067 and T068.** Two R-specific encodings also survive nowhere: the joint
  "spine" content of T068 and T120. Only the single-ended reading of each survives.
- **B loses the most.** The losses come from two vocabulary-level choices, not from scattered gaps:
  there is no response sort, and there is no server-side reply step or post-request state. Ten of
  B's 13 "reshaped" tags are restatements from the requester side or through state proxies.

**Does R's clause set survive literally?** The obligations survive, but several of R's exact
formulas would be false if moved unchanged onto another vocabulary, because a blind author decided
a case differently:
- T113 (`ackblk ≠ acked ⇒ NoPacket`) is false in A and C, which answer a future ACK with ERROR 4.
- T023 (`src ≠ conn ⇒ ErrPkt 5`, with no packet-kind parameter) is false in A, B and C, which do not
  answer a stray ERROR.
- T016/T077 ("any state + ERROR ⇒ Terminated") is false in C from `PhDone`.
- T033/T063 (`result = acked + 1`, unbounded) is false in B at 65535.
- T067 is false in all three.

### Duplicate obligations inside R

FREEZE acknowledges three pairs that are the same obligation at two RFC locations: T032/T073,
T034/T074, T066/T081. Three more are the same obligation and are not acknowledged:
- T033/T063: "start at one, consecutive" and "start at one, increase by one", with identical formula
  `(= result (+ acked 1))`.
- T018/T090: "neither acknowledged nor retransmitted", with identical formula
  `(= result (= st Terminated))`.
- T013 with T066/T081: "< 512" and "0..511", equivalent under the `0 <= len <= 512` precondition.

Separately, some *different* obligations share one formula, so the second obligation adds no
checkable content of its own:
- T082 has the formula of T032/T073 (`(= result datablk)`): finality is not mentioned.
- T089 has the formula of T017.
- T048 has the formula of T047 (`(= result st)`): the ERROR it promises is in a different function.
- T062 and T072 are implied by T049. T045 and T011 are implied by T033. T077's clause is implied by
  T016's. T118's clause is implied by T010's (a granted octet request yields Transferring, so it is
  not Denied).

Collapsing the six obligation-level duplicates (T013, T063, T073, T074, T081, T090) leaves 40
distinct obligations. On that basis the scores are:
- A: 34 yes, 5 reshaped, 1 conflict.
- B: 26 yes, 10 reshaped, 3 no, 1 conflict.
- C: 35 yes, 4 reshaped, 1 conflict.
- Expressible in all three: 36 of 40.

---

## 4. Decisions

**Method.** Every D-row of A (49), B (60) and C (56) was assigned to a question, together with R's
recorded decisions (§8 boundaries, §9 trusted schema, §11 corrections, Amendment 1, FREEZE "model
shape") and the disposition reasons that state a resolved choice or an exclusion for that question.
An exclusion counts as a position.
- **E** = raised explicitly.
- **s** = position visible only from sorts or signatures.
- **—** = no position.

Verdicts:
- **agree**: the positions are compatible.
- **scope**: the positions are compatible, but one vocabulary excludes or parameterizes what
  another fixes, or represents it differently in a way that changes which clauses exist.
- **CONFLICT**: a clause true over one vocabulary is false over another.

| Q | Question | R | A | B | C | n | Verdict |
|---|---|---|---|---|---|---|---|
| 1 | Block number after 65535 | E: no rollover defined, successor unbounded (§8) | E: forbid, precondition (D1) | E: wrap to 0 (D1) | E: restrict domain (D44) | 4 | **CONFLICT** |
| 2 | Order on block numbers | E: none (§8) | E: integer order (D7) | E: equality only (D21) | E: integer order (D43) | 4 | **CONFLICT** |
| 3 | What is a "duplicate ACK" (incl. ACK 0 after DATA 1) | E: any ACK ≠ awaited (§9) | E: any older (D4, D9) | E: any ≠ outstanding (D25, D26) | E: any older (D39) | 4 | agree on old ACKs (future ones: Q5) |
| 4 | RFC 1123 SAS fix governs over 1350:95-98 | E (T113) | E (D4) | E (D25, D46) | E (D39) | 4 | agree |
| 5 | ACK ahead of the outstanding block | s: NoPacket (T113 clause) | E: ERROR 4, abort (D6) | E: ignore (D25) | E: ERROR 4, abort (D40) | 3 | **CONFLICT** |
| 6 | DATA ahead of the expected block | s: echoed (receiver-ack-block), must answer (T067) | E: ERROR 4, abort (D6) | E: drop (D22) | E: ERROR 4, abort (D38) | 3 | **CONFLICT** |
| 7 | DATA older than the last acknowledged | s: answered (T067) | E: drop (D8) | E: drop (D22) | E: drop (D37) | 3 | **CONFLICT** |
| 8 | Re-ACK a duplicate of the last DATA | s: echoed, must answer (T067) | E: required (D5) | E: permitted, not required (D23) | E: always (D36) | 3 | **CONFLICT** |
| 9 | DATA carrying block 0 | s: echoed as ACK 0 | s: Duplicate when expecting 1 → ACK 0 (S7, S13) | E: never new except after wrap (D2) | E: malformed, ERROR 4 (D10) | 2 | **CONFLICT** |
| 10 | Termination test: data length vs "Datagram length < 516" | E (T081) | E: data length (D3) | E: TFTP length (D28, D30) | E: TFTP length (D14) | 4 | agree |
| 11 | Size multiple of 512 → empty final DATA | s (T065) | E: required (D2) | E: implied (D29) | E: yes (D45) | 3 | agree |
| 12 | Initial counters (request as block 0; first DATA 1; small file) | s (T033 pre, T045) | E (D40, S10) | E (D27) | E (D2, D5) | 3 | agree |
| 13 | ACK echoes the block; "sequence" = "block" | s (T032) | E (D41) | E (D24) | s | 2 | agree |
| 14 | Opcode outside 1..5 | s: unrepresentable (decoder) | E: ERROR 4 (D36) | E: ERROR 4 / refuse at 69 (D33) | E: ERROR 4 (D7) | 3 | agree |
| 15 | Size violations (ACK ≠ 4, DATA > 516, short packet) | s: deployment-modeled | E (D36) | E (D31, D32) | E (D8, D9, D11) | 3 | agree |
| 16 | Trailing bytes after the request's mode NUL | — | E: malformed (D23) | E: tolerated (D32) | E: malformed (D12) | 3 | **CONFLICT** |
| 17 | Empty filename | — | E: malformed (D23) | E: illegal (D9) | s: not checked | 2 | agree |
| 18 | Malformed ERROR packet | — | s: ERROR 4 (S24) | s: ERROR 4 (D14 order, S4) | E: still a peer ERROR, no reply (D13) | 1 | **CONFLICT** |
| 19 | Byte order of 2-byte fields | s | s | s | E: big-endian, in decoder (D6) | 1 | agree |
| 20 | Wire boundary: decoded fields only; strings outside | E (§8) | E (X4) | E (X5, D10, D60) | E (X2) | 4 | agree |
| 21 | Mode case-folding outside; Mode is an enum | E (T054, §11) | E (D16) | E (D5) | E (D15) | 4 | agree |
| 22 | Unknown / extension mode | s: unrepresentable | E: refuse, code 4 (D17) | E: policy flag (D6) | E: refuse, code 4 (D20) | 3 | scope |
| 23 | Mail mode | E: out (T006, T111) | E: always deny (D18) | E: policy (D7) | E: policy `mail_enabled` (D17) | 4 | scope |
| 24 | Mail with RRQ | E: out (T058) | E: illegal (D18) | E: refuse (D7) | E: refuse (D18) | 4 | agree |
| 25 | netascii and octet are mandatory | E (T117, T118) | s | s (`mode_supported` scope unclear) | E (D19) | 2 | agree |
| 26 | Code for refused mode / malformed request / non-request at 69 | s: 4 (T101) | E: 4 (D17, D19) | E: 4 (D8) | E: 4 (D21-D23) | 3 | agree |
| 27 | ERROR packet arriving at port 69 | — | s | E: ignore (D12) | E: ignore (D22) | 2 | agree |
| 28 | Broadcast request (and its priority) | E: out (T116) | E: ignore (D22) | E: ignore, first (D11, D58) | E: ignore, first (D24) | 4 | scope |
| 29 | Grant = protocol check vs file-system decision | s: one bool | s: one step with oracles | E: file system outside (D52) | E: two verdicts (D25) | 2 | scope |
| 30 | Situation → code 1, 2, 3, 6 (7) | E: vectored constants (T097-T104) | E (D19, D39) | E (D35) | E (D25, D47) | 4 | agree |
| 31 | WRQ onto an existing file | s | E: flag (D20) | E: policy (D35) | E: environment (D25) | 3 | agree |
| 32 | Access control / pathname rules | E: out (T115) | E: bool oracle (D21) | E: outside (D57) | E: verdict input (X5, D25) | 4 | scope |
| 33 | Received error code > 7 | s | E: ErrUnassigned (D34) | E: UnknownCode (D34) | E: raw, ignored (D16) | 3 | agree |
| 34 | ERROR from the peer always terminates (incl. code 5) | s (T016, T077) | E (D33) | E (D37) | E (D31) | 3 | agree |
| 35 | Does sending ERROR terminate the sender ("may", 1350:107-108) | E: always (T019) | E: yes except ERROR 5 to stray (D32) | E: same (D36) | E: same (D42) | 4 | agree |
| 36 | Local resource failure mid-transfer | E: input flag (T021) | E: caller's code (D39) | E (D35) | E (D47) | 4 | agree |
| 37 | Wrong-kind packet on an established transfer | s: `admissible` (T101) | E: ERROR 4, abort (D35) | E (D13) | E (D41) | 3 | agree |
| 38 | Stray packet: discard + ERROR 5, state kept; inside the model | E (Amendment 1) | E (D10) | s | E (D33) | 3 | agree |
| 39 | Stray packet that is itself an ERROR | s: ERROR 5 anyway (no kind parameter on `wrong-tid-reply`) | E: no reply (D11) | E: no reply (D15) | E: no reply (D34) | 3 | **CONFLICT** |
| 40 | What the source check compares | s: TID | E: TID only (D14) | E: source TID only (D16) | E: host + TID (D29) | 3 | **CONFLICT** |
| 41 | Server checks against the requester's TID | s | E (D13) | s | s | 1 | agree |
| 42 | Which reply binds the peer TID | s: none, `conn` given | E: first reply of any type, incl. ERROR (D12) | E: first accepted reply (D17) | E: only well-formed DATA 1 / ACK 0 (D30) | 3 | **CONFLICT** |
| 43 | Unacceptable first reply while unbound | — | s: ERROR 4 + abort (S11, S12) | E: illegal (D19) | E: ERROR 5, keep waiting (D32) | 2 | **CONFLICT** |
| 44 | ERROR as reply to a request = denial | E: `Denied` state (T035) | E (D12) | E: InitDenied (D38) | E: from any source (D31) | 4 | agree |
| 45 | Supporting protocol may hide the TID error (1350:244-246) | E: assumes visible (Amendment 1) | s | E (D18) | s | 2 | agree |
| 46 | Server's TID may be 69 / 0 | s | E: any (D15) | E: no constraint (D3, D4) | E: not modeled (D27) | 3 | agree |
| 47 | Duplicate requests at the server | E: out (T121) | E: independent (D27) | E: outside (D55) | E: independent (D26) | 4 | scope |
| 48 | Check order: TID first | s | E (D48) | E (D14) | s: table row 1 | 2 | agree |
| 49 | Packets after close | s: latch | E: ignore (D49) | s | E: ignore (D35) | 2 | agree |
| 50 | ERROR arriving after successful completion | s: Completed → Terminated | s: PhDone → PhAborted, outcome Failed (S22, S31) | s: Closed | E: ignored in closed phases (D35, D49) | 1 | **CONFLICT** |
| 51 | Dallying | E: not modeled (T083-T085) | E: flag (D28) | E: flag (D39, D40) | E: always, zero-length allowed (D48) | 4 | scope |
| 52 | What is answered while dallying | — | E: only dup final DATA (S27) | E (D39) | E (D49) | 3 | agree |
| 53 | When the receiver has succeeded | s: `Terminating` | E: on final ACK (D29) | E: open (D42) | E: on entering dally (D50) | 3 | scope |
| 54 | Sender timing out on final DATA | E: out (T088) | E: Indeterminate (D30) | E: Unknown (D41) | E: PhTimedOut (D50) | 4 | scope |
| 55 | Timeout as input event; sender must, receiver may retransmit | E: out (T014, T086) | E (D25) | E (D45) | E (D51, D53) | 4 | scope |
| 56 | Receiver without a retransmit timer still gives up | — | E: yes (D25) | s: never (S21 TimeoutNothing) | E: yes (D56) | 2 | **CONFLICT** |
| 57 | Retry limit | E: out (T086, T088) | E: int + max (D24) | E: bool (D44) | E: int budget (D52) | 4 | scope |
| 58 | Retry counter reset | — | E: per accepted packet (D45) | s | s: no reset step | 1 | scope |
| 59 | Requester retransmits the request (same TID) | — | E (D26) | E (D43) | E (D28) | 3 | agree |
| 60 | What is retransmitted: last packet unchanged | E: out (T015) | E (D44) | s | E (D54) | 3 | agree |
| 61 | Adaptive timeout and backoff | E: out (T114) | E: out (X1) | E: ×2, no cap (D47-D49) | E: ×2 floor with cap (D55) | 4 | **CONFLICT** |
| 62 | Sender/receiver vs client/server as the main split | E (T120) | s (M8-M10) | E (D20, D59) | E (D2) | 3 | agree |
| 63 | Multiple outputs → one function each | E (FREEZE) | E (D46) | s | E (D1) | 3 | agree |
| 64 | Classify first, discriminate on tags | E (FREEZE) | E (D47) | s | E (D3) | 3 | agree |
| 65 | State set and state as loose parameters | s | s | E (D56) | E (D4) | 2 | scope |
| 66 | "Sending DATA acknowledges the first ACK" | E: own obligation on spine (T068) | E: no step of its own (D31) | — | — | 2 | scope |
| 67 | Two-ended / trace properties | E: spine + trusted schema (§8, §9) | E: out (X8) | E: out (X11) | E: out (X11, X13) | 4 | scope |
| 68 | Datagram/UDP length in the model | E: out (T107, T112) | E: out (D3) | E: modeled (D30) | E: modeled (D14) | 4 | scope |
| 69 | Port 69 in the model | E: out (T041, T106) | s: absent | E: predicate (D54) | s: constant | 2 | scope |
| 70 | 512 counts wire bytes after netascii | s | E (D37) | E (D50) | E (D46) | 3 | agree |
| 71 | Local mode may differ from wire mode | s | E (D38) | E (D51) | s | 2 | agree |
| 72 | Payload buffer modeled | E: `bytes[512]` (§8) | s: none | s: none | s: none | 1 | scope |
| 73 | Transport other than UDP | E: out (T001, T105) | E (X11) | E (D53) | E (X10) | 4 | agree |
| 74 | Strength of lowercase should/must/may | E (§2 rubric) | E (D10) | s | E (preamble) | 3 | agree |
| 75 | RFC 1123's RFC-783 references apply to 1350 | E (T008, §2) | E (D43) | s | s | 2 | agree |
| 76 | RFC 1123 SAS example "ACK X+3" typo | — | E (D42) | — | — | 1 | agree |
| 77 | "unless a timeout occurs" in 1350:366-367 | E: unconditional reading (T067) | — | — | — | 1 | agree |

### Totals

| Raised explicitly by | Questions | agree | scope / representation | CONFLICT |
|---|---:|---:|---:|---:|
| all four | 24 | 11 | 10 (Q23, 28, 32, 47, 51, 54, 55, 57, 67, 68) | 3 (Q1, 2, 61) |
| three | 29 | 19 | 2 (Q22, 53) | 8 (Q5, 6, 7, 8, 16, 39, 40, 42) |
| two | 16 | 9 | 4 (Q29, 65, 66, 69) | 3 (Q9, 43, 56) |
| one | 8 | 4 | 2 (Q58, 72) | 2 (Q18, 50) |
| **total** | **77** | **43** | **18** | **16** |

Only 24 of 77 questions were raised by everyone. Of those, 11 agree, and the three genuine
conflicts among them are the block-number questions and backoff. Most conflicts sit in questions
that only three authors raised and R decided silently in a signature (Q5-Q8, Q39), which is where a
frozen surface can embed a contested choice without anyone recording it.

### The genuine conflicts (candidate questions for a human)

1. **Q1. Block number after 65535.** Source: 1350:348-350 (Block # is 2 bytes) and 1350:357-358
   ("begin with one and increase by one"); silent on overflow. Choices: wrap to 0 (B:D1); forbid
   and refuse large files (A:D1); restrict the domain (C:D44); unbounded successor (R:llmll:171-182,
   while R:§8 says no rollover is defined).
2. **Q2. Is there an order on block numbers?** Source: 1350:357-360. Choices: integer order is the
   RFC's own (A:D7, C:D43); no order, equality only (R:§8, B:D21).
3. **Q5. ACK ahead of the outstanding DATA.** Source: 1350:119-122 (a packet "which cannot be
   explained by a delay or duplication" is an error) vs 1123:46-60 (do not resend on a duplicate
   ACK). Choices: ERROR 4 and abort (A:D6, C:D40); ignore (B:D25); no packet (R's T113 clause).
4. **Q6. DATA ahead of the expected block.** Source: 1350:119-122. Choices: ERROR 4 and abort (A:D6,
   C:D38); silent drop (B:D22); R echoes an ACK for any block and must answer (T067).
5. **Q7. Older DATA.** Source: 1350:366-367 ("All packets other than duplicate ACK's and those used
   for termination are acknowledged"), 1350:27. Choices: drop silently (A:D8, B:D22, C:D37); answer
   (R's T067 clause).
6. **Q8. Re-ACK of the last DATA's duplicate.** Source: 1350:366-367, 1350:423-426, 1123:126-133.
   Choices: required (A:D5, C:D36, R by T067); optional outside dally (B:D23).
7. **Q9. DATA with block 0.** Source: 1350:189-190, 357-358. Choices: duplicate, re-ACK 0 (A,
   silently); drop, but new after a wrap (B:D2); malformed, ERROR 4 (C:D10).
8. **Q16. Trailing bytes after a request's mode string.** Source: 1350:287-292, silent. Choices:
   malformed (A:D23, C:D12); tolerated (B:D32).
9. **Q18. Malformed ERROR packet.** Source: 1350:106-107, 399-414. Choices: still a terminating peer
   ERROR, unanswered (C:D13); answered with ERROR 4 by check order (A:S24; B:D14 with S4).
10. **Q39. Stray packet that is itself an ERROR.** Source: 1350:128, 242-243 ("An error packet should
    be sent to the source of the incorrect packet") vs 1350:106-107 ("This packet is not
    acknowledged"). Choices: no reply (A:D11, B:D15, C:D34); ERROR 5 regardless (R:llmll:347-352,
    no packet-kind parameter).
11. **Q40. What identifies the peer.** Source: 1350:239-246 ("source TID matches"; "sent from
    somewhere else"). Choices: TID only (R, A:D14, B:D16); host and TID (C:D29).
12. **Q42. Which reply binds the requester to the server's TID.** Source: 1350:207-210, 253-254.
    Choices: the first reply of any type, including ERROR (A:D12); the first accepted reply
    (B:D17); only a well-formed DATA 1 or ACK 0 (C:D30).
13. **Q43. Unacceptable first reply while unbound.** Source: 1350:119-122 vs 239-246. Choices: ERROR
    4 and abort (A:S11/S12; B:D19 "illegal"); ERROR 5 and keep waiting (C:D32).
14. **Q50. ERROR after successful completion.** Source: 1350:434 ("In any case, the connection has
    been closed"). Choices: latch to error (R: `error-next-state` from `Completed`; A:S22 turns
    `PhDone` into `PhAborted`, so `outcome_of` reports Failed); ignore (C:D35, D49).
15. **Q56. Does a receiver without a retransmit timer ever give up?** Source: 1350:109-110, 441
    ("Timeouts must also be used to detect errors"), 1123:128-133. Choices: yes, always a give-up
    path (A:D25, C:D56); no, `TimeoutNothing` forever (B:S21). C's own S28 defeats its D56 (§6.3).
16. **Q61. Backoff cap.** Source: 1123:139-144 ("At least an exponential backoff"). Choices: doubling
    with no cap (B:D47); doubling floor capped at `rto_max`, flagged as an import (C:D55); not modeled
    (R:T114, A:X1).

---

## 5. Exclusions

| Topic | R | A | B | C |
|---|---|---|---|---|
| Clock values, timer durations, dally length | out | out (X1) | out (X1) | out (X1) |
| Timeout *event*, retransmission decision | **out** (T014, T086, T088, T091) | modeled (S28-S31) | modeled (S20-S21) | modeled (S25-S28) |
| Adaptive timeout / backoff | out (T114) | out (X1) | floor modeled; estimator out (X2) | floor + cap modeled; estimator out (X1) |
| Retry count value | out | parameter | out (X3; bool) | parameter, initial value out |
| Dally | **out** (T084, T085; T083 resolved as no dally) | modeled | modeled; exit out (X18) | modeled |
| Random TID choice | out (T037, T040) | out (X3) | out (X4) | out (X9) |
| TID allocation, port 69 rendezvous | out (T036, T040-T044, T106) | out (implicit) | partly in (`request_dest_ok`) | partly in (`WELL_KNOWN_TID`, `reply_dst_tid`) |
| Source-TID validation | in (Amendment 1) | in | in | in |
| Second response to a duplicated request | **out** (T121) | in (stranger path) | in (D17) | in (D30, D32) |
| Code 5 rule as such | **out** (T102), yet emitted (T023) | in | in | in |
| Byte parsing, NUL-terminated strings, field widths | out (B5, deployment-modeled) | out (X4) | out (X5) | out (X2) |
| Packet length checks | not represented | bool input | in (S4) | in (S3) |
| Datagram / UDP length | out (T107, T112) | out (D3) | in (S7, S8) | in (S4, S5) |
| UDP/IP headers, checksum, encapsulation | out (T024, T029, T123) | out (X2) | out (X9) | out (X10) |
| Broadcast rule | **out** (T116) | in, detection outside | in, detection out (X15) | in, detection outside (X10) |
| netascii translation | out (T004, T055) | out (X4) | out (X7) | out (X3) |
| File contents, octet round trip, file system | out (T057) | out (X6) | out (X7, X8) | out (X4) |
| Filenames, path access control, server rights | out (T053, T109, T115) | oracle bools (X5) | out (X6, X16) | verdict input (X5) |
| Mail mode | out (T006, T058, T059, T104, T111) | refused (X9) | in with policy; recipient syntax out (X13) | in with policy; delivery out (X6) |
| Extensions / extra modes | out (T007, T060, T119, T124) | out (X9, X10) | out (X14) | out (X8) |
| Error message text | out (T079, T080) | out (X5) | out (X19) | out (X7) |
| Concurrent connections, server table | out | out (X7) | out (X17) | out (X12) |
| Network loss / duplication / reorder | out (C6); duplicate delivery in spine alphabet | out (X2) | out (X10) | out (X11) |
| Two-ended / trace properties | **in** per step, closure trusted (§9) | out (X8) | out (X11) | out (X11, X13) |
| Block → byte offset, stream length | none | `has_more` bool | out (X12) | in (S7) |
| Payload bytes | in (opaque `bytes[512]`) | none | none | none |
| Performance / bootstrap remarks | out (T110) | out (X12) | out (X20) | out (X14) |
| Other datagram transports | out (T001, T105) | out (X11) | out (D53) | out (X10) |

**Overlap.**
- **Excluded by all four (13 topics):** clock values, random TID choice, byte parsing, UDP/IP
  headers, netascii translation, file contents, extensions, error text, concurrency, the network
  itself, performance remarks, other transports, and pathname semantics (as a string problem).
- **Excluded only by R:** the timeout event and retransmission, dally, the duplicate-request
  rejection, the broadcast rule, and the code-5 rule. Each of these is something all three blind
  authors could state, so R's barrier list (B1 timing, B2 transport) is drawn wider than the target
  forced.
- **Modeled only by R:** the two-ended spine and the payload buffer.
- **Split decisions:** datagram/UDP length (R and A out, B and C in); backoff (R and A out, B and C
  in); port 69 (R and A out, B and C partly in); block-to-offset (B out, C in).

---

## 6. Errors

### 6.1 Clearly contradicted by the source text

1. **R:T006 states the mail rule as "must not"; the source says "should not".**
   VERIFICATION_SCOPE line 223 gives the obligation as "An implementation must not implement or use
   the mail transfer mode". The source, 1350:80-81, reads: "(The mail mode is obsolete and should
   not be implemented or used.)". The same row's reason quotes "should not" correctly and then says
   "RFC 1123 4.2.2.1 forbids it", but 1123:28 reads "The transfer mode "mail" SHOULD NOT be
   supported." The strength word is raised from should to must, against R's own rubric (§2: "the
   strength word is recorded per row").
2. **R's block successor demands a block number the field cannot hold.** `sender-next-block`
   (R:llmll:171-182) has `pre (>= acked 0)` and `post (= result (+ acked 1))` with no upper bound,
   so at `acked = 65535` it requires block 65536. 1350:348-350 fixes "2 bytes | Block #". The RFC
   is silent on what happens at the limit, but it is not silent on the width. R:§8's claim that
   "no clause ... imports" a rollover holds only because the clause imports an unbounded domain
   instead.

No statement in A, B or C is clearly contradicted by the text. Their citations check out against the
line numbers, including A:D42's observation that 1123:102 and 1123:106 print "Send ACK X+3" where the
sequence requires X+2.

### 6.2 Contradicted by the letter, defensible in spirit (flagged, not counted as errors)

- **Silent drop of older or duplicate DATA** (A:D8, B:D22, B:D23, C:D37) against 1350:366-367:
  "All packets other than duplicate ACK's and those used for termination are acknowledged unless a
  timeout occurs [4]". Also 1350:27: "Each nonterminal packet is acknowledged separately." This is
  the reason T067 is a conflict in §3.
- **"RFC 1123 overrides RFC 1350's may-retransmit-on-duplicate rule"** (R:T113, R:llmll:186-187 and
  :194; C:D39; B:D25). 1350:43-44 says RFC 1350 itself is "The May, 1992 revision to fix the
  'Sorcerer's Apprentice' protocol bug [4]", and 1350:366-367 already exempts duplicate ACKs. The
  conflict is inside RFC 1350, between 95-98 ("thus causing the sender of the lost packet to
  retransmit") and 366-367, rather than between the two RFCs. A alone avoids the override framing.
- **B:S21, a receiver without a timer never times out,** against 1350:441: "Timeouts must also be
  used to detect errors." 1123:128-131 permits removing the receiver's *retransmission* timer, which
  is not obviously the same timer.
- **R:T070** (`step-reply-kind`: every ACK is answered by DATA or ERROR) has no duplicate-ACK
  exemption, against 1350:366 and 1123:46-60. It is consistent only if read as "if answered, then
  by DATA or ERROR", because the function cannot return "nothing". R's own T067 and T113 carry the
  exemption.
- **R:T104** ties code 7 to mail recipients. 1350:522 says only "No such user.", and 1350:119-120
  lists "no such user" among ordinary request failures. C:D25/Q14 raises exactly this question.

### 6.3 Internal inconsistencies (not source contradictions, but checkable)

- **R: mail.** `tftp.llmll:70-73` declares `Mode` with `(| Mail)`. The disposition reasons say "no
  mail constructor exists to verify" (T006, line 223), "no mail transfer exists in the model" (T058,
  line 275) and "the model has no mail mode to verify" (T111, line 328). Nothing in
  `request-next-state` refuses a granted Mail request.
- **R: code 5.** T102 is dispositioned out because "unknown transfer ID ... is transport identity the
  model does not carry" (line 319). Amendment 1 (§8) put the TID pair in the model, and
  `wrong-tid-reply` emits `(ErrPkt 5)` under T023 (R:llmll:347-352). The same applies to T121
  (line 338) against T046-T048.
- **R: T087 cannot fire.** The clause conditions on `st = Terminating` for the sender, but only the
  receiver's step (`receiver-next-state`) produces `Terminating`.
- **A: outcome after dally.** A:D29 says the receiver's outcome is Success once the final ACK is
  sent, "also from PhDally". A:S31 `outcome_of` maps only `PhDone` to Success and everything else
  live to Pending. Separately, A:S22 sends `PhDone` to `PhAborted` on a late ERROR, which A:D49 does
  not prevent, because it governs the action only.
- **C: give-up path.** C:D56 promises a timer-less receiver "always has a give-up path (ToGiveUp
  when the budget is 0)". But C's `timeout_action` returns `ToNone` for such a receiver, and
  C:S28 `timeout_retries` decrements only on `ToResend`. So the budget never reaches 0, and C
  behaves like B on Q56.

---

## 7. Summary

Three blind authors and the frozen reference R agree on the protocol core:
- opcodes, 0..512 data lengths and the < 512 termination test;
- ACK echoing, the WRQ ACK 0 and the first DATA 1;
- the error latch with its single wrong-TID exception;
- the RFC 1123 duplicate-ACK rule.

They diverge sharply at the edges. Of 77 distinct modeling questions, only 24 were raised by all
four. Overall, 43 positions agree, 18 differ only in representation or scope, and 16 genuinely
conflict. The deepest conflict is the block number: A and C import an integer order and forbid the
wrap, B imports a wrap to 0 and keeps equality only, and R imports neither but leaves the successor
unbounded. That one choice decides whether "ahead of the lock step" (ERROR 4) can be told apart from
"behind it" (drop), and it produces four further conflicts on out-of-window DATA and ACKs.

Against R's 46 tagged obligations, A and C can state 45 each and B 42; 42 survive in all three.
B's losses come from two structural choices, not from scattered gaps: it has no response sort, and
it has no server reply step or post-request state. One obligation, T067, is lost everywhere: every
blind author independently chose to drop some DATA silently, against the letter of 1350:366-367.
R's two-ended spine content (T068, T120) survives nowhere. Several R clauses would be falsified if
moved literally (T113, T023, T016/T077, T033/T063), because blind authors decided a case R decided
silently in a signature.

R has one clear strength error (T006 "must not" for the source's "should not") and one
width-blind successor (`sender-next-block` at 65535). It also has internal inconsistencies around
mail, code 5 and T087.
