#!/usr/bin/env python3
"""TOOL-RFC-004 mutation cover for DRIFT-DOC-3's LLMLL port.

RFC: docs/design/tool-rfc-004-doc-archive.md sections 6 and 8.

THIS WAS A DIFFERENTIAL COVER UNTIL 2026-08-17 AND IT IS NOT ONE NOW.
`scripts/doc_archive_gate.sh` was deleted when TOOL-RFC-004 moved to
`tool_state: retired`, so there is no second implementation to compare against.
Every cell now runs the PORT alone and checks it against the cell's own declared
`expect`. That value was always written here in CELLS and was never read off the
reference, which is why the retarget was mechanical.

WHAT WAS LOST, NAMED RATHER THAN LEFT FOR A READER TO NOTICE. This cover can no
longer separate "the two implementations agree" from "neither of them works".
That distinction had a defect to its name: at TOOL-ENCODING-1 every mutation
cell AGREED while both sides failed identically for a reason unrelated to the
mutation, and only a second implementation plus the negative controls could tell
those two cases apart. **A self-cover cannot detect that class at all.** The
negative controls are kept because they still catch a port that fails on an
unmutated tree, which is the weaker half of what they used to do.

WHY A LIVE GREEN RUN STILL DOES NOT DECIDE THIS. The live corpus declares
exactly ONE disposition, so it exercises one of four vocabulary values and zero
of the four violation classes. The mutation battery is the whole instrument, and
it survives the retirement intact.

THE ENVIRONMENT IS STILL SCRUBBED and it deliberately sets NO locale. With none
set, this cover is one of the gates that fails if the compiler ever again decodes
source through the environment (TOOL-ENCODING-1's acceptance criterion). That
property does not need two implementations.

  --gate    the PORT binary (built from tools/doc-archive/docarchive.llmll)
  --repo    the repository to copy fixtures and docs/archive from

Exit 0 iff every cell meets its expectation and every control passes.
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

# The env both sides are given. No locale on purpose; see the module docstring.
ENV = {"PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": "/nonexistent"}

FM = "---\narchive-disposition: {v}\n---\n\nbody\n"


def stage(repo: pathlib.Path, dest: pathlib.Path) -> None:
    """A scratch copy holding only what the gate reads."""
    (dest / "scripts").mkdir(parents=True, exist_ok=True)
    (dest / "docs").mkdir(parents=True, exist_ok=True)
    shutil.copytree(repo / FIXTURES, dest / FIXTURES)
    shutil.copytree(repo / ARCHIVE, dest / ARCHIVE)


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
# Each mutate() takes the staged tree root. `expect` is what the PORT must do.
# It said BOTH until the 2026-08-17 retirement removed the second side.

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
            rc_p, out_p = run_port(tree, gate)

        got_p = "PASS" if rc_p == 0 else "FAIL"
        # RETARGETED AT RETIREMENT, 2026-08-17. The expectation used to be
        # checked on the REFERENCE, with the port then required to match it
        # exactly. `scripts/doc_archive_gate.sh` is deleted, so `expect` is now
        # checked on the PORT directly. That retarget is mechanical and not a
        # rewrite: `expect` was always declared data in CELLS above and was
        # never read off the reference.
        #
        # WHAT THIS COVER NO LONGER DOES, stated because a silent loss is the
        # thing this file's own docstring is about. It cannot compare two
        # implementations, so it cannot separate "the two agree" from "neither
        # works". That is exactly the class TOOL-ENCODING-1 fell in: every
        # mutation cell AGREED while both sides failed identically, and only a
        # second implementation plus the negative controls could tell those
        # apart. Nothing here replaces that. The mutation battery survives; the
        # disagreement detector does not.
        ok = got_p == expect

        if ok:
            print(f"  ok    {name:52s} port {got_p}")
        else:
            bad += 1
            print(f"  FAIL  {name:52s} port={got_p}(rc={rc_p}) expected={expect}")
            for ln in norm(out_p)[:14]:
                print(f"        {ln}")

    total = len(CELLS)
    controls = sum(1 for n, _e, _m in CELLS if n.startswith("NC-"))
    if bad:
        print(f"\nDRIFT-DOC-3 COVER FAIL: {bad} of {total} cell(s) missed "
              f"their expectation")
        return 1
    print(f"\nDRIFT-DOC-3 COVER PASS: {total} cells met their expectation "
          f"({controls} negative controls, {total - controls} mutations)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
