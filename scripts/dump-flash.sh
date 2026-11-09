#!/usr/bin/env bash
# Take a READ-ONLY full dump of the PineVoice's 16 MiB flash (0x000000-0xFFFFFF) = the rollback image.
# Run this BEFORE the first flash. Nothing is written to the device.
#
# Usage: [PORT=/dev/ttyACM0] [BACKUP_DIR=~/pinevoice-backup] scripts/dump-flash.sh
# Before running: power the PineVoice OFF, hold the center ring button, power it ON (bootloader mode).
#
# Notes (see docs/how-it-works.md, "Reading the flash"):
# - The Bouffalo tool ignores --outdir for the data and writes ./flash.bin in its cwd, so we run it in
#   the flashtool folder and move the result.
# - --end is inclusive, hence 0xFFFFFF.
# - The tool resets the chip when it finishes, so a second dump needs bootloader mode again.
# - The image may contain Wi-Fi credentials. It goes to BACKUP_DIR, outside the repo. Never commit it.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FT="$ROOT/vendor/pinevoice_smartspeaker_sdk/tools/flashtool"
PORT="${PORT:-/dev/ttyACM0}"
OUT="${BACKUP_DIR:-$HOME/pinevoice-backup}"
TS="$(date +%Y%m%d-%H%M%S)"
LOG="$OUT/dump-$TS.log"
WANT=16777216

[ -x "$FT/bflb_iot_tool-ubuntu" ] || { echo "flash tool missing: run scripts/prepare.sh first" >&2; exit 1; }
[ -e "$PORT" ] || { echo "$PORT not found: put the unit in bootloader mode first" >&2; exit 1; }
mkdir -p "$OUT"

cd "$FT"
rm -f flash.bin
echo "start $(date +%T) port=$PORT" | tee "$LOG"
rc=0
timeout 600 ./bflb_iot_tool-ubuntu --chipname=bl606p --interface=uart --port="$PORT" \
  --baudrate=2000000 --read --start=0x0 --end=0xFFFFFF >>"$LOG" 2>&1 || rc=$?
echo "tool exit=$rc at $(date +%T)" | tee -a "$LOG"

size=$(stat -c %s flash.bin 2>/dev/null || echo 0)
echo "flash.bin size=$size (want $WANT)" | tee -a "$LOG"
if [ "$size" != "$WANT" ]; then
  echo "DUMP FAILED: size mismatch, nothing kept as a rollback image. See $LOG" | tee -a "$LOG" >&2
  exit 1
fi
mv flash.bin "$OUT/pinevoice-full-$TS.bin"
( cd "$OUT" && sha256sum "pinevoice-full-$TS.bin" | tee "pinevoice-full-$TS.bin.sha256" | tee -a "$LOG" )
echo "DUMP OK: $OUT/pinevoice-full-$TS.bin" | tee -a "$LOG"
echo "Next: take a second dump (bootloader mode again) and compare sha256 before trusting this as the rollback."
