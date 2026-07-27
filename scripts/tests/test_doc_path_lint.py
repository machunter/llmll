"""Tests for scripts/doc_path_lint.py (DRIFT-DOC-4, advisory prose-path lint).

The exclusion predicates are what make this lint usable rather than noise, so they
are tested directly. Without them the same scan reports roughly 450 findings, and
most of them are correct prose.
"""

import importlib.util
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
LINT = REPO_ROOT / "scripts" / "doc_path_lint.py"


def _module():
    spec = importlib.util.spec_from_file_location("doc_path_lint", LINT)
    assert spec is not None and spec.loader is not None
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def test_clean_on_live_repo():
    """The committed tree must have no unresolved prose path citations.

    This is the regression guard the lint exists for: move a file without updating
    the prose that names it and this test goes red.
    """
    r = subprocess.run([sys.executable, str(LINT)], cwd=str(REPO_ROOT),
                       capture_output=True, text=True)
    assert r.returncode == 0
    assert "all resolve" in r.stdout, (
        f"unresolved prose path citations on the live tree:\n{r.stdout}"
    )


def test_advisory_exit_contract():
    """Exit 0 is the contract. See the module docstring for why it must not fail."""
    r = subprocess.run([sys.executable, str(LINT)], cwd=str(REPO_ROOT),
                       capture_output=True, text=True)
    assert r.returncode == 0


def test_strict_env_is_available_for_local_use():
    """STRICT=1 opts in to a nonzero exit; CI deliberately does not set it."""
    src = LINT.read_text()
    assert "os.environ.get('STRICT')" in src


class TestHistoricalFile:
    """Documents that describe the tree AS IT WAS are excluded wholesale."""

    def test_postmortem_excluded(self):
        f = _module().historical_file
        assert f("experiments/repair-loop/findings/postmortem-001-apparatus.md")

    def test_frozen_run_record_excluded(self):
        assert _module().historical_file("experiments/rfc-swarm/runs/rfc826/REPORT.md")

    def test_changelog_excluded(self):
        assert _module().historical_file("CHANGELOG.md")

    def test_archived_doc_excluded(self):
        assert _module().historical_file("docs/archive/shipped-design-specs/x.md")

    def test_living_findings_md_included(self):
        """findings.md is living and gets linted; findings/ subfiles do not."""
        f = _module().historical_file
        assert not f("experiments/repair-loop/findings.md")
        assert f("experiments/repair-loop/findings/language-team.md")

    def test_ordinary_design_doc_included(self):
        assert not _module().historical_file("docs/design/oblig-0-spec.md")


class TestPlaceholder:
    """Patterns are not citations."""

    def test_numeric_metavariables(self):
        p = _module().PLACEHOLDER
        assert p.search("findings/postmortem-NNN.md")
        assert p.search("text/NNNN-name.md")
        assert p.search("turn_NN/verifier.json")
        assert p.search("cells/cell_NN/manifest.json")

    def test_elided_path(self):
        assert _module().PLACEHOLDER.search("runs/20260512T033017Z-.../solution.llmll")

    def test_illustrative_names(self):
        p = _module().PLACEHOLDER
        assert p.search("shipped-design-specs/v0.14/foo.md")
        assert p.search("src/FFI/Mylib.hs")

    def test_real_path_is_not_a_placeholder(self):
        assert not _module().PLACEHOLDER.search("docs/design/oblig-0-spec.md")


class TestHistoricalLine:
    """A living document can hold a historical sentence."""

    def test_done_moved_row(self):
        """UPDATE-PROTOCOL's archive table: rewriting the cited path would turn
        'X moved to Y' into 'Y moved to Y'."""
        h = _module().HIST_LINE
        assert h.search("| `docs/design/x.md` | ships | **DONE** moved to shipped-design-specs/ |")

    def test_other_past_tense_markers(self):
        h = _module().HIST_LINE
        for s in ("formerly at", "previously `a/b.md`", "archived to", "migrated from",
                  "removed 2026-07-18", "old path"):
            assert h.search(s), s

    def test_plain_reference_is_not_historical(self):
        assert not _module().HIST_LINE.search("see `docs/design/oblig-0-spec.md` for the schema")


class TestAllowList:
    """Every ALLOW entry must be justified, since an unexplained one is
    indistinguishable from a stale citation someone gave up on."""

    def test_counterfactual_entry_present(self):
        """The path names a location that does not exist, and its non-existence is
        the point of the sentence. This is the class that keeps the lint advisory."""
        assert ("experiments/language-comparison-backlog.md",
                "experiments/repair-loop/BACKLOG.md") in _module().ALLOW

    def test_every_entry_has_a_comment(self):
        src = LINT.read_text()
        block = src.split("ALLOW = {", 1)[1].split("\n}", 1)[0]
        entries = [l for l in block.split("\n") if l.strip().startswith("('")]
        comments = [l for l in block.split("\n") if l.strip().startswith("#")]
        assert comments, "ALLOW has no explanatory comments"
        assert len(entries) >= len(comments), "more comments than entries is fine; " \
            "zero comments is not"
