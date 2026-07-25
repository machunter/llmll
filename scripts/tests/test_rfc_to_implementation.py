"""RFC-SWARM driver tests (scripts/rfc_to_implementation.py).

Synthetic inputs and stub agents only: the driver's gates and schema checks are
exercised without a model or a compiler, so these tests stay fast and cannot be
perturbed by a stale binary or a network hiccup.

The point of most of these is NEGATIVE: a gate that never fires is decorative,
so each STOP condition is driven into firing on purpose.
"""
import importlib.util
import pathlib
import sys

import pytest

SCRIPTS = pathlib.Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location(
    "rfc_to_implementation", SCRIPTS / "rfc_to_implementation.py")
assert spec and spec.loader
drv = importlib.util.module_from_spec(spec)
sys.modules["rfc_to_implementation"] = drv
spec.loader.exec_module(drv)

Stop = drv.StopCondition


def row(cid, cls="C1", disposition="Encoded", core=False, barrier=None,
        reason="a named contract shape"):
    r = {"cid": cid, "class": cls, "disposition": disposition,
         "core": core, "reason": reason}
    if barrier:
        r["barrier"] = barrier
    return r


def ctx(tmp_path, rows=None):
    c = drv.Ctx(workdir=tmp_path, agent=drv.AgentRunner("true"), llmll="llmll",
                rfc_url="http://example/rfc.txt")
    if rows is not None:
        drv.write_json(tmp_path / "06-disposition" / "inventory-dispositioned.json",
                       {"rows": rows})
    return c


# ---------------------------------------------------------------------------
# Stage J: the gate
# ---------------------------------------------------------------------------

def test_gate_passes_when_core_intact_and_barriers_cited(tmp_path):
    rows = [row("T1", core=True), row("T2"),
            row("T3", cls="C6", disposition="Dispositioned out", barrier="B1")]
    drv.stage_J_gate(ctx(tmp_path, rows))
    rep = drv.read_json(tmp_path / "09-gate" / "gate.json")
    assert rep["characteristic_core"]["dispositioned_out"] == []
    assert rep["exclusions_outside_barrier_list"] == []


def test_gate_stops_when_a_core_row_is_dispositioned_out(tmp_path):
    """The condition that decides the target. Re-scope, never re-grade."""
    rows = [row("T1", core=True, disposition="Dispositioned out", barrier="B1"),
            row("T2")]
    with pytest.raises(Stop, match="characteristic-core rows dispositioned out"):
        drv.stage_J_gate(ctx(tmp_path, rows))


def test_gate_stops_on_an_exclusion_outside_the_closed_barrier_list(tmp_path):
    """The replacement for the retired ratio ceiling: catches the exclusion
    nobody can justify, which a percentage never could."""
    rows = [row("T1"), row("T2", disposition="Dispositioned out", barrier="B99")]
    with pytest.raises(Stop, match="citing no barrier from the closed list"):
        drv.stage_J_gate(ctx(tmp_path, rows))


def test_gate_reports_coverage_but_does_not_threshold_it(tmp_path):
    """Coverage is REPORTED. A ratio ceiling measures the RFC's genre
    composition, not the verifier's reach, so it must not gate."""
    rows = [row(f"T{i}", cls="C6", disposition="Dispositioned out", barrier="B2")
            for i in range(50)] + [row("T99", core=True)]
    drv.stage_J_gate(ctx(tmp_path, rows))  # must not raise
    rep = drv.read_json(tmp_path / "09-gate" / "gate.json")
    assert rep["verifiable_subject_matter"]["carried"] == 1
    assert "not thresholded" in rep["verifiable_subject_matter"]["note"].lower()


# ---------------------------------------------------------------------------
# Schema checks on agent output
# ---------------------------------------------------------------------------

def _extraction(**over):
    r = {"id": "A1", "source": "RFC1350", "line_start": 93, "line_end": 94,
         "quote": "q", "rule": "N3", "obligation": "x"}
    r.update(over)
    return {"extractor": "A", "normative": [r], "excluded": []}


def test_extraction_accepts_the_shape_reconcile_consumes():
    doc = drv.check_extraction(_extraction(), "a")
    assert doc["counts"] == {"normative": 1, "excluded": 0}


def test_extraction_requires_integer_line_spans():
    """reconcile.py matches by line-span overlap; a string span silently becomes
    a coverage disagreement that never happened."""
    with pytest.raises(Stop, match="non-integer line_start/line_end"):
        drv.check_extraction(_extraction(line_start="93", line_end="94"), "a")
    with pytest.raises(Stop, match="line_start > line_end"):
        drv.check_extraction(_extraction(line_start=94, line_end=93), "a")


def test_extraction_rejects_a_bare_array():
    """The old, wrong shape. reconcile.py reads {"normative": [...]}."""
    with pytest.raises(Stop, match="not a bare array"):
        drv.check_extraction([], "a")


def test_extraction_rejects_missing_fields_and_an_empty_census():
    with pytest.raises(Stop, match="missing"):
        drv.check_extraction({"normative": [{"id": "A1"}], "excluded": []}, "a")
    with pytest.raises(Stop, match="'normative' is empty"):
        drv.check_extraction({"normative": [], "excluded": []}, "a")
    with pytest.raises(Stop, match="missing or non-list 'excluded'"):
        drv.check_extraction({"normative": [_extraction()["normative"][0]]}, "a")


def test_disposition_requires_a_barrier_on_every_exclusion():
    with pytest.raises(Stop, match="not in the closed list"):
        drv.check_dispositioned({"rows": [
            row("T1", disposition="Dispositioned out", barrier=None)]})


def test_disposition_rejects_an_unknown_disposition_or_class():
    with pytest.raises(Stop, match="expected one of"):
        drv.check_dispositioned({"rows": [row("T1", disposition="Probably fine")]})
    with pytest.raises(Stop, match="expected C1..C6"):
        drv.check_dispositioned({"rows": [row("T1", cls="C9")]})


# ---------------------------------------------------------------------------
# Agent contract
# ---------------------------------------------------------------------------

def test_agent_that_exits_zero_without_writing_output_is_a_hard_failure(tmp_path):
    """Silently skipping an agent stage would hollow out the denominator and the
    citations, which are the only things making the claim checkable."""
    runner = drv.AgentRunner("true")
    with pytest.raises(Stop, match="wrote no result.json"):
        runner.run(tmp_path / "wd", "prompt", "result.json", "test")


def test_agent_nonzero_exit_stops_the_run(tmp_path):
    runner = drv.AgentRunner("exit 3")
    with pytest.raises(Stop, match="exited 3"):
        runner.run(tmp_path / "wd", "prompt", "result.json", "test")


def test_agent_output_is_accepted_when_the_contract_is_met(tmp_path):
    runner = drv.AgentRunner("printf '[]' > {out}")
    out = runner.run(tmp_path / "wd", "prompt", "result.json", "test")
    assert out.exists() and out.read_text() == "[]"


# ---------------------------------------------------------------------------
# Prompt rendering
# ---------------------------------------------------------------------------

def test_unfilled_prompt_placeholder_is_a_hard_failure(tmp_path):
    """A half-rendered prompt silently drops an instruction; better to stop."""
    c = ctx(tmp_path)
    with pytest.raises(Stop, match="unfilled placeholders"):
        c.prompt("stage-D-extract.md", rfc_text="x")  # rubric/extractor missing


def test_every_shipped_prompt_renders_with_its_documented_placeholders(tmp_path):
    """Guards against a prompt and its call site drifting apart."""
    c = ctx(tmp_path)
    supplied = {
        "stage-B-scope.md": dict(rfc_text="x", provenance="{}"),
        "stage-C-rubric.md": dict(rfc_text="x"),
        "stage-D-extract.md": dict(rfc_text="x", rubric="r", extractor="A"),
        "stage-F-core.md": dict(rfc_text="x", inventory="[]"),
        "stage-G-disposition.md": dict(rfc_text="x", inventory="[]", core_ids="[]",
                                       barriers="{}", scope="s"),
        "stage-H-feasibility.md": dict(llmll="llmll", scope="s"),
        "stage-I-prereg.md": dict(scope="s", barriers="{}"),
        "stage-K-contracts.md": dict(rfc_text="x", encoded="[]", scope="s",
                                     llmll="llmll"),
        "stage-M-fill.md": dict(brief="b", hole="h", llmll="llmll"),
        "stage-N-mutants.md": dict(tree="t", prereg="p"),
        "stage-O-writeup.md": dict(gate="{}", coverage="", kill_matrix="[]",
                                   wave="{}", reconcile="{}"),
    }
    for name, kw in supplied.items():
        assert c.prompt(name, **kw)


# ---------------------------------------------------------------------------
# Blindness
# ---------------------------------------------------------------------------

def test_blindness_audit_flags_a_leak_between_extractors(tmp_path):
    """If extractor A can see B's rows, the agreement statistic measures
    copying, which is the one thing dual extraction exists to rule out."""
    for tag in ("a", "b"):
        d = tmp_path / "03-extraction" / tag
        d.mkdir(parents=True)
        (d / "extraction.json").write_text("[]")
    assert drv.audit_blindness(tmp_path) == 0
    (tmp_path / "03-extraction" / "a" / "extraction-b.json").write_text("[]")
    assert drv.audit_blindness(tmp_path) == 1


# ---------------------------------------------------------------------------
# Source presentation
# ---------------------------------------------------------------------------

def test_sources_are_presented_with_newline_only_line_numbers(tmp_path):
    """RFC page breaks are form feeds; splitlines() would renumber around them
    and desynchronise every cited span."""
    src = tmp_path / "00-source"
    src.mkdir(parents=True)
    (src / "rfc.txt").write_text("alpha\n\x0cbeta\ngamma\n")
    text = drv._sources_text(ctx(tmp_path))
    assert "    1| alpha" in text
    assert "    2| \x0cbeta" in text
    assert "    3| gamma" in text
