# Namma Auto — dialogue and voice production inventory

Snapshot: `translations/ui.csv` from `feature/chennai-spoken-tamil-localization` on 14 November 2026. This is a **complete inventory of all 809 current localization keys**, not a guarantee that every hard-coded runtime string or authored quest resource is captured. The CSV includes exact English and Tamil values, candidate speaker, priority classification and suggested OGG path.

## Counts

- other_ui: 340
- ambient_voice_candidate: 6
- tutorial_ui: 14
- mentor_voice_candidate: 21
- quest_system_ui: 63
- quest_objective_or_ui: 268
- quest_voice_review: 63
- rider_system_ui: 9
- rider_voice_candidate: 25

**Voice immediately**: mentor voice candidates, five passenger archetype dialogue variants, and warning speech where context supports a speaker.

**Review first**: quest titles/briefs/choices are mostly instructions, not necessarily conversations. Assign actual characters and speakers before synthesizing.

**Do not voice by default**: menu buttons, status labels, achievements, road signs, technical instructions and other UI entries.

## Sources verified

- `translations/ui.csv` — English and Tamil localization table.
- `data/tutorial/first_ride.tres` — ten tutorial steps each points to `line_key` and optional `hint_key`.
- `scripts/tutorial/TutorialDirector.gd` — currently supports a tutorial `voice_path` and an `AudioStreamPlayer`.
- `scripts/passengers/SavariManager.gd` — five recurring passenger archetypes: `it_commuter`, `tnagar_shopper`, `tourist`, `monsoon_rider`, `college_student`.

## Technical implementation plan

1. Introduce character voice profiles (stable IDs, locale, speaking pace, emotion). Do **not** imitate real people without permission.
2. Add per-line voice asset IDs mapped to localization keys. Keep text as fallback if OGG asset is missing.
3. Generate English/Tamil separately, with Tamil-script input and native-speaker review. Normalize text for TTS without altering displayed subtitles.
4. Export Ogg **Vorbis** mono 24 kHz or 44.1 kHz at ~48–80 kbps for speech. Use Godot audio import for packaged assets; make sure Ogg is Vorbis, not Opus.
5. On each dialogue event: stop/fade preceding voice, play matching locale clip, preserve captions, respect mute and separate speech volume; unload/stream to avoid memory spikes.
6. Add validation: all referenced IDs exist, voice clip can decode, no mismatch between text/voice locale, no broken APK export, no clipped dialogue on transitions.
7. Start with Murugan Anna and one passenger, device-test before batch production.

**Important:** The CSV classification is based on key naming, not a full runtime call-graph audit. Hard-coded dialogue, conditional quest choices, and dynamic interpolation require a second source-code/resource sweep before declaring the inventory exhaustive.
