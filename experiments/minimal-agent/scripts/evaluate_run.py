#!/usr/bin/env python3
"""Evaluate a minimal-agent run directory, stopping at the first tool error."""

from __future__ import annotations

import argparse
import copy
import json
import re
import shlex
import subprocess
import time
from pathlib import Path
from typing import Any


FEATURE_PATTERNS = {
    "type": r"\(type\b|\"kind\"\s*:\s*\"type(?:-decl)?\"",
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
    # E2: Result detection moved to walk_json_ast — three-signal split
    # (Result-type / Result-helpers / Result-pattern). Legacy `Result` field
    # in `found` is preserved as a derived alias of `Result-type`.
    "Promise": r"\bPromise\b|\"kind\"\s*:\s*\"promise\"",
    "proof-required": r"\?proof-required\b|\"kind\"\s*:\s*\"hole-proof-required\"",
    "scaffold": r"\?scaffold\b|\"kind\"\s*:\s*\"hole-scaffold\"",
}

# REQUIRED_FEATURES: each item is either a string (must appear in `found`)
# or a list of strings (any-of disjunction — at least one must appear).
# Disjunctions are formatted with " | " in the `missing_required` output
# (e.g. "Result-type | Result-pattern") so downstream tooling that iterates
# over strings remains compatible.
#
# Experiment 002/003 loosening (F-301, postmortem-002-el-a): Promise is
# inferred from ?delegate-async per LLMLL.md §11.2 inference rules and
# almost never written explicitly in agent code; requiring it is asking
# for redundant annotations. Result-type (kind:"result") is similarly
# inferred when (await x) is followed by a match on Success/Error —
# agents typically elide the explicit annotation. Allowing
# Result-pattern (match arms with Success/Error constructors) as a
# satisfying alternative aligns the gate with v0.10.2 ergonomics.
# Experiment 001's Result-type requirement is preserved because the
# spec explicitly mandates `Result[string, string]` as login-handler's
# return type (001-two-agent-auth.md:23).
REQUIRED_FEATURES = {
    1: ["def-interface", "delegate", "on-failure", "check", "pre", "post", "Result-type"],
    2: [
        "def-interface",
        "delegate",
        "delegate-async",
        "await",
        "DelegationError",
        # Promise removed (inferred from ?delegate-async per §11.2).
        ["Result-type", "Result-pattern"],  # disjunction (F-301 loosening)
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
        ["Result-type", "Result-pattern"],  # disjunction (F-301 loosening)
        "proof-required",
        "def-invariant",
        "check",
        "pre",
        "post",
    ],
    # F-B0-3 (postmortem-007): 004 had no entry → feature_scan.required=[] →
    # the evaluator graded vacuous solutions A. The `check` block and the
    # count-lines `post` contract are mandated by the 004 task; this stops the
    # evaluator passing stubs. Capability-correctness (fs effects present, no
    # forbidden cap) stays the scorer's job (`score_capability.py --require`).
    4: ["check", "post"],
    # DEF-RET (experiment 005, postmortem-009/-010): the fill-the-hole task
    # mandates a `check` and a `post` on clamp-to-word; a correct find-account fill
    # produces a Result return (type annotation or a match on Success/Error).
    # `type` is satisfied by the seeded Account/LookupError aliases carried into
    # the solution (and, in a correct fill, the refinement alias the agent ADDS for
    # the clamp return — the seed no longer pre-declares it, per the postmortem-010
    # blindness fix). The scan reads the SOLUTION (scan_features), not the seed, so
    # the agent must supply these features itself. The non-vacuity bar mirrors
    # F-B0-3 — without an entry the evaluator grades stub bodies A.
    5: ["type", "check", "post", ["Result-type", "Result-pattern"]],
    # P3 grader-gap (experiment 006, solver-catches mode): the discriminating
    # postcondition is WITHHELD (hidden-specs/006.json) and injected at grade
    # time, so the agent must NOT be required to author a `post` — requiring one
    # would defeat the grader-gap. The only feature gate is the provided `check`
    # (the non-adversarial "tests blind" arm): if the agent strips it,
    # solver_caught can never be established (effective_total=0 → test_passed
    # False), so its presence is the non-vacuity bar. Stub bodies are caught
    # separately by the vacuous→C gate in solver_catch_grade (fixpoint cannot
    # reach a body-faithful VC). `scaffold` is intentionally NOT required:
    # detect_scaffold_usage keys on a stray scaffold.ast.json, which a hole-fill
    # solution need not produce.
    6: ["check"],
    # 007 (map-revocation) / 008 (bytes-scaled-read): solver-catches, same gate
    # rationale as 006 — the discriminating post is withheld (hidden-specs/
    # 007.json, 008.json), so requiring the agent to author a `post` would defeat
    # the grader-gap. The provided non-adversarial `check` is the only non-vacuity
    # bar (stripping it → effective_total=0 → test_passed False → no grade A).
    7: ["check"],
    8: ["check"],
    # 009 (transfer-conservation) / 010 (byte-saturate): discriminative
    # redesigns of 007/008, same solver-catches gate — withheld post
    # (hidden-specs/009.json, 010.json), the provided non-adversarial `check` is
    # the only non-vacuity bar. Correct fills verify body-faithfully (B); the
    # plausible errors (dropped debit leg / missing saturation clamp) refute (A).
    9: ["check"],
    10: ["check"],
}


def feature_present(spec: Any, found: dict[str, bool]) -> bool:
    """True iff the feature `spec` is satisfied in `found`. String specs require
    the named feature; list specs (disjunctions) require at least one named
    feature in the list to be true."""
    if isinstance(spec, list):
        return any(found.get(name, False) for name in spec)
    return bool(found.get(spec, False))


def feature_label(spec: Any) -> str:
    """Render a feature spec for output. Strings render as-is; list disjunctions
    render as ' | '-joined names."""
    if isinstance(spec, list):
        return " | ".join(spec)
    return str(spec)

CONTRACT_EXPECTATIONS = {
    1: {
        # E3 Option 2 (2026-05-28): pre removed from contract expectations
        # because it is QF-LIA-tractable but structurally asserted (login-handler
        # contains ?delegate → whole contract is asserted per §5.3.5). Keeping
        # pre with proof_required=False caused asserted_without_proof=1 → grade B
        # regardless of test results. Pre is still required by REQUIRED_FEATURES[1]
        # (feature scan enforces it); it is just not quality-tracked here.
        # Grade A is reachable when: (1) the solution includes a non-delegation-
        # dependent check (effective_total > 0), and (2) the agent marks the post
        # clause ?proof-required (asserted_without_proof stays 0).
        # See postmortem-001-el-a-revalidation F-201 for pre-flip history.
        "login-handler": {
            "post": {"proof_required": True},
        },
    },
    2: {
        "summarize-amounts": {
            "pre": {"proof_required": False},
            "post": {"proof_required": True},
        },
    },
    3: {
        "validate-order": {
            "pre": {"proof_required": False},
            "post": {"proof_required": True},
        },
        "calculate-tax": {
            "pre": {"proof_required": False},
            "post": {"proof_required": True},
        },
    },
}

TRUST_STATUS_PRESENT = {"verified", "contract-checked", "tested", "asserted"}

# Grading modes. "capability" is the legacy A/B/C/F path (experiments 001–004,
# feature-presence + tests + trust-tier ceiling, asserted accepted / refuted
# rejected). "solver_catches" is the grader-gap path for the non-trivial
# benchmark portfolio: a discriminating post is WITHHELD from the agent and
# injected only at grade time, then run through fixpoint with INVERTED polarity —
# `refuted` (body-faithful UNSAFE) is the success signal, `asserted`/fallback is
# a vacuous non-catch (the F-B0-2 non-vacuity gate). See findings (DEF-RET
# grader-gap) and hidden-specs/<id>.json.
GRADING_MODE_CAPABILITY = "capability"
GRADING_MODE_SOLVER_CATCHES = "solver_catches"

# Hidden-spec dir, resolved relative to this script (mirrors prepare_run.py's
# HIDDEN_SPECS_ROOT). The spec content stays here and never enters a run dir.
HIDDEN_SPECS_ROOT = Path(__file__).resolve().parent.parent / "hidden-specs"


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
        help="Explicit solution file. Defaults to solution.ast.json, then solution.llmll.",
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
    harness = load_harness_result(run_dir)
    solution = find_solution(run_dir, args.solution)
    solution_ast = load_solution_ast(solution) if solution else None

    report: dict[str, Any] = {
        "run_dir": str(run_dir),
        "experiment_id": metadata.get("experiment_id"),
        "experiment_slug": metadata.get("experiment_slug"),
        "experiment_title": metadata.get("experiment_title"),
        "problem_id": metadata.get("problem_id"),
        "status": "failed",
        "stop_policy": "first_error",
        "grading_mode": GRADING_MODE_CAPABILITY,
        "solution": str(solution) if solution else None,
        "feature_scan": None,
        "quality_grade": "F",
        "solver_catch": None,
        "test_summary": None,
        "test_assessment": None,
        "verify_summary": None,
        "verify_details": None,
        "contract_assessment": None,
        "effect_summary": None,
        "problems_md": analyze_problems_md(run_dir),
        "agent_duration_seconds": harness.get("duration_seconds"),
        "total_eval_duration_seconds": 0.0,
        "commands": [],
        "first_error": None,
    }
    eval_started = time.monotonic()

    if solution is None:
        report["first_error"] = {
            "phase": "solution-discovery",
            "message": "No solution.ast.json or solution.llmll found.",
        }
        report["quality_grade"] = quality_grade(report)
        report["total_eval_duration_seconds"] = round(time.monotonic() - eval_started, 3)
        write_outputs(run_dir, report)
        return 1

    report["feature_scan"] = scan_features(solution, metadata, run_dir)

    grading_mode = resolve_grading_mode_eval(metadata)
    report["grading_mode"] = grading_mode

    llmll = shlex.split(args.llmll_cmd)
    try:
        solution_name = str(solution.relative_to(run_dir))
    except ValueError:
        solution_name = str(solution)
    commands = [
        ("check", llmll + ["check", solution_name]),
        ("check-strict", llmll + ["check", solution_name, "--strict"]),
        ("holes", llmll + ["--json", "holes", "--deps", solution_name]),
        ("test", llmll + ["test", solution_name]),
    ]
    # Capability mode keeps the legacy trust-report verify (descriptive tiers).
    # Solver-catches mode replaces it with a fixpoint run on a graded copy (below)
    # — `--trust-report` SKIPS fixpoint, so it can never surface `refuted`.
    if not args.skip_verify and grading_mode == GRADING_MODE_CAPABILITY:
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

    # In solver-catches mode `test` is graded, not gating: a failed property suite
    # means the bug leaked into the tests (not a solver-ONLY catch), which the
    # grade records — it must not short-circuit the run before the fixpoint verify.
    non_stopping = {"test"} if grading_mode == GRADING_MODE_SOLVER_CATCHES else set()

    for name, argv in commands:
        result = run_command(name, argv, cwd=run_dir, timeout=args.timeout_seconds)
        annotate_command_result(result)
        report["commands"].append(result)

        if name == "test":
            report["test_summary"] = parse_test_summary(result["stdout"])
            report["test_assessment"] = assess_tests(
                report["test_summary"],
                solution_ast,
            )
        elif name == "verify":
            report["verify_summary"] = parse_verify_summary(result["stdout"])
            report["verify_details"] = parse_verify_details(result["stdout"])
            report["contract_assessment"] = assess_contracts(
                metadata.get("problem_id"),
                solution_ast,
                report["verify_details"],
            )

        if not result["effective_success"] and name not in non_stopping:
            report["first_error"] = {
                "phase": name,
                "argv": argv,
                "returncode": result["returncode"],
                "effective_failure_reason": result["effective_failure_reason"],
                "stderr": result["stderr"],
                "stdout": result["stdout"],
            }
            report["quality_grade"] = quality_grade(report)
            report["total_eval_duration_seconds"] = round(time.monotonic() - eval_started, 3)
            write_outputs(run_dir, report)
            return 1

    if grading_mode == GRADING_MODE_SOLVER_CATCHES and not args.skip_verify:
        # Grader-gap: inject the WITHHELD discriminating post(s) onto a graded copy
        # and run fixpoint with INVERTED polarity. A `refuted` here is the success
        # signal, not a stop-error; it never enters first_error.
        report["solver_catch"] = run_solver_catch_verify(
            llmll,
            solution_ast,
            metadata,
            run_dir,
            timeout=args.timeout_seconds,
            commands_log=report["commands"],
            test_assessment=report.get("test_assessment"),
        )
    elif not args.skip_verify:
        # v0.12.0 Bundle B0 authority channel (capture-only). `--obligation-report`
        # does NOT compose with `--trust-report` (they are mutually-exclusive output
        # modes), so the effect_summary is read from a separate verify invocation.
        # This is descriptive only: it runs after the graded command loop, is gated on
        # the success path, and never enters first_error, effective_success, or the
        # quality grade. A failed probe leaves report["effect_summary"] = None.
        oblig = run_command(
            "obligation-report",
            llmll + ["verify", solution_name, "--obligation-report"],
            cwd=run_dir,
            timeout=args.timeout_seconds,
        )
        report["effect_summary"] = parse_effect_summary(oblig["stdout"])

    report["status"] = "passed"
    report["quality_grade"] = quality_grade(report)
    report["total_eval_duration_seconds"] = round(time.monotonic() - eval_started, 3)
    write_outputs(run_dir, report)
    return 0


def load_metadata(run_dir: Path) -> dict[str, Any]:
    path = run_dir / ".llmll-experiment.json"
    if not path.exists():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {}
    return data if isinstance(data, dict) else {}


def load_harness_result(run_dir: Path) -> dict[str, Any]:
    path = run_dir / "harness_result.json"
    if not path.exists():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {}
    return data if isinstance(data, dict) else {}


def find_solution(run_dir: Path, explicit: Path | None) -> Path | None:
    if explicit:
        candidate = explicit if explicit.is_absolute() else run_dir / explicit
        return candidate if candidate.exists() else None
    for name in ("solution.ast.json", "solution.llmll"):
        candidate = run_dir / name
        if candidate.exists():
            return candidate
    return None


def load_solution_ast(solution: Path | None) -> dict[str, Any] | None:
    if solution is None or solution.suffix != ".json":
        return None
    try:
        data = json.loads(solution.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return None
    return data if isinstance(data, dict) else None


def scan_features(solution: Path, metadata: dict[str, Any], run_dir: Path) -> dict[str, Any]:
    text = solution.read_text(encoding="utf-8")
    found = {
        name: bool(re.search(pattern, text))
        for name, pattern in FEATURE_PATTERNS.items()
    }
    json_features = scan_json_ast_features(text)
    for name, was_found in json_features.items():
        found[name] = found.get(name, False) or was_found
    found["scaffold"] = found.get("scaffold", False) or detect_scaffold_usage(run_dir)

    try:
        pid = int(metadata.get("problem_id") or 0)
    except (TypeError, ValueError):
        pid = 0
    required = required_features_for(pid, metadata)
    missing = [feature_label(spec) for spec in required if not feature_present(spec, found)]
    return {
        "required": [feature_label(spec) for spec in required],
        "found": found,
        "missing_required": missing,
        "boundary_form_counts": count_boundary_forms(text),
    }


def required_features_for(problem_id: int, metadata: dict[str, Any]) -> list[str]:
    required = list(REQUIRED_FEATURES.get(problem_id, []))
    # Experiments that ship a scaffold template (003, 005) require the agent to
    # use it. Conditional on the template actually being provided in run metadata.
    if problem_id in {3, 5} and metadata.get("scaffold_templates_provided"):
        required.append("scaffold")
    return required


def detect_scaffold_usage(run_dir: Path) -> bool:
    template_root = run_dir / ".llmll" / "templates"
    for path in run_dir.rglob("scaffold.ast.json"):
        try:
            path.relative_to(template_root)
        except ValueError:
            return True
    return False


def count_boundary_forms(text: str) -> dict[str, int]:
    """Count def / def-shell / def-logic statement kinds for gate axis (d)."""
    counts: dict[str, int] = {"def": 0, "def-shell": 0, "def-logic": 0}
    try:
        document = json.loads(text)
    except json.JSONDecodeError:
        return counts
    for stmt in document.get("statements", []):
        if isinstance(stmt, dict):
            kind = stmt.get("kind")
            if kind in counts:
                counts[kind] += 1
    return counts


def scan_json_ast_features(text: str) -> dict[str, bool]:
    try:
        document = json.loads(text)
    except json.JSONDecodeError:
        return {}

    found: dict[str, bool] = {}
    walk_json_ast(document, found)
    # Three-signal Result split (E2): Result-type drives missing_required;
    # Result-helpers and Result-pattern are informational. Result is
    # preserved as a back-compat derived alias of Result-type.
    found.setdefault("Result-type", False)
    found.setdefault("Result-helpers", False)
    found.setdefault("Result-pattern", False)
    found["Result"] = found["Result-type"]
    return found


RESULT_HELPER_FNS = {"ok", "err", "is-ok", "unwrap", "unwrap-or"}
RESULT_PATTERN_CTORS = {"Success", "Error"}


def walk_json_ast(value: Any, found: dict[str, bool]) -> None:
    if isinstance(value, dict):
        kind = value.get("kind")
        if kind == "result":
            found["Result-type"] = True
        elif kind == "promise":
            found["Promise"] = True
        elif kind == "constructor":
            # Pattern-position constructor (match arm) per JSON-AST Pattern schema.
            # Distinguished from expression-position by kind == "constructor"
            # (Patterns use this; Exprs do not).
            if value.get("constructor") in RESULT_PATTERN_CTORS:
                found["Result-pattern"] = True
        elif kind == "app":
            # Expression-position function call; the three-layer rule routes
            # Result construction and testing through these helpers.
            if value.get("fn") in RESULT_HELPER_FNS:
                found["Result-helpers"] = True

        for child in value.values():
            walk_json_ast(child, found)
    elif isinstance(value, list):
        for child in value:
            walk_json_ast(child, found)


def analyze_problems_md(run_dir: Path) -> dict[str, Any]:
    path = run_dir / "PROBLEMS.md"
    if not path.exists():
        return {
            "exists": False,
            "entry_count": 0,
            "has_no_problems_marker": False,
            "stale_no_problems_marker": False,
        }

    text = path.read_text(encoding="utf-8")
    after_entries = text.split("## Entries", 1)[1] if "## Entries" in text else text
    entries = [
        line
        for line in after_entries.splitlines()
        if line.lstrip().startswith(("- ", "* "))
    ]
    marker_present = "No problems recorded yet." in after_entries
    entry_count = len(entries)
    return {
        "exists": True,
        "entry_count": entry_count,
        "has_no_problems_marker": marker_present and entry_count == 0,
        "stale_no_problems_marker": marker_present and entry_count > 0,
    }


def assess_tests(
    summary: dict[str, int] | None,
    solution_ast: dict[str, Any] | None,
) -> dict[str, Any] | None:
    if not summary:
        return None

    checks = collect_checks(solution_ast)
    excluded_candidates = [
        check for check in checks if check.get("delegation_dependent")
    ]

    passed = summary.get("passed", 0)
    failed = summary.get("failed", 0)
    skipped = summary.get("skipped", 0)
    total = summary.get("total", 0)

    excluded = min(len(excluded_candidates), failed + skipped)
    excluded_skipped = min(skipped, excluded)
    excluded_failed = min(failed, excluded - excluded_skipped)

    effective_total = max(0, total - excluded)
    effective_failed = max(0, failed - excluded_failed)
    effective_skipped = max(0, skipped - excluded_skipped)
    effective_passed = min(passed, effective_total)
    all_applicable_passed = (
        effective_failed == 0
        and effective_skipped == 0
        and effective_passed == effective_total
    )

    return {
        "raw": summary,
        "effective_total": effective_total,
        "effective_passed": effective_passed,
        "effective_failed": effective_failed,
        "effective_skipped": effective_skipped,
        "excluded_delegation_dependent": excluded,
        "delegation_dependent_checks": excluded_candidates,
        "all_applicable_passed": all_applicable_passed,
    }


DELEGATION_KINDS = {"hole-delegate", "hole-delegate-async", "await"}
DELEGATION_LABEL_RE = re.compile(
    r"\b(delegate|delegation|fallback|fail-closed|failed|fire-and-forget)\b"
)


def build_function_table(solution_ast: dict[str, Any] | None) -> dict[str, Any]:
    """E1: Map function name -> body AST over def-logic / def / def-shell.
    LT-INV (v0.11): SDef emits {"kind":"def"} and SDefShell {"kind":"def-shell"};
    legacy SDefLogic emits {"kind":"def-logic"}. All three carry a body and are
    user-defined functions. Interface methods (def-interface) declare signatures
    only and are excluded.
    """
    DEF_KINDS = {"def-logic", "def", "def-shell"}
    table: dict[str, Any] = {}
    if not isinstance(solution_ast, dict):
        return table
    for stmt in solution_ast.get("statements", []):
        if not isinstance(stmt, dict):
            continue
        if stmt.get("kind") in DEF_KINDS:
            name = stmt.get("name")
            body = stmt.get("body")
            if isinstance(name, str) and body is not None:
                table[name] = body
    return table


def extract_callee_names(value: Any) -> set[str]:
    """E1: Yield function-call names (ExprApp.fn) reachable from `value`'s AST.
    Skips qual-app (wasi.*) — those are builtins, not user-defined and not
    in the function table.
    """
    callees: set[str] = set()
    _collect_callees(value, callees)
    return callees


def _collect_callees(value: Any, callees: set[str]) -> None:
    if isinstance(value, dict):
        if value.get("kind") == "app":
            fn = value.get("fn")
            if isinstance(fn, str):
                callees.add(fn)
        for child in value.values():
            _collect_callees(child, callees)
    elif isinstance(value, list):
        for child in value:
            _collect_callees(child, callees)


def body_reaches_delegation_via_calls(
    body: Any,
    function_table: dict[str, Any],
    visited: set[str] | None = None,
) -> bool:
    """E1: True iff `body`'s transitive callees contain a delegation hole.
    Does NOT inspect `body` itself — caller uses `contains_kind` for that.
    Cycle-safe via `visited` (function names). Conservative on indirect calls:
    callees not in function_table (builtins, def-interface methods) are
    assumed non-delegating; the label-regex fallback in collect_checks catches
    cases where this assumption fails. Per `findings/experiment-lead.md` E1
    soundness conditions.
    """
    if visited is None:
        visited = set()
    for callee in extract_callee_names(body):
        if callee in visited:
            continue
        visited.add(callee)
        callee_body = function_table.get(callee)
        if callee_body is None:
            continue
        if contains_kind(callee_body, DELEGATION_KINDS):
            return True
        if body_reaches_delegation_via_calls(callee_body, function_table, visited):
            return True
    return False


def collect_checks(solution_ast: dict[str, Any] | None) -> list[dict[str, Any]]:
    """E1: Classify each check as delegation-dependent via three parallel signals:
    (1) call-graph traversal from the check body through transitive callees to
    delegation holes; (2) structural contains_kind on the check's own AST subtree
    (catches inlined delegates); (3) label regex (defence-in-depth for cases
    where the call graph misses external/indirect calls). Any signal firing
    marks the check delegation-dependent; reasons are reported individually.
    """
    checks: list[dict[str, Any]] = []
    if not solution_ast:
        return checks

    function_table = build_function_table(solution_ast)

    for statement in solution_ast.get("statements", []):
        if not isinstance(statement, dict) or statement.get("kind") != "check":
            continue
        label = str(statement.get("label") or "")
        reasons: list[str] = []
        if contains_kind(statement, DELEGATION_KINDS):
            reasons.append("contains delegation or await")
        if body_reaches_delegation_via_calls(statement, function_table):
            reasons.append("call graph reaches delegation")
        if DELEGATION_LABEL_RE.search(label):
            reasons.append("delegation-related label")
        checks.append(
            {
                "label": label,
                "delegation_dependent": bool(reasons),
                "reasons": reasons,
            }
        )
    return checks


def parse_verify_details(stdout: str) -> dict[str, dict[str, str]]:
    details: dict[str, dict[str, str]] = {}
    current_name: str | None = None

    for line in stdout.splitlines():
        if line.strip() == "Summary:":
            break
        name_match = re.match(r"\s{2}([A-Za-z0-9_.-]+):\s*$", line)
        if name_match:
            current_name = name_match.group(1)
            continue
        status_match = re.search(r"pre:\s*(.*?)\s*\|\s*post:\s*(.*)$", line)
        if current_name and status_match:
            details[current_name] = {
                "pre": normalize_trust_status(status_match.group(1)),
                "post": normalize_trust_status(status_match.group(2)),
            }

    return details


def normalize_trust_status(value: str) -> str:
    value = value.strip()
    if not value or value in {"—", "-"}:
        return "none"
    # Strip trailing sample-count suffix: "tested (100 samples)" → "tested"
    value = re.sub(r"\s*\(.*\)\s*$", "", value)
    return value.lower()


def assess_contracts(
    problem_id: Any,
    solution_ast: dict[str, Any] | None,
    verify_details: dict[str, dict[str, str]] | None,
) -> dict[str, Any] | None:
    try:
        pid = int(problem_id)
    except (TypeError, ValueError):
        pid = 0
    expectations = CONTRACT_EXPECTATIONS.get(pid, {})
    if not expectations:
        return None

    items = []
    accepted_count = 0
    proof_required_ceiling_count = 0
    asserted_without_proof_count = 0

    for function_name, sides in expectations.items():
        statement = find_def_logic(solution_ast, function_name)
        for side, expectation in sides.items():
            contract_expr = statement.get(side) if statement else None
            present_in_ast = contract_expr is not None
            proof_required = contains_kind(contract_expr, {"hole-proof-required"})
            status = (verify_details or {}).get(function_name, {}).get(side, "none")
            expected_proof_required = bool(expectation.get("proof_required"))

            accepted = False
            reason = "missing contract"
            if present_in_ast and status in TRUST_STATUS_PRESENT:
                if expected_proof_required:
                    accepted = proof_required
                    reason = (
                        "accepted asserted proof-required ceiling"
                        if status == "asserted" and proof_required
                        else "proof-required contract accepted"
                    )
                else:
                    accepted = True
                    reason = "required contract present"
                    if status == "asserted":
                        asserted_without_proof_count += 1
            elif present_in_ast:
                reason = "contract present but absent from trust report"

            if accepted:
                accepted_count += 1
            if accepted and expected_proof_required and status == "asserted":
                proof_required_ceiling_count += 1

            items.append(
                {
                    "function": function_name,
                    "side": side,
                    "expected_proof_required": expected_proof_required,
                    "present_in_ast": present_in_ast,
                    "proof_required_marker": proof_required,
                    "trust_status": status,
                    "accepted": accepted,
                    "reason": reason,
                }
            )

    return {
        "expected_total": len(items),
        "accepted_total": accepted_count,
        "all_required_contracts_met": accepted_count == len(items),
        "proof_required_ceiling_accepted": proof_required_ceiling_count,
        "asserted_without_proof": asserted_without_proof_count,
        "items": items,
    }


def find_def_logic(
    solution_ast: dict[str, Any] | None,
    name: str,
) -> dict[str, Any] | None:
    if not solution_ast:
        return None
    DEF_KINDS = {"def-logic", "def", "def-shell"}
    for statement in solution_ast.get("statements", []):
        if (
            isinstance(statement, dict)
            and statement.get("kind") in DEF_KINDS
            and statement.get("name") == name
        ):
            return statement
    return None


def contains_kind(value: Any, kinds: set[str]) -> bool:
    if isinstance(value, dict):
        if value.get("kind") in kinds:
            return True
        return any(contains_kind(child, kinds) for child in value.values())
    if isinstance(value, list):
        return any(contains_kind(child, kinds) for child in value)
    return False


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
            "effective_success": None,
            "effective_failure_reason": None,
        }
    except FileNotFoundError as exc:
        return {
            "name": name,
            "argv": argv,
            "returncode": 127,
            "duration_seconds": round(time.monotonic() - started, 3),
            "stdout": "",
            "stderr": str(exc),
            "effective_success": False,
            "effective_failure_reason": "command not found",
        }
    except subprocess.TimeoutExpired as exc:
        return {
            "name": name,
            "argv": argv,
            "returncode": 124,
            "duration_seconds": round(time.monotonic() - started, 3),
            "stdout": exc.stdout or "",
            "stderr": exc.stderr or f"Timed out after {timeout} seconds.",
            "effective_success": False,
            "effective_failure_reason": "timeout",
        }


def annotate_command_result(result: dict[str, Any]) -> None:
    if result["returncode"] != 0:
        result["effective_success"] = False
        result["effective_failure_reason"] = f"nonzero exit code {result['returncode']}"
        return

    diagnostic = detect_compiler_diagnostic_failure(result["stdout"])
    if diagnostic:
        result["effective_success"] = False
        result["effective_failure_reason"] = diagnostic
        return

    result["effective_success"] = True
    result["effective_failure_reason"] = None


def detect_compiler_diagnostic_failure(stdout: str) -> str | None:
    text = stdout.strip()
    if not text:
        return None

    if text.startswith("(error "):
        return "compiler emitted error diagnostic"

    try:
        parsed = json.loads(text)
    except json.JSONDecodeError:
        return None

    if isinstance(parsed, dict):
        if parsed.get("success") is False:
            return "compiler JSON reported success=false"
        if parsed.get("severity") == "error":
            return "compiler JSON reported severity=error"
        if parsed.get("code") and ("message" in parsed or "suggestion" in parsed):
            return "compiler JSON reported diagnostic object"
    if isinstance(parsed, list):
        for item in parsed:
            if isinstance(item, dict) and item.get("severity") == "error":
                return "compiler JSON reported severity=error"
    return None


def parse_test_summary(stdout: str) -> dict[str, int] | None:
    text = stdout.strip()
    if not text:
        return None

    try:
        parsed = json.loads(text)
    except json.JSONDecodeError:
        parsed = None
    if isinstance(parsed, dict):
        keys = ("total", "passed", "failed", "skipped")
        if all(k in parsed for k in keys):
            return {k: int(parsed[k]) for k in keys}

    total_match = re.search(r"\b(\d+)\s+properties\b", text)
    passed_match = re.search(r"Passed:\s+(\d+)", text)
    failed_match = re.search(r"Failed:\s+(\d+)", text)
    skipped_match = re.search(r"Skipped:\s+(\d+)", text)
    if not (total_match and passed_match and failed_match and skipped_match):
        return None
    return {
        "total": int(total_match.group(1)),
        "passed": int(passed_match.group(1)),
        "failed": int(failed_match.group(1)),
        "skipped": int(skipped_match.group(1)),
    }


def parse_verify_summary(stdout: str) -> dict[str, int] | None:
    text = stdout.strip()
    if not text:
        return None

    summary: dict[str, int] = {}
    patterns = {
        "verified": r"verified:\s+(\d+)",
        "contract_checked": r"contract-checked:\s+(\d+)",
        "tested": r"tested:\s+(\d+)",
        "asserted": r"asserted:\s+(\d+)",
        "no_contract": r"no contract:\s+(\d+)",
    }
    for key, pattern in patterns.items():
        match = re.search(pattern, text)
        if match:
            summary[key] = int(match.group(1))

    return summary if summary else None


def parse_effect_summary(stdout: str) -> dict[str, Any] | None:
    """Capture the v0.12.0 Bundle B0 per-function effect/authority summary from
    `verify --obligation-report` JSON.

    Capture-only / descriptive: this never affects the quality grade or the
    first-error stop policy. Returns the per-function effects plus a
    bounded/unbounded roll-up, or None if no obligation-report JSON was emitted.

    Each effect_summary entry is {"function": name, "effects": <list | "unbounded">};
    a function whose authority is ``⊤`` ("may exercise any capability", e.g. at a
    ``?delegate``/FFI boundary) carries ``"unbounded"``. See
    docs/design/bundle-b0-effect-summary-proposal.md.
    """
    def is_unbounded(eff: Any) -> bool:
        return eff == "unbounded" or (isinstance(eff, list) and "unbounded" in eff)

    for line in stdout.splitlines():
        stripped = line.strip()
        if not stripped.startswith("{") or "effect_summary" not in stripped:
            continue
        try:
            obj = json.loads(stripped)
        except json.JSONDecodeError:
            continue
        entries = obj.get("effect_summary")
        if not isinstance(entries, list):
            continue
        any_unbounded = any(is_unbounded(e.get("effects")) for e in entries)
        return {
            "per_function": entries,
            "functions": len(entries),
            "any_unbounded": any_unbounded,
            "all_bounded": len(entries) > 0 and not any_unbounded,
            "cross_module": obj.get("cross_module"),
            "obligation_report_schema_version": obj.get("schema_version"),
        }
    return None


# ---------------------------------------------------------------------------
# Solver-catches grading (grader-gap). Inverted polarity vs capability mode:
# refuted = the solver caught the planted bug (success); verified = clean impl
# (no bug); vacuous (fixpoint could not reach a body-faithful VC) = non-catch.
# ---------------------------------------------------------------------------


def resolve_grading_mode_eval(metadata: dict[str, Any]) -> str:
    """Read grading_mode from run metadata; fall back to inferring it from the
    presence of a hidden-spec (for runs prepared before the field existed)."""
    mode = metadata.get("grading_mode")
    if mode in (GRADING_MODE_CAPABILITY, GRADING_MODE_SOLVER_CATCHES):
        return mode
    experiment_id = str(metadata.get("experiment_id") or "")
    if experiment_id and (HIDDEN_SPECS_ROOT / f"{experiment_id}.json").exists():
        return GRADING_MODE_SOLVER_CATCHES
    return GRADING_MODE_CAPABILITY


def load_hidden_spec(experiment_id: str) -> dict[str, Any] | None:
    path = HIDDEN_SPECS_ROOT / f"{experiment_id}.json"
    if not path.exists():
        return None
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return None
    return data if isinstance(data, dict) else None


def inject_hidden_posts(
    solution_ast: dict[str, Any],
    spec: dict[str, Any],
) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    """Return a deep copy of the agent solution with each hidden post written onto
    the named def's `side` field, replacing any agent-authored contract there (so
    the agent cannot pre-satisfy or weaken the discriminator). Returns
    (graded_ast, injected) where injected lists the (function, side) actually hit."""
    graded = copy.deepcopy(solution_ast)
    injected: list[dict[str, Any]] = []
    DEF_KINDS = {"def-logic", "def", "def-shell"}
    statements = graded.get("statements", []) if isinstance(graded, dict) else []
    for hidden in spec.get("hidden_posts", []):
        function = hidden.get("function")
        side = hidden.get("side", "post")
        post = hidden.get("post")
        for statement in statements:
            if (
                isinstance(statement, dict)
                and statement.get("kind") in DEF_KINDS
                and statement.get("name") == function
            ):
                statement[side] = post
                injected.append({"function": function, "side": side})
                break
    return graded, injected


def parse_fixpoint_outcome(text: str, target_fns: list[str]) -> dict[str, str]:
    """Classify each target function's fixpoint outcome from the combined
    stdout+stderr of `llmll verify <file> --strict-verified-core`. Empirically
    pinned signal contract (llmll 0.13.2 + liquid-fixpoint):
      refuted  : `refuted: <fn>` (strict-verified-core) OR
                 `body verification of '<fn>' failed`.
      verified : `SAFE (liquid-fixpoint)` present and no refutation for <fn>.
      vacuous  : neither — fixpoint could not reach a body-faithful VC (fallback,
                 codegen error, missing function). Never counts as a catch.
    """
    safe = "SAFE (liquid-fixpoint)" in text
    outcomes: dict[str, str] = {}
    for fn in target_fns:
        refuted = (f"refuted: {fn}" in text) or (
            f"body verification of '{fn}' failed" in text
        )
        if refuted:
            outcomes[fn] = "refuted"
        elif safe:
            outcomes[fn] = "verified"
        else:
            outcomes[fn] = "vacuous"
    return outcomes


def assess_solver_catch(
    spec: dict[str, Any],
    outcomes: dict[str, str],
    test_assessment: dict[str, Any] | None,
) -> dict[str, Any]:
    targets = [
        {"function": t.get("function"), "side": t.get("side", "post")}
        for t in spec.get("targets", [])
    ]
    # Tests must have RUN and all-applicable passed, with a non-empty effective
    # surface — the grader-gap thesis is "tests are blind, the solver is not."
    test_passed = bool(
        test_assessment
        and test_assessment.get("all_applicable_passed")
        and test_assessment.get("effective_total", 0) > 0
    )
    per_target = []
    any_refuted = False
    all_body_faithful = True
    for target in targets:
        outcome = outcomes.get(target["function"], "vacuous")
        per_target.append({**target, "outcome": outcome})
        if outcome == "refuted":
            any_refuted = True
        if outcome == "vacuous":
            all_body_faithful = False
    return {
        "available": True,
        "targets": per_target,
        "outcomes": outcomes,
        "test_passed": test_passed,
        "any_refuted": any_refuted,
        "all_targets_body_faithful": all_body_faithful,
        # The headline per-cell metric: tests blind (pass) AND solver refuted.
        "solver_caught": bool(any_refuted and test_passed),
    }


def run_solver_catch_verify(
    llmll: list[str],
    solution_ast: dict[str, Any] | None,
    metadata: dict[str, Any],
    run_dir: Path,
    *,
    timeout: int,
    commands_log: list[dict[str, Any]],
    test_assessment: dict[str, Any] | None,
) -> dict[str, Any]:
    experiment_id = str(metadata.get("experiment_id") or "")
    spec = load_hidden_spec(experiment_id)
    if spec is None:
        return {"available": False, "reason": "no hidden-spec for experiment"}
    if not isinstance(solution_ast, dict):
        return {"available": False, "reason": "solution is not JSON-AST"}

    graded_ast, injected = inject_hidden_posts(solution_ast, spec)
    graded_path = run_dir / "solution.graded.ast.json"
    graded_path.write_text(json.dumps(graded_ast, indent=2) + "\n", encoding="utf-8")
    graded_name = str(graded_path.relative_to(run_dir))

    result = run_command(
        "solver-catch-verify",
        llmll + ["verify", graded_name, "--strict-verified-core"],
        cwd=run_dir,
        timeout=timeout,
    )
    commands_log.append(result)

    target_fns = [
        t.get("function") for t in spec.get("targets", []) if t.get("function")
    ]
    text = (result.get("stdout") or "") + "\n" + (result.get("stderr") or "")
    outcomes = parse_fixpoint_outcome(text, target_fns)
    assessment = assess_solver_catch(spec, outcomes, test_assessment)
    assessment["injected"] = injected
    assessment["graded_solution"] = graded_name
    assessment["verify_returncode"] = result.get("returncode")
    return assessment


def solver_catch_grade(report: dict[str, Any]) -> str:
    """Inverted-polarity grade for solver-catches mode.
    A = solver_caught (tests blind + refuted); B = verified-clean or refuted-but-
    tests-also-caught (informative, not the target signal); C = vacuous non-catch
    (fixpoint could not reach a body-faithful VC — the F-B0-2 gate); F = the agent
    solution did not compile / missing required features."""
    if report.get("status") != "passed" and report.get("first_error"):
        return "F"
    feature_scan = report.get("feature_scan") or {}
    if feature_scan.get("missing_required"):
        return "F"
    sc = report.get("solver_catch") or {}
    if not sc.get("available"):
        return "C"
    if not sc.get("all_targets_body_faithful"):
        return "C"
    if sc.get("solver_caught"):
        return "A"
    return "B"


def quality_grade(report: dict[str, Any]) -> str:
    if report.get("grading_mode") == GRADING_MODE_SOLVER_CATCHES:
        return solver_catch_grade(report)

    if report.get("status") != "passed" and report.get("first_error"):
        return "F"

    feature_scan = report.get("feature_scan") or {}
    if feature_scan.get("missing_required"):
        return "F"

    test_assessment = report.get("test_assessment")
    contract_assessment = report.get("contract_assessment")

    if test_assessment:
        tests_ok = bool(test_assessment.get("all_applicable_passed"))
        effective_total = test_assessment.get("effective_total", 0)
        excluded = test_assessment.get("excluded_delegation_dependent", 0)
    else:
        tests_ok = True
        effective_total = 0
        excluded = 0

    if contract_assessment:
        contracts_ok = bool(contract_assessment.get("all_required_contracts_met"))
        asserted_without_proof = contract_assessment.get("asserted_without_proof", 0)
    else:
        contracts_ok = True
        asserted_without_proof = 0

    if not tests_ok or not contracts_ok:
        return "C"
    if effective_total == 0 and excluded > 0:
        return "B"
    if asserted_without_proof > 0:
        return "B"
    if test_assessment or contract_assessment:
        return "A"
    return "C"


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
        f"Quality grade: `{report.get('quality_grade', 'F')}`",
        f"Experiment: `{format_experiment_label(report)}`",
        f"Problem: `{report.get('problem_id')}`",
        f"Solution: `{report.get('solution')}`",
        f"Stop policy: `{report['stop_policy']}`",
        f"Agent duration: `{format_optional_seconds(report.get('agent_duration_seconds'))}`",
        f"Evaluation duration: `{report.get('total_eval_duration_seconds', 0.0)}s`",
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
                f"Effective failure: `{first_error.get('effective_failure_reason', 'n/a')}`",
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

    solver_catch = report.get("solver_catch")
    if solver_catch:
        lines.extend(["## Solver-Catch Assessment (grader-gap)", ""])
        if not solver_catch.get("available"):
            lines.append(
                f"Not available: {solver_catch.get('reason', 'unknown')}."
            )
        else:
            lines.append(
                f"Solver caught planted bug: `{solver_catch.get('solver_caught', False)}` "
                f"(tests blind/passed: `{solver_catch.get('test_passed', False)}`, "
                f"any target refuted: `{solver_catch.get('any_refuted', False)}`, "
                f"all targets body-faithful: `{solver_catch.get('all_targets_body_faithful', False)}`)."
            )
            for target in solver_catch.get("targets", []):
                lines.append(
                    f"- `{target.get('function')}`.{target.get('side')}: "
                    f"**{target.get('outcome')}**"
                )
        lines.append("")

    effect_summary = report.get("effect_summary")
    if effect_summary:
        lines.extend(["## Effect / Authority Summary (Bundle B0, v0.12.0)", ""])
        if effect_summary.get("all_bounded"):
            rollup = "all functions bounded (∅ or declared capabilities)"
        elif effect_summary.get("any_unbounded"):
            rollup = "contains unbounded (⊤) authority"
        else:
            rollup = "no contracted functions"
        lines.append(
            f"Roll-up: {rollup} — {effect_summary.get('functions', 0)} function(s), "
            f"cross_module=`{effect_summary.get('cross_module')}`, "
            f"obligation-report schema `{effect_summary.get('obligation_report_schema_version')}`."
        )
        for entry in effect_summary.get("per_function", []):
            eff = entry.get("effects")
            if eff == "unbounded":
                eff_str = "unbounded (⊤)"
            elif isinstance(eff, list):
                eff_str = "∅" if not eff else ", ".join(str(x) for x in eff)
            else:
                eff_str = str(eff)
            lines.append(f"- `{entry.get('function')}`: {eff_str}")
        lines.append("")

    test_summary = report.get("test_summary")
    if test_summary:
        lines.extend(
            [
                "## Raw Test Summary",
                "",
                f"Total: `{test_summary.get('total', 0)}`",
                f"Passed: `{test_summary.get('passed', 0)}`",
                f"Failed: `{test_summary.get('failed', 0)}`",
                f"Skipped: `{test_summary.get('skipped', 0)}`",
                "",
            ]
        )

    test_assessment = report.get("test_assessment")
    if test_assessment:
        lines.extend(
            [
                "## Adjusted Test Assessment",
                "",
                f"Effective total: `{test_assessment.get('effective_total', 0)}`",
                f"Effective passed: `{test_assessment.get('effective_passed', 0)}`",
                f"Effective failed: `{test_assessment.get('effective_failed', 0)}`",
                f"Effective skipped: `{test_assessment.get('effective_skipped', 0)}`",
                "Delegation-dependent excluded: "
                f"`{test_assessment.get('excluded_delegation_dependent', 0)}`",
                "",
            ]
        )

    verify_summary = report.get("verify_summary")
    if verify_summary:
        lines.extend(
            [
                "## Raw Verify Summary",
                "",
                f"Verified: `{verify_summary.get('verified', 0)}`",
                f"Contract checked: `{verify_summary.get('contract_checked', 0)}`",
                f"Tested: `{verify_summary.get('tested', 0)}`",
                f"Asserted: `{verify_summary.get('asserted', 0)}`",
                f"No contract: `{verify_summary.get('no_contract', 0)}`",
                "",
            ]
        )

    contract_assessment = report.get("contract_assessment")
    if contract_assessment:
        lines.extend(
            [
                "## Contract Assessment",
                "",
                "Expected contracts accepted: "
                f"`{contract_assessment.get('accepted_total', 0)}/"
                f"{contract_assessment.get('expected_total', 0)}`",
                "Proof-required ceilings accepted: "
                f"`{contract_assessment.get('proof_required_ceiling_accepted', 0)}`",
                "Asserted non-proof contracts: "
                f"`{contract_assessment.get('asserted_without_proof', 0)}`",
                "",
            ]
        )

    problems = report.get("problems_md")
    if problems:
        lines.extend(
            [
                "## Problems Log",
                "",
                f"Entries: `{problems.get('entry_count', 0)}`",
                f"No-problems marker: `{problems.get('has_no_problems_marker', False)}`",
                f"Stale no-problems marker: `{problems.get('stale_no_problems_marker', False)}`",
                "",
            ]
        )

    lines.extend(["## Commands", ""])
    for command in report.get("commands", []):
        argv = " ".join(shlex.quote(part) for part in command["argv"])
        effective = "ok" if command.get("effective_success") else "fail"
        lines.append(
            f"- `{command['name']}` rc={command['returncode']} "
            f"effective={effective} duration={command['duration_seconds']}s: `{argv}`"
        )
    lines.append("")
    return "\n".join(lines)


def truncate(value: str, limit: int = 4000) -> str:
    if len(value) <= limit:
        return value
    return value[:limit] + "\n...[truncated]..."


def format_optional_seconds(value: Any) -> str:
    if value is None:
        return "n/a"
    try:
        return f"{float(value):.3g}s"
    except (TypeError, ValueError):
        return "n/a"


def format_experiment_label(report: dict[str, Any]) -> str:
    experiment_id = report.get("experiment_id")
    experiment_slug = report.get("experiment_slug")
    if experiment_id and experiment_slug:
        return f"{experiment_id}-{experiment_slug}"
    return str(experiment_id or "n/a")


if __name__ == "__main__":
    raise SystemExit(main())
