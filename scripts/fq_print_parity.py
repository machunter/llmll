#!/usr/bin/env python3
"""FQ-ARITH-FLAT-1: the gate for a change that moves only the .fq printing.

A byte-identical `.fq` sweep cannot pass when the printer changes on purpose.
This gate compares what the solver itself sends to z3 instead: for each tracked
source, `fixpoint --save` writes the SMT-LIB queries of a run to
`.liquid/<file>.smt2`, and the gate compares those logs from two compilers.

Two logs that are byte-identical mean z3 received the same input, so no verdict
can move on that file. A file whose log differs is allowed only if it is named
as expected (`--expect-differ`); any other difference fails the gate.

The default expected set is FQ-ARITH-FLAT-1's: the five tracked files that hold
a right-nested `+`, which the flat printer regroups as `a + b + c`. The solver
then reads `(+ (+ a b) c)` where it read `(+ a (+ b c))`. That is equal over
unbounded `int`, but it is a different query, so it is named here, not hidden.

Modes:

  emit:    fq_print_parity.py --old LLMLL --new LLMLL --work DIR [--repo R] [--rev REV]
           Extracts REV of the tracked tree twice (one copy per compiler, so the
           sidecars and `.fq` copies of one run cannot reach the other), runs
           `llmll --time-limit T --json verify SRC --fq-out ...` serially on every
           tracked `.llmll` and `.ast.json` source, then compares the logs.
  compare: fq_print_parity.py --fq-old DIR --fq-new DIR --work DIR
           Compares two directories of already emitted `.fq` files, by file name.

Every solver and compiler run is serial and is its own process group, killed
whole on a timeout. Exit 0: no unexpected difference. Exit 1: a difference
outside the expected set, or a file that has a log on one side only. Exit 2:
setup error.
"""

import argparse
import hashlib
import json
import os
import shutil
import signal
import subprocess
import sys
from pathlib import Path

GATE = "fq-print-parity"

# FQ-ARITH-FLAT-1: the tracked files with a right-nested `+` (11 sites), measured
# on v0.37.0 and again on v0.38.0. Their logs differ by `(+ a (+ b c))` against
# `(+ (+ a b) c)` and in nothing else; their verdicts match.
DEFAULT_EXPECTED = (
    "examples/conways_life_json_verifier/life.ast.json",
    "examples/netpbm-swarm/sample.llmll",
    "examples/netpbm/pixel.llmll",
    "examples/payments-core/conserve-bad.ast.json",
    "examples/payments-core/conserve-bad.llmll",
)

SUFFIXES = (".llmll", ".ast.json")
VERIFY_TIMEOUT_S = 400
SOLVE_TIMEOUT_S = 300


def run_group(cmd, cwd, timeout):
    """Run cmd as its own process group; on a timeout kill the whole group."""
    p = subprocess.Popen(cmd, cwd=str(cwd), stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                         text=True, start_new_session=True)
    try:
        out, err = p.communicate(timeout=timeout)
        code = p.returncode
    except subprocess.TimeoutExpired:
        os.killpg(p.pid, signal.SIGKILL)
        out, err = p.communicate()
        code = None
    try:
        os.killpg(p.pid, signal.SIGKILL)   # a straggler left in the group
    except (ProcessLookupError, PermissionError):
        pass
    return code, out, err


def tracked_sources(repo, rev):
    out = subprocess.run(["git", "ls-tree", "-r", "--name-only", "-z", rev], cwd=str(repo),
                         capture_output=True, text=True, check=True).stdout
    return sorted(n for n in out.split("\0")
                  if n and n.endswith(SUFFIXES) and not n.endswith(".verified.json"))


def extract(repo, rev, dest):
    dest.mkdir(parents=True)
    arch = subprocess.Popen(["git", "archive", rev], cwd=str(repo), stdout=subprocess.PIPE)
    subprocess.run(["tar", "-x", "-C", str(dest)], stdin=arch.stdout, check=True)
    if arch.wait() != 0:
        raise SystemExit(f"{GATE}: git archive {rev} failed")


def fq_name(rel):
    return rel.replace("/", "__") + ".fq"


def emit(llmll, tree, files, outdir, time_limit):
    outdir.mkdir(parents=True)
    exits = {}
    for n, rel in enumerate(files):
        src = tree / rel
        code, _, _ = run_group([llmll, "--time-limit", str(time_limit), "--json", "verify", src.name,
                                "--fq-out", str(outdir / fq_name(rel))],
                               src.parent, VERIFY_TIMEOUT_S)
        exits[rel] = code
        print(f"  {n + 1}/{len(files)} {rel} exit {code}", file=sys.stderr, flush=True)
    return exits


def smt_hash(fixpoint, fq, work):
    """sha256 of the solver's SMT log for one .fq, or None if it wrote none.

    The file is copied to a fixed name, so the log never holds a path that
    differs between the two sides.
    """
    if work.exists():
        shutil.rmtree(work)
    work.mkdir(parents=True)
    shutil.copyfile(fq, work / "q.fq")
    run_group([fixpoint, "-q", "--save", "q.fq"], work, SOLVE_TIMEOUT_S)
    log = work / ".liquid" / "q.fq.smt2"
    if not log.is_file():
        return None
    return hashlib.sha256(log.read_bytes()).hexdigest()


def compare(old_dir, new_dir, names, fixpoint, work, expected):
    """names maps a display name to the .fq file name used on both sides."""
    same, differ, one_side, neither, empty = [], [], [], [], []
    for disp, fn in sorted(names.items()):
        a, b = old_dir / fn, new_dir / fn
        ea = a.is_file() and a.stat().st_size > 0
        eb = b.is_file() and b.stat().st_size > 0
        if not ea and not eb:
            empty.append(disp)
            continue
        if ea != eb:
            one_side.append(disp)
            continue
        ha = smt_hash(fixpoint, a, work / "old")
        hb = smt_hash(fixpoint, b, work / "new")
        if ha is None and hb is None:
            neither.append(disp)
        elif ha is None or hb is None:
            one_side.append(disp)
        elif ha == hb:
            same.append(disp)
        else:
            differ.append(disp)
    unexpected = [d for d in differ if d not in expected]
    report = {
        "files": len(names), "no_fq_either_side": len(empty), "smt2_identical": len(same),
        "smt2_differ": differ, "smt2_differ_expected": [d for d in differ if d in expected],
        "smt2_differ_unexpected": unexpected, "log_on_one_side_only": one_side,
        "no_log_either_side": neither,
        "expected_but_identical": sorted(set(expected) & set(same)),
    }
    return report, not unexpected and not one_side


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--old")
    ap.add_argument("--new")
    ap.add_argument("--fq-old")
    ap.add_argument("--fq-new")
    ap.add_argument("--work", required=True)
    ap.add_argument("--repo", default=".")
    ap.add_argument("--rev", default="HEAD")
    ap.add_argument("--fixpoint", default=shutil.which("fixpoint") or "fixpoint")
    ap.add_argument("--time-limit", type=int, default=60)
    ap.add_argument("--expect-differ", action="append", default=None,
                    help="a source whose log may differ (repeatable); replaces the default set")
    ap.add_argument("--json-out")
    args = ap.parse_args(argv)
    expected = set(args.expect_differ if args.expect_differ is not None else DEFAULT_EXPECTED)
    work = Path(args.work).resolve()
    if work.exists() and any(work.iterdir()):
        print(f"{GATE}: --work {work} must be empty or absent", file=sys.stderr)
        return 2
    work.mkdir(parents=True, exist_ok=True)

    if args.fq_old and args.fq_new:
        old_dir, new_dir = Path(args.fq_old), Path(args.fq_new)
        names = {p.name: p.name for p in old_dir.glob("*.fq")}
        names.update({p.name: p.name for p in new_dir.glob("*.fq")})
        expected = {fq_name(e) for e in expected} | expected
    elif args.old and args.new:
        repo = Path(args.repo).resolve()
        files = tracked_sources(repo, args.rev)
        trees = {}
        for side in ("old", "new"):
            trees[side] = work / f"tree-{side}"
            extract(repo, args.rev, trees[side])
        print(f"{GATE}: {len(files)} tracked sources at {args.rev}", file=sys.stderr)
        exits = {}
        for side, llmll in (("old", args.old), ("new", args.new)):
            exits[side] = emit(llmll, trees[side], files, work / f"fq-{side}", args.time_limit)
        old_dir, new_dir = work / "fq-old", work / "fq-new"
        names = {rel: fq_name(rel) for rel in files}
    else:
        print(f"{GATE}: give --old and --new, or --fq-old and --fq-new", file=sys.stderr)
        return 2

    report, ok = compare(old_dir, new_dir, names, args.fixpoint, work / "smt", expected)
    if args.old and args.new and not (args.fq_old and args.fq_new):
        report["exit_code_differ"] = sorted(r for r in names if exits["old"][r] != exits["new"][r])
    if args.json_out:
        Path(args.json_out).write_text(json.dumps(report, indent=1, sort_keys=True) + "\n")
    print(f"{GATE}: files {report['files']}; no .fq either side {report['no_fq_either_side']}; "
          f"smt2 identical {report['smt2_identical']}; differ {len(report['smt2_differ'])} "
          f"(expected {len(report['smt2_differ_expected'])}, unexpected "
          f"{len(report['smt2_differ_unexpected'])}); log on one side only "
          f"{len(report['log_on_one_side_only'])}; no log either side {len(report['no_log_either_side'])}")
    for key in ("smt2_differ_unexpected", "log_on_one_side_only", "smt2_differ_expected",
                "expected_but_identical", "exit_code_differ"):
        for d in report.get(key, []):
            print(f"  {key}: {d}")
    print(f"{GATE}: {'PASS' if ok else 'FAIL'}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
