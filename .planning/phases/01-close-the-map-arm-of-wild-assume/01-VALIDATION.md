---
phase: 1
slug: close-the-map-arm-of-wild-assume
# status lifecycle: draft (seeded by plan-phase) → validated (set by validate-phase §6)
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-07-31
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Derived from `01-RESEARCH.md` §Validation Architecture and the four committed plans.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Hspec, `compiler/test/Spec.hs` |
| **Config file** | `compiler/package.yaml` (test-suite stanza), `compiler/llmll.cabal` |
| **Quick run command** | `cd compiler && stack test --test-arguments '--match "SAFE-ARG"'` |
| **Full suite command** | `cd compiler && stack test` |
| **Corpus gate** | `scripts/check-examples.sh` |
| **Release gate** | `scripts/version_gate.sh` |
| **Estimated runtime** | quick run seconds; full suite minutes (measure in 01-01 Task 1, do not assume) |

**Build-hygiene precondition, ahead of every command above.**
`(cd compiler && stack build --dry-run llmll)` must print `Nothing to build.` with no `Would build:`
line. `llmll version` is not sufficient and mtime comparison is wrong about correct input. Verified
clean at planning time (binary v0.14.73); re-check at execution time because a branch switch dirties
it.

---

## Sampling Rate

- **After every task commit:** `cd compiler && stack test --test-arguments '--match "SAFE-ARG"'`
- **After every plan wave:** `cd compiler && stack test` plus `scripts/check-examples.sh`
- **Before `/gsd-verify-work`:** full suite green, `scripts/version_gate.sh` exits 0
- **Max feedback latency:** the quick run; measure it in 01-01 Task 1 and record the figure here

---

## Per-Task Verification Map

| Task | Plan | Wave | Requirement | Threat Ref | Test Type | Automated Command | File Exists | Status |
|---|---|---|---|---|---|---|---|---|
| 1: Measure the baseline the phase is judged against | 01-01 | 1 | REQ-wild-assume-2 (c1) | — (none fired) | gate | `stack build --dry-run` reports `Nothing to build`, and `stack test --match "SA-6"` reports `1 example, 0 failures` | ✅ SA-6 at `Spec.hs:2093-2096` | ⬜ pending |
| 2: End-to-end map arm, return seam, with its over-breadth guard | 01-01 | 1 | REQ-wild-assume-2 (c2, c3) | — | unit | `stack test --match "SAFE-ARG"` reports `0 failures` | ❌ W0 — SA-9, SA-14 | ⬜ pending |
| 1: The argument seam, plus the control that proves the wildcard is the cause | 01-02 | 2 | REQ-wild-assume-2 (c2, c3) | — | unit | `stack test --match "SA-8"` and `--match "SA-10"` each report `1 example, 0 failures` | ❌ W0 — SA-8, SA-10 | ⬜ pending |
| 2: The over-breadth surface, alias coverage, key coverage, construction path | 01-02 | 2 | REQ-wild-assume-2 (c1) | — | unit | `stack test --match "laundering through an unannotated hop"` reports `15 examples, 0 failures` | ❌ W0 — SA-11, SA-12, SA-13, SA-15 | ⬜ pending |
| 1: The diagnostic names the fact it refused | 01-03 | 3 | REQ-wild-assume-2 (c2) | — | unit | `stack test --match "SA-16"` reports `1 example, 0 failures`; hop block reports `16 examples, 0 failures` | ❌ W0 — SA-16, `wildAssumeFactNoun` | ⬜ pending |
| 2: Re-measure the corpus and the suite against the baseline | 01-03 | 3 | REQ-wild-assume-2 (c4) | — | regression | `stack build llmll` then dry-run reports `Nothing to build`, then `scripts/check-examples.sh` reports `failed=0` | ✅ script exists | ⬜ pending |
| 3: Decide the checker-soundness epoch on evidence | 01-03 | 3 | REQ-wild-assume-2 (c4) | — | unit | `stack test --match "checker_soundness_version"` reports `0 failures` | ✅ `VerifiedCache.hs` | ⬜ pending |
| 1: Hand-off, then the release ceremony in the documentation-lead role | 01-04 | 4 | REQ-wild-assume-2 (c5) | — | scripted gate | `scripts/version_gate.sh` exits 0 and `CHANGELOG.md` has one `## v0.14.74` heading | ✅ script exists | ⬜ pending |
| 2: Run the Definition of Done gate end to end | 01-04 | 4 | REQ-wild-assume-2 (c5) | — | scripted gate | version gate, build, dry-run, full `stack test` `0 failures`, `check-examples.sh` all in one chain | ✅ | ⬜ pending |
| 3: Human read of the release notes against the evidence limit | 01-04 | 4 | REQ-wild-assume-2 (c4) | — | **manual-only** | none — blocking human checkpoint | n/a | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

**Sampling continuity holds:** no three consecutive tasks lack an automated verify. The only task
without one is 01-04 Task 3, which is a deliberate blocking human checkpoint and is the last task in
the phase.

---

## Wave 0 Requirements

New Hspec examples in `compiler/test/Spec.hs`, in a new sibling `describe` block rather than the
existing bytes-arm block (research open question 3, decided in 01-01):

- [ ] **SA-9** — return-position `map[int bool]` launder, `compatibleWith`/`checkExpr` seam (01-01)
- [ ] **SA-14** — `(map-empty)` at a `map[int bool]` position, the over-breadth guard SA-6 does not
      reach (01-01)
- [ ] **SA-8** — argument-position `map[int bool]` launder, `structuralUnify` seam (01-02)
- [ ] **SA-10** — annotated-hop control, proving the wildcard is the cause rather than the map type
      (01-02)
- [ ] **SA-11** — type alias over `map[int bool]`, settling research open question 1 as a committed
      fixture (01-02)
- [ ] **SA-12** — non-bool value component, must not fire (01-02)
- [ ] **SA-13** — string key, must not fire (01-02)
- [ ] **SA-15** — construction path (01-02)
- [ ] **SA-16** — diagnostic wording holds both arms to an accurate fact noun (01-03)

**Every one of SA-8, SA-9 and SA-16 must launder through an unannotated intermediate hop**, so the
guard is exercised against the `freshenFnType`-produced `?$N` form. This is the bar the Rev 1
SAFE-ARG guard failed: it compared against `TVar "?"` by exact equality and was completely dead,
because `freshenFnType` had already alpha-renamed the wildcard before the guard ever saw it. A
fixture that exercises only the bare form does not satisfy criterion 2.

Regression, not new files:

- [ ] SA-1 through SA-7 stay green after the `assumesFact` widen. SA-4 (refinement alias), SA-5
      (nullary enum), SA-6 (`map-empty` at `map[int int]`) and SA-7 (named holes) are the existing
      over-breadth guards.
- [ ] `scripts/check-examples.sh` reports no new failures. **This is a regression check and is
      explicitly not evidence the fix works** (criterion 4).

Test-count arithmetic: expected post-phase hspec example count is the measured 01-01 Task 1 baseline
plus 9. No absolute figure is recorded anywhere; the executor measures the baseline and computes.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|---|---|---|---|
| Release notes state the evidence limit rather than overclaiming | REQ-wild-assume-2 criterion 4 | The failure mode is a paraphrase that reads as a stronger claim than the evidence supports. No assertion distinguishes an accurate sentence from a plausible-sounding weaker one. | Read the `## v0.14.74` CHANGELOG entry against the three sentences pinned in `01-04-PLAN.md`. Confirm it says this closes a **measured member of the SAFE-ARG class with no reaching-SAFE witness**, that both shapes crash on a sort mismatch before a verdict, that the phase does not refute a demonstrated exploit, and that the corpus run is recorded as a regression check. Blocking checkpoint, 01-04 Task 3. |

The plans pin the required sentences verbatim as acceptance criteria so the executor cannot
paraphrase them into an overclaim; the human read is the backstop on that, not the primary control.

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or a stated Wave 0 dependency (one deliberate manual-only)
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references (nine new SA examples enumerated above)
- [x] No watch-mode flags
- [ ] Feedback latency recorded (measure in 01-01 Task 1)
- [ ] `nyquist_compliant: true` set in frontmatter (set by `/gsd-validate-phase`)

**Approval:** pending
