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
    # The current stamp (FN-SHADOW-1 moved it to "4"): a forged record must be
    # refused by the evidence checks, not merely discarded for an old stamp.
    "checker_soundness_version": "4",
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


@needs_binary
def test_tgk1_the_trust_gap_warning_reads_the_checked_level(tmp_path):
    """TRUST-GAP-KEY-1. The module loader merged an imported module's sidecar into
    the cache as written, and the type checker's cross-module trust-gap warning
    read that, so after an edit of `lib.sq`'s body it still named `level: tested`
    while every other reader showed `asserted`. The cache now passes the read
    check where it is loaded. Failed on v0.30.0 (the edited case said `tested`)."""
    lib_src = ("(def-shell sq [x: int] -> int\n  (post (>= result 0))\n  {body})\n"
               "(check \"sq is non-negative\"\n  (for-all [x: int]\n    (>= (sq x) 0)))\n")
    lib = _write(tmp_path, "lib.llmll", lib_src.format(body="(* x x)"))
    _write(tmp_path, "main.llmll", "(import lib)\n(def-shell f [x: int] -> int\n  (lib.sq x))\n")
    assert _llmll(tmp_path, "test", "lib.llmll").returncode == 0

    def gap_levels():
        r = _llmll(tmp_path, "--json", "check", "main.llmll")
        diags = json.loads(r.stdout)["diagnostics"]
        return [d["message"].split("(level: ")[1].split(")")[0]
                for d in diags if d.get("kind") == "trust-gap"]

    assert gap_levels() == ["tested"]          # control: the record matches its source
    lib.write_text(lib_src.format(body="(+ (* x x) 0)"), encoding="utf-8")
    assert gap_levels() == ["asserted"]        # the body changed after the test


@needs_binary
def test_tlf1_a_stale_declaration_re_warns(tmp_path):
    """TRUST-LEVEL-FLOOR-1. A `(trust f :level L)` declaration silences the gap
    only while f's checked evidence covers L. Under the old ceiling rule
    `(trust lib.sq :level tested)` stayed silent after the body edit demoted the
    record to `asserted`; now the warning returns and names both levels."""
    lib_src = ("(def-shell sq [x: int] -> int\n  (post (>= result 0))\n  {body})\n"
               "(check \"sq is non-negative\"\n  (for-all [x: int]\n    (>= (sq x) 0)))\n")
    lib = _write(tmp_path, "lib.llmll", lib_src.format(body="(* x x)"))
    _write(tmp_path, "main.llmll", "(import lib)\n(trust lib.sq :level tested)\n"
                                   "(def-shell f [x: int] -> int\n  (lib.sq x))\n")
    assert _llmll(tmp_path, "test", "lib.llmll").returncode == 0

    def gaps():
        r = _llmll(tmp_path, "--json", "check", "main.llmll")
        return [d["message"] for d in json.loads(r.stdout)["diagnostics"]
                if d.get("kind") == "trust-gap"]

    assert gaps() == []                        # control: tested evidence meets the declaration
    lib.write_text(lib_src.format(body="(+ (* x x) 0)"), encoding="utf-8")
    [msg] = gaps()                             # the body changed after the test
    assert "(level: asserted)" in msg
    assert "(trust lib.sq :level tested) declares tested" in msg


# ---------------------------------------------------------------------------
# C4: the flag law (design §3.1) and the one document (design §3.3)
# ---------------------------------------------------------------------------

INC_CORRECT = "(def inc [x: int] -> int (pre (>= x 0)) (post (> result x)) (+ x 1))\n"

REPORTING = {0, 4}
GATE = {0, 1, 4}

# (flag args, Adds(F) ∪ {0}). `{out}` is replaced with a tmp path. The other
# prover flags need a live Leanstral endpoint or binary; `--leanstral-mock`
# drives the same pipeline.
FLAGS = [
    (["--trust-report"], REPORTING),
    (["--spec-coverage"], REPORTING),
    (["--cdp"], REPORTING),
    (["--weakness-check"], REPORTING),
    (["--obligations"], REPORTING),
    (["--obligation-report"], REPORTING),
    (["--proof-artifact", "{out}"], REPORTING),
    (["--fq-out", "{out}"], REPORTING),
    (["--strict-verify"], REPORTING),
    (["--strict-verified-core"], GATE),
    (["--leanstral-mock"], REPORTING),
]


def _documents(stdout):
    """Every top-level JSON value on stdout, in order."""
    dec, i, docs = json.JSONDecoder(), 0, []
    while i < len(stdout):
        while i < len(stdout) and stdout[i].isspace():
            i += 1
        if i >= len(stdout):
            break
        doc, i = dec.raw_decode(stdout, i)
        docs.append(doc)
    return docs


def _flag_args(args, tmp_path):
    return [a.replace("{out}", str(tmp_path / "out.bin")) for a in args]


@needs_binary
@pytest.mark.parametrize("args,allowed", FLAGS, ids=[" ".join(a) for a, _ in FLAGS])
def test_flag_law(tmp_path, args, allowed):
    """No flag masks a failure; on a passing run a flag adds only Adds(F)."""
    for name, src in (("bad.llmll", INC_REFUTED), ("good.llmll", INC_CORRECT)):
        d = tmp_path / name.split(".")[0]
        d.mkdir()
        _write(d, name, src)
        plain = _llmll(d, "verify", name).returncode
        flagged = _llmll(d, "verify", name, *_flag_args(args, d)).returncode
        if plain != 0:
            assert flagged == plain, (name, args, plain, flagged)
        else:
            assert flagged in allowed, (name, args, plain, flagged)
    # the positive witness really is refuted, and its twin really passes
    assert _llmll(tmp_path / "bad", "verify", "bad.llmll").returncode == 1
    assert _llmll(tmp_path / "good", "verify", "good.llmll").returncode == 0


@needs_binary
@pytest.mark.parametrize("args,allowed", FLAGS, ids=[" ".join(a) for a, _ in FLAGS])
def test_one_document_whose_exit_code_is_the_status(tmp_path, args, allowed):
    """`verify --json` prints exactly one JSON value, carrying the process status."""
    for name, src in (("bad.llmll", INC_REFUTED), ("good.llmll", INC_CORRECT)):
        d = tmp_path / name.split(".")[0]
        d.mkdir()
        _write(d, name, src)
        r = _llmll(d, "--json", "verify", name, *_flag_args(args, d))
        docs = _documents(r.stdout)
        assert len(docs) == 1, (args, name, r.stdout)
        assert docs[0]["exit_code"] == r.returncode, (args, name, docs[0])
        assert list(docs[0])[:4] == ["verify_json_version", "exit_code", "solver_verdict", "composed"]


@needs_binary
def test_edge_1_and_14_the_refuted_inc_under_trust_report(tmp_path):
    """Design edge cases 1 and 14: exit 1, one document, refuted, on stdout alone."""
    _write(tmp_path, "inc.llmll", INC_REFUTED)
    r = _llmll(tmp_path, "--json", "verify", "inc.llmll", "--trust-report")
    assert r.returncode == 1
    (doc,) = _documents(r.stdout)
    assert doc["exit_code"] == 1
    assert doc["solver_verdict"] == "refuted"
    assert doc["trust_report"]["refuted_fns"] == ["inc"]
    t = _llmll(tmp_path, "verify", "inc.llmll", "--trust-report")
    assert t.returncode == 1
    assert "sidecar-only report" not in t.stdout


@needs_binary
def test_edge_2_the_refuted_inc_under_spec_coverage(tmp_path):
    _write(tmp_path, "inc.llmll", INC_REFUTED)
    r = _llmll(tmp_path, "--json", "verify", "inc.llmll", "--spec-coverage")
    assert r.returncode == 1
    (doc,) = _documents(r.stdout)
    assert doc["solver_verdict"] == "refuted"
    assert doc["spec_coverage"]["summary"]["contracted"] == 1


@needs_binary
def test_edge_3_strict_verify_obligation_report_is_one_document(tmp_path):
    _write(tmp_path, "inc.llmll", INC_CORRECT)
    r = _llmll(tmp_path, "--json", "verify", "inc.llmll", "--strict-verify", "--obligation-report")
    assert r.returncode == 0
    (doc,) = _documents(r.stdout)
    assert doc["exit_code"] == 0
    assert doc["composed"]["obligation_report_schema_version"] == doc["obligation_report"]["schema_version"]
    s = _llmll(tmp_path, "--json", "verify", "inc.llmll", "--strict-verify")
    (doc2,) = _documents(s.stdout)
    assert {"trust_report", "spec_coverage"} <= set(doc2)


@needs_binary
def test_edge_10_report_run_keeps_tested(tmp_path):
    """Design edge case 10 through the C4 path: `test`, then `verify --trust-report`."""
    _write(tmp_path, "sq.llmll", SQ)
    assert _llmll(tmp_path, "test", "sq.llmll").returncode == 0
    r = _llmll(tmp_path, "--json", "verify", "sq.llmll", "--trust-report")
    assert r.returncode == 0, r.stdout + r.stderr
    (doc,) = _documents(r.stdout)
    assert _entry(doc["trust_report"], "sq")["post_level"].startswith("tested")
    side = json.loads((tmp_path / "sq.llmll.verified.json").read_text())
    assert side["sq"]["post"]["display_level"]["level"] == "tested"
