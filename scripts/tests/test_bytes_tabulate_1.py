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

Step 3 (the verifier) adds the V and T cells below the B cells; they run
`llmll check` and `llmll verify` only.
"""

import glob
import json
import os
import random
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


# ---------------------------------------------------------------------------
# Step 3: the verifier (V and T cells). Fixtures in fixtures/bytes_tabulate_1/.
# No GHC build: each cell runs `llmll check` or `llmll verify` only.
#
# * BT-V1: gen and ops verify; the trust report gives `invert` the effective
#   level verified.
# * BT-V2: one byte too many is refuted, and the message names T2.
# * BT-V3 (edge case 3): a generator whose post does not bound its value is
#   refuted at T3, exit 1, and the message names T3.
# * BT-V4 to BT-V6 (edge cases 4a to 4c): two tabulates of lengths 3 and 5 are
#   two terms: 4a and 4c are refuted, 4b is not verified.
# * BT-V7 (edge case 11): a def-shell over a generator that falls back gets
#   the cause tabulate-gen-unverified, and is not verified.
# * BT-V8: the same caller as a def fails check (core-membership-violation).
# * BT-V9 (edge case 12): a cycle through a generator fails check, and the
#   message names the recursion.
# * BT-V10: the same, with the caller's sidecar written before the generator
#   gained its call back.
# * BT-V11: a post that reads the content of the result falls back with
#   abstraction:app:bytes-tabulate, exit 0.
# * BT-V12: --strict-verified-core refuses BT-V7's file.
# * BT-V13 (the step-2 invariant): a generator pre outside the fragment means
#   T2 cannot be built, so the caller falls back and the call-pre stays
#   reported unchecked; it is never body-faithful with no T2.
# * BT-V14: a refuted caller over an unverified generator stays refuted (exit
#   1); the generator rule never moves a function in a hard set.
# * BT-T1, BT-T2, BT-T3: the trust report lists the bytes-tabulate lemma and
#   the generator as a dependency; the proof artifact gives BT-V7's caller
#   fallback_reason tabulate-gen-unverified.
# * BT-T4 (step 4): the proof-artifact schema's closed fallback_reason enum
#   holds tabulate-gen-unverified, its $id names v0.4, and a written artifact
#   carries proof_artifact_version 0.4.0.
# ---------------------------------------------------------------------------

FIX = Path(__file__).resolve().parent / "fixtures" / "bytes_tabulate_1"
VERIFY_TIMEOUT_S = 300


@pytest.fixture()
def fx(tmp_path):
    """A private copy of the fixtures, so no sidecar is written under scripts/."""
    for p in FIX.glob("*.llmll"):
        shutil.copyfile(p, tmp_path / p.name)
    return tmp_path


def _llmll_run(work, *args):
    return _run([*shlex.split(os.environ["LLMLL_BIN"]), *args], cwd=work, timeout=VERIFY_TIMEOUT_S)


def _envelope(p):
    doc = None
    for line in p.stdout.splitlines():
        line = line.strip()
        if line.startswith("{"):
            try:
                doc = json.loads(line)
            except ValueError:
                continue
    if doc is None:
        doc = json.loads(p.stdout)
    return doc


def _verify(work, name, *extra):
    p = _llmll_run(work, "--json", "verify", name, *extra)
    return p, _envelope(p)


def _messages(doc):
    return [d.get("message", "") for d in doc.get("diagnostics", [])]


def _entry(doc, fn):
    tr = doc["trust_report"]
    entries = tr.get("functions") or tr.get("entries") or []
    named = [e for e in entries if e.get("name") == fn]
    assert named, json.dumps(tr)[:3000]
    return named[0]


def _gen_verified(work):
    p, doc = _verify(work, "gen.llmll")
    assert p.returncode == 0, p.stdout[-3000:] + p.stderr[-2000:]
    assert sorted(doc["body_faithful"]) == ["bad-at", "inv-at"], doc
    assert doc["body_fallback_causes"] == {"fb-at": "body-outside-fragment"}, doc


def test_bt_v1_invert_verifies_and_is_verified_in_the_trust_report(fx):
    _gen_verified(fx)
    p, doc = _verify(fx, "ops.llmll", "--trust-report")
    assert p.returncode == 0, p.stdout[-3000:] + p.stderr[-2000:]
    assert doc["body_faithful"] == ["invert"], doc
    assert doc["solver_verdict"] == "safe"
    e = _entry(doc, "invert")
    assert e.get("effective_level", "").startswith("verified"), json.dumps(e)


def test_bt_v2_one_byte_too_many_is_refuted_at_t2(fx):
    _gen_verified(fx)
    p, doc = _verify(fx, "ops_wrong.llmll")
    assert p.returncode == 1, p.stdout[-3000:]
    assert doc["solver_verdict"] == "refuted"
    assert any("(T2)" in m and "generator 'gen.inv-at'" in m for m in _messages(doc)), _messages(doc)


def test_bt_v3_edge3_an_unbounded_generator_value_is_refuted_at_t3(fx):
    _gen_verified(fx)
    p, doc = _verify(fx, "edge3.llmll")
    assert p.returncode == 1, p.stdout[-3000:]
    assert doc["solver_verdict"] == "refuted"
    msgs = _messages(doc)
    assert any("(T3)" in m and "is not proved to lie in 0..255" in m for m in msgs), msgs
    assert not any("(T2)" in m for m in msgs), msgs


@pytest.mark.parametrize("name", ["edge4a.llmll", "edge4b.llmll", "edge4c.llmll"])
def test_bt_v4_to_v6_edge4_two_tabulates_are_two_terms(fx, name):
    p, doc = _verify(fx, name)
    # none verifies: 4a and 4c are refuted (exit 1); 4b, whose post is false, is too
    assert p.returncode == 1, p.stdout[-3000:]
    assert doc["solver_verdict"] == "refuted", doc
    assert "f" not in doc.get("body_fallback_causes", {}), doc


def test_bt_v7_edge11_unverified_generator_gives_the_named_cause(fx):
    _gen_verified(fx)
    p, doc = _verify(fx, "edge11.llmll", "--trust-report")
    assert p.returncode == 0, p.stdout[-3000:]
    assert doc["body_fallback_causes"] == {"ramp": "tabulate-gen-unverified"}, doc
    assert doc["body_fallback_constructs"] == {"ramp": ["tabulate-gen:gen.fb-at"]}, doc
    assert doc["body_faithful"] == [], doc
    assert not _entry(doc, "ramp").get("effective_level", "").startswith("verified")


def test_bt_v8_edge11_a_def_caller_fails_check(fx):
    p = _llmll_run(fx, "--json", "check", "edge11_def.llmll")
    assert p.returncode != 0, p.stdout[-3000:]
    assert "core-membership-violation" in p.stdout, p.stdout[-3000:]


def test_bt_v9_edge12_a_cycle_through_a_generator_fails_check(fx):
    p = _llmll_run(fx, "--json", "check", "edge12.llmll")
    assert p.returncode != 0, p.stdout[-3000:]
    assert "core-membership-violation" in p.stdout and "recursive callee" in p.stdout, p.stdout[-3000:]


def test_bt_v10_edge12_with_a_warm_sidecar_is_refused(fx):
    # The caller and an acyclic generator verify first, so a sidecar exists.
    src = (fx / "edge12.llmll").read_text()
    acyclic = src.replace("(mod (bytes-length (f n)) 256)", "(mod n 256)")
    assert acyclic != src
    (fx / "warm.llmll").write_text(acyclic)
    p, doc = _verify(fx, "warm.llmll")
    assert p.returncode == 0, p.stdout[-3000:]
    assert (fx / "warm.llmll.verified.json").exists()
    # Then the generator gains the call back; the stale sidecar admits nothing.
    (fx / "warm.llmll").write_text(src)
    p = _llmll_run(fx, "--json", "check", "warm.llmll")
    assert p.returncode != 0, p.stdout[-3000:]
    assert "core-membership-violation" in p.stdout and "recursive callee" in p.stdout, p.stdout[-3000:]


def test_bt_v11_a_post_on_the_content_falls_back_as_abstraction(fx):
    _gen_verified(fx)
    p, doc = _verify(fx, "content.llmll")
    assert p.returncode == 0, p.stdout[-3000:]
    assert doc["body_fallback_constructs"] == {"first-inv": ["abstraction:app:bytes-tabulate"]}, doc


def test_bt_v12_strict_verified_core_refuses_the_edge11_file(fx):
    _gen_verified(fx)
    p = _llmll_run(fx, "--json", "verify", "edge11.llmll", "--strict-verified-core")
    assert p.returncode != 0, p.stdout[-3000:]


def test_bt_t1_t2_trust_report_lists_the_lemma_and_the_generator(fx):
    _gen_verified(fx)
    p, doc = _verify(fx, "ops.llmll", "--trust-report")
    assert p.returncode == 0, p.stdout[-3000:]
    e = _entry(doc, "invert")
    rows = e.get("builtin_axioms") or []
    assert any(r["builtin"] == "bytes-tabulate" for r in rows), json.dumps(e)
    assert all(r["category"] == "codegen-determined" for r in rows if r["builtin"] == "bytes-tabulate")
    deps = [d.get("name") for d in e.get("dependencies", [])]
    assert "gen.inv-at" in deps, json.dumps(e)


def test_bt_t3_proof_artifact_gives_the_fallback_reason(fx):
    _gen_verified(fx)
    p = _llmll_run(fx, "verify", "edge11.llmll", "--proof-artifact", "e11.pa.json")
    assert p.returncode == 0, p.stdout[-3000:]
    art = json.loads((fx / "e11.pa.json").read_text())
    ramp = next(f for f in art["functions"] if f["name"] == "ramp")
    assert ramp["fallback_reason"] == "tabulate-gen-unverified", json.dumps(ramp)
    assert ramp["evidence_level"] != "verified"
    # the schema's fallback_reason enum admits the new value
    schema = json.loads((FIX.parents[3] / "docs" / "proof-artifact.schema.json").read_text())
    jsonschema = pytest.importorskip("jsonschema")
    jsonschema.Draft202012Validator(schema).validate(art)


def test_bt_t4_proof_artifact_schema_admits_the_cause_at_0_4_0(fx):
    # Step 4: a new fallback_reason value raises proof_artifact_version
    # (0.3.0 -> 0.4.0). The schema's closed enum holds the value, its $id names
    # v0.4, and an artifact the compiler writes carries 0.4.0.
    schema = json.loads((FIX.parents[3] / "docs" / "proof-artifact.schema.json").read_text())
    assert schema["properties"]["functions"]["items"] == {"$ref": "#/definitions/functionRecord"}
    fn_props = schema["definitions"]["functionRecord"]["properties"]
    assert "tabulate-gen-unverified" in fn_props["fallback_reason"]["enum"]
    assert "/proof-artifact/v0.4/" in schema["$id"], schema["$id"]
    _gen_verified(fx)
    p = _llmll_run(fx, "verify", "ops.llmll", "--proof-artifact", "ops.pa.json")
    assert p.returncode == 0, p.stdout[-3000:]
    art = json.loads((fx / "ops.pa.json").read_text())
    assert art["proof_artifact_version"] == "0.4.0", art["proof_artifact_version"]


def test_bt_v13_a_generator_pre_outside_the_fragment_sends_the_caller_to_fallback(fx):
    p, doc = _verify(fx, "invariant.llmll")
    assert p.returncode == 0, p.stdout[-3000:]
    assert "ramp" not in doc["body_faithful"], doc
    assert doc["body_fallback_constructs"].get("ramp") == ["app:bytes-tabulate"], doc
    h = _llmll_run(fx, "verify", "invariant.llmll")
    assert "call-pre unchecked: ramp -> upre-at" in h.stdout, h.stdout[-3000:]


def test_bt_v14_a_refuted_caller_over_an_unverified_generator_stays_refuted(fx):
    p, doc = _verify(fx, "refuted.llmll")
    assert p.returncode == 1, p.stdout[-3000:]
    assert doc["solver_verdict"] == "refuted", doc
    assert "ramp" not in doc["body_fallback_causes"], doc
