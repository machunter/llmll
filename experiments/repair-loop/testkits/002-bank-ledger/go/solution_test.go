// Phase-1.75 harness tests for the 002-bank-ledger Go stub.
//
// Coverage parallels the Python testkit and the harness-test list in
// problems/002-bank-ledger.md. Tests are harness-owned (injected by the
// orchestrator via targets/go.json `harness_files`); agents do NOT write
// or modify this file.
package main

import (
	"errors"
	"reflect"
	"testing"
)

func mustBalance(t *testing.T, l *Ledger, account string, want int64) {
	t.Helper()
	got, err := Balance(l, account)
	if err != nil {
		t.Fatalf("Balance(%q): unexpected error %v", account, err)
	}
	if got != want {
		t.Fatalf("Balance(%q): got %d, want %d", account, got, want)
	}
}

func TestCreateLedgerPreservesBalances(t *testing.T) {
	l := CreateLedger(map[string]int64{"alice": 1000, "bob": 500})
	mustBalance(t, l, "alice", 1000)
	mustBalance(t, l, "bob", 500)
}

func TestSuccessfulTransferUpdatesBothAccounts(t *testing.T) {
	l := CreateLedger(map[string]int64{"alice": 1000, "bob": 500})
	after, err := Transfer(l, "alice", "bob", 250)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	mustBalance(t, after, "alice", 750)
	mustBalance(t, after, "bob", 750)
}

func TestTransferPreservesTotalBalanceSingleStep(t *testing.T) {
	l := CreateLedger(map[string]int64{"alice": 1000, "bob": 500})
	before := TotalBalance(l)
	after, err := Transfer(l, "alice", "bob", 250)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got := TotalBalance(after); got != before {
		t.Fatalf("total balance: got %d, want %d", got, before)
	}
}

func TestSequenceOfTransfersPreservesTotalBalance(t *testing.T) {
	l := CreateLedger(map[string]int64{"alice": 1000, "bob": 500, "carol": 200})
	before := TotalBalance(l)
	steps := []struct{ from, to string; amount int64 }{
		{"alice", "bob", 100},
		{"bob", "carol", 50},
		{"carol", "alice", 25},
		{"alice", "carol", 75},
	}
	curr := l
	for _, s := range steps {
		next, err := Transfer(curr, s.from, s.to, s.amount)
		if err != nil {
			t.Fatalf("transfer %v: unexpected error %v", s, err)
		}
		if got := TotalBalance(next); got != before {
			t.Fatalf("after %v: total %d, want %d", s, got, before)
		}
		curr = next
	}
}

func TestInsufficientFundsRejected(t *testing.T) {
	l := CreateLedger(map[string]int64{"alice": 100, "bob": 0})
	_, err := Transfer(l, "alice", "bob", 250)
	if !errors.Is(err, ErrInsufficientFunds) {
		t.Fatalf("got error %v, want ErrInsufficientFunds", err)
	}
}

func TestInsufficientFundsLeavesLedgerUnchanged(t *testing.T) {
	l := CreateLedger(map[string]int64{"alice": 100, "bob": 0})
	beforeBalances := map[string]int64{"alice": 100, "bob": 0}
	_, err := Transfer(l, "alice", "bob", 250)
	if err == nil {
		t.Fatalf("expected error, got nil")
	}
	// Original ledger must be unmodified.
	if !reflect.DeepEqual(l.balances, beforeBalances) {
		t.Fatalf("ledger mutated on failed transfer: %v", l.balances)
	}
	if len(l.log) != 0 {
		t.Fatalf("log gained entry on failed transfer: %v", l.log)
	}
}

func TestMissingAccountRejected(t *testing.T) {
	l := CreateLedger(map[string]int64{"alice": 100})
	_, err := Transfer(l, "alice", "carol", 50)
	if !errors.Is(err, ErrMissingAccount) {
		t.Fatalf("got error %v, want ErrMissingAccount", err)
	}
}

func TestNonPositiveAmountRejected(t *testing.T) {
	l := CreateLedger(map[string]int64{"alice": 100, "bob": 0})
	for _, amount := range []int64{0, -1, -100} {
		_, err := Transfer(l, "alice", "bob", amount)
		if !errors.Is(err, ErrNonPositiveAmount) {
			t.Fatalf("amount=%d: got error %v, want ErrNonPositiveAmount", amount, err)
		}
	}
}
