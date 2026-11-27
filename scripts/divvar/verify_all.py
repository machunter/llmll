#!/usr/bin/env python3
"""DIV-VAR-1: run `llmll --json verify --trust-report` on every task of the witness table and record the result.

The fixtures come from scripts/divvar/to_llmll.py. Each file runs in a fresh
temporary folder, so no sidecar is written into the repo. Runs are serial.
geom.llmll is verified first; a module that imports it gets a copy of it and
of its sidecar. The binary is $LLMLL_BIN, else `llmll` on PATH. With
--trace DIR, LLMLL_RECHECK_TRACE writes one JSON line per recheck query to
DIR/<task>.jsonl.

Usage: python3 scripts/divvar/verify_all.py OUT.json [--only PREFIX] [--trace DIR] [--fixtures DIR]
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
DEFAULT_DIR = os.path.join(REPO, "scripts", "tests", "fixtures", "div_var_1")


def last_json(text):
    lines = [x for x in text.splitlines() if x.strip()]
    try:
        return json.loads(lines[-1])
    except (ValueError, IndexError):
        return None


def verdict_of(doc, fid):
    """(verdict, fallback cause, fallback constructs) of function fid: refuted comes before ill-defined, as in
    the script's combine()."""
    if doc is None:
        return "no-json", None, None
    causes, constructs = doc.get("body_fallback_causes") or {}, doc.get("body_fallback_constructs") or {}
    if fid in (doc.get("abstraction_fallback") or {}) or fid in (doc.get("body_fallback") or []):
        return "fallback", causes.get(fid), constructs.get(fid) or (doc.get("abstraction_fallback") or {}).get(fid)
    tr = doc.get("trust_report") or {}
    tr = json.loads(tr) if isinstance(tr, str) else tr
    if any(e.get("name") == fid and e.get("refuted") for e in tr.get("entries", [])):
        return "refuted", None, None
    if fid in (doc.get("ill_defined") or []):
        return "ill-defined", None, None
    if fid in (doc.get("body_faithful") or []):
        # another function of the file may be refuted; the entry of this one is then not refuted and not listed
        return ("verified" if doc.get("solver_verdict") == "safe" else "solver-" + str(doc.get("solver_verdict"))), None, None
    return "other:" + str(doc.get("solver_verdict")), None, None


def run(exe, cwd, name, trace=None):
    env = dict(os.environ)
    if trace:
        env["LLMLL_RECHECK_TRACE"] = trace
    t0 = time.time()
    p = subprocess.run([exe, "--json", "verify", "--trust-report", name], cwd=cwd, capture_output=True, text=True, env=env)
    return p, last_json(p.stdout), round(time.time() - t0, 2)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--only", default="")
    ap.add_argument("--trace")
    ap.add_argument("--fixtures", default=DEFAULT_DIR)
    a = ap.parse_args()
    exe = os.environ.get("LLMLL_BIN") or shutil.which("llmll")
    ver = subprocess.run([exe, "--version"], capture_output=True, text=True).stdout.strip()
    expected = json.load(open(os.path.join(a.fixtures, "expected.json")))
    if a.trace:
        a.trace = os.path.abspath(a.trace)   # each run has its own working folder
        os.makedirs(a.trace, exist_ok=True)
    base = tempfile.mkdtemp(prefix="divvar-geom-")
    shutil.copy(os.path.join(a.fixtures, "geom.llmll"), base)
    p, doc, _ = run(exe, base, "geom.llmll")
    assert p.returncode == 0 and doc and doc["solver_verdict"] == "safe", p.stdout + p.stderr
    res, bad = {}, []
    for name, t in sorted(expected["tasks"].items(), key=lambda kv: (kv[1]["row"], kv[1]["kind"] != "original", kv[0])):
        if not name.startswith(a.only):
            continue
        tmp = tempfile.mkdtemp(prefix="divvar-")
        try:
            shutil.copy(os.path.join(a.fixtures, t["file"]), tmp)
            if t["first"]:
                shutil.copy(os.path.join(base, "geom.llmll"), tmp)
                shutil.copy(os.path.join(base, "geom.llmll.verified.json"), tmp)
            p, doc, wall = run(exe, tmp, t["file"], os.path.join(a.trace, name + ".jsonl") if a.trace else None)
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
        v, cause, constructs = verdict_of(doc, t["id"])
        ok = v in t["expected"]
        rec = dict(verdict=v, expected=t["expected"], ok=ok, exit_code=p.returncode, wall=wall, counted=t["counted"],
                   row=t["row"], kind=t["kind"], cause=cause, constructs=constructs,
                   solver_verdict=(doc or {}).get("solver_verdict"),
                   messages=[d.get("message") for d in (doc or {}).get("diagnostics", []) if d.get("severity") == "error"],
                   codes=sorted({d.get("code") for d in (doc or {}).get("diagnostics", []) if d.get("code")}))
        if not ok:
            rec.update(stdout=p.stdout[-3000:], stderr=p.stderr[-1000:])
            bad.append(name)
        res[name] = rec
        print(f"{name:16s} exp={'|'.join(t['expected']):22s} got={v:12s} exit {p.returncode} {wall:7.2f}s {'' if ok else '<-- NOT AS EXPECTED'}", flush=True)
    shutil.rmtree(base, ignore_errors=True)
    counted = [r for r in res.values() if r["counted"]]
    summary = dict(tasks=len(res), counted=len(counted), counted_as_expected=sum(r["ok"] for r in counted), not_as_expected=bad,
                   wall=round(sum(r["wall"] for r in res.values()), 1))
    with open(a.out, "w") as f:
        json.dump(dict(llmll_version=ver, binary=exe, summary=summary, tasks=res), f, indent=1, sort_keys=True)
        f.write("\n")
    print(json.dumps(summary, indent=1))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
