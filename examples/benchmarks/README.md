# benchmarks: holed seed programs for tests and experiments

Three small programs, each a contracted function whose body is a hole for an
agent (or a candidate generator) to fill. They are test inputs, not demos: the
compiler test suite and the experiment harnesses read them by path, so rename
or edit them only together with their consumers.

| File | Function | Contract | Hole |
|---|---|---|---|
| `b1-withdraw.llmll` | `withdraw [balance: int, amount: PositiveInt]` | pre `balance >= amount`, post `result = balance - amount` | `?body_impl` (whole body) |
| `b3-safe-first.llmll` | `safe-first [xs: list[int]]` | post `result >= 0` | `?success_impl` in the `Success` arm of a `list-head` match |
| `b5-double.llmll` | `double [n: int]` | post `result = n + n` | `?body_impl` (whole body) |

## Consumers

- `compiler/test/Spec.hs`, "Phase 4" golden tests: B1 checks that the
  candidate generator proposes `(- balance amount)` and treats the
  `PositiveInt` parameter as int-like; B3 checks that the body parses as a
  two-arm match. (The B5 test calls the generator directly and does not read
  the file.)
- Experiment manifests: `experiments/int-pre/manifest.json`,
  `experiments/cdp-0/manifest.json` and `experiments/cdp-perf-0/manifest.json`
  list all three as corpus entries.

## What `verify` prints

Each seed is unfilled, so its one contract is assumed, not proved. Reproduced
on llmll 0.26.5:

```
$ llmll verify ./b1-withdraw.llmll
   body-fallback: withdraw
   Running liquid-fixpoint ...
⚠️  ./b1-withdraw.llmll — SAFE (liquid-fixpoint), partial: 0 of 1 contracted functions proved; 1 assumed, not proved: withdraw
   (--strict-verified-core fails on assumed functions)
```

`b3-safe-first.llmll` and `b5-double.llmll` print the same `partial: 0 of 1`
verdict. All three exit 0. `llmll holes` lists the open hole:

```
$ llmll holes ./b1-withdraw.llmll
WARNING: def 'withdraw' body is entirely a single named hole (?body_impl). Prefer targeted holes over wholesale stubs.
./b1-withdraw.llmll — 1 holes (0 blocking)
  [ info] ?body_impl in def withdraw
```
