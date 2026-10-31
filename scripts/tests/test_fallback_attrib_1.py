"""FALLBACK-ATTRIB-1: W-BODY-FALLBACK names the term that refused.

What a pass here means:

* In fallback_attrib/attrib.llmll, each body fallback names its innermost
  refused term (`nonlinear:*`, `app:string-slice`), not the enclosing `if` or
  `let`. An `if` in argument position, which the body translator refuses, is
  named `if`.
* A post that calls a function and a nonlinear pre each raise W-BODY-FALLBACK
  with their contract cause. Before the change they raised nothing in text mode.
* `g`, which has no post, raises no warning.
"""

import os
import re
import shlex
import shutil
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURES = REPO_ROOT / "scripts" / "tests" / "fixtures" / "fallback_attrib"

pytestmark = pytest.mark.skipif(
    not os.environ.get("LLMLL_BIN"),
    reason="set LLMLL_BIN to a built llmll",
)


def _warnings(tmp_path: Path) -> dict[str, set[tuple[str, str]]]:
    """Each function's (cause, labels) pairs from its W-BODY-FALLBACK lines."""
    shutil.copy(FIXTURES / "attrib.llmll", tmp_path / "attrib.llmll")
    p = subprocess.run([*shlex.split(os.environ["LLMLL_BIN"]), "verify", "attrib.llmll"],
                       capture_output=True, text=True, timeout=120, cwd=str(tmp_path))
    out = p.stdout + p.stderr
    found: dict[str, set[tuple[str, str]]] = {}
    for m in re.finditer(r"W-BODY-FALLBACK: '([^']+)' fell back from body-faithful "
                         r"verification \(([^)]+)\).*?Refused by: ([^.]+)\.", out):
        found.setdefault(m.group(1), set()).add((m.group(2), m.group(3)))
    return found


def test_body_fallback_names_the_refused_term(tmp_path):
    w = _warnings(tmp_path)
    assert w.get("sq-pos") == {("body-outside-fragment", "nonlinear:*")}, w
    assert w.get("sq-let") == {("body-outside-fragment", "nonlinear:*")}, w
    assert w.get("first-len") == {("body-outside-fragment", "app:string-slice")}, w
    assert w.get("prod") == {("body-outside-fragment", "nonlinear:*")}, w
    assert w.get("if-arg") == {("body-outside-fragment", "if")}, w


def test_contract_cause_warns_and_no_post_does_not(tmp_path):
    w = _warnings(tmp_path)
    assert w.get("post-call") == {("contract-post-outside-fragment", "app:g")}, w
    assert w.get("pre-sq") == {("contract-pre-outside-fragment", "nonlinear:*")}, w
    assert "g" not in w, w
