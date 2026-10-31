# Friction log: netpbm-swarm

These friction reports come from the architect, seven implementers, seven
reviewers and the integrator, all against compiler v0.33.2 at `d0183907`.
Duplicates are merged, and the items are ranked by how much each one cost
(lost evidence first, then lost time, then noise). A roadmap tag means a
row in `docs/compiler-team-roadmap.md` matches. **unfiled** means no row
matches.

## Ranked friction

### F1. Posts in imported modules are never runtime-checked. **unfiled**
*Integrator.* The built executable checks every module's `pre` (39 to 43
`pre-condition failed` sites), but it emits `Postcondition violated` checks
only for the entry module (`main.llmll`, 14 sites). That is true with the
default build and also with `--contracts full --emit-only`.

So these posts are not checked at runtime, although LLMLL.md §5.3.4 and the
`--contracts` table say `full` asserts all contracts:
- `codec.decode` (Success implies `image-ok?`)
- `codec.encode` (`decode(encode img) = img`)
- every `image.img-*` transform (`image-ok?` plus header facts)

The trust report lists them as `asserted`, which reads as runtime-checked.
**Impact:** the shell's contracts work as documentation only. The real
evidence is `check` properties plus the external Python cross-check.
**Workaround:** none in-language; `tools/crosscheck.py`.
**Repro:** `grep -o 'Postcondition violated in [^"]*' build/src/Lib.hs`.

### F2. `llmll test` cannot evaluate an imported sum's constructors reached through an imported callee. **unfiled**
*Integrator.* Nearest rows: XMOD-RUN-LOAD-1 (closed) and PBT-COMPILED-1 (open,
Tier 1 only).

The three codec properties that go through `decode` were all skipped:
- the round trip
- comments and odd whitespace
- malformed input is rejected

Each was skipped with `property body did not reduce on any sample ... calls
Digit via decode -> char-class, which the test evaluator does not model`.

Minimal repro: a module that imports `lex` and checks
`(match (char-class " ") ((Blank) true) ...)` is skipped. The same property
inside `lex.llmll` passes.

**Impact:** decode, the most important shell function, has no `tested`
evidence. **Workaround:** build test images with `make-image` and leave
decode to the Python cross-check.

### F3. A post that compares a value with an imported sum's constructor crashes liquid-fixpoint. **unfiled**
*Architect.* `(= result NoProblem)`, where `Problem` is declared in another
module, fails with `elaborate solver failed ... Cannot unify Problem with
func(0, [Str; int])`, or with `The sort Str is not numeric` for a payload
constructor. Verify then exits 1 for the whole module. Matching on an
imported sum, and constructing one, both work.

Nearest row: CLAUSE-CTOR-PAREN-1 (closed, different cause).

**Impact:** this shaped the module split. Each sum has to live in the module
whose posts compare against it (CharClass, LexState and Tok in lex; Problem in
rules), and consumers may only match.

### F4. A verified imported def can be called in a body but not in a post. **unfiled**
*Integrator, probed.* For example,
`(post (= result (dims-width (hdr-dims (img-header img)))))` falls back with
`contract-post-outside-fragment; Refused by: app:img-header`. The identical
term as the body is body-faithful.

**Impact:**
- Posts must restate projections and index formulas in full.
- `kernel.hflip-sample`'s post writes `3*(w-1-i/3)+(i mod 3)` nine times.
  There is no post-level `let`.
- `img-crop` and `img-grayscale` lost their chance to state header facts via
  the verified accessors.

**Workaround:** spell out `(first (second (first result)))`.

### F5. Nested pair projections fall back in a body. **unfiled** (prior example's F2)
`(first (second s))` in a `def` gives `Refused by: app:first` (main's
`st-args` and `st-msg`). The reviewer of types saw the same cause reported as
`Refused by: pair`.

**Impact:** 8 one-level accessor defs in types, composed across modules. The
shell's fold state `(string, ((int,int), (list[int], list[list[int]])))`
needs 3-deep projections. There are no records and no multi-field
constructors to name the fields.

### F6. Verification cost, and one verify that never finished. VERIFY-MEMORY-1 (parked) is related; otherwise **unfiled**
*Architect, all implementers and reviewers.*
- A single `blur-sample` with nine `sample-at`/`nbr-src` reads did not finish
  in more than 3 minutes (280-700 MB RSS, stalled). Splitting it into
  `kernel.row-sum3` plus a level-3 `blur` module verifies in seconds. That
  cost one extra module.
- A fresh full run takes about 136 s: rules 50 s, kernel 45 s, blur 18 s,
  lex 15 s.
- Adversarial review is expensive. The rules reviewer's 23-mutant batch did
  not finish inside the 600 s tool limit, so no rules mutant verdicts exist.
  Its review rests on reading the posts.
- `verify` has no progress output and no time-limit flag, and macOS has no
  `timeout`.

### F7. Weak contracts verified SAFE, and `--weakness-check` did not see them. **unfiled** as a distinct row (related: the spec-weakening benchmark and CDP rows)
*Reviewers.* Plausible wrong bodies verified against the posts as written:
- `sample-at`: an out-of-range value read as 0, not clamped.
- `row-sum3`: a wrong-channel neighbour.
- `hflip-sample` and `crop-sample`: a defensive fallback read.
- `blur-sample`: `cur` in place of `above`, and vertical-only blur for P3 and
  at the edges.

`--weakness-check` reported "No spec weaknesses detected" on each one, because
it tries only trivial implementations. All four were fixed by strengthening
the posts. Hand-written branch mutants and index-valued (non-constant)
property inputs were what found them. Constant-row properties could not.

### F8. Spurious trust-gap warnings on every call to a callee that has a `pre`. **unfiled** (TRUST-GAP-KEY-1 and TRUST-LEVEL-FLOOR-1 are closed and different)
`Function row-len has an unproven contract (level: asserted). Your module
inherits this trust gap. Silence with: (trust row-len :level asserted)`.

This fires once per call site whenever the callee's `pre` is `asserted`,
which every `pre` is, even though the callee's post is verified. The source
is `TypeCheck.hs` around line 3216, where `emitTrustGap` runs on `csPre`.
Counts: 14 warnings in kernel, 16 in codec, 19 in image, 17 in main. Every
agent grepped them out. The suggested `trust` declaration would understate
the evidence.

### F9. Binary `and`/`or`, and parse errors that point at the wrong place. **unfiled** (message quality is nearest to CORE-SYNTAX-MSG-1)
A 16-row table is 15 nested `and`s. An unbalanced paren deep inside one was
reported in three misleading ways:
- `reserved word post used as identifier` (lex `char-class`, rules
  `header-problem`)
- `unexpected '('` at the **next** top-level form (integrator, codec)
- `unexpected ")"` past the real mistake (blur)

The hint "use def, def-shell, type, import, or check at the top level" never
helped. **Workaround:** every agent generated long posts with Python and ran
a paren counter before `check`.

### F10. Refutation diagnostics name neither the clause nor the arm. **unfiled**
A refuted body says `then-branch does not satisfy postcondition (constraint
#17)`, even when the body is a `match` with no `if`: the first arm is reported
as "then" and every other arm as "else". There is no counterexample, no
failing conjunct and no mapping from `#N` back to the source. With 9- to
15-clause posts, finding the failure meant bisecting the post by hand.

### F11. A fallback means the post is assumed, so a wrong body can be "SAFE". Related to FALLBACK-ATTRIB-1 (closed)
A mod-wrap `nbr-src`, `(mod (+ i dx) w)`, is wrong by its contract. It falls
back on `nonlinear:mod` and gets `SAFE ... partial: 4 of 5`, with exit 0.
Only the `partial` wording, W-BODY-FALLBACK, or a property (which did catch
it) reveal it. `--strict-verified-core` exists and fails on assumed
functions, but no agent knew about it until the integrator read the verify
footer.

### F12. Inconsistent gates for nonlinear terms, and a non-core error that names no term. CORE-SYNTAX-MSG-1, MOD-SPELLING-1 (both open)
- `(/ i c)` or `(* c w)` with variable `c` in a def body is a hard
  `non-core syntax — lambda, do, await, non-linear arithmetic, or unrestricted
  match` error. It does not name the term.
- A variable-divisor `mod` passes `check` and falls back only at `verify`.
- `(* c w)` is accepted in a pre/post but not in a body.

**Workaround:** case-split on `(= c 3)` so every multiplier is the constant 3.

### F13. Two fragment edges inside a body. **unfiled**
- An `if` in argument position, as in `(sample-at m row (if ...))`, makes
  the whole def fall back (`Refused by: if`). A top-level `if` is admitted.
- An `and` guard does not discharge a call-pre in its second conjunct:
  `(and (map-has r i) (>= (map-get r i) 0))` fails with `call-site
  precondition of 'map-get' not satisfied`. Nested `if`s work.

### F14. Whole-image facts cannot be stated. LIST-LEN-AXIOM-1, LIST-TAIL-MATCH-1 (open)
There are no quantifiers and no length facts for list producers. So these
facts can only be `tested`, never proved:
- the round trip
- the involutions
- row counts after a transform
- "every sample in 0..m"

The empty-list literal `[]` in a def body is also refused (`app:list-empty`).
This is the main reason the shell sits at 11 of 50 verified.

### F15. `tested` evidence attaches to the property's `:subject`, not to what the post says. **unfiled** (related to PBT-VACUITY-1)
*Integrator.* `codec.encode`'s post is the round trip. It shows `post: tested
(100 samples)` because a line-length property names `:subject encode`. The
round-trip property itself was skipped (F2).

### F16. Unknown functions only warn, and a guarded property over one passes. PBT-VACUITY-1, PBT-NOREDUCE-PASS-1 (open)
*sample implementer.* `map-set`, a typo for `map-put`, gets a `check` warning
and nothing more. Behind an `(if guard ... true)`, the property reports
Passed and records a false PBT witness.

### F17. Refused-term attribution is imprecise. A follow-up to FALLBACK-ATTRIB-1; **unfiled**
- `problem-message` lists `app:list-empty, app:list-prepend`, which come from
  the desugared `string-concat-many [...]` literal, not from the source.
- A nested projection shows up as `pair`.
- A whole family of shell functions shows only `guard:signature` (a
  `Result`/list-typed signature), which does not say which type is refused.

### F18. Refinement aliases are erased at the shell boundary. Documented in LLMLL.md 3.4.5
Core entry points restate `c in {1,3}` and the row bounds as explicit `pre`s
in 9 functions, because a `Channels` parameter would let the unverified shell
pass 2 silently.

### F19. Minor CLI, tooling and reporting items. All **unfiled**
- `--json` is a global flag and must come before the subcommand
  (`llmll --json verify`). `--weakness-check` must come after `verify`.
- The trust report's Summary `asserted: 0` counts only the post channel,
  while the per-function lines say `pre: asserted`.
- `verify` and `test` rewrite the sidecar in place, and `test` records
  witnesses even on scratch copies. The `.fq` file always goes to
  `/tmp/llmll-*.fq`.
- `Fmt` and `Dims` are both transparent `(int, int)` aliases, so swapped-field
  mutants type-check. Only the posts caught them.
- `regex-find-all` returns `list[list[string]]`, so each character needs
  `(unwrap-or (list-head g) "")`. The architect's tip omitted this.
- `tail` is not a builtin. `(NoProblem true)` silently binds a catch-all
  variable. `check` catches that one with a good fix-it.

### Spec choices (not defects)
- Only space, TAB, CR and LF are whitespace. Netpbm's `isspace` also allows
  VT and FF.
- The bad-magic message shows three characters (`'P23'`) when the magic is
  valid but is not followed by a separator.

### What did not hurt
- Runtime performance. The linear scan idiom (`string-split` lines, then
  `regex-find-all "."`) keeps decode linear. A 256x256 P3 image goes through
  any transform in 0.4-0.9 s at about 106 MB RSS.
- The architect's reference bodies verified on the first try in every
  module.
- Cross-module composition of verified defs (`fmt-channels (hdr-fmt
  (img-header img))`) is body-faithful.
- `build` took 17 s and worked first time.

## How the swarm workflow went

**Module ownership.** One file per agent, with no shared files, worked
without a single edit conflict. The architect wrote every contract and a
typed hole for every body (`?name-body`), and probed all 44 reference bodies
in a scratchpad before handing off. So the implementers' job was close to
mechanical: all seven core modules verified on the first fill. The real work
moved to the **reviewers**. They found weak contracts in 4 of 7 modules
(sample, kernel, blur, plus kernel's implementer strengthening `row-sum3`),
and those were the only contract changes in the project.

**Leaf-first verification.** The order (types/lex/sample, then rules/geom,
then kernel, then blur, then the shell) was required, not just tidy:
- `check` on an importer fails until each import has a sidecar.
- A contract change in kernel forced blur to be re-verified.

Because of this, the reviewers ran mutants in copies that had to include
every transitive import's `.verified.json`, and the levels could only
partly run in parallel. Verify cost (F6) was the critical path. Each kernel
and blur mutant cost 30-45 s, and one reviewer ran out of time.

**Interface handoffs.** The architect's JSON spec, with verbatim contracts, the
representation, the "who may compare which constructor" rule and the shell
loop protocol, was enough to write the shell without reading the core bodies.
Three things were missing:
- the `regex-find-all` shape (caught by the lex implementer)
- the fact that imported posts are not runtime-checked (F1)
- the fact that PBT cannot evaluate decode across modules (F2)

The last two showed up only at integration, which is where swarm handoffs
are weakest. No agent owns end-to-end evidence until the integrator runs.

**Duplicated friction.** F8 (trust-gap noise), F9 (paren depth) and F10
(then/else diagnostics) were each rediscovered by 3 to 6 agents
independently. A shared friction scratch file, written as agents go, would
have saved each of them the rediscovery.
