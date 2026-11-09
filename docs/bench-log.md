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
