#!/usr/bin/env python3
"""Evaluate a repair-loop run directory.

Phase 1 mode (apparatus validation): checks that the loop closed cleanly,
each turn produced verifier output, the context artifact was written, and
(for stub runs) the agent received prior turns' context as input. Produces
`evaluation.json` and `summary.md`.

Phases 2/3 (calibration, full matrix): extend this evaluator with the
two-axis scoring rubric from
`docs/design/language-comparison-experiments.md:198-226`. Phase 1 reports
scoring as `n/a` for stub runs and `pending` for real runs until that
extension lands.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Evaluate a repair-loop run directory."
    )
    parser.add_argument("run_dir", type=Path)
    args = parser.parse_args()

    run_dir: Path = args.run_dir.resolve()
    log_path = run_dir / "repair_loop_log.json"
    if not log_path.exists():
        print(f"repair_loop_log.json not found in {run_dir}", file=sys.stderr)
        return 2
    log = json.loads(log_path.read_text())

    apparatus = _evaluate_apparatus(run_dir, log)
    scoring = _evaluate_scoring(run_dir, log)

    evaluation = {
        "run_dir": str(run_dir),
        "harness": "repair-loop",
        "phase": log.get("phase"),
        "agent_name": log.get("agent_name"),
        "agent_mode": log.get("agent_mode"),
        "experiment": log.get("experiment"),
        "target": log.get("target"),
        "repair_budget_k": log.get("repair_budget_k"),
        "terminal_state": log.get("terminal_state"),
        "terminal_reason": log.get("terminal_reason"),
        "turns_completed": len(log.get("turns", [])),
        "apparatus": apparatus,
        "scoring": scoring,
    }

    eval_path = run_dir / "evaluation.json"
    eval_path.write_text(json.dumps(evaluation, indent=2) + "\n")

    summary_path = run_dir / "summary.md"
    summary_path.write_text(_summary_markdown(evaluation, log))

    print(f"evaluation: {eval_path}")
    print(f"summary: {summary_path}")
    print(f"apparatus_status: {apparatus['status']}")
    return 0


def _evaluate_apparatus(run_dir: Path, log: dict[str, Any]) -> dict[str, Any]:
    """Apparatus validation checks for Phase 1.

    The apparatus passes when every turn:
      a) has a verifier.json artefact under turns/turn_NN/
      b) has a context artefact at context/turn_NN_verifier.json
      c) has at least one non-empty verifier result
      d) for stub-agent runs and turns 2..k: the agent stdout records that
         it saw the prior turn's context file (proves re-injection works)

    Plus loop-level:
      e) terminal_state is one of the four legal values
      f) turn count >= 1
    """
    checks: list[dict[str, Any]] = []
    turns = log.get("turns", [])

    # a, b, c — per-turn artefact and capture checks
    for turn in turns:
        idx = turn.get("turn")
        turn_artifact = run_dir / "turns" / f"turn_{idx:02d}" / "verifier.json"
        context_artifact = run_dir / "context" / f"turn_{idx:02d}_verifier.json"
        verifier_results = turn.get("verifier_results", [])
        checks.append({
            "id": f"per-turn-artefact-{idx:02d}",
            "passed": turn_artifact.exists() and context_artifact.exists(),
            "detail": (
                f"turn_artifact={turn_artifact.exists()}, "
                f"context_artifact={context_artifact.exists()}"
            ),
        })
        checks.append({
            "id": f"per-turn-verifier-nonempty-{idx:02d}",
            "passed": len(verifier_results) > 0,
            "detail": f"{len(verifier_results)} verifier results captured",
        })

    # d — stub re-injection check (only for stub runs with turn >= 2)
    if log.get("agent_mode") == "stub" and len(turns) >= 2:
        for turn in turns[1:]:
            idx = turn.get("turn")
            stdout = run_dir / "turns" / f"turn_{idx:02d}" / "agent.stdout.log"
            saw_prior = False
            if stdout.exists():
                content = stdout.read_text()
                saw_prior = f"turn_{idx-1:02d}_verifier.json" in content
            checks.append({
                "id": f"stub-saw-prior-context-{idx:02d}",
                "passed": saw_prior,
                "detail": "stub stdout records prior context filename"
                          if saw_prior else "stub did not record prior context",
            })

    # e — terminal_state legal
    terminal_state = log.get("terminal_state")
    legal_states = {"target-reached", "budget-exhausted", "infrastructure-fail"}
    checks.append({
        "id": "terminal-state-legal",
        "passed": terminal_state in legal_states,
        "detail": f"terminal_state={terminal_state!r}",
    })

    # f — at least one turn
    checks.append({
        "id": "at-least-one-turn",
        "passed": len(turns) >= 1,
        "detail": f"{len(turns)} turns completed",
    })

    failed = [c for c in checks if not c["passed"]]
    status = "passed" if not failed else "failed"
    return {
        "status": status,
        "checks": checks,
        "failed_count": len(failed),
    }


def _evaluate_scoring(run_dir: Path, log: dict[str, Any]) -> dict[str, Any]:
    """Per-axis subscoring per the v2 rubric (language-team Addenda 7/8).

    Replaces the Phase-1.5 stub. Implements 8 sub-categories end-to-end,
    stubs 5 with TODO(sub-3-v2), hard-defers 1. Does NOT produce a
    100-pt aggregate (professor G3); reports per-axis subscores plus
    target-specific headline metrics.

    Stub agents return scoring = {status: "n/a"} unchanged.
    """
    if log.get("agent_mode") == "stub":
        return {
            "status": "n/a",
            "reason": "stub agent does not produce a scoreable solution",
        }

    target = log.get("target")
    turns = log.get("turns", [])
    if not turns:
        return {
            "status": "n/a",
            "reason": "no turns recorded; nothing to score",
        }

    final_verifier = turns[-1].get("verifier_results", [])
    evidence = _extract_target_evidence(target, final_verifier, run_dir)
    correctness = _build_correctness_subscores(evidence)
    assurance = _build_assurance_subscores(target, evidence)
    headline = _build_headline_metrics(target, evidence)

    implemented_count = sum(
        1 for v in {**correctness, **assurance}.values()
        if isinstance(v, dict) and v.get("status") == "scored"
    )
    return {
        "status": "scored",
        "reason": (
            f"per-axis v2 rubric: {implemented_count} sub-categories scored end-to-end, "
            "remainder stubbed with TODO(sub-3-v2) or hard-deferred. "
            "No 100-pt aggregate per professor G3."
        ),
        "correctness_subscores": correctness,
        "assurance_subscores": assurance,
        "headline_metrics": headline,
    }


# ---------------------------------------------------------------------------
# Per-target evidence extraction
# ---------------------------------------------------------------------------


def _extract_target_evidence(
    target: str | None, verifier: list[dict[str, Any]], run_dir: Path
) -> dict[str, Any]:
    """Dispatch evidence extraction by target. Returns a flat dict consumed
    by `_build_*_subscores`. Missing values are explicit (`None`), not absent.
    """
    if target == "llmll":
        return _extract_llmll_evidence(verifier, run_dir)
    if target == "go":
        return _extract_go_evidence(verifier, run_dir)
    if target == "python":
        return _extract_python_evidence(verifier, run_dir)
    return {"target_unknown": target}


def _extract_llmll_evidence(
    verifier: list[dict[str, Any]], run_dir: Path
) -> dict[str, Any]:
    by_name = {r["name"]: r for r in verifier}

    solution = _find_first_existing(run_dir, ["solution.ast.json", "solution.llmll"])
    source_present = solution is not None
    source_text = solution.read_text() if solution else ""
    is_ast = solution.suffix == ".json" if solution else False

    check_cmd = by_name.get("check") or by_name.get("check-strict")
    build_ok = (check_cmd is not None) and (check_cmd["exit_code"] == 0)

    test_cmd = by_name.get("test")
    pbt = _parse_llmll_test_results(test_cmd["stdout"]) if test_cmd else None

    verify_cmd = by_name.get("verify")
    verify_json = (verify_cmd or {}).get("parsed_json")
    trust_stats = _summarize_trust_report(verify_json)

    check_block_count = _count_llmll_check_blocks(source_text, is_ast)
    trust_decl_count = _count_llmll_trust_declarations(source_text, is_ast)
    kloc = _count_program_kloc(source_text, is_ast)

    return {
        "target": "llmll",
        "solution_file_exists": source_present,
        "build_typecheck_passed": build_ok,
        "pbt_results": pbt,
        "trust_stats": trust_stats,
        "agent_check_block_count": check_block_count,
        "agent_trust_declaration_count": trust_decl_count,
        "program_kloc": kloc,
    }


def _extract_go_evidence(
    verifier: list[dict[str, Any]], run_dir: Path
) -> dict[str, Any]:
    by_name = {r["name"]: r for r in verifier}
    solution = run_dir / "solution.go"
    source_present = solution.exists()

    vet_ok = (by_name.get("vet", {}).get("exit_code") == 0)
    build_ok = (by_name.get("build", {}).get("exit_code") == 0)
    build_typecheck_passed = vet_ok and build_ok

    test_cmd = by_name.get("test")
    test_results = _parse_go_test_results(test_cmd["stdout"]) if test_cmd else None

    return {
        "target": "go",
        "solution_file_exists": source_present,
        "build_typecheck_passed": build_typecheck_passed,
        "test_results": test_results,
    }


def _extract_python_evidence(
    verifier: list[dict[str, Any]], run_dir: Path
) -> dict[str, Any]:
    by_name = {r["name"]: r for r in verifier}
    solution = run_dir / "solution.py"
    source_present = solution.exists()

    pyright_cmd = by_name.get("pyright")
    pyright_results = _parse_pyright_results(pyright_cmd["stdout"]) if pyright_cmd else None
    build_typecheck_passed = (
        pyright_cmd is not None
        and pyright_cmd["exit_code"] == 0
        and (pyright_results or {}).get("errors") == 0
    )

    pytest_cmd = by_name.get("pytest")
    pytest_results = _parse_pytest_results(pytest_cmd["stdout"]) if pytest_cmd else None

    return {
        "target": "python",
        "solution_file_exists": source_present,
        "build_typecheck_passed": build_typecheck_passed,
        "pyright_results": pyright_results,
        "test_results": pytest_results,
    }


# ---------------------------------------------------------------------------
# Sub-score construction
# ---------------------------------------------------------------------------


def _build_correctness_subscores(evidence: dict[str, Any]) -> dict[str, Any]:
    """Six correctness sub-categories per v2 rubric. 3 implemented, 3 stubbed/deferred."""
    return {
        "solution_discovery": {
            "status": "scored",
            "value": bool(evidence.get("solution_file_exists")),
        },
        "build_typecheck": {
            "status": "scored",
            "value": evidence.get("build_typecheck_passed"),
        },
        "core_behavior": {
            "status": "scored",
            **_core_behavior_subscore(evidence),
        },
        "api_conformance": {
            "status": "TODO(sub-3-v2)",
            "value": None,
            "note": (
                "Detection differs per target: Python import-fail surfaces from pytest; "
                "Go undefined-symbol from build; LLMLL via cross-module type-check at "
                "Module.hs:checkInterfaceMismatch. Not extracted in this turn."
            ),
        },
        "edge_cases": {
            "status": "TODO(sub-3-v2)",
            "value": None,
            "note": "Requires test-tagging convention (which tests are edge cases). Not in place.",
        },
        "determinism_isolation": {
            "status": "deferred",
            "value": None,
            "note": "Sandbox introspection out of Phase 1.75 scope.",
        },
    }


def _build_assurance_subscores(target: str | None, evidence: dict[str, Any]) -> dict[str, Any]:
    """Six assurance sub-categories per v2 rubric. 4 implemented (LLMLL-conditional),
    4 stubbed/deferred. Test-quality is itself split into three independent sub-axes.
    """
    test_quality = _test_quality_subscore(target, evidence)
    proof_evidence = _proof_evidence_subscore(target, evidence)
    return {
        "test_quality": {
            "status": "scored",
            **test_quality,
        },
        "proof_or_trust_evidence": {
            "status": "scored" if target == "llmll" else "n/a",
            **proof_evidence,
        },
        "static_structure": {
            "status": "TODO(sub-3-v2)",
            "value": None,
            "note": (
                "Per-target measurement: Python type-hint density, Go exported-decl "
                "count, LLMLL declared-contract count. Not extracted in this turn."
            ),
        },
        "runtime_checks": {
            "status": "TODO(sub-3-v2)",
            "value": None,
            "note": "Per-target assertion/error-raise density. Not extracted in this turn.",
        },
        "contract_strength": {
            "status": "TODO(sub-3-v2)",
            "value": None,
            "note": (
                "Per-target: LLMLL pre/post clause density; Python type-hint coverage; "
                "Go error-return density. Not extracted in this turn."
            ),
        },
        "specification_adequacy": {
            "status": "deferred",
            "value": None,
            "note": "Vacuous-spec detection requires structural analysis. Out of scope.",
        },
    }


def _build_headline_metrics(target: str | None, evidence: dict[str, Any]) -> dict[str, Any]:
    """Headline metrics per language-team v2 (replaces dropped aggregate score)."""
    if target != "llmll":
        return {
            "status": "n/a",
            "reason": "headline metrics defined for LLMLL target only; per-target headlines for Python/Go pending Phase 1.75 v2",
        }
    kloc = evidence.get("program_kloc") or 0.0
    trust_count = evidence.get("agent_trust_declaration_count", 0)
    trust_per_kloc = (trust_count / kloc) if kloc > 0 else 0.0
    trust_stats = evidence.get("trust_stats") or {}
    comp_rate = trust_stats.get("compositionally_verified_rate")
    return {
        "trust_declarations_per_kloc": round(trust_per_kloc, 3),
        "compositionally_verified_module_rate": comp_rate,
    }


def _core_behavior_subscore(evidence: dict[str, Any]) -> dict[str, Any]:
    """Pass rate from the canonical test channel for this target."""
    target = evidence.get("target")
    if target == "llmll":
        pbt = evidence.get("pbt_results") or {}
        passed = pbt.get("passed", 0)
        failed = pbt.get("failed", 0)
        skipped = pbt.get("skipped", 0)
        total = passed + failed + skipped
        return {
            "value": (passed / total) if total > 0 else None,
            "passed": passed,
            "failed": failed,
            "skipped": skipped,
            "channel": "llmll-pbt",
        }
    if target in ("go", "python"):
        tr = evidence.get("test_results") or {}
        passed = tr.get("passed", 0)
        failed = tr.get("failed", 0)
        skipped = tr.get("skipped", 0)
        total = passed + failed + skipped
        return {
            "value": (passed / total) if total > 0 else None,
            "passed": passed,
            "failed": failed,
            "skipped": skipped,
            "channel": f"{target}-example-based",
        }
    return {"value": None}


def _test_quality_subscore(target: str | None, evidence: dict[str, Any]) -> dict[str, Any]:
    """v2 split: example_based + pbt_sample + agent_emitted."""
    example_based = None
    pbt_sample = None
    if target in ("go", "python"):
        tr = evidence.get("test_results") or {}
        denom = tr.get("passed", 0) + tr.get("failed", 0) + tr.get("skipped", 0)
        if denom > 0:
            example_based = round(tr.get("passed", 0) / denom, 3)
    if target == "llmll":
        pbt = evidence.get("pbt_results") or {}
        denom = pbt.get("passed", 0) + pbt.get("failed", 0) + pbt.get("skipped", 0)
        if denom > 0:
            pbt_sample = round(pbt.get("passed", 0) / denom, 3)
    agent_emitted = None
    if target == "llmll":
        agent_emitted = evidence.get("agent_check_block_count")
    return {
        "example_based_test_pass_rate": example_based,
        "pbt_sample_pass_rate": pbt_sample,
        "agent_emitted_test_count": agent_emitted,
    }


def _proof_evidence_subscore(target: str | None, evidence: dict[str, Any]) -> dict[str, Any]:
    """v2: locally_verified + outstanding_trust + compositionally_verified_rate.

    LLMLL-only; other targets have no analogous evidence channel.
    """
    if target != "llmll":
        return {
            "locally_verified_obligations": None,
            "outstanding_trust_acknowledgments": None,
            "compositionally_verified_module_rate": None,
            "note": "Target has no analogous proof-evidence channel.",
        }
    stats = evidence.get("trust_stats") or {}
    return {
        "locally_verified_obligations": stats.get("locally_verified_obligations"),
        "outstanding_trust_acknowledgments": evidence.get("agent_trust_declaration_count"),
        "compositionally_verified_module_rate": stats.get("compositionally_verified_rate"),
    }


# ---------------------------------------------------------------------------
# Parsers and source counters
# ---------------------------------------------------------------------------


def _parse_llmll_test_results(text: str) -> dict[str, int]:
    """Parse `llmll test` output for passed/failed/skipped counts.

    Output shape (per the R1 smoke and the v0.10.2 §5.1 outcomes table):
        N properties
          ✅ Passed:  K
          ❌ Failed:  M
          ⚠️  Skipped: J
    Falls back to zeros if pattern not found.
    """
    import re
    passed = _safe_int(re.search(r"Passed:\s*(\d+)", text))
    failed = _safe_int(re.search(r"Failed:\s*(\d+)", text))
    skipped = _safe_int(re.search(r"Skipped:\s*(\d+)", text))
    return {"passed": passed, "failed": failed, "skipped": skipped}


def _parse_go_test_results(text: str) -> dict[str, int]:
    """Count Go test outcomes from `-v` output.

    Lines look like:
        --- PASS: TestX (0.00s)
        --- FAIL: TestY (0.00s)
        --- SKIP: TestZ (0.00s)
    """
    import re
    passed = len(re.findall(r"--- PASS:", text))
    failed = len(re.findall(r"--- FAIL:", text))
    skipped = len(re.findall(r"--- SKIP:", text))
    return {"passed": passed, "failed": failed, "skipped": skipped}


def _parse_pytest_results(text: str) -> dict[str, int]:
    """Parse pytest summary line: '=== N passed, M failed, K skipped in T s ===' or variants."""
    import re
    passed = _safe_int(re.search(r"(\d+) passed", text))
    failed = _safe_int(re.search(r"(\d+) failed", text))
    skipped = _safe_int(re.search(r"(\d+) skipped", text))
    return {"passed": passed, "failed": failed, "skipped": skipped}


def _parse_pyright_results(text: str) -> dict[str, int]:
    """Parse pyright summary line: 'N errors, M warnings, K informations'."""
    import re
    errors = _safe_int(re.search(r"(\d+) errors?", text))
    warnings = _safe_int(re.search(r"(\d+) warnings?", text))
    return {"errors": errors, "warnings": warnings}


def _summarize_trust_report(parsed_verify: Any) -> dict[str, Any]:
    """Extract the per-axis evidence counts from llmll verify --trust-report JSON.

    Schema (per F-008's discovery + the v0.10.2 verify --json output, plus
    R6d's bb1bd98 `tier_profile` aggregate and `trust_report_version` field):
        {"trust_report_version": "1.0.0",
         "entries": [{"name", "pre_level", "post_level", "effective_level", ...}],
         "summary": {"verified", "contract_checked", "tested", "asserted",
                     "no_contract", "drifts"},
         "tier_profile": {"verified", "proved", "contract_checked",
                          "tested", "asserted", "no_contract"},
         "suppressions": [...]}

    R6d adds `tier_profile` (six-Int aggregate, harness-side Assurance signal)
    and `cred` (harness-derived universal-Cred binary) to the returned dict.
    Both are None on pre-R6d trust reports that lack the aggregate field.
    """
    if not isinstance(parsed_verify, dict):
        return {
            "locally_verified_obligations": None,
            "compositionally_verified_rate": None,
            "n_entries": 0,
            "tier_profile": None,
            "cred": None,
            "trust_report_version": None,
        }
    entries = parsed_verify.get("entries") or []
    if not isinstance(entries, list):
        return {
            "locally_verified_obligations": None,
            "compositionally_verified_rate": None,
            "n_entries": 0,
            "tier_profile": None,
            "cred": None,
            "trust_report_version": None,
        }

    locally_verified = 0
    compositionally_verified = 0
    n_entries = len(entries)
    for entry in entries:
        if not isinstance(entry, dict):
            continue
        if _normalize_level(entry.get("pre_level") or "") == "verified":
            locally_verified += 1
        if _normalize_level(entry.get("post_level") or "") == "verified":
            locally_verified += 1
        if _normalize_level(entry.get("effective_level") or "") == "verified":
            compositionally_verified += 1

    comp_rate = (compositionally_verified / n_entries) if n_entries > 0 else None

    # R6d: tier_profile is the spec-blessed Assurance signal, Cred is the
    # harness-derived loop-control binary. See experiments/repair-loop/README.md
    # "Credibility predicate and the H1 split (R6d)".
    tp = parsed_verify.get("tier_profile")
    if isinstance(tp, dict):
        n_asserted = int(tp.get("asserted") or 0)
        n_no_contract = int(tp.get("no_contract") or 0)
        cred = (n_entries > 0) and (n_asserted == 0) and (n_no_contract == 0)
    else:
        tp = None
        cred = None

    return {
        "locally_verified_obligations": locally_verified,
        "compositionally_verified_rate": round(comp_rate, 3) if comp_rate is not None else None,
        "n_entries": n_entries,
        "tier_profile": tp,
        "cred": cred,
        "trust_report_version": parsed_verify.get("trust_report_version"),
    }


def _normalize_level(level: str) -> str:
    """Mirror the orchestrator helper: 'verified (liquid-fixpoint)' -> 'verified'."""
    return level.lower().split()[0] if level else ""


def _count_llmll_check_blocks(source: str, is_ast: bool) -> int:
    """Count agent-emitted (check ...) blocks in solution.

    For .llmll: regex on the S-expression source.
    For .ast.json: parse JSON, count top-level statements with kind == "check".
    """
    if not source:
        return 0
    if is_ast:
        try:
            data = json.loads(source)
        except json.JSONDecodeError:
            return 0
        return _count_ast_nodes_of_kind(data, "check")
    import re
    return len(re.findall(r"\(check\b", source))


def _count_llmll_trust_declarations(source: str, is_ast: bool) -> int:
    """Count (trust ...) declarations. Same dual-path as _count_llmll_check_blocks."""
    if not source:
        return 0
    if is_ast:
        try:
            data = json.loads(source)
        except json.JSONDecodeError:
            return 0
        return _count_ast_nodes_of_kind(data, "trust")
    import re
    return len(re.findall(r"\(trust\b", source))


def _count_ast_nodes_of_kind(data: Any, kind: str) -> int:
    """Recursively count nodes whose .kind == kind in a JSON-AST tree."""
    count = 0
    if isinstance(data, dict):
        if data.get("kind") == kind:
            count += 1
        for v in data.values():
            count += _count_ast_nodes_of_kind(v, kind)
    elif isinstance(data, list):
        for item in data:
            count += _count_ast_nodes_of_kind(item, kind)
    return count


def _count_program_kloc(source: str, is_ast: bool) -> float:
    """Rough kLoC measure. For .llmll: source lines / 1000. For .ast.json:
    count statements (each top-level statement ~= 5 lines, approximate).

    The number is order-of-magnitude meaningful for the trust-per-kLoC headline,
    not a precise count.
    """
    if not source:
        return 0.0
    if is_ast:
        try:
            data = json.loads(source)
        except json.JSONDecodeError:
            return 0.0
        if isinstance(data, dict) and isinstance(data.get("body"), list):
            stmts = len(data["body"])
        elif isinstance(data, list):
            stmts = len(data)
        else:
            stmts = 1
        return round((stmts * 5) / 1000.0, 4)
    line_count = source.count("\n") + 1
    return round(line_count / 1000.0, 4)


def _find_first_existing(run_dir: Path, names: list[str]) -> Path | None:
    for name in names:
        candidate = run_dir / name
        if candidate.exists():
            return candidate
    return None


def _safe_int(match) -> int:
    if match is None:
        return 0
    try:
        return int(match.group(1))
    except (ValueError, IndexError):
        return 0


# ---------------------------------------------------------------------------
# Markdown rendering for the new scoring block
# ---------------------------------------------------------------------------


def _render_subscores_md(scoring: dict[str, Any]) -> list[str]:
    """Render correctness, assurance, and headline blocks under ## Scoring."""
    out: list[str] = []
    correctness = scoring.get("correctness_subscores", {})
    assurance = scoring.get("assurance_subscores", {})
    headline = scoring.get("headline_metrics", {})

    out.append("### Correctness subscores")
    out.append("")
    out.append("| Sub-category | Status | Value |")
    out.append("|---|---|---|")
    for name, payload in correctness.items():
        out.append(f"| `{name}` | {payload.get('status')} | {_fmt_subscore_value(payload)} |")
    out.append("")

    out.append("### Assurance subscores")
    out.append("")
    out.append("| Sub-category | Status | Value |")
    out.append("|---|---|---|")
    for name, payload in assurance.items():
        out.append(f"| `{name}` | {payload.get('status')} | {_fmt_subscore_value(payload)} |")
    out.append("")

    out.append("### Headline metrics")
    out.append("")
    if headline.get("status") == "n/a":
        out.append(f"_n/a — {headline.get('reason', '')}_")
    else:
        for k, v in headline.items():
            out.append(f"- **{k}:** `{v}`")
    out.append("")
    return out


def _fmt_subscore_value(payload: dict[str, Any]) -> str:
    """Pretty-print a subscore payload for the markdown table."""
    if not isinstance(payload, dict):
        return f"`{payload}`"
    if "value" in payload and len(payload) <= 2 and not any(
        k for k in payload if k not in {"status", "value"}
    ):
        return f"`{payload['value']}`"
    # Rich payload — list the populated keys briefly.
    pieces = []
    for k, v in payload.items():
        if k in {"status", "note"}:
            continue
        pieces.append(f"{k}=`{v}`")
    return "; ".join(pieces) if pieces else "—"


def _summary_markdown(evaluation: dict[str, Any], log: dict[str, Any]) -> str:
    lines = []
    lines.append(f"# Repair-Loop Run — {evaluation['agent_name']}")
    lines.append("")
    lines.append(f"- **Run directory:** `{evaluation['run_dir']}`")
    lines.append(f"- **Phase:** {evaluation['phase']}")
    lines.append(f"- **Agent mode:** {evaluation['agent_mode']}")
    lines.append(f"- **Experiment:** {evaluation['experiment']}")
    lines.append(f"- **Target:** {evaluation['target']}")
    lines.append(f"- **Repair budget k:** {evaluation['repair_budget_k']}")
    lines.append(f"- **Turns completed:** {evaluation['turns_completed']}")
    lines.append(f"- **Terminal state:** `{evaluation['terminal_state']}`")
    lines.append(f"- **Terminal reason:** {evaluation['terminal_reason']}")
    lines.append("")
    lines.append(f"## Apparatus: {evaluation['apparatus']['status']}")
    lines.append("")
    lines.append("| Check | Result | Detail |")
    lines.append("|---|---|---|")
    for c in evaluation["apparatus"]["checks"]:
        status = "✓" if c["passed"] else "✗"
        lines.append(f"| `{c['id']}` | {status} | {c['detail']} |")
    lines.append("")
    lines.append(f"## Scoring: {evaluation['scoring']['status']}")
    lines.append("")
    lines.append(f"{evaluation['scoring'].get('reason', '')}")
    lines.append("")
    if evaluation["scoring"].get("status") == "scored":
        lines.extend(_render_subscores_md(evaluation["scoring"]))
    lines.append("")
    lines.append("## Per-turn verifier summary")
    lines.append("")
    for turn in log.get("turns", []):
        idx = turn["turn"]
        match = "yes" if turn["terminal_target_match"] else "no"
        reason = turn["terminal_target_reason"]
        rc_cells = ", ".join(
            f"{r['name']}={r['exit_code']}" for r in turn["verifier_results"]
        )
        lines.append(f"- **Turn {idx}** — terminal match: {match} ({reason}); verifier rc: {rc_cells or 'none'}")
    lines.append("")
    return "\n".join(lines)


if __name__ == "__main__":
    sys.exit(main())
