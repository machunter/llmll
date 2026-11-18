"""CALL-RESULT-MARK-1 and ABSTRACTION-LEN-EXACT-1: the clause-1 cone of
influence, what a refuted function cites, and the exact length of a partial
result (docs/design/byte-io-proposal.md, Amendment Rev 2b, items 2-8).

What a pass here means:

* CRM-V1..V13b: each witness in fixtures/call_result_mark_1 gets its commit-1
  verdict. A refuted cell asserts exit 1, `solver_verdict` refuted and the
  named `lh-unsafe` message: the failing check does not depend on a partially
  known result, so it is a disproof (C1, B1, C3). A fallback cell asserts exit
  0, the `abstraction_fallback` construct and no `lh-unsafe`. N1, P-LG2 and
  H1-G are correct functions, so a refutation there would be false.
* CRM-V7, V8, V11 and V14..V23 (ABSTRACTION-LEN-EXACT-1): the length of a
  slice, concat, make, set or string-from-code result is exact when its
  equation reads no partially known value, so N3, N4, LX-P1, MK-P, SET, E11,
  E11-R and G1-P are refuted. LX-N1, MK-N and E11-D read a length from slice
  content and must stay fallbacks; LX-N2 (bytes-concat-many) and G1 (a
  let-bound index read twice, the stated precision gap) stay fallbacks too.
  V13b is the original H1 shape: a real modular refutation in the then-branch,
  with the H1 sites on the else path still marked `lh-may-fail`.
* CRM-H1, H2: a refuted function cites only its unmarked failing check; the
  marked one is a `lh-may-fail` warning (H4), and `verify_json_version` is
  1.3.0.
* CRM-S1: `--strict-verified-core` names the refutation, not the fallback.
* RT-1..RT-6: a built program on each counterexample input stops with the named
  pre-condition error, so each refutation is a real run-time failure.
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

REPO = Path(__file__).resolve().parents[2]
FIXTURES = REPO / "scripts" / "tests" / "fixtures" / "call_result_mark_1"
BUILD_TIMEOUT_S = 900

pytestmark = [
    pytest.mark.skipif(not os.environ.get("LLMLL_BIN"), reason="set LLMLL_BIN to a built llmll"),
]

needs_solver = pytest.mark.skipif(
    shutil.which("liquid-fixpoint") is None and shutil.which("fixpoint") is None,
    reason="needs liquid-fixpoint on PATH",
)
needs_stack = pytest.mark.skipif(shutil.which("stack") is None, reason="llmll build needs stack on PATH")


def _kill_tree(pid):
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


def _run(cmd, cwd, stdin="", timeout=300):
    proc = subprocess.Popen(cmd, cwd=str(cwd), text=True, errors="replace",
                            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        out, err = proc.communicate(stdin, timeout=timeout)
    except subprocess.TimeoutExpired:
        _kill_tree(proc.pid)
        proc.communicate()
        raise
    return subprocess.CompletedProcess(cmd, proc.returncode, out, err)


def _llmll(args, cwd, timeout=300):
    return _run([*shlex.split(os.environ["LLMLL_BIN"]), *args], cwd, timeout=timeout)


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


def _copy(tmp_path, name):
    d = tmp_path / name
    d.mkdir()
    shutil.copyfile(FIXTURES / f"{name}.llmll", d / "t.llmll")
    return d


def _verify(tmp_path, name, *extra):
    """`llmll --json verify` on a private copy (verify writes a sidecar)."""
    d = _copy(tmp_path, name)
    p = _llmll(["--json", "verify", *extra, "t.llmll", "-o", "t.fq"], d)
    return p, _json_line(p.stdout)


def _kind(doc, kind):
    return [d for d in doc["diagnostics"] if d.get("kind") == kind]


def _call_pre(callee, caller):
    return f"call-site precondition of '{callee}' not satisfied in '{caller}'"


REFUTED = [
    ("V1", "c1_bad", "two-codes", _call_pre("string-code-at", "two-codes")),
    ("V3", "b1_bad", "slice-get", _call_pre("bytes-get", "slice-get")),
    ("V4", "c3_strfromcode", "one-char", _call_pre("string-code-at", "one-char")),
    ("V7", "n3_len_let", "via-len", _call_pre("bytes-get", "via-len")),
    ("V8", "n4_slice_index", "row-at", _call_pre("bytes-get", "row-at")),
    ("V11", "lx_p1", "one-char-bad", _call_pre("string-code-at", "one-char-bad")),
    ("V16", "mk_at_len", "mk-at-len", _call_pre("bytes-get", "mk-at-len")),
    ("V18", "set_at_len", "set-at", _call_pre("bytes-get", "set-at")),
    ("V19", "e11_cat", "cat-at", _call_pre("bytes-get", "cat-at")),
    ("V20", "e11_cat_rev", "cat-at", _call_pre("bytes-get", "cat-at")),
    ("V23", "g1_two_reads_param", "two-reads", _call_pre("bytes-get", "two-reads")),
]

FALLBACK = [
    ("V5", "n1_spurious", "first-agrees", "bytes-slice"),
    ("V6", "n2_content_index", "via-content", "bytes-slice"),
    ("V9", "c2_guard", "guarded", "string-code-at"),
    ("V10", "a_attr", "h8", "g"),
    ("V12", "p_letguard2", "never-differs", "bytes-slice"),
    ("V13", "h1_g", "h1", "bytes-slice"),
    ("V14", "lx_n1", "dep-len", "bytes-slice"),
    ("V15", "lx_n2", "many-len", "bytes-concat-many"),
    ("V17", "mk_dep_len", "dep-make", "bytes-make"),
    ("V21", "e11_dep", "cat-dep", "bytes-slice"),
    ("V22", "g1_two_reads", "two-reads", "bytes-slice"),
]


@needs_solver
@pytest.mark.parametrize("cell,name,fn,message", REFUTED, ids=[c[0] for c in REFUTED])
def test_crm_v_refuted(tmp_path, cell, name, fn, message):
    p, doc = _verify(tmp_path, name)
    assert p.returncode == 1, p.stdout + p.stderr
    assert doc["solver_verdict"] == "refuted", doc
    assert fn in doc["body_faithful"], doc
    assert any(message in d["message"] for d in _kind(doc, "lh-unsafe")), doc["diagnostics"]


@needs_solver
def test_crm_v2_correct_twin_is_safe(tmp_path):
    p, doc = _verify(tmp_path, "c1_ok")
    assert p.returncode == 0, p.stdout + p.stderr
    assert doc["solver_verdict"] == "safe", doc
    assert "two-codes" in doc["body_faithful"], doc


@needs_solver
@pytest.mark.parametrize("cell,name,fn,callee", FALLBACK, ids=[c[0] for c in FALLBACK])
def test_crm_v_fallback(tmp_path, cell, name, fn, callee):
    p, doc = _verify(tmp_path, name)
    assert p.returncode == 0, p.stdout + p.stderr
    assert doc["solver_verdict"] == "safe", doc
    assert doc["abstraction_fallback"] == {fn: f"abstraction:app:{callee}"}, doc
    assert _kind(doc, "lh-unsafe") == [], doc["diagnostics"]


@needs_solver
def test_crm_v13b_h1_original_is_a_modular_refutation(tmp_path):
    """g's post says nothing about its result, so the then-branch fails on its
    own (exit 1). The H1 sites on the else path stay marked."""
    p, doc = _verify(tmp_path, "h1_g_modular")
    assert p.returncode == 1, p.stdout + p.stderr
    assert doc["solver_verdict"] == "refuted", doc
    errs = _kind(doc, "lh-unsafe")
    assert [d["message"] for d in errs] == [
        "body verification of 'h1' failed (then-branch does not satisfy postcondition) (constraint #1)"], errs
    may = _kind(doc, "lh-may-fail")
    assert len(may) == 2, may
    assert all(d["severity"] == "warning" for d in may), may
    assert any("precondition of 'g' may not hold in 'h1'" in d["message"] for d in may), may
    assert any("precondition of 'bytes-get' may not hold in 'h1'" in d["message"] for d in may), may


@needs_solver
def test_crm_h1_refuted_function_cites_only_the_unmarked_check(tmp_path):
    p, doc = _verify(tmp_path, "h4_cite", "--obligation-report")
    assert p.returncode == 1, p.stdout + p.stderr
    assert doc["verify_json_version"] == "1.3.0"
    assert doc["solver_verdict"] == "refuted", doc
    errs = [d for d in doc["diagnostics"] if d.get("severity") == "error"]
    assert [d["kind"] for d in errs] == ["lh-unsafe"], doc["diagnostics"]
    assert errs[0]["message"] == (_call_pre("string-code-at", "cite")
                                  + " — caller does not prove callee's precondition (constraint #3)")
    may = _kind(doc, "lh-may-fail")
    assert len(may) == 1 and may[0]["severity"] == "warning", doc["diagnostics"]
    assert may[0]["message"] == (
        "call-site precondition of 'string-code-at' may not hold in 'cite': the counterexample uses a "
        "value the verifier knows only in part (abstraction:app:string-code-at), so no run may reach it "
        "(constraint #4)")
    assert doc["obligation_report"]["summary"]["refuted"] == 1, doc["obligation_report"]["summary"]


@needs_solver
def test_crm_h2_text_prints_one_error_and_one_warning(tmp_path):
    d = _copy(tmp_path, "h4_cite")
    p = _llmll(["verify", "t.llmll", "-o", "t.fq"], d)
    assert p.returncode == 1, p.stdout + p.stderr
    lines = (p.stdout + p.stderr).splitlines()
    assert len([ln for ln in lines if ln.startswith("error: ")]) == 1, lines
    warns = [ln for ln in lines if ln.startswith("warning: ")]
    assert len(warns) == 1 and "may not hold" in warns[0], lines


@needs_solver
def test_crm_s1_strict_core_names_the_refutation(tmp_path):
    d = _copy(tmp_path, "c1_bad")
    p = _llmll(["verify", "--strict-verified-core", "t.llmll", "-o", "t.fq"], d)
    out = p.stdout + p.stderr
    assert p.returncode == 1, out
    assert "--strict-verified-core: refuted: two-codes" in out, out
    assert "fell back" not in out, out


# --- run-time cells ----------------------------------------------------------

def _console(defs, body):
    return f"""(import wasi.io (capability stdout :deterministic false))
{defs}
(def-main :mode console
  :init (pair 0 (wasi.io.stdout {body}))
  :step (fn [s: int line: string _r: Response] (pair s (wasi.io.stdout ""))))
"""


def _build_and_run(work, src, timeout=60):
    work.mkdir(parents=True, exist_ok=True)
    (work / "p.llmll").write_text(src, encoding="utf-8")
    b = _llmll(["build", "p.llmll", "-o", str(work / "out")], work, timeout=BUILD_TIMEOUT_S)
    assert b.returncode == 0, b.stdout[-2000:] + b.stderr[-2000:]
    exes = glob.glob(str(work / "out" / ".stack-work" / "install" / "*" / "*" / "*" / "bin" / "*"))
    assert len(exes) == 1, exes
    return _run([exes[0]], work, timeout=timeout)


def _defs(name):
    return "\n".join(ln for ln in (FIXTURES / f"{name}.llmll").read_text().splitlines()
                     if not ln.startswith(";;"))


RUNTIME = [
    ("RT-1", "c1_bad", '(int-to-string (two-codes "a"))',
     "string-code-at: pre-condition failed: index 5 out of bounds for a string of length 1"),
    ("RT-2", "b1_bad", "(int-to-string (slice-get (bytes-make 8 0)))",
     "bytes-get: pre-condition failed: index 8 out of bounds for bytes of length 8"),
    ("RT-3", "c3_strfromcode", '(int-to-string (one-char 65 ""))',
     "string-code-at: pre-condition failed: index 0 out of bounds for a string of length 0"),
    ("RT-4", "n4_slice_index", "(int-to-string (row-at (bytes-make 1 0) 1))",
     "bytes-get: pre-condition failed: index 1 out of bounds for bytes of length 1"),
    ("RT-5", "lx_p1", "(int-to-string (one-char-bad 65))",
     "string-code-at: pre-condition failed: index 1 out of bounds for a string of length 1"),
    ("RT-6", "mk_at_len", "(int-to-string (mk-at-len 0))",
     "bytes-get: pre-condition failed: index 0 out of bounds for bytes of length 0"),
]


@needs_stack
@pytest.mark.parametrize("cell,name,expr,message", RUNTIME, ids=[c[0] for c in RUNTIME])
def test_crm_rt_counterexample_stops_with_the_named_error(tmp_path, cell, name, expr, message):
    r = _build_and_run(tmp_path / cell, _console(_defs(name), expr))
    assert r.returncode != 0, r.stdout + r.stderr
    assert message in r.stdout + r.stderr, r.stdout + r.stderr
