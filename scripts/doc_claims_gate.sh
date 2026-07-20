#!/usr/bin/env bash
# DRIFT-CT-2 — doc-claim drift gate.
#
# Runs every fixture in scripts/doc-claims/ through `llmll check` and asserts the
# OBSERVED verdict matches the fixture's `;; @expect:` header. Catches documentation
# that has drifted from actual compiler behaviour — specifically the class of stale
# *restriction* claims found in the 2026-07-19 external-critique triage, where a doc
# said a program is rejected/broken but the compiler accepts it (or vice-versa).
#
# Sibling of scripts/version_gate.sh (DRIFT-CI-1, banner/schema drift). This gate is
# DRIFT-CT-2 (compiler-behaviour drift).
#
# Each fixture is a .llmll file with a header:
#     ;; @doc:    <doc file and section the claim lives in>
#     ;; @expect: check-ok | parse-error | check-error | warn:<substring>
#     ;; @claim:  <the human-readable claim being guarded>
#
# Binary resolution: $LLMLL_BIN, else `llmll` on PATH, else ~/.local/bin/llmll.
# In CI, set LLMLL_BIN to the freshly-built binary. If none is found the gate SKIPs
# (exit 0) rather than failing — it cannot assert behaviour without a compiler.
#
# Exit 0 = all claims match (or skipped); exit 1 = at least one claim drifted.

set -u
set -o pipefail

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
FIXTURE_DIR="$REPO_ROOT/scripts/doc-claims"

LLMLL_BIN="${LLMLL_BIN:-}"
if [ -z "$LLMLL_BIN" ]; then
    if command -v llmll >/dev/null 2>&1; then
        LLMLL_BIN="llmll"
    elif [ -x "$HOME/.local/bin/llmll" ]; then
        LLMLL_BIN="$HOME/.local/bin/llmll"
    else
        echo "DRIFT-CT-2 SKIP: no llmll binary found (set LLMLL_BIN to enable)"
        exit 0
    fi
fi

# LLMLL_BIN may be a multi-word command (e.g. the CI convention "stack exec llmll --")
# or a single path. Split into an array so both invoke correctly.
read -r -a LLMLL_CMD <<< "$LLMLL_BIN"

# Classify `llmll check` output into a single verdict token. Order matters:
# a parse error is printed as `(error :phase parse ...)`, so it must be tested
# before the generic `error:` (semantic) case.
observed_verdict() {
    local out="$1"
    if printf '%s\n' "$out" | grep -q ':phase parse'; then
        echo "parse-error"
    elif printf '%s\n' "$out" | grep -qE '(^|[[:space:]])error:'; then
        echo "check-error"
    elif printf '%s\n' "$out" | grep -q '✅' && printf '%s\n' "$out" | grep -q 'OK'; then
        echo "check-ok"
    else
        echo "unknown"
    fi
}

header_field() {  # $1 = fixture, $2 = field name (doc|expect|claim)
    grep -m1 "@$2:" "$1" | sed "s/.*@$2:[[:space:]]*//"
}

pass=0
fail=0
declare -a FAIL_REPORTS=()

shopt -s nullglob
fixtures=("$FIXTURE_DIR"/*.llmll)
if [ "${#fixtures[@]}" -eq 0 ]; then
    echo "DRIFT-CT-2 SKIP: no fixtures in $FIXTURE_DIR"
    exit 0
fi

for f in "${fixtures[@]}"; do
    expect=$(header_field "$f" expect)
    claim=$(header_field "$f" claim)
    docref=$(header_field "$f" doc)
    out=$("${LLMLL_CMD[@]}" check "$f" 2>&1 || true)

    matched=false
    # expect is "<verdict>" or "<verdict>:<substring>". The substring (optional for
    # parse-error/check-error, required for warn) must also appear in the output —
    # this pins a cited diagnostic message, not just the verdict class.
    base="${expect%%:*}"
    sub=""
    case "$expect" in *:*) sub="${expect#*:}" ;; esac

    if [ "$base" = "warn" ]; then
        obs="no-warning"
        if printf '%s\n' "$out" | grep -q 'warning:' \
           && { [ -z "$sub" ] || printf '%s\n' "$out" | grep -qF "$sub"; }; then
            matched=true
            obs="warn"
        fi
    else
        obs=$(observed_verdict "$out")
        if [ "$obs" = "$base" ] \
           && { [ -z "$sub" ] || printf '%s\n' "$out" | grep -qF "$sub"; }; then
            matched=true
        fi
    fi

    if $matched; then
        pass=$((pass + 1))
        printf '  \342\234\224 %-30s expect=%-11s [%s]\n' \
            "$(basename "$f")" "$expect" "$docref"
    else
        fail=$((fail + 1))
        report=$(printf '  \342\234\230 %s\n     expect : %s\n     observed: %s\n     doc    : %s\n     claim  : %s\n     --- llmll check output ---\n%s' \
            "$(basename "$f")" "$expect" "$obs" "$docref" "$claim" \
            "$(printf '%s\n' "$out" | sed 's/^/     /')")
        FAIL_REPORTS+=("$report")
    fi
done

echo
if [ "$fail" -eq 0 ]; then
    echo "DRIFT-CT-2 PASS: $pass doc-claim(s) match compiler behaviour"
    exit 0
fi

echo "DRIFT-CT-2 FAIL: $fail of $((pass + fail)) doc-claim(s) drifted from compiler behaviour"
echo
for r in "${FAIL_REPORTS[@]}"; do
    printf '%s\n\n' "$r"
done
echo "A failing claim means the docs and the compiler disagree. Fix BOTH the fixture's"
echo "@expect header AND the doc section named in @doc, then re-run."
exit 1
