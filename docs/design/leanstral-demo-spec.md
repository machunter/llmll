# Leanstral Demo — Minimal Vertical Slice (three-lite)

> **Version:** Rev 0 — demo spec derived from the 2026-07-04 Step-0 empirical validation (see `leanstral-integration-scope.md §8`).
> **Status:** Proposed (Rev 0) — compiler-engineer-ready. A *demo*, not the production LEAN-GA rebuild: one obligation end-to-end, scoped to sidestep the whole-translator faithfulness review.
> **Date:** 2026-07-04
> **Implements:** the "build a demo first" recommendation in `leanstral-integration-scope.md §6`; Layer-1/2 plan §7.
> **Prerequisites:** a Leanstral endpoint (`labs-leanstral-1-5`, Labs-enabled, key in `LLMLL_LEANSTRAL_API_KEY`); a Lean 4 + **Mathlib** project for kernel-checking (all Step-0 proofs use Mathlib tactics); the anti-laundering guard (shipped v0.14.7); Gap B (`isNonLinear` `EOp`, shipped v0.14.7).

---

## 1. Goal

One obligation flows **end-to-end**, showing the C-property: an agent authors code whose obligation escapes QF-LIA → LLMLL translates a **faithful** Lean theorem → `labs-leanstral-1-5` produces a proof → the **Lean kernel (+ Mathlib) checks it** → LLMLL records `verified-lean` with a **kernel-checkable certificate** a third party can independently re-verify. The demo ends at `verify`/`--trust-report`.

## 2. Demo obligation (chosen to be faithful-by-inspection)

`(def square [n: int] -> int (post (>= result 0)) (* n n))` — the Step-0-proven case.
- **Real QF-LIA escape:** `n*n` is nonlinear → Z3 cannot discharge it in the decidable fragment → currently lands `erBodyFallback → asserted`.
- **Faithful with zero review burden:** `*` agrees between Haskell codegen and Lean (no floor/trunc landmine — unlike `/`/`mod`); `result` is bound to the body; no partial function; no free var.
- **Empirically proved (Step-0):** `theorem square (n result : Int) (h : result = n*n) : result ≥ 0 := by rw [h]; nlinarith`.

Do **not** use a `/`/`mod` obligation for the demo — that hits the floor-vs-truncated landmine (`leanstral-integration-scope.md §7`) and needs `Int.fdiv`/`Int.fmod` first.

## 3. The three-lite slice

Each layer is scoped to *this obligation shape* — a fraction of the production rebuild.

### Layer-1-lite — translate the OBLIGATION (`LeanTranslate.hs`)
Widen `translateObligation` to receive `(name, params, ret, contract, body)` (caller `processPH`, `Main.hs:~1707`). Emit, with `result` **bound to the body**:
```
import Mathlib.Tactic
theorem <name> (p₁ : T₁) … (result : Tret) (h_body : result = ⟦body⟧) : ⟦post⟧ := by
  sorry
```
`⟦·⟧` via a minimal `bodyToLean` that handles QF-LIA + integer `*` faithfully and returns `Unsupported` for **everything else** (`/`, `mod`, `^`, lists, matches) — the demo needs only the arithmetic path. Mirror the body-VC LHS `FixpointEmit.hs:701-706`. **Fail-closed** on any residual free var. (This is the Layer-1 core change — bind `result` — but a fraction of the full escape-class table; the rest is production work.)

### Layer-2-lite — route the real body (`Main.hs`, `HoleAnalysis.hs`)
Today the pipeline consumes only body-position `?proof-required` holes (`Main.hs:1682-1690`); `square`'s nonlinear body lands `addBodyFallback` (`FixpointEmit.hs:656`) → `erBodyFallback` and never reaches it. Add **one targeted route:** under `--leanstral`, for a function in `erBodyFallback` whose fallback cause is nonlinear arithmetic, hand `(name, params, ret, contract, real body)` to `runLeanstralPipeline`. (Gap B already ensures operator-form nonlinearity is detected.) The full worklist rework (Gap A) is production; this one route is the demo.

### Layer-3 — call, check, record (`MCPClient.hs`, evidence)
1. **Call (T-B — model produces the proof):** `POST https://api.mistral.ai/v1/chat/completions`, model `labs-leanstral-1-5`, key from `LLMLL_LEANSTRAL_API_KEY` (env-only, never logged). This is a **direct chat-completions call**, *not* the `lean-lsp-mcp` server (which is a checker, not a prover — `leanstral-integration-scope.md §4`).
2. **Extract:** the response is **prose + a ` ```lean ` fenced block** — parse out the fenced code (do NOT treat the whole content as the proof).
3. **Check (the kernel step):** write the theorem + extracted proof to a `.lean` file in the Mathlib project; run `lake env lean <file>`. Success iff exit 0, no diagnostics of severity error, and **no `sorry`/`admit`** (the shipped `sanitizeProof` guard already rejects a `sorry` proof before it can be accepted — reuse it).
4. **Record:** on a clean check, mark the obligation `verified-lean` and persist the checked proof (the `.lean` text) as the **kernel-checkable certificate** in the trust report / proof artifact. Fail-closed otherwise (leave at `asserted`; optionally one retry feeding Lean's error back to Leanstral — its actual strength).

## 4. Config surface
- `--leanstral` flag (real mode; absence = off).
- `LLMLL_LEANSTRAL_API_KEY` (env; never a flag or log line).
- `--leanstral-model` (default `labs-leanstral-1-5`), `--leanstral-lean-project <path>` (the Mathlib project used for checking), `--leanstral-timeout`.

## 5. Demo end-state (the showable CLI)
```
$ llmll verify square.llmll --leanstral --trust-report
  square: post (>= result 0) — nonlinear, outside QF-LIA
    → Leanstral: proof found (rw [h]; nlinarith)
    → Lean kernel + Mathlib: CHECKED ✓
  square: verified-lean   (certificate: square.verified.lean)
```
Contrast with the same run without `--leanstral` (the obligation sits at `asserted`). That delta *is* the C-property demo.

## 6. Why no professor adequacy review (for the demo)
The production blocker is faithfulness review of the *whole* translator across every escape class. The demo's single obligation is multiplication-only + `result`-bound + no partial function, so its translation is faithful **by inspection** — no review gate. The review returns only when the escape-class table grows (production).

## 7. Pre-build validation (run FIRST — closes the one open risk)
Step-0 *generated* proofs but did not kernel-check them (no Lean toolchain in that environment). Before compiler work, **confirm the generated proofs actually compile**:
1. Install Lean 4 (`elan`); create a project with Mathlib (`lake new proofcheck`, add `mathlib` to the lakefile, `lake exe cache get`).
2. Drop the three Step-0 proofs (`square`, `sq2`, `len_app`) into `.lean` files with `import Mathlib.Tactic`.
3. `lake env lean <file>` each — exit 0, no errors, no `sorry` = kernel-checked.
4. Report which compile as-is. (Leanstral's strength is iterating against compiler errors, so a check-and-retry loop should push any that miss on the first shot.)
This is experiment-lead/infra; it de-risks Layer-3 before a line of compiler code.

## 8. Effort + risks
**Effort:** ~3–4 focused days (L1-lite ~1d; L2-lite ~0.5d; L3 call+extract+check+evidence ~1.5–2d) + the Mathlib-project setup. Versus the 5–8-day review-dominated production Layer-1/2.

**Risks:**
1. **Generated proof may not compile one-shot.** *Bite:* the kernel check catches it (fail-closed); a retry-with-error loop mitigates. §7 validation sizes this first.
2. **Mathlib in the trusted base.** The certificate is checkable, but the checker is Lean kernel **+ Mathlib**, not a bare kernel. Auditable, but state it — it's the honest trusted base for the C-property claim.
3. **Data privacy (Labs endpoint).** Labs models carry different data-usage terms; fine for toy demo theorems, a governance decision before real obligations. Flagged in `leanstral-integration-scope.md §8`.
4. **Direct-API vs MCP.** The demo uses the chat endpoint for generation + a local Lean project for checking — which *is* the trust-correct T-B split (untrusted model searches; kernel checks). The `lean-lsp-mcp` route is a later refinement.
