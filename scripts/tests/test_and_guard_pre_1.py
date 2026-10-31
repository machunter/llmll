"""LET-CALL-CONT-1 (commit 1 of AND-GUARD-PRE-1): a `let` whose right-hand
side continues after a call.

What a pass here means:

* and_guard/let_cont_bad.llmll holds four strict `def`s whose let RHS is a
  call followed by more work (`+ 1`, a nested `let`, an `if` over the call
  result), each with a post that is false of the body. Before the fix the let
  variable was bound to the bare call result and all four verified SAFE (a
  false `verified`). `verify` must exit 1 and refute each on its post.
* and_guard/xmod/d01.llmll is the cross-module form: a caller binds
  `(+ 1 (inc y))` where `inc`'s post is `result = x + 1`, and claims
  `result = y + 1`. Verified leaf-first, the caller must be refuted.
"""

import os
import shlex
import shutil
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURES = REPO_ROOT / "scripts" / "tests" / "fixtures" / "and_guard"

pytestmark = pytest.mark.skipif(
    not os.environ.get("LLMLL_BIN"),
    reason="set LLMLL_BIN to a built llmll",
)

needs_fixpoint = pytest.mark.skipif(
    shutil.which("liquid-fixpoint") is None and shutil.which("fixpoint") is None,
    reason="needs liquid-fixpoint on PATH",
)


def _run(cwd: Path, name: str) -> subprocess.CompletedProcess:
    return subprocess.run([*shlex.split(os.environ["LLMLL_BIN"]), "verify", name],
                          capture_output=True, text=True, timeout=120, cwd=str(cwd))


@needs_fixpoint
def test_let_cont_bad_refutes(tmp_path):
    shutil.copy(FIXTURES / "let_cont_bad.llmll", tmp_path / "let_cont_bad.llmll")
    p = _run(tmp_path, "let_cont_bad.llmll")
    out = p.stdout + p.stderr
    assert p.returncode == 1, out
    assert "liquid-fixpoint: {" not in out, out
    for fn in ["c01", "c02", "c04", "c06"]:
        assert f"body verification of '{fn}' failed" in out, out


@needs_fixpoint
def test_let_cont_xmod_refutes(tmp_path):
    for name in ["lib.llmll", "d01.llmll"]:
        shutil.copy(FIXTURES / "xmod" / name, tmp_path / name)
    lib = _run(tmp_path, "lib.llmll")
    assert lib.returncode == 0, lib.stdout + lib.stderr
    p = _run(tmp_path, "d01.llmll")
    out = p.stdout + p.stderr
    assert p.returncode == 1, out
    assert "body verification of 'f' failed" in out, out
