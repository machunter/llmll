"""COLLECT-ORDER-1: string-compare, list-sort, list-sort-by, list-reverse,
map-keys, map-entries and regex-replace-all, end to end.

The design record is docs/design/collect-order-1-proposal.md (Rev 0). It
closes STR-ORDER-1, LIST-SORT-1, MAP-ITER-1 and REGEX-REPLACE-1.

WHAT A PASS HERE MEANS. fixtures/collect_order/co.llmll is built once with
$LLMLL_BIN, so GHC compiles every new preamble body. Each cell writes a corpus
file, runs the built program with one tab-separated command line on stdin, and
compares the answer with Python as the oracle. Python's str order is code-point
order, which is the order the design chose, so the oracle is exact.
"""

import glob
import os
import random
import shlex
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURE = REPO_ROOT / "scripts" / "tests" / "fixtures" / "collect_order" / "co.llmll"

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
    out = tmp_path_factory.mktemp("co_build")
    p = subprocess.run(
        [*_llmll(), "build", str(FIXTURE), "-o", str(out)],
        capture_output=True, text=True, timeout=BUILD_TIMEOUT_S, cwd=str(REPO_ROOT),
    )
    assert p.returncode == 0, f"llmll build failed rc={p.returncode}\n{p.stderr[-2000:]}"
    exes = glob.glob(str(out / ".stack-work" / "install" / "*" / "*" / "*" / "bin" / "*"))
    assert len(exes) == 1, f"expected one executable under {out}, found {exes}"
    return exes[0]


def _run(exe: str, tmp: Path, mode: str, lines: list[str]) -> list[str]:
    """Write the corpus, run one mode over it, answer the printed lines. The
    harness does not perform the halting step's command, so the program prints
    on step 1 and halts on step 2: three stdin lines in all."""
    corpus = tmp / f"{mode}.txt"
    corpus.write_text("\n".join(lines), encoding="utf-8")
    r = subprocess.run([exe], input=f"{mode}\t{corpus}\n\n\n", capture_output=True,
                       text=True, encoding="utf-8", timeout=RUN_TIMEOUT_S, cwd=str(tmp))
    assert r.returncode == 0, f"rc={r.returncode} stderr={r.stderr[-500:]!r}"
    # wasi.io.stdout ends each write with a newline: the empty :init write
    # gives the leading one, and the answer's write the trailing one. The
    # answer itself ends every line it prints with a newline.
    assert r.stdout.startswith("\n") and r.stdout.endswith("\n"), repr(r.stdout[:200])
    answer = r.stdout[1:-1]
    assert answer == "" or answer.endswith("\n"), repr(answer[-200:])
    return answer.split("\n")[:-1]


def _words(n: int, seed: int) -> list[str]:
    rng = random.Random(seed)
    alphabet = ["a", "b", "B", "z", "Z", "0", " ", "é", "￿", "\U00010000", "中"]
    return ["".join(rng.choice(alphabet) for _ in range(rng.randint(0, 5))) for _ in range(n)]


# --- STR-ORDER-1: string-compare ---------------------------------------------

def _cmp(a: str, b: str) -> int:
    return (a > b) - (a < b)


def test_so_cmp_agrees_with_python_str_order(exe, tmp_path):
    corpus = _words(300, seed=11)
    corpus = [w for w in corpus if w != ""] + ["", "a", "ab", "￿", "\U00010000"]
    got = _run(exe, tmp_path, "cmp", corpus)
    want = [str(_cmp(a, b)) for a, b in zip(corpus, corpus[1:])]
    assert got == want


# --- LIST-SORT-1: list-sort, list-sort-by, list-reverse ---------------------

def test_ls_sort_agrees_with_python_sorted(exe, tmp_path):
    corpus = _words(300, seed=12) + ["", "a", "a", "\U00010000", "\uffff"]
    assert _run(exe, tmp_path, "sort", corpus) == sorted(corpus)


def test_ls_sort_keeps_duplicates_and_orders_ints_numerically(exe, tmp_path):
    rng = random.Random(13)
    nums = [rng.randint(-1000, 1000) for _ in range(200)] + [3, 1, 3, -1, -10, 5]
    got = _run(exe, tmp_path, "nums", [str(n) for n in nums])
    assert got == [str(n) for n in sorted(nums)]


def test_ls_sortby_pair_key_is_the_probe_order(exe, tmp_path):
    rng = random.Random(14)
    lines = [f"{rng.choice([10, 20, 30])} {rng.choice(['a', 'b', 'c', 'Z'])}" for _ in range(100)]
    lines += ["10 b", "20 a", "10 a"]
    def key(l):
        n, w = l.split(" ")
        return (-int(n), w)
    assert _run(exe, tmp_path, "sortby", lines) == sorted(lines, key=key)


def test_ls_sortby_is_stable(exe, tmp_path):
    corpus = _words(300, seed=15)
    corpus = [w for w in corpus if w != ""]
    assert _run(exe, tmp_path, "stable", corpus) == sorted(corpus, key=len)


def test_ls_reverse(exe, tmp_path):
    corpus = _words(50, seed=16) + ["x"]
    assert _run(exe, tmp_path, "rev", corpus) == list(reversed(corpus))
