"""DIVERGE-NOSOLVER-1: `llmll diverge-report` says when it could not grade a fill.

WHAT THE DEFECT WAS. `classifyFillStatus` (`compiler/app/Main.hs`) answered a
missing solver with `FSTypeError`, so with no `liquid-fixpoint` / `fixpoint`
on PATH every fill of an R5 divergence session was listed under
`status_partition.type_error`, the command exited 0, and nothing in the output
said the solver was missing. A caller could not tell a missing solver from N
ill-typed fills. A solver that ran and returned no verdict was listed as
`refuted`, which it also was not.

WHAT CHANGED. A fill that typechecks, stays in the QF-LIA fragment, and gets
no SAFE/UNSAFE verdict is `unavailable` (a new `status_partition` key). The
record gains `solver_available`. The command exits 3 when ANY fill is
unavailable, since the verdict covers only graded fills; a banner goes to
stderr outside `--json`. A fill outside the fragment is refuted without a
solver, as it was with one, because that check never needed the solver.

WHAT EACH CELL DID AGAINST THE v0.26.2 BINARY, measured and not assumed.
DN-1, DN-2, DN-3, DN-5 and DN-6 FAILED there (exit 0, no `unavailable` key,
fills under `type_error` or `refuted`). DN-4 FAILED only on the new
`solver_available` / `unavailable` keys; its grading assertions (one fill
verified, one refuted, exit 0) passed on both binaries, which is the
unchanged-behaviour pin. DN-4 needs `fixpoint` on the runner PATH and skips
without it.

WHY THE PATH IS AN EMPTY DIRECTORY. `checkout` and `diverge-report` exec
nothing but the solver, so an empty directory hides `fixpoint`,
`liquid-fixpoint` and `z3` on any runner.

WHY IT SKIPS WITHOUT A BINARY. `pytest scripts/tests/` runs in version-gate's
C1-C4 job, which builds no compiler. The spec-roundtrip job runs this file
with LLMLL_BIN set, after the toolchain step puts `fixpoint` on PATH.
"""

from __future__ import annotations

import json
import os
import shlex
import shutil
import subprocess
from pathlib import Path

import pytest

pytestmark = pytest.mark.skipif(
    not os.environ.get("LLMLL_BIN"),
    reason="set LLMLL_BIN to a built llmll; the spec-roundtrip job runs this in CI",
)

TIMEOUT_S = 120
POINTER = "/statements/0/body"


def _n() -> dict:
    return {"kind": "var", "name": "n"}


# `dbl` from experiments/minimal-agent/r5-campaign/corpus/double_tight.llmll:
# post (= result (+ n n)), a def-shell with one hole.
MODULE = {
    "schemaVersion": "0.11.0",
    "llmll_version": "0.26.2",
    "statements": [{
        "kind": "def-shell", "name": "dbl",
        "params": [{"name": "n", "param_type": {"kind": "primitive", "name": "int"}}],
        "return_type": {"kind": "primitive", "name": "int"},
        "post": {"kind": "op", "op": "=", "args": [
            {"kind": "var", "name": "result"},
            {"kind": "op", "op": "+", "args": [_n(), _n()]}]},
        "body": {"kind": "hole-named", "name": "hole"},
    }],
}

FILLS = {
    "good": {"kind": "op", "op": "+", "args": [_n(), _n()]},                    # verifies
    "bad": {"kind": "op", "op": "+", "args": [_n(), {"kind": "lit-int", "value": 1}]},  # UNSAFE
    "ill": {"kind": "lit-string", "value": "x"},                                # type error
    "nonlin": {"kind": "op", "op": "*", "args": [_n(), _n()]},                  # outside QF-LIA
}


def _llmll() -> list[str]:
    return shlex.split(os.environ["LLMLL_BIN"])


def _run(work: Path, path: str, *args: str) -> subprocess.CompletedProcess:
    env = {"PATH": path, "HOME": str(work)}
    return subprocess.run(
        _llmll() + list(args),
        cwd=work, env=env, capture_output=True, text=True, timeout=TIMEOUT_S,
    )


def _nosolver(work: Path) -> str:
    return str(work / "emptybin")


@pytest.fixture
def work(tmp_path: Path) -> Path:
    (tmp_path / "emptybin").mkdir()
    (tmp_path / "dbl.ast.json").write_text(json.dumps(MODULE))
    return tmp_path


def _session(work: Path, fills: list[str]) -> tuple[str, dict[str, str]]:
    """Open a session of len(fills) slots, write each fill into its scratch.

    Returns the session id and a map from fill name to the fill id the report
    uses (the first 12 characters of the slot's token).
    """
    ids: dict[str, str] = {}
    session = None
    for name in fills:
        p = _run(work, _nosolver(work), "checkout", "--multi", str(len(fills)),
                 "dbl.ast.json", POINTER)
        assert p.returncode == 0, p.stdout + p.stderr
        out = json.loads(p.stdout)
        session = session or out["session"]
        assert out["session"] == session, out
        scratch = work / out["scratch"]
        mod = json.loads(scratch.read_text())
        mod["statements"][0]["body"] = FILLS[name]
        scratch.write_text(json.dumps(mod))
        ids[name] = out["token"]["token"][:12]
    assert session is not None
    return session, ids


def _witness(stdout: str) -> dict:
    objs = [json.loads(line) for line in stdout.splitlines() if line.strip()]
    assert len(objs) == 1, f"expected one JSON object on stdout, got {objs}"
    return objs[0]["divergence_witness"]


def test_dn1_no_solver_fills_are_unavailable_not_type_errors(work: Path) -> None:
    """Pre-fix: exit 0, both fills under `type_error`, no word of the solver."""
    session, ids = _session(work, ["good", "bad"])
    p = _run(work, _nosolver(work), "diverge-report", "dbl.ast.json", session)
    assert p.returncode == 3, f"exit {p.returncode}, want 3:\n{p.stdout}{p.stderr}"
    dw = _witness(p.stdout)
    sp = dw["status_partition"]
    assert sorted(sp["unavailable"]) == sorted([ids["good"], ids["bad"]]), sp
    assert sp["type_error"] == [] and sp["verified"] == [] and sp["refuted"] == [], sp
    assert dw["solver_available"] is False, dw
    assert "SOLVER NOT FOUND" in p.stderr, p.stderr


def test_dn2_json_keeps_stdout_one_object_and_no_banner(work: Path) -> None:
    session, ids = _session(work, ["good", "bad"])
    p = _run(work, _nosolver(work), "--json", "diverge-report", "dbl.ast.json", session)
    assert p.returncode == 3, p.stdout + p.stderr
    dw = _witness(p.stdout)
    assert len(dw["status_partition"]["unavailable"]) == 2, dw
    assert "SOLVER NOT FOUND" not in p.stderr, "--json must not print the banner"


def test_dn3_real_type_error_without_solver_is_still_a_type_error(work: Path) -> None:
    """A string body for an int function fails the typechecker, solver or not."""
    session, ids = _session(work, ["ill", "good"])
    p = _run(work, _nosolver(work), "diverge-report", "dbl.ast.json", session)
    assert p.returncode == 3, p.stdout + p.stderr
    sp = _witness(p.stdout)["status_partition"]
    assert sp["type_error"] == [ids["ill"]], sp
    assert sp["unavailable"] == [ids["good"]], sp


def test_dn4_with_solver_grading_is_unchanged(work: Path) -> None:
    """The good fill verifies, the bad one is refuted, exit 0."""
    solver_path = os.environ.get("PATH", "")
    if not (shutil.which("fixpoint", path=solver_path)
            or shutil.which("liquid-fixpoint", path=solver_path)):
        pytest.skip("needs fixpoint on PATH")
    session, ids = _session(work, ["good", "bad"])
    p = _run(work, solver_path, "diverge-report", "dbl.ast.json", session)
    assert p.returncode == 0, p.stdout + p.stderr
    dw = _witness(p.stdout)
    sp = dw["status_partition"]
    assert sp["verified"] == [ids["good"]], sp
    assert sp["refuted"] == [ids["bad"]], sp
    assert sp["type_error"] == [], sp
    assert dw["verdict"] == "no-divergence-observed", dw
    assert sp["unavailable"] == [] and dw["solver_available"] is True, dw
    assert "SOLVER" not in p.stderr, p.stderr


def test_dn5_solver_error_is_unavailable_not_refuted(work: Path) -> None:
    """A `fixpoint` that runs but returns no verdict. Pre-fix: `refuted`, exit 0."""
    stub = work / "emptybin" / "fixpoint"
    stub.write_text("#!/bin/sh\necho 'fixpoint: simulated crash' >&2\nexit 2\n")
    stub.chmod(0o755)
    session, ids = _session(work, ["good", "bad"])
    p = _run(work, _nosolver(work), "diverge-report", "dbl.ast.json", session)
    assert p.returncode == 3, p.stdout + p.stderr
    dw = _witness(p.stdout)
    sp = dw["status_partition"]
    assert sorted(sp["unavailable"]) == sorted([ids["good"], ids["bad"]]), sp
    assert sp["refuted"] == [], sp
    assert dw["solver_available"] is True, dw
    assert "SOLVER ERROR" in p.stderr, p.stderr


def test_dn6_fragment_check_needs_no_solver(work: Path) -> None:
    """A nonlinear body leaves QF-LIA and is refuted with no solver, as with one.

    Pre-fix: `type_error`, because the solver check ran before the fragment
    check.
    """
    session, ids = _session(work, ["nonlin", "ill"])
    p = _run(work, _nosolver(work), "diverge-report", "dbl.ast.json", session)
    assert p.returncode == 0, p.stdout + p.stderr
    dw = _witness(p.stdout)
    sp = dw["status_partition"]
    assert sp["refuted"] == [ids["nonlin"]], sp
    assert sp["type_error"] == [ids["ill"]], sp
    assert sp["unavailable"] == [], sp
    assert dw["solver_available"] is False, dw
