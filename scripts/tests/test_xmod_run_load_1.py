"""XMOD-RUN-LOAD-1 / PBT-QUAL-1: multi-module programs in every command.

`check`, `build` and `verify` loaded a file's imported modules; `test`, `run`,
`patch`, `refine` and `repl` did not. Measured on v0.30.1 with the fixtures
under scripts/tests/fixtures/xmod_run_load/:

  * `test` reported the property over lib.f as skipped and exited 0 (T1, T2),
    and skipped a property whose subject calls an unexported helper (T3);
  * `run` failed with "call to unknown function 'lib.f'" (R1);
  * `patch` and `refine` reported PatchSuccess for the fill (lib.f "x"), which
    `check` then rejected (P1, F1);
  * `repl` checked an (import lib) line with no module cache (L1);
  * `patch --require-proof` refused a fill calling a contracted imported
    function, because its re-verify ran without the closure and reported the
    function as fallen back while `verify` proved the same file (P3).

Every cell here failed on v0.30.1 except P2, the control that a well-typed
fill is still accepted.
"""

import json
import os
import shlex
import shutil
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURES = REPO_ROOT / "scripts" / "tests" / "fixtures" / "xmod_run_load"

pytestmark = pytest.mark.skipif(
    not os.environ.get("LLMLL_BIN"),
    reason="set LLMLL_BIN to a built llmll; the spec-roundtrip job runs this in CI",
)

BUILD_TIMEOUT_S = 600
CMD_TIMEOUT_S = 120
FILL_POINTER = "/statements/1/body/args/1"


def _llmll() -> list[str]:
    return shlex.split(os.environ["LLMLL_BIN"])


def _run(args, cwd, stdin=None, timeout=CMD_TIMEOUT_S):
    return subprocess.run([*_llmll(), *args], cwd=str(cwd), input=stdin,
                          capture_output=True, text=True, timeout=timeout)


@pytest.fixture
def work(tmp_path) -> Path:
    for f in FIXTURES.glob("*.llmll"):
        shutil.copy(f, tmp_path / f.name)
    return tmp_path


def _test_json(work: Path, name: str):
    p = _run(["--json", "test", name], work)
    line = next((ln for ln in p.stdout.splitlines() if ln.startswith("{")), None)
    assert line, f"no JSON from test {name}: rc={p.returncode}\n{p.stdout[-800:]}{p.stderr[-800:]}"
    return p, json.loads(line)


def test_t1_property_over_qualified_import_is_evaluated(work):
    p, doc = _test_json(work, "main.llmll")
    assert (doc["passed"], doc["skipped"], doc["failed"]) == (1, 0, 0), doc
    assert p.returncode == 0


def test_t2_false_property_over_qualified_import_fails(work):
    p, doc = _test_json(work, "wrong.llmll")
    assert (doc["passed"], doc["skipped"], doc["failed"]) == (0, 0, 1), doc
    assert p.returncode != 0


def test_t3_helper_reached_only_through_a_forwarded_body(work):
    _, doc = _test_json(work, "usehelper.llmll")
    assert (doc["passed"], doc["skipped"], doc["failed"]) == (1, 0, 0), doc


def test_r1_run_loads_the_import_closure(work):
    p = _run(["run", "main.llmll"], work, stdin="x\n", timeout=BUILD_TIMEOUT_S)
    assert p.returncode == 0, f"rc={p.returncode}\n{p.stdout[-800:]}{p.stderr[-800:]}"
    assert p.stdout.strip().splitlines()[-1] == "42", p.stdout[-400:]


def _checkout_and_patch(work: Path, cmd: str, fill: dict, src: str = "fill",
                        pointer: str = FILL_POINTER, flags: tuple = ()):
    """Emit src.llmll to JSON-AST, check out its hole, apply one replace."""
    emit = work / "emit"
    p = _run(["build", f"{src}.llmll", "--emit", "-o", str(emit)], work, timeout=BUILD_TIMEOUT_S)
    assert p.returncode == 0, p.stdout[-800:] + p.stderr[-800:]
    target = work / f"{src}.ast.json"
    shutil.copy(emit / f"{src}.ast.json", target)
    co = _run(["--json", "checkout", target.name, pointer], work)
    assert co.returncode == 0, co.stdout[-800:] + co.stderr[-800:]
    token = json.loads(co.stdout)["token"]
    req = work / "patch.json"
    req.write_text(json.dumps({"token": token, "patch": [
        {"op": "replace", "path": pointer, "value": fill}]}), encoding="utf-8")
    before = target.read_text(encoding="utf-8")
    p = _run([cmd, *flags, target.name, req.name], work, timeout=BUILD_TIMEOUT_S)
    line = next((ln for ln in p.stdout.splitlines() if ln.startswith("{")), None)
    assert line, f"no JSON from {cmd}: {p.stdout[-800:]}{p.stderr[-800:]}"
    return json.loads(line), before, target.read_text(encoding="utf-8")


ILL_TYPED = {"kind": "app", "fn": "lib.f", "args": [{"kind": "lit-string", "value": "x"}]}
WELL_TYPED = {"kind": "app", "fn": "lib.f", "args": [{"kind": "lit-int", "value": 2}]}


@pytest.mark.parametrize("cmd", ["patch", "refine"], ids=["P1-patch", "F1-refine"])
def test_p1_f1_ill_typed_fill_over_import_is_rejected(work, cmd):
    res, before, after = _checkout_and_patch(work, cmd, ILL_TYPED)
    assert res["result"] == "PatchTypeError", res
    assert any(d.get("kind") == "type-mismatch" and "lib.f" in d.get("message", "")
               for d in res["diagnostics"]), res
    assert after == before, "a rejected fill must leave the file unchanged"


def test_p2_well_typed_fill_over_import_is_accepted(work):
    res, _, _ = _checkout_and_patch(work, "patch", WELL_TYPED)
    assert res["result"] == "PatchSuccess", res
    assert _run(["check", "fill.ast.json"], work).returncode == 0


def test_l1_repl_refuses_a_module_import_by_name(work):
    p = _run(["repl"], work, stdin="(import lib)\n:quit\n")
    assert "(import lib) needs a file" in p.stdout, p.stdout[-800:]


def test_p3_require_proof_accepts_a_fill_that_verify_proves(work):
    """Amendment A1: patch re-verifies against the import closure."""
    v = _run(["verify", "proved.llmll"], work, timeout=BUILD_TIMEOUT_S)
    assert v.returncode == 0, v.stdout[-800:] + v.stderr[-800:]
    call = {"kind": "app", "fn": "proved.idf", "args": [{"kind": "var", "name": "n"}]}
    res, _, _ = _checkout_and_patch(work, "patch", call, src="useproved",
                                    pointer="/statements/1/body", flags=("--require-proof",))
    assert res["result"] == "PatchSuccess", res
    assert res["verification"] == [{"body_faithful": True, "fn": "g"}], res

