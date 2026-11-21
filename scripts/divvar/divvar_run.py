#!/usr/bin/env python3
"""DIV-VAR-1 witness table (IMAGE-LIB-1 Rev 3, Part C). Writes r_divvar.json and prints a log.
Usage: python3 divvar_run.py [--jobs N] [--skip-mutants]"""
import json
import multiprocessing as mp
import random
import sys
import time

import divvar_core as D
import divvar_lib as L
import mulvar_rev3 as M

F = L.FUNS


def fn(params, pre, post, body, sorts=None):
    return dict(params=params, pre=pre, post=post, body=body, sorts=sorts or {})


TASKS = []


def task(row, label, f, body=None, expected="verified", kind="original", note="", wd_pre_only=False, oracle=None, op=None, count=True):
    TASKS.append(dict(row=row, label=label, f=f, body=body or f["body"], expected=expected, kind=kind,
                      note=note, wd_pre_only=wd_pre_only, oracle=oracle, op=op, count=count))


def build_tasks(mutants=True):
    gen_report = {}
    for name in ("row-of", "col-of", "chan-of", "scale-src", "hflip-at"):
        f = F[name]
        task("1", name, f, wd_pre_only=(name == "hflip-at"))
        ms, gen = L.mutants(f)
        gen_report[name] = dict(n=len(ms), example=f.get("example"), example_generated=gen,
                                ops=sorted({lab.split()[0] for lab, _ in ms}))
        if not mutants:
            continue
        for lab, mb in ms:
            o = L.oracle(name, f, mb)
            exp = "verified" if o == "equivalent" else "refuted"
            task("1", name, f, body=mb, expected=exp, kind="mutant", oracle=o, op=lab)
    # row 2: edge case 7
    s = F["scale-src"]
    pre1 = "(and (= sw 1) " + s["pre"] + ")"
    task("2", "scale-src sw=1, post as written", fn(s["params"], pre1, s["post"], s["body"]))
    task("2", "scale-src sw=1, (= result 0)", fn(s["params"], pre1, "(= result 0)", s["body"]))
    # row 3: D4, a let-bound stride against (* w c)
    r = F["row-of"]
    task("3", "row-of, body (let ((stride (* w c))) (/ i stride))", fn(r["params"], r["pre"], r["post"], "(let ((stride (* w c))) (/ i stride))"))
    # row 4: round trips through offset (G at t = y)
    op_ = F["offset"]
    task("4", "row-of(offset(y,x,k)) = y", fn(op_["params"], op_["pre"], "(= result y)", "(row-of w c h (offset w h c y x k))"))
    task("4", "col-of(offset(y,x,k)) = x (extra)", fn(op_["params"], op_["pre"], "(= result x)", "(col-of w c h (offset w h c y x k))"))
    task("4", "chan-of(offset(y,x,k)) = k (extra)", fn(op_["params"], op_["pre"], "(= result k)", "(chan-of c (offset w h c y x k))"))
    # row 5: the shadowing probe, adapted
    pre5 = "(and (>= d 1) (>= i 0))"
    task("5", "shadow d: post (/ i d), body (let ((d (+ d 1))) (/ i d))", fn("i d", pre5, "(= result (/ i d))", "(let ((d (+ d 1))) (/ i d))"), expected="refuted")
    task("5", "shadow d: post (mod i d), body (let ((d (+ d 1))) (mod i d))", fn("i d", pre5, "(= result (mod i d))", "(let ((d (+ d 1))) (mod i d))"), expected="refuted")
    task("5", "shadow i: post (/ i d), body (let ((i (+ i 1))) (/ i d))", fn("i d", pre5, "(= result (/ i d))", "(let ((i (+ i 1))) (/ i d))"), expected="refuted")
    task("5", "shadow i, equivalent: post (mod i d), body (let ((i (+ i d))) (mod i d)) (info)", fn("i d", pre5, "(= result (mod i d))", "(let ((i (+ i d))) (mod i d))"),
         expected="verified", count=False, note="true claim; needs uniqueness across two pairs; informational")
    # row 6: guarded against unguarded clause
    task("6", "pre (=> (>= d 1) (= (/ e d) q))", fn("e d q", "(=> (>= d 1) (= (/ e d) q))", "(= result e)", "e"))
    task("6", "pre (= (/ e d) q), unguarded", fn("e d q", "(= (/ e d) q)", "(= result e)", "e"), expected="ill-defined")
    task("6", "guarded use: pre (and (>= e 0) (=> (>= d 1) (= (/ e d) q))), post (=> (>= d 1) (>= q 0))",
         fn("e d q", "(and (>= e 0) (=> (>= d 1) (= (/ e d) q)))", "(=> (>= d 1) (>= q 0))", "e"))
    # row 7, solver part: a divisor that is not ground but is not >= 1
    task("7", "edge case 6: (/ x (- 0 w)), pre (>= w 1)", fn("x w", "(>= w 1)", "(= result (/ x (- 0 w)))", "(/ x (- 0 w))"), expected="refuted|ill-defined")
    task("7", "divisor (- w w)", fn("x w", "(>= w 1)", "(= result (/ x (- w w)))", "(/ x (- w w))"), expected="refuted|ill-defined")
    return gen_report


def run_task(t):
    t0 = time.time()
    vcs = L.vcs_of(t["f"], body=t["body"], wd_pre_only=t["wd_pre_only"])
    seen, res = {}, []
    for tag, kind, h, g, so in vcs:
        key = json.dumps([h, g])
        if key in seen:
            continue
        seen[key] = 1
        r = L.run_vc(h, g, so)
        res.append((tag, kind, r))
    if t["wd_pre_only"]:
        main = [x for x in res if "pre-only" not in x[0]]
    else:
        main = res
    out = dict(t)
    out.pop("f")
    out["verdict"] = L.combine(main)
    out["pre_only_wd"] = [(tag, r["verdict"]) for tag, k, r in res if "pre-only" in tag]
    out["vcs"] = [dict(tag=tag, kind=k, **{kk: vv for kk, vv in r.items()}) for tag, k, r in res]
    out["facts"] = sum(r.get("facts", 0) for _, _, r in res)
    out["P"] = max([r.get("T", 0) for _, _, r in res] or [0])
    out["dpairs"] = max([r.get("dpairs", 0) for _, _, r in res] or [0])
    out["cpu"] = round(sum(r.get("cpu", 0.0) for _, _, r in res), 3)
    out["capped"] = any(r.get("capped") for _, _, r in res)
    out["disagree"] = [tag for tag, _, r in res if "z3" in r and r.get("fp", "").startswith(("SAFE", "UNSAFE")) and (r["z3"] == "unsat") != r["fp"].startswith("SAFE")]
    out["wall"] = round(time.time() - t0, 2)
    exp = t["expected"].split("|")
    out["as_expected"] = out["verdict"] in exp
    return out


# ---------------------------------------------------------------- ablation
ABL = [("-G", dict(G=False)), ("-D0", dict(D0=False)), ("-D4", dict(D4=False)), ("-D4-F9div", dict(D4=False, F9div=False)),
       ("-Tlit", dict(Tlit=False)), ("-Tcof", dict(Tcof=False)), ("-Tzero", dict(Tzero=False)),
       ("Tzero-only", dict(Tlit=False, Tcof=False)), ("Tlit-only", dict(Tzero=False, Tcof=False)), ("Tcof-only", dict(Tzero=False, Tlit=False))]


def ablate(job):
    label, tag, h, g, so = job
    row = dict(label=label, tag=tag)
    for nm, cfg in ABL:
        r = L.run_vc(h, g, so, cfg=cfg, z3check=False, recheck=False)
        row[nm] = (r.get("fp") or r["verdict"], r.get("facts", 0))
    return row


def sens(job):
    label, tag, h, g, so = job
    a = L.run_vc(h, g, so, z3check=False, recheck=False)
    b = L.run_vc(h, g, so, cfg=dict(tlit_rules=True), z3check=False, recheck=False)
    return dict(label=label, tag=tag, literal=(a.get("fp") or a["verdict"], a.get("facts")), rules=(b.get("fp") or b["verdict"], b.get("facts")))


# ---------------------------------------------------------------- invariance (row 8)
def invariance(jobs):
    rnd = random.Random(11)
    checks = fails = 0
    failed = []
    ctl_fail = 0
    block_same = block_diff = 0
    verdict_changes = []
    for label, tag, h, g, so in jobs:
        D.CFG.clear(); D.CFG.update(D.DEFAULT_CFG)
        vs = set(L.vars_of(h, g).split())
        rec = dict(w=(vs, h, g), sorts=so or None, name=label)
        vc = M.mkvc(h, g, so or None)
        fx = vc.facts()
        for kind, vs2, h2, g2, so2, m in M.variants(rec, rnd):
            vc2 = M.mkvc(h2, g2, so2)
            n = {vc2.s_fact(f, {}) for f in vc2.facts()}
            b = {vc.s_fact(f, m) for f in fx}
            checks += 1
            if b != n:
                fails += 1
                failed.append((label, tag, kind, len(b ^ n)))
            # control: order-dependent T-literal must be caught by the same comparison
            D.CFG["ctl_first"] = D.CFG["ctl_first_lit"] = True
            vcc, vcc2 = M.mkvc(h, g, so or None), M.mkvc(h2, g2, so2)
            if {vcc.s_fact(f, m) for f in vcc.facts()} != {vcc2.s_fact(f, {}) for f in vcc2.facts()}:
                ctl_fail += 1
            D.CFG["ctl_first"] = D.CFG["ctl_first_lit"] = False
        # fact block text under shuffle and flip
        hs = list(h)
        x = [M.flip(y) for y in hs]
        rnd.shuffle(x)
        _, v1, _ = M.build_fq(vs, hs, g, so or None)
        _, v2, _ = M.build_fq(vs, x, M.flip(g), so or None)
        if v1.fact_block == v2.fact_block:
            block_same += 1
        else:
            block_diff += 1
        # verdict on one combined variant
        var = [v for v in M.variants(rec, rnd, 1) if v[0] == "combined"][0]
        _, vs2, h2, g2, so2, _ = var
        a = L.run_vc(h, g, so, z3check=False, recheck=False)
        b = L.run_vc(h2, g2, so2, z3check=False, recheck=False)
        if a.get("fp") != b.get("fp"):
            verdict_changes.append((label, tag, a.get("fp"), b.get("fp")))
    return dict(checks=checks, fails=fails, failed=failed[:20], control_differs=ctl_fail,
                block_same=block_same, block_diff=block_diff, verdict_changes=verdict_changes, vcs=len(jobs))


# ---------------------------------------------------------------- row 7, refusal scan
def refusal_rows():
    out = []
    for term in ("(/ x 0)", "(mod x 0)", "(/ x -2)", "(mod x -3)", "(/ x (- 0 2))", "(mod x (- 2 2))", "(/ x (/ 1 2))", "(rem x d)", "(quot x d)"):
        before = dict(M.SOLVER_CALLS)
        try:
            D.CFG.clear(); D.CFG.update(D.DEFAULT_CFG)
            vc = M.mkvc([M.parse("(>= d 1)")], M.parse(f"(>= {term} 0)"))
            vc.facts()
            res = "ADMITTED"
        except M.Refused as e:
            res = f"refused {e.construct}: {e.why}"
        out.append(dict(term=term, result=res, solver_calls=M.SOLVER_CALLS != before))
    return out


def main():
    jobs = 6
    if "--jobs" in sys.argv:
        jobs = int(sys.argv[sys.argv.index("--jobs") + 1])
    gen = build_tasks(mutants="--skip-mutants" not in sys.argv)
    t0 = time.time()
    print(f"{len(TASKS)} tasks, {jobs} jobs", flush=True)
    with mp.Pool(jobs) as pool:
        results = []
        for r in pool.imap(run_task, TASKS):
            results.append(r)
            flag = "" if r["as_expected"] else "   <-- NOT AS EXPECTED"
            print(f"[{r['row']}] {r['label']:60.60s} {r['kind']:8s} {(r['op'] or ''):18.18s} exp={r['expected']:12s} got={r['verdict']:18s} facts={r['facts']:6d} P={r['P']:3d} dpairs={r['dpairs']} cpu={r['cpu']:.3f}{flag}", flush=True)
            if r["kind"] == "mutant":
                print(f"      body {r['body']}  oracle: {r['oracle']}", flush=True)
        # ablation and sensitivity over originals of rows 1-4
        ab_jobs, inv_jobs = [], []
        for t in TASKS:
            if t["kind"] != "original" or t["row"] not in ("1", "2", "3", "4"):
                continue
            for tag, kind, h, g, so in L.vcs_of(t["f"], body=t["body"], wd_pre_only=t["wd_pre_only"]):
                key = (t["label"], tag)
                if any((j[0], j[1]) == key for j in inv_jobs):
                    continue
                inv_jobs.append((t["label"], tag, h, g, so))
        for j in inv_jobs:
            D.CFG.clear(); D.CFG.update(D.DEFAULT_CFG)
            try:
                vc = M.mkvc(j[2], j[3], j[4] or None)
                vc.facts()
                if len(vc.pairs):
                    ab_jobs.append(j)
            except M.Refused:
                pass
        print(f"\n--- ablation over {len(ab_jobs)} VCs with division pairs", flush=True)
        abl = list(pool.imap(ablate, ab_jobs))
        for a in abl:
            print(f"  {a['label'][:44]:44s} {a['tag']:28s} " + " ".join(f"{nm}:{a[nm][0]}" for nm, _ in ABL), flush=True)
        print("\n--- T-literal reading sensitivity (literals after rule substitution)", flush=True)
        sen = list(pool.imap(sens, ab_jobs))
        for s_ in sen:
            print(f"  {s_['label'][:44]:44s} {s_['tag']:28s} literal={s_['literal']} rules={s_['rules']}", flush=True)
    print("\n--- 8 invariance", flush=True)
    inv = invariance(inv_jobs)
    print(json.dumps(inv, indent=1), flush=True)
    print("\n--- 7 refusal scan", flush=True)
    ref = refusal_rows()
    for r in ref:
        print(f"  {r['term']:18s} {r['result']}  solver called: {r['solver_calls']}")
    print("\nmutant generation:", json.dumps(gen, indent=1))
    json.dump(dict(results=results, ablation=abl, sensitivity=sen, invariance=inv, refusal=ref, generation=gen,
                   wall=round(time.time() - t0, 1)), open("r_divvar.json", "w"), indent=1, default=str)
    n = sum(1 for r in results if r["count"])
    ok = sum(1 for r in results if r["count"] and r["as_expected"])
    print(f"\nas expected: {ok} of {n} counted tasks; wall {time.time() - t0:.1f}s")


if __name__ == "__main__":
    main()
