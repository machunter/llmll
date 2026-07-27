#!/usr/bin/env bash
# DRIFT-DOC-3: archive-disposition drift gate.
#
# Asserts that every archived design doc which DECLARES an `archive-disposition`
# frontmatter field sits in the directory that field's side names. Specified in
# docs/design/archive-organization-proposal.md (Rev 2), Move 4 + P3.
#
#     archive-disposition: shipped | superseded   -> shipped-design-specs/
#     archive-disposition: dropped | deferred     -> dormant-explorations/
#
# WHAT THIS GATE IS. A *consistency* gate, sibling of scripts/version_gate.sh
# (DRIFT-CI-1), which likewise asserts equality among records maintained inside
# this repository. It detects that two self-attested records (the declared field
# and the directory path) disagree. It CANNOT detect both being wrong: an author
# who abandons a design and updates neither leaves this gate green. That limit is
# structural for a self-attestation channel and the project already adjudicated it
# as such (F-002; LLMLL.md:708, experiments/adv-spec-weaken-0/findings.md:35-40).
#
# It is NOT a sibling of scripts/doc_claims_gate.sh (DRIFT-CT-2). That gate
# executes the compiler and compares an OBSERVED verdict to a claimed one, so it
# has an oracle outside the repository. This one does not.
#
# WHY A DECLARED FIELD AND NOT A PROSE SCAN. Measured over the 57 archived files
# on 2026-07-26: 55 carry some status marker, but only 21 of 57 DECIDE
# shipped-side-vs-not by keyword; the rest state lifecycle ("Approved", "BUILT",
# "CLOSED", "Deferred"), not disposition. A prose scan also over-fires: "superseded"
# appears in body text describing a superseded characterization, triage row,
# construct, and adjudication in four different files. So the gate reads a field
# the author declares, which is the same bargain the `;; @expect:` headers make in
# DRIFT-CT-2.
#
# OPT-IN, WITH A RATCHET. Files without the field are not gated. The gate reports
# how many there are and asserts that count against UNGATED_BOUND below: it fails
# if the count exceeds the bound, and warns (non-fatally) if it is under, naming
# the lower value. A newly archived doc must therefore either declare the field or
# force a visible bound raise in the diff. The bound may shrink and never grows
# silently. This replaces the named-file allowlist of Rev 1, which had no forcing
# function because growing it was a one-line edit in this same file.
#
# SELF-TEST. Unlike DRIFT-CT-2, whose fixture corpus is expected to contain
# failures, this gate's corpus is expected to be conformant, so its failure branch
# would never execute in CI. It therefore runs scripts/doc-archive-fixtures/ first
# and asserts both branches produce their expected verdicts. A self-test mismatch
# is a hard failure: it means the gate's own logic changed.
#
# Fail-closed: no SKIP path. This gate has no compiler dependency and nothing it
# needs can be absent. Requires bash and awk only.
#
# Exit 0 = self-test green, no disposition/path disagreement, ungated count within
# bound. Exit 1 = otherwise.

set -u
set -o pipefail

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$REPO_ROOT"

# Count of governed files not yet declaring `archive-disposition`. Shrink this as
# documents adopt the field; never raise it without saying why in the commit.
UNGATED_BOUND="${UNGATED_BOUND:-58}"

SHIPPED_DIR="shipped-design-specs"
DORMANT_DIR="dormant-explorations"

# Files that index a directory rather than being archived documents themselves.
is_index_file() {
    case "$(basename "$1")" in
        README.md|INDEX.md) return 0 ;;
        *) return 1 ;;
    esac
}

# Echo the value of `archive-disposition` from the file's YAML frontmatter, or
# nothing. Scoped to the frontmatter block so a mention in body prose cannot be
# picked up: the over-fire mode that ruled out a whole-file scan.
disposition_of() {
    awk '
        NR == 1 && $0 != "---" { exit }
        NR == 1 { infm = 1; next }
        infm && $0 == "---" { exit }
        infm && /^archive-disposition:[[:space:]]*/ {
            sub(/^archive-disposition:[[:space:]]*/, "")
            sub(/[[:space:]]*$/, "")
            gsub(/^["'"'"']|["'"'"']$/, "")
            print
            exit
        }
    ' "$1"
}

# shipped | superseded -> shipped-side ; dropped | deferred -> dormant-side
side_of() {
    case "$1" in
        shipped|superseded) echo "$SHIPPED_DIR" ;;
        dropped|deferred)   echo "$DORMANT_DIR" ;;
        *)                  echo "" ;;
    esac
}

# scan_root <root>. <root> is expected to contain shipped-design-specs/ and/or
# dormant-explorations/. Results land in the globals SCAN_VIOLATIONS (array),
# SCAN_GATED and SCAN_UNGATED.
#
# Deliberately NOT printing to stdout: a caller would then naturally write
# `v=$(scan_root ...)`, which runs the function in a subshell and silently
# discards the counters. That exact bug shipped in the first draft of this file
# and made the gate report PASS over a scan of zero files, which is why the
# zero-file guard below exists.
declare -a SCAN_VIOLATIONS=()
SCAN_UNGATED=0
SCAN_GATED=0
scan_root() {
    local root="$1" dir f disp want got
    SCAN_VIOLATIONS=()
    SCAN_UNGATED=0
    SCAN_GATED=0
    for dir in "$SHIPPED_DIR" "$DORMANT_DIR"; do
        [ -d "$root/$dir" ] || continue
        for f in "$root/$dir"/*.md; do
            [ -e "$f" ] || continue
            is_index_file "$f" && continue
            disp=$(disposition_of "$f")
            if [ -z "$disp" ]; then
                SCAN_UNGATED=$((SCAN_UNGATED + 1))
                continue
            fi
            SCAN_GATED=$((SCAN_GATED + 1))
            want=$(side_of "$disp")
            if [ -z "$want" ]; then
                SCAN_VIOLATIONS+=("$f: archive-disposition '$disp' is not one of shipped|superseded|dropped|deferred")
                continue
            fi
            got="$dir"
            if [ "$want" != "$got" ]; then
                SCAN_VIOLATIONS+=("$f: archive-disposition '$disp' belongs in $want/, found in $got/")
            fi
        done
    done

    # A declaration in an archive directory the invariant does not govern
    # (professor-reviews/, wasm-investigations/, any future category) is a claim
    # this gate cannot honor. Ignoring it silently is how an opt-in field stops
    # covering anything: the author believes the file is gated and it is not.
    for dir in "$root"/*/; do
        dir="${dir%/}"
        case "$(basename "$dir")" in
            "$SHIPPED_DIR"|"$DORMANT_DIR") continue ;;
        esac
        for f in "$dir"/*.md; do
            [ -e "$f" ] || continue
            is_index_file "$f" && continue
            disp=$(disposition_of "$f")
            [ -n "$disp" ] || continue
            SCAN_VIOLATIONS+=("$f: declares archive-disposition '$disp' outside the governed directories ($SHIPPED_DIR/, $DORMANT_DIR/); the field does not apply here")
        done
    done
}

fail() {
    echo "DRIFT-DOC-3 FAIL: $*" >&2
    exit 1
}

# ---------------------------------------------------------------- self-test ---
FIXTURE_ROOT="scripts/doc-archive-fixtures"
[ -d "$FIXTURE_ROOT/pass" ] && [ -d "$FIXTURE_ROOT/fail" ] \
    || fail "self-test fixtures missing under $FIXTURE_ROOT (expected pass/ and fail/)"

scan_root "$FIXTURE_ROOT/pass"
[ "${#SCAN_VIOLATIONS[@]}" -eq 0 ] || fail "self-test: pass/ fixtures reported ${#SCAN_VIOLATIONS[@]} violation(s), gate over-fires:
$(printf '  %s\n' "${SCAN_VIOLATIONS[@]}")"
[ "$SCAN_GATED" -eq 4 ] || fail "self-test: pass/ scanned $SCAN_GATED gated file(s), expected 4 (one per vocabulary value)"

scan_root "$FIXTURE_ROOT/fail"
[ "${#SCAN_VIOLATIONS[@]}" -eq 4 ] \
    || fail "self-test: fail/ fixtures produced ${#SCAN_VIOLATIONS[@]} violation(s), expected 4 (mis-filed shipped-side, mis-filed dormant-side, unknown value, stray declaration outside the governed dirs). Gate under-fires:
$(printf '  %s\n' "${SCAN_VIOLATIONS[@]:-<none>}")"

echo "DRIFT-DOC-3 self-test OK: pass/ clean over 4 values, fail/ caught 4 of 4"

# ------------------------------------------------------------------ real run ---
scan_root "docs/archive"
gated=$SCAN_GATED
ungated=$SCAN_UNGATED
scanned=$((gated + ungated))

# A gate that silently scans nothing reports PASS forever. If the governed
# directories are renamed or moved, that is a gate failure, not a clean run.
[ "$scanned" -gt 0 ] \
    || fail "scanned 0 files under docs/archive/{$SHIPPED_DIR,$DORMANT_DIR}, the governed directories are missing or renamed"

if [ "${#SCAN_VIOLATIONS[@]}" -gt 0 ]; then
    echo
    echo "DRIFT-DOC-3 FAIL: ${#SCAN_VIOLATIONS[@]} archived doc(s) sit in a directory their declared disposition contradicts" >&2
    echo >&2
    printf '  ✘ %s\n' "${SCAN_VIOLATIONS[@]}" >&2
    echo >&2
    echo "A reader who finds a dropped or deferred design under $SHIPPED_DIR/ concludes it is" >&2
    echo "realized in the compiler. Move the file, or correct its archive-disposition, whichever" >&2
    echo "of the two records is the wrong one." >&2
    exit 1
fi

if [ "$ungated" -gt "$UNGATED_BOUND" ]; then
    echo
    echo "DRIFT-DOC-3 FAIL: $ungated archived doc(s) declare no archive-disposition, above the bound of $UNGATED_BOUND" >&2
    echo "Add 'archive-disposition: shipped|superseded|dropped|deferred' to the new file's frontmatter," >&2
    echo "or raise UNGATED_BOUND in $0 and say why in the commit message." >&2
    exit 1
fi

echo "DRIFT-DOC-3 PASS: $gated declared disposition(s) agree with their directory"
if [ "$ungated" -lt "$UNGATED_BOUND" ]; then
    echo "DRIFT-DOC-3 NOTE: $ungated ungated file(s) against a bound of $UNGATED_BOUND, lower UNGATED_BOUND to $ungated."
else
    echo "DRIFT-DOC-3 NOTE: $ungated ungated file(s), at the bound."
fi
exit 0
