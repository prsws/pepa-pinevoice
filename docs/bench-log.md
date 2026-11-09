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
