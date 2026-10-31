#!/bin/sh
# Verify the core leaf-first, then the shell, test, build the CLI and
# cross-check it against an independent Python reference.
#
# Order matters: `check`/`verify` on an importer needs the import's
# <module>.llmll.verified.json, written by an EARLIER verify run.
#   level 0: types lex sample   level 1: rules geom   level 2: kernel
#   level 3: blur               shell:   codec image main
set -e
cd "$(dirname "$0")"
LLMLL=${LLMLL:-$(cd ../../compiler && stack path --local-install-root)/bin/llmll}
for m in types lex sample rules geom kernel blur codec image main; do
  "$LLMLL" verify --trust-report "$m.llmll"
done
for m in lex sample rules geom kernel blur codec image main; do
  "$LLMLL" test "$m.llmll"
done
"$LLMLL" build main.llmll -o build
EXE=$(cd build && stack path --local-install-root)/bin/main
echo "executable: $EXE"
mkdir -p work
python3 -I tools/gen256.py work/big256.ppm
python3 -I tools/crosscheck.py "$EXE" samples work/out work/big256.ppm
