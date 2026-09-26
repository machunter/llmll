# Security policy

LLMLL is a verifier, so the defects that matter most here are the ones where it claims more than it
proved. Please report those privately.

## Supported versions

Only the latest release is supported. The project is pre-1.0, and fixes ship as a new patch release
rather than as backports.

## What to report privately

Use GitHub's private reporting: the **Security** tab of this repository, then **Report a
vulnerability**.

Report privately when LLMLL accepts something it should reject:

- `llmll verify` reports a function as proved (`✅`, or `body-faithful` with `SAFE`) when its body
  violates its contract for some input.
- `--strict-verified-core` admits a function that `LLMLL.md` §5.3 says it refuses.
- `llmll patch` or `llmll refine` applies a fill that does not type-check or that the solver refutes.
- A stale or edited `.verified.json` sidecar is admitted as `verified` evidence.
- `llmll replay-artifact` accepts a record that does not match the program, the solver or the pins.
- The trust report shows a level (`verified`, `tested`) that the evidence does not support.
- The Docker image (`ghcr.io/machunter/llmll`) contains something other than what the Dockerfile
  builds.

A useful report has the smallest program that shows it, the exact command, the output of
`llmll version`, and what you expected instead.

## What is not a vulnerability

These are documented boundaries. Open an ordinary issue if the documentation is unclear about them.

- A contract that says the wrong thing. LLMLL proves a body meets its contract, not that the contract
  is the right one (`ROADMAP.md`, "Deliberate boundaries").
- A function outside the SMT fragment reported as `asserted` or as a body fallback. That is the tool
  saying it did not prove it.
- A recursive function without a `(decreases …)` measure proved at partial correctness. The `verify`
  headline names it (`LLMLL.md` §5.3).
- A `capability` clause on an import that is not enforced. It is declarative today (`LLMLL.md` §7,
  roadmap `CAP-1-REAL`).

## What happens next

This is a single-maintainer project. Expect an acknowledgement within about a week. A confirmed
soundness defect is fixed in a patch release, and the CHANGELOG entry says it was a soundness fix, as
v0.26.3 did for `MEASURE-NONNEG-1`. You are credited there unless you ask not to be.
