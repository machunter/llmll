# Friction log: netpbm codec on LLMLL v0.33.2

This log records each place where the language, compiler, verifier, docs or
diagnostics got in the way while writing `examples/netpbm`. Items are ranked
by how much they cost, in time or in verified share. Each item gives what I
tried, what happened, the workaround, and the roadmap row it matches in
`docs/compiler-team-roadmap.md`, or **unfiled**.

Witness files for the compiler defects are short enough to quote inline. All
were run with the compiler built from `main` at `d0183907`.

---

## Part A: what limits the verified share

These are the items behind the fallbacks listed in README.md. None of them
could be removed without contorting the code.

### F1. A `def` cannot call a `def` in its own module, and a function with no contract cannot be called from any `def`

* **Tried.** I wrote the natural shape: accessors `hdr-width` and so on,
  a `sample-ok?` predicate, and per-sample defs whose contracts call
  `sample-ok?`, all in one file.
* **Got.** About 60 errors, one per call site:
  `def 'luma': callee 'sample-ok?' is defined in this file and has no recorded
  verification; a def may call only trusted builtins and functions verified in
  an earlier run`, suggestion `Move 'sample-ok?' to its own module, verify it,
  then import it`. This applies to calls inside `pre`/`post` as well as the
  body. After the move I got a second refusal:
  `callee 'hdr-channels' is not body-faithful and not in the trusted prelude`.
  A function with **no contract** is never given a record, so even
  `(def hdr-channels [h: Header] -> int (first h))` cannot be called from a
  `def` until it gets a `post` that restates its body.
* **Workaround.** The proved core is now four modules verified leaf-first:
  `pixel`/`mainlogic`, then `geom`, then `blur`. Small predicates such as
  `0 <= s <= m` are written out inline in every contract instead of being
  factored into a helper. `build.sh` encodes the verify order. If the order is
  wrong, `check` fails on the importer.
* **Cost.** About 1 hour, a six-step build, and contracts that are noisier
  than they need to be.
* **Roadmap.** `STRICT-SIBLING` (settled by design 2026-07-12: "bottom-up
  sidecar staging IS the evidence model"). The no-contract-no-record half is
  **unfiled**. The repeated per-call-site error matches `CORE-SYNTAX-MSG-1`.

### F2. Nested pair projections: they fall back in a `def`, the let-bound form crashes liquid-fixpoint, and let-destructuring hangs `verify`

The image header is `(int, (int, (int, int)))`. The language has no records,
and LLMLL.md §13.4 recommends nested pairs.

1. `(def hdr-width [h: Header] -> int (post (= result (first (second h)))) (first (second h)))`
   gives `W-BODY-FALLBACK ... Refused by: app:first`. Only a 1-level
   projection, such as `(first h)`, verifies.
2. The let-bound form is accepted as body-faithful and then **crashes the
   solver**. `verify` exits 1:
   ```lisp
   (type Header (int, (int, (int, int))))
   (def hw [h: Header] -> int (post (>= result 0))
     (let [(r (second h))] (let [(w (first r))] (max w 0))))
   ```
   ```
   ERROR: liquid-fixpoint: ... elaborate solver elabBE 1 "_bv_r_0" {v : int | [(v = (pair2_1 h))]}
   failed on: v == pair2_1 h  with error  The sort (Pair2 int (Pair2 int int)) is not numeric
   ```
   The binder `r` is sorted `int` although `(second h)` is a pair. `check`
   reports OK on this file.
3. Pattern destructuring in a `def` **does not terminate**:
   ```lisp
   (def w4 [h: Header] -> int (post (>= result 0))
     (let [((pair c (pair w rest)) h)] (if (>= w 0) w 0)))
   ```
   `llmll verify` prints nothing. After 10 / 20 / 30 s of wall time it held
   2.2 / 1.7 / 1.5 GB RSS, and I killed it. `check` reports OK.
4. A pair-returning accessor in a separate module (`hdr-rest = (second h)`)
   with `(first (hdr-rest h))` in the caller verifies the body. A post that
   mentions `(first (hdr-rest h))` is then refused
   (`contract-post-outside-fragment`, `app:hdr-rest`), so the accessor cannot
   state what it returns.
* **Workaround.** The core never sees a `Header`. Every `def` takes
  `c w ht m` as separate ints, and the accessors are `def-shell`s with posts
  that are checked at runtime only. Cost: 5 asserted accessors, 2 asserted
  constructors, and the `pre` of `row-length`/`sample-count`.
* **Roadmap.** Nearest is `PAIR-PROJ-LET-1` (closed v0.23.11; that was a
  free pair *parameter*, and here the projection's own sort is wrong). Items
  2 and 3 are **unfiled** compiler defects: a solver crash and a
  non-terminating `verify`. Item 1 is **unfiled**: §5.3.5 lists "nested"
  among the admitted `first`/`second` shapes.

### F3. No list builtin is in the fragment, so nothing about an image's samples can be proved

* **Tried.** A post on the transforms, such as
  `(= (list-length (second result)) (list-length (second img)))`.
  I probed `list-prepend`, `list-map`, `list-reverse`, and a `(decreases
  (list-length xs))` recursion over `list-head`/`list-tail`.
* **Got.** Every one falls back:
  `Refused by: app:list-prepend`, `app:list-map, lambda`,
  `app:list-reverse`, and
  `app:list-empty, app:list-head, app:list-prepend, app:list-tail, app:unwrap-or`.
  The recursion also gets `W-DECREASES-UNDISCHARGED`. Only `list-length` of
  a *parameter* is reflected. No list producer has a length fact, so the
  per-row structure the brief suggested (a list of rows, each of length `w`)
  does not help: the rows are produced by a fold.
* **Workaround.** Every per-element decision is a verified `def` called from
  the shell's lambda (`invert-sample`, `luma`, `next-col`, `sep-after`,
  `sample-problem`, `in-span?`, `blur-sample`, ...). The list plumbing has
  runtime posts, such as `chunk`'s `(= (flatten result) xs)` and the
  `slice-list` length formula. Those posts are lifted to `tested` by `check`
  properties.
* **Roadmap.** `LIST-LEN-AXIOM-1` (sort/reverse/map length axioms, DECIDE),
  `LIST-TAIL-MATCH-1`, `DECREASES-IF-GUARD-1`. A length fact for
  `list-prepend`/`list-fold` producers is **unfiled** beyond those rows.

### F4. `Result` or a pair carrying a list, an `Image` or a `Command` withdraws the whole function (`guard:signature`)

* **Got.** `next-int`, `parse-samples`, `decode-body`, `decode-header`,
  `decode`, `int-args`, `apply-op`, `process` and `step` all report
  `contract-signature-outside-fragment ... Refused by: guard:signature`.
  This happens even where the post only states `(not (= e ""))` on the
  `Error` arm, which is in the fragment.
* **Workaround.** None. The decisions inside these functions (header checks,
  sample checks, op codes) were moved into verified defs that return
  `int`/`string`/`bool`.
* **Roadmap.** **Unfiled.** It is the documented §5.3.5 boundary
  (non-`Σ_auto` payloads), but no row proposes letting a contract that reads
  only the scalar arm survive.

### F5. `width * height` is nonlinear, and it is the one product the codec needs

* `sample-count = height * width * channels` cannot be stated in any
  verified contract. Channels is the easy factor: it is always 1 or 3, so
  `times-channels` writes `(if (= c 3) (* 3 n) n)`, which is linear and
  verified. `height * rowlen` has no such trick. `row-span` and
  `pixel-offset` state `* 3 w` bounds per channel case for the same reason.
* **Roadmap.** Documented (§5.3.3, `nonlinear:*`). The production Lean tier
  is deferred. No other row.

### F6. Contracts written in shell predicates (`image-ok?`) are refused as a whole

* Every transform's post is `(and (image-ok? result) (= (img-header result) (img-header img)))`.
  The `img-header` equality is in the fragment, but `image-ok?` folds over
  the list, so the post is withdrawn whole: `contract-post-outside-fragment ...
  Refused by: app:image-ok?, app:img-header`. Two related problems: the
  label names a verified callee (`img-header`) as refused, and the body's
  own causes (`list-map`, `lambda`) are not reported, because only the first
  cause found is listed.
* **Roadmap.** **Unfiled** (follows `FALLBACK-ATTRIB-1`, which closed
  2026-10-30). Splitting a post's in-fragment conjuncts from the rest would
  have verified the header half of 8 transforms.

---

## Part B: language and library gaps

### F7. No `list-take` / `list-drop` / `zip` / `list-slice`, and `list-nth` is O(n)

* `chunk`, `flatten`, `slice-list`, `slice-rows`, `slice-strings` and
  `row-map` are hand-written left folds over accumulator pairs, about 60
  lines. I did not try per-pixel access with `list-nth`: a 256x256 P3 image
  is 196,608 samples, and nine `list-nth` reads per sample is about 10^10 list
  steps. The blur keys each row as a `map[int,int]` (O(log w) reads) and
  calls `list-nth` only on the row list, which is O(h) per row, so 65,536
  steps for 256 rows. The cost is not visible in the timings.
* **Roadmap.** **Unfiled** (`LIST-SORT-1` added sort/reverse only).

### F8. `and` / `or` are binary, and there is no `cond`

* `(and a b c)` gives `operator 'and' expects 2 args, got 3`. Every contract
  is a right-nested chain `(and a (and b (and c d)))`. `op-code`'s post nests
  ten deep, and `apply-op` is eight nested `if`s. I miscounted the closing
  parens there once. The parse error points at the right column, but the
  hint "use def, def-shell, type, import, or check at the top level" does not
  help.
* **Roadmap.** **Unfiled.**

### F9. `string-to-int` accepts signs, so a strict natural-number parse needs a regex

* `parse-nat` gates on `(regex-match "^[0-9]+$" tok)` so that `-3` and `+3`
  are rejected as samples. That puts a regex call on every one of 196,608
  tokens.
* **Roadmap.** `STR-TO-INT-STRICT-1` (DECIDE).

### F10. `open` is not transitive

* `main` opens `netpbm`, which opens `pixel`. `main` still had to add
  `(import pixel) (open pixel)` to call `in-span?`. The error says so
  directly: `'in-span?' is declared in pixel; add (open pixel) ...`. Minor.
* **Roadmap.** Documented behaviour (§4.9). No row.

---

## Part C: performance

### F11. About 10 µs per sample: around 40 times slower than Python

* 256x256 P3 `copy`: **2.2 s** with `--contracts none` and **3.6 s** by
  default. Python decode, validate and encode of the same file: 0.05 s.
  512x512 P2: 2.4 s and 169 MB RSS. The time scales linearly, and the 9x
  map reads of the blur barely show.
* **Where the time goes** (from reading the generated `build/src/Lib.hs`,
  not from a profile). Text is Haskell `String`, a linked list of `Char`.
  `regex-find-all` tokenizes a `String`. Every sample is an `Integer`. Each
  call result is deep-forced (`llmll_full (llmll_uL ...)`), so for example
  every `list-reverse` inside `chunk` walks its result again. `parse-nat`
  runs a regex per token (F9).
* The runtime contracts add about 60%. Most of that is `encode`'s round-trip
  post. Keeping it was deliberate, because it is the strongest statement of
  the codec's correctness that the language can check.
* **Roadmap.** **Unfiled.** No performance row covers `String`-backed text or
  deep forcing.

---

## Part D: tooling and diagnostics

### F12. `check` warns "unproven contract (level: asserted)" for callees whose post is verified

* After `verify pixel.llmll` reported every function `SAFE`, `check geom.llmll`
  printed 10 warnings like `Function times-channels has an unproven contract
  (level: asserted). Your module inherits this trust gap. Silence with:
  (trust times-channels :level asserted)`. There is one warning per call
  site, and `main` gets 25. The trust report for the same module says
  `post: verified`. The warning appears to read the `pre` level (a `pre` is
  always `asserted`). Following its suggestion would add a trust declaration
  for a proved function.
* **Roadmap.** **Unfiled.** Related: `TRUST-GAP-KEY-1` (closed; it fixed the
  label for stale records) and `CORE-SYNTAX-MSG-1` (one diagnostic per call
  site).

### F13. The trust-report `Summary` counts `tested` and `verified` posts inconsistently

* `netpbm`: 17 rows read `post: tested (100 samples)`, but the summary says
  `tested: 7`. The 10 missing ones have `pre: asserted`, and they are counted
  as `asserted`. The 17 pixel defs with `pre: asserted | post: verified` are
  counted as `verified`. The summary also includes every imported function,
  so `main`'s summary (`verified: 30`) is mostly the core modules. README.md
  counts per row instead.
* **Roadmap.** **Unfiled.**

### F14. Two properties with the same body become one joint witness

* `(check "decode inverts encode" :subject decode ...)` and
  `(check "encode then decode ..." :subject encode ...)` had identical
  bodies. `encode` was reported `tested-joint` and was not counted. Witnesses
  are keyed by a hash of the body (§4.24), so two *separate* `check` blocks
  are merged silently. I gave `decode` a different property.
* **Roadmap.** Documented (§4.24 joint demotion). Surprising when the blocks
  are separate. **Unfiled.**

### F15. The verifier caught a real specification bug (positive)

* The first draft of `sample-problem`'s post claimed `v > m ⇒ result = 2`
  with no `pre` on `m`. For `m < 0` and `v` in `m+1..-1` the body returns 1.
  `verify` reported `body verification of 'sample-problem' failed
  (then-branch does not satisfy postcondition)`. The fix was `(pre (>= m 1))`.

### F16. Small items

* **`llmll build` does not name the executable.** It is
  `build/.stack-work/install/<hash>/9.6.6/bin/main`, found by searching.
  `BUILD-EXE-REPORT-1`.
* **`llmll test` skips properties that pass a named function as a value.** The
  blur property called `(list-map rows row-map)` and was reported "did not
  reduce on any sample". Wrapping it as `(fn [r: list[int]] (row-map r))`
  fixed it. `PBT-FN-VALUE-1`.
* **Fallback labels name desugared terms.** `parse-nat` is "Refused by:
  `app:list-empty, app:list-prepend`". Those come from the list literal
  `[what " is not ..." tok "'"]`, which the source never spells that way.
  **Unfiled**, minor.
* **The capability check matches only the namespace.** `wasi.io.stderr` is
  called with only `(capability stdout ...)` imported, and `check` accepts
  it. `CAP-1-REAL`.
* **`verify` writes outside the project.** It writes `.fq` files to `/tmp`
  (`/tmp/llmll-<name>-<hash>.fq`). There is no flag to keep them beside the
  source. **Unfiled**, minor.
* **A terminating step needs a dummy command.** In the `cli` loop, a step
  that ends the run must still return a `Command`, which is then discarded
  (§9.5). I used `(wasi.io.stdout "")`. This is documented and worked as
  documented.
