extends Node
## Dev-only: the ad placements in the real game scene, with the placeholder banner (MockAdProvider).
## Run: SHOT_UI=garage_autos SHOT_OUT=/tmp/a.png SHOT_W=1600 SHOT_H=720 \
##   xvfb-run -a godot --path . --rendering-driver opengl3 res://tests/shot_ads.tscn
## SHOT_UI: garage_autos, garage_paint, pause, map, summary, quest_double, driving, test_drive.
func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var w: int = int(OS.get_environment("SHOT_W")) if OS.has_environment("SHOT_W") else 1600
	var h: int = int(OS.get_environment("SHOT_H")) if OS.has_environment("SHOT_H") else 720
	get_window().size = Vector2i(w, h)
	GameState.persistence_enabled = false
	GameState.reset_profile()
	GameState.settings["first_ride_done"] = true
	GameState.tutorial_active = false
	GameState.wallet_inr = 4200
	GameState.progress.xp = 240
	GameState.shift_minute = 660.0
	var city: Node = (load("res://scenes/main_chennai.tscn") as PackedScene).instantiate()
	add_child(city)
	for i: int in 90:
		await get_tree().physics_frame
	GameState.tutorial_active = false
	var ui: String = OS.get_environment("SHOT_UI")
	var garage: GarageUI = _find(city, "GarageUI") as GarageUI
	match ui:
		"garage_autos", "garage_paint":
			garage.set("_current_tab", "TAB_AUTOS" if ui == "garage_autos" else "TAB_PAINT")
			garage.open_garage()
		"pause":
			garage.open_pause()
		"map":
			SignalBus.full_map_requested.emit(true)
		"summary":
			GameState.day_stats = {"earned": 1240, "rides": 9, "fuel_spent": 180, "repairs": 60}
			GameState.end_shift()
		"quest_double":
			var hud: QuestHUD = _find(city, "QuestHUD") as QuestHUD
			hud.set("_quest_id", "sq_demo")
			hud.set("_reward", 350)
			hud.call("_on_finished", "sq_demo", "completed", "")
		"test_drive":
			SignalBus.rewarded_ad_completed.emit("ad_test_drive", {"vehicle": "namma_green_ev", "ad_id": "shot"})
			garage.set("_current_tab", "TAB_AUTOS")
			garage.open_garage()
	for i: int in 50:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_environment("SHOT_OUT"))
	get_tree().quit()

func _find(root: Node, cls: String) -> Node:
	for n: Node in root.find_children("*", "", true, false):
		var sc: Script = n.get_script() as Script
		if sc != null and sc.get_global_name() == cls:
			return n
	return null
