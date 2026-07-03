#!/usr/bin/env python3
"""CDP-perf-0 driver.

Measures wall-clock cost of `llmll verify --cdp --trust-report` vs bare
`llmll verify` across experiments/cdp-perf-0/manifest.json's primary corpus
(shared fixture set with cdp-0), to answer the CDP default-on roadmap row's
stated remaining blocker: no wall-clock characterization of the --cdp
candidate-sweep exists.

Fits overhead_ms ~ a + b * total_candidate_count across the corpus (n = one
data point per FIXTURE, not per function — wall-clock is measured per whole
compiler invocation, so candidate_count is summed across all contracted
functions in that fixture before fitting).

Pure measurement — no model invocation, no network access. Timing noise is
handled via median-of-N-measured-reps with warmup reps discarded, mirroring
experiments/int-pre/'s replication discipline (lighter: 5+1 vs int-pre's
10+2, since this is a compile-time latency question, not a tight-threshold
runtime gate).

Usage (run from repo root):
    python3 experiments/cdp-perf-0/scripts/cdp_perf.py
"""

from __future__ import annotations

import datetime as dt
import json
import statistics
import subprocess
import sys
import time
from pathlib import Path
from typing import Any, NoReturn

HARNESS_DIR = Path(__file__).resolve().parent.parent
REPO_ROOT = HARNESS_DIR.parent.parent
MANIFEST_PATH = HARNESS_DIR / "manifest.json"


def die(code: int, msg: str) -> NoReturn:
    print(f"cdp_perf: {msg}", file=sys.stderr)
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


def run_once(fixture_abs: str, flags: list[str]) -> tuple[float, bool, str | None]:
    """One compiler invocation. Returns (wall_clock_seconds, ok, raw_stdout_if_cdp)."""
    cmd = ["stack", "exec", "llmll", "--", "--json", "verify"] + flags + [fixture_abs]
    t0 = time.perf_counter()
    proc = subprocess.run(
        cmd, cwd=str(REPO_ROOT / "compiler"), check=False,
        capture_output=True, text=True, timeout=120,
    )
    elapsed = time.perf_counter() - t0
    return elapsed, proc.returncode == 0, proc.stdout


def extract_total_candidate_count(stdout: str) -> int | None:
    """Sum candidate_count across all discriminative_axis entries in the
    trust-report JSON line. Returns None if no such line parses (bare mode,
    or a compiler-error cell)."""
    for line in stdout.splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue
        if "trust_report_version" not in obj:
            continue
        total = 0
        for entry in obj.get("entries", []):
            axis = entry.get("discriminative_axis")
            if axis and axis.get("candidate_count") is not None:
                total += axis["candidate_count"]
        return total
    return None


def measure_fixture_mode(fixture_abs: str, flags: list[str], reps: dict[str, int]) -> dict[str, Any]:
    warmup_n = reps["warmup"]
    measured_n = reps["measured"]
    for _ in range(warmup_n):
        run_once(fixture_abs, flags)
    timings = []
    ok_all = True
    candidate_count = None
    for _ in range(measured_n):
        elapsed, ok, stdout = run_once(fixture_abs, flags)
        timings.append(elapsed)
        ok_all = ok_all and ok
        if candidate_count is None and stdout is not None:
            candidate_count = extract_total_candidate_count(stdout)
    return {
        "ok": ok_all,
        "timings_s": timings,
        "median_s": statistics.median(timings),
        "candidate_count": candidate_count,
    }


def fit_linear(xs: list[float], ys: list[float]) -> dict[str, float]:
    """Least-squares fit y = a + b*x. Returns a, b, r_squared."""
    n = len(xs)
    mean_x = sum(xs) / n
    mean_y = sum(ys) / n
    ss_xy = sum((x - mean_x) * (y - mean_y) for x, y in zip(xs, ys))
    ss_xx = sum((x - mean_x) ** 2 for x in xs)
    if ss_xx == 0:
        return {"a": mean_y, "b": 0.0, "r_squared": 0.0}
    b = ss_xy / ss_xx
    a = mean_y - b * mean_x
    ss_tot = sum((y - mean_y) ** 2 for y in ys)
    ss_res = sum((y - (a + b * x)) ** 2 for x, y in zip(xs, ys))
    r_squared = 1 - (ss_res / ss_tot) if ss_tot > 0 else 1.0
    return {"a": a, "b": b, "r_squared": r_squared}


def main() -> None:
    manifest = load_manifest()
    ts = utc_timestamp()
    run_dir = HARNESS_DIR / "runs" / ts
    (run_dir / "per-fixture").mkdir(parents=True, exist_ok=True)

    reps = manifest["reps"]
    modes = {m["id"]: m["flags"] for m in manifest["modes"]}

    per_fixture: list[dict[str, Any]] = []
    for fix in manifest["primary_corpus"]:
        fixture_abs = str(REPO_ROOT / fix["path"])
        print(f"[cdp-perf-0] {fix['id']} bare...", file=sys.stderr)
        bare = measure_fixture_mode(fixture_abs, modes["bare"], reps)
        print(f"[cdp-perf-0] {fix['id']} cdp...", file=sys.stderr)
        cdp = measure_fixture_mode(fixture_abs, modes["cdp"], reps)
        overhead_s = cdp["median_s"] - bare["median_s"]
        entry = {
            "id": fix["id"], "path": fix["path"],
            "bare": bare, "cdp": cdp,
            "overhead_ms": overhead_s * 1000,
            "total_candidate_count": cdp["candidate_count"],
        }
        per_fixture.append(entry)
        (run_dir / "per-fixture" / f"{fix['id']}.json").write_text(json.dumps(entry, indent=2))

    valid = [e for e in per_fixture if e["bare"]["ok"] and e["cdp"]["ok"]
             and e["total_candidate_count"] is not None]
    fit = None
    if len(valid) >= 2:
        xs = [float(e["total_candidate_count"]) for e in valid]
        ys = [e["overhead_ms"] for e in valid]
        fit = fit_linear(xs, ys)

    results = {
        "experiment": "cdp-perf-0",
        "timestamp_utc": ts,
        "compiler_ref": manifest["compiler_ref"],
        "reps": reps,
        "per_fixture": per_fixture,
        "fit": fit,
        "n_fixtures_in_fit": len(valid),
    }
    (run_dir / "results.json").write_text(json.dumps(results, indent=2))
    write_summary(run_dir, manifest, results)
    print(f"[cdp-perf-0] run dir: {run_dir.relative_to(REPO_ROOT)}", file=sys.stderr)


def write_summary(run_dir: Path, manifest: dict[str, Any], results: dict[str, Any]) -> None:
    lines = [
        "# cdp-perf-0 run summary",
        "",
        f"- **Timestamp (UTC):** {results['timestamp_utc']}",
        f"- **Compiler:** `{manifest['compiler_ref']['version_string']}` (`{manifest['compiler_ref']['tag']}`, `{manifest['compiler_ref']['short_sha']}`)",
        f"- **Reps:** {manifest['reps']['measured']} measured + {manifest['reps']['warmup']} warmup, median reported",
        "",
        "## Per-fixture",
        "",
        "| fixture | bare median (ms) | cdp median (ms) | overhead (ms) | total candidate_count |",
        "|---|---|---|---|---|",
    ]
    for e in results["per_fixture"]:
        status = "" if (e["bare"]["ok"] and e["cdp"]["ok"]) else " **[ERROR]**"
        lines.append(
            f"| {e['id']}{status} | {e['bare']['median_s']*1000:.1f} | {e['cdp']['median_s']*1000:.1f} "
            f"| {e['overhead_ms']:.1f} | {e['total_candidate_count']} |"
        )
    if results["fit"]:
        f = results["fit"]
        lines += [
            "",
            "## Fit: overhead_ms ~ a + b * total_candidate_count",
            "",
            f"- n = {results['n_fixtures_in_fit']} fixtures",
            f"- a (fixed overhead, ms) = {f['a']:.2f}",
            f"- b (marginal cost per candidate, ms) = {f['b']:.2f}",
            f"- R² = {f['r_squared']:.4f}",
        ]
    (run_dir / "summary.md").write_text("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
