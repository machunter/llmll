#!/usr/bin/env python3
"""Prepare isolated LLMLL minimal-agent experiment directories."""

from __future__ import annotations

import argparse
import json
import re
import shutil
from datetime import datetime, timezone
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
EXPERIMENT_ROOT = SCRIPT_DIR.parent
REPO_ROOT = EXPERIMENT_ROOT.parent.parent

DEFAULT_PROBLEMS = REPO_ROOT / "examples" / "v0.3-exercise-problems.md"
DEFAULT_LLMLL = REPO_ROOT / "LLMLL.md"
DEFAULT_OUTPUT = EXPERIMENT_ROOT / "runs"
PROMPT_TEMPLATE = EXPERIMENT_ROOT / "prompts" / "agent-instructions.md"
PROBLEMS_TEMPLATE = EXPERIMENT_ROOT / "templates" / "PROBLEMS.md"


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Create isolated run directories for the minimal LLMLL agent experiment."
    )
    parser.add_argument(
        "--problem",
        required=True,
        choices=["1", "2", "3", "all"],
        help="Problem number to prepare, or all.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_OUTPUT,
        help=f"Directory where run directories are created (default: {DEFAULT_OUTPUT}).",
    )
    parser.add_argument(
        "--source",
        type=Path,
        default=DEFAULT_PROBLEMS,
        help=f"Exercise markdown file (default: {DEFAULT_PROBLEMS}).",
    )
    parser.add_argument(
        "--llmll-doc",
        type=Path,
        default=DEFAULT_LLMLL,
        help=f"LLMLL.md source file (default: {DEFAULT_LLMLL}).",
    )
    parser.add_argument(
        "--label",
        default="",
        help="Optional label to include in the run directory name, e.g. an agent name.",
    )
    parser.add_argument(
        "--run-id",
        default=None,
        help="Optional explicit run id prefix. Defaults to a UTC timestamp.",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        dest="json_output",
        help="Print machine-readable output.",
    )
    args = parser.parse_args()

    problems = extract_problems(args.source)
    selected = [1, 2, 3] if args.problem == "all" else [int(args.problem)]

    created = []
    for problem_id in selected:
        if problem_id not in problems:
            raise SystemExit(f"Problem {problem_id} was not found in {args.source}")
        created.append(
            prepare_one(
                problem_id=problem_id,
                title=problems[problem_id]["title"],
                body=problems[problem_id]["body"],
                output=args.output,
                source=args.source,
                llmll_doc=args.llmll_doc,
                label=args.label,
                run_id=args.run_id,
            )
        )

    if args.json_output:
        print(json.dumps({"runs": created}, indent=2))
    else:
        for run in created:
            print(run["run_dir"])
    return 0


def extract_problems(source: Path) -> dict[int, dict[str, str]]:
    text = source.read_text(encoding="utf-8")
    matches = list(re.finditer(r"^## Problem\s+(\d+):\s*(.+?)\s*$", text, re.MULTILINE))
    problems: dict[int, dict[str, str]] = {}

    for idx, match in enumerate(matches):
        problem_id = int(match.group(1))
        title = match.group(2).strip()
        start = match.start()
        end = matches[idx + 1].start() if idx + 1 < len(matches) else len(text)
        body = text[start:end].strip() + "\n"
        problems[problem_id] = {"title": title, "body": body}

    return problems


def prepare_one(
    *,
    problem_id: int,
    title: str,
    body: str,
    output: Path,
    source: Path,
    llmll_doc: Path,
    label: str,
    run_id: str | None,
) -> dict[str, str]:
    created_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    prefix = run_id or datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    parts = [prefix]
    if label:
        parts.append(slug(label))
    parts.append(f"p{problem_id}")

    run_dir = output / "-".join(parts)
    if run_dir.exists():
        raise SystemExit(f"Run directory already exists: {run_dir}")

    run_dir.mkdir(parents=True)
    (run_dir / "logs").mkdir()

    shutil.copyfile(llmll_doc, run_dir / "LLMLL.md")
    (run_dir / "problem.md").write_text(body, encoding="utf-8")
    shutil.copyfile(PROMPT_TEMPLATE, run_dir / "AGENT_INSTRUCTIONS.md")

    problems_text = PROBLEMS_TEMPLATE.read_text(encoding="utf-8")
    problems_text = problems_text.replace("{{CREATED_AT}}", created_at)
    problems_text = problems_text.replace("{{PROBLEM_ID}}", str(problem_id))
    (run_dir / "PROBLEMS.md").write_text(problems_text, encoding="utf-8")

    metadata = {
        "experiment": "minimal-agent",
        "created_at": created_at,
        "problem_id": problem_id,
        "problem_title": title,
        "source_problem_file": str(source.resolve()),
        "llmll_doc_file": str(llmll_doc.resolve()),
        "stop_policy": "first_error",
        "expected_solution_files": ["solution.llmll", "solution.ast.json"],
    }
    (run_dir / ".llmll-experiment.json").write_text(
        json.dumps(metadata, indent=2) + "\n",
        encoding="utf-8",
    )

    return {
        "run_dir": str(run_dir),
        "problem_id": str(problem_id),
        "problem_title": title,
        "created_at": created_at,
    }


def slug(value: str) -> str:
    cleaned = re.sub(r"[^A-Za-z0-9._-]+", "-", value.strip())
    cleaned = cleaned.strip("-._")
    return cleaned or "run"


if __name__ == "__main__":
    raise SystemExit(main())
