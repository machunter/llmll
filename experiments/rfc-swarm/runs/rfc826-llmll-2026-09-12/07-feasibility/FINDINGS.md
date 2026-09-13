# Stage H findings: what the contract shapes can and cannot do

Six probe pairs, all verified with
`llmll verify <file> --strict-verified-core`. Every probe is SAFE and
body-faithful; every mutant is refuted. `--weakness-check` reports no spec
weakness on any of the six.

The probe bodies are working implementations of functions the swarm is meant to
invent. They stay in this directory. What carries forward is the contract shapes,
the representation decisions, and the fragment boundaries below.

## 1. Representation decisions the probes committed to

| Stage B object | Representation | Constraint it rides on |
| --- | --- | --- |
| `HwAddr`, `ProtoAddr`, `HwType`, table key | `int`, touched by `=` / `!=` only | No ordering operator and no arithmetic operator appears in any of the twelve files (audited by grep). `int` is a carrier for an uninterpreted scalar, not a number. |
| translation table | `map[int,int]` | Key is the `<protocol type, sender protocol address>` pair of lines 210-213 carried as one opaque injectively-encoded scalar. Map keys in the fragment are `{int, string}` only, so a genuine pair key is not expressible; the encoding is where that gap is absorbed. |
| `ares_op$REQUEST` / `$REPLY` / other | nullary-only sum `(type Op (\| Request) (\| Reply) (\| Other))` | Lowers to an int tag, stays in QF-LIA. `Other` is what makes the merge-before-opcode claim statable. |
| an emitted packet | admissible sum with a pair-nest payload, e.g. `(\| Send (int, ((int,int),(int,int))))` | Layout `(dst, ((ar$sha, ar$spa), (ar$tha, ar$tpa)))`. `ar$op` is the constructor, not a field. |
| "no packet emitted" | a nullary arm (`Silent`, `Resolved`) | Absence is a constructor, not a sentinel value. |
| a universally quantified frame | a free parameter `okey` plus a `pre` disequality | The fragment has no quantifiers. A Skolem witness recovers "every other key is untouched" as a quantifier-free obligation. |
| `ar$tha` in a request (line 312, "no meaning") | a free parameter the correct body never reads | In `resolve-out` the emitted request's `ar$tha` is the free `any-tha`, so the contract is discharged for every value at once. That is what keeps the underspecification representable instead of silently resolved. |
| recency / "supersedes" (Stage B O-1) | position in a nested store, nothing more | Step order appears in no clause as a value. |

## 2. Contract shapes confirmed to verify and to refute

1. **Gated pointwise table update.** `gate ⇒ has(result,k) ∧ get(result,k)=v`,
   plus the negative `¬has(tbl,k) ∧ tpa≠mypa ⇒ ¬has(result,k)`. The negative
   clause needs no gate conjunct, which makes it strictly stronger than the
   negation of the positive one, and it is what refutes promiscuous learning.
2. **Frame by Skolem witness.** `map-has result okey <=> map-has tbl okey` plus
   `map-has tbl okey ⇒ map-get result okey = map-get tbl okey`. Presence and
   value both need stating; presence alone lets a value change through.
3. **Frame against a named key.** Same shape with `tkey` (the packet's own target
   pair) instead of a generic witness. This is the one that refutes "learn both
   ends", which a generic witness catches only by luck of instantiation.
4. **Independence stated as an absence.** The merge-before-opcode claim is an
   ordering claim about control flow, and it becomes a quantifier-free obligation
   by *not mentioning* `op` in the outcome clause, plus one clause that names
   `Other` explicitly for citability. The body matches all three opcodes so a
   divergent arm is a live possibility the contract has to exclude.
5. **Constructed emission by constructor equality.** `result = Send(<full
   payload>)` under a guard, with the complementary `result = Silent`. One clause
   pins the decision and every field at once; it refutes any field permutation.
6. **A derivable clause kept separate on purpose.** `reply-emit` [R3] (the reply
   is not broadcast) and `resolve-out` [A3] (the request does not carry the sought
   address as its own) are both implied by the joint construction clause above
   them. They are kept because they are the clauses that carry the attacker-model
   content on their own terms and would survive a later split of the joint clause.
7. **Two-step composition.** Supersession, per-key independence, and a frame that
   survives both writes, in one body, as a nested store.

## 3. Fragment boundaries found the hard way

These cost a rewrite each and will cost the swarm the same unless carried forward.

- **A `def` cannot call a same-file `def`, even a verified one, in one pass.**
  `checkCalleeAdmissibility` wants the callee's body-faithful evidence, which does
  not exist yet during the pass that would create it. Consequence: every function
  is self-contained, and a shared gate predicate has to be written out at each use
  or passed in as a `bool`. Probe 1 writes the hardware/protocol/optional-length
  conjunction out in full; probes 2, 5, 6 take it as `gated`.
- **A map-returning callee is rejected at the strict-core gate.** So is a
  `map`-typed `let` whose right-hand side is an `if` (`Refused by: let`).
  Composition of state transitions is written as a **nested store**, not as a
  bound intermediate state.
- **`map-has` applied to a `map-put` in guard position is refused**
  (`Refused by: if`). A read of an intermediate table has to be discharged by
  writing the select-over-store equivalence out by hand:
  `has(put(t,k1,v),k2) ≡ (k2=k1) ∨ has(t,k2)`. See the commented guard in
  `supersede-two.llmll`.
- **Whole-map equality never reflects.** Every table postcondition is pointwise
  (`map-has` / `map-get`) or it silently leaves the fragment.
- **`map-get` carries a PROVE-polarity key-presence obligation**, discharged by
  the surrounding guard or by an implication antecedent in the clause itself. It
  works in both positions; `resolve-out` exercises it in the body and probes 1, 5,
  6 exercise it inside a post.

## 4. What the probes did *not* establish

- Nothing here bears on parsing (Stage B §2, gap G-5). No probe touches a byte.
- Nothing here bears on a multi-interface node (Stage B §5 item 1, gap G-3). The
  table key carries no `ar$hrd`, exactly as lines 210-213 have it.
- Nothing here bears on liveness, aging, or convergence (gap G-4).
- **The negative result stands and is not a probe.** Stage B §6 says the attacker
  may deliver any well-sorted decoded packet, so a clause of the form "the table
  only ever holds true bindings" is refuted by the *correct* implementation, not
  by a mutant. It is therefore unprobeable in the probe/mutant shape this stage
  uses — a probe requires SAFE and its mutant requires refuted, and a property the
  protocol does not have gives refuted on both. It is recorded here so Stage D
  does not mistake its absence from `probes.json` for an oversight.
- `supersede-two` composes exactly two steps. It is a bounded trace, not an
  induction. Stage B §1 anticipated k-induction for invariant-shaped clauses; no
  probe exercised that, so whether the architecture can state a genuine inductive
  table invariant is still open.
