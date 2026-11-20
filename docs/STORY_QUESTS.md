# Story quests: voiced cutscenes, searching and talking in the world

Owner request (Nov 2026): side quests were "all button clicks". In Red Kite the game said "look
around for a boy" and a button finished the step without the boy ever being there. Make side quests
play in the world like RDR2: forced cutscenes with the camera inside the auto, real people and
things to find, and voiced dialogue that stays in sync with the scenes.

"The Little Red Kite" (`sq_007`, content version 3) was the first quest built this way;
"Paati Knows the Way" (`sq_004`, content version 3) is the second, and the first with a rider.

## How a story quest is built

| Piece | File | What it does |
|---|---|---|
| Stage kinds | `data/missions/MissionStage.gd` | `cutscene` (plays a scene, controls locked), `ask` (stop beside a person: they talk, no button), `spot` (a search: find the thing on screen and tap it), plus `next_id` (jump forward) |
| Story data | `data/missions/QuestStoryData.gd`, `data/missions/stories/sq_007_story.tres` | Cast, props, cutscene beats, lines said while driving, speakers |
| Content builders | `tools/quests/build_sq07_story.py`, `build_sq04_story.py` (+ `story_tres.py`, the shared writer) | Write `sq_NNN.tres` and its story from Python (positions are real spots read off `data/world`) |
| Director | `scripts/missions/MissionDirector.gd` | Still owns all progress; checks every "found it" and "scene done" |
| Player | `scripts/missions/QuestStory.gd` (+ `QuestActor.gd`, `KiteProp.gd`) | Camera, letterbox, subtitles, voices, people, props, taps |
| Rider | `scripts/missions/QuestRider.gd` | The quest's own passenger (`MissionDef.rider_model`): `story_out` / `story_walk` / `story_in` / `story_show` for scenes |
| Voices | `assets/audio/voice/sq0N/<line>_<en/ta>.ogg` | Made by Actions -> Generate quest voices (`docs/voice/README.md`) |
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

## Riders in a story (`"rider"` beats)

A quest with `MissionDef.rider_model` has its passenger in the auto (QuestRider). A beat can move her:
`"rider": {"out": mark, "face": look}` (she climbs out on the kerb side and walks to the mark),
`{"walk": mark}`, `{"in": true}` (back to the door and in), `{"show": false}`, and `"now": true` for a
cut. `"wait": "rider"` waits until she has stopped walking or climbing; looks and eyes take `"rider"`.

* While a scene has her out (`QuestRider.story_hold`) she doesn't walk back to the auto by herself; when
  the scene ends or is skipped she follows the fare rules again (stopped within 9 m: she gets in).
  Skip applies every remaining rider beat at once, so she ends up wherever the scene would leave her.
* Her stops still only count while she is aboard (`MissionDirector.rider_missing()`), so a scene that
  lets her out must put her back in (`"in"`) before the next drive.
* Frame a seated rider with `{"from": "rider", "dist": 2.9, "side": -1.1}` (lens ahead on the kerb
  side, past the driver). Once she stands beside the auto, use marks relative to the auto: framed
  "from" her, a positive `dist` points through the auto and puts the lens inside the canopy.
* At the flower stall the shop front (QuestPlaces) has no collider and fills the kerb: keep cameras
  on the road there. Shop fronts and tree canopies are not in any camera check.

## Paati Knows the Way

1. **Intro** (cutscene): Kamakshi Paati gets up from her thinnai and comes to the auto. She came from
   Kumbakonam yesterday, went to the temple and can't find her granddaughter Meena's new house. No phone,
   no address: only the jasmine stall she remembers. She gets in after "hop in, Paati".
2. **Ask** Valli at her flower stall on Venkatesa Agraharam Road (stop beside her). A watchman on the way
   jokes that there are a hundred new flats on this road.
3. **Valli remembers** her (and her forgotten change) and comes over to the auto. Paati asked about the
   temple tank and the market: the choice in the letterbox. The market gets "no bag in my hand, it was
   the tank".
4. **Ask** the old sundal seller on South Mada Street by the Kapaleeshwarar tank: a girl in a green
   churidar was asking everyone for her Paati and went toward the temple.
5. **Search** East Tank Square Street: Meena is the only green churidar (a green saree, a girl in a
   pavadai, an office coat and a violet saree are look-alikes). Tap her. Everyone wears their model's
   own colours: in the city a PaintSwap repaint can silently fail (see AGENTS.md), and a search must
   never depend on it.
6. **Reunion**: Paati gets out; Meena cries and scolds; "the temple hasn't changed, only the roads have";
   their house is two minutes away. Both get in.
7. **Ride home gently** (comfort bar) to the green gate on RK Mutt Road corner.
8. **Home**: take the fare (Rs 180) or refuse it (+40 XP); Paati gives you Kumbakonam athirasam either way.

Tests: `tests/run_story_quest_tests.tscn` plays it too (both choices, skips, the rider out and in).
`SHOT_QUEST=sq_004` in `tests/shot_story.tscn` renders its scenes.
