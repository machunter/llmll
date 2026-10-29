#!/usr/bin/env bash
#
# LLMLL: goto-fail's invariant as a hole, filled twice (site/assets/gotofail.gif).
# Shows: the contract with no body; `checkout` returns the brief (the contract,
# not the answer); a fill that returns Verified on every path is rejected by the
# verifier and leaves the program unchanged; the guarded fill is accepted; the
# filled program verifies SAFE.
#
# The two fills are the committed patch files finalize-patch-wrong.json and
# finalize-patch-correct.json: fixed, scripted stand-ins for agents.
#
# Usage (from any directory):
#   bash examples/gotofail/demo.sh           # interactive: tap Enter to run each command
#   bash examples/gotofail/demo.sh --auto    # unattended (also: DEMO_AUTO=1)
#
# Regenerate the GIF headlessly: `make demo-gifs` (repo root).
#
# The demo copies what it touches into a fresh temp dir and runs there, so
# checkout/patch never rewrite the tracked finalize-hole.ast.json or its lock file.
# Requires `llmll`, `fixpoint` (liquid-fixpoint), `z3` and `jq` on PATH.

set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)" || exit 1
command -v llmll >/dev/null || { echo "llmll not on PATH: stack --stack-yaml compiler/stack.yaml install"; exit 1; }
command -v jq    >/dev/null || { echo "jq not found: brew install jq"; exit 1; }

SRC="$ROOT/examples/gotofail"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cp "$SRC/finalize-hole.llmll" "$SRC/finalize-hole.ast.json" \
   "$SRC/finalize-patch-wrong.json" "$SRC/finalize-patch-correct.json" "$WORK/"
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
p  "# goto-fail's invariant as a contract: return Verified only if the check passed."
p  "# The body is a hole for an agent to fill."
pe "grep -v '^;;' finalize-hole.llmll"
p  "# checkout reserves the hole and returns the brief: the contract, not the answer."
pe "CO=\$(llmll checkout finalize-hole.ast.json /statements/2/body --json)"
pe "jq '{postcondition_goal, expected_return_type}' <<<\"\$CO\""

# Plumbing, not shown as commands: stamp the checkout token into both patch
# files, and keep a copy of the program to show the rejected patch left it alone.
TOKEN="$(jq -r .token <<<"$CO")"
jq --arg t "$TOKEN" '.token = $t' finalize-patch-wrong.json   > wrong.json
jq --arg t "$TOKEN" '.token = $t' finalize-patch-correct.json > right.json
cp finalize-hole.ast.json before.ast.json

beat
p  "# The fills are scripted stand-ins for agents: committed patch files, stamped"
p  "# with the checkout token. Fill 1 is the goto-fail bug: Verified on every arm."
p  "#   (match sig ((Continue) Verified) ((Abort c) Verified))"
pe "llmll patch finalize-hole.ast.json wrong.json --require-proof | jq ."
p  "# Rejected at submission. The program was not touched:"
pe "cmp finalize-hole.ast.json before.ast.json && echo unchanged"

beat
p  "# Fill 2 is the guarded body: Verified only on the Continue arm."
p  "#   (match sig ((Continue) Verified) ((Abort c) (Rejected c)))"
pe "llmll patch finalize-hole.ast.json right.json --require-proof | jq -c ."
p  "# The filled program, re-verified from scratch:"
pe "llmll verify finalize-hole.ast.json"
