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

WHY A PATH TEST AND NOT A CORPUS RUN. The property is about what the gate does
when it CANNOT decide, so the test has to produce a host where it cannot. It
does that by removing the solver from PATH rather than by uninstalling anything,
which keeps the test hermetic and lets it run in the toolchain-free CI job — the
gate exits at the preflight, before it ever reaches `stack exec`.

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

import pytest

REPO = pathlib.Path(__file__).resolve().parents[2]
GATE = REPO / "scripts" / "refute-crux-gate.sh"


def _path_without(tool: str) -> str:
    """PATH with every directory that provides `tool` removed.

    Removing directories rather than pointing PATH at a stub keeps the other
    preflight dependency (jq) reachable, so the gate gets far enough to reach
    the solver check instead of failing earlier for an unrelated reason.
    """
    keep = []
    for d in os.environ.get("PATH", "").split(os.pathsep):
        if not d:
            continue
        if shutil.which(tool, path=d) is None:
            keep.append(d)
    return os.pathsep.join(keep)


def _run_gate(path_value: str) -> subprocess.CompletedProcess:
    env = dict(os.environ, PATH=path_value)
    return subprocess.run(
        ["bash", str(GATE)],
        cwd=REPO,
        env=env,
        capture_output=True,
        text=True,
        timeout=120,
    )


def test_gate_script_exists():
    assert GATE.is_file(), f"{GATE} is missing"


@pytest.mark.parametrize("tool", ["fixpoint", "z3"])
def test_gate_refuses_when_solver_is_absent(tool):
    """Absent either half of the solver, the gate refuses and names it."""
    if shutil.which("jq") is None:
        pytest.skip("jq absent: the gate exits at the jq preflight, before the solver one")

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


def test_preflight_precedes_any_case_execution():
    """The refusal must come before the corpus, not partway through it."""
    if shutil.which("jq") is None:
        pytest.skip("jq absent: the gate exits at the jq preflight, before the solver one")

    combined = "".join(
        [(r := _run_gate(_path_without("fixpoint"))).stdout, r.stderr]
    )
    # No suite header and no per-case line may appear. `▸` prefixes a suite and
    # `✅`/`❌` prefix a graded case; any of them means cases ran regardless of
    # the exit code.
    for marker in ("▸", "✅", "❌"):
        assert marker not in combined, (
            f"gate began grading (saw {marker!r}) before refusing:\n{combined}"
        )
