#!/usr/bin/env python3
"""MUL-VAR-1: export the rev3.py witnesses and their fact-set statistics for the hspec suite.

For each of the 132 rows, and for the refusal, chain and limit inputs of
rev3.py sections 6, 7 and 4, this writes the hypotheses as rev3's VC sees them
(top-level `and` split, with the ground-fact families of a bytes or Str row
added) and the goal, as s-expression text, with what rev3.py's generator
gives: the number of facts, the pairs T, the cap state, the closure size, the
largest degree, the facts per family, and per family a SHA-256 of the fact
lines (see `fact_line`), which the hspec differential compares fact for fact;
or the refusal construct.

Usage: python3 scripts/mulvar/export_witnesses.py [out.json]
Default out: compiler/test/fixtures/mul_var_1/witnesses.json
"""
import hashlib
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import rev3  # noqa: E402

REPO = os.path.dirname(os.path.dirname(HERE))
DEFAULT_OUT = os.path.join(REPO, "compiler", "test", "fixtures", "mul_var_1", "witnesses.json")


def sx(t):
    if isinstance(t, str):
        return t
    return "(" + " ".join(sx(x) for x in t) + ")"


def fact_line(f):
    """One fact as a name-stable line: family, premises, conclusion.

    Each relation prints as `op[pkey]` after rev3's canonical form (`>` and
    `>=` turned round, `=` and `!=` on the smaller of p and -p). An atom prints
    as rev3's key (`x`, `div(1*w+1*,2)`, `bytesLen(1*b)`), which the hspec
    differential rebuilds from the emitter's atoms. Premises are a set.
    """
    fam, prem, con = f

    def rel(o, p):
        o2, p2 = rev3.VC.canon(o, p)
        return f"{o2}[{rev3.pkey(p2)}]"
    return f"{fam}|{';'.join(sorted({rel(o, p) for o, p in prem}))}|{rel(*con)}"


def fact_digests(fx):
    """Per family: the SHA-256 of the sorted fact lines of that family."""
    by = {}
    for f in fx:
        by.setdefault(f[0], []).append(fact_line(f))
    return {k: hashlib.sha256("\n".join(sorted(v)).encode()).hexdigest() for k, v in sorted(by.items())}


def stats(vs, h, g, sorts=None):
    try:
        vc = rev3.VC(h, g, sorts)
        hyps = [sx(x) for x in vc.hyps]
        fx = vc.facts()
    except rev3.Refused as e:
        return dict(hyps=[sx(x) for x in h], goal=sx(g), refused=e.construct, why=e.why)
    fam = {}
    for f in fx:
        fam[f[0]] = fam.get(f[0], 0) + 1
    return dict(hyps=hyps, goal=sx(g), facts=len(fx), T=vc.T, capped=vc.capped,
                closure=vc.closure_size, maxdeg=vc.max_deg, families=dict(sorted(fam.items())),
                fact_digests=fact_digests(fx))


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_OUT
    rows = []
    for rec in rev3.TBL:
        vs, h, g = rec["w"]
        r = dict(name=rev3.short(rec["name"]), group=rec["group"], truth=rec["truth"], vars=sorted(vs))
        r.update(stats(vs, h, g, rec["sorts"]))
        rows.append(r)
    extra = []
    # section 7: the refusal scan
    for name, v, h, g in [("C1", "x y", [], "(= (* 0 (/ x y)) 0)"),
                          ("C2", "x y", [], "(= (- (/ x y) (/ x y)) 0)"),
                          ("C3", "x y", [], "(= (* 0 (mod x y)) 0)"),
                          ("C4", "x", [], "(= (* 0 (/ x 0)) 0)"),
                          ("C5", "x", [], "(>= (* x (/ x (- 0 2))) 0)"),
                          ("C6", "x y w", ["(= w (* 0 (/ x y)))"], "(= w 0)"),
                          ("C7", "x", [], "(= (* 0 (/ x 2)) 0)"),
                          ("C8", "x w", ["(>= w 0)"], "(>= (* (mod x (+ 1 2)) w) 0)")]:
        vs, hh, gg = rev3.W(v, h, g)
        r = dict(name=name, kind="refusal", vars=sorted(vs))
        r.update(stats(vs, hh, gg))
        extra.append(r)
    # section 6: the chains
    for kind in ("sq1", "mix"):
        for n in (1, 2, 3, 6):
            hy = [f"(= x{i+1} (+ (* x{i} x{i}) 1))" if kind == "sq1" else f"(= x{i+1} (+ (* x{i} y) z))" for i in range(n)]
            vs, h, g = rev3.W(" ".join(f"x{i}" for i in range(n + 1)) + " y z", hy, f"(>= (* x{n} x{n}) 0)")
            r = dict(name=f"{kind}-{n}", kind="chain", vars=sorted(vs))
            r.update(stats(vs, h, g))
            extra.append(r)
    # section 4: limits
    for d in (3, 7, 8):
        vs, h, g = rev3.monotone(d)
        r = dict(name=f"monotone-{d}", kind="limit", vars=sorted(vs))
        r.update(stats(vs, h, g))
        extra.append(r)
    vs, h, g = rev3.expand((7, 7, 7))
    r = dict(name="expand-7x7x7", kind="limit", vars=sorted(vs))
    r.update(stats(vs, h, g))
    extra.append(r)
    for K in (62, 63):
        vs, h, g = rev3.crux(K)
        r = dict(name=f"crux-{K}", kind="limit", vars=sorted(vs))
        r.update(stats(vs, h, g))
        extra.append(r)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w") as f:
        json.dump(dict(source="scripts/mulvar/rev3.py sha256 14e9441d20f55f4025ae33eb5029114e0ef1fb5ac59a90efa33b884c6b4cda12",
                       witnesses=rows, extra=extra), f, indent=1)
        f.write("\n")
    print(f"{len(rows)} witnesses, {len(extra)} extra rows -> {out}")
    for r in extra:
        print(" ", r["name"], r.get("refused") or f"T={r['T']} facts={r['facts']} capped={r['capped']}")


if __name__ == "__main__":
    main()
