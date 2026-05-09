#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${LLMLL_REAL:-}" ]]; then
  echo "LLMLL_REAL is not set; the experiment harness could not locate the real llmll binary." >&2
  exit 127
fi

if [[ "$#" -ge 2 && "$1" == "hub" && "$2" == "scaffold" ]]; then
  HOME="$PWD" exec "$LLMLL_REAL" "$@"
fi

exec "$LLMLL_REAL" "$@"
