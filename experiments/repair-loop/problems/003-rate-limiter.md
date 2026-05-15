# 003 — Token Bucket Rate Limiter

> **Source:** Adapted from `docs/design/language-comparison-experiments.md:354-401`.
> **Class:** State-machine with bounded counter and nonlinear refill arithmetic.
> **H3 expectation:** LLMLL-disadvantaged or neutral. The dominant invariant (token refill as a function of elapsed ticks) involves multiplication of two non-literal integers, which escapes QF-LIA per `LLMLL.md §5.3.5`. LLMLL's strongest verification path is blocked on the refill computation; bounds-on-tokens contracts auto-discharge but are also straightforward in Python and Go. Predicted in detail at `docs/design/phase3-problem-shape-audit.md` §"003 — Token Bucket Rate Limiter".

## Specification

Build a deterministic token-bucket rate limiter. The core is pure (ticks are passed in; no ambient time).

### Required State

- Capacity (positive integer).
- Current token count (integer, in `[0, capacity]`).
- Refill rate (non-negative integer; tokens per tick).
- Last observed tick (integer; the tick at which state was last updated).

### Required API

- `new_limiter(capacity, refill_rate)` — creates a limiter with `tokens = capacity` (initially full), `last_tick = 0`. Rejects `capacity <= 0` and `refill_rate < 0`.
- `allow(state, tick)` — returns `(new_state, allowed: bool)` for one request at `tick`. Before deciding, refills tokens by `(tick - last_tick) * refill_rate`, capped at `capacity`. If the post-refill count is at least 1, allows the request and consumes one token; otherwise denies and leaves the token count at the refilled value. `last_tick` advances to `tick` regardless of allow/deny.
- `tokens(state)` — returns the current token count.

### Behavioral Requirements

- Capacity must be positive (`> 0`).
- Refill rate must be non-negative (`>= 0`).
- Ticks are monotonically non-decreasing inputs (the harness will not call `allow` with a tick less than `last_tick`; behavior under such input is implementation-defined and not tested).
- Before each request, tokens refill by `(tick - last_tick) * refill_rate`.
- Tokens never exceed capacity (post-refill is capped).
- A request is allowed when at least one token is available (post-refill).
- Allowed requests consume exactly one token.
- Denied requests consume no token.
- Calls at the same tick do not refill (delta = 0).

### LLMLL Assurance Requirements (Suggested)

The LLMLL target should express at least the following:

- `pre new-limiter`: `(and (> capacity 0) (>= refill-rate 0))` — QF-LIA, auto-discharged.
- `post allow`: `(and (>= (tokens result.0) 0) (<= (tokens result.0) capacity))` — QF-LIA bounds on token count, auto-discharged.
- Refill multiplication `(* (- tick last-tick) refill-rate)`: this clause is nonlinear (product of two non-literal integers) and escapes QF-LIA per `LLMLL.md §5.3.5`. It should be expressed as a `post` clause and marked `?proof-required`, OR covered by `(check ...)` blocks with explicit `(weakness-ok ...)` suppression per `LLMLL.md §4.5`. Silent assertion is an anti-pattern.
- Same-tick-no-refill invariant: if encoded with an explicit tick-equality guard (`(= last-tick tick) → (= (tokens result.0) (- (tokens state) 1))` for the allowed case), the obligation is QF-LIA-expressible and auto-discharges.

## Harness Tests

Tests live under `experiments/repair-loop/testkits/003-rate-limiter/<target>/`.
Black-box tests should enforce:

- A limiter with `capacity=2, refill_rate=1` allows two same-tick requests at tick 0 and denies the third (`allowed=False`).
- After exhausting tokens at tick 0, a call at tick 1 with `refill_rate=1` refills and allows the request.
- A large tick jump (e.g., tick `1_000_000`) refills tokens but the count never exceeds `capacity`.
- A denied request at the same tick as a previously exhausting allow does not change the token count from before the call (no refill, no consumption).
- Three same-tick calls on a `capacity=2, refill_rate=1` limiter produce `(allowed=True, tokens=1)`, `(allowed=True, tokens=0)`, `(allowed=False, tokens=0)` — no refill happens between calls.

## QF-LIA Classification

- **Inside QF-LIA:** capacity / token-count bounds; same-tick-no-refill invariant when encoded with an explicit tick-equality guard; allowed-request token decrement (linear arithmetic).
- **Outside QF-LIA / nonlinear:** the refill computation `(* (- tick last_tick) refill_rate)` is a product of two non-literal integers and is outside the v0.10.6 SMT fragment per `LLMLL.md §5.3.5`. Either mark `?proof-required` or use `(weakness-ok ...)` suppression per `LLMLL.md §4.5`; both are valid surfaces under the trust ladder.

H1 / H2 / H3 expectations: the refill nonlinearity is the H3 stressor — LLMLL's body-faithful SMT path cannot discharge it, so the trust report will floor at `asserted` (or `?proof-required` if explicitly marked) on the dominant invariant. Python's `pyright` and Go's type checker have no nonlinear arithmetic story either, so they are not at a disadvantage relative to LLMLL on this problem. The audit predicts LLMLL's H1-Assurance signal on this problem to be neutral-or-disadvantaged relative to Python / Go behavioral test pass rate; see `docs/design/phase3-problem-shape-audit.md` §"003 — Token Bucket Rate Limiter" for sharp falsifiable rate bands.
