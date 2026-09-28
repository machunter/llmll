"""DEF-ADMIT-XMOD-1: a `def` may not rest on an imported function that is
proved only if a recursion terminates.

WHAT THE DEFECT WAS. A `def` is a total-correctness claim (LLMLL.md §4.2): a
recursive callee is admissible only when a `(decreases …)` measure discharges
its termination. The admissibility check tested recursion in the CURRENT
module only, with the call graph that has no value edges. So a `def` that
called an imported recursive `spin`, or an imported `mid` that calls `spin`,
or that passed `spin` to `list-map`, passed `check`, `verify` and
`--strict-verified-core`.

THE RULE THE CELLS PIN. The type checker computes the set the verify headline
names ("proved only if it terminates") over `LLMLL.CallGraph`'s
module-qualified graph, minus the descent-discharged functions, and refuses a
`def` that calls, or passes as a value, a function in that set. The message
names the recursion it reaches.

WHAT EACH CELL DID AGAINST THE PRE-CHANGE (v0.26.14) BINARY, measured.
DAX-1, DAX-2 and DAX-4 FAILED: `check` passed. DAX-3, DAX-5 and DAX-6 PASSED:
they are the negative controls (a descent-discharged callee, a non-recursive
callee, and a parameter that shadows the recursive function's name), which
must stay admitted.

WHY IT SKIPS WITHOUT A BINARY. The cells call `llmll verify` on the imported
module first, which shells out to liquid-fixpoint. The spec-roundtrip job runs
this file with LLMLL_BIN set, after fixpoint is on PATH.
"""

from __future__ import annotations

import os
import shlex
import subprocess
from pathlib import Path

import pytest

pytestmark = pytest.mark.skipif(
    not os.environ.get("LLMLL_BIN"),
    reason="set LLMLL_BIN to a built llmll; the spec-roundtrip job runs this in CI "
           "(the cells call `llmll verify`, which shells out to liquid-fixpoint)",
)

# `spin` never returns; `mid` does not recurse but calls `spin`.
LOOP = """(def-shell spin [x: int] -> int (post (= result 42)) (spin x))
(def-shell mid [x: int] -> int (post (= result 42)) (spin x))
"""

# `cd` recurses with a discharging measure; `viacd` does not recurse and calls
# `cd`; `plain` does not recurse.
CDM = """(def-shell cd [n: int] -> int (pre (>= n 0)) (post (>= result 0)) (decreases n)
  (if (= n 0) 0 (cd (- n 1))))
(def-shell viacd [n: int] -> int (pre (>= n 0)) (post (>= result 0)) (cd n))
(def-shell plain [x: int] -> int (post (= result (+ x 1))) (+ x 1))
"""

REFUSED = "a def may call only functions whose termination is proved"


def _run(workdir: Path, *args: str):
    llmll = shlex.split(os.environ["LLMLL_BIN"])
    return subprocess.run([*llmll, *args], cwd=workdir, capture_output=True, text=True,
                          encoding="utf-8", timeout=300)


def _lib(d: Path, name: str, text: str) -> None:
    """Write and verify an imported module, so its sidecar records its evidence."""
    (d / name).write_text(text)
    r = _run(d, "verify", name)
    assert "SAFE (liquid-fixpoint)" in r.stdout, r.stdout + r.stderr


def _check(d: Path, text: str):
    (d / "main.llmll").write_text(text)
    r = _run(d, "check", "main.llmll")
    return r, r.stdout + r.stderr


def test_dax1_direct_call_to_imported_recursion(tmp_path: Path):
    """DAX-1. A def calling the imported recursive `spin` is refused."""
    _lib(tmp_path, "loop.llmll", LOOP)
    r, out = _check(tmp_path, "(import loop)\n(open loop)\n"
                    "(def use [s: int] -> int (post (= result 42)) (spin s))\n")
    assert r.returncode != 0, out
    assert "callee 'spin' is proved only if 'loop.spin' terminates" in out, out
    assert REFUSED in out


def test_dax2_callee_that_reaches_a_recursion(tmp_path: Path):
    """DAX-2. `mid` does not recurse but calls `spin`; the def is refused via `loop.spin`."""
    _lib(tmp_path, "loop.llmll", LOOP)
    r, out = _check(tmp_path, "(import loop)\n(open loop)\n"
                    "(def use2 [s: int] -> int (post (= result 42)) (mid s))\n")
    assert r.returncode != 0, out
    assert "callee 'mid' is proved only if 'loop.spin' terminates" in out, out


def test_dax3_discharged_recursion_is_admitted(tmp_path: Path):
    """DAX-3 (negative control). A descent-discharged `cd` stays callable, and so
    does `viacd`, which calls it. `viacd` carries no termination bit of its own,
    so only the discharge subtraction in the set admits it: this is the half of
    the cell that fails when that subtraction is removed."""
    _lib(tmp_path, "cdm.llmll", CDM)
    r, out = _check(tmp_path, "(import cdm)\n(open cdm)\n"
                    "(def usecd [s: int] -> int (pre (>= s 0)) (post (>= result 0)) (cd s))\n"
                    "(def usevia [s: int] -> int (pre (>= s 0)) (post (>= result 0)) (viacd s))\n")
    assert r.returncode == 0, out
    assert REFUSED not in out


def test_dax4_recursion_passed_as_a_value(tmp_path: Path):
    """DAX-4. Passing `spin` to `list-map` is refused like a call."""
    _lib(tmp_path, "loop.llmll", LOOP)
    r, out = _check(tmp_path, "(import loop)\n(open loop)\n"
                    "(def lens [xs: list[int]] -> int (post (>= result 0))\n"
                    "  (list-length (list-map xs spin)))\n")
    assert r.returncode != 0, out
    assert "callee 'spin' is proved only if 'loop.spin' terminates" in out, out


def test_dax5_non_recursive_callee_is_admitted(tmp_path: Path):
    """DAX-5 (negative control). A verified non-recursive import stays callable."""
    _lib(tmp_path, "cdm.llmll", CDM)
    r, out = _check(tmp_path, "(import cdm)\n(open cdm)\n"
                    "(def useplain [s: int] -> int (post (= result (+ s 1))) (plain s))\n")
    assert r.returncode == 0, out
    assert REFUSED not in out


def test_dax6_a_shadowing_parameter_is_not_the_function(tmp_path: Path):
    """DAX-6 (negative control). A parameter named `spin` is not the import."""
    _lib(tmp_path, "loop.llmll", LOOP)
    r, out = _check(tmp_path, "(import loop)\n(open loop)\n"
                    "(def k [spin: int] -> int (post (= result spin)) spin)\n")
    assert r.returncode == 0, out
    assert REFUSED not in out
