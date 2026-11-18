"""Generate the binary (P5 / P6) samples, deterministically, and a 256x256
P6 image for timing with the same pixels as tools/gen256.py.

usage: python3 -I tools/genbin.py SAMPLES_DIR BIG_OUT.ppm
"""
import os, sys


def raster(xs, m):
    if m < 256:
        return bytes(xs)
    return b"".join(bytes([x >> 8, x & 255]) for x in xs)


def image(magic, w, h, m, xs, sep=b"\n", tail=b""):
    return b"%s\n%d %d\n%d" % (magic, w, h, m) + sep + raster(xs, m) + tail


def samples():
    out = {}
    # P5 4x3, maxval 255; the raster holds 10, 13, 32 and 35 ('#') bytes.
    out["bin-gray.pgm"] = image(b"P5", 4, 3, 255, [0, 10, 13, 32, 35, 255, 1, 2, 128, 64, 9, 200])
    # P6 3x2, maxval 255.
    out["bin-rgb.ppm"] = image(b"P6", 3, 2, 255, [(i * 37) % 256 for i in range(18)])
    # P5 with '#' comments after the magic, between tokens and after maxval.
    out["bin-comment.pgm"] = (b"P5# made by genbin\n3 # width\n2\n# maxval next\n100#end\n"
                              + raster([0, 50, 100, 99, 10, 1], 100))
    # 16-bit samples: P5 maxval 1000, P6 maxval 65535.
    out["bin-gray16.pgm"] = image(b"P5", 3, 2, 1000, [0, 255, 256, 999, 1000, 513])
    out["bin-rgb16.ppm"] = image(b"P6", 2, 2, 65535, [0, 65535, 256, 1, 4660, 22136,
                                                      65280, 255, 10, 13, 2570, 3341])
    # CR as the single byte after maxval, and bytes after the raster (ignored).
    out["bin-cr.ppm"] = image(b"P6", 2, 1, 255, [13, 10, 32, 1, 2, 3], sep=b"\r", tail=b"trailing\n")
    # Truncated raster: 2x2 P5 needs 4 bytes, has 3.
    out["bad-bin-short.pgm"] = image(b"P5", 2, 2, 255, [1, 2, 3])
    # Bad header: the height is not a number.
    out["bad-bin-header.ppm"] = b"P6\n2 x\n255\n" + bytes(6)
    return out


def big(path):
    w = h = 256
    xs = []
    for y in range(h):
        for x in range(w):
            xs += [x, y, (x * 7 + y * 13) % 256]
    open(path, "wb").write(image(b"P6", w, h, 255, xs))


if __name__ == "__main__":
    d, bigout = sys.argv[1], sys.argv[2]
    for name, data in samples().items():
        open(os.path.join(d, name), "wb").write(data)
    os.makedirs(os.path.dirname(bigout) or ".", exist_ok=True)
    big(bigout)
