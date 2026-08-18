---
name: native-json-proposal
title: "JSON-1: the fourteen builtins the driver needs, and the native-JSON work that is not on its path"
status: "Rev 4, SETTLED, reconciled against the shipped compiler. The surface is FOURTEEN builtins, not thirteen. `json-get-number` was re-admitted during implementation (`TypeCheck.hs:290`) on the rationale recorded at `TypeCheck.hs:283-289`, which measured Rev 3's exclusion premise false: Rev 3 dropped the name because the ported spine reads no float, which is true of stage E as a stage and false of Phase 3's acceptance clause, four of whose six pinned results are floats (`rfc_to_implementation.py:1405-1409`). Without it the LLMLL driver can produce the artifact but not check it, and the check falls back to Python. Rev 4 therefore reopens and re-closes §11's first adjudicated question at fourteen, half-ships D-3, and withdraws §2's claim that the name is deliberately absent. The drift was confined to this file: `LLMLL.md:152`, LLMLL.md §13.13 and `CHANGELOG.md:13` already said fourteen. Shipped in v0.14.82. Rev 3, SETTLED by user adjudication 2026-08-03; ready for compiler-engineer. The thirteen-builtin surface was accepted as scoped, and the two §11 open questions were closed with it: the count stands (every name is a measured call site), and D-5's datatype encoding is not taken. Rescoped from Rev 2 after the byte-identity premise that drove most of Rev 0-2's clause burden was measured false: the resume gate at `rfc_to_implementation.py:1758-1769` compares a digest THIS RUN recorded against the file as it is now, in one workdir, so byte-identity with Python's `json.dumps` is required by nothing. Removing that premise removes insertion-ordered objects, the CPython layout clause, the float-formatting obligation, and half the trust-channel disclosures, and it demotes aeson's rejection from two grounds to one (the measured +40-package closure). Rev 2 folded `docs/archive/professor-reviews/native-json-review.md`, whose F2 proposed replacing the opaque carrier with a matchable seven-constructor datatype; F2's two empirical claims were checked and both are wrong in the same direction, but its conclusion still does not follow, because a `list`-carrying match arm forces `body-fallback` (measured) and every exhaustive match on `json` has two. Rev 1 folded a professor critique: equality at `Json` is unspecified and reaches through `list-contains` as well as `=`; duplicate keys are rejected per RFC 7493 rather than last-wins. Rev 0 established the carrier design and four spec-drift findings. Roadmap row: JSON-1"
date: 2026-08-03
author: language-team
consumers: [compiler-engineer, professor, documentation-lead, user]
---

# JSON-1: just enough JSON for the driver

**One line.** DRIVER-LL Phase 3 cannot be ported without structured JSON (72 field reads and 10 field
writes across its five stages, 54 of the reads in stage G2 alone), so `json` ships as a sealed opaque
carrier with fourteen `def-shell`-only builtins; everything that makes JSON *native* rather than
merely *available* is recorded in §8 and is not on the driver's path.

---

## 1. The scope decision, and the premise that moved

Rev 0 through Rev 2 grew a large normative surface: insertion-ordered objects, a byte-exact layout
clause reproducing CPython's `json.dumps(indent=1)`, lexeme-stored numbers to defeat a float-format
divergence, and a set of trust-channel disclosures for all of it. Every one of those rested on the
claim that the LLMLL driver's serialized output must be byte-identical to the Python driver's.

**That claim is false.** The resume gate reads:

```python
rec = manifest["stages"].get(stage.key)
recorded_digests = (rec or {}).get("outputs", {})
want = recorded_digests.get(o)
if want is None or want != sha256_file(ctx.workdir / o): mismatched.append(o)
```

`rfc_to_implementation.py:1758-1769`. The digest compared is the one **this run recorded**, against
the file **as it is now**, in the same workdir. It detects post-hoc tampering and partial writes
inside a single run. It never compares against a Python-produced digest or a committed artifact, and
Phase 4's "reproduces a committed campaign's artifacts" clause cannot demand byte-identity in general
either, because agent-authored stage outputs are nondeterministic text. That clause needs restating
on its own terms; see R-C in §9.

Removing the premise removes four things and changes a fifth:

| Rev 2 clause | Disposition |
|---|---|
| Insertion-ordered objects | **Dropped.** Only Python-byte-identity needed them. |
| `indent=1` layout with CPython separators | **Demoted** to a diff-readability preference: pin an indent, do not specify against CPython. |
| Float formatting compatible with `float.__repr__` | **Dropped** with the obligation that produced it. |
| Byte-fidelity trust disclosures | **Dropped.** |
| aeson rejection | **Narrowed** from two grounds to one: the measured +40-package generated-project closure, against the +46 that dropped `wasi.http.get`. The hand-rolled backend still wins, on the ground the project already adjudicated. |

Number-as-lexeme survives the cut on a different and independent reason. LLMLL's `int` is unbounded,
JSON numbers are not typed at the wire, and storing the source text defers the int/float question to
the accessor instead of forcing a representation choice at parse. It costs nothing and removes a
class of question rather than answering it.

**What "just enough" means here.** JSON is a Phase 3 blocker, not a Phase 4 one, and the builtin
count is close to irreducible because it follows the measured census (§7.1). What was reducible is
the clause burden, and that is what Rev 3 cuts.

---

## 2. Shipped surface

Fourteen builtins, a new `LLMLL.md §13.13`, all `def-shell`-only.

```lisp
;; ingress and egress
json-parse       : string -> Result[Json, string]
json-serialize   : Json -> string

;; projection by key; the fragment re-entry points
json-get         : Json -> string -> Result[Json, string]
json-get-string  : Json -> string -> Result[string, string]
json-get-int     : Json -> string -> Result[int, string]
json-get-bool    : Json -> string -> Result[bool, string]
json-get-number  : Json -> string -> Result[string, string]   ;; the source LEXEME, §3.3

;; sequence bridge
json-array       : Json -> Result[list[Json], string]

;; construction and functional update
json-object      : Json
json-set         : Json -> string -> Json -> Result[Json, string]

;; scalar injection
json-of-string   : string -> Json
json-of-int      : int -> Json
json-of-bool     : bool -> Json
json-of-list     : list[Json] -> Json
```

`Json` is `TCustom "Json"` with **no alias body**: opaque in the checker, opaque in the emitter,
sealed against redefinition. It lowers to a fresh opaque FQ sort alongside `FQList` and `FQStr`
(`FixpointEmit.hs:2415-2420`). No `json-*` name is reflected as an interpreted function, so a body or
contract mentioning one takes today's fallback routing unchanged, exactly as the `bytes` and `map`
entries do (`TypeCheck.hs:236-239`).

**Deliberately absent, each with the measurement.** No `json-index`: 3 integer-indexed reads exist,
all in `_checkout`'s pointer walk (`:1121-1128`), and `json-array` composed with `list-nth` covers
them. No `json-keys`: no site iterates object keys. No polymorphic `json-of`: `TVar` unification
would admit `Command -> Json`. No `json-remove`: zero deletion sites.
No RFC 6901 pointer access: 7 chained reads driver-wide, **0 in Phase 3** (§7.1); deferred as D-1.

**`json-get-number` is present, and Rev 3's argument for excluding it was wrong (Rev 4).** Rev 3
listed it in this paragraph on the ground that the driver's only float reads are `self_test`'s four
pinned comparisons (`:1405-1409`), a test harness rather than a stage, so the ported spine never
reads one. That is true of a stage and false of the phase: Phase 3's acceptance clause IS
`self_test()`'s pinned results (`driver-in-llmll-campaign.md:286-290`), and four of the six are
floats. Excluding the name let the driver produce the artifact but not check it, which moves the
acceptance check back into Python and forfeits the point of the port. It returns the source LEXEME
rather than a `float` (§3.3), so comparison against a literal is STRLIT string equality and lands
inside `Σ_auto`, where float equality does not (`LLMLL.md:289`). Still no `float` anywhere.

---

## 3. Semantics

### 3.1 `def-shell`-only, and why the rule tracks an emitter boundary

Enforced by a name-keyed exclusion set consulted by `checkCalleeAdmissibility` before its
`Map.member func builtinEnv` leg (`TypeCheck.hs:788-791`):

```
coreExcluded(f)                          Γ ⊢ core-mode
─────────────────────────────────────────────────────── (CORE-EXCL)
        core-membership-violation(enclosing, f)
```

The rule is **not** justified by `Json`'s opacity. Under a matchable datatype encoding a `def`
touching JSON structure also lands at `body-fallback` (§7.3), so both encodings produce the same
verdict. What `def-shell`-only buys is that the fallback is **explicit at the type-check gate**
rather than **silent at the emitter**. The boundary it tracks is stated in the code: "A `list`
carrier or a recursive sum stays firewalled (the deliberate final boundary)"
(`FixpointEmit.hs:2500`). If that boundary ever moves, this rule becomes conservative rather than
necessary, and the spec text should say it tracks the boundary rather than the type.

**Bundle the `wasi.*` names into the same set.** `LLMLL.md:454` already claims the typechecker
enforces `def-shell` for functions that "perform IO via `wasi.*`" and it does not (§9, R-B). Blast
radius measured at **0 of 303** `def`-form functions in the committed corpus. The change costs
nothing and makes an existing claim true.

### 3.2 Equality

```
       ⌈τᵢ⌉ mentions Json        f ∈ {=, !=, list-contains}
────────────────────────────────────────────────────────────── (JSON-NOEQ)
                    type error at the call site
```

`⌈·⌉` is `normalizeTy` (`TypeAdmissibility.hs:300-320`), whose congruence walk already descends
`TList`, `TResult`, `TPair`, and `TSumType` payloads, so `list[Json]` and `Result[Json, string]` are
covered with no new traversal. `list-contains` (`TypeCheck.hs:121`) is a second equality consumer
over `TVar "a"` and `json-array` produces `list[Json]`, so it is a reachable path rather than a
hypothetical one.

Denial rather than definition, for two reasons. Structural equality on any representation exposes
representation detail as observable program behaviour, and equality at an opaque type silently drops
a `def` from body-faithful to fallback with no diagnostic (measured: §7.4). The idiom for a program
that needs it is `(= (json-serialize a) (json-serialize b))`, where what is being compared is stated.

This is a per-type denial in a language that now has four types with unspecified equality (`Command`,
`Response`, `Promise`, `Json`). The general rule is D-6.

### 3.3 Numbers

A JSON number is validated against RFC 8259 §6's grammar at parse and **stored as its source text**.
`json-serialize` emits that text unchanged. `json-get-int` succeeds when the lexeme denotes an
integer and returns `err` otherwise, including on `1.0`, which denotes an integral value but is not
an integer lexeme. Number equality is therefore syntactic: `1.0`, `1.00`, and `1e0` are distinct
`Json` values. Silent narrowing is the worse failure, and the driver reads no non-integer number.

### 3.4 Duplicate member names

`json-parse` returns `err` on an object with duplicate member names, comparison performed **after
unescaping**, per RFC 7493 §2.3 verbatim: "Objects in I-JSON messages MUST NOT have members with
duplicate names. In this context, 'duplicate' means that the names, after processing any escaped
characters, are identical sequences of Unicode characters."

RFC 8259 §4 leaves the behaviour "unpredictable", and the inputs here are agent-authored at stages G,
H, and M, which the campaign's threat model treats as adversarial. Rejection makes two independent
parsers agree by construction; last-wins makes them silently disagree. Rejection also makes
`json-set`'s law unconditional: with no duplicates possible, replace-in-place is the only rule and
`json-get (json-set v k x) k = ok x` holds. Under retention it does not, which is `docs/archive/professor-reviews/native-json-review.md`
F4.

### 3.5 Serialization

Deterministic, with a pinned one-space indent for readable diffs. **Not** specified against CPython.
Key order is the implementation's choice and is not observable through any shipped builtin, since
JSON-NOEQ removes the only path to observing it other than `json-serialize` itself.

`json-serialize (json-parse s) = s` is a non-theorem and is not claimed. What is claimed and testable
is value round trip, `json-parse (json-serialize v) = ok v`, at the `tested` tier.

### 3.6 Runtime backing

A hand-rolled parser and serializer in `CodegenHs.hs` as an exported `jsonPreamble :: [Text]` CAF,
spliced only when the program mentions a `json-*` name, adding **no** generated-project dependency.
Correctness tier is `asserted`, the sealed-builtin-backed-by-real-Haskell precedent of `sha1` and
`hmac-sha1` (`LLMLL.md §13.11`, `TypeCheck.hs:227-231`).

The asserted surface is larger than a hash stub, and the mitigation is free: `aeson >= 2.1` is
already a **compiler** dependency (`compiler/package.yaml:34`), so a differential test can use it as
an oracle at zero cost to the generated closure. The corpus is `nst/JSONTestSuite` (Seriot 2016),
roughly 318 cases classified `y_` / `n_` / `i_`, which exercises the depth, duplicate-key,
number-format, and encoding cases §4 enumerates. This is a CI gate, not a one-time check: it is the
only thing standing between an agent-authored file and a recursive-descent parser in the asserted
tier.

---

## 4. Edge cases

1. **Positive witness, CORE-EXCL.** `(def field-len [j: Json] (post (>= result 0)) (string-length
   (unwrap (json-get-string j "cid"))))` → `core-membership-violation: field-len calls
   json-get-string`. The counterfactual is measured, not asserted: under a datatype encoding the same
   function is admitted and lands at `body-fallback` silently (§7.3). Channel: **type**
   (`TypeCheck.hs:791-794`).
2. **Positive witness, JSON-NOEQ, both paths.** `(def eq-json [a: Json b: Json] (if (= a b) 1 0))`
   and `(def has-it [xs: list[Json] j: Json] (if (list-contains xs j) 1 0))` are both rejected. Today
   the first is accepted and falls back (§7.4); the second is the path reachable through
   `json-array`. Channel: **type**.
3. **`Json` parameter with no operation.** `(def constant-one [j: Json] 1)` accepted, body-faithful,
   `j` bound at the opaque sort. Channel: spec is silent, intentionally. The rule bounds operations,
   not values, on the `list[a]` precedent; JSON-NOEQ narrows the admitted set to bodies applying no
   operation at all.
4. **Duplicate names after unescaping.** `{"a":1,"a":2}` → `err`. A parser comparing raw key
   text accepts it. Channel: **contract**, via the `err` arm; RFC 7493 §2.3.
5. **`json-get-int` on `1.0` and on a 40-digit integer.** The first is `err` (§3.3). The second
   succeeds: LLMLL's `int` is unbounded at the logic level, and the lexeme representation means no
   precision is lost at parse. Channel: **contract**. Cite `LLMLL.md §5.3.5` for the `Int64` codegen
   gap this does not widen.
6. **Depth bomb.** A 100k-deep `[[[[…]]]]` from an agent-authored file returns `err`, not a stack
   overflow, under a pinned 512 limit. Channel: **trust**, gated by JSONTestSuite's
   `i_structure_500_nested_arrays`. Without it a hostile input becomes a process abort, which would
   break the invariant that logic functions cannot crash from IO (`LLMLL.md:1840`).
7. **Non-UTF-8 input file.** Already `RErr` at `wasi.fs.read` (`CodegenHs.hs:517-524`), which forces
   decoding inside its `try`; never reaches `json-parse`. Channel: spec is silent, intentionally.

---

## 5. Verification mapping

| Obligation | Channel | Fragment | Citation |
|---|---|---|---|
| `json-parse` totality (malformed, deep, or hostile input yields `err`, never a crash) | trust | outside `Σ_auto`; **asserted** sealed builtin, gated by JSONTestSuite | `LLMLL.md §5.3.5`; `§13.11` precedent |
| Accessor call inside a body VC | contract | `Json` lowers to an opaque sort; each `json-*` is an **uninterpreted function**, so a mentioning body takes the existing fallback | `FixpointEmit.hs:2415-2420`; `TypeCheck.hs:236-239` |
| Accessor result re-entry, `Result[int\|bool\|string, string]` | contract | **QF-LIA**, auto-discharged; `Result` over scalar payloads is already admissible | `LLMLL.md §5.3.3` datatype class; `§5.3.5` |
| A `def` matching `json` structure under **either** encoding | contract | **fallback**, measured (§7.3); the list-carrier firewall is stated policy | `FixpointEmit.hs:2500` |
| Duplicate-name rejection | contract | `err` arm, QF-LIA-inert | RFC 7493 §2.3 |
| Value round trip `json-parse (json-serialize v) = ok v` | trust | `tested` tier via `llmll test`; **not** a Lean obligation | `LLMLL.md §4.4.5` PBT-Lift |
| CORE-EXCL and JSON-NOEQ side conditions | type | not proof obligations; set membership and a normalized-type test | `TypeCheck.hs:758-794`; `TypeAdmissibility.hs:300-320` |

No obligation escapes to Lean. No obligation is nonlinear or quantified. **`float` does not appear**,
which removes the one carrier-sort re-entry Rev 1 carried.

---

## 6. Affected surface

1. `compiler/src/LLMLL/TypeCheck.hs`: fourteen `builtinEnv` entries (new `§13.13` block after
   `:247`); `coreExcludedBuiltins :: Set Name` and its leg in `checkCalleeAdmissibility`
   (`:788-791`), carrying the `wasi.*` names too; JSON-NOEQ at the per-call-site substitution point,
   which needs a `TypeAdmissibility` call `TypeCheck` does not have today. `TypeAdmissibility` must
   stay leaf (`compiler/package.yaml:63-66`); this respects that.
2. `compiler/src/LLMLL/TypeAdmissibility.hs`: `sealedTypeNames` decoupled from
   `Map.keys builtinAliases` (`:275-276`), which cannot seal a type with no alias body (R-E); new
   `opaqueSealedNames` carrying `Json`.
3. `compiler/src/LLMLL/FixpointEmit.hs`: an opaque-sort constructor and its `typeToSort` clause
   (`:2415-2420`); confirm the sort-blind selector paths abstain rather than fall through.
4. `compiler/src/LLMLL/CodegenHs.hs`: `jsonPreamble :: [Text]` as an exported CAF; conditional
   splice in `emitModule` (`:207-215`); **no** `package.yaml` dependency change (`:1354-1356`
   unchanged).
5. `compiler/test/Spec.hs`: extend the WASI-RT preamble-completeness fold (`:14361-14386`) to cover
   `jsonPreamble`, plus a mirror fold asserting every `json-*` name in `builtinEnv` has a preamble
   binding. JSON-1 adds fourteen names at once and WASI-RT was the four-name version of this defect.
   Add the JSONTestSuite differential gate.
6. `LLMLL.md`: `§3` type table, `§4.1` (`:454` becomes true once CORE-EXCL lands), new `§13.13`
   after `§13.12` (`:2606`), `§13.2` equality table (`:2278`) gains the JSON-NOEQ note. Doc-lead's
   slot.
7. `docs/llmll-ast.schema.json`: **no change**. `Json` is a type name and the `json-*` names are
   ordinary `EApp` operators; no node kind changes, no version bump from 0.10.0. Worth stating
   because the roadmap row carries a `[SPEC]` tag that reads as though it implies one.
8. `scripts/build_smoke.sh`: the §3a build-acceptance clause requires the round trip to be built and
   executed, not checked. Fourteen signatures with no codegen case is the WASI-RT defect at three
   times the scale.

No freeze conflict: the freeze ran through v0.10 (`docs/compiler-team-roadmap.md:26-31`) and is
lifted; new builtins go through the normal pipeline (`:255`).

---

## 7. Measurements taken

Recorded so no one repeats them. All at `llmll 0.14.81` unless noted.

### 7.1 The driver's JSON census

The roadmap row's "18 JSON call sites" (`docs/compiler-team-roadmap.md:58`) counts only lines
matching `json.`. The driver routes almost all JSON through two helpers at `:157` and `:163`, adding
25 `read_json` and 14 `write_json` sites. **Union: 56 lines.** Operation census: 212 object-field
reads, 26 field writes, 3 integer-indexed reads, 16 runtime type tests, 26 comprehensions over parsed
arrays, **64 distinct keys**.

Per stage, with Phase 3's five marked:

| Stage | read | write | dumps | field read | field write | iterate |
|---|---|---|---|---|---|---|
| **A intake** | 0 | 1 | 0 | 1 | 0 | 1 |
| B scope | 1 | 0 | 1 | 0 | 0 | 0 |
| C rubric | 0 | 0 | 0 | 0 | 0 | 2 |
| D extract | 1 | 1 | 0 | 5 | 1 | 3 |
| **E reconcile** | 1 | 1 | 2 | 5 | 0 | 0 |
| F core | 2 | 0 | 1 | 2 | 0 | 0 |
| G disposition | 3 | 1 | 3 | 8 | 2 | 8 |
| **G2 audit** | 3 | 1 | 2 | **54** | 7 | 15 |
| H feasibility | 1 | 1 | 0 | 12 | 0 | 3 |
| I prereg | 0 | 0 | 1 | 0 | 0 | 0 |
| **J gate** | 1 | 1 | 0 | 10 | 3 | 7 |
| K contracts | 1 | 0 | 1 | 2 | 1 | 1 |
| **L coverage** | 1 | 0 | 0 | 2 | 0 | 2 |
| M wave | 4 | 3 | 2 | 21 | 2 | 8 |
| N killmatrix | 1 | 1 | 0 | 20 | 1 | 2 |
| O writeup | 5 | 3 | 0 | 36 | 3 | 25 |
| **Phase 3 total** | **6** | **4** | **4** | **72** | **10** | **25** |

Multi-level chained reads (`x["a"]["b"]`): **7 driver-wide, 0 in Phase 3.** The four in `self_test`
and `check_extraction` are test-harness and validation code, not stage code. This is what defers
D-1.

### 7.2 Generated-project closure cost of aeson

Transitive closure over the pinned snapshot (`aarch64-osx/fb6fe6c2…/9.6.6`, `aeson-2.1.2.1`), roots
`base text containers directory process cryptohash-sha256 bytestring unix`: adding `aeson` adds
**40 packages**. `regex-tdfa` is absent from the local db so the baseline reads 23 rather than the
shipped 33; the delta is unaffected, since `regex-tdfa`'s own closure (`array`, `mtl`, `parsec`,
`regex-base`) intersects none of the 40. Compare +46 for `http-client` + `http-client-tls`, which
dropped `wasi.http.get` (`effect-response-channel-proposal.md:479-481`).

### 7.3 Match-arm payload class decides body-faithfulness

The decisive measurement against `docs/archive/professor-reviews/native-json-review.md` F2, which proposes a matchable
seven-constructor `json` datatype.

| Probe | Sum type | `def` body | Verdict |
|---|---|---|---|
| pA | `(\| A3) (\| B3) (\| C3)` | 3-arm match | **body-faithful** |
| pB | `(\| AI int) (\| BI)` | match, payload bound | **body-faithful** |
| pC | `(\| AS string) (\| BS)` | match, payload bound | **body-faithful** |
| pD | `(\| AL list[int]) (\| BL)` | match, payload bound | **body-fallback** |
| pF | `(\| AF float) (\| BF)` | match, payload bound | **body-fallback** |
| pD4 | `(\| AL4 list[int]) (\| BL4) (\| CL4 int)` | 3-arm match | **body-fallback** |
| pD3 | pD's type, **no match** | `1` | **body-faithful** |

Three side results:

- `(match s ((AL2 _) 0) …)` is rejected outright: `def 'tagl2': body contains non-core syntax — …
  unrestricted match`. Wildcard payload binding is not an escape.
- A non-exhaustive match in a `def` is a **hard error**: `non-exhaustive match in 'partial5': …
  unmatched constructors: AL5`. Matching only the scalar arms is not available.
- `FixpointEmit.hs:2500` states the exclusion as policy: "A `list` carrier or a recursive sum stays
  firewalled (the deliberate final boundary)."

**Consequence.** A seven-arm `json` has an array arm and an object arm, both list-carried, so every
exhaustive `match` on `json` in a `def` falls back. F2's exactness claim holds for the four scalar
arms and cannot be reached, because exhaustiveness drags the list arms in with them. The datatype
encoding buys the same verdict as the opaque carrier while costing seven constructors, a `match`
surface, a float arm, and a bypass argument that is unnecessary (below).

Two of F2's own claims are settled by the same probes:

- **F2's stated cost is inverted.** `admissibleDatatype` does **not** reject a sum recursive through
  a list. `sumOf` descends only `TSumType` and `TCustom` (`FixpointEmit.hs:2560-2566`), so `TList`
  returns `Nothing` and is classified "base / non-sum payload: a leaf, fine" at `:2556`. The fielded
  declaration is emitted, which is the admissible branch (`:2570-2571`). **There is no gate to
  bypass**, so the review's D1 paragraph is owed for nothing.
- **The review's D2 is discharged affirmatively.** liquid-fixpoint accepts an `FQDataDecl` whose
  field sort is the bare uninterpreted `Lst`: pD3 emits
  `data SL3 0 = [ | ctor_al3 { ctor_al3_0 : Lst } | ctor_bl3 { }]`, the solver runs, returns SAFE,
  and the function is body-faithful.

### 7.4 Equality at an opaque type

`(def same-cmd [a: Command b: Command] … (if (= a b) 1 0))` → **`body-fallback`**, and the emitted
`.fq` carries no opaque sort and no equality atom. Controls: `same-int` → body-faithful, `same-str` →
body-fallback. The fallback is caused by the argument sort, not by the `if (= …)` shape. So equality
at `Json` is not a VC hazard; it is a specification gap plus a silent degradation.

### 7.5 The `def`-form IO gate does not exist

`checkCalleeAdmissibility` admits any name for which `Map.member func builtinEnv` holds
(`TypeCheck.hs:788-789`), and `tcCoreMode` gates nothing else. Probe: a module with
`(def make-read [p: string] (wasi.fs.read p))` and a `wasi.fs` capability import passes `llmll check`.
Blast radius of closing it: **0 of 303** `def`-form functions in `examples/`, `scripts/`, `tools/`,
`compiler/test/`, `docs/`.

### 7.6 Float formatting divergence

Python `repr`: `1e-05`, `0.725`, `1e+22`, `1e+23`, `0.001`. Haskell `show :: Double -> String`:
`1.0e-5`, `0.725`, `1.0e22`, `9.999999999999999e22`, `1.0e-3`. The divergence band is wider than
exponent-range (it starts at 1e-3) and includes a mantissa difference at 1e23. Recorded because it is
what a byte-identity requirement would have cost; §1 removes the requirement, and §3.3's lexeme
storage makes the question moot for parsed numbers regardless.

### 7.7 The committed float corpus

`experiments/rfc-swarm/data/reconciliation.json` carries ten distinct decimal values, all
plain-decimal (`0.725`, `0.8655`, `0.9378`, `0.9535`, plus section numbers). No exponent-notation
number appears. The driver constructs exactly one float into JSON, `MANIFEST.json`'s `seconds`
(`:1808`), which is wall-clock-derived, therefore not reproducible under any rule, and not covered by
any digest.

---

## 8. Deferred: native JSON

None of this is on the driver's path. Each row states what it would buy and what blocks it.

| # | Item | What it buys | Status |
|---|---|---|---|
| **D-1** | **RFC 6901 pointer access.** `json-ptr : Json -> string -> Result[Json, string]` plus fused typed leaf projections; `json-set` taking a pointer with RFC 6902 §4.1 `add` semantics including the `-` append token. | Closes a real asymmetry: LLMLL's own tooling speaks JSON Pointer in diagnostics, `checkout`, and normalization (`LLMLL.md:831`, `:1712`, `:1890`, `:1955`) and JSON Patch in hole resolution (`:1892-1910`), and an LLMLL program cannot address a JSON document at all. `_checkout` walks a pointer by hand (`:1121-1128`). | **Deferred on measurement**: 7 chained reads driver-wide, 0 in Phase 3 (§7.1). Take it when a consumer needs depth, not before. The fused form is the right shape (D7 in the review); the generic-then-project pair forces an intermediate unwrap at every read site. |
| **D-2** | **Byte-compatible serialization against an external producer.** Insertion-ordered objects, CPython layout, `float.__repr__` reproduction. | Would let LLMLL-produced and Python-produced artifacts be compared bytewise. | **Deferred, and the requirement should be re-derived before it is taken.** §1 shows nothing requires it today. §7.6 records what it costs. |
| **D-3** | **Numeric re-entry beyond `int`.** `json-get-number` returning the lexeme, or a `float` projection. | The lexeme form keeps a comparison inside `Σ_auto` via STRLIT; a `float` projection would land outside it (`LLMLL.md:289`). | **Half-shipped (Rev 4).** The lexeme form SHIPPED as `json-get-number` (§2): Rev 3's deferral rested on the ported spine reading no non-integer number, which held for a stage and failed for Phase 3's acceptance clause. The `float` projection remains deferred and should stay so, since it lands outside `Σ_auto`. |
| **D-4** | **RFC 8785 (JCS) canonical serialization.** | A standard canonical form for hashing and signing. | **Deferred, and in tension with D-2**: JCS canonicalizes numbers through ECMAScript `Number::toString` and sorts keys, which is incompatible with reproducing another producer's bytes. Taking both is not possible; taking neither is the current state. |
| **D-5** | **`match` on `json` via a datatype-sort encoding.** Seven constructors whose fields are existing scalar sorts and the opaque `Lst` carrier. | Testers and selectors reflect exactly for scalar arms, and `is-ok (json-as-int v) ⟺ tag(v) = JInt` becomes a theorem of the datatype theory rather than an asserted fact. | **Blocked, not merely deferred**: every exhaustive match falls back on the list-carrying arms (§7.3), so the surface would degrade silently on every real use. Revisit only if `FixpointEmit.hs:2500`'s list-carrier firewall moves. The sort is acyclic and the declaration is accepted today (§7.3), so nothing else stands in the way. |
| **D-6** | **A general equality discipline for opaque types.** `Command`, `Response`, `Promise`, and `Json` all have unspecified equality; JSON-1 denies it for one of them. | One rule instead of four ad hoc dispositions. | **Deferred, and routed to the professor**: whether SML's eqtype discipline is the right frame given LLMLL has no class system and no constraint solving (plain `TVar` substitution at `TypeCheck.hs:98`), or whether a denial list is the terminal state. |
| **D-7** | **Descent facts and a size measure over `json`** (the review's Layer 1b), so recursive JSON walkers reach total correctness. | Would let a recursive walker discharge termination. | **Deferred, and the review's F1 is right about the channel**: injecting `jsonSize(c) < jsonSize(v)` as a ground fact is the `resultLenFact` shape FACT-AG-LEN deleted (`fact-ag-proposal.md:36`, `:238-240`), and it fails both halves of the Hoare criterion at `:70-83`. The principled version puts the fact in the accessor's effective post, which needs a **builtin-contract channel that does not exist** (`builtinEnv` carries types only; `trustedPrelude` is a name set at `TypeCheck.hs:723-732`). That channel would also pay for `list-tail` and `string-concat` and is worth a roadmap row of its own. Do not ship the injection. |
| **D-8** | **Derived codecs** (the review's Layer 2): a codec generated from a `(type Manifest …)` declaration, so after decoding no JSON remains inside the program. | The only increment that yields both low-ceremony access and a verified core. Narcissus (ICFP 2019) and EverParse (USENIX Security 2019) derive encoder/decoder pairs with machine-checked round trips **per format description**, which is a dischargeable obligation rather than a universal one over the dynamic type. | **Deferred, roadmap-worthy.** Target shape is serde's `derive`; anti-target is Elm's `Json.Decode`, whose hand-written combinator pipelines are the complaint that opened this thread. Requires compiler access to the type declaration, which is why it is native-or-nonexistent: LLMLL has no macro system and no typeclass deriving. |
| **D-9** | **A `json` literal surface.** | An embedded JSON value costs nothing to represent in a JSON-AST-primary language, which is untrue in any host where JSON literals arrive as escaped strings. | **Deferred.** If taken, give the S-expression surface a **literal token**, not a `(json-lit "…")` pseudo-builtin: a builtin whose argument must be syntactically a literal is not expressible in `builtinEnv`, which carries types only, and cannot be passed or eta-expanded like every other builtin (review F7). |
| **D-10** | **Row polymorphism**, so `v.stages[2].name` typechecks rather than returning a `Result`. | Structural access without `Result` plumbing. | **REJECTED, recorded so it is not rediscovered.** The established machinery (Wand; Rémy; Leijen 2005) is a type-system change interacting with the refinement layer, the datatype class of `Σ_auto`, and every `§11` inference rule. It should not be spent on JSON. |
| **D-11** | **Fuel-based recursive measures** as an alternative to the acyclicity firewall (Amin/Leino/Rompf, TAP 2014; Leino, LPAR 2010). | Admits recursive definitions with bounded unrolling while keeping every query terminating. | **Scope divergence, recorded only.** Fuel trades completeness for control and LLMLL has chosen completeness inside `Σ_auto`. Worth knowing that the firewall is a choice, not the only instrument, if a defined recursive measure over `json` is ever wanted. |

---

## 9. Findings routed out

Each is real at HEAD, independent of whether JSON-1 ships, and wants its own disposition.

- **R-A. `admissibleDatatype` does not descend `TList` payloads.** `sumOf` returns `Nothing` for
  `TList` (`FixpointEmit.hs:2560-2566`), so a sum recursive through a list receives a *fielded*
  `FQDataDecl` (§7.3). `LLMLL.md:452` says such a sum is "firewalled" and it is not, by that
  mechanism; the outcome is produced by the match-arm boundary instead. One shape was tested and it
  landed at `body-fallback`, so this is a stated-mechanism drift, **not** a claim that a false
  body-faithful verdict exists.
- **R-B. `LLMLL.md:454` claims the typechecker enforces `def-shell` for `wasi.*` IO.** It does not
  (§7.5). Blast radius of closing it: 0 of 303. Bundled into JSON-1's CORE-EXCL change above; listed
  here because it stands alone if JSON-1 does not ship.
- **R-C. The JSON-1 acceptance clause states no equation.**
  `driver-in-llmll-campaign.md:267-269` accepts "a round trip `json-serialize (json-parse s)`". The
  textual reading is false under any implementation. Phase 4's "reproduces a committed campaign's
  artifacts" (`:307`) has the same defect and is additionally unachievable for agent-authored
  content. Both need restating on their own terms. Independently found by
  `docs/archive/professor-reviews/native-json-review.md` F8.
- **R-D. The `list[a]` justification is false.** `docs/compiler-team-roadmap.md:58` and
  `driver-in-llmll-campaign.md:260-261` justify opacity by claiming a sealed `Json` "never enters a
  body-faithful VC, exactly as `list[a]` does not today". Measured: `(def count-them [xs:
  list[string]] (post (>= result 0)) (list-length xs))` verifies `body-faithful` and the `.fq`
  carries `constant listLen : (func(0 , [Lst; int]))`. Lists enter as an opaque sort with an
  uninterpreted projection; `list-length` is an in-`Σ_auto` measure (`LLMLL.md:959`) and
  `sortableComponent` admits `TList _` (`FixpointEmit.hs:2475`). **What is firewalled is list
  *element* reasoning.** Reached independently by this proposal at Rev 0 and by
  `docs/archive/professor-reviews/native-json-review.md` F8; two reading paths, one conclusion.
- **R-E. `sealedTypeNames` cannot seal an opaque type.** It is `Map.keys builtinAliases`
  (`TypeAdmissibility.hs:275-276`), and `builtinAliases` maps a name to a `TSumType` body, which
  `Json` does not have. Today `(def-shell takes-json [j: Json] 1)` checks clean with `Json`
  undeclared, and a program writing `(type Json …)` would shadow the builtin silently, which is the
  failure `sealedTypeNames` exists to prevent (`:268-274`).

---

## 10. Relationship to `docs/archive/professor-reviews/native-json-review.md`

That file reviews a **different draft**: a 20-builtin design with `(json-lit …)`, a `JsonTag` enum,
and `jsonTag` / `jsonSize` measures, staged as Layers 1a/1b/2. This proposal contained none of those
at any revision, so its F1, F7, F9, and Q1 target constructs that were never on this thread.

Six of its findings do land and are folded above: **F2** into §7.3 and D-5 (conclusion rejected on
measurement, two of its claims settled), **F3** into §3.5 (resolved rather than adopted, since Rev
1's serializer was already a pretty-printer), **F4** into §3.4 (dissolved by duplicate rejection),
**F5** into §3.3 (narrowed, not dissolved), **F8** into R-C and R-D, and its §5 pointer
recommendation into D-1. Its D1 and D2 are discharged by measurement (§7.3); its D4, D5, and D6 are
dissolved by §3.4 and §3.3 and need no decision.

When this file is adjudicated, `docs/archive/professor-reviews/native-json-review.md` §2 should be replaced by a pointer to §2 here,
with a note that the restatement described an earlier draft.

---

## 11. Adjudicated, 2026-08-03

Both questions this proposal put to the user are closed. Recorded here rather than deleted, because
each was a live alternative and a later reader should see it was considered.

1. **Thirteen builtins stands.** It is the largest single `builtinEnv` addition in the project's
   history, nearly three times CAP-PROC's five. Every name is a measured call site (§7.1) and the
   count does not shrink without dropping one. Accepted as scoped.

   **Reopened and re-closed at fourteen (Rev 4).** The count did grow by one, and by the mechanism
   this bullet did not anticipate: not a name added for a new call site, but a name whose exclusion
   argument was refuted. `json-get-number` shipped (`TypeCheck.hs:290`). The clause "every name is a
   measured call site" was sound; what failed was the census's boundary, which counted the field
   reads of the five stages and not the reads of the acceptance clause that grades them. A phase's
   acceptance check is a consumer of the surface even though it is not a stage. Accepted at fourteen.
2. **The acyclic seven-constructor datatype is not declared** (D-5), not even speculatively against a
   future move of `FixpointEmit.hs:2500`'s list-carrier boundary. A `match` surface that falls back
   on every exhaustive use is worse than no `match` surface, because the degradation is silent. If
   the boundary moves, D-5 is a clean increment on top of this proposal rather than a rewrite of it:
   the sort is already acyclic and the declaration is already accepted by the solver (§7.3), so
   nothing shipped here forecloses it.
