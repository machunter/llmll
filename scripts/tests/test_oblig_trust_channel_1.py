"""TRUST-CH-HOLE-1 / OBLIG-BRANCH-PC end to end: `llmll verify --obligation-report`.

WHAT WAS MISSING. Three things, all of them fields the report already had a
place for.

`trust_channel.assumptions` shipped as a hardcoded empty array for sixteen
versions. The data sat one record away the whole time: TRUST-AXIOM fills
`teBuiltinAxioms`, `teInheritedAxioms` and `teGroundFacts` on the same trust
entry the assembler was already reading the tier off. A reader asking what a
function's evidence rests on got `[]` from a body rooted in a sealed builtin.

The channel reached only a hole obligation. A contract obligation and a
precondition obligation describe a function's own evidence just as directly,
and carried no channel at all.

A branch obligation emitted four keys and neither of the two `oblig-0-spec.md`
§6.2 has specified since Rev 1: `path_condition` and `postcondition_goal`.

WHAT THESE CELLS PIN. A POSITIVE WITNESS with its NEGATIVE CONTROL, in that
order, for each: a bytes-rooted body names the axiom it rests on, and a
bytes-free body's array is EMPTY; the two kinds that describe a function's own
evidence carry the channel, and the two that do not carry none. An empty array
passes any cell that only asks whether the key is present, so neither half is
worth anything alone.

On macOS a toolchain SDK mismatch makes the link step fail. MacOSX27.0.sdk
ships .tbd files the linker rejects; export SDKROOT to MacOSX26.5.sdk before
running these locally. The environment is inherited by the child.
"""

from __future__ import annotations

import json
import os
import shlex
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]

# A verify run invokes liquid-fixpoint. Generous relative to the work.
VERIFY_TIMEOUT_S = 300


def _resolve_llmll() -> list[str] | None:
    """LLMLL_BIN when the caller set it (CI does), else the local Stack
    install root. Never the repo-root binary: that one goes stale and a gate
    has read green against a months-old compiler because of it."""
    env = os.environ.get("LLMLL_BIN")
    if env:
        return shlex.split(env)
    compiler = REPO_ROOT / "compiler"
    try:
        p = subprocess.run(
            ["stack", "path", "--local-install-root"],
            capture_output=True, text=True, cwd=str(compiler), timeout=120,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if p.returncode != 0:
        return None
    exe = Path(p.stdout.strip()) / "bin" / "llmll"
    return [str(exe)] if exe.is_file() else None


LLMLL = _resolve_llmll()

pytestmark = pytest.mark.skipif(
    LLMLL is None,
    reason="no built llmll; set LLMLL_BIN or build compiler/ (CI's spec-roundtrip job does)",
)

# examples/bytes-bounds/read-at-off-by-one.llmll, self-contained: the bound is
# written (<= i 64), so the index-in-bounds pre of `bytes-get` is REFUTED and
# the call's precondition obligation is surfaced. The body rests on the
# bytes-get reflection axiom either way, which is the point of the cell.
BYTES_READ_SRC = """\
(def read-at [b: bytes[64] i: int] -> int
  (pre  (and (>= i 0) (<= i 64)))
  (post (and (>= result 0) (<= result 255)))
  (bytes-get b i))
"""

# examples/bytes-bounds/write-overflow.llmll, self-contained. `bytes-set` is
# the builtin whose assumed post is a CONJUNCTION of two different kinds of
# claim, so it is the one that shows the split.
BYTES_WRITE_SRC = """\
(def write-at [b: bytes[64] i: int v: int] -> bytes[64]
  (pre  (and (>= i 0) (and (< i 64) (and (>= v 0) (<= v 300)))))
  (post (= (bytes-length result) 64))
  (bytes-set b i v))
"""

# The NEGATIVE CONTROL's source, and the termination obligation's. `shrink` is
# refuted (x-1 is not > x) and touches no bytes and no map; `spin` declares a
# measure that does not descend.
ARITH_SRC = """\
(def-shell shrink [x: int] -> int
  (pre  (>= x 0))
  (post (> result x))
  (- x 1))

(def-shell spin [x: int] -> int
  (pre  (>= x 0))
  (post (= result x))
  (decreases x)
  (spin x))
"""

# A hole inside a match: one hole obligation, two branch obligations under it.
BRANCH_SRC = """\
(def-shell pick [r: Result[int, int]] -> int
  (post (>= result 0))
  (match r ((Success s) ?fill) ((Error e) 0)))
"""


def _report(workdir: Path, src: str, name: str) -> dict:
    """Verify a program in a PRIVATE directory and return the report.

    `llmll verify` writes a `.verified.json` sidecar beside the program, so
    nothing here may run against a file in the working tree. The report is one
    JSON object on stdout, preceded by human progress lines.
    """
    prog = workdir / name
    prog.write_text(src, encoding="utf-8")
    p = subprocess.run(
        [*LLMLL, "verify", str(prog), "--obligation-report"],
        capture_output=True, text=True, timeout=VERIFY_TIMEOUT_S, cwd=str(workdir),
    )
    # The exit status tracks the VERDICT (a refuted program exits non-zero);
    # the report is emitted either way, so the status is not asserted here.
    line = next(
        (l for l in p.stdout.splitlines()
         if l.lstrip().startswith("{") and '"schema_version"' in l),
        None,
    )
    assert line is not None, (
        f"no obligation-report JSON on stdout\n"
        f"rc={p.returncode}\nstdout={p.stdout[-3000:]}\nstderr={p.stderr[-2000:]}"
    )
    return json.loads(line.strip())


@pytest.fixture(scope="module")
def bytes_read_report(tmp_path_factory) -> dict:
    return _report(tmp_path_factory.mktemp("trust-ch-read"), BYTES_READ_SRC, "read.llmll")


@pytest.fixture(scope="module")
def bytes_write_report(tmp_path_factory) -> dict:
    return _report(tmp_path_factory.mktemp("trust-ch-write"), BYTES_WRITE_SRC, "write.llmll")


@pytest.fixture(scope="module")
def arith_report(tmp_path_factory) -> dict:
    return _report(tmp_path_factory.mktemp("trust-ch-arith"), ARITH_SRC, "arith.llmll")


@pytest.fixture(scope="module")
def branch_report(tmp_path_factory) -> dict:
    return _report(tmp_path_factory.mktemp("trust-ch-branch"), BRANCH_SRC, "branch.llmll")


def _of_kind(report: dict, kind: str) -> list[dict]:
    return [o for o in report["obligations"] if o["kind"] == kind]


def _assumptions(report: dict) -> list[dict]:
    return [a for o in report["obligations"]
            for a in o.get("trust_channel", {}).get("assumptions", [])]


def test_a_sealed_builtin_body_names_the_axiom_it_rests_on(bytes_read_report):
    """THE POSITIVE WITNESS. `bytes-get` reflects into the array theory by
    ASSUMPTION, on the codegen stamp. The obligation now says which builtin and
    which predicate, instead of an empty array."""
    rows = [a for a in _assumptions(bytes_read_report) if a["kind"] == "builtin-axiom"]
    assert rows, bytes_read_report["obligations"]
    assert [r["builtin"] for r in rows] == ["bytes-get"], rows
    assert "Map_select" in rows[0]["predicate"], rows[0]
    # the stamp the axiom rides is named, not implied
    assert rows[0]["stamp"] == "codegen_semantics_version", rows[0]
    assert rows[0]["category"] == "codegen-determined", rows[0]


def test_a_bytes_free_body_carries_an_empty_assumptions_array(arith_report):
    """THE NEGATIVE CONTROL. Same assembler, same run shape, a body with no
    bytes and no map operation. Without this cell the one above cannot tell a
    disclosure from a constant."""
    obls = [o for o in arith_report["obligations"] if "trust_channel" in o]
    assert obls, arith_report["obligations"]
    for o in obls:
        assert o["trust_channel"]["assumptions"] == [], o


def test_the_two_kinds_that_own_evidence_carry_a_trust_channel(
    arith_report, bytes_read_report
):
    """A contract obligation proves the function's own post; a precondition
    obligation is the CALLER's job at one call site. Both are claims about a
    function's own evidence, so both carry the channel."""
    contract = _of_kind(arith_report, "contract-obligation")
    assert contract, arith_report["obligations"]
    for o in contract:
        assert "trust_channel" in o, o
        assert set(o["trust_channel"]) >= {"assumptions", "effective_level", "body_faithful"}, o

    pre = _of_kind(bytes_read_report, "precondition-obligation")
    assert pre, bytes_read_report["obligations"]
    for o in pre:
        assert "trust_channel" in o, o
        # the channel describes the CALLER, whose body has to establish the pre
        assert o["function"] == "read-at", o


def test_termination_and_branch_obligations_carry_no_trust_channel(
    arith_report, branch_report
):
    """NEGATIVE CONTROL for the widening. A termination obligation proves a
    measure descends and a branch obligation is a sub-goal of a hole; neither
    is a claim about a function's own evidence, so neither may grow one."""
    terms = _of_kind(arith_report, "termination-obligation")
    assert terms, arith_report["obligations"]
    for o in terms:
        assert "trust_channel" not in o, o

    branches = _of_kind(branch_report, "branch-obligation")
    assert branches, branch_report["obligations"]
    for o in branches:
        assert "trust_channel" not in o, o


def test_bytes_set_splits_its_post_into_a_reflection_and_a_lemma(bytes_write_report):
    """Professor finding 4. `bytes-set`'s assumed post is the store equality
    AND a length-preservation fact. The first DEFINES the write in the array
    theory; the second is a theorem about it that the theory does not give you.
    Merged into one string a reader cannot tell them apart."""
    rows = [a for a in _assumptions(bytes_write_report)
            if a["kind"] == "builtin-axiom" and a["builtin"] == "bytes-set"]
    assert rows, bytes_write_report["obligations"]
    conj = rows[0]["conjuncts"]
    assert [c["tag"] for c in conj] == ["reflection", "lemma"], conj
    assert "Map_store" in conj[0]["predicate"], conj
    assert "bytesLen" in conj[1]["predicate"], conj
    # the merged field is UNCHANGED, so a reader of the older key sees no break
    assert conj[0]["predicate"] in rows[0]["predicate"], rows[0]
    assert conj[1]["predicate"] in rows[0]["predicate"], rows[0]


def test_a_branch_obligation_carries_its_arm_guard_and_the_parent_goal(branch_report):
    """oblig-0-spec.md §6.2's two missing fields. The `path_condition` is the
    ARM's own constructor guard — one structural entry, not the parent's
    accumulated guard set — and the goal is the enclosing function's post, the
    same string the parent hole obligation carries."""
    branches = _of_kind(branch_report, "branch-obligation")
    assert len(branches) == 2, branch_report["obligations"]

    holes = _of_kind(branch_report, "hole-obligation")
    assert holes, branch_report["obligations"]
    parent_goal = holes[0]["contract_channel"]["postcondition_goal"]

    for o in branches:
        pc = o["path_condition"]
        assert len(pc) == 1, o
        assert pc[0]["kind"] == "structural", o
        # built from the constructor AND the scrutinee, per §6.2's sample
        assert pc[0]["guard"] == f"(match-{o['constructor']} r)", o
        assert o["postcondition_goal"] == parent_goal, (o, parent_goal)

    assert {o["path_condition"][0]["guard"] for o in branches} == {
        "(match-Success r)",
        "(match-Error r)",
    }


def test_the_branch_fields_are_top_level_not_a_channel(branch_report):
    """§6.2 puts both on the branch object itself. A branch obligation carries
    no channel (spec §2.3), so folding them into one would have invented a
    channel the matrix says it does not have."""
    for o in _of_kind(branch_report, "branch-obligation"):
        assert "path_condition" in o, o
        assert "postcondition_goal" in o, o
        assert "contract_channel" not in o, o
