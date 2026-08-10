#!/usr/bin/env python3
"""TOOL-RFC-005 differential cover: the LLMLL port of DRIFT-DOC-4 against
scripts/doc_path_lint.py, over a mutation battery.

The RFC is docs/design/tool-rfc-005-doc-path-lint.md §6.

EXIT CODES GRADE ALMOST NOTHING HERE, AND THAT IS THIS GATE'S DEFINING FACT.
DRIFT-DOC-4 is advisory: it exits 0 whatever it finds, unless STRICT is set AND
findings exist. On the live tree even STRICT=1 exits 0, because the zero-findings
tail returns before STRICT is read. So a cover that compared exit codes would
compare two constants and detect nothing. THIS COVER COMPARES STDOUT TEXT, and
checks exit codes only in the two cells built to move them.

MUTATIONS MUST ADD FINDINGS, NOT REMOVE THEM. The corpus reports none, so every
cell either introduces a citation that must be reported or introduces one that a
named suppressor must swallow. Each cell states the finding count the REFERENCE
must produce; the port is then required to match its output exactly. A cell whose
reference does not do what the RFC says is a bug in the cell and is reported as
such rather than tolerated.

BOTH IMPLEMENTATIONS NEED A GIT REPOSITORY, which is what makes this cover's
staging different from TOOL-RFC-004's. The reference locates the tree with
`git rev-parse --show-toplevel` and takes its file list from `git ls-files`; the
port takes both its file list AND its existence oracle from `git ls-files` (RFC
§9 D2). So the scratch tree is a real repository with the fixture files added.
Tracked non-Markdown paths are staged as EMPTY files: nothing reads them, and
both implementations only ask whether they exist.

BOTH SIDES GET THE SAME SCRUBBED ENVIRONMENT. TOOL-RFC-003's cover found an
`llmll` on PATH that its reference could not see and was then comparing two
worlds rather than two implementations.

  --gate    the PORT binary (built from tools/doc-path-lint/pathlint.llmll)
  --repo    the repository to stage from (default: the current one)
"""
import argparse
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

REF = "scripts/doc_path_lint.py"

# No locale on purpose: TOOL-ENCODING-1's acceptance criterion is that the port
# reads UTF-8 in a scrubbed environment rather than one that happens to help.
ENV = {"PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "HOME": "/nonexistent"}


def stage(repo: pathlib.Path, dest: pathlib.Path) -> None:
    """A scratch git repository holding the corpus both sides read."""
    tracked = subprocess.run(["git", "ls-files"], cwd=repo,
                             capture_output=True, text=True).stdout.split()
    for rel in tracked:
        src, dst = repo / rel, dest / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        if rel.endswith(".md") or rel == REF:
            if src.exists():
                shutil.copy2(src, dst)
            else:
                dst.write_text("", encoding="utf-8")
        else:
            # Existence is all either implementation asks of a non-Markdown path.
            dst.touch()
    shutil.copy2(repo / REF, dest / REF)
    subprocess.run(["git", "init", "-q"], cwd=dest, check=True)
    subprocess.run(["git", "add", "-A"], cwd=dest, check=True,
                   capture_output=True)


def add(tree: pathlib.Path, rel: str, text: str) -> None:
    """Write a file AND stage it: an unstaged file is invisible to `git ls-files`,
    so both implementations would ignore the mutation entirely."""
    p = tree / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text, encoding="utf-8")
    subprocess.run(["git", "add", "-f", rel], cwd=tree, check=True,
                   capture_output=True)


def run_ref(tree: pathlib.Path, strict: bool) -> tuple[int, str]:
    env = dict(ENV)
    if strict:
        env["STRICT"] = "1"
    p = subprocess.run([sys.executable, REF], cwd=tree, env=env,
                       capture_output=True, text=True)
    return p.returncode, p.stdout + p.stderr


def run_port(tree: pathlib.Path, gate: str, strict: bool) -> tuple[int, str]:
    # The console harness consumes one stdin line per step and exits 70 on EOF,
    # so the budget must exceed the step count (5 phases + one per living file).
    argv = [gate] + (["--strict"] if strict else [])
    p = subprocess.run(argv, cwd=tree, env=ENV, input="x\n" * 900,
                       capture_output=True, text=True)
    return p.returncode, p.stdout + p.stderr


def norm(s: str) -> list[str]:
    """Blank lines stripped from BOTH sides. The port's console harness emits one
    per step, 177 of them before the report on this corpus, and stripping them
    also removes the blank lines the reference prints deliberately. Measured
    separately: from the first report line onward, with only the harness's
    leading run removed, the two are byte-identical. This is the same
    normalisation TOOL-RFC-003 and 004 use and for the same reason it is not
    called byte-identical here."""
    return [ln.rstrip() for ln in s.splitlines() if ln.strip()]


def findings(out: str) -> int:
    m = re.search(r"DRIFT-DOC-4: (\d+) do not resolve", out)
    if m:
        return int(m.group(1))
    return 0 if "all resolve." in out else -1


# --------------------------------------------------------------------- cells --
# Each mutate() takes the staged tree root. `expect` is the finding count the
# REFERENCE must report. `strict` runs both sides with the flag set.

MISS = "docs/design/no-such-design-doc.md"
DOC = "docs/design/zz-cover.md"


def _plain(t):      add(t, DOC, f"# c\n\nsee `{MISS}` for detail.\n")
def _fenced(t):     add(t, DOC, f"# c\n\n```\nsee `{MISS}` here\n```\n")
def _bt_target(t):  add(t, DOC, f"# c\n\nsee [text](`{MISS}`) here.\n")
def _label_ok(t):   add(t, DOC, f"# c\n\nsee [`{MISS}`](INDEX.md) here.\n")
def _label_bad(t):  add(t, DOC, f"# c\n\nsee [`{MISS}`](also-missing.md) here.\n")
def _ph(t):         add(t, DOC, "# c\n\nsee `docs/postmortem-NNN.md` here.\n")
def _hist_lower(t): add(t, DOC, f"# c\n\nit moved to `{MISS}` last week.\n")
def _hist_cap(t):   add(t, DOC, f"# c\n\nPreviously at `{MISS}`.\n")
def _hist_upper(t): add(t, DOC, f"# c\n\nPREVIOUSLY at `{MISS}`.\n")
def _changelog(t):  add(t, "CHANGELOG.md",
                        (t / "CHANGELOG.md").read_text(encoding="utf-8")
                        + f"\n## x\n\nsee `{MISS}`.\n")
def _archived(t):   add(t, "docs/archive/zz-cover.md", f"# c\n\nsee `{MISS}`.\n")
def _runs(t):       add(t, "experiments/zz/runs/zz-cover.md", f"# c\n\nsee `{MISS}`.\n")
def _site(t):       add(t, "site/zz-cover.md", f"# c\n\nsee `{MISS}`.\n")
def _rel_ok(t):     add(t, DOC, "# c\n\nsee `../compiler-team-roadmap.md` here.\n")
def _rel_bad(t):    add(t, DOC, "# c\n\nsee `../no-such-file-at-all.md` here.\n")
# ALLOW is keyed on (file, path). Citing an ALLOW-listed PATH from a different
# FILE must still be reported, which is what proves the key is the pair. The
# RFC's original cell removed an entry from both implementations; the port
# compiles its table in (D5), so that cell would need a rebuild mid-run and this
# one tests the same property without one.
def _allow_wrong_file(t):
    add(t, DOC, "# c\n\nsee `src/Lib.hs` here.\n")
def _twice(t):
    add(t, DOC, f"# c\n\nsee `{MISS}` once.\n" + "\nfiller\n" * 40 + f"\nand `{MISS}` again.\n")
def _resolves(t):   add(t, DOC, "# c\n\nsee `docs/design/INDEX.md` here.\n")
def _no_cites(t):   add(t, DOC, "# c\n\nnothing cited here at all.\n")
def _clean(t):      pass


CELLS = [
    ("1  missing path is reported",            1, _plain,           False),
    ("2  fenced block is not scanned",         0, _fenced,          False),
    ("3  backticked link TARGET blanked",      0, _bt_target,       False),
    ("4  label whose target resolves",         0, _label_ok,        False),
    ("5  label whose target does not",         1, _label_bad,       False),
    ("6  PLACEHOLDER suppresses",              0, _ph,              False),
    ("7  HIST_LINE 'moved to'",                0, _hist_lower,      False),
    ("8  HIST_LINE 'Previously' (case)",       0, _hist_cap,        False),
    ("9  HIST_LINE 'PREVIOUSLY' (all caps)",   0, _hist_upper,      False),
    ("10 CHANGELOG.md is historical",          0, _changelog,       False),
    ("11 docs/archive/ is historical",         0, _archived,        False),
    ("12 a /runs/ dir is historical",          0, _runs,            False),
    ("13 site/ is filtered",                   0, _site,            False),
    ("14 ../ path that resolves",              0, _rel_ok,          False),
    ("15 ../ path that does not",              1, _rel_bad,         False),
    ("16 ALLOW is keyed on (file, path)",      1, _allow_wrong_file, False),
    ("17 --strict exits 1 with findings",      1, _plain,           True),
    ("18 no --strict exits 0 with findings",   1, _plain,           False),
    ("19 same path twice, first line both",    2, _twice,           False),
    ("NC-1 unmutated tree",                    0, _clean,           False),
    ("NC-2 a citation that resolves",          0, _resolves,        False),
    ("NC-3 a living file with no citations",   0, _no_cites,        False),
]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--gate", required=True, help="the PORT binary")
    ap.add_argument("--repo", default=".", help="repository to stage from")
    # For the cover's OWN negative control: run a subset against a deliberately
    # broken port and check that the cells which should fail do. A battery that
    # has never been shown to fail is not evidence, and this campaign has twice
    # shipped a cell that could not fail (TOOL-RFC-004, REGEX-LOWER-1).
    ap.add_argument("--only", default=None,
                    help="run only cells whose name contains this substring")
    a = ap.parse_args()

    repo = pathlib.Path(a.repo).resolve()
    gate = str(pathlib.Path(a.gate).resolve())
    if not os.access(gate, os.X_OK):
        print(f"cover: --gate is not executable: {gate}", file=sys.stderr)
        return 1

    cells = [c for c in CELLS if a.only is None or a.only in c[0]]
    if not cells:
        print(f"cover: --only {a.only!r} matched no cell", file=sys.stderr)
        return 1

    bad = 0
    for name, expect, mutate, strict in cells:
        with tempfile.TemporaryDirectory(prefix="dpl-cover-") as td:
            tree = pathlib.Path(td)
            stage(repo, tree)
            mutate(tree)
            rc_r, out_r = run_ref(tree, strict)
            rc_p, out_p = run_port(tree, gate, strict)

        n_r, n_p = findings(out_r), findings(out_p)
        agree = norm(out_r) == norm(out_p) and rc_r == rc_p
        # Cell 17 is the ONE cell in which an exit code carries information.
        rc_ok = (rc_r == 1) if strict and expect else (rc_r == 0)
        ok = n_r == expect and agree and rc_ok

        if ok:
            print(f"  ok    {name:42s} both {n_r} finding(s), rc={rc_r}")
        else:
            bad += 1
            print(f"  FAIL  {name:42s} ref={n_r}(rc={rc_r}) port={n_p}(rc={rc_p})"
                  f" expected={expect} agree={agree}")
            if not agree:
                import difflib
                for ln in list(difflib.unified_diff(
                        norm(out_r), norm(out_p), "reference", "port",
                        lineterm=""))[:16]:
                    print(f"        {ln}")

    total = len(CELLS)
    controls = sum(1 for c in CELLS if c[0].startswith("NC-"))
    if bad:
        print(f"\nDRIFT-DOC-4 COVER FAIL: {bad} of {total} cell(s) diverged "
              f"or missed their expectation")
        return 1
    print(f"\nDRIFT-DOC-4 COVER PASS: {total} cells agree "
          f"({controls} negative controls, {total - controls} mutations)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
