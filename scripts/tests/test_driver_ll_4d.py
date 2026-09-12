"""DRIVER-LL sub-phase 4d: the checks that need no built sequencer.

4d ports stages H, K and N, the three whose oracle is the COMPILER: H and N
run `llmll verify --strict-verified-core` over files an agent wrote and score
the transcript, K runs `llmll check` and halts on its exit status. The
acceptance cover (`scripts/driver_ll_cover.py`, cells H1 to H5, K1 to K3, N1
to N4 and F0) runs the real compiler and needs a toolchain. Everything below
is a place the port and the reference, or the port and the compiler, can
drift with every cover cell still green and no toolchain on the machine to
notice.

Thirteen things about 4d are settleable statically:

  * the ONE `require_written` in the reference is stage H's, and it fires
    AFTER the write of feasibility.json (proposal section 9.3 item 2);
  * the port constructs `PartialThenHalt` at the stage sites this tier and
    4f own, carrying driver-spec sec 4:146-147 and sec 13, the 4a injector's
    sites aside;
  * that site decides one step AFTER the write it depends on, which is the
    write-before-halt construction discipline no proof can see;
  * stage K's hole count reaches a log line and nothing else (section 9.3
    item 3: `count("?")` is false the moment a `?` sits in a string literal);
  * `stage-needs-llmll?` agrees with the prompt files that carry `{{llmll}}`;
  * the precondition paths for H, K and N are the reference's, by AST;
  * stage K's row filter is the reference's `r["disposition"] == "Encoded"`;
  * each of the five 4d proved defs is forwarded exactly once;
  * the three lexemes the verify predicates key on are the compiler's own;
  * every `Ctl` constructor has an arm in all four dispatch matches;
  * `--llmll-cmd` is required at parse and the cover passes it;
  * `matrix-complete?`'s false branch is a disclosed unreachable halt;
  * `stage-agent-out` names the two catalogues the agent writes and defaults
    to the declared output everywhere else, which is the inverted artifact
    flow of restart record section 6 item 6 and the defect the first run of
    this sub-phase's cover found.

AST, NOT GREP, for every claim about the reference; BY NAME, NOT BY LINE, for
every claim about the port, on the reasoning `test_driver_ll_4c.py` gives.
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
PROMPTS = REPO / "experiments" / "rfc-swarm" / "prompts"
MAIN_HS = REPO / "compiler" / "app" / "Main.hs"

SRC = DRIVER.read_text()
TREE = ast.parse(SRC, filename=str(DRIVER))

PROVED_4D = ("probe-established?", "feasibility-established?",
             "outcome-as-expected?", "matrix-complete?", "probe-rows-conform?")


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


def _calls(fn: ast.FunctionDef, name: str) -> list[ast.Call]:
    return [n for n in ast.walk(fn)
            if isinstance(n, ast.Call) and isinstance(n.func, ast.Name)
            and n.func.id == name]


def _constants(fn: ast.FunctionDef) -> set[str]:
    return {n.value for n in ast.walk(fn)
            if isinstance(n, ast.Constant) and isinstance(n.value, str)}


def _defs(src: str) -> dict[str, str]:
    """Every `(def NAME` / `(def-shell NAME` block of an LLMLL module, by name.

    A block runs to the next top-level def or type form, so a name's body is
    the text a reader would attribute to it.
    """
    heads = list(re.finditer(r"^\s*\((?:def-shell|def-main|def|type)\s+([\w?!-]+)", src, re.M))
    out: dict[str, str] = {}
    for h, nxt in zip(heads, heads[1:] + [None]):
        end = nxt.start() if nxt else len(src)
        out[h.group(1)] = src[h.start():end]
    return out


SEQ_DEFS = _defs(SEQ)
REG_DEFS = _defs(REG)


def _referrers(name: str) -> set[str]:
    """The sequencer defs whose body mentions `name` as a call or argument,
    excluding its own definition."""
    pat = re.compile(r"[\s(]" + re.escape(name) + r"[\s)]")
    return {d for d, body in SEQ_DEFS.items() if d != name and pat.search(body)}


def _table_strings(fn: str) -> dict[int, list[str]]:
    """{index: [string literals]} of one registry if-chain."""
    block = REG_DEFS[fn]
    parts = re.split(r"\(if \(= i (\d+)\)", block)
    return {int(i): re.findall(r'"([^"]*)"', body)
            for i, body in zip(parts[1::2], parts[2::2])}


def _table_indices(fn: str) -> set[int]:
    """Every index a boolean registry table names as true."""
    return {int(i) for i in re.findall(r"\(= i (\d+)\)", REG_DEFS[fn])}


# ---------------------------------------------------------------------------
# 1. Stage H: the require_written site and its ordering
# ---------------------------------------------------------------------------

def test_the_reference_has_one_require_written_and_it_follows_the_write():
    """Proposal section 9.3 item 2: stage H holds the reference's ONLY
    `require_written`, and it fires after feasibility.json is written, which
    is why the disposition is `stopped` and the constructor PartialThenHalt.
    Counted over all three raising forms, by AST, in every top-level function.
    """
    sites = [(f.name, c) for f in TREE.body if isinstance(f, ast.FunctionDef)
             for c in _calls(f, "require_written")]
    assert [n for n, _ in sites] == ["stage_H_feasibility"], (
        f"require_written call sites are {[n for n, _ in sites]}; the port "
        "constructs PartialThenHalt at stage H alone on the strength of this")
    h = _fn("stage_H_feasibility")
    writes = [c for c in _calls(h, "write_json")
              if any(isinstance(a, ast.Constant) and a.value == "feasibility.json"
                     for a in ast.walk(c))]
    assert len(writes) == 1, "stage H must write feasibility.json exactly once"
    assert writes[0].lineno < sites[0][1].lineno, (
        "the write must precede the halt; otherwise sec 4:146-147 does not "
        "apply and the site reverts to `failed`")


def test_the_port_constructs_partial_then_halt_at_the_two_stage_sites():
    """The 4a injector builds PartialThenHalt on `--halt-kind` (its own
    sites: injected-outcome, halt-clause, stamped-step, halts-post?). Every
    OTHER site is a stage body's.

    4d landed the FIRST, stage H's probe-polarity bar. 4f landed the second,
    stage O's perturbation-omission check, so this assertion moved and the
    reason is recorded here rather than in a commit message: this test is what
    makes a third site arrive as a decision rather than as a diff."""
    injector = {"injected-outcome", "halt-clause", "stamped-step", "halts-post?"}
    users = {d for d, body in SEQ_DEFS.items()
             if re.search(r"[\s(]PartialThenHalt[\s)]", body)}
    stage_sites = users - injector
    assert stage_sites == {"hwrote-step", "o-decide"}, (
        f"PartialThenHalt is constructed by {sorted(stage_sites)} outside the "
        "injector; the stage sites are hwrote-step (4d) and o-decide (4f)")
    assert '"driver-spec sec 4:146-147"' in SEQ_DEFS["hwrote-step"], (
        "the stopped row must name the clause that authorised it")
    assert '"driver-spec sec 13"' in SEQ_DEFS["o-decide"], (
        "and so must 4f's")


def test_the_h_bar_is_decided_one_step_after_the_write():
    """Write-before-halt is a construction discipline no proof can see
    (proposal section 9.3 item 2). The bar is decided only in the arm that
    RECEIVES the write's response, and that arm is entered only by the arm
    that ISSUES the write."""
    assert _referrers("feasibility-established?") == {"feasible?"}
    assert _referrers("feasible?") == {"hwrote-step"}
    dispatch = {"drv-step", "drv-done?", "done-code", "drv-status"}
    enters = {d for d, body in SEQ_DEFS.items() if "(HWrote " in body} - dispatch
    assert enters == {"h-next"}, f"HWrote is entered from {sorted(enters)}"
    body = SEQ_DEFS["h-next"]
    assert "wasi.fs.write" in body and "(lp-acc l)" in body, (
        "h-next must issue the feasibility.json write on the way into HWrote")


# ---------------------------------------------------------------------------
# 2. Stage K: the hole count is a log figure
# ---------------------------------------------------------------------------

def test_the_hole_count_reaches_only_a_log_line():
    """Section 9.3 item 3: `count("?")` over the roots text is printed with a
    `~` and decides nothing, because it is false the moment a `?` appears in
    a string literal. The port's figure rides in the K payload; the only def
    that reads it back is the log line, and the only def that uses the log
    line hands it to stdout."""
    assert _referrers("hole-count") == {"k-enter"}, (
        "hole-count is computed once, on the way into KCheck")
    assert _referrers("kc-holes") == {"k-line"}, (
        "the stored hole count is read by the log line and nothing else")
    assert _referrers("k-line") == {"kcheck-step"}
    for line in SEQ_DEFS["kcheck-step"].splitlines():
        if "(k-line" in line:
            assert "(wasi.io.stdout (k-line" in line, (
                f"k-line reaches something other than stdout: {line.strip()}")
    assert "halt-" not in SEQ_DEFS["k-line"]


# ---------------------------------------------------------------------------
# 3. The registry rows, against the reference and the prompt files
# ---------------------------------------------------------------------------

def test_stage_needs_llmll_agrees_with_the_prompt_files():
    """A stage carries {{llmll}} iff its prompt template does. Computed over
    the files rather than remembered.

    M JOINED THE SET AT THE STAGE M AGENT CONTRACT. This test used to expect
    {8, 11} and said M "has no stage-prompt row and drops out by itself". The
    row was empty because sub-phase 4e rendered no prompt at all for stage M,
    which driver-spec section 8 part 3 refutes: a rendered task statement is a
    declared input because the driver declares it. The row now names
    stage-M-fill.md and the WAVE renders it, per attempt.

    M'S stage-needs-llmll? ROW IS DESCRIPTIVE AND NOT CONSULTED, which is why
    this test is where it earns its place. `render` in sequencer.llmll reads
    that row and stage M never reaches `render`: wave.llmll substitutes
    {{llmll}} unconditionally, because a wave with no compiler command cannot
    run. So nothing at run time would notice the row going stale, and this
    check over the prompt FILES is the only thing that would.
    """
    prompts = _table_strings("stage-prompt")
    carrying = {i for i, names in prompts.items() if names
                and "{{llmll}}" in (PROMPTS / names[0]).read_text()}
    assert carrying == {8, 11, 13}, \
        f"prompts carrying {{{{llmll}}}}: {sorted(carrying)}"
    assert _table_indices("stage-needs-llmll?") == carrying


def test_the_precondition_paths_of_h_k_n_are_the_references():
    """Every path the port reads before delegating is a path constant the
    reference's handler names. Checked per directory and per file name, by
    AST, so a renamed artifact on either side fails here."""
    handlers = {8: "stage_H_feasibility", 11: "stage_K_contracts",
                14: "stage_N_killmatrix"}
    paths = _table_strings("stage-pre-path")
    counts = dict(re.findall(r"\(= i (\d+)\)\s+(\d+)", REG_DEFS["stage-pre-count"]))
    for i, fn in handlers.items():
        consts = _constants(_fn(fn))
        rows = [r for r in paths[i] if r]   # the chain's "" default trails the last row
        assert len(rows) == int(counts[str(i)]), f"stage {i}: pre-count vs pre-path rows"
        for rel in rows:
            d, name = rel.split("/")
            assert d in consts and name in consts, (
                f"{fn} names no {rel!r} ({d!r}, {name!r}); the registry row is stale")


def test_stage_k_filters_on_the_references_own_compare():
    """`[r for r in rows if r["disposition"] == "Encoded"]`, found as a
    Compare node rather than remembered."""
    found = set()
    for n in ast.walk(_fn("stage_K_contracts")):
        if isinstance(n, ast.Compare) and isinstance(n.left, ast.Subscript) \
                and isinstance(n.left.slice, ast.Constant) \
                and len(n.comparators) == 1 \
                and isinstance(n.comparators[0], ast.Constant):
            found.add((n.left.slice.value, n.comparators[0].value))
    assert found == {("disposition", "Encoded")}, f"the reference compares {found}"
    key = _table_strings("stage-pre-filter-key")[11]
    val = _table_strings("stage-pre-filter-val")[11]
    assert key[0] == "disposition" and val[0] == "Encoded", (key, val)
    assert _table_strings("stage-pre-mode")  # the table parses
    assert re.search(r"\(= i 11\)\s+\(if \(= j 0\) 3", REG_DEFS["stage-pre-mode"]), (
        "K's inventory read is mode 3, the filter")


# ---------------------------------------------------------------------------
# 4. The proved cores are forwarded, the lexemes are the compiler's
# ---------------------------------------------------------------------------

def test_each_4d_proved_def_is_forwarded_exactly_once():
    """The 4e pattern: one one-line forward per proved def, so the call is
    visible to a reader and to the callerless census. A def forwarded twice
    is a decision made in two places; one forwarded zero times is the defect
    stage H exists to catch, turned on our own artifacts."""
    for name in PROVED_4D:
        sites = re.findall(r"\(" + re.escape(name) + r"\s", SEQ)
        assert len(sites) == 1, f"{name} is called {len(sites)} times in the sequencer"


def test_the_verify_lexemes_are_the_compilers():
    """oracle.llmll header item 2: the abstraction is a parse of the
    compiler's stdout, and a wording change keeps every proof green while
    changing what it means. The three literals are pinned against the source
    that prints them."""
    assert '"SAFE"' in SEQ_DEFS["verify-safe?"]
    assert '"body-faithful:"' in SEQ_DEFS["body-faithful-all?"]
    assert '"body-fallback:"' in SEQ_DEFS["body-faithful-all?"]
    hs = MAIN_HS.read_text()
    assert '"   body-faithful: "' in hs and '"   body-fallback: "' in hs, (
        "Main.hs no longer prints the two lists under the names the port reads")
    assert "SAFE" in hs


# ---------------------------------------------------------------------------
# 5. The state machine is total, the flag is required, the halt is disclosed
# ---------------------------------------------------------------------------

def test_every_ctl_constructor_has_an_arm_in_all_four_matches():
    """The 4e tier's 'three WCtl matches agree', over Ctl's four: drv-step,
    drv-done?, done-code and drv-status. A constructor with no arm is a
    partial match on the state the console loop hands back every step."""
    ctors = set(re.findall(r"^\s*\(\|\s+([A-Z]\w*)", SEQ_DEFS["Ctl"], re.M))
    assert len(ctors) >= 27, f"Ctl has {len(ctors)} constructors; 4d took it from 17 to 27"
    for fn in ("drv-step", "drv-done?", "done-code", "drv-status"):
        arms = set(re.findall(r"^\s*\(\(([A-Z]\w*)", SEQ_DEFS[fn], re.M))
        assert arms == ctors, f"{fn}: {sorted(ctors ^ arms)} differ from Ctl"


def test_llmll_cmd_is_required_and_the_cover_passes_it():
    """The parse-cfg comment said REQUIRED from 4c0014f on while missing-flags
    did not check it; 4d makes the code match the comment. The cover must
    then pass the flag on every run, which is checked by AST rather than by
    running it."""
    assert "cfg-llmll" in SEQ_DEFS["missing-flags"]
    assert "--llmll-cmd is required" in SEQ_DEFS["missing-flags"]
    tree = ast.parse(COVER.read_text(), filename=str(COVER))
    drive = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == "drive")
    assert "--llmll-cmd" in _constants(drive), "drive() no longer passes --llmll-cmd"
    assert "--reference-dir" in _constants(drive)


def test_matrix_complete_false_branch_is_a_disclosed_unreachable_halt():
    """oracle.matrix-complete? gates the kill-matrix write. Its false branch
    cannot fire (every row reaches NOut or NSkip and each appends one entry),
    and an unreachable halt is written down as such at the site rather than
    left to read as a live decision."""
    assert _referrers("complete-matrix?") == {"n-advance"}
    body = SEQ_DEFS["n-advance"]
    assert "halt-errored" in body and "unreachable by construction" in body


def test_stage_agent_out_names_the_two_catalogues():
    """Restart record section 6 item 6: H and N invert the artifact flow. The
    agent writes `probes.json` / `mutants.json` (the out_name of each
    ctx.agent.run) and the DRIVER writes the declared output. The first run
    of this sub-phase's cover handed the agent the declared path, and the
    shape check rejected the driver's own placeholder; this pins the table
    against the reference's out_name arguments so it cannot regress silently.
    """
    def out_name(fn: str) -> str:
        calls = [c for c in ast.walk(_fn(fn))
                 if isinstance(c, ast.Call) and isinstance(c.func, ast.Attribute)
                 and c.func.attr == "run" and isinstance(c.func.value, ast.Attribute)
                 and c.func.value.attr == "agent"]   # not subprocess.run
        assert len(calls) == 1, fn
        arg = calls[0].args[2]
        assert isinstance(arg, ast.Constant), fn
        return arg.value
    rows = _table_strings("stage-agent-out")
    assert rows[8][0] == "07-feasibility/" + out_name("stage_H_feasibility")
    assert rows[14][0] == "13-kill-matrix/" + out_name("stage_N_killmatrix")
    assert out_name("stage_K_contracts") == "roots.llmll", (
        "K's agent writes the declared output itself, so it takes the default")
    assert "(stage-out i j)" in REG_DEFS["stage-agent-out"], (
        "every other stage must default to its declared output")
    assert _referrers("agent-out-path") >= {"delegate-cmd", "delegate-step"}, (
        "the agent must be handed the catalogue path and Outp must read it")
    assert "stage-agent-out" in SEQ_DEFS["absent-detail"], (
        "an absent output is reported under the name the agent was asked for")
