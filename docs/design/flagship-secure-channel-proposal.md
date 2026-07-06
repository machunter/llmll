# Flagship: Verified Secure-Channel Record Layer — design & status

> **Status:** Substrate validated; the auto-A-normalization gate (§6) is **SHIPPED (v0.14.11)** — ready for the large multi-agent build.
> **Date:** 2026-07-05. **Compiler:** `llmll 0.14.11`.
> **Purpose:** a *convincing* large example — not a toy. A real subsystem, decomposed into
> hundreds of contracted holes, built by orchestrated agents, verified as a whole at scale,
> where famous-bug invariants are load-bearing and the compiler refuses agents who reintroduce them.

---

## 1. Goal & the "convincing" bar

The existing examples read as toys (a skeptic shrugs at a verified `clamp`). The flagship must:
1. carry a **load-bearing, relational/cross-component invariant** no unit test could establish;
2. **decompose into many contracted holes** so multi-agent orchestration is genuine;
3. have a **caught-bug moment** — a plausible-but-wrong fill that *verifies-refuted* mid-build;
4. and be **large enough to be a believable real subsystem**, not a snippet.

## 2. Domain decision (record)

- **Blockchain — rejected.** Famous chain hacks (BEC overflow, The DAO reentrancy, Parity) are catastrophic but the failing *logic* is trivial (one-liners) → a verified version can't help looking like a toy; "caught the missing check" earns a shrug.
- **CPU — rejected.** Bitvector + temporal + structural; all unbuilt (`MachineInt`/QF-BV is P3).
- **Kernel — component-only.** The word overclaims vs seL4; a specific component (capability core / scheduler / allocator) could fit, but not "a kernel."
- **Network vs Encryption → Encryption.** Selection criterion (user's): *a headline bug LLMLL would have caught, honestly.* Encryption's famous bugs (**Heartbleed**, **goto-fail**) **look like correct code** — subtle, a careful engineer misses them — so "the compiler refused it" is impressive. Network's most famous incidents are policy/config/entropy/DDoS (Facebook 2021, YouTube/Pakistan hijack, Kaminsky) — not clean code invariants — or integer-overflow (Ping-of-Death, SACK Panic) which needs the unbuilt bitvector core.
- **Chosen anchor:** **Heartbleed** (CVE-2014-0160) first; **goto-fail** (CVE-2014-1266) queued as the second.

## 3. The honest ceiling

LLMLL verifies **first-order relational integer invariants** (QF-LIA + refinement types + SMT), **modularly**. It does **not** verify bignum/bitvectors/crypto-math/memory/recursive data structures. So the flagship verifies the **protocol-logic layer where the bugs live**, with cryptographic primitives **axiomatized as opaque contracts**. The scale ceiling is the **data/math axis, not size** (§5).

## 4. Validated substrate — `examples/heartbleed/`

`channel.llmll` — a 7-function record layer that **verifies as a whole** (`SAFE`, all body-faithful), where **five distinct famous-bug classes are each caught** (each single-line bug flips exactly one function to `refuted` under `--strict-verified-core`):

| Function | Invariant | Famous bug it prevents |
|---|---|---|
| `copy-bytes` (memcpy bound) + `heartbeat-response` (calls it) | `n ≤ src_len` as a **call-precondition** | **Heartbleed** (CVE-2014-0160) |
| `accept-seq` | post: sequence never moves backward | **KRACK** / replay |
| `deliver-len` | post: `result>0 → mac_ok=1` | **goto-fail** (CVE-2014-1266) |
| `reassemble` | post: `result ≤ capacity` | **Ping-of-Death** |
| `next-state` | post: state only advances | downgrade / state-confusion |

`heartbleed-safe.llmll` / `heartbleed-bug.llmll` — the minimal 2-function "you cannot write Heartbleed and verify" moment: the real bug (echo `claimed_len` unchecked) → `refuted` on **both** the responder's post **and** `copy-bytes`' call-precondition ("caller does not prove callee's precondition" = *called memcpy without proving the length bound*).

**Fidelity boundary (state it):** we model the **length discipline**, not C memory semantics — `copy-bytes` returns a count. Heartbleed's actual fix *was* a length check; LLMLL enforces exactly that bound as a precondition you cannot bypass.

## 5. Scaling — measured, not assumed

Modular verification is **~linear** (generated verified modules, `llmll 0.14.10`):

| Functions | LOC | Whole-module verify |
|---|---|---|
| 240 | ~1,000 | 0.63s |
| 1,000 | 4,999 | 2.38s |
| **2,000** | **9,999** | **4.94s** |

**Scale is not the bottleneck** — 10k LOC / 2,000 functions verify in ~5s (contrast: seL4 ≈ a decade for 10k LOC of C, because that is interactive theorem proving; this is modular refinement checking). *Caveat:* this measures that **adding functions is cheap (linear/modular)**, not that every function is trivial; per-function cost rises with contract complexity, but the architecture stays linear. The missing ingredient for a *large* artifact is authoring the contracted code — which is exactly what **agent orchestration** supplies.

## 6. GATING PREREQUISITE — auto-A-normalization (✅ SHIPPED v0.14.11)

**SHIPPED (v0.14.11):** `aNormalizeBody` runs before `bodyToPredM` and lifts calls out of argument/pair/if-condition positions into fresh `let`s — nested/argument-position calls now verify (`post: verified`) instead of falling back. Identity on call-free-argument expressions (full suite unchanged 1064/0). `examples/heartbleed/anf-test.llmll` verifies with nested calls written un-`let`-bound; the DEMO-COMP §10 `withdraw-twice` fixture now surfaces its two `call-pre` origins. The record below is retained for provenance.

**Root cause (confirmed empirically):** the body-VC translation handles function calls in **tail/branch** position but **not in argument position** — `(f (g x))`, `(pair (g x) (h y))` fall back to `body-fallback` → post only **asserted** (silent under `verify`) / **hard error** under `--strict-verified-core`. This is *not* about pairs (an earlier mis-diagnosis): `recv-record`'s relational **pair** post over composed calls **verifies** once A-normalized.

**Confirmed fix (`anf-test.llmll`):** `let`-binding the nested calls makes them **`verified`** (not asserted) — `serve-heartbeat` (nested call) and `recv-record` (relational pair post over call components) both prove, **no soundness gap**. The one error hit along the way was a *real weak-contract bug* (a post too weak to establish a callee precondition) — caught correctly.

**Why fix first:** agents write *natural* nested-call code; without the fix the flagship would be full of **silently-asserted** functions (or strict-core errors) on correct code — worse than a small example, because it looks like the *tool* is broken. The machinery to thread a callee's post to a `let`-bound variable **already works**; the compiler just needs to introduce the bindings.

**Fix shape:** an **A-normalization pass over the body AST** (desugar non-tail calls into `let`s) before body-VC emission, reusing the existing `let` + callee-post machinery. Bounded (~1 day + version bump).

**Precise fallback site (confirmed):** `FixpointEmit.hs:1429-1437`, `translateCallArg` inside the `EApp`/`bodyToPredM` case. A call argument that is a bare `EVar` translates to `FQVar`; any other argument is accepted **only if `bodyToPredM` returns `Just (SimpleVC [] p)`**. A nested call `(g x)` returns a `CallVC` (not a `SimpleVC`), so `translateCallArg` yields `Nothing` → `mArgPreds = Nothing` → the whole call falls back. The design comment at `:1467-1468` confirms the intent — *"return CallVC directly … the enclosing `ELet` case fills the real continuation"* — i.e. `CallVC`s are threaded by an enclosing `ELet`, and a call in argument position has none. **Fix:** a pass `aNormalizeBody :: Expr -> Expr` that lifts calls out of `EApp`/`EOp` arg positions, `EPair` components, and `EIf` conditions into fresh `let` bindings (fresh names via the existing counter), applied to each function body before `bodyToPredM`. Tail positions (if-branches, let-body, final expr) are already handled — leave them. Acceptance: `examples/heartbleed/anf-test.llmll` must verify with its nested calls written *un*-normalized (no manual `let`), i.e. the pass reproduces today's hand-`let` result.

## 7. LLMLL syntax/tooling edges found (for the scaffold + agent instructions)

- No `=>` (implies): write `(or (<= result 0) Q)`.
- `and`/`or` are **binary** → nest multi-conjunct predicates.
- Pair return: `-> (int, int)`, use `(first result)` / `(second result)`.
- `let` form: `(let [[v e]] body)` (also `(let [(v e) ...] body)`).
- `--strict-verified-core` refuses **any** fallback function up-front (masks other bugs) → every function in a discriminative scaffold must stay body-faithful.
- `def-shell` for functions that call helpers (strict `def` needs callees body-faithful first).

## 8. Plan (resume here after the ANF fix)

1. **Scaffold** the subsystem — record layer + handshake + connection-state — into **hundreds of contracted holes**.
2. **Orchestrate** agents to fill them (via `checkout`/`patch`, or whole-scaffold fills); verify the assembled module at scale; **catch the bugs**.
3. **Experiment (2)** — type-directed refinement *moves* (case-split skeletons + solver-pruned candidate lists) vs the one-shot brief — run on these real, subtle holes.
4. **goto-fail** as the second famous-bug anchor.
