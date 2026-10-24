"""FN-SHADOW-1: a parameter or local binder shadows a top-level function.

fn-param-uf-1-proposal R1. Up to v0.31.0 the verifier, the test evaluator and
strict-core admission resolved a call head that names a parameter to the
top-level function of the same name, while the built program calls the
parameter.

What a pass here means:

* run.llmll (witness S1): the built program stops with "Postcondition violated
  in g", and `verify` on the same file no longer reports g as proved. The two
  agree.
* main.llmll (witness S4): `check` refuses the def, naming `pick` as a
  parameter or local binder. shell.llmll: the def-shell form passes `check`
  with no trust-gap warning about pk.pick.
"""

import glob
import os
import shlex
import shutil
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURES = REPO_ROOT / "scripts" / "tests" / "fixtures" / "fn_shadow_1"

pytestmark = pytest.mark.skipif(
    not os.environ.get("LLMLL_BIN"),
    reason="set LLMLL_BIN to a built llmll",
)

BUILD_TIMEOUT_S = 600


def _run(args, cwd, timeout=120):
    return subprocess.run([*shlex.split(os.environ["LLMLL_BIN"]), *args],
                          capture_output=True, text=True, timeout=timeout, cwd=str(cwd))


def test_s1_build_and_verify_agree(tmp_path):
    shutil.copy(FIXTURES / "run.llmll", tmp_path / "run.llmll")
    b = _run(["build", "run.llmll", "-o", str(tmp_path / "out")], tmp_path, BUILD_TIMEOUT_S)
    assert b.returncode == 0, b.stdout[-1500:] + b.stderr[-1500:]
    exes = glob.glob(str(tmp_path / "out" / ".stack-work" / "install" / "*" / "*" / "*" / "bin" / "*"))
    assert len(exes) == 1, exes
    r = subprocess.run([exes[0]], input="x\n", capture_output=True, text=True, timeout=20)
    assert r.returncode != 0
    assert "Postcondition violated in g" in r.stdout + r.stderr
    v = _run(["verify", "run.llmll"], tmp_path)
    out = v.stdout + v.stderr
    assert "body-fallback:" in out and " g" in out.split("body-fallback:")[1].splitlines()[0]
    assert "body-faithful: pick" in out or "body-faithful: pick\n" in out


def test_s4_admission_names_the_parameter_and_no_trust_gap(tmp_path):
    for name in ["pk.llmll", "main.llmll", "shell.llmll"]:
        shutil.copy(FIXTURES / name, tmp_path / name)
    assert _run(["verify", "pk.llmll"], tmp_path).returncode == 0
    m = _run(["check", "main.llmll"], tmp_path)
    assert m.returncode == 1
    assert "callee 'pick' is a parameter or local binder" in m.stdout + m.stderr
    s = _run(["check", "shell.llmll"], tmp_path)
    assert s.returncode == 0, s.stdout + s.stderr
    assert "trust gap" not in s.stdout + s.stderr
