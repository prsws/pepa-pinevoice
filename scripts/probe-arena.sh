#!/usr/bin/env bash
# Measure the tensor arena a wake-word model needs on the PineVoice, using the SDK's own tflite_micro.
#
# Usage: scripts/probe-arena.sh [model.tflite] [manifest.json]
#        (defaults: models/oye_pepa.tflite models/oye_pepa.json)
#
# Why: the PineVoice C906 firmware mallocs exactly micro.tensor_arena_size from the manifest. If it is
# too small the model fails to load and the wake word is silently off (the button still works).
# ESPHome probes and grows the arena on its own, so a manifest that works on ESPHome devices can still
# be too small here. See docs/how-it-works.md, "Tensor arena".
#
# Needs: scripts/prepare.sh run once (the SDK in vendor/), and g++ on a 64-bit host. The first run
# compiles tflite_micro (about 150 files, a minute or two); later runs reuse tools/arena-probe/build/.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODEL="${1:-$ROOT/models/oye_pepa.tflite}"
MANIFEST="${2:-${MODEL%.tflite}.json}"
TFLM="${TFLM_DIR:-$ROOT/vendor/pinevoice_smartspeaker_sdk/components/tflite_micro}"
BUILD="$ROOT/tools/arena-probe/build"

[ -f "$MODEL" ] || { echo "no model at $MODEL (run scripts/fetch-model.sh first)" >&2; exit 2; }
[ -f "$TFLM/package.yaml" ] || { echo "no SDK tflite_micro at $TFLM (run scripts/prepare.sh first)" >&2; exit 2; }
command -v g++ >/dev/null || { echo "g++ not found (Debian: apt install g++)" >&2; exit 2; }
[ "$(getconf LONG_BIT)" = 64 ] || echo "WARN: 32-bit host; the numbers will be lower than on the C906 (RV64)" >&2

CXXFLAGS=(-std=c++17 -O2 -fno-rtti -fno-exceptions -fno-threadsafe-statics -w
  -DTF_LITE_STATIC_MEMORY=1 -DTF_LITE_USE_GLOBAL_CMATH_FUNCTIONS=1 -DTF_LITE_USE_GLOBAL_MIN=1
  -DTF_LITE_USE_GLOBAL_MAX=1
  -I"$TFLM" -I"$TFLM/third_party/gemmlowp" -I"$TFLM/third_party/flatbuffers/include"
  -I"$TFLM/third_party/ruy" -I"$TFLM/third_party/kissfft")

if [ ! -x "$BUILD/probe" ] || [ "$ROOT/tools/arena-probe/probe.cpp" -nt "$BUILD/probe" ]; then
  mkdir -p "$BUILD/obj"
  # The interpreter and kernels as listed in the SDK's package.yaml. kernel_runner.cc is a test helper
  # with dependencies outside that list; the signal/ library is not used by microWakeWord.
  sed -n '/^source_file:/,/^[a-z_]*:/p' "$TFLM/package.yaml" | sed -n 's/^[[:space:]]*-[[:space:]]*//p' \
    | grep '^tensorflow/' | grep -v 'kernel_runner\.cc$' > "$BUILD/sources.txt"
  echo "compiling $(wc -l < "$BUILD/sources.txt") tflite_micro sources from the SDK..."
  export TFLM BUILD
  export CXXFLAGS_STR="${CXXFLAGS[*]}"
  xargs -P "$(nproc 2>/dev/null || echo 2)" -I{} sh -c '
    o="$BUILD/obj/$(echo "{}" | tr / _).o"
    [ "$o" -nt "$TFLM/{}" ] && exit 0
    case "{}" in
      *.c) gcc -O2 -w -DTF_LITE_STATIC_MEMORY=1 -I"$TFLM" -c "$TFLM/{}" -o "$o" ;;
      *)   g++ $CXXFLAGS_STR -c "$TFLM/{}" -o "$o" ;;
    esac || { echo "FAILED: {}" >&2; exit 255; }' < "$BUILD/sources.txt"
  ar rcs "$BUILD/libtflm.a" "$BUILD"/obj/*.o
  g++ "${CXXFLAGS[@]}" "$ROOT/tools/arena-probe/probe.cpp" "$BUILD/libtflm.a" -lm -o "$BUILD/probe"
fi

ARENA=""
if [ -f "$MANIFEST" ]; then
  ARENA=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["micro"]["tensor_arena_size"])' "$MANIFEST")
  echo "manifest: $MANIFEST"
fi
"$BUILD/probe" "$MODEL" $ARENA
