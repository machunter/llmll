"""DRIFT-DOC-4: the checks that do not need the LLMLL gate built.

`scripts/doc_path_lint_cover.py` is the acceptance cover and it needs a
toolchain: it builds nothing itself but takes a compiled `pathlint` binary and
runs it over 24 trees. That is the right home for every decision the gate makes,
because only a run settles them. It is the wrong home for everything below, each
of which is a way the cover stops grading with all 24 cells still green.

WHY THIS FILE EXISTS AT ALL, and it is a gap this campaign has now found twice.
TOOL-RFC-005's retirement deleted `test_doc_path_lint.py` on 2026-08-11 and put
nothing in its place, so the port had no pytest and, from 2026-08-12, no cover
either. TOOL-RFC-002's retirement found the same shape from the other side: its
cover pinned a list against the port and nothing checked that the two lists
still matched. The lesson both times: A COVER IS AN INSTRUMENT AND NOTHING WAS
CHECKING THE INSTRUMENT WAS STILL CONNECTED.

Three things are settleable without a toolchain:

  * THE COVER IS RUN BY CI, and it is run from the job that has a toolchain.
    A cover nothing invokes grades nothing. DRIVER-LL 4c shipped one of those
    and `test_version_gate_ll.py` carries the same assertion for its own cover;

  * THE COVER'S ALLOW PAIR IS REALLY IN THE PORT'S TABLE. Cell 16 asserts that
    a (file, path) pair is suppressed and cell 16b that a near miss is not. Both
    are silently meaningless if the pair leaves `allow-tbl`: cell 16 would then
    be testing an ordinary resolving citation and would keep passing. This is
    the direct analogue of the FAMILIES parity guard TOOL-RFC-002 added;

  * THE COVER'S CORPUS STILL MATCHES THE PORT'S FILTERS. `BASE` carries one
    file per filter rule so that F1 and F2 are reachable. If the port renames a
    prefix, those cells stop testing what they claim and no cell fails.
"""

from __future__ import annotations

import pathlib
import re

REPO = pathlib.Path(__file__).resolve().parents[2]
PORT = REPO / "tools" / "doc-path-lint" / "pathlint.llmll"
COVER = REPO / "scripts" / "doc_path_lint_cover.py"
WORKFLOW = REPO / ".github" / "workflows" / "version-gate.yml"


def _cover_const(name: str) -> str:
    """One `NAME = "value"` string constant, read as text.

    Read rather than imported: importing the cover would execute its module
    body, and the point of these checks is that they run in the fast job with
    nothing built.
    """
    m = re.search(rf'^{name} = "([^"]+)"', COVER.read_text(), re.M)
    assert m, f"{name} is not a string constant in doc_path_lint_cover.py"
    return m.group(1)


def test_cover_runs_in_ci_from_the_toolchain_job():
    """The cover is invoked, with a gate, in `spec-roundtrip`.

    The job matters and is not a detail. `version-gate` deliberately carries no
    Haskell toolchain, so a cover wired there could never build a subject to
    grade. TOOL-RFC-005 §3 put both DRIFT-DOC-4 steps in `spec-roundtrip` for
    that reason and the campaign's retirement condition 2 asks the same question
    of every job that runs a reference.
    """
    wf = WORKFLOW.read_text()
    assert "scripts/doc_path_lint_cover.py" in wf, \
        "version-gate.yml does not run the DRIFT-DOC-4 cover"

    job = wf.split("spec-roundtrip:", 1)
    assert len(job) == 2, "version-gate.yml has no spec-roundtrip job"
    assert "scripts/doc_path_lint_cover.py" in job[1], \
        "the cover runs outside spec-roundtrip, which is the job with a toolchain"

    line = next(ln for ln in wf.splitlines()
                if "scripts/doc_path_lint_cover.py" in ln and "python3" in ln)
    assert "--gate" in line, \
        f"the cover is invoked without --gate, so it grades nothing: {line.strip()}"


def test_cover_allow_pair_is_in_the_port_table():
    """Cells 16 and 16b rest on this pair being a real ALLOW entry.

    The port stores the table as tab-separated `file\\tpath` pairs inside a
    string literal. If the entry goes, cell 16 keeps passing for the wrong
    reason: it would assert that an ordinary resolving citation resolves.
    """
    f, p = _cover_const("ALLOW_FILE"), _cover_const("ALLOW_PATH")
    assert f"{f}\\t{p}\\n" in PORT.read_text(), (
        f"the cover's ALLOW pair ({f} -> {p}) is not in pathlint.llmll's "
        "allow-tbl, so cell 16 no longer tests suppression")


def test_cover_corpus_reaches_every_filter_prefix():
    """Each filter the port names has a file in the cover's corpus.

    F1 excludes `site/` and `node_modules/`; F2 excludes `CHANGELOG.md`,
    `/runs/`, `/postmortem-`, `docs/archive/` and `/findings/`. The cover does
    not need one file per prefix, but the two it grades cells on must be
    present, or cells 10 to 13 stop testing the rules they name.
    """
    cover = COVER.read_text()
    base = cover.split("BASE = {", 1)[1].split("}", 1)[0]
    for prefix in ("site/", "CHANGELOG.md", "docs/archive/", "/runs/"):
        assert prefix in base, \
            f"the cover's BASE corpus has no file matching {prefix}"
        assert prefix in PORT.read_text(), \
            f"the port no longer names {prefix}, so the cover's cell is stale"
