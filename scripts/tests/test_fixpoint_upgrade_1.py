"""FIXPOINT-UPGRADE-1: run on liquid-fixpoint 0.9.6.3.4 and later.

liquid-fixpoint 0.9.6.3.4 changed two things llmll depends on:

* the qualifier syntax: `qualif N(v : int) { p }`, not `qualif N(v : int): (p)`.
  Neither form parses on the other version.
* the `-q --json` verdict: the `{"tag", "contents"}` object moved under a
  `status` key. Before the fix the decode failed, the text scrape ran, and an
  UNSAFE verdict lost its constraint ids, so a refutation had no pointer.

llmll probes the solver once per run and rewrites the qualifier lines of the
`.fq` it hands over when the solver needs braces. On the old solver the file
stays as the compiler writes it.

The new-solver tests need LLMLL_FIXPOINT_NEW, a directory holding a `fixpoint`
of 0.9.6.3.4 or later. They are skipped without it.
"""

import json
import os
import shutil
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
AND_GUARD = REPO_ROOT / "scripts" / "tests" / "fixtures" / "and_guard"
BANKING = REPO_ROOT / "examples" / "banking_ledger"

pytestmark = pytest.mark.skipif(
    not os.environ.get("LLMLL_BIN"),
    reason="set LLMLL_BIN to a built llmll",
)

NEW_DIR = os.environ.get("LLMLL_FIXPOINT_NEW")

needs_new = pytest.mark.skipif(
    not NEW_DIR or not (Path(NEW_DIR) / "fixpoint").exists(),
    reason="set LLMLL_FIXPOINT_NEW to a directory holding liquid-fixpoint >= 0.9.6.3.4",
)

PROBE = "qualif LlmllProbe(v : int) { (v >= 0) }\n"


def _reads_braces(exe: str, tmp: Path) -> bool:
    probe = tmp / "probe.fq"
    probe.write_text(PROBE, encoding="utf-8")
    p = subprocess.run([exe, "-q", "--json", str(probe)], capture_output=True, text=True, timeout=60)
    return p.returncode == 0


def _env(solver_dir=None) -> dict:
    env = dict(os.environ)
    if solver_dir:
        env["PATH"] = str(solver_dir) + os.pathsep + env["PATH"]
    return env


def _verify(cwd: Path, name: str, solver_dir=None, extra=()) -> subprocess.CompletedProcess:
    return subprocess.run(
        [os.environ["LLMLL_BIN"], "--json", "verify", name, *extra],
        cwd=cwd, capture_output=True, text=True, timeout=300, env=_env(solver_dir),
    )


def _qualif_lines(fq: Path) -> list:
    return [l for l in fq.read_text(encoding="utf-8").splitlines() if l.startswith("qualif ")]


@needs_new
def test_refutation_keeps_constraint_ids_on_new_solver(tmp_path):
    shutil.copytree(AND_GUARD, tmp_path / "g")
    p = _verify(tmp_path / "g", "guard_bad.llmll", NEW_DIR)
    assert p.returncode == 1, p.stdout + p.stderr
    out = json.loads(p.stdout)
    assert out["solver_verdict"] == "refuted", p.stdout
    diags = [d for d in out["diagnostics"] if d.get("kind") == "lh-unsafe"]
    assert len(diags) == 3, p.stdout
    for d in diags:
        assert "(constraint #" in d["message"], d
        assert d["pointer"].startswith("/statements/"), d


@needs_new
def test_example_verifies_on_new_solver(tmp_path):
    shutil.copytree(BANKING, tmp_path / "b")
    p = _verify(tmp_path / "b", "banking.llmll", NEW_DIR)
    assert p.returncode == 0, p.stdout + p.stderr
    assert json.loads(p.stdout)["solver_verdict"] == "safe", p.stdout


@needs_new
def test_fq_out_is_in_brace_form_on_new_solver(tmp_path):
    shutil.copytree(BANKING, tmp_path / "b")
    fq = tmp_path / "out.fq"
    p = _verify(tmp_path / "b", "banking.llmll", NEW_DIR, ["-o", str(fq)])
    assert p.returncode == 0, p.stdout + p.stderr
    lines = _qualif_lines(fq)
    assert lines, fq.read_text(encoding="utf-8")
    assert all(") { " in l and l.endswith(" }") for l in lines), lines


def test_fq_out_stays_in_colon_form_on_old_solver(tmp_path):
    exe = shutil.which("fixpoint") or shutil.which("liquid-fixpoint")
    if exe is None:
        pytest.skip("needs liquid-fixpoint on PATH")
    if _reads_braces(exe, tmp_path):
        pytest.skip("the solver on PATH is 0.9.6.3.4 or later")
    shutil.copytree(BANKING, tmp_path / "b")
    fq = tmp_path / "out.fq"
    p = _verify(tmp_path / "b", "banking.llmll", None, ["-o", str(fq)])
    assert p.returncode == 0, p.stdout + p.stderr
    lines = _qualif_lines(fq)
    assert lines, fq.read_text(encoding="utf-8")
    assert all("): (" in l for l in lines), lines
