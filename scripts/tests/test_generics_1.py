"""GENERICS-1 + GENERIC-COMPARE-1, phase B (docs/design/generics-1-engineer-plan.md).

What a pass here means:

* pick.llmll verifies with one copy per instantiation: "generics: 2
  definitions, 6 instances". pick-min@[string] falls back (compare at string is
  uninterpreted), and use-pos proves its PositiveInt return through the
  copy pick-min@[PositiveInt], whose post carries the obligation result > 0.
* pick_bad.llmll (a body that does not meet its post) is refuted at the copy
  pick-min-bad@[int], exit 1.
* P1 (a priority queue over int, string and a sum type) and P3 (group-by with
  (k key)) build with GHC and print what the proposal says they print.
* `llmll test` lands the tested record on the copy the property calls
  (pick-min@[int]), with a subject_key, and on nothing else (edge case 15).
* A generic program round-trips through the JSON-AST (schema 0.15.0).
* A generic imported from another module is copied into the importer, and its
  copy calls the module's own helper by its qualified name.
* A generic that no root instantiates is listed in the trust report as
  "unverified (generic, not instantiated)".

* pick-min@[int], pick-min@[bool], pick-min@[PositiveInt] and
  pick-min-1@[int] prove: the guard (<= (compare x y) 0) unfolds through the
  same compare%int / compare%bool term as the body (GuardClassifier), and
  "5 of 7 contracted functions proved" (the two string copies are assumed).
  A body that takes the wrong branch of that guard is refuted at int and at
  bool, so the unfolding is not vacuous.

* GENERIC-COMPARE-PAIR-1: pair_cmp.llmll proves pick-min at (int,bool) and
  ((int,bool),int) and the two order witnesses, and pick-min@[(int,string)]
  stays assumed. pair_cmp_bad.llmll is refuted at every definition.
"""

import json
import os
import re
import shlex
import shutil
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURES = REPO_ROOT / "scripts" / "tests" / "fixtures" / "generics"

pytestmark = pytest.mark.skipif(
    not os.environ.get("LLMLL_BIN"),
    reason="set LLMLL_BIN to a built llmll",
)

needs_fixpoint = pytest.mark.skipif(
    shutil.which("liquid-fixpoint") is None and shutil.which("fixpoint") is None,
    reason="needs liquid-fixpoint on PATH",
)

BUILD_TIMEOUT_S = 900
RUN_TIMEOUT_S = 10
CHECK_TIMEOUT_S = 120


def _llmll() -> list[str]:
    return shlex.split(os.environ["LLMLL_BIN"])


def _run(args, cwd, timeout=CHECK_TIMEOUT_S):
    return subprocess.run([*_llmll(), *args], capture_output=True, text=True,
                          timeout=timeout, cwd=str(cwd))


def _copy(tmp_path: Path, *names: str) -> Path:
    for n in names:
        dst = tmp_path / n
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy(FIXTURES / n, dst)
    return tmp_path / names[0]


def _line(out: str, prefix: str) -> list[str]:
    """The comma-separated names on the first output line starting with prefix."""
    for raw in out.splitlines():
        s = raw.strip()
        if s.startswith(prefix):
            return [x.strip() for x in s[len(prefix):].split(",") if x.strip()]
    return []


@pytest.fixture(scope="module")
def pick_verify(tmp_path_factory):
    d = tmp_path_factory.mktemp("pick")
    src = _copy(d, "pick.llmll")
    p = _run(["verify", src.name], d)
    return p


@needs_fixpoint
def test_pick_counts_and_string_fallback(pick_verify):
    p = pick_verify
    out = p.stdout + p.stderr
    assert p.returncode == 0, out
    assert "generics: 2 definitions, 6 instances" in out
    fallback = _line(out, "body-fallback:")
    assert "pick-min@[string]" in fallback and "pick-min-1@[string]" in fallback, out
    assert "use-pos" in _line(out, "body-faithful:"), out
    # Generic sources are dropped; only copies and roots are verified.
    named = _line(out, "body-faithful:") + fallback
    assert "pick-min" not in named and "pick-min-1" not in named, out


@needs_fixpoint
def test_pick_positive_copy_carries_result_gt_zero(pick_verify):
    out = pick_verify.stdout + pick_verify.stderr
    m = re.search(r"\.fq written to (\S+\.fq)", out)
    assert m, out
    fq = Path(m.group(1)).read_text(encoding="utf-8")
    # use-pos reads the copy's post, which includes PositiveInt's refinement.
    assert "(_bv_call_pick_min__PositiveInt__0 > 0)" in fq


@needs_fixpoint
@pytest.mark.parametrize("copy", ["pick-min@[int]", "pick-min@[bool]",
                                  "pick-min@[PositiveInt]", "pick-min-1@[int]"])
def test_pick_predicted_proofs(pick_verify, copy):
    out = pick_verify.stdout + pick_verify.stderr
    assert copy in _line(out, "body-faithful:"), out
    assert copy not in _line(out, "body-fallback:"), out


@needs_fixpoint
def test_pick_proof_summary(pick_verify):
    out = pick_verify.stdout + pick_verify.stderr
    assert pick_verify.returncode == 0, out
    assert ("5 of 7 contracted functions proved; 2 assumed, not proved: "
            "pick-min@[string], pick-min-1@[string]") in out, out


@needs_fixpoint
def test_wrong_branch_of_compare_guard_is_refuted(tmp_path):
    src = tmp_path / "swap.llmll"
    src.write_text(
        "(def-shell pick-max-wrong :type-params [(a ord)] [x: a y: a] -> a\n"
        "  (post (<= (compare result y) 0))\n"
        "  (if (<= (compare x y) 0) y x))\n"
        "(def-shell use-i [x: int y: int] -> int (pick-max-wrong x y))\n"
        "(def-shell use-b [x: bool y: bool] -> bool (pick-max-wrong x y))\n",
        encoding="utf-8")
    p = _run(["verify", src.name], tmp_path)
    out = p.stdout + p.stderr
    assert p.returncode == 1, out
    assert "body verification of 'pick-max-wrong@[int]' failed" in out, out
    assert "body verification of 'pick-max-wrong@[bool]' failed" in out, out


@needs_fixpoint
def test_pick_bad_is_refuted_at_the_copy(tmp_path):
    src = _copy(tmp_path, "pick_bad.llmll")
    p = _run(["verify", src.name], tmp_path)
    out = p.stdout + p.stderr
    assert p.returncode == 1, out
    assert "pick-min-bad@[int]" in _line(out, "body-faithful:"), out
    assert "body verification of 'pick-min-bad@[int]' failed" in out


def _exe(out: Path) -> str:
    import glob
    exes = glob.glob(str(out / ".stack-work" / "install" / "*" / "*" / "*" / "bin" / "*"))
    assert len(exes) == 1, f"expected one executable under {out}, found {exes}"
    return exes[0]


@pytest.mark.skipif(shutil.which("stack") is None, reason="needs stack to build")
@pytest.mark.parametrize("name, expected", [
    ("p1", "1 2 3 |a b c |job1 job2 "),
    ("p3", "1: 2\n2: 2\n|a: 2\nb: 1\n"),
])
def test_build_and_run(tmp_path, name, expected):
    src = _copy(tmp_path, f"{name}.llmll")
    out = tmp_path / f"out-{name}"
    p = _run(["build", src.name, "-o", str(out)], tmp_path, BUILD_TIMEOUT_S)
    assert p.returncode == 0, f"build failed rc={p.returncode}\n{p.stdout[-1500:]}\n{p.stderr[-1500:]}"
    r = subprocess.run([_exe(out)], input="", capture_output=True, text=True, timeout=RUN_TIMEOUT_S)
    assert r.returncode == 0, r.stderr[-500:]
    assert r.stdout.startswith(expected), repr(r.stdout)
    lib = (out / "src" / "Lib.hs").read_text(encoding="utf-8")
    if name == "p3":
        assert "group_by :: (Ord tp_k, Show tp_k) => " in lib
    else:
        assert "pq_insert :: Ord tp_k => " in lib


def test_tested_record_lands_on_the_copy_only(tmp_path):
    src = _copy(tmp_path, "pick_test.llmll")
    p = _run(["test", src.name], tmp_path)
    assert p.returncode == 0, p.stdout + p.stderr
    side = json.loads((tmp_path / "pick_test.llmll.verified.json").read_text(encoding="utf-8"))
    fns = {k for k, v in side.items() if isinstance(v, dict)}
    assert fns == {"pick-min@[int]"}, side
    post = side["pick-min@[int]"]["post"]
    assert post["display_level"]["level"] == "tested"
    (w,) = post["pbt_witnesses"]
    assert w["description"] == "pick-min is at most both"
    assert w["subject_key"].startswith("sha256:")


def test_json_ast_round_trip(tmp_path):
    src = _copy(tmp_path, "pick.llmll")
    p = _run(["build", src.name, "--emit"], tmp_path, BUILD_TIMEOUT_S)
    assert p.returncode == 0, p.stdout + p.stderr
    (ast,) = list(tmp_path.glob("generated/pick/pick.ast.json"))
    text = ast.read_text(encoding="utf-8")
    assert json.loads(text)["schemaVersion"] == "0.15.0"
    assert '"type_params"' in text
    c = _run(["check", str(ast)], tmp_path)
    assert c.returncode == 0, c.stdout + c.stderr


@needs_fixpoint
def test_imported_generic_copy_calls_qualified_helper(tmp_path):
    _copy(tmp_path, "xmod/glib.llmll", "xmod/guse.llmll")
    d = tmp_path / "xmod"
    p = _run(["verify", "guse.llmll"], d)
    out = p.stdout + p.stderr
    assert p.returncode == 0, out
    faithful = _line(out, "body-faithful:")
    assert "glib.bump-first@[bool]" in faithful and "use-bump" in faithful, out
    m = re.search(r"\.fq written to (\S+\.fq)", out)
    assert m, out
    assert "glib_helper" in Path(m.group(1)).read_text(encoding="utf-8")


@needs_fixpoint
def test_uninstantiated_generic_trust_label(tmp_path):
    src = tmp_path / "unused.llmll"
    src.write_text("(def-shell idg :type-params [a] [x: a] -> a (post true) x)\n"
                   "(def-shell plus1 [x: int] -> int (post (> result x)) (+ x 1))\n",
                   encoding="utf-8")
    p = _run(["verify", src.name, "--trust-report"], tmp_path)
    out = p.stdout + p.stderr
    assert p.returncode == 0, out
    assert "generics: 1 definitions, 0 instances" in out
    assert "generic: unverified (generic, not instantiated)" in out


@needs_fixpoint
def test_verify_json_generics_block(tmp_path):
    src = _copy(tmp_path, "pick.llmll")
    p = _run(["--json", "verify", src.name], tmp_path)
    assert p.returncode == 0, p.stdout + p.stderr
    assert '"generics"' in p.stdout
    assert '"per_definition": {"pick-min": 4, "pick-min-1": 2}' in p.stdout \
        or '"per_definition":{"pick-min":4,"pick-min-1":2}' in p.stdout, p.stdout


@needs_fixpoint
def test_compare_unfolds_at_int_and_bool(tmp_path):
    """GENERIC-COMPARE-1: compare%int / compare%bool are interpreted, so posts
    that need compare's definition prove; compare at string falls back."""
    src = tmp_path / "c.llmll"
    src.write_text(
        "(def-shell ci [x: int y: int] -> int (post (and (and (>= result (- 0 1)) (<= result 1))"
        " (= (= result 0) (= x y)))) (compare x y))\n"
        "(def-shell cb [x: bool y: bool] -> int (post (= (= result 0) (= x y))) (compare x y))\n"
        "(def-shell cs [x: string y: string] -> int (post (<= result 1)) (compare x y))\n",
        encoding="utf-8")
    p = _run(["verify", src.name], tmp_path)
    out = p.stdout + p.stderr
    assert p.returncode == 0, out
    assert _line(out, "body-faithful:") == ["ci", "cb"], out
    assert _line(out, "body-fallback:") == ["cs"], out
    assert "2 of 3 contracted functions proved" in out, out


@needs_fixpoint
def test_pair_compare_proves(tmp_path):
    src = _copy(tmp_path, "pair_cmp.llmll")
    p = _run(["verify", src.name], tmp_path)
    out = p.stdout + p.stderr
    assert p.returncode == 0, out
    # _line splits on ",", which a pair copy name contains; read the raw line.
    faithful = next(l for l in out.splitlines() if l.strip().startswith("body-faithful:"))
    fallback = next(l for l in out.splitlines() if l.strip().startswith("body-fallback:"))
    for fn in ["pick-min@[(int,bool)]", "pick-min@[((int,bool),int)]",
               "order-first", "order-second"]:
        assert fn in faithful, out
    assert "pick-min@[(int,string)]" in fallback, out
    assert "pick-min@[(int,string)]" not in faithful, out
    assert ("4 of 5 contracted functions proved; 1 assumed, not proved: "
            "pick-min@[(int,string)]") in out, out


@needs_fixpoint
def test_pair_compare_refutes(tmp_path):
    src = _copy(tmp_path, "pair_cmp_bad.llmll")
    p = _run(["verify", src.name], tmp_path)
    out = p.stdout + p.stderr
    assert p.returncode == 1, out
    assert "body verification of 'pick-min-swapped@[(int,bool)]' failed" in out, out
    assert "body verification of 'order-second-wrong' failed" in out, out
