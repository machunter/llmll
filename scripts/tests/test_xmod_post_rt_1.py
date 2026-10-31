"""XMOD-POST-RT-1: `--contracts` instruments every module in the import closure.

Up to v0.33.2, `llmll build` and `llmll run` instrumented contracts on the
entry module only. An imported function reached codegen with its contract
untouched, so its post was dropped: a bad post in an imported module printed a
wrong answer and exited 0. A `?proof-required` clause was also wrapped as the
hole itself, so a built program crashed with `PROOF REQUIRED` at the first
call.

What a pass here means, each program built (or run) with $LLMLL_BIN:

* main.llmll imports lib.bad-inc, whose post is false: the binary exits
  non-zero naming bad-inc; under `--contracts none` it prints 3 and exits 0.
* chain_nopost.llmll -> bb -> cc, with no entry post: the failure names c-inc,
  two modules away from the entry.
* `llmll run main.llmll` fails the same way (the doRun path).
* prmain.llmll: imported and entry predicate-carrying `?proof-required` posts
  with correct bodies, plus bare ones: prints 22, exit 0. prbad.llmll: an
  imported predicate-carrying post with a wrong body exits non-zero.

Fixtures: compiler/test/fixtures/xmod-post-rt/ (shared with ModuleSpec),
copied into tmp_path so a build writes nothing in the repo.
"""

import glob
import os
import shlex
import shutil
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURES = REPO_ROOT / "compiler" / "test" / "fixtures" / "xmod-post-rt"

pytestmark = pytest.mark.skipif(
    not os.environ.get("LLMLL_BIN"),
    reason="set LLMLL_BIN to a built llmll",
)

BUILD_TIMEOUT_S = 600
RUN_TIMEOUT_S = 20


def _llmll():
    return shlex.split(os.environ["LLMLL_BIN"])


def _work(tmp_path: Path) -> Path:
    work = tmp_path / "src"
    shutil.copytree(FIXTURES, work)
    return work


def _build(work: Path, name: str, out: Path, *flags: str) -> str:
    p = subprocess.run([*_llmll(), "build", *flags, f"{name}.llmll", "-o", str(out)],
                       capture_output=True, text=True, timeout=BUILD_TIMEOUT_S, cwd=str(work))
    assert p.returncode == 0, f"build {name} failed\n{p.stdout[-1500:]}\n{p.stderr[-1500:]}"
    exes = glob.glob(str(out / ".stack-work" / "install" / "*" / "*" / "*" / "bin" / "*"))
    assert len(exes) == 1, exes
    return exes[0]


def _exec(exe: str):
    return subprocess.run([exe], input="x\n", capture_output=True, text=True, timeout=RUN_TIMEOUT_S)


def test_imported_bad_post_fails_at_run_time(tmp_path):
    work = _work(tmp_path)
    r = _exec(_build(work, "main", tmp_path / "full"))
    assert r.returncode != 0, (r.stdout, r.stderr[-500:])
    assert "Postcondition violated in bad-inc" in r.stderr


def test_contracts_none_still_disables_the_imported_post(tmp_path):
    work = _work(tmp_path)
    r = _exec(_build(work, "main", tmp_path / "none", "--contracts", "none"))
    assert r.returncode == 0, r.stderr[-500:]
    assert r.stdout.startswith("3"), r.stdout


def test_three_module_chain_names_the_deepest_function(tmp_path):
    work = _work(tmp_path)
    r = _exec(_build(work, "chain_nopost", tmp_path / "chain"))
    assert r.returncode != 0, (r.stdout, r.stderr[-500:])
    assert "Postcondition violated in c-inc" in r.stderr


def test_llmll_run_checks_the_imported_post(tmp_path):
    work = _work(tmp_path)
    p = subprocess.run([*_llmll(), "run", "main.llmll"], input="x\n", capture_output=True,
                       text=True, timeout=BUILD_TIMEOUT_S, cwd=str(work))
    assert p.returncode != 0, (p.stdout[-500:], p.stderr[-500:])
    assert "Postcondition violated in bad-inc" in p.stdout + p.stderr


def test_proof_required_posts_check_their_predicate(tmp_path):
    work = _work(tmp_path)
    r = _exec(_build(work, "prmain", tmp_path / "pr"))
    assert r.returncode == 0, r.stderr[-500:]
    assert r.stdout.startswith("22"), r.stdout
    assert "PROOF REQUIRED" not in r.stderr
    r2 = _exec(_build(work, "prbad", tmp_path / "prbad"))
    assert r2.returncode != 0, (r2.stdout, r2.stderr[-500:])
    assert "Postcondition violated in sqbad" in r2.stderr
