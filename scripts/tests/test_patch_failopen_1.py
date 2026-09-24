"""PATCH-FAILOPEN-1: `llmll patch` FAILS CLOSED when no solver can re-verify it.

WHAT THE DEFECT WAS. `reVerify` (`compiler/src/LLMLL/PatchApply.hs`, the
patch lifecycle's step 6.5) returned "no violation" when neither
`liquid-fixpoint` nor `fixpoint` was on PATH, and also when the solver ran
and returned no verdict. `applyPatchWithMode` then wrote the patched file,
cleared the lock, and answered `PatchSuccess` with exit 0. A wrong body,
`(+ balance amount)` against `post (= result (- balance amount))`, was
merged unproven with nothing in the output saying the proof was skipped.
`llmll verify` already failed closed for the same case (exit 3, `SOLVER NOT
FOUND`); `patch` now matches it.

WHAT EACH CELL DID AGAINST THE PRE-FIX BINARY, measured and not assumed.
PF-1, PF-2 and PF-4 FAILED: each exited 0 and rewrote the file. PF-3 and PF-5
PASSED on both binaries. PF-3 is the guard against overreach: a module with no
contracts has nothing to prove, so it still patches without a solver. PF-5
(the lock survives, and the same token lands once a solver is present) needs
`fixpoint` on the runner PATH and skips without it.

WHY THE PATH IS AN EMPTY DIRECTORY. `checkout` and `patch` exec nothing but
the solver, so an empty directory hides `fixpoint`, `liquid-fixpoint` and
`z3` on any runner. The binary is named by its absolute path.

WHY IT SKIPS WITHOUT A BINARY. `pytest scripts/tests/` runs in version-gate's
C1-C4 job, which builds no compiler. The spec-roundtrip job runs this file
with LLMLL_BIN set, after the toolchain step puts `fixpoint` on PATH so PF-5
runs there.
"""

from __future__ import annotations

import hashlib
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
REPO = Path(__file__).resolve().parents[2]
DEMO = REPO / "examples" / "withdraw-demo"
POINTER = "/statements/1/body"


def _llmll() -> list[str]:
    return shlex.split(os.environ["LLMLL_BIN"])


def _sha(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


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
    shutil.copy(DEMO / "withdraw.ast.json", tmp_path / "withdraw.ast.json")
    return tmp_path


def _checkout(work: Path, src: str, pointer: str = POINTER) -> str:
    p = _run(work, _nosolver(work), "checkout", src, pointer)
    assert p.returncode == 0, p.stdout + p.stderr
    return json.loads(p.stdout)["token"]


def _patch_file(work: Path, fixture: str, token: str, *, drop_test: bool = False) -> Path:
    req = json.loads((DEMO / fixture).read_text())
    req["token"] = token
    if drop_test:
        # `refine` admits only the fill and additive adds; no `test` op.
        req["patch"] = [op for op in req["patch"] if op["op"] != "test"]
    out = work / ("req-" + fixture)
    out.write_text(json.dumps(req))
    return out


def _result(stdout: str) -> dict:
    objs = [json.loads(line) for line in stdout.splitlines() if line.strip()]
    assert len(objs) == 1, f"expected one JSON result on stdout, got {objs}"
    return objs[0]


def test_pf1_wrong_patch_without_solver_is_not_applied(work: Path) -> None:
    """Pre-fix: exit 0, `PatchSuccess`, the wrong body written to disk."""
    src = work / "withdraw.ast.json"
    before = _sha(src)
    tok = _checkout(work, src.name)
    req = _patch_file(work, "withdraw-patch-wrong.json", tok)
    p = _run(work, _nosolver(work), "patch", src.name, req.name)
    out = p.stdout + p.stderr
    assert p.returncode == 3, f"exit {p.returncode}, want 3:\n{out}"
    assert _sha(src) == before, "the unverified patch was written"
    res = _result(p.stdout)
    assert res["result"] == "PatchVerifyUnavailable", res
    assert res["solver_available"] is False and res["verified"] is False, res
    assert "PatchSuccess" not in out, out
    assert "SOLVER NOT FOUND" in p.stderr, p.stderr


def test_pf2_json_correct_patch_without_solver_is_not_applied(work: Path) -> None:
    """A correct body is not proved either; `--json` keeps stdout one object.

    Pre-fix: exit 0 and `PatchSuccess`.
    """
    src = work / "withdraw.ast.json"
    before = _sha(src)
    tok = _checkout(work, src.name)
    req = _patch_file(work, "withdraw-patch-correct.json", tok)
    p = _run(work, _nosolver(work), "--json", "patch", src.name, req.name)
    assert p.returncode == 3, p.stdout + p.stderr
    assert _sha(src) == before
    res = _result(p.stdout)
    assert res["result"] == "PatchVerifyUnavailable", res
    assert "not applied" in res["message"].lower(), res
    assert "SOLVER NOT FOUND" not in p.stderr, "--json must not print the banner"


def test_pf3_no_contracts_still_patches_without_solver(work: Path) -> None:
    """Nothing to prove, so no solver is needed. Passed before the fix too."""
    mod = {
        "schemaVersion": "0.6.0",
        "llmll_version": "0.3.0",
        "statements": [{
            "kind": "def", "name": "add",
            "params": [
                {"name": "x", "param_type": {"kind": "primitive", "name": "int"}},
                {"name": "y", "param_type": {"kind": "primitive", "name": "int"}},
            ],
            "body": {"kind": "hole-named", "name": "impl"},
        }],
    }
    src = work / "nocontract.ast.json"
    src.write_text(json.dumps(mod))
    before = _sha(src)
    tok = _checkout(work, src.name, "/statements/0/body")
    req = work / "req-nc.json"
    req.write_text(json.dumps({"token": tok, "patch": [
        {"op": "replace", "path": "/statements/0/body",
         "value": {"kind": "app", "fn": "*",
                   "args": [{"kind": "var", "name": "x"},
                            {"kind": "var", "name": "y"}]}}]}))
    p = _run(work, _nosolver(work), "patch", src.name, req.name)
    assert p.returncode == 0, p.stdout + p.stderr
    assert _result(p.stdout)["result"] == "PatchSuccess"
    assert _sha(src) != before


def test_pf4_refine_without_solver_is_not_applied(work: Path) -> None:
    """`refine` shares the patch lifecycle. Pre-fix: exit 0, file rewritten."""
    src = work / "withdraw.ast.json"
    before = _sha(src)
    tok = _checkout(work, src.name)
    req = _patch_file(work, "withdraw-patch-wrong.json", tok, drop_test=True)
    p = _run(work, _nosolver(work), "refine", src.name, req.name)
    assert p.returncode == 3, p.stdout + p.stderr
    assert _sha(src) == before
    assert _result(p.stdout)["result"] == "PatchVerifyUnavailable"


def test_pf5_lock_survives_and_same_token_lands_with_solver(work: Path) -> None:
    """The failed attempt keeps the lock; the retry with a solver succeeds."""
    solver_path = os.environ.get("PATH", "")
    if not (shutil.which("fixpoint", path=solver_path)
            or shutil.which("liquid-fixpoint", path=solver_path)):
        pytest.skip("needs fixpoint on PATH")
    src = work / "withdraw.ast.json"
    before = _sha(src)
    tok = _checkout(work, src.name)
    req = _patch_file(work, "withdraw-patch-correct.json", tok)
    p = _run(work, _nosolver(work), "patch", src.name, req.name)
    assert p.returncode == 3, p.stdout + p.stderr
    p = _run(work, solver_path, "patch", src.name, req.name)
    assert p.returncode == 0, p.stdout + p.stderr
    assert _result(p.stdout)["result"] == "PatchSuccess"
    assert _sha(src) != before


def test_pf6_solver_error_is_not_a_pass(work: Path) -> None:
    """A `fixpoint` that runs but returns no verdict. Pre-fix: exit 0, written.

    The stub prints no SAFE/UNSAFE envelope and exits 2, which `parseFQOutcome`
    reads as `FQError`.
    """
    stub = work / "emptybin" / "fixpoint"
    stub.write_text("#!/bin/sh\necho 'fixpoint: simulated crash' >&2\nexit 2\n")
    stub.chmod(0o755)
    src = work / "withdraw.ast.json"
    before = _sha(src)
    tok = _checkout(work, src.name)
    req = _patch_file(work, "withdraw-patch-correct.json", tok)
    p = _run(work, _nosolver(work), "patch", src.name, req.name)
    assert p.returncode == 3, p.stdout + p.stderr
    assert _sha(src) == before
    res = _result(p.stdout)
    assert res["result"] == "PatchVerifyUnavailable", res
    assert res["solver_available"] is True, res
    assert "simulated crash" in res.get("solver_error", ""), res
    assert "SOLVER ERROR" in p.stderr, p.stderr
