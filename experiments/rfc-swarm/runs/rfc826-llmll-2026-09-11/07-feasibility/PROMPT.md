# Stage H: feasibility probes, before authoring anything

Prove the core contract shapes actually verify **and** actually refute, before the pipeline
commits to this target.

## What to produce

For each probe: a small LLMLL program exercising one protocol-core shape, and a **mutant** of
it carrying a plausible bug. Write both files into your working directory, then write
`probes.json` describing them.

```json
[
  {"name": "sender-step",
   "file": "sender-step.llmll",
   "mutant_file": "sender-step-mutant.llmll",
   "bug": "resends the current DATA packet on a duplicate ACK (the Sorcerer's Apprentice bug)"}
]
```

## The language reference is in your directory

`LLMLL.md` (the language specification) and `llmll-ast.schema.json` (the machine-readable
JSON-AST shape) are present. Read them: they define the syntax, the type system, and which
predicates the verifier can discharge automatically. They say nothing about the target
specification, so consulting them is not a shortcut, it is the tool manual.

## The bar

The pipeline runs `/Users/burcsahinoglu/Documents/llmll/compiler/.stack-work/install/aarch64-osx/fb6fe6c221f779865d3ec4b4bcb2605daf33fef2eed18f10050f3f379667f27e/9.6.6/bin/llmll verify <file> --strict-verified-core` on both and requires:

- the probe: **SAFE** and **body-faithful**
- the mutant: **not SAFE** (refuted)

**A contract that cannot refute its own historically-attested bug is decorative.** If a mutant
verifies SAFE, the contract is too weak; strengthen it and probe again rather than proceeding.

Probe at least the main transition function and any joint or product invariant the architecture
will need. Where the protocol has a famous bug, that bug is a mandatory mutant.

## Do not write a reference solution

These probe bodies are working implementations of functions the swarm is meant to invent. They
stay in this directory and are never promoted into the deliverable. Carry forward the contract
shapes and the verdicts only.

## Language constraints worth knowing

- A nullary constructor in a `match` arm is written `((Idle) ...)`, never `(Idle ...)`.
- Do not name a parameter after any constructor in the module.
- Matching on a payload-bearing ADT parameter loses body-faithfulness; discriminate on nullary
  tags plus scalars and return constructed values.

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

