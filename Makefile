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
# Refute-crux verdict gate: 80 frozen verify verdicts across twelve suites,
# eleven under examples/ and one under tools/llmll-driver/. Freezes verdict +
# exit code ONLY (not report/classification shapes).
#
# This comment named four families (tcp_rfc793, session-pay, gotofail,
# outcome-totality) and the corpus has been twelve for several releases. Counted
# from the port's `families` list rather than corrected by guess.
#
# THE BUILD IS THE STALE-BINARY GUARD (finding F-3), and it lives here now
# rather than inside the gate. `stack exec` does not rebuild, so grading a
# compiler change against an old binary reads a lost refutation as vacuously
# SAFE. CI does not need this line, having built before the gate runs since
# a23e361; `make` does, and this is the caller that has it. Moving it here is
# what lets the LLMLL port (TOOL-RFC-002) carry no dependency on a Haskell
# build system. Under `set -e` semantics a failed build aborts the target
# loudly instead of gating against a stale binary.
#
# THIS TARGET RAN scripts/refute-crux-gate.sh UNTIL 2026-08-17. TOOL-RFC-002
# retired the reference, so the recipe builds the LLMLL port and runs that. The
# guard above did not move again: $(SUBJECT) is the binary the first line just
# built, and the port grades with the same one it was compiled by.
#
# THE COST IS PAID HERE, and it is worth stating because a `make` target is what
# a person runs by hand. The reference was one line and ran in about seventy
# seconds. This recipe compiles an LLMLL program to Haskell and builds it first,
# so a cold run is minutes. CI does not pay it twice: the workflow's step reuses
# the same build.
#
# The stdin budget comes from python3 and NOT `yes x | head -n N`: `yes` dies of
# SIGPIPE by design, which would report 141 no matter what the gate decided. Run
# from a scratch dir, because a console program writes <module>.event-log.jsonl
# into its working directory and this one would write it into the repo root.
# ─────────────────────────────────────────────────────────────────────

refute-crux-gate:
	@cd compiler && stack build
	@set -eu; \
	ROOT="$$PWD"; \
	SUBJECT="$$(cd compiler && stack path --local-install-root)/bin/llmll"; \
	OUT="$$(mktemp -d)/refutecrux"; \
	( cd tools/refute-crux && "$$SUBJECT" build refutecrux.llmll -o "$$OUT" >/dev/null ); \
	GROOT="$$( (cd "$$OUT" && stack path --local-install-root) )"; \
	GATE="$$GROOT/bin/refutecrux"; \
	[ -x "$$GATE" ] || { echo "no refutecrux binary under $$OUT"; exit 1; }; \
	WORK="$$(mktemp -d)"; RUN="$$(mktemp -d)"; \
	cd "$$RUN" && python3 -c "import sys; sys.stdout.write('x\n' * 4000)" \
	  | "$$GATE" --root "$$ROOT" --subject "$$SUBJECT" --work "$$WORK"

# ─────────────────────────────────────────────────────────────────────
# Run all benchmarks
# ─────────────────────────────────────────────────────────────────────

benchmark-all: benchmark-erc20 benchmark-totp refute-crux-gate
