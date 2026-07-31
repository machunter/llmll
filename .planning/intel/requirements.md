# Requirements

> **Provenance note.** No PRD-typed document was present in the ingest set. Requirements below are
> extracted from the **open / unshipped remainder** recorded in SPEC-typed docs (and, where marked, a
> DOC-typed doc at precedence 2). Work a source records as already shipped is deliberately **not**
> emitted as a requirement. `docs/compiler-team-roadmap.md` is the backlog of record (precedence 0);
> where a proposal's status disagrees with it, the roadmap wins and the divergence is logged in
> `.planning/INGEST-CONFLICTS.md`.
>
> **Re-run note.** All 18 docs are synthesized. `docs/design/rfc-swarm-playbook.md` (precedence 1)
> and `docs/design/spec-from-rfc-pipeline.md` (precedence 2) were withheld by the prior run's cycle
> rule; the manifest now transcribes the ordering both docs declare about themselves, and the pair is
> traversed in precedence order. `docs/design/spec-agreement-proposal.md` is read at HEAD as **Rev 1**;
> Rev 0's applicability claim and effort table are withdrawn and are not extracted.

---

## REQ-wild-assume-2
- source: docs/compiler-team-roadmap.md (Active Items, WILD-ASSUME-2 row); docs/design/finding-arg-position-false-safe.md (Rev 2)
- description: Extend the WILD-ASSUME restriction from `bytes[n]` (stage 1, shipped v0.14.73) to the `map[k,bool]` arm. A `map[k,bool]` binder carries the ground fact `0 <= select(m$val,k) <= 1` asserted from its declared value type (`injectRangeFacts`, `boolValRooted`), the same class SAFE-ARG closed for bytes: a fact no obligation discharges, believed from a declaration the type channel need not have validated.
- acceptance: `assumesFact` extended to the map class. **Prerequisite:** the `(map-empty)` over-breadth fixture (`SA-6`) must be in place first, because `map-empty : TFn [] (TMap (TVar "k") (TVar "v"))` relies on componentwise wildcard absorption, so any discriminant broader than the bare wildcard breaks every use of it.
- scope: WILD-ASSUME, map[k,bool] value-range facts, `assumesFact`, SA-6 fixture
- note: measured member of the class, but with **no reaching-SAFE witness**; both the return and argument shapes crash on a sort mismatch before a verdict, so it is neither known exploitable nor known safe.

## REQ-ret-resolve
- source: docs/compiler-team-roadmap.md (Active Items, RET-RESOLVE row); docs/design/ret-resolve-proposal.md (Rev 2, SETTLED); docs/design/ret-branch-pref-proposal.md (Stage 1 / Stage 2); docs/design/ret-resolve-proposal-review.md (Round 1, finding 1, lines 19-27)
- description: Resolve a wildcard `tau_ret` transitively in a verification-facing pass. `collectTopLevel` registers an unannotated return as `TVar "?"`, callers inherit it through `inferExpr`, and `sortA1` lowers it to `FQInt`. Kleene iteration of a monotone update over the recorded return-type map (`tcRetTypes`) closes nine measured crash shapes at the root instead of one shape at a time. **This requirement now carries the whole if-join wildcard-preference scope**, including the generalization beyond self-recursion that was previously tracked as RET-BRANCH-PREF Stage 2.
- acceptance: Three side conditions hold. **SC1** wildcard-only refinement (bare `TVar "?"` only; named-hole types retained; a concrete `tau^0` is never revised). **SC2'** a sandboxed pass from which only the return-type map is extracted, so the type channel's accept/reject set and the sketch-hole registry are unchanged by construction. **SC3'** an SCC-conditioned `if`-join preference: the concrete branch is preferred only when the wildcard branch's head calls a member of `SCC(f)`. Gate: the corpus census predicts a **byte-identical `.fq` across all 128 files** and zero demotions, the same gate that refuted the withdrawn HOLE-RET. Cycle rule: a component with no concrete anchor stays bare-wildcard and keeps today's behavior.
- scope: `collectTopLevel`, `inferExpr`, `sortA1`, `calleeRetSort`, `FixpointEmit.hs`, `TypeCheck.hs`, `HoleAnalysis.hs`, `Module.hs`, if-join branch preference
- note: queued **second**, behind WILD-ASSUME-2. One of four behaviour channels (`resultLenFact` assumption injection) can turn a crash into `verified`, so this must not land before WILD-ASSUME is in place. **Prior shipped scope:** RET-BRANCH-PREF Stage 1 shipped v0.14.72 for **self-recursion only**; SC3' generalizes that condition to its natural boundary (same-SCC membership) and is not emitted separately. The type-channel Stage 2 variant is **not** a requirement: `docs/design/ret-resolve-proposal-review.md` Round 1 finding 1 classifies the unconditioned if-join preference as "soundness-adjacent" and recommends the SCC condition, citing Milner 1978, Damas and Milner POPL 1982, and Jones, *Typing Haskell in Haskell*, Haskell Workshop 1999 §11. The adjudication is recorded in `.planning/INGEST-CONFLICTS.md` (INFO) so it stays reversible.

## REQ-fact-ag
- source: docs/compiler-team-roadmap.md (Active Items, FACT-AG row); docs/design/ret-resolve-proposal-review.md (Round 4)
- description: Route type-derived VC assumptions through assume-guarantee. No fact derived from a *type* enters a VC antecedent unless the function that declared that type has discharged it, carried on the existing `consumed_guarantees` / §5.3.4 meet channel rather than asserted from an annotation. The criterion is "contributes a VC assumption that no obligation discharges", which is FACT-AG inverted.
- acceptance: (absent; recorded as research track, no acceptance criteria stated)
- scope: VC antecedents, `consumed_guarantees`, §5.3.4 meet channel, type-derived facts
- note: Research track. The general form of what WILD-ASSUME approximates. Scope beyond `bytes`/`map` is unmeasured.

## REQ-wildcard-semantics-spec
- source: docs/design/ret-branch-pref-proposal.md ("What `?` denotes", "Spec drift found"); docs/design/ret-branch-pref-proposal-review.md (F-4, Open questions)
- description: Land the definition of the `?` wildcard in `LLMLL.md §3.4.6`: `TVar "?"` denotes *inference produced no usable type at this position*, not *any type*. It is compatible with every type, making the compatibility relation reflexive and symmetric but **not** transitive; because LLMLL erases and inserts no casts (§3.4.5), that compatibility is an **unchecked admission**, not a deferred check. Consumers must treat a result derived through `?` as unproven. Separately, correct the drift at `LLMLL.md §3.4.6:399`, which describes `if` as checking one branch against the other's synthesized type while `TypeCheck.hs:1323-1331` synthesizes both, runs a symmetric compatibility test, and picks `thenType`.
- acceptance: The wording lands in the spec whether or not the if-join preference ships; the drift is routed to documentation-lead independently of the proposal.
- scope: `LLMLL.md §3.4.6`, `?` wildcard semantics, `compatibleWith`, spec/code drift

## REQ-oblig-1-def-invariant
- source: docs/compiler-team-roadmap.md (OBLIG-1-FOLLOWON row)
- description: Populate the one deferred province of the obligation-report `assumptions` field: `def-invariant` axioms. v1 (refinement predicates of in-scope refinement-typed params), v2a (let-definitional equalities), and v2b (match-scrutinee case hypotheses) have shipped.
- acceptance: (absent; deferred. The source records only that it needs provenance tagging, hence a schema bump, and that an unverified invariant is a TCB assumption)
- scope: obligation report, `assumptions` field, `def-invariant` axioms, schema version

## REQ-oblig-2
- source: docs/design/oblig-0-spec.md (Rev 8, Status line)
- description: OBLIG-2, which the OBLIG-0 approval records as gated on §4.2.3/§4.2.4 of the OBLIG-0 specification.
- acceptance: gates on OBLIG-0 §4.2.3 and §4.2.4
- scope: obligation report, OBLIG-2
- note: OBLIG-0 itself is `APPROVED`; OBLIG-1 and MOD-1 are recorded unblocked. The doc is dated 2026-05-02 and its status has been advanced by the backlog of record. See INFO-11 in `.planning/INGEST-CONFLICTS.md`.

## REQ-contract-read-lint-residual
- source: docs/compiler-team-roadmap.md (CONTRACT-READ-LINT row)
- description: Two deferred tiers of the contract-position partial-read lint: (a) the `map-get`-without-`map-has` heuristic tier (disposition (c), "may ship later"), and (b) the Dafny-style well-formedness side-obligation (disposition (b)).
- acceptance: (absent; both recorded as deferred, no criteria stated)
- scope: `TypeCheck.lintContractReads`, `contract-read-oob` warning, map reads

## REQ-int-3
- source: docs/compiler-team-roadmap.md (INT-3 row); docs/design/critique-2026-05-23-triage.md §4 (INT-3 row)
- description: `MachineInt` QF-BV alias, a post-freeze machine-integer type under QF-BV verification scope.
- acceptance: Language-team design when scheduled. Promote from P3 to P1 only if INT-PRE shows a TOTP regression > 5x; it cleared at 1.015x, so the item is dormant.
- scope: integer semantics, QF-BV, `MachineInt`

## REQ-mod-2-per-module-emission
- source: docs/compiler-team-roadmap.md (Future, Module System Codegen, MOD-2)
- description: `[CT]` Per-module Haskell file emission: instead of concatenating all module statements into a single `Lib.hs`, emit one `.hs` file per module with Haskell `module` export lists. Enables true codegen-level export hiding and qualified access.
- acceptance: (absent; status `☐`, no acceptance criteria stated)
- scope: module system codegen, export hiding
- note: prerequisite: none. Trigger for the whole MOD-2..5 group: a production use case requiring true namespace isolation.

## REQ-mod-3-qualified-access
- source: docs/compiler-team-roadmap.md (Future, Module System Codegen, MOD-3)
- description: `[CT]` Qualified access at codegen: with per-module `.hs` files, translate `module.function` to Haskell qualified imports, making §8.5.1 "Qualified Access" operational.
- acceptance: (absent; status `☐`)
- scope: module system codegen, qualified imports
- note: prerequisite MOD-2.

## REQ-mod-4-strict-typecheck-migration
- source: docs/compiler-team-roadmap.md (Future, Module System Codegen, MOD-4)
- description: `[CT]` `loadFromFile` strict typecheck migration: switch the DFS module loader from permissive `typeCheck` to strict `typeCheckStrictWithCache`.
- acceptance: all examples and library modules must have correct `(open ...)` declarations.
- scope: module loader, strict typecheck
- note: prerequisite MOD-1.

## REQ-mod-5-interface-mismatch
- source: docs/compiler-team-roadmap.md (Future, Module System Codegen, MOD-5)
- description: `[CT]` `checkInterfaceMismatch` wiring: add an `interfaceName` field to the `Import` AST in `Syntax.hs`, parse the `(interface ...)` clause in `Parser.hs`, and expand `meAliasMap` types before comparison in `Module.hs`.
- acceptance: (absent; status `☐`). Additionally motivated by XMOD-AG (v0.14.17): cross-module assume-guarantee inherits nominal-by-name ADT identity (same-named imported ADTs compared by constructor names, not structure); MOD-5's structural check would close that limitation.
- scope: module interfaces, `Import` AST, `meAliasMap`, XMOD-AG nominal identity
- note: prerequisite MOD-2.

## REQ-wasm-build-target
- source: docs/compiler-team-roadmap.md (Future, WASM Sandboxing)
- description: Replace Docker with WASM-WASI as the primary sandbox. Four phases (~7 days): Phase 0 install `ghc-wasm-meta` + `wasmtime` and manually compile hangman; Phase 1 `--target wasm` flag, generate a `.cabal` file, invoke `wasm32-wasi-cabal`; Phase 2 strip check blocks for WASM and map WASI capability imports; Phase 3 CI integration, setup script, docs.
- acceptance: `llmll build --target wasm examples/hangman_sexp/hangman.llmll` produces a `.wasm` binary; `wasmtime hangman.wasm` runs the game correctly; WASI capability imports align with LLMLL capability declarations; typed effect rows (`effectful`) integrate with WASI enforcement.
- scope: WASM/WASI sandboxing, build target, capability mapping
- note: unversioned. Risk: `ghc-wasm-meta` toolchain maintenance is low-bus-factor. Trigger: real users running untrusted agent code outside development environments, or Docker proving insufficient as a sandbox.

## REQ-lever-a-residue-a3x
- source: docs/compiler-team-roadmap.md (Future, Data Scope Extension, Lever A row)
- description: The open A3.x residue after Lever A completed (v0.14.33-51): the reuse-retrieval driver abstains on array contracts; CDP array-sorted candidate bases; classifier callee-leg imprecision.
- acceptance: (absent; recorded as open residue. The DATA class itself is complete)
- scope: Lever A arrays/maps, reuse retrieval, CDP candidate bases, obligation classifier
- note: also deliberate residue elsewhere in the set: non-`{int,string}` keys and direct `(map-empty)` reads.

## REQ-lever-b-dependent-lengths
- source: docs/compiler-team-roadmap.md (Future, Data Scope Extension, Lever B row); docs/design/data-scope-extension.md (Post 7, Lever B)
- description: Dependent lengths: length-indexed list types (`list[t]{len = n}`) plus a widened total-measure catalog, so an index refinement can be checked against a list's own length without arrays. Bridges "count a list" to "index a list safely".
- acceptance: Stays inside QF-LIA + EUF (+ arrays from Lever A), therefore **decidable**, so it stays in `Sigma_auto`. Unlocks safe list indexing.
- scope: dependent lengths, measure catalog, list indexing, `Sigma_auto`
- note: status **Proposed**; depends on Lever A (shipped); **overlaps R1** (indexed/dependent types, `Vect n a`).

## REQ-lever-c-induction
- source: docs/compiler-team-roadmap.md (Future, Data Scope Extension, Lever C row); docs/design/data-scope-extension.md (Post 7, Lever C)
- description: Inductive datatypes and induction: admit recursive datatypes to the verified tier with measure unfolding, Proof by Logical Evaluation (PLE), refinement reflection, and user- or auto-supplied induction. Unlocks list/tree/stack structural invariants (sortedness, balance, acyclicity, use-after-free).
- acceptance: Induction is **undecidable in general**, so this **cannot live in `Sigma_auto`** without breaking the decidability guarantee. It requires one of: a new, weaker trust tier for "proved by bounded/heuristic induction", **or** routing these obligations to the Lean tier (`verified-lean` / `DLVerifiedLean`) where the proof is kernel-checked and carries a re-checkable certificate.
- scope: recursive ADTs, induction, PLE, refinement reflection, trust tiers, Lean tier
- note: research frontier, gated on **LEAN-GA**. The R7 strict-descent gate cleared (shipped v0.14.25/27).

## REQ-lean-ga-layer1-translator
- source: docs/design/leanstral-integration-scope.md §2, §7; docs/compiler-team-roadmap.md (Externally-Blocked Parking Lot, LEAN-GA)
- description: Rewrite `LeanTranslate.hs` to translate the **obligation**, not the contract. `translateObligation` today reads only `contractPre`/`contractPost`; the body is never referenced, so `result` and params are unbound free variables and the emitted theorem is misstated (non-elaborating, or a universally-quantified false claim). Widen it to receive params/ret/**body** and emit `theorem f (p̄) (h_pre) (result) (h_body : result = ⟦body⟧) : ⟦post⟧`, with a new `bodyToLean` that mirrors `bodyToPredM`'s traversal but **admits** the nonlinear fragment.
- acceptance: Escape-class discipline: `*` faithful inside a bound obligation; `/` and `mod` map to `Int.fdiv`/`Int.fmod` (LLMLL codegen emits floor division, Lean's `/`/`%` are truncated; they disagree on negative operands, a silent unsoundness invisible on positive operands), verified empirically before ship else `Unsupported`; `^` Nat-exponent only; **kill** `list-head -> .head!` (unsound partial) and untyped `for-all` -> `Unsupported`; a residual free variable **fails closed** to `Unsupported`; termination measures -> `Unsupported`. Trust rests on a translation-adequacy (simulation) lemma, professor-reviewable. Gated on professor adequacy review + fixture replay. **Non-negotiable:** must not ship without the §5 anti-laundering guard.
- scope: `LeanTranslate.hs`, obligation translation, faithfulness, floor-vs-truncated division
- note: this is the trust root and must lead the sequence. Effort for layers 1+2 ≈ 5-8 days, review-dominated.

## REQ-lean-ga-layer2-routing
- source: docs/design/leanstral-integration-scope.md §3, §7
- description: Route the obligations that need Lean into the channel that feeds the pipeline. Today a nonlinear body hits `addBodyFallback` -> `erBodyFallback` -> `asserted` and is never marked `?proof-required`, while the Leanstral pipeline consumes only body-position `?proof-required` holes (`Main.hs:1682-1690`), so the obligations Lean exists to discharge never enter it. Change `runLeanstralPipeline` to take an obligation worklist unioned from `erBodyFallback` + existing holes + analysis flags, resolving each function's real body for layer 1. Gap B (small): `isNonLinear` (`HoleAnalysis.hs:338-348`) has no `EOp` case, so `(* n m)` is not auto-flagged; add the `EOp -> EApp` normalization.
- acceptance: (absent; sequencing stated: Gap B before layer 1, Gap A after). No function is falsely reported `verified` today; this is a coverage/routing gap, not a soundness hole.
- scope: obligation routing, `erBodyFallback`, `?proof-required`, `runLeanstralPipeline`, `isNonLinear`
- note: coupled to layer 1, which supplies the real body.

## REQ-lean-ga-layer3-transport
- source: docs/design/leanstral-integration-scope.md §4, §8, §8.1
- description: Build the T-B (server-as-checker) transport: the Leanstral model produces a candidate proof over a separate endpoint, and `lean-lsp-mcp` only checks it. `lean-lsp-mcp` exposes LSP primitives, **not** a `prove(theorem) -> proof_term` tool, so the `MCPClient.hs` non-mock branch is a stub built on a wrong assumption. Add a model-search + kernel-check loop and a retry-with-error loop.
- acceptance: Accept a proof iff zero errors, zero open goals, no `sorry`. Store the returned **proof term** as the durable artifact so independent re-checking is a deterministic kernel re-run (the PROOF-ARTIFACT C-property mechanism). Config: `MCPConfig` needs `mcpEndpoint` / `mcpModel` plus an env-only key (`LLMLL_LEANSTRAL_API_KEY`, never a flag or log). Build facts established by the step-0 probe: model id is `labs-leanstral-1-5` (Labs model, org admin must enable Labs); response shape is prose plus a fenced ```lean block, so the fence must be extracted; every proof uses Mathlib, so the trusted base is Lean kernel + Mathlib. The retry-with-error loop is **required for production, not for the demo**: nonlinear arithmetic kernel-checks 2/2 one-shot; the inductive/list class is one-shot-miss then one-retry-fix.
- scope: `MCPClient.hs`, MCP transport, kernel check, proof term storage, retry loop
- note: data privacy: `labs-*` models carry different data-usage terms; a governance decision is owed before real proprietary obligations are sent.

## REQ-lean-ga-anti-laundering-guard
- source: docs/design/leanstral-integration-scope.md §5
- description: Reject `sorry` / `admit` / empty proof terms before returning `ProofFound`, enforcing the PROOF-ARTIFACT §4.1 LCF anti-laundering invariant. Both the mock (`mockProofResult -> ProofFound "by sorry"`) and a degenerate real response could otherwise launder to a `verified` tier tagged `"leanstral"`. Also fix the `MCPClient.hs:6-11,48` docstring drift claiming the real protocol "is implemented" while the code is a stub.
- acceptance: `sanitizeProof` chokepoint, word-boundary aware; the mock's `by sorry` becomes a `ProofError`; end-to-end writes an empty cache instead of laundering.
- scope: `MCPClient.hs`, anti-laundering, PROOF-ARTIFACT §4.1
- note: recorded **BUILT** in a worktree as of 2026-07-04, **uncommitted, pending review/merge**. Small, independent of layers 1-3, and worth doing regardless.

## REQ-mcp-integration
- source: docs/compiler-team-roadmap.md (Externally-Blocked Parking Lot, MCP row)
- description: MCP integration for the compiler CLI.
- acceptance: (absent)
- scope: MCP, compiler CLI
- note: trigger, a concrete external integration request.

## REQ-r8-latency-benchmark
- source: docs/design/incremental-reverify-r8-proposal.md (Validation); docs/compiler-team-roadmap.md (R8 row)
- description: The repair-loop latency benchmark that R8 shipped without: a synthetic N-function module, patch one hole, whole-module versus sliced wall-clock as N grows (basis `experiments/cdp-perf-0/`). Expectation: whole-module scales with N, sliced is flat.
- acceptance: (absent; recorded as deferred residue. Correctness is already proven and the O(module) -> O(1) body-VC win is structural)
- scope: `llmll patch`, re-verify slice, latency measurement

## REQ-refine-slice
- source: docs/design/incremental-reverify-r8-proposal.md (Out of scope); docs/design/rfc-swarm-roadmap-proposal.md §4 Phase 2 (REFINE-SLICE-1)
- description: The refine-side sibling of R8. `refine` spawns *new* contracted functions whose fresh body-VCs must be verified, a different, additive slice, deliberately excluded from R8 Rev 0.
- acceptance: Contingent. Build only if Phase 2 dry-run telemetry shows refine re-verify dominating, and only after its own soundness note is written first.
- scope: `refine`, re-verify slice, assume-guarantee
- note: also recorded as the forward lever for contract edits: were a future op to edit a contract, the slice would extend to the transitive callers of the edited function.

## REQ-rfc-cov-1
- source: docs/design/rfc-swarm-roadmap-proposal.md §4 Phase 1 (RFC-COV-1)
- description: `[CT]` (S) The inventory-to-`:source` cross-check lint, including the fallback-mode failure and the `:source`-on-roots-only monopoly check. Syntactic, no solver.
- acceptance: RFC-COV-1 green; every contracted clause carries resolvable provenance at the decided mode's granularity; the clause-carrying surface frozen; roots verify at contract level and classify `contract_fragment: qf_lia` (the A4 Phase-2 gate, reused verbatim).
- scope: RFC-SWARM Phase 1, `:source` provenance, coverage lint
- note: the sibling item SRC-CONJ-1 shipped v0.14.65 and is **not** emitted as a requirement. `docs/design/rfc-swarm-playbook.md` stage L records `scripts/rfc_coverage.py --require-full-coverage` as the executed form and states the four directions it checks.

## REQ-ext-agent-1
- source: docs/design/rfc-swarm-roadmap-proposal.md §4 Phase 1 (EXT-AGENT-1)
- description: `[EXP]` (S) Blind-agent stages S1-S3 plus the independent second extraction and reconciliation. The agreement statistic is the finding.
- acceptance: The agent arm failing does **not** block: it downgrades the extraction-role claim and the wave proceeds on dual-checked human extraction.
- scope: RFC-SWARM Phase 1, blind extraction, agreement statistic

## REQ-swarm-1-concurrency-protocol
- source: docs/design/rfc-swarm-roadmap-proposal.md §4 Phase 2 (SWARM-1)
- description: `[DESIGN+EXP]` (M) The concurrency protocol note (explicit soundness argument, token-granularity resolution, separated retry budgets) plus the runner implementation, and a positive-witness test for the spawn-name collision. Dry run: re-run the `token-revocation-emergent` tree under N >= 4 concurrent agents and compare against the sequential baseline, recording conflict/latency telemetry.
- acceptance: The dry-run tree reaches the same verdicts as the sequential record, zero integrity violations, telemetry published.
- scope: RFC-SWARM Phase 2, multi-agent concurrency on one module tree
- note: STOP/descope: if the pre-registered numeric trigger fires (wall clock >= sequential baseline, or conflict-retry fraction above the Phase 0 bound), ship the swarm as parallel-per-module cascades with the limitation stated; only the intra-tree half of the claim is sacrificed. `docs/design/rfc-swarm-playbook.md` stage M supplies the executed resolution of the token-granularity question; see REQ-rfc-swarm-harness-resubmit-protocol.

## REQ-rfc-swarm-phase3-wave
- source: docs/design/rfc-swarm-roadmap-proposal.md §4 Phase 3
- description: `[EXP]` (M) The blind swarm fills the frozen TFTP roots under the Phase 2 protocol. Semantic retries <= 3 with error-text-only feedback; protocol retries counted separately; full audit trail.
- acceptance: Whole artifact SAFE under `--strict-verified-core`; all Encoded-clause functions body-faithful; budgets met; audit trail complete.
- scope: RFC-SWARM Phase 3, blind fill, `--strict-verified-core`
- note: requires Phases 0, 1, 2. STOP/descope: a hole that exhausts retries is a *finding*, never a hint occasion; if >= 3 holes exhaust, pause and adjudicate; do not lower the bar mid-wave. Per `docs/design/rfc-swarm-playbook.md` stage M, `--strict-verified-core` is the **whole-tree end-of-wave** bar and must not gate a single fill.

## REQ-rfc-swarm-phase4-refute-freeze
- source: docs/design/rfc-swarm-roadmap-proposal.md §4 Phase 4; docs/design/rfc-swarm-playbook.md stage N
- description: `[EXP][SPEC]` (S-M) Execute the Phase 0 mutant taxonomy: per-class mutants for every Encoded **and** Deployment-modeled row (the duplicate-ACK crux mandatory); freeze `EXPECTED_VERDICTS.json`; wire `make refute-crux-gate`; keep good twins SAFE in the same gate; report the **full kill matrix including survivors**, each survivor adjudicated as weak-contract-fixed or re-dispositioned. Produce the demo document (inventory with the Encoded fraction stated first, tier table, kill matrix, process metrics, integrity trail, trusted-composition-schema disclosure, claim discipline).
- acceptance: Every Encoded and Deployment-modeled clause has its taxonomy mutants authored; the kill matrix frozen and green in CI with survivors resolved; the writeup passes the positioning guardrails review.
- scope: RFC-SWARM Phase 4, mutation adequacy, refute-crux gate, writeup
- note: requires Phase 3. STOP/descope: a clause with no constructible refuting mutant is re-audited, either the contract is weak (fix, re-verify, record as a co-evolution exhibit) or the clause is re-dispositioned; neither silently ships.

## REQ-rfc-fourth-run-screening
- source: docs/design/rfc-swarm-target-selection.md §5, §6
- description: Screen fourth-run RFC candidates by running the real pipeline stages up to the gate and stopping: `scripts/rfc_to_implementation.py --only A,B,C,D,E,F,G,G2,J --rfc-url <url> --workdir ~/rfc-swarm-runs/<name> --agent-cmd '<cmd>'`. Stage H is the one to skip and is where the time goes (roughly 45 minutes of the RFC 4648 run's 4565s). Three candidates remain **unscreened, not rejected**: RFC 2453 (RIP v2), RFC 792 (ICMP), RFC 6455 (WebSocket). RFC 6298 (TCP RTO) screened and **REJECTed** at gate J (40 rows, 11 core, one out: `A27` under `B3`, trace-level).
- acceptance: A candidate is admissible when all six criterion clauses hold of the clauses that make the protocol *that protocol*: (1) the core is state transitions and fixed-width field values, not byte-stream layout; (2) no core obligation requires locating a field whose offset depends on another field's value; (3) no core obligation concerns position within, or insertion into, an output sequence; (4) no core obligation rests on an opaque transform (checksums, cryptography, character-set translation); (5) timing and liveness clauses may exist but must not be characteristic; (6) roughly 20 to 25 roots. The criterion **cannot be evaluated without running the pipeline**, which is the section's own evidence.
- scope: RFC target selection, gate J, stages A-J, screening cost
- note: screening is **quota-bound**: two usage windows produced one verdict; a screen is 45-60 minutes of agent work, not the 30 estimated. The fourth run is a multi-window project whose cost is dominated by delegation. All four workdirs are intact under `~/rfc-swarm-runs/screen-*`; a resume re-runs only what is not recorded complete, but stage D re-runs **both** extractors, so per-artifact reuse is recorded rather than built.

## REQ-rfc-swarm-barrier-field-backfill
- source: docs/design/rfc-swarm-playbook.md §4 (`--self-test`, "What it does not cover, and now says so")
- description: Make gate J's third condition (an exclusion for a reason outside the closed barrier list) evaluable on the pinned TFTP Phase 0 artifact. The closed barrier list postdates the TFTP run, so none of its 53 exclusions carries a `barrier` field and the per-barrier tally lives as prose in `VERIFICATION_SCOPE.md` rather than as data. Replayed against the shipped driver, that ledger would fail the disposition schema check and then STOP at the gate.
- acceptance: (absent as a criterion; the source states the requirement negatively). The self-test currently asserts the zero and **prints the gap**, on the stated ground that a condition skipped in silence is a gate kept green by its own blind spot, the defect that let a failed freeze gate be bypassed by its own report.
- scope: RFC-SWARM, gate J condition 3, closed barrier list, `--self-test`, TFTP disposition ledger
- note: a second, deliberate self-test limitation is recorded and is **not** a requirement: stage G2 is pinned only in the half that needs no source bytes, because the pinned RFCs are deliberately outside this repository, so the citation checks cannot be replayed here.

## REQ-rfc-swarm-harness-resubmit-protocol
- source: docs/design/rfc-swarm-playbook.md stage M
- description: Implement the wave harness submission protocol the first run derived the expensive way. The advisory lock is **per-hole** (checkout tokens keyed by JSON pointer, so N agents genuinely hold N different holes), but the compare-and-swap is **per-FILE** (`patch` validates against a whole-source hash and rejects anything older with `PatchAuthError: obligation context is stale`), so the first patch to land invalidates every other outstanding brief however unrelated the holes. Required shape: on submission, under a lock, **release the token, re-checkout the same pointer, and rebuild the patch from the fresh token and the current hole node**. The body is unaffected, because it was authored against the contract, which does not change when a sibling is filled; that costs no model call, which is why these retries are budgeted apart from semantic ones. Two harness failure modes must be avoided, both of which silently manufacture fake findings: **never re-checkout without releasing** (a stale-context rejection followed by a bare re-checkout returns `hole ... is already checked out` forever and wedges the hole; on the first run this turned 14 correct fills into "findings", one of which had already produced the right answer `(+ acked 1)`), and **do not gate a single fill on `--strict-verified-core`** (it hard-errors when any function in the module falls back, and during a wave every unfilled hole falls back by construction, so it rejects a correct body for its siblings being unfinished and makes the bar order-dependent). Each agent gets a **pristine** scratch copy of the module, every hole still a hole, so it can self-check before submitting; handing over the live tree would let one agent read another's attempt and destroy the blindness the wave exists to demonstrate.
- acceptance: Per-fill bar read per function: verify SAFE, the filled function in the body-faithful set, not flagged `termination_unverified`. The whole-tree strict check is kept for the end, when it means what it says. Independently confirmed on the first run: two holes checked out concurrently, first patch `PatchSuccess`, second `PatchAuthError`.
- scope: RFC-SWARM wave harness, `checkout` / `patch` / `refine`, advisory lock, compare-and-swap, per-fill bar
- note: the source states this **prescriptively for the next harness** and does not record it as built. Confirm build status against `docs/compiler-team-roadmap.md` (which carries no corresponding row) before scheduling. Refines rather than competes with REQ-swarm-1-concurrency-protocol: SWARM-1 is the protocol note plus runner, this is the executed resolution of its token-granularity question.

## REQ-spec-agree-1a-constructor-backend
- source: docs/design/spec-agreement-proposal.md Rev 1 §6.1, §6.2, §6.3(a)
- description: `[CT]` SPEC-AGREE-1a, the constructor-capable comparison backend. Declare constructors and their sorts in the subsumption query by reusing the `FixpointEmit` declaration path, rather than the bare two-constraint `.fq` that declares no UF constants. **In scope for this track, re-sequenced ahead of the harness, and without a Lever A dependency** (finding M-3: all 18 measured abstentions fire on `ufBearing`'s uppercase-head clauses; zero on `contractMentionsArrOp`, zero on a measure). The `baseSortText` widening (§6.2) is scoped alongside it pending the engineer feasibility read.
- acceptance: The comparable fraction over the same committed corpus rises from 9/85, republished.
- scope: SPEC-AGREE-1, `RefineReuse.hs`, `FixpointEmit.hs` declaration path, `Sigma_subsume`, constructor terms
- note: the arithmetic for the re-sequencing: an N-way run costs N agent authorings per row and, at 10.6%, returns a decidable verdict on one row in ten while excluding by construction every state-transition row, which is where the pipeline's documented failure lives (`step-weak`, pipeline §S4.4). Payoff is bounded by `Sigma_witness` (§6.2): widening comparison to constructor terms unlocks the C1 transition rows whose distinguishing input **is** a constructor value, and that value cannot be rendered, so those rows would return a bare "these differ" bit with no exhibit.

## REQ-spec-agree-1-effective-contract-and-verdicts
- source: docs/design/spec-agreement-proposal.md Rev 1 §6 table, §6.3(b)
- description: Fix the two defects that are preconditions of any meaningful number, adopted from review findings F-2 and F-3. **Effective-contract comparison:** `RefineReuse.hs:194-195` binds parameters as `FQReft "v" sort FQTrue`, dropping refinements; comparison must be over `pre ∧ param refinements` and `post ∧ return refinement`, matching `Feasibility.hs:155-162`. **Three-valued verdict:** `contractSubsumes` collapses non-`FQSafe` to `False` (`:226`), booking solver errors as fidelity findings; the information already exists at `DiagnosticFQ.hs:58-62`.
- acceptance: (absent as a numeric criterion). Stated as a precondition of any meaningful number, and cheap relative to the constructor backend.
- scope: SPEC-AGREE-1, `RefineReuse.hs`, `DiagnosticFQ.hs`, effective contract, three-valued verdicts

## REQ-spec-agree-1-comparison-cli
- source: docs/design/spec-agreement-proposal.md Rev 1 §3 steps 3 and 5, §6 table, §6.3(c)
- description: The comparison CLI emitting the **product position** `(pre-position, post-position)`, each in `{≡, ⊐, ⊏, ⋈}`, adopting Zaremski-Wing names where they apply (F-4), together with a **new two-contract difference query** and `result` in the witness vector (F-5). `Feasibility.buildQuery` takes one contract and hard-wires `∃in. pre ∧ ∀result. ¬(Rret ∧ post)` (`:167-169, 199-208`) and is **not reusable**; the difference query is an easier shape, plain QF-LIA SAT: `∃p̄. pre_A ∧ ¬pre_B` and `∃p̄,result. post_A ∧ ¬post_B`, quantifier-free over free constants. `minimizeWitness` and `witnessOf` range only over `qInputs` (`:256-284`) and must be extended.
- acceptance: (absent as a numeric criterion). Disposition of the strictly-ordered case uses F-6's three discriminators in decreasing definitiveness: feasibility of the stronger contract (`Feasibility.hs:292-304`), good-twin refutation (stage N), mutant kill differential. **Precondition strengthening is a defect candidate by default**, not "informative rather than fatal".
- scope: SPEC-AGREE-1, comparison CLI, product order, difference query, witness vector
- note: this step and the two before it have value for `refine` hygiene and accidental-duplication detection independent of whether the experiment runs, which preserves the review's Recommendation 2 as a fallback rather than an alternative.

## REQ-spec-agree-1-gloss-experiment
- source: docs/design/spec-agreement-proposal.md Rev 1 §3 step 2, §4 (T4), §6.3(d)
- description: The two-arm gloss experiment (F-7 lever 2) on whatever fragment the constructor backend delivers. The inventory row carries a one-sentence obligation authored at stage D, which is a prior formalization of the same clause in prose fed identically to all N arms; it sits at the same layer as the artifact being produced and is a larger leak than T3. Withhold the inventory obligation gloss from **at least one arm** and report agreement with and without it.
- acceptance: (absent as a threshold). Described as the cheapest manipulation that determines whether anything else on this track means anything.
- scope: SPEC-AGREE-1, threat T4, obligation-gloss priming channel, framing experiment
- note: gated on REQ-spec-agree-1a-constructor-backend.

## REQ-spec-agree-1-nway-adversarial
- source: docs/design/spec-agreement-proposal.md Rev 1 §3, §4 (T3), §6.3(e)
- description: Scale to N = 3 with adversarial framings (F-7 lever 1). Threat T3 (framing by the frozen signatures) is **measured, not only disclosed**: on a sample, run one arm against the frozen signature and a second against the same signature with constructor and field names mechanically replaced by opaque `A0..An`, sorts preserved.
- acceptance: Reporting rule, adopted without qualification (F-8): **never an unstratified agreement rate**. The headline is **the count and per-row list of `Encoded` rows where witness adjudication changed the frozen contract**, as a fraction of rows that reached comparison, published beside the `not-comparable` count and the comparable fraction. That is detection yield rather than concordance, and weak contracts cannot inflate it. Agreement figures, where reported at all, are stratified by discriminative power: rows whose contracts kill at least one pre-registered mutant, complement reported separately.
- scope: SPEC-AGREE-1, N-way blind formalization, adversarial framing, reporting discipline
- note: last step of the build order; gated on all prior steps. Adjudication is against the verbatim source text, never by vote.

## REQ-spec-agree-1-stage-k-amendment
- source: docs/design/spec-agreement-proposal.md Rev 1 §7, §3 (precondition), §5 EC-6
- description: Amend `docs/design/rfc-swarm-playbook.md` stage K, which currently says root contracts are authored by "agent(s)". The amendment is narrower than Rev 0 proposed: fix signatures **and add EC-6's naming rule to the freeze**, evaluate `qfContract` per row, send only the comparable set for N-way blind authoring, auto-accept unanimous rows, route non-equivalence to witness-based adjudication subject to the `Sigma_witness` limit, record `not-comparable` rows in the denominator, then proceed to the coverage lint and the freeze as before. EC-6: **"no parameter may be named `result`" joins the stage-K freeze rules**, because `alphaRenameMap` (`RefineReuse.hs:106-112`) gives the parameter mapping priority and leaves the postcondition result binder unnormalized.
- acceptance: Gate first, author second: rows that abstain under `qfContract` are recorded `not-comparable` and are **not** sent for N-way authoring, which is what keeps the experiment's cost proportional to its yield.
- scope: SPEC-AGREE-1, playbook stage K, signature freeze rules, `qfContract` gating
- note: stage D (dual blind extraction) is recorded as the same pattern one layer up. The playbook's stage K text is the current operational authority until this amendment lands.

## REQ-spec-agree-1-unrendered-defeater-question
- source: docs/design/spec-agreement-proposal.md Rev 1 §8 (open question for the professor)
- description: **Does an unrendered defeater carry evidential weight on its own?** Widening comparison to constructor terms would produce rows where the solver decides that two readings differ but no witness can be rendered, because the distinguishing value is a constructor and `baseSortText` admits Int and Bool only. In the eliminative frame the `sat` verdict alone falsifies "both readings are faithful", so the defeater is sound without the model. But the design's claimed advantage over human audit is the exhibit, the forced-choice discrimination on a concrete instance that F-13 grounds in Jackson's instance-level validation. If the exhibit is absent, does unlocking C1 comparison add anything a coverage count would not already show, or does the evidential value collapse to the bare count of disagreeing rows?
- acceptance: The answer decides whether widening `baseSortText` to enum sorts is a **prerequisite** of the constructor backend or an **enhancement** to it, which is the difference between one `[CT]` item and two.
- scope: SPEC-AGREE-1, `Sigma_witness`, evidential status of an unrendered defeater
- note: open work, addressed to the professor. Replaces Rev 0's five open questions; four are answered by the review and the fifth by F-13.

## REQ-spec-agree-1-basesorttext-feasibility
- source: docs/design/spec-agreement-proposal.md Rev 1 §9 (open item for the compiler-engineer); classification note (`Sigma_witness` finding routed to compiler-engineer)
- description: Feasibility read, **not** an implementation plan. Cost of (i) reusing the `FixpointEmit` declaration path for the subsumption query, and (ii) widening `baseSortText` (`Feasibility.hs:187-191`, which returns `Just "Int"` or `Just "Bool"` and `Nothing` for every other type after alias and refinement resolution) to enum and constructor sorts with `witnessOf` extended to match; and whether (ii) is separable from (i) or forced by it.
- acceptance: (absent; a feasibility read, no acceptance criteria stated)
- scope: SPEC-AGREE-1, `Feasibility.hs` `baseSortText`, `witnessOf`, `minimizeWitness`, `FixpointEmit` declaration path
- note: open work, addressed to the compiler-engineer. This is the new-in-Rev-1 `Sigma_witness` finding.

## REQ-spec-agree-1-remeasure-comparable-fraction
- source: docs/design/spec-agreement-proposal.md Rev 1 ("Provenance of §0")
- description: Re-derive the comparable-fraction measurement through the real `classifyContractFragment`, `contractMentionsArrOp` and `ufBearing` before any figure is published outside the proposal. §0's measurement transcribes `qfContract` and applies it to committed artifacts; it does not invoke the compiler, and its `classifyContractFragment` approximation ("at least one clause present") is generous.
- acceptance: The re-run reports the true fraction, which is **at or below 10.6%**. Every §0 figure is an upper bound until then.
- scope: SPEC-AGREE-1, measurement provenance, `qfContract`, comparable fraction
- note: experiment-lead's slot; belongs beside the existing runner rather than in the proposal document.

## REQ-r1-indexed-dependent-types
- source: docs/compiler-team-roadmap.md (Research track, R1)
- description: Indexed / dependent types: `Vect n a`, GADTs, type-level arithmetic, bidirectional typechecking.
- acceptance: Original promotion criterion: a design spec with typing rules, a bidirectional migration plan, and an erasure strategy.
- scope: research track, dependent types
- note: partially promoted (the obligation-guided part shipped in v0.10); deferred by professor consensus (2026-05-01), not a v0.x target. Overlaps Lever B.

## REQ-r2-self-hosted-orchestrator
- source: docs/compiler-team-roadmap.md (Research track, R2)
- description: Self-hosted orchestrator: rewrite `llmll-orchestra` as LLMLL `def-main :mode cli`.
- acceptance: Original promotion criterion: agent accuracy >= 80% on the auth-module exercise when filling LLMLL-source holes.
- scope: research track, orchestrator
- note: recorded as a dependency of the cascading-refinement acyclicity policy.

## REQ-r4-synthetic-training-corpus
- source: docs/compiler-team-roadmap.md (Research track, R4)
- description: Synthetic training corpus: Hackage back-translation; transpiler plus spec lifting plus benchmark.
- acceptance: Original promotion criterion: a research proposal with a measurable hypothesis and evaluation methodology.
- scope: research track, training corpus
- note: no competing roadmap row; independent.

## REQ-cascading-refinement-gating-question
- source: docs/compiler-team-roadmap.md (Future, Cascading Refinement, acyclicity policy note)
- description: One open design question left by the acyclicity policy: per-contract versus composed gating.
- acceptance: (absent)
- scope: cascading refinement, `refine`, cycle gating
- note: the Cascading Refinement line is otherwise recorded complete (Layers 1-4 shipped v0.14.13-53); the design-accepted joint-vacuity limitation is delegated to R5.

## REQ-do-1-discard-warn-or-error
- source: docs/design/critique-2026-05-23-triage.md §4 (DO-1 row)
- description: Compiler-side warn-or-error on non-final `Command`-typed binds in `do`-notation. The `LLMLL.md §9.6` spec text shipped (the Compilation bullet plus the "Intermediate commands silently discarded" callout); the compiler enforcement remains a separable engineer sub-item.
- acceptance: (absent; recorded as "engineer sub-item open")
- scope: `do`-notation, command discard, compiler diagnostics
- note: recorded **only at precedence 2** (a DOC-typed triage record dated 2026-05-23) and **absent from the backlog of record**. Confirm against `docs/compiler-team-roadmap.md` before scheduling. See INFO-18 in `.planning/INGEST-CONFLICTS.md`.
