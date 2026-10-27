class_name TutorialStep
extends Resource
## One step of a guided ride (Plan Phase 2 / test suite phase 11). Pure data: the
## TutorialDirector reads it, so the script can be re-ordered or re-worded without code.
## Later the same shape becomes a mission stage (Plan Phase 3).

## Stable id, used for analytics (tutorial_step_completed) and saves.
@export var id: String = ""
## Translation key of the mentor's line (subtitle). Voice file is optional.
@export var line_key: String = ""
## res:// path of the recorded line (Tamil/English). Missing file = subtitles only.
@export var voice_path: String = ""
## TouchHUD control to spotlight: a button name ("KickStart", "Accelerate", "Horn"...),
## "minimap", or "" for none.
@export var highlight: String = ""
## What finishes the step:
##   engine_restarted · speed · stop_marker · signalled_turn · horn · haggle_started ·
##   haggle_accepted · near_destination · ride_completed · timer
@export var complete_on: String = "timer"
## Numbers for complete_on (kmh, ahead_m, radius_m, seconds, remaining_m, archetype, trip_min_m...).
@export var params: Dictionary = {}
## Re-show the line plus this nudge if the step is still open after hint_after_s.
@export var hint_key: String = ""
@export var hint_after_s: float = 12.0
## On reload mid-tutorial, restart from this step index (-1 = this step). Ride steps go back
## to the pick-up, because the scripted rider is not saved.
@export var resume_to: int = -1
