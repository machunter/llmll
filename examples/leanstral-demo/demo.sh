#!/usr/bin/env bash
#
# LLMLL: verified-lean demo (EXPERIMENTAL; records docs/assets/leanstral.gif, not currently embedded in the README).
# Shows: a nonlinear postcondition that the SMT path can only ASSUME (the
# W-BODY-FALLBACK warning and the "partial" headline) becomes `verified-lean`
# under --leanstral: Leanstral writes a proof, and the Lean kernel + Mathlib
# check it. The machine-readable trust sidecar and the .lean certificate follow.
#
# ── one-time setup ───────────────────────────────────────────────────────────
#   brew install asciinema agg jq
#   stack --stack-yaml compiler/stack.yaml install         # puts `llmll` on PATH
#   source "$HOME/.elan/env"                                # puts `lake` on PATH
#   export LLMLL_LEANSTRAL_API_KEY=...    # set BEFORE recording; never typed on screen
#   export LEAN_PROJECT=<your Lean 4 + Mathlib project dir>
#
# ── run / record (from any directory) ────────────────────────────────────────
#   bash examples/leanstral-demo/demo.sh           # interactive: tap Enter per command
#   bash examples/leanstral-demo/demo.sh --auto    # unattended (also: DEMO_AUTO=1)
#
#   asciinema rec --headless --overwrite --window-size 100x34 -q \
#     -c "bash examples/leanstral-demo/demo.sh --auto" leanstral.cast
#   agg --font-size 14 --idle-time-limit 2 --last-frame-duration 6 \
#     leanstral.cast docs/assets/leanstral.gif
#
# --idle-time-limit compresses the real Leanstral-call + Mathlib-load pause on
# playback: the command ran, the viewer just does not wait for it.
#
# The demo copies square.llmll into a fresh temp dir and runs there, so the
# sidecar, proof cache and certificate never land next to the tracked example
# (and a stale cached proof cannot replace the live one). The Lean project path
# is passed as "$LEAN_PROJECT", so no local path appears on screen.
#
# Beat 3 uses plain --leanstral (no --trust-report) because only that path
# WRITES the .verified.json sidecar shown in beat 4.

set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)" || exit 1

# ── pre-flight (not part of the recorded beats) ──────────────────────────────
[ -n "${LLMLL_LEANSTRAL_API_KEY:-}" ] || { echo "set LLMLL_LEANSTRAL_API_KEY first"; exit 1; }
[ -n "${LEAN_PROJECT:-}" ]            || { echo "set LEAN_PROJECT to a Lean 4 + Mathlib project dir"; exit 1; }
[ -d "$LEAN_PROJECT" ]                || { echo "LEAN_PROJECT not found: $LEAN_PROJECT"; exit 1; }
command -v llmll >/dev/null           || { echo "llmll not on PATH: stack --stack-yaml compiler/stack.yaml install"; exit 1; }
command -v lake  >/dev/null           || { echo "lake not on PATH: source \$HOME/.elan/env"; exit 1; }
command -v jq    >/dev/null           || { echo "jq not found: brew install jq"; exit 1; }
export LEAN_PROJECT

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cp "$ROOT/examples/leanstral-demo/square.llmll" "$WORK/"
cd "$WORK" || exit 1

# ── minimal demo driver (inlined, no external deps) ──────────────────────────
AUTO="${DEMO_AUTO:-0}"
for a in "$@"; do [ "$a" = "--auto" ] && AUTO=1; done
TYPE_DELAY="${DEMO_TYPE_DELAY:-0.025}"   # seconds per typed character
PAUSE="${DEMO_PAUSE:-1.6}"               # --auto: reading pause after each beat
DEMO_PROMPT="\$ "
p()  { printf '\033[36m%s\033[0m\n' "$*"; }           # narration line (cyan)
pe() {                                                 # prompt, type the command, wait, run it
  printf '%s' "$DEMO_PROMPT"
  local i cmd="$*"
  for ((i=0; i<${#cmd}; i++)); do printf '%s' "${cmd:i:1}"; sleep "$TYPE_DELAY"; done
  if [ "$AUTO" = 1 ]; then sleep 0.4; printf '\n'; else read -r _; fi
  eval "$cmd"
  [ "$AUTO" = 1 ] && sleep "$PAUSE"
  printf '\n'
}

clear
p  "# EXPERIMENTAL (opt-in --leanstral). square(n) = n*n claims result >= 0:"
pe "sed -n '/^(def-shell square/,\$p' square.llmll"
p  "# n*n is nonlinear, outside the SMT solver's decidable fragment. The SMT"
p  "# path says so: the post is ASSUMED, not proved (W-BODY-FALLBACK, 'partial')."
pe "llmll verify square.llmll"
p  "# --leanstral: state the obligation as a Lean theorem, have Leanstral prove"
p  "# it, and check that proof with the Lean kernel + Mathlib."
pe "llmll verify square.llmll --leanstral --leanstral-lean-project \"\$LEAN_PROJECT\""
p  "# The machine-readable trust record, what a downstream agent or CI reads:"
pe "jq . square.llmll.verified.json"
p  "# The certificate: a Lean proof anyone can re-check with Lean."
p  "# (Still trusted: LLMLL's translation of the contract into the theorem.)"
pe "cat square.verified.lean"
