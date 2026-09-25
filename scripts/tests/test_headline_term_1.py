"""HEADLINE-TERM-1 + STRICT-XMOD-1: a proof that rests on termination or on an
unproved import is not shown as proved.

WHAT THE DEFECTS WERE. The `verify` headline printed the check mark when every
contracted function was body-faithful (VERIFY-HEADLINE-1). Two cases escaped:

  1. A function in a recursive cycle without a discharging `(decreases ...)`
     measure is proved at partial correctness only: a body that never returns
     meets any postcondition. So is every function that CALLS such a cycle,
     including a non-recursive caller in another module. `spin` with body
     `(spin x)` and post `(= result 42)`, and `use` calling it, printed the
     check mark, and across modules `--strict-verified-core` passed too.
  2. A proved function that calls an imported contract which is NOT proved
     (the import fell back, was never verified, or was edited since) printed
     the check mark and passed `--strict-verified-core`, although LLMLL.md
     §5.3 conjunct (d) says strict-core refuses an asserted-tier dependency.
     The gate read only the entry module's own emit result.

THE RULE THE CELLS PIN. Over one call graph of the whole program (entry plus
imports, names qualified by module), T is the proved functions that reach an
undischarged cycle and D is the other proved functions that reach an unproved
imported contract. Each is named with the function it reaches ("via"). The
check mark needs T and D empty. Strict-core refuses D and admits T (partial
correctness is what the §3.4.3 soundness statement covers).

WHAT EACH CELL DID AGAINST THE PRE-CHANGE (v0.26.4) BINARY, measured.
HT-1, HT-2, HT-3, HT-4, HT-5, HT-7, HT-9 and HT-10 FAILED: the check mark
printed (or strict-core passed, or the JSON lacked the field, or the old
diagnostic text printed). HT-6 and HT-8 PASSED: they are the negative controls
(a discharged recursion, and a same-named non-recursive function in another
module), which must stay a check mark.

WHY IT SKIPS WITHOUT A BINARY. Same as test_verify_headline_1.py: every cell
calls `llmll verify`, which shells out to liquid-fixpoint. The spec-roundtrip
job runs this file with LLMLL_BIN set, after fixpoint is on PATH.
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

SPIN = """(def-shell spin [x: int] -> int
  (post (= result 42))
  (spin x))
"""

# A non-recursive caller of a function that never returns.
CALLER3 = SPIN + """(def-shell use [s: int] -> int
  (post (= result 42))
  (spin s))
"""

MAIN_USES_SPIN = """(import loop)
(open loop)
(def-shell use [s: int] -> int
  (post (= result 42))
  (spin s))
"""

# The import claims 42 and returns x*x: the body falls back, so the post is
# assumed, and it is false.
LIB_SQ = """(def-shell sq [x: int] -> int
  (post (= result 42))
  (* x x))
"""

MAIN_USES_SQ = """(import lib)
(open lib)
(def-shell use [s: int] -> int
  (post (= result 42))
  (sq s))
"""

# use -> helper (no contract, so no trust entry) -> loop.spin. `use` returns
# 42 itself, so its post is proved; it still never returns, because the call to
# `helper` runs first.
MAIN_VIA_HELPER = """(import loop)
(open loop)
(def-shell helper [s: int] -> int
  (spin s))
(def-shell use [s: int] -> int
  (post (= result 42))
  (let [(r (helper s))] 42))
"""

CD = """(def-shell cd [n: int] -> int
  (pre (>= n 0))
  (post (= result 0))
  (decreases n)
  (if (= n 0) 0 (cd (- n 1))))
"""

MAIN_USES_CD = """(import lib)
(open lib)
(def use [n: int] -> int
  (pre (>= n 0))
  (post (= result 0))
  (cd n))
"""

GO_REC = """(def-shell go [x: int] -> int
  (post (= result 42))
  (go x))
"""

GO_FLAT = """(def-shell go [x: int] -> int
  (post (= result 42))
  42)
"""

# Both modules define `go`; only `modb` is opened, and its `go` terminates.
MAIN_USES_GO = """(import moda)
(import modb)
(open modb)
(def-shell use [s: int] -> int
  (post (= result 42))
  (go s))
"""

SAME_FILE_DEF = CD + """(def use [n: int] -> int
  (pre (>= n 0))
  (post (= result 0))
  (cd n))
"""

TERM_HINT = ("   (termination: add a (decreases …) measure to the recursive "
             "function; see --trust-report)")


def _run(workdir: Path, *args: str, json_mode: bool = False):
    llmll = shlex.split(os.environ["LLMLL_BIN"])
    argv = [*llmll, *(["--json"] if json_mode else []), *args]
    return subprocess.run(argv, cwd=workdir, capture_output=True, text=True,
                          encoding="utf-8", timeout=300)


def _headline(stdout: str) -> list[str]:
    lines = stdout.splitlines()
    for i, line in enumerate(lines):
        if "SAFE (liquid-fixpoint)" in line:
            return lines[i:i + 2]
    raise AssertionError("no SAFE (liquid-fixpoint) line in output:\n" + stdout)


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


def _verified_lib(d: Path, name: str) -> None:
    """Verify an imported module first, so its sidecar records its levels."""
    r = _run(d, "verify", name)
    assert "SAFE (liquid-fixpoint)" in r.stdout, r.stdout + r.stderr


def test_ht1_same_file_caller_of_a_divergent_function(tmp_path: Path):
    """HT-1. The cycle member and its non-recursive caller are both named."""
    _write(tmp_path, {"caller3.llmll": CALLER3})
    r = _run(tmp_path, "verify", "caller3.llmll")
    assert r.returncode == 0, r.stdout + r.stderr
    assert _headline(r.stdout) == [
        "⚠️  caller3.llmll — SAFE (liquid-fixpoint), 2 of 2 contracted functions "
        "proved; 2 proved only if they terminate: spin, use (via spin)",
        TERM_HINT,
    ]


def test_ht2_cross_module_caller_is_named_and_strict_core_admits_it(tmp_path: Path):
    """HT-2. The professor's witness: no recursion in the entry file at all."""
    _write(tmp_path, {"loop.llmll": SPIN, "main.llmll": MAIN_USES_SPIN})
    _verified_lib(tmp_path, "loop.llmll")
    r = _run(tmp_path, "verify", "main.llmll")
    assert r.returncode == 0, r.stdout + r.stderr
    assert _headline(r.stdout) == [
        "⚠️  main.llmll — SAFE (liquid-fixpoint), 1 of 1 contracted functions "
        "proved; 1 proved only if it terminates: use (via loop.spin)",
        TERM_HINT,
    ]
    s = _run(tmp_path, "verify", "--strict-verified-core", "main.llmll")
    assert s.returncode == 0, s.stdout + s.stderr
    assert "ERROR" not in s.stdout


def test_ht3_caller_of_an_imported_fallback_is_refused(tmp_path: Path):
    """HT-3. STRICT-XMOD-1: the import's false post was assumed, not proved."""
    _write(tmp_path, {"lib.llmll": LIB_SQ, "main.llmll": MAIN_USES_SQ})
    _verified_lib(tmp_path, "lib.llmll")
    r = _run(tmp_path, "verify", "main.llmll")
    assert r.returncode == 0, r.stdout + r.stderr
    assert _headline(r.stdout) == [
        "⚠️  main.llmll — SAFE (liquid-fixpoint), 1 of 1 contracted functions "
        "proved; 1 proved on unproved imported contracts: use (via lib.sq)",
        "   (--strict-verified-core fails on assumed functions and their callers)",
    ]
    s = _run(tmp_path, "verify", "--strict-verified-core", "main.llmll")
    assert s.returncode == 1, s.stdout + s.stderr
    assert ("ERROR: --strict-verified-core: 1 function(s) depend on unproved "
            "imported contracts: use (via lib.sq)") in s.stdout


def test_ht4_import_never_verified_counts_as_unproved(tmp_path: Path):
    """HT-4. No sidecar for the import: its contract is asserted."""
    _write(tmp_path, {"lib.llmll": SPIN.replace("(spin x)", "42").replace("spin", "k"),
                      "main.llmll": MAIN_USES_SQ.replace("(sq s)", "(k s)")})
    r = _run(tmp_path, "verify", "main.llmll")
    assert r.returncode == 0, r.stdout + r.stderr
    assert "1 proved on unproved imported contracts: use (via lib.k)" in _headline(r.stdout)[0]
    s = _run(tmp_path, "verify", "--strict-verified-core", "main.llmll")
    assert s.returncode == 1, s.stdout + s.stderr


def test_ht5_closure_passes_through_an_uncontracted_helper(tmp_path: Path):
    """HT-5. `helper` has no contract, so it has no trust entry; the graph still has it."""
    _write(tmp_path, {"loop.llmll": SPIN, "main.llmll": MAIN_VIA_HELPER})
    _verified_lib(tmp_path, "loop.llmll")
    r = _run(tmp_path, "verify", "main.llmll")
    assert "1 proved only if it terminates: use (via loop.spin)" in _headline(r.stdout)[0], r.stdout


def test_ht6_discharged_recursion_keeps_the_check_mark(tmp_path: Path):
    """HT-6. Negative control: a (decreases n) cycle is total, so nothing changes."""
    _write(tmp_path, {"lib.llmll": CD, "main.llmll": MAIN_USES_CD})
    _verified_lib(tmp_path, "lib.llmll")
    r = _run(tmp_path, "verify", "main.llmll")
    assert r.returncode == 0, r.stdout + r.stderr
    assert _headline(r.stdout)[0] == "✅ main.llmll — SAFE (liquid-fixpoint)"
    s = _run(tmp_path, "verify", "--strict-verified-core", "main.llmll")
    assert s.returncode == 0, s.stdout + s.stderr


def test_ht7_json_names_both_sets_with_their_via(tmp_path: Path):
    """HT-7. The --json fields, and all_proved false for either set."""
    a = tmp_path / "a"
    a.mkdir()
    _write(a, {"loop.llmll": SPIN, "main.llmll": MAIN_USES_SPIN})
    _verified_lib(a, "loop.llmll")
    j = _json(_run(a, "verify", "main.llmll", json_mode=True).stdout, "solver_verdict")
    assert j["all_proved"] is False
    assert j["termination_assumed_fns"] == [{"name": "use", "via": "loop.spin"}]
    assert j["import_assumed_fns"] == []

    b = tmp_path / "b"
    b.mkdir()
    _write(b, {"lib.llmll": LIB_SQ, "main.llmll": MAIN_USES_SQ})
    _verified_lib(b, "lib.llmll")
    j = _json(_run(b, "verify", "main.llmll", json_mode=True).stdout, "solver_verdict")
    assert j["all_proved"] is False
    assert j["termination_assumed_fns"] == []
    assert j["import_assumed_fns"] == [{"name": "use", "via": "lib.sq"}]


def test_ht8_same_name_in_two_modules_does_not_merge(tmp_path: Path):
    """HT-8. Negative control: `moda.go` loops, `modb.go` does not, only modb is opened."""
    _write(tmp_path, {"moda.llmll": GO_REC, "modb.llmll": GO_FLAT,
                      "main.llmll": MAIN_USES_GO})
    _verified_lib(tmp_path, "moda.llmll")
    _verified_lib(tmp_path, "modb.llmll")
    r = _run(tmp_path, "verify", "main.llmll")
    assert r.returncode == 0, r.stdout + r.stderr
    assert _headline(r.stdout)[0] == "✅ main.llmll — SAFE (liquid-fixpoint)"


def test_ht9_same_file_def_callee_gets_the_placement_diagnostic(tmp_path: Path):
    """HT-9. Item (4): the old text said a verified callee was not body-faithful."""
    _write(tmp_path, {"same.llmll": SAME_FILE_DEF})
    r = _run(tmp_path, "verify", "same.llmll")
    out = r.stdout + r.stderr
    assert ("def 'use': callee 'cd' is defined in this file and has no recorded "
            "verification") in out, out
    assert "must also be descent-discharged" in out
    assert "Move 'cd' to its own module with a (decreases …) measure, verify it, then import it" in out
    assert "is not body-faithful" not in out


def test_ht10_trust_report_carries_the_closure(tmp_path: Path):
    """HT-10. The report and the headline agree about `use`; version 1.7.0."""
    _write(tmp_path, {"caller3.llmll": CALLER3})
    assert _run(tmp_path, "verify", "caller3.llmll").returncode == 0
    t = _json(_run(tmp_path, "verify", "--trust-report", "caller3.llmll",
                   json_mode=True).stdout, "trust_report_version")
    assert t["trust_report_version"] == "1.7.0"
    assert t["termination_assumed_fns"] == [{"name": "spin", "via": "spin"},
                                            {"name": "use", "via": "spin"}]
    assert t["partial_fns"] == ["spin"]
    use = next(e for e in t["entries"] if e["name"] == "use")
    assert use.get("termination_assumed") is True
    text = _run(tmp_path, "verify", "--trust-report", "caller3.llmll").stdout
    assert "Proved only if a called function terminates:" in text
    assert "  ↳ use (via spin)" in text
