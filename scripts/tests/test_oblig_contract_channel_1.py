"""OBLIG-D4 / OBLIG-CH end to end: `llmll verify --obligation-report`.

WHAT WAS MISSING. Only a hole obligation carried a `contract_channel`. A
contract obligation (the function's own post, refuted) and a precondition
obligation (a callee's pre at one call site) carried `kind`, `origin`,
`backing` and `status` and nothing an agent could act on: not the goal, not
the hypotheses, not the fragment. And two calls to one callee from one body
produced two obligations with the SAME `id` and the SAME `origin`, so an agent
could not tell which call site it had been handed.

WHAT THESE CELLS PIN. Presence on the two kinds that have a goal, absence on
the one that does not, the POLARITY of a precondition obligation's goal (the
CALLEE's pre, instantiated at this call, never the caller's post), and the
distinctness of two sibling call-site ids. The compiler-side unit tests cover
the assemblers directly; these run the real CLI, because the id is minted in
the emitter and read back in the report and only an end-to-end run crosses
that seam.

A TERMINATION OBLIGATION IS THE NEGATIVE CONTROL. It proves a measure
descends. It has no contract goal, so a channel on it would be fabricated.
The cell fails if one appears.

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

# `shrink` is refuted (x-1 is not > x), so its contract obligation is surfaced.
# `spin` declares a measure that does not descend, so its termination
# obligation is surfaced on the same run. One verify, both kinds.
REFUTED_SRC = """\
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

# The banking_ledger shape: two calls to one callee from one body, the second
# through a let-bound result. This is the pair whose ids collided.
TWO_CALL_SRC = """\
(def-shell withdraw [balance: int amount: int]
  (pre  (and (>= balance amount) (>= amount 0)))
  (post (and (= result (- balance amount)) (>= result 0)))
  (- balance amount))

(def-shell withdraw-twice [balance: int first: int second: int]
  (pre  (and (>= balance (+ first second)) (and (>= first 0) (>= second 0))))
  (post (and (= result (- (- balance first) second)) (>= result 0)))
  (let [[after-first (withdraw balance first)]]
    (withdraw after-first second)))
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
def refuted_report(tmp_path_factory) -> dict:
    return _report(tmp_path_factory.mktemp("oblig-ch-refuted"), REFUTED_SRC, "refuted.llmll")


@pytest.fixture(scope="module")
def two_call_report(tmp_path_factory) -> dict:
    return _report(tmp_path_factory.mktemp("oblig-ch-twocall"), TWO_CALL_SRC, "twocall.llmll")


def _of_kind(report: dict, kind: str) -> list[dict]:
    return [o for o in report["obligations"] if o["kind"] == kind]


def test_schema_version_is_bumped(refuted_report):
    """The channel and the site segment are additive, so the minor moves."""
    assert refuted_report["schema_version"] == "0.12.4"


def test_a_contract_obligation_carries_its_own_goal_and_its_own_pre(refuted_report):
    """Cell 1: presence, and the right polarity for a contract obligation."""
    obls = _of_kind(refuted_report, "contract-obligation")
    assert obls, refuted_report["obligations"]
    shrink = [o for o in obls if o["function"] == "shrink"]
    assert shrink, obls
    ch = shrink[0].get("contract_channel")
    assert ch is not None, shrink[0]
    assert ch["postcondition_goal"] == "(> result x)", ch
    assert ch["preconditions"] == ["(>= x 0)"], ch
    # A refuted body-faithful function: the fragment channel says so.
    assert ch["body_fragment"] == "qf_lia", ch
    assert ch["body_faithful_possible"] is True, ch


def test_a_termination_obligation_carries_no_contract_channel(refuted_report):
    """NEGATIVE CONTROL: no goal exists, so no channel may be invented."""
    obls = _of_kind(refuted_report, "termination-obligation")
    assert obls, refuted_report["obligations"]
    for o in obls:
        assert "contract_channel" not in o, o


def test_sibling_call_sites_get_distinct_ids(two_call_report):
    """Cell 3: the D4 collision. Both obligations still name the same origin
    pointer (it points at the enclosing body, by design), so the id is the
    only thing that can tell them apart."""
    pre = [o for o in _of_kind(two_call_report, "precondition-obligation")
           if o["function"] == "withdraw-twice"]
    assert len(pre) == 2, two_call_report["obligations"]
    assert len({o["origin"] for o in pre}) == 1, pre
    assert len({o["id"] for o in pre}) == 2, [o["id"] for o in pre]


def test_each_call_site_goal_is_the_callee_pre_at_that_call(two_call_report):
    """Cell 4: the POLARITY that makes the channel worth having. The goal is
    the CALLEE's precondition instantiated with THIS call's arguments, so the
    two siblings read differently; the caller's own pre is the hypothesis."""
    pre = [o for o in _of_kind(two_call_report, "precondition-obligation")
           if o["function"] == "withdraw-twice"]
    goals = {o["contract_channel"]["postcondition_goal"] for o in pre}
    assert goals == {
        "(and (>= balance first) (>= first 0))",
        "(and (>= after-first second) (>= second 0))",
    }, goals
    caller_pre = "(and (>= balance (+ first second)) (and (>= first 0) (>= second 0)))"
    for o in pre:
        assert o["contract_channel"]["preconditions"] == [caller_pre], o
