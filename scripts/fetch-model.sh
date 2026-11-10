#!/usr/bin/env bash
# Download the Oye Pepa! microWakeWord model and check it has what the PineVoice loader needs.
# Usage: scripts/fetch-model.sh [--cutoff 0.95] [--arena 48000]
#   --cutoff X   rewrite micro.probability_cutoff in the copy that gets flashed
#   --arena N    rewrite micro.tensor_arena_size in the copy that gets flashed
#                (the upstream manifest is kept as models/oye_pepa.upstream.json)
#
# Tensor arena: the PineVoice firmware allocates exactly micro.tensor_arena_size, so a manifest value
# that is too small means the model never loads (ESPHome grows the arena itself and hides this).
# config/arena.tsv lists models measured with scripts/probe-arena.sh; for a listed model the flashed
# copy gets the arena from that table unless --arena is given. An --arena below the measured minimum
# is refused. For a model that is not listed, run scripts/probe-arena.sh before flashing.
set -euo pipefail

BASE="${OYE_PEPA_BASE:-https://ai-for-aging.org}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/models"
CUTOFF=""
ARENA=""

while [ $# -gt 0 ]; do
  case "$1" in
    --cutoff) CUTOFF="${2:?--cutoff needs a value}"; shift 2 ;;
    --arena)  ARENA="${2:?--arena needs a value}"; shift 2 ;;
    *) echo "usage: $0 [--cutoff 0.95] [--arena 48000]" >&2; exit 2 ;;
  esac
done

mkdir -p "$OUT"
# Download and check in a temp folder; models/ is only updated if every check passes, so a failed
# run never leaves a manifest behind that prepare.sh would copy into the build.
TMP="$(mktemp -d)"
trap 'rm -r "$TMP"' EXIT
curl -fsSL "$BASE/oye_pepa.json"   -o "$TMP/oye_pepa.json"
curl -fsSL "$BASE/oye_pepa.tflite" -o "$TMP/oye_pepa.tflite"
[ -f "$OUT/oye_pepa.upstream.json" ] || cp "$TMP/oye_pepa.json" "$OUT/oye_pepa.upstream.json"

SHA=$( (shasum -a 256 "$TMP/oye_pepa.tflite" 2>/dev/null || sha256sum "$TMP/oye_pepa.tflite") | cut -d' ' -f1)

python3 - "$TMP/oye_pepa.json" "$CUTOFF" "$ARENA" "$SHA" "$ROOT/config/arena.tsv" <<'PY'
import json, sys
path, cutoff, arena, sha, table = sys.argv[1:6]
d = json.load(open(path, encoding="utf-8"))
m = d.get("micro")
if not isinstance(m, dict):
    sys.exit("FAIL: no 'micro' object in manifest")
need = ["probability_cutoff", "feature_step_size", "sliding_window_size", "tensor_arena_size"]
missing = [k for k in need if not isinstance(m.get(k), (int, float))]
if missing:
    sys.exit(f"FAIL: PineVoice loader rejects the file; missing/non-numeric: {missing}")

known = {}
for line in open(table, encoding="utf-8"):
    if line.strip() and not line.startswith("#"):
        f = line.rstrip("\n").split("\t")
        known[f[0]] = (int(f[1]), int(f[2]))

changed = False
if cutoff:
    m["probability_cutoff"] = float(cutoff)
    changed = True
    print(f"cutoff rewritten to {cutoff}")

upstream_arena = m["tensor_arena_size"]
if arena:
    m["tensor_arena_size"] = int(arena)
elif sha in known and upstream_arena < known[sha][1]:
    m["tensor_arena_size"] = known[sha][1]
if m["tensor_arena_size"] != upstream_arena:
    changed = True
    print(f"tensor_arena_size rewritten: {upstream_arena} -> {m['tensor_arena_size']}")

if sha in known:
    minimum = known[sha][0]
    if m["tensor_arena_size"] < minimum:
        sys.exit(f"FAIL: tensor_arena_size {m['tensor_arena_size']} is below the {minimum} bytes this model "
                 "needs on the PineVoice (config/arena.tsv); the model would not load")
    print(f"arena OK: {m['tensor_arena_size']} >= measured minimum {minimum}")
else:
    print("WARN: this model is not in config/arena.tsv; run scripts/probe-arena.sh before flashing "
          "(a too-small arena means the wake word is silently off)", file=sys.stderr)

if changed:
    with open(path, "w", encoding="utf-8") as out:
        json.dump(d, out, indent=2, ensure_ascii=False)
        out.write("\n")
print("manifest OK:", {k: m[k] for k in need})
PY

mv "$TMP/oye_pepa.json" "$TMP/oye_pepa.tflite" "$OUT/"
SIZE=$(wc -c < "$OUT/oye_pepa.tflite")
echo "tflite: $SIZE bytes  sha256: $SHA"
# media partition is 753664 bytes; stock files + opus tones use ~110 KB
if [ "$SIZE" -gt 400000 ]; then
  echo "WARN: model is large for the 736 KB media partition (stock files use ~110 KB)" >&2
fi
