#!/usr/bin/env python3
"""DIV-VAR-1: export the witness-table VCs and their division-pass statistics for the hspec suite.

Follows scripts/mulvar/export_witnesses.py. For each VC of the originals of
rows 1 to 4 of the witness table (the 44 VCs of the invariance run), of the
probes of rows 5 to 7, and of a few limit and trigger rows, this writes the
hypotheses as the script's VC holds them (top-level `and` split, ground facts
added) and the goal, as s-expression text, with what divvar_core.py gives: the
number of facts, the pairs P, the cap state, the closure size, the largest
degree, the facts per family, a SHA-256 of the fact lines per family, the
division pairs of the pass and after the whole generator, and the G trigger
set of each pair; or the refusal construct.

The export runs the generator with D4rule=False: Rev 4 of Part C drops D4's
rule clause, whose facts are F9 at a division atom (ambiguity A6). For each
row it also checks that the two readings give the same fact set when the
family is ignored, which is what A6 states.

Usage: python3 scripts/divvar/export_witnesses.py [out.json]
Default out: compiler/test/fixtures/div_var_1/witnesses.json
"""
import hashlib
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import divvar_core as D  # noqa: E402
import divvar_lib as L  # noqa: E402
import divvar_run as R  # noqa: E402
import mulvar_rev3 as M  # noqa: E402

REPO = os.path.dirname(os.path.dirname(HERE))
DEFAULT_OUT = os.path.join(REPO, "compiler", "test", "fixtures", "div_var_1", "witnesses.json")
CFG = dict(D4rule=False)


def sx(t):
    if isinstance(t, str):
        return t
    return "(" + " ".join(sx(x) for x in t) + ")"


def rel(o, p):
    o2, p2 = M.VC.canon(o, p)
    return f"{o2}[{M.pkey(p2)}]"


def fact_line(f):
    """As scripts/mulvar/export_witnesses.py: family, premises as a set, conclusion; atoms as the script's keys."""
    fam, prem, con = f
    return f"{fam}|{';'.join(sorted({rel(o, p) for o, p in prem}))}|{rel(*con)}"


def fact_digests(fx):
    by = {}
    for f in fx:
        by.setdefault(f[0], []).append(fact_line(f))
    return {k: hashlib.sha256("\n".join(sorted(v)).encode()).hexdigest() for k, v in sorted(by.items())}


def triggers(vc):
    """Per pair (as `pkey e|pkey d`), the sorted trigger polynomials (pkey), as pre_facts() builds them."""
    return vc.div_triggers


def gen(h, g, sorts, cfg):
    D.CFG.clear()
    D.CFG.update(D.DEFAULT_CFG, **cfg)
    vc = M.mkvc(h, g, sorts or None)
    fx = vc.facts()
    return vc, fx


def stats(h, g, sorts=None):
    try:
        vc, fx = gen(h, g, sorts, CFG)
    except M.Refused as e:
        return dict(hyps=[sx(x) for x in h], goal=sx(g), refused=e.construct, why=e.why)
    # A6: with the rule clause of D4 the fact set is the same, families aside
    _, fx_rule = gen(h, g, sorts, dict(CFG, D4rule=True))
    same = sorted(fact_line(("", p, c)) for _, p, c in fx) == sorted(fact_line(("", p, c)) for _, p, c in fx_rule)
    fam = {}
    for f in fx:
        fam[f[0]] = fam.get(f[0], 0) + 1
    return dict(hyps=[sx(x) for x in vc.hyps], goal=sx(g), facts=len(fx), T=vc.T, capped=vc.capped,
                closure=vc.closure_size, maxdeg=vc.max_deg, families=dict(sorted(fam.items())),
                fact_digests=fact_digests(fx), dpairs_pass=vc.div_stats.get("pairs", 0), dpairs=len(vc.pairs),
                triggers=triggers(vc), a6_same=same)


def vc_rows(tasks):
    rows = []
    for t in tasks:
        seen = set()
        for tag, kind, h, g, so in L.vcs_of(t["f"], body=t["body"], wd_pre_only=t["wd_pre_only"]):
            if tag in seen:
                continue
            seen.add(tag)
            vs = sorted(set(L.vars_of(h, g).split()))
            r = dict(row=t["row"], label=t["label"], tag=tag, kind=kind, vars=vs, sorts=so or {})
            r.update(stats(h, g, so))
            rows.append(r)
    return rows


def lim_row(name, n, image=False):
    """n pairs (/ x_i d) written; with image, a rule x1 -> y makes one more pair (y, d)."""
    terms = " ".join(f"(/ x{i} d)" for i in range(1, n + 1))
    hyps = ["(>= d 1)"] + (["(= x1 y)"] if image else [])
    goal = f"(>= (+ {terms}) 0)"
    vs = ["d"] + [f"x{i}" for i in range(1, n + 1)] + (["y"] if image else [])
    r = dict(name=name, kind="limit", vars=sorted(vs), sorts={})
    r.update(stats([M.parse(x) for x in hyps], M.parse(goal)))
    return r


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_OUT
    R.build_tasks(mutants=False)
    originals = [t for t in R.TASKS if t["kind"] == "original" and t["row"] in ("1", "2", "3", "4")]
    probes = [t for t in R.TASKS if t["kind"] == "original" and t["row"] in ("5", "6", "7")]
    vcs = vc_rows(originals)
    prb = vc_rows(probes)
    extra = []
    # row 7: the refusal scan
    for i, term in enumerate(("(/ x 0)", "(mod x 0)", "(/ x -2)", "(mod x -3)", "(/ x (- 0 2))", "(mod x (- 2 2))",
                              "(/ x (/ 1 2))", "(rem x d)", "(quot x d)")):
        r = dict(name=f"R{i + 1}", kind="refusal", term=term, vars=["d", "x"], sorts={})
        r.update(stats([M.parse("(>= d 1)")], M.parse(f"(>= {term} 0)")))
        extra.append(r)
    # the limit of 32 division pairs; image pairs count (A2)
    extra.append(lim_row("lim-32", 32))
    extra.append(lim_row("lim-33", 33))
    extra.append(lim_row("lim-31-image", 31, image=True))
    extra.append(lim_row("lim-32-image", 32, image=True))
    # A1: T-literal reads literals as written; A3: T-cofactor does not iterate over G monomials
    for name, v, h, g in [("trig-a3", "e d a", ["(>= d 1)"], "(= (/ e d) a)"),
                          ("trig-a3-written", "e d a", ["(>= d 1)", "(>= (* a d) 0)"], "(= (/ e d) a)")]:
        r = dict(name=name, kind="trigger", vars=sorted(v.split()), sorts={})
        r.update(stats([M.parse(x) for x in h], M.parse(g)))
        extra.append(r)
    for r in vcs + prb + extra:
        if "a6_same" in r and not r["a6_same"]:
            print("A6 does not hold for", r.get("label") or r.get("name"), r.get("tag", ""))
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w") as f:
        json.dump(dict(source="scripts/divvar/divvar_core.py on scripts/mulvar/rev3.py "
                              "sha256 14e9441d20f55f4025ae33eb5029114e0ef1fb5ac59a90efa33b884c6b4cda12, D4rule=False",
                       vcs=vcs, probes=prb, extra=extra), f, indent=1)
        f.write("\n")
    print(f"{len(vcs)} VCs (rows 1-4), {len(prb)} probe VCs (rows 5-7), {len(extra)} extra rows -> {out}")
    for r in extra:
        print(" ", r["name"], r.get("refused") or f"T={r['T']} facts={r['facts']} dpairs={r['dpairs_pass']}/{r['dpairs']}")


if __name__ == "__main__":
    main()
