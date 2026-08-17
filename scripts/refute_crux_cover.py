#!/usr/bin/env python3
"""TOOL-RFC-002 mutation cover for the LLMLL refute-crux gate.

THIS WAS A DIFFERENTIAL COVER UNTIL 2026-08-17 AND IT IS NOT ONE NOW.
`scripts/refute-crux-gate.sh` was deleted when TOOL-RFC-002 moved to
`tool_state: retired`, so there is no second implementation to compare against.
Every cell now runs the PORT alone and checks it against the cell's own declared
`expect_fail`. That value was always written here in the `@cell` decorators and
was never read off the reference, which is why the retarget was mechanical.

WHAT WAS LOST, NAMED RATHER THAN LEFT FOR A READER TO NOTICE. Two checks die and
no rewrite recovers either. The exit codes are no longer compared, and the
per-case verdict ROWS are no longer compared, so this cover can no longer
separate "the two implementations agree" from "neither of them works". That
distinction had a defect to its name: at TOOL-ENCODING-1 every mutation cell
AGREED while both sides failed identically for a reason unrelated to the
mutation, and only a second implementation plus the negative controls could tell
those two cases apart. A self-cover cannot detect that class at all.

WHAT REPLACES ONE HALF OF IT, PARTLY. The row comparison also did a second job
by accident: two runs that each produced ZERO graded rows compared equal, so an
empty report could not pass a mutant cell but COULD pass a negative control.
Alone, that hole is wide open. `MIN_ROWS` below closes it directly: a negative
control must produce graded rows, and the count is asserted rather than assumed.
That is a weaker instrument than a second implementation and it is not offered as
an equal replacement.

WHAT DOES NOT CHANGE. The 80-verdict freeze is not here and never was. It is the
live corpus run, in `.github/workflows/version-gate.yml`, job `spec-roundtrip`,
step "Run refute-crux verdict gate (LLMLL port, TOOL-RFC-002)", which grades all
80 frozen verdicts against `EXPECTED_VERDICTS.json` with the compiler that job
just built. The retirement removed the reference's step beside it and left that
one untouched.

AGREEMENT ON A PASSING TREE IS NOT EVIDENCE. Three of the cells below are
negative controls that must PASS; every other cell is a mutant that must FAIL. A
port that always answered "everything diverged" is caught by the controls; a port
that always answered "fine" is caught by the mutants.

WHY A TRIMMED SCRATCH TREE. The live corpus is 80 cases and one full run is about
seventy seconds, and keeping one case per expectation across all twelve suites
still left sixteen cells at half an hour. `prepare()` copies all twelve suite
directories, then keeps ONE CASE PER EXPECTATION from each manifest. Not the
first case: every suite's first case is `safe`, so a first-case trim leaves a
corpus with no `refuted` and no `capability` in it and half the cells have
nothing to mutate. Trimming rather than dropping whole suites is also deliberate,
because the port's `families` list is hardcoded and a missing suite is a "not
found" failure in every cell, which would drown the signal. That reason used to
be stated about the reference's FAMILIES array; the port hardcodes the same list
in the same order, so the constraint outlived the reference.

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

# Keep in step with refutecrux.llmll's `families`. Until the 2026-08-17
# retirement it also had to match the shell reference's FAMILIES array, so one
# side of this duplication is now gone.
#
# scripts/tests/test_refute_crux_ll.py asserts this list against the port rather
# than trusting it, on version_gate_cover.py's precedent, and it checks ORDER and
# not only membership because `find_case` walks this list in order.
#
# THAT SENTENCE WAS FALSE FROM THE DAY THIS FILE WAS WRITTEN UNTIL 2026-08-17.
# It named test_refute_crux_ll.py, the file did not exist, and nothing asserted
# this list against anything, so a suite added to the port and not here would
# have been copied by no cell and mutated by no cell while the cover went on
# reporting sixteen. The comment is left true rather than deleted because what it
# claimed was worth claiming; the file now exists and its three failure modes,
# a dropped suite, an extra suite and a reordering, were each made to fire.
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
# list rather than being left out, because the port's `families` list is
# hardcoded and a missing directory is a "not found" failure in every cell,
# which would drown the signal. The port handles a zero-case manifest by moving
# on, so an empty suite costs one manifest read.
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
    # THREE LINES WERE REMOVED HERE AT THE 2026-08-17 RETIREMENT, and they were
    # all scaffolding for the reference. It derived REPO_ROOT from its own
    # location and ran every verify as `cd "$REPO_ROOT/compiler" && stack exec
    # llmll -- verify ...`, so a scratch tree it could run in needed a copy of
    # the script under scripts/ and a `compiler` symlink beside it. The port
    # needs neither: --subject names the binary directly, which is TOOL-RFC-002
    # §8 decision 2 paying for itself a second time. A scratch tree is now the
    # twelve suites and nothing else.


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

# The ✅ and ❌ alternatives were the REFERENCE's markers and are removed at the
# retirement, because a pattern that can only match output no program emits is
# the dead branch this campaign reports on elsewhere. The port writes PASS and
# FAIL. Keeping the reference's two would have cost nothing and asserted nothing,
# which is worse than removing them.
VERDICT = re.compile(r"^\s*(PASS|FAIL)\s+(.*)$")

# The floor a negative control must clear. Five, measured: `trimmed()` keeps one
# case per expectation, CASE_SUITES is two suites, `examples/gotofail` carries
# `safe` and `refuted`, and `tools/llmll-driver` carries all three, so an
# unmutated trimmed tree grades 2 + 3 cases.
#
# WHY THIS CONSTANT EXISTS AT ALL, and it is new at the retirement. The row
# comparison that died was doing a second job by accident: it compared the two
# implementations' rows, so a run that graded NOTHING still had to match a run
# that graded nothing, and the mutant cells caught an empty report because an
# empty report exits 0 where a mutant demands non-zero. A negative control has no
# such backstop. Alone, a port that read no manifest, graded no case and exited 0
# would pass all three controls. Asserting the count is the cheap direct answer,
# and it is the same technique the covers in this campaign already use when they
# report an assertion that was never reached.
MIN_ROWS = 5

# CAPTURE-ENCODING-1, kept as a direct check because the retarget would otherwise
# have dropped it silently. A case label carries U+2192, and a console program
# used to emit the bytes `c2 92` for it, the codepoint truncated to its low byte,
# even with the emitted `main` pinning utf8 on stdout: System.Posix.IO.fdToHandle
# returns a BINARY handle, so there is no codec for setLocaleEncoding to inform.
# Fixed at v0.14.90 by pinning both ends of the capture pipe in captureStdout.
#
# The differential form caught a regression here for free. The two labels were
# COMPARED, so a truncated arrow made the row comparison fail, and a comment on
# that line said so. There is nothing to compare now, so the property is asserted
# on its own. Testing for the mojibake directly is also the stronger form: it
# fires whether or not the label happens to differ from something else.
MOJIBAKE = "\u0092"  # the truncation, written as an escape so this file stays ASCII


def normalise(out: str) -> list[str]:
    """The graded core of a run: the ordered per-case verdicts."""
    rows = []
    for line in out.splitlines():
        m = VERDICT.match(line)
        if not m:
            continue
        mark = m.group(1)
        label = m.group(2).strip()
        rows.append(f"{mark} {label}")
    return rows


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


@cell("N3 unmutated tree", "the port passes an unmutated corpus and grades it",
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

            prc, prows, praw = run_port(tree, args.gate, args.llmll)
            port_failed = prc != 0

            # 1. The mutant must be CAUGHT. RETARGETED AT RETIREMENT,
            #    2026-08-17: this read `shell_failed and port_failed` and the
            #    reference is deleted, so it reads the port alone. The retarget
            #    is mechanical and not a rewrite, because `expect_fail` was
            #    always declared data in the @cell decorator above and was never
            #    read off the reference.
            if expect_fail and not port_failed:
                print(f"  MISS {name}: not caught (port exit {prc}) -- {why}")
                bad += 1
                continue
            if not expect_fail and port_failed:
                print(f"  MISS {name}: negative control failed "
                      f"(port exit {prc}) -- {why}")
                print("\n".join(f"    port | {l}" for l in praw.splitlines()[-6:]))
                bad += 1
                continue

            # 2. TWO COMPARISONS USED TO RUN HERE AND BOTH ARE GONE: exit code
            #    against exit code, and per-case rows against per-case rows. They
            #    needed two implementations. Nothing below replaces them; see the
            #    module docstring, which names the loss rather than leaving a
            #    reader to infer it from an absence.
            #
            #    What runs instead are two checks the differential form got for
            #    free and a self-cover does not. A negative control that grades
            #    NOTHING would otherwise pass, so the row count is asserted; and
            #    a label carrying the CAPTURE-ENCODING-1 truncation would
            #    otherwise go unread, so it is asserted too.
            if not expect_fail and len(prows) < MIN_ROWS:
                print(f"  MISS {name}: negative control graded {len(prows)} "
                      f"case(s), expected at least {MIN_ROWS} -- {why}")
                print("\n".join(f"    port | {l}" for l in praw.splitlines()[-6:]))
                bad += 1
                continue
            if MOJIBAKE in praw:
                print(f"  MISS {name}: output carries the CAPTURE-ENCODING-1 "
                      f"truncation (U+0092) -- a label lost its arrow")
                bad += 1
                continue

            print(f"  ok   {name} ({len(prows)} cases, exit {prc})")
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
