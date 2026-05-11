"""Phase-1.5 smoke tests for the bank-ledger Python stub.

Not the full testkit — Phase-1.75 will expand to the canonical harness suite
listed in problems/002-bank-ledger.md. These tests exist to validate that
the pytest path through the orchestrator wires correctly.
"""
import pytest

from solution import (
    InsufficientFundsError,
    MissingAccountError,
    NonPositiveAmountError,
    balance,
    create_ledger,
    total_balance,
    transfer,
)


def test_create_ledger_preserves_balances():
    ledger = create_ledger({"alice": 1000, "bob": 500})
    assert balance(ledger, "alice") == 1000
    assert balance(ledger, "bob") == 500


def test_successful_transfer_updates_both_accounts():
    ledger = create_ledger({"alice": 1000, "bob": 500})
    after = transfer(ledger, "alice", "bob", 250)
    assert balance(after, "alice") == 750
    assert balance(after, "bob") == 750


def test_transfer_preserves_total_balance():
    ledger = create_ledger({"alice": 1000, "bob": 500})
    before = total_balance(ledger)
    after = transfer(ledger, "alice", "bob", 250)
    assert total_balance(after) == before


def test_insufficient_funds_rejected():
    ledger = create_ledger({"alice": 100, "bob": 0})
    with pytest.raises(InsufficientFundsError):
        transfer(ledger, "alice", "bob", 250)


def test_missing_account_rejected():
    ledger = create_ledger({"alice": 100})
    with pytest.raises(MissingAccountError):
        transfer(ledger, "alice", "carol", 50)


def test_non_positive_amount_rejected():
    ledger = create_ledger({"alice": 100, "bob": 0})
    with pytest.raises(NonPositiveAmountError):
        transfer(ledger, "alice", "bob", 0)
    with pytest.raises(NonPositiveAmountError):
        transfer(ledger, "alice", "bob", -50)
