"""Phase-1.75 harness tests for the 001-hangman Python stub.

Coverage parallels the Go testkit and the harness-test list in
problems/001-hangman.md. Tests are harness-owned (injected by the
orchestrator via targets/python.json `harness_files`); agents do NOT
write or modify this file.
"""
from solution import (
    apply_guess,
    game_status,
    initialize_game,
    render_state,
)


def test_banana_correct_a_renders_revealed_positions():
    state = initialize_game("banana")
    state = apply_guess(state, "a")
    assert render_state(state) == "_ a _ a _ a"


def test_repeated_wrong_guess_consumes_at_most_one_attempt():
    state = initialize_game("banana")
    before = state.remaining
    state = apply_guess(state, "x")
    state = apply_guess(state, "x")
    # Two wrong guesses on the same letter consume at most one attempt total
    # (the second is a repeat and is ignored).
    assert before - state.remaining == 1


def test_six_distinct_wrong_guesses_lose_the_game():
    state = initialize_game("banana")
    for letter in ("x", "y", "z", "q", "r", "s"):
        state = apply_guess(state, letter)
    assert state.remaining == 0
    assert game_status(state) == "lost"


def test_guessing_all_unique_letters_wins_the_game():
    state = initialize_game("banana")
    # `banana` has unique letters {b, a, n}.
    for letter in ("b", "a", "n"):
        state = apply_guess(state, letter)
    assert game_status(state) == "won"


def test_guessing_after_terminal_leaves_state_unchanged():
    won = initialize_game("ab")
    won = apply_guess(won, "a")
    won = apply_guess(won, "b")
    assert game_status(won) == "won"
    after_won = apply_guess(won, "c")
    assert after_won == won

    lost = initialize_game("xyz")
    for letter in ("a", "b", "c", "d", "e", "f"):
        lost = apply_guess(lost, letter)
    assert game_status(lost) == "lost"
    after_lost = apply_guess(lost, "x")
    assert after_lost == lost
