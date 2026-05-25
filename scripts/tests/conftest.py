"""Shared pytest fixtures for DRIFT-CI-1 harness tests."""

import os
import stat
import subprocess
import sys
import textwrap
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
SCRIPTS = REPO_ROOT / "scripts"


@pytest.fixture
def version_gate_script():
    return str(SCRIPTS / "version_gate.sh")


@pytest.fixture
def spec_roundtrip_script():
    return str(SCRIPTS / "spec_roundtrip.py")


@pytest.fixture
def synth_repo(tmp_path):
    """A minimal repo tree with banner-equal versions and a valid schema/parser.

    Mutation in individual tests drives version_gate.sh into failure modes.
    """
    root = tmp_path / "repo"
    (root / "compiler" / "src" / "LLMLL").mkdir(parents=True)
    (root / "docs").mkdir(parents=True)

    (root / "README.md").write_text("# LLMLL — v9.9.9\n\nbody\n")
    (root / "LLMLL.md").write_text("# LLMLL: title (v9.9.9)\n\nbody\n")
    (root / "CHANGELOG.md").write_text(
        "# CHANGELOG\n\n## v9.9.9 — synthetic (2099-01-01)\n\nbody\n"
    )
    (root / "compiler" / "package.yaml").write_text(
        "name: llmll\nversion:             9.9.9\n"
    )
    (root / "compiler" / "llmll.cabal").write_text(
        "cabal-version:  1.12\nname:           llmll\nversion:        9.9.9\n"
    )
    (root / "compiler" / "src" / "LLMLL" / "ParserJSON.hs").write_text(
        'module LLMLL.ParserJSON where\n\n'
        'expectedSchemaVersion :: Text\n'
        'expectedSchemaVersion = "0.5.0"\n'
    )
    (root / "docs" / "llmll-ast.schema.json").write_text(
        '{\n'
        '  "$id": "https://llmll.dev/schemas/v0.5/ast.schema.json",\n'
        '  "$defs": {\n'
        '    "Program": {\n'
        '      "properties": {\n'
        '        "schemaVersion": { "const": "0.5.0" }\n'
        '      }\n'
        '    }\n'
        '  }\n'
        '}\n'
    )
    return root


def _write_stub(path: Path, body: str) -> str:
    path.write_text(body)
    path.chmod(path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    return f"{sys.executable} {path}"


@pytest.fixture
def llmll_stub_pass(tmp_path):
    """Always exits 0."""
    return _write_stub(
        tmp_path / "llmll_stub_pass.py",
        textwrap.dedent('''\
            #!/usr/bin/env python3
            import sys
            sys.exit(0)
        '''),
    )


@pytest.fixture
def llmll_stub_fail(tmp_path):
    """Always exits 1 with a synthetic diagnostic."""
    return _write_stub(
        tmp_path / "llmll_stub_fail.py",
        textwrap.dedent('''\
            #!/usr/bin/env python3
            import sys
            print("synthetic parse error", file=sys.stderr)
            sys.exit(1)
        '''),
    )


@pytest.fixture
def llmll_stub_content_based(tmp_path):
    """Pass unless the input file contains 'BAD'; useful for per-block routing."""
    return _write_stub(
        tmp_path / "llmll_stub_content.py",
        textwrap.dedent('''\
            #!/usr/bin/env python3
            import sys
            # argv: ["check", <path>, [..flags]]
            assert sys.argv[1] == "check"
            body = open(sys.argv[2]).read()
            if "BAD" in body:
                print("contains BAD token", file=sys.stderr)
                sys.exit(1)
            sys.exit(0)
        '''),
    )


@pytest.fixture
def llmll_stub_strict_aware(tmp_path):
    """Pass unless --strict is set; lets tests assert flag pass-through."""
    return _write_stub(
        tmp_path / "llmll_stub_strict.py",
        textwrap.dedent('''\
            #!/usr/bin/env python3
            import sys
            if "--strict" in sys.argv:
                print("strict mode active", file=sys.stderr)
                sys.exit(1)
            sys.exit(0)
        '''),
    )


def run_script(script: str, cwd: Path, env_overrides=None):
    env = os.environ.copy()
    if env_overrides:
        env.update(env_overrides)
    return subprocess.run(
        ["bash", script] if script.endswith(".sh") else [sys.executable, script],
        cwd=str(cwd),
        env=env,
        capture_output=True,
        text=True,
    )


@pytest.fixture
def run_script_fn():
    return run_script
