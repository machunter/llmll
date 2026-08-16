#!/usr/bin/env python3
"""TOOL-RFC-006 differential cover: BUILD-GATE-1's shell reference vs its LLMLL port.

RFC: docs/design/tool-rfc-006-build-smoke.md section 6.

Runs `scripts/build_smoke.sh` and `tools/build-smoke/buildsmoke.llmll` over the
same tree and compares their PER-STAGE VERDICTS. Exit codes alone grade almost
nothing here, because the subject exits 0 on fourteen different amounts of work:
a run that stopped after stage 4 and a run that finished stage 10 both exit 0
when nothing failed, so the verdict LINES are the observation and the exit code
is one assertion among several.

THE MUTATION CELLS RUN FIRST AND THE CONTROL RUNS LAST. Section 6 says so and
gives the reason: ports 003 and 004 found real defects only through their
mutation cells, and port 005's cover then passed 22 of 22 on its first run with
two of those cells later shown to be able to fail. A battery whose control is
green and whose mutants were never reached has measured agreement about a
passing tree, which is agreement about almost nothing.

EVERY ASSERTION IS DECLARED BEFORE IT RUNS AND THE UNREACHED ONES ARE PRINTED.
A cell that aborts at its first assertion never evaluates the rest, and a
summary that counted only pass and fail would show that cell as one failure
while three assertions it advertises quietly measured nothing. Each cell names
its assertions up front, the runner records which ones were evaluated, and the
difference is reported. This is the same defect class one level up from the one
the cover exists to catch.

A STAGE THE PORT DOES NOT IMPLEMENT IS REPORTED MISSING, NEVER SKIPPED. The
stage set is taken from the REFERENCE's own output on each run rather than from
a count written here, so a stage added to the subject cannot go ungraded: every
verdict line either keys to a known stage or is reported UNKEYED. The port is
then required to produce a counterpart for each of the reference's stages, and
an absent one is a named MISSING result rather than a shorter list that still
compares equal.

WHAT IS AND IS NOT COMPARED BYTE FOR BYTE. PASS and NOT EXERCISED lines are
compared as text, normalized for whitespace and for the two implementations'
different scratch paths. FAIL lines are NOT: the port appends the child's exit
status and the log path it wrote to, and the reference wraps its prose across
lines. So a failing cell asserts that BOTH sides failed, that both name the same
CAUSE phrase, and that the stages they passed BEFORE failing agree. Both texts
are printed when a cell fails, so a reader adjudicates rather than trusting the
comparison.

TWO DIFFERENCES ARE REAL AND WILL NOT BE REPAIRED, AND THEY ARE LISTED RATHER
THAN COMPARED AWAY. The port prints a verdict line for the W-REPLAY-INIT check
that the reference folds into stage 6, and the two PROC-STDIN-1 PASS lines each
name the feed that side built. A cover that widened its normalizer until those
two stopped showing would also stop grading every other difference in the same
shape. So EXPECTED_DIVERGENCES below names them one at a time, cell 1 tolerates
exactly those two and nothing else, every entry is printed on every run, and an
entry that no longer describes what the two implementations do FAILS as stale.
The list shrinks by failing rather than by someone remembering it is there.

BOTH SIDES GET THE SAME ENVIRONMENT, AND IT CANNOT BE SCRUBBED HERE. 003's cover
let the port inherit a PATH the reference could not see, which compares two
worlds rather than two implementations. This subject needs a Haskell toolchain,
so the minimum environment the sibling covers use would fail stage 1 on both
sides for a reason unrelated to any cell. The caller's environment is passed to
both, unchanged and identical, and the compiler is named explicitly with
--subject rather than left to PATH resolution.

Usage:
    python3 scripts/build_smoke_cover.py --gate <buildsmoke> --subject <llmll>
    python3 scripts/build_smoke_cover.py --static-only     # cells 8, 9, 10

`--slow` and `--no-slow` are both spellable, and `--no-slow` is the default.
The pair exists so a caller can WRITE the choice instead of making it by
omission: CI passes `--no-slow`, and a reader of that step sees which cells it
declined without opening this file.

Exit 0 iff every cell that ran passed. Exit 2 for a usage error, which includes
being asked to run a cell whose inputs were not supplied.
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
from typing import NamedTuple

REPO = Path(__file__).resolve().parents[1]
REF = REPO / "scripts" / "build_smoke.sh"
PORT_SRC = REPO / "tools" / "build-smoke" / "buildsmoke.llmll"

# Cells 9 and 10. Absolute paths on purpose: the port spawns these two by
# absolute path and not through PATH resolution, so the cover asserts the same
# two files the port will actually open.
ENV_BIN = "/usr/bin/env"
UNAME_BIN = "/usr/bin/uname"

# One stdin line per step of the port's console harness. A starved run exits 70,
# which is a budget error rather than a decision (MODE-CLI-1), so the budget is
# generous and the runner asserts 70 did not happen.
BUDGET = 4000

# What the port's PROC-STDIN-1 stage feeds a child, and what stage 5's fixture
# is fed. Not used by the cover directly; recorded here because a cell that
# lowered either would grade nothing (build_smoke.sh:689).


# ---------------------------------------------------------------- stage keys --
# The marker for each stage is text the reference and the port BOTH put in that
# stage's verdict line. Markers are matched in order and the first hit wins, so
# the FS-ENCODING-1 PASS line (which contains "wasi.fs.copy byte-faithful" in
# both of its two spellings) cannot be taken for the NOT EXERCISED line that
# follows it.
#
# THIS TABLE DOES NOT SET THE STAGE COUNT. It pairs lines. The count comes from
# the reference's output on the run, and a verdict line matching no marker is
# reported UNKEYED, which is what stops an eighteenth stage from being dropped
# on the floor the day it is added.
#
# Stages 1, 2 and 2a print no verdict when they pass, so they appear here only
# through the FAIL text of the cells that break them. The control cell cannot
# grade them and says so rather than implying it did.
STAGES: list[tuple[str, str]] = [
    ("4  corroboration",      "fixture compiled through GHC"),
    ("4b REGEX-LOWER-1",      "REGEX-LOWER-1 fixture compiled"),
    ("5  CAP-PROC",           "CAP-PROC operations executed"),
    ("5b FS-ENCODING-1",      "wasi.fs.copy byte-faithful"),
    ("5b FS-ENCODING-1/LC",   "LC_ALL=C encoding claim"),
    ("5c CAPTURE-ENCODING-1", "captureStdout as UTF-8"),
    ("5d JSON-SCALAR-1",      "scalar json-array elements"),
    ("5e PROC-MERGE-1",       "proc.run paths merge both streams"),
    ("PROC-STDIN-1",          "child reads its named stdin path"),
    ("6  REPLAY-FRAME",       "recorded runs replay clean"),
    # The reference folds this check into stage 6's verdict and prints no line
    # of its own for it; the port prints one. Keyed rather than left UNKEYED so
    # that cell 1 reports it as a stage present on one side only, which names
    # what diverged instead of reporting an unrecognised line.
    ("6b W-REPLAY-INIT",      "W-REPLAY-INIT fires"),
    ("7  PROC-BOUNDARY-1",    "argv on RList"),
    ("8  DRIVER-LL 4a-4c",    "DRIVER-LL 4a+4b+4c cover"),
    ("9  DRIVER-LL 4e",       "DRIVER-LL 4e wave cover"),
    ("10 DRIFT-CI-1",         "DRIFT-CI-1 decided by an LLMLL program"),
]

VERDICT = re.compile(r"^BUILD-GATE-1 (PASS|FAIL|NOT EXERCISED): ?(.*)$")


# ------------------------------------------------- expected divergences --
#
# THE TWO DIFFERENCES THE IMPLEMENTATIONS ACTUALLY HAVE, NAMED ONE AT A TIME.
# Neither is a defect and neither is going to be repaired, so the choice is
# between listing them and widening the comparison until they disappear. The
# second choice would also stop grading every other difference of the same
# shape, which is the failure mode this whole file is built against.
#
# Each entry carries the stage, what differs, and the text that identifies the
# difference ON EACH SIDE. Cell 1 does three things with an entry and no more:
# it requires the divergence to still occur exactly as recorded, it excludes
# that ONE stage from the equality assertions, and it prints the entry. A third
# difference, anywhere, still fails.
#
# THE LIST SHRINKS BY FAILING. An entry that no longer describes what the two
# implementations do is reported stale and fails cell 1. So a repaired port
# forces its entry out rather than leaving behind a tolerance nobody revisits,
# and a REWORDED verdict line cannot slip through the hole its own entry opened.
#
# THE TABLE BINDS CELL 1 ONLY, and that is a property of the other cells rather
# than an exemption granted to them: every mutation cell fails at stage 3, 4, 4b
# or 5, so neither stage below is reached and there is nothing there to tolerate.

class Expected(NamedTuple):
    stage: str        # a key from STAGES
    kind: str         # "port-only-stage" or "verdict-text"
    ref_mark: str     # text the reference's line must still carry ("" if none)
    port_mark: str    # text the port's line must still carry
    why: str


EXPECTED_DIVERGENCES: list[Expected] = [
    Expected(
        "6b W-REPLAY-INIT", "port-only-stage", "", "W-REPLAY-INIT fires",
        "the reference runs both W-REPLAY-INIT assertions inside stage 6 and "
        "folds them into that stage's verdict (build_smoke.sh:826-847); the "
        "port prints a verdict of its own for them. Same two assertions, one "
        "extra line"),
    Expected(
        "PROC-STDIN-1", "verdict-text", "12000 lines", "147456 bytes",
        "each side names the feed it built. The reference pipes `printf "
        "'LINE%s\\n' $(seq 12000)`, which is 108894 bytes; the port writes a "
        "file of 147456 bytes by doubling one 9-byte line fourteen times, "
        "because the fixture counts steps and never reads its input. Both are "
        "above the 8 KiB handle buffer the stage exists to defeat, which is the "
        "requirement; the byte count is not"),
]


class Failure(Exception):
    """An assertion that was reached and did not hold."""


class Missing(Exception):
    """What the cell grades is not in the port yet.

    A THIRD OUTCOME, and it exists because two are not enough. A cell whose
    subject has not been written can report `ok` (certifying nothing while
    looking green) or `FAIL` (calling an unfinished port a divergence). Neither
    is true, so this reports MISS, names what is absent, and leaves the cell's
    remaining assertions in the unreached list where a reader sees them.
    """


class Cell:
    """One cell, its declared assertions, and which of them were reached.

    `plans` is written before the body runs. `check` records the name as
    REACHED whether or not it holds, so the report can separate "this did not
    hold" from "this never ran".
    """

    def __init__(self, num: str, why: str, plans: list[str]):
        self.num = num
        self.why = why
        self.plans = plans
        self.reached: list[str] = []
        self.notes: list[str] = []

    def check(self, name: str, cond: bool, msg: str) -> None:
        if name not in self.plans:
            raise SystemExit(f"cover bug: cell {self.num} checks undeclared "
                             f"assertion {name!r}")
        self.reached.append(name)
        if not cond:
            raise Failure(f"[{name}] {msg}")

    def note(self, text: str) -> None:
        self.notes.append(text)

    @property
    def unreached(self) -> list[str]:
        return [p for p in self.plans if p not in self.reached]


# ------------------------------------------------------------------ parsing --

def verdicts(out: str) -> list[tuple[str, str, str]]:
    """(kind, stage, text) for every verdict line, in the order printed.

    Progress lines (`BUILD-GATE-1: building ...`) are dropped: they embed the
    compiler invocation, which is `stack exec llmll --` on one side and a path
    on the other by construction, so comparing them would report a divergence
    that is the CALLER's and not the port's. The reference's diagnostic blocks
    (`BUILD-GATE-1 execution failures:` and its indented detail) are dropped for
    the same reason the sibling covers drop tool chatter: the port answers RErr
    where the shell prints its tools' stderr, and the decision is the verdict.

    A verdict is its FIRST line. The reference wraps its FAIL prose over several
    lines and the port emits one, so the continuation is presentation rather
    than decision, and the cause assertions below read the text of both.
    """
    got = []
    for ln in out.splitlines():
        m = VERDICT.match(ln.rstrip())
        if m is None:
            continue
        kind, text = m.group(1), m.group(2)
        stage = "UNKEYED"
        for name, marker in STAGES:
            if marker in text:
                stage = name
                break
        got.append((kind, stage, text))
    return got


def normalize(text: str, subs: dict[str, str]) -> str:
    """Whitespace collapsed and scratch paths replaced.

    The two implementations are given DIFFERENT work directories on purpose,
    because they would otherwise overwrite each other's artifacts, so any path
    a verdict prints differs by construction. Collapsing whitespace covers the
    other known difference in shape: the reference's messages are wrapped and
    indented and the port's are one line.
    """
    for needle, repl in subs.items():
        if needle:
            text = text.replace(needle, repl)
    return " ".join(text.split())


def passed_stages(vs: list[tuple[str, str, str]]) -> list[str]:
    return [s for k, s, _t in vs if k in ("PASS", "NOT EXERCISED")]


def terminal_fail(vs: list[tuple[str, str, str]]) -> str:
    for kind, _s, text in vs:
        if kind == "FAIL":
            return text
    return ""


# ------------------------------------------------------------- source reads --

def strip_comments(src: str) -> str:
    """LLMLL line comments removed, so a cell counts CALL SITES and not prose.

    The port's header discusses `sh -c` and `/bin/sh` in comments on purpose,
    because D1's superseded option is kept as a record. A raw grep would count
    those and report a call site that does not exist. The cut is made at the
    first `;;` whose prefix holds an even number of quotes, which is exact for
    this file and would misread a `;;` inside a string that also contains an odd
    number of escaped quotes. No such string exists here and a cell that broke
    on one would report a count, not a silent pass.
    """
    out = []
    for ln in src.splitlines():
        i = ln.find(";;")
        while i != -1 and ln[:i].count('"') % 2 == 1:
            i = ln.find(";;", i + 2)
        out.append(ln if i == -1 else ln[:i])
    return "\n".join(out)


def helper_extent(src: str, name: str) -> tuple[int, int] | None:
    """The line range of a top-level `def-shell <name>`, or None if absent.

    The end is the line before the next definition at the same indentation,
    which is how every helper in the port is laid out.
    """
    lines = src.splitlines()
    start = None
    indent = ""
    for i, ln in enumerate(lines):
        m = re.match(r"^(\s*)\(def-shell " + re.escape(name) + r"\b", ln)
        if m:
            start, indent = i, m.group(1)
            break
    if start is None:
        return None
    for j in range(start + 1, len(lines)):
        if re.match(r"^" + indent + r"\(def", lines[j]):
            return (start, j - 1)
    return (start, len(lines) - 1)


def ref_preamble_names() -> list[str]:
    """The wasi_*/json_* names stage 4 requires the emitted preamble to define.

    Read from the reference rather than written here. The list is hand
    maintained in both implementations and the reference's own comment records
    that it has already drifted once: `wasi_fs_copy` was called by the fixture
    for several releases while the guard did not name it.
    """
    src = REF.read_text()
    m = re.search(r"for name in (.*?); do", src, re.S)
    if m is None:
        raise SystemExit("cover: scripts/build_smoke.sh has no `for name in "
                         "... ; do` block, so stage 4's criterion cannot be read")
    return [w for w in m.group(1).replace("\\", " ").split() if w]


def port_preamble_names() -> list[str]:
    src = PORT_SRC.read_text()
    m = re.search(r"\(def-shell preamble-names \[\] -> list\[string\]\s*\[(.*?)\]\)",
                  src, re.S)
    if m is None:
        raise SystemExit("cover: buildsmoke.llmll has no `preamble-names` list, "
                         "so stage 4's criterion cannot be compared")
    return re.findall(r'"([^"]+)"', m.group(1))


def port_build_timeout() -> int | None:
    """The timeout the port hands `wasi.proc.run` for the first build.

    Cell 7 needs it and must not pin it: a cell that slept past a literal
    written here would stop testing anything the day the port changed the
    parameter, which is the anti-hardcoding property version_gate_cover.py
    learned the expensive way.
    """
    src = PORT_SRC.read_text()
    m = re.search(r'\(log-of \(get-s b "work"\)\) \(log-of \(get-s b "work"\)\)'
                  r'\s*(\d+) "/dev/null"', src)
    return int(m.group(1)) if m else None


# -------------------------------------------------------------- the two runs --

def stage_partial(dst: Path) -> Path:
    """A scratch tree holding what the stages up to 5 read, and nothing else.

    The mutation cells all fail at stage 3, 4, 4b or 5, so the fixtures and
    covers that stages 6 to 10 reach are never opened. Copying them would add
    minutes per cell for files no cell reads. THE RISK OF A PARTIAL TREE IS A
    FAILURE FOR THE WRONG REASON, so every mutation cell asserts WHICH stage
    failed and that the stages before it passed, rather than only that the run
    was non-zero.

    `compiler` is a symlink for the same reason refute_crux_cover.py makes one:
    the reference resolves `$REPO_ROOT/compiler` for its stack fallback, and
    copying a build tree is not affordable.
    """
    tree = dst / "tree"
    (tree / "scripts").mkdir(parents=True, exist_ok=True)
    shutil.copy2(REF, tree / "scripts" / REF.name)
    shutil.copytree(REPO / "scripts" / "build-smoke",
                    tree / "scripts" / "build-smoke")
    (tree / "compiler").symlink_to(REPO / "compiler")
    return tree


# THE TWO RUNS ARE SEQUENTIAL AND MUST STAY SO. Stage 5's fixture hardcodes
# /tmp/llmll-capproc-exec, because it declares `(capability read-write "/tmp")`
# and LLMLL had no way to read an environment variable when it was written; the
# reference deletes that directory before it runs. Two implementations running
# at once would each clear the other's scratch, and the cell would report a
# divergence it created. Nothing below runs them in parallel, and this is the
# reason not to.

def run_ref(tree: Path, work: Path, subject: str, env: dict) -> tuple[int, str]:
    e = dict(env)
    e["REPO_ROOT"] = str(tree)
    e["OUTDIR"] = str(work)
    e["KEEP_OUTDIR"] = "1"   # the cover owns the scratch tree and deletes it
    e["LLMLL_BIN"] = subject
    p = subprocess.run(["bash", str(tree / "scripts" / REF.name)],
                       cwd=str(work.parent), env=e,
                       capture_output=True, text=True)
    return p.returncode, p.stdout + p.stderr


def run_port(gate: str, tree: Path, work: Path, rundir: Path, subject: str,
             env: dict) -> tuple[int, str]:
    # cwd is a scratch directory and not the caller's: a console program writes
    # <module>.event-log.jsonl beside wherever it stands, and the port also
    # writes its bs_*.txt redirects there.
    p = subprocess.run([gate, "--subject", subject, "--root", str(tree),
                        "--work", str(work)],
                       cwd=str(rundir), env=env,
                       input="x\n" * BUDGET, capture_output=True, text=True)
    return p.returncode, p.stdout + p.stderr


# ------------------------------------------------------------------- the shim --
#
# Four cells need to control what a build PRODUCED rather than what the tree
# CONTAINED. Stage 4 reads the emitted src/Lib.hs, stage 4b reads another one,
# and stage 5 runs the binary stack reports: all three are regenerated by the
# build, so a mutation planted in the tree beforehand is overwritten before the
# stage that reads it. The shim stands where the compiler stands, delegates
# every invocation to the real one, and changes ONE thing afterwards.
#
# Both implementations accept it the same way: the reference takes it through
# LLMLL_BIN and anchors it at stage 2a because it is already absolute, and the
# port takes it through --subject. Neither is patched for the cell.

SHIM = '''#!/usr/bin/env python3
"""A stand-in compiler, written by scripts/build_smoke_cover.py.

Delegates to the real compiler and then changes one thing about what the build
left behind. See the module comment in the cover for why a post-build change is
the only kind these cells can make.
"""
import os
import shutil
import subprocess
import sys
import time

REAL = {real!r}
MODE = {mode!r}
ARG = {arg!r}
SLEEP = {sleep!r}

argv = sys.argv[1:]


def outdir(a):
    return a[a.index("-o") + 1] if "-o" in a else None


def fixture(a):
    for x in a[1:]:
        if x.endswith(".llmll"):
            return os.path.basename(x)
    return ""


if MODE == "slow" and argv[:1] == ["build"]:
    time.sleep(SLEEP)

rc = subprocess.run([REAL] + argv).returncode
if rc != 0 or argv[:1] != ["build"]:
    sys.exit(rc)

out, fx = outdir(argv), fixture(argv)
lib = os.path.join(out, "src", "Lib.hs") if out else None

if MODE == "drop-def" and fx == "smoke.llmll" and lib and os.path.exists(lib):
    keep = [ln for ln in open(lib).read().splitlines()
            if not ln.startswith(ARG + " ")]
    open(lib, "w").write("\\n".join(keep) + "\\n")

if MODE == "drop-regex-call" and fx == "regex_lower.llmll" \\
        and lib and os.path.exists(lib):
    # Not the hyphenated spelling: that would trip the stage's THIRD assertion
    # and the cell would grade a different one than it names.
    open(lib, "w").write(open(lib).read().replace("regex_match (",
                                                  "regex_match_x ("))

if MODE == "drop-exe" and fx == "capproc_exec.llmll" and out:
    root = subprocess.run(["stack", "path", "--local-install-root"], cwd=out,
                          capture_output=True, text=True).stdout.strip()
    exe = os.path.join(root, "bin", ARG)
    if os.path.exists(exe):
        # The stale binary the cell's second half is about. It WORKS: an
        # implementation that searched the tree instead of asking stack would
        # find it, run it, and report PASS from a build whose own binary is
        # gone.
        stale = os.path.join(out, "stale", "bin")
        os.makedirs(stale, exist_ok=True)
        shutil.copy2(exe, os.path.join(stale, ARG))
        os.remove(exe)

sys.exit(0)
'''


def write_shim(where: Path, subject: str, mode: str, arg: str = "",
               sleep: int = 0) -> str:
    p = where / "llmll-shim"
    p.write_text(SHIM.format(real=subject, mode=mode, arg=arg, sleep=sleep))
    p.chmod(0o755)
    return str(p)


# --------------------------------------------------------------- stale plant --

def plant_stale_artifact(work: Path, names: list[str]) -> None:
    """A complete, plausible stage-4 artifact under a build that will fail.

    Cell 3. The reference's stage 4 tests `^name ` per name and the port tests
    for a newline followed by the name and a space, so the file starts with a
    blank line: without it the two implementations would disagree about the
    FIRST name for a reason that has nothing to do with the cell, and the cell
    would report a divergence it did not create.
    """
    (work / "src").mkdir(parents=True, exist_ok=True)
    body = "\n".join(f"{n} x = undefined" for n in names)
    (work / "src" / "Lib.hs").write_text("\n" + body + "\n")
    (work / ".build.log").write_text("stack build OK\n")


# ------------------------------------------------------------------- the cells --
#
# DECLARATION ORDER IS RUN ORDER, and it is not RFC section 6's numbering.
# Cells 8, 9 and 10 cost nothing and two of them measure preconditions the
# control cell's expectations depend on, so they run first. The mutation cells
# follow. The control runs LAST, which is section 6's rule and the reason is in
# this module's docstring.

REGISTRY: list = []


def cell(num: str, why: str, plans: list[str], needs: str = "run"):
    """`needs` is "static" (no built binaries), "run", or "slow" (opt in)."""
    def deco(fn):
        REGISTRY.append((num, why, plans, fn, needs))
        return fn
    return deco


# --- cell 8 ----------------------------------------------------------------
# RFC section 6 wrote this cell as "grep the port for a `/bin/sh` call site
# outside `drive`". THERE IS NO `drive` HELPER AND THERE WILL NOT BE: D1 was
# superseded on 2026-08-11 when PROC-STDIN-1 gave `wasi.proc.run` a stdin path,
# so the thirteen sites that needed a child's stdin pass a path and the port
# writes no shell string at all. The cell keeps its purpose, which is to bound
# where a process is spawned from, and states the bound the port actually has:
# no shell anywhere, and one single place that spawns /usr/bin/env.
@cell("8", "no /bin/sh anywhere, and one /usr/bin/env call site inside bs-env",
      ["no-shell", "env-helper-present", "one-env-call-site",
       "env-uses-inside-helper"],
      needs="static")
def cell8(c: Cell, _ctx) -> None:
    src = strip_comments(PORT_SRC.read_text())
    lines = src.splitlines()

    shells = [(i + 1, ln.strip()) for i, ln in enumerate(lines)
              if "/bin/sh" in ln or re.search(r'wasi\.proc\.run "(ba)?sh"', ln)]
    c.check("no-shell", not shells,
            f"{len(shells)} shell call site(s) in the port: {shells[:4]}")

    ext = helper_extent(src, "bs-env")
    uses = [i + 1 for i, ln in enumerate(lines) if "/usr/bin/env" in ln]
    if ext is None:
        # NOT a pass. `bs-env` is what stage 5b (FS-ENCODING-1) spawns, so
        # without it the two assertions below have nothing to bind to: a bound
        # certified over zero call sites is a bound over nothing.
        raise Missing(
            f"no `bs-env` helper in {PORT_SRC.name}, and {len(uses)} "
            f"/usr/bin/env occurrence(s). Stage 5b is the only stage that "
            f"spawns it, so `one-env-call-site` and `env-uses-inside-helper` "
            f"are unreached rather than satisfied.")

    c.check("env-helper-present", True, "")
    lo, hi = ext
    outside = [n for n in uses if not (lo + 1 <= n <= hi + 1)]
    c.check("env-uses-inside-helper", not outside,
            f"/usr/bin/env appears outside bs-env at line(s) {outside}")
    sites = [i + 1 for i, ln in enumerate(lines)
             if 'wasi.proc.run "/usr/bin/env"' in ln]
    c.check("one-env-call-site", len(sites) == 1,
            f"expected exactly one `wasi.proc.run \"/usr/bin/env\"` call site, "
            f"found {len(sites)} at {sites}")


# --- cell 9 ----------------------------------------------------------------
# NEW IN THIS COVER. /usr/bin/env was measured on Darwin only, and the port
# spawns it by absolute path to put LC_ALL=C into a child's environment. On a
# host without it the FS-ENCODING-1 stage would fail for a reason no other cell
# names. This cell is what makes the first ubuntu-latest run settle the Linux
# arm instead of raising a question.
@cell("9", "/usr/bin/env exists and is executable on this host",
      ["env-exists", "env-executable"], needs="static")
def cell9(c: Cell, _ctx) -> None:
    p = Path(ENV_BIN)
    c.check("env-exists", p.exists(), f"{ENV_BIN} does not exist")
    c.check("env-executable", os.access(ENV_BIN, os.X_OK),
            f"{ENV_BIN} exists but is not executable")


# --- cell 10 ---------------------------------------------------------------
# NEW IN THIS COVER, and it grades a READ rather than a file. The reference
# branches its FS-ENCODING-1 verdict on `uname -s`, resolved through PATH; the
# port spawns /usr/bin/uname with ["-s"] to reproduce that branch. Two different
# resolutions of the same question is one way a verdict changes without any
# implementation changing, so the cover requires the two answers to be equal
# rather than assuming a shim on PATH is impossible.
@cell("10", "/usr/bin/uname -s answers what the reference's `uname -s` sees",
      ["uname-exists", "uname-executable", "platform-reads-agree"],
      needs="static")
def cell10(c: Cell, ctx) -> None:
    c.check("uname-exists", Path(UNAME_BIN).exists(),
            f"{UNAME_BIN} does not exist")
    c.check("uname-executable", os.access(UNAME_BIN, os.X_OK),
            f"{UNAME_BIN} exists but is not executable")
    absolute = subprocess.run([UNAME_BIN, "-s"], capture_output=True,
                              text=True).stdout.strip()
    onpath = subprocess.run(["uname", "-s"], capture_output=True,
                            text=True).stdout.strip()
    # Recorded BEFORE the assertion, so that a cell 1 running after a failure
    # here compares against the string the port would actually read rather than
    # against an empty default, which would silently choose a branch.
    ctx["platform"] = absolute
    c.note(f"platform is {absolute!r}")
    c.check("platform-reads-agree", absolute == onpath and absolute != "",
            f"the port would read {absolute!r} and the reference reads "
            f"{onpath!r}; the FS-ENCODING-1 branch is chosen by this string")


# --- cell 2 ----------------------------------------------------------------
@cell("2", "a fixture that does not compile: both FAIL stage 3 and name it",
      ["ref-fails", "port-fails", "ref-names-cause", "port-names-cause",
       "prior-stages-agree", "exit-codes-agree"])
def cell2(c: Cell, ctx) -> None:
    tree = stage_partial(ctx["cellroot"])
    smoke = tree / "scripts" / "build-smoke" / "smoke.llmll"
    smoke.write_text(smoke.read_text() + "\n(this is not a form\n")
    differential(c, ctx, tree, ctx["subject"], cause="the fixture does not build")


# --- cell 3 ----------------------------------------------------------------
# THIS CELL EXISTS BECAUSE THE STAGE PROBE PASSED IT WRONGLY (RFC section 4).
# A command's status arrives as the response of the NEXT step, so "run the
# build" and "read what the build produced" are two steps and nothing in the
# language forces the second to consult the first. The RFC's first stage 4b
# printed PASS against a build that exited 1, by reading a complete Lib.hs left
# behind by an earlier good run. The artifact planted here is that Lib.hs.
@cell("3", "a stale artifact under a failing build: both still FAIL",
      ["ref-fails", "port-fails", "ref-names-cause", "port-names-cause",
       "prior-stages-agree", "exit-codes-agree", "artifact-would-satisfy"])
def cell3(c: Cell, ctx) -> None:
    tree = stage_partial(ctx["cellroot"])
    smoke = tree / "scripts" / "build-smoke" / "smoke.llmll"
    smoke.write_text(smoke.read_text() + "\n(this is not a form\n")
    names = ref_preamble_names()
    for w in (ctx["cellroot"] / "ref", ctx["cellroot"] / "port"):
        w.mkdir(parents=True, exist_ok=True)
        plant_stale_artifact(w, names)
    # The trap has to be a real trap: assert the planted artifact WOULD satisfy
    # stage 4 on its own, or the cell tests a build failure twice over.
    lib = (ctx["cellroot"] / "ref" / "src" / "Lib.hs").read_text()
    c.check("artifact-would-satisfy",
            all(f"\n{n} " in lib for n in names),
            "the planted Lib.hs does not define every name stage 4 requires, "
            "so a stage that ignored the build status would fail here anyway "
            "and this cell would grade nothing")
    differential(c, ctx, tree, ctx["subject"], cause="the fixture does not build")


# --- cell 4 ----------------------------------------------------------------
@cell("4", "a definition the corroboration stage names is dropped: both FAIL 4",
      ["name-lists-agree", "ref-fails", "port-fails", "ref-names-cause",
       "port-names-cause", "prior-stages-agree", "exit-codes-agree"])
def cell4(c: Cell, ctx) -> None:
    ref_names, port_names = ref_preamble_names(), port_preamble_names()
    only_ref = [n for n in ref_names if n not in port_names]
    only_port = [n for n in port_names if n not in ref_names]
    # Stage 4's criterion IS this list, so two implementations holding two
    # lists decide two different things and no mutation cell can measure the
    # difference: a name only one side carries produces a divergence on that
    # name and agreement on every other. Asserted here rather than worked
    # around, on version_gate_cover.py's precedent for the seven input files.
    c.check("name-lists-agree", not only_ref and not only_port,
            f"stage 4's name list differs: only in the reference {only_ref}, "
            f"only in the port {only_port}")
    tree = stage_partial(ctx["cellroot"])
    shim = write_shim(ctx["cellroot"], ctx["subject"], "drop-def",
                      arg=ref_names[0])
    differential(c, ctx, tree, shim, cause="is missing a definition for")


# --- cell 5 ----------------------------------------------------------------
@cell("5", "the regex_match prefix is removed from the generated Lib.hs",
      ["ref-fails", "port-fails", "ref-names-cause", "port-names-cause",
       "prior-stages-agree", "exit-codes-agree"])
def cell5(c: Cell, ctx) -> None:
    tree = stage_partial(ctx["cellroot"])
    shim = write_shim(ctx["cellroot"], ctx["subject"], "drop-regex-call")
    # Stage 4b's SECOND assertion, which the subject says does not decay. The
    # fixture still compiles and the preamble still defines regex_match; only
    # the call site is gone, which is the "the builtin is dead again" state.
    differential(c, ctx, tree, shim,
                 cause="no prefix application of regex_match")


# --- cell 6 ----------------------------------------------------------------
@cell("6", "the build succeeds and its binary is gone; a working stale one is "
           "planted elsewhere",
      ["ref-fails", "port-fails", "ref-names-cause", "port-names-cause",
       "prior-stages-agree", "exit-codes-agree"])
def cell6(c: Cell, ctx) -> None:
    tree = stage_partial(ctx["cellroot"])
    shim = write_shim(ctx["cellroot"], ctx["subject"], "drop-exe",
                      arg="capproc-exec")
    # Both halves of the RFC's cell in one mutation: `llmll build` exits 0, the
    # binary stack reports is absent, and a WORKING copy sits deeper in the same
    # out directory. An implementation that searched for the executable rather
    # than asking stack finds the copy and reports PASS from it.
    differential(c, ctx, tree, shim, cause="capproc-exec binary")


# --- cell 7 ----------------------------------------------------------------
# NOT A DIFFERENTIAL CELL, AND THE PLAN SAYS SO. `wasi.proc.run` takes a timeout
# and the shell does not, so there is nothing here for the two to agree about.
# A cover that graded it as agreement would claim a measurement it did not make.
# The reference is still run, and its answer is printed as CONTEXT rather than
# as an expectation.
#
# IT IS OPT IN because of what it costs. The port hands its first build a
# timeout read from its own source below, and the only way to exceed a timeout
# is to exceed it, so the cell's wall clock is that many seconds and no shorter.
# Deferred is not skipped: the runner prints the cell, its reason and its
# unreached assertions either way.
@cell("7", "PORT ONLY: a build that exceeds wasi.proc.run's timeout",
      ["timeout-is-readable", "port-fails", "port-does-not-report-pass"],
      needs="slow")
def cell7(c: Cell, ctx) -> None:
    t = port_build_timeout()
    c.check("timeout-is-readable", t is not None,
            "no timeout argument found on the port's first wasi.proc.run "
            "build, so this cell would sleep against a number written here")
    tree = stage_partial(ctx["cellroot"])
    shim = write_shim(ctx["cellroot"], ctx["subject"], "slow", sleep=t + 15)
    work = ctx["cellroot"] / "port"
    work.mkdir(parents=True, exist_ok=True)
    rundir = ctx["cellroot"] / "run"
    rundir.mkdir(parents=True, exist_ok=True)
    rc, out = run_port(ctx["gate"], tree, work, rundir, shim, ctx["env"])
    vs = verdicts(out)
    c.check("port-fails", rc != 0,
            f"the port exited {rc} on a build that outran its own timeout")
    c.check("port-does-not-report-pass",
            not any(k == "PASS" for k, _s, _t in vs),
            f"the port printed a PASS line for a build it never saw finish: "
            f"{[t for k, _s, t in vs if k == 'PASS']}")
    c.note(f"port timeout {t}s; verdicts {[(k, s) for k, s, _ in vs]}")


# --- cell 1 ----------------------------------------------------------------
# THE CONTROL, AND IT RUNS LAST. It is also the only cell that reaches stages 6
# to 10, so it runs against the LIVE tree: those stages build and run the other
# five ports of this campaign and a partial copy would fail them for the copy's
# reasons.
#
# THE LC_ALL=C LABEL IS OFF. RFC section 6 marked the encoding claim
# REFERENCE-ONLY on Linux, because the port could not set a child's environment
# and would print NOT EXERCISED where the reference settled the claim. That is
# no longer true, measured 2026-08-16: the port sets it by spawning
# /usr/bin/env with the assignment as an argv member, so both implementations
# take the same platform branch and cell 1 expects agreement on every stage,
# FS-ENCODING-1 included. The asymmetry that remains is cell 7's, in the other
# direction, and it is labelled where it lives.
@cell("1", "control: an unmutated tree, both PASS every stage",
      ["ref-passes", "port-passes", "no-unkeyed-verdict", "no-missing-stage",
       "no-extra-stage", "expected-divergences-hold", "verdicts-agree",
       "fs-encoding-branch", "exit-codes-agree"])
def cell1(c: Cell, ctx) -> None:
    tree = ctx["root"]
    refwork = ctx["cellroot"] / "ref"
    portwork = ctx["cellroot"] / "port"
    rundir = ctx["cellroot"] / "run"
    for d in (refwork, portwork, rundir):
        d.mkdir(parents=True, exist_ok=True)

    rc_r, out_r = run_ref(tree, refwork, ctx["subject"], ctx["env"])
    rc_p, out_p = run_port(ctx["gate"], tree, portwork, rundir, ctx["subject"],
                           ctx["env"])
    subs = {str(refwork): "<WORK>", str(portwork): "<WORK>",
            str(tree): "<ROOT>"}

    c.check("ref-passes", rc_r == 0,
            f"the reference rejected an unmutated tree (rc {rc_r}):\n"
            f"        {terminal_fail(verdicts(out_r))}")
    c.check("port-passes", rc_p == 0,
            f"the port rejected an unmutated tree (rc {rc_p}):\n"
            f"        {terminal_fail(verdicts(out_p))}")

    vr, vp = verdicts(out_r), verdicts(out_p)
    unkeyed = [t for k, s, t in vr + vp if s == "UNKEYED"]
    # A verdict line matching no marker is where a new stage would disappear.
    # It is a failure and not a note, because the alternative is a cover that
    # keeps reporting the same fourteen agreements while the subject grew.
    c.check("no-unkeyed-verdict", not unkeyed,
            f"verdict line(s) matching no stage marker, so the cover is not "
            f"grading them: {unkeyed}")

    sr, sp = passed_stages(vr), passed_stages(vp)
    missing = [s for s in sr if s not in sp]
    # A stage the port prints alone is a failure UNLESS the table names it, and
    # the table's entry is then checked below rather than taken on trust.
    port_only = [e.stage for e in EXPECTED_DIVERGENCES
                 if e.kind == "port-only-stage"]
    extra = [s for s in sp if s not in sr and s not in port_only]
    c.check("no-missing-stage", not missing,
            f"the reference reported these stages and the port reported no "
            f"counterpart: {missing}")
    c.check("no-extra-stage", not extra,
            f"the port reported stages the reference did not, and no entry in "
            f"EXPECTED_DIVERGENCES names them: {extra}")

    tr = {s: normalize(t, subs) for k, s, t in vr if k != "FAIL"}
    tp = {s: normalize(t, subs) for k, s, t in vp if k != "FAIL"}

    # EACH TOLERATED DIVERGENCE IS RE-MEASURED BEFORE IT IS TOLERATED, and it is
    # named in the output either way. An entry that no longer holds is reported
    # here rather than in `verdicts-agree`, because the two failures want
    # different repairs: this one says the TABLE is wrong, and that one says the
    # IMPLEMENTATIONS are.
    stale = []
    for e in EXPECTED_DIVERGENCES:
        if e.kind == "port-only-stage":
            if e.stage in sp and e.stage not in sr \
                    and e.port_mark in tp.get(e.stage, ""):
                c.note(f"tolerated divergence, {e.stage}: printed by the port "
                       f"only. {e.why}")
                continue
            stale.append(f"{e.stage}: recorded as printed by the PORT ONLY. "
                         f"reference printed it: {e.stage in sr}; port printed "
                         f"it: {e.stage in sp}; port text: {tp.get(e.stage)!r}")
        else:
            a, b = tr.get(e.stage), tp.get(e.stage)
            if a is not None and b is not None and a != b \
                    and e.ref_mark in a and e.port_mark in b:
                c.note(f"tolerated divergence, {e.stage}: verdict text "
                       f"({e.ref_mark!r} vs {e.port_mark!r}). {e.why}")
                continue
            stale.append(f"{e.stage}: recorded as differing on {e.ref_mark!r} "
                         f"vs {e.port_mark!r}\n"
                         f"          ref : {a}\n          port: {b}")
    c.check("expected-divergences-hold", not stale,
            "an entry in EXPECTED_DIVERGENCES no longer describes what the two "
            "implementations do. Either the difference was repaired, and the "
            "entry must be DELETED, or a verdict line moved, and the entry is "
            "now excusing something it was not written for:\n        "
            + "\n        ".join(stale))

    tolerated = {e.stage for e in EXPECTED_DIVERGENCES
                 if e.kind == "verdict-text"}
    diff = [(s, tr[s], tp[s]) for s in tr
            if s in tp and tr[s] != tp[s] and s not in tolerated]
    c.check("verdicts-agree", not diff,
            "stage verdicts differ:\n" + "\n".join(
                f"        {s}\n          ref : {a}\n          port: {b}"
                for s, a, b in diff))

    # The platform decides which of FS-ENCODING-1's two spellings is correct,
    # and cell 10 measured it. Darwin's GHC resolves UTF-8 whatever LC_ALL says,
    # so the claim is NOT EXERCISED there and settled everywhere else. Asserted
    # on both sides: a port that always printed NOT EXERCISED would agree with
    # the reference on macOS and be wrong in CI.
    plat = ctx.get("platform", "")
    want_lc = plat == "Darwin"
    got_r = "5b FS-ENCODING-1/LC" in sr
    got_p = "5b FS-ENCODING-1/LC" in sp
    c.check("fs-encoding-branch", got_r == want_lc and got_p == want_lc,
            f"on {plat!r} the LC_ALL=C claim should be "
            f"{'NOT EXERCISED' if want_lc else 'settled'} on both sides; "
            f"reference printed the NOT EXERCISED line: {got_r}, port: {got_p}")

    c.check("exit-codes-agree", rc_r == rc_p,
            f"exit codes differ: reference {rc_r}, port {rc_p}")
    c.note(f"{len(sr)} reference stage verdicts graded, "
           f"{len(EXPECTED_DIVERGENCES)} tolerated by name above; stages 1, 2 "
           f"and 2a print none when they pass and are not graded by this cell")


# --------------------------------------------------------- the shared cell body --

def differential(c: Cell, ctx, tree: Path, subject: str, *, cause: str) -> None:
    """Run both over `tree` and require them to fail at the same stage.

    THE EXPECTATION IS CHECKED ON THE REFERENCE FIRST. It defines the
    behaviour, so a cell whose mutant the reference does not catch is a bug in
    the CELL and is reported as one; the port is then required to match. Two
    implementations that both report success are not thereby correct, which is
    what TOOL-ENCODING-1 measured when every mutation cell agreed while both
    sides failed identically for an unrelated reason.
    """
    refwork = ctx["cellroot"] / "ref"
    portwork = ctx["cellroot"] / "port"
    rundir = ctx["cellroot"] / "run"
    for d in (refwork, portwork, rundir):
        d.mkdir(parents=True, exist_ok=True)

    rc_r, out_r = run_ref(tree, refwork, subject, ctx["env"])
    rc_p, out_p = run_port(ctx["gate"], tree, portwork, rundir, subject,
                           ctx["env"])
    vr, vp = verdicts(out_r), verdicts(out_p)
    fr, fp = terminal_fail(vr), terminal_fail(vp)

    c.check("ref-fails", rc_r != 0,
            "the REFERENCE did not catch this mutant, so the cell tests "
            "nothing and the comparison below would be vacuous")
    c.check("port-fails", rc_p != 0,
            f"the port did not catch this mutant.\n"
            f"        reference said: {fr}")
    c.check("ref-names-cause", cause in fr,
            f"the reference failed for a different reason than the cell "
            f"mutates. want {cause!r}, got: {fr}")
    c.check("port-names-cause", cause in fp,
            f"both failed but at different places. want {cause!r}\n"
            f"        reference: {fr}\n        port     : {fp}")

    # The stages that PASSED before the failure. This is what tells a real
    # detection from a run that died early for the scratch tree's own reasons,
    # and it is the assertion a partial staging makes necessary.
    sr, sp = passed_stages(vr), passed_stages(vp)
    c.check("prior-stages-agree", sr == sp,
            f"the two reached different depths before failing:\n"
            f"        reference: {sr}\n        port     : {sp}")
    c.check("exit-codes-agree", rc_r == rc_p,
            f"exit codes differ: reference {rc_r}, port {rc_p}")


# ------------------------------------------------------------------- runner --

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--gate", default=os.environ.get("BUILD_SMOKE_BIN", ""),
                    help="the PORT binary, built from "
                         "tools/build-smoke/buildsmoke.llmll")
    ap.add_argument("--subject", default=os.environ.get("LLMLL_SUBJECT", ""),
                    help="the llmll compiler both implementations drive")
    ap.add_argument("--root", default=str(REPO),
                    help="the repository the control cell runs against")
    ap.add_argument("--work", default="", help="scratch parent (default: temp)")
    ap.add_argument("--static-only", action="store_true",
                    help="run only the cells that need no built binary")
    # BOTH SPELLINGS EXIST SO THE CALLER CAN WRITE THE CHOICE. `--no-slow` is
    # the default and does nothing on its own; what it buys is that the step
    # which declines cell 7 says so where a reader of that step can see it,
    # rather than declining it by omitting a flag.
    ap.add_argument("--slow", action=argparse.BooleanOptionalAction,
                    default=False,
                    help="include cell 7, whose wall clock is the port's own "
                         "build timeout (default: --no-slow)")
    ap.add_argument("--keep", action="store_true")
    a = ap.parse_args()

    if not a.static_only:
        if not a.gate or not a.subject:
            print("ERROR: pass --gate (the built buildsmoke binary) and "
                  "--subject (the llmll compiler), or pass --static-only to "
                  "run the three cells that need neither.", file=sys.stderr)
            return 2
        if not os.access(a.gate, os.X_OK):
            print(f"ERROR: --gate is not executable: {a.gate}", file=sys.stderr)
            return 2

    root = Path(a.root).resolve()
    parent = Path(a.work).resolve() if a.work else Path(
        tempfile.mkdtemp(prefix="build-smoke-cover-"))
    parent.mkdir(parents=True, exist_ok=True)

    # ONE environment, handed to both. See the module docstring for why it is
    # the caller's and not a scrubbed minimum.
    ctx = {"root": root, "gate": a.gate, "subject": a.subject,
           "env": dict(os.environ), "platform": ""}

    npass = nfail = nmiss = 0
    ran: list[str] = []
    deferred: list[tuple[str, str]] = []
    unreached: list[tuple[str, list[str]]] = []
    try:
        for num, why, plans, fn, needs in REGISTRY:
            if needs == "run" and a.static_only:
                deferred.append((num, "--static-only was passed"))
                continue
            if needs == "slow" and not a.slow:
                t = port_build_timeout()
                deferred.append((num, f"opt in with --slow; the port's build "
                                      f"timeout is {t}s and the cell must "
                                      f"outlast it"))
                continue
            if needs == "slow" and a.static_only:
                deferred.append((num, "--static-only was passed"))
                continue

            c = Cell(num, why, plans)
            ran.append(num)
            cellroot = parent / f"cell{num}"
            cellroot.mkdir(parents=True, exist_ok=True)
            ctx["cellroot"] = cellroot
            try:
                fn(c, ctx)
            except Failure as e:
                nfail += 1
                print(f"  FAIL  {num:>3s}  {why}\n        {e}")
            except Missing as e:
                nmiss += 1
                print(f"  MISS  {num:>3s}  {why}\n        {e}")
            else:
                npass += 1
                tail = (f"  ({len(c.unreached)} assertion(s) unreached)"
                        if c.unreached else "")
                print(f"  ok    {num:>3s}  {why}{tail}")
            for n in c.notes:
                print(f"        note: {n}")
            if c.unreached:
                unreached.append((num, c.unreached))
    finally:
        if not a.keep and not a.work:
            shutil.rmtree(parent, ignore_errors=True)
        elif a.keep:
            print(f"  trees kept under {parent}")

    # THE UNREACHED ASSERTIONS ARE READ OFF, which is RFC section 6's
    # instruction and the half a pass/fail count cannot carry. An assertion that
    # never ran measured nothing, and a cover that did not say so would let a
    # cell advertise coverage it did not deliver.
    if unreached:
        print("\nASSERTIONS NEVER REACHED (these measured nothing):")
        for num, names in unreached:
            print(f"  cell {num}: {', '.join(names)}")
    if deferred:
        print("\nCELLS NOT RUN (named, not skipped):")
        for num, reason in deferred:
            print(f"  cell {num}: {reason}")

    # THE TOLERATED DIVERGENCES ARE READ OFF ON EVERY RUN, passing or failing,
    # and whether or not the cell that checks them ran. A difference the cover
    # agreed to allow is part of what the run REPORTS; printed only on failure
    # it would be a narrowing of the comparison that nobody sees while the
    # summary keeps saying the two implementations agree.
    print("\nEXPECTED DIVERGENCES (tolerated by name in cell 1, never dropped):")
    if "1" not in ran:
        print("  cell 1 did not run, so nothing below was measured this time.")
    for e in EXPECTED_DIVERGENCES:
        print(f"  {e.stage}  [{e.kind}]")
        print(f"    reference: {e.ref_mark or '(prints no line for this stage)'}")
        print(f"    port     : {e.port_mark}")
        print(f"    why      : {e.why}")

    # The summary states the three counts every time, so "COVER PASS" cannot be
    # read as "everything was measured". A MISS does not fail the run, because a
    # stage the port has not written is a known state and not a divergence, and
    # it is on the line either way.
    total = npass + nfail + nmiss
    if nfail:
        print(f"\nBUILD-GATE-1 COVER FAIL: {nfail} of {total} cell(s) diverged "
              f"or missed their expectation "
              f"({nmiss} MISSING, {len(deferred)} not run)")
        return 1
    print(f"\nBUILD-GATE-1 COVER PASS: {npass} of {total} cell(s) agree "
          f"({nmiss} MISSING, {len(deferred)} not run)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
