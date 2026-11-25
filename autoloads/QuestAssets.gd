extends Node
## QuestAssets: loads a quest's rider model, cast models and voice lines on worker threads BEFORE
## the player gets there, so nothing is read from disk while driving up to a quest or during its
## cutscenes (Nov 25 device report: frame drops in the Paati quest; every voice line was a
## main-thread load() at the moment it was spoken, and her model loaded when the auto came within
## 140 m).
##
## QuestRider calls warm() for the nearest available quest within WARM_M (well before the rider
## appears), and MissionDirector's active quest stays warm until it ends. Quest code takes every
## resource through get_resource(path): a warmed one is instant; anything not warmed yet still
## loads directly (correct, just slower). Only the warm quest's files stay in memory.

## A model load still unfinished after this long is completed with a short blocking fetch
## (only outside cutscenes, while the player is still on the way). On a 2-core machine the
## worker pool starves: a GLB's own sub-loads wait for a free thread that never comes, and only
## the main thread's fetch finishes them (~40 ms then, against ~460 ms for a cold load()).
const STALL_S: float = 2.0

## Files still on a worker thread.
var pending: PackedStringArray = PackedStringArray()
## Seconds each pending file has been waiting.
var _waited: Dictionary = {}
## Loaded and held: path -> Resource.
var cache: Dictionary = {}
## The quest whose files are wanted now ("" = none).
var warm_id: String = ""
## Language the voice lines were warmed in (a language change re-warms).
var _language: String = ""
## A quest cutscene is playing: never block the main thread then.
var _cinematic: bool = false

func _ready() -> void:
	set_process(false)
	SignalBus.quest_cinematic_changed.connect(func(on: bool) -> void: _cinematic = on)

## Start loading everything quest `d` will need. Cheap to call repeatedly for the same quest.
func warm(d: MissionDef) -> void:
	if d == null:
		return
	var lang: String = _lang()
	if d.id == warm_id and lang == _language:
		return
	warm_id = d.id
	_language = lang
	var wanted: PackedStringArray = paths_for(d, lang)
	# Let go of the previous quest's files (they're only a few MB, but no point holding them).
	for path: String in cache.keys():
		if not wanted.has(path):
			cache.erase(path)
	# Voice lines first (small, needed soonest), then models, so a slow model never holds up a line.
	var ordered: PackedStringArray = PackedStringArray()
	for path: String in wanted:
		if path.ends_with(".ogg"):
			ordered.append(path)
	for path: String in wanted:
		if not path.ends_with(".ogg"):
			ordered.append(path)
	for path: String in ordered:
		if cache.has(path) or pending.has(path):
			continue
		if ResourceLoader.load_threaded_request(path) == OK:
			pending.append(path)
			_waited[path] = 0.0
	set_process(not pending.is_empty())

## Every file quest `d` loads while it plays: rider, cast models, voice lines in `lang`.
static func paths_for(d: MissionDef, lang: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if d.rider_model != "" and ResourceLoader.exists(d.rider_model):
		out.append(d.rider_model)
	if d.story != null:
		for role: String in d.story.cast:
			var c: Dictionary = d.story.cast[role]
			var model: String = str(c.get("model", ""))
			if model != "" and ResourceLoader.exists(model) and not out.has(model):
				out.append(model)
		for line: String in d.story.all_lines():
			var v: String = d.story.voice_path(line, lang)
			if v != "" and not out.has(v):
				out.append(v)
	return out

## The resource at `path`: from the warm cache when it is there, else loaded now.
func get_resource(path: String) -> Resource:
	if path == "":
		return null
	if cache.has(path):
		return cache[path] as Resource
	if pending.has(path) and ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_LOADED:
		_collect(path)
		return cache.get(path) as Resource
	return load(path)

func is_warm(path: String) -> bool:
	return cache.has(path)

func _process(delta: float) -> void:
	# At most a few hand-overs per frame: each is just taking a finished resource off its thread.
	var taken: int = 0
	var unstuck: bool = false
	var i: int = pending.size() - 1
	while i >= 0 and taken < 8:
		var path: String = pending[i]
		var status: int = ResourceLoader.load_threaded_get_status(path)
		_waited[path] = float(_waited.get(path, 0.0)) + delta
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			_collect(path)
			taken += 1
		elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			pending.remove_at(i)
			_waited.erase(path)
		elif not unstuck and float(_waited[path]) >= STALL_S and not _cinematic:
			_collect(path) # blocking fetch: finishes the little work left (one per frame at most)
			unstuck = true
		i -= 1
	set_process(not pending.is_empty())

func _collect(path: String) -> void:
	var res: Resource = ResourceLoader.load_threaded_get(path)
	pending.remove_at(pending.find(path))
	_waited.erase(path)
	if res != null and _still_wanted(path):
		cache[path] = res

func _still_wanted(_path: String) -> bool:
	return warm_id != ""

func _lang() -> String:
	return "ta" if str(GameState.settings.get("language", "en")) == "ta" else "en"
