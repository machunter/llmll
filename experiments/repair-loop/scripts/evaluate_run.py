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
    """Two-axis scoring placeholder; Phase 1 emits structural metadata only."""
    if log.get("agent_mode") == "stub":
        return {
            "status": "n/a",
            "reason": "stub agent does not produce a scoreable solution",
        }
    return {
        "status": "pending",
        "reason": (
            "two-axis scoring rubric extension lands in Phase 2; this run's "
            "verifier outputs are captured per-turn for later re-scoring"
        ),
        "correctness_score": None,
        "assurance_score": None,
    }


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
    lines.append(f"{evaluation['scoring']['reason']}")
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
