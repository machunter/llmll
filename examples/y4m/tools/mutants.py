#!/usr/bin/env python3
"""Plausible wrong bodies for the core, each verified in a scratch copy.
A mutant must be refuted (verify exits non-zero). One at a time, never in
parallel.

usage: mutants.py WORKDIR
"""
import os, shutil, subprocess, sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LLMLL = os.environ.get("LLMLL", "llmll")

MUTANTS = [
    ("raster", "(/ (+ n 1) 2)", "(/ n 2)", "chroma-dim drops the odd column"),
    ("raster", "(if (< (+ x 1) pw) y (if (< (+ y 1) ph) (+ y 1) 0))",
               "(if (< (+ x 1) pw) y (+ y 1))", "next-y never wraps"),
    ("raster", "(if (or (< (+ x 1) pw) (< (+ y 1) ph)) p (if (= p 2) 0 (+ p 1)))",
               "(if (< (+ x 1) pw) p (if (= p 2) 0 (+ p 1)))", "next-p moves on at every row end"),
    ("raster", "(if (= k 5) (if (= b 10) 6 (if (= b 32) 7 -1))",
               "(if (= k 5) (if (= b 10) 6 7)", "marker accepts FRAMEX"),
    ("hdr", "(if (= v -1) (- b 48) (+ (* 10 v) (- b 48)))",
            "(if (= v -1) (- b 48) (+ v (- b 48)))", "num-step forgets the place value"),
    ("hdr", "(if (or (< w 1) (> w 16384)) 5", "(if (> w 16384) 5", "header-problem admits W0"),
    ("xform", "(ccw (chroma-dim cw))", "(ccw (/ cw 2))", "crop-keep? chroma window of cw/2"),
    ("xform", "(let [(cx (/ x0 2))", "(let [(cx x0)", "crop-keep? chroma window at x0"),
    ("xform", "(- (- pw 1) x)", "(- pw x)", "hflip-src off by one"),
    ("xform", "(and (= (mod x0 2) 0) (and (= (mod y0 2) 0)", "(and (= (mod x0 2) 0) (and true",
              "crop-ok? forgets that y0 is even"),
]


def main():
    work = sys.argv[1]
    killed = 0
    for i, (mod, old, new, what) in enumerate(MUTANTS):
        d = os.path.join(work, f"m{i}")
        shutil.rmtree(d, ignore_errors=True)
        os.makedirs(d)
        for m in ("raster", "hdr", "xform"):
            for suf in (".llmll", ".llmll.verified.json"):
                if os.path.exists(os.path.join(HERE, m + suf)):
                    shutil.copy(os.path.join(HERE, m + suf), d)
        src = open(os.path.join(d, mod + ".llmll")).read()
        if src.count(old) < 1:
            sys.exit(f"mutant {i}: pattern not found")
        # The body comes after the contract, so mutate the last occurrence.
        k = src.rindex(old)
        open(os.path.join(d, mod + ".llmll"), "w").write(src[:k] + new + src[k + len(old):])
        p = subprocess.run([LLMLL, "verify", mod + ".llmll"], cwd=d, capture_output=True, text=True)
        out = p.stdout + p.stderr
        ok = p.returncode != 0
        killed += ok
        line = next((l for l in out.splitlines() if "error" in l.lower()), out.strip().splitlines()[-1])
        print(f"{'refuted' if ok else 'SURVIVED'}: {mod}: {what} | {line.strip()[:140]}")
    print(f"{killed} of {len(MUTANTS)} mutants refuted")
    sys.exit(0 if killed == len(MUTANTS) else 1)


if __name__ == "__main__":
    main()
