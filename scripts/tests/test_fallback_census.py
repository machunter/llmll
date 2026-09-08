"""FALLBACK-CENSUS-1 cover for scripts/fallback_census.py.

Two tiers, on the precedent of the driver covers.

The NO-TOOLCHAIN tier builds a synthetic repository and a stub compiler that
prints canned JSON, so every classification rule is pinned without a build. The
rules are the whole point of the instrument: the census exists because the same
population was hand-counted three times and the first two counts were wrong in
the same direction, so a rule that silently changes is the failure this cover is
here to catch.

The LLMLL_BIN tier runs the REAL compiler over three fixtures and pins the two
labels the compiler gained for this row. It is skipped without a built
compiler, and the version-gate job that has one runs it.
"""
from __future__ import annotations

import json
import os
import shlex
import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
CENSUS = REPO_ROOT / "scripts" / "fallback_census.py"
FIXTURES = Path(__file__).resolve().parent / "fixtures" / "fallback-census"


# ---------------------------------------------------------------------------
# The synthetic repository and its stub compiler
# ---------------------------------------------------------------------------

STUB = '''#!/usr/bin/env python3
"""A stub `llmll`: prints the canned verdict recorded for the named file."""
import json, os, sys, time
name = sys.argv[-1]
table = json.load(open(os.environ["STUB_TABLE"]))
verdict = table.get(name)
if verdict is None:
    print("error: no canned verdict for " + name)
    sys.exit(1)
if verdict.get("sleep"):
    time.sleep(verdict["sleep"])
if verdict.get("exit") == 3:
    print("SOLVER NOT FOUND -- NOTHING WAS PROVEN")
    sys.exit(3)
if verdict.get("check_error"):
    print("warning: a warning that is not the cause")
    print("error: " + verdict["check_error"])
    sys.exit(1)
# A verdict may flip between the loaded pass and the confirmation pass: the
# counter file records how many times this file has been asked.
counts_path = os.environ.get("STUB_COUNTS")
if counts_path and verdict.get("then"):
    counts = json.load(open(counts_path)) if os.path.exists(counts_path) else {}
    n = counts.get(name, 0)
    counts[name] = n + 1
    json.dump(counts, open(counts_path, "w"))
    if n >= 1:
        verdict = verdict["then"]
# `llmll verify` writes a sidecar beside the file; the stub does too, so the
# cover exercises the census's cleanup.
open(name + ".verified.json", "w").write("{}\\n")
print(json.dumps(verdict["json"]))
sys.exit(verdict.get("exit", 0))
'''


def make_repo(tmp_path: Path, files: dict[str, dict], extra: dict[str, str] | None = None) -> Path:
    """A git repository with the named LLMLL files and a canned verdict for each."""
    repo = tmp_path / "repo"
    (repo / "examples").mkdir(parents=True)
    (repo / "LLMLL.md").write_text("# LLMLL — v0.0.0\n", encoding="utf-8")
    for name in files:
        (repo / "examples" / name).write_text(";; census fixture\n", encoding="utf-8")
    for rel, body in (extra or {}).items():
        target = repo / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(body, encoding="utf-8")
    subprocess.run(["git", "init", "-q"], cwd=repo, check=True)
    subprocess.run(["git", "add", "-A"], cwd=repo, check=True)
    table = {name: verdict for name, verdict in files.items()}
    (tmp_path / "table.json").write_text(json.dumps(table), encoding="utf-8")
    return repo


def stub_cmd(tmp_path: Path) -> str:
    stub = tmp_path / "stub_llmll.py"
    stub.write_text(STUB, encoding="utf-8")
    return f"{shlex.quote(sys.executable)} {shlex.quote(str(stub))}"


def run_census(tmp_path: Path, repo: Path, *args: str, env_extra: dict[str, str] | None = None):
    env = dict(os.environ)
    env["STUB_TABLE"] = str(tmp_path / "table.json")
    env["STUB_COUNTS"] = str(tmp_path / "counts.json")
    env.pop("GITHUB_STEP_SUMMARY", None)
    env.update(env_extra or {})
    return subprocess.run(
        [sys.executable, str(CENSUS), "--llmll", stub_cmd(tmp_path), "--repo", str(repo), *args],
        capture_output=True,
        text=True,
        env=env,
    )


def ok(faithful: list[str], causes: dict[str, str], kinds: dict[str, str],
       constructs: dict[str, list[str]] | None = None) -> dict:
    return {"json": {"body_faithful": faithful, "body_fallback": sorted(causes),
                     "body_fallback_causes": causes, "fn_kinds": kinds,
                     "body_fallback_constructs": constructs or {}, "success": True}}


def refused(faithful: list[str], causes: dict[str, str], kinds: dict[str, str],
            constructs: dict[str, list[str]] | None = None) -> dict:
    payload = ok(faithful, causes, kinds, constructs)["json"]
    payload["strict_errors"] = [{"cause": "fallback", "fns": sorted(causes), "msg": "fell back"}]
    return {"json": payload, "exit": 1}


# A population that exercises every outcome and every counting rule at once.
POPULATION = {
    "pass.llmll": ok(["a", "b"], {}, {"a": "def", "b": "def"}),
    "fallback.llmll": refused(["c"], {"d": "contract-post-outside-fragment"},
                              {"c": "def-shell", "d": "def-shell"},
                              {"d": ["nonlinear:*", "app:string-concat"]}),
    "scaffold.llmll": refused([], {"e": "unfilled-hole", "f": "unfilled-hole"},
                              {"e": "def-shell", "f": "def-shell"}),
    "nogoal.llmll": refused([], {"g": "no-post", "h": "unfilled-hole"},
                            {"g": "def", "h": "def"}),
    "refuted.llmll": {"json": {"body_faithful": ["i"], "body_fallback": [],
                               "body_fallback_causes": {}, "fn_kinds": {"i": "def"},
                               "success": False}, "exit": 1},
    "broken.llmll": {"check_error": "call to unknown function 'nope'"},
}


# ---------------------------------------------------------------------------
# No-toolchain tier
# ---------------------------------------------------------------------------

def test_ratio_counts_only_functions_with_a_goal(tmp_path):
    repo = make_repo(tmp_path, POPULATION)
    out = tmp_path / "record.json"
    r = run_census(tmp_path, repo, "--no-ratchet", "--out", str(out), "--jobs", "2")
    assert r.returncode == 0, r.stdout + r.stderr
    rec = json.loads(out.read_text())
    # a, b, c, i are body-faithful; d is the only fallback that keeps a goal.
    assert rec["ratio"]["body_faithful"] == 4
    assert rec["ratio"]["fallback"] == 1
    assert rec["ratio"]["denominator"] == 5
    assert rec["ratio"]["value"] == pytest.approx(0.8)
    # e, f, h are holes and g has no post: four functions carry no goal.
    assert rec["ratio"]["excluded_no_goal"] == 4


def test_causes_and_constructs_are_counted_per_function(tmp_path):
    repo = make_repo(tmp_path, POPULATION)
    out = tmp_path / "record.json"
    run_census(tmp_path, repo, "--no-ratchet", "--out", str(out))
    rec = json.loads(out.read_text())
    assert rec["causes"] == {
        "contract-post-outside-fragment": 1,
        "no-post": 1,
        "unfilled-hole": 3,
    }
    assert rec["constructs"] == {"app:string-concat": 1, "nonlinear:*": 1}


def test_kinds_split_faithful_fallback_and_excluded(tmp_path):
    repo = make_repo(tmp_path, POPULATION)
    out = tmp_path / "record.json"
    run_census(tmp_path, repo, "--no-ratchet", "--out", str(out))
    rec = json.loads(out.read_text())
    assert rec["kinds"]["def"] == {"faithful": 3, "fallback": 0, "excluded": 2}
    assert rec["kinds"]["def-shell"] == {"faithful": 1, "fallback": 1, "excluded": 2}


def test_every_file_outcome_is_distinguished(tmp_path):
    repo = make_repo(tmp_path, POPULATION)
    out = tmp_path / "record.json"
    run_census(tmp_path, repo, "--no-ratchet", "--out", str(out))
    rec = json.loads(out.read_text())
    got = {p.split("/")[-1]: v["outcome"] for p, v in rec["files"].items()}
    assert got == {
        "pass.llmll": "pass",
        "fallback.llmll": "fallback",
        "scaffold.llmll": "scaffold",
        "nogoal.llmll": "no-goal",
        "refuted.llmll": "refuted",
        "broken.llmll": "check-failed",
    }


def test_check_failure_reports_the_error_line_not_the_warning(tmp_path):
    repo = make_repo(tmp_path, POPULATION)
    out = tmp_path / "record.json"
    run_census(tmp_path, repo, "--no-ratchet", "--out", str(out))
    rec = json.loads(out.read_text())
    detail = rec["files"]["examples/broken.llmll"]["detail"]
    assert detail.startswith("error: call to unknown function")


def test_a_verdict_that_disagrees_with_itself_is_reported_unstable(tmp_path):
    files = {
        "flip.llmll": {
            "json": {"body_faithful": ["x"], "body_fallback": [], "body_fallback_causes": {},
                     "fn_kinds": {"x": "def"}, "success": False},
            "exit": 1,
            "then": ok(["x"], {}, {"x": "def"}),
        }
    }
    repo = make_repo(tmp_path, files)
    out = tmp_path / "record.json"
    r = run_census(tmp_path, repo, "--no-ratchet", "--out", str(out))
    assert r.returncode == 0, r.stdout
    rec = json.loads(out.read_text())
    assert rec["files"]["examples/flip.llmll"]["outcome"] == "unstable"
    assert "disagreed with itself" in r.stdout


def test_a_timeout_fails_and_names_the_file(tmp_path):
    files = {"slow.llmll": {"sleep": 3, "json": {"body_faithful": [], "success": True}}}
    repo = make_repo(tmp_path, files)
    r = run_census(tmp_path, repo, "--no-ratchet", "--timeout", "1")
    assert r.returncode == 1
    assert "slow.llmll" in r.stdout and "timeout" in r.stdout


def test_a_missing_solver_fails_closed_and_never_skips(tmp_path):
    files = {"any.llmll": {"exit": 3, "json": {}}}
    repo = make_repo(tmp_path, files)
    r = run_census(tmp_path, repo, "--no-ratchet")
    assert r.returncode == 2
    assert "liquid-fixpoint is not on PATH" in r.stdout
    assert "proved nothing" in r.stdout


def test_an_unknown_cause_fails_rather_than_folding_silently(tmp_path):
    files = {"weird.llmll": refused([], {"z": "brand-new-cause"}, {"z": "def"})}
    repo = make_repo(tmp_path, files)
    r = run_census(tmp_path, repo, "--no-ratchet")
    assert r.returncode == 1
    assert "unknown fallback cause" in r.stdout and "brand-new-cause" in r.stdout


def test_a_missing_baseline_fails_rather_than_skipping(tmp_path):
    repo = make_repo(tmp_path, POPULATION)
    r = run_census(tmp_path, repo)
    assert r.returncode == 1
    assert "no baseline" in r.stdout


def test_write_baseline_then_check_passes(tmp_path):
    repo = make_repo(tmp_path, POPULATION)
    w = run_census(tmp_path, repo, "--write-baseline")
    assert w.returncode == 0, w.stdout
    baseline = json.loads((repo / "scripts" / "fallback-census" / "BASELINE.json").read_text())
    assert baseline["strict_pass"] == ["examples/pass.llmll"]
    r = run_census(tmp_path, repo)
    assert r.returncode == 0, r.stdout


def test_the_ratchet_fails_when_a_passing_file_stops_passing(tmp_path):
    repo = make_repo(tmp_path, POPULATION)
    run_census(tmp_path, repo, "--write-baseline")
    demoted = dict(POPULATION)
    demoted["pass.llmll"] = refused([], {"a": "body-outside-fragment"}, {"a": "def"})
    (tmp_path / "table.json").write_text(json.dumps(demoted), encoding="utf-8")
    r = run_census(tmp_path, repo)
    assert r.returncode == 1
    assert "examples/pass.llmll" in r.stdout
    assert "does not now" in r.stdout


def test_a_waiver_with_a_reason_lets_the_set_shrink(tmp_path):
    repo = make_repo(tmp_path, POPULATION)
    run_census(tmp_path, repo, "--write-baseline")
    bpath = repo / "scripts" / "fallback-census" / "BASELINE.json"
    baseline = json.loads(bpath.read_text())
    baseline["waivers"] = {"examples/pass.llmll": "retired with the example, 2026-09-08"}
    bpath.write_text(json.dumps(baseline), encoding="utf-8")
    demoted = dict(POPULATION)
    demoted["pass.llmll"] = refused([], {"a": "body-outside-fragment"}, {"a": "def"})
    (tmp_path / "table.json").write_text(json.dumps(demoted), encoding="utf-8")
    r = run_census(tmp_path, repo)
    assert r.returncode == 0, r.stdout


def test_an_empty_waiver_reason_does_not_count(tmp_path):
    repo = make_repo(tmp_path, POPULATION)
    run_census(tmp_path, repo, "--write-baseline")
    bpath = repo / "scripts" / "fallback-census" / "BASELINE.json"
    baseline = json.loads(bpath.read_text())
    baseline["waivers"] = {"examples/pass.llmll": "   "}
    bpath.write_text(json.dumps(baseline), encoding="utf-8")
    demoted = dict(POPULATION)
    demoted["pass.llmll"] = refused([], {"a": "body-outside-fragment"}, {"a": "def"})
    (tmp_path / "table.json").write_text(json.dumps(demoted), encoding="utf-8")
    r = run_census(tmp_path, repo)
    assert r.returncode == 1


def test_the_population_is_the_tracked_tree_and_excludes_sidecars(tmp_path):
    repo = make_repo(tmp_path, POPULATION,
                     extra={".gitignore": "examples/generated/\n"})
    # Untracked build output and a sidecar must not enter the population.
    (repo / "examples" / "generated").mkdir()
    (repo / "examples" / "generated" / "out.llmll").write_text(";; build output\n", encoding="utf-8")
    (repo / "examples" / "pass.llmll.verified.json").write_text("{}\n", encoding="utf-8")
    subprocess.run(["git", "add", "-A"], cwd=repo, check=True)
    out = tmp_path / "record.json"
    r = run_census(tmp_path, repo, "--no-ratchet", "--out", str(out))
    assert r.returncode == 0, r.stdout
    rec = json.loads(out.read_text())
    assert rec["population"]["files"] == len(POPULATION)
    assert all("generated" not in p for p in rec["files"])
    assert all(not p.endswith(".verified.json") for p in rec["files"])


def test_the_measured_tree_is_not_modified(tmp_path):
    repo = make_repo(tmp_path, POPULATION)
    before = subprocess.run(["git", "status", "--porcelain"], cwd=repo,
                            capture_output=True, text=True).stdout
    run_census(tmp_path, repo, "--no-ratchet")
    after = subprocess.run(["git", "status", "--porcelain"], cwd=repo,
                           capture_output=True, text=True).stdout
    assert before == after
    assert not list(repo.rglob("*.verified.json"))


def test_the_step_summary_carries_the_tables(tmp_path):
    repo = make_repo(tmp_path, POPULATION)
    summary = tmp_path / "summary.md"
    r = run_census(tmp_path, repo, "--no-ratchet", "--summary", str(summary))
    assert r.returncode == 0, r.stdout
    text = summary.read_text()
    assert "FALLBACK-CENSUS-1" in text
    assert "| Fallback cause | Functions |" in text
    assert "`unfilled-hole` | 3" in text
    assert "| Refusing construct | Clauses |" in text


def test_the_record_carries_no_timestamp_so_two_runs_diff_cleanly(tmp_path):
    repo = make_repo(tmp_path, POPULATION)
    first, second = tmp_path / "a.json", tmp_path / "b.json"
    run_census(tmp_path, repo, "--no-ratchet", "--out", str(first))
    (tmp_path / "counts.json").unlink(missing_ok=True)
    run_census(tmp_path, repo, "--no-ratchet", "--out", str(second), "--jobs", "3")
    assert first.read_bytes() == second.read_bytes()


# ---------------------------------------------------------------------------
# LLMLL_BIN tier: the real compiler decides
# ---------------------------------------------------------------------------

real_compiler = pytest.mark.skipif(
    not os.environ.get("LLMLL_BIN"),
    reason="set LLMLL_BIN to a built llmll; the version-gate toolchain job runs this",
)


def verify_report(*args: str) -> dict:
    """Run the real compiler over a fixture and return its JSON report.

    The failure message is the point. All three cells below call `llmll verify`,
    which shells out to liquid-fixpoint; with no solver on PATH it exits 3 and
    prints no report, and the cells then died on a missing dict key that named
    neither the solver nor the step order. That is how these three failed on
    their first CI run at v0.22.0.
    """
    llmll = shlex.split(os.environ["LLMLL_BIN"])
    proc = subprocess.run(
        llmll + ["--json", "verify", *args],
        cwd=str(FIXTURES), capture_output=True, text=True,
    )
    lines = [ln for ln in proc.stdout.splitlines() if ln.startswith("{")]
    where = f"exit {proc.returncode}; stdout: {proc.stdout.strip()[:300]!r}"
    assert lines, f"the compiler printed no JSON report ({where})"
    payload = json.loads(lines[-1])
    assert "body_faithful" in payload, (
        "the report carries no body-faithful keys, so the emitter never ran. "
        f"Exit 3 means liquid-fixpoint is not on PATH and this step must run "
        f"after the toolchain step ({where})"
    )
    return payload


@real_compiler
def test_real_compiler_labels_the_two_new_causes():
    payload = verify_report("census-causes.llmll")
    causes = payload["body_fallback_causes"]
    assert causes["no_contract"] == "no-post"
    assert causes["pre_only"] == "no-post"
    assert causes["scaffold"] == "unfilled-hole"
    assert causes["nested_hole"] == "unfilled-hole"
    assert payload["fn_kinds"]["no_contract"] == "def"
    assert payload["fn_kinds"]["scaffold"] == "def-shell"


@real_compiler
def test_real_compiler_names_the_refusing_constructs():
    payload = verify_report("census-constructs.llmll")
    constructs = payload["body_fallback_constructs"]
    assert constructs["nonlinear_post"] == ["nonlinear:*"]
    assert constructs["string_post"] == ["app:string-concat"]
    assert payload["body_fallback_causes"]["nonlinear_post"] == "contract-post-outside-fragment"


@real_compiler
def test_real_compiler_keeps_a_body_faithful_file_faithful():
    payload = verify_report("--strict-verified-core", "census-pass.llmll")
    assert "strict_errors" not in payload
    assert sorted(payload["body_faithful"]) == ["clamp", "nonneg"]
