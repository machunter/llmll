"""AMBIG-TVAR-1: a type that nothing fixes, under Eq or Ord, now builds.

The design record is docs/design/ambig-tvar-1-proposal.md (Rev 0, settled).
Every Haskell module codegen emits carries ExtendedDefaultRules, so GHC
instantiates an ambiguous type that carries only Eq, Ord or Show at (). No
value of such a type exists at run time, so the instance cannot change the
result.

WHAT A PASS HERE MEANS.
  values  W1, W2, W6, W9, W15 and W20 build and print the section 4.7 values.
          Before the change, each of them passed `check` and failed GHC.
  fails   W3 builds and fails at run time with the message a fixed-type
          program gives, before list_contains sees the value.
  quiet   W8, W12 and W14, whose type is fixed at a distance, build, print
          their values, and GHC defaults nothing in their user code.
  gate    smoke.llmll type-checks with -Wtype-defaults to the SAME set of
          defaulting warnings with and without the pragma, and no warning
          names () or []. This is the CI form of the 47-program measurement
          recorded with the change.
"""

import glob
import os
import re
import shlex
import shutil
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURES = REPO_ROOT / "scripts" / "tests" / "fixtures" / "ambig_tvar"
SMOKE = REPO_ROOT / "scripts" / "build-smoke" / "smoke.llmll"
PRAGMA = "{-# LANGUAGE ExtendedDefaultRules #-}"

pytestmark = pytest.mark.skipif(
    not os.environ.get("LLMLL_BIN"),
    reason="set LLMLL_BIN to a built llmll; the spec-roundtrip job runs this in CI",
)

BUILD_TIMEOUT_S = 600
RUN_TIMEOUT_S = 30


def _llmll() -> list[str]:
    return shlex.split(os.environ["LLMLL_BIN"])


def _build(src: Path, out: Path, *extra: str) -> subprocess.CompletedProcess:
    return subprocess.run([*_llmll(), "build", str(src), "-o", str(out), *extra],
                          capture_output=True, text=True, timeout=BUILD_TIMEOUT_S,
                          cwd=str(REPO_ROOT))


def _exe(out: Path) -> str:
    exes = glob.glob(str(out / ".stack-work" / "install" / "*" / "*" / "*" / "bin" / "*"))
    assert len(exes) == 1, f"expected one executable under {out}, found {exes}"
    return exes[0]


def _run(exe: str) -> subprocess.CompletedProcess:
    # The harness does not perform the halting step's command, so the program
    # prints on step 1 and halts on step 2: three stdin lines in all.
    return subprocess.run([exe], input="\n\n\n", capture_output=True, text=True,
                          timeout=RUN_TIMEOUT_S)


def _answer(stdout: str) -> str:
    # The :init write and the halting step's write are empty; the answer is the
    # one non-empty line.
    lines = [l for l in stdout.split("\n") if l != ""]
    assert len(lines) == 1, repr(stdout[:200])
    return lines[0]


def test_values_witnesses_build_and_print_their_values(tmp_path):
    p = _build(FIXTURES / "values.llmll", tmp_path / "values")
    assert p.returncode == 0, f"llmll build failed rc={p.returncode}\n{p.stderr[-2000:]}"
    r = _run(_exe(tmp_path / "values"))
    assert r.returncode == 0, r.stderr[-500:]
    # W1 W2 W6 W9 W15 W20
    assert _answer(r.stdout) == "0 t t f t t"


def test_failing_witness_builds_and_fails_with_the_fixed_type_message(tmp_path):
    p = _build(FIXTURES / "fails.llmll", tmp_path / "fails")
    assert p.returncode == 0, f"llmll build failed rc={p.returncode}\n{p.stderr[-2000:]}"
    r = _run(_exe(tmp_path / "fails"))
    assert r.returncode != 0
    assert "list_head: empty list" in r.stderr


def _defaults(log: str) -> list[str]:
    """The -Wtype-defaults warnings of one GHC run, as (file, message) text
    with line numbers removed: the pragma line shifts every later line."""
    out = []
    for m in re.finditer(r"([A-Za-z]+\.hs):\d+:\d+: warning: .*?\[-Wtype-defaults\]\n(.*?)\n", log):
        out.append(f"{m.group(1)}: {m.group(2).strip()}")
    return sorted(out)


def _typecheck(project: Path, src_dir: Path, outdir: Path) -> str:
    top = src_dir / "Main.hs"
    if not top.exists():
        top = src_dir / "Lib.hs"
    p = subprocess.run(
        ["stack", "exec", "--", "ghc", "-fno-code", "-fforce-recomp", "-Wtype-defaults",
         f"-i{src_dir}", "-outputdir", str(outdir), str(top)],
        capture_output=True, text=True, timeout=BUILD_TIMEOUT_S, cwd=str(project))
    assert p.returncode == 0, p.stderr[-2000:]
    return p.stderr + p.stdout


def _strip_pragma(src_dir: Path, dest: Path) -> None:
    dest.mkdir(parents=True)
    for f in src_dir.glob("*.hs"):
        lines = f.read_text(encoding="utf-8").split("\n")
        assert lines.count(PRAGMA) == 1, f"{f.name} must carry the pragma exactly once"
        (dest / f.name).write_text("\n".join(l for l in lines if l != PRAGMA), encoding="utf-8")


def test_quiet_witnesses_build_and_default_nothing_in_user_code(tmp_path):
    out = tmp_path / "quiet"
    p = _build(FIXTURES / "quiet.llmll", out)
    assert p.returncode == 0, f"llmll build failed rc={p.returncode}\n{p.stderr[-2000:]}"
    r = _run(_exe(out))
    assert r.returncode == 0, r.stderr[-500:]
    assert _answer(r.stdout) == "0 0 0"
    lib = (out / "src" / "Lib.hs").read_text(encoding="utf-8").split("\n")
    first_user = next(i for i, l in enumerate(lib) if l.startswith("w8 ::")) + 1
    log = _typecheck(out, out / "src", tmp_path / "o")
    user_defaults = [int(n) for n in re.findall(r"Lib\.hs:(\d+):\d+: warning: .*?\[-Wtype-defaults\]", log)
                     if int(n) >= first_user]
    assert user_defaults == [], f"GHC defaulted a type in user code at lines {user_defaults}"


@pytest.mark.skipif(shutil.which("stack") is None, reason="needs stack for ghc -fno-code")
def test_smoke_defaulting_warnings_are_unchanged_by_the_pragma(tmp_path):
    out = tmp_path / "smoke"
    p = _build(SMOKE, out)
    assert p.returncode == 0, f"llmll build failed rc={p.returncode}\n{p.stderr[-2000:]}"
    stripped = tmp_path / "stripped"
    _strip_pragma(out / "src", stripped)
    with_pragma = _defaults(_typecheck(out, out / "src", tmp_path / "o1"))
    without = _defaults(_typecheck(out, stripped, tmp_path / "o2"))
    assert with_pragma == without
    assert with_pragma, "expected the preamble's one numeric default (sha1_hash's 2^160)"
    assert not [w for w in with_pragma if "type ‘()’" in w or "type ‘[]’" in w]
