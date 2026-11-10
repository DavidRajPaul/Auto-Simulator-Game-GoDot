extends Node
## Google Play release configuration in export_presets.cfg (both Android presets).
## CI additionally reads the built APK's manifest (android-build.yml, "Verify APK manifest").
## Run: godot --headless --path . res://tests/run_store_config_tests.tscn

## Google Play: new apps and updates must target Android 16 (API 36) from 31 Aug 2026.
const PLAY_TARGET_SDK: int = 36
const APP_CATEGORY_GAME: int = 2 # Godot's enum: Accessibility, Audio, Game, ...

var _passed: int = 0
var _failed: int = 0

func _ready() -> void:
	print("\n=== Namma Auto — Play Store config tests ===")
	var presets: ConfigFile = ConfigFile.new()
	_check("export_presets.cfg loads", presets.load("res://export_presets.cfg") == OK)
	var found: int = 0
	for section: String in presets.get_sections():
		if not (section.begins_with("preset.") and section.count(".") == 1):
			continue
		if str(presets.get_value(section, "platform", "")) != "Android":
			continue
		found += 1
		var label: String = str(presets.get_value(section, "name", section))
		var opts: String = section + ".options"
		_check("%s: target SDK %d" % [label, PLAY_TARGET_SDK], str(presets.get_value(opts, "gradle_build/target_sdk", "")) == str(PLAY_TARGET_SDK),
			"found '%s'" % presets.get_value(opts, "gradle_build/target_sdk", ""))
		_check("%s: Gradle build (needed for target SDK + plugins)" % label, bool(presets.get_value(opts, "gradle_build/use_gradle_build", false)))
		_check("%s: category Game (exempt from Android 16 large-screen rotation)" % label, int(presets.get_value(opts, "package/app_category", -1)) == APP_CATEGORY_GAME)
		_check("%s: immersive (Android 16 forces edge-to-edge anyway)" % label, bool(presets.get_value(opts, "screen/immersive_mode", false)))
	_check("Both Android presets found (APK + AAB)", found == 2, str(found))
	var manifest: String = FileAccess.get_file_as_string("res://android_plugins/namma_reminder/src/main/AndroidManifest.xml")
	_check("Back-button opt-out for target 36 is in the merged plugin manifest", manifest.contains("android:enableOnBackInvokedCallback=\"false\""))
	_check("Back button reaches the game (GameState handles WM_GO_BACK_REQUEST)", not bool(ProjectSettings.get_setting("application/config/quit_on_go_back", true)))
	print("\n=== %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)

func _check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  PASS  " + name)
	else:
		_failed += 1
		print("  FAIL  " + name + ("" if detail == "" else "  (" + detail + ")"))
