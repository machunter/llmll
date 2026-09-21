"""RUN-STDIN-1: `llmll run` forwards stdin, propagates the child's code, and
passes flag-shaped arguments through.

WHY A PASSING RUN PROVES NOTHING HERE. Every committed `def-main` program is
`:mode console` (20 of 20 at filing time), and a console program is a
stdin-driven step machine. Before this patch `doRun` handed the child `""` as
its stdin, so every one of them took immediate EOF, ran zero steps and exited
70, and `doRun` then reported that 70 as a bare 1. The whole population failed
the same way, so a green suite against the old binary would have been green for
the wrong reason. EACH CELL BELOW WAS RUN AGAINST THE PRE-FIX BINARY AND FAILED.
The measured pre-fix values are named in each cell.

WHAT THE THREE DEFECTS WERE. (i) the trailing `""` of `readProcessWithExitCode`
was the child's stdin; (ii) `ExitFailure _ -> exitFailure` discarded the child's
code and always answered 1; (iii) the pass-through was built from
`many (strArgument ...)` with no `noIntersperse`, so `llmll run p.llmll --root x`
was rejected by our own parser although the help advertised a pass-through.
A fourth, adjacent defect ships with them: the build step's diagnostics went to
stdout, so a redirected run captured a linker failure into the program's own
output file.

WHY IT SKIPS WITHOUT A BINARY. `pytest scripts/tests/` runs in version-gate's
C1-C4 job, which has no Haskell toolchain. The binary-bearing invocation is
wired into the spec-roundtrip job beside test_http_get_1.py, which set the
convention.

WHAT IS NOT GATED, AND WHY. The patch also removes the output buffering:
`readProcessWithExitCode` reads the child to EOF before returning, so a
long-running program's progress was withheld until it exited, and `Inherit`
hands the child the real handle instead. Asserting incremental arrival needs a
timing observation and would be flaky, so that third effect ships ungated and
this docstring is the record of it.

LOCAL NOTE. Each cell drives a real `stack build` of a generated package,
measured at about 6 s against a warm snapshot. On macOS a toolchain SDK
mismatch makes that build fail at the link step; export SDKROOT to a working SDK
before running these locally. The environment is inherited, so an exported
SDKROOT reaches the child.
"""

from __future__ import annotations

import os
import shlex
import stat
import subprocess
import textwrap
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURES = REPO_ROOT / "scripts" / "tests" / "fixtures"

pytestmark = pytest.mark.skipif(
    not os.environ.get("LLMLL_BIN"),
    reason="set LLMLL_BIN to a built llmll; the spec-roundtrip job runs this in CI",
)

# A build plus a run. The build dominates and is about 6 s warm; the budget is
# generous because a cold Stack snapshot on a fresh runner is not.
RUN_TIMEOUT_S = 300

# Two lines, and the second one is what makes the echo observable: the harness
# CONSTRUCTS the terminating step's command without PERFORMING it (RC-4), so a
# program settling on the echoing step prints nothing even with stdin working. The
# fixtures echo on line 1 and settle on line 2.
TWO_LINES = "hello\nbye\n"


def llmll_run(*args: str, stdin: str = "", cwd: Path | None = None):
    """Invoke `llmll run` and return the CompletedProcess."""
    llmll = shlex.split(os.environ["LLMLL_BIN"])
    return subprocess.run(
        [*llmll, "run", *args],
        input=stdin,
        capture_output=True,
        text=True,
        cwd=str(cwd or REPO_ROOT),
        timeout=RUN_TIMEOUT_S,
    )


@pytest.fixture(scope="module")
def echoed():
    """Run the witness once: it echoes stdin line 1 and exits with status 3."""
    return llmll_run(str(FIXTURES / "run_stdin.llmll"), stdin=TWO_LINES)


@pytest.fixture(scope="module")
def echoed_zero():
    """The same shape at status 0, for the `ExitFailure 0` trap."""
    return llmll_run(str(FIXTURES / "run_stdin_zero.llmll"), stdin=TWO_LINES)


# ---------------------------------------------------------------------------
# (i) stdin reaches the program
# ---------------------------------------------------------------------------

def test_rs1_stdin_reaches_the_program(echoed):
    """RS-1. PRE-FIX: stdout was `ready` and nothing else, because the program
    took EOF on the empty stdin and never called :step. `ready` came from :init,
    which runs before the loop, and its presence is what made the old behaviour
    read as "the program ran and failed"."""
    assert "hello" in echoed.stdout, (
        f"stdin did not reach the program; stdout={echoed.stdout!r} "
        f"stderr={echoed.stderr!r}"
    )


def test_rs2_nonzero_status_propagates(echoed):
    """RS-2. PRE-FIX: exit 1. The child exited 70 (the harness's documented EOF
    convention when :done? is declared) and `exitFailure` flattened it. This
    fixture's :status is 3, which is neither 70 nor 1, so a cell that passes
    here cannot be passing on either old value."""
    assert echoed.returncode == 3, (
        f"expected the program's own status 3, got {echoed.returncode}; "
        f"stdout={echoed.stdout!r} stderr={echoed.stderr!r}"
    )


def test_rs3_zero_status_stays_zero(echoed_zero):
    """RS-3. The trap this cell exists for: `exitWith (ExitFailure 0)` is an
    error in GHC, which CodegenHs.hs already records for the generated harness.
    A propagation written without a branch on zero would raise here rather than
    exit cleanly. The stdout assertion rides along so the cell cannot pass on a
    program that never ran."""
    assert echoed_zero.returncode == 0, (
        f"expected 0, got {echoed_zero.returncode}; "
        f"stdout={echoed_zero.stdout!r} stderr={echoed_zero.stderr!r}"
    )
    assert "hello" in echoed_zero.stdout


# ---------------------------------------------------------------------------
# (iii) the flag-shaped pass-through
# ---------------------------------------------------------------------------

def test_rs4_parser_accepts_a_flag_shaped_argument(tmp_path):
    """RS-4. PRE-FIX: ``Invalid option `--root'`` plus the TOP-LEVEL usage, so
    the diagnostic did not even name the command that rejected it.

    The target file does not exist on purpose. This cell grades the parser and
    nothing else, so it must not pay for a build; reaching the file read is
    already proof that the parser let the argument through."""
    missing = tmp_path / "nope.llmll"
    p = llmll_run(str(missing), "--root", "x")
    combined = p.stdout + p.stderr
    assert "Invalid option" not in combined, (
        f"the parser still rejects a flag-shaped pass-through: {combined!r}"
    )


def test_rs5_the_argument_reaches_the_program():
    """RS-5. RS-4 alone would prove the parser and nothing else, which is
    TOOL-ORACLE-1's recorded residue. This fixture performs `wasi.proc.args` in
    :init and prints the vector it receives, so the cell grades delivery.

    PRE-FIX this could not be reached at all: the parser rejected `--root`
    before any program ran."""
    p = llmll_run(str(FIXTURES / "run_stdin_args.llmll"), "--root", "x",
                  stdin=TWO_LINES)
    assert p.returncode == 0, f"stdout={p.stdout!r} stderr={p.stderr!r}"
    assert "--root" in p.stdout, (
        f"the pass-through did not reach the program; stdout={p.stdout!r}"
    )
    assert "NOARGS" not in p.stdout, (
        "the program received a response that was not RList; "
        f"stdout={p.stdout!r}"
    )


# ---------------------------------------------------------------------------
# (iv) build diagnostics leave on stderr
# ---------------------------------------------------------------------------

def test_rs6_build_diagnostics_go_to_stderr(tmp_path):
    """RS-6. PRE-FIX: `TIO.putStr (T.pack berr)` wrote the failed build's
    diagnostics to llmll's STDOUT, so `llmll run p.llmll > out.txt` captured a
    linker failure into the file meant to hold the program's output. Measured
    in this session on a macOS SDK link break.

    A stub `stack` on PATH is the lever, because it makes the build fail for a
    reason this cell controls. The alternative was a fixture whose generated
    Haskell does not compile, which would couple this cell to RESERVED-NAME-1
    and would start passing for the wrong reason the day that row closes."""
    stub_dir = tmp_path / "bin"
    stub_dir.mkdir()
    stub = stub_dir / "stack"
    stub.write_text(textwrap.dedent("""\
        #!/bin/sh
        echo "STUB-BUILD-FAILURE" >&2
        exit 1
        """))
    stub.chmod(stub.stat().st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)

    env = dict(os.environ)
    env["PATH"] = f"{stub_dir}{os.pathsep}{env['PATH']}"
    llmll = shlex.split(os.environ["LLMLL_BIN"])
    p = subprocess.run(
        [*llmll, "run", str(FIXTURES / "run_stdin.llmll")],
        input="", capture_output=True, text=True, cwd=str(REPO_ROOT),
        env=env, timeout=RUN_TIMEOUT_S,
    )

    assert p.returncode != 0, "the stubbed build was supposed to fail"
    assert "STUB-BUILD-FAILURE" in p.stderr, (
        f"the build diagnostic did not reach stderr; stderr={p.stderr!r}"
    )
    assert "STUB-BUILD-FAILURE" not in p.stdout, (
        f"the build diagnostic is still on stdout; stdout={p.stdout!r}"
    )
