"""Independent Python reference for the netpbm example.

Runs the built LLMLL executable on every sample image and every transform,
then re-implements each transform here and compares the decoded outputs.
Also checks that malformed inputs fail with a non-zero exit and a message.

usage: python3 -I tools/crosscheck.py BUILT_EXE SAMPLES_DIR WORK_DIR
"""
import os, re, subprocess, sys

def decode(text):
    toks = re.sub(r"#[^\n]*", "", text).split()
    magic, w, h, m = toks[0], int(toks[1]), int(toks[2]), int(toks[3])
    c = {"P2": 1, "P3": 3}[magic]
    xs = [int(t) for t in toks[4:]]
    assert len(xs) == w * h * c and all(0 <= x <= m for x in xs)
    return c, w, h, m, xs

def rows(img):
    c, w, h, m, xs = img
    n = w * c
    return [xs[i * n:(i + 1) * n] for i in range(h)]

def px(row, c):
    return [row[i:i + c] for i in range(0, len(row), c)]

def flat(rs):
    return [x for r in rs for x in r]

def ref(img, op, args):
    c, w, h, m, xs = img
    if op == "copy":
        return img
    if op == "invert":
        return (c, w, h, m, [m - x for x in xs])
    if op == "threshold":
        return (c, w, h, m, [m if x >= args[0] else 0 for x in xs])
    if op == "hflip":
        return (c, w, h, m, flat(flat(px(r, c)[::-1]) for r in rows(img)))
    if op == "vflip":
        return (c, w, h, m, flat(rows(img)[::-1]))
    if op == "crop":
        x, y, cw, ch = args
        return (c, cw, ch, m, flat(r[x * c:(x + cw) * c] for r in rows(img)[y:y + ch]))
    if op == "gray":
        if c == 1:
            return img
        return (1, w, h, m, [(77 * r + 150 * g + 29 * b) // 256 for r, g, b in px(xs, 3)])
    if op == "blur":
        R = rows(img)
        cl = lambda v, n: min(max(v, 0), n - 1)
        out = []
        for y in range(h):
            for x in range(w):
                for k in range(c):
                    s = sum(R[cl(y + dy, h)][cl(x + dx, w) * c + k]
                            for dy in (-1, 0, 1) for dx in (-1, 0, 1))
                    out.append(s // 9)
        return (c, w, h, m, out)
    raise ValueError(op)

OPS = [("copy", []), ("invert", []), ("hflip", []), ("vflip", []), ("gray", []),
       ("blur", []), ("threshold", [8]), ("crop", [1, 0, 2, 2])]

def main():
    exe, samples, work = sys.argv[1:4]
    os.makedirs(work, exist_ok=True)
    fails = 0
    for name in sorted(os.listdir(samples)):
        path = os.path.join(samples, name)
        text = open(path).read()
        if name.startswith("bad-"):
            p = subprocess.run([exe, path, "copy", os.path.join(work, "x.out")],
                               capture_output=True, text=True)
            ok = p.returncode != 0 and p.stderr.strip() != ""
            print(("ok  " if ok else "FAIL"), name, "rejected:", p.returncode, p.stderr.strip())
            fails += not ok
            continue
        img = decode(text)
        for op, args in OPS:
            out = os.path.join(work, "%s.%s%s" % (os.path.splitext(name)[0], op, os.path.splitext(name)[1]))
            p = subprocess.run([exe, path, op, out] + [str(a) for a in args],
                               capture_output=True, text=True)
            if p.returncode != 0:
                print("FAIL", name, op, "exit", p.returncode, p.stderr.strip()); fails += 1; continue
            got = decode(open(out).read())
            want = ref(img, op, args)
            ok = got == want and all(len(l) <= 70 for l in open(out).read().splitlines())
            print(("ok  " if ok else "FAIL"), name, op)
            fails += not ok
    feep = os.path.join(samples, "feep.pgm")
    for argv in (["frobnicate"], ["crop", "20", "0", "5", "5"], ["threshold"],
                 ["threshold", "-3"]):
        p = subprocess.run([exe, feep, argv[0], os.path.join(work, "x.out")] + argv[1:],
                           capture_output=True, text=True)
        ok = p.returncode == 1 and p.stderr.strip() != ""
        print(("ok  " if ok else "FAIL"), "feep.pgm", " ".join(argv), "rejected:", p.stderr.strip().splitlines()[0] if p.stderr.strip() else "")
        fails += not ok
    p = subprocess.run([exe, os.path.join(samples, "missing.pgm"), "copy", os.path.join(work, "x.out")],
                       capture_output=True, text=True)
    ok = p.returncode == 1
    print(("ok  " if ok else "FAIL"), "missing input rejected:", p.stderr.strip())
    fails += not ok
    print("failures:", fails)
    sys.exit(1 if fails else 0)

main()
