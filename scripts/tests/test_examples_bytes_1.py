"""EXAMPLES-BYTES-1: the verified byte-buffer modules of the examples
(plan: EXAMPLES-BYTES-1 Rev 1, "Contract plan" and "Test plan").

What a pass here means:

* Y4M-V: examples/y4m/ybuf.llmll verifies after raster and xform: exit 0,
  5 of 5 contracted functions proved, and no `abstraction:app:bytes-*`
  fallback. The correct bodies need nothing from the abstraction verdict.
* Y4M-M1, M2, M4A, M5: a wrong body of find-lf (Y-1), marker-end (Y-2),
  crop-row (Y-4 A) and hflip-at (Y-5) is refuted: exit 1, solver verdict
  `refuted`, and an `lh-unsafe` diagnostic that names the function. M4A
  breaks the outer slice's call pre, which rests on the exact length of the
  inner slice, so it pins ABSTRACTION-LEN-EXACT-1 on example code.
* Y4M-M3, M4B: a wrong body of luma-plane (Y-3) and crop-row (Y-4 B) breaks
  only the length post of the returned slice. Today that falls back, exit 0,
  with `abstraction:app:bytes-slice` (finding F-2). These cells pin that
  verdict; a fix of ABSTRACTION-RESULT-LEN-1 flips them to refuted, and the
  cells must then be moved to the refuted list.

Each cell verifies private copies of the example modules, so no sidecar is
written into the tree. The mutants are spelled out here rather than read
from examples/y4m/tools/mutants.py, so a change there cannot change what
these cells check.

* SWARM-V: examples/netpbm-swarm/binfmt.llmll verifies after types: exit 0,
  4 of 4 contracted functions proved, no `abstraction:app:bytes-*` fallback,
  and header-end (a def-shell with a decreases clause) is total.
* SWARM-B1 .. B4: a wrong body of byte-class, header-end, raster-len and
  bin-sample is refuted, naming the function.

The netpbm `binfmt` cells (commit 3) go below the netpbm-swarm ones.
"""

import json
import os
import shlex
import shutil
import subprocess
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[2]
Y4M = REPO / "examples" / "y4m"
SWARM = REPO / "examples" / "netpbm-swarm"

pytestmark = [
    pytest.mark.skipif(not os.environ.get("LLMLL_BIN"), reason="set LLMLL_BIN to a built llmll"),
    pytest.mark.skipif(
        shutil.which("liquid-fixpoint") is None and shutil.which("fixpoint") is None,
        reason="needs liquid-fixpoint on PATH",
    ),
]


def _llmll(args, cwd, timeout=300):
    return subprocess.run([*shlex.split(os.environ["LLMLL_BIN"]), *args], cwd=str(cwd),
                          capture_output=True, text=True, errors="replace", timeout=timeout)


def _json_line(text):
    doc = None
    for ln in text.splitlines():
        ln = ln.strip()
        if ln.startswith("{") and ln.endswith("}"):
            try:
                doc = json.loads(ln)
            except ValueError:
                pass
    assert doc is not None, text[-3000:]
    return doc


def _verify(d, module):
    p = _llmll(["--json", "verify", f"{module}.llmll"], d)
    return p, _json_line(p.stdout)


def _bytes_fallbacks(doc):
    """Every `abstraction:app:bytes-*` cause or construct the run reports."""
    found = []
    for v in doc.get("body_fallback_causes", {}).values():
        if isinstance(v, str) and v.startswith("abstraction:app:bytes-"):
            found.append(v)
    for vs in doc.get("body_fallback_constructs", {}).values():
        found.extend(c for c in vs if c.startswith("abstraction:app:bytes-"))
    return found


# ─── y4m ─────────────────────────────────────────────────────────────────

@pytest.fixture(scope="module")
def y4m_imports(tmp_path_factory):
    """raster and xform, copied and verified once (ybuf imports both)."""
    d = tmp_path_factory.mktemp("y4m-imports")
    for m in ("raster", "xform", "ybuf"):
        shutil.copyfile(Y4M / f"{m}.llmll", d / f"{m}.llmll")
    for m in ("raster", "xform"):
        p, doc = _verify(d, m)
        assert p.returncode == 0, p.stdout + p.stderr
        assert doc["solver_verdict"] == "safe", doc
        assert doc["proved_count"] == doc["contracted_count"], doc
    return d


def _y4m_copy(tmp_path, imports):
    d = tmp_path / "y4m"
    shutil.copytree(imports, d)
    return d


def test_y4m_v_ybuf_verifies(tmp_path, y4m_imports):
    d = _y4m_copy(tmp_path, y4m_imports)
    p, doc = _verify(d, "ybuf")
    assert p.returncode == 0, p.stdout + p.stderr
    assert doc["solver_verdict"] == "safe", doc
    assert doc["contracted_count"] == 5, doc
    assert doc["proved_count"] == 5, doc
    assert sorted(doc["body_faithful"]) == sorted(
        ["find-lf", "marker-end", "luma-plane", "crop-row", "hflip-at"]), doc
    assert doc["body_fallback"] == [], doc
    assert _bytes_fallbacks(doc) == [], doc


def _mutate(d, old, new, module="ybuf"):
    f = d / f"{module}.llmll"
    src = f.read_text()
    assert old in src, old
    k = src.rindex(old)  # the body comes after the contract
    f.write_text(src[:k] + new + src[k + len(old):])


Y4M_REFUTED = [
    ("M1", "find-lf", "(if (< i (bytes-length buf))", "(if (<= i (bytes-length buf))"),
    ("M2", "marker-end", "(if (= k2 6) (+ i 1)", "(if (= k2 6) i"),
    ("M4A", "crop-row", "(bytes-slice (bytes-slice pl ro (+ ro pw)) x0 (+ x0 cw))",
     "(bytes-slice (bytes-slice pl ro (+ ro pw)) x0 (+ x0 (+ cw 1)))"),
    ("M5", "hflip-at", "(bytes-get row (hflip-src (bytes-length row) ox))",
     "(bytes-get row (- (bytes-length row) ox))"),
]

Y4M_FALLBACK = [
    ("M3", "luma-plane", "(bytes-slice fr 0 (* w h))", "(bytes-slice fr 0 (* w (- h 1)))"),
    ("M4B", "crop-row", "(bytes-slice (bytes-slice pl ro (+ ro pw)) x0 (+ x0 cw))",
     "(bytes-slice (bytes-slice pl ro (+ ro pw)) (+ x0 1) (+ x0 cw))"),
]


@pytest.mark.parametrize("cell,fn,old,new", Y4M_REFUTED, ids=[c[0] for c in Y4M_REFUTED])
def test_y4m_mutant_refuted(tmp_path, y4m_imports, cell, fn, old, new):
    d = _y4m_copy(tmp_path, y4m_imports)
    _mutate(d, old, new)
    p, doc = _verify(d, "ybuf")
    assert p.returncode == 1, p.stdout + p.stderr
    assert doc["exit_code"] == 1, doc
    assert doc["solver_verdict"] == "refuted", doc
    unsafe = [x["message"] for x in doc["diagnostics"] if x.get("kind") == "lh-unsafe"]
    assert any(f"'{fn}'" in m for m in unsafe), doc["diagnostics"]
    assert fn not in doc.get("body_fallback_constructs", {}), doc


def test_y4m_m4a_is_a_refutation_of_the_outer_call_pre(tmp_path, y4m_imports):
    """The too-wide window fails the outer bytes-slice pre, which holds only
    with the exact length of the inner slice (ABSTRACTION-LEN-EXACT-1)."""
    d = _y4m_copy(tmp_path, y4m_imports)
    _mutate(d, Y4M_REFUTED[2][2], Y4M_REFUTED[2][3])
    p, doc = _verify(d, "ybuf")
    assert p.returncode == 1, p.stdout + p.stderr
    unsafe = [x["message"] for x in doc["diagnostics"] if x.get("kind") == "lh-unsafe"]
    assert any("call-site precondition of 'bytes-slice' not satisfied in 'crop-row'" in m
               for m in unsafe), unsafe
    assert doc.get("body_fallback_constructs", {}) == {}, doc


@pytest.mark.parametrize("cell,fn,old,new", Y4M_FALLBACK, ids=[c[0] for c in Y4M_FALLBACK])
def test_y4m_mutant_result_length_falls_back(tmp_path, y4m_imports, cell, fn, old, new):
    """F-2 / ABSTRACTION-RESULT-LEN-1: pinned as a fallback, not a refutation."""
    d = _y4m_copy(tmp_path, y4m_imports)
    _mutate(d, old, new)
    p, doc = _verify(d, "ybuf")
    assert p.returncode == 0, p.stdout + p.stderr
    assert doc["exit_code"] == 0, doc
    assert doc["solver_verdict"] == "safe", doc
    assert doc["body_fallback_constructs"] == {fn: ["abstraction:app:bytes-slice"]}, doc
    assert [x for x in doc["diagnostics"] if x.get("kind") == "lh-unsafe"] == [], doc["diagnostics"]


# ─── netpbm-swarm ────────────────────────────────────────────────────────

@pytest.fixture(scope="module")
def swarm_imports(tmp_path_factory):
    """types, copied and verified once (build.sh verifies binfmt after it)."""
    d = tmp_path_factory.mktemp("swarm-imports")
    for m in ("types", "binfmt"):
        shutil.copyfile(SWARM / f"{m}.llmll", d / f"{m}.llmll")
    p, doc = _verify(d, "types")
    assert p.returncode == 0, p.stdout + p.stderr
    assert doc["solver_verdict"] == "safe", doc
    return d


def _swarm_copy(tmp_path, imports):
    d = tmp_path / "swarm"
    shutil.copytree(imports, d)
    return d


def test_swarm_v_binfmt_verifies(tmp_path, swarm_imports):
    d = _swarm_copy(tmp_path, swarm_imports)
    p, doc = _verify(d, "binfmt")
    assert p.returncode == 0, p.stdout + p.stderr
    assert doc["exit_code"] == 0, doc
    assert doc["solver_verdict"] == "safe", doc
    assert doc["contracted_count"] == 4, doc
    assert doc["proved_count"] == 4, doc
    assert sorted(doc["body_faithful"]) == sorted(
        ["byte-class", "header-end", "raster-len", "bin-sample"]), doc
    assert doc["body_fallback"] == [], doc
    assert doc["termination_assumed_fns"] == [], doc
    assert _bytes_fallbacks(doc) == [], doc


SWARM_WS = "(or (= b 9) (or (= b 10) (or (= b 11) (or (= b 12) (or (= b 13) (= b 32))))))"
SWARM_REFUTED = [
    ("B1", "byte-class", SWARM_WS + " 0",
     "(or (= b 9) (or (= b 10) (or (= b 11) (or (= b 12) (= b 32))))) 0"),
    ("B2", "header-end", "(if (>= (+ nt 1) 4) (+ i 1)", "(if (>= (+ nt 1) 4) i"),
    ("B3", "raster-len", "(* b (* k n))", "(* k n)"),
    ("B4", "bin-sample", "(bytes-get buf (+ (+ off (+ i i)) 1))",
     "(bytes-get buf (+ (+ off (+ i i)) 2))"),
]


@pytest.mark.parametrize("cell,fn,old,new", SWARM_REFUTED, ids=[c[0] for c in SWARM_REFUTED])
def test_swarm_mutant_refuted(tmp_path, swarm_imports, cell, fn, old, new):
    d = _swarm_copy(tmp_path, swarm_imports)
    _mutate(d, old, new, module="binfmt")
    p, doc = _verify(d, "binfmt")
    assert p.returncode == 1, p.stdout + p.stderr
    assert doc["exit_code"] == 1, doc
    assert doc["solver_verdict"] == "refuted", doc
    unsafe = [x["message"] for x in doc["diagnostics"] if x.get("kind") == "lh-unsafe"]
    assert any(f"'{fn}'" in m for m in unsafe), doc["diagnostics"]
    assert fn not in doc.get("body_fallback_constructs", {}), doc
