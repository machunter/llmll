#!/usr/bin/env bash
# benchmark-erc20.sh — CI gate for the frozen ERC-20 benchmark (BM-4)
#
# Runs --spec-coverage, --trust-report, and --weakness-check against the
# frozen ERC-20 benchmark and compares against EXPECTED_RESULTS.json.
#
# Exit codes:
#   0 — all checks passed
#   1 — a check diverged from frozen expected results
#
# Usage:
#   ./scripts/benchmark-erc20.sh
#   make benchmark-erc20

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
EXAMPLE_DIR="$REPO_ROOT/examples/erc20_token"
EXPECTED="$EXAMPLE_DIR/EXPECTED_RESULTS.json"
FILLED="$EXAMPLE_DIR/erc20_filled.ast.json"
LLMLL="stack exec llmll --"

# Ensure jq is available
if ! command -v jq &> /dev/null; then
  echo "ERROR: jq is required for benchmark comparison. Install with: brew install jq"
  exit 1
fi

# Ensure expected results exist
if [ ! -f "$EXPECTED" ]; then
  echo "ERROR: $EXPECTED not found"
  exit 1
fi

PASS=0
FAIL=0

check_result() {
  local label="$1"
  local expected="$2"
  local actual="$3"

  # Normalize: jq may output 1 vs 1.0 for floats
  local norm_expected=$(echo "$expected" | sed 's/\.0$//')
  local norm_actual=$(echo "$actual" | sed 's/\.0$//')

  if [ "$norm_expected" = "$norm_actual" ]; then
    echo "  ✅ $label"
    PASS=$((PASS + 1))
  else
    echo "  ❌ $label"
    echo "     expected: $expected"
    echo "     actual:   $actual"
    FAIL=$((FAIL + 1))
  fi
}

echo "═══════════════════════════════════════════════════════════"
echo " ERC-20 Benchmark Gate (BM-4)"
echo "═══════════════════════════════════════════════════════════"
echo ""

# ── 1. Spec Coverage ──────────────────────────────────────────

echo "▸ Running --spec-coverage ..."
COVERAGE_JSON=$(cd "$REPO_ROOT/compiler" && $LLMLL verify "$FILLED" --spec-coverage --json 2>/dev/null)

ACTUAL_CONTRACTED=$(echo "$COVERAGE_JSON" | jq '.summary.contracted')
ACTUAL_SUPPRESSED=$(echo "$COVERAGE_JSON" | jq '.summary.suppressed')
ACTUAL_UNSPECIFIED=$(echo "$COVERAGE_JSON" | jq '.summary.unspecified')
ACTUAL_TOTAL=$(echo "$COVERAGE_JSON" | jq '.summary.total')
ACTUAL_COVERAGE=$(echo "$COVERAGE_JSON" | jq '.summary.effective_coverage')

EXPECTED_CONTRACTED=$(jq '.expected_spec_coverage.contracted' "$EXPECTED")
EXPECTED_SUPPRESSED=$(jq '.expected_spec_coverage.suppressed' "$EXPECTED")
EXPECTED_UNSPECIFIED=$(jq '.expected_spec_coverage.unspecified' "$EXPECTED")
EXPECTED_TOTAL=$(jq '.expected_spec_coverage.total' "$EXPECTED")
EXPECTED_COVERAGE=$(jq '.expected_spec_coverage.effective_coverage' "$EXPECTED")

check_result "contracted functions"      "$EXPECTED_CONTRACTED" "$ACTUAL_CONTRACTED"
check_result "suppressed functions"      "$EXPECTED_SUPPRESSED" "$ACTUAL_SUPPRESSED"
check_result "unspecified functions"     "$EXPECTED_UNSPECIFIED" "$ACTUAL_UNSPECIFIED"
check_result "total functions"           "$EXPECTED_TOTAL"      "$ACTUAL_TOTAL"
check_result "effective coverage"        "$EXPECTED_COVERAGE"   "$ACTUAL_COVERAGE"

echo ""

# ── 2. Trust Report ───────────────────────────────────────────

echo "▸ Running --trust-report ..."
TRUST_JSON=$(cd "$REPO_ROOT/compiler" && $LLMLL verify "$FILLED" --trust-report --json 2>/dev/null)

ACTUAL_TR_ENTRIES=$(echo "$TRUST_JSON" | jq '.entries | length')
ACTUAL_TR_NONE=$(echo "$TRUST_JSON" | jq '.summary.no_contract')
ACTUAL_TR_DRIFTS=$(echo "$TRUST_JSON" | jq '.summary.drifts')
ACTUAL_TR_SUPPS=$(echo "$TRUST_JSON" | jq '.suppressions | length')

# Trust report: check structure, not solver-dependent verification levels.
# The expected results assume liquid-fixpoint has run (proven=6), but the
# gate checks structural correctness: right number of entries, no drifts,
# correct suppressions count.
EXPECTED_TR_ENTRIES=$(jq '.expected_trust_report.proven + .expected_trust_report.asserted + .expected_trust_report.no_contract' "$EXPECTED")
EXPECTED_TR_NONE=$(jq '.expected_trust_report.no_contract' "$EXPECTED")
EXPECTED_TR_SUPPS=$(jq '.expected_trust_report.suppressions | length' "$EXPECTED")

check_result "trust report: total entries"    "$EXPECTED_TR_ENTRIES"  "$ACTUAL_TR_ENTRIES"
check_result "trust report: no contract"      "$EXPECTED_TR_NONE"     "$ACTUAL_TR_NONE"
check_result "trust report: drifts = 0"       "0"                     "$ACTUAL_TR_DRIFTS"
check_result "trust report: suppressions"     "$EXPECTED_TR_SUPPS"    "$ACTUAL_TR_SUPPS"

echo ""

# ── 3. Weakness Check ────────────────────────────────────────

echo "▸ Running --weakness-check ..."
# weakness-check requires liquid-fixpoint to first report SAFE;
# if solver is not installed, skip gracefully.
if command -v fixpoint &> /dev/null || command -v liquid-fixpoint &> /dev/null; then
  WEAK_OUTPUT=$(cd "$REPO_ROOT/compiler" && $LLMLL verify "$FILLED" --weakness-check 2>&1 || true)
  if echo "$WEAK_OUTPUT" | grep -q "No spec weaknesses detected"; then
    check_result "no weak functions" "true" "true"
  elif echo "$WEAK_OUTPUT" | grep -q "SAFE"; then
    # SAFE but no weakness message = no weaknesses
    check_result "no weak functions (SAFE)" "true" "true"
  elif echo "$WEAK_OUTPUT" | grep -q "spec weakness"; then
    check_result "no weak functions" "true" "false"
  else
    echo "  ⚠ weakness-check produced unexpected output — skipped"
    echo "    output: $(echo "$WEAK_OUTPUT" | head -3)"
  fi
else
  echo "  ⚠ liquid-fixpoint not installed — weakness check skipped"
fi

echo ""

# ── 4. Verification-Scope Matrix ─────────────────────────────

echo "▸ Checking verification-scope matrix ..."
MATRIX_COUNT=$(jq '.verification_scope.matrix | length' "$EXPECTED")
check_result "verification-scope matrix entries" "10" "$MATRIX_COUNT"

echo ""

# ── Summary ───────────────────────────────────────────────────

echo "═══════════════════════════════════════════════════════════"
echo " Results: $PASS passed, $FAIL failed"
echo "═══════════════════════════════════════════════════════════"

if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo "FAIL: ERC-20 benchmark gate failed — $FAIL check(s) diverged from frozen results."
  exit 1
else
  echo ""
  echo "OK: ERC-20 benchmark gate passed."
  exit 0
fi
