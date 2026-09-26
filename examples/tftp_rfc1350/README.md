# tftp_rfc1350: TFTP built by a swarm of blind agents

TFTP (RFC 1350, plus the RFC 1123 §4.2.3.1 Sorcerer's Apprentice fix) taken through
the spec-from-RFC pipeline. Every one of the 124 normative clauses was dispositioned
before any contract was written; 46 were encoded, one clause per row, across 23 root
contracts carrying `:source` citations. Six agents, each seeing only its checkout
brief, then filled all 23 bodies. The filled tree verifies body-faithfully under
`--strict-verified-core`, and the frozen clause surface was byte-identical after the
wave.

The claim is the disposition ledger, not "TFTP is verified": Encoded is 46 of 124
rows (37.1%). The rest are deployment-modeled (20), vectored (5), or excluded with a
cited barrier (53). See [`VERIFICATION_SCOPE.md`](VERIFICATION_SCOPE.md) §4.

| File | What it is |
|---|---|
| [`VERIFICATION_SCOPE.md`](VERIFICATION_SCOPE.md) | Phase 0: pinned RFC sources, normativity rubric, the 124-row inventory and its dispositions, scope matrix, trusted composition schema |
| [`roots/tftp.llmll`](roots/tftp.llmll) | Phase 1: the 23 frozen root contracts with holed bodies |
| [`roots/ROOTS.txt`](roots/ROOTS.txt) | The only function names allowed to carry a `:source` |
| [`roots/FREEZE.md`](roots/FREEZE.md) | The freeze record: what is immutable, gate evidence, model shape |
| [`wave/tftp-filled.ast.json`](wave/tftp-filled.ast.json) | Phase 2: the tree after the agent wave, all 23 holes filled |
| [`wave/wave.json`](wave/wave.json) | Per-hole fill status and attempt counts |
| [`wave/RESULTS.md`](wave/RESULTS.md) | What the wave produced: attempts, detection yield, kill matrix, what is not claimed |
| [`wave/EXPECTED_VERDICTS.json`](wave/EXPECTED_VERDICTS.json) · [`wave/mutants.json`](wave/mutants.json) | The recorded kill-matrix verdicts and the mutant names they refer to |

## Commands (outputs reproduced against llmll 0.26.5)

Run from this directory, on a copy (`verify` writes a `.verified.json` sidecar).

**The filled tree: all 23 functions body-faithful and proved.**
```bash
llmll verify ./wave/tftp-filled.ast.json --strict-verified-core
```
```
   body-faithful: opcode-of, data-length-valid, error-code-valid, request-direction, request-next-state, request-reply, sender-next-block, sender-reply, sender-next-state, receiver-next-state, receiver-ack-block, step-responds, step-reply-kind, error-next-state, error-reply, error-is-terminal, illegal-op-reply, tid-valid, tid-matches, wrong-tid-next-state, wrong-tid-reply, spine-coupled, spine-implicit-ack
   Running liquid-fixpoint ...
✅ ./wave/tftp-filled.ast.json — SAFE (liquid-fixpoint)
```
Exit 0. `--trust-report` on the same file ends with `verified: 23`, `asserted: 0`,
and prints each function's RFC `:source` next to its pre and post.

**The frozen roots: contracts only, nothing proved yet.**
```bash
llmll verify ./roots/tftp.llmll
```
```
⚠️  ./roots/tftp.llmll — SAFE (liquid-fixpoint), partial: 0 of 23 contracted functions proved; 23 assumed, not proved: opcode-of, ...
   (--strict-verified-core fails on assumed functions)
```
Exit 0 (the list of 23 names is abbreviated above). This is the holed starting surface the agents were given, so every body is a
hole and every post is assumed.

## The kill matrix is recorded, not re-runnable

`wave/EXPECTED_VERDICTS.json` records 8 mutants of the agents' own bodies, all
refuted, and one correct good twin that stays SAFE. The mutant files themselves were
never committed and cannot be regenerated from this tree: `wave/mutants.json` only
names them, and `wave/RESULTS.md` describes each mutation in one line. This suite is
not part of `make refute-crux-gate`, so nothing in CI checks it.

Reproducing the wave itself needs a workdir outside this repository, so the agents
cannot read the committed contracts; the command is in
[`wave/RESULTS.md`](wave/RESULTS.md#reproducing).
