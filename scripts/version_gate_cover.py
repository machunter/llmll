#!/usr/bin/env python3
"""DRIFT-CI-1: the LLMLL version gate against the shell version it ports.

Runs both implementations over the same tree and requires them to answer
IDENTICALLY: same exit code, same message, byte for byte. The shell script is
the reference, so any divergence is the port's defect until argued otherwise.

AGREEMENT ON A PASSING TREE IS NOT EVIDENCE, which is why the clean tree is one
cell out of fourteen and the other thirteen are mutants. Each names the
criterion it breaks, and each is asserted to FAIL: a battery where both
implementations pass everything agrees perfectly and detects nothing. The
suite fails if a mutant is not caught, separately from failing if the two
disagree, so a port that always returned "" would be caught by the first check
even though it agreed with nothing.

WHY A MUTATED COPY AND NOT THE LIVE REPO. Each cell needs a tree whose banner
is wrong, and the live tree's banner is right and must stay so. `prepare()`
copies the seven files the gate reads into a scratch tree, preserving their
paths, and a mutant edits one of them. The shell script takes REPO_ROOT from
the environment and the LLMLL one takes --root, so both are pointed at the copy.

THE SEVEN FILES ARE THE GATE'S WHOLE INPUT, and that is itself worth pinning:
if the gate ever reads an eighth, a mutant of it would go undetected here
because the scratch tree would not contain it. `test_driver_ll_4e.py` has the
same shape of check for the wave, and `test_version_gate_ll.py` carries this
one, so the file list is asserted against both implementations' sources rather
than trusted.

Usage:
    python3 scripts/version_gate_cover.py --gate /path/to/versiongate
    VERSION_GATE_BIN=... python3 scripts/version_gate_cover.py
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
SHELL_GATE = REPO / "scripts" / "version_gate.sh"


def _banner_version() -> str:
    """The version every C1 cell mutates, read from the tree rather than pinned.

    THIS COVER USED TO HARDCODE `0.14.87` AND THAT IS EXACTLY THE DEFECT V13
    EXISTS TO CATCH, one level up. V13's own comment says a gate that failed it
    "would be pinning a literal version rather than checking that the sites
    agree"; the cover asserting that property pinned a literal version itself.

    The moment the banner moved to 0.14.88 (d6e9f01) five cells could no longer
    find their anchor. They did not go quietly green — `edit`'s `want` reports a
    cell that would test nothing, which is the safe direction — but the stage
    had failed from that commit onward, and `build_smoke.sh` with it.

    LLMLL.md line 1 is the right source because it is where scripts/version_gate.sh
    takes the banner from: the cover now follows the release the gate is being
    graded against, instead of a release it was written during.
    """
    first = (REPO / "LLMLL.md").read_text().splitlines()[0]
    m = re.search(r"v(\d+\.\d+\.\d+)", first)
    if m is None:
        raise SystemExit(
            "version_gate_cover: no vX.Y.Z on LLMLL.md line 1, and every C1 "
            "cell is anchored to it"
        )
    return m.group(1)


# The banner under test, and two versions that are not it. DISAGREE is what a
# single site is moved to so it contradicts the others; ALL_TOGETHER is what
# every site moves to in V13, which must still pass. Both are well-formed and
# neither can collide with a real banner.
BANNER = _banner_version()
DISAGREE = "0.0.0"
ALL_TOGETHER = "0.99.0"

# `version:` lines carry different padding in package.yaml and llmll.cabal, so
# the anchor is a pattern rather than a literal with the spacing baked in — the
# other half of what made the pinned version brittle.
VERSION_LINE = rf"(?m)^(version:\s*){re.escape(BANNER)}\b"

# Every file the gate reads. Keep in step with versiongate.llmll's read chain.
INPUTS = [
    "README.md",
    "LLMLL.md",
    "CHANGELOG.md",
    "compiler/package.yaml",
    "compiler/llmll.cabal",
    "docs/llmll-ast.schema.json",
    "compiler/src/LLMLL/ParserJSON.hs",
]

# One line per step, and the gate takes nine. Generous, because a starved
# console run exits 70 and that is a budget error rather than a decision.
BUDGET = 60


class Failure(Exception):
    pass


def want(cond: bool, msg: str) -> None:
    if not cond:
        raise Failure(msg)


def prepare(root: Path) -> Path:
    tree = root / "tree"
    for rel in INPUTS:
        dst = tree / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy(REPO / rel, dst)
    return tree


def edit(tree: Path, rel: str, old: str, new: str) -> None:
    p = tree / rel
    s = p.read_text()
    want(old in s, f"the mutation's anchor {old!r} is not in {rel}, so this "
                   f"cell would test nothing")
    p.write_text(s.replace(old, new, 1))


def edit_re(tree: Path, rel: str, pattern: str, repl: str) -> None:
    """`edit` for anchors whose surrounding whitespace is not worth pinning."""
    p = tree / rel
    s, n = re.subn(pattern, repl, p.read_text(), count=1)
    want(n == 1, f"the mutation's pattern {pattern!r} matches nothing in "
                 f"{rel}, so this cell would test nothing")
    p.write_text(s)


def verdict_lines(out: str) -> str:
    """The gate's own output, with its subprocesses' chatter removed.

    THE SHELL GATE LEAKS ITS TOOLS' STDERR AND THE LLMLL PORT DOES NOT, which
    is a real difference and is why this filter exists rather than a raw
    comparison. On an absent README the shell emits `head: README.md: No such
    file or directory` ahead of its own message, and on a corrupt schema it
    emits `jq: parse error: ...`; the port emits neither, because a failed
    `wasi.fs.read` answers RErr and a failed `json-parse` answers Error, and
    neither prints. Both then report the SAME criterion with the SAME exit
    code, so the decision is identical and the noise is not part of it.

    Filtering on the `DRIFT-CI-1` prefix keeps every byte the gate itself
    writes, including the whole PASS report, so this is narrower than it looks:
    a port that changed a message, a criterion or a version would still be
    caught.
    """
    return "\n".join(ln for ln in out.splitlines()
                     if ln.startswith("DRIFT-CI-1") or ln.startswith("  "))


def run_shell(tree: Path) -> tuple[int, str]:
    env = dict(os.environ, REPO_ROOT=str(tree))
    p = subprocess.run(["bash", str(SHELL_GATE)], capture_output=True,
                       text=True, env=env)
    return p.returncode, verdict_lines(p.stdout + p.stderr)


def run_llmll(gate: Path, tree: Path) -> tuple[int, str]:
    # cwd is the cell's scratch directory and not this process's, because a
    # console program writes <module>.event-log.jsonl into its working
    # directory. Without this the cover drops one untracked file into whatever
    # tree it was invoked from, once per cell.
    p = subprocess.run([str(gate), "--root", str(tree)], cwd=tree.parent,
                       input="x\n" * BUDGET, capture_output=True, text=True)
    want(p.returncode != 70,
         "exit 70: stdin was exhausted before :done? fired, so this cell "
         "observed a starved run rather than a decision")
    # The console harness prints one captured block per step, so a run emits a
    # blank line for every step whose command wrote nothing. That is a property
    # of the harness and not of the gate; the decision is the non-blank text.
    return p.returncode, verdict_lines(p.stdout + p.stderr)


# ---------------------------------------------------------------------------
# The cells
# ---------------------------------------------------------------------------

CELLS = []


def cell(name: str, why: str, *, expect_fail: bool = True):
    def deco(fn):
        CELLS.append((name, why, fn, expect_fail))
        return fn
    return deco


@cell("V0", "the unmutated tree passes both", expect_fail=False)
def v0(tree):
    pass


@cell("V1", "C1 README banner disagrees with LLMLL.md")
def v1(tree):
    edit(tree, "README.md", f"v{BANNER}", f"v{DISAGREE}")


@cell("V2", "C1 README line 1 carries no version at all")
def v2(tree):
    p = tree / "README.md"
    lines = p.read_text().splitlines()
    lines[0] = "# LLMLL"
    p.write_text("\n".join(lines))


@cell("V3", "C1 README.md is absent entirely")
def v3(tree):
    (tree / "README.md").unlink()


@cell("V4", "C2 the CHANGELOG top heading disagrees with the banner")
def v4(tree):
    edit(tree, "CHANGELOG.md", f"## v{BANNER}", f"## v{DISAGREE}")


@cell("V5", "C2 the CHANGELOG has no `## vX.Y.Z` heading")
def v5(tree):
    p = tree / "CHANGELOG.md"
    p.write_text(p.read_text().replace("## v", "## release "))


@cell("V6", "C1 compiler/package.yaml disagrees with the banner")
def v6(tree):
    edit_re(tree, "compiler/package.yaml", VERSION_LINE, rf"\g<1>{DISAGREE}")


@cell("V7", "C1 compiler/package.yaml has no version field")
def v7(tree):
    p = tree / "compiler/package.yaml"
    p.write_text("\n".join(ln for ln in p.read_text().splitlines()
                           if not ln.startswith("version:")))


@cell("V8", "C1 compiler/llmll.cabal disagrees with the banner")
def v8(tree):
    edit_re(tree, "compiler/llmll.cabal", VERSION_LINE, rf"\g<1>{DISAGREE}")


@cell("V9", "C3 the schema const disagrees with ParserJSON")
def v9(tree):
    edit(tree, "docs/llmll-ast.schema.json", '"const": "0.11.0"',
         '"const": "0.12.0"')


@cell("V10", "C3 ParserJSON's expectedSchemaVersion disagrees with the schema")
def v10(tree):
    edit(tree, "compiler/src/LLMLL/ParserJSON.hs",
         'expectedSchemaVersion = "0.11.0"',
         'expectedSchemaVersion = "0.12.0"')


@cell("V11", "C4 the schema $id names a different minor than schemaVersion")
def v11(tree):
    edit(tree, "docs/llmll-ast.schema.json", "/schemas/v0.11/",
         "/schemas/v0.10/")


@cell("V12", "C3+C4 the schema is not readable as JSON")
def v12(tree):
    (tree / "docs/llmll-ast.schema.json").write_text("{ this is not json")


@cell("V13", "the whole banner moves together, and that is NOT a failure",
      expect_fail=False)
def v13(tree):
    # The negative control. Every mutant above breaks agreement between two
    # sites; this one changes all five consistently and must still pass. A gate
    # that failed here would be pinning a literal version rather than checking
    # that the sites agree, which is the anti-hardcoding property
    # crux-validate-subject-hardcoded exists for one directory over.
    edit(tree, "README.md", f"v{BANNER}", f"v{ALL_TOGETHER}")
    edit(tree, "LLMLL.md", f"v{BANNER}", f"v{ALL_TOGETHER}")
    edit(tree, "CHANGELOG.md", f"## v{BANNER}", f"## v{ALL_TOGETHER}")
    edit_re(tree, "compiler/package.yaml", VERSION_LINE, rf"\g<1>{ALL_TOGETHER}")
    edit_re(tree, "compiler/llmll.cabal", VERSION_LINE, rf"\g<1>{ALL_TOGETHER}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--gate", default=os.environ.get("VERSION_GATE_BIN", ""))
    ap.add_argument("--keep", action="store_true")
    a = ap.parse_args()
    if not a.gate:
        print("ERROR: pass --gate or set VERSION_GATE_BIN to the built "
              "`versiongate` binary "
              "(llmll build tools/version-gate/versiongate.llmll)",
              file=sys.stderr)
        return 2
    gate = Path(a.gate).resolve()
    if not gate.exists():
        print(f"ERROR: {gate} does not exist", file=sys.stderr)
        return 2

    root = Path(tempfile.mkdtemp(prefix="version-gate-cover-"))
    npass = nfail = 0
    try:
        for name, why, fn, expect_fail in CELLS:
            cellroot = root / name
            cellroot.mkdir(parents=True)
            try:
                tree = prepare(cellroot)
                fn(tree)
                src, sout = run_shell(tree)
                lrc, lout = run_llmll(gate, tree)

                # 1. DETECTION. A mutant nobody catches makes the agreement
                #    below vacuous, so this is checked first and separately.
                if expect_fail:
                    want(src != 0, "the SHELL gate did not catch this mutant, "
                                   "so the cell tests nothing")
                    want(lrc != 0, f"the LLMLL gate did not catch this mutant\n"
                                   f"        shell said: {sout}")
                else:
                    want(src == 0, f"the shell gate rejected a clean tree: {sout}")
                    want(lrc == 0, f"the LLMLL gate rejected a clean tree: {lout}")

                # 2. AGREEMENT, byte for byte.
                want(src == lrc,
                     f"exit codes differ: shell {src}, llmll {lrc}\n"
                     f"        shell: {sout}\n        llmll: {lout}")
                want(sout == lout,
                     f"messages differ\n        shell: {sout!r}\n"
                     f"        llmll: {lout!r}")
            except Failure as e:
                nfail += 1
                print(f"  FAIL {name:4s} {why}\n        {e}")
            else:
                npass += 1
                print(f"  ok   {name:4s} {why}")
    finally:
        if not a.keep:
            shutil.rmtree(root, ignore_errors=True)
        else:
            print(f"  trees kept under {root}")

    print(f"DRIFT-CI-1 LLMLL port cover: {npass} passed, {nfail} failed")
    return 1 if nfail else 0


if __name__ == "__main__":
    sys.exit(main())
