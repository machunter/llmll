"""TRUST-REPORT-GATE-1: the solver-less renders and the evidence-key checks.

CLI cells, run against the binary named by LLMLL_BIN. Design:
docs/design/trust-report-gate-1-proposal.md Rev 1 (§3.4 subcommands, §3.5
evidence that still matches). Plan: trust-report-gate-1-implementation-plan.md.

  Subcommands (C3, design §3.4)
    S1  `llmll trust-report` on a forged sidecar: `post: asserted`, the footer,
        exit 0, and the forged record named in `discarded_records`.
    S2  `llmll spec-coverage` on the refuted `inc`: exit 0, coverage printed. No
        solver runs, so the refutation is not visible here and the exit is 0.
    S3  both subcommands exit 1 on a file that fails `check`, as `verify` does.

  Evidence keys (C2, design §3.5, edge cases 10-13). The read here is the
  `trust-report` subcommand; the write is plain `verify`.
    E10 `test` then `verify` keeps the `tested` record (a SAFE write used to
        replace the file), and the render shows `tested`.
    E11 a body edit after `test`: the stamped key no longer matches, the render
        shows `asserted`, and `discarded_records` names the function.
    E12 a `tested` record with no `subject_key` (written before v0.30.0) demotes.
    E13 an untainted `leanstral` proof-cache entry whose `obligation_hash` is not
        the live one does not upgrade the post to `verified-lean`.

The fixtures are written into tmp_path, never into the tree.
"""

import json
import os
import shlex
import subprocess

import pytest

needs_binary = pytest.mark.skipif(
    not os.environ.get("LLMLL_BIN"),
    reason="set LLMLL_BIN to a built llmll; the spec-roundtrip job runs this in CI",
)

INC_REFUTED = "(def inc [x: int] -> int (pre (>= x 0)) (post (> result x)) x)\n"

SQ = """(def-shell sq [x: int] -> int
  (post (>= result 0))
  (* x x))
(check "sq is non-negative"
  (for-all [x: int]
    (>= (sq x) 0)))
"""

FORGED_SRC = """(module sq
  (export sq3)
  (def-shell sq3 [n: int] -> int
    (pre (>= n 0))
    (post (>= result n))
    (* n n)))
"""

FORGED = {
    "checker_soundness_version": "3",
    "sq3": {
        "post": {"display_level": {"level": "verified", "prover": "liquid-fixpoint"}},
        "pre": {"display_level": {"level": "asserted"}},
    },
}


def _llmll(cwd, *args):
    llmll = shlex.split(os.environ["LLMLL_BIN"])
    return subprocess.run([*llmll, *args], cwd=cwd, capture_output=True,
                          text=True, encoding="utf-8", timeout=300)


def _write(d, name, text):
    p = d / name
    p.write_text(text, encoding="utf-8")
    return p


def _entry(report, name):
    for e in report["entries"]:
        if e["name"] == name:
            return e
    raise AssertionError(f"no entry for {name}: {[e['name'] for e in report['entries']]}")


def _report_json(d, name):
    r = _llmll(d, "--json", "trust-report", name)
    assert r.returncode == 0, r.stdout + r.stderr
    return json.loads(r.stdout)


# ---------------------------------------------------------------------------
# Subcommands
# ---------------------------------------------------------------------------

@needs_binary
def test_s1_trust_report_on_a_forged_sidecar(tmp_path):
    _write(tmp_path, "sq.llmll", FORGED_SRC)
    _write(tmp_path, "sq.llmll.verified.json", json.dumps(FORGED))
    r = _llmll(tmp_path, "trust-report", "sq.llmll")
    assert r.returncode == 0, r.stdout + r.stderr
    assert "post: verified" not in r.stdout
    assert "post: asserted" in r.stdout
    assert "sidecar-only report" in r.stdout
    assert "records discarded (key mismatch): 1" in r.stdout
    assert _report_json(tmp_path, "sq.llmll")["discarded_records"] == ["sq3"]


@needs_binary
def test_s2_spec_coverage_on_the_refuted_inc_exits_zero(tmp_path):
    _write(tmp_path, "inc.llmll", INC_REFUTED)
    r = _llmll(tmp_path, "spec-coverage", "inc.llmll")
    assert r.returncode == 0, r.stdout + r.stderr
    assert "Effective coverage" in r.stdout
    j = _llmll(tmp_path, "--json", "spec-coverage", "inc.llmll")
    assert j.returncode == 0
    doc = json.loads(j.stdout)
    assert doc["summary"]["contracted"] == 1
    assert "discarded_records" not in doc  # no sidecar, nothing discarded
    # no solver ran, so no sidecar was written
    assert not (tmp_path / "inc.llmll.verified.json").exists()


@needs_binary
@pytest.mark.parametrize("sub", ["trust-report", "spec-coverage"])
def test_s3_subcommand_exits_one_when_check_fails(tmp_path, sub):
    _write(tmp_path, "bad.llmll", "(def f [x: int] -> int (+ x undefined-name))\n")
    r = _llmll(tmp_path, sub, "bad.llmll")
    assert r.returncode == 1, r.stdout + r.stderr
    # the type-check diagnostic, not an argument-parser rejection
    assert "unbound variable 'undefined-name'" in r.stdout, r.stdout + r.stderr


# ---------------------------------------------------------------------------
# Evidence keys
# ---------------------------------------------------------------------------

@needs_binary
def test_e10_a_safe_verify_keeps_the_tested_record(tmp_path):
    _write(tmp_path, "sq.llmll", SQ)
    assert _llmll(tmp_path, "test", "sq.llmll").returncode == 0
    side = json.loads((tmp_path / "sq.llmll.verified.json").read_text())
    witness = side["sq"]["post"]["pbt_witnesses"][0]
    assert witness["subject_key"].startswith("sha256:")
    v = _llmll(tmp_path, "verify", "sq.llmll")
    assert v.returncode == 0, v.stdout + v.stderr
    side = json.loads((tmp_path / "sq.llmll.verified.json").read_text())
    assert side["sq"]["post"]["display_level"]["level"] == "tested"
    rep = _report_json(tmp_path, "sq.llmll")
    assert _entry(rep, "sq")["post_level"].startswith("tested")
    assert "discarded_records" not in rep


@needs_binary
def test_e11_a_body_edit_after_test_demotes_and_is_listed(tmp_path):
    src = _write(tmp_path, "sq.llmll", SQ)
    assert _llmll(tmp_path, "test", "sq.llmll").returncode == 0
    src.write_text(SQ.replace("(* x x))", "(+ (* x x) 0))"), encoding="utf-8")
    rep = _report_json(tmp_path, "sq.llmll")
    assert _entry(rep, "sq")["post_level"] == "asserted"
    assert rep["discarded_records"] == ["sq"]


@needs_binary
def test_e12_a_record_with_no_subject_key_demotes(tmp_path):
    _write(tmp_path, "sq.llmll", SQ)
    assert _llmll(tmp_path, "test", "sq.llmll").returncode == 0
    p = tmp_path / "sq.llmll.verified.json"
    side = json.loads(p.read_text())
    for w in side["sq"]["post"]["pbt_witnesses"]:
        del w["subject_key"]
    p.write_text(json.dumps(side))
    rep = _report_json(tmp_path, "sq.llmll")
    assert _entry(rep, "sq")["post_level"] == "asserted"
    assert rep["discarded_records"] == ["sq"]


@needs_binary
def test_e13_a_leanstral_entry_for_an_edited_obligation_does_not_upgrade(tmp_path):
    _write(tmp_path, "sq.llmll", "(def-shell sq [x: int] -> int\n  (post (>= result 0))\n  (* x x))\n")
    # An untainted entry, as a kernel-checked run would write it, but for an
    # obligation that is no longer the live one. The mock prover is tainted and
    # never records an entry, so the cell writes the cache directly.
    cache = {"version": "0.3.1", "proofs": {"/post/sq": {
        "obligation_hash": "0" * 64,
        "proof": "by nlinarith [sq_nonneg x]",
        "prover": "leanstral",
        "verified_at": "2026-10-14T00:00:00Z"}}}
    (tmp_path / "sq.llmll.proof-cache.json").write_text(json.dumps(cache))
    rep = _report_json(tmp_path, "sq.llmll")
    assert not _entry(rep, "sq")["post_level"].startswith("verified-lean"), rep
    v = _llmll(tmp_path, "verify", "sq.llmll")
    assert v.returncode == 0, v.stdout + v.stderr
    side = json.loads((tmp_path / "sq.llmll.verified.json").read_text())
    assert side["sq"]["post"]["display_level"]["level"] != "verified-lean"


@needs_binary
def test_e10b_an_imported_subject_keeps_its_tested_record(tmp_path):
    """Plan Rev 1 amendment A2. `llmll test` writes the record for an imported
    subject under its qualified key (`lib.sq`), stamped with the key of the
    module that defines it. The read check resolves the name through that module,
    so a matching record renders `tested-joint` (a qualified record shares its
    witness with the opened alias), and an edit of the imported body demotes it."""
    lib = _write(tmp_path, "lib.llmll", "(def-shell sq [x: int] -> int\n  (post (>= result 0))\n  (* x x))\n")
    _write(tmp_path, "main.llmll", "(import lib)\n(open lib)\n(check \"sq is non-negative\"\n"
                                   "  (for-all [x: int]\n    (>= (sq x) 0)))\n")
    assert _llmll(tmp_path, "test", "main.llmll").returncode == 0
    side = json.loads((tmp_path / "main.llmll.verified.json").read_text())
    assert side["lib.sq"]["post"]["pbt_witnesses"][0]["subject_key"].startswith("sha256:")
    rep = _report_json(tmp_path, "main.llmll")
    assert _entry(rep, "lib.sq")["post_level"].startswith("tested-joint"), rep
    assert "discarded_records" not in rep
    lib.write_text("(def-shell sq [x: int] -> int\n  (post (>= result 0))\n  (+ (* x x) 0))\n")
    rep = _report_json(tmp_path, "main.llmll")
    assert _entry(rep, "lib.sq")["post_level"] == "asserted"
    assert rep["discarded_records"] == ["lib.sq"]
