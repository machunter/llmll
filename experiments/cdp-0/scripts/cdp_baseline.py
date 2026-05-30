#!/usr/bin/env python3
"""CDP-0 baseline driver.

Reads experiments/cdp-0/manifest.json, runs `stack exec llmll -- --json verify
--cdp --trust-report <fixture>` per primary + discovered-secondary fixture
at the repo root, aggregates `entries[*].discriminative_axis` blocks, computes
the four-label adjudication per the manifest's outcome_labels table, and
writes runs/<timestamp>-baseline/{baseline.json, summary.md, per-fixture/*.json}.

Pure measurement — no model invocation, no API spend, no network access.
The aggregated baseline.json is the load-bearing artifact the future LT-INV §8
empirical-validation gate loads as the spec-strength-distribution comparison
anchor (per contract-discriminative-power-proposal.md Rev 2 §2).

Usage (run from repo root, harness dir, or anywhere — paths resolved relative
to the manifest):

    python3 experiments/cdp-0/scripts/cdp_baseline.py
    python3 experiments/cdp-0/scripts/cdp_baseline.py --primary-only

Exit codes:
    0  — run completed; aggregated output written; adjudication label set
    2  — manifest parse error or compiler binary not available
    3  — every fixture failed (no DP data collected)
"""

from __future__ import annotations

import argparse
import datetime as dt
import fnmatch
import json
import statistics
import subprocess
import sys
from pathlib import Path
from typing import Any, NoReturn


HARNESS_DIR = Path(__file__).resolve().parent.parent
REPO_ROOT = HARNESS_DIR.parent.parent
MANIFEST_PATH = HARNESS_DIR / "manifest.json"


def utc_timestamp() -> str:
    return dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def load_manifest() -> dict[str, Any]:
    if not MANIFEST_PATH.exists():
        die(2, f"manifest not found: {MANIFEST_PATH}")
    try:
        return json.loads(MANIFEST_PATH.read_text())
    except json.JSONDecodeError as e:
        die(2, f"manifest parse error: {e}")


def die(code: int, msg: str) -> NoReturn:
    print(f"cdp_baseline: {msg}", file=sys.stderr)
    sys.exit(code)


def discover_secondary(manifest: dict[str, Any], primary_paths: set[str]) -> list[dict[str, str]]:
    """Walk include_globs minus exclude_globs minus primary paths."""
    cfg = manifest["secondary_corpus_discovery"]
    includes = cfg["include_globs"]
    excludes = cfg["exclude_globs"]
    found: list[dict[str, str]] = []
    for inc in includes:
        for path in sorted(REPO_ROOT.glob(inc)):
            rel = path.relative_to(REPO_ROOT).as_posix()
            if rel in primary_paths:
                continue
            if any(fnmatch.fnmatch(rel, ex) for ex in excludes):
                continue
            slug = rel.replace("/", "_").replace(".", "_")
            found.append({"id": f"sec_{slug}", "path": rel, "reason": "secondary-discovery"})
    return found


def run_verify_cdp(rel_path: str) -> tuple[bool, dict[str, Any] | None, str]:
    """Invoke `stack exec llmll -- --json verify --cdp --trust-report <rel_path>`
    at the repo root. Returns (ok, parsed_json_or_None, raw_stdout_or_error).

    Note: `--json` is a llmll-level option (per `llmll --help`), not a
    verify-subcommand option, so it must precede `verify` in the argv. F-003
    in postmortem-001 details how the prior placement (`verify ... --json`)
    silently failed every fixture with `Invalid option '--json'`."""
    # Stack requires invocation from the compiler/ dir (where stack.yaml lives),
    # but rel_path is relative to the repo root — pass the absolute path so the
    # llmll binary resolves the fixture regardless of cwd.
    abs_path = str(REPO_ROOT / rel_path)
    cmd = [
        "stack", "exec", "llmll", "--",
        "--json",                                # top-level flag — must precede subcommand
        "verify", "--cdp", "--trust-report",
        abs_path,
    ]
    try:
        proc = subprocess.run(
            cmd,
            cwd=str(REPO_ROOT / "compiler"),
            check=False,
            capture_output=True,
            text=True,
            timeout=120,
        )
    except subprocess.TimeoutExpired:
        return False, None, "timeout-120s"
    except FileNotFoundError:
        die(2, "stack not found in PATH — required to invoke llmll compiler")
    stdout = proc.stdout
    stderr = proc.stderr
    # The verify output writes a few stderr-like progress lines BEFORE the JSON;
    # trust-report JSON is the last non-empty line. Strip non-JSON noise.
    json_text = None
    for line in reversed(stdout.splitlines()):
        line = line.strip()
        if line.startswith("{"):
            json_text = line
            break
    if not json_text:
        return False, None, (stderr or stdout)[:2000]
    try:
        parsed = json.loads(json_text)
        return True, parsed, json_text
    except json.JSONDecodeError as e:
        return False, None, f"json-decode-error: {e}; raw={json_text[:500]}"


def extract_axes(parsed: dict[str, Any]) -> list[dict[str, Any]]:
    """Pull discriminative_axis blocks from trust-report JSON."""
    out = []
    for entry in parsed.get("entries", []):
        axis = entry.get("discriminative_axis")
        if axis is None:
            continue
        out.append({
            "fn_name": entry.get("name"),
            "axis": axis,
        })
    return out


def aggregate(per_fixture_axes: list[tuple[str, list[dict[str, Any]]]]) -> dict[str, Any]:
    """Compute aggregate stats + adjudication from per-fixture axes."""
    all_axes: list[dict[str, Any]] = []
    for fixture_id, axes in per_fixture_axes:
        for entry in axes:
            entry = dict(entry)
            entry["fixture_id"] = fixture_id
            all_axes.append(entry)

    # Deduplicate within the not-requested group: the same cross-module function
    # can appear under multiple fixtures (once as a cross-module import under the
    # entry file, again under a secondary-discovery fixture for that same module).
    # Collapsing by fn_name within this group prevents the denominator from being
    # inflated by redundant out-of-scope entries.  Measured entries (no
    # not-requested warning) are untouched — a fn_name shared between a measured
    # entry and a not-requested entry represents two distinct functions from
    # different modules, and both should count independently.
    _seen_nr: set[str | None] = set()
    deduped: list[dict[str, Any]] = []
    for e in all_axes:
        if "not-requested" in e["axis"].get("warnings", []):
            if e["fn_name"] in _seen_nr:
                continue
            _seen_nr.add(e["fn_name"])
        deduped.append(e)
    all_axes = deduped

    contracted_total = len(all_axes)
    scored = [e for e in all_axes if e["axis"].get("score") is not None]
    defined_count = len(scored)
    midrange = [e for e in scored if 0.0 < e["axis"]["score"] < 1.0]
    midrange_count = len(midrange)

    score_values = [e["axis"]["score"] for e in scored]
    score_stats: dict[str, float | None] = {
        "mean":   round(statistics.fmean(score_values), 6) if score_values else None,
        "median": round(statistics.median(score_values), 6) if score_values else None,
        "min":    min(score_values) if score_values else None,
        "max":    max(score_values) if score_values else None,
        "p10":    round(percentile(score_values, 10), 6) if score_values else None,
        "p50":    round(percentile(score_values, 50), 6) if score_values else None,
        "p90":    round(percentile(score_values, 90), 6) if score_values else None,
    }

    warning_counts: dict[str, int] = {}
    for e in all_axes:
        for w in e["axis"].get("warnings", []):
            warning_counts[w] = warning_counts.get(w, 0) + 1

    entropy_counts: dict[str, int] = {}
    for e in all_axes:
        ann = e["axis"].get("spec_entropy_annotation", "strict")
        entropy_counts[ann] = entropy_counts.get(ann, 0) + 1

    defined_fraction = (defined_count / contracted_total) if contracted_total else 0.0
    midrange_fraction = (midrange_count / defined_count) if defined_count else 0.0

    if contracted_total < 10:
        label = "cdp-corpus-inadequate"
    elif defined_fraction < 0.30:
        label = "cdp-null"
    elif defined_fraction >= 0.50 and midrange_fraction >= 0.25:
        label = "cdp-discriminating"
    elif defined_fraction >= 0.50:
        label = "cdp-discriminating-weak"
    else:
        # 0.30 <= defined_fraction < 0.50: partial signal, not null, not majority-defined
        label = "cdp-discriminating-weak"

    return {
        "contracted_fns_total":      contracted_total,
        "defined_scores":            defined_count,
        "defined_fraction":          round(defined_fraction, 6),
        "midrange_scores":           midrange_count,
        "midrange_fraction":         round(midrange_fraction, 6),
        "score_stats":               score_stats,
        "warning_counts":            dict(sorted(warning_counts.items())),
        "spec_entropy_annotation_counts": dict(sorted(entropy_counts.items())),
        "adjudication_label":        label,
    }


def percentile(xs: list[float], p: float) -> float:
    """Linear-interpolation percentile. xs must be non-empty."""
    if not xs:
        raise ValueError("percentile on empty list")
    sorted_xs = sorted(xs)
    if len(sorted_xs) == 1:
        return sorted_xs[0]
    k = (p / 100.0) * (len(sorted_xs) - 1)
    lo = int(k)
    hi = min(lo + 1, len(sorted_xs) - 1)
    frac = k - lo
    return sorted_xs[lo] * (1.0 - frac) + sorted_xs[hi] * frac


def write_summary_md(run_dir: Path, manifest: dict[str, Any], aggregate_data: dict[str, Any],
                     primary_results: list[dict[str, Any]],
                     secondary_results: list[dict[str, Any]],
                     excluded: list[dict[str, Any]]) -> None:
    label = aggregate_data["adjudication_label"]
    lines = [
        "# CDP-0 baseline run summary",
        "",
        f"- **Timestamp (UTC):** {run_dir.name.removesuffix('-baseline')}",
        f"- **Compiler SHA:** `{manifest['compiler_ref']['short_sha']}` "
            f"({manifest['compiler_ref']['branch']})",
        f"- **`llmll version`:** `{manifest['compiler_ref']['version_string']}`",
        f"- **CDP scope:** `{manifest['cdp_scope']}`",
        f"- **Adjudication:** `{label}`",
        "",
        "## Aggregate",
        "",
        f"- Contracted functions across corpus: **{aggregate_data['contracted_fns_total']}**",
        f"- Defined-score functions: **{aggregate_data['defined_scores']}** "
            f"({100 * aggregate_data['defined_fraction']:.1f}%)",
        f"- Midrange (0 < DP < 1) functions: **{aggregate_data['midrange_scores']}** "
            f"({100 * aggregate_data['midrange_fraction']:.1f}% of defined)",
    ]
    s = aggregate_data["score_stats"]
    if s["mean"] is not None:
        lines += [
            "",
            "### Score distribution (defined scores only)",
            "",
            f"- mean: **{s['mean']:.3f}**, median: **{s['median']:.3f}**",
            f"- min: {s['min']:.3f}, p10: {s['p10']:.3f}, p50: {s['p50']:.3f}, "
                f"p90: {s['p90']:.3f}, max: {s['max']:.3f}",
        ]
    lines += [
        "",
        "### Warning counts",
        "",
    ]
    for w, n in aggregate_data["warning_counts"].items():
        lines.append(f"- `{w}`: {n}")
    if not aggregate_data["warning_counts"]:
        lines.append("- (none)")

    lines += [
        "",
        "### spec-entropy annotation counts",
        "",
    ]
    for ann, n in aggregate_data["spec_entropy_annotation_counts"].items():
        lines.append(f"- `{ann}`: {n}")

    lines += ["", "## Primary corpus results", ""]
    for r in primary_results:
        if r["status"] == "ok":
            ax = r["axes"]
            lines.append(f"- **{r['id']}** ({r['path']}): {len(ax)} contracted fn(s)")
        else:
            lines.append(f"- **{r['id']}** ({r['path']}): EXCLUDED — {r['reason']}")

    if secondary_results:
        lines += ["", "## Secondary corpus results", ""]
        for r in secondary_results:
            if r["status"] == "ok":
                ax = r["axes"]
                lines.append(f"- **{r['id']}** ({r['path']}): {len(ax)} contracted fn(s)")
            else:
                lines.append(f"- **{r['id']}** ({r['path']}): EXCLUDED — {r['reason']}")

    if excluded:
        lines += ["", "## Excluded fixtures (verify-failure)", ""]
        for e in excluded:
            lines.append(f"- **{e['id']}** ({e['path']}): {e['reason']}")

    (run_dir / "summary.md").write_text("\n".join(lines) + "\n")


def run_one_fixture(fix: dict[str, str], run_dir: Path) -> dict[str, Any]:
    ok, parsed, raw = run_verify_cdp(fix["path"])
    if not ok or parsed is None:
        return {"status": "fail", "id": fix["id"], "path": fix["path"], "reason": raw[:500]}
    axes = extract_axes(parsed)
    per_fixture_path = run_dir / "per-fixture" / f"{fix['id']}.json"
    per_fixture_path.parent.mkdir(parents=True, exist_ok=True)
    per_fixture_path.write_text(json.dumps(parsed, indent=2))
    return {"status": "ok", "id": fix["id"], "path": fix["path"], "axes": axes}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--primary-only", action="store_true",
                        help="skip secondary corpus discovery")
    args = parser.parse_args()

    manifest = load_manifest()
    ts = utc_timestamp()
    run_dir = HARNESS_DIR / "runs" / f"{ts}-baseline"
    run_dir.mkdir(parents=True, exist_ok=True)

    primary = list(manifest["primary_corpus"])
    primary_paths = {f["path"] for f in primary}
    secondary = []
    if not args.primary_only:
        secondary = discover_secondary(manifest, primary_paths)

    print(f"[cdp-0] run dir: {run_dir.relative_to(REPO_ROOT)}", file=sys.stderr)
    print(f"[cdp-0] primary fixtures: {len(primary)}", file=sys.stderr)
    print(f"[cdp-0] secondary fixtures: {len(secondary)}", file=sys.stderr)

    primary_results = []
    for fix in primary:
        print(f"[cdp-0] primary {fix['id']}: {fix['path']}", file=sys.stderr)
        primary_results.append(run_one_fixture(fix, run_dir))

    secondary_results = []
    for fix in secondary:
        print(f"[cdp-0] secondary {fix['id']}: {fix['path']}", file=sys.stderr)
        secondary_results.append(run_one_fixture(fix, run_dir))

    excluded = [r for r in (primary_results + secondary_results) if r["status"] == "fail"]
    successful = [r for r in (primary_results + secondary_results) if r["status"] == "ok"]

    if not successful:
        die(3, "every fixture failed; no DP data collected")

    per_fixture_axes = [(r["id"], r["axes"]) for r in successful]
    aggregate_data = aggregate(per_fixture_axes)

    baseline = {
        "experiment": "cdp-0",
        "rev": manifest["rev"],
        "timestamp_utc": ts,
        "compiler_ref": manifest["compiler_ref"],
        "cdp_scope": manifest["cdp_scope"],
        "primary_corpus_size": len(primary),
        "secondary_corpus_size": len(secondary),
        "primary_results": [{"id": r["id"], "path": r["path"], "status": r["status"],
                             "n_contracted_fns": len(r.get("axes", [])),
                             "reason": r.get("reason", "")} for r in primary_results],
        "secondary_results": [{"id": r["id"], "path": r["path"], "status": r["status"],
                               "n_contracted_fns": len(r.get("axes", [])),
                               "reason": r.get("reason", "")} for r in secondary_results],
        "per_function_axes": [
            {
                "fixture_id": r["id"],
                "fn_name": ax["fn_name"],
                "axis": ax["axis"],
            }
            for r in successful
            for ax in r["axes"]
        ],
        "aggregate": aggregate_data,
    }

    (run_dir / "baseline.json").write_text(json.dumps(baseline, indent=2))
    write_summary_md(run_dir, manifest, aggregate_data,
                     primary_results, secondary_results, excluded)

    print(f"[cdp-0] aggregate: {aggregate_data['adjudication_label']} "
          f"({aggregate_data['defined_scores']}/{aggregate_data['contracted_fns_total']} "
          f"defined; midrange {aggregate_data['midrange_scores']})", file=sys.stderr)


if __name__ == "__main__":
    main()
