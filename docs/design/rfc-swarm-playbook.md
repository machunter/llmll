---
name: rfc-swarm-playbook
title: "RFC to verified implementation: the repeatable process"
status: "Rev 0, derived from the TFTP Phase 0 execution of 2026-07-24"
date: 2026-07-25
author: main-agent, from an executed instance
consumers: [orchestrating agent, user, language-team, professor, experiment-lead]
---

# RFC to verified implementation: the repeatable process

**What this document is.** An executable procedure. Its protagonist is an **orchestrating agent**
that is handed an RFC and a working LLMLL toolchain, builds the *specification* (the "what"),
and then spawns a swarm of blind agents to build the *implementation* (the "how"). It is written
as instructions to that agent, because the process, not any single protocol artifact, is the
thing being demonstrated. A second RFC run through it should reproduce the shape of the first.

**Relationship to the pipeline design doc.** [`spec-from-rfc-pipeline.md`](spec-from-rfc-pipeline.md)
defines the *stages* S0-S5 and the clause taxonomy: it answers "what are the parts". This
document answers "how do you actually run it, in what order, with what decision rules, and what
stops you". Where the two disagree, this one is the operational authority, because it was
derived from an execution rather than from a design.

**Worked instance.** Every stage below cites what it produced on the first full run, TFTP
(RFC 1350 + RFC 1123 §4.2.3.1), 2026-07-24. Artifacts:
[`examples/tftp_rfc1350/VERIFICATION_SCOPE.md`](../../examples/tftp_rfc1350/VERIFICATION_SCOPE.md),
[`experiments/rfc-swarm/PRE-REGISTRATION.md`](../../experiments/rfc-swarm/PRE-REGISTRATION.md),
[`experiments/rfc-swarm/data/`](../../experiments/rfc-swarm/data/).

---

## 0. The claim this process supports

State it precisely before starting, because the wording constrains every later step:

> Given an RFC, an orchestrating agent builds a formal specification traceable clause by clause
> to the source text, and a swarm of blind agents produces an implementation that the compiler
> proves satisfies it. Every normative clause of the source is dispositioned: verified, modeled,
> tested, or excluded with a cited reason. The protocol core is verified body-faithfully.

What it does **not** claim: that the RFC as a whole is "verified"; that agents would have failed
without verification (the benchmark is saturated, so that is unfalsifiable); that `:source`
provenance proves fidelity to the RFC; that trace-level or timing properties hold.

## 1. Roles, and the firewall between them

| Role | Who | Does | May see |
|---|---|---|---|
| **Orchestrator** | one agent, long-lived | runs this playbook, spawns the others, assembles artifacts | everything |
| **Extractor** | 2+ agents, blind to each other | clause census from verbatim RFC text | RFC bytes + rubric only |
| **Disposition** | 1 agent | assigns class and disposition per row | inventory + fragment capability |
| **Contract author** | agent(s) | root contracts, one clause per Encoded row, `:source`-tagged | inventory + RFC |
| **Fill** | N ≥ 4 agents, concurrent, blind | function bodies, sub-decomposition via `refine` | **the checkout brief and nothing else** |
| **Auditor** | human | named checkpoints below, and nothing else | everything |

The fill agents' isolation is the demonstration. They get no reference solution, no hints, no
sight of one another's attempts, and no forced failures. Everything they know arrives through
the compiler's checkout brief.

## 2. Stages

### A. Intake and provenance pinning

Fetch the RFC as **verbatim text** and record a SHA-256 of the exact bytes. Every later stage
reads those bytes, not a paraphrase and not recollection. If the target is amended by a later
RFC, fetch the amendment and extract the relevant section as its own pinned file.

*TFTP:* RFC 1350 (618 lines) and RFC 1123 §4.2 (216-line excerpt), three hashes recorded in the
pre-registration §1.

*Failure mode:* extracting from memory. A from-memory paraphrase cannot survive the side-by-side
clause-to-predicate audit, and the citations will not anchor.

### B. Scope decision, before extraction (S0)

Decide, and write down, where the boundary sits between what the verifier carries and what it
does not. Two boundaries matter for almost any protocol:

1. **The wire-format boundary.** Byte-level parsing of variable-length or NUL-terminated fields
   is string structure, outside the decidable fragment. Declare that the protocol core operates
   on **decoded packet ADTs** and that parsing is excluded. State it explicitly; do not leave it
   implicit in the types.
2. **The ordering boundary.** Do not import an order the RFC does not define. If sequence
   numbers have no defined ordering or rollover in the source, reason by equality and
   disequality only. Any needed order becomes a recorded modeling decision, never a silent
   import.

*Failure mode:* scoping optimism, promising `verified` for a clause that later classifies out.
The scope matrix is the headline, not a post-hoc disclaimer.

### C. Author the normativity rubric, before any extraction

If the RFC predates RFC 2119 (March 1997) it has no MUST/SHOULD/MAY discipline and every
normativity judgment is interpretive. Write the rubric **first** and apply it uniformly:

- Normative rules (what counts): imperative protocol behavior; packet-format definitions;
  explicit lowercase must/should/may; state-machine transitions; error and exception behavior.
- Non-normative rules (what does not): motivation and rationale; examples and traces; historical
  and deprecated text; document metadata; statements about another protocol's behavior.
- Tie-breaks, including: one obligation per row; a definition is normative when an
  implementation could violate it; a later amending RFC governs on conflict; **when in doubt,
  mark normative**.

*Consequence to understand before choosing metrics (see stage J):* the conservative tie-break
deliberately over-includes, which systematically adds rows that later disposition out. It makes
the denominator safe and the exclusion *ratio* meaningless.

### D. Dual blind extraction

Spawn **two extractors that cannot see each other**, on identical bytes under the identical
rubric. One audited pass cannot answer "who checked that the inventory is complete"; two
independent passes can. Each returns structured rows: source, line span, short verbatim quote,
rule applied, strength word, and a one-sentence obligation. Extraction assigns **no disposition**:
keeping scoping out of extraction is what makes the two runs comparable.

*TFTP:* 119 and 125 rows respectively.

### E. Mechanical reconciliation, then recorded adjudication

Reconcile by **line-span overlap**, not by prose similarity, and report three distinct things:

1. **Line-coverage agreement** (Jaccard over normative line regions). This speaks to the
   denominator's completeness.
2. **Granularity difference versus coverage disagreement.** Two extractors splitting one
   sentence into different numbers of rows is *not* disagreement about what the RFC requires.
   Separate the two, or the statistic will understate agreement badly.
3. **Rule agreement** on one-to-one matched rows, where Cohen's kappa genuinely applies.

Then adjudicate every genuine disagreement **by hand, with the reason recorded per row**. Useful
rules from the first run: adopt a row that states a real obligation the other extractor merged
away; reject a row that restates a clause already counted elsewhere (a requirements-summary
table that duplicates prose double-counts the denominator).

*TFTP:* Jaccard 0.866, kappa 0.938, 64 granularity differences, 11 genuine disagreements, 6
adopted and 5 rejected. Canonical inventory: 124 rows.

### F. Name the characteristic core, before dispositions exist

Write down the clauses that make this protocol *this protocol*: the handful whose loss would
mean you had not implemented it at all. Do this **before** any disposition is assigned, so the
set cannot be drawn around whatever happens to succeed.

*TFTP:* lock-step transfer, block-number sequencing including the initial number, short-block
termination, the error latch, the duplicate-ACK rule. 15 rows.

### G. The disposition pass

Every row gets exactly one disposition and one class.

Dispositions: **Encoded** (carried by a contract clause that reaches its class's tier),
**Deployment-modeled** (realized by a recorded model), **Vectored** (carried by an executed
`check` block), **Dispositioned out** (excluded, with a cited reason).

Classes: C1 state transition, C2 arithmetic invariant, C3 length or format, C4 opaque primitive,
C5 test vector, C6 timing, liveness, transport, or trace-level.

Two rules keep this defensible:

- **A row may be Encoded only if you can name the shape of the contract that carries it.**
- **A row that is true by construction is not covered.** If the model admits no constructor for
  the forbidden thing, no mutant can exercise the row, so it carries no verification evidence.
  Exclude it rather than counting it.

*TFTP:* 46 Encoded, 20 Deployment-modeled, 5 Vectored, 53 excluded.

### H. Feasibility probes, before authoring anything

Before committing to the target, prove the core shapes actually verify. Write a small program
exercising the protocol core, verify it, then **mutate it and confirm the mutant refutes**. A
contract that cannot refute its own historically-attested bug is decorative.

Probe both directions for at least: the main transition function, and any joint or product
invariant the architecture needs.

**Do not commit probe bodies.** They are working implementations of functions the swarm is meant
to invent; committing them plants a reference solution in the tree. Carry forward the contracts
and the verdicts only.

*TFTP:* sender step SAFE body-faithful, Sorcerer's Apprentice mutant refuted; ghost spine SAFE
over an alphabet including duplicate delivery, joint-invariant mutant refuted.

### I. Pre-registration

Fix, in writing, before any wave agent runs: acceptance criteria; the measurement set; process
budgets (semantic retries per hole, protocol retries counted separately, human interventions
after freeze); the numeric concurrency trigger; and the **mutant-class taxonomy** per clause
class, with historically attested bugs as mandatory members.

Pre-registration only means something if it is honored when it goes against you. Record outcomes
in an **appendix**; never edit the pre-registered text.

### J. The gate: evaluate STOP on the right instrument

**Do not use an exclusion-ratio ceiling.** This is the sharpest lesson of the first run. A ratio
of `excluded / total` tracks `(C4 + C6) / total`, which measures the **genre composition of the
target document**, not the reach of the verifier. Every complete protocol specification carries
transport binding, timers, and deployment prose that add denominator and can never add numerator,
so a ratio ceiling is unsatisfiable by any of them, and it fires before a single scoping judgment
has been made.

Use three conditions instead:

1. **Class-stratified coverage**, reported and not thresholded: rows carried within C1 + C2 + C3,
   the subject matter a body verifier could conceivably carry.
2. **The characteristic-core invariant**: no core row may disposition out. This is the condition
   that decides the target.
3. **A closed barrier list**: enumerate the permitted reasons for exclusion. **A STOP fires if
   any row is excluded for a reason outside the list.** That catches the real failure, an
   exclusion nobody can justify, which a percentage never could.

*TFTP:* 95.4% of verifiable subject matter carried, 15/15 core Encoded, zero unclassified
exclusions. The retired ratio would have failed at 46.8%.

### K. Root contract authoring

One contract clause per Encoded inventory row, each carrying its own `:source`. Per-conjunct
provenance (SRC-CONJ-1, v0.14.65) means a multi-clause `pre` or `post` keeps every citation, so
contracts are **not** distorted into one-clause-per-function to make traceability work.

**Citation convention:** every `:source` begins with a bracketed inventory tag, `"[T045] RFC 1350
p.4 - ..."`. Exact tags are what make coverage mechanically checkable; matching free prose would
be fuzzy, and a completeness claim cannot rest on fuzzy matching.

### L. Coverage lint, then freeze

Run `scripts/rfc_coverage.py` (RFC-COV-1) with `--require-full-coverage`. It checks both
directions: every citation resolves to a real row, every Encoded row is cited, no contract cites
an excluded row, and only root contracts carry `:source` at all.

Then **freeze the clause-carrying surface**. The freeze is scoped: root contracts bearing
`:source` are immutable, while `refine`-spawned sub-contracts are additive, carry no `:source`,
and are governed by the shipped spawn gates. That distinction matters because `refine` grows the
contract surface by definition; a blanket freeze would forbid the mechanism the wave depends on.
Weakening a spawned contract makes the root's obligation *harder* to discharge, not easier, so
there is no laundering path from the spawn channel into the clause layer.

### M. Spawn the swarm

N ≥ 4 concurrent blind agents on one module tree, coordinating only through checkout, patch, and
refine. Retries carry compiler error text only, capped, with protocol-level conflict retries
budgeted separately so concurrency cannot consume an agent's error budget.

**The advisory lock is per-hole; the compare-and-swap is per-FILE.** Checkout tokens are keyed
by JSON pointer, so N agents genuinely hold N different holes at once, but `patch` validates
against a whole-source hash and rejects anything older than the current file
(`PatchAuthError: obligation context is stale`). So **the first patch to land invalidates every
other outstanding brief**, however unrelated the holes.

This was already known and written down (`docs/blog/post-4-who-writes-the-decomposition.md`:
"a module carries a whole-file compare-and-swap … application to one module is serialized").
The first wave re-derived it the expensive way, by wedging fourteen holes, because the harness
was built without reading it. Recorded here so the next harness does not: the cost of the
rediscovery was a whole wave, and the fact was one paragraph away.

Independently confirmed on that run: two holes checked out concurrently, first patch
`PatchSuccess`, second `PatchAuthError`.

The consequence for the harness is specific: agents may think in parallel, but a submission must
not reuse the brief the agent worked from. On submission, under a lock, **release the token,
re-checkout the same pointer, and rebuild the patch from the fresh token and the current hole
node**. The body is unaffected, because it was authored against the contract, which does not
change when a sibling is filled. That costs no model call, which is exactly why these retries
are budgeted apart from semantic ones.

Two harness failure modes worth stating, because both silently manufacture fake findings:

- **Never re-checkout without releasing.** A stale-context rejection followed by a bare
  re-checkout returns `hole ... is already checked out` forever, and the hole is wedged. On the
  first run this turned 14 correct fills into "findings"; one of them had already produced
  `(+ acked 1)`, which is right.
- **Do not gate a single fill on `--strict-verified-core`.** That flag hard-errors when *any*
  function in the module falls back, and during a wave every unfilled hole falls back by
  construction, so it rejects a correct body for its siblings being unfinished and makes the
  bar order-dependent. Read the per-fill bar per function; keep the whole-tree strict check for
  the end, when it means what it says.

Give each agent a **pristine** scratch copy of the module (every hole still a hole) so it can
verify its own candidate before submitting. Pristine is the operative word: handing over the
live tree would let one agent read another's attempt and destroy the blindness the wave exists
to demonstrate. Without a scratch copy an agent cannot self-check at all, and a real one said
so and declined to go looking for the tree, which is the correct behaviour and also wasted
attempts.

Per-fill bar: verify SAFE, the filled function in the body-faithful set, not flagged
`termination_unverified`.

A hole that exhausts its retries is a **finding**, routed to the compiler team or back to the
inventory as a scoping error. It is never an occasion for a hint.

### N. Refute layer and kill matrix

Execute the pre-registered mutant taxonomy. Report the **full kill matrix including survivors**:
a mutant that verifies SAFE means the contract is weak or the row is mis-dispositioned, and it is
resolved rather than dropped. Retain **good twins** (correct variants expected to stay SAFE) as
the guard against over-strong contracts. Extend the refute requirement to Deployment-modeled rows
so a modeled clause cannot ship with zero evidence its model constrains anything. Freeze the
verdicts into the CI gate.

### O. Writeup discipline

Lead with the class-stratified coverage figure and the core count, not the raw ledger ratio.
Disclose every trusted step, including any closure from per-step invariant preservation to
all-traces properties, which is a trace induction outside the decidable fragment. Never frame the
result as verification catching agent error.

---

## 3. Anti-patterns, each learned the hard way

1. **Chasing a coverage number.** Recovering excluded rows by modeling more state is legitimate
   only when the added state buys assurance. The test is "does this rule defend against something
   an attacker can do", not "is this rule expressible". Expressibility alone lets the ledger
   absorb transport mechanics that improve a percentage and prove nothing. Route any proposed
   coverage improvement through adversarial review before adopting it.
2. **Widening the language to rescue a target.** Choose the RFC to fit the shipped decidable
   fragment. On the first run, new language features would have recovered 3 rows out of 58, and
   the interactive-prover tier would have recovered **zero**. Let wave telemetry, not
   anticipation, promote residues.
3. **Committing probe bodies.** See stage H.
4. **Trusting a green gate without checking the binary.** `stack exec llmll` resolves to a stale
   binary from some working directories. Confirm the version before reporting any gate as
   passing; a green gate against the wrong compiler is worse than a red one.
5. **Editing a pre-registration after seeing the data.** Append an amendment with its reason.
6. **Silently reinterpreting a fired STOP.** If the instrument turns out to be defective, say so
   in writing, show the argument, and let a human adjudicate the amendment.
7. **Letting one agent both produce and audit the inventory.** Dual extraction exists precisely
   because self-audit cannot answer the completeness question.

## 4. Tooling index

**The whole procedure is executable.** `scripts/rfc_to_implementation.py` runs stages A-O from
an RFC URL:

```bash
scripts/rfc_to_implementation.py \
  --rfc-url https://www.rfc-editor.org/rfc/rfc1350.txt \
  --workdir runs/rfc1350 \
  --agent-cmd 'claude -p "$(cat {prompt})"'
```

It is agent-agnostic (`--agent-cmd` is any shell command, the same abstraction
`experiments/minimal-agent/scripts/run_agent.py` uses), resumable (every stage writes its
artifact and hashes it into `MANIFEST.json`; completed stages are skipped), and it enforces the
STOPs rather than reporting them. Three properties are worth knowing before relying on it:

- **It separates what it automates from what it delegates.** Stages are `mechanical` (A, E, J,
  L, and the scoring half of N: deterministic, no model), `agent` (B, C, D, F, G, H, I, K, M, O:
  a judgment a model makes under a written contract, schema-checked on return), or `gate` (J, L,
  and the per-fill bar in M). The script makes no judgment it labels mechanical.
- **Blindness is structural, not requested.** Stage D's two extractors run in directories
  holding the pinned bytes, the rubric, and nothing else. `--audit-blindness` re-checks after
  the fact and fails on any unaccounted-for file.
- **`--self-test` pins the mechanical spine to the first real run.** It replays the committed
  TFTP Phase 0 data and asserts the exact published figures (Jaccard 0.8655 / 0.725, kappa
  0.9378, 124 rows, 46 Encoded, 15/15 core, 62/65 carried, RFC-COV-1 green). A green run of the
  driver therefore means something beyond internal consistency.

Prompts carrying each stage's contract live in `experiments/rfc-swarm/prompts/`. Driver tests:
`scripts/tests/test_rfc_to_implementation.py`, which drives every STOP into firing on purpose,
because a gate that never fires is decorative.

| Need | Tool |
|---|---|
| the whole pipeline, from a URL | `scripts/rfc_to_implementation.py` |
| clause coverage cross-check | `scripts/rfc_coverage.py` (RFC-COV-1) |
| per-conjunct provenance in reports | `llmll verify --trust-report --json` (`pre_sources`/`post_sources`) |
| per-fill acceptance | `llmll verify --strict-verified-core` |
| contract adequacy | `--spec-coverage`, `--weakness-check`, `--cdp` |
| executed test vectors | `check` blocks via `llmll test` |
| frozen refute evidence | `EXPECTED_VERDICTS.json` + `make refute-crux-gate` |
| concurrent fills on one tree | `checkout` / `patch` / `refine`, advisory lock + compare-and-swap |
| redundant fills for contract tightness | `checkout --multi` + `diverge-report` |

## 5. What a second run should reproduce

A different RFC through this playbook should produce, without re-deciding the method: pinned
source bytes; a rubric written before extraction; two blind censuses with a reported agreement
statistic; a reconciled inventory with every adjudication recorded; a named characteristic core
fixed before dispositions; a four-way disposition ledger with a closed barrier list; feasibility
probes that verify and refute before authoring; a pre-registration honored or amended in the
open; tagged root contracts passing the coverage lint; a frozen clause surface; a blind
concurrent wave; and a kill matrix reported with survivors.

If a second run cannot reproduce that shape, the process is not yet the deliverable and this
document is the thing to fix.
