# Quest voice lines

Voiced dialogue is generated with ElevenLabs (Eleven v3) by **Actions → Generate quest voices**.

1. Write a script here as `SQ<nn>_<Name>_Voice_Script.md`. Each voiced line is one bullet:
   `- sq07_l01 Lakshmi: [tags] Tamil text / [tags] English text`. Text in `[brackets]` is
   acting direction for v3 and is not spoken. A note in round brackets after the speaker
   (`Karthik (at Marina):`) is ignored.
2. Every speaker needs a profile in `tools/voice/cast.json`. The hero is always `Driver`:
   his voice is locked, so he sounds the same in every quest.
3. Push. The workflow picks a Tamil voice for any new speaker (`voices.json`), voices every
   line that has no file yet and commits `assets/audio/voice/<quest>/<id>_<ta|en>.ogg`
   (mono Vorbis, small). To redo lines, run it by hand with their ids in "only".
4. To change a character's voice, delete their entry in `tools/voice/voices.json` and push.

**Licence:** the ElevenLabs free plan is non-commercial only. Regenerate every line on a paid
plan (Starter or above) before any build with ads or purchases goes to the Play Store.
