#!/bin/sh
# Verify the core leaf-first, then the shell, test, build the CLI and
# cross-check it against an independent Python reference.
#
#   ./build.sh            verify, test, build, cross-check
#   ./build.sh --refill   first fill every core hole again through the hole
#                         protocol (checkout + patch), from holed/ and fills/
#   ./build.sh --mutants  also verify 10 wrong core bodies (each must fail)
#
# Order matters: `check`/`verify` on an importer needs the import's
# <module>.llmll.verified.json, written by an EARLIER verify run. Verify
# runs one module at a time.
#   level 0: raster hdr   level 1: xform   shell: y4m main   tests: props
set -e
cd "$(dirname "$0")"
LLMLL=${LLMLL:-$(cd ../../compiler && stack path --local-install-root)/bin/llmll}
export LLMLL
mkdir -p work
for m in raster hdr xform; do
  if [ "$1" = "--refill" ]; then
    rm -f "$m.ast.json"
    python3 -I tools/fill.py "$m"
    python3 -I tools/fill.py "$m" --source
  fi
  /usr/bin/time -p "$LLMLL" verify --trust-report "$m.llmll"
done
for m in y4m main; do
  /usr/bin/time -p "$LLMLL" verify --trust-report "$m.llmll"
done
"$LLMLL" test props.llmll
if [ "$1" = "--mutants" ]; then
  python3 -I tools/mutants.py work/mutants
fi
/usr/bin/time -p "$LLMLL" build main.llmll -o build
EXE=$(cd build && stack path --local-install-root)/bin/main
echo "executable: $EXE"
python3 -I tools/gen.py samples samples
python3 -I tools/gen.py clip work/clip-320x240x30.y4m 320 240 30
for c in "info work/clip-320x240x30.y4m" \
         "frame work/clip-320x240x30.y4m 29 work/f29.pgm" \
         "hflip work/clip-320x240x30.y4m work/hflip.y4m" \
         "crop work/clip-320x240x30.y4m 32 16 255 201 work/crop.y4m"; do
  echo "timing: $c"
  # shellcheck disable=SC2086
  /usr/bin/time -l "$EXE" $c 2>&1 | grep -E "real|maximum resident|^width|^frames|->"
done
python3 -I tools/crosscheck.py "$EXE" samples work/out work/clip-320x240x30.y4m
