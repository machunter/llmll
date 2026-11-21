"""Extra: the role of T-literal and T-cofactor when F4, F5 and F10 are omitted (as over the 64-pair cap).
MAX_PAIRS is set to 0 so every constraint is 'capped'. Writes r_capped.json."""
import json, multiprocessing as mp
import divvar_run as R, divvar_lib as L, divvar_core as D, mulvar_rev3 as M

CFGS = [("full", {}), ("Tzero-only", dict(Tlit=False, Tcof=False)), ("-Tcof", dict(Tcof=False)), ("-Tlit", dict(Tlit=False)), ("-G", dict(G=False)), ("-D0", dict(D0=False))]

def one(job):
    M.MAX_PAIRS = 0
    label, tag, h, g, so = job
    out = dict(label=label, tag=tag)
    for nm, cfg in CFGS:
        r = L.run_vc(h, g, so, cfg=cfg, z3check=False, recheck=False)
        out[nm] = (r.get("fp") or r["verdict"], r.get("facts"), r.get("cpu"))
    return out

if __name__ == "__main__":
    R.build_tasks(mutants=False)
    jobs = []
    for t in R.TASKS:
        if t["kind"] == "original" and t["row"] in ("1", "2", "3", "4"):
            for tag, k, h, g, so in L.vcs_of(t["f"], body=t["body"], wd_pre_only=t["wd_pre_only"]):
                if tag in ("truth", "read") or "pre-only" in tag:
                    if not any(j[0] == t["label"] and j[1] == tag for j in jobs):
                        jobs.append((t["label"], tag, h, g, so))
    with mp.Pool(6) as p:
        res = list(p.imap(one, jobs))
    for r in res:
        print(f"{r['label'][:46]:46s} {r['tag']:24s} " + " ".join(f"{nm}:{r[nm][0]}/{r[nm][1]}" for nm, _ in CFGS))
    json.dump(res, open("r_capped.json", "w"), indent=1)
