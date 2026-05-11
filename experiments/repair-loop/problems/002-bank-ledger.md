# 002 — Bank Ledger

> **Source:** Adapted from `docs/design/language-comparison-experiments.md:297-344`.
> **Class:** Financial invariant. QF-LIA-dominant.
> **H3 expectation:** LLMLL's verification surface should produce a measurable advantage here.

## Specification

Build an in-memory bank ledger for accounts and transfers.

### Required State

- A mapping from account ID (string) to integer balance in cents.
- A transaction log recording successful transfers.

### Required API

- `create_ledger(accounts)` — creates a ledger from initial balances.
- `balance(ledger, account_id)` — returns the account balance or an explicit error.
- `transfer(ledger, from_account, to_account, amount)` — returns a new ledger or an explicit error.
- `total_balance(ledger)` — returns the sum of all account balances.

### Behavioral Requirements

- Account IDs are strings.
- Balances are non-negative integers (cents).
- Transfer amount must be positive.
- Transfer fails if either account is missing.
- Transfer fails if the source account has insufficient funds.
- Failed transfers do not modify balances or append a successful log entry.
- Successful transfers debit the source, credit the destination, and append one log entry.
- Total balance is preserved by every successful transfer.

### LLMLL Assurance Requirements (Suggested)

The LLMLL target should express at least the following:

- `pre` on `transfer`: `amount > 0`.
- `post` on successful `transfer`: total balance is unchanged.
- `post` on successful `transfer`: source decreases by `amount`, destination increases by `amount`.
- If map reasoning exceeds the current SMT fragment, use focused `check` blocks
  and explicit `?proof-required` markers rather than silent assertion. See
  `LLMLL.md §13.8`.

## Harness Tests

Tests live under `experiments/repair-loop/testkits/002-bank-ledger/<target>/`.
Black-box tests should enforce:

- Transfer 250 cents from `alice` to `bob` updates both balances.
- Transfer with insufficient funds returns an error and leaves the ledger unchanged.
- Transfer to missing account returns an error.
- Zero or negative transfer amount is rejected.
- A sequence of valid transfers preserves total balance.

## QF-LIA Classification

- **Inside QF-LIA:** balance non-negativity, transfer amount positivity,
  per-account balance arithmetic, conservation invariant on summed totals
  (linear over a fixed number of accounts).
- **Outside QF-LIA / map reasoning:** lookup invariants on arbitrary-size
  account maps, transaction-log uniqueness. These should be marked
  `?proof-required` per `LLMLL.md §13.8`.

H1/H2 expectations: the LLMLL target should expose more of the conservation
invariant as verified evidence than the controls, even when the underlying
correctness is identical.
