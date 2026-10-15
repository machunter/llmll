"""TRUST-REPORT-GATE-1: every `llmll --json verify` document satisfies docs/llmll-verify.schema.json.

WHAT THIS PINS. Since TRUST-REPORT-GATE-1 (C4), `verify --json` prints exactly
one document once the file type-checks, built by compiler/src/LLMLL/VerifyEnvelope.hs.
The schema publishes that shape. The Haskell cells VS-1 to VS-4 in
compiler/test/Spec.hs check that the envelope builder and the schema agree on
the version, the head keys and the nested keys. These cells check the other
half: the document the binary actually prints, for each flag, on a refuted and a
correct function, on the pre-solver strict-core refusal, and with no solver on
PATH, validates against the schema, with the nested `trust_report` checked
against docs/llmll-trust-report.schema.json through its `$id`.

WHY IT SKIPS. Every cell runs the binary, and all but the solver-absent cell
need fixpoint on PATH. The spec-roundtrip job runs this file with LLMLL_BIN set
and jsonschema installed, and refuses a run where a cell skipped.
"""

from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path

import pytest

jsonschema = pytest.importorskip("jsonschema")
referencing = pytest.importorskip("referencing")

pytestmark = pytest.mark.skipif(
    not os.environ.get("LLMLL_BIN"),
    reason="set LLMLL_BIN to a built llmll; the spec-roundtrip job runs this in CI",
)

REPO = Path(__file__).resolve().parents[2]
VERIFY_SCHEMA = json.loads((REPO / "docs" / "llmll-verify.schema.json").read_text())
TRUST_SCHEMA = json.loads((REPO / "docs" / "llmll-trust-report.schema.json").read_text())

INC_REFUTED = "(def inc [x: int] -> int (pre (>= x 0)) (post (> result x)) x)\n"
INC_CORRECT = "(def inc [x: int] -> int (pre (>= x 0)) (post (> result x)) (+ x 1))\n"
# A def-shell outside the solver's fragment: strict-core refuses it before the solver runs.
SQ_FALLBACK = "(def-shell sq [n: int] -> int (post (>= result 0)) (* n n))\n"

FLAGS = [
    [],
    ["--trust-report"],
    ["--spec-coverage"],
    ["--cdp"],
    ["--weakness-check"],
    ["--obligations"],
    ["--obligation-report"],
    ["--strict-verify"],
    ["--strict-verified-core"],
    ["--proof-artifact", "artifact.json"],
    ["--leanstral-mock"],
    ["--strict-verify", "--obligation-report"],
]


def _validator():
    registry = referencing.Registry().with_resource(
        TRUST_SCHEMA["$id"], referencing.Resource.from_contents(TRUST_SCHEMA)
    )
    return jsonschema.Draft202012Validator(VERIFY_SCHEMA, registry=registry)


def _verify(tmp_path: Path, src: str, flags: list[str], env: dict | None = None):
    f = tmp_path / "subject.llmll"
    f.write_text(src)
    r = subprocess.run(
        [os.environ["LLMLL_BIN"], "--json", "verify", *flags, f.name],
        cwd=tmp_path, capture_output=True, text=True, env=env, timeout=120,
    )
    return r, json.loads(r.stdout)


def _assert_valid(doc: dict, returncode: int):
    errors = sorted(_validator().iter_errors(doc), key=lambda e: list(e.path))
    assert not errors, "\n".join(f"{list(e.path)}: {e.message}" for e in errors)
    assert doc["exit_code"] == returncode


@pytest.mark.parametrize("src", [INC_REFUTED, INC_CORRECT], ids=["refuted", "correct"])
@pytest.mark.parametrize("flags", FLAGS, ids=lambda f: " ".join(f) or "plain")
def test_vs_document_validates(tmp_path, src, flags):
    r, doc = _verify(tmp_path, src, flags)
    _assert_valid(doc, r.returncode)


def test_vs_strict_core_refusal_is_not_run(tmp_path):
    r, doc = _verify(tmp_path, SQ_FALLBACK, ["--strict-verified-core"])
    _assert_valid(doc, r.returncode)
    assert (doc["solver_verdict"], doc["exit_code"]) == ("not-run", 1)


def test_vs_solver_absent_is_not_run(tmp_path):
    empty = tmp_path / "empty-path"
    empty.mkdir()
    env = dict(os.environ, PATH=str(empty))
    r, doc = _verify(tmp_path, INC_CORRECT, ["--trust-report"], env=env)
    _assert_valid(doc, r.returncode)
    assert (doc["solver_verdict"], doc["exit_code"]) == ("not-run", 3)
