# String-Literal Distinctness — Reflecting String Literals into `Σ_auto`

> **Status:** Rev 1 — professor-reviewed, findings folded — **Stage 1 SHIPPED v0.14.44**; **Stage 2 (length-fact pinning) SHIPPED v0.14.45** (`injectStrLitLen`; see §Stage 2). The STRLIT line is complete (equality + distinctness + length); string structure remains out of scope.
> **Review:** professor review folded in-line (this cycle, 2026-07-13); dispositions in the Review-fold appendix.
> **Track:** enabler for Data Scope Extension Lever A2.2-string ([`data-scope-lever-a-arrays-proposal.md`](data-scope-lever-a-arrays-proposal.md) §3 F2 disposition — this document promotes and generalizes that deferred keys-only path); general string-surface improvement, not map-specific.
> **Author:** language-team · 2026-07-13 (Rev 0), professor fold same day (Rev 1)

---

## Restatement

Reflect string literals into the quantifier-free fragment as content-interned uninterpreted `Str`-sorted constants, accompanied by ground pairwise-distinctness facts, so that literal comparisons (`(= s "admin")`, `pre (= method "GET")`, and — once the A2.2-string value-sort thread lands — `(= (map-get m k) "admin")`) discharge body-faithfully instead of routing to Advisory. This is the general string-literal enabler; string map values (A2.2-string) and string map keys are downstream consumers that inherit it, not the scope of this document.

## Background

Today `exprToPred` (`compiler/src/LLMLL/FixpointEmit.hs:2247–2249`) reflects `LitInt` and `LitBool` but has **no `LitString` case** — a string literal falls through to `Nothing` (unreflected symbol), and the exact-reflection rule (§6.1; [`data-scope-lever-a-arrays-proposal.md:155`](data-scope-lever-a-arrays-proposal.md)) routes the whole clause to contract-only fallback. Term-vs-term string equality *does* reflect (opaque `Str`-EUF), and `string-length` reflects to the `strLen` UF; **string literals are the gap**, across the entire string surface, not just maps.

The arrays proposal §3 (F2 disposition) already specifies the distinctness mechanism for string *keys*, deferred to v1.5, with the soundness argument made (bare `Str` constants are refutation-unsound). This document promotes that path to active and generalizes it from keys-only to every literal position.

## Stage 1 — reflection + distinctness (ship now)

### Reflection rule

```
exprToPred (ELit (LitString s))  =  Just (FQApp (strlitConst s) [])
    where strlitConst s = "strlit_" <> escape s
```

`escape` is a **total function, injective into the sanitize-stable identifier alphabet `[isAlphaNum, '_']`**. Concretely (engineer's choice of form, property normative): per-code-point fixed-width hex over `[0-9a-f]`, so `escape` is injective *and* `sanitizeFQId ∘ escape = escape`. `sanitizeFQId` (`FixpointIR.hs:238`) collapses every non-`[alnum,_]` char to `_` and is itself **non-injective**, so an escape using `$`/`-`/etc. would collide post-sanitize and reintroduce the false-verify below — the encoding must therefore live entirely in `[alnum,_]`. A content **hash is prohibited**: non-injective, hence unsound. Reflection is position-independent (plain-string, map-key, map-value).

**Soundness side-condition (normative):** for any `s₁ ≠ s₂`, `strlitConst s₁ ≠ strlitConst s₂` as emitted FQ identifiers (post-sanitize). A violation makes `"s₁" = "s₂"` hold in the encoding — a **false VERIFY** (e.g. `post (= (f "s₁") (f "s₂"))` discharges though the generated program separates them). This is what makes syntactic distinctness track semantic distinctness; the distinctness facts are sound only under it.

### Distinctness facts (mandatory — the coupling)

An `injectStrLitDistinct` ground pass, mirroring the shipped `injectRangeFacts` / `injectBoolValRangeFacts` (v0.14.34/43): over the literal constants occurring in the constraint's **LHS ∪ RHS** (`FixpointEmit.hs:3362` — the union is required; a goal-only literal must still receive distinctness against a hypothesis literal), conjoin `c_i ≠ c_j` into the LHS for every unordered pair of **distinct** constants. Literal/variable and literal/non-literal-term pairs get **no** fact (a variable may equal any literal — a genuine model; arrays §87(iii)). Constants declared in the preamble via `FQConstant` (`constant strlit_… : (func(0 , [Str]))`), scoped to occurring literals (byte-inert otherwise).

**Atomicity:** the `LitString` reflection flip and the distinctness pass are **one change**. The flip alone is sound for SAFE but UNSAFE-unsound (arrays §155 F2 — the `"a"="b"` model spuriously refutes); the distinctness pass restores exactness.

### Ships vs enables
- **Ships:** plain-string literal contracts (`(= method "GET")`, `(= result "ok")`, string-tag patterns) — no sort threading.
- **Enables:** A2.2-string map values and string map keys inherit literal reflection once their respective sort-threading / key-gate work lands.

## Stage 2 — literal-length pinning (SHIPPED v0.14.45)

> **SHIPPED v0.14.45** as `injectStrLitLen` (a per-constraint pass sibling to `injectStrLitDistinct`, composed at the `addConst` choke point). `|s|` is recovered exactly from the interned name via `strlitLen` (`(len − |"strlit_"|) / 6`, since `strlitConst` emits fixed-width 6-hex per code point), so no re-decoding is needed. `strLen : (Str) → int` auto-declares because the injected application reaches the preamble sweep. Sound by construction: the ground equations are true and mutually consistent, so they only strengthen the hypothesis. The code-point regression below is the shipped acceptance gate (STRLIT-9); the length crux (STRLIT-8) is the load-bearing end-to-end check.

Add `strLen(strlitConst s) = |s|` per occurring literal constant, composing with the existing `string-length → strLen` reflection so length-consistency reasoning discharges (`s = "admin" ∧ strLen(s) = 3` → refute; and the value-domain length case for A2.2-string map values).

**The convention is resolved (professor finding 2, closed 2026-07-13):** `|s| := T.length s` — the **code-point count**. This matches the runtime `string_length = length :: String -> Int` (`CodegenHs.hs:302–303`) exactly: `emitLit (LitString s) = show (T.unpack s)` (`CodegenHs.hs:799`) emits the literal as a Haskell `String` with the AST literal's code points, and `T.length ≡ length (T.unpack s) ≡ runtime string_length` (all code points; `Data.Text.length` decodes astral-plane characters to a count of 1). **Forbidden:** a UTF-8 byte count (`BS.length . encodeUtf8`) or a UTF-16 word count — either makes `"😀"` reflect as length 4 or 2, disagreeing with the runtime's 1 (a §5.3.4 claim-accuracy break).

**Stage-2 acceptance gate:** a non-ASCII length regression — `"admin"`→5, `"😀"` (U+1F600)→**1**, `"e\x0301"` (e + combining acute)→**2**, `"é"` (U+00E9 precomposed)→**1** — locks the code-point convention against a units/bytes mistake.

Stage 2 is ~0.5 day riding on Stage 1's infrastructure (one extra conjunct per literal in the `injectStrLitDistinct` pass). It ships behind the code-point convention above; distinctness (Stage 1) is unaffected by it.

## Edge cases and degenerate inputs

1. **Positive witness (verifies where it degraded).** `def route [method: string] -> int (pre (= method "GET")) (post (= result 1)) (if (= method "GET") 1 0)` → `method = strlit_47_45_54`, body-faithful VC discharges → **verified** (was Advisory). Channel: contract → trust.
2. **Injectivity witness (the false-verify the side-condition forbids).** Content `"a-b"` vs `"a_b"`: a naive `-→_` escape maps both to `strlit_a_b`; the mandated hex encoding keeps them distinct, so `(= (f "a-b") (f "a_b"))` correctly does **not** verify. Channel: contract (soundness side-condition); a collision-avoidance regression. Cite: `FixpointIR.hs:238`.
3. **Distinctness refutation.** `(= (map-get (map-put (map-put m "a" 1) "b" 2) "a") 1)` → `strlit_a ≠ strlit_b` excludes the identifying model → **SAFE** (was spuriously UNSAFE). Channel: contract. Cite: arrays §85.
4. **Literal/variable no-fact.** `pre (= s t)`, body uses `"admin"`: no `strlit_admin ≠ t`; `s ≠ "admin"` stays unprovable given `s = t`. Channel: contract (intentional incompleteness). Cite: arrays §87(iii).
5. **Length-uniqueness completeness gap (Stage 2).** `post (=> (= (string-length s) 0) (= s ""))` is QF_S-valid but **not** EUF-valid (uninterpreted `strLen` admits a length-0 junk element ≠ `strlit_empty`). Sound, incomplete. Channel: trust (documented Advisory). Reactive recovery only: a single conditional ground fact `strLen(x)=0 ⟹ x = strlit_empty` emitted when both `strlit_empty` and a `strLen(_)=0` atom occur.
6. **Duplicate literal.** `(and (= a "x") (= b "x"))` → both intern to `strlit_x`, `a = b` discharges; no `c ≠ c`. Channel: contract.

## Verification mapping

- **Reflection + distinctness (Stage 1)** — Channel: contract; **Fragment: (a) QF-LIA-adjacent, auto-discharged.** QF_EUF (equality/distinctness of `Str` constants and terms) polite-combined with QF-LIA and QF_AX; distinctness is **ground per occurring pair** (no quantifier). Stays in `Σ_auto`, decidable (`LLMLL.md §5.3.3`).
- **Per-VC scope sufficiency (professor Q1, confirmed).** A disequality alters `H ⊨ G` only if both constants occur in `H ∪ {G}` (fresh-constant conservativity); under assume-guarantee a callee literal reaches the caller via contract substitution and thereby occurs. Sound **provided the collector unions LHS ∪ RHS** — inherited from `injectRangeFacts`.
- **EUF sound w.r.t. QF_S (professor Q2, confirmed).** Every QF_S model is an EUF+facts model, so EUF+facts-valid ⟹ QF_S-valid — sound in the verification direction. Completeness gap = length-uniqueness (edge 5), documented, not chased.
- **Length family (Stage 2)** — Channel: contract; **Fragment: (a) QF-LIA**, ground `strLen(c_s) = |s|`. Sound only under the code-point convention (§Stage 2).
- **Classification** follows by construction: `isQfLia = isJust . exprToPred` (CLASSIFY-MEASURE, v0.14.40) reclassifies string-literal contracts once the `LitString` case flips — this is also the blast radius (Risk 1).

**Non-goal (principled boundary):** string **structure** — `str.++`, `str.substr`, `str.at`, `str.contains`, regex, interpreted `str.len` — is out. Word equations alone are decidable (Makanin 1977), but **word equations + length constraints is a long-standing open problem** (Ganesh et al., HVC 2012) and adding regex/replace is undecidable. The equality-plus-pinned-length fragment sits on the decidable side by construction; structure is a separate lever (fragment restriction or Lean tier).

## Affected surface

- `compiler/src/LLMLL/FixpointEmit.hs` — the `LitString` reflection flip; `injectStrLitDistinct` ground pass (LHS ∪ RHS occurring-set, distinct-literal pairs only); preamble constant declaration; (Stage 2) the length-fact pass.
- `compiler/src/LLMLL/FixpointIR.hs` — the `escape` encoding (injective into `[alnum,_]`); no `sanitizeFQId` change (its non-injectivity is *why* the encoding is constrained).
- `ObligationMining.hs` / `ObligationAssembly.hs` — no direct edit (classifier follows via `isQfLia`); **`examples/` before/after verdict inventory is the acceptance gate**.
- Docs (post-ship, doc-lead): arrays proposal §3 F2 promoted/generalized; `LLMLL.md §5.3.3/§13` reflected-fragment note; roadmap row (Stage 1 shipped, Stage 2 next).
- **Schema:** none. **Surface syntax:** none. **Freeze:** N/A.

## Risks and open questions

1. **Blast-radius verdict flips.** *Verification-ergonomics.* Reflecting literals reclassifies every string-literal contract (ENUM-EQ-FALLBACK-class). A new **refute** is the dangerous direction — triage first against the injectivity side-condition (edge 2), then as a possible latent spec bug. **Bite: gates Stage 1** — the `examples/` before/after verdict inventory (arrays §10 discipline, `make refute-crux-gate`) is the required artifact.
2. **Injectivity side-condition.** *Soundness.* `FixpointIR.hs:238`. A non-injective `escape` (hash, or a `sanitizeFQId`-colliding escape) reintroduces a false verify. **Bite: none if the hex-into-`[alnum,_]` encoding is used and collision-tested; a blocking soundness gate if skipped.**
3. **Length convention (Stage-2 gate).** *Spec-drift / soundness-w.r.t.-runtime.* `CodegenHs.hs:302–303`. **Bite: complicates the deferred length family only;** distinctness unaffected. Resolved (§Stage 2); decoupled by staging.
4. **Length-uniqueness incompleteness.** *Verification-ergonomics.* Edge 5. **Bite: only at scale;** documented; reactive recovery specified.
5. **Pinned-fixpoint acceptance of `Str` constants + `≠`.** *Decidability (feasibility).* The p5/p9 precedent shows monomorphic quirks. Nullary `Str` `constant` declarations and `Str`-vs-`Str` `≠` are probe-unverified. **Bite: a one-hour engineer probe (the p1–p9 method) resolves it before build.** The `strLen : [Str] → int` constant precedent and probe p9 (Str equality) strongly suggest they work.

## Review-fold appendix — professor review (2026-07-13)

Five findings, all folded into Rev 1:
- **F1 (BLOCKING, soundness):** `canonicalize` must be provably injective — a hash is a false-verify hazard (literal collision → spurious identification). → Reflection rule now mandates a lossless injective escape into `[alnum,_]`; sharpened with the `sanitizeFQId` non-injectivity finding.
- **F2 (soundness-w.r.t.-runtime):** length convention is code points; must match `CodegenHs.hs:302–303` and be non-ASCII-tested. → §Stage 2 pins `|s| = T.length s` with the astral/combining regression; length family staged second.
- **F3 (confirmed, Q1):** per-VC occurring-set distinctness is sufficient, via fresh-constant conservativity; caveat LHS ∪ RHS collection. → Folded into Verification mapping.
- **F4 (confirmed, Q2):** EUF+facts is sound w.r.t. QF_S; completeness gap = length-uniqueness. → Folded (edge 5); QF_S not adopted.
- **F5 (scope):** the structure firewall lands exactly on the decidability boundary (Makanin 1977; word-equations+length open). → Non-goal cites it.

Recommendation: proceed, F1 blocking, two-stage ship. No open questions returned to the professor.
