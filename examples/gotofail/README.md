# goto-fail (CVE-2014-1266) — verified with real sum types

Apple's "goto fail" reported a successful TLS handshake while **skipping** the
signature check. Modeled here the *right way*: the outcome is a `Verdict` **value**,
each stage's status is a `Step` **value**, and the load-bearing invariant is a post
over the *scrutinee's constructor* — "return `Verified` only if `sig = Continue`".

This is the class of body that MATCH-WIDEN (v0.14.12) made verifiable: a two-arm sum
`match` whose contract references the matched value's constructor now discharges
body-faithfully (int-tag discrimination, QF-LIA — no datatype testers). Crypto/hash
primitives are axiomatized; the modeled discipline is the error-propagation control
flow the bug broke.

| File | Verdict |
|---|---|
| `pipeline.llmll` | `SAFE` — `finalize` returns `Verified` only when `sig = Continue` |
| `pipeline-bad.llmll` | **refuted** — returns `Verified` on the `Abort` arm too (the bug) |
| `nested.llmll` | `SAFE` — the multi-stage pipeline via nested matches (reordered arms) |

```
llmll verify examples/gotofail/pipeline.llmll        # SAFE
llmll verify examples/gotofail/pipeline-bad.llmll    # body verification failed (refuted)
llmll verify examples/gotofail/nested.llmll          # SAFE
```

**Scope (honest).** Two-arm sums; the scrutinee must be `match`ed in the body (a
constructor post over an *un-matched* param falls back to contract-only, not a crash).
Sequential two-match-in-one-body composition (`(let [x (match a …)] (match b …))`)
still falls back to contract-only — a separate case-tree-threading follow-on.
