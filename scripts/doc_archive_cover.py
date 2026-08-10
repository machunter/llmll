#!/usr/bin/env python3
"""TOOL-RFC-004 differential cover: DRIFT-DOC-3's shell reference vs its LLMLL port.

RFC: docs/design/tool-rfc-004-doc-archive.md section 6.

WHAT THIS DECIDES, AND WHY A LIVE GREEN RUN DOES NOT DECIDE IT. Both
implementations pass the unmutated tree, and that is nearly worthless here: the
live corpus declares exactly ONE disposition, so it exercises one of four
vocabulary values and zero of the four violation classes. Agreement on a passing
tree is agreement about almost nothing. This cover mutates the tree and requires
the two to agree on the FAILURE.

EVERY MUTANT IS ASSERTED TO FAIL UNDER BOTH BEFORE THEIR ANSWERS ARE COMPARED.
Two implementations that both report success are not thereby correct: at
TOOL-ENCODING-1 every mutation cell AGREED while both sides failed identically
for a reason unrelated to the mutation, and only the negative controls, which
require both to PASS an unmutated tree, could tell "these agree" from "neither
can read the corpus". So the controls are load-carrying, not decoration.

BOTH SIDES GET THE SAME ENVIRONMENT. 003's cover let the port inherit the
caller's PATH and it found an `llmll` the reference could not see, which compares
two worlds rather than two implementations. The env here is scrubbed to a fixed
minimum for both. It deliberately sets NO locale: with none set, this cover is
one of the gates that fails if the compiler ever again decodes source through the
environment (TOOL-ENCODING-1's acceptance criterion).

  --gate    the PORT binary (built from tools/doc-archive/docarchive.llmll)
  --repo    the repository to copy fixtures and docs/archive from

Exit 0 iff every cell agrees and every control passes.
"""

from __future__ import annotations

import argparse
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

GOVERNED = ("shipped-design-specs", "dormant-explorations")
FIXTURES = "scripts/doc-archive-fixtures"
ARCHIVE = "docs/archive"
GATE_SH = "scripts/doc_archive_gate.sh"

# The env both sides are given. No locale on purpose; see the module docstring.
ENV = {"PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": "/nonexistent"}

FM = "---\narchive-disposition: {v}\n---\n\nbody\n"


def stage(repo: pathlib.Path, dest: pathlib.Path) -> None:
    """A scratch copy holding only what the gate reads."""
    (dest / "scripts").mkdir(parents=True, exist_ok=True)
    (dest / "docs").mkdir(parents=True, exist_ok=True)
    shutil.copy2(repo / GATE_SH, dest / GATE_SH)
    shutil.copytree(repo / FIXTURES, dest / FIXTURES)
    shutil.copytree(repo / ARCHIVE, dest / ARCHIVE)


def run_ref(tree: pathlib.Path) -> tuple[int, str]:
    p = subprocess.run(["bash", GATE_SH], cwd=tree, env=ENV,
                       capture_output=True, text=True)
    return p.returncode, p.stdout + p.stderr


def run_port(tree: pathlib.Path, gate: str) -> tuple[int, str]:
    # The console harness consumes one stdin line per step and exits 70 on EOF,
    # so the budget must exceed the step count. python3 rather than
    # `yes x | head -n N`, which dies of SIGPIPE under pipefail.
    p = subprocess.run([gate, "--root", "."], cwd=tree, env=ENV,
                       input="x\n" * 900, capture_output=True, text=True)
    return p.returncode, p.stdout + p.stderr


def norm(s: str) -> list[str]:
    """Blank lines stripped from BOTH sides: the port's console harness emits one
    per step, and stripping them also removes the one blank line the reference
    prints deliberately. Same phrasing TOOL-RFC-003 uses, and for the same reason
    it is not called byte-identical."""
    return [ln.rstrip() for ln in s.splitlines() if ln.strip()]


# --------------------------------------------------------------------- cells --
# Each mutate() takes the staged tree root. `expect` is what BOTH must do.

def _write(p: pathlib.Path, text: str) -> None:
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text, encoding="utf-8")


def _live_gated(t: pathlib.Path) -> pathlib.Path:
    """The one file in docs/archive that declares a disposition. Located rather
    than hardcoded: hardcoding it would make this cover pass vacuously the day
    the file is renamed."""
    for p in (t / ARCHIVE).rglob("*.md"):
        head = p.read_text(encoding="utf-8", errors="replace").split("---")
        if len(head) > 1 and "archive-disposition:" in head[1]:
            return p
    raise SystemExit("cover: no file in docs/archive declares archive-disposition")


def _an_ungated(t: pathlib.Path) -> pathlib.Path:
    """Any governed file that declares nothing, so rewriting it leaves both the
    gated and the ungated count unchanged."""
    for p in sorted((t / ARCHIVE / GOVERNED[0]).glob("*.md")):
        parts = p.read_text(encoding="utf-8", errors="replace").split("---")
        if len(parts) < 2 or "archive-disposition:" not in parts[1]:
            return p
    raise SystemExit("cover: no ungated file to rewrite")


CELLS = [
    ("1  fixtures pass/ deleted", "FAIL",
     lambda t: shutil.rmtree(t / FIXTURES / "pass")),
    ("2  fixtures fail/ deleted", "FAIL",
     lambda t: shutil.rmtree(t / FIXTURES / "fail")),
    ("3  extra conformant file in pass/", "FAIL",
     lambda t: _write(t / FIXTURES / "pass" / GOVERNED[0] / "_extra.md",
                      FM.format(v="shipped"))),
    ("4  a pass/ fixture removed", "FAIL",
     lambda t: (t / FIXTURES / "pass" / GOVERNED[0] / "conformant-shipped.md").unlink()),
    ("5  pass/ fixture moved to the wrong side", "FAIL",
     lambda t: shutil.move(str(t / FIXTURES / "pass" / GOVERNED[0] / "conformant-shipped.md"),
                           str(t / FIXTURES / "pass" / GOVERNED[1] / "conformant-shipped.md"))),
    ("6  fail/ misfiled fixture corrected", "FAIL",
     lambda t: shutil.move(str(t / FIXTURES / "fail" / GOVERNED[1] / "misfiled-shipped.md"),
                           str(t / FIXTURES / "fail" / GOVERNED[0] / "misfiled-shipped.md"))),
    ("7  fail/ unknown-value fixture corrected", "FAIL",
     lambda t: _write(t / FIXTURES / "fail" / GOVERNED[0] / "unknown-value.md",
                      FM.format(v="shipped"))),
    ("8  fail/ stray-declaration fixture deleted", "FAIL",
     lambda t: (t / FIXTURES / "fail" / "professor-reviews" / "stray-declaration.md").unlink()),
    ("9  live gated file moved to the wrong side", "FAIL",
     lambda t: shutil.move(str(_live_gated(t)),
                           str(t / ARCHIVE / GOVERNED[0] / "_moved.md"))),
    ("10 live gated file given an unknown value", "FAIL",
     lambda t: _write(_live_gated(t), FM.format(v="probably-shipped?"))),
    ("11 stray declaration in an ungoverned archive dir", "FAIL",
     lambda t: _write(t / ARCHIVE / "professor-reviews" / "_stray.md",
                      FM.format(v="shipped"))),
    # Renaming ONE governed directory does not reach criterion 5: the other is
    # still scanned, so the gate passes with a different NOTE. The RFC's cell
    # said "rename shipped-design-specs" and was wrong about that; both have to
    # go for "scanned 0" to fire. Found by building this cover.
    ("12 both governed directories renamed", "FAIL",
     lambda t: [ (t / ARCHIVE / g).rename(t / ARCHIVE / (g + "-x")) for g in GOVERNED ]),
    ("13 the field stripped from the live gated file", "FAIL",
     lambda t: _write(_live_gated(t), "---\ntitle: x\n---\n\nbody\n")),
    # Rewrites an EXISTING ungated file rather than adding one. Adding any file
    # to a governed directory raises the ungated count to 59 and trips criterion
    # 7, so the first draft of this cell failed for a reason that had nothing to
    # do with frontmatter scoping. The cell has to hold the count fixed to test
    # what it claims to test.
    ("14 a declaration in BODY prose, not frontmatter", "PASS",
     lambda t: _write(_an_ungated(t),
                      "---\ntitle: x\n---\n\narchive-disposition: dropped\n")),
    ("NC-1 unmutated", "PASS", lambda _t: None),
    ("NC-2 a new conformant file on the correct side", "PASS",
     lambda t: _write(t / ARCHIVE / GOVERNED[1] / "_ok.md", FM.format(v="deferred"))),
    ("NC-3 an INDEX.md in a governed directory", "PASS",
     lambda t: _write(t / ARCHIVE / GOVERNED[0] / "INDEX.md", FM.format(v="dropped"))),
]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--gate", required=True, help="the PORT binary")
    ap.add_argument("--repo", default=".", help="repository to stage from")
    a = ap.parse_args()

    repo = pathlib.Path(a.repo).resolve()
    gate = str(pathlib.Path(a.gate).resolve())
    if not os.access(gate, os.X_OK):
        print(f"cover: --gate is not executable: {gate}", file=sys.stderr)
        return 1

    bad = 0
    for name, expect, mutate in CELLS:
        with tempfile.TemporaryDirectory(prefix="da-cover-") as td:
            tree = pathlib.Path(td)
            stage(repo, tree)
            mutate(tree)
            rc_r, out_r = run_ref(tree)
            rc_p, out_p = run_port(tree, gate)

        got_r = "PASS" if rc_r == 0 else "FAIL"
        got_p = "PASS" if rc_p == 0 else "FAIL"
        agree = norm(out_r) == norm(out_p) and rc_r == rc_p
        # The expectation is checked on the REFERENCE, which defines the
        # behaviour; the port is then required to match it exactly. A cell where
        # the reference does not do what the RFC says is a bug in the cell, and
        # it is reported as such rather than silently tolerated.
        ok = got_r == expect and agree

        if ok:
            print(f"  ok    {name:52s} both {got_r}")
        else:
            bad += 1
            print(f"  FAIL  {name:52s} ref={got_r}(rc={rc_r}) port={got_p}(rc={rc_p})"
                  f" expected={expect} agree={agree}")
            if not agree:
                import difflib
                for ln in list(difflib.unified_diff(
                        norm(out_r), norm(out_p), "reference", "port", lineterm=""))[:14]:
                    print(f"        {ln}")

    total = len(CELLS)
    controls = sum(1 for n, _e, _m in CELLS if n.startswith("NC-"))
    if bad:
        print(f"\nDRIFT-DOC-3 COVER FAIL: {bad} of {total} cell(s) diverged "
              f"or missed their expectation")
        return 1
    print(f"\nDRIFT-DOC-3 COVER PASS: {total} cells agree "
          f"({controls} negative controls, {total - controls} mutations)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
