"""Tests for scripts/version_gate.sh (DRIFT-CI-1 C1..C4)."""

import json
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent


def _run(script, cwd, env=None):
    import os
    e = os.environ.copy()
    if env:
        e.update(env)
    return subprocess.run(
        ["bash", script], cwd=str(cwd), env=e, capture_output=True, text=True
    )


def test_passes_on_live_repo(version_gate_script):
    """The committed tree must always satisfy the gate."""
    result = _run(version_gate_script, REPO_ROOT)
    assert result.returncode == 0, (
        f"version_gate.sh failed on the live tree:\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )
    assert "DRIFT-CI-1 PASS" in result.stdout


def test_passes_on_synth_repo(version_gate_script, synth_repo):
    result = _run(version_gate_script, synth_repo, env={"REPO_ROOT": str(synth_repo)})
    assert result.returncode == 0, f"stderr: {result.stderr}"
    assert "v9.9.9" in result.stdout


def test_fails_when_readme_banner_mutated(version_gate_script, synth_repo):
    (synth_repo / "README.md").write_text("# LLMLL — v9.9.8\n\nbody\n")
    result = _run(version_gate_script, synth_repo, env={"REPO_ROOT": str(synth_repo)})
    assert result.returncode == 1
    assert "C1" in result.stderr
    assert "README.md banner" in result.stderr


def test_fails_when_llmll_banner_mutated(version_gate_script, synth_repo):
    (synth_repo / "LLMLL.md").write_text("# LLMLL: title (v9.9.7)\n\nbody\n")
    result = _run(version_gate_script, synth_repo, env={"REPO_ROOT": str(synth_repo)})
    assert result.returncode == 1
    assert "C1" in result.stderr


def test_fails_when_changelog_top_mutated(version_gate_script, synth_repo):
    (synth_repo / "CHANGELOG.md").write_text(
        "# CHANGELOG\n\n## v9.9.6 — synthetic\n\nbody\n"
    )
    result = _run(version_gate_script, synth_repo, env={"REPO_ROOT": str(synth_repo)})
    assert result.returncode == 1
    assert "C2" in result.stderr


def test_fails_when_package_yaml_mutated(version_gate_script, synth_repo):
    (synth_repo / "compiler" / "package.yaml").write_text(
        "name: llmll\nversion:             9.9.5\n"
    )
    result = _run(version_gate_script, synth_repo, env={"REPO_ROOT": str(synth_repo)})
    assert result.returncode == 1
    assert "C1" in result.stderr
    assert "package.yaml" in result.stderr


def test_fails_when_cabal_mutated(version_gate_script, synth_repo):
    (synth_repo / "compiler" / "llmll.cabal").write_text(
        "cabal-version:  1.12\nname:           llmll\nversion:        9.9.4\n"
    )
    result = _run(version_gate_script, synth_repo, env={"REPO_ROOT": str(synth_repo)})
    assert result.returncode == 1
    assert "C1" in result.stderr
    assert "llmll.cabal" in result.stderr


def test_fails_when_schema_version_mismatched(version_gate_script, synth_repo):
    schema_path = synth_repo / "docs" / "llmll-ast.schema.json"
    schema = json.loads(schema_path.read_text())
    schema["$defs"]["Program"]["properties"]["schemaVersion"]["const"] = "0.6.0"
    schema_path.write_text(json.dumps(schema, indent=2))
    result = _run(version_gate_script, synth_repo, env={"REPO_ROOT": str(synth_repo)})
    assert result.returncode == 1
    assert "C3" in result.stderr


def test_fails_when_parser_expected_version_mismatched(version_gate_script, synth_repo):
    parser_path = synth_repo / "compiler" / "src" / "LLMLL" / "ParserJSON.hs"
    parser_path.write_text(
        'module LLMLL.ParserJSON where\n\n'
        'expectedSchemaVersion :: Text\n'
        'expectedSchemaVersion = "0.6.0"\n'
    )
    result = _run(version_gate_script, synth_repo, env={"REPO_ROOT": str(synth_repo)})
    assert result.returncode == 1
    assert "C3" in result.stderr


def test_fails_when_schema_id_url_misaligned(version_gate_script, synth_repo):
    schema_path = synth_repo / "docs" / "llmll-ast.schema.json"
    schema = json.loads(schema_path.read_text())
    schema["$id"] = "https://llmll.dev/schemas/v0.4/ast.schema.json"
    schema_path.write_text(json.dumps(schema, indent=2))
    result = _run(version_gate_script, synth_repo, env={"REPO_ROOT": str(synth_repo)})
    assert result.returncode == 1
    assert "C4" in result.stderr
    assert "/schemas/v0.5/" in result.stderr


def test_extracts_semver_not_substring(version_gate_script, synth_repo):
    """Banners with extra trailing version-like text in the title don't trip."""
    (synth_repo / "README.md").write_text(
        "# LLMLL — v9.9.9 (release notes for v1.0.0 candidates)\n\nbody\n"
    )
    result = _run(version_gate_script, synth_repo, env={"REPO_ROOT": str(synth_repo)})
    assert result.returncode == 0, (
        "head -1 + first-match grep should pick v9.9.9, not v1.0.0:\n"
        f"stderr: {result.stderr}"
    )
