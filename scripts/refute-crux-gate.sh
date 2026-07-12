#!/usr/bin/env bash
# refute-crux-gate.sh — frozen-verdict CI gate for showcased refute-crux examples.
#
# Runs `llmll verify` on every case listed in each example family's
# EXPECTED_VERDICTS.json and compares verdict + exit code against the frozen
# expectation. A "safe" case must exit 0 and print SAFE; a "refuted" case must
# exit 1 and print an error naming the localized function.
#
# Scope guard (deliberate): this gate freezes VERIFY verdicts + exit codes
# ONLY. It does not read obligation reports, trust-report shapes, or
# contract_fragment classifications — those legitimately change as the
# data-scope track's classifier stages land, and gating them here would churn.
#
# Motivation: refutation of tcp_rfc793/session-pay wrong twins was silently
# lost for twenty versions (v0.14.12–v0.14.31, ENUM-EQ-FALLBACK) because no
# gate froze their verdicts. This gate makes that class of regression loud.
#
# Each case verifies a COPY of the fixture in a temp dir, so no .verified.json
# sidecars are written into the example directories.
#
# Exit codes:
#   0 — all frozen verdicts reproduced
#   1 — a verdict, exit code, or localization diverged

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LLMLL="stack exec llmll --"

FAMILIES=(
  "tcp_rfc793"
  "session-pay"
  "gotofail"
  "outcome-totality"
  "total-recursion"
  "bytes-bounds"
  "rfc1982_serial"
)

if ! command -v jq &> /dev/null; then
  echo "ERROR: jq is required. Install with: brew install jq"
  exit 1
fi

PASS=0
FAIL=0

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

echo "═══════════════════════════════════════════════════════════"
echo " Refute-Crux Verdict Gate (frozen verify verdicts)"
echo "═══════════════════════════════════════════════════════════"

for FAMILY in "${FAMILIES[@]}"; do
  EXPECTED="$REPO_ROOT/examples/$FAMILY/EXPECTED_VERDICTS.json"
  if [ ! -f "$EXPECTED" ]; then
    echo "  ❌ $FAMILY: $EXPECTED not found"
    FAIL=$((FAIL + 1))
    continue
  fi

  echo ""
  echo "▸ $FAMILY"

  N=$(jq '.cases | length' "$EXPECTED")
  for ((i = 0; i < N; i++)); do
    FILE=$(jq -r ".cases[$i].file" "$EXPECTED")
    EXPECT=$(jq -r ".cases[$i].expect" "$EXPECTED")
    EXPECT_EXIT=$(jq -r ".cases[$i].expect_exit" "$EXPECTED")
    LOCALIZED=$(jq -r ".cases[$i].localized // empty" "$EXPECTED")
    FLAGS=$(jq -r ".cases[$i].flags | join(\" \")" "$EXPECTED")

    SRC="$REPO_ROOT/examples/$FAMILY/$FILE"
    if [ ! -f "$SRC" ]; then
      echo "  ❌ $FILE: fixture missing"
      FAIL=$((FAIL + 1))
      continue
    fi

    # Verify a copy so no sidecar lands in the example dir.
    CASE_DIR="$WORKDIR/$FAMILY-$i"
    mkdir -p "$CASE_DIR"
    cp "$SRC" "$CASE_DIR/"

    set +e
    OUTPUT=$(cd "$REPO_ROOT/compiler" && $LLMLL verify "$CASE_DIR/$FILE" $FLAGS 2>&1)
    ACTUAL_EXIT=$?
    set -e

    OK=true
    REASON=""

    if [ "$ACTUAL_EXIT" -ne "$EXPECT_EXIT" ]; then
      OK=false
      REASON="exit $ACTUAL_EXIT (expected $EXPECT_EXIT)"
    fi

    case "$EXPECT" in
      safe)
        if ! echo "$OUTPUT" | grep -q "SAFE"; then
          OK=false
          REASON="${REASON:+$REASON; }no SAFE verdict in output"
        fi
        ;;
      refuted)
        if ! echo "$OUTPUT" | grep -q "error:"; then
          OK=false
          REASON="${REASON:+$REASON; }no refutation error in output"
        elif [ -n "$LOCALIZED" ] && ! echo "$OUTPUT" | grep -q "'$LOCALIZED'"; then
          OK=false
          REASON="${REASON:+$REASON; }refutation not localized to '$LOCALIZED'"
        fi
        ;;
      *)
        OK=false
        REASON="unknown expectation '$EXPECT'"
        ;;
    esac

    LABEL="$FILE${FLAGS:+ $FLAGS} → $EXPECT/exit $EXPECT_EXIT"
    if $OK; then
      echo "  ✅ $LABEL"
      PASS=$((PASS + 1))
    else
      echo "  ❌ $LABEL"
      echo "     $REASON"
      echo "$OUTPUT" | tail -3 | sed 's/^/     | /'
      FAIL=$((FAIL + 1))
    fi
  done
done

echo ""
echo "═══════════════════════════════════════════════════════════"
echo " Results: $PASS passed, $FAIL failed"
echo "═══════════════════════════════════════════════════════════"

if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo "FAIL: refute-crux gate failed — $FAIL frozen verdict(s) diverged."
  exit 1
else
  echo ""
  echo "OK: refute-crux gate passed."
  exit 0
fi
