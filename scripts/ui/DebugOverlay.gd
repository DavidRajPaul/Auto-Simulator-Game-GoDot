class_name DebugOverlay
extends CanvasLayer
## Performance readout for on-device testing (numbers come from the FrameGuard autoload).
## * Debug builds: on by default (compact). Release / closed-test builds: off until a
##   FOUR-finger tap anywhere (also toggles it off again; remembered in settings "perf_overlay").
## * Tap the readout: compact → full (frame-time graph, 1 % low, hitches, pipeline compiles) → dot.
## * Long-press the readout (0.8 s): copies FrameGuard.report_text() to the clipboard, so a
##   tester can paste the numbers straight into a bug report from the phone.
## Budgets (AGENTS.md Rule 5): 60 FPS, ≤ 150 draw calls. Costs ~3 2D draw calls when shown.

const UPDATE_INTERVAL_S: float = 0.25
const DRAW_CALL_BUDGET: int = 150
const GRAPH_FRAMES: int = 120
const GRAPH_SIZE: Vector2 = Vector2(240.0, 60.0)
const GRAPH_MAX_MS: float = 50.0
const LONG_PRESS_S: float = 0.8

var _label: Label
var _graph: Control
var _timer: float = 0.0
var _mode: int = 1 # 0 dot, 1 compact, 2 full
var _press_s: float = -1.0
var _copied_s: float = 0.0

func _ready() -> void:
	layer = 20
	visible = OS.is_debug_build() or bool(GameState.settings.get("perf_overlay", false))
	_label = Label.new()
	_label.position = Vector2(16.0, 214.0) # below the mini-map
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 5)
	_label.mouse_filter = Control.MOUSE_FILTER_STOP
	_label.gui_input.connect(_on_label_input)
	_graph = Control.new()
	_graph.custom_minimum_size = GRAPH_SIZE
	_graph.size = GRAPH_SIZE
	_graph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_graph.visible = false
	_graph.draw.connect(_draw_graph)
	add_child(_graph)
	add_child(_label)

func _input(event: InputEvent) -> void:
	# Four fingers down at once toggles the overlay (any build), without blocking the touch.
	if event is InputEventScreenTouch:
		var t: InputEventScreenTouch = event as InputEventScreenTouch
		if t.pressed and t.index == 3:
			visible = not visible
			GameState.set_setting("perf_overlay", visible)

func _process(delta: float) -> void:
	if not visible:
		return
	if _press_s >= 0.0:
		_press_s += delta
		if _press_s >= LONG_PRESS_S:
			_press_s = -1.0
			DisplayServer.clipboard_set(FrameGuard.report_text())
			_copied_s = 1.5
	_copied_s = maxf(_copied_s - delta, 0.0)
	_timer += delta
	if _timer < UPDATE_INTERVAL_S:
		return
	_timer = 0.0
	var fps: float = Performance.get_monitor(Performance.TIME_FPS)
	var draws: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var ok: bool = fps >= float(Engine.max_fps) * 0.92 and draws <= DRAW_CALL_BUDGET and FrameGuard.compiles_in_play == 0
	_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5) if ok else Color(1.0, 0.45, 0.35))
	_graph.visible = _mode == 2
	if _copied_s > 0.0:
		_label.text = "Perf report copied"
		return
	match _mode:
		0:
			_label.text = "·"
		1:
			_label.text = "%d FPS  %d draws  %d hitches" % [roundi(fps), draws, FrameGuard.hitches]
		_:
			var s: Dictionary = FrameGuard.summary()
			var phys_ms: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
			var proc_ms: float = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
			_label.text = "%d FPS (cap %d, 1%% low %d)\nhitches %d, worst %.0f ms\npipeline compiles %d\n%d / %d draw calls\nprocess %.1f ms  physics %.1f ms\n3D scale %.2f\nRAM %.0f MB  VRAM %.0f MB\nhold to copy report" % [
				roundi(fps), Engine.max_fps, roundi(float(s["low1_fps"])), FrameGuard.hitches, FrameGuard.worst_ms,
				FrameGuard.compiles_in_play, draws, DRAW_CALL_BUDGET, proc_ms, phys_ms, get_tree().root.scaling_3d_scale,
				Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
				Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0]
			_graph.position = _label.position + Vector2(0.0, _label.size.y + 6.0)
			_graph.queue_redraw()

## Last GRAPH_FRAMES frame times as bars; the green line is the frame-rate cap's interval.
func _draw_graph() -> void:
	_graph.draw_rect(Rect2(Vector2.ZERO, GRAPH_SIZE), Color(0.0, 0.0, 0.0, 0.55))
	var frames: PackedFloat32Array = FrameGuard.recent_frames(GRAPH_FRAMES)
	var w: float = GRAPH_SIZE.x / float(GRAPH_FRAMES)
	var target_ms: float = 1000.0 / float(maxi(Engine.max_fps, 1))
	for i: int in frames.size():
		var ms: float = frames[i]
		var h: float = clampf(ms / GRAPH_MAX_MS, 0.0, 1.0) * GRAPH_SIZE.y
		var c: Color = Color(0.45, 0.9, 0.5) if ms <= target_ms * 1.4 else (Color(1.0, 0.8, 0.3) if ms <= FrameGuard.HITCH_MS else Color(1.0, 0.35, 0.3))
		_graph.draw_rect(Rect2(float(i) * w, GRAPH_SIZE.y - h, maxf(w - 0.5, 1.0), h), c)
	var ty: float = GRAPH_SIZE.y - target_ms / GRAPH_MAX_MS * GRAPH_SIZE.y
	_graph.draw_line(Vector2(0.0, ty), Vector2(GRAPH_SIZE.x, ty), Color(0.6, 1.0, 0.6, 0.8), 1.0)

func _on_label_input(event: InputEvent) -> void:
	# Phones send each touch twice (touch + emulated mouse): count only the touch there.
	if event is InputEventMouseButton and DisplayServer.is_touchscreen_available():
		return
	var down: bool = (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed) \
		or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed)
	var up: bool = (event is InputEventScreenTouch and not (event as InputEventScreenTouch).pressed) \
		or (event is InputEventMouseButton and not (event as InputEventMouseButton).pressed)
	if down:
		_press_s = 0.0
	elif up and _press_s >= 0.0:
		_press_s = -1.0
		_mode = (_mode + 1) % 3
		_timer = UPDATE_INTERVAL_S
