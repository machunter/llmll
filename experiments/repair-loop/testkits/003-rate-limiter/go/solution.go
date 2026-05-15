// Phase-1.75 stub token-bucket rate-limiter solution for Go adapter validation.
//
// Module-mode upgrade: paired with go.mod and solution_test.go (both
// harness-owned via targets/go.json `harness_files`). Verifier chain
// runs `go vet ./...`, `go build ./...`, `go test ./...`. Not the
// canonical Phase-2/3 solution — agents will write their own.
package main

import (
	"errors"
	"fmt"
)

type LimiterState struct {
	Capacity   int64
	Tokens     int64
	RefillRate int64
	LastTick   int64
}

var (
	ErrNonPositiveCapacity = errors.New("capacity must be positive")
	ErrNegativeRefillRate  = errors.New("refill_rate must be non-negative")
)

func NewLimiter(capacity, refillRate int64) (*LimiterState, error) {
	if capacity <= 0 {
		return nil, ErrNonPositiveCapacity
	}
	if refillRate < 0 {
		return nil, ErrNegativeRefillRate
	}
	return &LimiterState{
		Capacity:   capacity,
		Tokens:     capacity,
		RefillRate: refillRate,
		LastTick:   0,
	}, nil
}

func Allow(state *LimiterState, tick int64) (*LimiterState, bool) {
	deltaTicks := tick - state.LastTick
	if deltaTicks < 0 {
		deltaTicks = 0
	}
	refilled := state.Tokens + deltaTicks*state.RefillRate
	if refilled > state.Capacity {
		refilled = state.Capacity
	}
	newTick := tick
	if newTick < state.LastTick {
		newTick = state.LastTick
	}
	if refilled >= 1 {
		return &LimiterState{
			Capacity:   state.Capacity,
			Tokens:     refilled - 1,
			RefillRate: state.RefillRate,
			LastTick:   newTick,
		}, true
	}
	return &LimiterState{
		Capacity:   state.Capacity,
		Tokens:     refilled,
		RefillRate: state.RefillRate,
		LastTick:   newTick,
	}, false
}

func Tokens(state *LimiterState) int64 {
	return state.Tokens
}

func main() {
	// Smoke main: not exercised by the harness. Exists only so `go build`
	// in package-main mode produces an executable.
	l, _ := NewLimiter(2, 1)
	l, ok := Allow(l, 0)
	fmt.Println("first allow:", ok, "tokens:", Tokens(l))
}
