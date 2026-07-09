# secure-channel-emergent — the decomposition the agents invented

The companion artifact to [`../heartbleed/secure-channel/`](../heartbleed/secure-channel/),
built to remove that flagship's one authored shortcut. There, the decomposition was
**front-loaded**: a reference solution was written first and holed out into a 163-contract
scaffold; agents filled a structure a human had already solved. Here, **no reference
solution and no full decomposition ever existed**: the only human-authored layer is the
root contracts below, and everything under them — the sub-problems, their contracts, and
their bodies — was invented by agents through cascading `refine`, gated and verified at
every step.

## What is human-authored (the entire spec surface)

`roots/*.llmll` — seven modules, each a small set of root `def-shell` contracts with
`?impl` bodies. The famous-bug invariants live here, stated once at the root:

| Module | Root contracts | Invariant it pins |
|---|---|---|
| `record` | `frame-accept`, `deliver-count` | the Heartbleed bound: never deliver more than arrived |
| `sequence` | `seq-accept`, `seq-after` | anti-replay freshness: strictly newer, within window |
| `handshake` | `hs-can-establish`, `hs-step` | the goto-fail gate: ESTABLISHED only after checks actually passed |
| `keysched` | `key-ready`, `epoch-after` | keys only when installed, epoch monotone |
| `flow` | `send-allow`, `credit-after`, `credit-granted` | credit conservation, never negative |
| `alert` | `alert-admit`, `alert-worst` | fatal-alert latch: nothing delivers after fatal |
| `spine` | `channel-admit`, `channel-deliver-len` | the whole-channel delivery predicate (imports all six) |

No bodies were ever written by the author — not as references, not as drafts. The spine's
`channel-deliver-len` contract deliberately has the goto-fail shape (deliver `claimed`
exactly when every gate passes, else 0); no agent was steered toward or away from the
unconditional-deliver shortcut.

## The channel discipline (what agents saw, enforced)

Each hole was filled by a **fresh, stateless agent** (`claude -p`) with **all tools
disabled** — it cannot read this repository, the flagship, or anything else. Its entire
input is:

1. the fixed [operation manual](audit/OPERATION-MANUAL.md) — protocol + language rules
   only, disclosed verbatim as part of this artifact; and
2. the hole's **checkout brief** — the compiler-emitted contract, in-scope names, and
   callable contracts (including imported ones, `status: "imported"`).

No worked examples, no hints, no steering, no conversation history. On a rejection
(gate, type error, or verification failure) the agent's retry prompt adds only the
compiler/harness error text — the same feedback loop any engineer gets. Every prompt,
reply, request, and verdict is logged under `audit/` for independent inspection.

**Per-fill acceptance bar:** verify `SAFE` **and** the filled function lands in the
`body-faithful` set. Plain `SAFE` is not enough — see F-1 below.

## How it was built (`audit/runner.py`)

```
while the module has holes:
  checkout first hole → brief
  agent(manual + brief) → FILL <body> | REFINE <body + spawned def-shell contracts>
  convert via the compiler's own parser (build --emit on a temp module)
  apply (patch | refine — vacuity + scope gates run inside refine)
  accept iff verify SAFE ∧ filled function body-faithful; else roll back, retry (≤3)
```

The six leaf modules ran as parallel independent cascades; the spine ran last against
the finished modules, composing them through **cross-module assume-guarantee**
(`import`-linked, body-faithful across module boundaries — v0.14.17+; the briefs carry
imported contracts since v0.14.18/19).

## Findings

- **F-1 (compiler fix shipped, v0.14.21).** The first blind agent answered the very first
  brief with a degenerate **self-call** — `(alert-admit latched sev)` for `alert-admit`'s
  own hole. It patched cleanly and verified `SAFE`: a nonterminating body discharges its
  own contract vacuously at partial correctness (the R7/TERM-1 gap), and the recursive
  function silently drops out of the body-faithful set. Root cause: the brief presented
  the hole's own function as an available `"filled"` callable whose contract exactly
  matches the goal. Fixed upstream (the enclosing function now reads `status: "hole"`),
  and the harness bar (body-faithful, not just SAFE) closes the class.
- **F-2 (emergent Heartbleed bound).** Asked to fill a wide record-admission contract, an
  agent spawned `len-ok [claimed received] -> bool` with post
  `(<=> result (and (>= claimed 0) (<= claimed received)))` — the Heartbleed bound,
  invented as a sub-contract by an agent that has never seen the CVE framing.
- **F-3 (agents simplify rather than decompose when they can).** Given
  `(<=> result (and (and (>= sev 1) (<= sev 2)) (and (not latched) (not (= sev 2)))))`,
  the agent filled `(and (= sev 1) (not latched))` — the logically simplified equivalent —
  and the solver proved the equivalence. Emergent decomposition happens when the contract
  is genuinely wide, not because agents prefer trees.
- **F-4 (unprompted cross-hole reuse).** The agent filling `record.deliver-count` reused
  `claim-in-window` — a sub-function a *different* agent had invented for `frame-accept` —
  as its guard: `(if (claim-in-window claimed received) claimed received)`. The clamp's
  else-branch is correct only under the root's pre (`¬(0 ≤ claimed ≤ received) ∧ claimed ≥ 0
  ⇒ received < claimed`); the solver proved it body-faithfully.
- **F-5 (the spine agent composed the modules).** Handed `channel-admit`'s 12-atom
  contract, the agent's whole body was five imported root calls —
  `frame-accept ∧ seq-accept ∧ key-ready ∧ send-allow ∧ alert-admit` — correctly
  instantiating `send-allow`'s `len` with `claimed`, and *omitting* `hs-can-establish`
  (whose `hs_state = 4` clause `key-ready` already pins). The 12-atom `<=>` discharged
  through five cross-module assume-guarantees.
- **F-6 (the unsteered bait was declined).** `channel-deliver-len` is the goto-fail shape —
  deliver `claimed` iff every gate passes, else 0 — with no steering text anywhere. The
  agent wrote the guarded `(if (channel-admit …) claimed 0)`, reusing the sibling another
  agent had filled one step earlier. n = 1, observational; the deterministic guarantee is
  the mutation check below, not the agent's judgment.

## Results

| module | steps | refine / fill | retries | functions |
|---|---:|---|---:|---:|
| record | 4 | 1 / 3 | 0 | 4 |
| sequence | 5 | 1 / 4 | 0 | 5 |
| handshake | 4 | 1 / 3 | 0 | 4 |
| keysched | 5 | 1 / 4 | 0 | 5 |
| flow | 3 | 0 / 3 | 0 | 3 |
| alert | 2 | 0 / 2 | 0 | 2 |
| spine | 2 | 0 / 2 | 0 | 2 |
| **total** | **25** | **4 / 21** | **0** | **25** |

Every step accepted on the first attempt (after the F-1 compiler fix); the vacuity and
scope gates never had to fire — every invented sub-contract was an exact `<=>` or a
conditional equality. All seven modules verify `SAFE` under `--strict-verified-core`,
including the import-linked spine (cross-module assume-guarantee, body-faithful across
the boundaries).

**Mutation check** (`audit/mutation-check/`): replacing `channel-deliver-len`'s body with
the unconditional `claimed` — the goto-fail move — is **refuted**
(`body verification of 'channel-deliver-len' failed`). The invariant is in the program's
proof, not in the agents' good behavior.

## Scope

Same verification boundary as the flagship: the integer/boolean relational layer
(lengths, counters, ordinals, credits) in `Σ_auto`; crypto primitives are out of scope by
construction (none are modeled here). Recursion is proved at partial correctness — which
is precisely why the acceptance bar requires body-faithful, not just SAFE (F-1). The
compiler proves each invented sub-contract is met and non-vacuous — **not** that it is
the *right* sub-contract; the vacuity gate removes the emptiest failure mode and the root
contracts pin the ends, but contract quality in the middle is observed, not certified.
