"""DRIVER-LL sub-phase 4f: the checks that need no built sequencer.

4f ports stage O, the last stage this program stubs that is its own to land,
and writes the validator driver-spec sec 13 asks for. The reference has NONE:
`stage_O_writeup` is the only delegated stage in the driver with zero
`require()` sites, so 4f is the one sub-phase that adds behaviour rather than
reproducing it, and every check below exists because a port that invents a
validator can invent the wrong one.

The acceptance cover (`scripts/driver_ll_cover.py`, cells O1 to O4) runs the
built sequencer and needs a toolchain. Everything below is a place the port and
the reference, or the port and the specification, can drift with every cover
cell still green.

Ten things about 4f are settleable statically:

  * `stage_O_writeup` holds zero `require` calls, which is the premise the
    whole sub-phase rests on (proposal section 6.2);
  * the agent's file and the DECLARED output are different files, the third
    instance of the inverted artifact flow after H and N;
  * the five prompt inputs are the reference's, in the reference's keyword
    order, and each is OPTIONAL there;
  * mode 4 exists because of that, and stage O is its only user;
  * the substitute for an absent optional input is the reference's own string;
  * driver-spec sec 13 carries eight MUSTs and exactly one is mechanizable;
  * `omission-free?` is forwarded exactly once, the 4d and 4e discipline;
  * the port now constructs `PartialThenHalt` at TWO stage sites, and the
    second one decides AFTER the copy that is stage O's declared write;
  * the survivor predicate is shared with stage N rather than re-derived;
  * the cover holds a cell that can actually fire the halt.

AST, NOT GREP, for every claim about the reference; BY NAME, NOT BY LINE, for
every claim about the port.
"""
from __future__ import annotations

import ast
import pathlib
import re

REPO = pathlib.Path(__file__).resolve().parents[2]
DRIVER = REPO / "scripts" / "rfc_to_implementation.py"
COVER = REPO / "scripts" / "driver_ll_cover.py"
DRIVER_LL = REPO / "tools" / "llmll-driver"
SEQUENCER = DRIVER_LL / "sequencer.llmll"
REGISTRY = DRIVER_LL / "registry.llmll"
REPORT = DRIVER_LL / "report.llmll"
SPEC = REPO / "experiments" / "rfc-swarm" / "targets" / "driver-spec.txt"

SRC = DRIVER.read_text()
TREE = ast.parse(SRC, filename=str(DRIVER))


def _uncommented(path: pathlib.Path) -> str:
    return "\n".join(line.split(";;")[0] for line in
                     path.read_text().splitlines())


SEQ = _uncommented(SEQUENCER)
REG = _uncommented(REGISTRY)


def _fn(name: str) -> ast.FunctionDef:
    for node in TREE.body:
        if isinstance(node, ast.FunctionDef) and node.name == name:
            return node
    raise AssertionError(f"{name} is not a top-level function of {DRIVER.name}")


def _defs(src: str) -> dict[str, str]:
    heads = list(re.finditer(r"^\s*\((?:def-shell|def-main|def|type)\s+([\w?!-]+)",
                             src, re.M))
    out: dict[str, str] = {}
    for h, nxt in zip(heads, heads[1:] + [None]):
        out[h.group(1)] = src[h.start():nxt.start() if nxt else len(src)]
    return out


SEQ_DEFS = _defs(SEQ)
REG_DEFS = _defs(REG)


def _referrers(name: str) -> set[str]:
    pat = re.compile(r"[\s(]" + re.escape(name) + r"[\s)]")
    return {d for d, body in SEQ_DEFS.items() if d != name and pat.search(body)}


STAGE_O = _fn("stage_O_writeup")


def test_stage_O_holds_no_require_site_in_the_reference():
    """The premise of the whole sub-phase, and it is measured rather than
    quoted. driver-spec sec 7:283-286 makes validating a delegated output
    mandatory, non-downgradable and non-skippable. For this one stage there is
    nothing to downgrade because nothing exists, which is why 4f WRITES a
    validator instead of porting one."""
    calls = {n.func.id for n in ast.walk(STAGE_O)
             if isinstance(n, ast.Call) and isinstance(n.func, ast.Name)}
    assert not calls & {"require", "require_spec", "require_written"}, (
        f"stage_O_writeup calls {sorted(calls & {'require', 'require_spec', 'require_written'})}; "
        "the sub-phase's premise is that it holds none")


def test_the_agent_file_and_the_declared_output_are_different_files():
    """The inverted artifact flow, third instance. H and N hand the driver a
    catalogue and the DRIVER writes the declared output; stage O's agent writes
    14-report/REPORT.md and the driver COPIES it to the workdir root, which is
    the declared output. A port that took the agent's directory from
    stage-out-dir would run the agent in the workdir root."""
    runs = [n for n in ast.walk(STAGE_O)
            if isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute)
            and n.func.attr == "run"]
    assert len(runs) == 1, "stage O delegates exactly once"
    out_names = [a.value for a in runs[0].args
                 if isinstance(a, ast.Constant) and isinstance(a.value, str)]
    assert "REPORT.md" in out_names, f"the agent writes REPORT.md, got {out_names}"
    dirs = [n.args[0].value for n in ast.walk(STAGE_O)
            if isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute)
            and n.func.attr == "d" and n.args
            and isinstance(n.args[0], ast.Constant)]
    assert "14-report" in dirs, f"the agent works in 14-report, got {dirs}"
    copies = [n for n in ast.walk(STAGE_O)
              if isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute)
              and n.func.attr == "copy2"]
    assert len(copies) == 1, "the declared output is written by a copy"

    assert '"14-report/REPORT.md"' in REG_DEFS["stage-agent-out"], (
        "registry.stage-agent-out must name the agent's file for stage O; "
        "without the row it falls through to stage-out and reads the copy")
    assert '"14-report"' in REG_DEFS["stage-agent-dir"], (
        "registry.stage-agent-dir must name the agent's directory for stage O")
    assert '"REPORT.md"' in REG_DEFS["stage-out"], (
        "the declared output is the workdir-root copy")


def test_the_five_prompt_inputs_are_the_reference_keywords_in_order():
    """Every prompt input is a row in two registry tables, and the two must
    agree with the reference's keyword order: the Pre loop reads path j and
    substitutes key j."""
    prompts = [n for n in ast.walk(STAGE_O)
               if isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute)
               and n.func.attr == "prompt"]
    assert len(prompts) == 1
    keywords = [k.arg for k in prompts[0].keywords if k.arg is not None]
    assert keywords == ["gate", "coverage", "kill_matrix", "wave", "reconcile"], (
        f"the reference's keyword order is what the port's j indices mean, got {keywords}")

    paths = REG_DEFS["stage-pre-path"]
    for j, rel in enumerate(["09-gate/gate.json", "11-freeze/rfc-cov-1.txt",
                             "13-kill-matrix/kill-matrix.json", "12-wave/wave.json",
                             "04-reconcile/SUMMARY.json"]):
        assert f'"{rel}"' in paths, f"stage O input {j} reads {rel}"
    keys = REG_DEFS["stage-pre-key"]
    for kw in keywords:
        assert "{{" + kw + "}}" in keys, f"the port substitutes {{{{{kw}}}}}"
    assert "(= i 15) 5" in REG_DEFS["stage-pre-count"].replace("  ", " "), (
        "stage O declares five precondition inputs")


def test_every_stage_O_input_is_optional_in_the_reference():
    """`maybe()` is why mode 4 exists. Every other precondition read in the
    reference is unguarded and tracebacks on an absent file, which is why every
    other mode halts. Stage O's are guarded there, so halting would be the port
    inventing a halt where the subject has none."""
    maybes = [n for n in ast.walk(STAGE_O)
              if isinstance(n, ast.Call) and isinstance(n.func, ast.Name)
              and n.func.id == "maybe"]
    assert len(maybes) == 5, (
        f"all five inputs reach the prompt through maybe(), found {len(maybes)}")
    fallbacks = {n.value for n in ast.walk(STAGE_O)
                 if isinstance(n, ast.Constant) and isinstance(n.value, str)}
    assert "(stage not run)" in fallbacks, (
        "the reference's substitute for an absent input")
    assert '"(stage not run)"' in SEQ_DEFS["not-run"], (
        "the port must substitute the reference's own string, byte for byte")


def test_mode_four_is_optional_and_stage_O_is_its_only_user():
    """A mode that skipped the halt for any other stage would turn an absent
    precondition into a prompt carrying the words `(stage not run)`, which is
    exactly the silent-degradation direction driver-spec sec 7:279 is about."""
    assert "(= (stage-pre-mode i j) 4)" in SEQ_DEFS["optional-pre?"], (
        "mode 4 is the optional mode")
    modes = REG_DEFS["stage-pre-mode"]
    fours = re.findall(r"\(if \(= i (\d+)\)\s+4", modes.replace("\n", " "))
    assert fours == ["15"], f"mode 4 is stage O's alone, found stages {fours}"
    assert _referrers("optional-pre?") == {"pre-absent", "pre-step"}, (
        "the optional test must gate both the absent arms and the projection")


def test_driver_spec_section_13_carries_eight_musts():
    """Proposal section 6.2 splits them one to seven, and the phase close lists
    the seven as unchecked. The count is taken from the specification text, not
    from the proposal's five line ranges, because a range can carry two."""
    text = SPEC.read_text()
    # The table of contents carries both headings too, indented; the section
    # itself starts at column zero. Slice on the BODY headings, not the first
    # match, or the slice is the one empty line between two TOC entries.
    start = text.index("\n13. Reporting")
    end = text.index("\n14. Integrity Considerations")
    section = text[start:end]
    musts = re.findall(r"MUST NOT|MUST", section)
    assert len(musts) == 8, f"driver-spec sec 13 carries eight MUSTs, found {len(musts)}"
    assert musts.count("MUST NOT") == 3, f"three of them are prohibitions: {musts}"
    flat = " ".join(section.split())
    assert "including perturbations that were not detected" in flat, (
        "the mechanizable clause is the one that names undetected perturbations")
    assert "MUST be resolved rather than omitted" in flat, (
        "and the sentence beside it is disclosure-only: naming a survivor is "
        "not resolving it, so passing the set difference discharges nothing here")


def test_the_proved_decision_is_forwarded_exactly_once():
    """The 4d and 4e pattern: each proved def is reached through one shell
    wrapper, so the call is visible to a reader and to the callerless census
    rather than buried in an arm."""
    assert _referrers("omission-free?") == {"omission-ok?"}
    assert _referrers("omission-ok?") == {"o-decide"}
    for post in ("[O13-FULL]", "[O13-UNDETECTED]", "[O13-NO-OMIT]", "[O13-DOM]"):
        assert post in REPORT.read_text(), f"{post} is a clause of the proved core"


def test_the_port_now_constructs_partial_then_halt_at_two_stage_sites():
    """4d landed the first (stage H's probe-polarity bar) and 4f lands the
    second. The sequencer's own retirement schedule said 4f would retire the
    constructor from the injector; it had already been retired at 4d, and the
    comment is corrected rather than left to mislead the next reader."""
    injector = {"injected-outcome", "halt-clause", "stamped-step", "halts-post?"}
    users = {d for d, body in SEQ_DEFS.items()
             if re.search(r"[\s(]PartialThenHalt[\s)]", body)}
    assert users - injector == {"hwrote-step", "o-decide"}, (
        f"the stage sites are {sorted(users - injector)}")
    assert '"driver-spec sec 13"' in SEQ_DEFS["o-decide"], (
        "a stopped row names the clause that authorised it")


def test_the_omission_check_is_decided_after_the_declared_write():
    """Write-before-halt is a construction discipline no proof can see. The
    check is decided only in the arm that RECEIVES the copy's response, and
    that arm is entered only by the arm that ISSUES the copy. Get this backward
    and the same failure records `failed` over an artifact that exists."""
    dispatch = {"drv-step", "drv-done?", "done-code", "drv-status"}
    enters = {d for d, body in SEQ_DEFS.items() if "(OWrote " in body} - dispatch
    assert enters == {"o-enter"}, f"OWrote is entered from {sorted(enters)}"
    assert "o-copy-cmd" in SEQ_DEFS["o-enter"], (
        "o-enter must issue the copy on the way into OWrote")
    assert "wasi.fs.copy" in SEQ_DEFS["o-copy-cmd"]
    assert _referrers("o-decide") == {"owrote-step"}, (
        "the decision happens in the arm that received the copy's response")


def test_the_survivor_predicate_is_shared_with_stage_N():
    """One definition decides stage N's SURVIVORS line and stage O's survivor
    count, so the two cannot disagree about what survived. A second copy here
    would type-check, pass every cover cell, and drift on the first change to
    stage N's verdict vocabulary."""
    assert "survivor?" in SEQ_DEFS, "survivor? is defined once in the sequencer"
    assert _referrers("survivor?") == {"survivors-line", "o-survivor-count",
                                       "o-survivors-unnamed"}


def test_the_cover_holds_a_cell_that_can_fire_the_halt():
    """The acceptance clause rests on O2. O1, O3 and O4 are each satisfiable by
    a validator that always returns true, and a cover of those three alone
    would be the fourth time this phase lost a clause to vacuity."""
    cover = COVER.read_text()
    assert 'want_stopped_partial(r, "O", "driver-spec sec 13")' in cover, (
        "O2 must assert the stopped row, its constructor and its clause")
    assert 'mode="report-omits-survivor"' in cover, (
        "the firing cell drives the stub into omitting a survivor")
    for cell in ("O1", "O2", "O3", "O4"):
        assert f'@local4f("{cell}"' in cover, f"cover cell {cell} is declared"
