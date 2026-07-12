# total-recursion — termination discharged with `(decreases …)`

Recursion in LLMLL verifies at **partial** correctness by default (a
non-terminating body vacuously satisfies its post, so the trust report flags
the cycle `termination_unverified`). A `(decreases e)` measure upgrades the
claim to **total** correctness: the verifier discharges well-foundedness
(`pre ⟹ e ≥ 0`) and strict descent at every recursive call site, and the
discharged function is admitted by `--strict-verified-core`.

| File | What it demonstrates |
|---|---|
| `sum-to.llmll` | `(decreases n)` discharges: SAFE, **no** `termination_unverified` flag, strict-core admits the recursion |
| `sum-to-bad-measure.llmll` | same correct body, wrong measure (`(- 100 n)` grows as `n` shrinks): rejected on the dedicated **measure-not-decreasing** channel — distinct from a postcondition refutation |

## Commands (outputs reproduced against the shipped binary)

**Total: the measure discharges, the termination flag is gone.**
```bash
llmll verify ./sum-to.llmll --strict-verified-core --trust-report
```
```
   body-faithful: sum-to
   call-pre obligations: sum-to
   Running liquid-fixpoint ...
✅ ./sum-to.llmll — SAFE (liquid-fixpoint)
Trust Report
────────────────────────────────────────────────────────────
  sum-to:
    pre:  asserted  |  post: verified (liquid-fixpoint)
    ↳ calls sum-to (pre: asserted, post: verified (liquid-fixpoint))
────────────────────────────────────────────────────────────
Summary:
  verified:         1
```
Exit 0. No `Termination-unverified` section: the `(decreases n)` measure was
proven, so the recursion carries a total-correctness verdict and passes the
strict gate.

**Wrong measure: rejected on the termination channel, not the post channel.**
```bash
llmll verify ./sum-to-bad-measure.llmll
```
```
error: decreases-condition of 'sum-to' not verified (constraint #0)
error: descent-condition of 'sum-to' not verified (constraint #4)
```
Exit 1. The body is byte-identical to `sum-to.llmll` and still computes the
right answer — what fails is the *termination evidence*: `(- 100 n)` increases
along the recursion, so strict descent is disproved and the trust report
stamps the function `measure-not-decreasing`. The verifier distinguishes "your
function is wrong" (refuted) from "your termination measure is wrong"
(measure-not-decreasing).

## The discriminative point

A wrong measure on a *correct* body is caught, and caught on the right
channel. An agent cannot launder a non-terminating (or unproven-terminating)
recursion into the total tier: no measure → `termination_unverified` (partial),
bad measure → `measure-not-decreasing` (hard exit 1), discharged measure →
total. See `LLMLL.md` §4.2 and the §5.3.5 matrix row for recursive `EApp`.
