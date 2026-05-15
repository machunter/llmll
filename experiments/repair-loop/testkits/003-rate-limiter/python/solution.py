"""Phase-1.75 stub token-bucket rate-limiter solution for Python adapter validation.

Minimal working implementation: satisfies the 003-rate-limiter API surface
with correct types and basic invariants, passes pyright (strict-mode off)
and the colocated harness tests. Not the canonical Phase-2/3 solution —
agents will write their own.
"""
from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class LimiterState:
    capacity: int
    tokens: int
    refill_rate: int
    last_tick: int


class LimiterError(ValueError):
    """Base class for limiter construction failures."""


class NonPositiveCapacityError(LimiterError):
    pass


class NegativeRefillRateError(LimiterError):
    pass


def new_limiter(capacity: int, refill_rate: int) -> LimiterState:
    if capacity <= 0:
        raise NonPositiveCapacityError(capacity)
    if refill_rate < 0:
        raise NegativeRefillRateError(refill_rate)
    return LimiterState(
        capacity=capacity,
        tokens=capacity,
        refill_rate=refill_rate,
        last_tick=0,
    )


def allow(state: LimiterState, tick: int) -> tuple[LimiterState, bool]:
    delta_ticks = tick - state.last_tick
    if delta_ticks < 0:
        delta_ticks = 0
    refilled = state.tokens + delta_ticks * state.refill_rate
    if refilled > state.capacity:
        refilled = state.capacity
    new_tick = tick if tick >= state.last_tick else state.last_tick
    if refilled >= 1:
        return (
            LimiterState(
                capacity=state.capacity,
                tokens=refilled - 1,
                refill_rate=state.refill_rate,
                last_tick=new_tick,
            ),
            True,
        )
    return (
        LimiterState(
            capacity=state.capacity,
            tokens=refilled,
            refill_rate=state.refill_rate,
            last_tick=new_tick,
        ),
        False,
    )


def tokens(state: LimiterState) -> int:
    return state.tokens
