extends Node
## Dev-only visual check of the title screen and its panels with a played save.
## Run: SHOT_PANEL=achievements SHOT_OUT=/tmp/m.png SHOT_W=1280 SHOT_H=800 \
##   xvfb-run -a godot --path . --rendering-driver opengl3 res://tests/shot_menu.tscn
## SHOT_PANEL: empty (home), achievements, profile, settings. SHOT_FRESH=1: first launch, no save.
## SHOT_BROWSE=n: step the auto picker. SHOT_LANG=ta: Tamil.
func _ready() -> void:
	var w: int = int(OS.get_environment("SHOT_W")) if OS.has_environment("SHOT_W") else 1280
	var h: int = int(OS.get_environment("SHOT_H")) if OS.has_environment("SHOT_H") else 800
	get_window().size = Vector2i(w, h)
	GameState.reset_profile()
	if OS.has_environment("SHOT_LANG"):
		GameState.set_setting("language", OS.get_environment("SHOT_LANG"))
	if not OS.has_environment("SHOT_FRESH"):
		GameState.save_path = "user://shot_menu_save.dat"
		GameState.persistence_enabled = true
		GameState.save_game()
		GameState.persistence_enabled = true
		GameState.condition = 62.0
		GameState.rewards.stats = {"rides": 12, "earned": 1860, "meter_rides": 7, "near_misses": 18, "smooth_rides": 4}
		GameState.rewards.achieved = {"first_savari": "2026-11-03"}
		GameState.progress.xp = 240
	GameState.rewards.last_login_date = RewardsEngine.today_string()
	var menu: Node = (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	add_child(menu)
	for i: int in 30:
		await get_tree().process_frame
	var panel: String = OS.get_environment("SHOT_PANEL")
	if panel != "":
		menu.call("open_" + panel)
	if OS.has_environment("SHOT_BROWSE"):
		for i: int in int(OS.get_environment("SHOT_BROWSE")):
			menu.call("browse_vehicle", 1)
	for i: int in 45:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OS.get_environment("SHOT_OUT"))
	if FileAccess.file_exists(GameState.save_path) and GameState.save_path.ends_with("shot_menu_save.dat"):
		DirAccess.remove_absolute(GameState.save_path)
	get_tree().quit()
