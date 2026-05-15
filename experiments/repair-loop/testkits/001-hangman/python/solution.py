"""Phase-1.75 stub hangman solution for Python adapter validation.

Minimal working implementation: satisfies the 001-hangman API surface
with correct types and basic invariants, passes pyright (strict-mode off)
and the colocated harness tests. Not the canonical Phase-2/3 solution —
agents will write their own. Used here only to validate that the Python
target adapter wires pyright and pytest through the orchestrator without
schema-coupling defects.
"""
from __future__ import annotations

from dataclasses import dataclass, field, replace
from typing import Literal


GameStatus = Literal["playing", "won", "lost"]


@dataclass(frozen=True)
class GameState:
    secret: str
    guessed: frozenset[str] = field(default_factory=frozenset)
    remaining: int = 6
    status: GameStatus = "playing"


def initialize_game(secret: str) -> GameState:
    return GameState(secret=secret.lower())


def apply_guess(state: GameState, guess: str) -> GameState:
    if state.status != "playing":
        return state
    letter = guess.lower()
    if letter in state.guessed:
        return state
    new_guessed = state.guessed | {letter}
    if letter in state.secret:
        secret_letters = frozenset(state.secret)
        all_revealed = secret_letters <= new_guessed
        new_status: GameStatus = "won" if all_revealed else "playing"
        return replace(state, guessed=new_guessed, status=new_status)
    new_remaining = state.remaining - 1
    lost_status: GameStatus = "lost" if new_remaining <= 0 else "playing"
    return replace(
        state, guessed=new_guessed, remaining=new_remaining, status=lost_status
    )


def render_state(state: GameState) -> str:
    return " ".join(c if c in state.guessed else "_" for c in state.secret)


def game_status(state: GameState) -> GameStatus:
    return state.status
