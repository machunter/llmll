# Flagship: Verified Secure-Channel Record Layer — design & status

> **Status: BUILT.** The full **163-hole, seven-module** channel is scaffolded, filled by
> orchestrated agents, and verified **as one whole program — `SAFE`, all 163 body-faithful**
> (§11). The delivery gate (§8) and both caught-bug modes hold at scale. Artifact:
> `examples/heartbleed/secure-channel/`.
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

## 8. The delivery gate — the load-bearing cross-component invariant (✅ validated)

The spine that makes the flagship more than a pile of independent `clamp`s: **a plaintext
byte reaches the application only if every upstream condition held.** Validated in
`examples/heartbleed/slice-gate.llmll` (verifies `SAFE`):

- Four **gate leaves**, each a one-line function whose post carries (a) its own famous-bug
  implication and (b) the monotonicity `result <= n` that threads a running byte-count down
  the chain: `gate-mac` (delivered ⇒ MAC verified — goto-fail), `gate-fresh` (⇒ seq advanced
  — KRACK), `gate-connected` (⇒ handshake connected — downgrade), seeded by `payload-avail`
  (length discipline — Heartbleed / Ping-of-Death).
- The composer `deliver-plaintext` chains them by **nested calls in argument position**
  (`(gate-connected (gate-fresh (gate-mac (payload-avail …) …) …) …)` — the ANF fix in
  action). Its post is the **four-way conjunction** `result>0 ⇒ (mac ∧ fresh ∧ connected)`,
  provable *only* because each leaf's contract supplies its piece and the `<= n` monotonicity
  gives the solver the transitivity.

**Both caught-bug modes validated** (the "convincing" moment, §1.3):

| File | Bug | What fires |
|---|---|---|
| `slice-gate-bug.llmll` | `gate-mac`'s **post** weakened (drops the MAC clause) | `gate-mac` stays `SAFE` *in isolation*; `deliver-plaintext` **refutes** — a weakened contract three calls away breaks a whole-channel guarantee. *No unit test could catch this.* |
| (`gate-mac` body → `(if (= mac_ok 1) n n)`) | goto-fail in the **body**, contract intact | `gate-mac` refutes **locally** (its own post); composer stays `SAFE` (modular — trusts the contract). |

The scaffold form (`slice-gate-scaffold.llmll`, every body `?impl`) enumerates via `llmll holes`
as 5 non-blocking holes at `/statements/{0..4}/body` — the harness-consumable shape agents fill.

## 9. Module map (as built — 163 holes)

All contracts are **integer-relational (QF-LIA)** — lengths, offsets, sequence numbers, state
ordinals, credits, byte-budgets, epochs (the honest ceiling, §3). Each module is a family of
small `def-shell` holes plus a few composers that route facts through callee contracts into the
delivery gate. Realized in `examples/heartbleed/secure-channel/`.

| Module | Discipline | Famous-bug anchor | holes |
|---|---|---|---|
| **M1 Record framing** | record ≤ 2¹⁴; header/body/pad/tag length arithmetic; `copy-bytes` memcpy bound; `reassemble` ≤ capacity | Heartbleed, Ping-of-Death | 20 |
| **M2 Sequence / anti-replay** | monotone seq; sliding-window floor/in-window/slide; wrap-before-rekey | KRACK / replay | 28 |
| **M3 Handshake FSM** | state ordinals only advance; `expect-message`; version = highest-common (no downgrade); suite ≤ offered | downgrade / state-confusion | 28 |
| **M4 Key schedule / usage** | bytes-under-key ≤ AEAD limit before rekey; derive-stage ordering; key-gen counter monotone | rekey-safety | 26 |
| **M5 Flow control** | credits ≥ 0 ∧ ≤ max; buffered ≤ capacity; consume/grant bounds | resource exhaustion | 26 |
| **M6 Alert / close** | `deliver-len` (deliver ⇒ MAC); alert level order; fatal ⇒ closed; closed monotone | goto-fail | 22 |
| **M7 Delivery gate (spine)** | composers routing M1–M6 facts into the delivery gate (§8) | *all four, relationally* | 13 |
| | | | **163** |

**163 contracted holes**, seven modules, one whole-program `verify`.

## 10. Build result (✅ done)

The §9 decomposition is built and verified. Sequence:

1. **Scaffold** — `scaffold_holeout.py` holes out the verified reference solution
   (`secure-channel/sc-channel.llmll`) into `sc-channel-scaffold.llmll`: 163 `?impl` bodies,
   contracts intact, enumerating via `llmll holes` as **163 holes (0 blocking)**. The skeleton
   passes at the contract level before any body exists.
2. **Blind fill** — seven independent agents, each given only a module's scaffold plus the
   `slice-gate.llmll` pattern (**not** the reference). Six filled M1–M6 (150 functions); one
   filled the M7 spine (13 cross-module composers).
3. **Assemble & verify whole** — the seven filled modules concatenate into
   `agent-fill/sc-channel-agentfilled.llmll` and verify as one program: **`SAFE`, all 163
   body-faithful, 163 `caller_obligations`, ~60 s**. The reference solution verifies too.

**The catch, at scale** (`agent-fill/adversarial/`): the goto-fail fill of `deliver-len`
(unconditional `payload_len`) is **refuted** — `body verification of 'deliver-len' failed`;
the guarded fill verifies `SAFE`. Separately observed (n = 1, stochastic): the fill agent,
*prompted toward* the bug ("MAC already checked, drop the redundant check"), still wrote the
guarded form. The compiler is the guarantee; the agent behavior is a bonus.

Full write-up: [`examples/heartbleed/secure-channel/README.md`](../../examples/heartbleed/secure-channel/README.md).

## 11. Next

1. **Orchestrator at scale** — this build fanned out one agent per *module*; a genuine
   hundreds-of-holes run wants a multi-hole loop in `run_multi.py` (`find_hole_pointer` returns
   only the *first* hole today) doing per-hole `checkout`/`patch`.
2. **Experiment (2)** — type-directed refinement *moves* (case-split skeletons + solver-pruned
   candidate lists) vs the one-shot brief — run on these real, subtle holes.
3. **goto-fail** as a fully developed second anchor (M6 carries the `deliver-len` primitive).
