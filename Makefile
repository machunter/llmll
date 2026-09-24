# LLMLL Makefile: build, test and install the compiler, plus the benchmark and
# verdict gates. Run `make` or `make help` for the list of targets.

.DEFAULT_GOAL := help

.PHONY: help build test install benchmark-erc20 benchmark-totp refute-crux-gate \
        fallback-census benchmark-all demo-gifs

# ─────────────────────────────────────────────────────────────────────
# Build, test, install
#
# `build` and `install` use the resolver pinned in compiler/stack.yaml.
# `test` runs the Haskell suite (compiler/test) and the Python suite
# (scripts/tests). Python tests that call the compiler skip unless LLMLL_BIN
# names a binary, so `test` builds first and points LLMLL_BIN at that build.
# `install` copies llmll into BINDIR (default ~/.local/bin).
# ─────────────────────────────────────────────────────────────────────

BINDIR ?= $(HOME)/.local/bin

help:
	@echo "Targets:"
	@echo "  build             build the llmll compiler (stack build in compiler/)"
	@echo "  test              Haskell tests (stack test) and Python tests (scripts/tests)"
	@echo "  install           install llmll into BINDIR (default: ~/.local/bin)"
	@echo "  refute-crux-gate  CI verdict gate: frozen verify verdicts for the example suites"
	@echo "  fallback-census   body-faithful ratio over the tracked tree (CI ratchet)"
	@echo "  benchmark-erc20   ERC-20 benchmark"
	@echo "  benchmark-totp    TOTP (RFC 6238) benchmark"
	@echo "  benchmark-all     both benchmarks and refute-crux-gate"
	@echo "  demo-gifs         re-record the README demo GIFs (needs asciinema, agg)"
	@echo "llmll verify needs fixpoint and z3 on PATH: see docs/getting-started.md."

build:
	cd compiler && stack build

test: build
	cd compiler && stack test
	LLMLL_BIN="$$(cd compiler && stack path --local-install-root)/bin/llmll" \
	  python3 -m pytest scripts/tests/ -q

install:
	cd compiler && stack install --local-bin-path "$(BINDIR)"

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
# Refute-crux verdict gate: 96 frozen verify verdicts across fifteen suites,
# fourteen under examples/ and one under tools/llmll-driver/. Freezes verdict +
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
# FALLBACK-CENSUS-1: the body-faithful ratio over the tracked tree, and the
# ratchet on the --strict-verified-core pass set. The same command CI runs.
# Builds first for the reason the refute-crux target does: `stack exec` does
# not rebuild, so a compiler change measured against the old binary reports
# the old tree.
# ─────────────────────────────────────────────────────────────────────

fallback-census:
	@cd compiler && stack build
	@SUBJECT="$$(cd compiler && stack path --local-install-root)/bin/llmll"; \
	python3 scripts/fallback_census.py --llmll "$$SUBJECT" --repo . \
	  --out "$$(mktemp -d)/fallback-census.json"

# ─────────────────────────────────────────────────────────────────────
# Run all benchmarks
# ─────────────────────────────────────────────────────────────────────

benchmark-all: benchmark-erc20 benchmark-totp refute-crux-gate

# ─────────────────────────────────────────────────────────────────────
# README demo GIFs: docs/assets/refute.gif and docs/assets/protocol.gif.
#
# Records each demo script headlessly in --auto mode (asciinema 3), then renders
# the cast with agg. The recording runs under `env -i` with a neutral prompt and
# only the tool directories on PATH, so no username, hostname or home path can
# reach the screen. Each demo copies its inputs into a temp dir and runs there,
# so no tracked example, sidecar or lock file is touched. Casts are written to
# a temp dir and never enter the repo.
#
# Needs asciinema, agg, jq, fixpoint (liquid-fixpoint) and z3 on PATH, and an
# llmll build. LLMLL_BIN defaults to this checkout's stack install root; from
# a worktree without its own build, pass it:
#   make demo-gifs LLMLL_BIN=<dir containing llmll>
#
# The leanstral GIF is NOT recorded here: it needs a Leanstral API key and a
# Lean 4 + Mathlib project. See the header of examples/leanstral-demo/demo.sh.
# ─────────────────────────────────────────────────────────────────────

LLMLL_BIN      ?= $(shell cd compiler && stack path --local-install-root 2>/dev/null)/bin
DEMO_SIZE      ?= 100x34
DEMO_FONT_SIZE ?= 14
DEMO_IDLE      ?= 2
DEMO_LAST      ?= 6

demo-gifs:
	@set -eu; \
	ROOT="$$PWD"; \
	test -x "$(LLMLL_BIN)/llmll" || { echo "demo-gifs: no llmll in '$(LLMLL_BIN)'; pass LLMLL_BIN=<dir>"; exit 1; }; \
	for t in asciinema agg jq fixpoint z3; do command -v $$t >/dev/null || { echo "demo-gifs: $$t not on PATH"; exit 1; }; done; \
	echo "demo-gifs: recording with $$("$(LLMLL_BIN)/llmll" version)"; \
	DEMO_PATH="$(LLMLL_BIN)"; \
	for t in fixpoint z3 jq; do DEMO_PATH="$$DEMO_PATH:$$(dirname "$$(command -v $$t)")"; done; \
	DEMO_PATH="$$DEMO_PATH:/usr/bin:/bin"; \
	ASCIINEMA="$$(command -v asciinema)"; \
	CASTS="$$(mktemp -d)"; \
	for pair in payments-core:refute withdraw-demo:protocol; do \
	  ex="$${pair%%:*}"; name="$${pair##*:}"; \
	  echo "demo-gifs: recording examples/$$ex/demo.sh -> docs/assets/$$name.gif"; \
	  env -i HOME="$$CASTS" SHELL=/bin/bash PATH="$$DEMO_PATH" TERM=xterm-256color \
	    LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 PS1='$$ ' \
	    "$$ASCIINEMA" rec --headless --overwrite -q --window-size $(DEMO_SIZE) \
	      -c "bash $$ROOT/examples/$$ex/demo.sh --auto" "$$CASTS/$$name.cast"; \
	  agg -q --font-size $(DEMO_FONT_SIZE) --idle-time-limit $(DEMO_IDLE) \
	    --last-frame-duration $(DEMO_LAST) "$$CASTS/$$name.cast" "docs/assets/$$name.gif"; \
	  ls -l "docs/assets/$$name.gif"; \
	done; \
	echo "demo-gifs: casts kept in $$CASTS"
