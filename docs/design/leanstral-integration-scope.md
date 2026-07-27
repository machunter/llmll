# LEAN-GA — Leanstral Integration Scope (Spike Findings, 2026-07-04)

> **Version:** Rev 0 — captures the two-audit spike (translator faithfulness + MCP transport) run 2026-07-04.
> **Status:** Scoping note — **not a commitment to build.** Records what the spike found so LEAN-GA can be re-scoped in the parking lot with real evidence rather than the stale "blocked only on `lean-lsp-mcp` availability" framing.
> **Date:** 2026-07-04
> **Relates to:** roadmap `LEAN-GA` (externally-blocked parking lot, `docs/compiler-team-roadmap.md:97`); `TRUST-2b` (`prover: "lean"` evidence, parked); PROOF-ARTIFACT C-property (reserved for the Lean tier, `docs/archive/shipped-design-specs/proof-artifact-proposal.md`); `LLMLL.md §5.3.3:912` ("Inductive properties — designed, not shipped").
> **Trigger:** Mistral's Leanstral 1.5 release (open weights `mistralai/Leanstral-1.5-119B-A6B`, Apache-2.0; free `leanstral-1-5` API; Lean LSP MCP support) — which prompted the question "should real Leanstral integration be next?"

---

## 1. Executive finding

The parking-lot framing — *"LEAN-GA is blocked only on `lean-lsp-mcp` availability"* — is **wrong on three independent layers**, only one of which the Leanstral 1.5 news touches. LEAN-GA is a **three-layer rebuild**, not a next-sprint integration. The value (discharge the non-QF-LIA obligation tail; deliver the kernel-checkable C-property) is real but is gated behind all three.

| Layer | Finding | Status today | Source |
|---|---|---|---|
| **1. Obligation translation** | `LeanTranslate.hs` translates the *contract*, not the *obligation* — the function body is never passed in, so `result`/params are free variables → the emitted theorem is misstated (non-elaborating or a universally-quantified false claim). | Structurally unfaithful; a rewrite. | §2 |
| **2. Obligation routing** | The obligations that most need Lean (nonlinear bodies, complex measures) land at `erBodyFallback → asserted` and are **never marked `?proof-required`**; the pipeline only picks up *body-position* `?proof-required` holes (`Main.hs:1682-1690`), so they never reach it. | Honest (`asserted`, not falsely `verified`) but never routed to Lean. Rework. | §3 |
| **3. Transport / prover** | `lean-lsp-mcp` exposes the Lean *language-server* primitives (goals, diagnostics, `lean_build`, premise search) — **not** a `prove(theorem)→proof_term` tool. The `MCPClient.hs` non-mock branch is a stub built on a wrong assumption. | Needs a model-search + kernel-check loop (T-B, §4) built + a new endpoint/API-key config. | §4 |

## 2. Layer 1 — the translator is structurally unfaithful (rewrite)

`translateObligation :: Name → Contract → TranslateResult` reads **only** `contractPre`/`contractPost` (`LeanTranslate.hs:32-49`); the body is never referenced. The emitted theorem for the one example that flows end-to-end (`safe-div`, `examples/proof_required_test/`) is:

```
theorem safe_div (h : (d > 0)) : (result >= 0) := by sorry
```

`d`, `n`, `result` are **unbound free variables**. This does not state "the body returns a `result ≥ 0` under `d > 0`"; as a Lean proposition it either fails to elaborate or (auto-bound-implicit) is a universally-quantified **false** claim (`result := −1` refutes it). Additional unsound/unfaithful cases: `list-head → .head!` (partial function, proves the post for `[]`); `for-all → ∀ v, …` (untyped, unbounded); the QF-NIA content that motivates Lean (`/`, `mod`, `^`) either hits the honest `Unsupported` path or is embedded in the otherwise-misstated theorem. The parts that *are* faithful (`+`,`-`, comparisons, `.length`) are the QF-LIA-shaped ones that do **not** need Lean.

**Requirement:** a sound translator must state the **obligation** `pre ∧ (result = ⟦body⟧) ⇒ post`, with `result` bound to the body — i.e. translate the body-VC, not the standalone contract. This is the core of the translation-**faithfulness** obligation: a proved Lean theorem certifies the LLMLL contract *only if* the encoding is faithful, so faithfulness is the trust root, not a downstream nicety.

## 3. Layer 2 — the obligations that need Lean are never routed there

Verified against the tier machinery: a nonlinear body hits `addBodyFallback` (`FixpointEmit.hs:656`) → `erBodyFallback`, which excludes the function from body-faithful `verified` and lands its post at **`asserted`** (honest "not proven"), surfaced in the obligation report (`ObligationAssembly.hs:832`). **No function is falsely reported `verified`** — this is a coverage/routing gap, not a soundness hole. But these obligations are never marked `?proof-required`, and the Leanstral pipeline only consumes body-position `?proof-required` holes (`Main.hs:1682-1690`), so the very obligations Lean exists to discharge never enter it. Secondary detection gap: `isNonLinear` matches only `EApp` (`HoleAnalysis.hs:339`) while the parsers route `*`/`/` to `EOp` (`Parser.hs:918`), so operator-form nonlinearity in contracts is not auto-flagged. **Requirement:** route `erBodyFallback` / complex-decrease obligations into the proof-required channel that feeds the pipeline.

## 4. Layer 3 — `lean-lsp-mcp` is a checker, not a prover (T-B is the trust-correct architecture)

`lean-lsp-mcp` surfaces LSP primitives over MCP; there is no `prove` tool. Two integration shapes:

- **T-A (server-as-prover):** a Leanstral-backed server exposing a `prove` tool — not stock `lean-lsp-mcp`.
- **T-B (server-as-checker) — recommended, and trust-correct:** the Leanstral **model** (separate endpoint + API key) *produces* a candidate proof; `lean-lsp-mcp` only *checks* it (send file → diagnostics → accept iff zero errors, zero open goals, no `sorry`).

**Why T-B is the right shape for LLMLL, not merely an option.** It maps exactly onto the core thesis — *an agent hallucinates a candidate; the compiler checks it* — applied to proofs: **Leanstral hallucinates a proof; the Lean kernel checks it.** The model is untrusted proof *search*; the kernel is the trusted *gate*. Two consequences:

1. **Model non-determinism is irrelevant.** The durable, checkable artifact is the returned **proof term**, not the model call. Store the term; independent re-checking = re-run the Lean kernel on the stored term, deterministically. **This is precisely the PROOF-ARTIFACT C-property mechanism** — kernel-checkable, LCF-style, surviving the model being a black-box network service.
2. **The C-property survives the whole stack** only if layers 1–2 are fixed first: a kernel-checkable certificate over a *misstated* theorem (layer 1) is worse than none.

Config gap: `MCPConfig` (`MCPClient.hs:24-28`) has no model-endpoint / API-key / model-id field; T-B needs `mcpEndpoint` / `mcpModel` + an env-only key (`LLMLL_LEANSTRAL_API_KEY`, never a flag/log).

## 5. Extractable-now hardening (independent of the rebuild): the anti-laundering guard

> **Status (2026-07-04): BUILT** — worktree `agent-a86df7da86853aed0` (`sanitizeProof` chokepoint, word-boundary aware; mock's `by sorry` now → `ProofError`; docstring drift fixed; `stack test` 1029/0; end-to-end confirmed to write an empty cache instead of laundering). Uncommitted, pending review/merge.


Both the mock (`mockProofResult → ProofFound "by sorry"`, `MCPClient.hs:60`) and a degenerate *real* response could launder to a `verified` tier tagged `"leanstral"` (`Main.hs:1721`). A guard that **rejects `sorry`/`admit`/empty proof terms before returning `ProofFound`** enforces the PROOF-ARTIFACT §4.1 LCF anti-laundering invariant and hardens even the current mock. It is small, independent of layers 1–3, and worth doing regardless. (Fail-closed is otherwise already enforced downstream — only `ProofFound` mutates the cache.) Also fix the `MCPClient.hs:6-11,48` docstring drift (claims the real protocol "is implemented" while the code is a stub).

## 6. Verdict and recommendation

- **Value is real but gated.** LEAN-GA would close the ~20% non-QF-LIA tail (nonlinear arithmetic — including TOTP's `mod`/`^` — and inductive/`list`/recursive-datatype properties) that today gets only `asserted`, and would deliver the **C-property** (kernel-checkable certificates), a differentiator no design-reference tool (Liquid Haskell, F\*, Dafny) offers under agent-authoring conditions. The news partly clears the *external* blocker (a capable model exists) but not the *internal* ones (layers 1–2) or the transport rebuild (layer 3).
- **Sequencing (if pursued):** (1) translator rewrite → (2) routing rework → (3) T-B transport + kernel-check loop. Each is a real project; the translator rewrite is the trust root and should lead. The MCP-plumbing plan (spike Lane D) is step-3 work, not first.
- **Strategic placement:** the spike vindicates *R5 as the committed build* (fully in-control, no hidden layers) and *LEAN-GA as scoped-but-deferred* (a genuine multi-layer project, now costed). **Hold the C-property marketing claim until layers 1–3 are real.** Extract the §5 anti-laundering guard now as a standalone hardening.

**Roadmap update owed to doc-lead — DONE (2026-07-04):** the `LEAN-GA` parking-lot blocker was re-characterized (external availability partly cleared; real gate = internal three-layer rebuild), and `LLMLL.md §5.3.3:912`'s "translation infrastructure exists" was softened (contract-only / body-decoupled).

---

## 7. Layer 1 & 2 implementation plan (spike follow-on, 2026-07-04)

A *reviewed plan*, not code — Layer 1 is the trust root, so it must not ship until its faithfulness argument is checked by a second reviewer + fixture replay.

**Faithfulness landmine (VERIFIED) — floor vs. truncated division.** LLMLL codegen emits Haskell `div`/`mod` = **floor** division (`CodegenHs.hs:642,645`); Lean 4's `/` and `%` are **truncated** (toward zero) — they disagree on negative operands (`(-7) mod 3` = `2` floored vs `-1` truncated). A naive `mod → %` translation would prove a theorem about **different arithmetic than the program runs** — a silent unsoundness. Fix: emit `Int.fdiv`/`Int.fmod`, verified empirically before ship (else `Unsupported`). *This is the concrete reason Layer 1 was planned, not blind-built — the mapping error is invisible on positive operands.*

**Layer 1 — translate the OBLIGATION, not the contract.** Widen `translateObligation` to receive params/ret/**body**; emit `theorem f (p̄) (h_pre) (result) (h_body : result = ⟦body⟧) : ⟦post⟧` — binding `result` to the translated body (mirrors the body-VC LHS/RHS `FixpointEmit.hs:701-706`), which makes faithfulness a syntactic correspondence rather than a substitution lemma. A new `bodyToLean` mirrors `bodyToPredM`'s traversal but **admits** the nonlinear fragment (invert the QF-LIA firewall — that fragment is the whole point of Lean). Escape-class discipline: `*` faithful (now inside a *bound* obligation); `/`/`mod` → `Int.fdiv`/`Int.fmod` (the landmine); `^` Nat-exponent only; **kill** `list-head → .head!` (unsound partial, proves the post for `[]`) and untyped `for-all` → `Unsupported`; residual free var → **fail-closed** `Unsupported`; termination measures → `Unsupported` (category error — not pre/post). Trust rests on a translation-adequacy (simulation) lemma, professor-reviewable; each refusal is a clause where the operator identity is not established.

**Layer 2 — routing (coupled to Layer 1; it supplies the real body).** *Gap B* (small, verified): `isNonLinear` (`HoleAnalysis.hs:338-348`) has no `EOp` case, so `(* n m)` — which the parser routes to `EOp` — is not auto-flagged; add the `EOp→EApp` normalization (mirroring `FixpointEmit.hs:1535`). *Gap A* (the bridge): the pipeline consumes only body-position `?proof-required` holes (`Main.hs:1682-1690`), but the obligations that need Lean land at `erBodyFallback → asserted` with **real bodies**; change `runLeanstralPipeline` to take an obligation worklist unioned from `erBodyFallback` + existing holes + analysis flags, resolving each function's real body for Layer 1.

**Sequencing:** (1) anti-laundering guard **[BUILT, §5]** → (2) Gap B → (3) Layer 1 (gate on professor adequacy review + fixture replay) → (4) Gap A → (5) Layer 3 T-B transport (§4). **Effort Layers 1+2 ≈ 5–8 days, review-dominated** — the code is modest; the faithfulness review is the deliverable's actual cost. Non-negotiable: Layer 1 must not ship without the anti-laundering guard (a bound, faithful theorem still launders on a `sorry` proof).


---

## 8. Step-0 empirical validation (2026-07-04)

Before any compiler work, the pivotal unknown — *does Leanstral actually discharge our translated obligations?* — was tested directly against the live `labs-leanstral-1-5` endpoint. **Result: gate cleared, 3/3.**

| Probe | Obligation | Verdict |
|---|---|---|
| 1 | `result = n*n ⇒ result ≥ 0` (nonlinear) | ✅ `rw [h]; nlinarith` (269 tok) |
| 2 | `result = (a-b)² ⇒ result ≥ 0` (nonlinear + substitution) | ✅ `rw [h]; ring; apply pow_two_nonneg` (240 tok) |
| 3 | `(xs++ys).length = xs.length + ys.length` (inductive/list) | ✅ `induction xs … simp` (136 tok) |

Both major escape classes the QF-LIA core firewalls out — **nonlinear arithmetic and inductive/list** — are covered, cheaply (`finish=stop`, ~130–270 tok each). The inductive/list result is the strategically important one: it reaches the recursive-measure class QF-LIA deliberately excludes.

**Build facts established (feed the demo spec + production):**
- **Model id is `labs-leanstral-1-5`** — not the launch page's shorthand `leanstral-1-5` (which returns `invalid_model`). It is a **Labs model**: an org admin must enable Labs at `admin.mistral.ai/plateforme/privacy` before it is callable (`400` otherwise). Auth is a standard Mistral API key (`GET /v1/models` → `200`).
- **Response shape:** prose + a ` ```lean ` fenced block → Layer-3 must **extract the fence**, not consume the raw content.
- **Every proof uses Mathlib** (`nlinarith`, `pow_two_nonneg`, `ring`, `simp`, `induction`) → the C-property's trusted base is **Lean kernel + Mathlib** (small, auditable — state it in the claim).
- **Data privacy:** `labs-*` is enabled via a `/privacy` setting — Labs models carry different data-usage terms than the standard API. Fine for toy demo theorems; a governance decision before real proprietary obligations are sent.

**The one open risk (not closed by Step-0):** proofs were *generated*, not *kernel-checked* (no Lean+Mathlib toolchain in the test environment). The demo's Layer-3 check loop closes it; the pre-build validation ([`leanstral-demo-spec.md §7`](../archive/shipped-design-specs/leanstral-demo-spec.md)) closes it *first*.

**Decision: the demo is greenlit.** Spec: [`leanstral-demo-spec.md`](../archive/shipped-design-specs/leanstral-demo-spec.md).

### 8.1 Kernel-check + retry validation (2026-07-04)

The Step-0 proofs were kernel-checked in a real Lean 4 + Mathlib project (`lake env lean`):

| Proof | One-shot kernel-check |
|---|---|
| `square` (`result = n*n ⇒ result ≥ 0`) | ✅ checked |
| `sq2` (`(a-b)² ≥ 0`, via `pow_two_nonneg`) | ✅ checked — Leanstral's Mathlib lemma choice is current (no name drift) |
| `len_app` (list length) | ❌ one-shot near-miss — correct `induction`; `simp` left a trivial residual `a+b+1 = a+1+b` |

**Retry-with-error loop — validated.** One round of feeding Lean's `unsolved goals` error back to `labs-leanstral-1-5` produced a correct fix: it diagnosed "an arithmetic equality that needs `omega` or `ring`" and returned `… simp [List.length, ih] ; omega` (383 tok), where `omega` decides the residual linear-integer goal.

**Net:** nonlinear arithmetic (**the demo class**) kernel-checks **2/2 one-shot**; the inductive/list class is **one-shot-miss → one-retry-fix**.

**Implications:**
- The **demo class needs no retry** — generation + kernel-check both one-shot. Build the demo as specced.
- The **broader/production classes (inductive/list) require the Layer-3 retry-with-error loop**, now validated to converge in one round (Leanstral's stated strength — iterating against the compiler). Required for production, not for the demo.
