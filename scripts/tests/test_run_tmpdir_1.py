"""RUN-TMPDIR-1: `llmll run` builds into a directory keyed on the source
file's IDENTITY, so two files that share a basename no longer run each other.

WHAT THE DEFECT WAS. `doRun` built into `"/tmp/llmll-run-" <> takeBaseName fp`
(`compiler/app/Main.hs`, the `tmpDir` binding), so two DIFFERENT source files
with one basename shared one directory and one `.stack-work`. Each run rewrites
`src/Lib.hs` and `src/Main.hs`, so a sequential A-then-B is correct and the
defect needs concurrency: the loser of the race built or executed the other
program. Measured when the row was filed, over six concurrent trials of two
same-basename programs: six of six wrong, five of them silently. Measured
again here against the pre-fix binary, over the four trials this file runs:
FIVE of eight invocations answered for the wrong program. Three printed the
other program's marker and exited with the other program's status, with
nothing in either stream to say so. Two failed at exit 1 when `ghc-pkg init`
found the package database already there.

WHY A CONCURRENT CELL IS NOT ENOUGH ON ITS OWN. A passing concurrent run is an
absence of failure. Two stack builds can serialize on the shared `~/.stack`
lock, and a serialized pair removes the variable the cell exists to test, which
is `VERDICT-UNSTABLE-1`'s recorded mistake in another form. RT-2 therefore
grades the MECHANISM and not the outcome: it counts the build directories and
compares the generated `src/Lib.hs` bytes. Before the patch there is ONE
directory; after it there are TWO with different contents. That cell cannot
pass for a scheduling reason.

WHAT EACH CELL DID AGAINST THE PRE-FIX BINARY, measured and not assumed.
RT-1 FAILED (five of eight invocations wrong) and RT-2 FAILED (one directory,
`/tmp/llmll-run-collide`). RT-3 PASSED, and that is correct: it pins a
property the patch must PRESERVE, not one the patch introduces. A fresh
temporary directory per run would fix the collision and fail RT-3, so the cell
is a pin against that repair and is not evidence for this one. The measured
pre-fix values are named in each cell.

WHY IT SKIPS WITHOUT A BINARY. `pytest scripts/tests/` runs in version-gate's
C1-C4 job, which has no Haskell toolchain. `llmll run` drives a real `stack
build`, so the binary-bearing invocation is wired into the spec-roundtrip job
beside test_run_stdin_1.py, which set the convention.

LOCAL NOTE. Each trial drives two `stack build` runs of generated packages,
about 6 s each warm. On macOS a toolchain SDK mismatch makes that build fail at
the link step; export SDKROOT to a working SDK before running these locally.
The environment is inherited, so an exported SDKROOT reaches the child.
"""

from __future__ import annotations

import glob
import os
import shlex
import shutil
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURES = REPO_ROOT / "scripts" / "tests" / "fixtures" / "run_tmpdir"
PROG_A = FIXTURES / "a" / "collide.llmll"
PROG_B = FIXTURES / "b" / "collide.llmll"

# Both fixtures are named collide.llmll. The pre-fix key was the basename, so
# the old directory is exactly this path and the new ones carry a hash suffix.
OLD_DIR = "/tmp/llmll-run-collide"
DIR_GLOB = "/tmp/llmll-run-collide*"

pytestmark = pytest.mark.skipif(
    not os.environ.get("LLMLL_BIN"),
    reason="set LLMLL_BIN to a built llmll; the spec-roundtrip job runs this in CI",
)

# A build plus a run, twice over, and the build dominates.
RUN_TIMEOUT_S = 300

# Two lines: the console harness constructs the terminating step's command
# without performing it (RC-4), so the fixtures echo their marker on line 1 and
# settle on line 2.
TWO_LINES = "one\ntwo\n"

TRIALS = 4


def _spawn(prog: Path) -> subprocess.Popen:
    llmll = shlex.split(os.environ["LLMLL_BIN"])
    return subprocess.Popen(
        [*llmll, "run", str(prog)],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        cwd=str(REPO_ROOT),
    )


def _run_pair_concurrently():
    """Start both programs, then feed both. Returns (a_result, b_result)."""
    pa = _spawn(PROG_A)
    pb = _spawn(PROG_B)
    outs = {}
    try:
        outs["a"] = pa.communicate(TWO_LINES, timeout=RUN_TIMEOUT_S)
    finally:
        outs["b"] = pb.communicate(TWO_LINES, timeout=RUN_TIMEOUT_S)
    return (
        (pa.returncode, outs["a"][0], outs["a"][1]),
        (pb.returncode, outs["b"][0], outs["b"][1]),
    )


def _build_dirs():
    return sorted(d for d in glob.glob(DIR_GLOB) if os.path.isdir(d))


@pytest.fixture(scope="module")
def concurrent_trials():
    """The whole measurement, run once: TRIALS concurrent pairs.

    The wipe comes first, so a stale directory from an earlier binary cannot
    make RT-2 read the wrong count."""
    for d in _build_dirs():
        shutil.rmtree(d, ignore_errors=True)
    return [_run_pair_concurrently() for _ in range(TRIALS)]


# ---------------------------------------------------------------------------
# The outcome cell
# ---------------------------------------------------------------------------

def test_rt1_each_invocation_answers_its_own_program(concurrent_trials):
    """RT-1. PRE-FIX: five of these eight invocations wrong. Three printed the
    other program's marker and exited with the other program's status; two
    failed at exit 1 inside a Stack build that collided in the shared
    directory.

    The four values are chosen so no cell can pass on a coincidence: A is
    I-AM-A at status 3, B is I-AM-B at status 4, and neither status is 1 (the
    old flattened failure) or 70 (the console harness's EOF convention)."""
    wrong = []
    for i, ((ca, oa, ea), (cb, ob, eb)) in enumerate(concurrent_trials, start=1):
        if ca != 3 or "I-AM-A" not in oa or "I-AM-B" in oa:
            wrong.append(f"trial {i} A: code={ca} stdout={oa!r} stderr={ea[-400:]!r}")
        if cb != 4 or "I-AM-B" not in ob or "I-AM-A" in ob:
            wrong.append(f"trial {i} B: code={cb} stdout={ob!r} stderr={eb[-400:]!r}")
    assert not wrong, (
        f"{len(wrong)} of {2 * TRIALS} concurrent invocations answered for the "
        "wrong program:\n" + "\n".join(wrong)
    )


# ---------------------------------------------------------------------------
# The mechanism cells. These cannot pass for a scheduling reason.
# ---------------------------------------------------------------------------

@pytest.mark.usefixtures("concurrent_trials")
def test_rt2_two_files_get_two_build_directories():
    """RT-2. PRE-FIX: exactly ONE directory, /tmp/llmll-run-collide, holding
    whichever program wrote last. This is the cell that grades the fix itself:
    two directories, and the generated Lib.hs in each names its own program."""
    dirs = _build_dirs()
    assert OLD_DIR not in dirs, (
        f"{OLD_DIR} is the pre-fix basename-keyed directory and it is back"
    )
    assert len(dirs) == 2, (
        f"expected two identity-keyed build directories, found {len(dirs)}: {dirs}"
    )

    # The marker is in the generated LIBRARY: Lib.hs carries the program's
    # own functions and Main.hs is the console harness, which is the same for
    # both fixtures. Reading Main.hs finds neither marker.
    sources = {}
    for d in dirs:
        main_hs = Path(d) / "src" / "Main.hs"
        lib_hs = Path(d) / "src" / "Lib.hs"
        assert main_hs.is_file(), f"{main_hs} is missing"
        assert lib_hs.is_file(), f"{lib_hs} is missing"
        sources[d] = lib_hs.read_text()

    markers = {d: ("I-AM-A" in s, "I-AM-B" in s) for d, s in sources.items()}
    assert sorted(markers.values()) == [(False, True), (True, False)], (
        "the two build directories do not hold the two different programs: "
        f"{markers}"
    )


@pytest.mark.usefixtures("concurrent_trials")
def test_rt3_the_same_file_reuses_one_directory():
    """RT-3. The key is a hash and not a fresh temporary directory, so /tmp
    holds one directory per source file rather than one per run and the
    .stack-work cache survives between runs of the same file. That cache is
    what makes a warm `llmll run` cost about 6 s instead of a cold build.

    TRIALS runs of each fixture have already happened above, so a per-run key
    would have left 2 * TRIALS directories behind.

    THIS CELL PASSED PRE-FIX and is a pin rather than evidence: the old
    basename key also reused one directory. It fails against the other
    plausible repair, a fresh temporary directory per run."""
    before = _build_dirs()
    llmll = shlex.split(os.environ["LLMLL_BIN"])
    p = subprocess.run(
        [*llmll, "run", str(PROG_A)],
        input=TWO_LINES, capture_output=True, text=True,
        cwd=str(REPO_ROOT), timeout=RUN_TIMEOUT_S,
    )
    assert p.returncode == 3, f"stdout={p.stdout!r} stderr={p.stderr[-400:]!r}"
    assert _build_dirs() == before, (
        f"the run added a build directory: {before} -> {_build_dirs()}"
    )
