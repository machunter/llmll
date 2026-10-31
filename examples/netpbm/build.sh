#!/bin/sh
# Verify the layered core leaf-first, test, build the CLI and cross-check it.
#
# Order matters: a strict-core `def` may only call a def whose body-faithful
# record (<module>.llmll.verified.json) was written by an EARLIER verify run,
# so pixel and mainlogic (layer 1) go before geom (2), blur (3), netpbm and main.
set -e
cd "$(dirname "$0")"
LLMLL=${LLMLL:-$(cd ../../compiler && stack path --local-install-root)/bin/llmll}
for m in pixel mainlogic geom blur netpbm main; do
  "$LLMLL" verify "$m.llmll"
done
"$LLMLL" test netpbm.llmll
"$LLMLL" build main.llmll -o build
EXE=$(cd build && stack path --local-install-root)/bin/main
echo "executable: $EXE"
python3 -I tools/crosscheck.py "$EXE" samples work/out
