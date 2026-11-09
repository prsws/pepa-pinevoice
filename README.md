# pepa-pinevoice

Putting the **Oye Pepa!** wake word on a Pine64 **PineVoice** smart speaker, and keeping the record of how the unit behaves as a Pepa voice satellite.

Status (2026-11-09): PineVoice is on prod HA as a Wyoming satellite and answers the hardware button. The on-device wake word is stock "Hey Jarvis" only. Nothing in this repo has been run yet.

## What this repo is

A thin wrapper around `pine64/pinevoice_smartspeaker_sdk` (pinned, not forked): scripts to fetch the model, drop it into the SDK's filesystem image, build, flash and undo. Plus the findings and an append-only bench log. The SDK itself goes in `vendor/` and is gitignored.

## The finding that makes this small

The wake-word model is **not compiled into the firmware**. The C906 core opens `/mnt/hey_jarvis.json` and `/mnt/hey_jarvis.tflite` at startup, from a littlefs partition built out of `solutions/pinevoice_fw_e907/data/mnt/`. The Oye Pepa! model is already in the same format (ESPHome microWakeWord manifest + `.tflite`). Details and file references: [docs/how-it-works.md](docs/how-it-works.md).

## Steps

```sh
scripts/fetch-model.sh                # models/oye_pepa.{json,tflite} from ai-for-aging.org, checks the 4 required fields
scripts/prepare.sh                    # pinned SDK -> vendor/, stock model backed up, Oye Pepa! put in the hey_jarvis slot
scripts/build.sh                      # Docker (linux/amd64) -> generated/littlefs.bin + firmware zip
PORT=/dev/ttyACM0 scripts/flash.sh    # x86-64 Linux host with the unit on USB; see the script header
scripts/restore-stock.sh              # back to Hey Jarvis (then build + flash again)
```

Options: `fetch-model.sh --cutoff 0.95` lowers the detection threshold in the flashed copy. `prepare.sh --rename` patches the C906 loader to use `oye_pepa.*` filenames instead of hijacking the Jarvis slot. `prepare.sh --label` patches `wyoming.c` so the satellite advertises "oye pepa". Start without either.

## Before flashing

- **Where to flash from.** The Bouffalo flash tool in the SDK is `bflb_iot_tool-ubuntu`, a Linux binary, and the YoC build also calls it. Build and flash on an x86-64 Linux host. Docker Desktop on a Mac cannot pass the USB serial port through. Not verified: whether Bouffalo's macOS Dev Cube could write only the media partition (offset `0xEE8000`, size `0xB8000`) from `littlefs.bin`.
- **Bootloader mode.** Power off, hold the center ring button, power on, start the flash within seconds.
- **`full` matters.** `flash.sh` without `full` flashes firmware only, so the model would not change. `scripts/flash.sh` always passes it.
- **Guest room.** The unit is slated for the guest room next week. Flashing takes it offline, so do this first, and keep `restore-stock.sh` ready.

## Unknowns

- Model size is unknown (workspace could not download it). Media partition is 753,664 bytes; stock files use about 110 KB.
- `tensor_arena_size` is 30000 for Oye Pepa! vs 22860 for Jarvis. Probably fits the C906; not checked. If the model fails to load, the serial console prints `fopen failed`, `Failed to init model: N`, or similar (see `alg_dummy.c`).
- Cutoff 0.99 is strict. The July deployment record already treats false-rejects as the real problem. Lower it here with `--cutoff`; no retrain needed.
- Licensing and provenance of the trained model are still open in the Notion deployment record.

## Layout

```
scripts/   fetch-model, prepare, build, flash, restore-stock
patches/   optional patches against the SDK submodules (verified to apply to the pinned commits)
models/    downloaded model + stock backup (gitignored)
docs/      how-it-works.md, bench-log.md (append-only)
vendor/    pinned SDK checkout (gitignored)
```

Pinned SDK: `96197109949da77da3617817714c8dc05108f390` (submodules: c906 `455aeb7`, e907 `589cd99`, microwakeword-c `8d27a18`).
