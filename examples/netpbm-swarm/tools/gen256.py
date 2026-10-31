"""Generate a 256x256 P3 test image (deterministic) for timing.

usage: python3 -I tools/gen256.py OUT.ppm
"""
import sys
w = h = 256
out = ["P3", "# generated 256x256 gradient with noise", "%d %d" % (w, h), "255"]
for y in range(h):
    row = []
    for x in range(w):
        row += [x, y, (x * 7 + y * 13) % 256]
    for i in range(0, len(row), 12):
        out.append(" ".join(str(v) for v in row[i:i + 12]))
open(sys.argv[1], "w").write("\n".join(out) + "\n")
