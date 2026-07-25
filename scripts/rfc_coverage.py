#!/usr/bin/env python3
"""RFC-COV-1: clause-inventory <-> :source cross-check lint.

Makes the DENOMINATOR of an RFC-coverage claim mechanical. The claim "every
normative clause of the target is dispositioned, and every Encoded clause is
carried by a contract" is only auditable if something checks it both ways:

  * RESOLUTION  every citation in the module resolves to a real inventory row
  * COVERAGE    every Encoded inventory row is cited by at least one contract clause
  * DISPOSITION a contract may not cite a row that was dispositioned out
  * MONOPOLY    only root contracts carry :source (provenance authorship belongs
                to the extraction role; refine-spawned sub-contracts are additive
                and carry none)

Syntactic only: no solver, no verification. This lint makes the denominator
mechanical; it does NOT claim the citation is FAITHFUL to the RFC text, which
stays with human audit plus the refute layer (`spec-from-rfc-pipeline.md` §2).

No compiler change was needed: SRC-CONJ-1 (v0.14.65) exposes per-conjunct
provenance as `pre_sources` / `post_sources` in `verify --trust-report --json`,
which is this tool's input.

CITATION CONVENTION
    Every `:source` string on a root contract clause begins with a bracketed
    inventory row tag, e.g.

        (pre (>= block 1) :source "[T045] RFC 1350 p.4 - block numbers begin at one")

    The tag is what makes matching exact. Free prose alone would force fuzzy
    matching, which cannot support a completeness claim.

USAGE
    rfc_coverage.py --inventory INV.json --trust-report TR.json [--roots R.txt]
                    [--json] [--require-full-coverage]

    Exit 0 when every enabled check passes, 1 otherwise.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from typing import Any

TAG_RE = re.compile(r"^\s*\[(T\d{3,})\]")

CARRIED = ("Encoded", "Deployment-modeled", "Vectored")


def load(path: str) -> Any:
    with open(path) as f:
        return json.load(f)


def inventory_rows(doc: Any) -> dict[str, dict]:
    """Accept either the dispositioned shape {"rows":[...]} or a bare list."""
    rows = doc["rows"] if isinstance(doc, dict) and "rows" in doc else doc
    out = {}
    for r in rows:
        cid = r.get("cid") or r.get("id")
        if cid:
            out[cid] = r
    return out


def citations(trust: Any) -> list[tuple[str, str, str]]:
    """Extract (function, side, source-string) for every provenance-bearing clause.

    Handles both shapes SRC-CONJ-1 emits: the scalar `pre_source`/`post_source`
    for a single-clause side, and the `pre_sources`/`post_sources` arrays (author
    order) for a multi-clause side.
    """
    found = []
    for e in trust.get("entries", []):
        fn = e.get("name", "?")
        for side in ("pre", "post"):
            arr = e.get(f"{side}_sources")
            if arr:
                for s in arr:
                    if s:
                        found.append((fn, side, s))
            else:
                s = e.get(f"{side}_source")
                if s:
                    found.append((fn, side, s))
    return found


def check(inv: dict[str, dict], trust: Any, roots: set[str] | None,
          require_full: bool) -> dict:
    cites = citations(trust)
    errors: list[str] = []
    warnings: list[str] = []

    # --- RESOLUTION + DISPOSITION ---
    cited: dict[str, list[str]] = {}
    untagged: list[str] = []
    for fn, side, s in cites:
        m = TAG_RE.match(s)
        if not m:
            untagged.append(f"{fn}.{side}: {s[:70]}")
            continue
        cid = m.group(1)
        if cid not in inv:
            errors.append(
                f"RESOLUTION: {fn}.{side} cites [{cid}], which is not an inventory row")
            continue
        cited.setdefault(cid, []).append(f"{fn}.{side}")
        if inv[cid].get("disposition") == "Dispositioned out":
            errors.append(
                f"DISPOSITION: {fn}.{side} cites [{cid}], which is dispositioned out "
                f"({inv[cid].get('reason','')[:60]}); an excluded row cannot be claimed as carried")

    if untagged:
        msg = (f"{len(untagged)} :source string(s) carry no [Tnnn] inventory tag, "
               "so they cannot be cross-checked")
        (errors if require_full else warnings).append(
            msg + "".join(f"\n      {u}" for u in untagged[:8]))

    # --- COVERAGE ---
    encoded = [c for c, r in inv.items() if r.get("disposition") == "Encoded"]
    uncited = sorted(c for c in encoded if c not in cited)
    if uncited:
        msg = (f"COVERAGE: {len(uncited)} of {len(encoded)} Encoded rows are cited by no "
               f"contract clause: {', '.join(uncited[:15])}"
               + (" ..." if len(uncited) > 15 else ""))
        (errors if require_full else warnings).append(msg)

    # --- MONOPOLY ---
    if roots is not None:
        for fn, side, s in cites:
            if fn not in roots:
                errors.append(
                    f"MONOPOLY: {fn}.{side} carries a :source but {fn} is not a root "
                    "contract; provenance authorship belongs to the extraction role")
    else:
        warnings.append("MONOPOLY: no --roots given, provenance-monopoly check skipped")

    core = [c for c, r in inv.items() if r.get("core")]
    return {
        "inventory_rows": len(inv),
        "encoded_rows": len(encoded),
        "encoded_cited": len(encoded) - len(uncited),
        "encoded_uncited": uncited,
        "core_rows": len(core),
        "core_cited": sum(1 for c in core if c in cited),
        "citations_found": len(cites),
        "citations_untagged": len(untagged),
        "errors": errors,
        "warnings": warnings,
        "ok": not errors,
    }


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="RFC-COV-1 clause-coverage lint")
    p.add_argument("--inventory", required=True)
    p.add_argument("--trust-report", required=True)
    p.add_argument("--roots", help="file with one root function name per line")
    p.add_argument("--json", action="store_true", dest="as_json")
    p.add_argument("--require-full-coverage", action="store_true",
                   help="treat uncited Encoded rows and untagged citations as errors "
                        "(use at freeze time, once all roots are authored)")
    a = p.parse_args(argv)

    inv = inventory_rows(load(a.inventory))
    trust = load(a.trust_report)
    roots = None
    if a.roots:
        with open(a.roots) as f:
            roots = {ln.strip() for ln in f if ln.strip() and not ln.startswith("#")}

    res = check(inv, trust, roots, a.require_full_coverage)

    if a.as_json:
        print(json.dumps(res, indent=1))
    else:
        print(f"RFC-COV-1: {res['inventory_rows']} inventory rows, "
              f"{res['encoded_rows']} Encoded, {res['citations_found']} citations found")
        print(f"  Encoded rows cited : {res['encoded_cited']}/{res['encoded_rows']}")
        print(f"  core rows cited    : {res['core_cited']}/{res['core_rows']}")
        for w in res["warnings"]:
            print(f"  WARN  {w}")
        for e in res["errors"]:
            print(f"  ERROR {e}")
        print("RFC-COV-1 PASS" if res["ok"] else "RFC-COV-1 FAIL")
    return 0 if res["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
