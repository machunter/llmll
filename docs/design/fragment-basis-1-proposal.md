---
name: fragment-basis-1-proposal
title: "FRAGMENT-BASIS-1: what the example corpus measures, and what Lever B's evidence now is"
status: "Rev 1, review-ready, awaiting user adjudication. The roadmap row's re-measured labels (54 no-post, 2 contract-post-outside-fragment, 7 body-outside-fragment over 17 example files) are CONFIRMED by an independent census run at v0.23.0. Three findings go past the row. FIRST, the bucket is opened: all 11 fragment escapes in the tracked tree are named with the sub-term each one refused, and NOT ONE is a list-shaped or string-shaped contract. The only two contract-post escapes in the whole tree are erc20's `transfer` and `transfer-from`, and both refuse on `app:total-supply`, a call to a user-defined function inside a post. That is refinement reflection, which is Lever C's mechanism, not Lever B's. SECOND, a full contract-vocabulary census over 1094 post clauses and 885 pre clauses finds exactly 2 list symbols in contract position tree-wide, both `list-length`, which is already inside Σ_auto; a probe confirms that a `list-length` post on a `list[int]` parameter reaches body-faithful today. THIRD, an eliminative probe re-expresses the tictactoe board over `bytes[9]` and reaches body-faithful with no compiler change, so the two tictactoe escapes are a data-representation choice and not a fragment-width limit. The corpus decision is ALREADY MADE in the tree: three contracted game twins exist, one for each game, at 29% function coverage for Conway. The recommendation is to make no new corpus decision, to record Lever B as unevidenced, and to spend the fragment-width budget on the one gap the corpus does demand: `Σ_auto` refuses multiplication by an integer literal, which QF-LIA admits, and a row-major board index needs it. Two instrument findings are filed for routing: the census histogram covers 69 of 156 declared functions in its own population, and `contract-pre-outside-fragment` reads 0 tree-wide while two pre clauses use symbols outside Σ_auto."
date: 2026-09-09
author: language-team
consumers: [compiler-engineer, professor, documentation-lead, user]
---

# FRAGMENT-BASIS-1: what the example corpus measures, and what Lever B's evidence now is

**One line.** The corpus does not show that the contract vocabulary is too
narrow for lists. It shows that the programs which use lists carry no contracts,
and that the programs which carry contracts stay inside `Σ_auto`.

## 1. Summary

`FRAGMENT-BASIS-1` asks two questions and forbids folding them together. This
proposal answers both, and adds a third answer the row did not ask for.

1. **Should the example corpus carry contracts at all?** It already does. Three
   contracted game twins exist under `examples/hangman_json_verifier/`,
   `examples/tictactoe_json_verifier/` and
   `examples/conways_life_json_verifier/`. `examples/README.md` names them. No
   new corpus decision is owed. The recommendation is to leave the two-arm shape
   alone, and to stop reading the uncontracted arm as a fragment-width figure.

2. **Which vocabulary would a contracted corpus need?** Measured over every
   contract clause in the census roots, the answer is: nothing that Lever B
   provides. Lever B stays unevidenced. The recommendation is to say so in the
   roadmap and to keep the lever at its current status.

3. **What does the corpus demand instead?** One arithmetic symbol. `Σ_auto`
   refuses `(* 8 r)`, a product with an integer-literal operand, which QF-LIA
   admits. A row-major board index is `row * width`. That single refusal is what
   stops a two-dimensional board from being verified over the shipped array
   class.

## 2. Restatement

The roadmap row states that the first Lever B data point measured absent
contracts and not an unexpressible vocabulary. The design question is what
evidence Lever B now rests on, and whether the example corpus can supply any.
This proposal treats the corpus as an instrument and asks what it can and cannot
discriminate.

Two reference classes matter here and this proposal keeps them apart. The
**measurement set** is the committed tree that `scripts/fallback_census.py`
walks. The **design-reference set** is the verified-language ecosystem that
Lever B competes with on safe list indexing: Liquid Haskell, F\*, Dafny and
Idris. A corpus finding constrains the first. It does not by itself settle
whether the second justifies the lever.

## 3. Context located

1. `docs/compiler-team-roadmap.md`, the `FRAGMENT-BASIS-1` row. States the
   re-measured labels and the two sub-questions.
2. `docs/compiler-team-roadmap.md`, the Data Scope Extension section (anchor
   `#future--data-scope-extension-unversioned`). Lever B is "dependent lengths (`list[t]{len=n}`) plus a
   widened measure catalog", status **Proposed**, effort **low**, depends on
   Lever A.
3. `docs/design/critique-2026-09-05-triage.md` section 5. The first data point.
   It reported 51 of 61 entries as `contract-post-outside-fragment` and
   concluded that the width limit is the contract vocabulary.
4. `docs/design/data-scope-extension.md`, the Lever B section. Lever B's stated
   role is the bridge from "count a list" to "index a list safely".
5. `scripts/fallback_census.py` and `scripts/fallback-census/README.md`. The
   instrument, its method, and the reason it exists.
6. `scripts/fallback-census/BASELINE.json`. The committed baseline: 695 of 706
   body-faithful, ratio 0.9844, 490 with no goal, 98 files in the strict-pass
   set.
7. `LLMLL.md` section 5.3.3 and section 5.3.5. The `Σ_auto` definition, the
   class table, and the completeness statement.
8. `examples/README.md`. Names the two arms of the game corpus and gives the
   stated reason the contracted arm does not verify.
9. `examples/conways_life_json_verifier/VERIFICATION_SCOPE.md`. A per-function
   verification-scope matrix, 6 of 21 functions contracted.
10. `compiler/src/LLMLL/FixpointEmit.hs`. The multiplication guards and the
    `nonlinear:` construct label.

**No in-flight draft exists on this topic.** `docs/design/INDEX.md` carries no
`FRAGMENT-BASIS` row and `docs/design/` carries no matching file. This proposal
is new, not a revision.

**One spec-precision finding was made while reading, and it is section 9.1.**

## 4. What I measured

Every number below comes from a run I made on 2026-09-09 at `llmll 0.23.0`. The
binary is current: the last commit touching `compiler/` changed only the version
string in `compiler/package.yaml` and `compiler/llmll.cabal`, and the binary
already reports `0.23.0`. The working tree was clean before and after. No
committed sidecar was rewritten; every probe ran on a copy.

### 4.1 The census reproduces its own baseline

I ran `scripts/fallback_census.py` over the tracked tree at `--jobs 1` with
`--no-ratchet`. The result equals the committed baseline value for value:

    250 files, ratio 0.984 (695/706 body-faithful, 490 with no goal), strict-pass 98

Per-file outcomes: pass 98, fallback 83, scaffold 32, no-goal 31, check-failed 4,
refuted 2.

The cause histogram over the whole tracked tree:

| Cause | Entries |
|---|---|
| `no-post` | 246 |
| `unfilled-hole` | 244 |
| `body-outside-fragment` | 9 |
| `contract-post-outside-fragment` | 2 |
| `contract-pre-outside-fragment` | 0 |
| `contract-signature-outside-fragment` | 0 |
| `path-cap-exceeded` | 0 |
| `mixed-map-tail` | 0 |

Split by root:

| Root | Files | Body-faithful | `no-post` | `unfilled-hole` | Body escape | Contract-post escape |
|---|---|---|---|---|---|---|
| `examples` | 183 | 653 | 54 | 241 | 7 | 2 |
| `tools` | 56 | 40 | 165 | 3 | 1 | 0 |
| `scripts/build-smoke` | 11 | 2 | 27 | 0 | 1 | 0 |
| Total | 250 | 695 | 246 | 244 | 9 | 2 |

**The roadmap row's 54, 2 and 7 are correct.** I enumerated the population
independently. Exactly 17 example files carry at least one refusal that is not
`unfilled-hole`, and those 17 files carry exactly 54, 2 and 7. The 17-file
population and the whole `examples` root give the same three numbers, because
every other example file contributes none.

I also checked the file the row names. `examples/life_sexp/world.llmll` declares
15 functions and contains zero `post` clauses and zero `pre` clauses. That
reproduces.

### 4.2 The bucket, opened

Below is every fragment escape in the tracked tree, with the minimal sub-term the
emitter refused. This is the whole population, not a sample.

| Function | File | Cause | Refused sub-term |
|---|---|---|---|
| `transfer` | `examples/erc20_token/erc20_filled.ast.json` | contract-post | `app:total-supply` |
| `transfer-from` | `examples/erc20_token/erc20_filled.ast.json` | contract-post | `app:total-supply` |
| `cell-at` | `examples/conways_life_json_verifier/life.ast.json` | body | `let` |
| `count-alive` | `examples/conways_life_json_verifier/life.ast.json` | body | `if` |
| `make-state` | `examples/hangman_json_verifier/hangman.ast.json` | body | `pair` |
| `state-max-wrong` | `examples/hangman_json_verifier/hangman.ast.json` | body | `app:second` |
| `make-board` | `examples/tictactoe_json_verifier/tictactoe.ast.json` | body | `app:list-prepend` |
| `set-cell` | `examples/tictactoe_json_verifier/tictactoe.ast.json` | body | `let` |
| `square` | `examples/leanstral-demo/square.llmll` | body | `nonlinear:*` |
| `smoke-sha1` | `scripts/build-smoke/smoke.llmll` | body | `app:sha1` |
| `drv-status` | `tools/llmll-driver/sequencer.llmll` | body | `match` |

Not one entry is a list-shaped contract or a string-shaped contract. The two
contract-side entries both refuse on a call to a user-defined function inside a
post. `LLMLL.md` section 3.4.5 already names that case: a predicate that uses
user functions leaves `Σ_auto`. Its repair is refinement reflection or Proof by
Logical Evaluation, which `docs/design/data-scope-extension.md` assigns to
**Lever C**, not Lever B.

Three of the nine body entries report a container form (`let`, `if`, `match`)
rather than the term inside it. I opened those too. `cell-at` has the post
`(and (>= result 0) (<= result 1))` and a body whose `let` wraps a `list-nth`
call. `count-alive` has the post `(>= result 0)` and a body that recurses with
`list-head`, `list-tail` and `list-length`. So the contracts on both are pure
QF-LIA and the bodies are what leave the fragment.

### 4.3 The contract vocabulary the corpus actually uses

I scanned every `pre` and `post` clause in the census roots. The population is
175 `.llmll` files and 75 `.ast.json` files, giving 1094 post clauses and 885
pre clauses. Below is every non-arithmetic symbol that appears in any of them.

| Symbol | Occurrences | Class in `Σ_auto` |
|---|---|---|
| `map-has` | 45 | array class, in `Σ_auto` |
| `map-get` | 36 | array class, in `Σ_auto` |
| `Next`, `Rejected`, `Paid`, `ErrPkt`, `Accepted`, `AckPkt`, `DataPkt`, `ok`, `err` | 77 | datatype class, in `Σ_auto` |
| `second` | 11 | pair, in `Σ_auto` |
| `first` | 10 | pair, in `Σ_auto` |
| `bytes-get` | 8 | array class, in `Σ_auto` |
| `bytes-length` | 4 | array class, in `Σ_auto` |
| `string-length` | 3 | measure class, in `Σ_auto` |
| `list-length` | 2 | measure class, in `Σ_auto` |
| `total-supply`, `allowance`, `state-wrong-count`, `state-max-wrong` | 12 | user functions, **outside** `Σ_auto` |
| `string-empty?` | 3 | boolean-builtin class, **outside** `Σ_auto` |

**List vocabulary in contract position across the whole tracked tree is two
occurrences of `list-length`.** Both sit in
`examples/tictactoe_json_verifier/tictactoe.ast.json`, in the posts of
`make-board` and `set-cell`, and both read `(= (list-length result) 9)`.
`list-length` is measure class and is already inside `Σ_auto`. `list-nth`
appears in zero contracts. So do `string-slice`, `string-char-at` and every
`json-` operation.

### 4.4 Positive witness: a list post already verifies

I ran this file against the v0.23.0 binary:

```
(def-shell listed-len-post [xs: list[int]]
  (post (= result (list-length xs)))
  (list-length xs))
```

It reports `body_faithful` and `success: true`. A `list-length` post on a
`list[int]` parameter reaches body-faithful verification today. Lever B is not
needed to state such a post and is not needed to discharge it.

### 4.5 Eliminative probe: the tictactoe board did not have to be a list

`examples/README.md` explains the contracted game twins with one parenthetical:
"the board is a `list`, outside the decidable fragment". I tested whether the
board had to be a list. The tictactoe board is nine cells with a literal size, so
it fits the shipped array class. I re-expressed the same three operations over
`bytes[9]`:

```
(def make-board [] -> bytes[9]
  (post (= (bytes-length result) 9))
  (bytes-zero))

(def set-cell [board: bytes[9] index: int val: int] -> bytes[9]
  (pre  (and (and (>= index 0) (< index 9)) (and (>= val 0) (<= val 2))))
  (post (= (bytes-length result) 9))
  (bytes-set board index val))

(def cell-at [board: bytes[9] index: int] -> int
  (pre  (and (>= index 0) (< index 9)))
  (post (and (>= result 0) (<= result 255)))
  (bytes-get board index))
```

All three reach body-faithful and the file passes `--strict-verified-core`. No
compiler change was made. The idiom is the one
`examples/bytes-bounds/read-at.llmll` already ships.

**This is eliminative evidence.** The two tictactoe escapes come from a
data-representation choice, not from the width of the fragment. Those two
functions can no longer serve as evidence for Lever B, because the same program
verifies today over a type the project already supports.

### 4.6 Why Conway does not follow, and what stops it

I applied the same test to a Conway grid and it fails for a reason worth naming.
A flat grid needs a row-major index, `row * width`. I ran both operand shapes:

| Probe | Result | Refused sub-term |
|---|---|---|
| `(bytes-get grid (+ (* row 8) col))` in a `def` | rejected at check time | core-grammar violation, "non-linear arithmetic" |
| `(bytes-get grid (+ (* row 8) col))` in a `def-shell` | body escape | `app:bytes-get` |
| `(* r 8)` as a whole body | body escape | `nonlinear:*` |
| `(* 8 r)` as a whole body | body escape | `nonlinear:*` |
| `(post (= result (* 8 r)))` | **contract-post escape** | `nonlinear:*` |
| `(bytes-get b (+ (+ r r) c))` in a `def` | body-faithful | none |

A sum-built index verifies. A product-built index does not, and it does not even
when one operand is an integer literal.

The nested alternative is not available either. `map[k,v]` values are restricted
to `{int, bool, string}` by `LLMLL.md` section 5.3.5, so a map of rows cannot
hold a `bytes` value. A grid of rows is therefore not expressible in the shipped
array class.

### 4.7 Two instrument findings

**(a) The histogram is not a partition of the function population.** Over the 17
example files, `fn_kinds` declares 156 functions. Only 69 appear in either
`body_faithful` or `body_fallback_causes`. The other 87 appear in neither. A
four-function probe isolates the rule:

| Definition | Reported |
|---|---|
| `(def typed-int [x: int] (+ x 1))` | `no-post` |
| `(def untyped [x] (+ x 1))` | nothing |
| `(def-shell typed-list [xs: list[int]] (list-length xs))` | nothing |
| `(def-shell untyped-shell [xs] 0)` | nothing |

Adding a post to the list-typed function makes it appear, as body-faithful. So
the reported `no-post` count of 54 is a floor. The uncontracted population of
those 17 files is 141 of 156, which is 90 percent, and the instrument reports 54
of them.

**(b) `contract-pre-outside-fragment` reads 0 while two pre clauses leave
`Σ_auto`.** `examples/orchestrator_walkthrough/auth_module_filled.ast.json`
gives `login-handler` the clause `(pre (not (string-empty? password)))`.
`string-empty?` is boolean-builtin class, which `LLMLL.md` section 5.3.5 places
outside `Σ_auto`. The census reports that function as `no-post`, because a
function with no post has no goal and nothing refuses.
`examples/hangman_json_verifier/hangman.ast.json` gives `apply-guess` the clause
`(pre (<= (state-wrong-count state) (state-max-wrong state)))`, two calls to
user functions. `apply-guess` is one of the 87 unaccounted functions, and
`state-max-wrong` is instead reported as a body escape on `app:second`.

Both findings point the same way. The contract-side escape count of 2 is a floor
and not a measurement of demand.

## 5. Design proposal

### 5.1 Sub-question (1): should the example corpus carry contracts at all?

**Recommendation: make no new corpus decision. Keep the two-arm shape. Change
how the census figure is read, not what the corpus contains.**

The corpus already has a contracted arm and an uncontracted arm, and
`examples/README.md` states the split. The uncontracted arm is
`hangman_sexp`, `hangman_json`, `tictactoe_sexp`, `life_sexp` and `life_json`.
Its job is to show the two surface formats on one program, and `hangman_json` is
the worked example in `docs/getting-started.md`. A contract there teaches nothing
about a surface format. It would add about 141 proof goals that no reader
consults.

The contracted arm is the three `_json_verifier` directories.
`examples/conways_life_json_verifier/VERIFICATION_SCOPE.md` already gives a
per-function matrix at 29 percent coverage, names which functions reach
`verified`, and states the boundary it believes it hit.

What is owed is not more contracts. It is a reading rule. Three moves, in order
of cost:

1. **Report `no-post` per root.** The census already computes the split. Adding
   it to the record costs one field. A figure that mixes `tools` and
   `scripts/build-smoke` with `examples` cannot size an example-corpus question,
   and 192 of the 246 `no-post` entries are outside `examples`.
2. **Exclude the surface-format arm from any figure that sizes a fragment row.**
   Those five directories are pedagogy for the surface. Their `no-post` count
   measures a deliberate choice, not a limit.
3. **Close the instrument hole in section 4.7(a) before the next reading.** A
   histogram that covers 69 of 156 declared functions cannot support a claim
   about what the corpus does or does not express.

### 5.2 Sub-question (2): which vocabulary would a contracted corpus need?

**Recommendation: record Lever B as unevidenced by this corpus. Keep its
roadmap status unchanged. Do not promote it on the strength of the section 5
count.**

The measured demand, over every contract clause in the census roots, is:

| Demand | Occurrences | Where it routes |
|---|---|---|
| User-function calls in `pre` or `post` | 12, over 4 names | Refinement reflection or PLE. **Lever C.** |
| `string-empty?` in a `pre` | 3 | Boolean-builtin class. Needs an SMT string theory. Not a lever. |
| Multiplication by an integer literal | 1 measured witness, plus every row-major index | **Section 5.3.** Narrower than any lever. |
| List operations in **bodies** | 4 functions | Body-side reflection. Lever B does not admit these. |
| Pair projection in a body | 2 functions | Existing datatype and pair class. Engineer question. |
| Nonlinear multiplication | 1 function | Already routed to the Lean tier. |
| **List vocabulary in a contract** | **0 outside `Σ_auto`** | **Nothing. Lever B has no entry.** |

The last row is the finding. Lever B widens the **contract** vocabulary with
`list[t]{len=n}` and a larger measure catalog. The corpus contains no contract
that needs a wider list vocabulary, and section 4.4 shows that the list post the
corpus does write already verifies.

The four list operations that do refuse are all in **bodies**: `list-nth` in
`cell-at`, `list-head` and `list-tail` recursion in `count-alive`,
`list-prepend` in `make-board`, `list-map` in `set-cell`. Lever B as written does
not admit any of them to a body verification condition. So even the body-side
demand is not what Lever B ships.

### 5.3 What the corpus does demand: a literal-coefficient product

**Recommendation: file the multiplication case as its own row, and treat it as
the cheapest fragment-width move available.**

`LLMLL.md` section 5.3.3 closes the QF-LIA-core symbol set at
`+ - = != < <= > >= and or not`, integer and boolean literals, and variables.
`*` is not in that set. Section 5.3.5 then describes the same class as "genuine
QF-LIA". Those two statements do not agree, because QF-LIA admits a product with
an integer-literal coefficient. Section 4.6 measures which one the compiler
follows: it follows the symbol set, and it refuses `(* 8 r)` in a body and in a
post.

The mechanism is checkable and local. `compiler/src/LLMLL/FixpointEmit.hs`
refuses `*` by operator name at four sites and inspects no operand. The
`def` core-grammar check in `compiler/src/LLMLL/TypeCheck.hs` rejects the same
operator earlier, and `compiler/src/LLMLL/Diagnostic.hs` prints it as
"non-linear arithmetic".

The value is concrete. A two-dimensional board index is `row * width`. Admitting
a literal-coefficient product would let a fixed-width grid be verified over the
shipped array class, in the same way section 4.5 verified the tictactoe board.
That reaches the Conway example, which is the example the section 5 count was
about.

This is a candidate, not a settled design. Section 6.4 gives the degenerate case
that decides its shape, and section 7 gives its verification mapping.

### 5.4 What would settle Lever B, and what it costs

Lever B ships safe list **indexing**: a length-indexed list type and an index
refinement checked against the list's own length, so a read carries a
prove-polarity in-bounds precondition. Today `list-nth` has the signature
`list[a] int -> Result[a, string]`, so an out-of-range read returns an `Error`
value. No author has ever needed the proof, because the type already handles the
failure.

**That is why the corpus cannot settle Lever B.** Absence of a list-indexing
contract is what the current `list-nth` signature predicts. It does not
distinguish "the author could not express it" from "the author did not need to".
The two readings are confounded in every file, and section 4.5 shows the
confound is real: when a fixed-size buffer was available, the same program
verified.

Three things would settle it, in increasing cost.

1. **Finish the elimination. Cost: one file, no compiler change.** Re-express
   `examples/conways_life_json_verifier/life.ast.json` over the shipped array
   class and record what stops it. Section 4.6 predicts the answer is the
   literal-coefficient product and nothing else. If that prediction holds, every
   game escape in the tree is explained without Lever B, and Lever B's remaining
   case is narrowed to programs that need a length-polymorphic list rather than a
   fixed-size buffer.

2. **Build the discriminating cell. Cost: one contracted program, one census
   run, no compiler change.** Author one program whose data really is
   length-polymorphic, contract it as far as the current fragment allows, and
   record each post the author cannot state. A post the author cannot write is a
   positive witness. An absence count is not. Candidate shape: a parser or a
   framing routine over a variable-length record, where the length is an input
   and not a literal.

3. **Spike the surface. Cost: a compiler change, so this is a decision and not a
   measurement.** A `list[t]{len=n}` binder and a total indexed read cannot be
   written today, so no probe can measure them. This step should not start until
   step 2 produces a post that the current fragment refuses.

**Steps 1 and 2 are eliminative. Step 3 is corroborative and is worth less.** A
Lever B spike that succeeds shows only that the feature can be built. It does not
show that any program needed it.

### 5.5 What is still unevidenced, stated plainly

1. **Lever B has no supporting entry in the committed corpus.** Zero of the 11
   fragment escapes, and zero of the contract symbols outside `Σ_auto`, are what
   Lever B widens.
2. **The corpus cannot refute Lever B either.** Section 5.4 gives the reason: the
   `list-nth` signature predicts the absence. The measurement narrows the claim.
   It does not close the lever.
3. **The design-reference case for Lever B is untested here.** Liquid Haskell,
   F\*, Dafny and Idris all ship length-indexed sequence types. Whether LLMLL
   needs one for adoption is a separate argument from what this corpus contains,
   and this proposal does not make it.
4. **The 87 unaccounted functions have a measured count and no explained
   mechanism.** The probe in section 4.7(a) shows that a reflecting signature is
   sufficient for a function to appear. It does not show what the necessary
   condition is. That is a compiler question.
5. **The literal-coefficient product has one measured witness and no cost
   estimate.** Section 5.3 names the guards. It does not estimate the work, and
   it does not check what else those four guards protect.

## 6. Edge cases and degenerate inputs

### 6.1 A function with no post and a pre outside `Σ_auto`

**Input shape.** `(def-shell f [s: string] (pre (not (string-empty? s))) 0)`.
Live instance: `login-handler` in
`examples/orchestrator_walkthrough/auth_module_filled.ast.json`.

**Expected behavior.** The census reports `no-post` and nothing else. That is
correct on its own terms, because no post means no body verification condition
and nothing to refuse. It is also why the contract-side count understates
demand.

**Channel.** Contract channel, and the spec is silent by design.
`LLMLL.md` section 5.3.5 places the boolean-builtin class outside `Σ_auto`, but
no obligation is generated when there is no goal.

**Consequence for this proposal.** Any figure that reads `contract-pre-outside-fragment`
as demand must first add a post. Section 5.1 move 3 covers it.

### 6.2 A contract symbol that is a user function

**Input shape.** `(post (<= (+ from-bal to-bal) (total-supply)))`. Live instance:
`transfer` in `examples/erc20_token/erc20_filled.ast.json`.

**Expected behavior.** `contract-post-outside-fragment`, refused sub-term
`app:total-supply`. Measured.

**Channel.** Contract channel. `LLMLL.md` section 3.4.5 names user functions as
a scope-boundary case.

**Consequence.** This is the only contract-side escape shape in the tree, and it
routes to Lever C, not Lever B. A proposal that reads the contract-post bucket
as list demand reads it wrong.

### 6.3 A list post that already verifies

**Input shape.** `(def-shell f [xs: list[int]] (post (= result (list-length xs))) (list-length xs))`.

**Expected behavior.** Body-faithful, `success: true`. Measured in section 4.4.

**Channel.** Contract channel, measure class, auto-discharged.

**Consequence.** This is the degenerate case that refutes "posts over lists need
a wider `Σ_auto`" as a general claim. A length-shaped list post is inside the
fragment today.

### 6.4 Positive witness for the section 5.3 candidate: the product that must stay out

**Input shape.** `(def-shell f [r: int w: int] (post (= result (* r w))) (* r w))`,
with both operands variables.

**Expected behavior under the proposal.** Still refused, still labelled
`nonlinear:*`. The proposal admits a product only when one operand is an integer
literal. A variable times a variable is genuinely nonlinear and leaves QF-LIA.

**Firing witness for the admitted side.** `(post (= result (* 8 r)))` with
`(pre (and (>= r 0) (< r 8)))`. I ran that exact clause and it reports
`contract-post-outside-fragment` with construct `nonlinear:*` today. Under the
proposal it discharges in QF-LIA. This is a concrete input, not an abstract
description, and it fires now.

**Channel.** Contract channel and body channel, both. Both guards live in
`compiler/src/LLMLL/FixpointEmit.hs` and both refuse by operator name.

**Consequence.** The guard the proposal narrows has a live firing case on each
side. It is not dead code in either direction.

### 6.5 A grid that cannot move to the array class at all

**Input shape.** A grid of variable width, indexed `row * width` with `width` a
parameter.

**Expected behavior under the proposal.** Still refused. A literal coefficient is
required, and `width` is a variable. `map[k,v]` also cannot hold rows, because
`LLMLL.md` section 5.3.5 restricts values to `{int, bool, string}`.

**Channel.** Body channel, `nonlinear:*`, and a type-level restriction with no
obligation.

**Consequence.** The section 5.3 candidate reaches a fixed-width board and stops
there. It is not a general list story, and this proposal does not claim it is.

## 7. Verification mapping

This proposal introduces no new construct in sections 5.1 and 5.2. Those are a
corpus reading rule and a roadmap status statement. They carry no obligation.

Section 5.3 does introduce one. The mapping:

| Obligation | Channel | Fragment | Note |
|---|---|---|---|
| A product with one integer-literal operand, in a body verification condition | contract (body-faithful VC) | **QF-LIA, auto-discharged by liquid-fixpoint** | A literal coefficient keeps the term linear. `LLMLL.md` section 5.3.5 states that QF-LIA is decidable and that Z3 is complete on it. The class is unchanged; only the symbol set at section 5.3.3 widens. |
| A product with one integer-literal operand, in a `pre` or `post` | contract | **QF-LIA, auto-discharged** | Same term, same class. `augmentContractPost` folds it in the same way it folds any other post term. |
| A product with two variable operands | contract | **escapes to Lean (`?proof-required`)** | Unchanged. `examples/leanstral-demo/square.llmll` is the existing witness and the existing route. |
| An index-in-bounds obligation over a literal-coefficient index | contract | **QF-LIA, auto-discharged** | The array-class obligation is unchanged. Only the index term becomes emittable. `examples/bytes-bounds/read-at.llmll` is the shape. |

**No obligation in this proposal escapes to Lean that does not escape today.**
The change is a narrowing of a refusal, not a widening of a theory. `Σ_auto` gains
no new sort, no new uninterpreted function and no new axiom, so the completeness
statement at `LLMLL.md` section 5.3.5 stands as written.

**Strict immutability is untouched.** `bytes-set` is a functional update that
returns a new buffer, and section 4.5 uses it that way. No probe in this proposal
needs a mutable reference, an alias or an in-place update.

## 8. Affected surface

This is the seam where the engineer and the doc-lead take over. It is not an
implementation plan.

**If section 5.1 is adopted (corpus reading rule):**

1. `scripts/fallback_census.py`. Add a per-root split to the census record. The
   aggregate already computes the parts.
2. `scripts/fallback-census/README.md`. State that a `no-post` count is not a
   fragment-width figure, and that the reading rule is per root.
3. `scripts/tests/test_fallback_census.py`. The cover for the new field.
4. `docs/compiler-team-roadmap.md`. The `FRAGMENT-BASIS-1` row, doc-lead's slot.

**If section 5.2 is adopted (Lever B status):**

5. `docs/compiler-team-roadmap.md`, the Data Scope Extension table, Lever B row.
   Record that the corpus supplies no supporting entry. Doc-lead's slot.
6. `docs/design/data-scope-extension.md`, the Lever B section. Same statement.

**If section 5.3 is adopted (literal-coefficient product):**

7. `compiler/src/LLMLL/FixpointEmit.hs`. Four operator-name guards refuse `*`
   with no operand inspection. Each needs a literal-operand test.
8. `compiler/src/LLMLL/TypeCheck.hs`. The `def` core-grammar check rejects `*`
   before the emitter sees it.
9. `compiler/src/LLMLL/Diagnostic.hs`. The `core-grammar-violation` message says
   "non-linear arithmetic" and would need to say less.
10. `LLMLL.md` section 5.3.3, the QF-LIA-core symbol row, and section 5.3.5, the
    "genuine QF-LIA" sentence. Doc-lead's slot after the engineer ships.
11. A regression witness under `examples/bytes-bounds/`, in the shape of
    `examples/bytes-bounds/read-at.llmll`.

**Instrument findings for routing (section 4.7):**

12. The 87 unaccounted functions. This is a census-population question and needs
    a roadmap row of its own. It is not `FRAGMENT-BASIS-1`.
13. The container-form construct labels (`let`, `if`, `match`). The construct
    histogram names an enclosing form for three of nine body escapes, so it does
    not identify the refused term. This limits the histogram's use as a
    fragment-width instrument.

**Documentation drift found while reading, unrelated to the decision:**

14. `LLMLL.md` section 13.13 still says a `json-` body "reaches `contract-checked`
    rather than a body-faithful VC". `TRUST-CC-1` retired that tier at v0.23.0.
    Nine other mentions in the file are retirement notes and are correct. This one
    presents the tier as reachable. Doc-lead's slot.

**Nothing here is out of scope under the freeze policy.** Section 5.3 changes an
operand test on an existing operator. It adds no builtin, no syntax construct, no
FFI tier and no orchestration feature.

## 9. Risks and open questions

### 9.1 The spec calls a symbol set "genuine QF-LIA" when it is narrower

**Classify:** spec-drift, and precision rather than contradiction.
**Cite:** `LLMLL.md` section 5.3.3 closes the QF-LIA-core symbol set without `*`.
Section 5.3.5 calls the same class "genuine QF-LIA". QF-LIA admits a
literal-coefficient product.
**Effect:** Complicates. A reader who trusts the section 5.3.5 sentence will write
`(* 8 r)` and get a refusal the spec does not predict. This is the finding that
produced section 5.3. It does not block anything.

### 9.2 The census histogram covers 69 of 156 declared functions in its own population

**Classify:** verification-ergonomics, and instrument soundness.
**Cite:** section 4.7(a). Measured on the 17-file population and isolated with a
four-function probe.
**Effect:** Blocks any further reading of this histogram as a corpus measurement.
Every posted function I checked is accounted for, so the ratio 0.9844 is
sound. The
`no-post` bucket is not. This is the fourth reading of this histogram, and it is
the first to check whether the buckets sum to the population.

### 9.3 Section 5.3's guards may protect something else

**Classify:** scope.
**Cite:** `compiler/src/LLMLL/FixpointEmit.hs` refuses `*` at four sites, and I
have not traced what else reaches each one. the division, modulus, remainder and exponent operators share the same
lists.
**Effect:** Complicates. The engineer must check each site before narrowing any of
them. A change at one site and not the others would leave the body channel and
the contract channel disagreeing.

### 9.4 Section 5.1 leaves the game corpus unable to demonstrate verification

**Classify:** scope.
**Cite:** `examples/README.md` and
`examples/conways_life_json_verifier/VERIFICATION_SCOPE.md`. The contracted arm
reaches `verified` on two Conway functions and on none of the other two games.
**Effect:** Only matters at scale, and only for pedagogy. Section 4.5 shows the
tictactoe half is fixable today with a data-representation change, if the project
wants a game example that verifies. That is a separate decision and this
proposal does not make it.

### 9.5 The elimination in section 4.5 does not transfer to a variable-width grid

**Classify:** scope.
**Cite:** section 4.6 and `LLMLL.md` section 5.3.5 on map value sorts.
**Effect:** Complicates section 5.4 step 1. Conway's grid is variable-width in the
example as written. Step 1 may need to fix the width to make the test, and a
fixed-width Conway is a weaker witness than the current example.

### 9.6 Contract-side demand is measured at a floor and the floor may be low

**Classify:** verification-ergonomics.
**Cite:** section 4.7(b). Two pre clauses use symbols outside `Σ_auto` and
neither is counted.
**Effect:** Complicates. The count of 2 supports "Lever B has no entry" because
the two entries that exist are both user-function calls. It does not support any
statement about the size of contract-side demand in general.

## 10. Open questions for the professor

**None. This section is empty and that is the result of a test, not an
omission.**

Four candidates were raised and each one failed the negative test or dissolved.
Whether a literal-coefficient product is sound in QF-LIA is settled by the
definition of QF-LIA and by `compiler/src/LLMLL/FixpointEmit.hs`, so it is
homework and it is done. What the 87 unaccounted functions have in common is
answered by a probe and by the compiler, so it is homework and it is routed to a
roadmap row instead. Whether Lever B should be justified from the
design-reference set rather than from this corpus is already answered inside the
tree, because `docs/design/data-scope-extension.md` states that justification;
what remains is a user decision, and section 5.2 puts it in front of the user.
Whether a narrow instrument population has a name in the measurement literature
does not change what gets built, and it does not earn a `Q-NNN` entry in
`docs/design/theory-questions.md` either.

## 11. Hand-off

This proposal is **spec-track and code-track at once**, and the two halves
separate cleanly.

**Spec-track, for `documentation-lead`, after user approval.** Sections 5.1 and
5.2 need no compiler change. They change how a figure is read and what a roadmap
row records. The affected documents are `docs/compiler-team-roadmap.md` (the
`FRAGMENT-BASIS-1` row and the Lever B row),
`docs/design/data-scope-extension.md` (the Lever B section) and
`scripts/fallback-census/README.md` (the reading rule). Item 14 in section 8 is a
separate drift fix in `LLMLL.md` section 13.13 and is not part of this decision.

**Code-track, for `compiler-engineer`, only if the user adopts section 5.3.**
The settled surface is unchanged. The settled semantics is one narrowing: admit a
product when one operand is an integer literal, in a body verification condition
and in a contract clause, and keep refusing a variable-times-variable product.
The settled verification mapping is section 7: QF-LIA, auto-discharged, no new
sort and no new axiom. The affected modules are
`compiler/src/LLMLL/FixpointEmit.hs`, `compiler/src/LLMLL/TypeCheck.hs` and
`compiler/src/LLMLL/Diagnostic.hs`. There is no JSON-AST delta.

**Two rows are owed and neither belongs to `FRAGMENT-BASIS-1`.** The census
population hole in section 4.7(a) and the container-form construct labels in
section 8 item 13 are instrument defects. They should be filed against
`scripts/fallback_census.py` and the emitter's construct reporting, not against
this row.
