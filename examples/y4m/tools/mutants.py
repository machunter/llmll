#!/usr/bin/env python3
"""Plausible wrong bodies for the core, each verified in a scratch copy.
One at a time, never in parallel.

A mutant is expected to be refuted (verify exits non-zero), except the two
ybuf mutants that break only the length post of a returned slice. Those are
expected to fall back, exit 0, with `abstraction:app:bytes-slice`: the
compiler does not yet refute a wrong length of a returned slice
(ABSTRACTION-RESULT-LEN-1, finding F-2 of EXAMPLES-BYTES-1). They are
reported as "expected fallback", not as survivors. When that row ships they
become refutations, and this script reports them as UNEXPECTED until the
expectation here is changed.

usage: mutants.py WORKDIR
"""
import json, os, shutil, subprocess, sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LLMLL = os.environ.get("LLMLL", "llmll")
CORE = ("raster", "hdr", "xform", "ybuf")

# (module, old, new, what, expect). expect is "refuted", or
# ("fallback", fn, construct) for an expected fallback of fn.
F2 = "abstraction:app:bytes-slice"
MUTANTS = [
    ("raster", "(/ (+ n 1) 2)", "(/ n 2)", "chroma-dim drops the odd column", "refuted"),
    ("raster", "(if (< (+ x 1) pw) y (if (< (+ y 1) ph) (+ y 1) 0))",
               "(if (< (+ x 1) pw) y (+ y 1))", "next-y never wraps", "refuted"),
    ("raster", "(if (or (< (+ x 1) pw) (< (+ y 1) ph)) p (if (= p 2) 0 (+ p 1)))",
               "(if (< (+ x 1) pw) p (if (= p 2) 0 (+ p 1)))", "next-p moves on at every row end", "refuted"),
    ("raster", "(if (= k 5) (if (= b 10) 6 (if (= b 32) 7 -1))",
               "(if (= k 5) (if (= b 10) 6 7)", "marker accepts FRAMEX", "refuted"),
    ("hdr", "(if (= v -1) (- b 48) (+ (* 10 v) (- b 48)))",
            "(if (= v -1) (- b 48) (+ v (- b 48)))", "num-step forgets the place value", "refuted"),
    ("hdr", "(if (or (< w 1) (> w 16384)) 5", "(if (> w 16384) 5", "header-problem admits W0", "refuted"),
    ("xform", "(ccw (chroma-dim cw))", "(ccw (/ cw 2))", "crop-keep? chroma window of cw/2", "refuted"),
    ("xform", "(let [(cx (/ x0 2))", "(let [(cx x0)", "crop-keep? chroma window at x0", "refuted"),
    ("xform", "(- (- pw 1) x)", "(- pw x)", "hflip-src off by one", "refuted"),
    ("xform", "(and (= (mod x0 2) 0) (and (= (mod y0 2) 0)", "(and (= (mod x0 2) 0) (and true",
              "crop-ok? forgets that y0 is even", "refuted"),
    ("ybuf", "(if (< i (bytes-length buf))", "(if (<= i (bytes-length buf))",
             "find-lf reads at the end (Y-1)", "refuted"),
    ("ybuf", "(if (= k2 6) (+ i 1)", "(if (= k2 6) i",
             "marker-end answers the LF offset (Y-2)", "refuted"),
    ("ybuf", "(bytes-slice fr 0 (* w h))", "(bytes-slice fr 0 (* w (- h 1)))",
             "luma-plane one row short (Y-3)", ("fallback", "luma-plane", F2)),
    ("ybuf", "(bytes-slice (bytes-slice pl ro (+ ro pw)) x0 (+ x0 cw))",
             "(bytes-slice (bytes-slice pl ro (+ ro pw)) x0 (+ x0 (+ cw 1)))",
             "crop-row one column too wide (Y-4 A)", "refuted"),
    ("ybuf", "(bytes-slice (bytes-slice pl ro (+ ro pw)) x0 (+ x0 cw))",
             "(bytes-slice (bytes-slice pl ro (+ ro pw)) (+ x0 1) (+ x0 cw))",
             "crop-row shifted right, one column short (Y-4 B)", ("fallback", "crop-row", F2)),
    ("ybuf", "(bytes-get row (hflip-src (bytes-length row) ox))", "(bytes-get row (- (bytes-length row) ox))",
             "hflip-at off by one (Y-5)", "refuted"),
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
    as_expected = refuted = fallbacks = 0
    for i, (mod, old, new, what, expect) in enumerate(MUTANTS):
        d = os.path.join(work, f"m{i}")
        shutil.rmtree(d, ignore_errors=True)
        os.makedirs(d)
        for m in CORE:
            for suf in (".llmll", ".llmll.verified.json"):
                if os.path.exists(os.path.join(HERE, m + suf)):
                    shutil.copy(os.path.join(HERE, m + suf), d)
        src = open(os.path.join(d, mod + ".llmll")).read()
        if src.count(old) < 1:
            sys.exit(f"mutant {i}: pattern not found")
        # The body comes after the contract, so mutate the last occurrence.
        k = src.rindex(old)
        open(os.path.join(d, mod + ".llmll"), "w").write(src[:k] + new + src[k + len(old):])
        p = subprocess.run([LLMLL, "--json", "verify", mod + ".llmll"], cwd=d, capture_output=True, text=True)
        doc = last_json(p.stdout)
        constructs = doc.get("body_fallback_constructs", {})
        if p.returncode != 0:
            got = "refuted"
            msgs = [x.get("message", "") for x in doc.get("diagnostics", []) if x.get("severity") == "error"]
            detail = f"{doc.get('solver_verdict')} | {(msgs[0] if msgs else (p.stdout + p.stderr).strip()[-140:])[:140]}"
        else:
            got = "fallback" if constructs else "verified"
            detail = f"{doc.get('solver_verdict')} | fallback {constructs}"
        if expect == "refuted":
            ok = got == "refuted"
            label = "refuted" if ok else "SURVIVED"
        else:
            _, fn, construct = expect
            ok = got == "fallback" and constructs.get(fn) == [construct]
            label = "expected fallback (F-2)" if ok else f"UNEXPECTED {got} (expected fallback {construct})"
        as_expected += ok
        refuted += got == "refuted"
        fallbacks += ok and got == "fallback"
        print(f"{label}: {mod}: {what} | {detail}")
    n_ref = sum(1 for m in MUTANTS if m[4] == "refuted")
    print(f"{refuted} of {n_ref} mutants refuted; {fallbacks} of {len(MUTANTS) - n_ref} "
          f"expected fallbacks ({F2}, ABSTRACTION-RESULT-LEN-1); "
          f"{as_expected} of {len(MUTANTS)} as expected")
    sys.exit(0 if as_expected == len(MUTANTS) else 1)


if __name__ == "__main__":
    main()
