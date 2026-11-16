"""BYTE-IO step 3 (BYTES-UNSIZED-1, BYTES-READ-1, BYTES-WRITE-1).

docs/design/byte-io-proposal.md Rev 2 + Amendment Rev 2a. The unsized `bytes`
type lowers to a strict ByteString; `bytes[n]` keeps its `[Word8]` lowering.

What a pass here means (step 3, S3: the runtime of the pure operations):

* BIO-B1..B7: a built program computes each pure operation on a fixed vector
  set, and every printed line equals a Python reference: bytes-make (length
  first), bytes-concat and bytes-concat-many (order), bytes-slice (half-open),
  bytes-get / bytes-set / bytes-length on `bytes` and on `bytes[n]`,
  bytes-widen, bytes-from-string (UTF-8, with U+DC80..U+DCFF back to one byte
  and any other lone surrogate as U+FFFD), bytes-to-string (strict; the offset
  of the first invalid sequence, as Python's decoder reports it) and
  bytes-from-list (the index of the first value outside 0..255).
* BIO-B8..B10: a built program stops with the operation's named pre-condition
  error: a transposed slice is not an empty result, an index of 2^64 + 1 is
  not index 1, and a byte value of 256 is not 0.
"""

import glob
import os
import shlex
import shutil
import signal
import subprocess
from pathlib import Path

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


def _build_and_run(work, src, timeout=60, args=(), stdin=""):
    work.mkdir(parents=True, exist_ok=True)
    (work / "p.llmll").write_text(src, encoding="utf-8")
    b = _run([*shlex.split(os.environ["LLMLL_BIN"]), "build", "p.llmll", "-o", str(work / "out")],
             cwd=work, timeout=BUILD_TIMEOUT_S)
    assert b.returncode == 0, b.stdout[-2000:] + b.stderr[-2000:]
    exes = glob.glob(str(work / "out" / ".stack-work" / "install" / "*" / "*" / "*" / "bin" / "*"))
    assert len(exes) == 1, exes
    return _run([exes[0], *args], cwd=work, stdin=stdin, timeout=timeout)


def _console(body, defs=""):
    """A console program that prints `body`, a string expression, then reads EOF."""
    return f"""(import wasi.io (capability stdout :deterministic false))
{defs}(def-main :mode console
  :init (pair 0 (wasi.io.stdout {body}))
  :step (fn [s: int line: string _r: Response] (pair s (wasi.io.stdout ""))))
"""


def _lit(s):
    """An LLMLL string literal for s, written as UTF-8 source. A literal cannot
    hold a lone surrogate (the lexer packs it into Text, which replaces one
    with U+FFFD), so those come from argv in BIO-B5b."""
    assert not any(0xD800 <= ord(c) <= 0xDFFF for c in s), s
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


# --- Python references -------------------------------------------------------

def ref_from_string(s):
    out = bytearray()
    for c in s:
        o = ord(c)
        if 0xDC80 <= o <= 0xDCFF:
            out.append(o - 0xDC00)
        elif 0xD800 <= o <= 0xDFFF:
            out += b"\xef\xbf\xbd"
        else:
            out += c.encode("utf-8")
    return bytes(out)


def ref_to_string(bs):
    try:
        s = bytes(bs).decode("utf-8")
    except UnicodeDecodeError as e:
        return f"err {e.start}"
    return f"ok {len(s)} " + _show(s.encode("utf-8"))


def ref_from_list(xs):
    for k, x in enumerate(xs):
        if x < 0 or x > 255:
            return f"err {k}"
    return "ok " + _show(bytes(xs))


def _show(bs):
    return "".join(f"{b} " for b in bs)


# --- the value program -------------------------------------------------------

STRINGS = ["", "abc", "\u00e9", "\U0001F600", "\u0080", "\u07ff", "\u0800", "\uffff",
           "\U0010FFFF", "a\u00e9\u03bb\U0001F600z"]
# argv bytes GHC decodes to lone surrogates U+DC80..U+DCFF (file-system encoding)
ARGV = [b"\xff", b"\x80", b"a\xfeb", b"\xc3\xa9", b"\xc3", b"\xed\xa0\x80", b"plain"]
E_ACUTE_X = "\u00e9x"
DECODE = [[0xC3], [0x61, 0xC3, 0x28], [0xC0, 0x80], [0xC1, 0xBF], [0xED, 0xA0, 0x80],
          [0xED, 0x9F, 0xBF], [0xF4, 0x90, 0x80, 0x80], [0xF4, 0x8F, 0xBF, 0xBF],
          [0xE0, 0x80, 0x80], [0xE0, 0xA0, 0x80], [0xF0, 0x80, 0x80, 0x80], [0xF0, 0x90, 0x80, 0x80],
          [0xF0, 0x9F, 0x98], [0xE2, 0x28, 0xA1], [0xFF], [0x80], [0xF5, 0x80, 0x80, 0x80],
          [0x61, 0x62], [0xC3, 0xA9], [0xE2, 0x82, 0xAC], []]
FROM_LIST = [[256], [1, -1], [0, 255, 128], [], [5, 300, -2]]

DEFS = """(def-shell show-bytes [b: bytes] -> string
  (list-fold (bytes-to-list b) "" (fn [acc: string x: int] (string-concat acc (string-concat (int-to-string x) " ")))))
(def-shell ln [label: string s: string] -> string (string-concat-many [label "=" s "\\n"]))
(def-shell show-fl [r: Result[bytes, int]] -> string
  (match r ((Success b) (string-concat "ok " (show-bytes b))) ((Error i) (string-concat "err " (int-to-string i)))))
(def-shell show-ts [r: Result[string, int]] -> string
  (match r
    ((Success s) (string-concat-many ["ok " (int-to-string (string-length s)) " " (show-bytes (bytes-from-string s))]))
    ((Error i) (string-concat "err " (int-to-string i)))))
(def-shell mk [xs: list[int]] -> bytes
  (match (bytes-from-list xs) ((Success b) b) ((Error i) (bytes-make 0 0))))
(def-shell z4 [] -> bytes[4] (bytes-zero))
"""


def _list(xs):
    return "[" + " ".join(str(x) if x >= 0 else f"(- 0 {-x})" for x in xs) + "]"


def _items():
    """(label, LLMLL string expression, expected text) for every value cell."""
    it = []
    # B1 bytes-make: the length comes first.
    it += [("make-3-7", "(show-bytes (bytes-make 3 7))", _show(bytes([7] * 3))),
           ("make-0-9", "(int-to-string (bytes-length (bytes-make 0 9)))", "0"),
           ("make-2-255", "(show-bytes (bytes-make 2 255))", _show(bytes([255, 255])))]
    # B2 concat order.
    it += [("concat", '(show-bytes (bytes-concat (bytes-from-string "ab") (bytes-from-string "c")))', _show(b"abc")),
           ("concat-many", '(show-bytes (bytes-concat-many [(bytes-from-string "a") (bytes-from-string "bc")'
                           ' (bytes-make 0 0) (bytes-from-string "d")]))', _show(b"abcd")),
           ("concat-many-empty", "(show-bytes (bytes-concat-many (list-empty)))", "")]
    # B3 slice: half-open [s, e).
    for s, e in [(1, 4), (2, 2), (0, 5), (5, 5), (0, 0)]:
        it.append((f"slice-{s}-{e}", f'(show-bytes (bytes-slice (bytes-from-string "hello") {s} {e}))', _show(b"hello"[s:e])))
    # B4 get / set / length on bytes and on bytes[n]; widen.
    it += [("get", '(int-to-string (bytes-get (bytes-from-string "abc") 2))', str(ord("c"))),
           ("set", '(show-bytes (bytes-set (bytes-from-string "abc") 1 255))', _show(b"a\xffc")),
           ("len", f'(int-to-string (bytes-length (bytes-from-string {_lit(E_ACUTE_X)})))', "3"),
           ("widen", "(show-bytes (bytes-widen (bytes-set (z4) 2 9)))", _show(bytes([0, 0, 9, 0]))),
           ("sized-get", "(int-to-string (bytes-get (bytes-set (z4) 3 200) 3))", "200"),
           ("sized-len", "(int-to-string (bytes-length (z4)))", "4"),
           ("to-list-len", '(int-to-string (list-length (bytes-to-list (bytes-from-string "hello"))))', "5")]
    # B5 bytes-from-string.
    for k, s in enumerate(STRINGS):
        it.append((f"fs-{k}", f"(show-bytes (bytes-from-string {_lit(s)}))", _show(ref_from_string(s))))
    # B6 bytes-to-string.
    for k, v in enumerate(DECODE):
        it.append((f"ts-{k}", f"(show-ts (bytes-to-string (mk {_list(v)})))", ref_to_string(v)))
    # B7 bytes-from-list.
    for k, v in enumerate(FROM_LIST):
        it.append((f"fl-{k}", f"(show-fl (bytes-from-list {_list(v)}))", ref_from_list(v)))
    return it


CELLS = {"B1": "make-", "B2": "concat", "B3": "slice-", "B4": ("get", "set", "len", "widen", "sized-", "to-list"),
         "B5": "fs-", "B6": "ts-", "B7": "fl-"}


@pytest.fixture(scope="module")
def value_run(tmp_path_factory):
    items = _items()
    # One short list per helper: GHC's time on one string-concat-many literal
    # grows steeply with its length (test_bitwise_char.py measured it).
    chunks = [items[i:i + 5] for i in range(0, len(items), 5)]
    defs = DEFS + "".join(
        f'(def-shell p{i} [u: int] -> string (string-concat-many [{" ".join(f"(ln {_lit(lab)} {e})" for lab, e, _ in c)}]))\n'
        for i, c in enumerate(chunks))
    top = " ".join(f"(p{i} 0)" for i in range(len(chunks)))
    r = _build_and_run(tmp_path_factory.mktemp("bio_values"), _console(f"(string-concat-many [{top}])", defs))
    assert r.returncode == 0, r.stdout + r.stderr
    got = {}
    for line in r.stdout.split("\n"):
        if "=" in line:
            k, v = line.split("=", 1)
            got[k] = v
    return items, got


@pytest.mark.parametrize("cell", sorted(CELLS))
def test_bio_b_value_cells_match_python(value_run, cell):
    items, got = value_run
    pref = CELLS[cell]
    pref = pref if isinstance(pref, tuple) else (pref,)
    mine = [(lab, want) for lab, _, want in items if lab.startswith(pref)]
    assert mine, cell
    assert [(lab, got.get(lab)) for lab, _ in mine] == mine


@pytest.mark.parametrize("cell,expr,message", [
    ("B8", '(show-bytes (bytes-slice (bytes-from-string "hello") 3 2))', "bytes-slice: pre-condition failed"),
    ("B9", '(int-to-string (bytes-get (bytes-from-string "ab") 18446744073709551617))',
     "bytes-get: pre-condition failed: index 18446744073709551617 out of bounds for bytes of length 2"),
    ("B10", "(show-bytes (bytes-make 2 256))", "bytes-make: pre-condition failed: value 256"),
])
def test_bio_b_built_program_stops_with_the_named_error(tmp_path, cell, expr, message):
    r = _build_and_run(tmp_path, _console(expr, DEFS))
    assert r.returncode != 0
    assert message in r.stdout + r.stderr


def test_bio_b5b_argv_lone_surrogates_convert_back_to_their_bytes(tmp_path):
    """GHC decodes an undecodable argv byte x as U+DC00 + x; bytes-from-string
    maps it back, so each argument converts to its original bytes."""
    src = """(import wasi.io (capability stdout :deterministic false))
(import wasi.proc (capability exec "none"))
""" + DEFS + """(def-shell show-args [xs: list[string]] -> string
  (list-fold xs "" (fn [acc: string a: string] (string-concat-many [acc "arg=" (show-bytes (bytes-from-string a)) "\\n"]))))
(def-main :mode console
  :init (pair 0 wasi.proc.args)
  :step (fn [s: int line: string r: Response]
    (match r
      ((RList xs) (pair s (wasi.io.stdout (show-args xs))))
      (_ (pair s (wasi.io.stdout ""))))))
"""
    r = _build_and_run(tmp_path, src, args=ARGV, stdin="x\n")
    assert r.returncode == 0, r.stdout + r.stderr
    got = [ln[len("arg="):] for ln in r.stdout.split("\n") if ln.startswith("arg=")]
    assert got == [_show(a) for a in ARGV]
