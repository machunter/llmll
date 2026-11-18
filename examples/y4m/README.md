# y4m: a raw-video probe

A small command-line tool for **YUV4MPEG2 (Y4M) 4:2:0** video, written in
LLMLL against compiler v0.35.1 and moved to byte I/O on v0.41.0
(EXAMPLES-BYTES-1). Its purpose is **evidence**: it finds what blocks a real
video library in LLMLL today. The record is in
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
* **Real bytes.** The program reads the whole file with
  `wasi.fs.read-bytes` into one `bytes` buffer and writes the output with
  `wasi.fs.write-bytes`. Each frame is an O(1) `bytes-slice` of the buffer,
  and the verified module `ybuf` makes every index and slice decision. Until
  EXAMPLES-BYTES-1 the program ran `od` and `xxd` as helper processes
  (FRICTION F1, resolved).

## Build and run

```sh
./build.sh             # verify x6 leaf-first, test, build, time, cross-check
./build.sh --refill    # first fill every core hole again with checkout + patch
./build.sh --mutants   # also verify 16 wrong core bodies (14 refuted, 2 expected fallbacks)
EXE=$(cd build && stack path --local-install-root)/bin/main
$EXE info samples/tiny.y4m
$EXE crop samples/tiny.y4m 2 0 5 4 /tmp/tiny-crop.y4m
```

`build.sh` runs these steps in order:

1. With `--refill`, it fills the holes of `raster`, `hdr`, `xform` and `ybuf`
   through the hole protocol (see below).
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

320x240, 30 frames, 3,456,229 bytes, Apple Silicon, default contracts,
compiler v0.41.0. "Text" is the earlier build that read through `od` and
wrote through `xxd`; "bytes" is the current build:

| Command | Text: time | Text: max RSS | Bytes: time | Bytes: max RSS |
|---|---|---|---|---|
| `info` | 6.3-6.8 s | 1.78-1.92 GB | 0.01 s (0.46 s cold) | 17.6 MB |
| `frame IN 29 OUT` | 5.7-6.0 s | 1.41-1.65 GB | 0.01 s | 18.7 MB |
| `hflip` | 8.5-8.6 s | 1.93-1.94 GB | 0.25-0.26 s | 36.6 MB |
| `crop 32 16 255 201` | 7.7-7.9 s | 1.97 GB | 0.01 s | 28.5 MB |

`hflip` still builds each output row through `list[int]` and
`bytes-from-list`, so it is the slowest command. The Python reference does
parse, hflip and write in 0.033 s. See FRICTION F2 (resolved).

**Verify time per module:** raster 4.4 s, hdr 1.0 s, xform 0.2 s, ybuf
under 1 s, y4m 0.2 s, main 0.2 s; about 6 s in all. The peak memory of a
verify run was under 45 MB. The patches take 0.1-2.0 s each. The build takes
about 15 s.

## Module structure

Leaf-first. A core `def` never calls a `def` of its own module, because such
a call is not body-faithful.

| Level | File | Role | Functions |
|---|---|---|---|
| 0 | `raster.llmll` | Payload layout: plane sizes, the raster cursor `(p, y, x)` that advances one byte (`next-x`, `next-y`, `next-p`), `frame-end?`, the `FRAME` marker automaton, and `plane-area`, `frame-size` and `plane-offset` (products, since MUL-VAR-1). | 11 |
| 0 | `hdr.llmll` | Header decisions on byte values: digits, the decimal fold step, parameter tags, the magic, 4:2:0 test, and the ordered header fault. | 6 |
| 1 | `xform.llmll` | `hflip-src`, `crop-ok?`, `crop-keep?` (the window on Y, and on U and V), a chroma-window lemma, hex digits, digit codes. | 7 |
| 1 | `ybuf.llmll` | The index and slice decisions over the file's `bytes` buffer: `find-lf` (header end), `marker-end` (a `FRAME` marker), `luma-plane`, `crop-row`, `hflip-at`. | 5 |
| shell | `y4m.llmll` | Header parse, the frame walk over the buffer, the transforms, the output bytes. | 35 |
| shell | `main.llmll` | `def-main :mode cli`: args, read bytes, decode, transform, write bytes, exit status. | 19 |
| tests | `props.llmll` | 5 properties over the core, and 2 helpers. | 2 |
| | `holed/` | The core as first written: every contract, and a `?name-body` hole for each body. | |
| | `fills/` | The body for each hole (`*.sexp`), and `hole-log.jsonl`, the outcome of every patch. | |
| | `*.ast.json` | The patched JSON-AST of each core module (the artifact the hole protocol writes). | |
| | `samples/` | `tiny.y4m` (7x5, odd sizes, extra tokens, a frame parameter), `plain.y4m` (no `C`, two spaces), `zero.y4m` (no frames), and 11 `bad-*.y4m`. | |
| | `tools/` | `crosscheck.py` (the Python reference), `gen.py`, `fill.py` (the hole driver), `mutants.py`, `parens.py`, and `probe.llmll` (the F1 and F2 probes). | |

**Why a raster cursor, and why it is no longer the walk.** The frame size
is `w*h + 2*ceil(w/2)*ceil(h/2)`. A product of two variables was outside the
decidable fragment (FRICTION F5), so the first core stated no size or
offset: the shell walked the payload byte by byte, and each step of the
cursor `(p, y, x)` is a proved function. Since MUL-VAR-1 (v0.39.0),
`frame-size` and `plane-offset` state the size and the offsets as contracts.
Since EXAMPLES-BYTES-1 the shell finds each frame by offset in the buffer:
`ybuf.marker-end` gives the end of the `FRAME` marker, and the payload is the
next `frame-size` bytes. The cursor defs stay verified, and `props.llmll`
still tests one frame's cursor walk.

## The hole protocol

The bodies of the 29 core functions were filled with LLMLL's own protocol,
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
| ybuf | 5 | 5 PatchSuccess (EXAMPLES-BYTES-1). `find-lf` and `marker-end` are `def-shell` with `(decreases …)`, because `letrec` does not parse in the default grammar and a `def` takes no `decreases`. Both are body-faithful, with termination verified. |

Every final fill is body-faithful. `build.sh --refill` repeats the whole
protocol and appends to the log.

## Verification

All figures are from the EXAMPLES-BYTES-1 run on compiler v0.41.0
(2026-11-18). "Verified" means the post was proved by liquid-fixpoint and the
body is body-faithful. A `pre` is always runtime-checked (`asserted`) and is
not counted separately.

**Overall: 39 of 83 program functions verified (47%).**
- Core: **29 of 29 verified (100%)**: raster 11, hdr 6, xform 7, ybuf 5.
  All are body-faithful, with no fallbacks and no `abstraction:app:bytes-*`
  fallback.
- Shell: **10 of 54 verified**: 4 one-level `Hdr` accessors in y4m, and 6
  decisions in main (`cmd-code`, `cmd-argc`, `frame-index-ok?`, `st-phase`,
  `finished?`, `exit-code`).
- The other 44 shell functions have no post. Most of them build lists,
  strings or bytes, and no list producer has a length fact
  (LIST-LEN-AXIOM-1).
- Every verdict is `SAFE`. The 2 helpers in `props.llmll` are not counted.

**Every index and per-byte decision is a verified call.** `ybuf.find-lf`
finds the header end, and `ybuf.marker-end` (over `raster.marker-step`) the
end of each `FRAME` marker. `raster.frame-size` gives each payload's length.
`ybuf.luma-plane` cuts the luma plane for `frame`, `ybuf.crop-row` cuts each
cropped row, and `ybuf.hflip-at` (over `xform.hflip-src`) reads each mirrored
sample. Every `bytes-get` and `bytes-slice` in those defs has its call pre
proved. The header fields go through `num-step`, `param-tag`, `magic-byte`,
`chroma-420?` and `header-problem`. The shell only walks lists and builds
bytes.

**`llmll trust-report y4m.llmll` lists `ybuf.find-lf` and `ybuf.marker-end`
as termination-unverified**, although `ybuf`'s own record verifies their
`decreases` (XMOD-TERM-REPORT-1). The importer's report under-claims.

**What is not proved, and why.**
- Whole-stream facts: "the walk yields exactly the frames of the file",
  "hflip twice is the identity". There are no quantifiers and no length
  facts for list producers. The flip involution and the cursor walk are
  `tested` in `props.llmll`, and the whole commands are covered by the
  cross-check.
- The content of a slice. A slice has an exact length fact but no content
  fact (BYTES-SLICE-CONTENT-1, parked), so "the frame bytes are the file
  bytes" is not stated.
- The rows that `hflip` builds with `bytes-from-list`, and the header text
  read with `bytes-to-list`; both stay in `def-shell`.

**Contract strength.** `tools/mutants.py` verifies 16 plausible wrong core
bodies in scratch copies. The 10 older ones are all refuted: a chroma size
of `n/2`, a cursor row that never wraps, a plane that moves on at each row
end, a marker that accepts `FRAMEX`, a decimal step without the place value,
a header check that admits `W0`, a chroma crop window of `cw/2` columns or at
`x0`, an off-by-one flip, and a crop check that forgets that Y must be even.
Of the 6 `ybuf` mutants, 4 are refuted: `find-lf` reading at the end,
`marker-end` answering the LF offset, `hflip-at` off by one, and `crop-row`
one column too wide (mutant A). Mutant A breaks the outer slice's call pre
through the inner slice's exact length, so it shows ABSTRACTION-LEN-EXACT-1
on real code. The other 2 are **expected fallbacks**, exit 0 with
`abstraction:app:bytes-slice`: `luma-plane` one row short and `crop-row`
shifted right by a column (mutant B). Each breaks only the length post of a
returned slice, which the compiler does not yet refute
(ABSTRACTION-RESULT-LEN-1). When that row ships, `mutants.py` reports them
as UNEXPECTED until its expectation changes.
