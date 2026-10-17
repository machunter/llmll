"""REGEX-CAPTURE-1 / REGEX-CASE-1: capture, scan and case for text processing.

The design record is docs/design/regex-capture-case-proposal.md (Rev 0), plus
amendment A1 of the implementation plan: a literal pattern that escapes an
ASCII letter regex-tdfa reads as the letter itself (\\d, \\w, \\s, \\n) is a
check error, because at run time it silently matches the letter.

WHAT A PASS HERE MEANS. values.llmll is built once with $LLMLL_BIN and run;
each value cell reads one NAME= line of its output. On v0.30.1 the program
does not build, because the five builtins do not exist. M1 is the one cell
that changes an existing builtin (regex-match with (?i) answered false), and
M2 is its control: regex-match without (?i) is unchanged.

The agreement cells (AG-*) put the same pattern through two paths: `check`
with the pattern as a literal, and the built program with the pattern passed
as a parameter, where only the run-time compile acts. The two must agree on
whether the pattern compiles, and for AG4 (\\d) the run-time line shows why
A1 rejects it: the pattern matches the letter d and not the digit.
"""

import glob
import os
import shlex
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURES = REPO_ROOT / "scripts" / "tests" / "fixtures" / "regex_capture_case"

pytestmark = pytest.mark.skipif(
    not os.environ.get("LLMLL_BIN"),
    reason="set LLMLL_BIN to a built llmll; the spec-roundtrip job runs this in CI",
)

# A build plus a run, and the build dominates.
BUILD_TIMEOUT_S = 600
RUN_TIMEOUT_S = 10
CHECK_TIMEOUT_S = 60


def _llmll() -> list[str]:
    return shlex.split(os.environ["LLMLL_BIN"])


@pytest.fixture(scope="module")
def lines(tmp_path_factory) -> dict[str, str]:
    out = tmp_path_factory.mktemp("regex_values")
    p = subprocess.run(
        [*_llmll(), "build", str(FIXTURES / "values.llmll"), "-o", str(out)],
        capture_output=True, text=True, timeout=BUILD_TIMEOUT_S, cwd=str(REPO_ROOT),
    )
    assert p.returncode == 0, f"llmll build failed rc={p.returncode}\n{p.stderr[-2000:]}"
    exes = glob.glob(str(out / ".stack-work" / "install" / "*" / "*" / "*" / "bin" / "*"))
    assert len(exes) == 1, f"expected one executable under {out}, found {exes}"
    r = subprocess.run([exes[0]], input="x\n", capture_output=True, text=True,
                       timeout=RUN_TIMEOUT_S)
    assert r.returncode == 0, f"values: rc={r.returncode}, stderr={r.stderr[-500:]!r}"
    found: dict[str, str] = {}
    for line in r.stdout.splitlines():
        if "=" in line:
            key, _, value = line.partition("=")
            found[key] = value
    return found


# Lists render as <a><b>, a list of lists as [<a>][<b>], spans as (s,e).
VALUES = [
    ("E1", "<Previously>", "edge case 1 control: (?i) matches without regard to case"),
    ("E2", "<key=><key><>", "edge case 2: a group that took no part reads \"\""),
    ("E3", "[<`a/b.md`><a/b.md>]",
     "edge case 3: one element per span with group 1 inside; the span that crosses "
     "a newline is NOT matched, because [^`] does not match a newline (regex-tdfa's "
     "newline-sensitive default, which regex-match has always used)"),
    ("E4", "<ab><ab><>", "edge case 4: POSIX leftmost-longest, where Python gives a, b"),
    ("E5A", "[<>][<aaa>][<>][<>]", "edge case 5: empty matches are kept"),
    ("E5B", "(0,0)(1,4)(4,4)(5,5)", "edge case 5: the spans of the same four matches"),
    ("E9", "true", "edge case 9: string-lower normalizes before string-contains"),
    ("E10", "STRAßE|i|I", "edge case 10: simple case mapping; ß and İ do not round-trip"),
    ("E11", "|||[<>]|(0,0)", "edge case 11: the empty string, all five builtins"),
    ("M1", "true", "regex-match gains (?i), and (?i) also folds a bracket class"),
    ("M2", "true", "control: regex-match without (?i) is unchanged"),
    ("T1", "|||false",
     "totality: an invalid pattern passed as a parameter answers [], [], [] and "
     "false, and the program does not crash"),
    ("S1", "true", "each span's string-slice equals group 0 of the matching element"),
    ("NL1", "||<b>", "newline-sensitive: . and [^x] do not cross a newline; ^ matches at a line"),
]


@pytest.mark.parametrize("key,expected,why", VALUES, ids=[v[0] for v in VALUES])
def test_rc_value(lines, key, expected, why):
    assert key in lines, f"{key} missing from the program output: {sorted(lines)}"
    assert lines[key] == expected, f"{key}: expected {expected!r} ({why}); got {lines[key]!r}"


# (key, pattern as the builtin receives it, check accepts?, run-time line)
AGREEMENT = [
    ("AG1", "[0-9]+", True, "<12>"),
    ("AG2", "(?i)abc", True, "<ABC>"),
    ("AG3", "a{2,1}", False, ""),
    ("AG4", "\\d", False, "<d>"),
    ("AG5", "\\bfoo\\b", True, "<foo>"),
    ("AG6", "x(?i)y", False, ""),
    ("AG7", "[[:alpha:]]+", True, "<ab>"),
]


def _llmll_literal(pattern: str) -> str:
    return '"' + pattern.replace("\\", "\\\\").replace('"', '\\"') + '"'


@pytest.mark.parametrize("key,pattern,accepted,runtime", AGREEMENT,
                         ids=[a[0] for a in AGREEMENT])
def test_rc_check_agrees_with_runtime(lines, tmp_path, key, pattern, accepted, runtime):
    src = tmp_path / f"{key.lower()}.llmll"
    src.write_text(
        f"(def-shell f [s: string] -> list[string] (regex-find {_llmll_literal(pattern)} s))\n",
        encoding="utf-8",
    )
    p = subprocess.run([*_llmll(), "--json", "check", str(src)], capture_output=True,
                       text=True, timeout=CHECK_TIMEOUT_S, cwd=str(tmp_path))
    out = p.stdout + p.stderr
    if accepted:
        assert p.returncode == 0, f"{key}: check rejected {pattern!r}:\n{out[-800:]}"
    else:
        assert p.returncode != 0 and '"kind":"invalid-regex"' in out, (
            f"{key}: check accepted {pattern!r} (rc={p.returncode}):\n{out[-800:]}"
        )
    assert lines.get(key) == runtime, (
        f"{key}: run-time result for {pattern!r} is {lines.get(key)!r}, expected {runtime!r}"
    )


def test_rc_verify_caller_falls_back_and_stays_asserted(tmp_path):
    """V1: a def calling regex-find verifies with exit 0 and is not proved.

    The five builtins are outside Sigma_auto (LLMLL.md 5.3.3), so the caller
    falls back, as a caller of regex-match does, and the emitter does not crash.
    """
    src = tmp_path / "caller.llmll"
    src.write_text((FIXTURES / "caller.llmll").read_text(encoding="utf-8"), encoding="utf-8")
    p = subprocess.run([*_llmll(), "verify", str(src)], capture_output=True, text=True,
                       timeout=BUILD_TIMEOUT_S, cwd=str(tmp_path))
    out = p.stdout + p.stderr
    assert p.returncode == 0, f"verify rc={p.returncode}:\n{out[-1500:]}"
    assert "app:regex-find" in out and "0 of 1 contracted functions proved" in out, out[-1500:]
