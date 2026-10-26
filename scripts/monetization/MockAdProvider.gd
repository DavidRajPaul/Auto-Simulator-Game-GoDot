class_name MockAdProvider
extends AdProvider
## On-screen ad PLACEHOLDER used until real ad units are wired: a full-screen card that says
## "Ad placeholder", counts down, and (for rewarded) pays out at the end. Lets designers feel
## the exact frequency and flow on a phone before any SDK is integrated. Skippable rewarded
## ads forfeit the reward, like real networks. In headless tests it completes instantly.

var _layer: CanvasLayer
var _panel: ColorRect
var _label: Label
var _close: Button
var _remaining: float = 0.0
var _placement: String = ""
var _rewarded: bool = false
var instant: bool = false # tests
var _was_paused: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	instant = DisplayServer.get_name() == "headless"
	_layer = CanvasLayer.new()
	_layer.layer = 120
	_layer.visible = false
	add_child(_layer)
	_panel = ColorRect.new()
	_panel.color = Color(0.03, 0.03, 0.05, 0.94)
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_layer.add_child(_panel)
	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 30)
	_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	_panel.add_child(_label)
	_close = Button.new()
	_close.text = "  ✕  "
	_close.add_theme_font_size_override("font_size", 30)
	_close.anchor_left = 1.0
	_close.anchor_right = 1.0
	_close.offset_left = -110
	_close.offset_right = -24
	_close.offset_top = 24
	_close.offset_bottom = 90
	_close.pressed.connect(_finish.bind(false))
	_panel.add_child(_close)

func provider_name() -> String:
	return "mock"

func is_rewarded_ready() -> bool:
	return true

func is_interstitial_ready() -> bool:
	return true

func show_rewarded(placement: String) -> bool:
	return _show(placement, true, config.mock_rewarded_s if config != null else 3.0)

func show_interstitial(placement: String) -> bool:
	return _show(placement, false, config.mock_interstitial_s if config != null else 2.0)

func _show(placement: String, rewarded: bool, seconds: float) -> bool:
	if _layer.visible:
		return false
	_placement = placement
	_rewarded = rewarded
	if instant:
		_finish.call_deferred(true)
		return true
	_remaining = seconds
	_layer.visible = true
	_was_paused = get_tree().paused
	get_tree().paused = true
	_refresh()
	return true

func _process(delta: float) -> void:
	if not _layer.visible:
		return
	_remaining -= delta
	_refresh()
	if _remaining <= 0.0:
		_finish(true)

func _refresh() -> void:
	var kind: String = "REWARDED VIDEO" if _rewarded else "INTERSTITIAL"
	_label.text = "AD PLACEHOLDER\n%s · %s\n\n%d" % [kind, _placement, ceili(maxf(_remaining, 0.0))]

func _finish(watched: bool) -> void:
	var was_showing: bool = _layer.visible
	_layer.visible = false
	if was_showing:
		get_tree().paused = _was_paused
	if _rewarded:
		if watched:
			rewarded_earned.emit(_placement)
		else:
			rewarded_failed.emit(_placement, "skipped")
		rewarded_closed.emit(_placement)
	else:
		interstitial_closed.emit(_placement)
