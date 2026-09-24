"""VERIFY-HEADLINE-1: the `llmll verify` headline says what the SAFE verdict proved.

WHAT THE DEFECT WAS. Default `llmll verify` printed `✅ <file> — SAFE
(liquid-fixpoint)` on every solver pass. The verdict is about the emitted
constraint set, and a function that falls back from body-faithful verification
contributes its postcondition as an assumption. So the check mark appeared on
programs whose contracts were assumed, not proved
(docs/design/verify-headline-proposal.md).

THE RULE THE CELLS PIN. A function is CONTRACTED when it carries a postcondition
(after return-refinement folding). It is PROVED when it is body-faithful and
ASSUMED otherwise. On SAFE: all contracted functions proved gives the v0.26.0 line
byte for byte; one or more assumed gives the `⚠️` partial line and the
`--strict-verified-core` hint; no contracted function gives the `nothing proved`
line. The literal `SAFE (liquid-fixpoint)` stays on every line and the exit code
stays 0. `--json` gains `all_proved`, `proved_count`, `contracted_count` and
`assumed_fns`.

WHAT EACH CELL DID AGAINST THE PRE-CHANGE (v0.26.0) BINARY, measured.
VH-1 and VH-5 PASSED: the all-proved line and the exit code are unchanged by
design. VH-2, VH-3, VH-4 and VH-6 FAILED: each program printed the `✅` line and
the JSON carried none of the four fields.

WHY IT SKIPS WITHOUT A BINARY. Every cell calls `llmll verify`, which shells out
to liquid-fixpoint. The spec-roundtrip job runs this file with LLMLL_BIN set,
after the step that puts fixpoint on PATH. With no solver, verify exits 3 and
prints no headline, so the cells fail rather than pass vacuously.
"""

from __future__ import annotations

import json
import os
import shlex
import shutil
import subprocess
from pathlib import Path

import pytest

pytestmark = pytest.mark.skipif(
    not os.environ.get("LLMLL_BIN"),
    reason="set LLMLL_BIN to a built llmll; the spec-roundtrip job runs this in CI "
           "(the cells call `llmll verify`, which shells out to liquid-fixpoint)",
)

REPO = Path(__file__).resolve().parents[2]
CONSERVE = REPO / "examples" / "payments-core" / "conserve.llmll"

# One body-faithful contracted def (inc), one contracted def-shell whose
# non-linear body falls back (square), and one uncontracted def-shell (plumb)
# that falls back as `no-post` and must NOT be counted.
PARTIAL = """\
(def inc [x: int] -> int
  (post (= result (+ x 1)))
  (+ x 1))

(def-shell square [x: int] -> int
  (post (>= result 0))
  (* x x))

(def-shell plumb [x: int] -> int
  (inc x))
"""

# No function carries a postcondition.
PLAIN = """\
(def-shell add1 [x: int] -> int
  (+ x 1))
"""

# A hole body under a post is assumed, not proved.
HOLE = """\
(def inc [x: int] -> int
  (post (= result (+ x 1)))
  (+ x 1))

(def-shell hole-fn [x: int] -> int
  (post (>= result x))
  ?todo)
"""

SAFE_ALL = "✅ conserve.llmll — SAFE (liquid-fixpoint)"
PARTIAL_LINE = ("⚠️  partial.llmll — SAFE (liquid-fixpoint), partial: "
                "1 of 2 contracted functions proved; 1 assumed, not proved: square")
HINT_LINE = "   (--strict-verified-core fails on assumed functions)"
NOTHING_LINE = ("⚠️  plain.llmll — SAFE (liquid-fixpoint), nothing proved: "
                "no function carries a postcondition")


def _verify(workdir: Path, name: str, *, json_mode: bool = False):
    llmll = shlex.split(os.environ["LLMLL_BIN"])
    argv = [*llmll, *(["--json"] if json_mode else []), "verify", name]
    # The relative name is what the headline prints, so each cell runs in the
    # file's own directory.
    return subprocess.run(argv, cwd=workdir, capture_output=True, text=True,
                          encoding="utf-8", timeout=300)


def _headline(stdout: str) -> list[str]:
    """The SAFE line and the line after it (the hint, when there is one)."""
    lines = stdout.splitlines()
    for i, line in enumerate(lines):
        if "SAFE (liquid-fixpoint)" in line:
            return lines[i:i + 2]
    raise AssertionError("no SAFE (liquid-fixpoint) line in output:\n" + stdout)


def _json(stdout: str) -> dict:
    for line in reversed(stdout.strip().splitlines()):
        try:
            obj = json.loads(line)
        except ValueError:
            continue
        if "solver_verdict" in obj:
            return obj
    raise AssertionError("no verify report object in output:\n" + stdout)


@pytest.fixture
def work(tmp_path: Path) -> Path:
    shutil.copy(CONSERVE, tmp_path / "conserve.llmll")
    (tmp_path / "partial.llmll").write_text(PARTIAL)
    (tmp_path / "plain.llmll").write_text(PLAIN)
    (tmp_path / "hole.llmll").write_text(HOLE)
    return tmp_path


def test_vh1_all_proved_line_is_byte_identical(work: Path):
    """VH-1. Every contracted function proved: the v0.26.0 line, byte for byte."""
    r = _verify(work, "conserve.llmll")
    assert r.returncode == 0, r.stdout + r.stderr
    head = _headline(r.stdout)
    assert head[0] == SAFE_ALL, head
    assert "⚠" not in r.stdout
    assert "strict-verified-core" not in r.stdout


def test_vh2_partial_headline_names_the_assumed_function(work: Path):
    """VH-2. One proved, one assumed, one uncontracted: exact counts and names."""
    r = _verify(work, "partial.llmll")
    assert r.returncode == 0, r.stdout + r.stderr
    assert _headline(r.stdout) == [PARTIAL_LINE, HINT_LINE]
    assert "✅" not in r.stdout


def test_vh3_nothing_proved_line(work: Path):
    """VH-3. No function carries a postcondition: not presented as proved."""
    r = _verify(work, "plain.llmll")
    assert r.returncode == 0, r.stdout + r.stderr
    head = _headline(r.stdout)
    assert head[0] == NOTHING_LINE, head
    assert "✅" not in r.stdout


def test_vh4_json_fields(work: Path):
    """VH-4. The four additive fields, on all three headline cases."""
    want = {
        "conserve.llmll": (True, 1, 1, []),
        "partial.llmll": (False, 1, 2, ["square"]),
        "plain.llmll": (False, 0, 0, []),
    }
    for name, (all_proved, proved, contracted, assumed) in want.items():
        r = _verify(work, name, json_mode=True)
        assert r.returncode == 0, name + ": " + r.stdout + r.stderr
        obj = _json(r.stdout)
        # Additive only: the fields consumers already read keep their values.
        assert obj["success"] is True and obj["solver_verdict"] == "safe", obj
        got = (obj.get("all_proved"), obj.get("proved_count"),
               obj.get("contracted_count"), obj.get("assumed_fns"))
        assert got == (all_proved, proved, contracted, assumed), (name, got)


def test_vh5_exit_code_is_unchanged(work: Path):
    """VH-5. The headline changes; the exit code of a SAFE run does not."""
    for name in ("conserve.llmll", "partial.llmll", "plain.llmll", "hole.llmll"):
        r = _verify(work, name)
        assert r.returncode == 0, name + ": " + r.stdout + r.stderr
        assert "SAFE (liquid-fixpoint)" in r.stdout, name


def test_vh6_hole_body_under_a_post_is_assumed(work: Path):
    """VH-6. A hole is in `body-fallback` as `unfilled-hole`; under a post it is
    counted assumed, and the function without a post is not counted at all."""
    r = _verify(work, "hole.llmll")
    assert r.returncode == 0, r.stdout + r.stderr
    assert _headline(r.stdout)[0] == (
        "⚠️  hole.llmll — SAFE (liquid-fixpoint), partial: "
        "1 of 2 contracted functions proved; 1 assumed, not proved: hole-fn")
