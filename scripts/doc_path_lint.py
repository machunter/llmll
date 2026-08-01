#!/usr/bin/env python3
"""DRIFT-DOC-4: prose path-citation lint. ADVISORY, never fails.

Markdown links are checked by ordinary link checkers. This lints the other half:
bare-backtick path citations in prose, `docs/design/foo.md`, which no tool
follows and which rot silently when a file moves.

WHY ADVISORY, AND WHY IT MUST STAY THAT WAY
-------------------------------------------
The other three gates assert something with a definite truth value. DRIFT-CI-1
compares banners, DRIFT-CT-2 runs the compiler, DRIFT-DOC-3 compares a declared
field with a directory. "This path in prose ought to resolve" has no such value,
because of one class this lint cannot decide and never will:

    COUNTERFACTUAL PATHS. A rationale legitimately names a location that does not
    exist, and its non-existence is the point of the sentence. Real example, from
    experiments/language-comparison-backlog.md:

        "...lives at the root rather than inside `experiments/repair-loop/` to keep
         it visible as cross-cutting work. It can later move into
         `experiments/repair-loop/BACKLOG.md` via `git mv` if..."

    That citation is correct. A fail-closed gate would demand it be mangled.

A gate that can be wrong about correct input teaches people to write worse prose
to appease it. So this reports and exits 0. Its value is at review time, in the
diff, not as a merge blocker. Do not "promote" it to fail-closed without solving
the counterfactual class, which is a language problem, not a scripting one.

WHAT IT EXCLUDES, AND WHY
-------------------------
  historical files   A postmortem, a frozen run record, an append-only CHANGELOG
                     section and an archived doc all describe the tree AS IT WAS.
                     Their stale-looking paths are accurate history. This is the
                     big one: it is the difference between a ~450-item problem and
                     a ~50-item one.
  historical lines   A living doc can hold a historical sentence. UPDATE-PROTOCOL's
                     archive table says "`docs/design/x.md` ... **DONE** moved to
                     shipped-design-specs/". Rewriting the first path there would
                     turn "X moved to Y" into "Y moved to Y".
  placeholders       `postmortem-NNN.md`, `text/NNNN-name.md`, `turn_NN/verifier.json`,
                     and paths elided with "...". Patterns, not citations.
  link labels        [`old/path.md`](new/path.md) where the TARGET resolves. The
                     link works; the label is display text. Cosmetic at worst.
  ALLOW              Individually verified correct: counterfactuals, and paths that
                     are not repo paths at all (`src/Lib.hs` is `llmll build`
                     output; `.llmll/templates/...` is created at runtime).

Exit code is always 0. Set STRICT=1 to exit 1 when findings exist, for local use.
"""
import os
import re
import subprocess
import sys
from collections import defaultdict

REPO = subprocess.run(['git', 'rev-parse', '--show-toplevel'],
                      capture_output=True, text=True).stdout.strip()
os.chdir(REPO)

PATH = re.compile(r'`([A-Za-z0-9_./-]+\.(?:md|hs|llmll|json|sh|yaml|yml|py|cabal|txt))`')
LABEL = re.compile(r'\[`([A-Za-z0-9_./-]+\.\w+)`\]\(([^)]+)\)')
FENCE = re.compile(r'```.*?```', re.S)
LINK = re.compile(r'\]\([^)]*\)')
PLACEHOLDER = re.compile(r'NN|<|\bfoo\b|Mylib|cell_|turn_|\.\.\.')
HIST_LINE = re.compile(
    r'\*\*DONE\*\*|moved to|relocat|formerly|previously|old path|archived to'
    r'|removed 20|deleted 20|migrated from', re.I)

# Verified correct as written 2026-07-26. Every entry states why, because an
# unexplained entry here is indistinguishable from a stale citation someone gave
# up on. Prefer fixing the prose; add a row only when the citation is right.
ALLOW = {
    # counterfactual: the sentence is about a move that has not happened
    ('experiments/language-comparison-backlog.md', 'experiments/repair-loop/BACKLOG.md'),
    # not repo paths: generated into the user's output dir by `llmll build`
    ('README.md', 'src/Lib.hs'),
    ('LLMLL.md', 'src/FFI/Mylib.hs'),
    # runtime paths: the minimal-agent harness writes these under a temp .llmll/
    # working dir per cell; nothing with this name is ever committed
    ('experiments/minimal-agent/README.md',
     '.llmll/templates/ecommerce-order-handler/scaffold.ast.json'),
    ('experiments/minimal-agent/experiments/009-transfer-conservation.md',
     '.llmll/templates/transfer-conservation/scaffold.ast.json'),
    ('experiments/minimal-agent/experiments/010-byte-saturate.md',
     '.llmll/templates/byte-saturate/scaffold.ast.json'),
    ('experiments/minimal-agent/experiments/011-assume-guarantee-order.md',
     '.llmll/templates/assume-guarantee-order/scaffold.ast.json'),
    # session scratch, deliberately never committed
    ('experiments/r5-validation/findings.md', 'scratchpad/r5drive.sh'),
    # not a repo path: the user's global Claude Code config lives in $HOME/.claude,
    # not in this tree. The repo's own .claude/ holds skills and settings only.
    ('.planning/codebase/STRUCTURE.md', '.claude/CLAUDE.md'),
    # convention, not an instance: every emergent example carries its own
    # audit/runner.py, and the proposal is naming the shape, not one file
    ('docs/design/rfc-swarm-roadmap-proposal.md', 'audit/runner.py'),
}


def historical_file(f):
    return (f == 'CHANGELOG.md'
            or '/runs/' in f
            or re.search(r'/postmortem-', f)
            or f.startswith('docs/archive/')
            or '/findings/' in f
            # A phase directory is a frozen run record: SUMMARY/RESEARCH/LEARNINGS
            # describe what a completed phase saw and did, and their paths are
            # written relative to wherever that phase's commands ran (`app/Main.hs`
            # and `src/LLMLL/Module.hs` from inside `compiler/`, `autogen/…` from
            # inside `.stack-work/`). Rewriting them to repo-root form would falsify
            # the record. Same class as /runs/ and postmortem-, named separately
            # because the path shape is unrelated. `.planning/codebase/` is NOT
            # historical — it describes the tree as it IS, and its stale citations
            # are real errors to fix.
            or f.startswith('.planning/phases/')
            # Frozen record of what an ingest pass found, including paths that
            # existed only in the ingested documents.
            or f == '.planning/INGEST-CONFLICTS.md')


def main():
    files = [f for f in subprocess.run(['git', 'ls-files', '*.md'],
                                       capture_output=True, text=True).stdout.split()
             if not f.startswith(('site/', 'node_modules/'))]
    findings = defaultdict(list)
    scanned = cites = 0
    for f in files:
        if historical_file(f):
            continue
        scanned += 1
        d = os.path.dirname(f)
        raw = open(f, encoding='utf-8').read()
        lines = raw.split('\n')
        body = FENCE.sub('', raw)
        labels = {m.group(1) for m in LABEL.finditer(body)
                  if os.path.exists(os.path.normpath(os.path.join(d, m.group(2).split('#')[0])))}
        for m in PATH.finditer(LINK.sub(']()', body)):
            p = m.group(1)
            if '/' not in p:
                continue
            cites += 1
            if (os.path.exists(p)
                    or os.path.exists(os.path.normpath(os.path.join(d, p)))
                    or p in labels
                    or PLACEHOLDER.search(p)
                    or (f, p) in ALLOW):
                continue
            ln = next((i + 1 for i, l in enumerate(lines) if f'`{p}`' in l), 0)
            if ln and HIST_LINE.search(lines[ln - 1]):
                continue
            findings[f].append((ln, p))

    n = sum(len(v) for v in findings.values())
    print(f"DRIFT-DOC-4 (advisory): {cites} prose path citations in {scanned} living files")
    if not n:
        print("DRIFT-DOC-4: all resolve.")
        return 0
    print(f"DRIFT-DOC-4: {n} do not resolve, in {len(findings)} file(s).\n")
    for f, v in sorted(findings.items()):
        for ln, p in v:
            print(f"  {f}:{ln}  `{p}`")
    print("\nEach is one of: a stale citation to fix, or a case ALLOW should record "
          "with a reason.\nThis lint does not fail the build; see the module docstring "
          "for why it must not.")
    return 1 if os.environ.get('STRICT') else 0


if __name__ == '__main__':
    sys.exit(main())
