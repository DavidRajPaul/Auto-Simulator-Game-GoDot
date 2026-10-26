class_name ChennaiBackdrop
extends Control
## Flat, hand-drawn Chennai skyline at Marina sunset: sky gradient, sun, gopuram, Central
## station clock tower, LIC tower, palms, sea haze and a road strip with lane dashes.
## Drawn with a few polygons (no textures), shared by the main menu and the loading screen.

const SKY_TOP: Color = Color(0.16, 0.09, 0.24)
const SKY_MID: Color = Color(0.85, 0.36, 0.28)
const SKY_LOW: Color = Color(1.0, 0.72, 0.36)
const FAR: Color = Color(0.36, 0.16, 0.26)
const NEAR: Color = Color(0.13, 0.06, 0.13)
const ROAD: Color = Color(0.09, 0.08, 0.1)
const DASH: Color = Color(1.0, 0.8, 0.3, 0.85)

## 0..1 scroll offset of the road dashes (the loading screen animates it).
var road_scroll: float = 0.0
## Where the lane dashes sit inside the road strip (0 top … 1 bottom).
var dash_y: float = 0.45

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	get_viewport().size_changed.connect(_fit)
	_fit()

## Anchors don't resolve for a Control straight under a CanvasLayer here, so size it by hand.
func _fit() -> void:
	position = Vector2.ZERO
	size = get_viewport().get_visible_rect().size

func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	var horizon: float = h * 0.68
	# Sky: two stacked gradient quads.
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h * 0.45), Vector2(0, h * 0.45)]),
		PackedColorArray([SKY_TOP, SKY_TOP, SKY_MID, SKY_MID]))
	draw_polygon(PackedVector2Array([Vector2(0, h * 0.45), Vector2(w, h * 0.45), Vector2(w, horizon), Vector2(0, horizon)]),
		PackedColorArray([SKY_MID, SKY_MID, SKY_LOW, SKY_LOW]))
	# Sun sinking behind the city.
	var sun: Vector2 = Vector2(w * 0.62, horizon - h * 0.1)
	draw_circle(sun, h * 0.2, Color(1.0, 0.62, 0.3, 0.25))
	draw_circle(sun, h * 0.12, Color(1.0, 0.85, 0.55))
	# Far skyline blocks.
	var x: float = 0.0
	var i: int = 0
	while x < w:
		var bw: float = w * (0.04 + 0.03 * float((i * 37) % 5) / 4.0)
		var bh: float = h * (0.08 + 0.1 * float((i * 53) % 7) / 6.0)
		draw_rect(Rect2(x, horizon - bh, bw - 2.0, bh), FAR)
		x += bw
		i += 1
	# Landmarks in the near layer.
	_gopuram(Vector2(w * 0.16, horizon), h * 0.36, NEAR)
	_clock_tower(Vector2(w * 0.43, horizon), h * 0.33, NEAR)
	_tower(Vector2(w * 0.82, horizon), h * 0.3, NEAR)
	for px: float in [0.06, 0.3, 0.55, 0.71, 0.95]:
		_palm(Vector2(w * px, horizon), h * 0.2, NEAR)
	draw_rect(Rect2(0, horizon, w, h * 0.04), NEAR)
	# Road with scrolling centre dashes.
	var road_top: float = horizon + h * 0.04
	draw_rect(Rect2(0, road_top, w, h - road_top), ROAD)
	draw_rect(Rect2(0, road_top, w, 4.0), Color(1.0, 0.8, 0.3, 0.6))
	var dash_w: float = w * 0.06
	var gap: float = dash_w * 0.9
	var lane_y: float = road_top + (h - road_top) * dash_y
	var start: float = -fmod(road_scroll * (dash_w + gap) * 6.0, dash_w + gap)
	var dx: float = start
	while dx < w:
		draw_rect(Rect2(dx, lane_y, dash_w, 6.0), DASH)
		dx += dash_w + gap

## Temple tower: stacked, narrowing tiers with a kalasam on top.
func _gopuram(base: Vector2, height: float, c: Color) -> void:
	var tiers: int = 7
	var bw: float = height * 0.55
	var tier_h: float = height * 0.82 / float(tiers)
	for t: int in tiers:
		var w0: float = bw * (1.0 - float(t) / float(tiers) * 0.62)
		var w1: float = bw * (1.0 - float(t + 1) / float(tiers) * 0.62)
		var y0: float = base.y - tier_h * float(t)
		var y1: float = y0 - tier_h
		draw_colored_polygon(PackedVector2Array([Vector2(base.x - w0 * 0.5, y0), Vector2(base.x + w0 * 0.5, y0),
			Vector2(base.x + w1 * 0.5, y1 + 3.0), Vector2(base.x - w1 * 0.5, y1 + 3.0)]), c)
		draw_rect(Rect2(base.x - w1 * 0.55, y1, w1 * 1.1, 4.0), c)
	var top_y: float = base.y - tier_h * float(tiers)
	var cap: float = bw * 0.38
	draw_colored_polygon(PackedVector2Array([Vector2(base.x - cap * 0.5, top_y), Vector2(base.x + cap * 0.5, top_y),
		Vector2(base.x + cap * 0.3, top_y - height * 0.08), Vector2(base.x - cap * 0.3, top_y - height * 0.08)]), c)
	draw_rect(Rect2(base.x - 2.0, top_y - height * 0.16, 4.0, height * 0.08), c)

## Chennai Central style clock tower with a pointed roof.
func _clock_tower(base: Vector2, height: float, c: Color) -> void:
	var tw: float = height * 0.16
	draw_rect(Rect2(base.x - height * 0.42, base.y - height * 0.3, height * 0.84, height * 0.3), c)
	draw_rect(Rect2(base.x - tw * 0.5, base.y - height * 0.82, tw, height * 0.82), c)
	draw_colored_polygon(PackedVector2Array([Vector2(base.x - tw * 0.65, base.y - height * 0.82),
		Vector2(base.x + tw * 0.65, base.y - height * 0.82), Vector2(base.x, base.y - height)]), c)
	draw_circle(Vector2(base.x, base.y - height * 0.7), tw * 0.32, Color(1.0, 0.85, 0.55, 0.9))

## LIC-style office tower.
func _tower(base: Vector2, height: float, c: Color) -> void:
	var tw: float = height * 0.32
	draw_rect(Rect2(base.x - tw * 0.5, base.y - height, tw, height), c)
	draw_rect(Rect2(base.x - tw * 0.15, base.y - height * 1.12, tw * 0.3, height * 0.12), c)
	for r: int in 8:
		for col: int in 3:
			if (r * 3 + col) % 4 != 0:
				draw_rect(Rect2(base.x - tw * 0.38 + col * tw * 0.27, base.y - height * 0.95 + r * height * 0.11, tw * 0.16, height * 0.05),
					Color(1.0, 0.82, 0.45, 0.55))

func _palm(base: Vector2, height: float, c: Color) -> void:
	var top: Vector2 = base + Vector2(height * 0.08, -height)
	draw_line(base, top, c, maxf(3.0, height * 0.05), true)
	for k: int in 6:
		var a: float = deg_to_rad(-170.0 + k * 34.0)
		var tip: Vector2 = top + Vector2(cos(a), sin(a) * 0.5 + 0.35) * height * 0.42
		draw_line(top, tip, c, maxf(2.0, height * 0.035), true)
