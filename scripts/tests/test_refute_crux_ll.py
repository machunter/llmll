"""TOOL-RFC-002: the cover's corpus is the port's corpus.

WHY THIS FILE IS NEW AND ITS NAME IS OLD. `scripts/refute_crux_cover.py` has
declared, since it was written, that this file asserts its `FAMILIES` list
against the port rather than trusting it, on `version_gate_cover.py`'s precedent.
The precedent is real: `test_version_gate_ll.py` parses that cover's `INPUTS`
list and checks it against the LLMLL gate's own `read-at` call sites. This file
was not. A comment named a guard, the guard was never built, and the claim went
unchecked for the ten days the cover has existed.

WHAT DRIFT COSTS HERE. `FAMILIES` is the cover's whole world: `prepare()` copies
exactly those directories into the scratch tree, and every cell mutates inside
one of them. A suite added to the port's `families` and not to the cover is
copied by no cell, mutated by no cell, and untested by all sixteen, while the
cover goes on reporting `16 cells, 3 negative controls`. The drift is invisible
at exactly the moment it happens, which is why it needs an assertion and not a
convention.

ORDER IS ASSERTED, NOT ONLY MEMBERSHIP. The port walks its suites in list order
and the cover's `find_case` searches `FAMILIES` in list order to pick the case a
cell mutates. Two lists holding the same twelve entries in different orders would
send a cell at a different case than the one its name claims, so a set comparison
would pass while the battery tested something other than what it says.

ONE SOURCE AND NOT TWO, as of the 2026-08-17 retirement. The cover's comment said
BOTH sources, meaning the port and `scripts/refute-crux-gate.sh`, whose FAMILIES
array was the second. That file is deleted, so half of the check named here is
gone with it and this file checks what remains.
"""

from __future__ import annotations

import ast
import pathlib
import re

REPO = pathlib.Path(__file__).resolve().parents[2]
LLMLL = REPO / "tools" / "refute-crux" / "refutecrux.llmll"
COVER = REPO / "scripts" / "refute_crux_cover.py"


def _uncommented(p: pathlib.Path) -> str:
    """The module with `;;` comments removed.

    Without this, a suite path quoted in a comment counts as a list member. The
    port's header quotes several while explaining what the corpus is.
    """
    out = []
    for line in p.read_text(encoding="utf-8").splitlines():
        i = line.find(";;")
        out.append(line if i < 0 else line[:i])
    return "\n".join(out)


def _cover_families() -> list[str]:
    """The cover's FAMILIES, read structurally rather than by regex.

    `ast.parse` and not a line scan, on the 001 precedent: the list is followed
    by other string literals in the same file, and a regex over quoted strings
    picks up CASE_SUITES and the manifest name too.
    """
    tree = ast.parse(COVER.read_text(encoding="utf-8"))
    for node in ast.walk(tree):
        if (isinstance(node, ast.Assign)
                and any(getattr(t, "id", "") == "FAMILIES" for t in node.targets)):
            return [e.value for e in node.value.elts]  # type: ignore[attr-defined]
    raise AssertionError("the cover no longer declares a FAMILIES list")


def _port_families() -> list[str]:
    """The port's `families`, from the body of that def and nothing else."""
    src = _uncommented(LLMLL)
    m = re.search(r"\(def-shell\s+families\s*\[\]\s*->\s*list\[string\]\s*\[(.*?)\]\)",
                  src, re.S)
    assert m, "no `(def-shell families [] -> list[string] [...])` in the port"
    return re.findall(r'"([^"]+)"', m.group(1))


def test_the_cover_grades_the_suites_the_port_runs():
    port = _port_families()
    cover = _cover_families()

    assert port, "the port's `families` list came back empty; its shape moved"

    # Reported as three separate facts rather than one equality, because the
    # three failures want three different fixes: add a suite to the cover, drop
    # one from it, or reorder.
    missing = [f for f in port if f not in cover]
    extra = [f for f in cover if f not in port]
    assert not missing, (
        f"the port grades suites the cover never copies, so no cell can mutate "
        f"them: {missing}")
    assert not extra, (
        f"the cover copies suites the port does not grade; every cell wastes a "
        f"copy and `find_case` can select a case the port never reaches: {extra}")
    assert port == cover, (
        f"same suites, different ORDER. `find_case` walks FAMILIES in order to "
        f"choose the case a cell mutates, so a cell would mutate a different "
        f"case than its name claims.\n  port : {port}\n  cover: {cover}")


def test_every_named_suite_carries_a_manifest():
    """A suite in the list with no EXPECTED_VERDICTS.json is a `not found`
    failure in every cell, which drowns the signal the cells exist to give.
    Cell 10 deletes a manifest deliberately; this asserts the other eleven start
    from a tree where that mutation means something."""
    for fam in _port_families():
        assert (REPO / fam / "EXPECTED_VERDICTS.json").is_file(), (
            f"{fam} is in the port's `families` but has no EXPECTED_VERDICTS.json")
