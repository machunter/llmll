#!/usr/bin/env python3
"""Mutation cover for DRIFT-CT-3 (NORM-CLAIM-1), reference and port.

A NEW GATE IS A CLAIM, AND THE CLAIM IS THAT THE GATE CAN FAIL (tool-ll-RESTART.md item 14).
A green run on the live tree establishes nothing: a gate that printed PASS unconditionally
would pass it. So every cell here copies the tracked tree into a scratch directory, MUTATES
one thing, and asserts the gate's verdict on the mutation. The negative controls (N1 to N4)
change the input in ways that must NOT fail; without them a cover that reported failure
unconditionally would score full marks.

Two modes. With only `--repo`, this is a self-cover of the Python reference
(scripts/norm_claims_gate.py): each cell asserts the expected exit code. With `--port PATH`,
it is a DIFFERENTIAL cover: the port binary runs on the same scratch tree, and the cell also
asserts that the port's exit code equals the reference's and that on a passing tree the two
success lines are byte-identical (cell N4 is the non-ASCII byte-identity cell, the
TOOL-ENCODING-1 lesson).

Design: docs/design/norm-claim-proposal.md §5 (edge cases 1 to 12).
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Callable

REPO = Path(__file__).resolve().parent.parent
GATE = REPO / "scripts" / "norm_claims_gate.py"
REGISTRY = "scripts/norm-claims/registry.json"
SPEC = "LLMLL.md"
ROADMAP = "docs/compiler-team-roadmap.md"


# ---------------------------------------------------------------------------
# Scratch tree
# ---------------------------------------------------------------------------

def tracked(repo: Path) -> list[str]:
    out = subprocess.run(["git", "-C", str(repo), "ls-files"], capture_output=True, text=True, check=True).stdout
    return [p for p in out.split("\n") if p]


def prepare(src: Path, dst: Path) -> None:
    """Copy every tracked file (including intent-to-add entries) and make dst a git index of
    its own, because the gate resolves fixtures and suites against `git ls-files`."""
    for rel in tracked(src):
        s = src / rel
        if not s.is_file():
            continue
        d = dst / rel
        d.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(s, d)
    subprocess.run(["git", "-C", str(dst), "init", "-q"], check=True)
    subprocess.run(["git", "-C", str(dst), "add", "-A"], check=True)


def read(tree: Path, rel: str) -> str:
    return (tree / rel).read_text(encoding="utf-8")


def write(tree: Path, rel: str, text: str) -> None:
    (tree / rel).write_text(text, encoding="utf-8")
    subprocess.run(["git", "-C", str(tree), "add", rel], check=True)


def edit(tree: Path, rel: str, old: str, new: str, count: int = 1) -> None:
    s = read(tree, rel)
    assert old in s, f"cover setup: {old[:60]!r} not found in {rel}"
    write(tree, rel, s.replace(old, new, count))


def edit_registry(tree: Path, fn: Callable[[dict], None]) -> None:
    reg = json.loads(read(tree, REGISTRY))
    fn(reg)
    write(tree, REGISTRY, json.dumps(reg, ensure_ascii=False, indent=2) + "\n")


def row(reg: dict, rid: str) -> dict:
    for r in reg["claims"]:
        if r["id"] == rid:
            return r
    raise AssertionError(f"cover setup: {rid} not in registry")


# ---------------------------------------------------------------------------
# Running the two implementations
# ---------------------------------------------------------------------------

def run_reference(tree: Path) -> tuple[int, str]:
    p = subprocess.run([sys.executable, str(GATE), "--repo", str(tree)], capture_output=True, text=True)
    return p.returncode, p.stdout + p.stderr


def run_port(tree: Path, port: str) -> tuple[int, str]:
    # The port is a console step machine driven by stdin lines (MODE-CLI-1); 400 is generous.
    p = subprocess.run([port, "--root", str(tree)], input="x\n" * 400, capture_output=True, text=True)
    return p.returncode, p.stdout + p.stderr


def success_line(out: str) -> str | None:
    for line in out.split("\n"):
        if line.startswith("DRIFT-CT-3: "):
            return line
    return None


# ---------------------------------------------------------------------------
# Cells
# ---------------------------------------------------------------------------

def c1(t):  # untagged sentence (proposal §5 case 1)
    edit(t, SPEC, "[NC-023]", "")

def c2(t):  # row closed (case 2)
    s = read(t, ROADMAP)
    m = re.search(r"^\| \*\*CAP-1-REAL\*\*[^\n]*?\| \*\*OPEN", s, re.M)
    assert m, "cover setup: CAP-1-REAL row not found"
    write(t, ROADMAP, s[: m.start()] + m.group(0).replace("| **OPEN", "| **SHIPPED v9.9.9") + s[m.end():])

def c3(t):  # text edited without re-affirmation (case 3)
    edit(t, SPEC, "Imports are non-transitive, so", "Imports are never transitive, so")

def c4(t):  # fixture present, claim absent (case 4)
    edit(t, "scripts/doc-claims/import-non-transitive.llmll", ";; @norm: NC-030\n", "")

def c5(t):  # orphan registry row (case 5)
    edit_registry(t, lambda r: r["claims"].append({"id": "NC-099", "section": "1.6", "text": "Nothing.", "disposition": "informative"}))

def c6(t):  # assumed count over the bound (case 10)
    def f(r):
        x = row(r, "NC-003"); x["disposition"] = "assumed"; x["reason"] = "cover mutation"
    edit_registry(t, f)

def c7(t):  # malformed registry (case 9)
    write(t, REGISTRY, read(t, REGISTRY)[:-40])

def c8(t):  # empty scope (case 9)
    edit_registry(t, lambda r: r.__setitem__("scope", []))

def c9(t):  # falsified-by names no suite
    edit_registry(t, lambda r: row(r, "NC-008").__setitem__("target", "suite:no-such-suite"))

def c10(t):  # duplicate marker in the spec
    edit(t, SPEC, "[NC-010]", "[NC-009]")

def c11(t):  # fixture path not in the index
    edit_registry(t, lambda r: row(r, "NC-012").__setitem__("target", ["scripts/doc-claims/does-not-exist.llmll"]))

def c12(t):  # row target absent from the Active Items table
    edit_registry(t, lambda r: row(r, "NC-031").__setitem__("target", "NO-SUCH-ROW-1"))

def n1(t):  # an informative sentence with a marker and a row (case 6)
    edit(t, SPEC, "See §7 for the sandbox implementation and the enforcement gap.[NC-033]",
         "See §7 for the sandbox implementation and the enforcement gap.[NC-033] This item ends here.[NC-099]")
    edit_registry(t, lambda r: r["claims"].append({"id": "NC-099", "section": "1.6", "text": "This item ends here.", "disposition": "informative"}))

def n2(t):  # a marker inside a fenced block in scope (case 7)
    edit(t, SPEC, "\n## 0.2 Normative Sentence Markers", "\n```lisp\n;; [NC-999] inside a fence is not prose\n```\n\n## 0.2 Normative Sentence Markers")

def n3(t):  # whitespace-only change (normalization)
    edit(t, SPEC, "Imports are non-transitive, so", "Imports are non-transitive,  so")

def n4(_tree):  # no mutation: the live tree, non-ASCII sentences included (case 8)
    return None


CELLS: list[tuple[str, str, Callable[[Path], None], bool]] = [
    ("c1",  "untagged sentence in scope", c1, True),
    ("c2",  "row target closed (status cell no longer OPEN)", c2, True),
    ("c3",  "tagged sentence edited without re-affirming its row", c3, True),
    ("c4",  "fixture exists but its @norm: line no longer names the id", c4, True),
    ("c5",  "orphan registry row with no sentence", c5, True),
    ("c6",  "assumed count exceeds assumed_bound", c6, True),
    ("c7",  "registry is not valid JSON", c7, True),
    ("c8",  "registry scope is empty", c8, True),
    ("c9",  "falsified-by names a suite that does not exist", c9, True),
    ("c10", "one identifier appears twice in the spec", c10, True),
    ("c11", "fixture path absent from the git index", c11, True),
    ("c12", "row target absent from the Active Items table", c12, True),
    ("N1",  "negative: informative sentence added with marker and row", n1, False),
    ("N2",  "negative: marker inside a fenced block is not prose", n2, False),
    ("N3",  "negative: whitespace-only change inside a sentence", n3, False),
    ("N4",  "negative: live tree, non-ASCII sentences, byte-identical success line", n4, False),
]


def main() -> int:
    ap = argparse.ArgumentParser(description="Mutation cover for DRIFT-CT-3.")
    ap.add_argument("--repo", default=str(REPO))
    ap.add_argument("--port", default=None, help="the LLMLL port binary; when given, the cover is differential")
    a = ap.parse_args()
    repo = Path(a.repo).resolve()

    live_line = None
    failures: list[str] = []
    root = Path(tempfile.mkdtemp(prefix="norm-claims-cover-"))
    try:
        for name, why, mutate, expect_fail in CELLS:
            tree = root / name
            tree.mkdir()
            prepare(repo, tree)
            mutate(tree)
            rc, out = run_reference(tree)
            ok = (rc != 0) if expect_fail else (rc == 0 and success_line(out) is not None)
            detail = ""
            if not expect_fail and rc == 0:
                if name == "N4":
                    live_line = success_line(out)
            if a.port:
                prc, pout = run_port(tree, a.port)
                if prc != rc:
                    ok = False
                    detail += f" port exit {prc} != reference exit {rc};"
                if not expect_fail and rc == 0 and success_line(pout) != success_line(out):
                    ok = False
                    detail += f" success lines differ: {success_line(pout)!r} vs {success_line(out)!r};"
            status = "✔" if ok else "✘"
            print(f"  {status} {name:<4} {why} [reference exit {rc}]{detail}")
            if not ok:
                failures.append(name)
                print("     " + "\n     ".join(out.strip().split("\n")[:6]))
            shutil.rmtree(tree, ignore_errors=True)
    finally:
        shutil.rmtree(root, ignore_errors=True)

    mode = "differential (reference + port)" if a.port else "self-cover (reference only; no --port given)"
    if failures:
        print(f"norm_claims_cover FAIL: {len(failures)} of {len(CELLS)} cells disagree ({', '.join(failures)}); mode: {mode}")
        return 1
    print(f"norm_claims_cover PASS: {len(CELLS)} of {len(CELLS)} cells agree; mode: {mode}; live line: {live_line}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
