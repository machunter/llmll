"""The refute-crux gate must refuse an undecidable corpus, not grade it.

WHAT THIS PINS. `llmll verify` proves nothing on its own: it shells out to
`fixpoint`, which shells out to z3. Absent either, it exits 3 — "solver
unavailable (proof did not run)", compiler/app/Main.hs:1386 — for every case
whose verdict needs a proof.

Before the preflight this file pins, the gate ran its whole loop anyway and
counted each exit 3 as a diverged frozen verdict. Its first Linux CI run
therefore printed `78 frozen verdict(s) diverged` when ZERO had diverged, and
the closing line pointed whoever read it at a verification regression that did
not exist. The 2 that "passed" were the only two whose verdict is reached before
the solver runs, which is what identified the cause.

THIS FILE TESTED THE SHELL REFERENCE UNTIL 2026-08-17 AND IT TESTS THE PORT NOW.
`scripts/refute-crux-gate.sh` was deleted when TOOL-RFC-002 moved to
`tool_state: retired`. The four assertions carried over unchanged in substance,
because the port grew the same preflight for the same reason: the divergence
where one implementation refused by name and the other graded undecidable
verdicts is recorded in the restart record section 8 and was closed in
tools/refute-crux/refutecrux.llmll.

WHAT THE MOVE COSTS, and it is the same cost TOOL-RFC-004 and TOOL-RFC-005 paid
before it. The reference needed bash and nothing else, so this test ran in the
`version-gate` job, which is deliberately toolchain-free and finishes in seconds.
The port must be BUILT, so the test now skips unless REFUTE_CRUX_BIN names a
built binary, and CI sets that in `spec-roundtrip` after the build step. A missing
solver preflight is a one-line environment fault and it now surfaces behind a
Haskell build, minutes rather than seconds. That is the third condition in the
campaign's retirement rule being paid rather than waived.

WHY A PATH TEST AND NOT A CORPUS RUN. The property is about what the gate does
when it CANNOT decide, so the test has to produce a host where it cannot. It
does that by removing the solver from PATH rather than by uninstalling anything,
which keeps the test hermetic. The port exits at the preflight, before it reads a
single manifest.

The negative direction is the one that matters and it is the one asserted: a
missing solver must produce a REFUSAL naming the tool, and must NOT produce a
verdict tally. Asserting the absence of the tally is the actual regression
guard; a later change that restores grading-without-a-solver would still exit
non-zero and would slip past a bare exit-code check.
"""

from __future__ import annotations

import os
import pathlib
import shutil
import subprocess
import tempfile

import pytest

REPO = pathlib.Path(__file__).resolve().parents[2]

# The port, built. Same contract as scripts/refute_crux_cover.py, which reads the
# same two variables, so one CI step sets both and this test and the cover agree
# on what they are pointed at.
GATE = os.environ.get("REFUTE_CRUX_BIN", "")
SUBJECT = os.environ.get("LLMLL_SUBJECT", "")

needs_port = pytest.mark.skipif(
    not GATE or not SUBJECT,
    reason="set REFUTE_CRUX_BIN and LLMLL_SUBJECT; the spec-roundtrip job does",
)

# Forty is not generous, it is deliberate. The port performs one Command per
# stdin line, and a run that reaches the preflight and refuses needs three: parse
# argv, probe fixpoint, print. A budget in the thousands would let a port that
# SILENTLY SKIPPED the preflight run the whole corpus and still be measured by
# the assertions below, which would report a pass for the wrong reason. Starved
# at forty, a port that begins grading exits 70 and every assertion here fails.
BUDGET = 40

# What the PORT prints when it grades. The reference printed a suite header as
# `▸ <path>` and each case as `✅`/`❌ <label>`; the port writes `> <path>` and
# `  PASS `/`  FAIL ` before each label, which scripts/refute_crux_cover.py's
# `normalise` documents and depends on. Carrying the reference's three markers
# over to a port that never emits them would have left this test asserting the
# absence of characters no program writes, which passes for free and pins nothing.
GRADING_MARKERS = ("> ", "  PASS ", "  FAIL ")

# The budget for the ordering test, and it is deliberately the opposite of the one
# above. MEASURED, and the measurement is why this constant exists: starved at
# forty with the solver present, the port printed NOTHING AT ALL and exited 70. A
# console step performs exactly one Command, so the port accumulates its whole
# report and emits it once at the end, where the reference streamed each suite and
# each case as it went. So under a small budget the absence of a grading marker
# proves NOTHING: a port that skipped the preflight and began grading would be
# killed before it printed anything, and the assertion would pass for a reason
# that has nothing to do with ordering.
#
# Generous, therefore, so that a preflight-skipping port RUNS TO ITS REPORT and
# reveals itself. On a solver-less host with the preflight in place this budget
# costs nothing: the refusal is reached at the third step and the remaining lines
# go unread. In the counterfactual the run may instead exceed the timeout below,
# which raises and fails the test, and that is also the correct answer.
ORDERING_BUDGET = 4000


def _path_without(tool: str) -> str:
    """PATH with every directory that provides `tool` removed.

    Removing directories rather than pointing PATH at a stub keeps the rest of
    the environment reachable, so the gate gets as far as the solver check
    instead of failing earlier for an unrelated reason.
    """
    keep = []
    for d in os.environ.get("PATH", "").split(os.pathsep):
        if not d:
            continue
        if shutil.which(tool, path=d) is None:
            keep.append(d)
    return os.pathsep.join(keep)


def _run_gate(path_value: str, budget: int = BUDGET) -> subprocess.CompletedProcess:
    """Run the port from a scratch cwd, with the repo as --root.

    The cwd matters: a console program writes <module>.event-log.jsonl into its
    working directory, so running from the repo would leave a file behind on
    every test. Same reason the CI step for this gate runs from a scratch dir.
    """
    env = dict(os.environ, PATH=path_value)
    with tempfile.TemporaryDirectory(prefix="rc-preflight-") as td:
        work = pathlib.Path(td) / "work"
        run = pathlib.Path(td) / "run"
        work.mkdir()
        run.mkdir()
        return subprocess.run(
            [GATE, "--root", str(REPO), "--subject", SUBJECT, "--work", str(work)],
            cwd=str(run),
            env=env,
            input="x\n" * budget,
            capture_output=True,
            text=True,
            timeout=120,
        )


@needs_port
def test_port_binary_is_executable():
    assert os.access(GATE, os.X_OK), f"REFUTE_CRUX_BIN is not executable: {GATE}"


@needs_port
@pytest.mark.parametrize("tool", ["fixpoint", "z3"])
def test_gate_refuses_when_solver_is_absent(tool):
    """Absent either half of the solver, the gate refuses and names it."""
    result = _run_gate(_path_without(tool))
    combined = result.stdout + result.stderr

    assert result.returncode == 1, (
        f"expected exit 1 when {tool} is absent, got {result.returncode}\n{combined}"
    )
    assert "solver toolchain incomplete" in combined, (
        f"refusal did not name the cause:\n{combined}"
    )
    assert tool in combined, f"refusal did not name the missing tool {tool!r}:\n{combined}"

    # The regression guard proper. A gate that grades undecidable cases prints a
    # tally; one that refuses must not, no matter what it exits with.
    assert "frozen verdict(s) diverged" not in combined, (
        "gate reported diverged verdicts while the solver was absent — "
        f"nothing was decided, so nothing could have diverged:\n{combined}"
    )
    assert "Results:" not in combined, (
        f"gate printed a results tally without a solver:\n{combined}"
    )


@needs_port
def test_preflight_precedes_any_case_execution():
    """The refusal must come before the corpus, not instead of finishing it.

    Run with ORDERING_BUDGET and not BUDGET, for the reason that constant
    records: under a small budget this test cannot fail.
    """
    r = _run_gate(_path_without("fixpoint"), budget=ORDERING_BUDGET)
    combined = r.stdout + r.stderr
    for marker in GRADING_MARKERS:
        assert marker not in combined, (
            f"gate began grading (saw {marker!r}) before refusing:\n{combined}"
        )
    # The refusal is the WHOLE of the output, not merely its first part. The
    # marker loop above cannot see a report the port never got to print, so this
    # is the assertion that separates "refused" from "died quietly": a port that
    # graded the corpus emits a report, and a report is not this message.
    assert combined.strip().startswith("ERROR: solver toolchain incomplete"), (
        f"the refusal is not the first thing printed:\n{combined}"
    )
    assert "frozen verdict" not in combined and "Results:" not in combined, (
        f"a report followed the refusal:\n{combined}"
    )
