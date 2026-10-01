"""EVAL-STRICT-1: built programs evaluate call-by-value (LLMLL.md §4).

The design record is docs/design/eval-strict-1-proposal.md (Rev 2). Its edge
cases are the fixtures under scripts/tests/fixtures/eval_strict/, and the three
that stand under LLMLL.md NC-001 are scripts/doc-claims/cbv-*.llmll, which
DRIFT-CT-2 runs.

WHAT A PASS HERE MEANS. Each cell builds one program with $LLMLL_BIN and runs
it. Every cell except two was run against the v0.26.17 compiler, before the
patch, and failed: the program returned a value where call-by-value fails, or
exited 1 where it does not terminate. The two exceptions (edge case 2 and the
bare-reference call) pass on v0.26.17 as well and say so in their docstrings.

Failures are made to fail with a message rather than diverge wherever the
proposal allows it, because a message can be graded and a divergence can only
be timed. The two divergence cells (edge cases 1 and 2) are timed.
"""

import glob
import os
import shlex
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURES = REPO_ROOT / "scripts" / "tests" / "fixtures" / "eval_strict"

pytestmark = pytest.mark.skipif(
    not os.environ.get("LLMLL_BIN"),
    reason="set LLMLL_BIN to a built llmll; the spec-roundtrip job runs this in CI",
)

# A build plus a run, and the build dominates.
BUILD_TIMEOUT_S = 600

# The built program alone. Every terminating fixture answers in well under a
# second; the two divergence cells must still be running at this point.
RUN_TIMEOUT_S = 10


def _llmll() -> list[str]:
    return shlex.split(os.environ["LLMLL_BIN"])


def _build(name: str, out: Path) -> str:
    src = FIXTURES / f"{name}.llmll"
    p = subprocess.run(
        [*_llmll(), "build", str(src), "-o", str(out)],
        capture_output=True, text=True, timeout=BUILD_TIMEOUT_S, cwd=str(REPO_ROOT),
    )
    assert p.returncode == 0, f"llmll build {name} failed rc={p.returncode}\n{p.stderr[-2000:]}"
    exes = glob.glob(str(out / ".stack-work" / "install" / "*" / "*" / "*" / "bin" / "*"))
    assert len(exes) == 1, f"expected one executable under {out}, found {exes}"
    return exes[0]


def _run(exe: str) -> subprocess.CompletedProcess:
    # One stdin line: every fixture does its work in :init, before any step.
    return subprocess.run([exe], input="x\n", capture_output=True, text=True,
                          timeout=RUN_TIMEOUT_S)


@pytest.fixture(scope="module")
def build(tmp_path_factory):
    cache: dict[str, str] = {}

    def _get(name: str) -> str:
        if name not in cache:
            cache[name] = _build(name, tmp_path_factory.mktemp(name))
        return cache[name]
    return _get


# ---------------------------------------------------------------- fails --

FAILS = [
    # (fixture, message, what lazy code generation did instead)
    ("e4_hole_binding", "hole: todo", "printed 0"),
    ("e11_do_named_unread", "cannot parse 'bad-do'", "printed done"),
    ("inv_list_map", "cannot parse 'bad-map'", "printed 2"),
    ("inv_map_value", "cannot parse 'bad-mapval'", "printed true"),
    ("inv_string", "cannot parse 'bad-str'", "printed false"),
    ("inv_list_fold", "cannot parse 'bad-fold'", "printed 3"),
]


@pytest.mark.parametrize("name,message,lazy", FAILS, ids=[f[0] for f in FAILS])
def test_es_value_is_evaluated_and_fails(build, name, message, lazy):
    """A value call-by-value evaluates fails, although nothing reads it."""
    p = _run(build(name))
    assert p.returncode != 0 and message in p.stderr, (
        f"{name}: expected a failure naming {message!r}; got rc={p.returncode}, "
        f"stdout={p.stdout!r}, stderr={p.stderr[-300:]!r}. Lazy code {lazy}."
    )


def test_es_bare_reference_is_called_through_a_binding(build):
    """Edge case 13, second half. A REGRESSION GUARD: v0.26.17 fails here too.

    It guards the new `k ()` form: `(g)`, where g is bound to a zero-parameter
    definition, must call it. A codegen that emitted `g` alone would not build.
    """
    p = _run(build("e13_bare_call"))
    assert p.returncode != 0 and "cannot parse 'bad-call'" in p.stderr, (
        f"got rc={p.returncode}, stderr={p.stderr[-300:]!r}"
    )


# ------------------------------------------------------------ terminates --

@pytest.fixture(scope="module")
def values_out(build) -> str:
    p = _run(build("values"))
    assert p.returncode == 0, f"values: rc={p.returncode}, stderr={p.stderr[-500:]!r}"
    return p.stdout


@pytest.mark.parametrize("token,why", [
    ("E5=true", "edge case 5: => does not evaluate its right operand when the left is false"),
    ("E9=0", "edge case 9: a closure that fails when applied is not applied"),
    ("E13A=0", "edge case 13: a bare reference to a failing definition evaluates nothing"),
    ("REBIND=2", "a later let binding may reuse an earlier name; v0.26.17 did not build this"),
    ("ZP=32", "a zero-parameter function called directly and through a binding"),
])
def test_es_terminating_cells(values_out, token, why):
    assert token in values_out, f"expected {token} ({why}); got {values_out!r}"


# ------------------------------------------------------------- diverges --

def test_es_e1_unread_binding_is_evaluated(build):
    """Edge case 1, the proposal's section 2 probe. Lazy code exits 1 at once."""
    exe = build("e1_unread_binding")
    try:
        p = _run(exe)
    except subprocess.TimeoutExpired:
        return
    pytest.fail(f"expected no termination; got rc={p.returncode}, stderr={p.stderr[-300:]!r}")


def test_es_e2_either_failure_conforms(build):
    """Edge case 2. Argument order is unspecified: a hang or the tally failure
    both conform. Returning a value does not. NOT DISCRIMINATING: v0.26.17
    fails its pre and passes this cell too. It pins that the spec leaves the
    order open, so no later change may make one outcome required."""
    exe = build("e2_order")
    try:
        p = _run(exe)
    except subprocess.TimeoutExpired:
        return
    assert p.returncode != 0 and "Precondition violated in tally" in p.stderr, (
        f"got rc={p.returncode}, stdout={p.stdout!r}, stderr={p.stderr[-300:]!r}"
    )
