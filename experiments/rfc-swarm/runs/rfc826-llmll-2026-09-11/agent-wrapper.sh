#!/bin/sh
# Reproduces the reference's `claude -p "$(cat {prompt})" ...` without a shell in
# the driver. The port passes argv only (PROC-BOUNDARY-1), so {prompt} arrives as
# a PATH and this wrapper inlines the contents, which is what the oracle did.
#
# Usage: agent-wrapper.sh --model <MODEL> <PROMPT_PATH> <OUT_PATH>
# The model stays an argv ELEMENT so RUN-PROVENANCE.json's pin is checkable by
# clause2_compare.py's P2 (pre-registration section 6.2).
set -e
[ "$1" = "--model" ] || { echo "expected --model as \$1, got '$1'" >&2; exit 2; }
MODEL="$2"; PROMPT="$3"; OUT="$4"
[ -r "$PROMPT" ] || { echo "prompt not readable: $PROMPT" >&2; exit 2; }
exec claude -p "$(cat "$PROMPT")" \
     --model "$MODEL" \
     --allowedTools "Read,Write,Bash" \
     --permission-mode acceptEdits
