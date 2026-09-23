"""BUILD-NOSTACK-1: `llmll build` FAILS when neither `stack` nor `ghc` is on PATH.

WHAT THE DEFECT WAS. `runGhcCheck` (`compiler/app/Main.hs`) validates the
generated package with `stack build`, then with `ghc --make`. When it found
neither, it printed `WARN: stack/ghc not found` and returned True ("non-fatal;
user can build manually"). So `build` printed `OK Generated Haskell package`
and exited 0 having compiled nothing. Under `--json` it printed the
`"ghc_check": false` object AND a `"success": true` object, and still exited 0.
Every caller that grades the exit status read that as a build. The doc-claims
cover found it (REPORT-GATE-1) because its scrubbed PATH hid `stack`.

WHAT EACH CELL DID AGAINST THE PRE-FIX BINARY, measured and not assumed.
NS-1, NS-2 and NS-3 FAILED: each exited 0. NS-4 PASSED, and that is correct:
it pins `--emit-only`, the flag that serves the write-sources case the
non-fatal path used to serve. A fix that made every toolchain-less `build`
fail, `--emit-only` included, would fail NS-4.

WHY THE PATH IS AN EMPTY DIRECTORY. The cells need a PATH that holds neither
`stack` nor `ghc` on any runner. `/usr/bin:/bin` is not safe for that, because
a system GHC can live there. `llmll build` execs nothing else before the
toolchain check, so an empty directory is enough, and the binary is named by
its absolute path.

WHY IT SKIPS WITHOUT A BINARY. `pytest scripts/tests/` runs in version-gate's
C1-C4 job, which builds no compiler. The cells need no toolchain themselves,
but they need the freshly built `llmll`, so the spec-roundtrip job runs them
with LLMLL_BIN set, beside the other binary-gated cells.
"""

from __future__ import annotations

import json
import os
import shlex
import subprocess
from pathlib import Path

import pytest

pytestmark = pytest.mark.skipif(
    not os.environ.get("LLMLL_BIN"),
    reason="set LLMLL_BIN to a built llmll; the spec-roundtrip job runs this in CI",
)

# Code generation only; no cell reaches a toolchain.
TIMEOUT_S = 60

SOURCE = "(def-shell ns-inc [x: int] -> int\n  (+ x 1))\n"
MISSING = "stack/ghc not found"


def _llmll() -> list[str]:
    return shlex.split(os.environ["LLMLL_BIN"])


@pytest.fixture
def work(tmp_path: Path) -> Path:
    (tmp_path / "emptybin").mkdir()
    (tmp_path / "nostack.llmll").write_text(SOURCE)
    return tmp_path


def _build(work: Path, *args: str) -> subprocess.CompletedProcess:
    env = {"PATH": str(work / "emptybin"), "HOME": str(work)}
    return subprocess.run(
        _llmll() + list(args),
        cwd=work, env=env, capture_output=True, text=True, timeout=TIMEOUT_S,
    )


def test_ns1_build_fails_without_toolchain(work: Path) -> None:
    """Pre-fix: exit 0, `WARN: stack/ghc not found`, then `OK Generated`."""
    p = _build(work, "build", "nostack.llmll", "-o", "out")
    out = p.stdout + p.stderr
    assert p.returncode != 0, f"build exited 0 with no toolchain:\n{out}"
    assert f"FAIL: {MISSING}" in out, out
    assert "--emit-only" in out, "the failure should name the escape flag"
    assert "OK Generated" not in out, out


def test_ns2_json_build_reports_no_success(work: Path) -> None:
    """Pre-fix: exit 0, `ghc_check: false`, then `success: true`."""
    p = _build(work, "--json", "build", "nostack.llmll", "-o", "out")
    assert p.returncode != 0, f"--json build exited 0:\n{p.stdout}{p.stderr}"
    objs = [json.loads(line) for line in p.stdout.splitlines() if line.strip()]
    assert any(o.get("ghc_check") is False and MISSING in o.get("error", "")
               for o in objs), objs
    assert not any(o.get("success") is True for o in objs), objs


def test_ns3_json_ast_build_fails_without_toolchain(work: Path) -> None:
    """The .ast.json input has its own build path, doBuildFromJson.

    Pre-fix: exit 0 and `OK Generated Haskell package from JSON-AST`.
    """
    emit = _build(work, "build", "--emit", "nostack.llmll")
    assert emit.returncode == 0, emit.stdout + emit.stderr
    asts = list(work.rglob("nostack.ast.json"))
    assert len(asts) == 1, f"expected one emitted JSON-AST, found {asts}"
    p = _build(work, "build", str(asts[0]), "-o", "out-json")
    out = p.stdout + p.stderr
    assert p.returncode != 0, f"JSON-AST build exited 0 with no toolchain:\n{out}"
    assert f"FAIL: {MISSING}" in out, out
    assert "OK Generated" not in out, out


def test_ns4_emit_only_still_succeeds(work: Path) -> None:
    """`--emit-only` writes the package and skips the build, toolchain or not.

    Passed before the fix too. It pins the escape the fix points at.
    """
    p = _build(work, "build", "--emit-only", "nostack.llmll", "-o", "out")
    out = p.stdout + p.stderr
    assert p.returncode == 0, out
    assert MISSING not in out, "--emit-only must not look for a toolchain"
    assert (work / "out" / "src" / "Lib.hs").is_file(), out
