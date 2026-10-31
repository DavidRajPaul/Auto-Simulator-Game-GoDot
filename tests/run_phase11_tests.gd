extends Node
## Phase 11 (Plan Phase 2 — first-ride tutorial): a headless bot plays Murugan Anna's guided
## ride end to end through Input actions, then checks skip, replay, resume after reload, the
## scripted world (no ads, no fuel burn, thin traffic, crash floor) and the save migration.
## Run: godot --headless --path . --fixed-fps 60 res://tests/run_phase11_tests.tscn

const CITY: String = "res://scenes/main_chennai.tscn"
const SCRIPT_PATH: String = "res://data/tutorial/first_ride.tres"
const VALID_COMPLETE_ON: Array[String] = ["engine_restarted", "speed", "stop_marker", "signalled_turn", "horn",
	"haggle_started", "haggle_accepted", "near_destination", "ride_completed", "timer"]

var _passed: int = 0
var _failed: int = 0
var _completed: Array[String] = []
var _finished: Array[bool] = []
var _hints: int = 0

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	print("\n=== Namma Auto — Phase 11 tests (first-ride tutorial) ===")
	_test_data()
	_test_save_migration()
	GameState.reset_profile()
	SignalBus.tutorial_step_completed.connect(func(id: String, _s: float) -> void: _completed.append(id))
	SignalBus.tutorial_finished.connect(func(skipped: bool) -> void: _finished.append(skipped))
	SignalBus.tutorial_hint.connect(func(_t: String) -> void: _hints += 1)
	var city: Node = (load(CITY) as PackedScene).instantiate()
	add_child(city)
	await _physics(90)
	var dir: TutorialDirector = city.get_node("TutorialDirector") as TutorialDirector
	_check("Director never auto-starts in test runs", not dir.is_running())
	await _test_full_ride(city, dir)
	await _test_replay_and_skip(dir)
	await _test_resume(dir)
	city.queue_free()
	await _physics(2)
	GameState.tutorial_active = false
	print("\n=== %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)

# --- Data ------------------------------------------------------------------------------------------

func _test_data() -> void:
	var data: TutorialScript = load(SCRIPT_PATH) as TutorialScript
	_check("first_ride.tres loads as TutorialScript", data != null)
	if data == null:
		return
	_check("Ten steps, kick-start first, free roam last", data.steps.size() == 10 and data.steps[0].id == "kick_start" and data.steps[9].id == "free_roam")
	var bad_on: Array[String] = []
	var missing: Array[String] = []
	TranslationServer.set_locale("en")
	for s: TutorialStep in data.steps:
		if not VALID_COMPLETE_ON.has(s.complete_on):
			bad_on.append(s.id)
		for k: String in [s.line_key, s.hint_key]:
			if k != "" and tr(k) == k:
				missing.append(k)
	_check("Every step completes on a known condition", bad_on.is_empty(), str(bad_on))
	TranslationServer.set_locale("ta")
	for s: TutorialStep in data.steps:
		if tr(s.line_key) == s.line_key:
			missing.append("ta:" + s.line_key)
	TranslationServer.set_locale("en")
	_check("Every line and nudge has English and Tamil text", missing.is_empty(), str(missing))
	_check("Ride steps resume at the pick-up", data.steps[6].resume_to == 5 and data.steps[7].resume_to == 5 and data.steps[8].resume_to == 5)

func _test_save_migration() -> void:
	GameState.reset_profile()
	GameState.from_dict({"rides": 4, "settings": {"tutorial_step": 5, "language": "en"}})
	_check("Old save with rides skips the tutorial", bool(GameState.settings["first_ride_done"]) and not GameState.settings.has("tutorial_step"))
	GameState.from_dict({"rides": 0, "settings": {"language": "en"}})
	_check("Old save with no rides gets the tutorial", not bool(GameState.settings["first_ride_done"]))
	GameState.settings["first_ride_step"] = 4
	var d: Dictionary = JSON.parse_string(JSON.stringify(GameState.to_dict())) as Dictionary
	GameState.settings["first_ride_step"] = 0
	GameState.from_dict(d)
	_check("Tutorial step survives save/load", int(GameState.settings["first_ride_step"]) == 4)
	GameState.new_career()
	_check("New career queues the tutorial again", not bool(GameState.settings["first_ride_done"]) and int(GameState.settings["first_ride_step"]) == 0)

# --- The bot plays the whole ride --------------------------------------------------------------

func _test_full_ride(city: Node, dir: TutorialDirector) -> void:
	var auto: AutoRickshawController = city.get_node("AutoRickshaw") as AutoRickshawController
	var savari: SavariManager = city.get_node("SavariManager") as SavariManager
	var traffic: ChennaiTrafficManager = city.get_node("ChennaiTrafficManager") as ChennaiTrafficManager
	var hud: TouchHUD = city.get_node("TouchHUD") as TouchHUD
	var overlay: TutorialOverlay = city.get_node("TutorialOverlay") as TutorialOverlay
	var wallet0: int = GameState.wallet_inr
	dir.start(0)
	await _physics(4)
	_check("Tutorial starts at the kick-start", dir.is_running() and dir.current_step_id() == "kick_start" and GameState.tutorial_active)
	_check("Engine is switched off and KICK is shown", auto.is_engine_stalled and (hud._buttons["KickStart"]["panel"] as Control).visible)
	_check("Mentor card shows the line", overlay.card.visible and overlay.line_label.text.contains("KICK"), overlay.line_label.text)
	_check("Spotlight is on the KICK button", overlay.is_spotlight_on())
	# Coach mode (Oct 31 playtest: "I barely could see the game because of the overlay").
	var vp: Vector2 = overlay.get_viewport().get_visible_rect().size
	_check("No screen dimming: the overlay covers < 15 % of the screen", overlay.covered_fraction() < 0.15, "%.1f %%" % (overlay.covered_fraction() * 100.0))
	var road_band: Rect2 = Rect2(vp.x * 0.35, vp.y * 0.12, vp.x * 0.3, vp.y * 0.6) # road + vanishing point
	_check("Coach strip and bubble stay off the road ahead", not overlay.card.get_rect().intersects(road_band) and not overlay.bubble.get_rect().intersects(road_band),
		"vp %s band %s strip %s bubble %s" % [vp, road_band, overlay.card.get_rect(), overlay.bubble.get_rect()])
	_check("Coach strip shows the short task", overlay.task_label.text == tr("TUT_KICK_TASK"), overlay.task_label.text)
	_check("Tutorial teaches in daylight (clock >= 7:00)", GameState.shift_minute >= TutorialDirector.TUTORIAL_MIN_MINUTE, "%.0f" % GameState.shift_minute)
	_check("The big status ribbon is suppressed during the tutorial", not hud._banner.visible and not hud._status_label.visible)
	_check("SKIP is offered on the strip", overlay.skip_button.visible)
	AdMonetizationManager.debug_advance(2000.0) # well past the first-session grace
	_check("No interstitial can fire during the tutorial", AdMonetizationManager.interstitial_block_reason("after_fare_summary") == "tutorial"
		and not AdMonetizationManager.maybe_show_interstitial("after_fare_summary"))
	traffic._update_density()
	_check("Traffic is thinned while it runs", traffic.target_active <= dir.data.max_traffic, "%d" % traffic.target_active)
	_check("No random riders while it runs", savari.hails.is_empty(), "%d hails" % savari.hails.size())

	# 1. Kick-start: three steady kicks (~0.6 s apart).
	for i: int in 3:
		await _tap("kick_start")
		await _physics(34)
	await _physics(2)
	_check("Steady kicks start the engine and advance", not auto.is_engine_stalled and dir.current_step_id() == "pull_out", dir.current_step_id())
	_check("ACCEL target says HOLD", overlay._chip.visible and overlay._chip.text == tr("TUT_HOLD"), overlay._chip.text)

	# 2. Pull out to 15 km/h. No LPG burnt on the way.
	var fuel0: float = auto.fuel_level
	Input.action_press("accelerate")
	var frames: int = 0
	while dir.current_step_id() == "pull_out" and frames < 600:
		await _physics(1)
		frames += 1
	Input.action_release("accelerate")
	_check("Reaching 15 km/h advances to steer & brake", dir.current_step_id() == "steer_brake", "%s after %d frames" % [dir.current_step_id(), frames])
	_check("No fuel burn during the tutorial", is_equal_approx(auto.fuel_level, fuel0), "%.3f -> %.3f" % [fuel0, auto.fuel_level])

	# 3. Stop line: overshooting moves it on; stopping on it completes.
	var line_fwd: Vector3 = dir._marker_fwd
	var line_pos: Vector3 = dir.marker_position()
	_check("A STOP line is painted ahead", dir._marker.visible and line_pos.distance_to(auto.global_position) > 20.0)
	await _park(line_pos + line_fwd * 16.0, line_fwd)
	_check("Driving past the line moves it ahead with a nudge", dir.marker_position().distance_to(line_pos) > 5.0 and _hints > 0)
	line_pos = dir.marker_position()
	line_fwd = dir._marker_fwd
	await _park(line_pos - line_fwd * 6.0, line_fwd)
	Input.action_press("accelerate")
	await _physics(25)
	Input.action_release("accelerate")
	Input.action_press("brake")
	frames = 0
	while dir.current_step_id() == "steer_brake" and frames < 240:
		await _physics(1)
		frames += 1
	Input.action_release("brake")
	if dir.current_step_id() == "steer_brake": # rolled long: settle right on the line
		await _park(line_pos, line_fwd)
	_check("Stopping on the line advances to the indicator", dir.current_step_id() == "indicate", dir.current_step_id())

	# 4. Indicator + a signalled turn (the bot can't find a junction, so it reports the turn).
	await _tap("indicator_left")
	SignalBus.signalled_turn.emit(-1)
	await _physics(3)
	_check("A signalled turn advances to the horn", dir.current_step_id() == "horn", dir.current_step_id())
	await _tap("indicator_left") # lamp off again

	# 5. Horn: a scooter is placed in our lane ahead.
	var scooter: TrafficVehicleAI = null
	for v: TrafficVehicleAI in traffic.active_vehicles():
		var to_v: Vector3 = v.global_position - auto.global_position
		if v.archetype == TrafficVehicleAI.Archetype.TWO_WHEELER and to_v.length() < 40.0 and to_v.normalized().dot(-auto.global_transform.basis.z) > 0.5:
			scooter = v
	_check("A scooter blocks the lane ahead", scooter != null)
	await _tap("horn")
	await _physics(2)
	_check("Honking advances to the pick-up", dir.current_step_id() == "pick_up", dir.current_step_id())

	# 6. Pick-up: one scripted rider, waiting on the kerb.
	await _physics(3)
	var hail: Dictionary = {}
	for h: Dictionary in savari.hails:
		if bool(h.get("scripted", false)):
			hail = h
	_check("A scripted IT commuter waits ahead (and only her)", not hail.is_empty() and savari.hails.size() == 1
		and (hail["archetype"] as PassengerArchetype).id == "it_commuter")
	if hail.is_empty():
		return
	await _park(_road_side_of(hail["pos"] as Vector3), -auto.global_transform.basis.z)
	_check("Stopping beside her opens the haggle", dir.current_step_id() == "haggle" and savari.state == SavariManager.State.HAGGLING, dir.current_step_id())

	# 7. Haggle: she agrees, and her card never times out on a new player.
	await _physics(330) # longer than a normal 5 s haggle
	_check("Scripted haggle does not time out after 5 s", savari.state == SavariManager.State.HAGGLING)
	SignalBus.haggle_choice_made.emit(0)
	await _physics(2)
	var trip: float = float(savari.route.get("length", 0.0))
	_check("Correct Meter is accepted; the GPS ride starts", dir.current_step_id() == "follow_gps" and savari.state == SavariManager.State.RIDING, dir.current_step_id())
	_check("The scripted trip is a short Mylapore ride", trip > 300.0 and trip < 1200.0, "%.0f m" % trip)
	_check("Spotlight moves to the mini-map", overlay.is_spotlight_on())

	# 8–9. Drive to the drop-off and stop inside the ring.
	var dest: Vector3 = savari.destination["pos"]
	await _park(dest, -auto.global_transform.basis.z)
	await _physics(5)
	_check("Dropping her off completes the ride steps", dir.current_step_id() == "free_roam" and _completed.has("drop_off"), dir.current_step_id())
	_check("First savari bonus is paid once", GameState.rewards.granted_ids.has("first_savari") and GameState.wallet_inr >= wallet0 + 100,
		"wallet %d -> %d" % [wallet0, GameState.wallet_inr])

	# 10. Free roam card, then the tutorial ends on its own.
	await _physics(int(7.5 * 60.0))
	_check("Tutorial finishes after the free-roam tip", not dir.is_running() and _finished.size() == 1 and not _finished[0])
	_check("World is back to normal", not GameState.tutorial_active and bool(GameState.settings["first_ride_done"]))
	_check("Analytics saw all 10 steps in order", _completed.size() == 10 and _completed[0] == "kick_start" and _completed[9] == "free_roam", str(_completed))
	_check("Spotlight cleared at the end", not overlay.is_spotlight_on())
	await _physics(30)
	_check("Random riders come back after the tutorial", savari.hails.size() > 0, "%d hails" % savari.hails.size())

	# Crash floor (checked here so the auto is idle).
	GameState.tutorial_active = true
	GameState.tutorial_min_condition = 80.0
	GameState.condition = 100.0
	for i: int in 6:
		SignalBus.player_collision.emit(14.0)
	_check("Crashes during the tutorial never wear the auto below 80 %", GameState.condition >= 80.0, "%.1f" % GameState.condition)
	GameState.tutorial_active = false
	GameState.tutorial_min_condition = 0.0

func _test_replay_and_skip(dir: TutorialDirector) -> void:
	var wallet0: int = GameState.wallet_inr
	SignalBus.tutorial_replay_requested.emit()
	await _physics(3)
	_check("Replay from Settings restarts at step 1", dir.is_running() and dir.current_step_id() == "kick_start")
	SignalBus.tutorial_skip_requested.emit()
	await _physics(2)
	_check("Skip from the pause menu ends it", not dir.is_running() and _finished.back() == true and not GameState.tutorial_active)
	_check("Skipping marks it done (no replay next launch)", bool(GameState.settings["first_ride_done"]))
	_check("Replaying never pays the bonus twice", GameState.wallet_inr == wallet0)
	await _tap("kick_start") # leave the auto running for the next case
	await _physics(34)
	await _tap("kick_start")
	await _physics(34)
	await _tap("kick_start")
	await _physics(4)

func _test_resume(dir: TutorialDirector) -> void:
	_check("Mid-ride save resumes at the pick-up", dir.resume_index(7) == 5 and dir.resume_index(8) == 5)
	_check("Early steps resume where they were", dir.resume_index(3) == 3 and dir.resume_index(0) == 0)
	GameState.settings["first_ride_step"] = 3
	GameState.settings["first_ride_done"] = false
	dir.start(-1)
	await _physics(3)
	_check("Reload resumes at the saved step", dir.is_running() and dir.current_step_id() == "indicate", dir.current_step_id())
	dir.skip()
	await _physics(2)

# --- Helpers ---------------------------------------------------------------------------------------

## Put the auto, stopped, at `pos` facing `fwd`, and let it settle on its wheels.
func _park(pos: Vector3, fwd: Vector3) -> void:
	var f: Vector3 = Vector3(fwd.x, 0.0, fwd.z).normalized()
	var g: RoadGraph = SignalBus.current_road_graph
	var y: float = pos.y
	if g != null:
		var cp: Dictionary = g.closest_point(pos)
		if int(cp["edge"]) >= 0:
			y = g.sample(int(cp["edge"]), float(cp["s"]), 1)[0].y
	SignalBus.teleport_requested.emit(Transform3D(Basis.looking_at(f, Vector3.UP), Vector3(pos.x, y + 0.8, pos.z)))
	await _physics(80)

## A point on the carriageway next to a kerb-side rider (inside the pick-up radius).
func _road_side_of(hail_pos: Vector3) -> Vector3:
	var g: RoadGraph = SignalBus.current_road_graph
	var cp: Dictionary = g.closest_point(hail_pos)
	var centre: Vector3 = g.sample(int(cp["edge"]), float(cp["s"]), 1)[0]
	var to_c: Vector3 = Vector3(centre.x - hail_pos.x, 0.0, centre.z - hail_pos.z)
	return hail_pos + to_c.normalized() * minf(3.0, to_c.length())

func _tap(action: String) -> void:
	Input.action_press(action)
	await _physics(2)
	Input.action_release(action)
	await _physics(1)

func _physics(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame

func _check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  PASS  ", name)
	else:
		_failed += 1
		print("  FAIL  ", name, ("  (" + detail + ")") if detail != "" else "")
