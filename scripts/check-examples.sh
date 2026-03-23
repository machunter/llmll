#!/usr/bin/env bash
# check-examples.sh — Run `llmll check` on every example in examples/.
#
# Exits 0 if all found examples type-check (or if none are found).
# Exits 1 if any example fails to type-check.
#
# Designed to be called from CI or a Makefile target.
# Safe to run even if examples/ is empty or the directory doesn't exist.
# Compatible with macOS bash 3 (no mapfile, no bash 4 arrays via process sub).

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXAMPLES_DIR="$REPO_ROOT/examples"
COMPILER_DIR="$REPO_ROOT/compiler"

FAILED=0
PASSED=0
SKIPPED=0
TOTAL=0

# Collect file list into a temp file so we can count before iterating.
TMP_LIST="$(mktemp)"
find "$EXAMPLES_DIR" \
  -maxdepth 3 \
  \( -name "*.llmll" -o -name "*.ast.json" \) \
  2>/dev/null > "$TMP_LIST" || true

TOTAL=$(wc -l < "$TMP_LIST" | tr -d ' ')

if [[ "$TOTAL" -eq 0 ]]; then
  echo "check-examples: no example files found in $EXAMPLES_DIR — skipping (OK)"
  rm -f "$TMP_LIST"
  exit 0
fi

echo "check-examples: found $TOTAL file(s)"

while IFS= read -r FILE; do
  if [[ ! -f "$FILE" ]]; then
    # File disappeared between find and check — skip gracefully.
    echo "  SKIP  ${FILE#"$REPO_ROOT/"} (no longer exists)"
    SKIPPED=$(( SKIPPED + 1 ))
    continue
  fi

  REL="${FILE#"$REPO_ROOT/"}"

  if (cd "$COMPILER_DIR" && stack exec llmll -- check "$FILE") 2>&1; then
    PASSED=$(( PASSED + 1 ))
  else
    echo "  FAIL  $REL"
    FAILED=$(( FAILED + 1 ))
  fi
done < "$TMP_LIST"

rm -f "$TMP_LIST"

echo ""
echo "check-examples: passed=$PASSED  failed=$FAILED  skipped=$SKIPPED"

if [[ "$FAILED" -gt 0 ]]; then
  echo "check-examples: FAILED — $FAILED example(s) did not type-check"
  exit 1
fi

echo "check-examples: OK"
exit 0
