# ERC-20 Token Benchmark — Walkthrough

> **Version:** v0.6.0  
> **Goal:** Demonstrate end-to-end specification-driven development using the ERC-20 token standard as source material.

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

The transfer conservation postcondition `(= (total-supply result) (total-supply state))` asserts that no tokens are created or destroyed during a transfer. This is the strongest property in the benchmark — it's a pure integer arithmetic constraint expressible in QF-LIA.

---

## 2. Verification-Scope Matrix

| ERC-20 property | Verification level | Why |
|---|---|---|
| `total-supply` non-negative | **Proven** (QF-LIA) | Integer comparison |
| `balance-of` non-negative | **Proven** (QF-LIA) | Integer comparison |
| `transfer` conservation | **Proven** (QF-LIA) | Integer addition/subtraction |
| `transfer` non-negative amount | **Proven** (QF-LIA) | Integer comparison |
| `approve` non-negative amount | **Proven** (QF-LIA) | Integer comparison |
| `allowance` non-negative | **Proven** (QF-LIA) | Integer comparison |
| `transfer-from` conservation | **Proven** (QF-LIA) | Integer arithmetic |
| `transfer-from` allowance check | **Proven** (QF-LIA) | Integer comparison |
| Map key membership / absence | **Asserted** | Outside decidable fragment |
| Transfer-to-self edge case | **Tested** (QuickCheck) | Conditional logic |

### Honesty Note

Map key membership (e.g., "does the balance map contain this address?") is **outside the decidable fragment** of QF-LIA. We honestly classify this as **Asserted** rather than claiming it as proven. The transfer-to-self edge case involves conditional branching that is better tested via QuickCheck than proven via SMT.

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
    Proven:                     0
    Tested:                     0
    Asserted:                   6
────────────────────────────────────────────
  Effective coverage: 100% (6/6)
```

> **Note:** "Asserted: 6" reflects that verification levels come from the `.verified.json` sidecar. Without running `liquid-fixpoint`, all contracts default to Asserted.

> [!IMPORTANT]
> **Asserted vs. Proven:** The live `--spec-coverage` output shows all 6 functions as **Asserted** because verification levels are populated only after running `llmll verify` with `liquid-fixpoint`. The values in `EXPECTED_RESULTS.json` (`"proven": 6`) represent the **target state after verification** — the ground truth that the CI gate validates once fixpoint has run. Until then, all contracted functions default to Asserted.

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
3. **Verify** — `liquid-fixpoint` proves conservation invariants
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
