"""SCHEMA-TRUTH-1 (SCHEMA-VALID-1): what the compiler emits satisfies docs/llmll-ast.schema.json.

WHAT THE DEFECT WAS. The published JSON-AST schema was read by no script, and
zero of the 96 tracked `.ast.json` documents validated against it
(docs/design/schema-truth-proposal.md). Measured on v0.26.6 before the fix, the
schema also rejected 81 of the 384 documents the CURRENT compiler emits from
the tracked `.llmll` sources: identifier names with `?` or a leading `_`, the
empty `(export)` the spec uses, and the unnamed parameters of a `fn-type`.

THE POPULATION IS EMITTED DOCUMENTS, NOT COMMITTED ONES. A committed document
is an artifact some past release wrote; an old shape in it is history, not
drift. So the gate runs `llmll build --emit` over every tracked `.llmll` file
and validates each document it writes. That makes the claim narrower than
"every document is valid": it says the compiler's own output is, and nothing
about JSON-AST an agent writes by hand.

WHY VALIDATION IS AFFORDABLE NOW. The statement, type, expression, pattern and
hole unions were undiscriminated `oneOf`, and a 10 KB document did not finish in
120 s. They now dispatch on `kind` with `if`/`then`, so each node is checked
against one branch: the 1.3 MB driver document validates in about 3 s.

WHAT MAY FAIL, AND ONLY WITH A NAME.
  * A source that does not emit must declare `@expect: parse-error`, or be in
    NO_EMIT with its reason.
  * An emitted document the schema rejects must be in KNOWN_INVALID with the
    roadmap row and the message it fails with. SV-2 requires it to KEEP
    failing that way, so a fix forces the entry out rather than leaving an
    exemption behind.

WHY IT SKIPS WITHOUT A BINARY. Every cell calls `llmll build --emit`. The
spec-roundtrip job runs this file with LLMLL_BIN set and jsonschema installed,
and refuses a run where a cell skipped.
"""

from __future__ import annotations

import concurrent.futures as cf
import json
import os
import subprocess
from pathlib import Path

import pytest

pytestmark = pytest.mark.skipif(
    not os.environ.get("LLMLL_BIN"),
    reason="set LLMLL_BIN to a built llmll; the spec-roundtrip job runs this in CI",
)

REPO = Path(__file__).resolve().parents[2]
SCHEMA = REPO / "docs" / "llmll-ast.schema.json"

# Tracked sources that do not emit, and do not say so in an @expect header.
NO_EMIT: dict[str, str] = {}

# Emitted documents the schema rejects because the COMPILER is wrong, each with
# its open roadmap row and a fragment of the message it must keep failing with.
KNOWN_INVALID = {
    "scripts/doc-claims/unicode-alias-token.llmll":
        ("ALIAS-LOWER-1", "is not one of"),
}

# MODE-HTTP-1 defect (iii), the proposal's section 7.2 witness: the emitter
# writes "http:9000", and DefMain.mode is a console/cli string or a
# {"kind": "http", "port": N} object. No tracked program uses http mode, so the
# witness is built here.
HTTP_WITNESS = """\
(def-shell step [s: int i: string] -> int s)
(def-main
  :mode http 9000
  :init 0
  :step step)
"""


# Constructs the compiler emits that no tracked source happens to use, so SV-1
# never sees them. The unit literal `()` emits `"lit-unit"`, which the schema
# did not list until the orchestra repair found it through the fill prompt.
WITNESSES = {
    "unit literal": "(def-shell nothing [x: int] -> unit ())\n",
}


def _validator():
    jsonschema = pytest.importorskip("jsonschema")
    return jsonschema.Draft202012Validator(json.loads(SCHEMA.read_text(encoding="utf-8")))


def _emit(src: Path, out: Path) -> tuple[Path | None, str]:
    p = subprocess.run([os.environ["LLMLL_BIN"], "build", str(src), "--emit", "-o", str(out)],
                       capture_output=True, text=True, cwd=REPO)
    docs = sorted(out.glob("*.ast.json"))
    if p.returncode != 0 or len(docs) != 1:
        return None, (p.stdout + p.stderr)[-400:]
    return docs[0], ""


def _first_error(v, doc) -> str | None:
    from jsonschema.exceptions import best_match
    e = best_match(v.iter_errors(doc))
    if e is None:
        return None
    return f"{'/'.join(map(str, e.absolute_path))}: {e.message[:200]}"


def _tracked_sources() -> list[str]:
    out = subprocess.run(["git", "ls-files", "*.llmll"], capture_output=True, text=True,
                         cwd=REPO, check=True).stdout.split()
    assert out, "git ls-files found no .llmll sources; the gate would validate nothing"
    return out


def _declares_parse_error(rel: str) -> bool:
    head = (REPO / rel).read_text(encoding="utf-8", errors="replace").splitlines()[:10]
    return any("@expect: parse-error" in ln for ln in head)


@pytest.fixture(scope="module")
def results(tmp_path_factory):
    v = _validator()
    root = tmp_path_factory.mktemp("emit")
    srcs = _tracked_sources()

    def one(i_rel):
        i, rel = i_rel
        doc_path, why = _emit(REPO / rel, root / f"{i:04d}")
        if doc_path is None:
            return rel, None, why
        return rel, _first_error(v, json.loads(doc_path.read_text(encoding="utf-8"))), ""

    with cf.ThreadPoolExecutor(max_workers=os.cpu_count() or 4) as ex:
        rows = list(ex.map(one, enumerate(srcs)))
    return rows


def test_sv1_every_emitted_document_validates(results):
    no_emit, invalid, valid = [], [], 0
    for rel, err, why in results:
        if err is None and why:
            if rel not in NO_EMIT and not _declares_parse_error(rel):
                no_emit.append(f"{rel}: {why}")
        elif err is not None:
            if rel not in KNOWN_INVALID:
                invalid.append(f"{rel}: {err}")
        else:
            valid += 1
    assert not no_emit, "tracked sources that do not emit and do not declare it:\n" + "\n".join(no_emit)
    assert not invalid, "emitted documents the schema rejects:\n" + "\n".join(invalid)
    # Positive evidence: the gate validated a real population, not an empty one.
    assert valid >= 300, f"only {valid} emitted documents validated; the population collapsed"


def test_sv2_known_invalid_entries_still_fail_as_recorded(results):
    by_src = {rel: (err, why) for rel, err, why in results}
    for rel, (row, fragment) in KNOWN_INVALID.items():
        assert rel in by_src, f"{rel} ({row}) is no longer tracked; remove its entry"
        err, why = by_src[rel]
        assert not why, f"{rel} ({row}) no longer emits: {why}"
        assert err is not None, f"{rel} now validates; {row} may be fixed, so remove its KNOWN_INVALID entry"
        assert fragment in err, f"{rel} fails differently than recorded for {row}: {err}"
    for rel in NO_EMIT:
        assert rel in by_src, f"{rel} is no longer tracked; remove its NO_EMIT entry"
        assert by_src[rel][1], f"{rel} now emits; remove its NO_EMIT entry"


def test_sv3_mode_http_witness_is_rejected(tmp_path):
    """MODE-HTTP-1 (iii): pinned so that its fix flips this cell and the row's record with it."""
    v = _validator()
    src = tmp_path / "http_witness.llmll"
    src.write_text(HTTP_WITNESS)
    doc_path, why = _emit(src, tmp_path / "out")
    assert doc_path is not None, f"the http witness no longer emits: {why}"
    doc = json.loads(doc_path.read_text(encoding="utf-8"))
    modes = [s.get("mode") for s in doc["statements"] if s.get("kind") == "def-main"]
    assert modes == ["http:9000"], f"the emitter's http mode changed to {modes}; revisit MODE-HTTP-1"
    err = _first_error(v, doc)
    assert err is not None and "mode" in err, f"the schema now accepts {modes}; revisit MODE-HTTP-1: {err}"


def test_sv4_negative_control_the_validator_rejects_a_broken_document(tmp_path):
    """A gate that accepts everything agrees with everything. Break a valid emit two ways."""
    v = _validator()
    src = REPO / "examples" / "hangman_sexp" / "hangman.llmll"
    doc_path, why = _emit(src, tmp_path / "out")
    assert doc_path is not None, why
    doc = json.loads(doc_path.read_text(encoding="utf-8"))
    assert _first_error(v, doc) is None, "the control document itself must validate"

    unknown_kind = json.loads(json.dumps(doc))
    unknown_kind["statements"][0]["kind"] = "def-logic"
    err = _first_error(v, unknown_kind)
    assert err is not None and "is not one of" in err, err

    missing_field = json.loads(json.dumps(doc))
    stmt = next(s for s in missing_field["statements"] if s["kind"] in ("def", "def-shell"))
    del stmt["body"]
    err = _first_error(v, missing_field)
    assert err is not None and "'body' is a required property" in err, err


@pytest.mark.parametrize("label", sorted(WITNESSES))
def test_sv5_witness_programs_emit_valid_documents(tmp_path, label):
    v = _validator()
    src = tmp_path / "witness.llmll"
    src.write_text(WITNESSES[label])
    doc_path, why = _emit(src, tmp_path / "out")
    assert doc_path is not None, f"the {label} witness no longer emits: {why}"
    err = _first_error(v, json.loads(doc_path.read_text(encoding="utf-8")))
    assert err is None, f"the schema rejects the {label} witness: {err}"
