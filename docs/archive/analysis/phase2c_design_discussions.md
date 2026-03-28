# Phase 2c — Design Discussion Tracker

> **Scope:** `llmll typecheck --sketch` and the `POST /sketch` HTTP endpoint  
> **Status:** 🔴 All open  
> **Last updated:** 2026-03-27

---

## D1 — Inference Algorithm Architecture

**Status:** 🔴 Open

**Question:** LLMLL's current type-checker is bidirectional (checking ↔ synthesis). `--sketch` requires constraint-propagation so types can flow *into* holes from surrounding context. Are these two passes, or does the bidirectional checker get extended?

**Options:**
- A) Separate constraint-propagation pass (clean separation, more work)
- B) Extend bidirectional checker with hole-unification variables (less new code, risk of entanglement)

**Decision:**

---

## D2 — Hole Output When Type Is Unknown

**Status:** 🔴 Open

**Question:** If a hole's inferred type depends on another unresolved hole, what does `--sketch` return for `"inferredType"`?

**Options:**
- A) Emit `"inferredType": null` (omit)
- B) Emit `"inferredType": "?"` or `"inferredType": "unknown"`
- C) Emit the partial type with metavariables, e.g. `"list[?a]"`

**Decision:**

---

## D3 — Error Reporting Aggressiveness on Partial Programs

**Status:** 🔴 Open

**Question:** A bidirectional checker often can't confirm errors until all types are known. How aggressively should `--sketch` report errors while holes are present? Risk: false positives that mislead agents.

**Options:**
- A) Only report errors that are *certain* regardless of how holes resolve (conservative)
- B) Report all errors detectable under the assumption that holes could be any type (aggressive)
- C) Report errors with a `"definite": true/false` flag

**Decision:**

---

## D4 — Server Lifecycle

**Status:** 🔴 Open

**Question:** Is the HTTP endpoint a persistent daemon (`llmll serve` running on port 7777) or a per-request process?

**Considerations:**
- Persistent daemon: fast (<200ms feasible), but adds state, port conflicts, startup management
- Per-request: zero state issues, but cold-start cost may exceed 200ms target

**Decision:**

---

## D5 — Security Surface of localhost:7777

**Status:** 🔴 Open

**Question:** A persistent server on localhost is reachable by any local process. Is that acceptable for the intended use case (single-developer agent session)?

**Considerations:**
- Auth token? (simplest mitigation)
- Unix socket instead of TCP? (better isolation)
- Scope: is this only ever a local dev tool, or is multi-user/CI planned?

**Decision:**

---

## D6 — CLI Command vs. HTTP Endpoint Relationship

**Status:** 🔴 Open

**Question:** Should `llmll typecheck --sketch <file>` be a thin wrapper over the HTTP endpoint, or a completely separate code path?

**Options:**
- A) CLI calls the HTTP server internally (single implementation)
- B) CLI is a direct in-process call; HTTP server is a separate thin adapter over the same library (cleaner, recommended)
- C) CLI and HTTP are independent implementations

**Decision:**
