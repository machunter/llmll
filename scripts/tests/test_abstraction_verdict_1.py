"""ABSTRACTION-VERDICT-1: an UNSAFE answer that rests on two calls to one callee.

The body VC gives every call a fresh result and no congruence. When every
failing constraint of a function holds two or more call results of one callee
(a contracted callee, a self-call or a function-typed parameter), the UNSAFE
answer may be a model no pure function realizes. Such a function is no longer
reported refuted: it falls back with cause `abstraction-unsafe` and the
construct `abstraction:app:<callee>`, and its post is assumed. One call keeps
the refutation. Design: docs/design/byte-io-proposal.md Rev 2, Part 0.

Since CALL-CONGRUENCE-1, calls whose callee takes and returns only int, bool
or string get a congruence fact and are never marked; the rule is the
backstop for every other pair. The congruence side (a1, a2, w5, a4, caller,
mixed) is tested in test_call_congruence_1.py.

What a pass here means:

* backstop_list (a list[int] argument) and backstop_float (float, excluded on
  both sides) exit 0 with the function in `abstraction_fallback`; a3 (one call)
  stays refuted.
* `mixed_backstop` keeps the refutation of its one-call function and exit 1.
* `--strict-verified-core` refuses the reclassified function after the solver.
* the trust report, the sidecar, a caller, and the proof artifact (whose
  `solver_result` stays the raw answer and still replays) all agree.
"""

import json
import os
import shlex
import shutil
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURES = REPO_ROOT / "scripts" / "tests" / "fixtures" / "abstraction_verdict"
VERIFY_SCHEMA = json.loads((REPO_ROOT / "docs" / "llmll-verify.schema.json").read_text())
TRUST_SCHEMA = json.loads((REPO_ROOT / "docs" / "llmll-trust-report.schema.json").read_text())
ARTIFACT_SCHEMA = json.loads((REPO_ROOT / "docs" / "proof-artifact.schema.json").read_text())

pytestmark = [
    pytest.mark.skipif(not os.environ.get("LLMLL_BIN"), reason="set LLMLL_BIN to a built llmll"),
    pytest.mark.skipif(
        shutil.which("liquid-fixpoint") is None and shutil.which("fixpoint") is None,
        reason="needs liquid-fixpoint on PATH",
    ),
]


def _run(tmp_path: Path, name: str, *args: str, json_mode: bool = True) -> subprocess.CompletedProcess:
    if not (tmp_path / name).exists():
        shutil.copy(FIXTURES / name, tmp_path / name)
    cmd = [*shlex.split(os.environ["LLMLL_BIN"])]
    if json_mode:
        cmd.append("--json")
    cmd += ["verify", *args, name]
    return subprocess.run(cmd, capture_output=True, text=True, timeout=120, cwd=str(tmp_path))


def _doc(p: subprocess.CompletedProcess) -> dict:
    return json.loads(p.stdout)


def _nested(doc: dict, key: str):
    v = doc[key]
    return json.loads(v) if isinstance(v, str) else v


def _failed_fns(doc: dict) -> set:
    import re
    return {m.group(1) for d in doc.get("diagnostics", [])
            if d.get("kind") == "lh-unsafe"
            for m in [re.search(r"of '([^']+)'", d.get("message", ""))] if m}


@pytest.mark.parametrize("name,fn,callee", [
    ("backstop_list.llmll", "hl", "gl"),
    ("backstop_float.llmll", "hf", "gf"),
])
def test_av_true_post_falls_back(tmp_path, name, fn, callee):
    p = _run(tmp_path, name)
    doc = _doc(p)
    assert p.returncode == 0, p.stdout
    assert doc["solver_verdict"] == "safe"
    assert doc["abstraction_fallback"] == {fn: f"abstraction:app:{callee}"}
    assert doc["body_fallback_causes"][fn] == "abstraction-unsafe"
    assert fn not in doc["body_faithful"]
    t = _run(tmp_path, name, json_mode=False)
    out = t.stdout + t.stderr
    assert t.returncode == 0, out
    assert f"Refused by: abstraction:app:{callee}." in out, out
    assert f"abstraction fallback: {fn} (abstraction:app:{callee})" in out, out


def test_av_a3_single_call_stays_refuted(tmp_path):
    p = _run(tmp_path, "a3.llmll")
    doc = _doc(p)
    assert p.returncode == 1, p.stdout
    assert doc["solver_verdict"] == "refuted"
    assert "abstraction_fallback" not in doc
    assert _failed_fns(doc) == {"h1"}


def test_av_mixed_keeps_the_one_call_refutation(tmp_path):
    p = _run(tmp_path, "mixed_backstop.llmll")
    doc = _doc(p)
    assert p.returncode == 1, p.stdout
    assert doc["solver_verdict"] == "refuted"
    assert doc["abstraction_fallback"] == {"hl": "abstraction:app:gl"}
    assert _failed_fns(doc) == {"gw"}


def test_av_strict_core_refuses_the_reclassified_function(tmp_path):
    p = _run(tmp_path, "backstop_list.llmll", "--strict-verified-core")
    doc = _doc(p)
    assert p.returncode == 1, p.stdout
    errs = _nested(doc, "strict_errors")
    assert any(e["cause"] == "fallback" and e["fns"] == ["hl"] for e in errs), errs


def test_av_trust_report_marks_fallback_not_refuted(tmp_path):
    p = _run(tmp_path, "backstop_list.llmll", "--trust-report")
    doc = _doc(p)
    assert p.returncode == 0, p.stdout
    tr = _nested(doc, "trust_report")
    assert tr["refuted_fns"] == []
    h = next(e for e in tr["entries"] if e["name"] == "hl")
    assert h["body_fallback"]["cause"] == "abstraction-unsafe"
    assert h["body_fallback"]["constructs"] == ["abstraction:app:gl"]
    assert not h.get("refuted", False)


def test_av_sidecar_g_verified_h_asserted(tmp_path):
    p = _run(tmp_path, "backstop_list.llmll")
    assert p.returncode == 0, p.stdout
    side = json.loads((tmp_path / "backstop_list.llmll.verified.json").read_text())
    assert side["gl"]["post"]["display_level"]["level"] == "verified"
    assert side["hl"]["post"]["display_level"]["level"] == "asserted"


def test_av_caller_is_proved_and_not_depending_on_refuted(tmp_path):
    p = _run(tmp_path, "caller.llmll", "--trust-report")
    doc = _doc(p)
    assert p.returncode == 0, p.stdout
    assert "k" in doc["body_faithful"]
    tr = _nested(doc, "trust_report")
    k = next(e for e in tr["entries"] if e["name"] == "k")
    assert not k.get("refuted", False)
    assert not any("refuted" in d for d in k.get("drifts", [])), k


def test_av_proof_artifact_keeps_raw_result_and_replays(tmp_path):
    p = _run(tmp_path, "backstop_list.llmll", "--proof-artifact", "bl.pa.json", json_mode=False)
    assert p.returncode == 0, p.stdout + p.stderr
    art = json.loads((tmp_path / "bl.pa.json").read_text())
    assert art["solver_result"] == "unsafe-refuted"
    h = next(f for f in art["functions"] if f["name"] == "hl")
    assert h["fallback_reason"] == "abstraction-unsafe"
    assert h["refuted"] is False
    jsonschema = pytest.importorskip("jsonschema")
    jsonschema.Draft202012Validator(ARTIFACT_SCHEMA).validate(art)
    r = subprocess.run([*shlex.split(os.environ["LLMLL_BIN"]), "replay-artifact", "bl.pa.json"],
                       capture_output=True, text=True, timeout=120, cwd=str(tmp_path))
    assert r.returncode == 0, r.stdout + r.stderr
    assert "reproduced" in r.stdout, r.stdout


@pytest.mark.parametrize("name", ["a1.llmll", "a2.llmll", "a3.llmll", "a4.llmll",
                                  "w5.llmll", "mixed.llmll", "caller.llmll",
                                  "backstop_list.llmll", "backstop_float.llmll",
                                  "mixed_backstop.llmll"])
def test_av_verify_json_validates(tmp_path, name):
    jsonschema = pytest.importorskip("jsonschema")
    referencing = pytest.importorskip("referencing")
    registry = referencing.Registry().with_resource(
        TRUST_SCHEMA["$id"], referencing.Resource.from_contents(TRUST_SCHEMA))
    v = jsonschema.Draft202012Validator(VERIFY_SCHEMA, registry=registry)
    p = _run(tmp_path, name, "--trust-report")
    doc = _doc(p)
    errors = sorted(v.iter_errors(doc), key=lambda e: list(e.path))
    assert not errors, "\n".join(f"{list(e.path)}: {e.message}" for e in errors)
    assert doc["exit_code"] == p.returncode
