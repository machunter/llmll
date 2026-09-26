#!/usr/bin/env bash
#
# LLMLL: "money can't be created" refutation demo (the README's refute.gif).
# Shows: a deliberately wrong body that is type-correct but credits one unit too
# many is REFUTED by the SMT solver; the correct body is proved, and the strict
# trust report marks it `verified`. Pure SMT: no API key, no Lean toolchain.
#
# Usage (from any directory):
#   bash examples/payments-core/demo.sh           # interactive: tap Enter to run each command
#   bash examples/payments-core/demo.sh --auto    # unattended (also: DEMO_AUTO=1)
#
# Regenerate the GIF headlessly: `make demo-gifs` (repo root).
#
# The demo copies the two example files into a fresh temp dir and runs there,
# so `llmll verify` never writes sidecars next to the tracked examples.
# Requires `llmll`, `fixpoint` (liquid-fixpoint) and `z3` on PATH.

set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)" || exit 1
command -v llmll >/dev/null || { echo "llmll not on PATH: stack --stack-yaml compiler/stack.yaml install"; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cp "$ROOT/examples/payments-core/conserve-bad.llmll" "$ROOT/examples/payments-core/conserve.llmll" "$WORK/"
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
p  "# conserve(from, to, amount) returns BOTH new balances. Its contract:"
p  "#   (first result) + (second result) = from + to    (no money created or destroyed)"
p  "# A deliberately wrong body: type-correct, but it credits one unit too many."
pe "sed -n '/^(def conserve-bad/,\$p' conserve-bad.llmll"
p  "# The SMT solver refutes it:"
pe "llmll verify conserve-bad.llmll"
p  "# The correct body adds exactly what it subtracts:"
pe "sed -n '/^(def conserve /,\$p' conserve.llmll"
[ "$AUTO" = 1 ] && sleep 0.6
clear
p  "# Proved over BOTH return values; the strict report re-runs the solver:"
pe "llmll verify conserve.llmll --strict-verify"
