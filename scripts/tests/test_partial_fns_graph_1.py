"""PARTIAL-FNS-GRAPH-1 + SHELL-CALL-PRE-1 Part 1: the trust report reads one
module-qualified call graph.

WHAT THE DEFECTS WERE.

  1. `partial_fns` came from a call graph keyed by BARE name across modules.
     Two modules that each define `go` were one node, and the per-entry
     `termination_unverified` flag landed on the wrong function: with a
     recursive `a.go` and a non-recursive entry `go`, the entry `go` was
     flagged and `a.go` was not.
  2. A function used as a value, as in `(list-fold xs acc g)`, added no edge.
     `g` recursing through `list-fold` gave `partial_fns: []`, and a caller of
     `g` was counted as proved with no termination note in the headline.
  3. (SHELL-CALL-PRE-1 Part 1.) `caller_obligations` looked a callee's `pre`
     up by the bare dependency name, and the declared table is keyed
     qualified, so a callee reached through `open` gave no obligation. And
     nothing said that a call from a body with no body VC proves nothing about
     the callee's `pre`.

THE RULE THE CELLS PIN. `partial_fns`, `termination_assumed_fns` and the
transitive `caller_obligations` all read `LLMLL.CallGraph.qualifiedCallGraph`:
entry functions bare, cached ones `m.f`, and an edge for a call or for a
function used as a value that no binder in scope shadows. `verify` prints
`call-pre unchecked: <caller> -> <callee>` for each such call from an
entry-module function that has no body VC.

WHAT EACH CELL DID AGAINST THE PRE-CHANGE (v0.26.13) BINARY, measured.
PFG-1, PFG-2, SCP-1 and SCP-2 FAILED. PFG-3, PFG-4 and SCP-3 PASSED: they are
the negative controls (a helper passed as a value with no cycle, a parameter
that shadows a recursive function's name, and a body-faithful caller), which
must stay quiet.

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

TALLY = """(def tally [seen: int] -> int
  (pre (>= seen 0))
  (post (>= result 1))
  (+ seen 1))
"""

# The pathlint shape: a shell caller reaches a pre-bearing core through `open`.
MAIN_OPENS_ADJ = """(import adj)
(open adj)
(def-shell scan [x: int] -> int
  (tally x))
"""

SAME_MODULE = TALLY + """(def-shell caller [x: int] -> int
  (tally (- 0 5)))
"""

# A body-faithful caller: its call-site obligation is emitted and proved.
FAITHFUL = TALLY + """(def-shell ok [x: int] -> int
  (pre (>= x 0))
  (post (>= result 1))
  (tally x))
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


def test_pfg1_same_named_functions_are_refused(tmp_path: Path):
    """PFG-1. The recursive `a.go` and the entry's own `go` once checked that the
    module-qualified graph keeps them apart. Since v0.28.0 (XMOD-SCOPE) a build's
    top-level names share one scope, so the entry is refused first. If that rule
    is ever relaxed, this test fails and the original check must come back."""
    _write(tmp_path, {"a.llmll": LIB_A, "main.llmll": MAIN_TWO_GOS})
    assert "SAFE (liquid-fixpoint)" in _run(tmp_path, "verify", "a.llmll").stdout
    r = _run(tmp_path, "verify", "main.llmll")
    assert r.returncode == 1, r.stdout + r.stderr
    assert "duplicate top-level definition 'go'" in r.stdout, r.stdout


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


def test_scp1_callee_reached_through_open(tmp_path: Path):
    """SCP-1. The opened callee's pre reaches `caller_obligations` and the verify line."""
    _write(tmp_path, {"adj.llmll": TALLY, "main.llmll": MAIN_OPENS_ADJ})
    assert "SAFE (liquid-fixpoint)" in _run(tmp_path, "verify", "adj.llmll").stdout
    r = _run(tmp_path, "verify", "main.llmll")
    assert "   call-pre unchecked: scan -> adj.tally" in r.stdout, r.stdout
    t = _report(tmp_path, "main.llmll")
    assert _entry(t, "scan")["caller_obligations"] == [
        {"fn": "adj.tally", "requires": "(>= seen 0)"}]


def test_scp2_same_module_callee(tmp_path: Path):
    """SCP-2. The same-module case prints the line; its obligation is unchanged."""
    _write(tmp_path, {"m.llmll": SAME_MODULE})
    r = _run(tmp_path, "verify", "m.llmll")
    assert "   call-pre unchecked: caller -> tally" in r.stdout, r.stdout
    t = _report(tmp_path, "m.llmll")
    assert _entry(t, "caller")["caller_obligations"] == [
        {"fn": "tally", "requires": "(>= seen 0)"}]


def test_scp3_body_faithful_caller_is_quiet(tmp_path: Path):
    """SCP-3 (negative control). A caller with a body VC proves the pre; no line."""
    _write(tmp_path, {"m.llmll": FAITHFUL})
    r = _run(tmp_path, "verify", "m.llmll")
    assert r.returncode == 0, r.stdout + r.stderr
    assert "call-pre obligations: ok" in r.stdout, r.stdout
    assert "call-pre unchecked" not in r.stdout
