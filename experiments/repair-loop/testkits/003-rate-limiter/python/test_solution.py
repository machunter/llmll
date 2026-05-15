"""Phase-1.75 harness tests for the 003-rate-limiter Python stub.

Coverage parallels the Go testkit and the harness-test list in
problems/003-rate-limiter.md. Tests are harness-owned (injected by the
orchestrator via targets/python.json `harness_files`); agents do NOT
write or modify this file.
"""
import pytest

from solution import (
    NegativeRefillRateError,
    NonPositiveCapacityError,
    allow,
    new_limiter,
    tokens,
)


def test_capacity_2_allows_two_same_tick_requests_and_denies_third():
    state = new_limiter(capacity=2, refill_rate=1)
    state, ok1 = allow(state, 0)
    state, ok2 = allow(state, 0)
    state, ok3 = allow(state, 0)
    assert (ok1, ok2, ok3) == (True, True, False)


def test_later_tick_refills_per_refill_rate():
    state = new_limiter(capacity=2, refill_rate=1)
    state, _ = allow(state, 0)
    state, _ = allow(state, 0)
    assert tokens(state) == 0
    # At tick 1, refill_rate=1 adds one token; the call consumes it.
    state, ok = allow(state, 1)
    assert ok is True


def test_large_tick_jump_does_not_exceed_capacity():
    state = new_limiter(capacity=2, refill_rate=1)
    state, _ = allow(state, 0)
    state, _ = allow(state, 0)
    assert tokens(state) == 0
    # Large tick jump refills well beyond capacity; the cap holds.
    state, ok = allow(state, 1_000_000)
    assert ok is True
    assert tokens(state) <= 2


def test_denied_request_same_tick_leaves_count_unchanged():
    state = new_limiter(capacity=2, refill_rate=1)
    state, _ = allow(state, 0)
    state, _ = allow(state, 0)
    assert tokens(state) == 0
    before = tokens(state)
    state, ok = allow(state, 0)
    assert ok is False
    assert tokens(state) == before


def test_three_same_tick_calls_no_refill_between():
    state = new_limiter(capacity=2, refill_rate=1)
    state, ok1 = allow(state, 0)
    t1 = tokens(state)
    state, ok2 = allow(state, 0)
    t2 = tokens(state)
    state, ok3 = allow(state, 0)
    t3 = tokens(state)
    assert (ok1, t1) == (True, 1)
    assert (ok2, t2) == (True, 0)
    assert (ok3, t3) == (False, 0)


def test_non_positive_capacity_rejected():
    for capacity in (0, -1, -100):
        with pytest.raises(NonPositiveCapacityError):
            new_limiter(capacity=capacity, refill_rate=1)


def test_negative_refill_rate_rejected():
    with pytest.raises(NegativeRefillRateError):
        new_limiter(capacity=2, refill_rate=-1)
