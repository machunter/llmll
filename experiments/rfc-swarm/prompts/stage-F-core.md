# Stage F: name the characteristic core

Write `core.json`: the clauses that make this protocol **this protocol**, the handful whose
loss would mean you had not implemented it at all.

Do this **now**, before any disposition exists, so the set cannot be drawn around whatever
happens to succeed. That ordering is the whole value of this stage.

## Output contract

```json
{"core_ids": ["A012", "A013", "A016"],
 "rationale": "one sentence per id, saying why losing it would mean the protocol was not implemented"}
```

## How to choose

Ask of each candidate: if an implementation got this wrong but everything else right, would a
competent reviewer say it had implemented the protocol? If yes, it is not core. Expect a
handful to a couple of dozen rows, not a majority of the inventory.

Favor the clauses that carry the protocol's characteristic discipline: its sequencing rule, its
termination rule, its error behavior, and any rule a later document added specifically to fix a
known bug. Do not include a clause merely because it is important-sounding, and do not include
one because you expect it to be easy to verify. You do not yet know what will verify, and that
is deliberate.

## Consequence

No row named here may later be dispositioned out. If one is, the pipeline STOPs and the target
is re-scoped rather than re-graded. Choosing the core honestly now is what gives that condition
its force.

## The reconciled inventory

{{inventory}}

## The pinned RFC text

```
{{rfc_text}}
```
