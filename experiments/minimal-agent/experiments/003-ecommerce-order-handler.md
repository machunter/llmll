# Multi-Agent Microservice with Coordinated Delegation and Proof Obligations

**Difficulty:** ★★★
**v0.3 features exercised:** All v0.3 agent coordination features — `?delegate`, `?delegate-async`, `?scaffold`, `?proof-required :inductive`, `def-interface`, `def-invariant`, `on-failure`, `await` with `Result[t, DelegationError]`, multi-hole coordination, `DelegationError` variant matching

## Specification

Build an order processing system for an e-commerce platform. The system requires five coordinating agents:

- **Lead Agent** — owns the orchestration module, defines all interfaces and invariants
- **Inventory Agent (@inventory-agent)** — checks stock and reserves items
- **Pricing Agent (@pricing-agent)** — calculates totals with tax and discount rules
- **Payment Agent (@payment-agent)** — processes payments
- **Notification Agent (@notification-agent)** — sends order confirmations

**The Lead Agent writes the program.** It must:

1. Define these types:
   - `OrderItem`: a pair of item ID (string) and quantity (int)
   - `OrderStatus`: a sum type with variants `Pending`, `Confirmed`, `Failed` (each carrying a string reason)
   - `PriceBreakdown`: represents subtotal, tax, discount, and final total (all ints, in cents)

2. Define four `def-interface` contracts:
   - `InventorySystem`: `check-stock` (item ID → bool), `reserve-items` (list of OrderItem → `Result[string, string]`)
   - `PricingEngine`: `calculate-total` (list of OrderItem → int), `apply-discount` (int, string → int)
   - `PaymentProcessor`: `charge` (int, string → `Result[string, string]`)
   - `NotificationService`: `send-confirmation` (string, string → bool)

3. Write a `process-order` function that orchestrates the full flow:
   - Accept a list of `OrderItem`, a customer ID (string), and a discount code (string)
   - **Step 1 — Stock check:** Delegate to `@inventory-agent` asynchronously to check all items. Await the result. On failure, return `Failed "inventory unavailable"`.
   - **Step 2 — Pricing:** Delegate to `@pricing-agent` (blocking) to calculate the total. Apply the discount code. The `on-failure` fallback uses a flat 0% discount (no crash).
   - **Step 3 — Payment:** Delegate to `@payment-agent` (blocking) to charge the calculated total. On failure, return `Failed "payment declined"`.
   - **Step 4 — Notification:** Delegate to `@notification-agent` asynchronously. Do **not** await — fire and forget. If notification fails, the order still succeeds.
   - Return `Confirmed` with a confirmation message on success.

4. Write a `validate-order` function:
   - Accepts a list of `OrderItem`
   - `pre`: the list must not be empty
   - `pre`: every quantity must be positive
   - `post`: if the function returns `true`, then every item in the list has quantity ≥ 1
   - Mark the postcondition as `?proof-required :inductive` — it requires structural induction over the list to verify

5. Write a `calculate-tax` function:
   - Accepts a subtotal (int, in cents) and a tax rate (int, percentage points, e.g. 8 for 8%)
   - Returns the tax amount: `(subtotal * rate) / 100`
   - `pre`: subtotal ≥ 0 and rate ≥ 0
   - `post`: result ≥ 0
   - Mark the postcondition as `?proof-required` — it involves multiplication (non-linear arithmetic, beyond liquid-fixpoint's QF fragment)

6. Define `def-invariant` on the order processing state:
   - Total revenue (sum of all confirmed order amounts) must equal the sum of individual payments processed
   - No single order can appear in both `Confirmed` and `Failed` status

7. Include `check` blocks:
   - Processing an empty order list is rejected (tests the `pre` contract)
   - A single-item order with available stock goes through the full pipeline and reaches `Confirmed`
   - Payment failure after successful stock check + pricing results in `Failed`, not `Confirmed`
   - The fire-and-forget notification pattern does not block the order result
   - Tax calculation on a zero subtotal returns zero
   - Discount application never makes the total negative (returns 0 floor)

8. Use `?scaffold @template "ecommerce-order-handler"` for the initial module skeleton if the template exists; otherwise write from scratch
