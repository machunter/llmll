#!/usr/bin/env python3
"""Orchestrate one repair-loop cell: agent × problem × target × attempt.

A cell runs up to `repair_budget_k` turns. Each turn:
  1. Invoke the agent with cwd set to the run directory.
  2. Run the target adapter's verifier commands on the agent's solution.
  3. Capture verifier output to `context/turn_NN_verifier.json` for the
     next turn's context.
  4. Evaluate the terminal-target predicate. If matched, exit early with
     `terminal_state: target-reached`. Otherwise, continue to turn N+1.

If `repair_budget_k` turns elapse without matching the predicate, the cell
exits with `terminal_state: budget-exhausted`. Both are valid outcomes.

For apparatus validation without API spend, use --stub-agent. The stub writes
a deterministic per-turn solution that the verifier rejects, demonstrating
that the orchestrator captures and re-injects verifier output across turns.
"""

from __future__ import annotations

import argparse
import json
import shlex
import shutil
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


SCRIPT_DIR = Path(__file__).resolve().parent
HARNESS_ROOT = SCRIPT_DIR.parent
REPO_ROOT = HARNESS_ROOT.parent.parent


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Run one repair-loop cell against a manifest.",
    )
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--experiment", required=True,
                        help="Experiment slug; matches problems/<slug>.md")
    parser.add_argument("--target", required=True,
                        help="Target slug; matches targets/<slug>.json")
    parser.add_argument("--agent-name", required=True)
    parser.add_argument("--agent-cmd", default=None,
                        help="Agent command. Required unless --stub-agent.")
    parser.add_argument("--stub-agent", action="store_true",
                        help="Use deterministic stub agent for apparatus validation.")
    parser.add_argument("--llmll-cmd", default=None,
                        help="Compiler command prefix; overrides manifest.")
    parser.add_argument("--label", default=None,
                        help="Optional run-directory label suffix.")
    args = parser.parse_args()

    if not args.stub_agent and not args.agent_cmd:
        parser.error("--agent-cmd is required unless --stub-agent is set")

    manifest = json.loads(args.manifest.read_text())
    target_path = HARNESS_ROOT / "targets" / f"{args.target}.json"
    if not target_path.exists():
        print(f"target adapter not found: {target_path}", file=sys.stderr)
        return 2
    target = json.loads(target_path.read_text())

    problem_path = HARNESS_ROOT / "problems" / f"{args.experiment}.md"
    if not problem_path.exists():
        print(f"problem not found: {problem_path}", file=sys.stderr)
        return 2

    k = int(manifest.get("repair_budget_k", 3))
    timeout_per_turn = int(manifest.get("timeout_seconds_per_turn", 600))
    terminal_target = manifest.get("terminal_target", {})
    llmll_cmd = args.llmll_cmd or manifest.get("llmll_cmd", "llmll")

    run_dir = _prepare_run_dir(args, manifest, target, problem_path)
    log: dict[str, Any] = {
        "harness": "repair-loop",
        "phase": "1-apparatus-validation" if args.stub_agent else "n/a",
        "agent_name": args.agent_name,
        "agent_mode": "stub" if args.stub_agent else "real",
        "experiment": args.experiment,
        "target": args.target,
        "repair_budget_k": k,
        "terminal_target": terminal_target,
        "compiler_version_pin": _capture_compiler_version(llmll_cmd, target),
        "run_dir": str(run_dir),
        "started_at": _utc_now(),
        "turns": [],
        "terminal_state": None,
        "terminal_reason": None,
    }
    log_path = run_dir / "repair_loop_log.json"
    _write_json(log_path, log)

    for turn_idx in range(1, k + 1):
        turn_record = _run_one_turn(
            turn_idx=turn_idx,
            run_dir=run_dir,
            target=target,
            terminal_target=terminal_target,
            args=args,
            timeout_per_turn=timeout_per_turn,
            llmll_cmd=llmll_cmd,
            stub_agent=args.stub_agent,
        )
        log["turns"].append(turn_record)
        _write_json(log_path, log)

        if turn_record["terminal_target_match"]:
            log["terminal_state"] = "target-reached"
            log["terminal_reason"] = (
                f"terminal predicate matched at turn {turn_idx}"
            )
            break

        if turn_record["agent_rc"] != 0:
            log["terminal_state"] = "infrastructure-fail"
            log["terminal_reason"] = (
                f"agent rc={turn_record['agent_rc']} at turn {turn_idx}"
            )
            break

    if log["terminal_state"] is None:
        log["terminal_state"] = "budget-exhausted"
        log["terminal_reason"] = f"{k} turns elapsed without terminal match"

    log["finished_at"] = _utc_now()
    _write_json(log_path, log)

    print(f"run_dir: {run_dir}")
    print(f"terminal_state: {log['terminal_state']}")
    print(f"terminal_reason: {log['terminal_reason']}")
    print(f"turns: {len(log['turns'])}")
    return 0


def _prepare_run_dir(args, manifest, target, problem_path: Path) -> Path:
    label = args.label or args.agent_name
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    name = f"{timestamp}-{label}-e{args.experiment}-{args.target}"
    runs_root = HARNESS_ROOT / "runs"
    runs_root.mkdir(exist_ok=True)
    run_dir = runs_root / name
    run_dir.mkdir(parents=True, exist_ok=False)
    (run_dir / "context").mkdir()
    (run_dir / "turns").mkdir()

    shutil.copy(problem_path, run_dir / "problem.md")

    target_md = run_dir / "TARGET.md"
    target_md.write_text(_target_descriptor(target))

    agent_instructions = run_dir / "AGENT_INSTRUCTIONS.md"
    agent_instructions.write_text(_agent_instructions(target, manifest))

    return run_dir


def _target_descriptor(target: dict[str, Any]) -> str:
    expected = ", ".join(target.get("expected_files_priority", []))
    commands = "\n".join(
        f"- {c['name']}: `{' '.join(c['argv'])}`"
        for c in target.get("verifier_commands", [])
    )
    return (
        f"# Target: {target['target']}\n\n"
        f"## Expected solution files (priority order)\n\n{expected}\n\n"
        f"## Verifier commands (orchestrator runs these each turn)\n\n{commands}\n\n"
        f"## Scoring\n\n"
        f"- Correctness rubric: `{target['scoring']['correctness_rubric']}`\n"
        f"- Assurance rubric: `{target['scoring']['assurance_rubric']}`\n"
    )


def _agent_instructions(target: dict[str, Any], manifest: dict[str, Any]) -> str:
    return (
        "# Agent Instructions — Repair Loop\n\n"
        f"You are participating in a repair-loop experiment ({manifest.get('repair_budget_k', 3)} turn budget).\n\n"
        "Each turn:\n"
        "1. Read `problem.md` and `TARGET.md`.\n"
        "2. If `context/turn_NN_verifier.json` exists from prior turns, read the latest one and use the verifier output to revise your solution.\n"
        "3. Write your solution to the expected solution file(s) for this target (see TARGET.md).\n"
        "4. Exit 0 on success; non-zero on agent infrastructure failure.\n\n"
        "Do not iterate within a single turn. One agent invocation produces one solution emission;\n"
        "the orchestrator captures the verifier feedback and re-invokes you on the next turn.\n"
    )


def _run_one_turn(
    *,
    turn_idx: int,
    run_dir: Path,
    target: dict[str, Any],
    terminal_target: dict[str, Any],
    args,
    timeout_per_turn: int,
    llmll_cmd: str,
    stub_agent: bool,
) -> dict[str, Any]:
    turn_dir = run_dir / "turns" / f"turn_{turn_idx:02d}"
    turn_dir.mkdir(parents=True)

    agent_started = _utc_now()
    if stub_agent:
        agent_rc, agent_error = _invoke_stub_agent(turn_idx, run_dir, target)
    else:
        agent_rc, agent_error = _invoke_real_agent(
            turn_idx=turn_idx,
            run_dir=run_dir,
            turn_dir=turn_dir,
            agent_cmd=args.agent_cmd,
            timeout=timeout_per_turn,
        )
    agent_finished = _utc_now()

    verifier_results, terminal_match, terminal_reason = _run_verifier_chain(
        target=target,
        terminal_target=terminal_target,
        run_dir=run_dir,
        llmll_cmd=llmll_cmd,
    )

    turn_artifact = turn_dir / "verifier.json"
    context_artifact = run_dir / "context" / f"turn_{turn_idx:02d}_verifier.json"
    payload = {
        "turn": turn_idx,
        "verifier_results": verifier_results,
        "terminal_target_match": terminal_match,
        "terminal_target_reason": terminal_reason,
    }
    _write_json(turn_artifact, payload)
    _write_json(context_artifact, payload)

    return {
        "turn": turn_idx,
        "agent_started_at": agent_started,
        "agent_finished_at": agent_finished,
        "agent_rc": agent_rc,
        "agent_error": agent_error,
        "verifier_results": verifier_results,
        "terminal_target_match": terminal_match,
        "terminal_target_reason": terminal_reason,
    }


def _invoke_stub_agent(turn_idx: int, run_dir: Path, target: dict[str, Any]) -> tuple[int, str | None]:
    """Deterministic stub: writes a solution that the verifier rejects.

    Demonstrates the orchestrator captures verifier output and that the
    agent's stdout/stderr are captured across turns. Reads any prior
    verifier context to prove re-injection works.
    """
    prior_context = []
    context_dir = run_dir / "context"
    for prior in sorted(context_dir.glob("turn_*_verifier.json")):
        prior_context.append(prior.name)

    solution_path = run_dir / "solution.llmll"
    body = [
        f"; stub agent — turn {turn_idx}",
        f"; prior verifier contexts seen: {prior_context}",
        "; intentionally not valid LLMLL — apparatus validation only",
    ]
    solution_path.write_text("\n".join(body) + "\n")

    log_path = run_dir / "turns" / f"turn_{turn_idx:02d}" / "agent.stdout.log"
    log_path.write_text(
        f"stub agent turn {turn_idx}\n"
        f"prior contexts: {prior_context}\n"
        f"wrote {solution_path.relative_to(run_dir)}\n"
    )
    return 0, None


def _invoke_real_agent(
    *, turn_idx: int, run_dir: Path, turn_dir: Path, agent_cmd: str, timeout: int
) -> tuple[int, str | None]:
    stdout_path = turn_dir / "agent.stdout.log"
    stderr_path = turn_dir / "agent.stderr.log"
    try:
        with stdout_path.open("w") as out, stderr_path.open("w") as err:
            result = subprocess.run(
                agent_cmd,
                cwd=run_dir,
                shell=True,
                stdin=subprocess.DEVNULL,
                stdout=out,
                stderr=err,
                timeout=timeout,
                check=False,
            )
        return result.returncode, None
    except subprocess.TimeoutExpired:
        return 124, f"timeout after {timeout}s on turn {turn_idx}"


def _run_verifier_chain(
    *, target: dict[str, Any], terminal_target: dict[str, Any], run_dir: Path, llmll_cmd: str
) -> tuple[list[dict[str, Any]], bool, str]:
    """Run all verifier commands; return per-command results and terminal match.

    Note: unlike minimal-agent, we run ALL commands every turn so the agent
    sees the full diagnostic surface, not just the first error. The first
    failing command's output is still flagged for emphasis.
    """
    solution = _find_solution(run_dir, target.get("expected_files_priority", []))
    if solution is None:
        return [], False, "no expected solution file present"

    results = []
    first_fail = None
    for cmd_spec in target.get("verifier_commands", []):
        argv = _materialize_argv(cmd_spec["argv"], solution, run_dir, llmll_cmd)
        try:
            proc = subprocess.run(
                argv,
                cwd=run_dir,
                capture_output=True,
                text=True,
                timeout=120,
                check=False,
            )
            rc = proc.returncode
            stdout, stderr = proc.stdout, proc.stderr
            parsed = None
            if cmd_spec.get("capture") == "exit_and_json" and stdout.strip():
                try:
                    parsed = json.loads(stdout)
                except json.JSONDecodeError:
                    parsed = None
        except FileNotFoundError as e:
            rc, stdout, stderr, parsed = 127, "", str(e), None
        except subprocess.TimeoutExpired:
            rc, stdout, stderr, parsed = 124, "", "verifier command timed out", None

        record = {
            "name": cmd_spec["name"],
            "argv": argv,
            "exit_code": rc,
            "stdout": _truncate(stdout, 16_000),
            "stderr": _truncate(stderr, 16_000),
            "parsed_json": parsed,
        }
        results.append(record)
        if rc != 0 and first_fail is None:
            first_fail = cmd_spec["name"]

    terminal_match, terminal_reason = _evaluate_terminal_target(
        target=target,
        terminal_target=terminal_target,
        results=results,
        first_fail=first_fail,
    )
    return results, terminal_match, terminal_reason


def _find_solution(run_dir: Path, priority: list[str]) -> Path | None:
    for name in priority:
        candidate = run_dir / name
        if candidate.exists():
            return candidate
    return None


def _materialize_argv(argv: list[str], solution: Path, run_dir: Path, llmll_cmd: str) -> list[str]:
    out = []
    rel_solution = str(solution.relative_to(run_dir))
    for token in argv:
        if token == "llmll":
            out.extend(shlex.split(llmll_cmd))
        else:
            out.append(token.replace("{solution}", rel_solution))
    return out


def _evaluate_terminal_target(
    *,
    target: dict[str, Any],
    terminal_target: dict[str, Any],
    results: list[dict[str, Any]],
    first_fail: str | None,
) -> tuple[bool, str]:
    """Dispatch on `terminal_target.kind` declared in the manifest.

    Supported kinds:
      - "trust-tier" (LLMLL):  all commands rc=0 AND verify's JSON trust
        report has zero entries below the accepted-level set.
      - "all-pass" (general):  all commands in the chain rc=0. No
        target-specific output parsing. Suitable for Python, Go, Rust,
        TypeScript, or any target whose verifier exit codes alone are
        the load-bearing signal.

    Unknown kinds return False with a clear error so misconfiguration
    surfaces immediately.
    """
    kind = (terminal_target or {}).get("kind", "trust-tier")
    if kind == "trust-tier":
        return _eval_trust_tier_predicate(results=results, first_fail=first_fail)
    if kind == "all-pass":
        return _eval_all_pass_predicate(results=results, first_fail=first_fail)
    return False, f"unknown terminal_target.kind: {kind!r}"


def _eval_trust_tier_predicate(
    *, results: list[dict[str, Any]], first_fail: str | None
) -> tuple[bool, str]:
    if first_fail is not None:
        return False, f"command failed: {first_fail}"

    verify = next((r for r in results if r["name"] == "verify"), None)
    if verify is None:
        return False, "verify command not in chain"
    parsed = verify.get("parsed_json")
    if parsed is None:
        return False, "verify did not produce parseable JSON"

    bad = _count_bad_trust_tiers(parsed)
    if bad > 0:
        return False, f"trust report has {bad} entries below 'asserted'"
    return True, "all expected contracts verified or asserted"


def _eval_all_pass_predicate(
    *, results: list[dict[str, Any]], first_fail: str | None
) -> tuple[bool, str]:
    if first_fail is not None:
        return False, f"command failed: {first_fail}"
    if not results:
        return False, "no verifier commands ran"
    return True, f"all {len(results)} verifier commands exited 0"


def _count_bad_trust_tiers(parsed: Any) -> int:
    """Count trust-report entries below 'asserted'.

    Schema (per `llmll --json verify --trust-report`):
        {
          "entries": [
            {"name": str, "effective_level": str,
             "pre_level": str, "post_level": str, ...},
            ...
          ],
          "summary": {"verified": int, "contract_checked": int,
                      "tested": int, "asserted": int, "no_contract": int,
                      "drifts": int},
          "suppressions": [...]
        }

    Tolerant of schema variation; if the trust report structure cannot be
    located, returns 1 (conservative — predicate does not match).
    """
    accepted_levels = {
        "verified", "proved", "asserted",
        "contract-checked", "contract_checked", "checked",
        "tested",
    }
    entries = None
    if isinstance(parsed, dict):
        entries = parsed.get("entries") or parsed.get("trust_report") or parsed.get("trust")
    if not isinstance(entries, list):
        return 1
    bad = 0
    for entry in entries:
        if not isinstance(entry, dict):
            bad += 1
            continue
        level = (
            entry.get("effective_level")
            or entry.get("tier")
            or entry.get("trust_tier")
            or entry.get("level")
        )
        if isinstance(level, str) and _normalize_level(level) in accepted_levels:
            continue
        bad += 1
    return bad


def _normalize_level(level: str) -> str:
    """`verified (liquid-fixpoint)` → `verified`; otherwise lowercase as-is."""
    return level.lower().split()[0] if level else ""


def _capture_compiler_version(llmll_cmd: str, target: dict[str, Any]) -> dict[str, Any]:
    argv = target.get("version_pin_command")
    if not argv:
        return {"unknown": "no version_pin_command in target"}
    materialized = []
    for token in argv:
        if token == "llmll":
            materialized.extend(shlex.split(llmll_cmd))
        else:
            materialized.append(token)
    try:
        proc = subprocess.run(
            materialized,
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
        )
        if proc.returncode == 0 and proc.stdout.strip():
            try:
                return json.loads(proc.stdout)
            except json.JSONDecodeError:
                return {"raw": proc.stdout.strip()}
        return {"rc": proc.returncode, "stderr": proc.stderr.strip()[:200]}
    except (FileNotFoundError, subprocess.TimeoutExpired) as e:
        return {"error": str(e)}


def _truncate(s: str, n: int) -> str:
    if len(s) <= n:
        return s
    return s[:n] + f"\n... [truncated; original length {len(s)}]"


def _utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _write_json(path: Path, payload: Any) -> None:
    path.write_text(json.dumps(payload, indent=2, sort_keys=False) + "\n")


if __name__ == "__main__":
    sys.exit(main())
