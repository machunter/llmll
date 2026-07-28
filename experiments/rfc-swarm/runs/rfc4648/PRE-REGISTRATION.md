# Pre-registration: RFC 4648 verification wave

Written **before any wave agent runs**. Everything in sections 1 through 10 is frozen at the
moment this file is committed. Outcomes go in Appendix A. Amendments go in Appendix B. **No text
in sections 1 through 10 is ever edited**, including when it goes against the run.

Pinned source: `00-source/rfc4648.txt`, sha256
`84e14418f795d503be5f34bf23ce4ebaa119e9ec7c9f667d8caeb111385b178f`, 1011 lines. Verified at freeze
time. All `L<n>` citations are against that file.

Toolchain: `llmll 0.14.67`, resolved at
`/Users/burcsahinoglu/Documents/llmll/compiler/.stack-work/install/aarch64-osx/fb6fe6c2.../9.6.6/bin/llmll`.
Prover: `liquid-fixpoint`.

Upstream artifacts this document takes as given, by the shas recorded in `MANIFEST.json`:
`01-scope/scope.md`, `02-rubric/rubric.md`, `06-disposition/inventory-dispositioned.json`,
`07-feasibility/FINDINGS.md`.

---

## 0. The rule this document is built to serve

A pre-registration that is only consulted when it agrees with the result is a decoration. Three
commitments give this one force:

1. **Sections 1 through 10 are immutable.** If an instrument registered here turns out to be
   defective, the response is an amendment in Appendix B stating the defect, showing the argument,
   and leaving the adjudication to a human. It is not a quiet reinterpretation and it is not a
   deletion.
2. **A run that reports fewer filled holes, each failure witnessed, is a better run than one that
   reports more by weakening contracts.** Section 2.2 states this as an acceptance criterion rather
   than as an aspiration, because the incentive runs the other way.
3. **No ratio ceiling is introduced.** On the first run of this pipeline an exclusion-ratio ceiling
   fired and the instrument, not the target, was wrong: every clause in the timing/transport class
   is excluded by the definition of the class, so the threshold was breached by class assignment
   before any scoping judgment was made. The ratio measured the RFC's genre composition. That
   failure is not repeated here. **Every threshold registered below is a trigger on a mechanism,
   not a trigger on a proportion.**

---

## 1. What is being measured, and the one number that is not a coverage figure

The deliverable is a set of LLMLL modules, each carrying one contracted hole, filled concurrently
by wave agents. What the run produces is **detection yield**: defects found and fixed, each with a
concrete witness.

Stated once, plainly, so section 3 can be read against it:

> **Agreement between two formalizations is not evidence.** Two independently authored contracts
> that agree could be wrong in the same way, and shared training makes that the likely case rather
> than the unlikely one. Concordance is not reported. Absence-of-failure is not reported. A metric
> that rises when contracts get weaker is worse than no metric, and the mutant-kill requirement in
> section 2.1 exists precisely to make the headline number fall when contracts weaken.

---

## 2. Acceptance criteria

### 2.1 A successful fill

A hole is **FILLED** only when all seven conditions hold. They are conjunctive. Partial
satisfaction is `UNFILLED`, with the failing condition named.

| # | Condition | Instrument |
|---|---|---|
| F1 | The fill commits | `llmll patch <file>.ast.json <patch>.json --json` returns `{"result":"PatchSuccess"}`, exit 0 |
| F2 | The module verifies under the strict core | `llmll verify <file> --strict-verified-core` exits 0 and prints `SAFE (liquid-fixpoint)` |
| F3 | Every contracted function in the module is body-faithful, with zero fallbacks | the `body-faithful:` line of F2 names every contracted function in the file; no `erBodyFallback`, no `--strict-verified-core: refuted` |
| F4 | Every `post` clause of the hole's function records SMT evidence | `<file>.verified.json` shows `display_level.level == "verified"` and `prover == "liquid-fixpoint"` for each `post` |
| F5 | Every `pre` and `post` clause carries a `:source` citing an `L<start>-<end>` range of the pinned sha, and the cited range contains the text the clause claims | mechanical check of the `sources` / `source` fields in `<file>.verified.json` against `00-source/rfc4648.txt` |
| F6 | **Every mutant pre-registered for this hole in section 7 is refuted** | for each mutant file: `llmll verify <mutant> --strict-verified-core` exits 1 and prints `refuted: <fn>` naming a function of this hole |
| F7 | The contract is not satisfied by a trivial body | `llmll verify <file> --strict-verified-core --weakness-check` prints `No spec weaknesses detected`; a reported weakness is recorded in Appendix A and downgrades the hole to `FILLED-WEAK` |

**F6 is the condition that makes the other six mean anything.** Stage H established the
generalization this rests on: range and injectivity clauses do not refute the base32 bit-order bug,
because an LSB-first packing is exactly as injective as an MSB-first one. A contract over a finite
encoding is decorative unless it pins values rather than bounding them. F6 is how that is checked
per hole rather than assumed.

**Prohibited route to F6.** Weakening a mutant so that it is refuted by a contract that would not
refute the real bug. Every mutant is fixed by section 7 before the wave runs, and a mutant's bug
statement is part of the frozen text. An agent that believes a registered mutant is malformed
files an amendment; it does not edit the mutant.

**Prohibited route to F2.** Weakening a `post` clause so the body verifies. If an agent concludes
that a contract as registered cannot be discharged, the outcome is `UNFILLED` with the reason
recorded, or an amendment. It is not a relaxed contract with a green result.

### 2.2 A successful run overall

The run is **successful** when all of the following hold. Note that none of them is a count of
filled holes.

- **R1.** Every hole in the frozen set (section 4) has a terminal state recorded in Appendix A:
  `FILLED`, `FILLED-WEAK`, or `UNFILLED` with the failing condition from 2.1 named.
- **R2.** Every `UNFILLED` hole carries a witness: the exact command, its exit code, and the
  diagnostic text (constraint id, SMT counterexample, or type error). "It did not verify" is not a
  witness.
- **R3.** No contract registered in the skeleton was weakened after freeze. Checked mechanically:
  the `pre` / `post` clause set of each contracted function at the end of the run is compared to
  the frozen skeleton, and any difference appears in Appendix B as an amendment or the run fails.
- **R4.** The defect ledger (section 3.2) is complete: every defect found carries a witness and a
  disposition.
- **R5.** Sections 1 through 10 of this file are byte-identical to their frozen state.
- **R6.** Every exclusion added during the run cites exactly one barrier from the closed list, and
  an exclusion fitting none of them halted the run rather than being absorbed.

**Stated as directly as it can be:** a run that reports 11 of 16 holes filled, five failures each
carrying a witness, and three defects found is a **successful run**. A run that reports 16 of 16 by
relaxing three postconditions is a **failed run**, and R3 is the check that distinguishes them. The count of filled holes is a reported number, not an acceptance criterion.

### 2.3 What does not count, in either direction

- A hole that reaches `SAFE` without `--strict-verified-core` is not filled.
- A hole whose evidence is `tested` (property-based) or `asserted` rather than `verified` is not
  filled. PBT lift under the `check` rule is not admitted as F4 evidence.
- The 28 test vectors at L652-713 and the 3 worked examples at L623-648 are **validation
  instances**. They are reported in their own column with their own label, never summed with
  proved clauses, per scope.md section 7 item 4.
- The empty input remains **uncovered, not vacuous** (scope.md Decision 4). `BASE64("") = ""` and
  its four siblings at L652, L666, L687, L701 are recorded as a gap.

---

## 3. The measurement set

Exactly these numbers are reported. Each is stated with its denominator. Nothing else is reported
as a headline figure.

### 3.1 The reported quantities

| # | Quantity | Denominator | Notes |
|---|---|---|---|
| M1 | Holes `FILLED` | 16 (the frozen hole set, section 4) | `FILLED-WEAK` counted and shown separately, never merged into `FILLED` |
| M2 | Mutants refuted | the total registered in section 7, fixed at freeze | a mutant that verifies SAFE is a **defect in the contract**, enters the ledger, and is fixed by strengthening |
| M3 | Encoded rows carried by at least one `FILLED` hole | 39 (rows dispositioned `Encoded` in `inventory-dispositioned.json`) | not a coverage ratio with a threshold; a reported pair `x / 39` |
| M4 | Characteristic-core rows carried | 22 (the 23 core rows minus A1, see section 8) | reported as `x / 22` **with A1 named in the same sentence** as the uncovered 23rd |
| M5 | Class-stratified fills | C1: 2 holes, C2: 5 holes, C3: 9 holes | reported per class; a class at zero is a finding regardless of the total |
| M6 | **Detection yield** | no denominator | count of defects found and fixed, each with a witness. This is the headline |
| M7 | Semantic retries consumed | per hole, budget 3 (section 5) | |
| M8 | Protocol conflicts and protocol retries | per hole, counted separately from M7 | section 6 |
| M9 | Max concurrent live checkout tokens (overlap factor) | measured, section 6.4 | if `< 2`, the concurrency result is `NOT MEASURED`, not `0 conflicts` |
| M10 | Human interventions after freeze | budget 0 for content, section 5.3 | each one enumerated |
| M11 | Validation instances evaluated | 28 test vectors, 3 worked examples | separate column, separate label, never added to M3 or M4 |
| M12 | Rows dispositioned out, by barrier | 20, by `B3` 1 / `B5` 4 / `B7` 8 / `B8` 7 | reported as part of the headline matrix, not as an appended disclaimer |

### 3.2 The defect ledger (M6)

A **defect** is one of exactly three kinds. Each entry carries a witness, and a defect without a
witness is not an entry.

| Kind | What it is | Witness |
|---|---|---|
| `D-CONTRACT` | a registered contract fails to refute its own registered mutant | the mutant file, and its `SAFE` verdict that should have been a refutation |
| `D-FILL` | a fill fails verification | the constraint id and the branch (`then-branch` / `else-branch` / `implementation`) from the `llmll verify` diagnostic |
| `D-INSTRUMENT` | something registered in this document is defective | the argument, plus the amendment number in Appendix B that adjudicates it |

`D-INSTRUMENT` is the entry that makes commitment 1 of section 0 operational. Filing one is a
correct outcome, not a failure.

### 3.3 Explicitly not reported

Named here so their absence from the writeup is a commitment rather than an oversight:

- **Concordance** between any two formalizations, extractions, or agents. Stage E's Cohen's kappa
  of 0.8057 is an input to the reconciled inventory. It is not evidence about RFC 4648 and it is
  not carried into the writeup as a result.
- **Absence of failure.** "No counterexample found" is not reported as an outcome.
- **Any coverage ratio with a threshold attached.** M3 and M4 are reported as pairs, and no
  proportion computed from them triggers anything.
- **Any exclusion ratio.** Retired by amendment on the first run of this pipeline and not
  reintroduced. The barrier-list check (R6) replaces it: the failure worth catching is an exclusion
  nobody can justify, not an exclusion count.
- **Clause counts as a difficulty measure.** scope.md section 1 already records that what is inside
  the boundary is finite rather than merely decidable: "the base64 alphabet is injective" is
  enumeration over 64 constants. The clause count is not presented as a difficulty figure.

---

## 4. The hole set, and the rule that fixes it

### 4.1 The derivation rule

The hole set is derived from the 39 rows dispositioned `Encoded`, by this rule, which is fixed
before the skeleton is authored:

> One hole per (codec, obligation shape) pair, where obligation shape is one of: **alphabet table**,
> **final-quantum character count**, **final-quantum pad count**, **quantum packing relation**,
> **fill-bit verdict**, **symbol classification**, **decode decision**, **order preservation**.
> Every `Encoded` row is assigned to at least one hole. A hole's class is the class of the
> characteristic-core row it carries, or of its rows where they are uniform.

Applying that rule to the dispositioned inventory yields **16 holes**. The table below is the
frozen hole set.

### 4.2 The frozen hole set

| Hole | Module file | Class | Rows carried | Core rows |
|---|---|---|---|---|
| H01 | `base64-alphabet.llmll` | C3 | A13, A17, A18 | A18 |
| H02 | `base64url-alphabet.llmll` | C3 | A28, A29 | A29 |
| H03 | `base64-tail-chars.llmll` | C3 | A19, A23, A24, A25 | A23, A24, A25 |
| H04 | `base64-tail-pads.llmll` | C3 | A2, A22, A23, A24, A25 | A2, A23, A24, A25 |
| H05 | `base64-packing.llmll` | C2 | A15, A16, A21 | A16, A21 |
| H06 | `base64-fill-verdict.llmll` | C2 | A9, A10 | A9 |
| H07 | `base64-symbol-class.llmll` | C1 | A4, A6 | A4 |
| H08 | `base64-decode-decision.llmll` | C1 | A4 | A4 |
| H09 | `base32-alphabet.llmll` | C3 | A30, A35, A36 | A36 |
| H10 | `base32hex-alphabet.llmll` | C3 | A49, A50 | A50 |
| H11 | `base32hex-order.llmll` | C2 | A48 | none |
| H12 | `base32-tail-chars.llmll` | C3 | A37, A41, A42, A43, A44, A45 | A41, A42, A43, A44, A45 |
| H13 | `base32-tail-pads.llmll` | C3 | A2, A40, A41, A42, A43, A44, A45 | A2, A41, A42, A43, A44, A45 |
| H14 | `base32-packing.llmll` | C2 | A32, A33, A34, A39 | A33, A34, A39 |
| H15 | `base16-alphabet.llmll` | C3 | A51, A55, A56 | A56 |
| H16 | `base16-packing.llmll` | C2 | A54 | A54 |

All 39 `Encoded` rows are assigned. All 22 encoded characteristic-core rows are assigned. Class
distribution: C1 = 2, C2 = 5, C3 = 9.

### 4.3 Deviation from 16

If the authored skeleton has a different hole count, the deviation is recorded in Appendix A with
its reason before the wave runs. A count outside the band **14 to 20** is investigated as a
possible boundary violation rather than accepted as a better-than-expected result, following the
discipline scope.md section 6 applies to the clause count. **This is a prompt to investigate, not
a ratio ceiling and not a STOP.**

### 4.4 Two architectural constraints inherited from Stage H, fixed here

Both are consequences of measured toolchain behavior, not preferences.

- **C-A. No hole computes a bit slice.** `*`, `/` and `mod` are outside the strict core; a `def`
  body containing one is rejected at typecheck, and in a contract clause it forces
  `erBodyFallback`, which `--strict-verified-core` refuses. Extracting the high six bits of an
  octet is `o / 4` and has no admitted form. Every packing hole (H05, H14, H16) therefore states
  the **packing relation over quantum components** (`octet0 = 8*s0 + s1-high`, with coefficients
  unrolled into binary `+`), never the slicing function. A quantum is never modeled as a single
  packed integer, because a 40-bit quantum's weights reach 2^35 and unrolling is infeasible.
- **C-B. One hole per file, and each file is self-contained.** A user-defined callee needs
  pre-existing body-faithful evidence to be admissible in a `def` body, same-file evidence is not
  available during the run that would produce it, and cross-module `(open ...)` did not resolve.
  Shared ADTs are therefore **redeclared per file** rather than imported. This is also what makes
  the concurrency prediction in section 6 sharp, and section 6.2 states the coupling.

---

## 5. Process budgets

### 5.1 Semantic retries: 3 per hole

A **semantic retry** is an attempt that failed on the content of the fill. Exactly these outcomes
consume the budget:

- `llmll patch` returns `PatchVerifyError` (the fill violates a contract)
- `llmll patch` returns `PatchTypeError` (the fill does not typecheck)
- `llmll verify --strict-verified-core` returns non-zero for a reason other than a protocol conflict
- a fill verifies but fails F3 (fallback or not body-faithful) or F6 (a registered mutant survives)

**Budget: 3 per hole.** On exhaustion the hole is `UNFILLED` with the last witness recorded. It is
not re-contracted, not narrowed, and not moved to `def-shell` to escape the strict core. A fill
that reaches `contract-checked` via `def-shell` does not satisfy F2 and does not rescue the hole.

### 5.2 Protocol retries: counted separately, capped at 10 per hole

A **protocol retry** is an attempt that failed on concurrency, with no bearing on the content of
the fill. Exactly these outcomes are protocol retries:

- `llmll checkout` exits 1 with `hole at <pointer> is already checked out`
- `llmll patch` returns `{"result":"PatchAuthError","message":"obligation context is stale — re-checkout required (source file changed)"}`, exit 1

**These never consume the semantic budget.** That separation is the point of registering them
apart: contention is a property of how the wave was scheduled, and if it could eat an agent's error
budget then a scheduling accident would show up in the writeup as a verification failure.

**Cap: 10 per hole,** to bound wall-clock. Reaching 10 on any hole is itself a finding and is
reported under M8, because the recovery cycle in section 6.3 is three commands and ten failures of
it indicates the isolation reasoning in 6.2 is wrong.

### 5.3 Human interventions after freeze: 0 for content

**Zero interventions that touch content are permitted.** Exactly three mechanical classes are
permitted, and each is enumerated individually in Appendix A with a timestamp:

1. Killing a hung process or a wedged solver invocation.
2. Recovering from a host or filesystem failure (disk full, permissions, an interrupted write).
3. Re-running a previously issued command verbatim, with no argument changed.

Anything else, including editing a contract, editing a mutant, re-scoping a hole, adjusting a
budget, or reinterpreting a criterion in section 2, is an **amendment** under section 9. It is
appended, it states its argument, and a human adjudicates it. It is never applied silently.

---

## 6. The numeric concurrency trigger

### 6.1 The mechanism, measured before freeze

The trigger below is grounded in behavior measured on `llmll 0.14.67` at freeze time, not inferred
from documentation. The transcript is in Appendix C. The three facts that matter:

1. **The lock is per-pointer.** Two agents checking out `/statements/0/body` and
   `/statements/1/body` of the same file both succeed, exit 0.
2. **The staleness check is per-file.** A checkout token records a `source_hash` over the **whole
   file**. When one agent commits, every other live token in that file is invalidated, and its next
   `llmll patch` returns `PatchAuthError` with `obligation context is stale — re-checkout required
   (source file changed)`, exit 1. Measured directly: agent B committed to `/statements/1/body`,
   after which agent A's patch to `/statements/0/body` failed, despite A's hole being untouched and
   still `hole-named`.
3. **A stale lock does not self-clear.** Re-checking out the same pointer while holding the stale
   token returns `hole at <pointer> is already checked out`. The token must be explicitly released
   first, or wait out the 3600-second TTL.

The consequence, stated as a formula because the wave design depends on it:

> For a file holding `k` holes worked concurrently, at most one commit per round succeeds and the
> other `k - 1` agents take a `PatchAuthError`. **Expected protocol conflict rate per commit round
> is `(k - 1) / k`.** For a single 16-hole file that is 93.75%, and the wave serializes.

### 6.2 The wave configuration

- **Agents: 8 concurrent wave agents**, over a work queue of the 16 holes.
- **Isolation: one hole per file** (constraint C-B, section 4.4). Every hole has its own
  `.ast.json` and its own `<name>.llmll-lock.json`.
- **Therefore `k = 1` for every file, and the predicted protocol conflict rate is exactly 0.**

### 6.3 The registered triggers

**Trigger A (isolation failure).** *Any* protocol conflict, at any point in the wave, is a
**finding**. Not a rate, not a threshold: one. The prediction is exactly zero, derived from a
measured mechanism, so a single occurrence falsifies the isolation reasoning in 6.2 and is worth
more than a tolerance band would be. Reported with the pointer, the exact diagnostic string, both
agent ids, and the file.

**Trigger B (contention within a file).** If the authored skeleton places `k > 1` holes in any
file, that file's predicted conflict rate becomes `(k - 1) / k` per commit round, and:

- the predicted rate is recorded in Appendix A **before** the wave runs, per file;
- a **measured rate exceeding the prediction** is a finding (the mechanism is worse than modeled);
- a **measured rate of 0 where the prediction is positive** is a finding, and is investigated as
  evidence that the agents did not in fact run concurrently, per 6.4.

**Trigger C (budget breach).** Any hole reaching the cap of 10 protocol retries (section 5.2) is a
finding.

### 6.4 The guard that keeps Trigger A from being vacuous

A design predicting zero conflicts cannot, by itself, distinguish "isolation worked" from
"concurrency never happened". So one further quantity is registered:

> **M9, the overlap factor:** the maximum number of wave agents holding a live checkout token
> simultaneously, sampled by polling every `*.llmll-lock.json` at 5-second intervals for the
> duration of the wave, counting entries whose `timestamp + ttl` is in the future.

**If the measured overlap factor is less than 2 at every sample, the concurrency result is reported
as `NOT MEASURED`.** It is not reported as "0 conflicts", and it is not reported as a successful
concurrency outcome. A serialized run that reports zero conflicts is reporting nothing.

The target overlap factor is 8, matching the agent count. An overlap factor of 2 through 7 is
reported as measured with the shortfall noted, and is not itself a finding: the queue empties
unevenly and partial overlap is expected near the end of the wave.

---

## 7. The mutant-class taxonomy

Per clause class, with the historically attested bugs of this protocol as mandatory members. Every
mutant listed as mandatory in 7.2 **must** be authored and **must** be refuted for its hole to
satisfy F6.

A mutant is one file, identical to the hole's module except for the named perturbation, carrying a
plausible bug rather than an arbitrary one. A mutant that no competent implementer would write does
not test the contract.

### 7.1 The families, by class

**C1, state transition** (H07, H08)

| ID | Family | What it perturbs |
|---|---|---|
| M-C1-a | **Cell substitution** | the action in one (profile x class) cell of the decision table |
| M-C1-b | **Converse collapse** | makes an action reachable from a cell it must not be reachable from; tests whether the contract states the converse rather than only the forward direction |
| M-C1-c | **Class merge** | collapses `Pad` into `NonAlphabet`, the two-way flag scope.md section 4(a) rejects |
| M-C1-d | **Profile drop** | ignores the leniency flag, giving one behavior under both modes |

**C2, arithmetic invariant** (H05, H06, H11, H14, H16)

| ID | Family | What it perturbs |
|---|---|---|
| M-C2-a | **Positional-weight transposition** | MSB-first replaced by LSB-first in the packing relation |
| M-C2-b | **Coefficient perturbation** | one weight in the packing equation (8 to 4, 32 to 16) |
| M-C2-c | **Width-for-value substitution** | carries the fill region's width but not its value; the failure mode scope.md section 4(b) names, and the one that makes L257-258 defend against L765-768 rather than describe a field |
| M-C2-d | **Conservation break** | violates `8*rem + fill = 6*chars` at one residue |
| M-C2-e | **Order-seam break** | a table breaking monotonicity at exactly one seam (H11 only) |

**C3, length or format** (H01, H02, H03, H04, H09, H10, H12, H13, H15)

| ID | Family | What it perturbs |
|---|---|---|
| M-C3-a | **Table entry perturbation** | one value-to-character entry |
| M-C3-b | **Table substitution** | a whole-alphabet swap between variants |
| M-C3-c | **Case-tuple transposition** | swaps the (chars, pads) tuples of two residues |
| M-C3-d | **Pad-count off-by-one** | one residue's pad count, plus or minus one |
| M-C3-e | **Boundary padding** | emits padding on an exact-boundary quantum, violating A23 / A41 |
| M-C3-f | **Pad-character substitution** | a character other than `=`, violating A22 / A40 |

No families are registered for C4, C5 or C6: no row of those classes is dispositioned `Encoded`.

### 7.2 The mandatory attested members

Each is a bug this protocol has actually suffered, sourced either to the RFC's own text saying why
the rule exists or to shipped implementation behavior. **A hole whose mandatory mutant is not
authored, or whose mandatory mutant verifies SAFE, is not `FILLED`.**

| ID | The bug | Attestation | Family | Holes it must be run against |
|---|---|---|---|---|
| **H-1** | Decoder silently discards characters outside the base alphabet, regardless of profile | The liberal-decoder behavior L200-206 was written to override. L754-760 names it as "a covert channel that can be used to 'leak' information", usable "to avoid a string equality comparison or to trigger implementation bugs". Shipped as the **default** in Python's `base64.b64decode` (`validate=False`) | M-C1-a | H07, H08 |
| **H-2** | Decoder accepts non-zero pad bits, in the usual partial form where only one residue is checked | L253-256 and L259-263: multiple encoded strings then decode to the same octets. L765-768: the non-significant bits "may be abused to leak information or used to bypass string equality comparisons". The clause L257-258 exists because decoders do this | M-C2-c | H06 |
| **H-3** | base32 quantum packed least-significant-bit first | L438-442 states MSB-first at MUST strength for exactly this reason. Stage H established that this bug survives every range and injectivity clause and is refuted only by the positional weight equation | M-C2-a | H14 |
| **H-4** | Table 3 (base32) used where Table 4 (base32hex) is required | The two variants differ in nothing but the table (A50). L516-517 names NSEC3 as the consumer, and NSEC3 is where the substitution has real consequences. It breaks sort order at the seam value 25 (`Z`, 0x5A) to value 26 (`2`, 0x32) | M-C3-b, M-C2-e | H10, H11 |
| **H-5** | Final-quantum case transposition: the one-octet remainder given three significant characters and one pad, the two-octet remainder two and two | Contradicts the RFC's own vectors: L654 `BASE64("f") = "Zg=="` becomes `"Zg="`, L656 `BASE64("fo") = "Zm8="` becomes `"Zm8=="`. Same shape at L668 and L670 for base32 | M-C3-c | H03, H04, H12, H13 |
| **H-6** | base64url emits `+` and `/` at values 62 and 63 | Section 5 (L351-353) exists to give an alphabet safe in URLs and filenames; Table 2 differs from Table 1 at exactly those two indices, so this is the whole variant. The derived clause the variant exists for is "never emits `+` or `/`" | M-C3-a | H02 |

### 7.3 Minimum mutant count per hole

Each hole carries **at least two** mutants: every mandatory one from 7.2 that names it, plus at
least one further family from its class in 7.1. A hole with no mandatory mutant (H01, H05, H09,
H12, H15, H16) carries at least two from its class families.

The rationale is the Stage H result: a single mutant tests a single axis, and a contract can pin
one axis while leaving the neighboring one bounded rather than fixed.

---

## 8. The pre-existing STOP, registered rather than absorbed

`06-disposition/inventory-dispositioned.json` records **A1** (L161-163, "Implementations MUST NOT
add line feeds to base-encoded data") as `class C3`, `core: true`, `disposition: Dispositioned out`,
`barrier: B7`. Stage G's own instruction is that no core row may be dispositioned out, and that if
one must be, the pipeline STOPs and the target is re-scoped rather than re-graded. Stage G reported
it correctly instead of reclassifying it to make the gate pass.

It is registered here rather than resolved, because resolving it is not this stage's call:

- **A1 is the only core row not dispositioned `Encoded`.** The other 22 are all `Encoded`.
- The clause's positional form (line feeds after a specific number of characters) needs the output
  as a positioned character sequence, which scope.md section 3 refuses to import and section 7 item
  3 names in advance as scope creep.
- The surviving flat form (LF is not in the encoder's output alphabet) is true by construction:
  every position of a quantum's output tuple is filled by `TABLE[v]` or by the pad constant 0x3D,
  so the model admits no constructor placing 0x0A anywhere, and **no mutant can exercise the row**.
  Under Stage G rule 2 that is `B7` and carries no verification evidence.

**Pre-committed handling.** M4 is reported as `x / 22` **with A1 named as the uncovered 23rd core
row in the same sentence**, never as `x / 23` and never as a silently reduced denominator. If a
human adjudicates the STOP differently before the wave runs, that adjudication is Appendix B
amendment 1 and this section is not edited.

---

## 9. Amendment procedure

An amendment is filed when something registered in sections 1 through 10 is found defective. It is
appended to Appendix B and never applied by editing the frozen text.

Each amendment states, in this order:

1. **The defect.** Which instrument, and what it actually measures as opposed to what it was
   registered to measure.
2. **The argument.** Why this is a defect in the instrument rather than a result the instrument
   correctly reports. The bar is the one the retired exclusion-ratio ceiling met: the instrument
   was breached by class assignment before any judgment it was meant to test had been made, so it
   measured the RFC's genre composition rather than the verifier's reach.
3. **What it would take to be wrong.** The reading under which the instrument is fine and the
   result stands.
4. **The proposed disposition**, and space for a human adjudication with a name and a date.

An amendment filed to make a failing run pass, without argument (2) reaching the bar in (3), is
itself recorded as a `D-INSTRUMENT` defect against this pre-registration.

---

## 10. The report format

The writeup's headline is **the scope matrix including the OUT column**, per scope.md section 7. It
is not a set of numbers with the matrix appended as a disclaimer.

Fixed obligations on the writeup:

- The `SPLIT` rows are reported as splits, **both halves in the same sentence**. Reporting a SPLIT
  row as a satisfied clause is pre-committed scope creep (scope.md section 7 item 2). The rows the
  scope matrix marks `SPLIT` are **three**: L200-203 (per-symbol classifier IN, existential over an
  unbounded string OUT), L253-256 with L259-263 (per-quantum collision IN, stream-level uniqueness
  OUT), and L519-521 (per-symbol monotonicity IN, string lifting OUT and false unrestricted). See
  10.1.
- No top-level statement of the form "BASE-N is injective" or "decode(encode(x)) = x" for unbounded
  `x` appears. The segmentation and concatenation induction is not attempted and is not axiomatized
  to make a top-level statement typecheck. It is simply not among the results.
- The profile qualifier is not dropped from the three "unless the referring specification states
  otherwise" clauses (L161-163, L182-184, L200-203), nor the case-discipline qualifier from base16
  and base32 results.
- The L519-521 sort-order property is never quoted without its equal-length restriction. The
  unrestricted form is false, and the counterexample is on the record: base32hex of the one octet
  `0x00` is `00======` and of the two octets `0x00 0x00` is `0000====`; `=` is 0x3D and sorts above
  the digits, so the encodings sort opposite to the octet sequences.
- Validation instances (28 test vectors, 3 worked examples) appear in a separate column with a
  separate label. "We checked 28 test vectors" is not presented as verification.
- The empty input is listed as an uncovered gap, not as vacuously satisfied.

### 10.1 A discrepancy in an upstream artifact, registered rather than reconciled

`01-scope/scope.md` disagrees with itself about how many rows are `SPLIT`. Its matrix marks
**three** (L266, L270, L280 of that file). Its prose says **four**, twice: L293, "roughly a dozen
clauses fully IN, four SPLIT", and L308, "Four rows have a decidable core and an undecidable
clause."

This is recorded here, before the wave, rather than settled by picking whichever count makes a
later sentence come out even. Resolving it would mean either promoting some fourth row to `SPLIT`
(which would be inventing a scope verdict after the fact, the thing scope.md was frozen to prevent)
or amending the prose of a frozen upstream artifact. Neither is this stage's call.

**Pre-committed handling.** The writeup reports the three rows the matrix marks, and states the
discrepancy in the same place. If a human adjudicates a fourth row into `SPLIT` before the wave
runs, that is an Appendix B amendment and this section is not edited.

---

# Appendix A: outcomes

*Empty at freeze. Appended during and after the run. Nothing here edits sections 1 through 10.*

| Field | Value |
|---|---|
| Freeze timestamp | 2026-07-27 |
| Skeleton hole count at freeze | *to be recorded before the wave runs* |
| Deviation from 16, and reason | *to be recorded* |

## A.1 Per-hole outcomes

*One row per hole: state (`FILLED` / `FILLED-WEAK` / `UNFILLED`), failing condition if any, witness,
semantic retries consumed, protocol retries consumed, mutants authored, mutants refuted.*

## A.2 Measurement set results

*M1 through M12, each with its denominator as registered in section 3.1.*

## A.3 Defect ledger

*M6. One row per defect: kind (`D-CONTRACT` / `D-FILL` / `D-INSTRUMENT`), description, witness,
disposition.*

## A.4 Concurrency measurements

*Overlap factor samples, per-file predicted and measured conflict rates, and every protocol conflict
with its pointer, diagnostic string, and agent ids.*

## A.5 Human interventions

*Each one enumerated with a timestamp and its permitted class from section 5.3.*

---

# Appendix B: amendments

*Empty at freeze. Each amendment follows the four-part form in section 9 and carries a human
adjudication.*

---

# Appendix C: the pre-freeze concurrency transcript

Recorded so that the prediction in section 6 is auditable rather than asserted. Run on
`llmll 0.14.67` against a two-hole scratch module, before freeze.

```
# per-pointer lock, disjoint pointers both succeed
$ llmll checkout t.ast.json /statements/0/body --json   -> exit 0, token 4c84972807bc...
$ llmll checkout t.ast.json /statements/1/body --json   -> exit 0, token 7d23cc4c4e4f...
  both tokens record the same source_hash 95c57e0e989c..., ttl 3600

# same pointer twice: lock contention
$ llmll checkout t.ast.json /statements/0/body --json
  hole at /statements/0/body is already checked out
  exit 1

# agent B commits to its own hole
$ llmll patch t.ast.json patchB.json --json
  {"result":"PatchSuccess","reuse_suggestions":[],"statements":2}
  exit 0

# agent A's hole is untouched (still hole-named) and its token is still live,
# but the whole-file source_hash has moved
$ llmll patch t.ast.json patchA.json --json
  {"message":"obligation context is stale — re-checkout required (source file changed)",
   "result":"PatchAuthError"}
  exit 1

# the stale lock does not self-clear
$ llmll checkout t.ast.json /statements/0/body --json
  hole at /statements/0/body is already checked out
  exit 1

# recovery is three commands
$ llmll checkout t.ast.json --release 4c84972807bc...   -> {"released":true}, exit 0
$ llmll checkout t.ast.json /statements/0/body --json   -> exit 0, fresh source_hash 2eb6123ff204...
$ llmll patch t.ast.json patchA2.json --json            -> {"result":"PatchSuccess"}, exit 0
```

Lock state lives in `<basename>.llmll-lock.json` beside the `.ast.json`, as a `tokens` array whose
entries carry `pointer`, `token`, `timestamp`, `ttl` (3600), and `source_hash`. That file is what
M9 samples.
