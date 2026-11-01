"""VERIFY-BUDGET-1: verify stops the solver at a memory or time limit.

liquid-fixpoint and its z3 child can use several gigabytes (VERIFY-MEMORY-1),
and macOS does not enforce memory rlimits. verify now starts the solver in its
own process group, polls the group's memory, and kills the whole group above
--solver-mem-mb (default 2048) or after --time-limit seconds (default 120).

These tests put a fake `liquid-fixpoint` first on PATH, so no real solver run
uses memory. What a pass here means:

* a fake solver that sleeps, with a child process, under --time-limit 2:
  verify exits 5, solver_verdict is "resource-limit", the resource_limit
  object names the time limit, the child process is gone afterwards, and no
  .verified.json is written.
* a fake solver whose child holds about 200 MB, under --solver-mem-mb 64:
  verify exits 5 with kind "memory", and the child is gone.
* the real solver, both limits off: the fixture still verifies (exit 0).
"""

import json
import os
import shlex
import shutil
import signal
import subprocess
import time
from typing import Optional
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
SRC = REPO_ROOT / "scripts" / "tests" / "fixtures" / "abstraction_verdict" / "a1.llmll"

pytestmark = pytest.mark.skipif(
    not os.environ.get("LLMLL_BIN"),
    reason="set LLMLL_BIN to a built llmll",
)

SLOW = """#!/bin/sh
sleep 300 &
echo $! > "{pidfile}"
sleep 300
"""

HOG = """#!/bin/sh
python3 -c 'import os, time
open("{pidfile}", "w").write(str(os.getpid()))
b = bytearray(200 * 1024 * 1024)
b[::4096] = b"x" * len(b[::4096])
time.sleep(300)' &
wait
"""


def _fake_solver(tmp_path: Path, body: str) -> tuple[Path, Path]:
    bindir = tmp_path / "bin"
    bindir.mkdir()
    pidfile = tmp_path / "child.pid"
    exe = bindir / "liquid-fixpoint"
    exe.write_text(body.format(pidfile=pidfile))
    exe.chmod(0o755)
    return bindir, pidfile


def _verify(tmp_path: Path, *flags: str, path_prefix: Optional[Path] = None):
    shutil.copy(SRC, tmp_path / SRC.name)
    env = dict(os.environ)
    if path_prefix is not None:
        env["PATH"] = f"{path_prefix}{os.pathsep}{env['PATH']}"
    # Own session, so a hang is killed with everything it started.
    p = subprocess.Popen([*shlex.split(os.environ["LLMLL_BIN"]), *flags, "--json", "verify", SRC.name],
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                         cwd=str(tmp_path), env=env, start_new_session=True)
    try:
        out, _ = p.communicate(timeout=60)
    except subprocess.TimeoutExpired:
        os.killpg(p.pid, signal.SIGKILL)
        p.communicate()
        pytest.fail("verify did not stop within 60 s")
    return p.returncode, json.loads(out)


def _alive(pidfile: Path) -> bool:
    pid = int(pidfile.read_text().strip())
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    return True


def test_time_limit_stops_the_solver_and_its_child(tmp_path):
    bindir, pidfile = _fake_solver(tmp_path, SLOW)
    t0 = time.monotonic()
    code, doc = _verify(tmp_path, "--time-limit", "2", path_prefix=bindir)
    assert time.monotonic() - t0 < 30
    assert code == 5, doc
    assert doc["solver_verdict"] == "resource-limit"
    assert doc["resource_limit"]["kind"] == "time"
    assert doc["resource_limit"]["limit_s"] == 2
    assert any(d.get("kind") == "resource-limit" for d in doc["diagnostics"])
    time.sleep(0.5)
    assert not _alive(pidfile), "the solver's child process outlived the run"
    assert not (tmp_path / "a1.verified.json").exists()


def test_memory_limit_stops_the_solver(tmp_path):
    bindir, pidfile = _fake_solver(tmp_path, HOG)
    code, doc = _verify(tmp_path, "--solver-mem-mb", "64", path_prefix=bindir)
    assert code == 5, doc
    assert doc["resource_limit"]["kind"] == "memory"
    assert doc["resource_limit"]["limit_mb"] == 64
    assert doc["resource_limit"]["peak_mb"] > 64
    time.sleep(0.5)
    assert not _alive(pidfile), "the memory-holding child outlived the run"


@pytest.mark.skipif(
    shutil.which("liquid-fixpoint") is None and shutil.which("fixpoint") is None,
    reason="needs liquid-fixpoint on PATH",
)
def test_limits_off_real_solver_still_verifies(tmp_path):
    code, doc = _verify(tmp_path, "--solver-mem-mb", "0", "--time-limit", "0")
    assert code == 0, doc
    assert doc["solver_verdict"] == "safe"
    assert "resource_limit" not in doc
