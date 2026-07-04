#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Acceptance gate for the zero-install llmll Docker image.
#
# Proves the container can actually DISCHARGE proofs (z3 + fixpoint wired), not
# merely that the binaries exist. The load-bearing assertion is that
# `verify conserve-bad` exits 1 (refuted) and NOT 3 (SOLVER NOT FOUND) — exit 3
# is what a solver-less image returns, and it is a silent way to ship a dead
# demo (compiler/app/Main.hs:1102-1105,1247-1282).
#
# Ground-truth exit codes (llmll verify, solver present):
#     conserve.llmll      -> 0  (SAFE)
#     conserve-bad.llmll  -> 1  (body verification failed: postcondition)
#
# Usage:  scripts/tests/docker-acceptance.sh <image-ref>
#     e.g. scripts/tests/docker-acceptance.sh llmll:dev
# ─────────────────────────────────────────────────────────────────────────────
set -u
set -o pipefail

IMG="${1:?usage: docker-acceptance.sh <image-ref>}"
CONSERVE_BAD=/opt/llmll/examples/payments-core/conserve-bad.llmll
CONSERVE_OK=/opt/llmll/examples/payments-core/conserve.llmll
fails=0

pass() { printf 'PASS  %s\n' "$*"; }
fail() { printf 'FAIL  %s\n' "$*"; fails=$((fails + 1)); }

echo "== llmll docker acceptance: $IMG =="

# 1. Backend binaries must be runnable (else verify would exit 3 downstream).
if v=$(docker run --rm --entrypoint z3 "$IMG" --version 2>/dev/null); then
  pass "z3 runnable ($v)"
else
  fail "z3 not runnable in image"
fi
if docker run --rm --entrypoint fixpoint "$IMG" --help >/dev/null 2>&1; then
  pass "fixpoint (liquid-fixpoint) runnable"
else
  fail "fixpoint not runnable in image"
fi
if v=$(docker run --rm --entrypoint llmll "$IMG" --version 2>/dev/null | head -1); then
  pass "llmll runnable ($v)"
else
  fail "llmll not runnable in image"
fi

# 2. Headline: the conservation-breaking fill must be REFUTED (exit 1).
#    Anything else is a failure; exit 3 specifically means the solver is not wired.
out=$(docker run --rm "$IMG" verify "$CONSERVE_BAD" 2>&1); rc=$?
case "$rc" in
  1) pass "conserve-bad refuted (exit 1)" ;;
  3) fail "conserve-bad exited 3 — SOLVER NOT FOUND (z3/fixpoint not wired)" ;;
  0) fail "conserve-bad exited 0 — bad fill was NOT refuted (verifier regression)" ;;
  *) fail "conserve-bad expected exit 1 (refuted), got $rc" ;;
esac
if printf '%s' "$out" | grep -q "SOLVER NOT FOUND"; then
  fail "SOLVER NOT FOUND banner present — solver missing"
fi

# 3. The correct program must VERIFY (exit 0).
docker run --rm "$IMG" verify "$CONSERVE_OK" >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 0 ]; then
  pass "conserve verified SAFE (exit 0)"
else
  fail "conserve expected exit 0 (SAFE), got $rc"
fi

if [ "$fails" -eq 0 ]; then
  echo "== ALL PASS =="
else
  echo "== $fails FAILURE(S) =="
fi
[ "$fails" -eq 0 ]
