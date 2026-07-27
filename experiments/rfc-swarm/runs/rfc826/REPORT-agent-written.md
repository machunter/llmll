# RFC 826: a formal specification traced to the source text, and an implementation the compiler proves satisfies it

**Source.** `rfc826.txt`, sha256 `01bc62fe6a37e90f1246ac43e8e145f1322b4ed1474836145c3da93d2bd3c8a6`, 470 lines.
**Toolchain.** `llmll 0.14.67`.
**Tree under test.** `12-wave/roots.ast.json`, sha256 `69ad0f9aa0a2eab161676cb632d6a2d1ba639bc61c36ee6976b225c204f5d90b` (byte-identical to `13-kill-matrix/baseline.ast.json`).
**Pre-registration.** `08-prereg/PRE-REGISTRATION.md`, sha256 `1cf8f5fb…0ac585cb`, matching the value pinned in `MANIFEST.json`. It was not edited after the run; Appendix B (amendments) is still empty, and so is Appendix A (outcomes). This report supplies A.2, A.5, A.6, A.7 and A.8 from the artifacts.

Every number below was recomputed from the artifacts for this report rather than copied from a summary line. Where a recomputation disagrees with a stage's own output, both are given and the disagreement is named.

---

## 1. The result, in the numbers the pre-registration fixed

### 1.1 Class-stratified coverage (M8)

The verifiable subject matter is clause classes CC1 (state transition), CC2 (arithmetic invariant) and CC3 (length or format): **76 of the 91 inventory rows**. Within it, **42 rows are carried**.

| Class | Rows | Encoded | Deployment-modeled | Carried | Dispositioned out (barrier) |
|---|---|---|---|---|---|
| CC1 state transition | 37 | 31 | 3 | **34** | 3 (B7 true by construction) |
| CC2 arithmetic invariant | 3 | 0 | 0 | **0** | 3 (B5 string structure) |
| CC3 length or format | 36 | 8 | 0 | **8** | 28 (19 B5, 6 B8 outside any tool, 3 B7) |
| **CC1+CC2+CC3** | **76** | **39** | **3** | **42** | **34** |
| CC4 opaque primitive | 0 | 0 | 0 | 0 | 0 |
| CC5 test vector | 1 | 0 | 0 | 1 Vectored (see §5, D8) | 0 |
| CC6 timing / liveness / transport / trace-level | 14 | 0 | 0 | **0** | 14 (11 B2 transport, 2 B7, 1 B1 timing) |

Every one of the 48 dispositioned-out rows cites exactly one barrier from the closed list B1..B8, and the gate found **zero exclusions outside that list**. CC6 is carried at zero by design: those 14 rows are the timing, transport and trace-level obligations that no body-level verifier of any language discharges, and they are the reason the raw ledger ratio is not the headline. The raw ratio (42 carried against all 91 rows) would measure how much of RFC 826 is about transport and prose, not how far the verifier reaches.

CC2 sits at 0 of 3 and CC3 at 8 of 36. Those are real gaps, not rounding: the CC3 losses are the wire format (byte offsets computed from `ar$hln`/`ar$pln` carried in the same packet), excluded at Stage B as X1/X2 and booked here under B5 and B8.

### 1.2 The characteristic core

**19 of 19.** The core row set was fixed at Stage F, before any disposition was assigned, as the clauses whose loss would mean the protocol was not implemented at all. None was dispositioned out. All 19 are `Encoded`, all 19 are cited by a contract clause in the frozen tree, and all 19 of those clauses live in functions that verify body-faithful:

`A25 A26 A30 A36 A37 A38 A39 A42 A46 A53 A55 A57 A58 A59 A60 A61 A62 A64 A65`

### 1.3 Verification state of the tree

Re-run cold for this report, in a fresh directory with no `.verified.json` sidecar present:

```
$ llmll verify roots.ast.json --strict-verified-core
   body-faithful: arp-resolve, arp-request-emit, arp-request-hrd, arp-request-pro,
   arp-request-hln, arp-request-pln, arp-request-op, arp-request-sha, arp-request-spa,
   arp-request-tpa, arp-emitted-op-well-formed?, arp-hln-check, arp-pln-check, arp-frame,
   arp-merge, arp-add, arp-emission, arp-reply-op, arp-reply-sha, arp-reply-spa,
   arp-reply-tha, arp-reply-tpa
✅ roots.ast.json — SAFE (liquid-fixpoint)          exit 0
```

**22 of 22 functions body-faithful, zero body-fallback, exit 0.** Every one of the 39 `:source`-bearing postconditions is inside a function whose body was encoded as a verification condition and discharged, so no clause below rests on an unencoded body.

This corrects the Stage M artifact. `12-wave/wave.json` records `safe: false` and `body-fallback: arp-add`, because at the moment that check ran the `arp-add` hole was still open (see D3 and D4 in §5). The tree as frozen carries `arp-add`'s body and verifies.

### 1.4 Citation cross-check, recomputed

The frozen tree carries 39 `:source` strings (26 per-clause plus 13 whole-postcondition), each opening with a bracketed inventory tag. Recomputed against `06-disposition/inventory-dispositioned.json`:

- cited rows: **39**, distinct: **39**
- Encoded rows: **39**
- cited set == Encoded set: **true** (no row cited that is not Encoded, no Encoded row uncited)
- core rows cited: **19 of 19**

Stage L's lint reported the opposite (`0/39` cited, `RFC-COV-1 FAIL`) and halted the pipeline. That failure is an instrument defect, not a citation defect: the lint looks for a `[Tnnn]` tag while this run's inventory uses `[Annn]` ids. See D2.

---

## 2. The claim

> Given an RFC, an orchestrating agent built a formal specification traceable clause by clause to the source text, and a swarm of blind agents produced an implementation the compiler proves satisfies it. Every normative clause is dispositioned: verified, modeled, tested, or excluded with a cited reason. The protocol core is verified body-faithfully.

That is the claim this pipeline supports, and each conjunct maps to an artifact above: the traceable specification is the 39-citation clause surface (§1.4), the compiler's proof is §1.3, the disposition of all 91 rows is §1.1, and the core is §1.2.

One qualification belongs in the same breath as the claim rather than in a footnote. "The compiler proves the implementation satisfies it" is a statement about 22 function bodies against 39 postconditions, each function checked in isolation. It is not a statement about the composed protocol, about any sequence of packets, or about the bytes on the wire. §4 states every step between the machine-checked facts and the protocol-level reading, and what each would take to discharge.

---

## 3. What is not claimed

- **Not that RFC 826 is "verified".** 48 of 91 normative rows are dispositioned out with a cited barrier; 14 of them are timing, transport and trace-level rows that carry no verification evidence at all. The document as a whole was not verified and this pipeline cannot verify it.
- **Not that the agents would have failed without verification.** The benchmark is saturated: ARP is in the training data of every model involved. A claim that verification prevented an error the agents would otherwise have made is unfalsifiable here, and it is not what was measured. Nothing in this run is a controlled comparison against an unverified swarm.
- **Not that `:source` provenance proves fidelity to the RFC.** A `:source` string is a traceability pointer: it says which inventory row a clause is meant to carry, and the row says which RFC lines it came from. Whether the clause means what the English means is a question about prose and has no formal answer. The cross-check in §1.4 shows the pointers are complete and well-formed; it shows nothing about whether they point at the right thing.
- **Not that trace-level or timing properties hold.** Nothing here constrains retransmission, aging, timeouts, ordering between packets, or liveness. CC6 is carried at zero.

**The kills are not verification catching agent error.** Every mutant in §6 was written deliberately, after the fact, to test whether the contract excludes a behavior. No mutant is a bug an agent introduced. The one fill that failed (D3) failed on an AST schema key, was caught by the type checker before any solver ran, and its logic was correct as written. Nothing in this run is evidence that verification caught a semantic mistake by a model, and it should not be presented that way.

---

## 4. Trusted steps

Everything in this section is outside what the compiler checked. Each is stated as a schema with its premise, its conclusion, and what would be needed to discharge it.

### T1. Per-step to all-traces (trace induction)

**Where it applies.** C7 (the table is a partial function and *every transition preserves it*), C6 (the sender fields of *every emitted packet* name the emitter, therefore *every table entry* originates from the station it names), R1 and R2 (claims about what caches *end up* holding).

**The schema.** From "each step, run once from an arbitrary pre-state satisfying its guard, establishes P of its post-state" conclude "P holds in every state reachable by any sequence of receipts and emissions". That closure is an induction over traces. It is outside the decidable fragment this toolchain verifies, it was not attempted, and it is trusted here.

**Concretely.** `arp-merge` and `arp-add` are each proved at a single arbitrary key `<key-pro, key-pa>` with the pre-state entering as the pair `key-present?`/`key-hw`. Generalizing from one key to the whole table, and from one receipt to a run, are both outside the proof. `arp-frame`'s three postconditions are the frame conditions that would be the induction step, and they are proved; the induction itself is not.

**To discharge.** A trace semantics and an inductive invariant proof in a tool that has one. Not this fragment.

### T2. Branch decomposition and composition

The reception algorithm (RFC 197-234) is split into four functions. Three carry a precondition, and the compiler records them as obligations on a caller that does not exist in this tree:

```json
[{"fn":"arp-frame","requires":"(not (and (and supports? speaks?) (and (= key-pro pro) (= key-pa spa))))"},
 {"fn":"arp-merge","requires":"(and (and supports? speaks?) (and (and (= key-pro pro) (= key-pa spa)) key-present?))"},
 {"fn":"arp-add",  "requires":"(and (and supports? speaks?) (and (and (= key-pro pro) (= key-pa spa)) (not key-present?)))"}]
```

All three `pre` clauses verify at display level **`asserted`**, not `verified`. They are assumptions discharged by nobody. Writing G for `supports? ∧ speaks?`, K for the key match and P for `key-present?`, the three guards are `¬(G∧K)`, `G∧K∧P` and `G∧K∧¬P`. I checked by hand that these are pairwise disjoint and exhaustive, so the split covers every receipt exactly once. That check is a three-case truth table done by a reader, not by the toolchain, and if it were wrong the tree would still verify.

`arp-emission` and the five `arp-reply-*` field functions carry no precondition at all. The reply field map is therefore unconditioned: `arp-reply-op` returns `Rep` for every input, including a received reply. The only thing that stops a reply being emitted in response to a reply is `arp-emission`'s `Silent` clauses. Nothing ties the two together inside the proof.

**Why the split exists rather than one transition.** Stage H established (FINDINGS §3) that a user-defined callee inside a `pre` or `post` forces body-fallback, so a cross-function joint invariant cannot be written by calling the other function from a contract. The guards are duplicated inline instead. §7 records the textual agreement review the pre-registration required for exactly this reason.

### T3. Decoding

Every step takes decoded field values as parameters. The wire format is excluded (Stage B X1, X2): byte order, field offsets computed from `ar$hln` and `ar$pln`, and the parse itself. The assumption A-WF ("the received packet decoded to a well-sorted field tuple") is on for C1, C2, C3, C4, C5, C9 and C10. A decoder that mis-parses satisfies every clause in this tree.

### T4. Guards as instantiated relations

`supports?`, `speaks?`, `owns-target?`, `key-present?` and `key-hw` enter as booleans and ints. The intended readings are `supports(h, ar$hrd)`, `speaks(h, ar$pro)`, `owns_pa(h, ar$pro, ar$tpa)` and the table read at `<ar$pro, ar$spa>`. Nothing in the tree checks that a caller passes the relation evaluated at those arguments rather than at some others. The correspondence between the parameter and the host state it names is trusted.

### T5. Opaque sorts modeled as `int`

`Host`, `HwAddr`, `ProtoAddr` and `ProtoType` are `int`, appearing only under `=` and `!=`. No clause uses `<`, `+`, or any ordering, so the modeling adds no structure; but distinctness of two addresses is a hypothesis of the model, not a fact the model derives.

### T6. Properties true by representation, which carry no proof content

Booked as carried, but with no verification condition emitted, so no mutant can exercise them:

- **C7, functionality half.** A key holds `Absent` or `Bound int`; at most one hardware address per key is a fact about the datatype.
- **C9, emission half.** `arp-emission` has no `tha` parameter, so "emissions do not depend on `ar$tha`" is true because the field is absent from the signature. The table half of C9 does carry proof content (A82 on `arp-merge`) and is killed by a mutant.
- **A40, A41, A45** (the three Deployment-modeled rows). `ar$tha` freedom in generation is realized by the absence of a clause constraining it, and A45 is the statement that the recorded transition relation is the specification.

Stage G's own rule says a row true by construction is not covered and should be excluded under B7. These are the cases where the ledger books a row that no mutant can reach; they are named here so the 42 is read correctly.

---

## 5. Detection yield (M7)

Findings, each with a witness, itemized by locus. No denominator: the number of defects present is unknown, and any denominator would be invented. **Thirteen findings.**

| # | Locus | Finding | Witness | State |
|---|---|---|---|---|
| D1 | formalization | Extractor B missed five obligations that extractor A recorded: **A75** (279-280, `ar$pro` from the assigned Ethernet protocol types), **A81** (304-306, an implementation need not depend on `ar$tpa` when processing a reply), **A88** (344-346, a reply is sent directly and not broadcast), **A89** (353-354, the length fields suffice to locate the address fields), **A90** (400-401, the reply is addressed to the requester's hardware address). A81 and A88 are `Encoded` and cited in the frozen tree; A81 is the clause on `arp-add` that carries R3. Had B alone been used, no clause would state that `ar$tpa` gates the add branch for replies. | `03-extraction/{a,b}/extraction.json`, line ranges recomputed for this report; `10-roots/roots.llmll:281,313` | found, carried into the spec |
| D2 | driver | `RFC-COV-1` looks for a `[Tnnn]` inventory tag; this run's inventory uses `[Annn]` ids. All 39 citations were therefore reported as untagged and all 39 Encoded rows as uncited, the gate failed, and the pipeline stopped at Stage L. Recomputing the same cross-check against the actual id scheme: 39/39 Encoded cited, 19/19 core cited, no extras. The clause surface was never machine-frozen; §8 records that the wave then started anyway. | `11-freeze/rfc-cov-1.txt`; recomputation in §1.4 | found, not fixed |
| D3 | fill | The `arp-add` agent emitted its conditional with keys `then`/`else`. The AST schema provisioned to every agent requires `then_branch`/`else_branch` (`ExprIf`, `required`). `llmll patch` rejected it: `{"result":"PatchTypeError","diagnostics":[{"code":"E011","kind":"json-decode-error","message":"Error in $: key \"then_branch\" not found"}]}`. The body's logic was correct; four other fills in the same wave used the schema keys correctly. `wave.json` does not record this diagnostic; I recovered it by the forensic re-derivation of prereg §3.4 (copy the tree with the hole open, re-checkout, re-run `patch` with the recorded `patch-request.json`, no agent involved). | `12-wave/agent-15-arp-add/patch-request.json`; re-derivation command in §10 | found, resolved (§8) |
| D4 | driver | The checkout lock is **retained** when `patch` fails on the type-error path. Reproduced: after the `PatchTypeError` above, `checkout --status` returns `{"remaining_ttl":3557}` and re-checkout of the same pointer returns `hole at /statements/20/body is already checked out`, the exact string in the run's `checkout.err`. The hole's two remaining semantic attempts were unspendable and it terminated as `checkout-failed` before any second agent ran. Prereg §3.3 registered this failure in advance for `PatchVerifyError` and `PatchAuthError`; the type-error path extends that table. The driver's summary then printed `FINDINGS (exhausted budget; routed, never hinted): arp-add`, which is wrong in both halves: no budget was spent, and nothing semantic was found. | `12-wave/agent-15-arp-add/checkout.err`; `run.log:156`; reproduction in §10 | found, not fixed |
| D5 | instrument | Stage N's first baseline copy was stale: it held `arp-add`'s body as an unfilled hole. Under that copy `arp-add` verifies body-fallback, which emits no body VC, so mutants 1, 5 and 11 (`promiscuous-cache`, `reply-ignores-tpa`, `merge-key-substituted`, all sited on `arp-add`) would each have been booked as survivors at a site where no mutation can be refuted: three false "weak contract" readings from one wrong input file. Caught by hashing the baseline against `12-wave/roots.ast.json`; every result taken from the stale copy was discarded. | `13-kill-matrix/baseline-STALE-hole-at-arp-add.ast.json` sha256 `a750a9b9…52e480` vs baseline `69ad0f9a…4f5d90b` | found, fixed before booking |
| D6 | driver | The scoring script reported by the Stage N agent overwrites `mutants.json` with its verdict rows, discarding operators, target rows, sites and rationales, and discovers mutants by globbing `m-*.ast.json`, which drops the one entry that has no file and silently reports a denominator of 14 instead of the registered 15. Mitigated by writing the catalogue to `taxonomy.json` from the same literal. I can verify the mitigation (20 entries in `taxonomy.json`, 20 in `kill-matrix.json`, denominator intact at 15) but not the script: it is no longer on disk, so this row is relayed from the agent's log rather than reproduced. | `13-kill-matrix/agent.stdout.log`; `taxonomy.json`, `kill-matrix.json` | reported, mitigated |
| D7 | driver | The driver crashed assembling the matrix when a taxonomy entry has `file: null`: `TypeError: unsupported operand type(s) for /: 'PosixPath' and 'NoneType'` at `rfc_to_implementation.py:929`. The unwritable mutant is exactly such an entry. | `run.log:180-187` | found, fixed (the current driver guards `not m.get("file")` and books it `unwritable`) |
| D8 | contract | Row **A90** is booked `Vectored`, whose stated realization is "an executed `check` block that replays the worked example of lines 370 to 401 as a concrete two-station run". The frozen tree contains no `check` block. The single CC5 row is carried by an artifact that was never built, which is also why mutant 15 is unwritable. | `grep '(check' 10-roots/roots.llmll` returns nothing; `06-disposition/inventory-dispositioned.json` A90; `taxonomy.json` entry 15 | found, not fixed |
| D9 | contract | Scope C4 requires the reply to carry `ar$hrd`, `ar$pro`, `ar$hln`, `ar$pln` through unchanged. The tree has no `arp-reply-hrd`, `arp-reply-pro`, `arp-reply-hln` or `arp-reply-pln`, so that half of C4 has no site: no clause states it and no mutation can perturb it. Mutant 14 was written at `arp-request-pln` instead and its shortfall was disclosed rather than absorbed. | `11-freeze/ROOTS.txt` (22 functions); `taxonomy.json` `reply-drops-parameters.scope_note` | found, not fixed |
| D10 | compiler | `liquid-fixpoint` fails with a sort error when an ADT-returning callee appears inside a relational body: `The sort Emission is not numeric because Cannot unify int with Emission … _bv_call_emit_of_2 := int, ctor_noemit := Emission`. The call result is bound at sort `int` while the constructors keep the ADT sort. Constrains every two-run claim the architecture can state; `tha-irrelevance.llmll` compares `bool`-valued projections instead. | `07-feasibility/FINDINGS.md §3`, with reproduction | found, worked around |
| D11 | compiler | A same-file `def` cannot call another same-file `def` on a first run: the strict-core callee-admissibility gate demands persisted verified evidence and a cold run has no sidecar, so it fails with `core-membership-violation`. `def-shell` has no such gate, stays body-faithful, and passes `--strict-verified-core`. | `07-feasibility/FINDINGS.md §3` | found, worked around |
| D12 | reconciliation instrument | The one "B-only" row is not a coverage disagreement. B81 (404-406, a receiver discards a REPLY after merging, emitting nothing) is the same obligation extractor A recorded as A77 at lines 294-295, and A77 is `Encoded` and cited on `arp-emission`. The reconciler matches rows by line overlap, so an obligation a document states twice in different places reads as a disagreement. | `04-reconcile/data/reconciliation.json`; A77 vs B81 texts | found, not fixed |
| D13 | process | Four agent-stage contract failures, each recovered by re-running: Stage G exited 1 after 647 s; Stage K timed out at the 1800 s subprocess limit and left no manifest entry; Stage N twice exited 0 without writing its deliverable. | `run.log:27, 50-69, 159, 162` | found, recovered |

Two things the pre-registration forbids reporting as results, and which are therefore not reported here: the two extractors' agreement statistics (a process fact about extraction; two formalizations agreeing entails nothing, since both can be wrong the same way), and any fill rate presented as a quality score.

---

## 6. Kill matrix (M6), including survivors

The taxonomy was closed at Stage I: 15 kill-required mutants and 5 good twins. Stage N added none, renamed none and dropped none. Mutation is structural: the named function's `body` node is replaced wholesale in the parsed AST. Two instrument assertions ran on every entry before its verdict was taken: the body actually changed, and nothing but the body changed (the 39-clause `:source` surface, type declarations, parameter lists, `pre` clauses and return types re-serialized and compared byte for byte; `clause_surface_identical` true for every entry). Every verify ran against a freshly deleted sidecar.

**A killed mutant proves the contract excludes one specific behavior. That is eliminative evidence and it is the whole of what a kill establishes.** It does not corroborate that the clause says what RFC 826 says.

### 6.1 The 15 mutants

| # | Name | Site | Target rows | Operator | Outcome |
|---|---|---|---|---|---|
| 1 | promiscuous-cache | `arp-add` | A55, A57 | guard-drop | **refuted** |
| 2 | merge-after-opcode | `arp-merge` | A64, A53 | order-swap | **refuted** |
| 3 | old-address-wins | `arp-merge` | A65, A53 | update-suppress | **refuted** |
| 4 | reply-to-reply | `arp-emission` | A58, A77 | guard-drop | **refuted** |
| 5 | reply-ignores-tpa | `arp-add` | A81, A55, A57 | guard-drop | **refuted** |
| 6 | unicast-request | `arp-request-emit` | A42 | delivery-scope-flip | **refuted** |
| 7 | reply-broadcast | `arp-emission` | A62, A88 | delivery-scope-flip | **refuted** |
| 8 | reply-fields-swapped | `arp-reply-spa` | A59, A60 | field-substitute | **refuted** |
| 9 | discard-suppressed | `arp-emission` | A46, A47, A49 | discard-suppress | **refuted** |
| 10 | tha-sensitive-receive | `arp-merge` | A82 | irrelevant-field-sensitivity | **refuted** |
| 11 | merge-key-substituted | `arp-add` | A52, A79 | branch-substitute | **refuted** |
| 12 | hln-constant-wrong | `arp-request-hln` | A34, A67 | constant-substitute | **refuted** |
| 13 | op-constant-swap | `arp-request-op`, `arp-reply-op` | A17, A36, A61 | constant-swap | **refuted** |
| 14 | reply-drops-parameters | `arp-request-pln` | A76, A66 | field-preservation-drop | **refuted**, partial (see below) |
| 15 | vector-reply-mismatch | none | A90 | vector-field-perturbation | **unwritable, survives in the denominator** |

**14 written, 14 refuted, 1 unwritable. The denominator stays at 15.**

Three entries carry disclosed shortfalls rather than smoothed-over kills:

- **#2 merge-after-opcode** names both the target test and the opcode test. `arp-merge` has no `owns-target?` parameter, so only the opcode half is writable at that site.
- **#9 discard-suppressed** was written at the emission locus, which carries A46. The table-side discards A47 and A49 sit on `arp-frame` and were deliberately not touched: one change per mutant. Those two rows carry no mutant of their own.
- **#14 reply-drops-parameters** is partial for the reason in D9: the registered change is that *the reply* fails to carry `ar$hrd`/`ar$pro`/`ar$hln`/`ar$pln` through, and the tree has no reply-side site for it. Registered target A66 lives on `arp-request-hrd` and is untouched, so A66 should not be read as instrumented by this kill.

**#15 is a survivor of a particular kind and it is reported as one.** A90 is `Vectored`, not `Encoded`, and no clause in the tree instantiates the worked example at concrete field values, so no contract can refute a perturbation of it. Mutating `arp-reply-tha` instead would be refuted by A83, a row this entry does not target, and would report the vector as instrumented when it is not. Prereg §5.3 #15 anticipated the `unwritable` outcome; the entry is kept in the denominator rather than dropped.

### 6.2 The 5 good twins (correct variants, expected to survive)

| Name | Site | What it varies | Outcome |
|---|---|---|---|
| good-twin-unsolicited-reply-merges | `arp-merge` | dispatches on the opcode, every arm returns `(Bound sha)`: a REPLY merges exactly as a REQUEST does | **SAFE** |
| good-twin-tha-arbitrary | `arp-merge` | mentions `ar$tha` syntactically while the result stays invariant in it | **SAFE** |
| good-twin-optional-checks-omitted | `arp-hln-check`, `arp-pln-check` | both optional length checks return `true` unconditionally: a receiver that performs neither | **SAFE** |
| good-twin-multi-owner-target | `arp-reply-spa` | `(if (= spa tpa) spa tpa)`, which is `tpa` on both branches: a station owning several protocol addresses | **SAFE** |
| good-twin-structural-variant | `arp-emission` | `if` chain in place of the three-arm `match`, identical behavior | **SAFE** |

**5 of 5 survived, as registered.** Each kill would have been a finding: the first three would mean a contract forbids behavior RFC 826 permits, and the last two would mean a contract fixes syntax rather than behavior.

### 6.3 Spot-check

I re-ran four entries cold for this report and reproduced the recorded verdicts:

```
m-old-address-wins                  error: body verification of 'arp-merge' failed
                                    — implementation does not satisfy postcondition (constraint #20)
m-merge-after-opcode                error: body verification of 'arp-merge' failed
                                    (else-branch does not satisfy postcondition) (constraint #21)
m-reply-broadcast                   error: body verification of 'arp-emission' failed
                                    (then-branch does not satisfy postcondition) (constraint #23)
m-good-twin-unsolicited-reply-merges  ✅ SAFE (liquid-fixpoint)
```

Every refutation is localized to the named function and comes from a clause that cites RFC 826, not from a type error or a parse failure.

---

## 7. Cross-function agreement review (S4, prereg §1.3)

Registered as an acceptance condition because the toolchain cannot check it: guards that must agree across functions appear as duplicated inline predicates, and nothing verifies the copies. The review was never recorded; here it is, as literal predicate text per site.

**The reception gate `(and supports? speaks?)`**, four sites:

| Site | Literal text |
|---|---|
| `arp-frame` pre | `(not (and (and supports? speaks?) (and (= key-pro pro) (= key-pa spa))))` |
| `arp-merge` pre | `(and (and supports? speaks?) (and (and (= key-pro pro) (= key-pa spa)) key-present?))` |
| `arp-add` pre | `(and (and supports? speaks?) (and (and (= key-pro pro) (= key-pa spa)) (not key-present?)))` |
| `arp-emission` A46 | `(=> (not (and supports? speaks?)) (= result Silent))` |
| `arp-emission` A62/A88 | `(=> (and (and supports? speaks?) (and owns-target? (= op Req))) (= result (Unicast sha)))` |

**The key match `(and (= key-pro pro) (= key-pa spa))`**: three sites, identical text in all three.

**The target-ownership guard `owns-target?`**: `arp-add` A57 (`(=> owns-target? (= result (Bound sha)))` with its negative companion) and `arp-emission` A55 (`(=> (not owns-target?) (= result Silent))`), used as the same bare boolean at both.

**Verdict: agree.** The gate and the key match are textually identical, associativity included, at every site.

Two asymmetries that are not disagreements but change how the clauses read:

1. The table steps carry the gate as a `pre` (asserted, so their postconditions hold only under the assumed guard), while `arp-emission` carries it inline in postconditions that hold for all inputs. `arp-emission`'s clauses are the stronger form.
2. The `arp-reply-*` field functions carry no guard at all (T2). Their clauses say what a reply's fields are, unconditionally; nothing inside the proof connects that to whether a reply should be emitted.

---

## 8. Obligation ledger (M1) and deviations from pre-registration

### 8.1 The 15 obligations

Denominator frozen at Stage B. `discharged` requires both a verified clause and a killed mutant mapped to the obligation; `discharged (no refutation pressure)` carries its label every time it is read.

| Obligation | Verdict | Evidence |
|---|---|---|
| C1 merge precedes opcode | discharged | A64, A53 on `arp-merge`; mutants 2, 3 refuted |
| C2 add only if target | discharged | A57, A81 on `arp-add`; mutants 1, 5 refuted |
| C3 emission gate | discharged | A46, A55, A58, A77 on `arp-emission`; mutants 4, 9 refuted |
| C4 reply field map | **partially discharged** | swap half: A59, A60, A61, A83 on `arp-reply-*`; mutants 8, 13 refuted. Preservation half (`ar$hrd`/`ar$pro`/`ar$hln`/`ar$pln` unchanged): **not-attempted**, no site exists (D9) |
| C5 reply delivery | discharged (delivery-scope half) | A62, A88 on `arp-emission`; mutant 7 refuted. The "same hardware on which the request was received" half is vacuous under MD2, one link modeled, as registered in §5.6 |
| C6 no third-party relay | discharged (no refutation pressure) | A91 on `arp-reply-sha`, A38 on `arp-request-spa`. No mutant: the obligation quantifies over all emitted packets, which a single-body mutation cannot express. Closure to "every packet" is T1 |
| C7 table functionality | discharged (frame half) | A52 on `arp-frame`; mutant 11 refuted. Functionality half holds by representation, emits no VC (T6). Preservation across a run is T1 |
| C8 request generation | discharged | A32-A39, A42 on `arp-request-*`; mutants 6, 12, 13, 14 refuted |
| C9 `ar$tha` irrelevance | discharged (table half) | A82 on `arp-merge`; mutant 10 refuted; good twin 2 SAFE. Emission half true by construction, no VC (T6) |
| C10 discard on unsupported hardware or protocol | discharged | A47, A49 on `arp-frame`, A46 on `arp-emission`; mutant 9 refuted at the emission locus only |
| C11 Ethernet parameter agreement | discharged | A66, A67 on `arp-request-hrd`/`arp-request-hln`; mutant 12 refuted |
| C12 optional checks non-rejecting | discharged (no refutation pressure) | A48, A50 on `arp-hln-check`/`arp-pln-check`; good twin 3 SAFE. No mutant is mapped to A48 or A50, and prereg §5.6 did not register C12 among the obligations lacking refutation pressure. That omission is itself worth recording |
| R1 "the only bad information …" | **not booked, witness owed** | Stage H established the witness transition verifies SAFE (`merge-order.llmll`, `op = Rep` clause) and stated explicitly that the refutation still owes a concrete trace under A1 and A2 |
| R2 "each station will get the new hardware address" | **not booked, witness owed** | no trace artifact exists |
| R3 `ar$tpa` "not necessarily needed in the reply form" | **not booked, witness owed** | formal shadow present and killed (A81 on `arp-add`, mutant 5), which is evidence about the model. The witness under A4 was never exhibited |

**12 of 15 booked, 3 unbooked.** Failure to find a proof is not a refutation: R1, R2 and R3 need exhibited traces with their assumption sets, and Appendix A.3 was never written. Two of the twelve are partial (C4, C5) and three rest partly on representation rather than proof (C7, C9, and C4's absent half).

### 8.2 Deviations

| Registered | What happened |
|---|---|
| Appendix C preflight **C1**: "Stage L reported the clause surface FROZEN and RFC-COV-1 passed. Fail action: **Stop. The wave does not start.**" | RFC-COV-1 failed (D2) and the driver stopped at Stage L as designed. The stage was then re-entered as "already complete, skipping" and the wave ran. The clause surface was never machine-frozen. The cross-check in §1.4 shows it would have passed under the correct id scheme, but that is a recomputation done after the fact, not the gate |
| §4.1 wave agents: **four** (`--wave-agents 4`), "recorded now so it cannot be tuned to the outcome" | the wave ran at **five** concurrent agents |
| §3.3: operator chooses branch AS-IS or FIXED before the wave and records it in A.1 with the driver's sha256 | A.1 was never written. The observed lock retention (D4) is the AS-IS symptom. The driver on disk today has sha256 `8c709d0c…53df51`, which does not match the pinned `f45102b9…3b97c`; its mtime is 2026-07-26 16:59, after the wave, so the current file cannot corroborate what ran |
| §3.5: post-freeze changes to a body are class X, "run is invalid" | `arp-add`'s body is in the frozen tree with schema-correct keys, applied after `wave.json` was written (`wave.json` 17:48:34, `roots.ast.json` 18:38:55). The applied body is the blind agent's own conditional, identical modulo the `then`/`then_branch` key naming that D3 is about; no hint or reference solution appears anywhere in that agent's directory. No A.4 entry records who applied it or by what command, and the pre-registration requires one |
| §4.4 trigger **T1**: zero E1 (stale CAS) events means the per-file compare-and-swap was never exercised | no E1 event appears in the run log. **Registered here: this run makes no claim that concurrent filling is safe under this driver** |
| §4.4 trigger **T6**: any checkout failure classified as lock retention is a finding against the driver | one, `arp-add`. `patch-request.json` and `body.json` both exist in its directory, so a prior attempt reached submission: cause is lock retention, not contention. True-contention `conflict_rate` = 0/22 |

**Fill record (M3, M4, M5).** 22 holes, 21 filled on attempt 1, 1 terminated `checkout-failed`. Semantic attempts per hole: 1 for every hole; no `#2` agent was invoked anywhere in the run. Protocol events: E1 = 0, E2 = 1 (lock retention), E3 = 0.

### 8.3 Cost (M10)

Recorded stage time totals **7,844 s (2.18 h)** across the 11 stages the manifest timed: Stage H (feasibility) 2,014 s, Stage D (dual extraction) 1,424 s, Stage N 1,152 s, Stage I 984 s, Stage G 769 s, Stage M (the wave) 516 s, Stage B 445 s, Stage C 346 s, Stage F 195 s, Stages A/E/J under a second. The manifest has **no entry for Stage K** (root contract authoring), which timed out at the 1,800 s subprocess limit and was completed on a re-entry, and it does not count the failed attempts at Stages G and N. Actual cost is meaningfully higher than 2.18 h. The wave itself was 22 agent invocations at 5 concurrent, 29 s to 222 s each.

---

## 9. What this run supports, stated once more with its limits attached

An orchestrating agent read RFC 826 and produced a 91-row normative inventory in which every row is dispositioned: 39 encoded as contract clauses, 3 realized by a recorded model, 1 assigned to a test vector that was never built (D8), and 48 excluded, each citing one barrier from a list closed before the run, with zero exclusions outside it. The 39 encoded rows are cited one-to-one by the 39 `:source` clauses of a 22-function specification whose bodies were then written by blind agents, one hole each, no hints and no sibling bodies. The compiler proves all 22 bodies satisfy all 39 postconditions, body-faithfully, cold, exit 0. Fourteen deliberately wrong variants are each refuted by a clause that cites the RFC; five correct variants survive; one registered mutant could not be written and stays in the denominator as a survivor.

Within the verifiable classes, 42 of 76 rows are carried. The characteristic core is 19 of 19. Twelve of the 15 frozen obligations are booked, two of them partially; three await exhibited witnesses that this run did not produce.

Everything between "22 function bodies satisfy 39 postconditions" and "an ARP implementation behaves as RFC 826 says" is in §4: a trace induction that was not attempted, a branch partition checked by a reader, an assumed decoder, and guard parameters whose correspondence to host state nothing checks. The pipeline's product is that this list is short, written down, and separable from what the compiler proved, rather than absorbed into the word "verified".

---

## 10. Reproduction

```bash
# 1. The tree verifies, cold (§1.3)
mkdir -p /tmp/rfc826-verify && cd /tmp/rfc826-verify
cp .../12-wave/roots.ast.json .
llmll verify roots.ast.json --strict-verified-core      # SAFE, 22/22 body-faithful, exit 0

# 2. Citation cross-check under the correct id scheme (§1.4, D2)
python3 - <<'PY'
import json, re
tree = json.load(open('roots.ast.json'))
inv  = json.load(open('.../06-disposition/inventory-dispositioned.json'))['rows']
tags = []
for s in tree['statements']:
    if s.get('kind') != 'def': continue
    tags += [c['source'] for c in s.get('post_clauses', []) if c.get('source')]
    if 'post_source' in s: tags.append(s['post_source'])
cited   = {re.match(r'\[(A\d+)\]', t.strip()).group(1) for t in tags}
encoded = {r['cid'] for r in inv if r['disposition'] == 'Encoded'}
print(len(tags), len(cited), len(encoded), cited == encoded)   # 39 39 39 True
PY

# 3. Recover the arp-add diagnostic (D3), per prereg §3.4: no agent, no hint
cp .../13-kill-matrix/baseline-STALE-hole-at-arp-add.ast.json tree.ast.json
cp .../12-wave/agent-15-arp-add/patch-request.json .
llmll checkout tree.ast.json /statements/20/body       # returns a fresh token
# substitute that token into patch-request.json, then:
llmll patch tree.ast.json patch-request.json
#   {"result":"PatchTypeError","diagnostics":[{"code":"E011",
#    "message":"Error in $: key \"then_branch\" not found"}]}

# 4. Lock retention on the failing-patch path (D4)
llmll checkout tree.ast.json /statements/20/body       # hole at /statements/20/body is already checked out
llmll checkout tree.ast.json --status <token>          # {"remaining_ttl":3557}

# 5. Kill-matrix spot checks (§6.3)
for m in m-old-address-wins m-merge-after-opcode m-reply-broadcast \
         m-good-twin-unsolicited-reply-merges; do
  rm -f $m.ast.json.verified.json
  llmll verify $m.ast.json --strict-verified-core
done
```
