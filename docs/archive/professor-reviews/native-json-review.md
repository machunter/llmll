---
name: native-json-review
title: "Professor review of the native `json` design, and the verdict on how far nativeness pays"
status: "Rev 0, standalone review; the reviewed proposal is not on disk"
date: 2026-08-03
author: professor
consumers: [user, language-team, main-agent, compiler-engineer]
---

# Professor review: native `json` in LLMLL

## 1. What this document is

A record of one design exchange on native JSON support, written to be portable into a session that
did not see it. It contains three things: a restatement of the language-team proposal it reviews
(§2, non-normative), the review findings (§3, §4), and the verdict on the separate question of how
much nativeness is worth buying (§5).

**The reviewed proposal is not on disk.** The language-team produced it in conversation and stopped
before drafting, per its POST-PLAN step 1. §2 restates it so this review stands alone. When
`native-json-proposal.md` is written, this file becomes its paired review and §2 should be deleted
in favour of a pointer.

**Tracked row this sits on.** `JSON-1` (`docs/compiler-team-roadmap.md:58`), the last open item of
DRIVER-LL Phase 2 (`docs/design/driver-in-llmll-campaign.md:221-270`). The tracked row scopes a
sealed `Json` builtin, `def-shell`-only, on the stated grounds that it "never enters a body-faithful
VC, exactly as `list[a]` does not today." The proposal reviewed here is a widening of that row, and
both it and this review find the quoted justification false; see F4.

No prior JSON design doc exists in `docs/design/`. A grep of the folder and `INDEX.md` returns only
the campaign row. The absence is itself information: this is the first design pass, and there is no
earlier review to fold.

---

## 2. The proposal as reviewed (restatement, non-normative)

Attributed to language-team, restated here for portability. Nothing in this section is settled spec.

The organizing idea is that "built into the language like a list" has a precise meaning in LLMLL
across five axes, and JSON can be given the same treatment on each:

| Axis | `list[a]` today | proposed `json` |
|---|---|---|
| Type level | lowercase builtin in §3.2, not user-declarable | `json`, added to §3.2 and `sealedTypeNames` |
| Literal | `[a b c]`; JSON-AST `lit-list` | `(json-lit "…")`; JSON-AST `lit-json` |
| Operations | 12 builtins, partial ones return `Result` (§13.5) | 20 builtins, same discipline, new §13.13 |
| Codegen | native Haskell list | sealed JSON value type in the emitted prelude |
| Verification | opaque carrier `Lst` + measure `listLen` | opaque carrier `Jsn` + measures `jsonTag`, `jsonSize` |

Staged as **Layer 1a** (the driver's need: parse, serialize, single-step accessors, ten builtins),
**Layer 1b** (tag reflection, a size measure, and subterm-descent facts so recursive walkers reach
total correctness), and **Layer 2** (schema-directed derived codecs, named but out of campaign
scope).

Decisions that carry through the review:

- **No `match` on `json`.** Discrimination goes through a separate nullary enum `JsonTag` with seven
  arms (`JNull JBool JInt JFloat JStr JArr JObj`) projected by `json-tag`, on the argument that
  payload-binding arms would yield inexact body VCs and therefore false `refuted` verdicts.
- **Objects are ordered association lists**, not `map[string,json]`, retaining duplicate keys, with
  `json-get` last-wins. Justified by diff stability on committed artifacts.
- **Numbers split** into `JInt int` and `JFloat float`, exploiting LLMLL's unbounded `int`.
- **Accessors return `Result` with no PROVE-polarity preconditions**, a deliberate asymmetry with
  the bytes and map families of §13.12, because a JSON value's shape is not statically expressible.
- **Canonical serialization**, so `json-serialize (json-parse s) = s` is a stated non-theorem.
- **Two measures as uninterpreted functions** with ground range facts per occurring term, presented
  as widening `Σ_auto` by two symbols and no new theory.

---

## 3. Findings

Severity ordered. Each carries a classification, a citation, and the size of the bite.

### F1. Layer 1b re-introduces the fact-injection mechanism the project deleted at v0.14.78

**Spec-drift, then soundness of discipline. Bite: blocks Layer 1b as written.**

Layer 1b emits `jsonSize(c) < jsonSize(v)` as ground facts injected at syntactic accessor
occurrences, citing `compiler/src/LLMLL/FixpointEmit.hs:4306-4316` ("grounded per OCCURRENCE, from
three sources after FACT-AG-LEN, and from no declaration directly"). That comment says the opposite
of the reading given to it: its three sources are the effective **precondition**
(`bytesLenParamPre`), the **constructor axiom** (`bytes-zero`), and the effective **postcondition**
(`bytesLenRetPost`). The constraint-LHS injection was `resultLenFact`, recorded as **deleted** at
Stage 3 (`docs/design/fact-ag-proposal.md:36`, `:238-240`), with the fact moved "off `lhsPred` into
the goal" so the body proves it and callers recover it through assume-guarantee.

The project has already adjudicated which facts may be injected.
`docs/design/fact-ag-proposal.md:70-83` states Hoare's two-sided criterion (*Proof of Correctness of
Data Representations*, Acta Informatica 1(4), 1972):

> **(i) Establishment.** A fact derived from a declared type may be assumed in a VC antecedent only
> if it is established by the sealed introduction forms of that type. Otherwise it must be earned as
> an obligation.
>
> **(ii) Modularity.** A fact that is *parametric in a type index* must additionally be re-exported
> as a guarantee to cross a call boundary. A fact that is *uniform over the type constructor's
> inhabitants* needs no export channel.

The one surviving injection (`injectBoolValRangeFacts`, `fact-ag-proposal.md:37`) survives because
`0 ≤ select(m$val,k) ≤ 1` is uniform over inhabitants. `jsonSize(c) < jsonSize(v)` fails both
halves: no introduction form of `json` establishes it at the use site, and it is parametric in the
accessor and its key or index. By the project's own criterion it belongs on the earn side.

The external reading converges. Liquid Haskell does not inject descent facts either; it attaches
measures to **constructors** as refinement types, so the tail selector carries
`{v : [a] | len v = len xs - 1}` in its own signature and the fact rides assume-guarantee (Vazou,
Seidel, Jhala, Vytiniotis, Peyton Jones, *Refinement Types for Haskell*, ICFP 2014, §3.2, §4). Two
independent reading paths reaching the same channel is the signal.

### F2. The ban on `match` rests on a false premise: the sort-level encoding of `json` is not recursive

**Decidability, then scope. Bite: complicates, and removes the main justification for the proposed surface.**

The proposal's Risk 1 asserts that matchable payload arms would bind fresh unconstrained symbols,
producing under-determined body VCs and hence false `refuted` verdicts. That is a property of one
encoding, not of the type.

Lower each constructor's payload by the existing rules: `bool`, `int`, `float`, `string` go to
scalars and the `Str` carrier; `list[json]` goes to `FQList`, the opaque `Lst` carrier
(`FixpointEmit.hs:2419`); the object association list goes to `Lst` as well. **The sort `Jsn`
therefore does not mention itself.** The recursion is quotiented into an uninterpreted carrier from
which the logic has no path back: no selector, axiom, or measure maps `Lst` to `Jsn`. The declared
datatype is acyclic, the quantifier-free theory of algebraic datatypes is decidable and is what z3
runs (Barrett, Shikanian, Tinelli, CADE 2007; Reynolds, Blanchette, JAR 2018, both already cited at
`LLMLL.md:961`), and the emission path exists today: `FQDataDecl` and `emitDataDecl`
(`FixpointIR.hs:187, 367`) driven by `typeSorts` (`FixpointEmit.hs:2568-2579`, `:527`).

Under that encoding testers and selectors reflect **exactly**, so the false-refutation hazard does
not arise for `match` on `json`: an arm's payload binder is `jarr(v)`, not a fresh symbol, and the
tester is the path guard. Three consequences:

1. `JsonTag`, `json-tag`, the `FQJsn` carrier, and both measure symbols become unnecessary. `json`
   joins the **datatype class** of `Σ_auto` with a note, rather than adding two measure symbols to
   `LLMLL.md:952`.
2. The obligation the proposal flags as possibly unstatable
   (`is-ok (json-as-int v) ⟺ jsonTag(v) = JInt`) becomes a theorem of the datatype theory instead of
   an asserted fact contingent on whether `is-ok` reflects in `exprToPred`.
3. The proposal's positive witness (a seven-arm nullary match on `json-tag`) is replaced by a direct
   seven-arm match on `json`, with the same verdict and the same refuting twin, exercising the
   shipped COMP-4 path rather than a new one.

The cost, stated plainly: `admissibleDatatype` (`FixpointEmit.hs:2548-2566`) decides acyclicity over
**source** types, so it rejects `json`, and admitting it is a deliberate bypass of a shipped gate.
That bypass needs one written soundness paragraph, and `LLMLL.md:961` supplies the argument: the
gate firewalls the recursive *measure* a recursive type invites, not the datatype theory, and this
encoding introduces no measure over `Jsn` at all.

**Empirical check owed before settling**, in the project's own "measured, not assumed" style
(`fact-ag-proposal.md:221`): confirm the pinned liquid-fixpoint accepts an `FQDataDecl` whose field
sort is the bare uninterpreted `Lst`. `FixpointIR.hs:233` records `Lst` as "probe-verified accepted
bare" in *binder* position; accepted as a *datatype field sort* is a different acceptance and has
not been probed.

### F3. The object representation and the serializer contradict each other

**Internal inconsistency, ergonomic. Bite: complicates; changes the builtin family and the acceptance clause.**

Objects are ordered association lists, justified by diff stability on committed artifacts ("a JSON
writer that reorders every key produces noise in exactly the artifacts the campaign diffs"). The
same section mandates canonical serialization with no insignificant whitespace, and the family
contains only `json-serialize`. Reading and rewriting a pretty-printed `manifest.json` collapses it
to one line, which destroys diff stability far more thoroughly than key reordering would. Either a
pretty-printer ships with a pinned indentation discipline, or the diff-stability rationale is
withdrawn and the assoc-list choice is re-justified on duplicate-key fidelity alone, which is a
sufficient argument on its own and a cleaner one.

### F4. `json-set` has no stated law, and duplicate retention makes the obvious ones inconsistent

**Soundness of the stated laws, ergonomic. Bite: complicates; must be pinned before hand-off.**

Duplicates are retained and `json-get` is last-wins, but no law is stated for `json-set`.
Replace-first gives `json-get (json-set v k x) k ≠ ok x` whenever `k` occurs twice, because the get
returns the later binding. Remove-all-and-append restores the law but moves the field to the end,
defeating F3's motivation. Replace-last-in-place preserves both and is the only one of the three
that does. RFC 8259 §4 leaves duplicate handling to the implementation, so this is a free choice
that must nonetheless be made explicitly.

### F5. The tag-determines-projection biconditional is hostile to real JSON

**Ergonomic, interop. Bite: complicates; catches a likely driver failure.**

Splitting numbers at the tag and then making the tag exactly determine which projection succeeds
means `{"timeout": 30}` and `{"timeout": 30.0}` are not interchangeable for a consumer expecting a
float. RFC 8259 §6 leaves number representation to the implementation and frames interoperability in
terms of what receivers accept; every mainstream codec coerces (aeson parses to `Scientific` and
converts on demand, serde's `Number` exposes `as_f64` over both representations). The proposal's own
biconditional is what forbids coercion, so verification elegance and interop are in direct conflict
and the proposal does not notice.

Resolution at no verification cost: `json-as-float` succeeds on `JInt` and `JFloat` both, and the
fact becomes a disjunction over testers or tag values, still quantifier-free. Keep `json-as-int`
strict on `JFloat`, including integral floats, and say so, because silent narrowing is the worse
failure.

### F6. Declaring PBT the end state for the round-trip law forfeits available work

**Scope. Bite: only matters at scale, but it changes what Layer 2 claims.**

The proposal routes `json-parse (json-serialize v) = ok v` to PBT and the `tested` tier, with a
proof marked Lever C. Correct for a hand-written codec, not for a **derived** one, which is what
Layer 2 proposes. Narcissus (Delaware, Suriyakarn, Pit-Claudel, Ye, Chlipala, ICFP 2019) and
EverParse (Ramananandro, Delignat-Lavaud, Fournet, Swamy, Rastogi, Protzenko, USENIX Security 2019)
both derive encoder/decoder pairs together with machine-checked round-trip theorems, in Coq and F\*
respectively. The structural point: both discharge the round trip **per format description**, so the
theorem is proved once per derived codec rather than universally over the dynamic type. That is a
materially different and dischargeable obligation.

EverParse also states its round trip in two directions, parse-after-serialize and
serialize-after-parse modulo canonicalization. That is exactly the pair the language-team arrived at
independently when correcting the acceptance clause (F8), and the convergence supports the
correction.

### F7. `(json-lit <string-literal>)` is a function-shaped construct with a syntactic side condition

**Ergonomic, surface. Bite: minor.**

A builtin whose argument must be *syntactically* a literal is not expressible in `builtinEnv`, which
carries types only (`TypeCheck.hs`, and `trustedPrelude` at `:723-732` is a name set), so it needs a
bespoke check and cannot be passed or eta-expanded like every other builtin. The cited `bytes-zero`
precedent is a **type**-determined context (`FixpointEmit.hs:1580-1593` matches head-syntactically
on the declared *return type*), a different mechanism. The JSON-AST surface already gets a proper
node; give the S-expression surface a literal token as well, so both surfaces have a literal and
neither has a pseudo-builtin.

### F8. Two drift findings from the proposal, independently confirmed

**Spec-drift. Bite: complicates; both should be routed regardless of which encoding wins.**

- The roadmap justification at `docs/compiler-team-roadmap.md:58` and
  `driver-in-llmll-campaign.md:260-261`, that a sealed `Json` "never enters a body-faithful VC,
  exactly as `list[a]` does not today", is false in its strong reading. `list-length` is named as an
  in-`Σ_auto` measure at `LLMLL.md:959`, a list binder gets a real carrier sort
  (`FixpointEmit.hs:2419`), `sortableComponent` admits `TList _` (`:2475`), and the §5.3.5 `EPair`
  row marks a list component body-faithful. What is firewalled is list *element* reasoning.
- The `JSON-1` acceptance clause at `driver-in-llmll-campaign.md:267-269` accepts "a round trip
  `json-serialize (json-parse s)`" without stating an equation. The textual reading is false under
  any implementation. It should be restated as value round trip plus normalization idempotence
  (`json-serialize (json-parse s1) = s1` where `s1 = json-serialize (json-parse s)`).

### F9. The recursive-measure firewall is presented as forced; it is a choice

**Scope divergence, informational. Bite: blocks nothing.**

Following `LLMLL.md:961`, the proposal treats "recursive measure axiom, therefore non-terminating
instantiation, therefore ban" as the only disposition. The established alternative is **fuel**:
bounded unrolling of recursive definitions, which keeps every query terminating while admitting
recursive functions (Amin, Leino, Rompf, *Computing with an SMT Solver*, TAP 2014; Leino, *Dafny*,
LPAR 2010). Fuel trades completeness for control, and LLMLL has chosen completeness inside
`Σ_auto`, so this is a scope divergence rather than a soundness disagreement. Worth recording
because if `json-size` is ever wanted as a *defined* recursive measure, the acyclicity firewall is
not the only instrument.

---

## 4. Answers to the two questions the language-team posed

**Q1. Is per-occurrence ground instantiation of `size(child) < size(parent)` a known-complete
strategy under Sofronie-Stokkermans locality?** The completeness framing is misdirected. Ground
facts are hypotheses, not an axiom set; conjoining them to a QF-LIA + EUF + DT query leaves it in
the same decidable, complete fragment, so locality (*Hierarchic Reasoning in Local Theory
Extensions*, CADE 2005) has no work to do. Locality is the right instrument only if the
**quantified** equation is retained, which this design does not. The live questions are soundness
(does every accessor genuinely return a proper subterm in the intended model, a trust-axiom question
rather than a solver question) and sufficiency (do the syntactic occurrences generate enough facts
to close the descent goal). And per F1, the channel is already settled: a fact of this shape is
earned through the effective post.

**Q2. Is there a standard formulation of parse-don't-validate as a refinement obligation on a
derived decoder?** Yes, and this repository already names the classical anchor.
`fact-ag-proposal.md:69` cites Hoare 1972 for abstraction function plus representation invariant; a
decoder's postcondition is the representation invariant of the target type at the `ok` position, and
the round trip states that the abstraction function has a section. Modern derived instances are
Narcissus and EverParse (F6); the Haskell-shaped deriving mechanism is Magalhães, Dijkstra, Jeuring,
Löh, *A Generic Deriving Mechanism for Haskell* (Haskell '10), which aeson's `Generic` instances are
built on. In LLMLL terms the decoder post is an ordinary §3.4.1 introduction obligation at the `ok`
payload position, discharged by the datatype class whenever the target type is
`admissibleDatatype`-admissible. Layer 2 is a port, not a research row, provided the target type
stays inside that gate.

---

## 5. How far nativeness pays

A separate question was put after the review: is native JSON *object* support of any use, or is
Layer 1a enough, given that JSON is the universal exchange format, existing frameworks overcomplicate
it, and JavaScript's treatment is the standard to beat.

### N1. "JavaScript does it best" is correct, and the reason makes it unavailable here

JSON is a subset of JavaScript's object-literal syntax by construction, so in JS there is no
boundary to cross: the parsed value is already a first-class value, `o.a[2].b` is one expression,
and absence is `undefined` with `?.` and `??` to absorb it. Those ergonomics are purchased with the
absence of exactly the property LLMLL exists to provide. Aeson, serde, Jackson, and Elm's
`Json.Decode` are not complicated through carelessness; converting an untyped tree into typed data
is real work, and in a verification language that conversion **is the product**. Nativeness cannot
move LLMLL toward JS on this axis. What it decides is how far inward untyped data travels before it
is converted.

### N2. Where the complexity is gratuitous, and where it is not

Four properties of JSON's data model disagree with any ML-family type system: no sum types (so
tagged unions need an ad hoc convention, which is why serde has `#[serde(tag=...)]` and aeson has
`SumEncoding`), no distinction between an absent key and an explicit `null`, one numeric type, and
objects that are formally unordered but practically ordered. Every mainstream framework's
configuration surface exists to absorb those four, and that complexity is not removable.

What **is** gratuitous is path access. Reading `manifest.stages[2].name` through a chain of
`Result`-returning single-step accessors is friction with no verification content, and it is
precisely what Layer 1a as scoped imposes on all 18 driver call sites. Two systems solved this and
are worth copying: Postgres `jsonb` (`->`, `->>`, `#>>`, plus the SQL:2016 JSON path language) and
`jq`, whose entire data model is JSON. Neither attempted structural typing; both supply a path
operator family over one opaque-ish type, and that shape has survived contact with users for a
decade.

### N3. The strongest argument for nativeness here has no analogue in Haskell or Rust

Two capabilities are unavailable to a library and available only to the language. First, the
literal: LLMLL's primary emission surface is JSON-AST, so an embedded JSON value costs nothing to
represent and nothing to escape, which is untrue in any host language where JSON literals arrive as
escaped strings. Second, derivation: a codec derived from `(type Manifest …)` needs compiler access
to the type declaration, and LLMLL has no macro system and no typeclass deriving. serde gets this
from procedural macros and aeson from `GHC.Generics`. LLMLL has neither, so the ergonomic layer that
matters is native or it does not exist.

### N4. Taken to its limit, the request is row polymorphism, and that is a larger commitment

If the goal is that `v.stages[2].name` *typechecks* rather than returning a `Result`, the
established machinery is row types (Wand; Rémy; Leijen, *Extensible Records with Scoped Labels*,
2005), realized in PureScript and Elm records and retrofitted structurally by TypeScript over
exactly this data. That is a type-system change interacting with the refinement layer, the datatype
class of `Σ_auto`, and every inference rule in §11. It should not be spent on JSON.

### The missing operator, and the asymmetry that motivates it

LLMLL's own tooling is already built on JSON Pointer and JSON Patch, and a program written in LLMLL
cannot address a JSON document at all. RFC 6901 pointers appear in compiler diagnostics
(`LLMLL.md:831`, `:1712`), in `llmll checkout` (`:1890`), and in pointer normalization (`:1955`);
RFC 6902 patch is the hole-resolution protocol (`:1892-1910`,
`docs/llmll-ast.schema.json:1050`). Adding pointer access to the language closes an avoidable
asymmetry using a standard the repository already speaks.

---

## 6. Consolidated recommendation

1. **Adopt the datatype-sort encoding and drop the tag enum** (F2). Declare `json` as an
   `FQDataDecl` with seven constructors whose fields are the existing scalar sorts and the opaque
   `Lst` carrier; keep `match` on `json` with payload binders; delete `JsonTag`, `json-tag`,
   `json-size`, and the `FQJsn` carrier from the design. Smaller than the proposal, reuses the
   shipped COMP-4 path, and converts the weakest obligation into a theorem. Owes one soundness
   paragraph for the `admissibleDatatype` bypass and one liquid-fixpoint probe.
2. **Defer Layer 1b, or move it onto the contract channel** (F1). As specified it is the
   `resultLenFact` shape FACT-AG-LEN removed. The principled version puts the descent fact in the
   accessor's effective post, which needs a builtin-contract channel that does not exist today
   (`builtinEnv` carries types only; `trustedPrelude` is a name set at `TypeCheck.hs:723-732`). That
   channel is worth building because it also pays for `list-tail`, `string-concat`, and the rest of
   §13, and it would close the list-descent gap the language-team correctly identified as symmetric
   residue. It is not on the driver's critical path. Build the channel if Layer 1b is wanted;
   otherwise defer Layer 1b whole. Do not ship the injection.
3. **Add RFC 6901 pointer access to Layer 1a** (§5). Fuse the pointer with the leaf projection so
   the common case is one call taking `"/stages/2/name"` and returning `Result[string, string]`,
   alongside a generic pointer form returning `Result[json, string]`. This is the specific addition
   that answers the ergonomics complaint, at a handful of builtins rather than a type-system change.
4. **Keep the rest of Layer 1a as proposed.** `Result`-returning accessors with no PROVE-polarity
   preconditions are right, and the argument for the asymmetry with §13.12 is the correct one. The
   sealed type name, the depth limit as a disclosed runtime bound, the unbounded-`int` number
   fidelity, and the acceptance-clause correction all stand. Route the acceptance-clause correction
   to `driver-in-llmll-campaign.md:267` immediately and independently; it is wrong today regardless
   of which encoding lands.
5. **Then stop, for this campaign.** Layer 1a plus pointer access covers 18 call sites with no
   residual awkwardness worth paying for now.
6. **Roadmap derived codecs as the next increment, with target and anti-target named.** serde's
   `derive` is the target: near-zero ceremony, configuration only where the four impedance
   mismatches force a choice. Elm's `Json.Decode` is the anti-target: principled hand-written
   combinator pipelines that are widely disliked. If Layer 2 ships as combinators rather than
   derivation it will reproduce the complaint that opened this thread. This is also the only
   increment that yields both low-ceremony access and a verified core, because after decoding there
   is no JSON left inside the program.
7. **Reject row polymorphism for this purpose** (N4), and record the decision so it is not
   rediscovered.

---

## 7. Decisions owed before engineer hand-off

| # | Decision | Source |
|---|---|---|
| D1 | Datatype-sort encoding versus carrier-plus-measures; if the former, write the `admissibleDatatype` bypass paragraph | F2 |
| D2 | Run the liquid-fixpoint probe: `FQDataDecl` with a bare `Lst` field sort | F2 |
| D3 | Layer 1b: build the builtin-contract channel, or defer whole | F1 |
| D4 | Pretty-printer ships, or the diff-stability rationale is withdrawn | F3 |
| D5 | `json-set` law under retained duplicates (replace-last-in-place is the only consistent choice) | F4 |
| D6 | Float coercion over `JInt`, and the disjunctive fact that replaces the biconditional | F5 |
| D7 | Pointer access: one generic builtin plus separate leaf projections, or a fused family per leaf type. The fused form removes the friction but multiplies the builtin count and forces D6 at every call site | §5 |
| D8 | Route the acceptance-clause correction and the `list[a]` justification correction to the campaign doc and roadmap row | F8 |

---

## 8. External references

- Barrett, Shikanian, Tinelli. *An Abstract Decision Procedure for the Theory of Recursive Data
  Types.* CADE 2007. Decidability of QF datatypes; already cited at `LLMLL.md:961`.
- Reynolds, Blanchette. *A Decision Procedure for (Co)datatypes in SMT Solvers.* JAR 2018. The
  procedure z3 runs.
- Vazou, Seidel, Jhala, Vytiniotis, Peyton Jones. *Refinement Types for Haskell.* ICFP 2014.
  Measures attached to constructors; the principled channel for descent facts (F1).
- Hoare. *Proof of Correctness of Data Representations.* Acta Informatica 1(4), 1972. Abstraction
  function plus representation invariant; the anchor the repo already uses.
- Sofronie-Stokkermans. *Hierarchic Reasoning in Local Theory Extensions.* CADE 2005. Relevant only
  if a quantified measure equation is retained (§4, Q1).
- Amin, Leino, Rompf. *Computing with an SMT Solver.* TAP 2014; Leino, *Dafny.* LPAR 2010. Fuel as
  the alternative to an acyclicity firewall (F9).
- Delaware, Suriyakarn, Pit-Claudel, Ye, Chlipala. *Narcissus.* ICFP 2019. Derived decoders and
  encoders with machine-checked round trips.
- Ramananandro, Delignat-Lavaud, Fournet, Swamy, Rastogi, Protzenko. *EverParse.* USENIX Security
  2019. Same, in F\*, with the two-directional round-trip statement.
- Magalhães, Dijkstra, Jeuring, Löh. *A Generic Deriving Mechanism for Haskell.* Haskell '10. What
  aeson's `Generic` instances are built on.
- Leijen. *Extensible Records with Scoped Labels.* 2005. Row polymorphism (N4).
- RFC 8259 §4 (duplicate keys), §6 (numbers). RFC 6901 (JSON Pointer). RFC 6902 (JSON Patch).
- Design references for shape: Postgres `jsonb` operators and SQL:2016 JSON path; `jq`. Anti-target:
  Elm `Json.Decode`. Target: Rust `serde` derive.

---

## 9. In-repo citation index

| Citation | What it establishes |
|---|---|
| `LLMLL.md:952, 959, 961` | `Σ_auto` definition; measure class as local theory extension; the acyclicity gate firewalls the recursive *measure*, not the datatype theory |
| `LLMLL.md:967` | Path-(a) emission side condition: ground facts per occurring measure term |
| `LLMLL.md:831, 1712, 1890, 1955` | RFC 6901 pointers in diagnostics, checkout, normalization |
| `LLMLL.md:1892-1910` | RFC 6902 JSON-Patch hole resolution |
| `LLMLL.md:1010-1035` | §5.3.5 matrix; recursive ctor routed to the strict-core gate |
| `compiler/src/LLMLL/FixpointEmit.hs:2419` | `typeToSort (TList _) = FQList`, the opaque carrier |
| `compiler/src/LLMLL/FixpointEmit.hs:2475, 2529` | `sortableComponent` and `scalarish` admit `TList _` |
| `compiler/src/LLMLL/FixpointEmit.hs:2548-2566` | `admissibleDatatype` decides acyclicity over *source* types |
| `compiler/src/LLMLL/FixpointEmit.hs:2568-2579`, `:527` | `typeSorts` emits datatype declarations into the `.fq` |
| `compiler/src/LLMLL/FixpointEmit.hs:2757` | `exprToPred :: Expr -> Maybe FQPred`; `Nothing` yields clean fallback |
| `compiler/src/LLMLL/FixpointEmit.hs:4306-4316` | Measure constants; the three post-FACT-AG-LEN grounding sources |
| `compiler/src/LLMLL/FixpointIR.hs:85, 233` | `FQList`, emitted as `Lst`, probe-verified accepted bare in binder position |
| `compiler/src/LLMLL/FixpointIR.hs:187-198, 367-372` | `FQDataDecl` and `emitDataDecl` |
| `compiler/src/LLMLL/TypeCheck.hs:723-732` | `trustedPrelude` is a name set; builtins carry types only |
| `compiler/src/LLMLL/TypeAdmissibility.hs:145-151, 253-266` | Recursive ADTs are legitimate to the cycle check; `Response` seeded as a builtin sum |
| `docs/design/fact-ag-proposal.md:36-40, 68-95, 221, 238-240` | `resultLenFact` deleted; Hoare's two-sided criterion; measured-not-assumed discipline |
| `docs/compiler-team-roadmap.md:58` | The `JSON-1` row and its justification |
| `docs/compiler-team-roadmap.md:255` | Freeze-era exclusions lifted; new builtins go through the normal pipeline |
| `docs/design/driver-in-llmll-campaign.md:221-270` | Phase 2 scope and the acceptance clauses |
| `docs/llmll-ast.schema.json:3` | Schema `$id` at v0.10 |
