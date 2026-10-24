"""FN-PARAM-UF-1: a call through a function-typed parameter is an opaque call.

fn-param-uf-1-proposal R2 and R3. Each fixture is verified and then built and
run, so the verdict and the program's behaviour can be compared:

* w2.llmll (witness W2): min2-by and pick-lambda are body-faithful and the file
  is SAFE (both fell back before); the run prints 3.
* w6.llmll (witness W6): use-pos is body-faithful and REFUTED, because the
  return refinement of the parameter is not assumed; the run stops with
  "Postcondition violated in use-pos" (the lambda returns -5).
"""

import glob
import os
import shlex
import shutil
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURES = REPO_ROOT / "scripts" / "tests" / "fixtures" / "fn_param_uf_1"

pytestmark = pytest.mark.skipif(
    not os.environ.get("LLMLL_BIN"),
    reason="set LLMLL_BIN to a built llmll",
)


def _run(args, cwd, timeout=600):
    return subprocess.run([*shlex.split(os.environ["LLMLL_BIN"]), *args],
                          capture_output=True, text=True, timeout=timeout, cwd=str(cwd))


def _build_run(name, tmp_path):
    out = tmp_path / ("out-" + name)
    b = _run(["build", name, "-o", str(out)], tmp_path)
    assert b.returncode == 0, b.stdout[-1500:] + b.stderr[-1500:]
    exes = glob.glob(str(out / ".stack-work" / "install" / "*" / "*" / "*" / "bin" / "*"))
    assert len(exes) == 1, exes
    return subprocess.run([exes[0]], input="x\n", capture_output=True, text=True, timeout=20)


def test_w2_proves_and_w6_refutes_and_the_runs_agree(tmp_path):
    for name in ["w2.llmll", "w6.llmll"]:
        shutil.copy(FIXTURES / name, tmp_path / name)
    v2 = _run(["verify", "w2.llmll"], tmp_path)
    assert v2.returncode == 0, v2.stdout + v2.stderr
    assert "body-faithful: min2-by, pick-lambda" in v2.stdout
    r2 = _build_run("w2.llmll", tmp_path)
    assert r2.returncode == 0 and r2.stdout.strip() == "3", r2.stderr[-500:]
    v6 = _run(["verify", "w6.llmll"], tmp_path)
    assert v6.returncode == 1, v6.stdout + v6.stderr
    assert "body verification of 'use-pos' failed" in v6.stdout + v6.stderr
    r6 = _build_run("w6.llmll", tmp_path)
    assert r6.returncode != 0
    assert "Postcondition violated in use-pos" in r6.stdout + r6.stderr
