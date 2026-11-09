#!/usr/bin/env bash
# Download the Oye Pepa! microWakeWord model and check it has what the PineVoice loader needs.
# Usage: scripts/fetch-model.sh [--cutoff 0.95]
#   --cutoff X   rewrite micro.probability_cutoff in the copy that gets flashed
#                (the upstream manifest is kept as models/oye_pepa.upstream.json)
set -euo pipefail

BASE="${OYE_PEPA_BASE:-https://ai-for-aging.org}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/models"
CUTOFF=""

while [ $# -gt 0 ]; do
  case "$1" in
    --cutoff) CUTOFF="${2:?--cutoff needs a value}"; shift 2 ;;
    *) echo "usage: $0 [--cutoff 0.95]" >&2; exit 2 ;;
  esac
done

mkdir -p "$OUT"
curl -fsSL "$BASE/oye_pepa.json"   -o "$OUT/oye_pepa.json"
curl -fsSL "$BASE/oye_pepa.tflite" -o "$OUT/oye_pepa.tflite"
[ -f "$OUT/oye_pepa.upstream.json" ] || cp "$OUT/oye_pepa.json" "$OUT/oye_pepa.upstream.json"

python3 - "$OUT/oye_pepa.json" "$CUTOFF" <<'PY'
import json, sys
path, cutoff = sys.argv[1], sys.argv[2]
d = json.load(open(path))
m = d.get("micro")
if not isinstance(m, dict):
    sys.exit("FAIL: no 'micro' object in manifest")
need = ["probability_cutoff", "feature_step_size", "sliding_window_size", "tensor_arena_size"]
missing = [k for k in need if not isinstance(m.get(k), (int, float))]
if missing:
    sys.exit(f"FAIL: PineVoice loader rejects the file; missing/non-numeric: {missing}")
if cutoff:
    m["probability_cutoff"] = float(cutoff)
    json.dump(d, open(path, "w"), indent=2)
    print(f"cutoff rewritten to {cutoff}")
print("manifest OK:", {k: m[k] for k in need})
PY

SIZE=$(wc -c < "$OUT/oye_pepa.tflite")
echo "tflite: $SIZE bytes  sha256: $( (shasum -a 256 "$OUT/oye_pepa.tflite" 2>/dev/null || sha256sum "$OUT/oye_pepa.tflite") | cut -d' ' -f1)"
# media partition is 753664 bytes; stock files + opus tones use ~110 KB
if [ "$SIZE" -gt 400000 ]; then
  echo "WARN: model is large for the 736 KB media partition (stock files use ~110 KB)" >&2
fi
