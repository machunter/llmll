"""FS-SIZE-1: wasi.fs.size against os.stat.

The design record is docs/design/collect-order-1-proposal.md (Rev 0). The
fact row it adds, {v : int | v >= 0} on the RCode arm, holds only because the
generated body refuses every target that is not a regular file; these cells
check that behaviour on a real filesystem.

WHAT A PASS HERE MEANS. fixtures/fs_size/fs_size.llmll is built once with
$LLMLL_BIN. Each cell runs the built program with one path on stdin and reads
what (wasi.fs.size path) answered.

  S1-S3  a regular file: empty, n bytes, and a sparse file past 2^31.
  S4     a symlink to a file answers the target's size (the link is followed).
  S5-S6  a missing path and a dangling link answer RErr.
  S7     a directory answers RErr.
  S8     a FIFO answers RErr and does not block.
  S9     a mode-000 file answers its size (stat needs no read permission).
  S10    the obligation report's effect_summary for the only caller is {fs.read}.
"""

import glob
import json
import os
import shlex
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURE = REPO_ROOT / "scripts" / "tests" / "fixtures" / "fs_size" / "fs_size.llmll"

pytestmark = pytest.mark.skipif(
    not os.environ.get("LLMLL_BIN"),
    reason="set LLMLL_BIN to a built llmll; the spec-roundtrip job runs this in CI",
)

BUILD_TIMEOUT_S = 600
RUN_TIMEOUT_S = 30


def _llmll() -> list[str]:
    return shlex.split(os.environ["LLMLL_BIN"])


@pytest.fixture(scope="module")
def exe(tmp_path_factory) -> str:
    out = tmp_path_factory.mktemp("fs_size_build")
    p = subprocess.run(
        [*_llmll(), "build", str(FIXTURE), "-o", str(out)],
        capture_output=True, text=True, timeout=BUILD_TIMEOUT_S, cwd=str(REPO_ROOT),
    )
    assert p.returncode == 0, f"llmll build failed rc={p.returncode}\n{p.stderr[-2000:]}"
    exes = glob.glob(str(out / ".stack-work" / "install" / "*" / "*" / "*" / "bin" / "*"))
    assert len(exes) == 1, f"expected one executable under {out}, found {exes}"
    return exes[0]


def _size(exe: str, path: Path) -> str:
    """Answer the program's printed Response for (wasi.fs.size path). The
    harness does not perform the halting step's command, so three lines."""
    r = subprocess.run([exe], input=f"{path}\n\n\n", capture_output=True,
                       text=True, timeout=RUN_TIMEOUT_S)
    assert r.returncode == 0, f"rc={r.returncode} stderr={r.stderr[-500:]!r}"
    # wasi.io.stdout ends each write with a newline: the empty :init write
    # gives the leading one, and the answer's write the trailing one.
    assert r.stdout.startswith("\n") and r.stdout.endswith("\n"), repr(r.stdout[:200])
    return r.stdout[1:-1]


def test_s1_empty_file_is_zero(exe, tmp_path):
    f = tmp_path / "empty"
    f.write_bytes(b"")
    assert _size(exe, f) == "RCode 0"


def test_s2_n_byte_file(exe, tmp_path):
    f = tmp_path / "data"
    f.write_bytes(b"x" * 12345)
    assert _size(exe, f) == f"RCode {os.stat(f).st_size}" == "RCode 12345"


def test_s3_sparse_file_past_2_31(exe, tmp_path):
    f = tmp_path / "sparse"
    n = 2**31 + 5
    with open(f, "wb") as h:
        h.truncate(n)
    assert os.stat(f).st_size == n
    assert _size(exe, f) == f"RCode {n}"


def test_s4_symlink_to_file_answers_target_size(exe, tmp_path):
    target = tmp_path / "target"
    target.write_bytes(b"abcdef")
    link = tmp_path / "link"
    os.symlink("target", link)
    assert _size(exe, link) == "RCode 6"


def test_s5_missing_path_is_rerr(exe, tmp_path):
    assert _size(exe, tmp_path / "missing").startswith("RErr ")


def test_s6_dangling_link_is_rerr(exe, tmp_path):
    link = tmp_path / "dangle"
    os.symlink("gone", link)
    assert _size(exe, link).startswith("RErr ")


def test_s7_directory_is_rerr(exe, tmp_path):
    d = tmp_path / "sub"
    d.mkdir()
    out = _size(exe, d)
    assert out.startswith("RErr ") and "is not a regular file" in out, out


def test_s8_fifo_is_rerr_and_does_not_block(exe, tmp_path):
    p = tmp_path / "pipe"
    os.mkfifo(p)
    # _size's RUN_TIMEOUT_S is the blocking check: opening the FIFO would hang.
    out = _size(exe, p)
    assert out.startswith("RErr ") and "is not a regular file" in out, out


@pytest.mark.skipif(hasattr(os, "geteuid") and os.geteuid() == 0,
                    reason="root reads a mode-000 file anyway; the cell needs an unprivileged user")
def test_s9_unreadable_file_still_answers_its_size(exe, tmp_path):
    f = tmp_path / "locked"
    f.write_bytes(b"0123456789")
    os.chmod(f, 0)
    try:
        assert _size(exe, f) == "RCode 10"
    finally:
        os.chmod(f, 0o600)


def test_s10_effect_summary_is_fs_read(tmp_path):
    p = subprocess.run(
        [*_llmll(), "verify", str(FIXTURE), "--obligation-report",
         "-o", str(tmp_path / "fs_size.fq")],
        capture_output=True, text=True, timeout=BUILD_TIMEOUT_S, cwd=str(REPO_ROOT),
    )
    doc = json.loads(p.stdout[p.stdout.index("{"):])
    entries = {e["function"]: e["effects"] for e in doc["effect_summary"]}
    # size-cmd calls nothing but wasi.fs.size: fs.read alone, not the top
    # ("unbounded") and not nondet (a size does not change with the clock).
    assert entries["size-cmd"] == ["fs.read"], entries
