#!/usr/bin/env bash
# refute-crux-gate.sh — frozen-verdict CI gate for showcased refute-crux examples.
#
# Runs `llmll verify` on every case listed in each example family's
# EXPECTED_VERDICTS.json and compares verdict + exit code against the frozen
# expectation. A "safe" case must exit 0 and print SAFE; a "refuted" case must
# exit 1 and print an error naming the localized function; a "capability" case
# must exit 1 with the missing-capability diagnostic, having been rejected at
# type-check before the solver was reached. The third kind exists because
# "refuted" and "capability" both print "error:" and exit 1, so without it a
# program the type checker rejected counted as one the solver disproved.
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

# Repo-relative suite directories. Not bare names under examples/: the
# driver suite lives in tools/, so a suite is addressed by its path.
FAMILIES=(
  "examples/tcp_rfc793"
  "examples/session-pay"
  "examples/gotofail"
  "examples/outcome-totality"
  "examples/total-recursion"
  "examples/bytes-bounds"
  "examples/rfc1982_serial"
  "examples/token-revocation-emergent"
  "examples/nested-result"
  "examples/niw-measure"
  "examples/banking_ledger"
  "tools/llmll-driver"
)

if ! command -v jq &> /dev/null; then
  echo "ERROR: jq is required. Install with: brew install jq"
  exit 1
fi

# Preflight (A4 finding F-3): `stack exec` does NOT rebuild — after a compiler
# change, a stale binary silently checks the frozen verdicts against the OLD
# compiler (a new-feature refute then reads as vacuously SAFE). Build first so
# every verdict is checked against the current sources; under `set -e` a failed
# build aborts the gate loudly instead of gating against a stale binary.
echo "▸ stack build (preflight — stale-binary guard, finding F-3)"
(cd "$REPO_ROOT/compiler" && stack build)

PASS=0
FAIL=0

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

echo "═══════════════════════════════════════════════════════════"
echo " Refute-Crux Verdict Gate (frozen verify verdicts)"
echo "═══════════════════════════════════════════════════════════"

for FAMILY in "${FAMILIES[@]}"; do
  EXPECTED="$REPO_ROOT/$FAMILY/EXPECTED_VERDICTS.json"
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

    SRC="$REPO_ROOT/$FAMILY/$FILE"
    if [ ! -f "$SRC" ]; then
      echo "  ❌ $FILE: fixture missing"
      FAIL=$((FAIL + 1))
      continue
    fi

    # Verify a copy so no sidecar lands in the suite dir. The whole suite is
    # copied, not just the case file: a case that imports a sibling module
    # cannot resolve it otherwise, and `verify` still checks only the named
    # file, so the extra siblings change no verdict.
    CASE_DIR="$WORKDIR/${FAMILY//\//-}-$i"
    mkdir -p "$CASE_DIR"
    cp "$REPO_ROOT/$FAMILY"/*.llmll "$CASE_DIR/"

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
        elif echo "$OUTPUT" | grep -q "requires (import"; then
          # A capability violation is not a refutation. Both print "error:" and
          # exit 1, so grepping for "error:" alone let a program rejected at
          # TYPE-CHECK stand in for one the solver disproved. Those are different
          # claims about different machinery, and a suite that conflates them
          # would keep reporting a green refutation after the solver stopped
          # being reached at all.
          OK=false
          REASON="${REASON:+$REASON; }capability violation, not a refutation; expect 'capability'"
        elif [ -n "$LOCALIZED" ] && ! echo "$OUTPUT" | grep -q "'$LOCALIZED'"; then
          OK=false
          REASON="${REASON:+$REASON; }refutation not localized to '$LOCALIZED'"
        fi
        ;;
      capability)
        # Rejected before the solver: an effect reached without the capability
        # import that authorizes it. The case must fail for THAT reason, so the
        # diagnostic is matched rather than the bare exit code.
        if ! echo "$OUTPUT" | grep -q "requires (import"; then
          OK=false
          REASON="${REASON:+$REASON; }no capability diagnostic in output"
        elif [ -n "$LOCALIZED" ] && ! echo "$OUTPUT" | grep -q "$LOCALIZED"; then
          OK=false
          REASON="${REASON:+$REASON; }capability error does not name '$LOCALIZED'"
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
