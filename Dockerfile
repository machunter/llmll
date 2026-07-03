# syntax=docker/dockerfile:1
# ─────────────────────────────────────────────────────────────────────────────
# LLMLL zero-install image — verify-capable (llmll + fixpoint + z3 + demos).
#
# Build from the REPO ROOT (the build needs both compiler/ and examples/):
#     docker build -t llmll:dev .
#
# Headline demo, no mount (SMT refutation of a conservation-breaking fill):
#     docker run --rm llmll:dev verify /opt/llmll/examples/payments-core/conserve-bad.llmll
#
# Verify your own file (mount the current directory):
#     docker run --rm -v "$PWD":/work llmll:dev verify myfile.llmll
#
# This packages the COMPILER for distribution. It is unrelated to the Docker
# sandbox that isolates untrusted agent-generated code — different concern.
# ─────────────────────────────────────────────────────────────────────────────

# ---- Stage 1: builder (large; discarded, never shipped) ----
FROM haskell:9.6.6 AS build
# GHC 9.6.6 == the compiler stanza of resolver lts-22.43 (compiler/stack.yaml),
# so `--system-ghc` reuses the image GHC instead of downloading a second copy.
# `stack` ships in the official haskell image.
WORKDIR /src
COPY compiler/ ./compiler/
COPY examples/ ./examples/

# Build the `llmll` executable into /out.
RUN cd compiler \
 && stack build --system-ghc --copy-bins --local-bin-path /out

# Build the SMT backend into /out. liquid-fixpoint installs as `fixpoint`, which
# `llmll verify` discovers on PATH (compiler/app/Main.hs:1240-1245) and which in
# turn shells out to z3 (smtlib-backends-process).
#
# lts-22.43 does NOT ship smtlib-backends / smtlib-backends-process, so the two
# must be supplied as extra-deps (everything else liquid-fixpoint-0.9.6.3.1
# needs resolves from the snapshot). The pinned cabal-revision hashes below are
# the exact set proven to build this liquid-fixpoint on a clean tree; they are
# what a bare-snapshot `stack install` is otherwise missing.
RUN mkdir -p /build && printf '%s\n' \
      'snapshot: lts-22.43' \
      'packages: []' \
      'extra-deps:' \
      '  - smtlib-backends-0.4@sha256:a7ae228f4464727a8c725341cf9b6690577f5289c80a33e8960264e296fb9a47,1258' \
      '  - smtlib-backends-process-0.3@sha256:bb730a55c5974eeb24112b560d30c49d518d6de45148723435219baa269f8b5e,1676' \
      > /build/fixpoint.stack.yaml \
 && stack --stack-yaml /build/fixpoint.stack.yaml --system-ghc \
      install liquid-fixpoint-0.9.6.3.1 --local-bin-path /out

# Fail the build here if either binary has an unsatisfiable shared-library set —
# the classic "the slim runtime can't exec the copied GHC binary" trap. The
# runtime apt list below must cover everything these two lines print.
RUN ldd /out/llmll && ldd /out/fixpoint

# ---- Stage 2: slim runtime (this is what ships) ----
FROM debian:bookworm-slim
# z3: REQUIRED — fixpoint shells out to it; absent, `llmll verify` exits 3
#     (SOLVER NOT FOUND, compiler/app/Main.hs:1247-1282), a dead demo.
# libgmp10 + zlib1g: the only non-base shared libs the two copied GHC binaries
#     dynamically link (per the builder `ldd` step — they do NOT link
#     libffi/libtinfo). z3 pulls its own transitive deps via apt.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      z3 libgmp10 zlib1g ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# GHC's text IO decodes source files using the locale encoding. debian-slim
# defaults to the C (ASCII) locale, so `llmll` fails on the first non-ASCII byte
# of a .llmll file (hGetContents: invalid argument). C.UTF-8 is built into glibc
# — no `locales` package required.
ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

COPY --from=build /out/llmll    /usr/local/bin/llmll
COPY --from=build /out/fixpoint /usr/local/bin/fixpoint
COPY --from=build /src/examples /opt/llmll/examples

# User .llmll files land here via `-v "$PWD":/work`.
WORKDIR /work
ENTRYPOINT ["llmll"]
CMD ["--help"]

LABEL org.opencontainers.image.title="llmll" \
      org.opencontainers.image.description="LLMLL verify-capable compiler (llmll + liquid-fixpoint + z3)" \
      org.opencontainers.image.source="https://github.com/machunter/llmll"
