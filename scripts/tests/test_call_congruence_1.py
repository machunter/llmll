"""CALL-CONGRUENCE-1: two calls with equal arguments return equal results.

For each pair of calls to one callee on one path, the body VC now assumes the
Ackermann fact (args_i = args_j) => (r_i = r_j), when the callee's parameters
and result are all int, bool or string. Pairs are keyed on the callee's
alpha-renamed binder, so a shadowed parameter name never pairs with the
parameter. ABSTRACTION-VERDICT-1 stays the backstop for every other pair
(test_abstraction_verdict_1.py). Design: docs/design/ffi-determinism-proposal.md
Rev 1, Part 3.

What a pass here means:

* a1, a2 and w5 (true posts that need two equal calls to agree) and caller's h
  are verified, with no abstraction fallback.
* a4 (a false post whose counterexample needs two self-calls with different
  arguments) is refuted again; before, it fell back.
* mixed: h is verified and gw keeps its one-call refutation.
* W-WRAP: twice-g, two calls to a def-shell wrapper of a haskell.text export,
  is verified and keeps its inherited ffi_assumptions row.
* bool arguments compare by value: (> x 0) and (< 0 x) pair; (> x 0) and
  (> x 1) do not, and the false post stays refuted.
* string arguments: a guarded pair verifies, and a body that passes two
  string params to a callee called twice keeps verifying.
* R3 (a shadowed function-typed parameter) is never verified.
* --strict-verified-core accepts a1.
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
FIXTURES = REPO_ROOT / "scripts" / "tests" / "fixtures"
AV = FIXTURES / "abstraction_verdict"
CC = FIXTURES / "call_congruence"

pytestmark = [
    pytest.mark.skipif(not os.environ.get("LLMLL_BIN"), reason="set LLMLL_BIN to a built llmll"),
    pytest.mark.skipif(
        shutil.which("liquid-fixpoint") is None and shutil.which("fixpoint") is None,
        reason="needs liquid-fixpoint on PATH",
    ),
]


def _verify(tmp_path: Path, src: Path, *args: str) -> tuple[subprocess.CompletedProcess, dict]:
    shutil.copy(src, tmp_path / src.name)
    p = subprocess.run([*shlex.split(os.environ["LLMLL_BIN"]), "--json", "verify", *args, src.name],
                       capture_output=True, text=True, timeout=120, cwd=str(tmp_path))
    return p, json.loads(p.stdout)


def _failed_fns(doc: dict) -> set:
    return {m.group(1) for d in doc.get("diagnostics", [])
            if d.get("kind") == "lh-unsafe"
            for m in [re.search(r"of '([^']+)'", d.get("message", ""))] if m}


@pytest.mark.parametrize("src,fns", [
    (AV / "a1.llmll", ["g", "h"]),
    (AV / "a2.llmll", ["g", "h8"]),
    (AV / "w5.llmll", ["t"]),
    (AV / "caller.llmll", ["g", "h", "k"]),
    (CC / "wwrap.llmll", ["twice-g"]),
    (CC / "bool_args.llmll", ["gb", "hb"]),
    (CC / "string_args.llmll", ["gs1", "hs", "us"]),
])
def test_cc_equal_calls_agree(tmp_path, src, fns):
    p, doc = _verify(tmp_path, src)
    assert p.returncode == 0, p.stdout
    assert doc["solver_verdict"] == "safe"
    assert "abstraction_fallback" not in doc
    assert doc["body_fallback"] == []
    assert sorted(doc["body_faithful"]) == sorted(fns)


def test_cc_a4_false_post_is_refuted_again(tmp_path):
    p, doc = _verify(tmp_path, AV / "a4.llmll")
    assert p.returncode == 1, p.stdout
    assert doc["solver_verdict"] == "refuted"
    assert "abstraction_fallback" not in doc
    assert _failed_fns(doc) == {"f"}


def test_cc_mixed_h_verified_gw_refuted(tmp_path):
    p, doc = _verify(tmp_path, AV / "mixed.llmll")
    assert p.returncode == 1, p.stdout
    assert "abstraction_fallback" not in doc
    assert _failed_fns(doc) == {"gw"}
    assert "h" in doc["body_faithful"]


def test_cc_bool_args_that_differ_stay_refuted(tmp_path):
    p, doc = _verify(tmp_path, CC / "bool_args_bad.llmll")
    assert p.returncode == 1, p.stdout
    assert _failed_fns(doc) == {"hb"}


def test_cc_wwrap_keeps_its_ffi_row(tmp_path):
    p, doc = _verify(tmp_path, CC / "wwrap.llmll", "--trust-report")
    assert p.returncode == 0, p.stdout
    tr = doc["trust_report"]
    tr = json.loads(tr) if isinstance(tr, str) else tr
    e = next(x for x in tr["entries"] if x["name"] == "twice-g")
    assert e["post_level"].startswith("verified"), e
    assert e["ffi_assumptions"] == [{"export": "length", "origin": "g", "package": "text"}]


def test_cc_wwrap_text_names_determinism(tmp_path):
    shutil.copy(CC / "wwrap.llmll", tmp_path / "wwrap.llmll")
    p = subprocess.run([*shlex.split(os.environ["LLMLL_BIN"]), "verify", "--trust-report", "wwrap.llmll"],
                       capture_output=True, text=True, timeout=120, cwd=str(tmp_path))
    out = p.stdout + p.stderr
    assert "≈ inherits haskell.text export length via g" in out, out
    assert "deterministic within one run" in out, out


def test_cc_r3_shadowed_parameter_never_verified(tmp_path):
    p, doc = _verify(tmp_path, CC / "r3.llmll")
    assert "k" not in doc["body_faithful"] or "k" in _failed_fns(doc), doc


def test_cc_strict_core_accepts_a1(tmp_path):
    p, doc = _verify(tmp_path, AV / "a1.llmll", "--strict-verified-core")
    assert p.returncode == 0, p.stdout
