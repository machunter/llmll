"""FFI-TIER2-REFUSE-1: `check` refuses every `c.*` import.

Up to v0.34.0, a `c.*` import passed `check`, and no `c.*` program built
(docs/design/ffi-determinism-proposal.md Part 1, measurement M-BUILD). The
trust report also gave a `c.*` caller no `ffi_assumptions` row (witness W8).

What a pass here means, each file checked with $LLMLL_BIN:

* m_build.llmll (the M-BUILD witness) exits 1 with ffi-tier2-refused.
* m_build.ast.json, the same program as JSON-AST, exits 1 the same way.
* w8.llmll (a c.* callee behind a def-shell wrapper) exits 1 the same way.
* uses_clib.llmll imports clib.llmll, which imports c.stdlib: the importer
  fails check with ffi-tier2-refused (design edge case 4).
"""

import json
import os
import shlex
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURES = REPO_ROOT / "scripts" / "tests" / "fixtures" / "ffi_tier2"

pytestmark = pytest.mark.skipif(
    not os.environ.get("LLMLL_BIN"),
    reason="set LLMLL_BIN to a built llmll",
)


def _check(name: str):
    p = subprocess.run([*shlex.split(os.environ["LLMLL_BIN"]), "--json", "check", name],
                       capture_output=True, text=True, timeout=120, cwd=str(FIXTURES))
    return p.returncode, p.stdout


def _kinds(out: str):
    kinds = []
    for line in out.splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        d = json.loads(line)
        for diag in d.get("diagnostics", [d]):
            if diag.get("severity") == "error":
                kinds.append(diag.get("kind"))
    return kinds


@pytest.mark.parametrize("name", ["m_build.llmll", "m_build.ast.json", "w8.llmll", "uses_clib.llmll"])
def test_c_import_refused(name):
    code, out = _check(name)
    assert code == 1, out
    assert "ffi-tier2-refused" in _kinds(out), out
