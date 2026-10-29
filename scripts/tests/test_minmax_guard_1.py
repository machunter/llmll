"""MINMAX-GUARD-1: `min`, `max` and `abs` in an `if` guard.

What a pass here means:

* minmax/guard.llmll verifies SAFE with all three functions body-faithful:
  a `min` guard (clamp), a `max` guard whose fact the else-branch needs
  (pick-hi) and an `abs` guard (cap). Before the change each fell back with
  "Refused by: if", so its post was assumed and not proved.
* minmax/guard_bad.llmll puts the wrong branch in each body and is refuted at
  all three, exit 1. Its fourth function calls a parameter named `min`, which
  is not the builtin, and is refuted too: a shadowed `min` never proves.
"""

import os
import shlex
import shutil
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURES = REPO_ROOT / "scripts" / "tests" / "fixtures" / "minmax"

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
def test_minmax_guard_proves(tmp_path):
    p = _verify(tmp_path, "guard.llmll")
    out = p.stdout + p.stderr
    assert p.returncode == 0, out
    assert sorted(_line(out, "body-faithful:")) == sorted(["clamp", "pick-hi", "cap"]), out
    assert _line(out, "body-fallback:") == [], out
    assert "SAFE (liquid-fixpoint)" in out and "partial" not in out, out


@needs_fixpoint
def test_minmax_guard_refutes(tmp_path):
    p = _verify(tmp_path, "guard_bad.llmll")
    out = p.stdout + p.stderr
    assert p.returncode == 1, out
    assert "liquid-fixpoint: {" not in out, out
    for fn in ["clamp", "pick-hi", "cap", "gs"]:
        assert f"body verification of '{fn}' failed" in out, out
