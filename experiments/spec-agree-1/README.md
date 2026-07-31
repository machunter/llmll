# SPEC-AGREE-1 — comparable-fragment measurement

> **Status:** Complete. Figures published in `docs/design/spec-agreement-proposal.md` Rev 1 §0.
> **Last updated:** 2026-07-31
> **Owner:** experiment-lead
> **Consumer:** `docs/design/spec-agreement-proposal.md` §0.3 (Result), §0.4 (M-1, M-2, M-3)

## 1. Purpose

SPEC-AGREE-1 Rev 1 settled its own scope by measurement rather than by argument: it reports what
fraction of the committed RFC-SWARM corpus the shipped contract-subsumption gate can decide, and
scopes the instrument to that fraction. Rev 0 had estimated "roughly a fifth to a quarter" of
`Encoded`; the measured figure is 10.6%, which is what moved the proposal's disposition.

This directory is the reproducibility contract for that number. The measurement was originally run
from a throwaway script; it lives here so the figure can be re-derived, and so the corpus or the
gate moving under it is detected rather than silently invalidating a published claim.

## 2. What this harness is NOT

- **Not an agent harness.** It invokes zero models and makes zero API calls. Agent-effectiveness
  work is `experiments/minimal-agent/`; the RFC-SWARM runs it reads are `experiments/rfc-swarm/`.
- **Not a compiler invocation.** It does not build or run `llmll`. It transcribes the gate's
  predicate into Python and applies it to committed JSON artifacts, so it is not evidence about
  what the compiler does at runtime, only about what the gate's stated predicate admits.
- **Not a CI gate.** Nothing in `scripts/version_gate.sh` or `scripts/check-examples.sh` calls it.
  Run it by hand when the corpus, `RefineReuse.hs`, or `FixpointEmit.hs` changes.

## 3. Method

The gate is `qfContract` (`compiler/src/LLMLL/RefineReuse.hs:281-285`):

```
qfContract c = classifyContractFragment c == "qf_lia"
               && not (contractMentionsArrOp c)
               && not (clauseUF (contractPre c))
               && not (clauseUF (contractPost c))
```

`ufBearing` (`RefineReuse.hs:289-299`) and the array-op families
(`FixpointEmit.hs:1577,1581`) are transcribed alongside it.

Two properties of the transcription bound what the output supports:

1. **`classifyContractFragment` is approximated as "at least one clause present."** That is
   generous, so every figure is an **upper bound** on comparability. A tighter transcription can
   only move the fraction down.
2. **The corpus is authored contracts, not stage-H probes.** Both runs read here passed gate J.
   That is a stronger sample for the scope question than probes would be, and a weaker one for the
   pre-authoring timing the original F-1 assumed.

Row counting follows **EC-4**: a row is comparable only when *every* clause citing it lives in a
comparable contract. Clauses cite inventory rows through the leading `[cid]` of their `:source`
field, and only rows dispositioned `Encoded` in the run inventory are counted.

## 4. Inputs

| Run | Contracts | Inventory |
|---|---|---|
| TFTP (RFC 1350) | `examples/tftp_rfc1350/wave/tftp-filled.ast.json` | `experiments/rfc-swarm/data/inventory-dispositioned.json` |
| ARP (RFC 826) | `experiments/rfc-swarm/runs/rfc826/implementation.ast.json` | `experiments/rfc-swarm/runs/rfc826/inventory-dispositioned.json` |

Two available runs are excluded, with the reason recorded in `manifest.json`: RFC 4648 stopped at
gate J and so carries no authored contracts, and RFC 1982 serial has zero contract-bearing defs and
contributes to neither denominator.

## 5. Running it

```sh
python3 experiments/spec-agree-1/scripts/sigma_subsume.py          # tables
python3 experiments/spec-agree-1/scripts/sigma_subsume.py --json   # machine-readable
```

No dependencies beyond the standard library.

Exit status is the regression check:

| Status | Meaning |
|---|---|
| 0 | every measured figure matches the value pinned in `manifest.json` |
| 1 | a figure drifted; the corpus or the gate changed under a published claim |
| 2 | an input artifact is missing or unparsed |

The pinned values in `manifest.json` are exactly the figures printed in
`spec-agreement-proposal.md` Rev 1 §0.3. Changing a pin means editing the proposal in the same
commit.

## 6. Result at `fa4b6b9`

| Unit | TFTP | ARP | Combined |
|---|---|---|---|
| Contract-bearing defs | 12 | 9 | 21 |
| Comparable defs | 2 | 1 | 3 (14.3%) |
| `Encoded` rows | 46 | 39 | 85 |
| `Encoded` rows cited by a clause | 35 | 26 | 61 |
| **Comparable rows** | **7 (15.2%)** | **2 (5.1%)** | **9 (10.6%)** |

Abstention histogram over all 18 non-comparable contract-bearing defs: **13 nullary constructor
terms, 5 constructor applications, 0 array ops, 0 measures.**

Comparable rows by class: TFTP `{C2 5, C3 1, C1 1}`, ARP `{C3 2}`. The comparable defs are TFTP
`sender-next-block` and `receiver-ack-block`, ARP `arp-request-pln`.

## 7. What the numbers were used for

Each of the three findings in §0.4 rests on a different column above, so re-running this script is
what keeps them checkable:

- **M-1** (the fraction is below both the Rev 0 estimate and the threshold the review's own
  question names) rests on the comparable-rows line.
- **M-2** (the clause taxonomy is not a proxy for the solver fragment, so a class-scoped instrument
  cannot be built as the review described) rests on the class breakdown: TFTP splits its ten
  `Encoded` C2 rows five comparable and five not, and ARP has zero `Encoded` C2 rows at all while
  two comparable C3 rows sit undecided.
- **M-3** (the gap is constructor terms, and Lever A is not on the critical path) rests on the
  histogram: all 18 abstentions fire on `ufBearing`'s uppercase-head clauses, none on
  `contractMentionsArrOp`, none on a measure.

M-3 is the finding that reorders work: a constructor-capable subsumption backend, not Lever A, is
what would move the fraction, so it precedes the N-way harness.
