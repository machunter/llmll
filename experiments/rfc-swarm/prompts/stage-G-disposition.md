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

2. **A row that is true by construction is NOT covered.** If the model admits no constructor
   for the forbidden thing, no mutant can exercise the row, so it carries no verification
   evidence at all. Exclude it under barrier `B7` rather than counting it. This rule costs you
   coverage on purpose.

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
