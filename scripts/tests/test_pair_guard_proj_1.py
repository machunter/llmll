"""PAIR-GUARD-PROJ-1: `first` / `second` of a pair parameter in an `if` guard.

What a pass here means:

* pairs/pair_guard.llmll verifies SAFE with all four functions body-faithful:
  an int component compared (min-by-first), a bool component as the guard
  atom (flag-to-int), a nested projection (nested-cmp) and a string component
  against a literal (str-key). Before the change each fell back with
  "Refused by: if".
* pairs/pair_guard_bad.llmll takes the wrong branch of the same guard in each
  function and is refuted at all four, exit 1, so the guard is not vacuous.
"""

import os
import shlex
import shutil
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURES = REPO_ROOT / "scripts" / "tests" / "fixtures" / "pairs"
FNS = ["min-by-first", "flag-to-int", "nested-cmp", "str-key"]

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
def test_pair_guard_proves(tmp_path):
    p = _verify(tmp_path, "pair_guard.llmll")
    out = p.stdout + p.stderr
    assert p.returncode == 0, out
    assert sorted(_line(out, "body-faithful:")) == sorted(FNS), out
    assert _line(out, "body-fallback:") == [], out
    assert "SAFE (liquid-fixpoint)" in out and "partial" not in out, out


@needs_fixpoint
def test_pair_guard_refutes(tmp_path):
    p = _verify(tmp_path, "pair_guard_bad.llmll")
    out = p.stdout + p.stderr
    assert p.returncode == 1, out
    for fn in FNS:
        assert f"body verification of '{fn}' failed" in out, out
