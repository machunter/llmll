#!/usr/bin/env python3
"""DRIVER-LL sub-phase 4a, 4b and 4c acceptance cover.

Drives the BUILT `sequencer` binary through the eleven-cell transition cover of
`docs/design/driver-ll-phase4-proposal.md` section 2.3, the three
corrupt-manifest shapes of its section 10 cases 16, 17 and 18, and the
delegated-output conditions of its section 9's 4b row, and asserts the same
decisions `scripts/tests/test_rfc_pipeline_integration.py` asserts against the
Python reference.

WHY THIS IS A SECOND HARNESS RATHER THAN THE RIG WITH A DIFFERENT `DRIVER`.
The rig invokes `scripts/rfc_to_implementation.py` with an agent command, an
llmll command and an RFC URL, and drives real stage bodies through a stub
agent. Sub-phase 4b lands three of the sixteen stage bodies, so the rig's
`--llmll-cmd` and `--rfc-url` still reach nothing here. What the two harnesses
share is the DECISION under test and the name of the test that pins it: every
scenario below carries the name of the Python-side test whose decision it
reproduces, and `scripts/tests/test_driver_ll_4a_cover.py` fails if a name here
does not exist there. That check is what keeps the two covers from drifting
into two different questions; it is cheaper than structural sharing and it is
the whole mitigation for the mirror risk.

THE AGENT STUB MIRRORS THE RIG'S, and the correspondence is checked rather than
promised. Both take `{out}` as argv[1] and `{prompt}` as argv[2] and read
STUB_MODE from the environment, which is the channel proposal section 5 item 2
settles (`wasi.proc.run` has no env parameter, so the driver cannot inject one;
STUB_MODE is the RIG's control channel, set on the driver process and
inherited). `test_driver_ll_4a_cover.py` asserts the rig still reads argv in
that order, so a change there reddens rather than silently splitting the two
harnesses.

THE STDIN BUDGET IS NOT DATA. The console harness consumes one line per step
(`CodegenHs.hs` emitMainBody, the ModeConsole loop). Since PROC-BOUNDARY-1 an
under-budgeted run exits 70 with `:status` NOT consulted, so a starved run can
no longer read as a green one; this file reports 70 as a budget error rather
than as a decision.

Usage:
    python3 scripts/driver_ll_cover.py --driver /path/to/sequencer
    DRIVER_LL_BIN=/path/to/sequencer python3 scripts/driver_ll_cover.py
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

# One line per step. A full sixteen-stage run is about 140 steps once B, C and
# I have real bodies; every scenario below selects at most four stages.
# Generous on purpose: the failure mode of a tight budget is exit 70, which is
# loud, but it is not the property under test.
BUDGET = 800

REPO = Path(__file__).resolve().parent.parent
PROMPTS = REPO / "experiments" / "rfc-swarm" / "prompts"

# The stub agent. argv[1] is {out} and argv[2] is {prompt}, matching the rig's
# STUB_AGENT. Every mode writes a byte count chosen against a STAGE CONTRACT
# floor (200 for B, 400 for C, none for I) rather than against a size any
# committed run produced, which is the distinction driver-spec section 7:288-291
# draws and the reason `short-rubric` writes 300: it CLEARS stage B's floor and
# FAILS stage C's, so a driver reading one stage's floor for another is caught.
AGENT_STUB = r'''
import json, os, pathlib, sys
out    = pathlib.Path(sys.argv[1])
prompt = pathlib.Path(sys.argv[2])
mode   = os.environ.get("STUB_MODE", "ok")
name   = out.name

# Sub-phase 4c: D, F and G declare a SHAPE rather than a byte floor
# (registry.stage-shape), so their stubs write schema-valid JSON and the padding
# below would fail them for the wrong reason. The shapes mirror the rig's stub
# (test_rfc_pipeline_integration.py:101-121) so both drivers are driven by the
# same inputs and a divergence between them is a driver difference rather than a
# harness one.
def _rows(tag):
    return [{"id": "%s%d" % (tag, i), "source": "SPEC",
             "line_start": 2 + i, "line_end": 2 + i, "quote": "q",
             "rule": "N%d" % (i + 1), "obligation": "obligation %d" % i}
            for i in range(2)]

if name == "extraction.json":
    tag = "A" if "(extractor A)" in prompt.read_text(encoding="utf-8") else "B"
    rows = _rows(tag)
    # A DELEGATED-OUTPUT DEFECT: the span is a string where reconcile.py matches
    # on integers. `bad-extraction-b` corrupts the SECOND extractor only, which
    # is the only way to reach the halt with a valid SIBLING already on disk
    # (proposal sec 3.6.1).
    if mode == "bad-extraction" or (mode == "bad-extraction-b" and tag == "B"):
        rows[0]["line_start"] = "2"
    if mode == "empty-extraction":
        rows = []
    out.write_text(json.dumps(
        {"extractor": tag, "normative": rows,
         "excluded": [{"id": tag + "x", "source": "SPEC", "line_start": 1,
                       "line_end": 1, "quote": "q", "rule": "X1",
                       "reason": "preamble"}]}))
    sys.exit(0)

if name == "core.json":
    # `bare-core` is the shape the reference TOLERATES and the port narrows away
    # (finding F-20: no producer in the tree emits it).
    out.write_text(json.dumps(["A0"] if mode == "bare-core"
                              else {"core_ids": ["A0"],
                                    "rationale": "the first obligation defines it"}))
    sys.exit(0)

if name == "inventory-dispositioned.json":
    row = {"cid": "A0", "class": "C1", "disposition": "Encoded",
           "reason": "encoded directly"}
    if mode == "bad-barrier":
        # driver-spec sec 6:229-231, the ONE spec-defined condition in stage G.
        row = {"cid": "A0", "class": "C1", "disposition": "Dispositioned out",
               "barrier": "B9", "reason": "outside the closed list"}
    if mode == "listed-barrier":
        row = {"cid": "A0", "class": "C1", "disposition": "Dispositioned out",
               "barrier": "B5", "reason": "string structure"}
    if mode == "bad-class":
        row["class"] = "C9"
    out.write_text(json.dumps({"rows": [row]}))
    sys.exit(0)

# "Silence is not success" (driver-spec sec 7:279) at a STAGE-level delegated
# output: exit 0 having written nothing. AgentRunner.run is what catches it in
# the reference (rfc_to_implementation.py:331-334).
if mode == "silent-scope" and name == "scope.md":
    sys.exit(0)
if mode == "short-scope" and name == "scope.md":
    out.write_text("too short\n")
    sys.exit(0)
if mode == "short-rubric" and name == "rubric.md":
    out.write_text("-" * 300)
    sys.exit(0)
if mode == "empty-prereg" and name == "PRE-REGISTRATION.md":
    out.write_text("")
    sys.exit(0)
# A VALID declared output AND a non-zero exit. Proposal sec 3.1 row 3 and sec
# 10 case 4 both say `complete`; the reference records `failed`, because
# AgentRunner.run raises on the exit status BEFORE it checks for the output.
if mode == "nonzero-scope" and name == "scope.md":
    out.write_text("-" * 900)
    sys.exit(7)

# The prompt is read so that a stub which never opened it would differ
# observably from one that did; the driver's contract is that {prompt} names a
# file the agent can read.
body = "stub output for %s from a prompt of %d bytes\n" % (
    name, len(prompt.read_text(encoding="utf-8")))
out.write_text(body + "-" * (5000 if mode == "big" else 900) + "\n")
'''


class Failure(Exception):
    pass


class Run:
    def __init__(self, proc: subprocess.CompletedProcess, workdir: Path):
        self.rc = proc.returncode
        self.out = proc.stdout
        self.err = proc.stderr
        self.workdir = workdir

    def manifest(self) -> dict:
        p = self.workdir / "MANIFEST.json"
        if not p.exists():
            return {}
        return json.loads(p.read_text())

    def stages(self) -> dict:
        return self.manifest().get("stages", {})


def prepare(wd: Path, *, sources: dict[str, str] | None = None,
            provenance: str | None = None) -> None:
    """What stage A would have left behind.

    Stage A is not ported at 4b (it needs HTTP-GET-1) and is not listed in any
    of proposal section 9's sub-phase rows, so its outputs are laid down here.
    They are the real shapes: PROVENANCE.json as `write_json` writes it, and
    the pinned bytes as `00-source/*.txt`, which is what `_sources_text` globs.
    """
    src = wd / "00-source"
    src.mkdir(parents=True, exist_ok=True)
    for name, text in (sources if sources is not None
                       else {"rfc.txt": "1. Introduction\nA sender MUST ack.\n"}).items():
        (src / name).write_text(text, encoding="utf-8")
    (src / "PROVENANCE.json").write_text(
        provenance if provenance is not None
        else json.dumps({"sources": [{"url": "file:///spec.txt", "file": "rfc.txt",
                                      "sha256": "0" * 64, "lines": 2}]}, indent=1) + "\n",
        encoding="utf-8")


def _stub(root: Path) -> Path:
    p = root / "stub_agent.py"
    if not p.exists():
        p.write_text(AGENT_STUB)
        p.chmod(p.stat().st_mode | stat.S_IXUSR)
    return p


def drive(binary: Path, workdir: Path, only: str, *,
          force: bool = False, halt_at: str = "", halt_kind: str = "",
          mode: str = "ok", prompts: Path | str | None = None,
          agent_exe: str | None = None, timeout: int | None = None) -> Run:
    stub = _stub(workdir.parent)
    cmd = [str(binary), "--workdir", str(workdir), "--only", only,
           # Proposal section 5 item 1: --agent-exe plus repeatable
           # --agent-arg, with {prompt}/{out}/{workdir} substituted per
           # argument. NOT a shell template, because passing one to /bin/sh -c
           # restores shell semantics through a granted binary.
           "--agent-exe", agent_exe if agent_exe is not None else sys.executable,
           "--agent-arg", str(stub),
           "--agent-arg", "{out}",
           "--agent-arg", "{prompt}",
           "--prompts-dir", str(prompts if prompts is not None else PROMPTS)]
    if timeout is not None:
        cmd += ["--timeout", str(timeout)]
    if force:
        cmd.append("--force")
    if halt_at:
        cmd += ["--halt-at", halt_at, "--halt-kind", halt_kind]
    proc = subprocess.run(cmd, input="x\n" * BUDGET, capture_output=True,
                          text=True, cwd=str(workdir.parent),
                          env=dict(os.environ, STUB_MODE=mode))
    if proc.returncode == 70:
        raise Failure(
            f"the run exited 70: stdin was exhausted before :done? fired, so "
            f"the step budget of {BUDGET} is too small for this scenario. "
            f"This is a harness error, not a driver decision.\n{proc.stdout}")
    return Run(proc, workdir)


def drive_bare(binary: Path, workdir: Path, *args: str) -> Run:
    """No --agent-exe and no --prompts-dir. The reference makes --agent-cmd a
    required argparse argument (:1888-1891) and exits 2 through ap.error before
    any stage exists."""
    proc = subprocess.run([str(binary), "--workdir", str(workdir), *args],
                          input="x\n" * BUDGET, capture_output=True, text=True,
                          cwd=str(workdir.parent))
    return Run(proc, workdir)


# ---------------------------------------------------------------------------
# assertions
# ---------------------------------------------------------------------------

def want(cond: bool, msg: str) -> None:
    if not cond:
        raise Failure(msg)


def want_in(needle: str, r: Run) -> None:
    want(needle in r.out, f"expected {needle!r} on stdout, got:\n{r.out}")


def want_not_in(needle: str, r: Run) -> None:
    want(needle not in r.out, f"did NOT expect {needle!r} on stdout, got:\n{r.out}")


def want_rc(r: Run, code: int) -> None:
    want(r.rc == code, f"expected exit {code}, got {r.rc}\n{r.out}\n{r.err}")


def want_complete_row(row: dict, kind: str) -> None:
    """Section 4's asymmetry, positive half."""
    want(row.get("status") == "complete", f"expected a complete row, got {row}")
    want(row.get("kind") == kind, f"expected kind {kind!r} in {row}")
    want("seconds" in row, f"a complete row carries seconds: {row}")
    want("outputs" in row, f"a complete row carries outputs: {row}")
    # The decision proposal section 4 states and the natural port breaks.
    want("outcome" not in row,
         f"a complete row MUST NOT carry an `outcome` member; alpha retains "
         f"`outcome` and the reference emits none here: {row}")
    want("detail" not in row, f"a complete row carries no detail: {row}")
    want("clause" not in row, f"a complete row carries no clause: {row}")


def want_halt_row(row: dict, status: str, outcome: str, clause: bool) -> None:
    """Section 4's asymmetry, negative half."""
    want(row.get("status") == status, f"expected status {status!r} in {row}")
    want(row.get("outcome") == outcome, f"expected outcome {outcome!r} in {row}")
    want(bool(row.get("detail")), f"a halt row carries a non-empty detail: {row}")
    want(("clause" in row) == clause,
         f"expected clause present={clause} in {row}")
    want("kind" not in row, f"a halt row MUST NOT carry kind: {row}")
    want("seconds" not in row, f"a halt row MUST NOT carry seconds: {row}")


# ---------------------------------------------------------------------------
# the cover
#
# Each entry is (transition, python_side_test_name, body). The name is checked
# against scripts/tests/test_rfc_pipeline_integration.py by the pytest wrapper.
# ---------------------------------------------------------------------------

SCENARIOS = []


def scenario(cell: str, mirrors: str):
    def deco(fn):
        SCENARIOS.append((cell, mirrors, fn))
        return fn
    return deco


def local(cell: str, why: str):
    """A cell with NO Python-side counterpart, and the reason is the cell.

    Sub-phase 4b's conditions divide in two. Some the reference also decides,
    and those use `@scenario` and name the test that pins the decision there.
    The rest are conditions the reference reaches as a TRACEBACK (proposal
    section 9.1 item 1's guarded reads), or are flags the port has and the
    reference does not (--prompts-dir), or are properties of the port's own
    facility (the per-stage floor, subject neutrality). A mirror name would be
    a fiction for those, and inventing one would weaken the invariant
    `test_every_cover_scenario_mirrors_a_test_that_exists` exists to hold.
    """
    def deco(fn):
        SCENARIOS.append((cell, "(4b, no reference counterpart) " + why, fn))
        return fn
    return deco



def local4c(cell: str, why: str):
    """The 4c sibling of `local`, so the printed provenance stays accurate."""
    def deco(fn):
        SCENARIOS.append((cell, "(4c, no reference counterpart) " + why, fn))
        return fn
    return deco

@scenario("T1", "test_pipeline_runs_through_both_gates")
def t1(b, wd):
    r = drive(b, wd, "A,B,C")
    want_rc(r, 0)
    want_in("stage A [mechanical] intake and provenance pinning", r)
    want_in("stage C [agent] normativity rubric", r)
    want_in("[driver-ll] end status=0", r)
    for key, kind in (("A", "mechanical"), ("B", "agent"), ("C", "agent")):
        want_complete_row(r.stages()[key], kind)
    want((wd / "01-scope" / "scope.md").exists(),
         "a stage that ran must have written its declared artifact")


@scenario("T2", "test_a_spec_defined_halt_records_stopped_and_names_its_clause")
def t2(b, wd):
    r = drive(b, wd, "A,B,C", halt_at="B", halt_kind="ConditionUnmet")
    want_rc(r, 2)
    want_in("STOP at stage B", r)
    want_halt_row(r.stages()["B"], "stopped", "ConditionUnmet", clause=True)
    want(r.stages()["B"]["clause"] == "4a-injector",
         "the injected halt names its clause")
    want_not_in("stage C [", r)
    want("C" not in r.stages(), "the stage after a halt is never attempted")
    want(not (wd / "01-scope" / "scope.md").exists(),
         "ConditionUnmet halts BEFORE the stage writes; that is what makes "
         "it distinct from PartialThenHalt")


@scenario("T3", "test_a_delegated_output_defect_records_failed_not_stopped")
def t3(b, wd):
    r = drive(b, wd, "A,B,C", halt_at="B", halt_kind="Errored")
    want_rc(r, 3)
    want_in("FAILED at stage B", r)
    want_halt_row(r.stages()["B"], "failed", "Errored", clause=False)
    want_not_in("stage C [", r)


@scenario("T4", "test_stage_H_records_partial_then_halt_after_writing_its_output")
def t4(b, wd):
    r = drive(b, wd, "A,B,C", halt_at="B", halt_kind="PartialThenHalt")
    want_rc(r, 2)
    want_in("STOP at stage B", r)
    want_halt_row(r.stages()["B"], "stopped", "PartialThenHalt", clause=True)
    want((wd / "01-scope" / "scope.md").exists(),
         "PartialThenHalt wrote its declared output and THEN halted; without "
         "the artifact the constructor is indistinguishable from ConditionUnmet")


@scenario("T5", "test_a_completed_stage_is_still_skipped_on_resume")
def t5(b, wd):
    want_rc(drive(b, wd, "A,B,C"), 0)
    r = drive(b, wd, "A,B,C")
    want_rc(r, 0)
    want_in("already complete, skipping", r)
    want_not_in("stage B [agent] scope decision", r)
    want(r.out.count("already complete, skipping") == 3,
         f"all three stages skip on an untouched resume:\n{r.out}")


@scenario("T6", "test_a_modified_artifact_forces_a_rerun")
def t6(b, wd):
    want_rc(drive(b, wd, "A,B,C"), 0)
    art = wd / "02-rubric" / "rubric.md"
    art.write_text(art.read_text() + "edited outside the protocol\n")
    r = drive(b, wd, "A,B,C")
    want_rc(r, 0)
    want_in("artifact(s) changed since this stage recorded completion", r)
    want_in("02-rubric/rubric.md", r)
    want_not_in("stage C (normativity rubric): already complete, skipping", r)
    want_in("stage A (intake and provenance pinning): already complete, skipping", r)


@scenario("T7", "test_a_declared_artifact_deleted_from_a_complete_stage_forces_a_rerun")
def t7(b, wd):
    """Skip condition (b) failing ALONE.

    NO ASSERTION ON SILENCE, per proposal section 10 case 15's withdrawal of
    the Rev 5 instruction: the port is free to print a reason line and this
    test must not pin its absence. What is asserted is the DECISION.
    """
    want_rc(drive(b, wd, "A,B,C"), 0)
    (wd / "01-scope" / "scope.md").unlink()
    r = drive(b, wd, "A,B,C")
    want_rc(r, 0)
    want_in("stage B [agent] scope decision", r)
    want_in("stage A (intake and provenance pinning): already complete, skipping", r)
    want_in("stage C (normativity rubric): already complete, skipping", r)
    want((wd / "01-scope" / "scope.md").exists(), "the re-run rewrote the artifact")


@scenario("T8", "test_artifacts_without_a_completion_record_force_a_rerun")
def t8(b, wd):
    want_rc(drive(b, wd, "A,B,C"), 0)
    man = json.loads((wd / "MANIFEST.json").read_text())
    del man["stages"]["C"]
    (wd / "MANIFEST.json").write_text(json.dumps(man))
    r = drive(b, wd, "A,B,C")
    want_rc(r, 0)
    want_in("artifacts present but no completion record", r)
    want_in("stage C [agent] normativity rubric", r)
    want_complete_row(r.stages()["C"], "agent")


@scenario("T9", "test_a_failed_gate_is_not_bypassed_by_its_own_output_on_resume")
def t9(b, wd):
    """THE regression, in the port. A stage that wrote its output and then
    halted must not be skipped by that output on the next run."""
    r1 = drive(b, wd, "A,B,C", halt_at="B", halt_kind="PartialThenHalt")
    want_rc(r1, 2)
    want((wd / "01-scope" / "scope.md").exists(), "the halting stage wrote output")
    want(r1.stages()["B"]["status"] == "stopped", "premise")

    r2 = drive(b, wd, "A,B,C")
    want_not_in("stage B (scope decision): already complete, skipping", r2)
    want_in("stage B [agent] scope decision", r2)
    want_rc(r2, 0)
    want_complete_row(r2.stages()["B"], "agent")


@scenario("T10", "test_a_failed_stage_is_re_run_on_resume")
def t10(b, wd):
    r1 = drive(b, wd, "A,B,C", halt_at="C", halt_kind="Errored")
    want_rc(r1, 3)
    want(r1.stages()["C"]["status"] == "failed", "premise")
    r2 = drive(b, wd, "A,B,C")
    want_rc(r2, 0)
    want_not_in("stage C (normativity rubric): already complete, skipping", r2)
    want_complete_row(r2.stages()["C"], "agent")


@scenario("T11", "test_force_re_runs_a_stage_the_manifest_records_complete")
def t11(b, wd):
    want_rc(drive(b, wd, "A,B,C"), 0)
    warm = drive(b, wd, "A,B,C")
    want_in("already complete, skipping", warm)
    r = drive(b, wd, "A,B,C", force=True)
    want_rc(r, 0)
    want_not_in("already complete, skipping", r)
    want_in("stage C [agent] normativity rubric", r)


def _corrupt(b, wd, body: str, needle: str) -> Run:
    want_rc(drive(b, wd, "A,B,C"), 0)
    (wd / "MANIFEST.json").write_text(body)
    r = drive(b, wd, "A,B,C")
    want_rc(r, 2)
    want_in("STOP:", r)
    want_in(needle, r)
    want_in("Delete it to re-run", r)
    want_not_in("stage A [", r)
    want((wd / "MANIFEST.json").read_text() == body,
         "an undecidable resume writes NOTHING to the manifest")
    return r


@scenario("case16", "test_a_truncated_manifest_halts_as_a_decision_not_a_traceback")
def c16(b, wd):
    _corrupt(b, wd, '{"stages": {"A": ', "not readable JSON")


@scenario("case17", "test_a_manifest_that_is_not_an_object_halts_as_a_decision")
def c17(b, wd):
    _corrupt(b, wd, "[]", "not an object")


@scenario("case18", "test_a_manifest_whose_stages_key_is_not_an_object_halts")
def c18(b, wd):
    _corrupt(b, wd, '{"stages": [], "rfc_url": "x"}', "at 'stages'")


# ---------------------------------------------------------------------------
# Sub-phase 4b. Proposal section 9's row: "A delegated output that is absent,
# malformed, or subject-hardcoded fails the stage and is never skipped. Every
# reachable halt in B, C and I records `failed`/`Errored`; a `stopped` anywhere
# in 4b is wrong by construction."
#
# EVERY cell below asserts `clause` ABSENT as well as the status, because a
# `clause` member is what the halt-row shape writes on the STOPPED path and
# nowhere else. That assertion is the acceptance clause's "a stopped anywhere
# in 4b is wrong by construction" made observable at the manifest.
# ---------------------------------------------------------------------------

def want_failed(r: Run, key: str, needle: str) -> None:
    want_rc(r, 3)
    row = r.stages().get(key)
    want(row is not None, f"stage {key} recorded no row at all:\n{r.out}")
    want_halt_row(row, "failed", "Errored", clause=False)
    want(needle in row["detail"],
         f"expected {needle!r} in the detail, got {row['detail']!r}")
    want("FAILED at stage " + key in r.out,
         f"driver-spec sec 4:139-143 requires the reason ON THE OUTPUT too:\n{r.out}")


@scenario("B0", "test_an_agent_that_exits_zero_without_writing_records_failed")
def b0(b, wd):
    """Silence is not success (sec 7:279), at a stage-level delegated output."""
    r = drive(b, wd, "B,C", mode="silent-scope")
    want_failed(r, "B", "wrote no scope.md")
    want_not_in("stage C [", r)
    want("C" not in r.stages(), "no stage after a failed one is attempted")


@local("B1", "the happy path; without it every negative cell below is vacuous")
def b1(b, wd):
    r = drive(b, wd, "B,C,I")
    want_rc(r, 0)
    for key in ("B", "C", "I"):
        want_complete_row(r.stages()[key], "agent")
    for rel in ("01-scope/scope.md", "02-rubric/rubric.md",
                "08-prereg/PRE-REGISTRATION.md"):
        want((wd / rel).exists(), f"{rel} was not written")
    # The delegation actually happened, through the channel section 5 settles.
    for d in ("01-scope", "02-rubric", "08-prereg"):
        p = wd / d / "PROMPT.md"
        want(p.exists(), f"{d}/PROMPT.md was not written")
        want("{{" not in p.read_text(),
             f"{d}/PROMPT.md still carries an unsubstituted placeholder")
        want((wd / d / "agent.stdout.log").exists(),
             f"{d}: the agent's stdout was not captured to a file")
    # _sources_text's numbering, byte for byte against the reference's format.
    want("    1| 1. Introduction" in (wd / "01-scope" / "PROMPT.md").read_text(),
         "the pinned bytes must reach the agent with EXPLICIT line numbers; "
         "extraction rows cite spans and reconciliation matches on them")


@local("B2", "a delegated output below the floor its stage contract declares")
def b2(b, wd):
    r = drive(b, wd, "B,C", mode="short-scope")
    want_failed(r, "B", "scope.md is too short to state a boundary")
    want("C" not in r.stages(), "no stage after a failed one is attempted")


@local("B3", "the floor is PER STAGE CONTRACT: 300 bytes clears B and fails C")
def b3(b, wd):
    """The discriminating cell for the validation facility.

    One output size, two stages, two decisions. A driver holding a single
    global floor, or reading stage B's floor while validating stage C, passes
    every other cell here and fails this one.
    """
    r = drive(b, wd, "B,C", mode="short-rubric")
    want_complete_row(r.stages()["B"], "agent")
    want_failed(r, "C", "rubric.md is too short")


@local("B4", "valid output AND non-zero exit: the reference records failed, "
             "where proposal sec 3.1 row 3 and sec 10 case 4 say complete")
def b4(b, wd):
    r = drive(b, wd, "B,C", mode="nonzero-scope")
    want_failed(r, "B", "exited 7")
    want((wd / "01-scope" / "scope.md").exists(),
         "the premise: the agent DID write a valid declared output")
    want((wd / "01-scope" / "scope.md").stat().st_size > 200,
         "the premise: and it clears the floor, so validation would have passed")


@local("B5", "sec 9.1 item 1: PROVENANCE.json absent is a DECISION, not a traceback")
def b5(b, wd):
    (wd / "00-source" / "PROVENANCE.json").unlink()
    r = drive(b, wd, "B")
    want_failed(r, "B", "00-source/PROVENANCE.json")
    want("is absent" in r.stages()["B"]["detail"], "the reason names the shape")


@local("B6", "sec 9.1 item 1: PROVENANCE.json that does not parse")
def b6(b, wd):
    (wd / "00-source" / "PROVENANCE.json").write_text('{"sources": ')
    r = drive(b, wd, "B")
    want_failed(r, "B", "does not parse as JSON")


@local("B7", "the pinned sources are gone; sec 7:279 for an INPUT")
def b7(b, wd):
    (wd / "00-source" / "rfc.txt").unlink()
    r = drive(b, wd, "B")
    want_failed(r, "B", "no pinned RFC text found; run stage A first")


@local("B8", "sec 9.1 item 1: stage I's read of stage B's scope.md")
def b8(b, wd):
    r = drive(b, wd, "I")
    want_failed(r, "I", "01-scope/scope.md")


@local("B9", "sec 9.1 item 2: stage I has NO validator and one is not invented")
def b9(b, wd):
    """A 0-byte PRE-REGISTRATION.md records `complete` at exit 0.

    Measured against the reference before it was ported: stage I holds zero
    halt calls. This cell is the disclosure made executable, so a later
    sub-phase that adds a validator to stage I has to delete a green test
    rather than quietly improving on the reference.
    """
    r = drive(b, wd, "B,I", mode="empty-prereg")
    want_rc(r, 0)
    want_complete_row(r.stages()["I"], "agent")
    p = wd / "08-prereg" / "PRE-REGISTRATION.md"
    want(p.exists() and p.stat().st_size == 0,
         f"the premise: a 0-byte declared output, got "
         f"{p.stat().st_size if p.exists() else 'nothing'}")


@local("B10", "the prompt template is not under --prompts-dir")
def b10(b, wd):
    r = drive(b, wd, "B", prompts=wd / "no-such-prompts")
    want_failed(r, "B", "not readable under --prompts-dir")


@local("B11", "a template placeholder no keyword fills (Ctx.prompt's require)")
def b11(b, wd):
    d = wd / "prompts"
    d.mkdir()
    for src in PROMPTS.glob("*.md"):
        shutil.copy2(src, d / src.name)
    (d / "stage-B-scope.md").write_text(
        (d / "stage-B-scope.md").read_text() + "\n\nUnknown: {{not_a_keyword}}\n")
    r = drive(b, wd, "B", prompts=d)
    want_failed(r, "B", "unfilled placeholders")


@local("B12", "the agent executable does not exist; the RErr arm of proc.run")
def b12(b, wd):
    r = drive(b, wd, "B", agent_exe=str(wd / "no-such-agent"))
    want_failed(r, "B", "could not be started")


@local("B13", "'and is never skipped': a stage whose output failed validation "
              "is re-run, and one whose output passed is skipped")
def b13(b, wd):
    r1 = drive(b, wd, "B,C", mode="short-scope")
    want_failed(r1, "B", "too short")
    want((wd / "01-scope" / "scope.md").exists(),
         "the premise: the failing stage LEFT AN ARTIFACT behind, which is what "
         "would let a presence-only resume gate skip it")
    r2 = drive(b, wd, "B,C")
    want_rc(r2, 0)
    want_not_in("stage B (scope decision): already complete, skipping", r2)
    want_in("stage B [agent] scope decision", r2)
    want_complete_row(r2.stages()["B"], "agent")
    r3 = drive(b, wd, "B,C")
    want_rc(r3, 0)
    want(r3.out.count("already complete, skipping") == 2,
         f"a validated stage IS skipped on the next resume:\n{r3.out}")


@local("B14", "sec 7:288-291: the same driver over TWO different subjects")
def b14(b, wd):
    """Subject neutrality, measured rather than promised.

    A validator that hardcoded the values one run produced passes its own
    subject and reports emptiness on the next. Two subjects here differ in
    every dimension a fitted validator could have latched onto: the source
    filename, the byte count, the line count, the provenance, and the size of
    what the agent writes. Both must reach the same verdicts.
    """
    r1 = drive(b, wd, "B,C,I")
    want_rc(r1, 0)
    first = {k: v["status"] for k, v in r1.stages().items()}

    other = wd.parent / (wd.name + "-subject2")
    other.mkdir()
    prepare(other,
            sources={"rfc9999.txt": "".join(
                f"{i:4d} A receiver SHOULD ignore an unknown option.\n"
                for i in range(200))},
            provenance=json.dumps(
                {"sources": [{"url": "https://example.invalid/rfc9999.txt",
                              "file": "rfc9999.txt", "sha256": "f" * 64,
                              "lines": 200}]}, indent=1) + "\n")
    r2 = drive(b, other, "B,C,I", mode="big")
    want_rc(r2, 0)
    second = {k: v["status"] for k, v in r2.stages().items()}
    want(first == second == {"B": "complete", "C": "complete", "I": "complete"},
         f"the two subjects disagree: {first} vs {second}")
    want((other / "01-scope" / "scope.md").stat().st_size
         != (wd / "01-scope" / "scope.md").stat().st_size,
         "the premise: the two subjects really did produce different outputs")


@local("B15", "--agent-exe is required, as the reference requires --agent-cmd")
def b15(b, wd):
    r = drive_bare(b, wd, "--only", "B")
    want_rc(r, 2)
    want_in("STOP:", r)
    want_in("--agent-exe is required", r)
    want(not r.stages(), "an argument fault assigns no stage status")


# ---------------------------------------------------------------------------
# Not a cover cell: the registry's own drift guard. stage-out and stage-out-dir
# are two hand-written tables and nothing in the language relates them, so a
# path whose directory is wrong writes into the wrong place and every digest
# still matches. A full run over all sixteen stages is what catches it.
# ---------------------------------------------------------------------------

DECLARED = [
    "00-source/PROVENANCE.json", "01-scope/scope.md", "02-rubric/rubric.md",
    "03-extraction/a/extraction.json", "03-extraction/b/extraction.json",
    "04-reconcile/SUMMARY.json", "05-core/core.json",
    "06-disposition/inventory-dispositioned.json", "06b-audit/audit.json",
    "07-feasibility/feasibility.json", "08-prereg/PRE-REGISTRATION.md",
    "09-gate/gate.json", "10-roots/roots.llmll", "11-freeze/rfc-cov-1.txt",
    "11-freeze/ROOTS.txt", "12-wave/wave.json", "12-wave/roots.ast.json",
    "13-kill-matrix/kill-matrix.json", "REPORT.md",
]


def registry_drift(b, wd) -> None:
    r = drive(b, wd, "")
    want_rc(r, 0)
    want(len(r.stages()) == 16, f"a full run records sixteen stages: {r.stages().keys()}")
    for rel in DECLARED:
        want((wd / rel).exists(), f"declared output {rel} was not written")
    recorded = {o for row in r.stages().values() for o in row.get("outputs", {})}
    want(recorded == set(DECLARED),
         f"the outputs maps and the declared list disagree: "
         f"{sorted(recorded ^ set(DECLARED))}")


# ---------------------------------------------------------------------------
# Sub-phase 4c: stages D, F and G.
#
# Section 9's 4c row, as replaced at Rev 10: the already-ported downstream stages
# RUN over 4c's own output rather than pinned values reproducing over it. The
# acceptance is therefore that E, and G2 and J, can run at all, which they cannot
# unless D stages its pair where they read it.
#
# THE THIRD Outcome ARM APPEARS HERE. Every 4b cell asserts `clause` ABSENT
# because no 4b halt is spec-defined. Stage G has one: check_dispositioned's
# require_spec (:493) citing driver-spec sec 6:229-231. C5 asserts the clause
# PRESENT, and C5b asserts the same check passes on a LISTED barrier, so the
# condition is discriminating rather than always-firing.
# ---------------------------------------------------------------------------

def want_stopped(r: Run, key: str, clause: str) -> None:
    want_rc(r, 2)
    row = r.stages().get(key)
    want(row is not None, f"stage {key} recorded no row at all:\n{r.out}")
    want_halt_row(row, "stopped", "ConditionUnmet", clause=True)
    want(row.get("clause") == clause,
         f"a stopped row names the clause that authorised it: expected "
         f"{clause!r}, got {row.get('clause')!r}")


@local4c("C1", "stage D delegates TWICE and both extractors get an identical, "
               "complete isolated input set; blindness is structural")
def c1(b, wd):
    r = drive(b, wd, "B,C,D")
    want_rc(r, 0)
    want_complete_row(r.stages()["D"], "agent")
    # The port logs STAGE lines, not per-delegation agent lines, so the evidence
    # that two distinct invocations happened is the two rendered prompts: each
    # carries its own extractor letter through {{extractor}} (:654).
    for tag, letter in (("a", "A"), ("b", "B")):
        pr = (wd / "03-extraction" / tag / "PROMPT.md").read_text(encoding="utf-8")
        want("(extractor %s)" % letter in pr,
             f"extractor {tag}'s prompt must be rendered with {letter!r}; "
             f"a single rendering reused for both tags is the failure this "
             f"catches")
    sets = {}
    for tag in ("a", "b"):
        d = wd / "03-extraction" / tag
        want(d.exists(), f"extractor {tag} has no directory at all")
        sets[tag] = sorted(x.name for x in d.iterdir())
    want(sets["a"] == sets["b"],
         f"the two extractors must receive the SAME input set, got {sets}")
    # Every FILE under 00-source, not just the .txt ones: the reference globs `*`
    # and copies each file (:648-650), and audit_blindness's allowed set
    # (:1836-1837) lists PROVENANCE.json among the legitimate inputs, so a
    # .txt-only filter would drop an input the blindness audit expects.
    pinned = sorted(x.name for x in (wd / "00-source").iterdir() if x.is_file())
    want(len(pinned) > 1,
         f"the premise: 00-source must hold more than one file for the unfiltered "
         f"copy to be observable at all, got {pinned}")
    for tag in ("a", "b"):
        for need in pinned + ["rubric.md", "PROMPT.md"]:
            want(need in sets[tag],
                 f"extractor {tag} is missing {need}; it holds {sets[tag]} while "
                 f"00-source holds {pinned}")


@local4c("C2", "stage D stamps the extractor and the counts into its own "
               "declared output, which check_extraction's mutation produces")
def c2(b, wd):
    r = drive(b, wd, "B,C,D")
    want_rc(r, 0)
    for tag, letter in (("a", "A"), ("b", "B")):
        doc = json.loads((wd / "03-extraction" / tag / "extraction.json").read_text())
        want(doc.get("extractor") == letter,
             f"extractor {tag} output must be stamped {letter!r} (:657), got "
             f"{doc.get('extractor')!r}")
        want(doc.get("counts") == {"normative": len(doc["normative"]),
                                   "excluded": len(doc["excluded"])},
             f"check_extraction sets counts from the lists it validated "
             f"(:425-427); got {doc.get('counts')!r}")


@local4c("C3", "stage D stages the pair where the reconciler reads it, which is "
               "what makes F and G reachable at all")
def c3(b, wd):
    r = drive(b, wd, "B,C,D,F,G")
    want_rc(r, 0)
    for tag in ("a", "b"):
        f = wd / "04-reconcile" / "data" / ("extraction-%s.json" % tag)
        want(f.exists(),
             f"stage D copies its pair to the reconcile data directory "
             f"(:662-665); without it stage F halts on an absent precondition")
    for key in ("D", "F", "G"):
        want_complete_row(r.stages()[key], "agent")


@scenario("C4", "test_stage_D_records_failed_when_the_valid_sibling_is_already_written")
def c4(b, wd):
    """The second site where the two classification axes disagree.

    A tag-B defect halts with extractor A's output present AND past validation,
    so section 4:146's "wrote some of its artifacts" is satisfied by a valid
    SIBLING. The artifact-state axis says `stopped`; the reference says `failed`,
    and so does this port. Proposal section 3.6.1.
    """
    r = drive(b, wd, "B,C,D", mode="bad-extraction-b")
    want_failed(r, "D", "does not meet the shape")
    sib = json.loads((wd / "03-extraction" / "a" / "extraction.json").read_text())
    want(len(sib.get("normative", [])) > 0 and sib.get("extractor") == "A",
         "the premise that makes this cell differ from the tag-a case: the "
         f"sibling is present AND valid when the halt lands, got {sib!r}")


@local4c("C5", "stage F rejects the bare-array core the reference tolerates; the "
               "narrowing of finding F-20, which has no producer in the tree")
def c5(b, wd):
    r = drive(b, wd, "B,C,D,F", mode="bare-core")
    want_failed(r, "F", "non-empty core_ids list")


@scenario("C6", "test_exclusion_outside_the_barrier_list_halts_the_run")
def c6(b, wd):
    """4c's THIRD Outcome arm, and the only spec-defined halt in the sub-phase.

    check_dispositioned raises this one through require_spec rather than require
    (:493), so it records `stopped` with its clause where the other five record
    `failed`. It does NOT route through validate.verdict-outcome, whose
    [V7-NO-STOP] forbids ConditionUnmet.
    """
    r = drive(b, wd, "B,C,D,F,G", mode="bad-barrier")
    want_stopped(r, "G", "driver-spec sec 6:229-231")
    want_in("not in the closed list", r)


@local4c("C6b", "the barrier condition is DISCRIMINATING: a LISTED barrier "
                "completes where an unlisted one stops")
def c6b(b, wd):
    r = drive(b, wd, "B,C,D,F,G", mode="listed-barrier")
    want_rc(r, 0)
    want_complete_row(r.stages()["G"], "agent")


@local4c("C7", "a disposition row whose class is outside C1..C6 records failed, "
               "not stopped; five of check_dispositioned's six are `require`")
def c7(b, wd):
    r = drive(b, wd, "B,C,D,F,G", mode="bad-class")
    want_failed(r, "G", "class C1 through C6")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--driver", default=os.environ.get("DRIVER_LL_BIN", ""))
    ap.add_argument("--keep", action="store_true")
    a = ap.parse_args()
    if not a.driver:
        print("ERROR: pass --driver or set DRIVER_LL_BIN to the built "
              "`sequencer` binary (llmll build tools/llmll-driver/sequencer.llmll)",
              file=sys.stderr)
        return 2
    binary = Path(a.driver).resolve()
    if not binary.exists():
        print(f"ERROR: {binary} does not exist", file=sys.stderr)
        return 2

    root = Path(tempfile.mkdtemp(prefix="driver-ll-4a-"))
    npass = nfail = 0
    try:
        for cell, mirrors, fn in SCENARIOS + [("registry", "-", registry_drift)]:
            wd = root / cell
            wd.mkdir(parents=True)
            # What stage A would have left behind. Every scenario gets it and
            # the ones testing its absence remove what they need to; stage A is
            # not ported at 4b, so without this the three ported stages would
            # all halt on a missing input and no other cell would be reachable.
            prepare(wd)
            try:
                fn(binary, wd)
            except Failure as e:
                nfail += 1
                print(f"  FAIL {cell:8s} {fn.__name__}\n        {e}")
            else:
                npass += 1
                print(f"  ok   {cell:8s} mirrors {mirrors}")
    finally:
        if not a.keep:
            shutil.rmtree(root, ignore_errors=True)
        else:
            print(f"  workdirs kept under {root}")

    print(f"DRIVER-LL 4a+4b+4c cover: {npass} passed, {nfail} failed")
    return 1 if nfail else 0


if __name__ == "__main__":
    sys.exit(main())
