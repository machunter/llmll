# Stage B: the scope decision, before extraction

Write `scope.md`: where the boundary sits between what the verifier carries and what it does
not. This is decided and written down **before** any clause is extracted, so that the boundary
cannot be drawn around whatever happens to succeed.

State, explicitly rather than leaving it implicit in the types:

1. **The wire-format boundary.** Byte-level parsing of variable-length or NUL-terminated fields
   is string structure, outside the decidable fragment. Say whether the protocol core operates
   on decoded packet values and that parsing is excluded, or argue why not.

2. **The ordering boundary.** Do not import an order the RFC does not define. If sequence
   numbers have no defined ordering or rollover in the source, say that the core reasons by
   equality and disequality only, and that any needed order is a recorded modeling decision
   rather than a silent import.

3. **Anything the modeled state deliberately carries.** If you bring part of the transport
   surface inside the boundary, justify it by an attacker model, not by expressibility. The
   test is "does this rule defend against something an attacker can do", not "is this rule
   expressible". Expressibility alone lets the ledger absorb mechanics that buy a number and
   prove nothing.

The failure mode this stage exists to prevent is scoping optimism: promising verification for a
clause that later classifies out. The scope matrix is the headline of the eventual writeup, not
a post-hoc disclaimer.

## Provenance of the bytes you are reading

{{provenance}}

## The pinned RFC text

```
{{rfc_text}}
```
