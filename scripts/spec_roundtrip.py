#!/usr/bin/env python3
"""DRIFT-CI-1 C5: opt-in round-trip of LLMLL.md code blocks against `llmll check`.

Walks LLMLL.md for fenced code blocks tagged ```lisp``` or ```llmll``` that are
*explicitly opted in* by an HTML comment immediately preceding the fence:

    <!-- ci:roundtrip -->
    ```lisp
    ...code...
    ```

    <!-- ci:roundtrip: strict -->
    ```lisp
    ...code...
    ```

Opt-in is deliberate (not default-on) so spec authors retain control over which
blocks are full programs vs. illustrative fragments. The marker must sit on the
line immediately above the fence opener, or with at most one blank line in
between; further separation does not count.

Flags (comma-separated after `ci:roundtrip:`):
  strict     invoke `llmll check --strict`; warnings become errors

Environment:
  LLMLL_BIN  override the llmll invocation. Default: `stack exec llmll --`.
             Tokenized with shlex.split before subprocess.run.
  SPEC_FILE  override the spec path. Default: `LLMLL.md`.

Exit codes:
  0  all opt-in blocks parsed (or no opt-in blocks present)
  1  one or more opt-in blocks failed, or harness error

The script is invoked from the `spec-roundtrip` job of
.github/workflows/version-gate.yml after `stack build llmll`. It is also
runnable locally:  `python3 scripts/spec_roundtrip.py`.
"""

import os
import re
import shlex
import subprocess
import sys
import tempfile
from pathlib import Path

OPT_IN_RE = re.compile(r'<!--\s*ci:roundtrip(?:\s*:\s*([^>]+?))?\s*-->')
FENCE_OPEN_RE = re.compile(r'^```(lisp|llmll)\s*$')
FENCE_CLOSE_RE = re.compile(r'^```\s*$')


def find_opt_in_blocks(spec_path):
    """Yield (fence_line_no, flags_set, body_text) per opted-in block.

    fence_line_no is 1-indexed and points at the ``` opener.
    body_text is the joined block contents with a trailing newline.
    """
    text = spec_path.read_text(encoding='utf-8')
    lines = text.splitlines()
    n = len(lines)
    i = 0
    while i < n:
        m = OPT_IN_RE.search(lines[i])
        if not m:
            i += 1
            continue
        flags_raw = (m.group(1) or '').strip()
        flags = {f.strip() for f in flags_raw.split(',') if f.strip()}

        # Locate fence opener: allowed positions are i+1 or i+2 (one blank gap).
        j = i + 1
        if j < n and not lines[j].strip():
            j += 1
        if j >= n or not FENCE_OPEN_RE.match(lines[j]):
            i += 1
            continue

        fence_open = j
        k = j + 1
        while k < n and not FENCE_CLOSE_RE.match(lines[k]):
            k += 1
        if k >= n:
            # Unterminated fence; bail to keep scanning.
            i = j + 1
            continue

        body = '\n'.join(lines[fence_open + 1:k]) + '\n'
        yield (fence_open + 1, flags, body)
        i = k + 1


def run_check(llmll_bin, block_path, strict):
    cmd = shlex.split(llmll_bin) + ['check', str(block_path)]
    if strict:
        cmd.append('--strict')
    proc = subprocess.run(cmd, capture_output=True, text=True)
    diag = (proc.stderr or proc.stdout).strip().splitlines()
    return proc.returncode, diag


def main():
    spec_path = Path(os.environ.get('SPEC_FILE', 'LLMLL.md'))
    llmll_bin = os.environ.get('LLMLL_BIN', 'stack exec llmll --')

    if not spec_path.exists():
        print(f"DRIFT-CI-1 C5 FAIL: spec file not found: {spec_path}", file=sys.stderr)
        return 1

    blocks = list(find_opt_in_blocks(spec_path))
    if not blocks:
        print(f"DRIFT-CI-1 C5: no opt-in blocks in {spec_path}; nothing to check")
        return 0

    failures = 0
    with tempfile.TemporaryDirectory() as tmp:
        tmp_dir = Path(tmp)
        for idx, (line_no, flags, body) in enumerate(blocks, start=1):
            block_path = tmp_dir / f"block_{idx:03d}_line_{line_no}.llmll"
            block_path.write_text(body, encoding='utf-8')
            strict = 'strict' in flags
            rc, diag = run_check(llmll_bin, block_path, strict)
            label = f"{spec_path}:{line_no} (block {idx}, strict={strict})"
            if rc == 0:
                print(f"OK   {label}")
            else:
                head = diag[0] if diag else '(no diagnostic output)'
                print(f"FAIL {label}: {head}")
                failures += 1

    if failures:
        print(
            f"DRIFT-CI-1 C5 FAIL: {failures} of {len(blocks)} opt-in block(s) failed",
            file=sys.stderr,
        )
        return 1

    print(f"DRIFT-CI-1 C5 PASS: {len(blocks)} opt-in block(s) parsed")
    return 0


if __name__ == '__main__':
    sys.exit(main())
