#!/usr/bin/env python3
"""Evaluate a minimal-agent run directory, stopping at the first tool error."""

from __future__ import annotations

import argparse
import json
import re
import shlex
import subprocess
import time
from pathlib import Path
from typing import Any


FEATURE_PATTERNS = {
    "type": r"\(type\b|\"kind\"\s*:\s*\"type\"",
    "def-interface": r"\(def-interface\b|\"kind\"\s*:\s*\"def-interface\"",
    "def-invariant": r"\(def-invariant\b|\"kind\"\s*:\s*\"def-invariant\"",
    "check": r"\(check\b|\"kind\"\s*:\s*\"check\"",
    "pre": r"\(pre\b|\"pre\"\s*:",
    "post": r"\(post\b|\"post\"\s*:",
    "delegate": r"\?delegate(?!-)\b|\"kind\"\s*:\s*\"hole-delegate\"",
    "delegate-async": r"\?delegate-async\b|\"kind\"\s*:\s*\"hole-delegate-async\"",
    "await": r"\(await\b|\"kind\"\s*:\s*\"await\"",
    "on-failure": r"\bon-failure\b|\"on_failure\"\s*:",
    "DelegationError": r"\bDelegationError\b",
    "Result": r"\bResult\b|\"kind\"\s*:\s*\"result\"",
    "Promise": r"\bPromise\b|\"kind\"\s*:\s*\"promise\"",
    "proof-required": r"\?proof-required\b|\"kind\"\s*:\s*\"hole-proof-required\"",
    "scaffold": r"\?scaffold\b|\"kind\"\s*:\s*\"hole-scaffold\"",
}

REQUIRED_FEATURES = {
    1: ["def-interface", "delegate", "on-failure", "check", "pre", "Result"],
    2: [
        "def-interface",
        "delegate",
        "delegate-async",
        "await",
        "DelegationError",
        "Promise",
        "Result",
        "proof-required",
        "def-invariant",
        "check",
        "pre",
        "post",
    ],
    3: [
        "type",
        "def-interface",
        "delegate",
        "delegate-async",
        "await",
        "on-failure",
        "DelegationError",
        "Result",
        "proof-required",
        "def-invariant",
        "check",
        "pre",
        "post",
        "scaffold",
    ],
}


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Evaluate a prepared LLMLL experiment run directory."
    )
    parser.add_argument("run_dir", type=Path, help="Prepared run directory.")
    parser.add_argument(
        "--llmll-cmd",
        default="llmll",
        help='Compiler command prefix. Examples: "llmll" or "stack --stack-yaml compiler/stack.yaml exec llmll --".',
    )
    parser.add_argument(
        "--solution",
        type=Path,
        default=None,
        help="Explicit solution file. Defaults to solution.llmll, then solution.ast.json.",
    )
    parser.add_argument(
        "--skip-verify",
        action="store_true",
        help="Skip the verify/trust/spec-coverage command.",
    )
    parser.add_argument(
        "--timeout-seconds",
        type=int,
        default=300,
        help="Timeout for each compiler command.",
    )
    args = parser.parse_args()

    run_dir = args.run_dir.resolve()
    metadata = load_metadata(run_dir)
    solution = find_solution(run_dir, args.solution)

    report: dict[str, Any] = {
        "run_dir": str(run_dir),
        "problem_id": metadata.get("problem_id"),
        "status": "failed",
        "stop_policy": "first_error",
        "solution": str(solution) if solution else None,
        "feature_scan": None,
        "commands": [],
        "first_error": None,
    }

    if solution is None:
        report["first_error"] = {
            "phase": "solution-discovery",
            "message": "No solution.llmll or solution.ast.json found.",
        }
        write_outputs(run_dir, report)
        return 1

    report["feature_scan"] = scan_features(solution, metadata.get("problem_id"))

    llmll = shlex.split(args.llmll_cmd)
    solution_name = solution.name
    commands = [
        ("check", llmll + ["check", solution_name]),
        ("check-strict", llmll + ["check", solution_name, "--strict"]),
        ("holes", llmll + ["--json", "holes", "--deps", solution_name]),
        ("test", llmll + ["test", solution_name]),
    ]
    if not args.skip_verify:
        commands.append(
            (
                "verify",
                llmll
                + [
                    "verify",
                    solution_name,
                    "--trust-report",
                    "--weakness-check",
                    "--spec-coverage",
                ],
            )
        )

    for name, argv in commands:
        result = run_command(name, argv, cwd=run_dir, timeout=args.timeout_seconds)
        report["commands"].append(result)
        if result["returncode"] != 0:
            report["first_error"] = {
                "phase": name,
                "argv": argv,
                "returncode": result["returncode"],
                "stderr": result["stderr"],
                "stdout": result["stdout"],
            }
            write_outputs(run_dir, report)
            return 1

    report["status"] = "passed"
    write_outputs(run_dir, report)
    return 0


def load_metadata(run_dir: Path) -> dict[str, Any]:
    path = run_dir / ".llmll-experiment.json"
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {}


def find_solution(run_dir: Path, explicit: Path | None) -> Path | None:
    if explicit:
        candidate = explicit if explicit.is_absolute() else run_dir / explicit
        return candidate if candidate.exists() else None
    for name in ("solution.llmll", "solution.ast.json"):
        candidate = run_dir / name
        if candidate.exists():
            return candidate
    return None


def scan_features(solution: Path, problem_id: Any) -> dict[str, Any]:
    text = solution.read_text(encoding="utf-8")
    found = {
        name: bool(re.search(pattern, text))
        for name, pattern in FEATURE_PATTERNS.items()
    }
    try:
        pid = int(problem_id)
    except (TypeError, ValueError):
        pid = 0
    required = REQUIRED_FEATURES.get(pid, [])
    missing = [name for name in required if not found.get(name, False)]
    return {
        "required": required,
        "found": found,
        "missing_required": missing,
    }


def run_command(
    name: str,
    argv: list[str],
    *,
    cwd: Path,
    timeout: int,
) -> dict[str, Any]:
    started = time.monotonic()
    try:
        result = subprocess.run(
            argv,
            cwd=cwd,
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
        return {
            "name": name,
            "argv": argv,
            "returncode": result.returncode,
            "duration_seconds": round(time.monotonic() - started, 3),
            "stdout": result.stdout,
            "stderr": result.stderr,
        }
    except FileNotFoundError as exc:
        return {
            "name": name,
            "argv": argv,
            "returncode": 127,
            "duration_seconds": round(time.monotonic() - started, 3),
            "stdout": "",
            "stderr": str(exc),
        }
    except subprocess.TimeoutExpired as exc:
        return {
            "name": name,
            "argv": argv,
            "returncode": 124,
            "duration_seconds": round(time.monotonic() - started, 3),
            "stdout": exc.stdout or "",
            "stderr": exc.stderr or f"Timed out after {timeout} seconds.",
        }


def write_outputs(run_dir: Path, report: dict[str, Any]) -> None:
    (run_dir / "evaluation.json").write_text(
        json.dumps(report, indent=2) + "\n",
        encoding="utf-8",
    )
    (run_dir / "summary.md").write_text(render_summary(report), encoding="utf-8")


def render_summary(report: dict[str, Any]) -> str:
    lines = [
        "# Evaluation Summary",
        "",
        f"Status: `{report['status']}`",
        f"Problem: `{report.get('problem_id')}`",
        f"Solution: `{report.get('solution')}`",
        f"Stop policy: `{report['stop_policy']}`",
        "",
    ]

    first_error = report.get("first_error")
    if first_error:
        lines.extend(
            [
                "## First Error",
                "",
                f"Phase: `{first_error.get('phase')}`",
                f"Return code: `{first_error.get('returncode', 'n/a')}`",
                "",
            ]
        )
        message = first_error.get("message")
        if message:
            lines.extend(["Message:", "", "```text", message, "```", ""])
        stderr = first_error.get("stderr")
        if stderr:
            lines.extend(["Stderr:", "", "```text", truncate(stderr), "```", ""])
        stdout = first_error.get("stdout")
        if stdout:
            lines.extend(["Stdout:", "", "```text", truncate(stdout), "```", ""])

    feature_scan = report.get("feature_scan")
    if feature_scan:
        lines.extend(["## Feature Scan", ""])
        missing = feature_scan.get("missing_required", [])
        if missing:
            lines.append("Missing required markers: " + ", ".join(f"`{m}`" for m in missing))
        else:
            lines.append("All required feature markers were found.")
        lines.append("")

    lines.extend(["## Commands", ""])
    for command in report.get("commands", []):
        argv = " ".join(shlex.quote(part) for part in command["argv"])
        lines.append(
            f"- `{command['name']}` rc={command['returncode']} "
            f"duration={command['duration_seconds']}s: `{argv}`"
        )
    lines.append("")
    return "\n".join(lines)


def truncate(value: str, limit: int = 4000) -> str:
    if len(value) <= limit:
        return value
    return value[:limit] + "\n...[truncated]..."


if __name__ == "__main__":
    raise SystemExit(main())
