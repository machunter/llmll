#!/usr/bin/env bash
# DRIFT-CI-1 version-gate — criteria C1..C4 from
# docs/design/critique-2026-05-23-triage.md row :111.
#
#   C1  README.md banner == LLMLL.md banner
#       (extended to: package.yaml + llmll.cabal also equal)
#   C2  LLMLL.md banner == CHANGELOG.md top "## vX.Y.Z" heading
#   C3  docs/llmll-ast.schema.json schemaVersion const
#         == compiler/src/LLMLL/ParserJSON.hs::expectedSchemaVersion
#   C4  docs/llmll-ast.schema.json $id URL contains
#         "/schemas/v<MAJOR>.<MINOR>/" derived from schemaVersion
#
# Exits 0 on all-pass; exits 1 on first failure with a single-line message.
# Runs without Stack/GHC. Requires bash, grep, awk, jq.

set -u
set -o pipefail

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$REPO_ROOT"

fail() {
    echo "DRIFT-CI-1 FAIL: $*" >&2
    exit 1
}

SEMVER='[0-9]+\.[0-9]+\.[0-9]+'

readme_v=$(head -n 1 README.md | grep -oE "v${SEMVER}" | head -n 1) \
    || true
[ -n "${readme_v:-}" ] || fail "C1 could not extract vX.Y.Z from README.md line 1"

llmll_v=$(head -n 1 LLMLL.md | grep -oE "v${SEMVER}" | head -n 1) \
    || true
[ -n "${llmll_v:-}" ] || fail "C1 could not extract vX.Y.Z from LLMLL.md line 1"

changelog_v=$(grep -m1 -oE "^## v${SEMVER}" CHANGELOG.md | head -n 1) \
    || true
[ -n "${changelog_v:-}" ] || fail "C2 could not extract top-level '## vX.Y.Z' from CHANGELOG.md"
changelog_v="${changelog_v#'## '}"

package_v=$(awk '/^version:/{print $2; exit}' compiler/package.yaml) \
    || true
[ -n "${package_v:-}" ] || fail "C1 could not extract version from compiler/package.yaml"
package_v="v${package_v}"

cabal_v=$(awk '/^version:/{print $2; exit}' compiler/llmll.cabal) \
    || true
[ -n "${cabal_v:-}" ] || fail "C1 could not extract version from compiler/llmll.cabal"
cabal_v="v${cabal_v}"

[ "$readme_v" = "$llmll_v" ] \
    || fail "C1 README.md banner ($readme_v) != LLMLL.md banner ($llmll_v)"
[ "$llmll_v" = "$changelog_v" ] \
    || fail "C2 LLMLL.md banner ($llmll_v) != CHANGELOG.md top heading ($changelog_v)"
[ "$llmll_v" = "$package_v" ] \
    || fail "C1 LLMLL.md banner ($llmll_v) != compiler/package.yaml version ($package_v)"
[ "$llmll_v" = "$cabal_v" ] \
    || fail "C1 LLMLL.md banner ($llmll_v) != compiler/llmll.cabal version ($cabal_v)"

schema_sv=$(jq -er '."$defs".Program.properties.schemaVersion.const' \
                docs/llmll-ast.schema.json) \
    || fail "C3 could not read schemaVersion const from docs/llmll-ast.schema.json"

parser_sv=$(grep -E 'expectedSchemaVersion[[:space:]]*=' \
                compiler/src/LLMLL/ParserJSON.hs \
            | grep -oE '"[0-9]+\.[0-9]+\.[0-9]+"' \
            | head -n 1 \
            | tr -d '"')
[ -n "$parser_sv" ] \
    || fail "C3 could not read expectedSchemaVersion from compiler/src/LLMLL/ParserJSON.hs"

[ "$schema_sv" = "$parser_sv" ] \
    || fail "C3 schema schemaVersion ($schema_sv) != ParserJSON.expectedSchemaVersion ($parser_sv)"

schema_id=$(jq -er '."$id"' docs/llmll-ast.schema.json) \
    || fail "C4 could not read \$id from docs/llmll-ast.schema.json"

schema_mm=$(printf '%s' "$schema_sv" | awk -F. '{print "v" $1 "." $2}')

case "$schema_id" in
    *"/schemas/${schema_mm}/"*) ;;
    *) fail "C4 schema \$id URL ($schema_id) lacks /schemas/${schema_mm}/ (derived from schemaVersion $schema_sv)" ;;
esac

echo "DRIFT-CI-1 PASS:"
echo "  banner       $llmll_v   (README, LLMLL.md, CHANGELOG, package.yaml, llmll.cabal)"
echo "  schemaVer    $schema_sv (schema.const == ParserJSON.expectedSchemaVersion)"
echo "  \$id          $schema_id (URL contains /schemas/${schema_mm}/)"
