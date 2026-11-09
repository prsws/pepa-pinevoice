#!/usr/bin/env bash
# Flash the PineVoice (firmware + media partition) over USB.
# Needs an x86-64 Linux host with the unit attached: the Bouffalo flash tool is a Linux x86-64 binary
# and Docker Desktop on macOS cannot pass USB serial devices through.
#
# Usage: PORT=/dev/ttyACM0 scripts/flash.sh
# Before running: power the PineVoice OFF, hold the center ring button, power it ON. The bootloader
# window is short, so start this script within a few seconds.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="$ROOT/vendor/pinevoice_smartspeaker_sdk"
E907="$SDK/solutions/pinevoice_fw_e907"
: "${PORT:?set PORT, e.g. PORT=/dev/ttyACM0 (ls -l /dev/ttyACM* /dev/ttyUSB*)}"

[ -f "$E907/generated/littlefs.bin" ] || { echo "no littlefs.bin: run scripts/build.sh first" >&2; exit 1; }
[ "$(uname -s)" = "Linux" ] && [ "$(uname -m)" = "x86_64" ] || \
  echo "WARN: $(uname -sm): the flash tool probably will not run here" >&2

# The SDK's flash.sh picks the first /dev/tty* it finds, which is unreliable; pin the port in a local copy.
sed "s#^PV_TTY=.*#PV_TTY=${PORT}#" "$E907/flash.sh" > "$E907/flash.local.sh"
chmod +x "$E907/flash.local.sh"
cd "$E907"
# "full" = also flash the media partition (littlefs.bin), which is where the wake-word model lives.
# Without "full" only the firmware is flashed and the model does not change.
./flash.local.sh cli full
