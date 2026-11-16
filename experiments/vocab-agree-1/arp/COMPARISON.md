# RFC 826 vocabularies: R vs three blind vocabularies (A, B, C)

Inputs: `reference/scope.md` + `reference/roots.llmll` (R, written with inventory rows and compiler
constraints), `a/vocabulary.md` (A), `b/vocabulary.md` (B), `c/vocabulary.md` (C), each of A–C
written from `rfc826.txt` alone. Line numbers are into `a/rfc826.txt` (470 lines). IDs are cited
as `A:D12`, `R:MD3`, `C:R4`, `B:S9`. R's clause tags are written `[A57]` so they don't collide with
vocabulary A.

Size: A has 17 sorts, 35 steps, 46 D-rows, 17 X-rows. B has 10 sorts, 28 steps, 30 D-rows, 13 X-rows.
C has 12 sorts, 29 steps, 37 D-rows, 14 X-rows. R has 5 declared types, 22 defs, MD1–MD8, 5 `A-*`
assumptions plus attacker A1–A4, and X1–X10.

---

## 1. Sorts

| Concept | R | A | B | C |
|---|---|---|---|---|
| Opcode, received | enum `Op {Req, Rep, OpOther}` | enum `Opcode {OpRequest, OpReply, OpOther}`, from U16 by `opcode_of` (S2) | enum `Opcode {OpRequest, OpReply, OpOther}`, from U16 by `classify_opcode` (S1) | enum `OpClass {OpRequest, OpReply, OpOther}`, from U16 by `classify_op` (P4) |
| Opcode, emitted | same `Op` (constant `Req`/`Rep`) | raw `U16` (`req_op` returns 1, `reply_op` returns 2) | `Opcode` enum (it includes `OpOther`) | separate enum `OutKind {OutRequest, OutReply}`, then `encode_op` returns U16 (M6, P5). `OpOther` cannot be emitted |
| Hardware type `ar$hrd` | enum `HwType {Eth, HwOther}`; receiver test is the bool `supports?` | `U16` alias; receiver test is equality with `my_hrd` (S3, D4) | `U16`; receiver test is the caller-supplied bool `hrd_mine` (D23) | `U16`; receiver test is the caller-supplied bool `have_hrd` (D3) |
| Hardware length `ar$hln` | enum `Len {Six, LenOther}` | `U8`; expected `my_hln` | `U8`; request constant 6 | `U8`; expected `want_hln`, request `local_hln` |
| Protocol length `ar$pln` | the same `Len` enum; expected is the parameter `pln-of-hrd-pro` | `U8`; map `ProtoLens: pro -> U8` | `U8`; parameter `pro_len`; receive check is the external bool `pln_ok` | `U8`; parameters `want_pln`, `proto_pln` |
| Hardware address | `int`, opaque, unbounded, `=` only | `HwAddr` in [0, 2^48) | `Hw48` in [0, 2^48) | `HwAddr` in [0, 2^48) |
| Protocol address | `int`, opaque, unbounded | `ProtoAddr`, int ≥ 0, unbounded | `PAddr` in [0, 2^32) | `ProtoAddr`, int ≥ 0, unbounded |
| Protocol type `ar$pro` | `int`, opaque | `ProtoType` = U16 | `U16` | `U16` |
| Host identity | `h: int` on table steps (Host sort, scope §5) | none (one node) | none | none |
| Local identity / ownership | `own-hw`, `own-pa-for-pro`: addresses the host owns, possibly several (relation, MD3); `owns-target?: bool` | `MyAddrs` map `pro -> addr` (one address per protocol; `has` = "speaks"), `my_ha`, `my_hrd`, `my_hln` | `my_hw`, `my_pa` (one), bools `hrd_mine`, `pro_mine` | `local_ha`, `local_pa` (one), bools `have_hrd`, `speak_pro` |
| Table | no value; facts at an **arbitrary** key `<key-pro, key-pa>`: `key-present?`, `key-hw`; result `Binding {Absent, Bound int}` | `Table = map[int,int]`, key `table_key = pro + 65536*spa` (D1) | `Table = map[int,int]`, key `pro*2^32 + pa` (D1) | no value; facts at the **received** key `<pro, spa>` only: `entry_present`, `entry_hw`; then `TableAction {TableKeep, TableUpdate, TableInsert}`; outputs `entry_present_after`, `entry_hw_after` (D9) |
| Merge_flag | input `key-present?` | step `merge_flag` (S9) | step `tbl_has` (S4) | step `merge_flag [g, entry_present]` (R2) |
| Reception gate | no gate sort; `supports?`, `speaks?` are bool parameters and branch preconditions | `RxGate {GateAccept, DropHrd, DropHln, DropPro, DropPln}` | `Gate {Proceed, Discard}` | `Gate {GateOpen, DropHrd, DropHln, DropPro, DropPln}` |
| Optional length checks | separate bool steps `arp-hln-check`, `arp-pln-check`; no enable flag, no consequence | flags `chk_hln`, `chk_pln`; a failed enabled check yields `DropHln`/`DropPln` | flags `hln_check_on`, `pln_check_on` + decoder-supplied `hln_ok`, `pln_ok`; failure yields `Discard` | flags `check_hln`, `check_pln` + `want_*`; failure yields `DropHln`/`DropPln` |
| Lookup result | `Binding {Absent, Bound int}` | `Lookup {Found HwAddr, Miss}` | `Lookup {Miss, Hit Hw48}` | `ResolveResult {Found HwAddr, NotFound}` |
| Transmit decision | `Emission` (`Silent`/`Broadcast`) from `arp-request-emit` | `TxAction {TxSend, TxDiscardAndRequest}` | `Resolve {SendFrame, DropAndRequest}` | none (`NotFound` is defined as the request trigger) |
| Reception outcome | `Emission {Silent, Broadcast, Unicast int}`: decision **and** destination in one value | `RxAction {RxDiscard, RxAbsorb, RxReply}` | `Action {NoAction, SendReply}` | `Disposition {Discard, SendReply}` |
| Delivery scope / destination | inside `Emission` | `Dest {DestBroadcast, DestUnicast HwAddr}` (`req_dest`, `reply_dest`) | `reply_dest` returns a bare `Hw48`; the request has no destination | `LinkDst {Broadcast, Unicast HwAddr}` via `out_dst [OutKind, HwAddr]` |
| `ar$tha` | a parameter of `arp-merge`/`arp-add`, used in no clause; no request `tha` step | `req_tha [fill]` returns a free filler; absent from reception | absent everywhere (D14) | absent everywhere (D18, D23) |
| Wire layout | none | `decode_u16` (S1) | none | `u16_of_bytes`, `body_len`, `field_offset`, enum `AddrField` (P1–P3) |
| Station role | none | `Role {RoleHost, RoleMonitor}` | none | none |
| Named numeric constants | none (enum constants only) | `ARES_OP_REQUEST=1`, `ARES_OP_REPLY=2`, `ARES_HRD_ETHERNET=1`, `ETHER_HLN=6`, `ETHER_BROADCAST=2^48-1` | 1 and 6 inline | 1, 2, 1, 6 |

### Material differences (they change which clauses can be written or what they mean)

1. **The table: whole map or per-key facts.** A and B pass the whole table as `map[int,int]`, so a
   frame condition is one map equality (`set(tbl, k, sha)`). R and C pass only facts at one key. R's
   key is arbitrary (`key-pro`, `key-pa` are parameters, so "every other key unchanged" is stateable,
   [A52]). C's key is fixed to `<pro, spa>`, so no clause can mention any other key (C:D10 says this).
2. **The pair encoding differs between A and B.** A uses `pro + 65536*spa` and relies on `pro` having
   16 bits. B uses `pro*2^32 + pa` and relies on `pa` having 32 bits. Key-mentioning clauses don't carry
   over textually, and B's encoding is what forces its 32-bit `PAddr` bound (B:D1, D2).
3. **Numeric fields: uninterpreted enums or refined ints.** R's `HwType`, `Len` and `Op` are enums with an
   `Other` tag and no arithmetic (MD7). A, B and C use U8/U16 and numeric equality. R's `Len {Six, LenOther}` is shared by
   `hln` and `pln`, so every non-6 length is the same value. [A50]'s check `pln = pln-of-hrd-pro`
   can't tell IPv4's 4 from CHAOS's 2, so it is weaker in R than in A or C.
4. **Ownership: relation or single address.** R lets a host own several protocol addresses per
   protocol (MD3, S4). A, B and C allow one (A:D9, B:D11, C:D17). A also merges "speaks" into "has an
   address" (A:D8, M10).
5. **Emission: decision and destination.** R has one value (`Silent | Broadcast | Unicast hw`). A and C
   separate a decision tag from a destination sort. B has no scope sort: the reply destination is a
   bare `Hw48`, and the request's broadcast is only the meaning of `DropAndRequest` (B:D18).
6. **Opcode presence in the table steps.** R's `arp-merge`/`arp-add` take `op`. A's `rx_table`, B's
   `tbl_merge`/`rx_learn`/`rx_table` and C's `table_action` do not (A:S11, B:D10, C:R4). In A, B and C
   the table is opcode-independent by signature. No clause can say it.
7. **`ar$tha` in reception.** R keeps it as a parameter so a clause can be "falsified by" it. A, B and C
   drop it, so tha-independence holds by signature.
8. **Gate.** R has no gate step. In A, B and C the guards reach later steps through a Gate tag, so an
   R clause over `supports?` becomes two clauses: one on the gate step and one on its consumer.
9. **Request `hrd`/`hln`.** R and B use constants (`Eth`/`Six`, 1/6). A and C use interface parameters
   (`my_hrd`/`my_hln`, `local_hrd`/`local_hln`).
10. **Emitted opcode type.** A emits raw numbers. B emits an enum that includes `OpOther`. In C,
    `OpOther` cannot be emitted at all, so [A17] holds by type.
11. **Scope-bearing sorts.** Only R has a host identity (needed for C6/R1/R2). Only A has `Role`
    (monitor). Only A and C decode wire words. Only C models layout offsets, which R §2 rules out of
    the fragment.

---

## 2. Decomposition of RFC 158–234

| RFC unit (lines) | R | A | B | C |
|---|---|---|---|---|
| Lookup on transmit (169–172) | `arp-resolve` on facts | `resolve [tbl,pro,tpa]` (S21) | `tbl_get` (S5) + `tx_resolve` (S20) | `resolve [entry_present, entry_hw]` (G1) |
| Miss: drop + emit a request (172–176, 188–190) | `arp-request-emit [key-present?]` returns `Silent`/`Broadcast` | `tx_action [hit]` (S22) + `req_dest []` (S33) + `tx_table` identity (S23) | inside `tx_resolve` (`DropAndRequest`); no destination | no step; `NotFound` is the trigger; `out_dst OutRequest` returns `Broadcast` |
| Request field map (176–187) | 8 steps: hrd, pro, hln, pln, op, sha, spa, tpa; **no tha** | 9 steps incl. `req_tha [fill]` | 8 steps; no tha | 7 steps + `encode_op`; no tha |
| Gate (203–208) | none; guards are bools and branch preconditions; `arp-hln-check`/`arp-pln-check` are non-rejection predicates only | `hrd_ok`, `hln_ok`, `speaks`, `pln_ok` + `rx_gate` (first-failure tag) | `rx_gate` over 6 bools (two-valued) | `recv_gate` over values + expectations (first-failure tag) |
| Merge_flag (209–213) | `key-present?` input | `merge_flag` | `tbl_has` | `merge_flag [g, entry_present]` |
| Target test (214) | `owns-target?` input | `is_target` (S10) | inline `tpa == my_pa` in `rx_table` and `rx_action` | `is_target` (R3), then `target: bool` downstream |
| Table change (210–218) | **split by branch**: `arp-frame` (discard + every other key), `arp-merge`, `arp-add`; branch selected by precondition | **one step** `rx_table` (merge + add) + `rx_table_final` (gate wrapper) | **split in RFC order**: `tbl_merge` then `rx_learn`, composed by `rx_table` | **split by decision and effect**: `table_action` tag, then `entry_present_after`, `entry_hw_after` |
| Opcode test (219–220) | inside `arp-emission` | `rx_action` (3-valued: discard/absorb/reply) | `rx_action` | `recv_disposition` |
| Reply field map (221–223) | op, sha, spa, tha, tpa (5 steps); **no step** for unchanged hrd/pro/hln/pln | op, sha, spa, tha, tpa + `reply_hdr_word/byte` identity | op, sha, spa, tha, tpa + `reply_hrd/pro/hln/pln` | sha, spa, tha, tpa + `reply_hrd/pro/hln/pln`; op via `encode_op` |
| Reply delivery (224–225) | inside `arp-emission` (`Unicast sha`) | `reply_dest [sha]` | `reply_dest [req_sha] -> Hw48` | `out_dst OutReply sha` |
| Monitor (337–348) | excluded (X6) | `mon_table`, `mon_action` | excluded | excluded |

Where the step boundaries differ:

- **Table transition.** There are four different cuts. R cuts by branch (discard / merge / add), each a
  `Binding` at an arbitrary key. A has one function. B follows the RFC's sequence (merge, then add).
  C cuts into decision (`TableAction`) and effect. Only B's cut matches the order in which the RFC
  states the steps (209–218).
- **Emission.** R fuses "whether to send" with "where to send". A, B and C separate them. This is
  the main reason [A62]/[A88] are reshaped everywhere.
- **Guards.** R takes guard results as inputs to every step. A, B and C compute them once in a gate
  step and pass a tag. Every R clause conditioned on `supports?`/`speaks?` therefore needs one more
  clause on the gate step.
- **Transmit decision.** R, A and B have an explicit output for "a request is emitted". C has none.
- **Reply header.** A, B and C have identity steps for the unchanged fields. R's scope C4 lists them
  ("`ar$hrd`, `ar$pro`, `ar$hln`, `ar$pln` unchanged"), but `roots.llmll` has no step to carry that part.

---

## 3. Re-expressibility of R's 39 clauses

Categories: **yes** means one template sentence on one existing step, directly or by renaming.
**reshaped** means expressible, but the obligation has to be split, merged or restated across
steps. **no** means a needed parameter, sort or step is missing. **no\*** is the subset of "no"
where the vocabulary makes the obligation hold by signature (the parameter R's clause mentions is
deliberately absent), so it can't be stated or falsified. **conflict** means the vocabulary makes
the obligation false.

Cause codes: **[G]** a guard reaches the step only through a Gate tag; **[P]** an Ethernet constant
became an interface parameter; **[E]** the emission decision and the destination are separate steps.

| Tag | R step | Obligation | A | B | C | Reason (non-yes only) |
|---|---|---|---|---|---|---|
| A25 | arp-resolve | miss ⇒ no binding | yes | yes | yes | |
| A26 | arp-resolve | hit ⇒ stored address | yes | yes | yes | |
| A30 | arp-request-emit | request emitted iff miss | yes | yes | reshaped | C: there's no "emit" output. "Request iff `NotFound`" is how G1/D26 are defined, so the clause merges into [A25] |
| A42 | arp-request-emit | request is broadcast | yes | **no** | yes | B: no request destination step or scope sort (B:D18) |
| A32 | arp-request-hrd | `ar$hrd` = Ethernet | reshaped | yes | reshaped | [P] A:D22, C:D27: becomes `REQUIRES my_hrd = 1` |
| A66 | arp-request-hrd | duplicate of A32 (C11) | reshaped | yes | reshaped | [P] |
| A33 | arp-request-pro | `ar$pro` = protocol being resolved | yes | yes | yes | |
| A34 | arp-request-hln | `ar$hln` = 6 | reshaped | yes | reshaped | [P] A:D37 `my_hln`, C:D27 `local_hln` |
| A67 | arp-request-hln | duplicate of A34 (C11) | reshaped | yes | reshaped | [P] |
| A35 | arp-request-pln | `ar$pln` = length for the protocol | yes | yes | yes | |
| A76 | arp-request-pln | duplicate of A35 (A-REDUNDANT) | yes | yes | yes | in every vocabulary, "determined by ⟨hrd,pro⟩" lives only in a parameter. B's `pro_len` is explicitly not tied to `pro` (B:D8) |
| A36 | arp-request-op | `ar$op` = REQUEST | yes | yes | yes | |
| A37 | arp-request-sha | `ar$sha` = own hardware address | yes | yes | yes | |
| A38 | arp-request-spa | `ar$spa` = own protocol address | yes | yes | yes | |
| A39 | arp-request-tpa | `ar$tpa` = address sought | yes | yes | yes | |
| A17 | arp-emitted-op-well-formed? | every emitted op ∈ {REQUEST, REPLY} | reshaped | reshaped | yes | A: two U16 steps, two sentences. B: two `Opcode` steps, and the sort includes `OpOther`. C: `encode_op` over `OutKind`, one sentence that holds by sort |
| A48 | arp-hln-check | hln check accepts conforming 6 | yes | **no** | yes | B: the comparison is outside the vocabulary (`hln_ok` is supplied by the decoder, B:D7) |
| A50 | arp-pln-check | pln check accepts conforming length | yes | **no** | yes | B: same (`pln_ok`) |
| A47 | arp-frame | hrd fails ⇒ table unchanged at every key | reshaped | reshaped | reshaped | [G] needs a gate clause plus a table clause. C also covers only key `<pro,spa>` (C:D10) and needs `table_action` + R5/R6 |
| A49 | arp-frame | pro fails ⇒ table unchanged | reshaped | reshaped | reshaped | [G], as A47 |
| A52 | arp-frame | keys other than `<pro,spa>` untouched | yes | yes | **no** | A/B: `SHALL return one of {tbl, set(tbl, key(pro,spa), sha)}`. C: no table value, and no other key is in scope (C:D9, D10) |
| A53 | arp-merge | present ⇒ entry := sha | yes | yes | reshaped | C: `table_action` = `TableUpdate`, then `entry_hw_after` = `sha` (two steps) |
| A64 | arp-merge | a REPLY merges exactly as a REQUEST | **no\*** | **no\*** | **no\*** | none of the table steps takes the opcode (A:S11, B:D10, C:R4). The property holds by signature and can't be written as a clause |
| A65 | arp-merge | new address supersedes old | yes | yes | yes | |
| A82 | arp-merge | `ar$tha` irrelevant | yes | yes | yes | tha is in no reception signature (holds by signature). R's surrogate "one of {sha, old}" restates directly |
| A57 | arp-add | absent key: add iff owns target | reshaped | yes | reshaped | A: merge and add are one step, so the branch moves from a precondition into the guard, giving two sentences. B: `rx_learn` WHEN/OTHERWISE. C: `table_action` + R5/R6 |
| A81 | arp-add | REPLY: add still gated by `ar$tpa` (R3 site) | **no\*** | **no\*** | **no\*** | as A64 |
| A79 | arp-add | entries come only from `<spa> → sha` | yes | yes | yes | |
| A46 | arp-emission | hrd/pro fail ⇒ silent | reshaped | reshaped | reshaped | [G] |
| A55 | arp-emission | not target ⇒ silent | yes | yes | yes | |
| A58 | arp-emission | op ≠ REQUEST ⇒ silent | yes | yes | yes | |
| A77 | arp-emission | REPLY ⇒ silent | yes | yes | yes | |
| A62 | arp-emission | all guards pass ⇒ unicast to `sha` | reshaped | reshaped | reshaped | [E] decision step + destination step. B: `reply_dest` returns a bare `Hw48`, so the "not broadcast" conjunct R uses to separate R1 from R2 is lost |
| A88 | arp-emission | duplicate of A62 (monitor passage) | reshaped | reshaped | reshaped | [E] |
| A61 | arp-reply-op | reply op = REPLY | yes | yes | yes | |
| A91 | arp-reply-sha | reply `sha` = own hardware address | yes | yes | yes | A/B/C `reply_sha` can't see the request's `sha`, so a relaying implementation can't even be typed. The clause tests less |
| A60 | arp-reply-spa | reply `spa` = matched `tpa` | reshaped | reshaped | yes | A: `reply_spa [pro, mine]` returns `get(mine,pro)` (A:D15). B: `reply_spa [my_pa]`. Each equals `tpa` only through the separate target test. Under R:MD3's multi-address reading, A and B would give a different value |
| A83 | arp-reply-tha | reply `tha` = request `sha` | yes | yes | yes | |
| A59 | arp-reply-tpa | reply `tpa` = request `spa` | yes | yes | yes | |

### Totals

| | yes | reshaped | no (of which no\*) | conflict |
|---|---|---|---|---|
| A | 25 | 12 | 2 (2) | 0 |
| B | 27 | 7 | 5 (2) | 0 |
| C | 24 | 12 | 3 (2) | 0 |

- **Duplicates.** R has four clause pairs with identical posts: A32/A66, A34/A67, A35/A76 and A62/A88.
  Over the 35 distinct obligations, the counts are A 24/9/2, B 24/6/5 and C 23/9/3.
- **Lenient reading.** If routing a guard through the Gate tag ([G]) counts as renaming, A has 28
  yes, B 30 and C 25.
- **Common ground.** 19 of 39 tags are "yes" in all three. They are the field maps and the simple
  emission guards. 7 tags are "yes" in none of the three: A46, A47, A49, A62, A88, A64 and A81.
- **Survival.** 33 of 39 tags can be expressed (yes or reshaped) in every vocabulary. 4 are lost in
  one vocabulary: A42, A48 and A50 in B, and A52 in C. 2 are lost in all three: A64 and A81.
- **No conflicts.** No vocabulary makes an R obligation false. The losses are all shape: missing
  parameters, a different step cut, or a property made true by signature.
- **The two universal losses are R's security claims.** A64 and A81 are the clauses R built so the R3
  refutation would have something to falsify (`op` in the table step). The blind authors' cleaner
  signatures make them true by construction, so the witness R3 needs can't be exhibited. A82 is the
  same phenomenon, but R's surrogate clause doesn't mention `tha`, so it survives.
- **Reverse direction (not measured).** A, B and C can state things R cannot: the unchanged reply
  header fields (promised by R scope C4 but missing from `roots.llmll`), discard on a failed enabled
  length check, the gate's first-failure tag, opcode decoding, A's free request `tha`, A's monitor,
  and C's layout offsets.

---

## 4. Decisions

Explicit (E) means the vocabulary states the decision: a D-row for A, B and C; MD, `A-*`, the
attacker rows, the `roots.llmll` header encoding decisions, or a scope X-row/§ ruling for R. An
X-row counts as an explicit decision for any vocabulary. S means the position is visible only in
types or signatures (or, for R, in a scope C-clause). — means no position.

| # | Question | R | A | B | C | Agreement |
|---|---|---|---|---|---|---|
| 1 | Does the table key include `ar$hrd`? | E MD1 | S | S | E D11 | agree (no) |
| 2 | One table per link/interface, or global? | E MD2 | E D41, X6 | E D4 | E D11, X8 | agree (a single interface is modeled) |
| 3 | Table representation | E hdr "witness plus flag" | E D1 | E D1 | E D9, D34 | **diverge (repr)**: A and B use a whole map with different encodings; R and C use per-key facts |
| 4 | Frame condition on other keys | S (`arp-frame`) | S (map) | S (map) | E D10 | **diverge (repr)**: C can't state it |
| 5 | Entry holds only the hardware address | S | E D40 | S | E D11 | agree |
| 6 | Supersession: function update, no recency order | E MD6 | S | E D19, D20 | E D14 | agree |
| 7 | Table capacity and eviction | E §4.3 | E D36 | E D30, X9 | E D33, X9 | agree (unbounded) |
| 8 | Does sending a request create table or pending state? | S | E D26 | S | E X7 | agree (no) |
| 9 | Uniqueness of hardware addresses | E A-UNIQ | E D35 | — | — | agree (not enforced) |
| 10 | Form of "Do I have the hardware type" | E hdr (relation → bool) | E D4 (equality, one type) | E D23 (bool) | E D3 (bool) | agree (A narrower) |
| 11 | Does "speaks the protocol" equal "has an address in it"? | S (separate) | E D8 (conflated) | S (separate) | S (separate) | **CONFLICT** |
| 12 | Optional length checks: flag, and what a failed check does | E A-REDUNDANT, X3 | E D5, D6 | E D7 | E D5, D6 | partial: A, B and C discard; R takes no position on the consequence |
| 13 | Where the expected length comes from | E A-REDUNDANT | E D6, D37 (config) | E D7 (decoder bool) | E D5 (input) | **diverge (repr)**: B keeps the comparison outside |
| 14 | Gate order and failure tags | S | E D7 | S | E D7, D36 | agree |
| 15 | Update an existing entry when not the target? | S (C1) | E D10 | E D5 | E D12 | agree (yes) |
| 16 | Add a new entry when not the target? | S (C2) | E D11 | E D5 | E D13 | agree (no) |
| 17 | Does a later "discard" undo the merge? | S | E D42 | E D6 | S | agree (the merge stays) |
| 18 | Merge_flag on the pre-state, exposed as a step | S | S | E D25 | E D15 | agree |
| 19 | Table step independent of the opcode | S (C1) | E D12 | E D10 | E D21 | agree |
| 20 | Opcode neither 1 nor 2 | E hdr (`OpOther`) | E D12, D13, D32 | E D9 | E D21 | agree (merge, no reply) |
| 21 | Unsolicited replies accepted, no pending-request state | E A4, R3 | E D27 | E D26 | E D22 | agree |
| 22 | Sender validity (`spa` = own, `sha` broadcast, gratuitous) | E MD4 | E D28 | E D12, D28 | E D32 | agree (no special case) |
| 23 | Received `ar$tha` ignored | E hdr (roots 209–210) | S | S | E D18 | agree |
| 24 | Several protocol addresses per protocol (target test = membership?) | E MD3 | E D9 | E D11 | E D17 | **CONFLICT** |
| 25 | Is the reception algorithm normative ("similar to", L199)? | S | S | S | E D1 | agree (results binding) |
| 26 | Reply `ar$spa`: the matched `tpa` or the configured local address? | E MD3 | E D15 | S (S12) | E D16 | **CONFLICT** |
| 27 | Which local hardware address goes in reply `sha` | S | E D16 | S | E D37 | agree |
| 28 | Meaning of "swap"; hrd/pro/hln/pln unchanged | S (C4) | E D17, D19 | E D13 | E D20 | agree |
| 29 | Ethernet header: ignored for learning and as reply destination | E X7, §4.3 | E D18, D29 | E D15 | E D19, X4 | agree |
| 30 | Delivery scope as a first-class value | E hdr | S | E D18 | S | **diverge (repr)**: B has no scope |
| 31 | Reply built from packet fields and the pre-state | S | S | E D16, D21 | S | agree |
| 32 | Request `ar$tha` | S (C8) | E D20 (free param) | E D14 (no step) | E D23 (no step) | agree (unconstrained) |
| 33 | Request destination | S ([A42]) | E D21 | E D18 | E D24 | agree (broadcast; B doesn't represent it) |
| 34 | Request `hrd`/`hln`: Ethernet constants or interface parameters | S (constants) | E D22, D37 | E D24 (constants) | E D27 | **CONFLICT** |
| 35 | Source of request `ar$pln` | E A-REDUNDANT | E D23 | E D8 | S | agree (supplied; B not tied to `pro`) |
| 36 | On a miss, is the original packet dropped? | — | E D24, D44 | E D17 | E D25 | **CONFLICT** |
| 37 | One request per miss, no throttling | S | E D25 | S | E D26 | agree |
| 38 | Request `tpa` is the next hop | S | E D45 | S | S | agree |
| 39 | Address representation and width | E hdr (opaque, unbounded) | E D2, D3, D34 | E D2, D3 (PAddr < 2^32) | E D8 | **diverge (scope)** |
| 40 | Numeric fields: enums or ints | E MD7 | S | S | E D2 | **diverge (repr)** |
| 41 | Opcode as an enum with Other; numbers only at decode | E hdr | E D32, D33, D46 | E D22 | S | agree |
| 42 | Byte order and decoding inside the model | E X2 (out) | E D31, D33 (in) | E X2 (out) | E D28 (in, plus offsets) | **diverge (scope)** |
| 43 | Packet length, truncation, `hln`/`pln` = 0 | E X1, X3 | E D43, X17 | E X2 | E D30, D31 | agree (out / allowed) |
| 44 | Ethertype dispatch before ARP | E X7 | E D30 | E D27 | E D29 | agree |
| 45 | No packet sort or record | E MD8 | S | S | S | agree |
| 46 | Monitor role | E X6 (out) | E D38, D39 (in) | E D29, X4 (out) | E D35, X3 (out) | **diverge (scope)** |
| 47 | Delivery reliability | E MD5, A-PERFECT (modeled, lossy) | E X2 (out) | E X7 (out) | — | **diverge (scope)** |
| 48 | Adversary and multi-station model | E A-CONF, A1–A4 (in) | E X13 (out) | E X11 (out) | — | **diverge (scope)** |
| 49 | Time, aging, timeouts | E MD6, X5 | E X1 | E X5 | E X1 | agree (out) |
| 50 | Decoded input assumed well-formed | E A-WF | E X17 | E X2 | S | agree |
| 51 | Non-Ethernet hardware generality | S (`HwOther`, `LenOther`) | E D3, X14 | E D3, X1 (out) | E D27, D31 | **diverge (scope)** |

### Totals

- There are **51** distinct questions. 17 were raised explicitly by all four, 16 by three, 12 by two
  and 6 by one.
- **Agree: 34.** Partial (one vocabulary abstains): 1 (#12). Representation or scope divergence: 11
  (#3, 4, 13, 30, 39, 40, 42, 46, 47, 48, 51). **Semantic conflicts: 5** (#11, 24, 26, 34, 36).
- **Opcode and table behaviour.** Every question about the order of operations agrees across all four
  (#15–#22): merge before opcode, update without target, add only with target, unknown opcodes,
  unsolicited replies, sender validity.

### Candidate questions for a human (the conflicts)

1. **#24 and #26 (linked): can a host own several protocol addresses in one protocol, and what goes in
   the reply's `ar$spa`?** RFC L182 ("the protocol address of itself", singular), L214 ("Am I the
   target protocol address?") and L221–222 ("putting the local hardware and protocol addresses in the
   sender fields").
   - R: ownership is a relation, and reply `spa` is the matched `tpa` (MD3).
   - C: one address, but reply `spa` is `tpa`, so it survives a multi-address upgrade (D16, D17).
   - A: one address, and reply `spa` is `get(mine,pro)` (D9, D15).
   - B: one address, and reply `spa` is `my_pa` (D11, S12).

   With one address the readings agree. With several they don't.
2. **#34: is the request's `ar$hrd`/`ar$hln` the Ethernet constants (1, 6) or the sending interface's
   values?** RFC L165 and L177–180 (Ethernet case), L236–242 (generalization), and L384 (the example
   writes `length(EA(X))`, not 6).
   - Constants: R ([A32]/[A34]) and B (D24, S21, S23).
   - Interface parameters: A (D22, D37) and C (D27).
3. **#11: does "I speak the protocol" (L206) imply "I have an address in it" (L214, L221–222)?** A
   merges the two (D8). R, B and C keep separate inputs. In A, a host that speaks a protocol without
   owning an address can't exist (A's open question 3).
4. **#36: on a resolution miss, is the outgoing datagram dropped?** RFC L172–176 ("it probably informs
   the caller that it is throwing the packet away") and L379–380 ("It throws the Internet packet away").
   A (D24, D44) and B (D17) model the drop as part of the outcome tag. C (D25) leaves it unspecified.
   R takes no position.
5. **#12 (partial): when an enabled optional length check fails, is the packet discarded before the
   table step?** RFC L200–201 ("negative conditionals"), L205 and L208 ("optionally check"). A, B and
   C discard. R abstains (X3: enforcement out; only non-rejection is carried). Two blind authors list
   it as open (B Q6, C Q2).

Scope divergences a developer would also have to settle: the monitor (A in; the others out), the
adversary and delivery model (R in; the others out), 32-bit protocol addresses (B), and the table
representation (#3/#4, which decides whether frame conditions are writable).

---

## 5. Exclusions

| Excluded region | R | A | B | C |
|---|---|---|---|---|
| Parsing variable-offset address fields | X1 | X3 | X2 | X2 (but P2/P3 model offsets as arithmetic) |
| Byte order of the three words | X2 | modeled (S1, D31) | X2 | modeled (P1, D28) |
| Packet length, truncation, padding | X1, X3, X4 | X17 | X2 | D30 (layout only) |
| Same-length reply / buffer reuse as an obligation | X4 | not excluded (used in D19 and S20) | X13 | X11 |
| Aging, timeouts, probe daemon, retransmission | X5 | X1 | X5, X6 | X1 |
| Host moves, clearing, delete-on-failure | X9 | X10, X16 | X5 | X1 |
| Monitor role | X6 | partial: only its own requests/loop (X7) and display (X8) | X4 | X3 |
| Ethernet frame header | X7 | X2 (+ D29, D30) | X3 | X4 |
| Design rationale | X8 | X11 (multiplexing only) | X12 | X14 |
| Hardware registry / authority | X10 | X9 | X10 | X12 |
| Numeric ether_type values | — | X15 | X10 | D29 |
| Routing / next hop | — (MD2 single link) | X5 | X8 | X6 |
| Higher-layer retransmission of the dropped datagram | — | X4 | X6 | X5 |
| Concurrency | — | X12 | X9 | X10 |
| Multiple interfaces | MD2 | X6 | X9 | X8 |
| Table capacity, eviction, hashing | §4.3 | D36 | X9 | X9 |
| Pending-request state, rate limiting | — | D25, D26 | X6 | X7 |
| Network delivery, broadcast reach | **carried** (MD5, A-PERFECT, S1) | X2 | X7 | X11 (transmission) |
| Spoofing / security | **carried** (A1–A4, A-CONF, R1–R3) | X13 | X11 | — |
| Non-Ethernet hardware | — (open enums) | X14 (params only) | X1 (and pln > 4) | — (params) |
| Ordering on addresses | §3 | — | — | X13 |

- **Excluded by all four:** variable-field parsing, aging/time, host-move and clearing, the frame
  header, the registry, multiple interfaces, and table capacity. The monitor and the design rationale
  are also excluded by all four, with A only partly.
- **Excluded by A, B and C but not R:** routing, higher-layer retransmission and concurrency (R is
  silent on these). R is the only one that **carries** delivery and the adversary; A and B exclude
  them, and C mentions neither.
- **Excluded by R and B but modeled by A and C:** wire-word decoding. C additionally models the
  offsets that R §2 names as the reason parsing is out.
- **Only B** excludes non-Ethernet hardware and protocol addresses longer than 4 bytes.

---

## 6. Errors against the RFC text

These are claims the text clearly contradicts or does not support.

1. **R, `roots.llmll` lines 10–11: "Host, HwAddr, ProtoAddr and ProtoType carry no constants …
   in RFC 826."** The RFC names a distinguished hardware address, "the broadcast address for the
   hardware (all ones in the case of the 10Mbit Ethernet)" (L186–187). It also names protocol-type
   constants `ether_type$XEROX_PUP`, `$DOD_INTERNET`, `$CHAOS` and `$ADDRESS_RESOLUTION` (L117–121),
   and `ET(IP)` (L373). These are names without numeric values, but they are constants. Consequence:
   R cannot state the "sha = broadcast" question that B:D12 and C:D32 raise.
2. **R, `scope.md` MD3: "This is the only reading … consistent with the example at 393-401."** The
   example says only that `EA(Y)` goes into `ar$sha` (L398–399). It never says what the reply's
   `ar$spa` is. Both readings in #26 are consistent with it. [A60] also cites L399, which is about
   `ar$sha`, as support for `spa := tpa`.
3. **C:D25 "The RFC says 'probably' throws it away" (A:D24 elides the same sentence).** At L173,
   "probably" qualifies *informing the caller* ("it probably informs the caller that it is throwing the
   packet away"). The worked example states the drop without a hedge: "It throws the Internet packet
   away" (L379–380). C's "unspecified" rests on a misplaced hedge. This is clear on L379–380. How far
   "probably" reaches at L173 is arguable, so treat this one as probable rather than certain.

No row in A or B states something the RFC text unambiguously contradicts. Their line citations, as
spot-checked, are accurate.

Internal inconsistencies in R (not RFC errors, but they affect measurement):

- Scope C4 promises "`ar$hrd`, `ar$pro`, `ar$hln`, `ar$pln` unchanged" in the reply. No `roots.llmll`
  step carries this.
- `Len {Six, LenOther}` makes [A50]'s `pln` comparison unable to tell non-6 lengths apart.
- Four clause pairs are verbatim duplicates (A32/A66, A34/A67, A35/A76, A62/A88).

---

## 7. Summary

**Agreement.** The three blind vocabularies and R agree on almost all of the protocol's behaviour:

- 34 of 51 decision questions agree.
- Every question about the reception algorithm's order of operations agrees (#15–#22).
- No vocabulary makes any of R's 39 obligations false (0 conflicts).
- 33 of 39 obligations can still be expressed in all three.

**Where it fails.** What fails is the *clause set*, not the meaning:

- Only 19 of 39 R clauses can be restated verbatim as a single sentence in all three vocabularies.
- A gets 25/39, B 27/39 and C 24/39 "yes".
- The rest come from four structural choices that each author made differently: how the table is
  passed (whole map vs per-key facts), where guards live (inputs vs a Gate tag), whether "emit"
  and "where to" are one value or two, and whether a constant is a parameter.

**Where the disagreement concentrates.** Two places:

- **Local identity** (#11, #24, #26): one address or several, speaking vs owning, and reply `spa`.
- **Ethernet-specific vs generalized generation** (#34, #51), plus one hedge-reading question
  (#36). These five are the questions to put to a human.

**Two losses matter more than their count.** A64 and A81 are lost everywhere because the blind
authors' cleaner signatures make the property true by construction. R includes `op` in the table
steps precisely so R3 can be refuted with a witness. Signature-level choices therefore carry
verification intent that no blind author reproduced.

**Implication.** Making the vocabulary the developer-authored artifact would preserve the
*semantics* of the clause set across authors, but not the *clause set itself*. It works only if the
vocabulary is frozen before clause writing and the five conflicts plus the table/guard/emission
shape choices are settled explicitly. Otherwise roughly a third to a half of the clauses get
reshaped or lost with each change of vocabulary.
