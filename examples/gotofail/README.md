# goto-fail (CVE-2014-1266) — verified with real sum types

Apple's "goto fail" reported a successful TLS handshake while **skipping** the
signature check. Modeled here the *right way*: the outcome is a `Verdict` **value**,
each stage's status is a `Step` **value**, and the invariant that carries the story is a post
over the *scrutinee's constructor* — "return `Verified` only if `sig = Continue`".

This is the class of body that MATCH-WIDEN (v0.14.12) made verifiable: a two-arm sum
`match` whose contract references the matched value's constructor discharges
body-faithfully (int-tag discrimination, QF-LIA — no datatype testers). **MATCH-WIDEN-2
(v0.14.26)** extended that to **n-arm (>2-constructor) sums** (`nary.llmll`) and to
**sequential matches in one body** (`sequential.llmll` — the `(let [x (match a …)]
(match b …))` shape that previously fell back). Crypto/hash primitives are axiomatized;
the modeled discipline is the error-propagation control flow the bug broke.

| File | Verdict |
|---|---|
| `finalize.llmll` | `SAFE` — the single-function `def-shell` version quoted in blog Post 2 |
| `finalize-bad.llmll` | **refuted** — the goto-fail fill (`Verified` on the `Abort` arm) |
| `pipeline.llmll` | `SAFE` — `finalize` returns `Verified` only when `sig = Continue` |
| `pipeline-bad.llmll` | **refuted** — returns `Verified` on the `Abort` arm too (the bug) |
| `nested.llmll` | `SAFE` — the multi-stage pipeline via nested matches (reordered arms) |
| `sequential.llmll` | `SAFE` — the sequential `(let [(h (match hash …))] (match sig …))` form (MATCH-WIDEN-2 Commit B) |
| `sequential-bad.llmll` | **refuted** — `Verified` on the signature stage's `Abort` arm, threaded across the sequence (the bug) |
| `nary.llmll` | `SAFE` — a 3-arm `Step3` sum, `Verified` only if `sig = Continue` (MATCH-WIDEN-2 Commit A; strict-core `def`, v0.14.27) |

```
llmll verify examples/gotofail/finalize.llmll        # SAFE
llmll verify examples/gotofail/finalize-bad.llmll    # body verification failed (refuted)
llmll verify examples/gotofail/pipeline.llmll        # SAFE
llmll verify examples/gotofail/pipeline-bad.llmll    # body verification failed (refuted)
llmll verify examples/gotofail/nested.llmll          # SAFE
llmll verify examples/gotofail/sequential.llmll      # SAFE
llmll verify examples/gotofail/sequential-bad.llmll  # body verification failed (refuted)
llmll verify examples/gotofail/nary.llmll            # SAFE
```

**Scope.** As of MATCH-WIDEN-2 (v0.14.26): two-arm **and** n-arm payload-bearing sums,
nested matches, and sequential two-match-in-one-body composition all discharge
body-faithfully. The scrutinee must be `match`ed in the body (a constructor post over
an *un-matched* param falls back to contract-only, not a crash). The n-arm strict-core
`def` grammar gap (an n-arm match once needing a `def-shell` escape hatch) closed in
v0.14.27, so `nary.llmll` earns the strict tier directly. One residual limit remains:
recursive / non-admissible sums stay firewalled (int-tag discrimination is for acyclic
admissible sums).
