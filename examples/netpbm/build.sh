#!/bin/sh
# Verify the layered core leaf-first, test, build the CLI and cross-check it.
#
# Order matters: a strict-core `def` may only call a def whose body-faithful
# record (<module>.llmll.verified.json) was written by an EARLIER verify run,
# so pixel, mainlogic and binfmt (layer 1) go before geom (2), blur (3),
# netpbm and main.
#
#   ./build.sh            verify, test, build, cross-check
#   ./build.sh --mutants  also verify 4 wrong binfmt bodies (all must be refuted)
set -e
cd "$(dirname "$0")"
LLMLL=${LLMLL:-$(cd ../../compiler && stack path --local-install-root)/bin/llmll}
for m in pixel mainlogic binfmt geom blur netpbm main; do
  "$LLMLL" verify "$m.llmll"
done
"$LLMLL" test netpbm.llmll
if [ "$1" = "--mutants" ]; then
  LLMLL="$LLMLL" python3 -I tools/mutants.py work/mutants
fi
"$LLMLL" build main.llmll -o build
EXE=$(cd build && stack path --local-install-root)/bin/main
echo "executable: $EXE"
python3 -I tools/genbin.py samples work/big256-p6.ppm work/big256.ppm
python3 -I tools/crosscheck.py "$EXE" samples work/out work/big256.ppm work/big256-p6.ppm
