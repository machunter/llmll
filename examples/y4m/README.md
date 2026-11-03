# y4m: a raw-video probe

A small command-line tool for **YUV4MPEG2 (Y4M) 4:2:0** video, written in
LLMLL against compiler v0.35.1. Its purpose is **evidence**: it finds what
blocks a real video library in LLMLL today. The record is in
[`FRICTION.md`](FRICTION.md). The layout follows
[`examples/netpbm-swarm`](../netpbm-swarm): a leaf-first verified core with
contracts written before the bodies, a thin shell, and a cross-check against
an independent Python reference.

```
main info  IN                    width, height, frame rate, frame count
main frame IN N OUT.pgm          luma plane of frame N (from 0), binary PGM (P5)
main hflip IN OUT.y4m            mirror every plane left to right
main crop  IN X Y W H OUT.y4m    the W x H window at (X, Y); X and Y even
```

* **Input.** `YUV4MPEG2 W<w> H<h> F<n>:<d> ...` then frames. Each frame is
  `FRAME`, optional parameters, LF, then the Y plane (w*h bytes), then the U
  and V planes (ceil(w/2)*ceil(h/2) bytes each). Odd sizes are allowed.
  `I`, `A`, `X` and unknown parameters are ignored. A `C` parameter must start
  with `420`. No `C` means 4:2:0.
* **Errors.** A malformed header or stream exits 1 with a message:
  `not a YUV4MPEG2 stream (bad magic)`, `missing width (W)`,
  `malformed width (W)`, `width must be in 1..16384`,
  `malformed frame rate (F), expected F<n>:<d>`,
  `frame rate terms must be at least 1`,
  `colour space 'C444' is not 4:2:0`, `no header line (no LF)`,
  `frame 2: bad FRAME marker`, `frame 2 is truncated inside its FRAME marker`,
  and `frame 1 is truncated: the payload ends in the V plane at row 1, column 3`.
* **Output.** `hflip` and `crop` copy the header line and change only `W`
  and `H`. They write each frame marker as `FRAME` with no parameters.
* **Real bytes.** LLMLL cannot read or write bytes (FRICTION F1). So the
  program runs `od -An -v -tu1 IN` to get the bytes as decimal text, and
  writes hex text that `xxd -r -p` turns into the output file. Both helpers
  run through `wasi.proc.exec`, so the tool works on real `.y4m` files.

## Build and run

```sh
./build.sh             # verify x5 leaf-first, test, build, time, cross-check
./build.sh --refill    # first fill every core hole again with checkout + patch
./build.sh --mutants   # also verify 10 wrong core bodies (each must fail)
EXE=$(cd build && stack path --local-install-root)/bin/main
$EXE info samples/tiny.y4m
$EXE crop samples/tiny.y4m 2 0 5 4 /tmp/tiny-crop.y4m
```

`build.sh` runs these steps in order:

1. With `--refill`, it fills the holes of `raster`, `hdr` and `xform` through
   the hole protocol (see below).
2. `llmll verify --trust-report` on every module, leaf-first and one at a
   time. An importer cannot be checked until each module it imports has a
   `.verified.json`.
3. `llmll test props.llmll`: 5 cross-module properties.
4. `llmll build main.llmll -o build`.
5. `tools/gen.py` writes the samples and a 320x240, 30-frame clip. It
   times `info`, `frame`, `hflip` and `crop` on the clip.
6. `python3 -I tools/crosscheck.py` compares every command with an
   independent Python implementation on each good sample and on the clip:
   `info` output, `frame` for the first and last frame, `hflip`, a full crop
   and a crop with odd W and H. It checks that each `bad-*.y4m` exits 1 with
   a message that names the fault, and checks 10 argument and IO errors.

**Result of the last run: 0 failures in 43 checks.** That is 3 good samples
plus the clip (22 command checks), 11 malformed files, and 10 argument and IO
errors. The first run of the cross-check also passed.

## Timing

320x240, 30 frames, 3,456,229 bytes, Apple Silicon, default contracts:

| Command | Time | Max RSS |
|---|---|---|
| `info` | 6.3-6.8 s | 1.78-1.92 GB |
| `frame IN 29 OUT` | 5.7-6.0 s | 1.41-1.65 GB |
| `hflip` | 8.5-8.6 s | 1.93-1.94 GB |
| `crop 32 16 255 201` | 7.7-7.9 s | 1.97 GB |

That is 1.8-2.5 µs and about 550 bytes of memory per input byte. Parsing the
`od` text into `list[int]` alone takes 4.96 s and 1.93 GB. The Python
reference does parse, hflip and write in 0.033 s. See FRICTION F2.

**Verify time per module:** raster 4.4 s, hdr 1.0 s, xform 0.2 s, y4m 0.2 s,
main 0.2 s; about 6 s in all. The peak memory of a verify run was under 45 MB. The 21 patches take
0.1-2.0 s each. The build takes about 15 s.

## Module structure

Leaf-first. A core `def` never calls a `def` of its own module, because such
a call is not body-faithful.

| Level | File | Role | Functions |
|---|---|---|---|
| 0 | `raster.llmll` | Payload layout: plane sizes, the raster cursor `(p, y, x)` that advances one byte (`next-x`, `next-y`, `next-p`), `frame-end?`, and the `FRAME` marker automaton. | 8 |
| 0 | `hdr.llmll` | Header decisions on byte values: digits, the decimal fold step, parameter tags, the magic, 4:2:0 test, and the ordered header fault. | 6 |
| 1 | `xform.llmll` | `hflip-src`, `crop-ok?`, `crop-keep?` (the window on Y, and on U and V), a chroma-window lemma, hex digits, digit codes. | 7 |
| shell | `y4m.llmll` | `od` text to bytes, header split and parse, the payload walk into frames, the transforms, hex output. | 39 |
| shell | `main.llmll` | `def-main :mode cli`: args, `od`, read, decode, transform, write, `xxd`, exit status. | 21 |
| tests | `props.llmll` | 5 properties over the core, and 2 helpers. | 2 |
| | `holed/` | The core as first written: every contract, and a `?name-body` hole for each body. | |
| | `fills/` | The body for each hole (`*.sexp`), and `hole-log.jsonl`, the outcome of every patch. | |
| | `*.ast.json` | The patched JSON-AST of each core module (the artifact the hole protocol writes). | |
| | `samples/` | `tiny.y4m` (7x5, odd sizes, extra tokens, a frame parameter), `plain.y4m` (no `C`, two spaces), `zero.y4m` (no frames), and 11 `bad-*.y4m`. | |
| | `tools/` | `crosscheck.py` (the Python reference), `gen.py`, `fill.py` (the hole driver), `mutants.py`, `parens.py`, and `probe.llmll` (the F1 and F2 probes). | |

**Why a raster cursor.** The frame size is `w*h + 2*ceil(w/2)*ceil(h/2)`.
A product of two variables is outside the decidable fragment (FRICTION F5).
So the core never states a size or an offset. The shell walks the payload
byte by byte, and each step of the cursor is a proved function. A frame
ends exactly when `frame-end?` holds, and a truncated frame is found by the
cursor position at the end of the input.

## The hole protocol

The bodies of the 21 core functions were filled with LLMLL's own protocol,
not by editing files:

1. Write `holed/<mod>.llmll`: every contract, and a `?<name>-body` hole for
   each body.
2. `llmll build holed/<mod>.llmll --emit` gives `<mod>.ast.json`.
3. For each hole, `tools/fill.py`:
   * runs `llmll --json holes <mod>.ast.json` for the hole's pointer,
   * gets the JSON-AST of the body from `fills/<mod>.sexp` (it emits a copy
     of the holed source with that one hole filled),
   * runs `llmll --json checkout <mod>.ast.json <pointer>` for a token,
   * runs `llmll --json patch <mod>.ast.json <req> --require-proof` with a
     `test` op (the hole is still there) and a `replace` op (the body).
4. `tools/fill.py <mod> --source` writes the readable `<mod>.llmll` and
   checks that it emits the same JSON-AST as the patched file.

**Hole log** (`fills/hole-log.jsonl`):

| Module | Holes | Outcome |
|---|---|---|
| raster | 8 | `chroma-dim` first as `(/ n 2)`: **PatchVerifyError**, file unchanged. Then 5 fills passed. `next-p`: **PatchNotProved**, because its post had an `if` (FRICTION F4). The contract was fixed in `holed/`, and all 8 holes were filled again: 8 PatchSuccess. |
| hdr | 6 | 6 PatchSuccess. Filled again after an unused type alias was removed from the holed source. |
| xform | 7 | 7 PatchSuccess. `crop-keep?` calls `raster.chroma-dim` and is body-faithful. |

Every final fill is body-faithful. `build.sh --refill` repeats the whole
protocol and appends to the log.

## Verification

All figures are from `./build.sh --refill` on 2026-11-02. "Verified" means
the post was proved by liquid-fixpoint and the body is body-faithful. A `pre`
is always runtime-checked (`asserted`) and is not counted separately.

**Overall: 31 of 81 program functions verified (38%).**
- Core: **21 of 21 verified (100%)**, all body-faithful, with no fallbacks.
- Shell: **10 of 60 verified**: 4 one-level `Hdr` accessors in y4m, and 6
  decisions in main (`cmd-code`, `cmd-argc`, `frame-index-ok?`, `st-phase`,
  `finished?`, `exit-code`).
- The other 50 shell functions have no post. Most of them build lists or
  strings, and no list producer has a length fact (LIST-LEN-AXIOM-1).
- Every verdict is `SAFE`. The 2 helpers in `props.llmll` are not counted.

**Every per-byte decision is a verified call.** In the payload walk, the
cursor step, the frame end and the marker automaton are `raster` defs. In
the transforms, `hflip-src` and `crop-keep?` decide every output sample. In
the encoder, `hex-hi` and `hex-lo` give every output digit. The header
fields go through `num-step`, `param-tag`, `magic-byte`, `chroma-420?` and
`header-problem`. The shell only walks lists and builds text.

**What is not proved, and why.**
- The frame size and every byte offset (FRICTION F5: nonlinear).
- Whole-stream facts: "the walk yields exactly the frames of the file",
  "hflip twice is the identity", "a crop row has W samples". There are no
  quantifiers and no length facts for list producers. The cursor walk, the
  flip involution and the per-row crop count are `tested` in
  `props.llmll`, and the whole commands are covered by the cross-check.
- The `od` text parse and the hex encoding of the output (F1).

**Contract strength.** `tools/mutants.py` verifies 10 plausible wrong core
bodies in scratch copies. All 10 are refuted: a chroma size of `n/2`, a
cursor row that never wraps, a plane that moves on at each row end, a marker
that accepts `FRAMEX`, a decimal step without the place value, a header
check that admits `W0`, a chroma crop window of `cw/2` columns or at `x0`, an
off-by-one flip, and a crop check that forgets that Y must be even.
