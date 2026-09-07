#!/usr/bin/env python3
"""TOOL-RFC-003 mutation cover for DRIFT-CT-2's LLMLL port.

WAS A DIFFERENTIAL COVER UNTIL 2026-08-17. `scripts/doc_claims_gate.sh` was
deleted when TOOL-RFC-003 moved to `tool_state: retired`, so `docclaims.llmll` is
the only implementation and every cell now checks it against its own declared
`expect_fail`. TWO CHECKS DIED, not one: the exit-code comparison, and the report
comparison that caught "same verdict, different report". No cell declares the
report text it expects, so nothing replaces the second. This is a decision
battery now.

WHAT THIS IS FOR. The two implementations are declared `oracle`, meaning either
answers for the other. A live green run does not establish that: two gates that
both pass on a healthy tree agree perfectly and detect nothing. So every cell
here MUTATES a scratch tree, asserts the mutation is caught by BOTH
implementations, and only then compares what they said.

THE NEGATIVE CONTROLS ARE NOT DECORATION. N1-N3 change the input in ways that
must NOT fail. Without them a cover that reported failure unconditionally would
score a perfect 16/16, which is exactly the shape of the defect the campaign
exists to catch.

CELLS 10 AND 11 ASSERT AGREEMENT ON SKIPPING, NOT AGREEMENT ON DECIDING, and
that is a user adjudication (2026-08-08) rather than an accident: the reference
exits 0 without asserting anything when it finds no compiler and when the
fixture directory is empty, and the port reproduces both faithfully. The
silent-success behaviour is filed as its own roadmap row against the reference.
A cover that quietly "fixed" it here would be the port improving on its
reference, which retirement cannot survive.

Usage mirrors refute_crux_cover.py, INCLUDING THE ARGUMENT ROLES, which are not
what their names suggest:
    --gate   the PORT BINARY (docclaims), executed directly
    --llmll  the COMPILER, passed on as the subject
The shell reference is not an argument at all; it is copied into the scratch
tree and invoked there.
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Callable

REPO = Path(__file__).resolve().parent.parent
FIXTURES = REPO / "scripts" / "doc-claims"

# The port is a console step machine (MODE-CLI-1), so it is driven by a stdin
# budget rather than a loop. 16 fixtures cost ~6 steps each; 400 is generous
# and still an order of magnitude under the refute-crux port's 4000.
BUDGET = 400

# Seconds one cell may take before it is reported as a HANG (see CAPTURE-PIPE-1
# above). The real subject runs a cell in about 3 s locally; the budget is wide
# so a slow solver on a CI runner cannot trip it, and it is still a bound.
CELL_TIMEOUT = 300

# THE ENVIRONMENT BOTH SIDES GET, and every entry in it is load-bearing for a
# reason that cost a red CI run to learn.
#
# PATH and HOME are scrubbed so the two implementations are asked the SAME
# question: an earlier revision let the port inherit the caller's PATH and find
# an `llmll` the reference could not see.
#
# NO LOCALE IS SET HERE, DELIBERATELY, AND THAT IS THIS COVER'S SECOND JOB.
#
# v0.14.92 shipped with `LC_ALL=C.UTF-8` and `LANG=C.UTF-8` pinned in this dict
# as a WORKAROUND, pre-marked for removal. Scrubbing the environment had put the
# compiler in the POSIX locale, and `llmll` decoded `.llmll` source through
# `TIO.readFile`, which takes the ambient locale, so on Linux it could not read
# a single one of the fixtures:
#
#     hGetContents: invalid argument (cannot decode byte sequence starting from 194)
#
# 194 being 0xC2, a UTF-8 lead byte. `TOOL-ENCODING-1` fixed that at the handle,
# so the pin came out with it. Removing it is the row's acceptance criterion
# rather than a tidy-up: with no locale set, this cover is the only gate in the
# repository that fails if the compiler ever again decodes source through the
# environment. Do not re-add it to make a red run go away.
#
# WHAT THAT EPISODE DEMONSTRATED, kept because it is the argument for the three
# negative controls. Cells 1-13 all AGREED while every fixture was unreadable:
# both implementations failed, and failed identically, so every mutation cell
# went green. Only the controls, which require both sides to PASS an unmutated
# tree, could tell "the two implementations agree" from "the compiler cannot
# read a single fixture".
#
# **macOS cannot reproduce any of it**, which is v0.14.86's finding and finding
# 10's: GHC there resolves UTF-8 under every `LC_ALL`. This cover passed 17/17
# locally throughout, with no locale set and, until v0.20.0, no solver on PATH.
#
# THE SOLVER IS THE ONE THING PUT BACK, AND ONLY THE SOLVER. Since v0.20.0 three
# fixtures (shadow-alpha-renamed, display-level-verified and
# effective-level-post-meet; NC-012, NC-022, NC-024) have a solver verdict as
# their witness, so a corpus run with no `fixpoint` on PATH fails those three
# and every negative control with them: run 34061569204 reported 3 of 17 cells
# diverged, all three controls, on a runner whose fixpoint sat in ~/.local/bin
# below this scrub. main() resolves `fixpoint` (or `liquid-fixpoint`) and `z3`
# from the CALLER's PATH, links them into a directory holding nothing else, and
# prepends that directory here. The scrub still hides every `llmll` the caller
# can see, which is what it was for. A caller with no solver is refused up
# front, naming the binary, rather than reported as drift in the corpus.
#
# CELL 11 HANGS ON macOS SINCE THE CORPUS REACHED 31 FIXTURES, and the cause is
# the runtime's, not this cover's: CAPTURE-PIPE-1. The console step machine
# redirects stdout into a pipe for one step and reads it back afterwards on the
# same thread; a step that prints more than the pipe holds (16 KiB on macOS,
# 64 KiB on Linux) blocks in the write with nobody reading. Cell 11 makes every
# fixture fail, so the port's finish step prints the whole 31-block report,
# 18,316 bytes, in one step (28 fixtures print 15,893 and pass; 29 hang). Two
# local runs of this cover sat at cell 11 for two hours before that was measured. Each cell is now bounded by CELL_TIMEOUT and a
# hang is reported as a diverged cell that names the row. It is NOT skipped on
# darwin: a red cell that says why is the cover doing its job, and skipping it
# would be the locale-pin mistake again. On Linux the same report is under the
# buffer and the cell passes, which is why CI never saw it.
ENV = {
    "PATH": "/usr/bin:/bin:/usr/local/bin",
    "HOME": "/nonexistent",
}


def solver_dir(root: Path) -> Path:
    """A directory holding ONLY the solver, linked from the caller's PATH."""
    fixpoint = shutil.which("liquid-fixpoint") or shutil.which("fixpoint")
    z3 = shutil.which("z3")
    missing = [n for n, p in (("fixpoint", fixpoint), ("z3", z3)) if p is None]
    if missing:
        raise SystemExit(
            "FAIL: doc-claims cover: no " + " or ".join(missing)
            + " on the caller's PATH; three fixtures need a proof, so no cell "
            + "can be decided (see ENV)"
        )
    d = root / "solver-bin"
    d.mkdir()
    for exe in (fixpoint, z3):
        (d / Path(exe).name).symlink_to(exe)
    return d


def prepare(dst: Path) -> None:
    """A scratch tree the reference can run in and the port can be pointed at."""
    (dst / "scripts" / "doc-claims").mkdir(parents=True, exist_ok=True)
    for f in FIXTURES.glob("*.llmll"):
        shutil.copy2(f, dst / "scripts" / "doc-claims" / f.name)
    # The reference resolves its subject from $LLMLL_BIN; the compiler symlink
    # is what lets `stack exec` style invocations still work if anyone uses one.
    (dst / "compiler").symlink_to(REPO / "compiler")


def fixtures(tree: Path) -> list[Path]:
    return sorted((tree / "scripts" / "doc-claims").glob("*.llmll"))


def find_fixture(tree: Path, base: str) -> Path:
    """First fixture whose @expect base matches, so cells do not hardcode names.

    Hardcoding a filename is how a cover rots: the fixture set is expected to
    grow, and a cell that cannot find its anchor must FAIL rather than skip.
    """
    for f in fixtures(tree):
        for line in f.read_text().splitlines():
            if "@expect:" in line:
                if line.split("@expect:", 1)[1].strip().split(":", 1)[0] == base:
                    return f
                break
    raise AssertionError(
        f"no fixture with @expect base {base!r}; this cell would test nothing"
    )


def set_header(f: Path, field: str, value: str) -> None:
    out, done = [], False
    for line in f.read_text().splitlines():
        if not done and f"@{field}:" in line:
            head = line.split(f"@{field}:", 1)[0]
            out.append(f"{head}@{field}: {value}")
            done = True
        else:
            out.append(line)
    assert done, f"{f.name} has no @{field}: line; this cell would test nothing"
    f.write_text("\n".join(out) + "\n")


def drop_header(f: Path, field: str) -> None:
    lines = f.read_text().splitlines()
    kept = [l for l in lines if f"@{field}:" not in l]
    assert len(kept) < len(lines), (
        f"{f.name} has no @{field}: line to drop; this cell would test nothing"
    )
    f.write_text("\n".join(kept) + "\n")


def normalise(out: str) -> list[str]:
    """Comparable lines. Blank lines only: the port's console harness emits one
    per step, which is a property of the entry mode and not of the verdict.

    NOTHING ELSE IS NORMALISED, deliberately. v0.14.90's lesson is that two
    implementations should have their labels COMPARED rather than reconciled by
    the cover: the arrow-normalising line in refute_crux_cover.py hid a real
    encoding defect for a release. The port reproduces the reference's %-30s
    and %-11s padding so that this comparison can be exact.
    """
    return [l for l in out.splitlines() if l.strip()]


def run_port(tree: Path, gate: str, subject: str) -> tuple[int | None, list[str], str]:
    work = tree / ".work"
    work.mkdir(exist_ok=True)
    run = tree / ".run"
    run.mkdir(exist_ok=True)
    # An empty subject means "nothing names a compiler": the argument is omitted
    # entirely rather than passed empty, which is what makes the port fall back
    # to its default and probe.
    argv = [gate, "--root", str(tree), "--work", str(work)]
    if subject:
        argv += ["--subject", subject]
    # THE SAME RESTRICTED ENVIRONMENT THE REFERENCE GETS, character for
    # character. Without this the two implementations are asked different
    # questions: the port inherited the caller's PATH and found an `llmll` the
    # reference could not see, so the no-compiler cell had one side run the whole
    # corpus and the other skip. A differential cover that varies the environment
    # between the two sides is comparing two worlds, not two implementations.
    # See ENV for why the locale is pinned rather than absent.
    try:
        p = subprocess.run(
            argv,
            input="x\n" * BUDGET, capture_output=True, text=True, cwd=str(run),
            env=dict(ENV), timeout=CELL_TIMEOUT,
        )
    except subprocess.TimeoutExpired:
        # A hung port is neither a fail nor a pass: returncode None, and main()
        # reports it before the expect_fail comparison can read it as either.
        return None, [], f"(no output: the port ran for {CELL_TIMEOUT}s and was killed)"
    return p.returncode, normalise(p.stdout + p.stderr), p.stdout + p.stderr


CELLS: list[tuple[str, str, "Callable[[Path], None]", bool, bool]] = []


def cell(name: str, why: str, *, expect_fail: bool = True,
         compare_report: bool = True):
    def reg(fn):
        CELLS.append((name, why, fn, expect_fail, compare_report))
        return fn
    return reg


# --- the criteria ----------------------------------------------------------

@cell("1", "a check-ok fixture claims check-error")
def _c1(tree): set_header(find_fixture(tree, "check-ok"), "expect", "check-error")


@cell("2", "a parse-error fixture claims check-error (CLASSIFICATION ORDER)")
def _c2(tree): set_header(find_fixture(tree, "parse-error"), "expect", "check-error")


@cell("3", "a check-error fixture claims parse-error (order, other way)")
def _c3(tree): set_header(find_fixture(tree, "check-error"), "expect", "parse-error")


@cell("4", "a pinned substring is corrupted")
def _c4(tree):
    for f in fixtures(tree):
        for line in f.read_text().splitlines():
            if "@expect:" in line:
                v = line.split("@expect:", 1)[1].strip()
                if ":" in v:
                    base, sub = v.split(":", 1)
                    set_header(f, "expect", f"{base}:{sub}-CORRUPTED")
                    return
                break
    raise AssertionError("no fixture pins a substring; this cell would test nothing")


@cell("5", "a warn fixture claims a warning that is not emitted")
def _c5(tree): set_header(find_fixture(tree, "warn"), "expect", "warn:no-such-warning-xyz")


@cell("6", "an output-base fixture's cited string is corrupted")
def _c6(tree): set_header(find_fixture(tree, "output"), "expect", "output:no-such-output-xyz")


def find_with_cmd(tree: Path) -> Path:
    for f in fixtures(tree):
        if "@cmd:" in f.read_text():
            return f
    raise AssertionError("no fixture carries @cmd; this cell would test nothing")


@cell("7", "@cmd is redirected to a subcommand whose output cannot match")
def _c7(tree): set_header(find_with_cmd(tree), "cmd", "version")


@cell("8", "@cmd is dropped so the fixture falls back to `check {file}`")
def _c8(tree):
    # Dropping the override makes `checkout`/`verify` become `check`, whose
    # output cannot satisfy the fixture's expectation.
    drop_header(find_with_cmd(tree), "cmd")


@cell("9", "a check-ok fixture's SOURCE is broken (the gate reads the compiler)")
def _c9(tree):
    f = find_fixture(tree, "check-ok")
    f.write_text(f.read_text() + "\n(this is not valid llmll\n")


@cell("10", "the fixture directory is emptied", expect_fail=False)
def _c10(tree):
    for f in fixtures(tree):
        f.unlink()


# An EXPLICITLY NAMED but nonexistent subject must FAIL loudly, not skip. The
# reference uses $LLMLL_BIN as given and never second-guesses it; a port that
# probed unconditionally skipped here instead, which this cell caught.
# compare_report=False, and the reason is not laziness. When the named subject
# does not exist the reference's captured output is BASH's own diagnostic
# ("...: No such file or directory", one per fixture, emitted by the shell that
# tried to exec it). No port can reproduce another shell's error text, and a
# cover that demanded it would be asserting something neither implementation
# controls. What this cell asserts is the DECISION: fail, not skip. That is the
# property the port got wrong.
# ON macOS THIS CELL REPORTS HANG TODAY (CAPTURE-PIPE-1, see ENV): with every
# fixture failing, the port's report exceeds the 16 KiB pipe the step machine
# captures stdout through. Linux passes it. Not skipped here on purpose.
@cell("11", "an explicitly named subject does not exist (must FAIL, not skip)",
      compare_report=False)
def _c11(tree):
    pass  # the runner substitutes a nonexistent subject for this cell


# The genuine SKIP path: nothing NAMES a compiler and none can be found. The
# reference reaches it with $LLMLL_BIN empty and no llmll on PATH; the port
# reaches it by being given no --subject at all.
# PINS AN OPEN DEFECT RATHER THAN A CORRECT BEHAVIOUR, and that is deliberate.
# SKIP-SILENT-1 is open: this gate exits 0 having asserted nothing when no
# compiler resolves. The cell used to assert the two implementations AGREE on
# skipping; it now asserts the port skips, which pins the defect in place until
# someone decides SKIP-SILENT-1. Read a passing cell here as "the known defect
# is still here", not as "this is right".
@cell("11b", "no compiler can be found at all (the port SKIPs: pins SKIP-SILENT-1)", expect_fail=False)
def _c11b(tree):
    pass  # the runner omits the subject entirely for this cell


@cell("12", "two fixtures drift at once")
def _c12(tree):
    set_header(find_fixture(tree, "check-ok"), "expect", "check-error")
    set_header(find_fixture(tree, "parse-error"), "expect", "check-ok")


@cell("13", "only the LAST fixture drifts (the loop does not stop early)")
def _c13(tree): set_header(fixtures(tree)[-1], "expect", "check-error")


# --- negative controls -----------------------------------------------------

@cell("N1", "header whitespace is reflowed", expect_fail=False)
def _n1(tree):
    f = fixtures(tree)[0]
    txt = f.read_text().replace("@expect: ", "@expect:    ")
    f.write_text(txt)


@cell("N2", "a @claim line is edited (reported, never matched)", expect_fail=False)
def _n2(tree):
    set_header(fixtures(tree)[0], "claim", "an entirely different sentence")


@cell("N3", "the tree is unmutated", expect_fail=False)
def _n3(tree):
    pass


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--gate", help="the PORT binary (docclaims)")
    ap.add_argument("--llmll", help="the COMPILER, used as --subject")
    ap.add_argument("--keep", action="store_true")
    args = ap.parse_args()

    if not args.gate or not Path(args.gate).exists():
        print("SKIP: no docclaims binary (--gate)")
        return 0
    if not args.llmll or not Path(args.llmll).exists():
        print("SKIP: no llmll subject (--llmll)")
        return 0

    solver_root = Path(tempfile.mkdtemp(prefix="doc-claims-cover-solver-"))
    ENV["PATH"] = f"{solver_dir(solver_root)}:{ENV['PATH']}"

    bad = 0
    for name, why, mutate, expect_fail, compare_report in CELLS:
        root = Path(tempfile.mkdtemp(prefix="doc-claims-cover-"))
        tree = root / "tree"
        tree.mkdir()
        try:
            prepare(tree)
            mutate(tree)
            if name == "11":
                subject = str(tree / "no-such-llmll")
            elif name == "11b":
                subject = ""          # nothing names a compiler
            else:
                subject = args.llmll

            prc, prows, praw = run_port(tree, args.gate, subject)

            # A HANG is its own verdict. Folding it into port_failed would let
            # cell 11 (expect_fail) pass on the strength of a killed process,
            # which is exactly what a SIGTERM from outside made it do once.
            if prc is None:
                print(f"  HANG     {name:4s} the port did not finish in {CELL_TIMEOUT}s  ({why}) [CAPTURE-PIPE-1]")
                print(praw)
                bad += 1
                continue

            port_failed = prc != 0

            # RETARGETED AT RETIREMENT, 2026-08-17. This used to compare the
            # port against `scripts/doc_claims_gate.sh` twice: once on the exit
            # code and once on the report rows. The reference is deleted, so the
            # only surviving check is the cell's own `expect_fail`, which was
            # always declared data in the @cell decorator.
            if port_failed is not expect_fail:
                verb = "must fail" if expect_fail else "must NOT fail"
                print(f"  VACUOUS  {name:4s} the mutation {verb} and did not  ({why})")
                print(praw)
                bad += 1
                continue

            # THE REPORT COMPARISON IS GONE AND IT WAS DOING WORK. It caught
            # "same verdict, different report", a class no per-cell boolean can
            # reach, because no cell declares the report text it expects. This
            # cover is now a decision battery and not a report battery. That is
            # a larger loss than TOOL-RFC-004's retirement took, and it is
            # recorded here rather than left for a reader to infer from the
            # absent branch. `compare_report` is kept in the @cell signature so
            # the cells need no edit; nothing reads it now.
            print(f"  ok   {name:4s} {why} ({len(prows)} lines, exit {prc})  [decision only]")
        finally:
            if not args.keep:
                shutil.rmtree(root, ignore_errors=True)

    if not args.keep:
        shutil.rmtree(solver_root, ignore_errors=True)
    print()
    if bad:
        print(f"FAIL: doc-claims cover: {bad} of {len(CELLS)} cell(s) diverged")
        return 1
    print(f"OK: doc-claims cover: {len(CELLS)} cells, 3 negative controls.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
