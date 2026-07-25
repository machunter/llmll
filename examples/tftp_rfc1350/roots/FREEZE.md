# TFTP clause surface: the freeze record

> **Status:** RFC-SWARM Phase 1 output, 2026-07-25. Frozen against compiler v0.14.66 (authored against v0.14.65; re-verified after the MATCH-NULLARY-1 fix).
> Procedure: [`docs/design/rfc-swarm-playbook.md`](../../../docs/design/rfc-swarm-playbook.md)
> stages K and L. Inventory: [`../VERIFICATION_SCOPE.md`](../VERIFICATION_SCOPE.md).

## What is frozen

[`tftp.llmll`](tftp.llmll): **23 root contracts carrying 46 `Encoded` inventory rows**, one
contract clause per row, each opened by its bracketed `[Tnnn]` tag. Those `:source`-bearing
clauses are immutable from this point.

The freeze is **scoped**, not blanket. `refine`-spawned sub-contracts are additive, carry no
`:source`, and are governed by the shipped spawn gates. That distinction is required rather
than convenient: `refine` grows the contract surface by definition, so a blanket freeze
would forbid the mechanism the wave depends on. Weakening a spawned contract makes the
root's obligation *harder* to discharge, not easier, so there is no laundering path from the
spawn channel into the clause layer.

[`ROOTS.txt`](ROOTS.txt) is the provenance monopoly list: only these 23 names may carry a
`:source` at all, enforced by RFC-COV-1's `--roots` check.

## Gate evidence

Binary confirmed as `llmll 0.14.66` from `compiler/.stack-work` before every run below (a
`stack exec llmll` from the repo root resolves to a stale binary; playbook anti-pattern 4).

```
$ llmll check examples/tftp_rfc1350/roots/tftp.llmll
✅ OK (28 statements)

$ python3 scripts/rfc_coverage.py \
    --inventory experiments/rfc-swarm/data/inventory-dispositioned.json \
    --trust-report /tmp/tftp-tr.json \
    --roots examples/tftp_rfc1350/roots/ROOTS.txt \
    --require-full-coverage
RFC-COV-1: 124 inventory rows, 46 Encoded, 60 citations found
  Encoded rows cited : 46/46
  core rows cited    : 15/15
RFC-COV-1 PASS
```

All four RFC-COV-1 checks pass at freeze strength: every citation resolves to a real row
(RESOLUTION), every `Encoded` row is cited (COVERAGE, 46/46), no clause cites an excluded
row (DISPOSITION), and only roots carry provenance (MONOPOLY).

60 citations resolving to 46 distinct rows. **12 rows are cited by more than one clause**,
which accounts for the difference: usually a row carried as both a `pre` and a `post` on one
function (T012, T030, T031, T032, T033, T068, T087, T120), and four rows reused as a
precondition elsewhere (T027 guards all four TID functions; T064, T077, T078 each appear on
a second function). Every such repeat states the same obligation, so no row is being
double-counted into the coverage figure: COVERAGE is measured over distinct rows.

Separately, three pairs of rows (T032/T073, T034/T074, T066/T081) state the same obligation
from two different RFC locations. Each keeps its own clause and its own citation, so the
inventory's duplication is preserved rather than collapsed.

**The trust report reads `asserted: 23`, and that is correct.** Every body is a hole. These
contracts are claims about what the swarm must satisfy, not evidence that anything does.

## Feasibility, and what it does and does not show

The whole clause surface was discharged once, by an **uncommitted** twin carrying a body for
each of the 23 roots (playbook stage H: probe bodies are working implementations of
functions the swarm is meant to invent, so committing them would plant a reference
solution). Result: **23/23 body-faithful, whole-module SAFE under `--strict-verified-core`.**

That establishes the contracts are jointly satisfiable inside the shipped decidable fragment
and that no root is a trap. It says nothing about whether an agent will find such a body,
and nothing about fidelity to the RFC.

### Kill matrix

Satisfiability alone would be consistent with a decorative contract set, so each core
obligation was mutated and re-verified. **9 of 9 refuted, no survivors:**

| Mutant | Rows it targets | Verdict |
|---|---|---|
| `sorcerers-apprentice` (resend current DATA on a duplicate ACK) | T113 | refuted |
| `block-off-by-one` (`acked + 2`) | T033 / T063 / T045 / T011 | refuted |
| `block-no-advance` (`acked`) | T011 | refuted |
| `short-block-inverted` (512 ends, short continues) | T013 / T065 / T066 / T081 | refuted |
| `ack-block-skew` (ACK echoes `datablk + 1`) | T032 / T073 / T082 | refuted |
| `wrong-tid-terminates` (injected packet kills the transfer) | T022 / T047 / T048 | refuted |
| `error-latch-open` (ERROR leaves the state unchanged) | T016 / T077 | refuted |
| `wrq-ack-block-one` (WRQ answered with ACK block 1) | T034 / T074 | refuted |
| `tid-range-wrong` (TID upper bound 65536) | T027 | refuted |

Read this correctly: a killed mutant proves the contract **excludes one specific behavior**.
It is eliminative evidence. It does not corroborate that the surviving contract says what
RFC 1350 says, which is a question about English prose and has no formal answer.

Two mutants first appeared to survive. Both were defective instruments: their bodies were
single tokens (`Terminated`, `st`) and the substitution hit the first occurrence anywhere in
the file, inside a comment and a type declaration respectively. Rebuilt to target the body
line, both refute. Recorded here because "survivor" and "broken mutant" are easy to confuse
and only one of them is a finding.

## Two compiler defects found while authoring

Both were found by authoring against this surface, and both are routed on the roadmap.

1. **[MATCH-NULLARY-1](../../../docs/design/finding-match-nullary-ctor-unsound.md) was a
   soundness defect, and it gated the wave. FIXED in v0.14.66.** A nullary constructor
   written bare in a match arm (`(Idle 1)` rather than `((Idle) 1)`) parsed as a catch-all
   binder, and the verifier then proved postconditions the generated program violates,
   returning SAFE and body-faithful under `--strict-verified-core`. That flag is the per-fill
   acceptance bar (playbook stage M), so an agent writing the intuitive form would have
   collected a verified stamp that meant nothing. The typechecker now rejects the bare form
   and names the correct one. Blast radius in the existing tree was zero (0 hits across 127
   sources and 1526 committed ASTs).

2. **[FQ-CTOR-COLLIDE-1](../../../docs/design/finding-fq-ctor-name-collision.md) shaped a
   parameter name in this file.** `error-reply` takes `refused: bool` rather than the natural
   `denied: bool`, because the `.fq` emitter lowercases constructor names and `XferState`'s
   `Denied` would collide, crashing liquid-fixpoint with a sort error naming a type the
   function never mentions. This one fails closed, so it costs an agent's retry budget rather
   than its correctness.

## Model shape, and why the signatures look like this

Recorded because it constrains what a fill agent may write, and because part of it is a
fragment limitation rather than a modeling choice.

- **Inputs are nullary enum tags plus int scalars; outputs are constructed packets.** In
  v0.14.66 a `match` **on** a payload-bearing ADT parameter falls back from body-faithful
  verification, while **constructing** one does not. The decoded opcode therefore travels as
  the nullary `PacketKind` tag with block numbers beside it as ints.
- **Constructors are nullary or single-payload** (spec §5.3.5), so `DATA`'s block number is
  the payload and the `bytes[512]` buffer plus its length travel beside the packet, which is
  the T061/T094 modeled record.
- **`Mode` is a decoded enum, not a string.** Bare `string` equality against a literal falls
  back in v0.14.66, so T118 is carried as `(= m Octet)`. This matches the T054 model
  ("mode is a decoded enum with the octet literal pinned") but **differs from T118's own
  disposition reason**, which said "using literal equality only". The row stays `Encoded`;
  its named contract shape is corrected here. Flagged rather than silently changed, per
  playbook stage G ("a row may be Encoded only if you can name the shape of the contract
  that carries it").
- **Block numbers carry no order.** RFC 1350 defines neither ordering nor rollover, so no
  clause compares two block numbers with `<` or `>`; the contracts use equality,
  disequality, and successor only (`VERIFICATION_SCOPE.md` §8).

## One clause was corrected during authoring

T022's first draft read `src ≠ conn ⟹ result ≠ Terminated`, which is false when the
connection was *already* terminated. It now reads
`src ≠ conn ∧ st ≠ Terminated ⟹ result ≠ Terminated`, which is the row's actual content:
a wrong-source-TID packet does not *drive* a live transfer into termination.

## Single module, and why

All 23 roots live in one file because **user ADT constructors do not cross module
boundaries**: `Module.hs`'s `toExport (STypeDef name body)` exports the type name only, so
`(open ...)` never injects `Idle` or `DataPkt` and a split tree fails to resolve them. This
does not serialize the wave, because checkout locks are per-hole (`CheckoutLock.lockTokens`
is a list keyed by JSON pointer), so concurrent agents can hold different holes in one file.
SWARM-1's dry run measures whether that holds in practice.

## What happens next

Phase 2 is SWARM-1's concurrency dry-run on the token-revocation tree, then the blind
concurrent wave on this surface. The MATCH-NULLARY-1 gate is cleared (v0.14.66).
