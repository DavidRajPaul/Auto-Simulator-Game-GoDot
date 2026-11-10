extends Node
## Daily reminder notifications (autoloads/DailyReminder.gd). The Android plugin is absent here,
## so this checks the schedule and messages, the no-op paths and the Android packaging wiring.
## Run: godot --headless --path . --fixed-fps 60 res://tests/run_reminder_tests.tscn

var _passed: int = 0
var _failed: int = 0

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	print("\n=== Namma Auto — Daily reminder tests ===")
	TranslationServer.set_locale("en")
	_test_schedule_times()
	_test_streak_messages()
	_test_broken_streak_messages()
	_test_translations()
	_test_no_plugin_is_safe()
	await _test_ask_card()
	_test_packaging()
	print("\n=== %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)

func _test_schedule_times() -> void:
	var status: Dictionary = {"available": false, "streak": 3}
	var week: Array[Dictionary] = DailyReminder.build_reminders(status)
	_check("A week of reminders", week.size() == DailyReminder.DAYS, str(week.size()))
	_check("Ids 1..7 (rescheduling replaces the same jobs)", week[0]["id"] == 1 and week[6]["id"] == 7)
	var ok_days: bool = true
	for i: int in week.size():
		ok_days = ok_days and int(week[i]["days_ahead"]) == i + 1 and int(week[i]["hour"]) == 19
	_check("One per day at 7 PM local, starting tomorrow (never today)", ok_days)

func _test_streak_messages() -> void:
	var r: Array[Dictionary] = DailyReminder.build_reminders({"available": false, "streak": 3})
	_check("Claimed today, 3-day streak → tomorrow's title names the streak", str(r[0]["title"]).contains("3-day"), str(r[0]["title"]))
	_check("…and tomorrow's tile: day 4, ₹125", str(r[0]["body"]).contains("Day 4") and str(r[0]["body"]).contains("₹%d" % RewardsEngine.DAILY_INR[3]), str(r[0]["body"]))
	var jackpot: Array[Dictionary] = DailyReminder.build_reminders({"available": false, "streak": 6})
	_check("Streak 6 → tomorrow is the day-7 jackpot", str(jackpot[0]["title"]) == tr("REM_T_JACKPOT") and str(jackpot[0]["body"]).contains("₹%d" % RewardsEngine.DAILY_INR[6]), str(jackpot[0]["body"]))
	var cycle: Array[Dictionary] = DailyReminder.build_reminders({"available": false, "streak": 7})
	_check("After the jackpot the calendar restarts at day 1", str(cycle[0]["body"]).contains("Day 1"), str(cycle[0]["body"]))
	_check("Last reminder says we'll stop", str(r[6]["title"]) == tr("REM_T_LAST"))

func _test_broken_streak_messages() -> void:
	var r: Array[Dictionary] = DailyReminder.build_reminders({"available": true, "streak": 1})
	_check("Bonus not claimed today → fresh ₹50 streak offer", str(r[0]["title"]) == tr("REM_T_BONUS") and str(r[0]["body"]).contains("₹%d" % RewardsEngine.DAILY_INR[0]), str(r[0]["body"]))
	var titles: Dictionary = {}
	for x: Dictionary in r:
		titles[str(x["title"])] = true
		_check("Day %d has a title and body" % int(x["id"]), str(x["title"]) != "" and str(x["body"]) != "" and not str(x["body"]).contains("%"))
	_check("Messages vary across the week", titles.size() >= 5, str(titles.size()))

func _test_translations() -> void:
	var csv: String = FileAccess.get_file_as_string("res://translations/ui.csv")
	var keys: PackedStringArray = ["DAILY_REMINDER", "REMINDER_TEST", "REMINDER_ASK_TITLE", "REMINDER_ASK_BODY", "REMINDER_YES", "REMINDER_NO",
		"REM_T_STREAK", "REM_B_STREAK", "REM_T_JACKPOT", "REM_B_JACKPOT", "REM_T_BONUS", "REM_B_BONUS", "REM_T_PASSENGERS", "REM_B_PASSENGERS",
		"REM_T_AUTO", "REM_B_AUTO", "REM_T_MARINA", "REM_B_MARINA", "REM_T_LAST", "REM_B_LAST"]
	var missing: PackedStringArray = []
	for k: String in keys:
		if not csv.contains("\n" + k + ","):
			missing.append(k)
	_check("Every reminder string is in ui.csv (English + Tamil)", missing.is_empty(), ", ".join(missing))
	TranslationServer.set_locale("ta")
	var ta: Array[Dictionary] = DailyReminder.build_reminders({"available": false, "streak": 2})
	_check("Tamil reminders are translated (and keep the numbers)", str(ta[0]["title"]) != "REM_T_STREAK" and str(ta[0]["title"]).contains("2") and not str(ta[0]["title"]).contains("-day"), str(ta[0]["title"]))
	TranslationServer.set_locale("en")

func _test_no_plugin_is_safe() -> void:
	_check("No Android plugin in tests/editor", not DailyReminder.is_supported())
	_check("Toggle reads off without the plugin", not DailyReminder.is_on())
	DailyReminder.reschedule()
	DailyReminder.cancel_all()
	DailyReminder.send_test()
	var asked_before: bool = bool(GameState.settings.get("reminder_asked", false))
	DailyReminder.maybe_ask()
	_check("No permission card without the plugin", get_tree().root.find_child("ReminderAsk", true, false) == null)
	_check("…and nothing recorded as asked", bool(GameState.settings.get("reminder_asked", false)) == asked_before)
	_check("Reminders default to on (asked later, never at launch)", bool(GameState.settings.get("daily_reminder", false)))

## The card itself (normally only shown with the plugin): pauses, blocks, answers, restores.
func _test_ask_card() -> void:
	var keep: Dictionary = GameState.settings.duplicate()
	GameState.persistence_enabled = false
	get_tree().paused = false
	DailyReminder._show_dialog()
	await get_tree().process_frame
	var card: Node = get_tree().root.find_child("ReminderAsk", true, false)
	_check("Ask card shows and pauses the game", card != null and get_tree().paused)
	DailyReminder._answer(false)
	await get_tree().process_frame
	_check("'Not now' closes it and unpauses", get_tree().root.find_child("ReminderAsk", true, false) == null and not get_tree().paused)
	_check("'Not now' records the answer: asked, reminders off", bool(GameState.settings["reminder_asked"]) and not bool(GameState.settings["daily_reminder"]))
	GameState.settings = keep

func _test_packaging() -> void:
	var godot_cfg: String = FileAccess.get_file_as_string("res://project.godot")
	_check("Export addon is enabled", godot_cfg.contains("res://addons/namma_reminder/plugin.cfg"))
	_check("DailyReminder autoload is loaded", get_node_or_null("/root/DailyReminder") != null)
	var addon: String = FileAccess.get_file_as_string("res://addons/namma_reminder/export_plugin.gd")
	var gradle: String = FileAccess.get_file_as_string("res://android_plugins/namma_reminder/build.gradle")
	var deps_match: bool = true
	for dep: String in ["androidx.work:work-runtime:", "androidx.core:core:"]:
		var a: int = addon.find(dep)
		var g: int = gradle.find(dep)
		deps_match = deps_match and a >= 0 and g >= 0 and addon.substr(a, addon.find("\"", a) - a) == gradle.substr(g, gradle.find("'", g) - g)
	_check("Export addon and Gradle build list the same AndroidX versions", deps_match)
	var manifest: String = FileAccess.get_file_as_string("res://android_plugins/namma_reminder/src/main/AndroidManifest.xml")
	_check("Plugin registers as v2 'NammaReminder' (matches DailyReminder.PLUGIN)", manifest.contains("org.godotengine.plugin.v2." + DailyReminder.PLUGIN))
	_check("Plugin declares POST_NOTIFICATIONS", manifest.contains("android.permission.POST_NOTIFICATIONS"))
	var kt: String = FileAccess.get_file_as_string("res://android_plugins/namma_reminder/src/main/kotlin/com/davidrajpaul/nammaauto/reminder/NammaReminderPlugin.kt")
	var gd: String = FileAccess.get_file_as_string("res://autoloads/DailyReminder.gd")
	var names_ok: bool = kt.contains("getPluginName(): String = \"%s\"" % DailyReminder.PLUGIN) and kt.contains("SignalInfo(\"permission_result\"")
	for m: String in ["scheduleAt", "schedule", "cancelAll", "notificationsEnabled", "requestPermission"]:
		names_ok = names_ok and kt.contains("@UsedByGodot\n\tfun %s(" % m) and gd.contains("\"%s\"" % m)
	_check("Every plugin method DailyReminder calls exists in the Kotlin plugin", names_ok)

func _check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  PASS  " + name)
	else:
		_failed += 1
		print("  FAIL  " + name + ("" if detail == "" else "  (" + detail + ")"))
