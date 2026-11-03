#!/usr/bin/env python3
"""Make Y4M test inputs.

usage: gen.py clip OUT W H N     a W x H x N-frame 4:2:0 clip
       gen.py samples DIR        the small good and bad samples

Sample values come from a fixed formula plus a seeded PRNG, so they cover
all of 0..255, including 10 (LF) and 70 ('F'), which must not confuse the
marker scan.
"""
import os, random, sys


def frame(w, h, f, rnd):
    cw, ch = (w + 1) // 2, (h + 1) // 2
    y = bytes(((3 * x + 5 * r + 7 * f) ^ rnd.randrange(4)) & 255 for r in range(h) for x in range(w))
    u = bytes((11 * x + 2 * r + f) & 255 for r in range(ch) for x in range(cw))
    v = bytes((13 * r + 3 * x + 2 * f + rnd.randrange(256)) & 255 for r in range(ch) for x in range(cw))
    return y + u + v


def clip(w, h, n, header=None, marker=lambda f: b"FRAME\n", seed=1):
    rnd = random.Random(seed)
    hdr = header or f"YUV4MPEG2 W{w} H{h} F30000:1001 Ip A1:1 C420jpeg".encode()
    out = hdr + b"\n"
    for f in range(n):
        out += marker(f) + frame(w, h, f, rnd)
    return out


def samples(d):
    os.makedirs(d, exist_ok=True)
    good = {
        # odd sizes, extra tokens, a parameter on frame 1
        "tiny.y4m": clip(7, 5, 3, header=b"YUV4MPEG2 W7 H5 F25:1 It A0:0 C420paldv XYSCSS=420PALDV",
                         marker=lambda f: b"FRAME Ixyz\n" if f == 1 else b"FRAME\n"),
        # no C token (4:2:0 by default), even sizes, two spaces
        "plain.y4m": clip(16, 8, 2, header=b"YUV4MPEG2  H8 W16 F24:1"),
        "zero.y4m": b"YUV4MPEG2 W4 H2 F1:1 C420\n",
    }
    t = clip(8, 6, 2)
    bad = {
        "bad-magic.y4m": b"YUV4MPEG W4 H2 F1:1\n" + b"FRAME\n" + bytes(12),
        "bad-nowidth.y4m": b"YUV4MPEG2 H2 F1:1\n",
        "bad-width.y4m": b"YUV4MPEG2 W4x H2 F1:1\n",
        "bad-zero.y4m": b"YUV4MPEG2 W0 H2 F1:1\n",
        "bad-rate.y4m": b"YUV4MPEG2 W4 H2 F30\n",
        "bad-rate0.y4m": b"YUV4MPEG2 W4 H2 F30:0\n",
        "bad-c444.y4m": b"YUV4MPEG2 W4 H2 F1:1 C444\n" + b"FRAME\n" + bytes(24),
        "bad-nolf.y4m": b"YUV4MPEG2 W4 H2 F1:1",
        "bad-trunc.y4m": t[:-5],
        "bad-trunc-marker.y4m": t + b"FRA",
        "bad-marker.y4m": t + b"FRAMEX\n" + bytes(72),
    }
    for name, data in {**good, **bad}.items():
        open(os.path.join(d, name), "wb").write(data)


if __name__ == "__main__":
    if sys.argv[1] == "clip":
        out, w, h, n = sys.argv[2], *map(int, sys.argv[3:6])
        open(out, "wb").write(clip(w, h, n))
    else:
        samples(sys.argv[2])
