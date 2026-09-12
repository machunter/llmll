"""Program unification job (a2): the checks that do not need a built driver.

Stage M is the one stage whose delegation count is settled at run time, and job
(a2) folded it into the sequencer's stage loop as a single `Ctl` arm carrying
the wave's own machine. `scripts/wave_cover.py` grades what the folded stage
DOES, against the real compiler, through the `wave` sub-command. This file
grades the things a passing cover cannot see.

Five of them:

  * THE FOUR MATCHES OVER `Ctl` AGREE. The compiler enforces that each is
    exhaustive. It does not enforce that they name the same arms, so an arm
    added to `drv-step` and forgotten in `drv-done?` type-checks and hangs the
    run. `test_driver_ll_4e.py` makes the same check for the wave's own three;

  * A `Fan` STATE IS NEVER TERMINAL. `fan-step` reads `wave-exit-code` and
    leaves through `Ending` rather than re-wrapping, for both values of `k`. If
    that interception is lost, a folded stage M ends the whole campaign with the
    wave's exit code and stage N never runs;

  * `:status` STAYS STRICT-CORE. `drv-status` is a proved `def`, so its arms may
    not call a `def-shell`. An earlier version of the `Fan` arm called
    `wave-status` and `llmll check` rejected it. The arm is a literal and must
    stay one;

  * THE `wave` SUB-COMMAND IS DISPATCHED BEFORE `parse-cfg`. Cover cells W5 and
    W6 assert the WAVE's usage text at exit 2, and `boot-step`'s own
    missing-flag stop also exits 2 with different text. A dispatch after the
    parse gives the right code with the wrong message, which `want_rc` alone
    does not catch;

  * THE REGISTRY DECIDES WHICH STAGE FANS OUT. `started-step` reads
    `stage-fanout` rather than testing an index, and the table is non-zero for
    exactly the stage the wave handles.

AGAINST THE SOURCE TEXT, on the reasoning `test_driver_ll_4c.py` gives: this
tier runs on a machine with no toolchain.
"""

from __future__ import annotations

import pathlib
import re

REPO = pathlib.Path(__file__).resolve().parents[2]
DRIVER_LL = REPO / "tools" / "llmll-driver"
SEQUENCER = DRIVER_LL / "sequencer.llmll"
REGISTRY = DRIVER_LL / "registry.llmll"
WAVE = DRIVER_LL / "wave.llmll"

_IDENT_TAIL = r"(?![\w?!-])"


def _uncommented(path: pathlib.Path) -> str:
    """Source with `;` comment tails removed, string literals respected.

    These modules are more comment than code and the comments quote the very
    names asserted below, so a raw-text search finds the prose and concludes the
    code is there.
    """
    out = []
    for line in path.read_text().splitlines():
        in_str = False
        for i, ch in enumerate(line):
            if ch == '"' and (i == 0 or line[i - 1] != "\\"):
                in_str = not in_str
            elif ch == ";" and not in_str:
                line = line[:i]
                break
        out.append(line)
    return "\n".join(out)


def _body_of(src: str, name: str) -> str:
    """One def's text, from its opening paren to the next top-level def."""
    m = re.search(r"\(def(?:-shell)?\s+" + re.escape(name) + _IDENT_TAIL, src)
    assert m, f"{name} is not defined"
    rest = src[m.end():]
    nxt = re.search(r"\n  \(def(?:-shell)?\s", rest)
    return rest[:nxt.start()] if nxt else rest


def _ctl_arms() -> set[str]:
    src = _uncommented(SEQUENCER)
    m = re.search(r"\(type Ctl\b(.*?)\n\n", src, re.S)
    assert m, "the Ctl type is not where this file expects it"
    return set(re.findall(r"\(\|\s*(\w+)", m.group(1)))


# ---------------------------------------------------------------------------
# 1. The four matches agree
# ---------------------------------------------------------------------------

CTL_MATCHES = ("drv-step", "drv-done?", "done-code", "drv-status")


def test_every_match_over_ctl_names_every_arm():
    """FOUR matches, not three. The wave has three and `test_driver_ll_4e.py`
    checks those; the sequencer has four because `done-code` and `drv-status`
    are separate, one feeding the end-of-run line and one feeding the exit."""
    src = _uncommented(SEQUENCER)
    arms = _ctl_arms()
    assert {"Fan", "FanBoot"} <= arms, f"the stage M arms are gone: {sorted(arms)}"
    for fn in CTL_MATCHES:
        named = set(re.findall(r"\(\((\w+)[ )]", _body_of(src, fn)))
        assert named == arms, (
            f"{fn} does not match Ctl: missing {sorted(arms - named)}, "
            f"extra {sorted(named - arms)}")


# ---------------------------------------------------------------------------
# 2. A Fan state is never terminal
# ---------------------------------------------------------------------------

def test_the_fan_arm_leaves_through_ending_and_not_by_re_wrapping():
    """The interception is the whole invariant.

    `fan-step` asks `wave-exit-code` whether the wave has reached an ending. A
    negative answer means keep going and re-wrap; anything else must leave the
    `Fan` arm. Both exits are named here: the standalone sub-command goes to
    `Ending`, and a folded stage goes to `fan-exit`, which halts or joins the
    post-stage path.
    """
    body = _body_of(_uncommented(SEQUENCER), "fan-step")
    assert "wave-exit-code" in body, \
        "fan-step no longer asks whether the wave has ended"
    assert "(Ending code)" in body, \
        "the standalone wave run no longer leaves through Ending"
    assert "fan-exit" in body, "a folded stage M no longer rejoins the stage loop"


def test_no_fan_state_is_reported_as_done():
    """`drv-done?` must answer false for both stage M arms.

    True for `Fan` would end the campaign in the middle of stage M with the
    wave's own exit code, and stage N would never run. That is reachable only
    if `fan-step` stops intercepting, so this and the cell above are the two
    halves of one property.
    """
    body = _body_of(_uncommented(SEQUENCER), "drv-done?")
    for arm in ("Fan", "FanBoot"):
        m = re.search(r"\(\(" + arm + r"\s+\w+\)\s*(\w+)\)", body)
        assert m, f"drv-done? has no {arm} arm"
        assert m.group(1) == "false", \
            f"drv-done? reports {arm} as terminal, which ends the run inside stage M"


# ---------------------------------------------------------------------------
# 3. :status stays strict-core
# ---------------------------------------------------------------------------

def test_the_status_arms_for_stage_m_are_literals():
    """MEASURED, not predicted: `llmll check` rejected an earlier `Fan` arm with

        def 'drv-status': callee 'wave-status' is not body-faithful and not in
        the trusted prelude

    `drv-status` is a `def`, so strict-core admissibility applies to its arms
    and every helper in reach is a `def-shell`. The arms are literals because a
    `Fan` state is never terminal, and they must stay literals whatever else
    changes.
    """
    body = _body_of(_uncommented(SEQUENCER), "drv-status")
    for arm in ("Fan", "FanBoot"):
        m = re.search(r"\(\(" + arm + r"\s+\w+\)\s*([^)]*)\)", body)
        assert m, f"drv-status has no {arm} arm"
        assert re.fullmatch(r"\s*\d+\s*", m.group(1)), (
            f"drv-status's {arm} arm is {m.group(1)!r} and not an integer literal; "
            "a call here is rejected at `llmll check`")


# ---------------------------------------------------------------------------
# 4. The sub-command is dispatched before the parse
# ---------------------------------------------------------------------------

def test_the_wave_subcommand_is_dispatched_before_parse_cfg():
    """Cells W5 and W6 assert the WAVE's usage text at exit 2. `boot-step` stops
    at exit 2 as well, with its own text, when a sequencer flag is missing. Both
    give exit 2, so the order is what decides which message an operator sees."""
    body = _body_of(_uncommented(SEQUENCER), "boot-step")
    sub = body.find('"wave"')
    parse = body.find("parse-cfg")
    assert sub != -1, "boot-step no longer dispatches the wave sub-command"
    assert parse != -1, "boot-step no longer parses the driver's own flags"
    assert sub < parse, \
        "parse-cfg runs before the wave dispatch, so a wave run gets the driver's usage text"


def test_the_subcommand_token_matches_the_cover():
    """One token, named in two files. The cover prepends it and `boot-step`
    tests for it; a rename in one place makes seven cells drive the stage loop
    with the wave's flags."""
    cover = (REPO / "scripts" / "wave_cover.py").read_text()
    m = re.search(r"^SUBCOMMAND = \[(.*)\]", cover, re.M)
    assert m, "wave_cover.py declares no SUBCOMMAND"
    assert m.group(1).strip() == '"wave"', \
        f"the cover's sub-command is {m.group(1)} and boot-step tests for \"wave\""


# ---------------------------------------------------------------------------
# 5. The registry decides which stage fans out
# ---------------------------------------------------------------------------

def test_started_step_routes_on_the_registry_and_not_on_an_index():
    """`registry.llmll`'s header states the rule: a table written as syntax is a
    constant a reader enumerates from the source. A bare index test in the stage
    loop puts the fact where no reader of the registry finds it."""
    body = _body_of(_uncommented(SEQUENCER), "started-step")
    assert "stage-fanout" in body, "started-step no longer reads stage-fanout"
    assert not re.search(r"\(=\s*\(idx-at[^)]*\)\s*\d+\)", body), \
        "started-step tests a bare stage index instead of the registry"


def test_the_fanout_branch_precedes_the_kind_branch():
    """Stage M's kind is `agent`, so a `stage-kind` test reached first would
    send it to `begin-body`, which renders a prompt template stage M does not
    have and delegates once."""
    body = _body_of(_uncommented(SEQUENCER), "started-step")
    assert body.find("stage-fanout") < body.find("stage-kind"), \
        "started-step tests stage-kind before stage-fanout"


def test_stage_fanout_is_non_zero_for_exactly_stage_m():
    """The table and the fold must name the same stage. A second non-zero row
    would send a stage into the wave's machine with no arm to receive it."""
    body = _body_of(_uncommented(REGISTRY), "stage-fanout")
    nonzero = re.findall(r"\(=\s*i\s*(\d+)\)\s*(\d+)", body)
    assert [(i, v) for i, v in nonzero if v != "0"] == [("13", "1")], \
        f"stage-fanout's non-zero rows are {nonzero}, not stage M alone"


def test_stage_m_declares_two_outputs_and_the_fold_uses_both():
    """The correction the (a2) design rests on: stage M's DECLARED artifact
    count is static at two, and only its delegation count is run-time. The fold
    reads the AST at index 1 and the wave writes the record at index 0."""
    reg = _uncommented(REGISTRY)
    outs = _body_of(reg, "stage-out")
    assert "12-wave/wave.json" in outs and "12-wave/roots.ast.json" in outs, \
        "stage M no longer declares the two artifacts the fold and the comparator read"
    cnt = _body_of(reg, "stage-out-count")
    assert re.search(r"\(=\s*i\s*13\)\s*2", cnt), \
        "stage-out-count no longer says stage M declares two"
    assert "art-path c i 1" in _body_of(_uncommented(SEQUENCER), "fan-cfg"), \
        "fan-cfg no longer hands the wave declared output 1, the AST tree"


# ---------------------------------------------------------------------------
# 6. The exit seam: which wave codes halt the stage
# ---------------------------------------------------------------------------

def test_the_four_halting_wave_codes_are_the_ones_that_halt():
    """THE CLAUSE A PLAUSIBLE PORT GETS WRONG, and nothing else grades it.

    `stage_M_wave` holds two `require` calls and neither fires on a finding, on
    a protocol fault, or on an unsealed tree: it logs all three and returns. So
    four of the wave's exit codes record the stage COMPLETE, and a port that
    read any non-zero code as a failure would halt where the reference continues.
    Stage N would then never run and the campaign would lose the kill matrix for
    a reason that is not a defect in the fill wave.

    NO COVER CELL REACHES THIS. `driver_ll_cover.py` M1 drives the failing path,
    because that is the only wave code its stub compiler can produce; W2 and W9
    grade a finding at the wave level, one layer below the stage outcome. A
    findings run continuing into stage N is asserted here and nowhere else.

    CODES 6 AND 7 JOINED AT THE STAGE M AGENT CONTRACT, and the set they joined
    is what this test is about. The prompt template is a declared input
    (driver-spec section 8 part 3), so an absent or empty one is a halt and so
    is a rendered prompt that kept a placeholder. This test expected [2, 4] and
    now expects [2, 4, 6, 7]. The SET is still the assertion, because the way
    this breaks is a code joining the halt chain, not an arm changing shape, and
    a completing code joining it is the failure that costs a campaign its kill
    matrix.
    """
    body = _body_of(_uncommented(SEQUENCER), "fan-join")
    halting = sorted(int(c) for c in re.findall(r"\(=\s*code\s*(\d+)\)", body))
    assert halting == [2, 4, 6, 7], (
        f"fan-join halts on wave codes {halting}, not [2, 4, 6, 7]. Codes 0, 1, "
        "3 and 5 must fall through to to-summed: they are a clean run, a "
        "finding, a protocol failure and an unsealed tree, and the reference "
        "records the stage complete for all four.")
    assert "to-summed" in body, \
        "fan-join no longer rejoins the post-stage path on a completing code"


def test_the_token_halt_is_stopped_and_the_empty_tree_is_failed():
    """The two halting codes take DIFFERENT dispositions and the difference is
    driver-spec's, not a preference.

    Code 4 is the token discipline, which `token.llmll` cites to driver-spec
    section 10:371 as [S10-NOTHELD]. A halt on a condition the SPECIFICATION
    defines is `stopped` per section 4:125-127. Code 2 is a `require` in the
    reference, so it is `failed`. Recording code 4 as failed would report a gate
    that fired as an accident, which section 4:135-137 names as the dangerous
    direction.
    """
    body = _body_of(_uncommented(SEQUENCER), "fan-join")
    four = body[body.find("(= code 4)"):body.find("(= code 2)")]
    assert "ConditionUnmet" in four, \
        "the token halt is no longer a spec-defined stop"
    assert "halt-errored" not in four, \
        "the token halt records failed; driver-spec sec 4:135-137 names that direction"
    two = body[body.find("(= code 2)"):body.find("(= code 6)")]
    assert "halt-errored" in two, "the empty-tree halt no longer records failed"

    # THE TWO PROMPT HALTS TAKE `tmpl-step`'s DISPOSITIONS AND NOT NEW ONES.
    # Every other delegated stage reaches its template through `tmpl-step`,
    # which records `Absent` for a template it cannot read and `Malformed` for
    # one whose placeholders survived. Stage M reaches its template through the
    # wave, and a different vocabulary for the same two conditions would make a
    # manifest row's disposition depend on which stage produced it.
    six = body[body.find("(= code 6)"):body.find("(= code 7)")]
    assert "Absent" in six, \
        "an unreadable stage M template no longer records Absent"
    seven = body[body.find("(= code 7)"):]
    assert "Malformed" in seven, \
        "a stage M prompt with unfilled placeholders no longer records Malformed"


# ---------------------------------------------------------------------------
# 6. The emit guard
# ---------------------------------------------------------------------------

def test_the_ast_emit_is_guarded_by_the_trees_presence():
    """`stage_M_wave` emits only when the tree is absent or `--force` is set.

    Re-emitting resets every hole a partial run had already filled. A stage M
    that halted part way leaves no manifest row, so `may-skip` runs it again and
    the hole list is re-derived from the tree: a filled hole is no longer a
    hole. That is what makes resume at hole granularity free, and an unguarded
    emit destroys it with no gate to say so.
    """
    body = _body_of(_uncommented(SEQUENCER), "fanboot-step")
    assert "cfg-forced" in body, "the emit no longer honours --force"
    assert "hex-of r" in body, "the emit no longer probes for an existing tree"
    assert "emit-tree-cmd" in body, "fanboot-step no longer emits the AST"
