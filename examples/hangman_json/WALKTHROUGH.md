# Hangman — JSON-AST Version Walkthrough

## What was built

A fully playable Hangman game in LLMLL JSON-AST format (`hangman.ast.json`).
The word is fixed as `"hangman"` with 6 wrong guesses allowed.

**Game features:**
- 7-stage ASCII gallows art (0–6 wrong guesses)
- Progressive word reveal (`_` for unguessed letters)
- Guessed-letter tracking (no penalty for duplicates)
- Win and lose detection with end messages
- Input validation (rejects multi-character input)

## Compilation

```bash
# Type-check
cd compiler
stack exec llmll -- check ../examples/hangman_json/hangman.ast.json
# ✅ OK (no output = success)

# Generate Haskell (--emit-only avoids Stack lock deadlock)
stack exec llmll -- build ../examples/hangman_json/hangman.ast.json \
  -o ../generated/hangman_json --emit-only
# ✅ OK Generated Haskell package from JSON-AST: ../generated/hangman_json

# Build the executable
cd ../generated/hangman_json && stack build
# ✅ OK

# Run — win path
printf 'h\na\nn\ng\nm\na\n' | stack exec hangman
# ✅ Word reveals progressively; "You won! Congratulations!" on final guess

# Run — lose path
printf 'z\nx\nq\nw\nv\nb\n' | stack exec hangman
# ✅ Gallows fills stage by stage; "Game over! The word was: hangman"
```

## Design decisions

**State representation:** Nested pairs `(word, (guessed, (wrong-count, max-wrong)))`.
LLMLL v0.1.x has no record syntax, so 4-field state requires 3 levels of nesting.
Named accessor functions (`state-word`, `state-guessed`, `state-wrong`, `state-max`) keep
usage readable.

**No duplicate penalty:** `process-guess` checks `list-contains` before appending or
incrementing wrong-count. Already-guessed letters are silently re-accepted without cost.

**`def-main` init:** Per `getting-started.md §4.6`, `:init` must be a zero-arg function
call `{ "kind": "app", "fn": "start-game", "args": [] }`, not a variable reference.

**`string-trim` on input:** The console harness pipes raw lines including `\n`. Using
`string-trim` before checking `string-length == 1` ensures the newline is stripped.

## Problems encountered

### P1 — Stack lock deadlock (`UE+` processes)

**Symptom:** After running `llmll build` from within an active `stack exec llmll -- repl`
or other `stack exec` session, subsequent `stack exec llmll -- test` calls entered
uninterruptible sleep (`UE+`) and could not be killed with `kill -9`.

**Root cause:** Both processes competed for the GHC package cache lock
(`package.cache.lock`). The OS enters uninterruptible sleep waiting for the lock — this
state is immune to signals including `SIGKILL`.

**Workaround used:** `--emit-only` flag on `llmll build` skips the internal `stack build`
call, breaking the lock contention. The `stack build` is then run separately in the
generated output directory.

**Resolution:** The parent zsh shells (PIDs 78819 and 84429) were killed to close the
terminal pseudodevices, allowing the orphaned processes to eventually be reaped.
The `--emit-only` pattern should be used whenever `llmll build` is called from inside
a running stack session.

**Compiler team note:** The `test` subcommand has no `--emit-only` equivalent. The same
deadlock can occur with `llmll test`. Consider adding a `--no-stack` or `--emit-only`
flag to `test` as well.

### P2 — `done?` check renders board twice on win/loss

**Symptom:** The board (and win/loss message) can print twice on game-over.

**Root cause:** The console harness checks `:done?` **at the top** of the next
iteration. When `game-loop` includes the end-of-game message inside its `Command`,
that message prints once during `:step`. On the next iteration `:done?` fires and
the loop exits — but if `game-loop` also re-renders the board as part of its
`Command`, the board appears a second time.

**Resolution — use `:on-done` for terminal output:**

Move all end-of-game printing into a dedicated `show-result` function and declare
it via `:on-done`. `game-loop` should then only print the in-progress board on
every turn. This is the **canonical pattern** (see `LLMLL.md §9.5`):

```lisp
(def-main
  :mode    console
  :init    (start-game "hangman")
  :step    game-loop        ;; prints board only — never the end message
  :done?   is-game-over?
  :on-done show-result)     ;; called exactly once with the final state
```

`show-result` has signature `State -> Command` and prints the final
"You won!" / "Game over!" line. It fires **after** the last `:step` and
**exactly once**, eliminating the double-render entirely.

## Property-based tests

```bash
stack exec llmll -- test ../examples/hangman_json/hangman.ast.json
# ✅ (no output = all passed)
```

4 check blocks were defined (all with empty `for-all` bindings — static assertions):

| Check | Passes |
|-------|--------|
| `game-not-over-at-start` | ✅ |
| `game-lost-at-max-wrong` | ✅ |
| `game-won-only-when-all-letters-guessed` | ✅ |
| `game-won-with-all-letters` | ✅ |
