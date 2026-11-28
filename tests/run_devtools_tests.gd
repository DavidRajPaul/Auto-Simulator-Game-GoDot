extends Node
## Dev tools panel (scripts/devtools/DevTools.gd): weather, time, clock, player and flood switches work,
## and the panel only exists in the main scene. DEV ONLY: this file is deleted on release/* branches
## (tools/release/strip_devtools.py).
## Run: godot --headless --path . --fixed-fps 60 res://tests/run_devtools_tests.tscn

var passed: int = 0
var failed: int = 0
var flood_paths: Array[String] = []

func check(name: String, ok: bool) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		print("FAIL: ", name)

func _ready() -> void:
	await get_tree().process_frame
	GameState.reset_profile()
	var dev: DevTools = DevTools.new()
	dev.main_scene_name = get_tree().current_scene.name
	add_child(dev)
	await get_tree().process_frame
	await get_tree().process_frame
	check("panel is built in the main scene", dev.has_panel())

	var other: DevTools = DevTools.new()
	other.main_scene_name = "SomeOtherScene"
	add_child(other)
	await get_tree().process_frame
	await get_tree().process_frame
	check("no panel outside the main scene", not other.has_panel())
	other.queue_free()

	dev.set_time(720.0)
	dev.set_weather("rain")
	check("rain switches on", GameState.is_raining)
	check("rain has no thunder", not GameState.is_thunderstorm())
	dev.set_weather("storm")
	check("storm is a thunderstorm", GameState.is_raining and GameState.is_thunderstorm())
	check("storm is mid-way (closest strikes)", absf(GameState.rain_progress() - 0.5) < 0.05)
	dev.set_weather("dry")
	check("dry stops the rain", not GameState.is_raining)
	dev.set_weather("auto")
	check("auto gives control back to the day's roll", GameState.thunder_override == -1)

	dev.set_time(1200.0)
	check("night jump", GameState.is_night())
	dev.set_time(540.0)
	check("morning jump", not GameState.is_night())
	dev.set_weather("storm")
	dev.set_time(1200.0)
	check("a storm follows a time jump", GameState.is_raining)

	dev.set_speed(0.0)
	var frozen: float = GameState.shift_minute
	await get_tree().create_timer(0.4).timeout
	check("freeze holds the clock", is_equal_approx(GameState.shift_minute, frozen))
	dev.set_speed(1.0)
	await get_tree().create_timer(0.4).timeout
	check("normal speed moves the clock", GameState.shift_minute > frozen)
	var before: float = GameState.shift_minute
	dev.set_speed(DevTools.FAST_FORWARD)
	await get_tree().create_timer(0.4).timeout
	check("fast forward outruns normal", GameState.shift_minute - before > 0.4 * GameState.GAME_MIN_PER_SECOND * 1.5)
	dev.set_time(GameState.SHIFT_END_MIN - 2.0)
	await get_tree().create_timer(0.6).timeout
	check("fast forward never ends the shift", GameState.shift_minute < GameState.SHIFT_END_MIN)
	dev.set_speed(1.0)

	var wallet: int = GameState.wallet_inr
	dev.add_cash()
	check("cash added", GameState.wallet_inr == wallet + DevTools.CASH_STEP)

	SignalBus.quest_flood_requested.connect(func(p: String) -> void: flood_paths.append(p))
	dev.toggle_flood()
	dev.toggle_flood()
	check("flood on then off", flood_paths.size() == 2 and flood_paths[0] != "" and flood_paths[1] == "")

	print("Dev tools tests: %d passed, %d failed" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)
