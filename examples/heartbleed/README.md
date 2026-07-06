# Heartbleed & the secure-channel record layer

**Protocol logic, honestly scoped:** cryptographic primitives are axiomatized as opaque
contracts; LLMLL verifies the *length / ordering / monotonicity discipline* — the layer where
these famous bugs actually lived. Design & plan of record:
[`docs/design/flagship-secure-channel-proposal.md`](../../docs/design/flagship-secure-channel-proposal.md).

## ▶ The flagship: [`secure-channel/`](secure-channel/) — a 163-function verified channel

A full record layer decomposed into **163 contracted holes across seven modules**, filled by
**orchestrated agents**, verified **as one whole program** — `SAFE`, every body faithful, ~60 s.
The goto-fail primitive cannot verify if you reintroduce the bug. See
[`secure-channel/README.md`](secure-channel/README.md) for the headline and how to reproduce it.

```
llmll verify examples/heartbleed/secure-channel/agent-fill/sc-channel-agentfilled.llmll   # SAFE, 163 fns
```

The files below are the **minimal warm-ups** — the single-idea pieces the flagship is built from.

## Minimal substrate (start here)

- **`channel.llmll`** — a 7-function record layer that verifies as a whole (`SAFE`), where five
  famous-bug classes are each load-bearing. Try flipping one line of any function and re-running.

    ```
    llmll verify examples/heartbleed/channel.llmll                      # SAFE
    ```

- **`heartbleed-safe.llmll` / `heartbleed-bug.llmll`** — the minimal "you cannot write Heartbleed
  and verify" moment. The bug echoes the attacker's `claimed_len` bytes without checking it
  against `received_len` (the real CVE-2014-0160); `copy-bytes`' precondition is the bound whose
  absence *was* Heartbleed.

    ```
    llmll verify examples/heartbleed/heartbleed-safe.llmll                     # SAFE
    llmll verify examples/heartbleed/heartbleed-bug.llmll --strict-verified-core
    #   error: call-site precondition of 'copy-bytes' not satisfied in 'heartbeat-response'
    #          — caller does not prove callee's precondition
    #   ERROR: --strict-verified-core: refuted: heartbeat-response
    ```

- **`anf-test.llmll`** — the auto-A-normalization fix **shipped (v0.14.11)**: nested calls in
  argument position and a relational **pair** post over composed calls now verify
  (`post: verified`) written *naturally* — no manual `let`. The compiler A-normalizes them
  (`aNormalizeBody`, proposal §6).

- **`slice-gate.llmll` / `slice-gate-scaffold.llmll` / `slice-gate-bug.llmll`** — the
  **delivery gate**, the flagship's load-bearing cross-component invariant: a plaintext byte is
  delivered *only if* MAC-verified **and** sequence-fresh **and** handshake-connected **and**
  length-sound. Four gate leaves chained by nested calls; `deliver-plaintext`'s post is the
  four-way conjunction, provable only through the leaves' contracts (proposal §8).

    ```
    llmll verify examples/heartbleed/slice-gate.llmll            # SAFE
    llmll holes  examples/heartbleed/slice-gate-scaffold.llmll   # 5 holes to fill
    llmll verify examples/heartbleed/slice-gate-bug.llmll        # gate-mac SAFE alone,
    #   error: body verification of 'deliver-plaintext' failed   # but the composer refutes
    ```

    `slice-gate-bug.llmll` is the moment no unit test could catch: `gate-mac`'s contract is
    weakened (drops "delivered ⇒ MAC verified"), it still verifies *in isolation*, and the
    refutation fires three calls away at `deliver-plaintext`.

## Famous-bug invariants in `channel.llmll`

| Function | Prevents |
|---|---|
| `heartbeat-response` (+ `copy-bytes` bound) | Heartbleed (CVE-2014-0160) |
| `accept-seq` (monotone sequence) | KRACK / replay |
| `deliver-len` (deliver ⇒ MAC verified) | goto-fail (CVE-2014-1266) |
| `reassemble` (≤ capacity) | Ping-of-Death |
| `next-state` (state only advances) | downgrade / state-confusion |
