# TFTP (RFC 1350 + RFC 1123 §4.2) — vocabulary

Sources. `1350:N` means `rfc1350.txt` line N; `1123:N` means `rfc1123-s4.2.txt` line N (file-relative,
i.e. RFC 1123 line 2543+N).

Scope in one sentence: one TFTP connection (one transfer), seen from one host, as a sequence of pure
decisions "given the decoded fields of the packet that just arrived (or a timeout event) and the facts
of my current state, what do I send and what state am I in next". Byte decoding, strings, time,
the file system and the network are outside; their results enter as enum tags, bounded ints and bools.

---

## 1. Sorts (M-rows)

| ID | Sort | Constructors / refinement | Reason | RFC |
|---|---|---|---|---|
| M1 | `Word16` | `(where [v: int] (and (>= v 0) (< v 65536)))` | Opcode, Block #, ErrorCode and TIDs are all 2-byte fields | 1350:155, 287, 348, 373, 399, 152 |
| M2 | `Tid` | alias of `Word16` | TIDs are passed to UDP as ports, "must be between 0 and 65,535" | 1350:150-152, 203-204, 554-555 |
| M3 | `BlockNum` | alias of `Word16` | Block # is a 2-byte field; 0 occurs only in the ACK of a WRQ | 1350:189-192, 357-358, 384-385 |
| M4 | `DataLen` | `(where [v: int] (and (>= v 0) (<= v 512)))` | Data field is 0..512 bytes; 512 = not last, 0..511 = last | 1350:361-363, 418-419 |
| M5 | `Opcode` | enum `OpRrq \| OpWrq \| OpData \| OpAck \| OpError \| OpInvalid` | Five packet types; `OpInvalid` is the decoded tag for any 2-byte value outside 1..5 | 1350:263-271, 466-482 |
| M6 | `Mode` | enum `ModeNetascii \| ModeOctet \| ModeMail \| ModeOther` | Three defined modes, case-insensitive; `ModeOther` covers locally defined / unknown modes | 1350:73-82, 297-300, 334-345; 1123:28, 148-151 |
| M7 | `ErrCode` | enum `ErrNotDefined \| ErrFileNotFound \| ErrAccess \| ErrDiskFull \| ErrIllegalOp \| ErrUnknownTid \| ErrFileExists \| ErrNoSuchUser \| ErrUnassigned` | Codes 0..7 in the table; `ErrUnassigned` is the decoded tag for a received value 8..65535 | 1350:409-412, 511-522 |
| M8 | `Role` | enum `RoleRequester \| RoleServer` | Who sent the RRQ/WRQ to TID 69 vs who answered | 1350:197-210 |
| M9 | `Direction` | enum `DirRead \| DirWrite` | RRQ = requester reads from server; WRQ = requester writes to server | 1350:184-187 |
| M10 | `Side` | enum `SideDataSender \| SideDataReceiver` | "both machines are senders and receivers": one sends DATA, the other sends ACK; derived from Role x Direction | 1350:101-103 |
| M11 | `Phase` | enum `PhListen \| PhAwaitFirstReply \| PhAwaitAck \| PhAwaitData \| PhDally \| PhDone \| PhAborted` | Lock-step state of one end; `PhDally` is the optional wait after the final ACK; `PhDone`/`PhAborted` are terminal | 1350:89-104, 237-238, 416-434, 436-441 |
| M12 | `Action` | sum `ActNone \| ActSendData int \| ActSendAck int \| ActSendError ErrCode \| ActRetransmit \| ActRejectStranger` | What one step emits. `ActSendData b`/`ActSendAck b` carry the block number; `ActRetransmit` re-sends the single packet on hand; `ActRejectStranger` sends ERROR 5 to the mismatched source without touching the connection | 1350:96-100, 128, 241-244, 438-441 |
| M13 | `TidVerdict` | enum `TidMatch \| TidMismatch \| TidBind` | Result of the source-TID check; `TidBind` is the first reply, which fixes the peer TID | 1350:207-210, 239-246 |
| M14 | `BlockClass` | enum `BlkExpected \| BlkDuplicate \| BlkStale \| BlkFuture` | Block number relative to lock-step state: the one I wait for, the one just handled, older (delayed), or not explainable by delay/duplication | 1350:357-360, 119-122; 1123:46-60 |
| M15 | `AddrClass` | enum `AddrUnicast \| AddrBroadcast` | Destination address class of an incoming request, decided outside | 1123:159-162 |
| M16 | `RequestVerdict` | sum `ReqGrant \| ReqDeny ErrCode \| ReqIgnore` | Server's answer to RRQ/WRQ: open a connection, refuse with ERROR, or silently drop | 1350:89-91, 195, 438-439; 1123:159-162 |
| M17 | `Outcome` | enum `OutPending \| OutSuccess \| OutFailed \| OutIndeterminate` | §6 makes the data sender's result indeterminate when it times out after the final DATA | 1350:427-434 |
| M18 | `RetryCount` | `(where [v: int] (>= v 0))` | Counter of consecutive timeouts in a phase; limit is a configuration parameter (see D24) | 1350:96-98, 427-428 |
| M19 | `NextBlock` | `(where [v: int] (and (>= v 1) (< v 65536)))` | Block numbers of DATA begin at 1 and are in the Word16 field | 1350:189-190, 357-358 |

Booleans used as inputs (not separate sorts): `well_formed` (decoder accepted the layout: zero
terminators present, DATA <= 512, no trailing bytes), `path_allowed`, `write_allowed`, `file_exists`,
`overwrite_allowed`, `has_more` (sender has another block to read), `receiver_timer` (configuration),
`peer_bound` (peer TID already fixed).

---

## 2. Steps

### How the algorithm is divided

The RFC describes one lock-step loop run by two symmetric ends. I split it along three axes, each
because the target forces or rewards it:

1. **By event**: one step per kind of event an end can face (request at port 69, first reply,
   DATA, ACK, ERROR, stranger packet, malformed packet, timeout). Each RFC obligation is about one
   event, so one clause can attach to one step.
2. **By output**: a step that would return "packet to send + next phase + next counter" is split
   into `*_action`, `*_next_phase`, `*_next_*` functions with the same parameters, because a
   constructor cannot carry two fields (D47).
3. **By classification first**: TID check, opcode decoding and block classification are their own
   small steps returning enums; the handlers then take those enum tags as parameters and
   discriminate on them, instead of re-deriving them from ints (tool constraint on matching).

### Step list

Decoding / classification

| ID | Signature | Purpose | RFC |
|---|---|---|---|
| S1 | `opcode_of [raw: Word16] -> Opcode` | 1..5 to the five tags, anything else to `OpInvalid` | 1350:266-271 |
| S2 | `errcode_of [raw: Word16] -> ErrCode` | 0..7 to tags, 8..65535 to `ErrUnassigned` | 1350:513-522 |
| S3 | `errcode_value [e: ErrCode] -> Word16` | encode a code for sending (precondition: `e` is not `ErrUnassigned`) | 1350:513-522 |
| S4 | `side_of [role: Role, dir: Direction] -> Side` | requester+read and server+write are data receivers; the others are data senders | 1350:101-103, 184-187 |
| S5 | `is_final [len: DataLen] -> bool` | `len < 512` | 1350:361-363, 418-419 |
| S6 | `check_tid [peer_bound: bool, expected: Tid, src: Tid] -> TidVerdict` | bind on first reply, otherwise compare | 1350:207-210, 239-243 |
| S7 | `classify_block [expected: int, got: BlockNum] -> BlockClass` | `got = expected` -> Expected; `got = expected - 1` -> Duplicate; `got < expected - 1` -> Stale; else Future | 1350:357-360, 119-122 |

Connection setup

| ID | Signature | Purpose | RFC |
|---|---|---|---|
| S8 | `server_on_request [op: Opcode, mode: Mode, addr: AddrClass, well_formed: bool, path_allowed: bool, write_allowed: bool, file_exists: bool, overwrite_allowed: bool] -> RequestVerdict` | grant, deny with which code, or silently ignore a request at TID 69 | 1350:89-91, 195, 309-310, 516-522, 583-588; 1123:28, 155-162 |
| S9 | `server_first_action [dir: Direction] -> Action` | on grant: RRQ -> `ActSendData 1`; WRQ -> `ActSendAck 0` | 1350:184-195, 234, 384-385, 490 |
| S10 | `initial_phase [role: Role, dir: Direction] -> Phase` | requester -> `PhAwaitFirstReply`; server after RRQ grant -> `PhAwaitAck` (for block 1); server after WRQ grant -> `PhAwaitData` (for block 1) | 1350:184-195, 237-238 |
| S11 | `requester_first_reply_action [dir: Direction, op: Opcode, got: BlockNum, len: DataLen] -> Action` | WRQ+ACK 0 -> `ActSendData 1`; RRQ+DATA 1 -> `ActSendAck 1`; ERROR -> `ActNone`; anything else -> `ActSendError ErrIllegalOp` | 1350:184-195, 231-238, 487-491 |
| S12 | `requester_first_reply_next_phase [dir: Direction, op: Opcode, got: BlockNum, len: DataLen] -> Phase` | companion of S11 (WRQ -> `PhAwaitAck`; RRQ -> `PhAwaitData`, or `PhDally`/`PhDone` if DATA 1 is final; ERROR or illegal -> `PhAborted`) | same |

Steady state

| ID | Signature | Purpose | RFC |
|---|---|---|---|
| S13 | `receiver_on_data_action [phase: Phase, cls: BlockClass, got: BlockNum, len: DataLen] -> Action` | Expected -> `ActSendAck got`; Duplicate -> `ActSendAck got` (re-ACK); Stale -> `ActNone`; Future -> `ActSendError ErrIllegalOp` | 1350:92-94, 120-122, 359-360, 420-426; 1123:126-133 |
| S14 | `receiver_on_data_next_phase [phase: Phase, cls: BlockClass, len: DataLen, dally: bool] -> Phase` | Expected+final -> `PhDally` (if `dally`) else `PhDone`; Future -> `PhAborted`; otherwise unchanged | 1350:418-426 |
| S15 | `receiver_next_expected [expected: int, cls: BlockClass] -> int` | `expected + 1` on Expected, else unchanged | 1350:357-359 |
| S16 | `sender_on_ack_action [phase: Phase, cls: BlockClass, current: NextBlock, current_len: DataLen, has_more: bool] -> Action` | Expected and current not final -> `ActSendData (current+1)`; Expected and final -> `ActNone`; Duplicate/Stale -> `ActNone` (Sorcerer's Apprentice fix); Future -> `ActSendError ErrIllegalOp` | 1350:92-94, 366-369, 381-384, 427-429; 1123:46-60, 119-126 |
| S17 | `sender_on_ack_next_phase [phase: Phase, cls: BlockClass, current_len: DataLen] -> Phase` | Expected+final -> `PhDone`; Future -> `PhAborted`; else unchanged | 1350:427-429 |
| S18 | `sender_next_block [current: NextBlock, cls: BlockClass] -> int` | `current + 1` on Expected, else unchanged (precondition at the wrap, D1) | 1350:357-359 |
| S19 | `next_data_len_ok [has_more: bool, len: DataLen] -> bool` | a non-last block has exactly 512 bytes; the last has 0..511 (so a file of 512k bytes ends with an empty block) | 1350:91-95, 361-363 |

Errors, strangers, malformed packets, termination

| ID | Signature | Purpose | RFC |
|---|---|---|---|
| S20 | `on_stranger_action [op: Opcode] -> Action` | packet with `TidMismatch`: `ActRejectStranger`, except an ERROR from a stranger -> `ActNone` | 1350:126-128, 239-259 |
| S21 | `on_stranger_next_phase [phase: Phase] -> Phase` | identity: a stranger never disturbs the transfer | 1350:126-128, 243-244, 255-259 |
| S22 | `on_error_packet_next_phase [phase: Phase] -> Phase` | any ERROR from the peer -> `PhAborted`; no reply | 1350:105-108, 195, 407-408, 439-440 |
| S23 | `on_error_packet_action [phase: Phase] -> Action` | always `ActNone` (ERROR is not acknowledged) | 1350:105-108, 439-440 |
| S24 | `on_bad_packet_action [phase: Phase, op: Opcode, well_formed: bool] -> Action` | from the peer: `OpInvalid`, not well formed, RRQ/WRQ on a transfer TID, or a packet of the wrong side's kind (DATA to a data sender, ACK to a data receiver) -> `ActSendError ErrIllegalOp` | 1350:119-122, 520 |
| S25 | `on_bad_packet_next_phase [phase: Phase] -> Phase` | -> `PhAborted` (premature termination) | 1350:105, 119-122, 436-439 |
| S26 | `on_local_failure_action [code: ErrCode] -> Action` | lost resource during transfer (disk full, access lost) -> `ActSendError code`; phase -> `PhAborted` via S25 | 1350:123-124, 438-439, 518 |
| S27 | `in_dally_on_data_action [cls: BlockClass, got: BlockNum] -> Action` | in `PhDally`, duplicate of the final DATA -> `ActSendAck got`; anything else -> `ActNone` | 1350:423-426 |

Timeouts (the event is an input; time itself is not modelled)

| ID | Signature | Purpose | RFC |
|---|---|---|---|
| S28 | `on_timeout_action [phase: Phase, side: Side, retries: RetryCount, max_retries: RetryCount, receiver_timer: bool] -> Action` | below the limit: data sender and requester-awaiting-reply -> `ActRetransmit`; data receiver -> `ActRetransmit` only if `receiver_timer`; at the limit -> `ActNone` | 1350:95-98, 427-428; 1123:126-135 |
| S29 | `on_timeout_next_phase [phase: Phase, side: Side, retries: RetryCount, max_retries: RetryCount] -> Phase` | at the limit -> `PhAborted`; in `PhDally` the timeout ends the dally -> `PhDone` | 1350:422-426, 427-434, 441 |
| S30 | `on_timeout_next_retries [retries: RetryCount] -> RetryCount` | `retries + 1`; any accepted Expected packet resets to 0 (stated on S15/S18 companions) | 1350:427-428 |
| S31 | `outcome_of [phase: Phase, side: Side, timed_out_after_final: bool] -> Outcome` | `PhDone` -> Success; `PhAborted` -> Failed, except a data sender aborted by timeout while the final DATA is unacknowledged -> Indeterminate; else Pending | 1350:427-434 |

Count: 31 steps.

---

## 3. Modeling decisions (D-rows)

| ID | Question | Alternatives | Choice | RFC |
|---|---|---|---|---|
| D1 | What happens after block 65535? The field is 2 bytes, the RFC only says "increase by one". | (a) forbid: files > 65535x512-1 bytes cannot be sent; (b) wrap to 0; (c) wrap to 1; (d) leave unspecified | (a): `sender_next_block` has precondition `current < 65535` when not final; a sender that would need block 65536 must abort with `ErrNotDefined` (or `ErrDiskFull`? see Q1). Wrap would break the ordering D7 relies on. | 1350:357-360, 348-350 |
| D2 | File size that is a multiple of 512: is a 0-byte final DATA required? | (a) required; (b) last full block counts as final | (a): a 512-byte block always means "not last", so an empty final block is required (S19). | 1350:361-363, 418-419 |
| D3 | Termination test: data length or datagram length? §6 says "Datagram length < 516", which counts neither the UDP header (1123 correction) nor anything else consistently. | (a) `data_len < 512`; (b) `udp_len < 524`; (c) `tftp_len < 516` | (a): the only form free of the UDP-length erratum; datagram length is outside the vocabulary. | 1350:361-363, 418-419, 547; 1123:30-33 |
| D4 | What is a "duplicate ACK" for the Sorcerer's Apprentice rule? | (a) `got = current - 1` only; (b) any `got < current`; (c) any ACK not equal to `current` | (b) for "never resend": Duplicate and Stale both yield `ActNone` in S16. The MUST is phrased for duplicate ACK; ignoring older ones too is the only reading that cannot re-trigger the loop. | 1123:46-60, 119-126 |
| D5 | Does the data receiver re-ACK a duplicate DATA? | (a) yes, re-send ACK of that block; (b) ignore | (a): needed for dallying ("will know the ACK has been lost if it receives the final DATA again") and harmless once senders ignore duplicate ACKs. Applies to every block, not only the final one. | 1350:423-426; 1123:126-133 |
| D6 | DATA or ACK with a block number ahead of the lock step (Future). | (a) ERROR 4 and terminate; (b) discard silently | (a): it "cannot be explained by a delay or duplication". | 1350:119-122, 359-360 |
| D7 | Can the vocabulary use `<` on block numbers? (tool: do not import an undefined order) | (a) equality only (Expected / last / Other); (b) integer order | (b): the RFC defines block numbers as starting at 1 and increasing by one, so the order is the RFC's. Valid only because of D1 (no wrap). | 1350:189-190, 357-360 |
| D8 | Stale DATA/ACK (older than the last handled block). | (a) discard; (b) re-ACK; (c) error | (a) for both sides: explainable by delay; re-ACKing an old DATA would send an ACK that the sender ignores anyway. | 1350:119-122; 1123:62-66 |
| D9 | ACK 0 arriving at the writer after DATA 1 was sent (duplicate of the WRQ answer). | (a) Duplicate -> ignore; (b) illegal | (a): `classify_block` treats 0 as `expected - 1` when current = 1; SAS fix forbids resending DATA 1. | 1350:384-385; 1123:46-60 |
| D10 | Wrong-TID packet: SHOULD or MUST, and what exactly is sent? | (a) discard + ERROR 5 to the source; (b) discard only | (a) as the specified behaviour (`ActRejectStranger`), state unchanged. The "should" wording is noted as a strength gap for the clause writer. | 1350:126-128, 239-246, 521 |
| D11 | ERROR packet arriving from a wrong TID. | (a) answer with ERROR 5; (b) ignore | (b): ERRORs are never acknowledged, and answering them risks an ERROR ping-pong between strangers. | 1350:105-108, 239-244 |
| D12 | Which reply binds the peer TID for the requester? | (a) first reply of any type, including ERROR; (b) first valid positive reply | (a): an ERROR reply also comes from the server's chosen TID and denies the request; anything later from another TID is a stranger. | 1350:195, 207-210, 248-259 |
| D13 | TID check for the server: against what? | (a) the requester's source TID from the RRQ/WRQ; (b) nothing | (a): "the hosts" (plural) check source TID from step 3 onward. | 1350:205-210, 239-241 |
| D14 | Only the port (TID) is checked, not the host address. | (a) TID only; (b) host+TID | (a): the RFC speaks only of TIDs; addresses are outside the vocabulary. See Q4. | 1350:239-246 |
| D15 | Server's chosen TID: may it be 69, may it be 0? | (a) any Word16; (b) exclude 69; (c) exclude 0 | (a): the RFC states the range 0..65535 and nothing else. Random choice is not modelled (X3). | 1350:150-152, 197-201 |
| D16 | Case-insensitive mode strings. | (a) decode outside to `Mode`; (b) model strings | (a): steps receive a `Mode` tag; clauses compare enums. | 1350:297-300 |
| D17 | Unknown mode string. | (a) deny with ERROR 4; (b) deny with ERROR 0; (c) grant as octet | (a) `ReqDeny ErrIllegalOp`; locally agreed modes would be added as constructors, not handled by `ModeOther`. | 1350:82, 334-345; 1123:148-151 |
| D18 | Mail mode. | (a) deny; (b) implement (WRQ only, recipient lookup, error 7) | (a): "obsolete and should not be implemented", SHOULD NOT in 1123. `ModeMail` stays as a constructor so the denial can be stated; if granted (not chosen), RRQ+mail would be illegal. | 1350:80-81, 309-313, 522; 1123:28, 197 |
| D19 | Which error code for which refusal? The table names codes but never maps situations to them. | many | not found -> 1; path not allowed or writes disabled -> 2; WRQ to existing file without overwrite -> 6; malformed request / bad mode -> 4. | 1350:119-124, 513-522, 583-588; 1123:155-157 |
| D20 | WRQ for an existing file. | (a) overwrite; (b) ERROR 6 | Configurable by `overwrite_allowed`; with false -> `ReqDeny ErrFileExists`. | 1350:521 |
| D21 | Access control and "writes disallowed" are local policy. | (a) bool inputs from an oracle; (b) model path rules | (a) `path_allowed`, `write_allowed`. Pathname matching is a string/regex problem (X5). | 1350:583-588; 1123:153-157 |
| D22 | Broadcast request. | (a) `ReqIgnore` (no ERROR); (b) deny with ERROR | (a): "silently ignored". | 1123:159-162 |
| D23 | Malformed request (missing NUL, empty filename, trailing bytes). | (a) ERROR 4; (b) silent drop | (a) when unicast; decoder supplies `well_formed`. | 1350:119-122, 295-297 |
| D24 | Retransmission limit. RFC: "until acknowledged or the sending host times out" — no number. | (a) unbounded; (b) configuration `max_retries` | (b): totality and termination need a bound; the value is a parameter, not specified. | 1350:427-430, 441 |
| D25 | Does the data receiver run a retransmit timer? | (a) required; (b) forbidden; (c) optional | (c): `receiver_timer` flag; 1123 permits removing it once SAS is fixed. The receiver must still eventually give up (premature termination), so `max_retries` applies to it either way. | 1350:95-98; 1123:126-135 |
| D26 | Does the requester retransmit RRQ/WRQ on timeout? | (a) yes; (b) no | (a): "may retransmit his last packet". A duplicated request may open two connections at the server; that is the case §4 describes and the requester handles it by TID (D12). | 1350:95-98, 248-259 |
| D27 | Server and duplicate requests. | (a) each request opens an independent connection; (b) deduplicate | (a): the server sees no connection state at port 69 (`PhListen` is stateless). | 1350:248-259 |
| D28 | Dallying. | (a) required; (b) optional | (b) "encouraged": `dally` input to S14; in `PhDally` only the duplicate final DATA is answered (S27); dally length is time (X1). | 1350:421-426 |
| D29 | When is the data receiver done? | (a) on sending the final ACK; (b) after dally | (a) for the outcome (`OutSuccess` once the final ACK is sent, also from `PhDally`); the phase only becomes `PhDone` after the dally. | 1350:421-422 |
| D30 | Data sender outcome after timing out on the final DATA. | (a) Failed; (b) Indeterminate | (b) `OutIndeterminate`: "may still have been completed successfully". Timing out on an earlier block is `OutFailed`. | 1350:429-434 |
| D31 | What does "Sending a DATA packet is an acknowledgment for the first ACK" add? | (a) nothing operational; (b) a separate obligation | (a): it is the lock step already encoded by S16; no step of its own. | 1350:368-369 |
| D32 | Which packets terminate the connection when sent by us? | (a) every ERROR we send except ERROR 5 to a stranger; (b) only some | (a): "Most errors cause termination"; the single non-terminating case is the wrong source port. ERROR is a courtesy; we terminate after sending. | 1350:105-108, 126-128, 438-441 |
| D33 | Receiving ERROR with code 5 (Unknown TID) from the bound peer. | (a) terminate like any ERROR; (b) ignore, since 5 is non-terminating for its sender | (a): the RFC says ERROR from the peer means termination; it never says the receiver may continue. See Q5. | 1350:105-108, 126-128 |
| D34 | Received error codes > 7 and the error message. | (a) `ErrUnassigned` tag, message ignored; (b) reject packet | (a): the field is 2 bytes; the message is "for human consumption". | 1350:409-414 |
| D35 | Wrong-kind packet from the peer (ACK to a data receiver, DATA to a data sender, RRQ/WRQ on a transfer TID, ACK to an RRQ). | (a) ERROR 4 and terminate; (b) ignore | (a): not explainable by delay or duplication. | 1350:119-122, 369-381, 520 |
| D36 | Opcode outside 1..5 or a body that does not fit its opcode (DATA > 512 bytes, ACK longer than 4 bytes). | (a) ERROR 4; (b) ignore | (a) `OpInvalid` / `well_formed = false` -> S24. | 1350:121-122, 361 |
| D37 | Data length in netascii mode: before or after translation? | (a) wire bytes; (b) local bytes | (a): blocks are 512 bytes on the wire; translation is local (X4). | 1350:91-92, 300-302 |
| D38 | Mode used on each side may differ (storage server example). | (a) protocol steps independent of local mode; (b) model local mode | (a): only the mode on the wire is a step input, and only `server_on_request` uses it. | 1350:315-332 |
| D39 | Local resource loss during transfer. | (a) ERROR with a code chosen by the caller, terminate; (b) fixed code | (a) S26 takes the code (typically 3 or 2). | 1350:123-124, 518 |
| D40 | First DATA to an RRQ that is final (file < 512 bytes or empty). | (a) normal: requester ACKs 1 and is done/dallies; (b) special case | (a): S12 routes to `PhDally`/`PhDone`. | 1350:190, 490 |
| D41 | Synonyms: "sequence number" and "block number". | — | Same thing: `BlockNum`. | 1350:238, 357 |
| D42 | Errata in the RFC 1123 SAS example: "Send ACK X+3" at steps 10 and 12. | (a) typo for ACK X+2; (b) literal | (a): the surrounding text only makes sense with X+2. Nothing normative depends on it. | 1123:100-106 |
| D43 | RFC 1123 cites RFC-783 pages. | (a) applies to 1350 too; (b) not | (a): 1350 obsoletes 783 and itself points to 1123 §4.2. | 1350:10, 84-85; 1123:5-6, 26-33 |
| D44 | Retransmission granularity: what is "the packet on hand"? | (a) exactly the last packet sent (request, DATA or ACK); (b) rebuilt | (a) `ActRetransmit` is nullary: it means "the last packet, byte-identical". | 1350:95-100 |
| D45 | Retry counter reset. | (a) reset on every accepted Expected packet; (b) never | (a): the limit is per outstanding packet. Duplicates and stale packets do not reset it. | 1350:427-428 (silent) |
| D46 | One-payload restriction: the step result needs packet + phase + counter. | (a) one function per output, same parameters; (b) encode into ints | (a), giving the `_action` / `_next_phase` / `_next_*` triples. | tool constraint |
| D47 | Handlers take enum tags (`BlockClass`, `TidVerdict`, `Opcode`) instead of raw ints. | (a) classify first; (b) compare inside each handler | (a): keeps clauses as constructor tests, satisfies the "discriminate on tags" constraint. | tool constraint |
| D48 | Order of checks on an incoming packet. | TID check first vs well-formedness first | TID check first: a malformed packet from a stranger gets ERROR 5 and does not abort our transfer. | 1350:239-246, 255-259 |
| D49 | Packets arriving in a terminal phase (`PhDone`, `PhAborted`). | (a) ignore; (b) ERROR 5 (the TID is no longer known) | (a) `ActNone`; RFC silent. See Q6. | silent |

Count: 49 D-rows.

---

## 4. Exclusions (X-rows)

| ID | Not modelled | Why | RFC |
|---|---|---|---|
| X1 | Time: timeout values, the adaptive-timeout MUST, exponential backoff, dally duration | clocks are outside the target; only the timeout event and a retry counter are inputs | 1350:95-98, 423-425; 1123:137-144, 199 |
| X2 | The network: loss, delay, duplication, delivery to the right host, UDP checksum, IP header | I/O; the vocabulary only reacts to packets that arrived | 1350:137-153, 524-555 |
| X3 | Randomness of TID choice | probabilistic requirement; the chosen TID is an input | 1350:197-201 |
| X4 | Byte-level parsing and encoding: NUL-terminated strings, netascii translation, octet identity on round trip | value-dependent offsets and string content; the decoder hands over tags, ints and `well_formed` | 1350:287-310, 399-414 |
| X5 | Filenames, pathname access-control rules, mail recipients, the error message text | strings/regexes; reduced to bool oracles | 1350:296, 311-313, 412-414; 1123:155-157 |
| X6 | File contents and the file system (reading the next block, disk full detection) | I/O; `has_more`, `file_exists`, local failure code are inputs | 1350:123-124 |
| X7 | Multiple concurrent connections and the server's listener | concurrency; each connection is analysed alone (D27) | 1350:248-259 |
| X8 | Two-sided properties (e.g. "the file is transferred correctly if the transfer completes", absence of the SAS loop between two ends) | need a model of both ends plus the network over time | 1123:39-44, 62-76 |
| X9 | Mail mode semantics and locally defined modes | obsolete / unstandardized; denied (D17, D18) | 1350:80-82, 309-345; 1123:148-151 |
| X10 | Non-standard extensions (options, passwords) | not standardized | 1123:146-151 |
| X11 | Underlying datagram protocols other than UDP | protocol is UDP-agnostic at this level; nothing to model | 1350:63-65, 526-527 |
| X12 | Performance remarks (window of one segment, bootstrap use) | not obligations | 1123:8-19 |

Count: 12 X-rows.

---

## 5. Open questions for the author

1. Q1. What must happen when a transfer needs more than 65535 blocks: wrap to 0, wrap to 1, or refuse? Which error code? (D1)
2. Q2. Is "Datagram length < 516" in §6 the TFTP packet length (UDP length minus 8)? (D3)
3. Q3. Does the Sorcerer's Apprentice rule cover any old ACK, or only the duplicate of the previous block? (D4)
4. Q4. Should a host also verify the peer's IP address, or is the TID check alone intended? (D14)
5. Q5. When a host receives ERROR 5 from its own peer, should it terminate? (D33)
6. Q6. How should a host answer packets that arrive after it has terminated? (D49)
7. Q7. Which error code goes with an unknown mode, a malformed request, or a packet ahead of the lock step: 0 or 4? (D17, D19, D6)
8. Q8. Is the 0-length final block mandatory for files whose size is a multiple of 512, or can an implementation agree otherwise? (D2)
9. Q9. Should a requester treat an ERROR reply from a TID different from a later positive reply as binding (which reply wins)? (D12)
10. Q10. Is there a recommended retry limit, or a minimum number of retransmissions before giving up? (D24)
11. Q11. May the server pick 69 (or 0) as its own transfer TID? (D15)
12. Q12. "All packets other than duplicate ACK's and those used for termination are acknowledged" — which packets are "used for termination": the final ACK, ERROR, or also the final DATA? (D31, D32; 1350:366-367)

---

Totals: 19 sorts (M1-M19), 31 steps (S1-S31), 49 D-rows (D1-D49), 12 X-rows (X1-X12), 12 open questions.
