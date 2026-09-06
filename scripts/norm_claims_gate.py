#!/usr/bin/env python3
"""DRIFT-CT-3 (NORM-CLAIM-1): every normative sentence in LLMLL.md names what stands under it.

REFERENCE IMPLEMENTATION. The LLMLL port is tools/norm-claims/normclaims.llmll and
scripts/norm_claims_cover.py is the differential cover that mutates a scratch tree and
asserts both implementations catch each mutation. Design: docs/design/norm-claim-proposal.md
(Rev 1, settled 2026-09-06). Registry format: scripts/norm-claims/README.md.

WHAT THIS DECIDES. DRIFT-CT-2 checks that a claim which has a fixture still holds. This gate
checks the other direction: that every sentence in the registry's scope carries a marker
`[NC-NNN]`, that every marker has a registry row whose pinned `text` matches the sentence, and
that every row's disposition still names something that exists: a doc-claims fixture whose
header claims the identifier, a refute-crux suite, an OPEN roadmap row, or an explicit
assumption inside the ratchet bound. It never SKIPs (SKIP-SILENT-1): a missing or malformed
registry, an unreadable spec, or a scope heading not found is a FAIL.

THE SENTENCE RULE IS THE DEFINITION. Prose in scope conforms to this splitter, not the other
way round (proposal §3.1 rule 5). The port implements the same rule; the cover's cells pin it.

Exit 0 with one line `DRIFT-CT-3: N sentences dispositioned (...)` on success, exit 1 with one
`DRIFT-CT-3 FAIL: ...` line per finding otherwise.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys

MARKER_RE = re.compile(r"\[NC-(\d{3})\]")
TRAILING_MARKER_RE = re.compile(r"\[NC-\d{3}\]$")
LIST_MARKER_RE = re.compile(r"^\s*(?:\d+[a-z]?\.|[-*])\s+")
BLOCKQUOTE_RE = re.compile(r"^\s*>\s?")
ABBREVIATIONS = ("e.g", "i.e", "vs", "cf", "etc", "et al")
DISPOSITIONS = ("fixture", "falsified-by", "row", "assumed", "informative")
GATE = "DRIFT-CT-3"


# ---------------------------------------------------------------------------
# Sentence rule (proposal §3.1)
# ---------------------------------------------------------------------------

def heading_level(line: str) -> int:
    m = re.match(r"^(#{1,6})\s", line)
    return len(m.group(1)) if m else 0


def scope_lines(spec_lines: list[str], heading: str) -> list[tuple[int, str]] | None:
    """Lines under `heading` (a prefix match on the heading text) up to the next heading of
    equal or higher level. Returns None when the heading is not found."""
    start = None
    level = 0
    for i, line in enumerate(spec_lines):
        lv = heading_level(line)
        if lv and line.strip().startswith(heading.strip()):
            start, level = i + 1, lv
            break
    if start is None:
        return None
    out = []
    for j in range(start, len(spec_lines)):
        lv = heading_level(spec_lines[j])
        if lv and lv <= level:
            break
        out.append((j + 1, spec_lines[j]))
    return out


def prose_lines(lines: list[tuple[int, str]]) -> list[tuple[int, str]]:
    out, in_fence = [], False
    for n, line in lines:
        s = line.strip()
        if s.startswith("```"):
            in_fence = not in_fence
            continue
        if in_fence or not s or s.startswith("|") or s.startswith("<!--") or s == "---":
            continue
        out.append((n, line))
    return out


def split_sentences(line: str) -> list[str]:
    """Split one prose line into sentences. A boundary is `.`, `!` or `?` outside a code
    span, optionally followed by a marker, then whitespace and an uppercase letter, `*`, a
    backtick, `(` or `[`, unless the word before the punctuation is an abbreviation."""
    s = BLOCKQUOTE_RE.sub("", LIST_MARKER_RE.sub("", line, count=1), count=1).strip()
    out, cur, in_code, i = [], "", False, 0
    while i < len(s):
        c = s[i]
        if c == "`":
            in_code = not in_code
        cur += c
        if not in_code and c in ".!?":
            j = i + 1
            m = MARKER_RE.match(s, j)
            if m:
                cur += m.group(0)
                j = m.end()
            prev = cur[: -1 - (len(m.group(0)) if m else 0)].rstrip()
            if any(prev.endswith(a) for a in ABBREVIATIONS):
                i = j
                continue
            rest = s[j:]
            if rest == "" or (rest[0].isspace() and re.match(r"\s*[A-Z*`(\[]", rest)):
                out.append(cur.strip())
                cur = ""
                i = j
                continue
            i = j
            continue
        i += 1
    if cur.strip():
        out.append(cur.strip())
    return out


def normalize(sentence: str) -> str:
    return re.sub(r"\s+", " ", TRAILING_MARKER_RE.sub("", sentence)).strip()


def marker_of(sentence: str) -> str | None:
    m = TRAILING_MARKER_RE.search(sentence)
    return m.group(0)[1:-1] if m else None


# ---------------------------------------------------------------------------
# Repository readers
# ---------------------------------------------------------------------------

def git_index(repo: str) -> set[str]:
    out = subprocess.run(["git", "-C", repo, "ls-files"], capture_output=True, text=True, check=True).stdout
    return set(out.split("\n")) - {""}


def fixture_norm_ids(path: str) -> set[str]:
    ids: set[str] = set()
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            if not line.startswith(";;"):
                if line.strip():
                    break
                continue
            m = re.match(r";;\s*@norm:\s*(.*)$", line)
            if m:
                ids |= {t.strip() for t in m.group(1).split(",") if t.strip()}
    return ids


def roadmap_status_cells(path: str) -> dict[str, str]:
    """Tag -> status cell (column 2) for rows between '## Active Items' and '## Upcoming Releases'."""
    cells: dict[str, str] = {}
    with open(path, encoding="utf-8") as fh:
        lines = fh.read().split("\n")
    inside = False
    for line in lines:
        if line.startswith("## Active Items"):
            inside = True
            continue
        if inside and line.startswith("## "):
            break
        if inside and line.startswith("| **"):
            cols = line.split("|")
            if len(cols) < 3:
                continue
            m = re.match(r"\s*\*\*([A-Za-z0-9-]+)\*\*", cols[1])
            if m:
                cells[m.group(1)] = cols[2].strip()
    return cells


def verdict_families(repo: str, index: set[str]) -> set[str]:
    fams: set[str] = set()
    for rel in index:
        if rel.endswith("EXPECTED_VERDICTS.json"):
            try:
                with open(os.path.join(repo, rel), encoding="utf-8") as fh:
                    doc = json.load(fh)
            except (OSError, ValueError):
                continue
            # One verdict file in the tree is a bare list; a suite is an object with a family.
            fam = doc.get("family") if isinstance(doc, dict) else None
            if isinstance(fam, str):
                fams.add(fam)
    return fams


# ---------------------------------------------------------------------------
# The gate
# ---------------------------------------------------------------------------

def run(repo: str, registry_path: str, spec_path: str, roadmap_path: str, workflow_path: str, dump: bool) -> int:
    fails: list[str] = []

    def fail(msg: str) -> None:
        fails.append(f"{GATE} FAIL: {msg}")

    try:
        with open(registry_path, encoding="utf-8") as fh:
            reg = json.load(fh)
    except OSError as e:
        print(f"{GATE} FAIL: registry unreadable: {e}")
        return 1
    except ValueError as e:
        print(f"{GATE} FAIL: registry is not valid JSON: {e}")
        return 1
    try:
        with open(spec_path, encoding="utf-8") as fh:
            spec_lines = fh.read().split("\n")
    except OSError as e:
        print(f"{GATE} FAIL: spec unreadable: {e}")
        return 1

    scope = reg.get("scope") or []
    if not isinstance(scope, list) or not scope:
        print(f"{GATE} FAIL: registry scope is empty; a gate with nothing to check does not pass")
        return 1
    claims = reg.get("claims")
    if not isinstance(claims, list):
        print(f"{GATE} FAIL: registry has no claims list")
        return 1

    # Sentences in scope.
    sentences: list[tuple[str, int, str]] = []  # (heading, line, sentence)
    for heading in scope:
        lines = scope_lines(spec_lines, heading)
        if lines is None:
            fail(f"scope heading not found in spec: {heading!r}")
            continue
        for n, line in prose_lines(lines):
            for s in split_sentences(line):
                sentences.append((heading, n, s))

    if dump:
        for heading, n, s in sentences:
            print(f"{marker_of(s) or '-':<6}\t{n}\t{normalize(s)}")
        return 0

    by_id: dict[str, dict] = {}
    for row in claims:
        rid = row.get("id")
        if not isinstance(rid, str) or not re.fullmatch(r"NC-\d{3}", rid):
            fail(f"registry row with a malformed id: {rid!r}")
            continue
        if rid in by_id:
            fail(f"{rid} appears twice in the registry")
        by_id[rid] = row

    seen: dict[str, int] = {}
    for heading, n, s in sentences:
        mid = marker_of(s)
        if mid is None:
            fail(f"untagged sentence at line {n} under {heading!r}: {normalize(s)[:80]!r}")
            continue
        if mid in seen:
            fail(f"{mid} appears twice in the spec (lines {seen[mid]} and {n})")
            continue
        seen[mid] = n
        row = by_id.get(mid)
        if row is None:
            fail(f"{mid} at line {n} has no registry row")
            continue
        if row.get("text") != normalize(s):
            fail(f"{mid} text differs from registry; re-affirm the row (line {n})")

    for rid in by_id:
        if rid not in seen:
            fail(f"{rid} has no sentence in scope (orphan row)")

    # Dispositions.
    index = git_index(repo)
    families = None
    statuses = None
    counts = {d: 0 for d in DISPOSITIONS}
    for rid, row in by_id.items():
        disp = row.get("disposition")
        if disp not in DISPOSITIONS:
            fail(f"{rid} has an unknown disposition {disp!r}")
            continue
        counts[disp] += 1
        target = row.get("target")
        if disp == "fixture":
            paths = target if isinstance(target, list) else [target]
            if not paths or any(not isinstance(p, str) for p in paths):
                fail(f"{rid} fixture disposition needs one or more paths")
                continue
            for p in paths:
                if p not in index:
                    fail(f"{rid} fixture {p} is not in the git index")
                    continue
                if rid not in fixture_norm_ids(os.path.join(repo, p)):
                    fail(f"{rid} fixture {p} does not name {rid} in an @norm: header line")
        elif disp == "falsified-by":
            if not isinstance(target, str):
                fail(f"{rid} falsified-by disposition needs a string target")
                continue
            if families is None:
                families = verdict_families(repo, index)
            if target.startswith("suite:"):
                if target[len("suite:"):] not in families:
                    fail(f"{rid} names suite {target[6:]!r}; no EXPECTED_VERDICTS.json in the index has that family")
            elif target == "gate:refute-crux":
                ok = False
                try:
                    with open(workflow_path, encoding="utf-8") as fh:
                        ok = "refutecrux" in fh.read()
                except OSError:
                    ok = False
                if not ok or not families:
                    fail(f"{rid} names gate:refute-crux, but the workflow has no refute-crux step or no suite exists")
            else:
                fail(f"{rid} falsified-by target must be suite:<family> or gate:refute-crux, got {target!r}")
        elif disp == "row":
            if not isinstance(target, str):
                fail(f"{rid} row disposition needs a roadmap tag")
                continue
            if statuses is None:
                statuses = roadmap_status_cells(roadmap_path)
            cell = statuses.get(target)
            if cell is None:
                fail(f"{rid} names row {target}, which is not in the Active Items table; re-disposition")
            elif not cell.startswith("**OPEN"):
                fail(f"{rid} names row {target}, whose status cell reads {cell[:30]!r}, not OPEN; re-disposition")
        elif disp == "assumed":
            if not isinstance(row.get("reason"), str) or not row["reason"].strip():
                fail(f"{rid} is assumed without a reason")
        # informative: nothing to check.

    bound = reg.get("assumed_bound")
    if not isinstance(bound, int):
        fail("registry has no integer assumed_bound")
    elif counts["assumed"] > bound:
        fail(f"assumed count {counts['assumed']} exceeds bound {bound}; lower the count or raise the bound with a bound_reason")

    if fails:
        for f in fails:
            print(f)
        return 1
    denom = counts["fixture"] + counts["falsified-by"] + counts["row"] + counts["assumed"]
    ratio = (counts["assumed"] / denom) if denom else 0.0
    print(
        f"{GATE}: {len(sentences)} sentences dispositioned "
        f"(fixture {counts['fixture']}, falsified-by {counts['falsified-by']}, row {counts['row']}, "
        f"assumed {counts['assumed']}, informative {counts['informative']}); "
        f"assumed ratio {ratio:.2f}, bound {bound}"
    )
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description="DRIFT-CT-3: every normative sentence in LLMLL.md names what stands under it.")
    ap.add_argument("--repo", default=".", help="repository root (default: cwd)")
    ap.add_argument("--registry", default="scripts/norm-claims/registry.json")
    ap.add_argument("--spec", default="LLMLL.md")
    ap.add_argument("--roadmap", default="docs/compiler-team-roadmap.md")
    ap.add_argument("--workflow", default=".github/workflows/version-gate.yml")
    ap.add_argument("--dump", action="store_true", help="print marker, line and normalized text per sentence; no checks")
    a = ap.parse_args()
    repo = os.path.abspath(a.repo)
    j = lambda p: p if os.path.isabs(p) else os.path.join(repo, p)  # noqa: E731
    return run(repo, j(a.registry), j(a.spec), j(a.roadmap), j(a.workflow), a.dump)


if __name__ == "__main__":
    sys.exit(main())
