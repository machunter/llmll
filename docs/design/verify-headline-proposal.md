---
Status: SHIPPED-PENDING Rev 1 (2026-09-24, user-approved direction; witnesses re-measured on the implementation)
Tag: VERIFY-HEADLINE-1
Owner: language-team
---

# VERIFY-HEADLINE-1: the `verify` headline shows what was proved

## Problem

Default `llmll verify` prints `✅ <file> — SAFE (liquid-fixpoint)` whenever the solver
accepts the emitted constraint set (`doVerify`, the `FQSafe` arm of the text-mode result
in `compiler/app/Main.hs`). That verdict is about the constraints, and the constraints of
a function that fell back from body-faithful verification assume its postcondition. So
the check mark appears on programs where most contracts are assumed, not proved.

Witnesses, measured on v0.26.0. `examples/erc20_token/erc20_filled.ast.json` has five
contracted functions, two of which fall back, and prints `✅ erc20_filled.ast.json — SAFE
(liquid-fixpoint)`. `examples/tictactoe_sexp/tictactoe.llmll` carries no postcondition at
all; its four `body-fallback:` entries are `no-post` fallbacks, and it also prints `✅`.
`hangman_json_verifier` and `effect-authority` behave the same way (launch audit,
2026-09-23; the audit read tictactoe's fallbacks as assumed posts, which Rev 1 corrects). A reader who runs an example
sees green on code whose contracts were not proved. The `body-fallback:` line above the
headline is accurate but is not what a reader looks at.

## Design

The verdict word stays. The mark and a count change, and only when something was not
proved.

**Proved set.** A function counts as *contracted* when it carries a postcondition. A
contracted function is *proved* when it is in `erBodyFaithfulFns`, and *assumed*
otherwise: a body fallback (`erBodyFallback`), a function skipped as non-linear, or a
function whose body is a hole. Functions without a postcondition are not counted; they
have nothing to prove.

**Text-mode headline on `FQSafe`:**

1. Every contracted function proved (the case for every README and blog example):
   unchanged, byte for byte.

   ```
   ✅ conserve.llmll — SAFE (liquid-fixpoint)
   ```

2. At least one contracted function assumed (measured on erc20):

   ```
   ⚠️  erc20_filled.ast.json — SAFE (liquid-fixpoint), partial: 3 of 5 contracted functions proved; 2 assumed, not proved: transfer, transfer-from
      (--strict-verified-core fails on assumed functions)
   ```

3. No contracted function at all (measured on tictactoe):

   ```
   ⚠️  tictactoe.llmll — SAFE (liquid-fixpoint), nothing proved: no function carries a postcondition
   ```

The literal `SAFE (liquid-fixpoint)` stays in every case, so every consumer that detects
a solver pass by that text keeps working. The refuted and solver-error arms are
unchanged.

**Exit code:** unchanged (0 on `FQSafe`). Failing on assumed functions is what
`--strict-verified-core` is for; the hint line names it.

**JSON (`--json`):** additive fields on the existing verify object:
`"all_proved": bool`, `"proved_count": int`, `"contracted_count": int`,
`"assumed_fns": [name]`. No field is removed or renamed.

## Edge cases

1. **All proved.** Output identical to v0.26.0. Channel: trust (display). Pins every
   public transcript.
2. **Partial** (the erc20 witness). `⚠️` headline with counts and names. This is the
   positive witness: the minimal firing input is any program with one body-faithful and
   one fallback contracted function, e.g. a `def` with `(post (= result (+ x 1)))` and
   body `(+ x 1)`, plus a `def-shell` with a post whose body calls an uncontracted
   helper.
3. **No postconditions.** `⚠️ … nothing proved`. A program of plumbing is not presented
   as proved.
4. **Refuted.** Unchanged: the error lines, exit 1.
5. **Solver error.** Unchanged: `ERROR: liquid-fixpoint: …`.
6. **`--trust-report` / `--strict-verify`.** Out of scope: those paths print the
   per-function report, which already shows each function's level.

## Verification mapping

No new proof obligation. The change is display and JSON over data `doVerify` already
computes (`erBodyFaithfulFns`, `erBodyFallback`, the skipped list, contract presence).
Channel: trust (what the tool claims). Fragment: none.

## Affected surface

- `compiler/app/Main.hs`, `doVerify` text-mode `FQSafe` arm and the JSON object.
- Consumers that match the headline: `scripts/benchmark-totp.sh`,
  `scripts/benchmark-erc20.sh`, `scripts/build_smoke.sh`, `scripts/refute_crux_cover.py`,
  `tools/doc-claims/docclaims.llmll`, `scripts/tests/test_rfc_pipeline_integration.py`,
  and any `EXPECTED_*` or doc-claims fixture keyed on `✅`. Each is checked; none may
  change meaning.
- Docs (documentation-lead): `LLMLL.md` where it shows verify output, getting-started
  transcripts that show `✅` on a partial program, README if any.

## Rationale for keeping `SAFE`

The solver verdict is correct about the constraint set, and several gates key on it.
The defect is the mark and the missing count, which imply that every contract was
proved. Keeping the verdict word and changing only the mark fixes the claim without
changing any gate's meaning.
