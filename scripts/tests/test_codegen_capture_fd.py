"""FD-CAPTURE-1: every handle `captureStdout` opens must be closed.

WHY THIS PINS THE SOURCE AND NOT A RUN. The defect is that `captureStdout`
duplicated stdout on every step and never closed the duplicate, so the
descriptor was reclaimed only when GC happened to finalize the `Handle`. That
makes the observable failure a RACE: the refute-crux port died at fd 1103 after
about 51 of 80 cases, while a 1400-step probe doing nothing but writing to
stdout survived. A test shaped "run N steps and assert no crash" would
therefore pass on a broken tree whenever GC kept up, which is the wrong
direction for a regression test to be flaky in.

So this reads the emitted preamble instead and asserts the property directly:
each handle bound in `captureStdout` is closed on the success path. That is
decidable from the text, does not depend on the collector, and fails loudly if
a later change reintroduces reliance on finalization.

`readEnd` was the one deliberate exception: `hGetContents` puts a handle in the
semi-closed state and closes it at EOF, and the line above it forces the whole
string. Since CAPTURE-PIPE-1 it is closed explicitly as well, so the exception
set is empty and stays declared, because any future addition to it needs the
same kind of argument in writing.

CAPTURE-PIPE-1 (2026-09-06). The capture sink moved from a `createPipe` pipe to
a temporary file: a step that printed more than the pipe held (16 KiB on macOS,
64 KiB on Linux) blocked in the write with the read not yet started, on one
thread, and the program slept forever. The handles are now `openTempFile`'s
(writeEnd, with the file's path) and `openFile`'s (readEnd), and the file is
removed after the read. These tests track those binders; the descriptor
property they pin is the same one.
"""

from __future__ import annotations

import pathlib
import re

REPO = pathlib.Path(__file__).resolve().parents[2]
CODEGEN = REPO / "compiler" / "src" / "LLMLL" / "CodegenHs.hs"

# Handles closed by something other than an hClose naming them. Empty since
# CAPTURE-PIPE-1 (readEnd is now closed by name); any addition here needs the
# same kind of argument in writing that readEnd's hGetContents case had.
CLOSED_BY_CONSUMPTION: set[str] = set()

# The binders that open a handle inside captureStdout. openTempFile binds a
# (path, handle) pair, so the pattern accepts a tuple whose LAST name is the
# handle.
OPENER = re.compile(
    r"\s*(?:\(\s*\w+\s*,\s*(\w+)\s*\)|(\w+))\s*<-\s*"
    r"(hDuplicate|fdToHandle|openFile|openTempFile)\b"
)


def _opened(body: list[str]) -> set[str]:
    return {m.group(1) or m.group(2) for line in body if (m := OPENER.match(line))}


def _capture_stdout_body() -> list[str]:
    """The emitted lines of captureStdout, unquoted from the Haskell string list."""
    text = CODEGEN.read_text(encoding="utf-8")
    start = text.index('"captureStdout :: IO () -> IO String"')
    # The emitted function ends at the first empty emitted line after it.
    end = text.index('  , ""', start)
    body = []
    for m in re.finditer(r'^\s*,?\s*"(.*)"\s*$', text[start:end], re.M):
        body.append(m.group(1))
    assert body, "could not extract captureStdout's emitted body"
    return body


def test_capture_stdout_closes_every_handle_it_opens():
    body = _capture_stdout_body()
    joined = "\n".join(body)

    opened = _opened(body)

    assert {"oldStdout", "writeEnd", "readEnd"} <= opened, (
        f"captureStdout binds {sorted(opened)}; it should duplicate stdout and "
        "open a write handle and a read handle on the capture file. If the "
        "capture mechanism changed, this test needs rewriting rather than deleting"
    )

    closed = set(re.findall(r"hClose\s+(\w+)", joined))

    leaked = opened - closed - CLOSED_BY_CONSUMPTION
    assert not leaked, (
        f"captureStdout opens {sorted(leaked)} and never closes them. This is "
        f"FD-CAPTURE-1: the descriptors are then reclaimed only by GC "
        f"finalization, and a console program that steps faster than the "
        f"collector dies with 'file descriptor NNNN out of range for select'. "
        f"Measured at 139 leaked handles on a live run before the fix."
    )


def test_the_restore_happens_before_the_close():
    """Closing the duplicate before restoring through it would break capture.

    The fix is `hClose oldStdout`, and WHERE it goes is part of it: the restore
    `hDuplicateTo oldStdout stdout` must have already copied the descriptor
    back onto stdout. A close placed above the restore would leave stdout
    pointing at the closed pipe, which no descriptor count would catch.
    """
    body = _capture_stdout_body()
    restore = next(i for i, l in enumerate(body)
                   if "hDuplicateTo oldStdout stdout" in l)
    close = next(i for i, l in enumerate(body) if "hClose oldStdout" in l)
    assert restore < close, (
        "hClose oldStdout must come AFTER hDuplicateTo oldStdout stdout; "
        "closing first restores stdout onto a closed descriptor"
    )


# ---------------------------------------------------------------------------
# CAPTURE-ENCODING-1 (v0.14.90)
#
# These live beside the FD-CAPTURE-1 tests above because they are about the same
# nine lines, and they pin the SOURCE for a different reason than those do. The
# fd leak was GC-timing dependent, so a behavioural test would have been flaky in
# the wrong direction. This defect is perfectly deterministic and DOES have a
# behavioural gate -- scripts/build-smoke/capture_encoding.llmll, run by
# build_smoke.sh, which compares the emitted bytes. But that gate only runs in
# the Stack-bearing CI job, several minutes in. These two run in the
# toolchain-free job in milliseconds and fail with the cause named, which is
# where a reader wants to learn that a pin went missing.
# ---------------------------------------------------------------------------


def test_both_capture_handles_are_pinned_to_utf8():
    """Both handles on the capture file carry an explicit utf8 pin.

    History, because the pin outlived its first reason. The pipe ends came from
    System.Posix.IO.fdToHandle in BINARY mode -- hGetEncoding answered Nothing --
    and binary mode is the ABSENCE of a codec rather than a wrong one, so
    setLocaleEncoding had nothing to inform. A binary handle writes a Char's low
    byte, which is why `→` (U+2192) went out as 0x92 and `✅` (U+2705) as 0x05:
    codepoint mod 256. Both ends were required and each was ablated separately:
    writeEnd alone gave a latin-1 re-decode (c3 a2 c2 86 c2 92), readEnd alone
    gave "hGetContents: invalid byte sequence".

    Since CAPTURE-PIPE-1 the handles come from openTempFile and openFile, TEXT
    mode, so the locale main moves does reach them. The pins stay by name: the
    capture must not depend on the order in which main moves the locale, and
    scripts/build-smoke/capture_encoding.llmll asserts the bytes either way.
    """
    body = _capture_stdout_body()
    joined = "\n".join(body)

    capture = {name for name in _opened(body) if name != "oldStdout"}
    assert capture == {"writeEnd", "readEnd"}, (
        f"captureStdout opens {sorted(capture)} on the capture file; expected a "
        "writeEnd and a readEnd. If the capture mechanism changed, this test "
        "needs rewriting rather than deleting"
    )

    pinned = set(re.findall(r"hSetEncoding\s+(\w+)\s+utf8", joined))
    unpinned = capture - pinned
    assert not unpinned, (
        f"captureStdout opens {sorted(unpinned)} without pinning an encoding. "
        f"A capture handle that resolves its codec from the ambient state is "
        f"CAPTURE-ENCODING-1's class, whichever sink it writes to."
    )


def test_the_capture_file_is_removed_after_the_read_is_forced():
    """The file replaces the pipe; leaving it behind would replace one leak with another."""
    body = _capture_stdout_body()
    force = next(i for i, l in enumerate(body) if "length output `seq`" in l)
    remove = next((i for i, l in enumerate(body) if "removeFile capPath" in l), None)
    assert remove is not None, "captureStdout never removes its capture file (CAPTURE-PIPE-1)"
    assert force < remove, (
        "removeFile capPath must come AFTER the read is forced; hGetContents is "
        "lazy and an unlinked file with a semi-closed handle still reads on "
        "POSIX, but the order is the property a reader can check"
    )


def test_the_write_end_is_pinned_before_the_redirect():
    """WHERE the writeEnd pin goes is part of the fix, and this is measured.

    `hDuplicateTo writeEnd stdout` copies this handle onto stdout, so a pin
    placed after it leaves `action` writing through a still-binary stdout.
    Moving the line down by one was measured to produce

      hGetContents: invalid argument (cannot decode byte sequence starting from 146)

    where 146 is 0x92, the truncated U+2192 arriving at a correctly pinned read
    end. Note the failure surfaces on the READ, which is why an ordering bug here
    would be read as a problem with the wrong handle.
    """
    body = _capture_stdout_body()
    pin = next((i for i, l in enumerate(body)
                if re.search(r"hSetEncoding\s+writeEnd\s+utf8", l)), None)
    redirect = next((i for i, l in enumerate(body)
                     if "hDuplicateTo writeEnd stdout" in l), None)
    assert pin is not None, "no hSetEncoding writeEnd utf8 in captureStdout"
    assert redirect is not None, "no hDuplicateTo writeEnd stdout in captureStdout"
    assert pin < redirect, (
        "hSetEncoding writeEnd utf8 must come BEFORE hDuplicateTo writeEnd "
        "stdout; the redirect copies the handle onto stdout, so pinning after it "
        "leaves the captured writes in binary mode (CAPTURE-ENCODING-1)"
    )
