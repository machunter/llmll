#!/usr/bin/env bash
set -euo pipefail

# LT-INV (v0.11) grammar-aware wrapper.
# Injects --grammar=core-inversion before every subcommand so agents working
# in a core-inversion run directory do not need to know the flag explicitly.
# LLMLL_REAL is set by run_agent.py::build_agent_env to the resolved binary path.

if [[ -z "${LLMLL_REAL:-}" ]]; then
  echo "LLMLL_REAL is not set; the experiment harness could not locate the real llmll binary." >&2
  exit 127
fi

if [[ "$#" -ge 2 && "$1" == "hub" && "$2" == "scaffold" ]]; then
  HOME="$PWD" exec "$LLMLL_REAL" --grammar=core-inversion "$@"
fi

exec "$LLMLL_REAL" --grammar=core-inversion "$@"
