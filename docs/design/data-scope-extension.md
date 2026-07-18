# The Data Scope of LLMLL Verification — where we are, and where we're going

> **Status:** Design / roadmap — **partly shipped.** Posts 1–5 (the decidable core) describe
> capabilities shipped as of `llmll 0.14.51`; **Lever A** of the extension — the SMT theory of
> arrays for `bytes[n]`/`map` (Post 7) — has since **shipped** (v0.14.33–51), so Post 6's array and
> map bug-classes are now caught and Post 8's goal is met. The two remaining levers (**B** dependent
> lengths, **C** induction) are proposals for future work, not commitments.
> **Audience:** a technically literate third party — someone who knows a little SMT and a little
> functional programming, and wants to understand *exactly* what this compiler can and cannot
> prove about data, and what it would take to widen that.
> **Format:** a multi-post series. Read it front to back; each post assumes the previous one.
> **Companion:** the engineering tickets are in
> [`compiler-team-roadmap.md`](../compiler-team-roadmap.md) → *Future — Data Scope Extension*.

---

## Prologue — why this document exists

Someone looked at our flagship verified example — a 163-function secure channel — and asked one
sharp question:

> *"Will this use any complex data type: list, array, circular list, stacks, hash…?"*

The answer, stated precisely: **more than it used to, but with a sharp and defended edge.** LLMLL
verifies rich properties over **integers** and **non-recursive tagged unions**, reasons about the
**length** of a list or string, and — since Lever A shipped (Post 7) — proves **index-in-bounds on
`bytes[n]` buffers** and **get-after-put / key-presence on `map`s** with `{int,string}` keys and
`{int,bool,string}` values. What it still cannot prove is the *contents* or *structure* of a
**list** (indexing is Lever B, unshipped) or of any **recursive** data structure (Lever C, fenced).
Those live outside the decidable core the whole trust story is built on.

That answer deserves more than a shrug, for two reasons:

1. **It is the single most important thing to understand about the language's reach.** Of the famous
   bugs that would be *most* convincing to catch, the wall now falls *between* them: a buffer
   overread that indexes past a `bytes[n]` buffer and a hash table that mishandles a key are **now
   caught** (Lever A); a use-after-free walking a linked list, or any invariant over recursive
   structure, is **still outside** (Lever C). Knowing exactly where that wall sits, and *why*, is
   the difference between a precise claim and an overclaim.

2. **It is a roadmap, not a dead end.** The wall is made of *decidability*, and decidability can be
   bought — at known prices, with known trade-offs. This document lays out what we'd buy, in what
   order, and what each purchase unlocks.

**What we set out to achieve** was a verified example in which *the data structure itself is the
risk* — the data-axis analog of the Heartbleed length-discipline story — caught within a theory the
solver can actually decide. Lever A delivered it: `examples/bytes-bounds/` (an index that must be
proved in-bounds) and `examples/token-revocation-emergent/` (key-presence-gated map reads, the A4
flagship). What follows is precise about where the boundary sits now — five posts on the decidable
core, then three on the bug classes, the extension levers, and the goal, with **Lever A now
shipped** and Levers B and C still ahead.

---

## Post 1 — How LLMLL proves anything: the decidable core

Everything downstream follows from one design decision, so start here.

LLMLL is a **refinement-typed** language. A function's contract is a pair of logical predicates —
a **precondition** and a **postcondition** — attached to its type:

```lisp
(def clamp [x: int lo: int hi: int] -> int
  (pre  (<= lo hi))
  (post (and (>= result lo) (<= result hi)))   ;; `result` names the return value
  (if (< x lo) lo (if (> x hi) hi x)))
```

`llmll verify` turns the body against that contract into a **verification condition** (VC) — a
logical formula that is valid *iff* the body satisfies the postcondition whenever the
precondition holds — and hands it to an SMT solver (liquid-fixpoint over Z3). If the solver says
the VC is valid, the function is **`verified`**; if it finds a counterexample, the function is
**`refuted`** (disproved, not merely unproven); if the predicate falls outside what the solver can
decide, the function falls back to **`asserted`** (a claim we take on trust) or **`tested`**
(property-based evidence only). This four-way vocabulary — verified / refuted / tested / asserted —
is the *trust tier* of every function, and it is surfaced in every trust report and `.verified.json`.

Here is the load-bearing subtlety, the one that creates the entire data-scope boundary:

> **"SAFE" is only meaningful because it is a *decidable* predicate on a *fixed* VC.**

We do not run an open-ended proof search. We restrict the predicates that may reach the
`verified` tier to a fragment the spec calls **`Σ_auto`** — a combination of logical theories each
of which is *decidable*, so the solver always terminates with a definite yes/no on the one VC we
built. The spec (§3.4.5, Theorem B) is explicit that the soundness guarantee "degrades to
run-dependence" the moment a VC outside `Σ_auto` is admitted to the body-faithful tier. Decidability
is the currency the trust story is bought with.

Today `Σ_auto` is:

- **QF-LIA** — quantifier-free linear integer arithmetic. `int` is a *mathematical* integer
  (unbounded; it lowers to Haskell `Integer`), so there is no `Int64` overflow gap on `int`.
- **the measure class** — a tiny, closed set of length functions (Post 4).
- **the acyclic (non-recursive) datatype theory** — tagged unions without self-reference (Post 3).

Everything in this series is a statement about what is, or could be, inside `Σ_auto`. That is the
whole game.

---

## Post 2 — The type *surface* vs. the verification *surface*

The most common misunderstanding — the one that made a flat "no, it has no lists" the wrong answer —
is conflating "the language has a type" with "the verifier reasons about it." They are different
surfaces. Every type sits in one of three tiers:

- **T1 — Exists.** It parses, type-checks, and generates running Haskell. You can write programs
  with it.
- **T2 — Verified-over (`Σ_auto`).** The solver reasons about its *values* and can discharge
  refinements over it to the `verified` tier.
- **T3 — Opaque to the verifier.** It exists and runs (T1), but the solver treats it as an
  uninterpreted black box; any refinement that depends on its contents falls back to `asserted`.

Here is the whole surface, mapped:

| Type / former | Surface (T1)? | Verifier sees (T2) | Contents/structure (T3-opaque) |
|---|---|---|---|
| `int` | yes | **full QF-LIA** | — |
| `bool` | yes | as a proposition | — |
| non-recursive `type` sum (ADT) | yes | **constructors, selectors, testers, injectivity** (Post 3) | — |
| `pair` / tuple | yes | **`first`/`second` as datatype selectors** | — |
| `list[t]` | yes | **`list-length` only** (Post 4) | elements, order, membership → opaque |
| `string` | yes | **`string-length` only** | characters, regex → opaque |
| `bytes[n]` | yes | **`select`/`store` reflection, `bytesLen(b)=n` ground fact, byte-range facts, index-in-bounds as a PROVE obligation** (Lever A stage A1 — the off-by-one refutes) | whole-`bytes` `=` → out-of-fragment by design (exact-reflection rule) |
| `map[k,v]` | yes | **two-array presence encoding: `map-has`/get-after-put/key-presence discharge; presence is a PROVE obligation** (Lever A stage A2 — aliased-key and dropped-put twins refute) | string/bool values, cross-call map contracts → fallback (A2.1); whole-map `=` → out-of-fragment by design |
| recursive `type` (self-referential) | **rejected at the verified gate** (Post 5) | — | — |

Read the `list[t]` row carefully, because it is the crux of the "complex data" question. There are
thirteen list builtins in the surface — `list-nth`, `list-head`, `list-contains`, `list-append`,
`list-map`, `list-filter`, `list-fold`, `list-prepend`, `list-singleton`, `list-tail`,
`list-empty`, `list-length`, and the `list` type former. All thirteen are **T1**: they compile and
run. Exactly **one** — `list-length` — is **T2**. A postcondition about *what element*
`list-nth` returns, or *whether* `list-contains` holds, is **T3**: it falls back. The verifier can
count a list; it cannot look inside one.

That is not a bug or a missing patch. It is the boundary of the decidable core, and the next three
posts explain each piece of it.

---

## Post 3 — The one complex-data win we already have: non-recursive ADTs

It would be wrong to say LLMLL has *no* complex data verification. It has one genuine, shipped,
non-trivial win: **non-recursive algebraic data types**. This is the tier the next example
(goto-fail) will live in, so it's worth understanding well.

You declare a tagged union with `type`:

```lisp
(type Outcome
  (| Accepted int)     ;; a constructor carrying an int payload
  (| Rejected int))
```

Nullary constructors are barewords (`Red`); payload constructors are call forms (`(Accepted n)`).
The solver reasons about these through the **theory of algebraic datatypes** — decidable for the
*acyclic* (non-recursive) case by the Barrett–Shikanian–Tinelli decision procedure, and combined
with QF-LIA by *polite theory combination* (Ranise–Ringeissen–Zarba). Concretely, the solver knows:

- **constructors are injective** — `(Accepted a) = (Accepted b)` iff `a = b`;
- **distinct constructors are disjoint** — `(Accepted a) ≠ (Rejected b)` always;
- **testers and selectors** — it can case-split on which constructor a value is, and read a
  payload back out.

That is enough to prove real *discrimination and totality* properties. Here is the shipped example
`examples/outcome-totality/classify.llmll`, verbatim — it verifies **SAFE**:

```lisp
(type Outcome (| Accepted int) (| Rejected int))

(def classify [n: int] -> Outcome
  (post (and (or (not (>= n 0)) (= result (Accepted n)))     ;; legal   -> Accepted(n)
             (or (>= n 0)       (= result (Rejected n)))))    ;; illegal -> Rejected(n)
  (if (>= n 0) (Accepted n) (Rejected n)))
```

The post says *every* input maps to the *correct* payload-bearing variant, and the solver **proves
it** by constructor equality — it is not asserted. Flip the body to `(Accepted n)` unconditionally
(the shipped `classify-bad.llmll` twin) and it is **`refuted`**: the solver produces the
counterexample `n < 0`, where the body returns `Accepted` but the contract demands `Rejected`.

This capability shipped incrementally across the **COMP-4** line (v0.13.5–v0.13.9: refined
elimination per match-arm, opaque-sum elimination, and finally *native datatype construction* — the
first verification beyond pure QF-LIA) and the **PAIR-RET** line (v0.13.11–v0.13.14: `Pair2`
products, `first`/`second` as selectors, and *acyclic-tail recursion* so a pair-of-`Result` or a
nested non-recursive payload still discharges).

**The boundary within ADTs.** Payloads must be QF-LIA scalars (or other acyclic datatypes); the
strict-core discharge is defined for two-arm matches and single-constructor products; and — the
important one — **the type must be acyclic.** The moment a constructor refers to its own type, you
have left this tier (Post 5). Within those limits, though, this is a real, checkable,
counterexample-producing datatype logic — and it is exactly why goto-fail, whose natural model is a
`Verified | Rejected` outcome threaded through a pipeline, fits *today's* compiler.

---

## Post 4 — Counting without seeing: the measure catalog

So the verifier can look inside a *non-recursive tagged union*. Why not inside a *list*? Because a
list is unbounded, and reasoning about "all its elements" needs a quantifier — and quantifiers are
where decidability goes to die. LLMLL's answer is the **measure**: a way to project one *decidable
integer fact* out of an otherwise-opaque structure.

A measure is a total function `m : τ → int`. The catalog is **closed**, and contains exactly two:

```
string-length : string -> int
list-length   : list[t] -> int
```

The discipline that keeps them decidable (spec §5.3.3, the "M1–M4" rules) is the whole trick:

- **M1 — total.** Defined on every value of the type.
- **M2 — reflected as *uninterpreted*, with only a *range axiom*.** The solver learns
  `list-length xs ≥ 0` and nothing else. Its *defining equations are never unfolded* — the solver
  does **not** know `list-length (cons x xs) = 1 + list-length xs`.
- **M3/M4 — one function symbol per measure**, so the solver's congruence closure relates repeated
  occurrences (`list-length xs` is the same term everywhere it appears).

Under M2+M4 the range axiom plus congruence lands the obligation in **QF-LIA + EUF** (equality with
uninterpreted functions) — still decidable. What you get, and what you don't, follows exactly from
"non-negative integer you can do arithmetic on, defining equations hidden":

**You *can* prove** (all tested, all `verified`):

```lisp
(def head-or-zero [xs: list[int]] -> int
  (pre  (>= (list-length xs) 0))
  (post (>= result 0))                       ;; length is non-negative
  (list-length xs))

(def-shell total [xs: list[int] ys: list[int]] -> int
  (post (= result (+ (list-length xs) (list-length ys))))   ;; arithmetic over given lengths
  (+ (list-length xs) (list-length ys)))
```

**You *cannot* prove** (these fall back to `asserted`, because each needs a hidden defining
equation or a look at contents):

- `list-length (list-append xs ys) = list-length xs + list-length ys` — needs `list-append`'s
  defining equation, which M2 forbids unfolding.
- anything about `list-nth`, `list-head`, `list-contains` — those are *contents*, and no measure
  projects them to an integer fact.
- `list-length xs = 0  ⇔  xs is empty` in a way that lets you then reason about the elements — the
  measure gives you the count, never the structure.

The measures are, in the spec's phrase, a *decidable local theory extension* (in the sense of
Sofronie-Stokkermans): a carefully bounded amount of extra reasoning that provably stays inside a
decidable fragment. The catalog is closed at two precisely because each new measure is a new
opportunity to smuggle in undecidability, so extension requires a totality-and-range argument and
team consensus. This is the honest shape of "LLMLL can reason about lists": **it can count them, and
that is all.**

---

## Post 5 — The firewall: why recursive/inductive data is fenced off

Now the hard wall. You might think: fine, let me *define* my own list and reason inductively.

```lisp
(type IntList
  (| Nil)
  (| Cons int IntList))     ;; <-- self-reference
```

At the `verified` tier, **this is rejected.** The spec calls it the `admissibleDatatype`
firewall: a recursive (non-acyclic) sum's constructors are refused at the strict-core gate
(`def-shell` is required, dropping the function out of the body-faithful tier). Not because we
can't *represent* it — codegen handles it fine — but because *verifying* over it would break the
one invariant Post 1 rests on.

Why recursion is different in kind: a useful property of a recursive structure ("this list is
sorted", "this tree is balanced", "walking `.next` terminates") is a statement about *arbitrarily
many* elements. Proving it needs **induction**, and induction needs the solver to *unfold the
recursive defining equations* — exactly what M2 forbids. Once you unfold, you are doing
proof *search* over an unbounded space, the VC is no longer in a decidable fragment, and "SAFE"
stops being a decidable predicate. Theorem B's soundness argument (§3.4.5) is explicit that this is
where the clean guarantee "degrades to run-dependence." Termination itself is undecidable in
general (a `letrec` under legacy grammar can supply a `:decreases` measure, checked for
well-foundedness, but strict per-call-site descent — research item **R7** — is not yet implemented,
and under the default grammar `letrec` is rejected outright).

So the firewall is not an omission — it is the boundary being *defended*. Everything past it is a
deliberate research frontier, which is the subject of the rest of this document.

---

## Post 6 — What real data-structure bugs actually need

Before proposing extensions, make the gap concrete. Here are the data-structure bug classes a
skeptic would find convincing, and the theory each one demands:

| Bug class (famous instance) | What the proof needs | In `Σ_auto` today? |
|---|---|---|
| Array / buffer index out-of-bounds (Heartbleed *as memory*, off-by-one) | a **theory of arrays** (`select`/`store`) *or* a dependent length + an index-in-bounds refinement | **✓ (Lever A — `bytes[n]`)** |
| Hash / map correctness (get-after-put, key presence) | a **theory of arrays/maps** (extensional select/store) | **✓ (Lever A — `map[{int,string},{int,bool,string}]`)** |
| Linked-list / tree structural invariants (sortedness, balance, acyclicity, use-after-free) | **inductive datatypes + induction** over the structure | ✗ |
| Stack / queue discipline (LIFO/FIFO, non-empty pop) | inductive datatypes, *or* a bounded array model | ✗ |
| Length / counting discipline (records ≤ capacity, credit ≥ 0) | QF-LIA + the length measure | **✓ (this is what we already do)** |

The pattern, updated: rows 1–2 (array/buffer indexing and map correctness) are **now inside** the
decidable core, bought by Lever A; rows 3–4 (linked-list/tree structure, stack/queue discipline)
remain outside, awaiting Lever C. The Heartbleed example was originally convincing because we
reframed a memory bug as a **length** bug (row 5) rather than an **array-indexing** bug (row 1) —
that reframing was faithful, since the real fix *was* a length check, but it is why that example
never touched an actual buffer. Today it can: `examples/bytes-bounds/` verifies an index directly
against `select`/`store`. What still needs widening is rows 3–4 — the recursive-structure frontier
(Post 7, Lever C).

---

## Post 7 — The extension levers (the roadmap proper)

Three levers, in increasing order of power and cost. The design principle throughout: **buy exactly
as much undecidability as a bug class needs, and no more** — prefer a decidable theory extension
over an induction engine wherever the bug allows it. Lever A has shipped and is described below as
the worked case, in past tense; Levers B and C remain proposals.

### Lever A — the SMT theory of arrays (`bytes[n]`, `map[k,v]`)  · *decidable · SHIPPED v0.14.33–51*

The classical **theory of arrays** (McCarthy `select`/`store`, plus extensionality) is now a member
of `Σ_auto`, backing `bytes[n]` and `map`. The quantifier-free fragment (SMT-LIB `QF_AX` /
combinatory array logic) is **decidable** and combines with QF-LIA by the same polite-theory
machinery datatypes use — so it stayed inside the Post-1 discipline; "SAFE" remained a decidable
predicate (`LLMLL.md §5.3.3`).

- **What it delivered:** array/buffer **index-in-bounds** on `bytes[n]` (`0 ≤ i < n` as a genuine
  `select`/`store` guard — memory-safety, not a length proxy) and **map get-after-put /
  key-presence** (`select (store m k v) k = v`). `bytes-get`→`select`, `bytes-set`→`store`,
  `map-put`→paired stores, `map-empty`→const arrays; an out-of-bounds read, a read without a
  presence proof, or a dropped update in a verified function is **`refuted`**, not merely asserted.
- **Shipped vocabulary:** `bytes-get`/`bytes-set`/`bytes-length`/`bytes-zero`,
  `map-has`/`map-get`/`map-put`/`map-empty` (`LLMLL.md §13.12`), with index-in-bounds and
  key-presence as PROVE-polarity call-site obligations.
- **Where the new wall stands (the deliberate residues).** The purchase was scoped, not total: map
  **keys** are `{int, string}` and **values** are `{int, bool, string}` — a `map` at any other
  key/value sort falls back whole; **whole-structure equality** (`(= m1 m2)`, `(= b1 b2)`) never
  reflects (the encoding carries junk at absent keys, so representational `=` diverges from
  observational `=`); a direct read on a bare `(map-empty)` falls back; and `bytes[n]` length `n` is
  a **literal**, not a variable (length-polymorphism is Lever B). **Lists are not arrays** — `list`
  indexing did not ship here; that is Lever B. String *literals* reflect (equality, distinctness,
  code-point length — STRLIT), but string *structure* (concat/substr/regex) does not.

### Lever B — dependent lengths / a widened measure catalog  · *decidable · a bridge*

Extend the measure discipline (Post 4) with **length-indexed list types** (`list[t]{len = n}`) and
a small number of additional total measures, so an index refinement can be checked against a list's
own length without arrays. Stays in QF-LIA + EUF (+ arrays from Lever A). Modest on its own; its
real role is to make `list` a first-class *bounded-indexable* type once Lever A exists — the bridge
between "count a list" and "index a list safely."

### Lever C — inductive datatypes + induction  · *undecidable · the frontier*

Admit **recursive datatypes** to the verified tier and give the solver a way to reason about them:
measure **unfolding**, **Proof by Logical Evaluation (PLE)** and **refinement reflection**
(Vazou et al., *Refinement Reflection*, POPL 2018 — the Liquid Haskell lineage), and
user- or auto-supplied **induction**. This is what unlocks the full linked-list / tree / stack
correctness story (rows 3–4 of Post 6) — sortedness, balance, acyclicity.

The catch is structural, not incidental: induction is **undecidable in general**, so this work
**cannot live in `Σ_auto`** without breaking the Post-1 guarantee. It needs one of:

- a **new, weaker trust tier** for "proved by bounded/heuristic induction" (honest about its
  incompleteness — the solver may time out or fail to find the instantiation), *or*
- routing these obligations to the **Lean tier** (`verified-lean` / `DLVerifiedLean`, the
  **LEAN-GA** track; a demo slice shipped v0.14.8), where an interactive/tactic proof is
  **kernel-checked** and carries a re-checkable certificate. This keeps *independent
  checkability* even though the discharge is no longer a decidable SMT call.

Lever C is research-grade and gated on the Lean-tier production build. It is the frontier, not the
next step.

### Comparison

| | Lever A (arrays) — **shipped** | Lever B (dependent length) | Lever C (induction) |
|---|---|---|---|
| Theory | QF theory of arrays | measures + length-indexing | inductive datatypes + PLE / reflection |
| Decidable? | **yes** | **yes** | **no** (in general) |
| Stays in `Σ_auto`? | yes | yes | **no** — new tier or Lean route |
| Unlocks | index-in-bounds, map get-after-put | safe list indexing | list/tree/stack structural invariants |
| Effort / risk | **shipped (v0.14.33–51)** | low | high / research |
| Depends on | — | Lever A | LEAN-GA production build |

**Sequence: A (done) → B → (C via the Lean tier).** Lever A alone was enough to author a *convincing
data-structure example* — a verified index-bounds story on a real `bytes` buffer, and a
key-presence-gated map service — at the lowest risk and without disturbing the decidability
guarantee. Those examples now exist (`examples/bytes-bounds/`, `examples/token-revocation-emergent/`);
the near-term frontier is Lever B (safe list indexing), then Lever C.

---

## Post 8 — What we're trying to achieve, and how we'll keep it honest

**The goal, now met.** A verified example in which *the data structure is the risk itself* — a
buffer whose index must be proved in-bounds, or a map whose key must be proved present — catching a
bug that looks like correct code, within a theory the solver decides. Lever A was its enabling
purchase, and two examples realize it: `examples/bytes-bounds/` (the off-by-one and the out-of-range
write are `refuted`) and `examples/token-revocation-emergent/` (the A4 flagship — an RFC 7009/7662
token service whose reads are gated on proved key-presence). It is the data-axis sequel to the
Heartbleed length story.

**The evaluation-integrity principle** (this is a standing rule for how these examples are built and
run, not a detail of one demo):

> **The `checkout` context is the *sole* information channel to a hole-filling agent.**

When an agent fills a hole, everything it is allowed to know comes from the `checkout` instruction's
returned brief — the postcondition goal, the expected return type, the in-scope bindings, and the
contracts of callable functions — and **nothing else**. Two corollaries:

1. **We do not force a failure.** The example is not rigged so the agent *must* write the bug. It is
   given a real, fillable contract and left to solve it. If it happens to write the buggy body, the
   verifier refutes it; if it writes a correct body, that is a genuine independent solution. Either
   outcome is informative.
2. **We do not leak hints beyond the checkout brief.** No "watch out for the off-by-one," no worked
   answer, no narrowing prose in the prompt. The contract carries the whole specification; the agent
   works blind from it.

Why this matters, and why it *connects back to the extension*: this principle is only satisfiable if
the **contract alone is expressive enough** to make a data-structure hole both *fillable* (the agent
can derive a solution from it) and *checkable* (the verifier can refute a wrong one) — with no
out-of-band hinting. That is exactly what a richer data theory buys. Before Lever A, a `bytes` index
bound could not even be *stated* in a checkout brief as a checkable obligation, so a hint-free
data-structure experiment was not possible. Lever A is what made it possible — and
`examples/token-revocation-emergent/` is that experiment carried out: the token-service holes were
filled by blind agents from the checkout brief alone, and the verifier — not a scripted bug — is
what refuted the wrong fills.

**How this stays honest as a demonstration.** The compiler is the oracle. The agent is blind. A
caught bug is therefore a *real* caught bug — the solver found a counterexample to a contract the
agent was trying to satisfy — not a staged one. A passed fill is a *real* independent solution to a
stated spec. That is the difference between an experiment and a scripted demo, and it is the bar
every example built under this roadmap is held to.

---

## Epilogue — placement and next actions

- **This document** is the didactic reference. The **engineering tickets** (Levers A/B/C, with
  acceptance criteria and dependencies) live in
  [`compiler-team-roadmap.md`](../compiler-team-roadmap.md) → *Future — Data Scope Extension*.
- **The goto-fail example** (CVE-2014-1266) is deliberately scoped to non-recursive ADTs (Post 3),
  no arrays, no recursion — a control-flow example that fixes the *types / return-types /
  trivial-bodies / real-orchestration / narration* critiques of the Heartbleed example. The
  *data-structure* question it does not answer is now answered elsewhere, by the Lever-A examples
  (`examples/bytes-bounds/`, `examples/token-revocation-emergent/`).
- **The extension's first move — Lever A (theory of arrays) — has shipped** (v0.14.33–51) as the
  enabling purchase for the first data-structure examples. The remaining frontier is Lever B (safe
  list indexing), then Lever C (recursive-data induction) via the Lean tier.
