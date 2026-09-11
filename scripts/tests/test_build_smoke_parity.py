"""BUILD-GATE-1: the reference and its LLMLL port must print the same verdicts.

WHY THIS FILE EXISTS, and it is a defect this repository shipped rather than a
hazard someone imagined. On 2026-09-11 program unification job (a2) changed
`scripts/build_smoke.sh` stage 9 to build the sequencer instead of the wave, and
left `tools/build-smoke/buildsmoke.llmll` saying the old thing. `main` went red.

The miss is structural and will recur. Every TOOL-LL gate is THREE artifacts: a
reference, an LLMLL port of it, and a differential cover that runs both and
compares. `scripts/build_smoke_cover.py` is that cover and it does catch this,
which is how the defect was found. What it cannot do is catch it CHEAPLY: it
builds both sides and ran for 16m43s on CI, in the opt-in C5 job. The 31-second
job that runs on every push saw nothing, because no test in this directory so
much as named `buildsmoke.llmll`.

So this file is the fast half of that gate and NOT a replacement for the cover.
It compares SOURCE TEXT and settles one question: do the two sides' verdict
lines say the same words. It cannot tell whether they FIRE at the same time,
which is what the cover is for and why the cover keeps running.

THE EXCEPTION LIST IS NOT WRITTEN HERE. Two verdict lines legitimately differ
and `EXPECTED_DIVERGENCES` in the cover names both, with the reason each is
tolerated. This file imports that list rather than restating it, because a
second copy is a second thing to update and the whole subject of this file is
what happens when one copy of a fact moves and another does not.
"""

from __future__ import annotations

import importlib.util
import pathlib
import re
import sys

REPO = pathlib.Path(__file__).resolve().parents[2]
SMOKE = REPO / "scripts" / "build_smoke.sh"
PORT = REPO / "tools" / "build-smoke" / "buildsmoke.llmll"
COVER = REPO / "scripts" / "build_smoke_cover.py"


def _load(path: pathlib.Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


cover = _load(COVER, "build_smoke_cover")


def _reference_verdicts() -> list[str]:
    """The text of every `BUILD-GATE-1 PASS:` line the shell can print."""
    return re.findall(r'"BUILD-GATE-1 PASS: ([^"]*)"', SMOKE.read_text())


def _port_verdicts() -> list[str]:
    """The same, from the port. `pass-line` prepends the common prefix."""
    return re.findall(r'\(pass-line "([^"]*)"\)', PORT.read_text())


def _tolerated_marks() -> list[str]:
    """Both halves of every divergence the cover names.

    `ref_mark` and `port_mark` are SUBSTRINGS the respective line must still
    carry, not whole lines, so this matches by containment. Either may be empty
    for a stage only one side has; an empty mark is dropped, because "" is
    contained in everything and would excuse the whole file.
    """
    return [m for e in cover.EXPECTED_DIVERGENCES
            for m in (e.ref_mark, e.port_mark) if m]


def _tolerated(line: str) -> bool:
    return any(m in line for m in _tolerated_marks())


def _as_pattern(reference_line: str) -> re.Pattern[str]:
    """A reference line with its shell expansions turned into wildcards.

    `${#MISSING[@]} missing preamble definitions` becomes a number when the
    shell runs it, and the port writes the number directly. Comparing the source
    texts reports the two as different words for the same sentence, so the
    expansion matches anything and the rest must still match exactly.

    SYMMETRIC ON PURPOSE. An earlier version filtered only the side carrying the
    `${`, which excused the reference's line and then reported the port's as
    port-only. One line, two verdicts, and neither of them true.
    """
    return re.compile("".join(
        ".*" if part.startswith("${") else re.escape(part)
        for part in re.split(r"(\$\{[^}]*\})", reference_line)) + "$")


def _matches_any(line: str, reference_lines: list[str]) -> bool:
    return any(_as_pattern(r).match(line) for r in reference_lines)


def test_the_cover_still_exposes_the_list_this_file_imports():
    """A guard on the import, not on the gate.

    If `EXPECTED_DIVERGENCES` is renamed or emptied, every assertion below gets
    quietly stricter or quietly weaker, and the failure would read as a parity
    defect rather than as this file losing its footing.
    """
    assert hasattr(cover, "EXPECTED_DIVERGENCES"), \
        "build_smoke_cover.py no longer exposes EXPECTED_DIVERGENCES"
    assert cover.EXPECTED_DIVERGENCES, \
        "EXPECTED_DIVERGENCES is empty; either the ports converged or the list moved"
    for e in cover.EXPECTED_DIVERGENCES:
        assert e.ref_mark or e.port_mark, f"a divergence names neither side: {e}"
    assert _tolerated_marks(), "every divergence carries empty marks, so nothing is excused"


def test_every_verdict_line_the_reference_prints_exists_in_the_port():
    """The direction that catches a reference edit landing alone.

    That is the 2026-09-11 defect exactly: stage 9's banner went from seven
    cells to nine in the shell and stayed at seven in the port.
    """
    port = _port_verdicts()
    missing = [v for v in _reference_verdicts()
               if not _tolerated(v)
               and not any(_as_pattern(v).match(p) for p in port)]
    assert not missing, (
        "the reference prints verdict lines the port does not:\n  "
        + "\n  ".join(missing)
        + "\n\nEither port the change into tools/build-smoke/buildsmoke.llmll, or "
          "add an entry to EXPECTED_DIVERGENCES in scripts/build_smoke_cover.py "
          "saying why the two sides differ.")


def test_every_verdict_line_the_port_prints_exists_in_the_reference():
    """The opposite direction, and it is not symmetric decoration.

    A port that grows a verdict the reference never prints is a port that has
    stopped being a port. The cover reports that as a port-only stage and
    tolerates it only when EXPECTED_DIVERGENCES says so.
    """
    ref = _reference_verdicts()
    extra = [v for v in _port_verdicts()
             if not _tolerated(v) and not _matches_any(v, ref)]
    assert not extra, (
        "the port prints verdict lines the reference does not:\n  "
        + "\n  ".join(extra)
        + "\n\nEither the reference is missing the change, or EXPECTED_DIVERGENCES "
          "owes an entry naming this as port-only.")


def test_stage_nine_builds_the_driver_on_both_sides():
    """The specific pin for what broke, kept beside the general check.

    The general assertions above compare VERDICT text. They would still pass if
    both sides printed `9 cells` while one of them built the wrong program, and
    the wave has had no `def-main` since job (a2), so building `wave.llmll` here
    produces a library and no binary at all.
    """
    smoke = SMOKE.read_text()
    port = PORT.read_text()
    assert 'build sequencer.llmll -o "$WAVE_OUTDIR"' in smoke, \
        "build_smoke.sh stage 9 no longer builds the driver program"
    assert '["build" "sequencer.llmll" "-o" (w-out-of (get-s b "work"))]' in port, \
        "the port's stage 9 no longer builds the driver program"
    assert "exe_path \"$WAVE_OUTDIR\" 'sequencer'" in smoke, \
        "build_smoke.sh stage 9 resolves a binary that is not the driver"
    # FLAG-QUALIFIED, because stage 8's driver cover resolves the same binary
    # and an unqualified search finds its occurrence instead. A mutation control
    # caught this: `--wave .../bin/wave` passed the bare check.
    assert '"--wave" (string-concat sir "/bin/sequencer")' in port, \
        "the port's stage 9 resolves a binary that is not the driver"
