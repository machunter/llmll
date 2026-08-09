"""TOOL-ENCODING-1: the compiler decodes its own source as UTF-8, end to end.

WHY THIS EXISTS ALONGSIDE THE HSPEC TESTS. `compiler/test/Spec.hs` pins
`decodeSourceUtf8`'s contract as a pure function, which is the right place for
the table of valid and invalid byte sequences. It cannot pin what a USER SEES,
and what a user saw before this fix was a raw GHC exception escaping to the top
level:

    llmll: bad.llmll: hGetContents: invalid argument
           (cannot decode byte sequence starting from 255)

rather than a diagnostic. That is a CLI-level property, so it needs the CLI.

WHY THE MESSAGE ASSERTIONS LOOK FUSSY. `emitParseDiag` renders
:phase/:file/:line/:col/:message/:hint and does NOT render `diagKind`, so on the
default S-expression channel the message text is the ONLY thing distinguishing
"your bytes are wrong" from "your syntax is wrong". Both classify as
`parse-error`. The message therefore owes three things, and each gets its own
assertion rather than being folded into one substring check: it names the
encoding in words, it gives the offending byte in hex, and it gives a position.

WHY IT SKIPS WITHOUT A BINARY. `pytest scripts/tests/` runs in version-gate's
C1-C4 job, which sets up Python and jq and NO Haskell toolchain, so there is no
compiler to invoke there. The same convention (and the same reason) governs
`test_driver_ll_4a_cover.py`. The binary-bearing invocation is wired into the
`spec-roundtrip` job, which builds one.

THE LOCALE HALF IS NOT TESTED HERE AND CANNOT BE. macOS GHC resolves UTF-8 under
every LC_ALL (v0.14.86), so a locale-scrubbed run cannot fail on the machine most
of this was written on. That half is gated by `doc_claims_cover.py`, which
scrubs the environment and runs on Linux CI over a corpus that is 16-for-16
non-ASCII.
"""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]

needs_binary = pytest.mark.skipif(
    not os.environ.get("LLMLL_BIN"),
    reason="set LLMLL_BIN to a built llmll; the spec-roundtrip job runs this in CI",
)


def _check(tmp_path: Path, name: str, payload: bytes):
    """Write raw BYTES and run `llmll check` over them.

    Bytes, not text, and written by the test rather than committed: an
    intentionally malformed fixture on disk is exactly the kind of file an
    editor, a linter, or `git` normalization silently repairs, at which point
    the test passes for the wrong reason.
    """
    f = tmp_path / name
    f.write_bytes(payload)
    return subprocess.run(
        [os.environ["LLMLL_BIN"], "check", str(f)],
        capture_output=True, text=True, cwd=str(tmp_path),
    )


@needs_binary
def test_invalid_utf8_is_a_diagnostic_not_an_exception(tmp_path):
    p = _check(tmp_path, "bad.llmll", b";; bad byte: \xff\n")
    assert p.returncode == 1, p.stdout + p.stderr
    assert "(error :phase parse" in p.stdout, p.stdout + p.stderr


@needs_binary
def test_invalid_utf8_does_not_leak_the_ghc_exception(tmp_path):
    """The pre-fix behaviour, pinned as an explicit negative.

    `hGetContents` in user-facing output means the IOException escaped again.
    """
    p = _check(tmp_path, "bad.llmll", b";; bad byte: \xff\n")
    combined = p.stdout + p.stderr
    assert "hGetContents" not in combined, combined
    assert "invalid argument" not in combined, combined


@needs_binary
def test_the_message_carries_encoding_byte_and_position(tmp_path):
    """The three-part content specification, one assertion each."""
    # The invalid byte opens line 3, column 1.
    p = _check(tmp_path, "bad.llmll", b";; one\n;; two\n\xff\n")
    out = p.stdout + p.stderr
    assert "not valid UTF-8" in out, out          # names the encoding
    assert "0xff" in out, out                     # names the byte
    assert ":line 3" in out and ":col 1" in out, out  # names the position


@needs_binary
def test_a_byte_order_mark_is_rejected_by_name(tmp_path):
    p = _check(tmp_path, "bom.llmll", b"\xef\xbb\xbf;; leading BOM\n")
    assert p.returncode == 1, p.stdout + p.stderr
    assert "U+FEFF" in p.stdout, p.stdout + p.stderr


@needs_binary
def test_valid_non_ascii_source_still_checks(tmp_path):
    """The control. A section sign in a comment must not become an error."""
    payload = (
        ";; § valid — UTF-8\n"
        "(module m (export f)\n"
        "  (def f [n: int] -> int\n"
        "    (pre true)\n"
        "    (post (= result n))\n"
        "    n))\n"
    ).encode("utf-8")
    p = _check(tmp_path, "ok.llmll", payload)
    assert p.returncode == 0, p.stdout + p.stderr


def test_replay_pins_utf8_on_both_child_pipe_handles():
    """The replay half, pinned at the SOURCE rather than executed.

    `runReplay` builds the child with `std_in = CreatePipe, std_out = CreatePipe`
    and `createProcess` hands back handles carrying whatever codec
    `getLocaleEncoding` supplied, so replaying a program that prints non-ASCII
    failed under a POSIX locale. This asserts both handles are pinned.

    SOURCE-PINNED AND NOT EXECUTED, deliberately, and the reason is a spec one
    rather than laziness: LLMLL.md governs SOURCE decoding (§2) and the
    generated program's own channels (§13's text-command note), but says nothing
    about the toolchain's subprocess pipes, and it should not. `llmll replay` is
    a debugging command, not a language property. With no spec claim for an
    execution gate to falsify, a source pin is the proportionate instrument: it
    fails loudly if the pin is ever deleted, and claims nothing more.

    Needs no compiler, so unlike the rest of this file it runs in CI's C1-C4 job.
    """
    src = (REPO_ROOT / "compiler" / "src" / "LLMLL" / "Replay.hs").read_text()
    assert "hSetEncoding hin utf8" in src, "stdin pipe lost its UTF-8 pin"
    assert "hSetEncoding hout utf8" in src, "stdout pipe lost its UTF-8 pin"
