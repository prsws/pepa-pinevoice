#!/usr/bin/env bash
# Check out the pinned PineVoice SDK and put the Oye Pepa! model into its data/mnt folder.
# Usage: scripts/prepare.sh [--rename] [--label]
#   (default)  hijack the hey_jarvis slot: copy oye_pepa.* over hey_jarvis.*  (data-only change)
#   --rename   instead patch the C906 loader to open /mnt/oye_pepa.* and add the files under that name
#   --label    also patch wyoming.c so the satellite advertises "oye pepa" instead of "hey jarvis"
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="$ROOT/vendor/pinevoice_smartspeaker_sdk"
SDK_SHA="96197109949da77da3617817714c8dc05108f390"   # pine64/pinevoice_smartspeaker_sdk, checked 2026-11-09
FLASHTOOL_URL="http://files.pine64.org/tools/bouffalo/bflb_flashtool_bl606p_v190.tar.gz"
RENAME=0; LABEL=0
for a in "$@"; do
  case "$a" in --rename) RENAME=1 ;; --label) LABEL=1 ;; *) echo "unknown option $a" >&2; exit 2 ;; esac
done

[ -f "$ROOT/models/oye_pepa.tflite" ] || { echo "run scripts/fetch-model.sh first" >&2; exit 1; }

if [ ! -d "$SDK/.git" ]; then
  mkdir -p "$ROOT/vendor"
  git clone https://github.com/pine64/pinevoice_smartspeaker_sdk.git "$SDK"
fi
git -C "$SDK" checkout "$SDK_SHA"
git -C "$SDK" submodule update --init --recursive

# the YoC build calls the Bouffalo flash tool (x86-64 Linux binary), so it must be present before building
if [ ! -x "$SDK/tools/flashtool/bflb_iot_tool-ubuntu" ]; then
  mkdir -p "$SDK/tools/flashtool"
  curl -fL "$FLASHTOOL_URL" -o /tmp/bflb_flashtool.tar.gz
  tar xzf /tmp/bflb_flashtool.tar.gz -C "$SDK/tools/flashtool"
  chmod +x "$SDK/tools/flashtool/bflb_iot_tool-ubuntu"
fi

DATA="$SDK/solutions/pinevoice_fw_e907/data/mnt"
STOCK="$ROOT/models/stock"
mkdir -p "$STOCK"
for f in hey_jarvis.json hey_jarvis.tflite; do
  [ -f "$STOCK/$f" ] || cp "$DATA/$f" "$STOCK/$f"       # keep pristine copies for restore-stock.sh
done

apply() {  # apply <dir> <patch>   (skips if already applied)
  if patch -p1 -R --dry-run -s -d "$1" < "$2" >/dev/null 2>&1; then echo "already applied: $(basename "$2")"
  else patch -p1 -d "$1" < "$2"; fi
}

if [ "$RENAME" -eq 1 ]; then
  apply "$SDK/solutions/pinevoice_fw_c906" "$ROOT/patches/c906-model-filenames-oye-pepa.patch"
  cp "$ROOT/models/oye_pepa.json"   "$DATA/oye_pepa.json"
  cp "$ROOT/models/oye_pepa.tflite" "$DATA/oye_pepa.tflite"
else
  cp "$ROOT/models/oye_pepa.json"   "$DATA/hey_jarvis.json"
  cp "$ROOT/models/oye_pepa.tflite" "$DATA/hey_jarvis.tflite"
fi
[ "$LABEL" -eq 1 ] && apply "$SDK/solutions/pinevoice_fw_e907" "$ROOT/patches/e907-wake-label-oye-pepa.patch"

echo "--- $DATA"; ls -la "$DATA"
echo "ready. next: scripts/build.sh"
