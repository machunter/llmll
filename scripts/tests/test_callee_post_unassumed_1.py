"""CALLEE-POST-UNASSUMED-1: an UNSAFE answer that rests on a dropped callee post.

When a callee has a `post` the verifier cannot assume at the call (outside the
decidable fragment, or dropped by a call-site sort guard), the caller's body VC
lacks an authored hypothesis. An UNSAFE answer whose every failing constraint
holds the result of such a call is a may-counterexample, not a disproof. The
function is no longer reported refuted: it falls back with cause
`callee-post-unassumed` and the construct `post-unassumed:app:<callee>`, and
its post is assumed. Design: docs/design/post-conj-split-professor-review.md
P1, P8; the decision path is ABSTRACTION-VERDICT-1's.

What a pass here means:

* whole, rneed, split, bad (callee post refused, whole or in part) and sg1
  (post dropped by the CALLEE-DATA-SORT-1 guard) exit 0 with the caller in
  `post_unassumed_fallback`.
* wrongother (one failing id with no call on its path) and fullwrong (the
  callee post assumed in full) stay refuted.
* the cross-module caller is attributed with the qualified callee.
* `--strict-verified-core` refuses the reclassified function after the solver.
* the trust report, the sidecar, the proof artifact (whose `solver_result`
  stays the raw answer and still replays) and `patch` agree.
"""

import json
import os
import re
import shlex
import shutil
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURES = REPO_ROOT / "scripts" / "tests" / "fixtures" / "callee_post_unassumed"
VERIFY_SCHEMA = json.loads((REPO_ROOT / "docs" / "llmll-verify.schema.json").read_text())
TRUST_SCHEMA = json.loads((REPO_ROOT / "docs" / "llmll-trust-report.schema.json").read_text())
ARTIFACT_SCHEMA = json.loads((REPO_ROOT / "docs" / "proof-artifact.schema.json").read_text())

REPAIR = ("The solver's counterexample may need a fact from the post of '{g}', which the "
          "verifier did not assume at this call. A callee post is assumed only when all "
          "of it is inside the decidable fragment.")

pytestmark = [
    pytest.mark.skipif(not os.environ.get("LLMLL_BIN"), reason="set LLMLL_BIN to a built llmll"),
    pytest.mark.skipif(
        shutil.which("liquid-fixpoint") is None and shutil.which("fixpoint") is None,
        reason="needs liquid-fixpoint on PATH",
    ),
]


def _llmll() -> list:
    return shlex.split(os.environ["LLMLL_BIN"])


def _copy(tmp_path: Path, name: str) -> None:
    if not (tmp_path / name).exists():
        shutil.copy(FIXTURES / name, tmp_path / name)


def _run(tmp_path: Path, name: str, *args: str, json_mode: bool = True) -> subprocess.CompletedProcess:
    _copy(tmp_path, name)
    cmd = _llmll()
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
    return {m.group(1) for d in doc.get("diagnostics", [])
            if d.get("kind") == "lh-unsafe"
            for m in [re.search(r"of '([^']+)'", d.get("message", ""))] if m}


@pytest.mark.parametrize("name,fn,callee", [
    ("whole.llmll", "use-it", "pos-only"),
    ("rneed.llmll", "use-it", "pos-or-one"),
    ("split.llmll", "use-it", "pos-or-one"),
    ("bad.llmll", "use-it", "pos-or-one"),
    ("sg1.llmll", "use", "mk"),
])
def test_cpu_dropped_callee_post_falls_back(tmp_path, name, fn, callee):
    p = _run(tmp_path, name)
    doc = _doc(p)
    assert p.returncode == 0, p.stdout
    assert doc["solver_verdict"] == "safe"
    assert doc["body_fallback_causes"][fn] == "callee-post-unassumed"
    assert doc["body_fallback_constructs"][fn] == [f"post-unassumed:app:{callee}"]
    assert doc["post_unassumed_fallback"] == {fn: f"post-unassumed:app:{callee}"}
    assert "abstraction_fallback" not in doc
    assert fn not in doc["body_faithful"]
    t = _run(tmp_path, name, json_mode=False)
    out = t.stdout + t.stderr
    assert t.returncode == 0, out
    assert (f"W-BODY-FALLBACK: '{fn}' fell back from body-faithful verification "
            f"(callee-post-unassumed), so its post is assumed and not proved. "
            f"Refused by: post-unassumed:app:{callee}. " + REPAIR.format(g=callee)) in out, out
    assert f"callee-post fallback: {fn} (post-unassumed:app:{callee})" in out, out


def test_cpu_wrongother_keeps_the_unmarked_refutation(tmp_path):
    p = _run(tmp_path, "wrongother.llmll")
    doc = _doc(p)
    assert p.returncode == 1, p.stdout
    assert doc["solver_verdict"] == "refuted"
    assert "post_unassumed_fallback" not in doc
    assert _failed_fns(doc) == {"use-it"}


def test_cpu_fullwrong_callee_post_assumed_stays_refuted(tmp_path):
    p = _run(tmp_path, "fullwrong.llmll")
    doc = _doc(p)
    assert p.returncode == 1, p.stdout
    assert doc["solver_verdict"] == "refuted"
    assert "post_unassumed_fallback" not in doc
    assert _failed_fns(doc) == {"use-it"}


def test_cpu_cross_module_caller_names_the_qualified_callee(tmp_path):
    lib = _run(tmp_path, "xlib.llmll")
    assert lib.returncode == 0, lib.stdout
    p = _run(tmp_path, "xuse.llmll")
    doc = _doc(p)
    assert p.returncode == 0, p.stdout
    assert doc["body_fallback_causes"]["use-it"] == "callee-post-unassumed"
    assert doc["post_unassumed_fallback"] == {"use-it": "post-unassumed:app:xlib.pos-only"}


def test_cpu_strict_core_still_fails_closed(tmp_path):
    # The plan expected the post-solver gate to name use-it. Measured: the
    # callee whose post is dropped is itself a fallback here, so the
    # PRE-solver gate refuses the file first (pos-only,
    # contract-post-outside-fragment) and the solver never runs. Pinned as
    # measured: under strict the file still exits 1 and use-it is not proved.
    p = _run(tmp_path, "whole.llmll", "--strict-verified-core")
    doc = _doc(p)
    assert p.returncode == 1, p.stdout
    errs = _nested(doc, "strict_errors")
    assert any(e["cause"] == "fallback" and "pos-only" in e["fns"] for e in errs), errs


def test_cpu_trust_report_marks_fallback_not_refuted(tmp_path):
    p = _run(tmp_path, "whole.llmll", "--trust-report")
    doc = _doc(p)
    assert p.returncode == 0, p.stdout
    tr = _nested(doc, "trust_report")
    assert tr["refuted_fns"] == []
    u = next(e for e in tr["entries"] if e["name"] == "use-it")
    assert u["body_fallback"]["cause"] == "callee-post-unassumed"
    assert u["body_fallback"]["constructs"] == ["post-unassumed:app:pos-only"]
    assert not u.get("refuted", False)


def test_cpu_sidecar_caller_asserted_not_body_faithful(tmp_path):
    p = _run(tmp_path, "whole.llmll")
    assert p.returncode == 0, p.stdout
    side = json.loads((tmp_path / "whole.llmll.verified.json").read_text())
    assert side["use-it"]["post"]["display_level"]["level"] == "asserted"
    assert side["use-it"].get("body_faithful", False) is False


def test_cpu_proof_artifact_keeps_raw_result_and_replays(tmp_path):
    p = _run(tmp_path, "whole.llmll", "--proof-artifact", "w.pa.json", json_mode=False)
    assert p.returncode == 0, p.stdout + p.stderr
    art = json.loads((tmp_path / "w.pa.json").read_text())
    assert art["solver_result"] == "unsafe-refuted"
    u = next(f for f in art["functions"] if f["name"] == "use-it")
    assert u["fallback_reason"] == "callee-post-unassumed"
    assert u["refuted"] is False
    jsonschema = pytest.importorskip("jsonschema")
    jsonschema.Draft202012Validator(ARTIFACT_SCHEMA).validate(art)
    r = subprocess.run([*_llmll(), "replay-artifact", "w.pa.json"],
                       capture_output=True, text=True, timeout=120, cwd=str(tmp_path))
    assert r.returncode == 0, r.stdout + r.stderr
    assert "reproduced" in r.stdout, r.stdout


@pytest.mark.parametrize("name", ["whole.llmll", "sg1.llmll", "wrongother.llmll"])
def test_cpu_verify_json_validates(tmp_path, name):
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


def _patch_use_it(tmp_path: Path, flags: tuple = ()):
    """Emit whole.llmll to JSON-AST, hole use-it's body, check it out, fill the original body back."""
    _copy(tmp_path, "whole.llmll")
    emit = tmp_path / "emit"
    b = subprocess.run([*_llmll(), "build", "whole.llmll", "--emit", "-o", str(emit)],
                       capture_output=True, text=True, timeout=600, cwd=str(tmp_path))
    assert b.returncode == 0, b.stdout[-800:] + b.stderr[-800:]
    target = tmp_path / "whole.ast.json"
    shutil.copy(emit / "whole.ast.json", target)
    ast = json.loads(target.read_text(encoding="utf-8"))
    idx = next(i for i, s in enumerate(ast["statements"]) if s.get("name") == "use-it")
    pointer = f"/statements/{idx}/body"
    fill = ast["statements"][idx]["body"]
    ast["statements"][idx]["body"] = {"kind": "hole-named", "name": "impl"}
    target.write_text(json.dumps(ast), encoding="utf-8")
    co = subprocess.run([*_llmll(), "--json", "checkout", target.name, pointer],
                        capture_output=True, text=True, timeout=120, cwd=str(tmp_path))
    assert co.returncode == 0, co.stdout[-800:] + co.stderr[-800:]
    token = json.loads(co.stdout)["token"]
    req = tmp_path / "patch.json"
    req.write_text(json.dumps({"token": token, "patch": [
        {"op": "replace", "path": pointer, "value": fill}]}), encoding="utf-8")
    p = subprocess.run([*_llmll(), "patch", *flags, target.name, req.name],
                       capture_output=True, text=True, timeout=600, cwd=str(tmp_path))
    line = next((ln for ln in p.stdout.splitlines() if ln.startswith("{")), None)
    assert line, f"no JSON from patch: {p.stdout[-800:]}{p.stderr[-800:]}"
    return json.loads(line), p


NOT_PROVED = ("'use-it' was not proved: the solver answered UNSAFE, but the failing constraint "
              "uses the result of 'pos-only', whose post was not assumed at that call "
              "(post-unassumed:app:pos-only). Its postcondition was assumed.")


def test_cpu_patch_writes_the_fill_and_reports_it_not_proved(tmp_path):
    res, p = _patch_use_it(tmp_path)
    assert res["result"] == "PatchSuccess", res
    assert res["verification"] == [{"body_faithful": False, "fallback_cause": "callee-post-unassumed",
                                    "fallback_constructs": ["post-unassumed:app:pos-only"],
                                    "fn": "use-it"}], res


def test_cpu_patch_require_proof_refuses_with_the_new_message(tmp_path):
    res, p = _patch_use_it(tmp_path, ("--require-proof",))
    assert res["result"] == "PatchNotProved", res
    assert NOT_PROVED in json.dumps(res) or NOT_PROVED in p.stdout + p.stderr, res


def test_cpu_callee_with_refused_post_says_callers_do_not_assume_it(tmp_path):
    t = _run(tmp_path, "whole.llmll", json_mode=False)
    out = t.stdout + t.stderr
    assert ("W-BODY-FALLBACK: 'pos-only' fell back from body-faithful verification "
            "(contract-post-outside-fragment), so its post is not proved, and callers "
            "do not assume it.") in out, out

