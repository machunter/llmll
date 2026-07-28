# Stage G: the disposition pass

Every row of the reconciled inventory gets **exactly one disposition and one class**. Write
the result to `inventory-dispositioned.json`.

## Dispositions

| Disposition | Meaning |
|---|---|
| `Encoded` | carried by a contract clause that reaches its class's tier |
| `Deployment-modeled` | realized by a recorded model, which you must state |
| `Vectored` | carried by an executed `check` block (test vector) |
| `Dispositioned out` | excluded, citing exactly one barrier from the closed list |

## Classes

`C1` state transition, `C2` arithmetic invariant, `C3` length or format, `C4` opaque
primitive, `C5` test vector, `C6` timing / liveness / transport / trace-level.

## Two rules that keep this defensible

1. **A row may be `Encoded` only if you can name the shape of the contract that carries it.**
   Write that shape into `reason`. "This is verifiable" is not a shape. "Contract on the
   receive step: `len < 512` implies the post-state is Terminating" is a shape.

2. **A row that is already entailed is NOT covered.** If the row's obligation follows from the
   declared types alone, or from the clauses carrying other inventory rows, it carries no
   verification evidence of its own. Exclude it under barrier `B7` and **name what entails it**
   in `reason`. This rule costs you coverage on purpose.

   Two limits on `B7`, both learned from a run where it was misapplied to the row that halted
   the gate. **Do not write "no mutant can exercise this row" unless you can say why**: whether a
   mutant exists is undecidable in general, and on RFC 4648 the claim was false for the one row
   that mattered. And **`B7` is for rows whose obligation you can express**. A row whose
   obligation cannot be stated in the model at all is not `B7`; it exits under the barrier naming
   why it cannot be stated, and the existence of some weaker form you *can* state does not change
   that. Excluding a clause because a weakened surrogate for it is vacuous is the one move this
   rule must never license.

## The closed barrier list

Every `Dispositioned out` row cites exactly one of these in a `barrier` field. **An exclusion
that fits none of them is a STOP condition** and the pipeline will halt: that is what replaces
a coverage-ratio ceiling, and it catches the real failure, which is an exclusion nobody can
justify.

{{barriers}}

## Do not chase a coverage number

Recovering an excluded row by modeling more state is legitimate only when the added state buys
assurance. The test is "does this rule defend against something an attacker can do", not "is
this rule expressible". Expressibility alone lets the ledger absorb transport mechanics that
improve a percentage and prove nothing.

## The characteristic core

These row ids were fixed **before** you saw any disposition, and they are the clauses whose
loss would mean the protocol was not implemented at all:

{{core_ids}}

**No core row may be `Dispositioned out`.** If you find that one must be, do not re-classify it
to make the gate pass: say so in its `reason`, and let the pipeline STOP. The target gets
re-scoped, not re-graded.

## Output contract

```json
{"rows": [
  {"cid": "T012", "class": "C1", "disposition": "Encoded", "core": true,
   "reason": "Contract precondition on the sender step: DATA n+1 is emitted only from a state whose last-acked block equals n."},
  {"cid": "T014", "class": "C6", "disposition": "Dispositioned out", "barrier": "B1",
   "reason": "Timeout detection and retransmission scheduling are timing properties with no single-transition encoding."}
]}
```

`barrier` is required on and only on `Dispositioned out` rows.

## The scope decision (fixed before extraction)

{{scope}}

## The reconciled inventory

{{inventory}}

## The pinned RFC text

```
{{rfc_text}}
```
