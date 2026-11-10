# How the PineVoice wake word works

Read from the SDK at commit `96197109949da77da3617817714c8dc05108f390` on 2026-11-09. Paths are relative to the SDK root.

## Two cores, two firmwares

- `solutions/pinevoice_fw_e907`: main core (M0). Wi-Fi, BT, audio, Wyoming satellite, playback of tones.
- `solutions/pinevoice_fw_c906`: DSP core (D0). Only job today is wake-word detection.

The BL606P has 32 MiB pSRAM, 16 MiB flash. The C906 reads mic PCM from the E907 through `epm_pcm_read` and runs microWakeWord (`components/microwakeword`, a C port of the ESPHome component built on `tflite_micro`).

## Where the model comes from

`solutions/pinevoice_fw_c906/app/dummy/alg_dummy.c`:

- `load_model_json()` opens `/mnt/hey_jarvis.json` and requires four numbers under `micro`: `probability_cutoff`, `feature_step_size`, `sliding_window_size`, `tensor_arena_size`. Anything missing and it returns an error.
- `load_model()` opens `/mnt/hey_jarvis.tflite` and reads it into a malloc'd buffer.
- `load_default_model()` calls `mww_streaming_model_init(model, buf, cutoff * 255, window, arena)`. The cutoff is stored as a uint8, so 0.99 becomes 252.
- The filenames are hard-coded. The `model` and `wake_word` fields in the JSON are not used by this loader.

`/mnt` is a littlefs image: `boards/bl606p_pinevoice_e907/script/aft_build.sh` runs `lfs ... -c data -b 4096 -s 753664` over `solutions/pinevoice_fw_e907/data/` and writes `generated/littlefs.bin`. 753664 = `0xB8000`, the `media` partition in `boards/bl606p_pinevoice_e907/configs/partition.toml` (address `0xEE8000`).

`solutions/pinevoice_fw_e907/data/mnt/` currently holds `hey_jarvis.{json,tflite}` (52,272 bytes, Apache 2.0 from linux-voice-assistant per the LICENSES file), five `.opus` tones (wifi provisioning, wifi disconnected, `wsat-is-disconnected`), and `LICENSES`.

## Tensor arena

The arena is the working memory TFLite Micro needs to run the model. Getting its size wrong is the one manifest error that fails silently on this device.

- `alg_dummy.c` passes `micro.tensor_arena_size` to `mww_streaming_model_init()`. `StreamingModel::load()` (`components/microwakeword/src/mww_streaming_model.cpp`) mallocs exactly that many bytes. There is no probing and no retry.
- If it is too small, `AllocateTensors()` fails. The C906 console prints `Failed to init model: -2` and `Ret3: -3`, and wake-word detection stays off until the next boot. The E907 is never told, and the center button still works.
- Current ESPHome (`micro_wake_word/streaming_model.cpp` on the dev branch, read 2026-11-10) tries the manifest size, then 1.5x and 2x, and then shrinks to what the model really uses. A manifest that is too small therefore works on ESPHome devices and fails here. Whether the ESPHome builds on the Satellite1 and Voice PE include that probe was not checked.

Measured with `scripts/probe-arena.sh` (the SDK's own `tflite_micro`, the same 20 ops, variable arena and checks as the firmware, built on a 64-bit host):

| Model | Size | Minimum arena | Manifest value | Flashed value |
|---|---|---|---|---|
| Oye Pepa! v2 (`3bc32c76…`) | 137,984 | 42,896 | 30,000 | 48,000 |
| Hey Jarvis (stock, `21a7976a…`) | 52,272 | 19,392 | 22,860 | 22,860 |

`config/arena.tsv` holds these numbers. `scripts/fetch-model.sh` writes the "flashed" value into the copy that gets built and refuses an `--arena` below the minimum.

- **Why Oye Pepa! needs more.** It is the Okay Nabu network layout with the filter counts doubled (64/128 instead of 32/64). It also runs every 20 ms (2 feature slices per inference) instead of every 30 ms. That gives about 81k weights against 21.6k for Jarvis. The size comes from the training configuration, not from the length of the phrase.
- **Use a 64-bit host.** The C906 is RV64. A 32-bit build of the probe needs less (38,852 bytes for Oye Pepa!) because pointers are smaller, and would undercount.
- **Not verified on the device.** Whether the C906 heap has room for the 48 KB arena plus the 138 KB model buffer (the C906 image is linked into a 4 MiB pSRAM region, `boards/bl606p_pinevoice_c906/gcc_flash_c906.ld`). How long one inference takes on the C906. On the host it is about 3.5x Jarvis per inference, and about 5x per second of audio because it also runs more often.

## The Wyoming side

`solutions/pinevoice_fw_e907/app/src/wyoming/wyoming.c:57-66` declares a `wsat_wake` component with the name string `"hey jarvis"`, registered via `wsat_wake_set(&wake)`. This is what the satellite advertises to HA. Whether HA does anything with it was not checked. Detection itself triggers `wsat_wake_detection()` (line 29), same call the center button makes (`app_key_msg.c:114`).

## Flashing

`solutions/pinevoice_fw_e907/flash.sh <cli> <full>`:

- Always flashes `yoc_rfpa.bin` with `partition.toml`.
- Only with `full` also flashes `generated/littlefs.bin` (media) and the mfg image.
- Picks `PV_TTY` as the first `/dev/tty*` character device, so pin the port yourself (`scripts/flash.sh` does).
- Uses `tools/flashtool/bflb_iot_tool-ubuntu` (Linux x86-64).

## Reading the flash (rollback image)

Verified on 2026-11-09 with a 4 KB read-only test. The full dump itself is covered by `scripts/dump-flash.sh`; its result goes in `bench-log.md`.

- Bootloader mode shows up on the host as USB `ffff:ffff CherryUSB CherryUSB_CDC_DEMO` (serial `2022123456`), i.e. `/dev/ttyACM0`. A power-only cable shows nothing at all; use a data cable.
- Command: `bflb_iot_tool-ubuntu --chipname=bl606p --interface=uart --port=/dev/ttyACM0 --baudrate=2000000 --read --start=0x0 --end=0xFFF`, run from `tools/flashtool/` after copying `boards/bl606p_pinevoice_e907/configs/eflash_loader_cfg.ini` into `chips/bl606p/eflash_loader/`.
- The handshake reports MAC `222222222222` (looks like a placeholder; not checked against other units, so do not treat it as an identity), flash JEDEC id `ef601880`, size `0x01000000`.
- **`--outdir` does not control where the data goes.** The tool writes `./flash.bin` in its current directory and uses `--outdir` only for generated config files. `scripts/dump-flash.sh` runs it in the flashtool folder and moves the result.
- **`--end` is inclusive.** `--start=0x0 --end=0xFFF` returned exactly 4096 bytes. The full range is `--end=0xFFFFFF` (16,777,216 bytes).
- The first 4 KB begins `BFNP` / `FCFG` / `PCFG`, the Bouffalo boot header, so the read returns real flash content.
- The tool **resets the CPU after every read** and then logs `Error: [Errno 5] Input/output error`. Exit code is 0 and it prints `[All Success]`, so the error is cosmetic. Every new attempt needs bootloader mode again (power off, hold center button, power on). The port may still be listed by the host after the reset; do not use "port exists" as proof that the unit is in bootloader mode.
- The dump can contain Wi-Fi credentials and per-unit data. Keep it out of git.
- **Not verified:** writing a dump back. The same tool has `--single`, `--addr` and `--firmware`/`--media`/`--mfg` options, but a full-image restore has not been tried. Until it is, the dump protects the data, not the procedure. Reflashing via the SDK (`flash.sh ... full`) from a stock build is the other way back.

## Checking the built image

`generated/littlefs.bin` (753,664 bytes) is the media partition image. A proper unpack needs a littlefs reader (for example the `littlefs-python` package with block size 4096, 184 blocks); mm2010 had no pip when this was written, so that check has not been done.

What was done instead, on 2026-11-09:

- `data/mnt/hey_jarvis.tflite` is byte-identical to `models/oye_pepa.tflite`, and `data/mnt/hey_jarvis.json` holds the Oye Pepa! manifest (cutoff 0.99, window 5, step 10, arena 30000).
- The 388-byte JSON appears whole inside `littlefs.bin`.
- littlefs stores big files in 4096-byte blocks with a few pointer bytes at the start of each, so the `.tflite` is not contiguous in the image. Sampling 64-byte windows of the model every 500 bytes found 272 of 275 in the image. The stock Jarvis model matched 22 of 104, which I read as bytes shared between the two models, not as Jarvis being present. This is evidence, not proof; the boot log is the real test.

## Upstream status

Pine64's software page says future firmware updates are expected to support custom MicroWakeWord-compatible models and that a PineVoice-specific model is planned. Until then this repo hand-swaps the files. Open issues on the SDK repo as of 2026-11-09: #2 (chime on wake word), #4 (AGC on mics), #5 (build without VS Code).

## Not verified

- Anything about how the loaded model performs. The model has never loaded on the unit: the 2026-11-09 flashes used the too-small arena (see docs/bench-log.md, 2026-11-10).
- Whether the C906 heap has room for the 48,000-byte arena plus the 137,984-byte model buffer (see "Tensor arena"). The manifest's 30000 is too small; that part is measured.
- Whether the unit's mute button cuts the mic electrically.
