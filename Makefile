# LLMLL Benchmarks Makefile
# v0.6.1: Frozen benchmark CI gates

.PHONY: benchmark-erc20 benchmark-totp refute-crux-gate benchmark-all

# ─────────────────────────────────────────────────────────────────────
# ERC-20 Token Benchmark (v0.6.0, CI gate v0.6.1)
# ─────────────────────────────────────────────────────────────────────

benchmark-erc20:
	@./scripts/benchmark-erc20.sh

# ─────────────────────────────────────────────────────────────────────
# TOTP RFC 6238 Benchmark (v0.6.1)
# ─────────────────────────────────────────────────────────────────────

benchmark-totp:
	@./scripts/benchmark-totp.sh

# ─────────────────────────────────────────────────────────────────────
# Refute-crux verdict gate — frozen verify verdicts for the showcased
# example families (tcp_rfc793, session-pay, gotofail, outcome-totality).
# Freezes verdict + exit code ONLY (not report/classification shapes).
#
# THE BUILD IS THE STALE-BINARY GUARD (finding F-3), and it lives here now
# rather than inside the gate. `stack exec` does not rebuild, so grading a
# compiler change against an old binary reads a lost refutation as vacuously
# SAFE. CI does not need this line, having built before the gate runs since
# a23e361; `make` does, and this is the caller that has it. Moving it here is
# what lets the LLMLL port (TOOL-RFC-002) carry no dependency on a Haskell
# build system. Under `set -e` semantics a failed build aborts the target
# loudly instead of gating against a stale binary.
# ─────────────────────────────────────────────────────────────────────

refute-crux-gate:
	@cd compiler && stack build
	@./scripts/refute-crux-gate.sh

# ─────────────────────────────────────────────────────────────────────
# Run all benchmarks
# ─────────────────────────────────────────────────────────────────────

benchmark-all: benchmark-erc20 benchmark-totp refute-crux-gate
