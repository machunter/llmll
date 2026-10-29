"""PAIR-BOOL-COMP-1: a bool constructor argument built by `not` or a comparison.

What a pass here means:

* pairs/bool_comp.llmll verifies SAFE with all five functions body-faithful: a
  `not` and a comparison as a pair component (flip, sign), a pair with a `not`
  component in a contract (flip-eq), a user constructor (wrap) and `ok` (okb).
  Before the change each crashed liquid-fixpoint ("Constraint with free vars
  [not]" or a parse error), because the predicate was emitted as an
  application argument, where fixpoint accepts only a term.
* pairs/bool_comp_bad.llmll gives each body the wrong bool argument and is
  refuted at all five, exit 1, with no solver error.
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
def test_bool_comp_proves(tmp_path):
    p = _verify(tmp_path, "bool_comp.llmll")
    out = p.stdout + p.stderr
    assert p.returncode == 0, out
    assert sorted(_line(out, "body-faithful:")) == sorted(["flip", "sign", "flip-eq", "wrap", "okb"]), out
    assert _line(out, "body-fallback:") == [], out
    assert "SAFE (liquid-fixpoint)" in out and "partial" not in out, out


@needs_fixpoint
def test_bool_comp_refutes(tmp_path):
    p = _verify(tmp_path, "bool_comp_bad.llmll")
    out = p.stdout + p.stderr
    assert p.returncode == 1, out
    assert "liquid-fixpoint: {" not in out and "unexpected error" not in out, out
    for fn in ["flip", "sign", "flip-eq", "wrap", "okb"]:
        assert f"body verification of '{fn}' failed" in out, out
