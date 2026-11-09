#!/usr/bin/env bash
# Build the PineVoice firmware + littlefs image in the SDK's Docker image (Ubuntu 22.04, x86-64).
# Output: vendor/pinevoice_smartspeaker_sdk/firmware_<commit>.zip and solutions/pinevoice_fw_e907/generated/littlefs.bin
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="$ROOT/vendor/pinevoice_smartspeaker_sdk"
[ -d "$SDK/solutions/pinevoice_fw_e907/data" ] || { echo "run scripts/prepare.sh first" >&2; exit 1; }

cd "$SDK"
# --platform: the Pine64 toolchain and flash tool are x86-64 binaries (matters on Apple Silicon)
docker build --platform linux/amd64 \
  --build-arg UID="$(id -u)" --build-arg GID="$(id -g)" \
  -t pinevoice-sdk -f .devcontainer/Dockerfile .
docker run --rm --platform linux/amd64 \
  -v "$PWD:/workspace" -w /workspace \
  pinevoice-sdk ./package.sh

ls -la solutions/pinevoice_fw_e907/generated/littlefs.bin firmware_*.zip
