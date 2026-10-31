# netpbm: an ASCII PGM/PPM codec in LLMLL

An encoder and decoder for the plain Netpbm formats **PGM P2** (grayscale) and
**PPM P3** (colour), with eight transforms and a command-line entry point.
The goal was a practical program written against today's compiler (v0.33.2),
with as much of it proved as the verifier allows. The verified share is the
main measure. Everything that got in the way is logged in
[`FRICTION.md`](FRICTION.md).

```
netpbm IN TRANSFORM OUT [N ...]
  TRANSFORM: copy | invert | hflip | vflip | gray | blur | threshold T | crop X Y W H
```

* **Decoder.** Handles `#` comments anywhere on a line, any whitespace
  (including a header on one line), and maxval up to 65535. Malformed input is
  rejected with a `Result` error that names the problem, and the CLI exits 1:
  `bad magic number 'P6' (expected P2 or P3)`, `missing height`,
  `width must be positive`, `sample 5 (11) exceeds maxval 10`,
  `wrong sample count: 3x2x1 needs 6 samples, found 5`, and
  `sample 3 is not a non-negative integer: '-4'`.
* **Encoder.** Writes the header, then the samples with a newline at the end
  of each row and after every 12th sample in a row, so no line is longer than
  70 characters.
* **Transforms.** `invert`; `hflip` and `vflip`; `crop X Y W H` (a window
  outside the image is an error); `gray` (P3 to P2 with integer luma
  `(77r + 150g + 29b) / 256`, and P2 unchanged); `threshold T`; `blur` (3x3
  box blur with edge replication); `copy`.

## Layout

The layout follows the verifier's rules. A strict-core `def` may call another
`def` only when that callee's body-faithful record was written by an earlier
`llmll verify` run of a different module. So the proved core is split into
modules that are verified leaf-first, and no `def` calls a `def` in its own
module.

| File | Layer | Contents |
|---|---|---|
| `pixel.llmll` | 1 (leaf) | 17 strict-core defs over plain ints: header and crop predicates, per-sample transforms, luma, blur average, coordinate clamp, row spans, encoder column logic, decoder decisions, map-backed sample read |
| `mainlogic.llmll` | 1 (leaf) | 4 defs: transform-name lookup, argument counts, loop termination, exit status |
| `geom.llmll` | 2 | `pixel-offset`, `window-sum3` (calls layer 1) |
| `blur.llmll` | 3 | `blur-sample`: one output sample of the box blur (calls layers 1 and 2) |
| `netpbm.llmll` | shell | Image type, decoder, encoder, transforms, and 19 `check` properties |
| `main.llmll` | shell | The `def-main :mode cli` loop: argv, read, process, write, report |
| `samples/` | | `feep.pgm` (from pgm(5)), `tiny.ppm` (from ppm(5)), `rgb.ppm` (header on one line, comments between rows), and four malformed `bad-*.pgm` files |
| `tools/crosscheck.py` | | An independent Python reference. It runs the binary on every sample and transform and compares the decoded results |
| `build.sh` | | Verifies, tests, builds and cross-checks, in that order |

An image is `(Header, list[int])`, with `Header = (channels, (width, (height, maxval)))`.
The samples are row-major and channel-interleaved. The verified core never
receives a `Header` pair. A nested projection such as `(first (second h))` is
outside the fragment, so the core takes the header fields as separate ints
(see FRICTION.md F2).

## Build and run

```sh
./build.sh                      # verify x6, test, build, cross-check
EXE=$(cd build && stack path --local-install-root)/bin/main
$EXE samples/tiny.ppm gray work/tiny-gray.pgm
$EXE samples/feep.pgm crop work/feep-crop.pgm 1 1 6 5
```

`build.sh` runs `llmll verify` on `pixel`, `mainlogic`, `geom`, `blur`,
`netpbm` and `main`, in that order. It then runs `llmll test netpbm.llmll`
(19 properties) and `llmll build main.llmll -o build`. Last, it runs
`python3 -I tools/crosscheck.py`, which compares every transform on every
sample with the Python reference and checks that each malformed input,
unknown transform, out-of-range crop, missing argument, negative argument and
missing file exits 1 with a message. Current result: **0 failures**. The
cross-check also passes on generated 256x256 P2 and P3 images.

The executable is named `main` and is installed under
`$(cd build && stack path --local-install-root)/bin/`. `llmll build` does not
print that path.

## Verification summary

The figures come from `llmll verify` / `llmll trust-report` on every module,
counting each module's own functions only, which is 76 in total. Each count
uses the function's **post** level. Every function listed as verified is
body-faithful, and every solver run is SAFE.

| Level | Functions | Share |
|---|---:|---:|
| verified (liquid-fixpoint, body-faithful) | 30 | **39%** |
| tested (post covered by a passing `check` property, 100 samples) | 17 | 22% |
| asserted (contract runtime-checked only; the body fell back) | 23 | 30% |
| no contract | 6 | 8% |

Verified plus tested comes to **47 of 76 (62%)**. Every function in the four
core modules is verified (24 of 24). In the shell modules the verified
functions are the 1-level pair projections.

`llmll trust-report`'s own `Summary` block gives lower `tested` figures, for
example 7 for `netpbm`. It counts a function whose pre is `asserted` and whose
post is `tested` as `asserted`, but it counts the same pattern with a
`verified` post as `verified` (FRICTION.md F13). The table above uses the post
column of each row.

### Verified (30)

| Module | Function | What is proved |
|---|---|---|
| pixel | `header-ok?` | the result equals the header well-formedness formula |
| pixel | `times-channels` | `n*c` for `c in {1,3}`, kept linear by a case split |
| pixel | `invert-sample` | `result + s = maxval` (so invert is an involution) and `result` in `0..maxval` |
| pixel | `threshold-sample` | result is `0` or `maxval`, and is `maxval` exactly when `s >= t` |
| pixel | `luma` | `(77r+150g+29b)/256` stays in `0..maxval` (constant products and divisor) |
| pixel | `avg9` | `sum/9` stays in `0..maxval` given `0 <= sum <= 9*maxval` |
| pixel | `clamp-coord` | result in `0..n-1`, and the identity on in-range input |
| pixel | `crop-ok?` | the result equals the crop-window-inside-image formula |
| pixel | `row-span` | the crop span `[lo,hi)` lies inside the row and is exactly `cw` pixels wide |
| pixel | `magic-channels`, `magic-for` | the P2/P3 to channel-count mapping, both directions |
| pixel | `header-problem` | returns `""` exactly when the header is valid, and names the first fault |
| pixel | `sample-problem` | returns 0 exactly when `0 <= v <= m` (the verifier refuted the first draft, F15) |
| pixel | `next-col`, `sep-after` | the encoder's column counter stays in `0..rowlen-1`, and every row ends in `\n` |
| pixel | `sample-at` | a map read clamped into `0..m`, equal to the stored value when that value is in range |
| pixel | `in-span?` | the result equals `lo <= i < hi` |
| mainlogic | `op-code`, `op-arity` | name to code lookup (0 exactly for unknown names) and argument counts |
| mainlogic | `phase-done?`, `phase-status` | termination predicate, exit status in `0..255` (0 on success, 1 on failure) |
| geom | `pixel-offset` | `x*c + k` lands inside the row |
| geom | `window-sum3` | `0 <= sum <= 3m` over three clamped columns, **whatever the map holds** |
| blur | `blur-sample` | every blurred sample is in `0..maxval`, built from `window-sum3`'s and `avg9`'s contracts |
| netpbm | `hdr-channels`, `img-header`, `img-samples` | 1-level projections |
| main | `st-phase`, `finished?`, `exit-code` | state projection, `:done?` and `:status` (exit status in `0..255`) |

### Tested (17): the body falls back; the post passed a `check` property

`decode` (comment and trailing-whitespace tolerance), `encode` (decode of encode is the
identity), `invert` / `hflip` / `vflip` (involutions), `crop` (a full-size crop
is the identity), `grayscale` (yields a valid P2 image), `blur` (a constant image
is unchanged), `threshold` (only `0` and `maxval` appear), `chunk`, `flatten`, `slice-list`,
`strip-comments`, `tokenize`, `parse-nat`, `encode-body`, `row-map`. The
property "hflip and vflip commute" is a joint property with
`:subjects [hflip vflip]`.

### Asserted (23): fell back; runtime contract only

| Function | Fallback cause | Refused term |
|---|---|---|
| `hdr-width`, `hdr-height`, `hdr-maxval`, `st-args`, `st-msg` | body | `app:first` / `app:second` (nested pair projection, F2) |
| `make-header`, `mk` | post | calls the shell accessors above |
| `row-length`, `sample-count` | pre | `app:img-ok-header?` (the pre reads the header through the shell accessors) |
| `slice-rows`, `slice-strings` | body | `app:list-fold`, `app:list-prepend`, `lambda`, ... (no list builtin is in the fragment, F3) |
| `arg`, `nth-int` | body | `app:list-nth` |
| `strip-comment` | post | `app:string-contains` |
| `next-int`, `parse-samples`, `decode-body`, `decode-header`, `int-args`, `apply-op`, `process`, `step` | signature | `guard:signature`: a `Result` or pair carrying a list, an `Image` or a `Command` (F4) |
| `test-image` | post | `app:image-ok?` |

`sample-count` also multiplies two variables (`height * row-length`). It would
fall back on `nonlinear:*` even with a scalar pre (F5).

### No contract (6)

`image-ok?`, `img-ok-header?`, `all-samples-ok?` are the specification
predicates that the other contracts are written in. `report` returns a
`Command`. `usage` and `summary` are string constants and concatenation.

### What this means for the codec

Every number the codec computes is proved in range: inverted, thresholded,
luma and blurred samples, crop spans, encoder columns, and exit status. The
decoder's and the CLI's decisions are proved to match their specifications.
What is **not** proved is anything about the *lists*: sample counts, the
round trip, the involutions, row order. No list or string producer is in the
verifier's fragment, and `width * height` is nonlinear. Those properties are
runtime contracts (`image-ok?` before and after every transform, and
`decode(encode img) = img` as `encode`'s post) and are also checked by
property tests.

## Performance (256x256, Apple Silicon, default build)

Wall-clock time for one run. Each cell gives the default build (runtime
contracts on) first, then the `--contracts none` build. Single runs; the
noise is about ±0.3 s.

| Image | `copy` | `invert` | `blur` |
|---|---:|---:|---:|
| 256x256 P2 (65,536 samples) | 1.1–1.5 s / 0.6–1.3 s | 1.2 s / 0.6 s | 1.3 s / 0.7 s |
| 256x256 P3 (196,608 samples) | 3.6 s / 2.2 s | 3.6 s / 1.9 s | 3.8 s / 2.1 s |

Measured earlier, before `encode` gained its round-trip post: a 512x512 P2
image (262,144 samples) took 2.4 s and 169 MB RSS for `copy`, and 2.7 s and
175 MB for `blur`. The time grows about linearly with the sample count.

A Python decode-validate-encode of the same P3 file takes 0.05 s, about 40
times faster than the `--contracts none` build. The runtime contracts add
roughly 60%. Most of that is `encode`'s `decode(encode img) = img` post,
which decodes every output a second time. See FRICTION.md F11 for where the
time goes.
