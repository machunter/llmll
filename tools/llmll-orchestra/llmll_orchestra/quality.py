"""
quality.py — Quality heuristics for Lead Agent plan validation.

Checks architecture plans for common issues before skeleton generation.

v0.4: Sprint 2 Task 5.
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass
class QualityResult:
    """Result of a single quality heuristic check."""
    heuristic: str
    message: str
    blocking: bool  # True = must fix before proceeding


def check_plan_quality(plan: dict) -> list[QualityResult]:
    """Run all quality heuristics on a plan.

    Returns a list of QualityResult objects. Blocking results must be
    fixed before the plan can proceed to skeleton generation.
    """
    results: list[QualityResult] = []
    results.extend(_check_all_string_types(plan))
    results.extend(_check_unassigned_agents(plan))
    results.extend(_check_low_parallelism(plan))
    results.extend(_check_missing_contracts(plan))
    results.extend(_check_empty_modules(plan))
    return results


# ─────────────────────────────────────────────────────────────────────
# Blocking heuristics
# ─────────────────────────────────────────────────────────────────────

def _check_all_string_types(plan: dict) -> list[QualityResult]:
    """BLOCKING: Reject plans where all parameter and return types are 'string'.

    This is a strong signal that the LLM didn't think about the type design
    and just defaulted to string for everything.
    """
    all_types: list[str] = []
    for module in plan.get("modules", []):
        for fn in module.get("functions", []):
            for p in fn.get("params", []):
                all_types.append(p.get("type", ""))
            if "returns" in fn:
                all_types.append(fn["returns"])

    if not all_types:
        return []

    non_string = [t for t in all_types if t.lower() not in ("string", "str")]
    if len(non_string) == 0 and len(all_types) >= 2:
        return [QualityResult(
            heuristic="all-string-types",
            message=f"All {len(all_types)} types are 'string'. Use specific types "
                    f"(int, bool, list[T], Result[T,E]) for better type safety.",
            blocking=True,
        )]
    return []


def _check_unassigned_agents(plan: dict) -> list[QualityResult]:
    """BLOCKING: Reject plans where functions have no agent assignment."""
    unassigned: list[str] = []
    for module in plan.get("modules", []):
        for fn in module.get("functions", []):
            agent = fn.get("agent", "")
            if not agent or agent.strip() == "":
                unassigned.append(fn.get("name", "<unnamed>"))

    if unassigned:
        names = ", ".join(unassigned[:5])
        suffix = f" (and {len(unassigned) - 5} more)" if len(unassigned) > 5 else ""
        return [QualityResult(
            heuristic="unassigned-agents",
            message=f"{len(unassigned)} function(s) have no agent assignment: {names}{suffix}. "
                    f"Every function must have an '@agent' field.",
            blocking=True,
        )]
    return []


# ─────────────────────────────────────────────────────────────────────
# Advisory heuristics
# ─────────────────────────────────────────────────────────────────────

def _check_low_parallelism(plan: dict) -> list[QualityResult]:
    """ADVISORY: Warn when there's only one independent hole.

    Low parallelism means the orchestrator can't fill holes concurrently,
    which slows down the overall pipeline.
    """
    total_functions = 0
    for module in plan.get("modules", []):
        total_functions += len(module.get("functions", []))

    # If there's only 0 or 1 function, parallelism isn't relevant
    if total_functions <= 1:
        return [QualityResult(
            heuristic="low-parallelism",
            message=f"Plan has only {total_functions} function(s). Consider decomposing "
                    f"into more smaller functions for better agent parallelism.",
            blocking=False,
        )]
    return []


def _check_missing_contracts(plan: dict) -> list[QualityResult]:
    """ADVISORY: Warn when no functions have contracts (pre/post conditions)."""
    total = 0
    with_contracts = 0
    for module in plan.get("modules", []):
        for fn in module.get("functions", []):
            total += 1
            contracts = fn.get("contracts", {})
            if contracts.get("pre") or contracts.get("post"):
                with_contracts += 1

    if total > 0 and with_contracts == 0:
        return [QualityResult(
            heuristic="missing-contracts",
            message=f"None of the {total} functions have pre/post contracts. "
                    f"Contracts improve verification quality. Consider adding "
                    f"postconditions for boundary functions.",
            blocking=False,
        )]
    return []


def _check_empty_modules(plan: dict) -> list[QualityResult]:
    """ADVISORY: Warn about modules with no functions."""
    empty = [
        m.get("name", "<unnamed>")
        for m in plan.get("modules", [])
        if not m.get("functions")
    ]
    if empty:
        return [QualityResult(
            heuristic="empty-modules",
            message=f"Module(s) with no functions: {', '.join(empty)}. "
                    f"Every module should define at least one function.",
            blocking=False,
        )]
    return []
