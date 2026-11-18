"""Generate the binary (P5 / P6) samples of the netpbm example,
deterministically, and a 256x256 timing image written twice, as P6 and as
P3 with the same pixels.

usage: python3 -I tools/genbin.py SAMPLES_DIR BIG_P6_OUT.ppm [BIG_P3_OUT.ppm]
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
    # A comment that ends at CR, with the next token on the same LF line.
    out["bin-comment-cr.pgm"] = b"P5\n# cr comment\r2 1\n7\n" + raster([7, 3], 7)
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
    # A sample above maxval: maxval 1000, 16-bit sample 1001.
    out["bad-bin-range.pgm"] = image(b"P5", 2, 1, 1000, [1000, 1001])
    return out


def big_pixels():
    xs = []
    for y in range(256):
        for x in range(256):
            xs += [x, y, (x * 7 + y * 13) % 256]
    return xs


def big_p6(path):
    open(path, "wb").write(image(b"P6", 256, 256, 255, big_pixels()))


def big_p3(path):
    xs = big_pixels()
    lines = [" ".join(str(v) for v in xs[i:i + 12]) for i in range(0, len(xs), 12)]
    open(path, "w").write("P3\n256 256\n255\n" + "\n".join(lines) + "\n")


if __name__ == "__main__":
    d, p6 = sys.argv[1], sys.argv[2]
    for name, data in samples().items():
        open(os.path.join(d, name), "wb").write(data)
    os.makedirs(os.path.dirname(p6) or ".", exist_ok=True)
    big_p6(p6)
    if len(sys.argv) > 3:
        big_p3(sys.argv[3])
