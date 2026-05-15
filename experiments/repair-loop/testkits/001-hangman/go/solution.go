// Phase-1.75 stub hangman solution for Go adapter validation.
//
// Module-mode upgrade: paired with go.mod and solution_test.go (both
// harness-owned via targets/go.json `harness_files`). Verifier chain
// runs `go vet ./...`, `go build ./...`, `go test ./...`. Not the
// canonical Phase-2/3 solution — agents will write their own.
//
// Naming convention: `Status` is the enum type (avoids collision with
// the `GameStatus` function); `GameStatus(state)` is the API accessor.
package main

import (
	"fmt"
	"strings"
)

type Status string

const (
	StatusPlaying Status = "playing"
	StatusWon     Status = "won"
	StatusLost    Status = "lost"
)

type GameState struct {
	Secret    string
	Guessed   map[rune]bool
	Remaining int
	Status    Status
}

func InitializeGame(secret string) *GameState {
	return &GameState{
		Secret:    strings.ToLower(secret),
		Guessed:   map[rune]bool{},
		Remaining: 6,
		Status:    StatusPlaying,
	}
}

func ApplyGuess(state *GameState, guess string) *GameState {
	if state.Status != StatusPlaying {
		return state
	}
	runes := []rune(strings.ToLower(guess))
	if len(runes) == 0 {
		return state
	}
	letter := runes[0]
	if state.Guessed[letter] {
		return state
	}
	newGuessed := make(map[rune]bool, len(state.Guessed)+1)
	for k, v := range state.Guessed {
		newGuessed[k] = v
	}
	newGuessed[letter] = true

	if strings.ContainsRune(state.Secret, letter) {
		allRevealed := true
		for _, c := range state.Secret {
			if !newGuessed[c] {
				allRevealed = false
				break
			}
		}
		status := StatusPlaying
		if allRevealed {
			status = StatusWon
		}
		return &GameState{
			Secret:    state.Secret,
			Guessed:   newGuessed,
			Remaining: state.Remaining,
			Status:    status,
		}
	}

	newRemaining := state.Remaining - 1
	status := StatusPlaying
	if newRemaining <= 0 {
		status = StatusLost
	}
	return &GameState{
		Secret:    state.Secret,
		Guessed:   newGuessed,
		Remaining: newRemaining,
		Status:    status,
	}
}

func RenderState(state *GameState) string {
	var b strings.Builder
	for i, c := range state.Secret {
		if i > 0 {
			b.WriteString(" ")
		}
		if state.Guessed[c] {
			b.WriteRune(c)
		} else {
			b.WriteString("_")
		}
	}
	return b.String()
}

func GameStatus(state *GameState) Status {
	return state.Status
}

func main() {
	// Smoke main: not exercised by the harness. Exists only so `go build`
	// in package-main mode produces an executable.
	state := InitializeGame("banana")
	state = ApplyGuess(state, "a")
	fmt.Println(RenderState(state))
}
