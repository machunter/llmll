# ERC-20 Token Benchmark — Walkthrough

> **Goal:** Demonstrate end-to-end specification-driven development using the ERC-20 token standard as source material. See `EXPECTED_RESULTS.json`'s `future_work` note for what's still aspirational.

---

## 1. From External Spec to LLMLL Contracts

The ERC-20 token standard (EIP-20) defines six core functions:

| ERC-20 Function | LLMLL Contract | Type |
|---|---|---|
| `totalSupply()` | `(post (>= result 0))` | Non-negative invariant |
| `balanceOf(owner)` | `(post (>= result 0))` | Non-negative balance |
| `transfer(to, amount)` | `(pre (>= amount 0))` + conservation | Safety + invariant |
| `approve(spender, amount)` | `(pre (>= amount 0))` | Safety precondition |
| `allowance(owner, spender)` | `(post (>= result 0))` | Non-negative allowance |
| `transferFrom(from, to, amount)` | `(pre (and (>= amount 0) (>= allowance amount)))` + conservation | Safety + invariant |

### Key Design Decision: Conservation Invariant

The transfer conservation postcondition `(= (total-supply result) (total-supply state))` *states* that no tokens are created or destroyed during a transfer — a pure integer arithmetic constraint, in principle expressible in QF-LIA. Whether the compiler can actually *discharge* that statement, rather than just accept it as an unproven assertion, depends on how `transfer` is implemented — see the Verification-Scope Matrix below and the Honesty Note for why this benchmark's current implementation can state it but not prove it.

---

## 2. Verification-Scope Matrix

| ERC-20 property | Verification level | Why |
|---|---|---|
| `total-supply` non-negative | **Verified** (QF-LIA) | Integer comparison, given `(pre (>= state 0))` |
| `balance-of` non-negative | **Verified** (QF-LIA) | Integer comparison, given `(pre (>= state 0))` |
| `allowance` non-negative | **Verified** (QF-LIA) | Integer comparison |
| `transfer` conservation | **Asserted** (stated, not discharged) | See Honesty Note |
| `transfer` non-negative amount | **Asserted** (stated, not discharged) | See Honesty Note |
| `approve` non-negative amount | **No contract** (precondition only) | A precondition alone has no effective post-level — this is current, correct behavior, not a gap |
| `transfer-from` conservation | **Asserted** (stated, not discharged) | See Honesty Note |
| `transfer-from` allowance check | **Asserted** (stated, not discharged) | See Honesty Note |
| Map key membership / absence | **Asserted** | Outside decidable fragment |
| Transfer-to-self edge case | **Tested** (QuickCheck) | Conditional logic |

### Honesty Note

Map key membership (e.g., "does the balance map contain this address?") is **outside the decidable fragment** of QF-LIA. We honestly classify this as **Asserted** rather than claiming it as proven. The transfer-to-self edge case involves conditional branching that is better tested via QuickCheck than proven via SMT.

**`transfer`/`transfer-from`'s conservation and amount properties are stated but not solver-discharged**, and this isn't a fixable annotation gap: this benchmark models the entire ledger as a single bare `int` (see `total-supply`/`balance-of`'s bodies, both literally `(var state)`), `transfer`'s body is a no-op stub, and its conservation postcondition calls `total-supply` only *inside the post clause* — the compiler's assume-guarantee call-edge machinery composes over calls in a function's *body* (the way [`examples/payments-core/transfer.llmll`](../payments-core/transfer.llmll) actually calls `debit` in its body), not calls that appear only in a postcondition. `transfer`/`transfer-from` are `def-shell` (not `def`) specifically so they're permitted to call `total-supply`/`allowance` at all — `def`'s strict-core admissibility check requires a callee's *persisted* verified evidence, which can't exist yet for a same-file callee at type-check time. Getting `transfer` itself to `verified` would require a materially richer benchmark — real per-account balance state and a body that actually moves value between two accounts — not a fixture patch. See `EXPECTED_RESULTS.json`'s `future_work` note.

---

## 3. Running the Benchmark

### Parse and type-check the skeleton:
```bash
llmll check examples/erc20_token/erc20.ast.json
```

### Run spec coverage on the filled version:
```bash
llmll verify examples/erc20_token/erc20_filled.ast.json --spec-coverage
```

Expected output:
```
Spec Coverage Report
────────────────────────────────────────────
  Functions with contracts:     6 / 6   (100%)
    Verified:                   0
    Contract-checked:           0
    Tested:                     0
    Asserted:                   6
────────────────────────────────────────────
  Effective coverage: 100% (6/6)
```

> **Note:** "Asserted: 6" reflects that verification levels come from the `.verified.json` sidecar. Without running `liquid-fixpoint`, all contracts default to Asserted.

> [!IMPORTANT]
> **Asserted vs. Verified:** The live `--spec-coverage` output above shows all 6 functions as **Asserted** because `--spec-coverage` reads whatever `.verified.json` sidecar already exists on disk, and a bare `--spec-coverage` run doesn't populate one. The genuinely achievable state — confirmed via `llmll verify erc20_filled.ast.json --trust-report`, which does run `liquid-fixpoint` fresh — is **`verified: 3` (`total-supply`, `balance-of`, `allowance`), `asserted: 2` (`transfer`, `transfer-from` — stated but not solver-discharged), `no_contract: 1` (`approve` — precondition-only, no effective post-level)**, matching `EXPECTED_RESULTS.json`'s `expected_trust_report`. This is *not* "6 verified once fixpoint runs" — `transfer`/`transfer-from` structurally cannot reach `verified` with this benchmark's current single-int ledger model; see `EXPECTED_RESULTS.json`'s `future_work` note.

### Run weakness check:
```bash
llmll verify examples/erc20_token/erc20_filled.ast.json --weakness-check
```

No weaknesses expected — all functions have meaningful, non-trivially-satisfiable contracts.

---

## 4. Strengthening Workflow

The benchmark demonstrates the iterative strengthening cycle:

1. **Start with skeleton** (`erc20.ast.json`) — 6 holes, all contracts specified
2. **Fill implementations** (`erc20_filled.ast.json`) — resolve all holes
3. **Verify** — `liquid-fixpoint` discharges the properties that are within its reach (3 of 6 functions reach `verified`; see §2's Verification-Scope Matrix for why `transfer`/`transfer-from`'s conservation invariants stay `asserted`)
4. **Weakness check** — confirm contracts are non-trivial
5. **Spec coverage** — confirm 100% effective coverage

If `--weakness-check` finds a trivially satisfiable contract, the downstream obligation miner suggests strengthening postconditions. This cycle continues until all contracts are meaningful.

---

## 5. Files

| File | Description |
|------|-------------|
| `erc20.ast.json` | Skeleton with 6 holes + full contract suite |
| `erc20_filled.ast.json` | Filled version with implementations |
| `EXPECTED_RESULTS.json` | Frozen ground truth for CI gate |
| `WALKTHROUGH.md` | This file |
