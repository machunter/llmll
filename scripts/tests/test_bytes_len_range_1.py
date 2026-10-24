"""BYTES-LEN-RANGE-1: a bytes[n] length outside [0, 2^63 - 1] is refused.

int-index-wrap-1-proposal D4. Up to v0.31.0, bytes[9223372036854775808] was
narrowed to bytes[-2^63], and `llmll verify` reported SAFE for a post of
(= 1 2): the verifier held bytesLen = -2^63 beside bytesLen >= 0, so every goal
discharged. The JSON form "length": -1 did the same.

What a pass here means:

* `check` refuses both witnesses with kind bytes-length-range, on the
  S-expression channel and under --json.
* fixtures/bytes_len_range_1/big.llmll.verified.json was written by v0.31.0 and
  records `verified` for mk. `trust-report` and `verify` now stop at the parse
  error, so no command renders that record, and neither rewrites it.
"""

import os
import shlex
import shutil
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURES = REPO_ROOT / "scripts" / "tests" / "fixtures" / "bytes_len_range_1"

pytestmark = pytest.mark.skipif(
    not os.environ.get("LLMLL_BIN"),
    reason="set LLMLL_BIN to a built llmll",
)

TIMEOUT_S = 120


def _run(args, cwd):
    return subprocess.run([*shlex.split(os.environ["LLMLL_BIN"]), *args],
                          capture_output=True, text=True, timeout=TIMEOUT_S, cwd=str(cwd))


def test_check_refuses_both_witnesses(tmp_path):
    sexp = tmp_path / "big.llmll"
    sexp.write_text("(def mk [] -> bytes[9223372036854775808]\n  (post (= 1 2))\n  (bytes-zero))\n",
                    encoding="utf-8")
    p = _run(["check", str(sexp)], tmp_path)
    assert p.returncode == 1
    assert ':kind "bytes-length-range"' in p.stdout + p.stderr
    j = _run(["--json", "check", str(sexp)], tmp_path)
    assert j.returncode == 1 and "bytes-length-range" in j.stdout
    js = tmp_path / "neg.ast.json"
    js.write_text('{"schemaVersion":"0.14.0","statements":[{"kind":"def","name":"mk","params":[],'
                  '"return_type":{"kind":"bytes","length":-1},'
                  '"body":{"kind":"app","fn":"bytes-zero","args":[]}}]}', encoding="utf-8")
    q = _run(["--json", "check", str(js)], tmp_path)
    assert q.returncode == 1 and "bytes-length-range" in q.stdout


def test_old_false_verified_sidecar_is_never_rendered(tmp_path):
    for name in ["big.llmll", "big.llmll.verified.json"]:
        shutil.copy(FIXTURES / name, tmp_path / name)
    sidecar = (tmp_path / "big.llmll.verified.json").read_text(encoding="utf-8")
    assert '"level":"verified"' in sidecar  # the fixture really holds the false verdict
    for cmd in (["trust-report", "big.llmll"], ["verify", "big.llmll"]):
        p = _run(cmd, tmp_path)
        assert p.returncode == 1, cmd
        out = p.stdout + p.stderr
        assert "bytes-length-range" in out, cmd
        assert "verified (liquid-fixpoint)" not in out, cmd
    assert (tmp_path / "big.llmll.verified.json").read_text(encoding="utf-8") == sidecar
