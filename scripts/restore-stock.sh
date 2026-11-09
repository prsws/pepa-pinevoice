#!/usr/bin/env bash
# Put the stock Hey Jarvis model back and undo the optional patches. Then rebuild and reflash.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="$ROOT/vendor/pinevoice_smartspeaker_sdk"
DATA="$SDK/solutions/pinevoice_fw_e907/data/mnt"
STOCK="$ROOT/models/stock"

[ -f "$STOCK/hey_jarvis.tflite" ] || { echo "no stock copies in models/stock (prepare.sh never ran)" >&2; exit 1; }
cp "$STOCK/hey_jarvis.json" "$STOCK/hey_jarvis.tflite" "$DATA/"
rm -f "$DATA/oye_pepa.json" "$DATA/oye_pepa.tflite"

undo() {
  if patch -p1 -R --dry-run -s -d "$1" < "$2" >/dev/null 2>&1; then patch -p1 -R -d "$1" < "$2"; fi
}
undo "$SDK/solutions/pinevoice_fw_c906" "$ROOT/patches/c906-model-filenames-oye-pepa.patch"
undo "$SDK/solutions/pinevoice_fw_e907" "$ROOT/patches/e907-wake-label-oye-pepa.patch"
echo "stock restored. next: scripts/build.sh && scripts/flash.sh"
