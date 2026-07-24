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
# Grader-gap (solver-catches mode): per-experiment hidden-spec files. Their mere
# presence flips the experiment's grading_mode to "solver_catches" in run
# metadata; the spec CONTENT (the withheld discriminating post) stays in the
# harness tree and is NEVER copied into a run dir — evaluate_run.py loads it by
# experiment_id at grade time. See hidden-specs/005.json and
# experiments/minimal-agent/findings (DEF-RET grader-gap).
HIDDEN_SPECS_ROOT = EXPERIMENT_ROOT / "hidden-specs"

# Bundle B0 experiment (004), condition A: the provided helpers' effect_summary,
# appended to the initial problem.md when --context-effect-summary is set.
# Keyed by experiment id; absent key → empty append (no-op).
EFFECT_SUMMARY_BLOCKS = {
    "004": (
        "\n\n## Provided helper effect summaries (Bundle B0, condition A)\n\n"
        "The `effect_summary` (reachable coarse capabilities, per "
        "`llmll verify --obligation-report`) of the helpers available to you:\n\n"
        "- `read-log` → `[\"fs.read\"]`\n"
        "- `write-summary` → `[\"fs.write\"]`\n"
        "- `enrich-via-api` → `[\"net.http\"]`  ← reaches a FORBIDDEN capability "
        "(`net.http`); calling it, directly or transitively, makes the program "
        "capability-incorrect.\n"
    ),
}
# DEF-RET experiment (005), condition A: the hole brief's `expected_return_type`
# for each seeded body hole, appended to the initial problem.md when
# --context-expected-return-type is set. This faithfully renders the field
# `llmll checkout` would emit for a def carrying `-> Word` /
# `-> Result[Account, LookupError]` (see CheckoutToken.expected_return_type in
# docs/llmll-ast.schema.json). Keyed by experiment id; absent key → empty append
# (no-op). BLINDNESS INVARIANT (postmortem-010 fix for the postmortem-009 F-009.1
# validity bug): the seeded fixture must NOT name either hole's return type
# anywhere both arms read it. The two target defs omit `return_type`, the clamp
# return's refinement alias is NOT pre-declared as a `type` in the seed, and the
# shared experiment markdown (005-seeded-return-holes.md) does not name `Word` /
# `Result[t, E]` — the harness agents read raw AST + problem.md (not the checkout
# brief), so the type can only be withheld from condition B by keeping it out of
# BOTH the seed AST and the shared header. This block is the ONLY source of the
# type names; it is the on/off injection (condition A) that isolates the field's
# information content. Condition B must infer the return from the behavioral spec
# plus the seeded value-type vocabulary (Account / LookupError / AccountStore).
RETURN_TYPE_BRIEF_BLOCKS = {
    "005": (
        "\n\n## Hole brief — expected return types (DEF-RET, condition A)\n\n"
        "The `expected_return_type` (per `llmll checkout` / the CheckoutToken "
        "brief) at each seeded hole site, as an LLMLL type label:\n\n"
        "- hole `clamp-to-word-body` (body of `clamp-to-word`) → "
        "`expected_return_type`: `Word`  "
        "(`Word = (where [w: int] (and (>= w 0) (<= w 65535)))` — a "
        "refinement-aliased `int`; the body must produce a value provably in "
        "`[0, 65535]` and carries the §3.4.1 return obligation).\n"
        "- hole `find-account-body` (body of `find-account`) → "
        "`expected_return_type`: `Result[Account, LookupError]`  "
        "(success channel `Account`, error channel `LookupError` with "
        "constructors `NotFound` / `Malformed`; construct both channels).\n"
    ),
}
EXPERIMENT_SCAFFOLD_TEMPLATES = {
    "003": ["ecommerce-order-handler"],
    "005": ["seeded-return-holes"],
    "006": ["reservoir-inflow"],
    "007": ["map-revocation"],
    "008": ["bytes-scaled-read"],
    "009": ["transfer-conservation"],
    "010": ["byte-saturate"],
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
    parser.add_argument(
        "--context-effect-summary",
        action="store_true",
        help="Bundle B0 (experiment 004) condition A: append the provided "
        "helpers' effect_summary to the initial problem.md. Default-off — a "
        "no-op for other experiments and for condition B.",
    )
    parser.add_argument(
        "--context-expected-return-type",
        action="store_true",
        help="DEF-RET (experiment 005) condition A: append the seeded holes' "
        "expected_return_type brief to the initial problem.md. Default-off — a "
        "no-op for other experiments and for condition B.",
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
                context_effect_summary=args.context_effect_summary,
                context_expected_return_type=args.context_expected_return_type,
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
    context_effect_summary: bool = False,
    context_expected_return_type: bool = False,
) -> dict[str, str]:
    experiment_id = experiment["experiment_id"]
    experiment_slug = experiment["slug"]
    problem_id = int(experiment["problem_id"])
    title = experiment["title"]
    body = experiment["body"]
    # Bundle B0 (experiment 004) condition A: append the provided helpers'
    # effect_summary to the initial context. Default-off keeps problem.md
    # byte-identical for all other experiments and for condition B.
    if context_effect_summary:
        body = body + EFFECT_SUMMARY_BLOCKS.get(experiment_id, "")
    # DEF-RET (experiment 005) condition A: append the seeded holes'
    # expected_return_type brief. Default-off keeps problem.md byte-identical
    # across arms except for this injected block (the field under test).
    if context_expected_return_type:
        body = body + RETURN_TYPE_BRIEF_BLOCKS.get(experiment_id, "")

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
        "grading_mode": resolve_grading_mode(experiment_id),
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
        # LEAK STRIP (postmortem-010 residual): the raw copytree shipped fixture
        # metadata into the agent-visible scaffold — most damagingly `_fixture_note`,
        # which describes the A/B design (and its blindness invariant) itself. Drop
        # every underscore-prefixed key from each copied .ast.json so harness/fixture
        # metadata can never reach the agent. No valid JSON-AST schema field starts
        # with `_`, so this is safe; it is the on-disk enforcement of the blindness
        # invariant the note merely asserted.
        for ast_path in dst_dir.rglob("*.ast.json"):
            _strip_fixture_metadata(ast_path)
        copied.append(template_name)
    return copied


def _strip_fixture_metadata(ast_path: Path) -> None:
    try:
        document = json.loads(ast_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return
    if not _drop_underscore_keys(document):
        return
    ast_path.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")


def _drop_underscore_keys(value: object) -> bool:
    """Recursively delete dict keys beginning with '_'. Returns True if anything
    was removed (so the caller only rewrites changed files)."""
    changed = False
    if isinstance(value, dict):
        for key in [k for k in value if isinstance(k, str) and k.startswith("_")]:
            del value[key]
            changed = True
        for child in value.values():
            changed = _drop_underscore_keys(child) or changed
    elif isinstance(value, list):
        for child in value:
            changed = _drop_underscore_keys(child) or changed
    return changed


def resolve_grading_mode(experiment_id: str) -> str:
    """solver-catches mode is activated by the presence of a hidden-spec for the
    experiment (hidden-specs/<id>.json). Default-off → "capability" (the legacy
    grade path, unchanged for experiments 001–004)."""
    if (HIDDEN_SPECS_ROOT / f"{experiment_id}.json").exists():
        return "solver_catches"
    return "capability"


def slug(value: str) -> str:
    cleaned = re.sub(r"[^A-Za-z0-9._-]+", "-", value.strip())
    cleaned = cleaned.strip("-._")
    return cleaned or "run"


if __name__ == "__main__":
    raise SystemExit(main())
