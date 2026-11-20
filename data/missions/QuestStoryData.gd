class_name QuestStoryData
extends Resource
## The voiced story of one side quest, played by scripts/missions/QuestStory.gd. Authoring data
## only: the mission's progress stays in MissionDirector. Marks are [right, up, forward] metres in
## the player auto's frame (its position, its flat heading) unless a key says "world".
##
## cast: role -> {"model", "scale", "paint" (Color, PaintSwap), "kite" (holds a flying kite),
##   "world" (Vector3 where they stand outside cutscenes), "face" (Vector3 world point),
##   "anim", "stages" (PackedStringArray: stages they stand in the world),
##   "decoy_for" (spot stage id: tapping them is a wrong guess), "line"/"reply" (voice ids spoken
##   when the auto stops within "near_m" of them during their stages, once), "stall" (QuestPlaceKit
##   kind beside them)}.
## props: id -> {"kind": "kite", "world": Vector3, "hang": Vector3 (string end), "stages": [...]}.
## cutscenes: id -> Array of beats; see QuestStory for the beat keys.
## barks: stage id -> {"enter": [...], "idle": [...], "idle_s": Vector2, "hint": [...],
##   "hint_after_s": float, "wrong": id, "found": id, "impact": id, "jolt": id, "near": id,
##   "near_m": float}.
## voice_dir holds <line>_<en|ta>.ogg; speakers maps a line's letter ("l" in sq07_l01), or a whole
## line id when two speakers share a letter, to the speaker's name key; every line has a subtitle key VO_<LINE> in translations/ui.csv.

@export var voice_dir: String = ""
@export var speakers: Dictionary = {}
@export var cast: Dictionary = {}
@export var props: Dictionary = {}
@export var cutscenes: Dictionary = {}
@export var barks: Dictionary = {}

## Speaker name key for a line id such as "sq07_l01" (the letter after the underscore).
func speaker_key(line: String) -> String:
	if speakers.has(line):
		return str(speakers[line])
	var parts: PackedStringArray = line.split("_")
	if parts.size() < 2 or parts[1].is_empty():
		return ""
	return str(speakers.get(parts[1].substr(0, 1), ""))

## The audio file for a line in a language ("en" / "ta"); falls back to English.
func voice_path(line: String, language: String) -> String:
	var path: String = "%s/%s_%s.ogg" % [voice_dir, line, language]
	if ResourceLoader.exists(path):
		return path
	path = "%s/%s_en.ogg" % [voice_dir, line]
	return path if ResourceLoader.exists(path) else ""

## Every voice line this story uses (cutscene beats, cast lines and barks), for checks.
func all_lines() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for id: String in cutscenes:
		for beat: Dictionary in cutscenes[id]:
			if beat.has("line"):
				out.append(str(beat["line"]))
	for role: String in cast:
		for key: String in ["line", "reply"]:
			if (cast[role] as Dictionary).has(key):
				out.append(str(cast[role][key]))
	for stage: String in barks:
		var b: Dictionary = barks[stage]
		for key: String in b:
			var v: Variant = b[key]
			if v is String and str(v).begins_with("sq"):
				out.append(str(v))
			elif v is Array or v is PackedStringArray:
				for item: Variant in v:
					if item is String and str(item).begins_with("sq"):
						out.append(str(item))
	return out
