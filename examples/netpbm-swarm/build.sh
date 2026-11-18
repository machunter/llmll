#!/bin/sh
# Verify the core leaf-first, then the shell, test, build the CLI and
# cross-check it against an independent Python reference.
#
#   ./build.sh            verify, test, build, cross-check
#   ./build.sh --refill   first fill binfmt's holes again through the hole
#                         protocol (checkout + patch), from holed/ and fills/
#   ./build.sh --mutants  also verify 4 wrong binfmt bodies (all must be refuted)
#
# Order matters: `check`/`verify` on an importer needs the import's
# <module>.llmll.verified.json, written by an EARLIER verify run.
#   level 0: types lex sample   level 1: binfmt rules geom   level 2: kernel
#   level 3: blur               shell:   codec image main
set -e
cd "$(dirname "$0")"
LLMLL=${LLMLL:-$(cd ../../compiler && stack path --local-install-root)/bin/llmll}
export LLMLL
mkdir -p work
if [ "$1" = "--refill" ]; then
  rm -f binfmt.ast.json
  python3 -I tools/fill.py binfmt
  python3 -I tools/fill.py binfmt --source
fi
for m in types lex sample binfmt rules geom kernel blur codec image main; do
  if [ "$m" = "blur" ]; then
    echo "SKIPPED: verify blur.llmll (EXAMPLES-VERIFY-REGRESS-1: stops at the solver time limit on v0.41.0)"
    continue
  fi
  "$LLMLL" verify --trust-report "$m.llmll"
done
for m in lex sample binfmt rules geom kernel blur codec image main; do
  "$LLMLL" test "$m.llmll"
done
if [ "$1" = "--mutants" ]; then
  python3 -I tools/mutants.py work/mutants
fi
"$LLMLL" build main.llmll -o build
EXE=$(cd build && stack path --local-install-root)/bin/main
echo "executable: $EXE"
python3 -I tools/gen256.py work/big256.ppm
python3 -I tools/genbin.py samples work/big256-p6.ppm
python3 -I tools/crosscheck.py "$EXE" samples work/out work/big256.ppm work/big256-p6.ppm
