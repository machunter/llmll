#!/usr/bin/env python3
"""Per-file verification table for the LLMLL tools under tools/.

The tools' `.verified.json` sidecars are gitignored, so the checkout records
no proof for them. This script regenerates the evidence and prints the table
that `tools/VERIFICATION.md` quotes.

WHAT IT RUNS

For every tracked `tools/**/*.llmll`, from the file's own directory, over a
COPY of the tree (made with `git archive`, because `llmll verify` writes a
sidecar next to every file it reads):

  1. `llmll verify FILE`: runs the solver, writes the sidecar, gives the
     headline and the exit status.
  2. `llmll verify FILE --trust-report --json`: reads that sidecar. Run on its
     own, without step 1, it reports nothing proved, because `--trust-report`
     renders a sidecar and does not run the solver.

A trust report also lists the functions a file imports, under qualified names
(`fill.next-error-budget`). The OWN columns count only unqualified names, so
a proof is counted once, in the file that holds it.

Crux files (`crux-*.llmll`) are mutants that are expected to fail; their exit
status is 1 by design. The frozen expectations live in the refute-crux gate
(`tools/llmll-driver/EXPECTED_VERDICTS.json`) and in the crux loop of
`.github/workflows/version-gate.yml`, not here. This script reports; it does
not gate.

Usage:
  python3 scripts/tools_verification.py [--llmll PATH]
"""

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def default_llmll():
    root = subprocess.run(
        ["stack", "path", "--local-install-root"],
        cwd=os.path.join(REPO, "compiler"),
        capture_output=True, text=True, check=True,
    ).stdout.strip()
    return os.path.join(root, "bin", "llmll")


def headline(out):
    """The verdict line: the first `error:` line, else the SAFE/UNSAFE line.

    Warnings such as W-BODY-FALLBACK also start with a marker, so a line is
    only a verdict if it names one.
    """
    lines = [l.strip() for l in out.splitlines() if "written to" not in l]
    for s in lines:
        if s.startswith("error:"):
            return s
    for s in lines:
        if "SAFE" in s and s.startswith(("✅", "⚠️", "❌")):
            # Drop the file path the compiler prints after the marker.
            return re.sub(r"\s+\./\S+\s+", " ", s, count=1)
    return "(no headline)"


def own_counts(report):
    counts = {"verified": 0, "asserted": 0, "no contract": 0, "other": 0}
    for e in report.get("entries", []):
        if "." in e.get("name", ""):
            continue
        level = e.get("effective_level") or ""
        if level.startswith("verified"):
            counts["verified"] += 1
        elif level.startswith("asserted"):
            counts["asserted"] += 1
        elif level in ("", "no-contract", "no contract", "none"):
            counts["no contract"] += 1
        else:
            counts["other"] += 1
    return counts


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--llmll", help="compiler binary (default: stack local install root)")
    args = ap.parse_args()
    llmll = os.path.abspath(args.llmll) if args.llmll else default_llmll()
    if not os.access(llmll, os.X_OK):
        sys.exit(f"no llmll binary at {llmll}")
    version = subprocess.run([llmll, "version"], capture_output=True, text=True).stdout.strip()

    files = subprocess.run(
        ["git", "ls-files", "tools/*.llmll", "tools/**/*.llmll"],
        cwd=REPO, capture_output=True, text=True, check=True,
    ).stdout.split()
    files = sorted(set(files))
    if not files:
        sys.exit("no tracked tools/*.llmll files found")

    with tempfile.TemporaryDirectory() as tmp:
        archive = subprocess.run(["git", "archive", "HEAD", "tools"], cwd=REPO,
                                 capture_output=True, check=True).stdout
        subprocess.run(["tar", "-x", "-C", tmp], input=archive, check=True)

        print(f"{version}, {len(files)} files, tree at HEAD")
        print()
        print("| File | Exit | Own verified | Own asserted | Own no contract | Headline |")
        print("|---|---|---|---|---|---|")
        for rel in files:
            d, b = os.path.split(os.path.join(tmp, rel))
            v = subprocess.run([llmll, "verify", "./" + b], cwd=d,
                               capture_output=True, text=True)
            out = v.stdout + v.stderr
            t = subprocess.run([llmll, "verify", "./" + b, "--trust-report", "--json"],
                               cwd=d, capture_output=True, text=True)
            try:
                c = own_counts(json.loads(t.stdout))
                cells = [str(c["verified"]), str(c["asserted"]), str(c["no contract"])]
                if c["other"]:
                    cells[2] += f" (+{c['other']} other)"
            except (json.JSONDecodeError, ValueError):
                cells = ["n/a", "n/a", "n/a"]
            hl = headline(out).replace("|", "\\|")
            if len(hl) > 110:
                hl = hl[:107] + "..."
            print(f"| `{rel[len('tools/'):]}` | {v.returncode} | " + " | ".join(cells) + f" | {hl} |")


if __name__ == "__main__":
    main()
