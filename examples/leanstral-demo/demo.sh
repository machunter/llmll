#!/usr/bin/env bash
#
# LLMLL — verified-lean C-property demo (self-contained; record with asciinema).
# Shows: a nonlinear obligation Z3 can only mark `asserted` becomes `verified-lean`
# under --leanstral (Leanstral proves it; the Lean kernel + Mathlib check it),
# and that the machine-readable trust sidecar reflects it.
#
# ── one-time setup (from the repo root) ──────────────────────────────────────
#   brew install asciinema agg jq
#   stack --stack-yaml compiler/stack.yaml install       # puts `llmll` on PATH
#   source "$HOME/.elan/env"                              # puts `lake` on PATH
#   export LLMLL_LEANSTRAL_API_KEY="$MISTRAL_API_KEY"     # set BEFORE recording — never typed on screen
#   export LEAN_PROJECT=/path/to/your/lean4+mathlib/project   # e.g. ~/proofcheck
#
# ── record (from the repo root) ──────────────────────────────────────────────
#   asciinema rec --idle-time-limit 2 -t "LLMLL — verified-lean" leanstral.cast
#   bash examples/leanstral-demo/demo.sh     # tap Enter to advance each beat
#   exit                                     # stop recording
#   agg --idle-time-limit 2 leanstral.cast docs/assets/leanstral.gif   # → README GIF
#
# --idle-time-limit compresses the real ~60s Leanstral-call + Mathlib-load pause
# to ~2s on playback. Honest — the command ran; the viewer just doesn't wait.
#
# Note: beat 3 uses plain --leanstral (no --trust-report) because only that path
# WRITES the .verified.json sidecar shown in beat 4 (--trust-report renders the
# report but does not persist the sidecar). It still prints "verified-lean".

cd "$(dirname "$0")/../.." || { echo "run from inside the llmll repo"; exit 1; }   # repo root

SQ="examples/leanstral-demo/square.llmll"
LEAN_PROJECT="${LEAN_PROJECT:-$HOME/proofcheck}"

# ── pre-flight (not part of the recorded beats) ──────────────────────────────
[ -n "${LLMLL_LEANSTRAL_API_KEY:-}" ] || { echo "set LLMLL_LEANSTRAL_API_KEY first"; exit 1; }
command -v llmll >/dev/null           || { echo "llmll not on PATH — run: stack --stack-yaml compiler/stack.yaml install"; exit 1; }
command -v lake  >/dev/null           || { echo "lake not on PATH — run: source \$HOME/.elan/env"; exit 1; }
command -v jq    >/dev/null           || { echo "jq not found — run: brew install jq"; exit 1; }
[ -d "$LEAN_PROJECT" ]                || { echo "LEAN_PROJECT not found: $LEAN_PROJECT"; exit 1; }
# fresh proof: a cached proof would print "cached proof (skip)" and weaken the demo
rm -f examples/leanstral-demo/square.llmll.proof-cache.json \
      examples/leanstral-demo/square.llmll.verified.json \
      examples/leanstral-demo/square.verified.lean

# ── minimal demo driver (inlined — no external demo-magic.sh needed) ──────────
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
p  "# An agent wrote square(n) = n*n, and claims the result is always >= 0."
pe "grep -A2 def-shell $SQ"
p  ""
p  "# n*n is nonlinear — outside the SMT solver's decidable fragment."
p  "# So Z3 gives up: the postcondition falls back to 'asserted' (unproven)."
pe "llmll verify $SQ --trust-report"
p  ""
p  "# --leanstral: translate the obligation to a Lean theorem, have Leanstral"
p  "# prove it, and check that proof with the Lean kernel + Mathlib."
pe "llmll verify $SQ --leanstral --leanstral-lean-project $LEAN_PROJECT"
p  ""
p  "# The machine-readable trust record — what a downstream agent or CI reads —"
p  "# now says verified-lean, kernel-checked by leanstral (not asserted):"
pe "cat examples/leanstral-demo/square.llmll.verified.json | jq ."
p  ""
p  "# And the certificate: a Lean proof term anyone can independently re-check."
pe "cat examples/leanstral-demo/square.verified.lean"
