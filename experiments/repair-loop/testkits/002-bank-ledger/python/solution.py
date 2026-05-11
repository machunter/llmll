"""Phase-1.5 stub bank-ledger solution for Python adapter validation.

Minimal working implementation: satisfies the 002-bank-ledger API surface
with correct types and basic invariants, passes pyright (strict-mode off)
and the colocated smoke test. Not the canonical Phase-2/3 solution — agents
will write their own. Used here only to validate that the Python target
adapter wires pyright and pytest through the orchestrator without
schema-coupling defects.
"""
from __future__ import annotations

from dataclasses import dataclass, field, replace
from typing import Mapping


@dataclass(frozen=True)
class Transfer:
    from_account: str
    to_account: str
    amount: int


@dataclass(frozen=True)
class Ledger:
    balances: Mapping[str, int]
    log: tuple[Transfer, ...] = field(default_factory=tuple)


class LedgerError(Exception):
    """Base class for transfer/balance failures."""


class MissingAccountError(LedgerError):
    pass


class InsufficientFundsError(LedgerError):
    pass


class NonPositiveAmountError(LedgerError):
    pass


def create_ledger(initial: Mapping[str, int]) -> Ledger:
    return Ledger(balances=dict(initial), log=())


def balance(ledger: Ledger, account_id: str) -> int:
    if account_id not in ledger.balances:
        raise MissingAccountError(account_id)
    return ledger.balances[account_id]


def transfer(
    ledger: Ledger, from_account: str, to_account: str, amount: int
) -> Ledger:
    if amount <= 0:
        raise NonPositiveAmountError(amount)
    if from_account not in ledger.balances:
        raise MissingAccountError(from_account)
    if to_account not in ledger.balances:
        raise MissingAccountError(to_account)
    if ledger.balances[from_account] < amount:
        raise InsufficientFundsError(amount)
    new_balances = dict(ledger.balances)
    new_balances[from_account] -= amount
    new_balances[to_account] += amount
    new_log = ledger.log + (Transfer(from_account, to_account, amount),)
    return replace(ledger, balances=new_balances, log=new_log)


def total_balance(ledger: Ledger) -> int:
    return sum(ledger.balances.values())
