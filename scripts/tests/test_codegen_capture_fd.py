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

`readEnd` is the one deliberate exception and it is named rather than skipped:
`hGetContents` puts a handle in the semi-closed state and closes it at EOF, and
the line above it forces the whole string, so it is closed by the read itself.
"""

from __future__ import annotations

import pathlib
import re

REPO = pathlib.Path(__file__).resolve().parents[2]
CODEGEN = REPO / "compiler" / "src" / "LLMLL" / "CodegenHs.hs"

# Closed by hGetContents reaching EOF, which the forcing line above it
# guarantees. Any addition here needs the same kind of argument in writing.
CLOSED_BY_CONSUMPTION = {"readEnd"}


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

    opened = set()
    for line in body:
        m = re.match(r"\s*(\w+)\s*<-\s*(hDuplicate|fdToHandle)\b", line)
        if m:
            opened.add(m.group(1))

    assert "oldStdout" in opened, (
        "captureStdout no longer duplicates stdout; if the capture mechanism "
        "changed, this test needs rewriting rather than deleting"
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
