"""TRUST-AXIOM: a sealed builtin's assumed fact reaches a channel of the trust
report instead of reaching only the solver.

WHAT THE SILENCE WAS. `(bytes-zero)` emits the axiom `bytesLen(r) = n` and
`(bytes-set b i v)` emits `bytesLen(r) = bytesLen(b)`. Both are ASSUME-polarity
facts about sealed builtins. No solver discharges either. Both are valid only
because codegen reads the same annotation to emit the value they describe, so
both ride the `codegen_semantics_version` stamp. Before this change the trust
report printed `post: verified (liquid-fixpoint)` and named neither lemma, so a
reader could not tell that a `verified` tier carried a trust-channel dependency.

THE DISCLOSURE IS NOT A TIER CHANGE. No verdict moves and no function leaves
`--strict-verified-core` admission. These cells assert the report's CONTENT,
never its verdict.

WHICH PATH DISCLOSES, AND WHY. The rows come from the emitted body VC, so they
exist only on a path that RUNS THE EMITTER. Plain `--trust-report` is a
sidecar-only read: it reports evidence from `.verified.json` without re-running
emission, and it already says so in its own footer. `--strict-verify` runs the
emitter, and that is the path asserted here. Cell 4 pins the sidecar-only path
explicitly so the difference is recorded rather than discovered again later.

THE FIXTURE IS COPIED TO A TEMPORARY DIRECTORY. `llmll verify --strict-verify`
WRITES a `.verified.json` sidecar beside the program it verifies. Running it
against `examples/` in place would dirty the working tree, so every cell runs
against a copy.

On macOS a toolchain SDK mismatch makes the link step fail. MacOSX27.0.sdk
ships .tbd files the linker rejects ("unknown architecture"); export SDKROOT to
MacOSX26.5.sdk before running these locally. The environment is inherited, so
an exported SDKROOT reaches the child.
"""

from __future__ import annotations

import json
import os
import shlex
import shutil
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
ZERO_BUFFER = REPO_ROOT / "examples" / "bytes-bounds" / "zero-buffer.llmll"

pytestmark = pytest.mark.skipif(
    not os.environ.get("LLMLL_BIN"),
    reason="set LLMLL_BIN to a built llmll; the spec-roundtrip job runs this in CI",
)

# A verify run invokes liquid-fixpoint. Generous relative to the work.
VERIFY_TIMEOUT_S = 300

# The trust report's emit version. TRUST-AXIOM adds `builtin_axioms` as an
# ADDITIVE per-entry key, so this must NOT move (the `harness_assumptions`
# precedent, stated at the JSON emitter in TrustReport.hs). A cell asserts it,
# because an accidental change here silently breaks every consumer.
TRUST_REPORT_VERSION = "1.6.0"

# A bytes-free and map-free program. It must disclose nothing, which is what
# proves the activation gate is inherited rather than mirrored.
ARITH_SRC = "(def add1 [n: int] -> int (post (> result n)) (+ n 1))\n"


def _llmll() -> list[str]:
    return shlex.split(os.environ["LLMLL_BIN"])


def _verify(workdir: Path, prog: Path, *extra: str) -> str:
    p = subprocess.run(
        [*_llmll(), "verify", str(prog), "--trust-report", *extra],
        capture_output=True,
        text=True,
        timeout=VERIFY_TIMEOUT_S,
        cwd=str(workdir),
    )
    assert p.returncode == 0, f"verify failed rc={p.returncode}\n{p.stderr[-2000:]}"
    return p.stdout


@pytest.fixture(scope="module")
def zero_buffer_copy(tmp_path_factory) -> Path:
    """A private copy, so the sidecar write never touches examples/."""
    d = tmp_path_factory.mktemp("trust-axiom")
    dst = d / "zero-buffer.llmll"
    shutil.copyfile(ZERO_BUFFER, dst)
    return dst


@pytest.fixture(scope="module")
def arith_prog(tmp_path_factory) -> Path:
    d = tmp_path_factory.mktemp("trust-axiom-arith")
    dst = d / "arith.llmll"
    dst.write_text(ARITH_SRC, encoding="utf-8")
    return dst


def test_the_bytes_zero_axiom_is_named_in_the_trust_report(zero_buffer_copy):
    """Cell 1: the constructor axiom appears, with its length and its stamp.

    Before TRUST-AXIOM this output carried `post: verified (liquid-fixpoint)`
    and named the lemma nowhere.
    """
    out = _verify(zero_buffer_copy.parent, zero_buffer_copy, "--strict-verify")
    assert "bytes-zero" in out, out[-3000:]
    # The LENGTH conjunct is the axiom. Without it the length is not derivable
    # at all, because Map_default carries none.
    assert "(bytesLen result) = 32" in out, out[-3000:]
    assert "codegen-determined" in out, out[-3000:]
    assert "codegen_semantics_version" in out, out[-3000:]
    # The reader must be told this was ASSUMED, not proved. The wording is
    # shared with the FS-STAT-1 assumed-fact line on purpose.
    assert "ASSUMED, not proved" in out, out[-3000:]


def test_the_binder_reads_as_result_not_the_emission_counter(zero_buffer_copy):
    """Cell 2: the row renders `result`, never `_bv_call_bytes_zero_0`.

    The emitted name is the alpha-renaming counter's and is an artifact of
    emission order, so it tells a reader nothing.
    """
    out = _verify(zero_buffer_copy.parent, zero_buffer_copy, "--strict-verify")
    assert "_bv_call" not in out, out[-3000:]


def test_json_carries_builtin_axioms_without_moving_the_emit_version(zero_buffer_copy):
    """Cell 3: the additive key is present and `trust_report_version` is fixed."""
    out = _verify(zero_buffer_copy.parent, zero_buffer_copy, "--strict-verify", "--json")
    doc = None
    for line in out.splitlines():
        line = line.strip()
        if line.startswith("{") and "trust_report_version" in line:
            doc = json.loads(line)
            break
    assert doc is not None, f"no trust-report JSON object in output\n{out[-3000:]}"

    assert doc["trust_report_version"] == TRUST_REPORT_VERSION

    entries = doc.get("functions") or doc.get("entries") or []
    named = [e for e in entries if e.get("name") == "make-buffer"]
    assert named, f"make-buffer entry missing\n{json.dumps(doc)[:3000]}"

    rows = named[0].get("builtin_axioms")
    assert rows, f"builtin_axioms absent on make-buffer\n{json.dumps(named[0])[:3000]}"
    assert any(r["builtin"] == "bytes-zero" for r in rows), rows
    assert all(r["category"] == "codegen-determined" for r in rows), rows
    assert all(r["stamp"] == "codegen_semantics_version" for r in rows), rows


def test_the_sidecar_only_path_does_not_invent_rows(zero_buffer_copy):
    """Cell 4: plain `--trust-report` runs no emitter, so it names no axiom.

    This is the CORRECT behaviour, not a gap in the disclosure: that path reads
    `.verified.json` and never rebuilds the body VC, so it has no axiom set to
    report. It already discloses its own limitation in its footer. The cell
    exists so the path difference is pinned rather than rediscovered.
    """
    # Seed the sidecar with a strict run first, then read it back without one.
    _verify(zero_buffer_copy.parent, zero_buffer_copy, "--strict-verify")
    out = _verify(zero_buffer_copy.parent, zero_buffer_copy)
    assert "sidecar-only report" in out, out[-3000:]
    assert "codegen_semantics_version" not in out, out[-3000:]


def test_a_bytes_free_program_discloses_no_axiom(arith_prog):
    """Cell 5, the negative control for the activation gate.

    A body with no bytes or map operation must produce no row and no key, so a
    report over such a module is byte-identical to its pre-change form.
    """
    out = _verify(arith_prog.parent, arith_prog, "--strict-verify")
    assert "codegen_semantics_version" not in out, out[-3000:]
    assert "ASSUMED, not proved" not in out, out[-3000:]

    out_json = _verify(arith_prog.parent, arith_prog, "--strict-verify", "--json")
    assert "builtin_axioms" not in out_json, out_json[-3000:]


# ---------------------------------------------------------------------------
# TRUST-AXIOM propagation (D1/D2(c)/D3): the axiom set crosses a module boundary
#
# A caller's run never emits its callee's body VC, so it cannot recompute what
# the callee assumed. The callee's sidecar is the only source. These cells pin
# both halves of that: the recorded case, and the case where the callee's
# sidecar predates the disclosure and the set is UNKNOWN rather than empty.
#
# Same-module sibling `def` calls are inadmissible in strict-core bodies, so
# propagation is inherently CROSS-MODULE and these cells need two files.
# ---------------------------------------------------------------------------

CALLEE_SRC = """(export make-buffer)
(def make-buffer [] -> bytes[32]
  (post (= (bytes-length result) 32))
  (bytes-zero))
"""

CALLER_SRC = """(import buf)
(open buf)
(def use-buffer [] -> int
  (post (= result 32))
  (bytes-length (make-buffer)))
"""


@pytest.fixture(scope="module")
def two_module_program(tmp_path_factory) -> Path:
    """The callee is verified first, so its sidecar exists when the caller runs."""
    d = tmp_path_factory.mktemp("trust-axiom-prop")
    (d / "buf.llmll").write_text(CALLEE_SRC, encoding="utf-8")
    (d / "use.llmll").write_text(CALLER_SRC, encoding="utf-8")
    _verify(d, d / "buf.llmll", "--strict-verify")
    return d


def test_the_callee_records_its_axiom_set_in_the_sidecar(two_module_program):
    """Cell 6: the sidecar carries the set and the unconditional marker."""
    doc = json.loads((two_module_program / "buf.llmll.verified.json").read_text())
    assert doc["axiom_disclosure_version"] == "1"
    assert doc["builtin_axioms"]["make-buffer"] == ["bytes-zero"]


def test_the_caller_inherits_the_callee_axiom(two_module_program):
    """Cell 7: the caller names an axiom its own body never used.

    Before propagation this report carried zero `assumes` lines while
    `use-buffer`'s whole post rested on the constructor axiom.
    """
    out = _verify(two_module_program, two_module_program / "use.llmll", "--strict-verify")
    assert "inherits bytes-zero via make-buffer" in out, out[-3000:]
    assert "ASSUMED, not proved" in out, out[-3000:]


def test_an_unrecorded_callee_reads_as_unknown_not_empty(two_module_program, tmp_path):
    """Cell 8, the fail-closed half, and the reason the marker is unconditional.

    A sidecar written before the disclosure carries no axiom set. Reporting
    silence there would claim the callee assumes nothing, when the truth is
    that nobody wrote it down. INT-1 made exactly this mistake in reverse; see
    the commentary above `sidecarNeedsRevalidation` in VerifiedCache.hs.
    """
    d = tmp_path / "unrecorded"
    shutil.copytree(two_module_program, d)
    sidecar = d / "buf.llmll.verified.json"
    doc = json.loads(sidecar.read_text())
    doc.pop("axiom_disclosure_version", None)
    doc.pop("builtin_axioms", None)
    sidecar.write_text(json.dumps(doc), encoding="utf-8")

    out = _verify(d, d / "use.llmll", "--strict-verify")
    assert "UNRECORDED" in out, out[-3000:]
    assert "unknown, not empty" in out, out[-3000:]
    # It must NOT silently claim the callee is axiom-free.
    assert "inherits bytes-zero" not in out, out[-3000:]


def test_one_row_per_builtin_not_per_occurrence(tmp_path):
    """Cell 9 (D4): a three-read body discloses one row, not three.

    The three rows differed only in an index literal and all asserted that
    `bytes-get` reflects to `Map_select`. What a reader needs is the SET.
    """
    prog = tmp_path / "rmw.llmll"
    prog.write_text(
        "(def sum3 [b: bytes[8]] -> int\n"
        "  (post (>= result 0))\n"
        "  (+ (+ (bytes-get b 0) (bytes-get b 1)) (bytes-get b 2)))\n",
        encoding="utf-8")
    out = _verify(tmp_path, prog, "--strict-verify")
    assert out.count("≈ assumes bytes-get") == 1, out[-3000:]
