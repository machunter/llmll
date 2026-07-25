#!/usr/bin/env python3
"""Reconcile two independent RFC clause extractions (RFC-SWARM Phase 0, F-10).

The task is a CENSUS (identify the set of normative clauses), not a labelling of
a fixed item set, so Cohen's kappa does not apply directly to the clause-set
question. We report:

  * line-COVERAGE agreement: over the union of normative line regions, what
    fraction did both extractors mark normative? This is the statistic that
    speaks to the completeness of the denominator, which is what dual
    extraction exists to defend.
  * row-level matching by span overlap, separating two distinct phenomena:
      - coverage gap: a region one extractor marked normative and the other
        did not mark at all (a real disagreement about what the RFC requires)
      - granularity difference: both cover the region, but split it into a
        different number of rows (rubric tie-break 1 applied differently; not
        a coverage disagreement)
  * rule agreement (N1-N5) on matched rows, where Cohen's kappa DOES apply.
"""
import json
import sys
from pathlib import Path
from typing import Any

# Default: the committed extraction data, so the reported statistics are
# reproducible from the repository alone. Override with argv[1].
SC = Path(sys.argv[1]) if len(sys.argv) > 1 else \
    Path(__file__).resolve().parent.parent / "data"


def load(name):
    with open(SC / name) as f:
        return json.load(f)


def lines_of(rows, source):
    """Set of line numbers covered by rows from one source."""
    out = set()
    for r in rows:
        if r.get("source") != source:
            continue
        a, b = int(r["line_start"]), int(r["line_end"])
        if b < a:
            a, b = b, a
        out.update(range(a, b + 1))
    return out


def overlaps(r1, r2):
    if r1.get("source") != r2.get("source"):
        return False
    a1, b1 = int(r1["line_start"]), int(r1["line_end"])
    a2, b2 = int(r2["line_start"]), int(r2["line_end"])
    return not (b1 < a2 or b2 < a1)


def kappa(pairs):
    """Cohen's kappa over matched-row rule labels."""
    if not pairs:
        return None
    labels = sorted({p[0] for p in pairs} | {p[1] for p in pairs})
    n = len(pairs)
    po = sum(1 for a, b in pairs if a == b) / n
    pe = 0.0
    for lab in labels:
        pa = sum(1 for a, _ in pairs if a == lab) / n
        pb = sum(1 for _, b in pairs if b == lab) / n
        pe += pa * pb
    if pe == 1.0:
        return 1.0
    return (po - pe) / (1 - pe)


def main():
    A = load("extraction-a.json")
    B = load("extraction-b.json")
    an, bn = A["normative"], B["normative"]

    report: dict[str, Any] = {"counts": {"A_rows": len(an), "B_rows": len(bn)}}

    # --- line-coverage agreement, per source document ---
    cov = {}
    for src in ("RFC1350", "RFC1123"):
        la, lb = lines_of(an, src), lines_of(bn, src)
        inter, union = la & lb, la | lb
        cov[src] = {
            "A_lines": len(la), "B_lines": len(lb),
            "both": len(inter), "union": len(union),
            "jaccard": round(len(inter) / len(union), 4) if union else None,
            "A_only_lines": len(la - lb), "B_only_lines": len(lb - la),
        }
    report["line_coverage"] = cov

    # --- row matching by span overlap ---
    a_match = {i: [] for i in range(len(an))}
    b_match = {j: [] for j in range(len(bn))}
    for i, ra in enumerate(an):
        for j, rb in enumerate(bn):
            if overlaps(ra, rb):
                a_match[i].append(j)
                b_match[j].append(i)

    a_unmatched = [an[i] for i, m in a_match.items() if not m]
    b_unmatched = [bn[j] for j, m in b_match.items() if not m]
    one_to_one = sum(1 for m in a_match.values()
                     if len(m) == 1 and len(b_match[m[0]]) == 1)
    granularity = sum(1 for m in a_match.values() if len(m) > 1)

    report["row_matching"] = {
        "one_to_one": one_to_one,
        "A_rows_matching_multiple_B": granularity,
        "A_unmatched": len(a_unmatched),
        "B_unmatched": len(b_unmatched),
    }
    report["A_unmatched_rows"] = [
        {"id": r["id"], "source": r["source"],
         "lines": [r["line_start"], r["line_end"]],
         "rule": r.get("rule"), "quote": r.get("quote", "")[:90],
         "obligation": r.get("obligation", "")[:160]}
        for r in a_unmatched]
    report["B_unmatched_rows"] = [
        {"id": r["id"], "source": r["source"],
         "lines": [r["line_start"], r["line_end"]],
         "rule": r.get("rule"), "quote": r.get("quote", "")[:90],
         "obligation": r.get("obligation", "")[:160]}
        for r in b_unmatched]

    # --- rule agreement on 1:1 matched rows (kappa applies here) ---
    pairs = []
    for i, m in a_match.items():
        if len(m) == 1 and len(b_match[m[0]]) == 1:
            pairs.append((an[i].get("rule"), bn[m[0]].get("rule")))
    agree = sum(1 for a, b in pairs if a == b)
    k = kappa(pairs)
    report["rule_agreement"] = {
        "compared": len(pairs),
        "identical": agree,
        "raw_agreement": round(agree / len(pairs), 4) if pairs else None,
        "cohens_kappa": round(k, 4) if k is not None else None,
    }

    with open(SC / "reconciliation.json", "w") as f:
        json.dump(report, f, indent=1)
    print(json.dumps({k: v for k, v in report.items()
                      if k not in ("A_unmatched_rows", "B_unmatched_rows")},
                     indent=1))
    print(f"\nA-only rows ({len(a_unmatched)}):")
    for r in report["A_unmatched_rows"]:
        print(f"  {r['id']} {r['source']}:{r['lines']} [{r['rule']}] {r['obligation'][:110]}")
    print(f"\nB-only rows ({len(b_unmatched)}):")
    for r in report["B_unmatched_rows"]:
        print(f"  {r['id']} {r['source']}:{r['lines']} [{r['rule']}] {r['obligation'][:110]}")


if __name__ == "__main__":
    main()
