---
name: rfc-genre-and-naming
title: "What 'RFC' means in this repository, and whether an IETF RFC can be ported by machine"
status: "Rev 0, DISCUSSION. NOTHING HERE IS SETTLED and nothing has been acted on. Opened 2026-08-08 when the user asked why TOOL-RFC-003 carries no RFC 2119 keywords. The answer turned out to be that the repository has THREE artifacts called RFC, one of them typeset as a published IETF document, and no line anywhere distinguishing them. Carries one measured defect that is latent rather than committed (section 4) and three routing items (section 6). The user adjudicates; this file records, it does not decide."
date: 2026-08-08
author: experiment-lead
consumers: [language-team, professor, compiler-engineer, documentation-lead, user]
---

# What "RFC" means here, and what a machine could do with a real one

**How this started.** TOOL-RFC-003 was written and the user asked why it uses no
`MUST` / `SHOULD` / `MAY`. The short answer is that the template does not and
neither do 001 and 002. The long answer is this file.

**What is NOT in question.** TOOL-RFC-003 shipped as written. Nothing below
changes any document that exists; every item is a proposal awaiting
adjudication.

---

## 1. There are three claimants, not two

| # | Artifact | Where | What it is |
|---|---|---|---|
| 1 | `TOOL-RFC-NNN` | [`docs/design/tool-rfc-002-refute-crux.md`](tool-rfc-002-refute-crux.md), [`-003-`](tool-rfc-003-doc-claims.md), [`TOOL-RFC-TEMPLATE.md`](TOOL-RFC-TEMPLATE.md) | a **decision record** for replacing one CI gate with an LLMLL program |
| 2 | published IETF RFCs | [`experiments/rfc-swarm/SUMMARY.md`](../../experiments/rfc-swarm/SUMMARY.md); RFC 1350, 826, 4648, 1982, 7009/7662 | **conformance targets** written by a standards body |
| 3 | `driver-spec.txt` | [`experiments/rfc-swarm/targets/driver-spec.txt`](../../experiments/rfc-swarm/targets/driver-spec.txt) | an **internal spec deliberately typeset as an IETF document** so the pipeline can consume it |

The third is the one nobody had counted. Its header reads:

```
Internet Engineering Note                              B. Sahinoglu
Request for Comments: XXXX                                     LLMLL
Category: Experimental                                         July 2026
```

It carries Status of This Memo, an RFC-layout table of contents, and the §2
Requirements Language boilerplate, and
[`targets/README.md`](../../experiments/rfc-swarm/targets/README.md) counts 78
`MUST` and 26 `MUST NOT` in it. It sits in one three-row table beside the live
URLs for RFC 1350 and RFC 826. **A `grep` for "IETF" across the whole tree
returns one hit**, so nothing distinguishes a genuine standard from an internal
document wearing its clothes.

**This is not an argument for changing the third one's form.** Writing an
internal spec in IETF style is exactly what makes it consumable by a pipeline
built for IETF documents, and that is a good reason. It is an argument for one
line of provenance.

## 2. The genres are different, and only one of them wants 2119

**A `TOOL-RFC` is a decision record.** Its value is §3 and §8: policy choices
asked before the code instead of reported after. Campaign
[§6](llmll-tooling-campaign.md) says so directly, and TOOL-RFC-001 is the worked
failure, written after its port shipped with three of four §8 decisions made at
the keyboard. Nothing in it is a conformance target for a third party. The
closest established genre is Nygard's architecture decision record, with the
Rust RFC and GHC proposal processes as the workflow model. **None of those
families uses 2119**, and the name "RFC" in this repository descends from them
rather than from the IETF.

**An IETF RFC is a conformance target.** Its normative clauses exist so
independent implementations interoperate. That is the genre 2119 was invented
for, and where it is doing real work.

So the absence of `MUST` in a `TOOL-RFC` is correct, and the presence of `MUST`
in `driver-spec.txt` is also correct. The problem is only that both are called
RFC.

## 3. Where a 2119 layer WOULD earn its place, if it is ever wanted

Two sections of the TOOL-RFC template, and no others.

**§2 Criteria is already normative in prose.** It says the port "owes these
messages verbatim" and fixes a failure order. That is a conformance target for a
second implementation, and both implementations are declared `oracle`, meaning
either answers for the other. That is an interoperability claim in everything but
vocabulary.

**§7 Retirement is a precondition list**, which is `MUST`-shaped.

Everywhere else it would be ceremony. §5 already has a better-fitted three-valued
vocabulary of its own (`BLOCKS` / `SHAPES` / `COSMETIC`).

**The objection, which is this campaign's own idiom.** Normative keywords that
nothing checks are the failure the campaign exists to prevent: finding 6 is "a
gate that is not wired in decides nothing", and
[`tools/doc-claims/docclaims.llmll`](../../tools/doc-claims/docclaims.llmll) exists because
docs made restriction claims the compiler did not honour. **So if 2119 is ever
adopted here it should arrive with a coupling, not alone**: §2 clauses get
identifiers, and each differential-cover cell cites the clause it tests. That is
cheap, and it would answer a question none of the three TOOL-RFCs can answer
today, which is *which criterion has no cell*.

## 4. The measured finding: a latent contradiction about SHOULD

This is the only part of this file with a defect in it, and it was found by
asking whether the "generate an implementation from an RFC" ambition survives
contact with defeasible norms.

**`MUST` looks like a contract and often is one. `SHOULD` is not**: it is a norm
the spec explicitly licenses violating with good reason, so it has no truth
condition a solver can discharge. A machine that treats `SHOULD` as `MUST`
produces a wrong implementation; one that drops it produces silent
under-coverage.

**The repository already has a rule for this, and it is the pragmatic one.**
[`rfc-swarm-roadmap-proposal.md`](rfc-swarm-roadmap-proposal.md): "SHOULD to
Encoded where decidable else Dispositioned out with the reason naming the
SHOULD", `MAY` to a recorded scope decision.

**Measured against the TFTP run**, joining
[`inventory-merged.json`](../../experiments/rfc-swarm/data/inventory-merged.json)
to
[`inventory-dispositioned.json`](../../experiments/rfc-swarm/data/inventory-dispositioned.json):

| | |
|---|---|
| rows at `strength: should` | **14** |
| Encoded | **3** (T046, T047, T048) |
| Dispositioned out | **11** |
| of those 11, carrying a barrier code `B1`-`B8` | **0** |
| how the 11 are classified instead | class only: C6 ×7, C4 ×4, plus free text |

**The contradiction.** "Dispositioned out with the reason naming the SHOULD" is
not one of the eight barriers in
[`scripts/rfc_to_implementation.py`](../../scripts/rfc_to_implementation.py), and
the STOP rule requires every exclusion to carry one. A `SHOULD` exclusion must
therefore either be forced into `B8` ("outside any tool", which is false for a
testable clause) or halt the run.

**It is LATENT, not committed, and that distinction is the reason to measure
rather than argue.** All eleven TFTP rows predate the barrier list and were
dispositioned by class, so no artifact in the tree violates the STOP rule today.
It fires the first time a run excludes a `SHOULD` under the barrier regime.

**The suggested shape, not taken:** a fourth barrier kind. The existing eight
already stratify as fragment-relative, model-relative and document-relative; a
defeasibility code would be *norm-relative*, which is a cleaner argument for
adding one than for stretching `B8`.

**Keep the strength check report-only.** The equivalence table `_STRENGTH_FAMILY`
in `rfc_to_implementation.py` feeds a report-only check, and
[`rfc-swarm-target-selection.md`](rfc-swarm-target-selection.md) justifies that
empirically on RFC 6298: it fired on 9 of 40 rows, all nine correct, and a
fail-closed version "would have halted this run at 22% of its rows for nothing".

## 5. Can a machine take an IETF RFC and emit LLMLL?

**Partly, and the valuable half is not the code.**

**What is derivable** is the slice with a formal skeleton: wire format and state
machine, where the spec carries ABNF, packet diagrams, or an explicit automaton.
That is the slice Narcissus (ICFP 2019) and EverParse (USENIX Security 2019)
mechanize, and both are already cited as the target shape in
[`native-json-proposal.md`](native-json-proposal.md) D-8.

**What is not**, regardless of tooling: timing and liveness, resource limits,
adversarial-peer behaviour, Security Considerations, and interop with
noncompliant implementations. None of that lands inside `Σ_auto`. The in-tree
precedent is `HTTP-GET-1`, dropped partly because an `RText` round trip is not
byte-faithful, which is a wire-fidelity problem rather than a verification one.

**The argument against "just generate", from this repository's own record.** The
TFTP coverage figure of 95.4% was later found to be **78.5%**, and an agent
applied the repo's own coverage rule more correctly than the repo did. That is
not a tooling bug. It says the hard question is *which clauses did we cover*, not
*what code implements them*. A generator that cannot answer the first honestly
will report 95% and mean 78%.

**So the proposal, one recommendation rather than a menu: the machine is a
coverage instrument first and a code generator second.** Its primary artifact is
a clause-by-clause ledger saying which normative clauses are proven, which are
tested, which are out of scope with a named barrier, and which nobody has read.
The generated LLMLL is a by-product of the clauses that happen to be derivable.

**That also settles the accommodation question.** The shared substrate between
genre 1 and genre 2 is exactly that ledger: a clause-identified conformance
target plus an obligation that something mechanically covers each clause. A
`TOOL-RFC` is the degenerate case with one implementation to compare against
instead of many, which is why its §2 + §6 already have the shape without the
vocabulary. **One shared core, two profiles.** Not one document standard: §1, §3,
§5, §7 and §8 are campaign bookkeeping with no IETF analogue, and an IETF port
needs wire-format and state-machine sections a `TOOL-RFC` has no use for.

## 6. Routing, none of it acted on

| # | Item | Bite |
|---|---|---|
| 1 | **The barrier list has no code for a `SHOULD` exclusion.** Two committed documents contradict each other; latent only because the eleven TFTP rows predate the list | the only item with teeth. Fires on the next run that excludes a `SHOULD` under the barrier regime |
| 2 | **`driver-spec.txt` reads `Request for Comments: XXXX`.** Nothing marks it as internal, and it sits beside live IETF URLs | one line. `Request for Comments: N/A (internal)` or similar |
| 3 | **"disposition" is a gate-enforced term of art in BOTH programmes with disjoint vocabularies** (Encoded / Deployment-modeled / Vectored / Dispositioned-out versus BLOCKS / SHAPES / COSMETIC) and neither cross-references the other | naming, but gate-enforced naming |

**A fourth, optional:** rename genre 1 so "the RFC says" is unambiguous. `TOOL-ADR`
is the accurate term. The cost is renaming three files, a template, a test, and
every citation, against a benefit that is entirely readability. Recorded so the
option is not lost, not recommended.

## 7. What was wrong on the way here, kept because it is the useful part

**The first research pass reported that no run had ever exercised a `SHOULD`.**
That was false and was self-corrected: the 14 rows in §4 are the evidence, and
the standing rule in `rfc-swarm-roadmap-proposal.md` had been policy the whole
time. **The recommendation offered before that check ("demote SHOULD to a test
rather than a proof") was therefore not a proposal but a rediscovery.** The
finding that survived is sharper than the one that was replaced, and it was only
reachable by joining two committed artifacts rather than by reasoning about
deontic logic.

**The barrier-code question was answered by one query**, after being carried as
"could not determine". It is the difference between a defect that is latent and
one that is already committed, and it cost about a minute.
