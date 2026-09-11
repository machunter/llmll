"""Cover for experiments/rfc-swarm/tools/clause2_compare.py.

The comparator decides DRIVER-LL acceptance clause 2 over a live run directory.
No live run exists in this repository and none can, so every cell here builds a
synthetic run under tmp_path from the REFERENCE's own stage table. That is the
same discipline the driver cover uses: assert against the reference, never
against the port's copy of it.

FOUR CELLS ARE NEGATIVE CONTROLS AND THEY ARE THE POINT.

  * `test_the_gate_removed_control` deletes the T4 check and asserts the cell
    that should fail then passes. Without it, a T4 that never fires would look
    identical to a T4 that fires correctly.
  * `test_an_empty_manifest_fails_loudly` asserts that a run recording nothing
    FAILS rather than passing over an empty population. A gate with no rows to
    reject rejects nothing, and this campaign has shipped that failure before.
  * `test_the_floor_drift_guard_fires` feeds a reference whose floors moved and
    asserts T0 catches it. The comparator encodes the floors, so this is what
    stops the encoded copy drifting away from the source it claims to mirror.
  * `test_the_model_pin_removed_control` removes P2 and asserts the run that
    must fail then passes. Its input is the oracle's OWN agent invocation,
    which names a binary and no model, so the witness is not hypothetical.

Every assertion reads the tool's own verdict LINE. None reads an exit status
alone: a status cannot distinguish a pass from a check that did not run.
"""
from __future__ import annotations

import importlib.util
import json
import pathlib
import sys

import pytest

REPO = pathlib.Path(__file__).resolve().parents[2]
TOOL = REPO / "experiments" / "rfc-swarm" / "tools" / "clause2_compare.py"
REFERENCE = REPO / "scripts" / "rfc_to_implementation.py"
ORACLE = REPO / "experiments" / "rfc-swarm" / "runs" / "rfc826"


def _load(path: pathlib.Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod  # see clause2_compare.load_reference for why
    spec.loader.exec_module(mod)
    return mod


cmp_mod = _load(TOOL, "clause2_compare")
ref = _load(REFERENCE, "rfc_reference_for_clause2")
STAGES = list(ref.STAGES)


_OMIT = object()

# The section 6.2 sidecar a compliant operator writes. Every cell in this file
# gets one by default, because P1 and P2 are thresholded: a builder that omitted
# it would fail all seventeen pre-existing cells at once rather than the one
# under test.
GOOD_PROV = {"agent_exe": "claude",
             "agent_args": ["--model", "claude-opus-5", "-p", "{prompt}"],
             "model": "claude-opus-5",
             "llmll_version": "v0.23.1",
             "driver_commit": "e49e968",
             "date": "2026-09-11"}


def _run_dir(tmp_path: pathlib.Path, *, drop: str | None = None,
             sizes: dict[str, int] | None = None,
             halt: tuple[str, str] | None = None,
             prov=_OMIT) -> pathlib.Path:
    """Build a synthetic run whose every stage is complete, then perturb one thing.

    `drop` removes a stage's manifest row. `sizes` overrides a stage's declared
    artifact size. `halt` records (stage_key, detail) as a stopped row. `prov`
    replaces the section 6.2 sidecar; pass None to write no sidecar at all.
    """
    run = tmp_path / "run"
    run.mkdir(exist_ok=True)
    stages: dict[str, dict] = {}
    for st in STAGES:
        if st.key == drop:
            continue
        if halt and st.key == halt[0]:
            stages[st.key] = {"status": "stopped", "detail": halt[1],
                              "clause": "driver-spec sec 6:229-231",
                              "outcome": "ConditionUnmet"}
            continue
        stages[st.key] = {"status": "complete", "kind": st.kind, "seconds": 0.1,
                          "outputs": {o: "deadbeef" for o in st.outputs}}
        for o in st.outputs:
            p = run / o
            p.parent.mkdir(parents=True, exist_ok=True)
            size = (sizes or {}).get(st.key, 1000)
            if o.endswith(".json") and size > 0:
                # A declared .json artifact must BE json: the reported half reads
                # some of these, and filler bytes would exercise the unreadable
                # path instead of the one under test.
                body = json.dumps({"pad": "x" * max(size - 14, 1)})
            else:
                body = "x" * size
            p.write_text(body, encoding="utf-8")
    (run / "MANIFEST.json").write_text(
        json.dumps({"rfc_url": "https://example.invalid/rfc826.txt", "stages": stages},
                   indent=1), encoding="utf-8")
    if prov is _OMIT:
        prov = GOOD_PROV
    if prov is not None:
        (run / "RUN-PROVENANCE.json").write_text(
            prov if isinstance(prov, str) else json.dumps(prov), encoding="utf-8")
    return run


def _verdict(capsys) -> str:
    return capsys.readouterr().out


def _call(run: pathlib.Path, capture: pathlib.Path | None = None) -> int:
    argv = ["--run", str(run), "--oracle", str(ORACLE)]
    if capture is not None:
        argv += ["--stdout", str(capture)]
    return cmp_mod.main(argv)


def test_a_complete_run_passes(tmp_path, capsys):
    rc = _call(_run_dir(tmp_path))
    out = _verdict(capsys)
    assert "CLAUSE-2 PASS" in out, out
    assert rc == 0


def test_every_reference_stage_is_enumerated(tmp_path, capsys):
    """Sixteen, not fifteen: the specification's A..O plus G2, the artifact audit."""
    _call(_run_dir(tmp_path))
    out = _verdict(capsys)
    assert len(STAGES) == 16, "the reference stage table moved; the comparator must follow"
    assert "terminal state over all 16 enumerated stages" in out, out


def test_a_missing_stage_row_fails_T1(tmp_path, capsys):
    rc = _call(_run_dir(tmp_path, drop="G2"))
    out = _verdict(capsys)
    assert "FAIL         T1" in out and "no row for G2" in out, out
    assert "CLAUSE-2 FAIL" in out and rc == 1


def test_an_empty_manifest_fails_loudly(tmp_path, capsys):
    """NEGATIVE CONTROL. An empty population must not pass by having nothing to reject."""
    run = tmp_path / "empty"
    run.mkdir()
    (run / "MANIFEST.json").write_text(json.dumps({"stages": {}}), encoding="utf-8")
    rc = _call(run)
    out = _verdict(capsys)
    assert "FAIL         T1" in out and "a run that did not happen" in out, out
    assert rc == 1


def test_an_absent_manifest_fails(tmp_path, capsys):
    run = tmp_path / "bare"
    run.mkdir()
    rc = _call(run)
    out = _verdict(capsys)
    assert "CLAUSE-2 FAIL" in out and "recorded nothing" in out, out
    assert rc == 1


def test_a_complete_over_an_artifact_below_the_floor_fails_T4(tmp_path, capsys):
    """Stage B declares a 200-byte floor. 200 is NOT above it; the reference uses `>`."""
    rc = _call(_run_dir(tmp_path, sizes={"B": 200}))
    out = _verdict(capsys)
    assert "FAIL         T4" in out and "floor 200" in out, out
    assert rc == 1


def test_a_complete_one_byte_above_the_floor_passes_T4(tmp_path, capsys):
    """The boundary is asserted on both sides, so an off-by-one cannot hide."""
    rc = _call(_run_dir(tmp_path, sizes={"B": 201}))
    out = _verdict(capsys)
    assert "ok           T4" in out, out
    assert rc == 0


def test_a_complete_over_an_absent_artifact_fails_T4(tmp_path, capsys):
    run = _run_dir(tmp_path)
    victim = next(o for st in STAGES for o in st.outputs)
    (run / victim).unlink()
    rc = _call(run)
    out = _verdict(capsys)
    assert "FAIL         T4" in out and "absent (presence)" in out, out
    assert rc == 1


def test_the_floor_drift_guard_fires(tmp_path, capsys):
    """NEGATIVE CONTROL on the comparator's own copy of the reference's floors."""
    fake = tmp_path / "moved_reference.py"
    fake.write_text(REFERENCE.read_text(encoding="utf-8")
                    .replace("st_size > 200", "st_size > 999"), encoding="utf-8")
    cmp_mod.main(["--run", str(_run_dir(tmp_path)), "--oracle", str(ORACLE),
                  "--reference", str(fake)])
    out = _verdict(capsys)
    assert "FAIL         T0" in out and "floor drift" in out, out


def test_a_halt_not_named_on_the_output_fails_T3(tmp_path, capsys):
    run = _run_dir(tmp_path, halt=("J", "gate J: a characteristic-core row was excluded"))
    capture = tmp_path / "console.txt"
    capture.write_text("stage J [gate] the gate\n", encoding="utf-8")
    rc = _call(run, capture)
    out = _verdict(capsys)
    assert "FAIL         T3" in out, out
    assert rc == 1


def test_a_halt_named_on_the_output_passes_T3(tmp_path, capsys):
    detail = "gate J: a characteristic-core row was excluded"
    run = _run_dir(tmp_path, halt=("J", detail))
    capture = tmp_path / "console.txt"
    capture.write_text(f"STOP at stage J: {detail}\n", encoding="utf-8")
    _call(run, capture)
    out = _verdict(capsys)
    assert "ok           T3" in out, out


def test_T3_is_not_checked_without_a_capture(tmp_path, capsys):
    """Fail-closed on the CHECK's availability, not on the run."""
    _call(_run_dir(tmp_path, halt=("J", "some reason")))
    out = _verdict(capsys)
    assert "NOT CHECKED  T3" in out and "operator's output" in out, out


def test_T5_reports_not_checked_and_names_the_reason(tmp_path, capsys):
    """The stopped-for-failed item is BLOCKED, and the tool says so rather than guessing.

    Proposal Rev 16 item 5 compares against the reference's recorded status. That
    lives in MANIFEST.json and no committed run carries one, which is the same
    ground on which Rev 16 retired the missing-manifest finding for stage status.
    The tool must not substitute a different reading to make the cell green.
    """
    _call(_run_dir(tmp_path))
    out = _verdict(capsys)
    assert "NOT CHECKED  T5" in out, out
    assert "no committed run carries one" in out.lower() or "NO committed run" in out, out


_WAVE_FILLS = {
    "fills": [{"hole": f"h{i}", "status": "filled", "attempts": 1} for i in range(18)]
             + [{"hole": "h18", "status": "finding", "attempts": 3}]}


def test_a_divergent_wave_partition_is_reported_and_does_not_fail(tmp_path, capsys):
    """The reported half is recorded with n and never gates.

    THE PATH IS STAGED. Stage M declares `12-wave/wave.json` and that is where a
    run writes it; `_run_dir` already lays every declared output down at its
    staged path.
    """
    run = _run_dir(tmp_path)
    (run / "12-wave" / "wave.json").write_text(json.dumps(_WAVE_FILLS), encoding="utf-8")
    rc = _call(run)
    out = _verdict(capsys)
    assert "CLAUSE-2 PASS" in out, out
    assert "R5 wave partition" in out and "'filled': 18" in out, out
    assert rc == 0


def test_a_wave_json_at_the_run_root_is_not_read(tmp_path, capsys):
    """NEGATIVE CONTROL for the staged path, and the cell above is not one.

    The tool read `<run>/wave.json` until 2026-09-11 and its fixture wrote there,
    so tool and test agreed on a path no run produces. With only the cell above,
    moving the read back to the root would still pass by moving the fixture with
    it. This cell fails in that direction: the root file carries a partition the
    staged file does not, so R5 names which path was read.

    The decoy status is a string that appears in NEITHER the staged fixture nor
    the oracle. `runs/rfc826/wave.json` carries one real `checkout-failed`, so a
    decoy using that status would be masked by the oracle half of the R5 line.
    """
    run = _run_dir(tmp_path)
    (run / "12-wave" / "wave.json").write_text(json.dumps(_WAVE_FILLS), encoding="utf-8")
    (run / "wave.json").write_text(json.dumps(
        {"fills": [{"hole": "decoy", "status": "read-the-run-root"}]}), encoding="utf-8")
    _call(run)
    out = _verdict(capsys)
    assert "'filled': 18" in out, f"the staged wave.json was not the one read\n{out}"
    assert "read-the-run-root" not in out, f"the run-root wave.json was read\n{out}"


def test_the_gate_removed_control(tmp_path, capsys, monkeypatch):
    """NEGATIVE CONTROL. With T4 deleted, the cell that must fail passes instead."""
    monkeypatch.setattr(cmp_mod, "t4_complete_shape", lambda *_args, **_kw: None)
    rc = _call(_run_dir(tmp_path, sizes={"B": 0}))
    out = _verdict(capsys)
    assert "FAIL         T4" not in out, "T4 was removed; it must not report"
    assert "CLAUSE-2 PASS" in out, out
    assert rc == 0


def test_the_oracle_the_cover_reads_is_the_committed_run():
    """The reported half is worthless if the oracle moved. Pin what it must contain."""
    assert ORACLE.is_dir(), "runs/rfc826 is the only valid oracle; see proposal Rev 16"
    wave = json.loads((ORACLE / "wave.json").read_text(encoding="utf-8"))
    statuses = [f.get("status") for f in wave["fills"]]
    assert len(statuses) == 22, "the oracle wave moved; re-derive the reported figures"
    assert statuses.count("filled") == 21 and statuses.count("checkout-failed") == 1
    gate = json.loads((ORACLE / "gate.json").read_text(encoding="utf-8"))
    assert gate["characteristic_core"]["dispositioned_out"] == []
    assert gate["exclusions_outside_barrier_list"] == []


@pytest.mark.skipif(not ORACLE.is_dir(), reason="the committed oracle is absent")
def test_the_reported_half_names_no_oracle_for_stage_status(tmp_path, capsys):
    """Rev 16 moved stage status to clause 1a. The tool must say so, not infer a value."""
    _call(_run_dir(tmp_path))
    out = _verdict(capsys)
    assert "R1 stage status" in out and "NO ORACLE" in out, out


# --------------------------------------------------------------------------
# P1 and P2: the model pin, pre-registration section 6.2 (Rev 3).
# --------------------------------------------------------------------------
def test_a_run_with_no_provenance_fails_P1(tmp_path, capsys):
    """Both obligations are unmet by one omission, and both say so separately."""
    rc = _call(_run_dir(tmp_path, prov=None))
    out = _verdict(capsys)
    assert "FAIL         P1" in out and "RUN-PROVENANCE.json is absent" in out, out
    assert "FAIL         P2" in out, out
    assert "CLAUSE-2 FAIL" in out and rc == 1


def test_a_provenance_missing_a_field_fails_P1(tmp_path, capsys):
    """The cell names the missing field. A generic parse error would not locate it."""
    bad = {k: v for k, v in GOOD_PROV.items() if k != "driver_commit"}
    rc = _call(_run_dir(tmp_path, prov=bad))
    out = _verdict(capsys)
    assert "FAIL         P1" in out and "driver_commit" in out, out
    assert rc == 1


def test_unreadable_provenance_fails_P1_without_killing_the_run(tmp_path, capsys):
    """A malformed sidecar must not stop the other cells from reporting."""
    rc = _call(_run_dir(tmp_path, prov="{not json"))
    out = _verdict(capsys)
    assert "FAIL         P1" in out and "not readable JSON" in out, out
    assert "T1" in out and "T4" in out, "the other cells must still report"
    assert rc == 1


def test_an_undeclared_model_fails_P2(tmp_path, capsys):
    bad = {**GOOD_PROV, "model": ""}
    rc = _call(_run_dir(tmp_path, prov=bad))
    out = _verdict(capsys)
    assert "FAIL         P2" in out and "declared no model" in out, out
    assert rc == 1


def test_the_oracle_invocation_shape_fails_P2(tmp_path, capsys):
    """POSITIVE WITNESS. The minimal firing input, and it is not hypothetical.

    This is the oracle's own agent invocation (runs/rfc826/RESULTS.md:175)
    translated into the port's --agent-exe / --agent-arg flags. It names the
    binary and no model, which is exactly the section 4.2 defect. The run that
    produced the oracle would fail this cell, which is the point of the cell.
    """
    bad = {**GOOD_PROV,
           "agent_args": ["-p", "{prompt}", "--allowedTools", "Read,Write,Bash",
                          "--permission-mode", "acceptEdits"]}
    rc = _call(_run_dir(tmp_path, prov=bad))
    out = _verdict(capsys)
    assert "FAIL         P2" in out and "appears in NO element" in out, out
    assert "CLAUSE-2 FAIL" in out and rc == 1


def test_a_model_only_in_an_unrelated_argument_fails_P2(tmp_path, capsys):
    """The test is over ELEMENTS. A substring test over the join would pass this."""
    bad = {**GOOD_PROV, "model": "opus",
           "agent_args": ["--workdir", "/tmp/opus-run", "-p", "{prompt}"]}
    rc = _call(_run_dir(tmp_path, prov=bad))
    out = _verdict(capsys)
    assert "FAIL         P2" in out, out
    assert rc == 1


def test_both_invocation_styles_pass_P2(tmp_path, capsys):
    """--model X and --model=X are both admitted; neither is imposed on the operator."""
    joined = {**GOOD_PROV, "agent_args": ["--model=claude-opus-5", "-p", "{prompt}"]}
    rc = _call(_run_dir(tmp_path, prov=joined))
    out = _verdict(capsys)
    assert "ok           P2" in out and "CLAUSE-2 PASS" in out, out
    assert rc == 0


def test_the_model_pin_removed_control(tmp_path, capsys, monkeypatch):
    """NEGATIVE CONTROL. Remove P2 and assert the run that must fail then passes.

    Without this cell, a P2 that never fires looks identical to a P2 that fires
    correctly. The input is the positive witness above: the oracle's own
    invocation, which carries no model.
    """
    monkeypatch.setattr(cmp_mod, "p2_model_pinned", lambda *_a, **_k: None)
    bad = {**GOOD_PROV,
           "agent_args": ["-p", "{prompt}", "--allowedTools", "Read,Write,Bash"]}
    rc = _call(_run_dir(tmp_path, prov=bad))
    out = _verdict(capsys)
    assert "FAIL         P2" not in out, "the control did not remove the cell"
    assert "CLAUSE-2 PASS" in out and rc == 0, out


def test_the_model_pin_is_reported_beside_the_agent_logs(tmp_path, capsys):
    """R7 records what the run asked for. It never gates: section 6.2's own limit."""
    run = _run_dir(tmp_path)
    (run / "02-extract").mkdir(parents=True, exist_ok=True)
    (run / "02-extract" / "agent.stdout.log").write_text("x", encoding="utf-8")
    rc = _call(run)
    out = _verdict(capsys)
    assert "R7 model pin" in out and "claude-opus-5" in out, out
    assert "1 agent log(s)" in out and "NO ORACLE" in out, out
    assert rc == 0
