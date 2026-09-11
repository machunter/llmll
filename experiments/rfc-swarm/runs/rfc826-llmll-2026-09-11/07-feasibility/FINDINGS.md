# Stage H findings: what carries forward

Six probes, six mutants, all twelve verdicts as required by the bar. The probe bodies are
working implementations of functions the swarm is meant to invent and **stay in this
directory**. What follows is the contract shapes and the constraints, which is what Stage D
inherits.

Verifier: `llmll verify <file> --strict-verified-core`, v0.23.1.
Every probe: `SAFE (liquid-fixpoint)`, `body_faithful: true`, `display_level: verified`.
Every mutant: `refuted`, with a `.fq` constraint index naming the branch.
No mutant wrote a `.verified.json` sidecar, which is correct: a refuted function writes none.

---

## 1. The model shape that verifies

Confirmed body-faithful under `--strict-verified-core`:

| Modeled thing | Shape | Note |
| --- | --- | --- |
| `HwAddr`, `ProtoAddr` | `int` | used with `=` and `!=` only |
| `Opcode` | nullary sum `(\| OpRequest) (\| OpReply)` | discriminated with `=`, never matched on |
| The front guards of lines 203, 206 | `bool` parameters | |
| "Am I the target protocol address?" | `bool` parameter | |
| The translation table | `map[int,int]` | `map-has` / `map-get` / `map-put` all reflect exactly |
| Emitted packets | **constructed** sums with nested-pair payloads | up to `(((int,int),(int,int)), int)` |
| "emits nothing" | a real nullary arm (`NoEmission`) | the discard rule needs a total function |

Three shapes were checked specifically because the fragment could have refused them, and did
not: a **map-valued `if`**, an arm that **returns the table unchanged** as a bare variable, and
**`map-get` under an implication antecedent** that does not hold on every path.

## 2. Constraints Stage D must design around

**No composite table key.** The map key class is `{int, string}`, so
`tbl(ProtoType, ProtoAddr) -> HwAddr` cannot be keyed on the pair. The probes key on protocol
address and carry the protocol type as the `proto-ok` guard instead. Scope section 4's S2 names
a four-place relation; the fragment gives a two-place map plus a guard. That is a real narrowing
and Stage D either accepts it or splits the table per protocol type.

**No quantifier in a contract.** There is no `forall k`. The frame condition is carried by a
**witness key** parameter (`table-frame.llmll`): a parameter of a body-faithful function is
universally quantified at the VC's outer level, so a clause about it is the frame condition and
not a sample of it. The cost is a proof-device parameter in the transition's signature. The
alternative Stage D may prefer, a separate relation over a before-table and an after-table, is
untested here; this probe shows the first form works, not that the second would not.

**Matching on a payload-bearing ADT parameter loses body-faithfulness.** Every probe therefore
takes nullary tags plus scalars in and returns constructed values out. No probe destructures a
packet.

**`int` is a carrier, not an order.** No clause in any probe compares two addresses with `<` or
`>`. Scope section 3 refuses an order on every data sort and `int` is simply the equality-
carrying scalar that `Σ_auto` offers. This is the pre-commitment most easily broken by
inattention. The check that actually works is on operator position, not on the bare characters:
`rg '\((<|>|<=|>=)\s' *.llmll` and `rg '≤|≥' *.llmll`, both empty across all twelve files. A
plain search for `<` and `>` does not work — it matches the `=>` implication sugar and the
`<protocol type, sender protocol address>` triplet notation that every `:source` string quotes.

## 3. One contract was too strong and had to be fixed

The first draft of `resolve-out.llmll` carried

```lisp
(post (=> (not (map-has tbl tpa))
          (not (= result (BroadcastRequest (pair (pair own-hw tpa) tpa))))))
```

and was **refuted**. When a station resolves its own protocol address, `own-pa = tpa`, and the
transposed packet and the correct packet are the same value: no contract can separate them. RFC
826 never rules that case out. The fix guards the clause with `(not (= own-pa tpa))` rather than
constraining callers with a `pre` the RFC does not license. The mutant is still refuted, by this
clause and independently by `[A32]`.

Worth carrying forward as a pattern: a "field X is not field Y" clause is false wherever the two
fields can coincide, and in this protocol they often can.

## 4. The negative result is stateable

`spoof-binding.llmll` proves the weak, true binding (the table holds what the packet **asserted**
in `ar$sha`); its twin shows the strong claim (the table holds the address that **actually
transmitted**) is refuted. Scope pre-commitment 4 — S4 is an observable, never a precondition on
a transition — is mechanically checkable in this shape: `frame-src` is in the signature and
absent from the body, and a reader can confirm it by reading four lines.

This is the one mutant whose mutation is in the contract rather than the body, because the claim
being knocked down is a claim about the protocol, not about an implementation of it.

## 5. Not probed

- The example trace of lines 367-410, which scope section 7 commits to as a mandatory falsifier.
  It is a multi-step trace across two hosts; nothing here establishes that the eventual model can
  exhibit it.
- Cross-function composition. Every probe is a single `def`. Assume-guarantee across the
  reception step and the reply step is untested.
- The `M-OPTCHECK` obligation from scope section 7: every property proved for **both** settings
  of the optional length checks of lines 205 and 208. The probes fold both checks into one
  `proto-ok` / `hw-ok` guard and do not separate the two settings.
