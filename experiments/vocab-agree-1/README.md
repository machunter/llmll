# VOCAB-AGREE-1: do independent authors agree on a protocol's vocabulary?

> **Status:** Complete (n = 2 RFCs). Exploratory; not pre-registered.
> **Dates:** 2026-11-15 to 2026-11-16
> **Owner:** experiment-lead
> **Consumers:** language-team (clause-sheet proposal in `consults/`), SPEC-AGREE-1
> (`docs/design/spec-agreement-proposal.md`), the RFC-SWARM pipeline (`experiments/rfc-swarm/`)

## 1. Question

The premise under test is that the developer's role shifts left, into the specification. The
language-team proposed that the developer should author a **clause sheet** instead of working from
an RFC: a vocabulary (sorts, step signatures, modeling decisions, exclusions) plus sentences from a
closed template set, each mapping to one contract clause. Two risks were named:

1. **The templates are too narrow** for real requirements.
2. **The vocabulary hides the ambiguity**, out of the solver's reach (the professor's point).

This experiment measures both on the two RFC-SWARM runs that passed gate J: ARP (RFC 826) and
TFTP (RFC 1350 + RFC 1123 §4.2).

## 2. Background consults (in `consults/`)

| File | What it is |
|---|---|
| `spec-elicitation-loop.md` | The user's draft that started this: loose English, then N formalizations, then solver witnesses, then human A/B questions. |
| `professor-spec-input.md` | Professor consult: state of the art in spec-first development, and what a developer should author. |
| `language-team-spec-input.md` | Language-team Rev 0 DRAFT: the clause sheet, its templates, example pinning, and the closure lint. Not yet in `docs/design/`. |

Both consults agree that the RFC is a good source and a poor authoring format. They also agree that
the developer authors a typed vocabulary, examples, and a decision log. Their disagreement was over
how central templates should be. Part A below settles that disagreement.

## 3. Part A: template fit (`template-fit/`)

**Method.** Every top-level conjunct of every clause in the frozen root contracts was sorted by the
template that could produce it. Each Encoded inventory row was then joined to its clauses through
the leading `[cid]` of `:source`. Scripts: `extract.py` then `classify.py` (run from the repo root;
both take the output folder as their argument). The method is mechanical, with the unusual shapes
read by hand.

**Result.** 74 of 85 Encoded rows (87%) fit the existing templates (TFTP 39/46, ARP 35/39). The
other 11 need three additional templates:

| Template needed | Rows |
|---|---|
| "WHEN g, f SHALL NOT return t" | 6 |
| "f SHALL return one of {a, b}" | 4 |
| "f SHALL return t ONLY WHEN g" | 1 |

With these three added, all 85 rows fit. All 11 gap rows are deliberately partial specs, mostly in
C1 transition rows, so example pinning will flag them unless a freedom is recorded. Three ARP
`pre` clauses carry no `:source`. See `template-fit/RESULT.md`.

**Limit.** The check is retrospective. It shows that the templates can express what the pipeline
froze. It does not show that a developer would write those sentences from scratch, since the
vocabulary had already done the interpretive work. That limit motivates Part B.

## 4. Part B: blind vocabularies (`arp/`, `tftp/`)

**Method.** Three blind authors received the same `brief.md`: the RFC text, a neutral description
of the target fragment, and the vocabulary format. They received no inventory, no scope, and no
prior run. Each used a different model:

| Author | Model |
|---|---|
| A | Opus |
| B | Sonnet |
| C | Fable |

Each wrote sorts, steps, D-rows (decisions), X-rows (exclusions) and open questions. A separate
Opus comparer then compared A, B and C with the frozen vocabulary R, which comes from:

- ARP: `experiments/rfc-swarm/runs/rfc826/scope.md` and `roots.llmll`
- TFTP: `examples/tftp_rfc1350/VERIFICATION_SCOPE.md`, `roots/FREEZE.md` and `roots/tftp.llmll`

R was also agent-written, under different prompts, and is not ground truth. The key measurement is
re-expressibility: can each frozen tagged obligation be stated as template sentences over A, B and
C? The answer is one of yes, reshaped, no, or conflict.

**Sources.** ARP used `experiments/rfc-swarm/runs/rfc826-llmll-2026-09-11/00-source/rfc826.txt`
(sha256 `01bc62fe…`). TFTP used rfc1350.txt (sha256 `39c9534e…`) and RFC 1123 lines 2544-2760
(sha256 `f276196f…`), both fetched from rfc-editor.org on 2026-11-16. All three hashes match the
values pinned in the repo, and the TFTP texts are not committed here. The comparison files cite
the session scratch paths that the authors worked in. Each blind vocabulary maps to a file here
as follows:

| Author folder in the session | File here |
|---|---|
| `a/vocabulary.md` | `vocab-A-opus.md` |
| `b/vocabulary.md` | `vocab-B-sonnet.md` |
| `c/vocabulary.md` | `vocab-C-fable.md` |

### Results

Counts of tagged obligations:

| | ARP | TFTP |
|---|---|---|
| Frozen tagged obligations | 39 | 46 (40 without duplicates) |
| yes/reshaped/no/conflict, A (Opus) | 25/12/2/0 | 40/5/0/1 |
| yes/reshaped/no/conflict, B (Sonnet) | 27/7/5/0 | 29/13/3/1 |
| yes/reshaped/no/conflict, C (Fable) | 24/12/3/0 | 41/4/0/1 |
| Expressible in all three | 33 (85%) | 42 (91%); 36/40 without duplicates |
| Lost in all three | 2 (A64, A81) | 1 (T067) |

Modeling questions:

| | ARP | TFTP |
|---|---|---|
| Distinct questions | 51 | 77 |
| Agree | 34 | 43 |
| Differ only in representation or scope | 11 | 18 |
| Genuinely conflict | 5 (plus 1 partial) | 16 |

### Findings

- **F-1. Meaning survives a change of author, but exact wording does not.** Between 85% and 91% of
  obligations stay expressible across all three blind vocabularies. Most reshaping comes from a
  few structural choices, not from different readings:
  - guards passed as inputs or as one gate tag
  - emission split into whether and where
  - constants or interface parameters
  - the whole table or per-key facts
  - classify first, or one projection per result

  A house style in the clause-sheet spec can fix these choices without asking anyone.
- **F-2. The human questions concentrate where the RFC is silent, and their number grows with
  the state machine.** ARP has 5 conflicts, about multihoming, interface constants, the meaning of
  "speaks", a miss with no answer, and optional length checks. TFTP has 16. They concern
  off-nominal transfer behavior: an ACK or DATA ahead of sequence, old or duplicate DATA, block 0,
  stray or malformed ERROR packets, an ERROR after completion, timeouts and backoff caps, peer
  identity, and block numbers after 65535. On that last question, four vocabularies gave four
  answers. Two of the three blind authors imported an integer order on block numbers, although the
  brief told them not to. The questions fall in the areas that later RFCs patched, which suggests
  they are substantive.
- **F-3. Agreement does not catch a misreading that all authors share.** TFTP row T067 states that
  "All packets other than duplicate ACK's and those used for termination are acknowledged"
  (rfc1350:366-367). All three blind authors drop some DATA packets silently, so T067 is lost in
  every one of them. Only R, which came from a different process, carries it. Diversity has to come
  from the process, not only from the model. This is the correlated-misreading risk that
  `consults/spec-elicitation-loop.md` names.
- **F-4. Blind readings audit the frozen pipeline output.** Four errors in R were confirmed by
  reading the source text:
  - ARP `scope.md` MD3 calls its reading of the reply's `ar$spa` "the only reading consistent with
    the example at 393-401". That example never states the field. Clause A60 cites line 399, which
    is about `ar$sha`.
  - The ARP `roots.llmll` header says the address and protocol-type sorts carry "no constants".
    RFC 826 names the ether_type constants (117-121) and the hardware broadcast address (186-187).
  - TFTP T006 strengthens "should not be implemented or used" (rfc1350:80-81) and "SHOULD NOT be
    supported" (RFC 1123 4.2.2.1) to "must not".
  - TFTP `sender-next-block` has `post (= result (+ acked 1))` with no upper bound, so at block
    65535 it requires 65536. The Block # field is 2 bytes (rfc1350:348-350).

  The blind authors also had errors. Those are recorded in the two `COMPARISON.md` files, §6.
- **F-5. Author quality varies.** On TFTP, Sonnet's vocabulary has no response sort and no server
  reply step. It is the only one that loses 3 obligations and reshapes 13.

## 5. Implications

- The vocabulary is a workable developer-authored artifact. The developer's real job is to answer
  roughly 5 to 16 genuine questions per protocol, almost all about behavior the RFC leaves open.
- A clause-sheet workflow needs three supports:
  - a house style for the structural choices (F-1)
  - blind multi-author readings to surface the questions (F-2)
  - at least one reading from a different process, because the blind authors' agreement misses
    shared misreadings (F-3)
- The professor's claim holds. Most of the remaining ambiguity is in the vocabulary, not in the
  clause sentences (Part A against Part B).

## 6. Limits

- n = 2 RFCs, with one blind author per model and one comparer run per RFC.
- The comparer is a model. Only the four errors in F-4 and the T067 finding were checked by hand.
  The per-row tables were not audited.
- The blind authors and R worked from different prompts. R also had the inventory and the compiler
  constraints, so "lost" partly reflects what the blind authors were never asked to carry.
- The blind authors' isolation was by instruction, not enforced. Their reports state that they
  read only their folder.

## 7. Open follow-ups (not filed)

- Roadmap rows for the four R errors in F-4. TFTP `sender-next-block` is a contract defect in a
  shipped example.
- Fold the three extra templates and the house-style rules into the language-team clause-sheet
  draft.
- Have a human answer the ARP five and the TFTP sixteen, to measure the cost of answering.
