# RFC-SWARM

Given an RFC, an agent builds the specification, then a swarm of blind agents builds the
implementation, and the compiler proves the implementation satisfies the specification.

**Start here: [`SUMMARY.md`](SUMMARY.md)** is the cross-run answer — both runs side by side,
what is established, what is not, and where the claim is weakest.

**The process is the deliverable, not any one protocol artifact.** The procedure is
[`docs/design/rfc-swarm-playbook.md`](../../docs/design/rfc-swarm-playbook.md) (why each stage
exists) and [`scripts/rfc_to_implementation.py`](../../scripts/rfc_to_implementation.py) (how to
run it).

## Run it

```bash
scripts/rfc_to_implementation.py \
  --rfc-url https://www.rfc-editor.org/rfc/rfc1350.txt \
  --amend-url https://www.rfc-editor.org/rfc/rfc1123.txt \
  --workdir runs/rfc1350 \
  --agent-cmd 'claude -p "$(cat {prompt})"' \
  --wave-agents 4
```

`--agent-cmd` is any shell command; `{prompt}`, `{out}`, and `{workdir}` expand. Stages are
resumable (`--from`, `--only`, `--force`) and every stage hashes its artifacts into
`MANIFEST.json`.

Before trusting any run:

```bash
scripts/rfc_to_implementation.py --self-test          # pins the mechanical stages to the TFTP run
scripts/rfc_to_implementation.py --workdir DIR --audit-blindness
```

`--self-test` replays the committed TFTP Phase 0 data through the deterministic stages and
asserts the exact published figures. It is what makes a green run mean more than internal
consistency.

## The fifteen stages

| | Stage | Kind | Produces |
|---|---|---|---|
| A | intake and provenance pinning | mechanical | pinned bytes + SHA-256 |
| B | scope decision, before extraction | agent | the stated boundary |
| C | normativity rubric, before extraction | agent | the rule that fixes the denominator |
| D | dual blind extraction | agent ×2 | two independent censuses |
| E | mechanical reconciliation | mechanical | agreement statistics + genuine disagreements |
| F | characteristic core, before dispositions | agent | the rows that define the protocol |
| G | disposition pass | agent | four-way ledger with a barrier per exclusion |
| H | feasibility probes | agent | probe verifies **and** mutant refutes |
| I | pre-registration | agent | criteria fixed before any wave agent runs |
| J | **the gate** | gate | core invariant + closed barrier list |
| K | root contract authoring | agent | one `:source`-tagged clause per Encoded row |
| L | **coverage lint, then freeze** | gate | RFC-COV-1 both directions |
| M | the swarm | agent ×N | filled bodies, blind and concurrent |
| N | kill matrix | agent | mutants executed, survivors reported |
| O | writeup | agent | the report |

## What a run does not claim

Worth reading before writing anything up from a run's output:

- **not** that the RFC as a whole is "verified": the ledger says which clauses are verified,
  modeled, tested, or excluded with a cited reason
- **not** that agents would have failed without verification; that is unfalsifiable on a
  saturated benchmark and it is not what is measured
- **not** that `:source` proves fidelity to the RFC; it is a traceability pointer, and fidelity
  is a question about English prose with no formal answer
- **not** that trace-level or timing properties hold

A killed mutant is **eliminative** evidence: it proves the contract excludes one specific
behavior. An unkilled mutant set proves nothing, and an agreement rate rises as contracts get
weaker. Report detection yield, with witnesses.

## The worked instances

**TFTP** (RFC 1350 + RFC 1123 §4.2.3.1) is where the playbook and this driver come from; its
contracts were authored by hand and only the fill wave was agent-driven. **ARP** (RFC 826) is
the first run where agents did every stage, contracts included:
[`runs/rfc826/RESULTS.md`](runs/rfc826/RESULTS.md).

| Artifact | |
|---|---|
| clause inventory and dispositions | [`examples/tftp_rfc1350/VERIFICATION_SCOPE.md`](../../examples/tftp_rfc1350/VERIFICATION_SCOPE.md) |
| frozen clause surface | [`examples/tftp_rfc1350/roots/`](../../examples/tftp_rfc1350/roots/) |
| pre-registration + Amendment 1 | [`PRE-REGISTRATION.md`](PRE-REGISTRATION.md) |
| the two blind extractions | [`data/`](data/) |

Results: 124 normative clauses; 46 Encoded, 20 modeled, 5 vectored, 53 excluded; **62/65 of
verifiable subject matter carried, 15/15 characteristic-core rows Encoded**. Dual extraction
agreed at Jaccard 0.8655 and kappa 0.9378.

**The sharpest lesson of that run is recorded in Amendment 1:** the pre-registered
exclusion-ratio ceiling was a *defective instrument*. Every timing/transport clause is excluded
by the definition of its class, so the threshold was breached by class assignment before any
scoping judgment was made. A ratio of that shape measures the RFC's genre composition rather
than the verifier's reach, and no complete protocol RFC can pass it. It was retired in writing,
not ignored. The driver does not implement a ratio ceiling, and stage I's prompt tells the agent
not to reintroduce one.

## Contents

| Path | |
|---|---|
| `prompts/` | the per-stage contracts the driver hands to agents |
| `data/` | the TFTP extractions, reconciliation, and dispositioned inventory |
| `tools/reconcile.py` | stage E: line-span reconciliation, kappa on 1:1 matched rows |
| `PRE-REGISTRATION.md` | the TFTP pre-registration and its amendment |
