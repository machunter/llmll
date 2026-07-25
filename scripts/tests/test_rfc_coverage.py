"""RFC-COV-1 lint tests (scripts/rfc_coverage.py).

Synthetic inputs only: the lint's logic is exercised without invoking the
compiler, so these tests stay fast and cannot be perturbed by a stale binary.
"""
import importlib.util
import json
import pathlib
import sys

import pytest

SCRIPTS = pathlib.Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("rfc_coverage", SCRIPTS / "rfc_coverage.py")
assert spec and spec.loader
rc = importlib.util.module_from_spec(spec)
sys.modules["rfc_coverage"] = rc
spec.loader.exec_module(rc)


def inv(*rows):
    return {r["cid"]: r for r in rows}


def row(cid, disposition="Encoded", core=False, reason=""):
    return {"cid": cid, "disposition": disposition, "core": core, "reason": reason}


def trust(*entries):
    return {"entries": list(entries)}


def entry(name, pre_sources=None, post_sources=None, pre_source=None, post_source=None):
    e = {"name": name}
    if pre_sources is not None:
        e["pre_sources"] = pre_sources
    if post_sources is not None:
        e["post_sources"] = post_sources
    if pre_source is not None:
        e["pre_source"] = pre_source
    if post_source is not None:
        e["post_source"] = post_source
    return e


# --- RESOLUTION ------------------------------------------------------------

def test_citation_resolving_to_a_real_row_passes():
    r = rc.check(inv(row("T001")), trust(entry("f", pre_sources=["[T001] RFC 1350 p.4"])),
                 None, False)
    assert r["ok"]
    assert r["encoded_cited"] == 1


def test_citation_to_unknown_row_is_an_error():
    r = rc.check(inv(row("T001")), trust(entry("f", pre_sources=["[T999] bogus"])),
                 None, False)
    assert not r["ok"]
    assert any("RESOLUTION" in e and "T999" in e for e in r["errors"])


def test_scalar_single_clause_shape_is_read():
    """A one-clause side emits pre_source, not pre_sources (SRC-CONJ-1 keeps the
    legacy scalar shape); the lint must read both."""
    r = rc.check(inv(row("T001")), trust(entry("f", pre_source="[T001] cite")), None, False)
    assert r["citations_found"] == 1
    assert r["ok"]


def test_multi_clause_array_reads_every_conjunct():
    r = rc.check(inv(row("T001"), row("T002"), row("T003")),
                 trust(entry("f", pre_sources=["[T001] a", "[T002] b"],
                             post_sources=["[T003] c"])), None, False)
    assert r["citations_found"] == 3
    assert r["encoded_cited"] == 3


def test_null_entries_in_a_source_array_are_skipped():
    """An unsourced conjunct rides as null in the array; it is not a citation."""
    r = rc.check(inv(row("T001")), trust(entry("f", pre_sources=["[T001] a", None])),
                 None, False)
    assert r["citations_found"] == 1


# --- DISPOSITION -----------------------------------------------------------

def test_citing_a_dispositioned_out_row_is_an_error():
    r = rc.check(inv(row("T001", disposition="Dispositioned out", reason="B1 timing")),
                 trust(entry("f", pre_sources=["[T001] cite"])), None, False)
    assert not r["ok"]
    assert any("DISPOSITION" in e for e in r["errors"])


def test_citing_a_modeled_row_is_allowed():
    r = rc.check(inv(row("T001", disposition="Deployment-modeled")),
                 trust(entry("f", pre_sources=["[T001] cite"])), None, False)
    assert r["ok"]


# --- COVERAGE --------------------------------------------------------------

def test_uncited_encoded_row_warns_by_default_and_fails_under_require_full():
    i = inv(row("T001"), row("T002"))
    t = trust(entry("f", pre_sources=["[T001] a"]))
    lenient = rc.check(i, t, None, False)
    assert lenient["ok"]
    assert lenient["encoded_uncited"] == ["T002"]
    assert any("COVERAGE" in w for w in lenient["warnings"])

    strict = rc.check(i, t, None, True)
    assert not strict["ok"]
    assert any("COVERAGE" in e for e in strict["errors"])


def test_dispositioned_out_rows_are_not_required_to_be_cited():
    r = rc.check(inv(row("T001"), row("T002", disposition="Dispositioned out")),
                 trust(entry("f", pre_sources=["[T001] a"])), None, True)
    assert r["ok"], r["errors"]


def test_core_row_citation_is_counted():
    r = rc.check(inv(row("T001", core=True), row("T002", core=True)),
                 trust(entry("f", pre_sources=["[T001] a"])), None, False)
    assert r["core_rows"] == 2
    assert r["core_cited"] == 1


# --- UNTAGGED --------------------------------------------------------------

def test_untagged_source_warns_by_default_and_fails_under_require_full():
    i = inv(row("T001"))
    t = trust(entry("f", pre_sources=["RFC 1350 p.4 with no tag"]))
    assert rc.check(i, t, None, False)["citations_untagged"] == 1
    assert rc.check(i, t, None, False)["ok"]
    assert not rc.check(i, t, None, True)["ok"]


# --- MONOPOLY --------------------------------------------------------------

def test_source_on_a_non_root_function_violates_the_monopoly():
    r = rc.check(inv(row("T001")),
                 trust(entry("spawned-helper", pre_sources=["[T001] a"])),
                 roots={"root-fn"}, require_full=False)
    assert not r["ok"]
    assert any("MONOPOLY" in e for e in r["errors"])


def test_source_on_a_root_function_is_fine():
    r = rc.check(inv(row("T001")),
                 trust(entry("root-fn", pre_sources=["[T001] a"])),
                 roots={"root-fn"}, require_full=False)
    assert r["ok"]


def test_monopoly_check_is_skipped_with_a_warning_when_roots_absent():
    r = rc.check(inv(row("T001")), trust(entry("f", pre_sources=["[T001] a"])), None, False)
    assert any("MONOPOLY" in w for w in r["warnings"])


# --- end to end ------------------------------------------------------------

def test_cli_exit_codes(tmp_path):
    i = tmp_path / "inv.json"
    t = tmp_path / "tr.json"
    i.write_text(json.dumps({"rows": [row("T001"), row("T002")]}))
    t.write_text(json.dumps(trust(entry("f", pre_sources=["[T001] a", "[T002] b"]))))
    assert rc.main(["--inventory", str(i), "--trust-report", str(t)]) == 0

    t.write_text(json.dumps(trust(entry("f", pre_sources=["[T404] nope"]))))
    assert rc.main(["--inventory", str(i), "--trust-report", str(t)]) == 1


def test_runs_against_the_real_committed_inventory():
    """The shipped TFTP inventory must load and report its true Encoded count."""
    p = SCRIPTS.parent / "experiments/rfc-swarm/data/inventory-dispositioned.json"
    if not p.exists():
        pytest.skip("TFTP inventory not present")
    i = rc.inventory_rows(json.load(open(p)))
    r = rc.check(i, {"entries": []}, None, False)
    assert r["inventory_rows"] == 124
    assert r["encoded_rows"] == 46
    assert r["core_rows"] == 15
    # No contracts authored yet, so every Encoded row is uncited: a warning, not an error.
    assert r["ok"]
    assert len(r["encoded_uncited"]) == 46
