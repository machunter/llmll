# Friction log: y4m

This is the record of what blocks a real video library in LLMLL today. It
comes from one agent that built the y4m probe against compiler v0.35.1 (the
build in the main checkout, with the worktree at `dd017869`). The items are ranked by cost: lost
capability first, then lost performance, then lost time, then noise. A
roadmap tag means a row in `docs/compiler-team-roadmap.md` matches. **new**
means no row matches.

## Summary

| # | Item | Row |
|---|---|---|
| F1 | No byte input or output; the program spawns `od` and `xxd` | BYTES-READ-1, BYTES-WRITE-1, BYTES-UNSIZED-1, FFI-BYTES-1 |
| F2 | 1.8-2.5 µs and about 550 bytes of memory per input byte | PERF-TEXT-1 |
| F3 | Hand-written take, drop, split and enumerate; no seek | LIST-SLICE-1 (second consumer) |
| F4 | One `if` conjunct withdrew a whole post, and `check` did not say so | POST-CONJ-SPLIT-1 |
| F5 | The frame size `w*h` is nonlinear, so no contract can state it | new (message: CORE-SYNTAX-MSG-1) |
| F6 | A contract fix restarts the hole protocol; fills must be JSON-AST | new |
| F7 | Nested pair projections fall back | PAIR-NEST-PROJ-1 |
| F8 | No character codes | CHAR-CODE-1 |
| F9 | Child output only goes to a file; fixed temp paths; capability not checked | new (capability part: CAP-1-REAL) |
| F10 | Trust-gap warning noise, and parse errors at the wrong place | TRUST-GAP-PRE-1, AND-NARY-1 |

Not hit: BITWISE-1 and PBT-XMOD-CTOR-1. See "What did not hurt".

## Ranked friction

### F1. No byte input or output. BYTES-READ-1, BYTES-WRITE-1, BYTES-UNSIZED-1, FFI-BYTES-1

A Y4M payload is raw bytes. LLMLL has no way to read or write them:
- `wasi.fs.read` delivers UTF-8 text. A Y4M file is almost never valid UTF-8,
  so the read fails.
- `wasi.fs.write` encodes its argument as UTF-8, so a sample of 128 or more
  becomes two bytes.
- `bytes[n]` is length-indexed. A file's length is not known at compile time,
  so `bytes[n]` cannot type a file read even if a read existed.
- The Tier 1 FFI reaches no part of `Data.ByteString` or `Data.Vector`
  (LLMLL.md §7, reach table: "none").

**Minimal repro** (`tools/probe.llmll`, a 30-line `cli` program that
calls `(wasi.fs.read path)`):
```
$ probe read samples/tiny.y4m
RErr: samples/tiny.y4m: hGetContents: invalid argument (cannot decode byte sequence starting from 235)
$ probe read samples/zero.y4m        # header only, all ASCII
26 chars
```

**Workaround.** The program runs two helper processes through
`wasi.proc.exec`:
- `od -An -v -tu1 IN` writes one decimal number per byte to a temp file. The
  program reads that text and parses it into `list[int]`.
- The program writes the output as hex text. `xxd -r -p HEX OUT` turns it
  into bytes.

So the probe works on **real Y4M files**, not on a transcoding. The core is
written over byte values (`int` 0..255), so it applies unchanged to a future
byte type. The cost is F2: the text round trip is most of the run time and
memory.

### F2. 1.8-2.5 µs and about 550 bytes of memory per input byte. PERF-TEXT-1

Measured on a 320x240, 30-frame clip (3,456,229 bytes) on Apple Silicon:

| Command | Time | Max RSS |
|---|---|---|
| `info` | 6.3-6.8 s | 1.78-1.92 GB |
| `frame IN 29 OUT` | 5.7-6.0 s | 1.41-1.65 GB |
| `hflip` | 8.5-8.6 s | 1.93-1.94 GB |
| `crop 32 16 255 201` | 7.7-7.9 s | 1.97 GB |
| Python reference (parse, hflip, write) | 0.033 s | |
| `od` alone | 0.34 s | 1.3 MB |

- `info` costs about 1.9 µs per input byte. `hflip` costs about 2.5 µs.
  That is about 250 times the Python reference.
- **The text round trip dominates.** A probe that only runs `od-bytes`
  (`string-split` plus `string-to-int` on the 16 MB `od` text) takes 4.96 s
  and 1.93 GB on its own. That is about 80% of `info`.
- The whole file is in memory as `String` and then as `list[Integer]`.
  There is no streaming read, so memory grows with the file. At about 550
  bytes per input byte, a 30-frame 1080p clip (93 MB) would need about
  50 GB.
- `frame N` cannot seek (F3), so it costs the same as `info`.

**Workaround:** none. The clip was not shrunk; all four commands finish on
the full 30-frame clip.

### F3. Hand-written take, drop, split and enumerate; no seek. LIST-SLICE-1 (second consumer)

**Did the program need list-take, list-drop, list-slice, zip, or O(1)
indexing? Yes, the first four, written by hand as folds.** It did not need
O(1) indexing for correctness, but it replaced it with `map[int,int]` rows
and it gave up seeking. Each hand-written helper is in `y4m.llmll`:

| Needed | Written as | Used by |
|---|---|---|
| `list-take` until a byte (take-while) | `split-header`: a fold that keeps the bytes before the first LF | the header line |
| early exit from a fold | none: `split-header` walks all 3.4 M bytes to find the LF at byte 48 | the header line |
| `list-drop` | `drop-bytes`: a fold with a counter | header tokens (`drop-bytes 10`, `drop-bytes 1`) |
| split at a separator | `split-on`: a fold over `list[int]` | header tokens (space), frame rate (`:`) |
| zip with an index (enumerate) | `map-planes`, `row-map`, `crop-plane`, `magic-ok?`: each a fold over `(index, acc)` | crop (plane index), hflip, magic check |
| O(1) indexing | `row-map`: each row becomes a `map[int,int]`, then `map-get` (O(log w)) | hflip |
| slice by offset (seek) | none | `frame N` decodes every frame |

These helpers are about 45 lines. The payload walk itself needed no slice.
A raster cursor (F5) streams the bytes into rows, so the layout is never an
offset computation. But with a slice and a length fact, `frame N` could
stop after frame N, and the header split would be one call.

**Minimal repro:** no builtin takes the bytes before the first LF.
`list-take`, `list-take-while` and `list-drop` are not in LLMLL.md §13.

### F4. One `if` conjunct withdrew a whole post, and `check` did not say so. POST-CONJ-SPLIT-1

The first contract of `raster.next-p` had four conjuncts. One of them was
`(= result (if (= p 2) 0 (+ p 1)))`. `check` accepted the file. The first
sign of trouble was the patch of the body:
```
raster ?next-p-body /statements/5/body: PatchNotProved
'next-p' passed the solver but was not proved: contract-post-outside-fragment
(outside the decidable fragment: if), so its postcondition was assumed.
```
The `if` is admitted in a body but not in a post. And the three conjuncts
that were in the fragment were withdrawn with it. `marker-step`'s post had
the same shape (seven `if` conjuncts) and would have failed the same way.

**Workaround:** each `(= result (if c a b))` became
`(and (=> c (= result a)) (=> (not c) (= result b)))`. Then the contract
change restarted the hole protocol for the module (F6).

### F5. The frame size w*h is nonlinear, so no contract can state it. new (message: CORE-SYNTAX-MSG-1)

The natural core function is the frame size, `w*h + 2*ceil(w/2)*ceil(h/2)`.
Then a frame's offset, a truncation check and a crop's byte count follow
from it. But a product of two variables is outside the fragment:
```lisp
(def frame-bytes [w: int h: int] -> int
  (pre (and (>= w 1) (>= h 1)))
  (post (= result (+ (* w h) (* 2 (* (/ (+ w 1) 2) (/ (+ h 1) 2))))))
  (+ (* w h) (* 2 (* (/ (+ w 1) 2) (/ (+ h 1) 2)))))
```
- As a `def`, `check` fails: `body contains non-core syntax — lambda, do,
  await, non-linear arithmetic, or unrestricted match`. It does not name the
  term.
- As a `def-shell`, `verify` falls back: `Refused by: nonlinear:*`, so the
  post is assumed.

**Workaround (a design change).** The core never states a size. A raster
cursor `(p, y, x)` advances one byte at a time (`next-x`, `next-y`,
`next-p`), and `frame-end?` marks the last byte of a frame. Every transition
is linear and proved. Truncation is "the input ended while the cursor was
not at a frame start", and the error names the plane, row and column. The
cost is that no contract can say "frame N starts at byte k" (F3: no seek),
and the shell cannot check a byte count against a proved size.

### F6. A contract fix restarts the hole protocol, and fills must be JSON-AST. new

- `llmll checkout` and `llmll patch` work on `.ast.json` only, and a patch
  value is a JSON-AST node. An agent writes S-expressions. So
  `tools/fill.py` (160 lines) emits a copy of the holed source with one hole
  filled, takes the node at the hole's pointer, and sends that as the
  `replace` value.
- A patch can only fill a hole. When `next-p`'s contract had to change (F4),
  the only path was to edit `holed/raster.llmll`, emit a new `.ast.json`,
  and fill all 8 holes again. The hole log shows the 6 earlier fills twice.
- Nothing prints a patched `.ast.json` back to `.llmll`. `fill.py --source`
  writes the readable source from the same bodies and checks that it emits
  the patched JSON-AST.

**Impact:** small here, because each patch re-verifies in 0.1-2 s. A
contract change in a big module, or after review, would cost a full refill.

### F7. Nested pair projections fall back. PAIR-NEST-PROJ-1

`(def hdr-w [h: Hdr] -> int (post (= result (first (first h)))) (first
(first h)))` fell back (`W-BODY-FALLBACK`), as in netpbm-swarm F5.
**Workaround:** four one-level defs (`hdr-size`, `hdr-rate`, `pair-a`,
`pair-b`) that verify, and shell compositions of them. The payload walk
keeps an 11-field state in pairs nested 4 deep, so it stays shell code.

### F8. No character codes. CHAR-CODE-1

Two places need to move between a byte value and text:
- The message `colour space 'C444' is not 4:2:0` needs the token's bytes as
  text. `ascii-text` indexes a 95-character table with `string-char-at`.
- A written header needs `W255` as bytes. `digit-bytes` runs
  `int-to-string`, splits the text with `regex-find-all "[0-9]"`, parses each
  digit back with `string-to-int`, and maps it through the verified
  `digit-code`.

### F9. Child output only goes to a file; fixed temp paths; capability not checked. new (capability part: CAP-1-REAL)

- `wasi.proc.exec` can send a child's stdout only to a path. So the program
  writes two fixed files in /tmp, llmll-y4m-od.txt and llmll-y4m-hex.txt. There is no
  temp-file builtin, so two runs at the same time would overwrite each
  other's files.
- `main.llmll` declares `(capability exec "/usr/bin/od")` and also runs
  `/usr/bin/xxd`. Nothing objects, because the capability clause is
  declarative (LLMLL.md §7).

### F10. Noise: trust-gap warnings and parse errors at the wrong place. TRUST-GAP-PRE-1, AND-NARY-1

- `check` prints 13 "unproven contract (level: asserted)" warnings for
  `y4m.llmll` and 10 for `main.llmll`. Each callee's post is verified; only
  its `pre` is asserted (netpbm-swarm F8).
- One missing `)` at the end of `header-problem`'s post (13 nested binary
  `and`s) gave `reserved word post used as identifier` at the `post` line.
  Two extra parens in `y4m.llmll` gave errors at later forms.
  **Workaround:** `tools/parens.py` flags the open form before `check` runs.
- `fn` is reserved, so a parameter for the frame-rate numerator cannot be
  called `fn`. The message says so clearly.

## What did not hurt

- **Bitwise operations (BITWISE-1)** were not needed. 8-bit 4:2:0 has no
  packed fields. The hex digits are `(/ b 16)` and `(mod b 16)`, which are
  linear and proved. A 10-bit or packed format (v210, P010) would need them.
- **Imported constructors in tests (PBT-XMOD-CTOR-1)** were not hit. The
  program declares no sum type, and all 5 cross-module properties in
  `props.llmll` reduce and pass. A planted wrong expectation in two of them
  fails with a counterexample.
- **The hole protocol itself.** 21 holes filled through `checkout` +
  `patch --require-proof`, each re-verified in 0.1-2 s. A wrong fill
  (`chroma-dim` as `(/ n 2)`) was refused with `PatchVerifyError` and the
  file was not changed. `--require-proof` caught the fragment problem (F4)
  at the first fill, which `check` did not.
- **Verify cost.** All five modules verify in about 6 s together. No solver
  run came near the watchdog limits (peak 42 MB).
- **Contract strength.** All 10 hand-written wrong bodies in
  `tools/mutants.py` are refuted (off-by-one flip, `cw/2` chroma window, a
  marker that accepts `FRAMEX`, a cursor that never wraps, and others).
- **Correctness.** The program matched the Python reference on the first run
  of the cross-check: 0 failures in 43 checks.
