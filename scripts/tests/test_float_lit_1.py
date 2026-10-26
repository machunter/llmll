"""FLOAT-LIT-1: float literals (decimal-numbers-proposal Rev 1, R1-1 to R1-3).

What a pass here means:

* values.llmll, built with $LLMLL_BIN and run, shows that a negative float
  literal and -0.0 compile and behave: -0.5 equals -0.5, the pattern
  (Box -0.5) matches (on v0.31.0 that pattern was GHC's parse error
  "Box - 0.5", D8, and -0.5 itself was a parse error, D1), and -0.0 is the
  zero pattern 0.0 (R1-1). The generated Lib.hs carries 0.0 and
  (Box (-0.5 :: Double)).
* A float pattern 2.0 survives S-expression -> JSON-AST -> build (D6: the
  emitter wrote it as the number 2, the reader made it an int pattern, and
  GHC refused the program).
* `check` refuses an out-of-range literal with kind float-literal-range on
  both surfaces, including an exponent past 2^64 that used to wrap (D7).
* `check` refuses a leading-zero float and an int pattern against a float
  scrutinee (R1-2, R1-3).
"""

import glob
import json
import os
import shlex
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURES = REPO_ROOT / "scripts" / "tests" / "fixtures" / "float_lit_1"

pytestmark = pytest.mark.skipif(
    not os.environ.get("LLMLL_BIN"),
    reason="set LLMLL_BIN to a built llmll",
)

BUILD_TIMEOUT_S = 600
RUN_TIMEOUT_S = 10
CHECK_TIMEOUT_S = 60


def _llmll() -> list[str]:
    return shlex.split(os.environ["LLMLL_BIN"])


def _run(args, cwd, timeout=CHECK_TIMEOUT_S):
    return subprocess.run([*_llmll(), *args], capture_output=True, text=True,
                          timeout=timeout, cwd=str(cwd))


def _exe(out: Path) -> str:
    exes = glob.glob(str(out / ".stack-work" / "install" / "*" / "*" / "*" / "bin" / "*"))
    assert len(exes) == 1, f"expected one executable under {out}, found {exes}"
    return exes[0]


def test_negative_and_zero_floats_build_and_run(tmp_path):
    out = tmp_path / "values"
    p = _run(["build", str(FIXTURES / "values.llmll"), "-o", str(out)], REPO_ROOT, BUILD_TIMEOUT_S)
    assert p.returncode == 0, f"build failed rc={p.returncode}\n{p.stdout[-1500:]}\n{p.stderr[-1500:]}"
    r = subprocess.run([_exe(out)], input="x\n", capture_output=True, text=True, timeout=RUN_TIMEOUT_S)
    assert r.returncode == 0, r.stderr[-500:]
    cells = dict(line.partition("=")[::2] for line in r.stdout.splitlines() if "=" in line)
    assert cells == {"NEG": "yes", "PAT": "neg-half", "ZERO": "zero", "EXP": "minus-1250", "Z2": "zero"}
    lib = (out / "src" / "Lib.hs").read_text(encoding="utf-8")
    assert "(Box (-0.5 :: Double))" in lib
    assert "(-1250.0 :: Double)" in lib


def test_float_pattern_round_trips_through_json_ast_and_builds(tmp_path):
    src = tmp_path / "pat.llmll"
    src.write_text("(def-shell k [x: float] -> int (match x (2.0 1) (_ 0)))\n", encoding="utf-8")
    p = _run(["build", str(src), "--emit"], tmp_path, BUILD_TIMEOUT_S)
    assert p.returncode == 0, p.stdout + p.stderr
    (ast,) = list(tmp_path.glob("generated/pat/pat.ast.json"))
    doc = json.loads(ast.read_text(encoding="utf-8"))
    assert doc["schemaVersion"] == "0.15.0"
    assert '"literal_kind": "float"' in ast.read_text(encoding="utf-8")
    c = _run(["check", str(ast)], tmp_path)
    assert c.returncode == 0, c.stdout + c.stderr
    assert "warning" not in (c.stdout + c.stderr)
    b = _run(["build", str(ast), "-o", str(tmp_path / "out")], tmp_path, BUILD_TIMEOUT_S)
    assert b.returncode == 0, b.stdout[-1500:] + b.stderr[-1500:]


def test_check_refuses_out_of_range_sexp(tmp_path):
    for lit in ["1e400", "1e-400", "1e18446744073709551617"]:
        f = tmp_path / "r.llmll"
        f.write_text(f"(def-shell f [] -> float {lit})\n", encoding="utf-8")
        p = _run(["check", str(f)], tmp_path)
        assert p.returncode == 1, lit
        assert ':kind "float-literal-range"' in p.stdout + p.stderr, lit
        j = _run(["--json", "check", str(f)], tmp_path)
        assert j.returncode == 1, lit
        assert "float-literal-range" in j.stdout, lit


def test_check_refuses_out_of_range_json(tmp_path):
    for value in ["1e400", "1e18446744073709551617"]:
        f = tmp_path / "r.ast.json"
        f.write_text('{"schemaVersion":"0.14.0","statements":[{"kind":"def-shell","name":"f",'
                     '"params":[],"body":{"kind":"lit-float","value":' + value + '}}]}',
                     encoding="utf-8")
        j = _run(["--json", "check", str(f)], tmp_path)
        assert j.returncode == 1, value
        assert "float-literal-range" in j.stdout, value


def test_check_refuses_leading_zero_and_int_pattern_on_float(tmp_path):
    lz = tmp_path / "lz.llmll"
    lz.write_text("(def-shell f [] -> float 00.5)\n", encoding="utf-8")
    p = _run(["check", str(lz)], tmp_path)
    assert p.returncode == 1 and "leading zero" in p.stdout + p.stderr
    ip = tmp_path / "ip.llmll"
    ip.write_text("(def-shell f [x: float] -> int (match x (2 1) (_ 0)))\n", encoding="utf-8")
    q = _run(["check", str(ip)], tmp_path)
    assert q.returncode == 1
    assert "does not match scrutinee type float" in q.stdout + q.stderr
