#!/usr/bin/env python3
"""Adversarial spec-weakening benchmark (adv-spec-weaken-0) driver.

Reads experiments/adv-spec-weaken-0/manifest.json, runs each fixture under
each of the four CLI configs (`--weakness-check --json`, `--cdp
--trust-report --json`, `--strict-verify --json`, `--strict-verify` text
mode), captures and classifies every JSON line the compiler emits per
invocation, and writes runs/<timestamp>/{results.json, summary.md,
per-fixture/*.json}.

Pure measurement — no model invocation, no API spend, no network access.
Mirrors experiments/cdp-0/scripts/cdp_baseline.py's shape and the `--json`
top-level-flag-precedes-subcommand convention documented there
(postmortem-001 F-003).

Usage (from anywhere; paths resolve relative to the manifest):

    python3 experiments/adv-spec-weaken-0/scripts/run_adv_weaken.py

Exit codes:
    0 — run completed
    2 — manifest parse error or compiler binary not available
    3 — every fixture/config cell failed
"""

from __future__ import annotations

import datetime as dt
import json
import subprocess
import sys
from pathlib import Path
from typing import Any, NoReturn

HARNESS_DIR = Path(__file__).resolve().parent.parent
REPO_ROOT = HARNESS_DIR.parent.parent
MANIFEST_PATH = HARNESS_DIR / "manifest.json"


def die(code: int, msg: str) -> NoReturn:
    print(f"run_adv_weaken: {msg}", file=sys.stderr)
    sys.exit(code)


def load_manifest() -> dict[str, Any]:
    if not MANIFEST_PATH.exists():
        die(2, f"manifest not found: {MANIFEST_PATH}")
    try:
        return json.loads(MANIFEST_PATH.read_text())
    except json.JSONDecodeError as e:
        die(2, f"manifest parse error: {e}")


def utc_timestamp() -> str:
    return dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def classify_json_line(obj: dict[str, Any]) -> str:
    """Classify a parsed JSON object by its distinctive keys."""
    if "weakness_check" in obj:
        return "weakness_check"
    if "trust_report_version" in obj:
        return "cdp_trust_report"
    if "diagnostics" in obj and "phase" in obj and "body_faithful" in obj:
        return "fixpoint_result"
    if "entries" in obj and "laws" in obj:
        return "spec_coverage"
    return "unknown"


def run_one(fixture_abs: str, flags: list[str], json_mode: bool) -> dict[str, Any]:
    cmd = ["stack", "exec", "llmll", "--"]
    if json_mode:
        cmd.append("--json")
    cmd += ["verify"] + flags + [fixture_abs]
    try:
        proc = subprocess.run(
            cmd,
            cwd=str(REPO_ROOT / "compiler"),
            check=False,
            capture_output=True,
            text=True,
            timeout=60,
        )
    except subprocess.TimeoutExpired:
        return {"status": "timeout", "stdout": "", "stderr": "timeout-60s"}
    except FileNotFoundError:
        die(2, "stack not found in PATH — required to invoke llmll compiler")

    # A nonzero exit (parse/typecheck/grammar rejection) is a distinct outcome
    # from a clean run with no diagnostic — conflating the two here is exactly
    # what silently mis-scored ax1-04's first run as "silent" when the fixture
    # had actually failed to compile (non-core '*' syntax rejected under 'def').
    result: dict[str, Any] = {
        "status": "ok" if proc.returncode == 0 else "compiler-error",
        "returncode": proc.returncode,
        "stdout_raw": proc.stdout,
        "stderr_raw": proc.stderr,
    }
    if json_mode:
        parsed_lines = []
        for line in proc.stdout.splitlines():
            line = line.strip()
            if not line.startswith("{"):
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue
            parsed_lines.append({"kind": classify_json_line(obj), "data": obj})
        result["json_lines"] = parsed_lines
    else:
        # Text mode: pull out the two human-readable diagnostic markers this
        # benchmark cares about — spec-weakness lines and the module-level
        # over-annotation-warning line (Main.hs:1479-1488).
        result["over_annotation_warning_present"] = "over-annotation-warning" in proc.stdout
        result["spec_weakness_lines"] = [
            l for l in proc.stdout.splitlines() if "Spec weakness detected" in l
        ]
    return result


def summarize_cell(cell: dict[str, Any], config_id: str) -> dict[str, Any]:
    """Pull the load-bearing signal out of one fixture x config cell."""
    if cell["status"] != "ok":
        return {"signal": "ERROR", "detail": cell["status"]}

    if config_id == "strict-verify-text":
        signals = []
        if cell.get("over_annotation_warning_present"):
            signals.append("over-annotation-warning")
        if cell.get("spec_weakness_lines"):
            signals.append(f"spec-weakness x{len(cell['spec_weakness_lines'])}")
        return {"signal": ",".join(signals) if signals else "silent"}

    lines = cell.get("json_lines", [])
    signals = []
    for entry in lines:
        kind, data = entry["kind"], entry["data"]
        if kind == "weakness_check":
            n = len(data.get("weaknesses", []))
            if n:
                signals.append(f"weakness-check-diag x{n}")
        elif kind == "cdp_trust_report":
            oa = data.get("over_annotation")
            if oa is not None:
                signals.append(f"over_annotation:ratio={oa.get('ratio')},warning={oa.get('warning')}")
            for e in data.get("entries", []):
                axis = e.get("discriminative_axis", {})
                warns = axis.get("warnings", [])
                real_warns = [w for w in warns if w not in ("not-requested",)]
                if real_warns:
                    signals.append(f"cdp:{e.get('name')}:{','.join(real_warns)}")
                signals.append(f"cdp:{e.get('name')}:score={axis.get('score')}")
                signals.append(f"cdp:{e.get('name')}:entropy={axis.get('spec_entropy_annotation')}")
        elif kind == "fixpoint_result":
            signals.append(f"effective:{data.get('success')}")
    return {"signal": "; ".join(signals) if signals else "silent"}


def main() -> None:
    manifest = load_manifest()
    ts = utc_timestamp()
    run_dir = HARNESS_DIR / "runs" / ts
    (run_dir / "per-fixture").mkdir(parents=True, exist_ok=True)

    configs = {c["id"]: c for c in manifest["cli_configs"]}
    results: dict[str, Any] = {
        "experiment": manifest["experiment"],
        "rev": manifest["rev"],
        "timestamp_utc": ts,
        "compiler_ref": manifest["compiler_ref"],
        "cells": [],
    }

    for fix in manifest["fixtures"]:
        fixture_abs = str(REPO_ROOT / fix["path"])
        print(f"[adv-spec-weaken-0] {fix['id']}", file=sys.stderr)
        per_fixture: dict[str, Any] = {"fixture_id": fix["id"], "axis": fix["axis"],
                                        "control_for": fix["control_for"], "configs": {}}
        for cfg_id, cfg in configs.items():
            cell = run_one(fixture_abs, cfg["flags"], cfg["json"])
            summary = summarize_cell(cell, cfg_id)
            per_fixture["configs"][cfg_id] = {"raw": cell, "summary": summary}
            results["cells"].append({
                "fixture_id": fix["id"], "config_id": cfg_id, "summary": summary,
            })
        (run_dir / "per-fixture" / f"{fix['id']}.json").write_text(
            json.dumps(per_fixture, indent=2)
        )

    (run_dir / "results.json").write_text(json.dumps(results, indent=2))
    write_summary_md(run_dir, manifest, results)
    print(f"[adv-spec-weaken-0] run dir: {run_dir.relative_to(REPO_ROOT)}", file=sys.stderr)


def write_summary_md(run_dir: Path, manifest: dict[str, Any], results: dict[str, Any]) -> None:
    lines = [
        "# adv-spec-weaken-0 run summary",
        "",
        f"- **Timestamp (UTC):** {results['timestamp_utc']}",
        f"- **Compiler SHA:** `{manifest['compiler_ref']['short_sha']}` "
            f"({manifest['compiler_ref']['branch']})",
        f"- **`llmll version`:** `{manifest['compiler_ref']['version_string']}`",
        "",
        "## Per-fixture signal by CLI config",
        "",
        "| fixture | weakness-check-json | cdp-json | strict-verify-json | strict-verify-text |",
        "|---|---|---|---|---|",
    ]
    by_fixture: dict[str, dict[str, str]] = {}
    for cell in results["cells"]:
        by_fixture.setdefault(cell["fixture_id"], {})[cell["config_id"]] = cell["summary"]["signal"]
    for fix in manifest["fixtures"]:
        row = by_fixture.get(fix["id"], {})
        lines.append(
            f"| {fix['id']} | {row.get('weakness-check-json', '?')} "
            f"| {row.get('cdp-json', '?')} | {row.get('strict-verify-json', '?')} "
            f"| {row.get('strict-verify-text', '?')} |"
        )
    (run_dir / "summary.md").write_text("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
