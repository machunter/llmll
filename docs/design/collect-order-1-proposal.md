---
title: COLLECT-ORDER-1 — string ordering, sort, map iteration, regex replacement and file size
status: Rev 0 draft, 2026-10-21 (user-approved for drafting; two decisions settled by the user, see "Settled decisions")
rows: STR-ORDER-1, LIST-SORT-1, MAP-ITER-1, REGEX-REPLACE-1, FS-SIZE-1 (new, PLAN); LIST-LEN-AXIOM-1 (new, DECIDE)
review: none yet
---

# COLLECT-ORDER-1 — string ordering, sort, map iteration, regex replacement and file size

## Settled decisions

The user settled two decisions on 2026-10-21. They are not open questions.

1. **`regex-replace-all` takes its arguments in the order pattern, subject, replacement.** This extends the §13.6 regex rule "pattern first, subject second". The replacement comes last.
2. **`wasi.fs.size` carries the declared fact `{v : int | v >= 0}` on its `RCode` arm.** The category is codegen-determined. The trust report discloses it.

## Restatement

Three real-program probes on v0.30.10 (csv-report, log-analyser, dup-finder) built correct programs. Each probe paid for a missing primitive in one area: there is no ordering on `string`, no sort, no listing of map keys, no regex replacement, no list reversal, and no file size. The workarounds weaken trust:

- A recursive insertion sort is termination-unverified. Six of log-analyser's callers inherit the mark.
- Tier 1 `haskell.containers` used as a sorter adds `ffi_assumptions` rows and forces `def-shell`. PBT cannot evaluate it, and it removes duplicates without a signal.
- dup-finder runs one `wc -c` process per file. Its `effect_summary` becomes `unbounded`.

This proposal adds eight builtins and one ordered-type check, in five PLAN rows and one DECIDE row. It adds no symbol to `Σ_auto` and no sealed-builtin axiom. It adds one declared response fact, and the trust report discloses it.

Two reference classes apply. The **measurement set** is the Python reference in each probe; the chosen string order equals Python's `str` order, so the probe diffs stay byte-identical. The **design-reference set** is Liquid Haskell, Dafny and F\*. Their sorted-list specifications need measures or quantified lemmas. This proposal stays out of the quantified fragment on purpose.

## Context located

1. **Probe findings** (session scratchpad, not in the repository). log-analyser wrote a stable insertion sort (count descending, then key ascending) and a `replace-all` with the arguments `(pat rep s)`. dup-finder sorted with `from-list` and `keys` through Tier 1, which removes duplicates. dup-finder sorted groups by the padded key `pad16(10^15 - size) ++ path`.
2. **`docs/design/multilangbench-scope-evaluation.md` Rev 2, "`CHAR-CODE-1`"**: `string-code-at` and `string-from-code` with a surrogate-excluding `pre`. This proposal stays consistent with it (see the order law below).
3. **`docs/compiler-team-roadmap.md`, row `CHAR-CODE-1`** (DECIDE, paired with the byte-I/O design). This batch does not depend on it.
4. **`LLMLL.md` §13**: the preamble states argument order per row. §13.2 makes `<` int-only and calls string `=` "byte-by-byte equality (UTF-8)". §13.6 gives the regex rule "pattern first, subject second", with POSIX ERE through `regex-tdfa`. §13.9 holds `wasi.fs.stat`, `wasi.fs.exists`, `wasi.fs.list-kinds` and the "Declared facts" table. §13.12 restricts map keys to `{int,string}` and says the sealed-builtin axiom set "is closed".
5. **`LLMLL.md` §5.3.3**: the measure class holds `listLen` and `strLen` as uninterpreted functions with ground range facts only. The "Outside" bullet makes `string-lower` and the `regex-*` builtins uninterpreted, so a caller falls back.
6. **`LLMLL.md` §1 and §8 (`builtin-redefinition`)**: a top-level definition that reuses a builtin name is a `check` error. A search of the 1,969 `.llmll` files in the repository found no top-level definition with any name this proposal adds.
7. **`compiler/src/LLMLL/TypeCheck.hs`**: the `builtinEnv` blocks for §13.5, §13.6, §13.12 and `wasi.fs.stat`; `checkEqDefined`, the model for the new order check; `regexBuiltins` and the literal-pattern rule; `arrayOpNames` and `inferArrayOp`, the map key gate; `fnResolveMap`, which builds the termination-assumed closure from `extractCalls` and `extractRefs`. A key function passed by name is therefore an edge in the call graph.
8. **`compiler/src/LLMLL/CodegenHs.hs`**: strings are Haskell `String`, so `compare` is code-point lexicographic. Maps are `Data.Map.Strict`. The file holds `regex_spans` and `llmll_rxTotal`, `list_append xs x = xs ++ [x]`, `wasi_fs_stat` with its shared probe, `esResultForcers`, and the reserved preamble names.
9. **`compiler/src/LLMLL/Contracts.hs`, `evalBuiltinApp`**: it has no arm for string comparison, regex or map iteration. That is why `llmll test` reports `PBTSkipped` for properties that call them.
10. **`compiler/src/LLMLL/FixpointEmit.hs`**: `mapOpNames` gates the map class. `exprToPred` reflects `list-length` and `string-length` only on a variable. `collectBuiltinAxioms` and `sealedAxiomBuiltins` implement TRUST-AXIOM.
11. **`compiler/src/LLMLL/RespFact.hs`, `respFactTable`**: the `wasi.fs.stat` `RCode` fact `v >= 0` is `FactCodegen`.
12. **`compiler/src/LLMLL/ObligationAssembly.hs`**: `wasi.fs.stat` gets `Caps {EFsRead, ENonDet}`. The clause must stay above the `wasi.` fallthrough.
13. **`compiler/src/LLMLL/Checkout.hs`, `mapEntries`**: the hole-brief builtin list for maps.

**Drift found.**

- **D1.** §13.2 calls string `=` "byte-by-byte (UTF-8)". The runtime compares character by character. The two agree on valid text. They differ for the lone surrogates that §7 says argv and directory listings can carry. Proposal: the spec says "code-point-wise", which matches the order below.
- **D2.** A `TypeCheck.hs` comment says "v1 int-only map-key gate", and `Checkout.hs` renders `map[int,v]`. The key class is `{int,string}` (§13.12). This is minor and only in comments and brief text.
- **D3.** The cost of `list-append` is not documented. That is the engineer's performance item. This proposal does not design it.

## Design proposal

### Surface

In JSON-AST each builtin is an ordinary `app` node that names the builtin.

| Builtin | Signature | Call form | Row |
|---|---|---|---|
| `string-compare` | `string string -> int` | `(string-compare a b)` gives -1, 0 or 1 | STR-ORDER-1 |
| `list-sort` | `list[a] -> list[a]`, `a ∈ O` | `(list-sort xs)` | LIST-SORT-1 |
| `list-sort-by` | `list[a] (fn [a] -> k) -> list[a]`, `k ∈ O` | `(list-sort-by xs key)`: list first, as `list-map` | LIST-SORT-1 |
| `list-reverse` | `list[a] -> list[a]` | `(list-reverse xs)` | LIST-SORT-1 |
| `map-keys` | `map[k,v] -> list[k]` | `(map-keys m)`: map first, as `map-has` | MAP-ITER-1 |
| `map-entries` | `map[k,v] -> list[(k, v)]` | `(map-entries m)` | MAP-ITER-1 |
| `regex-replace-all` | `string string string -> string` | `(regex-replace-all pattern subject replacement)` | REGEX-REPLACE-1 |
| `wasi.fs.size` | `string -> Command` | `(wasi.fs.size path)`, capability `(import wasi.fs (capability read PATH))` | FS-SIZE-1 |

**The ordered types O.** O is the smallest set that holds `int`, `string` and `bool` and is closed under pairs: if `s` and `t` are in O, then `(s, t)` is in O. An alias is in O when its expansion is in O. These types are not in O: `float`, `list`, `map`, `Json`, `bytes[n]`, `unit`, `Result`, user sum types, functions, `Command` and `Promise`. A use at a type outside O is the `check` error `order-undefined`. This mirrors `equality-undefined`.

- `float` is out because a NaN breaks a total order, and `float` has no operations.
- User sum types are out so that the spec defines the order, not the order of constructor declarations.
- `list` is out because no probe needs it. Adding it later is a monotone extension.

**Argument order.**

- `regex-replace-all` extends the regex rule of §13.6 and adds the replacement last. This is settled decision 1. It is also the order of Haskell's `subRegex` and Go's `ReplaceAllString`. Python uses `(pattern, repl, string)`, and the log-analyser probe wrote that order. All three arguments are `string`, so a transposed call type-checks. The §13.6 row and its IMPORTANT box must state the order in the same words.
- The name is `regex-replace-all`, which matches `regex-find-all`. It does not suggest a first-match-only replacement.
- `list-sort-by` takes a **key function**, as Clojure, Python `key=`, Kotlin `sortedBy` and Ruby `sort_by` do. Haskell's `sortBy` takes a comparator. The row names that difference.

### Semantics

**String order (STR-ORDER-1).** Strings are ordered lexicographically by Unicode code point. A proper prefix comes first, so `""` is least. The order is locale-free and case-sensitive.

- For any string with no lone surrogate, this order equals UTF-8 byte order. It also equals `LC_ALL=C sort` and Python's `str` order.
- A string decoded from a non-UTF-8 name carries U+DC80–U+DCFF (§7). It sorts by those code points, not by the raw bytes. Python does the same.
- The order is not UTF-16 order. Java and JavaScript sort U+10000 before U+FFFF; LLMLL sorts U+FFFF first.

Laws (spec text; none is a verifier axiom):

```
(string-compare a b) ∈ {-1, 0, 1}
(string-compare a b) = 0   ⇔  (= a b)                       ; consistent with §13.2
(string-compare a b) = - (string-compare b a)                ; antisymmetry
string order = lexicographic order on the sequences (string-code-at s i), 0 ≤ i < (string-length s)   ; CHAR-CODE-1 consistency
```

`<` stays int-only. Overloading it to strings would give `FixpointEmit` a QF-LIA operator at sort `Str`. That is the class of the FQ-RESULT-SORT-1 crashes.

**Order on O.** `int` is numeric. On `bool`, `false < true`. `string` is as above. A pair is lexicographic: compare the first components, then the second components. For every type in O, "compares equal" coincides with structural `=`. Two elements that compare equal therefore cannot be told apart.

**`list-sort`.** The result is the ascending permutation of `xs`, and duplicates are kept. Equal elements cannot be told apart, so stability is not observable and the result is unique. The runtime uses `Data.List.sort`, with O(n log n) comparisons.

**`list-sort-by`.** The result is the stable ascending permutation of `xs` by `key x`. Elements with equal keys keep their input order, so the result is a function of the input list.

- **Multi-key order** uses a pair key. The probe's "size descending, then path ascending" is `(list-sort-by gs (fn [g] (pair (- 0 (size g)) (path g))))`.
- **Descending order on a string key** is not a key. Use `(list-reverse (list-sort-by …))`. This reverses the input order of equal keys, and the row says so.
- **A comparator form is rejected.** A user comparator can be non-transitive. "Sorted" then has no meaning, and any future sortedness fact would rest on user code. A key function cannot break the order, because the order belongs to the builtin. A `list-sort-with` comparator form is a trigger-gated non-goal. It gets no row; evidence that mixed-direction string keys are needed opens it.
- The runtime uses `Data.List.sortOn` and computes each key once.

**`list-reverse`.** The result is the elements in reverse order, in O(n). It enables the idiom "prepend in a fold, then reverse once", which replaces quadratic `list-append` accumulation. That is surface only; the performance item is the engineer's.

**`map-keys` and `map-entries`.** Both return their elements in **ascending key order**, by the order on O. Keys are `{int,string}` (§13.12), and both are in O.

- **Why sorted and not insertion order.** §13.2 defines map `=` as "same key set and each value is `=`". Two maps that are `=` must give the same `map-keys`. Insertion order would make the history of the map observable and break this extensionality. The `Json` rule in §13.2 refuses equality for the same reason.
- `(map-entries m)` equals `(list-map (map-keys m) (fn [k] (pair k (map-get m k))))`.
- The map key gate of `inferArrayOp` applies. A key type outside `{int,string}` is a diagnostic on the operation.
- The runtime uses `Map.keys` and `Map.toAscList`. Both are ascending under `Ord` on `Integer` and `String`.

**`regex-replace-all`.** The definition is the probe's seven-line fold, stated as the specification:

```
(regex-replace-all p s r)  =  fold over (regex-spans p s): emit (string-slice s prev start) ++ r, prev := end;
                              then emit (string-slice s prev (string-length s))
```

- Matching is the same as `regex-spans`: leftmost-longest POSIX ERE, the same `(?i)` rule, and the same empty matches. So `(regex-replace-all "a*" "baaab" "X")` gives `"XbXXbX"`, as Python 3.7 and later give.
- The replacement is **literal text**. There are no `\1` or `$1` group references.
- The builtin is total. A computed invalid pattern returns `s` unchanged, as `regex-spans` returns `[]`.
- It joins `regexBuiltins`, so a literal invalid pattern is the `check` error `invalid-regex`.
- A **literal** replacement that holds a backslash followed by a digit gets the warning `regex-replacement-literal`. The text is inserted as written. The warning points to `regex-find-all` with the spans.
- The runtime reuses `regex_spans`, so the two builtins cannot diverge.

**`wasi.fs.size` (FS-SIZE-1).** It delivers the size in bytes of the regular file at `path` as `RCode`. It **follows** a symlink, as the probe that `wasi.fs.stat` and `wasi.fs.exists` share does. It delivers `RErr` in these cases:

- a missing path or a dangling link;
- a path that cannot be reached;
- a directory, FIFO, socket or device. So the builtin never blocks on a FIFO.

The effect label is `EFsRead`, without `ENonDet`. A size changes only with filesystem state, as for `wasi.fs.read`. The runtime reads `st_size` after `isRegularFile`, through the `unix` package's `getFileStatus`. The generated project depends on `unix` only when the program calls the builtin, as for `wasi.fs.list-kinds`.

A size needs search permission on the parent only, not read permission on the file. So a file at mode 000 has a size, while `wasi.fs.sha256` on it delivers `RErr`. The row states this, because dup-finder's skipped-file count depends on it.

### Refinement predicates and declared facts

- No new refinement-predicate vocabulary.
- One declared-fact row (settled decision 2): `wasi.fs.size`, arm `RCode`, fact `{v : int | v >= 0}`, category codegen-determined. The fact holds because a non-regular target never reaches the arm, and `st_size` of a regular file is never negative. No clamp is involved.

### Builtin signatures, soundness and Response arm

**Seven pure builtins.** They have no effect label and no Response arm. All are total, and none has a `pre`. Only `list-sort-by` can fail at run time, and only when its key function fails, as for `list-map`.

They add no **authority**: a `def-shell` can compute each one today, and two probes did. The soundness argument is therefore about the **evidence they replace**:

- They delete a recursive cycle that has no `decreases` clause. This removes entries from `trPartialFns` and from the HEADLINE-TERM-1 closure.
- They delete Tier 1 `ffi_assumptions` rows.
- They put nothing new on the solver.

**`wasi.fs.size`.**

- **Capability:** `read PATH` in the existing `wasi.fs` namespace.
- **Authority:** strictly less than `wasi.fs.read` on the same path, which reads the content. It is the same class as `wasi.fs.stat`, which reads inode metadata. It writes nothing.
- **`CAP-1-REAL`:** the capability clause is declarative today. This adds one name under the same clause, with no new class of authority.
- **`:deterministic true`:** already refused on a `wasi.fs` import (§7).
- **Response arm:** the existing `RCode`, so no new arm (CAP-PROC precedent). A byte count is a count, so the §9.7 objection to an enum on `RCode` does not apply.

Sizes inside the `wasi.fs.list-kinds` output were the alternative. That alternative is rejected. It changes the output shape of a shipped builtin and mixes listing with probing.

### Schema delta

None. Builtin calls are `app` nodes, and `docs/llmll-ast.schema.json` lists no builtin names. `schemaVersion` stays 0.13.0. The trust-report schema does not change, because the declared-fact row reuses the shape of the `wasi.fs.stat` row.

## Edge cases and degenerate inputs

### `string-compare`

1. `(string-compare "" "a")` gives -1. `(string-compare "ab" "abc")` gives -1 (prefix rule). Channel: contract (PBT through the ground arm in `evalBuiltinApp`). Cite: §13.6 new row.
2. `(string-compare "Z" "a")` gives -1. `"é"` (U+00E9) against `"z"` gives 1. The order is by code point, not collation. Channel: spec is silent on collation (intentional). Cite: STR-ORDER-1 semantics.
3. U+FFFF against U+10000 gives -1. This is the positive witness for "not UTF-16". Channel: contract (PBT). Cite: STR-ORDER-1.
4. **Positive witness for the `=` law:** `(check "cmp-eq" (for-all [a: string b: string] (= (= (string-compare a b) 0) (= a b))))` must evaluate and pass, not report `PBTSkipped`. Channel: contract (tested). Cite: the new arm in `evalBuiltinApp`.
5. An argv string that holds U+DC80 sorts after `"é"`. `LC_ALL=C sort` on the raw bytes puts it first. Channel: spec gap at Rev 0, which the new §13.6 note closes. Cite: §7, lone surrogates.

### `list-sort`

1. `[]` gives `[]`, and `[x]` gives `[x]`. Channel: contract (PBT). Cite: LIST-SORT-1.
2. `(list-sort [3 1 3])` gives `[1 3 3]`. Duplicates are kept; the FFI workaround gives `[1 3]`. Channel: contract (PBT). Cite: LIST-SORT-1.
3. `[(2,"b") (1,"z") (2,"a")]` gives `[(1,"z") (2,"a") (2,"b")]`, and `[-1 -10 5]` gives `[-10 -1 5]`. Channel: contract (PBT). Cite: order on O.
4. **Positive witness for the gate:** `(def-shell f [xs: list[list[int]]] -> list[list[int]] (list-sort xs))` gives the `check` error `order-undefined`, "'list-sort' is not defined at type 'list[int]'". `list[Json]`, `list[float]` and a user sum type give the same error. Channel: type. Cite: the new `checkOrdDefined` beside `checkEqDefined`.
5. A `def` with `post (= (list-length result) (list-length xs))` and body `(list-sort xs)` falls back with `W-BODY-FALLBACK … Refused by: app:list-sort`, at tier `asserted`. PBT can raise it to `tested`. Channel: contract fallback. Cite: §5.3.3 "Outside". This is the positive witness for the deferred `LIST-LEN-AXIOM-1`.

### `list-sort-by`

1. The probe's multi-key witness: `[(10,"b") (20,"a") (10,"a")]` with key `(pair (- 0 size) path)` gives `[(20,"a") (10,"a") (10,"b")]`. Channel: contract (PBT). Cite: LIST-SORT-1.
2. A constant key, `(list-sort-by xs (fn [x: int] 0))`, gives `xs` unchanged. This is the stability witness. Channel: contract (PBT). Cite: LIST-SORT-1.
3. A key of type `Json` gives `order-undefined` at the result type of the key. Channel: type. Cite: `checkOrdDefined`.
4. A named key function that is a recursive `def-shell` without `decreases` puts the caller into the termination-assumed closure, through `extractRefs`, as `list-map` already does. Channel: trust. Cite: `fnResolveMap` in `compiler/src/LLMLL/TypeCheck.hs`. The engineer confirms that a lambda which calls such a function is also an edge.
5. A descending string order through `list-reverse` reverses the input order of equal keys. Channel: the spec states it (intentional). Cite: LIST-SORT-1 row text.

### `list-reverse`

1. `[]` gives `[]`, and `[a]` gives `[a]`. Channel: contract. Cite: LIST-SORT-1.
2. A positive witness, `(= (list-reverse (list-reverse xs)) xs)`, evaluates under `llmll test`. Channel: contract (tested). Cite: the `evalBuiltinApp` arm on cons chains.
3. "Prepend in a fold, then reverse" equals "append in a fold". This is the PBT witness for the idiom §13.5 will print. Channel: contract. Cite: the §13.5 note.

### `map-keys` and `map-entries`

1. `(map-keys (map-empty))` gives `[]`. Channel: contract. Cite: MAP-ITER-1.
2. **Extensionality witness:** `(map-put (map-put e "b" 1) "a" 2)` and `(map-put (map-put e "a" 2) "b" 1)` both give `["a" "b"]`. Channel: contract (PBT). Cite: §13.2 map `=`.
3. An overwrite, `(map-put (map-put e "a" 1) "a" 2)`, gives the entries `[("a", 2)]`, with no duplicate key. Channel: contract. Cite: MAP-ITER-1.
4. `int` keys 10, 9 and -5 give `[-5 9 10]`, in numeric order, not string order. Channel: contract. Cite: order on O.
5. **Positive witness for the gate:** a parameter `m: map[bool,int]` with `(map-keys m)` gives the existing map-key diagnostic on the operation. Channel: type. Cite: `inferArrayOp`.
6. A body that uses `map-keys` together with `map-get` falls back whole (`Refused by: app:map-keys`), under the exact-reflection rule. It is never partly reflected. Channel: contract fallback. Cite: `mapOpNames` in `compiler/src/LLMLL/FixpointEmit.hs`. Neither new map builtin may join that list.

### `regex-replace-all`

1. No match gives `subject` unchanged. Channel: contract. Cite: REGEX-REPLACE-1.
2. `("a*" "baaab" "X")` gives `"XbXXbX"`. `("a|ab" "abc" "X")` gives `"Xc"` (POSIX leftmost-longest; PCRE gives `"Xbc"`). Channel: contract (PBT through a ground arm that uses `regex-tdfa`, already a compiler dependency in `compiler/package.yaml`). Cite: §13.6 NOTE.
3. **Positive witness for `invalid-regex`:** `(regex-replace-all "[0-9]\\d" s "")` gives the `check` error `invalid-regex` (an escaped letter). Channel: check. Cite: `regexBuiltins`.
4. **Positive witness for the new warning:** `(regex-replace-all "([0-9]+)" s "<\\1>")` gives the warning `regex-replacement-literal`. The output holds a literal `<\1>`. Channel: check (warning). Cite: REGEX-REPLACE-1.
5. A computed invalid pattern gives `s` unchanged at run time. Channel: the spec states it (total). Cite: `llmll_rxTotal`.

### `wasi.fs.size`

1. An empty regular file gives `RCode 0`. A file larger than 2³¹ bytes gives the exact count as `Integer`. Channel: contract. Cite: FS-SIZE-1.
2. A missing path, a dangling link, a directory or a FIFO gives `RErr`. The FIFO case does not block. Channel: spec. Cite: FS-SIZE-1.
3. A file at mode 000 under a readable directory gives `RCode n`, while `wasi.fs.sha256` on it gives `RErr`. Channel: the spec states it. Cite: FS-SIZE-1.
4. **Positive witness for the declared fact:** a `:step` issues `(wasi.fs.size p)` under the control tag `Sized`. A callee with `pre (>= n 0)` then discharges. The trust report shows this row:

   ```
   ≈ assumes Sized ⇒ wasi.fs.size/RCode {v : int | (>= v 0)} [codegen-determined; premise: codegen:wasi.fs.size] (ASSUMED, not proved: it rides codegen_semantics_version)
   ```

   Channel: trust (disclosed) and contract (QF-LIA). Cite: `respFactTable` in `compiler/src/LLMLL/RespFact.hs`.
5. A program that calls only `wasi.fs.size`, `wasi.fs.list-kinds` and `wasi.fs.sha256` gets the `effect_summary` `{fs.read}`, not `unbounded`. Channel: trust (effect). Cite: `compiler/src/LLMLL/ObligationAssembly.hs`. The new clause must sit above the `wasi.` fallthrough.

## Verification mapping

| Obligation | Channel | Fragment | Note |
|---|---|---|---|
| `t ∈ O` at each call site of `list-sort` and `list-sort-by` | type | none (syntactic) | `checkOrdDefined` |
| A body that calls any of the seven pure builtins | contract | outside `Σ_auto`; the body **falls back** (`Refused by: app:<name>`) | same class as `string-lower` and the `regex-*` builtins, §5.3.3 "Outside" |
| The `wasi.fs.size` `RCode` fact `v >= 0` | contract and trust | **(a) QF-LIA** | codegen-determined assumed fact, disclosed (§13.9 "Declared facts") |
| Length preservation `listLen(r) = listLen(xs)` for the sort builtins and `list-reverse` | contract | **(a) QF-LIA with the measure class**, if it is introduced | **Not introduced here.** It would be a new sealed-builtin assumed post, and §13.12 says the set is closed. Deferred to `LIST-LEN-AXIOM-1` |
| Sortedness (`∀i. r[i] ≤ r[i+1]`), permutation (`multiset(r) = multiset(xs)`), coverage of `map-keys` | none | **(c) Lean only**, and not stated | §3.4.4 predicates have no quantifiers. These are claims of the runtime semantics, under the sealed-builtin trust closure (§7, §13.6 Class A note). PBT tests them |
| The `=` law of `string-compare` | contract | PBT (`tested`) | not a solver fact |

**`Σ_auto` is unchanged.** The completeness statement of §5.3.3 stands as written, and `FixpointEmit` gets no new reflection. `collectBuiltinAxioms` gains no builtin, so the closed set of TRUST-AXIOM stays closed. The only change to the trusted base is the one declared-fact row. It goes through the existing RespFact disclosure, so no new mechanism is needed.

**How the batch removes the probe's termination mark.** A builtin call is in no SCC. So `undischargedCycleMembers` loses `insert-desc`, and `callerClosure` drops its six callers. "Proved only if a called function terminates" becomes empty for log-analyser. dup-finder's `sort-strings` can become a `def`, because FFI-UNINTERP-1 no longer applies, and its two `ffi_assumptions` rows go away.

## Affected surface

- **`LLMLL.md`**:
  - §13.2: fix the string `=` wording (D1) and add a pointer to the order.
  - §13.5: add `list-sort`, `list-sort-by` and `list-reverse`, and a note that defines O and `order-undefined`.
  - §13.6: add `string-compare` and `regex-replace-all`. Update the IMPORTANT box: the regex rule now covers five builtins, and the replacement comes last. Add the surrogate-order note.
  - §13.9: add the `wasi.fs.size` row and a Declared-facts row. List it as an `RCode` producer in the §9.7 arm table.
  - §13.12: add the `map-keys` and `map-entries` rows. The "set is closed" sentence does not change.
  - §5.3.3 "Outside": add the seven names to the uninterpreted list.
- **`docs/getting-started.md`**: the builtin table and a short sorting idiom with a pair key.
- **`compiler/src/LLMLL/TypeCheck.hs`**: `builtinEnv` entries, `checkOrdDefined`, `regexBuiltins`, and the map-key gate for the two map builtins.
- **`compiler/src/LLMLL/CodegenHs.hs`**: preamble functions, `esResultForcers` (EVAL-STRICT-1 forcers for list and string results), the reserved preamble names, and the conditional `unix` dependency.
- **`compiler/src/LLMLL/Contracts.hs`, `evalBuiltinApp`**: a ground-argument arm for each of the seven pure builtins. This is required. Without it, the PBT witnesses above report `PBTSkipped`.
- **`compiler/src/LLMLL/ObligationAssembly.hs`**: the effect `EFsRead` for `wasi.fs.size`, above the fallthrough. Mark the seven pure builtins as known pure.
- **`compiler/src/LLMLL/RespFact.hs`**: one table row.
- **`compiler/src/LLMLL/Checkout.hs`**: add the two map builtins to `mapEntries`, and fix the D2 text.
- **`compiler/src/LLMLL/FixpointEmit.hs`**: no change. The engineer adds a test that keeps both new map builtins out of `mapOpNames`.
- **Schema:** none.
- **Additions that need a soundness argument:** seven pure builtins (no new authority; they replace weaker evidence), one WASI capability name, and one codegen-determined declared fact. The sections above carry each argument.

## Risks and open questions

1. **A transposed `regex-replace-all` call type-checks.** Class: verification-ergonomics. Cite: the log-analyser probe used Python's order. Effect: makes the proposal more complex; does not block it. The order is settled (decision 1). The mitigation is the row text and the §13.6 IMPORTANT box.
2. **No length axiom, so contracts over sorted lists stay `asserted`.** Class: verification-ergonomics. Cite: §13.12, closed axiom set. Effect: matters only when a program writes contracts over list functions; no probe did. `LIST-LEN-AXIOM-1` (DECIDE) covers `list-map`, the sort builtins, `list-reverse`, `list-append` and `list-prepend` together, as one change to the trusted base.
3. **`builtin-redefinition` breaks a user program that already defines one of these names.** Class: scope. Cite: `LLMLL.md` §8. Effect: none in the repository (1,969 files searched). An external program that defines `list-reverse` fails `check` with a rename message. The CHANGELOG entry must name this.
4. **Spec drift D1 and D2.** Class: spec-drift. Cite: §13.2 and `compiler/src/LLMLL/Checkout.hs`. Effect: minor. Fix both in the same documentation pass.
5. **`list-sort-by` differs from Haskell's `sortBy`.** Class: verification-ergonomics. Effect: minor. The row text names the difference.

## Open questions for the professor

None. Each candidate either failed the negative test or was a user policy decision. These were code point against collation, key function against comparator, sorted map order, and axiom policy.

## Hand-off

- **Proposal file:** `docs/design/collect-order-1-proposal.md`, Rev 0 draft. There is no standalone review file.
- **Rows to file** (doc-lead), all `[CT][SPEC]`:
  1. `STR-ORDER-1`, PLAN: `string-compare`, the ordered types O, `order-undefined`, and the D1 wording fix.
  2. `LIST-SORT-1`, PLAN: `list-sort`, `list-sort-by` and `list-reverse`. Depends on O from STR-ORDER-1.
  3. `MAP-ITER-1`, PLAN: `map-keys` and `map-entries`, in ascending key order.
  4. `REGEX-REPLACE-1`, PLAN: `regex-replace-all` (pattern, subject, replacement), literal replacement, and the `regex-replacement-literal` warning.
  5. `FS-SIZE-1`, PLAN: `wasi.fs.size` with the declared fact `v >= 0`. Cross-reference `CAP-1-REAL` and `BYTES-READ-1`.
  6. `LIST-LEN-AXIOM-1`, DECIDE: deferred length-preservation axioms, under TRUST-AXIOM.
- **Rows closed:** none. `CHAR-CODE-1` stays open and independent. Its row gets a cross-reference to the order law.
- **Engineer summary:**
  - The five PLAN rows are independent and can ship in one release.
  - Seven pure, total builtins need `builtinEnv` entries, preamble functions, forcers, reserved names and `evalBuiltinApp` arms. They get no `FixpointEmit` reflection.
  - One new type check, `checkOrdDefined`, follows the model of `checkEqDefined`.
  - `wasi.fs.size` is one `wasi.fs` Command on the `RCode` arm with `EFsRead`, a conditional `unix` dependency, and one `respFactTable` row.
  - `regex-replace-all` reuses `regex_spans`.
  - Each positive-witness edge case above becomes a regression test.
