# hangman_json: a console game in the JSON-AST surface

Hangman written directly as a JSON-AST (`hangman.ast.json`, schema 0.7.0), the
format agents emit. It is the statement-for-statement twin of
[`../hangman_sexp/`](../hangman_sexp/): same types, same 16 functions, same
`def-main :mode console` loop, and the built program prints byte-identical
output for the same input. It is also the worked example that
[`docs/getting-started.md`](../../docs/getting-started.md) uses for `holes`,
`test` and `build`.

This is a language and syntax example. No function carries a postcondition, so
the solver has nothing to prove (see [the examples index](../README.md#language-and-syntax)).

| File | What it is |
|---|---|
| `hangman.ast.json` | The whole game as a JSON-AST: an import, 3 refinement type declarations, 16 functions and a `def-main` |

## Commands (outputs reproduced against llmll 0.26.5)

Run these from this directory. The `.ast.json` extension selects the JSON-AST
reader. `verify` and `test` write a `.verified.json` sidecar next to the file,
so experiment on a copy.

**Check, holes, test.**
```bash
llmll check ./hangman.ast.json
llmll holes ./hangman.ast.json
llmll test  ./hangman.ast.json
```
```
✅ ./hangman.ast.json — OK (21 statements)
./hangman.ast.json — 0 holes (0 blocking)
./hangman.ast.json — 0 properties
  ✅ Passed:  0
  ❌ Failed:  0
  ⚠️  Skipped: 0
```
All exit 0. The program is complete (no holes) and declares no `check`
properties.

**Build and play.**
```bash
llmll build ./hangman.ast.json -o ./out
cd out && stack exec hangman
```
`build` ends with `stack build OK` and `OK Generated Haskell package: ./out`
(exit 0). The game reads one guess per line from stdin; the secret word is
`"hangman"` with 6 wrong guesses allowed. See
[`../hangman_sexp/README.md`](../hangman_sexp/README.md#commands-outputs-reproduced-against-llmll-0265)
for a scripted session.

**Verify: nothing to prove.**
```bash
llmll verify ./hangman.ast.json
```
```
   body-fallback: make-state, gallows-art
   Running liquid-fixpoint ...
⚠️  ./hangman.ast.json — SAFE (liquid-fixpoint), nothing proved: no function carries a postcondition
```
Exit 0. SAFE here means "no contradiction found", not "proved".
