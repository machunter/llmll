"""DRIVER-LL sub-phase 4b: the checks that do not need a built sequencer.

`scripts/driver_ll_cover.py` is the acceptance cover and it needs a toolchain,
so it runs in `scripts/build_smoke.sh`. Four things about 4b can be settled
without building anything, and each one is a place where the port and the
reference could drift with every cover cell still green:

  * the validation facility's SIGNATURE. `validate.verdict-of` takes
    `bool int int` and no string, and that is the whole of the port's answer to
    driver-spec section 7:288-291 ("a validator that hardcodes the values seen
    in one run will silently report emptiness on the next"). Widening it to
    take content would let a subject's conventions back in, and would do so in
    a change nothing else here would notice;

  * the FLOORS. `registry.stage-floor` is a hand-written table and the
    reference's floors are integer literals inside two `require` calls. Nothing
    in either language relates them, so they are related here, by AST rather
    than by grep;

  * stage I having NO validator, which is proposal section 9.1 item 2 and the
    reason its floor is negative. Measured by an AST census of the reference's
    `stage_I_prereg`, so that a validator added there makes the port's -1
    wrong LOUDLY instead of silently;

  * the reference's disposition when a delegated stage writes a valid declared
    output and exits non-zero. Proposal section 3.1 row 3 and section 10 case 4
    both say `complete`; the reference records `failed`. That is executed here
    rather than argued, because the port reproduces the reference and not the
    table, and a reader is entitled to the measurement.

AST, NOT GREP. Every claim about the reference below is made against a parsed
tree. A `require(` count over source text is not a census of halt sites: it
counts docstring mentions and the definition, which is exactly the error the
Phase 4 proposal's own Rev 8 stamp made and Rev 9 corrected.
"""
from __future__ import annotations

import ast
import json
import pathlib
import re
import stat
import subprocess
import sys

import pytest

REPO = pathlib.Path(__file__).resolve().parents[2]
DRIVER = REPO / "scripts" / "rfc_to_implementation.py"
RIG = REPO / "scripts" / "tests" / "test_rfc_pipeline_integration.py"
VALIDATE = REPO / "tools" / "llmll-driver" / "validate.llmll"
REGISTRY = REPO / "tools" / "llmll-driver" / "registry.llmll"
SEQUENCER = REPO / "tools" / "llmll-driver" / "sequencer.llmll"

TREE = ast.parse(DRIVER.read_text(), filename=str(DRIVER))
HALT_HELPERS = {"require", "require_spec", "require_written"}


def _fn(name: str) -> ast.FunctionDef:
    for node in TREE.body:
        if isinstance(node, ast.FunctionDef) and node.name == name:
            return node
    raise AssertionError(f"{name} is not a top-level function of {DRIVER.name}")


def _halt_sites(fn: ast.FunctionDef) -> list[str]:
    """Every halt this function performs in its OWN body.

    Calls to the three halt helpers plus bare `raise`. Calls the function makes
    into `ctx.agent.run` or `ctx.prompt` are NOT counted: those halt inside
    another frame, which is the distinction that makes "stage I holds zero halt
    calls" true and "stage I cannot fail" false.
    """
    out = []
    for n in ast.walk(fn):
        if isinstance(n, ast.Call) and isinstance(n.func, ast.Name) \
                and n.func.id in HALT_HELPERS:
            out.append(n.func.id)
        elif isinstance(n, ast.Raise):
            out.append("raise")
    return out


def _llmll_params(src: str, fn: str) -> list[tuple[str, str]]:
    """The declared parameter list of an LLMLL `def`, as (name, type)."""
    m = re.search(r"\(def %s \[([^\]]*)\]" % re.escape(fn), src)
    assert m, f"{fn} has no parameter list in the source"
    return re.findall(r"([\w?!-]+):\s*([\w\[\]]+)", m.group(1))


def _llmll_int_table(fn: str) -> dict[int, int]:
    """One `(if (= i N) V ...)` chain over ints out of registry.llmll."""
    block = REGISTRY.read_text().split(f"(def-shell {fn} ")[1].split("\n(def-shell ")[0]
    return {int(i): int(v) for i, v in re.findall(r"\(if \(= i (\d+)\) (\d+)", block)}


# ---------------------------------------------------------------------------
# 1. The facility's signature IS the subject-neutrality argument
# ---------------------------------------------------------------------------

def test_the_validation_decision_takes_no_subject_content():
    """driver-spec section 7:288-291, as a type rather than as a convention.

    verdict-of decides over presence, a measured length, and a floor the STAGE
    CONTRACT declares. No byte of the subject document, of the agent's output,
    or of any run's conventions is in scope, so none can be read. The
    accompanying postcondition [V7-NO-HARDCODE] is what refutes a body fitted
    to one run's sizes; this test is what stops the parameter list from
    quietly acquiring the string that would make such a body expressible.
    """
    params = _llmll_params(VALIDATE.read_text(), "verdict-of")
    assert [t for _, t in params] == ["bool", "int", "int"], (
        f"verdict-of's parameters are {params}. A `string` parameter here is "
        "how one subject's conventions get into a validator, which is the "
        "failure driver-spec section 7:288-291 names.")


def test_the_facility_proves_4b_constructs_no_stopped_outcome():
    """Proposal section 9.1 item 3, as three named postconditions.

    "A site that comes out `stopped` is wrong by construction." The three tags
    are what make that a proof over the delegated-output path rather than a
    reading of the code, and they are named here so a header rewrite that drops
    one is loud.
    """
    src = VALIDATE.read_text()
    for tag in ("[V7-MANDATORY]", "[V7-NO-STOP]", "[V7-NO-PARTIAL]",
                "[V7-ONLY-TWO]", "[V7-NO-HARDCODE]", "[V7-PRESENCE]",
                "[V7-FLOOR]", "[V7-NO-FLOOR]"):
        assert tag in src, f"validate.llmll no longer carries {tag}"


def test_the_sequencer_carries_the_4b_section_7_disclosure():
    """Section 7 owes a statement per ACTIVATED proved core, and 4b activates a
    third. The 4a pair is checked in test_driver_ll_4a_cover.py."""
    head = SEQUENCER.read_text().split("(module sequencer")[0]
    assert "[DISCLOSURE validate.verdict-of]" in head
    # The three shell-side decisions the statement owes, each named.
    assert "string-length" in head, "the code-points-not-bytes decision"
    assert "wasi.fs.read" in head, "the presence-and-decodability collapse"


# ---------------------------------------------------------------------------
# 2. The floors, related by AST to the reference's own literals
# ---------------------------------------------------------------------------

def _size_floor(fn_name: str) -> int:
    """The integer in `require(out.stat().st_size > N, ...)`."""
    for n in ast.walk(_fn(fn_name)):
        if (isinstance(n, ast.Call) and isinstance(n.func, ast.Name)
                and n.func.id == "require" and n.args
                and isinstance(n.args[0], ast.Compare)
                and isinstance(n.args[0].ops[0], ast.Gt)):
            left = n.args[0].left
            if (isinstance(left, ast.Attribute) and left.attr == "st_size"
                    and isinstance(n.args[0].comparators[0], ast.Constant)):
                return n.args[0].comparators[0].value
    raise AssertionError(f"{fn_name} declares no st_size floor")


def test_the_port_floors_are_the_references_floors():
    floors = _llmll_int_table("stage-floor")
    assert floors.get(1) == _size_floor("stage_B_scope"), "stage B"
    assert floors.get(2) == _size_floor("stage_C_rubric"), "stage C"


def test_stage_I_has_no_validator_in_the_reference():
    """Proposal section 9.1 item 2, and section 6.2's claim that stage O is the
    ONLY delegated stage with no validator is false because of it.

    The port encodes this as a NEGATIVE floor, which validate's [V7-NO-FLOOR]
    proves accepts every present output. If a validator is ever added to
    `stage_I_prereg`, that encoding becomes a silent under-check; this test is
    what makes it a red one instead.
    """
    assert _halt_sites(_fn("stage_I_prereg")) == [], (
        "stage_I_prereg has acquired a halt site. The port gives stage I a "
        "floor of -1 on the measured ground that it had none; update "
        "registry.stage-floor and validate.llmll's disclosure together.")
    # And the two that DO have one, so the census above is not vacuously green
    # against a parser that found nothing anywhere.
    assert _halt_sites(_fn("stage_B_scope")) == ["require"]
    assert _halt_sites(_fn("stage_C_rubric")) == ["require"]


def test_stage_O_also_has_no_validator_so_the_pair_is_the_finding():
    """Section 6.2 named stage O. Section 9.1 item 2 adds stage I. Both are
    measured, and both are deferred to 4f rather than invented at 4b."""
    assert _halt_sites(_fn("stage_O_writeup")) == []


# ---------------------------------------------------------------------------
# 3. The agent channel the two harnesses share
# ---------------------------------------------------------------------------

def test_the_rig_stub_still_reads_out_then_prompt_from_argv():
    """Proposal section 5 item 2: `wasi.proc.run` has no env parameter, so the
    two paths reach the agent through argv and the rig's stub was rewritten to
    read them there. The 4b cover's stub uses the same order. If the rig's ever
    changes, the two harnesses stop driving the same agent contract."""
    src = RIG.read_text()
    assert "sys.argv[1]" in src and "sys.argv[2]" in src
    m = re.search(r"out\s*=\s*pathlib\.Path\(sys\.argv\[(\d)\]\)", src)
    assert m and m.group(1) == "1", "the rig's stub takes {out} as argv[1]"
    m = re.search(r"prompt\s*=\s*pathlib\.Path\(sys\.argv\[(\d)\]\)", src)
    assert m and m.group(1) == "2", "the rig's stub takes {prompt} as argv[2]"


# ---------------------------------------------------------------------------
# 4. The measurement behind the correction to section 3.1 row 3
# ---------------------------------------------------------------------------

def test_a_valid_output_with_a_nonzero_exit_records_failed_in_the_reference(tmp_path):
    """Executed, not derived.

    `AgentRunner.run` raises on the exit status at :328-330, BEFORE the
    output-existence check at :331-334, so the output being present and valid
    never enters the decision. Proposal section 3.1 row 3 ("Declared output
    present and valid, agent exit non-zero -> complete") and section 10 case 4
    ("The stage is complete; ... no halt occurs and section 4 is not reached")
    therefore describe behaviour the reference does not have.

    The port reproduces the reference. Cover cell B4 is the port-side half of
    this measurement and asserts the same three facts against the binary.
    """
    agent = tmp_path / "agent.py"
    agent.write_text("import sys, pathlib\n"
                     "pathlib.Path(sys.argv[1]).write_text('-' * 900)\n"
                     "sys.exit(7)\n")
    agent.chmod(agent.stat().st_mode | stat.S_IXUSR)
    spec = tmp_path / "spec.txt"
    spec.write_text("1. Introduction\nA sender MUST ack.\n")
    wd = tmp_path / "wd"

    p = subprocess.run(
        [sys.executable, str(DRIVER), "--rfc-url", spec.resolve().as_uri(),
         "--workdir", str(wd),
         "--agent-cmd", f"{sys.executable} {agent} {{out}} {{prompt}}",
         # pytest's tmp_path is under /var/folders, which the driver refuses.
         "--allow-volatile-workdir", "--only", "A,B"],
        capture_output=True, text=True, cwd=str(REPO))

    out = wd / "01-scope" / "scope.md"
    assert out.exists() and out.stat().st_size > 200, (
        "the premise: the agent wrote a declared output that CLEARS stage B's "
        "200-byte floor, so validation would have passed")
    row = json.loads((wd / "MANIFEST.json").read_text())["stages"]["B"]
    assert row["status"] == "failed", row
    assert row["outcome"] == "Errored", row
    assert "clause" not in row, "a failed row carries no clause"
    assert p.returncode == 3
