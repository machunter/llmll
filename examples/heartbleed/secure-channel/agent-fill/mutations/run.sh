#!/usr/bin/env bash
#
# Reintroduce goto-fail or Heartbleed into the 163-function agent-filled program
# and verify it (blog Post 5). Each mutation is a diff that changes ONE body and
# leaves every contract as it is; verify must then refute the program at that
# function.
#
#   gotofail.diff    deliver-len returns payload_len whether or not the MAC verified
#   heartbleed.diff  heartbeat-response echoes claimed_len unchecked against received_len
#
# Usage (from any directory):
#   bash examples/heartbleed/secure-channel/agent-fill/mutations/run.sh            # both
#   bash examples/heartbleed/secure-channel/agent-fill/mutations/run.sh gotofail   # one
#
# Each verify takes about a minute and 5 GB. The mutated copy lives in a temp
# dir, so the tracked program and its sidecar are never touched.
# Requires `llmll`, `fixpoint` (liquid-fixpoint), `z3` and `patch` on PATH.

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 1
PROGRAM="$HERE/../sc-channel-agentfilled.llmll"
command -v llmll >/dev/null || { echo "llmll not on PATH"; exit 1; }

status=0
for m in "${@:-gotofail heartbleed}"; do
  for name in $m; do
    WORK="$(mktemp -d)"
    cp "$PROGRAM" "$WORK/"
    ( cd "$WORK" && patch -s -p1 < "$HERE/$name.diff" ) || { echo "$name: diff did not apply"; exit 1; }
    echo "== $name: $(grep -m1 MUTATION "$WORK/sc-channel-agentfilled.llmll" | sed 's/.*;; //')"
    ( cd "$WORK" && llmll verify sc-channel-agentfilled.llmll )
    rc=$?
    echo "== $name: exit $rc"
    # A mutation that verifies is the failure this script exists to catch.
    [ "$rc" -eq 1 ] || status=1
    rm -rf "$WORK"
  done
done
exit $status
