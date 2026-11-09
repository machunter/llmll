"""BITWISE-1 + CHAR-CODE-1: bit operations and character codes.

docs/design/byte-io-proposal.md Rev 2, Parts 3 and 5, edge cases 12-15, 19, 20
and 23. The seven builtins are pure and each carries a pre. Three bit forms
reflect exactly; the character builtins reflect through a UF or a fresh string,
in bodies only.

What a pass here means:

* The fixtures in fixtures/bitwise_char: each correct body verifies and each
  wrong body gets the stated verdict. rotl32-7 is the linear rotate that the
  whole exact-form design rests on.
* The measured edge cases: E12, E13 refute at the call; E14, E15 (254), E19, E20
  fall back with `app:<name>`; E23 falls back with
  `abstraction:app:string-code-at` and is not refuted.
* D2: a guard use carries its call-pre. D3: a clause read of a possibly negative
  operand is `ill-defined`. A built program stops with "Postcondition of ... is
  undefined" on a bit-or of a negative.
* A parameter named `bit-and` is the parameter, not the builtin (FN-SHADOW-1).
* A `check` property pins string-compare agreement on one-character strings.
* 2^64 masks and 2^4096 shift numerals pass through fixpoint and z3.
* The built program's output equals Python's &, |, ^, <<, >>, ord and chr.
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

REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURES = REPO_ROOT / "scripts" / "tests" / "fixtures" / "bitwise_char"

pytestmark = [
    pytest.mark.skipif(not os.environ.get("LLMLL_BIN"), reason="set LLMLL_BIN to a built llmll"),
    pytest.mark.skipif(
        shutil.which("liquid-fixpoint") is None and shutil.which("fixpoint") is None,
        reason="needs liquid-fixpoint on PATH",
    ),
]

BUILD_TIMEOUT_S = 600


def _kill_tree(pid):
    """SIGKILL a process and every descendant. subprocess.run's timeout kills only
    the direct child, which leaves llmll's ghc, stack and z3 running for hours."""
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


def _run(cmd, cwd=None, stdin=None, timeout=120):
    proc = subprocess.Popen(cmd, cwd=None if cwd is None else str(cwd), text=True,
                            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        out, err = proc.communicate(stdin, timeout=timeout)
    except subprocess.TimeoutExpired:
        _kill_tree(proc.pid)
        proc.communicate()
        raise
    return subprocess.CompletedProcess(cmd, proc.returncode, out, err)


def _llmll(args, cwd, timeout=120):
    return _run([*shlex.split(os.environ["LLMLL_BIN"]), *args], cwd=cwd, timeout=timeout)


def _verify_src(tmp_path, src, *args):
    (tmp_path / "t.llmll").write_text(src)
    p = _llmll(["--json", "verify", *args, "t.llmll"], tmp_path)
    return p, json.loads(p.stdout)


def _verify_fixture(tmp_path, name):
    return _verify_src(tmp_path, (FIXTURES / f"{name}.llmll").read_text())


def _kinds(doc):
    return [d.get("kind") for d in doc.get("diagnostics", [])]


def _messages(doc, kind):
    return [d["message"] for d in doc.get("diagnostics", []) if d.get("kind") == kind]


def _refuted_body(doc, fn):
    return any(f"body verification of '{fn}' failed" in m for m in _messages(doc, "lh-unsafe"))


def _refuted_call_pre(doc, callee):
    return any(f"call-site precondition of '{callee}' not satisfied" in m for m in _messages(doc, "lh-unsafe"))


def _falls_back(doc, fn, label):
    return (fn in doc["body_fallback_causes"]
            and any(f"Refused by: {label}" in m for m in _messages(doc, "body-fallback-cause")))


@pytest.mark.parametrize("name,fn", [("low_nibble", "low-nibble"), ("hi_byte", "hi-byte"),
                                     ("rotl32_7", "rotl32-7"), ("first_code", "first-code")])
def test_correct_body_verifies(tmp_path, name, fn):
    p, doc = _verify_fixture(tmp_path, name)
    assert p.returncode == 0, p.stdout + p.stderr
    assert doc["body_faithful"] == [fn]
    assert doc["body_fallback_causes"] == {}


@pytest.mark.parametrize("name,fn", [("low_nibble_bad", "low-nibble"), ("hi_byte_bad", "hi-byte"),
                                     ("rotl32_7_bad", "rotl32-7")])
def test_wrong_body_is_refuted(tmp_path, name, fn):
    p, doc = _verify_fixture(tmp_path, name)
    assert p.returncode == 1, p.stdout + p.stderr
    assert _refuted_body(doc, fn), doc["diagnostics"]


def test_first_code_with_no_pre_refutes_the_call_pre(tmp_path):
    p, doc = _verify_fixture(tmp_path, "first_code_bad")
    assert p.returncode == 1, p.stdout + p.stderr
    assert _refuted_call_pre(doc, "string-code-at"), doc["diagnostics"]


def test_e23_a_code_falls_back_not_refuted(tmp_path):
    """The post is true; the VC holds only strCode's range, so UNSAFE is no disproof."""
    p, doc = _verify_fixture(tmp_path, "a_code")
    assert p.returncode == 0, p.stdout + p.stderr
    assert doc["abstraction_fallback"] == {"a-code": "abstraction:app:string-code-at"}
    assert doc["body_fallback_causes"] == {"a-code": "abstraction-unsafe"}
    assert "lh-unsafe" not in _kinds(doc)
    # A single call: the hint must not offer to bind "two calls".
    msgs = _messages(doc, "body-fallback-cause")
    assert any("The verifier knows only part of what 'string-code-at' returns" in m for m in msgs), msgs
    assert not any("bind one call" in m or "two calls" in m for m in msgs), msgs
    sidecar = json.loads((tmp_path / "t.llmll.verified.json").read_text())
    assert sidecar["a-code"]["post"]["display_level"]["level"] == "asserted"


def test_e12_empty_string_refutes_the_call_pre(tmp_path):
    p, doc = _verify_src(tmp_path, '(def-shell f [] -> int (post (>= result 0)) (string-code-at "" 0))\n')
    assert p.returncode == 1, p.stdout + p.stderr
    assert _refuted_call_pre(doc, "string-code-at")


def test_e13_surrogate_refutes_the_call_pre(tmp_path):
    p, doc = _verify_src(tmp_path, '(def-shell f [] -> string (post (= (string-length result) 1)) (string-from-code 55296))\n')
    assert p.returncode == 1, p.stdout + p.stderr
    assert _refuted_call_pre(doc, "string-from-code")


@pytest.mark.parametrize("label,body,refused", [
    # E14: the plan's recognizer refuses a negative count, so this is a fallback
    # and the runtime assertion, not the call-pre refutation the design's text names.
    ("e14", "(bit-shl x -1)", "app:bit-shl"),
    ("e15_254", "(bit-and x 254)", "app:bit-and"),
    ("e19", "(bit-and x -1)", "app:bit-and"),
    ("e20", "(bit-shl x 5000)", "app:bit-shl"),
    ("shift_4097", "(bit-shr x 4097)", "app:bit-shr"),
    ("let_const", "(let [(c 3)] (bit-shl x c))", "app:bit-shl"),
    ("or", "(bit-or x 1)", "app:bit-or"),
    ("xor", "(bit-xor x 1)", "app:bit-xor"),
])
def test_inexact_form_falls_back_with_its_label(tmp_path, label, body, refused):
    p, doc = _verify_src(tmp_path, f"(def-shell f [x: int] -> int (pre (>= x 0)) (post (>= result 0)) {body})\n")
    assert p.returncode == 0, p.stdout + p.stderr
    assert doc["body_fallback_causes"] == {"f": "body-outside-fragment"}
    assert _falls_back(doc, "f", refused), doc["diagnostics"]


def test_e15_255_stays_body_faithful(tmp_path):
    p, doc = _verify_src(tmp_path, "(def-shell f [x: int] -> int (pre (>= x 0)) "
                                   "(post (and (>= result 0) (<= result 255))) (bit-and x 255))\n")
    assert p.returncode == 0, p.stdout + p.stderr
    assert doc["body_faithful"] == ["f"]


def test_d2_guard_with_no_pre_refutes_the_call_pre(tmp_path):
    p, doc = _verify_src(tmp_path, "(def-shell f [x: int] -> int (post (>= result 0)) (if (= (bit-and x 1) 0) 0 1))\n")
    assert p.returncode == 1, p.stdout + p.stderr
    assert _refuted_call_pre(doc, "bit-and"), doc["diagnostics"]


def test_d2_guard_under_its_pre_verifies(tmp_path):
    p, doc = _verify_src(tmp_path, "(def-shell f [x: int] -> int (pre (>= x 0)) (post (>= result 0)) "
                                   "(if (= (bit-and x 1) 0) 0 1))\n")
    assert p.returncode == 0, p.stdout + p.stderr
    assert doc["body_faithful"] == ["f"]


def test_d3_clause_read_with_no_pre_is_ill_defined(tmp_path):
    p, doc = _verify_src(tmp_path, "(def-shell f [x: int] -> int (post (= result (bit-shl x 3))) (* x 8))\n")
    assert p.returncode == 1, p.stdout + p.stderr
    assert doc["ill_defined"] == ["f"]
    assert any("(bit-shl x 3) needs (>= x 0)" in m for m in _messages(doc, "clause-ill-defined"))


def test_d3_clause_read_under_its_pre_verifies(tmp_path):
    p, doc = _verify_src(tmp_path, "(def-shell f [x: int] -> int (pre (>= x 0)) (post (= result (bit-shl x 3))) (* x 8))\n")
    assert p.returncode == 0, p.stdout + p.stderr
    assert doc["body_faithful"] == ["f"]


def test_d4_character_builtin_in_a_clause_falls_back_with_no_obligation(tmp_path):
    p, doc = _verify_src(tmp_path, "(def-shell f [s: string] -> int (pre (> (string-length s) 0)) "
                                   "(post (= result (string-code-at s 0))) (string-code-at s 0))\n")
    assert p.returncode == 0, p.stdout + p.stderr
    assert doc["body_fallback_causes"] == {"f": "contract-post-outside-fragment"}
    assert _falls_back(doc, "f", "app:string-code-at"), doc["diagnostics"]
    assert "ill_defined" not in doc


def test_parameter_named_bit_and_is_the_parameter(tmp_path):
    """The post holds of the builtin and not of an arbitrary parameter. Reading the
    call as the builtin would prove it; the built program calls the parameter."""
    p, doc = _verify_src(tmp_path, "(def-shell f [bit-and: (fn [int int] -> int) x: int] -> int "
                                   "(pre (>= x 0)) (post (= result (mod x 16))) (bit-and x 15))\n")
    assert p.returncode == 1, p.stdout + p.stderr
    assert _refuted_body(doc, "f"), doc["diagnostics"]


def test_top_level_redefinition_is_refused(tmp_path):
    (tmp_path / "t.llmll").write_text("(def-shell bit-and [a: int b: int] -> int (+ a b))\n")
    p = _llmll(["check", "t.llmll"], tmp_path)
    assert p.returncode == 1
    assert "'bit-and' is a builtin and cannot be redefined" in p.stdout + p.stderr


@pytest.mark.parametrize("label,src", [
    ("mask_2_64", "(def-shell f [x: int] -> int (pre (>= x 0)) "
                  "(post (and (>= result 0) (<= result 18446744073709551615))) (bit-and x 18446744073709551615))\n"),
    ("shr_4096", "(def-shell f [x: int] -> int (pre (>= x 0)) (post (= result 0)) (bit-shr (bit-and x 255) 4096))\n"),
    ("shl_4096", "(def-shell f [x: int] -> int (pre (>= x 0)) (post (>= result x)) (bit-shl x 4096))\n"),
])
def test_big_numerals_pass_through_the_solver(tmp_path, label, src):
    p, doc = _verify_src(tmp_path, src)
    assert p.returncode == 0, p.stdout + p.stderr
    assert doc["body_faithful"] == ["f"]
    assert doc["body_fallback_causes"] == {}


def test_trust_report_discloses_character_axioms_not_exact_forms(tmp_path):
    p, doc = _verify_src(tmp_path, "(def-shell f [s: string x: int] -> int (pre (and (> (string-length s) 0) (>= x 0))) "
                                   "(post (>= result 0)) (+ (string-code-at s 0) (bit-shr x 3)))\n", "--trust-report")
    assert p.returncode == 0, p.stdout + p.stderr
    tr = doc["trust_report"]
    tr = json.loads(tr) if isinstance(tr, str) else tr
    assert "string-code-at" in json.dumps(tr)
    assert '"builtin": "bit-shr"' not in json.dumps(tr)


def _build_and_run(tmp_path, src, stdin="", timeout=30):
    (tmp_path / "p.llmll").write_text(src)
    b = _llmll(["build", "p.llmll", "-o", str(tmp_path / "out")], tmp_path, BUILD_TIMEOUT_S)
    assert b.returncode == 0, b.stdout[-1500:] + b.stderr[-1500:]
    exes = glob.glob(str(tmp_path / "out" / ".stack-work" / "install" / "*" / "*" / "*" / "bin" / "*"))
    assert len(exes) == 1, exes
    return _run([exes[0]], cwd=tmp_path, stdin=stdin, timeout=timeout)


def _console(body, defs=""):
    """A console program that prints `body`, a string expression, then reads EOF."""
    return f"""(import wasi.io (capability stdout :deterministic false))
{defs}(def-main :mode console
  :init (pair 0 (wasi.io.stdout {body}))
  :step (fn [s: int line: string _r: Response] (pair s (wasi.io.stdout ""))))
"""


def test_end_to_end_agrees_with_python(tmp_path):
    a, b = 2 ** 70 + 12345, 2 ** 66 + 999
    pairs = [("and", a, b, a & b), ("or", a, b, a | b), ("xor", a, b, a ^ b),
             ("shl", a, 9, a << 9), ("shr", a, 9, a >> 9), ("shl", 3, 0, 3), ("shr", 3, 100, 0)]
    text = "a\u00e9\u03bb\U0001F600"
    items = ([f"(ln (bit-{op} {x} {y}))" for op, x, y, _ in pairs]
             + [f'(ln (string-code-at "{text}" {i}))' for i in range(len(text))]
             + [f'(string-concat (string-from-code {ord(c)}) "\\n")' for c in text])
    # One short list per helper: GHC's time on one string-concat-many literal grows
    # steeply with its length (v0.37.0: 10 elements 21 s, 20 elements over 280 s).
    chunks = [items[i:i + 5] for i in range(0, len(items), 5)]
    defs = '(def-shell ln [n: int] -> string (string-concat (int-to-string n) "\\n"))\n'
    defs += "".join(f'(def-shell p{i} [u: int] -> string (string-concat-many [{" ".join(c)}]))\n'
                    for i, c in enumerate(chunks))
    top = " ".join(f"(p{i} 0)" for i in range(len(chunks)))
    r = _build_and_run(tmp_path, _console(f"(string-concat-many [{top}])", defs))
    assert r.returncode == 0, r.stdout + r.stderr
    want = [str(v) for *_, v in pairs] + [str(ord(c)) for c in text] + list(text)
    assert r.stdout.split("\n")[:len(want)] == want


@pytest.mark.parametrize("label,expr,message", [
    ("surrogate", "(string-from-code 55296)", "string-from-code: pre-condition failed"),
    ("oob", '(int-to-string (string-code-at "abc" 18446744073709551616))', "string-code-at: pre-condition failed"),
    ("negative", "(int-to-string (bit-or 0 (- 0 1)))", "bit-or: pre-condition failed"),
    ("shl_huge", "(int-to-string (bit-shl 1 18446744073709551616))", "bit-shl: shift"),
])
def test_built_program_stops_with_the_named_error(tmp_path, label, expr, message):
    r = _build_and_run(tmp_path, _console(expr))
    assert r.returncode != 0
    assert message in r.stdout + r.stderr


def test_built_clause_reading_bit_or_of_a_negative_stops(tmp_path):
    defs = """(def-shell f [x: int] -> int
  (post (>= (bit-or result 1) 0))
  (- x 5))
"""
    src = _console("(int-to-string (f 1))", defs)
    r = _build_and_run(tmp_path, src)
    assert r.returncode != 0
    assert "Postcondition of f is undefined" in r.stdout + r.stderr
    assert "bit-or" in r.stdout + r.stderr


def test_check_property_pins_string_compare_agreement(tmp_path):
    (tmp_path / "t.llmll").write_text("""(module t
  (def-shell one [c: int] -> string
    (string-from-code (mod c 55296)))
  (def-shell code [c: int] -> int
    (string-code-at (one c) 0))
  (check "string-compare agrees with the codes on one-character strings"
    (for-all [a: int b: int]
      (= (string-compare (one a) (one b)) (compare (code a) (code b))))))
""")
    p = _llmll(["test", "t.llmll"], tmp_path, 300)
    out = p.stdout + p.stderr
    assert p.returncode == 0, out
    assert "Passed:  1" in out
    assert "Failed:  0" in out
