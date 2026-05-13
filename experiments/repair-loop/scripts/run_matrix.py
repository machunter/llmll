#!/usr/bin/env python3
"""Run a repair-loop matrix from a manifest.

A matrix enumerates cells as (target, experiment, agent, attempt) and invokes
`run_repair_loop.py` once per cell. The matrix runner owns:

  - Cell enumeration with a stable 1-based index (the unit for --resume-from-cell).
  - Per-cell synthetic manifest generation, resolving target-specific terminal_target
    from manifest.terminal_target_per_target (Phase 2 spans mixed verification
    surfaces: trust-tier for LLMLL, all-pass for Python/Go).
  - Pre-flight prerequisite checks: required env vars and executables per agent,
    declared in the manifest. Fails fast before any cell launch.
  - Per-cell evaluator invocation (evaluate_run.py) after run_repair_loop.py exits.
  - Aggregating matrix_report.json / matrix_summary.md.

Cells are ordered: target outer, experiment, agent, attempt inner. This groups
all tries of a single (target, experiment, agent) contiguously, which matches the
Addendum-10 cell pin and makes adapter-specific debugging easier.

For a 9-cell Phase 2 run at k=5 × 540s/turn the wall-clock ceiling is ~6.75h.
--resume-from-cell N is load-bearing under that budget.
"""

from __future__ import annotations

import argparse
import json
import os
import shlex
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


SCRIPT_DIR = Path(__file__).resolve().parent
HARNESS_ROOT = SCRIPT_DIR.parent
RUN_REPAIR_LOOP = SCRIPT_DIR / "run_repair_loop.py"
EVALUATE_RUN = SCRIPT_DIR / "evaluate_run.py"
DEFAULT_RUN_COUNT = 3


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Run a repair-loop matrix from a JSON manifest.",
    )
    parser.add_argument("manifest", type=Path, help="JSON manifest file.")
    parser.add_argument(
        "--output",
        type=Path,
        default=HARNESS_ROOT / "runs",
        help="Output root for batch metadata directories (default: experiments/repair-loop/runs).",
    )
    parser.add_argument(
        "--batch-id",
        type=str,
        default=None,
        help="Reuse an existing batch metadata directory. Required when resuming into a prior batch.",
    )
    parser.add_argument(
        "--resume-from-cell",
        type=int,
        default=1,
        help="1-based cell index to start at. Cells before this index are skipped (default: 1).",
    )
    parser.add_argument(
        "--prepare-only",
        action="store_true",
        help="Enumerate the matrix, write the plan, do not launch cells. Skips prereq checks.",
    )
    parser.add_argument(
        "--fail-fast",
        action="store_true",
        help="Stop the matrix on the first failed cell.",
    )
    parser.add_argument(
        "--skip-prereqs",
        action="store_true",
        help="Bypass per-agent prerequisite checks. Use only for offline harness work.",
    )
    parser.add_argument(
        "--no-evaluate",
        action="store_true",
        help="Do not invoke evaluate_run.py after each cell.",
    )
    parser.add_argument(
        "--llmll-cmd",
        type=str,
        default=None,
        help="Compiler command prefix. Overrides manifest.llmll_cmd; forwarded to run_repair_loop.py.",
    )
    args = parser.parse_args()

    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    cells = enumerate_cells(manifest)
    if not cells:
        raise SystemExit("Manifest enumerates zero cells; check experiments/targets/agents/run_count.")

    if args.resume_from_cell < 1 or args.resume_from_cell > len(cells):
        raise SystemExit(
            f"--resume-from-cell {args.resume_from_cell} out of range [1, {len(cells)}]."
        )

    batch_dir = resolve_batch_dir(args, manifest)
    batch_dir.mkdir(parents=True, exist_ok=True)
    (batch_dir / "cells").mkdir(exist_ok=True)

    snapshot_manifest_path = batch_dir / "matrix_manifest.json"
    if not snapshot_manifest_path.exists():
        snapshot = dict(manifest)
        snapshot["_harness_git_sha"] = _capture_git_sha()
        snapshot["_snapshotted_at"] = _utc_now()
        snapshot_manifest_path.write_text(json.dumps(snapshot, indent=2) + "\n")

    plan_path = batch_dir / "matrix_plan.json"
    plan_path.write_text(json.dumps({"cells": cells}, indent=2) + "\n")

    if not args.prepare_only and not args.skip_prereqs:
        prereq_failures = check_prereqs(manifest.get("agents", []))
        if prereq_failures:
            for line in prereq_failures:
                print(f"prereq: {line}", file=sys.stderr)
            raise SystemExit(
                "Prerequisite checks failed. Fix and re-run, or pass --skip-prereqs to bypass."
            )

    results = load_existing_results(batch_dir)
    completed_indices = {r["cell"] for r in results}

    any_failed = any(
        r.get("status") not in {"target-reached", "budget-exhausted", "prepared", None}
        for r in results
    )

    for cell in cells:
        idx = cell["cell"]
        if idx < args.resume_from_cell:
            continue
        if idx in completed_indices:
            print(f"cell {idx:02d}: already in matrix_report.json; skipping (re-run with fresh --batch-id to retry).")
            continue

        entry = run_one_cell(
            cell=cell,
            batch_dir=batch_dir,
            manifest=manifest,
            args=args,
        )
        results.append(entry)
        write_batch_report(batch_dir, results, total_cells=len(cells))

        if entry.get("status") in {"infrastructure-fail", "harness-error"}:
            any_failed = True
            if args.fail_fast:
                print(f"cell {idx:02d}: {entry['status']}; --fail-fast set, halting.", file=sys.stderr)
                return 1

    return 1 if any_failed else 0


def enumerate_cells(manifest: dict[str, Any]) -> list[dict[str, Any]]:
    """Enumerate matrix cells in deterministic order: target × experiment × agent × attempt.

    Each cell gets a 1-based index used by --resume-from-cell. Order is fixed so
    --resume semantics are stable across reruns of the same manifest.
    """
    experiments = manifest.get("experiments", [])
    targets = manifest.get("targets", [])
    agents = manifest.get("agents", [])
    manifest_run_count = int(manifest.get("run_count", DEFAULT_RUN_COUNT))

    if not experiments:
        raise SystemExit("Manifest must list at least one experiment.")
    if not targets:
        raise SystemExit("Manifest must list at least one target.")
    if not agents:
        raise SystemExit("Manifest must list at least one agent.")

    cells: list[dict[str, Any]] = []
    idx = 0
    for target in targets:
        for experiment in experiments:
            for agent in agents:
                attempts = int(agent.get("run_count", manifest_run_count))
                if attempts < 1:
                    raise SystemExit(
                        f"Agent {agent.get('name')!r} run_count must be >= 1 (got {attempts})."
                    )
                for attempt in range(1, attempts + 1):
                    idx += 1
                    cells.append(
                        {
                            "cell": idx,
                            "target": str(target),
                            "experiment": str(experiment),
                            "agent": agent["name"],
                            "attempt": attempt,
                            "attempt_count": attempts,
                        }
                    )
    return cells


def resolve_batch_dir(args: argparse.Namespace, manifest: dict[str, Any]) -> Path:
    batch_id = args.batch_id or manifest.get("batch_id") or _utc_batch_stamp()
    label = manifest.get("batch_label") or "matrix"
    name = f"{batch_id}-{label}"
    return args.output / name


def check_prereqs(agents: list[dict[str, Any]]) -> list[str]:
    """Validate per-agent prerequisites declared in the manifest.

    Each agent may declare:
      - required_env: list[str]          env vars that must be set and non-empty
      - required_executables: list[str]  binaries that must resolve via shutil.which

    Returns a list of human-readable failure messages. Empty list = all OK.
    Failures are accumulated (does not short-circuit) so the operator sees the
    full prereq surface in one pass.
    """
    failures: list[str] = []
    for agent in agents:
        name = agent.get("name", "<unnamed>")
        for var in agent.get("required_env", []) or []:
            if not os.environ.get(var):
                failures.append(f"agent {name!r}: env var {var!r} is not set or empty")
        for exe in agent.get("required_executables", []) or []:
            if shutil.which(exe) is None:
                failures.append(f"agent {name!r}: executable {exe!r} not found on PATH")
    return failures


def run_one_cell(
    *,
    cell: dict[str, Any],
    batch_dir: Path,
    manifest: dict[str, Any],
    args: argparse.Namespace,
) -> dict[str, Any]:
    idx = cell["cell"]
    cell_dir = batch_dir / "cells" / f"cell_{idx:02d}"
    cell_dir.mkdir(exist_ok=True)

    synthetic_manifest = build_cell_manifest(manifest, cell)
    cell_manifest_path = cell_dir / "manifest.json"
    cell_manifest_path.write_text(json.dumps(synthetic_manifest, indent=2) + "\n")

    agent_block = _find_agent(manifest, cell["agent"])
    if agent_block is None:
        return {
            **cell,
            "status": "harness-error",
            "error": f"agent {cell['agent']!r} not in manifest",
            "run_dir": None,
        }

    label = f"{cell['agent']}-try{cell['attempt']:02d}-of-{cell['attempt_count']:02d}-c{idx:02d}"

    if args.prepare_only:
        return {**cell, "status": "prepared", "run_dir": None, "cell_dir": str(cell_dir)}

    print(
        f"cell {idx:02d}/{len(_load_plan(batch_dir))}: "
        f"agent={cell['agent']} experiment={cell['experiment']} target={cell['target']} "
        f"attempt={cell['attempt']}/{cell['attempt_count']}"
    )

    cmd = [
        sys.executable,
        str(RUN_REPAIR_LOOP),
        "--manifest", str(cell_manifest_path),
        "--experiment", cell["experiment"],
        "--target", cell["target"],
        "--agent-name", cell["agent"],
        "--agent-cmd", agent_block["cmd"],
        "--label", label,
    ]
    llmll_cmd = args.llmll_cmd or manifest.get("llmll_cmd")
    if llmll_cmd:
        cmd.extend(["--llmll-cmd", llmll_cmd])

    stdout_path = cell_dir / "orchestrator.stdout.log"
    stderr_path = cell_dir / "orchestrator.stderr.log"
    with stdout_path.open("w") as out, stderr_path.open("w") as err:
        rc = subprocess.run(cmd, stdout=out, stderr=err, check=False).returncode

    run_dir = _extract_run_dir(stdout_path)
    entry: dict[str, Any] = {
        **cell,
        "cell_dir": str(cell_dir),
        "orchestrator_rc": rc,
        "run_dir": str(run_dir) if run_dir else None,
        "status": "harness-error" if rc != 0 or run_dir is None else None,
    }

    if run_dir is not None and run_dir.exists():
        try:
            (cell_dir / "run_dir").symlink_to(run_dir, target_is_directory=True)
        except (OSError, FileExistsError):
            pass

        log = _load_json(run_dir / "repair_loop_log.json")
        entry["terminal_state"] = log.get("terminal_state")
        entry["terminal_reason"] = log.get("terminal_reason")
        entry["turns_completed"] = len(log.get("turns", []))
        entry["status"] = log.get("terminal_state") or entry["status"] or "unknown"

        if not args.no_evaluate:
            ev_rc = subprocess.run(
                [sys.executable, str(EVALUATE_RUN), str(run_dir)],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            ).returncode
            evaluation = _load_json(run_dir / "evaluation.json")
            entry["evaluation"] = {
                "rc": ev_rc,
                "apparatus_status": (evaluation.get("apparatus") or {}).get("status"),
                "scoring": evaluation.get("scoring"),
            }

    return entry


def build_cell_manifest(manifest: dict[str, Any], cell: dict[str, Any]) -> dict[str, Any]:
    """Generate a single-cell synthetic manifest for run_repair_loop.py.

    Resolves target-specific terminal_target from manifest.terminal_target_per_target
    when present, falling back to manifest.terminal_target. Drops other agents and
    experiments / targets / run_count so the synthetic manifest scopes exactly to
    this cell.
    """
    target = cell["target"]
    per_target = manifest.get("terminal_target_per_target") or {}
    terminal_target = per_target.get(target) or manifest.get("terminal_target") or {}

    return {
        "_purpose": f"Synthetic per-cell manifest for cell {cell['cell']:02d}: "
                     f"{cell['agent']} × {cell['experiment']} × {target} × attempt {cell['attempt']}.",
        "_derived_from": manifest.get("_purpose", "<unlabelled parent manifest>"),
        "experiments": [cell["experiment"]],
        "targets": [target],
        "run_count": 1,
        "repair_budget_k": int(manifest.get("repair_budget_k", 3)),
        "terminal_target": terminal_target,
        "timeout_seconds_per_turn": int(manifest.get("timeout_seconds_per_turn", 600)),
        "llmll_cmd": manifest.get("llmll_cmd", "llmll"),
        "agents": [_find_agent(manifest, cell["agent"])],
    }


def load_existing_results(batch_dir: Path) -> list[dict[str, Any]]:
    report_path = batch_dir / "matrix_report.json"
    if not report_path.exists():
        return []
    data = json.loads(report_path.read_text(encoding="utf-8"))
    results = data.get("results", [])
    return results if isinstance(results, list) else []


def write_batch_report(
    batch_dir: Path,
    results: list[dict[str, Any]],
    *,
    total_cells: int,
) -> None:
    by_status: dict[str, int] = {}
    for r in results:
        status = r.get("status") or "unknown"
        by_status[status] = by_status.get(status, 0) + 1

    report = {
        "batch_dir": str(batch_dir),
        "total_cells": total_cells,
        "cells_recorded": len(results),
        "by_status": by_status,
        "results": results,
    }
    (batch_dir / "matrix_report.json").write_text(json.dumps(report, indent=2) + "\n")
    (batch_dir / "matrix_summary.md").write_text(render_summary(report))


def render_summary(report: dict[str, Any]) -> str:
    lines = [
        "# Repair-Loop Matrix Summary",
        "",
        f"Batch dir: `{report['batch_dir']}`",
        f"Cells recorded: `{report['cells_recorded']}` / `{report['total_cells']}`",
        f"By status: `{json.dumps(report['by_status'], sort_keys=True)}`",
        "",
        "| # | Agent | Experiment | Target | Try | Status | Turns | Terminal Reason | Run |",
        "| --- | --- | --- | --- | --- | --- | --- | --- | --- |",
    ]
    for r in report["results"]:
        run_dir = r.get("run_dir") or ""
        run_label = f"`{Path(run_dir).name}`" if run_dir else "—"
        lines.append(
            "| "
            + " | ".join(
                [
                    str(r.get("cell", "—")),
                    str(r.get("agent", "—")),
                    str(r.get("experiment", "—")),
                    str(r.get("target", "—")),
                    f"{r.get('attempt', '—')}/{r.get('attempt_count', '—')}",
                    str(r.get("status") or "—"),
                    str(r.get("turns_completed") or "—"),
                    (r.get("terminal_reason") or "—").replace("|", "\\|"),
                    run_label,
                ]
            )
            + " |"
        )
    lines.append("")
    return "\n".join(lines)


def _find_agent(manifest: dict[str, Any], name: str) -> dict[str, Any] | None:
    for agent in manifest.get("agents", []):
        if agent.get("name") == name:
            return agent
    return None


def _extract_run_dir(stdout_log: Path) -> Path | None:
    """run_repair_loop.py prints `run_dir: <path>` on its first stdout line."""
    if not stdout_log.exists():
        return None
    for line in stdout_log.read_text(encoding="utf-8", errors="replace").splitlines():
        if line.startswith("run_dir: "):
            return Path(line[len("run_dir: "):].strip())
    return None


def _load_json(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {}
    return data if isinstance(data, dict) else {}


def _load_plan(batch_dir: Path) -> list[dict[str, Any]]:
    plan = _load_json(batch_dir / "matrix_plan.json").get("cells") or []
    return plan if isinstance(plan, list) else []


def _utc_batch_stamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def _utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _capture_git_sha() -> dict[str, Any]:
    """Capture HEAD SHA + dirty-tree flag for postmortem reproducibility."""
    try:
        sha = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=HARNESS_ROOT,
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
        )
        if sha.returncode != 0:
            return {"error": sha.stderr.strip()[:200] or "git rev-parse failed"}
        dirty = subprocess.run(
            ["git", "status", "--porcelain"],
            cwd=HARNESS_ROOT,
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
        )
        return {
            "sha": sha.stdout.strip(),
            "dirty": bool(dirty.stdout.strip()) if dirty.returncode == 0 else None,
        }
    except (FileNotFoundError, subprocess.TimeoutExpired) as e:
        return {"error": str(e)}


if __name__ == "__main__":
    raise SystemExit(main())
