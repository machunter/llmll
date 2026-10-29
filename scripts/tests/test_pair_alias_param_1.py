"""PAIR-ALIAS-PARAM-1: a pair alias, refined (Pt) or not (IB), as a parameter
and as a return.

What a pass here means:

* pairs/pair_alias.llmll verifies SAFE with all four functions body-faithful:
  a Pt parameter returned (ret-pt), a guard over Pt parameters (min-pt), a Pt
  built under a pre (mk-pt) and an IB parameter and return (ib-flip). Before
  the change ret-pt and min-pt fell back, and mk-pt and ib-flip crashed
  liquid-fixpoint ("The sort (Pair2 ...) is not numeric"), because the result
  binder of a pair-alias return was declared at int.
* pairs/pair_alias_bad.llmll breaks the alias predicate or the post in each
  function and is refuted at all four, exit 1, with no solver crash.
* pairs/pair_alias_call.llmll calls a Pt-returning callee and verifies SAFE.
  Before the change the call-result binder was declared at int and the
  callee post's `pair2_0` crashed liquid-fixpoint. pairs/pair_alias_call_bad.llmll
  is refuted at the body and at the call-site pre, exit 1.
"""

import os
import shlex
import shutil
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURES = REPO_ROOT / "scripts" / "tests" / "fixtures" / "pairs"

pytestmark = pytest.mark.skipif(
    not os.environ.get("LLMLL_BIN"),
    reason="set LLMLL_BIN to a built llmll",
)

needs_fixpoint = pytest.mark.skipif(
    shutil.which("liquid-fixpoint") is None and shutil.which("fixpoint") is None,
    reason="needs liquid-fixpoint on PATH",
)


def _verify(tmp_path: Path, name: str) -> subprocess.CompletedProcess:
    shutil.copy(FIXTURES / name, tmp_path / name)
    return subprocess.run([*shlex.split(os.environ["LLMLL_BIN"]), "verify", name],
                          capture_output=True, text=True, timeout=120, cwd=str(tmp_path))


def _line(out: str, prefix: str) -> list[str]:
    """The comma-separated names on the first output line starting with prefix."""
    for raw in out.splitlines():
        s = raw.strip()
        if s.startswith(prefix):
            return [x.strip() for x in s[len(prefix):].split(",") if x.strip()]
    return []


@needs_fixpoint
def test_pair_alias_proves(tmp_path):
    p = _verify(tmp_path, "pair_alias.llmll")
    out = p.stdout + p.stderr
    assert p.returncode == 0, out
    assert sorted(_line(out, "body-faithful:")) == sorted(["ret-pt", "min-pt", "mk-pt", "ib-flip"]), out
    assert _line(out, "body-fallback:") == [], out
    assert "SAFE (liquid-fixpoint)" in out and "partial" not in out, out


@needs_fixpoint
def test_pair_alias_refutes(tmp_path):
    p = _verify(tmp_path, "pair_alias_bad.llmll")
    out = p.stdout + p.stderr
    assert p.returncode == 1, out
    assert "liquid-fixpoint: {" not in out, out
    for fn in ["ret-pt-bad", "min-pt", "mk-pt-bad", "ib-flip"]:
        assert f"body verification of '{fn}' failed" in out, out


@needs_fixpoint
def test_pair_alias_call_proves(tmp_path):
    p = _verify(tmp_path, "pair_alias_call.llmll")
    out = p.stdout + p.stderr
    assert p.returncode == 0, out
    assert sorted(_line(out, "body-faithful:")) == sorted(["mk", "use", "use2"]), out
    assert "SAFE (liquid-fixpoint)" in out and "partial" not in out, out


@needs_fixpoint
def test_pair_alias_call_refutes(tmp_path):
    p = _verify(tmp_path, "pair_alias_call_bad.llmll")
    out = p.stdout + p.stderr
    assert p.returncode == 1, out
    assert "liquid-fixpoint: {" not in out, out
    assert "body verification of 'use' failed" in out, out
    assert "call-site precondition of 'mk' not satisfied in 'use2'" in out, out
