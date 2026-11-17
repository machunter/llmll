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

S7 (the four commands) and S8 (the verifier witnesses and the trust report)
state what their cells mean beside them, below.
"""

import glob
import json
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


# --- S7: the four byte commands (BYTES-READ-1, BYTES-WRITE-1) ----------------
#
# What a pass here means:
#
# * BIO-C1..C5: wasi.fs.read-bytes delivers every byte of a file on RBytes
#   (byte 0xFF included, edge case 2), an empty file as RBytes of length 0, not
#   RNone (edge case 1), and RErr for a directory and for a missing path (edge
#   case 3); wasi.fs.write-bytes writes all 256 byte values and they read back.
# * BIO-C6..C8: wasi.io.stdout-bytes with an empty value writes nothing and
#   delivers RNone (edge case 17); text and byte writes interleave in command
#   order, 61 FF 63, to a file and to a pipe (edge case 22, P13).
# * BIO-C9, C10: two wasi.io.stdin-bytes reads deliver all of standard input,
#   then RBytes of length 0 (edge case 21); a piped 0xFF arrives unchanged.
# * BIO-C11: check refuses byte stdio named by the entry module of a console
#   program (byte-stdio-console, edge case 6); the same commands issued from an
#   imported module pass check and publish RErr at run time (Rev 2a item 3).
# * BIO-C12: the CRC-32 of a file read with wasi.fs.read-bytes equals
#   Python's zlib.crc32 (the design's worked example, end to end).

REPO = Path(__file__).resolve().parents[2]
TINY_Y4M = REPO / "examples" / "y4m" / "samples" / "tiny.y4m"


def _build(work, files, entry="p.llmll"):
    """Write files (name -> source) into work, build entry, return the executable."""
    work.mkdir(parents=True, exist_ok=True)
    for name, src in files.items():
        (work / name).write_text(src, encoding="utf-8")
    b = _run([*shlex.split(os.environ["LLMLL_BIN"]), "build", entry, "-o", str(work / "out")],
             cwd=work, timeout=BUILD_TIMEOUT_S)
    assert b.returncode == 0, b.stdout[-2000:] + b.stderr[-2000:]
    exes = glob.glob(str(work / "out" / ".stack-work" / "install" / "*" / "*" / "*" / "bin" / "*"))
    assert len(exes) == 1, exes
    return exes[0]


def _run_bytes(cmd, cwd, stdin=b"", stdout=subprocess.PIPE, timeout=60):
    """Run with byte-exact standard streams."""
    p = subprocess.run(cmd, cwd=str(cwd), input=stdin, stdout=stdout, stderr=subprocess.PIPE,
                       timeout=timeout)
    return p


CRC_DEFS = """(def-shell crc-bits [c: int k: int] -> int
  (pre (and (and (>= c 0) (<= c 4294967295)) (>= k 0)))
  (post (and (>= result 0) (<= result 4294967295)))
  (decreases k)
  (if (= k 0)
      c
      (crc-bits (if (= (bit-and c 1) 1)
                    (bit-xor (bit-shr c 1) 3988292384)
                    (bit-shr c 1))
                (- k 1))))
(def-shell crc-byte [c: int b: int] -> int
  (pre (and (and (>= c 0) (<= c 4294967295)) (and (>= b 0) (<= b 255))))
  (post (and (>= result 0) (<= result 4294967295)))
  (crc-bits (bit-xor c b) 8))
(def-shell crc-loop [buf: bytes i: int c: int] -> int
  (pre (and (and (>= i 0) (<= i (bytes-length buf)))
            (and (>= c 0) (<= c 4294967295))))
  (post (and (>= result 0) (<= result 4294967295)))
  (decreases (- (bytes-length buf) i))
  (if (= i (bytes-length buf))
      c
      (crc-loop buf (+ i 1) (crc-byte c (bytes-get buf i)))))
(def-shell crc32 [buf: bytes] -> int
  (bit-xor (crc-loop buf 0 4294967295) 4294967295))
"""

# One cli program, one build; argv[0] picks the scenario.
CLI = """(import wasi.io (capability stdin))
(import wasi.io (capability stdout :deterministic false))
(import wasi.fs (capability read-write "/"))
(import wasi.proc (capability exec :deterministic false))
""" + DEFS + CRC_DEFS + """(def-shell arg [xs: list[string] i: int] -> string (unwrap-or (list-nth xs i) ""))
(def-shell all256 [] -> bytes (mk (range 0 256)))
(def-shell desc [r: Response] -> string
  (match r
    ((RBytes b) (string-concat-many ["RBytes " (int-to-string (bytes-length b)) ": " (show-bytes b)]))
    ((RErr e) "RErr")
    ((RNone) "RNone")
    (_ "other")))
(def-shell crcdesc [r: Response] -> string
  (match r ((RBytes b) (int-to-string (crc32 b))) (_ "RErr")))
(def-shell start [xs: list[string]] -> ((int, string), Command)
  (let [(mode (arg xs 0)) (p (arg xs 1))]
    (if (= mode "read") (pair (pair 10 p) (wasi.fs.read-bytes p))
    (if (= mode "write") (pair (pair 20 p) (wasi.fs.write-bytes p (all256)))
    (if (= mode "stdin") (pair (pair 10 p) wasi.io.stdin-bytes)
    (if (= mode "stdin2") (pair (pair 40 p) wasi.io.stdin-bytes)
    (if (= mode "inter") (pair (pair 50 p) (wasi.io.stdout "a"))
    (if (= mode "empty") (pair (pair 60 p) (wasi.io.stdout-bytes (bytes-make 0 0)))
    (if (= mode "crc") (pair (pair 70 p) (wasi.fs.read-bytes p))
      (pair (pair 99 p) (wasi.io.stdout "bad mode")))))))))))
(def-shell step [s: (int, string) r: Response] -> ((int, string), Command)
  (let [(ph (first s)) (acc (second s))]
    (if (= ph 0)
      (match r ((RList xs) (start xs)) (_ (pair (pair 99 "") (wasi.io.stdout "no argv"))))
    (if (= ph 10) (pair (pair 99 acc) (wasi.io.stdout (desc r)))
    (if (= ph 20)
      (match r
        ((RNone) (pair (pair 10 acc) (wasi.fs.read-bytes acc)))
        (_ (pair (pair 99 acc) (wasi.io.stdout (string-concat "write: " (desc r))))))
    (if (= ph 40) (pair (pair 41 (desc r)) wasi.io.stdin-bytes)
    (if (= ph 41) (pair (pair 99 acc) (wasi.io.stdout (string-concat-many [acc "|" (desc r)])))
    (if (= ph 50) (pair (pair 51 acc) (wasi.io.stdout-bytes (bytes-make 1 255)))
    (if (= ph 51) (pair (pair 99 acc) (wasi.io.stdout "c"))
    (if (= ph 60) (pair (pair 99 acc) (wasi.io.stdout (desc r)))
    (if (= ph 70) (pair (pair 99 acc) (wasi.io.stdout (crcdesc r)))
      (pair (pair 100 acc) (wasi.io.stdout "")))))))))))))
(def-shell done? [s: (int, string)] -> bool (>= (first s) 100))
(def-main :mode cli
  :init (pair (pair 0 "") wasi.proc.args)
  :step step
  :done? done?)
"""


@pytest.fixture(scope="module")
def cli_exe(tmp_path_factory):
    work = tmp_path_factory.mktemp("bio_cli")
    return work, _build(work, {"p.llmll": CLI})


def _cli(cli_exe, *args, stdin=b"", stdout=subprocess.PIPE):
    work, exe = cli_exe
    r = _run_bytes([exe, *args], work, stdin=stdin, stdout=stdout)
    assert r.returncode == 0, (r.stdout, r.stderr)
    return r


def test_bio_c1_read_bytes_delivers_every_byte_ff_included(cli_exe, tmp_path):
    f = tmp_path / "bin.dat"
    data = b"\x00\xff\xc3\x28\x0a\x80"
    f.write_bytes(data)
    assert _cli(cli_exe, "read", str(f)).stdout == f"RBytes {len(data)}: {_show(data)}".encode()


def test_bio_c2_an_empty_file_is_rbytes_of_length_0_not_rnone(cli_exe, tmp_path):
    f = tmp_path / "empty.dat"
    f.write_bytes(b"")
    assert _cli(cli_exe, "read", str(f)).stdout == b"RBytes 0: "


def test_bio_c3_a_directory_is_rerr(cli_exe, tmp_path):
    assert _cli(cli_exe, "read", str(tmp_path)).stdout == b"RErr"


def test_bio_c4_a_missing_path_is_rerr(cli_exe, tmp_path):
    assert _cli(cli_exe, "read", str(tmp_path / "absent.dat")).stdout == b"RErr"


def test_bio_c5_write_bytes_writes_all_256_values_and_they_read_back(cli_exe, tmp_path):
    f = tmp_path / "out.dat"
    f.write_bytes(b"old contents that must be overwritten, longer than nothing" * 10)
    r = _cli(cli_exe, "write", str(f))
    assert f.read_bytes() == bytes(range(256))
    assert r.stdout == f"RBytes 256: {_show(bytes(range(256)))}".encode()


def test_bio_c6_stdout_bytes_with_an_empty_value_writes_nothing_and_delivers_rnone(cli_exe):
    assert _cli(cli_exe, "empty").stdout == b"RNone"


def test_bio_c7_text_and_byte_writes_interleave_in_order_to_a_file(cli_exe, tmp_path):
    out = tmp_path / "inter.out"
    with open(out, "wb") as fo:
        _cli(cli_exe, "inter", stdout=fo)
    assert out.read_bytes() == b"a\xffc"


def test_bio_c8_text_and_byte_writes_interleave_in_order_to_a_pipe(cli_exe):
    assert _cli(cli_exe, "inter").stdout == b"a\xffc"


def test_bio_c9_a_second_stdin_read_delivers_length_0(cli_exe):
    data = b"first\nsecond\x00\xff"
    r = _cli(cli_exe, "stdin2", stdin=data)
    assert r.stdout == f"RBytes {len(data)}: {_show(data)}|RBytes 0: ".encode()


def test_bio_c10_piped_stdin_delivers_ff_unchanged(cli_exe):
    data = bytes([0xFF, 0x00, 0x0A, 0xC3])
    assert _cli(cli_exe, "stdin", stdin=data).stdout == f"RBytes 4: {_show(data)}".encode()


LIB = """(module bylib)
(import wasi.io (capability stdin))
(import wasi.io (capability stdout :deterministic false))
(def-shell read-in [] -> Command wasi.io.stdin-bytes)
(def-shell write-out [] -> Command (wasi.io.stdout-bytes (bytes-make 1 65)))
"""

CONSOLE_VIA_LIB = """(module p)
(import bylib)
(open bylib)
(import wasi.io (capability stdout :deterministic false))
(def-shell desc [r: Response] -> string
  (match r ((RBytes b) "RBytes") ((RErr e) (string-concat "RErr " e)) ((RNone) "RNone") (_ "other")))
(def-main :mode console
  :init (pair 0 (read-in))
  :step (fn [s: int line: string r: Response]
    (if (= s 0)
        (pair 1 (wasi.io.stdout (string-concat-many ["init=" (desc r) "\\n"])))
        (if (= s 1)
            (pair 2 (write-out))
            (pair 3 (wasi.io.stdout (string-concat-many ["write=" (desc r) "\\n"])))))))
"""

CONSOLE_DIRECT = """(import wasi.io (capability stdin))
(import wasi.io (capability stdout :deterministic false))
(def-shell step [s: int input: string r: Response] -> (int, Command)
  (pair 1 wasi.io.stdin-bytes))
(def-shell done? [s: int] -> bool (>= s 1))
(def-main :mode console :init (pair 0 (wasi.io.stdout "")) :step step :done? done?)
"""


def test_bio_c11_console_byte_stdio_is_a_check_error_in_the_entry_and_rerr_from_a_library(tmp_path):
    direct = tmp_path / "direct"
    direct.mkdir()
    (direct / "p.llmll").write_text(CONSOLE_DIRECT, encoding="utf-8")
    c = _run([*shlex.split(os.environ["LLMLL_BIN"]), "--json", "check", "p.llmll"], cwd=direct)
    assert c.returncode == 1, c.stdout + c.stderr
    assert '"kind":"byte-stdio-console"' in c.stdout, c.stdout
    # The same commands from an imported module: check passes (U3, entry
    # module only), and the runtime backstop publishes RErr for both.
    work = tmp_path / "lib"
    exe = _build(work, {"bylib.llmll": LIB, "p.llmll": CONSOLE_VIA_LIB})
    r = _run_bytes([exe], work, stdin=b"a\nb\nc\n")
    assert r.returncode == 0, (r.stdout, r.stderr)
    lines = [ln for ln in r.stdout.split(b"\n") if ln.startswith((b"init=", b"write="))]
    # The read consumed nothing: the harness still saw lines b and c.
    assert [ln.split(b" ")[0] for ln in lines] == [b"init=RErr", b"write=RErr"], r.stdout
    assert b"wasi.io.stdin-bytes" in lines[0] and b"wasi.io.stdout-bytes" in lines[1], lines
    assert b"A" not in r.stdout, r.stdout


def test_bio_c12_crc32_of_a_file_equals_zlib(cli_exe):
    import zlib
    want = zlib.crc32(TINY_Y4M.read_bytes())
    assert _cli(cli_exe, "crc", str(TINY_Y4M)).stdout == str(want).encode()



# --- S8: the verifier witnesses (fixtures/byte_io_1) and the trust report ----
#
# What a pass here means:
#
# * BIO-V1..V12, V14, V15 (and V16..V18, BYTES-MAKE-ALIAS-1, below): each
#   witness of the step-3 plan's contract plan gets its stated verdict
#   through `llmll --json verify`: the correct body is SAFE and body-faithful;
#   a refuting body whose constraint holds no abstracted result is `refuted`,
#   exit 1, on the named obligation; a
#   refuting body whose constraint holds a partial (abstracted) result falls
#   back with `abstraction:app:<name>`, exit 0, and is not refuted (design
#   risk 4, CALL-RESULT-MARK-1). W-8 is the design's crc-loop as written (the
#   Rev 2a `bytes-length` guard arm) with its off-by-one guard control; W-15
#   is the Rev 2a slice workaround: the index bug sits in a callee that takes
#   the slice as a `bytes` parameter with a length pre, so it is refuted.
#   W-13 (whole-value `=` on `bytes`, edge case 16) has no cell yet: the plan
#   expects `guard:whole-structure-eq`, and the measured outcome is a fallback
#   refused by `var`, so its expected verdict awaits a decision.
# * BIO-T1..T4: `--trust-report --strict-verify` names each of the seven new
#   sealed axioms; a bytes-free program names none of them; the obligation
#   report's effect_summary carries the `stdin` label for
#   `(wasi.io.stdin-bytes)`; `--strict-verified-core` refuses W-2's
#   abstraction fallback and admits its correct body.

FIXTURES = REPO / "scripts" / "tests" / "fixtures" / "byte_io_1"

pytestmark_v = pytest.mark.skipif(
    shutil.which("liquid-fixpoint") is None and shutil.which("fixpoint") is None,
    reason="needs liquid-fixpoint on PATH",
)


def _llmll(args, cwd, timeout=300):
    return _run([*shlex.split(os.environ["LLMLL_BIN"]), *args], cwd=cwd, timeout=timeout)


def _json_line(text):
    doc = None
    for ln in text.splitlines():
        ln = ln.strip()
        if ln.startswith("{") and ln.endswith("}"):
            try:
                doc = json.loads(ln)
            except ValueError:
                pass
    assert doc is not None, text[-3000:]
    return doc


def _verify_fixture(tmp_path, name, *extra):
    """`llmll --json verify` on a private copy (verify writes a sidecar)."""
    d = tmp_path / name
    d.mkdir()
    shutil.copyfile(FIXTURES / f"{name}.llmll", d / "t.llmll")
    p = _llmll(["--json", "verify", *extra, "t.llmll", "-o", "t.fq"], d)
    return p, _json_line(p.stdout)


def _unsafe(doc):
    return [d["message"] for d in doc["diagnostics"] if d.get("kind") == "lh-unsafe"]


def _safe(tmp_path, name, fns):
    p, doc = _verify_fixture(tmp_path, name)
    assert p.returncode == 0, p.stdout + p.stderr
    assert doc["solver_verdict"] == "safe", doc
    for fn in fns:
        assert fn in doc["body_faithful"], doc
    return doc


def _refuted(tmp_path, name, fn, obligation):
    p, doc = _verify_fixture(tmp_path, name)
    assert p.returncode == 1, p.stdout + p.stderr
    assert doc["solver_verdict"] == "refuted", doc
    assert fn in doc["body_faithful"], doc
    assert any(obligation in m for m in _unsafe(doc)), _unsafe(doc)
    return doc


def _abstraction_fallback(tmp_path, name, fn, builtin):
    p, doc = _verify_fixture(tmp_path, name)
    assert p.returncode == 0, p.stdout + p.stderr
    assert doc["solver_verdict"] == "safe", doc
    assert doc["body_fallback_causes"] == {fn: "abstraction-unsafe"}, doc
    assert doc["body_fallback_constructs"] == {fn: [f"abstraction:app:{builtin}"]}, doc
    assert doc["abstraction_fallback"] == {fn: f"abstraction:app:{builtin}"}, doc
    assert _unsafe(doc) == [], doc
    return doc


def _call_pre(callee, caller):
    return f"call-site precondition of '{callee}' not satisfied in '{caller}'"


def _body(fn):
    return f"body verification of '{fn}' failed"


@pytestmark_v
def test_bio_v1_magic16_verifies_and_an_index_past_the_pre_is_refuted(tmp_path):
    _safe(tmp_path, "w01_magic16", ["magic16"])
    _refuted(tmp_path, "w01_magic16_bad", "magic16", _call_pre("bytes-get", "magic16"))


@pytestmark_v
def test_bio_v2_slice_length_verifies_a_bad_slice_end_refutes_a_bad_start_falls_back(tmp_path):
    _safe(tmp_path, "w02_tail_len", ["tail-len"])
    # Body A: the slice call-pre fails before the slice result is in scope.
    _refuted(tmp_path, "w02_tail_len_bad_a", "tail-len", _call_pre("bytes-slice", "tail-len"))
    # Body B: the false post's constraint holds the slice result (risk 4).
    _abstraction_fallback(tmp_path, "w02_tail_len_bad_b", "tail-len", "bytes-slice")


@pytestmark_v
def test_bio_v3_widen_keeps_a_parameter_length_exactly(tmp_path):
    _safe(tmp_path, "w03_widen", ["w8"])
    _refuted(tmp_path, "w03_widen_bad", "w8", _body("w8"))


@pytestmark_v
def test_bio_v4_widen_of_a_let_bound_bytes_set_keeps_the_parameter_length(tmp_path):
    _safe(tmp_path, "w04_widen_let", ["w8-let"])


@pytestmark_v
def test_bio_v5_concat_length_verifies_and_a_wrong_operand_falls_back(tmp_path):
    _safe(tmp_path, "w05_cat_len", ["cat-len"])
    _abstraction_fallback(tmp_path, "w05_cat_len_bad", "cat-len", "bytes-concat")


@pytestmark_v
def test_bio_v6_make_length_is_exact_and_a_value_of_256_is_refuted(tmp_path):
    _safe(tmp_path, "w06_make_len", ["mk-len"])
    _refuted(tmp_path, "w06_make_len_bad", "mk-len", _call_pre("bytes-make", "mk-len"))


# BYTES-MAKE-ALIAS-1 (v0.40.1 hotfix). v0.40.0 reflected `(bytes-make n v)` as
# `result = Map_default(v)`, so two makes with one fill were one SMT term and
# congruence on `bytesLen` forced two lengths on it: the hypotheses were
# inconsistent and any post was proved. W-16 is the professor's witness (it
# returns 8; v0.40.0 called `(= result 1)` SAFE and body-faithful). bytes-make now
# states its length only and is abstracted, so each wrong post falls back with
# `abstraction:app:bytes-make`, exit 0, and the true post `(= result 8)` still
# verifies on the length lemmas. The fill-1 control was refuted on v0.40.0
# (different terms); it now falls back too, because the verdict rule does not
# refute on a constraint holding an abstracted result.
@pytestmark_v
def test_bio_v16_two_makes_of_different_lengths_are_not_one_term(tmp_path):
    _safe(tmp_path, "w16_make_two_len_ok", ["two-makes"])
    _abstraction_fallback(tmp_path, "w16_make_two_len", "two-makes", "bytes-make")
    _abstraction_fallback(tmp_path, "w16_make_two_len_fill1", "two-makes", "bytes-make")


# The same cause through a variable length and through a bytes-set chain rooted
# at each make (v0.40.0: both SAFE, both false).
@pytestmark_v
def test_bio_v17_a_variable_length_make_and_a_set_chain_are_not_one_term(tmp_path):
    _abstraction_fallback(tmp_path, "w17_make_var_len", "v", "bytes-make")
    _abstraction_fallback(tmp_path, "w17_make_set_chain", "s", "bytes-make")


# Audit control: `(bytes-zero)` also reflects as `Map_default(0)`, but only as
# the whole body of a `-> bytes[n]` def, so one constraint holds at most one; a
# caller sees each callee result as a fresh term with its declared length.
# Two such callees of lengths 3 and 5 are refuted, on v0.39.0, v0.40.0 and now.
@pytestmark_v
def test_bio_v18_two_bytes_zero_callees_of_different_lengths_are_refuted(tmp_path):
    _refuted(tmp_path, "w18_zero_two_callees", "use", _body("use"))


@pytestmark_v
def test_bio_v7_byte_loop_with_a_let_bound_guard_and_its_descent_control(tmp_path):
    _safe(tmp_path, "w07_sum_bytes", ["sum-bytes"])
    _refuted(tmp_path, "w07_sum_bytes_bad", "sum-bytes", "descent-condition of 'sum-bytes' not verified")


@pytestmark_v
def test_bio_v8_the_design_crc_loop_verifies_as_written_and_its_controls_refute(tmp_path):
    doc = _safe(tmp_path, "w08_crc_loop", ["crc-loop"])
    # crc-byte keeps its contract and falls back on bit-xor; crc-loop rests on it.
    assert set(doc["body_fallback"]) == {"crc-bits", "crc-byte"}, doc
    # Rev 2a control: guard (= i (+ (bytes-length buf) 1)) reads at i = len.
    _refuted(tmp_path, "w08_crc_loop_bad_guard", "crc-loop", _call_pre("bytes-get", "crc-loop"))
    _refuted(tmp_path, "w08_crc_loop_bad_index", "crc-loop", _call_pre("bytes-get", "crc-loop"))


@pytestmark_v
def test_bio_v9_strict_core_bytes_def_across_modules(tmp_path):
    good = tmp_path / "good"
    shutil.copytree(FIXTURES / "w9_core", good)
    for m, fn in [("bio_core", "bget0"), ("bio_use", "first-byte")]:  # leaf first
        p = _llmll(["--json", "verify", "--strict-verified-core", f"{m}.llmll", "-o", f"{m}.fq"], good)
        assert p.returncode == 0, p.stdout + p.stderr
        assert _json_line(p.stdout)["body_faithful"] == [fn]
    bad = tmp_path / "bad"
    shutil.copytree(FIXTURES / "w9_core_bad", bad)
    p = _llmll(["--json", "verify", "--strict-verified-core", "bio_core.llmll", "-o", "c.fq"], bad)
    assert p.returncode == 1, p.stdout + p.stderr
    assert any(_call_pre("bytes-get", "bget0") in m for m in _unsafe(_json_line(p.stdout)))
    p = _llmll(["--json", "verify", "--strict-verified-core", "bio_use.llmll", "-o", "u.fq"], bad)
    assert p.returncode == 1, p.stdout + p.stderr
    assert "callee 'bget0' is not body-faithful" in p.stdout, p.stdout


@pytestmark_v
def test_bio_v10_a_response_match_with_a_wildcard_stays_body_faithful(tmp_path):
    doc = _safe(tmp_path, "w10_resp_wildcard", ["code-of"])
    assert doc["body_fallback"] == [], doc


@pytestmark_v
def test_bio_v11_a_match_that_binds_the_rbytes_payload_falls_back(tmp_path):
    p, doc = _verify_fixture(tmp_path, "w11_rbytes_arm")
    assert p.returncode == 0, p.stdout + p.stderr
    assert doc["body_fallback_causes"] == {"len-of": "body-outside-fragment"}, doc
    assert doc["body_fallback_constructs"] == {"len-of": ["match-payload-sort"]}, doc


@pytestmark_v
def test_bio_v12_reading_at_the_length_refutes_on_a_parameter_and_falls_back_on_a_slice(tmp_path):
    _refuted(tmp_path, "w12_at_len", "at-len", _call_pre("bytes-get", "at-len"))
    _abstraction_fallback(tmp_path, "w12_at_len_slice", "at-len-slice", "bytes-slice")


@pytestmark_v
def test_bio_v14_bytes_from_list_in_a_body_falls_back(tmp_path):
    p, doc = _verify_fixture(tmp_path, "w14_from_list")
    assert p.returncode == 0, p.stdout + p.stderr
    assert doc["body_fallback_causes"] == {"fl": "body-outside-fragment"}, doc
    assert doc["body_fallback_constructs"] == {"fl": ["app:bytes-from-list"]}, doc
    assert any("Refused by: app:bytes-from-list" in d["message"] for d in doc["diagnostics"]), doc


@pytestmark_v
def test_bio_v15_an_index_bug_behind_a_slice_is_refuted_in_the_callee(tmp_path):
    """The documented workaround for CALL-RESULT-MARK-1 (Rev 2a item 6)."""
    _safe(tmp_path, "w15_slice_callee", ["get2", "use"])
    _refuted(tmp_path, "w15_slice_callee_bad", "get3", _call_pre("bytes-get", "get3"))


SEVEN = """(def-shell mk-len [n: int] -> int
  (pre (>= n 0))
  (post (= result n))
  (bytes-length (bytes-make n 7)))
(def-shell w8 [k: bytes[8]] -> int
  (post (= result 8))
  (bytes-length (bytes-widen k)))
(def-shell tail-len [b: bytes s: int] -> int
  (pre (and (>= s 0) (<= s (bytes-length b))))
  (post (= result (- (bytes-length b) s)))
  (bytes-length (bytes-slice b s (bytes-length b))))
(def-shell cat-len [a: bytes b: bytes] -> int
  (post (= result (+ (bytes-length a) (bytes-length b))))
  (bytes-length (bytes-concat a b)))
(def-shell many-len [xs: list[bytes]] -> int
  (post (>= result 0))
  (bytes-length (bytes-concat-many xs)))
(def-shell list-len [a: bytes] -> int
  (post (= result (bytes-length a)))
  (list-length (bytes-to-list a)))
(def-shell str-len [s: string] -> int
  (post (>= result (string-length s)))
  (bytes-length (bytes-from-string s)))
"""

SEVEN_AXIOMS = {
    # BYTES-MAKE-ALIAS-1: the length only. The v0.40.0 content reflection
    # `result = (Map_default 7)` is gone (see BIO-V16).
    "mk-len": ("bytes-make", "((bytesLen result) = n)"),
    "w8": ("bytes-widen", "(result = k)"),
    "tail-len": ("bytes-slice", "((bytesLen result) = ((bytesLen b) - s))"),
    "cat-len": ("bytes-concat", "((bytesLen result) = ((bytesLen a) + (bytesLen b)))"),
    "many-len": ("bytes-concat-many", "((bytesLen result) >= 0)"),
    "list-len": ("bytes-to-list", "((listLen result) = (bytesLen a))"),
    "str-len": ("bytes-from-string", "((strLen s) <= (bytesLen result)) && ((bytesLen result) <= (4 * (strLen s)))"),
}


def _trust_strict(tmp_path, src, json_out=False):
    (tmp_path / "t.llmll").write_text(src, encoding="utf-8")
    p = _llmll([*(["--json"] if json_out else []), "verify", "t.llmll", "--trust-report", "--strict-verify",
                "-o", "t.fq"], tmp_path)
    assert p.returncode == 0, p.stdout[-3000:] + p.stderr[-2000:]
    return p.stdout


@pytestmark_v
def test_bio_t1_the_trust_report_names_each_of_the_seven_new_sealed_axioms(tmp_path):
    out = _trust_strict(tmp_path, SEVEN)
    for builtin, pred in SEVEN_AXIOMS.values():
        assert f"≈ assumes {builtin} {pred} [codegen-determined; stamp: codegen_semantics_version]" in out, \
            (builtin, out[-4000:])
    doc = _json_line(_trust_strict(tmp_path, SEVEN, json_out=True))["trust_report"]
    rows = {e["name"]: e.get("builtin_axioms") or [] for e in doc["entries"]}
    for fn, (builtin, pred) in SEVEN_AXIOMS.items():
        assert [(r["builtin"], r["predicate"], r["category"]) for r in rows[fn]] == \
            [(builtin, pred, "codegen-determined")], (fn, rows[fn])


@pytestmark_v
def test_bio_t2_a_bytes_free_program_names_none_of_the_seven(tmp_path):
    out = _trust_strict(tmp_path, "(def-shell add1 [n: int] -> int (post (> result n)) (+ n 1))\n")
    for builtin, _ in SEVEN_AXIOMS.values():
        assert f"assumes {builtin}" not in out, out[-3000:]
    assert "codegen_semantics_version" not in out, out[-3000:]


@pytestmark_v
def test_bio_t3_effect_summary_reports_stdin_for_stdin_bytes(tmp_path):
    (tmp_path / "t.llmll").write_text("(import wasi.io (capability stdin))\n"
                                      "(def-shell read-in [] -> Command (wasi.io.stdin-bytes))\n", encoding="utf-8")
    p = _llmll(["verify", "t.llmll", "--obligation-report", "-o", "t.fq"], tmp_path)
    assert p.returncode == 0, p.stdout + p.stderr
    rep = next(json.loads(ln) for ln in p.stdout.splitlines() if ln.startswith("{") and "effect_summary" in ln)
    assert rep["effect_summary"] == [{"effects": ["stdin"], "function": "read-in"}], rep
    assert rep["schema_version"] == "0.12.5", rep


@pytestmark_v
def test_bio_t4_strict_core_refuses_the_slice_fallback_and_admits_the_correct_body(tmp_path):
    for name, rc in [("w02_tail_len", 0), ("w02_tail_len_bad_b", 1)]:
        d = tmp_path / name
        d.mkdir()
        (d / "t.llmll").write_text((FIXTURES / f"{name}.llmll").read_text().replace("(def-shell ", "(def "),
                                   encoding="utf-8")
        p = _llmll(["verify", "--strict-verified-core", "t.llmll", "-o", "t.fq"], d)
        assert p.returncode == rc, (name, p.stdout + p.stderr)
        if rc:
            assert ("--strict-verified-core: 1 function(s) fell back from body-faithful verification: "
                    "tail-len (abstraction-unsafe, abstraction:app:bytes-slice)") in p.stdout + p.stderr, p.stdout + p.stderr
