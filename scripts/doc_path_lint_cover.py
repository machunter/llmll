#!/usr/bin/env python3
"""TOOL-RFC-005 mutation cover for DRIFT-DOC-4's LLMLL port.

RFC: docs/design/tool-rfc-005-doc-path-lint.md sections 6 and 8.

THIS FILE IS A REBUILD, NOT A RESTORE. The original
`scripts/doc_path_lint_cover.py` was a DIFFERENTIAL cover: it pinned
`REF = "scripts/doc_path_lint.py"` and diffed the two implementations under
mutation. It could not outlive its reference, so the retirement at v0.14.99
deleted both and left the port graded by nothing for five days. RFC section 8
stated that cost at the time rather than discovering it later, and named cells 9
and 13 as the two that were measured to discriminate. This file starts there.

WHAT WAS LOST AND IS NOT RECOVERED HERE. A self-cover cannot separate "the two
implementations agree" from "neither of them works". That distinction had a
defect to its name: at TOOL-ENCODING-1 every mutation cell AGREED while both
sides failed identically for a reason unrelated to the mutation, and only a
second implementation plus the negative controls could tell those two cases
apart. Nothing below replaces that. The mutation battery is recovered; the
disagreement detector is not.

THE CORPUS IS SYNTHETIC AND THAT IS THE CHANGE THAT MADE THE REBUILD POSSIBLE.
The old cover staged the live tree, so its counts moved with every commit, and
it therefore could not pin a literal anywhere: it compared counts between two
implementations instead. With one implementation there is nothing to compare a
count against, so the counts here come from an eight-file tree defined in `BASE`
below, where every count is exact and every rule is reachable. The live corpus
still runs, in `.github/workflows/version-gate.yml`, job `spec-roundtrip`, step
"Run prose path-citation lint (LLMLL port, TOOL-RFC-005)". That step is the live
half and this file is the mutation half. Neither is the other.

NC-4 IS THE ONE CELL THAT READS THE REAL REPOSITORY, and it exists because the
live step cannot fail. The gate is advisory by design and exits 0 whatever it
finds, so a port that read NO corpus at all would print a zero-citation report
and the live step would pass it. NC-4 asserts floors on the two counts and
nothing else. **It deliberately does not assert that the live tree resolves.**
Making a broken citation in the tree fail this cover would move DRIFT-DOC-4 to
fail-closed through the back door, which RFC section 8 leaves as a decision for
a person to take and not for a cover to take by accident.

WHY THE EXIT CODE GRADES ALMOST NOTHING. The port exits 0 on every input that is
not both `--strict` and finding-bearing. Cells 17 and 18 are the only two where
the exit code carries information, and every other cell is graded on the report
text: the summary counts, the `file:line  `path`` finding lines, and the tail.

  --gate    the PORT binary (built from tools/doc-path-lint/pathlint.llmll)
  --repo    the repository NC-4 runs against
  --only    run one cell by its leading name, for the broken-port drill below

THE BATTERY HAS BEEN SHOWN TO FAIL, WHICH IS THE POINT OF `--only`. This file
passed 24 of 24 on its first run, and that is the state this campaign has twice
been wrong in. So three one-line mutants of the port were built and run through
it, two of them reproducing the drill RFC section 6 records for the original
cover. Measured 2026-08-17:

  * `hist-pat` written as the literal-plus-capitalized variant list that
    decision D3 forbids: cell 9 FAILS and cells 7, 8 and 13 still pass, so cell
    9 is not redundant with its neighbours.
  * `excluded-dir?` returning false, dropping the `site/` and `node_modules/`
    filter: cell 13 FAILS on all three of its axes at once, reporting a finding
    against `site/index.md`, counting 2 citations where 1 is expected, and
    scanning 5 living files where 4 are expected. **Cells 7, 8 and 9 also fail
    this mutant, on the living-file count alone.** That is a difference from the
    original cover and it is a property of the corpus rather than of the port:
    `BASE` always carries a `site/` file, so every cell's living count sees F1.
    Cell 13 is therefore the only cell that tests F1 deliberately, and it is no
    longer the only cell that would notice F1 going away.
  * `allowed?` testing the cited PATH alone and ignoring the citing FILE: cell
    16 passes and cell 16b FAILS. That is the pair those two cells exist to
    separate, and 16b is the half the RFC's own cell 16 could not see.

No mutant is committed. What this establishes is narrow: three cells are known
to discriminate. The other twenty-one are not individually shown to fail.

Usage:
    python3 scripts/doc_path_lint_cover.py --gate /path/to/pathlint
    PATHLINT_BIN=... python3 scripts/doc_path_lint_cover.py

Exit 0 iff every cell meets its expectation.
"""

from __future__ import annotations

import argparse
import os
import pathlib
import re
import subprocess
import sys
import tempfile

# The env every cell is given. No locale on purpose: with none set, this cover is
# one of the gates that fails if the compiler ever again decodes source through
# the environment, which is TOOL-ENCODING-1's acceptance criterion.
ENV = {"PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": "/nonexistent"}

# The console harness consumes one stdin line per step and exits 70 on EOF, so
# the budget must exceed the step count. The loop takes one step per living file
# plus five. python3 rather than `yes x | head -n N`, which dies of SIGPIPE.
STEPS = 900

# A path that is a citation by PATH_PAT and resolves in no tree here.
MISSING = "no/such/file.md"

# NC-4's floors. Measured 2026-08-17: the live corpus is 1109 citations in 177
# living files. These are set near two thirds of that, which is far enough below
# to survive ordinary growth and far enough above zero to catch the failure NC-4
# exists for, which is a port that reads no corpus and reports a clean zero.
# They are floors and never equalities: a literal here would be a stale record by
# the next commit, which is the reason the original cover pinned nothing.
MIN_CITES = 700
MIN_SCANNED = 120

# The eight-file synthetic corpus. Four files are living (`real/target.md`,
# `docs/design/INDEX.md`, `docs/compiler-team-roadmap.md`, `docs/design/a.md`)
# and four are filtered: `site/index.md` by F1, and `CHANGELOG.md`,
# `docs/archive/x.md` and `experiments/runs/x.md` by F2. `docs/design/a.md`
# carries the one baseline citation and is the file most cells rewrite.
BASE = {
    "real/target.md": "body\n",
    "docs/design/INDEX.md": "index\n",
    "docs/compiler-team-roadmap.md": "roadmap\n",
    "CHANGELOG.md": "changelog\n",
    "docs/archive/x.md": "arch\n",
    "experiments/runs/x.md": "runs\n",
    "site/index.md": "site\n",
    "docs/design/a.md": "# a\n\nA resolving citation: `real/target.md` here.\n",
}

# The baseline the mutations move away from: one citation, four living files.
BASE_CITES = 1
BASE_SCANNED = 4

# An entry that IS in the port's ALLOW table, used by cell 16. The pair is
# (citing file, cited path). Cell 16 asserts that the pair is suppressed and that
# the SAME path from a different file is not, which is the specificity half.
# Chosen because the retirement of TOOL-RFC-005 put it there: the roadmap keeps a
# past-tense citation of the reference this port replaced.
ALLOW_FILE = "docs/compiler-team-roadmap.md"
ALLOW_PATH = "scripts/doc_path_lint.py"

FINDING = re.compile(r"^(?P<file>[^\s:]+):(?P<line>\d+)\s+`(?P<path>[^`]+)`$")
SUMMARY = re.compile(r"prose path citations in (?P<scanned>\d+) living files")
CITES = re.compile(r"\(advisory\): (?P<cites>\d+) prose path citations")


class Report:
    """One run of the gate, parsed. `findings` is a list of (file, line, path)."""

    def __init__(self, rc: int, out: str) -> None:
        self.rc = rc
        # Blank lines stripped: the console harness emits one per step, so a raw
        # comparison would be a comparison of step counts. Same reason
        # TOOL-RFC-003's and TOOL-RFC-004's covers strip them.
        self.lines = [ln.rstrip() for ln in out.splitlines() if ln.strip()]
        self.text = "\n".join(self.lines)
        m = CITES.search(self.text)
        self.cites = int(m.group("cites")) if m else -1
        m = SUMMARY.search(self.text)
        self.scanned = int(m.group("scanned")) if m else -1
        self.resolves = "DRIFT-DOC-4: all resolve." in self.text
        self.findings = []
        for ln in self.lines:
            m = FINDING.match(ln.strip())
            if m:
                self.findings.append(
                    (m.group("file"), int(m.group("line")), m.group("path")))


def stage(d: pathlib.Path, edits: dict[str, str] | None = None) -> None:
    """Write the synthetic corpus and put it in a git INDEX.

    The index is not incidental. Decision D2 resolves existence by `git ls-files`
    membership rather than by a filesystem probe, so a file that is written and
    not added does not exist as far as this gate is concerned. No commit is
    needed and none is made: `ls-files` reads the index.
    """
    for rel, text in {**BASE, **(edits or {})}.items():
        p = d / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text, encoding="utf-8")
    subprocess.run(["git", "init", "-q", "."], cwd=d, check=True, env=ENV)
    subprocess.run(["git", "add", "-A"], cwd=d, check=True, env=ENV)


def run(tree: pathlib.Path, gate: str, strict: bool = False) -> Report:
    argv = [gate] + (["--strict"] if strict else [])
    p = subprocess.run(argv, cwd=tree, env=ENV, input="x\n" * STEPS,
                       capture_output=True, text=True)
    return Report(p.returncode, p.stdout + p.stderr)


# --------------------------------------------------------------------- cells --
# Each cell is (name, edits, strict, expectation). `edits` overwrites files in
# BASE or adds new ones. The expectation is a dict checked field by field, so a
# cell that gets the finding count right and the line number wrong still fails.
# Every value below was MEASURED against the port before it was written here.

A = "docs/design/a.md"
CELLS: list[tuple[str, dict[str, str], bool, dict]] = [
    ("1  a citation that does not resolve",
     {A: f"# a\n\nSee `{MISSING}` here.\n"}, False,
     {"findings": [(A, 3, MISSING)], "cites": 1, "scanned": 4, "rc": 0}),

    ("2  the same citation inside a fenced block",
     {A: f"# a\n\n```\nSee `{MISSING}` here.\n```\n"}, False,
     # cites drops to 0: fence stripping removes the citation before it is
     # counted, so a port that forgets FENCE reports 1 finding AND 1 citation.
     {"findings": [], "cites": 0, "scanned": 4, "rc": 0}),

    ("3  the same citation as a BACKTICKED link target",
     {A: f"# a\n\n[label](`{MISSING}`)\n"}, False,
     # The first version of this cell in the RFC used an UNBACKTICKED target and
     # graded nothing, because such a target is not a citation under PATH_PAT at
     # all. The live corpus holds zero backticked targets, so this cell is the
     # only instrument for the LINK rule.
     {"findings": [], "cites": 0, "scanned": 4, "rc": 0}),

    ("4  a label whose link target resolves",
     {A: "# a\n\n[`old/x.md`](INDEX.md)\n"}, False,
     {"findings": [], "cites": 1, "scanned": 4, "rc": 0}),

    ("5  the same label with a target that does not resolve",
     {A: "# a\n\n[`old/x.md`](nope/gone.md)\n"}, False,
     # S3 requires a RESOLVING target. This is the cell that proves it, and it is
     # the pair of cell 4: a port that accepted any label at all passes 4 and
     # fails here.
     {"findings": [(A, 3, "old/x.md")], "cites": 1, "scanned": 4, "rc": 0}),

    ("6  a placeholder path, postmortem-NNN.md",
     {A: "# a\n\nSee `docs/postmortem-NNN.md` here.\n"}, False,
     {"findings": [], "cites": 1, "scanned": 4, "rc": 0}),

    ("7  a historical line, 'moved to'",
     {A: f"# a\n\nIt moved to `{MISSING}` in June.\n"}, False,
     {"findings": [], "cites": 1, "scanned": 4, "rc": 0}),

    ("8  a historical line, 'Previously'",
     {A: f"# a\n\nPreviously `{MISSING}` held it.\n"}, False,
     # Fails a port with no case handling at all.
     {"findings": [], "cites": 1, "scanned": 4, "rc": 0}),

    ("9  a historical line, 'PREVIOUSLY'",
     {A: f"# a\n\nPREVIOUSLY `{MISSING}` held it.\n"}, False,
     # THE CELL THAT HOLDS THE PER-LETTER BRACKET CLASSES HONEST, and one of the
     # two shown to discriminate. A port matching only `previously|Previously`
     # passes cells 7 and 8 and fails here, which is the shortcut D3 forbids.
     # TDFA has no inline `(?i)`, so the bracket classes are the only spelling.
     {"findings": [], "cites": 1, "scanned": 4, "rc": 0}),

    ("10 a stale citation in CHANGELOG.md",
     {"CHANGELOG.md": f"# log\n\nSee `{MISSING}`.\n"}, False,
     # F2, and the citation is not counted either: a filtered file is never
     # scanned, so the count stays at the baseline rather than rising.
     {"findings": [], "cites": 1, "scanned": 4, "rc": 0}),

    ("11 a stale citation under docs/archive/",
     {"docs/archive/x.md": f"# arch\n\nSee `{MISSING}`.\n"}, False,
     {"findings": [], "cites": 1, "scanned": 4, "rc": 0}),

    ("12 a stale citation under a /runs/ directory",
     {"experiments/runs/x.md": f"# runs\n\nSee `{MISSING}`.\n"}, False,
     {"findings": [], "cites": 1, "scanned": 4, "rc": 0}),

    ("13 a stale citation in site/index.md",
     {"site/index.md": f"# site\n\nSee `{MISSING}`.\n"}, False,
     # THE CELL THAT TESTS F1 DELIBERATELY, and the second of the three shown to
     # discriminate. It grades three axes at once: no finding, the citation count
     # unchanged at 1, and the living count unchanged at 4. On the live tree no
     # corpus state can reach this rule at all, because the six files F1 removes
     # hold zero citations between them. Measured caveat: dropping the filter
     # also fails cells 7, 8 and 9 here, on the living count, because BASE always
     # carries a site/ file. This cell is the deliberate instrument, not the only
     # one that would notice.
     {"findings": [], "cites": 1, "scanned": 4, "rc": 0}),

    ("14 a ../ citation that resolves from docs/design/",
     {A: "# a\n\nSee `../compiler-team-roadmap.md`.\n"}, False,
     {"findings": [], "cites": 1, "scanned": 4, "rc": 0}),

    ("15 a ../ citation that does not resolve",
     {A: "# a\n\nSee `../no-such-roadmap.md`.\n"}, False,
     # The `..` fold must resolve and then fail, not fail to parse. A port whose
     # norm-join dropped the fold reports the wrong path text here, so the
     # expectation names the path and not only the count.
     {"findings": [(A, 3, "../no-such-roadmap.md")], "cites": 1, "scanned": 4,
      "rc": 0}),

    ("16 an ALLOW pair, suppressed",
     {ALLOW_FILE: f"# r\n\nSee `{ALLOW_PATH}`.\n"}, False,
     # S5. The RFC's cell 16 deleted an ALLOW entry from BOTH implementations and
     # compared them. With one implementation that mutation needs the port
     # rebuilt, so this cell tests the rule from the input side instead, and cell
     # 16b below supplies the half that a bare suppression cannot: specificity.
     {"findings": [], "cites": 2, "scanned": 4, "rc": 0}),

    ("16b the same path from a file the table does not name",
     {A: f"# a\n\nSee `{ALLOW_PATH}`.\n"}, False,
     # MEASURED, not argued: a port whose ALLOW test reads the PATH alone and
     # ignores the citing file passes cell 16 and fails here. That is the defect
     # cell 16 cannot see, and it is the third cell shown to discriminate.
     {"findings": [(A, 3, ALLOW_PATH)], "cites": 1, "scanned": 4, "rc": 0}),

    ("17 findings with --strict",
     {A: f"# a\n\nSee `{MISSING}` here.\n"}, True,
     # One of two cells where the exit code carries information.
     {"findings": [(A, 3, MISSING)], "cites": 1, "scanned": 4, "rc": 1}),

    ("18 findings without --strict",
     {A: f"# a\n\nSee `{MISSING}` here.\n"}, False,
     # The advisory contract, pinned. This gate decides nothing and must keep
     # deciding nothing: it reports a finding and still exits 0. A change that
     # made DRIFT-DOC-4 fail-closed breaks this cell, which is the intent.
     {"findings": [(A, 3, MISSING)], "cites": 1, "scanned": 4, "rc": 0}),

    ("19 the same missing path twice, 40 lines apart",
     {A: f"# a\n\nSee `{MISSING}` here.\n" + "\n" * 40
         + f"And again `{MISSING}`.\n"}, False,
     # THE REFERENCE QUIRK IS REPRODUCED AND NOT FIXED. The line lookup takes the
     # FIRST line containing the path, so both findings carry line 3 and the
     # second one names a line 40 rows above itself. A port that "corrected" this
     # would fail here, which is what a port that copies its reference means.
     {"findings": [(A, 3, MISSING), (A, 3, MISSING)], "cites": 2, "scanned": 4,
      "rc": 0}),

    ("NC-1 the unmutated corpus", {}, False,
     {"findings": [], "cites": BASE_CITES, "scanned": BASE_SCANNED, "rc": 0}),

    ("NC-2 one more citation that DOES resolve",
     {A: "# a\n\nSee `real/target.md` and `docs/design/INDEX.md`.\n"}, False,
     # The citation count rises by exactly one and the findings stay empty. A
     # port that stopped counting resolving citations passes every mutation cell
     # above and fails here.
     {"findings": [], "cites": BASE_CITES + 1, "scanned": BASE_SCANNED,
      "rc": 0}),

    ("NC-3 one more living file with no citations",
     {"docs/design/b.md": "# b\n\nnothing here.\n"}, False,
     # The living count rises by exactly one and the citation count does not.
     {"findings": [], "cites": BASE_CITES, "scanned": BASE_SCANNED + 1,
      "rc": 0}),
]


def check(rep: Report, expect: dict) -> list[str]:
    """Every field, not the first failure: a cell that gets the count right and
    the line number wrong should say so in one run."""
    bad = []
    if rep.rc != expect["rc"]:
        bad.append(f"exit {rep.rc}, expected {expect['rc']}")
    if rep.cites != expect["cites"]:
        bad.append(f"{rep.cites} citations, expected {expect['cites']}")
    if rep.scanned != expect["scanned"]:
        bad.append(f"{rep.scanned} living files, expected {expect['scanned']}")
    if rep.findings != expect["findings"]:
        bad.append(f"findings {rep.findings}, expected {expect['findings']}")
    # The two tails are mutually exclusive and the summary alone does not say
    # which one printed, so a port that emitted both would pass every count.
    if expect["findings"] and rep.resolves:
        bad.append("printed 'all resolve.' while reporting findings")
    if not expect["findings"] and not rep.resolves:
        bad.append("did not print 'all resolve.' with no findings")
    return bad


def live(repo: pathlib.Path, gate: str) -> list[str]:
    """NC-4: the port over the real repository. Floors only; see the docstring."""
    rep = run(repo, gate)
    bad = []
    if rep.rc != 0:
        bad.append(f"exit {rep.rc}, expected 0")
    if rep.cites < MIN_CITES:
        bad.append(f"{rep.cites} citations, expected at least {MIN_CITES}")
    if rep.scanned < MIN_SCANNED:
        bad.append(f"{rep.scanned} living files, expected at least {MIN_SCANNED}")
    return bad


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--gate", default=os.environ.get("PATHLINT_BIN", ""),
                    help="the PORT binary")
    ap.add_argument("--repo", default=".", help="the repository NC-4 reads")
    ap.add_argument("--only", default="", help="run one cell by leading name")
    a = ap.parse_args()

    if not a.gate:
        print("cover: --gate or PATHLINT_BIN is required", file=sys.stderr)
        return 1
    gate = str(pathlib.Path(a.gate).resolve())
    if not os.access(gate, os.X_OK):
        print(f"cover: --gate is not executable: {gate}", file=sys.stderr)
        return 1
    repo = pathlib.Path(a.repo).resolve()

    cells = [c for c in CELLS
             if not a.only or c[0].split()[0] == a.only]
    run_live = not a.only or a.only == "NC-4"
    if not cells and not run_live:
        print(f"cover: --only {a.only} matched no cell", file=sys.stderr)
        return 1

    bad = 0
    for name, edits, strict, expect in cells:
        with tempfile.TemporaryDirectory(prefix="pl-cover-") as td:
            tree = pathlib.Path(td)
            stage(tree, edits)
            rep = run(tree, gate, strict)
        problems = check(rep, expect)
        if not problems:
            print(f"  ok    {name}")
            continue
        bad += 1
        print(f"  FAIL  {name}")
        for p in problems:
            print(f"        {p}")

    if run_live:
        problems = live(repo, gate)
        if not problems:
            print(f"  ok    NC-4 the live repository, floors "
                  f"{MIN_CITES}/{MIN_SCANNED}")
        else:
            bad += 1
            print("  FAIL  NC-4 the live repository")
            for p in problems:
                print(f"        {p}")

    total = len(cells) + (1 if run_live else 0)
    controls = sum(1 for c in cells if c[0].startswith("NC-")) + \
        (1 if run_live else 0)
    if bad:
        print(f"\nDRIFT-DOC-4 COVER FAIL: {bad} of {total} cell(s) missed "
              f"their expectation")
        return 1
    print(f"\nDRIFT-DOC-4 COVER PASS: {total} cells met their expectation "
          f"({controls} negative controls, {total - controls} mutations)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
