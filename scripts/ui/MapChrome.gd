class_name MapChrome
extends RefCounted
## Game-style pieces for the full map, painted straight onto the map's own canvas.
##
## They use the same arcade faces, shelves and card boxes as the rest of the game (UIKit), so the
## map reads as a screen of the same game rather than a utility app. Every box is a cached
## StyleBox drawn with one call, and no nodes are added, so the map's draw-call count stays flat
## however many buttons or tokens it shows.

const PLUM: Color = Color("1c1520")
const DUSK: Color = Color("3b1f4f")
const DARK_PANEL: Color = Color("1f1828")
const INK: Color = Color("261a00")
const JASMINE: Color = Color("fff6e3")
const MARIGOLD: Color = Color("ffc21a")
const GREEN: Color = Color("2fbf4f")
const RED: Color = Color("e8392e")
const ORANGE: Color = Color("ff7a3d")
const PRESS_PX: float = 4.0

static var _boxes: Dictionary = {}

## One cached flat box: fill, contour and corner radius.
static func box(fill: Color, border: Color, radius: int, width: int) -> StyleBoxFlat:
	var key: String = "%s|%s|%d|%d" % [fill.to_html(), border.to_html(), radius, width]
	if _boxes.has(key):
		return _boxes[key] as StyleBoxFlat
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(radius)
	sb.anti_aliasing = true
	_boxes[key] = sb
	return sb

## A notice-board panel: dusk body, marigold contour.
static func panel(c: CanvasItem, rect: Rect2) -> void:
	c.draw_style_box(box(Color(DUSK, 0.97), PLUM, 20, 4), rect)
	c.draw_style_box(box(Color(0, 0, 0, 0), MARIGOLD, 16, 2), rect.grow(-6.0))

## A marigold title tab that sits on a panel's top edge.
static func ribbon(c: CanvasItem, rect: Rect2, text: String, font: Font, size: int = 20) -> void:
	c.draw_style_box(box(MARIGOLD, PLUM, 14, 4), rect)
	c.draw_string(font, rect.position + Vector2(0.0, rect.size.y * 0.5 + size * 0.36), text,
			HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, size, INK)

## A one-line hint on a dusk board, used for toasts and mode prompts.
static func banner(c: CanvasItem, rect: Rect2, text: String, font: Font, size: int = 18) -> void:
	c.draw_style_box(box(Color(DUSK, 0.97), MARIGOLD, 14, 3), rect)
	c.draw_string(font, rect.position + Vector2(0.0, rect.size.y * 0.5 + size * 0.36), text,
			HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, size, JASMINE)

## An arcade button in one of the game's tones. Pressed = the shelf sinks and the label drops,
## which is how a selected mode (Drop Pin) shows it is on.
static func button(c: CanvasItem, rect: Rect2, text: String, tone: UIKit.Tone, font: Font,
		pressed: bool = false, size: int = 22) -> void:
	c.draw_style_box(UIKit.button_box(tone, "pressed" if pressed else "normal"), rect)
	var dy: float = PRESS_PX if pressed else 0.0
	var ink: Color = UIKit.TONES[int(tone)][2] as Color
	c.draw_string(font, rect.position + Vector2(0.0, rect.size.y * 0.5 + size * 0.36 + dy), text,
			HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, size, ink)

## A round game token (quest, passenger, flag) with a plum shelf-and-ring disc under it. Three draw
## calls, no textures. A selected token sinks onto its shelf, like a pressed button.
static func token(c: CanvasItem, point: Vector2, radius: float, tone: UIKit.Tone, label: String,
		font: Font, selected: bool = false) -> void:
	var colours: Array = UIKit.TONES[int(tone)]
	var lift: float = 1.0 if selected else 4.0
	# One plum disc under the face is both the contour and the shelf: two filled circles, no arc.
	c.draw_circle(point + Vector2(0.0, 4.0), radius + 2.5, PLUM)
	var face: Color = (colours[0] as Color).lightened(0.15) if selected else colours[0] as Color
	c.draw_circle(point + Vector2(0.0, lift), radius, face)
	if label != "":
		var fs: int = int(radius * 1.05)
		c.draw_string(font, point + Vector2(-radius, lift + fs * 0.36), label,
				HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, fs, colours[2] as Color)

## A small status pill with a label, used on quest rows and the quest card.
static func pill(c: CanvasItem, rect: Rect2, text: String, fill: Color, font: Font, size: int = 14) -> void:
	c.draw_style_box(box(fill, PLUM, 10, 2), rect)
	c.draw_string(font, rect.position + Vector2(0.0, rect.size.y * 0.5 + size * 0.36), text,
			HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, size, PLUM)
