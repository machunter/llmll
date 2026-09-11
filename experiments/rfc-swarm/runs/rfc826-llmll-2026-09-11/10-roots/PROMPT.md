# Stage K: root contract authoring

Author the LLMLL **root contracts** that carry every `Encoded` inventory row. Write them to
`roots.llmll` in your working directory.

## The rule that defines this stage

**One contract clause per `Encoded` inventory row, each carrying its own `:source`, opened by
the bracketed row tag.**

```lisp
(post (=> (and (= st Transferring) (= len 512)) (= result Transferring))
  :source "[T065] RFC 1350 lines 361-362 - a full 512-byte data field means the transfer continues")
```

The bracketed `[Tnnn]` tag is what makes coverage mechanically checkable. Matching free prose
would be fuzzy, and a completeness claim cannot rest on fuzzy matching. A citation whose tag is
not an inventory row, a missing row, or a citation of an excluded row each fail the lint and
halt the pipeline.

Per-conjunct provenance means a multi-clause `pre` or `post` keeps **every** citation, so do
**not** distort the design into one-clause-per-function to make traceability work. Write the
contract the protocol wants, and give each conjunct its own clause and citation.

## Bodies are holes

Every function body is `?impl`. You are authoring **what must be true**, not how. The bodies
are invented later by a swarm of agents that will never see a reference solution, and writing
one here would destroy the experiment.

## Staying inside the body-faithful fragment

A contract the verifier cannot discharge is a trap for the swarm. Constraints that hold in the
shipped compiler:

- **Discriminate on nullary enum tags, not on payload-bearing ADT parameters.** A `match` ON a
  payload-bearing ADT parameter falls back from body-faithful verification; CONSTRUCTING one
  does not. So pass a decoded tag plus scalars, and return a constructed value.
- **Constructors are nullary or single-payload.** A record with two fields is not expressible
  as one constructor; carry the extra fields as sibling parameters.
- **A bare `string` compared to a literal falls back.** Model an enumerated wire field as a
  decoded enum, not as a string.
- **A nullary constructor in a `match` arm is written `((Idle) ...)`, never `(Idle ...)`.** The
  bare form is a binder and is rejected.
- **Do not name a parameter after a constructor** of any type in the module, even a different
  one: the emitted constraint file lowercases constructor names and the two collide, crashing
  the solver.
- **Import no ordering the RFC does not define.** If sequence numbers have no defined ordering
  or rollover in the source, reason by equality, disequality, and successor only.

## The language reference is in your directory

`LLMLL.md` (the language specification) and `llmll-ast.schema.json` (the machine-readable
JSON-AST shape) are present. Read them: they define the syntax, the type system, and which
predicates the verifier can discharge automatically. They say nothing about the target
specification, so consulting them is not a shortcut, it is the tool manual.

## Self-check before you finish

Run `/Users/burcsahinoglu/Documents/llmll/compiler/.stack-work/install/aarch64-osx/fb6fe6c221f779865d3ec4b4bcb2605daf33fef2eed18f10050f3f379667f27e/9.6.6/bin/llmll check roots.llmll`. It must typecheck. The pipeline will additionally run the
coverage lint in both directions and will not proceed until it passes.

## The scope decision

# Scope: the verification boundary for RFC 826

**Stage B artifact. Written before any clause has been extracted.**

Source: `00-source/rfc826.txt`, sha256 `01bc62fe6a37e90f1246ac43e8e145f1322b4ed1474836145c3da93d2bd3c8a6`,
470 lines. Hash re-verified against the manifest at the time this document was written.

All line references below are to that pinned file.

This document fixes where the boundary sits between what the verifier carries and what it does
not. It is written first so the boundary cannot be redrawn later around whatever happens to
succeed. Section 8 records the pre-commitments that make this checkable.

---

## 0. Two facts about the source that set the ceiling on every claim

These are properties of RFC 826 itself, not of our method, and they cap what any verification of
this document can claim. They are stated first because they constrain everything after.

**F1. There are no RFC 2119 keywords, because RFC 2119 did not exist.** RFC 826 is from November
1982; RFC 2119 is from March 1997. Counted over the pinned text: zero uppercase
`MUST`/`SHOULD`/`SHALL`/`REQUIRED`/`RECOMMENDED`/`MAY`/`OPTIONAL` tokens. The thirteen lowercase
modals that do occur are ordinary prose ("special care must be taken", line 65; "should be
submitted to", line 70), and four of them (lines 429, 430, 434, 457) sit inside the section the
RFC declares out of its own scope.

Consequence: normative content cannot be extracted by keyword. It has to be reconstructed from an
imperative algorithm description and from declarative statements about field meaning. That
reconstruction is a modeling decision, recorded as **M-NORM**, and every extracted clause in
Stage C must carry a pointer to the prose it was reconstructed from.

**F2. The reception algorithm is offered as a suggestion, not a mandate.** Line 199: the Address
Resolution module "goes through an algorithm similar to the following". Line 307 repeats the
framing: "the suggested processing algorithm described above". Line 50 puts the whole document
outside standards track: "This is not the specification of a Internet Standard."

Consequence, and this is the single most important scoping statement in this document: **the
strongest claim available to us is conditional.** We can prove

> any host that implements the algorithm of lines 203-225 satisfies property P

We cannot prove

> any conformant ARP host satisfies property P

because RFC 826 does not define conformance. A host that does something "similar" is within the
document's letter and outside our model. Every property statement in the eventual writeup carries
this antecedent explicitly. It is not a footnote and it does not get dropped in the summary.

---

## 1. What "the protocol core" means here

The core is a transition system over:

- a finite set of hosts on one broadcast medium,
- per host, a translation table mapping `<protocol type, protocol address>` to a hardware address,
- decoded ARP packet values in flight.

Its transitions are packet generation (lines 161-190) and packet reception (lines 197-225). That
is the whole of it. Everything else in the 470 lines is either rationale for these transitions,
worked examples of them, or explicitly disclaimed.

---

## 2. The wire-format boundary

**Decision: the core operates on decoded packet values. Byte-level parsing is excluded.**

RFC 826's four address fields are variable-length and their extents are carried in band:

```
 8.bit: (ar$hln) byte length of each hardware address     (line 146)
 8.bit: (ar$pln) byte length of each protocol address     (line 147)
nbytes: (ar$sha) ... n from the ar$hln field              (lines 149-150)
mbytes: (ar$spa) ... m from the ar$pln field              (lines 151-152)
nbytes: (ar$tha)                                          (lines 153-154)
mbytes: (ar$tpa)                                          (line 155)
```

and line 320 removes the last bit of slack: "There are no padding bytes between addresses. The
packet data should be viewed as a byte stream."

Deciding a statement like "the first byte of `ar$tpa` sits at offset `8 + 2n + m`" requires
arithmetic over the length fields composed with indexing into a byte string. That is string
structure plus integer arithmetic, which is outside the quantifier-free-plus-`forall` fragment we
target (section 6) and undecidable in general. It does not classify in, and no amount of
restructuring makes it classify in. So it goes outside the line deliberately rather than by
accident.

**A-PARSE (assumption, stated not proved).** The core is handed a fully decoded packet record:

| field | modeled as |
| --- | --- |
| `ar$hrd` | element of finite enumerated sort `HwType` |
| `ar$pro` | element of finite enumerated sort `ProtoType` |
| `ar$op` | element of finite enumerated sort `Opcode` = {REQUEST, REPLY} |
| `ar$sha`, `ar$tha` | elements of uninterpreted sort `HwAddr` with equality |
| `ar$spa`, `ar$tpa` | elements of uninterpreted sort `ProtoAddr` with equality |
| `ar$hln`, `ar$pln` | elements of an uninterpreted sort `Len` with equality only |

The length fields are carried, but they are used **only** for the optional consistency checks of
lines 205, 208 and 291. They never determine which bytes a field occupies, because in the model
fields do not occupy bytes. `Len` therefore needs equality and nothing else: the checks at lines
205 and 208 compare an observed length against a locally expected one, which is a `=` test.

**What classifies out, named in advance so it cannot be quietly reclassified:**

| Clause | Lines | Why out |
| --- | --- | --- |
| High-byte-first encoding of `ar$hrd`, `ar$pro`, `ar$op` | 63-66, 320-323 | byte-level representation |
| No padding between address fields | 320-321 | byte-level layout |
| Packet buffer may be reused for the reply | 268-270 | implementation storage, not observable behavior |
| "parse a protocol address" from the length fields | 353-355 | explicitly a parsing statement |

**The gap this leaves, stated plainly.** A parser that mis-splits the byte stream, for example one
that trusts an attacker-supplied `ar$hln` and reads `ar$spa` from the wrong offset, produces a
perfectly well-formed record in our model. We prove nothing whatsoever about that host. This is
the largest distance between the model and any deployed implementation, and it is exactly where
real ARP implementations have historically had memory-safety bugs. We are not covering that class.
Saying so here is the point of this section.

---

## 3. The ordering boundary

**Decision: the core reasons by equality and disequality only. No order is imported.**

RFC 826 defines no sequence numbers, no transaction identifiers, no timestamps, no version
counters, no generation numbers, and no rollover. This is not an inference from the prose; it is a
property of the packet format, which has exactly nine fields (lines 141-155), none of them ordered.
A search of the pinned text for ordering and sequencing vocabulary (`sequence`, `serial`,
`counter`, `increment`, `rollover`, `wrap`, `timestamp`, `clock`, `version`, `nonce`, transaction
id, `older`, `newer`) returns zero hits across all 470 lines.

So `HwAddr`, `ProtoAddr`, `HwType`, `ProtoType` and `Len` are sorts with equality and no order
relation, no successor, no arithmetic. There is nothing to compare and the RFC never compares
anything.

There are two places where an order could be smuggled in by inattention. Both are handled here,
before extraction, rather than discovered later:

**(a) "the new hardware address supersedes the old one" (lines 231-234, restated 443-445).**

This looks like an order and is not. It is not an order on hardware address *values*; nothing in
the RFC says a numerically larger or lexicographically later address wins. It is an order on
*trace positions*: whichever update executes later in the run is the one that persists. That is
supplied by the transition relation of the state machine, which is where "later" already lives. No
order relation on any data sort is needed, and none is introduced. This is the correct reading of
lines 445-447: "on a perfect Ethernet where a broadcast REQUEST reaches all stations on the cable,
each station will be get the new hardware address", which is a statement about what happens after
a later event, not about comparing two addresses.

**(b) Table aging, timeouts, and the daemon (lines 412-470).**

The RFC removes this itself, at line 416: "The implementation of these is outside the scope of this
protocol." The section is conditional throughout: "It may be desirable" (415), "Perhaps failure to
initiate a connection should" (430), "Or perhaps" (433), "Another alternative" (449), "Perhaps
manually resetting" (464), and it closes at line 468 with "This issue clearly needs more thought if
it is believed to be important." There is no normative content here to extract. Every timing
mention in the entire document is confined to this section, plus line 174's reference to
*higher-layer* retransmission, which is also outside the core.

Modeling any of it would require a clock, and a clock means an ordered time sort plus comparison,
which imports exactly the order this section refuses. **M-CLOCK** is recorded as a modeling
decision **not taken**. The consequence is accepted and stated: we can prove no liveness property,
no recovery-after-host-move property, and no bounded-staleness property. Those need a clock. We do
not have one, so we do not claim them.

**(c) Broadcast is a set, not a sequence.** Line 189 says the request is broadcast "to all stations
on the Ethernet cable". A set of recipients carries no delivery order between distinct receivers,
and we impose none. The network is modeled as nondeterministic delivery to each host independently.

---

## 4. What the modeled state deliberately carries

The test applied to each item below is: **does carrying this let us reason about something an
attacker can actually do?** Not: is it expressible. Items that are merely expressible are listed
in section 5 and refused.

### Carried, required by the algorithm's own branching

| ID | State | Source | Note |
| --- | --- | --- | --- |
| S1 | Per host: which hardware types it has, which protocols it speaks, its own hardware address, its own protocol addresses | lines 203, 206, 214 | These are the algorithm's three tests. Modeled as relations, not functions: the RFC never says a host has exactly one protocol address per protocol type, so `own_pa(Host, ProtoType, ProtoAddr)` stays a relation. Recorded as **M-MULTIADDR**. |
| S2 | The translation table, `tbl(Host, ProtoType, ProtoAddr, HwAddr)` with a functionality axiom | lines 170, 210-218 | Partial map. The functionality axiom is universally quantified and stays in fragment. |
| S3 | `Merge_flag` | lines 209-218 | Local to one reception. Carried because the interleaving of the merge step and the add step is the substance of the algorithm, not an implementation detail. |

### Carried, justified by attacker model

**S4. The link-layer frame source address** (lines 137-138, "48.bit: Ethernet address of sender").

This is transport surface and it is brought inside the boundary deliberately. The justification is
a capability, not expressibility:

An attacker on the same cable can transmit a frame whose Ethernet source address is its own while
setting `ar$sha` to any value it likes. RFC 826's algorithm never compares the two. It merges the
sender triplet into the table at lines 210-213, *before* the opcode is examined at line 219, and
the RFC is explicit that this ordering is intentional (lines 227-231, 302-309).

Carrying the frame source lets us state:

> **P-SPOOF**: the hardware address installed in the table for `<ar$pro, ar$spa>` is the hardware
> address that actually transmitted the frame

and prove that the algorithm of lines 203-225 **does not imply it**. That is a negative result
about a real on-link attacker capability, which is precisely what the attacker-model test asks
for. It is worth carrying the extra state to be able to say it.

Constraint on how S4 is used, to stop it strengthening the protocol by the back door: the frame
source is carried as an **observable in the state, never as a precondition on any transition**. No
modeled receiver is permitted to branch on it. Adding S4 changes what we can *state*; it must not
change what the modeled hosts *do*. Stage D must check this.

**S5. Frame destination mode: broadcast, or unicast to a named hardware address** (lines 188-190,
224-225, 400-401).

Required by the algorithm: line 224 says send the reply "to the (new) target hardware address on
the same hardware on which the request was received", which is a unicast with a specific
destination, and it is contrasted against the broadcast of line 189 and line 400's "sends the
packet directly (not broadcast)".

Attacker relevance: the asymmetry between broadcast requests and unicast replies is what makes an
unsolicited unicast reply a distinct attack shape from a forged broadcast request. With S5 we can
distinguish them; without it we cannot state either. Carried.

---

## 5. What is refused, and why

Each of these is expressible. Expressibility is not the test.

| ID | Refused | Lines | Reason |
| --- | --- | --- | --- |
| R1 | Multiple media, bridging, routing between cables | 161-164, 236-242 | We model one broadcast domain and a `same_link` predicate sufficient for line 225. Modeling more defends against no additional attacker capability; it only enlarges the state space. Recorded as **M-ONELINK**. |
| R2 | Packet buffer reuse, register and stack savings | 268-270, 315-318 | Implementation efficiency. The RFC itself frames both as conveniences. Zero defensive content. |
| R3 | Higher-layer routing, the decision to throw the outbound packet away and rely on higher-layer retransmission | 161-164, 172-175 | Outside the Address Resolution module by the RFC's own layering. |
| R4 | The monitor role | 326-355 | Excluded from the verified core, and recorded rather than dropped. Reason: the monitor's only difference from the core receiver is that it drops the "Am I the target protocol address?" test and "always enters" the triplet (line 337-339). That makes it strictly more permissive than the core. Verifying it would add a second principal and a second set of extracted clauses while defending against nothing the core does not already fail to defend against. Including it would buy a larger clause count and prove nothing. Re-includable in a later stage if a property is found that actually needs it. |
| R5 | The hardware name space registry and the assignment authority | 68-75, 272-277 | Administrative process, not protocol behavior. |
| R6 | Rationale prose in general | 245-323 | Non-normative by construction. The two exceptions are lines 227-234 and 302-309, which restate rules already present in the algorithm; those are extracted from the algorithm text, with the rationale cited as corroboration only. |

---

## 6. The fragment being targeted

Many-sorted first-order logic with equality:

- **Uninterpreted sorts**: `Host`, `HwAddr`, `ProtoAddr`. Equality only.
- **Finite enumerated sorts**: `HwType`, `ProtoType`, `Opcode` = {REQUEST, REPLY}, `Len`.
- **Relations only**, no function symbols beyond constants. The table is the relation
  `tbl(Host, ProtoType, ProtoAddr, HwAddr)` constrained by a universally quantified functionality
  axiom; host identity attributes are relations constrained the same way.
- **No arithmetic, no strings, no arrays with computed indices, no recursive datatypes, no
  cardinality constraints, no ordering relations on any sort.**
- Transition relations and invariants written so that verification conditions stay in the
  effectively propositional fragment: the quantifier alternation graph must be acyclic, and
  invariants are universally quantified.

The three boundary decisions above are what keep the model in this fragment. Section 2 removes
arithmetic and strings. Section 3 removes order. Section 5 keeps the sort structure flat. A clause
that needs any of them classifies out rather than forcing the fragment open.

---

## 7. The scope matrix

The headline of the eventual writeup. Committed now.

| Lines | Content | Verdict | Reason |
| --- | --- | --- | --- |
| 1-50 | Title, abstract, "not a standard" framing | OUT (context) | Sets F2, no extractable clause |
| 52-75 | Notes: byte order, naming authority | OUT | Byte representation (sec 2), administrative (R5) |
| 77-110 | Problem statement, motivation | OUT | Narrative |
| 112-126 | Constant definitions | **IN** | Finite enumerated sorts |
| 128-139 | Ethernet transmission layer header | **PARTIAL IN** | Source address as S4, destination mode as S5, type field as an enum tag; byte widths out |
| 141-148 | Fixed-width ARP header fields | **IN** as decoded values | Widths out per A-PARSE |
| 149-155 | Variable-length address fields | **IN** as sort elements, **OUT** as byte extents | The wire-format boundary, exactly here |
| 158-190 | Packet generation | **IN** | Core transition |
| 194-201 | Algorithm preamble, "similar to the following" | **IN** as the F2 antecedent | Establishes the conditional form of every claim |
| 203, 206, 214 | Hardware type / protocol / target-address tests | **IN** | Core branching, S1 |
| 205, 208 | Optional length checks | **IN**, as a per-host mode flag | "Optionally" means both behaviours conform, so every property must be proved for *both* settings. Recorded as **M-OPTCHECK**. |
| 209-218 | Merge, Merge_flag, conditional add | **IN** | The substance, S2 and S3 |
| 219-225 | Opcode test, field swap, reply send | **IN** | Core transition, S5 |
| 227-234 | Merge-before-opcode rationale, supersession | **IN** (corroborating) | Restates the algorithm; supersession handled per sec 3(a) |
| 236-242 | Generalization over hardware types | **IN**, free | Achieved by leaving `HwType` uninterpreted; costs nothing |
| 245-323 | "Why is it done this way??" | OUT | R6 |
| 302-309 | Target protocol address rationale | **IN** (corroborating) | Restates the line 214 test |
| 326-364 | Network monitoring and debugging | OUT, recorded | R4 |
| 367-410 | Worked example X and Y | OUT as specification, **IN as a mandatory test trace** | See below |
| 412-470 | Related issue: aging and timeouts | OUT | The RFC excludes it itself, line 416; needs M-CLOCK |

**The example as a test obligation.** Lines 367-410 are not normative and yield no clause. They are
still used: the model must be able to *exhibit* that exact trace, X broadcasts a request, Y merges
and replies unicast, X merges and discards. If the model cannot produce it, the model is wrong,
regardless of what it proves. This is a cheap, concrete falsifier and it is committed to here so
that a model which proves properties vacuously gets caught.

---

## 8. Pre-commitments

The purpose of writing this before extraction is to make the following checkable after it.

1. **Predicted IN, and expected to survive**: every row marked IN in section 7. If any of them
   classifies out during Stage C, that is a scoping error by this document, and section 7 gets an
   amendment with a date and a reason, in place. The original row is not deleted or reworded.
2. **Predicted OUT, and will not be quietly recovered**: the four wire-format clauses in section 2,
   all of R1 through R6, and all of lines 412-470. If any of them turns out to be needed for a
   property we want, the property is reported as not provable in this scope rather than the
   boundary being moved.
3. **No state beyond S1 through S5** enters the model. Any addition requires an attacker-model
   justification written in the same form as S4's, added to this file before it is used.
4. **S4 does not gate any transition.** A modeled receiver that branches on the frame source
   address is a bug in the model, not a feature.
5. **Every property carries the F2 antecedent.** "Any host implementing the suggested algorithm of
   lines 203-225", never "any ARP host".
6. **No ordering relation appears on any data sort.** If one appears, section 3 was wrong and the
   run reports that, rather than adding a `<` and continuing.

## 9. What this scope cannot deliver, stated up front

- No parser correctness, and no memory-safety claim. Section 2.
- No liveness, no recovery time bound, no staleness bound. Section 3(b), M-CLOCK not taken.
- No claim about hosts that implement something merely "similar" to the algorithm. Section 0, F2.
- No claim about multi-interface or bridged topologies. R1.
- No claim about monitors. R4.

The intended positive results are safety properties of the table under the algorithm of lines
203-225, and at least one intended result (P-SPOOF, section 4) is a **negative** one: a
demonstration that the suggested algorithm does not establish the binding between `ar$sha` and the
actual frame sender. A proof that a protocol fails to defend something is a result, and it is
listed here as an intended deliverable so it is not mistaken for a failure of the verification.


## The `Encoded` rows you must carry (one clause each)

[
 {
  "cid": "A27",
  "class": "C1",
  "disposition": "Encoded",
  "core": true,
  "reason": "Contract on the generation step: the hit branch is enabled exactly when there exists ha with tbl(self, ar$pro, ar$tpa, ha). The guard names both components of the key, so a module that matches on the protocol address alone and returns an entry recorded under a different protocol type falsifies the clause."
 },
 {
  "cid": "A28",
  "class": "C1",
  "disposition": "Encoded",
  "core": true,
  "reason": "Contract on the hit branch of the generation step: the address yielded to the caller is an ha with tbl(self, ar$pro, ar$tpa, ha), and the S2 functionality axiom (universally quantified, in fragment) makes that ha unique, so the step is deterministic in its result."
 },
 {
  "cid": "A32",
  "class": "C1",
  "disposition": "Encoded",
  "core": true,
  "reason": "Contract on the generation step: in the branch where no ha satisfies tbl(self, ar$pro, ar$tpa, ha), the successor state contains an in-flight frame tagged ether_type$ADDRESS_RESOLUTION (section 7 carries the type field as an enum tag). A module that leaves the miss branch silent, or that emits an untagged frame, falsifies the clause."
 },
 {
  "cid": "A33",
  "class": "C1",
  "disposition": "Encoded",
  "core": false,
  "reason": "Contract on the generation step: the emitted request's ar$hrd is the hardware type of the interface it leaves on, which under M-ONELINK is the Ethernet element of HwType. A sender that emits a different HwType element falsifies the clause and is dropped by every receiver at A46's guard."
 },
 {
  "cid": "A34",
  "class": "C1",
  "disposition": "Encoded",
  "core": false,
  "reason": "Contract on the generation step: the emitted request's ar$pro equals the protocol type that keyed the failed lookup, the same pt appearing in A27's guard, so the question asked on the wire is about the protocol the lookup missed on."
 },
 {
  "cid": "A36",
  "class": "C3",
  "disposition": "Encoded",
  "core": false,
  "reason": "Contract on the generation step: the emitted request's ar$pln is the Len element the sender locally expects for ar$pro, the same element that line 208's optional check compares against under M-OPTCHECK. The clause needs equality on Len and nothing more, and a sender emitting any other element is dropped by every receiver running with the check enabled."
 },
 {
  "cid": "A37",
  "class": "C1",
  "disposition": "Encoded",
  "core": true,
  "reason": "Contract on the generation step: the emitted frame's ar$op is the REQUEST element of Opcode. With A57's guard this is what puts a compliant peer on the reply branch. The numeral that element is encoded as is A8, which this scope does not carry."
 },
 {
  "cid": "A38",
  "class": "C1",
  "disposition": "Encoded",
  "core": true,
  "reason": "Contract on the generation step: own_ha(self, ar$sha) holds for the emitted request, so a sender advertises its own hardware address. The clause binds senders only; there is no matching guard at the receiver, and that absence is the negative result P-SPOOF, which S4 is carried in order to state."
 },
 {
  "cid": "A39",
  "class": "C1",
  "disposition": "Encoded",
  "core": true,
  "reason": "Contract on the generation step: own_pa(self, ar$pro, ar$spa) holds for the emitted request. Under M-MULTIADDR own_pa is a relation rather than a function, so the clause is membership, and a host with several addresses in one protocol satisfies it with any of them."
 },
 {
  "cid": "A40",
  "class": "C1",
  "disposition": "Encoded",
  "core": true,
  "reason": "Contract on the generation step: the emitted request's ar$tpa is the protocol address that keyed the failed lookup, the same pa appearing in A27's guard, which ties the address asked about on the wire to the entry that was missing."
 },
 {
  "cid": "A43",
  "class": "C1",
  "disposition": "Encoded",
  "core": true,
  "reason": "Contract on the generation step: the emitted request's frame destination mode is broadcast (S5), so the delivery relation offers the frame to every host on the link, independently and without order between receivers (section 3(c)). M-ONELINK collapses 'the cable originally determined by the routing mechanism' to the single modeled broadcast domain; the routing choice itself is R3 and is not carried."
 },
 {
  "cid": "A45",
  "class": "C1",
  "disposition": "Encoded",
  "core": true,
  "reason": "Contract on the receive step, one conjunct per guard: when any of the four guards (A46 on ar$hrd, A48 on ar$pro, A54 on ar$tpa, A57 on ar$op) is false, the successor state equals the pre-state on tbl and on Merge_flag and no frame is emitted. A receiver that merges the sender triplet on a hardware-type mismatch falsifies the clause."
 },
 {
  "cid": "A46",
  "class": "C1",
  "disposition": "Encoded",
  "core": false,
  "reason": "Contract on the receive step: every branch past line 203 is enabled only when own_hw_type(self, ar$hrd) holds (S1). The content of the guard is what this row adds to A45's discard clause, which refers to the guard without fixing what it tests."
 },
 {
  "cid": "A48",
  "class": "C1",
  "disposition": "Encoded",
  "core": false,
  "reason": "Contract on the receive step: every branch past line 206 is enabled only when speaks(self, ar$pro) holds (S1)."
 },
 {
  "cid": "A50",
  "class": "C1",
  "disposition": "Encoded",
  "core": false,
  "reason": "Contract on the receive step: Merge_flag is false at the point the table is consulted unless this same reception's merge branch sets it (A53), so the flag is local to one reception (S3). A receiver that carries a flag left set by an earlier packet skips the add at A56 and falsifies the clause."
 },
 {
  "cid": "A51",
  "class": "C1",
  "disposition": "Encoded",
  "core": true,
  "reason": "Contract on the receive step: the merge branch is enabled exactly when there exists ha with tbl(self, ar$pro, ar$spa, ha). As in A27 the guard names both components of the key, so a receiver that matches on ar$spa alone and overwrites an entry held under another protocol type falsifies the clause."
 },
 {
  "cid": "A52",
  "class": "C1",
  "disposition": "Encoded",
  "core": true,
  "reason": "Contract on the merge branch: the post-state satisfies tbl(self, ar$pro, ar$spa, ar$sha), no ha other than ar$sha remains under that key, and every other row of tbl is unchanged. Supersession (lines 231-234) is expressed as this post-state equality rather than as an order on hardware address values, per section 3(a)."
 },
 {
  "cid": "A53",
  "class": "C1",
  "disposition": "Encoded",
  "core": false,
  "reason": "Contract on the merge branch: the post-state has Merge_flag true. This constrains S3 rather than the table, so it is not contained in A52's clause, and it is the flag A56's guard reads."
 },
 {
  "cid": "A54",
  "class": "C1",
  "disposition": "Encoded",
  "core": true,
  "reason": "Contract on the receive step: the add branch and the reply branch are enabled only when own_pa(self, ar$pro, ar$tpa) holds. Under M-MULTIADDR this is membership in a relation, so a host with several protocol addresses in one protocol matches on any of them."
 },
 {
  "cid": "A56",
  "class": "C1",
  "disposition": "Encoded",
  "core": true,
  "reason": "Contract on the target branch: when Merge_flag is false, the post-state satisfies tbl(self, ar$pro, ar$spa, ar$sha) with every other row of tbl unchanged. This is the clause that installs a binding at a host that held none for the key."
 },
 {
  "cid": "A57",
  "class": "C1",
  "disposition": "Encoded",
  "core": true,
  "reason": "Contract on the receive step: the reply branch is enabled only when ar$op is the REQUEST element of Opcode, and the guard is read only after the table post-state is fixed (A61). A receiver that answers a REPLY falsifies the clause."
 },
 {
  "cid": "A58",
  "class": "C1",
  "disposition": "Encoded",
  "core": true,
  "reason": "Contract on the reply step, as four field equalities between the emitted record and the received one: own_ha(self, ar$sha') holds for the emitted frame, ar$spa' is the request's ar$tpa (which A54's guard has already established is one of the replier's own addresses), ar$tha' is the request's ar$sha and ar$tpa' is the request's ar$spa. The swap is stated as equalities, with no byte movement."
 },
 {
  "cid": "A59",
  "class": "C1",
  "disposition": "Encoded",
  "core": true,
  "reason": "Contract on the reply step: the emitted frame's ar$op is the REPLY element of Opcode. The numeral that element is encoded as is A9, which this scope does not carry."
 },
 {
  "cid": "A60",
  "class": "C1",
  "disposition": "Encoded",
  "core": true,
  "reason": "Contract on the reply step: the emitted frame's destination mode is unicast to the request's ar$sha (S5), and the frame is offered on the link the request arrived on (same_link, M-ONELINK). Unicast rather than broadcast is what makes a solicited reply a different shape from a forged broadcast, which is the reason S5 is carried at all."
 },
 {
  "cid": "A61",
  "class": "C1",
  "disposition": "Encoded",
  "core": true,
  "reason": "Contract on the receive step, stated as a non-dependence rather than as an order: the guards and post-state conditions of the merge branch (A51, A52, A53) and of the add branch (A54, A56) do not mention ar$op, so for two received packets differing only in ar$op the post-state of tbl is identical. That is 'merged before the opcode is looked at' as a single-transition property, which keeps it out of B3, and it is the clause under which an unsolicited REPLY updates the table exactly as a REQUEST does, the surface P-SPOOF reports on."
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
