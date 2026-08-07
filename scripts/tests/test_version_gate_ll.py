"""DRIFT-CI-1: the checks that do not need the LLMLL gate built.

`scripts/version_gate_cover.py` is the acceptance cover and it needs a
toolchain: it compares a compiled LLMLL binary against the shell script over
fourteen trees, and runs from `scripts/build_smoke.sh` stage 10. That is the
right home for every decision the gate makes, because only a run settles them.
It is the wrong home for everything below, each of which is a way the two
implementations drift apart with all fourteen cells still green.

WHAT A DIFFERENTIAL COVER CANNOT SEE. It compares the two gates on trees this
file's author thought to mutate. If a criterion is dropped from BOTH, or from
the shell script alone in a way no cell probes, the cover keeps agreeing. So
the checks here are about the criteria being PRESENT and the two sources
naming the same ones, rather than about what either answers.

Four things are settleable without a toolchain:

  * THE SEVEN INPUT FILES ARE THE SAME SEVEN. The cover copies exactly the
    files the gate reads into its scratch tree. If the LLMLL gate learned to
    read an eighth, a mutant of that file would be untestable there, and the
    cover would go on passing while the new criterion went uncovered;

  * BOTH IMPLEMENTATIONS CARRY ALL FOUR CRITERIA, by their C1..C4 tags. The
    tags are what the messages are keyed on and what the triage row names;

  * EVERY CRITERION MESSAGE IN THE SHELL SCRIPT HAS A COUNTERPART IN THE LLMLL
    SOURCE. This is the drift the cover is weakest against: a reworded shell
    message is caught by the cover only if some cell reaches it, and five of
    the shell's fourteen messages are extraction failures that need a
    malformed tree to fire;

  * THE COVER IS RUN BY THE BUILD GATE. 4c shipped a cover nothing invoked.
"""

from __future__ import annotations

import ast
import pathlib
import re

REPO = pathlib.Path(__file__).resolve().parents[2]
SHELL = REPO / "scripts" / "version_gate.sh"
LLMLL = REPO / "tools" / "version-gate" / "versiongate.llmll"
COVER = REPO / "scripts" / "version_gate_cover.py"
SMOKE = REPO / "scripts" / "build_smoke.sh"


def _uncommented(path: pathlib.Path) -> str:
    """LLMLL source with `;` comment tails removed, string literals respected.

    `versiongate.llmll` is more comment than code and its header quotes the
    criteria, so a raw search would find the prose and conclude the code is
    there. Same reasoning as `test_driver_ll_4e.py`.
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


def _llmll_literals() -> list[str]:
    """Every string literal in the LLMLL gate's code (not its comments)."""
    return re.findall(r'"((?:[^"\\]|\\.)*)"', _uncommented(LLMLL))


def _shell_messages() -> list[str]:
    """Every `fail "..."` message in the shell script, with $vars stripped.

    The shell interpolates values into its messages; the LLMLL port builds the
    same text with `string-concat-many`. Comparing the literal SEGMENTS around
    the interpolations is what makes the two comparable at all.
    """
    msgs = []
    for m in re.finditer(r'fail "((?:[^"\\]|\\.)*)"', SHELL.read_text()):
        msgs.append(m.group(1))
    return msgs


def test_the_cover_copies_exactly_the_files_the_gate_reads():
    """The scratch tree is the cover's whole world. A file the gate reads and
    the cover does not copy is a criterion no cell can mutate."""
    tree = ast.parse(COVER.read_text())
    inputs = None
    for node in ast.walk(tree):
        if (isinstance(node, ast.Assign)
                and any(getattr(t, "id", "") == "INPUTS" for t in node.targets)):
            inputs = {e.value for e in node.value.elts}  # type: ignore[attr-defined]
    assert inputs, "the cover no longer declares an INPUTS list"

    # Structurally, not by guessing which literals look like paths: every read
    # in the gate goes through `read-at`, so its arguments ARE the input set.
    # A heuristic over all literals picks up the message fragments that name
    # the same files ("compiler/package.yaml version") and reports them as
    # uncopied inputs.
    read = set(re.findall(r'\(read-at\s+\w+\s+"([^"]+)"\)', _uncommented(LLMLL)))
    assert read, "no `read-at` call sites found; the gate's read chain moved"
    missing = read - inputs
    assert not missing, (
        f"the LLMLL gate reads files the cover never copies, so no cell can "
        f"mutate them: {sorted(missing)}")


def test_both_implementations_carry_all_four_criteria():
    shell = SHELL.read_text()
    llmll = _uncommented(LLMLL)
    for tag in ("C1", "C2", "C3", "C4"):
        assert re.search(rf'"{tag} ', shell), f"{tag} is gone from the shell gate"
        assert any(lit.startswith(f"{tag} ") or lit == tag
                   for lit in _llmll_literals()), \
            f"{tag} is gone from the LLMLL gate"
        assert tag in llmll


def test_every_shell_criterion_message_has_an_llmll_counterpart():
    """The drift the differential cover is weakest against.

    A shell message only reachable on a malformed tree is compared by the cover
    only if some cell builds that tree; this asserts the text exists in both
    regardless. Matching is on the message's LITERAL SEGMENTS, since the shell
    interpolates with `$var` where the port concatenates.
    """
    lits = _llmll_literals()
    unmatched = []
    for msg in _shell_messages():
        # Split on BOTH the shell's interpolations and the punctuation that
        # straddles them, because the port assembles the same sentence from
        # separate pieces: `mismatch` supplies " (", ") != " and ")" while the
        # call site supplies the two labels. Comparing the punctuation-bearing
        # run (") != LLMLL.md banner (") finds nothing and says the criterion
        # is missing when it is present.
        runs = [s.strip() for s in re.split(r"\$\{?\w+\}?|[()!=]", msg)]
        # The criterion tag leads the message in the shell and is a SEPARATE
        # literal in the port (`mismatch "C1" "README.md banner" ...`), so a
        # run of "C1 README.md banner" matches nothing. The tags themselves are
        # covered by test_both_implementations_carry_all_four_criteria.
        runs = [re.sub(r"^C[1-4]\s+", "", s) for s in runs]
        runs = [s for s in runs if len(s) > 12]
        if not runs:
            continue
        longest = max(runs, key=len)
        if not any(longest in lit for lit in lits):
            unmatched.append((longest, msg))
    assert not unmatched, (
        "shell criterion messages with no counterpart in the LLMLL port:\n"
        + "\n".join(f"  {seg!r}  (from {msg!r})" for seg, msg in unmatched))


def test_the_cover_is_run_by_the_build_gate():
    smoke = SMOKE.read_text()
    assert "scripts/version_gate_cover.py" in smoke, \
        "build_smoke.sh does not run the version-gate cover"
    assert "--gate" in smoke, \
        "the gate is invoked without the binary it needs"


def test_the_shell_gate_is_still_the_one_the_fast_job_runs():
    """The port does not replace the shell script, and that is a property of
    the workflow rather than a preference: version-gate.yml has no Stack and no
    GHC, so a compiled binary there would trade a fast gate for a slow one. If
    this assertion ever fails, the decision was reversed and the LLMLL gate's
    header is stale."""
    wf = (REPO / ".github" / "workflows" / "version-gate.yml").read_text()
    assert "bash scripts/version_gate.sh" in wf, \
        "the fast job no longer runs the shell gate"
    assert "haskell-actions/setup" not in wf.split("spec-roundtrip")[0], \
        "the fast job acquired a Haskell toolchain, so the split this port " \
        "was designed around no longer holds"
