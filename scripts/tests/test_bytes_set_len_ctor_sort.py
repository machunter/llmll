"""BYTES-SET-CLAUSE-LEN-1 and CTOR-FIELD-SORT-1, end to end.

BYTES-SET-CLAUSE-LEN-1: a contract clause that reads the length of a
`bytes-set` result gets the store's length lemma, guarded by the store's
precondition, as ground-fact family `bytes-set-length`. The body side has
assumed the same lemma since LEVER-A1; the clause side had no fact, so a true
clause was refuted.

CTOR-FIELD-SORT-1: a constructor field whose type is a payload sum, a pair
holding one, or a `Result` is declared at that sort in the `.fq` data
declaration. It was declared `int`, and every term that built the constructor
crashed liquid-fixpoint ("Cannot unify int with T").

What a pass here means:

* b1, b3_nest, b5_def and the cross-module caller buse verify (exit 0).
* b2_wrong and b6_def_wrong (false clauses) stay refuted.
* b4_oob (an out-of-bounds store index) stays refuted: the fact is guarded.
* c1, c3_order and c22_param verify; c2_wrong is refuted, not a solver crash.
* the trust report on b1 discloses the `bytes-set-length` family.
"""

import json
import os
import shlex
import shutil
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURES = REPO_ROOT / "scripts" / "tests" / "fixtures" / "bytes_set_len_ctor_sort"

pytestmark = [
    pytest.mark.skipif(not os.environ.get("LLMLL_BIN"), reason="set LLMLL_BIN to a built llmll"),
    pytest.mark.skipif(
        shutil.which("liquid-fixpoint") is None and shutil.which("fixpoint") is None,
        reason="needs liquid-fixpoint on PATH",
    ),
]


def _llmll() -> list:
    return shlex.split(os.environ["LLMLL_BIN"])


def _verify(tmp_path: Path, name: str, *args: str) -> tuple:
    shutil.copy(FIXTURES / name, tmp_path / name)
    p = subprocess.run(_llmll() + ["--json", "verify", *args, name],
                       capture_output=True, text=True, timeout=120, cwd=str(tmp_path))
    return p, json.loads(p.stdout)


@pytest.mark.parametrize("name", [
    "b1.llmll", "b3_nest.llmll", "b5_def.llmll",
    "c1.llmll", "c3_order.llmll", "c22_param.llmll",
])
def test_true_contract_verifies(tmp_path, name):
    p, doc = _verify(tmp_path, name)
    assert p.returncode == 0, p.stdout + p.stderr
    assert doc["solver_verdict"] == "safe"
    assert doc["success"] is True


@pytest.mark.parametrize("name", [
    "b2_wrong.llmll", "b4_oob.llmll", "b6_def_wrong.llmll", "c2_wrong.llmll",
])
def test_false_contract_is_refuted(tmp_path, name):
    p, doc = _verify(tmp_path, name)
    assert p.returncode == 1, p.stdout + p.stderr
    assert doc["solver_verdict"] == "refuted"
    assert any(d.get("kind") == "lh-unsafe" for d in doc["diagnostics"])
    assert "Cannot unify" not in p.stdout + p.stderr


def test_cross_module_call_pre(tmp_path):
    """The clause term sits in a callee pre and reaches the caller's call-pre."""
    lib, _ = _verify(tmp_path, "blib.llmll")
    assert lib.returncode == 0, lib.stdout + lib.stderr
    p, doc = _verify(tmp_path, "buse.llmll")
    assert p.returncode == 0, p.stdout + p.stderr
    assert doc["solver_verdict"] == "safe"


def test_trust_report_discloses_family(tmp_path):
    p, doc = _verify(tmp_path, "b1.llmll", "--trust-report")
    assert p.returncode == 0, p.stdout + p.stderr
    tr = doc["trust_report"]
    tr = json.loads(tr) if isinstance(tr, str) else tr
    fams = {f for e in tr["entries"] for f in e.get("ground_fact_families", [])}
    assert "bytes-set-length" in fams
