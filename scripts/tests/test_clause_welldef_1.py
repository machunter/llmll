"""CLAUSE-WELLDEF-1: a partial read in a pre or post must be defined where the
clause is evaluated.

The verifier emits one definedness obligation (`wd-pre`, `wd-post`) per
`map-get`, `bytes-get` and `bytes-set` in a translated clause, under the same
hypotheses as the clause's truth obligation. A failing obligation with no
dropped hypothesis is the hard verdict `ill-defined` (exit 1); one that rests
on a dropped hypothesis is the fallback cause `clause-welldef-unproved`.
Design: docs/design/clause-welldef-proposal.md Rev 3.

What a pass here means:

* E1 (an unguarded `map-get` on an empty map in the post) exits 1 with
  `ill_defined == ["mk"]`, a `clause-ill-defined` diagnostic and no verified
  record; E2 (the same read under `map-has`) verifies.
* E3 is ill-defined and refuted, and the refutation is qualified.
* E6 (the contract-read-oob doc claim) and E7 (`bytes-set` out of range) exit 1.
* E17 (a read through an in-range `bytes-set`) verifies.
* E20 (a body outside the fragment) is ill-defined and keeps its fallback cause.
* A2S-13 (a caller reading a map key its callee's post reads) verifies: the
  definedness of an assumed callee post is assumed with it.
* `verify --json` and `--proof-artifact` validate against their schemas, and
  the artifact carries the soundness-epoch member.
"""

import json
import os
import shlex
import shutil
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
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

SOURCES = {
    "e1.llmll": "(def-shell mk [n: int] -> map[int,int] (post (= (map-get result 3) 0)) (map-empty))\n",
    "e2.llmll": "(def-shell mk [n: int] -> map[int,int] (post (and (map-has result 3) (= (map-get result 3) 7))) (map-put (map-empty) 3 7))\n",
    "e3.llmll": "(def-shell mk [n: int] -> map[int,int] (post (and (= (map-get result 3) 7) (map-has result 3))) (map-empty))\n",
    "e7.llmll": "(def-shell h [b: bytes[4]] -> int (post (>= (bytes-get (bytes-set b 9 300) 0) 0)) 0)\n",
    "e17.llmll": "(def-shell h [b: bytes[4]] -> int (post (= (bytes-get (bytes-set b 0 7) 1) (bytes-get b 1))) 0)\n",
    "a2s13.llmll": "(def bump [m: map[int,int] k: int] -> map[int,int] (pre (map-has m k)) (post (= (map-get result k) 7)) (map-put m k 7))\n(def-shell wrap [m: map[int,int] k: int] -> map[int,int] (pre (map-has m k)) (post (= (map-get result k) 7)) (bump m k))\n",
    "e20.llmll": "(def-shell g [m: map[int,int] s: string] -> int (pre (> (map-get m 3) 0)) (post (>= result 0)) (string-length (string-concat s s)))\n",
}


def _put(tmp_path: Path, name: str) -> None:
    if name == "e6.llmll":
        shutil.copy(REPO_ROOT / "scripts" / "doc-claims" / "contract-read-oob.llmll", tmp_path / name)
    else:
        (tmp_path / name).write_text(SOURCES[name])


def _verify(tmp_path: Path, name: str, *args: str, json_mode: bool = True) -> subprocess.CompletedProcess:
    _put(tmp_path, name)
    cmd = shlex.split(os.environ["LLMLL_BIN"])
    if json_mode:
        cmd.append("--json")
    cmd += ["verify", *args, name]
    return subprocess.run(cmd, capture_output=True, text=True, timeout=120, cwd=str(tmp_path))


def _doc(p: subprocess.CompletedProcess) -> dict:
    return json.loads(p.stdout)


def test_e1_ill_defined(tmp_path):
    p = _verify(tmp_path, "e1.llmll")
    doc = _doc(p)
    assert p.returncode == 1, p.stdout + p.stderr
    assert doc["ill_defined"] == ["mk"]
    ds = [d for d in doc["diagnostics"] if d.get("kind") == "clause-ill-defined"]
    assert len(ds) == 1, doc["diagnostics"]
    assert ds[0]["pointer"] == "/statements/0/post"
    assert "(map-get result 3) needs (map-has result 3)" in ds[0]["message"]
    assert not (tmp_path / "e1.llmll.verified.json").exists()


def test_e2_guarded_read_verifies(tmp_path):
    p = _verify(tmp_path, "e2.llmll")
    assert p.returncode == 0, p.stdout + p.stderr
    assert "ill_defined" not in _doc(p)


def test_e3_ill_defined_and_refuted_qualified(tmp_path):
    p = _verify(tmp_path, "e3.llmll", "--trust-report")
    doc = _doc(p)
    assert p.returncode == 1, p.stdout + p.stderr
    assert doc["ill_defined"] == ["mk"]
    tr = doc["trust_report"]
    tr = json.loads(tr) if isinstance(tr, str) else tr
    assert tr["ill_defined_fns"] == ["mk"]
    assert tr["refuted_fns"] == ["mk"]
    assert any("fix the ill-defined clause first" in d["message"]
               for d in doc["diagnostics"] if d.get("kind") == "lh-unsafe")


@pytest.mark.parametrize("name,fn", [("e6.llmll", "f"), ("e7.llmll", "h")])
def test_out_of_range_reads_are_ill_defined(tmp_path, name, fn):
    p = _verify(tmp_path, name)
    assert p.returncode == 1, p.stdout + p.stderr
    assert _doc(p)["ill_defined"] == [fn]


def test_e17_read_through_in_range_set_verifies(tmp_path):
    p = _verify(tmp_path, "e17.llmll")
    assert p.returncode == 0, p.stdout + p.stderr


def test_e20_ill_defined_keeps_fallback_cause(tmp_path):
    p = _verify(tmp_path, "e20.llmll")
    doc = _doc(p)
    assert p.returncode == 1, p.stdout + p.stderr
    assert doc["ill_defined"] == ["g"]
    assert doc["body_fallback_causes"]["g"] == "body-outside-fragment"



def test_a2s13_callee_post_definedness_is_assumed(tmp_path):
    """The callee post (= (map-get result k) 7) was defined on every run that
    made it true, so the caller assumes map-has result k with it."""
    p = _verify(tmp_path, "a2s13.llmll")
    doc = _doc(p)
    assert p.returncode == 0, p.stdout + p.stderr
    assert doc["solver_verdict"] == "safe"
    assert "ill_defined" not in doc

@pytest.mark.parametrize("name", ["e1.llmll", "e2.llmll", "e3.llmll", "e20.llmll"])
def test_verify_json_validates(tmp_path, name):
    jsonschema = pytest.importorskip("jsonschema")
    referencing = pytest.importorskip("referencing")
    registry = referencing.Registry().with_resource(
        TRUST_SCHEMA["$id"], referencing.Resource.from_contents(TRUST_SCHEMA))
    v = jsonschema.Draft202012Validator(VERIFY_SCHEMA, registry=registry)
    p = _verify(tmp_path, name, "--trust-report")
    doc = _doc(p)
    errors = sorted(v.iter_errors(doc), key=lambda e: list(e.path))
    assert not errors, "\n".join(f"{list(e.path)}: {e.message}" for e in errors)
    assert doc["verify_json_version"] == "1.1.0"
    assert doc["exit_code"] == p.returncode


def test_proof_artifact_carries_epoch_and_ill_defined(tmp_path):
    p = _verify(tmp_path, "e1.llmll", "--proof-artifact", "e1.pa.json", json_mode=False)
    assert p.returncode == 1, p.stdout + p.stderr
    art = json.loads((tmp_path / "e1.pa.json").read_text())
    assert art["proof_artifact_version"] == "0.2.0"
    assert art["composed_versions"]["checker_soundness_version"] == "7"
    mk = next(f for f in art["functions"] if f["name"] == "mk")
    assert mk["ill_defined"] is True
    assert mk["evidence_level"] != "verified"
    jsonschema = pytest.importorskip("jsonschema")
    jsonschema.Draft202012Validator(ARTIFACT_SCHEMA).validate(art)
