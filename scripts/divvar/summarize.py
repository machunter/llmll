import json, collections
d = json.load(open("r_divvar.json"))
R = d["results"]
dis = [ (r["label"], r["body"], r["disagree"]) for r in R if r["disagree"]]
print("z3/fixpoint disagreements:", dis)
fb = [(r["label"], r["op"], r["body"]) for r in R if r["verdict"].startswith("fallback")]
print("fallbacks:", fb)
capped = [(r["label"], r["op"]) for r in R if r["capped"]]
print("pair-capped:", capped)
rl = [v.get("rl") for r in R for v in r["vcs"] if v.get("rc") == "sat"]
print("recheck sat count", len(rl), "max rlimit", max(x for x in rl if x), "unvalidated:", [(r["label"], r["op"], v["tag"], v.get("rc_model")) for r in R for v in r["vcs"] if v.get("fp") == "UNSAFE" and v["verdict"] != "refuted"])
print()
print("| Function | Mutants | Non-equivalent (oracle) | Refuted | Equivalent | Verified | Other | Refuting VC (count) | Facts (sum) | max P | max div pairs | CPU s (sum) |")
print("|---|---:|---:|---:|---:|---:|---:|---|---:|---:|---:|---:|")
for name in ("row-of", "col-of", "chan-of", "scale-src", "hflip-at"):
    ms = [r for r in R if r["label"] == name and r["kind"] == "mutant"]
    ne = [r for r in ms if r["expected"] == "refuted"]
    eq = [r for r in ms if r["expected"] == "verified"]
    by = collections.Counter()
    for r in ms:
        if r["verdict"] == "refuted":
            tags = [v["tag"].split(":")[0] for v in r["vcs"] if v["verdict"] == "refuted" and v["kind"] in ("TRUTH", "BODY")]
            by[" + ".join(sorted(set(tags)))] += 1
    other = [r for r in ms if r["verdict"] not in ("refuted", "verified")]
    print(f"| `{name}` | {len(ms)} | {len(ne)} | {sum(r['verdict']=='refuted' for r in ne)} of {len(ne)} | {len(eq)} | {sum(r['verdict']=='verified' for r in eq)} of {len(eq)} | {len(other)} | " +
          "; ".join(f"{k}: {v}" for k, v in sorted(by.items())) + f" | {sum(r['facts'] for r in ms)} | {max(r['P'] for r in ms)} | {max(r['dpairs'] for r in ms)} | {sum(r['cpu'] for r in ms):.2f} |")
print()
print("| Row | Witness | Expected | Got | VCs | Facts | P | Div pairs | CPU s |")
print("|---|---|---|---|---:|---:|---:|---:|---:|")
for r in R:
    if r["kind"] == "original":
        print(f"| {r['row']} | {r['label']} | {r['expected']} | {r['verdict']}{'' if r['as_expected'] else ' **(not as expected)**'} | {len(r['vcs'])} | {r['facts']} | {r['P']} | {r['dpairs']} | {r['cpu']:.3f} |")
print()
print("equivalent mutants:")
for r in R:
    if r["kind"] == "mutant" and r["expected"] == "verified":
        print(" ", r["label"], r["op"], r["body"], r["verdict"])
print("examples:")
for r in R:
    if r["kind"] == "mutant" and ("table" in (r["op"] or "") or r["body"] in ("(/ i w)", "(/ i c)", "(/ (* (+ x 1) sw) dw)")):
        v = [x for x in r["vcs"] if x["verdict"] == "refuted"]
        print(" ", r["label"], r["op"], r["body"], r["verdict"], [(x["tag"], x.get("cex")) for x in v][:2])
print("ablation facts:")
for a in d["ablation"]:
    print(" ", a["label"][:40], a["tag"], {k: v[1] for k, v in a.items() if isinstance(v, list)})
print("total cpu", round(sum(r["cpu"] for r in R), 2), "wall", d["wall"])
