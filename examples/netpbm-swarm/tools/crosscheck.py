"""Independent Python reference for the netpbm-swarm example.

Runs the built LLMLL executable on every sample image and every transform,
re-implements each transform here, and compares the decoded outputs. Plain
(P2/P3) and binary (P5/P6) inputs are both read; the output must be in the
input's format (binary in, binary out). It also checks the plain encoder's
line layout (<= 70 characters, <= 10 samples a line) and that every
malformed input, bad argument and missing file exits 1 with a message on
stderr.

usage: python3 -I tools/crosscheck.py BUILT_EXE SAMPLES_DIR WORK_DIR [EXTRA_IMAGE ...]
"""
import os, re, subprocess, sys, time

def decode_text(text):
    magic, body = text[:2], text[2:]
    c = {"P2": 1, "P3": 3}[magic]
    toks = [int(t) for t in re.sub(r"#[^\n]*", "", body).split()]
    w, h, m = toks[:3]
    xs = toks[3:]
    assert len(xs) == w * h * c and all(0 <= x <= m for x in xs), "bad image"
    return c, w, h, m, xs

WS = b" \t\n\v\f\r"

def decode_bin(data):
    """P5/P6 as netpbm reads it: a '#' comment runs to the end of the line
    and reads as that LF or CR; exactly one whitespace byte follows maxval;
    samples are 1 byte, or 2 big-endian when maxval > 255; bytes after the
    raster are ignored."""
    c = {b"P5": 1, b"P6": 3}[data[:2]]
    pos = [2]

    def getc():
        assert pos[0] < len(data), "header ends early"
        ch = data[pos[0]:pos[0] + 1]
        pos[0] += 1
        if ch == b"#":
            while pos[0] < len(data) and data[pos[0]:pos[0] + 1] not in (b"\n", b"\r"):
                pos[0] += 1
            ch = getc()
        return ch

    toks = []
    ch = getc()
    assert ch in WS, "magic not followed by whitespace"
    for _ in range(3):
        while ch in WS:
            ch = getc()
        digits = b""
        while ch.isdigit():
            digits += ch
            ch = getc()
        assert digits, "header token is not a number"
        toks.append(int(digits))
    assert ch in WS, "maxval not followed by whitespace"
    w, h, m = toks
    assert w >= 1 and h >= 1 and 1 <= m <= 65535, "bad header"
    b = 1 if m < 256 else 2
    n = w * h * c
    r = data[pos[0]:pos[0] + n * b]
    assert len(r) == n * b, "raster too short"
    xs = list(r) if b == 1 else [r[2 * i] * 256 + r[2 * i + 1] for i in range(n)]
    assert all(x <= m for x in xs), "sample over maxval"
    return c, w, h, m, xs

def decode(data):
    """(binary?, image) of a file's bytes."""
    if data[:2] in (b"P5", b"P6"):
        return True, decode_bin(data)
    return False, decode_text(data.decode())

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

def ops_for(img):
    c, w, h, m, xs = img
    return [("copy", []), ("invert", []), ("hflip", []), ("vflip", []), ("gray", []),
            ("blur", []), ("threshold", [m // 2]),
            ("crop", [min(1, w - 1), min(1, h - 1), max(1, w - 2), max(1, h - 2)])]

def layout_ok(text):
    lines = text.splitlines()
    return all(len(l) <= 70 and len(l.split()) <= 10 for l in lines)

def run(exe, argv):
    t = time.time()
    p = subprocess.run([exe] + argv, capture_output=True, text=True)
    return p, time.time() - t

def check_image(exe, path, work, timed):
    fails = 0
    name = os.path.basename(path)
    binary, img = decode(open(path, "rb").read())
    for op, args in ops_for(img):
        out = os.path.join(work, "%s.%s%s" % (os.path.splitext(name)[0], op, os.path.splitext(name)[1]))
        p, dt = run(exe, [path, op, out] + [str(a) for a in args])
        if p.returncode != 0:
            print("FAIL", name, op, "exit", p.returncode, p.stderr.strip()); fails += 1; continue
        data = open(out, "rb").read()
        try:
            obin, oimg = decode(data)
        except (AssertionError, KeyError, ValueError, IndexError) as e:
            print("FAIL", name, op, "output does not decode:", e); fails += 1; continue
        ok = obin == binary and oimg == ref(img, op, args) and (binary or layout_ok(data.decode()))
        print(("ok  " if ok else "FAIL"), name, op, ("%.2fs" % dt) if timed else "")
        fails += not ok
    return fails

def main():
    exe, samples, work = sys.argv[1:4]
    extra = sys.argv[4:]
    os.makedirs(work, exist_ok=True)
    fails = 0
    for name in sorted(os.listdir(samples)):
        path = os.path.join(samples, name)
        if name.startswith("bad-"):
            p, _ = run(exe, [path, "copy", os.path.join(work, "x.out")])
            ok = p.returncode == 1 and p.stderr.strip() != ""
            print(("ok  " if ok else "FAIL"), name, "rejected:", p.returncode, p.stderr.strip())
            fails += not ok
        else:
            fails += check_image(exe, path, work, False)
    for path in extra:
        fails += check_image(exe, path, work, True)
    feep = os.path.join(samples, "feep.pgm")
    for argv in (["frobnicate"], ["crop", "20", "0", "5", "5"], ["threshold"],
                 ["threshold", "-3"], ["invert", "7"]):
        p, _ = run(exe, [feep, argv[0], os.path.join(work, "x.out")] + argv[1:])
        ok = p.returncode == 1 and p.stderr.strip() != ""
        print(("ok  " if ok else "FAIL"), "feep.pgm", " ".join(argv), "rejected:",
              p.stderr.strip().splitlines()[0] if p.stderr.strip() else "")
        fails += not ok
    for argv in ([os.path.join(samples, "missing.pgm"), "copy", os.path.join(work, "x.out")], [feep]):
        p, _ = run(exe, argv)
        ok = p.returncode == 1 and p.stderr.strip() != ""
        print(("ok  " if ok else "FAIL"), " ".join(os.path.basename(a) for a in argv), "rejected:",
              p.stderr.strip().splitlines()[0] if p.stderr.strip() else "")
        fails += not ok
    print("failures:", fails)
    sys.exit(1 if fails else 0)

main()
