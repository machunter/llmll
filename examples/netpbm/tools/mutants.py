#!/usr/bin/env python3
"""Plausible wrong bodies for the netpbm example's binfmt (EXAMPLES-BYTES-1
B-1..B-4), each verified in a scratch copy, one at a time. Every mutant is
expected to be refuted: verify exits non-zero and an lh-unsafe diagnostic
names the mutated function.

usage: mutants.py WORKDIR
"""
import json, os, shutil, subprocess, sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LLMLL = os.environ.get("LLMLL", "llmll")

# (module, function, old, new, what)
WS = "(or (= b 9) (or (= b 10) (or (= b 11) (or (= b 12) (or (= b 13) (= b 32))))))"
MUTANTS = [
    ("binfmt", "byte-class", WS + " 0", "(or (= b 9) (or (= b 10) (or (= b 11) (or (= b 12) (= b 32))))) 0",
     "byte-class forgets CR (B-1)"),
    ("binfmt", "header-end", "(if (>= (+ nt 1) 4) (+ i 1)", "(if (>= (+ nt 1) 4) i",
     "header-end answers the offset of the whitespace byte (B-2)"),
    ("binfmt", "raster-len", "(* b (* k n))", "(* k n)",
     "raster-len ignores 16-bit samples (B-3)"),
    ("binfmt", "bin-sample", "(bytes-get buf (+ (+ off (+ i i)) 1))", "(bytes-get buf (+ (+ off (+ i i)) 2))",
     "bin-sample reads the low byte one past the sample (B-4)"),
]


def last_json(text):
    doc = None
    for ln in text.splitlines():
        ln = ln.strip()
        if ln.startswith("{") and ln.endswith("}"):
            try:
                doc = json.loads(ln)
            except ValueError:
                pass
    return doc or {}


def main():
    work = sys.argv[1]
    refuted = 0
    for i, (mod, fn, old, new, what) in enumerate(MUTANTS):
        d = os.path.join(work, f"m{i}")
        shutil.rmtree(d, ignore_errors=True)
        os.makedirs(d)
        shutil.copy(os.path.join(HERE, mod + ".llmll"), d)
        src = open(os.path.join(d, mod + ".llmll")).read()
        if src.count(old) < 1:
            sys.exit(f"mutant {i}: pattern not found")
        # The body comes after the contract, so mutate the last occurrence.
        k = src.rindex(old)
        open(os.path.join(d, mod + ".llmll"), "w").write(src[:k] + new + src[k + len(old):])
        p = subprocess.run([LLMLL, "--json", "verify", mod + ".llmll"], cwd=d, capture_output=True, text=True)
        doc = last_json(p.stdout)
        unsafe = [x.get("message", "") for x in doc.get("diagnostics", []) if x.get("kind") == "lh-unsafe"]
        ok = p.returncode != 0 and doc.get("solver_verdict") == "refuted" and any(f"'{fn}'" in m for m in unsafe)
        refuted += ok
        detail = (unsafe[0] if unsafe else (p.stdout + p.stderr).strip()[-140:])[:140]
        print(f"{'refuted' if ok else 'SURVIVED'}: {mod}: {what} | {doc.get('solver_verdict')} | {detail}")
    print(f"{refuted} of {len(MUTANTS)} mutants refuted")
    sys.exit(0 if refuted == len(MUTANTS) else 1)


if __name__ == "__main__":
    main()
