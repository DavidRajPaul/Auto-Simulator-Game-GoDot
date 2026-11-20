extends Node
## Savari dialogue + voices (SavariVoice, tools/voice/savari_lines.py; Nov 20 owner request: "10
## variety of dialogues in English and Tamil … calling auto … saying the place … bargain voices").
## Checks that every moment has ten lines in both languages, that every line the game can pick has
## its voice file in both languages, that every destination and every rider character maps to a
## place and a voice, that the elder says தம்பி, that the game's destination rotation matches the
## voice script, and that lines play one after another without repeating back to back.

const SCRIPT_PATH: String = "res://docs/voice/SAV_Savari_Voice_Script.md"

var passed: int = 0
var failed: int = 0


func _ready() -> void:
	_run.call_deferred()


func check(label: String, okay: bool, detail: String = "") -> void:
	if okay:
		passed += 1
		print("PASS: " + label)
	else:
		failed += 1
		push_error("FAIL: " + label + ("  (" + detail + ")" if detail != "" else ""))


func _run() -> void:
	GameState.persistence_enabled = false
	var v: SavariVoice = SavariVoice.new()
	add_child(v)
	await get_tree().process_frame
	_test_text(v)
	_test_script_and_files(v)
	_test_mapping()
	await _test_playback(v)
	TranslationServer.set_locale("en")
	print("Savari voices: %d passed, %d failed" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)


func _test_text(v: SavariVoice) -> void:
	for lang: String in ["en", "ta"]:
		TranslationServer.set_locale(lang)
		var missing: Array[String] = []
		var keys: Array[String] = []
		for cat: String in SavariVoice.RIDER_CATS:
			for i: int in SavariVoice.LINES_PER:
				keys.append("SAV_%s_%02d" % [cat.to_upper(), i + 1])
		for cat: String in SavariVoice.DRIVER_CATS:
			for i: int in SavariVoice.LINES_PER:
				keys.append("SAV_DRV_%s_%02d" % [cat.to_upper(), i + 1])
		for i: int in SavariVoice.LINES_PER:
			keys.append("SAV_DEST_%02d" % (i + 1))
			keys.append("SAV_NEAR_%02d" % (i + 1))
		for p: String in SavariVoice.PLACES:
			if p != "near":
				keys.append("SAV_PLACE_%s" % p.to_upper())
		var distinct: Dictionary = {}
		for k: String in keys:
			var t: String = tr(k)
			if t == k or t.strip_edges() == "":
				missing.append(k)
			distinct[t] = true
		check("%s: 10 lines for every rider moment and every bargain move (%d strings)" % [lang, keys.size()], missing.is_empty(), str(missing.slice(0, 5)))
		check("%s: no two lines are the same" % lang, distinct.size() == keys.size(), "%d distinct" % distinct.size())
		check("%s: destination lines name the place" % lang, str(v.dest_line("tnagar", "man")["text"]).contains(tr("SAV_PLACE_TNAGAR")))
	TranslationServer.set_locale("ta")
	GameState.settings["language"] = "ta"
	var elder_ok: bool = true
	for i: int in 30:
		var t: String = str(v.rider_line("call", "elder")["text"]) + str(v.dest_line("marina", "elder")["text"])
		elder_ok = elder_ok and not t.contains("அண்ணா")
	check("The elder calls the driver தம்பி, never அண்ணா", elder_ok)
	GameState.settings["language"] = "en"
	TranslationServer.set_locale("en")


## Every line the game can pick is in the voice script, and its two .ogg files are present.
func _test_script_and_files(_v: SavariVoice) -> void:
	var f: FileAccess = FileAccess.open(SCRIPT_PATH, FileAccess.READ)
	check("Voice script exists", f != null)
	if f == null:
		return
	var ids: Dictionary = {}
	while not f.eof_reached():
		var ln: String = f.get_line()
		if ln.begins_with("- sav_"):
			ids[ln.substr(2).split(" ")[0]] = true
	var want: Array[String] = []
	for voice: String in SavariVoice.VOICES:
		for cat: String in SavariVoice.RIDER_CATS:
			for i: int in SavariVoice.LINES_PER:
				want.append("sav_%s_%02d_%s" % [cat, i + 1, voice])
		for p: String in SavariVoice.PLACES:
			for t: int in SavariVoice.dest_templates(voice, p):
				want.append("sav_dest_%s_%02d_%s" % [p, t + 1, voice])
	for cat: String in SavariVoice.DRIVER_CATS:
		for i: int in SavariVoice.LINES_PER:
			want.append("sav_drv_%s_%02d" % [cat, i + 1])
	var not_in_script: Array[String] = []
	var no_file: Array[String] = []
	for id: String in want:
		if not ids.has(id):
			not_in_script.append(id)
		for lang: String in ["en", "ta"]:
			if not ResourceLoader.exists(SavariVoice.DIR + id + "_" + lang + ".ogg"):
				no_file.append(id + "_" + lang)
	check("Game and voice script agree on every line (%d)" % want.size(), not_in_script.is_empty() and ids.size() == want.size(),
		"%s; script has %d" % [str(not_in_script.slice(0, 4)), ids.size()])
	check("Every line has its voice in English and Tamil (%d files)" % (want.size() * 2), no_file.is_empty(),
		"%d missing, e.g. %s" % [no_file.size(), str(no_file.slice(0, 4))])
	var all_dest: Dictionary = {}
	for voice: String in SavariVoice.VOICES:
		for t: int in SavariVoice.dest_templates(voice, "tnagar"):
			all_dest[t] = true
	check("Across the four voices, all 10 ways of naming a place are heard", all_dest.size() == SavariVoice.LINES_PER)


func _test_mapping() -> void:
	var f: FileAccess = FileAccess.open("res://data/world/manifest.json", FileAccess.READ)
	var m: Dictionary = JSON.parse_string(f.get_as_text()) as Dictionary
	var unmapped: Array[String] = []
	for k: String in ["landmarks", "auto_stands", "zones"]:
		for d: Dictionary in m.get(k, []):
			if not SavariVoice.PLACE_OF.has(str(d["name"])):
				unmapped.append(str(d["name"]))
	check("Every Savari destination maps to a place riders can name", unmapped.is_empty(), str(unmapped))
	var no_voice: Array[String] = []
	for arch: String in SavariManager.ARCHETYPE_PEOPLE:
		for id: Variant in SavariManager.ARCHETYPE_PEOPLE[arch]:
			if not SavariVoice.VOICE_OF.has(str(id)):
				no_voice.append(str(id))
	check("Every rider character has a voice", no_voice.is_empty(), str(no_voice))
	check("Women and girls never get the man's voice",
		SavariVoice.voice_of("woman_saree_green") == "woman" and SavariVoice.voice_of("girl_pavadai") == "girl"
		and SavariVoice.voice_of("old_man_veshti") == "elder")


func _test_playback(v: SavariVoice) -> void:
	var a: Dictionary = v.rider_line("counter", "woman")
	var b: Dictionary = v.rider_line("counter", "woman")
	check("A line never repeats back to back", a["id"] != b["id"])
	var lines: Array[Dictionary] = [v.dest_line("marina", "girl"), v.rider_line("open", "girl")]
	var total: float = v.say(lines, true)
	check("Lines have their spoken length", float(lines[0]["seconds"]) > 0.3 and float(lines[1]["seconds"]) > 0.3,
		"%.2f / %.2f" % [float(lines[0]["seconds"]), float(lines[1]["seconds"])])
	check("Two lines play one after another", v.busy() and total >= float(lines[0]["seconds"]) + float(lines[1]["seconds"]))
	var waited: float = 0.0
	while v.busy() and waited < total + 1.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	check("…and finish when their audio does", not v.busy() and waited >= total - 0.2, "%.2f of %.2f" % [waited, total])
