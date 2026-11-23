extends Node
## Smoothness: frame pacing decisions (FramePacer), FrameGuard wiring, hitch log, project
## settings that keep motion smooth, and a scan that keeps loads / spawns / new materials out
## of per-frame code.
## Run: godot --headless --path . --fixed-fps 60 res://tests/run_smoothness_tests.tscn

const MS_60: float = 1000.0 / 60.0
const MS_30: float = 1000.0 / 30.0
## Per-frame functions that must never load, spawn, free or build materials.
const HOT_FUNCS: Array[String] = ["_process", "_physics_process", "_integrate_forces"]
const HOT_PATTERNS: Array[String] = ["instantiate(", "queue_free(", " load(", "(load(", "ResourceLoader.load(",
	"ShaderMaterial.new(", "StandardMaterial3D.new(", "ORMMaterial3D.new(", "Image.create(", "Image.load("]
## Loading screens are allowed to load in _process (that is their job).
const HOT_ALLOW: Array[String] = ["res://scripts/ui/SplashScreen.gd", "res://scripts/ui/LoadingScreen.gd"]

var _passed: int = 0
var _failed: int = 0

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	print("\n=== Namma Auto — Smoothness tests ===")
	_test_project_settings()
	_test_pacer_steady()
	_test_pacer_lowers_resolution_then_falls_back()
	_test_pacer_returns_to_60_with_backoff()
	_test_pacer_raises_resolution_when_calm()
	_test_pacer_locked_modes()
	_test_pacer_ignores_pauses()
	_test_frame_guard_wiring()
	_test_frame_guard_summary_and_log()
	_test_hot_paths()
	print("\n=== %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)

## Feeds frames for `seconds` (or until `stop` returns true). Returns how many changes it made.
func _feed(p: FramePacer, seconds: float, pattern: Array[float], work_ms: float = -1.0, stop: Callable = Callable()) -> int:
	var changes: int = 0
	var t: float = 0.0
	var i: int = 0
	while t < seconds and not (stop.is_valid() and bool(stop.call())):
		var ms: float = pattern[i % pattern.size()]
		if p.feed(ms, work_ms):
			changes += 1
		t += ms / 1000.0
		i += 1
	return changes

func _test_project_settings() -> void:
	_check("Physics runs at 60 Hz", int(ProjectSettings.get_setting("physics/common/physics_ticks_per_second")) == 60)
	_check("Physics interpolation is on", bool(ProjectSettings.get_setting("physics/common/physics_interpolation")))
	var steps: int = int(ProjectSettings.get_setting("physics/common/max_physics_steps_per_frame"))
	_check("A slow frame catches up at most 4 physics ticks", steps <= 4, str(steps))
	_check("Mobile (Vulkan) renderer: ubershaders + Swappy frame pacing", str(ProjectSettings.get_setting("rendering/renderer/rendering_method.mobile")) == "mobile")
	_check("Frame cap starts at 60", int(ProjectSettings.get_setting("application/run/max_fps")) == 60)
	_check("FrameGuard autoload is loaded", get_node_or_null("/root/FrameGuard") != null)

func _test_pacer_steady() -> void:
	var p: FramePacer = FramePacer.new()
	var changes: int = _feed(p, 30.0, [MS_60], 9.0)
	_check("Steady 60 FPS: nothing changes", changes == 0 and p.target_fps == 60 and is_equal_approx(p.factor, 1.0), "%d %d %.2f" % [changes, p.target_fps, p.factor])

func _test_pacer_lowers_resolution_then_falls_back() -> void:
	var p: FramePacer = FramePacer.new()
	# Every 4th frame misses its vsync (25 % missed): too slow for 60.
	_feed(p, 4.0, [MS_60, MS_60, MS_60, MS_60 * 2.0])
	_check("Missed frames lower the 3D resolution a step first", p.factor < 1.0 and p.target_fps == 60, "%.2f" % p.factor)
	_feed(p, 30.0, [MS_60, MS_60, MS_60, MS_60 * 2.0], -1.0, func() -> bool: return p.factor <= FramePacer.MIN_FACTOR + 0.001 or p.target_fps == 30)
	_check("…step by step down to the floor, still at 60", is_equal_approx(p.factor, FramePacer.MIN_FACTOR) and p.target_fps == 60, "%.2f %d" % [p.factor, p.target_fps])
	_feed(p, FramePacer.FALLBACK_AFTER_S + 2.0, [MS_60, MS_60, MS_60, MS_60 * 2.0])
	_check("Still missing at the floor → steady 30 FPS at full resolution", p.target_fps == 30 and is_equal_approx(p.factor, 1.0) and p.fallbacks == 1,
		"%d %.2f %d" % [p.target_fps, p.factor, p.fallbacks])

func _test_pacer_returns_to_60_with_backoff() -> void:
	var p: FramePacer = FramePacer.new()
	_feed(p, 40.0, [MS_60 * 2.0]) # far too slow → falls back
	_check("Heavy load ends at 30", p.target_fps == 30, str(p.target_fps))
	_feed(p, 30.0, [MS_30], 8.0)
	_check("No retry of 60 before the wait is over", p.target_fps == 30)
	_feed(p, FramePacer.RETRY_60_S, [MS_30], 8.0, func() -> bool: return p.target_fps == 60)
	_check("Lots of headroom at 30 → tries 60 again at a lower resolution", p.target_fps == 60 and is_equal_approx(p.factor, FramePacer.RETRY_FACTOR),
		"%d %.2f" % [p.target_fps, p.factor])
	_feed(p, 40.0, [MS_60 * 2.0])
	_check("Falls back again (fallback 2)", p.target_fps == 30 and p.fallbacks == 2, "%d %d" % [p.target_fps, p.fallbacks])
	_feed(p, FramePacer.RETRY_60_S + 15.0, [MS_30], 8.0, func() -> bool: return p.target_fps == 60)
	_check("Second retry waits twice as long (no flip-flopping)", p.target_fps == 30)
	_feed(p, FramePacer.RETRY_60_S, [MS_30], 8.0, func() -> bool: return p.target_fps == 60)
	_check("…then tries 60 again", p.target_fps == 60)
	var busy: FramePacer = FramePacer.new()
	_feed(busy, 40.0, [MS_60 * 2.0])
	_feed(busy, 200.0, [MS_30], 14.0)
	_check("Without headroom (14 ms work) it stays at a steady 30", busy.target_fps == 30)

func _test_pacer_raises_resolution_when_calm() -> void:
	var p: FramePacer = FramePacer.new()
	_feed(p, 7.0, [MS_60, MS_60, MS_60 * 2.0])
	var low: float = p.factor
	_feed(p, 40.0, [MS_60], 8.0)
	_check("Calm frames with spare time raise the resolution again", p.factor > low, "%.2f → %.2f" % [low, p.factor])
	var q: FramePacer = FramePacer.new()
	_feed(q, 7.0, [MS_60, MS_60, MS_60 * 2.0])
	var low_q: float = q.factor
	_feed(q, 40.0, [MS_60], 15.0)
	_check("…but not when the work nearly fills the frame", is_equal_approx(q.factor, low_q), "%.2f → %.2f" % [low_q, q.factor])

func _test_pacer_locked_modes() -> void:
	var p: FramePacer = FramePacer.new()
	p.set_mode(FramePacer.Mode.LOCK_30)
	_check("Smooth 30 caps at 30", p.target_fps == 30)
	_feed(p, 200.0, [MS_30], 4.0)
	_check("Smooth 30 never goes back to 60", p.target_fps == 30)
	var q: FramePacer = FramePacer.new()
	q.set_mode(FramePacer.Mode.LOCK_60)
	_feed(q, 60.0, [MS_60 * 2.0])
	_check("Always 60 never drops to 30, only lowers resolution", q.target_fps == 60 and is_equal_approx(q.factor, FramePacer.MIN_FACTOR),
		"%d %.2f" % [q.target_fps, q.factor])

func _test_pacer_ignores_pauses() -> void:
	var p: FramePacer = FramePacer.new()
	for i: int in 50:
		p.feed(900.0, -1.0) # resume from an ad, a call, a load
	_feed(p, 2.0, [MS_60], 8.0)
	_check("Loading / resume pauses are not counted as load", is_equal_approx(p.factor, 1.0) and p.target_fps == 60)

func _test_frame_guard_wiring() -> void:
	_check("Tests never adapt the frame rate (headless / test run)", not FrameGuard.adaptive and not FrameGuard.measuring)
	var gfx: int = clampi(int(GameState.settings.get("graphics", 1)), 0, 2)
	var old_max: int = Engine.max_fps
	FrameGuard.adaptive = true
	GameState.set_setting("frame_rate", 1)
	_check("Setting 'Smooth 30' caps the engine at 30", Engine.max_fps == 30, str(Engine.max_fps))
	FrameGuard.pacer.factor = 0.8
	FrameGuard._apply()
	_check("Dynamic factor multiplies the preset's 3D scale", is_equal_approx(get_tree().root.scaling_3d_scale, GameState.GRAPHICS_SCALE[gfx] * 0.8),
		"%.3f" % get_tree().root.scaling_3d_scale)
	GameState.set_setting("graphics", gfx)
	_check("Changing graphics keeps the dynamic factor", is_equal_approx(get_tree().root.scaling_3d_scale, GameState.GRAPHICS_SCALE[gfx] * 0.8))
	GameState.set_setting("frame_rate", 0)
	_check("Back to Auto: 60 at full preset scale", Engine.max_fps == 60 and is_equal_approx(get_tree().root.scaling_3d_scale, GameState.GRAPHICS_SCALE[gfx]))
	FrameGuard.adaptive = false
	Engine.max_fps = old_max

func _test_frame_guard_summary_and_log() -> void:
	FrameGuard.reset_stats()
	for i: int in 99:
		FrameGuard._record(MS_60, 0, self)
	FrameGuard._record(50.0, 2, self)
	var s: Dictionary = FrameGuard.summary()
	_check("Summary counts frames", int(s["frames"]) == 100, str(s["frames"]))
	_check("Worst frame and hitch are counted", is_equal_approx(float(s["worst_ms"]), 50.0) and FrameGuard.hitches == 1 and FrameGuard.compiles_in_play == 2)
	_check("1 % low reflects the hitch", float(s["low1_fps"]) < 25.0, "%.1f" % float(s["low1_fps"]))
	_check("Recent frames come back oldest first", FrameGuard.recent_frames(2) == PackedFloat32Array([MS_60, 50.0]))
	_check("Report text carries the key numbers", FrameGuard.report_text().contains("1% low") and FrameGuard.report_text().contains("pipeline compiles"))
	# Hitch log round trip (measuring is off in tests; switch it on just for this).
	FrameGuard.measuring = true
	FrameGuard._start_log()
	FrameGuard._record(48.0, 0, self)
	FrameGuard.flush_log()
	var text: String = FileAccess.get_file_as_string(FrameGuard.LOG_PATH)
	var lines: PackedStringArray = text.strip_edges().split("\n")
	_check("Hitch log: header + one line per hitch, written in a batch", lines.size() == 2 and lines[0] == FrameGuard.LOG_HEADER and lines[1].contains(",48.0,"), text)
	FrameGuard.measuring = false
	DirAccess.remove_absolute(FrameGuard.LOG_PATH)
	FrameGuard.reset_stats()

func _test_hot_paths() -> void:
	var offences: PackedStringArray = PackedStringArray()
	var files: PackedStringArray = PackedStringArray()
	_collect("res://scripts", files)
	_collect("res://autoloads", files)
	for path: String in files:
		if HOT_ALLOW.has(path):
			continue
		var current: String = ""
		var n: int = 0
		for line: String in FileAccess.get_file_as_string(path).split("\n"):
			n += 1
			if line.begins_with("func ") or line.begins_with("static func "):
				current = line.trim_prefix("static ").trim_prefix("func ").get_slice("(", 0).strip_edges()
				continue
			if not HOT_FUNCS.has(current):
				continue
			var code: String = line.get_slice("#", 0)
			for pat: String in HOT_PATTERNS:
				if code.contains(pat):
					offences.append("%s:%d %s" % [path, n, line.strip_edges()])
	_check("No load / instantiate / queue_free / new material inside _process, _physics_process or _integrate_forces",
		offences.is_empty(), "\n      ".join(offences))
	_check("Scanned the game's scripts", files.size() > 50, str(files.size()))

func _collect(dir: String, out: PackedStringArray) -> void:
	for f: String in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d: String in DirAccess.get_directories_at(dir):
		_collect(dir.path_join(d), out)

func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  PASS  %s" % label)
	else:
		_failed += 1
		print("  FAIL  %s  %s" % [label, detail])
