"""DRIVER-LL stage M: the agent contract, in the checks that need no binary.

`scripts/wave_cover.py` cells W10, W11 and W12 grade what the contract DOES,
against the real compiler and a built driver. This file grades the things a run
cannot see, on the precedent `test_driver_ll_4e.py` sets: these run on a machine
with no toolchain, and each is a place the port can go wrong with all twelve
cells still passing.

WHAT SUB-PHASE 4e BUILT, and why nothing caught it. 4e settled that the checkout
brief is the agent's only input and called that the sole-channel discipline.
driver-spec section 8 does not say that. Its third paragraph requires the driver
to report any file in an agent's directory that was not among ITS DECLARED
INPUTS, which makes a declared input a driver-side commitment rather than a
spec-side enumeration, so a rendered task statement is one. The Phase 4
proposal's own section 5 item 1 refuted 4e first and more tightly: it settled
`--agent-exe` plus repeatable `--agent-arg` with the placeholders SUBSTITUTED
PER ARGUMENT, and 4e built a stage that substitutes nothing and appends two
paths instead. Three gates missed it. No cover cell passed `--agent-arg`;
`driver_ll_cover.py` stopped selecting stage M at the (a2) fold; and the
2026-09-11 clause 2 run never reached stage M because stage M was stubbed.

FIVE THINGS ARE SETTLEABLE STATICALLY:

  * THE PLACEHOLDER SET IS THE TEMPLATE'S, NOT A REMEMBERED LIST. A template
    edited to add `{{scope}}` would otherwise reach an agent carrying the
    literal string, and only a run would notice;

  * THE THREE STRING SLOTS ON `Att` PROJECT THREE DISTINCT POSITIONS. `token`,
    `body` and `errors` are all `string`, so a swapped accessor typechecks and
    passes every type-level gate;

  * THE ERROR CHANNEL IS CARRIED AND NOT CLEARED. `at-next` cleared the token
    and the body and carried only the budgets, so attempt n+1 received
    byte-identical input to attempt n. That makes driver-spec section 9's error
    budget a sampling loop where the reference's is a repair loop;

  * THE PRISTINE COPY COMES FROM THE STAGE'S INPUT AND NEVER FROM THE TREE.
    Section 8 part 4 says the self-check copy MUST be the original, unmodified
    subject, and the tree is what the wave patches in place;

  * THE SUBSTITUTION IS ONE FUNCTION WITH TWO CALLERS. A second copy is how the
    two conventions parted in the first place.

AGAINST THE SOURCE TEXT, not against a built artifact.
"""

from __future__ import annotations

import pathlib
import re

REPO = pathlib.Path(__file__).resolve().parents[2]
DRIVER_LL = REPO / "tools" / "llmll-driver"
WAVE = DRIVER_LL / "wave.llmll"
SEQUENCER = DRIVER_LL / "sequencer.llmll"
REGISTRY = DRIVER_LL / "registry.llmll"
COMMON = DRIVER_LL / "common.llmll"
TEMPLATE = REPO / "experiments" / "rfc-swarm" / "prompts" / "stage-M-fill.md"

_IDENT_TAIL = r"(?![A-Za-z0-9_?!*+/<>=-])"


def _uncommented(path: pathlib.Path) -> str:
    """Source with `;;` comments removed.

    Crude on purpose, and it is the same helper `test_driver_ll_4e.py` uses:
    this repository's driver modules are more comment than code, and every
    assertion below is about which names appear in which body.
    """
    out = []
    for line in path.read_text(encoding="utf-8").splitlines():
        i = line.find(";;")
        out.append(line if i < 0 else line[:i])
    return "\n".join(out)


def _body_of(src: str, name: str) -> str:
    m = re.search(r"\(def(?:-shell)?\s+" + re.escape(name) + _IDENT_TAIL, src)
    assert m, f"{name} is not defined"
    rest = src[m.end():]
    nxt = re.search(r"\n  \(def(?:-shell)?\s", rest)
    return rest[:nxt.start()] if nxt else rest


def _top_body_of(src: str, name: str) -> str:
    """`_body_of` for a module whose defs sit at column 0, like the registry."""
    m = re.search(r"\(def(?:-shell)?\s+" + re.escape(name) + _IDENT_TAIL, src)
    assert m, f"{name} is not defined"
    rest = src[m.end():]
    nxt = re.search(r"\n\(def(?:-shell)?\s", rest)
    return rest[:nxt.start()] if nxt else rest


# ---------------------------------------------------------------------------
# 1. The argument vector
# ---------------------------------------------------------------------------

def test_the_agent_vector_is_substituted_and_nothing_is_appended():
    """THE DEFECT ITSELF, asserted where it lived.

    `rel-step` is the one arm that spawns the agent. It mapped nothing and
    appended `brief.json` and `body.json` to the operator's arguments, so one
    `--agent-arg` list served two incompatible calling conventions: every other
    delegated stage substitutes, and stage M appended. Measured with the
    campaign's real vector, the agent received the literal strings `{prompt}`
    and `{out}`, and the committed wrapper exited 2 on the unreadable literal
    before any model ran.
    """
    body = _body_of(_uncommented(WAVE), "rel-step")
    assert "subst-arg" in body, \
        "rel-step no longer substitutes the agent's argument vector"
    assert "list-append" not in body, (
        "rel-step appends to the agent's argument vector again. The operator "
        "says where the prompt and the output go; an append is what made one "
        "list serve two conventions.")


def test_the_agent_works_in_its_own_directory():
    """The template tells the agent to run `verify scratch.llmll` and to write
    `body.json` in its working directory. Both instructions need that directory
    to be the one the files are in. `delegate-cmd` in sequencer.llmll and
    `AgentRunner.run` in the reference both pass the agent's directory; this arm
    passed `"."` until the stage M agent contract."""
    body = _body_of(_uncommented(WAVE), "rel-step")
    m = re.search(r"wasi\.proc\.run.*?\n(.*?)\n\s*\(wasi\.fs\.read", body, re.S)
    assert m, "rel-step no longer spawns the agent and then reads its output"
    assert "att-dir" in m.group(1), (
        "the agent's working directory is not its own attempt directory, so "
        "the template's `verify scratch.llmll` names a file it cannot reach")


def test_the_substitution_is_one_function_with_two_callers():
    """`subst-arg` lived in `sequencer.llmll` and the wave could not reach it,
    because the sequencer imports the wave and not the reverse. A second copy is
    how the two conventions parted, so it moved to `common.llmll` rather than
    being duplicated."""
    common = _uncommented(COMMON)
    assert re.search(r"\(def-shell\s+subst-arg" + _IDENT_TAIL, common), \
        "subst-arg is not in common.llmll"
    assert re.search(r"\(def-shell\s+replace-all" + _IDENT_TAIL, common), \
        "replace-all is not in common.llmll"
    for path in (WAVE, SEQUENCER):
        src = _uncommented(path)
        for name in ("subst-arg", "replace-all"):
            assert not re.search(r"\(def-shell\s+" + name + _IDENT_TAIL, src), (
                f"{path.name} holds a second copy of {name}; the two callers "
                "are supposed to share one")


# ---------------------------------------------------------------------------
# 2. The rendered task statement
# ---------------------------------------------------------------------------

def test_the_wave_substitutes_every_placeholder_the_template_carries():
    """COMPUTED FROM THE TEMPLATE FILE AND NOT REMEMBERED, which is the whole
    point of the check.

    driver-spec section 7:288-291 warns that a validator hardcoding the values
    seen in one run reports emptiness on the next, and a renderer written
    against a remembered placeholder list is that shape. A template edited to
    add `{{scope}}` would reach an agent carrying the literal string, and the
    only thing that would notice is a run.

    The wave halts on a leftover `{{`, so this test and `has-unfilled?` are two
    halves of one guard: this one says the port fills what the template asks
    for, and the guard says the port never hands over a prompt it could not
    fill.
    """
    wanted = set(re.findall(r"\{\{(\w+)\}\}", TEMPLATE.read_text(encoding="utf-8")))
    assert wanted, "the stage M template carries no placeholders at all"
    body = _body_of(_uncommented(WAVE), "render-prompt")
    filled = set(re.findall(r'"\{\{(\w+)\}\}"', body))
    assert filled == wanted, (
        f"the template asks for {sorted(wanted)} and render-prompt fills "
        f"{sorted(filled)}. A placeholder the port does not fill reaches the "
        "agent as a literal string, or halts the stage at code 7.")


def test_the_first_attempt_renders_the_references_literal():
    """`errors or "(first attempt)"`. A port rendering an empty string leaves
    the prompt's heading with nothing under it, which reads to an agent as an
    attempt that produced no output rather than as one that has not happened."""
    body = _body_of(_uncommented(WAVE), "errors-or-first")
    assert "(first attempt)" in body, \
        "the first-attempt literal is not the reference's"


def test_the_render_happens_in_the_wave_and_not_in_the_stage_loop():
    """THE DESIGN DECISION, and the registry row is where it is observable.

    Every placeholder in `stage-pre-key` names an artifact read ONCE per stage
    before delegating, which is why `render` in sequencer.llmll can run in the
    stage loop. Three of stage M's four are settled per attempt inside the hole
    loop: the hole name, the checkout brief re-taken each attempt, and the
    previous attempt's compiler output. So `stage-pre-count` for M is zero and
    stays zero, and a non-zero row would claim the stage reads something before
    delegating that it does not.
    """
    counts = dict(re.findall(r"\(= i (\d+)\)\s+(\d+)",
                             _top_body_of(_uncommented(REGISTRY), "stage-pre-count")))
    assert counts.get("13") in (None, "0"), (
        f"stage-pre-count row 13 is {counts.get('13')}; stage M reads no "
        "artifact before delegating, because its prompt's values are per-attempt")
    assert "render-prompt" in _body_of(_uncommented(WAVE), "brief-step"), \
        "the wave no longer renders the prompt at the arm that holds the brief"


def test_the_registry_names_the_template_and_the_template_exists():
    """`stage-prompt` row 13 was empty because 4e rendered no prompt at all. It
    names the basename now, as every other delegated stage's row does, and
    `fan-cfg` resolves it under --prompts-dir."""
    row = _top_body_of(_uncommented(REGISTRY), "stage-prompt")
    m = re.search(r'\(= i 13\)\s+"([^"]+)"', row)
    assert m, "stage-prompt has no row 13"
    assert m.group(1) == TEMPLATE.name, \
        f"row 13 names {m.group(1)!r} and the template is {TEMPLATE.name!r}"
    assert TEMPLATE.exists(), f"{TEMPLATE} does not exist"
    assert "tmpl-file" in _body_of(_uncommented(SEQUENCER), "fan-cfg"), \
        "fan-cfg no longer resolves the template through the registry row"


# ---------------------------------------------------------------------------
# 3. The error channel
# ---------------------------------------------------------------------------

def test_the_three_string_slots_project_three_distinct_positions():
    """THE MUTATION CONTROL FOR THE WIDENING, and it is the one thing the type
    checker cannot do here.

    `token`, `body` and `errors` are all `string`. A swapped accessor
    typechecks, passes `llmll check`, builds, and puts the previous attempt's
    compiler transcript into the JSON-Patch while the agent's body node goes
    into the next prompt. Every projection in wave.llmll is written once in an
    accessor for this reason; this test is what makes "written once" mean
    "written correctly".
    """
    src = _uncommented(WAVE)
    projections = {}
    for name in ("at-token", "at-body", "at-errors"):
        body = _body_of(src, name)
        m = re.search(r"\(\(Att q\)\s*(.+?)\)\)", body, re.S)
        assert m, f"{name} does not project out of an Att"
        projections[name] = " ".join(m.group(1).split())
    assert len(set(projections.values())) == 3, (
        f"two Att accessors project the same position: {projections}. All three "
        "slots are `string`, so the type checker cannot see this.")


def test_at_next_carries_the_error_text_and_does_not_clear_it():
    """`at-next` cleared the token and the body and carried only the budgets, so
    attempt n+1 received byte-identical input to attempt n. driver-spec section
    9 requires two separately counted budgets and makes only an exhausted error
    budget a finding; with identical input the error budget samples agent
    nondeterminism rather than measuring repair. `fill.next-error-budget` was
    always correct and is untouched. What changed is the input the running
    program supplies."""
    src = _uncommented(WAVE)
    sig = re.search(r"\(def-shell\s+at-next\s*\[([^\]]*)\]", src)
    assert sig, "at-next is not defined"
    assert "errs" in sig.group(1), (
        "at-next takes no error text, so every next attempt starts from a "
        "cleared slot and reads what the attempt before it read")
    # A DEFAULT WOULD DEFEAT THE PARAMETER. Each caller states what the next
    # attempt should read: the two checkout failures carry the previous text,
    # because a checkout that produced no token says nothing about the fill, and
    # the agent-failure and rejection paths supply new text.
    calls = re.findall(r"\(at-next\s+a\s+[^\n]*", src)
    assert len(calls) >= 4, f"expected at least four at-next call sites, got {calls}"
    carried = [c for c in calls if "at-errors" in c]
    assert len(carried) == 2, (
        f"expected exactly the two checkout-failure paths to carry the previous "
        f"text forward, got {len(carried)}: {calls}")


def test_undo_keeps_the_log_reason_and_the_transcript_apart():
    """Two strings and not one. `why` is the short reason the reject line prints
    and the fill row records; `errs` is the compiler's whole transcript, which
    the next attempt's prompt renders. Folding them puts a 2 KB transcript in a
    log line, or hands the agent four words where the reference hands it the
    compiler's output."""
    sig = re.search(r"\(def-shell\s+undo\s*\[([^\]]*)\]", _uncommented(WAVE))
    assert sig, "undo is not defined"
    params = sig.group(1)
    assert "why" in params and "errs" in params, \
        f"undo no longer keeps the log reason and the transcript apart: {params}"


# ---------------------------------------------------------------------------
# 4. The pristine copy and the language reference
# ---------------------------------------------------------------------------

def test_the_pristine_copy_is_the_stage_input_and_never_the_tree():
    """driver-spec section 8 part 4: where the agent needs a copy of the subject
    to check its own work, the copy MUST be the ORIGINAL, unmodified subject.

    `FS-COPY-1` shipped `wasi.fs.copy` citing that clause, and 4e then used the
    builtin for its per-attempt backup and never for the agent's copy, so the
    mechanism existed and the clause it was built for was unmet.

    `wcfg-tree` is the .ast.json the wave patches IN PLACE, so by the second
    hole it carries the first hole's accepted fill. Copying that into an agent's
    directory hands over a peer's output, which section 8 forbids by name.
    """
    body = _body_of(_uncommented(WAVE), "provision-cmd")
    assert "wcfg-pristine" in body, \
        "the agent's self-check copy does not come from the declared pristine input"
    assert "wcfg-tree" not in body, (
        "the agent's copy is taken from the tree the wave patches in place, so "
        "by hole 1 it carries hole 0's accepted fill (driver-spec sec 8)")
    seq = _body_of(_uncommented(SEQUENCER), "wave-roots-path")
    assert "roots.llmll" in seq, \
        "the stage arm no longer names the authored roots as the pristine input"


def test_the_two_provisioning_mechanisms_are_not_conflated():
    """DIFFERENT SOURCES, DIFFERENT FLAGS, DIFFERENT FAILURE MODES.
    `stage-provision-ref?` copies LLMLL.md and the AST schema from
    --reference-dir and is the row `_provision_reference`'s four callers fill.
    The pristine copy comes from the stage's own input and has no flag of its
    own. Both are owed; conflating them loses one."""
    reg = _top_body_of(_uncommented(REGISTRY), "stage-provision-ref?")
    assert re.search(r"\(= i 13\)", reg), (
        "stage-provision-ref? has no row 13; the reference calls "
        "_provision_reference inside stage_M_wave's per-hole closure")
    fan = _body_of(_uncommented(SEQUENCER), "fan-cfg")
    assert "stage-provision-ref?" in fan, (
        "fan-cfg passes the reference directory unconditionally; the registry "
        "row is supposed to decide, and an empty directory is what tells the "
        "wave to copy nothing")
    prov = _body_of(_uncommented(WAVE), "provision-cmd")
    assert "ref-copies-cmd" in prov and "wcfg-pristine" in prov, \
        "the two provisioning mechanisms were folded into one"


def test_the_schema_reaches_the_agent_under_its_bare_name():
    """The template calls `llmll-ast.schema.json` in the agent's directory the
    authority on every node's shape. The reference copies to `wd / src.name`, so
    the file loses its `docs/` directory on the way in. A copy that kept the
    directory leaves the template naming a file that is not there."""
    body = _body_of(_uncommented(WAVE), "ref-copies-cmd")
    assert 'in-dir c a "llmll-ast.schema.json"' in body, \
        "the schema does not arrive under the bare name the template gives it"
    assert "llmll-ast.schema.json" in TEMPLATE.read_text(encoding="utf-8"), \
        "the template no longer names the schema, so this copy has no consumer"


# ---------------------------------------------------------------------------
# 5. The flags, and the message an operator actually sees
# ---------------------------------------------------------------------------

def test_the_new_required_flags_come_after_agent_cmd():
    """Cover cell W5 drops `--agent-cmd` alone and asserts the stop names that
    flag. `wave-missing-flags` answers the FIRST unmet condition, so a check
    placed above `--agent-cmd` would answer a different flag for the same input
    and W5 would grade a message no operator would see."""
    body = _body_of(_uncommented(WAVE), "wave-missing-flags")
    order = [m for m in re.findall(r'"(--[a-z-]+)', body)]
    for flag in ("--agent-cmd", "--prompt", "--pristine"):
        assert flag in order, f"{flag} is not required at all: {order}"
    assert order.index("--agent-cmd") < order.index("--prompt"), \
        f"the --prompt check precedes --agent-cmd, which moves W5's message: {order}"
    assert order.index("--agent-cmd") < order.index("--pristine"), \
        f"the --pristine check precedes --agent-cmd: {order}"
