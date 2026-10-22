"""PBT-EVAL-PARITY-1: `llmll test` evaluates the pure builtins and says why it skips.

On v0.30.10 every property below that touches a string, regex or numeric
builtin was skipped ("property body did not reduce on any sample"), and
`llmll --json test` printed QuickCheck's "*** Gave up!" lines to stdout ahead of
its JSON document, so the output did not parse. The evaluator now answers each
pure builtin with the definition the generated program runs
(compiler/src/LLMLL/RuntimePure.hs), QuickCheck runs with chatty = False, and a
skip carries a `skip_reason` that names the Tier 1 FFI export or the unmodeled
builtin the property reaches.
"""

import json
import os
import shlex
import subprocess
from pathlib import Path

import pytest

pytestmark = pytest.mark.skipif(
    not os.environ.get("LLMLL_BIN"),
    reason="set LLMLL_BIN to a built llmll",
)

TIMEOUT_S = 120

BUILTINS = """\
(module builtins
  (def-shell sl [s: string] -> string (string-slice s 0 1))
  (type Color (| Red) (| Box int))
  (def-shell unbox [c: Color] -> int (match c ((Red) 0) ((Box n) n)))
  (check "slice" (for-all [s: string] (<= (string-length (sl s)) 1)))
  (check "char-at" (for-all [s: string] (<= (string-length (string-char-at s 0)) 1)))
  (check "abs" (for-all [x: int] (>= (abs x) 0)))
  (check "min-max" (for-all [x: int y: int] (<= (min x y) (max x y))))
  (check "mod" (for-all [x: int] (= (mod (* x 2) 2) 0)))
  (check "trim" (for-all [s: string] (= (string-trim (string-trim s)) (string-trim s))))
  (check "concat" (for-all [a: string b: string]
    (= (string-length (string-concat a b)) (+ (string-length a) (string-length b)))))
  (check "split" (for-all [s: string] (>= (list-length (string-split "," s)) 1)))
  (check "to-int" (for-all [x: int] (= (string-to-int (int-to-string x)) (ok x))))
  (check "regex" (for-all [s: string] (= (regex-match "^a" s) (= (string-char-at s 0) "a"))))
  (check "range" (for-all [n: int] (>= (list-length (range 0 n)) 0)))
  (check "nth" (for-all [x: int] (is-ok (list-nth [x] 0))))
  (check "contains" (for-all [x: int] (list-contains [x] x)))
  (check "ctor" (for-all [x: int] (= (unbox (Box x)) x)))
  (check "nullary" (for-all [x: int] (= (unbox Red) 0))))
"""

FFI = """\
(module ffiprop
  (import haskell.containers (interface [
    [from-list (fn [xs: list[(string, int)]] -> map[string, int])]
    [keys      (fn [m: map[string, int]] -> list[string])]]))
  (def-shell sort-strings [xs: list[string]] -> list[string]
    (keys (from-list (list-map xs (fn [x: string] (pair x 0))))))
  (check "sorts two" (for-all [a: string b: string]
    (= (list-length (sort-strings [a b])) (if (= a b) 1 2)))))
"""


def _run(tmp_path: Path, name: str, src: str, *args: str) -> subprocess.CompletedProcess:
    f = tmp_path / name
    f.write_text(src, encoding="utf-8")
    return subprocess.run(
        shlex.split(os.environ["LLMLL_BIN"]) + list(args) + ["test", str(f)],
        cwd=tmp_path, capture_output=True, text=True, timeout=TIMEOUT_S,
    )


def test_json_test_output_is_one_json_document(tmp_path):
    p = _run(tmp_path, "ffiprop.llmll", FFI, "--json")
    doc = json.loads(p.stdout)  # fails on v0.30.10: "*** Gave up!" came first
    assert doc["total"] == 1
    assert "Gave up" not in p.stdout


def test_pure_builtin_properties_are_evaluated_not_skipped(tmp_path):
    p = _run(tmp_path, "builtins.llmll", BUILTINS, "--json")
    doc = json.loads(p.stdout)
    skipped = [(r["description"], r["skip_reason"]) for r in doc["results"]
               if r["status"] == "PBTSkipped"]
    assert skipped == []
    assert doc["passed"] == doc["total"] == 15


def test_skip_reason_names_the_ffi_export(tmp_path):
    p = _run(tmp_path, "ffiprop.llmll", FFI, "--json")
    (run,) = json.loads(p.stdout)["results"]
    assert run["status"] == "PBTSkipped"
    assert "Tier 1 FFI export keys (haskell.containers, Data.Map.Strict.keys)" in run["skip_reason"]
    assert "via sort-strings" in run["skip_reason"]


def test_text_mode_prints_the_skip_reason(tmp_path):
    p = _run(tmp_path, "ffiprop.llmll", FFI)
    assert p.returncode == 0
    assert "Gave up" not in p.stdout
    assert '"sorts two": ' in p.stdout and "Tier 1 FFI export keys" in p.stdout
