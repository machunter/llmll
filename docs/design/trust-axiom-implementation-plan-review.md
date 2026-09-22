# Professor review: TRUST-AXIOM implementation plan

> Reviews [`trust-axiom-implementation-plan.md`](trust-axiom-implementation-plan.md)
> (Rev 1 plus the Rev 2 implementation findings), and the branch
> `trust-axiom/builtin-axiom-disclosure` at the review-ready state.
> Standalone. Not folded into the proposal.

---

## Restatement

The plan adds a per-function disclosure row naming each sealed-builtin axiom
that a body VC assumed. The rows come from the emitted `BodyVC`. The engineer
asks whether the sidecar-only report path must also carry them.

---

## Context located

1. [`trust-axiom-implementation-plan.md`](trust-axiom-implementation-plan.md)
   §(b), §(d), and Rev 2 item 3: the routed question.
2. `LLMLL.md` §5.4: the anti-laundering invariant is about a RECORD's internal
   coherence. It does not require a positive tier to name its assumed axioms.
   The gap below is therefore not a §5.4 violation; it is the same silence one
   level up.
3. `LLMLL.TrustReport`, `refutedClosure`: its comment states the governing
   principle. The transitive closure is taken "because assume-guarantee
   composition (LLMLL.md §0.1) makes a caller of a refuted callee unsound".
4. `LLMLL.TrustReport`, `markCallerObligations` and the `teCallerObligations`
   comment: a SECOND transitive-propagation precedent, for an escaped callee
   obligation.
5. `LLMLL.FixpointEmit`, `collectBuiltinAxioms` on the branch: it walks one
   function's own `BodyVC` and filters on `sealedAxiomBuiltins`. A user
   function's `CallVC` is excluded by construction.
6. Coq Reference Manual, `Print Assumptions`; Lean 4 `#print axioms`. Both
   compute the axiom set of a result TRANSITIVELY, over the kernel-checked
   term.
7. Wenzel, *The Isabelle/Isar Implementation*, on oracles (`Thm.oracle`,
   `Thm.peek_status`). An oracle tag propagates to every theorem derived from a
   tagged one.
8. Leroy, "Formal verification of a realistic compiler", CACM 2009. The
   distinction that decides §(d).
9. Vazou et al., ICFP 2014 (`assume`); F\* `assume val`; Dafny `{:axiom}`.
   Already cited in the roadmap's RESP-FACT-1 row. Named here to record
   convergence, not novelty.

---

## Gaps and hazards

### 1. The disclosure does not propagate to callers, and it is destroyed at the module boundary

**Classify: disclosure-completeness. This is the row's own defect class,
reappearing one level up.**

I constructed the witness rather than inferring it. Two modules:

```lisp
;; buf.llmll
(export make-buffer)
(def make-buffer [] -> bytes[32]
  (post (= (bytes-length result) 32))
  (bytes-zero))

;; use.llmll
(import buf)
(open buf)
(def use-buffer [] -> int
  (post (= result 32))
  (bytes-length (make-buffer)))
```

Measured with the branch binary under `verify --trust-report --strict-verify`:

| report | `assumes` lines |
|---|---|
| `buf.llmll` alone | 1, naming `bytes-zero` and `(bytesLen result) = 32` |
| `use.llmll` | **0** |

In the caller's report BOTH entries are silent. `use-buffer` is `verified`, and
so is the `buf.make-buffer` entry beside it. The whole of `use-buffer`'s post
is discharged from `make-buffer`'s post, and that post rests entirely on the
constructor axiom. The reader of `use.llmll` sees two `verified` tiers and no
axiom anywhere.

The cause is structural, not a wiring defect. `collectBuiltinAxioms` reads the
`BodyVC` of the function being emitted. The caller's run never emits the
callee's body VC, so the caller's run never sees the callee's axioms. A
cross-module callee entry is built from the persisted contract, which carries
no axiom set.

**The bite: this affects the row's closure claim, not its correctness.** No
verdict is wrong. But TRUST-AXIOM was opened because "a reader cannot tell from
any output that the tier has a trust-channel dependency". After this patch a
reader of a one-function module can tell. A reader of any caller still cannot.
The population that matters most, composed programs, is the population still
silent.

**The established treatment propagates, and both systems that implement it do
so transitively.** Coq's `Print Assumptions` and Lean's `#print axioms` walk
the dependency graph of the checked term and report every axiom reached, not
only the ones used at the top level. Isabelle goes further and makes
propagation automatic: an oracle tag attached by `Thm.oracle` is carried in the
derivation, so any theorem derived from a tagged theorem is itself tagged.
LLMLL already applies exactly this reasoning to a different property:
`refutedClosure` propagates refutation to transitive callers, and its comment
gives the assume-guarantee argument that applies here word for word.

### 2. The sidecar question is not a scope choice. Finding 1 forces persistence

**Classify: scope, resolved by Finding 1.**

The engineer frames the sidecar path as an optional second landing, and
recommends "accept for this landing and file the sidecar half as a follow-on".
That framing is wrong, for a mechanical reason.

The caller's run cannot recompute the callee's axioms. It does not emit the
callee's body. So the ONLY place the caller can read them from is the callee's
persisted record. Persisting the rows into `.verified.json` is therefore not a
nicety for a second report path; it is the mechanism that fixes Finding 1.
Deciding the sidecar question separately from the propagation question will
produce two designs where one is needed.

This matches the external treatment precisely. `Print Assumptions` does not
re-run elaboration. It reads the stored, kernel-checked term. The persisted
artifact is the PRIMARY source of the axiom set in Coq and Lean, not a
degraded copy of it. The engineer's Rev 2 item 3 treats the sidecar path as
inherently second-class ("the sidecar path genuinely does not know what the
body VC assumed"). That is true of today's sidecar, and it is a property of the
sidecar's current contents, not a necessary one.

### 3. Rows multiply per occurrence, with no deduplication

**Classify: ergonomic.**

Measured on a three-read body:

```lisp
(def sum3 [b: bytes[8]] -> int
  (post (>= result 0))
  (+ (+ (bytes-get b 0) (bytes-get b 1)) (bytes-get b 2)))
```

The report prints three rows. They differ only in the index literal, and all
three assert the same thing: `bytes-get` reflects to `Map_select`. Rev 1's risk
2 predicted this and proposed deduplication per `(def, builtin)`. The
implementation did not apply it.

**The bite: it complicates reading, and it will get worse.** A realistic buffer
loop produces a row per unrolled read. The signal a reader needs is the SET of
sealed builtins the evidence rests on, which is small and bounded by
`sealedAxiomBuiltins`. The per-occurrence index is noise at the disclosure
layer. Coq reports an axiom once, not once per use site.

### 4. Family B and family A are merged in one field, and a reader cannot separate them

**Classify: ergonomic, with a mild disclosure consequence.**

`baPredicate` carries the whole assumed post. For `bytes-set` that is the
reflection conjunct AND the length-preservation axiom, joined by `&&`. The two
have different characters. The reflection conjunct defines the encoding. The
length conjunct is a substantive lemma about the operation.

Rev 1 §(c) argued correctly that both rest on the same trust channel and both
belong. I agree. But merging them into one rendered string means a reader
cannot tell which part is the definition and which is the lemma. The negative
control in Rev 2 is the proof that the distinction is real: deleting the length
conjunct flipped the verdict, and deleting the reflection conjunct would not
have the same character.

### 5. `--strict-verified-core`: the engineer's conclusion is right, and one argument in it is weaker than stated

**Classify: scope. No change recommended for this landing.**

I agree with disclosure-only. The engineer's decisive argument is correct: if
an axiom taint gated admission, consistency would force tainting every
`Map_select` reflection, which would empty the array class. That argument
holds.

The INT-1 comparison is also right, and CACM 2009 sharpens why. `erOverflowTainted`
marks a gap where the fact can be false while every component behaves as
specified: the Int64 semantics genuinely differ from the mathematical integers
the VC reasons about. The bytes axioms are false only if codegen does not
implement the semantics it claims. Leroy's distinction is exactly this: a
verified compiler turns codegen faithfulness into a theorem, and an unverified
one leaves it an assumption of the whole pipeline. LLMLL is in the second case
and `codegen_semantics_version` is the honest name for that assumption. Tainting
on it would taint every generated program uniformly, which discloses nothing.

**Where the engineer's reasoning is weaker than stated:** the argument from the
`[CT]` tag with no `[SPEC]` is not evidence. The roadmap tag records what the
author expected the work to touch. It cannot settle whether the work SHOULD
touch the spec. The engineer already ranked it last and called it weakest; I
would drop it entirely rather than rank it.

---

## Recommendation

**Do not close TRUST-AXIOM on this landing. Land the patch, and treat
propagation as the row's remaining half rather than as a follow-on row.**

Ranked:

1. **Persist the axiom rows into `.verified.json`, then propagate them
   transitively.** This fixes Findings 1 and 2 together, and it is the
   established design. The callee's record carries its axiom set; the caller's
   report unions the sets of its transitive callees, exactly as `refutedClosure`
   unions refutation and as `markCallerObligations` escapes obligations. The
   propagated rows should be visually distinct from a function's own rows, on
   the `depends-on-refuted` precedent, so a reader can tell "this function uses
   `bytes-zero`" from "this function trusts a callee that does".

2. **Deduplicate to the set, not the occurrence list.** Report each
   `(def, builtin)` once. If the predicate must be kept, keep one
   representative and drop the index literal, or record the occurrence count
   separately. This is Finding 3 and Rev 1's own risk 2.

3. **Split the predicate field, or tag each conjunct.** Distinguish the
   reflection conjunct from the substantive lemma. This is the smallest
   principled fix for Finding 4 and it can wait for the propagation work.

**On the evidence-hash question that persistence raises.** Adding an axiom set
to `.verified.json` is additive data about a body that the hash already covers.
It does not need a `checker_soundness_version` change. It DOES need the axiom
set to be recomputed whenever the body is, which
`downgradeStaleVerifiedSidecar` already enforces by dropping body-faithful
evidence on hash drift. A stale axiom set cannot survive a body edit, because
the evidence it rides is dropped first.

**The principled future move for `--strict-verified-core`, when propagation
exists.** Do not taint. Instead, make the propagated axiom set a checkable
quantity against a declared allowlist. This is what mathlib's CI does with
Lean's axiom mechanism: it does not forbid axioms, it checks that a result
depends only on the expected ones and flags `sorryAx`. The LLMLL analogue is a
flag that admits a function whose transitive axiom set is a subset of the
sealed-builtin table, and refuses one that has acquired an axiom from anywhere
else. That is a real gate, it costs the array class nothing, and it becomes
expressible only after Recommendation 1 lands.

---

## Open questions for the language-team

1. **Does a propagated axiom row belong on the trust report only, or does it
   also belong in the proof artifact's determinism-pin block?** `LLMLL.md` §5.4
   says the artifact already consolidates the trust report and the
   `codegen_semantics_version` stamp. If the axiom set is the enumerated
   content of that stamp, then the artifact is arguably its natural home, and
   the trust report shows a view of it. Settle which artifact owns the set
   before the engineer plumbs it twice.

2. **Is `sealedAxiomBuiltins` a closed set the spec should name, or an
   implementation detail?** Recommendation 3's future gate needs the set to be
   declared somewhere a reader can audit, which argues for `LLMLL.md` §13.12.
   The current branch defines it in `LLMLL.FixpointEmit` with a comment saying
   one site is deliberate. That is right for the implementation and may be
   wrong for the spec.
