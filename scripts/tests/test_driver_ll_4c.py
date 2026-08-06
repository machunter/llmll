"""DRIVER-LL sub-phase 4c: the checks that do not need a built sequencer.

4c shipped with NOTHING in this tier, which is why this file exists. Its whole
cover lives in `scripts/driver_ll_cover.py`, which needs a toolchain and a
built binary and runs from `scripts/build_smoke.sh` stage 8. That is the right
home for the two provisioning defects 4c found, because only a run could have
caught them. It is the wrong home for everything below, each of which is a
place the port and the reference can drift with every cover cell still green
and with no toolchain on the machine to notice.

Six things about 4c are settleable statically:

  * the content-shape channel's SIGNATURES. `shape.llmll`'s four defs take
    only `bool` and `int`. That is the same argument `validate.verdict-of`
    makes by taking no string, made once per def: a validator that can read a
    document can be fitted to one document, and driver-spec section 7:288-291
    is the obligation that forbids it. A `Json` parameter appearing here would
    be a one-token change that no cover cell and no proof would fail on;

  * WHICH STAGES CLAIM TO BE PORTED. `registry.stage-ported?` is an index
    switch and the reference's stage letters are a separate table. A stage
    flipped on before its body exists compiles and lies, which the 4c plan
    names as worse than a tree that does not compile;

  * THE ONE SPEC-DEFINED HALT IN `check_dispositioned`. Five of its six checks
    are `require` and record `failed`; the barrier check is `require_spec` and
    records `stopped`. That single asymmetry is the whole reason 4c builds
    three of `Outcome`'s four arms where 4b built two (proposal Rev 11
    section 9.2 item 1). If the reference ever levels them, the port's split
    becomes wrong silently, in the direction that files a method verdict as an
    accident;

  * THE DICT-OR-LIST TOLERANCE CENSUS, which has been stated short twice.
    F-20 named two sites, the 4c plan found a third, and this file's own
    authoring found a FOURTH. A census is the kind of claim that should be
    computed rather than remembered;

  * that `regex-match` is called NOWHERE. It typechecks, it verifies, and it
    does not build (`REGEX-LOWER-1`), so a well-meaning simplification of
    either hand-rolled pattern check back to the builtin breaks the build and
    only the toolchain tier would say so;

  * that NO COVER CELL CLAIMS to exercise a budget-overrun halt. D, F and G
    each invoke an agent and `wasi.proc.run`'s timeout does not fire
    (`PROC-TIMEOUT-1`), so three overrun halts are written and unreachable. A
    cell that claimed one would be reporting coverage it does not have.

AST, NOT GREP, for every claim about the reference, on the same reasoning
`test_driver_ll_4b.py` gives: a `require(` count over source text counts
docstring mentions and the definition, which is the error the Phase 4
proposal's own Rev 8 stamp made.

BY NAME, NOT BY LINE, for every claim that could be keyed either way.
Proposal section 3.5.1: two of the nine spec-defined line numbers already
point at sites with the opposite disposition, so a reader keying on a number
lands somewhere plausible and nothing signals the miss.
"""
from __future__ import annotations

import ast
import pathlib
import re

REPO = pathlib.Path(__file__).resolve().parents[2]
DRIVER = REPO / "scripts" / "rfc_to_implementation.py"
COVER = REPO / "scripts" / "driver_ll_cover.py"
DRIVER_LL = REPO / "tools" / "llmll-driver"
SHAPE = DRIVER_LL / "shape.llmll"
REGISTRY = DRIVER_LL / "registry.llmll"

SRC = DRIVER.read_text()
TREE = ast.parse(SRC, filename=str(DRIVER))
HALT_HELPERS = {"require", "require_spec", "require_written"}

SHAPE_DEFS = ("extraction-conforms?", "core-conforms?",
              "dispositions-conform?", "barrier-condition-met?")

# index -> letter, from registry.llmll's own stage table. Duplicated here on
# purpose: a test that reads the table it is checking cannot fail.
PORTED = {1: "B", 2: "C", 3: "D", 5: "F", 6: "G", 9: "I"}


def _fn(name: str) -> ast.FunctionDef:
    for node in TREE.body:
        if isinstance(node, ast.FunctionDef) and node.name == name:
            return node
    raise AssertionError(f"{name} is not a top-level function of {DRIVER.name}")


def _own_halts(fn: ast.FunctionDef) -> list[tuple[str, str]]:
    """Every halt this function performs in its OWN body, as (helper, clause).

    `clause` is the `require_spec` citation where there is one and "" for a
    plain `require`, so the spec-defined halts are identifiable without a line
    number.
    """
    out = []
    for n in ast.walk(fn):
        if isinstance(n, ast.Call) and isinstance(n.func, ast.Name) \
                and n.func.id in HALT_HELPERS:
            clause = ""
            if n.func.id == "require_spec" and len(n.args) >= 3:
                arg = n.args[2]
                if isinstance(arg, ast.Constant) and isinstance(arg.value, str):
                    clause = arg.value
            out.append((n.func.id, clause))
    return out


def _uncommented(path: pathlib.Path) -> str:
    """LLMLL source with `;;` comment tails removed.

    Every mention of `regex-match` in this directory today is prose explaining
    why it is not called. Searching the raw text would find those and prove
    nothing.
    """
    return "\n".join(line.split(";;")[0] for line in
                     path.read_text().splitlines())


def _llmll_params(src: str, fn: str) -> list[tuple[str, str]]:
    """The declared parameter list of an LLMLL `def`, as (name, type)."""
    m = re.search(r"\(def %s \[([^\]]*)\]" % re.escape(fn), src)
    assert m, f"{fn} has no parameter list in {SHAPE.name}"
    return re.findall(r"([\w?!-]+):\s*([\w\[\]]+)", m.group(1))


def _tolerance_census() -> set[tuple[str, str]]:
    """Every `X[k] if isinstance(X, dict) ... else X` in the reference.

    Returned as (enclosing function, indexed key) rather than as line numbers,
    so a shift cannot make a stale expectation look satisfied.
    """
    owner: dict[int, str] = {}
    for f in ast.walk(TREE):
        if isinstance(f, (ast.FunctionDef, ast.AsyncFunctionDef)):
            for n in ast.walk(f):
                owner[id(n)] = f.name
    found = set()
    for n in ast.walk(TREE):
        if not isinstance(n, ast.IfExp):
            continue
        tests = n.test.values if isinstance(n.test, ast.BoolOp) else [n.test]
        guarded = any(isinstance(t, ast.Call) and isinstance(t.func, ast.Name)
                      and t.func.id == "isinstance" for t in tests)
        if not guarded:
            continue
        key = None
        if isinstance(n.body, ast.Subscript) \
                and isinstance(n.body.slice, ast.Constant):
            key = n.body.slice.value
        found.add((owner.get(id(n), "<module>"), key))
    return found


# ---------------------------------------------------------------------------
# 1. The content-shape channel's signatures ARE the subject-neutrality argument
# ---------------------------------------------------------------------------

def test_the_shape_channel_reads_no_subject_content():
    """driver-spec section 7:288-291 again, one def at a time.

    `validate.verdict-of` earns subject-neutrality by taking no string. The
    content-shape channel decides over CONTENT, so it cannot take no
    information about content; what it takes instead is facts already reduced
    to bools and ints by the `def-shell` caller. The document never crosses the
    boundary, so no body on this side can be fitted to one. `[D7-NO-HARDCODE]`
    refutes a fitted body; this test is what stops the parameter list from
    acquiring the `Json` that would make a fitted body expressible.
    """
    src = SHAPE.read_text()
    offenders = {}
    for fn in SHAPE_DEFS:
        params = _llmll_params(src, fn)
        assert params, f"{fn} declares no parameters"
        bad = [(n, t) for n, t in params if t not in ("bool", "int")]
        if bad:
            offenders[fn] = bad
    assert not offenders, (
        f"the content-shape channel took a non-scalar parameter: {offenders}. "
        "A `Json` or `string` here puts every row of every census in scope and "
        "leaves review as the only thing stopping a body from reading one, "
        "which is the failure driver-spec section 7:288-291 names.")


def test_the_shape_posts_are_named():
    """The four tags that make the channel's properties proofs rather than
    readings. Named here so a header rewrite that drops one is loud."""
    src = SHAPE.read_text()
    for tag in ("[D7-NO-HARDCODE]", "[D7-ROWS]",
                "[G6-CLOSED]", "[G6-NOVACUOUS]"):
        assert tag in src, f"shape.llmll no longer carries {tag}"


# ---------------------------------------------------------------------------
# 2. Which stages claim to be ported
# ---------------------------------------------------------------------------

def test_exactly_six_stages_claim_to_be_ported_and_they_are_the_expected_six():
    """`registry.stage-ported?` is the switch between a real body and a stub.

    Flipping a stage on before its body exists produces a tree that compiles
    and lies, which is strictly worse than one that does not compile, and no
    proof and no type would catch it. The letters come from the reference's own
    stage list so that a renumbering on either side is a failure here.
    """
    block = REGISTRY.read_text().split("(def-shell stage-ported? ")[1] \
                                .split("\n(def-shell ")[0]
    ported = {int(i) for i in re.findall(r"\(if \(= i (\d+)\) true", block)}
    assert ported == set(PORTED), (
        f"stage-ported? claims {sorted(ported)}; expected {sorted(PORTED)} "
        f"({', '.join(PORTED[i] for i in sorted(PORTED))})")

    stages = [n for n in ast.walk(TREE) if isinstance(n, ast.Call)
              and isinstance(n.func, ast.Name) and n.func.id == "Stage"]
    letters = [c.args[0].value for c in stages
               if c.args and isinstance(c.args[0], ast.Constant)]
    for i, letter in PORTED.items():
        assert letter in letters, (
            f"index {i} is ported as stage {letter}, which the reference's "
            "own stage list does not contain")


def test_stage_D_runs_two_tagged_extractors_and_the_registry_agrees():
    """The invocation index exists because stage D delegates twice.

    Authoring this test refuted two plausible readings of what
    `stage-tag-count` counts, and neither is declared outputs and neither is
    static call sites. D declares two outputs and holds ONE `agent.run` call
    site, executed twice by a loop over `("a", "b")`. K holds two call sites
    and declares one output. So the relation that actually holds is the loop:
    D iterates its two extractor tags, and the registry's table is that
    iteration hoisted into a constant.
    """
    f = _fn("stage_D_extract")
    tags = set()
    for n in ast.walk(f):
        if isinstance(n, ast.For) and isinstance(n.target, ast.Name) \
                and n.target.id == "tag" and isinstance(n.iter, ast.Tuple):
            tags.add(tuple(e.value for e in n.iter.elts
                           if isinstance(e, ast.Constant)))
    assert tags == {("a", "b")}, (
        f"stage_D_extract iterates {tags or 'no tag tuple'}; the port's two "
        "invocations, its per-tag artifact paths and its `{{extractor}}` "
        "substitution are all keyed on exactly these two tags.")

    block = REGISTRY.read_text().split("(def-shell stage-tag-count ")[1] \
                                .split("\n(def-shell ")[0]
    assert re.search(r"\(if \(= i 3\) 2", block), (
        "stage-tag-count no longer gives stage D (index 3) two invocations")


def test_the_tag_table_is_D_only_and_three_later_stages_will_break_it():
    """A forward hazard, asserted so that it fires when it arrives.

    `stage-tag-count` is `(if (= i 3) 2 1)`. That is right for everything
    ported today, and wrong for three stages that are not: K holds two
    `agent.run` call sites, M holds two and declares two outputs, and L holds
    two while being a gate. Whichever of those lands first, its port needs the
    table widened, and nothing else in the tree would say so.

    This test passes while the hazard is only a hazard. It fails the moment one
    of the three is marked ported without the table moving, which is the only
    moment the information is worth anything.
    """
    fns = {n.name: n for n in TREE.body if isinstance(n, ast.FunctionDef)}
    multi = set()
    for c in ast.walk(TREE):
        if not (isinstance(c, ast.Call) and isinstance(c.func, ast.Name)
                and c.func.id == "Stage" and len(c.args) >= 4):
            continue
        letter, handler = c.args[0], c.args[3]
        if not (isinstance(letter, ast.Constant) and isinstance(handler, ast.Name)):
            continue
        body = fns.get(handler.id)
        if body is None:
            continue
        runs = sum(1 for x in ast.walk(body) if isinstance(x, ast.Call)
                   and isinstance(x.func, ast.Attribute) and x.func.attr == "run")
        loops = any(isinstance(x, ast.For) and isinstance(x.iter, ast.Tuple)
                    and len(x.iter.elts) > 1 for x in ast.walk(body))
        if runs > 1 or loops:
            multi.add(letter.value)
    assert multi == {"D", "K", "L", "M"}, (
        f"the reference's multi-invocation stages are {sorted(multi)}; the "
        "expectation was D, K, L and M. A new one is a stage whose extra "
        "delegation stage-tag-count does not know about.")

    ported_letters = {PORTED[i] for i in PORTED}
    unported_multi = multi - ported_letters
    assert unported_multi == {"K", "L", "M"}, (
        f"{sorted(unported_multi & ported_letters)} is marked ported and "
        "delegates more than once, but stage-tag-count still gives two "
        "invocations to D alone. Widen the table with the port, not after it.")


# ---------------------------------------------------------------------------
# 3. The one spec-defined halt, which is why 4c has a third Outcome arm
# ---------------------------------------------------------------------------

def test_the_barrier_check_is_the_only_spec_defined_halt_in_check_dispositioned():
    """Proposal Rev 11 section 9.2 item 1, as a census rather than a reading.

    Five `require` recording `failed`, one `require_spec` recording `stopped`.
    That asymmetry is the entire reason 4c constructs `ConditionUnmet` and
    routes it through the sequencer's own halt channel rather than through
    `validate.verdict-outcome`, which `[V7-NO-STOP]` forbids. Level the two in
    the reference and the port files a verdict the method reached as an
    accident, which is precisely the distinction driver-spec section 4:133-137
    draws and the two halt channels exist to keep.
    """
    halts = _own_halts(_fn("check_dispositioned"))
    kinds = [h for h, _ in halts]
    assert kinds.count("require") == 5 and kinds.count("require_spec") == 1, (
        f"check_dispositioned's halts are {halts}. The port splits `stopped` "
        "from `failed` on exactly this five-to-one shape.")
    clause = next(c for h, c in halts if h == "require_spec")
    assert "driver-spec" in clause and "6:" in clause, (
        f"the spec-defined halt cites {clause!r}; the port's ConditionUnmet "
        "detail carries the section 6 barrier clause and must keep matching it")


# ---------------------------------------------------------------------------
# 4. The census that has been stated short twice
# ---------------------------------------------------------------------------

def test_the_dict_or_list_tolerance_census_is_four_sites():
    """F-20, and the two amendments it has already needed.

    F-20 named two sites, both indexing `core_ids` on `core.json`. The 4c plan
    found a third, over the dispositions document's `rows`. Authoring this file
    found a FOURTH, over the audit document's `audited`, which belongs to stage
    G2 and so sits outside 4c's port entirely.

    The generalization is the SHAPE, not the artifact, and that is why the
    count kept moving: each reader looked at the artifact they were porting.
    Computing it removes the reader. A fifth site appearing is a narrowing
    decision somebody owes, not a detail.
    """
    census = _tolerance_census()
    expected = {
        ("check_audit", "audited"),
        ("check_dispositioned", "rows"),
        ("stage_F_core", "core_ids"),
        ("stage_G_disposition", "core_ids"),
    }
    assert census == expected, (
        f"the dict-or-list tolerance census is {sorted(census)}, expected "
        f"{sorted(expected)}. Each site is a place a bare list is accepted "
        "where a dict is meant; the port narrows them and a new one is a "
        "narrowing decision, not a detail.")


# ---------------------------------------------------------------------------
# 5. Two disclosures that only hold while nobody tidies them away
# ---------------------------------------------------------------------------

def test_the_driver_calls_regex_match_nowhere():
    """`REGEX-LOWER-1`: it typechecks, it verifies, and it does not build.

    Both pattern checks are hand-rolled from `string-char-at`, which reads like
    something a later reader would simplify back to the builtin. Doing so
    breaks the build, and the build is the tier that is unavailable exactly
    when this file is the only thing running.
    """
    callers = []
    for path in sorted(DRIVER_LL.glob("*.llmll")):
        if re.search(r"\(\s*regex-match\b", _uncommented(path)):
            callers.append(path.name)
    assert not callers, (
        f"{callers} call regex-match, which does not code-generate "
        "(REGEX-LOWER-1). Until that row ships, a pattern check here is "
        "hand-rolled and says so at the site.")


def test_no_cover_cell_claims_to_exercise_the_unreachable_overrun_halt():
    """`PROC-TIMEOUT-1` is open and D, F and G each invoke an agent.

    Three budget-overrun halts are therefore written and unreachable through
    the timeout. A cover cell whose description claimed one would be reporting
    coverage the run cannot have, which is the failure mode the whole cover
    exists to prevent, turned inward. `--timeout` appears in the cover's own
    process plumbing, which is not a claim and is not matched here.
    """
    tree = ast.parse(COVER.read_text(), filename=str(COVER))
    claims = []
    for n in ast.walk(tree):
        if not isinstance(n, ast.Call) or not isinstance(n.func, ast.Name):
            continue
        if n.func.id not in {"scenario", "local", "local4c"}:
            continue
        for a in n.args:
            if isinstance(a, ast.Constant) and isinstance(a.value, str) \
                    and re.search(r"\b(timeout|overrun|budget)\b", a.value, re.I):
                claims.append(a.value[:70])
    assert not claims, (
        f"a cover cell claims an overrun path: {claims}. PROC-TIMEOUT-1 is "
        "open, so no cell can exercise one and none may say it does.")
