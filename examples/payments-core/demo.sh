#!/usr/bin/env bash
#
# LLMLL — "money can't be created, proven" refutation demo (record with asciinema).
# Shows: a type-correct fill that breaks a conservation invariant is REFUTED by the
# SMT solver before it can merge; the correct fill is proven SAFE. Pure SMT — no
# API key, no Lean toolchain.
#
# ── one-time setup (from the repo root) ──────────────────────────────────────
#   brew install asciinema agg
#   stack --stack-yaml compiler/stack.yaml install       # puts `llmll` on PATH
#
# ── record (from the repo root) ──────────────────────────────────────────────
#   asciinema rec --idle-time-limit 2 -t "LLMLL — refuted" refute.cast
#   bash examples/payments-core/demo.sh      # tap Enter to advance each beat
#   exit                                     # stop recording
#   agg --idle-time-limit 2 refute.cast docs/assets/refute.gif   # → README GIF
#
# --idle-time-limit compresses the (short) liquid-fixpoint pauses on playback.

cd "$(dirname "$0")/../.." || { echo "run from inside the llmll repo"; exit 1; }   # repo root
command -v llmll >/dev/null || { echo "llmll not on PATH — run: stack --stack-yaml compiler/stack.yaml install"; exit 1; }

BAD="examples/payments-core/conserve-bad.llmll"
GOOD="examples/payments-core/conserve.llmll"

# ── minimal demo driver (inlined — no external deps) ─────────────────────────
DEMO_PROMPT="\$ "
p()  { printf '\033[36m%s\033[0m\n' "$*"; }          # narration line (cyan)
pe() {                                                # prompt, "type" the command, wait Enter, run it
  printf '%s' "$DEMO_PROMPT"
  local i cmd="$*"
  for ((i=0; i<${#cmd}; i++)); do printf '%s' "${cmd:i:1}"; sleep 0.02; done
  read -r _
  eval "$cmd"
  printf '\n'
}

clear
p  "# conserve(from, to, amount) returns BOTH new balances. The contract ties them:"
p  "#   (first result) + (second result) = from + to   — the total is conserved."
p  "# An agent's 'helpful' fill credits the destination one extra unit:"
pe "grep -A2 '(def conserve-bad' $BAD"
p  ""
p  "# Type-correct. Passes a happy-path test. Looks harmless. But it creates money —"
p  "# and the SMT solver refutes it before it can merge:"
pe "llmll verify $BAD --strict-verified-core"
p  ""
p  "# The correct fill adds exactly what it subtracts:"
pe "grep -F '(pair' $GOOD"
p  ""
p  "# Proven — a relational invariant over BOTH return values. The money didn't move."
pe "llmll verify $GOOD"
