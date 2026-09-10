#!/usr/bin/env python3
"""FALLBACK-CENSUS-1 — the tree-wide body-faithful ratio, per run.

The ratio decides whether `RESP-FACT-1` scales faster than the `wasi.*`
alphabet grows, and before this script it appeared in no committed file. It had
been counted by hand three times, and the first two readings were wrong in the
same direction: the first histogram's "252 body-outside-fragment" was 245
unfilled scaffolds plus 7 real bodies, because an unfilled hole was refused
under the same label as a written body that leaves the fragment. The compiler
now labels those separately (`unfilled-hole`, `no-post`), and this script is
what turns the labels into a number a later run can diff.

WHAT IT MEASURES

  ratio = functions reaching body-faithful / functions with a post

A function with no post has no proof goal, and an unfilled hole has nothing
written to prove. Neither is a fallback in the sense the ratio asks about, so
both leave the denominator and are counted beside it. That rule is the reason
the compiler carries two label-only causes: without them this script would have
to guess, and guessing is what the three hand counts did.

WHAT IT RUNS

One `llmll --json verify --strict-verified-core FILE` per file, from the file's
own directory, over a COPY of the tree. The copy is not a convenience: `llmll
verify` writes a `.verified.json` sidecar beside every file it reads, and this
script must not modify the tree it measures.

THE RATCHET

`scripts/fallback-census/BASELINE.json` records the set of files that pass
`--strict-verified-core`. The set may grow freely. It may not shrink unless the
baseline names a waiver for the file, with a reason. A file that stops passing,
or that is deleted while passing, fails this gate.

IT NEVER SKIPS. A missing solver, a missing baseline and an unreadable file are
each a non-zero exit with a message. A gate that skips silently reports success
for a measurement it did not make.

USAGE

    python3 scripts/fallback_census.py --llmll /path/to/llmll --repo .
    python3 scripts/fallback_census.py --llmll "stack exec llmll --" \\
        --out census.json --write-baseline
"""
from __future__ import annotations

import argparse
import json
import os
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

GATE = "fallback-census"

# The roots the CI gates build or verify. `scripts/check-examples.sh` caps its
# own walk at -maxdepth 3; that cap is NOT adopted here, because it drops the
# generated scaffold trees the hole bucket exists to separate.
ROOTS = ("examples", "tools", "scripts/build-smoke")
SUFFIXES = (".llmll", ".ast.json")

# The causes that leave the ratio's denominator: neither names a body that left
# the fragment.
NON_DENOMINATOR_CAUSES = frozenset({"unfilled-hole", "no-post"})

# The compiler's closed vocabulary (FixpointEmit.hs `FallbackCause`). Listed so
# a new cause shows up as an unknown bucket instead of being folded silently.
KNOWN_CAUSES = (
    "contract-post-outside-fragment",
    "contract-pre-outside-fragment",
    "contract-signature-outside-fragment",
    "body-outside-fragment",
    "path-cap-exceeded",
    "mixed-map-tail",
    "unfilled-hole",
    "no-post",
)

# Outcomes worth confirming alone before they are believed: each depends on the
# solver's answer, and the solver is the part of the run that has been seen to
# disagree with itself under load.
RECHECK_OUTCOMES = frozenset({"refuted", "timeout", "run-failed"})

EXIT_OK = 0
EXIT_FAIL = 1
EXIT_SETUP = 2


def tracked(repo: Path) -> list[Path]:
    """Every TRACKED file under the roots, repo-relative and sorted.

    Enumerating from git rather than from the filesystem is what keeps
    `tools/llmll-driver/generated` (107 MB of `llmll build` output, gitignored)
    out of both the population and the copy.
    """
    try:
        proc = subprocess.run(
            ["git", "ls-files", "-z", "--"] + list(ROOTS),
            cwd=str(repo), capture_output=True, text=True, check=True,
        )
    except (OSError, subprocess.CalledProcessError) as exc:
        raise SystemExit(
            f"{GATE}: cannot list the tracked tree in {repo}: {exc}; "
            "the census measures the committed tree and needs git"
        )
    names = [n for n in proc.stdout.split("\0") if n]
    return sorted((Path(n) for n in names), key=str)


def population(files: list[Path]) -> list[Path]:
    """The subset the census verifies: LLMLL sources, never sidecars."""
    return [
        p for p in files
        if not p.name.endswith(".verified.json")
        and any(p.name.endswith(sfx) for sfx in SUFFIXES)
    ]


def run_one(llmll: list[str], workdir: Path, rel: Path, timeout: int) -> dict:
    """Verify one file and classify the run. Never raises on a compiler failure."""
    target = workdir / rel
    started = time.monotonic()
    # Every run must see the same tree, whatever ran before it and whatever is
    # running beside it. `llmll verify` writes a sidecar next to the file, and a
    # sidecar left behind changes what a later run reads. So a sidecar this run
    # creates is removed again; one that came from the repository stays.
    sidecar = target.with_name(target.name + ".verified.json")
    sidecar_existed = sidecar.exists()
    try:
        proc = subprocess.run(
            llmll + ["--json", "verify", "--strict-verified-core", target.name],
            cwd=str(target.parent),
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        return {"outcome": "timeout", "detail": f"exceeded {timeout}s"}
    except OSError as exc:
        return {"outcome": "run-failed", "detail": str(exc)}
    finally:
        if not sidecar_existed and sidecar.exists():
            sidecar.unlink()

    if proc.returncode == 3:
        return {"outcome": "solver-missing", "detail": proc.stdout.strip()[:200]}

    payload = None
    for line in proc.stdout.splitlines():
        line = line.strip()
        if line.startswith("{") and line.endswith("}"):
            try:
                payload = json.loads(line)
            except json.JSONDecodeError:
                continue
    if payload is None:
        # Prefer the error line: a `check` failure prints its warnings first, and
        # reporting a warning as the cause sends a reader to the wrong place.
        lines = [ln.strip() for ln in (proc.stdout + proc.stderr).splitlines() if ln.strip()]
        errs = [ln for ln in lines if ln.startswith("error:")]
        detail = (errs or lines or [f"exit {proc.returncode}, no output"])[0]
        return {"outcome": "check-failed", "detail": detail[:200]}

    faithful = list(payload.get("body_faithful") or [])
    causes = dict(payload.get("body_fallback_causes") or {})
    constructs = dict(payload.get("body_fallback_constructs") or {})
    kinds = dict(payload.get("fn_kinds") or {})

    elapsed = round(time.monotonic() - started, 1)
    if "strict_errors" in payload:
        # Refused before the solver ran. Three readings, and only the third is
        # about the fragment's width: a file whose every refusal is an unfilled
        # hole is a SCAFFOLD, a file whose every refusal has no proof goal is
        # NO-GOAL, and anything else is a genuine FALLBACK. Folding the first two
        # into the third is what made the earlier hand counts overstate the
        # fallback population.
        cause_set = set(causes.values())
        if cause_set and cause_set <= {"unfilled-hole"}:
            outcome = "scaffold"
        elif cause_set and cause_set <= NON_DENOMINATOR_CAUSES:
            outcome = "no-goal"
        else:
            outcome = "fallback"
    elif payload.get("success") is False:
        outcome = "refuted"
    else:
        outcome = "pass"

    return {
        "outcome": outcome,
        "body_faithful": faithful,
        "causes": causes,
        "constructs": constructs,
        "kinds": kinds,
        # Reported in the log and the step summary, never written to the record:
        # a duration varies between runs, and the record has to stay byte-stable
        # so a diff shows only what actually changed.
        "seconds": elapsed,
    }


def aggregate(files: dict[str, dict]) -> dict:
    """Fold the per-file runs into the census record."""
    outcomes: dict[str, int] = {}
    causes: dict[str, int] = {}
    constructs: dict[str, int] = {}
    kinds: dict[str, dict[str, int]] = {}
    faithful_n = 0
    excluded_n = 0
    fallback_n = 0

    for rec in files.values():
        outcomes[rec["outcome"]] = outcomes.get(rec["outcome"], 0) + 1
        kmap = rec.get("kinds") or {}
        for fn in rec.get("body_faithful") or []:
            faithful_n += 1
            kind = kmap.get(fn, "unknown")
            kinds.setdefault(kind, {"faithful": 0, "fallback": 0, "excluded": 0})
            kinds[kind]["faithful"] += 1
        for fn, cause in (rec.get("causes") or {}).items():
            causes[cause] = causes.get(cause, 0) + 1
            kind = kmap.get(fn, "unknown")
            kinds.setdefault(kind, {"faithful": 0, "fallback": 0, "excluded": 0})
            if cause in NON_DENOMINATOR_CAUSES:
                excluded_n += 1
                kinds[kind]["excluded"] += 1
            else:
                fallback_n += 1
                kinds[kind]["fallback"] += 1
        for fn, cons in (rec.get("constructs") or {}).items():
            for label in cons:
                constructs[label] = constructs.get(label, 0) + 1

    denominator = faithful_n + fallback_n
    ratio = (faithful_n / denominator) if denominator else 0.0
    unknown = sorted(c for c in causes if c not in KNOWN_CAUSES)
    return {
        "outcomes": dict(sorted(outcomes.items())),
        "ratio": {
            "body_faithful": faithful_n,
            "fallback": fallback_n,
            "denominator": denominator,
            "value": round(ratio, 4),
            "excluded_no_goal": excluded_n,
        },
        "causes": dict(sorted(causes.items())),
        "constructs": dict(sorted(constructs.items())),
        "kinds": dict(sorted(kinds.items())),
        "unknown_causes": unknown,
    }


def render_summary(record: dict) -> str:
    r = record["ratio"]
    lines = [
        "### FALLBACK-CENSUS-1",
        "",
        f"Body-faithful ratio **{r['value']:.3f}** "
        f"({r['body_faithful']} of {r['denominator']} functions with a post). "
        f"{r['excluded_no_goal']} functions carry no proof goal and are excluded.",
        "",
        "| Fallback cause | Functions |",
        "|---|---:|",
    ]
    for cause, n in sorted(record["causes"].items(), key=lambda kv: (-kv[1], kv[0])):
        lines.append(f"| `{cause}` | {n} |")
    if record["constructs"]:
        lines += ["", "| Refusing construct | Clauses |", "|---|---:|"]
        for label, n in sorted(record["constructs"].items(), key=lambda kv: (-kv[1], kv[0])):
            lines.append(f"| `{label}` | {n} |")
    lines += ["", "| File outcome | Files |", "|---|---:|"]
    for outcome, n in sorted(record["outcomes"].items(), key=lambda kv: (-kv[1], kv[0])):
        lines.append(f"| {outcome} | {n} |")
    return "\n".join(lines) + "\n"


def check_ratchet(record: dict, baseline: dict) -> tuple[list[str], list[str]]:
    """The strict-pass set may grow, never shrink without a named waiver.

    Returns (failures, notes). A file that lost its pass because its verdict is
    unstable is a note, not a failure: the gate reports the instability and does
    not convert a flaky verdict into a red build.
    """
    now = set(record["strict_pass"])
    was = set(baseline.get("strict_pass") or [])
    waivers = baseline.get("waivers") or {}
    failures, notes = [], []
    for path in sorted(was - now):
        reason = waivers.get(path)
        if isinstance(reason, str) and reason.strip():
            continue
        if record["files"].get(path, {}).get("outcome") == "unstable":
            notes.append(
                f"{GATE}: {path} is in the baseline's strict-pass set and did not pass this run, "
                "because its verdict is unstable; not counted as a regression"
            )
            continue
        failures.append(
            f"{GATE}: {path} passed --strict-verified-core at the baseline and does not now; "
            "name the cause in the baseline's waivers, or restore the file"
        )
    return failures, notes


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="FALLBACK-CENSUS-1 body-faithful census and ratchet")
    ap.add_argument("--llmll", required=True, help="the compiler under test; split with shlex")
    ap.add_argument("--repo", default=".", help="repository root (default: .)")
    ap.add_argument("--baseline", default=None, help="ratchet file (default: scripts/fallback-census/BASELINE.json)")
    ap.add_argument("--out", default=None, help="write the full census record here")
    ap.add_argument("--write-baseline", action="store_true", help="rewrite the ratchet file from this run")
    ap.add_argument("--no-ratchet", action="store_true", help="report the census, do not enforce the ratchet")
    # 600 s and not 300: measured 2026-09-08, examples/heartbleed/secure-channel/
    # sc-channel.llmll exceeded 300 s under four concurrent workers. Each such
    # timeout costs the budget twice, once waiting and once in the confirmation
    # run, which is what took one census to 10 min 41 s.
    #
    # The isolated figure this comment used to cite, 130 s ALONE, DOES NOT
    # REPRODUCE. Five isolated samples on 2026-09-09 at v0.23.0 cluster near
    # 60 s, and neither --json, nor the repository sidecar, nor either cache
    # explains the gap; see item 2 of
    # docs/design/fallback-census-1-implementation-plan.md. 600 s STAYS: it is
    # generous against either figure, and the number that justifies it is the
    # 300 s overrun under four workers, not the isolated one.
    ap.add_argument("--timeout", type=int, default=600, help="per-file seconds (default: 600)")
    ap.add_argument("--jobs", type=int, default=min(8, (os.cpu_count() or 2)),
                    help="directories verified concurrently (default: min(8, cpu count))")
    ap.add_argument("--summary", default=None, help="append a markdown table here (default: $GITHUB_STEP_SUMMARY)")
    args = ap.parse_args(argv)

    repo = Path(args.repo).resolve()
    if not (repo / "LLMLL.md").is_file():
        print(f"{GATE}: {repo} does not look like the repository root (no LLMLL.md)")
        return EXIT_SETUP

    llmll = shlex.split(args.llmll)
    baseline_path = Path(args.baseline) if args.baseline else repo / "scripts" / "fallback-census" / "BASELINE.json"

    all_files = tracked(repo)
    files = population(all_files)
    if not files:
        print(f"{GATE}: the population is empty; the roots are {', '.join(ROOTS)}")
        return EXIT_SETUP

    per_file: dict[str, dict] = {}
    jobs = max(1, args.jobs)
    with tempfile.TemporaryDirectory(prefix="fallback-census-") as tmp:
        # Each worker verifies inside its OWN copy of the tracked tree, so two
        # concurrent runs can never see each other at all. Together with the
        # sidecar cleanup in run_one, the result does not depend on --jobs: two
        # runs over one tree produce identical bytes, which is what makes the
        # record diffable.
        works = []
        for w in range(jobs):
            work = Path(tmp) / f"w{w}"
            for rel in all_files:
                dest = work / rel
                dest.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(repo / rel, dest)
            works.append(work)

        # Assign the biggest files first, one per worker. Cost is dominated by a
        # few files: measured 2026-09-08 at --jobs 4, three files took 398 s,
        # 368 s and 211 s while the other 247 together took about 250 s. Round
        # robin over path order can put two of them behind each other and the
        # run then waits on one worker. Source size is an imperfect predictor
        # (the two slowest rank 4th and 5th by size, the third 34th) but it is
        # free and it separates them. Chunk order does not reach the record:
        # the counts are order-independent and every list in it is sorted.
        chunks: list[list[Path]] = [[] for _ in range(jobs)]
        by_cost = sorted(files, key=lambda r: (-(repo / r).stat().st_size, str(r)))
        for i, rel in enumerate(by_cost):
            chunks[i % jobs].append(rel)

        def run_chunk(job: int) -> list[tuple[str, dict]]:
            return [(str(r), run_one(llmll, works[job], r, args.timeout)) for r in chunks[job]]

        with ThreadPoolExecutor(max_workers=jobs) as pool:
            for done in pool.map(run_chunk, range(jobs)):
                per_file.update(dict(done))

        # CONFIRMATION PASS. A negative verdict is re-run once, alone, in a
        # pristine tree. Measured 2026-09-08: one file
        # (examples/secure-channel-emergent/work/spine.ast.json) reported
        # `refuted` during a loaded census and `pass` on five isolated runs and
        # on eight concurrent ones, so the flip is real but not reproducible on
        # demand. A gate must not fail the build on a verdict that does not
        # reproduce, and must not hide it either: a file that disagrees with
        # itself is reported as `unstable` and named.
        for path in sorted(p for p, r in per_file.items() if r["outcome"] in RECHECK_OUTCOMES):
            again = run_one(llmll, works[0], Path(path), args.timeout)
            if again["outcome"] != per_file[path]["outcome"]:
                per_file[path] = {
                    **again,
                    "outcome": "unstable",
                    "detail": f"{per_file[path]['outcome']} under load, {again['outcome']} alone",
                }

    stuck = sorted(p for p, r in per_file.items() if r["outcome"] == "solver-missing")
    if stuck:
        print(f"{GATE}: liquid-fixpoint is not on PATH; {len(stuck)} file(s) proved nothing, first {stuck[0]}")
        return EXIT_SETUP

    record = aggregate(per_file)
    record["population"] = {"roots": list(ROOTS), "files": len(files)}
    record["strict_pass"] = sorted(p for p, r in per_file.items() if r["outcome"] == "pass")
    record["files"] = {
        p: {
            "outcome": r["outcome"],
            **({"detail": r["detail"]} if "detail" in r else {}),
            **({"body_faithful": len(r["body_faithful"])} if "body_faithful" in r else {}),
            **({"causes": r["causes"]} if r.get("causes") else {}),
        }
        for p, r in sorted(per_file.items())
    }
    # No timestamp anywhere in the record: two runs over one tree must produce
    # identical bytes, or a diff cannot separate a real change from the clock.

    if args.out:
        Path(args.out).write_text(json.dumps(record, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    summary_path = args.summary or os.environ.get("GITHUB_STEP_SUMMARY")
    if summary_path:
        with open(summary_path, "a", encoding="utf-8") as fh:
            fh.write(render_summary(record))

    slowest = sorted(
        ((rec.get("seconds") or 0.0, path) for path, rec in per_file.items()),
        reverse=True,
    )[:3]
    if slowest and slowest[0][0] > 0:
        print(f"{GATE}: slowest: " + ", ".join(f"{p} {sec:.0f}s" for sec, p in slowest))

    r = record["ratio"]
    print(
        f"{GATE}: {len(files)} files, ratio {r['value']:.3f} "
        f"({r['body_faithful']}/{r['denominator']} body-faithful, {r['excluded_no_goal']} with no goal); "
        f"strict-pass {len(record['strict_pass'])}; "
        + ", ".join(f"{k} {v}" for k, v in record["outcomes"].items())
    )
    if record["unknown_causes"]:
        print(f"{GATE}: unknown fallback cause(s): {', '.join(record['unknown_causes'])}; widen KNOWN_CAUSES")
        return EXIT_FAIL

    unstable = sorted(p for p, rec in per_file.items() if rec["outcome"] == "unstable")
    for p in unstable:
        print(f"{GATE}: {p} disagreed with itself: {per_file[p]['detail']}; the verdict is not stable")

    hard = sorted(p for p, rec in per_file.items() if rec["outcome"] in ("timeout", "run-failed"))
    if hard:
        for p in hard:
            print(f"{GATE}: {p}: {per_file[p]['outcome']} ({per_file[p].get('detail', '')})")
        return EXIT_FAIL

    if args.write_baseline:
        baseline_path.parent.mkdir(parents=True, exist_ok=True)
        baseline_path.write_text(
            json.dumps(
                {
                    "note": "FALLBACK-CENSUS-1 ratchet floor. The strict-pass set may grow; "
                            "it may not shrink without a waiver naming the cause.",
                    "strict_pass": record["strict_pass"],
                    "waivers": {},
                    "recorded": record["ratio"],
                },
                indent=2,
                sort_keys=True,
            )
            + "\n",
            encoding="utf-8",
        )
        print(f"{GATE}: baseline written to {baseline_path} ({len(record['strict_pass'])} files)")
        return EXIT_OK

    if args.no_ratchet:
        return EXIT_OK

    if not baseline_path.is_file():
        print(f"{GATE}: no baseline at {baseline_path}; write one with --write-baseline")
        return EXIT_FAIL
    try:
        baseline = json.loads(baseline_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        print(f"{GATE}: baseline {baseline_path} is unreadable: {exc}")
        return EXIT_FAIL

    failures, notes = check_ratchet(record, baseline)
    for line in notes:
        print(line)
    if failures:
        for line in failures:
            print(line)
        return EXIT_FAIL

    gained = sorted(set(record["strict_pass"]) - set(baseline.get("strict_pass") or []))
    if gained:
        print(f"{GATE}: {len(gained)} file(s) newly pass --strict-verified-core; refresh the baseline")
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
