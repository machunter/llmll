"""EXAMPLE-BUILD-1: programs that pass `llmll check` must also build.

Two causes, measured in docs/design/example-build-1-measure-findings.md:

A. `llmll build` instruments contracts before code generation, so a
   `(bytes-zero)` body with a `pre` or `post` was no longer the bare body the
   code generator gives its length to, and `bytes_zero` was emitted with no
   argument (GHC-83865).
B. The generated package was named after the file stem, so a stem such as
   `base` or `text` named a Haskell package in the dependency closure and Stack
   refused the build plan (S-4804).

WHAT EACH CELL DID AGAINST v0.27.2, measured: EB-B1 to EB-B5 FAILED.
EB-B5 also pins that the built executable keeps the file stem as its name,
which CI and the tools rely on to find a binary.

WHY IT SKIPS WITHOUT A BINARY. Each cell runs `llmll build`, which runs
`stack build` on the generated package. The spec-roundtrip job runs this file
with LLMLL_BIN set.
"""

from __future__ import annotations

import os
import shlex
import subprocess
from pathlib import Path

import pytest

pytestmark = pytest.mark.skipif(
    not os.environ.get("LLMLL_BIN"),
    reason="set LLMLL_BIN to a built llmll; the spec-roundtrip job runs this in CI "
           "(the cells call `llmll build`, which runs `stack build`)",
)

REPO = Path(__file__).resolve().parents[2]


def _run(workdir: Path, *args: str):
    llmll = shlex.split(os.environ["LLMLL_BIN"])
    return subprocess.run([*llmll, *args], cwd=workdir, capture_output=True, text=True,
                          encoding="utf-8", timeout=900)


def _copy_tracked(dest: Path, rel: str) -> Path:
    archive = subprocess.run(["git", "archive", "HEAD", rel], cwd=REPO,
                             capture_output=True, check=True)
    subprocess.run(["tar", "-x", "-C", str(dest)], input=archive.stdout, check=True)
    return dest / rel


def _build(d: Path, name: str, out: Path):
    r = _run(d, "build", name, "-o", str(out))
    assert r.returncode == 0, r.stdout[-3000:] + r.stderr[-3000:]
    return r


def test_eb_b1_zero_buffer_with_contract(tmp_path: Path):
    """EB-B1 (cause A). examples/bytes-bounds/zero-buffer.llmll: a (bytes-zero)
    body with a post, under the default --contracts=full."""
    d = _copy_tracked(tmp_path, "examples/bytes-bounds")
    _build(d, "zero-buffer.llmll", tmp_path / "out")


def test_eb_b2_bytes_zero_with_pre_only(tmp_path: Path):
    """EB-B2 (cause A). A pre alone also wraps the body."""
    (tmp_path / "prezero.llmll").write_text(
        "(def make-buffer [k: int] -> bytes[32]\n  (pre (>= k 0))\n  (bytes-zero))\n")
    _build(tmp_path, "prezero.llmll", tmp_path / "out")


def test_eb_b3_stem_base_llmll(tmp_path: Path):
    """EB-B3 (cause B). examples/refine-demo/base.llmll."""
    d = _copy_tracked(tmp_path, "examples/refine-demo")
    _build(d, "base.llmll", tmp_path / "out")


def test_eb_b4_stem_base_ast_json(tmp_path: Path):
    """EB-B4 (cause B). examples/refine-demo/base.ast.json."""
    d = _copy_tracked(tmp_path, "examples/refine-demo")
    _build(d, "base.ast.json", tmp_path / "out")


TEXT_MAIN = """(import wasi.io (capability stdout :deterministic false))
(def-shell step [s: int input: string r: Response] -> (int, Command)
  (pair (+ s 1) (wasi.io.stdout "x")))
(def-shell done? [s: int] -> bool (>= s 1))
(def-main :mode console
  :init (pair 0 (wasi.io.stdout "start"))
  :step step
  :done? done?)
"""


def test_eb_b5_stem_text_keeps_executable_name(tmp_path: Path):
    """EB-B5 (cause B). A def-main program named after the `text` package
    builds, and its executable is still named `text`."""
    (tmp_path / "text.llmll").write_text(TEXT_MAIN)
    out = tmp_path / "out"
    _build(tmp_path, "text.llmll", out)
    root = subprocess.run(["stack", "path", "--local-install-root"], cwd=out,
                          capture_output=True, text=True, check=True).stdout.strip()
    assert (Path(root) / "bin" / "text").exists(), sorted(os.listdir(Path(root) / "bin"))
