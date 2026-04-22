# LLMLL Benchmarks Makefile
# v0.6.0: Frozen benchmark CI gates

LLMLL := cd compiler && stack run --

.PHONY: benchmark-erc20 benchmark-all

# ─────────────────────────────────────────────────────────────────────
# ERC-20 Token Benchmark (v0.6.0)
# ─────────────────────────────────────────────────────────────────────

benchmark-erc20:
	@echo "═══ ERC-20 Benchmark ═══"
	@echo "--- Check skeleton (holes) ---"
	$(LLMLL) -- check ../examples/erc20_token/erc20.ast.json
	@echo ""
	@echo "--- Check filled version ---"
	$(LLMLL) -- check ../examples/erc20_token/erc20_filled.ast.json
	@echo ""
	@echo "--- Spec coverage ---"
	$(LLMLL) -- verify ../examples/erc20_token/erc20_filled.ast.json --spec-coverage
	@echo ""
	@echo "--- Spec coverage (JSON) ---"
	$(LLMLL) -- verify ../examples/erc20_token/erc20_filled.ast.json --spec-coverage --json
	@echo ""
	@echo "═══ ERC-20 Benchmark PASSED ═══"

# ─────────────────────────────────────────────────────────────────────
# Run all benchmarks
# ─────────────────────────────────────────────────────────────────────

benchmark-all: benchmark-erc20
