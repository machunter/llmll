"""End-to-end integration tests for the RFC-SWARM driver's STOP paths.

WHY THIS FILE EXISTS

`test_rfc_to_implementation.py` unit-tests the gate predicates, and they pass. They
passed while a FAILED freeze gate was being bypassed by its own output file and the
wave ran on regardless. The predicates were right; the seam around them was not.

So these tests drive the real driver as a subprocess, through the real stages, and
assert on things a unit test cannot see:

  * a STOP actually halts the process with a non-zero status
  * a STOP records `stopped`, never `complete`
  * no stage after a halted gate is attempted
  * a stopped stage RE-RUNS on resume even though its artifacts are present
    (this is the gate-bypass regression, and it is the whole point)
  * a genuinely complete stage IS skipped on resume, so the fix did not just
    disable resumption

Hermetic: no network (the source is a file:// URL), no model (a stub agent), and no
compiler (a stub `--llmll-cmd`). Runs in seconds.
"""
import importlib.util
import json
import os
import pathlib
import stat
import subprocess
import sys

import pytest

REPO = pathlib.Path(__file__).resolve().parents[2]
DRIVER = REPO / "scripts" / "rfc_to_implementation.py"

# import once, at module level: re-executing the module inside a test breaks the
# dataclass decorators it defines
_spec = importlib.util.spec_from_file_location("rfc_driver_itest", DRIVER)
assert _spec and _spec.loader
drv = importlib.util.module_from_spec(_spec)
sys.modules["rfc_driver_itest"] = drv
_spec.loader.exec_module(drv)

# Two normative-looking lines are enough: reconciliation matches on line spans, and
# the stub extractors below cite these.
SPEC = """Line one is preamble.
An implementation MUST do the first thing.
An implementation MUST do the second thing.
Trailing prose.
"""

# --- the stub agent -------------------------------------------------------------
# Produces schema-valid output for every delegated stage. The disposition it emits is
# controlled by STUB_MODE so a test can drive a specific gate into firing.
STUB_AGENT = r'''
import json, os, sys, pathlib
out  = pathlib.Path(os.environ["RFC_PIPELINE_OUT"])
mode = os.environ.get("STUB_MODE", "ok")
name = out.name

def rows(tag):
    return [{"id": f"{tag}{i}", "source": "SPEC", "line_start": 2 + i, "line_end": 2 + i,
             "quote": "q", "rule": "N1", "strength": "must",
             "obligation": f"obligation {i}"} for i in range(2)]

if name == "extraction.json":
    tag = "A" if "(extractor A)" in pathlib.Path(os.environ["RFC_PIPELINE_PROMPT"]).read_text() else "B"
    json.dump({"extractor": tag, "normative": rows(tag),
               "excluded": [{"id": f"{tag}x", "source": "SPEC", "line_start": 1,
                             "line_end": 1, "quote": "q", "rule": "X1",
                             "reason": "preamble"}]}, out.open("w"))
elif name == "core.json":
    json.dump({"core_ids": ["A0"], "rationale": "the first obligation defines it"}, out.open("w"))
elif name == "inventory-dispositioned.json":
    r0 = {"cid": "A0", "class": "C1", "disposition": "Encoded", "core": True,
          "reason": "contract on the step function"}
    r1 = {"cid": "A1", "class": "C1", "disposition": "Encoded", "core": False,
          "reason": "contract on the reply"}
    if mode == "core-excluded":          # gate J, characteristic-core condition
        r0 = {"cid": "A0", "class": "C1", "disposition": "Dispositioned out",
              "core": True, "barrier": "B5", "reason": "string structure"}
    if mode == "bad-barrier":            # gate J, closed-barrier condition
        r1 = {"cid": "A1", "class": "C1", "disposition": "Dispositioned out",
              "core": False, "barrier": "B99", "reason": "reason nobody agreed"}
    json.dump({"rows": [r0, r1]}, out.open("w"))
elif name == "probes.json":
    (out.parent / "p.llmll").write_text("probe")
    (out.parent / "m.llmll").write_text("mutant")
    json.dump([{"name": "p", "file": "p.llmll", "mutant_file": "m.llmll",
                "bug": "the attested bug"}], out.open("w"))
elif name == "roots.llmll":
    cited = ["A0"] if mode == "coverage-gap" else ["A0", "A1"]   # gate L
    out.write_text("".join(f';; :source "[{c}] SPEC line" \n' for c in cited))
elif name.endswith(".md"):
    out.write_text("# stub\n\n" + ("body. " * 200))
else:
    json.dump({}, out.open("w"))
'''

# --- the stub llmll -------------------------------------------------------------
# `check` succeeds. `verify` reports SAFE and body-faithful for probes and NOT SAFE for
# mutants, which is what stage H requires. `--trust-report --json` emits one entry per
# citation found in roots.llmll, so stage L's coverage lint has something real to check.
STUB_LLMLL = r'''#!/usr/bin/env python3
import json, re, sys, pathlib
argv = sys.argv[1:]
cmd  = argv[0] if argv else ""
if cmd == "check":
    print("OK"); sys.exit(0)
if cmd == "verify":
    target = pathlib.Path(argv[1])
    if "--trust-report" in argv:
        cites = re.findall(r'\[([A-Za-z0-9]+)\]', target.read_text())
        print(json.dumps({"entries": [
            {"name": f"fn{i}", "post_sources": [f"[{c}] SPEC line"]}
            for i, c in enumerate(cites)]}))
        sys.exit(0)
    if "mutant" in target.read_text():
        print("error: body verification failed"); sys.exit(1)
    print(f"   body-faithful: {target.stem}")
    print(f"OK {target} - SAFE (liquid-fixpoint)")
    sys.exit(0)
print("unhandled", cmd, file=sys.stderr); sys.exit(1)
'''


@pytest.fixture
def rig(tmp_path):
    """A workdir, a file:// source, and executable stubs for agent and compiler."""
    def _w(name, body):
        p = tmp_path / name
        p.write_text(body)
        p.chmod(p.stat().st_mode | stat.S_IXUSR)
        return p

    spec = tmp_path / "spec.txt"
    spec.write_text(SPEC)
    agent = _w("stub_agent.py", STUB_AGENT)
    llmll = _w("stub_llmll.py", STUB_LLMLL)

    def run(mode="ok", stages="A,B,C,D,E,F,G,H,I,J,K,L", workdir=None, extra=None):
        wd = workdir or (tmp_path / "wd")
        env = dict(os.environ, STUB_MODE=mode)
        cmd = [sys.executable, str(DRIVER),
               "--rfc-url", spec.resolve().as_uri(),
               "--workdir", str(wd),
               "--agent-cmd", f"{sys.executable} {agent}",
               "--llmll-cmd", str(llmll),   # a single executable: the driver uses it as argv[0]
               "--only", stages]
        if extra:
            cmd += extra
        p = subprocess.run(cmd, capture_output=True, text=True, env=env, cwd=REPO)
        return p, wd

    return run


def manifest(wd):
    p = wd / "MANIFEST.json"
    return json.loads(p.read_text())["stages"] if p.exists() else {}


# ---------------------------------------------------------------------------
# The happy path has to work, or every negative result below is vacuous
# ---------------------------------------------------------------------------

def test_pipeline_runs_through_both_gates(rig):
    p, wd = rig()
    assert p.returncode == 0, p.stdout + p.stderr
    m = manifest(wd)
    for stage in "ABCDEFGHIJKL":
        assert m.get(stage, {}).get("status") == "complete", (stage, m.get(stage), p.stdout)


# ---------------------------------------------------------------------------
# Gate J: the two enforced conditions
# ---------------------------------------------------------------------------

def test_core_row_excluded_halts_at_J_and_K_is_never_attempted(rig):
    p, wd = rig(mode="core-excluded")
    assert p.returncode != 0
    assert "characteristic-core rows dispositioned out" in p.stdout
    m = manifest(wd)
    assert m["J"]["status"] == "stopped"
    assert "K" not in m, "a stage after a halted gate must not be attempted"


def test_exclusion_outside_the_barrier_list_halts_the_run(rig):
    """The barrier condition is enforced TWICE: stage G rejects the disposition
    output as malformed, and gate J re-checks. G runs first, so that is where a
    live run stops. The redundancy is deliberate; gate J still has to hold on its
    own for a resumed run whose inventory arrived some other way, which the next
    test covers."""
    p, wd = rig(mode="bad-barrier")
    assert p.returncode != 0
    assert "not in the closed list" in p.stdout
    m = manifest(wd)
    assert m["G"]["status"] == "stopped"
    assert "H" not in m and "J" not in m


def test_gate_J_halts_on_a_bad_barrier_it_is_handed_directly(rig, tmp_path):
    """Gate J in isolation, given an inventory it did not produce. This is the
    resumed-run path, where stage G's validation is not in front of it."""
    wd = tmp_path / "gateJ"
    p1, _ = rig(stages="A,B,C,D,E,F,G")          # get a good inventory in place
    assert p1.returncode == 0

    # hand-edit the inventory the way a resumed run might receive it
    inv = json.loads((p1 and (tmp_path / "wd" / "06-disposition"
                              / "inventory-dispositioned.json")).read_text())
    inv["rows"][1] = {"cid": "A1", "class": "C1", "disposition": "Dispositioned out",
                      "core": False, "barrier": "B99", "reason": "unjustified"}
    (tmp_path / "wd" / "06-disposition" / "inventory-dispositioned.json").write_text(
        json.dumps(inv))

    p2, _ = rig(stages="J", workdir=tmp_path / "wd")
    assert p2.returncode != 0
    assert "citing no barrier from the closed list" in p2.stdout


# ---------------------------------------------------------------------------
# Gate L, and the regression that motivates this file
# ---------------------------------------------------------------------------

def test_coverage_gap_halts_at_L_and_M_is_never_attempted(rig):
    p, wd = rig(mode="coverage-gap", stages="A,B,C,D,E,F,G,H,I,J,K,L,M")
    assert p.returncode != 0
    assert "RFC-COV-1 failed at freeze strength" in p.stdout
    m = manifest(wd)
    assert m["L"]["status"] == "stopped", "a failing gate must not record itself complete"
    assert "M" not in m, "the wave must not run after a failed freeze gate"


def test_a_failed_gate_is_not_bypassed_by_its_own_output_on_resume(rig, tmp_path):
    """THE regression.

    Stage L writes rfc-cov-1.txt and then fails. The driver used to skip any stage
    whose outputs existed, so the next invocation logged
    `STOP ... RFC-COV-1 failed` followed by `already complete, skipping`, and the
    wave proceeded against an unfrozen surface. Artifacts are evidence of activity,
    not of success.
    """
    wd = tmp_path / "resume"
    p1, _ = rig(mode="coverage-gap", workdir=wd)
    assert p1.returncode != 0
    assert (wd / "11-freeze" / "rfc-cov-1.txt").exists(), "the failing gate wrote output"
    assert manifest(wd)["L"]["status"] == "stopped"

    p2, _ = rig(mode="coverage-gap", workdir=wd)          # resume, artifacts present
    assert "stage L (coverage lint and freeze): already complete, skipping" not in p2.stdout
    assert p2.returncode != 0, "the gate must fire again, not be skipped"
    assert manifest(wd)["L"]["status"] == "stopped"


def test_a_completed_stage_is_still_skipped_on_resume(rig, tmp_path):
    """The fix must not have simply disabled resumption: a stage the manifest
    records complete, whose artifacts are present, is skipped."""
    wd = tmp_path / "warm"
    p1, _ = rig(workdir=wd)
    assert p1.returncode == 0
    p2, _ = rig(workdir=wd)
    assert p2.returncode == 0
    assert "already complete, skipping" in p2.stdout
    assert "stage D [agent] dual blind extraction" not in p2.stdout, \
        "an expensive completed stage must not re-run"


def test_artifacts_without_a_completion_record_force_a_rerun(rig, tmp_path):
    """A stage interrupted after writing output has artifacts but no record. It must
    re-run, and say why, rather than be trusted."""
    wd = tmp_path / "interrupted"
    p1, _ = rig(workdir=wd)
    assert p1.returncode == 0
    man = json.loads((wd / "MANIFEST.json").read_text())
    del man["stages"]["G"]                      # simulate dying mid-stage
    (wd / "MANIFEST.json").write_text(json.dumps(man))

    p2, _ = rig(workdir=wd)
    assert "artifacts present but no completion record" in p2.stdout
    assert manifest(wd)["G"]["status"] == "complete"


# ---------------------------------------------------------------------------
# Spec §5: presence is not integrity
# ---------------------------------------------------------------------------

def test_a_modified_artifact_forces_a_rerun(rig, tmp_path):
    """The driver recorded a digest of every artifact from the start and checked
    only .exists(), so a stage whose output had been edited since it completed was
    skipped and a later stage consumed something no stage of that run produced.

    This is not hypothetical: it happened twice in one day, hand-editing a body
    into the ARP tree and hand-editing an inventory in a test.
    """
    wd = tmp_path / "tamper"
    p1, _ = rig(workdir=wd)
    assert p1.returncode == 0

    inv = wd / "06-disposition" / "inventory-dispositioned.json"
    doc = json.loads(inv.read_text())
    doc["rows"][1]["reason"] = "edited outside the protocol"
    inv.write_text(json.dumps(doc))

    p2, _ = rig(workdir=wd)
    assert "artifact(s) changed since this stage recorded completion" in p2.stdout
    assert "06-disposition/inventory-dispositioned.json" in p2.stdout
    assert "stage G (disposition pass): already complete, skipping" not in p2.stdout


def test_an_untouched_run_still_skips_everything(rig, tmp_path):
    """The integrity check must not make every resume a full re-run."""
    wd = tmp_path / "intact"
    p1, _ = rig(workdir=wd)
    assert p1.returncode == 0
    p2, _ = rig(workdir=wd)
    assert p2.returncode == 0
    assert "artifact(s) changed" not in p2.stdout
    assert p2.stdout.count("already complete, skipping") >= 10


def test_a_manifest_without_digests_is_not_trusted(rig, tmp_path):
    """An artifact whose integrity was never recorded is not evidence."""
    wd = tmp_path / "nodigest"
    p1, _ = rig(workdir=wd)
    assert p1.returncode == 0
    man = json.loads((wd / "MANIFEST.json").read_text())
    man["stages"]["G"].pop("outputs", None)
    (wd / "MANIFEST.json").write_text(json.dumps(man))

    p2, _ = rig(workdir=wd)
    assert "artifact(s) changed since this stage recorded completion" in p2.stdout


def test_every_stage_declares_the_artifact_that_carries_its_result(rig):
    """The §5 check protects only DECLARED outputs. Stage M declared its report and
    not the tree it built, so the implementation itself was uncovered, which is how
    a hand-edited body entered the ARP tree unnoticed."""
    outs = {st.key: set(st.outputs) for st in drv.STAGES}
    assert "12-wave/roots.ast.json" in outs["M"], "the implementation must be declared"
    assert "11-freeze/ROOTS.txt" in outs["L"], "the monopoly list must be declared"
    assert "10-roots/roots.llmll" in outs["K"], "the frozen surface must be declared"
