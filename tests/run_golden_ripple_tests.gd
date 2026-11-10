extends Node
## Golden ripple on the first-ride tutorial (scripts/ui/GoldenRipple.gd, wired in TutorialOverlay).
## Run: godot --headless --path . res://tests/run_golden_ripple_tests.tscn

var _passed: int = 0
var _failed: int = 0

func _ready() -> void:
	print("\n=== Namma Auto — Tutorial golden ripple tests ===")
	_run.call_deferred()

func _run() -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.position = Vector2(100, 80)
	panel.size = Vector2(300, 90)
	add_child(panel)
	var ripple: GoldenRipple = GoldenRipple.new()
	ripple.target = panel
	ripple.corner_radius = 16
	add_child(ripple)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("Ripple is mouse-transparent (never blocks driving)", ripple.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	_check("Ripple surrounds the panel by PAD on every side", ripple.position.is_equal_approx(panel.position - Vector2.ONE * GoldenRipple.PAD)
		and ripple.size.is_equal_approx(panel.size + Vector2.ONE * GoldenRipple.PAD * 2.0), "pos %s size %s" % [ripple.position, ripple.size])
	panel.size = Vector2(420, 120)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("Ripple follows the panel when it resizes", ripple.size.is_equal_approx(panel.size + Vector2.ONE * GoldenRipple.PAD * 2.0))
	panel.visible = false
	await get_tree().process_frame
	_check("Ripple hides with its panel", not ripple.visible)
	panel.visible = true
	await get_tree().process_frame
	_check("Ripple returns when the panel does", ripple.visible)
	_check("Ring reaches beyond the border, not inside it", GoldenRipple.REACH >= 12.0 and GoldenRipple.REACH <= 24.0)
	_check("Two rings are offset in time (no gap in the ripple)", GoldenRipple.RINGS == 2)
	var overlay: String = FileAccess.get_file_as_string("res://scripts/ui/TutorialOverlay.gd")
	_check("Coach strip and speech bubble both get a ripple", overlay.contains("_make_ripple(card, 30)") and overlay.contains("_make_ripple(bubble, 16)"))
	print("\n=== %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)

func _check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  PASS  " + name)
	else:
		_failed += 1
		print("  FAIL  " + name + ("" if detail == "" else "  (" + detail + ")"))
