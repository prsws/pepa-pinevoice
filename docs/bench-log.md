# Bench log

Append-only. Corrections go in a new entry, not in edits to an old one.

## 2026-11-09: arrival, HA integration, plan

**State found (read from prod HA, no changes made).**
- Wyoming config entry "PineVoice" at 192.168.15.103:10700, loaded; device in area guest_room.
- Entities: `assist_satellite.pinevoice`, `select.pinevoice_assistant` (PepaV6.1), `select.pinevoice_noise_suppression_level` (medium), `select.pinevoice_finished_speaking_detection` (default), `switch.pinevoice_mute` (off), `number.pinevoice_mic_volume` (5.5), `number.pinevoice_auto_gain` (0). No wake-word entity: detection is on the device.
- One "Unable to get info from 192.168.15.103:10700" error from the Wyoming coordinator at about 12:21 local, during first poking.
- Satellite state history 12:20-12:29 local: several idle/responding cycles, then one listening -> processing -> idle in about 12 s with no responding state.

**José's observation, 13:17.** Works, apparently through the hardware button only. Stock wake word is "Hey Jarvis"; the Pine64 docs mention no other.

**Decision.** No detailed acceptance testing. The unit goes in the guest room for his son's visit the following week as the real-use test. First goal: get Oye Pepa! onto it.

**Findings.** Model is loaded at runtime from littlefs, not compiled in (docs/how-it-works.md). Existing Oye Pepa! manifest (served from ai-for-aging.org) has all four fields the loader needs: cutoff 0.99, window 5, step 10, arena 30000.

**Next.** fetch-model, prepare, build, flash. Then: say "Oye Pepa", watch `assist_satellite.pinevoice` states in HA, and check the serial console on boot for the model-load lines.

**Prior context.** The July deployment record (Notion, "microWakeWord — Oye Pepa! Deployment Record (2026-07-28)") covers training, the Satellite1 and Voice PE deployments, and the pending bed test. PineVoice would be a fourth unit; its entry in that record is not written yet.

## 2026-11-09 (evening): flash tool proven, rollback image planned

**Host.** mm2010 (Debian 13, x86-64) at 192.168.10.4, flash tool from the pinned SDK checkout. The first cable was power-only and showed nothing on USB. With a known-good data cable the unit enumerates in bootloader mode as `ffff:ffff CherryUSB CDC` on `/dev/ttyACM0`.

**Read-only test, 18:15 local.** Read 0x0-0xFFF. Handshake OK, flash JEDEC `ef601880`, size `0x01000000`, `Read 4096/4096`, `[All Success]`, exit 0, then the CPU reset and a cosmetic `[Errno 5]`. Output was `flash.bin` (4096 bytes, starts with the `BFNP` boot header) in the tool's working directory, not in `--outdir`. Details in docs/how-it-works.md, "Reading the flash".

**Correction to the earlier plan.** I first looked for the read data in `--outdir` and found nothing; it was in `flashtool/flash.bin`. The tool also resets the chip after each read, so every attempt needs bootloader mode again.

**State.** No rollback image yet. `scripts/dump-flash.sh` written (read-only, keeps the file only if it is exactly 16,777,216 bytes). Not run at the time of this entry. Nothing has been flashed. The Docker build of the Oye Pepa! image was still compiling.

**Next.** Dump twice and compare sha256, then check `littlefs.bin` contains the Oye Pepa! files, then flash only with José's go-ahead.

**Addendum, 18:24 local.** The Docker build finished. Outputs: `firmware_9619710994.zip` (1,658,956 bytes) and `generated/littlefs.bin` (753,664 bytes, the size of the media partition). Whether the Oye Pepa! files are inside `littlefs.bin` has not been checked yet. This supersedes "still compiling" above.

## 2026-11-09 19:08-19:14: rollback image taken

Two full read-only dumps of the unit's flash (0x000000-0xFFFFFF), each 16,777,216 bytes, taken one power-cycle apart (19:08:30 and 19:13:46, about 6 s each). Both have sha256 `cd4d6b394fcaa8893b52595898ad8ea8d7d17e09e34c6f82e7bc0445bc91ae2b` and `cmp` reports them identical. Kept on mm2010 as `~/pinevoice-backup/pinevoice-full-20261109-190830.bin` and `...-191346.bin` (not in the repo; may contain Wi-Fi credentials).

Contents checked by byte search: `BFNP` boot header at 0x0; littlefs in the media partition at 0xEE8000 with stock `hey_jarvis.json` (0xF1F748) and `hey_jarvis.tflite` (0xF1F248) and no `oye_pepa` files; the string "hey jarvis" at 0x1E51F4. This is the stock state.

An earlier attempt at 19:06 failed with `BFLB IMG LOAD SHAKEHAND FAIL` because the unit was not in bootloader mode even though `/dev/ttyACM0` was listed. Nothing was written to the unit.

Still not verified: restoring the dump onto the unit. Nothing has been flashed.

**Addendum, 19:16 local: built image checked.** `data/mnt/hey_jarvis.tflite` equals `models/oye_pepa.tflite` byte for byte, and the JSON in the image is the Oye Pepa! manifest. Sampling 64-byte windows of the model against `generated/littlefs.bin` found 272 of 275; the stock Jarvis model matched 22 of 104 (probably bytes the two models share). Not a full unpack: mm2010 has no pip, so no littlefs reader was available. A first attempt to count the model as a contiguous run failed, which is expected because littlefs splits files across blocks with pointer bytes. Open decision before flashing: keep cutoff 0.99 or rebuild at 0.95. Nothing flashed.

## 2026-11-09 19:46: rebuild at cutoff 0.97

José chose 0.97 (between the trained 0.99 and the 0.95 I suggested). Done with `fetch-model.sh --cutoff 0.97`, `prepare.sh`, `build.sh`; build finished 19:46 (about 19 minutes, a full recompile each time).

- `generated/littlefs.bin`: 753,664 bytes, sha256 starts `1522d4c68cc461e1` (the 0.99 image started `05ca445538b29946`). `firmware_9619710994.zip`: 1,658,959 bytes.
- Compared with the 0.99 image: 411 bytes differ, all in three 4 KB blocks (0, 55, 100): the filesystem metadata and the JSON block.
- `.tflite` unchanged (sha256 starts `3bc32c76de0841b4`); 272 of 275 sampled model windows present. The JSON in the image says `"probability_cutoff": 0.97` and the `0.99` text is gone.
- `fetch-model.sh --cutoff` rewrites the manifest with `json.dumps`, so the `author` field now holds `\u00e9` escapes instead of a literal e-acute and the file is indented. The loader only reads the four numeric `micro` fields, so this should not matter; the boot log will confirm.

Nothing flashed yet.

## 2026-11-09 20:04-20:49: flashed, wake word never fires

**Flash 1, 20:06 (cutoff 0.97).** Firmware, partition table, mfg and media written and each verified on the device (media sha256 `1522d4c6...`). The unit rebooted, rejoined Wi-Fi by itself (no reprovisioning), answered ping, port 10700 open, `assist_satellite.pinevoice` idle. José: 5 attempts at "Oye Pepa" with simple commands, no response of any kind. HA logbook: nothing.

**Button check, 20:19.** Center button still starts a full pipeline (listening, processing, responding, idle in HA). The flash did not break the speech path.

**Flash 2, 20:21 (probe, cutoff 0.5).** Only `littlefs.bin` regenerated (`product lfs` in the SDK container: seconds instead of a 19-minute rebuild); media sha256 `9c2f0352...` verified. Still no trigger of any kind; HA shows only the button session.

**Key fact from José.** Stock "Hey Jarvis" never worked either, on the factory firmware, right after unboxing. The HA device page has no wake-word section; that is expected for a Wyoming satellite that detects on the device (Satellite1 and Voice PE expose wake-word selects because they run ESPHome). In `wyoming.c` a detection either starts a pipeline (HA logbook shows listening) or, if HA is not connected, plays `wsat-is-disconnected.opus`. Neither happened, so the device is not detecting anything. Some other `wsat_wake_detection()` errors would be silent; not ruled out.

**Stock-Jarvis reflash: prepared, then dropped.** `restore-stock.sh` plus an lfs repack put the stock files back in the image (103/104 sampled windows), and a flash watcher was armed at 20:26. Disarmed at 20:41 without flashing, because Jarvis is already known to fail on this unit. The unit is still on the 0.5 Oye Pepa image; the build tree now holds the stock model. Gotcha: `pkill -f <script>` run over the remote shell also kills that shell when its own command line contains the script name.

**Console, 20:41-20:45.** 200 s capture of the USB console (2,000,000 baud) while José said "Oye Pepa", "Hey Jarvis", talked, and pressed the button. The log is flooded and garbled by one warning repeated continuously: `codec_input.c _aui_recv 133`. That is the `MSP_LOGW` in `components/multimedia/xcodec/src/bl606p/codec/codec_input.c` when `mringbuffer_put_index()` returns <= 0, i.e. a mic capture ring buffer is full and nobody is draining it. It also appears in both post-flash boot captures, within the first ~15 KB. No "WAKE UP!!!" line even for the button press, so debug logs are off (package.sh comments out CONFIG_DEBUG) or lost in the flood. Not known whether the factory firmware shows the same warning; its console was never captured.

**Upstream.** SDK issue #2: other owners say the wake word works for them (LEDs react). Issue #4: mic gain is a fixed 27 dB in `boards/bl606p_pinevoice_e907/src/audio/board_audio.h`; the maintainer says there is AGC inside the wake-word processing only. No issue mentions a unit that never wakes or the `_aui_recv` warning.

**Reading.** Not the Oye Pepa model and not the HA configuration. Leading suspects: this unit's audio capture path (the full ring buffer), or neither model reaching threshold on this unit's mics. Not proven.

## 2026-11-10: why Oye Pepa! never loaded

**Finding.** The PineVoice firmware mallocs exactly `micro.tensor_arena_size` and does not retry. Oye Pepa! needs at least 42,896 bytes; the manifest from ai-for-aging.org says 30000. So the model failed to load on every flash on 2026-11-09 (cutoff 0.97 and 0.5 alike), and those tests say nothing about sensitivity. ESPHome grows the arena itself, which is why the same manifest works on the other satellites.

**How it was measured.** The SDK's `tflite_micro` and the firmware's load path, rebuilt on a 64-bit host (`tools/arena-probe`, `scripts/probe-arena.sh`). The model was read with its weights zeroed, which does not change the memory plan; its hash matched the flashed file (`3bc32c76…`). Stock Hey Jarvis: minimum 19,392 against its manifest's 22,860, so Jarvis does load. Details in docs/how-it-works.md, "Tensor arena".

**Change.** `fetch-model.sh` now writes 48000 (minimum + about 10%) into the flashed copy, from `config/arena.tsv`.

**Still open.** Stock Hey Jarvis never woke this unit either, with an arena that fits. That is a separate problem and is tracked separately. Not verified on the device: C906 heap headroom for the bigger arena and model, and inference time.
