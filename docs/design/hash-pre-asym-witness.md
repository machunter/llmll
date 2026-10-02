---
name: hash-pre-asym-witness
title: "HASH-PRE-ASYM witness: a stale caller record passes --strict-verified-core across modules"
status: "MEASURED 2026-10-02 on v0.27.1 (60b2a9e). Confirms hash-pre-asym-review.md H1; adds one finding (F2). Input to hash-pre-asym-proposal.md Rev 1."
date: 2026-10-02
author: compiler-engineer
consumers: [language-team, professor, user]
related: "hash-pre-asym-proposal.md Rev 0; hash-pre-asym-review.md"
---

# HASH-PRE-ASYM witness

## 1. What was tested

The professor's review (H1) claimed that the per-function evidence hash plus the §4.4.3 meet do not keep a caller's record correct when a callee's contract changes and the callee alone is re-proved. This record builds that case on v0.27.1 instead of arguing it.

The case uses source edits, not a checker change, because one binary cannot show an augmentation. A source edit that strengthens a callee `pre` gives the caller the same new call-site obligation a pre augmentation would (the C2 shape). A source edit that weakens a callee `post` removes an assumption the caller's proof used.

## 2. The program

Three modules in one directory. `c` imports `a`, and `a` imports `b`.

```
;; b.llmll, step 1
(def g [x: int] -> int (pre (>= x 0)) (post (= result x)) x)

;; a.llmll
(import b)
(open b)
(def f [] -> int (post (= result 1)) (g 1))

;; c.llmll
(import a)
(open a)
(def h [] -> int (post (= result 1)) (f))
```

## 3. Results

**Step 1.** `llmll verify` on `b`, then `a`, then `c`: each prints SAFE. `a` reports `call-pre obligations: f`.

**Variant 1: the callee's pre is strengthened.** `b.llmll` becomes `(pre (>= x 5))`, so `f`'s call `(g 1)` now violates it. Only `b` is re-verified (SAFE). `a.llmll.verified.json` is byte-identical to its step-1 copy.

| Command | Result |
|---|---|
| `llmll verify c.llmll` | SAFE, exit 0 |
| `llmll verify c.llmll --strict-verified-core` | SAFE |
| `llmll verify c.llmll --trust-report` | `a.f: post: verified`; `verified: 3`; no warning on `f` |
| `llmll verify a.llmll --trust-report --strict-verify` (control) | `error: call-site precondition of 'g' not satisfied in 'f'`; `f` is marked refuted |

**Variant 2: the callee's post is weakened.** `b.llmll` becomes `(pre (>= x 0)) (post (>= result 0))`, so `f`'s post `(= result 1)` no longer follows. Only `b` is re-verified (SAFE).

| Command | Result |
|---|---|
| `llmll verify c.llmll --strict-verified-core` | SAFE, exit 0 |
| `llmll verify a.llmll` (control) | `error: body verification of 'f' failed` |
| `llmll verify c.llmll --strict-verified-core`, after the failed control | SAFE |

## 4. Findings

**F1. H1 is confirmed, on both channels a caller reads from a callee.** A caller's stored `verified` survives a change to the callee's `pre` (an obligation it must prove) and to the callee's `post` (an assumption it used). `--strict-verified-core` on an importer passes in both variants. In variant 1, the built program would reach `g` with `x = 1` and stop on the runtime `pre` assertion. The cause is the one the review named: `canonicalDefEvidenceHash` covers only the function's own parts, and the meet passes because `g` is `verified` again under its new hash.

**F2. A failed `verify` leaves the old `verified` records in place.** `compiler/app/Main.hs` writes the sidecar only on a SAFE result (the `saveVerifiedWithAxioms` branch; every other result returns `Map.empty`). After `llmll verify a.llmll` reports `f` refuted, `a.llmll.verified.json` is unchanged and still says `f: verified`. So re-checking the caller does not correct what importers read, and the importer still passes `--strict-verified-core`. This is separate from the hash. Not persisting `refuted` is deliberate (the code comment calls a refuted verdict perishable), but keeping a positive record that the same run just contradicted is not covered by that reason.

**What does warn.** The sidecar-only trust report prints that its evidence "was NOT validated against a run of the VC emitter", and names `--strict-verify`. `--strict-verify` on the caller's own module finds the refutation. Neither of these reaches an importer's `verify` or `--strict-verified-core`.

## 5. Consequences for Rev 1

1. The professor's recommendation 1 (fold each direct callee's effective contract into the caller's hash) closes F1 in both variants. `f`'s hash would move when `g`'s contract changes, and `downgradeStaleVerifiedSidecar` would downgrade `f` on read in `c`.
2. F2 needs its own rule. With a dependency key, a source edit to the caller or a callee moves the caller's hash, so F2 no longer matters for source edits. It still matters for any change the key cannot see, such as a checker change shipped without an epoch increase: the new binary's own run refutes `f`, and the old `verified` record stays. A failed run is the one moment the system knows a record is wrong. Candidate rule: an UNSAFE run removes or downgrades the positive records of the functions it refuted.
3. The meet stays a display rule. It is not a freshness mechanism, and S1's clause "until the callee is re-proved" is withdrawn.
