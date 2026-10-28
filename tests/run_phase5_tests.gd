extends Node
## Phase 5 (MVP polish) verification: real-size osm2streets world, player-comfort pack,
## day/night + monsoon, flood spots + kick-start rhythm, main menu, Android back button.
## Run:  godot --headless --path . --fixed-fps 60 res://tests/run_phase5_tests.tscn

const MAIN_SCENE: String = "res://scenes/main_chennai.tscn"
const MENU_SCENE: String = "res://scenes/main_menu.tscn"
const WORLD_DIR: String = "res://data/world"

var _passed: int = 0
var _failed: int = 0
var _events: Dictionary = {}

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	print("\n=== Namma Auto — Phase 5 tests ===")
	for sig: String in ["recover_available", "hint_requested", "weather_changed", "kick_timed", "flood_restart_blocked", "engine_restarted", "teleport_requested"]:
		var n: String = sig
		SignalBus.connect(sig, func(a: Variant = null, _b: Variant = null) -> void: _events[n] = a)
	GameState.reset_profile()
	var manifest: Dictionary = _load_json("manifest.json")
	_test_world_data(manifest)
	await _test_menu()

	GameState.reset_profile()
	GameState.set_rain(false)
	GameState.shift_minute = 720.0 # noon
	var main: Node = (load(MAIN_SCENE) as PackedScene).instantiate()
	add_child(main)
	var auto: AutoRickshawController = main.get_node("AutoRickshaw") as AutoRickshawController
	var world: WorldChunkStreamer = main.get_node("World") as WorldChunkStreamer
	await _physics(60)
	_test_chunk_meshes(world)
	await _test_hints_and_arrow(main, auto)
	await _test_flip_recovery(auto)
	await _test_stuck_offer(auto)
	await _test_atmosphere(main)
	await _test_monsoon(main, world, auto, manifest)
	await _test_back_button(main)
	main.queue_free()
	await _physics(2)

	print("\n=== %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)

# --- Real-size world -------------------------------------------------------------------------

func _test_world_data(m: Dictionary) -> void:
	_check("Map is 1 : 1 with osm2streets roads", is_equal_approx(float(m.get("map_scale", 0.0)), 1.0) and str(m.get("road_source", "")) == "osm2streets")
	var st: Dictionary = m.get("stats", {})
	_check("Most buildings are real OSM footprints", int(st.get("real_buildings", 0)) * 3 > int(st.get("buildings", 1)) * 2,
		"%d of %d" % [int(st.get("real_buildings", 0)), int(st.get("buildings", 0))])
	var graph: RoadGraph = RoadGraph.from_json_file(WORLD_DIR.path_join("road_graph.json"))
	var floods: Array = m.get("flood_spots", [])
	var off_road: int = 0
	for f: Dictionary in floods:
		var cp: Dictionary = graph.closest_point(Vector3(float(f["x"]), 0.0, float(f["z"])))
		if float(cp["dist"]) > 2.0:
			off_road += 1
	_check("≥ 3 monsoon flood spots, all on roads", floods.size() >= 3 and off_road == 0, "%d spots" % floods.size())
	# A chunk around the Mylapore stand has real lanes, sidewalks and junction surfaces.
	var stand: Dictionary = {}
	for s: Dictionary in m["auto_stands"]:
		if str(s["id"]) == "stand_mylapore":
			stand = s
	var k: Vector2i = Vector2i(floori(float(stand["x"]) / 250.0), floori(float(stand["z"]) / 250.0))
	var c: Dictionary = _load_json("chunks/c_%d_%d.json" % [k.x, k.y])
	var surf: Dictionary = c.get("surf", {})
	_check("Stand chunk has lanes, sidewalks, junctions, markings", surf.has("road") and surf.has("walk") and surf.has("junction") and (surf.has("centre") or surf.has("lane")))
	var blds: Array = c.get("blds", [])
	var real: int = 0
	for b: Dictionary in blds:
		if not b.has("f"):
			real += 1
	_check("Stand chunk has real building footprints", real >= 20, "%d real of %d" % [real, blds.size()])

func _test_chunk_meshes(world: WorldChunkStreamer) -> void:
	var road_tris: int = 0
	var bld_tris: int = 0
	for k: Vector2i in world.loaded:
		var ch: Node3D = world.loaded[k]
		var r: MeshInstance3D = ch.get_node_or_null("Roads") as MeshInstance3D
		if r != null:
			road_tris += r.mesh.surface_get_array_index_len(0) / 3
		var b: MeshInstance3D = ch.get_node_or_null("Buildings/BuildingMeshes") as MeshInstance3D
		if b != null:
			bld_tris += b.mesh.surface_get_array_len(0) / 3
	_check("Streamed chunks build road surfaces", road_tris > 2000, "%d tris" % road_tris)
	_check("Streamed chunks build extruded buildings", bld_tris > 2000, "%d tris" % bld_tris)

# --- Comfort pack ------------------------------------------------------------------------------

func _test_hints_and_arrow(main: Node, auto: AutoRickshawController) -> void:
	# First-run guidance is the guided first ride now (TutorialDirector, phase 11 suite).
	_check("City has the first-ride tutorial", main.get_node_or_null("TutorialDirector") is TutorialDirector)
	Input.action_press("accelerate")
	await _physics(240)
	Input.action_release("accelerate")
	var savari: SavariManager = main.get_node("SavariManager") as SavariManager
	await _physics(90)
	var assist: ComfortAssist = main.get_node("ComfortAssist") as ComfortAssist
	var arrow: MeshInstance3D = assist.get_node("GuidanceArrow") as MeshInstance3D
	var target: Vector3 = assist.guidance_target()
	_check("Guidance arrow points to the nearest rider", savari.hails.size() > 0 and target != Vector3.INF, "%d hails" % savari.hails.size())
	var far: bool = target != Vector3.INF and Vector2(target.x - auto.global_position.x, target.z - auto.global_position.z).length() > ComfortAssist.ARROW_HIDE_NEAR_M
	_check("Arrow visible while the rider is far", arrow.visible == far)
	GameState.settings["guidance_arrow"] = false
	await _physics(2)
	_check("Guide-arrow setting hides it", not arrow.visible)
	GameState.settings["guidance_arrow"] = true

func _test_flip_recovery(auto: AutoRickshawController) -> void:
	await _brake_to_stop(auto)
	var graph: RoadGraph = SignalBus.current_road_graph
	auto.global_transform = Transform3D(Basis(Vector3.FORWARD, PI), auto.global_position + Vector3(0, 1.5, 0))
	auto.linear_velocity = Vector3.ZERO
	auto.angular_velocity = Vector3.ZERO
	await _physics(200)
	var cp: Dictionary = graph.closest_point(auto.global_position)
	_check("Flipped auto is put back upright", auto.global_transform.basis.y.y > 0.9, "up.y %.2f" % auto.global_transform.basis.y.y)
	_check("…on a road", float(cp["dist"]) < 8.0, "%.1f m from centre" % float(cp["dist"]))

func _test_stuck_offer(auto: AutoRickshawController) -> void:
	# Pin the auto in place and hold the throttle: after a few seconds a Reset button is offered.
	# Settle first: a frozen auto stops reporting speed, so freezing it mid-roll left a stale
	# speed above the "stuck" limit and made this check flaky.
	await _brake_to_stop(auto)
	await _physics(10)
	auto.freeze = true
	_events.erase("recover_available")
	Input.action_press("accelerate")
	await _physics(int(ComfortAssist.STUCK_S * 60.0) + 30)
	Input.action_release("accelerate")
	_check("Stuck auto gets a 'Reset auto' offer", _events.get("recover_available", false) == true)
	auto.freeze = false
	SignalBus.recover_requested.emit()
	await _physics(30)
	_check("Reset clears the offer", _events.get("recover_available", true) == false)

# --- Day / night / monsoon --------------------------------------------------------------------

func _test_atmosphere(main: Node) -> void:
	var atmo: Atmosphere = main.get_node("Atmosphere") as Atmosphere
	var env: Environment = (main.get_node("WorldEnvironment") as WorldEnvironment).environment
	var light: Light3D = get_tree().get_nodes_in_group("headlight")[0] as Light3D
	_check("Sun is high at noon, low at dusk, gone at night",
		Atmosphere.sun_height(720.0) > 0.9 and Atmosphere.sun_height(1080.0) < 0.3 and Atmosphere.sun_height(1260.0) < 0.0)
	atmo.apply(720.0, 0.0)
	var day_amb: float = env.ambient_light_color.get_luminance()
	var noon_lights: bool = light.visible
	atmo.apply(1260.0, 0.0)
	var night_amb: float = env.ambient_light_color.get_luminance()
	_check("Night is darker than day but never pitch black", night_amb < day_amb and night_amb > 0.12, "%.2f vs %.2f" % [night_amb, day_amb])
	_check("Headlight off at noon, on at night", not noon_lights and light.visible)
	atmo.apply(720.0, 1.0)
	_check("Headlight on in heavy rain", light.visible)
	atmo.apply(720.0, 0.0)

func _test_monsoon(main: Node, world: WorldChunkStreamer, auto: AutoRickshawController, m: Dictionary) -> void:
	var fx: MonsoonFX = main.get_node("MonsoonFX") as MonsoonFX
	GameState.set_rain(true, 600.0)
	_check("Rain starts (weather_changed)", GameState.is_raining and _events.get("weather_changed", false) == true)
	await _frames(240)
	_check("Rain overlay fades in", fx.rain > 0.5 and (fx.get_node("RainLayer").get_child(0) as ColorRect).visible)
	_check("Roads turn wet and glossy", world.wetness > 0.3, "wetness %.2f" % world.wetness)
	# Drive into the deepest flood spot: the engine floods and needs a rhythmic kick-start.
	var deepest: Dictionary = {}
	for f: Dictionary in m["flood_spots"]:
		if deepest.is_empty() or float(f["depth"]) > float(deepest["depth"]):
			deepest = f
	await _brake_to_stop(auto)
	SignalBus.teleport_requested.emit(Transform3D(Basis.IDENTITY, Vector3(float(deepest["x"]), 1.0, float(deepest["z"]))))
	await _physics(90)
	Input.action_press("accelerate")
	await _physics(30)
	Input.action_release("accelerate")
	_check("Deep monsoon flood stalls the engine", auto.is_engine_stalled, "%s, %.2f m" % [deepest["name"], auto.current_water_depth_m])
	_check("Three wheel splash emitters exist", auto.get_node_or_null("WheelSplash0") != null and auto.get_node_or_null("WheelSplash1") != null and auto.get_node_or_null("WheelSplash2") != null)

	_events.erase("flood_restart_blocked")
	for i: int in 3: # submerged: kick is blocked before rhythm evaluation
		auto.pull_hand_kick_starter()
	_check("Submerged engine cannot be kick-started", auto.is_engine_stalled and _events.has("flood_restart_blocked"))
	auto.current_water_depth_m = 0.0 # pushed out of the water
	# Outside the flood, the original anti-mashing rhythm behavior still applies.
	for i: int in 3:
		auto.pull_hand_kick_starter()
	_check("Mashing KICK doesn't restart it once dry", auto.is_engine_stalled and _events.get("kick_timed", true) == false)
	_events.erase("engine_restarted")
	for i: int in auto.stats.kick_start_pulls_needed + 1:
		await _physics(36) # ~0.6 s rhythm
		auto.pull_hand_kick_starter()
	_check("Steady kick rhythm restarts it", not auto.is_engine_stalled and _events.has("engine_restarted"))
	GameState.set_rain(false)
	await _frames(5)
	_check("Floods drain when the rain stops", not GameState.is_raining)
	# Windscreen wiper clears drops.
	GameState.set_rain(true, 600.0)
	SignalBus.camera_mode_changed.emit("Cockpit")
	await _frames(300)
	var wet_drops: float = fx.drops
	SignalBus.wiper_toggled.emit(true)
	await _frames(90)
	_check("Wiper clears the windscreen", fx.drops < wet_drops * 0.5, "%.2f → %.2f" % [wet_drops, fx.drops])
	SignalBus.wiper_toggled.emit(false)
	SignalBus.camera_mode_changed.emit("Chase")
	GameState.set_rain(false)

func _test_back_button(main: Node) -> void:
	var ui: GarageUI = main.get_node("GarageUI") as GarageUI
	ui.close_modal()
	SignalBus.back_requested.emit()
	_check("Back button pauses the game", ui.is_open() and get_tree().paused)
	SignalBus.back_requested.emit()
	_check("Back again resumes", not ui.is_open() and not get_tree().paused)

# --- Main menu ---------------------------------------------------------------------------------

func _test_menu() -> void:
	GameState.set_setting("language", "ta")
	GameState.wallet_inr = 4321
	var menu: MainMenu = (load(MENU_SCENE) as PackedScene).instantiate() as MainMenu
	add_child(menu)
	await _frames(5)
	_check("Main menu holds the shift clock", not GameState.shift_running)
	_check("No Continue without a save (tests never persist)", not menu._buttons.has("continue") and menu._buttons.has("new"))
	menu.open_credits()
	var credits: String = ""
	for c: Node in menu._panel_body.get_children():
		if c is Label:
			credits += (c as Label).text
	_check("Credits name OpenStreetMap (ODbL) and osm2streets", credits.contains("OpenStreetMap") and credits.contains("ODbL") and credits.contains("osm2streets"))
	SignalBus.back_requested.emit()
	_check("Back closes a menu panel", not menu._panel.visible)
	menu.queue_free()
	await _frames(2)
	GameState.new_career()
	_check("New career resets money but keeps settings", GameState.wallet_inr == 500 and str(GameState.settings["language"]) == "ta" and int(GameState.settings["first_ride_step"]) == 0 and not bool(GameState.settings["first_ride_done"]))
	GameState.set_setting("language", "en")
	GameState.shift_running = true

# --- Helpers -----------------------------------------------------------------------------------

func _brake_to_stop(auto: AutoRickshawController) -> void:
	Input.action_release("accelerate")
	Input.action_press("brake")
	for i: int in 240:
		await get_tree().physics_frame
		if auto.current_speed_kmh < 1.0:
			break
	Input.action_release("brake")
	auto.linear_velocity = Vector3.ZERO

func _load_json(rel: String) -> Dictionary:
	var f: FileAccess = FileAccess.open(WORLD_DIR.path_join(rel), FileAccess.READ)
	return {} if f == null else JSON.parse_string(f.get_as_text()) as Dictionary

func _physics(frames: int) -> void:
	for i: int in frames:
		await get_tree().physics_frame

func _frames(frames: int) -> void:
	for i: int in frames:
		await get_tree().process_frame

func _check(test_name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  PASS  ", test_name, ("  (" + detail + ")") if detail != "" else "")
	else:
		_failed += 1
		printerr("  FAIL  ", test_name, ("  (" + detail + ")") if detail != "" else "")
