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

## The Wyoming side

`solutions/pinevoice_fw_e907/app/src/wyoming/wyoming.c:57-66` declares a `wsat_wake` component with the name string `"hey jarvis"`, registered via `wsat_wake_set(&wake)`. This is what the satellite advertises to HA. Whether HA does anything with it was not checked. Detection itself triggers `wsat_wake_detection()` (line 29), same call the center button makes (`app_key_msg.c:114`).

## Flashing

`solutions/pinevoice_fw_e907/flash.sh <cli> <full>`:

- Always flashes `yoc_rfpa.bin` with `partition.toml`.
- Only with `full` also flashes `generated/littlefs.bin` (media) and the mfg image.
- Picks `PV_TTY` as the first `/dev/tty*` character device, so pin the port yourself (`scripts/flash.sh` does).
- Uses `tools/flashtool/bflb_iot_tool-ubuntu` (Linux x86-64).

## Upstream status

Pine64's software page says future firmware updates are expected to support custom MicroWakeWord-compatible models and that a PineVoice-specific model is planned. Until then this repo hand-swaps the files. Open issues on the SDK repo as of 2026-11-09: #2 (chime on wake word), #4 (AGC on mics), #5 (build without VS Code).

## Not verified

- Anything about how the loaded model performs. Nothing has been built or flashed.
- Whether the C906 has memory for a 30000-byte arena plus the model buffer. Jarvis needs 22860.
- Whether the unit's mute button cuts the mic electrically.
