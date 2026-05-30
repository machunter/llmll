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

DEFAULT_EXPERIMENTS_DIR = EXPERIMENT_ROOT / "experiments"
DEFAULT_LLMLL = REPO_ROOT / "LLMLL.md"
DEFAULT_AST_SCHEMA = REPO_ROOT / "docs" / "llmll-ast.schema.json"
DEFAULT_OUTPUT = EXPERIMENT_ROOT / "runs"
PROMPT_TEMPLATE = EXPERIMENT_ROOT / "prompts" / "agent-instructions.md"
PROBLEMS_TEMPLATE = EXPERIMENT_ROOT / "templates" / "PROBLEMS.md"
LLMLL_WRAPPER_TEMPLATE = EXPERIMENT_ROOT / "templates" / "llmll-wrapper.sh"
LLMLL_WRAPPER_CORE_INVERSION_TEMPLATE = EXPERIMENT_ROOT / "templates" / "llmll-wrapper-core-inversion.sh"
GRAMMAR_MODES = {"legacy", "core-inversion"}
SCAFFOLD_TEMPLATES_ROOT = EXPERIMENT_ROOT / "scaffold-templates"
EXPERIMENT_SCAFFOLD_TEMPLATES = {
    "003": ["ecommerce-order-handler"],
}

LEGACY_PROBLEM_IDS = {
    "1": "001",
    "2": "002",
    "3": "003",
}


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Create isolated run directories for the minimal LLMLL agent experiment."
    )
    selector = parser.add_mutually_exclusive_group(required=True)
    selector.add_argument(
        "--experiment",
        help=(
            "Experiment selector, or all. Accepts numeric id (001 or 1), slug "
            "(two-agent-auth), stem (001-two-agent-auth), or filename."
        ),
    )
    selector.add_argument(
        "--problem",
        choices=["1", "2", "3", "all"],
        help="Deprecated alias for --experiment 001/002/003, or all.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_OUTPUT,
        help=f"Directory where run directories are created (default: {DEFAULT_OUTPUT}).",
    )
    parser.add_argument(
        "--experiments-dir",
        type=Path,
        default=DEFAULT_EXPERIMENTS_DIR,
        help=f"Directory of split experiment markdown files (default: {DEFAULT_EXPERIMENTS_DIR}).",
    )
    parser.add_argument(
        "--source",
        type=Path,
        default=None,
        help="Deprecated combined exercise markdown source. Prefer --experiments-dir.",
    )
    parser.add_argument(
        "--llmll-doc",
        type=Path,
        default=DEFAULT_LLMLL,
        help=f"LLMLL.md source file (default: {DEFAULT_LLMLL}).",
    )
    parser.add_argument(
        "--ast-schema",
        type=Path,
        default=DEFAULT_AST_SCHEMA,
        help=f"JSON-AST schema source file (default: {DEFAULT_AST_SCHEMA}).",
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
        "--grammar-mode",
        default="legacy",
        choices=sorted(GRAMMAR_MODES),
        help="LT-INV: grammar mode passed to the compiler wrapper in bin/llmll. "
             "'core-inversion' installs the grammar-aware wrapper that injects "
             "--grammar=core-inversion into every agent llmll call (default: legacy).",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        dest="json_output",
        help="Print machine-readable output.",
    )
    args = parser.parse_args()

    selector_value = args.experiment if args.experiment is not None else args.problem
    if args.problem and args.problem != "all":
        selector_value = LEGACY_PROBLEM_IDS[args.problem]

    experiments = (
        load_legacy_experiments(args.source)
        if args.source
        else load_experiments(args.experiments_dir)
    )
    selected = select_experiments(experiments, selector_value)

    created = []
    for experiment in selected:
        created.append(
            prepare_one(
                experiment=experiment,
                output=args.output,
                llmll_doc=args.llmll_doc,
                ast_schema=args.ast_schema,
                label=args.label,
                run_id=args.run_id,
                grammar_mode=args.grammar_mode,
            )
        )

    if args.json_output:
        print(json.dumps({"runs": created}, indent=2))
    else:
        for run in created:
            print(run["run_dir"])
    return 0


def load_experiments(experiments_dir: Path) -> dict[str, dict[str, str]]:
    if not experiments_dir.exists():
        raise SystemExit(f"Experiments directory does not exist: {experiments_dir}")

    experiments: dict[str, dict[str, str]] = {}
    for path in sorted(experiments_dir.glob("*.md")):
        match = re.match(r"^(\d{3,})-(.+)$", path.stem)
        if not match:
            raise SystemExit(
                f"Experiment filename must match NNN-kebab-slug.md: {path.name}"
            )

        experiment_id = match.group(1)
        slug_value = match.group(2)
        text = path.read_text(encoding="utf-8")
        problem_id = int(experiment_id)
        experiments[experiment_id] = {
            "experiment_id": experiment_id,
            "slug": slug_value,
            "stem": path.stem,
            "filename": path.name,
            "problem_id": str(problem_id),
            "title": extract_title(text) or title_from_slug(slug_value),
            "body": text.rstrip() + "\n",
            "source": str(path),
        }

    if not experiments:
        raise SystemExit(f"No experiment markdown files found in {experiments_dir}")
    return experiments


def load_legacy_experiments(source: Path) -> dict[str, dict[str, str]]:
    text = source.read_text(encoding="utf-8")
    matches = list(re.finditer(r"^## Problem\s+(\d+):\s*(.+?)\s*$", text, re.MULTILINE))
    experiments: dict[str, dict[str, str]] = {}

    for idx, match in enumerate(matches):
        problem_id = int(match.group(1))
        experiment_id = f"{problem_id:03d}"
        title = match.group(2).strip()
        slug_value = slug(title).lower()
        start = match.start()
        end = matches[idx + 1].start() if idx + 1 < len(matches) else len(text)
        body = text[start:end].strip() + "\n"
        experiments[experiment_id] = {
            "experiment_id": experiment_id,
            "slug": slug_value,
            "stem": f"{experiment_id}-{slug_value}",
            "filename": source.name,
            "problem_id": str(problem_id),
            "title": title,
            "body": body,
            "source": str(source),
        }

    return experiments


def select_experiments(
    experiments: dict[str, dict[str, str]],
    selector: str | None,
) -> list[dict[str, str]]:
    if selector is None:
        raise SystemExit("An experiment selector is required.")
    normalized = selector.strip()
    if normalized == "all":
        return [experiments[key] for key in sorted(experiments)]

    normalized = normalized.removesuffix(".md")
    normalized_lower = normalized.lower()
    matches = []
    for experiment in experiments.values():
        aliases = {
            experiment["experiment_id"],
            str(int(experiment["experiment_id"])),
            experiment["slug"],
            experiment["stem"],
            experiment["filename"].removesuffix(".md"),
        }
        if normalized_lower in {alias.lower() for alias in aliases}:
            matches.append(experiment)

    if not matches:
        valid = ", ".join(
            f"{exp['experiment_id']} ({exp['slug']})"
            for exp in sorted(experiments.values(), key=lambda item: item["experiment_id"])
        )
        raise SystemExit(f"Experiment {selector!r} was not found. Valid experiments: {valid}")
    if len(matches) > 1:
        raise SystemExit(f"Experiment selector {selector!r} is ambiguous.")
    return matches


def extract_title(text: str) -> str | None:
    match = re.search(r"^#\s+(.+?)\s*$", text, re.MULTILINE)
    return match.group(1).strip() if match else None


def title_from_slug(value: str) -> str:
    return " ".join(part.capitalize() for part in value.split("-"))


def prepare_one(
    *,
    experiment: dict[str, str],
    output: Path,
    llmll_doc: Path,
    ast_schema: Path,
    label: str,
    run_id: str | None,
    grammar_mode: str = "legacy",
) -> dict[str, str]:
    experiment_id = experiment["experiment_id"]
    experiment_slug = experiment["slug"]
    problem_id = int(experiment["problem_id"])
    title = experiment["title"]
    body = experiment["body"]

    created_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    prefix = run_id or datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    parts = [prefix]
    if label:
        parts.append(slug(label))
    parts.append(f"e{experiment_id}")

    run_dir = output / "-".join(parts)
    if run_dir.exists():
        raise SystemExit(f"Run directory already exists: {run_dir}")

    run_dir.mkdir(parents=True)
    (run_dir / "logs").mkdir()
    (run_dir / "bin").mkdir()

    wrapper_src = (
        LLMLL_WRAPPER_CORE_INVERSION_TEMPLATE
        if grammar_mode == "core-inversion"
        else LLMLL_WRAPPER_TEMPLATE
    )
    shutil.copyfile(llmll_doc, run_dir / "LLMLL.md")
    shutil.copyfile(ast_schema, run_dir / "llmll-ast.schema.json")
    shutil.copyfile(wrapper_src, run_dir / "bin" / "llmll")
    (run_dir / "bin" / "llmll").chmod(0o755)
    (run_dir / "problem.md").write_text(body, encoding="utf-8")
    shutil.copyfile(PROMPT_TEMPLATE, run_dir / "AGENT_INSTRUCTIONS.md")

    problems_text = PROBLEMS_TEMPLATE.read_text(encoding="utf-8")
    problems_text = problems_text.replace("{{CREATED_AT}}", created_at)
    problems_text = problems_text.replace("{{EXPERIMENT_ID}}", experiment_id)
    problems_text = problems_text.replace("{{EXPERIMENT_SLUG}}", experiment_slug)
    problems_text = problems_text.replace("{{PROBLEM_ID}}", str(problem_id))
    (run_dir / "PROBLEMS.md").write_text(problems_text, encoding="utf-8")

    scaffold_templates = provide_scaffold_templates(experiment_id, run_dir)

    provided_files = [
        "LLMLL.md",
        "llmll-ast.schema.json",
        "problem.md",
        "AGENT_INSTRUCTIONS.md",
        "PROBLEMS.md",
        "bin/llmll",
    ]
    provided_files.extend(
        f".llmll/templates/{template_name}/scaffold.ast.json"
        for template_name in scaffold_templates
    )

    metadata = {
        "experiment": "minimal-agent",
        "created_at": created_at,
        "experiment_id": experiment_id,
        "experiment_slug": experiment_slug,
        "experiment_title": title,
        "experiment_source": experiment["source"],
        "problem_id": problem_id,
        "stop_policy": "first_error",
        "solution_format": "json_ast",
        "ast_schema": "llmll-ast.schema.json",
        "grammar_mode": grammar_mode,
        "provided_files": provided_files,
        "scaffold_templates_provided": scaffold_templates,
        "scaffold_template_root": ".llmll/templates",
        "expected_solution_files": ["solution.ast.json"],
    }
    (run_dir / ".llmll-experiment.json").write_text(
        json.dumps(metadata, indent=2) + "\n",
        encoding="utf-8",
    )

    return {
        "run_dir": str(run_dir),
        "experiment_id": experiment_id,
        "experiment_slug": experiment_slug,
        "experiment_title": title,
        "problem_id": str(problem_id),
        "problem_title": title,
        "created_at": created_at,
    }


def provide_scaffold_templates(experiment_id: str, run_dir: Path) -> list[str]:
    template_names = EXPERIMENT_SCAFFOLD_TEMPLATES.get(experiment_id, [])
    copied: list[str] = []
    for template_name in template_names:
        src_dir = SCAFFOLD_TEMPLATES_ROOT / template_name
        if not src_dir.exists():
            raise SystemExit(f"Scaffold template is missing: {src_dir}")
        dst_dir = run_dir / ".llmll" / "templates" / template_name
        shutil.copytree(src_dir, dst_dir)
        copied.append(template_name)
    return copied


def slug(value: str) -> str:
    cleaned = re.sub(r"[^A-Za-z0-9._-]+", "-", value.strip())
    cleaned = cleaned.strip("-._")
    return cleaned or "run"


if __name__ == "__main__":
    raise SystemExit(main())
