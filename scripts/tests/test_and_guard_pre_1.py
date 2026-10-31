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

AND-GUARD-PRE-1 (commit 2): a call in a later operand of `and`, `or` or `=>`.

* and_guard/guard.llmll holds eight strict `def`s that call map-get or
  bytes-get in a later operand whose earlier operand establishes the pre
  (and, nested and, or-over-not, not-over-and, a let-bound and, =>, a bool
  body). Before the fix each was refuted at its call-site pre. `verify` must
  exit 0 with all eight body-faithful.
* and_guard/guard_bad.llmll: the earlier operand does not establish the pre,
  or the call is in the first operand. Each stays refuted at its call pre.
* and_guard/xmod/d02.llmll guards a cross-module `half` (pre x > 0) with
  `(> y 0)` and must verify; d06.llmll is a def-shell whose post is false on
  the path that never calls the non-terminating `boom` (post false). Before
  the fix boom's post was assumed on that path and d06 verified SAFE (a false
  SAFE); it must now be refuted, like its nested-`if` control d07.
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


def _line(out: str, prefix: str) -> list[str]:
    """The comma-separated names on the first output line starting with prefix."""
    for raw in out.splitlines():
        t = raw.strip()
        if t.startswith(prefix):
            return [x.strip() for x in t[len(prefix):].split(",") if x.strip()]
    return []


GUARD_FNS = ["w1", "a04", "a05", "a06", "a07", "a11", "a12", "b08"]


@needs_fixpoint
def test_and_guard_proves(tmp_path):
    shutil.copy(FIXTURES / "guard.llmll", tmp_path / "guard.llmll")
    p = _run(tmp_path, "guard.llmll")
    out = p.stdout + p.stderr
    assert p.returncode == 0, out
    assert "SAFE (liquid-fixpoint)" in out, out
    assert sorted(_line(out, "body-faithful:")) == sorted(GUARD_FNS), out
    assert _line(out, "body-fallback:") == [], out
    assert "not satisfied" not in out, out


@needs_fixpoint
def test_and_guard_refutes(tmp_path):
    shutil.copy(FIXTURES / "guard_bad.llmll", tmp_path / "guard_bad.llmll")
    p = _run(tmp_path, "guard_bad.llmll")
    out = p.stdout + p.stderr
    assert p.returncode == 1, out
    assert "liquid-fixpoint: {" not in out, out
    for fn in ["a15", "a16", "wrong"]:
        assert f"call-site precondition of 'map-get' not satisfied in '{fn}'" in out, out


@needs_fixpoint
def test_and_guard_xmod(tmp_path):
    for name in ["lib.llmll", "lib2.llmll", "d02.llmll", "d06.llmll", "d07.llmll"]:
        shutil.copy(FIXTURES / "xmod" / name, tmp_path / name)
    for leaf in ["lib.llmll", "lib2.llmll"]:
        r = _run(tmp_path, leaf)
        assert r.returncode == 0, r.stdout + r.stderr
    d02 = _run(tmp_path, "d02.llmll")
    assert d02.returncode == 0, d02.stdout + d02.stderr
    # d06 was the false SAFE: on the path y <= 0 it returns 1 without calling
    # boom, so boom's post (false) must not be assumed there. d07 is its
    # nested-if control and was already refuted.
    for caller in ["d06.llmll", "d07.llmll"]:
        p = _run(tmp_path, caller)
        out = p.stdout + p.stderr
        assert p.returncode == 1, out
        assert "body verification of 'f' failed" in out, out
