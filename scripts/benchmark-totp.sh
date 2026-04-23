#!/usr/bin/env bash
# benchmark-totp.sh — CI gate for the frozen TOTP RFC 6238 benchmark (BM2-4)
#
# Runs --spec-coverage and --trust-report against the frozen TOTP benchmark
# and compares against EXPECTED_RESULTS.json.
#
# Exit codes:
#   0 — all checks passed
#   1 — a check diverged from frozen expected results

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
EXAMPLE_DIR="$REPO_ROOT/examples/totp_rfc6238"
EXPECTED="$EXAMPLE_DIR/EXPECTED_RESULTS.json"
FILLED="$EXAMPLE_DIR/totp_filled.ast.json"
SKELETON="$EXAMPLE_DIR/totp.ast.json"
LLMLL="stack exec llmll --"

if ! command -v jq &> /dev/null; then
  echo "ERROR: jq is required. Install with: brew install jq"
  exit 1
fi

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
echo " TOTP RFC 6238 Benchmark Gate (BM2-4)"
echo "═══════════════════════════════════════════════════════════"
echo ""

# ── 0. Parse check ────────────────────────────────────────────

echo "▸ Checking skeleton parses ..."
SKEL_OUTPUT=$(cd "$REPO_ROOT/compiler" && $LLMLL check "$SKELETON" 2>/dev/null)
if echo "$SKEL_OUTPUT" | grep -q "OK"; then
  check_result "skeleton parse" "true" "true"
else
  check_result "skeleton parse" "true" "false"
fi

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

EXPECTED_TR_ENTRIES=$(jq '.expected_trust_report.proven + .expected_trust_report.asserted + .expected_trust_report.no_contract' "$EXPECTED")
EXPECTED_TR_NONE=$(jq '.expected_trust_report.no_contract' "$EXPECTED")
EXPECTED_TR_SUPPS=$(jq '.expected_trust_report.suppressions | length' "$EXPECTED")

check_result "trust report: total entries"    "$EXPECTED_TR_ENTRIES"  "$ACTUAL_TR_ENTRIES"
check_result "trust report: no contract"      "$EXPECTED_TR_NONE"     "$ACTUAL_TR_NONE"
check_result "trust report: drifts = 0"       "0"                     "$ACTUAL_TR_DRIFTS"
check_result "trust report: suppressions"     "$EXPECTED_TR_SUPPS"    "$ACTUAL_TR_SUPPS"

echo ""

# ── 3. Source provenance (PROV-3) ─────────────────────────────

echo "▸ Checking source provenance in trust report ..."
HAS_PRE_SOURCE=$(echo "$TRUST_JSON" | jq '[.entries[] | select(.pre_source != null)] | length')
HAS_POST_SOURCE=$(echo "$TRUST_JSON" | jq '[.entries[] | select(.post_source != null)] | length')

check_result "entries with pre_source > 0"   "true" "$([ "$HAS_PRE_SOURCE" -gt 0 ] && echo true || echo false)"
check_result "entries with post_source > 0"  "true" "$([ "$HAS_POST_SOURCE" -gt 0 ] && echo true || echo false)"

echo ""

# ── 4. Verification-scope matrix ──────────────────────────────

echo "▸ Checking verification-scope matrix ..."
MATRIX_COUNT=$(jq '.verification_scope.matrix | length' "$EXPECTED")
check_result "verification-scope matrix entries" "6" "$MATRIX_COUNT"

echo ""

# ── 5. Check blocks ──────────────────────────────────────────

echo "▸ Validating check block count ..."
EXPECTED_CHECKS=$(jq '.check_blocks.total' "$EXPECTED")
check_result "check block count" "$EXPECTED_CHECKS" "4"

echo ""

# ── Summary ───────────────────────────────────────────────────

echo "═══════════════════════════════════════════════════════════"
echo " Results: $PASS passed, $FAIL failed"
echo "═══════════════════════════════════════════════════════════"

if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo "FAIL: TOTP benchmark gate failed — $FAIL check(s) diverged from frozen results."
  exit 1
else
  echo ""
  echo "OK: TOTP benchmark gate passed."
  exit 0
fi
