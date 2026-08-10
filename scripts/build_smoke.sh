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

# --- 2a. Anchor the compiler to an ABSOLUTE path, before anything cd's. ------
#
# Several stages below invoke the compiler from a DIFFERENT directory: the
# replay stage cd's into $REPLAY_DIR (inside the temp $OUTDIR) and the DRIVER-LL
# stage cd's into tools/llmll-driver. A project-relative invocation re-resolves
# against that new cwd and dies there. MEASURED, CI run 30938236092, with
# LLMLL_BIN="stack exec llmll --" -- which is exactly what
# .github/workflows/version-gate.yml:130 sets:
#
#   BUILD-GATE-1: replaying recorded runs
#   Executable named llmll not found on path:
#     ["/tmp/llmll-build-smoke.DMRLnw/.stack-work/install/...", ...]
#
# stack had taken the temp OUTDIR for its project root, because that is where it
# was standing. Resolving once HERE, while the cwd is still the one the caller
# chose, makes every later invocation cwd-independent. This never fired on macOS
# because local runs put llmll on PATH as an absolute path already.
case "${LLMLL_CMD[0]}" in
  stack)
    _SIR="$(stack path --local-install-root 2>/dev/null || true)"
    if [ -z "$_SIR" ] || [ ! -x "$_SIR/bin/llmll" ]; then
      _SIR="$( (cd "$REPO_ROOT/compiler" && stack path --local-install-root) 2>/dev/null || true)"
    fi
    { [ -n "$_SIR" ] && [ -x "$_SIR/bin/llmll" ]; } || fail "LLMLL_BIN is
  '${LLMLL_CMD[*]}' but no llmll binary exists under \`stack path
  --local-install-root\`, from either \$PWD or $REPO_ROOT/compiler. Build it
  first: (cd compiler && stack build)."
    # The trailing '--' of "stack exec llmll --" is dropped with the wrapper; it
    # only ever separated stack's own flags from the compiler's.
    LLMLL_CMD=("$_SIR/bin/llmll")
    ;;
  /*) ;;   # already absolute — nothing to anchor
  *)
    _ABS="$(command -v "${LLMLL_CMD[0]}" 2>/dev/null || true)"
    case "$_ABS" in
      /*) LLMLL_CMD[0]="$_ABS" ;;
      ?*) LLMLL_CMD[0]="$(cd "$(dirname "$_ABS")" && pwd)/$(basename "$_ABS")" ;;
      *)  fail "LLMLL_BIN names '${LLMLL_CMD[0]}', which does not resolve to an
  executable. It must be runnable from any directory, because stages below run
  it from inside \$OUTDIR." ;;
    esac
    ;;
esac

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
            wasi_clock_monotonic wasi_proc_run wasi_proc_args \
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

# --- 4b. REGEX-LOWER-1: a builtin that checks, verifies, and does not build. -
#
# This stage is the ONLY gate that can see this defect class. `regex-match`
# passed `llmll check` at exit 0 with no warning and `llmll verify` as SAFE,
# then failed at GHC, because Parser.hs's isOperator named it and emitOp's
# fallback intercalated the operator name between its arguments. A check-time
# fixture would have been green on both sides of the fix.
#
# Two assertions, and the second is the one that does not decay. Building is
# necessary but a future refactor could make the module build while emitting
# something other than the preamble binding, so the call site is asserted
# directly.

RX_FIXTURE="$REPO_ROOT/scripts/build-smoke/regex_lower.llmll"
RX_OUTDIR="$OUTDIR/regex-lower"
RX_LOG="$OUTDIR/.regex-lower.log"

[ -f "$RX_FIXTURE" ] || fail "REGEX-LOWER-1 fixture missing at $RX_FIXTURE"

if ! "${LLMLL_CMD[@]}" build "$RX_FIXTURE" -o "$RX_OUTDIR" > "$RX_LOG" 2>&1; then
  echo "--- llmll build output ---" >&2
  cat "$RX_LOG" >&2
  fail "the REGEX-LOWER-1 fixture does not build. If GHC reports
  'Variable not in scope: regex', then isOperator (Parser.hs) is naming
  'regex-match' again and emitOp's fallback is emitting it infix. That call
  must parse as an EApp so emitApp's default applies toHsIdent and binds the
  preamble's regex_match."
fi

RX_LIB="$RX_OUTDIR/src/Lib.hs"
[ -f "$RX_LIB" ] || fail "REGEX-LOWER-1: no src/Lib.hs emitted at $RX_LIB"

# The prefix call, not merely the preamble definition: grep for an APPLICATION.
grep -qE 'regex_match \(' "$RX_LIB" || fail "REGEX-LOWER-1: src/Lib.hs has no
  prefix application of regex_match. The preamble defines it; if nothing calls
  it the builtin is dead again, which is the state this gate exists to detect."

# The hyphenated spelling must not survive into emitted Haskell AT ALL.
#
# An earlier draft of this assertion matched '[a-z_]+ regex-match ', modelled on
# the `(p regex-match s)` form. That cell was WRONG BY CONSTRUCTION: this
# fixture's first def passes a string LITERAL, whose emission is
# `("^[a-f0-9]{64}$" regex-match s)`, and the character before the operator is a
# quote rather than an identifier, so the pattern missed the very call it was
# written for. Measured on both sides instead: a correct build contains ZERO
# occurrences of the hyphenated spelling, the preamble carrying `regex_match`
# and a comment that says "regex patterns". So test for zero.
if grep -q 'regex-match' "$RX_LIB"; then
  echo "--- offending lines ---" >&2
  grep -n 'regex-match' "$RX_LIB" >&2
  fail "REGEX-LOWER-1: src/Lib.hs contains the hyphenated 'regex-match'. GHC
  lexes that hyphen as subtraction. isOperator must not name anything emitOp
  cannot lower; the call must reach emitApp and be mangled by toHsIdent."
fi

echo "BUILD-GATE-1 PASS: REGEX-LOWER-1 fixture compiled and binds regex_match prefix"

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

# --- 5b. FS ENCODING + BYTE-FAITHFUL COPY (FS-ENCODING-1, FS-COPY-1). --------
#
# Two properties that only a RUNNING program settles, and that were both
# asserted from source before they were measured.
#
# The encoding half runs under LC_ALL=C on purpose. Before the UTF-8 pin, a
# POSIX-locale write of any non-ASCII string failed to encode and a read of a
# valid UTF-8 file failed to decode, each surfacing as a spurious RErr on input
# the program was right about. Nothing crashed, because llmll_publish_io's `try`
# already made the failure a value, so this stage asserts a SUCCESSFUL round
# trip rather than the absence of a traceback. A gate written against the
# crash-freedom framing would have passed before the fix.
#
# The copy half compares two digests. That is the only byte-faithfulness check
# expressible from inside the language, and it is why the fixture prints both
# rather than deciding its own verdict. Note that read-then-write cannot even
# be attempted here: wasi.fs.read of this input returns RErr under UTF-8 as
# much as under any other encoding, which is precisely why wasi.fs.copy exists.
FSENC_FIXTURE="$REPO_ROOT/scripts/build-smoke/fs_encoding.llmll"
FSENC_OUTDIR="$OUTDIR/fsenc"
FSENC_SCRATCH="/tmp/llmll-fsenc"

if [ -f "$FSENC_FIXTURE" ]; then
  echo "BUILD-GATE-1: building and RUNNING $(basename "$FSENC_FIXTURE") under LC_ALL=C"
  rm -rf "$FSENC_SCRATCH"; mkdir -p "$FSENC_SCRATCH"
  # The binary input is created HERE: a .llmll string literal cannot carry a
  # lone 0xFF, so the fixture cannot author its own adversarial input.
  printf 'binary \377\376\000 raw\n' > "$FSENC_SCRATCH/bin.dat"
  # Multi-buffer, and non-ASCII throughout so it exercises the decoder rather
  # than just the byte count. GHC's default handle buffer is 8K; 4000 lines of
  # this is comfortably past it. This is the input the truncation guard needs:
  # a short string survives a force-after-close and proves nothing.
  awk 'BEGIN{for(i=0;i<4000;i++) printf "line %d section \302\247 padding padding padding\n", i}' \
    > "$FSENC_SCRATCH/big.txt"

  FSENC_LOG="$OUTDIR/.fsenc-build.log"
  if ! "${LLMLL_CMD[@]}" build "$FSENC_FIXTURE" -o "$FSENC_OUTDIR" > "$FSENC_LOG" 2>&1; then
    cat "$FSENC_LOG" >&2
    fail "the fs-encoding fixture does not build."
  fi
  FSENC_EXE="$(find "$FSENC_OUTDIR/.stack-work/install" -type f -name 'fs-encoding' -perm -111 2>/dev/null | head -1)"
  [ -n "$FSENC_EXE" ] || fail "built the fs-encoding fixture but found no fs-encoding binary."

  # DOES LC_ALL=C MEAN ANYTHING TO GHC ON THIS PLATFORM?
  #
  # On Linux/glibc it does: the locale encoding resolves to ANSI_X3.4-1968 and
  # every non-ASCII encode or decode fails. On macOS it does NOT. GHC 9.6.6
  # (aarch64-osx) resolves UTF-8 under LC_ALL=C even though the system's own
  # locale database reports otherwise -- MEASURED 2026-08-05, macOS 25.5.0:
  #
  #   $ LC_ALL=C locale charmap                             -> US-ASCII
  #   $ LC_ALL=C ./probe   # getLocaleEncoding >>= print     -> UTF-8
  #
  # So on macOS the encoding half of this stage is a STRUCTURAL NO-OP. That is
  # not a hypothetical: it reported PASS on the developer's machine for the whole
  # of v0.14.84 while the property it names was false, and its first real
  # execution -- CI run 31035476326 -- failed on the first line it printed. A
  # gate that cannot fail where it runs is worth nothing, and printing PASS for
  # it is how the shipped defect got past review.
  #
  # The assertions still RUN everywhere: the copy and truncation halves are
  # locale-independent and catch regressions on any platform. Only the VERDICT
  # changes. Where the locale cannot be made non-UTF-8 for GHC, this stage says
  # NOT EXERCISED and refuses to claim the LC_ALL=C property it cannot test.
  #
  # The discriminator is the platform, not a probe, because after the fix the
  # program behaves IDENTICALLY under both locales by construction -- so nothing
  # the fixture can print distinguishes them. If GHC on macOS ever starts
  # honouring LC_ALL, this under-claims (loses a claim it could make) rather than
  # over-claims, which is the safe direction to rot in.
  case "$(uname -s)" in
    Darwin) FSENC_LOCALE_HONOURED=0 ;;
    *)      FSENC_LOCALE_HONOURED=1 ;;
  esac

  FSENC_OUT="$(cd "$OUTDIR" && printf 'x\n%.0s' $(seq 12) | LC_ALL=C "$FSENC_EXE" 2>&1)" || true

  FSENC_FAIL=()
  # U+00A7 is the character 45 files in this repository's own corpus carry.
  case "$FSENC_OUT" in *"text=section § marker"*) ;; *)
    FSENC_FAIL+=("the non-ASCII write/read round trip did not survive LC_ALL=C (FS-ENCODING-1)");; esac
  FSENC_SRC="$(printf '%s\n' "$FSENC_OUT" | sed -n 's/^src=//p')"
  FSENC_DST="$(printf '%s\n' "$FSENC_OUT" | sed -n 's/^dst=//p')"
  if [ -z "$FSENC_SRC" ] || [ -z "$FSENC_DST" ]; then
    FSENC_FAIL+=("one or both digests are missing; the copy or a sha256 published RErr")
  elif [ "$FSENC_SRC" != "$FSENC_DST" ]; then
    FSENC_FAIL+=("wasi.fs.copy is not byte-faithful: src=$FSENC_SRC dst=$FSENC_DST (FS-COPY-1)")
  fi
  # Guards the assertion above against passing on a copy that never happened:
  # two absent files would hash to nothing and the digests would both be empty,
  # which the -z branch catches, but a copy of the WRONG file would not.
  cmp -s "$FSENC_SCRATCH/bin.dat" "$FSENC_SCRATCH/bin.copy" \
    || FSENC_FAIL+=("bin.copy does not match bin.dat on disk")
  # The truncation guard. A force moved outside the bracket closes the handle
  # before the string is demanded, and the read returns SHORT with no error.
  if ! cmp -s "$FSENC_SCRATCH/big.txt" "$FSENC_SCRATCH/big.copy"; then
    # `wc -c < missing` fails in the SHELL, before wc runs, so a 2>/dev/null on
    # wc does not suppress it -- the bare "No such file or directory" that led
    # this stage's CI output came from here and named a line number rather than
    # a cause. Report 0 for an absent file instead, which is the fact.
    _bytes() { if [ -f "$1" ]; then wc -c < "$1" | tr -d ' '; else echo 0; fi; }
    FSENC_FAIL+=("the multi-buffer read/write round trip did not preserve the file \
($(_bytes "$FSENC_SCRATCH/big.txt") bytes in, $(_bytes "$FSENC_SCRATCH/big.copy") out); \
the force may have escaped the bracket")
  fi

  if [ "${#FSENC_FAIL[@]}" -gt 0 ]; then
    printf 'BUILD-GATE-1 fs-encoding failures:\n' >&2
    for f in "${FSENC_FAIL[@]}"; do printf '  - %s\n' "$f" >&2; done
    printf -- '--- program output ---\n%s\n' "$FSENC_OUT" >&2
    fail "the fs bodies compiled but did not behave under a POSIX locale."
  fi

  rm -rf "$FSENC_SCRATCH"
  if [ "$FSENC_LOCALE_HONOURED" -eq 1 ]; then
    echo "BUILD-GATE-1 PASS: UTF-8 round trip survived LC_ALL=C; wasi.fs.copy byte-faithful"
  else
    echo "BUILD-GATE-1 PASS: wasi.fs.copy byte-faithful; multi-buffer round trip preserved"
    echo "BUILD-GATE-1 NOT EXERCISED: the LC_ALL=C encoding claim (FS-ENCODING-1).
  GHC on $(uname -s) resolves UTF-8 whatever LC_ALL says, so this run cannot
  distinguish a working pin from a missing one. Only Linux CI settles it; do not
  read this stage's green as evidence for the encoding half. See the note above."
  fi
fi

# --- 5b. CAPTURE-ENCODING-1 gate. -------------------------------------------
#
# Can a console program put a non-ASCII character from its own string literal
# onto its own stdout?
#
# UNLIKE STAGE 5 ABOVE, THIS STAGE IS EXERCISED EVERYWHERE, and the difference
# matters enough to state. Stage 5 can only decide its encoding claim where the
# locale reaches GHC, which is not macOS, so it prints NOT EXERCISED there. This
# defect had nothing to do with the locale: it reproduced under en_US.UTF-8 on
# macOS and would reproduce under any locale on any platform, because
# System.Posix.IO.fdToHandle returns a handle in BINARY mode and a binary handle
# has no codec for a locale to inform. So this verdict is real everywhere.
#
# WHY IT EXISTS. Before scripts/build-smoke/capture_encoding.llmll, no committed
# .llmll carried a non-ASCII character in a string literal that reached stdout.
# The firing population was zero, so `→` emitting as c2 92 and `✅` as 05 was
# invisible to every gate in the repository and shipped through v0.14.89.
#
# COMPARES BYTES, NOT CHARACTERS, and that is not fastidiousness. The broken
# output contains control bytes and a NUL, which a shell `case` pattern and a
# terminal both mangle in their own ways -- comparing a corrupted string against
# a corrupted pattern can match. Hexing the whole stream and asking for the
# expected run as a substring is immune to that, and to how the harness frames
# the surrounding lines.
CENC_FIXTURE="$REPO_ROOT/scripts/build-smoke/capture_encoding.llmll"
CENC_OUTDIR="$OUTDIR/capenc"

if [ -f "$CENC_FIXTURE" ]; then
  echo "BUILD-GATE-1: building and RUNNING $(basename "$CENC_FIXTURE")"
  CENC_LOG="$OUTDIR/.capenc-build.log"
  if ! "${LLMLL_CMD[@]}" build "$CENC_FIXTURE" -o "$CENC_OUTDIR" > "$CENC_LOG" 2>&1; then
    cat "$CENC_LOG" >&2
    fail "the capture-encoding fixture does not build."
  fi
  CENC_EXE="$(find "$CENC_OUTDIR/.stack-work/install" -type f -name 'capture-encoding' -perm -111 2>/dev/null | head -1)"
  [ -n "$CENC_EXE" ] || fail "built the capture-encoding fixture but found no capture-encoding binary."

  # BMP=→✔✘✅§|AST=<U+1F600>|LEN=5|ALEN=1 as UTF-8. Written as hex because the
  # point of the assertion is the bytes; a literal here would be checking this
  # file's own encoding as much as the program's.
  CENC_WANT="424d503de28692e29c94e29c98e29c85c2a77c4153543df09f98807c4c454e3d357c414c454e3d31"
  CENC_OUT_FILE="$OUTDIR/.capenc.out"
  ( cd "$OUTDIR" && printf 'x\n%.0s' $(seq 6) | "$CENC_EXE" ) > "$CENC_OUT_FILE" 2>&1 || true
  CENC_HEX="$(od -An -tx1 < "$CENC_OUT_FILE" | tr -d ' \n')"

  case "$CENC_HEX" in
    *"$CENC_WANT"*) ;;
    *)
      printf 'BUILD-GATE-1 capture-encoding failure:\n' >&2
      printf '  want (hex): %s\n' "$CENC_WANT" >&2
      printf '  got  (hex): %s\n' "$CENC_HEX" >&2
      # The two signatures worth recognising on sight, so a reader does not have
      # to decode hex to know which half broke.
      case "$CENC_HEX" in
        *c29214*) printf '  diagnosis : codepoint mod 256 -- both pipe ends unpinned (the original defect)\n' >&2 ;;
        *c3a2c286*) printf '  diagnosis : latin-1 re-decode -- writeEnd pinned, readEnd NOT\n' >&2 ;;
      esac
      case "$(cat "$CENC_OUT_FILE")" in
        *"invalid byte sequence"*) printf '  diagnosis : readEnd pinned, writeEnd NOT -- UTF-8 read rejected a truncated byte\n' >&2 ;;
      esac
      printf -- '--- program output ---\n' >&2
      cat "$CENC_OUT_FILE" >&2
      fail "a console program cannot put a non-ASCII character on its own stdout (CAPTURE-ENCODING-1)."
      ;;
  esac
  echo "BUILD-GATE-1 PASS: non-ASCII string literals survive captureStdout as UTF-8 (5 BMP + 1 astral)"
fi

# ---------------------------------------------------------------------------
# Stage 5c: JSON-SCALAR-1 -- a scalar element of a json-array is readable, and
# reading it wrongly is an error rather than a plausible answer.
#
# WHY IT IS RUN AND NOT ONLY BUILT. smoke.llmll calls all eighteen json-*
# builtins, which catches a builtinEnv entry landing with no preamble body.
# That gate is structurally incapable of catching this defect class: before
# JSON-SCALAR-1 the projection family was ABSENT, and absence type-checks and
# verifies. The refute-crux port ran all 80 of its cases with every flag
# dropped and reported 30 passed / 50 failed with no gate saying anything.
#
# THE TWO err CELLS ARE THE ASSERTION, not the three value cells. A family that
# narrowed 1.5 to 1, or coerced the number 7 to the string "7", would satisfy
# every value cell and reintroduce exactly the silent-wrong-answer class this
# row was filed to close. A whole-line comparison is used so a cell that
# vanishes fails as loudly as a cell that changes.
JS_FIXTURE="$REPO_ROOT/scripts/build-smoke/json_scalar.llmll"
JS_OUTDIR="$OUTDIR/jsonscalar"

if [ -f "$JS_FIXTURE" ]; then
  echo "BUILD-GATE-1: building and RUNNING $(basename "$JS_FIXTURE")"
  JS_LOG="$OUTDIR/.jsonscalar-build.log"
  if ! "${LLMLL_CMD[@]}" build "$JS_FIXTURE" -o "$JS_OUTDIR" > "$JS_LOG" 2>&1; then
    cat "$JS_LOG" >&2
    fail "the json-scalar fixture does not build."
  fi
  JS_EXE="$(find "$JS_OUTDIR/.stack-work/install" -type f -name 'json-scalar' -perm -111 2>/dev/null | head -1)"
  [ -n "$JS_EXE" ] || fail "built the json-scalar fixture but found no json-scalar binary."

  JS_WANT='STR=--strict-verified-core|INT=7|BOOL=true|NUM=1.5|X-AS-INT=err|N-AS-STR=err|OLD-GET=err'
  JS_RUNDIR="$OUTDIR/.jsonscalar-run"
  mkdir -p "$JS_RUNDIR"
  JS_OUT_FILE="$OUTDIR/.jsonscalar.out"
  ( cd "$JS_RUNDIR" && printf 'x\n%.0s' $(seq 4) | "$JS_EXE" ) > "$JS_OUT_FILE" 2>&1 || true

  if ! grep -Fqx "$JS_WANT" "$JS_OUT_FILE"; then
    printf 'BUILD-GATE-1 json-scalar failure:\n' >&2
    printf '  want: %s\n' "$JS_WANT" >&2
    printf -- '--- program output ---\n' >&2
    cat "$JS_OUT_FILE" >&2
    # The signatures worth naming on sight.
    if grep -q 'STR=$\|STR=|' "$JS_OUT_FILE"; then
      printf '  diagnosis : the projection answered empty -- the JSON-SCALAR-1 defect itself\n' >&2
    fi
    if grep -q 'STR="' "$JS_OUT_FILE"; then
      printf '  diagnosis : quotes present -- reading via json-serialize, not a projection\n' >&2
    fi
    if grep -q 'X-AS-INT=ok' "$JS_OUT_FILE"; then
      printf '  diagnosis : json-as-int narrowed 1.5 -- strictness lost\n' >&2
    fi
    if grep -q 'N-AS-STR=ok' "$JS_OUT_FILE"; then
      printf '  diagnosis : json-as-string coerced a number -- the family coerces\n' >&2
    fi
    fail "a scalar element of a json-array does not read back correctly (JSON-SCALAR-1)."
  fi
  echo "BUILD-GATE-1 PASS: scalar json-array elements project to values, and mis-typed reads refuse"
fi

# ---------------------------------------------------------------------------
# Stage 5d: PROC-MERGE-1 -- equal stdout/stderr path STRINGS put both of a
# child's streams in one file, and unequal ones still keep them apart.
#
# Nothing here is visible to a check-only gate: the signature, the effect label
# and the response arm are all unchanged. What changes is which file the
# child's bytes land in, and the only oracle for that is reading the file.
#
# BOTH LINES ARE REQUIRED, and the second is not decoration. The merged line
# alone is satisfied by a build that dups the second handle onto the first
# UNCONDITIONALLY, which would silently destroy every two-file caller in the
# tree -- the driver's stage runner among them. The control differs from the
# positive case only in whether the two path strings are equal.
#
# ORDER IS NOT ASSERTED, deliberately. A merged stream's interleaving is the
# order the CHILD flushes: measured, a child writing stdout first and stderr
# second lands stderr first, because stdout is block-buffered to a file and
# stderr is not. Asserting it would pin /bin/sh's buffering, not this compiler.
PM_FIXTURE="$REPO_ROOT/scripts/build-smoke/proc_merge.llmll"
PM_OUTDIR="$OUTDIR/procmerge"

if [ -f "$PM_FIXTURE" ]; then
  echo "BUILD-GATE-1: building and RUNNING $(basename "$PM_FIXTURE")"
  PM_LOG="$OUTDIR/.procmerge-build.log"
  if ! "${LLMLL_CMD[@]}" build "$PM_FIXTURE" -o "$PM_OUTDIR" > "$PM_LOG" 2>&1; then
    cat "$PM_LOG" >&2
    fail "the proc-merge fixture does not build."
  fi
  PM_EXE="$(find "$PM_OUTDIR/.stack-work/install" -type f -name 'proc-merge' -perm -111 2>/dev/null | head -1)"
  [ -n "$PM_EXE" ] || fail "built the proc-merge fixture but found no proc-merge binary."

  # The fixture spawns /bin/sh and writes capture files into its working
  # directory, so it gets one of its own.
  PM_RUNDIR="$OUTDIR/.procmerge-run"
  mkdir -p "$PM_RUNDIR"
  PM_OUT_FILE="$OUTDIR/.procmerge.out"
  ( cd "$PM_RUNDIR" && printf 'x\n%.0s' $(seq 8) | "$PM_EXE" ) > "$PM_OUT_FILE" 2>&1 || true

  PM_FAILED=0
  if ! grep -Fqx 'MERGED|OUT=y|ERR=y' "$PM_OUT_FILE"; then
    printf 'BUILD-GATE-1 proc-merge failure: equal paths did not merge\n' >&2
    printf '  want: MERGED|OUT=y|ERR=y\n' >&2
    PM_FAILED=1
  fi
  if ! grep -Fqx 'SPLIT-ERRFILE|OUT=n|ERR=y' "$PM_OUT_FILE"; then
    printf 'BUILD-GATE-1 proc-merge failure: unequal paths did NOT stay separate\n' >&2
    printf '  want: SPLIT-ERRFILE|OUT=n|ERR=y\n' >&2
    if grep -q 'SPLIT-ERRFILE|OUT=y' "$PM_OUT_FILE"; then
      printf '  diagnosis : the merge is unconditional -- every two-file caller is broken\n' >&2
    fi
    PM_FAILED=1
  fi
  if [ "$PM_FAILED" -ne 0 ]; then
    printf -- '--- program output ---\n' >&2
    cat "$PM_OUT_FILE" >&2
    fail "wasi.proc.run's stream redirection does not match PROC-MERGE-1."
  fi
  echo "BUILD-GATE-1 PASS: equal proc.run paths merge both streams; unequal paths stay separate"
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

# --- 7. PROCESS BOUNDARY (PROC-BOUNDARY-1). ---------------------------------
#
# Three properties, none settleable by a check-only gate and two of them EXIT
# CODES, which a program cannot observe about itself:
#
#   wasi.proc.args   the real argument vector arrives on the existing RList arm
#                    through RC-3. Invoked with three known arguments, so a body
#                    publishing RList [] unconditionally fails HERE and passes
#                    every string-shape assertion in the unit suite.
#   :done? + :status the settled path applies :status and exits with it. 42 is
#                    neither 0 nor 70 nor 1, so it cannot be produced by
#                    success, by exhaustion, or by a crash.
#   starved stdin    with :done? DECLARED, exhaustion exits 70 without
#                    consulting :status.
#   no :done?        exhaustion exits 0. Asserted on examples/replay-demo, a
#                    SHIPPED program, because this half of the rule is a
#                    no-regression claim about the existing corpus and a
#                    purpose-built fixture cannot make it.
#
# The third is the one with a silent failure mode, and it is the only assertion
# in this file whose pre-change behaviour was SUCCESS. Measured against the
# pre-PROC-BOUNDARY-1 harness on this same fixture: 1 line exited 0, 2 lines
# exited 0, 0 lines exited 0. Partial state written, no diagnostic, exit 0.
#
# The fourth exists because an earlier revision of this rule got it wrong in the
# other direction: it exited 70 on ANY exhaustion, which made every run of a
# program with no :done? a false alarm on a success. A program that declares no
# completion predicate has no notion of completion, so EOF is the normal end of
# its input. The discriminator is DECLARATION, not firing.
#
# Note the `|| true` idiom stages 5 and 6 use to swallow exit codes CANNOT be
# used here: the exit code is the observation.
PB_FIXTURE="$REPO_ROOT/scripts/build-smoke/proc_boundary.llmll"
PB_OUTDIR="$OUTDIR/procboundary"

if [ -f "$PB_FIXTURE" ]; then
  echo "BUILD-GATE-1: building and RUNNING $(basename "$PB_FIXTURE") for exit codes"
  PB_LOG="$OUTDIR/.pb-build.log"
  if ! "${LLMLL_CMD[@]}" build "$PB_FIXTURE" -o "$PB_OUTDIR" > "$PB_LOG" 2>&1; then
    cat "$PB_LOG" >&2
    fail "the process-boundary fixture does not build."
  fi
  PB_EXE="$(find "$PB_OUTDIR/.stack-work/install" -type f -name 'proc-boundary' -perm -111 2>/dev/null | head -1)"
  [ -n "$PB_EXE" ] || fail "built the process-boundary fixture but found no
  proc-boundary binary. Without running it this stage observes nothing, which is
  the failure mode it exists to prevent."

  PB_FAIL=()

  # (a) :done? path. Two lines reach (>= s 2); :status yields 42.
  PB_OUT="$( cd "$OUTDIR" && printf 'x\nx\n' | "$PB_EXE" 2>&1 )" && PB_RC=0 || PB_RC=$?
  [ "$PB_RC" -eq 42 ] || PB_FAIL+=(":done? path exited $PB_RC, not the 42 :status returns")

  # (b) argv. Three arguments must reach the program through RC-3's first
  # response. Checked on the SAME two-line run so the count is independent of
  # how many lines :done? needs.
  PB_ARGV="$( cd "$OUTDIR" && printf 'x\nx\n' | "$PB_EXE" alpha beta gamma 2>&1 )" || true
  case "$PB_ARGV" in
    *"argc=3"*) ;;
    *) PB_FAIL+=("wasi.proc.args did not deliver three arguments; got: $PB_ARGV");;
  esac
  # The negative half. Without it, a body publishing a constant three-element
  # list would pass the line above.
  PB_ARGV0="$( cd "$OUTDIR" && printf 'x\nx\n' | "$PB_EXE" 2>&1 )" || true
  case "$PB_ARGV0" in
    *"argc=0"*) ;;
    *) PB_FAIL+=("wasi.proc.args reported a non-empty vector for a no-argument run; got: $PB_ARGV0");;
  esac

  # (c) THE POSITIVE WITNESS. One line is not enough to reach :done?, so stdin
  # is starved. Before PROC-BOUNDARY-1 this exited 0.
  ( cd "$OUTDIR" && printf 'x\n' | "$PB_EXE" > /dev/null 2>&1 ) && PB_RC=0 || PB_RC=$?
  [ "$PB_RC" -eq 70 ] || PB_FAIL+=("a starved stdin exited $PB_RC, not 70 (this exited 0 before PROC-BOUNDARY-1)")

  # (d) Immediate EOF, the degenerate case: still 70, and the event log must
  # still hold its header. The header is the ONLY log write with no following
  # hFlush, so an exit that jumped over hClose would lose it entirely.
  ( cd "$PB_OUTDIR" && rm -f proc_boundary.event-log.jsonl \
      && printf '' | "$PB_EXE" > /dev/null 2>&1 ) && PB_RC=0 || PB_RC=$?
  [ "$PB_RC" -eq 70 ] || PB_FAIL+=("an immediate EOF exited $PB_RC, not 70")
  if ! grep -q '"type":"header"' "$PB_OUTDIR/proc_boundary.event-log.jsonl" 2>/dev/null; then
    PB_FAIL+=("a zero-input run left no header in the event log; the exit jumped over hClose")
  fi

  # (e) THE OTHER HALF OF THE RULE, and it needs a SHIPPED program rather than
  # this fixture. examples/replay-demo declares no :done?, so EOF is the normal
  # end of its input and it must exit 0. This is a no-regression claim about the
  # existing corpus, so a purpose-built fixture cannot make it: the assertion
  # only means something against a program that predates the change.
  #
  # Stage 6 already built this exact source into $REPLAY_DIR, so the binary is
  # reused rather than rebuilt. Falling back to a build keeps the stage
  # self-contained if stage 6 is ever reordered or skipped.
  RD_EXE="$(find "$REPLAY_DIR/generated/replay-demo/.stack-work/install" -type f -name 'replay-demo' -perm -111 2>/dev/null | head -1)"
  if [ -z "$RD_EXE" ] && [ -f "$REPO_ROOT/examples/replay-demo/replay-demo.llmll" ]; then
    RD_DIR="$OUTDIR/nodone"; mkdir -p "$RD_DIR"
    cp "$REPO_ROOT/examples/replay-demo/replay-demo.llmll" "$RD_DIR/"
    ( cd "$RD_DIR" && "${LLMLL_CMD[@]}" build replay-demo.llmll ) > "$RD_DIR/build.log" 2>&1 \
      || { cat "$RD_DIR/build.log" >&2; fail "the no-:done? witness does not build"; }
    RD_EXE="$(find "$RD_DIR/generated/replay-demo/.stack-work/install" -type f -name 'replay-demo' -perm -111 2>/dev/null | head -1)"
  fi
  [ -n "$RD_EXE" ] || fail "found no replay-demo binary for the no-:done? exit-code
  witness. Skipping it silently would leave the half of the rule that protects
  the SHIPPED corpus unobserved, which is the dead-gate mode this file refuses."

  ( cd "$OUTDIR" && printf 'a\nb\n' | "$RD_EXE" > /dev/null 2>&1 ) && PB_RC=0 || PB_RC=$?
  [ "$PB_RC" -eq 0 ] || PB_FAIL+=("examples/replay-demo declares no :done?, so EOF is normal termination, but it exited $PB_RC instead of 0")
  ( cd "$OUTDIR" && printf '' | "$RD_EXE" > /dev/null 2>&1 ) && PB_RC=0 || PB_RC=$?
  [ "$PB_RC" -eq 0 ] || PB_FAIL+=("examples/replay-demo exited $PB_RC on immediate EOF instead of 0")

  if [ "${#PB_FAIL[@]}" -gt 0 ]; then
    printf 'BUILD-GATE-1 process-boundary failures:\n' >&2
    for f in "${PB_FAIL[@]}"; do printf '  - %s\n' "$f" >&2; done
    fail "the process boundary compiled but did not behave. A starved stdin that
  reports success is the exact defect PROC-BOUNDARY-1 closes, and it is silent;
  a program with no :done? reporting failure on a clean run is the same defect
  inverted, and it is loud but wrong."
  fi

  echo "BUILD-GATE-1 PASS: argv on RList; :done? exits 42; starved exits 70; no-:done? exits 0"
fi

# --- 8. DRIVER-LL sub-phase 4a + 4b + 4c acceptance cover. -------------------
#
# The eleven-cell transition cover of docs/design/driver-ll-phase4-proposal.md
# section 2.3, the three corrupt-manifest shapes of its section 10 cases 16 to
# 18, and the sixteen delegated-output cells of its section 9's 4b row, driven
# against the BUILT sequencer. It is here rather than in pytest because it
# needs a toolchain: the thing under test is a compiled binary, and the
# properties are exit codes, a manifest on disk, and a child process the
# binary actually spawned, none of which any check-only gate can settle.
#
# Campaign section 3a requires the Phase 4 artifact to enter the build gate.
# The static checks that need no binary live in
# scripts/tests/test_driver_ll_4a_cover.py (cover-to-rig name correspondence,
# the two 4a section 7 disclosures, registry agreement with the Python STAGES
# list) and scripts/tests/test_driver_ll_4b.py (the facility's signature, the
# floors against the reference's own literals by AST, and stage I's absent
# validator) and run under pytest.
#
# The sequencer imports five sibling modules, so it is built from its own
# directory; `llmll build` resolves imports relative to the source file.
DRV_SRC="$REPO_ROOT/tools/llmll-driver/sequencer.llmll"
DRV_OUTDIR="$OUTDIR/driverll"

if [ -f "$DRV_SRC" ]; then
  echo "BUILD-GATE-1: building and RUNNING the DRIVER-LL 4a+4b cover"
  DRV_LOG="$OUTDIR/.driverll-build.log"
  if ! ( cd "$REPO_ROOT/tools/llmll-driver" \
           && "${LLMLL_CMD[@]}" build sequencer.llmll -o "$DRV_OUTDIR" ) \
         > "$DRV_LOG" 2>&1; then
    cat "$DRV_LOG" >&2
    fail "the DRIVER-LL sequencer does not build."
  fi

  DRV_EXE="$(find "$DRV_OUTDIR/.stack-work/install" -type f -name 'sequencer' -perm -111 2>/dev/null | head -1)"
  [ -n "$DRV_EXE" ] || fail "built the DRIVER-LL sequencer but found no
  sequencer binary under $DRV_OUTDIR/.stack-work/install. Without running it
  this stage observes nothing, which is the failure mode it exists to prevent."

  if ! python3 "$REPO_ROOT/scripts/driver_ll_cover.py" --driver "$DRV_EXE" > "$OUTDIR/.driverll-cover.log" 2>&1; then
    cat "$OUTDIR/.driverll-cover.log" >&2
    fail "the DRIVER-LL 4a+4b+4c acceptance cover did not pass. Every scenario is a
  DECISION the Python reference makes and this port must make identically; the
  log above names the cell and the assertion."
  fi
  cat "$OUTDIR/.driverll-cover.log"
  echo "BUILD-GATE-1 PASS: DRIVER-LL 4a+4b+4c cover (11 transition cells + 3 manifest shapes + 16 delegated-output cells + 8 content-shape cells + registry)"
fi

# --- 9. DRIVER-LL sub-phase 4e acceptance cover: the serial wave. ------------
#
# The seven cells of scripts/wave_cover.py, driven against the BUILT `wave`
# binary and the REAL compiler.
#
# THIS STAGE USES NO STUB COMPILER, unlike stage 8. The decisions under test
# are what `checkout`, `patch` and `verify` answer, so a stub would be testing
# the stub. Cell W4 is the one the 4e row makes mandatory: it holds TWO BRIEFS
# SIMULTANEOUSLY against the real per-file CAS and observes the wave's own
# patch refused as stale, which is proposal Rev 15's F-27 replacing this
# document's earlier fault-injector design.
#
# It is here rather than in pytest for the same reason stage 8 is: the thing
# under test is a compiled binary, and the properties are exit codes, a tree on
# disk and a child process the binary actually spawned. The checks that need no
# binary live in scripts/tests/test_driver_ll_4e.py.
#
# The wave imports two sibling modules, so it is built from its own directory.
WAVE_SRC="$REPO_ROOT/tools/llmll-driver/wave.llmll"
WAVE_OUTDIR="$OUTDIR/waverun"

if [ -f "$WAVE_SRC" ]; then
  echo "BUILD-GATE-1: building and RUNNING the DRIVER-LL 4e wave cover"
  WAVE_LOG="$OUTDIR/.wave-build.log"
  if ! ( cd "$REPO_ROOT/tools/llmll-driver" \
           && "${LLMLL_CMD[@]}" build wave.llmll -o "$WAVE_OUTDIR" ) \
         > "$WAVE_LOG" 2>&1; then
    cat "$WAVE_LOG" >&2
    fail "the DRIVER-LL wave does not build."
  fi

  WAVE_EXE="$(find "$WAVE_OUTDIR/.stack-work/install" -type f -name 'wave' -perm -111 2>/dev/null | head -1)"
  [ -n "$WAVE_EXE" ] || fail "built the DRIVER-LL wave but found no wave binary
  under $WAVE_OUTDIR/.stack-work/install. Without running it this stage
  observes nothing, which is the failure mode it exists to prevent."

  if ! python3 "$REPO_ROOT/scripts/wave_cover.py" \
         --wave "$WAVE_EXE" --llmll "${LLMLL_CMD[0]}" \
         > "$OUTDIR/.wave-cover.log" 2>&1; then
    cat "$OUTDIR/.wave-cover.log" >&2
    fail "the DRIVER-LL 4e wave cover did not pass. Every cell is a DECISION
  driver-spec.txt sections 9 and 10 require of the fill protocol; the log above
  names the cell and the assertion."
  fi
  cat "$OUTDIR/.wave-cover.log"
  echo "BUILD-GATE-1 PASS: DRIVER-LL 4e wave cover (7 cells: accept, finding, unfaithful fill, two-brief contention, two usage stops, unsealed tree)"
fi

# --- 10. DRIFT-CI-1, decided by an LLMLL program. ----------------------------
#
# tools/version-gate/versiongate.llmll is a port of scripts/version_gate.sh:
# the same C1..C4 criteria, the same order, the same messages, the same exit
# codes. This stage builds it and RUNS IT AS THE GATE, so a banner that drifts
# out of step fails this job because an LLMLL program said so.
#
# IT DOES NOT REPLACE THE SHELL SCRIPT AND IS NOT MEANT TO. The shell version
# runs in .github/workflows/version-gate.yml, a job with no Stack and no GHC,
# deliberately fast. This one runs here, where Stack is already warm. Two
# implementations, two jobs, both deciding.
#
# The cover is the check rather than a single invocation, because agreement on
# a passing tree is not evidence: twelve of its fourteen cells are mutants, and
# each is asserted to FAIL under BOTH implementations before their messages are
# compared. A battery where both pass everything agrees perfectly and detects
# nothing. The gate is then also run once against the live tree, so the banner
# under test appears in the log rather than only in a temporary copy.
VG_SRC="$REPO_ROOT/tools/version-gate/versiongate.llmll"
VG_OUTDIR="$OUTDIR/versiongate"

if [ -f "$VG_SRC" ]; then
  echo "BUILD-GATE-1: building and RUNNING the LLMLL version gate (DRIFT-CI-1)"
  VG_LOG="$OUTDIR/.versiongate-build.log"
  if ! ( cd "$REPO_ROOT/tools/version-gate" \
           && "${LLMLL_CMD[@]}" build versiongate.llmll -o "$VG_OUTDIR" ) \
         > "$VG_LOG" 2>&1; then
    cat "$VG_LOG" >&2
    fail "the LLMLL version gate does not build."
  fi

  VG_EXE="$(find "$VG_OUTDIR/.stack-work/install" -type f -name 'versiongate' -perm -111 2>/dev/null | head -1)"
  [ -n "$VG_EXE" ] || fail "built the LLMLL version gate but found no
  versiongate binary under $VG_OUTDIR/.stack-work/install. Without running it
  this stage observes nothing, which is the failure mode it exists to prevent."

  if ! python3 "$REPO_ROOT/scripts/version_gate_cover.py" --gate "$VG_EXE" \
         > "$OUTDIR/.versiongate-cover.log" 2>&1; then
    cat "$OUTDIR/.versiongate-cover.log" >&2
    fail "the LLMLL version gate does not agree with scripts/version_gate.sh.
  The shell script is the reference: a divergence is the port's defect until
  argued otherwise, and the log above names the cell and the two messages."
  fi
  cat "$OUTDIR/.versiongate-cover.log"

  # The deciding invocation, against the real tree.
  #
  # The step budget comes from python3 and NOT from `yes x | head -n 60`. This
  # script sets `pipefail` (line 45), and `yes` dies of SIGPIPE the moment
  # `head` has taken its sixty lines, so that pipeline reports 141 no matter
  # what the gate decided. Measured: the gate printed its PASS report and this
  # stage failed anyway. A console program's step budget is not worth a
  # pipeline whose leftmost member is designed to be killed.
  # RUN FROM $OUTDIR AND NOT FROM THE REPO ROOT, with --root absolute. A
  # console program writes <module>.event-log.jsonl into its working
  # directory, so running this from the repo root drops an untracked file into
  # the tree on every build. `--root` exists precisely so the gate's subject
  # and its working directory can be different places.
  if ! ( cd "$OUTDIR" \
           && python3 -c "import sys; sys.stdout.write('x\n' * 60)" \
                | "$VG_EXE" --root "$REPO_ROOT" ) \
         > "$OUTDIR/.versiongate-live.log" 2>&1; then
    cat "$OUTDIR/.versiongate-live.log" >&2
    fail "the LLMLL version gate rejected this tree."
  fi
  grep -v '^$' "$OUTDIR/.versiongate-live.log" || true
  echo "BUILD-GATE-1 PASS: DRIFT-CI-1 decided by an LLMLL program (14 cover cells + the live tree)"
fi

exit 0
