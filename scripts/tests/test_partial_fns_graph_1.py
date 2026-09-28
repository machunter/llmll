"""PARTIAL-FNS-GRAPH-1: the trust report reads one module-qualified call graph.

WHAT THE DEFECTS WERE.

  1. `partial_fns` came from a call graph keyed by BARE name across modules.
     Two modules that each define `go` were one node, and the per-entry
     `termination_unverified` flag landed on the wrong function: with a
     recursive `a.go` and a non-recursive entry `go`, the entry `go` was
     flagged and `a.go` was not.
  2. A function used as a value, as in `(list-fold xs acc g)`, added no edge.
     `g` recursing through `list-fold` gave `partial_fns: []`, and a caller of
     `g` was counted as proved with no termination note in the headline.

THE RULE THE CELLS PIN. `partial_fns` and `termination_assumed_fns` both
read `LLMLL.CallGraph.qualifiedCallGraph`:
entry functions bare, cached ones `m.f`, and an edge for a call or for a
function used as a value that no binder in scope shadows.

WHAT EACH CELL DID AGAINST THE PRE-CHANGE (v0.26.13) BINARY, measured.
PFG-1 and PFG-2 FAILED. PFG-3 and PFG-4 PASSED: they are the negative controls
(a helper passed as a value with no cycle, and a parameter that shadows a
recursive function's name), which must stay quiet.

WHY IT SKIPS WITHOUT A BINARY. Every cell calls `llmll verify`, which shells
out to liquid-fixpoint. The spec-roundtrip job runs this file with LLMLL_BIN
set, after fixpoint is on PATH.
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
    reason="set LLMLL_BIN to a built llmll; the spec-roundtrip job runs this in CI "
           "(the cells call `llmll verify`, which shells out to liquid-fixpoint)",
)

# Module `a`: a `go` that never returns.
LIB_A = """(def-shell go [x: int] -> int
  (post (>= result 0))
  (go x))
"""

# The entry defines its own `go`, which does not recurse, and calls `a.go`.
MAIN_TWO_GOS = """(import a)
(def-shell go [x: int] -> int
  (post (= result x))
  x)
(def-shell top [x: int] -> int
  (post (>= result 0))
  (a.go x))
"""

# `g` recurses only through `list-fold`, as a value; `h` calls `g`.
FOLD_REC = """(def-shell g [acc: int y: int] -> int
  (post (= result 42))
  (list-fold (list-prepend y (list-empty)) acc g))
(def-shell h [x: int] -> int
  (post (= result 42))
  (g x x))
"""

# A helper passed as a value with no cycle: nothing is partial.
MAP_NO_CYCLE = """(def-shell inc [x: int] -> int
  (post (= result (+ x 1)))
  (+ x 1))
(def-shell lens [xs: list[int]] -> int
  (post (>= result 0))
  (list-length (list-map xs inc)))
"""

# `k`'s parameter shadows the recursive `spin`; `k` does not reach `spin`.
SHADOW = """(def-shell spin [x: int] -> int
  (post (= result 42))
  (spin x))
(def-shell k [spin: int] -> int
  (post (= result spin))
  spin)
"""

def _run(workdir: Path, *args: str, json_mode: bool = False):
    llmll = shlex.split(os.environ["LLMLL_BIN"])
    argv = [*llmll, *(["--json"] if json_mode else []), *args]
    return subprocess.run(argv, cwd=workdir, capture_output=True, text=True,
                          encoding="utf-8", timeout=300)


def _json(stdout: str, key: str) -> dict:
    for line in reversed(stdout.strip().splitlines()):
        try:
            obj = json.loads(line)
        except ValueError:
            continue
        if key in obj:
            return obj
    raise AssertionError(f"no object with {key!r} in output:\n" + stdout)


def _write(d: Path, files: dict[str, str]) -> Path:
    for name, text in files.items():
        (d / name).write_text(text)
    return d


def _report(d: Path, name: str) -> dict:
    r = _run(d, "verify", name)
    assert "SAFE (liquid-fixpoint)" in r.stdout, r.stdout + r.stderr
    return _json(_run(d, "verify", "--trust-report", name, json_mode=True).stdout,
                 "partial_fns")


def _entry(report: dict, name: str) -> dict:
    return next(e for e in report["entries"] if e["name"] == name)


def test_pfg1_same_named_functions_stay_apart(tmp_path: Path):
    """PFG-1. The recursive `a.go` is partial and flagged; the entry `go` is not."""
    _write(tmp_path, {"a.llmll": LIB_A, "main.llmll": MAIN_TWO_GOS})
    assert "SAFE (liquid-fixpoint)" in _run(tmp_path, "verify", "a.llmll").stdout
    t = _report(tmp_path, "main.llmll")
    assert t["partial_fns"] == ["a.go"]
    flagged = sorted(e["name"] for e in t["entries"] if e.get("termination_unverified"))
    assert flagged == ["a.go"]


def test_pfg2_recursion_through_a_function_value(tmp_path: Path):
    """PFG-2. `g` is partial, and the headline names `h` as proved only if `g` returns."""
    _write(tmp_path, {"m.llmll": FOLD_REC})
    r = _run(tmp_path, "verify", "m.llmll")
    assert "1 proved only if it terminates: h (via g)" in r.stdout, r.stdout
    t = _report(tmp_path, "m.llmll")
    assert t["partial_fns"] == ["g"]
    assert t["termination_assumed_fns"] == [{"name": "g", "via": "g"},
                                            {"name": "h", "via": "g"}]


def test_pfg3_function_value_without_a_cycle(tmp_path: Path):
    """PFG-3 (negative control). A helper passed to `list-map` makes nothing partial."""
    _write(tmp_path, {"m.llmll": MAP_NO_CYCLE})
    t = _report(tmp_path, "m.llmll")
    assert t["partial_fns"] == []
    assert t["termination_assumed_fns"] == []


def test_pfg4_a_shadowing_parameter_adds_no_edge(tmp_path: Path):
    """PFG-4 (negative control). `k` uses its parameter `spin`, not the function."""
    _write(tmp_path, {"m.llmll": SHADOW})
    t = _report(tmp_path, "m.llmll")
    assert t["partial_fns"] == ["spin"]
    assert [x["name"] for x in t["termination_assumed_fns"]] == ["spin"]
