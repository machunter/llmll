#!/usr/bin/env bash
# BUILD-GATE-1 — end-to-end build gate.
#
# Compiles scripts/build-smoke/smoke.llmll all the way through GHC and fails if
# it does not link. Sibling of scripts/doc_claims_gate.sh (DRIFT-CT-2, doc
# claims vs compiler behaviour) and scripts/version_gate.sh (DRIFT-CI-1,
# banner/schema drift). This one is the only gate in the repository whose
# oracle is the Haskell compiler.
#
# WHY THIS EXISTS
#
# Before this gate, no job invoked `llmll build`. check-examples.sh typechecks.
# The corpus was a check-only corpus, so a defect that passes `llmll check` and
# dies at GHC was invisible to CI. Three such defects were found in one release:
# WASI-RT (four declared wasi.* builtins with no preamble definition), the
# def-main :step arity change (checkStatement discards inferExpr's result, so no
# program reports it), and IFACE-CONFORM. The pattern, not any single defect,
# is the justification.
#
# WHY IT IS NOT JUST `llmll build && echo ok`
#
# `llmll build`'s internal self-check FAILS OPEN. runGhcCheck (compiler/app/
# Main.hs:911-940) shells out to `stack build`, falls back to `ghc --make`, and
# when NEITHER is on PATH it returns True and the build reports success having
# compiled nothing. A gate that only reads the exit code therefore goes green in
# any environment without a toolchain, while observing nothing at all. That is
# the dead-gate failure mode this gate was created to prevent, so:
#
#   1. `stack` (or `ghc`) must be on PATH, or the gate FAILS. It does not skip.
#      This is a deliberate departure from doc_claims_gate.sh, which skips when
#      no binary is found. That is right for a behaviour-comparison gate and
#      wrong for a build gate: a skipped build gate is indistinguishable from a
#      passing one in the CI summary.
#   2. The emitted src/Lib.hs is asserted to define every wasi_* name the
#      fixture calls, so a fail-open runGhcCheck cannot carry a green verdict
#      on its own.
#
# Binary resolution: $LLMLL_BIN, else `llmll` on PATH, else ~/.local/bin/llmll.
# In CI, LLMLL_BIN is set to the freshly-built binary. A missing binary is a
# FAILURE here, not a skip, for the reason above.
#
# Exit 0 = the fixture built; exit 1 = it did not, or the gate could not run.

set -u
set -o pipefail

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
FIXTURE="${FIXTURE:-$REPO_ROOT/scripts/build-smoke/smoke.llmll}"
OUTDIR="${OUTDIR:-$(mktemp -d "${TMPDIR:-/tmp}/llmll-build-smoke.XXXXXX")}"
KEEP_OUTDIR="${KEEP_OUTDIR:-0}"

cleanup() {
  if [ "$KEEP_OUTDIR" != "1" ]; then rm -rf "$OUTDIR"; fi
}
trap cleanup EXIT

fail() { echo "BUILD-GATE-1 FAIL: $*" >&2; exit 1; }

# --- 1. Toolchain must be present. Fail-closed, never skip. ------------------

if ! command -v stack >/dev/null 2>&1 && ! command -v ghc >/dev/null 2>&1; then
  fail "neither 'stack' nor 'ghc' is on PATH. This gate compiles generated
  Haskell; without a toolchain it would pass while observing nothing
  (runGhcCheck returns True in that case — compiler/app/Main.hs:940). Install
  Stack from https://haskellstack.org, or set PATH, and re-run."
fi

# --- 2. Compiler binary. --------------------------------------------------

if [ -n "${LLMLL_BIN:-}" ]; then
  # May be a multi-word invocation, e.g. "stack exec llmll --".
  read -r -a LLMLL_CMD <<< "$LLMLL_BIN"
elif command -v llmll >/dev/null 2>&1; then
  LLMLL_CMD=(llmll)
elif [ -x "$HOME/.local/bin/llmll" ]; then
  LLMLL_CMD=("$HOME/.local/bin/llmll")
else
  fail "no llmll binary found. Set LLMLL_BIN, put llmll on PATH, or install to
  ~/.local/bin. A missing binary is a failure here, not a skip: see the header."
fi

[ -f "$FIXTURE" ] || fail "fixture not found: $FIXTURE"

echo "BUILD-GATE-1: building $(basename "$FIXTURE") with ${LLMLL_CMD[*]}"

# --- 3. Build. -------------------------------------------------------------

BUILD_LOG="$OUTDIR/.build.log"
if ! "${LLMLL_CMD[@]}" build "$FIXTURE" -o "$OUTDIR" > "$BUILD_LOG" 2>&1; then
  echo "--- llmll build output ---" >&2
  cat "$BUILD_LOG" >&2
  fail "the fixture does not build. This is the defect class the gate exists
  for: it passes 'llmll check' and fails at GHC."
fi

# --- 4. Independent corroboration that something was actually compiled. -----
#
# Guards against a fail-open runGhcCheck reporting success on an emitted file
# that never reached GHC. Every wasi_* name the fixture calls must have a
# top-level definition in the emitted preamble.

LIB="$OUTDIR/src/Lib.hs"
[ -f "$LIB" ] || fail "no src/Lib.hs emitted at $LIB"

MISSING=()
for name in wasi_io_stdout wasi_io_stderr wasi_http_response \
            wasi_fs_read wasi_fs_write wasi_fs_delete wasi_http_post \
            seq_commands; do
  grep -qE "^${name} " "$LIB" || MISSING+=("$name")
done

if [ "${#MISSING[@]}" -gt 0 ]; then
  fail "src/Lib.hs is missing a definition for: ${MISSING[*]}
  The build reported success, which means it did not actually reach GHC
  (see runGhcCheck's fail-open path) or the preamble drifted from builtinEnv."
fi

if ! grep -q "stack build OK\|ghc OK" "$BUILD_LOG"; then
  fail "build reported success but the log shows no GHC invocation. Fail-open
  path taken; the gate refuses to report green on an uncompiled fixture.
  Log follows:
$(cat "$BUILD_LOG")"
fi

echo "BUILD-GATE-1 PASS: fixture compiled through GHC; ${#MISSING[@]} missing preamble definitions"
exit 0
