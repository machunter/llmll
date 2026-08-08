#!/usr/bin/env python3
"""TOOL-RFC-002: the LLMLL refute-crux gate against the shell version it ports.

Runs both implementations over the same tree and requires them to answer the
same way: same exit code, and the same per-case verdicts in the same order.

AGREEMENT ON A PASSING TREE IS NOT EVIDENCE. Three of the cells below are
negative controls that must PASS under both; every other cell is a mutant that
must FAIL under both, and the suite fails if a mutant is not caught, separately
from failing if the two implementations disagree. A port that always answered
"everything diverged" would agree with nothing and still be caught by the
negative controls; a port that always answered "fine" would be caught by the
mutants.

WHY A TRIMMED SCRATCH TREE. The live corpus is 80 cases and one full run is
about seventy seconds per implementation, and keeping one case per
expectation across all twelve suites still left sixteen cells at half an hour. `prepare()` copies all twelve suite
directories, then keeps ONE CASE PER EXPECTATION from each manifest. Not the
first case: every suite's first case is `safe`, so a first-case trim leaves a
corpus with no `refuted` and no `capability` in it and half the cells have
nothing to mutate. Trimming rather than dropping whole suites is also
deliberate, because the shell reference's FAMILIES array is hardcoded and a
missing suite is a "not found" failure in every cell, which would drown the
signal.

WHY `compiler` IS A SYMLINK. The shell script derives REPO_ROOT from its own
location and runs every verify as `cd "$REPO_ROOT/compiler" && stack exec llmll
-- verify ...`, so a scratch tree it can run in must have a compiler there. Symlinking the real one is what
lets the reference run against a mutated corpus at all; the port needs no such
thing, because --subject names the binary directly, which is TOOL-RFC-002 §8
decision 2 paying for itself in the first place it is used.

Usage:
    python3 scripts/refute_crux_cover.py --gate /path/to/refutecrux --llmll /path/to/llmll
    REFUTE_CRUX_BIN=... LLMLL_SUBJECT=... python3 scripts/refute_crux_cover.py
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
SHELL_GATE = REPO / "scripts" / "refute-crux-gate.sh"

# Keep in step with refutecrux.llmll's `families` and the shell's FAMILIES.
# test_refute_crux_ll.py asserts this list against BOTH sources rather than
# trusting it, on version_gate_cover.py's precedent.
FAMILIES = [
    "examples/tcp_rfc793",
    "examples/session-pay",
    "examples/gotofail",
    "examples/outcome-totality",
    "examples/total-recursion",
    "examples/bytes-bounds",
    "examples/rfc1982_serial",
    "examples/token-revocation-emergent",
    "examples/nested-result",
    "examples/niw-measure",
    "examples/banking_ledger",
    "tools/llmll-driver",
]

# One stdin line per step. The port needs roughly (4 + files-in-suite) steps per
# case plus two per suite; twelve trimmed suites stay far under this. Generous
# because a starved console run exits 70, which is a budget error and not a
# decision (MODE-CLI-1).
BUDGET = 4000

MANIFEST = "EXPECTED_VERDICTS.json"


# The suites that keep cases. Every OTHER suite is copied with an EMPTY case
# list rather than being left out, because the shell reference's FAMILIES array
# is hardcoded and a missing directory is a "not found" failure in every cell,
# which would drown the signal. Both implementations handle a zero-case
# manifest by moving on, so an empty suite costs one manifest read.
#
# These two between them carry all three expectations, and `capability` exists
# in exactly one suite in the whole corpus. Five cases per run instead of
# twenty-five: the cells test the CRITERIA, and the criteria do not care which
# suite a case came from. Corpus coverage is what the live 80-case run in CI is
# for, and it runs beside this.
CASE_SUITES = ["examples/gotofail", "tools/llmll-driver"]


def trimmed(cases: list[dict], fam: str) -> list[dict]:
    """One case per distinct expectation, in the manifest's own order.

    NOT simply `cases[:1]`. Every suite's first case is `safe`, so a
    first-case trim leaves a corpus with no `refuted` and no `capability` in
    it, and the cells that mutate those have nothing to mutate. The cover
    caught that on its first run by aborting rather than by reporting `ok`,
    which is the behaviour `find_case` raising buys.
    """
    if fam not in CASE_SUITES:
        return []
    seen, keep = set(), []
    for c in cases:
        e = c.get("expect")
        if e not in seen:
            seen.add(e)
            keep.append(c)
    return keep


def prepare(dst: Path, *, trim: bool = True) -> None:
    """Copy the twelve suites into `dst`, trimmed to one case per expectation."""
    for fam in FAMILIES:
        src = REPO / fam
        out = dst / fam
        out.mkdir(parents=True, exist_ok=True)
        for f in src.glob("*.llmll"):
            shutil.copy2(f, out / f.name)
        doc = json.loads((src / MANIFEST).read_text())
        if trim:
            doc["cases"] = trimmed(doc["cases"], fam)
        (out / MANIFEST).write_text(json.dumps(doc, indent=2))
    # The reference needs a compiler where it expects one; the port does not.
    (dst / "scripts").mkdir(parents=True, exist_ok=True)
    shutil.copy2(SHELL_GATE, dst / "scripts" / SHELL_GATE.name)
    (dst / "compiler").symlink_to(REPO / "compiler")


def manifest(tree: Path, fam: str) -> dict:
    return json.loads((tree / fam / MANIFEST).read_text())


def write_manifest(tree: Path, fam: str, doc: dict) -> None:
    (tree / fam / MANIFEST).write_text(json.dumps(doc, indent=2))


def edit_case(tree: Path, fam: str, key: str, value, idx: int = 0) -> None:
    doc = manifest(tree, fam)
    doc["cases"][idx][key] = value
    write_manifest(tree, fam, doc)


def find_case(tree: Path, expect: str) -> tuple[str, int]:
    """First (suite, index) whose kept case has the given expectation.

    Searches EVERY kept case and not just index 0. `trimmed()` keeps one case
    per expectation and every suite's first case is `safe`, so an index-0-only
    search finds no `refuted` case anywhere and the cells that need one abort.
    That is exactly what happened on the cover's second run, and it aborted
    rather than reporting `ok`, which is what `find_case` raising buys.
    """
    for fam in FAMILIES:
        for i, c in enumerate(manifest(tree, fam)["cases"]):
            if c.get("expect") == expect:
                return fam, i
    raise SystemExit(f"cover: no kept case expects {expect!r}")


# ---------------------------------------------------------------------------
# Running the two implementations
# ---------------------------------------------------------------------------

VERDICT = re.compile(r"^\s*(PASS|FAIL|✅|❌)\s+(.*)$")


def normalise(out: str) -> list[str]:
    """The comparable core of a run: the ordered per-case verdicts.

    The two implementations do NOT print byte-identical reports and are not
    asked to: the reference streams with ✅/❌ and box-drawing rules, the port
    accumulates and emits once with PASS/FAIL, because a console step performs
    exactly one Command and the filesystem work already claims it. What must
    agree is the DECISION per case, in order, which is what this extracts.
    """
    rows = []
    for line in out.splitlines():
        m = VERDICT.match(line)
        if not m:
            continue
        mark = "PASS" if m.group(1) in ("PASS", "✅") else "FAIL"
        # The reference writes U+2192 in its label and the port writes `->`.
        # That is NOT a stylistic choice in the port: measured, a console
        # program emits the bytes `c2 92` for U+2192, the codepoint truncated
        # to its low byte, even though the emitted `main` pins utf8 on stdout.
        # Filed as CAPTURE-ENCODING-1. Normalised here so the cover compares
        # the DECISION rather than re-reporting a known encoding defect on
        # every row; when the row closes, this line goes and the port's label
        # becomes the arrow.
        label = m.group(2).strip().replace("→", "->").replace("\u0092", "->")
        rows.append(f"{mark} {label}")
    return rows


def run_shell(tree: Path) -> tuple[int, list[str], str]:
    p = subprocess.run(
        ["bash", str(tree / "scripts" / SHELL_GATE.name)],
        capture_output=True, text=True, cwd=str(tree),
    )
    return p.returncode, normalise(p.stdout + p.stderr), p.stdout + p.stderr


def run_port(tree: Path, gate: str, subject: str) -> tuple[int, list[str], str]:
    work = tree / ".work"
    work.mkdir(exist_ok=True)
    run = tree / ".run"
    run.mkdir(exist_ok=True)
    p = subprocess.run(
        [gate, "--root", str(tree), "--subject", subject, "--work", str(work)],
        input="x\n" * BUDGET, capture_output=True, text=True, cwd=str(run),
    )
    return p.returncode, normalise(p.stdout + p.stderr), p.stdout + p.stderr


# ---------------------------------------------------------------------------
# Cells
# ---------------------------------------------------------------------------

CELLS = []


def cell(name: str, why: str, *, expect_fail: bool = True):
    def deco(fn):
        CELLS.append((name, why, fn, expect_fail))
        return fn
    return deco


@cell("1 safe->refuted", "a safe case relabelled refuted must not find a refutation")
def _c1(tree: Path):
    fam, i = find_case(tree, "safe"); edit_case(tree, fam, "expect", "refuted", i)


@cell("2 refuted->safe", "a refuted case relabelled safe must not find SAFE")
def _c2(tree: Path):
    fam, i = find_case(tree, "refuted"); edit_case(tree, fam, "expect", "safe", i)


@cell("3 exit 0->1 on safe", "the exit-code check must fire on its own")
def _c3(tree: Path):
    fam, i = find_case(tree, "safe"); edit_case(tree, fam, "expect_exit", 1, i)


@cell("4 exit 1->0 on refuted", "the exit-code check must fire in both directions")
def _c4(tree: Path):
    fam, i = find_case(tree, "refuted"); edit_case(tree, fam, "expect_exit", 0, i)


@cell("5 localized corrupted (refuted)", "localization is checked, quoted, on the refuted arm")
def _c5(tree: Path):
    for fam in FAMILIES:
        doc = manifest(tree, fam)
        for c in doc["cases"]:
            if c.get("expect") == "refuted" and c.get("localized"):
                c["localized"] = "no-such-function-name"
                write_manifest(tree, fam, doc)
                return
    raise SystemExit("cover: no kept refuted case carries `localized`")


@cell("6 localized corrupted (capability)",
      "localization is checked, BARE, on the capability arm")
def _c6(tree: Path):
    for fam in FAMILIES:
        doc = manifest(tree, fam)
        for c in doc["cases"]:
            if c.get("expect") == "capability" and c.get("localized"):
                c["localized"] = "no-such-capability-name"
                write_manifest(tree, fam, doc)
                return
    raise SystemExit("cover: no kept capability case carries `localized`")


@cell("7 capability->refuted",
      "a capability rejection must not stand in for a refutation")
def _c7(tree: Path):
    fam, i = find_case(tree, "capability")
    edit_case(tree, fam, "expect", "refuted", i)


@cell("8 unknown expectation", "an expectation outside the three is rejected by name")
def _c8(tree: Path):
    edit_case(tree, CASE_SUITES[0], "expect", "banana")


@cell("9 fixture deleted", "a case naming an absent fixture fails as missing")
def _c9(tree: Path):
    doc = manifest(tree, CASE_SUITES[0])
    (tree / CASE_SUITES[0] / doc["cases"][0]["file"]).unlink()


@cell("10 manifest deleted", "a suite with no manifest fails as not found")
def _c10(tree: Path):
    (tree / CASE_SUITES[0] / MANIFEST).unlink()


@cell("11 bogus flag injected", "the flag vector reaches the subject")
def _c11(tree: Path):
    """A flag the subject REJECTS, not a flag removed.

    The first version of this cell deleted `--strict-verified-core` and was NOT
    CAUGHT by either implementation, because dropping it only makes
    verification less strict and a case that is safe without it stays safe. The
    cell reported a miss, which is the battery working: a mutation that changes
    no verdict tests nothing.

    Injecting a flag the subject rejects is discriminative in the direction
    that matters. It is also the exact mutation that would have caught
    `JSON-SCALAR-1`: with the flag vector silently dropped, a bogus flag is
    dropped too and the case passes, so the port that lost its flags would fail
    this cell rather than sailing through it.
    """
    for fam in CASE_SUITES:
        doc = manifest(tree, fam)
        for c in doc["cases"]:
            if c.get("flags") is not None:
                c["flags"] = ["--not-a-real-flag"]
                write_manifest(tree, fam, doc)
                return
    raise SystemExit("cover: no kept case carries a flags array")


@cell("12 two faults in one case", "exit AND verdict both fire; reasons join")
def _c12(tree: Path):
    fam, i = find_case(tree, "safe")
    doc = manifest(tree, fam)
    doc["cases"][i]["expect"] = "refuted"
    doc["cases"][i]["expect_exit"] = 1
    write_manifest(tree, fam, doc)


@cell("13 two suites broken", "the run does not stop at the first failure")
def _c13(tree: Path):
    edit_case(tree, CASE_SUITES[0], "expect", "banana")
    edit_case(tree, CASE_SUITES[1], "expect", "banana")


@cell("N1 reformatted json", "reindenting and reordering keys changes nothing",
      expect_fail=False)
def _n1(tree: Path):
    for fam in CASE_SUITES:
        doc = manifest(tree, fam)
        doc["cases"] = [dict(reversed(list(c.items()))) for c in doc["cases"]]
        (tree / fam / MANIFEST).write_text(json.dumps(doc, indent=8))


@cell("N2 unread field edited", "`why` feeds no criterion", expect_fail=False)
def _n2(tree: Path):
    for fam in CASE_SUITES:
        doc = manifest(tree, fam)
        for c in doc["cases"]:
            c["why"] = "rewritten by the cover; no criterion reads this"
        write_manifest(tree, fam, doc)


@cell("N3 unmutated tree", "both implementations agree the corpus is green",
      expect_fail=False)
def _n3(tree: Path):
    pass


# ---------------------------------------------------------------------------


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--gate", default=os.environ.get("REFUTE_CRUX_BIN", ""))
    ap.add_argument("--llmll", default=os.environ.get("LLMLL_SUBJECT", ""))
    ap.add_argument("--keep", action="store_true")
    args = ap.parse_args()

    if not args.gate or not Path(args.gate).exists():
        print("SKIP: no refutecrux binary (--gate or REFUTE_CRUX_BIN)")
        return 0
    if not args.llmll or not Path(args.llmll).exists():
        print("SKIP: no llmll subject (--llmll or LLMLL_SUBJECT)")
        return 0

    bad = 0
    for name, why, mutate, expect_fail in CELLS:
        root = Path(tempfile.mkdtemp(prefix="refute-crux-cover-"))
        tree = root / "tree"
        tree.mkdir()
        try:
            prepare(tree)
            mutate(tree)

            src, srows, sraw = run_shell(tree)
            prc, prows, praw = run_port(tree, args.gate, args.llmll)

            shell_failed = src != 0
            port_failed = prc != 0

            # 1. The mutant must be CAUGHT, under both. A battery where both
            #    implementations pass everything agrees perfectly and detects
            #    nothing.
            if expect_fail and not (shell_failed and port_failed):
                print(f"  MISS {name}: not caught "
                      f"(shell exit {src}, port exit {prc}) -- {why}")
                bad += 1
                continue
            if not expect_fail and (shell_failed or port_failed):
                print(f"  MISS {name}: negative control failed "
                      f"(shell exit {src}, port exit {prc}) -- {why}")
                print("\n".join(f"    shell| {l}" for l in sraw.splitlines()[-6:]))
                print("\n".join(f"    port | {l}" for l in praw.splitlines()[-6:]))
                bad += 1
                continue

            # 2. Only then are the two answers compared. Agreement is checked
            #    after detection, never instead of it.
            if src != prc:
                print(f"  DIVERGE {name}: exit {src} (shell) vs {prc} (port)")
                bad += 1
                continue
            if srows != prows:
                print(f"  DIVERGE {name}: per-case verdicts differ")
                for a, b in zip(srows, prows):
                    if a != b:
                        print(f"    shell| {a}")
                        print(f"    port | {b}")
                if len(srows) != len(prows):
                    print(f"    shell rows {len(srows)}, port rows {len(prows)}")
                bad += 1
                continue

            print(f"  ok   {name} ({len(srows)} cases, exit {src})")
        finally:
            if not args.keep:
                shutil.rmtree(root, ignore_errors=True)
            else:
                print(f"       kept: {root}")

    print()
    if bad:
        print(f"FAIL: refute-crux cover: {bad} of {len(CELLS)} cells bad.")
        return 1
    print(f"OK: refute-crux cover: {len(CELLS)} cells, "
          f"{sum(1 for c in CELLS if not c[3])} negative controls.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
