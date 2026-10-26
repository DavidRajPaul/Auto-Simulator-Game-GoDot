class_name UIKit
extends RefCounted
## "Namma Auto Arcade" UI kit (Stitch design system, docs prompt pack 4A-5B).
## One place for every reusable piece, so all screens share the same fonts, styleboxes and
## textures (cached statics: built once, reused, cheap to draw):
##  * theme(): fonts + default Button / Panel / ProgressBar / Slider looks for a whole UI tree.
##  * button(): glossy arcade button (plum contour, extruded shelf, presses down 4 px).
##  * card() / ribbon() / chip() / stat_bar() / reward_icon() / badge_for_level() / portrait().
##  * Animations as light tweens: pulse, bob, pop_in, count_up, spin, flicker.

const PLUM: Color = Color("1c1520")
const DUSK: Color = Color("3b1f4f")
const SURFACE: Color = Color("241d28")
const SURFACE_HI: Color = Color("2f2733")
const JASMINE: Color = Color("fff6e3")
const YELLOW: Color = Color("ffc21a")
const GREEN: Color = Color("2fbf4f")
const RED: Color = Color("e8392e")
const ORANGE: Color = Color("ff7a3d")
const MUTED: Color = Color("d3c5ac")

enum Tone { YELLOW, GREEN, RED, ORANGE, PURPLE, DARK }
## face colour, extrusion shelf, text colour
const TONES: Array[Array] = [
	[Color("ffc21a"), Color("c48200"), Color("261a00")],
	[Color("2fbf4f"), Color("1b7c30"), Color("00210a")],
	[Color("e8392e"), Color("991d16"), Color("fff6e3")],
	[Color("ff7a3d"), Color("b84310"), Color("2a0d00")],
	[Color("3b1f4f"), Color("1e0f29"), Color("fff6e3")],
	[Color("2f2733"), Color("17111a"), Color("fff6e3")],
]

const REWARDS_ATLAS: String = "res://assets/ui/rewards.png"
const PORTRAITS_ATLAS: String = "res://assets/ui/portraits.png"
## tools/art/import_game_art.py REWARD_CELLS (256 px cells, 4 per row).
const REWARD_CELLS: Array[String] = ["coin", "coins", "coin_pile", "star", "star_half", "star_empty", "xp", "lpg",
	"tick", "gift", "lock", "badge_bronze", "badge_silver", "badge_gold", "badge_ruby", "badge_diamond"]
const BADGE_TIERS: Array[String] = ["badge_bronze", "badge_silver", "badge_gold", "badge_ruby", "badge_diamond"]
## Rider portraits (4G haggle = office-goer, 4F fare = cheerful regular).
const PORTRAIT_FOR: Dictionary = {"it_commuter": 0, "college_student": 0}

const SHELF_PX: int = 6
const PRESS_PX: int = 4

static var _theme: Theme
static var _title_font: Font
static var _body_font: Font
static var _rewards: Texture2D
static var _portraits: Texture2D
static var _cells: Dictionary = {}
static var _boxes: Dictionary = {}

# --- Fonts & theme -----------------------------------------------------------------

static func _font(path: String, weight: int) -> Font:
	var base: FontFile = load(path) as FontFile
	var v: FontVariation = FontVariation.new()
	v.base_font = base
	v.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	var tamil: Font = load("res://assets/fonts/NotoSansTamil-Regular.ttf") as Font
	if tamil != null:
		v.fallbacks = [tamil]
	return v

static func title_font() -> Font:
	if _title_font == null:
		_title_font = _font("res://assets/fonts/ui/BricolageGrotesque.ttf", 800)
	return _title_font

static func body_font() -> Font:
	if _body_font == null:
		_body_font = _font("res://assets/fonts/ui/Rubik.ttf", 600)
	return _body_font

## Theme for a whole UI tree: set it on the root Control of a CanvasLayer.
static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t: Theme = Theme.new()
	t.default_font = body_font()
	t.default_font_size = 20
	t.set_color("font_color", "Label", JASMINE)
	t.set_color("font_outline_color", "Label", PLUM)
	_style_button_into(t, "Button", Tone.DARK)
	t.set_font("font", "Button", title_font())
	t.set_font_size("font_size", "Button", 22)
	t.set_stylebox("panel", "PanelContainer", card_box(DUSK))
	t.set_stylebox("panel", "Panel", card_box(DUSK))
	t.set_stylebox("background", "ProgressBar", _bar_bg())
	t.set_stylebox("fill", "ProgressBar", _bar_fill(YELLOW))
	t.set_stylebox("slider", "HSlider", _bar_bg())
	t.set_stylebox("grabber_area", "HSlider", _bar_fill(YELLOW))
	t.set_stylebox("grabber_area_highlight", "HSlider", _bar_fill(YELLOW))
	_theme = t
	return t

static func _style_button_into(t: Theme, type: String, tone: Tone) -> void:
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		t.set_stylebox(state, type, button_box(tone, state))
	var c: Array = TONES[int(tone)]
	for k: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(k, type, c[2] as Color)
	t.set_color("font_disabled_color", type, (c[2] as Color).darkened(0.4))

# --- Styleboxes (cached) -------------------------------------------------------------

## Arcade button face: contour, shelf (shadow below), generous corners. Pressed = shelf gone,
## content pushed down 4 px, so the face reads as clicking into the dashboard.
static func button_box(tone: Tone, state: String = "normal") -> StyleBoxFlat:
	var key: String = "btn:%d:%s" % [int(tone), state]
	if _boxes.has(key):
		return _boxes[key] as StyleBoxFlat
	var c: Array = TONES[int(tone)]
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	var face: Color = c[0] as Color
	sb.bg_color = face.lightened(0.06) if state == "hover" else (face.darkened(0.05) if state == "pressed" else face)
	if state == "disabled":
		sb.bg_color = face.darkened(0.45)
	sb.border_color = PLUM
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(18)
	sb.content_margin_left = 22.0
	sb.content_margin_right = 22.0
	sb.content_margin_top = 10.0 + (PRESS_PX if state == "pressed" else 0.0)
	sb.content_margin_bottom = 12.0 - (PRESS_PX if state == "pressed" else 0.0)
	sb.shadow_color = c[1] as Color
	sb.shadow_size = 1
	sb.shadow_offset = Vector2(0, 1 if state == "pressed" else SHELF_PX)
	sb.anti_aliasing = true
	if state == "focus":
		sb.draw_center = false
		sb.border_color = JASMINE
		sb.set_border_width_all(3)
		sb.shadow_size = 0
	_boxes[key] = sb
	return sb

## Modal / card body: dusk purple, 4 px plum contour, a faint jasmine inner line.
static func card_box(bg: Color = DUSK, radius: int = 22) -> StyleBoxFlat:
	var key: String = "card:%s:%d" % [bg.to_html(), radius]
	if _boxes.has(key):
		return _boxes[key] as StyleBoxFlat
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = PLUM
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(18.0)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 10
	sb.shadow_offset = Vector2(0, 6)
	sb.anti_aliasing = true
	_boxes[key] = sb
	return sb

static func pill_box(bg: Color, border: Color = PLUM) -> StyleBoxFlat:
	var key: String = "pill:%s:%s" % [bg.to_html(), border.to_html()]
	if _boxes.has(key):
		return _boxes[key] as StyleBoxFlat
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(40)
	sb.content_margin_left = 14.0
	sb.content_margin_right = 16.0
	sb.content_margin_top = 4.0
	sb.content_margin_bottom = 4.0
	sb.anti_aliasing = true
	_boxes[key] = sb
	return sb

static func _bar_bg() -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color("120c16")
	sb.border_color = PLUM
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	return sb

static func _bar_fill(c: Color) -> StyleBoxFlat:
	var key: String = "fill:" + c.to_html()
	if _boxes.has(key):
		return _boxes[key] as StyleBoxFlat
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = c
	sb.border_color = c.lightened(0.35) # the specular rim along the top of the fill
	sb.border_width_top = 2
	sb.set_corner_radius_all(10)
	_boxes[key] = sb
	return sb

# --- Widgets ---------------------------------------------------------------------------

## Glossy arcade button. `icon` = a rewards-atlas cell drawn before the text.
static func button(text: String, tone: Tone, on_press: Callable, font_size: int = 24, icon: String = "") -> Button:
	var b: Button = Button.new()
	b.text = text
	b.add_theme_font_override("font", title_font())
	b.add_theme_font_size_override("font_size", font_size)
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(state, button_box(tone, state))
	var c: Array = TONES[int(tone)]
	for k: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(k, c[2] as Color)
	b.add_theme_color_override("font_disabled_color", (c[2] as Color).darkened(0.4))
	if icon != "":
		b.icon = reward_cell(icon)
		b.expand_icon = true
		b.add_theme_constant_override("icon_max_width", int(font_size * 1.5))
	b.custom_minimum_size = Vector2(0, maxf(64.0, font_size * 2.6))
	b.focus_mode = Control.FOCUS_NONE
	if on_press.is_valid():
		b.pressed.connect(on_press)
	b.add_child(_gloss())
	return b

## The pill-shaped specular reflection on the upper half of a button face.
static func _gloss() -> Panel:
	var g: Panel = Panel.new()
	g.name = "Gloss"
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb: StyleBoxFlat = _boxes.get("gloss") as StyleBoxFlat
	if sb == null:
		sb = StyleBoxFlat.new()
		sb.bg_color = Color(1, 1, 1, 0.2)
		sb.set_corner_radius_all(12)
		_boxes["gloss"] = sb
	g.add_theme_stylebox_override("panel", sb)
	g.anchor_left = 0.0
	g.anchor_right = 1.0
	g.anchor_top = 0.0
	g.anchor_bottom = 0.0
	g.offset_left = 10.0
	g.offset_right = -10.0
	g.offset_top = 6.0
	g.offset_bottom = 18.0
	return g

static func label(text: String, size: int, colour: Color = JASMINE, title: bool = false, outline: int = 0) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_font_override("font", title_font() if title else body_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	if outline > 0:
		l.add_theme_color_override("font_outline_color", PLUM)
		l.add_theme_constant_override("outline_size", outline)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## Card with a ribbon title that hangs over its top edge (orange by default).
static func card(title: String = "", ribbon_tone: Tone = Tone.ORANGE) -> PanelContainer:
	var p: PanelContainer = PanelContainer.new()
	p.add_theme_stylebox_override("panel", card_box(DUSK))
	if title != "":
		var r: PanelContainer = ribbon(title, ribbon_tone)
		r.name = "Ribbon"
		p.set_meta("ribbon", r)
	return p

## A notched title ribbon (place it with place_ribbon after the card is laid out).
static func ribbon(text: String, tone: Tone = Tone.ORANGE, size: int = 34) -> PanelContainer:
	var r: PanelContainer = PanelContainer.new()
	var c: Array = TONES[int(tone)]
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = c[0] as Color
	sb.border_color = PLUM
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 36.0
	sb.content_margin_right = 36.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 8.0
	sb.shadow_color = c[1] as Color
	sb.shadow_size = 1
	sb.shadow_offset = Vector2(0, 6)
	r.add_theme_stylebox_override("panel", sb)
	var l: Label = label(text.to_upper(), size, c[2] as Color, true)
	l.name = "Text"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	r.add_child(l)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

## Stat chip: dark pill with an oversized icon hanging over its left edge, e.g. wallet.
static func chip(icon: String, text: String, size: int = 22) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", -14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic: TextureRect = reward_icon(icon, size * 2.1)
	ic.z_index = 1
	row.add_child(ic)
	var pill: PanelContainer = PanelContainer.new()
	var sb: StyleBoxFlat = _boxes.get("chip") as StyleBoxFlat
	if sb == null:
		sb = (pill_box(PLUM.lerp(DUSK, 0.5), PLUM).duplicate()) as StyleBoxFlat
		sb.content_margin_left = 24.0 # room under the overhanging icon
		_boxes["chip"] = sb
	pill.add_theme_stylebox_override("panel", sb)
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l: Label = label(text, size, JASMINE, true)
	l.name = "Value"
	pill.add_child(l)
	row.add_child(pill)
	return row

static func chip_value(c: HBoxContainer) -> Label:
	return c.get_child(1).get_node("Value") as Label

## Labelled bar (garage stats, XP, odds): label · bar · value.
static func stat_bar(caption: String, value: float, colour: Color, width: float = 220.0) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if caption != "":
		var l: Label = label(caption, 16, MUTED)
		l.custom_minimum_size = Vector2(110, 0)
		row.add_child(l)
	row.add_child(bar(value, colour, width))
	return row

static func bar(value: float, colour: Color, width: float = 220.0, height: float = 16.0) -> ProgressBar:
	var pb: ProgressBar = ProgressBar.new()
	pb.max_value = 1.0
	pb.step = 0.001
	pb.value = clampf(value, 0.0, 1.0)
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(width, height)
	pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pb.add_theme_stylebox_override("background", _bar_bg())
	pb.add_theme_stylebox_override("fill", _bar_fill(colour))
	pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return pb

# --- Textures ------------------------------------------------------------------------------

static func reward_cell(cell: String) -> AtlasTexture:
	if _cells.has(cell):
		return _cells[cell] as AtlasTexture
	if _rewards == null:
		_rewards = load(REWARDS_ATLAS) as Texture2D
	var i: int = REWARD_CELLS.find(cell)
	var at: AtlasTexture = AtlasTexture.new()
	at.atlas = _rewards
	at.region = Rect2((i % 4) * 256, (i / 4) * 256, 256, 256)
	_cells[cell] = at
	return at

static func reward_icon(cell: String, side: float) -> TextureRect:
	var t: TextureRect = TextureRect.new()
	t.texture = reward_cell(cell)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = Vector2(side, side)
	t.size = Vector2(side, side)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t

## Bronze Lv 1-4, silver 5-8, gold 9-12, ruby 13-16, diamond 17-20.
static func badge_for_level(level: int) -> String:
	return BADGE_TIERS[clampi((level - 1) / 4, 0, BADGE_TIERS.size() - 1)]

static func portrait(archetype_id: String, side: float) -> TextureRect:
	if _portraits == null:
		_portraits = load(PORTRAITS_ATLAS) as Texture2D
	var key: String = "portrait:%d" % int(PORTRAIT_FOR.get(archetype_id, 1))
	var at: AtlasTexture = _cells.get(key) as AtlasTexture
	if at == null:
		at = AtlasTexture.new()
		at.atlas = _portraits
		at.region = Rect2(int(PORTRAIT_FOR.get(archetype_id, 1)) * 256, 0, 256, 256)
		_cells[key] = at
	var t: TextureRect = TextureRect.new()
	t.texture = at
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = Vector2(side, side)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t

static func set_portrait(t: TextureRect, archetype_id: String) -> void:
	var src: TextureRect = portrait(archetype_id, 1.0)
	t.texture = src.texture
	src.free()

## Full-screen 85 % plum dim behind modals.
static func backdrop() -> ColorRect:
	var c: ColorRect = ColorRect.new()
	c.color = Color(PLUM, 0.85)
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	return c

# --- Animations (tweens; nothing runs while hidden) ------------------------------------------

## Gentle "breathing" scale for the main call to action.
static func pulse(c: Control, amount: float = 0.04, seconds: float = 1.1) -> Tween:
	c.pivot_offset = c.size * 0.5
	var tw: Tween = c.create_tween().set_loops()
	tw.tween_property(c, "scale", Vector2.ONE * (1.0 + amount), seconds * 0.5).set_trans(Tween.TRANS_SINE)
	tw.tween_property(c, "scale", Vector2.ONE, seconds * 0.5).set_trans(Tween.TRANS_SINE)
	return tw

## Up-and-down hover (hero auto, gift, loading auto).
static func bob(c: CanvasItem, px: float = 6.0, seconds: float = 3.2) -> Tween:
	var start: Vector2 = c.get("position") as Vector2
	var tw: Tween = c.create_tween().set_loops()
	tw.tween_property(c, "position:y", start.y - px, seconds * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(c, "position:y", start.y, seconds * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return tw

## Spring in from small (stars, medallion, cards).
static func pop_in(c: Control, delay: float = 0.0, seconds: float = 0.35) -> Tween:
	c.pivot_offset = c.size * 0.5
	c.scale = Vector2.ONE * 0.2
	c.modulate.a = 0.0
	var tw: Tween = c.create_tween()
	tw.tween_interval(delay)
	tw.set_parallel(true)
	tw.tween_property(c, "scale", Vector2.ONE, seconds).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "modulate:a", 1.0, seconds * 0.6)
	return tw

## Rolling number (coins, fare total). `fmt` takes one %d.
static func count_up(l: Label, from: int, to: int, fmt: String = "%d", seconds: float = 0.9) -> Tween:
	var tw: Tween = l.create_tween()
	tw.tween_method(func(v: float) -> void: l.text = fmt % roundi(v), float(from), float(to), seconds).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	return tw

static func spin(c: CanvasItem, seconds_per_turn: float = 22.0) -> Tween:
	var tw: Tween = c.create_tween().set_loops()
	tw.tween_property(c, "rotation", TAU, seconds_per_turn).from(0.0)
	return tw

## Neon sign flicker for loading screens.
static func flicker(c: CanvasItem, seconds: float = 2.5) -> Tween:
	var tw: Tween = c.create_tween().set_loops()
	tw.tween_property(c, "modulate:a", 1.0, seconds * 0.7)
	tw.tween_property(c, "modulate:a", 0.55, 0.05)
	tw.tween_property(c, "modulate:a", 1.0, 0.05)
	tw.tween_property(c, "modulate:a", 0.7, 0.06)
	tw.tween_property(c, "modulate:a", 1.0, seconds * 0.2)
	return tw

static func inr(v: int) -> String:
	var s: String = str(absi(v))
	var out: String = ""
	# Indian grouping: last 3, then pairs (₹1,23,456).
	if s.length() > 3:
		out = "," + s.substr(s.length() - 3)
		s = s.substr(0, s.length() - 3)
		while s.length() > 2:
			out = "," + s.substr(s.length() - 2) + out
			s = s.substr(0, s.length() - 2)
	return ("-" if v < 0 else "") + s + out
