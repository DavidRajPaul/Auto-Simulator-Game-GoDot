extends Node
## FrameGuard: keeps frames landing on time on the phone, and records every hitch.
##
## * Adaptive pacing (Android only, never in tests or headless runs): feeds each frame to
##   FramePacer, then applies its frame-rate cap (Engine.max_fps, which Godot's Swappy frame
##   pacing uses as the target) and its dynamic-resolution factor (GameState.dynamic_res_factor).
##   This is the ONLY code that changes Engine.max_fps or the dynamic factor.
## * Settings "frame_rate": 0 Auto (60, falls back to a steady 30 when the phone can't keep up or
##   gets hot), 1 Smooth 30, 2 Always 60.
## * Hitch log: every frame over HITCH_MS after the scene has warmed up goes to
##   user://perf/hitches.csv (written in batches, never on the hitch frame itself), with draw
##   calls, pipeline compiles, render scale, scene and camera position. report_text() is the
##   summary the debug overlay copies to the clipboard for a bug report.
## * Loading and resume: the first WARMUP_FRAMES after a scene change and GRACE_S after the app
##   returns from the background (ads, calls) are not counted as hitches or as load.

const HITCH_MS: float = 33.4
const WARMUP_FRAMES: int = 180
const GRACE_S: float = 1.5
const RING_SIZE: int = 3600 # one minute at 60 FPS
const LOG_DIR: String = "user://perf"
const LOG_PATH: String = "user://perf/hitches.csv"
const LOG_HEADER: String = "session_s,frame_ms,fps_cap,pipeline_compiles,render_scale,draw_calls,objects,scene,cam_x,cam_z"
const FLUSH_EVERY_S: float = 10.0
const MAX_LOG_LINES: int = 2000
const PIPELINE_MONITORS: Array[int] = [Performance.PIPELINE_COMPILATIONS_CANVAS, Performance.PIPELINE_COMPILATIONS_MESH,
	Performance.PIPELINE_COMPILATIONS_SURFACE, Performance.PIPELINE_COMPILATIONS_DRAW, Performance.PIPELINE_COMPILATIONS_SPECIALIZATION]

var pacer: FramePacer = FramePacer.new()
## Adjusts cap and resolution (Android phones). Tests may switch it on to check the wiring.
var adaptive: bool = false
## Measures and logs hitches (any run with a real display outside the test suites).
var measuring: bool = false

## Stats since the scene warmed up (reset on scene change).
var hitches: int = 0
var worst_ms: float = 0.0
var compiles_in_play: int = 0
var frame_ring: PackedFloat32Array = PackedFloat32Array()
var ring_head: int = 0
var ring_count: int = 0

var _last_usec: int = 0
var _warmup: int = WARMUP_FRAMES
var _grace_s: float = 0.0
var _scene_id: int = 0
var _compiles_seen: int = 0
var _pending: PackedStringArray = PackedStringArray()
var _logged: int = 0
var _flush_s: float = 0.0
var _session_s: float = 0.0
var _vp_rid: RID
var _first_sync: bool = true

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -100 # measure before the game's own _process work
	if OS.is_debug_build() and ResourceLoader.exists("res://scripts/devtools/DevTools.gd"): # DEVTOOLS-HOOK (dev only, never on release/*)
		var dev: Node = (load("res://scripts/devtools/DevTools.gd") as GDScript).new() as Node # DEVTOOLS-HOOK
		add_child(dev) # DEVTOOLS-HOOK
	frame_ring.resize(RING_SIZE)
	var headless: bool = DisplayServer.get_name() == "headless"
	measuring = not headless and GameState.persistence_enabled
	adaptive = measuring and OS.get_name() == "Android"
	_vp_rid = get_viewport().get_viewport_rid()
	if adaptive:
		RenderingServer.viewport_set_measure_render_time(_vp_rid, true)
	if measuring:
		_start_log()
	SignalBus.settings_changed.connect(func(_s: Dictionary) -> void: _sync_mode())
	_sync_mode()

## Picks up the "frame_rate" setting (only when it changed, so other settings don't reset pacing).
func _sync_mode() -> void:
	var m: int = clampi(int(GameState.settings.get("frame_rate", 0)), 0, 2)
	if m != pacer.mode or _first_sync:
		_first_sync = false
		pacer.set_mode(m)
		_apply()

func _apply() -> void:
	if not adaptive:
		return
	Engine.max_fps = pacer.target_fps
	GameState.dynamic_res_factor = pacer.factor
	GameState.apply_render_scale()

func _process(_delta: float) -> void:
	var now: int = Time.get_ticks_usec()
	var frame_ms: float = float(now - _last_usec) / 1000.0 if _last_usec > 0 else 0.0
	_last_usec = now
	if not measuring:
		return
	_session_s += frame_ms / 1000.0
	var compiles: int = _pipeline_compiles()
	var new_compiles: int = maxi(compiles - _compiles_seen, 0)
	_compiles_seen = compiles
	var scene: Node = get_tree().current_scene
	var sid: int = scene.get_instance_id() if scene != null else 0
	if sid != _scene_id:
		_scene_id = sid
		_warmup = WARMUP_FRAMES
		reset_stats()
	if _warmup > 0:
		_warmup -= 1
	elif _grace_s > 0.0:
		_grace_s -= frame_ms / 1000.0
	else:
		_record(frame_ms, new_compiles, scene)
		if adaptive and pacer.feed(frame_ms, _work_ms()):
			_apply()
	_flush_s += frame_ms / 1000.0
	if _flush_s >= FLUSH_EVERY_S:
		flush_log()

func _record(frame_ms: float, new_compiles: int, scene: Node) -> void:
	frame_ring[ring_head] = frame_ms
	ring_head = (ring_head + 1) % RING_SIZE
	ring_count = mini(ring_count + 1, RING_SIZE)
	compiles_in_play += new_compiles
	if frame_ms <= HITCH_MS:
		return
	hitches += 1
	worst_ms = maxf(worst_ms, frame_ms)
	if not measuring or _logged >= MAX_LOG_LINES:
		return
	var cam: Camera3D = get_viewport().get_camera_3d()
	var cp: Vector3 = cam.global_position if cam != null else Vector3.ZERO
	_pending.append("%.1f,%.1f,%d,%d,%.2f,%d,%d,%s,%.0f,%.0f" % [_session_s, frame_ms, Engine.max_fps, new_compiles,
		get_tree().root.scaling_3d_scale, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		scene.name if scene != null else "-", cp.x, cp.z])
	_logged += 1

## Longest of CPU and GPU work for the last frame, in ms (-1 when the renderer doesn't report it).
func _work_ms() -> float:
	var gpu: float = RenderingServer.viewport_get_measured_render_time_gpu(_vp_rid)
	var cpu: float = RenderingServer.viewport_get_measured_render_time_cpu(_vp_rid) \
		+ (Performance.get_monitor(Performance.TIME_PROCESS) + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0
	if gpu <= 0.0:
		return -1.0
	return maxf(cpu, gpu)

func _pipeline_compiles() -> int:
	var n: int = 0
	for m: int in PIPELINE_MONITORS:
		n += int(Performance.get_monitor(m))
	return n

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_APPLICATION_FOCUS_IN:
			_grace_s = GRACE_S
			_last_usec = 0
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_PREDELETE:
			flush_log()

func reset_stats() -> void:
	hitches = 0
	worst_ms = 0.0
	compiles_in_play = 0
	ring_head = 0
	ring_count = 0

# --- Summary -------------------------------------------------------------------------------

## Frame times (ms) of the last `n` recorded frames, oldest first.
func recent_frames(n: int) -> PackedFloat32Array:
	var k: int = mini(n, ring_count)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(k)
	for i: int in k:
		out[i] = frame_ring[(ring_head - k + i + RING_SIZE) % RING_SIZE]
	return out

## Average FPS, 1 % low FPS and worst frame over the last minute.
func summary() -> Dictionary:
	var f: PackedFloat32Array = recent_frames(RING_SIZE)
	if f.is_empty():
		return {"avg_fps": 0.0, "low1_fps": 0.0, "worst_ms": 0.0, "frames": 0}
	var total: float = 0.0
	for ms: float in f:
		total += ms
	var sorted: PackedFloat32Array = f.duplicate()
	sorted.sort()
	var p99: float = sorted[clampi(int(floor(float(sorted.size()) * 0.99)), 0, sorted.size() - 1)]
	return {"avg_fps": 1000.0 * float(f.size()) / maxf(total, 0.001), "low1_fps": 1000.0 / maxf(p99, 0.001),
		"worst_ms": sorted[sorted.size() - 1], "frames": f.size()}

func report_text() -> String:
	var s: Dictionary = summary()
	var scene: Node = get_tree().current_scene
	return "Namma Auto perf %s | %s | %s\nscene %s | cap %d FPS (mode %d, fallbacks %d) | 3D scale %.2f\nlast minute: avg %.1f FPS, 1%% low %.1f FPS, worst %.1f ms\nsince scene start: %d hitches > %.0f ms, worst %.1f ms, %d pipeline compiles in play\n%d draw calls, %d objects, RAM %.0f MB, VRAM %.0f MB" % [
		str(ProjectSettings.get_setting("application/config/version", "?")), OS.get_model_name(), RenderingServer.get_video_adapter_name(),
		scene.name if scene != null else "-", Engine.max_fps, pacer.mode, pacer.fallbacks, get_tree().root.scaling_3d_scale,
		float(s["avg_fps"]), float(s["low1_fps"]), float(s["worst_ms"]),
		hitches, HITCH_MS, worst_ms, compiles_in_play,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0]

# --- Hitch log -----------------------------------------------------------------------------

func _start_log() -> void:
	DirAccess.make_dir_recursive_absolute(LOG_DIR)
	var f: FileAccess = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if f != null:
		f.store_line(LOG_HEADER)
		f.close()

func flush_log() -> void:
	_flush_s = 0.0
	if _pending.is_empty() or not measuring:
		return
	var f: FileAccess = FileAccess.open(LOG_PATH, FileAccess.READ_WRITE)
	if f == null:
		_pending.clear()
		return
	f.seek_end()
	for line: String in _pending:
		f.store_line(line)
	f.close()
	_pending.clear()
