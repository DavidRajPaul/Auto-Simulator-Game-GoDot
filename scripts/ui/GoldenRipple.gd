class_name GoldenRipple
extends Control
## A soft golden ripple that rolls outward from the border of a tutorial panel, so the first-ride
## coach strip and speech bubble catch the eye without covering anything. Two rings are offset in
## time, so there is always one travelling out. Drawn by hand (no textures, no tweens), outline
## only, mouse-transparent. It follows `target` every frame, so it stays put as the bubble resizes.

## Panel this ripple surrounds (the coach strip or the speech bubble).
var target: Control
## Corner radius of the panel, so the ring follows its rounded corners.
var corner_radius: int = 16
## Seconds for one ring to travel from the border to full size.
const PERIOD: float = 1.8
## How far (px) the outermost ring reaches beyond the panel border.
const REACH: float = 20.0
const LINE: int = 4
const PAD: float = REACH + 2.0
const GOLD: Color = Color(1.0, 0.84, 0.32)
const RINGS: int = 2

var _box: StyleBoxFlat

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box = StyleBoxFlat.new()
	_box.draw_center = false
	_box.border_color = GOLD
	_box.set_border_width_all(LINE)
	_box.anti_aliasing = true
	_box.set_corner_radius_all(corner_radius)

func _process(_delta: float) -> void:
	if target == null:
		return
	visible = target.is_visible_in_tree()
	if not visible:
		return
	position = target.position - Vector2.ONE * PAD
	size = target.size + Vector2.ONE * PAD * 2.0
	queue_redraw()

func _draw() -> void:
	if target == null or not target.is_visible_in_tree():
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	var base: Rect2 = Rect2(Vector2.ONE * PAD, target.size)
	for i: int in RINGS:
		var t: float = fposmod(now / PERIOD + float(i) / float(RINGS), 1.0)
		var grow: float = lerpf(0.0, REACH, t)
		_box.border_color = Color(GOLD.r, GOLD.g, GOLD.b, pow(1.0 - t, 0.6))
		_box.set_corner_radius_all(corner_radius + int(grow * 0.5))
		draw_style_box(_box, base.grow(grow))
