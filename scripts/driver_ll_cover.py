#!/usr/bin/env python3
"""DRIVER-LL sub-phase 4a acceptance cover.

Drives the BUILT `sequencer` binary through the eleven-cell transition cover of
`docs/design/driver-ll-phase4-proposal.md` section 2.3 and the three
corrupt-manifest shapes of its section 10 cases 16, 17 and 18, and asserts the
same decisions `scripts/tests/test_rfc_pipeline_integration.py` asserts against
the Python reference.

WHY THIS IS A SECOND HARNESS RATHER THAN THE RIG WITH A DIFFERENT `DRIVER`.
The rig invokes `scripts/rfc_to_implementation.py` with an agent command, an
llmll command and an RFC URL, and drives real stage bodies through a stub
agent. Sub-phase 4a lands NO stage bodies, so there is nothing for those three
flags to reach. What the two harnesses share is the DECISION under test and the
name of the test that pins it: every scenario below carries the name of the
Python-side test whose decision it reproduces, and
`scripts/tests/test_driver_ll_4a_cover.py` fails if a name here does not exist
there. That check is what keeps the two covers from drifting into two different
questions; it is cheaper than structural sharing and it is the whole mitigation
for the mirror risk.

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
import subprocess
import sys
import tempfile
from pathlib import Path

# One line per step. A full sixteen-stage run is about 110 steps; every
# scenario below selects at most four stages. Generous on purpose: the failure
# mode of a tight budget is exit 70, which is loud, but it is not the property
# under test.
BUDGET = 800

REPO = Path(__file__).resolve().parent.parent


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


def drive(binary: Path, workdir: Path, only: str, *,
          force: bool = False, halt_at: str = "", halt_kind: str = "") -> Run:
    cmd = [str(binary), "--workdir", str(workdir), "--only", only]
    if force:
        cmd.append("--force")
    if halt_at:
        cmd += ["--halt-at", halt_at, "--halt-kind", halt_kind]
    proc = subprocess.run(cmd, input="x\n" * BUDGET, capture_output=True,
                          text=True, cwd=str(workdir.parent))
    if proc.returncode == 70:
        raise Failure(
            f"the run exited 70: stdin was exhausted before :done? fired, so "
            f"the step budget of {BUDGET} is too small for this scenario. "
            f"This is a harness error, not a driver decision.\n{proc.stdout}")
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

    print(f"DRIVER-LL 4a cover: {npass} passed, {nfail} failed")
    return 1 if nfail else 0


if __name__ == "__main__":
    sys.exit(main())
