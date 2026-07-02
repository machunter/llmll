# session-pay — Verification Scope

What the compiler **proves** versus what is **trusted**, for the connected demo. (Unlike a crypto-bearing RFC demo, this scenario has *no* opaque/`asserted` core — every obligation lands in QF-LIA, so the solver is the catcher throughout.)

| Function | Obligation | Status | Basis |
|---|---|---|---|
| `step` | RFC 793 §3.2 legal-successor relation (state-safety) | **proven** | body-faithful VC, liquid-fixpoint (QF-LIA) |
| `debit` | `result = balance - amount ∧ result >= 0` (payment) | **proven** | body-faithful VC, liquid-fixpoint (QF-LIA) |
| `open-and-pay` | legal session-pay relation: `result = Paid(balance - amount)` iff an `ESTABLISHED`-reaching transition **and** `balance >= amount`; else `result = Rejected(0)` | **proven, through the `step` and `debit` call edges** | body-faithful VC (outcome constructed natively, discharged by constructor equality / injectivity) + assume-guarantee on `step.post` / `debit.post`; `debit.pre` discharged at the call site (funds guard ⊕ `Word` bound) |
| `amount: Word` | `0 <= amount <= 65535` | **proven** (refinement-typed parameter) | discharges `debit`'s `amount >= 0` |

**Trusted (TCB):** the LLMLL compiler, liquid-fixpoint, and z3 — same as any LLMLL `verify`. Nothing demo-specific is assumed.

**Scope honesty:**
- **Real enum states/events AND a real outcome sum.** `ConnState` and `Event` are real nullary-enum sum types, matched and compared as values (verified). The multi-outcome RESULT is a real payload-bearing sum, `PayOutcome` (`Paid(int)` / `Rejected(int)`), **constructed natively**: the post discharges by constructor equality and refutes by injectivity, into Z3's non-recursive datatype theory. No int sentinel remains — `Rejected(0)` is a first-class constructor value, distinct from every `Paid(n)`.
- **Single module.** `step`/`debit` are re-authored in-file rather than cross-module-imported (cross-module verified composition is a tracked gap), so the entire composition stays body-faithful.
- **Bounded state subset.** The state machine is the RFC 793 connection-setup subset (5 states × 6 events), well under the path-split ceiling.

**Claim:** the implementation provably cannot pay before the session is `ESTABLISHED`, cannot overdraw, and cannot pay an out-of-range amount — three safety properties proven simultaneously on one trust-report.
