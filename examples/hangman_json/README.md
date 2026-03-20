# Hangman JSON-AST Example

This directory contains a version of the Hangman game implemented entirely in LLMLL JSON-AST format.

## Files

- `hangman.ast.json`: The complete game logic, types, and CLI interaction defined as a structured JSON AST.

## Playing the Game

To play the game, follow these steps:

1.  **Build the project:**
    ```bash
    cd compiler
    stack exec llmll -- build ../examples/hangman_json/hangman.ast.json -o ../generated/hangman_json
    ```

2.  **Run the game:**
    ```bash
    cd generated/hangman_json
    stack build
    stack exec hangman-json-exe
    ```

## Game Logic

The game uses the standard LLMLL `(State, Input) -> (NewState, Command)` pattern for CLI interaction.

- **Initial State:** Created via `start-game`.
- **Game Loop:** Managed by `game-loop`, which takes user input and returns the next state and a stdout command.
- **Victory/Defeat:** The game ends when all letters are guessed or the maximum number of wrong guesses (6) is reached.
