"""FQ-NAME-COLLIDE-1: two program names must not reach the solver as one symbol.

The verifier prints names through a many-to-one map (`a-b`, `a?b`, `a.b` and
`a_b` all print as `a_b`), and its internal names (`result`, `v`, `_bv_*`,
`strlit_*`, `ctor_*`, `s$tag`) share the namespace with the program's. On
llmll 0.37.0 each fixture below that names a refuting input was reported
`verified`: exit 0, `all_proved` true, and a `verified` sidecar.

What a pass here means:

* Each false-proof fixture now falls back with the cause `fq-name-collision`:
  `all_proved` is not true and the sidecar does not record `verified`.
* `v-capture` (a parameter named `v`) gets a correct verdict instead: refuted.
  `v-id`, the same shape on a true program, verifies.
* `json-carrier`, a JSON-AST parameter spelled `s$tag`, is a parse error of
  kind `invalid-name`.
* The companions (a hyphen alone, a parameter `v` with no binder) still verify,
  and the controls with distinct names are still refuted.
* `--strict-verified-core` refuses `collide`; its sidecar records `asserted`
  under stamp "8"; a stamp "7" sidecar that claims `verified` is discarded; a
  0.37.0 proof artifact fails closed on replay; a clash in one function keeps
  the proof of another function in the same file.
"""

import json
import os
import shlex
import shutil
import signal
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
FIX = Path(__file__).resolve().parent / "fixtures" / "fq_name_collide_1"

pytestmark = [
    pytest.mark.skipif(not os.environ.get("LLMLL_BIN"), reason="set LLMLL_BIN to a built llmll"),
    pytest.mark.skipif(
        shutil.which("liquid-fixpoint") is None and shutil.which("fixpoint") is None,
        reason="needs liquid-fixpoint on PATH",
    ),
]

TIMEOUT_S = 120


def _run(args, cwd):
    """Run llmll; on a timeout kill the whole process group, not only the child."""
    p = subprocess.Popen(shlex.split(os.environ["LLMLL_BIN"]) + list(args), cwd=str(cwd),
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                         start_new_session=True)
    try:
        out, err = p.communicate(timeout=TIMEOUT_S)
    except subprocess.TimeoutExpired:
        os.killpg(p.pid, signal.SIGKILL)
        p.communicate()
        raise
    return subprocess.CompletedProcess(p.args, p.returncode, out, err)


# A dotted parameter parses from source, but llmll-ast.schema.json's name pattern
# rejects it, so as a tracked file it would fail test_schema_valid_1. It is
# written here instead.
INLINE = {
    "dot.llmll": ";; FQ-NAME-COLLIDE-1: a.b beside a_b. False: (g 1 0).\n"
                 "(def g [a.b: int a_b: int] -> int (pre (>= a.b 1)) (post (>= a_b 1)) 0)\n",
}


def _verify(tmp_path, name, *flags):
    if name in INLINE:
        (tmp_path / name).write_text(INLINE[name], encoding="utf-8")
    else:
        shutil.copy(FIX / name, tmp_path / name)
    p = _run(["--json", "verify", *flags, name], tmp_path)
    return p, json.loads(p.stdout)


def _sidecar(tmp_path, name):
    side = tmp_path / (name + ".verified.json")
    return json.loads(side.read_text()) if side.exists() else None


def _level(side, fn):
    if side is None or fn not in side:
        return None
    return side[fn].get("post", {}).get("display_level", {}).get("level")


FALSE_PROOFS = [
    ("collide.llmll", "collide"),
    ("ques-dot.llmll", "f"),
    ("dot.llmll", "g"),
    ("bool-sort.llmll", "f"),
    ("string-len.llmll", "f"),
    ("tag-carrier.llmll", "f"),
    ("map-carrier.llmll", "f"),
    ("fresh-prefix.llmll", "f"),
    ("result-param.llmll", "f"),
    ("strlit.llmll", "f"),
    ("ctor-same-sort.llmll", "f"),
    ("dup-param.llmll", "f"),
]


@pytest.mark.parametrize("name,fn", FALSE_PROOFS)
def test_false_proof_falls_back_on_name_collision(tmp_path, name, fn):
    p, doc = _verify(tmp_path, name)
    assert doc["body_fallback_causes"].get(fn) == "fq-name-collision", p.stdout + p.stderr
    assert doc.get("all_proved") is not True
    assert fn not in doc.get("body_faithful", [])
    assert _level(_sidecar(tmp_path, name), fn) != "verified"
    codes = [d.get("code") for d in doc.get("diagnostics", [])]
    assert "W-FQ-NAME-COLLIDE" in codes


def test_v_capture_is_refuted(tmp_path):
    p, doc = _verify(tmp_path, "v-capture.llmll")
    assert p.returncode == 1, p.stdout + p.stderr
    assert doc["solver_verdict"] == "refuted"
    assert "f" not in doc["body_fallback_causes"]
    assert _level(_sidecar(tmp_path, "v-capture.llmll"), "f") != "verified"


def test_v_id_verifies(tmp_path):
    p, doc = _verify(tmp_path, "v-id.llmll")
    assert p.returncode == 0, p.stdout + p.stderr
    assert doc["solver_verdict"] == "safe"
    assert doc.get("all_proved") is True
    assert _level(_sidecar(tmp_path, "v-id.llmll"), "f") == "verified"


@pytest.mark.parametrize("name", ["hyphen-alone.llmll", "v-nobinder.llmll"])
def test_companions_still_verify(tmp_path, name):
    p, doc = _verify(tmp_path, name)
    assert p.returncode == 0, p.stdout + p.stderr
    assert doc.get("all_proved") is True
    assert doc["body_fallback_causes"] == {}


@pytest.mark.parametrize("name", ["control-pq.llmll", "control-tag.llmll"])
def test_controls_stay_refuted(tmp_path, name):
    p, doc = _verify(tmp_path, name)
    assert p.returncode == 1, p.stdout + p.stderr
    assert doc["solver_verdict"] == "refuted"


def test_json_binder_with_dollar_is_invalid_name(tmp_path):
    p, doc = _verify(tmp_path, "json-carrier.ast.json")
    assert p.returncode == 1, p.stdout + p.stderr
    diags = doc.get("diagnostics", [doc])
    assert any(d.get("kind") == "invalid-name" and "s$tag" in d.get("message", "")
               for d in diags), doc
    assert not (tmp_path / "json-carrier.ast.json.verified.json").exists()


def test_strict_verified_core_refuses_collide(tmp_path):
    p, doc = _verify(tmp_path, "collide.llmll", "--strict-verified-core")
    assert p.returncode != 0, p.stdout + p.stderr
    assert doc["body_fallback_causes"]["collide"] == "fq-name-collision"


def test_collide_sidecar_is_asserted_under_stamp_8(tmp_path):
    _verify(tmp_path, "collide.llmll")
    side = _sidecar(tmp_path, "collide.llmll")
    assert side["checker_soundness_version"] == "8"
    assert _level(side, "collide") == "asserted"


def test_stamp_7_verified_sidecar_is_discarded(tmp_path):
    """The sidecar llmll 0.37.0 wrote for collide.llmll claims a false `verified`
    under stamp "7". Its hash is collide's real one, so only the stamp discards it.
    llmll 0.37.0 reports this file `verified (liquid-fixpoint)` from it."""
    shutil.copy(FIX / "collide.llmll", tmp_path / "collide.llmll")
    side = json.loads((FIX / "collide.v0.37.0.verified.json").read_text())
    assert side["checker_soundness_version"] == "7"
    assert side["collide"]["post"]["display_level"]["level"] == "verified"
    (tmp_path / "collide.llmll.verified.json").write_text(json.dumps(side))
    p = _run(["--json", "trust-report", "collide.llmll"], tmp_path)
    doc = json.loads(p.stdout)
    entry = next(e for e in doc["entries"] if e["name"] == "collide")
    assert entry["post_level"] == "asserted", p.stdout
    assert doc["summary"]["verified"] == 0


def test_v0_37_0_proof_artifact_fails_closed_on_replay(tmp_path):
    shutil.copy(FIX / "collide.llmll", tmp_path / "collide.llmll")
    shutil.copy(FIX / "collide.v0.37.0.pa.json", tmp_path / "collide.pa.json")
    p = _run(["replay-artifact", "collide.pa.json"], tmp_path)
    assert p.returncode != 0, p.stdout + p.stderr
    assert "soundness epoch" in (p.stdout + p.stderr)


def test_clash_keeps_the_other_functions_proof(tmp_path):
    p, doc = _verify(tmp_path, "mixed.llmll")
    assert doc["body_fallback_causes"] == {"collide": "fq-name-collision"}
    assert "good" in doc.get("body_faithful", [])
    side = _sidecar(tmp_path, "mixed.llmll")
    assert _level(side, "good") == "verified"
    assert _level(side, "collide") == "asserted"
