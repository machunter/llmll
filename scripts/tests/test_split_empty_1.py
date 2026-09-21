"""SPLIT-EMPTY-1: `(string-split "" subject)` answers `[subject]` instead of
producing an infinite list of empty strings.

WHAT THE DEFECT WAS. The emitted preamble guarded the general equation on
``sep `isPrefixOf` s`` and recursed on `drop (length sep) s`. For an empty
separator `isPrefixOf ""` is always True and `drop 0 s` is `s`, so `go`
produced `"" : go s` forever. The list is infinite rather than bottom, which is
why the two cells below grade two DIFFERENT observations.

MEASURED AGAINST THE PRE-FIX BINARY (v0.23.15), not predicted:

  value.llmll   HEAD=[] COMMA=2 EMPTY=1     terminates, WRONG head
  spine.llmll   SPINE=                      prints the prefix, then hangs

THE VALUE CELL IS THE STRONGER HALF. `list_head` is lazy in the emitted
preamble, so it answers the head of the infinite list and returns. The pre-fix
answer is "" and the post-fix answer is "abc". Both arrive at once, so this
cell discriminates the fix BY VALUE on a program that terminates either way. No
timeout grades it.

THE SPINE CELL REPRODUCES WHAT A USER HITS: a built program that hangs with no
diagnostic on any check-time channel. It is kept even though a timeout is
weaker evidence, and it is strengthened by reading stdout: the pre-fix binary
emits `SPINE=` and never the digit, so the cell asserts the DIGIT rather than
mere termination. A build that failed, or a program that never started, does
not produce that prefix.

THE BUILD IS SEPARATED FROM THE RUN for the spine cell. `llmll build -o` runs
unbounded, and only the produced executable runs under a short timeout, so the
timeout measures runtime and never build time. The value cell can use `llmll
run` because it terminates on both binaries.

On macOS a toolchain SDK mismatch makes the link step fail. MacOSX27.0.sdk
ships .tbd files the linker rejects ("unknown architecture"); export SDKROOT to
MacOSX26.5.sdk before running these locally. The environment is inherited, so
an exported SDKROOT reaches the child.
"""

from __future__ import annotations

import glob
import os
import shlex
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURES = REPO_ROOT / "scripts" / "tests" / "fixtures" / "split_empty"
VALUE_PROG = FIXTURES / "value.llmll"
SPINE_PROG = FIXTURES / "spine.llmll"

pytestmark = pytest.mark.skipif(
    not os.environ.get("LLMLL_BIN"),
    reason="set LLMLL_BIN to a built llmll; the spec-roundtrip job runs this in CI",
)

# A build plus a run, and the build dominates.
BUILD_TIMEOUT_S = 600

# The built spine executable alone. Pre-fix it never returns; post-fix it
# answers immediately. Ten seconds separates those two cases by a wide margin.
RUN_TIMEOUT_S = 10

# Two stdin lines by design: the console harness CONSTRUCTS the terminating
# step's command without PERFORMING it (RC-4).
TWO_LINES = "one\ntwo\n"


def _llmll() -> list[str]:
    return shlex.split(os.environ["LLMLL_BIN"])


@pytest.fixture(scope="module")
def value_output() -> str:
    """`llmll run` on the value program. Terminates on either binary."""
    p = subprocess.run(
        [*_llmll(), "run", str(VALUE_PROG)],
        input=TWO_LINES,
        capture_output=True,
        text=True,
        timeout=BUILD_TIMEOUT_S,
        cwd=str(REPO_ROOT),
    )
    assert p.returncode == 0, f"llmll run failed rc={p.returncode}\n{p.stderr[-2000:]}"
    return p.stdout


@pytest.fixture(scope="module")
def spine_exe(tmp_path_factory) -> str:
    """Build the spine program. The build is unbounded relative to the run."""
    out = tmp_path_factory.mktemp("spine-build")
    p = subprocess.run(
        [*_llmll(), "build", str(SPINE_PROG), "-o", str(out)],
        capture_output=True,
        text=True,
        timeout=BUILD_TIMEOUT_S,
        cwd=str(REPO_ROOT),
    )
    assert p.returncode == 0, f"llmll build failed rc={p.returncode}\n{p.stderr[-2000:]}"
    exes = glob.glob(str(out / ".stack-work" / "install" / "*" / "*" / "*" / "bin" / "spine"))
    assert exes, f"no spine executable under {out}"
    return exes[0]


def test_se1_empty_separator_answers_the_subject(value_output):
    """The discriminating cell. Pre-fix this reads HEAD=[]."""
    assert "HEAD=[abc]" in value_output, (
        "expected the empty separator to answer [\"abc\"]; "
        f"got {value_output!r}. HEAD=[] is the pre-fix answer."
    )


def test_se2_the_general_equation_is_not_shadowed(value_output):
    """A regression guard. The new equation sits above the general one."""
    assert "COMMA=2" in value_output, f"(string-split \",\" \"a,b\") moved: {value_output!r}"


def test_se3_an_empty_subject_is_unchanged(value_output):
    """A regression guard. This call already terminated by the first equation."""
    assert "EMPTY=1" in value_output, f"(string-split \"\" \"\") moved: {value_output!r}"


def test_se4_forcing_the_spine_terminates(spine_exe):
    """The defect itself. Pre-fix this prints SPINE= and never returns."""
    try:
        p = subprocess.run(
            [spine_exe], input=TWO_LINES, capture_output=True, text=True,
            timeout=RUN_TIMEOUT_S,
        )
    except subprocess.TimeoutExpired as e:
        got = e.stdout.decode() if isinstance(e.stdout, bytes) else (e.stdout or "")
        pytest.fail(
            f"the built program did not terminate in {RUN_TIMEOUT_S}s; "
            f"stdout so far = {got!r} (pre-fix this is 'SPINE=')"
        )
    assert "SPINE=1" in p.stdout, (
        f"expected the spine of (string-split \"\" \"abc\") to have one element; "
        f"got {p.stdout!r}"
    )
