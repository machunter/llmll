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
            wasi_fs_list wasi_fs_mkdir wasi_fs_sha256 \
            wasi_clock_monotonic wasi_proc_run \
            seq_commands \
            json_parse json_serialize json_get json_get_string json_get_int \
            json_get_bool json_get_number json_array json_object json_set \
            json_of_string json_of_int json_of_bool json_of_list; do
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

# --- 5. EXECUTION gate (CAP-PROC). ------------------------------------------
#
# Everything above proves the preamble COMPILES. That is not the property
# WASI-RT was about. Its stopgap wasi.fs.read performed a read and discarded
# the result; it compiled, linked, raised nothing on an unreadable path, and
# passed every check in this script. readFile is lazy, a spawned process can go
# unwaited, and a "hash" can be a rolling polynomial returning twenty plausible
# bytes -- sha1_hash in the same preamble is exactly that and shipped for four
# releases. GHC sees none of it.
#
# So this stage RUNS a second fixture and compares against answers computed
# outside the program:
#
#   wasi.fs.sha256       NIST SHA-256 vector for "abc"
#   wasi.proc.run        a string only a real /bin/echo can have written, read
#                        back from the redirect file (a spawn that is created
#                        and never waited on fails here, not above)
#   wasi.clock.monotonic a positive integer
#   wasi.fs.mkdir        implicit: every later step writes into the directory
#
# The console harness consumes one stdin line per step, so the input below is
# the step budget, not data.

EXEC_FIXTURE="${EXEC_FIXTURE:-$REPO_ROOT/scripts/build-smoke/capproc_exec.llmll}"
EXEC_OUTDIR="$OUTDIR/exec"
# Literal /tmp, not $TMPDIR: the fixture hardcodes this path because LLMLL has
# no way to read an environment variable, and its (capability read-write "/tmp")
# clause names the same root. On macOS $TMPDIR is a per-user /var/folders path,
# so deriving it here would check a directory the program never touches.
EXEC_SCRATCH="/tmp/llmll-capproc-exec"

if [ -f "$EXEC_FIXTURE" ]; then
  echo "BUILD-GATE-1: building and RUNNING $(basename "$EXEC_FIXTURE")"
  rm -rf "$EXEC_SCRATCH"
  EXEC_LOG="$OUTDIR/.exec-build.log"
  if ! "${LLMLL_CMD[@]}" build "$EXEC_FIXTURE" -o "$EXEC_OUTDIR" > "$EXEC_LOG" 2>&1; then
    cat "$EXEC_LOG" >&2
    fail "the execution fixture does not build."
  fi

  EXE="$(find "$EXEC_OUTDIR/.stack-work/install" -type f -name capproc-exec -perm -111 2>/dev/null | head -1)"
  [ -n "$EXE" ] || fail "built the execution fixture but found no capproc-exec
  binary under $EXEC_OUTDIR/.stack-work/install. Without running it this stage
  observes nothing, which is the failure mode it exists to prevent."

  # Run from OUTDIR, not the caller's cwd: the console harness writes a
  # <module>.event-log.jsonl beside wherever it runs, and CI's cwd is the repo
  # root. Without this the gate litters a tracked directory on every run.
  RUN_OUT="$(cd "$OUTDIR" && printf 'x\n%.0s' $(seq 12) | "$EXE" 2>&1)" || true

  # SHA-256("abc"), FIPS 180-4. A stub that derives bytes from its input passes
  # every other assertion in this file and fails this one.
  EXPECT_SHA="ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"

  EXEC_FAIL=()
  case "$RUN_OUT" in *"sha256=$EXPECT_SHA"*) ;; *) EXEC_FAIL+=("wasi.fs.sha256 did not produce the NIST vector for \"abc\"");; esac
  case "$RUN_OUT" in *"exit=0"*)             ;; *) EXEC_FAIL+=("wasi.proc.run did not report exit 0");; esac
  case "$RUN_OUT" in *"echo=capproc-echo-ok"*) ;; *) EXEC_FAIL+=("wasi.proc.run's child output did not round-trip through the redirect file");; esac
  if ! printf '%s' "$RUN_OUT" | grep -qE 'clock=[0-9]+'; then
    EXEC_FAIL+=("wasi.clock.monotonic did not return a positive integer")
  fi
  [ -d "$EXEC_SCRATCH" ] || EXEC_FAIL+=("wasi.fs.mkdir did not create $EXEC_SCRATCH")

  # JSON-1. "jr=42" is a four-way conjunction: json-set replaced the existing
  # "n" instead of appending a second member (42, not 41), json-serialize kept
  # both members, json-parse read them back, and both typed projections hit the
  # right lexeme. A parser returning an empty object passes every type check in
  # the fixture and fails this.
  case "$RUN_OUT" in *"json=jr=42"*) ;; *) EXEC_FAIL+=("the JSON round trip did not yield jr=42; json-set, json-serialize, json-parse, or a typed projection is wrong");; esac
  # RFC 7493 §2.3, compared after unescaping. Last-wins is the permissive
  # reading RFC 8259 §4 allows and this implementation deliberately refuses.
  case "$RUN_OUT" in *"dup=rejected"*) ;; *) EXEC_FAIL+=("json-parse accepted an object with duplicate member names (RFC 7493 §2.3)");; esac
  # Ten adversarial inputs, verdicts hand-computed in the fixture. Both
  # degenerate parsers (accept-everything, reject-everything) differ from this
  # string in its first character, so the assertion cannot pass vacuously.
  case "$RUN_OUT" in *"battery=ARRRRRRAAR"*) ;; *) EXEC_FAIL+=("the adversarial parse battery did not match ARRRRRRAAR; json-parse accepts or rejects the wrong inputs");; esac

  if [ "${#EXEC_FAIL[@]}" -gt 0 ]; then
    printf 'BUILD-GATE-1 execution failures:\n' >&2
    for f in "${EXEC_FAIL[@]}"; do printf '  - %s\n' "$f" >&2; done
    printf -- '--- program output ---\n%s\n' "$RUN_OUT" >&2
    fail "the CAP-PROC bodies compiled but did not behave. A body that links and
  does nothing is the WASI-RT defect class; this stage is its only oracle."
  fi

  rm -rf "$EXEC_SCRATCH"
  echo "BUILD-GATE-1 PASS: CAP-PROC operations executed and matched known answers"
fi

# --- 6. REPLAY gate (REPLAY-FRAME). -----------------------------------------
#
# Before this stage, `llmll replay` was executed by NO gate: not this script,
# not check-examples.sh, not refute-crux-gate.sh, not pytest, not any CI job.
# Its only coverage was three unit tests driving runReplay against bash mocks,
# and those mocks framed their output differently from the emitter, so they
# passed while three separate divergence classes shipped (unlogged :init
# output, an unmatchable RC-4 settle entry, and any event whose output was not
# exactly one line). The pattern is the same one that justifies stage 5: a
# component with no end-to-end oracle drifts from the emitter that feeds it.
#
# Two fixtures, because they cover different halves:
#   replay-demo      the shipped example, no :done? -- proves no regression on
#                    the one program anyone runs by hand
#   replay_settle    :done? + :on-done -- the RC-4 settle entry, which is the
#                    shape that could not replay clean at all
#
# Each is asserted BOTH ways. A tampered log must make replay fail: a replay
# gate whose oracle never reports divergence is indistinguishable from one that
# always returns 2/2, which is the dead-gate mode this file's header names.

REPLAY_DIR="$OUTDIR/replay"
mkdir -p "$REPLAY_DIR"

replay_case() {
  # $1 = source path, $2 = module name, $3 = stdin line count, $4 = expected "N/N"
  local src="$1" mod="$2" lines="$3" expect="$4"
  [ -f "$src" ] || { echo "  skip $mod (fixture not found: $src)"; return 0; }
  cp "$src" "$REPLAY_DIR/$mod.llmll"

  ( cd "$REPLAY_DIR" && "${LLMLL_CMD[@]}" build "$mod.llmll" ) > "$REPLAY_DIR/$mod.build.log" 2>&1 \
    || { cat "$REPLAY_DIR/$mod.build.log" >&2; fail "replay fixture $mod does not build"; }

  # BUG-2 (v0.14.3): the executable's on-disk name is the hpack/Cabal-sanitized
  # package name (underscores -> hyphens, CodegenHs.sanitizePkgName), not the
  # filename-derived module name. capproc_exec builds capproc-exec for the same
  # reason (stage 5 above hardcodes that).
  local exe exe_name="${mod//_/-}"
  exe="$(find "$REPLAY_DIR/generated/$mod/.stack-work/install" -type f -name "$exe_name" -perm -111 2>/dev/null | head -1)"
  [ -n "$exe" ] || fail "built $mod but found no executable named '$exe_name'; the replay stage would observe nothing"

  # Record. The harness writes <module>.event-log.jsonl into its own cwd.
  ( cd "$REPLAY_DIR" && printf 'x\n%.0s' $(seq "$lines") | "$exe" ) > "$REPLAY_DIR/$mod.run.out" 2>&1 || true
  local log="$REPLAY_DIR/$mod.event-log.jsonl"
  [ -f "$log" ] || fail "$mod produced no event log at $log"

  # Replay must reproduce it exactly.
  local out rc
  out="$( cd "$REPLAY_DIR" && "${LLMLL_CMD[@]}" replay "$mod.llmll" "$mod.event-log.jsonl" 2>&1 )"
  rc=$?
  case "$out" in
    *"$expect events matched"*) ;;
    *) printf -- '--- replay output ---\n%s\n' "$out" >&2
       fail "$mod did not replay $expect. A recorded run that cannot be replayed
  is the defect class this stage exists for.";;
  esac
  [ "$rc" -eq 0 ] || { printf -- '--- replay output ---\n%s\n' "$out" >&2
                       fail "$mod replayed $expect but exited $rc"; }

  # Refute-crux: perturb every recorded stdout value and the verdict must flip.
  # Prefixing rather than substituting a literal keeps this independent of what
  # the fixture happens to print, so the crux cannot rot into a no-op when a
  # fixture's output changes. A kind="none" entry is deliberately untouched:
  # it records that nothing was written, so there is no value to corrupt.
  local tampered="$REPLAY_DIR/$mod.tampered.jsonl"
  sed 's/"kind":"stdout","value":"/"kind":"stdout","value":"TAMPERED-/g' \
    "$log" > "$tampered"
  if cmp -s "$log" "$tampered"; then
    fail "the $mod refute-crux did not perturb anything, so it proves nothing.
  Its sed pattern no longer matches the log's recorded values."
  fi
  local tout trc
  tout="$( cd "$REPLAY_DIR" && "${LLMLL_CMD[@]}" replay "$mod.llmll" "$(basename "$tampered")" 2>&1 )"
  trc=$?
  [ "$trc" -ne 0 ] || { printf -- '--- replay output ---\n%s\n' "$tout" >&2
                        fail "$mod replayed a TAMPERED log successfully. The oracle
  does not discriminate, so its green verdict on the real log means nothing."; }

  echo "  $mod: replayed $expect, tampered log correctly refuted"
}

echo "BUILD-GATE-1: replaying recorded runs"
replay_case "$REPO_ROOT/examples/replay-demo/replay-demo.llmll" "replay-demo"   2 "2/2"
replay_case "$REPO_ROOT/scripts/build-smoke/replay_settle.llmll" "replay_settle" 2 "2/2"

# W-REPLAY-INIT must fire on a program that declares :init, or the warning
# added for the unlogged-:init hazard is dead code. Emitted by `llmll replay`,
# not by `llmll build`, so this re-runs replay rather than reading the build log.
if [ -f "$REPLAY_DIR/replay_settle.llmll" ]; then
  RS_WARN="$( cd "$REPLAY_DIR" && "${LLMLL_CMD[@]}" replay replay_settle.llmll replay_settle.event-log.jsonl 2>&1 )"
  case "$RS_WARN" in
    *W-REPLAY-INIT*) ;;
    *) printf -- '--- replay output ---\n%s\n' "$RS_WARN" >&2
       fail "W-REPLAY-INIT did not fire on a program declaring :init. The warning
  exists because an :init that prints breaks replay alignment; if it never
  fires it warns nobody.";;
  esac
  # And it must NOT fire on a program with no :init, or it is unconditional
  # noise rather than a signal.
  RD_WARN="$( cd "$REPLAY_DIR" && "${LLMLL_CMD[@]}" replay replay-demo.llmll replay-demo.event-log.jsonl 2>&1 )"
  case "$RD_WARN" in
    *W-REPLAY-INIT*) fail "W-REPLAY-INIT fired on replay-demo, which declares no
  :init. A warning that fires on every program is not a warning.";;
  esac
fi

echo "BUILD-GATE-1 PASS: recorded runs replay clean and tampered logs are refuted"

exit 0
