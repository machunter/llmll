"""FQ-ARITH-FLAT-1: arithmetic prints flat, and every regrouping it does is sound.

liquid-fixpoint's parser costs 2^depth in parenthesis depth: at each `(` it
tries a tuple first, reads the whole expression, fails for want of a comma and
reads it again (liquid-fixpoint 0.9.6.3.7, Parse.hs:987-988). On llmll 0.38.0
a 20-term sum printed one pair per operation stopped `verify` at its time
limit (exit 5), and a trivial function beside it lost its proof. The printer
now writes `a + b + c` and keeps a pair only where the solver's fixity table
needs one.

What a pass here means:

* Each false fixture (F1-F7) is still refuted. F1-F5 are proved by a printer
  that drops every pair, so they fail if the printer drops a pair it needs.
  F7 is proved by a printer that regroups `2 * ((a / 2) * 3)` as
  `2 * a / 2 * 3`, the unsound rule FA-13 found during implementation.
* Each true fixture (T1-T6) is still verified; S20 and R20, both 20-term
  sums, now verify under `--time-limit 15`, beside a function that keeps its
  proof.
* The differential test: random trees over `+ - * / mod` go through the real
  compiler, and the solver proves each printed term equal to a fully
  parenthesized print of the same tree. The same trees with every pair dropped
  are refuted, so the test is shown to be able to fail.
* Four fixity facts the printer relies on are Unsafe, and one is Safe, on the
  solver on PATH. They fail if a future solver changes its table.
"""

import json
import os
import random
import re
import shlex
import shutil
import signal
import subprocess
from pathlib import Path

import pytest

FIX = Path(__file__).resolve().parent / "fixtures" / "fq_arith_flat_1"
FIXPOINT = shutil.which("fixpoint") or shutil.which("liquid-fixpoint")

pytestmark = [
    pytest.mark.skipif(not os.environ.get("LLMLL_BIN"), reason="set LLMLL_BIN to a built llmll"),
    pytest.mark.skipif(FIXPOINT is None, reason="needs liquid-fixpoint on PATH"),
]

TIMEOUT_S = 120


def _run(cmd, cwd):
    """Run a command; on a timeout kill the whole process group, not only the child."""
    p = subprocess.Popen(cmd, cwd=str(cwd), stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                         text=True, start_new_session=True)
    try:
        out, err = p.communicate(timeout=TIMEOUT_S)
    except subprocess.TimeoutExpired:
        os.killpg(p.pid, signal.SIGKILL)
        p.communicate()
        raise
    return subprocess.CompletedProcess(p.args, p.returncode, out, err)


def _llmll(args, cwd):
    return _run(shlex.split(os.environ["LLMLL_BIN"]) + list(args), cwd)


def _verify(tmp_path, name, *flags):
    shutil.copy(FIX / name, tmp_path / name)
    p = _llmll([*flags, "--json", "verify", name, "--fq-out", str(tmp_path / "out.fq")], tmp_path)
    return p, json.loads(p.stdout)


# ---------------------------------------------------------------------------
# Fixtures through the real binary
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("name", ["F1_sub.llmll", "F2_div.llmll", "F3_mod.llmll",
                                  "F4_subadd.llmll", "F5_mulsub.llmll", "F6_divmul.llmll",
                                  "F7_mulregroup.llmll"])
def test_false_fixture_is_refuted(tmp_path, name):
    p, j = _verify(tmp_path, name)
    assert p.returncode == 1, p.stdout + p.stderr
    assert j["solver_verdict"] == "refuted"
    assert j.get("all_proved") is not True


@pytest.mark.parametrize("name", ["T1_rsub.llmll", "T2_coef.llmll", "T3_mod.llmll",
                                  "T4_negl.llmll", "T5_boolflip.llmll", "T6_notchain.llmll"])
def test_true_fixture_is_verified(tmp_path, name):
    p, j = _verify(tmp_path, name)
    assert p.returncode == 0, p.stdout + p.stderr
    assert j["solver_verdict"] == "safe"
    assert j["all_proved"] is True


@pytest.mark.parametrize("name", ["S20_left.llmll", "R20_right.llmll"])
def test_twenty_term_sum_verifies_under_a_short_limit(tmp_path, name):
    """llmll 0.38.0: exit 5, resource-limit. Now: verified, and `good` keeps its proof."""
    p, j = _verify(tmp_path, name, "--time-limit", "15")
    assert p.returncode == 0, p.stdout + p.stderr
    assert j["solver_verdict"] == "safe"
    assert j["all_proved"] is True
    sidecar = json.loads((tmp_path / (name + ".verified.json")).read_text())
    assert "good" in json.dumps(sidecar)
    # The sum reaches the solver as one chain, with no inner pair.
    fq = (tmp_path / "out.fq").read_text()
    assert " + ".join(f"x{i}" for i in range(20)) in fq


# ---------------------------------------------------------------------------
# The differential test
# ---------------------------------------------------------------------------

VARS = ("a", "b", "c")


def _leaf(rng):
    if rng.random() < 0.6:
        return ("var", rng.choice(VARS))
    return ("lit", rng.choice([-3, -1, 0, 1, 2, 5]))


def _tree(rng, d):
    """A random tree. `*` has a numeral operand and `/`, `mod` a numeral divisor
    above 0, which is what the emitter admits."""
    if d == 0 or rng.random() < 0.15:
        return _leaf(rng)
    op = rng.choice(["+", "+", "-", "-", "*", "/", "mod"])
    if op == "*":
        k = ("lit", rng.choice([-2, 2, 3]))
        t = _tree(rng, d - 1)
        return ("bin", "*", t, k) if rng.random() < 0.5 else ("bin", "*", k, t)
    if op in ("/", "mod"):
        return ("bin", op, _tree(rng, d - 1), ("lit", rng.choice([2, 3, 7])))
    return ("bin", op, _tree(rng, d - 1), _tree(rng, d - 1))


def _sexpr(e):
    if e[0] == "var":
        return e[1]
    if e[0] == "lit":
        return str(e[1])
    return f"({e[1]} {_sexpr(e[2])} {_sexpr(e[3])})"


def _nested(e):
    """One pair per operation: the shape the solver reads with no fixity at all."""
    if e[0] == "var":
        return e[1]
    if e[0] == "lit":
        return str(e[1])
    return f"({_nested(e[2])} {e[1]} {_nested(e[3])})"


def _dropped(e):
    """Every pair dropped: the error a wrong printer makes."""
    if e[0] == "var":
        return e[1]
    if e[0] == "lit":
        return str(e[1])
    return f"{_dropped(e[2])} {e[1]} {_dropped(e[3])}"


def _trees(n, seed=20261107):
    rng = random.Random(seed)
    out = []
    while len(out) < n:
        t = _tree(rng, rng.choice([3, 4, 5]))
        if t[0] == "bin":
            out.append(t)
    return out


def _goal_fq(pairs):
    lines = [f"bind {i} {v} : {{ v : int | true }}" for i, v in enumerate(VARS)]
    for n, (lhs, rhs) in enumerate(pairs):
        lines.append("constraint:\n  env [0; 1; 2]\n  lhs { result : int | true }\n"
                     f"  rhs {{ result : int | (({lhs}) - ({rhs})) = 0 }}\n  id {n}\n  tag [{n}]\n")
    return "\n".join(lines) + "\n"


def _solve(tmp_path, name, text):
    (tmp_path / name).write_text(text)
    p = _run([FIXPOINT, "-q", "--json", name], tmp_path)
    o = p.stdout + p.stderr
    status = json.loads(o[o.index("{"):o.rindex("}") + 1])
    return status.get("status", status)


TAG = 100000


def _printed_terms(tmp_path, trees):
    """The compiler's own print of each tree, read back from the emitted .fq.

    Function t<i> has body tree i and the false post `result = TAG + i`, so the
    constraint whose rhs names TAG + i carries the body's print in its lhs.
    """
    src = "\n".join(f"(def t{i} [a: int b: int c: int] -> int (post (= result {TAG + i})) {_sexpr(t)})"
                    for i, t in enumerate(trees)) + "\n"
    (tmp_path / "diff.llmll").write_text(src)
    _llmll(["--json", "verify", "diff.llmll", "--fq-out", str(tmp_path / "diff.fq")], tmp_path)
    text = (tmp_path / "diff.fq").read_text()
    got = {}
    for block in text.split("constraint:")[1:]:
        lhs = re.search(r"^  lhs \{ result : int \| (.*) \}$", block, re.M)
        rhs = re.search(r"^  rhs \{ result : int \| \(?result = (\d+)\)? \}$", block, re.M)
        if not (lhs and rhs):
            continue
        m = re.fullmatch(r"\(result = (.*)\)|result = (.*)", lhs.group(1))
        if m:
            got[int(rhs.group(1)) - TAG] = m.group(1) or m.group(2)
    return got


@pytest.fixture(scope="module")
def printed(tmp_path_factory):
    trees = _trees(200)
    return trees, _printed_terms(tmp_path_factory.mktemp("diff"), trees)


def test_printed_terms_equal_their_nested_form(tmp_path, printed):
    trees, got = printed
    assert sorted(got) == list(range(len(trees))), "every body reached the .fq"
    # The printer did flatten: no printed term keeps one pair per operation.
    assert sum(1 for i, t in enumerate(trees) if got[i] != _nested(t)) > len(trees) // 2
    status = _solve(tmp_path, "good.fq", _goal_fq([(_nested(t), got[i]) for i, t in enumerate(trees)]))
    assert status["tag"] == "Safe", status


def test_the_differential_test_can_fail(tmp_path, printed):
    """The same trees with every pair dropped, where that differs from the
    compiler's print: most are refuted."""
    trees, got = printed
    bad = [(_nested(t), _dropped(t)) for i, t in enumerate(trees)
           if "(" + _dropped(t) + ")" != got.get(i)]
    assert len(bad) > len(trees) // 2
    status = _solve(tmp_path, "bad.fq", _goal_fq(bad))
    assert status["tag"] == "Unsafe", status
    # An Unsafe status is [stats, [refuted constraint ids]].
    assert len(status["contents"][1]) > len(bad) // 2, status


# ---------------------------------------------------------------------------
# The fixity facts the printer relies on
# ---------------------------------------------------------------------------

FACTS = [
    ("a - (b - c)", "a - b - c", "Unsafe"),
    ("(a * (b / 2))", "(a * b / 2)", "Unsafe"),
    ("(a + (b mod 3))", "(a + b mod 3)", "Unsafe"),
    ("(a - (b + c))", "(a - b + c)", "Unsafe"),
    ("((a / 2) / 3)", "(a / 2 / 3)", "Safe"),
]


@pytest.mark.parametrize("lhs,rhs,tag", FACTS, ids=[f"{l} vs {r}" for l, r, _ in FACTS])
def test_solver_fixity_fact(tmp_path, lhs, rhs, tag):
    assert _solve(tmp_path, "fact.fq", _goal_fq([(lhs, rhs)]))["tag"] == tag
