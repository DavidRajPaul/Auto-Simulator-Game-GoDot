class_name DebugOverlay
extends CanvasLayer
## Top-left performance readout for on-device testing. Auto-hidden in release
## builds; tap the readout to cycle compact/full/hidden.
## Budgets (AGENTS.md Rule 5): 60 FPS, ≤ 150 draw calls, physics well under 16 ms.

const UPDATE_INTERVAL_S: float = 0.25
const DRAW_CALL_BUDGET: int = 150

var _label: Label
var _timer: float = 0.0
var _mode: int = 1 # 0 hidden, 1 compact, 2 full
var _worst_fps: float = 999.0

func _ready() -> void:
	layer = 20
	if not OS.is_debug_build():
		queue_free()
		return
	_label = Label.new()
	_label.position = Vector2(12.0, 8.0)
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 5)
	_label.mouse_filter = Control.MOUSE_FILTER_STOP
	_label.gui_input.connect(_on_label_input)
	add_child(_label)

func _process(delta: float) -> void:
	_timer += delta
	if _timer < UPDATE_INTERVAL_S:
		return
	_timer = 0.0
	var fps: float = Performance.get_monitor(Performance.TIME_FPS)
	if Engine.get_process_frames() > 180: # ignore loading frames
		_worst_fps = minf(_worst_fps, fps)
	var draws: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var phys_ms: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var mem_mb: float = Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	var vram_mb: float = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	var ok: bool = fps >= 55.0 and draws <= DRAW_CALL_BUDGET
	_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5) if ok else Color(1.0, 0.45, 0.35))
	match _mode:
		0:
			_label.text = "·"
		1:
			_label.text = "%d FPS  %d draws" % [roundi(fps), draws]
		_:
			_label.text = "%d FPS (worst %d)\n%d / %d draw calls\nphysics %.1f ms\nRAM %.0f MB  VRAM %.0f MB\n%s" % [
				roundi(fps), roundi(_worst_fps), draws, DRAW_CALL_BUDGET, phys_ms, mem_mb, vram_mb,
				RenderingServer.get_video_adapter_name()]

func _on_label_input(event: InputEvent) -> void:
	var tapped: bool = (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed) \
		or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed)
	if tapped:
		_mode = (_mode + 1) % 3
		_worst_fps = 999.0
