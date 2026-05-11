"""Phase-1.75 harness tests for the 002-bank-ledger Python stub.

Coverage parallels the Go testkit and the harness-test list in
problems/002-bank-ledger.md. Tests are harness-owned (injected by the
orchestrator via targets/python.json `harness_files`); agents do NOT
write or modify this file.
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


def test_transfer_preserves_total_balance_single_step():
    ledger = create_ledger({"alice": 1000, "bob": 500})
    before = total_balance(ledger)
    after = transfer(ledger, "alice", "bob", 250)
    assert total_balance(after) == before


def test_sequence_of_transfers_preserves_total_balance():
    ledger = create_ledger({"alice": 1000, "bob": 500, "carol": 200})
    before = total_balance(ledger)
    steps = [
        ("alice", "bob", 100),
        ("bob", "carol", 50),
        ("carol", "alice", 25),
        ("alice", "carol", 75),
    ]
    curr = ledger
    for frm, to, amount in steps:
        curr = transfer(curr, frm, to, amount)
        assert total_balance(curr) == before, f"after {(frm, to, amount)}"


def test_insufficient_funds_rejected():
    ledger = create_ledger({"alice": 100, "bob": 0})
    with pytest.raises(InsufficientFundsError):
        transfer(ledger, "alice", "bob", 250)


def test_insufficient_funds_leaves_ledger_unchanged():
    ledger = create_ledger({"alice": 100, "bob": 0})
    before_balances = dict(ledger.balances)
    before_log = ledger.log
    with pytest.raises(InsufficientFundsError):
        transfer(ledger, "alice", "bob", 250)
    # Frozen dataclass guarantees immutability, but the test asserts
    # the contract explicitly for cross-language symmetry with Go.
    assert dict(ledger.balances) == before_balances
    assert ledger.log == before_log


def test_missing_account_rejected():
    ledger = create_ledger({"alice": 100})
    with pytest.raises(MissingAccountError):
        transfer(ledger, "alice", "carol", 50)


def test_non_positive_amount_rejected():
    ledger = create_ledger({"alice": 100, "bob": 0})
    for amount in (0, -1, -100):
        with pytest.raises(NonPositiveAmountError):
            transfer(ledger, "alice", "bob", amount)
