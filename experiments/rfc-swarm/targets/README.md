# Pipeline targets

Source documents the driver can be pointed at. Each is consumed as verbatim text and pinned
by digest at stage A.

| Target | Source |
|---|---|
| TFTP | `https://www.rfc-editor.org/rfc/rfc1350.txt` (+ RFC 1123 §4.2) |
| ARP | `https://www.rfc-editor.org/rfc/rfc826.txt` |
| **the driver itself** | [`driver-spec.txt`](driver-spec.txt) |

## driver-spec.txt

An RFC-style specification of the driver's own stage discipline: the stage model, when a
completed stage may be skipped, what a gate must do, the acceptance criterion for delegated
work, token lifetime, isolation of independent agents, and reporting obligations.

368 lines, 78 MUST and 26 MUST NOT. Run it like any other target; `file://` URLs work:

```bash
scripts/rfc_to_implementation.py \
  --rfc-url "file://$(pwd)/experiments/rfc-swarm/targets/driver-spec.txt" \
  --workdir <dir outside this repo> \
  --agent-cmd 'claude -p "$(cat {prompt})" ...'
```

### Why it exists

The driver is unverified glue wrapped around a verifier, and it accumulated roughly a dozen
defects across two runs, none of which code review caught. Every serious one was a property of
sequencing and state rather than of arithmetic: a gate skipped because its own failure output
existed, a fill accepted without its body ever being applied, a token held across an agent call
until the hole wedged, a liveness check that matched the query asking the question.

Those are exactly the properties a refinement-type checker is good at, so the honest response to
"why is the driver buggy" is to specify it and verify the core.

### Feasibility, established before authoring

Four probes were written against the shipped compiler and then mutated to reproduce the defects
that actually shipped:

| Probe | Mutant reproducing the real bug | Verdict |
|---|---|---|
| skip decision | skip whenever artifacts exist | **refuted** |
| gate record | a failing gate records complete | **refuted** |
| fill outcome | accept without applying the body | **refuted** |
| liveness | any matching process counts as a run | **refuted** |

All four probes verify body-faithful under `--strict-verified-core`; all four mutants refute.
The contracts would have caught the defects that were shipped.

**The probe bodies are deliberately not committed.** They are working implementations of
functions a swarm is meant to invent, and committing them would plant a reference solution.
The contract shapes and the verdicts above are what carries forward.

### What this run would and would not be

It is **dogfooding, not a third experiment.** The specification is written by the same party
that maintains the tool, so it has none of the blindness that made the ARP run meaningful. It
demonstrates the fragment's reach on a program actually needed, and it is not another data point
on repeatability.

Expect a carried fraction well below TFTP's. The effectful surface cannot be proved, and it is
most of the driver's line count.

But §15 does **not** put it outside the program. It defines three tiers: **proved** (the stage
discipline of §§4-13), **asserted** (filesystem, fetch, diagnostics, clock, process creation and
concurrency, reached only through a declared capability or a named interface **in the program
itself**, contracts runtime-enforced, authority reportable per function), and **outside any
claim** (prompt content, agent internals, OS guarantees).

§15.4 rules out writing the effectful half in another language: nothing would then bound its
authority or enforce its contracts, and the boundary would rest on the author's word. That is
precisely the complaint against the current Python driver, so an implementation that repeated it
would not have fixed anything.

Measured, not assumed: a probe with a proved decision function and a `wasi.io` effect in one
module reports `verified: 1` for the decision and an `effect_summary` of `["stdout"]` for the
effect. The module block and the capability import demote nothing. The one genuine gap is
process spawning, for which there is no capability; that needs a single `def-interface` with an
FFI stub, which codegen already emits.
