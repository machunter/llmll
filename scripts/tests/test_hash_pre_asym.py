"""HASH-PRE-ASYM: a stored verdict is keyed on everything its proof read.

WHAT THE DEFECT IS. A `.verified.json` record is checked on read against a
hash of its own function's source only (`canonicalDefEvidenceHash`). A
caller's proof also reads its callees' interfaces, its recursion group (for
the termination claim) and any control-tag fact seeded into it. When one of
those changes and the caller's module is not re-verified, the stored
`verified` survives every read that does not run the solver: an importer's
`verify`, `--strict-verified-core`, and `--trust-report`. A failed `verify`
also left the previous positive records in place.

Design: docs/design/hash-pre-asym-proposal.md Rev 3 (S1 to S4). Measured
witness: docs/design/hash-pre-asym-witness.md.

WHAT EACH CELL DID AGAINST THE PRE-CHANGE (v0.27.1) BINARY, measured.
HPA-W1, HPA-W2, HPA-S4, HPA-T1 and HPA-T2 FAILED. HPA-G1 and HPA-T2-CONTROL
PASSED: they guard against over-invalidation and must keep passing.

WHY IT SKIPS WITHOUT A BINARY. Every cell calls `llmll verify`, which shells
out to liquid-fixpoint. The spec-roundtrip job runs this file with LLMLL_BIN
set.
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

B_ORIG = "(def g [x: int] -> int (pre (>= x 0)) (post (= result x)) x)\n"
A_SRC = "(import b)\n(open b)\n(def f [] -> int (post (= result 1)) (g 1))\n"
C_SRC = "(import a)\n(open a)\n(def h [] -> int (post (= result 1)) (f))\n"


def _run(workdir: Path, *args: str):
    llmll = shlex.split(os.environ["LLMLL_BIN"])
    return subprocess.run([*llmll, *args], cwd=workdir, capture_output=True, text=True,
                          encoding="utf-8", timeout=300)


def _verify_safe(d: Path, name: str) -> None:
    r = _run(d, "verify", name)
    assert "SAFE (liquid-fixpoint)" in r.stdout, r.stdout + r.stderr


def _report(d: Path, name: str) -> dict:
    """The solver-less trust report, as JSON."""
    r = _run(d, "--json", "verify", name, "--trust-report")
    return json.loads(r.stdout)


def _post_level(report: dict, fn: str):
    """The rendered post tier, e.g. "verified (liquid-fixpoint)" or "asserted"."""
    for e in report["entries"]:
        if e["name"] == fn:
            return e["post_level"] or ""
    raise AssertionError(f"no entry for {fn}: {[e['name'] for e in report['entries']]}")


def _chain(d: Path) -> None:
    """Three modules, c imports a imports b; all verified."""
    (d / "b.llmll").write_text(B_ORIG)
    (d / "a.llmll").write_text(A_SRC)
    (d / "c.llmll").write_text(C_SRC)
    for m in ("b.llmll", "a.llmll", "c.llmll"):
        _verify_safe(d, m)


def _strict_c(d: Path):
    r = _run(d, "verify", "c.llmll", "--strict-verified-core")
    return r, r.stdout + r.stderr


def test_hpa_w1_callee_pre_strengthened(tmp_path: Path):
    """HPA-W1. g's pre now rejects f's call (g 1); only b is re-verified.
    An importer of a must not pass --strict-verified-core on f's old record."""
    _chain(tmp_path)
    (tmp_path / "b.llmll").write_text(
        "(def g [x: int] -> int (pre (>= x 5)) (post (= result x)) x)\n")
    _verify_safe(tmp_path, "b.llmll")
    r, out = _strict_c(tmp_path)
    assert r.returncode != 0, out
    assert "f" in out, out


def test_hpa_w2_callee_post_weakened(tmp_path: Path):
    """HPA-W2. g's post no longer gives f's post; only b is re-verified."""
    _chain(tmp_path)
    (tmp_path / "b.llmll").write_text(
        "(def g [x: int] -> int (pre (>= x 0)) (post (>= result 0)) x)\n")
    _verify_safe(tmp_path, "b.llmll")
    r, out = _strict_c(tmp_path)
    assert r.returncode != 0, out
    assert "f" in out, out


def test_hpa_g1_callee_body_edit_keeps_caller(tmp_path: Path):
    """HPA-G1 (guard). g declares its return type and only its body changes.
    f's proof read nothing that changed, so the importer still passes."""
    _chain(tmp_path)
    (tmp_path / "b.llmll").write_text(
        "(def g [x: int] -> int (pre (>= x 0)) (post (= result x)) (+ x 0))\n")
    _verify_safe(tmp_path, "b.llmll")
    r, out = _strict_c(tmp_path)
    assert r.returncode == 0, out


def test_hpa_s4_failed_verify_drops_positive_record(tmp_path: Path):
    """HPA-S4. After `verify a` refutes f, a's sidecar must not still say
    f is verified."""
    _chain(tmp_path)
    (tmp_path / "b.llmll").write_text(
        "(def g [x: int] -> int (pre (>= x 0)) (post (>= result 0)) x)\n")
    _verify_safe(tmp_path, "b.llmll")
    r = _run(tmp_path, "verify", "a.llmll")
    assert "body verification of 'f' failed" in r.stdout + r.stderr, r.stdout + r.stderr
    side = json.loads((tmp_path / "a.llmll.verified.json").read_text())
    level = side.get("f", {}).get("post", {}).get("display_level", {}).get("level")
    assert level != "verified", side.get("f")


T1_BEFORE = """(def-shell g [n: int] -> int (pre (>= n 0)) (post (>= result 0)) n)
(def-shell f [n: int] -> int (pre (>= n 0)) (post (>= result 0)) (decreases n) (if (= n 0) (g 0) (f (- n 1))))
"""
T1_AFTER = """(def-shell g [n: int] -> int (pre (>= n 0)) (post (>= result 0)) (if (= n 0) 0 (f (- n 1))))
(def-shell f [n: int] -> int (pre (>= n 0)) (post (>= result 0)) (decreases n) (if (= n 0) (g 0) (f (- n 1))))
"""


def test_hpa_t1_recursion_group_change_clears_termination(tmp_path: Path):
    """HPA-T1. f's termination was discharged while it recursed alone. g's
    body now calls f, so {f, g} is one recursion group and g has no measure.
    Without re-verifying, the solver-less report must not call f terminating."""
    (tmp_path / "a.llmll").write_text(T1_BEFORE)
    _verify_safe(tmp_path, "a.llmll")
    assert "f" not in _report(tmp_path, "a.llmll")["partial_fns"]
    (tmp_path / "a.llmll").write_text(T1_AFTER)
    partial = _report(tmp_path, "a.llmll")["partial_fns"]
    assert "f" in partial, partial


T2_SRC = """(import wasi.fs (capability read "/tmp" :deterministic false))
(import wasi.io (capability stdout :deterministic false))
(export)
(type Ctl (| Boot) (| Probed) (| Halt))
(def-shell go [r: int p: Ctl c: Command] -> ((int, Ctl), Command)
  (pair (pair r p) c))
(def-shell age-step [p: Ctl x: Response] -> int
  (pre (= p Probed))
  (post (>= result 0))
  (match x ((RCode age) age) (_ 0)))
(def-shell plain [x: int] -> int (post (= result (+ x 1))) (+ x 1))
(def-shell step [s: (int, Ctl) input: string x: Response] -> ((int, Ctl), Command)
  (match (second s)
    ((Boot)   (go (first s) Probed (wasi.fs.stat "/tmp")))
    ((Probed) (go (age-step Probed x) Halt (wasi.io.stdout "done")))
    ((Halt)   (go (first s) Halt (wasi.io.stdout "")))))
(def-shell done? [s: (int, Ctl)] -> bool
  (match (second s) ((Halt) true) ((Boot) false) ((Probed) false)))
(def-main :mode console
  :init (pair (pair 0 Boot) (wasi.io.stdout "start"))
  :step step
  :done? done?)
"""
T2_REBIND = ('(go (first s) Probed (wasi.fs.stat "/tmp"))',
             '(go (first s) Probed (wasi.io.stdout "x"))')


def _t2_edited(d: Path) -> dict:
    (d / "m.llmll").write_text(T2_SRC)
    _verify_safe(d, "m.llmll")
    (d / "m.llmll").write_text(T2_SRC.replace(*T2_REBIND))
    return _report(d, "m.llmll")


def test_hpa_t2_issuing_def_edit_drops_fact_user(tmp_path: Path):
    """HPA-T2. `step` now binds Probed to wasi.io.stdout, which declares no
    fact. age-step's post rested on the fact, so its record must not read
    verified before a re-verify."""
    rep = _t2_edited(tmp_path)
    assert not _post_level(rep, "age-step").startswith("verified"), _post_level(rep, "age-step")


def test_hpa_t2_control_non_requesting_def_kept(tmp_path: Path):
    """HPA-T2-CONTROL (guard). `plain` requests no fact and calls nothing
    that changed, so its record survives the same edit."""
    rep = _t2_edited(tmp_path)
    assert _post_level(rep, "plain").startswith("verified"), _post_level(rep, "plain")


# ---------------------------------------------------------------------------
# HPA-INV: the round-trip invariant (proposal §3.1). A record a fresh `verify`
# writes must read back as written, on the entry path (the module's own trust
# report) and on the import path (an importer's report of that module's
# functions). A read site that computes the key with less information than the
# write side downgrades fresh records, and this cell sees it. It passes on
# v0.27.1 too, where both sides hash the same fields: it guards the read sites.
# ---------------------------------------------------------------------------

REPO = Path(__file__).resolve().parents[2]
INV_DIRS = ["tools/doc-path-lint", "tools/llmll-driver"]


def _copy_tracked(dest: Path, rel: str) -> Path:
    """The directory's tracked files only, so no stale local sidecar comes along."""
    archive = subprocess.run(["git", "archive", "HEAD", rel], cwd=REPO,
                             capture_output=True, check=True)
    subprocess.run(["tar", "-x", "-C", str(dest)], input=archive.stdout, check=True)
    return dest / rel


def _sidecar_verified(d: Path, mod: str) -> set[str]:
    p = d / f"{mod}.llmll.verified.json"
    if not p.exists():
        return set()
    side = json.loads(p.read_text())
    return {f for f, cs in side.items()
            if isinstance(cs, dict)
            and str((cs.get("post") or {}).get("display_level", {}).get("level", "")).startswith("verified")}


@pytest.mark.parametrize("rel", INV_DIRS)
def test_hpa_inv_fresh_sidecar_reads_back(tmp_path: Path, rel: str):
    d = _copy_tracked(tmp_path, rel)
    mods = sorted(p.stem for p in d.glob("*.llmll"))
    # Two passes, so every importer's second run sees its imports' sidecars.
    for _ in range(2):
        for m in mods:
            _run(d, "verify", f"{m}.llmll")
    fresh = {m: _sidecar_verified(d, m) for m in mods}
    assert any(fresh.values()), f"no verified record anywhere under {rel}"
    for m in mods:
        r = _run(d, "--json", "verify", f"{m}.llmll", "--trust-report")
        try:
            rep = json.loads(r.stdout)
        except json.JSONDecodeError:
            # A module that fails `check` (the refute-crux fixtures do, by
            # design) has no report; it must also have no fresh record.
            assert not fresh[m], (m, r.stdout + r.stderr)
            continue
        levels = {e["name"]: (e["post_level"] or "") for e in rep["entries"]}
        own = {n for n, l in levels.items() if "." not in n and l.startswith("verified")}
        assert own == fresh[m], (m, sorted(own ^ fresh[m]))
        for n, l in levels.items():
            if "." not in n:
                continue
            src, fn = n.rsplit(".", 1)
            if src in fresh:
                assert l.startswith("verified") == (fn in fresh[src]), (m, n, l)


def test_hpa_inv_import_view(tmp_path: Path):
    """HPA-INV-IMPORT. The corpus has neither an unannotated def nor a local
    name that collides with another module's function, so the corpus invariant
    cannot tell an import read that uses the module's own view from one that
    does not (measured: negative control NC4 passed it). This cell has both.
    In `b`, `k` calls the unannotated `u` and has a parameter named `n`; the
    importer `a` also imports `z`, which defines a function `n`. Read from `a`,
    b.k must still be verified: the key is computed over b's own imports and
    b's recorded return types, not over a's whole cache."""
    (tmp_path / "z.llmll").write_text(
        "(def-shell n [y: int] -> int (post (= result y)) y)\n")
    (tmp_path / "b.llmll").write_text(
        "(def-shell u [x: int] (pre (>= x 0)) (post (= result x)) x)\n"
        "(def-shell k [n: int] -> int (pre (>= n 0)) (post (>= result 0)) (u n))\n")
    (tmp_path / "a.llmll").write_text(
        "(import b)\n(open b)\n(import z)\n(open z)\n"
        "(def-shell top [] -> int (post (>= result 0)) (k 1))\n")
    for m in ("z.llmll", "b.llmll", "a.llmll"):
        _verify_safe(tmp_path, m)
    assert _post_level(_report(tmp_path, "b.llmll"), "k").startswith("verified")
    assert _post_level(_report(tmp_path, "a.llmll"), "b.k").startswith("verified")
