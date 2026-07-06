# Heartbleed & the secure-channel record layer (flagship substrate)

Validated substrate for the flagship "convincing large example." Design & plan of record:
[`docs/design/flagship-secure-channel-proposal.md`](../../docs/design/flagship-secure-channel-proposal.md).

**Protocol logic, honestly scoped:** cryptographic primitives are axiomatized as opaque
contracts; LLMLL verifies the *length / ordering / monotonicity discipline* — the layer where
these famous bugs actually lived.

## Files

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

- **`anf-test.llmll`** — evidence for the auto-A-normalization compiler fix (proposal §6): with
  `let`-bound (A-normalized) nested calls, both a nested-call composition and a relational
  **pair** post over composed calls verify (`post: verified`), confirming the fallback is purely
  a calls-in-argument-position issue with no soundness gap.

## Famous-bug invariants in `channel.llmll`

| Function | Prevents |
|---|---|
| `heartbeat-response` (+ `copy-bytes` bound) | Heartbleed (CVE-2014-0160) |
| `accept-seq` (monotone sequence) | KRACK / replay |
| `deliver-len` (deliver ⇒ MAC verified) | goto-fail (CVE-2014-1266) |
| `reassemble` (≤ capacity) | Ping-of-Death |
| `next-state` (state only advances) | downgrade / state-confusion |
