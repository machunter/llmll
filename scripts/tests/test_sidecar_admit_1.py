"""SIDECAR-ADMIT-1: a persisted positive tier the compiler cannot back is not rendered.

Four CLI cells, each one a witness measured against llmll 0.23.6 BEFORE the fix:

  A  `verify --trust-report` on a forged sidecar rendered `post: verified` and
     counted `verified: 1`, exit 0.
  B  `verify --proof-artifact --json` refused to mint, printed nothing at all,
     wrote no artifact, exit 0.
  C  `verify --strict-verify` on a SAFE run was already honest, because the SAFE
     sidecar write repairs the file before the render reads it. Negative control.
  D  `verify --strict-verify` on an UNSAFE run rendered
     `post: verified (liquid-fixpoint)   [body_fallback: ...]` and counted
     `verified: 1`. No sidecar write happens on a failing run, so the render read
     the forged file raw.

The forged sidecar is an adversarial fixture. It is written into a tmp_path, never
into the tree, and it is the input the defect is about: hand-editing
`.verified.json` is not a workflow this project supports.
"""

import json
import os
import shlex
import subprocess

import pytest

needs_binary = pytest.mark.skipif(
    not os.environ.get("LLMLL_BIN"),
    reason="set LLMLL_BIN to a built llmll; the spec-roundtrip job runs this in CI "
           "(the cells call `llmll verify`, which shells out to liquid-fixpoint)",
)

FIXTURE = """(module sq
  (export sq3)
  (def-shell sq3 [n: int] -> int
    (pre (>= n 0))
    (post (>= result n))
    (* n n)))
"""

# `bad` is refuted by the solver, so the run fails and NO sidecar write happens.
# That is what lets the forged record reach the render on the strict path.
FIXTURE_UNSAFE = """(module two
  (export sq3 bad)
  (def-shell sq3 [n: int] -> int
    (pre (>= n 0))
    (post (>= result n))
    (* n n))
  (def bad [m: int] -> int
    (post (> result m))
    m))
"""

FORGED = {
    "checker_soundness_version": "2",
    "sq3": {
        "post": {"display_level": {"level": "verified", "prover": "liquid-fixpoint"}},
        "pre": {"display_level": {"level": "asserted"}},
    },
}


def _write(tmp_path, name, source):
    src = tmp_path / name
    src.write_text(source)
    (tmp_path / (name + ".verified.json")).write_text(json.dumps(FORGED))
    return src


def _verify(src, *flags):
    llmll = shlex.split(os.environ["LLMLL_BIN"])
    return subprocess.run(
        [*llmll, "verify", str(src), *flags],
        capture_output=True, text=True, timeout=300,
    )


@needs_binary
def test_trust_report_does_not_render_a_forged_tier(tmp_path):
    """Cell A. The sidecar-only render downgrades, discloses, and still exits 0."""
    src = _write(tmp_path, "sq.llmll", FIXTURE)
    r = _verify(src, "--trust-report")

    assert "post: verified" not in r.stdout, "forged tier rendered: " + r.stdout
    assert "post: asserted" in r.stdout
    assert "verified:         0" in r.stdout
    # A downgrade is not a failure: this path holds one input and cannot detect a
    # contradiction, so it must not claim to have found one.
    assert r.returncode == 0
    assert "sidecar-only report" in r.stdout


@needs_binary
def test_proof_artifact_json_is_not_silent(tmp_path):
    """Cell B. The artifact is written with honest tiers instead of withheld."""
    src = _write(tmp_path, "sq.llmll", FIXTURE)
    out = tmp_path / "pa.json"
    r = _verify(src, "--proof-artifact", str(out), "--json")

    assert r.returncode == 0
    json.loads(r.stdout)  # stdout stays exactly one valid JSON document
    assert out.exists(), "artifact withheld with no explanation in either channel"
    rec = [f for f in json.loads(out.read_text())["functions"] if f["name"] == "sq3"]
    assert rec, "sq3 missing from the artifact"
    # The kernel's PositiveWithFallback state is now unreachable here: the tier is
    # demoted on read, so the record it mints is consistent by construction.
    assert rec[0]["evidence_level"] == "asserted"
    assert rec[0]["fallback_reason"] == "body-outside-fragment"


@needs_binary
def test_strict_verify_safe_run_is_unaffected(tmp_path):
    """Cell C, negative control. An honest SAFE run keeps its verdict and its exit."""
    src = _write(tmp_path, "sq.llmll", FIXTURE)
    r = _verify(src, "--strict-verify")

    assert r.returncode == 0
    assert "post: verified" not in r.stdout
    assert "verified:         0" in r.stdout


@needs_binary
def test_strict_verify_unsafe_run_does_not_render_a_forged_tier(tmp_path):
    """Cell D. No sidecar write happens, so the render must not trust the file."""
    src = _write(tmp_path, "two.llmll", FIXTURE_UNSAFE)
    r = _verify(src, "--strict-verify")

    # A positive tier beside a body_fallback mark is the contradiction the proof
    # artifact's kernel calls unrepresentable. It must not appear in the report.
    assert "post: verified" not in r.stdout, "forged tier rendered: " + r.stdout
    assert "verified:         0" in r.stdout
    assert "body_fallback" in r.stdout
    # The refuted contract keeps its own exit code: SIDECAR-ADMIT-1 escalates from
    # success only and never rewrites an existing non-zero status.
    assert r.returncode == 1
