# Cascading-refinement demo — a live run

Observed transcript of running this demo end to end against `llmll 0.14.16`. It answers a
specific confusion: why a `refine` fill body names functions that have no visible definition and
no `?` decorator. Runbook and full command sequence are in [`README.md`](README.md); this file
records what the run actually produced.

## The one idea

A **hole** is a body-position node. Its governing contract lives on the *enclosing def*, not on
the hole. Filling a hole replaces the body at one JSON pointer.

- `patch` fills a hole with a final body.
- `refine` fills a hole with a body **and** spawns new contracted sub-holes that body calls,
  atomically. That is how one problem is decomposed into a tree without any single agent seeing
  the whole thing.

Every call site is undecorated — a call to a not-yet-implemented (but contracted) function looks
identical to a call to a finished one. That is deliberate: the verifier consumes the callee's
**contract**, never its body, so the call is sound the moment the callee is spawned with a `post`.
When you later fill that callee, its body goes `?impl → <expr>` and the call site does not change.

## Part 1 — the cascade (observed, matches the README table)

Every intermediate state verified `SAFE`. The hole frontier fanned out under `refine`, then
contracted under `patch`:

| # | op | target | `statements` | verify | holes |
|---|---|---|---|---|---|
| — | start | — | 1 | SAFE | **1** |
| 1 | refine `admit-byte`    | `/statements/0/body` | 3 | SAFE | **2** |
| 2 | refine `authenticated` | `/statements/1/body` | 5 | SAFE | **3** |
| 3 | refine `ordered`       | `/statements/2/body` | 7 | SAFE | **4** |
| 4 | patch  `mac-matches`   | `/statements/3/body` | 7 | SAFE | **3** |
| 5 | patch  `handshake-up`  | `/statements/4/body` | 7 | SAFE | **2** |
| 6 | patch  `seq-fresh`     | `/statements/5/body` | 7 | SAFE | **1** |
| 7 | patch  `length-sound`  | `/statements/6/body` | 7 | SAFE | **0** |

Frontier: `1 → 2 → 3 → 4 → 3 → 2 → 1 → 0`. Zero hole nodes remain in the AST.

## The merged program — what the seven edits add up to

```lisp
(def-shell admit-byte    … -> int  = (if (and (= (authenticated computed expected hs_state) 1) (= (ordered seq last claimed received) 1)) 1 0))
(def-shell authenticated … -> int  = (if (and (= (mac-matches computed expected) 1) (= (handshake-up hs_state) 1)) 1 0))
(def-shell ordered       … -> int  = (if (and (= (seq-fresh seq last) 1) (= (length-sound claimed received) 1)) 1 0))
(def-shell mac-matches   … -> int  = (if (= computed expected) 1 0))
(def-shell handshake-up  … -> int  = (if (= hs_state 2) 1 0))
(def-shell seq-fresh     … -> int  = (if (> seq last) 1 0))
(def-shell length-sound  … -> int  = (if (<= claimed received) 1 0))
```

`02-refine-authenticated.sexp` showed `(mac-matches computed expected)` with no definition in
sight. Here `mac-matches` is a real function and `authenticated` calls it with byte-identical
text. Between step 2 and step 4 only `mac-matches`'s body changed
(`?impl → (if (= computed expected) 1 0)`); the call site was stable throughout. That stability
*is* the soundness — the call always reasoned about the contract, which was present from the spawn.

## Part 2 — the two gates against a cheating decomposition

An agent invents both a sub-contract and its filling, so two rejections keep it honest. Each ran
on its own clean copy; the base was left at 1 hole (no partial write):

- **Vacuous** (`08-refine-vacuous.json`) → `PatchApplyError`:
  *"spawned sub-contract 'authenticated' is vacuous — a trivial (identity/constant) body already
  satisfies it … strengthen the contract."* No progress by splitting a hard goal into an empty one.
- **Orphan** (`09-refine-orphan.json`) → *"spawned def 'audit-log' is not referenced by the fill
  body."* A `refine` cannot introduce code the decomposition never calls.

## Two operational footnotes surfaced by running it

1. **Result-code split.** The orphan rejection surfaces under the `PatchAuthError` result code, not
   `PatchApplyError`. Intentional: `compiler/src/LLMLL/PatchApply.hs` documents `PatchAuthError` as
   *"invalid/expired/scope-violation"*, and orphan is a scope violation. So vacuity → apply-error,
   orphan → auth/scope-error. Reclassifying scope under apply-error would be a one-liner if the
   split is undesirable.
2. **A rejected `refine` does not release the checkout lock.** Sound for a whole-file
   compare-and-swap module, but if you script several attempts against one file, release or
   re-checkout between tries — otherwise the next checkout returns *"already checked out"*.

*Run on a throwaway copy of `base.ast.json`; the tracked demo files were not modified.*
