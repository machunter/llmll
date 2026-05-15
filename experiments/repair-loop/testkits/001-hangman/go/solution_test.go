// Phase-1.75 harness tests for the 001-hangman Go stub.
//
// Coverage parallels the Python testkit and the harness-test list in
// problems/001-hangman.md. Tests are harness-owned (injected by the
// orchestrator via targets/go.json `harness_files`); agents do NOT write
// or modify this file.
package main

import (
	"testing"
)

func TestBananaCorrectARendersRevealedPositions(t *testing.T) {
	state := InitializeGame("banana")
	state = ApplyGuess(state, "a")
	if got, want := RenderState(state), "_ a _ a _ a"; got != want {
		t.Fatalf("render: got %q, want %q", got, want)
	}
}

func TestRepeatedWrongGuessConsumesAtMostOneAttempt(t *testing.T) {
	state := InitializeGame("banana")
	before := state.Remaining
	state = ApplyGuess(state, "x")
	state = ApplyGuess(state, "x")
	if delta := before - state.Remaining; delta != 1 {
		t.Fatalf("remaining decrement on repeated wrong guess: got %d, want 1", delta)
	}
}

func TestSixDistinctWrongGuessesLoseTheGame(t *testing.T) {
	state := InitializeGame("banana")
	for _, letter := range []string{"x", "y", "z", "q", "r", "s"} {
		state = ApplyGuess(state, letter)
	}
	if state.Remaining != 0 {
		t.Fatalf("remaining: got %d, want 0", state.Remaining)
	}
	if GameStatus(state) != StatusLost {
		t.Fatalf("status: got %q, want %q", GameStatus(state), StatusLost)
	}
}

func TestGuessingAllUniqueLettersWinsTheGame(t *testing.T) {
	state := InitializeGame("banana")
	for _, letter := range []string{"b", "a", "n"} {
		state = ApplyGuess(state, letter)
	}
	if GameStatus(state) != StatusWon {
		t.Fatalf("status: got %q, want %q", GameStatus(state), StatusWon)
	}
}

func TestGuessingAfterTerminalLeavesStateUnchanged(t *testing.T) {
	won := InitializeGame("ab")
	won = ApplyGuess(won, "a")
	won = ApplyGuess(won, "b")
	if GameStatus(won) != StatusWon {
		t.Fatalf("setup failed: status %q, want %q", GameStatus(won), StatusWon)
	}
	afterWon := ApplyGuess(won, "c")
	if afterWon != won {
		t.Fatalf("guess after won mutated state: %+v vs %+v", afterWon, won)
	}

	lost := InitializeGame("xyz")
	for _, letter := range []string{"a", "b", "c", "d", "e", "f"} {
		lost = ApplyGuess(lost, letter)
	}
	if GameStatus(lost) != StatusLost {
		t.Fatalf("setup failed: status %q, want %q", GameStatus(lost), StatusLost)
	}
	afterLost := ApplyGuess(lost, "x")
	if afterLost != lost {
		t.Fatalf("guess after lost mutated state: %+v vs %+v", afterLost, lost)
	}
}
