# `--sketch` — Compiler Team Handoff

> **From:** Language Team  
> **Date:** 2026-03-28  
> **Reference:** `docs/sketch-implementation-guide.md` (full decision record)  

This document summarises what to build, where to build it, and what decisions have already been made. Read `sketch-implementation-guide.md` for the full rationale behind each decision.

---

## What you are building

`llmll typecheck --sketch <file>` — accepts a partial LLMLL program (holes allowed everywhere), runs constraint-propagation type inference, returns a JSON object mapping each hole's pointer to its inferred type plus any detectable errors.

`llmll serve [--host HOST] [--port PORT] [--token TOKEN]` — exposes the sketch pass as an HTTP endpoint for agent use.

---

## Decisions already made — do not revisit

| Decision | Outcome |
|----------|---------|
| **D1** Inference algorithm | `checkExpr` / `inferExpr` split; `EIf` try-and-fallback; `EMatch` two-pass loop; `EApp` 1-line swap |
| **D2** Hole status ADT | `HoleTyped`, `HoleAmbiguous`, `HoleUnknown`; `inferredType` is `null` for indeterminate cases; conflicts in `errors` only |
| **D3** Error aggressiveness | Emit all errors; annotate with `holeSensitive: bool`; `TVar ("?" <> name)` is the required canonical form for hole type variables |
| **D4** JSON Pointer tracking | `tcPointerStack :: [Text]` in `TCState`; `withSegment` / `currentPointer` mirror `withEnv` pattern; zero monad stack change |
| **D5** Server security | Localhost default; `--token` pre-wired; TLS via reverse proxy; `emptyTCState` per request — not at startup |

---

## Files to touch

| File | What changes |
|------|-------------|
| `compiler/src/LLMLL/TypeCheck.hs` | Add `tcSketch`, `tcHoles`, `tcPointerStack` to `TCState`; add `checkExpr`, `recordHole`, `recordHoleUnknown`, `withSegment`, `currentPointer`, `isHoleVar`, `isHoleSensitive`; patch `EIf`, `EMatch`, `EApp` arms; patch `inferExpr (EHole ...)` |
| `compiler/src/LLMLL/Sketch.hs` | **New file.** `HoleStatus`, `SketchHole`, `SketchResult`, `runSketch`, `encodeSketchResult` |
| `compiler/src/Main.hs` | Add `doSketch` subcommand; add `llmll serve` subcommand with Warp handler |
| `compiler/package.yaml` | Add `warp`, `wai` dependencies |

---

## Key invariants — must not be broken

**1. `inferExpr (EHole name _)` must return `TVar ("?" <> name)` in synthesis mode.**  
`isHoleVar` and `holeSensitive` classification depend on the `"?"` prefix. Any other form silently breaks D3.

**2. `emptyTCState` must be constructed inside the Warp handler, not at server startup.**  
Hoisting it to a shared ref breaks the stateless-per-request guarantee and introduces concurrency bugs.

**3. `withSegment` must guard against calling `init` on an empty list.**  
See the `[!WARNING]` in `sketch-implementation-guide.md` §D4. The panic cannot occur in correct usage, but defensive handling is required.

**4. `tcSketch = False` must make `recordHole`, `withSegment`, and `currentPointer` inert.**  
Zero overhead on the normal `llmll check` path. All new `when tcSketch $` guards must be consistent.

---

## Output schema (what `encodeSketchResult` must produce)

```json
{
  "schemaVersion": "0.2.0",
  "holes": [
    { "name": "?win_message",  "inferredType": "Command",      "pointer": "/statements/3/body/else" },
    { "name": "?my_ambiguous", "inferredType": null,           "pointer": "/statements/5/body/then" }
  ],
  "errors": [
    { "kind": "ambiguous-hole", "hole": "?my_ambiguous",
      "message": "conflicting constraints: string vs int",
      "pointer": "/statements/5/body/then" },
    { "kind": "type-mismatch", "expected": "bool", "got": "int",
      "pointer": "/statements/1/body/condition", "holeSensitive": false }
  ]
}
```

**Rules:**
- `inferredType` is always a valid LLMLL type string (surface syntax, not Haskell) or `null`. Never a diagnostic string.
- `holeSensitive: false` errors appear before `holeSensitive: true` errors.
- `schemaVersion` is present at the top level.
- One entry in `holes[]` per pointer (not per name — the same `?name` at two positions gets two entries).

**`displayType` note:** `encodeSketchResult` needs a function that renders `Type` as an LLMLL surface-syntax string (`"Result[int, string]"`, `"list[Command]"`, `"(int, string)"`). Check whether a `showType` or similar already exists in `TypeCheck.hs` for error messages — if so, reuse it directly.

---

## Acceptance gate

All criteria are in `sketch-implementation-guide.md`. The minimum set to pass before Phase 2c closes:

```bash
# Hole inferred from EApp context
stack exec llmll -- typecheck --sketch examples/sketch/app_hole.ast.json
# → holes[0].inferredType != null

# EIf sibling constraint
stack exec llmll -- typecheck --sketch examples/sketch/if_hole.ast.json
# → holes[0].inferredType == "Command"

# EMatch sibling constraint
stack exec llmll -- typecheck --sketch examples/sketch/match_hole.ast.json
# → holes[0].inferredType == "Command"

# EMatch conflict → null + ambiguous-hole error
stack exec llmll -- typecheck --sketch examples/sketch/match_conflict.ast.json
# → holes[0].inferredType == null
# → errors[0].kind == "ambiguous-hole"

# holeSensitive classification
stack exec llmll -- typecheck --sketch examples/sketch/hole_sensitive.ast.json
# → errors contains both holeSensitive:true and holeSensitive:false entries

# Server statelessness
llmll serve --port 7777 &
curl -s -X POST localhost:7777/sketch -d @examples/sketch/if_hole.ast.json | jq '.holes[0].inferredType'
# → "Command"
# Two concurrent POSTs return independent results
```

Fixture files belong in `examples/sketch/`. Minimise each fixture to exactly one acceptance criterion.
