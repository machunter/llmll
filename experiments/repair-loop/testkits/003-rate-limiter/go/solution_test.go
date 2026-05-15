// Phase-1.75 harness tests for the 003-rate-limiter Go stub.
//
// Coverage parallels the Python testkit and the harness-test list in
// problems/003-rate-limiter.md. Tests are harness-owned (injected by the
// orchestrator via targets/go.json `harness_files`); agents do NOT write
// or modify this file.
package main

import (
	"errors"
	"testing"
)

func TestCapacity2AllowsTwoSameTickRequestsAndDeniesThird(t *testing.T) {
	state, err := NewLimiter(2, 1)
	if err != nil {
		t.Fatalf("NewLimiter: %v", err)
	}
	state, ok1 := Allow(state, 0)
	state, ok2 := Allow(state, 0)
	state, ok3 := Allow(state, 0)
	if ok1 != true || ok2 != true || ok3 != false {
		t.Fatalf("allow sequence: got (%v, %v, %v), want (true, true, false)", ok1, ok2, ok3)
	}
	_ = state
}

func TestLaterTickRefillsPerRefillRate(t *testing.T) {
	state, _ := NewLimiter(2, 1)
	state, _ = Allow(state, 0)
	state, _ = Allow(state, 0)
	if got := Tokens(state); got != 0 {
		t.Fatalf("tokens after exhaustion: got %d, want 0", got)
	}
	state, ok := Allow(state, 1)
	if !ok {
		t.Fatalf("allow at tick 1 with refill_rate=1: got denied, want allowed")
	}
	_ = state
}

func TestLargeTickJumpDoesNotExceedCapacity(t *testing.T) {
	state, _ := NewLimiter(2, 1)
	state, _ = Allow(state, 0)
	state, _ = Allow(state, 0)
	if got := Tokens(state); got != 0 {
		t.Fatalf("tokens after exhaustion: got %d, want 0", got)
	}
	state, ok := Allow(state, 1_000_000)
	if !ok {
		t.Fatalf("allow at tick 1_000_000: got denied, want allowed")
	}
	if got := Tokens(state); got > 2 {
		t.Fatalf("tokens after large tick jump: got %d, want <= 2", got)
	}
}

func TestDeniedRequestSameTickLeavesCountUnchanged(t *testing.T) {
	state, _ := NewLimiter(2, 1)
	state, _ = Allow(state, 0)
	state, _ = Allow(state, 0)
	before := Tokens(state)
	state, ok := Allow(state, 0)
	if ok {
		t.Fatalf("expected deny, got allow")
	}
	if got := Tokens(state); got != before {
		t.Fatalf("tokens after denied same-tick call: got %d, want %d", got, before)
	}
}

func TestThreeSameTickCallsNoRefillBetween(t *testing.T) {
	state, _ := NewLimiter(2, 1)
	state, ok1 := Allow(state, 0)
	t1 := Tokens(state)
	state, ok2 := Allow(state, 0)
	t2 := Tokens(state)
	state, ok3 := Allow(state, 0)
	t3 := Tokens(state)
	if ok1 != true || t1 != 1 {
		t.Fatalf("call 1: got (allow=%v, tokens=%d), want (true, 1)", ok1, t1)
	}
	if ok2 != true || t2 != 0 {
		t.Fatalf("call 2: got (allow=%v, tokens=%d), want (true, 0)", ok2, t2)
	}
	if ok3 != false || t3 != 0 {
		t.Fatalf("call 3: got (allow=%v, tokens=%d), want (false, 0)", ok3, t3)
	}
}

func TestNonPositiveCapacityRejected(t *testing.T) {
	for _, capacity := range []int64{0, -1, -100} {
		_, err := NewLimiter(capacity, 1)
		if !errors.Is(err, ErrNonPositiveCapacity) {
			t.Fatalf("capacity=%d: got error %v, want ErrNonPositiveCapacity", capacity, err)
		}
	}
}

func TestNegativeRefillRateRejected(t *testing.T) {
	_, err := NewLimiter(2, -1)
	if !errors.Is(err, ErrNegativeRefillRate) {
		t.Fatalf("got error %v, want ErrNegativeRefillRate", err)
	}
}
