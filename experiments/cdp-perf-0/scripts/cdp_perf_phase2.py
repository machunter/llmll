#!/usr/bin/env python3
"""CDP-perf-0 Phase 2 driver.

Extends the Phase 1 run (postmortem-001) two ways, per its stated
acceptance criteria for F-002 (candidate count alone doesn't predict
overhead):

1. Re-measures the 6 primary-corpus fixtures at higher replication
   (reps_phase2_primary: 15 measured + 2 warmup, vs Phase 1's 5+1) to check
   whether b3's anomalous per-candidate cost is reproducible or was noise.
2. Discovers and measures the cdp-0 secondary corpus (same include/exclude
   globs as experiments/cdp-0/manifest.json) at reps_phase2_secondary
   (5+1) for more (candidate_count, overhead) data points, and tags each
   scored function's source with a crude match/hole heuristic (substring
   search, not AST-level) to test whether match/hole-shaped functions
   correlate with elevated per-candidate cost.

Pure measurement — no model invocation, no network access.

Usage (run from repo root):
    python3 experiments/cdp-perf-0/scripts/cdp_perf_phase2.py
"""

from __future__ import annotations

import fnmatch
import json
import statistics
import sys
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))
from cdp_perf import (  # noqa: E402
    HARNESS_DIR, REPO_ROOT, load_manifest, utc_timestamp,
    run_once, extract_total_candidate_count, fit_linear,
)


def measure_fixture_mode(fixture_abs: str, flags: list[str], reps: dict[str, int]) -> dict[str, Any]:
    for _ in range(reps["warmup"]):
        run_once(fixture_abs, flags)
    timings, ok_all, candidate_count = [], True, None
    for _ in range(reps["measured"]):
        elapsed, ok, stdout = run_once(fixture_abs, flags)
        timings.append(elapsed)
        ok_all = ok_all and ok
        if candidate_count is None and stdout is not None:
            candidate_count = extract_total_candidate_count(stdout)
    return {
        "ok": ok_all, "timings_s": timings,
        "median_s": statistics.median(timings), "candidate_count": candidate_count,
    }


def discover_secondary(manifest: dict[str, Any], primary_paths: set[str]) -> list[dict[str, str]]:
    cfg = manifest["secondary_corpus_discovery"]
    found = []
    for inc in cfg["include_globs"]:
        for path in sorted(REPO_ROOT.glob(inc)):
            rel = path.relative_to(REPO_ROOT).as_posix()
            if rel in primary_paths:
                continue
            if any(fnmatch.fnmatch(rel, ex) for ex in cfg["exclude_globs"]):
                continue
            slug = rel.replace("/", "_").replace(".", "_")
            found.append({"id": f"sec_{slug}", "path": rel})
    return found


def structural_tag(path_abs: Path) -> str:
    """Crude substring heuristic — NOT an AST-level check. 'match-or-hole' if
    the source contains a match expression or an unfilled hole; 'plain'
    otherwise. Caveat this explicitly wherever it's cited."""
    try:
        text = path_abs.read_text()
    except OSError:
        return "unreadable"
    if path_abs.suffix == ".json":
        hit = ('"match"' in text) or ('"kind": "hole"' in text) or ('"kind":"hole"' in text) or ('?' in text)
    else:
        hit = ("(match " in text) or ("?" in text)
    return "match-or-hole" if hit else "plain"


def measure_one(fix: dict[str, str], reps: dict[str, int], modes: dict[str, list[str]]) -> dict[str, Any]:
    fixture_abs = REPO_ROOT / fix["path"]
    bare = measure_fixture_mode(str(fixture_abs), modes["bare"], reps)
    cdp = measure_fixture_mode(str(fixture_abs), modes["cdp"], reps)
    return {
        "id": fix["id"], "path": fix["path"],
        "bare": bare, "cdp": cdp,
        "overhead_ms": (cdp["median_s"] - bare["median_s"]) * 1000,
        "total_candidate_count": cdp["candidate_count"],
        "structural_tag": structural_tag(fixture_abs),
    }


def main() -> None:
    manifest = load_manifest()
    ts = utc_timestamp()
    run_dir = HARNESS_DIR / "runs" / f"{ts}-phase2"
    (run_dir / "per-fixture").mkdir(parents=True, exist_ok=True)

    modes = {m["id"]: m["flags"] for m in manifest["modes"]}
    reps_primary = manifest["reps_phase2_primary"]
    reps_secondary = manifest["reps_phase2_secondary"]

    primary = manifest["primary_corpus"]
    primary_paths = {f["path"] for f in primary}
    secondary = discover_secondary(manifest, primary_paths)

    print(f"[cdp-perf-0-phase2] primary: {len(primary)} fixtures @ {reps_primary}", file=sys.stderr)
    print(f"[cdp-perf-0-phase2] secondary: {len(secondary)} fixtures @ {reps_secondary}", file=sys.stderr)

    results_primary = []
    for fix in primary:
        print(f"[cdp-perf-0-phase2] primary {fix['id']}...", file=sys.stderr)
        entry = measure_one(fix, reps_primary, modes)
        entry["corpus"] = "primary"
        results_primary.append(entry)
        (run_dir / "per-fixture" / f"{fix['id']}.json").write_text(json.dumps(entry, indent=2))

    results_secondary = []
    for fix in secondary:
        print(f"[cdp-perf-0-phase2] secondary {fix['id']}...", file=sys.stderr)
        try:
            entry = measure_one(fix, reps_secondary, modes)
        except Exception as e:  # log-and-continue per stop_policy
            entry = {"id": fix["id"], "path": fix["path"], "error": str(e),
                      "bare": {"ok": False}, "cdp": {"ok": False},
                      "overhead_ms": None, "total_candidate_count": None,
                      "structural_tag": "error"}
        entry["corpus"] = "secondary"
        results_secondary.append(entry)
        (run_dir / "per-fixture" / f"{fix['id']}.json").write_text(json.dumps(entry, indent=2))

    all_fixtures = results_primary + results_secondary
    valid = [e for e in all_fixtures if e["bare"].get("ok") and e["cdp"].get("ok")
             and e.get("total_candidate_count") is not None and e["total_candidate_count"] > 0]

    fit_all = None
    if len(valid) >= 2:
        xs = [float(e["total_candidate_count"]) for e in valid]
        ys = [e["overhead_ms"] for e in valid]
        fit_all = fit_linear(xs, ys)

    by_tag: dict[str, list[float]] = {}
    for e in valid:
        per_candidate = e["overhead_ms"] / e["total_candidate_count"]
        by_tag.setdefault(e["structural_tag"], []).append(per_candidate)
    tag_summary = {
        tag: {"n": len(vals), "median_ms_per_candidate": statistics.median(vals)}
        for tag, vals in by_tag.items()
    }

    results = {
        "experiment": "cdp-perf-0-phase2",
        "timestamp_utc": ts,
        "compiler_ref": manifest["compiler_ref"],
        "reps_primary": reps_primary,
        "reps_secondary": reps_secondary,
        "primary": results_primary,
        "secondary": results_secondary,
        "fit_all_fixtures": fit_all,
        "n_fixtures_in_fit": len(valid),
        "per_candidate_cost_by_structural_tag": tag_summary,
    }
    (run_dir / "results.json").write_text(json.dumps(results, indent=2))
    write_summary(run_dir, results)
    print(f"[cdp-perf-0-phase2] run dir: {run_dir.relative_to(REPO_ROOT)}", file=sys.stderr)


def write_summary(run_dir: Path, results: dict[str, Any]) -> None:
    lines = [
        "# cdp-perf-0 Phase 2 run summary",
        "",
        f"- **Timestamp (UTC):** {results['timestamp_utc']}",
        f"- **Compiler:** `{results['compiler_ref']['version_string']}`",
        f"- **Primary reps:** {results['reps_primary']['measured']} measured + {results['reps_primary']['warmup']} warmup",
        f"- **Secondary reps:** {results['reps_secondary']['measured']} measured + {results['reps_secondary']['warmup']} warmup",
        "",
        "## Primary corpus (re-measured at higher reps)",
        "",
        "| fixture | bare (ms) | cdp (ms) | overhead (ms) | candidates | ms/candidate | tag |",
        "|---|---|---|---|---|---|---|",
    ]
    for e in results["primary"]:
        cc = e["total_candidate_count"]
        per_c = f"{e['overhead_ms']/cc:.1f}" if cc else "n/a"
        lines.append(f"| {e['id']} | {e['bare']['median_s']*1000:.1f} | {e['cdp']['median_s']*1000:.1f} "
                      f"| {e['overhead_ms']:.1f} | {cc} | {per_c} | {e['structural_tag']} |")

    lines += ["", "## Secondary corpus", "", "| fixture | status | overhead (ms) | candidates | ms/candidate | tag |", "|---|---|---|---|---|---|"]
    for e in results["secondary"]:
        if not (e["bare"].get("ok") and e["cdp"].get("ok")):
            lines.append(f"| {e['id']} | ERROR/{e.get('error','n/a')} | - | - | - | - |")
            continue
        cc = e["total_candidate_count"]
        per_c = f"{e['overhead_ms']/cc:.1f}" if cc else "n/a"
        lines.append(f"| {e['id']} | ok | {e['overhead_ms']:.1f} | {cc} | {per_c} | {e['structural_tag']} |")

    if results["fit_all_fixtures"]:
        f = results["fit_all_fixtures"]
        lines += ["", "## Fit across all valid fixtures (candidate_count > 0)", "",
                  f"- n = {results['n_fixtures_in_fit']}",
                  f"- a = {f['a']:.2f} ms, b = {f['b']:.2f} ms/candidate, R² = {f['r_squared']:.4f}"]

    lines += ["", "## Per-candidate cost by structural tag (crude substring heuristic)", ""]
    for tag, s in results["per_candidate_cost_by_structural_tag"].items():
        lines.append(f"- `{tag}`: n={s['n']}, median ms/candidate = {s['median_ms_per_candidate']:.1f}")

    (run_dir / "summary.md").write_text("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
