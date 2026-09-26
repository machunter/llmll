# tictactoe_sexp: two-player Tic-Tac-Toe in the S-expression surface

A two-player console Tic-Tac-Toe in LLMLL's S-expression syntax. The state is a
`(board, turn)` pair, the board a 9-cell `list[string]`. It shows `match` on
the `Result` of `string-to-int`, list literals hoisted into `let` bindings, and
a `def-main :mode console` loop whose `:done?` hook (`is-game-over?`) ends the
game on a win or a full board and whose `:on-done` hook (`show-result`) prints
the outcome.

This is a language and syntax example. No function carries a postcondition, so
the solver has nothing to prove (see [the examples index](../README.md#language-and-syntax)).
The JSON-AST Tic-Tac-Toe in [`../tictactoe_json_verifier/`](../tictactoe_json_verifier/)
is a separate program written with contracts, not a translation of this one.

| File | What it is |
|---|---|
| `tictactoe.llmll` | The whole game: 15 functions and a `def-main` |

## Commands (outputs reproduced against llmll 0.26.5)

Run these from this directory. `verify` writes a `.verified.json` sidecar next
to the file, so experiment on a copy.

**Check and build.**
```bash
llmll check ./tictactoe.llmll
llmll build ./tictactoe.llmll -o ./out
```
```
✅ ./tictactoe.llmll — OK (17 statements)
...
   stack build OK
OK Generated Haskell package: ./out
```
Both exit 0.

**Play.** Players alternate, X first, entering a position 1 to 9 on stdin.
Non-numeric input, a position out of range, or a taken cell re-prompts.
```bash
cd out && stack exec tictactoe
```
Scripted with `printf '1\n4\n2\n5\n3\n' | stack exec tictactoe`:
```
=== Tic-Tac-Toe ===
Enter a position (1-9):
 1 | 2 | 3
-----------
 4 | 5 | 6
-----------
 7 | 8 | 9

Player X goes first. Enter position: 
 X |   |  
-----------
   |   |  
-----------
   |   |  

Player O's turn. Enter position: 
...
Player X's turn. Enter position: 
Player X wins! Congratulations!
```
Exit 0.

**Verify: nothing to prove.**
```bash
llmll verify ./tictactoe.llmll
```
```
   body-fallback: cell-at, set-cell, three-match?, build-prompt
   Running liquid-fixpoint ...
⚠️  ./tictactoe.llmll — SAFE (liquid-fixpoint), nothing proved: no function carries a postcondition
```
Exit 0. SAFE here means "no contradiction found", not "proved". With
`--trust-report`, all 15 functions are listed as `no contract`.
