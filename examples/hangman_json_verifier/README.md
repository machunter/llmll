# hangman_json_verifier: Hangman with contracts the solver cannot reach

A separate Hangman program in the JSON-AST surface (schema 0.6.0), written with
contracts and `check` properties. It is not a copy of
[`../hangman_json/`](../hangman_json/): the state carries a refinement type
`MaxWrong = {n: int | n > 0}`, `all-guessed?` and `display-word` are recursive,
and three functions carry contracts:

- `make-state`: `pre` non-empty word and `max-wrong > 0`; `post` the initial wrong count is 0.
- `apply-guess`: `pre` wrong count `<=` max wrong.
- `gallows`: `pre` `0 <= wrong <= 6`.

No contract here is proved. The state is a nested `pair` and the accessors use
`second`, which are outside the decidable fragment, so the contracted bodies
fall back and their contracts are assumed (see
[the examples index](../README.md#language-and-syntax)). The Tic-Tac-Toe
counterpart is [`../tictactoe_json_verifier/`](../tictactoe_json_verifier/).

| File | What it is |
|---|---|
| `hangman.ast.json` | The game: 16 functions, 3 `check` properties, a `def-main :mode console` |
| `VERIFICATION_SCOPE.md` | Per-function contract classification and the verification boundary |

## Commands (outputs reproduced against llmll 0.26.5)

Run these from this directory. `verify` and `test` write a `.verified.json`
sidecar next to the file, so experiment on a copy.

**Verify: partial, 0 of 2 proved.**
```bash
llmll verify ./hangman.ast.json
```
```
   body-fallback: make-state, state-max-wrong, all-guessed?, apply-guess, display-word, gallows
   ⚠️  W-BODY-FALLBACK: 'make-state' fell back from body-faithful verification (body-outside-fragment), so its post is assumed and not proved. Refused by: pair.
   ⚠️  W-BODY-FALLBACK: 'state-max-wrong' fell back from body-faithful verification (body-outside-fragment), so its post is assumed and not proved. Refused by: app:second.
   Running liquid-fixpoint ...
⚠️  ./hangman.ast.json — SAFE (liquid-fixpoint), partial: 0 of 2 contracted functions proved; 2 assumed, not proved: make-state, state-max-wrong
   (--strict-verified-core fails on assumed functions)
```
Exit 0. `state-max-wrong` has no written `pre`/`post`; its result is the
state's `MaxWrong` field. With `--trust-report`, `make-state` is `asserted` on
both sides, `apply-guess` and `gallows` have an `asserted` pre, and
`all-guessed?` and `display-word` are listed as termination-unverified
recursion (no `(decreases …)` measure).

**Test: the `check` properties.**
```bash
llmll test ./hangman.ast.json
```
```
./hangman.ast.json — 3 properties
  ✅ Passed:  1
  ❌ Failed:  0
  ⚠️  Skipped: 2
```
Exit 0. `initial-wrong-count-is-0` passes on 100 samples. The two properties
that call `apply-guess` (`wrong-guess-increments-count`,
`correct-guess-no-increment`) are skipped: their bodies did not reduce to a
`bool` on any of 1000 samples, so no evidence was produced either way.

**Build and play.**
```bash
llmll build ./hangman.ast.json -o ./out
cd out && stack exec hangman
```
`build` exits 0. The game reads one guess per line; the word is `"hangman"`
with 6 wrong guesses allowed. Scripted with `printf 'h\nz\na\nn\ng\nm\n'`, it
prints `Good guess: 'h' is in the word!`, `Wrong: 'z' is not in the word.`,
and so on, and ends with `You won! Congratulations!` (exit 0).
