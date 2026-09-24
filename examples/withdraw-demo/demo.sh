#!/usr/bin/env bash
#
# LLMLL: the agent protocol loop in one hole (the README's protocol.gif).
# Shows: `holes` finds a typed hole; `checkout` reserves it and returns the
# brief (the contract, not the answer); a wrong patch is rejected by the
# verifier and leaves the program unchanged; the correct patch is accepted; the
# hole count falls to 0; the strict trust report marks the function `verified`.
#
# The two fills are the committed patch files withdraw-patch-wrong.json and
# withdraw-patch-correct.json: hand-written, scripted stand-ins for agents.
#
# Usage (from any directory):
#   bash examples/withdraw-demo/demo.sh           # interactive: tap Enter to run each command
#   bash examples/withdraw-demo/demo.sh --auto    # unattended (also: DEMO_AUTO=1)
#
# Regenerate the GIF headlessly: `make demo-gifs` (repo root).
#
# The demo copies what it touches into a fresh temp dir and runs there, so
# checkout/patch never rewrite the tracked withdraw.ast.json or its lock file.
# Requires `llmll`, `fixpoint` (liquid-fixpoint), `z3` and `jq` on PATH.

set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)" || exit 1
command -v llmll >/dev/null || { echo "llmll not on PATH: stack --stack-yaml compiler/stack.yaml install"; exit 1; }
command -v jq    >/dev/null || { echo "jq not found: brew install jq"; exit 1; }

SRC="$ROOT/examples/withdraw-demo"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cp "$SRC/withdraw.llmll" "$SRC/withdraw.ast.json" \
   "$SRC/withdraw-patch-wrong.json" "$SRC/withdraw-patch-correct.json" "$WORK/"
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
beat() { [ "$AUTO" = 1 ] && sleep 0.6; clear; }

clear
p  "# withdraw has a contract and no body yet: one typed hole."
pe "cat withdraw.llmll"
pe "llmll holes withdraw.ast.json 2>/dev/null"
p  "# checkout reserves the hole and returns the brief: the contract, not the answer."
pe "CO=\$(llmll checkout withdraw.ast.json /statements/1/body --json)"
pe "jq '{contract_pre, postcondition_goal, in_scope: [.in_scope[].name]}' <<<\"\$CO\""

# Plumbing, not shown as commands: stamp the checkout token into both patch
# files, and keep a copy of the program to show the rejected patch left it alone.
TOKEN="$(jq -r .token <<<"$CO")"
jq --arg t "$TOKEN" '.token = $t' withdraw-patch-wrong.json   > wrong.json
jq --arg t "$TOKEN" '.token = $t' withdraw-patch-correct.json > right.json
cp withdraw.ast.json before.ast.json

beat
p  "# The fills are scripted stand-ins for agents: committed patch files, stamped"
p  "# with the checkout token. Fill 1 is hand-written and wrong (balance + amount):"
pe "jq -c '.patch[1].value' wrong.json"
pe "llmll patch withdraw.ast.json wrong.json | jq ."
p  "# Rejected at submission. The program was not touched:"
pe "cmp withdraw.ast.json before.ast.json && echo unchanged"
p  "# Fill 2 (scripted, correct: balance - amount):"
pe "jq -c '.patch[1].value' right.json"
pe "llmll patch withdraw.ast.json right.json | jq -c ."
pe "llmll holes withdraw.ast.json"

beat
p  "# The filled program, re-verified from scratch:"
pe "llmll verify withdraw.ast.json --strict-verify"
