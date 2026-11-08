"""FQ-OUT-SPECIAL-1: the solver reads only a private temp file.

Every solver call used to hand liquid-fixpoint a path anyone could name in
advance: `--fq-out`, the default `/tmp/llmll-<base>-<tag>.fq`, or a fixed
`/tmp/llmll-{weakness,cdp,patch}-<name>.fq` and `/tmp/llmll-replay-artifact.fq`.
llmll wrote the constraints there and the solver read them back. A symlink to
`/dev/null`, a FIFO, or a concurrent writer at that path made the solver read
no constraints and answer Safe. On llmll 0.37.0, `h.llmll` below (a false
program) was reported `verified`, with exit 0 and a sidecar, by plain
`llmll verify` with a link planted at the default path.

What a pass here means:

* The solver reads a file llmll creates for that one call (`openTempFile`), and
  a verdict counts only if the solver reports checking exactly the emitted
  number of constraints.
* `--fq-out` and the default path are output copies. They are written in the
  solver's qualifier form, before the solve, and never read back.
* A copy that cannot be written is a warning: a passing program still exits 0.
* `k.llmll` (a closed-true post, zero constraints) still verifies, so "zero
  constraints" is not treated as "no verdict".

Every plant in this file is at a path derived from this test's own tmp_path or
a random function name, so it is ours. The replay test plants at the one fixed
path left, `/tmp/llmll-replay-artifact.fq`, only when nothing is there, and
removes only its own link.
"""

import hashlib
import json
import os
import secrets
import select
import shlex
import shutil
import signal
import stat
import subprocess
import sys
import threading
import time
from pathlib import Path

import pytest

FIX = Path(__file__).resolve().parent / "fixtures" / "fq_out_special_1"

pytestmark = [
    pytest.mark.skipif(sys.platform == "win32", reason="POSIX only (symlinks, FIFOs)"),
    pytest.mark.skipif(not os.environ.get("LLMLL_BIN"), reason="set LLMLL_BIN to a built llmll"),
    pytest.mark.skipif(
        shutil.which("liquid-fixpoint") is None and shutil.which("fixpoint") is None,
        reason="needs liquid-fixpoint on PATH",
    ),
]

TIMEOUT_S = 60


def _run(args, cwd):
    """Run llmll; on a timeout kill the whole process group, not only the child."""
    p = subprocess.Popen(shlex.split(os.environ["LLMLL_BIN"]) + list(args), cwd=str(cwd),
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                         start_new_session=True)
    try:
        out, err = p.communicate(timeout=TIMEOUT_S)
    except subprocess.TimeoutExpired:
        os.killpg(p.pid, signal.SIGKILL)
        p.communicate()
        raise
    return subprocess.CompletedProcess(p.args, p.returncode, out, err)


def _copy(tmp_path, name):
    shutil.copy(FIX / name, tmp_path / name)
    return tmp_path / name


def _verify_json(tmp_path, name, *flags):
    _copy(tmp_path, name)
    p = _run(["--json", "verify", *flags, name], tmp_path)
    return p, json.loads(p.stdout)


def _sidecar(tmp_path, name):
    return (tmp_path / (name + ".verified.json")).exists()


def _default_fq_path(src: Path) -> str:
    """`fqPathFor Nothing`: /tmp/llmll-<base>-<12 hex of sha256(abs path)>.fq."""
    absolute = os.path.join(os.path.realpath(src.parent), src.name)
    tag = hashlib.sha256(absolute.encode("utf-8")).hexdigest()[:12]
    return f"/tmp/llmll-{src.stem}-{tag}.fq"


def _remove_own(path: str):
    try:
        os.unlink(path)
    except FileNotFoundError:
        pass


class _FifoReader:
    """Hold the read end of a FIFO open and collect what is written to it."""

    def __init__(self, path):
        self.fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
        self.data = b""
        self.stop = threading.Event()
        self.t = threading.Thread(target=self._loop, daemon=True)
        self.t.start()

    def _loop(self):
        deadline = time.monotonic() + TIMEOUT_S
        while not self.stop.is_set() and time.monotonic() < deadline:
            r, _, _ = select.select([self.fd], [], [], 0.1)
            if r:
                try:
                    chunk = os.read(self.fd, 65536)
                except BlockingIOError:
                    continue
                if chunk:
                    self.data += chunk
                else:
                    time.sleep(0.05)   # no writer yet, or the writer closed

    def close(self):
        self.stop.set()
        self.t.join(5)
        os.close(self.fd)


# ---------------------------------------------------------------------------
# P1-P3, P7-P10: --fq-out
# ---------------------------------------------------------------------------

def test_p1_fq_out_dev_null_does_not_prove_a_false_program(tmp_path):
    p, out = _verify_json(tmp_path, "h.llmll", "--fq-out", "/dev/null")
    assert p.returncode == 1, p.stdout + p.stderr
    assert out["solver_verdict"] == "refuted", p.stdout
    assert not _sidecar(tmp_path, "h.llmll")


def test_p2_fq_out_symlink_to_dev_null(tmp_path):
    link = tmp_path / "link.fq"
    os.symlink("/dev/null", link)
    p, out = _verify_json(tmp_path, "h.llmll", "--fq-out", str(link))
    assert p.returncode == 1, p.stdout + p.stderr
    assert out["solver_verdict"] == "refuted", p.stdout
    assert not _sidecar(tmp_path, "h.llmll")


def test_p3_zero_constraints_is_still_a_proof(tmp_path):
    copy = tmp_path / "k.fq"
    p, out = _verify_json(tmp_path, "k.llmll", "--fq-out", str(copy))
    assert p.returncode == 0, p.stdout + p.stderr
    assert out["all_proved"] is True, p.stdout
    lines = copy.read_text(encoding="utf-8").splitlines()
    assert sum(1 for l in lines if l == "constraint:") == 0


def test_p7_fq_out_fifo_gets_the_text_and_proves_nothing(tmp_path):
    fifo = tmp_path / "pipe.fq"
    os.mkfifo(fifo)
    reader = _FifoReader(str(fifo))
    try:
        p, out = _verify_json(tmp_path, "h.llmll", "--fq-out", str(fifo))
    finally:
        time.sleep(0.2)
        reader.close()
    assert p.returncode == 1, p.stdout + p.stderr
    assert out["solver_verdict"] == "refuted", p.stdout
    assert b"constraint:" in reader.data


@pytest.mark.parametrize("kind", ["directory", "read-only file"])
def test_p8_failed_copy_is_a_warning_not_a_failure(tmp_path, kind):
    if kind == "directory":
        target = tmp_path / "adir"
        target.mkdir()
    else:
        if os.geteuid() == 0:
            pytest.skip("root writes a read-only file")
        target = tmp_path / "ro.fq"
        target.write_text("", encoding="utf-8")
        target.chmod(stat.S_IRUSR)
    p, out = _verify_json(tmp_path, "t.llmll", "--fq-out", str(target))
    assert p.returncode == 0, p.stdout + p.stderr
    assert out["solver_verdict"] == "safe", p.stdout
    assert _sidecar(tmp_path, "t.llmll")
    assert ".fq not written to " + str(target) in p.stderr, p.stderr


def _reads_braces(tmp_path) -> bool:
    exe = shutil.which("fixpoint") or shutil.which("liquid-fixpoint")
    probe = tmp_path / "probe.fq"
    probe.write_text("qualif LlmllProbe(v : int) { (v >= 0) }\n", encoding="utf-8")
    p = subprocess.run([exe, "-q", "--json", str(probe)], capture_output=True, text=True,
                       timeout=TIMEOUT_S, cwd=str(tmp_path))
    return p.returncode == 0


def test_p9_copy_is_in_the_solver_form(tmp_path):
    braces = _reads_braces(tmp_path)
    copy = tmp_path / "out.fq"
    p, out = _verify_json(tmp_path, "t.llmll", "--fq-out", str(copy))
    assert p.returncode == 0, p.stdout + p.stderr
    quals = [l for l in copy.read_text(encoding="utf-8").splitlines() if l.startswith("qualif ")]
    assert quals
    if braces:
        assert all(") { " in l and l.endswith(" }") for l in quals), quals
    else:
        assert all("): (" in l for l in quals), quals


def test_p10_copy_exists_after_a_refuted_run(tmp_path):
    copy = tmp_path / "out.fq"
    p, out = _verify_json(tmp_path, "h.llmll", "--fq-out", str(copy))
    assert p.returncode == 1, p.stdout + p.stderr
    lines = copy.read_text(encoding="utf-8").splitlines()
    assert sum(1 for l in lines if l == "constraint:") == 1


# ---------------------------------------------------------------------------
# P4-P6: the default path, no flag
# ---------------------------------------------------------------------------

def test_p4_symlink_at_the_default_path(tmp_path):
    src = _copy(tmp_path, "h.llmll")
    path = _default_fq_path(src)
    assert not os.path.lexists(path), path   # derived from our tmp_path: ours
    os.symlink("/dev/null", path)
    try:
        p = _run(["verify", "h.llmll"], tmp_path)
    finally:
        _remove_own(path)
    assert p.returncode == 1, p.stdout + p.stderr
    # the plant was at the path llmll uses
    assert f".fq written to {path}" in p.stdout, p.stdout
    assert not _sidecar(tmp_path, "h.llmll")


def test_p5_fifo_at_the_default_path(tmp_path):
    src = _copy(tmp_path, "h.llmll")
    path = _default_fq_path(src)
    assert not os.path.lexists(path), path
    os.mkfifo(path)
    reader = _FifoReader(path)
    try:
        p = _run(["--json", "verify", "h.llmll"], tmp_path)
    finally:
        time.sleep(0.2)
        reader.close()
        _remove_own(path)
    assert p.returncode == 1, p.stdout + p.stderr
    assert json.loads(p.stdout)["solver_verdict"] == "refuted", p.stdout
    assert not _sidecar(tmp_path, "h.llmll")


def test_p6_concurrent_truncation_of_the_default_path(tmp_path):
    src = _copy(tmp_path, "h.llmll")
    path = _default_fq_path(src)
    assert not os.path.lexists(path), path
    stop = threading.Event()

    def truncate():
        while not stop.is_set():
            try:
                with open(path, "w"):
                    pass
            except OSError:
                pass

    t = threading.Thread(target=truncate, daemon=True)
    t.start()
    codes = []
    try:
        for _ in range(5):
            codes.append(_run(["--json", "verify", "h.llmll"], tmp_path).returncode)
    finally:
        stop.set()
        t.join(5)
        _remove_own(path)
    assert codes == [1] * 5, codes
    assert not _sidecar(tmp_path, "h.llmll")


# ---------------------------------------------------------------------------
# P11-P12: the other fixed paths
# ---------------------------------------------------------------------------

def _weaknesses(p):
    out = json.loads(p.stdout)
    return [w for w in out.get("weakness", {}).get("weaknesses", []) if w.get("kind") == "spec-weakness"]


def test_p11_weakness_check_does_not_use_the_fixed_path(tmp_path):
    fn = "fqoswk" + secrets.token_hex(6)
    src = tmp_path / "w.llmll"
    src.write_text(f"(def {fn} [x: int] -> int (post (>= result 0)) (if (>= x 0) x 0))\n",
                   encoding="utf-8")
    honest = _run(["--json", "verify", "--weakness-check", "w.llmll"], tmp_path)
    assert honest.returncode == 0, honest.stdout + honest.stderr
    fixed = f"/tmp/llmll-weakness-{fn}.fq"
    _remove_own(fixed)   # a v0.37.0 binary would have left it; the name is ours
    sentinel = tmp_path / "sentinel.txt"
    sentinel.write_text("sentinel\n", encoding="utf-8")
    os.symlink(str(sentinel), fixed)
    try:
        planted = _run(["--json", "verify", "--weakness-check", "w.llmll"], tmp_path)
    finally:
        _remove_own(fixed)
    assert planted.returncode == 0, planted.stdout + planted.stderr
    assert sentinel.read_text(encoding="utf-8") == "sentinel\n"
    assert len(_weaknesses(planted)) == len(_weaknesses(honest)) == 1


def test_p12_replay_does_not_use_the_fixed_path(tmp_path):
    fixed = "/tmp/llmll-replay-artifact.fq"
    if os.path.lexists(fixed):
        pytest.skip(f"{fixed} exists and is not this test's to replace")
    _copy(tmp_path, "t.llmll")
    art = tmp_path / "t.pa.json"
    v = _run(["verify", "t.llmll", "--proof-artifact", str(art)], tmp_path)
    assert v.returncode == 0, v.stdout + v.stderr
    sentinel = tmp_path / "sentinel.txt"
    sentinel.write_text("sentinel\n", encoding="utf-8")
    try:
        os.symlink(str(sentinel), fixed)
    except FileExistsError:
        pytest.skip(f"{fixed} appeared concurrently")
    try:
        r = _run(["replay-artifact", str(art)], tmp_path)
    finally:
        if os.path.islink(fixed) and os.readlink(fixed) == str(sentinel):
            _remove_own(fixed)
    assert r.returncode == 0, r.stdout + r.stderr
    assert "replay reproduced" in r.stdout, r.stdout
    assert sentinel.read_text(encoding="utf-8") == "sentinel\n"
