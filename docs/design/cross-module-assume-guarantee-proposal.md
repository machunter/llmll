---
name: cross-module-assume-guarantee
title: "Body-faithful cross-module assume-guarantee"
status: "Design (Rev 1) — settled, professor-reviewed, ready for compiler-engineer"
date: 2026-07-08
author: language-team
consumers: [compiler-engineer, documentation-lead]
---

# Body-faithful cross-module assume-guarantee

## Summary

A function whose callee is **imported** falls back to contract-only verification
(`erBodyFallback`), losing the `verified` tier, while the identical call to a same-file
callee stays body-faithful. This is a plumbing gap, not a designed boundary: the imported
contracts exist in the right shape (`ModuleEnv.meContracts`) and are used for type-checking,
but are never handed to the body-VC emitter. This proposal threads them into the body-VC's
`ContractEnv`, so a cross-module caller verifies body-faithful against the imported callee's
**contract** — the same assume-guarantee VC as intra-module — with the trust tier riding the
evidence meet rather than collapsing to fallback.

**Consequence:** a program can be split into real `(import)`-linked modules **and** stay
`verified`. This is the prerequisite for a modular flagship — today the 163-function
secure-channel is concatenated into one file precisely because splitting it downgrades every
cross-module composer from `verified` to `asserted` and breaks `--strict-verified-core`.

## Background — the finding (spike, v0.14.16)

- The **identical** `deliver-plaintext` (slice-gate) is `body-faithful` in one file but
  `body-fallback` when its gate callees are imported from a `record` module.
- Minimal: `(def-shell use-double [x:int]->int (pre (>= x 0)) (post (= result (+ x x))) (double x))`
  with a same-file `double` → body-faithful; with `(import lib)(open lib)` and `double` in
  `lib.llmll` → **body-fallback**.
- `--strict-verified-core` **passes** the concatenated 163-fn flagship (163/163 body-faithful,
  0 fallbacks) but **hard-errors** the module-split version ("1 function fell back from
  body-faithful verification").

**Root cause (traced):** `emitFixpointWith :: EmitOptions -> FilePath -> [Statement] -> IO
EmitResult` receives only the entry file's statements (`Main.hs` `doVerify`, ~:1198 —
`emitFixpointWith … fp stmts`). The imported contracts live in the module cache (`_cache`,
used for type-checking via `typeCheckStrictWithCacheAndStatus`) but the `_cache` is dropped
for verification. `buildContractEnv stmts` (`FixpointEmit.hs:187`) therefore builds `cenv`
from same-file defs only; the assume-guarantee path fires only when `fname ∈ cenv`
(`FixpointEmit.hs:1612`), so an imported callee misses and the caller falls back. No
`LLMLL.md` clause states cross-module = contract-only — **spec/code drift**: §5.3.4's
assume-guarantee discipline is written module-agnostically and already *implies* cross-module
should be body-faithful.

## Design proposal

Seed the body-VC's `ContractEnv` with the imported modules' `meContracts` before emitting the
caller's VC. Three coordinated changes (the engineer pins the plumbing):

1. **Thread the imported `ContractEnv` to the emitter.** `emitFixpointWith` gains an
   imported-contract input (or `doVerify` unions `_cache`'s `meContracts` into the
   statement-derived `cenv`). Imported functions are keyed under **both** their opened name
   (`double`, after `(open lib)`) and their qualified name (`lib.double`), matching call-site
   resolution.

2. **Assume-guarantee across the boundary; do not re-verify imported bodies.** With the callee
   in `cenv`, `bodyToPredM (EApp fname args)` (`FixpointEmit.hs:1612`) discharges exactly as
   intra-module: prove the callee's `pre` at the call site, assume its `post`. The imported
   callee's **body VC is not re-emitted** — the caller is proved against the imported
   *contract*, not its *body*, so changing `lib`'s implementation re-verifies only `lib`. This
   is the modular-verification win.

3. **Separate body-faithfulness from tier.** Today `erBodyFallback` conflates "cannot prove
   the body" with "the callee is only `asserted`." Split them: a cross-module caller is
   **body-faithful** whenever its body discharges against the imported contracts (it now
   does); its **tier** rides the §5.3.4 evidence meet against the callee's tier. Caller of an
   imported `verified` fn → `verified`; caller of an imported `asserted`/`tested` fn →
   body-faithful but tier-`asserted`, surfaced by the existing downstream-trust warning.
   `--strict-verified-core`'s `erBodyFallback` conjunct (§5.3.5) then fires only on genuine
   fallbacks, not on module boundaries.

No surface or schema change — `import`/`open`/qualified calls already parse and type-check.
This completes verification plumbing only.

## Acceptance criteria

- **(A1) Positive witness → body-faithful + verified.** The `use-double` witness above
  verifies `body-faithful` and tier `verified` (today: `body-fallback`).
- **(A2) Tier meet across the boundary.** A caller of an imported `asserted`/`tested` function
  is body-faithful but tier-`asserted` (the meet), with the downstream-trust warning — **not**
  a body fallback and **not** `verified`. (Witnesses A1 vs A2 are the gate.)
- **(A3) BLOCKING — cross-module staleness validation (professor finding, elevated).** At
  import, the imported module's `.verified.json` sidecar tier is validated against the imported
  module's **current source hash**; a stale imported `verified` is downgraded before the
  importer's meet consumes it. `downgradeStaleVerifiedSidecar` must extend transitively across
  imports. **This ships in the same change, not as a follow-on** — the proposal's value is
  letting a caller reach `verified` on an imported `verified`, which is unsound if the import's
  sidecar can be stale. (See Soundness §3 and Open questions.)
- **(A4) Regression.** Same-file verdicts unchanged; the concatenated flagship still 163/163
  body-faithful; module import cycles still rejected.

## Edge cases

1. **Cross-module call to `verified`** — body-faithful + `verified` (A1). *Channel:* contract,
   QF-LIA. *Cite:* `FixpointEmit.hs:1612` once the callee is in `cenv`.
2. **Cross-module call to `asserted`** — body-faithful, tier `asserted` (A2), not fallback.
   *Channel:* trust (§5.3.4 meet).
3. **Module import cycle A↔B** — already a hard compile error (`Module.hs:147`), so
   cross-module AG never faces a cyclic module graph. *Channel:* type/module-resolution. This
   is why cross-module AG is *unconditionally* sound (contrast the intra-module function-cycle
   case, `cycle-verification-finding.md`, where `def-shell` permits cycles → partial
   correctness).
4. **Qualified `lib.double` vs `(open lib)` unqualified `double`** — identical body-faithful
   treatment via dual keying. *Channel:* contract. *Spec silent today (gap — this closes it).*
5. **Refinement-aliased param across the boundary (`xmod-alias safe-withdraw`)** — a **second,
   separate cause**: the imported alias is merged into the TypeEnv (`Module.hs:183`) but
   `buildContractEnv`'s alias map (`FixpointEmit.hs:193`) is same-file, so the
   `augmentContractPre` fold misses across modules. The `cenv` seeding is necessary but not
   sufficient; the alias map must also be seeded from imports. **Fail-closed** (unresolvable
   alias → fallback, never mis-verify), so a completeness follow-on, not a soundness blocker.

## Verification mapping

- **Obligation:** the caller's existing body-VC, now with the imported callee's `pre`/`post`
  as call-site obligation / assumption.
- **Channel:** contract (body-faithful VC) for the proof; trust (§5.3.4 meet) for the tier.
- **Fragment:** **QF-LIA — no new obligation, no new theory.** The identical assume-guarantee
  VC intra-module calls already emit (§5.3.4); only the `ContractEnv` population changes.
  `Σ_auto` membership unchanged (§5.3.3).

## Soundness (professor-reviewed — clean, one blocking condition)

1. **Acyclic-DAG corollary — confirmed.** Assume-guarantee over a *cyclic* component graph
   needs the well-foundedness/fixpoint argument (Abadi–Lamport, *Conjoining Specifications*,
   TOPLAS 1995; Misra–Chandy for the mutual case). Over an *acyclic* graph a topological order
   exists, so each component is verified against imports whose specs are already discharged —
   the ordinary compositional Hoare rule, no fixpoint argument. Module-cycle rejection
   (`Module.hs:147`) puts LLMLL squarely in the acyclic case; this is exactly the F\* interface
   (`.fsti`) model and Dafny's `module`/`export` model (verify a module against imported
   interfaces, acyclic dependency graph). The module-cycle prohibition is the side condition
   the classical result requires. *Note:* the corollary composes through the existing
   partial-correctness caveat for recursive `def-shell` functions inside a module; it adds no
   new caveat at the boundary.
2. **Body-faithful / tier separation — sound.** "Body-faithful" = the body-VC discharged
   *under the assumption of the callees' posts*; "tier" = the trust closure of those
   assumptions. Orthogonal by the assume-guarantee discipline: a Hoare triple proved relative
   to assumed callee specs is a genuine derivation whose soundness is conditional on the
   assumptions. This is the existing intra-module §5.3.4 meet + strict-core conjunct (d),
   lifted verbatim across the boundary; the current fallback is strictly *less* precise.
3. **Cross-module staleness — the one blocking condition (A3).** The importer's `verified`
   tier rests on the imported module's sidecar; a stale imported `verified` (source changed,
   not re-verified) would make the importer's `verified` false. The status quo (contract-only
   fallback) lands the caller at `asserted`, honestly signalling "conditional on an unproven
   assumption"; this proposal raises the caller to `verified`, so it raises the stakes of the
   pre-existing staleness gap from "an asserted claim was optimistic" to "a `verified` claim is
   false." This is the separate-compilation / stale-interface consistency problem (F\*'s
   per-module checked-file hashing; Dafny's fresh dependency-graph re-verification;
   `make`-consistency). LLMLL is "sound modulo trust" (`verification-debate.md`); a stale
   imported `verified` is a trust-model violation. Hence A3 is a soundness precondition, in
   this change.

## Affected surface

- `compiler/src/LLMLL/FixpointEmit.hs` — `emitFixpointWith` signature (imported `ContractEnv`),
  `buildContractEnv` union / `seedImportedContracts`, and (edge case 5) `buildAliasMap` seeding
  from imports. `bodyToPredM` AG path unchanged.
- `compiler/app/Main.hs` `doVerify` (~:1150-1232) — extract `meContracts` + `meContractStatus`
  from `_cache` and pass to `emitFixpointWith`; extend `downgradeStaleVerifiedSidecar`
  transitively (A3).
- `compiler/src/LLMLL/Module.hs` — expose the merged imported `ContractEnv` + tier map.
- `compiler/src/LLMLL/TrustReport.hs` — cross-module tier meet + downstream-trust warning
  (sidecar already keys qualified names, §4.4.4 — likely read-side compatible).
- Docs (doc-lead, after ship): §5.3.4 (cross-module AG is body-faithful), §5.3.5
  (`erBodyFallback` no longer fires on module boundaries), the §8 module section, the
  §5.3.3/§5.3.5 matrix.
- Freeze: not implicated — freeze ran through v0.10; HEAD is v0.14.16. No new construct.

## Risks and open questions

1. **Tier meet over-admits.** *soundness/trust.* An imported `asserted` must yield an
   `asserted` caller, never `verified`. The meet exists intra-module; risk is faithful reuse.
   A1 vs A2 is the acceptance gate. *Bite:* blocks correctness if botched.
2. **Refinement-aliased-param second cause (edge case 5).** *scope.* `cenv` fix alone leaves
   `xmod-alias safe-withdraw` on `body-fallback`; alias-map seeding is a paired sub-fix. Name
   it so it is not read as a regression. *Bite:* completeness, fail-closed.
3. **Staleness contract shape (open — decide before implementation).** When an imported
   module's source hash mismatches its sidecar, does the importer's verify (a) **hard-error**
   demanding re-verification of the import (F\*/`make` behavior), or (b) **silently downgrade**
   the imported tier to `asserted`/`unknown` and continue (Dafny-ish)? The choice determines
   whether a stale import is a build failure or a silent tier demotion, and it must be stated
   so `--strict-verified-core`'s guarantee is unambiguous across a module graph.

## Engineer hand-off (Rev 1, settled)

- **Settled surface/semantics:** seed the body-VC `ContractEnv` with imported `meContracts`
  (dual-keyed opened + qualified); intra-module AG VC unchanged; tier via §5.3.4 meet;
  body-faithfulness and tier orthogonal.
- **Affected modules:** `FixpointEmit.hs` (`emitFixpointWith` sig + `buildContractEnv`/alias-map
  seeding), `Main.hs` `doVerify` (thread `_cache` contracts + transitive staleness),
  `Module.hs` (expose merged contracts), `TrustReport.hs` (cross-module meet).
- **Blocking acceptance:** A1–A4, with **A3 (cross-module staleness validation) in-scope, not a
  follow-on.** Resolve open question 3 (hard-error vs downgrade) first.
- **No JSON-AST / schema delta.**

## Appendix — Professor review log

*Reviewed 2026-07-08. Verdict: two clean confirmations, one blocking condition.*

- **Q1 (acyclic-DAG corollary): confirmed, and stronger than "no new metatheory."** Cyclic AG
  needs the Abadi–Lamport fixpoint argument; acyclic AG is the ordinary compositional Hoare
  rule with a topological order. Module-cycle rejection is exactly the side condition the
  canonical modular-verification result (F\* interface model; Dafny modules; Leino–Nelson
  lineage) requires. Composes through the existing partial-correctness caveat for in-module
  recursion; adds none at the boundary.
- **Q2 (body-faithful/tier separation): sound.** It is the existing §5.3.4 trust-closure lifted
  across the boundary; the current `erBodyFallback` collapse is strictly less precise (discards
  a real proof because a dependency lives in another file). Load-bearing: the meet must run
  cross-module (`asserted` import → `asserted` importer).
- **Q3 (staleness): the leading hazard — promote from risk note to blocking acceptance
  criterion.** The proposal's value is a `verified` caller on an imported `verified`; that is
  unsound if the import's sidecar can be stale. Transitive imported-sidecar freshness
  validation must ship *in* this change. → folded as A3 + Soundness §3 + open question 3.
- Refinement-aliased-param case is fail-closed → completeness follow-on, not a soundness
  blocker; must not hold up the primary fix.

*Reviewed 2026-07-08 (implementation follow-on — cross-module constructor-tag coherence). Verdict: hazard confirmed, clean fix; shipped v0.14.17.*

- **Tag-coherence subtlety (surfaced by the engineer's implementation homework, not in Rev 1).**
  Desugaring an imported contract's nullary-enum constructor VALUES to int tags with the *imported*
  module's tag map, while the caller's body uses the *entry* module's map, is unsound when the two
  modules independently declare a same-named ADT with a different constructor order. It is reachable:
  cross-module type identity is nominal-by-bare-name with structural checking explicitly deferred
  (`TypeCheck.hs`, "nominal identity is future work; `compatibleWith` compares constructor names, not
  structure" — the unshipped MOD-5 item), and alias merge is local-wins. **Fix (adopted):** build ONE
  cache-aware, local-wins alias map (entry ∪ imported `STypeDef`s, matching `TypeCheck.seedAliases`)
  and desugar BOTH the caller body and the imported contracts against it — tags coherent by
  construction, and `buildCtorTagMap`'s "unambiguous only" guard fail-closes any residual clash. Do
  **not** split the tag map per module (that split is where the unsoundness lives). This also closed
  the imported-only-ADT crash gap (widen the emitter's alias map from entry-only). Orthogonal to the
  A2/A3 tier confirmations — a translation-layer concern, upstream of the tier meet. The
  nominal-by-name residue is a pre-existing MOD-5 limitation the feature inherits but does not widen.
