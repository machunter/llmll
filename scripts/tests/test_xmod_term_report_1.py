"""XMOD-TERM-REPORT-1: an importer's trust report reads an import's own
termination proof.

WHAT THE DEFECT WAS. The trust report lists every member of a recursive cycle
in the whole program (entry and imports) as `termination_unverified`, then
removes the functions whose `(decreases ...)` was proved. That removal used the
entry module's proved set only. An imported recursive function whose own
sidecar records `termination_verified: true` stayed listed in the importer's
report, in `partial_fns` and in the text section `Termination-unverified`,
while the `verify` headline, which already read the import's sidecar, did not
name it. Found on `examples/y4m`: `y4m.llmll` listed `ybuf.find-lf` and
`ybuf.marker-end`.

THE RULE THE CELLS PIN. An imported function leaves the list only when its
module's sidecar passes the staleness gate and records a positive post level
with `termination_verified`. A missing sidecar, and a body edited after its
sidecar was written, keep it listed.

AGAINST THE PRE-CHANGE BINARY (v0.41.0 + EXAMPLES-VERIFY-REGRESS-1), measured:
XTR-P1 and XTR-P2 FAIL. XTR-P3 and XTR-P4 PASS; they are the negative controls.

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

# `walk` recurses with a measure the solver discharges.
LIB = """(def-shell walk [n: int] -> int
  (pre (>= n 0))
  (post (>= result 0))
  (decreases n)
  (if (<= n 0) 0 (walk (- n 1))))
"""

# The same function with its base case edited.
LIB_EDITED = LIB.replace("(<= n 0) 0", "(<= n 1) 0")

MAIN = """(import lib)
(def-shell top [x: int] -> int
  (pre (>= x 0))
  (post (>= result 0))
  (lib.walk x))
"""


def llmll(*args: str, cwd: Path) -> subprocess.CompletedProcess:
    return subprocess.run(shlex.split(os.environ["LLMLL_BIN"]) + list(args),
                          cwd=str(cwd), capture_output=True, text=True, timeout=300)


def report_json(*args: str, cwd: Path) -> dict:
    out = llmll("--json", *args, cwd=cwd).stdout
    doc = json.loads(out[out.index("{"):])
    return doc.get("trust_report", doc)


def unverified_flag(report: dict, name: str):
    return next(e.get("termination_unverified") for e in report["entries"]
                if (e.get("function") or e.get("name")) == name)


def setup(tmp_path: Path, verify_lib: bool = True) -> Path:
    (tmp_path / "lib.llmll").write_text(LIB, encoding="utf-8")
    (tmp_path / "main.llmll").write_text(MAIN, encoding="utf-8")
    if verify_lib:
        r = llmll("verify", "lib.llmll", cwd=tmp_path)
        assert r.returncode == 0, r.stdout + r.stderr
        side = json.loads((tmp_path / "lib.llmll.verified.json").read_text())
        assert side["walk"]["post"].get("termination_verified") is True, side
    return tmp_path


def test_xtr_p1_trust_report_reads_the_imports_termination_proof(tmp_path: Path):
    d = setup(tmp_path)
    rep = report_json("trust-report", "main.llmll", cwd=d)
    assert "lib.walk" not in rep["partial_fns"], rep["partial_fns"]
    assert not unverified_flag(rep, "lib.walk")
    text = llmll("trust-report", "main.llmll", cwd=d).stdout
    assert "↻ lib.walk" not in text, text


def test_xtr_p2_verify_trust_report_reads_the_imports_termination_proof(tmp_path: Path):
    d = setup(tmp_path)
    rep = report_json("verify", "--trust-report", "main.llmll", cwd=d)
    assert "lib.walk" not in rep["partial_fns"], rep["partial_fns"]
    assert not unverified_flag(rep, "lib.walk")


def test_xtr_p3_an_import_never_verified_stays_listed(tmp_path: Path):
    d = setup(tmp_path, verify_lib=False)
    rep = report_json("trust-report", "main.llmll", cwd=d)
    assert "lib.walk" in rep["partial_fns"], rep["partial_fns"]
    assert unverified_flag(rep, "lib.walk") is True


def test_xtr_p4_an_import_edited_after_its_sidecar_stays_listed(tmp_path: Path):
    d = setup(tmp_path)
    (d / "lib.llmll").write_text(LIB_EDITED, encoding="utf-8")
    rep = report_json("trust-report", "main.llmll", cwd=d)
    assert "lib.walk" in rep["partial_fns"], rep["partial_fns"]
    assert unverified_flag(rep, "lib.walk") is True
