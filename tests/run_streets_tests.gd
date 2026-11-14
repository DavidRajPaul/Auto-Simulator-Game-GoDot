extends Node
## Roads, paved plots, compound walls and street ambience (shaders/street_surface.gdshader,
## tools/osm/build_plots.py, tools/art/make_ground_detail.py, scripts/world/AmbienceAudio.gd).
## Run: godot --headless --path . res://tests/run_streets_tests.tscn

var _passed: int = 0
var _failed: int = 0

func _ready() -> void:
	print("\n=== Namma Auto — streets, plots and ambience tests ===")
	_run.call_deferred()

func _run() -> void:
	_test_texture_and_shader()
	_test_plot_data()
	_test_surface_mesh()
	_test_walls_and_gates()
	await _test_city()
	print("\n=== %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)

func _test_texture_and_shader() -> void:
	var img: Image = Image.load_from_file(ProjectSettings.globalize_path("res://assets/textures/ground_detail.png"))
	_check("Ground detail texture is 1024 x 1024 RGBA", img != null and img.get_width() == 1024 and img.get_format() == Image.FORMAT_RGBA8)
	if img != null:
		var sum: Color = Color(0, 0, 0, 0)
		var seam: float = 0.0
		for i: int in 256:
			var c: Color = img.get_pixel(i * 4, (i * 37) % 1024)
			sum += c
		for y: int in range(0, 1024, 16):
			seam += absf(img.get_pixel(0, y).b - img.get_pixel(1023, y).b) / 64.0
		_check("Detail maps average mid-grey, so vertex colours keep their tone",
			absf(sum.r / 256.0 - 0.5) < 0.06 and absf(sum.g / 256.0 - 0.5) < 0.08 and absf(sum.b / 256.0 - 0.5) < 0.06, str(sum / 256.0))
		_check("Concrete map wraps left to right without a seam", seam < 0.08, "%.3f" % seam)
	var imp: String = FileAccess.get_file_as_string("res://assets/textures/ground_detail.png.import")
	_check("Ground detail ships compressed with mipmaps", imp.contains("compress/mode=2") and imp.contains("mipmaps/generate=true"))
	var sh: String = FileAccess.get_file_as_string("res://shaders/street_surface.gdshader")
	_check("Street shader costs at most two texture lookups", sh.count("texture(") == 2)
	_check("Street shader keeps the monsoon wet look", sh.contains("uniform float wet"))

func _test_plot_data() -> void:
	var files: PackedStringArray = DirAccess.get_files_at("res://data/world/plots")
	var walls: int = 0
	var gates: int = 0
	var tris: int = 0
	var bad: int = 0
	var short: int = 0
	var biggest: int = 0
	for file_name: String in files:
		var text: String = FileAccess.get_file_as_string("res://data/world/plots/" + file_name)
		biggest = maxi(biggest, text.length())
		var d: Dictionary = JSON.parse_string(text) as Dictionary
		for w: Array in (d.get("walls", []) as Array) + (d.get("gates", []) as Array):
			if w.size() != 9 or not BuildingStyles.TYPES.has(str(w[6])) or int(w[8]) < 0 or int(w[8]) >= BuildingStyles.ZONE_IDS.size():
				bad += 1
			if Vector2(float(w[0]), float(w[1])).distance_to(Vector2(float(w[2]), float(w[3]))) < 0.25:
				short += 1
		walls += (d.get("walls", []) as Array).size()
		gates += (d.get("gates", []) as Array).size()
		for cls: String in (d.get("pave", {}) as Dictionary):
			if not WorldChunkStreamer.PAVE_STYLE.has(cls):
				bad += 1
			tris += ((d["pave"] as Dictionary)[cls]["i"] as Array).size() / 3
	_check("Plots exist for most chunks", files.size() > 400, str(files.size()))
	_check("Tens of thousands of compound wall runs and thousands of gates", walls > 20000 and gates > 6000, "%d walls, %d gates" % [walls, gates])
	_check("Every wall and gate carries its building's type, seed and zone", bad == 0, "%d bad" % bad)
	_check("No stub walls", short == 0, "%d" % short)
	_check("Paving stays light: under 700 triangles a chunk on average", tris > 100000 and tris / maxi(1, files.size()) < 700, "%d total" % tris)
	_check("No plot file passes 150 KB", biggest < 150000, "%d bytes" % biggest)
	var preset: String = FileAccess.get_file_as_string("res://export_presets.cfg")
	_check("Plots are exported with the world data", preset.contains("data/world/*"))

func _test_surface_mesh() -> void:
	var s: WorldChunkStreamer = WorldChunkStreamer.new()
	s._street_mat = ShaderMaterial.new()
	var surf: Dictionary = {"road": {"v": [0, 0, 10, 0, 10, 10], "i": [0, 1, 2]}, "walk": {"v": [0, 0, 5, 0, 5, 5], "i": [0, 1, 2]},
		"lane": {"v": [1, 1, 2, 1, 2, 2], "i": [0, 1, 2]}}
	var pave: Dictionary = {"cement": {"v": [20, 0, 30, 0, 30, 10], "i": [0, 1, 2]}, "paver": {"v": [40, 0, 50, 0, 50, 10], "i": [0, 1, 2]}}
	var mesh: ArrayMesh = s._surface_mesh(surf, pave)
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var kinds: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var seen: Dictionary = {}
	var lowest_road: float = 9.0
	var highest_plot: float = -9.0
	for i: int in verts.size():
		seen[int(kinds[i].x)] = true
		if kinds[i].x < 2.5:
			lowest_road = minf(lowest_road, verts[i].y)
		else:
			highest_plot = maxf(highest_plot, verts[i].y)
	_check("Roads, footpath, paint, cement and pavers share one mesh", mesh.get_surface_count() == 1 and seen.size() == 5, str(seen.keys()))
	_check("Paving lies under the road layers but above the park and water layers", highest_plot < lowest_road - 0.025 and highest_plot > -0.02 + 0.025,
		"%.3f vs %.3f" % [highest_plot, lowest_road])
	_check("Surface mesh uses the street material", mesh.surface_get_material(0) == s._street_mat)
	_check("A chunk with paving but no road still draws", s._surface_mesh({}, pave) != null and s._surface_mesh({}, {}) == null)
	s.free()

func _test_walls_and_gates() -> void:
	var s: WorldChunkStreamer = WorldChunkStreamer.new()
	s._bld_mat = ShaderMaterial.new()
	var wall: Array = [0.0, 0.0, 10.0, 0.0, 1.7, 0.23, "fl", 1234, 0]
	var gate: Array = [10.0, 0.0, 13.2, 0.0, 1.7, 0.1, "fl", 1234, 0]
	var holder: Node3D = s._buildings([], {}, [], [wall], [gate])
	var mi: MeshInstance3D = holder.get_node("BuildingMeshes") as MeshInstance3D
	var arrays: Array = mi.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	var top: float = 0.0
	var wall_run: int = 0
	var gate_leaf: int = 0
	for i: int in verts.size():
		top = maxf(top, verts[i].y)
		if uv2[i] == BuildingStyles.COMPOUND:
			if uv[i].y >= 0.5:
				wall_run += 1
			elif uv[i].x <= 0.5:
				gate_leaf += 1
	_check("Compound wall is drawn from the wall run of the atlas, on both faces", wall_run >= 12, "%d verts" % wall_run)
	_check("Gate has two steel leaves on both faces", gate_leaf == 24, "%d verts" % gate_leaf)
	_check("Gate piers stand a little above the wall", top > 1.7 + 0.2 and top < 2.4, "%.2f" % top)
	_check("Wall and gate stay in the one building mesh (%d vertices)" % verts.size(), mi.mesh.get_surface_count() == 1 and verts.size() < 400)
	var shape: CollisionShape3D = null
	for c: Node in holder.get_children():
		if c is CollisionShape3D:
			shape = c as CollisionShape3D
	_check("Wall and gate are solid", shape != null and (shape.shape as ConcavePolygonShape3D).get_faces().size() >= 24)
	var temple: Node3D = s._buildings([], {}, [], [[0.0, 0.0, 10.0, 0.0, 2.1, 0.23, "tp", 5, 2]], [])
	var tuv2: PackedVector2Array = (temple.get_node("BuildingMeshes") as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV2]
	_check("Temple compound walls are kaavi striped", tuv2.has(BuildingStyles.KAAVI))
	var mask: PackedByteArray = s._building_mask(Vector2i(0, 0), [], [wall, gate])
	var n: int = int(ceil(s.chunk_size / WorldChunkStreamer.BLOCK_CELL_M))
	_check("Walkers treat walls and gates as solid", mask[int(0.2 / WorldChunkStreamer.BLOCK_CELL_M) * n + int(5.0 / WorldChunkStreamer.BLOCK_CELL_M)] == 1
		and mask[int(0.2 / WorldChunkStreamer.BLOCK_CELL_M) * n + int(11.5 / WorldChunkStreamer.BLOCK_CELL_M)] == 1)
	holder.free()
	temple.free()
	s.free()

func _test_city() -> void:
	GameState.reset_profile()
	var city: Node = (load("res://scenes/main_chennai.tscn") as PackedScene).instantiate()
	add_child(city)
	for i: int in 20:
		await get_tree().physics_frame
	var world: WorldChunkStreamer = city.get_node("World") as WorldChunkStreamer
	var with_walls: int = 0
	var road_nodes: int = 0
	for k: Vector2i in world.loaded:
		var chunk: Node3D = world.loaded[k] as Node3D
		if chunk == null:
			continue
		var roads: MeshInstance3D = chunk.get_node_or_null("Roads") as MeshInstance3D
		if roads != null:
			road_nodes += 1
			if roads.mesh.get_surface_count() != 1 or roads.mesh.surface_get_material(0) != world._street_mat:
				road_nodes = -999
		if FileAccess.file_exists("res://data/world/plots/c_%d_%d.json" % [k.x, k.y]):
			with_walls += 1
	_check("Loaded chunks draw their streets with the street material, one surface each", road_nodes > 4, str(road_nodes))
	_check("Loaded chunks have plots", with_walls > 4, str(with_walls))
	_check("Open ground uses the same shader with its own kind", world._ground_mat != null
		and is_equal_approx(float(world._ground_mat.get_shader_parameter("fixed_kind")), WorldChunkStreamer.GROUND_KIND))
	GameState.set_rain(true, 30.0)
	for i: int in 30:
		await get_tree().process_frame
	_check("Rain wets the street material", float(world._street_mat.get_shader_parameter("wet")) > 0.0)
	GameState.set_rain(false, 0.0)

	# --- ambience ---
	var amb: AmbienceAudio = city.get_node("AmbienceAudio") as AmbienceAudio
	for kind: String in ["crows", "birds", "night"]:
		_check("Ambience loop '%s' is loaded and playing" % kind, amb.players.has(kind))
	for kind: String in AmbienceAudio.SHOTS:
		_check("One-shot '%s' is loaded" % kind, amb.shot_streams.has(kind))
	amb._player_pos = Vector3(-200.0, 0.0, 600.0)   # a residential street
	GameState.shift_minute = 400.0   # 6:40 am
	var dawn: Dictionary = amb.targets()
	GameState.shift_minute = 720.0   # noon
	var noon: Dictionary = amb.targets()
	GameState.shift_minute = 1230.0  # 8:30 pm
	var night: Dictionary = amb.targets()
	_check("Birds sing at dawn and stop by noon", float(dawn["birds"]) > 0.5 and float(noon["birds"]) == 0.0, "%s / %s" % [dawn["birds"], noon["birds"]])
	_check("Crows call all day and roost at night", float(noon["crows"]) > 0.4 and float(night["crows"]) == 0.0)
	_check("Insects come out after dark only", float(night["night"]) > 0.5 and float(noon["night"]) == 0.0)
	var temple: Vector2 = amb._temples[0]
	amb._player_pos = Vector3(temple.x + 20.0, 0.0, temple.y)
	var near_bell: float = float(amb.shot_levels()["temple_bell"])
	amb._player_pos = Vector3(temple.x + 3000.0, 0.0, temple.y + 9000.0)
	_check("Temple bell is heard near a temple and not far from one", near_bell > 0.4 and float(amb.shot_levels()["temple_bell"]) == 0.0, "%.2f" % near_bell)
	_check("Street dogs bark at night only", float(amb.shot_levels()["dogs"]) > 0.5)
	GameState.shift_minute = 720.0
	_check("…and a cycle bell rings by day only", float(amb.shot_levels()["dogs"]) == 0.0 and float(amb.shot_levels()["cycle_bell"]) > 0.3)
	_check("A one-shot plays on a pooled voice", amb.play_shot("cycle_bell", 0.8) and amb.last_shot == "cycle_bell")
	GameState.set_rain(true, 30.0)
	_check("Rain silences crows and dogs", float(amb.targets()["crows"]) == 0.0 and float(amb.shot_levels()["cycle_bell"]) == 0.0)
	GameState.set_rain(false, 0.0)
	_check("No nodes are created for one-shots while driving", amb._shot_voices.size() == AmbienceAudio.SHOT_VOICES)
	await _test_thunderstorm(city)
	city.queue_free()

## Nov 14 thunder and lightning (scripts/world/Thunderstorm.gd): storms only in rain, the flash
## lights the street, the ambient, the fog and the sky and then lets go, thunder comes d / 343 s
## later, and a close strike cracks loud and bright while a far one only rumbles, low and quiet.
func _test_thunderstorm(city: Node) -> void:
	var ts: Thunderstorm = city.get_node_or_null("Thunderstorm") as Thunderstorm
	_check("Thunderstorm runs in the city", ts != null)
	if ts == null:
		return
	var env: Environment = (city.get_node("WorldEnvironment") as WorldEnvironment).environment
	var sky: ShaderMaterial = env.sky.sky_material as ShaderMaterial
	_check("Lightning light, bolt and thunder voices are built once, idle and hidden",
		not ts.light.visible and not ts.bolt.visible and ts.voices.size() == Thunderstorm.THUNDER_VOICES and not ts.light.shadow_enabled)
	var pools_ok: bool = true
	for p: String in Thunderstorm.POOLS:
		pools_ok = pools_ok and not (ts.pools[p] as PackedStringArray).is_empty()
	_check("Real thunder recordings loaded for close, mid and far strikes", pools_ok, str(ts.pools))
	GameState.thunder_override = -1
	GameState.set_rain(false, 0.0)
	var before: int = ts.strike_count
	for i: int in 120:
		await get_tree().process_frame
	_check("No lightning without rain", not GameState.is_thunderstorm() and ts.strike_count == before)
	# Distance rules.
	_check("Thunder gets quieter with distance, from loud overhead to faint far off",
		Thunderstorm.thunder_db(200.0) > Thunderstorm.thunder_db(1000.0) and Thunderstorm.thunder_db(1000.0) > Thunderstorm.thunder_db(8000.0)
		and Thunderstorm.thunder_db(200.0) > -3.0 and Thunderstorm.thunder_db(9000.0) < -20.0,
		"%.1f / %.1f / %.1f dB" % [Thunderstorm.thunder_db(200.0), Thunderstorm.thunder_db(1000.0), Thunderstorm.thunder_db(8000.0)])
	_check("Air takes the highs: a close crack is bright, a far roll is only bass",
		Thunderstorm.thunder_cutoff_hz(250.0) > 10000.0 and Thunderstorm.thunder_cutoff_hz(8000.0) < 1000.0)
	_check("Close, mid and far strikes pick their own recordings",
		Thunderstorm.pool_for(400.0) == "close" and Thunderstorm.pool_for(3000.0) == "mid" and Thunderstorm.pool_for(9000.0) == "far")
	_check("The sky glow carries further than the light on the street",
		Thunderstorm.sky_falloff(6000.0) > Thunderstorm.light_falloff(6000.0) * 2.0)
	var children: int = ts.get_child_count()
	var heard: Array[float] = []
	var cb: Callable = func(_at: Vector3, d: float, _g: bool) -> void: heard.append(d)
	SignalBus.lightning_struck.connect(cb)
	# A close ground strike to the camera's right.
	var base_amb: float = env.ambient_light_energy
	var base_fog: float = env.fog_light_energy
	var cam: Camera3D = get_viewport().get_camera_3d()
	var right: Vector3 = cam.global_transform.basis.x if cam != null else Vector3.RIGHT
	var bearing: float = atan2(right.z, right.x)
	ts.strike(343.0 * 1.5, bearing, true)
	await get_tree().process_frame
	await get_tree().process_frame
	var lit: float = ts.light.light_energy
	_check("A close strike lights the street: light, ambient, fog and sky all flash",
		ts.light.visible and lit > 0.5 and env.ambient_light_energy > base_amb * 1.5 and env.fog_light_energy > base_fog * 1.3
		and float(sky.get_shader_parameter("flash")) > 0.3,
		"light %.2f amb %.2f/%.2f fog %.2f sky %.2f" % [lit, env.ambient_light_energy, base_amb, env.fog_light_energy, float(sky.get_shader_parameter("flash"))])
	_check("A ground strike shows its bolt", ts.bolt.visible and ts.bolt.mesh.get_surface_count() == 1)
	_check("The light comes from the strike's side, from above", ts.flash_dir.y > 0.3 and ts.flash_dir.dot(right) > 0.3)
	_check("Every strike is announced on the SignalBus", heard.size() == 1 and is_equal_approx(heard[0], 343.0 * 1.5))
	# The flash flickers and dies; the thunder has not arrived yet.
	for i: int in 60:
		await get_tree().process_frame
	_check("The flash is over within a second and everything returns to normal",
		not ts.light.visible and not ts.bolt.visible and is_equal_approx(env.ambient_light_energy, base_amb)
		and is_equal_approx(env.fog_light_energy, base_fog) and float(sky.get_shader_parameter("flash")) == 0.0)
	_check("Thunder is still on its way after one second (sound is slower than light)", ts.pending.size() == 1)
	for i: int in 36:
		await get_tree().process_frame
	_check("Thunder arrives distance / 343 s after the flash", ts.pending.is_empty() and float(ts.last_thunder.get("distance_m", 0.0)) > 500.0)
	var close_file: String = str(ts.last_thunder.get("file", ""))
	_check("A close strike cracks: a close recording, loud and bright, panned to its side",
		(ts.pools["close"] as PackedStringArray).has(close_file) and float(ts.last_thunder["db"]) > -8.0
		and float(ts.last_thunder["cutoff_hz"]) > 5000.0 and float(ts.last_thunder["pan"]) > 0.3, str(ts.last_thunder))
	var playing: bool = false
	for v: AudioStreamPlayer in ts.voices:
		playing = playing or v.playing
	_check("…and it is playing", playing)
	# A far strike inside the cloud: dim, no bolt, a quiet low rumble.
	ts.strike(8000.0, bearing + PI, false)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("A far cloud flash lights the sky more than the street, and shows no bolt",
		not ts.bolt.visible and ts.light.light_energy < lit * 0.2 and float(sky.get_shader_parameter("flash")) > 0.05,
		"light %.3f sky %.3f" % [ts.light.light_energy, float(sky.get_shader_parameter("flash"))])
	ts._t += 8000.0 / Thunderstorm.SPEED_OF_SOUND_MPS
	await get_tree().process_frame
	_check("A far strike only rumbles: a far recording, quiet and low",
		(ts.pools["far"] as PackedStringArray).has(str(ts.last_thunder.get("file", ""))) and float(ts.last_thunder["db"]) < -18.0
		and float(ts.last_thunder["cutoff_hz"]) < 1000.0 and float(ts.last_thunder["pan"]) < 0.0, str(ts.last_thunder))
	SignalBus.lightning_struck.disconnect(cb)
	# A storm day: strikes come by themselves, closest in the middle of the rain.
	GameState.thunder_override = 1
	GameState.set_rain(true, 120.0)
	var start: int = ts.strike_count
	for i: int in 9 * 60:
		await get_tree().process_frame
	_check("In a thunderstorm the lightning comes by itself", GameState.is_thunderstorm() and ts.strike_count > start, "%d strikes" % (ts.strike_count - start))
	GameState.shift_minute = GameState.rain_window.x + 3.0
	var edge: float = ts.storm_centre_m()
	GameState.shift_minute = (GameState.rain_window.x + GameState.rain_window.y) * 0.5
	var middle: float = ts.storm_centre_m()
	_check("The storm builds, passes closest mid-rain and moves on", middle < edge * 0.5, "%.0f m / %.0f m" % [middle, edge])
	_check("No nodes are created by strikes", ts.get_child_count() == children)
	GameState.thunder_override = -1
	GameState.set_rain(false, 0.0)
	for i: int in 90:
		await get_tree().process_frame

func _check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  PASS  " + name)
	else:
		_failed += 1
		print("  FAIL  " + name + ("" if detail == "" else "  (" + detail + ")"))
