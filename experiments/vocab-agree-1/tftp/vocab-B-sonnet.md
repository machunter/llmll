# Vocabulary for RFC 1350 (TFTP rev 2) with RFC 1123 s4.2

Citations: `A:n` = rfc1350.txt line n; `B:n` = rfc1123-s4.2.txt line n.
Notation: `f [x: T ...] -> R`. "Policy flag" = a bool parameter whose value is decided outside the model.

## 0. How the algorithm is divided

The RFC describes one lock-step protocol (A:89-103) that has three phases and two roles per connection.
I cut it so that each step is one *decision a host makes on one event*, taking already-decoded field values.

- Packet intake (A:287-414): decode raw fields into enums (`classify_*`), then check length and opcode legality.
  Byte-level parsing is outside, so all offsets are inputs.
- Connection set-up (A:182-259): server's judgement of a request (`check_request`), requestor's judgement of the first reply (`init_response`).
- Lock-step transfer (A:89-103, A:356-385): sender and receiver are separate functions because the RFC treats them asymmetrically (B:46-48 fixes only the sender).
  The TID check (A:239-246) is its own step because it gates all other processing and is the one non-fatal error (A:126-128).
- Termination (A:416-441, A:105-124): final-block test, dally, outcome, error codes and which errors end the transfer.
- Timers: the clock is outside, but *what to do when the timer fires* and *how the next timeout relates to the last* are decisions, so they are steps over an abstract `Ticks` int.

## 1. Sorts (M-rows)

| Id | Sort | Definition | Reason | RFC |
|---|---|---|---|---|
| M1 | `Opcode` | enum `Rrq` `Wrq` `Data` `Ack` `Error` | the five packet types, wire values 1..5 | A:266-271 |
| M2 | `OpcodeCls` | sum `BadOp` / `GoodOp(Opcode)` | the opcode field is 2 bytes, so values 0 and 6..65535 exist and must be classified | A:155, A:273 |
| M3 | `Mode` | enum `Netascii` `Octet` `Mail` `OtherMode` | the three defined modes plus "defined by cooperating hosts" | A:73-82, A:298-300, A:334-345 |
| M4 | `Block` | `(where [v: int] (and (>= v 0) (<= v 65535)))` | 2-byte field; 0 is legal only in ACK | A:348-351, A:189-192 |
| M5 | `Tid` | `(where [v: int] (and (>= v 0) (<= v 65535)))` | TIDs are UDP ports | A:150-152 |
| M6 | `DataLen` | `(where [v: int] (and (>= v 0) (<= v 512)))` | data field is 0..512 bytes | A:361-364 |
| M7 | `ErrCode` | enum `ENotDefined` `EFileNotFound` `EAccess` `EDiskFull` `EIllegalOp` `EUnknownTid` `EFileExists` `ENoUser` (0..7 in order) | the eight defined codes | A:511-522 |
| M8 | `ErrCodeCls` | sum `UnknownCode` / `KnownCode(ErrCode)` | the field is 2 bytes; received values outside 0..7 exist | A:401, A:407-410 |
| M9 | `ErrReason` | enum `RFileMissing` `RNoPermission` `RNoSpace` `RMalformed` `RUnexpectedOp` `RForeignTid` `RFileExists` `RUnknownUser` `ROther` | the *situation* that causes an ERROR; several situations share a code, so this is not isomorphic to M7 | A:119-124, A:511-522 |
| M10 | `Direction` | enum `ReadXfer` `WriteXfer` | what the requestor asked for (RRQ vs WRQ); fixes who sends data | A:184-186, A:89-103 |
| M11 | `ConnState` | enum `Requesting` `Established` `Dallying` `Closed` | the only connection facts the RFC names: request sent, TIDs agreed, waiting after the last ACK, ended | A:197-210, A:421-426, A:434 |
| M12 | `TidVerdict` | enum `TidOk` `TidDiscard` `TidDiscardAndError` | accept, drop silently, or drop and answer ERROR 5 to the sender | A:239-246 |
| M13 | `ReqVerdict` | enum `ReqServe` `ReqIgnore` `ReqRefuse` | server's reaction to a packet at the listening port | A:184-195, B:161-162 |
| M14 | `InitVerdict` | enum `InitEstablished` `InitDenied` `InitIllegal` | requestor's reaction to the first reply | A:184-195 |
| M15 | `RecvAct` | enum `RecvNew` `RecvDupLast` `RecvOther` | receiver's classification of an incoming DATA block number | A:358-360, A:425-426 |
| M16 | `SendAct` | enum `SendAdvance` `SendComplete` `SendIgnore` | sender's reaction to an ACK | A:366-385, B:46-48 |
| M17 | `TimeoutAct` | enum `TimeoutRetransmit` `TimeoutAbort` `TimeoutNothing` | what a fired timer does | A:94-98, A:427-434, B:128-135 |
| M18 | `Outcome` | enum `Completed` `Failed` `Unknown` `Pending` | the sender's knowledge about the end of a transfer | A:427-434 |
| M19 | `Ticks` | `(where [v: int] (>= v 1))` | abstract timeout length, unit-free; no clock is modeled | B:139-144 |

19 sorts. Mutually exclusive classification enums are used instead of strings or ints (tool manual: compare enums).

## 2. Steps

Every step is pure and total. "ok" results never carry more than one payload.

### Intake
- **S1** `classify_opcode [raw: int] -> OpcodeCls` : 1..5 map to `GoodOp`, anything else `BadOp`. A:266-271.
- **S2** `classify_mode [is_netascii: bool, is_octet: bool, is_mail: bool] -> Mode` : booleans are the outcome of the case-insensitive string comparison done outside; priority netascii, octet, mail, else `OtherMode`. A:298-300.
- **S3** `classify_errcode [raw: int] -> ErrCodeCls` : 0..7 known, else `UnknownCode`. A:513-522.
- **S4** `packet_len_ok [op: Opcode, total_len: int] -> bool` : length in bytes from the opcode onward. ACK exactly 4; DATA 4..516; ERROR at least 5; RRQ/WRQ at least 6. A:287-289, A:348-351, A:373-375, A:399-402.
- **S5** `data_len_ok [payload_len: int] -> bool` : 0 <= payload_len <= 512. A:361.
- **S6** `opcode_in_transfer [is_sender: bool, op: Opcode] -> bool` : sender accepts `Ack` and `Error`, receiver accepts `Data` and `Error`; request opcodes are never valid inside an established transfer. A:366-372, A:407-408.
- **S7** `data_datagram_len [len: DataLen] -> int` : TFTP packet length of a DATA with that payload, `len + 4`. A:348-351, A:419.
- **S8** `udp_length_field [tftp_len: int] -> int` : value of the UDP Length field, `tftp_len + 8`. B:32-33, A:547.

### Set-up
- **S9** `check_request [op: Opcode, mode: Mode, mode_supported: bool, name_len: int, is_broadcast: bool] -> ReqVerdict` : server-side judgement of a packet that arrived on the listening port. A:184-195, A:296-313, B:28, B:161-162.
- **S10** `request_dest_ok [dst: Tid] -> bool` : true iff `dst = 69`. A:206-207, A:545.
- **S11** `init_response [dir: Direction, op: Opcode, blk: Block] -> InitVerdict` : requestor's judgement of the first reply: `WriteXfer` expects `Ack` with block 0, `ReadXfer` expects `Data` with block 1, `Error` means denied, everything else illegal. A:184-195, A:231-236, A:487-491.
- **S12** `check_tid [src: Tid, peer: Tid, is_error_pkt: bool] -> TidVerdict` : `src = peer` gives `TidOk`; otherwise `TidDiscard` if the offending packet is itself an ERROR, else `TidDiscardAndError`. A:239-246, A:105-110.

### Lock-step
- **S13** `next_block [b: Block] -> Block` : successor; 65535 wraps to 0. A:358-360, A:189-190.
- **S14** `data_is_final [len: DataLen] -> bool` : `len < 512`. A:361-364, A:418-419.
- **S15** `recv_on_data [last_acked: Block, got: Block] -> RecvAct` : `got = next_block(last_acked)` gives `RecvNew`; `got = last_acked` and not new gives `RecvDupLast`; all else `RecvOther`. `last_acked` is 0 at start. A:358-360.
- **S16** `recv_ack_block [act: RecvAct, last_acked: Block, got: Block] -> Block` : block number to put in the ACK: `got` for `RecvNew` and `RecvDupLast`, `last_acked` for `RecvOther` (value is a placeholder, no ACK is sent). A:383-385.
- **S17** `recv_advance [act: RecvAct, last_acked: Block, got: Block] -> Block` : new `last_acked`; `got` iff `RecvNew`, else unchanged. A:358-360.
- **S18** `sender_on_ack [cur: Block, got: Block, cur_final: bool] -> SendAct` : `cur` is the block of the outstanding DATA. `got = cur` gives `SendComplete` if `cur_final` else `SendAdvance`; any other `got` gives `SendIgnore` (never retransmit). B:46-48, A:383.
- **S19** `opcode_expected_after [dir: Direction, is_requestor: bool] -> bool` is NOT a step (see D13); use S6.

(Counted steps skip S19; numbering continues.)

### Timers
- **S20** `sender_on_timeout [retries_left: bool] -> TimeoutAct` : `TimeoutRetransmit` if `retries_left` else `TimeoutAbort`. A:94-99, A:427-431, B:134-135.
- **S21** `recv_on_timeout [ack_timer_enabled: bool, retries_left: bool] -> TimeoutAct` : not enabled gives `TimeoutNothing`; enabled gives retransmit-last-ACK or abort like S20. A:94-98, B:128-135.
- **S22** `backoff_next [cur: Ticks] -> Ticks` : `2 * cur`, the minimal conforming exponential backoff. B:139-144.

### Termination and errors
- **S23** `final_ack_state [dally: bool] -> ConnState` : after the receiver sends the ACK of the final DATA: `Dallying` if dally else `Closed`. A:421-426.
- **S24** `reack_final [st: ConnState, final_data_again: bool] -> bool` : true iff `st = Dallying` and the final DATA arrived again. A:425-426.
- **S25** `sender_outcome [acked_final: bool, got_error: bool, gave_up: bool] -> Outcome` : priority `Completed` (acked), `Failed` (error), `Unknown` (gave up), else `Pending`. A:427-434.
- **S26** `err_code_for [r: ErrReason] -> ErrCode` : `RFileMissing`->1, `RNoPermission`->2, `RNoSpace`->3, `RMalformed`/`RUnexpectedOp`->4, `RForeignTid`->5, `RFileExists`->6, `RUnknownUser`->7, `ROther`->0. A:511-522, A:119-124.
- **S27** `error_ends_transfer [r: ErrReason] -> bool` : false only for `RForeignTid`. A:105-110, A:126-128, A:243-244.
- **S28** `error_received_state [st: ConnState] -> ConnState` : always `Closed`. A:105-110, A:407-410.

Step count: S1-S18 plus S20-S28 = 27 steps (S19 deliberately absent, kept as a numbering note only).

## 3. Modeling decisions (D-rows)

**D1 Block wrap-around.** Q: what follows block 65535? Alt: unbounded int; wrap to 0; wrap to 1; refuse/ERROR; file too large. Choice: `Block` is 0..65535 and `next_block` wraps to 0 (plain mod 2^16). RFC says only "increase by one" in a 2-byte field and never states a limit. A:351, A:358-360.
**D2 Block 0 in DATA.** Block sort includes 0 because ACK needs it. Choice: DATA with block 0 is never `RecvNew` (since next_block(x)=0 only at wrap, see D1; the wrap case is accepted). A:189-194, A:358, A:384-385.
**D3 TID range and TID 0.** Q: is TID 0 valid? Choice: sort admits 0..65535, no exclusion of 0, since A:152 gives the range and nothing else. A:150-153.
**D4 Server's first-reply TID vs 69.** Q: may the server's chosen TID equal 69 or the client's? Choice: no constraint expressed; TID choice is outside (X). A:197-210.
**D5 Mode matching.** Q: case-insensitive match "in any combination of upper and lower case". Alt: strings in the model; booleans; enum from outside. Choice: the case-fold comparison is outside; `classify_mode` takes three booleans and defines priority netascii > octet > mail for overlapping flags (flags should be exclusive; priority only makes the function total). A:298-300.
**D6 Other modes.** Q: does a server accept additional modes? Alt: always refuse; accept; unspecified. Choice: `OtherMode` exists, acceptance is the policy flag `mode_supported`. A:81-82, A:334-345, B:148-151, B:198.
**D7 Mail mode.** Q: mail with RRQ; mail with WRQ. RFC: must begin with WRQ (A:309-310), obsolete and SHOULD NOT (A:80-81, B:28, B:197). Choice: mail with RRQ is `ReqRefuse` regardless of flag; mail with WRQ follows `mode_supported`. The "username@hostname" form is not checked (X).
**D8 Which error for refused requests.** Q: unsupported mode, mail via RRQ, DATA/ACK sent to port 69. RFC gives no mapping. Alt: code 0, 2, 4, 5. Choice: all are `ReqRefuse` and answered with `RMalformed` (code 4); for non-request opcodes at the listening port code 5 was considered (source TID unknown to the server) but rejected as 5 is defined for packets within a connection. A:519-520.
**D9 Empty filename.** Q: is a zero-length filename legal? Alt: legal; illegal. Choice: `name_len >= 1` required, else `ReqRefuse`. The RFC says only "sequence of bytes ... terminated by a zero byte". A:296-297.
**D10 Filename and netascii content.** Q: non-netascii bytes in filename. Choice: not checked (byte parsing, X). A:296.
**D11 Broadcast request.** RFC: SHOULD be silently ignored (B:161-162). Choice: `ReqIgnore`, taking priority over every other verdict, applied to RRQ/WRQ (and any other opcode: also ignored). How broadcast is detected is outside.
**D12 ERROR at the listening port.** Choice: `ReqIgnore` (ERROR is never answered, A:106-107, A:440-441).
**D13 Unexpected opcode inside a transfer.** Q: what counts as illegal. Choice: S6 only admits the one data-bearing opcode for the role plus ERROR; the rest are RMalformed/RUnexpectedOp (code 4), as a packet "which cannot be explained by a delay or duplication". RRQ/WRQ in an established connection are illegal. A:119-122, A:366-372, A:407-408.
**D14 Check order for an incoming packet.** RFC does not give an order. Choice: (1) `check_tid` (A:239-242 "discarded as erroneously sent"), (2) `classify_opcode`, (3) `opcode_in_transfer`, (4) `packet_len_ok` and `data_len_ok`, (5) the role step. Consequence: a malformed packet from a foreign TID gets code 5, not 4.
**D15 Foreign-TID packet is an ERROR.** Q: reply with ERROR to an ERROR? Alt: yes; no. Choice: no, `TidDiscard` (ERROR is not acknowledged, A:106-107). A:240-246.
**D16 TID check scope.** Q: check source only, or also destination. Choice: source against the agreed peer TID only; destination port is fixed by the datagram layer. A:239-241.
**D17 When the peer TID becomes known.** Choice: the first accepted reply fixes the peer TID (`init_response` = `InitEstablished`); `check_tid` is used from then on. For a duplicated request, the first reply wins and later ones go through `check_tid` with `TidDiscardAndError`. A:207-210, A:248-259.
**D18 TID check availability.** RFC: may not arise if the underlying protocol hides it. Choice: model assumes the source TID is visible. A:245-246.
**D19 First reply of the requestor.** Q: legal first replies. Choice: S11 table (write: ACK block 0; read: DATA block 1; ERROR denial; else illegal). ACK with nonzero block to a WRQ and DATA to a WRQ are illegal. A:184-195, A:231-236, A:487-491.
**D20 Who the sender is.** Choice: connection has exactly one sender, determined by `Direction` and by who requested (WRQ requestor sends, RRQ server sends); steps take `is_sender` from outside, no step derives it. A:101-103.
**D21 Duplicate vs new DATA without order.** RFC: "a single number to discriminate between new packets and duplicates" (A:359-360) but no ordering on blocks is defined (and wrap, D1, breaks one). Choice: `recv_on_data` uses equality only: successor of last acked is `RecvNew`, equal to last acked is `RecvDupLast`, anything else `RecvOther`.
**D22 Handling `RecvOther`.** Q: ERROR 4, or silent drop. A genuinely old duplicate is "explained by delay", a future block is not, and equality cannot tell them apart. Choice: the step returns `RecvOther`; contracts must treat it as "drop, no state change, no ACK". A:119-122, A:105-110.
**D23 Re-ACK of duplicate DATA.** Choice: on `RecvDupLast` re-sending the ACK of that block is permitted; not required except while dallying (S24). Not forbidden by B:46-48, which restricts only the sender. A:95-98, B:128-135.
**D24 ACK number content.** Choice: ACK echoes the block of the DATA acknowledged (`recv_ack_block`). A:383-385.
**D25 Sender reaction to unmatched ACK.** RFC 1350 text lets either side resend on a duplicate (A:95-98); RFC 1123 forbids the sender to resend the current DATA on duplicate ACK (B:46-49). Choice: `SendIgnore` for every `got != cur`, whether old (duplicate) or future. Includes a repeated ACK 0 at the start of a write. B:46-60.
**D26 What "duplicate ACK" means.** Choice: any ACK that does not acknowledge the outstanding DATA; a second copy of the current ACK arrives after `cur` has already advanced, so it falls under the same rule. B:46-49.
**D27 Which block is "current".** Choice: `cur` is the block of the outstanding DATA; before the first DATA exists the sender is in `Requesting`/start and uses `init_response`, then `next_block(0) = 1`. A:237-239.
**D28 Last block test.** `len < 512` final, including `len = 0`. A:361-364, A:418-419.
**D29 File size multiple of 512.** Q: must the sender emit a trailing zero-length DATA? RFC implies it (0..511 means end) but never states it. Choice: modeled by `data_is_final` only; the obligation on sender about the trailing empty block is left for contracts to state in terms of the final test. A:361-364.
**D30 What "Datagram length < 516" means.** A:419 says length < 516; 516 = 4 + 512, which is a TFTP packet length, but B:32-33 says UDP length includes the 8-byte header. Choice: all lengths in the model are TFTP-packet lengths (opcode onward); `data_datagram_len` = len+4, and S8 gives UDP Length = +8 as corrected by RFC 1123. A:419, B:32-33.
**D31 Oversize DATA.** Q: payload > 512. Alt: truncate; ERROR 4; accept. Choice: `data_len_ok` false means illegal (code 4); `DataLen` makes oversize unrepresentable inside the step. A:361.
**D32 Packet length bounds.** Choice: ACK exactly 4 (trailing bytes illegal); DATA 4..516; ERROR >= 5 (empty message allowed); RRQ/WRQ >= 6 with no upper bound and trailing bytes after the mode NUL tolerated. RFC silent on maxima and trailing bytes. A:287-289, A:373-375, A:399-402.
**D33 Opcode out of range.** Choice: `BadOp`; inside a connection it is an ERROR 4 case; at port 69 it is `ReqRefuse`. A:273, A:519.
**D34 Error code domain.** Choice: wire value outside 0..7 is `UnknownCode`; a received ERROR with an unknown code still terminates (S28). A:511-522.
**D35 Mapping situations to codes.** RFC lists codes but not the triggering rules. Choice: S26 table; disk full and allocation exceeded both 3; access denied during transfer 2; "File already exists" 6 for a WRQ over an existing file (server policy); "no such user" 7. A:119-124, A:511-522.
**D36 Which errors terminate.** Choice: every error except `RForeignTid` ends the transfer for the host that sends it; sending is a courtesy, termination is not conditional on delivery. The RFC says a host "may terminate after sending" (A:107-108) and also that most errors "cause termination" (A:105); I take the second. A:105-110, A:126-128, A:243-244.
**D37 Receiving ERROR.** Choice: any ERROR from the accepted TID ends the transfer, no reply (S28), in every state. A:407-410.
**D38 ERROR as reply to a request.** Choice: `InitDenied`. A:194-195.
**D39 Dally.** RFC: terminating after the final ACK is allowed; dallying encouraged. Choice: `dally` is a policy flag; `Dallying` state; in it, final DATA repeated gives a re-ACK (S24), in other states false. A:421-426.
**D40 End of dally.** Choice: leaves `Dallying` by timer only, which is outside; no step. (X)
**D41 Sender's final outcome.** Choice: ACK of the final DATA means `Completed`; ERROR means `Failed`; giving up without either means `Unknown` (RFC says both success and failure are possible). A:427-434.
**D42 Receiver's view of success.** RFC silent; no step. Open.
**D43 Retransmit of the request itself.** Choice: while `Requesting` the requestor treats the request as its "current packet", so S20 applies (timeout retransmits). The server must tolerate duplicates (two connections, A:248-259); that is server table state, outside. A:366-370.
**D44 Retry limit.** RFC gives none ("not prepared to retransmit any more", A:431). Choice: a bool `retries_left`, the count is policy (X).
**D45 Receiver timer.** B:128-135 says the receiver's timer may be removed or kept. Choice: policy flag `ack_timer_enabled`; if on, its action is retransmitting the last ACK. B:128-135.
**D46 Effect of the Sorcerer fix on recovery.** With D25 a lost DATA is recovered only by the sender's own timeout, since the receiver's re-ACK of the previous block is ignored by the sender. Choice: accepted; stated here so contracts do not demand recovery on receipt of an old ACK. A:95-98, B:46-48.
**D47 Backoff factor and cap.** "At least an exponential backoff" (B:143-144), unit unspecified. Choice: factor 2, no cap, minimal conforming; contracts should state `>= 2 * cur` and not equality if they wish to allow better algorithms.
**D48 Adaptive timeout.** B:139 MUST use adaptive timeout; B:142 TCP is "a useful base". Choice: only the backoff floor is modeled; estimator and reset on success are excluded (X).
**D49 Units of Ticks.** Choice: no unit, minimum 1; the RFC has no time constants.
**D50 What 512 counts.** Choice: wire bytes after any netascii translation; translation itself is outside. A:300-308, A:361.
**D51 Mode after request.** Choice: mode is fixed by the request and never appears again; no step uses it after set-up. Differing modes at each end (A:315-332) are local matters. A:315-332.
**D52 Meaning of "request grants".** `ReqServe` means "packet is acceptable"; whether the file exists or is permitted is a file-system fact outside, and a failure is then reported with the `ErrReason` table (D35). A:119-124.
**D53 Transport.** Choice: UDP semantics (TID = port, 16 bits); other datagram protocols are not modeled although allowed. A:62-63, A:150-153.
**D54 Port 69.** Choice: constant, as a predicate only (`request_dest_ok`); client-side acceptance of other ports is not an error action. A:206-207, A:545.
**D55 Simultaneous connections.** Choice: all state is per connection; no step sees another connection. A:248-259.
**D56 Connection state set.** Choice: four states (M11). Not modeled as a transition table; transitions are carried by the steps that produce `ConnState` (S23, S28) and by the events outside (requests, dally timer).
**D57 Access control and pathnames.** B:155-157 SHOULD be configurable. Choice: outside; it enters only as `RNoPermission`/`mode_supported`-style policy. (X)
**D58 Mixed-priority in `check_request`.** Choice order: broadcast (ignore) > opcode not RRQ/WRQ (ERROR ignored, else refuse) > mail rules > empty name > mode support. Reason: RFC gives no precedence but ignoring first is the only reading that cannot create a security hole (B:164-178).
**D59 Both-ends-sender claim.** A:101-103 says both hosts are "senders and receivers". Choice: per connection one data sender, one data receiver; each host plays both only as a function of ACK vs DATA.
**D60 Error packet content.** Choice: message text and its netascii form are outside; message length is only counted in S4. A:411-414.

60 D-rows (D-ids are not contiguous in importance; D40 and D42 are explicit non-steps).

## 4. Exclusions (X-rows)

- **X1** Time: clocks, timer expiry as a measurement, dally length, timeout durations. Outside the tool. A:94-98, A:424-426.
- **X2** Adaptive timeout estimation and reset (RTT-style). B:139-144.
- **X3** Retry count policy. A:431.
- **X4** Random TID selection and its quality ("very low probability" of repeat). Needs randomness/probability. A:199-201.
- **X5** Byte-level packet parsing: finding the NUL after the filename, mode position, string lengths. Offsets depend on bytes in the same packet. A:287-289, A:399-402.
- **X6** Case-insensitive string comparison of mode and the filename/pathname semantics. A:298-300, A:296.
- **X7** File content transfer, netascii translation, octet round-trip identity ("must be identical"). A:300-308.
- **X8** File-system and disk effects (existence, permissions, disk full). A:119-124.
- **X9** UDP/IP headers, checksum, local-medium header, fragmentation. A:137-153, A:524-552.
- **X10** Network loss, reordering, duplication as a model of the channel; only its consequences on single events are modeled.
- **X11** Whole-transfer properties: all blocks delivered in order, termination, liveness. They need quantifiers or induction over a trace.
- **X12** Block-to-offset mapping (512*(n-1)) and file-size-to-block-count (division). Needs file content.
- **X13** Mail recipient syntax and mail forwarding. A:309-313.
- **X14** Extensions and extra modes (passwords, secure mode). B:148-151, A:334-345.
- **X15** Broadcast-address detection, address/port plumbing, where an ERROR is sent. B:161-178.
- **X16** Access control configuration. B:155-157, A:581-588.
- **X17** Server's table of live connections and duplicated-request handling. A:248-259.
- **X18** Dally exit and ConnState transition table beyond S23/S28 (D40, D56).
- **X19** Error message text and netascii requirement. A:411-414.
- **X20** Performance remarks (window of one, bandwidth-delay). B:8-14.

## 5. Open questions for the RFC author

1. Which block follows 65535: 0 or 1 or none? What of files over 65535 blocks?
2. For a file whose size is a multiple of 512, must a final zero-length DATA be sent? (A:361-364 implies yes.)
3. On receiving a DATA whose block is not the expected one and not the last acked, is an ERROR 4 required or a drop?
4. Is "Datagram length < 516" a UDP length (then it should be < 524) or a TFTP length? (A:419 vs B:32-33.)
5. After the Sorcerer fix, who recovers a lost DATA 1 after an RRQ: only the requestor's request retransmit?
6. Which error code answers an unsupported or unknown mode, a mail RRQ, or a non-request packet at port 69?
7. Must a host stop after sending an ERROR ("may terminate", A:107) or is it required ("most errors cause termination", A:105)?
8. Is an empty filename legal? May a filename be longer than a datagram allows?
9. May ACK or DATA packets carry trailing bytes? May request packets?
10. Does the receiver have a defined notion of success or failure at the end, given dally is optional?
11. When a packet from a foreign TID is itself malformed, is the ERROR code 5 or 4?
12. Is TID 0 legal? May the server's TID equal 69 or the client's TID?
13. Is the ERROR packet from a foreign TID to be ignored or does it count as "any other ERROR"? (A:407 vs A:240-242.)
14. "At least exponential backoff": does a capped backoff conform?
15. May a client accept a first reply from a port other than the one used by the first valid reply when two replies race (A:248-259)?
