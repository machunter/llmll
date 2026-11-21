"""MUL-VAR-1: the fact-multiset differential against rev3.py, the oracle side.

The design's fact set (docs/design/mul-var-proposal.md, "Fact set") has two
implementations: the oracle `scripts/mulvar/rev3.py` and the compiler's
`compiler/src/LLMLL/ProductFacts.hs`. They are compared fact for fact in two
halves, because one side is Python and the other Haskell:

* `scripts/mulvar/export_witnesses.py` runs rev3.py on every witness and
  writes, per witness and per family, the SHA-256 of rev3's sorted fact lines
  (`fact_line`: canonical relations, atoms under rev3's keys) into
  `compiler/test/fixtures/mul_var_1/witnesses.json`.
* `compiler/test/ProductSpec.hs` ("differential: every witness's fact
  multiset equals rev3.py's") rebuilds the same lines from the emitter's facts,
  after renaming its atoms to rev3's keys, and compares the digests.

This file holds the Python half: the committed table is what the pinned
rev3.py gives today. Without it, a change to rev3.py or to the exporter could
leave the hspec half comparing against a stale table.

Since DIV-VAR-1 the compiler's generator has the division pass, so the table is
exported with `--divvar` (rev3.py plus `scripts/divvar/divvar_core.py`). Only
the refusal rows C1, C2, C3 and C6, which divide by a variable, differ from
rev3.py alone.
"""

from __future__ import annotations

import hashlib
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
REV3 = REPO_ROOT / "scripts" / "mulvar" / "rev3.py"
EXPORT = REPO_ROOT / "scripts" / "mulvar" / "export_witnesses.py"
TABLE = REPO_ROOT / "compiler" / "test" / "fixtures" / "mul_var_1" / "witnesses.json"
REV3_SHA256 = "14e9441d20f55f4025ae33eb5029114e0ef1fb5ac59a90efa33b884c6b4cda12"


def test_mv_rev3_is_the_corrected_oracle() -> None:
    assert hashlib.sha256(REV3.read_bytes()).hexdigest() == REV3_SHA256


def test_mv_witness_table_regenerates_from_rev3_byte_for_byte(tmp_path: Path) -> None:
    out = tmp_path / "witnesses.json"
    p = subprocess.run([sys.executable, "-I", str(EXPORT), "--divvar", str(out)], capture_output=True, text=True, timeout=300)
    assert p.returncode == 0, p.stdout + p.stderr
    assert out.read_bytes() == TABLE.read_bytes(), "witnesses.json is stale: rerun scripts/mulvar/export_witnesses.py"


def test_mv_witness_table_carries_fact_digests() -> None:
    import json

    rows = json.loads(TABLE.read_text())["witnesses"]
    assert len(rows) == 132
    with_facts = [r for r in rows if "refused" not in r]
    assert all(set(r["fact_digests"]) == set(r["families"]) for r in with_facts)
    assert sum(r["facts"] for r in with_facts) == 58487
