#!/usr/bin/env python3
"""INT-PRE harness — codegen-comparison wall-clock measurement for the int → Integer switch.

Consumes manifest.json; produces runs/<timestamp>/{raw,report}.json plus report.md.
Adjudicates the gate criterion (TOTP total-wall-clock regression ≥ 5× → escalate INT-3).

Pinned: docs/design/int-2-boundary-shims.md §3 (catalog SHA in manifest).

Usage: python3 scripts/int_pre_bench.py [manifest.json]

The harness is deterministic-compiler-measurement only; no model invocations, no API spend.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import platform
import re
import statistics
import subprocess
import sys
import time
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

HARNESS_VERSION = "1.0.0"
REPO_ROOT = Path(__file__).resolve().parent.parent.parent.parent  # experiments/int-pre/scripts/ → repo root
EXPERIMENT_DIR = REPO_ROOT / "experiments" / "int-pre"
WORKTREE_BASE = EXPERIMENT_DIR / ".worktrees"


# ──────────────────────────────────────────────────────────────────────────────
# Manifest + data shapes
# ──────────────────────────────────────────────────────────────────────────────

@dataclass
class Rep:
    rep_idx: int
    wall_ms: float
    exit_code: int
    stdout_sha256: str
    stderr_sha256: str


@dataclass
class CellResult:
    variant_label: str
    benchmark_id: str
    phase: str
    reps: list[Rep] = field(default_factory=list)
    median_ms: Optional[float] = None
    iqr_ms: Optional[float] = None
    min_ms: Optional[float] = None
    max_ms: Optional[float] = None
    n: int = 0
    notes: list[str] = field(default_factory=list)


@dataclass
class ProfiledResult:
    variant_label: str
    benchmark_id: str
    total_ms: float
    user_total_ms: float
    builtin_total_ms: float
    user_pct: float
    builtin_pct: float
    prof_path: str
    cost_centers: list[dict] = field(default_factory=list)


# ──────────────────────────────────────────────────────────────────────────────
# CPU governor + host metadata
# ──────────────────────────────────────────────────────────────────────────────

def check_cpu_governor(skip: bool) -> dict:
    """Best-effort: report current governor / power state. Refuse if not 'performance'
    (or equivalent) unless --no-governor-check is passed."""
    system = platform.system()
    state = {"system": system, "governor_pinned": False, "evidence": ""}
    if system == "Darwin":
        try:
            out = subprocess.run(["pmset", "-g"], capture_output=True, text=True, timeout=5).stdout
            state["evidence"] = out
            state["governor_pinned"] = "lowpowermode" not in out.lower() or "lowpowermode         0" in out.lower()
        except Exception as e:
            state["evidence"] = f"pmset failed: {e}"
    elif system == "Linux":
        gov_path = Path("/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor")
        if gov_path.exists():
            gov = gov_path.read_text().strip()
            state["evidence"] = f"scaling_governor={gov}"
            state["governor_pinned"] = gov == "performance"
        else:
            state["evidence"] = "no cpufreq sysfs entry"
    if not state["governor_pinned"] and not skip:
        sys.stderr.write(
            f"\nCPU governor not pinned to performance:\n  {state['evidence']}\n"
            f"  Mac: turn off Low Power Mode in System Settings → Battery.\n"
            f"  Linux: sudo cpupower frequency-set -g performance\n"
            f"  Override: re-run with --no-governor-check (measurements may be noisier).\n\n"
        )
        sys.exit(2)
    return state


def capture_host_metadata(commands: list[str]) -> dict:
    meta = {}
    for cmd in commands:
        try:
            out = subprocess.run(cmd.split(), capture_output=True, text=True, timeout=5)
            meta[cmd] = (out.stdout + out.stderr).strip()
        except Exception as e:
            meta[cmd] = f"<failed: {e}>"
    meta["python_version"] = sys.version.split()[0]
    meta["harness_version"] = HARNESS_VERSION
    meta["harness_sha"] = git_head_sha(REPO_ROOT)
    return meta


def git_head_sha(repo: Path) -> str:
    try:
        return subprocess.run(
            ["git", "rev-parse", "HEAD"], cwd=repo, capture_output=True, text=True, timeout=5
        ).stdout.strip()
    except Exception:
        return "<unknown>"


# ──────────────────────────────────────────────────────────────────────────────
# Worktree + build management
# ──────────────────────────────────────────────────────────────────────────────

def ensure_worktree(variant: dict) -> Path:
    """Materialize the variant's compiler at a git worktree. Idempotent."""
    label = variant["label"]
    sha = variant["compiler_ref"]
    wt = WORKTREE_BASE / label
    if wt.exists():
        head = subprocess.run(
            ["git", "rev-parse", "HEAD"], cwd=wt, capture_output=True, text=True
        ).stdout.strip()
        if head.startswith(sha):
            return wt
        sys.stderr.write(f"worktree {wt} exists but HEAD={head} != {sha}; removing and re-adding\n")
        subprocess.run(["git", "worktree", "remove", "--force", str(wt)], cwd=REPO_ROOT)
    WORKTREE_BASE.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["git", "worktree", "add", "--detach", str(wt), sha], cwd=REPO_ROOT, check=True
    )
    return wt


def ensure_built(worktree: Path, profiled: bool = False) -> Path:
    """Run stack build in the worktree's compiler/ subdir; return path to llmll binary."""
    compiler_dir = worktree / "compiler"
    build_args = ["stack", "build", "llmll"]
    if profiled:
        build_args.append("--profile")
    sys.stderr.write(f"  building {'profiled ' if profiled else ''}llmll in {worktree.name}...\n")
    res = subprocess.run(build_args, cwd=compiler_dir, capture_output=True, text=True, timeout=900)
    if res.returncode != 0:
        sys.stderr.write(f"BUILD FAILED in {worktree.name}:\n{res.stderr[-2000:]}\n")
        raise RuntimeError(f"stack build failed for variant at {worktree}")
    path_res = subprocess.run(
        ["stack", "exec", "which", "--", "llmll"], cwd=compiler_dir, capture_output=True, text=True
    )
    binary = Path(path_res.stdout.strip())
    if not binary.exists():
        raise RuntimeError(f"llmll binary not found after build: {binary}")
    return binary


# ──────────────────────────────────────────────────────────────────────────────
# Phase execution
# ──────────────────────────────────────────────────────────────────────────────

PHASE_COMMANDS = {
    "verify_spec_coverage": (["verify"], ["--spec-coverage", "--json"]),
    "verify_trust_report":  (["verify"], ["--trust-report", "--json"]),
    "build":  (["build"], ["--emit-only"]),
    "test":   (["test"], []),  # no --emit-only: we want the full run-time measurement
}


def hash_bytes(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def time_one_invocation(binary: Path, args: list[str], cwd: Path) -> Rep:
    t0 = time.perf_counter()
    proc = subprocess.run(
        [str(binary), *args], cwd=cwd, capture_output=True, timeout=300
    )
    t1 = time.perf_counter()
    return Rep(
        rep_idx=-1,  # set by caller
        wall_ms=(t1 - t0) * 1000.0,
        exit_code=proc.returncode,
        stdout_sha256=hash_bytes(proc.stdout),
        stderr_sha256=hash_bytes(proc.stderr),
    )


def run_phase(
    binary: Path,
    benchmark: dict,
    phase: str,
    warmup_reps: int,
    measured_reps: int,
    cwd: Path,
) -> list[CellResult]:
    """Execute warmups (discarded) + measured reps. `phase` is one of the high-level phases
    in the manifest; expand_phase splits it (e.g., 'verify' → spec-coverage + trust-report
    sub-cells). Returns one CellResult per sub-phase. Variant label is set by the caller.
    A warmup failure halts that sub-cell with a note; other sub-cells continue."""
    results: list[CellResult] = []
    for sub_phase in expand_phase(phase):
        subcmd, suffix = PHASE_COMMANDS[sub_phase]
        bench_path = REPO_ROOT / benchmark["path"]
        args = [*subcmd, str(bench_path), *suffix]
        cell = CellResult(
            variant_label="",
            benchmark_id=benchmark["id"],
            phase=sub_phase,
        )
        warmup_failed = False
        for w in range(warmup_reps):
            rep = time_one_invocation(binary, args, cwd)
            if rep.exit_code != 0:
                cell.notes.append(f"warmup rep {w} exited {rep.exit_code}; halt cell")
                warmup_failed = True
                break
        if warmup_failed:
            results.append(cell)
            continue
        for r in range(measured_reps):
            rep = time_one_invocation(binary, args, cwd)
            rep.rep_idx = r
            cell.reps.append(rep)
        cell.n = len(cell.reps)
        if cell.n > 0:
            walls = sorted(r.wall_ms for r in cell.reps)
            cell.median_ms = statistics.median(walls)
            cell.min_ms = walls[0]
            cell.max_ms = walls[-1]
            if cell.n >= 4:
                q1 = statistics.median(walls[: cell.n // 2])
                q3 = statistics.median(walls[(cell.n + 1) // 2:])
                cell.iqr_ms = q3 - q1
        results.append(cell)
    return results


def expand_phase(phase: str) -> list[str]:
    if phase == "verify":
        return ["verify_spec_coverage", "verify_trust_report"]
    if phase == "build":
        return ["build"]
    if phase == "test":
        return ["test"]
    if phase == "test-profiled":
        return []  # handled separately
    raise ValueError(f"unknown phase: {phase}")


# ──────────────────────────────────────────────────────────────────────────────
# Profiled run (TOTP only, F2 user-only decomposition)
# ──────────────────────────────────────────────────────────────────────────────

PROF_LINE_RE = re.compile(r"^\s*(\S+)\s+(\S+)\s+\S+\s+([\d.]+)\s+([\d.]+)\s*$")


def parse_prof_file(prof_path: Path, builtin_patterns: list[str]) -> tuple[float, float, list[dict]]:
    """Parse a GHC .prof file's COST CENTRE table. Returns (user_pct, builtin_pct, centers).
    Sum residual (MAIN, GC, etc.) is absorbed into user-side per manifest classification notes."""
    if not prof_path.exists():
        return 0.0, 0.0, []
    in_table = False
    user_pct = 0.0
    builtin_pct = 0.0
    centers: list[dict] = []
    for line in prof_path.read_text(errors="replace").splitlines():
        if "COST CENTRE" in line and "MODULE" in line:
            in_table = True
            continue
        if not in_table or not line.strip():
            continue
        m = PROF_LINE_RE.match(line)
        if not m:
            continue
        cc_name, module, time_pct = m.group(1), m.group(2), float(m.group(3))
        is_builtin = any(pat in cc_name for pat in builtin_patterns)
        centers.append({"name": cc_name, "module": module, "time_pct": time_pct, "is_builtin": is_builtin})
        if is_builtin:
            builtin_pct += time_pct
        else:
            user_pct += time_pct
    return user_pct, builtin_pct, centers


def run_profiled(
    variant: dict,
    benchmark: dict,
    binary_profiled: Path,
    reps: int,
    builtin_patterns: list[str],
    cwd: Path,
) -> list[ProfiledResult]:
    """TOTP-only. Run llmll test with +RTS -p -RTS, parse the .prof file, aggregate.
    The .prof file is emitted in cwd by GHC's profiling runtime."""
    bench_path = REPO_ROOT / benchmark["path"]
    results: list[ProfiledResult] = []
    for r in range(reps):
        prof_target = cwd / "llmll.prof"
        if prof_target.exists():
            prof_target.unlink()
        t0 = time.perf_counter()
        proc = subprocess.run(
            [str(binary_profiled), "test", str(bench_path), "+RTS", "-p", "-RTS"],
            cwd=cwd, capture_output=True, timeout=600,
        )
        t1 = time.perf_counter()
        total_ms = (t1 - t0) * 1000.0
        if proc.returncode != 0:
            sys.stderr.write(f"  profiled rep {r}: exit {proc.returncode}; skipping\n")
            continue
        user_pct, builtin_pct, centers = parse_prof_file(prof_target, builtin_patterns)
        results.append(ProfiledResult(
            variant_label=variant["label"],
            benchmark_id=benchmark["id"],
            total_ms=total_ms,
            user_total_ms=total_ms * user_pct / 100.0,
            builtin_total_ms=total_ms * builtin_pct / 100.0,
            user_pct=user_pct,
            builtin_pct=builtin_pct,
            prof_path=str(prof_target),
            cost_centers=centers,
        ))
    return results


# ──────────────────────────────────────────────────────────────────────────────
# Aggregation + adjudication
# ──────────────────────────────────────────────────────────────────────────────

def aggregate(
    cells_by_variant: dict[str, list[CellResult]],
    profiled_by_variant: dict[str, list[ProfiledResult]],
) -> dict:
    """Build the report.json structure. Cross-variant regression factors per (benchmark, phase)."""
    variants = list(cells_by_variant.keys())
    by_bench: dict[str, dict] = {}
    for vlabel, cells in cells_by_variant.items():
        for cell in cells:
            b = by_bench.setdefault(cell.benchmark_id, {})
            p = b.setdefault(cell.phase, {"variants": {}})
            p["variants"][vlabel] = {
                "median_ms": cell.median_ms,
                "iqr_ms": cell.iqr_ms,
                "min_ms": cell.min_ms,
                "max_ms": cell.max_ms,
                "n": cell.n,
                "notes": cell.notes,
            }
    # Regression factors (B median / A median) per (benchmark, phase).
    if len(variants) == 2:
        a, b = "variant-a-baseline", "variant-b-prototype"
        for _bench_id, phases in by_bench.items():
            for _phase, p in phases.items():
                va = p["variants"].get(a, {}).get("median_ms")
                vb = p["variants"].get(b, {}).get("median_ms")
                if va and vb and va > 0:
                    p["regression_factor"] = vb / va
    # Profiled aggregation (TOTP user-only ratio).
    profiled_summary = {}
    for vlabel, runs in profiled_by_variant.items():
        if not runs:
            continue
        user_medians = statistics.median(r.user_total_ms for r in runs)
        total_medians = statistics.median(r.total_ms for r in runs)
        profiled_summary[vlabel] = {
            "user_total_ms_median": user_medians,
            "total_ms_median": total_medians,
            "n": len(runs),
            "user_pct_median": statistics.median(r.user_pct for r in runs),
            "builtin_pct_median": statistics.median(r.builtin_pct for r in runs),
        }
    user_only_ratio = None
    if "variant-a-baseline" in profiled_summary and "variant-b-prototype" in profiled_summary:
        ua = profiled_summary["variant-a-baseline"]["user_total_ms_median"]
        ub = profiled_summary["variant-b-prototype"]["user_total_ms_median"]
        if ua and ua > 0:
            user_only_ratio = ub / ua
    return {
        "benchmarks": by_bench,
        "profiled": profiled_summary,
        "totp_user_only_ratio": user_only_ratio,
    }


def assert_control_predictions(
    cells_by_variant: dict[str, list[CellResult]], manifest: dict
) -> list[dict]:
    """Check byte-identity assertions across variants."""
    if len(cells_by_variant) != 2:
        return [{"name": "control", "holds": None, "evidence": "skipped — not a two-variant run"}]
    a, b = cells_by_variant["variant-a-baseline"], cells_by_variant["variant-b-prototype"]
    by_a = {(c.benchmark_id, c.phase): c for c in a}
    by_b = {(c.benchmark_id, c.phase): c for c in b}
    results = []
    for assertion in manifest.get("control_assertions", []):
        phase_key = {
            "verify_spec_coverage_byte_identity": "verify_spec_coverage",
            "verify_trust_report_byte_identity":  "verify_trust_report",
        }.get(assertion["name"])
        if not phase_key:
            results.append({"name": assertion["name"], "holds": None, "evidence": "no mapping"})
            continue
        holds = True
        evidence = []
        for (bench_id, phase), ca in by_a.items():
            if phase != phase_key:
                continue
            cb = by_b.get((bench_id, phase))
            if not cb or not ca.reps or not cb.reps:
                continue
            # Compare first-rep stdout hashes (all reps of one variant should be identical anyway).
            ha = ca.reps[0].stdout_sha256
            hb = cb.reps[0].stdout_sha256
            if ha != hb:
                holds = False
                evidence.append(f"{bench_id}: A={ha[:12]} B={hb[:12]}")
        results.append({"name": assertion["name"], "holds": holds, "evidence": evidence})
    return results


def adjudicate(report: dict, manifest: dict, controls: list[dict]) -> str:
    """Apply the gate criteria. Return one of the named adjudications."""
    for c in controls:
        if c["holds"] is False:
            return "halted-control-prediction-violation"
    # Variant B build failure → no variant-b numbers; halt.
    if "totp" not in report["benchmarks"] or "test" not in report["benchmarks"]["totp"]:
        return "halted-variant-b-build-failure"
    totp_test = report["benchmarks"]["totp"]["test"]
    rf = totp_test.get("regression_factor")
    if rf is None:
        return "halted-variant-b-build-failure"
    # Noise check on totp test phase.
    iqr = totp_test["variants"].get("variant-b-prototype", {}).get("iqr_ms", 0) or 0
    median = totp_test["variants"].get("variant-b-prototype", {}).get("median_ms", 0) or 0
    if median > 0 and iqr / median > 0.5:
        return "null-result-noisy"
    primary_threshold = manifest["gate"]["primary"]["threshold"]
    secondary_threshold = manifest["gate"]["secondary"]["threshold"]
    user_only = report.get("totp_user_only_ratio")
    if rf >= primary_threshold:
        return "int-3-escalate-total"
    if user_only is not None and user_only >= secondary_threshold:
        return "int-3-warning-user-only"
    return "int-2-clear"


# ──────────────────────────────────────────────────────────────────────────────
# Output writers
# ──────────────────────────────────────────────────────────────────────────────

def write_json(obj: dict, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(obj, indent=2, default=str) + "\n")


def write_markdown_summary(report: dict, controls: list[dict], adjudication: str, manifest: dict, outdir: Path) -> None:
    md = ["# INT-PRE report — " + outdir.name, ""]
    md.append(f"**Adjudication:** `{adjudication}`")
    md.append(f"**Catalog:** `{manifest['catalog_ref']['doc']}` @ `{manifest['catalog_ref']['sha']}`")
    md.append("")
    md.append("## Per-benchmark regression factors (Variant B median / Variant A median)")
    md.append("")
    md.append("| benchmark | phase | A median (ms) | B median (ms) | factor | A IQR | B IQR | n |")
    md.append("|---|---|---|---|---|---|---|---|")
    for bench_id, phases in report["benchmarks"].items():
        for phase, p in phases.items():
            va = p["variants"].get("variant-a-baseline", {})
            vb = p["variants"].get("variant-b-prototype", {})
            rf = p.get("regression_factor")
            md.append("| {b} | {p} | {am} | {bm} | {f} | {ai} | {bi} | {n} |".format(
                b=bench_id, p=phase,
                am=fmt(va.get("median_ms")), bm=fmt(vb.get("median_ms")),
                f=fmt(rf, 3), ai=fmt(va.get("iqr_ms")), bi=fmt(vb.get("iqr_ms")),
                n=vb.get("n", "—"),
            ))
    md.append("")
    if report.get("totp_user_only_ratio") is not None:
        md.append("## F2 decomposition — TOTP user-only ratio")
        md.append("")
        md.append(f"**TOTP total wall-clock ratio:** {fmt(report['benchmarks']['totp']['test'].get('regression_factor'), 3)}")
        md.append(f"**TOTP user-only ratio:** {fmt(report['totp_user_only_ratio'], 3)}")
        md.append("")
        md.append("| variant | user_total_ms | total_ms | user_pct | builtin_pct | n |")
        md.append("|---|---|---|---|---|---|")
        for v, s in report.get("profiled", {}).items():
            md.append("| {v} | {ut} | {t} | {up}% | {bp}% | {n} |".format(
                v=v, ut=fmt(s["user_total_ms_median"]), t=fmt(s["total_ms_median"]),
                up=fmt(s["user_pct_median"]), bp=fmt(s["builtin_pct_median"]), n=s["n"],
            ))
    md.append("")
    md.append("## Control assertions")
    md.append("")
    for c in controls:
        md.append(f"- **{c['name']}**: holds={c['holds']}; evidence={c['evidence']}")
    md.append("")
    md.append(f"## Gate criterion")
    md.append("")
    md.append(f"- Primary: {manifest['gate']['primary']['metric']} ≥ {manifest['gate']['primary']['threshold']} → {manifest['gate']['primary']['action_if_exceeded']}")
    md.append(f"- Secondary: {manifest['gate']['secondary']['metric']} ≥ {manifest['gate']['secondary']['threshold']} → {manifest['gate']['secondary']['action_if_exceeded']}")
    md.append("")
    (outdir / "report.md").write_text("\n".join(md))


def fmt(v, prec=2):
    if v is None:
        return "—"
    try:
        return f"{v:.{prec}f}"
    except Exception:
        return str(v)


# ──────────────────────────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────────────────────────

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("manifest", nargs="?", default=str(EXPERIMENT_DIR / "manifest.json"))
    parser.add_argument("--no-governor-check", action="store_true",
                        help="Skip CPU governor pinning enforcement (measurements may be noisier)")
    parser.add_argument("--skip-profiled", action="store_true",
                        help="Skip the F2 profiled re-runs (gate adjudicates on total ratio only)")
    args = parser.parse_args()

    manifest = json.loads(Path(args.manifest).read_text())
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    outdir = EXPERIMENT_DIR / "runs" / timestamp
    outdir.mkdir(parents=True, exist_ok=True)
    sys.stderr.write(f"INT-PRE harness {HARNESS_VERSION}\n")
    sys.stderr.write(f"Output: {outdir.relative_to(REPO_ROOT)}\n\n")

    host_state = check_cpu_governor(args.no_governor_check)
    host_meta = capture_host_metadata(manifest["system_pins"]["host_metadata_capture"])

    cells_by_variant: dict[str, list[CellResult]] = {}
    profiled_by_variant: dict[str, list[ProfiledResult]] = {}
    halted = None

    for variant in manifest["variants"]:
        label = variant["label"]
        sys.stderr.write(f"=== {label} ({variant['compiler_ref']}) ===\n")
        try:
            wt = ensure_worktree(variant)
            binary = ensure_built(wt, profiled=False)
        except Exception as e:
            halted = f"halted-variant-build-failure: {label}: {e}"
            sys.stderr.write(f"  HALT: {halted}\n")
            break
        cells: list[CellResult] = []
        for bench in manifest["benchmarks"]:
            for phase in bench["phases"]:
                if phase == "test-profiled":
                    continue
                sys.stderr.write(f"  {bench['id']}/{phase}...\n")
                sub_cells = run_phase(
                    binary, bench, phase,
                    manifest["rep_config"]["warmup_reps"],
                    manifest["rep_config"]["measured_reps"],
                    cwd=wt / "compiler",
                )
                for cell in sub_cells:
                    cell.variant_label = label
                    cells.append(cell)
        cells_by_variant[label] = cells

        # Profiled (TOTP-only).
        if not args.skip_profiled and any("test-profiled" in b["phases"] for b in manifest["benchmarks"]):
            sys.stderr.write(f"  building profiled llmll...\n")
            try:
                binary_prof = ensure_built(wt, profiled=True)
            except Exception as e:
                sys.stderr.write(f"  profiled build failed: {e}; skipping profiled phase for {label}\n")
            else:
                for bench in manifest["benchmarks"]:
                    if "test-profiled" not in bench["phases"]:
                        continue
                    sys.stderr.write(f"  {bench['id']}/test-profiled...\n")
                    runs = run_profiled(
                        variant, bench, binary_prof,
                        manifest["rep_config"]["profiled_reps"],
                        manifest["cost_center_classification"]["builtin_patterns"],
                        cwd=wt / "compiler",
                    )
                    profiled_by_variant.setdefault(label, []).extend(runs)

    # Write raw.json regardless of halt state.
    raw = {
        "harness_version": HARNESS_VERSION,
        "timestamp": timestamp,
        "manifest": manifest,
        "host_state": host_state,
        "host_meta": host_meta,
        "cells": {
            v: [{**asdict(c), "reps": [asdict(r) for r in c.reps]} for c in cs]
            for v, cs in cells_by_variant.items()
        },
        "profiled": {v: [asdict(p) for p in ps] for v, ps in profiled_by_variant.items()},
        "halted": halted,
    }
    write_json(raw, outdir / "raw.json")
    sys.stderr.write(f"  wrote {outdir / 'raw.json'}\n")

    if halted:
        write_json({"adjudication": halted, "manifest_ref": str(args.manifest)}, outdir / "report.json")
        sys.stderr.write(f"\nADJUDICATION: {halted}\n")
        return 1

    report = aggregate(cells_by_variant, profiled_by_variant)
    controls = assert_control_predictions(cells_by_variant, manifest)
    adjudication = adjudicate(report, manifest, controls)
    report["adjudication"] = adjudication
    report["controls"] = controls
    report["timestamp"] = timestamp
    report["manifest_catalog_sha"] = manifest["catalog_ref"]["sha"]
    write_json(report, outdir / "report.json")
    write_markdown_summary(report, controls, adjudication, manifest, outdir)
    sys.stderr.write(f"\nADJUDICATION: {adjudication}\n")
    return 0 if adjudication in ("int-2-clear", "int-3-warning-user-only") else 1


if __name__ == "__main__":
    sys.exit(main())
