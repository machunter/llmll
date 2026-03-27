# Write-and-Verify Examples — Walkthrough

Three JSON-AST example programs were created to exercise the Phase 2b `llmll verify` backend.

## Files Created

| Game | AST source | Generated |
|---|---|---|
| Tic-Tac-Toe | [tictactoe.ast.json](file:///Users/burcsahinoglu/Documents/llmll/examples/tictactoe_json_verifier/tictactoe.ast.json) | `generated/tictactoe_json_verifier/` |
| Conway's Life | [life.ast.json](file:///Users/burcsahinoglu/Documents/llmll/examples/conways_life_json_verifier/life.ast.json) | `generated/conways_life_json_verifier/` |
| Hangman | [hangman.ast.json](file:///Users/burcsahinoglu/Documents/llmll/examples/hangman_json_verifier/hangman.ast.json) | `generated/hangman_json_verifier/` |

---

## Results Summary

### `llmll check`
| Game | Statements | Status |
|---|---|---|
| Tic-Tac-Toe | 24 | ✅ OK |
| Conway's Life | 29 | ✅ OK |
| Hangman | 22 | ✅ OK |

### `llmll holes`
All files: **0 blocking holes**.

Non-blocking `?proof-required(complex-decreases)` holes on `letrec` decreases measures that involve a subtraction expression (e.g. `string-length - i`) — these are expected per the Phase 2b spec.

### `llmll verify`
All three files: **✅ SAFE (liquid-fixpoint)**

Contracts verified by the solver:
- `make-board` postcondition: `list-length result = 9`
- `set-cell` pre/post: bounds check + length-preserving
- `count-neighbors` postcondition: `0 <= result <= 8`
- `next-cell` pre/post: neighbor bounds, result in {0,1}
- `make-state` postcondition: `wrong-count = 0`
- `apply-guess` precondition: `wrong-count <= max-wrong`
- Three `check` properties per game (9 total)

### `llmll build --emit-only` + `stack run`
All three: ✅ GHC compiled, ran correctly.

---

## Bugs Discovered

### Bug 1 — liquid-fixpoint rejects capitalized ADT constructor names

**Symptom:** `llmll verify` fails with `.fq` parser error:
```
data Player 0 = [X 0 | O 0]
                 ^
unexpected 'X'
```

**Root cause:** The liquid-fixpoint `.fq` ADT declaration format does not accept capitalized identifiers (even multi-character ones like `PlayerX`) in the constructor list position.

**Workaround:** Avoid `sum` type declarations entirely. Use `string` constants (`"X"`, `"O"`, `"playing"`, `"x-wins"`) to represent variants. Tictactoe was rewritten this way.

**Impact:** Any LLMLL program using `type-decl` with a `sum` body will fail `llmll verify`. The compiler should either quote constructor names in `.fq` output or lower-case them.

---

### Bug 2 — `unwrap` builtin not in scope for `Result[int, string]`

**Symptom:** GHC compilation error:
```
Variable not in scope: unwrap :: Either String Int -> t
```

**Root cause:** The builtin `unwrap` is defined in the preamble as `llmll_unwrap :: Either String a -> a`, but the codegen emits `unwrap` (without the `llmll_` prefix) which is not in scope.

**Workaround:** Use `unwrap-or` with a safe default value instead. Since the call is guarded by `is-ok`, the default is never reached.

**Impact:** `unwrap` is documented but not available at call sites. `unwrap-or` always works.

---

### Bug 3 — `op: "/"` maps to Haskell fractional `/` instead of integer `div`

**Symptom:** GHC compilation error inside a lambda body:
```
Couldn't match expected type 'Int' with actual type 'a1 -> a1'
yi = (/ (i) (width))
```

**Root cause:** The `op: "/"` node emits Haskell's `(/)` operator, which is only available for `Fractional` types, not `Int`. Inside a lambda with multiple `let` bindings, GHC type-checks `yi` as a function type rather than `Int`.

**Workaround:** Extract the integer division into a top-level `def-logic` helper and use `"fn": "div"` (Haskell Prelude `div :: Int -> Int -> Int`) as the function name. The `div` identifier is available because `Prelude` is imported.

**Impact:** Any use of `op: "/"` on `int` values compiles incorrectly. The codegen should emit `div` for integer division.

---

## Smoke Test Output

### Tic-Tac-Toe (move: centre = 4)
```
Player X goes first.
>    |   |  
---+---+---
   | X |  
---+---+---
   |   |  
Player O's turn.
```

### Conway's Life (initial glider after 1 step)
```
Generation 1 | Alive: 5
....................
#.#.................
.##.................
.#..................
...
```

### Hangman (word: "hangman", guesses: h a n g m)
```
Word: h a n g m a n 
Wrong guesses left: 6
You won! Congratulations!
```
