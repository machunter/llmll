#!/usr/bin/env python3
"""MUL-VAR-1: run `llmll --json verify` on every witness fixture and record the result.

Each fixture is copied into a fresh temporary folder first, so no sidecar is
written into the repo. Runs are serial. The binary is $LLMLL_BIN, else `llmll`
on PATH.

Usage: python3 scripts/mulvar/verify_all.py OUT.json [fixture_dir]
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
DEFAULT_DIR = os.path.join(REPO, "scripts", "tests", "fixtures", "mul_var_1")


def verdict_of(js, fid):
    """One word for function fid, from the verify JSON."""
    if js is None:
        return "no-json"
    if fid in (js.get("ill_defined") or []):
        return "ill-defined"
    if fid in (js.get("abstraction_fallback") or {}):
        return "fallback"
    if fid in (js.get("body_fallback") or []):
        return "fallback"
    if fid in (js.get("body_faithful") or []):
        sv = js.get("solver_verdict")
        if sv == "safe":
            return "verified"
        if sv == "refuted":
            return "refuted"
        return "solver-" + str(sv)
    return "other"


def main():
    out_path = sys.argv[1]
    d = sys.argv[2] if len(sys.argv) > 2 else DEFAULT_DIR
    exe = os.environ.get("LLMLL_BIN") or shutil.which("llmll")
    ver = subprocess.run([exe, "--version"], capture_output=True, text=True).stdout.strip()
    exp = json.load(open(os.path.join(d, "expected.json")))["witnesses"]
    res = {}
    for name in sorted(exp, key=lambda n: exp[n]["file"]):
        e = exp[name]
        tmp = tempfile.mkdtemp(prefix="mulvar-")
        try:
            shutil.copy(os.path.join(d, e["file"]), tmp)
            p = subprocess.run([exe, "--json", "verify", e["file"]], cwd=tmp, capture_output=True, text=True)
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
        try:
            js = json.loads(p.stdout.strip().splitlines()[-1]) if p.stdout.strip() else None
        except (ValueError, IndexError):
            js = None
        rec = dict(exit_code=p.returncode, verdict=verdict_of(js, e["id"]))
        if js is not None:
            rec["solver_verdict"] = js.get("solver_verdict")
            rec["fallback_cause"] = (js.get("body_fallback_causes") or {}).get(e["id"]) or (js.get("abstraction_fallback") or {}).get(e["id"])
            rec["fallback_constructs"] = (js.get("body_fallback_constructs") or {}).get(e["id"])
            rec["diagnostic_kinds"] = sorted({x.get("kind") for x in js.get("diagnostics", []) if x.get("kind")})
            rec["phase"] = js.get("phase")
            rec["success"] = js.get("success")
        else:
            rec["stdout_tail"] = p.stdout[-400:]
            rec["stderr_tail"] = p.stderr[-400:]
        res[name] = rec
        print(f"{name:5s} exit {rec['exit_code']} {rec['verdict']} {rec.get('fallback_cause')} {rec.get('fallback_constructs')}", flush=True)
    summary = {}
    for r in res.values():
        k = f"{r['verdict']} / {r.get('fallback_cause')} / {','.join(r.get('fallback_constructs') or [])}"
        summary[k] = summary.get(k, 0) + 1
    with open(out_path, "w") as f:
        json.dump(dict(llmll_version=ver, command="llmll --json verify <file>", summary=summary, witnesses=res), f, indent=2, sort_keys=True)
        f.write("\n")
    print(json.dumps(summary, indent=1, sort_keys=True))


if __name__ == "__main__":
    main()
