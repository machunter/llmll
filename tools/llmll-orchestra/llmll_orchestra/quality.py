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


def check_plan_quality(
    plan: dict,
    *,
    mode: str = "auto",
    min_spec_coverage: float | None = None,
) -> list[QualityResult]:
    """Run all quality heuristics on a plan.

    Returns a list of QualityResult objects. Blocking results must be
    fixed before the plan can proceed to skeleton generation.

    Args:
        plan: The architecture plan dict.
        mode: "auto" or "lead". Controls threshold behavior.
        min_spec_coverage: Override the default coverage threshold.
            Defaults: auto=0.6, lead warn=0.6, lead fail=0.4.
            Tightening roadmap: 0.6 in v0.6, 0.7 in v0.7, 0.8 in v0.8.
    """
    results: list[QualityResult] = []
    results.extend(_check_all_string_types(plan))
    results.extend(_check_unassigned_agents(plan))
    results.extend(_check_low_parallelism(plan))
    results.extend(_check_missing_contracts(plan))
    results.extend(_check_empty_modules(plan))
    results.extend(_check_effective_coverage(plan, mode=mode,
                                             min_spec_coverage=min_spec_coverage))
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


# ─────────────────────────────────────────────────────────────────────
# v0.6: Spec coverage gate
# ─────────────────────────────────────────────────────────────────────

def _check_effective_coverage(
    plan: dict,
    *,
    mode: str = "auto",
    min_spec_coverage: float | None = None,
) -> list[QualityResult]:
    """v0.6: Check effective specification coverage.

    Coverage = (contracted + suppressed) / total_functions.

    Thresholds (Language Team Q2 resolution):
        - --mode auto:  fail at 60%  (tightening: 70% v0.7, 80% v0.8)
        - --mode lead:  warn at 60%, hard fail at 40%
        - Overridable via min_spec_coverage.
    """
    total = 0
    contracted = 0
    suppressed = 0

    for module in plan.get("modules", []):
        for fn in module.get("functions", []):
            total += 1
            contracts = fn.get("contracts", {})
            if contracts.get("pre") or contracts.get("post"):
                contracted += 1
            elif fn.get("weakness_ok"):
                suppressed += 1

    if total == 0:
        return []

    coverage = (contracted + suppressed) / total
    unspecified_names = [
        fn.get("name", "<unnamed>")
        for module in plan.get("modules", [])
        for fn in module.get("functions", [])
        if not (fn.get("contracts", {}).get("pre") or
                fn.get("contracts", {}).get("post") or
                fn.get("weakness_ok"))
    ]

    results: list[QualityResult] = []

    if mode == "lead":
        fail_threshold = min_spec_coverage if min_spec_coverage is not None else 0.4
        warn_threshold = 0.6

        if coverage < fail_threshold:
            names = ", ".join(unspecified_names[:5])
            suffix = f" (and {len(unspecified_names) - 5} more)" if len(unspecified_names) > 5 else ""
            results.append(QualityResult(
                heuristic="effective-coverage",
                message=f"Effective spec coverage is {coverage:.0%} "
                        f"({contracted + suppressed}/{total}), below the {fail_threshold:.0%} "
                        f"minimum. Unspecified: {names}{suffix}.",
                blocking=True,
            ))
        elif coverage < warn_threshold:
            results.append(QualityResult(
                heuristic="effective-coverage",
                message=f"Effective spec coverage is {coverage:.0%} "
                        f"({contracted + suppressed}/{total}). Consider adding contracts "
                        f"to reach the {warn_threshold:.0%} target.",
                blocking=False,
            ))
    else:  # mode == "auto"
        threshold = min_spec_coverage if min_spec_coverage is not None else 0.6
        if coverage < threshold:
            names = ", ".join(unspecified_names[:5])
            suffix = f" (and {len(unspecified_names) - 5} more)" if len(unspecified_names) > 5 else ""
            results.append(QualityResult(
                heuristic="effective-coverage",
                message=f"Effective spec coverage is {coverage:.0%} "
                        f"({contracted + suppressed}/{total}), below the {threshold:.0%} "
                        f"threshold. Unspecified: {names}{suffix}.",
                blocking=True,
            ))

    return results
