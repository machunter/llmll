# netpbm-swarm: a plain PGM/PPM tool written by an agent swarm

A decoder, encoder and eight-transform command-line tool for the plain Netpbm
formats **PGM P2** (grayscale) and **PPM P3** (colour), written in LLMLL
against compiler v0.33.2 (`d0183907`). It is the second take on
[`examples/netpbm`](../netpbm). This time it was built by a swarm of agents:
an architect designed the verified core, one implementer and one adversarial
reviewer worked on each core module, and an integrator wrote the shell, the
samples and these documents. The aim was to **maximize the verified share**,
and the record of what got in the way is in [`FRICTION.md`](FRICTION.md).

```
main IN TRANSFORM OUT [N ...]
  TRANSFORM: copy | invert | hflip | vflip | gray | blur | threshold T | crop X Y W H
```

* **Decoder.** A character-level finite-state scanner whose every transition is
  a verified function. `#` comments may appear anywhere, including straight
  after a digit (`12#c` is 12). Whitespace is space, TAB, CR and LF. The
  header may be on one line, and maxval may be anything from 1 to 65535.
  Malformed input fails with a message that names the problem, and the CLI
  exits 1. The messages are: `bad magic number 'P6'` (and `'P23'`, because
  the magic must be followed by whitespace or `#`), `unexpected character 'x'`,
  `missing height`, `width must be at least 1, got 0`,
  `maxval must be in 1..65535, got 65536`, `sample 0 (11) exceeds maxval 10`,
  and `wrong sample count: 2x2x1 needs 4 samples, found 3`.
* **Encoder.** Writes a newline after every 10th sample and at the end of
  each row, so a line holds at most 10 samples and 59 characters, inside the
  format's limit of 70. The earlier example used 12 per line, which allows
  71 characters at maxval 65535.
* **Transforms.**
  * `invert`
  * `threshold T`
  * `hflip`, which keeps each pixel's r,g,b order
  * `vflip`
  * `crop X Y W H`: a window that does not fit inside the image is an error
  * `gray`: P3 to P2 with luma `(77r + 150g + 29b) / 256`; a P2 image is unchanged
  * `blur`: 3x3 box blur, per channel, with edge replication and the floor of the mean
  * `copy`

## Build and run

```sh
./build.sh      # verify x10 leaf-first, test x9, build, cross-check (about 2.5 min)
EXE=$(cd build && stack path --local-install-root)/bin/main
$EXE samples/tiny.ppm gray /tmp/tiny-gray.pgm
$EXE samples/feep.pgm crop /tmp/feep-crop.pgm 1 1 6 5
```

`build.sh` runs these steps in order:

1. `llmll verify --trust-report` on every module, leaf-first. An importer
   cannot be checked until each module it imports has a `.verified.json`.
2. `llmll test` on every module that has `check` properties.
3. `llmll build main.llmll -o build`.
4. It generates a 256x256 P3 image with `tools/gen256.py`.
5. `python3 -I tools/crosscheck.py` compares every transform, on every sample
   and on the 256x256 image, against an independent Python implementation.
   It also checks the encoder's line layout (at most 70 characters and at
   most 10 samples per line), and checks that each malformed file, unknown
   transform, wrong argument count, negative argument, out-of-range crop,
   missing file and missing argument exits 1 with a message on stderr.

**Result of the last run: 0 failures in 47 checks** (8 transforms x 4 images,
8 malformed files, 7 argument and IO errors).

**Timing** (256x256 P3, 196,608 samples, 702 KB, Apple Silicon): each
transform runs end to end (read, decode, transform, encode, write) in
0.4-0.9 s, with about 106 MB maximum RSS. Blur is the slowest, at 0.8-0.9 s.
`llmll verify` takes about 136 s across all ten modules. Most of that is
rules (50 s), kernel (45 s), blur (18 s) and lex (15 s); the shell modules
take under 3 s each. The build takes about 17 s.

## Module structure

Leaf-first. A `def` in this program never calls a `def` in its own module:
such a call is not body-faithful, so each layer calls only layers below it,
whose verified records already exist.

| Level | File | Role | Functions |
|---|---|---|---|
| 0 | `types.llmll` | Representation: `Image = (Header, list[Row])`, `Header = ((channels, maxval), (width, height))`. Rows are channel-interleaved. Only one-level accessors. | 13 |
| 0 | `lex.llmll` | Scanner automaton: `CharClass`, `LexState`, `Tok`. | 5 |
| 0 | `sample.llmll` | Per-sample arithmetic: invert, threshold, luma, the 9-mean, a coordinate clamp, and a clamped map read. | 6 |
| 1 | `rules.llmll` | Format decisions: magic, ordered header faults (`Problem`), sample range, the `(r, k)` row counter (so w*h*c is never compared), line layout, shape predicates. | 10 |
| 1 | `geom.llmll` | Index maps on interleaved rows: hflip source, crop window, crop source, same-channel neighbour. | 5 |
| 2 | `kernel.llmll` | One output sample per transform: geom index, then sample read, then arithmetic. | 4 |
| 3 | `blur.llmll` | One blur output sample: 3 x `row-sum3`, then `avg9`. | 1 |
| shell | `codec.llmll` | Verified header accessors and `make-image`; `image-ok?`; the scanner loop; `decode`; `encode`; Problem messages. | 22 |
| shell | `image.llmll` | Whole-image transforms. They only walk rows and indices; every sample comes from a core def. | 11 |
| shell | `main.llmll` | `def-main :mode cli`: args, read, decode, transform, encode, write, exit status. Transform lookup, arity and exit code are verified defs. | 17 |
| | `samples/` | `feep.pgm` (pgm(5)), `tiny.ppm` (ppm(5)), `rgb.ppm` (CRLF, TABs, a comment straight after the magic and after digits, a header split across lines), and eight `bad-*` files. | |
| | `tools/` | `crosscheck.py` (the Python reference), `gen256.py` (the timing image). | |

The verify order is types, lex, sample, then rules, geom, then kernel, then
blur, then codec, image, main.

## Verification

All figures below are from a fresh `./build.sh` run on 2026-10-31, using
`llmll verify --trust-report` and then `llmll trust-report` on each module.
"Verified" means the post was proved by liquid-fixpoint and the body is
body-faithful. A `pre` is always runtime-checked (`asserted`) and is not
counted separately.

**Overall: 55 of 94 functions verified (58.5%).**
- Core: **44 of 44 verified (100%)**, all body-faithful, with no fallbacks.
- Shell: **11 of 50 verified**: 6 in codec and 5 in main.
- Counting only functions that carry a contract, 55 of 82 are verified (67%).
- Every verdict is `SAFE`.

The one assumption the core inherits is the disclosed, codegen-determined
`map-get` axiom (through `sample-at`).

| Category | Count |
|---|---|
| verified (post proved, body-faithful) | 55 |
| tested only (post has `tested` PBT evidence, no proof) | 9 |
| fallback, post asserted (assumed by the verifier) | 18 |
| no contract | 12 |
| **total** | **94** |

### Per function

**Core (level 0-3): all verified.**

| Module | Function | Status |
|---|---|---|
| types | mk-fmt, mk-dims, mk-header, mk-image, fmt-channels, fmt-maxval, dims-width, dims-height, hdr-fmt, hdr-dims, img-header, img-rows, row-len | verified (13) |
| lex | char-class, lex-step, lex-emit, lex-flush, sep-ok? | verified (5) |
| sample | invert-sample, threshold-sample, luma, avg9, clamp-coord, sample-at | verified (6) |
| rules | magic-channels, header-problem, header-ok?, sample-problem, next-k, next-r, count-problem, sep-after, row-length-ok?, rows-count-ok? | verified (10) |
| geom | hflip-src, crop-ok?, crop-row?, crop-src, nbr-src | verified (5) |
| kernel | hflip-sample, crop-sample, gray-sample, row-sum3 | verified (4) |
| blur | blur-sample | verified (1) |

**Shell.**

| Module | Function | Status | Refused term / note |
|---|---|---|---|
| codec | img-channels, img-maxval, img-width, img-height | verified | Compositions of the one-level types accessors. |
| codec | make-image | verified | `pre` is asserted. |
| codec | magic-for | verified | |
| codec | encode | tested only | Fallback: `guard:signature`. The `tested` evidence comes from the line-length property; the round-trip property is skipped (see FRICTION F2). |
| codec | decode, decode-tokens, decode-samples, scan | fallback, asserted | `guard:signature` (Result over list/Image) |
| codec | problem-message | fallback, asserted | `app:int-to-string, app:string-concat(-many)` (also lists `app:list-empty, app:list-prepend`, from the list literal's desugaring) |
| codec | nth-or-0 | fallback, asserted | `app:list-nth, app:unwrap-or` |
| codec | drop3 | fallback, asserted | `app:list-tail, app:unwrap-or, app:list-empty` |
| codec | test-image | fallback, asserted | `app:image-ok?` in the post (test generator) |
| codec | image-ok?, samples-in-range?, row-lengths-ok?, scan-char, place-sample, encode-row, count-message | no contract | Specification predicates and loop bodies. |
| image | img-invert, img-threshold, img-vflip, img-hflip, img-blur | tested only | Post refused: `app:image-ok?, app:same-shape?` |
| image | img-crop, img-grayscale | tested only | Post refused: `app:image-ok?`, `app:img-width` and the other verified accessors (F4) |
| image | row-map | fallback, asserted | `app:list-fold, app:map-empty, app:map-put, lambda, pair` |
| image | gen-image | fallback, asserted | `app:image-ok?` (test generator) |
| image | row-at, same-shape? | no contract | |
| main | op-code, op-arity, st-phase, finished?, exit-code | verified | |
| main | int-args | tested only | `guard:signature` |
| main | st-args, st-msg | fallback, asserted | `app:first` / `app:second`: a nested projection (F5) |
| main | mk | fallback, asserted | Post calls `st-args`, `st-msg`, `st-phase` |
| main | arg | fallback, asserted | `app:list-nth, app:unwrap-or` |
| main | parse-nat | fallback, asserted | `app:regex-match, app:string-to-int, app:string-concat-many` |
| main | apply-op, step | fallback, asserted | `guard:signature` |
| main | process | fallback, asserted | `app:string-concat-many, app:ok` |
| main | nth-int, report, usage | no contract | |

**Properties.** There are 35 `check` properties: lex 2, sample 4, rules 3,
geom 3, kernel 5, blur 3, codec 4, image 10, main 1.

- 32 pass and none fail.
- 3 codec properties are **skipped**. They go through `decode`, and the
  `llmll test` evaluator cannot reduce `lex`'s constructors when they are
  reached through an imported callee (FRICTION F2).
- The round trip, the involutions and the identities are therefore `tested`
  for the transforms only. Decode and encode are covered end to end by the
  Python cross-check instead.

**What is not proved, and why.**

Every whole-image fact is outside the fragment, because there are no
quantifiers and no list producer has a length fact (LIST-LEN-AXIOM-1). That
covers the round trip, row counts after a transform, the involutions, and
"every sample in range". So the shell's list plumbing is at best `tested`.

The posts of `decode`, `encode` and the transforms are **not even
runtime-checked** in the built executable. Only the entry module's posts are
emitted, although every module's `pre` is (FRICTION F1). Their real evidence
is the property tests plus the Python cross-check.

Every per-sample and per-header decision is proved. That covers which
source sample a transform reads, the luma and blur arithmetic, the clamping,
the header fault order, the sample counter and the line layout.

## Contracts strengthened by the reviewers

The adversarial review found plausible wrong bodies that verified against the
architect's posts, and strengthened four of them:

* `sample-at`: absent key gives 0, and a stored value is clamped (not zeroed).
* `row-sum3`: the exact sum at the left edge, interior, right edge and for a
  1-pixel row, for P2 and P3.
* `hflip-sample` and `crop-sample`: pinned off the decoded-image domain too.
* `blur-sample`: the exact 9-cell mean at every position, for P2 and P3. The
  original post pinned only a constant 1x1 image, so blurring only vertically
  verified SAFE.

Two documented residuals remain. Both are off the decoded-image domain:
`gray-sample` and `row-sum3` do not pin the result when a key is absent.
