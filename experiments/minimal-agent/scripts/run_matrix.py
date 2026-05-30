#!/usr/bin/env python3
"""Run a mixed-agent/experiment matrix from a JSON manifest."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


SCRIPT_DIR = Path(__file__).resolve().parent
EXPERIMENT_ROOT = SCRIPT_DIR.parent
PREPARE = SCRIPT_DIR / "prepare_run.py"
RUN_AGENT = SCRIPT_DIR / "run_agent.py"
DEFAULT_RUN_COUNT = 3


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Prepare and optionally run a mixed-agent LLMLL experiment matrix."
    )
    parser.add_argument("manifest", type=Path, help="JSON manifest file.")
    parser.add_argument(
        "--output",
        type=Path,
        default=EXPERIMENT_ROOT / "runs",
        help="Output directory for batch run directories.",
    )
    parser.add_argument(
        "--prepare-only",
        action="store_true",
        help="Create run directories without launching agent commands.",
    )
    parser.add_argument(
        "--fail-fast",
        action="store_true",
        help="Stop the matrix after the first failed run.",
    )
    parser.add_argument(
        "--run-count",
        type=int,
        default=None,
        help=f"Attempts per agent/experiment cell (default: manifest run_count or {DEFAULT_RUN_COUNT}).",
    )
    args = parser.parse_args()

    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    agents = manifest.get("agents", [])
    experiments = manifest.get("experiments")
    if experiments is None:
        experiments = [str(problem) for problem in manifest.get("problems", [1, 2, 3])]
    if not agents:
        raise SystemExit("Manifest must include at least one agent.")

    batch_id = manifest.get("batch_id") or datetime.now(timezone.utc).strftime(
        "%Y%m%dT%H%M%SZ"
    )
    manifest_run_count = int(manifest.get("run_count", DEFAULT_RUN_COUNT))
    run_count = args.run_count if args.run_count is not None else manifest_run_count
    if run_count < 1:
        raise SystemExit("--run-count must be at least 1.")
    grammar_mode = str(manifest.get("grammar_mode", "legacy"))

    batch_dir = args.output / batch_id
    batch_dir.mkdir(parents=True, exist_ok=False)

    results: list[dict[str, Any]] = []
    any_failed = False

    for agent in agents:
        name = agent["name"]
        cmd = agent["cmd"]
        agent_run_count = int(agent.get("run_count", run_count))
        if agent_run_count < 1:
            raise SystemExit(f"Agent {name!r} run_count must be at least 1.")
        for experiment in experiments:
            for attempt in range(1, agent_run_count + 1):
                prepared = prepare_run(
                    batch_dir,
                    batch_id,
                    name,
                    str(experiment),
                    attempt,
                    agent_run_count,
                    grammar_mode=grammar_mode,
                )
                run_dir = Path(prepared["run_dir"])

                entry: dict[str, Any] = {
                    "agent": name,
                    "experiment": prepared.get("experiment_id", str(experiment)),
                    "experiment_slug": prepared.get("experiment_slug"),
                    "problem": int(prepared.get("problem_id", 0)),
                    "attempt": attempt,
                    "attempt_count": agent_run_count,
                    "run_dir": str(run_dir),
                    "status": "prepared",
                    "returncode": None,
                    "prepared": prepared,
                    "harness": None,
                    "evaluation": None,
                    "result": None,
                }

                if not args.prepare_only:
                    rc = run_agent(
                        run_dir=run_dir,
                        agent_name=name,
                        agent_cmd=cmd,
                        timeout_seconds=int(
                            agent.get(
                                "timeout_seconds",
                                manifest.get("timeout_seconds", 1800),
                            )
                        ),
                        llmll_cmd=agent.get(
                            "llmll_cmd",
                            manifest.get(
                                "llmll_cmd",
                                "llmll --grammar=core-inversion"
                                if grammar_mode == "core-inversion"
                                else "llmll",
                            ),
                        ),
                        skip_verify=bool(
                            agent.get("skip_verify", manifest.get("skip_verify", False))
                        ),
                    )
                    entry["returncode"] = rc
                    entry.update(summarize_attempt(run_dir, rc))
                    if rc != 0:
                        any_failed = True
                        results.append(entry)
                        write_batch_report(batch_dir, batch_id, results)
                        if args.fail_fast:
                            return 1
                        continue

                results.append(entry)
                write_batch_report(batch_dir, batch_id, results)

    return 1 if any_failed else 0


def prepare_run(
    batch_dir: Path,
    batch_id: str,
    agent_name: str,
    experiment: str,
    attempt: int,
    attempt_count: int,
    grammar_mode: str = "legacy",
) -> dict[str, str]:
    label = f"{agent_name}-try{attempt:02d}-of-{attempt_count:02d}"
    cmd = [
        sys.executable,
        str(PREPARE),
        "--experiment",
        experiment,
        "--output",
        str(batch_dir),
        "--run-id",
        batch_id,
        "--label",
        label,
        "--grammar-mode",
        grammar_mode,
        "--json",
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, check=False)
    if result.returncode != 0:
        raise SystemExit(result.stderr or result.stdout)
    data = json.loads(result.stdout)
    return data["runs"][0]


def run_agent(
    *,
    run_dir: Path,
    agent_name: str,
    agent_cmd: str,
    timeout_seconds: int,
    llmll_cmd: str,
    skip_verify: bool,
) -> int:
    cmd = [
        sys.executable,
        str(RUN_AGENT),
        str(run_dir),
        "--agent-name",
        agent_name,
        "--agent-cmd",
        agent_cmd,
        "--timeout-seconds",
        str(timeout_seconds),
        "--llmll-cmd",
        llmll_cmd,
    ]
    if skip_verify:
        cmd.append("--skip-verify")
    return subprocess.run(cmd, check=False).returncode


def summarize_attempt(run_dir: Path, rc: int) -> dict[str, Any]:
    harness = load_json(run_dir / "harness_result.json")
    evaluation = load_json(run_dir / "evaluation.json")
    status = attempt_status(rc, harness, evaluation)
    return {
        "status": status,
        "harness": summarize_harness(harness),
        "evaluation": summarize_evaluation(evaluation),
        "result": {
            "status": status,
            "returncode": rc,
            "agent_status": harness.get("status"),
            "evaluation_status": evaluation.get("status"),
            "quality_grade": evaluation.get("quality_grade"),
            "first_error_phase": (evaluation.get("first_error") or {}).get("phase"),
            "first_error_reason": (evaluation.get("first_error") or {}).get(
                "effective_failure_reason"
            ),
        },
    }


def attempt_status(
    rc: int,
    harness: dict[str, Any],
    evaluation: dict[str, Any],
) -> str:
    if harness.get("status") == "failed":
        return "agent_failed"
    if evaluation and evaluation.get("status") == "passed":
        return "passed"
    if evaluation:
        return "evaluation_failed"
    return "failed" if rc != 0 else "passed"


def summarize_harness(harness: dict[str, Any]) -> dict[str, Any] | None:
    if not harness:
        return None
    return {
        "status": harness.get("status"),
        "returncode": harness.get("returncode"),
        "duration_seconds": harness.get("duration_seconds"),
        "error": harness.get("error"),
        "stdout_log": harness.get("stdout_log"),
        "stderr_log": harness.get("stderr_log"),
    }


def summarize_evaluation(evaluation: dict[str, Any]) -> dict[str, Any] | None:
    if not evaluation:
        return None

    first_error = evaluation.get("first_error") or {}
    feature_scan = evaluation.get("feature_scan") or {}
    commands = {
        command.get("name"): {
            "returncode": command.get("returncode"),
            "effective_success": command.get("effective_success"),
            "effective_failure_reason": command.get("effective_failure_reason"),
        }
        for command in evaluation.get("commands", [])
    }
    return {
        "status": evaluation.get("status"),
        "quality_grade": evaluation.get("quality_grade"),
        "solution": evaluation.get("solution"),
        "first_error": {
            "phase": first_error.get("phase"),
            "returncode": first_error.get("returncode"),
            "effective_failure_reason": first_error.get("effective_failure_reason"),
            "stdout": first_error.get("stdout"),
            "stderr": first_error.get("stderr"),
            "message": first_error.get("message"),
        }
        if first_error
        else None,
        "feature_scan": {
            "required_count": len(feature_scan.get("required", [])),
            "missing_required": feature_scan.get("missing_required", []),
        },
        "test_summary": evaluation.get("test_summary"),
        "test_assessment": evaluation.get("test_assessment"),
        "verify_summary": evaluation.get("verify_summary"),
        "contract_assessment": evaluation.get("contract_assessment"),
        "problems_md": evaluation.get("problems_md"),
        "commands": commands,
    }


def write_batch_report(
    batch_dir: Path,
    batch_id: str,
    results: list[dict[str, Any]],
) -> None:
    passed = sum(1 for item in results if item["status"] == "passed")
    failed = sum(
        1
        for item in results
        if item["status"] in {"failed", "agent_failed", "evaluation_failed"}
    )
    prepared = sum(1 for item in results if item["status"] == "prepared")
    by_status: dict[str, int] = {}
    for item in results:
        status = item["status"]
        by_status[status] = by_status.get(status, 0) + 1
    report = {
        "batch_id": batch_id,
        "passed": passed,
        "failed": failed,
        "prepared": prepared,
        "attempts": len(results),
        "by_status": by_status,
        "results": results,
    }
    (batch_dir / "matrix_report.json").write_text(
        json.dumps(report, indent=2) + "\n",
        encoding="utf-8",
    )
    (batch_dir / "matrix_summary.md").write_text(
        render_batch_summary(report),
        encoding="utf-8",
    )


def render_batch_summary(report: dict[str, Any]) -> str:
    lines = [
        "# Matrix Summary",
        "",
        f"Batch: `{report['batch_id']}`",
        f"Attempts recorded: `{report['attempts']}`",
        f"Passed: `{report['passed']}`",
        f"Failed: `{report['failed']}`",
        f"Prepared only: `{report['prepared']}`",
        f"By status: `{json.dumps(report['by_status'], sort_keys=True)}`",
        "",
        "| Agent | Experiment | Try | Status | Grade | First Error | Run |",
        "| --- | --- | --- | --- | --- | --- | --- |",
    ]
    for item in report["results"]:
        result = item.get("result") or {}
        evaluation = item.get("evaluation") or {}
        first_error = evaluation.get("first_error") or {}
        first_error_label = first_error.get("phase") or "—"
        if first_error.get("effective_failure_reason"):
            first_error_label = f"{first_error_label}: {first_error['effective_failure_reason']}"
        lines.append(
            "| "
            + " | ".join(
                [
                    str(item.get("agent", "—")),
                    str(item.get("experiment", "—")),
                    f"{item.get('attempt', '—')}/{item.get('attempt_count', '—')}",
                    str(item.get("status", "—")),
                    str(result.get("quality_grade") or "—"),
                    first_error_label,
                    f"`{Path(item.get('run_dir', '')).name}`",
                ]
            )
            + " |"
        )
    lines.append("")
    return "\n".join(lines)


def load_json(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {}
    return data if isinstance(data, dict) else {}


if __name__ == "__main__":
    raise SystemExit(main())
