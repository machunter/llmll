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
#
# ARGV, NOT ENV, for the two paths the driver supplies. `wasi.proc.run` takes
# (executable, argv, cwd, stdout-path, stderr-path, timeout) and has NO env
# parameter (TypeCheck.hs:192-193), so the LLMLL driver cannot set
# RFC_PIPELINE_OUT / RFC_PIPELINE_PROMPT and a stub that reads them is not
# portable across the two drivers this harness has to check. The template
# placeholders {out} and {prompt} are the channel both drivers can drive
# (DRIVER-LL Phase 4 proposal §5). STUB_MODE stays on the environment: it is the
# RIG's control channel, set on the driver process and inherited, not something
# either driver injects.
STUB_AGENT = r'''
import json, os, sys, pathlib
out    = pathlib.Path(sys.argv[1])
prompt = pathlib.Path(sys.argv[2])
mode   = os.environ.get("STUB_MODE", "ok")
name   = out.name

def rows(tag):
    return [{"id": f"{tag}{i}", "source": "SPEC", "line_start": 2 + i, "line_end": 2 + i,
             "quote": "q", "rule": "N1", "strength": "must",
             "obligation": f"obligation {i}"} for i in range(2)]

if name == "body.json":
    # Stage M: the AST node that replaces the hole. The stub `llmll` decides
    # whether a fill verifies, so the body only has to be well-formed JSON.
    json.dump({"kind": "int_lit", "value": 1}, out.open("w"))
elif name == "extraction.json":
    tag = "A" if "(extractor A)" in prompt.read_text() else "B"
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
#
# `build --emit`, `checkout`, `patch` and a tree-aware `verify` exist so that STAGE M
# CAN RUN AT ALL. Before they did, no test in this file executed the wave: stage M
# appeared only in an assertion that it had NOT run after a halted gate L. The wave
# carries the fill protocol, the two retry budgets and the token discipline, which is
# the largest untested surface in the pipeline and the same shape as the defect class
# BUILD-GATE-1 was created for.
#
# Under STUB_MODE=wave the stub injects, in order: a STALE first patch (contention,
# which `_apply` must retry WITHOUT consulting the agent and WITHOUT spending the
# error budget) and then one unfaithful verify (a wrong body, which DOES spend it).
# Contention is unreachable under a serial wave by construction -- one writer, and
# `_apply` re-checkouts under the lock immediately before patching -- so injecting it
# here is the only way the branch fires at all.
STUB_LLMLL = r'''#!/usr/bin/env python3
import json, os, re, sys, pathlib

MODE = os.environ.get("STUB_MODE", "ok")

def state(tree):
    p = pathlib.Path(str(tree) + ".stub.json")
    return p, (json.loads(p.read_text()) if p.exists() else {"patch": 0, "treeverify": 0})

def bump(tree, key):
    p, st = state(tree)
    st[key] = st.get(key, 0) + 1
    p.write_text(json.dumps(st))
    return st[key]

def resolve(doc, pointer):
    node, segs = doc, pointer.strip("/").split("/")
    for seg in segs[:-1]:
        node = node[int(seg)] if seg.isdigit() else node[seg]
    return node, segs[-1]

argv = sys.argv[1:]
cmd  = argv[0] if argv else ""

if cmd == "check":
    print("OK"); sys.exit(0)

if cmd == "build":
    outdir = pathlib.Path(argv[argv.index("-o") + 1])
    outdir.mkdir(parents=True, exist_ok=True)
    (outdir / "roots.ast.json").write_text(json.dumps(
        {"module": "roots",
         "statements": [{"kind": "def", "name": "fn0", "body": {"kind": "hole"}}]}))
    print("emitted"); sys.exit(0)

if cmd == "checkout":
    tree = pathlib.Path(argv[1])
    if "--release" in argv:
        sys.exit(0)
    n = bump(tree, "checkout")
    print(json.dumps({"token": f"tok-{n}", "pointer": argv[2],
                      "function": "fn0", "expected_return_type": "int"}))
    sys.exit(0)

if cmd == "patch":
    tree = pathlib.Path(argv[1])
    n = bump(tree, "patch")
    if MODE == "wave" and n == 1:
        print("PatchAuthError: obligation context is stale", file=sys.stderr)
        sys.exit(1)
    req = json.loads(pathlib.Path(argv[2]).read_text())
    doc = json.loads(tree.read_text())
    for op in req["patch"]:
        if op["op"] == "replace":
            node, last = resolve(doc, op["path"])
            node[int(last) if last.isdigit() else last] = op["value"]
    tree.write_text(json.dumps(doc))
    print("PatchSuccess"); sys.exit(0)

if cmd == "verify":
    target = pathlib.Path(argv[1])
    if "--trust-report" in argv:
        cites = re.findall(r'\[([A-Za-z0-9]+)\]', target.read_text())
        print(json.dumps({"entries": [
            {"name": f"fn{i}", "post_sources": [f"[{c}] SPEC line"]}
            for i, c in enumerate(cites)]}))
        sys.exit(0)
    if target.name.endswith(".ast.json"):
        n = bump(target, "treeverify")
        doc = json.loads(target.read_text())
        filled = [st["name"] for st in doc["statements"]
                  if not str(st.get("body", {}).get("kind", "")).startswith("hole")]
        # The wrong body: reported SAFE but NOT body-faithful, which is what the
        # per-fill bar rejects. Deliberately not the word "refuted", so the test
        # exercises the faithfulness half rather than the refutation half.
        if MODE == "wave" and n == 1:
            filled = []
        print(f"   body-faithful: {', '.join(filled) if filled else '(none)'}")
        print(f"OK {target} - SAFE (liquid-fixpoint)")
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
               # {out} and {prompt} are AgentRunner template placeholders, and they
               # are the whole channel: the stub reads argv, not the environment.
               "--agent-cmd", f"{sys.executable} {agent} {{out}} {{prompt}}",
               "--llmll-cmd", str(llmll),   # a single executable: the driver uses it as argv[0]
               # pytest's tmp_path lives under /var/folders, which the driver
               # refuses as a run directory. These runs really are throwaway,
               # which is precisely the case the override exists for.
               "--allow-volatile-workdir",
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

    # Check the PREMISE before the conclusion. This test once failed on a
    # thrashing machine in a way that read exactly like "gate L is broken", when
    # gate L was provably firing when driven by hand. The two halves are worth
    # telling apart: if the stub never produced a gap there was nothing for the
    # gate to catch, and that is a rig fault, not a gate fault.
    assert "Encoded rows cited : 1/2" in p.stdout, (
        "the coverage-gap scenario did not produce a gap, so this says nothing "
        "about gate L:\n" + p.stdout)

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


# ---------------------------------------------------------------------------
# Losing a run to the operating system is a bug in the driver, not bad luck
# ---------------------------------------------------------------------------

def _bare(tmp_path, workdir, url=None, extra=None):
    """Drive the driver WITHOUT the rig's --allow-volatile-workdir, which is the
    whole point of these two tests."""
    spec = tmp_path / "spec.txt"
    spec.write_text(SPEC)
    cmd = [sys.executable, str(DRIVER),
           "--rfc-url", url or spec.resolve().as_uri(),
           "--workdir", str(workdir),
           "--agent-cmd", "true",
           "--only", "A"]
    return subprocess.run(cmd + (extra or []), capture_output=True, text=True, cwd=REPO)


def test_a_volatile_workdir_is_refused_before_any_stage_runs(tmp_path):
    """A reboot destroyed an eight-stage RFC 4648 run whose workdir was under
    /private/tmp: the whole tree was recreated at boot. The run directory IS the
    experimental record, so the driver must refuse a location the OS may reclaim,
    and must refuse it BEFORE spending a stage on it."""
    wd = pathlib.Path("/tmp/rfc-swarm-volatile-guard-test")
    p = _bare(tmp_path, wd)
    assert p.returncode == 2, p.stdout + p.stderr
    assert "may clear at any time" in p.stdout
    assert "stage A" not in p.stdout, "it must refuse before running anything"
    assert not wd.exists(), "a refused run must not leave a directory behind"
    # The alternative it offers has to satisfy BOTH constraints. Durable is not
    # enough: inside the repo the workdir would sit beside the committed records
    # of earlier runs, which are worked answers, and section 8 blindness dies.
    assert "outside this repository" in p.stdout


def test_the_volatile_override_warns_but_proceeds(tmp_path):
    """The escape hatch has to exist (pytest's own tmp_path is volatile) and it has
    to be loud, or the guard just teaches people to pass the flag silently."""
    p = _bare(tmp_path, tmp_path / "vol", extra=["--allow-volatile-workdir"])
    assert "WARNING" in p.stdout and "may not survive a reboot" in p.stdout
    assert "stage A" in p.stdout


# ---------------------------------------------------------------------------
# A crash is not a stop, and neither may be silent
# ---------------------------------------------------------------------------

def test_a_crashing_stage_is_recorded_rather_than_escaping_as_a_traceback(rig, tmp_path):
    """An unhandled exception used to leave NOTHING in the manifest, so a resume
    could not tell `crashed` from `never ran`. It is also reported as FAILED, not
    STOPPED: a stop is a verdict the method reached and is a result, a crash is an
    accident and is not. Conflating them would let a dead run read as a fired gate."""
    wd = tmp_path / "crash"
    p, _ = rig(workdir=wd, stages="A", extra=["--rfc-url", "http://127.0.0.1:9/x.txt"])
    assert p.returncode == 3, p.stdout + p.stderr
    assert manifest(wd)["A"]["status"] == "failed"
    assert "URLError" in manifest(wd)["A"]["detail"]
    assert "Traceback" in p.stderr, "the traceback still has to reach the operator"

    st = subprocess.run([sys.executable, str(DRIVER), "--status", "--workdir", str(wd)],
                        capture_output=True, text=True, cwd=REPO)
    assert "! FAILED" in st.stdout and "STOPPED" not in st.stdout


# ---------------------------------------------------------------------------
# Section 9: the wave, the fill protocol, and the two retry budgets
#
# No test in this file ran stage M before these. It appeared once, in an
# assertion that it had NOT run after a halted gate L, and once in the
# artifact-declaration check. The wave carries the fill protocol, the separated
# budgets and the token discipline -- the largest untested surface here.
# ---------------------------------------------------------------------------

# G2 is absent, and deliberately, matching the stage list every test above uses.
# Driving it surfaced a SECOND never-executed stage: with G2 in the list the run
# reaches it and reports "unresolved: 2" before stopping on the stub's audit shape,
# because the stub's rows quote "q" against SPEC lines that do not contain it, so
# `_span_coverage` scores every citation below CITATION_RESOLVES_AT. Making G2 pass
# needs stub rows whose quotes are drawn from the pinned bytes, which is its own
# item; it is not the wave's premise and is filed rather than bundled here.
ALL_STAGES = "A,B,C,D,E,F,G,H,I,J,K,L,M"


def _wave(wd):
    return json.loads((wd / "12-wave" / "wave.json").read_text())


def test_the_wave_fills_a_hole(rig, tmp_path):
    """The PREMISE for the contention test below. If the wave cannot fill a hole
    with no injection at all, a later assertion about WHY it took two attempts
    says nothing."""
    p, wd = rig(stages=ALL_STAGES, workdir=tmp_path / "wave-ok")
    assert p.returncode == 0, p.stdout + p.stderr
    w = _wave(wd)
    assert [f["status"] for f in w["fills"]] == ["filled"], w
    assert w["fills"][0]["attempts"] == 1, "no injection, so no retry"
    assert w["whole_tree"]["safe"], w["whole_tree"]


def test_contention_does_not_consume_the_error_budget(rig, tmp_path):
    """driver-spec section 9: "Two retry budgets MUST be counted separately...
    Contention MUST NOT consume the budget for error."

    The stub rejects the first `patch` with PatchAuthError and reports the first
    filled tree as not body-faithful. So the hole sees one CONTENTION event and
    one SEMANTIC failure, and finishes on attempt 2 rather than attempt 3: the
    contention retry re-submitted the SAME body against a fresh checkout without
    consulting the agent, and cost nothing.

    This is the only route by which the branch fires. Under a serial wave there
    is one writer and `_apply` re-checkouts under the lock immediately before
    patching, so `contention = true` is unreachable by construction and
    `fill.next-error-budget`'s proved separation is never exercised at run time.
    """
    p, wd = rig(mode="wave", stages=ALL_STAGES, workdir=tmp_path / "wave-contended")
    assert p.returncode == 0, p.stdout + p.stderr
    w = _wave(wd)
    assert [f["status"] for f in w["fills"]] == ["filled"], w
    assert w["fills"][0]["attempts"] == 2, (
        "one semantic failure spends one attempt; the contention retry must spend "
        "none. attempts==3 would mean contention ate the error budget: " + str(w))

    # The premise, checked rather than assumed: contention really did happen.
    st = json.loads((wd / "12-wave" / "roots.ast.json.stub.json").read_text())
    assert st["patch"] == 3, (
        "expected patch calls: 1 stale, 1 accepted-then-reverted, 1 accepted. "
        f"got {st['patch']}")


# ---------------------------------------------------------------------------
# Transition cover: the two manifest transitions nothing above reaches
# ---------------------------------------------------------------------------

def test_a_failed_stage_is_re_run_on_resume(rig, tmp_path):
    """Spec section 5: "A stage recorded stopped or failed MUST be run, however many
    artifacts a previous attempt left behind." The stopped half is covered by the
    gate-L regression above; this is the failed half."""
    wd = tmp_path / "failed-resume"
    p1, _ = rig(workdir=wd, stages="A", extra=["--rfc-url", "http://127.0.0.1:9/x.txt"])
    assert p1.returncode == 3
    assert manifest(wd)["A"]["status"] == "failed"

    p2, _ = rig(workdir=wd, stages="A")          # good URL this time
    assert p2.returncode == 0, p2.stdout + p2.stderr
    assert "already complete, skipping" not in p2.stdout
    assert manifest(wd)["A"]["status"] == "complete"


def test_force_re_runs_a_stage_the_manifest_records_complete(rig, tmp_path):
    """Spec section 5: "When the operator requests a forced re-run, the driver MUST
    run the stage regardless of its record." The proved core says so too, as the
    [S5-FORCE] post on skip.may-skip."""
    wd = tmp_path / "forced"
    p1, _ = rig(workdir=wd, stages="A,B,C")
    assert p1.returncode == 0
    assert "already complete, skipping" not in p1.stdout

    p2, _ = rig(workdir=wd, stages="A,B,C")
    assert "already complete, skipping" in p2.stdout, "premise: a warm run skips"

    p3, _ = rig(workdir=wd, stages="A,B,C", extra=["--force"])
    assert p3.returncode == 0, p3.stdout + p3.stderr
    assert "already complete, skipping" not in p3.stdout, "--force must override the record"
    assert "stage C [agent] normativity rubric" in p3.stdout
