---
title: "Professor consult: what should a developer author when the specification is the work?"
author: professor
date: 2026-11-15
status: "Standalone consult. Not a review of one proposal. No repo files changed."
question: "Is the RFC the best way to write a specification to be implemented by LLMLL? What is the state of the art?"
---

# What the developer should author, if the job moves into the specification

## Restatement

The question has two parts. The first is a fact question: how do practice and research write specifications that are meant to be implemented and verified, as of late 2026? The second is a design question: which artifact should be LLMLL's primary *input*, and which artifact does a "shifted-left" developer actually write?

My short answer: the RFC is a good **source** for LLMLL and a bad **authoring format**. In the RFC lane the developer does not write the specification. The developer translates it, and the work is clause triage and decision making. In the general lane (no external standard), nobody in the literature or in industry asks the developer to write RFC-style prose. The convergent state of the art has three developer-authored layers: a typed vocabulary, concrete examples, and a log of decisions that a machine forced. Contracts are the compiled form of those three. The 10.6% figure is not the main bottleneck. It measures the *comparison* tool, and a known technique removes most of it. The main bottleneck is fidelity: does the contract mean what the person meant? No input format solves fidelity alone. Examples and solver-made questions are the only mechanisms with evidence behind them.

## Context located

1. `docs/design/specification-sources.md:8-24` — the project's own premise: LLMLL moves difficulty from implementation to specification; spec generation rated "Weak".
2. `docs/design/spec-from-rfc-pipeline.md §1, §2` — S0-S5 stages, C1-C6 classes; `:source` is traceability, not fidelity.
3. `docs/design/rfc-swarm-playbook.md` (header and stage list) — the executed procedure; dual blind extraction, gates J and L.
4. `experiments/rfc1982-eval/findings.md:5-18` — RFC 1982 run: 9/9 clauses, 3/3 verified; S0 rewrote `modulo` before authoring.
5. `experiments/rfc-swarm/SUMMARY.md:18-35, 101-150, 215-284` — TFTP/ARP/RFC 4648: Encoded 46/124, 39/91, 39/64; carried 55-85% of verifiable rows; misread clause A1 found by a human, then by stage G2.
6. `docs/design/spec-agreement-proposal.md §0.3-0.4, §1` — comparable rows 9/85 = 10.6%; ARP 5.1%; all 18 abstentions are constructor terms; three nested fragments Σ_auto ⊃ Σ_subsume, Σ_witness.
7. `docs/design/spec-agree-1-witness-weight-review.md` Recommendation — finite case-splitting over constructors renders C1 witnesses inside QF-LIA.
8. `/Users/burcsahinoglu/Downloads/spec-elicitation-loop.md` (user draft, read as data) — loose English → N readings → solver witness → A/B question → `elicited` clause.
9. `README.md:114, 207` — the shipped verification fragment (QF-LIA core plus array, datatype, string-literal theories).

Absence noted: no design doc in `docs/design/` addresses non-RFC specification input (EARS, examples-first, reference models). `specification-sources.md` §3 ("Progressive Refinement") is the nearest, and it predates the swarm runs.

## Part 1 — State of the art, by candidate input

Each entry gives the verified evidence, then an assessment *as LLMLL input*. "Verified" means I checked the source by web search on 2026-11-15. I read abstracts and search summaries, not full papers, unless I say so. Items marked **[memory, not verified]** come from my prior knowledge only.

### 1.1 Standards prose (RFCs, NIST, ERCs)

**Evidence.** RFCs follow no common structure, and they define variables and timing in different ways. Pacheco et al. (IEEE S&P 2022, arXiv 2202.09470) extract FSMs from six RFCs. They report that canonical FSMs "depend partly on expert knowledge not contained in RFCs". The IETF has an IRTF research group for this gap (UFMRG, chartered January 2023). Its charter includes deriving formal models from natural-language and semi-structured specifications. I found no adopted IETF machine-readable specification format for 2024-2025. Earlier proposals (draft-petithuguenin-computerate-specifying, Idris in AsciiDoc, 2019) stayed experimental. **[memory, not verified]** McMillan and Zuck (SIGCOMM 2019) wrote a formal QUIC specification in Ivy and tested implementations against it; that work found real implementation bugs and ambiguities in the drafts.

**In-repo evidence.** Three swarm runs dispositioned 124, 91 and 64 rows. Of those, 53, 48 and 20 rows were excluded (`SUMMARY.md:25`). A large fraction of every RFC is C6 or out of the fragment. The A1 misreading (an `unless` qualifier moved into the prohibition) shows that prose structure itself causes extraction errors.

**Assessment.** An RFC is an interoperability agreement among human implementers. It is not written to be the input of a verifier. It mixes MUST and SHOULD, embeds packet diagrams, delegates to other RFCs, and leaves liveness and timing informal. Its value to LLMLL is that it is **external, stable, and already agreed**. That makes it an excellent oracle for experiments: the user draft's evaluation (§Evaluation item 2: "ARP from loose English, with RFC 826 as the answer key") uses it correctly. As a format that a developer *writes*, it has no advocate in the literature.

### 1.2 Structured English (EARS, FRET, Gherkin, Kiro-style SDD)

**Evidence.** Kiro produces three markdown artifacts per spec (requirements, design, tasks) under `.kiro/specs/`. Requirements use EARS templates ("WHEN [condition] THE SYSTEM SHALL [behavior]"), with approval gates between phases. These details come from third-party guides; I did not read Kiro's official docs. Böckeler (martinfowler.com, 15 October 2025) sorts SDD tools into spec-first, spec-anchored, and spec-as-source. Secondary summaries report her doubt that any current tool reaches spec-as-source. I did not open the article itself. Thoughtworks Radar lists SDD in "Assess" (5 November 2025).

NASA FRET is the strongest example of the idea. FRETish is restricted English with up to six fields. Four fields (scope, condition, timing, response) select a template with formal semantics in past/future metric temporal logic. FRET then emits Lustre and checks *realizability*, meaning consistency against all environment inputs (Katis et al., 2022). Gherkin/BDD studies (Ferreira et al., AST 2025, arXiv 2504.07244; AToMIC, arXiv 2510.18861) measure LLMs *generating* Gherkin and test scripts. I found no study that measures Gherkin as the input for code generation.

**Assessment.** Structured English gives two things that RFC prose lacks. First, each requirement is one atomic, numbered unit, which is exactly the user draft's §1 "numbered sentences". Second, in FRET the template *is* the semantics, so formalization is deterministic and no LLM reading is needed. Kiro-style EARS gives the first property but not the second: an EARS sentence still needs an LLM to formalize it, so the fidelity gap stays open. The FRET lesson for LLMLL is specific. A small set of templates, each with a fixed mapping to a contract shape (C1 transition, C2 range, C3 length), would remove ambiguity at the source for the classes LLMLL proves best. Gherkin's Given/When/Then is an example format, not a specification format; see §1.3.

### 1.3 Examples, test vectors, and interactive example selection

**Evidence.** TiCoder (Lahiri et al., arXiv 2208.05950, Microsoft Research) asks the user to approve or reject generated tests. The approved tests form a partial formal specification that prunes and ranks candidate code. With 1-5 simulated user queries, pass@1 rose about 22-38 points on MBPP and 25-54 points on HumanEval (Codex). A follow-up user study reports about 46 points within five interactions (from search summaries). Test vectors are the native example format of crypto standards: hacspec specs "can be tested against test vectors taken from standards" (Cryspen; hacspec SSR 2018). **[memory, not verified]** Project Wycheproof is the standard industrial corpus of adversarial crypto test vectors.

**Assessment.** Examples have one property that no other candidate has: **a non-specialist can judge an example**. Jackson's instance-level validation argument (already cited in `spec-agree-1-witness-weight-review.md`) is the theory. TiCoder is the strongest measured evidence that it works with LLMs. In LLMLL, examples already exist as C5 `check` blocks, but they are a minor class. Two in-repo facts limit them today. Constructor-valued vectors are skipped by the property evaluator (`spec-from-rfc-pipeline.md §3`, degenerate input 2). RFC vectors are width-parametric and need adaptation (F-1982-3). The first fact matters most, because C1 transition rows are where `step-weak` lives and where human audit is hardest.

### 1.4 Executable reference models and differential testing

**Evidence.** Amazon S3 ShardStore (Bornholt et al., SOSP 2021, best paper) writes executable reference models at about 1% of implementation size. It checks conformance with property-based testing (sequential) and stateless model checking (concurrent). The team reports 16 issues stopped before production. Cedar (arXiv 2407.01688, "How We Built Cedar: A Verification-Guided Approach") writes an executable model in Lean, proves properties about the model, and checks the Rust production code against the model by differential random testing. Proofs found 4 validator bugs; DRT and PBT found 21 more. One proof took 4,686 lines and 18 person-days (AWS blog). hacspec puts RFC 9180 (HPKE) into an executable, typed Rust subset "as close to the RFC pseudocode as possible" (Cryspen blog). The repository says development has moved to hax.

**Assessment.** This is the dominant *industrial* pattern for high-assurance systems: the specification is a small program, not a predicate. It sidesteps the fidelity question in one direction: a reference model is easy to read as "what the system does" and can be run on examples. It does not sidestep it fully, because the model can be wrong in the same way the prose was misread. For LLMLL the pattern matters for one reason. A reference model is a **second, independent formalization** of the same intent, in a different notation. That is exactly the diversity that Knight-Leveson's correlated-error result (cited in SPEC-AGREE-1 §4 T1) says agreement checks need. An LLMLL function verified against contracts and then differentially tested against a reference model has two independent links to intent, not one.

### 1.5 Lightweight formal specification (Alloy, TLA+/PlusCal, P, Event-B)

**Evidence.** On NL→TLA+, a 2026 evaluation of 30 LLMs (arXiv 2606.05792) reports at most 26.6% syntactic and 8.6% semantic correctness. It concludes that current models need expert oversight. A TLC-reward fine-tune reports about 30% pass@1 on a 30-problem set (same group, ai4fm.cs.luc.edu). The 2025 TLA+ Foundation GenAI challenge winner, Specula, generates TLA+ *from existing code*, not from documents. For Alloy, LLM work is about *repair*: hybrid repair reaches up to 85.5% on over 1,900 specs (Hasan et al., DSN 2025), but LLMs alone make operator, type and arity errors. I found nothing relevant for P or Event-B with LLMs.

**Assessment.** These languages specify *systems* (traces, concurrency, liveness). LLMLL's verifier proves *functions* against pre/post in a QF-LIA-centred fragment. The large C6 class in every RFC run (retransmission, timing, liveness) is exactly what TLA+ and P model. So these tools are a **complement for the C6 residue**, not a replacement input. The evidence says LLMs cannot yet author them without an expert, so they do not reduce developer work today.

### 1.6 Contract languages (Dafny, JML, SPARK, Liquid Haskell, Lean, Verus)

**Evidence.** nl2postcond (Endres, Fakhoury, Chakraborty, Lahiri, FSE 2024) turns comments into postconditions. It scores them by correctness and *discriminative power*; the generated postconditions caught 64 historical Defects4J bugs. Lahiri (FMCAD 2024, arXiv 2406.09757) states the problem precisely. Checking an implementation against a specification can be automated; checking that the specification matches intent cannot. He proposes "symbolically testing specifications" against examples for Dafny/F*/Verus, and reports close agreement with human labels. Clover (Sun et al., SAIV 2024) checks consistency among code, docstring and annotations in six directions. It reports up to 87% acceptance of correct instances with no false positives, and found 6 wrong programs in MBPP-DFY-50. VERINA (ICML 2025; ICLR 2026 version) reports, for the best model, about 72.6% correct code, 52.3% sound-and-complete specifications, and 4.9% proofs. The vericoding benchmark (arXiv 2509.22908) gives specs and asks for code plus proof: about 82% Dafny, 44% Verus, 27% Lean, and natural-language descriptions did not help much. CLEVER (ICML 2025) and AlgoVeri (arXiv 2602.09464) both report that benchmark specs often leak the implementation or miss intent.

**Assessment.** This literature is the closest match to LLMLL, and it has one clear result: **the specification is now the weak link, and models write specifications worse than code**. VERINA's 52% sound-and-complete rate is the number to remember. Its proof figure does not transfer to LLMLL, because LLMLL's SMT fragment makes proofs automatic where the fragment applies. Two techniques here are directly reusable. Discriminative power (nl2postcond) is what LLMLL's mutant kill matrices and `--cdp` already measure. Symbolic testing of specs against examples (Lahiri 2024) is what LLMLL lacks: run the contract, not the body, on accepted and rejected examples. Should the developer author contracts directly? A developer who reads refinement predicates fluently can. The `step-weak` exhibit shows that even then, the omission of a totality clause passes review. That is the argument for examples as the validation channel even for expert authors.

### 1.7 Domain policy languages and NL→logic with ambiguity findings

**Evidence.** AWS Automated Reasoning checks (ARc) translate policy text into formal rules over typed variables. A finding is VALID, INVALID, SATISFIABLE, IMPOSSIBLE or TRANSLATION_AMBIGUOUS (AWS announcements, August 2025 and June 2026). The June 2026 release adds a "resolve policy ambiguities" workflow that refines variable descriptions and type definitions. The method paper (arXiv 2511.09008, "A Neurosymbolic Approach to Natural Language Formalization and Verification") formalizes the same text with *several different LLMs* and cross-checks the results for symbolic equivalence. It reports over 99% soundness on held-out data. It contrasts this with LINC, which majority-votes over solver outcomes from one model. Li et al. (arXiv 2410.20936) select among autoformalization candidates by Z3/CVC5 equivalence for maths. Cedar (§1.4) is the policy language whose semantics is itself proved.

**Assessment.** ARc is the most important external finding for this question. It is a shipped industrial instance of SPEC-AGREE-1's core: N independent formalizations, a solver decides equivalence, and ambiguity is a first-class output, not a vote. Two of its design choices answer open points in the repo. First, it uses *model diversity*, not one model sampled N times. This matches SPEC-AGREE-1 T1 and the NeurIPS 2026 result in §1.8. Second, its remedy for ambiguity is to **refine the variable descriptions and types**, which is the vocabulary layer. That matches the user draft's §2 claim that the vocabulary step "is the main place where ambiguity can still hide". I could not verify from abstracts which logic fragment ARc compares in, or whether it handles enumerated types in equivalence checks. Do not cite ARc as evidence for constructor-term comparison.

### 1.8 Interactive elicitation and clarification

**Evidence.** nl2spec (Cosler et al., CAV 2023) decomposes a sentence into sub-translations, each tied to a phrase, and lets the user edit them. The authors say earlier tools "lack a detection and interactive resolving of the inherent ambiguity of natural language". "Eliciting Specifications: When Does Interactive Clarification Help?" (NeurIPS 2026 listing, neurips.cc/virtual/2026/171451) tests a clarifying-question agent before Lean formalization on 189 VERINA tasks. With one model (Claude Sonnet 4.6) for both roles, the strict pass@1 effect was *negative* at budgets of 3 and 10 questions. Cross-model pipelines were positive; the best was 65.6%, up 6.3 points. Most of the loss was in postconditions. I saw the abstract only. ClarifySTL (arXiv 2605.01209) does clarification for signal temporal logic; I saw the title only.

**Assessment.** The evidence supports *one* kind of question and not another. Open-ended LLM-originated questions can hurt. Questions grounded in a concrete case help (TiCoder, nl2spec sub-translations). The user draft (§8 and Risks) already draws this line: "only the solver originates questions". I agree, and the NeurIPS result is the citation that supports it. The draft calls that a design answer. More precisely, the NeurIPS result says nothing about solver-originated questions, so it is a reason for the design, not evidence that the design works.

## Part 2 — Synthesis

### 2.1 The convergent shape

Across ARc, TiCoder, nl2spec, Cedar, ShardStore, FRET and Clover, five practices recur, all independent of LLMLL:

1. **Atomic, identified requirement units** (EARS, FRETish, numbered policy rules, the RFC clause inventory).
2. **A fixed vocabulary of typed variables before any rule is formalized** (ARc's variables and types; FRET's fields; LLMLL's frozen signatures).
3. **More than one formalization in different notations or by different models**, compared mechanically (ARc, Clover's six directions, Cedar's model versus Rust).
4. **Concrete instances as the human interface** (TiCoder tests, Cedar DRT inputs, ShardStore PBT, solver witnesses).
5. **Ambiguity as an explicit, recorded outcome** (TRANSLATION_AMBIGUOUS, FRET unrealizability, nl2spec sub-translation edits).

LLMLL's RFC pipeline already has 1 (S1 inventory), 2 (stage-K freeze), part of 4 (C5 checks, kill matrices), and has 3 and 5 designed but not built (SPEC-AGREE-1, user draft). That is a strong position. It is closer to the state of the art than Kiro-style SDD, which has 1 and nothing mechanical behind it.

### 2.2 Is the RFC the right primary input?

For the RFC lane: yes, as the *source*, with a qualification. The playbook's rule "choose the RFC to fit the fragment" (`SUMMARY.md:161`) shows that the RFC is a chosen benchmark, not a general input. Keep it for three jobs: as an external oracle that nobody in the project wrote, as a demo of traceability, and as an answer key for elicitation experiments.

For the general lane: no. A developer who writes RFC-style prose for LLMLL creates the same extraction problem the swarm spends stages A-G2 solving, and adds nothing an external standard would give (independence, prior agreement). The RFC's structure is an obstacle the pipeline works around, not a feature to copy.

### 2.3 What the shifted-left developer actually authors

Recommendation, ranked by what the developer writes most:

1. **A decision log.** Each entry answers a machine-made question about one concrete case: "at input x, reading A accepts and B rejects; which is right?" It records the answer, the case, and the clause it fixes. This is the user draft's `:source (decision D7)` and `elicited` label. The decision log is the developer's main product because it is the only artifact that records *intent where intent was in doubt*, which is the fidelity gap `:source` cannot fill (`spec-from-rfc-pipeline.md §2`).
2. **Examples.** Accepted and rejected input/output pairs, including constructor-valued ones. They are the validation channel for contracts (symbolic spec testing, Lahiri 2024) and the seed for questions (TiCoder).
3. **The vocabulary.** Types, sum constructors, signatures, units. ARc and the user draft both locate ambiguity here, and SPEC-AGREE-1 T3 shows the frozen outcome sum can "already contain the answer". This layer needs human review and has no mechanical check in either system.
4. **Short structured requirement sentences**, optionally in a few FRET-like templates with a fixed contract mapping for C1-C3. These are the input to N-way formalization, not the source of truth.

**Contracts are generated and reviewed, not primarily written.** A developer who reads refinement predicates may write them. The pipeline must still validate them against examples and decisions, because `step-weak` passes an expert's review. The shift-left framing is therefore slightly wrong in emphasis. The developer does not move into *writing* formal specifications. The developer moves into *adjudicating* them: choosing the vocabulary, approving examples, and answering distinguishing questions. Kleppmann (8 December 2025) states the same point: once proofs are cheap, the hard question is whether the proved properties are the ones you care about.

### 2.4 Is the bottleneck the input format or the fragment?

Three bottlenecks exist. They have different owners and different costs.

**B1. Fidelity of contract to intent (largest; unmechanized).** No input format closes it. Structured input reduces the rate of ambiguity; it does not detect a shared misreading. The only mechanisms with evidence are (a) diverse independent formalizations compared by a solver (ARc), and (b) human judgment on concrete instances (TiCoder, Cedar DRT). Both need B2 to be small.

**B2. The comparison fragment Σ_subsume (the 10.6%; cheap to widen).** The 10.6% is *not* the verification fragment. It is the reach of `RefineReuse.qfContract` (`spec-agreement-proposal.md §1`), which abstains on any constructor term because the bare comparison `.fq` declares no constructors. All 18 abstentions were constructor terms; zero were arrays or measures (§0.3, M-3). The earlier professor review gives the fix: finite case-splitting per constructor, which keeps every query in QF-LIA and renders the witness by construction (`spec-agree-1-witness-weight-review.md`, Recommendation). On the measured corpus that costs tens of trivial queries. Note also that the two-contract difference query with `(get-model)` does not exist yet (same review, hazard 1). Until it exists, the comparison yields no witness at any sort, so no decision log can be generated even for the 10.6%. **This is the item on the critical path for the whole recommendation.**

**B3. The verification fragment Σ_auto (target-dependent; slow to widen).** It decides how much of a target is *carried* at all: about 55-85% of verifiable rows, depending on whether wire fields are fixed-length (TFTP) or length-driven (ARP, `8 + 2*ar$hln + ar$pln`) (`SUMMARY.md:125-130, 220-225`). Changing the input format does not move B3. The same clause lands in the same fragment whether it is written in RFC prose or EARS. The current BYTE-IO work on this branch is a B3 lever.

So the answer to "format or fragment?" is: **neither is the main limit**. The main limit is B1. B1's mechanical fix needs B2, and B2 is an engineering gap with a known solution. Input format matters only at the margin: it changes how many rows need a question, not whether a question can be asked.

## Gaps and hazards

1. **Correlated misreading survives every recommendation above.** Classification: soundness of the fidelity claim. Source: SPEC-AGREE-1 §4 T1 (Knight-Leveson 1986). ARc reduces it by model diversity; the NeurIPS 2026 result shows same-model pipelines can be worse than no elicitation. Bite: limits the claim. LLMLL must state agreement only in the eliminative direction (SPEC-AGREE-1 §4), and must use different models per reading.

2. **The vocabulary layer has no check.** Classification: scope. Source: user draft §2; SPEC-AGREE-1 T3. Both the draft and ARc say ambiguity hides in types. Neither LLMLL nor ARc (from what I could verify) checks the vocabulary mechanically. Bite: complicates. T3's de-naming experiment is the cheapest available measurement.

3. **Question volume is unmeasured.** Classification: ergonomic. Source: user draft, Risks. TiCoder's gains came at 1-5 questions per task on small functions. RFC-scale inventories have 64-124 rows. Bite: matters at scale. A decision log is only useful if its length is tolerable, so the ARP-from-loose-English experiment (draft, Evaluation item 2) must report questions per normative row.

4. **Constructor-valued examples are not executed.** Classification: scope. Source: `spec-from-rfc-pipeline.md §3` degenerate input 2. Examples are the recommended human interface, and C1 rows are where they matter most. Bite: blocks the examples layer for C1 until `check` blocks evaluate constructed sums.

5. **Structured-template mapping can drift from the verifier.** Classification: spec-drift risk. If FRET-style templates are adopted, each template's contract shape becomes a second semantics that must stay inside Σ_auto. Bite: only matters if templates are built; then it needs one conformance test per template.

## Recommendation

1. **Keep the RFC lane as it is, and name its role correctly.** It is the project's external oracle and benchmark family. Do not present it as the way developers should write specifications.

2. **Make the decision log the developer's primary artifact for the general lane.** Its unit is one solver-made distinguishing case, one answer, one fixed clause, with provenance. The user draft's `elicited` label and `:source (decision …)` kind are the right shape. The language-team should specify it as a trust-report fidelity axis distinct from `verified`/`asserted`, as the draft §9 proposes.

3. **Build B2 before any harness, in this order:** the two-contract difference query with a model; then nullary-enum comparison; then case-split payload sums (per the earlier review's order). Acceptance: the 9/85 figure is re-measured and rises. This is cheap relative to its value and is the precondition of recommendations 2 and 4.

4. **Add symbolic spec testing against examples** (Lahiri FMCAD 2024): evaluate the *contract* on developer-approved positive and negative examples, before any body exists. It needs constructor-valued example evaluation (hazard 4). It catches `step-weak`-style omissions whenever an example exercises the missing case.

5. **Use model diversity, not sampling, for N-way readings.** Cite ARc (arXiv 2511.09008) and the NeurIPS 2026 elicitation result as the grounds.

6. **Treat structured English (EARS, a few FRET-like templates) as an optional front end**, not the source of truth. Adopt it only for C1-C3 shapes where a template maps to one contract shape.

7. **Use TLA+/P only for the C6 residue**, and only with an expert author. Current NL→TLA+ accuracy (8.6% semantic) does not support agent authoring.

8. **Do not wait on B3 for any of this.** Widening Σ_auto (BYTE-IO, length-driven formats) increases carried coverage, but it does not affect the fidelity question.

## Open questions for the language-team

1. Specify the unit of the decision log and its invalidation rule. The draft's open question 4 ("should `elicited` decisions expire when the English sentence changes?") needs an answer before the log can be the developer's main artifact. A decision tied to a witness over the frozen vocabulary should become invalid when the vocabulary changes, not only when the sentence does.

2. Justify, or revise, the claim that the vocabulary step is outside mechanical reach. T3's de-naming arm measures one part of it. State what else could test a signature against intent, or record it as a permanent human-only gate.

## Sources (verified by web search, 2026-11-15; abstracts and summaries unless stated)

- Pacheco et al., Automated Attack Synthesis by Extracting FSMs from Protocol Specification Documents, IEEE S&P 2022 — https://arxiv.org/abs/2202.09470
- IRTF Usable Formal Methods Research Group — https://datatracker.ietf.org/rg/ufmrg/about/ ; computerate-specifying draft — https://datatracker.ietf.org/doc/draft-petithuguenin-computerate-specifying/
- Kiro SDD guides (third-party) — https://www.verdent.ai/guides/agents/kiro-spec-driven-development
- Böckeler, Understanding Spec-Driven-Development: Kiro, spec-kit, and Tessl — https://www.martinfowler.com/articles/exploring-gen-ai/sdd-3-tools.html ; Thoughtworks Radar — https://www.thoughtworks.com/radar/techniques/spec-driven-development
- NASA FRET realizability (Katis et al. 2022) — https://link.springer.com/chapter/10.1007/978-3-031-13188-2_24 ; FRET compositional semantics — https://rd.springer.com/chapter/10.1007/978-3-030-44429-7_2
- Ferreira et al., Acceptance Test Generation with LLMs, AST 2025 — https://arxiv.org/abs/2504.07244 ; AToMIC — https://arxiv.org/abs/2510.18861v1
- TiCoder, Interactive Code Generation via Test-Driven User-Intent Formalization — https://arxiv.org/abs/2208.05950v2
- hacspec — https://cryspen.com/hacspec ; executable HPKE spec — https://cryspen.com/post/hpke_spec/
- Bornholt et al., ShardStore, SOSP 2021 — https://www.cs.utexas.edu/~bornholt/papers/shardstore-sosp21.pdf
- How We Built Cedar: A Verification-Guided Approach — https://arxiv.org/abs/2407.01688 ; AWS blog — https://aws.amazon.com/blogs/opensource/lean-into-verified-software-development
- Can LLMs Write Correct TLA+ Specifications? — https://arxiv.org/abs/2606.05792 ; Loyola AI4FM — https://ai4fm.cs.luc.edu/papers/llm-tla-evaluation/
- Alloy LLM repair — https://arxiv.org/abs/2404.11050 ; DSN 2025 comparative study — https://research.chalmers.se/en/publication/547710
- Endres et al., nl2postcond, FSE 2024 — https://arxiv.org/abs/2310.01831
- Lahiri, Evaluating LLM-driven User-Intent Formalization for Verification-Aware Languages, FMCAD 2024 — https://arxiv.org/abs/2406.09757
- Clover: Closed-Loop Verifiable Code Generation — https://ai.stanford.edu/blog/clover
- VERINA — https://arxiv.org/abs/2505.23135 ; ICLR 2026 — https://iclr.cc/virtual/2026/poster/10011965
- Vericoding benchmark — https://arxiv.org/abs/2509.22908 ; AlgoVeri — https://arxiv.org/abs/2602.09464 ; CLEVER — https://icml.cc/virtual/2025/52383
- AWS Automated Reasoning checks — https://aws.amazon.com/about-aws/whats-new/2025/08/automated-reasoning-checks-amazon-bedrock-guardrails ; June 2026 refinement workflows — https://aws.amazon.com/about-aws/whats-new/2026/06/amazon-bedrock-guardrails/
- A Neurosymbolic Approach to Natural Language Formalization and Verification (ARc) — https://arxiv.org/abs/2511.09008
- Li et al., Autoformalizing Mathematical Statements by Symbolic Equivalence and Semantic Consistency — https://arxiv.org/abs/2410.20936
- nl2spec, CAV 2023 — https://arxiv.org/abs/2303.04864
- Eliciting Specifications: When Does Interactive Clarification Help? (NeurIPS 2026) — https://neurips.cc/virtual/2026/171451
- ClarifySTL (title only) — https://arxiv.org/abs/2605.01209
- Kleppmann, Prediction: AI will make formal verification go mainstream — https://martin.kleppmann.com/2025/12/08/ai-formal-verification.html

**Not verified in this session (memory only):** McMillan and Zuck, Ivy QUIC specification (SIGCOMM 2019); Project Wycheproof; Jackson, *Software Abstractions*; Knight and Leveson (1986). The last two are cited from the repo's own earlier reviews.
