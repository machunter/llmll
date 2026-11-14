"""MUL-VAR-1: a product of two variables in a contract, end to end.

Design: docs/design/mul-var-proposal.md (Rev 3b). The emitter normalizes a
product of two non-constant terms, each monomial becomes one free symbol
`mul##k`, and a fixed set of ground theorems is added. SAFE is a proof. An
UNSAFE answer on a constraint that names `mul##k` is not a disproof until the
native recheck asks z3 the same question with `*` interpreted and validates
the model by exact evaluation. Only then is the function `refuted`; any other
answer keeps the fallback with the construct `abstraction:nonlinear:*`.

What a pass here means:

* The witness table. Each of the 134 witnesses in
  scripts/tests/fixtures/mul_var_1/ goes through `llmll --json verify
  --trust-report`, serially, each in its own temporary folder (no sidecar is
  written into the repo), and its verdict matches expected.json: 89 of 94 true
  witnesses verified and 39 of 40 false witnesses refuted. The known
  divergences are A5 and AF3 (a product in a contract `if`, design Rev 3b
  amendment 2, row CONTRACT-IF-1), which fall back with
  `contract-post-outside-fragment`. The verdict is read from the trust
  report's `refuted` flag, so a function that is refuted and ill-defined at
  once (N5: the pre's read is out of bounds exactly in the counterexample)
  counts as refuted, as `test_e3_ill_defined_and_refuted_qualified` holds.
* M1 (an off-by-one offset) is refuted, exit 1, and prints its validated
  model in the one allowed form. W23 (x*x != 2*y*y) falls back, exit 0, with
  the product W-BODY-FALLBACK text and no `abstraction:app:` key.
* The other three callers run the recheck: `patch` rejects an off-by-one fill
  of a product contract (HEAD before step 6 wrote it as a fallback), the
  diverge classifier puts it under `refuted` (before: `outside_fragment`),
  and `--cdp` kills mutants of a product post (before: every candidate was
  excluded).
* A replay of the proof artifact of a rechecked refutation reproduces, and
  reruns the recheck: an artifact whose product function's recorded verdict
  the rerun recheck does not give back fails closed (step 7).
* The trust report names the ground-fact family `product-facts`.

Every test needs a built llmll (LLMLL_BIN), liquid-fixpoint and z3 on PATH.
The `--cdp` test is one run; CDP runs must not overlap (CDP-FQ-RACE-1).
"""

from __future__ import annotations

import json
import os
import re
import shlex
import shutil
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURES = REPO_ROOT / "scripts" / "tests" / "fixtures" / "mul_var_1"
EXPECTED = json.loads((FIXTURES / "expected.json").read_text())
TIMEOUT_S = 180

pytestmark = [
    pytest.mark.skipif(not os.environ.get("LLMLL_BIN"), reason="set LLMLL_BIN to a built llmll"),
    pytest.mark.skipif(
        shutil.which("liquid-fixpoint") is None and shutil.which("fixpoint") is None,
        reason="needs liquid-fixpoint on PATH",
    ),
    pytest.mark.skipif(shutil.which("z3") is None, reason="the native recheck needs z3 on PATH"),
]


def _llmll() -> list[str]:
    return shlex.split(os.environ["LLMLL_BIN"])


def _run(cwd: Path, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(_llmll() + list(args), cwd=str(cwd), capture_output=True,
                          text=True, timeout=TIMEOUT_S)


def _last_json(stdout: str) -> dict:
    lines = [ln for ln in stdout.splitlines() if ln.strip()]
    return json.loads(lines[-1])


def _nested(doc: dict, key: str):
    v = doc.get(key)
    return json.loads(v) if isinstance(v, str) else v


def _verdict(doc: dict, fid: str) -> tuple[str, object, object]:
    """One verdict for function fid: verified, refuted, fallback or other."""
    causes = doc.get("body_fallback_causes") or {}
    constructs = doc.get("body_fallback_constructs") or {}
    if fid in (doc.get("abstraction_fallback") or {}) or fid in (doc.get("body_fallback") or []):
        return "fallback", causes.get(fid), constructs.get(fid)
    tr = _nested(doc, "trust_report") or {}
    entry = next((e for e in tr.get("entries", []) if e.get("name") == fid), {})
    if entry.get("refuted"):
        return "refuted", None, None
    if doc.get("solver_verdict") == "safe" and fid in (doc.get("body_faithful") or []):
        return "verified", None, None
    return "other:" + str(doc.get("solver_verdict")), None, None


def _expected(w: dict) -> tuple[str, object, object]:
    if w.get("known_divergence") == "contract-if":
        return "fallback", "contract-post-outside-fragment", ["if"]
    if w["design_verdict"] == "fallback":
        return "fallback", "abstraction-unsafe", ["abstraction:nonlinear:*"]
    return w["design_verdict"], None, None


def test_mv_witness_table_matches_expected(tmp_path: Path) -> None:
    """134 witnesses, serially: 89 of 94 true verified, 39 of 40 false refuted."""
    witnesses = EXPECTED["witnesses"]
    mismatches = []
    got = {}
    for name in sorted(witnesses, key=lambda n: witnesses[n]["file"]):
        w = witnesses[name]
        work = tmp_path / name
        work.mkdir()
        shutil.copy(FIXTURES / w["file"], work / w["file"])
        p = _run(work, "--json", "verify", "--trust-report", w["file"])
        doc = _last_json(p.stdout)
        v = _verdict(doc, w["id"])
        got[name] = v
        want = _expected(w)
        want_exit = 1 if want[0] == "refuted" else 0
        if v != want or p.returncode != want_exit:
            mismatches.append((name, v, p.returncode, want, want_exit))
    assert mismatches == [], mismatches
    true_ws = [n for n, w in witnesses.items() if w["truth"]]
    false_ws = [n for n, w in witnesses.items() if not w["truth"]]
    s = EXPECTED["summary"]
    assert (len(true_ws), len(false_ws)) == (s["true"], s["false"]) == (94, 40)
    assert sum(got[n][0] == "verified" for n in true_ws) == s["true_verified"] == 89
    assert sum(got[n][0] == "refuted" for n in false_ws) == s["false_refuted"] == 39
    # no false witness is ever proved
    assert not any(got[n][0] == "verified" for n in false_ws), got


def test_mv_m1_off_by_one_is_refuted_with_a_vc_counterexample(tmp_path: Path) -> None:
    shutil.copy(FIXTURES / "m1.llmll", tmp_path / "m1.llmll")
    p = _run(tmp_path, "verify", "m1.llmll")
    assert p.returncode == 1, p.stdout + p.stderr
    lines = [ln.strip() for ln in p.stdout.splitlines() if "VC counterexample:" in ln]
    assert lines, p.stdout
    m = re.fullmatch(r"VC counterexample: ((?:\S+=-?\d+ ?)+)\. Callee results in it are assumed, not computed\.",
                     lines[0])
    assert m, lines[0]
    vals = {k: int(v) for k, v in (kv.split("=") for kv in m.group(1).split())}
    # the model is a real counterexample of M1's VC
    w, h, y, x, r = (vals[k] for k in ("w", "h", "y", "x", "r"))
    assert 0 <= y < h and 0 <= x <= w and r == y * w + x and not r < w * h, vals
    pj = _run(tmp_path, "--json", "verify", "m1.llmll")
    doc = _last_json(pj.stdout)
    assert pj.returncode == 1 and doc["solver_verdict"] == "refuted", doc
    assert "abstraction_fallback" not in doc, doc


def test_mv_w23_falls_back_with_the_product_text(tmp_path: Path) -> None:
    shutil.copy(FIXTURES / "w23.llmll", tmp_path / "w23.llmll")
    p = _run(tmp_path, "--json", "verify", "w23.llmll")
    assert p.returncode == 0, p.stdout + p.stderr
    doc = _last_json(p.stdout)
    assert doc["abstraction_fallback"] == {"mv-w23": "abstraction:nonlinear:*"}, doc
    assert "abstraction:app:" not in p.stdout, p.stdout
    msgs = [d["message"] for d in doc.get("diagnostics", []) if d.get("code") == "W-BODY-FALLBACK"]
    assert len(msgs) == 1, doc.get("diagnostics")
    lines = msgs[0].split("\n")
    assert lines[0] == "W-BODY-FALLBACK mv-w23: the post is not proved. A product is in the failing constraint."
    assert lines[1].startswith("  Refused by: abstraction:nonlinear:*   at /statements/"), lines
    assert lines[2] == "  Product facts did not prove it. Native z3 found no counterexample."
    assert lines[3] == "  The post stays a run-time check. A strict-core def that calls mv-w23 will be refused."
    assert "''" not in msgs[0]


# --- the other three callers ---------------------------------------------------

def _v(n: str) -> dict:
    return {"kind": "var", "name": n}


def _op(o: str, *args: dict) -> dict:
    return {"kind": "op", "op": o, "args": list(args)}


def _lit(k: int) -> dict:
    return {"kind": "lit-int", "value": k}


# def-shell offs [w h y x] -> int, pre 0 <= y < h, 0 <= x < w, post result < w*h
OFFS = {
    "schemaVersion": "0.15.0",
    "llmll_version": "0.38.1",
    "statements": [
        {"kind": "export", "names": ["offs"]},
        {"kind": "def-shell", "name": "offs",
         "params": [{"name": n, "param_type": {"kind": "primitive", "name": "int"}} for n in "whyx"],
         "return_type": {"kind": "primitive", "name": "int"},
         "pre": _op("and", _op(">=", _v("y"), _lit(0)),
                    _op("and", _op("<", _v("y"), _v("h")),
                        _op("and", _op(">=", _v("x"), _lit(0)), _op("<", _v("x"), _v("w"))))),
         "post": _op("<", _v("result"), _op("*", _v("w"), _v("h"))),
         "body": {"kind": "hole-named", "name": "body"}},
    ],
}
POINTER = "/statements/1/body"
GOOD = _op("+", _op("*", _v("y"), _v("w")), _v("x"))
OFF_BY_ONE = _op("+", _op("*", _v("y"), _v("w")), _op("+", _v("x"), _lit(1)))


@pytest.fixture
def offs(tmp_path: Path) -> Path:
    (tmp_path / "offs.ast.json").write_text(json.dumps(OFFS))
    return tmp_path


def _patch(work: Path, fill: dict) -> subprocess.CompletedProcess:
    p = _run(work, "checkout", "offs.ast.json", POINTER)
    assert p.returncode == 0, p.stdout + p.stderr
    tok = json.loads(p.stdout)["token"]
    req = work / "req.json"
    req.write_text(json.dumps({"token": tok, "patch": [{"op": "replace", "path": POINTER, "value": fill}]}))
    return _run(work, "patch", "offs.ast.json", "req.json")


def test_mv_patch_rejects_an_off_by_one_fill(offs: Path) -> None:
    """Before step 6 the fill was written: PatchSuccess, abstraction-unsafe."""
    before = (offs / "offs.ast.json").read_bytes()
    p = _patch(offs, OFF_BY_ONE)
    assert p.returncode == 1, p.stdout + p.stderr
    res = _last_json(p.stdout)
    assert res["result"] == "PatchVerifyError", res
    assert any(d.get("kind") == "lh-unsafe" for d in res["diagnostics"]), res
    assert (offs / "offs.ast.json").read_bytes() == before, "the refuted fill was written"


def test_mv_patch_accepts_the_correct_fill(offs: Path) -> None:
    p = _patch(offs, GOOD)
    assert p.returncode == 0, p.stdout + p.stderr
    res = _last_json(p.stdout)
    assert res["result"] == "PatchSuccess", res
    assert res["verification"] == [{"body_faithful": True, "fn": "offs"}], res


def test_mv_diverge_reports_the_off_by_one_fill_refuted(offs: Path) -> None:
    """Before step 6 the off-by-one fill was `outside_fragment`."""
    ids = {}
    session = None
    for name, fill in (("good", GOOD), ("bad", OFF_BY_ONE)):
        p = _run(offs, "checkout", "--multi", "2", "offs.ast.json", POINTER)
        assert p.returncode == 0, p.stdout + p.stderr
        out = json.loads(p.stdout)
        session = session or out["session"]
        scratch = offs / out["scratch"]
        mod = json.loads(scratch.read_text())
        mod["statements"][1]["body"] = fill
        scratch.write_text(json.dumps(mod))
        ids[name] = out["token"]["token"][:12]
    p = _run(offs, "diverge-report", "offs.ast.json", session)
    assert p.returncode == 0, p.stdout + p.stderr
    sp = _last_json(p.stdout)["divergence_witness"]["status_partition"]
    assert sp["refuted"] == [ids["bad"]], sp
    assert sp["verified"] == [ids["good"]], sp
    assert sp["outside_fragment"] == [], sp


def test_mv_replay_of_a_rechecked_refutation_reproduces(tmp_path: Path) -> None:
    shutil.copy(FIXTURES / "m1.llmll", tmp_path / "m1.llmll")
    p = _run(tmp_path, "verify", "m1.llmll", "--proof-artifact", "m1.pa.json")
    assert p.returncode == 1, p.stdout + p.stderr
    art = json.loads((tmp_path / "m1.pa.json").read_text())
    assert art["solver_result"] == "unsafe-refuted", art
    f = next(f for f in art["functions"] if f["name"] == "mv-m1")
    assert f["refuted"] is True and f["fallback_reason"] is None, f
    r = _run(tmp_path, "replay-artifact", "m1.pa.json")
    assert r.returncode == 0, r.stdout + r.stderr
    assert "reproduced" in r.stdout, r.stdout


def _tamper(path: Path, fid: str, **fields) -> None:
    art = json.loads(path.read_text())
    f = next(f for f in art["functions"] if f["name"] == fid)
    f.update(fields)
    path.write_text(json.dumps(art))


def test_mv_replay_reruns_the_recheck_and_fails_closed_on_a_changed_refutation(tmp_path: Path) -> None:
    """Step 7: replay reruns the native recheck on the stored VC. The raw
    answer of M1 is UNSAFE either way, so a replay that compared only the raw
    answer (step 6) reproduced an artifact whose M1 record says fallback
    instead of refuted. The recheck validates M1's model again, so that
    record does not reproduce and the replay fails closed."""
    shutil.copy(FIXTURES / "m1.llmll", tmp_path / "m1.llmll")
    p = _run(tmp_path, "verify", "m1.llmll", "--proof-artifact", "m1.pa.json")
    assert p.returncode == 1, p.stdout + p.stderr
    _tamper(tmp_path / "m1.pa.json", "mv-m1", refuted=False, fallback_reason="abstraction-unsafe")
    r = _run(tmp_path, "replay-artifact", "m1.pa.json")
    assert r.returncode == 1, r.stdout + r.stderr
    assert "FAILED CLOSED" in r.stdout and "native recheck" in r.stdout, r.stdout


def test_mv_replay_of_a_product_fallback_reproduces_and_a_forged_refutation_fails_closed(tmp_path: Path) -> None:
    """W23: the raw answer is UNSAFE and the recheck validates no model, so
    the artifact records a fallback. Its replay reproduces; the same artifact
    with W23 forged to refuted fails closed, because the rerun recheck gives
    no model."""
    shutil.copy(FIXTURES / "w23.llmll", tmp_path / "w23.llmll")
    p = _run(tmp_path, "verify", "w23.llmll", "--proof-artifact", "w23.pa.json")
    assert p.returncode == 0, p.stdout + p.stderr
    art = json.loads((tmp_path / "w23.pa.json").read_text())
    assert art["solver_result"] == "unsafe-refuted", art
    f = next(f for f in art["functions"] if f["name"] == "mv-w23")
    assert f["refuted"] is False and f["fallback_reason"] == "abstraction-unsafe", f
    r = _run(tmp_path, "replay-artifact", "w23.pa.json")
    assert r.returncode == 0, r.stdout + r.stderr
    assert "reproduced" in r.stdout, r.stdout
    _tamper(tmp_path / "w23.pa.json", "mv-w23", refuted=True)
    r = _run(tmp_path, "replay-artifact", "w23.pa.json")
    assert r.returncode == 1, r.stdout + r.stderr
    assert "FAILED CLOSED" in r.stdout and "native recheck" in r.stdout, r.stdout


def test_mv_trust_report_discloses_the_product_facts_family(tmp_path: Path) -> None:
    """Design "Disclosure": one ground-fact family, product-facts, on a
    function whose proof used the facts. No new assumed_facts kind."""
    shutil.copy(FIXTURES / "w3.llmll", tmp_path / "w3.llmll")
    p = _run(tmp_path, "--json", "verify", "--trust-report", "w3.llmll")
    assert p.returncode == 0, p.stdout + p.stderr
    doc = _last_json(p.stdout)
    tr = _nested(doc, "trust_report")
    entry = next(e for e in tr["entries"] if e["name"] == "mv-w3")
    assert "product-facts" in entry.get("ground_fact_families", []), entry
    assert tr["trust_report_version"] == "1.11.0", tr.get("trust_report_version")


AREA = """(module area
  (export area)
  (def area [w: int h: int] -> int
    (pre (and (>= w 0) (>= h 0)))
    (post (= result (* w h)))
    (* w h)))
"""


def test_mv_cdp_kills_mutants_of_a_product_post(tmp_path: Path) -> None:
    """One serial --cdp run. Before step 6 all 6 candidates were excluded as
    unvalidated, because a marked UNSAFE read as no verdict."""
    (tmp_path / "area.llmll").write_text(AREA)
    p = _run(tmp_path, "--json", "verify", "--cdp", "--trust-report", "area.llmll")
    assert p.returncode == 0, p.stdout + p.stderr
    doc = _last_json(p.stdout)
    tr = _nested(doc, "trust_report")
    axis = next(e for e in tr["entries"] if e["name"] == "area")["discriminative_axis"]
    assert axis["candidate_count"] > 0, axis
    assert axis["excluded_candidate_count"] == 0, axis
    assert axis["satisfying_candidate_count"] == 0, axis
    assert "(lambda [w] w)" in axis["distinguishing_inputs"], axis
