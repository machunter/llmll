# hangman_sexp: a console game in the S-expression surface

Hangman written in LLMLL's S-expression syntax: refinement type declarations
(`Word`, `Letter`, `GuessCount`), a nested-pair game state, list and string
builtins, and a `def-main :mode console` loop with `:init`, `:step`, `:done?`
and `:on-done`. The same program in the JSON-AST surface is
[`../hangman_json/`](../hangman_json/).

This is a language and syntax example. No function carries a postcondition, so
the solver has nothing to prove (see [the examples index](../README.md#language-and-syntax)).

| File | What it is |
|---|---|
| `hangman.llmll` | The whole game: 16 functions and a `def-main`. The secret word is `"hangman"`, 6 wrong guesses allowed |

## Commands (outputs reproduced against llmll 0.26.5)

Run these from this directory. `verify` writes a `.verified.json` sidecar next
to the file, so experiment on a copy.

**Check and build.**
```bash
llmll check ./hangman.llmll
llmll build ./hangman.llmll -o ./out
```
```
✅ ./hangman.llmll — OK (21 statements)
...
   stack build OK
OK Generated Haskell package: ./out
```
Both exit 0. `build` writes a Stack package (`package.yaml`, `src/Lib.hs`,
`src/Main.hs`) and builds it.

**Play.** The program reads one guess per line from stdin:
```bash
cd out && stack exec hangman
```
Scripted with `printf 'h\nz\na\nn\ng\nm\n' | stack exec hangman`, the first
turns print:
```
=== HANGMAN ===
 -----
 |   |
 |
 |
 |
 |
-+----

Word: _ _ _ _ _ _ _
Wrong guesses: 0 / 6  (6 remaining)

Guess a letter: Good guess!
...
Word: h _ _ _ _ _ _
Wrong guesses: 0 / 6  (6 remaining)
Guess a letter: 
Wrong!
```
and the game ends with `You won! The word was: hangman` (exit 0).

**Verify: nothing to prove.**
```bash
llmll verify ./hangman.llmll
```
```
   body-fallback: make-state, gallows-art
   Running liquid-fixpoint ...
⚠️  ./hangman.llmll — SAFE (liquid-fixpoint), nothing proved: no function carries a postcondition
```
Exit 0. SAFE here means "no contradiction found", not "proved". With
`--trust-report`, all 16 functions are listed as `no contract`.
