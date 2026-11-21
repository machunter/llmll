"""BYTES-TABULATE-1 (docs/design/image-library-proposal.md Rev 3, Part B).

`(bytes-tabulate n gen a1 ... ak)` builds an n-byte `bytes` value whose byte i
is `gen(a1, ..., ak, i)`. `gen` is the bare name of a top-level `def` with a
`post`.

What a pass here means (step 1: codegen and run time, B cells, GHC):

* BT-B1: a built program computes `invert` (255 - byte) on fixed random
  buffers, and a generator with two extra arguments, and every printed line
  equals a Python reference. The extra arguments come before the index, in
  order.
* BT-B2: n = 0 gives the empty buffer and the generator is never called (a
  generator that stops when called is used).
* BT-B3 (edge case 5): n = 0 with an argument that stops the program still
  stops it. Arguments are evaluated before the index loop (call-by-value).
* BT-B4 (edge case 3): with contracts stripped, a generator value of 256 stops
  the program at that index with "outside byte range 0..255", before any
  narrowing to a byte.
* BT-B5 (edge case 10): n = 2^64 + 5 stops with "too large to represent"; it is
  not narrowed to a 5-byte buffer.
* BT-B6: n = -1 stops with the length guard's text.
* BT-B7: n and the arguments are evaluated once, in order, before the loop:
  with n = (bytes-get buf 99) and a1 = (bytes-get buf 98) the run stops on
  index 99, not 98.

The verifier cells (V, T) belong to step 3.
"""

import glob
import os
import random
import shlex
import shutil
import signal
import subprocess

import pytest

pytestmark = [
    pytest.mark.skipif(not os.environ.get("LLMLL_BIN"), reason="set LLMLL_BIN to a built llmll"),
    pytest.mark.skipif(shutil.which("stack") is None, reason="llmll build needs stack on PATH"),
]

BUILD_TIMEOUT_S = 900


def _kill_tree(pid):
    """SIGKILL a process and every descendant (llmll's stack, ghc)."""
    rows = subprocess.run(["ps", "-axo", "pid=,ppid="], capture_output=True, text=True).stdout.split("\n")
    kids = {}
    for row in rows:
        parts = row.split()
        if len(parts) == 2:
            kids.setdefault(int(parts[1]), []).append(int(parts[0]))
    todo, seen = [pid], []
    while todo:
        p = todo.pop()
        seen.append(p)
        todo.extend(kids.get(p, []))
    for p in seen:
        try:
            os.kill(p, signal.SIGKILL)
        except ProcessLookupError:
            pass


def _run(cmd, cwd=None, stdin="", timeout=120):
    proc = subprocess.Popen(cmd, cwd=None if cwd is None else str(cwd), text=True, errors="replace",
                            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        out, err = proc.communicate(stdin, timeout=timeout)
    except subprocess.TimeoutExpired:
        _kill_tree(proc.pid)
        proc.communicate()
        raise
    return subprocess.CompletedProcess(cmd, proc.returncode, out, err)


def _build(work, src, contracts=None):
    """Build `src` in `work` and return the path of the one executable."""
    work.mkdir(parents=True, exist_ok=True)
    (work / "p.llmll").write_text(src, encoding="utf-8")
    extra = [] if contracts is None else ["--contracts", contracts]
    b = _run([*shlex.split(os.environ["LLMLL_BIN"]), "build", "p.llmll", "-o", str(work / "out"), *extra],
             cwd=work, timeout=BUILD_TIMEOUT_S)
    assert b.returncode == 0, b.stdout[-2000:] + b.stderr[-2000:]
    exes = glob.glob(str(work / "out" / ".stack-work" / "install" / "*" / "*" / "*" / "bin" / "*"))
    assert len(exes) == 1, exes
    return exes[0]


def _show(bs):
    return "".join(f"{b} " for b in bs)


def _list(xs):
    return "[" + " ".join(str(x) for x in xs) + "]"


DEFS = """(def-shell show-bytes [b: bytes] -> string
  (list-fold (bytes-to-list b) "" (fn [acc: string x: int] (string-concat acc (string-concat (int-to-string x) " ")))))
(def-shell ln [label: string s: string] -> string (string-concat-many [label "=" s "\\n"]))
(def-shell mk [xs: list[int]] -> bytes
  (match (bytes-from-list xs) ((Success b) b) ((Error i) (bytes-make 0 0))))
(def inv-at [buf: bytes i: int] -> int
  (pre (and (>= i 0) (< i (bytes-length buf))))
  (post (= result (- 255 (bytes-get buf i))))
  (- 255 (bytes-get buf i)))
(def-shell invert [buf: bytes] -> bytes
  (bytes-tabulate (bytes-length buf) inv-at buf))
(def lin-at [a: int b: int i: int] -> int
  (pre (>= i 0))
  (post (and (>= result 0) (<= result 255)))
  (mod (+ (- a b) i) 256))
(def boom-at [i: int] -> int
  (post (>= result 0))
  (bytes-get (bytes-make 0 0) i))
(def k-at [k: int i: int] -> int
  (post (= result 0))
  0)
(def bad-at [buf: bytes i: int] -> int
  (pre (and (>= i 0) (< i (bytes-length buf))))
  (post (>= result 0))
  (+ (bytes-get buf i) 1))
"""

_rng = random.Random(20261120)
BUFFERS = [[], [0], [255], [0, 1, 2, 254, 255]] + [
    [_rng.randrange(256) for _ in range(n)] for n in (7, 64, 300)]
LIN = [(0, 0, 0), (10, 3, 5), (3, 10, 300), (1000, 7, 20)]


def _console(defs, init_expr, step_expr):
    return f"""(import wasi.io (capability stdout :deterministic false))
{defs}(def-main :mode console
  :init (pair 0 (wasi.io.stdout {init_expr}))
  :step (fn [s: int line: string _r: Response] (pair s (wasi.io.stdout {step_expr}))))
"""


def _items():
    """(label, LLMLL string expression, expected text) for every value cell."""
    it = []
    for k, xs in enumerate(BUFFERS):
        it.append((f"inv-{k}", f"(show-bytes (invert (mk {_list(xs)})))", _show(bytes(255 - x for x in xs))))
    for k, (a, b, n) in enumerate(LIN):
        it.append((f"lin-{k}", f"(show-bytes (bytes-tabulate {n} lin-at {a} {b}))",
                   _show(bytes(((a - b) + i) % 256 for i in range(n)))))
    it.append(("zero-len", "(int-to-string (bytes-length (bytes-tabulate 0 boom-at)))", "0"))
    it.append(("zero-show", "(show-bytes (bytes-tabulate 0 boom-at))", ""))
    return it


@pytest.fixture(scope="module")
def value_run(tmp_path_factory):
    items = _items()
    chunks = [items[i:i + 5] for i in range(0, len(items), 5)]
    defs = DEFS + "".join(
        f'(def-shell p{i} [u: int] -> string (string-concat-many [{" ".join(f"(ln {chr(34)}{lab}{chr(34)} {e})" for lab, e, _ in c)}]))\n'
        for i, c in enumerate(chunks))
    top = " ".join(f"(p{i} 0)" for i in range(len(chunks)))
    exe = _build(tmp_path_factory.mktemp("bt_values"), _console(defs, f"(string-concat-many [{top}])", '""'))
    r = _run([exe])
    assert r.returncode == 0, r.stdout + r.stderr
    got = {}
    for line in r.stdout.split("\n"):
        if "=" in line:
            k, v = line.split("=", 1)
            got[k] = v
    return items, got


@pytest.mark.parametrize("cell,prefix", [("B1", ("inv-", "lin-")), ("B2", ("zero-",))])
def test_bt_b_value_cells_match_python(value_run, cell, prefix):
    items, got = value_run
    mine = [(lab, want) for lab, _, want in items if lab.startswith(prefix)]
    assert mine, cell
    assert [(lab, got.get(lab)) for lab, _ in mine] == mine


# Each stopping expression is selected by one stdin line, so one build serves
# B3, B5, B6 and B7 (default contracts). `if` is lazy in the generated code.
STOPS = {
    "B3": ('(show-bytes (bytes-tabulate 0 k-at (bytes-get (mk [1 2 3 4]) 99)))',
           "bytes-get: pre-condition failed: index 99 out of bounds for bytes of length 4"),
    "B5": ("(show-bytes (bytes-tabulate 18446744073709551621 boom-at))",
           "bytes-tabulate: length 18446744073709551621 is too large to represent"),
    "B6": ("(show-bytes (bytes-tabulate (- 0 1) boom-at))",
           "bytes-tabulate: pre-condition failed: length -1 is negative"),
    "B7": ("(show-bytes (bytes-tabulate (bytes-get (mk [1 2 3 4]) 99) k-at (bytes-get (mk [1 2 3 4]) 98)))",
           "bytes-get: pre-condition failed: index 99 out of bounds for bytes of length 4"),
}


@pytest.fixture(scope="module")
def stop_exe(tmp_path_factory):
    pick = '""'
    for cell, (expr, _) in sorted(STOPS.items(), reverse=True):
        pick = f'(if (= line "{cell}") {expr} {pick})'
    return _build(tmp_path_factory.mktemp("bt_stops"), _console(DEFS, '""', pick))


@pytest.mark.parametrize("cell", sorted(STOPS))
def test_bt_b_built_program_stops_with_the_named_error(stop_exe, cell):
    r = _run([stop_exe], stdin=cell + "\n")
    out = r.stdout + r.stderr
    assert r.returncode != 0, out
    assert STOPS[cell][1] in out, out
    if cell == "B7":
        assert "index 98" not in out, out


def test_bt_b4_a_value_past_255_stops_at_its_index_with_contracts_stripped(tmp_path):
    """Edge case 3, run time: bad-at gives byte + 1, so the byte 255 at index 2
    gives 256. The guard names the value and the index; nothing is narrowed."""
    expr = "(show-bytes (bytes-tabulate 4 bad-at (mk [0 10 255 3])))"
    exe = _build(tmp_path, _console(DEFS, expr, '""'), contracts="none")
    r = _run([exe])
    out = r.stdout + r.stderr
    assert r.returncode != 0, out
    assert "bytes-tabulate: generator value 256 at index 2 outside byte range 0..255" in out, out
