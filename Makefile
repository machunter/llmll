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
# ─────────────────────────────────────────────────────────────────────

refute-crux-gate:
	@./scripts/refute-crux-gate.sh

# ─────────────────────────────────────────────────────────────────────
# Run all benchmarks
# ─────────────────────────────────────────────────────────────────────

benchmark-all: benchmark-erc20 benchmark-totp refute-crux-gate
