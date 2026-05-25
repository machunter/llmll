"""Tests for scripts/spec_roundtrip.py (DRIFT-CI-1 C5)."""

import os
import subprocess
import sys
import textwrap
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent


def _run(script, cwd, env=None):
    e = os.environ.copy()
    if env:
        e.update(env)
    return subprocess.run(
        [sys.executable, script], cwd=str(cwd), env=e, capture_output=True, text=True
    )


def _write_spec(path: Path, body: str):
    path.write_text(textwrap.dedent(body))


def test_no_opt_in_blocks_is_pass(spec_roundtrip_script, tmp_path, llmll_stub_fail):
    spec = tmp_path / "spec.md"
    _write_spec(
        spec,
        '''\
        # Spec

        Some prose.

        ```lisp
        (def-logic foo [x: int] x)
        ```

        More prose.
        ''',
    )
    result = _run(
        spec_roundtrip_script,
        tmp_path,
        env={"LLMLL_BIN": llmll_stub_fail, "SPEC_FILE": str(spec)},
    )
    assert result.returncode == 0, f"stderr: {result.stderr}"
    assert "nothing to check" in result.stdout


def test_opt_in_block_runs_against_llmll(spec_roundtrip_script, tmp_path, llmll_stub_pass):
    spec = tmp_path / "spec.md"
    _write_spec(
        spec,
        '''\
        # Spec

        <!-- ci:roundtrip -->
        ```lisp
        (def-logic foo [x: int] x)
        ```
        ''',
    )
    result = _run(
        spec_roundtrip_script,
        tmp_path,
        env={"LLMLL_BIN": llmll_stub_pass, "SPEC_FILE": str(spec)},
    )
    assert result.returncode == 0
    assert "OK" in result.stdout
    assert "1 opt-in block(s) parsed" in result.stdout


def test_opt_in_block_fails_when_llmll_fails(
    spec_roundtrip_script, tmp_path, llmll_stub_fail
):
    spec = tmp_path / "spec.md"
    _write_spec(
        spec,
        '''\
        <!-- ci:roundtrip -->
        ```lisp
        (this is not valid)
        ```
        ''',
    )
    result = _run(
        spec_roundtrip_script,
        tmp_path,
        env={"LLMLL_BIN": llmll_stub_fail, "SPEC_FILE": str(spec)},
    )
    assert result.returncode == 1
    assert "FAIL" in result.stdout
    assert "synthetic parse error" in result.stdout


def test_blank_line_between_marker_and_fence_allowed(
    spec_roundtrip_script, tmp_path, llmll_stub_pass
):
    spec = tmp_path / "spec.md"
    _write_spec(
        spec,
        '''\
        <!-- ci:roundtrip -->

        ```lisp
        (def-logic foo [x: int] x)
        ```
        ''',
    )
    result = _run(
        spec_roundtrip_script,
        tmp_path,
        env={"LLMLL_BIN": llmll_stub_pass, "SPEC_FILE": str(spec)},
    )
    assert result.returncode == 0
    assert "1 opt-in block(s) parsed" in result.stdout


def test_marker_too_far_above_does_not_opt_in(
    spec_roundtrip_script, tmp_path, llmll_stub_fail
):
    """Two blank lines or more between marker and fence: marker does NOT apply."""
    spec = tmp_path / "spec.md"
    _write_spec(
        spec,
        '''\
        <!-- ci:roundtrip -->


        ```lisp
        (def-logic foo [x: int] x)
        ```
        ''',
    )
    result = _run(
        spec_roundtrip_script,
        tmp_path,
        env={"LLMLL_BIN": llmll_stub_fail, "SPEC_FILE": str(spec)},
    )
    assert result.returncode == 0, "unrelated marker should not opt in this block"
    assert "nothing to check" in result.stdout


def test_strict_flag_passed_through(
    spec_roundtrip_script, tmp_path, llmll_stub_strict_aware
):
    spec = tmp_path / "spec.md"
    _write_spec(
        spec,
        '''\
        <!-- ci:roundtrip: strict -->
        ```lisp
        (def-logic foo [x: int] x)
        ```
        ''',
    )
    result = _run(
        spec_roundtrip_script,
        tmp_path,
        env={"LLMLL_BIN": llmll_stub_strict_aware, "SPEC_FILE": str(spec)},
    )
    assert result.returncode == 1, "stub should refuse when --strict is passed"
    assert "strict=True" in result.stdout


def test_non_strict_does_not_pass_strict_flag(
    spec_roundtrip_script, tmp_path, llmll_stub_strict_aware
):
    spec = tmp_path / "spec.md"
    _write_spec(
        spec,
        '''\
        <!-- ci:roundtrip -->
        ```lisp
        (def-logic foo [x: int] x)
        ```
        ''',
    )
    result = _run(
        spec_roundtrip_script,
        tmp_path,
        env={"LLMLL_BIN": llmll_stub_strict_aware, "SPEC_FILE": str(spec)},
    )
    assert result.returncode == 0
    assert "strict=False" in result.stdout


def test_llmll_tag_also_recognized(
    spec_roundtrip_script, tmp_path, llmll_stub_pass
):
    spec = tmp_path / "spec.md"
    _write_spec(
        spec,
        '''\
        <!-- ci:roundtrip -->
        ```llmll
        (def-logic foo [x: int] x)
        ```
        ''',
    )
    result = _run(
        spec_roundtrip_script,
        tmp_path,
        env={"LLMLL_BIN": llmll_stub_pass, "SPEC_FILE": str(spec)},
    )
    assert result.returncode == 0
    assert "1 opt-in block(s) parsed" in result.stdout


def test_mixed_pass_and_fail(
    spec_roundtrip_script, tmp_path, llmll_stub_content_based
):
    spec = tmp_path / "spec.md"
    _write_spec(
        spec,
        '''\
        <!-- ci:roundtrip -->
        ```lisp
        (def-logic ok [x: int] x)
        ```

        Some prose.

        <!-- ci:roundtrip -->
        ```lisp
        (def-logic BAD [x: int] x)
        ```
        ''',
    )
    result = _run(
        spec_roundtrip_script,
        tmp_path,
        env={"LLMLL_BIN": llmll_stub_content_based, "SPEC_FILE": str(spec)},
    )
    assert result.returncode == 1
    assert "1 of 2 opt-in block(s) failed" in result.stderr


def test_missing_spec_file_errors(spec_roundtrip_script, tmp_path):
    result = _run(
        spec_roundtrip_script,
        tmp_path,
        env={"SPEC_FILE": str(tmp_path / "nope.md")},
    )
    assert result.returncode == 1
    assert "not found" in result.stderr
