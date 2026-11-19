# Story quests: voiced cutscenes, searching and talking in the world

Owner request (Nov 2026): side quests were "all button clicks". In Red Kite the game said "look
around for a boy" and a button finished the step without the boy ever being there. Make side quests
play in the world like RDR2: forced cutscenes with the camera inside the auto, real people and
things to find, and voiced dialogue that stays in sync with the scenes.

"The Little Red Kite" (`sq_007`, content version 3) is the first quest built this way.

## How a story quest is built

| Piece | File | What it does |
|---|---|---|
| Stage kinds | `data/missions/MissionStage.gd` | `cutscene` (plays a scene, controls locked), `ask` (stop beside a person: they talk, no button), `spot` (a search: find the thing on screen and tap it), plus `next_id` (jump forward) |
| Story data | `data/missions/QuestStoryData.gd`, `data/missions/stories/sq_007_story.tres` | Cast, props, cutscene beats, lines said while driving, speakers |
| Content builder | `tools/quests/build_sq07_story.py` | Writes `sq_007.tres` and its story from Python (positions are real Santhome / Marina spots) |
| Director | `scripts/missions/MissionDirector.gd` | Still owns all progress; checks every "found it" and "scene done" |
| Player | `scripts/missions/QuestStory.gd` (+ `QuestActor.gd`, `KiteProp.gd`) | Camera, letterbox, subtitles, voices, people, props, taps |
| Voices | `assets/audio/voice/sq07/<line>_<en/ta>.ogg` | Made by Actions -> Generate quest voices (`docs/voice/README.md`) |
| Subtitles | `translations/ui.csv` `VO_<LINE>`, `VO_SPK_*` | English and Tamil |

## Rules

* **No button ever moves a story forward.** A stage ends because something happened in the world:
  the auto stopped beside someone, the player tapped the thing they were looking for, a scene ended.
* **The director decides.** `QuestStory` only reports `mission_spot_requested` (the tap hit the
  thing) and `mission_cutscene_finished`. `MissionDirector.spot()` checks the auto really is
  within `spot_range_m` and at or below `spot_max_kmh`.
* **A tap counts only if you could see it**: in front of the camera, close enough on screen, in
  range, slow enough and not behind a building, car or tree trunk (physics ray). Tapping a
  look-alike (`decoy_for`) gets the "not that one" line; tapping empty sky does nothing.
  Taps above the top HUD row or over the controls (`TAP_TOP_FRAC`, `TAP_BOTTOM_FRAC`) are ignored.
* **Searches are circles, not pins.** GPS leads to the circle (`target`, `radius_m`) and goes quiet
  inside it; after `shrink_after_s` the circle closes in on the thing but never centres on it.
  The mini-map draws it in the pin batch (no extra draw call).
* **Cutscenes lock the controls**: the auto is frozen, `ui_modal_changed` hides the HUDs, the story
  camera takes over, and everything comes back when the scene chain ends, is skipped, or the quest
  ends any other way. A held last beat (`"hold": true`) keeps the scene open for the next
  dialogue stage and shows its choices in the letterbox.
* **Dialogue is timed from the voice files**, not the audio driver: a beat lasts at least its line,
  lines never overlap, and lines while driving queue one after another. Subtitles show the speaker.
* **Camera marks are relative to the auto** (`[right, up, forward]`, kerb side is left) or framed on
  a person or prop (`{"from": "role:karthik", "dist", "up", "side"}`), so a scene plays wherever the
  player stopped. Every camera position is checked: never inside a building, never behind a parked
  car, bus or tree trunk; otherwise the shot is mirrored, moved closer or lifted.
* **People who are not needed walk off** and are freed once the player is 70 m away; nobody pops
  out of existence in view.
* **Sarees never sit**, so Lakshmi rides along as a voice from the back seat (she climbs in and out
  in the scenes). There is no child model yet: Karthik and the beach kids are the street-people
  models scaled down and repainted (`PaintSwap`). A proper boy model is a later art task.

## The Little Red Kite

1. **Intro** (cutscene, driver's eye): a red kite swoops across the windscreen, Lakshmi runs up:
   her son Karthik chased it. She gets in.
2. **Ask** the tea stall man on Santhome High Road (stop beside him). A flower seller on the way gives
   a wrong lead if you stop by her.
3. **Search** near Santhome Church for the kite: it is caught on the EB wire over Sullivan Street.
   A blue kite on Rosary Church Road is the wrong one. Tap the red kite.
4. **Children** run up: big boys cut his string; he ran to the beach.
5. **Search** the sand off Foreshore Estate Link: six children, some flying kites. Karthik is the
   only blue shirt without a kite. Tap him.
6. **Reunion**, then the choice in the letterbox: "The kite's gone, let's go home" or "I know where
   your kite is!"
7. Kite branch: **park right under the kite**; Karthik climbs on the roof and takes it.
8. **Ride home gently** (comfort bar; Lakshmi shouts if you brake hard or crash; Karthik giggles over
   speed breakers).
9. **Home**: take the fare (Rs 220) or refuse it (+40 XP respect).

Tests: `tests/run_story_quest_tests.tscn` plays the whole quest with the real auto, rig, director and
story player (both branches, skip, abandon, taps from too far / too fast / on decoys, voices and
subtitles in both languages). `tests/shot_story.tscn` renders every scene in the city (dev only).
