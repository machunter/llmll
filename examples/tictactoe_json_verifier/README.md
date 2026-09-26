# tictactoe_json_verifier: Tic-Tac-Toe with contracts the solver cannot reach

A Tic-Tac-Toe program in the JSON-AST surface (schema 0.6.0), written with
contracts and `check` properties. It is a separate program from
[`../tictactoe_sexp/`](../tictactoe_sexp/): the state is
`(board, (player, status))`, cells are numbered 0 to 8, and five functions
carry contracts:

- `make-board`: `post` the board has 9 cells.
- `board-get`, `cell-empty?`: `pre` `0 <= idx < 9`.
- `set-cell`: `pre` `0 <= idx < 9`; `post` the board still has 9 cells.
- `render-row`: `pre` `0 <= base <= 6`.

No contract here is proved. The board is a `list`, outside the decidable
fragment, so `make-board` and `set-cell` fall back and their postconditions are
assumed (see [the examples index](../README.md#language-and-syntax)). The
Hangman counterpart is [`../hangman_json_verifier/`](../hangman_json_verifier/).

| File | What it is |
|---|---|
| `tictactoe.ast.json` | The game: 19 functions, 3 `check` properties, a `def-main :mode console` |
| `VERIFICATION_SCOPE.md` | Per-function contract classification and the verification boundary |

## Commands (outputs reproduced against llmll 0.26.5)

Run these from this directory. `verify` and `test` write a `.verified.json`
sidecar next to the file, so experiment on a copy.

**Verify: partial, 0 of 2 proved.**
```bash
llmll verify ./tictactoe.ast.json
```
```
   body-fallback: make-board, board-get, cell-empty?, set-cell, check-triple, render-row
   ⚠️  W-BODY-FALLBACK: 'make-board' fell back from body-faithful verification (body-outside-fragment), so its post is assumed and not proved. Refused by: app:list-prepend.
   ⚠️  W-BODY-FALLBACK: 'set-cell' fell back from body-faithful verification (body-outside-fragment), so its post is assumed and not proved. Refused by: let.
   Running liquid-fixpoint ...
⚠️  ./tictactoe.ast.json — SAFE (liquid-fixpoint), partial: 0 of 2 contracted functions proved; 2 assumed, not proved: make-board, set-cell
   (--strict-verified-core fails on assumed functions)
```
Exit 0. With `--trust-report`, the four preconditions and the two
postconditions are all `asserted`, and `board-full?` is listed as
termination-unverified recursion (no `(decreases …)` measure).

**Test: the `check` properties.**
```bash
llmll test ./tictactoe.ast.json
```
```
./tictactoe.ast.json — 3 properties
  ✅ Passed:  2
  ❌ Failed:  0
  ⚠️  Skipped: 1
   .verified.json write-back diagnostics:
     ⚠ property "set-cell-preserves-length" covers multiple contracted callees (make-board, set-cell); no trust evidence recorded — split the property or add an explicit ':subject f' / ':subjects [f₁ … fₖ]' annotation
```
Exit 0. `make-board-has-9-cells` and `set-cell-preserves-length` pass on 100
samples each; `fresh-board-status-is-playing` is skipped because its body did
not reduce to a `bool` on any of 1000 samples. The second passing property
calls two contracted functions, so it records no trust evidence for either.

**Build and play.**
```bash
llmll build ./tictactoe.ast.json -o ./out
cd out && stack exec tictactoe
```
`build` exits 0. Players alternate, X first, entering a cell number 0 to 8.
Scripted with `printf '0\n3\n1\n4\n2\n' | stack exec tictactoe`, the game ends:
```
 X | X |  
---+---+---
 O | O |  
---+---+---
   |   |  
Player X's turn.
> 
X wins!
```
Exit 0.
