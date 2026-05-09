#!/usr/bin/env python3
"""Compare minimal-agent experiment run directories."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


SCRIPT_DIR = Path(__file__).resolve().parent
EXPERIMENT_ROOT = SCRIPT_DIR.parent
DEFAULT_RUNS_ROOT = EXPERIMENT_ROOT / "runs"


COMMAND_COLUMNS = [
    ("check", "Check"),
    ("check-strict", "Strict"),
    ("holes", "Holes"),
    ("test", "Test"),
    ("verify", "Verify"),
]


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Compare minimal-agent experiment runs."
    )
    parser.add_argument(
        "run_dirs",
        nargs="*",
        type=Path,
        help="Explicit run directories. If omitted, scans --runs-root recursively.",
    )
    parser.add_argument(
        "--runs-root",
        type=Path,
        default=DEFAULT_RUNS_ROOT,
        help=f"Runs root to scan when no explicit run dirs are provided (default: {DEFAULT_RUNS_ROOT}).",
    )
    parser.add_argument(
        "--write",
        type=Path,
        default=None,
        help="Optional path to write the Markdown comparison table.",
    )
    args = parser.parse_args()

    run_dirs = args.run_dirs or discover_runs(args.runs_root)
    rows = [summarize_run(path) for path in run_dirs]
    rows.sort(key=lambda row: row["run"])

    table = render_table(rows)
    print(table)
    if args.write:
        args.write.write_text(table + "\n", encoding="utf-8")
    return 0


def discover_runs(root: Path) -> list[Path]:
    if not root.exists():
        return []
    return sorted(path.parent for path in root.rglob(".llmll-experiment.json"))


def summarize_run(run_dir: Path) -> dict[str, str]:
    metadata = load_json(run_dir / ".llmll-experiment.json")
    harness = load_json(run_dir / "harness_result.json")
    evaluation = load_json(run_dir / "evaluation.json")

    experiment = experiment_label(metadata, evaluation)
    agent = harness.get("agent_name", "")
    duration = format_duration(harness.get("duration_seconds"))
    grade = evaluation.get("quality_grade", "F" if evaluation else "—")
    status = status_label(harness, evaluation)
    features = feature_label(evaluation.get("feature_scan"))
    test_summary = test_label(
        evaluation.get("test_summary"),
        evaluation.get("test_assessment"),
    )
    verify_summary = verify_label(
        evaluation.get("verify_summary"),
        evaluation.get("contract_assessment"),
    )

    command_statuses = {name: "—" for name, _ in COMMAND_COLUMNS}
    for command in evaluation.get("commands", []):
        name = command.get("name")
        if name in command_statuses:
            command_statuses[name] = command_label(command)

    row = {
        "run": f"`{run_dir.name}`",
        "agent": agent or "—",
        "experiment": experiment,
        "status": status,
        "grade": grade,
        "duration": duration,
        "features": features,
        "test_summary": test_summary,
        "verify_summary": verify_summary,
    }
    for name, _ in COMMAND_COLUMNS:
        row[name] = command_statuses[name]
    return row


def experiment_label(metadata: dict[str, Any], evaluation: dict[str, Any]) -> str:
    experiment_id = evaluation.get("experiment_id", metadata.get("experiment_id"))
    experiment_slug = evaluation.get("experiment_slug", metadata.get("experiment_slug"))
    if experiment_id and experiment_slug:
        return f"{experiment_id}-{experiment_slug}"
    if experiment_id:
        return str(experiment_id)
    problem = evaluation.get("problem_id", metadata.get("problem_id", ""))
    return str(problem) if problem != "" else "—"


def status_label(harness: dict[str, Any], evaluation: dict[str, Any]) -> str:
    if harness and harness.get("status") == "failed":
        return f"agent fail rc={harness.get('returncode', '?')}"
    if not evaluation:
        return "not evaluated"
    if evaluation.get("status") == "passed":
        return "passed"
    first_error = evaluation.get("first_error") or {}
    phase = first_error.get("phase", "eval")
    return f"eval fail: {phase}"


def feature_label(feature_scan: dict[str, Any] | None) -> str:
    if not feature_scan:
        return "—"
    required = feature_scan.get("required", [])
    missing = feature_scan.get("missing_required", [])
    present = max(0, len(required) - len(missing))
    return f"{present}/{len(required)}"


def command_label(command: dict[str, Any]) -> str:
    rc = command.get("returncode")
    effective = command.get("effective_success")
    if effective is None:
        effective = rc == 0
    if effective:
        return "ok"
    return f"fail rc={rc}"


def test_label(
    summary: dict[str, Any] | None,
    assessment: dict[str, Any] | None,
) -> str:
    if assessment:
        return (
            f"{assessment.get('effective_passed', 0)}/"
            f"{assessment.get('effective_total', 0)} eff, "
            f"{assessment.get('excluded_delegation_dependent', 0)} excl"
        )
    if not summary:
        return "—"
    return (
        f"{summary.get('passed', 0)}/"
        f"{summary.get('total', 0)} pass, "
        f"{summary.get('skipped', 0)} skip"
    )


def verify_label(
    summary: dict[str, Any] | None,
    contract_assessment: dict[str, Any] | None,
) -> str:
    if contract_assessment:
        return (
            f"contracts {contract_assessment.get('accepted_total', 0)}/"
            f"{contract_assessment.get('expected_total', 0)}, "
            f"proof {contract_assessment.get('proof_required_ceiling_accepted', 0)}"
        )
    if not summary:
        return "—"
    return (
        f"v{summary.get('verified', 0)} "
        f"cc{summary.get('contract_checked', 0)} "
        f"t{summary.get('tested', 0)} "
        f"a{summary.get('asserted', 0)} "
        f"none{summary.get('no_contract', 0)}"
    )


def render_table(rows: list[dict[str, str]]) -> str:
    headers = [
        "Run",
        "Agent",
        "Experiment",
        "Status",
        "Grade",
        "Duration",
        "Features",
        "Check",
        "Strict",
        "Holes",
        "Test",
        "Verify",
        "Test Summary",
        "Verify Summary",
    ]
    keys = [
        "run",
        "agent",
        "experiment",
        "status",
        "grade",
        "duration",
        "features",
        "check",
        "check-strict",
        "holes",
        "test",
        "verify",
        "test_summary",
        "verify_summary",
    ]
    lines = [
        "| " + " | ".join(headers) + " |",
        "| " + " | ".join("---" for _ in headers) + " |",
    ]
    for row in rows:
        lines.append("| " + " | ".join(row.get(key, "—") for key in keys) + " |")
    return "\n".join(lines)


def load_json(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {}
    return data if isinstance(data, dict) else {}


def format_duration(value: Any) -> str:
    try:
        return f"{float(value):.1f}s"
    except (TypeError, ValueError):
        return "—"


if __name__ == "__main__":
    raise SystemExit(main())
