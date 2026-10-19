"""G7 tooling builtins: path-normalize, wasi.fs.list-kinds, ProcSpec, wasi.proc.exec.

The design record is docs/design/g7-tooling-builtins-proposal.md (Rev 0). It
closes PATH-NORM-1, LIST-KIND-1, PROC-ENV-1 and PROC-REDIRECT-1.

WHAT A PASS HERE MEANS. fixtures/g7_tooling/g7.llmll is built once with
$LLMLL_BIN. Each cell runs the built program with one tab-separated command
line on stdin and reads what the command answered. On v0.30.3 the program does
not build, because none of the ten builtins exists.

  P1-P7  path-normalize: the design's table, then Python's posixpath.normpath
         as an oracle over a seeded corpus, then idempotence.
  K1-K3  wasi.fs.list-kinds on a real directory: the four kinds, the error
         arms (the same as wasi.fs.list), and names with a space or newline.
  E1-E8  wasi.proc.exec: the environment is added to the inherited one, the
         last setter wins, the merge is an operation, the defaults, the
         timeout, a computed bad name, and a missing executable.
"""

import glob
import os
import posixpath
import random
import shlex
import shutil
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURE = REPO_ROOT / "scripts" / "tests" / "fixtures" / "g7_tooling" / "g7.llmll"

pytestmark = pytest.mark.skipif(
    not os.environ.get("LLMLL_BIN"),
    reason="set LLMLL_BIN to a built llmll; the spec-roundtrip job runs this in CI",
)

BUILD_TIMEOUT_S = 600
RUN_TIMEOUT_S = 30
SEP = "<<SEP>>"


def _llmll() -> list[str]:
    return shlex.split(os.environ["LLMLL_BIN"])


@pytest.fixture(scope="module")
def exe(tmp_path_factory) -> str:
    out = tmp_path_factory.mktemp("g7_build")
    p = subprocess.run(
        [*_llmll(), "build", str(FIXTURE), "-o", str(out)],
        capture_output=True, text=True, timeout=BUILD_TIMEOUT_S, cwd=str(REPO_ROOT),
    )
    assert p.returncode == 0, f"llmll build failed rc={p.returncode}\n{p.stderr[-2000:]}"
    exes = glob.glob(str(out / ".stack-work" / "install" / "*" / "*" / "*" / "bin" / "*"))
    assert len(exes) == 1, f"expected one executable under {out}, found {exes}"
    return exes[0]


def _run(exe: str, cwd: Path, *fields: str) -> str:
    """Run one command line; answer the program's stdout. The harness does not
    perform the halting step's command, so the program prints on step 1 and
    halts on step 2: three lines in all."""
    r = subprocess.run([exe], input="\t".join(fields) + "\n\n\n", capture_output=True,
                       text=True, timeout=RUN_TIMEOUT_S, cwd=str(cwd))
    assert r.returncode == 0, f"rc={r.returncode} stderr={r.stderr[-500:]!r}"
    # wasi.io.stdout ends each write with a newline: the empty :init write
    # gives the leading one, and the answer's write the trailing one.
    assert r.stdout.startswith("\n") and r.stdout.endswith("\n"), repr(r.stdout[:200])
    return r.stdout[1:-1]


def _normalize(exe: str, tmp: Path, paths: list[str]) -> list[str]:
    corpus = tmp / "corpus.txt"
    corpus.write_text("\n".join(paths), encoding="utf-8")
    return _run(exe, tmp, "norm", str(corpus)).splitlines()


# --- path-normalize ----------------------------------------------------------

TABLE = [
    ("P1", "a/b/../c", "a/c"),
    ("P2", "../../a", "../../a"),
    ("P3", "/../a", "/a"),
    ("P4", "", "."),
    ("P5", "a/", "a"),
]


@pytest.mark.parametrize("key,given,expected", TABLE, ids=[t[0] for t in TABLE])
def test_path_table(exe, tmp_path, key, given, expected):
    assert _normalize(exe, tmp_path, [given]) == [expected], (key, given)


def _corpus(n: int = 200, seed: int = 7) -> list[str]:
    rng = random.Random(seed)
    parts = ["a", "b", ".", "..", ""]
    out = []
    for _ in range(n):
        p = "/".join(rng.choice(parts) for _ in range(rng.randint(1, 6)))
        out.append(rng.choice(["", "/", "//"]) + p)
    return out


def _oracle(p: str) -> str:
    # The one stated difference: posixpath keeps a leading "//" (POSIX leaves it
    # implementation-defined); path-normalize collapses it to "/".
    q = posixpath.normpath(p)
    return "/" + q.lstrip("/") if q.startswith("//") else q


def test_p6_agrees_with_posixpath(exe, tmp_path):
    corpus = _corpus()
    got = _normalize(exe, tmp_path, corpus)
    bad = [(p, g, _oracle(p)) for p, g in zip(corpus, got) if g != _oracle(p)]
    assert len(got) == len(corpus)
    assert not bad, f"{len(bad)} disagreements, first: {bad[:5]}"


def test_p7_idempotent(exe, tmp_path):
    once = _normalize(exe, tmp_path, _corpus())
    assert _normalize(exe, tmp_path, once) == once


# --- wasi.fs.list-kinds ------------------------------------------------------

def _rlist(out: str) -> list[str]:
    assert out.startswith("RList "), out[:200]
    body = out[len("RList "):].rstrip("\n")
    return [e for e in body.split(SEP)][:-1] if body else []


def test_k1_four_kinds(exe, tmp_path):
    t = tmp_path / "t"
    (t / "sub").mkdir(parents=True)
    (t / "file").write_text("hi")
    os.symlink("file", t / "lfile")
    os.symlink("sub", t / "lsub")
    os.symlink("gone", t / "dangle")
    os.mkfifo(t / "pipe")
    assert _rlist(_run(exe, tmp_path, "kinds", str(t))) == [
        "l dangle", "f file", "l lfile", "l lsub", "o pipe", "d sub"]


def test_k2_error_arms_match_wasi_fs_list(exe, tmp_path):
    (tmp_path / "empty").mkdir()
    (tmp_path / "afile").write_text("x")
    assert _run(exe, tmp_path, "kinds", str(tmp_path / "empty")).startswith("RList ")
    assert _rlist(_run(exe, tmp_path, "kinds", str(tmp_path / "empty"))) == []
    for target in ("missing", "afile"):
        kinds = _run(exe, tmp_path, "kinds", str(tmp_path / target))
        plain = _run(exe, tmp_path, "list", str(tmp_path / target))
        assert kinds.startswith("RErr ") and plain.startswith("RErr "), (target, kinds, plain)


def test_k3_names_with_space_and_newline(exe, tmp_path):
    t = tmp_path / "t"
    t.mkdir()
    for name in ("a b", "x\ny"):
        (t / name).write_text("")
    entries = _rlist(_run(exe, tmp_path, "kinds", str(t)))
    assert entries == ["f a b", "f x\ny"]
    assert [e[2:] for e in entries] == ["a b", "x\ny"]


# --- wasi.proc.exec ----------------------------------------------------------

def _exec(exe: str, tmp: Path, variant: str, arg: str = "") -> tuple[str, Path]:
    w = tmp / "w"
    if w.exists():
        shutil.rmtree(w)
    w.mkdir()
    return _run(exe, tmp, "exec", variant, str(w), arg).strip(), w


def test_e1_env_is_added_to_the_inherited_environment(exe, tmp_path):
    out, w = _exec(exe, tmp_path, "env")
    assert out == "RCode 0"
    lc_all, _, path = (w / "out").read_text().strip().partition("|")
    assert lc_all == "C"
    assert path == os.environ["PATH"], "the child lost the inherited PATH"


def test_e2_last_env_setter_wins(exe, tmp_path):
    out, w = _exec(exe, tmp_path, "env-twice")
    assert out == "RCode 0"
    assert (w / "out").read_text().strip() == "two"


def test_e3_merge_puts_both_streams_in_one_file(exe, tmp_path):
    out, w = _exec(exe, tmp_path, "merge")
    assert out == "RCode 0"
    assert (w / "out").read_text().split() == ["to-out", "to-err"]


def test_e4_a_later_proc_stderr_cancels_the_merge(exe, tmp_path):
    out, w = _exec(exe, tmp_path, "unmerge")
    assert out == "RCode 0"
    assert (w / "out").read_text().strip() == "to-out"
    assert (w / "err").read_text().strip() == "to-err"


def test_e5_defaults_and_stdin(exe, tmp_path):
    out, w = _exec(exe, tmp_path, "defaults")
    assert out == "RCode 0", "discarded output must not fail the child"
    assert (w / "stdin-bytes").read_text().strip() == "0", "default stdin is empty"
    src = tmp_path / "input.txt"
    src.write_text("fed through proc-stdin\n")
    out, w = _exec(exe, tmp_path, "stdin", str(src))
    assert out == "RCode 0"
    assert (w / "got").read_text() == "fed through proc-stdin\n"


def test_e6_timeout_is_a_value(exe, tmp_path):
    out, _ = _exec(exe, tmp_path, "timeout")
    assert out.startswith("RErr ") and "exceeded 1s" in out, out


def test_e7_computed_bad_name_answers_rerr_before_the_child_starts(exe, tmp_path):
    out, w = _exec(exe, tmp_path, "bad-name", "A=B")
    assert out.startswith("RErr ") and "cannot name an environment variable" in out, out
    assert not (w / "started").exists(), "the child ran"


def test_e8_missing_executable_and_exit_status(exe, tmp_path):
    out, _ = _exec(exe, tmp_path, "missing")
    assert out.startswith("RErr "), out
    out, _ = _exec(exe, tmp_path, "exit3")
    assert out == "RCode 3"
