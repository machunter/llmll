// Phase-1.75 stub bank-ledger solution for Go adapter validation.
//
// Module-mode upgrade from Phase-1.5: paired with go.mod and
// solution_test.go (both harness-owned via targets/go.json
// `harness_files`). Verifier chain runs `go vet ./...`, `go build ./...`,
// `go test ./...`. Not the canonical Phase-2/3 solution — agents will
// write their own.
package main

import (
	"errors"
	"fmt"
)

type Ledger struct {
	balances map[string]int64
	log      []TransferRecord
}

type TransferRecord struct {
	From   string
	To     string
	Amount int64
}

var (
	ErrMissingAccount    = errors.New("account does not exist")
	ErrInsufficientFunds = errors.New("source account has insufficient funds")
	ErrNonPositiveAmount = errors.New("transfer amount must be positive")
)

func CreateLedger(initial map[string]int64) *Ledger {
	bal := make(map[string]int64, len(initial))
	for k, v := range initial {
		bal[k] = v
	}
	return &Ledger{balances: bal, log: nil}
}

func Balance(l *Ledger, accountID string) (int64, error) {
	b, ok := l.balances[accountID]
	if !ok {
		return 0, ErrMissingAccount
	}
	return b, nil
}

func Transfer(l *Ledger, from, to string, amount int64) (*Ledger, error) {
	if amount <= 0 {
		return nil, ErrNonPositiveAmount
	}
	fromBal, ok := l.balances[from]
	if !ok {
		return nil, ErrMissingAccount
	}
	if _, ok := l.balances[to]; !ok {
		return nil, ErrMissingAccount
	}
	if fromBal < amount {
		return nil, ErrInsufficientFunds
	}
	newBalances := make(map[string]int64, len(l.balances))
	for k, v := range l.balances {
		newBalances[k] = v
	}
	newBalances[from] -= amount
	newBalances[to] += amount
	newLog := append([]TransferRecord(nil), l.log...)
	newLog = append(newLog, TransferRecord{From: from, To: to, Amount: amount})
	return &Ledger{balances: newBalances, log: newLog}, nil
}

func TotalBalance(l *Ledger) int64 {
	var sum int64
	for _, v := range l.balances {
		sum += v
	}
	return sum
}

func main() {
	// Smoke main: not exercised by the harness. Exists only so `go build`
	// in package-main mode produces an executable.
	l := CreateLedger(map[string]int64{"alice": 1000, "bob": 500})
	fmt.Println("total:", TotalBalance(l))
}
