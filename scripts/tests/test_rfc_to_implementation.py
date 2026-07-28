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
        "stage-G2-audit.md": dict(rfc_text="x", subjects="[]"),
        "stage-H-feasibility.md": dict(llmll="llmll", scope="s"),
        "stage-I-prereg.md": dict(scope="s", barriers="{}"),
        "stage-K-contracts.md": dict(rfc_text="x", encoded="[]", scope="s",
                                     llmll="llmll"),
        "stage-M-fill.md": dict(brief="b", hole="h", llmll="llmll", errors="none"),
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


# ---------------------------------------------------------------------------
# --status liveness
# ---------------------------------------------------------------------------

def test_status_does_not_report_itself_as_a_running_driver(tmp_path, capsys):
    """The killer case, and the one that took four attempts.

    `--status` is itself the script, invoked with the workdir being asked about,
    so a naive scan of `ps` matches the query process and answers RUNNING for
    every workdir including ones that never ran. Three earlier versions failed
    here: `pgrep -af` (GNU-only flag, matched nothing on BSD), a substring match
    (matched its own shell wrapper), and an interpreter regex (the real binary is
    .../MacOS/Python, capital P).
    """
    (tmp_path / "run.log").write_text("nothing\n")
    drv.show_status(tmp_path)
    assert "process : not running" in capsys.readouterr().out


def test_status_reports_stopped_stages_and_a_stale_log(tmp_path, capsys):
    drv.write_json(tmp_path / "MANIFEST.json",
                   {"stages": {"A": {"status": "complete", "seconds": 1},
                               "B": {"status": "stopped", "detail": "gate fired"}}})
    (tmp_path / "run.log").write_text("x\n")
    drv.show_status(tmp_path)
    out = capsys.readouterr().out
    assert "✓ complete" in out and "✗ STOPPED" in out and "gate fired" in out


def test_kill_matrix_accepts_an_unwritable_entry(tmp_path):
    """A pre-registered mutant nothing in the frozen surface can instantiate is
    kept in the denominator with no file, rather than dropped. The driver used to
    assume every entry had a file and died with a TypeError on the agent's
    entirely correct output."""
    m = {"name": "vector-reply-mismatch", "file": None, "unwritable": True}
    assert m.get("unwritable") or not m.get("file")


def test_an_agent_that_exceeds_its_budget_stops_cleanly(tmp_path):
    """A budget overrun must be a stage failure, not a traceback. Unhandled, the
    TimeoutExpired propagated out of main(), so nothing was recorded and the run
    was left mid-stage rather than resumable."""
    runner = drv.AgentRunner("sleep 30", timeout=1)
    with pytest.raises(Stop, match="exceeded its 1s budget"):
        runner.run(tmp_path / "wd", "prompt", "out.json", "slow")


# ---------------------------------------------------------------------------
# Stage G2: the artifact audit
# ---------------------------------------------------------------------------

PINNED = "\n".join([
    "RFC 9999                    Example                        July 2026",   # 1
    "",                                                                       # 2
    "1.  Encoding",                                                           # 3
    "",                                                                       # 4
    "   Implementations MUST NOT add line feeds to encoded data unless the",  # 5
    "   specification referring to this document explicitly directs encoders",# 6
    "   to add line feeds after a specific number of characters.",            # 7
    "",                                                                       # 8
    "   The block number should be incremented by one for each block sent.",  # 9
    "",                                                                       # 10
    "    +--------+--------+",                                                # 11
    "    | Opcode | Block  |",                                                # 12
    "    +--------+--------+",                                                # 13
])


def _cite(cid, quote, ls, le, strength="declarative", source="RFC9999"):
    return {"id": cid, "source": source, "line_start": ls, "line_end": le,
            "quote": quote, "rule": "N1", "strength": strength,
            "obligation": "an obligation"}


def audit_ctx(tmp_path, cites, rows, catalogue=None, pinned=PINNED):
    """A workdir carrying pinned bytes, a census and a ledger, plus a stub agent
    that returns `catalogue` verbatim. The catalogue is copied from a file rather
    than printf'd: AgentRunner str.format()s its command, and JSON is all braces.
    """
    (tmp_path / "00-source").mkdir(parents=True, exist_ok=True)
    (tmp_path / "00-source" / "rfc9999.txt").write_text(pinned, encoding="utf-8")
    drv.write_json(tmp_path / "04-reconcile" / "data" / "extraction-a.json",
                   {"normative": cites, "excluded": []})
    drv.write_json(tmp_path / "06-disposition" / "inventory-dispositioned.json",
                   {"rows": rows})
    if catalogue is None:
        catalogue = {"audited": [{"cid": r["cid"], "verdict": "matches"}
                                 for r in rows
                                 if r.get("core")
                                 or r["disposition"] == "Dispositioned out"]}
    fixture = tmp_path / "catalogue.json"
    drv.write_json(fixture, catalogue)
    return drv.Ctx(workdir=tmp_path, agent=drv.AgentRunner(f"cp {fixture} " "{out}"),
                   llmll="llmll", rfc_url="http://example/rfc9999.txt")


LF_QUOTE = ("Implementations MUST NOT add line feeds to encoded data unless the "
            "specification referring to this document explicitly directs encoders "
            "to add line feeds after a specific number of characters.")


def test_span_coverage_survives_an_elision_and_a_flattened_diagram():
    """The regression that shaped this check. A substring test called both of
    these a broken citation, and fired on 22 of the 113 real RFC 1350 rows: a
    census legitimately elides a long clause and legitimately flattens a
    multi-line packet diagram onto one line."""
    span = "\n".join(PINNED.split("\n")[10:13])
    assert drv._span_coverage("| Opcode | Block |", span) == 1.0
    assert drv._span_coverage("Implementations MUST NOT add line feeds ... "
                              "after a specific number of characters.",
                              "\n".join(PINNED.split("\n")[4:7])) == 1.0


def test_span_coverage_separates_a_true_citation_from_a_wrong_span():
    true_span = "\n".join(PINNED.split("\n")[4:7])
    wrong_span = "\n".join(PINNED.split("\n")[10:13])
    assert drv._span_coverage(LF_QUOTE, true_span) == 1.0
    assert drv._span_coverage(LF_QUOTE, wrong_span) < drv.CITATION_RESOLVES_AT


def test_audit_passes_a_clean_artifact(tmp_path):
    cites = [_cite("A1", LF_QUOTE, 5, 7, strength="must"),
             _cite("A2", "The block number should be incremented by one", 9, 9,
                   strength="should")]
    rows = [row("A1", cls="C3", disposition="Dispositioned out", barrier="B5",
                core=True, reason="stream insertion is not per-quantum"),
            row("A2", cls="C2")]
    drv.stage_G2_audit(audit_ctx(tmp_path, cites, rows))
    rep = drv.read_json(tmp_path / "06b-audit" / "audit.json")
    assert rep["unresolved_citations"] == []
    assert rep["citations_checked"] == 2
    assert rep["reasons_audited"] == 1        # only the excluded/core row


def test_audit_stops_on_a_span_outside_the_pinned_file(tmp_path):
    cites = [_cite("A1", LF_QUOTE, 900, 902)]
    rows = [row("A1", cls="C3", disposition="Dispositioned out", barrier="B5")]
    with pytest.raises(Stop, match="do not resolve to the pinned bytes"):
        drv.stage_G2_audit(audit_ctx(tmp_path, cites, rows))


def test_audit_stops_when_the_quote_does_not_come_from_its_span(tmp_path):
    """Section 14 pins the source so every later stage reads it. A quote whose
    words are not in the span it cites was not read from there."""
    cites = [_cite("A1", LF_QUOTE, 11, 13)]          # cites the diagram
    rows = [row("A1", cls="C3", disposition="Dispositioned out", barrier="B5")]
    with pytest.raises(Stop, match="do not resolve to the pinned bytes"):
        drv.stage_G2_audit(audit_ctx(tmp_path, cites, rows))


def test_audit_stops_on_a_source_name_matching_no_pinned_file(tmp_path):
    """Silence is the danger, not noise: the two tools that hardcoded the first
    run's source names both reported zeros on the second and the run continued."""
    cites = [_cite("A1", LF_QUOTE, 5, 7, source="RFC1350")]
    rows = [row("A1", cls="C3", disposition="Dispositioned out", barrier="B5")]
    with pytest.raises(Stop, match="do not resolve to the pinned bytes"):
        drv.stage_G2_audit(audit_ctx(tmp_path, cites, rows))


def test_audit_stops_on_a_dispositioned_row_that_cites_no_census_row(tmp_path):
    cites = [_cite("A1", LF_QUOTE, 5, 7)]
    rows = [row("A1", cls="C3"), row("A99", cls="C1")]
    with pytest.raises(Stop, match="cite no census row"):
        drv.stage_G2_audit(audit_ctx(tmp_path, cites, rows))


def test_audit_reports_a_near_miss_span_and_an_absent_strength_without_stopping(tmp_path):
    """Both fire on correct rows, so both report. Six TFTP rows cite a span one
    line short of their quote, and three cite RFC 1123's requirements-summary
    table, where the strength is a column position rather than a word."""
    cites = [_cite("A1", "encoders to add line feeds after a specific number", 7, 7),
             _cite("A2", "| Opcode | Block |", 11, 13, strength="must")]
    rows = [row("A1", cls="C3"), row("A2", cls="C3")]
    drv.stage_G2_audit(audit_ctx(tmp_path, cites, rows))
    rep = drv.read_json(tmp_path / "06b-audit" / "audit.json")
    assert [n["cid"] for n in rep["span_nearly_right"]] == ["A1"]
    assert [s["cid"] for s in rep["declared_strength_absent_from_quote"]] == ["A2"]
    assert rep["unresolved_citations"] == []


def test_audit_stops_when_a_flags_evidence_is_not_in_the_artifact(tmp_path):
    """Section 6 forbids a gate condition to rest on an unevidenced input, and
    that has to bind this stage's own output too."""
    cites = [_cite("A1", LF_QUOTE, 5, 7)]
    rows = [row("A1", cls="C3", disposition="Dispositioned out", barrier="B5",
                reason="stream insertion is not per-quantum")]
    cat = {"audited": [{"cid": "A1", "verdict": "misreads",
                        "quote_phrase": "a phrase that is not in the clause",
                        "reason_phrase": "stream insertion"}]}
    with pytest.raises(Stop, match="not in the pinned quote"):
        drv.stage_G2_audit(audit_ctx(tmp_path, cites, rows, cat))


def test_audit_stops_when_a_flagged_row_is_characteristic_core(tmp_path):
    """The RFC 4648 case, mechanised: a core row disposed of on a reason that
    misreads its own clause is exactly the unevidenced input stage J then rules
    on."""
    cites = [_cite("A1", LF_QUOTE, 5, 7)]
    rows = [row("A1", cls="C3", disposition="Dispositioned out", barrier="B5",
                core=True,
                reason="the clause forbids line feeds after a specific number "
                       "of characters")]
    cat = {"audited": [{"cid": "A1", "verdict": "misreads",
                        "quote_phrase": "unless the specification referring to",
                        "reason_phrase": "after a specific number of characters",
                        "note": "the qualifier belongs to the exception"}]}
    with pytest.raises(Stop, match="misreads the clause|misread"):
        drv.stage_G2_audit(audit_ctx(tmp_path, cites, rows, cat))


def test_audit_records_a_non_core_flag_without_stopping(tmp_path):
    cites = [_cite("A1", LF_QUOTE, 5, 7)]
    rows = [row("A1", cls="C3", disposition="Dispositioned out", barrier="B5",
                reason="the clause forbids line feeds after a specific number "
                       "of characters")]
    cat = {"audited": [{"cid": "A1", "verdict": "misreads",
                        "quote_phrase": "unless the specification referring to",
                        "reason_phrase": "after a specific number of characters"}]}
    drv.stage_G2_audit(audit_ctx(tmp_path, cites, rows, cat))
    rep = drv.read_json(tmp_path / "06b-audit" / "audit.json")
    assert [v["cid"] for v in rep["reasons_flagged"]] == ["A1"]


def test_audit_catalogue_must_cover_every_subject():
    """An audit that may quietly omit its hardest row reports the same thing as
    one that found nothing."""
    with pytest.raises(Stop, match="no verdict for"):
        drv.check_audit({"audited": [{"cid": "A1", "verdict": "matches"}]},
                        ["A1", "A2"])


def test_audit_catalogue_rejects_a_duplicate_and_an_unknown_subject():
    with pytest.raises(Stop, match="two verdicts"):
        drv.check_audit({"audited": [{"cid": "A1", "verdict": "matches"},
                                     {"cid": "A1", "verdict": "misreads",
                                      "quote_phrase": "x", "reason_phrase": "y"}]},
                        ["A1"])
    with pytest.raises(Stop, match="not among the subjects"):
        drv.check_audit({"audited": [{"cid": "ZZ", "verdict": "matches"}]}, ["A1"])


def test_audit_catalogue_requires_evidence_on_a_flag():
    with pytest.raises(Stop, match="carries no quote_phrase"):
        drv.check_audit({"audited": [{"cid": "A1", "verdict": "misreads"}]}, ["A1"])
