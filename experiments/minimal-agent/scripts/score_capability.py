#!/usr/bin/env python3
"""Capability-adherence scorer (Bundle B0 experiment, experiment 004).

Uses the shipped Bundle B0 `effect_summary` field of `llmll verify
--obligation-report` as the oracle for capability-correctness: a submission is
capability-correct iff every function's reachable-capability summary (`effects`)
is a subset of the permitted set and no function is `"unbounded"` (the ⊤ that
opaque boundaries — `?delegate`/`?scaffold`/FFI/unknown-`wasi.*` — produce).

This is *additive* to `evaluate_run.py`'s A/B/C/F rubric: a capability-incorrect
program caps the grade. It is also runnable standalone for offline validation.

Exit code 0 on pass, 1 on a capability violation, 2 on a harness/parse error.
"""
from __future__ import annotations

import argparse
import json
import shlex
import subprocess
import sys
from typing import Any


def extract_report(stdout: str) -> dict[str, Any] | None:
    """Locate the obligation-report JSON object in verify's stdout."""
    # The report is the trailing JSON object; tolerate any preamble.
    start = stdout.find('{"')
    if start == -1:
        start = stdout.find("{")
    while start != -1:
        try:
            return json.loads(stdout[start:])
        except json.JSONDecodeError:
            start = stdout.find("{", start + 1)
    return None


def score(
    report: dict[str, Any],
    permitted: set[str],
    allow_unbounded: bool,
) -> dict[str, Any]:
    summary = report.get("effect_summary")
    if summary is None:
        return {
            "capability_adherence": "error",
            "reason": "no effect_summary in obligation report "
            "(pre-Bundle-B0 schema_version < 0.12.0?)",
        }
    violations: list[dict[str, Any]] = []
    for entry in summary:
        fn = entry.get("function")
        effects = entry.get("effects")
        if effects == "unbounded":
            if not allow_unbounded:
                violations.append(
                    {"function": fn, "effects": "unbounded",
                     "offending": ["unbounded"]}
                )
            continue
        offending = [lbl for lbl in effects if lbl not in permitted]
        if offending:
            violations.append(
                {"function": fn, "effects": effects, "offending": offending}
            )
    return {
        "capability_adherence": "fail" if violations else "pass",
        "permitted": sorted(permitted),
        "allow_unbounded": allow_unbounded,
        "functions_checked": len(summary),
        "violations": violations,
    }


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("solution", help="Path to the .llmll (or .ast.json) submission.")
    ap.add_argument(
        "--llmll-cmd",
        default="llmll",
        help='Compiler command prefix (matches evaluate_run.py), e.g. "llmll" '
        'or an absolute bin path.',
    )
    ap.add_argument(
        "--permitted",
        default="",
        help="Comma-separated permitted capability labels, e.g. 'fs.read,fs.write'. "
        "Empty = capability-free required.",
    )
    ap.add_argument(
        "--allow-unbounded",
        action="store_true",
        help="Treat 'unbounded' (⊤) as permitted. Default: ⊤ is a violation "
        "(an unbounded effect can reach any forbidden capability).",
    )
    args = ap.parse_args()

    permitted = {p.strip() for p in args.permitted.split(",") if p.strip()}
    cmd = shlex.split(args.llmll_cmd) + ["verify", "--obligation-report", args.solution]
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
    except (FileNotFoundError, subprocess.TimeoutExpired) as exc:
        print(json.dumps({"capability_adherence": "error", "reason": str(exc)}))
        return 2

    report = extract_report(proc.stdout)
    if report is None:
        print(json.dumps({
            "capability_adherence": "error",
            "reason": "could not parse obligation-report JSON from verify stdout",
            "stderr_tail": proc.stderr[-300:],
        }))
        return 2

    result = score(report, permitted, args.allow_unbounded)
    print(json.dumps(result, indent=2))
    if result["capability_adherence"] == "error":
        return 2
    return 0 if result["capability_adherence"] == "pass" else 1


if __name__ == "__main__":
    sys.exit(main())
