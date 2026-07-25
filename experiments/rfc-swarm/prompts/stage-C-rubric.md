# Stage C: the normativity rubric, before any extraction

Write `rubric.md`: the rule that decides which sentences of this RFC are **normative** and
therefore count in the denominator.

Write it **first**. A rubric written after seeing the clauses is a rubric fitted to them, and a
denominator produced by an unstated rule is not auditable.

## What it must contain

1. **Normative rules**, numbered `N1`, `N2`, ... Typically: imperative protocol behavior;
   packet-format definitions; explicit requirement words; state-machine transitions; error and
   exception behavior.

2. **Non-normative rules**, numbered `X1`, `X2`, ... Typically: motivation and rationale;
   examples and illustrative traces; historical and deprecated text; document metadata;
   statements about another protocol's behavior not imposed on the implementation.

3. **Tie-breaks**, explicitly. At minimum: one obligation per row; a definition is normative
   when an implementation could violate it and metadata when it only names a thing; a later
   amending RFC governs on conflict; and **when in doubt, mark normative**.

## Check the date

If the RFC predates RFC 2119 (March 1997) it has no MUST/SHOULD/MAY discipline, every
normativity judgment on it is interpretive, and the rubric is doing all the work. Say so, and
record the requirement word actually present per row. If it postdates RFC 2119 and declares the
convention, read the uppercase keywords at face value.

## Understand the consequence of the conservative tie-break

"When in doubt, mark normative" deliberately over-includes. That systematically adds rows which
later disposition out. It makes the denominator safe, and it makes the exclusion **ratio**
meaningless. That is an accepted trade: the gate later measures class-stratified coverage and a
closed barrier list, never a ratio ceiling.

## The pinned RFC text

```
{{rfc_text}}
```
