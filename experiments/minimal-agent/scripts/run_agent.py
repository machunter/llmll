#!/usr/bin/env python3
"""Run a supplied agent command inside one prepared experiment directory."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
EVALUATOR = SCRIPT_DIR / "evaluate_run.py"


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Run an arbitrary agent command in a prepared LLMLL experiment directory."
    )
    parser.add_argument("run_dir", type=Path, help="Prepared run directory.")
    parser.add_argument(
        "--agent-cmd",
        required=True,
        help="Agent command to execute. It runs through the shell with cwd set to run_dir.",
    )
    parser.add_argument(
        "--agent-name",
        default="agent",
        help="Human-readable agent name for logs.",
    )
    parser.add_argument(
        "--timeout-seconds",
        type=int,
        default=1800,
        help="Timeout for the agent command.",
    )
    parser.add_argument(
        "--llmll-cmd",
        default="llmll",
        help="Compiler command prefix passed to evaluate_run.py.",
    )
    parser.add_argument(
        "--skip-verify",
        action="store_true",
        help="Skip verify during evaluation.",
    )
    parser.add_argument(
        "--no-evaluate",
        action="store_true",
        help="Do not run evaluation after the agent exits successfully.",
    )
    args = parser.parse_args()

    run_dir = args.run_dir.resolve()
    logs = run_dir / "logs"
    logs.mkdir(exist_ok=True)

    stdout_path = logs / "agent.stdout.log"
    stderr_path = logs / "agent.stderr.log"
    started_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    started = time.monotonic()

    append_event(
        run_dir,
        {
            "event": "agent-start",
            "agent_name": args.agent_name,
            "agent_cmd": args.agent_cmd,
            "started_at": started_at,
        },
    )

    try:
        with stdout_path.open("w", encoding="utf-8") as stdout, stderr_path.open(
            "w", encoding="utf-8"
        ) as stderr:
            result = subprocess.run(
                args.agent_cmd,
                cwd=run_dir,
                shell=True,
                stdout=stdout,
                stderr=stderr,
                timeout=args.timeout_seconds,
                check=False,
            )
        agent_rc = result.returncode
        status = "passed" if agent_rc == 0 else "failed"
        error = None
    except subprocess.TimeoutExpired:
        agent_rc = 124
        status = "failed"
        error = f"Agent command timed out after {args.timeout_seconds} seconds."
        (run_dir / "HARNESS_STOPPED.md").write_text(error + "\n", encoding="utf-8")

    duration = round(time.monotonic() - started, 3)
    harness_result = {
        "agent_name": args.agent_name,
        "agent_cmd": args.agent_cmd,
        "status": status,
        "returncode": agent_rc,
        "duration_seconds": duration,
        "stdout_log": str(stdout_path),
        "stderr_log": str(stderr_path),
        "error": error,
    }
    (run_dir / "harness_result.json").write_text(
        json.dumps(harness_result, indent=2) + "\n",
        encoding="utf-8",
    )
    append_event(run_dir, {"event": "agent-finish", **harness_result})

    if agent_rc != 0:
        return agent_rc

    if args.no_evaluate:
        return 0

    eval_cmd = [
        sys.executable,
        str(EVALUATOR),
        str(run_dir),
        "--llmll-cmd",
        args.llmll_cmd,
        "--timeout-seconds",
        "300",
    ]
    if args.skip_verify:
        eval_cmd.append("--skip-verify")
    append_event(run_dir, {"event": "evaluation-start", "argv": eval_cmd})
    eval_result = subprocess.run(eval_cmd, check=False)
    append_event(
        run_dir,
        {"event": "evaluation-finish", "returncode": eval_result.returncode},
    )
    return eval_result.returncode


def append_event(run_dir: Path, event: dict) -> None:
    event = {
        "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        **event,
    }
    with (run_dir / "logs" / "events.jsonl").open("a", encoding="utf-8") as f:
        f.write(json.dumps(event) + "\n")


if __name__ == "__main__":
    raise SystemExit(main())
