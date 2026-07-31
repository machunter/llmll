#!/usr/bin/env python3
"""
SPEC-AGREE-1 F-1 measurement: what fraction of the committed RFC-SWARM
corpus survives the Sigma_subsume gate?

Reproduces the tables in docs/design/spec-agreement-proposal.md Rev 1 §0.3
and the class breakdown in §0.4 M-2.

The gate is a faithful transcription of RefineReuse.hs qfContract:

    qfContract c = classifyContractFragment c == "qf_lia"
                   && not (contractMentionsArrOp c)
                   && not (clauseUF (contractPre c))
                   && not (clauseUF (contractPost c))

with ufBearing at RefineReuse.hs:289-299 and the array-op families at
FixpointEmit.hs:1577,1581. `classifyContractFragment` is approximated as
"at least one clause present", which is generous, so every figure this
script prints is an UPPER BOUND on comparability.

Row counting follows EC-4: a row is comparable only when every clause
citing it lives in a comparable contract.

Usage:
    python3 experiments/spec-agree-1/scripts/sigma_subsume.py [--json]

Exit status:
    0  every measured figure matches the value pinned in manifest.json
    1  a figure drifted from the pinned value (corpus or gate changed)
    2  an input artifact is missing or unparsed
"""
import argparse
import collections
import json
import os
import re
import sys

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
MANIFEST = os.path.join(os.path.dirname(__file__), "..", "manifest.json")

# RefineReuse.hs:289-299 ufBearing
UF_FNS = {"string-length", "list-length", "first", "second", "ok", "err"}
# FixpointEmit.hs:1577,1581 bytesOpNames ++ mapOpNames
ARR_OPS = {"bytes-length", "bytes-get", "bytes-set", "bytes-zero",
           "map-has", "map-get", "map-put", "map-empty"}

CID_RE = re.compile(r"^\[([A-Za-z]+\d+)\]")


def uf_bearing(e):
    """RefineReuse.hs ufBearing, transcribed."""
    if not isinstance(e, dict):
        return False
    k = e.get("kind")
    if k == "var":
        n = e.get("name") or ""
        return bool(n) and n[0].isupper()            # nullary ctor term
    if k == "app":
        f = e.get("fn") or ""
        if f in UF_FNS:
            return True
        if f and f[0].isupper():                     # ctor application
            return True
        return any(uf_bearing(a) for a in e.get("args", []))
    if k == "op":
        return any(uf_bearing(a) for a in e.get("args", []))
    if k == "pair":
        return True
    return False


def uf_reason(e):
    """Which clause of ufBearing fired, for the abstention histogram."""
    if not isinstance(e, dict):
        return None
    k = e.get("kind")
    if k == "var":
        n = e.get("name") or ""
        if n and n[0].isupper():
            return "nullary-ctor"
    if k == "app":
        f = e.get("fn") or ""
        if f in UF_FNS:
            return "measure/Result/pair-sel:" + f
        if f and f[0].isupper():
            return "ctor-app"
        for a in e.get("args", []):
            r = uf_reason(a)
            if r:
                return r
    if k == "op":
        for a in e.get("args", []):
            r = uf_reason(a)
            if r:
                return r
    if k == "pair":
        return "pair-literal"
    return None


def mentions_arr_op(e):
    """FixpointEmit.hs exprMentionsOpIn over bytesOpNames ++ mapOpNames."""
    if isinstance(e, dict):
        if e.get("kind") in ("app", "op"):
            if (e.get("fn") or e.get("op")) in ARR_OPS:
                return True
        return any(mentions_arr_op(v) for v in e.values())
    if isinstance(e, list):
        return any(mentions_arr_op(v) for v in e)
    return False


def cid_of(source):
    """Inventory row id cited by a clause: '[T049] RFC 1350 ...' -> 'T049'."""
    if not isinstance(source, str):
        return None
    m = CID_RE.match(source.strip())
    return m.group(1) if m else None


def load_encoded(inventory_path):
    """cid -> class, over rows dispositioned Encoded."""
    with open(inventory_path) as fh:
        doc = json.load(fh)
    rows = doc["rows"] if isinstance(doc, dict) and "rows" in doc else doc
    return {r["cid"]: r.get("class") for r in rows
            if r.get("disposition") == "Encoded"}


def analyse(ast_path, inventory_path):
    """Apply the gate to one run. Returns a dict of measured figures."""
    with open(ast_path) as fh:
        doc = json.load(fh)
    encoded = load_encoded(inventory_path)

    defs = []              # (name, comparable, abstention_reason, [cids])
    reasons = collections.Counter()

    for s in doc.get("statements") or []:
        if not isinstance(s, dict):
            continue
        if not str(s.get("kind", "")).startswith("def"):
            continue
        clauses, cids = [], []
        for field in ("pre_clauses", "post_clauses"):
            for c in (s.get(field) or []):
                if not isinstance(c, dict):
                    continue
                clauses.append(c.get("expr"))
                cid = cid_of(c.get("source"))
                if cid:
                    cids.append(cid)
        if not clauses:
            continue                                  # no contract, not in scope

        if any(mentions_arr_op(x) for x in clauses):
            defs.append((s.get("name"), False, "array-op", cids))
            reasons["array-op"] += 1
        elif any(uf_bearing(x) for x in clauses):
            why = next((uf_reason(x) for x in clauses if uf_reason(x)), "uf")
            defs.append((s.get("name"), False, why, cids))
            reasons[why] += 1
        else:
            defs.append((s.get("name"), True, None, cids))

    # EC-4: a row is comparable only when EVERY clause citing it lives in a
    # comparable contract. Collect citations per row, then require all-comparable.
    citing = collections.defaultdict(list)
    for d in defs:
        comparable, cids = d[1], d[3]
        for cid in cids:
            citing[cid].append(comparable)

    cited_encoded = [cid for cid in citing if cid in encoded]
    comparable_rows = [cid for cid in cited_encoded if all(citing[cid])]

    return {
        "contract_bearing_defs": len(defs),
        "comparable_defs": sum(1 for d in defs if d[1]),
        "comparable_def_names": [d[0] for d in defs if d[1]],
        "encoded_rows": len(encoded),
        "encoded_rows_cited": len(cited_encoded),
        "comparable_rows": len(comparable_rows),
        "comparable_row_classes": dict(collections.Counter(
            encoded[cid] for cid in comparable_rows)),
        "abstention_reasons": dict(reasons),
    }


def pct(num, den):
    return (100.0 * num / den) if den else 0.0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", action="store_true",
                    help="emit measured figures as JSON instead of tables")
    args = ap.parse_args()

    with open(MANIFEST) as fh:
        manifest = json.load(fh)

    measured, missing = {}, []
    for run in manifest["runs"]:
        ast = os.path.join(REPO, run["ast"])
        inv = os.path.join(REPO, run["inventory"])
        if not os.path.exists(ast) or not os.path.exists(inv):
            missing.append(run["label"])
            continue
        measured[run["label"]] = analyse(ast, inv)

    if missing:
        print("MISSING INPUTS: " + ", ".join(missing), file=sys.stderr)
        return 2

    combined = {
        k: sum(m[k] for m in measured.values())
        for k in ("contract_bearing_defs", "comparable_defs", "encoded_rows",
                  "encoded_rows_cited", "comparable_rows")
    }
    histogram = collections.Counter()
    for m in measured.values():
        histogram.update(m["abstention_reasons"])

    if args.json:
        print(json.dumps({"runs": measured, "combined": combined,
                          "abstention_histogram": dict(histogram)}, indent=2))
    else:
        labels = list(measured)
        w = max(len(l) for l in labels) + 2
        print("Sigma_subsume gate over the committed RFC-SWARM corpus")
        print("(upper bound: classifyContractFragment approximated as "
              "'at least one clause present')\n")
        lw = 32
        header = f"{'Unit':<{lw}}" + "".join(f"{l:>{w}}" for l in labels) + f"{'Combined':>14}"
        print(header)
        print("-" * len(header))

        def row(name, key, of_key=None):
            cells = "".join(f"{measured[l][key]:>{w}}" for l in labels)
            tot = combined[key]
            suffix = (f"{tot} ({pct(tot, combined[of_key]):.1f}%)"
                      if of_key else str(tot))
            print(f"{name:<{lw}}{cells}{suffix:>14}")

        row("Contract-bearing defs", "contract_bearing_defs")
        row("Comparable defs", "comparable_defs", "contract_bearing_defs")
        row("Encoded rows", "encoded_rows")
        row("Encoded rows cited by a clause", "encoded_rows_cited")
        row("Comparable rows", "comparable_rows", "encoded_rows")

        print("\nPer-run comparable-row share of Encoded rows:")
        for l in labels:
            m = measured[l]
            print(f"  {l:<18} {m['comparable_rows']}/{m['encoded_rows']}"
                  f"  ({pct(m['comparable_rows'], m['encoded_rows']):.1f}%)"
                  f"   classes {m['comparable_row_classes'] or '{}'}"
                  f"   defs {m['comparable_def_names']}")

        n_abstain = combined["contract_bearing_defs"] - combined["comparable_defs"]
        print(f"\nAbstention histogram over all {n_abstain} "
              f"non-comparable contract-bearing defs:")
        for k, v in histogram.most_common():
            print(f"  {v:4d}  {k}")
        for family in ("array-op", "measure"):
            if not any(k.startswith(family) for k in histogram):
                print(f"  {0:4d}  {family}")

    # Regression check against the figures published in Rev 1 §0.3.
    drift = []
    for run in manifest["runs"]:
        exp = run.get("expected") or {}
        got = measured[run["label"]]
        for k, v in exp.items():
            if got.get(k) != v:
                drift.append(f"{run['label']}.{k}: expected {v}, measured {got.get(k)}")
    for k, v in (manifest.get("expected_combined") or {}).items():
        if combined.get(k) != v:
            drift.append(f"combined.{k}: expected {v}, measured {combined.get(k)}")
    for k, v in (manifest.get("expected_abstention_histogram") or {}).items():
        if histogram.get(k, 0) != v:
            drift.append(f"histogram.{k}: expected {v}, measured {histogram.get(k, 0)}")

    if drift:
        print("\nDRIFT from the figures pinned in manifest.json "
              "(published in spec-agreement-proposal.md Rev 1 §0.3):", file=sys.stderr)
        for d in drift:
            print("  " + d, file=sys.stderr)
        return 1

    print("\nAll figures match manifest.json "
          "(spec-agreement-proposal.md Rev 1 §0.3). OK.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
