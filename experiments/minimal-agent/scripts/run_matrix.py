#!/usr/bin/env python3
"""Run a mixed-agent/problem matrix from a JSON manifest."""

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
    args = parser.parse_args()

    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    agents = manifest.get("agents", [])
    problems = manifest.get("problems", [1, 2, 3])
    if not agents:
        raise SystemExit("Manifest must include at least one agent.")

    batch_id = manifest.get("batch_id") or datetime.now(timezone.utc).strftime(
        "%Y%m%dT%H%M%SZ"
    )
    batch_dir = args.output / batch_id
    batch_dir.mkdir(parents=True, exist_ok=False)

    results: list[dict[str, Any]] = []
    any_failed = False

    for agent in agents:
        name = agent["name"]
        cmd = agent["cmd"]
        for problem in problems:
            prepared = prepare_run(batch_dir, batch_id, name, int(problem))
            run_dir = Path(prepared["run_dir"])

            entry: dict[str, Any] = {
                "agent": name,
                "problem": int(problem),
                "run_dir": str(run_dir),
                "status": "prepared",
                "returncode": None,
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
                    llmll_cmd=agent.get("llmll_cmd", manifest.get("llmll_cmd", "llmll")),
                    skip_verify=bool(agent.get("skip_verify", manifest.get("skip_verify", False))),
                )
                entry["returncode"] = rc
                entry["status"] = "passed" if rc == 0 else "failed"
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


def prepare_run(batch_dir: Path, batch_id: str, agent_name: str, problem: int) -> dict[str, str]:
    cmd = [
        sys.executable,
        str(PREPARE),
        "--problem",
        str(problem),
        "--output",
        str(batch_dir),
        "--run-id",
        batch_id,
        "--label",
        agent_name,
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


def write_batch_report(
    batch_dir: Path,
    batch_id: str,
    results: list[dict[str, Any]],
) -> None:
    passed = sum(1 for item in results if item["status"] == "passed")
    failed = sum(1 for item in results if item["status"] == "failed")
    prepared = sum(1 for item in results if item["status"] == "prepared")
    report = {
        "batch_id": batch_id,
        "passed": passed,
        "failed": failed,
        "prepared": prepared,
        "results": results,
    }
    (batch_dir / "matrix_report.json").write_text(
        json.dumps(report, indent=2) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    raise SystemExit(main())
