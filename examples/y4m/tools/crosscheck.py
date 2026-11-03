#!/usr/bin/env python3
"""Cross-check the y4m CLI against an independent Python reference.

usage: crosscheck.py EXE SAMPLES_DIR WORK_DIR [EXTRA.y4m ...]

For every good file it runs info, frame (first and last frame), hflip, and
two crops (one with an odd W and H), and compares stdout or the output
bytes with the reference. For every bad-*.y4m it checks that `info` exits 1
with a message on stderr that names the problem. It also checks argument
errors. It exits 1 on any failure.
"""
import glob, os, subprocess, sys


class Bad(Exception):
    pass


def parse(data):
    nl = data.find(b"\n")
    if nl < 0:
        raise Bad("no header line")
    line = data[:nl]
    if not (line[:9] == b"YUV4MPEG2" and (len(line) == 9 or line[9:10] == b" ")):
        raise Bad("bad magic")
    w = h = None
    rate = None
    c420 = True
    for t in line[10:].split(b" "):
        if not t:
            continue
        k, v = t[:1], t[1:]
        if k == b"W":
            w = v
        elif k == b"H":
            h = v
        elif k == b"F":
            rate = v
        elif k == b"C":
            c420 = v[:3] == b"420"
    def num(v):
        if v is None:
            return -1
        return int(v) if v and v.isdigit() else -2
    w, h = num(w), num(h)
    if w < 0:
        raise Bad("width")
    if h < 0:
        raise Bad("height")
    if not 1 <= w <= 16384:
        raise Bad("width")
    if not 1 <= h <= 16384:
        raise Bad("height")
    if rate is None:
        raise Bad("frame rate")
    parts = rate.split(b":")
    if len(parts) != 2 or num(parts[0]) < 0 or num(parts[1]) < 0:
        raise Bad("frame rate")
    rn, rd = num(parts[0]), num(parts[1])
    if rn == 0 or rd == 0:
        raise Bad("frame rate")
    if not c420:
        raise Bad("4:2:0")
    cw, ch = (w + 1) // 2, (h + 1) // 2
    size = w * h + 2 * cw * ch
    frames, pos = [], nl + 1
    while pos < len(data):
        end = data.find(b"\n", pos)
        m = data[pos:end if end >= 0 else len(data)]
        if not b"FRAME".startswith(m[:5]) or (len(m) > 5 and m[5:6] != b" ") :
            raise Bad("bad FRAME marker")
        if end < 0 or len(m) < 5:
            raise Bad("truncated")
        if m[:5] != b"FRAME":
            raise Bad("bad FRAME marker")
        p = end + 1
        if p + size > len(data):
            raise Bad("truncated")
        buf = data[p:p + size]
        yp = [buf[r * w:(r + 1) * w] for r in range(h)]
        o = w * h
        up = [buf[o + r * cw:o + (r + 1) * cw] for r in range(ch)]
        o += cw * ch
        vp = [buf[o + r * cw:o + (r + 1) * cw] for r in range(ch)]
        frames.append([yp, up, vp])
        pos = p + size
    return line, (w, h, rn, rd), frames


def header_with(line, w, h):
    toks = [t for t in line[10:].split(b" ") if t]
    out = []
    for t in toks:
        if t[:1] == b"W":
            t = b"W%d" % w
        elif t[:1] == b"H":
            t = b"H%d" % h
        out.append(t)
    return b" ".join([b"YUV4MPEG2"] + out) + b"\n"


def write(line, w, h, frames):
    out = header_with(line, w, h)
    for f in frames:
        out += b"FRAME\n" + b"".join(f[0] + f[1] + f[2])
    return out


def hflip(frames):
    return [[[bytes(reversed(r)) for r in pl] for pl in f] for f in frames]


def crop(frames, x, y, cw, ch):
    out = []
    for f in frames:
        yp = [r[x:x + cw] for r in f[0][y:y + ch]]
        cx, cy, ccw, cch = x // 2, y // 2, (cw + 1) // 2, (ch + 1) // 2
        uv = [[r[cx:cx + ccw] for r in pl[cy:cy + cch]] for pl in f[1:]]
        out.append([yp] + uv)
    return out


def run(exe, *args):
    return subprocess.run([exe, *args], capture_output=True)


def main():
    exe, sdir, work = sys.argv[1:4]
    extra = sys.argv[4:]
    os.makedirs(work, exist_ok=True)
    fails, checks = [], 0

    def check(ok, what):
        nonlocal checks
        checks += 1
        if not ok:
            fails.append(what)
            print("FAIL", what)

    goods = sorted(set(glob.glob(os.path.join(sdir, "*.y4m"))) -
                   set(glob.glob(os.path.join(sdir, "bad-*.y4m")))) + extra
    for path in goods:
        name = os.path.basename(path)
        line, (w, h, rn, rd), frames = parse(open(path, "rb").read())
        r = run(exe, "info", path)
        want = f"width: {w}\nheight: {h}\nframe rate: {rn}/{rd}\nframes: {len(frames)}\n"
        check(r.returncode == 0 and r.stdout.decode() == want, f"info {name}: {r.stdout!r} {r.stderr!r}")
        for n in sorted({0, len(frames) - 1}):
            if n < 0 or n >= len(frames):
                continue
            out = os.path.join(work, f"{name}.f{n}.pgm")
            r = run(exe, "frame", path, str(n), out)
            want = b"P5\n%d %d\n255\n" % (w, h) + b"".join(frames[n][0])
            got = open(out, "rb").read() if r.returncode == 0 and os.path.exists(out) else None
            check(got == want, f"frame {name} {n}: rc={r.returncode} {r.stderr!r}")
        out = os.path.join(work, f"{name}.hflip.y4m")
        r = run(exe, "hflip", path, out)
        got = open(out, "rb").read() if r.returncode == 0 else None
        check(got == write(line, w, h, hflip(frames)), f"hflip {name}: rc={r.returncode} {r.stderr!r}")
        for (x, y, cw, ch) in [(0, 0, w, h), (2 if w > 3 else 0, 2 if h > 3 else 0,
                                                 max(1, w - 3), max(1, h - 3))]:
            if x + cw > w or y + ch > h:
                continue
            out = os.path.join(work, f"{name}.crop{x}-{y}-{cw}-{ch}.y4m")
            r = run(exe, "crop", path, str(x), str(y), str(cw), str(ch), out)
            got = open(out, "rb").read() if r.returncode == 0 else None
            check(got == write(line, cw, ch, crop(frames, x, y, cw, ch)),
                  f"crop {name} {x} {y} {cw} {ch}: rc={r.returncode} {r.stderr!r}")

    for path in sorted(glob.glob(os.path.join(sdir, "bad-*.y4m"))):
        name = os.path.basename(path)
        try:
            parse(open(path, "rb").read())
            check(False, f"reference accepts {name}")
            continue
        except Bad as e:
            key = str(e)
        r = run(exe, "info", path)
        err = r.stderr.decode()
        check(r.returncode == 1 and key.split()[-1].lower() in err.lower(),
              f"bad {name}: rc={r.returncode} want '{key}' in {err!r}")

    tiny = os.path.join(sdir, "tiny.y4m")
    o = os.path.join(work, "x.y4m")
    for args in [[], ["info"], ["play", tiny], ["info", tiny, "extra"],
                 ["frame", tiny, "-1", o], ["frame", tiny, "3", o],
                 ["crop", tiny, "1", "0", "2", "2", o], ["crop", tiny, "0", "0", "8", "2", o],
                 ["crop", tiny, "0", "0", "0", "2", o], ["info", os.path.join(work, "missing.y4m")]]:
        r = run(exe, *args)
        check(r.returncode == 1 and r.stderr.strip() != b"", f"args {args}: rc={r.returncode} {r.stderr!r}")

    print(f"{len(fails)} failures in {checks} checks")
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
