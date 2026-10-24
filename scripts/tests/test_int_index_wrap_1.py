"""INT-INDEX-WRAP-1: an int argument is never narrowed by wrapping.

int-index-wrap-1-proposal Rev 0 (D1 to D3). Up to v0.31.0 an index argument
crossed a `fromIntegral :: Int` seam, so 2^64 read as 0: (list-nth xs 2^64)
answered the first element, (string-char-at "abc" 2^64+2) answered "c", and a
bytes-set at 2^64+1 wrote index 1. The process timeout and the :status exit
value wrapped the same way.

What a pass here means, each program built with $LLMLL_BIN and run:

* values.llmll: list-nth answers Error, string-char-at answers "", and
  string-slice clamps, for indices outside Int64 (witnesses 1, 4, 5).
* bytes_wrap.llmll: the bytes-set at 2^64+1 fails its runtime precondition and
  the program exits non-zero (witness 6).
* status_wrap.llmll: a :status of 2^64 exits 255 (witness 8; it crashed).
* timeout_wrap.llmll: a timeout of 18446744073710 s lets /bin/sleep 1 finish
  (witness 7; it wrapped to about 0.45 s and timed out).
"""

import glob
import os
import shlex
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURES = REPO_ROOT / "scripts" / "tests" / "fixtures" / "int_index_wrap_1"

pytestmark = pytest.mark.skipif(
    not os.environ.get("LLMLL_BIN"),
    reason="set LLMLL_BIN to a built llmll",
)

BUILD_TIMEOUT_S = 600
RUN_TIMEOUT_S = 20


def _build(name: str, out: Path) -> str:
    p = subprocess.run([*shlex.split(os.environ["LLMLL_BIN"]), "build", str(FIXTURES / name), "-o", str(out)],
                       capture_output=True, text=True, timeout=BUILD_TIMEOUT_S, cwd=str(REPO_ROOT))
    assert p.returncode == 0, f"build {name} failed\n{p.stdout[-1500:]}\n{p.stderr[-1500:]}"
    exes = glob.glob(str(out / ".stack-work" / "install" / "*" / "*" / "*" / "bin" / "*"))
    assert len(exes) == 1, exes
    return exes[0]


def test_indices_outside_int64_get_the_out_of_range_answer(tmp_path):
    exe = _build("values.llmll", tmp_path / "values")
    r = subprocess.run([exe], input="x\n", capture_output=True, text=True, timeout=RUN_TIMEOUT_S)
    assert r.returncode == 0, r.stderr[-500:]
    cells = dict(line.partition("=")[::2] for line in r.stdout.splitlines() if "=" in line)
    assert cells == {"NTH64": "Error", "NTH64P1": "Error", "NTHNEG": "Error", "NTH2": "30",
                     "AT": "<>", "SL1": "<>", "SL2": "abc", "SL3": "abc", "SL4": "ab"}
    exe2 = _build("bytes_wrap.llmll", tmp_path / "bytes")
    r2 = subprocess.run([exe2], input="x\n", capture_output=True, text=True, timeout=RUN_TIMEOUT_S)
    assert r2.returncode != 0
    assert "bytes-set: pre-condition failed: index 18446744073709551617" in r2.stderr


def test_exit_status_and_timeout_do_not_wrap(tmp_path):
    exe = _build("status_wrap.llmll", tmp_path / "status")
    r = subprocess.run([exe], capture_output=True, text=True, timeout=RUN_TIMEOUT_S)
    assert r.returncode == 255, (r.returncode, r.stderr[-500:])
    assert "invalid argument" not in r.stderr
    exe2 = _build("timeout_wrap.llmll", tmp_path / "timeout")
    r2 = subprocess.run([exe2], capture_output=True, text=True, timeout=RUN_TIMEOUT_S)
    assert r2.returncode == 0, (r2.returncode, r2.stderr[-500:])
