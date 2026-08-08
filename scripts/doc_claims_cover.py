#!/usr/bin/env python3
"""Differential cover for TOOL-RFC-003: doc_claims_gate.sh vs docclaims.llmll.

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
SHELL_GATE = REPO / "scripts" / "doc_claims_gate.sh"
FIXTURES = REPO / "scripts" / "doc-claims"

# The port is a console step machine (MODE-CLI-1), so it is driven by a stdin
# budget rather than a loop. 15 fixtures cost ~6 steps each; 400 is generous
# and still an order of magnitude under the refute-crux port's 4000.
BUDGET = 400


def prepare(dst: Path) -> None:
    """A scratch tree the reference can run in and the port can be pointed at."""
    (dst / "scripts" / "doc-claims").mkdir(parents=True, exist_ok=True)
    for f in FIXTURES.glob("*.llmll"):
        shutil.copy2(f, dst / "scripts" / "doc-claims" / f.name)
    shutil.copy2(SHELL_GATE, dst / "scripts" / SHELL_GATE.name)
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


def run_shell(tree: Path, subject: str) -> tuple[int, list[str], str]:
    p = subprocess.run(
        ["bash", str(tree / "scripts" / SHELL_GATE.name)],
        capture_output=True, text=True, cwd=str(tree),
        env={"PATH": "/usr/bin:/bin:/usr/local/bin", "HOME": "/nonexistent",
             "LLMLL_BIN": subject, "REPO_ROOT": str(tree)},
    )
    return p.returncode, normalise(p.stdout + p.stderr), p.stdout + p.stderr


def run_port(tree: Path, gate: str, subject: str) -> tuple[int, list[str], str]:
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
    # THE SAME RESTRICTED ENVIRONMENT THE REFERENCE GETS. Without this the two
    # implementations are asked different questions: the port inherited the
    # caller's PATH and found an `llmll` the reference could not see, so the
    # no-compiler cell had one side run the whole corpus and the other skip.
    # A differential cover that varies the environment between the two sides is
    # comparing two worlds, not two implementations.
    p = subprocess.run(
        argv,
        input="x\n" * BUDGET, capture_output=True, text=True, cwd=str(run),
        env={"PATH": "/usr/bin:/bin:/usr/local/bin", "HOME": "/nonexistent"},
    )
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
@cell("11", "an explicitly named subject does not exist (must FAIL, not skip)",
      compare_report=False)
def _c11(tree):
    pass  # the runner substitutes a nonexistent subject for this cell


# The genuine SKIP path: nothing NAMES a compiler and none can be found. The
# reference reaches it with $LLMLL_BIN empty and no llmll on PATH; the port
# reaches it by being given no --subject at all.
@cell("11b", "no compiler can be found at all (both SKIP)", expect_fail=False)
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

            src, srows, sraw = run_shell(tree, subject)
            prc, prows, praw = run_port(tree, args.gate, subject)

            shell_failed = src != 0
            port_failed = prc != 0

            if shell_failed != port_failed:
                print(f"  DIVERGED {name:4s} shell exit {src}, port exit {prc}  ({why})")
                print("    --- shell ---"); print(sraw)
                print("    --- port  ---"); print(praw)
                bad += 1
                continue

            if shell_failed is not expect_fail:
                verb = "must fail" if expect_fail else "must NOT fail"
                print(f"  VACUOUS  {name:4s} the mutation {verb} and did not  ({why})")
                print(sraw)
                bad += 1
                continue

            if compare_report and srows != prows:
                print(f"  DIVERGED {name:4s} same verdict, different report  ({why})")
                only_s = [l for l in srows if l not in prows]
                only_p = [l for l in prows if l not in srows]
                for l in only_s: print(f"    shell only: {l}")
                for l in only_p: print(f"    port  only: {l}")
                bad += 1
                continue

            note = "" if compare_report else "  [decision only]"
            print(f"  ok   {name:4s} {why} ({len(srows)} lines, exit {src}){note}")
        finally:
            if not args.keep:
                shutil.rmtree(root, ignore_errors=True)

    print()
    if bad:
        print(f"FAIL: doc-claims cover: {bad} of {len(CELLS)} cell(s) diverged")
        return 1
    print(f"OK: doc-claims cover: {len(CELLS)} cells, 3 negative controls.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
