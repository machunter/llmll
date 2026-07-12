---
name: match-widen-stretch-plan
title: "MATCH-WIDEN STRETCH — scrutinee-constructor posts via int-tag discrimination"
status: "Design / de-risking plan — no implementation"
date: 2026-07-06
author: compiler-engineer
---

# MATCH-WIDEN STRETCH — making scrutinee-constructor posts discharge

## Problem

A body-VC over a two-arm sum match discriminates the arms with a **fresh, unconstrained boolean
guard** (`_match_success`, declared `FQTrue`; `FixpointEmit.hs:1814,1830,1833`) — the
opaque-sum-elimination encoding. Both arms are checked, but the scrutinee's *constructor* is never
materialized as a sortable term, so a post that references it (`(= sig Continue)` over `sig : Step`)
leaves `sig` free → liquid-fixpoint crashes (`Constraint with free vars [sig]`). The v0.14.12 FLOOR
(`clauseOverOpaqueSumParam`, `FixpointEmit.hs:851`) guards this by falling back to contract-only; the
STRETCH is to make such posts **discharge** so the goto-fail pipeline verifies.

## The key finding: int-tag discrimination is a *conservative extension*, not a risky rewrite

Read `FixpointEmit.hs:1826–1837`. A `BranchVC` on the free boolean `guardVar` (unconstrained) forces
the solver to satisfy **both** arms unconditionally (`svc ∧ evc`) — there is no information tying an
arm to the scrutinee. Replace the free boolean with a **tag equality** on a free integer tag:
`BranchVC (= sig_tag 0) …`, with `sig_tag : FQInt` free. The VC becomes
`(sig_tag = 0 ⇒ svc) ∧ (sig_tag ≠ 0 ⇒ evc)`.

- **On every *existing* match, this is equivalent.** Existing arm bodies/posts do not mention the
  scrutinee's tag, so the extra hypothesis `sig_tag = 0` (resp. `≠ 0`) is irrelevant to `svc`/`evc` —
  `svc` under `sig_tag=0` ≡ `svc` unconditional. Same discharge, same refutation (a true tag fact
  cannot excuse a body that violates its post). This is the load-bearing de-risking argument: the
  change is **equivalent on the entire existing corpus** (settle, safe-withdraw, classify,
  withdraw-outcome, all COMP-4/Result matches) and strictly stronger *only* where a post references
  the scrutinee's constructor.
- **On the new case it discharges.** The goto-fail pipeline post `result=Verified ⇒ sig=Continue`
  desugars to `result=Verified ⇒ sig_tag=0`; in the `sig_tag=0` arm it holds, in the `sig_tag≠0` arm
  it is vacuous (result≠Verified). The skip twin (return `Verified` when `sig_tag≠0`) refutes.

This dissolves the "cross-cutting regression risk" that made the earlier one-shot attempt unsafe: the
rewrite is uniform (one path) *because* it is semantically conservative, not despite touching every
match.

## Recommendation: **full rewrite to tag-discrimination via int-tag** (not per-match dual, not testers)

1. **Full rewrite, not per-match dual.** The per-match dual (switch only matches whose post
   references the scrutinee's constructor) was motivated by regression fear; the equivalence argument
   removes that fear, and the dual costs a fragile "does the post reference the scrutinee constructor"
   emit-time detector plus two coexisting encodings that must compose under nesting. Reject it.
2. **Int-tag, not datatype testers.** The existing all-nullary int-tag path (`buildChain`,
   `FixpointEmit.hs:1173–1177`, emits `EOp "=" [scr, tagLit c]`) confirms int-tag equality sorts in
   pure **QF-LIA** — no liquid-fixpoint datatype-theory / `is-C` tester machinery needed. The R1
   spike was right that testers are unneeded; it was wrong only that the *discharge* case is the whole
   story. Int-tag keeps the STRETCH inside QF-LIA.
3. **Payload unchanged.** Only the guard changes (free bool → `(= tag k)`). The payload skolems
   (`successRenamed : okSort`, `FQTrue`; `:1818,1830`) and the `<v>$<Ctor>` seeding
   (`adtKeys`/`adtRefs`, `:629`) are untouched, so COMP-4(b) refined-payload consumption is preserved.

## Mechanism (three emit-time changes)

- **Seed the scrutinee tag.** For a matched sum var `sig : Step`, seed `sig$tag : FQInt` in the
  SortEnv (mirroring the `sig$Ctor` payload seeding), plus a range fact `(or (= sig$tag 0)
  (= sig$tag 1))` so the free int is confined to valid constructors (a two-arm exhaustive match's
  else-arm is `¬(tag=0)`; the range fact keeps `¬(tag=0)` ≡ `tag=1` rather than any int).
- **Discriminate on the tag.** In the two-arm-ADT / Result branch (`buildOpaqueSumBranch` / `:1791`),
  build `BranchVC (FQApp "=" [FQVar sig$tag, tagLit k1]) …` instead of the fresh boolean.
  `tagLit k` reuses the nullary-enum tag numbering (`buildCtorTagMap`).
- **Desugar scrutinee-constructor references.** A clause `(= sig Continue)` (bare sum var `=` bare
  nullary ctor) rewrites to `(= sig$tag <k_Continue>)`. This is the one genuinely new bit and the main
  residual unknown (below): the existing `desugarCtorValues` (`:475`) already lowers a bare nullary
  ctor to its tag literal, but the *scrutinee variable* `sig` must be rewritten to `sig$tag` — a
  var→tagvar substitution keyed on "this var is a matched sum scrutinee." With the tag seeded, the
  `clauseOverOpaqueSumParam` FLOOR guard (`:851`) is then narrowed/removed for the seeded case (it
  fires only when the sum var is *unsorted*, which after seeding it no longer is).

## Staged, incrementally-de-riskable build order

Each stage ends with a **full `cabal test` (must stay 1064/0)** so a regression is caught at that
stage, not at the end. The equivalence argument predicts stages 1–2 are green with *zero* example
changes — if any example flips, the equivalence assumption is violated and the stage stops.

| Stage | Change | Verify (gate) | Effort |
|---|---|---|---|
| **S0** | Seed `sig$tag` + range fact; keep the *boolean* guard (tag unused yet) | 1064/0 unchanged; nothing discharges differently | **S** |
| **S1** | Result path (`:1791`) → tag guard | settle / safe-withdraw / withdraw-outcome + their `-bad` twins **unchanged** (SAFE / refuted); 1064/0 | **S–M** |
| **S2** | Two-arm user-ADT path (`:1777`) → tag guard | classify / outcome-totality + `-bad` twins unchanged; 1064/0 | **S** |
| **S3** | Scrutinee-constructor desugar (`sig=Continue`→`sig$tag=k`); narrow the FLOOR guard | goto-fail **pipeline verifies body-faithful**; skip twin **refutes**; discharge case still faithful; 1064/0 | **M** |
| **S4** | Sequential (Slice 2) + nested (Slice 3) case-tree composition under tag guards | two-match + 3-deep pipeline verify; mid-pipeline skip refutes; 1064/0 | **M** |

Total **M** (a touch more than the R1 spike's mis-scoped "M, no unknown", but now genuinely
de-risked). S1–S2 are the "prove the equivalence empirically" stages — cheap and decisive.

## Regression surface + how it is guarded

The blast radius is *every two-arm sum match*, but the equivalence argument bounds the *behavioral*
change to zero on that surface. The guard is the staged suite runs (S1/S2 are pure regression gates
that must show no example flips). The specific things to watch:
- **Refutation preservation** — a `-bad` twin that previously refuted must still refute (the tag
  cannot launder a violating arm). S1/S2 twins are the check.
- **Nested/sequential composition (S4)** — the tag guards must thread first-match `¬prior` exactly as
  the boolean guards did; reuse the existing `BranchVC` nesting, only the guard predicate changes.

## Residual unknowns (need a small spike, not a redesign)

1. **The scrutinee var→tagvar desugar (S3).** Detecting "`sig` in a post is a matched sum scrutinee"
   and rewriting `sig`→`sig$tag` at the right point (post translation, after payload seeding). Likely
   a targeted case in the post/pre desugar keyed on the seeded `sig$tag` presence. This is the one
   step that could reveal a wrinkle (e.g. a post mentioning `sig` in a non-`=Ctor` position).
2. **DIP stage-3 interaction (cross-proposal, likely a *win*).** The free `_match_success` boolean is
   a *branch skolem*; `differential-implementation-pressure-proposal.md:36` gates R5 stage-3 on
   branch-skolem-free bodies. Replacing it with a tag equality on a seeded var **removes** a branch
   skolem, so more MATCH bodies become stage-3-eligible — a coverage *increase* for R5, not a
   regression. Confirm `collectBranchBinders` no longer flags the tag guard; update the DIP
   cross-reference.
3. **Tag range for ≥3-arm all-nullary enums** is out of scope (this STRETCH is two-arm sums); confirm
   the range-fact seeding does not perturb the existing `buildChain` all-nullary path (it should be
   independent — different code path).

## What stays out
Recursive/non-admissible sums (firewall, unchanged). `>2`-arm mixed matches (two-arm is the STRETCH
scope). Datatype-theory testers (int-tag suffices). No JSON-AST schema change (EMatch node unchanged).
