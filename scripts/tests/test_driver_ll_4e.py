"""DRIVER-LL sub-phase 4e: the checks that do not need a built wave.

4e's whole cover lives in `scripts/wave_cover.py`, which needs a toolchain, a
built binary and a real compiler, and runs from `scripts/build_smoke.sh` stage
9. That is the right home for every decision the fill protocol makes, because
only a run could settle them. It is the wrong home for everything below, each
of which is a place the wave can rot with all seven cells still green and with
no `llmll` on the machine to notice.

Seven things about 4e are settleable statically:

  * THE SEAM IS ONE SITE. `wave.llmll` reads another process's stdout, and
    every such read is outside Sigma_auto by construction. The module's claim
    is that each is written ONCE, so the unproved surface is auditable in one
    place; a second `string-contains` appearing inside a state-machine arm
    would make that claim false with no gate to say so;

  * THE FOUR PROVED CORES ARE STILL CALLED. This is the whole point of the
    sub-phase and the reason `test_driver_ll_callers.py` shrank from twelve
    rows to eight. A refactor that inlined `fill-accepted`'s conjunction into
    the arm would leave every cover cell green and quietly return the census
    to where 4e found it;

  * `token-during` IS CONSULTED BEFORE THE AGENT RUNS and not merely imported.
    The guard is what makes the proved decision decide something, and the
    shipped defect it stands against (`crux-token-held-across-call`, fourteen
    wedged holes on the first wave) is invisible to a cover whose stub agent
    never wedges;

  * THE CONTENTION PREDICATE KEYS ON `stale` AND NOT ON THE FULLER PHRASE. The
    compiler's message carries U+2014 EM DASH immediately after that lexeme, so
    a predicate written against the readable phrase matches nothing and every
    contention is charged to the error budget [S9-SEPARATE] says never
    depletes. No cell can catch a predicate that is merely never true;

  * THE STATE MACHINE IS EXHAUSTIVE. Three matches over `WCtl` have to name
    every arm, and the compiler enforces that; what it does not enforce is that
    the three agree, so an arm that is a step but never terminal, or terminal
    but never a step, type-checks;

  * THE COVER IS WIRED INTO THE BUILD GATE. 4c shipped its cover with nothing
    invoking it and `test_driver_ll_4c.py` was written because of it. A cover
    that no gate runs is a file, not a check;

  * THE CENSUS ROWS 4e DISCHARGED ARE GONE, not widened, and no
    `4e-owes-caller` class survives in the register.

AGAINST THE SOURCE TEXT, not against a built artifact, on the same reasoning
`test_driver_ll_4c.py` gives: this tier runs on a machine with no toolchain.
"""

from __future__ import annotations

import ast
import importlib.util
import json
import pathlib
import re

REPO = pathlib.Path(__file__).resolve().parents[2]
DRIVER_LL = REPO / "tools" / "llmll-driver"
WAVE = DRIVER_LL / "wave.llmll"
FIXTURE = DRIVER_LL / "fixtures" / "wave-roots.llmll"
COVER = REPO / "scripts" / "wave_cover.py"
SMOKE = REPO / "scripts" / "build_smoke.sh"
CALLERS = REPO / "scripts" / "tests" / "test_driver_ll_callers.py"

_IDENT_TAIL = r"(?![\w?!-])"


def _uncommented(path: pathlib.Path) -> str:
    """Source with `;` comment tails removed, string literals respected.

    `wave.llmll` is more comment than code and its header quotes the very
    predicates asserted below, so a raw-text search would find the prose and
    conclude the code is there.
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


def _defs(src: str) -> list[str]:
    return re.findall(r"\(def(?:-shell)?\s+([^\s()\[\]]+)", src)


def _body_of(src: str, name: str) -> str:
    """The text of one def, from its opening paren to the next top-level def.

    Crude on purpose: the assertions below are about which NAMES appear inside
    which def, and a paren-accurate slice would need a reader for a language
    this file is deliberately not parsing.
    """
    m = re.search(r"\(def(?:-shell)?\s+" + re.escape(name) + _IDENT_TAIL, src)
    assert m, f"{name} is not defined"
    rest = src[m.end():]
    nxt = re.search(r"\n  \(def(?:-shell)?\s", rest)
    return rest[:nxt.start()] if nxt else rest


# ---------------------------------------------------------------------------
# 1. The unproved seam
# ---------------------------------------------------------------------------

# Every function that reads another process's output. Each is a shell-side
# observation with no proposition for a prover to discharge, so the module's
# mitigation is that there are exactly these and they are written once.
#
# IDENTIFIED BY A CONJUNCTION, takes `out: string` AND reads it, because this
# file tried each half alone first and each half alone was wrong.
# "calls string-contains" also catches `missing-flags`, whose subject is the
# operator's OWN argv and carries no verification claim. "takes an `out`" also
# catches `accept-fill?` and `spend-budget`, which take the transcript and hand
# it straight to a proved decision without deciding anything about it.
SEAM = {
    "patch-succeeded?", "contention?", "verify-safe?", "body-faithful?",
    "termination-observed?", "seal-holds?",
}

# Reads a string, but its subject is the operator's own argv. Named here with
# its reason rather than filtered silently, so a second exception has to be
# argued for.
NOT_A_SUBPROCESS_READ = {"missing-flags"}


def _params(src: str, name: str) -> str:
    m = re.search(r"\(def(?:-shell)?\s+" + re.escape(name) + _IDENT_TAIL
                  + r"\s*\[([^\]]*)\]", src)
    return m.group(1) if m else ""


def test_the_seam_is_exactly_the_declared_set():
    """A CONJUNCTION, and each half is needed. `missing-flags` calls
    `string-contains` and takes no `out`; `accept-fill?` and `spend-budget`
    take an `out` and never read it, because their whole job is to hand it to
    a proved decision. Either half alone names one of those three as part of
    the unproved seam."""
    src = _uncommented(WAVE)
    measured = {d for d in _defs(src)
                if "out: string" in _params(src, d)
                and "string-contains" in _body_of(src, d)}
    assert measured == SEAM, (
        f"a new reader of someone else's stdout: {sorted(measured - SEAM)}\n"
        f"a declared one that stopped reading: {sorted(SEAM - measured)}")


def test_the_forwards_pass_the_output_on_rather_than_reading_it():
    """The other half of the split: `accept-fill?` and `spend-budget` take the
    transcript and must not decide anything about it themselves. A
    `string-contains` appearing here would move a decision out of the proved
    core and into the seam without changing a single cover cell."""
    src = _uncommented(WAVE)
    for d in ("accept-fill?", "spend-budget"):
        assert "out: string" in _params(src, d), f"{d} no longer takes the output"
        assert "string-contains" not in _body_of(src, d), \
            f"{d} decides something about the transcript instead of forwarding it"


def test_no_subprocess_read_is_inlined_into_an_arm():
    """The claim the header makes: the seam is auditable at one site. A
    `string-contains` inside a state-machine arm would be a second site."""
    src = _uncommented(WAVE)
    allowed = SEAM | NOT_A_SUBPROCESS_READ
    for d in _defs(src):
        if d in allowed:
            continue
        assert "string-contains" not in _body_of(src, d), (
            f"{d} reads a string directly; the seam is supposed to be the "
            f"{len(SEAM)} predicates in SEAM, plus {sorted(NOT_A_SUBPROCESS_READ)} "
            f"over the operator's own argv")


def test_contention_keys_on_the_ascii_lexeme():
    """The message is `obligation context is stale`, then U+2014, then
    `re-checkout required (source file changed)`. Written out that way rather
    than reproduced, because the character is the whole hazard.

    Keying on anything past `stale` matches that dash, so the predicate would
    be never-true and every contention would be charged to the error budget.
    Nothing observable distinguishes a never-true predicate from an absent
    contention, which is why this is asserted rather than covered."""
    body = _body_of(_uncommented(WAVE), "contention?")
    lits = re.findall(r'"([^"]*)"', body)
    assert "stale" in lits, f"contention? no longer tests for `stale`: {lits}"
    assert not any("—" in s for s in lits), \
        "contention? carries an em dash, so it can never match"
    assert not any(s.startswith("stale") and len(s) > len("stale")
                   for s in lits), \
        "contention? keys on a phrase longer than the ASCII lexeme `stale`"


def test_the_seal_needs_more_than_the_word_safe():
    """A tree that fails `--strict-verified-core` prints no SAFE line at all,
    so keying on SAFE alone would pass a run that never reached the solver.
    Both conjuncts are the check."""
    body = _body_of(_uncommented(WAVE), "seal-holds?")
    assert "SAFE" in body and "fell back" in body, \
        f"seal-holds? lost a conjunct: {body.strip()}"


# ---------------------------------------------------------------------------
# 2. The proved cores are still called
# ---------------------------------------------------------------------------

# Qualified name -> the def in `wave` that forwards to it. One forward each, so
# the call is visible to a reader and to the callerless census.
FORWARDS = {
    "fill-accepted": "accept-fill?",
    "next-error-budget": "spend-budget",
    "is-finding": "finding?",
    "token-during": "token-state-now",
}


def test_every_proved_core_has_its_forward():
    src = _uncommented(WAVE)
    for core, forward in FORWARDS.items():
        assert re.search(r"(?<![\w?!-])" + re.escape(core) + _IDENT_TAIL,
                         _body_of(src, forward)), \
            f"{forward} no longer calls {core}, which is the whole of 4e"


def test_every_forward_is_reached_from_the_state_machine():
    """A forward nothing calls is the defect this sub-phase exists to close,
    reproduced one level up."""
    src = _uncommented(WAVE)
    for core, forward in FORWARDS.items():
        sites = [d for d in _defs(src)
                 if d != forward
                 and re.search(r"(?<![\w?!-])" + re.escape(forward) + _IDENT_TAIL,
                               _body_of(src, d))]
        assert sites, (
            f"{forward} forwards to {core} and nothing calls {forward}, so "
            f"the proved decision still decides nothing")


def test_the_token_guard_admits_the_agent_call():
    """`must-release-before-agent?` is `token-during` at AgentWorking, and the
    arm that spawns the agent is guarded by it. The shipped defect this stands
    against wedged fourteen holes; a stub agent cannot wedge, so no cover cell
    reaches it."""
    body = _body_of(_uncommented(WAVE), "rel-step")
    assert "must-release-before-agent?" in body, \
        "the agent call is no longer guarded by the token invariant"
    assert "wasi.proc.run" in body, \
        "rel-step no longer spawns the agent, so the guard guards nothing"


def test_the_release_precedes_the_agent_in_the_protocol():
    """§10:371-373's ordering is a SHELL obligation: `token-during` is
    memoryless and constrains each step, not the sequence. The ordering is
    discharged by `brief-step` issuing the release and `rel-step` spawning the
    agent afterwards, and by nothing in `token.llmll`."""
    src = _uncommented(WAVE)
    assert "--release" in _body_of(src, "brief-step"), \
        "the brief is no longer released before the agent runs"
    assert "wasi.proc.run" not in _body_of(src, "brief-step"), \
        "brief-step spawns something, so the release may not precede the agent"


# ---------------------------------------------------------------------------
# 3. The state machine
# ---------------------------------------------------------------------------

def _ctl_arms() -> list[str]:
    src = _uncommented(WAVE)
    decl = re.search(r"\(type WCtl(.*?)\n\n", src, re.S)
    assert decl, "the WCtl declaration moved"
    return re.findall(r"\(\|\s+(\w+)", decl.group(1))


def test_the_three_matches_over_ctl_agree():
    """The compiler enforces that each match is exhaustive. It does not
    enforce that the three name the same arms, so an arm that is a step but
    never terminal type-checks and hangs the run."""
    src = _uncommented(WAVE)
    arms = set(_ctl_arms())
    assert len(arms) >= 10, f"WCtl lost arms: {sorted(arms)}"
    for fn in ("wave-step", "wave-done?", "done-code"):
        named = set(re.findall(r"\(\((\w+)[ )]", _body_of(src, fn)))
        assert named == arms, (
            f"{fn} does not match WCtl: missing {sorted(arms - named)}, "
            f"extra {sorted(named - arms)}")


def test_exactly_one_arm_is_terminal():
    """`Done` and nothing else. Two terminal arms would make the exit code
    depend on which one the run happened to reach."""
    body = _body_of(_uncommented(WAVE), "wave-done?")
    trues = re.findall(r"\(\((\w+)[^)]*\)\s+true\)", body)
    assert trues == ["Done"], f"the terminal arms are {trues}, not just Done"


def test_the_main_options_are_in_the_fixed_order():
    """`Parser.hs` parses the five in sequence, so `:status` before `:on-done`
    is a parse error rather than a reorder. Asserted because the run that
    would catch it is the toolchain tier."""
    src = _uncommented(WAVE)
    # `\b` cannot follow `done\?`: `?` is not a word character, so a boundary
    # there matches nothing and the option silently drops out of the sequence.
    order = re.findall(r":(mode|init|step|done\?|on-done|status)(?![\w?-])", src)
    assert order == ["mode", "init", "step", "done?", "on-done", "status"], \
        f"def-main's options are out of order: {order}"


# ---------------------------------------------------------------------------
# 4. The fixture, and the clause it exists to keep non-vacuous
# ---------------------------------------------------------------------------

def test_the_fixture_carries_at_least_two_holes():
    """Rev 15 risk 1. The contention clause needs two briefs outstanding at one
    source_hash, and one hole cannot produce a second brief. The clause has
    gone vacuous twice by two other mechanisms; a one-hole fixture is the
    third."""
    holes = re.findall(r"\?body-[\w-]+", FIXTURE.read_text())
    assert len(holes) >= 2, f"the fixture has {len(holes)} hole(s): {holes}"


def test_the_fixture_holes_are_independent():
    """Neither contract calls the other, so neither fill needs its sibling
    filled first. A strict-core `def` may not call a sibling lacking persisted
    verified evidence, so a fixture whose holes called each other would make
    the wave order-dependent and would be measuring that instead of the
    protocol."""
    src = FIXTURE.read_text()
    names = re.findall(r"\(def\s+([\w?!-]+)", src)
    for name in names:
        others = [n for n in names if n != name]
        body = _body_of(src, name)
        for other in others:
            assert not re.search(r"\(" + re.escape(other) + _IDENT_TAIL, body), \
                f"{name} calls its sibling {other}; the holes are not independent"


# ---------------------------------------------------------------------------
# 5. The cover exists, is wired in, and claims only what it runs
# ---------------------------------------------------------------------------

def _cover_cells() -> list[str]:
    tree = ast.parse(COVER.read_text())
    cells = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.FunctionDef):
            continue
        for dec in node.decorator_list:
            if (isinstance(dec, ast.Call) and isinstance(dec.func, ast.Name)
                    and dec.func.id == "cell" and dec.args
                    and isinstance(dec.args[0], ast.Constant)):
                cells.append(dec.args[0].value)
    return cells


def test_the_cover_is_run_by_the_build_gate():
    """4c shipped a cover that nothing invoked. A cover no gate runs is a
    file, not a check."""
    smoke = SMOKE.read_text()
    assert "scripts/wave_cover.py" in smoke, \
        "build_smoke.sh does not run the wave cover"
    assert "--wave" in smoke and "--llmll" in smoke, \
        "the gate invokes the cover without the binaries it needs"


def test_the_gate_banner_counts_the_cells_it_ran():
    """A banner naming more cells than the file defines is the coverage claim
    this repository has overstated before."""
    n = len(_cover_cells())
    assert n >= 7, f"the cover defines only {n} cells"
    m = re.search(r"DRIVER-LL 4e wave cover \((\d+) cells", SMOKE.read_text())
    assert m, "the gate banner does not state a cell count"
    assert int(m.group(1)) == n, \
        f"the banner claims {m.group(1)} cells and the cover defines {n}"


def test_the_contention_cell_holds_two_briefs():
    """The one cell the 4e row makes mandatory. It is asserted structurally
    because a cell that stopped taking the second brief would still pass: the
    wave would simply never be refused, and an absent rejection reads the same
    as a rejection that never had to happen."""
    src = COVER.read_text()
    body = src[src.index("def w4("):]
    body = body[:body.index("\n@cell")] if "\n@cell" in body else body
    assert "c.checkout(" in body, \
        "W4 no longer takes a brief of its own, so only one brief is ever live"
    assert "c.patch(" in body, \
        "W4 no longer patches, so the wave's brief never goes stale"
    assert "PatchSuccess" in body, (
        "W4 does not check that its own patch landed, so a silently failed "
        "injection would read as an absent contention")


# ---------------------------------------------------------------------------
# 6. The census 4e discharged
# ---------------------------------------------------------------------------

def test_no_row_still_waits_on_4e():
    """The rows are deleted rather than widened, and the class goes with its
    last row rather than staying behind as an empty bucket.

    THE REGISTER, NOT THE FILE'S TEXT. A raw search finds the sentence in that
    file's own docstring explaining that the class is gone and concludes it is
    still there, which is the mistake `_uncommented` exists for one directory
    over and which this assertion made on its first run.
    """
    spec = importlib.util.spec_from_file_location("_callers", CALLERS)
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    CALLERLESS = mod.CALLERLESS
    classes = {cls for cls, _ in CALLERLESS.values()}
    assert "4e-owes-caller" not in classes, \
        f"a census row still waits on 4e, which has landed: {sorted(classes)}"
    assert not any(q.startswith(("fill.", "token.")) for q in CALLERLESS), \
        f"a fill or token def is still registered as callerless: {sorted(CALLERLESS)}"


def test_the_wave_is_a_program_and_imports_both_proved_modules():
    """The orphan remedy is an import from a program, not a call site. Both
    halves are needed: a `def-main` with no import leaves `fill` and `token`
    orphaned, and an import with no `def-main` leaves `wave` orphaned too,
    which is the state 4e passed through."""
    src = _uncommented(WAVE)
    assert re.search(r"\(def-main" + _IDENT_TAIL, src), "wave has no def-main"
    imports = set(re.findall(r"\(import\s+([a-z][\w-]*)\)", src))
    assert {"fill", "token"} <= imports, \
        f"wave no longer imports the modules it rescued: {sorted(imports)}"


def test_the_frozen_verdict_covers_the_wave():
    """`sequencer`, `spine` and `shape` each froze a verdict when they landed.
    The wave's protects the same thing theirs do: that the module keeps
    IMPORTING the proved decisions rather than reimplementing them."""
    cases = json.loads((DRIVER_LL / "EXPECTED_VERDICTS.json").read_text())["cases"]
    files = {c["file"] for c in cases}
    assert "wave.llmll" in files, (
        "the wave's verify verdict is frozen nowhere, so a module that stopped "
        "compiling would be caught only by the build gate")
